;
;	FILE:	blt216.asm
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module contains routines that deal with screen to screen blts
;	using 216 advanced hardware features (align src to dst and ROP hw.)
;

SRCFILE_BLT216	equ	1
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

;REPCOUNT	EQU	8


.286
sBegin	Code
assumes cs,Code
assumes ds,Nothing
assumes es,Nothing
assumes ss,Nothing

PUBLIC	remap_rop
remap_rop	LABEL	BYTE
DB	00H, 01H, 04H, 05H, 02H, 03H, 06H, 07H
DB	08H, 09H, 0CH, 0DH, 0AH, 0BH, 0EH, 0FH

PUBLIC  read_modify_write_needed
read_modify_write_needed	LABEL	BYTE
DB	00H, 20H, 20H, 20H, 20H, 00H, 20H, 20H
DB	20H, 20H, 00H, 20H, 20H, 20H, 20H, 00H

;	blt216_src_dst
;
;	This routine handles all 16 logical-operand blts involving src and
;	dst -- no pattern is involved (both src and dst must be the display.)

PUBLIC	blt216_src_dst
blt216_src_dst	PROC	NEAR

	call	blt216_src_dst_prep
	lds	si,dword ptr src_blt_offset
	les	di,dword ptr dst_blt_offset
	cmp	word ptr vert_dir,0
	jne	short blt216_src_dst_down

blt216_src_dst_loop:

	dec	word ptr yExt
	js	blt216_src_dst_done
	call	word ptr blt216_scandir_func

	add	si,src_width_bytes
	jns	@F
	and	si,7FFFH			;32K src wrap
	add	word ptr src_page,8H
	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_SRC_SPLITBANK
	mov	ah,src_page
	out	dx,ax

@@:	add	di,dst_width_bytes
	js	@F
	or	di,8000H			;32K dst wrap
	add	word ptr dst_page,8H
	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_DST_SPLITBANK
	mov	ah,dst_page
        out     dx,ax
@@:	jmp	blt216_src_dst_loop


blt216_src_dst_down:

	dec	word ptr yExt
	js	blt216_src_dst_done
	call	word ptr blt216_scandir_func

	sub	si,src_width_bytes
	jns	@F
	and	si,7FFFH			;32K src wrap
	sub	word ptr src_page,8H
	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_SRC_SPLITBANK
	mov	ah,src_page
	out	dx,ax

@@:	sub	di,dst_width_bytes
	js	@F
	or	di,8000H			;32K dst wrap
	sub	word ptr dst_page,8H
	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_DST_SPLITBANK
	mov	ah,dst_page
        out     dx,ax
@@:	jmp	blt216_src_dst_down

blt216_src_dst_done:

	call	blt216_src_dst_cleanup
	ret

blt216_src_dst  ENDP




;	blt216_src_dst_prep
;
;	This routine does preparation for src,dst blts.

PUBLIC	blt216_src_dst_prep
blt216_src_dst_prep  PROC    NEAR

;       enable split bank addressing

	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_SPLITBANK
        out     dx,al
        inc     dx
        in      al,dx
        or      al,80H
        out     dx,al

;	compute the src addr which will be:
;		addr of first src pixel minus (DestxOrg & 7)

	mov	ax,SrcyOrg		;src addr should be seq chain 4
        mov     bx,SrcxOrg
	mov	dx,src_width_bytes
	mul	dx
	add	ax,bx			;compute address for splitbank

	mov	cx,DestxOrg
	and	cx,7
	sub	ax,cx
	sbb	dx,0
	and	dx,0FH			;only 1M of memory

	shl	ax,1			; offset within a 32K window
	rcl	dx,1
	shr	ax,1
        mov     src_blt_offset,ax
	shl	dl,3
	mov	src_page,dx
	mov	al,VGAREG_SQ_SRC_SPLITBANK
	mov	ah,dl
	mov	dx,VGAREG_SQ_ADDR
        out     dx,ax

