;
;	FILE:	vgautil.asm
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module holds routines that are useful in a fairly general
;	context throughout most of the device driver.
;
;	Copyright (c) 1990 by James A. Keller
;

SRCFILE_VGAUTIL         equ     1
incLogical	=	1
incDrawMode	=	1

include cmacros.inc
include gdidefs.inc
include vgareg.inc
include vgautil.inc
include macros.mac

.286
sBegin	Code
assumes cs,Code
assumes ds,Nothing
assumes es,Nothing
assumes ss,Nothing

;
;	get_edge_masks_nibbles
;
;	PARMS:
;	BX	x coord of left edge of rect
;	CX	xExt of rect
;
;	RETURNS:
;	CX	number of full nibbles
;	BL	left edge mask
;	BH	right edge mask
;

left_edge_mask_nibbles	label	byte
db	00001111b,	00001110b,	00001100b,	00001000b

right_edge_mask_nibbles label	byte
db	00001111b,	00000001b,	00000011b,	00000111b

PUBLIC	get_edge_masks_nibbles
get_edge_masks_nibbles	PROC	NEAR

	push	bx

	add	cx,bx				;compute right edge + 1
	and	bx,03H
	mov	al,cs:left_edge_mask_nibbles[bx]	;get left edge mask
	mov	bx,cx				;restore right edge + 1
	and	bx,03H
	mov	ah,cs:right_edge_mask_nibbles[bx]	;get right edge mask
	mov	bx,ax

	pop	ax				;restore left edge
	dec	cx				;get right edge
	and	cx,0FFFCH			;x coord: start of last nibble
	and	ax,0FFFCH			;x coord: 1st pixel of 1st nib
	sub	cx,ax				;compute pixel run-length
	shr	cx,2				;then make it nibble run-length
	je	get_edge_mask_one_nibble	;run is portion of single nibbl
	dec	cx				;adjust for full nibble count
	ret

get_edge_mask_one_nibble:			;if only part of one nibble is
	and	bh,bl				; hit, combine the two masks
	sub	bl,bl				; into one
	ret

get_edge_masks_nibbles	ENDP			;

;
;	vga_set_features
;
;	This little routine sets some of the registers that are always
;	being didled with to do things like fast pattern fills and wierd
;	ROPS. Hope it helps.
;
;	PARMS:
;	AH	7:5 Unused
;		4:3 are desired values of 4:3 in VGAREG_GR_FUNCTION
;		1:0 are desired values of 3:2 in VGAREG_SQ_MODE
;	AL	7:5 Unused
;		4:2 are desired values of 3:1 in VGAREG_SQ_FOREBACK_MODE
;		1:0 are desired values of 1:0 in VGAREG_GR_MODE
;
;	RETURNS:
;	Values set as desired. Other bits in the accessed registers are left
;	undisturbed.
;

PUBLIC	vga_set_features
vga_set_features	PROC	NEAR

	push	ax			;save regs
	push	bx
	push	dx
	mov	bx,ax

	mov	dx,VGAREG_GR_ADDR	;first set the desired write mode
	mov	al,VGAREG_GR_MODE	; in the graphics mode register
	out	dx,al
	inc	dx
	in	al,dx
	and	al,NOT 00000011b
	mov	ah,bl
	and	ah,00000011b
	or	al,ah
	out	dx,al

	mov	dx,VGAREG_SQ_ADDR		;set the desired foreback mode
        mov     al,VGAREG_SQ_FOREBACK_MODE
        out     dx,al
        inc     dx
        in      al,dx
        and     al,NOT 00001110b
	and	bl,00011100b
	shr	bl,1
	or	al,bl
        out     dx,al

	mov	dx,VGAREG_GR_ADDR		;set the desired ALU operation
        mov     al,VGAREG_GR_FUNCTION
        out     dx,al
        inc     dx
        in      al,dx
        and     al,NOT 00011000b
	mov	ah,bh
	and	ah,00011000b
	or	al,ah
        out     dx,al

	mov	dx,VGAREG_SQ_ADDR		;set the desired foreback mode
	mov	al,VGAREG_SQ_MODE
	out	dx,al
	inc	dx
	in	al,dx
	and	al,NOT 00001100b
	and	bh,00000011b
	shl	bh,2
	or	al,bh
        out     dx,al

	pop	dx
	pop	bx
	pop	ax
	ret

