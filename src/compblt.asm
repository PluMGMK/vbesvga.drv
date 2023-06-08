;
;	FILE:	compblt.asm
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module contains routines that generate code into a dest.
;	Every routine in this module assumes that es:di points to the
;	place to store the compiled code.
;

SRCFILE_COMPBLT equ	1
incLogical	=	1
incDrawMode	=	1

include cmacros.inc
include gdidefs.inc
include display.inc
include vgareg.inc
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

extrn	roptable:byte

;
;	compile_mono_pattern_fetch
;
;	This routine places pattern fetch code onto the stack. The template
;	is shown below. The bp register will be used as the pattern pointer
;	during the execution of the compiled blt code. This routine is only
;	used for mono patterns. For color patterns things are a bit more
;	complex.
;
;	PARMS:
;	pattern must be located at an address that is:
;		0 modulo  8 in the case of a mono pattern
;

mono_pattern_fetch_template:
	mov	dh,[bp + 01234H]	;1234 will become address of pattern
mpft0:	inc	bp			;if the direction is x-, then dec bp
	and	bp,07H

MPFT_SIZE = $ - mono_pattern_fetch_template
MPFT0_OFFSET = $ - mpft0

PUBLIC	compile_mono_pattern_fetch
compile_mono_pattern_fetch   PROC    NEAR

	lea	si,mono_pattern_fetch_template
	mov	cx,MPFT_SIZE
	rep	movs byte ptr es:[di], cs:[si]

	mov	bx,pattern_offset
	mov	es:[di - MPFT0_OFFSET - 2],bx	;fixup pattern address
	or	word ptr dst_xExt_bytes,0	;if the x direction is X-
	jns	@F				; then change inc bp to dec bp
	mov	byte ptr es:[di - MPFT0_OFFSET],I_DEC_BP
@@:	ret

compile_mono_pattern_fetch   ENDP



;
;	compile_color_pattern_fetch
;
;	This routine places pattern fetch code onto the stack. The template
;	is shown below. The bp register will be used as the pattern pointer
;	during the execution of the compiled blt code. This routine is only
;	used for color patterns. We have to modify and wrap the low 3 bits
;	only i.e. bits 2:0. The higher order bits contain the offset to the
;	row of the color pattern.
;
;	PARMS:
;	pattern must be located at an address that is:
;		0 modulo 64 in the case of a color pattern
;

color_pattern_fetch_template:
	and	bp,NOT 07H
	or	bp,ss:[01234H]	      ;1234 becomes pattern column counter addr
