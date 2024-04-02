page	,132
;----------------------------------------------------------------------------;
;		       DeviceIndependentBitmaps				     ;
;		       ------------------------				     ;
; This routine does the	conversions from a device independent bitmap format  ;
; to a format adopted for the SVGA adapter, and back.			     ;
;	  Depending on one of the input	parameters it call either,	     ;
;	   . SetDeviceBitmapBits -  to set the bits in the internal format   ;
;	   . GetDeviceBitmapBits -  to get the bits from the internal format ;
;									     ;
; Copyright (c)	1987  Microsoft	Corporation				     ;
;									     ;
; General Description:							     ;
;									     ;
;	There are four standard	bitmap formats.	 All device drivers	     ;
;	are required to	be able	to translate between any of these	     ;
;	formats	and their own internal formats.	The standard formats	     ;
;	are as follows:							     ;
;									     ;
;			      Bitcount	      Planes			     ;
;			      --------	      ------			     ;
;				  1		 1			     ;
;				  4		 1			     ;
;				  8		 1			     ;
;				 24		 1			     ;
;									     ;
;	These formats are chosen because they are identical or similar	     ;
;	to all formats commonly	used by	raster devices.	 Only single	     ;
;	plane formats are standard, but	it is very easy	to convert these     ;
;	to any multiple	plane format used internally by	a device.	     ;
;									     ;
;	For both the device independent	format and the device specific format;
;	the origin of the bitmap is at the top left hand corner	of the bitmap;
;	X axis extends to the right and	Y towards the bottom, both moving to-;
;	-wards higher memory addresses.					     ;
;									     ;
;  History:								     ;
;     .	Created	for PM by Walt Moore [waltm]		    on 16-May-1987   ;
;									     ;
;     .	Modified by Bob	Gruden [bobgru]			    on 09-Nov-1987   ;
;									     ;
;     .	Adapted	for Windows-286	by Amit	Chatterjee [amitc]  on 10-Oct-1988   ;
;									     ;
; Last Modified	-by-  Amit Chatterjee [amitc]	  12-Oct-1988  17:14:00	     ;
;----------------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.
.286

	.xlist
	include	cmacros.inc
	include	macros.mac
	include	gdidefs.inc
	include	display.inc	; for ipd_*
	include getrle.inc
        .list


	externA		__NEXTSEG	; offset to next segment

	externB		red_shr
	externB		green_shr
	externB		blue_shr

createSeg _DIMAPS,DIMapSeg,word,public,code

sBegin	DIMapSeg

	assumes	cs,DIMapSeg

	externNP	SetDeviceBitmapBits	; in BMC_ETI.ASM
	externNP	GetDeviceBitmapBits	; in BMC_ITE.ASM
	externNP	RleBlt			; in RLD.ASM

	assumes	ds, Data		; this is a CProc after all!
	assumes	es, nothing

cProc	DeviceBitmapBits,<FAR,PUBLIC,WIN,PASCAL>,<ds,si,di,es>
	include	bmc_main.var
cBegin

WriteAux <'DeviceBitmapBits'>		; ***** DEBUG *****
	cld

; get the colour conversion parameters in case we need them...
	mov	ax, wptr [red_shr]
	mov	dx, wptr [green_shr]
	mov	cx, wptr [blue_shr]
	mov	local_red_shr,al
	mov	local_red_shl,ah
	mov	local_green_shr,dl
	mov	local_green_shl,dh
	mov	local_blue_shr,cl
	mov	local_blue_shl,ch

	lds	si, lp_dest_dev 	; DS:SI points to internal BM struc
	assumes	ds, nothing

	mov	al,[si].bmBitsPixel
	shr	al,3			; bits --> bytes
	mov	total_depth_bytes,al

;----------------------------------------------------------------------------;
; we shall do a	few validations	out here. The number of	pels per row and the ;
; number of scans in the internal and external maps must be equal.	     ;
;----------------------------------------------------------------------------;
; formats seem to match. So now	we will	call one of the	two routines which
; actually does	the transfer. Also determine whether own map is	mono or
; color.

	mov	al,SD_COLOR		; assume color map
	cmp	wptr [si].bmPlanes, 101h; is it	one plane AND 1 bit per pel?
	jne	al_has_flag		; no, so it is color

	xor	al, al			; own flag is mono
al_has_flag:
	mov	fbsd, al		; set own color	indicator

; the parameters for the call have been	set, decide which routine to call.
; get a	long pointer to	the start of the destination bitmap

        mov     ax,[si].bmBits.off
        mov     dx,[si].bmBits.sel
        mov     lp_bits_dev.off, ax
        mov     lp_bits_dev.sel, dx

        les     bx,lp_info_ext

        mov     ax,wptr es:[bx].biCompression
        or      ax,ax
        jz      not_encoded
        cmp     ax,BI_RLE4
        ja      error_detected

        errnz   BI_RGB-0
        errnz   BI_RLE8-1
        errnz   BI_RLE4-2
