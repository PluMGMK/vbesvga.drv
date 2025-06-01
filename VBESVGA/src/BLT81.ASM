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
include compblt.inc


.286
sBegin	Code
assumes cs,Code
assumes ds,Nothing
assumes es,Nothing
assumes ss,Nothing

externW	pxbytes	;in SWCURS.ASM
externW	_cstods ;in CURSOR.ASM

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

	test	rop_flags,SOURCE_PRESENT
	jz	@F
	call	compile_ctom_subroutine

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
;	compile_ctom_subroutine
;
;	Create a subroutine on the stack that checks the next byte in the
;	source against a background colour byte in AL, and accumulates
;	the result in BH, taking care of bank crossings if necessary
;

ctom_subrtn_template:
	test	bh,bh
	jnz	@F			;we already know it's not a match!
	cmp	al,[si]			;AL set by caller
	je	@F
	inc	bh			;use BH as scratch reg to indicate mismatch
@@:	inc	si			;sets ZF if we wrap

CTOM_SUBRTN_SIZE = $ - ctom_subrtn_template

ctom_subrtn_bankcross:
	jnz	@F			;ZF set/unset by "INC SI" directly above
	mov	dx,ss:[1234H]		;1234H becomes offset of src_page
subbc1:	inc	dx
	mov	ss:[1234H],dx		;1234H becomes offset of src_page
subbc2: call	far_set_bank_select
@@:

CTOM_SUBRTN_BANKCROSS_SIZE = $ - ctom_subrtn_bankcross
CTOM_SUBRTN_BANKPTR1 = $ - subbc1 + 2
CTOM_SUBRTN_BANKPTR2 = $ - subbc2 + 2

compile_ctom_subroutine	PROC	NEAR
	call	compile_begin_subroutine
	mov	bx,di	; for compile_end_subroutine below

	mov	cx,CTOM_SUBRTN_SIZE
	lea	si,ctom_subrtn_template
	rep	movs byte ptr es:[di], cs:[si]

	test	[device_flags],DEVFLAG_SRC_SCAN_X_SEG
	jz	@F
	mov	cx,CTOM_SUBRTN_BANKCROSS_SIZE
	lea	si,ctom_subrtn_bankcross
	rep	movs byte ptr es:[di], cs:[si]
	lea	ax,src_page
	mov	es:[di - CTOM_SUBRTN_BANKPTR1],ax
	mov	es:[di - CTOM_SUBRTN_BANKPTR2],ax

@@:	; BX was set above...
	mov	[any_jmp_address],bx
	call	compile_end_subroutine
	ret
compile_ctom_subroutine	ENDP

;
;	compile_ctom
;
;	A few things to note. First the blt will always go from left to right
;	then top to bottom (blt is X+Y+); Since a color and mono bitmap will
;	never be the same device, they cannot overlap.
;	Secondly, except for startup conditions, the same code is used for
;	the left edge and the inner loop. Unfortunately, because of single
;	byte dst blt problem, slightly different code must be used for the
;	right edge.
;
;	PARMS:
;	AL	initial value for rotating bit counter
;

ctom_template_setup:
	mov	ah,0FFH 		;0FFH will become 1 SHL (DestxOrg & 07H)
ctom_fix:
	xor	bh,bh			;initialize scratch register

CTOM_SETUP_SIZE = $ - ctom_template_setup
CTOM_FIXUP = $ - ctom_fix + 1
CTOM_SCRATCHINIT = $ - ctom_fix

ctom_template_getbyte:
	mov	al,0FFH 		;0FFH will become bgcolor
ctom_color:
	call	compile_ctom		;this will become our compiled sub
ctom_call_fix:

CTOM_GETBYTE_SIZE = $ - ctom_template_getbyte
CTOM_COLOR = $ - ctom_color + 1
CTOM_CALL_FIX = $ - ctom_call_fix

ctom_template_setbit:
@@:	cmp	bh,1			;set CF iff scratch register == 0
	rcl	ah,1
	jnc	@B			;@B becomes ctom_template_getbyte
ctom_jnc_back:
	mov	al,ah

CTOM_SETBIT_SIZE = $ - ctom_template_setbit
CTOM_JNC_BACK = $ - ctom_jnc_back

