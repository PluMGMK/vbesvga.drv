PUBDEFS	equ	1
;----------------------------------------------------------------------------;
;			 SetDeviceBitmapBits				     ;
;			 -------------------				     ;
;   Converts device independent	bitmap format into a bitmap format suitable  ;
;   for	EGA adapters.							     ;
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
;     .	Adapted	for Windows-286	by Amit	Chatterjee [amitc]  on 03-Oct-1988   ;
;									     ;
;     .	Modified to suite 4 plane EGA/VGA drivers  for Windows 286/386	     ;
;				by Amit	Chatterjee [amitc]  on 30-Nov-1988   ;
;									     ;
; Last Modified	-by-  Amit Chatterjee [amitc]	 30-Nov-1988   08:04:25	     ;
;									     ;
; Modified to work in VRAM's 256 color modes by Irene Wu, Video 7, 2/89      ;
;									     ;
; Fixed 24-bit code - Steve Glickman - Headland Technology - 21 Nov 91       ;
;----------------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.

.286
MONO_BIT		equ	00000001b

	.xlist
	include	cmacros.inc
	include	gdidefs.inc
	include display.inc
	include	lines.inc
	include	macros.mac
	.list

	externA		__NEXTSEG	; offset to next segment

	externFP	sum_RGB_alt_far		; in ROBJECT.ASM
	externFP	rgb_to_ipc_seq		; in RGB2IPC.ASM


sBegin Data
	externD 	GetColor_addr		; DeviceColorMatch vector
sEnd


createSeg _DIMAPS,DIMapSeg,word,public,CODE
sBegin	DIMapSeg
	assumes	cs, DIMapSeg

	externNP	do_bitmap_computations	; in BMC_MAIN.ASM
	externNP	OurDeviceColourMatch	; in DISCREEN.ASM

;----------------------------------------------------------------------------;
; The following	table contains the addresses of	the initialization routines  ;
; for each of the 4 Device Independent Bitmap formats.			     ;
;----------------------------------------------------------------------------;

anpfnPreProc	label	word
	dw	eti_1			; 1 bit	per pel	format
	dw	eti_4			; 4 bits per pel format
	dw	eti_8			; 8 bits per pel format
	dw	eti_24			; 24 bits per pel format


	assumes	ds, nothing
	assumes	es, nothing

cProc	frame,<FAR,WIN,PASCAL>,<ds,si,di,es>
	include	bmc_main.var
cBegin	<nogen>
cEnd	<nogen>

	public	SetDeviceBitmapBits

SetDeviceBitmapBits	proc	near

WriteAux <'bmc_eti'>                    ; ***** DEBUG *****

        cld
	xor	ax, ax
	mov	scans_copied, ax	; init the # of	scans copied field


;----------------------------------------------------------------------------;
; Test to see that the format of the Device Independent	Bitmaps	is one that  ;
; we support.								     ;
; The number of	color planes must be 1,	and the	bits per pel can be 1/4/8/24 ;
;----------------------------------------------------------------------------;

	les	bx, lp_info_ext		; far pointer to Bitmap	Header
	assumes	es, nothing

	xor	cx, cx			; will be the success/failure code
	cmp	es:[bx].biPlanes, 1	; # of color planes must be 1
	jne	cbmi_invalid_format	; not supported

	mov	ax, es:[bx].biBitCount
	cmp	ax, 1			; test the bits	per pel	value
	je	cbmi_have_format	; CX has the index

	inc	cx			; try next index
	cmp	ax, 4			; 4 bits per pel ?
	je	cbmi_have_format	; index	= 1

	inc	cx			; try next index
	cmp	ax, 8			; 8 bits per pel ?
	je	cbmi_have_format	; index	= 2

	inc	cx			; try next index
	cmp	ax, 24			; 4 bits per pel ?
	je	cbmi_have_format	; index	= 3

cbmi_invalid_format:
	mov	cx, 0ffffh		; want CX to be	made zero below
	xor	ax, ax			; error	code
	jmp	eti_exit		; get out

cbmi_have_format:
	mov	ax, cx			; get the index
	add	ax, ax			; double it for	word table access

;----------------------------------------------------------------------------;
; perform the format specific initialization now			     ;
;----------------------------------------------------------------------------;
	push	bx			; save offset to info block
	xchg	ax, bx
	mov	si, anpfnPreProc[bx]	; Save preprocessor's address
	pop	bx			; get back offset to info block

; SI has the address of	the format specific pre-processor routine
; Copy the bitmap data as necessary to local frame storage

	cCall	do_bitmap_computations

; the above routine does the following:
;	.   copies parameters from the info block to local storage
;	.   deceided whether the internal map is huge or small
;	.   clears carry flag if no copy is to be done
;	.   sets tha carry flag	if copy	is to be done and in DX:AX
;	    returns the	start pointer in the internal map

	jnc	eti_copy_needed		; test for error
	xor	ax, ax			; 0 scans copied
	jmp	eti_exit

eti_copy_needed:
	mov	es, dx
	assumes	es, nothing
	mov	di, ax			; set ES:DI point to internal map

; ES:DI	now points to the starting position in target (device dependent) map

        lds     si, lp_bits_ext         ; Source is user's buffer
	assumes	ds, nothing

;----------------------------------------------------------------------------;
; A point to remember. The source of the transfer is just an array of bits in;
; the specified	format.	It is not a complete bitmap, but just a	portion	that ;
; is to	be copied. We, thus, do	not have to do any further calculations	for  ;
; obtaining the	starting address in the	source buffer, it is the passed	long ;
; pointer. Also	note that the user buffer may arbitarily cross a segment     ;
; boundary (even a single scan line could span the boundary). However even in;
; source the scan lines will be aligned to a DWORD (they could still cross a ;
; segment if the bytes per scan	is large enough).			     ;
;----------------------------------------------------------------------------;

; test to see whether users buffer cross a segment or not, if it does special
; code will be needed.

	mov	cx, scanline_count	; no of	scans to copy

        mov     ax, scan_length.hi      ; do full 32 bit multiplication
	mul	cx			; multiply the HIWORD

; assuming that scan_length.hi is not so large to overflow result into DX

	xchg	ax, bx			; save in bx
	mov	ax, scan_length.lo	; LOWORD multiplication
	mul	cx

; BX has the HIWORD mul	result

	add	dx, bx			; DX:AX	= total	bytes of buffer	needed

; SI has the start offset to the user's buffer

	add	ax, si
	adc	dx, 0			; DX:AX	= last address + 1
	jz	eti_in_segment		; Won't cross a segment boundary
	or	fbsd, CAN_CROSS_SEG	; Can cross a segment boundary

	public	eti_next_scan
eti_next_scan:
	test	fbsd, CAN_CROSS_SEG	; If buffer might cross	a segment
	jnz	eti_might_cross_seg	; then go check it out

eti_in_segment:
	push	di			; Save bitmap scan start address
	mov	cx, int_move_count	; Set translation procedure loop count
	jcxz	eti_see_about_partial	; No full bytes!
	call	full_byte_proc		; Process all complete bytes

eti_see_about_partial:
	mov	cx, int_remaining_pixel_count  ; Process any partial byte
	jcxz	eti_no_partial_byte
	mov	bx, mono_shift_align_count ; alignment for the partial bytes
	call	partial_byte_proc

eti_no_partial_byte:
	pop	di
	dec	scanline_count
	jz	eti_xfered_all		; Transfered all scans

