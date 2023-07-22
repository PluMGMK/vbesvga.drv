;	FILE:	bltpat.asm
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module contains routines that deal with pattern blts.
;

SRCFILE_BLTPAT	equ	1
incLogical	=	1
incDrawMode	=	1

include cmacros.inc
include gdidefs.inc
include macros.mac
include njumps.mac
include display.inc
include vgareg.inc
include bblt.inc
include bltutil.inc
;include blt216.inc
include bitblt.var
include vgautil.inc

.286
sBegin	Code
assumes cs,Code
assumes ds,Nothing
assumes es,Nothing
assumes ss,Nothing

SCREEN_DSCAN	EQU	1024

;
;	blt_pat_dst_prep
;
;

PUBLIC	blt_pat_dst_prep
blt_pat_dst_prep	PROC	NEAR

	mov	ax,DestyOrg		;the dst address
	mov	bx,DestxOrg
	mov	dx,word ptr dst_width_bytes
	shr	dx,2
	mul	dx
        shr     bx,2
	add	ax,bx
	mov	dst_blt_offset,ax
	mov	dst_bank,dx
	ret

blt_pat_dst_prep	ENDP		;


V7VGA_ROP2     STRUC
V7VGA_ROP2_FLAGS		db	0
V7VGA_ROP2_PATTERN		db	0
V7VGA_ROP2_FEATURE_0		db	0  ;the al reg parm to vga_set_features
V7VGA_ROP2_FEATURE_1		db	0  ;the ah reg parm to vga_set_features
V7VGA_ROP2_LOOP_FUNCTION        dw      0
V7VGA_ROP2_SOLID_LOOP_FUNCTION	dw	0
V7VGA_ROP2     ENDS

TWO_PASSES	EQU	10H
LOAD_LATCHES    EQU     20H
NEGATE_PATTERN	EQU	40H

