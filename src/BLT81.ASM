;
;	FILE:	blt81.asm
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module contains routines that deal with mono to color blts.
;

SRCFILE_BLT81	equ	1
incLogical	=	1
incDrawmode	=	1

include cmacros.inc
include gdidefs.inc
include macros.mac
include njumps.mac
include genconst.inc
include bitblt.var
include bblt.inc
include bltutil.inc
include vgautil.inc
include compblt.inc


.286
sBegin	Code
assumes cs,Code
assumes ds,Nothing
assumes es,Nothing
assumes ss,Nothing

externW	pxbytes	;in SWCURS.ASM

;
;	blt81
;
;

PUBLIC	blt81
blt81	PROC	NEAR

	call	blt_ctom_prep

	test	rop_flags,PATTERN_PRESENT	;compile the pattern code
	je	@F				; if a pattern is used
	call	compile_mono_pattern_fetch

@@:	cmp	first_edge_mask, 0FF00H 	;if no first edge mask
	je	@F				; then move on
	mov	cx,DestxOrg			;get rotating bit counter
	and	cl,07H				; to correct position
	mov	al,1
	rol	al,cl
	call	compile_ctom
	mov	ax,first_edge_mask
	call	compile_edge_mask

@@:	cmp	word ptr inner_loop_count,0
	je	@F
	call	compile_inner_loop_start
	push	di				;save looping address
	mov	al,1				;the rotating bit counter for
	call	compile_ctom			; the inner loop starts at 1
	mov	al,I_STOSB			;now do the old stosb
	stosb
	pop	bx
	call	compile_inner_loop_end		;generate the loop @B
	call	compile_inner_loop_wraps

@@:	mov	ax,8				;compute number of pixels in
	sub	ax,align_rotate_count		; last edge byte
	cmp	word ptr first_edge_mask,0FF00H ; if only 1 byte of dst (namely
	jne	@F				; the right edge) is touched in
	mov	ax,xExt 			; the blt, just use the xExt
@@:	call	compile_ctom_last_edge		; as the count of pixels to mov
	mov	ax,last_edge_mask
	call	compile_edge_mask

	call	compile_outer_loop

	test	word ptr rop_flags,SOURCE_PRESENT
	je	src_update_done
	test	word ptr device_flags,DEVFLAG_SRC_SCREEN
        jne     @F
	call	compile_src_memory_yupdate
	jmp	short src_update_done
@@:	call	compile_src_screen_yupdate

src_update_done:
	call	compile_dst_memory_yupdate
	call	compile_jmp_back_to_start
	ret

blt81	ENDP		       ;

;
;	blt_ctom_prep
;
;

PUBLIC	blt_ctom_prep
blt_ctom_prep	PROC	NEAR

	test	word ptr device_flags,DEVFLAG_SRC_SCREEN
	je	@F
	mov	ax,SrcyOrg
	mov	bx,SrcxOrg
	mul	word ptr src_width_bytes
	add	ax,bx
	adc	dx,0
	mov	src_blt_offset,ax
	mov	src_page,dx
	SET_BANK
@@:	ret

blt_ctom_prep	ENDP				;

;
;	compile_ctom
;
;	A few things to note. First the blt will always go from left to right
;	then top to bottom (blt is X+Y+); Since a color and mono bitmap will
;	never be the same device, they cannot overlap.
;	Secondly, except for startup conditions, the same code is used for
;	the left edge and the inner loop. Unfortunately, because of single
;	byte dst blt problesm, slightly different code must be used for the
;	right edge.
;
;	PARMS:
;	AL	initial value for rotating bit counter
;

ctom_template_setup:
	mov	ah,0FFH 		;0FFH will become (DestxOrg & 07H)
ctom_fix:

CTOM_SETUP_SIZE = $ - ctom_template_setup
CTOM_FIXUP = $ - ctom_fix + 1

ctom_template_getbyte:
@@:	mov	al,[si+1234H]		;1234H will become the current index
ctom_index:
	sub	al,0FFH 		;0FFH will become bgcolor
ctom_color:
	cmp	al,1
	jnc	@F
ctom_jnc_forward:

CTOM_GETBYTE_SIZE = $ - ctom_template_getbyte
CTOM_INDEX = $ - ctom_index + 2
CTOM_COLOR = $ - ctom_color + 1
CTOM_JNC_FORWARD = $ - ctom_jnc_forward

ctom_template_setbit:
@@:	rcl	ah,1
	lea	si,[si+1234H]		;1234H will become pxbytes
ctom_si_step:
	jnc	@B
ctom_jnc_back:
	mov	al,ah

CTOM_SETBIT_SIZE = $ - ctom_template_setbit
CTOM_SI_STEP = $ - ctom_si_step + 2
CTOM_JNC_BACK = $ - ctom_jnc_back

PUBLIC	compile_ctom
compile_ctom	PROC	NEAR

	test	rop_flags,SOURCE_PRESENT
	je	@F
	mov	cx,CTOM_SETUP_SIZE
	lea	si,ctom_template_setup
	rep	movs byte ptr es:[di], cs:[si]
	mov	es:[di - CTOM_FIXUP],al
	push	di	;save address to jump back to

	mov	cx,[pxbytes]
	xor	dx,dx	;initialize index into bgcolour
