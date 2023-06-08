;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.
;-----------------------------------------------------------------------
; Handles monochrome bitmap scanline calls for rop = ?
;
;   entry:
;	ah = current_mono_pattern
;	bl = left edge mask
;	bh = right edge mask
;	cx = inner loop count
;	es:[di] --> first byte
;	current_mono_pattern = the color of bits to put in (pre-rotated!!)
;   exit:
;-----------------------------------------------------------------------
mono_opaque_rop_0   proc
	; handle the left edge
	not	bl
	and	es:[di],bl
	inc	di

@@:	; handle the inner loop
	xor	al,al
	rep	stosb

	; handle the last byte
	or	bh,bh
	jz	@F
	; perform the rop
	not	bh
	and	es:[di],bh

@@:	; all done - I'm out'a here
	ret
mono_opaque_rop_0   endp
;-----------------------------------------------------------------------

mono_opaque_rop_1   proc
	not	ah
	mov	dx	,bx
	not	dx

	; handle the left edge
	xor	es:[di],bl
	or	dl	,ah
	and	es:[di] ,dl
	inc	di

	jcxz	@F
orop_1_loop:
	not	BYTE PTR es:[di]
	and	BYTE PTR es:[di],ah
	inc	di
	loop	orop_1_loop

@@:	; handle the last byte
	or	bh,bh
	jz	@F
	; perform the rop
	xor	es:[di],bh
	or	dh	,ah
	and	es:[di] ,dh

@@:	; all done - I'm out'a here
	ret
mono_opaque_rop_1   endp
;-----------------------------------------------------------------------

mono_opaque_rop_2   proc
	not	ah			; not the pattern

	; handle the left edge
	not	bl
	or	bl,ah
	and	es:[di],bl
	inc	di

	jcxz	@F
orop_2_loop:
	and	es:[di],ah
	inc	di
	loop	orop_2_loop
@@:
	; handle the last byte
	or	bh,bh
	jz	@F
	; perform the rop
	not	bh
	or	bh,ah
	and	es:[di],bh

@@:	; all done - I'm out'a here
	ret
mono_opaque_rop_2   endp
;-----------------------------------------------------------------------

mono_opaque_rop_3   proc
	mov	dx,bx
	not	dx
	not	ah

	; handle the left edge
	mov	al,es:[di]
	and	al,dl
	and	bl,ah
	or	al,bl
	stosb

	mov	al,ah
	rep	stosb

	; handle the last byte
	or	bh,bh
	jz	@F
	; perform the rop
	mov	al,es:[di]
	and	al,dh
	and	bh,ah
	or	al,bh
	stosb

@@:	; all done - I'm out'a here
	ret
mono_opaque_rop_3   endp
;-----------------------------------------------------------------------

mono_opaque_rop_4   proc
	mov	dx,bx
	not	dx

	; handle the left edge
	mov	al,es:[di]
	xor	al,bl
	or	dl,ah
	and	al,dl
	stosb

	; handle the inner loop
	jcxz	@F
orop_4_loop:
	mov	al,es:[di]
	not	al
	and	al,ah
	stosb
	loop	orop_4_loop

@@:
	; handle the last byte
	or	bh,bh
	jz	@F
	; perform the rop
	mov	al,es:[di]
	xor	al,bh
	or	dh,ah
	and	al,dh
	stosb

@@:	; all done - I'm out'a here
	ret
mono_opaque_rop_4   endp
;-----------------------------------------------------------------------

mono_opaque_rop_5   proc
	; handle the left edge
	xor	es:[di],bl
	inc	di

	; handle the inner loop
	jcxz	@F
orop_5_loop:
	not	BYTE PTR es:[di]
	inc	di
	loop	orop_5_loop

@@:	; handle the last byte
	or	bh,bh
	jz	@F
	; perform the rop
	xor	es:[di],bh

@@:	; all done - I'm out'a here
	ret
mono_opaque_rop_5   endp
;-----------------------------------------------------------------------

mono_opaque_rop_6   proc
	; handle the left edge
	and	bl,ah
	xor	es:[di],bl
	inc	di

	; handle the inner loop
	jcxz	@F
orop_6_loop:
	xor	es:[di],ah
	inc	di
	loop	orop_6_loop

@@:	; handle the last byte
	or	bh,bh
	jz	@F
	; perform the rop
	and	bh,ah
	xor	es:[di],bh

@@:	; all done - I'm out'a here
	ret
mono_opaque_rop_6   endp
;-----------------------------------------------------------------------

