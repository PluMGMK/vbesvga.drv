	page	,132
;
;-----------------------------Module-Header-----------------------------;
; Module Name:	COLORINF.ASM
;
; This module contains the color information routine.
;
; Created: 16-Feb-1987
; Author:  Walt Moore [waltm]
;
; Copyright (c) 1983-1987 Microsoft Corporation
;
; Exported Functions:	Control
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
;   ColorInfo is called by GDI to either convert a logical color
;   (an RGB triplet) to a physical color, or a phsyical color to
;   a logical color.
;
; Restrictions:
;
;-----------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.
.286

	.xlist
	include cmacros.inc
	include gdidefs.inc
	include display.inc
	include macros.mac
	.list


	??_out	colorinf


	externD adPalette		;initial color table
	externB Palette			; VGA palette stuff

sBegin	Code
assumes cs,Code

	externW	pxbytes
	externNP ipc_to_rgb
	externNP rgb_to_ipc

page

;--------------------------Exported-Routine-----------------------------;
;
; ColorInfo
;
;   ColorInfo accepts a logical RGB color value and returns the
;   logical RGB color value that the device can most closely represent.
;   ColorInfo also returns the device dependent, physical representation
;   of bits necessary to display the specified color on the device.
;   This information will be passed back into the driver by GDI.  GDI
;   will do no interpreting of the physical color.
;
;   Colorinfo may also be requested to convert a physical color into
;   a logical RGB color.  This is indicated by a NULL lpPColour.
;
; Entry:
;	None
; Returns:
;	DX:AX = physical color or logical color as appropriate
; Error Returns:
;	None
; Registers Preserved:
;	SI,DI,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,FLAGS
; Calls:
;	rgb_to_ipc
;	ipc_to_rgb
; History:
;	Mon 16-Feb-1987 18:09:09 -by-  Walt Moore [waltm]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


assumes ds,Data
assumes es,nothing


cProc	ColorInfo,<FAR,PUBLIC,WIN,PASCAL>,<di,si,es>

	parmD	lpDevice		;Pointer to device
	parmD	ColorIn 		;Input color (RGB or physical)
	parmD	lpPColour		;Pointer to physical color index

cBegin
WriteAux <'ClrInf'>
	cmp	seg_lpPColour,0 	;are wt to return the RGB colour for
	mov	bx,off_ColorIn		; the indexed passed?
	mov	dx,seg_ColorIn
	je	CIReturnRGBColour	;yes! return RGB DX:AX

	;No, return closest matching index at lpPColour
	; and RGB of closest matching index in DX:AX

CIReturnPhysicalColour:
	les	di,lpPColour		;now ES:DI points to PCOLOR data Struc
	mov	ax,off_ColorIn		; Get passed RGB into DX:AX

	; usually, DH==FFh indicates palette index, but if we have four bytes
	; per pixel, it instead encodes actual colour data.
	cmp	[pxbytes],4
	je	@F

	cmp	dh,0FFh			;is this already a palette index?
	je	CIWritePhysicalColorIndex

%out GDI bug.;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        cmp     dh,01h
        je      CIWritePhysicalColorIndex
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

@@:	;Convert RGB to nearest matching index
	call	rgb_to_ipc

;-------------------------------------------------------------------
;if using a palette, dx:ax contains our physical color as follows:
;  dh = ffh
;  dl = 00h
;  ah = color accelerators: ExxxxxZM where:E = Exact Match Bit (1=exact)
;					   Z = All Ones or Zeros bit (1=yes)
;                                          M = Mono bit (1=white)
;  al = physical index
;
;See rgb2ipc.asm for details about physical color.
;-------------------------------------------------------------------
	rcl	ch,1			;save mono flag
	mov	bx,ds			;save ds.
	lds	si,lpDevice			
	cmp	byte ptr [si].bmBitsPixel,1     ;Is DC monochrome?
	mov	ds,bx			;restore ds.
	jne	short CIWritePhysicalColorIndex ;No.

	shr	ch,1			;Put mono bit into carry.
	sbb	al,al			;al=0 if mono=0, al=255 if mono=1
	cmp	[pxbytes],4
	je	CIMono32

	cmp	dh,0FFh			;palette index?
	jne	CIMono32

	shl	ah,2			;Put Exact bit into carry.
	mov	ah,al			;ZM = 11 (white) or 00 (black)
	rcr	ah,1			;create E bit from carry.
	and	ah,10000001b		;create the M bit. clear extraneous bits.
	or	ah,2			;set Z bit. ZM = 11 (white) or 10 (black)
	jmp	CIWritePhysicalColorIndex
CIMono32:
	cbw
	cwd
	;if we got here because pxbytes==4, ZF will still be set
	;otherwise, make sure DH==0, to avoid confusing any other code that
	; might think this is an index if it's white...
	je	CIWritePhysicalColorIndex
	xor	dh,dh

CIWritePhysicalColorIndex:
	stosw				; save data in Pcolor
	xchg	ax,dx
        stosw
	xchg	ax,dx

	; now the physical colour is safely stashed in memory, convert the
	; registers back to the logical one, to fulfil this function's contract
CIReturnRGBColour:
	call	ipc_to_rgb

	; if it gave us back an index, then just exit.
	cmp	dh,0FFh
	je	CI_really_exit
	; otherwise, we zero DH because we don't need the accelerators for this.

CIExit:
;   At this time:
;	al has Red
;	ah has green
;	dl has blue
;
	xor dh,dh			; make sure it is an RGB flag

CI_really_exit:
	cEnd


sEnd	Code
end