; remember we map the first scan line in the user buffer to the	last scan line
; in our internal map, so the pointer in our own format	starts at the bottom
; and then goes	up

	sub	di, int_aligned_width	; --> previous bitmap scanline
	add	si, ext_dword_adjust	; Align to dword boundary
	jnc	eti_chk_segment_update	; don't update segment if no wrap
	mov	ax, ds			; otherwise, increment segment
	add	ax, __NEXTSEG
	mov	ds, ax
	assumes	ds, nothing

eti_chk_segment_update:
	test	fbsd, SD_HUGE		; If not a huge	bitmap,
	jz	eti_next_scan		; go do	next scanline

	dec	huge_scans_left 	; Any more scans in this segment?
	jnz	eti_next_scan		; yes, don't update bitmap pointer
	mov	ax, es
	sub	ax, __NEXTSEG		; go to	the previous segment
	mov	es, ax
	assumes	es, nothing

	mov	di, prev_offset		; start	from the bottom	of the segment
	mov	ax, scans_per_seg
	mov	huge_scans_left, ax	; This many scans in the segment
	jmp	eti_next_scan


eti_might_cross_seg:

;  The buffer will cross a segment boundary.  If this scanline will
;  cross the segment, then we'll process eight bits of bitmap data
;  at a	time.  !!! someday we may improve upon this, but we don't
;  expect this to be critical !!!

	mov	ax, si			; If the entire	scan shows, then
	xor	dx, dx			; we can use the normal	code
	add	ax, scan_length.lo
	adc	dx, scan_length.hi	; scan_length may be > 64K
	jz	eti_in_segment		; It won't cross a segment boundary

;  The scan will cross a segment boundary.   We'll take the easy
;  way out and do the entire scanline one bitmap byte at a time.

	push	di			; Save bitmap scan start address
	mov	cx, int_move_count	; If only a last byte exists,
	jcxz	eti_see_about_partial	; use the normal code
	mov	some_temp, cx		; Save full byte count

eti_looking_to_cross:
	mov	cl, num_pels_per_src_byte ; process one byte of source
	xor	ch,ch
        xor     bx, bx                  ; No alignment required
	call	partial_byte_proc
	dec	some_temp
	jnz	eti_looking_to_cross
	jmp	eti_see_about_partial	; Finish with partial byte code

eti_xfered_all:
	mov	ax, scans_copied	; Return number	of scans copied

eti_exit:
	WriteAux <'bmc_eti-out'>
	cwd
	ret

SetDeviceBitmapBits	endp


;----------------------------------------------------------------------------;
;
;		 METHOD	OF TRANSFERRING	A SINGLE SCAN LINE
;		 -----------------------------------------
;
; We know that:
;		 . The source may have 1,4,8 or	24 bits	per pel, and
;		 . the size of each scan in the	source buffer is a multiple
;		   of 4	bytes (DWORD)
;
; This means that towards the end of the scan line some	of the bits will be
; filler bits and not information bits.	We have	the option of skipping over
; the filler bits or convert them too -	and would choose which ever gives a
; simpler algorithm.
;
; Device dependent bitmaps also	store scan lines as a multiple of DWORDS and
; hence	we will	also have filler bits in our internal formats.
;
; Consider, the	first two formats: (1 or 4 bits	per pel)
;
; 1 or 4 bits from the source will be mapped into 1 bit	(for each plane) in
; the target, and we know that the no of bits in the source are	a multiple of
; 32 (including	the fiiler bits	ofcourse). As 32/4 = 8,	so if we converts all
; the bits we will always have an integral number of bytes in the destination.
; Also since we	shall be converting all	the bits, we will not have to skip
; over the filler bits in the source buffer to move over to the	next scan line.
;
; Consider the 8 bits per pel format:
;
; 8 bits from the source will be converted into	one bit	in the target, and the
; source scan has a multiple of	32 bits. Here again we will try	to convert the
; whole	of the source scan line	including the filler bits, thus	here again at
; the end of the copy of one scan line,	the source pointer will	not have to be
; advanced over	the filler  bytes. However, 32/8 is 4, and hence if the	length
; of the source	scan line is an	odd multiple of	a DWORD	size, then we will
; have an incomplete byte at the end for the destination.
;
; How do we generate the target	bits ? we process them a byte at a time. We
; extract the required number of source	bits, convert them into	one
; destination bit (based on the	color mapping) and start building a target
; byte by stuffing it into a byte variable from	the right. Once	8 targer bits
; have been compiled we	store the target byte.
;
; With this approch, for the 8 bits/pel	case, if we do have a leftover nibble,
; it will be at	the right end of the work byte.	Thus it	has to be alligned
; against the left end and then	stored.	So we will also	prepare	an allignment
; mask for this	case.
;
; Finally consider the 24 bits/pel case. Here the 24 bits to a pel themselves
; give the color value and we will always process the source 24	bits at	a time.
; However as 32	is not a multiple of 24, we cannot always include the filler
; bits in the conversion. So in	this case the source pointer will have to be
; carried over the filler bytes	and we will calculate the number of bytes of
; adjustment required.
;
; In the last case 24 bits get mapped into 1 target bit	so for the target we
; may then get an incomplete byte again, which has to be correctly alligned
; before storing.
;
; We will thus calculate the following parameters for each of the formats:
;
;	int_move_count	      ---- the number of complete bytes for target
;	scan_length	      ---- no of bytes for source which yield the above
;	int_remaining_pixel_count ---- the last few source pels which do not yield
;				   a complete target byte.
;	allignment	      ---- no of positions by which the incomplete last
;				   target byte is to be shifted before storing
;	ext_dword_adjust      ---- no of bytes to be added to the the source
;				   ptr at the end of the copy to move over to
;				   the start of the next scan line in src buf
;
; Let's see how we calculate these values:
;
; 1 bit	per pel:
; --------------
; int_move_count = scan_length = width_scan (no of bytes in one scan)
; rest of the parameters are all zero.
;
;
; 4 bits per pel:
; ---------------
; We have to first calculate the no of bits in the source buffer after the
; DWORD	allignment.
;
; To do	this we	have to	multiply the no	of pels	by 4, add 31 and AND with
; NOT(31). This	then has to be divided by 8*4 to give the no of	bytes. The
; process can be simplified if we observe what exactly happens in binary.
;
; let n	a string of 0's and 1's	representing the no of pels in binary.
;
;	 n*4  -----		      n00      (shiftl n,2)
;    add 31		     +	    11111
;    AND NOT(31)	     &	 ..100000
;    divide by 8*4		 shift right by	5 bits
;
; This is equivalent to:
;
;				    n
;			    +	  111	(add n,7)
;			 shift right 5 3 bits
;
; The above result will be int_move_count, and this multiplied by 4
; will give scan_length.
;
; Here again we	will neither have partial bytes	nor any	source buffer
; adjustment byte.
;
; 8 bits per pel:
; ---------------
;
; This case is very similar to the 4 bits per pel case.	Following similar
; logic,
;			 mov	 ax,n	 --  no	of pels
;			 add	 ax,3	 --  last 2 bits of value 31
;			 mov	 bx,ax
;	    this value /8 gives	no of bytes in target
;			 shiftr  ax,3	 --- int_move_count
;	    to get the no of bytes in source we	will have to AND NOT(31)
;	    and	divide by 8, but since last 3 bits are always zero, so
;			 and	 bl,0f4h -- scan_length	in bx
;
; also note since we pack 8 bits into 1	bit, the remainder on division by
; 64 gives the last few	bits whcich can't be packed into a byte, then divided
; by 8 gives the last few pels that cant be packed in a	byte.
; This can be obtained simply by ANDind	BX with	4 and note that	the result
; will be 0 or 4 (as at	best one nibble	can be left over) and if it is 4, then
; that is also the alignment factor.
;
; 24 bits per pel:
; ----------------
;
; Here we will not be converting any of	the filler bits. So if n is the	no.
; of pels, n/8 gives the no. of	complete target	bytes and rem(n,8) gives the
; number of pels in the	incomplete byte, the differnece	of this	from 8 will
; give us the allignment(ie, the number	of left	shifts).
;
; mod(allignment,4) will give us the number of bytes by	which the source
; pointer has to be advanced at	the end	of the copy.
;
;----------------------------------------------------------------------------;

	page