mono_opaque_rop_7   proc
	mov	dx,bx
	not	dx

	; handle the left edge
	mov	al,es:[di]
	or	dl,ah
	and	al,dl
	xor	al,bl
	stosb

	; handle the inner loop
	jcxz	@F
orop_7_loop:
	mov	al,es:[di]
	and	al,ah
	not	al
	stosb
	loop	orop_7_loop

@@:	; handle the last byte
	or	bh,bh
	jz	@F
	; perform the rop
	mov	al,es:[di]
	or	dh,ah
	and	al,dh
	xor	al,bh
	stosb

@@:	; all done - I'm out'a here
	ret
mono_opaque_rop_7   endp
;-----------------------------------------------------------------------

mono_opaque_rop_8   proc
	mov	dx,bx
	not	dx

	; handle the left edge
	or	dl,ah
	and	es:[di],dl
	inc	di

	; handle the inner loop
	jcxz	@F
orop_8_loop:
	and	es:[di],ah
	inc	di
	loop	orop_8_loop

@@:	; handle the last byte
	or	bh,bh
	jz	@F
	; perform the rop
	or	dh,ah
	and	es:[di],dh

@@:	; all done - I'm out'a here
	ret
mono_opaque_rop_8   endp
;-----------------------------------------------------------------------

mono_opaque_rop_9   proc
	not	ah

	; handle the left edge
	and	bl,ah
	xor	es:[di],bl
	inc	di

	; handle the inner loop
	jcxz	@F
orop_9_loop:
	xor	es:[di],ah
	inc	di
	loop	orop_9_loop

@@:	; handle the last byte
	or	bh,bh
	jz	@F
	; perform the rop
	and	bh,ah
	xor	es:[di],bh

@@:	; all done - I'm out'a here
	ret
mono_opaque_rop_9   endp
;-----------------------------------------------------------------------

mono_opaque_rop_a   proc
	ret
mono_opaque_rop_a   endp
;-----------------------------------------------------------------------

mono_opaque_rop_b   proc
	not	ah

	; handle the left edge
	and	bl,ah
	or	es:[di],bl
	inc	di

	; handle the inner loop
	jcxz	@F
orop_b_loop:
	or	es:[di],ah
	inc	di
	loop	orop_b_loop

@@:	; handle the last byte
	or	bh,bh
	jz	@F
	; perform the rop
	and	bh,ah
	or	es:[di],bh

@@:	; all done - I'm out'a here
	ret
mono_opaque_rop_b   endp
;-----------------------------------------------------------------------

mono_opaque_rop_c   proc
	mov	dx,bx
	not	dx

	; handle the left edge
	mov	al,es:[di]
	and	al,dl
	and	bl,ah
	or	al,bl
	stosb

	; handle the inner loop
	mov	al,ah
	rep	stosb

	; handle the last byte
	or	bh,bh
	jz	@F
	; perform the rop
	mov	al,es:[di]
	and	al,dh
	and	bh,ah
	or	al,bh
	stosb

@@:	; all done - I'm out'a here
	ret
mono_opaque_rop_c   endp
;-----------------------------------------------------------------------

mono_opaque_rop_d   proc
	mov	dx,bx
	not	dx

	; handle the left edge
	mov	al,es:[di]
	xor	al,bl
	and	bl,ah
	or	al,bl
	stosb

	; handle the inner loop
	jcxz	@F
orop_d_loop:
	mov	al,es:[di]
	not	al
	or	al,ah
	stosb
	loop	orop_d_loop

@@:	; handle the last byte
	or	bh,bh
	jz	@F
	; perform the rop
	mov	al,es:[di]
	xor	al,bh
	and	bh,ah
	or	al,bh
	stosb

@@:	; all done - I'm out'a here
	ret
mono_opaque_rop_d   endp
;-----------------------------------------------------------------------

mono_opaque_rop_e   proc

	; handle the left edge
	and	bl,ah
	or	es:[di],bl
	inc	di

	; handle the inner loop
	jcxz	@F
orop_e_loop:
	or	es:[di],ah
	inc	di
	loop	orop_e_loop

@@:	; handle the last byte
	or	bh,bh
	jz	@F
	; perform the rop
	and	bh,ah
	or	es:[di],bh

@@:	; all done - I'm out'a here
	ret
mono_opaque_rop_e   endp
;-----------------------------------------------------------------------

mono_opaque_rop_f   proc
	; handle the left edge
	or	es:[di],bl
	inc	di

	; handle the inner loop
	mov	al	,0FFH
	rep	stosb

	; handle the last byte
	or	bh,bh
	jz	@F
	; perform the rop
	or	es:[di],bh

@@:	; all done - I'm out'a here
	ret
