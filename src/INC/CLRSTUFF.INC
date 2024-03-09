;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; clrstuff.inc
;
; Copyright (c) 1991 Microsoft Corporation.  All Rights Reserved.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;--------------------------------------------------------------------
; Color rop inner loops - Opaque first
;
; entry:
;   ss:si -> color pattern ( already set to correct byte of pattern for
;			     this starting x)
;   cx = count (guaranteed not zero)
;   dh = current xpar mask ( already rotated )
;   dl = rotating bit to keep track of pattern byte
;
;
;--------------------------------------------------------------------
color_opaque_rop_0 proc
	xor	al,al
	rep	stosb
	ret
color_opaque_rop_0 endp
;--------------------------------------------------------------------
color_opaque_rop_1 proc

co_rop_1_loop:
	lods	byte PTR ss:[si]
	or	es:[di],al
	not	BYTE PTR es:[di]
	inc	di
	rol	dl,1
	jc	@F
	loop	co_rop_1_loop
	ret

	;update pattern pointer
@@:	sub	si,SIZE_PATTERN
	loop	co_rop_1_loop

	ret
color_opaque_rop_1 endp
;--------------------------------------------------------------------
color_opaque_rop_2 proc

co_rop_2_loop:
	lods	byte PTR ss:[si]
	not	al
	and	es:[di],al
	inc	di
	rol	dl,1
	jc	@F
	loop	co_rop_2_loop
	ret

	;update pattern pointer
@@:	sub	si,SIZE_PATTERN
	loop	co_rop_2_loop

	ret
color_opaque_rop_2 endp
;--------------------------------------------------------------------
color_opaque_rop_3 proc

co_rop_3_loop:
	lods	byte PTR ss:[si]
	not	al		    ; not it
	stosb			    ; store in destination
	rol	dl,1
	jc	@F
	loop	co_rop_3_loop
	ret

	;update pattern pointer
@@:	sub	si,SIZE_PATTERN
	loop	co_rop_3_loop

	ret
color_opaque_rop_3 endp
;--------------------------------------------------------------------
color_opaque_rop_4 proc

co_rop_4_loop:
	lods	byte PTR ss:[si]
	not	BYTE PTR es:[di]
	and	es:[di],al
	inc	di
	rol	dl,1
	jc	@F
	loop	co_rop_4_loop
	ret

	;update pattern pointer
@@:	sub	si,SIZE_PATTERN
	loop	co_rop_4_loop

	ret
color_opaque_rop_4 endp
;--------------------------------------------------------------------
color_opaque_rop_5 proc

co_rop_5_loop:
	not	BYTE PTR es:[di]
	inc	di
	loop	co_rop_5_loop

	ret
color_opaque_rop_5 endp
;--------------------------------------------------------------------
color_opaque_rop_6 proc

co_rop_6_loop:
	lods	byte PTR ss:[si]
	xor	es:[di],al
	inc	di
	rol	dl,1
	jc	@F
	loop	co_rop_6_loop
	ret

	;update pattern pointer
@@:	sub	si,SIZE_PATTERN
	loop	co_rop_6_loop

	ret
color_opaque_rop_6 endp
;--------------------------------------------------------------------
color_opaque_rop_7 proc

co_rop_7_loop:
	lods	byte PTR ss:[si]
	and	es:[di],al
	not	BYTE PTR es:[di]
	inc	di
	rol	dl,1
	jc	@F
	loop	co_rop_7_loop
	ret

	;update pattern pointer
@@:	sub	si,SIZE_PATTERN
	loop	co_rop_7_loop

	ret
color_opaque_rop_7 endp
;--------------------------------------------------------------------
color_opaque_rop_8 proc

co_rop_8_loop:
	lods	byte PTR ss:[si]
	and	es:[di],al
	inc	di
	rol	dl,1
	jc	@F
	loop	co_rop_8_loop
	ret

	;update pattern pointer
@@:	sub	si,SIZE_PATTERN
	loop	co_rop_8_loop

	ret
color_opaque_rop_8 endp
;--------------------------------------------------------------------
color_opaque_rop_9 proc

co_rop_9_loop:
	lods	byte PTR ss:[si]
	not	al
	xor	es:[di],al
	inc	di
	rol	dl,1
	jc	@F
	loop	co_rop_9_loop
	ret

	;update pattern pointer
@@:	sub	si,SIZE_PATTERN
	loop	co_rop_9_loop

	ret
color_opaque_rop_9 endp
;--------------------------------------------------------------------
color_opaque_rop_a proc
	ret
color_opaque_rop_a endp
;--------------------------------------------------------------------
color_opaque_rop_b proc

co_rop_b_loop:
	lods	byte PTR ss:[si]
	not	al
	or	es:[di],al
	inc	di
	rol	dl,1
	jc	@F
	loop	co_rop_b_loop
	ret

	;update pattern pointer
@@:	sub	si,SIZE_PATTERN
	loop	co_rop_b_loop

	ret