;	compute dst address. This address will be mutiplied by 8 by the
;	216 hardware.

	mov	ax,DestyOrg		 
	mov	bx,DestxOrg
	and	bx,NOT 7
	mov	dx,dst_width_bytes
	shr	dx,3			;dst addr compute as 8-planar
	mov	dst_width_bytes,dx
	mul	dx
	shr	bx,3
	add	ax,bx
	shl	ax,1
	rcl	dx,1
	shr	ax,1
	or	ah,80H
	mov	dst_blt_offset,ax
	shl	dl,3
	mov	dst_page,dx
	mov	al,VGAREG_SQ_DST_SPLITBANK
	mov	ah,dl
	mov	dx,VGAREG_SQ_ADDR
        out     dx,ax

;	now compute the edge masks

	mov	cx,dst_left_edge
        and     cx,7
        neg     cx
        add     cx,8
	mov	ax,1
	shl	ax,cl
	dec	ax
	mov	first_edge_mask,al

	mov	cx,dst_left_edge
	add	cx,xExt
	dec	cx
	and	cx,7
	mov	al,80H
	sar	al,cl
	mov	last_edge_mask,al

	mov	ax,dst_left_edge
        mov     bx,ax
        shr     ax,3
        add     bx,xExt
        dec     bx
        shr     bx,3
        sub     bx,ax
	je	bsd_prep_combine_edges

	dec	bx
	mov	full_byte_count,bx
	jmp	short bsd_prep_done_edges

bsd_prep_combine_edges:

	mov	ax,first_edge_mask
	and	ax,last_edge_mask
	mov	first_edge_mask,ax
	sub	ax,ax
	mov	full_byte_count,ax
	mov	last_edge_mask,ax

bsd_prep_done_edges:

;	get the correct scanline function and order the masks for the
;	correct blt direction

	cld
	lea	cx,blt216_src_dst_ltor_scanline
        cmp     word ptr horz_dir,0
        je      @F
        std
	lea	cx,blt216_src_dst_rtol_scanline
	mov	bl,first_edge_mask
	xchg	bl,last_edge_mask
	mov	first_edge_mask,bl
@@:	mov	blt216_scandir_func,cx

	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_FOREBACK_MODE
	out	dx,al
	inc	dx
	in	al,dx				;use the bg latches as
	or	al,2CH				; input A into the ALU
	out	dx,al

	mov	dx,VGAREG_SQ_ADDR
	mov	ax,VGAREG_SQ_XALU_CONTROL +  (0C2H SHL 8)
	mov	bl,byte ptr Rop[2]
	and	bx,0FH			;convert rop3(p,s,d) to rop2(s,d)
	mov	bl,cs:remap_rop[bx]	;Oops! hardware rops are backwards
	or	ah,cs:read_modify_write_needed[bx]
	mov	blt216_reg_cd,ah
	out	dx,ax			;enable XALU and RMW as needed

	mov	al,VGAREG_SQ_XALU
	mov	ah,0CH				;bgrop = 'B' (input B to ALU)
	shl	bl,4
	or	ah,bl
	out	dx,ax				;specify the rop being used
	ret

blt216_src_dst_prep  ENDP



;	blt216_src_dst_cleanup
;
;
PUBLIC	  blt216_src_dst_cleanup
blt216_src_dst_cleanup	PROC	NEAR

	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_FOREBACK_MODE
	out	dx,al
	inc	dx
	in	al,dx
	and	al,NOT 3CH
	out	dx,al

	mov	dx,VGAREG_SQ_ADDR
	mov	ax,VGAREG_SQ_XALU_CONTROL + (00H SHL 8)
	out	dx,ax

        mov     al,VGAREG_SQ_SPLITBANK
        out     dx,al
        inc     dx
        in      al,dx
        and     al,NOT 80H
        out     dx,al
        ret

blt216_src_dst_cleanup	ENDP