PUBLIC	compile_ctom
compile_ctom	PROC	NEAR

	test	rop_flags,SOURCE_PRESENT
	jz	ctom_no_source

@@:	mov	cx,CTOM_SETUP_SIZE
	lea	si,ctom_template_setup
	rep	movs byte ptr es:[di], cs:[si]
	mov	es:[di - CTOM_FIXUP],al
	lea	ax,[di - CTOM_SCRATCHINIT]
	push	ax	;save address to jump back to

	mov	cx,[pxbytes]
	xor	dx,dx	;initialize index into bgcolour
ctom_colour_byte_loop:
	mov	bx,cx
	mov	cx,CTOM_GETBYTE_SIZE
	lea	si,ctom_template_getbyte
	rep	movs byte ptr es:[di], cs:[si]
	mov	cx,bx
	mov	si,dx
	mov	al,bgcolour[si]
	mov	es:[di - CTOM_COLOR],al
	;fixup the near call:
	lea	ax,[di - CTOM_CALL_FIX]
	neg	ax
	add	ax,[any_jmp_address]
	mov	es:[di - CTOM_CALL_FIX - 2],ax
	inc	dx
	loop	ctom_colour_byte_loop

	mov	cx,CTOM_SETBIT_SIZE
	lea	si,ctom_template_setbit
	rep	movs byte ptr es:[di], cs:[si]

	pop	ax			;get back the address to jump back to
	lea	bx,[di - CTOM_JNC_BACK]
	sub	ax,bx
	mov	es:[bx - 1],al

ctom_no_source:
	call	compile_rop
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
	xor	bh,bh		;initialize scratch register

CTOMLE_SETUP_SIZE = $ - ctomle_template_setup
CTOMLE_FIXUP = $ - ctomle_fix + 2
CTOMLE_SCRATCHINIT = $ - ctomle_fix

ctomle_template_setbit:
@@:	cmp	bh,1		;set CF iff scratch register == 0
	rcl	ah,1
	loop	@B
ctomle_loop_back:
	mov	al,ah
	rol	al,04		;04H becomes align_rotate_count
ctomle_rot:

CTOMLE_SETBIT_SIZE = $ - ctomle_template_setbit
CTOMLE_LOOP_BACK = $ - ctomle_loop_back
CTOMLE_ROT = $ - ctomle_rot + 1

PUBLIC	compile_ctom_last_edge
compile_ctom_last_edge	PROC	NEAR

	test	rop_flags,SOURCE_PRESENT
	jz	ctomle_no_source

@@:	mov	cx,CTOMLE_SETUP_SIZE
	lea	si,ctomle_template_setup
	rep	movs byte ptr es:[di], cs:[si]
	mov	es:[di - CTOMLE_FIXUP],ax
	lea	ax,[di - CTOMLE_SCRATCHINIT]
	push	ax	;save address to jump back to

	mov	cx,[pxbytes]
	xor	dx,dx	;initialize index into bgcolour
ctomle_colour_byte_loop:
	mov	bx,cx
	mov	cx,CTOM_GETBYTE_SIZE
	lea	si,ctom_template_getbyte
	rep	movs byte ptr es:[di], cs:[si]
	mov	cx,bx
	mov	si,dx
	mov	al,bgcolour[si]
	mov	es:[di - CTOM_COLOR],al
	;fixup the near call:
	lea	ax,[di - CTOM_CALL_FIX]
	neg	ax
	add	ax,[any_jmp_address]
	mov	es:[di - CTOM_CALL_FIX - 2],ax
	inc	dx
	loop	ctomle_colour_byte_loop

	mov	cx,CTOMLE_SETBIT_SIZE
	lea	si,ctomle_template_setbit
	rep	movs byte ptr es:[di], cs:[si]

	pop	ax			;get back the address to jump back to
	lea	bx,[di - CTOMLE_LOOP_BACK]
	sub	ax,bx
	mov	es:[bx - 1],al
	mov	al,align_rotate_count
	mov	es:[di - CTOMLE_ROT],al

ctomle_no_source:
	call	compile_rop
	ret

compile_ctom_last_edge	ENDP

sEnd    CODE

END