cpft:	mov	dh,[bp + 01234H]      ;01234H will become address of pattern
cpft0:	inc	word ptr ss:[01234H]  ;1234 becomes pattern column counter addr
cpft1:	and	word ptr ss:[01234H],5678H ;1234 becomes pat col counter addr
cpft2:				      ; and 5678 will become 07H -- if 07H were
				      ; put there the code length is compiler
				      ; dependent (there is a short form of the
				      ; and word ptr [####],$$$$ where $$$$ is
				      ; only a byte which is sign extended to a
				      ; word before being ANDed. I make certain
				      ; that $$$$ is the full word form of the
				      ; instruction by using 5678H and then do
				      ; the fixup.) JAKX

CPFT_SIZE = $ - color_pattern_fetch_template
CPFT_OFFSET  = $ - cpft
CPFT0_OFFSET = $ - cpft0
CPFT1_OFFSET = $ - cpft1
CPFT2_OFFSET = $ - cpft2

PUBLIC	compile_color_pattern_fetch
compile_color_pattern_fetch	PROC	NEAR

	lea	si,color_pattern_fetch_template
	mov	cx,CPFT_SIZE
	rep	movs byte ptr es:[di], cs:[si]

	mov	bx,pattern_offset
	mov	es:[di - CPFT0_OFFSET - 2],bx	;fixup pattern address
	or	word ptr dst_xExt_bytes,0	;if the x direction is X-
	jns	@F				; then change inc bp to dec bp
	mov	word ptr es:[di - CPFT0_OFFSET + 1],I_DEC_MEM_WORD
@@:	lea	bx,pattern_row_counter
	mov	es:[di - CPFT_OFFSET - 2],bx
	mov	es:[di - CPFT1_OFFSET - 2],bx
	mov	es:[di - CPFT2_OFFSET - 4],bx
	mov	word ptr es:[di - CPFT2_OFFSET - 2],0007H
	ret

compile_color_pattern_fetch	ENDP



;
;	compile_pattern_yupdate
;
;	This routine creates code to update the pattern pointer to the next
;	row of pattern data. Note that it should only be used when the dst
;	is color, because mono dsts change pattern rows with the code from
;	compile_mono_pattern_fetch -- (to go to the next row of a mono
;	pattern, you simply add 1 to the pattern pointer register bp). To
;	go to the next row of a color pattern, you need to add the width of
;	the pattern into the pattern pointer.
;
;	PARMS:
;	pattern must be located at an address that is:
;		0 modulo 64 in the case of a color pattern
;

pattern_yupdate_template:
	add	bp,SIZE_PATTERN
	and	bp,SIZE_PATTERN * (SIZE_PATTERN - 1)
	mov	word ptr ss:[1234H],5678H    ;zero out pattern column counter
					     ; for start of next line. 5678H
					     ; becomes a 0000H. I want to force
					     ; use of the long form of the
					     ; instruction so that the code is
					     ; not assembler dependent.

PYUD_SIZE = $ - pattern_yupdate_template
PYUD_OFFSET = $ - pattern_yupdate_template
I_SUB_BP_I	equ	0ED83H		  ;sub bp,#	   instruction

PUBLIC	compile_pattern_yupdate
compile_pattern_yupdate PROC	NEAR

	lea	si,pattern_yupdate_template
	mov	cx,PYUD_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	lea	bx,pattern_row_counter
	mov	es:[di - 4],bx
	mov	word ptr es:[di - 2],0

	or	word ptr dst_swing_bytes,0	;if the y direction is y-
	jns	@F				; then change inc bp to dec bp
	mov	word ptr es:[di - PYUD_OFFSET],I_SUB_BP_I
@@:	ret

compile_pattern_yupdate ENDP



;
;	compile_rop
;
;	This routine places the rop code onto the stack. The template
;	is shown below.
;
;	PARMS:
;	The rop_flags variable should have been set on the stack.
;

PUBLIC	compile_rop
compile_rop	PROC	NEAR

	mov	ax,rop_offset			;get offset of ropcode template
	or	ax,ax				;if its 0, then ROP = NOP
	je	@F
	lea	si,roptable
	add	si,ax
	and	word ptr device_flags,NOT DEVFLAG_MOVSB
	mov	cx,rop_length			;else get length of rop code
	rep	movs byte ptr es:[di], cs:[si]

@@:	test	rop_flags,NEGATE_NEEDED 	;see if a final negate needed
	je	@F
	and	word ptr device_flags,NOT DEVFLAG_MOVSB
        mov     ax,I_NOT_AL
	stosw
@@:	ret

compile_rop	ENDP




;
;	compile_edge_mask
;
;	This routine places edge masking code onto the stack. It is only
;	needed for mono dsts. The template is below.
;
;	PARMS:
;	AH:AL	edge mask:NOT edge mask
;

edge_mask_template:
	mov	ah,es:[di]
	and	ax,01234H		;the 1234 will be replaced with the
emt0:	or	al,ah			; correct edge mask value
	stosb

EMT_SIZE = $ - edge_mask_template
EMT0_OFFSET = $ - emt0 + 2

PUBLIC	compile_edge_mask
compile_edge_mask   PROC    NEAR

	lea	si,edge_mask_template
	mov	cx,EMT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	mov	es:[di - EMT0_OFFSET],ax
	ret

compile_edge_mask   ENDP



;
;       compile_inner_loop_start
;
;	This routine places the inner loop start code onto the stack.
;

PUBLIC  compile_inner_loop_start
compile_inner_loop_start   PROC    NEAR

	cmp	word ptr inner_loop_count,1
	je	@F
	mov	al,I_MOV_CX_I
	stosb
	mov	ax,inner_loop_count
	stosw
@@:	ret

compile_inner_loop_start   ENDP



;
;	compile_inner_loop_end
;
;	This routine places the inner loop end code onto the stack.
;	PARMS:
;	BX	address of start of the loop
;

PUBLIC	compile_inner_loop_end
compile_inner_loop_end	 PROC	 NEAR

	cmp	word ptr inner_loop_count,1
	jne	@F
	and	word ptr device_flags,NOT DEVFLAG_REP
	ret

@@:	mov	al,I_LOOP
	stosb
	lea	ax,[di + 1]
	sub	ax,bx
	neg	ax
	stosb
@@:     ret

compile_inner_loop_end	 ENDP



;
;	compile_outer_loop
;
;	This routine places outer loop code onto the stack.
;

outer_loop_template:
	dec	word ptr ss:[01234H]	 ;01234H becomes addr of yExt on stack
olt0:	jne	@F
	retf
@@:
OLT_SIZE = $ - outer_loop_template
OLT0 = $ - olt0 + 2

PUBLIC	compile_outer_loop
compile_outer_loop   PROC    NEAR

	lea	si,outer_loop_template
	mov	cx,OLT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	lea	ax,word ptr yExt
	mov	es:[di - OLT0],ax
	ret

compile_outer_loop   ENDP



;
;	compile_src_memory_yupdate
;
;	This routine places src memory address y update code onto the stack.
;
;	PARMS:
;	src_swing_bytes, src_fill_bytes should be available on the stack.
;

src_memory_yplus_template:
	add	si,01234H	;01234H becomes src_swing_bytes
smypt0:
        cmp     si,01234H       ;01234H becomes src_width_bytes
smypt1: jb	@F
	cmp	si,01234H	;01234H becomes -src_fill_bytes
smypt2: jb	smypt3
@@:	mov	ax,ds
	add	ax,__NEXTSEG
	mov	ds,ax
	add	si,01234H	;01234H becomes src_fill_bytes
smypt3:

SMYPT_SIZE = $ - src_memory_yplus_template
SMYPT0 = $ - smypt0 + 2
SMYPT1 = $ - smypt1 + 2
SMYPT2 = $ - smypt2
SMYPT3 = $ - smypt3 + 2


src_memory_yminus_template:
	add	si,01234H   ;01234H becomes src_swing_bytes
smymt0: cmp	si,01234H   ;01234H becomes -(src_width_bytes + src_fill_bytes)
smymt1: jc	@F
	sub	si,01234H   ;01234H will become src_fill_bytes
smymt2: mov	ax,ds
	sub	ax,__NEXTSEG
	mov	ds,ax
@@:

SMYMT_SIZE = $ - src_memory_yminus_template
SMYMT0 = $ - smymt0 + 2
SMYMT1 = $ - smymt1 + 2
SMYMT2 = $ - smymt2 + 2


PUBLIC	compile_src_memory_yupdate
compile_src_memory_yupdate   PROC    NEAR

	or	word ptr src_swing_bytes,0
	js	smy_negative
	lea	si,src_memory_yplus_template
        mov     cx,SMYPT_SIZE
        rep     movs byte ptr es:[di], cs:[si]
        mov     ax,src_swing_bytes
        mov     es:[di - SMYPT0],ax
        mov     ax,src_width_bytes
        mov     es:[di - SMYPT1],ax
	mov	ax,src_fill_bytes
	mov	es:[di - SMYPT3],ax
	neg	ax
	jne	@F
	mov	byte ptr es:[di - SMYPT2],I_JMP_SHORT
@@:	mov	es:[di - SMYPT2 - 2],ax
	ret

smy_negative:
	lea	si,src_memory_yminus_template
	mov	cx,SMYMT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,src_swing_bytes
	mov	es:[di - SMYMT0],ax
	mov	ax,src_fill_bytes
	mov	es:[di - SMYMT2],ax
	neg	ax
	sub	ax,src_width_bytes
	mov	es:[di - SMYMT1],ax
        ret

compile_src_memory_yupdate   ENDP		;

;
;	compile_src_screen_yupdate
;
;	This routine places dst screen address y update code onto the stack.
;
;	PARMS:
;	src_swing_bytes and the initial src_page should be available on the
;	stack.
;

src_screen_yplus_template:
	add	si,01234H		;01234H becomes src_swing_bytes
ssypt0: cmp	si,01234H		;01234H becomes src_width_bytes
ssypt1: jae	@F
	mov	dx,05678H		;05678H starts out at (src_page + 1)
ssypt2: inc	word ptr ss:[01234H]	;01234H becomes addr of 05678H above
ssypt3: clc				;flag indicating src opposed to dst
	call	far_set_page
@@:

SSYPT_SIZE = $ - src_screen_yplus_template
SSYPT0 = $ - ssypt0
SSYPT1 = $ - ssypt1
SSYPT2 = $ - ssypt2
SSYPT3 = $ - ssypt3

src_screen_yminus_template:
	add	si,01234H	   ;01234H becomes src_swing_bytes
ssymt0:
	cmp	si,01234H	   ;01234H becomes -src_width_bytes
ssymt1: jb	@F
	mov	dx,05678H		;05678H starts out at (src_page - 1)
ssymt2: dec	word ptr ss:[01234H]	;01234H becomes addr of 05678H above
ssymt3: clc				;flag indicating src as opposed to dst
	call	far_set_page
@@:

SSYMT_SIZE = $ - src_screen_yminus_template
SSYMT0 = $ - ssymt0
SSYMT1 = $ - ssymt1
SSYMT2 = $ - ssymt2
SSYMT3 = $ - ssymt3

PUBLIC	compile_src_screen_yupdate
compile_src_screen_yupdate   PROC    NEAR

	or	word ptr src_swing_bytes,0
	js	@F
	lea	si,src_screen_yplus_template
	mov	cx,SSYPT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,src_swing_bytes
	mov	es:[di - SSYPT0 - 2],ax
	mov	ax,src_width_bytes
	mov	es:[di - SSYPT1 - 2],ax
	mov	ax,src_page
	inc	ax
	lea	bx,[di - SSYPT2 - 2]
	mov	es:[bx],ax
	mov	es:[di - SSYPT3 - 2],bx
	ret

@@:	lea	si,src_screen_yminus_template
	mov	cx,SSYMT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,src_swing_bytes
	mov	es:[di - SSYMT0 - 2],ax
	mov	ax,src_width_bytes
	neg	ax
	mov	es:[di - SSYMT1 - 2],ax
	mov	ax,src_page
	dec	ax
	lea	bx,[di - SSYMT2 - 2]
	mov	es:[bx],ax
	mov	es:[di - SSYMT3 - 2],bx
	ret

compile_src_screen_yupdate   ENDP		;

;
;	compile_dst_memory_yupdate
;
;	This routine places dst memory address y update code onto the stack.
;
;	PARMS:
;	dst_swing_bytes, dst_fill_bytes should be available on the stack.
;

dst_memory_yplus_template:
	add	di,01234H	;01234H becomes dst_swing_bytes
dmypt0: cmp	di,01234H	;01234H becomes dst_width_bytes
dmypt1: jb	@F
	cmp	di,01234H	;01234H becomes -dst_fill_bytes
dmypt2: jb	dmypt3
@@:	mov	ax,es
	add	ax,__NEXTSEG
	mov	es,ax
	add	di,01234H     ;01234H becomes dst_fill_bytes
dmypt3:

DMYPT_SIZE = $ - dst_memory_yplus_template
DMYPT0 = $ - dmypt0 + 2
DMYPT1 = $ - dmypt1 + 2
DMYPT2 = $ - dmypt2
DMYPT3 = $ - dmypt3 + 2


dst_memory_yminus_template:
	add	di,01234H   ;01234H becomes dst_swing_bytes
dmymt0: cmp	di,01234H   ;01234H becomes -(dst_width_bytes + dst_fill_bytes)
dmymt1: jc	@F
	sub	di,01234H   ;01234H will become dst_fill_bytes
dmymt2: mov	ax,es
	sub	ax,__NEXTSEG
	mov	es,ax
@@:

DMYMT_SIZE = $ - dst_memory_yminus_template
DMYMT0 = $ - dmymt0 + 2
DMYMT1 = $ - dmymt1 + 2
DMYMT2 = $ - dmymt2 + 2


PUBLIC	compile_dst_memory_yupdate
compile_dst_memory_yupdate   PROC    NEAR

	or	word ptr dst_swing_bytes,0
	js	dmy_negative
	lea	si,dst_memory_yplus_template
	mov	cx,DMYPT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
        mov     ax,dst_swing_bytes
        mov     es:[di - DMYPT0],ax
        mov     ax,dst_width_bytes
        mov     es:[di - DMYPT1],ax
	mov	ax,dst_fill_bytes
	mov	es:[di - DMYPT3],ax
	neg	ax
	jne	@F
	mov	byte ptr es:[di - DMYPT2],I_JMP_SHORT
@@:	mov	es:[di - DMYPT2 - 2],ax
	ret

dmy_negative:
	lea	si,dst_memory_yminus_template
	mov	cx,DMYMT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,dst_swing_bytes
	mov	es:[di - DMYMT0],ax
        mov     ax,dst_fill_bytes
	mov	es:[di - DMYMT2],ax
	neg	ax
	sub	ax,dst_width_bytes
	mov	es:[di - DMYMT1],ax
        ret

compile_dst_memory_yupdate   ENDP		;

;
;	compile_dst_screen_yupdate
;
;	This routine places dst screen address y update code onto the stack.
;
;	PARMS:
;	dst_swing_bytes and the initial dst_page should be available on the
;	stack.
;

dst_screen_yplus_template:
	add	di,01234H		;01234H will become dst_swing_bytes
dsypt0: cmp	di,01234H		;01234H will become dst_width_bytes
dsypt1: jae	@F
	mov	dx,05678H		;05678H starts out at (dst_page + 1)
dsypt2: inc	word ptr ss:[01234H]	;01234H becomes addr of 05678H above
dsypt3: stc				;flag indicating dst as opposed to src
	call	far_set_page
@@:

DSYPT_SIZE = $ - dst_screen_yplus_template
DSYPT0 = $ - dsypt0
DSYPT1 = $ - dsypt1
DSYPT2 = $ - dsypt2
DSYPT3 = $ - dsypt3

dst_screen_yminus_template:
	add	di,01234H	   ;01234H becomes dst_swing_bytes
dsymt0: cmp	di,01234H	   ;01234H becomes -dst_width_bytes
dsymt1: jb	@F
	mov	dx,05678H		;05678H starts out at (dst_page - 1)
dsymt2: dec	word ptr ss:[01234H]	;01234H becomes addr of 05678H above
dsymt3: stc				;flag indicating dst as opposed to src
	call	far_set_page
@@:

DSYMT_SIZE = $ - dst_screen_yminus_template
DSYMT0 = $ - dsymt0
DSYMT1 = $ - dsymt1
DSYMT2 = $ - dsymt2
DSYMT3 = $ - dsymt3

PUBLIC	compile_dst_screen_yupdate
compile_dst_screen_yupdate   PROC    NEAR

        or      word ptr dst_swing_bytes,0
	js	@F
	lea	si,dst_screen_yplus_template
	mov	cx,DSYPT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,dst_swing_bytes
	mov	es:[di - DSYPT0 - 2],ax
	mov	ax,dst_width_bytes
	mov	es:[di - DSYPT1 - 2],ax
	mov	ax,dst_page
	inc	ax
	lea	bx,[di - DSYPT2 - 2]
	mov	es:[bx],ax
	mov	es:[di - DSYPT3 - 2],bx
	ret

@@:	lea	si,dst_screen_yminus_template
	mov	cx,DSYMT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,dst_swing_bytes
	mov	es:[di - DSYMT0 - 2],ax
	mov	ax,dst_width_bytes
	neg	ax
	mov	es:[di - DSYMT1 - 2],ax
	mov	ax,dst_page
	dec	ax
	lea	bx,[di - DSYMT2 - 2]
	mov	es:[bx],ax
	mov	es:[di - DSYMT3 - 2],bx
	ret

compile_dst_screen_yupdate   ENDP		;

;
;	compile_screen_yupdate
;
;	This routine places screen address y update code onto the stack. This
;	routine assumes that src = dst so both src and dst pages and banks
;	are set to the same thing.
;
;	PARMS:
;	dst_swing_bytes and the initial dst_page should be available on the
;	stack.
;

screen_yplus_template:
	add	di,01234H		;01234H becomes dst_swing_bytes
sypt0:	cmp	di,01234H		;01234H becomes dst_width_bytes
sypt1:	jae	@F
	mov	dx,05678H		;05678H starts out at (dst_page + 1)
sypt2:	inc	word ptr ss:[01234H]	;01234H becomes addr of 05678H above
sypt3:	call	far_set_both_pages
@@:

SYPT_SIZE = $ - screen_yplus_template
SYPT0 = $ - sypt0
SYPT1 = $ - sypt1
SYPT2 = $ - sypt2
SYPT3 = $ - sypt3

screen_yminus_template:
	add	di,01234H	   ;01234H becomes dst_swing_bytes
symt0:
	cmp	di,01234H	   ;01234H becomes -dst_width_bytes
symt1:	jb	@F
	mov	dx,05678H		;05678H starts out at (dst_page - 1)
symt2:	dec	word ptr ss:[01234H]	;01234H becomes addr of 05678H above
symt3:	call	far_set_both_pages
@@:

SYMT_SIZE = $ - screen_yminus_template
SYMT0 = $ - symt0
SYMT1 = $ - symt1
SYMT2 = $ - symt2
SYMT3 = $ - symt3

PUBLIC	compile_screen_yupdate
compile_screen_yupdate	 PROC	 NEAR

        or      word ptr dst_swing_bytes,0
	js	@F
	lea	si,screen_yplus_template
	mov	cx,SYPT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,dst_swing_bytes
	mov	es:[di - SYPT0 - 2],ax
	mov	ax,dst_width_bytes
	mov	es:[di - SYPT1 - 2],ax
	mov	ax,dst_page
	inc	ax
	lea	bx,[di - SYPT2 - 2]
	mov	es:[bx],ax
	mov	es:[di - SYPT3 - 2],bx
	ret

@@:	lea	si,screen_yminus_template
	mov	cx,SYMT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,dst_swing_bytes
	mov	es:[di - SYMT0 - 2],ax
	mov	ax,dst_width_bytes
	neg	ax
	mov	es:[di - SYMT1 - 2],ax
	mov	ax,dst_page
	dec	ax
	lea	bx,[di - SYMT2 - 2]
	mov	es:[bx],ax
	mov	es:[di - SYMT3 - 2],bx
	ret

compile_screen_yupdate	ENDP		   ;

;
;	compile_jmp_back_to_start
;
;	This routine places a final jmp at the end to go back to the start of
;	the compiled code. (Thus the next scanline will be done. The yExt
;	counter is compiled into the middle of the compile blt code immediately
;	before the segment update code. This is so that segment update will
;	not occur after the last scanline is drawn when the last scanline
;	happens to be the end of a bank. This could result in the loading
;	of an invalid selector value into a segment register.) Hence
;	following the segment update code, a jmp is required to go back to
;	the start of the blt code.
;

PUBLIC	compile_jmp_back_to_start
compile_jmp_back_to_start	PROC	NEAR

	mov	ax,I_JMP_NEAR
	stosb
	lea	ax,cblt_code
	sub	ax,di
	sub	ax,2
	stosw
	ret

compile_jmp_back_to_start	ENDP



;
;	compile_src_splitbank_yupdate
;
;	This routine places src screen address y update code onto the stack
;	assuming that splitbank adresing is being used. Remember that
;	"split banks" are 32K bytes -- not 64K bytes since the high bit of
;	the address is used as the src/dst flag. Hence instead of adding
;	and jumping on carry set/clear we will be jumping on plus/minus.
;
;	PARMS:
;	src_swing_bytes and the initial src_page should be available on the
;	stack.
;

src_splitbank_template:
	add	si,01234H		;01234H becomes src_swing_bytes
slypt0: jns	@F			; signed => "wrap" to next 32K page
	mov	ax,056E8H		;056XXH starts out at (src_page + 1)
slypt1: add	byte ptr ss:[01234H],8	;01234H becomes addr of 056H above
slypt2: mov	dx,VGAREG_SQ_ADDR	;E8 is the src splitbank reg index
	out	dx,ax			;sub 32K from si since we "added" 32K
	and	si,7FFFH		;into the splitbank src reg
@@:

SLYPT_SIZE = $ - src_splitbank_template
SLYPT0 = $ - slypt0
SLYPT1 = $ - slypt1
SLYPT2 = $ - slypt2

PUBLIC	compile_src_splitbank_yupdate
compile_src_splitbank_yupdate	PROC	NEAR

	lea	si,src_splitbank_template
	mov	cx,SLYPT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,src_swing_bytes
	mov	es:[di - SLYPT0 - 2],ax
        lea     bx,[di - SLYPT1 - 1]
	mov	es:[di - SLYPT2 - 3],bx

	or	ax,ax
        mov     ax,src_page
	js	@F
	add	ax,8
	mov	es:[bx],al
	ret

@@:	sub	ax,8
	mov	es:[bx],al
	mov	byte ptr es:[di - SLYPT2 - 1],-8
        ret

compile_src_splitbank_yupdate	ENDP



;
;	compile_dst_splitbank_yupdate
;
;	This routine places dst screen address y update code onto the stack
;	assuming that splitbank adresing is being used. Remember that
;	"split banks" are 32K bytes -- not 64K bytes since the high bit of
;	the address is used as the src/dst flag. Hence instead of adding
;	and jumping on carry set/clear we will be jumping on plus/minus.
;
;	PARMS:
;	dst_swing_bytes and the initial dst_page should be available on the
;	stack.
;

dst_splitbank_template:
	add	di,01234H		;01234H becomes dst_swing_bytes
dlypt0: js	@F			; UNsigned => "wrap" to next 32K page
	mov	ax,056E9H		;056XXH starts out at (dst_page + 1)
dlypt1: add	byte ptr ss:[01234H],8	;01234H becomes addr of 056H above
dlypt2: mov	dx,VGAREG_SQ_ADDR	;flag indicating dst opposed to src
	out	dx,ax			;need to set the high bit of di so the
	or	di,8000H		; splitbank hardware uses it as dst
@@:

DLYPT_SIZE = $ - dst_splitbank_template
DLYPT0 = $ - dlypt0
DLYPT1 = $ - dlypt1
DLYPT2 = $ - dlypt2

PUBLIC	compile_dst_splitbank_yupdate
compile_dst_splitbank_yupdate	PROC	NEAR

	lea	si,dst_splitbank_template
	mov	cx,DLYPT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,dst_swing_bytes
	mov	es:[di - DLYPT0 - 2],ax
        lea     bx,[di - DLYPT1 - 1]
	mov	es:[di - DLYPT2 - 3],bx

	or	ax,ax
	mov	ax,dst_page
	js	@F
	add	ax,8
	mov	es:[bx],al
	ret

@@:	sub	ax,8
	mov	es:[bx],al
	mov	byte ptr es:[di - DLYPT2 - 1],-8
        ret

compile_dst_splitbank_yupdate	ENDP


;
;	compile_color_stosb
;
;	This routine was created for the Multimedia (MM) Windows release.
;	MMWindows supports transparent blts which means that a value that
;	is about to be stored in a dst bitmap (after the ROP has been
;	performed on src,pat and dst) is first compared against the
;	background color. If the value equals the background color, the
;	stosb is skipped; otherwise the value gets stored in the dst bitmap.
;	If the blt is not a transparent blt, then the value is always stored.

color_stosb_xpar_template:
	cmp	al,034H 			;034H will become the bg color
cstxf:	je	@F
	stosb
	dec	di
@@:	inc	di

COLOR_STOSB_XPAR_LEN	=  $ - color_stosb_xpar_template
COLOR_STOSB_XPAR_FIX	=  $ - cstxf + 1


PUBLIC	compile_color_stosb
compile_color_stosb	PROC	NEAR

	cmp	word ptr background_mode,OPAQUE
	jne	@F
	mov	al,I_STOSB
	stosb
	ret

@@:	lea	si,color_stosb_xpar_template
	mov	cx,COLOR_STOSB_XPAR_LEN
	rep	movs byte ptr es:[di], cs:[si]
	mov	al,byte ptr [colors + 1]
	mov	es:[di - COLOR_STOSB_XPAR_FIX],al
	ret

compile_color_stosb	ENDP

sEnd

END

