;
;	FILE:	bltstos.asm
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module contains routines that deal with mono to color blts.
;

SRCFILE_BLTSTOS equ	1
incLogical	=	1
incDrawMode	=	1

include cmacros.inc
include gdidefs.inc
include macros.mac
include njumps.mac
include vgareg.inc
include genconst.inc
include display.inc
include bblt.inc
include bitblt.var
include vgautil.inc
include compblt.inc

.286
sBegin	Code
assumes cs,Code
assumes ds,Nothing
assumes es,Nothing
assumes ss,Nothing

;
;	bltstos
;
;

stos_src1_template:
	; FIXME: What if there isn't enough space on the stack??
	sub	sp,01234H		;01234H will become |src_xExt_bytes| + 8

stos_src1_outer_loop:
	mov	dx,01234H		;0FFH will become the src_page
stos_src1_src_page:			;set the correct src page (also sets

	call	far_set_bank_select	;the dst page, but that doesn't matter)
	mov	cx,01234H		;01234H will become |src_xExt_bytes|
	; FIXME: Check if this wraps around a segment boundary
stos_src1_xExt_1:

	push	di			;Since the src and dst may be in
	push	es			; different pages of the screen,
	mov	di,sp			; copy a scanline of the src to a
	add	di,01234H		; temporary buffer on the stack.
stos_src1_xExt_2:			;01234H:=|src_xExt_bytes|+8 if X- else 0

	mov	ax,ss			; This way src and dst pages need
	mov	es,ax			; not be switched every pixel, but
	rep	movsb			; only every scanline.
	pop	es
	pop	di

	mov	dx,01234H		;01234H will become the dst_page
stos_src1_dst_page:

	call	far_set_bank_select	;Set BOTH src and dst page to dst_page
	mov	cx,01234H		;01234H will become |src_xExt_bytes|
	; FIXME: Check if this wraps around a segment boundary
stos_src1_xExt_3:

	push	si			; and set the src to point to the
	push	ds			; copy of the src that was just copied
	mov	si,sp			; to the stack
	add	si,01234H		;01234H:=|src_xExt_bytes|+8 if X- else 0
stos_src1_xExt_4:

	mov	ax,ss
	mov	ds,ax

stos_src1_inner_loop:
	lodsb				;load a src byte

STOS_SRC1_SIZE = $ - stos_src1_template
STOS_SRC1_DST_PAGE = $ - stos_src1_dst_page + 2
STOS_SRC1_SRC_PAGE = $ - stos_src1_src_page + 2
STOS_SRC1_OUTER_LOOPADDR = $ - stos_src1_outer_loop
STOS_SRC1_INNER_LOOPADDR = $ - stos_src1_inner_loop
STOS_SRC1_XEXT_1 = $ - stos_src1_xExt_1 + 2
STOS_SRC1_XEXT_2 = $ - stos_src1_xExt_2 + 2
STOS_SRC1_XEXT_3 = $ - stos_src1_xExt_3 + 2
STOS_SRC1_XEXT_4 = $ - stos_src1_xExt_4 + 2


stos_src2_template:
	loop	stos_src1_inner_loop	;do every pixel on the scanline
stos_src2_inner_loop:

	pop	ds			;restore ds,si to point to the src
	pop	si			; on the screen
	dec	word ptr ss:[01234H]	;01234H will become ptr to yExt
stos_src2_yExt:

	jne	@F
	add	sp,01234H		;01234H will be 2 * xExt
stos_src2_clear_stack:
	retf

@@:	add	si,01234H		;01234H will become src_swing_bytes
stos_src2_src_swing_bytes:
	cmp	si,01234H	;if blt y+, 01234H will become src_width_bytes
				;if blt y-, 01234H will become -src_width_bytes
stos_src2_src_cmp:
					;segment update code: if blt is y-, the
	adc	byte ptr ss:[01234H],0	; 0 will become -1. 01234H points to
stos_src2_src_yupdate:			; compiled addr stos_src1_src_page - 2

	add	di,01234H		;01234H will become dst_swing_bytes
stos_src2_dst_swing_bytes:
	cmp	di,01234H	;if blt y+ 01234H will become dst_width_bytes
				;if blt y- 01234H will become -dst_width_bytes
stos_src2_dst_cmp:

	adc	byte ptr ss:[01234H],0
stos_src2_dst_yupdate:

STOS_SRC2_SIZE = $ - stos_src2_template
STOS_SRC2_INNER_LOOPADDR = $ - stos_src2_inner_loop
STOS_SRC2_YEXT = $ - stos_src2_yExt + 2
STOS_SRC2_SRC_SWING_BYTES = $ - stos_src2_src_swing_bytes + 2
STOS_SRC2_SRC_YUPDATE = $ - stos_src2_src_yupdate
STOS_SRC2_DST_SWING_BYTES = $ - stos_src2_dst_swing_bytes + 2
STOS_SRC2_DST_YUPDATE = $ - stos_src2_dst_yupdate
STOS_SRC2_CLEAR_STACK = $ - stos_src2_clear_stack + 2
STOS_SRC2_SRC_CMP = $ - stos_src2_src_cmp
STOS_SRC2_DST_CMP = $ - stos_src2_dst_cmp


PUBLIC	bltstos
bltstos 	PROC	NEAR

	call	bltstos_prep

	mov	cx,STOS_SRC1_SIZE		;move first template on and
	lea	si,stos_src1_template		; do all the fixups
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,src_xExt_bytes
	mov	cx,8				;eight guard bytes either end
        mov     es:[di - STOS_SRC1_XEXT_2],cx
	mov	es:[di - STOS_SRC1_XEXT_4],cx
	test	ax,ax
	jns	@F
	neg	ax
        add     es:[di - STOS_SRC1_XEXT_2],ax
	add	es:[di - STOS_SRC1_XEXT_4],ax
@@:	mov	es:[di - STOS_SRC1_XEXT_1],ax
	mov	es:[di - STOS_SRC1_XEXT_3],ax

	add	ax,10h				;eight guard bytes either end
	lea	bx,[di - STOS_SRC1_OUTER_LOOPADDR]
	push	bx				;save outer loop addr
	mov	es:[bx - 2],ax

	lea	bx,[di - STOS_SRC1_SRC_PAGE]
	push	bx				;save address of src_page value
	mov	ax,src_page
	mov	es:[bx],ax
	lea	bx,[di - STOS_SRC1_DST_PAGE]
	push	bx				;save address of dst_page value
	mov	ax,dst_page
        mov     es:[bx],ax
	lea	bx,[di - STOS_SRC1_INNER_LOOPADDR]
	push	bx				;save inner loop address

	push	es:[di - STOS_SRC1_OUTER_LOOPADDR - 2] ; save stack frame size

	test	rop_flags,PATTERN_PRESENT	;compile the pattern code
	je	@F				; if a pattern is used
	call	compile_color_pattern_fetch
@@:	call	compile_rop

	call	compile_color_stosb

	mov	cx,STOS_SRC2_SIZE
	lea	si,stos_src2_template
	rep	movs byte ptr es:[di], cs:[si]

        pop     es:[di - STOS_SRC2_CLEAR_STACK] ;recover stack frame size

	pop	ax				;recover inner loop start addr
	lea	bx,[di - STOS_SRC2_INNER_LOOPADDR]
	sub	ax,bx
	mov	es:[bx - 1],al			;fixup inner loop -- loop @B

	lea	ax,word ptr yExt
	mov	es:[di - STOS_SRC2_YEXT],ax
        mov     bx,vert_dir
	mov	ax,src_swing_bytes
	mov	es:[di - STOS_SRC2_SRC_SWING_BYTES],ax
        mov     ax,dst_swing_bytes
        mov     es:[di - STOS_SRC2_DST_SWING_BYTES],ax
	mov	ax,src_width_bytes
	mov	cx,dst_width_bytes
	or	bx,bx
	je	@F
	neg	ax
	neg	cx
@@:	mov	es:[di - STOS_SRC2_SRC_CMP - 2],ax
	mov	es:[di - STOS_SRC2_DST_CMP - 2],cx

	pop	ax
	mov	es:[di - STOS_SRC2_DST_YUPDATE - 3],ax	;fixup dst_page change
	mov	es:[di - STOS_SRC2_DST_YUPDATE - 1],bl
	pop	ax
	mov	es:[di - STOS_SRC2_SRC_YUPDATE - 3],ax	;fixup src_page change
	mov	es:[di - STOS_SRC2_SRC_YUPDATE - 1],bl

	test	rop_flags,PATTERN_PRESENT	;compile the pattern code
	je	@F				; if a pattern is used
	call	compile_pattern_yupdate
@@:	mov	al,I_JMP_NEAR
	stosb
        pop     ax
	lea	bx,[di + 2]
	sub	ax,bx
	stosw
	ret

bltstos ENDP				;

;
;	bltstos_prep
;
;

PUBLIC	bltstos_prep
bltstos_prep	PROC	NEAR

	mov	ax,SrcyOrg
	mov	bx,SrcxOrg
	mul	word ptr src_width_bytes
	add	ax,bx
	mov	src_blt_offset,ax
	mov	src_page,dx

	mov	ax,DestyOrg
	mov	bx,DestxOrg
	mul	word ptr dst_width_bytes
	add	ax,bx
	mov	dst_blt_offset,ax
	mov	dst_page,dx
        ret

bltstos_prep	ENDP				;

;
;	bltstos_srccopy
;
;	This routine handles source to dest copies where the source and
;	destination are equal modulo 4 and the bgmode is OPAQUE.
;

PUBLIC	bltstos_srccopy
bltstos_srccopy PROC	NEAR

	call	bltstos_srccopy_prep

	lds	si,dword ptr src_blt_offset
	les	di,dword ptr dst_blt_offset
        mov     bh,last_edge_mask
	mov	bl,first_edge_mask
	mov	word ptr first_edge_mask_count,0
	or	bl,bl
	je	source_aligned_copy_loop
	mov	word ptr first_edge_mask_count,1

source_aligned_copy_loop:
	dec	word ptr yExt
	js	source_aligned_copy_done
	call	source_copy_one_scanline

	mov	ax,dst_swing_bytes	;for screen aligned source copy
	add	si,ax
	add	di,ax
	or	ax,ax
	mov	ax,dst_width_bytes
	js	sa_copy_up

	cmp	si,ax			;src and dst are the same -- screen
	jae	@F			; so OK to cmp si to dst_width_bytes
	inc	word ptr src_bank
	mov	dx,src_bank
	clc
	SET_BANK	; call	set_banko

@@:	cmp	di,ax
	jae	@F
	inc	word ptr dst_bank
	mov	dx,dst_bank
	stc
	SET_BANK	; call	set_banko
@@:	jmp	short	source_aligned_copy_loop

sa_copy_up:
	neg	ax
	cmp	si,ax
	jb	@F
	dec	word ptr src_bank
	mov	dx,src_bank
	clc
	SET_BANK	; call	set_banko

@@:	cmp	di,ax
	jb	@F
	dec	word ptr dst_bank
	mov	dx,dst_bank
	stc
        SET_BANK	; call    set_banko
@@:	jmp	short	source_aligned_copy_loop

source_aligned_copy_done:
	ret

bltstos_srccopy 	ENDP			;



;
;   source_copy_one_scanline
;
;   This routine blits one scanline where source and destination are equal
;   modulo 4.
;
;   PARMS:
;   4 plane mode
;   write mode 1
;   direction flag cleared or set as appropriate
;   BL          -       left edge mask
;   BH		-	right edge mask
;   CX		-	number of full nibbles
;   DS:SI       -       ptr to src
;   ES:DI	-	ptr to dest
;

source_copy_one_scanline     proc    near

	mov	dx	,VGAREG_SQ_ADDR
	mov	al	,VGAREG_SQ_MAP_MASK
	out	dx	,al
	inc	dx

        mov     al      ,bl             ;set the left edge mask
        out     dx      ,al
	mov	cx,first_edge_mask_count	;this is either 0 or 1
	rep	movsb			;move the left edge bytes

	mov	al	,0FH		;set mask for full nibble moves
        out     dx      ,al
	mov	cx,	nibble_count
	rep	movsb			;move all four byte "nibbles"

	mov	al	,bh		;set the right edge mask
	out	dx	,al
	movsb				;move the right edge bytes
	ret

source_copy_one_scanline   ENDP 	;



;
;	bltstos_srccopy_prep
;
;	This computes src and dst addresses assuming planar mode!!

PUBLIC	bltstos_srccopy_prep
bltstos_srccopy_prep	PROC	NEAR

        mov     ax,SrcyOrg
        mov     bx,SrcxOrg
	mov	dx,src_width_bytes
	shr	dx,2			;in planar mode, all addresses are
	mov	src_width_bytes,dx
	mul	dx
        shr     bx,2                    ; divided by 4
	add	ax,bx
        mov     src_blt_offset,ax
	mov	src_bank,dx
	clc
	SET_BANK	; call	set_banko

        mov     ax,DestyOrg
        mov     bx,DestxOrg
	mov	dx,dst_width_bytes
	shr	dx,2			;in planar mode, all address are
	mov	dst_width_bytes,dx
	mul	dx
        shr     bx,2                    ; divided by 4
        add     ax,bx
        mov     dst_blt_offset,ax
	mov	dst_bank,dx
	stc
	SET_BANK	; call	set_banko

	mov	ah,FUNC_COPY or PLANAR_MODE
	mov	al,WRITE_MODE_1 or SET_RESET_FOREGROUND
        call    vga_set_features

	cmp	word ptr vert_dir,-1	;for aligned srccopy, I need vert_dir
	adc	word ptr vert_dir,0	; = 1 for Y+ blts and = -1 for Y- blts

	mov	ax,dst_width_bytes
	mov	bx,nibble_count
	cmp	byte ptr first_edge_mask,1
	sbb	bx,-2

	or	word ptr dst_swing_bytes,0  ;should I make the swing_bytes neg?
	jns	@F			    ;nah!
	neg	ax

@@:	std
	or	word ptr dst_xExt_bytes,0
	js	@F
	neg	bx
	cld

@@:	add	ax,bx
	mov	dst_swing_bytes,ax
	mov	src_swing_bytes,ax
	ret

bltstos_srccopy_prep	ENDP			;



;
;	bltstos_splitbank
;
;	This routine is a fast non-nibble aligned screen to screen srccopy.
;	It will only work on a Video 7 board which has split-bank
;	functionality; at the time that this routine was written, only
;	the VRAM II could do split banking.
;	RETURNS:


PUBLIC	bltstos_splitbank
bltstos_splitbank	PROC	NEAR

	call	bltstos_splitbank_prep

	call	compile_inner_loop_start
	push	di				;save inner_loop_address
	or	word ptr device_flags, DEVFLAG_MOVSB or DEVFLAG_REP
	mov	al,I_LODSB
	stosb

	test	rop_flags,PATTERN_PRESENT	;compile the pattern code
	je	@F				; if a pattern is used
	and	word ptr device_flags, NOT DEVFLAG_MOVSB  ; can't do a movsb
	call	compile_color_pattern_fetch
@@:	call	compile_rop

	call	compile_color_stosb

	pop	bx
	call	compile_inner_loop_end

	cmp	word ptr background_mode,OPAQUE
	jne	bltstos_nomovsb
	test	word ptr device_flags,DEVFLAG_MOVSB
	je	bltstos_nomovsb
	sub	di,2
	test	word ptr device_flags,DEVFLAG_REP
	je	@F

public  bltstos_repmovsb
bltstos_repmovsb:				  ;just for debugging
	sub	di,2
	mov	al,I_REP
	stosb
@@:	mov	al,I_MOVSB
	stosb

bltstos_nomovsb:

	call	compile_outer_loop

	call	compile_src_splitbank_yupdate
	call	compile_dst_splitbank_yupdate

	test	rop_flags,PATTERN_PRESENT	;compile the pattern code
        je      @F                              ; if a pattern is used
	call	compile_pattern_yupdate

@@:	call	compile_jmp_back_to_start
	ret

bltstos_splitbank	ENDP


;
;	bltstos_splitbank_prep
;
;

PUBLIC	bltstos_splitbank_prep
bltstos_splitbank_prep	PROC	NEAR

	mov	dx,VGAREG_SQ_ADDR		;enable splitbank adressing
        mov     al,VGAREG_SQ_SPLITBANK
        out     dx,al
        inc     dx
        in      al,dx
        or      al,80H
        out     dx,al

	mov	ax,SrcyOrg
	mov	bx,SrcxOrg
	mov	cx,src_width_bytes
	shl	cx,4
	mul	cx
	shr	ax,4
	add	ax,bx
	mov	src_blt_offset,ax
	mov	src_page,dx

	mov	ax,DestyOrg
	mov	bx,DestxOrg
	mov	cx,dst_width_bytes
	shl	cx,4
	mul	cx
	shr	ax,4
	add	ax,bx
	or	ax,8000H			;split bank dst flag bit
	mov	dst_blt_offset,ax
	mov	dst_page,dx

	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_SRC_SPLITBANK
	mov	ah,byte ptr src_page
	out	dx,ax

	mov	al,VGAREG_SQ_DST_SPLITBANK
	mov	ah,byte ptr dst_page
	out	dx,ax
	ret

bltstos_splitbank_prep	ENDP				;

sEnd	Code

END
