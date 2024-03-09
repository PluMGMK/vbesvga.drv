;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setrle.asm
;
; Copyright February, 1990  HEADLAND TECHNOLOGY, INC."
;
; This module holds all the RLE decoding routines.
;
; The parameters for copyrle_exi1 are:
;
;      AL      -       00 or FF (bit value repeated 8 times)
;      CX      -       number of pixels (bits) in the run
;      ES:DI   -       pointer to memory where run is to be expanded
;
;
; The parameters for copyrle_exi8 are:
;
;      AL      -       value to "run out" through memory
;      AH      -       same as AL    AH = AL
;      CX      -       number of pixels (bytes) in the run
;      ES:DI   -       pointer to memory where run is to be expanded
;
;
; All of the remaining routines have the following parameters:
;
;      DS:SI   -       pointer to an RL value (this value will be color mapped)
;      ES:DI   -       pointer to place where a "run" will be expanded
;      CX      -       length of the run
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

include	cmacros.inc
include	macros.mac
include	gdidefs.inc
include rledat.inc
include rlecom.inc

	externA 	__NEXTSEG

createSeg	_DIMAPS, DIMapSeg, word, public, code
sBegin		DIMapSeg
	assumes	cs, DIMapSeg

cProc	frame, <FAR,WIN,PASCAL>,<ds,si,di,es>
include	bmc_main.var
cBegin	<nogen>
cEnd	<nogen>


public	scanline_decode_bitmap
scanline_decode_bitmap	proc	near

        push    ax
	push    bx
	push	cx
	push	dx

	les	bx	,lp_dest_dev
	mov	ax, es:[bx].bmWidthBytes
	mov	bitmap_width	,ax
	mov	ax, word ptr es:[bx].bmHeight
	mov	bitmap_height,ax
	mov	ax	,es:[bx].bmFillBytes
	mov	filler_bytes  ,ax
	mov	ax	,es:[bx].bmScanSegment
        mov     scans_per_seg ,ax

        les     bx      ,lp_info_ext
	mov	dx	,WORD PTR es:[bx].biCompression
	mov	cx	,16			;number of color in 4bits

	sub	si	,si
	cmp	dx	,BI_RLE4
	je	external_type_found

	mov	cx	,256			;number of colors in 8bits
	inc	si
	cmp	dx	,BI_RLE8
	je	external_type_found
	jmp	scanline_decode_end

external_type_found:

	test	fbsd, SD_COLOR			  ;is it color?
	jne	scanline_decode_into_color
	add	si	,NOF_EXTERNAL_RLE_TYPES   ;specific routine index

	public scanline_decode_into_color
scanline_decode_into_color:
	add	si	,si			  ;specific decode routine
	mov	ax, decode_rle_table[si]
	mov	decode_rle	,ax
	mov	ax	,decode_absolute_table[si]
	mov	decode_absolute	,ax

        lds     si      ,lp_info_ext
	add	si	,wptr es:[bx].biSize
	mov	ax, ss			; get stack segment into es
	mov	es, ax
	lea	di, color_xlate
	rep	movsw			; word indices

	; initialize variables used in jumps and compute segment/offset
	lds	si	,lp_bits_ext
	les	di	,lp_bits_dev
	xor	ax	,ax
	mov	xlocation   ,ax
	mov	bit_position,al
        mov     ax      ,bitmap_height
	mov	ylocation, ax		; y location is one based
	mov	dx	,es

setstart_loop:
	add	dx	,__NEXTSEG
	sub	ax	,scans_per_seg
	ja	setstart_loop

	sub	dx	,__NEXTSEG
	mov	es	,dx
        add     ax      ,scans_per_seg
	dec	ax
	mul	bitmap_width
	add	di	,ax
	mov	ch	,8
	push	di

;******************************************************************
; for both 8 bit internal and 1 bit internal es:di points to next location to
; place the converted pixel. For 1 bit internal formats, though, we also need
; a bit position specified within the destination byte pointed to by es:di
; This bit position is: bit_position
;******************************************************************

public	scanline_decode_next
scanline_decode_next:
	lodsb				; get major command of rle
	or	si	,si		;  check for segment wrap
	jne	scanline_decode_next_0
	mov	si	,ds
	add	si	,__NEXTSEG
	mov	ds	,si
	sub	si	,si
scanline_decode_next_0:

	cmp	al	,0		; command or runlen?
	jne	scanline_decode_rle

	lodsb				; get minor command of rle
	or	si	,si		;  check for segment wrap
	jne	scanline_decode_next_1
	mov	si	,ds
	add	si	,__NEXTSEG
	mov	ds	,si
	sub	si	,si
