;
;	FILE:	blt88.asm
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module contains routines that deal with mono to color blts.
;

SRCFILE_BLT88	equ	1
incLogical	=	1
incDrawMode	=	1

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
;	blt88
;
;	This handles only color to color blts from:
;	memory to memory, memory to screen, screen to memory.
;	It does NOT handle screen to screen blts. Thus there is no worry
;	about changing src and dst pages in between reads and writes.
;

PUBLIC	blt88
blt88	PROC	NEAR

        call    blt_ctoc_prep

	call	compile_inner_loop_start
	push	di
	test	rop_flags,SOURCE_PRESENT
	je	@F
	or	word ptr device_flags,DEVFLAG_MOVSB or DEVFLAG_REP
	mov	al,I_LODSB
	stosb
	test	word ptr device_flags,DEVFLAG_XLAT_REQUIRED
	je	@F
	and	word ptr device_flags,NOT DEVFLAG_MOVSB
	mov	ax,I_XLAT_SS_BX
        stosw

@@:	test	word ptr rop_flags,PATTERN_PRESENT
	je	@F
	and	word ptr device_flags,NOT DEVFLAG_MOVSB
	call	compile_color_pattern_fetch
@@:	call	compile_rop
	call	compile_color_stosb
	pop	bx
	call	compile_inner_loop_end

	cmp	word ptr background_mode,OPAQUE ;xpar bg mode means no movsb
	jne	blt88_nomovsb
	test	word ptr device_flags,DEVFLAG_MOVSB
	je	blt88_nomovsb
	sub	di,2
	test	word ptr device_flags,DEVFLAG_REP
	je	@F

public  blt88_repmovsb
blt88_repmovsb: 				;just for debugging
	sub	di,2
	mov	al,I_REP
	stosb
@@:	mov	al,I_MOVSB
	stosb

blt88_nomovsb:
	call	compile_outer_loop

	test	word ptr rop_flags,SOURCE_PRESENT
	je	short	blt88_src_updated
	test	word ptr device_flags,DEVFLAG_SRC_SCREEN
	je	@F
	call	compile_src_screen_yupdate
	jmp	short	blt88_src_updated
@@:	call	compile_src_memory_yupdate

blt88_src_updated:
	test	word ptr device_flags,DEVFLAG_DST_SCREEN
	je	@F				;if screen is dst then set both
	call	compile_screen_yupdate		; src and dst pages & banks to
	jmp	short	blt88_dst_updated	; the dst bank since we may
@@:	call	compile_dst_memory_yupdate	; need to read from the dst!

blt88_dst_updated:
	test	word ptr rop_flags,PATTERN_PRESENT
	je	@F
	call	compile_pattern_yupdate

@@:	call	compile_jmp_back_to_start
	ret

blt88	ENDP					;

;
;	blt_ctoc_prep
;
;

PUBLIC	blt_ctoc_prep
blt_ctoc_prep	PROC	NEAR

	test	word ptr device_flags,DEVFLAG_SRC_SCREEN
	je	@F
	mov	ax,SrcyOrg
	mov	bx,SrcxOrg
	mul	word ptr src_width_bytes
	add	ax,bx				;FIXME: bitness, possible overflow
	mov	src_blt_offset,ax
	mov	src_page,dx
	clc
	call	set_page

@@:	test	word ptr device_flags,DEVFLAG_DST_SCREEN
	je	@F
	mov	ax,DestyOrg
	mov	bx,DestxOrg
	mul	word ptr dst_width_bytes
	add	ax,bx				;FIXME: bitness, possible overflow
	mov	dst_blt_offset,ax
	mov	dst_page,dx			;if dst is the screen, may need
	call	set_both_pages			; to read AND write to it, so
@@:	ret					; set both pages, not just dst

blt_ctoc_prep	ENDP			;

sEnd	CODE

END


