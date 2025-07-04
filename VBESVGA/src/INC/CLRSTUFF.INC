;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;   es:di -> destination bitmap (or screen)
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
;   es:di -> destination bitmap (or screen)
;   ss:si -> color pattern ( already set to correct byte of pattern for
;			     this starting x)
;   ax = xstart in BYTES (only for ROP C)
;   bx = pattern pitch (8, 16, 24 or 32)
;   cx = count in PIXELS (guaranteed not zero)
;   dh = current xpar mask ( already rotated )
;   dl = rotating bit to keep track of pattern byte
;
;
;--------------------------------------------------------------------
color_opaque_rop_0 proc
	; convert CX from pixels to bytes
	xor	ax,ax
@@:	add	ax,cx
	sub	bx,SIZE_PATTERN
	jnz	@B
	mov	cx,ax

	mov	ax,di
	add	ax,cx
	jc	@F
	xor	al,al
	rep	stosb
	ret

@@:	; DI + CX wraps around --> we will cross a bank boundary during this ROP
	; AX at this point contains the remainder, so store that...
	push	ax
	mov	cx,di
	neg	cx	; do enough to finish the current bank
	xor	al,al
	rep	stosb
	; the XOR instruction has set ZF so this will advance the bank:
	call	colour_check_bank
	pop	cx	; get back the remainder
	rep	stosb
	ret
color_opaque_rop_0 endp
;--------------------------------------------------------------------
color_opaque_rop_1 proc

co_rop_1_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes

@@:	lods	byte PTR ss:[si]
	or	es:[di],al
	not	BYTE PTR es:[di]
	inc	di
	call	colour_check_bank
	dec	bh
	jnz	@B

	rol	dl,1
	jc	@F
	loop	co_rop_1_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	co_rop_1_loop

	ret
color_opaque_rop_1 endp
;--------------------------------------------------------------------
color_opaque_rop_2 proc

co_rop_2_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes

@@:	lods	byte PTR ss:[si]
	not	al
	and	es:[di],al
	inc	di
	call	colour_check_bank
	dec	bh
	jnz	@B

	rol	dl,1
	jc	@F
	loop	co_rop_2_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	co_rop_2_loop

	ret
color_opaque_rop_2 endp
;--------------------------------------------------------------------
color_opaque_rop_3 proc

co_rop_3_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes

@@:	lods	byte PTR ss:[si]
	not	al		    ; not it
	stosb			    ; store in destination
	test	di,di
	call	colour_check_bank
	dec	bh
	jnz	@B

	rol	dl,1
	jc	@F
	loop	co_rop_3_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	co_rop_3_loop

	ret
color_opaque_rop_3 endp
;--------------------------------------------------------------------
color_opaque_rop_4 proc

co_rop_4_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes

@@:	lods	byte PTR ss:[si]
	not	BYTE PTR es:[di]
	and	es:[di],al
	inc	di
	call	colour_check_bank
	dec	bh
	jnz	@B

	rol	dl,1
	jc	@F
	loop	co_rop_4_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	co_rop_4_loop

	ret
color_opaque_rop_4 endp
;--------------------------------------------------------------------
color_opaque_rop_5 proc

	; convert CX from pixels to bytes
	xor	ax,ax
@@:	add	ax,cx
	sub	bx,SIZE_PATTERN
	jnz	@B
	mov	cx,ax

co_rop_5_loop:
	not	BYTE PTR es:[di]
	inc	di
	call	colour_check_bank
	loop	co_rop_5_loop

	ret
color_opaque_rop_5 endp
;--------------------------------------------------------------------
color_opaque_rop_6 proc

co_rop_6_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes

@@:	lods	byte PTR ss:[si]
	xor	es:[di],al
	inc	di
	call	colour_check_bank
	dec	bh
	jnz	@B

	rol	dl,1
	jc	@F
	loop	co_rop_6_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	co_rop_6_loop

	ret
color_opaque_rop_6 endp
;--------------------------------------------------------------------
color_opaque_rop_7 proc

co_rop_7_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes

@@:	lods	byte PTR ss:[si]
	and	es:[di],al
	not	BYTE PTR es:[di]
	inc	di
	call	colour_check_bank
	dec	bh
	jnz	@B

	rol	dl,1
	jc	@F
	loop	co_rop_7_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	co_rop_7_loop

	ret
color_opaque_rop_7 endp
;--------------------------------------------------------------------
color_opaque_rop_8 proc

co_rop_8_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes

