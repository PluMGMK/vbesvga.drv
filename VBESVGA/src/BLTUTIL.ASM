;
;	FILE:	bltutil.asm
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module holds routines that are useful in a fairly general
;	context throughout most of the device driver.
;

SRCFILE_BLTUTIL    equ	   1
incLogical	=	1
incDrawmode	=	1

include cmacros.inc
include gdidefs.inc
include display.inc
include bblt.inc
include bitblt.var

EXTRN	abPaletteAccl:BYTE
externA __NEXTSEG

.286
sBegin	Code
assumes cs,Code
assumes ds,Nothing
assumes es,Nothing
assumes ss,Nothing

externW	pxbytes			; in SWCURS.ASM
externW	oem_brush_size		; in ROBJECT.ASM
externW	pattern_copy_numwords	; in ROBJECT.ASM
externW	colour_expand		; in ROBJECT.ASM (function pointer)
externW	colour_compress		; in ROBJECT.ASM (function pointer)
externW	fill_solid_plane	; in ROBJECT.ASM (function pointer)
externNP ipc_to_rgb		; in RGB2IPC.ASM
externB PaddingBits		; in VESAFNS.ASM

;
;	bitmasks for valid colours
;

public	white,notwhite
white		dd ?	; significant bits set, padding bits clear
notwhite	dd ?	; padding bits set, others all clear

;
;	blt_clip
;

PUBLIC	blt_clip
blt_clip	PROC	NEAR

	mov	ax,SrcxOrg
	or	ax,ax			;if rect does not overhang left edge
	jns	@F			; then go clip right edge
	add	xExt,ax 		;else reduce xExt by amount of overhang
	js	blt_clip_full		;if signed, then nothing to blt
	sub	DestxOrg,ax		;remove overhang from dst
	sub	ax,ax			;set the srcxOrg to 0
	mov	SrcxOrg,ax

@@:	add	ax,xExt 		;get right edge of blt + 1
	sub	ax,[si].bmWidth 	;if rect does not overhang right edge
	jbe	@F			; then go clip the top edge
	sub	xExt,ax 		;else reduce xExt by right overhang
	js	blt_clip_full		;if signed, then nothing to blt

@@:	mov	ax,SrcyOrg
	or	ax,ax			;if rect does not overhang top edge
	jns	@F			; then go clip bottom edge
	add	yExt,ax 		;else reduce yExt by amount of overhang
	js	blt_clip_full		;if signed, then nothing to blt
	sub	DestyOrg,ax		;remove overhang from dst
	sub	ax,ax			;set the srcyOrg to 0
	mov	SrcyOrg,ax

@@:	add	ax,yExt 		;get bottom edge of blt + 1
	sub	ax,[si].bmHeight	;if rect does not overhang bottom edge
	jbe	@F			; then done
	sub	yExt,ax 		;else reduce yExt by bottom overhang
	js	blt_clip_full		;if signed, then nothing to blt

@@:	or	word ptr xExt,0
	je	blt_clip_full
	or	word ptr yExt,0
	je	blt_clip_full
	clc
	ret

blt_clip_full:
	stc
	ret

blt_clip	ENDP			;

;
;	blt_set_directions
;

PUBLIC	blt_set_directions
blt_set_directions	PROC	NEAR

	;We need to fixup the xOrg(s) to account for the correct bitness
	xor	cx,cx
	mov	bx,device_flags
	test	bx,DEVFLAG_SRC_COLOR
	jz	@F
	mov	cl,[si].bmBitsPixel
	shr	cx,3	; convert bits to bytes
	mov	ax,SrcxOrg
	mul	cx
	mov	SrcxOrg,ax
@@:
	test	bx,DEVFLAG_DST_COLOR
	jz	@F
	mov	cl,es:[di].bmBitsPixel
	shr	cx,3	; convert bits to bytes
	mov	ax,DestxOrg
	mul	cx
	mov	DestxOrg,ax