;	the flags entry has the following bit definitions
;	bits 3:0  the rop number of the second pass rop if required
;	bit 4 = 0 if the rop is 1 pass, bit 0 = 1 if the rop is 2 pass
;	bit 5 = 1 if the FGLATCHES need to be loaded
;		  (this can be used to load an FF and using XOR invert the dst,
;		   or it can be used on rop #0 to fill with all 0's or with
;		   rop #15 to fill with all FF's)
;                 the V7VGA_ROP2_PATTERN entry gives the pattern -- 00 or FF
;	bit 5 = 0 otherwise
;	bit 6 = 1 if the pattern should be negated before the bltting starts

rop2_with_vga	label	BYTE
V7VGA_ROP2	<LOAD_LATCHES, 00H, DITHERED_FOREGROUND or WRITE_MODE_0, FUNC_COPY or PLANAR_MODE,blt_dst_loop, blt_dst_loop>
V7VGA_ROP2	<TWO_PASSES or 5, 00H, DITHERED_FOREGROUND or WRITE_MODE_0, FUNC_OR or PLANAR_MODE,blt_pat_dst_pattern_row_loop, blt_pat_dst_loop>
V7VGA_ROP2	<NEGATE_PATTERN, 00H, DITHERED_FOREGROUND or WRITE_MODE_0, FUNC_AND or PLANAR_MODE,blt_pat_dst_pattern_row_loop, blt_pat_dst_loop>
V7VGA_ROP2	<NEGATE_PATTERN, 00H, DITHERED_FOREGROUND or WRITE_MODE_0, FUNC_COPY or PLANAR_MODE,blt_dst_pattern_row_loop, blt_dst_loop>
V7VGA_ROP2	<LOAD_LATCHES or TWO_PASSES or 8, 0FFH, DITHERED_FOREGROUND or WRITE_MODE_0, FUNC_XOR or PLANAR_MODE,blt_pat_dst_loop, blt_pat_dst_loop>
V7VGA_ROP2	<LOAD_LATCHES, 0FFH, DITHERED_FOREGROUND or WRITE_MODE_0, FUNC_XOR or PLANAR_MODE,blt_pat_dst_loop, blt_pat_dst_loop>
V7VGA_ROP2	<00H, 00H, DITHERED_FOREGROUND or WRITE_MODE_0, FUNC_XOR or PLANAR_MODE,blt_pat_dst_pattern_row_loop, blt_pat_dst_loop>
V7VGA_ROP2	<TWO_PASSES or 5, 00H, DITHERED_FOREGROUND or WRITE_MODE_0, FUNC_AND or PLANAR_MODE,blt_pat_dst_pattern_row_loop, blt_pat_dst_loop>
V7VGA_ROP2	<00H, 00H, DITHERED_FOREGROUND or WRITE_MODE_0, FUNC_AND or PLANAR_MODE,blt_pat_dst_pattern_row_loop, blt_pat_dst_loop>
V7VGA_ROP2	<NEGATE_PATTERN, 00H, DITHERED_FOREGROUND or WRITE_MODE_0, FUNC_XOR or PLANAR_MODE,blt_pat_dst_pattern_row_loop, blt_pat_dst_loop>
V7VGA_ROP2	<00H, 00H, SET_RESET_FOREGROUND or WRITE_MODE_1, FUNC_COPY or PLANAR_MODE,blt_pat_dst_loop, blt_pat_dst_loop>
V7VGA_ROP2	<NEGATE_PATTERN, 00H, DITHERED_FOREGROUND or WRITE_MODE_0, FUNC_OR or PLANAR_MODE,blt_pat_dst_pattern_row_loop, blt_pat_dst_loop>
V7VGA_ROP2	<00H, 00H, DITHERED_FOREGROUND or WRITE_MODE_0, FUNC_COPY or PLANAR_MODE,blt_dst_pattern_row_loop, blt_dst_loop>
V7VGA_ROP2	<LOAD_LATCHES or TWO_PASSES or 0EH, 0FFH, DITHERED_FOREGROUND or WRITE_MODE_0, FUNC_XOR or PLANAR_MODE,blt_pat_dst_loop, blt_pat_dst_loop>
V7VGA_ROP2	<00H, 00H, DITHERED_FOREGROUND or WRITE_MODE_0, FUNC_OR or PLANAR_MODE,blt_pat_dst_pattern_row_loop, blt_pat_dst_loop>
V7VGA_ROP2	<LOAD_LATCHES, 0FFH, DITHERED_FOREGROUND or WRITE_MODE_0, FUNC_COPY or PLANAR_MODE,blt_dst_loop, blt_dst_loop>


;
;	blt_pat_dst
;
;	This routine is the main loop for a 2 rop blt involving the pattern
;	and the dst. WE do blts of this nature by setting up 5 loops!!!
;	For Rop pass = 1 to 2	(4 of the 16 rops require 2 passes)
;	    For pattern_row = 1 to min(SIZE_PATTERN,yExt)
;		For nibble = (even, odd)
;		    For blt_y = (yExt - pattern_row) to 1 step -SIZE_PATTERN
;			For blt_x = 1 to xExt
;
;	This loop organization actually minimizes the expected number of
;	accesses across the bus. If a second rop pass isn't required, the
;	outer loop is terminated after the first pass.
;

PUBLIC	blt_pat_dst
blt_pat_dst	PROC	NEAR

	call	blt_pat_dst_prep

	mov	al,byte ptr Rop[2]	;from the ROP 3, construct the
	mov	bl,al			; equivalent ROP 2 since we know
	and	bx,0030H		; that the source is not being used
	shl	bl,1
	and	al,03H
	shl	al,3
	or	bl,al
	mov	al,cs:rop2_with_vga[bx].V7VGA_ROP2_FLAGS

	test	al,NEGATE_PATTERN
	je	blt_pat_216_check
	mov	cx,SIZE_PATTERN * SIZE_PATTERN
	mov	si,pattern_offset
@@:	xor	byte ptr ss:[si],0FFH
	inc	si
	loop	@B


blt_pat_216_check:
;       test    word ptr local_board_flags,BOARD_FLAG_ENABLE_216
;       je      blt_pat_dst_roploop
;	cmp	bl,60H
;	jne	blt_pat_dst_roploop
;	int	 3
;       call	blt216_pat_dst
;       jmp     short blt_pat_dst_done


blt_pat_dst_roploop:
	test	al,LOAD_LATCHES
	je	@F
	mov	dl,cs:rop2_with_vga[bx].V7VGA_ROP2_PATTERN
	mov	cx,cs:rop2_with_vga[bx].V7VGA_ROP2_SOLID_LOOP_FUNCTION
	jmp	short	blt_pat_execute

@@:	mov	cx,cs:rop2_with_vga[bx].V7VGA_ROP2_LOOP_FUNCTION
	test	word ptr brush_accel_flags,SOLID_BRUSH
	je	blt_pat_execute
	mov	si,pattern_offset
	mov	dl,ss:[si]
	mov	cx,cs:rop2_with_vga[bx].V7VGA_ROP2_SOLID_LOOP_FUNCTION

blt_pat_execute:
	push	ax
	mov	ax,word ptr cs:rop2_with_vga[bx].V7VGA_ROP2_FEATURE_0
        call    vga_set_features
	mov	ah,dl
	call	cx
	pop	ax

	test	al,TWO_PASSES
	je	@F
	and	ax,0FH
	shl	ax,3
	mov	bx,ax
	mov	al,cs:rop2_with_vga[bx].V7VGA_ROP2_FLAGS
	jmp	short	blt_pat_dst_roploop

blt_pat_dst_done:
@@:	ret

blt_pat_dst	ENDP				;

;
;	blt_pat_dst_pattern_row_loop
;
;	This routine calls the even nibble then the odd nibble routine to
;	make two passes over the blt rectangle. All the necessary vga
;	state restore is included herein.
;

PUBLIC	blt_pat_dst_pattern_row_loop
blt_pat_dst_pattern_row_loop	PROC	NEAR

	mov	bl,first_edge_mask
	mov	bh,last_edge_mask
        lds     si,dword ptr dst_blt_offset     ;set vga dst state
	les	di,dword ptr dst_blt_offset
	mov	word ptr pattern_row_counter,1
	mov	dx,dst_bank			;preserve the initial state
	push	dx				; in case of two pass rop
	SET_BANK	; call	set_both_banko

bpdprl_0:
	call	blt_pat_dst_nibble_loop
	add	si,(SCREEN_DSCAN / 4)
	add	di,(SCREEN_DSCAN / 4)
        jnc     @F
	inc	word ptr dst_bank
	mov	dx,dst_bank
	SET_BANK	; call	set_both_banko

@@:	inc	word ptr pattern_row_counter
        mov     ax,pattern_row_counter
	cmp	ax,yExt
        ja      @F
        cmp     ax,8
	jbe	bpdprl_0

@@:	pop	word ptr dst_bank
	ret

blt_pat_dst_pattern_row_loop	ENDP		;

;
;	blt_pat_dst_nibble_loop
;
;	This routine calls the even nibble then the odd nibble routine to
;	make two passes over the blt rectangle. All the necessary vga
;	state restore is included herein.
;

PUBLIC	blt_pat_dst_nibble_loop
blt_pat_dst_nibble_loop PROC	NEAR

        lea     ax,blt_pat_dst_even_nibbles
        mov     nibble_function,ax

@@:	push	di
	push	dst_bank
        mov     ax,yExt
        sub     ax,pattern_row_counter
        mov     same_pattern_row_counter,ax
	call	load_fglatches
	call	blt_pat_dst_same_pattern_row_loop

	pop	dx
	mov	dst_bank,dx
	SET_BANK	; call	set_both_banko
        pop     di
	mov	si,di

	lea	ax,blt_pat_dst_odd_nibbles
	mov	cx,ax
	xchg	ax,nibble_function
	cmp	ax,cx
	jne	@B
	ret

blt_pat_dst_nibble_loop ENDP


;
;	blt_pat_dst_same_pattern_row
;
;	This routine blts every other nibble on all rows of the blt rectangle
;	that are equivalent modulo 8. This is because the same pattern nibble
;	is used in all these spots.
;	PARMS:
;

PUBLIC	blt_pat_dst_same_pattern_row_loop
blt_pat_dst_same_pattern_row_loop	PROC

	call	nibble_function
	add	si,((SCREEN_DSCAN / 4) * 8)
	add	di,((SCREEN_DSCAN / 4) * 8)
	jnc	@F
        inc     word ptr dst_bank
        mov     dx,dst_bank
	SET_BANK	; call	set_both_banko
@@:	sub	word ptr same_pattern_row_counter,8
	jnc	blt_pat_dst_same_pattern_row_loop
	ret

blt_pat_dst_same_pattern_row_loop	ENDP		;


;
;       blt_pat_dst_even_nibbles
;
;       This routine rops the even nibbles of the src with the pattern in the
;       foreground latches and places the result in the even nibbles of the dst
;       NOTE: If ds:si = es:di then this is a (pattern,dst) rop -- right?
;             This routine only handles blts that ascend in x,y -- X+,Y+
;
;       PARMS:
;       BH:BL   right edge mask : left edge mask
;

PUBLIC  blt_pat_dst_even_nibbles
blt_pat_dst_even_nibbles        PROC    NEAR

        push    si
        push    di
        mov     dx,VGAREG_SQ_ADDR
        mov     al,VGAREG_SQ_MAP_MASK
        out     dx,al
        inc     dx

	or	bl,bl				;if left edge mask = 0, then
	je	blt_pat_dst_even_nibbles_right	; so does the nibble_count
        mov     al,bl                           ; and the blt is <= 1 nibble
        out     dx,al                           ; wide which is taken care of
        movsb                                   ; by the right edge mask
        inc     si
        inc     di
	mov	cx,nibble_count
	jcxz	blt_pat_dst_even_nibbles_done
        dec     cx
        je      blt_pat_dst_even_nibbles_right

        mov     al,0FH
        out     dx,al
@@:     movsb
        inc     si
        inc     di
        sub     cx,2
        ja      @B
        js      blt_pat_dst_even_nibbles_done

blt_pat_dst_even_nibbles_right:
        mov     al,bh
        out     dx,al
        movsb

blt_pat_dst_even_nibbles_done:
        pop     si
        pop     di
        ret

blt_pat_dst_even_nibbles        ENDP                ;

;
;       blt_pat_dst_odd_nibbles
;
;       This routine rops the odd nibbles of the src foreground latches into the
;       odd nibbles of the screen dst.
;             This routine only handles blts that ascend in x,y -- X+,Y+
;
;       PARMS:
;       BH:BL   right edge mask : left edge mask
;
;

PUBLIC  blt_pat_dst_odd_nibbles
blt_pat_dst_odd_nibbles        PROC    NEAR

        push    si
        push    di
	or	bl,bl				;if first edge mask is 0 then
        je      blt_pat_dst_odd_nibbles_done        ; blt is <= 1 nibble wide and
        mov     dx,VGAREG_SQ_ADDR               ; that nibble was taken care
        mov     al,VGAREG_SQ_MAP_MASK           ; of in the even nibble routine
        out     dx,al
        inc     dx

	mov	cx,nibble_count
	jcxz	blt_pat_dst_odd_nibbles_right
        mov     al,0FH
        out     dx,al
@@:     inc     si
        inc     di
        movsb
        sub     cx,2
        ja      @B
        js      blt_pat_dst_odd_nibbles_done

blt_pat_dst_odd_nibbles_right:
        mov     al,bh
        out     dx,al
        inc     si
        inc     di
        movsb

blt_pat_dst_odd_nibbles_done:
        pop     di
        pop     si
        ret

blt_pat_dst_odd_nibbles        ENDP                 ;




;
;	blt_dst_pattern_row_loop
;
;	This routine calls the even nibble then the odd nibble routine to
;	make two passes over the blt rectangle. All the necessary vga
;	state restore is included herein.
;

PUBLIC	blt_dst_pattern_row_loop
blt_dst_pattern_row_loop    PROC    NEAR

	mov	bl,first_edge_mask
	mov	bh,last_edge_mask
	les	di,dword ptr dst_blt_offset
	mov	word ptr pattern_row_counter,1
	mov	dx,dst_bank			;preserve the initial state
	push	dx				; in case of two pass rop
	stc
	SET_BANK	; call	set_banko

bdprl_0:
	call	blt_dst_nibble_loop
	add	di,(SCREEN_DSCAN / 4)
	jnc	@F
	inc	word ptr dst_bank
	mov	dx,dst_bank
	stc
	SET_BANK	; call	set_banko

@@:	inc	word ptr pattern_row_counter
        mov     ax,pattern_row_counter
	cmp	ax,yExt
        ja      @F
        cmp     ax,8
	jbe	bdprl_0

@@:	pop	word ptr dst_bank
	ret

blt_dst_pattern_row_loop	ENDP		;

;
;	blt_dst_nibble_loop
;
;	This routine calls the even nibble then the odd nibble routine to
;	make two interleaved passes over the blt rectangle. All the necessary
;	vga state restore is included herein.
;

PUBLIC	blt_dst_nibble_loop
blt_dst_nibble_loop PROC    NEAR

	lea	ax,blt_dst_even_nibbles
        mov     nibble_function,ax

@@:	push	di
	push	dst_bank
        mov     ax,yExt
        sub     ax,pattern_row_counter
        mov     same_pattern_row_counter,ax
	call	load_fglatches
	call	blt_dst_same_pattern_row_loop

	pop	dx
	mov	dst_bank,dx
	stc
	SET_BANK	; call	set_banko
        pop     di

	lea	ax,blt_dst_odd_nibbles
	mov	cx,ax
	xchg	ax,nibble_function
	cmp	ax,cx
	jne	@B
	ret

blt_dst_nibble_loop ENDP			;

;
;	blt_dst_same_pattern_row_loop
;
;	This routine blts every other nibble on all rows of the blt rectangle
;	that are equivalent modulo 8. This is because the same pattern nibble
;	is used in all these spots.
;	PARMS:
;

blt_dst_same_pattern_row_loop	PROC

	call	nibble_function
	add	di,((SCREEN_DSCAN / 4) * 8)
	jnc	@F
	inc	word ptr dst_bank
	mov	dx,dst_bank
	stc
        SET_BANK	; call    set_banko
@@:	sub	word ptr same_pattern_row_counter,8
	jnc	blt_dst_same_pattern_row_loop
	ret

blt_dst_same_pattern_row_loop	ENDP



;
;	blt_dst_even_nibbles
;
;	The blt_dst_xxx_nibble routines can actually be done using the
;	blt_pat_dst_xxx_functions, by setting the VGA ALU rop to be NOCHG,
;	the extended register FE to foreground latch mode, and ds:si to
;	pretty much anything that will not generate a GPV. The latches will
;	be written in on the movsb, just as if a stosb were being used. But
;	the movsb takes significantly longer (particularly if ds:si points
;	to video memory) so I copied the routines changing movsb to stosb.
;
;	This routine places the pattern in the foreground latches into the
;	even nibbles of the screen dst.
;	      This routine only handles blts that ascend in x,y -- X+,Y+
;
;	PARMS:
;	BH:BL	right edge mask : left edge mask
;
;

PUBLIC	blt_dst_even_nibbles
blt_dst_even_nibbles	    PROC    NEAR

	push	di
	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_MAP_MASK
	out	dx,al
	inc	dx

	or	bl,bl
	je	blt_dst_even_nibbles_right
        mov     al,bl
	out	dx,al
	stosb
	inc	di
	mov	cx,nibble_count
	jcxz	blt_dst_even_nibbles_done
	dec	cx
	je	blt_dst_even_nibbles_right

	mov	al,0FH
	out	dx,al
@@:	stosb
	inc	di
	sub	cx,2
	ja	@B
	js	blt_dst_even_nibbles_done

blt_dst_even_nibbles_right:
	mov	al,bh
	out	dx,al
	stosb

blt_dst_even_nibbles_done:
	pop	di
	ret

blt_dst_even_nibbles	    ENDP

;
;	blt_dst_odd_nibbles
;
;	This routine places the pattern in the foreground latches into the
;	odd nibbles of the screen dst.
;	      This routine only handles blts that ascend in x,y -- X+,Y+
;
;	PARMS:
;	BH:BL	right edge mask : left edge mask
;
;

PUBLIC	blt_dst_odd_nibbles
blt_dst_odd_nibbles	   PROC    NEAR

	push	di
	or	bl,bl			    ;if no left edge mask,then blt
	je	blt_dst_odd_nibbles_done    ; is <= 1 nibble wide so it was
	mov	dx,VGAREG_SQ_ADDR	    ; taken care of in the even
	mov	al,VGAREG_SQ_MAP_MASK	    ; nibble pass
	out	dx,al
	inc	dx

	mov	cx,nibble_count
        jcxz    blt_dst_odd_nibbles_right
	mov	al,0FH
	out	dx,al
@@:	inc	di
	stosb
	sub	cx,2
	ja	@B
	js	blt_dst_odd_nibbles_done

blt_dst_odd_nibbles_right:
	mov	al,bh
	out	dx,al
	inc	di
	stosb
	dec	di

blt_dst_odd_nibbles_done:
	pop	di
	ret

blt_dst_odd_nibbles	   ENDP 		;


;
;	blt_pat_dst_loop
;

PUBLIC	blt_pat_dst_loop
blt_pat_dst_loop	PROC	NEAR

	call	set_fglatches
	lds	si,dword ptr dst_blt_offset
	les	di,dword ptr dst_blt_offset	;reset vga dst state. For the
	mov	dx,dst_bank		; times we use this routine, srcaddr =
	SET_BANK	; call	set_both_banko		; dstaddr so bank selects are equal
	mov	bl,first_edge_mask
	mov	bh,last_edge_mask
	mov	ax,yExt
	mov	pattern_row_counter,ax

blt_pat_dst_loop_0:
	call	blt_pat_dst_nibbles
	mov	si,di
	add	si,SCREEN_DSCAN / 4
	add	di,SCREEN_DSCAN / 4
	jnc	@F
	inc	word ptr dst_bank
	mov	dx,dst_bank
	SET_BANK	; call	set_both_banko

@@:	dec	word ptr pattern_row_counter
	jne	blt_pat_dst_loop_0
	ret

blt_pat_dst_loop	ENDP				;

;
;	blt_pat_dst_nibbles
;
;	This routine assumes that even and odd nibbles are the same.
;	Basically the two routines were combined into this one.
;             This routine only handles blts that ascend in x,y -- X+,Y+
;
;       PARMS:
;       BH:BL   right edge mask : left edge mask
;

PUBLIC	blt_pat_dst_nibbles
blt_pat_dst_nibbles	PROC	NEAR

	push	di
	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_MAP_MASK
	out	dx,al
	inc	dx

	or	bl,bl
	je	@F
        mov     al,bl
	out	dx,al
	movsb

@@:	mov	cx,nibble_count
	mov	al,0FH
	out	dx,al
	rep	movsb

	mov	al,bh
	out	dx,al
	movsb
	pop	di
	ret

blt_pat_dst_nibbles	ENDP			;

;
;       blt_dst_loop
;

PUBLIC  blt_dst_loop
blt_dst_loop    PROC    NEAR

        call    set_fglatches
	les	di,dword ptr dst_blt_offset	  ;reset vga dst state
        mov     dx,dst_bank
        stc
        SET_BANK	; call    set_banko
	mov	bl,first_edge_mask
        mov     bh,last_edge_mask
	mov	ax,yExt
	mov	pattern_row_counter,ax

blt_dst_loop_0:
        call    blt_dst_nibbles
        add     di,SCREEN_DSCAN / 4
        jnc     @F
	inc	word ptr dst_bank
        mov     dx,dst_bank
        stc
        SET_BANK	; call    set_banko
@@:	dec	word ptr pattern_row_counter
        jne     blt_dst_loop_0
        ret

blt_dst_loop    ENDP                            ;

;
;	blt_dst_nibbles
;
;	This routine assumes that even and odd nibbles are the same.
;	Basically the two routines were combined into this one.
;             This routine only handles blts that ascend in x,y -- X+,Y+
;
;       PARMS:
;       BH:BL   right edge mask : left edge mask
;

PUBLIC	blt_dst_nibbles
blt_dst_nibbles PROC	NEAR

	push	di
	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_MAP_MASK
	out	dx,al
	inc	dx

	or	bl,bl
	je	@F
        mov     al,bl
	out	dx,al
	stosb

@@:	mov	cx,nibble_count
	mov	al,0FH
	out	dx,al
	rep	stosb

	mov	al,bh
	out	dx,al
	stosb
	pop	di
	ret

blt_dst_nibbles ENDP			;

;
;	load_fglatches
;
;	This routine loads the fg_latches from the pattern pointed to by
;	the variable pattern_offset. Pattern_offset is advanced by 4 after
;	the first 4 bytes are laoded in.
;

PUBLIC	load_fglatches
load_fglatches	PROC	NEAR

	push	si
	mov	si,pattern_offset
	mov	dx,VGAREG_SQ_ADDR

	mov	al,0ECH
	mov	ah,ss:[si]
	out	dx,ax

	inc	al
	mov	ah,ss:[si + 1]
        out     dx,ax

	inc	al
	mov	ah,ss:[si + 2]
        out     dx,ax

	inc	al
	mov	ah,ss:[si + 3]
        out     dx,ax

	add	si,4
	mov	pattern_offset,si
	pop	si
	ret

load_fglatches	ENDP			;

;
;	set_fglatches
;
;	This routine loads the fg_latches from the pattern pointed to by
;	the variable pattern_offset. Pattern_offset is advanced by 4 after
;	the first 4 bytes are laoded in.
;

PUBLIC	set_fglatches
set_fglatches  PROC    NEAR

	mov	dx,VGAREG_SQ_ADDR
	mov	al,0ECH
	out	dx,ax
	inc	al
	out	dx,ax
	inc	al
	out	dx,ax
	inc	al
	out	dx,ax
	ret

set_fglatches	ENDP

sEnd    CODE

END
