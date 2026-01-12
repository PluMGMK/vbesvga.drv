
;
;	FILE:	bankswr0.asm
;	DATE:	11 January 2026
;	AUTHOR: PluMGMK
;
;	This module contains code and data to support Bank Switching in
;	Ring0. This should allow the use of DCI when using banked modes
;	in 386 Enhanced Mode, although this first-pass implementation
;	probably won't have stellar performance!
;

GET_VIDEO_SEL   equ     1       ;function # to call to get selector

	.xlist
	include CMACROS.INC
	include MACROS.MAC
	.list

	externFP GetSelectorBase

sBegin	Data

externD	MemSize		;in VESAFNS.ASM
externW	LinBufSel	;in DBLBUF.ASM
externB	bank_granfac_m1	; in BANK.INC
externB	bank_select_byte; in BANK.INC
; Entry points set in EGAINIT.ASM
externD	Ring3to0
externD	Ring0to3

public	VFlatDEntry
VFlatDEntry	dd ?	; entry point to Virtual Flat-Framebuffer Device

sEnd	Data


sBegin	Code
	assumes cs,Code

externW		_cstods			; in CURSOR.ASM
externD		VESABankSwitch		; in VESAFNS.ASM

; this is a hybrid function that does all the initialization to ensure
; that the Ring0 functions further down can run properly.
; Entry: 16-bit Ring3, DS = Data, ES = Code (writable)
; Return: CF clear, bswsel:bswoff and r0_ss16 populated
; Error return: CF set
setup_ring0_template	proc far
	assumes	ds,Data
	assumes	es,Code

	.286
	; first, we need to get the full linear address of the 32-bit
	; code we're about to run...
	cCall	GetSelectorBase,<cs>
	add	ax,offset setup_ring0_32bit
	adc	dx,0
	mov	es:[setup_ring0_32bit_off.lo],ax
	mov	es:[setup_ring0_32bit_off.hi],dx

	; ready to rough it in Ring0!
	call	[Ring3to0]
	.386p
	; at this point, ES is still our writable Ring3 code selector,
	; and CS is a Ring0 executable alias!
	mov	es:[r0_cs_1],cs		; record the alias...
	mov	es:[r0_cs_2],cs		; record the alias...

	; To call the BIOS's Protected-Mode bank-switch code from Ring0,
	; we need a couple of other things:
	;  1. a Ring0 code selector for the BIOS code
	;  2. a page of memory to use as the stack
	;  3. a Ring0 16-bit stack selector to point at that page
	; To get these we need to do some `VMMcall`s. But to do those,
	; we need to be in the 32-bit flat selector - so find that
	; selector and call some 32-bit code in it...

	; we're currently on a 32-bit stack, so we can use ESP like so:
	sub	esp,6
	sidt	fword ptr [esp]
	pop	ax
	pop	ecx

	; EBX now points at the base of the IDT in linear memory, and
	; SS is a flat 32-bit selector, so we can inspect it easily.
	; Look at the int 20h vector, which is used for `VMMcall`s.
	; Such calls in 32-bit flat code are converted into near calls,
	; meaning `int 20h` must always live in the 32-bit flat code
	; selector. The selector is at offset 2 within the descriptor.
	mov	ax,ss:[ecx+20h*8+2]
	mov	es:[flat_csel],ax
	jmp	short $+2	; clear prefetch queue

	; `VMMcall`s need DS to point to 32-bit flat selector too...
	push	ds
	mov	ax,ss
	mov	ds,ax
	push	es		; and some will trash ES!

	; get the pointer to the BIOS code
	mov	ax,es:[VESABankSwitch.off]
	mov	es:[bswoff],ax
	mov	ax,es:[VESABankSwitch.sel]
	mov	edi,offset bswsel

	db	66h,0EAh	; 32-bit FAR JMP
setup_ring0_32bit_off	label dword
	dd	?		; becomes LINEAR address of following label
flat_csel		label word
	dw	?		; becomes selector for flat 32-bit Ring0 code