@@:
	mov	word ptr vert_dir,0
	mov	word ptr horz_dir,0
        mov     dx,es:[di].bmWidthBytes
	test	word ptr rop_flags,SOURCE_PRESENT
	je	blt_set_directions_done

	mov	bx,[si].bmWidthBytes
	cmp	si,di			;if src and dst are not the same
	jne	blt_set_directions_done ; device, then directions can be
	mov	ax,ds			; X+,Y+
	mov	cx,es
	cmp	ax,cx
	jne	blt_set_directions_done

	mov	ax,SrcyOrg		;Is src_y > dst y
	cmp	ax,DestyOrg		; then blt is Y+
	jae	@F			; go set x direction
	dec	word ptr vert_dir
	neg	bx			;else negate the line lengths for src
	neg	dx			; and dst
	mov	ax,yExt
	dec	ax
	add	SrcyOrg,ax		;set starting y coordinate to last line
	add	DestyOrg,ax		; for both src and dst

@@:	mov	ax,SrcxOrg		;Is src_x > dst_x
	cmp	ax,DestxOrg		; then blt is X+
	jae	blt_set_directions_done ; done
	dec	word ptr horz_dir
	mov	ax,src_xExt_bytes	;adjust starting x coords to
	dec	ax			; the end of the scanline
	add	SrcxOrg,ax
	neg	word ptr src_xExt_bytes ;show by the sign that blt is X-
	mov	ax,dst_xExt_bytes	;adjust starting x coords to
	dec	ax			; the end of the scanline
	add	DestxOrg,ax
	neg	word ptr dst_xExt_bytes ;show by the sign that blt is X-

	mov	ax,first_edge_mask
	xchg	ax,last_edge_mask
	mov	first_edge_mask,ax

blt_set_directions_done:
	sub	bx,src_xExt_bytes	;now set the swing_bytes as correct for
	sub	dx,dst_xExt_bytes	; the x,y blt directions
	mov	src_swing_bytes,bx
	mov	dst_swing_bytes,dx
	ret

blt_set_directions	ENDP		;


;
;       set_memory_address
;
;       This routine computes a segment:offset address given a pointer to
;       a MEMORY bitmap and an (x,y) coordinate in the bitmap. For mono
;       bitmaps it only gets the correct byte location -- this routine does
;       not compute any bitmasks!
;
;       PARMS:
;	DS:SI	ptr to device struct
;       BX:AX   x,y coordinate in bitmap
;
;       RETURNS:
;       DX:AX   segment:offset of point x,y
;

PUBLIC  set_memory_address
set_memory_address      PROC    NEAR

	cmp	[si].bmBitsPixel,1		;if the bitmap is mono
	jne	@f				; then divide the x coord
        shr     bx,3                            ; by 8 to get the byte offset
@@:     mov     cx,word ptr [si + 2].bmBits     ;first segment of bitmap in cx

	push	ax
	mov	ax,[si].bmHeight		;if bitmap is not >= 64K, the
	mul	[si].bmWidthBytes		;bmScanSegment entry is invalid
	sub	ax,1				; so we need to skip over the
	sbb	dx,0				; huge bitmap segment finding
	pop	ax				; code.
	je	sma2
	jmp	short sma1

@@:     add     cx,__NEXTSEG                    ;find the correct segment
	sub	ax,[si].bmScanSegment		; for a huge bitmap
sma1:	cmp	ax,[si].bmScanSegment
        jnc     @B

sma2:	mul	[si].bmWidthBytes		;compute offset into bitmap
        add     ax,bx
        add     ax,word ptr [si].bmBits         ;add start of bitmap
        jnc     @F                              ;if there was a carry from this
        add     cx,__NEXTSEG                    ; add, go into next segment
@@:     mov     dx,cx
        ret

set_memory_address      ENDP                    ;

;
;	get_edge_masks_bytes
;
;	Important things to know about this routine:
;	1) If the region is such that it lies entirely within one byte, then:
;	   RETURN BH:BL will be the correct mask
;	   RETURN AH:AL will equal FF:00 and
;	   RETURN CX will equal 0
;
;	   e.g. If the PARMS are BX = 3, CX = 3
;               RETURN AH:AL = 11111111:00000000
;		RETURN BH:BL = 11100011:00011100
;		RETURN CX = 0
;
;	2) If the region is such that only two bytes are touched then:
;	   RETURN CX = 0
;
;	   e.g. If the PARMS are BX = 4, CX = 7
;		RETURN AH:AL = 11110000:00001111
;		RETURN BH:BL = 00011111:11100000
;		RETURN CX = 0
;
;	PARMS:
;	BX	x coord of left edge of rect
;	CX	xExt of rect
;
;	RETURNS:
;	CX	number of full bytes
;	AH:AL	left edge_mask : NOT left edge mask
;	BH:BL	right edge_mask : NOT right edge mask
;

