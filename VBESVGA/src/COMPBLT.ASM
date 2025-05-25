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

externA __NEXTSEG
externFP far_set_bank_select	; in BANK.INC
externB bank_select_byte	; in BANK.INC

.286
sBegin	Code
assumes cs,Code
assumes ds,Nothing
assumes es,Nothing
assumes ss,Nothing

extrn	roptable:byte
extrn	oem_brush_size:word	; in ROBJECT.ASM
extrn	pxbytes:word		; in SWCURS.ASM
extrn	_cstods:word		; in CURSOR.ASM
extrn	??BigFontFlags:byte	; in STRBLT.ASM

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

; commented-out version only works if pxbytes is a power of two
; TODO: Make this a modal function?
;color_pattern_fetch_template:
;	and	bp,01234H             ;1234 becomes negative pattern row size
;cpfta:	or	bp,ss:[01234H]	      ;1234 becomes pattern column counter addr
;cpft:	mov	dh,[bp + 01234H]      ;01234H will become address of pattern
;cpft0:	inc	word ptr ss:[01234H]  ;1234 becomes pattern column counter addr
;cpft1:	and	word ptr ss:[01234H],5678H ;1234 becomes pat col counter addr
;cpft2:				      ; and 5678 will become pattern row size -1
color_pattern_fetch_template:
	push	bp
	add	bp,ss:[01234H]	      ;1234 becomes pattern column counter addr
cpft:	mov	dh,[bp + 01234H]      ;01234H will become address of pattern
cpft0:	inc	word ptr ss:[01234H]  ;1234 becomes pattern column counter addr
cpft1:	jns	cpft2
	mov	word ptr ss:[01234H],5678H ;1234 becomes pat col counter addr
cpft2:				      ; and 5678 will become pattern row size -1
	cmp	word ptr ss:[01234H],5678H ;1234 becomes pat col counter addr
cpft3:				      ; and 5678 will become pattern row size -1
	jbe	cpft4
	mov	word ptr ss:[01234H],5678H ;1234 becomes pat col counter addr
cpft4:				      ; and 5678 will become zero
	pop	bp

CPFT_SIZE = $ - color_pattern_fetch_template
;CPFTA_OFFSET  = $ - cpfta
CPFT_OFFSET  = $ - cpft
CPFT0_OFFSET = $ - cpft0
CPFT1_OFFSET = $ - cpft1
CPFT2_OFFSET = $ - cpft2
CPFT3_OFFSET = $ - cpft3
CPFT4_OFFSET = $ - cpft4

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
	mov	es:[di - CPFT3_OFFSET - 4],bx
	mov	es:[di - CPFT4_OFFSET - 4],bx

	; fixup the pattern size
	mov	dx,[pxbytes]
	errnz	SIZE_PATTERN-8
	shl	dx,3				;multiply by eight to get a row
	dec	dx				;column counter mask
	mov	es:[di - CPFT2_OFFSET - 2],dx
	mov	es:[di - CPFT3_OFFSET - 2],dx
	xor	dx,dx
	mov	es:[di - CPFT4_OFFSET - 2],dx
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

; commented-out version only works if pxbytes is a power of two
; TODO: Make this a modal function?
;pattern_yupdate_template:
;	add	bp,1234H	; 1234h becomes size in bytes of a pattern row
;pyud0:	and	bp,5678H	; 5678h becomes row counter mask (row size * 7)
;pyud1:	mov	word ptr ss:[1234H],5678H    ;zero out pattern column counter
;					     ; for start of next line. 5678H
;					     ; becomes a 0000H. I want to force
;					     ; use of the long form of the
;					     ; instruction so that the code is
;					     ; not assembler dependent.
;
;PYUD_SIZE = $ - pattern_yupdate_template
;PYUD_OFFSET = $ - pattern_yupdate_template
;PYUD_PATSIZE_OFFSET = $ - pyud0 + 2
;PYUD_PATMASK_OFFSET = $ - pyud1 + 2
;I_SUB_BP_I	equ	0ED83H		  ;sub bp,#	   instruction
pattern_yupdate_template:
	add	bp,1234H	; 1234h becomes size in bytes of a pattern row