;   blt216_src_dst_ltor_scanline
;
;   This routine blits one scanline and rops src and dst.
;
;   PARMS:
;   direction flag cleared or set as appropriate
;   DS:SI       -       ptr to src
;   ES:DI	-	ptr to dest
;   foreback mode set to bglatches into A input of ALU
;   XALU control set to C2 or E2 as appropriate

blt216_src_dst_ltor_scanline	PROC	NEAR

	push	si
	push	di

	mov	dx,VGAREG_SQ_ADDR		;for the edge, we need rmw
	mov	al,VGAREG_SQ_XALU_CONTROL	; cycles to permit masking
	mov	ah,0E2H
ifdef REPCOUNT
rept REPCOUNT
	jmp $+2
endm
endif
        out     dx,ax

	mov	al,0F5H
	mov	ah,first_edge_mask
	out	dx,ax
	movsb
        add     si,7
	jns	@F
	and	si,7FFFH
	add	word ptr dst_page,8H
	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_SRC_SPLITBANK
	mov	ah,dst_page
        out     dx,ax

@@:
	jmp	fancyMovsb

blt216_src_dst_ltor_scanline	ENDP



;
;   blt216_src_dst_rtol_scanline
;
;   This routine blits one scanline and rops src and dst.
;
;   PARMS:
;   direction flag cleared or set as appropriate
;   DS:SI       -       ptr to src
;   ES:DI	-	ptr to dest
;   foreback mode set to bglatches into A input of ALU
;   XALU control set to C2 or E2 as appropriate

blt216_src_dst_rtol_scanline	PROC	NEAR

	push	si
	push	di

	mov	dx,VGAREG_SQ_ADDR		;for the edge, we need rmw
	mov	al,VGAREG_SQ_XALU_CONTROL	; cycles to permit masking
	mov	ah,0E2H
ifdef REPCOUNT
rept REPCOUNT
	jmp $+2
endm
endif
        out     dx,ax

	mov	al,0F5H
	mov	ah,first_edge_mask
	out	dx,ax
	movsb
        sub     si,7

fancyMovsb:
        mov     cx, full_byte_count
	or	cx,cx
	je	fancySkip
;	push	cx
;	and	cx,0fff8h

	mov	al,VGAREG_SQ_XALU_CONTROL	;for the middle, don't use
        mov     ah,blt216_reg_cd                ; rmw cycles if only writes
ifdef REPCOUNT
rept REPCOUNT
	jmp $+2
endm
endif
        out     dx,ax                           ; are needed

	mov	al,0F5H
	mov	ah,0FFH
	out	dx,ax
	mov	al,VGAREG_SQ_XMISCCTL2 ; Set index port
	out	dx,al
	inc	dx	; Point to data port
	in	al,dx	; Get current misc. cont. reg. 2
	push	ax   	; Save
	or	al,VGA216_SQ_XMISCCTL2_ENMOVSB ; Turn on ENMOVSB
	out	dx,al	; Reset misc...reg
	mov	dx,VGAREG_GR_ADDR ; Select gr.. reg
	mov	ax,si	; Get source offset
	shr	si,3	; Addr. data interp w/ 3-bit shift
	and	ax,0007h ; Get 3 ls bits (8-offset)
	push	ax	; Save it
	mov	ah,al	; Into ah
; Prepare for movsb 8-at-a-time align-source-to-data mode
	mov	al,VGAREG_GR_FUNCTION
	out	dx,ax	; Set within-8 offset
	rep	movsb	; Do it
	shl	si,3	; Restore real address offset
	pop	ax	; Recover 3 ls bits in al
	add	si,ax	; Now si is as it should have been
	mov	ah,0	; Disable fancy movsb
	out	dx,ax

	mov	dx,VGAREG_SQ_ADDR
	pop	ax	; Reset with value in al
	xchg	ah,al
	mov	al,VGAREG_SQ_XMISCCTL2 ; Set index port
	out	dx,ax
	mov	al,VGAREG_SQ_XALU_CONTROL	;for the edge, we need rmw
	mov	ah,0E2H 			; cycles to permit masking