encoded:
        cmp     set_or_get ,SET_CODE
        jnz     rle_get_call

        xor     ax,ax

        arg     <ds,si>                 ; pointer to device structure
        arg     ax                      ; !!! Screen origin X coordinate
        arg     ax                      ; Screen origin Y coordinate
        arg     lp_bits_ext             ; pointer to DI bits
        arg     <es,bx>                 ; pointer to bitmap info block
        arg     <ax,ax>                 ; clipping rectangle NULL

        cCall   RleBlt
        jmp     short xfer_done

rle_get_call:
	cmp	set_or_get ,GET_CODE
	jnz	error_detected

        call    scanline_encode_bitmap
	jmp	short xfer_done

not_encoded:
	mov	ax, lp_bits_ext.off
        or      ax, lp_bits_ext.sel     ; test for zero
	jnz	@F

	cmp	set_or_get,SET_CODE
	je	error_detected		; NULL pointer invalid for set call

	mov	ax,word ptr es:[bx].biWidth	;NULL ptr and GET should
	mul	es:[bx].biBitCount		; return biSizeImage equal
	add	ax,31				; to size needed to hold
	and	ax,NOT 31			; DIB and a success code
	shr	ax,3				; in dx:ax
	mul	num_scans
	mov	word ptr es:[bx].biSizeImage,ax
	mov	word ptr es:[bx + 2].biSizeImage,dx
	mov	ax,num_scans
	sub	dx,dx
	jmp	short	xfer_done

@@:	cmp	set_or_get, SET_CODE	; set code is zero
	jnz	get_call		; the other call

	call	SetDeviceBitmapBits
	jmp	short xfer_done		; return with status code in ax

get_call:
	cmp	set_or_get, GET_CODE	; make sure its	a get call
	jnz	error_detected		  ; error condition

	call	GetDeviceBitmapBits
	jmp	short xfer_done

error_detected:
	xor	ax, ax			; the error code

xfer_done:
cEnd

page
;----------------------------------------------------------------------------;
; A dummy procedure to handle the Create call for independent bitmaps	     ;
;----------------------------------------------------------------------------;

cProc	CreateBitmap,<PUBLIC,FAR>

; do not even bother about parameters

cBegin
	WriteAux <'CreateBitmap'>
	xor	ax, ax			; success code
cEnd

page
;----------------------------------------------------------------------------;
;   do_bitmap_computations						     ;
;									     ;
;	.   copies parameters from the info block to local storage	     ;
;	.   deceided whether the internal map is huge or small		     ;
;	.   set	the carry flag if no copy is to	be done			     ;
;	.   resets tha carry flag if copy is to	be done	and in DX:AX	     ;
;	    returns the	start pointer in the internal map		     ;
;									     ;
;----------------------------------------------------------------------------;

cProc	do_bitmap_computations,<NEAR,PUBLIC>

cBegin
	push	si			; save the pre processor address
	mov	ax, word ptr es:[bx].biWidth
	mov	bitmap_width, ax
	mov	si, ax			; SI has cX
	mov	ax, word ptr es:[bx].biHeight
	mov	bitmap_height, ax
	mov	di, ax			; DI has cY

; now we shall calculate the bytes required for	ecah scan in one plane and
; for each scan	in all planes as well as decide	whether	the map	is a huge map
; or not.
; SI has cX (will be < 32k)
; DI has cY (will be < 32k)

; Note that we are trying to find out the parameters for the target device
; dependent bitmap.
; For the device dependent bitmap, each	scan line will be alligned to a
; WORD boundary, or in other word each scan line has to	be made	a multiple
; of a WWORD.
; To do	the WORD allignment we add 15 to the no	of pels	and then mask the
; result with NOT(15).

	test	fbsd, SD_COLOR		; our format mono chrome ?
	jne	format_is_color		; yes
	mov	cx, 15			; to allign to word boundary
	add	si, cx			;
	not	cx			; fff0
	and	si, cx			; # of bits a multiple of 32
	shiftr	si, 3			; get the number of bytes to store
	jmp	short ax_has_num_planes

format_is_color:
	mov	al,[total_depth_bytes]
	cbw
	xchg	ax,si
	mul	si			; convert pixels to bytes
	xchg	si,ax
	inc	si			; allign to word boundary
	and	si, 0fffeh		;

ax_has_num_planes:
	mov	int_aligned_width, si	; offset to next scan line
	mov	ax, si			; save the value in ax

; multiply by the number of scan lines to get the total	store size required
; by the map.

	mul	di			; DX:AX	has total number of bytes
	jno	size_obtained		; DX = 0 => small map
	dec	dx
	jnz	huge_bitmap		; DX > 1 => huge bitmap
	or	ax, ax			; DX = 1, AX = 0 => small map still
	jz	size_obtained