;--------------------------Private-Routine-----------------------------------;
; eti_1									     ;
;									     ;
;   Bitmap conversion, external	1-bit format to internal		     ;
;									     ;
;   This routine is responsible	for all	preprocessing for converting	     ;
;   from external 1 bit	per pixel to internal formats			     ;
;									     ;
; Entry:								     ;
;	ES:DI --> where	color table is					     ;
; Returns:								     ;
;	None								     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

        ?_pub   eti_1
eti_1	proc	near

	xor	ax, ax
	mov	int_remaining_pixel_count, ax  ; Will never have a partial byte
	mov	scan_length.hi, ax	; Max dest scan	size is	< 64K
	mov	ext_dword_adjust, ax
	mov	mono_shift_align_count,ax

        mov     dx, DIMapSegOFFSET copy_e1i1
	mov	bx, DIMapSegOFFSET copy_e1i1_partial
	mov	num_pels_per_src_byte,1 ; src will give straight xlate

	test	fbsd, SD_COLOR		; Monochrome destination?
	jz	short eti_1_have_proc

	mov	dx, DIMapSegOFFSET copy_e1i8
	mov	bx, DIMapSegOFFSET copy_e1i8_partial
	mov	num_pels_per_src_byte,8 ; src generates 8 bytes
;
eti_1_have_proc:
	mov	full_byte_proc, dx
	mov	partial_byte_proc, bx	; Might	need this for seg boundaries
        mov     cx, 2                   ; There will be 16 color table entries
        call    create_color_table      ; Create the color table to use

; Whenever we allocated	a scanline (or each scan of a color
; bitmap), we allocated	to a dword boundary.  If we just
; translate for	the width of the scan in bytes,	the required
; dword	alignment will be maintained.

; independent map is alligned on DWORDS	and own	map on WORDS
; so may have left over	bytes at the end

	mov	ax, bitmap_width	; get no of external pels
	mov	dx,ax			; temp...
	mov	cx, 31
	add	ax, cx			; try to allign	to dword
	not	cx
	and	ax, cx			; ax is alligned to dwords
	mov	bx,ax			; save the dword max bitmap width
        shiftr  ax, 3                   ; get no of bytes
	mov	scan_length.lo, ax	; Set #	bytes of user buffer required
;
; calculate the internal move count
;
	mov	ax,dx
	shiftr	ax,3
	mov	int_move_count,ax
;
; calculate the internal remaining pixel count
;
        shiftl  ax,3
        sub     dx,ax
	mov	int_remaining_pixel_count,dx
	jz	eti1_skip
;
; calculate the monochrome shift alignment count
;
	sub	dx,8
	neg	dx
	mov	mono_shift_align_count,dx
;
eti1_skip:
;
; calculate the external dword adjustment
;
	sub	bx,bitmap_width
	shiftr	bx,3
	mov	ext_dword_adjust,bx
	ret

eti_1   endp

	page
;--------------------------Private-Routine----------------------------------;
; eti_4									    ;
;									    ;
;   Bitmap conversion, external	4 bit to internal format		    ;
;									    ;
;   This routine is responsible	for all	preprocessing for converting	    ;
;   from external 4 bit	format to our internal formats.			    ;
;									    ;
; Entry:								    ;
;	ES:DI --> where	color table is					    ;
; Returns:								    ;
;	None								    ;
;---------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

        ?_pub   eti_4
eti_4	proc	near

        xor     ax, ax
	mov	ext_dword_adjust, ax	      ; Everything will be dword aligned
	mov	int_remaining_pixel_count, ax ; Will never have a partial byte
	mov	scan_length.hi, ax	      ; Max dest scan size is < 64K
	mov	mono_shift_align_count,ax
;
        mov     cx, 16                  ; There will be 16 color table entries
	call	create_color_table	; Create the color table to use

	mov	ax, DIMapSegOFFSET copy_e4i1
	mov	bx, DIMapSegOFFSET copy_e4i1_partial
	mov	num_pels_per_src_byte,8 ; mono dest needs 8 pels

	test	fbsd, SD_COLOR		; Monochrome destination?
	jz	eti_4_have_proc		; It is	mono

	mov	ax, DIMapSegOFFSET copy_e4i8
	mov	bx, DIMapSegOFFSET copy_e4i8_partial
	mov	num_pels_per_src_byte,2 ; src provides 2 pels

        ?_pub eti_4_have_proc
eti_4_have_proc:
	mov	full_byte_proc, ax
	mov	partial_byte_proc, bx	; Might	need this for seg boundaries
;
	mov	ax, bitmap_width	; Compute the number of source bytes
	mov	dx,ax
	add	ax, 7			; force dword alignment of the source
	and	al, 0f8h
	mov	bx,ax
        shr     ax, 1
        mov     scan_length.lo, ax      ; Set # bytes of user buffer required
;
; process mono & 8 bit separately
;
	test	fbsd, SD_COLOR
	jne	eti_4t8_color
;
; calculate the monochrome internal move count
;
        mov     ax,dx
	shiftr	ax,3
	mov	int_move_count,ax
;
; calculate the monochrome internal remaining pixel count
;
	mov	ax,dx
	and	ax,0111b
	mov	int_remaining_pixel_count,ax
	jz	eti_4t1_color
;
; calculate the monochrome shift alignment count
;
	sub	ax,8
	neg	ax
	mov	mono_shift_align_count,ax
;
; calculate the external dword adjustment
;
eti_4t1_color:
	sub	bx,dx
	shr	bx,1
	mov	ext_dword_adjust,bx
	ret
;
eti_4t8_color:
;
; calculate the color internal move count, with no int_remaining_pixel_count
;
; IF we have an 8-bit destination, then it's more efficient to round UP to
; the nearest even number, because if we process an extra pixel, it just ends
; up being the alignment byte to make the scanline word-aligned.
; OTHERWISE (depth >= 2 bytes), we have to round down, and set the excess
; count appropriately (which will involve calling copy_e4i8_partial).
;
	xor	ax,ax
        shr     dx,1                    ; # of source BYTES
	adc	al,al			; get excess pixel count (1 or 0)
	cmp	[total_depth_bytes],2
	jnb	@F
	add	dx,ax			; process extra pixel (alignment byte)
	xor	ax,ax			; no partial pixels in that case
@@:
        mov     int_move_count,dx
	mov	int_remaining_pixel_count,ax
;
; calculate the external dword adjustment
;
	shr	bx,1			; make a byte count
	sub	bx,dx			; get the remaining bytes
	sub	bx,ax			; partial pixel also counts!
	mov	ext_dword_adjust,bx	; save the difference