ifdef REPCOUNT
rept REPCOUNT
	jmp $+2
endm
endif
        out     dx,ax

;	pop	cx
;	and	cx,0007h
;	je	fancySkip
;fancyExtraLoop:
;	movsb				;grab 8 pixels into extended bg latches
;	add	si,7			;since al = 0FFH, all fgrop
;	dec	cx
;	loop	fancyExtraLoop
fancySkip:
	mov	al,0F5H
	mov	ah,last_edge_mask
	out	dx,ax
	movsb

        pop     di
	pop	si
	ret

blt216_src_dst_rtol_scanline	ENDP


;	blt216_pat_dst
;
;	This routine handles all 16 logical-operand blts involving pat and
;	dst -- no src is involved (dst must be the display.)

PUBLIC	blt216_pat_dst
blt216_pat_dst	PROC	NEAR

	call	blt216_pat_dst_prep
	lds	si,dword ptr src_blt_offset
	les	di,dword ptr dst_blt_offset
	mov	ax,yExt
	cmp	ax,8
	jbe	@F
	mov	ax,8
@@:	mov	pattern_row_counter,ax

blt216_pat_dst_bigloop:

	mov	ax,yExt
	mov	same_pattern_row_counter,ax

blt216_pat_dst_smallloop:

	call	blt216_scandir_func
	add	di,dst_width_bytes		;skip down 8 lines
	js	@F
        or      di,8000H                        ;32K dst wrap
	add	byte ptr dst_page,8H
        mov     dx,VGAREG_SQ_ADDR
        mov     al,VGAREG_SQ_DST_SPLITBANK
        mov     ah,dst_page
        out     dx,ax

@@:	sub	word ptr same_pattern_row_counter,8
	jg	blt216_pat_dst_smallloop

	mov	ah,dst2_page
        mov     di,dst2_blt_offset
        add     di,dst2_width_bytes
	js	@F
	or	di,8000H
	add	ah,08H
@@:	mov	dx,VGAREG_SQ_ADDR
        mov     al,VGAREG_SQ_DST_SPLITBANK
        out     dx,ax
        mov     dst2_blt_offset,di
        mov     dst2_page,ah
	mov	dst_page,ah

	add	si,8
	dec	word ptr yExt
	dec	word ptr pattern_row_counter
	jg	blt216_pat_dst_bigloop

        call    blt216_pat_dst_cleanup
	ret

blt216_pat_dst	ENDP




;	blt216_pat_dst_prep
;
;	This routine does preparation for pat,dst blts.

PUBLIC	blt216_pat_dst_prep
blt216_pat_dst_prep  PROC    NEAR

;       enable split bank addressing

	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_SPLITBANK
        out     dx,al
        inc     dx
        in      al,dx
        or      al,80H
        out     dx,al

;	the pattern needs to be placed in video memory so that it can
;	be loaded into the extended background latches by a memory read.
;	The 64 byte pattern will be placed 256+64 bytes before the end
;	of video memory. The reason for this is that if a hardware cursor
;	is being used, it will be in the last 256 bytes.

	mov	dx,VGAREG_SQ_ADDR	;find bank location of hardware cursor
	mov	al,0FFH 		; which is always the last bank in mem
	out	dx,al
	inc	dx
	in	al,dx
	and	al,60H
	shl	ax,9
	or	ah,038H 		;set src splitbank window to last
	dec	dx			;32K of video memory
	mov	al,VGAREG_SQ_SRC_SPLITBANK
	out	dx,ax

	mov	ax,ss
	mov	ds,ax
	mov	si,pattern_offset
	mov	es,dst_blt_segment	;load the screen selector
	mov	di,07FFFH - 100H - 03FH ;end of memory - 256 - 64
	mov	src_blt_segment,es
	mov	src_blt_offset,di
	mov	cx,20H			;copy pattern into video memory
	rep	movsw

