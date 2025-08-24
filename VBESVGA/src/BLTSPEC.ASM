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
externNP bltstos_prep		; in BLTSTOS.ASM

;
;	blt_spec_pattern
;
;	load pattern on stack and ROP it directly to linear framebuffer at ES:SI:DI
;

PUBLIC	blt_spec_pattern
blt_spec_pattern	PROC	NEAR

	; convert ternary to binary ROP (since it's just pat/dest)
	mov	ax,Rop[2]
	and	al,00111100b	; get the middle nibble
	shr	al,2		; make it the lower nibble
	; for ROPA (nop), we're already done!
	cmp	al,0Ah
	jne	@F
	ret

@@:	; reuse the "Rop" slot on the stack to store our Rop procedures
	mov	bx,ax
	shl	bx,1
	mov	ax,cs:repdword_table[bx]
	mov	Rop[0],ax
	mov	ax,cs:repbyte_table[bx]
	mov	Rop[2],ax

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
	push	eax

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
@@load_pat_dwords:
	test	ax,ax
	push	ax
	jz	@@leftover_bytes
	mov	cx,ax
@@:	shl	ecx,10h	; use two halves of ECX for outer/inner counters
	mov	cx,bx
	shr	cx,2	; convert bytes to dwords
	call	word ptr Rop[0]
	shr	ecx,10h
	; back to start of pattern row
	sub	si,bx
	loop	@B

@@leftover_bytes:
	test	dx,dx
	jz	@F
	movzx	ecx,dx
	call	word ptr Rop[2]
	; back to start of pattern row
	sub	si,dx

@@:	; next row...
	dec	word ptr [yExt]
	pop	ax
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
	jmp	short @@load_pat_dwords

@@no_more_rows:
	pop	eax
	pop	ecx
	pop	esi
	pop	edi
	.286
	ret

blt_spec_pattern	ENDP		;

;
;	blt_spec_stoscopy
;
;	copy directly from one location in linear framebuffer at ES:SI:DI
;	to another location in the same framebuffer - no patterns or ROPs
;

PUBLIC	blt_spec_stoscopy
blt_spec_stoscopy	PROC	NEAR

	; setup the 32-bit offsets within the framebuffer
	call	bltstos_prep
	mov	ax,[src_blt_offset]
	mov	dx,[src_page]
	add	ax,di
	adc	dx,si
	mov	cx,[dst_blt_offset]
	mov	bx,[dst_page]
	add	cx,di
	adc	bx,si

	; if all the conditions were met to call this function, we know
	; that ES is a 32-bit flat selector, and hence that we are on a
	; 386 or newer
	.386
	push	edi
	push	esi
	push	ecx
	push	eax

	; get full 32-bit offsets into one register each
	mov	si,ax
	ror	esi,10h
	mov	si,dx
	ror	esi,10h
	mov	di,cx
	ror	edi,10h
	mov	di,bx
	ror	edi,10h

	; get the X and Y extents into registers so we minimize stack use...
	mov	bx,[src_xExt_bytes]	; should be same as dst_xExt_bytes
	test	bx,bx
	jns	@F
	std				; this is an X- blit!
	neg	bx
@@:	mov	dx,[yExt]

	; stick the swing byte counts in the two halves of EAX
	; FIXME: aren't they always the same??
	mov	ax,[src_swing_bytes]
	shl	eax,10h
	mov	ax,[dst_swing_bytes]

	; and off we go!
@@:	movzx	ecx,bx			; xExt bytes
	rep	movs byte ptr es:[edi],byte ptr es:[esi]
	ror	eax,10h
	movsx	ecx,ax			; src swing bytes
	add	esi,ecx
	ror	eax,10h
	movsx	ecx,ax			; dst swing bytes
	add	edi,ecx
	dec	dx			; yExt
	jnz	@B

	pop	eax
	pop	ecx
	pop	esi
	pop	edi
	.286
	ret

blt_spec_stoscopy	ENDP		;

	.386
;---------------------------------------------------------------------------;
; 386 ROP routines to operate on CX DWORDs (source SS:ESI, dest ES:EDI)
;---------------------------------------------------------------------------;
repdword_ROP0	proc	near
	; rep uses ECX so we need to stash its upper half
	; we can use ESI because the source pointer isn't used for ROP0
	mov	esi,ecx
	movzx	ecx,cx
	xor	eax,eax
	rep	stos DWORD PTR es:[edi]
	db	67h,90h	; 386 bug
	mov	ecx,esi
	ret
repdword_ROP0	endp
;---------------------------------------------------------------------------;
repdword_ROP1	proc	near
	lods	DWORD PTR ss:[esi]
	db	67h,90h	; 386 bug
	or	DWORD PTR es:[edi],eax
	not	DWORD PTR es:[edi]
	lea	edi,[edi+4]
	loop	repdword_ROP1	; loop uses CX, not ECX, so we're OK
	ret
repdword_ROP1	endp
;---------------------------------------------------------------------------;
repdword_ROP2	proc	near
	lods	DWORD PTR ss:[esi]
	db	67h,90h	; 386 bug
	not	eax
	and	DWORD PTR es:[edi],eax
	lea	edi,[edi+4]
	loop	repdword_ROP2	; loop uses CX, not ECX, so we're OK
	ret
repdword_ROP2	endp
;---------------------------------------------------------------------------;
repdword_ROP3	proc	near
	lods	DWORD PTR ss:[esi]
	db	67h,90h	; 386 bug
	not	eax
	stos	DWORD PTR es:[edi]
	db	67h,90h	; 386 bug
	loop	repdword_ROP3	; loop uses CX, not ECX, so we're OK
	ret
repdword_ROP3	endp
;---------------------------------------------------------------------------;
repdword_ROP4	proc	near
	lods	DWORD PTR ss:[esi]
	db	67h,90h	; 386 bug
	not	DWORD PTR es:[edi]
	and	DWORD PTR es:[edi],eax
	lea	edi,[edi+4]
	loop	repdword_ROP4	; loop uses CX, not ECX, so we're OK
	ret
repdword_ROP4	endp
;---------------------------------------------------------------------------;
repdword_ROP5	proc	near
	not	DWORD PTR es:[edi]
	lea	edi,[edi+4]
	loop	repdword_ROP5	; loop uses CX, not ECX, so we're OK
	ret
repdword_ROP5	endp
;---------------------------------------------------------------------------;
repdword_ROP6	proc	near
	lods	DWORD PTR ss:[esi]
	db	67h,90h	; 386 bug
	xor	DWORD PTR es:[edi],eax
	lea	edi,[edi+4]
	loop	repdword_ROP6	; loop uses CX, not ECX, so we're OK
	ret
repdword_ROP6	endp
;---------------------------------------------------------------------------;
repdword_ROP7	proc	near
	lods	DWORD PTR ss:[esi]
	db	67h,90h	; 386 bug
	and	DWORD PTR es:[edi],eax
	not	DWORD PTR es:[edi]
	lea	edi,[edi+4]
	loop	repdword_ROP7	; loop uses CX, not ECX, so we're OK
	ret
repdword_ROP7	endp
;---------------------------------------------------------------------------;
repdword_ROP8	proc	near
	lods	DWORD PTR ss:[esi]
	db	67h,90h	; 386 bug
	and	DWORD PTR es:[edi],eax
	lea	edi,[edi+4]
	loop	repdword_ROP8	; loop uses CX, not ECX, so we're OK
	ret
repdword_ROP8	endp
;---------------------------------------------------------------------------;
repdword_ROP9	proc	near
	lods	DWORD PTR ss:[esi]
	db	67h,90h	; 386 bug
	xor	DWORD PTR es:[edi],eax
	not	DWORD PTR es:[edi]
	lea	edi,[edi+4]
	loop	repdword_ROP9	; loop uses CX, not ECX, so we're OK
	ret
repdword_ROP9	endp
;---------------------------------------------------------------------------;
repdword_ROPA	proc	near
	; we can use ESI because the source pointer isn't used for ROPA
	movzx	esi,cx
	lea	edi,[edi+esi*4]	; advance dest pointer, nothing else
	ret
repdword_ROPA	endp
;---------------------------------------------------------------------------;
repdword_ROPB	proc	near
	lods	DWORD PTR ss:[esi]
	db	67h,90h	; 386 bug
	not	eax
	or	DWORD PTR es:[edi],eax
	lea	edi,[edi+4]
	loop	repdword_ROPB	; loop uses CX, not ECX, so we're OK
	ret
repdword_ROPB	endp
;---------------------------------------------------------------------------;
repdword_ROPC	proc	near
	; rep uses ECX so we need to stash its upper half
	mov	eax,ecx
	movzx	ecx,cx
	rep	movs DWORD PTR es:[edi],DWORD PTR ss:[esi]
	db	67h,90h	; 386 bug
	mov	ecx,eax
	ret
repdword_ROPC	endp
;---------------------------------------------------------------------------;
repdword_ROPD	proc	near
	lods	DWORD PTR ss:[esi]
	db	67h,90h	; 386 bug
	not	DWORD PTR es:[edi]
	or	DWORD PTR es:[edi],eax
	lea	edi,[edi+4]
	loop	repdword_ROPD	; loop uses CX, not ECX, so we're OK
	ret
repdword_ROPD	endp
;---------------------------------------------------------------------------;
repdword_ROPE	proc	near
	lods	DWORD PTR ss:[esi]
	db	67h,90h	; 386 bug
	or	DWORD PTR es:[edi],eax
	lea	edi,[edi+4]
	loop	repdword_ROPE	; loop uses CX, not ECX, so we're OK
	ret
repdword_ROPE	endp
;---------------------------------------------------------------------------;
repdword_ROPF	proc	near
	; rep uses ECX so we need to stash its upper half
	; we can use ESI because the source pointer isn't used for ROPF
	mov	esi,ecx
	movzx	ecx,cx
	xor	eax,eax
	dec	eax
	rep	stos DWORD PTR es:[edi]
	db	67h,90h	; 386 bug
	mov	ecx,esi
	ret
repdword_ROPF	endp

;---------------------------------------------------------------------------;
; 386 ROP routines to operate on CX BYTEs (source SS:ESI, dest ES:EDI)
;---------------------------------------------------------------------------;
repbyte_ROP0	proc	near
	; rep uses ECX so we need to stash its upper half
	; we can use ESI because the source pointer isn't used for ROP0
	mov	esi,ecx
	movzx	ecx,cx
	xor	al,al
	rep	stos BYTE PTR es:[edi]
	db	67h,90h	; 386 bug
	mov	ecx,esi
	ret
repbyte_ROP0	endp
;---------------------------------------------------------------------------;
repbyte_ROP1	proc	near
	lods	BYTE PTR ss:[esi]
	db	67h,90h	; 386 bug
	or	BYTE PTR es:[edi],al
	not	BYTE PTR es:[edi]
	inc	edi
	loop	repbyte_ROP1	; loop uses CX, not ECX, so we're OK
	ret
repbyte_ROP1	endp
;---------------------------------------------------------------------------;
repbyte_ROP2	proc	near
	lods	BYTE PTR ss:[esi]
	db	67h,90h	; 386 bug
	not	al
	and	BYTE PTR es:[edi],al
	inc	edi
	loop	repbyte_ROP2	; loop uses CX, not ECX, so we're OK
	ret
repbyte_ROP2	endp
;---------------------------------------------------------------------------;
repbyte_ROP3	proc	near
	lods	BYTE PTR ss:[esi]
	db	67h,90h	; 386 bug
	not	al
	stos	BYTE PTR es:[edi]
	db	67h,90h	; 386 bug
	loop	repbyte_ROP3	; loop uses CX, not ECX, so we're OK
	ret
repbyte_ROP3	endp
;---------------------------------------------------------------------------;
repbyte_ROP4	proc	near
	lods	BYTE PTR ss:[esi]
	db	67h,90h	; 386 bug
	not	BYTE PTR es:[edi]
	and	BYTE PTR es:[edi],al
	inc	edi
	loop	repbyte_ROP4	; loop uses CX, not ECX, so we're OK
	ret
repbyte_ROP4	endp
;---------------------------------------------------------------------------;
repbyte_ROP5	proc	near
	not	BYTE PTR es:[edi]
	inc	edi
	loop	repbyte_ROP5	; loop uses CX, not ECX, so we're OK
	ret
repbyte_ROP5	endp
;---------------------------------------------------------------------------;
repbyte_ROP6	proc	near
	lods	BYTE PTR ss:[esi]
	db	67h,90h	; 386 bug
	xor	BYTE PTR es:[edi],al
	inc	edi
	loop	repbyte_ROP6	; loop uses CX, not ECX, so we're OK
	ret
repbyte_ROP6	endp
;---------------------------------------------------------------------------;
repbyte_ROP7	proc	near
	lods	BYTE PTR ss:[esi]
	db	67h,90h	; 386 bug
	and	BYTE PTR es:[edi],al
	not	BYTE PTR es:[edi]
	inc	edi
	loop	repbyte_ROP7	; loop uses CX, not ECX, so we're OK
	ret
repbyte_ROP7	endp
;---------------------------------------------------------------------------;
repbyte_ROP8	proc	near
	lods	BYTE PTR ss:[esi]
	db	67h,90h	; 386 bug
	and	BYTE PTR es:[edi],al
	inc	edi
	loop	repbyte_ROP8	; loop uses CX, not ECX, so we're OK
	ret
repbyte_ROP8	endp
;---------------------------------------------------------------------------;
repbyte_ROP9	proc	near
	lods	BYTE PTR ss:[esi]
	db	67h,90h	; 386 bug
	xor	BYTE PTR es:[edi],al
	not	BYTE PTR es:[edi]
	inc	edi
	loop	repbyte_ROP9	; loop uses CX, not ECX, so we're OK
	ret
repbyte_ROP9	endp
;---------------------------------------------------------------------------;
repbyte_ROPA	proc	near
	; we can use ESI because the source pointer isn't used for ROPA
	movzx	esi,cx
	lea	edi,[edi+esi]	; advance dest pointer, nothing else
	ret
repbyte_ROPA	endp
;---------------------------------------------------------------------------;
repbyte_ROPB	proc	near
	lods	BYTE PTR ss:[esi]
	db	67h,90h	; 386 bug
	not	al
	or	BYTE PTR es:[edi],al
	inc	edi
	loop	repbyte_ROPB	; loop uses CX, not ECX, so we're OK
	ret
repbyte_ROPB	endp
;---------------------------------------------------------------------------;
repbyte_ROPC	proc	near
	; rep uses ECX so we need to stash its upper half
	mov	eax,ecx
	movzx	ecx,cx
	rep	movs BYTE PTR es:[edi],BYTE PTR ss:[esi]
	db	67h,90h	; 386 bug
	mov	ecx,eax
	ret
repbyte_ROPC	endp
;---------------------------------------------------------------------------;
repbyte_ROPD	proc	near
	lods	BYTE PTR ss:[esi]
	db	67h,90h	; 386 bug
	not	BYTE PTR es:[edi]
	or	BYTE PTR es:[edi],al
	inc	edi
	loop	repbyte_ROPD	; loop uses CX, not ECX, so we're OK
	ret
repbyte_ROPD	endp
;---------------------------------------------------------------------------;
repbyte_ROPE	proc	near
	lods	BYTE PTR ss:[esi]
	db	67h,90h	; 386 bug
	or	BYTE PTR es:[edi],al
	inc	edi
	loop	repbyte_ROPE	; loop uses CX, not ECX, so we're OK
	ret
repbyte_ROPE	endp
;---------------------------------------------------------------------------;
repbyte_ROPF	proc	near
	; rep uses ECX so we need to stash its upper half
	; we can use ESI because the source pointer isn't used for ROPF
	mov	esi,ecx
	movzx	ecx,cx
	xor	al,al
	dec	al
	rep	stos BYTE PTR es:[edi]
	db	67h,90h	; 386 bug
	mov	ecx,esi
	ret
repbyte_ROPF	endp

repdword_table	dw offset repdword_ROP0
		dw offset repdword_ROP1
		dw offset repdword_ROP2
		dw offset repdword_ROP3
		dw offset repdword_ROP4
		dw offset repdword_ROP5
		dw offset repdword_ROP6
		dw offset repdword_ROP7
		dw offset repdword_ROP8
		dw offset repdword_ROP9
		dw offset repdword_ROPA
		dw offset repdword_ROPB
		dw offset repdword_ROPC
		dw offset repdword_ROPD
		dw offset repdword_ROPE
		dw offset repdword_ROPF
repbyte_table	dw offset repbyte_ROP0
		dw offset repbyte_ROP1
		dw offset repbyte_ROP2
		dw offset repbyte_ROP3
		dw offset repbyte_ROP4
		dw offset repbyte_ROP5
		dw offset repbyte_ROP6
		dw offset repbyte_ROP7
		dw offset repbyte_ROP8
		dw offset repbyte_ROP9
		dw offset repbyte_ROPA
		dw offset repbyte_ROPB
		dw offset repbyte_ROPC
		dw offset repbyte_ROPD
		dw offset repbyte_ROPE
		dw offset repbyte_ROPF

; TRUTH TABLE
;P D  0 1 2 3 4 5 6 7 8 9 a b c d e f
;0 0  0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1
;0 1  0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1
;1 0  0 0 0 0 1 1 1 1 0 0 0 0 1 1 1 1
;1 1  0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1



sEnd    CODE

END