;
	ret

eti_4   endp

	page
;--------------------------Private-Routine----------------------------------;
; eti_8									    ;
;									    ;
;   Bitmap conversion, external	8 bit to internal format		    ;
;									    ;
;   This routine is responsible	for all	preprocessing for converting	    ;
;   from external 8 bit	format to our internal formats			    ;
;									    ;
; Entry:								    ;
;	ES:DI --> where	color table is					    ;
; Returns:								    ;
;	None								    ;
;---------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

	?_pub	eti_8
eti_8	proc	near

	xor	ax, ax			; Will not require any buffer adjustment
	mov	mono_shift_align_count, ax
	mov	ext_dword_adjust, ax
	mov	scan_length.hi, ax	; Max dest scan	size is	< 64K
	mov	num_pels_per_src_byte,8 ; loop max = 8 for mono

        mov     cx, 256                 ; There will be 256 color table entries
	call	create_color_table	; Create the color table to use

	mov	ax, DIMapSegOFFSET copy_e8i1
	mov	bx, DIMapSegOFFSET copy_e8i1_partial

	test	fbsd, SD_COLOR		; Monochrome destination?
	jz	eti_8_have_proc		; It is	mono

	mov	ax, DIMapSegOFFSET copy_e8i8
	mov	bx, DIMapSegOFFSET copy_e8i8_partial
	mov	num_pels_per_src_byte,1 ; src will give straight xlate

eti_8_have_proc:
	mov	full_byte_proc, ax
	mov	partial_byte_proc, bx

	mov	ax, bitmap_width	; Compute the number of	source bytes
	mov	dx, ax			; save a copy for later
        add     ax, 3                   ; to convert.   Each dword becomes
	and	al, 11111100b		; 4 source bytes = 1 dest nibble
	mov	scan_length.lo, ax	; Set #	bytes of user buffer required
	mov	bx, ax			; bx holds the dword adjusted value

	test	fbsd, SD_COLOR
	jne	eti_8_color3
;
; calc the mono internal move count
;
	mov	ax,dx
	shiftr	ax,3
	mov	int_move_count,ax
;
; calculate the mono internal remaining count
;
	mov	ax,dx
	and	ax,0111b
	mov	int_remaining_pixel_count,ax
	jz	eti_8t1_mono
;
; calculate the mono shift alignment count
;
	sub	ax,8
	neg     ax
	mov	mono_shift_align_count,ax
;
eti_8t1_mono:
	sub	bx,dx
	mov	ext_dword_adjust,bx
	ret
;
eti_8_color3:
;
; calc the color external map's dword alignment value
;
	sub	bx,dx
	mov	ext_dword_adjust,bx	; dword alignment of source
	mov	int_move_count, dx
	mov	int_remaining_pixel_count, 0
;
        ret

eti_8	endp

	page
;--------------------------Private-Routine-----------------------------------;
; eti_24								     ;
;									     ;
;   Bitmap conversion, external	24 bit RGB to internal format		     ;
;									     ;
;   This routine is responsible	for all	preprocessing for converting	     ;
;   from external 24 bit RGB format to our internal formats		     ;
;									     ;
; Entry:								     ;
;	None								     ;
; Returns:								     ;
;	None								     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

        ?_pub   eti_24
eti_24	proc	near
;
; setup the color conversion processing
;
	sub	ax,ax			; flush the starting RGB, IPC = index 0
	mov	wptr LastRGB[0],ax
	mov	wptr LastRGB[2],ax
;
        push    ds
	mov	ax, _DATA
	mov	ds,ax
	assumes ds,Data
	lds	ax,ds:[GetColor_addr]	; fetch the GDI vector
	assumes	ds,nothing
	mov	wptr DeviceColorMatch[0],ax
	mov	wptr DeviceColorMatch[2],ds
	pop	ds

	mov	mono_shift_align_count,0
        mov     num_pels_per_src_byte,1	; For use in huge source case
	mov	bx, bitmap_width	; Number of source pixels per scan

; Compute the number of	source pixels to convert.
; Each becomes one bit in the destination
        mov     cx, 3			; 3 source bytes per pixel
	mov	ax, bx			; Number of source pixels per scan
	shr	ax, cl			; Divide by 8 (pels per dest byte)
	mov	int_move_count, ax	; Integral number of dest bytes per scan

; Compute number of source bytes per scan
; (each source scan starts on a doubleword boundary).
	mov	ax,bx			; Number of source pixels per scan
	mul	cx			; Times 3 bytes per source pixel
	push	ax			; Save the ls word
	add	ax, cx			; Round up to a double word
	adc	dx, 0
	and	al, 11111100b
        mov     scan_length.lo, ax      ; Set # bytes of user buffer required
	mov	scan_length.hi, dx
	pop	cx			; Recover the ls word
	sub	ax,cx
	and	ax,3			; Extra bytes for doubleword roundup
	mov	ext_dword_adjust,ax	; Number of source bytes to skip

	test	fbsd, SD_COLOR	; Monochrome destination?
	jz	eti_24_mono	; Yes

eti_24_color:
; 24-bit-per-pixel source, one byte per pixel (color) destination

	mov	ax, DIMapSegOFFSET copy_e24i8
	mov	full_byte_proc, ax
	mov	ax, DIMapSegOFFSET copy_e24i8_partial
	mov	partial_byte_proc, ax
@@:
	xor	ax,ax
	mov	int_remaining_pixel_count, ax
	mov	int_move_count, bx	; Number of dest bytes per scan
	jmp	eti_24tx

eti_24_mono:
; 24-bit-per-pixel source, one bit per pixel (mono) destination

	mov	ax, DIMapSegOFFSET copy_e24i1
	mov	full_byte_proc, ax
	mov	ax, DIMapSegOFFSET copy_e24i1_partial
	mov	partial_byte_proc, ax

; Compute the number of	source pixels to convert.
; Each becomes one bit in the destination
        mov     cx, 3			; 3 source bytes per pixel
	mov	ax, bx			; Number of source pixels per scan
	shr	ax, cl			; Divide by 8 (pels per dest byte)
	mov	int_move_count, ax	; Integral number of dest bytes per scan

; Compute number of bit pels to output to the last dest byte
        and     bx, 00000111b           ; Can have up to 7 bits in the last
	mov	int_remaining_pixel_count, bx  ; byte to convert
	jz	eti_24tx
	sub	bx, 8
	neg	bx			  ; shift the last byte
	mov	mono_shift_align_count,bx ; align for internal 1 bit/pixel mode

eti_24tx:
	ret

eti_24	endp

	page
;--------------------------Private-Routine-----------------------------------;
; create_color_table							     ;
;									     ;
;   The	color table for	translating from user colors to	our colors	     ;
;   is generated							     ;
;									     ;
; Entry:								     ;
;	ES:DI --> where	color table is					     ;
;	CX    =	  total	number of color	table entries			     ;
; Returns:								     ;
;	None								     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

	?_pub create_color_table
create_color_table proc	near
	push	es
	push	ds
	push	si
	push	di

	mov	ax, es			; get color segment into ds
	mov	ds, ax
	mov	si, di			; get color offset into	si

	mov	ax, ss			; get stack segment into es
	mov	es, ax
	lea	di, color_xlate
	mov	bl, [total_depth_bytes]	; zero if converting to mono

	; check if we're using palette translation
	cmp	[use_palette_trans],0
	jz	colour_table_nopalette

	; if we do, then the colour table we've been given contains two-byte
	; indices rather than RGBQUADs, which we simply need to copy
	test	bl,bl
	jnz	@F
	; in the mono case, it's as simple as can be
	rep	movsw
	jmp	short colour_table_done
	; in the colour case, we need to include an upper word for each one...