left_edge_mask_bytes	label	BYTE
db	11111111b,	01111111b
db	00111111b,	00011111b
db	00001111b,	00000111b
db	00000011b,	00000001b

right_edge_mask_bytes	label	BYTE
db	11111111b,	10000000b
db	11000000b,	11100000b
db	11110000b,	11111000b
db	11111100b,	11111110b

PUBLIC	get_edge_masks_bytes
get_edge_masks_bytes	PROC	NEAR

	mov	dx,bx				;save left edge
	and	bx,07H
	mov	al,cs:left_edge_mask_bytes[bx]	;get left edge mask
	mov	bx,dx				;get left edge
	add	bx,cx				;compute right edge + 1
	mov	cx,bx				;save for later
	and	bx,07H
	mov	bl,cs:right_edge_mask_bytes[bx] ;get right edge mask

	dec	cx			;compute right edge + 1
	shr	cx,3			;byte number of start x coord
	shr	dx,3			;byte + 1 number of ending x coord
	sub	cx,dx			;compute width of blt rect in bytes
	jne	@F			;if 0, then only one byte hit, so
	and	bl,al			; combine the two masks into 1.
	mov	bh,bl
	not	bh
	mov	ax,0FF00H
	ret

@@:     dec     cx
	mov	ah,al
	not	ah
	mov	bh,bl
	not	bh
	ret

get_edge_masks_bytes  ENDP		;

;
;	brush_convert_mono_to_mono
;
;	Preping a mono brush for a mono dst you would think would be a ret,
;	but in reality the mono brush needs to be adjusted according to the
;	mono bits of the desired foreground and background colors. Only four
;	possibilities exist if you think about it. Both a 0 and a 1 bit in the
;	brush can map to 0 in the adjusted mono brush (the case of a dark
;	foreground color on a dark background color.) Both a 0 and a 1 may
;	map to a 1 in the adjusted brush. Thirdly, the map could be the
;	identity or lastly it could be the inverse.
;
;	PARMS:
;	DS:SI	ptr to oem_brush_com structure
;	ES:DI	ptr to location to store preped brush
;	BH:BL	bg mono bit:fg mono bit
;
;	RETURNS:
;	ES:DI	the memory it points to is filled with the new mono portion
;		of the brush (NOTE: The entire brush structure is NOT there.
;		Just eight bytes of mono data.)
;

public	brush_convert_mono_to_mono
brush_convert_mono_to_mono PROC    NEAR

	mov	cx,SIZE_PATTERN 		;eight bytes of pattern
	sub	ax,ax				;clear out ax
	mov	dx,ds:[si].oem_brush_style	;get the style
	add	si,oem_brush_mono		;point to mono portion

        and     bx,101H                         ;isolate mono bits
	je	bcmtom_solid			;brush is all zeros
	dec	al
	cmp	bx,101H 			;test to see if brush is
	je	bcmtom_solid			; all ones

	sub	bx,100H 			;the only other options are
        sbb     ah,ah                           ; pattern or NOT pattern
@@:     lodsb                                   ;get mono pattern
        xor     al,ah                           ;either invert it or leave it
        stosb                                   ;save it
        loop    @B
        ret

bcmtom_solid:
        rep     stosb                           ;store the all 0s or all 1s
        ret

brush_convert_mono_to_mono ENDP 		;

;
;	brush_convert_color_to_color
;
;	PARMS:
;	DS:SI	ptr to oem_brush_def structure
;	ES:DI	ptr to location to store preped brush
;
;	RETURNS:
;	ES:DI	the memory it points to is filled with the new color portion
;		of the brush (NOTE: The entire brush structure is NOT there.
;		Just 64 bytes of color data.)
;

