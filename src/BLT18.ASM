;
;	FILE:	blt18.asm
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module contains routines that deal with mono to color blts.
;	March 1, 1991 -- Jim Keller added code to implement multi-media
;	transparent blts.
;

SRCFILE_BLT18	equ	1
incLogical	=	1
incDrawMode	=	1

include cmacros.inc
include gdidefs.inc
include macros.mac
include njumps.mac
include genconst.inc
include bblt.inc
include bitblt.var
include compblt.inc
include vgautil.inc

externA __NEXTSEG

.286
sBegin	Code
assumes cs,Code
assumes ds,Nothing
assumes es,Nothing
assumes ss,Nothing


;
;	blt18
;
;

PUBLIC	blt18
blt18	PROC	NEAR

	call	blt_mtoc_prep

@@:	test	rop_flags,SOURCE_PRESENT	;If there is no src
	je	@F				; then move on
	call	compile_mtoc_src1		;else do it

@@:	test	rop_flags,PATTERN_PRESENT	;compile the pattern code
	je	@F				; if a pattern is used
	call	compile_color_pattern_fetch

@@:	call	compile_rop			;now do the rop
	call	compile_mtoc_loop
	call	compile_outer_loop
	call	compile_src_memory_yupdate

	test	word ptr device_flags,DEVFLAG_DST_SCREEN
	jne	@F
	call	compile_dst_memory_yupdate
	jmp	short update_done
@@:	call	compile_screen_yupdate

update_done:
	test	word ptr rop_flags,PATTERN_PRESENT
	je	@F
	call	compile_pattern_yupdate

@@:	call	compile_jmp_back_to_start
	ret

blt18	ENDP



;
;	blt_mtoc_prep
;
;	Almost all preparation was done before the blt specific routines
;	were called. The only thing that might need to be done here is
;	setting the dst address and page if the dst is the screen.
;

PUBLIC	blt_mtoc_prep
blt_mtoc_prep	PROC	NEAR

	test	word ptr device_flags,DEVFLAG_DST_SCREEN
	je	@F
	mov	ax,DestyOrg		 ; compute the starting address
	mul	word ptr dst_width_bytes
	add	ax,DestxOrg		;fixed for bitness in bitblt_prep_final
        mov     dst_blt_offset,ax
	mov	dst_page,dx
	SET_BANK
@@:	ret

blt_mtoc_prep	ENDP			;

;
;	compile_mtoc_src1
;
;	A few things to note. First the blt will always go from left to right
;	then top to bottom (blt is X+Y+); Since a color and mono bitmap will
;	never be the same device, they cannot overlap.
;

mtoc_src1_template:
	mov	cx,01234H		;01234H will become inner_loop_count
mtoc_src1_inner_loop:
	lodsb
	mov	bl,al
	mov	bh,04H			;04H becomes 1 << (SrcxOrg & 07H)
mtoc_src1_fix0:
	rol	bl,04H			;04H becomes (SrcxOrg & 07H)
mtoc_src1_fix1:
	rol	bl,1
	sbb	ax,ax
	cwd
	and	ax,1234h	 	;1234h will become (fgcolor xor bgcolor)
mtoc_src1_fix2:
	and	dx,1234h		;ditto
mtoc_src1_fix2a:
	xor	ax,1234h		;1234h will become fgcolor
mtoc_src1_fix3:
	xor	dx,1234h		;ditto
mtoc_src1_fix3a:

MTOC_SRC1_LEN = $ - mtoc_src1_template
MTOC_SRC1_INNER_LOOP = $ - mtoc_src1_inner_loop + 2
MTOC_SRC1_FIXUP0 = $ - mtoc_src1_fix0 + 1
MTOC_SRC1_FIXUP1 = $ - mtoc_src1_fix1 + 1
MTOC_SRC1_FIXUP2 = $ - mtoc_src1_fix2 + 2
MTOC_SRC1_FIXUP2A = $ - mtoc_src1_fix2a + 2
MTOC_SRC1_FIXUP3 = $ - mtoc_src1_fix3 + 2
MTOC_SRC1_FIXUP3A = $ - mtoc_src1_fix3a + 2
MTOC_SRC1_ADDR_SAVE = $ - mtoc_src1_fix1

PUBLIC	compile_mtoc_src1
compile_mtoc_src1	PROC	NEAR

	mov	cx,MTOC_SRC1_LEN
	lea	si,mtoc_src1_template
	rep	movs byte ptr es:[di], cs:[si]

	mov	ax,inner_loop_count
	mov	es:[di - MTOC_SRC1_INNER_LOOP],ax
	mov	cx,align_rotate_count
	mov	es:[di - MTOC_SRC1_FIXUP1],cl	;fixup left edge pre-roll
	mov	al,1
	rol	al,cl
	mov	es:[di - MTOC_SRC1_FIXUP0],al	;fixup left edge pre-roll

	mov	ax,fgcolour.lo			;fixup the standard mono
	mov	dx,fgcolour.hi
	mov	es:[di - MTOC_SRC1_FIXUP3],ax
	mov	es:[di - MTOC_SRC1_FIXUP3A],dx
	xor	ax,bgcolour.lo
	xor	dx,bgcolour.hi
	mov	es:[di - MTOC_SRC1_FIXUP2],ax
	mov	es:[di - MTOC_SRC1_FIXUP2A],dx
	lea	ax,[di - MTOC_SRC1_ADDR_SAVE]	;save looping address for
	mov	any_jmp_address,ax		; later
	ret

compile_mtoc_src1	ENDP			;




;
;	compile_mtoc_loop
;

mtoc_loop_template:
	dec	cx
	je	@F
        rol     bh,1
	jnc	mtoc_loop_template	 ;this jnc addr will get a fixup
mtoc_loop_fix1:
        lodsb
	mov	bl,al
	jmp	short mtoc_loop_template ;this jmp addr will get a fixup
mtoc_loop_fix2:
@@:

MTOC_LOOP_FIXUP1 = $ - mtoc_loop_fix1
MTOC_LOOP_FIXUP2 = $ - mtoc_loop_fix2
MTOC_LOOP_LEN = $ - mtoc_loop_template

PUBLIC	compile_mtoc_loop
compile_mtoc_loop	PROC	NEAR

	call	compile_colour_stos

	mov	cx,MTOC_LOOP_LEN
	lea	si,mtoc_loop_template
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,any_jmp_address
	lea	bx,[di - MTOC_LOOP_FIXUP1]
	sub	ax,bx
	mov	es:[di - MTOC_LOOP_FIXUP1 - 1],al
	mov	ax,any_jmp_address
	lea	bx,[di - MTOC_LOOP_FIXUP2]
	sub	ax,bx
	mov	es:[di - MTOC_LOOP_FIXUP2 - 1],al
        ret

compile_mtoc_loop       ENDP

sEnd	CODE

END