pyud0:	jnc	pyud1
	and	bp,5678H	; 5678h becomes row counter mask (row size * 7)
pyud1:	cmp	bp,5678H	; 5678h becomes row counter mask (row size * 7)
pyud2:	jbe	@F
	xor	bp,bp
@@:	mov	word ptr ss:[1234H],5678H    ;zero out pattern column counter
					     ; for start of next line. 5678H
					     ; becomes a 0000H. I want to force
					     ; use of the long form of the
					     ; instruction so that the code is
					     ; not assembler dependent.

PYUD_SIZE = $ - pattern_yupdate_template
PYUD_OFFSET = $ - pattern_yupdate_template
PYUD_PATSIZE_OFFSET = $ - pyud0 + 2
PYUD_PATMASK_OFFSET = $ - pyud1 + 2
PYUD_PATMASK_OFFSET2 = $ - pyud2 + 2
I_SUB_BP_I	equ	0ED83H		  ;sub bp,#	   instruction

PUBLIC	compile_pattern_yupdate
compile_pattern_yupdate PROC	NEAR

	lea	si,pattern_yupdate_template
	mov	cx,PYUD_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	lea	bx,pattern_row_counter
	mov	es:[di - 4],bx
	mov	word ptr es:[di - 2],0

	; fixup the pattern size
	mov	ax,[oem_brush_size]
	sub	ax,size oem_brush_com		;just the colour pattern size
	mov	dx,ax
	errnz	SIZE_PATTERN-8
	shr	dx,3				;divide by eight to get one row
	mov	es:[di - PYUD_PATSIZE_OFFSET],dx
	sub	ax,dx				;full size of pattern minus size
	mov	es:[di - PYUD_PATMASK_OFFSET],ax; of one row = correct mask so
	mov	es:[di - PYUD_PATMASK_OFFSET2],ax; that the row counter wraps
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

	test	[device_flags],DEVFLAG_SCAN_X_SEG
	jz	@F
	call	compile_inner_loop_wrapchecks

@@:	ret

compile_inner_loop_start   ENDP



;
;	compile_inner_loop_wrapchecks
;
;	This routine places code on the stack to check if the next scanline
;	will wrap around to the next segment.
;

wrap_check_template:
	;"***" in these comments is either "src" or "dst"
	xor	dx,dx
	mov	ax,1234H	;1234H becomes ***_xExt_bytes
wct0:	mov	word ptr ss:[1234H],dx	;1234H becomes offset of ***_seg_wrap
wct1:	add	ax,si		;01H,0F0H ; change to F8H to make it DI instead
wct1a:	jnc	@F		;decrement to make JC instead of JNC
	;in the unlikely event that we wrap to the next segment, then figure out
	; how many inner loop iterations are needed before and after the wrap
	cwd
	mov	bx,1234H	;1234H becomes (***_xExt_bytes/inner_loop_count)
wct2:	idiv	bx
	inc	ax		;guarantee it is not zero on this codepath
	mov	ss:[1234H],ax	;1234H becomes offset of ***_seg_wrap
wct3:	sub	cx,ax		;CX := iterations left to end of segment
	inc	cx		;restore so we get the correct # of iterations
@@:

WCT_SIZE = $ - wrap_check_template
WCT_XEXT_BYTES_OFFSET = $ - wct0 + 2
WCT_SEGWRAP_PTR_OFFSET1 = $ - wct1 + 2
WCT_ADDINST_OFFSET = $ - wct1
WCT_JNC_OFFSET = $ - wct1a
WCT_RATIO_OFFSET = $ - wct2 + 2
WCT_SEGWRAP_PTR_OFFSET2 = $ - wct3 + 2

PUBLIC	compile_inner_loop_wrapchecks
compile_inner_loop_wrapchecks	PROC	NEAR

	test	[device_flags],DEVFLAG_SRC_SCAN_X_SEG
	jz	wcdst
	test	word ptr [device_flags],DEVFLAG_SRC_SCREEN
	jz	wcdst	; we don't support wrapping memory segments (not needed)

	lea	si,wrap_check_template
	mov	cx,WCT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,src_xExt_bytes
	lea	bx,src_seg_wrap
	mov	cx,inner_loop_count
	cwd
	test	ax,ax
	jns	@F
	dec	byte ptr es:[di - WCT_JNC_OFFSET]	; change JNC to JC
