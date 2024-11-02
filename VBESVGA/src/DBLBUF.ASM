
;
;	FILE:	dblbuf.asm
;	DATE:	31 October 2024
;	AUTHOR: PluMGMK
;
;	This module contains code and data to support double-buffering for
;	improved performance.
;

SB_PERIOD_MS	equ 15		;swap buffers every 15 milliseconds
TIME_PERIODIC	equ 1		;from MMSYSTEM.H

incDevice = 1				;Include control for gdidefs.inc

	.xlist
	include CMACROS.INC
	include MACROS.MAC
	include GDIDEFS.INC
	include int3.inc
	include windefs.inc
	.list

	externFP AllocSelector
	externFP SetSelectorBase
	externFP SetSelectorLimit
	externFP GetSelectorBase
	externFP GetSelectorLimit
	externFP PrestoChangeoSelector

sBegin	Data

; Selectors
BackBufSel	dw ?
FrontBufSel	dw ?

; Handle to back-buffer memory block
BackBufDPMIHdl	dd ?

; How much data to transfer when swapping buffers
BackBufSize	dd ?

sEnd	Data


sBegin	Code
	assumes cs,Code

externD	VESALinearBuf

; Here is our callback function that gets called from CheckCursor
public	SwapBuffers
SwapBuffers	proc near
	assumes ds,Data
	assumes es,nothing

	push	ax
	mov	ax,[BackBufSize.lo]
	or	ax,[BackBufSize.hi]
	jz	SwapBufDone

	.386	; if we get this far we have a 386 (required for lin framebuf)
	push	ds
	push	es
	push	ecx
	push	esi
	push	edi
	mov	ecx,[BackBufSize]

	mov	es,[FrontBufSel]
	mov	ds,[BackBufSel]
	assumes	ds,nothing
	; point at the start of the buffers
	cld
	xor	esi,esi
	mov	edi,esi

	; stash the lower two bits in case we need to move extra byte / word
	mov	ax,cx
	and	ax,3

	; copy dword-by-dword
	shr	ecx,2
	rep	movs dword ptr es:[edi], dword ptr ds:[esi]
; 386 bug. 32-bit string instruction must be followed by a 32-bit instruction.
	db	67h
	nop

	; copy any extra word needed
	btr	ax,1
	jnc	@F
	movs	word ptr es:[edi], word ptr ds:[esi]
; 386 bug. 32-bit string instruction must be followed by a 32-bit instruction.
	db	67h
	nop

@@:	; copy any extra byte needed
	btr	ax,0
	jnc	@F
	movs	byte ptr es:[edi], byte ptr ds:[esi]
; 386 bug. 32-bit string instruction must be followed by a 32-bit instruction.
	db	67h
	nop

@@:	; All done
	pop	edi
	pop	esi
	pop	ecx
	pop	es
	pop	ds
	.286

SwapBufDone:
	pop	ax
	ret
SwapBuffers	endp

sEnd	Code


.286

createSeg _INIT,InitSeg,word,public,CODE
sBegin	InitSeg

assumes	cs,InitSeg
assumes	ds,Data

;--------------------------------------------------------------------------;
; setup_double_buf
;	prepares to start double-buffering, by getting the timer function
;	addresses and allocating memory for the back-buffer
; Entry:
;	DS	= Data
;	SI:DI	= int_phys_device structure
;	The driver must be setup to use a linear framebuffer
; Returns:
;	BackBufSel and FrontBufSel populated, pointing at respective buffers
; Error Returns:
;	BackBufSel and/or FrontBufSel NULL
; Registers Destroyed:
;	FLAGS
; Registers Preserved:
;	AX,BX,CX,DX,SI,DI,DS,ES,BP
; Calls:
;	LoadLibrary
;	GetProcAddress
;	int 31h
; History:
;	see Git
;--------------------------------------------------------------------------;
cProc	setup_double_buf,<NEAR,PUBLIC>,<es,ax,bx,cx,dx,si,di,bp>
cBegin
	; first of all check if double-buffering is already set up
	mov	ax,[BackBufSel]
	mov	bx,[FrontBufSel]
	or	ax,bx
	jz	@F
	jmp	setup_done