color_opaque_rop_b endp
;--------------------------------------------------------------------
color_opaque_rop_c proc

;
;ifdef WAYNEK
	cmp	cx,8 
	jl	co_rop_c_loop

	push	si
	and	ax,0111b
	sub	si,ax
	mov	ax,ss:[si]
	cmp	ah,al
	jnz	co_rop_c_loop_si
	cmp	ax,ss:[si+2]
	jnz	co_rop_c_loop_si
	cmp	ax,ss:[si+4]
	jnz	co_rop_c_loop_si
	cmp	ax,ss:[si+6]
	jnz	co_rop_c_loop_si
	pop	si

co_rop_a:
	shr	cx,1
	jc	co_rop_c_odd
	test	di,1
	jnz	co_rop_c_ena
	rep	stosw	;even alined
	ret
co_rop_c_ena:
	dec	cx
	stosb
	rep	stosw
	stosb
	ret
co_rop_c_odd:
	test	di,1
	jnz	co_rop_c_ona
	rep	stosw
	stosb
	ret
co_rop_c_ona:
	stosb
	rep	stosw
	ret
co_rop_c_loop_si:
	pop	si
;endif
;

co_rop_c_loop:

	movs	byte ptr es:[di], ss:[si]
	rol	dl,1
	jc	@F
	loop	co_rop_c_loop
	ret

	;update pattern pointer
@@:	sub	si,SIZE_PATTERN
	loop	co_rop_c_loop
	ret
color_opaque_rop_c endp

;--------------------------------------------------------------------
color_opaque_rop_d proc

co_rop_d_loop:
	lods	byte PTR ss:[si]
	not	BYTE PTR es:[di]
	or	es:[di],al
	inc	di
	rol	dl,1
	jc	@F
	loop	co_rop_d_loop
	ret

	;update pattern pointer
@@:	sub	si,SIZE_PATTERN
	loop	co_rop_d_loop

	ret
color_opaque_rop_d endp
;--------------------------------------------------------------------
color_opaque_rop_e proc

co_rop_e_loop:
	lods	byte PTR ss:[si]
	or	es:[di],al
	inc	di
	rol	dl,1
	jc	@F
	loop	co_rop_e_loop
	ret

	;update pattern pointer
@@:	sub	si,SIZE_PATTERN
	loop	co_rop_e_loop

	ret
color_opaque_rop_e endp
;--------------------------------------------------------------------
color_opaque_rop_f proc
	mov	al,0ffh
	rep	stosb
	ret
color_opaque_rop_f endp

;--------------------------------------------------------------------
; Color rop inner loops - Transparent
;
; entry:
;   ss:si -> color pattern ( already set to correct byte of pattern for
;			     this starting x)
;   cx = count (guaranteed not zero)
;   dh = current xpar mask ( already rotated )
;   dl = rotating bit to keep track of pattern byte
;
;
;--------------------------------------------------------------------
color_xpar_rop_0 proc
	xor	al,al

cx_rop_0_loop:
	rol	dh,1
	jnc	@F
	;perform rop
	mov	es:[di],al
@@:	inc	di
	loop	cx_rop_0_loop

	ret
color_xpar_rop_0 endp
;--------------------------------------------------------------------
color_xpar_rop_1 proc

cx_rop_1_loop:
	rol	dh,1
	jnc	@F
	;perform rop
	mov	al,ss:[si]
	or	BYTE PTR es:[di] ,al
	not	BYTE PTR es:[di]
@@:	inc	di
	inc	si
	rol	dl,1
	jc	@F
	loop	cx_rop_1_loop
	ret

@@:	sub	si,SIZE_PATTERN
	loop	cx_rop_1_loop

	ret
color_xpar_rop_1 endp
;--------------------------------------------------------------------
color_xpar_rop_2 proc
cx_rop_2_loop:
	rol	dh,1
	jnc	@F
	;perform rop
	mov	al,ss:[si]
	not	al
	and	es:[di],al
@@:	inc	di
	inc	si
	rol	dl,1
	jc	@F
	loop	cx_rop_2_loop
	ret

@@:	sub	si,SIZE_PATTERN
	loop	cx_rop_2_loop

	ret
color_xpar_rop_2 endp
;--------------------------------------------------------------------
color_xpar_rop_3 proc
cx_rop_3_loop:
	rol	dh,1
	jnc	@F
	;perform rop
	mov	al,ss:[si]
	not	al
	mov	es:[di],al
@@:	inc	di
	inc	si
	rol	dl,1
	jc	@F
	loop	cx_rop_3_loop
	ret

@@:	sub	si,SIZE_PATTERN
	loop	cx_rop_3_loop

	ret
color_xpar_rop_3 endp
;--------------------------------------------------------------------
color_xpar_rop_4 proc
cx_rop_4_loop:
	rol	dh,1
	jnc	@F
	;perform rop
	mov	al,ss:[si]
	not	BYTE PTR es:[di]
	and	es:[di],al