@@:	mov	ax,0FF00h	; indicate a palette index in the upper word
@@:	movsw
	stosw
	loop	@B
	jmp	short colour_table_done

colour_table_nopalette:
	; BL needs to contain the number of bits we want out, which is 32
	; for the colour case, or 16 for the mono case, and in the latter
	; case we set the flag (i.e. the LSB) saying we only want 0 or FFFF
	test	bl,bl
	mov	bl,20h	; 32 bits
	jnz	@F
	mov	bl,11h	; 16 bits w/ mono flag
@@:
	mov	bh,11b	; RGBQUAD --> 4 bytes input, need to swap red and blue
	call	rgb_to_ipc_seq
colour_table_done:
	pop	di
	pop	si
        pop     ds
	pop	es

	ret

create_color_table endp

page
;--------------------------Private-Routine-----------------------------------;
; copy_e1i1								    ;
;									     ;
;   copy external 1 to internal	1					     ;
;									     ;
;   The	source is copied to the	destination, with color	conversion	     ;
;   via	the passed color table taking place				     ;
;									     ;
;   It is the caller's responsibility to handle all segment crossings.       ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of destination	bytes to xlate			     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

copy_e1i1_table LABEL	WORD
	dw	OFFSET	    copy_e1i1_zeroed
	dw	OFFSET	    copy_e1i1_inverted
	dw	OFFSET	    copy_e1i1_normal
	dw	OFFSET	    copy_e1i1_oned

        ?_pub   copy_e1i1
copy_e1i1	proc near

	lea	bx	,color_xlate
	mov	al	,ss:[bx]
	mov	ah	,ss:[bx + 2]
	and	ax	,0101H
	shl	ax	,1
	shl	ah	,1
	or	al	,ah
	mov	bx	,ax
	sub	bh	,bh
	mov	bx	,cs:copy_e1i1_table[bx]
	jmp	bx

copy_e1i1_normal:
	rep	movsb
	ret

copy_e1i1_inverted:
	lodsb
	not	al
	stosb
	loop	copy_e1i1_inverted
	ret

copy_e1i1_zeroed:
	add	si	,cx
	sub	al	,al
	rep	stosb
	ret

copy_e1i1_oned:
	add	si	,cx
	mov	al	,0FFH
	rep	stosb
	ret

copy_e1i1	endp

page
;--------------------------Private-Routine-----------------------------------;
; copy_e1i1_partial							     ;
;									     ;
;   copy external 1 to internal	1					     ;
;									     ;
;   A source is	copied into an internal	mono bitmap.			     ;
;									     ;
;   This code handles crossing the segment boundary			     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	BX     =  mask and alignment control				     ;
;	CX     =  number of destination	pixels to accumulate		     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

copy_e1i1_partial_table LABEL	WORD
	dw	OFFSET	    copy_e1i1_partial_zeroed
	dw	OFFSET	    copy_e1i1_partial_inverted
	dw	OFFSET	    copy_e1i1_partial_normal
	dw	OFFSET	    copy_e1i1_partial_oned

copy_e1i1_partial proc near

	lea	bx	,color_xlate
	mov	al	,ss:[bx]
	mov	ah	,ss:[bx + 2]
	and	ax	,0101H
	shl	ax	,1
	shl	ah	,1
	or	al	,ah
	mov	bx	,ax
	sub	bh	,bh
	mov	bx	,cs:copy_e1i1_partial_table[bx]
	jmp	bx

copy_e1i1_partial_normal:
	movsb
        dec     si
        jmp     load_with_seg_check     ; updating the selector if needed

copy_e1i1_partial_inverted:
	lodsb
	dec	si
	not	al
	stosb
	jmp	load_with_seg_check	; updating the selector if needed

copy_e1i1_partial_zeroed:
	sub	al	,al
	stosb
	jmp	load_with_seg_check	; updating the selector if needed

copy_e1i1_partial_oned:
	mov	al	,0FFH
	stosb
	jmp	load_with_seg_check	; updating the selector if needed

copy_e1i1_partial endp

page
;--------------------------Private-Routine-----------------------------------;
; copy_e4i1								     ;
;									     ;
;   copy external 4 bit	packed pixel to	internal 1 plane		     ;
;									     ;
;   The	source is copied to the	destination, with color	conversion	     ;
;   via	the passed color table taking place				     ;
;									     ;
;   It is the caller's responsibility to handle all segment crossings.       ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of destination	bytes to xlate			     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

        ?_pub   copy_e4i1
copy_e4i1	proc near
	lea	bx, color_xlate

ce4i1_next_store:
	mov	dl, 4			; Four source bytes per	dest byte

ce4i1_next_fetch:
	lodsb				; Get 2	pels of	source data
	mov	ah, al
  REPT 2
	rotl	ax, 4
	and	al, 0Fh
	rol	al, 1
	or	al, 1			; (use flags byte)
	xlat	ss:[bx] 		; the actual colors to use are
	shr	al, 1			;    either 0 or 1
	rcl	dh, 1			; accumulate result pel
  ENDM
	dec	dl
	jnz	ce4i1_next_fetch	; complete a byte for the target

	mov	al, dh
	stosb				; save abyte for the target
	loop	ce4i1_next_store
	ret

copy_e4i1	endp

page
;--------------------------Private-Routine-----------------------------------;
; copy_e4i1_partial							     ;
;									     ;
;   copy external 4 bit	packed pixel to	internal 1 plane, partial byte	     ;
;									     ;
;   The	source is copied to the	destination, with color	conversion	     ;
;   via	the passed color table taking place				     ;
;									     ;
;   This code handles crossing the segment boundary			     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CL     =  number of destination	bits to	accumulate		     ;
;	BX     =  mask and alignment control				     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

copy_e4i1_partial proc near

	push	bx
	lea	bx, color_xlate

ce4i1p_fetch:

	call	load_with_seg_check
	mov	ah, al

	shiftr	al, 3
	or	al, 1
	xlat	ss:[bx]
	shr	al, 1
	rcl	ch, 1

	dec	cl
	jz	ce4i1p_store

	mov	al, ah
	and	al, 00001111b
	shl	al, 1
	or	al, 1
	xlat	ss:[bx]
	shr	al, 1
	rcl	ch, 1
	dec	cl
	jnz	ce4i1p_fetch

ce4i1p_store:
	mov	al, ch
	pop	bx
	call	align_and_store
	ret

copy_e4i1_partial endp
page
;--------------------------Private-Routine-----------------------------------;
; copy_e8i1								     ;
;									     ;
;   copy external 8 bit	packed pixel to	internal 1 plane		     ;
;									     ;
;   The	source is copied to the	destination, with color	conversion	     ;
;   onversion via the passed color table taking	place			     ;
;									     ;
;   It is the caller's responsibility to handle all segment crossings.       ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of destination	bytes to xlate			     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

        ?_pub   copy_e8i1
copy_e8i1	proc near

ce8i1_store:
	mov	dh, 8			; Eight	source bytes per dest byte

