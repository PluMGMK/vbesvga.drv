
;
;	FILE:	mtrr.asm
;	DATE:	24 November 2024
;	AUTHOR: PluMGMK
;
;	This module contains code and data to manipulate MTRRs (Memory Type
;	Range Registers) in Pentium Pro and later processors, to enable
;	write-combining on the VESA framebuffer and so reduce the double-buf
;	frame budget.
;

USING_ANCIENT_MASM	equ 1	;roll our own definitions for CPUID/RDMSR/WRMSR

; incDevice = 1			;Include control for gdidefs.inc

	.xlist
	include CMACROS.INC
	include MACROS.MAC
	include GDIDEFS.INC
	include int3.inc
	include windefs.inc
	include	display.inc
	.list

externA	__WinFlags

sBegin	Data

; Entry points set in EGAINIT.ASM
externD	Ring3to0
externD	Ring0to3

; MTRR base indices that need changing (store only lower byte of each)
mtrrs	db 80h dup (?)
; Number of stored MTRR base indices (up to 128)
n_mtrrs	db 0

sEnd	Data


sBegin	Code
	assumes cs,Code
	; NOTE: even though these are all init-time functions, we need to
	; put them in the main Code (_TEXT) segment so that they can use
	; the Ring3to0 entry point!

externD		VESALinearBuf		; in VESAFNS.ASM
externW		_cstods			; in CURSOR.ASM

;--------------------------------------------------------------------------;
; find_mtrrs
;	initializes our MTRR handling (by establishing that we can get into
;	Ring0 and that MTRRs are supported) and then goes searching for any
;	MTRR specs that render the framebuffer "uncacheable".
; Entry:
;	DS	= Data
;	BX:CX	= PHYSICAL address of the linear framebuffer
;	SI:DI	= size of the linear framebuffer
; Returns:
;	mtrrs and n_mtrrs populated
; Error Returns:
;	n_mtrrs zero
; Registers Destroyed:
;	FLAGS
; Registers Preserved:
;	AX,BX,CX,DX,SI,DI,DS,ES,BP
; Calls:
;	Ring3to0
;	Ring0to3
; History:
;	see Git
;--------------------------------------------------------------------------;
public	find_mtrrs
find_mtrrs	proc far
	assumes	ds,Data

	; first of all, can we get to Ring0?
	cmp	[Ring3to0.sel],0
	jnz	@F
	; nope, no point in trying anything then
	ret

@@:	; right, we can get to Ring0, which means we're in 386 mode, so we
	; can use 386 instructions and registers!
	.386
	movzx	esp,sp
	pushad
	; the newest CPU that Windows 3.1 knows about is a 486, so as far
	; as it's concerned, if we have MTRRs available, we're on that CPU:
        mov     ax,__WinFlags
        test    ax,WF_CPU486
	jz	mtrrs_found		; we're on a 386 --> no MTRRs

	; check for CPUID
	push	bp
	pushfd
	pushfd
	mov	bp,sp
	xor	dword ptr [bp],200000h	; flip ID bit of EFLAGS
	popfd
	pushfd
	pop	eax
	mov	bp,sp
	xor	eax,[bp]		; check if the flip stuck
	popfd				; restore original EFLAGS
	pop	bp

	test	eax,eax			; did the ID bit flip?
	jz	mtrrs_found		; nope --> on a 486, no MTRRs

	; get our 32-bit args into single registers
	push	bx
	push	cx
	push	si
	push	di
	pop	edi			; EDI := framebuffer size
	pop	esi			; ESI := framebuffer physical address
	add	edi,esi			; EDI := end of framebuffer

if	USING_ANCIENT_MASM
	cpuid	macro
	db	0Fh,0A2h
	endm
else
	.586
endif
	mov	eax,1			; CPUID_GETFEATURES
	cpuid
	; check for MTRR support in EDX
	bt	edx,12
	jnc	mtrrs_found		; MTRRs not supported

	; head into Ring0 to find out what's cooking with the MTRRs...
	call	Ring3to0		; preserves ds, es, ecx, esi, edi, ebp
if	USING_ANCIENT_MASM
	rdmsr	macro
	db	0Fh,032h
	endm
	wrmsr	macro
	db	0Fh,030h
	endm
else
	.586p
endif
	mov	ecx,0FEh		; IA32_MTRRCAP
	rdmsr

	; check for write-combining
	bt	eax,10
	jnc	back_to_ring3
	; get the total number of variable-range MTRRs
	and	eax,7Fh
	jz	back_to_ring3		; no variable-range MTRRs --> no good

	; point ECX just beyond the last MTRR mask register
	mov	ecx,eax
	shl	cl,1
	mov	ch,2			; now ECX = 0x200 + (n*2)

mtrr_check_loop:
	dec	cl			; move onto mask register
	rdmsr				; read it
	btr	eax,11			; "valid" bit
	dec	cl			; move onto base register (preserves CF)
	jnbe	mtrr_check_loop		; not valid and CL NOT zero --> move on
	jnc	back_to_ring3		; not valid and CL zero --> we're done
	mov	ebx,eax			; hold onto bits 31:12 of the mask

	rdmsr				; read the base register
	test	edx,edx			; make sure it's 32 bits or less
	jnz	next_mtrr		; >32-bit --> we can't handle it

	; is this an uncacheable MTR? If so, AL will be exactly zero
	test	al,al
	jnz	next_mtrr

	; now we know it's uncacheable, and that EAX is exactly == the base
	; check if the base is within the framebuffer
	cmp	eax,esi
	jnb	@F

	; base is not within the framebuffer, but maybe the framebuffer base is
	; within the range of this MTRR?
	and	eax,ebx			; EAX := MaskBase
	mov	edx,esi
	and	edx,ebx			; EDX := MaskTarget
	cmp	eax,edx
	je	have_relevant_mtrr	; MaskBase == MaskTarget --> in range!
	jmp	next_mtrr		; Nope, check the next one