setup_ring0_32bit:
	; *** THIS CODE RUNS IN 32-BIT MODE, SO BE CAREFUL! ***

	; First step: get the descriptor of the BIOS code segment

	mov	si,sp		; really ESI,ESP
	; push stack parameters right-to-left
	xor	cx,cx		; really ECX
	push	cx		; really ECX => flags = 0
	push	bx		; really EBX = VM (since we called Ring0to3)
	push	ax		; really EAX = selector

	int	20h		; VxDcall
	dw	123		; _GetDescriptor
	dw	1		; VMM

	; Second step: make a Ring0 alias to it and save it

	mov	sp,si		; really ESP,ESI
	; push stack parameters right-to-left
	push	cx		; really ECX => flags = 0
	and	dh,10011111b	; make DPL = 0 in access byte
	push	ax		; really EAX = DescDWORD2
	push	dx		; really EDX = DescDWORD1

	int	20h		; VxDcall
	dw	118		; _Allocate_GDT_Selector
	dw	1		; VMM

	mov	sp,si		; really ESP,ESI
	stosd	; really STOSW!	; store AX (selector) @ ES:EDI == bswsel

	; Third step: allocate a fixed page of memory for a 16-bit stack

	; push stack parameters right-to-left
	mov	cl,00001000b	; PageFixed
	push	cx		; really ECX => flags = PageFixed
	xor	cl,cl
	push	cx		; really ECX => PhysAddr = NULL
	push	cx		; really ECX => maxPhys = NULL
	push	cx		; really ECX => minPhys = NULL
	push	cx		; really ECX => AlignMask = NULL
	push	cx		; really ECX => VM = NULL
	mov	cl,1		; PG_SYS
	push	cx		; really ECX => pType = PG_SYS
	push	cx		; really ECX => nPages = 1

	int	20h		; VxDcall
	dw	83		; _PageAllocate
	dw	1		; VMM
	assumes	es,nothing	; above call trashes ES apparently...

	; Fourth step: create 16-bit stack segment descriptor pointing at it

	mov	sp,si		; really ESP,ESI
	; push stack parameters right-to-left
	mov	cl,1		; BDDExplicitDPL
	push	cx		; really ECX => flags = BDDExplicitDPL
	xor	cl,cl
	push	cx		; really ECX => DESCSize = 0
	mov	cl,10010010b	; present, non-system, read-write
	push	cx		; really ECX => DESCType = data sel
	mov	cl,0FFh
	mov	ch,0Fh
	push	cx		; really ECX => DESCLimit = 0FFFh
	push	dx		; really EDX => DESCBase = address of page

	int	20h		; VxDcall
	dw	122		; _BuildDescriptorDWORDs
	dw	1		; VMM

	; Final step: put that descriptor in the GDT as well

	mov	sp,si		; really ESP,ESI
	; push stack parameters right-to-left
	xor	cx,cx		; really ECX
	push	cx		; really ECX => flags = 0
	push	ax		; really EAX = DescDWORD2
	push	dx		; really EDX = DescDWORD1

	int	20h		; VxDcall
	dw	118		; _Allocate_GDT_Selector
	dw	1		; VMM

	mov	sp,si		; really ESP,ESI
	; Done with the `VMMcall`s, head back to ~sanity~ - I mean, 16-bit!
	db	66h,0EAh	; 16-bit FAR JMP
	dw	offset @F
r0_cs_1	dw	?		; becomes selector for flat 32-bit Ring0 code

@@:	; *** BACK TO 16-BIT MODE, WE CAN BREATHE AGAIN! :3 ***
	pop	es
	assumes	es,Code
	pop	ds

	; at this point, AX should be our new 16-bit stack selector
	mov	es:[r0_ss16],ax

	; done with the Ring0 stuff for now...
	call	[Ring0to3]
	.286

	; now make sure that the two selectors were created successfully...
	cmp	cs:[r0_ss16],1	; sets CF iff r0_ss16 == 0
	jc	@F
	cmp	cs:[bswsel],1	; sets CF iff bswsel == 0
@@:	ret
setup_ring0_template	endp