;----------------------------------------------------------------------------;
; We have a huge bitmap, and must calculate the	additioanal parameters	     ;
;----------------------------------------------------------------------------;

huge_bitmap:
	or	fbsd, SD_HUGE		; set the huge map flag
	mov	NextSegOff, __NEXTSEG	; offset to next segment

;----------------------------------------------------------------------------;
; Let's calculate the no of scan lines which can fit in a segment and the    ;
; filler bytes at the end.						     ;
;----------------------------------------------------------------------------;

; remember, SI has the number of bytes per scan	including all planes

	xor	ax, ax			; ax = 0
	cwd				; dx = 0
	inc	dx			; DX:AX	= 64k
	div	si			; divide by bytes/scan for all planes

; DX now has the no of unused bytes at the end of the segment
; AX has the no	of scans which fit in one segment

	mov	scans_per_seg, ax	; save the # of	scans in each segment
	mov	filler_bytes, dx	; save the number of filler bytes
	add	dx, int_aligned_width
	neg	dx			; gives	the offset to last scan	in seg
	mov	prev_offset, dx		; save it

;----------------------------------------------------------------------------;
; All the defining parameters for the target device dependent bitmap have    ;
; been obtained. Note that the memory for the target bitmap has	already	been ;
; allocated by a prior 'CreateDeviceBitmap' call and we	have been passed a   ;
; long ptr to it. We shall now invoke the format specific initializer routine;
;----------------------------------------------------------------------------;

size_obtained:

;----------------------------------------------------------------------------;
; One of the passed parameters is the no of scan lines to be copied. We	shall;
; validate this	to ensure that the no of scans to copy from the	starting scan;
; does not exceed the no of scans in the map.				     ;
;----------------------------------------------------------------------------;

	pop	si			; get back the preprocessor address

        mov     cx, init_scan           ;
	mov	dx, bitmap_height	; no of scans in the map
	sub	dx, cx			; no of scans from start point to end
	ja	copy_needed		; something to copy case
	stc
	jmp	do_computations_ret	; carry flag set to indicate no copy

copy_needed:
	push	bx
	mov	bx	,dx
        mov     ax, num_scans           ; no of scans to copy
        sub     ax, bx                  ; get minimum of ax and bx in ax
	cwd
	and	ax, dx
	add	ax, bx
	mov	scanline_count, ax	; validated no of lines	to copy
	mov	scans_copied, ax		; we will return this value
	pop	bx			; get back information block pointer

; ES:BX	still points to	the information	block.

	mov	di, bx
	add	di,wptr es:[bx].biSize	; ES:DI points to color conversion table
	call	si			; format specific initializations done

;----------------------------------------------------------------------------;
; BITMAPS in windows have their	origin at the top-left-corner. However the   ;
; first	scan in	the user buffer	is actually the	bottom most line of the	map  ;
; and should be	stored at the bottom of	the map, so we will consider the     ;
; start	scan number for	our own	format to start	at the bottom.This routine is;
; called with a	start scan number which	may not	be zero. We will thus have to;
; compute the exact starting scan line address.				     ;
;----------------------------------------------------------------------------;

PUBLIC	james_bmc_main
james_bmc_main:
	mov	ax	,bitmap_height
	sub	ax	,init_scan
	cmp	ax	,scanline_count
	ja	higher
	mov	ax	,scanline_count

higher:
	dec	ax
	xor	dx, dx			; dx = 0
	test	fbsd, SD_HUGE		; test for huge	maps
	jz	eti_finish_y_calc

;----------------------------------------------------------------------------;
; This is a huge bitmap.Compute	which segment the Y coordinate is in Assuming;
; that no bitmap will be bigger	than 2 or 3 segments, iterative	subtraction  ;
; will be faster than a	divide,	especially if Y	is in the first	segment.     ;
;----------------------------------------------------------------------------;

	mov	cx, __NEXTSEG		; offset to the	next segment
	mov	bx, scans_per_seg	; number of scans in one segment

eti_huge_bitmap:
	add	dx, cx			; Show in next segment
	sub	ax, bx			; See if in this segment
	jnc	eti_huge_bitmap		; Not in current segment, try next
	sub	dx, cx			; Show correct segment

; AX now has the no of scans from the top - the	totals scans in	the segment
; the no of scan left will be from the top as we will be going towards lower
; addresses in our internal map

	add	ax, bx			; restore correct Y
	inc	ax
	mov	huge_scans_left, ax	; save it
	dec	ax

eti_finish_y_calc:
	add	dx, seg_lp_bits_dev	; Dest is our bitmap
	push	dx			; save segment
	mul	int_aligned_width	; Compute offset within the segment
	pop	dx			; get back segment
	add	ax, off_lp_bits_dev	; add to start offset of map
	clc				; reset	carry, coppy is	to be done

do_computations_ret:

cEnd

sEnd	DIMapSeg
END

