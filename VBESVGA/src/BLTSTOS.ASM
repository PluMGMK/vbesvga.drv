;
;	FILE:	bltstos.asm
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module contains routines that deal with screen to screen blts.
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

externA	stack_top	; in CHKSTK.ASM
externA	stack_bot	; in CHKSTK.ASM
externA	stack_min	; in CHKSTK.ASM

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
	sub	sp,01234H		;01234H will become |src_xExt_bytes| + 8
stos_src1_frame_size:

	; do some book-keeping with the stack pointer
	cmp	sp,ss:[stack_top]
	jae	@F
	int	3			;uh-oh...
@@:	cmp	sp,ss:[stack_min]
	jae	stos_src1_outer_loop
	mov	ss:[stack_min],sp	;update record of min stack pointer

stos_src1_outer_loop:
	mov	dx,01234H		;01234H will become the src_page
stos_src1_src_page:			;set the correct src page (also sets

	call	far_set_bank_select	;the dst page, but that doesn't matter)
	mov	cx,01234H		;01234H will become |src_xExt_bytes|
stos_src1_xExt_1:
	push	di			;Since the src and dst may be in
	push	es			; different pages of the screen,
	mov	di,sp			; copy a scanline of the src to a
	add	di,01234H		; temporary buffer on the stack.
stos_src1_xExt_2:			;01234H:=|src_xExt_bytes|+8 if X- else 8
	mov	ax,ss			; This way src and dst pages need
	mov	es,ax			; not be switched every pixel, but
					; only every scanline.
; FIXME: omit everything from here to @F when not scanxseg!
	mov	bx,si
stos_src1_add_check_1:
	add	bx,cx			;ADD becomes SUB if X-
	sbb	ax,ax			;AX:=FFFFh if we wrap, zero otherwise
	jz	@F

	and	ax,bx		;set AX to our count, and set SF appropriately
	jns	ss1ia1
	neg	ax
	dec	ax		;if X-, need extra iteration to get to SI==FFFFh
ss1ia1:	inc	ax		;guarantee it is not zero on this codepath
	sub	cx,ax		;CX := iterations left to end of segment
	inc	cx		;restore so we get the correct # of iterations

@@:	rep	movsb
; FIXME: omit everything from here to @F when not scanxseg!
	xchg	cx,ax		;get back remaining iterations from before
	jcxz	@F
	;we've wrapped, so switch the bank and head back to the beginning of the
	; inner loop for another X amount of iterations...
	mov	dx,ss:[1234H]	;1234H becomes offset of stos_src1_src_page
stos_src1_src_page_off1:
	inc	dx		;42h ; change to 4Ah to make it DEC DX
	mov	ss:[1234H],dx	;1234H becomes offset of stos_src1_src_page
stos_src1_src_page_off2:
	call	far_set_bank_select
	dec	cx		;AX was incremented when it was set
	jnz	@B
@@:
	pop	es
	pop	di

	mov	dx,01234H		;01234H will become the dst_page
stos_src1_dst_page:

	call	far_set_bank_select	;Set BOTH src and dst page to dst_page
	mov	cx,01234H		;01234H will become |src_xExt_bytes|
stos_src1_xExt_3:

	push	si			; and set the src to point to the
	push	ds			; copy of the src that was just copied
	mov	si,sp			; to the stack
	add	si,01234H		;01234H:=|src_xExt_bytes|+8 if X- else 8
stos_src1_xExt_4:

	mov	ax,ss
	mov	ds,ax

; FIXME: omit everything from here to stos_src1_inner_loop
; when not scanxseg!
	mov	bx,di
stos_src1_add_check_2:
	add	bx,cx		;ADD becomes SUB if X-
	sbb	ax,ax		;AX:=FFFFh if we wrap, zero otherwise
	jz	@F

	and	ax,bx		;set AX to our count, and set SF appropriately
	jns	ss1ia2
	neg	ax
	dec	ax		;if X-, need extra iteration to get to DI==FFFFh
ss1ia2:	inc	ax		;guarantee it is not zero on this codepath
	sub	cx,ax		;CX := iterations left to end of segment
	inc	cx		;restore so we get the correct # of iterations
@@:	mov	ss:[01234H],ax	;01234H becomes dst_seg_wrap

stos_src1_inner_loop:
	lodsb			;load a src byte

STOS_SRC1_SIZE = $ - stos_src1_template
STOS_SRC1_DST_PAGE = $ - stos_src1_dst_page + 2
STOS_SRC1_SRC_PAGE = $ - stos_src1_src_page + 2
STOS_SRC1_FRAME_SIZE = $ - stos_src1_frame_size + 2
STOS_SRC1_OUTER_LOOPADDR = $ - stos_src1_outer_loop
STOS_SRC1_INNER_LOOPADDR = $ - stos_src1_inner_loop
STOS_SRC1_XEXT_1 = $ - stos_src1_xExt_1 + 2
STOS_SRC1_XEXT_2 = $ - stos_src1_xExt_2 + 2
STOS_SRC1_XEXT_3 = $ - stos_src1_xExt_3 + 2
STOS_SRC1_XEXT_4 = $ - stos_src1_xExt_4 + 2
STOS_SRC1_ADDSUB_1 = $ - stos_src1_add_check_1
STOS_SRC1_ADDSUB_2 = $ - stos_src1_add_check_2
STOS_SRC1_INCDEC = $ - stos_src1_src_page_off1
STOS_SRC1_SRC_PAGE_OFF1 = $ - stos_src1_src_page_off1 + 2
STOS_SRC1_SRC_PAGE_OFF2 = $ - stos_src1_src_page_off2 + 2
STOS_SRC1_DST_SEGWRAP_OFF = $ - stos_src1_inner_loop + 2


stos_src2_template:
	loop	stos_src1_inner_loop	;do every pixel on the scanline
stos_src2_inner_loop1:

; FIXME: omit everything from here to stos_src2_inner_loop2
; when not scanxseg!
	xchg	cx,ss:[1234H]	;1234H becomes offset of dst_seg_wrap
stos_src2_dst_segwrap_off:
	jcxz	stos_src2_inner_loop2
	;we've wrapped, so switch the bank and head back to the beginning of the
	; inner loop for another X amount of iterations...
	mov	dx,ss:[1234H]	;1234H becomes offset of stos_src1_dst_page
stos_src2_dst_page_off1:
	inc	dx		;42h ; change to 4Ah to make it DEC DX
	mov	ss:[1234H],dx	;1234H becomes offset of stos_src1_dst_page
stos_src2_dst_page_off2:
	call	far_set_bank_select
	dec	cx		;dst_seg_wrap was incremented when it was set
	jnz	stos_src1_inner_loop
stos_src2_inner_loop2:

	pop	ds			;restore ds,si to point to the src
	pop	si			; on the screen
	dec	word ptr ss:[01234H]	;01234H will become ptr to #passes
stos_src2_passes:
	jne	stos_src2_dst_yupdate	;jump to the end where we loop back
	;reset the number of passes:	01234H becomes pointer to #passes,
	;				05678H becomes the actual number
	mov	word ptr ss:[01234H],05678H
stos_src2_passes_reset:
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
				;if scanxseg, 01234H will become src_swing_bytes
stos_src2_src_cmp:
					;segment update code: if blt is y-, the
	adc	byte ptr ss:[01234H],0	; 0 will become -1. 01234H points to
stos_src2_src_yupdate:			; compiled addr stos_src1_src_page - 2

	add	di,01234H		;01234H will become dst_swing_bytes
stos_src2_dst_swing_bytes:
	cmp	di,01234H	;if blt y+ 01234H will become dst_width_bytes
				;if blt y- 01234H will become -dst_width_bytes
				;if scanxseg, 01234H will become dst_swing_bytes
stos_src2_dst_cmp:

	adc	byte ptr ss:[01234H],0
stos_src2_dst_yupdate:

STOS_SRC2_SIZE = $ - stos_src2_template
STOS_SRC2_INNER_LOOPADDR1 = $ - stos_src2_inner_loop1
STOS_SRC2_INNER_LOOPADDR2 = $ - stos_src2_inner_loop2
STOS_SRC2_DST_SEGWRAP_OFF = $ - stos_src2_dst_segwrap_off + 2
STOS_SRC2_DST_PAGE_OFF1 = $ - stos_src2_dst_page_off1 + 2
STOS_SRC2_DST_PAGE_OFF2 = $ - stos_src2_dst_page_off2 + 2
STOS_SRC2_INCDEC = $ - stos_src2_dst_page_off1
STOS_SRC2_PASSES_PTR1 = $ - stos_src2_passes + 2
STOS_SRC2_PASSES_PTR2 = $ - stos_src2_passes_reset + 4
STOS_SRC2_PASSES_VAL = $ - stos_src2_passes_reset + 2
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

	;here, SP = BitBlt - 4 (bltstos --> bitblt_dispatch --> BitBlt);
	;in the compiled code, SP will be BitBlt - 8:
	; compiled code (far return frame = 4 bytes) -->
	; bitblt_execute (stored BP + near return frame) -->
	; BitBlt
	mov	word ptr [bltstos_passes],1
	mov	cx,src_xExt_bytes
	mov	bx,cx
	test	bx,bx
	jns	@F
	neg	bx
@@:	;so we need to check if the current SP, minus four, leaves enough space,
	; including eight guard bytes either end (so 20 bytes altogether)
	lea	ax,[bx+14h]
	sub	ax,sp
	;if AX > SP, then stack would wrap: not good
	ja	stack_not_ok

	;OK, stack doesn't wrap, but is there enough space beyond "stack_top"?
	; (confusingly, "stack_top" is the *lowest* memory address, corresponding
	;  to a metaphor of the stack growing up, even though it grows down...)
	neg	ax
	cmp	ax,ss:[stack_top]
	jnb	stack_ok

stack_not_ok:
	;halve the number of bytes per pass and double the number of passes
	sar	cx,1
	shr	bx,1
	shl	word ptr [bltstos_passes],1
	jmp	@B	;go back and check if it'll fit now

stack_ok:
	mov	ax,cx
	mov	cx,8				;eight guard bytes either end
        mov     es:[di - STOS_SRC1_XEXT_2],cx
	mov	es:[di - STOS_SRC1_XEXT_4],cx
	test	ax,ax
	jns	@F
	or	es:[di - STOS_SRC1_INCDEC],cl	;change to DEC (42h | 8 == 4Ah)
	or	cl,20H
	or	es:[di - STOS_SRC1_ADDSUB_1],cl	;change to SUB (03->2BH)
	or	es:[di - STOS_SRC1_ADDSUB_2],cl	;change to SUB (03->2BH)
	neg	ax
        add     es:[di - STOS_SRC1_XEXT_2],ax
	add	es:[di - STOS_SRC1_XEXT_4],ax
@@:	mov	es:[di - STOS_SRC1_XEXT_1],ax
	mov	es:[di - STOS_SRC1_XEXT_3],ax
	add	ax,10h	;eight guard bytes either end

	lea	bx,[di - STOS_SRC1_FRAME_SIZE]
	mov	es:[bx],ax
	lea	ax,[di - STOS_SRC1_OUTER_LOOPADDR]
	push	ax				;save outer loop addr

	lea	bx,[di - STOS_SRC1_SRC_PAGE]
	push	bx				;save address of src_page value
	mov	ax,src_page
	mov	es:[bx],ax
	mov	es:[di - STOS_SRC1_SRC_PAGE_OFF1],bx
	mov	es:[di - STOS_SRC1_SRC_PAGE_OFF2],bx

	lea	bx,[di - STOS_SRC1_DST_PAGE]
	push	bx				;save address of dst_page value
	mov	ax,dst_page
        mov     es:[bx],ax
	lea	bx,[di - STOS_SRC1_INNER_LOOPADDR]
	push	bx				;save inner loop address

	push	es:[di - STOS_SRC1_FRAME_SIZE]	;save stack frame size
	lea	bx,[dst_seg_wrap]
	mov	es:[di - STOS_SRC1_DST_SEGWRAP_OFF],bx

	test	rop_flags,PATTERN_PRESENT	;compile the pattern code
	je	@F				; if a pattern is used
	call	compile_color_pattern_fetch
@@:	call	compile_rop

	call	compile_color_stosb

	mov	cx,STOS_SRC2_SIZE
	lea	si,stos_src2_template
	rep	movs byte ptr es:[di], cs:[si]

	lea	bx,[dst_seg_wrap]
	mov	es:[di - STOS_SRC2_DST_SEGWRAP_OFF],bx
        pop     es:[di - STOS_SRC2_CLEAR_STACK] ;recover stack frame size

	lea	bx,[bltstos_passes]
	mov	es:[di - STOS_SRC2_PASSES_PTR1],bx
	mov	es:[di - STOS_SRC2_PASSES_PTR2],bx
	mov	ax,ss:[bx]
	mov	es:[di - STOS_SRC2_PASSES_VAL],ax

	pop	ax				;recover inner loop start addr
	mov	dx,ax
	lea	bx,[di - STOS_SRC2_INNER_LOOPADDR1]
	sub	ax,bx
	mov	es:[bx - 1],al			;fixup inner loop -- loop @B
	lea	bx,[di - STOS_SRC2_INNER_LOOPADDR2]
	sub	dx,bx
	mov	es:[bx - 1],dl			;fixup inner loop -- jnz @B

	or	word ptr [dst_xExt_bytes],0
	jns	@F
	or	byte ptr es:[di - STOS_SRC2_INCDEC],8	;change to DEC
@@:
	lea	ax,word ptr yExt
	mov	es:[di - STOS_SRC2_YEXT],ax
        mov     bx,vert_dir
	mov	ax,src_swing_bytes
        mov     cx,dst_swing_bytes
	mov	es:[di - STOS_SRC2_SRC_SWING_BYTES],ax
        mov     es:[di - STOS_SRC2_DST_SWING_BYTES],cx
	; DON'T DO THIS because there's a whole chunk of hard-coded stuff
	; in stos_src1_template which handles segment wrapping in the middle
	; of a scanline whether it's needed or not. So if we do this next bit,
	; we'll be over-compensating in that case. Ideally should refactor
	; so that stuff can be excluded altogether in the non-scanxseg case,
	; then we can put these lines back.
;	test	word ptr [device_flags],DEVFLAG_SCAN_X_SEG
;	jnz	@F
;	mov	ax,src_width_bytes
;	mov	cx,dst_width_bytes
;	or	bx,bx
;	je	@F
;	neg	ax
;	neg	cx
@@:	mov	es:[di - STOS_SRC2_SRC_CMP - 2],ax
	mov	es:[di - STOS_SRC2_DST_CMP - 2],cx

	pop	ax
	mov	es:[di - STOS_SRC2_DST_YUPDATE - 3],ax	;fixup dst_page change
	mov	es:[di - STOS_SRC2_DST_YUPDATE - 1],bl
	mov	es:[di - STOS_SRC2_DST_PAGE_OFF1],ax
	mov	es:[di - STOS_SRC2_DST_PAGE_OFF2],ax
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
	adc	dx,0
	mov	src_blt_offset,ax
	mov	src_page,dx

	mov	ax,DestyOrg
	mov	bx,DestxOrg
	mul	word ptr dst_width_bytes
	add	ax,bx
	adc	dx,0
	mov	dst_blt_offset,ax
	mov	dst_page,dx
        ret

bltstos_prep	ENDP				;

sEnd	Code

END