ctom_colour_byte_loop:
	mov	bx,cx
	mov	cx,CTOM_GETBYTE_SIZE
	lea	si,ctom_template_getbyte
	rep	movs byte ptr es:[di], cs:[si]
	mov	cx,bx
	mov	si,dx
	mov	es:[di - CTOM_INDEX],si
	mov	al,bgcolour[si]
	mov	es:[di - CTOM_COLOR],al
	inc	dx
	loop	ctom_colour_byte_loop

	;At this point, we have DX JNCs to fixup to point at our current
	; position. In fact, the last JNC is redundant since it would just
	; jump here anyway: get rid of it!
	sub	di,2	;size of 286 JNC instruction is always two bytes
	dec	dx	;count the number of JNCs that remain (may be zero)
	jz	ctom_forward_jncs_done
	;Point BX at the most recent JNC (+2 is to comp for the SUB above)
	lea	bx,[di + 2 - CTOM_GETBYTE_SIZE - CTOM_JNC_FORWARD]
	mov	cx,dx
ctom_forward_jncs_loop:
	mov	ax,di
	sub	ax,bx
	mov	es:[bx - 1],al
	sub	bx,CTOM_GETBYTE_SIZE	;point at the one before that, if any...
	loop	ctom_forward_jncs_loop

ctom_forward_jncs_done:
	mov	cx,CTOM_SETBIT_SIZE
	lea	si,ctom_template_setbit
	rep	movs byte ptr es:[di], cs:[si]
	pop	ax			;get back the address to jump back to
	lea	bx,[di - CTOM_JNC_BACK]
	sub	ax,bx
	mov	es:[bx - 1],al
	inc	dx			;this should still have pxbytes...
	mov	es:[di - CTOM_SI_STEP],dx

@@:	call	compile_rop
	ret

compile_ctom	ENDP

;
;	compile_ctom_last_edge
;
;	A few things to note. First the blt will always go from left to right
;	then top to bottom (blt is X+Y+); Since a color and mono bitmap will
;	never be the same device, they cannot overlap.
;
;	PARMS:
;	AX	# of pixels to do in the last edge (between 1 and 8 inclusive)
;

ctomle_template_setup:
	mov	cx,01234H	;01234H becomes ax parm
ctomle_fix:

CTOMLE_SETUP_SIZE = $ - ctomle_template_setup
CTOMLE_FIXUP = $ - ctomle_fix + 2

ctomle_template_setbit:
	rcl	ah,1
	lea	si,[si+1234H]		;1234H will become pxbytes
ctomle_si_step:
	loop	@B
ctomle_loop_back:
	mov	al,ah
	rol	al,04		;04H becomes align_rotate_count
ctomle_rot:

CTOMLE_SETBIT_SIZE = $ - ctomle_template_setbit
CTOMLE_SI_STEP = $ - ctomle_si_step + 2
CTOMLE_LOOP_BACK = $ - ctomle_loop_back
CTOMLE_ROT = $ - ctomle_rot + 1

PUBLIC	compile_ctom_last_edge
compile_ctom_last_edge	PROC	NEAR

	test	rop_flags,SOURCE_PRESENT
	je	@F
	mov	cx,CTOMLE_SETUP_SIZE
	lea	si,ctomle_template_setup
	rep	movs byte ptr es:[di], cs:[si]
	mov	es:[di - CTOMLE_FIXUP],ax
	push	di	;save address to jump back to

	mov	cx,[pxbytes]
	xor	dx,dx	;initialize index into bgcolour
ctomle_colour_byte_loop:
	mov	bx,cx
	mov	cx,CTOM_GETBYTE_SIZE
	lea	si,ctom_template_getbyte
	rep	movs byte ptr es:[di], cs:[si]
	mov	cx,bx
	mov	si,dx
	mov	es:[di - CTOM_INDEX],si
	mov	al,bgcolour[si]
	mov	es:[di - CTOM_COLOR],al
	inc	dx
	loop	ctomle_colour_byte_loop

	;At this point, we have DX JNCs to fixup to point at our current
	; position. In fact, the last JNC is redundant since it would just
	; jump here anyway: get rid of it!
	sub	di,2	;size of 286 JNC instruction is always two bytes
	dec	dx	;count the number of JNCs that remain (may be zero)
	jz	ctomle_forward_jncs_done
	;Point BX at the most recent JNC (+2 is to comp for the SUB above)
	lea	bx,[di + 2 - CTOM_GETBYTE_SIZE - CTOM_JNC_FORWARD]
	mov	cx,dx
ctomle_forward_jncs_loop:
	mov	ax,di
	sub	ax,bx
	mov	es:[bx - 1],al
	sub	bx,CTOM_GETBYTE_SIZE	;point at the one before that, if any...
	loop	ctomle_forward_jncs_loop

ctomle_forward_jncs_done:
	mov	cx,CTOMLE_SETBIT_SIZE
	lea	si,ctomle_template_setbit
	rep	movs byte ptr es:[di], cs:[si]
	pop	ax			;get back the address to loop back to
	lea	bx,[di - CTOMLE_LOOP_BACK]
	sub	ax,bx
	mov	es:[bx - 1],al
	inc	dx			;this should still have pxbytes...
	mov	es:[di - CTOMLE_SI_STEP],dx
	mov	al,align_rotate_count
	mov	es:[di - CTOMLE_ROT],al

@@:	call	compile_rop
	ret

compile_ctom_last_edge	ENDP

sEnd    CODE

END

