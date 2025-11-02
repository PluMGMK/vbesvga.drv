
;-----------------------------Module-Header-----------------------------;
; Module Name:	VESADEFS.INC
;
; This file contains constants and structures defined in various VESA
; standards, used in different places in the driver.
;
; Created: Tue 05-Jun-2023
; Author:  PluMGMK
;
; Exported Functions:	none
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
; Restrictions:
;
; History:
; See Git

; VBE Function Numbers
VBE_INT10_FN	= 4Fh	; placed in AH to call, returned in AL
VBE_GETINFO	=  0
VBE_GETMODEINFO	=  1
VBE_SETMODE	=  2
VBE_GETMODE	=  3
VBE_SAVERESTORE	=  4
VBE_BANKSWITCH	=  5
VBE_SCANLINELEN	=  6
VBE_DISPSTART	=  7
VBE_DACSIZE	=  8
VBE_PALENTRIES	=  9
VBE_GETPMINT	= 0Ah
VBE_GETPIXCLOCK	= 0Bh
VBE_GETEDID	= 15h

; VBE Error Codes
VBE_ERR_NONE	= 0
VBE_ERR_FAIL	= 1
VBE_ERR_BADHW	= 2
VBE_ERR_BADMODE	= 3
; Extra Error Codes for our wrapper functions
ERR_REAL_ALLOC	= 4
ERR_PROT_ALLOC	= 5

; CRT Controller Info Block (taken straight from VBE 3.0 spec)
CRTCInfoBlock	struc
HorizontalTotal		dw ?	; Horizontal total in pixels
HorizontalSyncStart	dw ?	; Horizontal sync start in pixels
HorizontalSyncEnd	dw ?	; Horizontal sync end in pixels
VerticalTotal		dw ?	; Vertical total in lines
VerticalSyncStart	dw ?	; Vertical sync start in lines
VerticalSyncEnd		dw ?	; Vertical sync end in lines
Flags			dw ?	; Flags (Interlaced, Double Scan etc.)
PixelClock		dd ?	; Pixel clock in units of Hz
RefreshRate		dw ?	; Refresh rate in units of 0.01 Hz

Reserved		db 40 dup (?)
CRTCInfoBlock	ends