ce8i1_fetch:
	lodsb
	mov	ah, 80h
	rol	ax, 1
	lea	bx, color_xlate
	add	bx, ax
	mov	al, ss:[bx]
	shr	al, 1
	rcl	dl, 1
	dec	dh
	jnz	ce8i1_fetch

	mov	al, dl
	stosb
	loop	ce8i1_store

	ret

copy_e8i1	endp

page
;--------------------------Private-Routine-----------------------------------;
; copy_e8i1_partial							     ;
;									     ;
;   copy external 8 bit	packed pixel to	internal 1 plane, partial byte	     ;
;									     ;
;   The	source is copied to destination, with color conversion		     ;
;   via	the passed color table taking place				     ;
;									     ;
;   This code handles crossing the segment boundary			     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CL     =  number of destination	bits to	accumulate		     ;
;	BX     =  mask and alignment control				     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

copy_e8i1_partial proc near

	push	bx

ce8i1p_fetch:
	call	load_with_seg_check
	mov	ah, 80h
	rol	ax, 1
	lea	bx, color_xlate
	add	bx, ax
	mov	al, ss:[bx]
	shr	al, 1
	rcl	ch, 1
	dec	cl
	jnz	ce8i1p_fetch

	mov	al, ch
	pop	bx
	call	align_and_store
	ret

copy_e8i1_partial endp
page
;--------------------------Private-Routine-----------------------------------;
; copy_e24i1								     ;
;									     ;
;   copy external 24 bit RGB to	internal 1 plane			     ;
;									     ;
;   The	source is copied to the	destination, with the RGB triplet	     ;
;   being converted into black/white.					     ;
;									     ;
;   It is the caller's responsibility to handle all segment crossings.       ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of destination	bytes to xlate			     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

        ?_pub   copy_e24i1
copy_e24i1	proc near

ce24i1_store:
	mov	bh, 8			; 8 pels/byte output

ce24i1_fetch:
;
; take the RGB & convert it into an index
;
        lodsw
	mov	dl, [si]
	inc	si
;
; if already done, skip the conversion
;
        cmp     ax,wptr LastRGB[0]
	jnz	ce24i1convertit
	cmp	dl,bptr LastRGB[2]
	jz	ce24i1skipit
;
ce24i1convertit:
	mov	wptr LastRGB[0],ax
	mov	bptr LastRGB[2],dl
	xor	dh,dh
;
        push    cx
        push    bx
	push	es
;
	cmp	wptr lpColorInfo[2],0
	jz	@F
;
        push    dx
	push	ax
	push	wptr lpColorInfo[2]
	push	wptr lpColorInfo[0]
	; still need to use this GDI one for the monochrome case...
        call    DeviceColorMatch
	jmp	ce24i1converted
@@:
	xor	dh,dh
	xchg	al,dl			; swap red/blue
	call	sum_RGB_alt_far
	or	ax,dx			; collapse it into one byte for
	or	al,ah			; the simple zero-check code below
;
ce24i1converted:
        pop     es
	pop	bx
	pop	cx
;
	mov	bptr LastRGB[3],al
;
ce24i1skipit:
	mov	al,bptr LastRGB[3]
;
; take the index & convert it into a single bit, then store it in a byte
;
        cmp     al, 1                   ; carry set if al 0
	rcl	bl, 1
	dec	bh
	jnz	ce24i1_fetch
;
; store the byte in the map
;
        mov     al, bl
	not	al
	stosb
	loop	ce24i1_store
	ret

copy_e24i1	endp

page
;--------------------------Private-Routine-----------------------------------;
; copy_e24i1_partial							     ;
;									     ;
;   copy external 24 bit RGB to	internal 1 plane, partial byte		     ;
;									     ;
;   The	source is copied to the	destination, with color	conversion	     ;
;   via	the actual RGB triplet.						     ;
;									     ;
;   This code handles crossing the segment boundary			     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CL     =  number of destination	bits to	accumulate		     ;
;	BX     =  mask and alignment control				     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

copy_e24i1_partial proc	near
	push	bx

ce24i1p_next_byte:
	cmp	si, 0FFFDh		; test for segment end (need 3 bytes)
	jae	ce24i1p_next_seg
	lodsw
	mov	dl, [si]
	inc	si

ce24i1p_have_source:
;
; if already done, skip the conversion
;
        cmp     ax,wptr LastRGB[0]
	jnz	ce24i1pconvertit
	cmp	dl,bptr LastRGB[2]
	jz	ce24i1pskipit
;
ce24i1pconvertit:
	mov	wptr LastRGB[0],ax
	mov	bptr LastRGB[2],dl
	xor	dh,dh
;
; convert the RGB to an index
;
        push    cx
	push	bx
	push	es

	cmp	wptr lpColorInfo[2],0
	jz	@F
;
	push	dx
	push	ax
	push	wptr lpColorInfo[2]
	push	wptr lpColorInfo[0]
	; still need to use this GDI one for the monochrome case...
        call    DeviceColorMatch        ; get the color for this pel
	jmp	ce24i1pconverted
@@:
	xor	dh,dh
	xchg	al,dl			; swap red/blue
	call	sum_RGB_alt_far
	or	ax,dx			; collapse it into one byte for
	or	al,ah			; the simple zero-check code below
;
ce24i1pconverted:
        pop     es
        pop     bx
	pop	cx
;
	mov	bptr LastRGB[3],al
;
ce24i1pskipit:
	mov	al,bptr LastRGB[3]
;
	cmp	al, 1			; make it a single bit
	rcl	ch, 1
	dec	cl
	jnz	ce24i1p_next_byte	; process all the left over pels

ce24i1p_save_byte:
	mov	al, ch
	not	al
	pop	bx
        call    align_and_store
	ret

ce24i1p_next_seg:
	call	load_with_seg_check	; load a byte with segment test
	xchg	al, dl
	call	load_with_seg_check	; load the next	byte
	xchg	al, dh
	call	load_with_seg_check	; the last 8 of 24 bits
	xchg	dx, ax
	jmp	ce24i1p_have_source

copy_e24i1_partial endp

;============================================================================;
page
;--------------------------Private-Routine-----------------------------------;
; copy_e1i8								     ;
;									     ;
;   copy external 1 to internal	4					     ;
;									     ;
;   The	source is copied to all	four planes of the destination,	with	     ;
;   color conversion via the passed color table	taking place.		     ;
;									     ;
;   It is the caller's responsibility to handle all segment crossings.       ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of destination	bytes to xlate			     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

        ?_pub   copy_e1i8
copy_e1i8	proc near

	; at this point, "color_xlate" points at the physical background colour
	; and "color_xlate+4" points at the physical foreground colour
	mov	ax, color_xlate[0].lo
	mov	dx, color_xlate[0].hi
	; get fg XOR bg
	xor	ax, color_xlate[4].lo
	xor	dx, color_xlate[4].hi
	; and stash it at "color_xlate+8" since we have plenty of room
	mov	color_xlate[8].lo, ax
	mov	color_xlate[8].hi, dx

	; use both nibbles of BL as counters
	mov	bl, [total_depth_bytes]
	shl	bl, 4	; upper nibble

ce1i8_next_byte:
	or	bl, 8	; lower nibble
	lodsb
	mov	bh, al

; Note:	this could be made more efficient (fewer insts, no stack spillage)
;       with 386 registers - should look into making it modal
ce1i8_next_pixel:
	shl	bh, 1
	sbb	ax, ax
	cwd
	and	ax, color_xlate[8].lo	;if 1 select fg XOR bg
	xor	ax, color_xlate[0].lo	;if 0 select bg
	cmp	bl, 20h			;byte counter (upper nibble) >= 2?
	jnb	@F
	stosb
	jmp	ce1i8_dec_counter
