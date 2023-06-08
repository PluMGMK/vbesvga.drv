	page	,132
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; egainit.asm
;
; Copyright (c) 1991 Microsoft Corporation.  All Rights Reserved.
;
; EGA initialization code.
; 
; Created: 26 June 1987
;
; This module handles disabling of the RC_SAVEBITMAP raster capability
; if the EGA doesn't have 256Kbytes of display memory.  This operation
; happens at run time, because the bit will always be set at assembly-
; time if the SaveScreenBitmap code is present in the driver, though
; a particular EGA board may not be able to use it.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	title	EGA Initialization Code

incDevice = 1				;allow assembly of needed constants

	.xlist
	include cmacros.inc
	include gdidefs.inc
        include display.inc
	include macros.mac
	.list

	??_out	egainit

        externA         __A000
        externA         __WinFlags

sBegin	Data

        externW ScreenSelector  ; the selector for display memory
        externW ssb_mask        ; Mask for save screen bitmap bit

sEnd	Data

;createSeg _INIT,InitSeg,byte,public,CODE
;sBegin  InitSeg
;assumes cs,InitSeg

sBegin	Code
assumes cs,Code

page

;--------------------------Public-Routine-------------------------------;
; dev_initialization - device specific initialization
;
; Any device specific initialization is performed.
;
; Entry:
;	None
; Returns:
;	AX = 1
; Registers Preserved:
;	SI,DI,BP,DS
; Registers Destroyed:
;	AX,BX,CX,DX,ES,FLAGS
; Calls:
;	int 10h
; History:
;       Mon 26-Mar-1990 -by-  Todd Laney [ToddLa]
;       Now fails loading on pre-286 machines
;
;	Mon 23-Jan-1989 13:01:00 -by-  Dave Miller
;	Changed to support 256 color modes on VRAM VGA by
;	Video Seven Inc.
;
;	Mon 21-Sep-1987 00:34:56 -by-  Walt Moore [waltm]
;	Changed it to be called from driver_initialization and
;	renamed it.
;
;	Fri 26-Jun-1987 -by- Bob Grudem    [bobgru]
;	Creation.
;-----------------------------------------------------------------------;
	assumes ds,Data
	assumes es,nothing

cProc	dev_initialization,<FAR,PUBLIC>

cBegin
;	Video 7 does not allow Save Screen bitmap calls
	and	ssb_mask,not RC_SAVEBITMAP

	mov	ax,__A000			; get the address of memory
	mov	ScreenSelector,ax

;       Fail to load on a 8086 or worse, we now use 286 specific code

        xor     ax,ax
        mov     bx,__WinFlags
        test    bx,WF_CPU086+WF_CPU186
        jnz     dev_init_exit

	mov	ax,1				;no way to have error
dev_init_exit:
cEnd

;sEnd	 InitSeg
sEnd	Code

end