@@:	mov	es:[di - WCT_XEXT_BYTES_OFFSET],ax
	mov	es:[di - WCT_SEGWRAP_PTR_OFFSET1],bx
	mov	es:[di - WCT_SEGWRAP_PTR_OFFSET2],bx
	idiv	cx
	;At this point, DX should be zero - should we check for this?
	mov	es:[di - WCT_RATIO_OFFSET],ax

wcdst:
	test	word ptr [device_flags],DEVFLAG_DST_SCAN_X_SEG
	jz	wcdone
	test	word ptr [device_flags],DEVFLAG_DST_SCREEN
	jz	wcdone	; we don't support wrapping memory segments (not needed)

	lea	si,wrap_check_template
	mov	cx,WCT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,dst_xExt_bytes
	lea	bx,dst_seg_wrap
	mov	cx,inner_loop_count
	cwd
	test	ax,ax
	jns	@F
	dec	byte ptr es:[di - WCT_JNC_OFFSET]	; change JNC to JC
@@:	mov	es:[di - WCT_XEXT_BYTES_OFFSET],ax
	mov	es:[di - WCT_SEGWRAP_PTR_OFFSET1],bx
	mov	es:[di - WCT_SEGWRAP_PTR_OFFSET2],bx
	idiv	cx
	;At this point, DX should be zero - should we check for this?
	mov	es:[di - WCT_RATIO_OFFSET],ax
	;change SI to DI
	db	0B8h		;mov ax,imm16
		add	ax,di	;this instruction becomes an immediate
	mov	es:[di - WCT_ADDINST_OFFSET],ax

wcdone:	ret

compile_inner_loop_wrapchecks	ENDP



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
	test	ah,ah
	jz	@F
	int	3	;we're in trouble here son...
@@:	neg	ax
	stosb
@@:     ret

compile_inner_loop_end	 ENDP



;
;	compile_inner_loop_wraps
;
;	This routine places code on the stack to  if the next scanline
;	will wrap around to the next segment.
;

wrap_screen_template:
	;"***" in these comments is either "src" or "dst"
	xchg	cx,ss:[1234H]	;1234H becomes offset of ***_seg_wrap
wt0:	jcxz	@F
	;we've wrapped, so switch the bank and head back to the beginning of the
	; inner loop for another X amount of iterations...
	mov	dx,ss:[1234H]	;1234H becomes offset of ***_page
wt1:	inc	dx		;42h ; change to 4Ah to make it DEC DX
	mov	ss:[1234H],dx	;1234H becomes offset of ***_page
wt2:	call	far_set_bank_select
	dec	cx		;***_seg_wrap was incremented when it was set
	jnz	wt0		;wt0 becomes start of inner loop
@@:

WST_SIZE = $ - wrap_screen_template
WST_SEGWRAP_PTR_OFFSET = $ - wt0 + 2
WST_PAGE_PTR_OFFSET1 = $ - wt1 + 2
WST_INCDEC_OFFSET = $ - wt1
WST_PAGE_PTR_OFFSET2 = $ - wt2 + 2

;	these are the special cases where inner_loop_count == 1

wrap_screen_special_srcminus:
	cmp	si,-1		;SI == -1 if we've just wrapped back from zero
	jne	@F
	mov	dx,ss:[1234H]	;1234H becomes offset of src_page
wsssm1:	dec	dx
	mov	ss:[1234H],dx	;1234H becomes offset of src_page
wsssm2:	call	far_set_bank_select
@@:

WSSSM_SIZE = $ - wrap_screen_special_srcminus
WSSSM_PAGE_PTR_OFFSET1 = $ - wsssm1 + 2
WSSSM_PAGE_PTR_OFFSET2 = $ - wsssm2 + 2

wrap_screen_special_srcplus:
	test	si,si		;SI == 0 if we've just wrapped up from -1
	jnz	@F
	mov	dx,ss:[1234H]	;1234H becomes offset of src_page