@@:	stosw
	cmp	bl, 30h
	jb	ce1i8_dec_counter
	mov	ax, dx			;saved by CWD above
	and	ax, color_xlate[8].hi
	xor	ax, color_xlate[0].hi
	cmp	bl, 40h			;byte counter (upper nibble) >= 4?
	jnb	@F
	stosb
	jmp	ce1i8_dec_counter
@@:	stosw
ce1i8_dec_counter:
	dec	bl
	test	bl, 0Fh			;is lower nibble zero?
	jnz	ce1i8_next_pixel

	loop	ce1i8_next_byte

	ret

copy_e1i8	endp
page

;--------------------------Private-Routine-----------------------------------;
; copy_e1i8_partial							     ;
;									     ;
;   copy external 1 to internal	4					     ;
;									     ;
;   The	source is copied to all	four planes of the destination,	with	     ;
;   color conversion via the passed color table	taking place.		     ;
;									     ;
;   This routine will handle crossing a	segment	boundry			     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of destination	pixels to xlate			     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

copy_e1i8_partial proc near

	; at this point, "color_xlate" points at the physical background colour
	; and "color_xlate+4" points at the physical foreground colour
	mov	ax, color_xlate[0].lo
	mov	dx, color_xlate[0].hi
	; get fg XOR bg
	xor	ax, color_xlate[4].lo
	xor	dx, color_xlate[4].hi
	; and stash it at "color_xlate+8" since we have plenty of room
	mov	color_xlate[8].lo, ax
	mov	color_xlate[8].hi, dx

	mov	bl, [total_depth_bytes]
	lodsb
	mov	bh, al

ce1i8p_next_pixel:
	shl	bh, 1
	sbb	ax, ax
	cwd
	and	ax, color_xlate[8].lo	;if 1 select fg XOR bg
	xor	ax, color_xlate[0].lo	;if 0 select bg
	cmp	bl, 2h			;byte counter >= 2?
	jnb	@F
	stosb
	jmp	short e1i8_partial_doloop
@@:	stosw
	ja	@F			;flags are still set by CMP above
	jmp	short e1i8_partial_doloop
@@:	mov	ax, dx			;saved by CWD above
	and	ax, color_xlate[8].hi
	xor	ax, color_xlate[0].hi
	cmp	bl, 4h			;byte counter >= 4?
	jnb	@F
	stosb
	jmp	short e1i8_partial_doloop
@@:	stosw
e1i8_partial_doloop:
	loop	ce1i8p_next_pixel
	dec	si
	jmp	load_with_seg_check

copy_e1i8_partial endp

page

;--------------------------Private-Routine-----------------------------------;
; copy_e4i8								     ;
;									     ;
;   copy external 4 bit	packed pixel to	internal 4 plane		     ;
;									     ;
;   The	source is copied to all	four planes of the destination,	with	     ;
;   color conversion via the passed color table	taking place		     ;
;									     ;
;   It is the caller's responsibility to handle all segment crossings.       ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of destination	bytes to xlate			     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

        ?_pub   copy_e4i8
copy_e4i8	proc near
	lea	bx, color_xlate

ce4i8_next_pixel:
	lodsb
	mov	dh, [total_depth_bytes]
	mov	ah, al
	and	al, 0f0h
	shiftr	al, 2	; AL := first pixel colour index * 4
	mov	dl, al
@@:	xlat	ss:[bx]
	stosb
	inc	dl
	dec	dh
	mov	al,dl
	jnz	@B

	mov	dh, [total_depth_bytes]
	mov	al, ah
	and	al, 0fh
	shiftl	al, 2	; AL := second pixel colour index * 4
	mov	dl, al
@@:	xlat	ss:[bx]
	stosb
	inc	dl
	dec	dh
	mov	al,dl
	jnz	@B

	loop	ce4i8_next_pixel
	ret

copy_e4i8	endp

page
;--------------------------Private-Routine-----------------------------------;
; copy_e4i8_partial							     ;
;									     ;
;   copy external 4 bit	packed pixel to	internal 4 plane, partial byte	     ;
;									     ;
;   The	source is copied to all	four planes of the destination,	with	     ;
;   color conversion via the passed color table	taking place		     ;
;									     ;
;   This code handles crossing the segment boundary			     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CL     =  number of destination	bits to	accumulate		     ;
;;;;;;;	BX     =  mask and alignment control				     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

copy_e4i8_partial proc near

	mov	dh, [total_depth_bytes]
	lea	bx, color_xlate
ce4i8p_next_pixel:
	call	load_with_seg_check	; Get 2	bits of	source data

	mov	ch, dh
	mov	ah, al
	and	al, 0f0h
	shiftr	al, 2	; AL := first pixel colour index * 4
	mov	dl, al
@@:	xlat	ss:[bx]
	stosb
	inc	dl
	dec	ch
	mov	al,dl
	jnz	@B

	dec	cl
	jz	ce4i8p_done

	mov	ch, dh
	mov	al, ah
	and	al, 0fh
	shiftl	al, 2	; AL := second pixel colour index * 4
	mov	dl, al
@@:	xlat	ss:[bx]
	stosb
	inc	dl
	dec	ch
	mov	al,dl
	jnz	@B

	dec	cl
	jne	ce4i8p_next_pixel
ce4i8p_done:
        ret

copy_e4i8_partial endp

page
;--------------------------Private-Routine-----------------------------------;
; copy_e8i8								     ;
;									     ;
;   copy external 8 bit	packed pixel to	internal packed-pixel or direct map  ;
;									     ;
;   The	source is copied to the destination, with colour conversion	     ;
;   via the passed color table taking place				     ;
;									     ;
;   It is the caller's responsibility to handle all segment crossings.       ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of destination	bytes to xlate			     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

	?_pub	copy_e8i8
copy_e8i8	proc near

	push	bp
	mov	dh, [total_depth_bytes]
	lea	bx, color_xlate
ce8i8_next_byte:
	mov	dl, dh	; 1-4 destination bytes per source byte
	mov	bp, bx
	lodsb
	xor	ah, ah
	shl	ax, 2	; four bytes per palette entry
	add	bp, ax
	xchg	bp, si
	shr	dl, 1	; check if we've an odd number of bytes
	jnc	@F
	movs	byte ptr es:[di], ss:[si]
@@:	shr	dl, 1	; check if we've an odd number of words
	jc	@F
	shr	dl, 1	; check if we've to move a dword
	jnc	ce8i8_byte_done
	movs	word ptr es:[di], ss:[si]
@@:	movs	word ptr es:[di], ss:[si]
ce8i8_byte_done:
	xchg	bp, si
	loop	ce8i8_next_byte
	pop	bp
	ret

copy_e8i8	endp

page
;--------------------------Private-Routine-----------------------------------;
; copy_e8i8_partial							     ;
;									     ;
;   copy external 8 bit	packed pixel to	internal 4 plane, partial byte	     ;
;									     ;
;   The	source is copied to all	four planes of the destination,	with	     ;
;   color conversion via the passed color table	taking place		     ;
;									     ;
;   This code handles crossing the segment boundary			     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CL     =  number of destination	bits to	accumulate		     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

	?_pub	copy_e8i8_partial