@@:	lods	byte PTR ss:[si]
	and	es:[di],al
	inc	di
	call	colour_check_bank
	dec	bh
	jnz	@B

	rol	dl,1
	jc	@F
	loop	co_rop_8_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	co_rop_8_loop

	ret
color_opaque_rop_8 endp
;--------------------------------------------------------------------
color_opaque_rop_9 proc

co_rop_9_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes

@@:	lods	byte PTR ss:[si]
	not	al
	xor	es:[di],al
	inc	di
	call	colour_check_bank
	dec	bh
	jnz	@B

	rol	dl,1
	jc	@F
	loop	co_rop_9_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
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
	mov	bh,bl
	shr	bh,3	; BH := pxbytes

@@:	lods	byte PTR ss:[si]
	not	al
	or	es:[di],al
	inc	di
	call	colour_check_bank
	dec	bh
	jnz	@B

	rol	dl,1
	jc	@F
	loop	co_rop_b_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	co_rop_b_loop

	ret
color_opaque_rop_b endp
;--------------------------------------------------------------------
color_opaque_rop_c proc

;
;ifdef WAYNEK
	cmp	cx,8 
	jl	co_rop_c_loop

	; the following special case only works for 8-bit
	cmp	bl,SIZE_PATTERN
	ja	co_rop_c_loop

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

	; check if we'll cross a bank
	mov	si,di
	add	si,cx
	jc	co_rop_c_loop_si
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

	mov	bh,bl
	shr	bh,3	; BH := pxbytes

@@:	movs	byte ptr es:[di], ss:[si]
	test	di,di
	call	colour_check_bank
	dec	bh
	jnz	@B

	rol	dl,1
	jc	@F
	loop	co_rop_c_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	co_rop_c_loop
	ret
color_opaque_rop_c endp

;--------------------------------------------------------------------
color_opaque_rop_d proc

co_rop_d_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes

@@:	lods	byte PTR ss:[si]
	not	BYTE PTR es:[di]
	or	es:[di],al
	inc	di
	call	colour_check_bank
	dec	bh
	jnz	@B

	rol	dl,1
	jc	@F
	loop	co_rop_d_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	co_rop_d_loop

	ret
color_opaque_rop_d endp
;--------------------------------------------------------------------
color_opaque_rop_e proc

co_rop_e_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes

@@:	lods	byte PTR ss:[si]
	or	es:[di],al
	inc	di
	call	colour_check_bank
	dec	bh
	jnz	@B

	rol	dl,1
	jc	@F
	loop	co_rop_e_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	co_rop_e_loop

	ret
color_opaque_rop_e endp
;--------------------------------------------------------------------
color_opaque_rop_f proc
	; convert CX from pixels to bytes
	xor	ax,ax
@@:	add	ax,cx
	sub	bx,SIZE_PATTERN
	jnz	@B
	mov	cx,ax

	mov	ax,di
	add	ax,cx
	jc	@F
	mov	al,0ffh
	rep	stosb
	ret

@@:	; DI + CX wraps around --> we will cross a bank boundary during this ROP
	; AX at this point contains the remainder, so store that...
	push	ax
	mov	cx,di
	neg	cx	; do enough to finish the current bank
	mov	al,0ffh
	rep	stosb
	test	di,di	; set ZF
	call	colour_check_bank
	pop	cx	; get back the remainder
	rep	stosb
	ret
color_opaque_rop_f endp

;--------------------------------------------------------------------
; Color rop inner loops - Transparent
;
; entry:
;   es:di -> destination bitmap (or screen)
;   ss:si -> color pattern ( already set to correct byte of pattern for
;			     this starting x)
;   bx = pattern pitch (8, 16, 24 or 32)
;   cx = count in PIXELS (guaranteed not zero)
;   dh = current xpar mask ( already rotated )
;   dl = rotating bit to keep track of pattern byte
;
;
;--------------------------------------------------------------------
color_xpar_rop_0 proc
	shr	bl,3	; BL := pxbytes
	xor	al,al

cx_rop_0_loop:
	mov	bh,bl
cx_rop_0_inner:
	test	dh,dh
	jns	@F	; if MSB is clear, this is a transparent pixel
	;perform rop
	mov	es:[di],al
@@:	inc	di
	call	colour_check_bank
	dec	bh
	jnz	cx_rop_0_inner

	rol	dh,1	; move onto next bit of transparent mask
	loop	cx_rop_0_loop

	ret
color_xpar_rop_0 endp
;--------------------------------------------------------------------
color_xpar_rop_1 proc