wsssp1:	inc	dx
	mov	ss:[1234H],dx	;1234H becomes offset of src_page
wsssp2:	call	far_set_bank_select
@@:

WSSSP_SIZE = $ - wrap_screen_special_srcplus
WSSSP_PAGE_PTR_OFFSET1 = $ - wsssp1 + 2
WSSSP_PAGE_PTR_OFFSET2 = $ - wsssp2 + 2

wrap_screen_special_dstminus:
	cmp	di,-1		;DI == -1 if we've just wrapped back from zero
	jne	@F
	mov	dx,ss:[1234H]	;1234H becomes offset of dst_page
wssdm1:	dec	dx
	mov	ss:[1234H],dx	;1234H becomes offset of dst_page
wssdm2:	call	far_set_bank_select
@@:

WSSDM_SIZE = $ - wrap_screen_special_dstminus
WSSDM_PAGE_PTR_OFFSET1 = $ - wssdm1 + 2
WSSDM_PAGE_PTR_OFFSET2 = $ - wssdm2 + 2

wrap_screen_special_dstplus:
	test	di,di		;DI == 0 if we've just wrapped up from -1
	jnz	@F
	mov	dx,ss:[1234H]	;1234H becomes offset of dst_page
wssdp1:	inc	dx
	mov	ss:[1234H],dx	;1234H becomes offset of dst_page
wssdp2:	call	far_set_bank_select
@@:

WSSDP_SIZE = $ - wrap_screen_special_dstplus
WSSDP_PAGE_PTR_OFFSET1 = $ - wssdp1 + 2
WSSDP_PAGE_PTR_OFFSET2 = $ - wssdp2 + 2

PUBLIC	compile_inner_loop_wraps
compile_inner_loop_wraps	PROC	NEAR

	; first of all, if inner_loop_count is 1, then the wrap check
	; isn't needed at all, and is skipped in compile_inner_loop_start,
	; so skip it here too!
	cmp	word ptr inner_loop_count,1
	jne	@F
	jmp	wrap_special

@@:	test	[device_flags],DEVFLAG_SRC_SCAN_X_SEG
	jz	dstwrap
	test	word ptr [device_flags],DEVFLAG_SRC_SCREEN
	jz	dstwrap	; we don't support wrapping memory segments (not needed)

	lea	si,wrap_screen_template
	mov	cx,WST_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	lea	ax,src_seg_wrap
	lea	cx,src_page
	or	word ptr src_xExt_bytes,0
	jns	@F
	or	byte ptr es:[di - WST_INCDEC_OFFSET],8	; change to DEC
@@:	mov	es:[di - WST_SEGWRAP_PTR_OFFSET],ax
	mov	es:[di - WST_PAGE_PTR_OFFSET1],cx
	mov	es:[di - WST_PAGE_PTR_OFFSET2],cx
	; fixup the jump back to start
	mov	ax,di
	sub	ax,bx
	test	ah,ah
	jz	@F
	int	3	;we're in trouble here son...
@@:	neg	ax
	mov	es:[di - 1],al

dstwrap:
	test	word ptr [device_flags],DEVFLAG_DST_SCAN_X_SEG
	jz	donewrap
	test	word ptr [device_flags],DEVFLAG_DST_SCREEN
	jz	donewrap; we don't support wrapping memory segments (not needed)

	lea	si,wrap_screen_template
	mov	cx,WST_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	lea	ax,dst_seg_wrap
	lea	cx,dst_page
	or	word ptr dst_xExt_bytes,0
	jns	@F
	or	byte ptr es:[di - WST_INCDEC_OFFSET],8	; change to DEC
@@:	mov	es:[di - WST_SEGWRAP_PTR_OFFSET],ax
	mov	es:[di - WST_PAGE_PTR_OFFSET1],cx
	mov	es:[di - WST_PAGE_PTR_OFFSET2],cx
	; fixup the jump back to start
	mov	ax,di
	sub	ax,bx
	test	ah,ah
	jz	@F
	int	3	;we're in trouble here son...
@@:	neg	ax
	mov	es:[di - 1],al

donewrap:
	ret