@@:	; Allocate the back buffer memory. Use DPMI directly, since
	; GlobalAlloc/GlobalLock would allocate a whole bunch of selectors
	; which we don't actually need!
	mov	es,si
	mov	ax,501h				; Allocate memory block
	mov	bx,es:[di].bmWidthPlanes.hi
	mov	cx,es:[di].bmWidthPlanes.lo
	mov	dx,di				; Stash this offset
	int	31h
	xchg	dx,di				; Get back the offset we stashed
	jc	setup_done
	mov	[BackBufDPMIHdl.lo],dx
	mov	[BackBufDPMIHdl.hi],si

	; Lock it straight away - we will keep the physical memory for
	; the back buffer in use for as long as Windows is running...
	; (It is a LOT of physical memory, so we don't want to lose it!)
	mov	ax,600h				; Lock linear region
	mov	si,es:[di].bmWidthPlanes.hi
	mov	dx,es:[di].bmWidthPlanes.lo
	xchg	dx,di
	int	31h
	xchg	dx,di				; Get back the offset we stashed
	jc	setup_done

	; Allocate selectors for front and back buffer
	mov	si,es
	push	bx
	push	cx
	cCall	AllocSelector,<es:[di].bmBits.sel>
	pop	cx
	pop	bx
	test	ax,ax
	jz	setup_done
	mov	[BackBufSel],ax

	; Set the selector to the base of the back buffer.
	cCall	SetSelectorBase,<ax,bx,cx>

	; And set its limit - SetSelectorBase should have returned the same
	; value in AX again
	mov	es,si
	mov	dx,es:[di].bmWidthPlanes.lo
	mov	cx,es:[di].bmWidthPlanes.hi
	; Limit == size-1
	sub	dx,1
	sbb	cx,0
	; Page-align the limit
	or	dx,0FFFh
	; Stash the selector before calling the function
	mov	bx,ax
	; Have to use DPMI instead of Windows KERNEL since the latter doesn't
	; know how to set page-granular limits...
	mov	ax,8	;set segment limit
	int	31h

	; Now copy the selector, to make one for the front buffer
	cCall	AllocSelector,<bx>
	test	ax,ax
	jz	setup_done
	mov	[FrontBufSel],ax

	; Set the selector to the base of the front buffer.
	mov	dx,seg VESALinearBuf
	mov	es,dx
	assumes	es,Code
	cCall	SetSelectorBase,<ax,[VESALinearBuf.hi],[VESALinearBuf.lo]>
	assumes	es,nothing			; C function stomps it

setup_done:
cEnd

;--------------------------------------------------------------------------;
; start_double_buf
;	actually starts the double-buffering: the linear framebuffer pointer
;	is switched to the back buffer and the swap-buffer timer event is
;	created.
; Entry:
;	DS	= Data
;	SI:DI	= int_phys_device structure
;	BackBufSel and FrontBufSel populated, pointing at respective buffers
; Registers Destroyed:
;	FLAGS
; Registers Preserved:
;	AX,BX,CX,DX,SI,DI,DS,ES,BP
; Calls:
; History:
;	see Git
;--------------------------------------------------------------------------;
cProc	start_double_buf,<NEAR,PUBLIC>,<es,ax,bx,cx,dx,si,di>
cBegin
	; first of all check if double-buffering is actually set up
	mov	ax,[BackBufSel]
	mov	bx,[FrontBufSel]
	or	ax,bx
	jz	start_done

	; grab the buffer size again
	mov	es,si
	mov	bx,es:[di].bmWidthPlanes.hi
	mov	cx,es:[di].bmWidthPlanes.lo

	; place it in BackBufSize to indicate that SwapBuffers should run
	mov	[BackBufSize.lo],cx
	mov	[BackBufSize.hi],bx

	; now point the driver bitmap at the back buffer
	mov	di,[BackBufSel]
	call	ChangeLinBuf

start_done:
cEnd

;--------------------------------------------------------------------------;
; stop_double_buf
;	actually stops the double-buffering: the linear framebuffer pointer
;	is switched to the front buffer and the swap-buffer timer event is
;	killed.
; Entry:
;	DS	= Data
; Registers Destroyed:
;	FLAGS
; Registers Preserved:
;	AX,BX,CX,DX,SI,DI,DS,ES,BP
; Calls:
; History:
;	see Git
;--------------------------------------------------------------------------;
cProc	stop_double_buf,<NEAR,PUBLIC>,<es,ax,bx,cx,dx,di>
cBegin
	; check if SwapBuffers is actually set to run
	mov	ax,[BackBufSize.lo]
	or	ax,[BackBufSize.hi]
	jz	stop_done

	; disable it by setting the amount of data to transfer to zero
	xor	ax,ax
	mov	[BackBufSize.lo],ax
	mov	[BackBufSize.hi],ax

	; now point the driver bitmap at the front buffer
	mov	di,[FrontBufSel]
	call	ChangeLinBuf

stop_done:
cEnd

; Change VESALinearBuf to point at the base of the selector pointed to by DI,
; and reset the bank pointer to ensure reads/writes go to the right place
ChangeLinBuf	proc near
	push	bp
	push	si

	; We need to modify Code, so repurpose the ES selector momentarily.
	; It is imperative that nothing interrupts us while this is going on.
	EnterCrit
	; Save the selector params
	.386	; if we get this far we have a 386 (required for lin framebuf)
	push	eax
	db	66h,0Fh,03h,0C7h	;lsl eax,edi
	push	eax
	cCall	GetSelectorBase,<di>
	; Set BP:SI to the new pointer we want to set
	mov	bp,dx
	mov	si,ax

	; Point the selector at Code
	mov	ax,seg VESALinearBuf
	cCall	PrestoChangeoSelector,<ax,di>
	; Load it into ES
	mov	es,di
	assumes	es,Code
	mov	[VESALinearBuf.lo],si
	mov	[VESALinearBuf.hi],bp

	; Now restore the original selector base and limit
	cCall	SetSelectorBase,<es,bp,si>
	assumes	es,nothing
	pop	dx
	pop	cx
	mov	bx,di
	; Have to use DPMI instead of Windows KERNEL since the latter doesn't
	; know how to set page-granular limits...
	mov	ax,8	;set segment limit
	int	31h

	pop	eax
	.286

	; We can be interrupted again
	LeaveCrit b

	; Now force the bank to be reset
	mov	dl,-1
	xchg	dl,[bank_select_byte]
	SET_BANK

	pop	si
	pop	bp
	ret
ChangeLinBuf	endp

sEnd	InitSeg

END