public	brush_convert_color_to_color
brush_convert_color_to_color	    PROC    NEAR

	mov	cx,[pattern_copy_numwords]
	shl	cx,3
	errnz	SIZE_PATTERN-8
	rep	movsw				;copy over color pattern
	ret

brush_convert_color_to_color	    ENDP	;

;
;       prep_pattern_norotate
;
;       PARMS:
;       DS:SI   ptr to brush structure
;       ES:DI   ptr to place to put preprocessed pattern
;	SS:BP	ptr to physical fg colour then physical bg colour
;       DL	zero if mono dest, non-zero if colour dest
;
;       RETURNS:
;	DS:SI	points at the "common" part of the brush structure
;	ES:DI	the memory it points to is filled with the new pattern for
;		the brush (NOTE: The entire brush structure is NOT there.
;		Just 64*bpp bytes of color data / 8 bytes of mono data.)
;

PUBLIC	prep_pattern_far
prep_pattern_far	PROC	FAR
	call	prep_pattern_norotate
	ret
prep_pattern_far	ENDP

PUBLIC  prep_pattern_norotate
prep_pattern_norotate	PROC    NEAR

	mov	ax,ds
	or	ax,si				;if the brush is NULL then
	je	bitblt_prep_pattern_error	; there is an error
	mov	bx,[oem_brush_size]
	sub	bx,size oem_brush_com
	mov	ax,[bx+si].oem_brush_style
	cmp	ax,BS_HOLLOW			;if the brush is hollow then
	je	bitblt_prep_pattern_error	; there is an error

	cmp	ax,BS_SOLID			;solid and hatched brushes
	je	bitblt_prep_pattern_copy	; go exactly as they are since
	cmp	ax,BS_HATCHED			; they are created in both hues
	je	bitblt_prep_pattern_copy	; but they may need rotation

	test	byte ptr [bx+si].oem_brush_accel,GREY_SCALE
	je	bitblt_prep_color_pattern
	lea	si,[bx+si]			;point at common part
	test	dl,dl
	jz	@F
	call	[colour_expand]
	lea	si,[si-SIZE_PATTERN]		;go back to start of common part
        jmp     short   prep_pattern_norotate_done

@@:	; get the mono bits for the colours on the stack frame
	mov	ax,[bp]				;foreground
	mov	dx,[bp+2]
	call	ipc_to_rgb			;get accels in DH
	mov	bl,dh
	cmp	bl,0FFh				;just an index?
	jne	@F
	mov	bl,ah				;then accels are in AH
@@:
	mov	ax,[bp+4]			;background
	mov	dx,[bp+6]
	call	ipc_to_rgb			;get accels in DH
	mov	bh,dh
	cmp	bh,0FFh				;just an index?
	jne	@F
	mov	bh,ah				;then accels are in AH
@@:
        call    brush_convert_mono_to_mono
	lea	si,[si-SIZE_PATTERN]		;go back to start of common part
	jmp	short	prep_pattern_norotate_done

bitblt_prep_color_pattern:
	test	dl,dl
	jnz	@F
	call	[colour_compress]
	jmp	short	prep_pattern_norotate_done
@@:	call	brush_convert_color_to_color
	jmp	short	prep_pattern_norotate_done

bitblt_prep_pattern_error:
        stc
        ret

public	bitblt_prep_pattern_copy
bitblt_prep_pattern_copy:
	mov	cx,[pattern_copy_numwords]
	shl	cx,3
	errnz	SIZE_PATTERN-8
	test	dl,dl
	jnz	@F
	mov	cx,SIZE_PATTERN SHR 1
	add	si,bx
@@:	rep	movsw

prep_pattern_norotate_done:
	clc
        ret

prep_pattern_norotate	ENDP				;

;
;       pattern_rotate
;
;       PARMS:
;       DS:SI   ptr to pattern
;       ZERO    CLEAR (NOT EQUAL) if the pattern pointed to by DS:SI is color
;               pattern (64*bpp bytes)
;               SET   (EQUAL) if the pattern pointed to by DS:SI is a
;               mono pattern (8 bytes)
;       ES:DI   ptr to place to put new rotated pattern
;       CH:CL   y rotate count:x rotate count
;
;       RETURNS:
;       ES:DI   new brush filled in correctly. No checking done for NULL brush.
;