wrap_special:
	test	[device_flags],DEVFLAG_SRC_SCAN_X_SEG
	jz	dstwrap_special
	test	word ptr [device_flags],DEVFLAG_SRC_SCREEN
	jz	dstwrap_special	; we don't support wrapping memory segments (not needed)

	lea	si,wrap_screen_special_srcplus
	mov	cx,WSSSP_SIZE

	or	word ptr src_xExt_bytes,0
	jns	@F
	lea	si,wrap_screen_special_srcminus
	mov	cx,WSSSM_SIZE

@@:	rep	movs byte ptr es:[di], cs:[si]
	lea	cx,src_page
; things are much easier when we have the same pointer offsets in the templates
; for Y- and Y+ blits!
.errnz	WSSSP_PAGE_PTR_OFFSET1 - WSSSM_PAGE_PTR_OFFSET1
.errnz	WSSSP_PAGE_PTR_OFFSET2 - WSSSM_PAGE_PTR_OFFSET2
	mov	es:[di - WSSSP_PAGE_PTR_OFFSET1],cx
	mov	es:[di - WSSSP_PAGE_PTR_OFFSET2],cx

dstwrap_special:
	test	word ptr [device_flags],DEVFLAG_DST_SCAN_X_SEG
	jz	donewrap
	test	word ptr [device_flags],DEVFLAG_DST_SCREEN
	jz	donewrap; we don't support wrapping memory segments (not needed)

	lea	si,wrap_screen_special_dstplus
	mov	cx,WSSDP_SIZE

	or	word ptr dst_xExt_bytes,0
	jns	@F
	lea	si,wrap_screen_special_dstminus
	mov	cx,WSSDM_SIZE

@@:	rep	movs byte ptr es:[di], cs:[si]
	lea	cx,dst_page
; things are much easier when we have the same pointer offsets in the templates
; for Y- and Y+ blits!
.errnz	WSSDP_PAGE_PTR_OFFSET1 - WSSDM_PAGE_PTR_OFFSET1
.errnz	WSSDP_PAGE_PTR_OFFSET2 - WSSDM_PAGE_PTR_OFFSET2
	mov	es:[di - WSSDP_PAGE_PTR_OFFSET1],cx
	mov	es:[di - WSSDP_PAGE_PTR_OFFSET2],cx

	ret

compile_inner_loop_wraps	ENDP



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
ssypt3: call	far_set_bank_select	;page
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
ssymt3: call	far_set_bank_select	;page
@@:

SSYMT_SIZE = $ - src_screen_yminus_template
SSYMT0 = $ - ssymt0
SSYMT1 = $ - ssymt1
SSYMT2 = $ - ssymt2
SSYMT3 = $ - ssymt3

; "paranoid" version is aware of segment wrapping and may take a bit longer
src_screen_paranoid_template:
	add	si,01234H		;01234H becomes src_swing_bytes
sspt0:  jnc	@F			;no carry means we don't wrap
	mov	dx,ss:[1234H]		;1234H becomes offset of src_page
sspt1:	inc	dx			;42h ; change to 4Ah to make it DEC DX
	mov	ss:[1234H],dx		;1234H becomes offset of src_page
sspt2:  call	far_set_bank_select
@@:

SSPT_SIZE = $ - src_screen_paranoid_template
SSPT0 = $ - sspt0
SSPT1 = $ - sspt1
SSPT2 = $ - sspt2

PUBLIC	compile_src_screen_yupdate
compile_src_screen_yupdate   PROC    NEAR

	test	[device_flags],DEVFLAG_SRC_SCAN_X_SEG
	jz	@F
	test	word ptr [device_flags],DEVFLAG_SRC_SCREEN
	jz	@F	; we don't support wrapping memory segments (not needed)
	jmp	compile_paranoid_src_yupdate

@@:	or	word ptr src_swing_bytes,0
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

compile_paranoid_src_yupdate:
	lea	si,src_screen_paranoid_template
	mov	cx,SSPT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,src_swing_bytes
	lea	bx,src_page
	mov	es:[di - SSPT0 - 2],ax
	mov	es:[di - SSPT1 - 2],bx
	mov	es:[di - SSPT2 - 2],bx
	test	ax,ax
	jns	@F
	dec	byte ptr es:[di - SSPT0]	; change JNC to JC
	or	byte ptr es:[di - SSPT1],8	; change to DEC