cx_rop_1_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes
cx_rop_1_inner:
	test	dh,dh
	jns	@F	; if MSB is clear, this is a transparent pixel
	;perform rop
	mov	al,ss:[si]
	or	BYTE PTR es:[di] ,al
	not	BYTE PTR es:[di]
@@:	inc	di
	call	colour_check_bank
	inc	si
	dec	bh
	jnz	cx_rop_1_inner

	rol	dh,1	; move onto next bit of transparent mask
	rol	dl,1
	jc	@F
	loop	cx_rop_1_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	cx_rop_1_loop

	ret
color_xpar_rop_1 endp
;--------------------------------------------------------------------
color_xpar_rop_2 proc
cx_rop_2_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes
cx_rop_2_inner:
	test	dh,dh
	jns	@F	; if MSB is clear, this is a transparent pixel
	;perform rop
	mov	al,ss:[si]
	not	al
	and	es:[di],al
@@:	inc	di
	call	colour_check_bank
	inc	si
	dec	bh
	jnz	cx_rop_2_inner

	rol	dh,1	; move onto next bit of transparent mask
	rol	dl,1
	jc	@F
	loop	cx_rop_2_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	cx_rop_2_loop

	ret
color_xpar_rop_2 endp
;--------------------------------------------------------------------
color_xpar_rop_3 proc
cx_rop_3_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes
cx_rop_3_inner:
	test	dh,dh
	jns	@F	; if MSB is clear, this is a transparent pixel
	;perform rop
	mov	al,ss:[si]
	not	al
	mov	es:[di],al
@@:	inc	di
	call	colour_check_bank
	inc	si
	dec	bh
	jnz	cx_rop_3_inner

	rol	dh,1	; move onto next bit of transparent mask
	rol	dl,1
	jc	@F
	loop	cx_rop_3_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	cx_rop_3_loop

	ret
color_xpar_rop_3 endp
;--------------------------------------------------------------------
color_xpar_rop_4 proc
cx_rop_4_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes
cx_rop_4_inner:
	test	dh,dh
	jns	@F	; if MSB is clear, this is a transparent pixel
	;perform rop
	mov	al,ss:[si]
	not	BYTE PTR es:[di]
	and	es:[di],al

@@:	inc	di
	call	colour_check_bank
	inc	si
	dec	bh
	jnz	cx_rop_4_inner

	rol	dh,1	; move onto next bit of transparent mask
	rol	dl,1
	jc	@F
	loop	cx_rop_4_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	cx_rop_4_loop

	ret
color_xpar_rop_4 endp
;--------------------------------------------------------------------
color_xpar_rop_5 proc
	shr	bl,3	; BL := pxbytes
cx_rop_5_loop:
	mov	bh,bl
cx_rop_5_inner:
	test	dh,dh
	jns	@F	; if MSB is clear, this is a transparent pixel
	;perform rop
	not	BYTE PTR es:[di]
@@:	inc	di
	call	colour_check_bank
	dec	bh
	jnz	cx_rop_5_inner

	rol	dh,1	; move onto next bit of transparent mask
	loop	cx_rop_5_loop
	ret
color_xpar_rop_5 endp
;--------------------------------------------------------------------
color_xpar_rop_6 proc
cx_rop_6_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes
cx_rop_6_inner:
	test	dh,dh
	jns	@F	; if MSB is clear, this is a transparent pixel
	;perform rop
	mov	al,ss:[si]
	xor	es:[di],al
@@:	inc	di
	call	colour_check_bank
	inc	si
	dec	bh
	jnz	cx_rop_6_inner

	rol	dh,1	; move onto next bit of transparent mask
	rol	dl,1
	jc	@F
	loop	cx_rop_6_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	cx_rop_6_loop

	ret
color_xpar_rop_6 endp
;--------------------------------------------------------------------
color_xpar_rop_7 proc
cx_rop_7_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes
cx_rop_7_inner:
	test	dh,dh
	jns	@F	; if MSB is clear, this is a transparent pixel
	;perform rop
	mov	al,ss:[si]
	and	es:[di],al
	not	BYTE PTR es:[di]
@@:	inc	di
	call	colour_check_bank
	inc	si
	dec	bh
	jnz	cx_rop_7_inner

	rol	dh,1	; move onto next bit of transparent mask
	rol	dl,1
	jc	@F
	loop	cx_rop_7_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	cx_rop_7_loop

	ret
