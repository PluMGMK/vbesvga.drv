;	FILE:	bltspec.asm
;	DATE:	2025-08-17
;	AUTHOR: PluMGMK
;
;	This module contains routines for blitting directly to/from
;	a linear framebuffer.
;

SRCFILE_BLTSPEC	equ	1
incLogical	=	1
incDrawMode	=	1

include cmacros.inc
include gdidefs.inc
include macros.mac
include display.inc
include bblt.inc
include bltspec.inc
include bltutil.inc
include bitblt.var

.286
sBegin	Code
assumes cs,Code
assumes ds,Nothing
assumes es,Nothing
assumes ss,Nothing

externW	pattern_copy_numwords	; in ROBJECT.ASM
externNP blt_ctoc_prep		; in BLT88.ASM

;
;	blt_spec_patcopy
;
;	copy pattern on stack directly to linear framebuffer at ES:SI:DI
;

PUBLIC	blt_spec_patcopy
blt_spec_patcopy	PROC	NEAR

	; setup the 32-bit offset within the framebuffer
	call	blt_ctoc_prep
	add	di,[dst_blt_offset]
	adc	si,[dst_page]

	; if all the conditions were met to call this function, we know
	; that ES is a 32-bit flat selector, and hence that we are on a
	; 386 or newer
	.386
	push	edi
	push	esi
	push	ecx

	; get full 32-bit offset into one register
	ror	edi,10h
	mov	di,si
	ror	edi,10h

	movzx	esi,word ptr [pattern_offset]
	mov	bx,[pattern_copy_numwords]
	shl	bx,1	; convert words to bytes

	; figure out how many pattern widths fit into the dest rectangle
	mov	ax,[dst_xExt_bytes]
	xor	dx,dx
	div	bx

	; now AX = full pattern widths, DX = leftover bytes
@@copy_pat_dwords:
	test	ax,ax
	jz	@@leftover_bytes
	mov	cx,ax
@@:	push	ecx
	movzx	ecx,bx
	shr	ecx,2	; convert bytes to dwords
	rep	movs dword ptr es:[edi],dword ptr ss:[esi]
	db	67h,90h	; 386 bug
	pop	ecx
	; back to start of pattern row
	sub	si,bx
	loop	@B

@@leftover_bytes:
	test	dx,dx
	jz	@F
	movzx	ecx,dx
	rep	movs byte ptr es:[edi],byte ptr ss:[esi]
	db	67h,90h	; 386 bug
	; back to start of pattern row
	sub	si,dx

@@:	; next row...
	dec	word ptr [yExt]
	jz	@@no_more_rows
	; next pattern row:
	add	si,bx
	; next dest row:
	movzx	ecx,word ptr [dst_swing_bytes]
	add	edi,ecx
	; check if we need to wrap around the pattern
	mov	cx,[pattern_row_counter]
	inc	cx
	cmp	cx,SIZE_PATTERN
	jb	@F
	; back to row zero and beginning of pattern
	xor	cx,cx
	movzx	esi,word ptr [pattern_offset]
@@:	mov	[pattern_row_counter],cx
	jmp	short @@copy_pat_dwords

@@no_more_rows:
	pop	ecx
	pop	esi
	pop	edi
	.286
	ret

blt_spec_patcopy	ENDP		;



sEnd    CODE

END