@@:	ret

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
sypt3:	call	far_set_bank_select
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
symt3:	call	far_set_bank_select
@@:

SYMT_SIZE = $ - screen_yminus_template
SYMT0 = $ - symt0
SYMT1 = $ - symt1
SYMT2 = $ - symt2
SYMT3 = $ - symt3

; "paranoid" version is aware of segment wrapping and may take a bit longer
screen_paranoid_template:
	add	di,01234H		;01234H becomes dst_swing_bytes
spt0:   jnc	@F			;no carry means we don't wrap
        mov	dx,ss:[1234H]		;1234H becomes offset of dst_page
spt1:   inc	dx			;42h ; change to 4Ah to make it DEC DX
        mov	ss:[1234H],dx		;1234H becomes offset of dst_page
spt2:   call	far_set_bank_select
@@:

SPT_SIZE = $ - screen_paranoid_template
SPT0 = $ - spt0
SPT1 = $ - spt1
SPT2 = $ - spt2

PUBLIC	compile_screen_yupdate
compile_screen_yupdate	 PROC	 NEAR

	test	word ptr [device_flags],DEVFLAG_DST_SCAN_X_SEG
	jz	@F
	test	word ptr [device_flags],DEVFLAG_DST_SCREEN
	jz	@F	; we don't support wrapping memory segments (not needed)
	jmp	compile_paranoid_dst_yupdate

@@:     or      word ptr dst_swing_bytes,0
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

compile_paranoid_dst_yupdate:
	lea	si,screen_paranoid_template
	mov	cx,SPT_SIZE
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,dst_swing_bytes
	lea	bx,dst_page
	mov	es:[di - SPT0 - 2],ax
	mov	es:[di - SPT1 - 2],bx
	mov	es:[di - SPT2 - 2],bx
	test	ax,ax
	jns	@F
	dec	byte ptr es:[di - SPT0]		; change JNC to JC
	or	byte ptr es:[di - SPT1],8	; change to DEC
@@:	ret

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


; extra logic needed for 24-bit colour stosb at bank boundaries,
; broken out into a separate far function to avoid cluttering the stack!
; Entry: DI == 0 or 1, AX = two bytes to store at ES:"DI - 2"
store_in_prev_bank	PROC	FAR
	test	di,1
	jz	@F
	; if DI == 1, then AH goes in current bank!
	mov	es:[0],ah

@@:	; go back to previous bank
	push	ds
	mov	ds,[_cstods]
	assumes	ds,Data
	xor	dh,dh
	mov	dl,[bank_select_byte]
	pop	ds
	assumes	ds,nothing
	dec	dl
	call	far_set_bank_select

	test	di,1
	jz	@F
	; if DI == 1, then only AL goes in previous bank!
	mov	es:[-1],al
	jmp	@@done
@@:	; if DI == 0, then all of AX goes in previous bank
	mov	es:[-2],ax

@@done:	; restore the current bank
	inc	dl
	call	far_set_bank_select
	ret
store_in_prev_bank	ENDP

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

color_stosb_xpar_template_16:
	test	di,1
	jz	csx16e				;even byte, go stash it
	mov	ah,al
	mov	al,034H				;this gets updated every second byte
csx16l:	cmp	ax,01234H 			;01234H will become the bg color
csx16f:	je	csx16pl
	mov	es:[di-1],ax
	jmp	short csx16pl
csx16e:	mov	ss:[05678H],al			;05678H will become csx16l-1
csx16pl:inc	di

COLOR_STOSB_XPAR16_LEN	=  $ - color_stosb_xpar_template_16
COLOR_STOSB_XPAR16_LB	=  $ - csx16l + 1
COLOR_STOSB_XPAR16_FIX	=  $ - csx16f + 2
COLOR_STOSB_XPAR16_PTRLB=  $ - csx16pl + 2

color_stosb_xpar_template_24:
	mov	bx,01234H			;this becomes the phase (0/1/2)
