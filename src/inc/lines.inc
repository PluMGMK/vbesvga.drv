;----------------------------------------------------------------------------;
;									     ;
; INCLUDE file has the following macro deginitions:			     ;
;							                     ;
;              1.    mag r        returns magnitude of value in reg r in AX  ;
;              2.    minmax       returns the min of AX & BX in AX,max in BX ;
;              3.    minim r1,r2  return the minimum of r1 and r2 in ax      ;
;              4.    smov    A,B  moves register B into register A via stack ;
;							                     ;
; -by-  Amit Chatterjee [amitc]   Thu Aug 25  08:32:30                       ;
;----------------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.


mag	MACRO	r
	mov	ax,&r
	cwd			;; DX will be 0 if X positive , 0FFH if X neg
	xor	ax,dx		;; makes ones complement if X neg, else not     
	sub	ax,dx		;; subtract 1 from 1s compl to give 2s comp
				;; if X had been negative
	ENDM


minmax  MACRO     
	LOCAL	label
        mov	cx,ax		;; save original ax
	sub	ax,bx	
	cwd			;; DX will be 0 if AX >= BX, 0FFH if AX < BX
	and	ax,dx		;; AX = 0 if AX >= BX, AX = ax-bx if AX < BX
	add	ax,bx		;; AX = BX if AX >= BX, AX = AX if AX < BX
	cmp	ax,cx		;; test whether ax has changed or not
	jz	label		;; no, so BX has max value
	mov	bx,cx		;; set BX to original AX which is also the max
label:
	ENDM


minim   MACRO   r1,r2  
	mov	ax,&r1
        mov	bx,&r2
	sub	ax,bx	
	cwd			;; DX will be 0 if AX >= BX, 0FFH if AX < BX
	and	ax,dx		;; AX = 0 if AX >= BX, AX = ax-bx if AX < BX
	add	ax,bx		;; AX = BX if AX >= BX, AX = AX if AX < BX
	ENDM



smove	MACRO	A,B
	push	&B
	pop	&A		;; exchange via the stack
	ENDM
	