PUBLIC  pattern_rotate
pattern_rotate  PROC    NEAR

        push    ax                      ;save regs
        push    bx
	push	dx
        mov     ax,cx
        mov     bx,(SIZE_PATTERN SHL 8) OR SIZE_PATTERN
	je	pattern_rotate_mono

	mov	bx,[pxbytes]
	mul	bx			;multiply both AH and AL by bpp number
	mov	cl,al
	shl	bx,3			;get back to full row size
	errnz	SIZE_PATTERN-8
	mov	dx,bx			;dx = size of row in bytes
	mov	bh,SIZE_PATTERN		;row counter NOT multiplied by bpp
        sub     bx,cx                   ;bh:bl = 8 - y : (8 - x) * bpp
        shl     ah,3                    ;ah = y*bpp*8, i.e. offset of row y within brush
	errnz	SIZE_PATTERN-8
        add     cl,ah                   ;cl = (x+8y)*bpp, i.e. offset of row y, pixel x
	mov	ah,ch			;save unmultiplied row count
        sub     ch,ch                   ;clear out ch
        add     si,cx                   ;add offset into si

pattern_rotate_color_column:
	; At this point:
	; * AL = x * bpp
	; * AH = y [zero second time round]
	; * DX = 8 * bpp
	; * BL = (8 - x) * bpp
	; * BH =  8 - y [y second time round]
	; * SI -> row y, pixel x [row 0, pixel x second time round]

        mov     cl,bl                   ;get number of bytes til end of row
        rep     movsb                   ;move them into new pattern
        sub     si,dx                   ;point to start of src pattern row
        mov     cl,al                   ;number of bytes til the start offset
        rep     movsb

        add     si,dx                   ;go down to next src row
        dec     bh                      ;one less row til we have to wrap
        jne     pattern_rotate_color_column
	shl	dx,3			;increase to full pattern size
	errnz	SIZE_PATTERN-8
        sub     si,dx			;row wrap
	shr	dx,3			;go back to just row size
	errnz	SIZE_PATTERN-8
        or      bh,ah                   ;now do rows up to row offset
        mov     ah,0                    ; 2nd time thru, we want to terminate
        jne     pattern_rotate_color_column
        jmp     short pattern_rotate_done

pattern_rotate_mono:
        sub     bx,ax                   ;bh:ah = 8 - y : y
        mov     cl,ch                   ;cl = y rotate count
        sub     ch,ch                   ;clear out ch
        add     si,cx                   ;add offset into si
	mov	cl,al

pattern_rotate_mono_row:
        lodsb                           ;get first mono pattern row
        ror     al,cl                   ;rotate entire row of mono pattern
        stosb                           ;store row
        dec     bh                      ;one less row til we wrap
        jne     pattern_rotate_mono_row
        sub     si,8                    ;wrap back to start of src pattern
        or      bh,ah                   ;just a few rows left to do
        mov     ah,0
        jne     pattern_rotate_mono_row

pattern_rotate_done:
	pop	dx
        pop     bx
        pop     ax
        ret

pattern_rotate	ENDP				;

;
;	get_exclusion_region
;
;	PARMS:
;	BX,AX	x,y coord of upper left corner of src exclusion region
;	DX,CX	x,y coord of upper left corner of dst exclusion region
;	DI,SI	xExt,yExt of region rectangle
;	parmW	stack parm - device flags obtained by a get_device_flags call
;
;	NOTE:	The two regions specified above are usually the src and dst
;		regions. (For example in a bitblt).
;
;	RETURNS:
;	CARRY	CLEAR if no exclusion is needed (AX,BX,SI,DI may not be valid)
;		SET exclusion is needed and values in AX,BX,SI,DI are valid
;	BX,AX	x,y coord of upper left corner of exclusion rectangle
;	DI,SI	x,y coord of lower right corner of exclusion rectangle
;

EXCLUSION_DEVICE_FLAGS	equ	4