; this is a Ring0 16-bit function that does a bank switch while keeping
; state coherent with the VBESVGA.DRV internal state.
; Entry: EAX = bank, SS = 32-bit flat stack, CS = our Ring0 alias
do_ring0_bankswitch	proc far
	assumes	ds,nothing
	assumes	es,nothing

	.386p
	push	ds
	push	es
	pushad

	mov	ds,[_cstods]
	assumes	ds,Data

	mov	dx,ax		; get bank from caller
        ;
        ;   compare requested bank against the current one
        ;
        cmp     dl,ds:[bank_select_byte]
        jz      r0_sbs_exit
        ;
        ;   we need to modify the BANK registers
        ;
        mov     ds:[bank_select_byte],dl

	; get the size-to-granularity multiplication factor, minus 1
	mov	ah,ds:[bank_granfac_m1]
	test	ah,ah
	jz	@F			; factor == 1 so no need to multiply

	inc	ah
	mov	al,dl
	mul	ah
	mov	dl,al

@@:	pushfd
	cli
;
	xor	bx,bx			; BH = 0 = "set", BL = 0 = window 0
	xor	dh,dh			; DX = DL = bank number (gran. units)

	db	0B8h		; mov AX,?
r0_ss16	dw	?		; 16-bit Ring0 stack selector

	; save current stack pointer
	mov	es,ax
	mov	es:[0FFCh],ss
	mov	es:[0FF8h],esp

	; switch to 16-bit stack
	; DO NOT SINGLE-STEP THIS in WDEB386!
	; I guess it doesn't expect a Ring0 debuggee to suddenly go onto a
	; 16-bit stack, and so it seems to halt and catch fire - under VBox
	; I get a Guru Meditation!
	mov	ss,ax
	mov	sp,0FF4h

	; call BIOS function
	db	9Ah		; far call (16:16)
bswoff	dw	?		; copy this from VESABankSwitch @ runtime
bswsel	dw	?		; Ring0 alias for VESABankSwitch, fill @ runtime
;
	lss	esp,ss:[0FF8h]	; get back original stack pointer

	popfd			; Okay to interrupt now

r0_sbs_exit:
	popad
	pop	es
	pop	ds
	assumes	ds,nothing

	db	66h		; 32-bit far return!
	ret
do_ring0_bankswitch	endp

; this is a code template that gets executed **in 32-bit Ring0**!
ring0_bsw_template:
	db	9Ah		; far call (16:32 in 32-bit mode!)
	dd	offset do_ring0_bankswitch
r0_cs_2	dw	?		; to be filled in at runtime
ring0_bsw_size	equ ($ - ring0_bsw_template)

sEnd	Code


.286

createSeg _INIT,InitSeg,word,public,CODE
sBegin	InitSeg

assumes	cs,InitSeg
assumes	ds,Data

;--------------------------------------------------------------------------;
; setup_bankswitch_ring0
;	sets up Ring0 bank-switch function and passses it to DVA/VFlatD to
;	create the virtual flat framebuffer selector.
; Entry:
;	DS	= Data
;	ES	= Code (writable)
;	VESABankSwitch populated with valid protected-mode function pointer
;	MemSize correctly populated with full framebuffer size
; Returns:
;	LinBufSel populated with selector to virtual flat framebuffer
; Error Returns:
;	LinBufSel remains NULL if any step fails
; Registers Destroyed:
;	FLAGS
; Registers Preserved:
;	AX,BX,CX,DX,SI,DI,DS,ES,BP
; Calls:
;	setup_ring0_template
;	VFlatDEntry
; History:
;	see Git
;--------------------------------------------------------------------------;
cProc	setup_bankswitch_ring0,<NEAR,PUBLIC>,<es>
cBegin
	assumes	es,Code

	; is VFlatD / DVA available?
	cmp	[VFlatDEntry.sel],0
	jz	setup_done

	.386	; if VFlatD exists, we're in Enhanced Mode, on a 386!
	; can we get to Ring0?
	cmp	[Ring3to0],0
	jz	setup_done

	pushad

	; first make sure we have valid Ring0 code to run
	call	setup_ring0_template
	jc	@F

	; then pass it in to VFlatD as a bank-switch function
        mov     dx, GET_VIDEO_SEL       ; the argument to the VxD function
	mov	eax,[MemSize]
	shr	eax,0Ch			; convert to pages
	mov	di,offset ring0_bsw_template
	mov	cx,ring0_bsw_size
	call	[VFlatDEntry]
	mov	[LinBufSel],ax

@@:	popad
	.286

setup_done:
cEnd

sEnd	InitSeg

END