@@:	inc	di
	inc	si
	rol	dl,1
	jc	@F
	loop	cx_rop_4_loop
	ret

@@:	sub	si,SIZE_PATTERN
	loop	cx_rop_4_loop

	ret
color_xpar_rop_4 endp
;--------------------------------------------------------------------
color_xpar_rop_5 proc
cx_rop_5_loop:
	rol	dh,1
	jnc	@F
	;perform rop
	not	BYTE PTR es:[di]
@@:	inc	di
	loop	cx_rop_5_loop
	ret
color_xpar_rop_5 endp
;--------------------------------------------------------------------
color_xpar_rop_6 proc
cx_rop_6_loop:
	rol	dh,1
	jnc	@F
	;perform rop
	mov	al,ss:[si]
	xor	es:[di],al
@@:	inc	di
	inc	si
	rol	dl,1
	jc	@F
	loop	cx_rop_6_loop
	ret

@@:	sub	si,SIZE_PATTERN
	loop	cx_rop_6_loop

	ret
color_xpar_rop_6 endp
;--------------------------------------------------------------------
color_xpar_rop_7 proc
cx_rop_7_loop:
	rol	dh,1
	jnc	@F
	;perform rop
	mov	al,ss:[si]
	and	es:[di],al
	not	BYTE PTR es:[di]
@@:	inc	di
	inc	si
	rol	dl,1
	jc	@F
	loop	cx_rop_7_loop
	ret

@@:	sub	si,SIZE_PATTERN
	loop	cx_rop_7_loop

	ret
color_xpar_rop_7 endp
;--------------------------------------------------------------------
color_xpar_rop_8 proc
cx_rop_8_loop:
	rol	dh,1
	jnc	@F
	;perform rop
	mov	al,ss:[si]
	and	es:[di],al
@@:	inc	di
	inc	si
	rol	dl,1
	jc	@F
	loop	cx_rop_8_loop
	ret

@@:	sub	si,SIZE_PATTERN
	loop	cx_rop_8_loop

	ret
color_xpar_rop_8 endp
;--------------------------------------------------------------------
color_xpar_rop_9 proc
cx_rop_9_loop:
	rol	dh,1
	jnc	@F
	;perform rop
	mov	al,ss:[si]
	not	al
	xor	es:[di],al
@@:	inc	di
	inc	si
	rol	dl,1
	jc	@F
	loop	cx_rop_9_loop
	ret

@@:	sub	si,SIZE_PATTERN
	loop	cx_rop_9_loop

	ret
color_xpar_rop_9 endp
;--------------------------------------------------------------------
color_xpar_rop_a proc
	ret
color_xpar_rop_a endp
;--------------------------------------------------------------------
color_xpar_rop_b proc
cx_rop_b_loop:
	rol	dh,1
	jnc	@F
	;perform rop
	mov	al,ss:[si]
	not	al
	or	es:[di],al

@@:	inc	di
	inc	si
	rol	dl,1
	jc	@F
	loop	cx_rop_b_loop
	ret

@@:	sub	si,SIZE_PATTERN
	loop	cx_rop_b_loop

	ret
color_xpar_rop_b endp
;--------------------------------------------------------------------
color_xpar_rop_c proc
cx_rop_c_loop:
	rol	dh,1
	jnc	@F
	;perform rop
	mov	al,ss:[si]
	mov	es:[di],al
@@:	inc	di
	inc	si
	rol	dl,1
	jc	@F
	loop	cx_rop_c_loop
	ret

@@:	sub	si,SIZE_PATTERN
	loop	cx_rop_c_loop

	ret
color_xpar_rop_c endp
;--------------------------------------------------------------------
color_xpar_rop_d proc
cx_rop_d_loop:
	rol	dh,1
	jnc	@F
	;perform rop
	mov	al,ss:[si]
	not	BYTE PTR es:[di]
	or	es:[di],al

@@:	inc	di
	inc	si
	rol	dl,1
	jc	@F
	loop	cx_rop_d_loop
	ret

@@:	sub	si,SIZE_PATTERN
	loop	cx_rop_d_loop

	ret
color_xpar_rop_d endp
;--------------------------------------------------------------------
color_xpar_rop_e proc
cx_rop_e_loop:
	rol	dh,1
	jnc	@F
	;perform rop
	mov	al,ss:[si]
	or	es:[di],al
@@:	inc	di
	inc	si
	rol	dl,1
	jc	@F
	loop	cx_rop_e_loop
	ret

@@:	sub	si,SIZE_PATTERN
	loop	cx_rop_e_loop

	ret
color_xpar_rop_e endp
;--------------------------------------------------------------------
color_xpar_rop_f proc
	mov	al,0ffh

cx_rop_f_loop:
	rol	dh,1
	jnc	@F
	;perform rop
	mov	es:[di],al
@@:	inc	di
	loop	cx_rop_f_loop

	ret
color_xpar_rop_f endp
