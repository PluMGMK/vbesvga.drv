;-------------------------Macro-----------------------------------------;
; TRACER
;
; Writes some debugging info to the standard aux device.
;
; Entry:
;	none
;
; Returns:
;	none - string was output to aux
;
; History:
;   Tue Apr 4, 1981 - Gary Maltzen - Preferred Solutions @ Video 7
;   Wrote it.
;
;-----------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.

	ifdef	DEBUG ;=================

	externFP tracer

TRACER	macro	dstr

	call	tracer
	jmp	short @F

	db	dstr,10,13

@@:
	endm

	else ;--------------------------

TRACER	macro
	endm

	endif ;=========================