csx24p:	cmp	bl,2
	jb	csx24e				;byte 0 or 1, go stash it
	xor	dl,dl				;reset the phase
	mov	byte ptr ss:[05678H],dl		;05678H will become csx24p-2
csx24p1:mov	dl,al
	mov	ax,01234H			;this gets updated to bytes 0 and 1
csx24l:	cmp	ax,01234H 			;01234H will become lower word of bg colour
csx24f:	jne	@F
	cmp	dl,056H				;056H will become upper byte of bg colour
csx24f2:je	csx24p2
@@:	mov	es:[di],dl
	cmp	di,2
	jb	@F
	mov	es:[di-2],ax
	jmp	short csx24p2
@@:	call	store_in_prev_bank		;call separate far function
	jmp	short csx24p2
csx24e:	mov	ss:[bx+05678H],al		;05678H will become csx24l-2
csx24pl:inc	byte ptr ss:[05678H]		;05678H will become csx24p-2
csx24p2:inc	di

COLOR_STOSB_XPAR24_LEN	=  $ - color_stosb_xpar_template_24
COLOR_STOSB_XPAR24_PHASE=  $ - csx24p + 2
COLOR_STOSB_XPAR24_PPHS1=  $ - csx24p1 + 2
COLOR_STOSB_XPAR24_PPHS2=  $ - csx24p2 + 2
COLOR_STOSB_XPAR24_LW	=  $ - csx24l + 2
COLOR_STOSB_XPAR24_FIX	=  $ - csx24f + 2
COLOR_STOSB_XPAR24_FIX2	=  $ - csx24f2 + 1
COLOR_STOSB_XPAR24_PTRLW=  $ - csx24pl + 2

color_stosb_xpar_template_32:
	mov	bx,di
	and	bx,11b				;get the phase
	test	bl,2
	jz	csx32e				;byte 0 or 1, go stash it
	test	bl,1
	jz	csx32t				;byte 2, go stash it
	mov	dh,al
	mov	ax,01234H			;this gets updated to bytes 0 and 1
csx32l:	mov	dl,056H				;this gets updated to byte 2
csx32u:	cmp	ax,01234H 			;01234H will become lower word of bg colour
csx32f:	jne	@F
	cmp	dx,05678H			;05678H will become upper word of bg colour
csx32f2:je	csx32pl
@@:	mov	es:[di-3],ax
	mov	es:[di-1],dx
	jmp	short csx32pl
csx32t:	mov	ss:[05678H],al			;05678H will become csx32u-1
csx32pu:jmp	short csx32pl
csx32e:	mov	ss:[bx+05678H],al		;05678H will become csx32l-2
csx32pl:inc	di

COLOR_STOSB_XPAR32_LEN	=  $ - color_stosb_xpar_template_32
COLOR_STOSB_XPAR32_LW	=  $ - csx32l + 2
COLOR_STOSB_XPAR32_UB	=  $ - csx32u + 1
COLOR_STOSB_XPAR32_FIX	=  $ - csx32f + 2
COLOR_STOSB_XPAR32_FIX2	=  $ - csx32f2 + 2
COLOR_STOSB_XPAR32_PTRLW=  $ - csx32pl + 2
COLOR_STOSB_XPAR32_PTRUB=  $ - csx32pu + 2

color_stosb_xpar_template_32_386:
	.386
	mov	bx,di
	and	bx,11b				;get the phase
	cmp	bl,3
	jb	csx33e				;byte 0/1/2, go stash it
	shl	eax,18h				;get current byte into upper byte of EAX
	or	eax,0123456H			;this gets updated to bytes 0/1/2
csx33l:	cmp	eax,012345678H 			;012345678H will become bg colour
csx33f:	je	csx33pl
@@:	mov	es:[di-3],eax
	jmp	short csx33pl
csx33e:	mov	ss:[bx+05678H],al		;05678H will become csx33l-4
csx33pl:inc	di
	.286

COLOR_STOSB_XPAR33_LEN	=  $ - color_stosb_xpar_template_32_386
COLOR_STOSB_XPAR33_L3B	=  $ - csx33l + 4
COLOR_STOSB_XPAR33_FIX	=  $ - csx33f + 4
COLOR_STOSB_XPAR33_PTRL3=  $ - csx33pl + 2