vga_set_features	ENDP			       ;

;
;	set_page
;
;	This routine will set the page, extended page, and bank select bits
;	according to the value in DX.
;
;	PARMS:
;	CARRY	CLEAR then assume this is a src address
;		SET   then assume this is a dst address
;		NOTE: need to know whether to set read or write bank bits
;	DL	holds 64K screen segment we need to address
;
;	RETURNS:
;	all vga bits set such that we can access the desired 64K area
;	NOTE: This routine should be used when in sequential chain 4 mode.
;	In planar modes, the page and extended page bits do not need to be
;	set; only the bank select bits are needed. The bank select routines
;	can be called directly.
;

PUBLIC	far_set_page
far_set_page	PROC	FAR

	call	set_page
	ret

far_set_page	ENDP

PUBLIC	set_page
set_page	PROC	NEAR

	pushf
	push	ax				;save regs
	push	dx
	mov	ah,dl
	mov	dx,VGAREG_SQ_ADDR		;set the Extended page bit
	mov	al,VGAREG_SQ_EXTENDED_PAGE
	out	dx,al
	inc	dx
	mov	al,ah
	and	al,01H
	cli
	out	dx,al

	mov	dx,VGAREG_MISC_R		;read in the misc reg
	in	al,dx
	and	al,NOT 20H			;mask out the page bit
	shl	ah,4				;place desired page bit in
	and	ah,20H				; correct bit position and mask
	or	al,ah				; it into al
	mov	dx,VGAREG_MISC_W		;then write the new page bit in
	out	dx,al
	pop	dx
	pop	ax
	shr	dl,2				;prepare to set bank bits
	popf					;carry flag is important
	; FIXME: set_banko is not the same thing as SET_BANK (factor-of-four difference)
	SET_BANK	;call	set_banko
        sti
        ret

set_page    ENDP				;


;
;	set_both_pages
;
;	This routine will set the page select and extended page select bits
;	to the value of bits 1 and 0 of dl respectively. Then both the src
;	AND dst bank select bits are set to the same value -- the value of
;	bits 3:2 of dl.
;
;	PARMS:
;	DL	holds 64K screen segment we need to address
;
;	RETURNS:
;	all vga bits set such that we can access the desired 64K area
;	NOTE: This routine should be used when in sequential chain 4 mode.
;	In planar modes, the page and extended page bits do not need to be
;	set; only the bank select bits are needed. The bank select routines
;	can be called directly.
;

PUBLIC	far_set_both_pages
far_set_both_pages	PROC	far

	call	set_both_pages
	ret

far_set_both_pages	ENDP

PUBLIC	set_both_pages
set_both_pages	PROC	NEAR

	push	dx
        push    ax                              ;save regs
	push	dx
	mov	ah,dl
	mov	dx,VGAREG_SQ_ADDR		;set the Extended page bit
	mov	al,VGAREG_SQ_EXTENDED_PAGE
	out	dx,al
	inc	dx
	mov	al,ah
	and	al,01H
	cli
	out	dx,al

	mov	dx,VGAREG_MISC_R		;read in the misc reg
	in	al,dx
	and	al,NOT 20H			;mask out the page bit
	shl	ah,4				;place desired page bit in
	and	ah,20H				; correct bit position and mask
	or	al,ah				; it into al
	mov	dx,VGAREG_MISC_W		;then write the new page bit in
	out	dx,al
	pop	dx
	pop	ax
	shr	dl,2				;prepare to set bank bits
	; FIXME: set_both_banko is not the same thing as SET_BANK (factor-of-four difference)
	SET_BANK	;call	set_both_banko
	sti
	pop	dx
        ret

set_both_pages	ENDP				    ;

sEnd    Code

END

