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

externW	oem_brush_size		; in ROBJECT.ASM
externW	pattern_copy_numwords	; in ROBJECT.ASM

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
;	DS:SI	ptr to oem_brush_def structure
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
;	brush_convert_mono_to_color
;
;	The classic color expansion problem.
;
;	PARMS:
;	BH:BL	bgcolor:fgcolor
;	DS:SI	ptr to oem_brush_def structure
;	ES:DI	ptr to location to store preped brush
;
;	RETURNS:
;	ES:DI	the memory it points to is filled with the new color portion
;		of the brush (NOTE: The entire brush structure is NOT there.
;		Just sixty-four bytes of color data.)
;
; FIXME: Best thing to do here might be to refactor realize_hatched (in robject)
; to allow modal code reuse between this function and that one. Might be better
; to sort out heap corruption before we start messing with robject again...
public	brush_convert_mono_to_color
brush_convert_mono_to_color	   PROC    NEAR

	add	si,[oem_brush_size]
	sub	si,size oem_brush_com		;point to mono portion
	mov	cl,SIZE_PATTERN 		;SIZE_PATTERN rows of data
	xor	bh,bl

brush_convert_mono_to_color0:
	mov	ch,SIZE_PATTERN 		;SIZE_PATTERN bytes across
	lodsb					;get first mono byte
	mov	ah,al				;move into ah

brush_convert_mono_to_color1:
        rol     ah,1                            ;get first bit
	sbb	al,al				;the classic color expansion
	and	al,bh				; process
	xor	al,bl
	stosb
	dec	ch				;do all pixels in a row
	jne	brush_convert_mono_to_color1
	loop	brush_convert_mono_to_color0	;do all the rows
	ret

brush_convert_mono_to_color	   ENDP 	;

;
;	brush_convert_color_to_mono
;
;	The classic color compression problem.
;
;	PARMS:
;	DS:SI	ptr to oem_brush_def structure
;	ES:DI	ptr to location to store preped brush
;	BX	driver data segment so we can access abPaletteAccl
;
;
;	RETURNS:
;	ES:DI	the memory it points to is filled with the new mono portion
;		of the brush (NOTE: The entire brush structure is NOT there.
;		Just eight bytes of mono data.) However, the ES:DI buffer
;		needs 64 free bytes for temporary scratch space.
;

public	brush_convert_color_to_mono
brush_convert_color_to_mono	   PROC    NEAR

	mov	cx,SIZE_PATTERN * SIZE_PATTERN	;SIZE_PATTERN rows of data
	rep	movsb				;copy over color pattern
	sub	di,SIZE_PATTERN * SIZE_PATTERN	;restore di
	mov	si,di

	mov	ds,bx				;driver data segment into ds
        lea     bx,abPaletteAccl                ;color to mono xlat table
	mov	cl,SIZE_PATTERN 		;SIZE_PATTERN rows of data

brush_convert_color_to_mono0:
	mov	ch,SIZE_PATTERN 		;SIZE_PATTERN bytes across

brush_convert_color_to_mono1:
	lods	byte ptr es:[si]		;get first mono byte
	xlat					;abPaletteAccl holds mono bits
	ror	al,1				;pull out mono bit
	rcl	ah,1				;shove it into ah
	dec	ch				;next byte in pattern row
	jne	brush_convert_color_to_mono1
	mov	al,ah
	stosb					;store compressed byte
	loop	brush_convert_color_to_mono0	;next pattern row
	ret

brush_convert_color_to_mono	   ENDP 	;

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

	mov	bx,[oem_brush_size]
	sub	bx,size oem_brush_com
	shr	bx,6			;divide by 64==SIZE_PATTERN**2
	errnz	SIZE_PATTERN-8
	mul	bx			;multiply both AH and AL by bpp number
	mov	cl,al
	shl	bx,3			;get back to full row size
	errnz	SIZE_PATTERN-8
	mov	dx,bx
	mov	bh,SIZE_PATTERN		;row counter NOT multiplied by bpp
        sub     bx,cx                   ;bh:bl = 8 - y : (8 - x) * bpp
        shl     ah,3                    ;8 pixels per pattern row
	errnz	SIZE_PATTERN-8
        add     cl,ah                   ;add in x rotate count
	mov	ah,ch			;save unmultiplied row count
        sub     ch,ch                   ;clear out ch
        add     si,cx                   ;add offset into si

pattern_rotate_color_column:
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
        dec     bh                      ;one less rwo til we wrap
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

sEnd	Code

END