;	compute dst address. This address will be mutiplied by 8 by the
;	216 hardware.

	mov	ax,DestyOrg		 
	mov	bx,DestxOrg
	and	bx,NOT 7
	mov	dx,dst_width_bytes
	shr	dx,3			;dst addr compute as 8-planar
	mov	dst2_width_bytes,dx
	mul	dx
	shr	bx,3
	add	ax,bx
	shl	ax,1
	rcl	dx,1
	shr	ax,1
	or	ah,80H
	mov	dst_blt_offset,ax
	mov	dst2_blt_offset,ax
        shl     dl,3
	mov	dst_page,dx
	mov	dst2_page,dx
	mov	al,VGAREG_SQ_DST_SPLITBANK
	mov	ah,dl
	mov	dx,VGAREG_SQ_ADDR
        out     dx,ax

;	now compute the edge masks

	mov	cx,dst_left_edge
        and     cx,7
        neg     cx
        add     cx,8
	mov	ax,1
	shl	ax,cl
	dec	ax
	mov	first_edge_mask,al

	mov	cx,dst_left_edge
	add	cx,xExt
	dec	cx
	and	cx,7
	mov	al,80H
	sar	al,cl
	mov	last_edge_mask,al

	mov	ax,dst_left_edge
        mov     bx,ax
        shr     ax,3
        add     bx,xExt
        dec     bx
        shr     bx,3
        sub     bx,ax
	je	bpd_prep_combine_edges

	dec	bx
	mov	full_byte_count,bx
	jmp	short bpd_prep_done_edges

bpd_prep_combine_edges:

	mov	ax,first_edge_mask
	and	ax,last_edge_mask
	mov	first_edge_mask,ax
	sub	ax,ax
	mov	full_byte_count,ax
	mov	last_edge_mask,ax

bpd_prep_done_edges:

	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_FOREBACK_MODE
	out	dx,al
	inc	dx
	in	al,dx				;use the bg latches as
	or	al,0CH				; input A into the ALU
	out	dx,al

	mov	dx,VGAREG_SQ_ADDR
	mov	ax,VGAREG_SQ_XALU_CONTROL +  (0C2H SHL 8)
	mov	bl,byte ptr Rop[2]
	and	bx,003CH		;convert rop3(p,s,d) to rop2(s,d)
	shr	bl,2
	mov	bl,cs:remap_rop[bx]	;Oops! hardware rops are backwards
	or	ah,cs:read_modify_write_needed[bx]
	mov	blt216_reg_cd,ah
	out	dx,ax			;enable XALU and RMW as needed

%OUT	remove the 5 lines below when the HT216 rmw problem is solved
	mov	cx,OFFSET blt216_pat_dst_scanline  ;assume no rmw required
	test	byte ptr cs:read_modify_write_needed[bx],20H
	jz	@F
	mov	cx,OFFSET blt216_pat_dst_scanline_rmw
@@:	mov	blt216_scandir_func,cx

	mov	al,VGAREG_SQ_XALU
	mov	ah,0CH				;bgrop = 'B' (input B to ALU)
	shl	bl,4
	or	ah,bl
	out	dx,ax				;specify the rop being used

	cld
	ret

blt216_pat_dst_prep  ENDP



;	blt216_pat_dst_cleanup
;
;
PUBLIC	  blt216_pat_dst_cleanup
blt216_pat_dst_cleanup	PROC	NEAR

        mov     dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_FOREBACK_MODE
	out	dx,al
	inc	dx
	in	al,dx
	and	al,NOT 0CH
	out	dx,al

	dec	dx
	mov	ax,VGAREG_SQ_XALU_CONTROL + (00H SHL 8)
	out	dx,ax

	mov	al,VGAREG_SQ_SPLITBANK
        out     dx,al
        inc     dx
        in      al,dx
        and     al,NOT 80H
        out     dx,al
        ret