color_xpar_rop_7 endp
;--------------------------------------------------------------------
color_xpar_rop_8 proc
cx_rop_8_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes
cx_rop_8_inner:
	test	dh,dh
	jns	@F	; if MSB is clear, this is a transparent pixel
	;perform rop
	mov	al,ss:[si]
	and	es:[di],al
@@:	inc	di
	call	colour_check_bank
	inc	si
	dec	bh
	jnz	cx_rop_8_inner

	rol	dh,1	; move onto next bit of transparent mask
	rol	dl,1
	jc	@F
	loop	cx_rop_8_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	cx_rop_8_loop

	ret
color_xpar_rop_8 endp
;--------------------------------------------------------------------
color_xpar_rop_9 proc
cx_rop_9_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes
cx_rop_9_inner:
	test	dh,dh
	jns	@F	; if MSB is clear, this is a transparent pixel
	;perform rop
	mov	al,ss:[si]
	not	al
	xor	es:[di],al
@@:	inc	di
	call	colour_check_bank
	inc	si
	dec	bh
	jnz	cx_rop_9_inner

	rol	dh,1	; move onto next bit of transparent mask
	rol	dl,1
	jc	@F
	loop	cx_rop_9_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
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
	mov	bh,bl
	shr	bh,3	; BH := pxbytes
cx_rop_b_inner:
	test	dh,dh
	jns	@F	; if MSB is clear, this is a transparent pixel
	;perform rop
	mov	al,ss:[si]
	not	al
	or	es:[di],al

@@:	inc	di
	call	colour_check_bank
	inc	si
	dec	bh
	jnz	cx_rop_b_inner

	rol	dh,1	; move onto next bit of transparent mask
	rol	dl,1
	jc	@F
	loop	cx_rop_b_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	cx_rop_b_loop

	ret
color_xpar_rop_b endp
;--------------------------------------------------------------------
color_xpar_rop_c proc
cx_rop_c_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes
cx_rop_c_inner:
	test	dh,dh
	jns	@F	; if MSB is clear, this is a transparent pixel
	;perform rop
	mov	al,ss:[si]
	mov	es:[di],al
@@:	inc	di
	call	colour_check_bank
	inc	si
	dec	bh
	jnz	cx_rop_c_inner

	rol	dh,1	; move onto next bit of transparent mask
	rol	dl,1
	jc	@F
	loop	cx_rop_c_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	cx_rop_c_loop

	ret
color_xpar_rop_c endp
;--------------------------------------------------------------------
color_xpar_rop_d proc
cx_rop_d_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes
cx_rop_d_inner:
	test	dh,dh
	jns	@F	; if MSB is clear, this is a transparent pixel
	;perform rop
	mov	al,ss:[si]
	not	BYTE PTR es:[di]
	or	es:[di],al

@@:	inc	di
	call	colour_check_bank
	inc	si
	dec	bh
	jnz	cx_rop_d_inner

	rol	dh,1	; move onto next bit of transparent mask
	rol	dl,1
	jc	@F
	loop	cx_rop_d_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	cx_rop_d_loop

	ret
color_xpar_rop_d endp
;--------------------------------------------------------------------
color_xpar_rop_e proc
cx_rop_e_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes
cx_rop_e_inner:
	test	dh,dh
	jns	@F	; if MSB is clear, this is a transparent pixel
	;perform rop
	mov	al,ss:[si]
	or	es:[di],al
@@:	inc	di
	call	colour_check_bank
	inc	si
	dec	bh
	jnz	cx_rop_e_inner

	rol	dh,1	; move onto next bit of transparent mask
	rol	dl,1
	jc	@F
	loop	cx_rop_e_loop
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	cx_rop_e_loop

	ret
color_xpar_rop_e endp
;--------------------------------------------------------------------
color_xpar_rop_f proc
	shr	bl,3	; BL := pxbytes
	mov	al,0ffh
	; remaining logic is identical to rop 0
	jmp	cx_rop_0_loop
color_xpar_rop_f endp

;--------------------------------------------------------------------
; Masked colour rop inner loops (only 7 and D) - Opaque first
;
; entry:
;   es:di -> destination bitmap (or screen)
;   ss:si -> color pattern ( already set to correct byte of pattern for
;			     this starting x)
;   ss:ax -> colour mask (size == BX SHR 3)
;   bx = pattern pitch (8, 16, 24 or 32)
;   cx = count in PIXELS (guaranteed not zero)
;   dh = current xpar mask ( already rotated )
;   dl = rotating bit to keep track of pattern byte
;
;
;--------------------------------------------------------------------
colour_opaque_rop_7_masked proc

	push	bp
	mov	bp,ax