copy_e8i8_partial proc near

	push	dx
	lea	dx,color_xlate
ce8i8p_next_byte:
	call	load_with_seg_check	; Get 1 pel of source data
	xor	ah, ah
	shl	ax, 2	; four bytes per palette entry
	mov	bx, dx
	add	bx, ax
	xchg	bx, si
	mov	al, [total_depth_bytes]
	shr	al, 1	; check if we've an odd number of bytes
	jnc	@F
	movs	byte ptr es:[di], ss:[si]
@@:	shr	al, 1	; check if we've an odd number of words
	jc	@F
	shr	al, 1	; check if we've to move a dword
	jnc	ce8i8p_byte_done
	movs	word ptr es:[di], ss:[si]
@@:	movs	word ptr es:[di], ss:[si]
ce8i8p_byte_done:
	xchg	bx, si
	dec	cl
	jne	ce8i8p_next_byte
	pop	dx
	ret

copy_e8i8_partial endp

page
;--------------------------Private-Routine-----------------------------------;
; copy_e24i8								     ;
;									     ;
;   copy external 24 bit RGB to	internal one byte per pixel                  ;
;									     ;
;   The	source is copied to all	four planes of the destination,	with	     ;
;   color conversion via the actual RGB	triplet.			     ;
;									     ;
;   It is the caller's responsibility to handle all segment crossings.       ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of destination	bytes to xlate			     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

        ?_pub	copy_e24i8
copy_e24i8	proc near
	; check if we have a colour info table.
	cmp	wptr lpColorInfo[2],0
	jnz	@F

	; if not, we just have a list of RGBTRIPLEs to deal with
	mov	bh,10b	; swap red/blue, only three bytes (not four) per pixel
	mov	bl,[total_depth_bytes]
	shl	bl,3	; convert back to bits
	call	rgb_to_ipc_seq
	ret

@@:	push	es

ce24i8_next_pixel:
;
; take the RGB & convert it into an index
;
        lodsw
	mov	dl, [si]
	inc	si
;
; if already done, skip the conversion
;
        cmp     ax,wptr LastRGB[0]
	jnz	ce24i8convertit
	cmp	dl,bptr LastRGB[2]
	jz	ce24i8skipit
;
ce24i8convertit:
	mov	wptr LastRGB[0],ax
	mov	bptr LastRGB[2],dl
	xor	dh,dh
;
        push    cx
        push    bx
;
	xchg	dl,al			; swap Red/Blue
	push	wptr lpColorInfo[2]
	push	wptr lpColorInfo[0]
        call    OurDeviceColourMatch
	mov	bptr LastRGB[3],al
;
	pop	bx
	pop	cx
;
ce24i8skipit:
	mov	al,bptr LastRGB[3]

;
; store the color
;
        stosb                           ; Save C0
  
	loop	ce24i8_next_pixel	; complete all the target pixels
	pop	es
        ret

copy_e24i8	endp


page
;--------------------------Private-Routine-----------------------------------;
; copy_e24i8_partial								     ;
;									     ;
;   copy external 24 bit RGB to	internal one byte per pixel                  ;
;									     ;
;   The	source is copied to all	four planes of the destination,	with	     ;
;   color conversion via the actual RGB	triplet.			     ;
;									     ;
;   This code handles crossing the segment boundary.                         ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of destination	bytes to xlate			     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

        ?_pub	copy_e24i8_partial
copy_e24i8_partial	proc near
	push	es

ce24i8_next_pixel_p:
;
; take the RGB & convert it into an index
;
;       lodsw			; Byte 0 in al, byte 1 in ah
;	mov	dl, [si]	; Byte 2 in dl
;	inc	si
;
	push	bx
	mov	bl,[total_depth_bytes]

	call load_with_seg_check	; Byte 0 in al
	mov	ah,al			; Byte 0 in ah
	call load_with_seg_check	; Byte 0 in ah, byte 1 in al
	xchg	al,ah			; Byte 1 in ah, byte 0 in al
	push	ax
	call load_with_seg_check	; Byte 2 in al
	mov	dl,al			; Byte 2 in dl
	pop	ax
;
; check if we have a colour info table
;
	cmp	wptr lpColorInfo[2],0
	jnz	ce24i8usetable_p

	; TODO: Add caching here (same as in the DeviceColorMatch case below)
	xor	dh,dh
	xchg	al,dl			; swap red/blue
	call	sum_RGB_alt_far
	test	bl,4	; storing 32 bits?
	jz	@F
	stosw
	mov	ax,dx
	jmp	short ce24i8nextword_p
@@:
	test	bl,2	; storing (at least) 16 bits?
	jz	@F
ce24i8nextword_p:
	stosw
	mov	al,dl
@@:
	test	bl,1	; storing an odd number of bytes?
	jz	@F
	stosb
@@:	jmp	short ce24i8done_p

ce24i8usetable_p:
;
; if already done, skip the conversion
;
        cmp     ax,wptr LastRGB[0]
	jnz	ce24i8convertit_p
	cmp	dl,bptr LastRGB[2]
	jz	ce24i8skipit_p
;
ce24i8convertit_p:
	mov	wptr LastRGB[0],ax
	mov	bptr LastRGB[2],dl
	xor	dh,dh
;
        push    cx
        push    bx
;
	xchg	dl,al			; swap Red/Blue
	push	wptr lpColorInfo[2]
	push	wptr lpColorInfo[0]
        call    OurDeviceColourMatch
	mov	bptr LastRGB[3],al
;
	pop	bx
	pop	cx
;
ce24i8skipit_p:
	mov	al,bptr LastRGB[3]

;
; store the color
;
        stosb                           ; Save C0

ce24i8done_p:
	loop	ce24i8_next_pixel_p	; complete all the target pixels
	pop	bx
	pop	es
        ret

copy_e24i8_partial	endp

page
;--------------------------Private-Routine-----------------------------------;
;  load_with_seg_check							     ;
;									     ;
;   The	contents of *DS:SI is loaded into AL.  If SI becomes 0,	then	     ;
;   the	next destination selector (if it exists) will be loaded.	     ;
;									     ;
; Entry:								     ;
;	DS:SI --> destination						     ;
; Returns:								     ;
;	DS:SI --> next source byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

load_with_seg_check proc near

	lodsb				; Get the byte
; Note:	GLM optimized following	code for most frequent case (890411)
	or	si, si			; In the next segment?
	jz	lwsc_upd8		;   Yes, update	selector
	ret				;   No

lwsc_upd8:
	cmp	scanline_count,1
	ja	lwsc_upd8_1
	cmp	cl,1
        je      @F

lwsc_upd8_1:
	push	ax
	mov	ax, ds			; get current segment
	add	ax, __NEXTSEG		; move on to next segment
	mov	ds, ax
	assumes	ds, nothing
	pop	ax
@@:
	ret

load_with_seg_check endp

page
;--------------------------Private-Routine-----------------------------------;
;  align_and_store							     ;
;									     ;
;   The	given byte is stored into the bitmap, being aligned to the	     ;
;   left hand side of byte						     ;
;									     ;
; Entry:								     ;
;	ES:DI --> destination						     ;
;	AL     =  byte to save						     ;
;	BL     =  shift	count for alignment				     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

align_and_store	proc near

	xchg	bx, cx
	shl	al, cl			; Perform any needed alignment
	stosb
	xchg	bx, cx
	ret

align_and_store	endp


sEnd    DIMapSeg
end

