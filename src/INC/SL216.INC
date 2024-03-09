;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; sl216.inc
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;--------------------------------------------------------------------
; Color rop inner loops - Opaque first
;
; entry:
;   es:di -> 216 8planar ptr to start of first set of 8 pixels to do
;   bl,bh left edge mask, right edge mask
;   cx	  middle 8pixel count  (may be zero)
;   extended bglatches have been loaded
;
;--------------------------------------------------------------------

sl216_opaque_rop proc

        mov     dx,VGAREG_SQ_ADDR               ;for the edge, we need rmw
        mov     al,VGAREG_SQ_XALU_CONTROL       ; cycles to permit masking
        mov     ah,0E2H
rept 8
        jmp $+2
endm
        out     dx,ax


;	Remove this stuff when same backtoback stosb with rmw works

	mov	dx,VGAREG_SQ_ADDR
	mov	al,0E8H
	out	dx,al
	inc	dx
	in	al,dx
	mov	ah,al
	mov	al,0C0H
	out	dx,al
	mov	al,es:[07FFFH - 100H - 03FH]
	mov	al,ah
	out	dx,al


        mov     al,bl
        stosb

        or      cx,cx
	je	ender

	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_XALU_CONTROL	;for the middle, don't use
	mov	ah,0C2H
rept 8
	jmp $+2
endm
        out     dx,ax                           ; are needed

	mov	ax,0FFFFH
	test	di,1
	jz	@F
	stosb
	dec	cx
@@:	shr	cx,1
	rep	stosw
	rcl	cx,1
	rep	stosb

	mov	al,VGAREG_SQ_XALU_CONTROL	; cycles to permit masking
	mov	ah,0E2H
rept 8
	jmp $+2
endm
        out     dx,ax
	jmp	short ender2

ender:
;	Remove this stuff when same backtoback stosb with rmw works

	mov	dx,VGAREG_SQ_ADDR
	mov	al,0E8H
	out	dx,al
	inc	dx
	in	al,dx
	mov	ah,al
	mov	al,0C0H
	out	dx,al
	mov	al,es:[07FFFH - 100H - 03FH]
	mov	al,ah
	out	dx,al

ender2:
	mov	al,bh
        stosb
	ret

sl216_opaque_rop endp



sl216_xpar_rop proc

	mov	dx,VGAREG_SQ_ADDR		;for the edge, we need rmw
	mov	al,VGAREG_SQ_XALU_CONTROL	; cycles to permit masking
	mov	ah,0E2H
rept 8
	jmp $+2
endm
        out     dx,ax

	mov	al,bl
        stosb

	mov	al,VGAREG_SQ_XALU_CONTROL	;for the middle, don't use
	mov	ah,0C2H
rept 8
	jmp $+2
endm
        out     dx,ax                           ; are needed

	mov	ax,0FFFFH
	test	di,1
	jz	@F
	stosb
	dec	cx
@@:	shr	cx,1
	rep	stosw
	rcl	cx,1
	rep	stosb

	mov	al,VGAREG_SQ_XALU_CONTROL	; cycles to permit masking
	mov	ah,0E2H
rept 8
	jmp $+2
endm
        out     dx,ax

	mov	al,bh
        stosb
	ret

sl216_xpar_rop endp