@@:	cmp	eax,edi
	ja	next_mtrr		; if it's beyond the end, we don't care

have_relevant_mtrr:
	movzx	bx,[n_mtrrs]
	mov	mtrrs[bx],cl		; store index of current base reg
	inc	bl
	mov	[n_mtrrs],bl		; increment MTRR counter
next_mtrr:
	test	cl,cl
	jnz	mtrr_check_loop

back_to_ring3:
	call	Ring0to3		; preserves ds, es, ecx, esi, edi, ebp
mtrrs_found:
	.386
	popad
	ret
find_mtrrs	endp

;--------------------------------------------------------------------------;
; enable_wrcomb
;	enables write-combining on all Memory Type Ranges identified by
;	find_mtrrs above.
; Entry:
;	DS	= Data
;	BL	= desired mode (0=uncacheable, 1=write-combine, 4=write-through)
;	running on a 386
;	mtrrs and n_mtrrs populated
; Returns:
;	VESA linear framebuffer MTR type updated
; Error Returns:
;	linear framebuffer MTR unchanged
; Registers Destroyed:
;	FLAGS
; Registers Preserved:
;	AX,BX,CX,DX,SI,DI,DS,ES,BP
; Calls:
;	Ring3to0
;	Ring0to3
; History:
;	see Git
;--------------------------------------------------------------------------;
set_mtrr_types	proc near
	pushad
	movzx	cx,[n_mtrrs]
	jcxz	wrcomb_enabled

	mov	di,bx			; stash our argument
	call	Ring3to0		; preserves ds, es, ecx, esi, edi, ebp
ife	USING_ANCIENT_MASM
	.586p
endif
	mov	bx,di			; get back our argument

@@:	mov	di,cx
	movzx	ecx,mtrrs[di-1]
	mov	ch,2			; ECX points at MTRR base register
	rdmsr
	mov	al,bl
	wrmsr
	mov	cx,di
	loop	@B
	call	Ring0to3		; preserves ds, es, ecx, esi, edi, ebp

wrcomb_enabled:
	.386
	popad
	ret
set_mtrr_types	endp

;--------------------------------------------------------------------------;
; enable_wrcomb
;	enables write-combining on all Memory Type Ranges identified by
;	find_mtrrs above.
; Entry:
;	DS	= Data
;	running on a 386 (guaranteed since this only runs if DBLBUF has
;	been setup successfully)
;	mtrrs and n_mtrrs populated
; Returns:
;	write-combining enabled for the VESA linear framebuffer
; Error Returns:
;	linear framebuffer MTR unchanged
; Registers Destroyed:
;	FLAGS
; Registers Preserved:
;	AX,BX,CX,DX,SI,DI,DS,ES,BP
; Calls:
;	set_mtrr_types
; History:
;	see Git
;--------------------------------------------------------------------------;
public	enable_wrcomb
enable_wrcomb	proc far
	push	bx
	mov	bl,1	; write combining
	call	set_mtrr_types
	pop	bx
	ret
enable_wrcomb	endp

;--------------------------------------------------------------------------;
; enable_wrthru
;	enables write-through on all Memory Type Ranges identified by
;	find_mtrrs above.
; Entry:
;	DS	= Data
;	running on a 386 (guaranteed since this only runs if DBLBUF has
;	been setup successfully)
;	mtrrs and n_mtrrs populated
; Returns:
;	write-through enabled for the VESA linear framebuffer
; Error Returns:
;	linear framebuffer MTR unchanged
; Registers Destroyed:
;	FLAGS
; Registers Preserved:
;	AX,BX,CX,DX,SI,DI,DS,ES,BP
; Calls:
;	set_mtrr_types
; History:
;	see Git
;--------------------------------------------------------------------------;
public	enable_wrthru
enable_wrthru	proc far
	push	bx
	mov	bl,4			; write-through
	call	set_mtrr_types
	pop	bx
	ret
enable_wrthru	endp

;--------------------------------------------------------------------------;
; disable_wrcomb
;	disables write-combining / write-through on all Memory Type Ranges
;	identified by find_mtrrs above.
; Entry:
;	DS	= Data
;	mtrrs and n_mtrrs populated
; Returns:
;	VESA linear framebuffer back to uncacheable
; Error Returns:
;	linear framebuffer MTR unchanged
; Registers Destroyed:
;	FLAGS
; Registers Preserved:
;	AX,BX,CX,DX,SI,DI,DS,ES,BP
; Calls:
;	set_mtrr_types
; History:
;	see Git
;--------------------------------------------------------------------------;
public	disable_wrcomb
disable_wrcomb	proc far
	.286	; this is called unconditionally by stop_double_buf
	cmp	[n_mtrrs],0
	jz	@F

	push	bx
	xor	bl,bl			; uncacheable
	call	set_mtrr_types
	pop	bx
@@:	ret
disable_wrcomb	endp

sEnd	Code

END
