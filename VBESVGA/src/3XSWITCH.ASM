	page	,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	3XSWITCH.ASM
;
;   This module contains the functions:
;
;	dev_to_background
;	dev_to_foreground
;
;   These functions support screen switching in and out of the OS/2
;   compatibility box.
;
; Created: 16-Sep-1987
; Author:  Bob Grudem [bobgru]
;
; Copyright (c) 1984-1987 Microsoft Corporation
;
; Exported Functions:	none
;
; Public Functions:	dev_to_background
;			dev_to_foreground
;
; Public Data:		none
;
; General Description:
;
; Restrictions:
;
;-----------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.

incDevice = 1				;Include control for gdidefs.inc

	.xlist
	include cmacros.inc
	include gdidefs.inc
	include macros.mac
	include	ega.inc
	.list

	??_out	3xswitch

	public		dev_to_foreground
	public		dev_to_background

	EXTRN		far_set_dacsize:FAR
	EXTRN		far_set_cursor_addr:FAR

sBegin  Data
	externW ScreenSelector
	externB enabled_flag
	externB screen_busy
	externB adPalette
	externW is_protected
	externB	info_table_base
sEnd	Data

createSeg _INIT,InitSeg,word,public,CODE
sBegin	InitSeg
assumes cs,InitSeg
	externFP	farsetmode
sEnd


createSeg _PALETTE,PaletteSeg,word,public,CODE
sBegin	PaletteSeg
	assumes cs,PaletteSeg
	externFP	SetPalette	; in TRN_PAL.ASM
        externFP        setramdac
sEnd

STOP_IO_TRAP    equ 4000h               ; stop io trapping
START_IO_TRAP	equ 4007h		; re-start io trapping

sBegin	Code
assumes cs,Code
	page

        externFP        init_hw_regs

;---------------------------Public-Routine-----------------------------;
; dev_to_foreground
;
; Performs any action necessary to restore the state of the display
; hardware prior to becoming the active context.
;
; Entry:
;	nothing
; Returns:
;	nothing
; Registers Preserved:
;	SI,DI,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,ES,FLAGS
; Calls:
;	none
; History:
;	Wed 16-Sep-1987 20:17:08 -by-  Bob Grudem [bobgru]
;	Modified for VRAM 256 color modes.
;-----------------------------------------------------------------------;

	assumes ds,Data
	assumes es,nothing
dev_to_foreground	proc	near
WriteAux    <'devtofg'>

	mov	ax,ScreenSelector	; res_hw_regs requires this
	mov	es,ax
	assumes es,nothing

        call    farsetmode

        mov     bx,1                    ;attempt to set 8 bit dac mode
        call    far_set_dacsize

	test	[info_table_base.dpRaster],RC_PALETTE
	jz	@F

	mov	cx,256			; number of entries to program
	sub	ax,ax			; first index
	lea	si,adPalette		; get pointer to table
	call	setramdac		; do it!!!

@@:
	call	init_hw_regs
	mov	[enabled_flag],0ffh	; is now enabled.
;	 mov	 screen_busy,1

	call	far_set_cursor_addr
        ret

dev_to_foreground	endp

	page

;---------------------------Public-Routine-----------------------------;
; dev_to_background
;
; Performs any action necessary to save the state of the display
; hardware prior to becoming an inactive context.
;
; Entry:
;	nothing
; Returns:
;	nothing
; Registers Preserved:
;	SI,DI,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,ES,FLAGS
; Calls:
;	none
; History:
;	Wed 16-Sep-1987 20:17:08 -by-  Bob Grudem [bobgru]
;
;

	assumes ds,Data
	assumes es,nothing


dev_to_background	proc	near
;WriteAux <'dev_to_background'>
WriteAux <'devtobk'>

	mov	[enabled_flag],00h	; block the driver from screen acesses.
;	 mov	 screen_busy,0
	sub	bx,bx			;set 6 bit dac mode
        call    far_set_dacsize
        ret

dev_to_background	endp

sEnd	Code
	end