PUBLIC	compile_color_stosb
compile_color_stosb	PROC	NEAR

	cmp	word ptr background_mode,OPAQUE
	jne	@F
	; opaque: we just store the byte at ES:DI, and done
	mov	al,I_STOSB
	stosb
	ret

@@:	cmp	[pxbytes],1
	ja	@F
	; transparent, 1 byte per pixel
	lea	si,color_stosb_xpar_template
	mov	cx,COLOR_STOSB_XPAR_LEN
	rep	movs byte ptr es:[di], cs:[si]
	mov	al,byte ptr [bgcolour]
	mov	es:[di - COLOR_STOSB_XPAR_FIX],al
	ret

@@:	cmp	[pxbytes],2
	ja	@F
	; transparent, 2 bytes per pixel - need to accumulate
	; them and then check the entire pixel at once
	lea	si,color_stosb_xpar_template_16
	mov	cx,COLOR_STOSB_XPAR16_LEN
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,word ptr [bgcolour]
	mov	es:[di - COLOR_STOSB_XPAR16_FIX],ax
	lea	ax,[di - COLOR_STOSB_XPAR16_LB]
	mov	es:[di - COLOR_STOSB_XPAR16_PTRLB],ax
	ret

@@:	cmp	[pxbytes],3
	ja	@F
	; transparent, 3 bytes per pixel - need to accumulate
	; them and then check the entire pixel at once
	lea	si,color_stosb_xpar_template_24
	mov	cx,COLOR_STOSB_XPAR24_LEN
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,word ptr bgcolour[0]
	mov	dl,byte ptr bgcolour[2]
	mov	es:[di - COLOR_STOSB_XPAR24_FIX],ax
	mov	es:[di - COLOR_STOSB_XPAR24_FIX2],dl
	lea	ax,[di - COLOR_STOSB_XPAR24_LW]
	mov	es:[di - COLOR_STOSB_XPAR24_PTRLW],ax
	lea	bx,[di - COLOR_STOSB_XPAR24_PHASE]
	xor	ax,ax	; initialize phase to zero
	mov	es:[bx],ax
	mov	es:[di - COLOR_STOSB_XPAR24_PPHS1],bx
	mov	es:[di - COLOR_STOSB_XPAR24_PPHS2],bx
	ret

@@:	cmp	[??BigFontFlags],0
	jnz	@F
	; transparent, 4 bytes per pixel, 286 - need to
	; accumulate them and then check the entire pixel
	; at once (in 2-byte chunks)
	lea	si,color_stosb_xpar_template_32
	mov	cx,COLOR_STOSB_XPAR32_LEN
	rep	movs byte ptr es:[di], cs:[si]
	mov	ax,word ptr bgcolour[0]
	mov	dx,word ptr bgcolour[2]
	mov	es:[di - COLOR_STOSB_XPAR32_FIX],ax
	mov	es:[di - COLOR_STOSB_XPAR32_FIX2],dx
	lea	ax,[di - COLOR_STOSB_XPAR32_LW]
	mov	es:[di - COLOR_STOSB_XPAR32_PTRLW],ax
	lea	ax,[di - COLOR_STOSB_XPAR32_UB]
	mov	es:[di - COLOR_STOSB_XPAR32_PTRUB],ax
	ret

@@:	; transparent, 4 bytes per pixel, 386 - need to
	; accumulate them and then check the entire pixel
	; at once (as a single 4-byte unit)
	lea	si,color_stosb_xpar_template_32_386
	mov	cx,COLOR_STOSB_XPAR33_LEN
	rep	movs byte ptr es:[di], cs:[si]
	.386
	mov	eax,dword ptr bgcolour
	mov	es:[di - COLOR_STOSB_XPAR33_FIX],eax
	.286
	lea	ax,[di - COLOR_STOSB_XPAR33_L3B]
	mov	es:[di - COLOR_STOSB_XPAR33_PTRL3],ax
	ret

compile_color_stosb	ENDP

sEnd

END