blt216_pat_dst_cleanup	ENDP




;   blt216_pat_dst_scanline
;
;   This routine blits one scanline and rops bglatches and dst.
;
;   PARMS:
;   direction flag cleared
;   ES:DI	-	ptr to dest
;   foreback mode set to bglatches into A input of ALU
;   XALU control set to C2 or E2 as appropriate

blt216_pat_dst_scanline    PROC    NEAR

	push	di

	mov	dx,VGAREG_SQ_ADDR		;for the edge, we need rmw
	mov	al,VGAREG_SQ_XALU_CONTROL	; cycles to permit masking
	mov	ah,0E2H
ifdef REPCOUNT
rept REPCOUNT
	jmp $+2
endm
endif
        out     dx,ax

	mov	al,first_edge_mask
	mov	ah,ds:[si]
        stosb
	mov	cx, full_byte_count
	or	cx,cx
	je	bpds0

	mov	al,VGAREG_SQ_XALU_CONTROL	;for the middle, don't use
        mov     ah,blt216_reg_cd                ; rmw cycles if only writes
ifdef REPCOUNT
rept REPCOUNT
	jmp $+2
endm
endif
        out     dx,ax                           ; are needed

	mov	ax,0FFFFH
	test	di,1
	jz	@F
	stosb
	dec	cx
@@:	shr	cx,1
	rep	stosw
	rcl	cx,1
	rep	stosb

	mov	al,VGAREG_SQ_XALU_CONTROL	; cycles to permit masking
	mov	ah,0E2H
ifdef REPCOUNT
rept REPCOUNT
	jmp $+2
endm
endif
        out     dx,ax

bpds0:
	mov	ah,ds:[si]
        mov     al,last_edge_mask
        stosb

        pop     di
	ret

blt216_pat_dst_scanline    ENDP




;   blt216_pat_dst_scanline_rmw
;
;   This routine blits one scanline and rops bglatches and dst.
;
;   PARMS:
;   direction flag cleared
;   ES:DI	-	ptr to dest
;   foreback mode set to bglatches into A input of ALU
;   XALU control set to C2 or E2 as appropriate

blt216_pat_dst_scanline_rmw PROC    NEAR

	push	di

	mov	dx,VGAREG_SQ_ADDR		;for the edge, we need rmw
	mov	al,VGAREG_SQ_XALU_CONTROL	; cycles to permit masking
	mov	ah,0E2H
ifdef REPCOUNT
rept REPCOUNT
	jmp $+2
endm
endif
        out     dx,ax

	mov	al,first_edge_mask
	mov	ah,ds:[si]
        stosb
	mov	cx, full_byte_count
	or	cx,cx
	je	bpds1

	mov	al,VGAREG_SQ_XALU_CONTROL	;for the middle, don't use
        mov     ah,blt216_reg_cd                ; rmw cycles if only writes
ifdef REPCOUNT
rept REPCOUNT
	jmp $+2
endm
endif
        out     dx,ax                           ; are needed

        mov     ax,0FFFFH
IF	1
;	 rep	 stosb			 ;since al = 0FFH, all fgrop
	test	di,1
	jz	@F
	stosb
	dec	cx
@@:
	shr	cx,1
	rep	stosw
	adc	cx,cx
	rep	stosb
ELSE
@@:
	mov	ah,ds:[si]
	stosb
	loop	@B
ENDIF

	mov	al,VGAREG_SQ_XALU_CONTROL	; cycles to permit masking
	mov	ah,0E2H
ifdef REPCOUNT
rept REPCOUNT
	jmp $+2
endm
endif
        out     dx,ax

bpds1:
	mov	al,last_edge_mask
;	mov	ah,ds:[si]
        stosb

        pop     di
	ret

blt216_pat_dst_scanline_rmw  ENDP

sEnd    Code

END