PUBLIC	get_exclusion_region
get_exclusion_region	    PROC    NEAR

	push	bp
	mov	bp,sp
	mov	bp,[bp + EXCLUSION_DEVICE_FLAGS]	;get parm

	and	bp,DEVFLAG_BOTH_SCREEN	    ;if neither src nor dst is the
	je	get_exclusion_region_done   ; screen, then done
	cmp	bp,DEVFLAG_BOTH_SCREEN	    ;if both src and dst are screen
	je	get_exclusion_region_union  ; then get the union
	cmp	bp,DEVFLAG_SRC_SCREEN	    ;if the src is the screen
	je	get_exclusion_region_src    ; then just use src rect
	mov	bx,dx			    ;else use the dst rect
	mov	ax,cx

get_exclusion_region_src:
	add	di,bx				;get right edge of region
	add	si,ax				;get bottom edge of region
	stc					;indicate exclusion required
	jmp	short get_exclusion_region_done

get_exclusion_region_union:
	cmp	bx,dx				;get smaller of x coords
	jl	@F
	xchg	bx,dx
@@:	cmp	ax,cx				;get smaller of y coords
	jl	@F
	xchg	ax,cx
@@:	add	di,dx				;add xExt to larger x coord
	add	si,cx				;add yExt to larger y coord
	stc					;indicate exclusion required

get_exclusion_region_done:
	pop	bp
	ret

get_exclusion_region	    ENDP		;

; helper functions for sanitization, which depend on pxbytes
get_clr1 proc near
	mov	al,es:[di]
	ret
get_clr1 endp
get_clr2 proc near
	mov	ax,es:[di]
	ret
get_clr2 endp
get_clr3 proc near
	mov	ax,es:[di]
	mov	dl,es:[di+2]
	ret
get_clr3 endp
get_clr4 proc near
	mov	ax,es:[di]
	mov	dx,es:[di+2]
	ret
get_clr4 endp
get_clr	label word
	dw	offset get_clr1
	dw	offset get_clr2
	dw	offset get_clr3
	dw	offset get_clr4
set_clr1 proc near
	mov	es:[di],al
	ret
set_clr1 endp
set_clr2 proc near
	mov	es:[di],ax
	ret
set_clr2 endp
set_clr3 proc near
	mov	es:[di],ax
	mov	es:[di+2],dl
	ret
set_clr3 endp
set_clr4 proc near
	mov	es:[di],ax
	mov	es:[di+2],dx
	ret
set_clr4 endp
set_clr	label word
	dw	offset set_clr1
	dw	offset set_clr2
	dw	offset set_clr3
	dw	offset set_clr4

pattern_pad_ones	PROC	NEAR
	; we have a ROP which gives "NOT P" when D and S are 0
	; => sufficient to set P = 1 in the padding bits of the
	;    pattern at ES:DI
	push	di
	mov	bx,[pxbytes]
	dec	bx
	shl	bx,1
	mov	cx,SIZE_PATTERN*SIZE_PATTERN

@@:	call	get_clr[bx]
	or	ax,word ptr notwhite[0]
	or	dx,word ptr notwhite[2]
	call	set_clr[bx]
	add	di,[pxbytes]	; clears CF
	loop	@B

	pop	di
	ret
pattern_pad_ones	ENDP

pattern_set_white	PROC	NEAR
	; just set the entire pattern to white
	push	di
	mov	ax,word ptr white[0]
	mov	dx,word ptr white[2]
	call	[fill_solid_plane]
	pop	di
	ret
pattern_set_white	ENDP

;
;	sanitize_binary_rop
;
;	PARMS:
;	AX	binary ROP index (four bits) requested for the output
;	SI:DI-->64 pixels of pattern to sanitize (or NULL if not needed)
;
;	RETURNS:
;	AX	binary ROP index to be used for the output
;	CARRY	CLEAR if output can proceed without a masking step
;		SET if a masking step is required
;	CX:DX	if CARRY CLEAR: value to OR pattern with before output
;		if CARRY SET: value to AND ROP result with during output
;	SI:DI-->pattern sanitized if needed
;

PUBLIC  sanitize_binary_rop
sanitize_binary_rop  PROC    FAR

	cmp	[PaddingBits],0
	jnz	@F
	; no padding bytes, no problem...
	ret

