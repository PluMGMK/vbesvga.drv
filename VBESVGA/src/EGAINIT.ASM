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
; This module handles setting up the INT 10H calling route and setting a few
; default pointers.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	title	EGA Initialization Code

incDevice = 1				;allow assembly of needed constants

	.xlist
	include cmacros.inc
	include gdidefs.inc
        include display.inc
	include macros.mac
	include int3.inc
	.list

	??_out	egainit

        externA         __A000
        externA         __WinFlags

sBegin	Data

        externW ScreenSelector  ; the selector for display memory
	externD	VDDDBEntry	; in DBLBUF.ASM

public	VDDEntry,Ring3to0,Ring0to3
	VDDEntry	dd 0	; entry point to Virtual Display Driver
	Ring3to0	dd 0	; entry point to enter Ring0
	Ring0to3	dd 0	; entry point to get back to Ring3

sEnd	Data

createSeg _INIT,InitSeg,byte,public,CODE
sBegin  InitSeg
assumes cs,InitSeg

externNP SetupInt10h	; in INT10.ASM

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
;	SetupInt10h
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

cProc	dev_initialization,<FAR,PUBLIC>,<di>

cBegin
	mov	ax,__A000			; get the address of memory
	mov	ScreenSelector,ax

;       Fail to load on a 8086 or worse, we now use 286 specific code

        xor     ax,ax
        mov     bx,__WinFlags
        test    bx,WF_CPU086+WF_CPU186
        jnz     dev_init_exit

	; make sure we can call int 10h from Protected Mode...
	call	SetupInt10h
	test	ax,ax
	jz	dev_init_exit

	; VESA Protected Mode Interface, if available, gets setup later, in
	; ENABLE.ASM, because we need to allow the user to specify how to check
	; the structure's integrity...

	; grab the VDD entry and ring-transition code
	mov	ax,1684h	; get VxD entry point
	mov	bx,000Ah	; VDD
	xor	di,di		; NULL default return value
	mov	es,di		; NULL default return value
	int	2Fh
	mov	ax,es
	test	ax,ax		; Still NULL?
	jz	@F
	mov	[VDDEntry.off],di
	mov	[VDDEntry.sel],ax

	; now get the ring-transition entry points
	xor	dx,dx
	mov	ax,000Ah	;VDD ring transition API
	mov	cx,_TEXT	;desired code segment.
	call	VDDEntry
	or	dx,dx
	jz	@F		;RingAPI not present.
	mov	[Ring3to0.off],ax
	mov	[Ring3to0.sel],dx
	mov	[Ring0to3.off],bx
	mov	[Ring0to3.sel],cx

	; check if there's a double-buf entry point too...
	mov	dx,"DB"
	xor	bx,bx
	mov	ax,000Ah	;VDD ring transition API
	mov	cx,_TEXT	;pass valid code segment for
				; backwards compatibility
	call	VDDEntry
	cmp	bx,"BD"
	jne	@F		;Double-Buf API not present.
	test	cx,cx
	jnz	@F		;Double-Buf API not present.
	mov	[VDDDBEntry.off],ax
	mov	[VDDDBEntry.sel],dx

@@:	mov	ax,1		;no way to have error
dev_init_exit:
cEnd

sEnd	 InitSeg

end