co_rop_7_masked_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes

	push	bp
@@:	lods	byte PTR ss:[si]
	and	es:[di],al
	not	BYTE PTR es:[di]
	mov	al,[bp]
	and	es:[di],al
	inc	di
	call	colour_check_bank
	inc	bp
	dec	bh
	jnz	@B
	pop	bp

	rol	dl,1
	jc	@F
	loop	co_rop_7_masked_loop

	pop	bp
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	co_rop_7_masked_loop

	pop	bp
	ret
colour_opaque_rop_7_masked endp
;--------------------------------------------------------------------
colour_opaque_rop_d_masked proc

	push	bp
	mov	bp,ax

co_rop_d_masked_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes

	push	bp
@@:	lods	byte PTR ss:[si]
	not	BYTE PTR es:[di]
	or	es:[di],al
	mov	al,[bp]
	and	es:[di],al
	inc	di
	call	colour_check_bank
	inc	bp
	dec	bh
	jnz	@B
	pop	bp

	rol	dl,1
	jc	@F
	loop	co_rop_d_masked_loop

	pop	bp
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	co_rop_d_masked_loop

	pop	bp
	ret
colour_opaque_rop_d_masked endp

;--------------------------------------------------------------------
; Masked colour rop inner loops (only 7 and D) - Transparent
;
; entry:
;   es:di -> destination bitmap (or screen)
;   ss:si -> color pattern ( already set to correct byte of pattern for
;			     this starting x)
;   ss:ax -> colour mask (size == BX SHR 3)
;   bx = pattern pitch (8, 16, 24 or 32)
;   cx = count in PIXELS (guaranteed not zero)
;   dh = current xpar mask ( already rotated )
;   dl = rotating bit to keep track of pattern byte
;
;
;--------------------------------------------------------------------
colour_xpar_rop_7_masked proc
	push	bp
	mov	bp,ax

cx_rop_7_masked_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes

	push	bp
cx_rop_7_masked_inner:
	test	dh,dh
	jns	@F	; if MSB is clear, this is a transparent pixel
	;perform rop
	mov	al,ss:[si]
	and	es:[di],al
	not	BYTE PTR es:[di]
	mov	al,[bp]
	and	es:[di],al
@@:	inc	di
	call	colour_check_bank
	inc	si
	inc	bp
	dec	bh
	jnz	cx_rop_7_masked_inner
	pop	bp

	rol	dh,1	; move onto next bit of transparent mask
	rol	dl,1
	jc	@F
	loop	cx_rop_7_masked_loop

	pop	bp
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	cx_rop_7_masked_loop

	pop	bp
	ret
colour_xpar_rop_7_masked endp
;--------------------------------------------------------------------
colour_xpar_rop_d_masked proc
	push	bp
	mov	bp,ax

cx_rop_d_masked_loop:
	mov	bh,bl
	shr	bh,3	; BH := pxbytes

	push	bp
cx_rop_d_masked_inner:
	test	dh,dh
	jns	@F	; if MSB is clear, this is a transparent pixel
	;perform rop
	mov	al,ss:[si]
	not	BYTE PTR es:[di]
	or	es:[di],al
	mov	al,[bp]
	and	es:[di],al

@@:	inc	di
	call	colour_check_bank
	inc	si
	inc	bp
	dec	bh
	jnz	cx_rop_d_masked_inner
	pop	bp

	rol	dh,1	; move onto next bit of transparent mask
	rol	dl,1
	jc	@F
	loop	cx_rop_d_masked_loop

	pop	bp
	ret

	;update pattern pointer (BH == 0 if we're here)
@@:	sub	si,bx
	loop	cx_rop_d_masked_loop

	pop	bp
	ret
colour_xpar_rop_d_masked endp

;--------------------------------------------------------------------
; Check if DI has crossed a segment boundary and update bank
; (this is always valid since internal colour bitmaps don't have
;  scanlines crossing segment boundaries unless they are the screen)
;
; entry:
;   ZF = set if DI has wrapped, clear otherwise
;
;
;--------------------------------------------------------------------
colour_check_bank proc near
	jz	@F
	ret
@@:
	push	ds
	push	dx
        mov     dx,DataBASE
	mov	ds,dx
	assumes ds,Data
	mov	dl,[bank_select_byte]
	inc	dl
	SET_BANK
	pop	dx
	pop	ds
	assumes	ds,nothing
	ret
colour_check_bank endp
