page	,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	TRACER.ASM
;
;   This module contains debugging functions.
;
; Created: 13-Feb-1989
; Author:  Gary Maltzen
;
; Copyright (c) 1989  Preferred Solutions, Inc.
; Copyright (c) 1989  Video Seven Inc.
;
; Exported Functions:	none
;
; Public Functions:	tracer
;
; Public Data:
;
; General Description:
;
; Restrictions:
;
;-----------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.

	.xlist
	include cmacros.inc
	.list

sBegin	Code
assumes	cs,Code

;=======================================================================
;
;  calling sequence - NOTE CAREFULLY
;
;	call	far ptr tracer
;	jmp	short @f
;	db	'text....'
; @@:	...
;
;  the jump distance in the `jmp short' instruction
;  incidentally happens to be the string length
;  THIS ROUTINE DEPENDS ON THIS!


	public	tracer
tracer	proc	far

 IF 1
	push	bp
	mov	bp,sp

	pushf
	push	si
	push	ds
	push	dx
	push	cx
	push	bx
	push	ax

	cld
	lds	si,[bp+2]	;get return address
	lodsb			;`jmp short' opcode
	lodsb			;string length
	mov	cl,al
	xor	ch,ch
	jcxz	short @2

	xor	dx,dx		;COM1
@1:	lodsb			;next byte
	mov	ah,01h		;write byte
	int	14h
	loop	@1	

@2:	pop	ax
	pop	bx
	pop	cx
	pop	dx
	pop	ds
	pop	si
	popf

	pop	bp

 ENDIF

	ret

tracer	endp


sEnd	Code

end

