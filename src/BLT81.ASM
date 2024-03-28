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
	mov	src_blt_offset,ax
	mov	src_page,dx
	clc
	call	set_page
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

ctom_template:
	mov	ah,0FFH 		;0FFH will become (DestxOrg & 07H)
ctom_fix:
@@:	lodsb
	sub	al,0FFH 		;0FFH will become bgcolor
ctom_color:
	cmp	al,1
	rcl	ah,1
	jnc	@B
	mov	al,ah

CTOM_SIZE = $ - ctom_template
CTOM_FIXUP = $ - ctom_fix + 1
CTOM_COLOR = $ - ctom_color + 1

PUBLIC	compile_ctom
compile_ctom	PROC	NEAR

	test	rop_flags,SOURCE_PRESENT
	je	@F
	mov	cx,CTOM_SIZE
	lea	si,ctom_template
	rep	movs byte ptr es:[di], cs:[si]
	mov	es:[di - CTOM_FIXUP],al
	mov	al,byte ptr [colors+1]			;get the bgcolor
	mov	es:[di - CTOM_COLOR],al

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

ctomle_template:
	mov	cx,01234H	;01234H becomes ax parm
ctomle_fix:
@@:	lodsb
	sub	al,04H		;04H will become bgcolor
ctomle_color:
	cmp	al,1
	rcl	ah,1
	loop	@B
	mov	al,ah
	rol	al,04		;04H becomes align_rotate_count
ctomle_rot:

CTOMLE_SIZE = $ - ctomle_template
CTOMLE_FIXUP = $ - ctomle_fix + 2
CTOMLE_COLOR = $ - ctomle_color + 1
CTOMLE_ROT = $ - ctomle_rot + 1

PUBLIC	compile_ctom_last_edge
compile_ctom_last_edge	PROC	NEAR

	test	rop_flags,SOURCE_PRESENT
	je	@F
	mov	cx,CTOMLE_SIZE
	lea	si,ctomle_template
	rep	movs byte ptr es:[di], cs:[si]
	mov	es:[di - CTOMLE_FIXUP],ax
	mov	al,byte ptr [colors+1]			;get the bgcolor
	mov	es:[di - CTOMLE_COLOR],al
	mov	al,align_rotate_count
	mov	es:[di - CTOMLE_ROT],al

@@:	call	compile_rop
	ret

compile_ctom_last_edge	ENDP

sEnd    CODE

END

