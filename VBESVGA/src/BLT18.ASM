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

externA __NEXTSEG

.286
sBegin	Code
assumes cs,Code
assumes ds,Nothing
assumes es,Nothing
assumes ss,Nothing

externW	pxbytes	; in SWCURS.ASM

;
;	blt18
;
;

PUBLIC	blt18
blt18	PROC	NEAR

	call	blt_mtoc_prep

	;create a subroutine that will be called for each byte of each colour,
	; to optimize our memory footprint and prevent overflow.
	call	compile_begin_subroutine
	push	di				;save subroutine start address

	test	rop_flags,PATTERN_PRESENT	;compile the pattern code
	je	@F				; if a pattern is used
	call	compile_color_pattern_fetch

@@:	call	compile_rop			;now do the rop
	call	compile_mtoc_wrap

	pop	bx				;get back subroutine start address
	call	compile_end_subroutine

	;there is no need to check SOURCE_PRESENT because bitblt_dispatch only
	; calls blt18 if that is already the case.
	call	compile_mtoc_src1

	;determine how many bytes per colour to process
	mov	cx,[pxbytes]
	xor	si,si
blt18_colour_byte_loop:
	push	cx
	call	compile_mtoc_src2
	pop	cx
	inc	si
	loop	blt18_colour_byte_loop

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
	mov	ax,DestyOrg		; compute the starting address
	mul	word ptr dst_width_bytes
	add	ax,DestxOrg		;fixed for bitness in bitblt_prep_final
	adc	dx,0
        mov     dst_blt_offset,ax
	mov	dst_page,dx
	SET_BANK
@@:	ret

blt_mtoc_prep	ENDP

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

MTOC_SRC1_LEN = $ - mtoc_src1_template
MTOC_SRC1_INNER_LOOP = $ - mtoc_src1_inner_loop + 2
MTOC_SRC1_FIXUP0 = $ - mtoc_src1_fix0 + 1
MTOC_SRC1_FIXUP1 = $ - mtoc_src1_fix1 + 1
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
	lea	ax,[di - MTOC_SRC1_ADDR_SAVE]	;save looping address for
	mov	any_jmp_address,ax		; later
	ret

compile_mtoc_src1	ENDP			;

;
;	compile_mtoc_src2
;
;	Entry:
;	SI = N == which byte of colour we're dealing with
;
;	This routine places code on the stack to set AL to the Nth byte of
;	fg or bg colour, based on the lowest bit of BL (which in turn was
;	loaded in mtoc_src1 above).
;

mtoc_src2_template:
	rol	bl,1
	sbb	al,al			;this instruction preserves CF!
	rcr	bl,1			;send it back into BL for the time being
	and	al,0FFH 		;0FFH will become (fgcolor xor bgcolor)
mtoc_src2_fix2:
	xor	al,0FFH 		;0FFH will become fgcolor
mtoc_src2_fix3:
	call	compile_mtoc_src2	;this will become our compiled sub
mtoc_src2_fix1:

MTOC_SRC2_LEN = $ - mtoc_src2_template
MTOC_SRC2_FIXUP2 = $ - mtoc_src2_fix2 + 1
MTOC_SRC2_FIXUP3 = $ - mtoc_src2_fix3 + 1
MTOC_SRC2_FIXUP1 = $ - mtoc_src2_fix1

PUBLIC	compile_mtoc_src2
compile_mtoc_src2	PROC	NEAR

	mov	cx,MTOC_SRC2_LEN
	mov	ax,si				;save N
	lea	si,mtoc_src2_template
	rep	movs byte ptr es:[di], cs:[si]
	mov	si,ax				;restore N

	mov	al,fgcolour[si]			;fixup the standard mono
	mov	ah,bgcolour[si]
	xor	ah,al
	mov	es:[di - MTOC_SRC2_FIXUP2],ah
	mov	es:[di - MTOC_SRC2_FIXUP3],al

	;fixup the near call:
	lea	ax,[di - MTOC_SRC2_FIXUP1]
	neg	ax
	add	ax,bx				;BX has the subroutine address
	mov	es:[di - MTOC_SRC2_FIXUP1 - 2],ax

	ret

compile_mtoc_src2	ENDP			;




;
;	compile_mtoc_wrap
;

mtoc_wrap_template:
	test	di,di			;if DI is zero, we wrapped on this pixel
	jnz	@F
        mov	dx,ss:[1234H]		;1234H becomes offset of dst_page
mtoc_wrap_fix1:
	inc	dx			;always INC since mono-to-colour
        mov	ss:[1234H],dx		;1234H becomes offset of dst_page
mtoc_wrap_fix2:
	call	far_set_bank_select
@@:

MTOC_WRAP_FIXUP1 = $ - mtoc_wrap_fix1
MTOC_WRAP_FIXUP2 = $ - mtoc_wrap_fix2
MTOC_WRAP_LEN = $ - mtoc_wrap_template

PUBLIC	compile_mtoc_wrap
compile_mtoc_wrap	PROC	NEAR

	; this needs to be done here anyway
	call	compile_color_stosb

	;check if we wrap around the end of a segment
	test	word ptr [device_flags],DEVFLAG_DST_SCAN_X_SEG
	jz	@F
	test	word ptr [device_flags],DEVFLAG_DST_SCREEN
	jz	@F	; we don't support wrapping memory segments (not needed)

	mov	cx,MTOC_WRAP_LEN
	lea	si,mtoc_wrap_template
	rep	movs byte ptr es:[di], cs:[si]
	lea	ax,dst_page
	mov	es:[di - MTOC_WRAP_FIXUP1 - 2],ax
	mov	es:[di - MTOC_WRAP_FIXUP2 - 2],ax

@@:	ret

compile_mtoc_wrap       ENDP

;
;	compile_mtoc_loop
;

mtoc_loop_template:
	dec	cx
	je	mtoc_loop_done
	rol	bl,1			;flush the LSB for real this time
        rol     bh,1
	jnc	@F			;may or may not get a fixup
mtoc_loop_fix1:
        lodsb
	mov	bl,al
@@:	jmp	blt18			;this "jmp near" addr will get a fixup
mtoc_loop_fix2:
mtoc_loop_done:

MTOC_LOOP_FIXUP1 = $ - mtoc_loop_fix1
MTOC_LOOP_FIXUP2 = $ - mtoc_loop_fix2
MTOC_LOOP_LEN = $ - mtoc_loop_template

PUBLIC	compile_mtoc_loop
compile_mtoc_loop	PROC	NEAR

	mov	cx,MTOC_LOOP_LEN
	lea	si,mtoc_loop_template
	rep	movs byte ptr es:[di], cs:[si]

	mov	ax,any_jmp_address
	lea	bx,[di - MTOC_LOOP_FIXUP1]
	sub	ax,bx
	inc	ah
	jnz	@F
	test	al,al
	jns	@F
	;if it's within 128 bytes, fixup the JNC SHORT instruction
	; so there's one less jump involved in the code
	mov	es:[di - MTOC_LOOP_FIXUP1 - 1],al

@@:	mov	ax,any_jmp_address
	lea	bx,[di - MTOC_LOOP_FIXUP2]
	sub	ax,bx
	mov	es:[di - MTOC_LOOP_FIXUP2 - 2],ax
        ret

compile_mtoc_loop       ENDP

sEnd	CODE

END