mono_opaque_rop_f   endp
;-----------------------------------------------------------------------

;-----------------------------------------------------------------------
; Handles monochrome bitmap scanline calls for rop = ?
;
;   entry:
;	FLAGS = are set here according to the and that created ah
;	ah = current_mono_pattern AND current_xpar_mask
;	bl = left edge mask
;	bh = right edge mask
;	cx = inner loop count
;	es:[di] --> first byte
;	current_mono_pattern = the color of bits to put in (pre-rotated!!)
;	current_xpar_mask = the bits to affect ( one bits are opaque)
;   exit:
;-----------------------------------------------------------------------
mono_xpar_rop_0   proc
	mov	ah, current_xpar_mask
mono_xpar_rop_0_alt:
	not	ah

	; Left Edge
	not	bl
	or	bl,ah
	and	es:[di],bl
	inc	di

	; Middle - ie full bytes
	jcxz	@F
xrop_0_loop:
	and	es:[di],ah
	inc	di
	loop	xrop_0_loop

@@:	; Right Edge
	or	bh,bh
	jz	@F
        not     bh
	or	bh,ah
	and	es:[di],bh
@@:
	ret
mono_xpar_rop_0   endp
;-----------------------------------------------------------------------
mono_xpar_rop_5   proc
	mov	ah,current_xpar_mask
mono_xpar_rop_5_alt:

	; handle left edge
	and	bl,ah
	xor	es:[di],bl
	inc	di

	; handle inner loop
	jcxz	@F
xrop_5_loop:
	xor	es:[di],ah
	inc	di
	loop	xrop_5_loop

@@:	; handle right edge
	or	bh,bh
	jz	@F

	and	bh,ah
	xor	es:[di],bh
@@:
	ret
mono_xpar_rop_5   endp
;-----------------------------------------------------------------------
mono_xpar_rop_f   proc
	mov	ah, current_xpar_mask
mono_xpar_rop_f_alt:

	; Left Edge
	and	bl,ah
	or	es:[di],bl
	inc	di

	; Middle - ie full bytes
	jcxz	@F
xrop_f_loop:
	or	es:[di],ah
	inc	di
	loop	xrop_f_loop

@@:	; Right Edge
	or	bh,bh
	jz	@F
	and	bh,ah
	or	es:[di],bh
@@:
	ret
mono_xpar_rop_f   endp
;-----------------------------------------------------------------------
mono_xpar_rop_1   proc
	jz	mono_xpar_rop_5
	jmp	short mono_xpar_rop_0
mono_xpar_rop_1   endp
;-----------------------------------------------------------------------
mono_xpar_rop_2   proc
	jz	mono_xpar_rop_a
	jmp	short mono_xpar_rop_0
mono_xpar_rop_2   endp
;-----------------------------------------------------------------------
mono_xpar_rop_3   proc
	jz	mono_xpar_rop_f
	jmp	short mono_xpar_rop_0
mono_xpar_rop_3   endp
;-----------------------------------------------------------------------
mono_xpar_rop_4   proc
	jz	mono_xpar_rop_0
	jmp	short mono_xpar_rop_5
mono_xpar_rop_4   endp
;-----------------------------------------------------------------------
mono_xpar_rop_6   proc
	jnz	short mono_xpar_rop_5
	ret
mono_xpar_rop_6   endp
;-----------------------------------------------------------------------
mono_xpar_rop_7   proc
	jz	mono_xpar_rop_f
	jmp	mono_xpar_rop_5
mono_xpar_rop_7   endp
;-----------------------------------------------------------------------
mono_xpar_rop_8   proc
	jz	mono_xpar_rop_0
	ret
mono_xpar_rop_8   endp
;-----------------------------------------------------------------------
mono_xpar_rop_9   proc
	jz	mono_xpar_rop_5
mono_xpar_rop_a:
	ret
mono_xpar_rop_9   endp
;-----------------------------------------------------------------------
mono_xpar_rop_b   proc
	jz	mono_xpar_rop_f
	ret
mono_xpar_rop_b   endp
;-----------------------------------------------------------------------
mono_xpar_rop_c   proc
	jz	mono_xpar_rop_0
	jmp	short mono_xpar_rop_f
mono_xpar_rop_c   endp
;-----------------------------------------------------------------------
mono_xpar_rop_d   proc
	jz	mono_xpar_rop_5
	jmp	short mono_xpar_rop_f
mono_xpar_rop_d   endp
;-----------------------------------------------------------------------
mono_xpar_rop_e   proc
	jnz	mono_xpar_rop_f
	ret
mono_xpar_rop_e   endp