scanline_decode_next_1:

	cmp	al	,0		; end of line?
        je      scanline_decode_end_of_line

	cmp	al	,1		; end of frame?
	jne	scanline_decode_end_skip
	jmp	scanline_decode_end

scanline_decode_end_skip:
	cmp	al	,2		; jump record?
	jne	scanline_decode_absolute; must be absolute run then
	jmp	scanline_decode_skip

;******************************************************************
public	scanline_decode_rle
scanline_decode_rle:

	mov	bx,xlocation
	mov	cl	,al		; keep run count
	xor	ah,ah
	add	xlocation,ax

	mov	ch, bl			; compute start bit for mono
	and	ch, 7

	lodsb				; get pixel data to run
	or	si	,si
	jne	scanline_decode_rle_1
	mov	si	,ds
	add	si	,__NEXTSEG
	mov	ds	,si
	sub	si	,si
scanline_decode_rle_1:
	lea	bx	,color_xlate	; point to xlate table
        call    decode_rle
	jmp	scanline_decode_next

;******************************************************************
public	scanline_decode_absolute
scanline_decode_absolute:

	mov	bx,xlocation
	mov	cl	,al		; keep run count
	xor	ah,ah
	add	xlocation,ax

	mov	ch, bl			; compute start bit for mono
	and	ch, 7
	clc				; always in correct nibble order

	lea	bx	,color_xlate	; point to xlate table
        call    decode_absolute
	inc	si			; word align for next source cmnd.
	jne	scanline_decode_abs_1
	mov	si	,ds
	add	si	,__NEXTSEG
	mov	ds	,si
	sub	si	,si

scanline_decode_abs_1:
	and	si	,0FFFEH
        jmp     scanline_decode_next

;******************************************************************
public scanline_decode_end_of_line
scanline_decode_end_of_line:

	dec	WORD PTR ylocation
	mov	WORD PTR xlocation ,0
	mov	BYTE PTR bit_position,0
	pop	di
	sub	di	,bitmap_width
	jnc	scanline_decode_end_of_line_0
	sub	di	,filler_bytes
	cmp	WORD PTR [si]	 ,0100H 	;JAK - check for end of frame
	je	scanline_decode_end_of_line_0	; to avoid invalid segment load
	mov	bx	,es
	sub	bx	,__NEXTSEG
	mov	es	,bx

scanline_decode_end_of_line_0:
	push	di
	jmp	scanline_decode_next

;******************************************************************
public	scanline_decode_skip
scanline_decode_skip:

	lodsb				; fetch x jump
	or  si	,si
	jne scanline_decode_skip0
	mov si	,ds
	add si	,__NEXTSEG
	mov ds	,si
	sub si	,si
scanline_decode_skip0:
	xor ah,ah
	add xlocation, ax		; update current x location

	lodsb				; fetch y jump
	or  si	,si
	jne scanline_decode_skip1
	mov si	,ds
	add si	,__NEXTSEG
	mov ds	,si
	sub si	,si

	public scanline_decode_skip1
scanline_decode_skip1:
	xor	ah	,ah
	sub	ylocation, ax		; update current y location

	pop	di			; get old start of scan - waste it
	les	di	,lp_bits_dev	; compute address of new location
	mov	ax	,ylocation	; note ylocation is one based
	mov	dx	,es

scanline_decode_skip2:
	add	dx	,__NEXTSEG
	sub	ax	,scans_per_seg
	ja	scanline_decode_skip2

	sub	dx	,__NEXTSEG
	mov	es	,dx
        add     ax      ,scans_per_seg
	dec	ax
	mul	bitmap_width
	add	di	,ax		; address of begining of scan
	push	di			; define new start of scan

	test	fbsd	,SD_COLOR	; is destination color
	jne	scanline_decode_skip_color

	; compute byte offset and bit location of next mono pixel
	mov	ax	,xlocation
	shr	ax	,1		; get byte of x location
	shr	ax	,1
	shr	ax	,1
	add	di	,ax		; byte of next pixel

	mov	ax	,xlocation
	and	al	,7
	mov	bit_position	 ,al	; keep bit position around
	jmp	scanline_decode_next

scanline_decode_skip_color:
	add	di	,xlocation	; offset of next pixel
	jmp	scanline_decode_next

;******************************************************************
public	scanline_decode_end
scanline_decode_end:

	pop	di
	pop	dx
	pop	cx
	pop	bx
	pop	ax
        ret

	db	"COPYRIGHT FEBRUARY 1990 HEADLAND TECHNOLOGY, INC."

scanline_decode_bitmap	endp


sEnd	DIMapSeg

END
