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

REFACTORED_IPC2RGB	equ 1
if	REFACTORED_IPC2RGB
	; FIXME: asymmetry; why don't we just include rgb_to_ipc and ipc_to_rgb?
	externNP ipc_to_rgb
endif
	externNP sum_RGB_colors_alt

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
;	sum_RGB_colors_alt
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
	; int	3
	les	di,lpPColour		;now ES:DI points to PCOLOR data Struc
	mov	ax,off_ColorIn		; Get passed RGB into DX:AX

	or	dh,dh			;is this already a physical color?
        errnz   COL_IS_PHYS-10000000b	;ensure COL_IS_PHYS is actually sign bit
	js	CIWritePhysicalColorIndex

%out GDI bug.;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        cmp     dh,01h
        je      CIWritePhysicalColorIndex
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	;Convert RGB to nearest matching index
	call	sum_RGB_colors_alt

;-------------------------------------------------------------------
;dx:ax contains our physical color as follows:
;  dh = ffh
;  dl = 00h
;  ah = color accelerators: ExxxxxZM where:E = Exact Match Bit (1=exact)
;					   Z = All Ones or Zeros bit (1=yes)
;                                          M = Mono bit (1=white)
;  al = physical index (4 lsb's)
;
;See rgb2ipc.asm for details about physical color.
;-------------------------------------------------------------------
	mov	bx,ds			;save ds.
	lds	si,lpDevice			
	cmp	byte ptr [si].bmBitsPixel,1     ;Is DC monochrome?
	mov	ds,bx			;restore ds.
	jne	short CIWritePhysicalColorIndex ;No.
	; TODO: Change this to DH? Maybe choose reg based on palette use?
	shr	ah,1			;Put mono bit into carry.
	sbb	al,al			;al=0 if mono=0, al=255 if mono=1  
	shl	ah,2			;Put Exact bit into carry.
	mov	ah,al			;ZM = 11 (white) or 00 (black)
	rcr	ah,1			;create E bit from carry.
	and	ah,10000001b		;create the M bit. clear extraneous bits.
	or	ah,2			;set Z bit. ZM = 11 (white) or 10 (black)

CIWritePhysicalColorIndex:
	stosw				; save data in Pcolor
	xchg	ax,dx
        stosw
	xchg	ax,dx

if	REFACTORED_IPC2RGB
	; now the physical colour is safely stashed in memory, convert the
	; registers back to the logical one, to fulfil this function's contract
CIReturnRGBColour:
	call	ipc_to_rgb

	; if it gave us back an index, then just exit.
	cmp	dh,0FFh
	je	CI_really_exit
	; otherwise, we zero DH because we don't need the accelerators for this.
else
	; if it's not an index, just return
	test	dh,COL_IS_INDEX
	jz	CIExit
	; If COL_IS_INDEX is 1, we also need to check COL_ROT_MASK (since it
	; could just be indicating that the colour needs to rotate one byte...)
	test	dh,COL_ROT_MASK
	jz	CIExit

; the color value we want to return is in Palette (the VGA simulated
; colors).  so convert the index to the 20 entry table of TRIPLES and
; get the color.

	xor	bh,bh
	cmp	bx,245
	jl	lower_end
	sub	bx,236			; shift upper-256 indices to upper-20

lower_end:
	mov	ax,bx
	shl	bx,1
	add	bx,ax			; index into a TRIPLEs table
	mov	ax,word ptr Palette[bx+0]
	mov	dx,word ptr Palette[bx+2]
	jmp	short CIExit

CIReturnRGBColour:
	; Here DX:BX holds our physical colour with (hopefully) all accel bits
	test	dh,COL_IS_INDEX
	jz	CI_really_exit
	; If COL_IS_INDEX is 1, we also need to check COL_ROT_MASK (since it
	; could just be indicating that the colour needs to rotate one byte...)
	test	dh,COL_ROT_MASK
	jz	CI_really_exit

	cmp	bl	,10
	jb	CIReturnSystemClr
	cmp	bl	,245
	ja	CIReturnSystemClr

	mov	ax	,bx
	mov	dx	,0FF00H
	jmp	CI_really_exit

CIReturnSystemClr:
        sub     bh      ,bh
	shiftl	bx,2
	mov	ax,word ptr adPalette[bx+0]
	mov	dx,word ptr adPalette[bx+2]
endif	; REFACTORED_IPC2RGB

CIExit:
;   At this time:
;	al has Red
;	ah has green
;	dl has blue
;
	xor dh,dh			; make sure it is an RGB flag

CI_really_exit:
	; int	3
	cEnd


sEnd	Code
end