@@:	; to analyse the binary ROP, we translate it into a ternary one
	; for which S is a don't-care. We do this by doubling the bottom
	; two bits into the bottom nibble, and the upper two bits into
	; the upper nibble, producing an 8-bit index.
	mov	ah,al
	and	al,0011b	; lower two bits
	and	ah,1100b	; upper two bits
	shl	ah,2		; move upper two bits into upper nibble
	or	al,ah		; now AL has two bits at the bottom of each nibble
	mov	ah,al
	shl	ah,2		; now AH has two bits at the top of each nibble
	or	al,ah		; now AL has the bits duplicated as needed
	xor	ah,ah		; now AX is a valid ternary ROP index!

	push	bx
	; this function does most of the analysis...
	call	sanitize_ternary_rop
	pushf			; save CF

	test	bx,bx		; do we have a pattern sanitizing function?
	jz	@F		; nope, move on...
	test	si,si		; AND a pattern to sanitize?
	jz	@F		; nope, move on...

	; sanitize the pattern here and now!
	push	es
	push	dx
	push	ax
	mov	es,si
	call	bx
	pop	ax
	pop	dx
	pop	es

@@:	and	al,00111100b	; get the middle nibble
	shr	al,2		; make it the lower nibble

	popf			; restore CF
	pop	bx
	ret

sanitize_binary_rop	ENDP				;

;
;	sanitize_ternary_rop
;
;	PARMS:
;	AX	ternary ROP index (eight bits) requested for the blit
;
;	RETURNS:
;	AX	ternary ROP index to be used for the blit
;	CARRY	CLEAR if blit can proceed without a masking step
;		SET if a masking step is required
;	CX:DX	if CARRY CLEAR: value to OR pattern with before blit
;		if CARRY SET: value to AND ROP result with during blit
;	BX	NEAR pointer to function to sanitize 64 pixels at ES:DI
;		(or zero if no pattern sanitization needed)
;

ROP_P0S0D0_1	equ	00000001b
ROP_P1S0D0_1	equ	00010000b

PUBLIC	sanitize_ternary_rop
sanitize_ternary_rop	    PROC    NEAR

	; if there are no padding bits, no sanitization is required
	cmp	[PaddingBits],0
	jnz	@F

@@no_sanitization:
	xor	bx,bx	; no pattern sanitization function
	mov	dx,bx	; no need to OR pattern with anything
	mov	cx,bx	; no need to OR pattern with anything
	ret

@@:	; if the ROP gives zero in response to all-zero inputs,
	; there is no problem
	test	ax,ROP_P0S0D0_1
	jz	@@no_sanitization

	; if it gives zero in response to P1 and all-zero S/D,
	; then it can be used as-is with the pattern sanitized
	; by setting the padding bits to 1
	test	ax,ROP_P1S0D0_1
	jnz	@F

	; set padding bits of pattern to 1
	lea	bx,pattern_pad_ones
	; i.e. OR it with notwhite
	mov	dx,word ptr notwhite[0]
	mov	cx,word ptr notwhite[2]
	ret

@@:	; one last check we can do is if the upper and lower
	; nibbles of the ROP index are the same, which means
	; P is a don't-care...
	mov	bx,ax	; back up the ROP index if needed
	mov	ah,al
	and	ah,0F0h	; AH includes only the upper nibble
	shl	al,4	; AL has lower nibble in the upper position
	cmp	ah,al
	jne	@F

	; since P is a don't-care, we can change the ROP and
	; introduce our own pattern: specifically, zero out
	; the lower nibble, so it gives zero for P0, and
	; set the pattern to all white, so that the padding
	; bits are P0 and others are P1.
	xor	ah,ah	; left with the upper nibble in AL
	; set significant bits of pattern to 1
	lea	bx,pattern_set_white
	; i.e. OR it with white
	mov	dx,word ptr white[0]
	mov	cx,word ptr white[2]
	ret

@@:	; we can't sanitize in pre-processing, so a masking step
	; is needed during the blit :(
	mov	ax,bx	; get back the ROP index
	xor	bx,bx	; no pre-processing function
	; need to AND every ROP result with white
	mov	dx,word ptr white[0]
	mov	cx,word ptr white[2]
	; set CF to indicate masking step needed
	stc
	ret

sanitize_ternary_rop	    ENDP		;

sEnd	Code

END

