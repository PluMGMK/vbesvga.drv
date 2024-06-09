page	,132
;----------------------------------------------------------------------------;
;			 GetDeviceBitmapBits (ITE)			     ;
;			 -------------------				     ;
;   Converts device VGA dependent bitmap format into a device independent    ;
;   bitmap format							     ;
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
;     .	Adapted	for Windows-286	by Amit	Chatterjee [amitc]  on 07-Oct-1988   ;
;									     ;
;     .	Modified to suite 4 plane EGA/VGA drivers  for Windows 286/386	     ;
;				by Amit	Chatterjee [amitc]  on 30-Nov-1988   ;
;									     ;
; Last Modified	-by-  Amit Chatterjee [amitc]	  30-Nov-1988  14:22:00	     ;
;									     ;
;     .	Modified to work in VRAM's 256 color modes by Irene Wu, Video 7, 2/89;
;----------------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.

.286
SD_COLOR                equ     01000000b
SD_HUGE			equ	00100000b
CAN_CROSS_SEG		equ	00010000b

MONO_BIT		equ	00000001b

	.xlist
	include	cmacros.inc
	include	gdidefs.inc
	include	lines.inc
	include	macros.mac
	.list

	externA		__NEXTSEG		; offset to next segment
	externFP	ipc_to_rgb_seq		; in RGB2IPC.ASM


sBegin Data
	externD 	GetColor_addr		; DeviceColorMatch vector
sEnd


createSeg _DIMAPS,DIMapSeg,word,public,CODE
sBegin	DIMapSeg
	assumes	cs, DIMapSeg

	externNP    do_bitmap_computations	; in bmc_eti.asm

;----------------------------------------------------------------------------;
; The following	table contains the addresses of	the initialization routines  ;
; for each of the 4 Device Independent Bitmap formats.			     ;
;----------------------------------------------------------------------------;

anpfnPreProc	label	word
	dw	ite_1
	dw	ite_4
	dw	ite_8
	dw	ite_24

	assumes	ds, nothing
	assumes	es, nothing

cProc	frame,<FAR,WIN,PASCAL>,<ds,si,di,es>
	include	bmc_main.var
cBegin	<nogen>
cEnd	<nogen>

	public	GetDeviceBitmapBits
GetDeviceBitmapBits	proc	near

WriteAux <'bmc_ite'>			; *****	DEBUG *****
IFDEF DEBUG
%OUT take this out!!!
int 1
ENDIF

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
	jmp	ite_exit		; get out

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
;	.   decided whether the	internal map is	huge or	small
;	.   did	the preprocessor
;	.   sets carry flag if no copy is to be	done
;	.   sets the carry flag	if copy	is to be done and in DX:AX
;	    returns the	start pointer in the internal map

	jnc	ite_copy_needed		; test for error
	jmp	ite_xfered_all		; no copy necessary
ite_copy_needed:
	mov	ds, dx
	assumes	ds, nothing
	mov	si, ax			; set DS:SI point to internal map

; DS:SI	now points to the starting position in source (device dependent) map

	les	di, lp_bits_ext		; target is user's buffer
	assumes	es, nothing

;----------------------------------------------------------------------------;
; A point to remember. The sorce of the	transfer is just an array of bits in ;
; the specified	format.	It is not a complete bitmap, but just a	portion	that ;
; is to	be copied. We, thus, do	not have to do any further calculations	for  ;
; obtaining the	starting address in the	source buffer, it is the passed	long ;
; pointer. Also	note that the user buffer may arbitarily cross a segment     ;
; boundary (even a single scan line could span the boundary). However even in;
; source the scan lines	will be	alligned to a DWORD (they could	still cross a;
; segment if the bytes per scan	is large enough).			     ;
;----------------------------------------------------------------------------;

; test to see whether users buffer cross a segment or not, if it does special
; code will be needed.

	mov	cx, scanline_count	; no of	scans to copy
	mov	ax, scan_length.hi	; do full 32 bit multiplication
	mul	cx			; multiply the HIWORD

; assuming that	scan_lenght.hi is not so large to overflow result into DX

	xchg	ax, bx			; save in bx
	mov	ax, scan_length.lo	; LOWORD multiplication
	mul	cx
; BX has the HIWORD mul	result

	add	dx, bx			; DX:AX	= total	bytes of buffer	needed

; DI has the start offset to the user's buffer

	add	ax, di
	adc	dx, 0			; DX:AX	= last address + 1
	jz	ite_in_segment		; Won't cross a segment boundary
	or	fbsd, CAN_CROSS_SEG	; Can cross a segment boundary

ite_next_scan:
	test	fbsd, CAN_CROSS_SEG	; If buffer might cross	a segment
	jnz	ite_might_cross_seg	; then go check	it out

ite_in_segment:
	push	si			; Save bitmap scan start address
	mov	cx, int_move_count	; Set translation procedure loop count
	jcxz	ite_see_about_partial	; No full bytes!
	call	full_byte_proc		; Process all complete bytes

ite_see_about_partial:
	mov	cx, int_remaining_pixel_count  ;Process any partial byte
	jcxz	ite_no_partial_byte
	call	partial_byte_proc

ite_no_partial_byte:
	pop	si
	dec	scanline_count
	jz	ite_xfered_all		; Transfered all scans

; we pointer for the own bitmap	starts at the bottom and then goes up

	sub	si, int_aligned_width		;--> previous bitmap scanline
	add	di, ext_dword_adjust	   ;Align to dword boundary
	jnc	ite_chk_segment_update	;don't update segment if no wrap
	mov	ax, es			; otherwise, increment segment
	add	ax, __NEXTSEG
	mov	es, ax
	assumes	es, nothing

ite_chk_segment_update:
	test	fbsd, SD_HUGE		; If not a huge	bitmap,
	jz	ite_next_scan		; go do	next scanline

	dec	huge_scans_left		; Any more scans in this segment?
	jnz	ite_next_scan		; yes, don't update bitmap pointer
	mov	ax, ds
	sub	ax, __NEXTSEG		; go to	the previous segment
	mov	ds, ax
	assumes	ds, nothing

	mov	si, prev_offset		; start	from the bottom	of the segment
	mov	ax, scans_per_seg
	mov	huge_scans_left, ax	; This many scans in the segment
	jmp	ite_next_scan

ite_might_cross_seg:
;
; The buffer will cross a segment boundary.  If this scanline will
; cross the segment, then we'll process eight bits of bitmap data
; at a time.  !!! someday we may improve upon this, but we don't
; expect this to be critical !!!
;
	mov	ax, di			;If the	entire scan shows, then
	xor	dx, dx			;  we can use the normal code
	add	ax, scan_length.lo
	adc	dx, scan_length.hi	;scan_length may be > 64K
	jz	ite_in_segment		;It won't cross a segment boundary

;	The scan will cross a segment boundary.	  We'll take the easy
;	way out	and do the entire scanline one bitmap byte at a	time.

	push	si			;Save bitmap scan start	address
	mov	cx, int_move_count	;If only a last byte exists,
	jcxz	ite_see_about_partial	;  use the normal code
	mov	some_temp, cx		;Save full byte	count

ite_looking_to_cross:
	mov	cl, num_pels_per_src_byte ; process one byte of source
	call	partial_byte_proc
	dec	some_temp
	jnz	ite_looking_to_cross
	jmp	ite_see_about_partial	;Finish	with partial byte code

ite_xfered_all:
	mov	ax, scans_copied	;Return	number of scans	copied
	xor	dx, dx

ite_exit:
	cwd
	ret

GetDeviceBitmapBits	endp

;----------------------------------------------------------------------------;
;comment ~
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
; 1 or 4 bits from the source will be mapped into 1 bit	(for each plane) in
; the target, and we know that the no of bits in the source are	a multiple of
; 32 (including	the filler bits). As 32/4 = 8, so if we	converts all the bits
; we will always have an integral number of bytes in the destination. Also
; since	we shall be converting all the bits, we	will not have to skip over
; the filler bits in the source	buffer to move ober to the next	scan line.
;
; Consider the 8 bits per pel format:
;
; 8 bits from the source will be converted into	one bit	in the target, and
; the source scan has a	multiple of 32 bits. Here again	we will	try to
; convert the whole of the source scan line including the filler bits, thus
; here again at	the end	of the copy of one scan	line, the source pointer will
; not have to be advanced over the filler  bytes. However, 32/8	is 4, and
; hence	if the length of the source scan line is an odd	multiple of a DWORD
; size,	then we	will have an incomplete	byte at	the end	for the	destination.
;
; How do we generate the target	bits ? we process them a byte at a time. We
; extract the required number of source	bits, convert them into	one
; destination bit (based on the	color mapping) and start building a target
; byte by stuffing it into a byte variable from	the right. Once	8 target
; bits have been compiled we store the target byte.
;
; With this approch, for the 8 bits/pel	case, if we do have a leftover nibble,
; it will be at	the right end of the work byte.	Thus it	has to be alligned
; against the left end and then	stored.	So we will also	prepare	an allignment
; mask for this	case.
;
; Finally consider the 24 bits/pel case. Here the 24 bits to a pel themselves
; give the color value and we will always process the source 24	bits at	a
; time.	However	as 32 is not a multiple	of 24, we cannot always	include	the
; filler bits in the conversion. So in this case the source pointer will have
; to be	carried	over the filler	bytes and we will calculate the	number of
; bytes	of adjustment required.
;
; In the last case 24 bits get mapped into 1 target bit	so for the target we
; may then get an incomplete byte again, which has to be correctly alligned
; before storing.
;
; We will thus calculate the following parameters for each of the formats:
;
;	int_move_count	   ----  the number of complete bytes for target
;	int_remaining_pixel_count ----	the last few source pels which do not
;					yield a complete target byte.
;	scan_length	   ----	 no of bytes for source	which yield the	above
;	allignment	   ----  no of positions by which the incomplete last
;				 target	byte is	to be shifted before storing
;	ext_dword_adjust   ----  no of bytes to be added to the the source
;				 ptr at	the end	of the copy to move over to
;				 the start of the next scan line in src	buf
;
; Let's see how we calculate these values:
;
; 1 bit	per pel:
; ---------------
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
;	n*4  -----		     n00      (shiftl n,2)
;   add	31		    +	   11111
;   AND	NOT(31)		    &	..100000
;   divide by 8*4		shift right by 5 bits
;
; This is equivelent to:
;
;				    n
;			    +	  111	(add n,7)
;			shift right 5 3	bits
;
; The above result will be int_move_count, and this multiplied by 4
; will give scan_length.
;
; Here again we	will not have partial bytes neither any	source buffer
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
;			 shiftr  ax,3	 -- int_move_count
;	    to get the no of bytes in source we	will have to AND NOT(31)
;	    and	divide by 8, but since last 3 bits are always zero, so
;			 and	 bl,0f4h -- scan_length	in bx
;
; also note since we pack 8 bits into 1	bit, the remainder on division by
; 64 gives the last few	bits whcich can't be packed into a byte, then divided
; by 8 gives the last few pels that cant be packed in a	byte.
; This can be obtained simply by ANDind	BX with	4 and note that	the result
; will be 0 or 4 (as at	best one nibble	can be left over) and if it is 4,
; then that is also the	alignment factor.
;
; 24 bits per pel:
; ----------------
;
; Here we will not be converting any of	the filler bits. So if n is the	number
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
; ite_1									     ;
;									     ;
;   Bitmap conversion, internal	format to external 1 bit		     ;
;									     ;
;   This routine is responsible	for all	preprocessing for converting	     ;
;   from our internal formats to external 1 bit	format			     ;
;									     ;
; Entry:								     ;
;	ES:DI --> where	color table would go				     ;
; Returns:								     ;
;	None								     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

ite_1	proc	near

        xor     ax, ax
	mov	ext_dword_adjust, ax	      ; Everything will be dword aligned
	mov	int_remaining_pixel_count, ax ; Will never have a partial byte
	mov	scan_length.hi, ax	      ;Max dest scan size is < 64K
	mov	num_pels_per_src_byte,8


        mov     ax, DIMapSegOFFSET copy_i8e1 ;Color bitmap
	mov	bx, DIMapSegOFFSET copy_i8e1_partial
	mov	cx	,256

        test    fbsd, SD_COLOR          ;Monochrome source?
	jnz	ite_1_have_proc 	;  No

        mov     ax, DIMapSegOFFSET copy_i1e1 ;Assume monochrome bitmap
	mov	bx, DIMapSegOFFSET copy_i1e1_partial
	mov	cx	,256

ite_1_have_proc:
	mov	full_byte_proc, ax
	mov	partial_byte_proc, bx
	call	move_color_table

; Whenever we allocated a scanline (or each scan of a color
; bitmap), we allocated to a dword boundary.  If we just
; translate for the width of the scan in bytes, the required
; dword alignment will be maintained.
; independent map is alligned on DWORDS	and own	map on WORDS
; so may have left over bytes at the end of

	mov	ax, bitmap_width	; get no of pels
	mov	dx,ax
        mov     cx, 31
	add	ax, cx			; try to allign	to dword
	not	cx
	and	ax, cx			; ax is	alligned to dwords
	mov	bx,ax
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
;
; calculate the external dword adjustment
;
	sub	bx,bitmap_width
	shiftr	bx,3
	mov	ext_dword_adjust,bx
;
	ret

ite_1	endp

page
;--------------------------Private-Routine-----------------------------------;
; ite_4									     ;
;									     ;
;   Bitmap conversion, internal	format to external 4 bit		     ;
;									     ;
;   This routine is responsible	for all	preprocessing for converting	     ;
;   from our internal formats to external 4 bit	format			     ;
;									     ;
; Entry:								     ;
;									     ;
; Returns:                                                                   ;
;	None								     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

public	ite_4
ite_4	proc	near

	xor	ax, ax
	mov	ext_dword_adjust, ax	;Everything will be dword aligned
	mov	int_remaining_pixel_count, ax  ;Will never have a partial byte
	mov	scan_length.hi, ax	;Max dest scan size is < 64K
	mov	num_pels_per_src_byte,8


        mov     ax, DIMapSegOFFSET copy_i8e4
	mov	bx, DIMapSegOFFSET copy_i8e4_partial
	mov	cx	,256

        test    fbsd, SD_COLOR          ;Monochrome source?
	jnz	ite_4_not_mono		;Not mono, must	be color

        mov     ax, DIMapSegOFFSET copy_i1e4
	mov	bx, DIMapSegOFFSET copy_i1e4_partial
	mov	cx	,256

ite_4_not_mono:
	mov	full_byte_proc, ax
	mov	partial_byte_proc, bx	;Might need this for seg boundaries
        call    move_color_table

	mov	ax, bitmap_width	; Compute the number of	source bytes
	add	ax, 7			; We can force dword alignment by
	shr	ax, 1			; always xlating a multiple of 8 bits
	and	ax, 0fffch
	mov	scan_length.lo, ax	; Set #	bytes of user buffer required

	mov	bx, int_aligned_width	; Moving all bytes of the scan

	test	fbsd, SD_COLOR
	jne	ite_4_color3
	mov	int_move_count, bx
	mov	num_pels_per_src_byte,8
        ret

ite_4_color3:
	mov	ax, bitmap_width
	shiftr	ax, 3
	mov	int_move_count, ax
	shiftl	ax, 3
	sub	bx, ax			; must be multiple of 2
	mov	int_remaining_pixel_count, bx
	or	bx, bx
	je	ite_4_colorx
	shr	bx, 1
	sub	bx, 4
	neg	bx
	mov	ext_dword_adjust, bx
ite_4_colorx:
	ret				; for one bitmap scan

ite_4	endp
page

;--------------------------Private-Routine-----------------------------------;
; ite_8									     ;
;									     ;
;   Bitmap conversion, internal	format to external 8 bit		     ;
;									     ;
;   This routine is responsible	for all	preprocessing for converting	     ;
;   from our internal formats to external 8 bit	format			     ;
;									     ;
; Entry:								     ;
;	ES:DI --> where	color table would go				     ;
; Returns:								     ;
;	None								     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

ite_8	proc	near

	xor	ax, ax			;Will not require any buffer adjustment
	mov	ext_dword_adjust, ax
	mov	scan_length.hi, ax	;Max dest scan size is < 64K

	call	move_color_table

        mov     num_pels_per_src_byte,8
	mov	ax, DIMapSegOFFSET copy_i8e8
	mov	bx, DIMapSegOFFSET copy_i8e8_partial
	mov	cx	,256

        test    fbsd, SD_COLOR          ;Monochrome source?
	jnz	ite_8_not_mono		;Not mono, must	be color

        mov     ax, DIMapSegOFFSET copy_i1e8
	mov	bx, DIMapSegOFFSET copy_i1e8_partial
	mov	cx	,256

ite_8_not_mono:
	mov	full_byte_proc, ax
	mov	partial_byte_proc, bx

	mov	ax, bitmap_width	; Compute the number of	source bytes
	add	ax, 3			; to convert.	Each dword becomes
	and	al, 11111100b		; 4 source bytes = 1 dest nibble
	mov	scan_length.lo, ax	; Set #	bytes of user buffer required

	test	fbsd, SD_COLOR
	jne	ite_8_color3
	mov	bx, ax
	shiftr	ax, 3
	mov	int_move_count, ax
	and	bx, 4
	mov	int_remaining_pixel_count, bx
	ret

ite_8_color3:
	mov	ax, bitmap_width	; Moving all bytes of the scan
	shiftr	ax, 3
	mov	int_move_count, ax     ; pixels not enough for 1 byte
	shiftl	ax, 3
	mov	bx, int_aligned_width
	sub	bx, ax
	mov	int_remaining_pixel_count, bx
	neg	bx			; shift	the last byte
	add	bx, 4
	and	bx, 00000011b		; Compute number of bytes to pad with
	mov	ext_dword_adjust, bx
	ret

ite_8	endp

page
;--------------------------Private-Routine-----------------------------------;
; ite_24								     ;
;									     ;
;   Bitmap conversion, internal	format to external 24 bit RGB		     ;
;									     ;
;   This routine is responsible	for all	preprocessing for converting	     ;
;   from our internal formats to external 24 bit RGB format		     ;
;									     ;
; Entry:								     ;
;	ES:DI --> where	color table would go				     ;
; Returns:								     ;
;	None								     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

ite_24	proc	near

	mov	num_pels_per_src_byte,8 ; actually .3, but we want a min of 1

	mov	ax, DIMapSegOFFSET copy_i8e24
	mov	bx, DIMapSegOFFSET copy_i8e24_partial

        test    fbsd, SD_COLOR          ;Monochrome source?
	jnz	ite_24_have_proc	;  No

	mov	ax, DIMapSegOFFSET copy_i1e24
	mov	bx, DIMapSegOFFSET copy_i1e24_partial

ite_24_have_proc:
	mov	full_byte_proc, ax
	mov	partial_byte_proc, bx
	mov	cx, 3
	mov	ax, bitmap_width	;Compute the number of source bytes
	mov	bx, ax			;  to convert.	Each bit becomes
	shr	ax, cl			;  three bytes in the destination
	mov	int_move_count, ax
	mov	ax, bx			;1 source bit =	3 dest bytes
	mul	cx
	add	ax, cx			;Need to round up to a double word
	adc	dx, 0
	and	al, 11111100b
	mov	scan_length.lo, ax	;Set # bytes of	user buffer required
	mov	scan_length.hi, dx
	and	bx, 00000111b		;Can have up to	7 bits in the last
	mov	int_remaining_pixel_count, bx  ;  byte to convert
	and	bl, 00000011b		;Compute number	of bytes to pad	with
	mov	ext_dword_adjust, bx
	ret

ite_24	endp

page
;--------------------------Private-Routine-----------------------------------;
; move_color_table							     ;
;									     ;
;   Move GDI's lpColorInfo table to the stack.                               ;
;									     ;
; Entry:								     ;
;	NONE								     ;
; Returns:								     ;
;	AX,CX destroyed 						     ;
;       No other registers modified                                          ;
;	Direction flag cleared						     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

        ?_pub   move_color_table

move_color_table proc	 near
	push	es
	push	ds
	push	di
	push	si
	pushf

        mov     ax,ss
	mov	es,ax
	lea	di,color_xlate
	lds	si,lpColorInfo

	cld
        mov     cx,100h/2
	rep	movsw

	popf
        pop     si
	pop	di
	pop	ds
	pop	es
	ret

move_color_table endp

page
;--------------------------Private-Routine-----------------------------------;
; copy_i1e1								     ;
;									     ;
;   The	given number of	bytes are copied from source to	destination.	     ;
;									     ;
;   It is the caller's responsibility to handle all segment crossings.       ;
;									     ;
;   This routine is used for:						     ;
;	internal mono to external mono					     ;
;	external mono to internal mono					     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of bytes to copy				     ;
;	Direction flag cleared						     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
;	Direction flag cleared						     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

	public	copy_i1e1

copy_i1e1_table LABEL	WORD
	dw	OFFSET	    copy_i1e1_zeroed
	dw	OFFSET	    copy_i1e1_inverted
	dw	OFFSET	    copy_i1e1_normal
	dw	OFFSET	    copy_i1e1_oned

	?_pub	copy_i1e1
copy_i1e1	proc near

	lea	bx	,color_xlate
	mov	al	,ss:[bx]
	mov	ah	,ss:[bx + 1]
	and	ax	,0101H
	shl	ax	,1
	shl	ah	,1
	or	al	,ah
	mov	bx	,ax
	sub	bh	,bh
	mov	bx	,cs:copy_i1e1_table[bx]
	jmp	bx

copy_i1e1_normal:
	rep	movsb
	ret

copy_i1e1_inverted:
	lodsb
	not	al
	stosb
	loop	copy_i1e1_inverted
	ret

copy_i1e1_zeroed:
	add	si	,cx
	sub	al	,al
	rep	stosb
	ret

copy_i1e1_oned:
	add	si	,cx
	mov	al	,0FFH
	rep	stosb
	ret

copy_i1e1	endp


page
;--------------------------Private-Routine-----------------------------------;
; copy_i1e1_partial                                                          ;
;                                                                            ;
;   A Byte is copied from the source to destination.                         ;
;                                                                            ;
;   This routine will handle the destination (user's buffer) crossing        ;
;   a segment boundary during the translation of the source byte.            ;
;   The source will never cross a segment boundary since it is an            ;
;   internal bitmap and all scans are allocated to fit within a              ;
;   segment.                                                                 ;
;                                                                            ;
;                                                                            ;
; Entry:                                                                     ;
;       DS:SI --> source                                                     ;
;       ES:DI --> destination                                                ;
;       CL     =  number of pixels to translate (Will always be 8)           ;
;       Direction flag cleared                                               ;
; Returns:                                                                   ;
;       ES:DI --> next destination byte                                      ;
;       Direction flag cleared                                               ;
;----------------------------------------------------------------------------;

        assumes ds, nothing
        assumes es, nothing

copy_i1e1_partial_table LABEL	WORD
	dw	OFFSET	    copy_i1e1_partial_zeroed
	dw	OFFSET	    copy_i1e1_partial_inverted
	dw	OFFSET	    copy_i1e1_partial_normal
	dw	OFFSET	    copy_i1e1_partial_oned

copy_i1e1_partial proc near

        lea     bx      ,color_xlate
        mov     al      ,ss:[bx]
	mov	ah	,ss:[bx + 1]
        and     ax      ,0101H
        shl     ax      ,1
        shl     ah      ,1
        or      al      ,ah
        mov     bx      ,ax
        sub     bh      ,bh
	mov	bx	,cs:copy_i1e1_partial_table[bx]
	jmp	bx

copy_i1e1_partial_normal:
        lodsb
	jmp	store_e1_with_seg_check     ; updating the selector if needed

copy_i1e1_partial_inverted:
        lodsb
        not     al
	jmp	store_e1_with_seg_check     ; updating the selector if needed

copy_i1e1_partial_zeroed:
        inc     si
        sub     al      ,al
	jmp	store_e1_with_seg_check     ; updating the selector if needed

copy_i1e1_partial_oned:
        inc     si
        mov     al      ,0FFH
	jmp	store_e1_with_seg_check     ; updating the selector if needed

copy_i1e1_partial endp


store_e1_with_seg_check proc near
	stosb				;Save the byte
	or	di, di			;If in the next segment
	jz	swsc_e1_exit		   ;  then update the selector
	ret
;
swsc_e1_exit:

	cmp	scanline_count,1
	je	@F

	push	ax
	push	dx
	mov	dx, es
	add	dx, __NEXTSEG
	mov	es, dx
	assumes	es, nothing
	pop	dx
	pop	ax

@@:     ret

store_e1_with_seg_check endp



page
;--------------------------Private-Routine-----------------------------------;
; copy_i1e4								     ;
;									     ;
;   copy internal 1 bit	to external 4 bit packed pixel			     ;
;									     ;
;   The	destination is filled with the source data, with each source	     ;
;   bit	expanded to a nibble in	the destination.			     ;
;									     ;
;   It is the caller's responsibility to handle all segment crossings,       ;
;   and	to ensure that there are enough	bytes of destination available	     ;
;   to hold the	data.							     ;
;									     ;
;   This routine is used for:						     ;
;	internal mono to external four-bit packed pixels		     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of bytes to xlate				     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

copy_i1e4	proc	near

	lea	bx,color_xlate
;
ci1e4_next_byte:
	mov	dl,8
        lodsb
	mov	ah,al
;
ci1e4_next_bit:
        sub     al      ,al
	shl	ah,1		; first nibble
	adc	al	,al
	xlat	ss:[bx]
	shiftl	al,4
	mov	dh,al

	dec	dl		; count down...

	sub	al	,al
	shl	ah,1		; first nibble
        adc     al      ,al
        xlat    ss:[bx]
	and	al,0fh
        or      al,dh

	stosb
        dec     dl
	jg	ci1e4_next_bit	; may dec < 0 due to partial byte
	loop	ci1e4_next_byte

        ret

copy_i1e4	endp

page
;--------------------------Private-Routine-----------------------------------;
; copy_i1e4_partial							     ;
;									     ;
;   copy internal 1 bit	to external 4 bit packed pixel,	partial	byte	     ;
;									     ;
;   The	destination is filled with the source data, with each source	     ;
;   bit	expanded to a nibble in	the destination.  This routine handles	     ;
;   partial bytes where	some portion of	the first or last byte needs	     ;
;   to be saved.							     ;
;									     ;
;   This routine will handle the destination (user's buffer) crossing        ;
;   a segment boundary during the translation of the source byte.	     ;
;   The	source will never cross	a segment boundary since it is an	     ;
;   internal bitmap and	all scans are allocated	to fit within a		     ;
;   segment.								     ;
;									     ;
;   Since this routine always writes nibbles, it is guaranteed that	     ;
;   the	shift count passed in is even.					     ;
;									     ;
;   This routine shouldn't be called very often, so a short loop will        ;
;   be sufficient for our needs.					     ;
;									     ;
;   This routine is used for:						     ;
;	internal mono to external four-bit packed pixels		     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CL     =  number of pixels to xlate				     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

public	copy_i1e4
copy_i1e4_partial proc near
	lea	bx,color_xlate
        lodsb
	mov	ah,al
;
ci1e4p_next_bit:
	sub	al	,al
	shl	ah,1		; first nibble
        adc     al      ,al
	xlat	ss:[bx]
	shiftl	al,4
	mov	dh,al

	dec	cl		; count down...

	sub	al	,al
	shl	ah,1		; first nibble
        adc     al      ,al
        xlat    ss:[bx]
	and	al,0fh
        or      al,dh

	cmp	di,-1
	jz	ci1e4p_dest_segx
	stosb
;
ci1e4p_10:
	dec	cl
	jg	ci1e4p_next_bit  ; may dec < 0 due to partial byte
	ret
;
ci1e4p_dest_segx:
	call	store_e4_with_seg_check
	jmp	short ci1e4p_10

copy_i1e4_partial endp


store_e4_with_seg_check proc near
	stosb				;Save the byte
	or	di, di			;If in the next segment
	jz	swsc_e4_exit		   ;  then update the selector
	ret
;
swsc_e4_exit:

	cmp	cl,1
	ja	@F
	cmp	scanline_count,1
	je	swsc_e4_x

@@:	push	ax
	push	dx
	mov	dx, es
	add	dx, __NEXTSEG
	mov	es, dx
	assumes	es, nothing
	pop	dx
	pop	ax

swsc_e4_x:
	ret

store_e4_with_seg_check endp


page
;--------------------------Private-Routine-----------------------------------;
; copy_i1e8								     ;
;									     ;
;   copy internal 1 bit	to external 8 bit packed pixel			     ;
;									     ;
;   The	destination is filled with the source data, with each source	     ;
;   bit	expanded to a byte in the destination.				     ;
;									     ;
;   It is the caller's responsibility to handle all segment crossings,       ;
;   and	to ensure that there are eight bytes of	destination available	     ;
;   to hold each byte of source	data.					     ;
;									     ;
;   This routine is used for:						     ;
;	internal mono to external eight-bit packed pixels		     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of bytes to xlate				     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

public	copy_i1e8
copy_i1e8       proc    near

        lea     bx,color_xlate

ci1e8_next_byte:
	mov	dl,8
        lodsb
	mov	ah,al

ci1e8_next_bit:
	sub	al	,al
	shl	ah,1		; first nibble
        adc     al      ,al
        xlat    ss:[bx]

	stosb

	dec	dl
	jnz	ci1e8_next_bit
	loop	ci1e8_next_byte

	ret

copy_i1e8	endp

page
;--------------------------Private-Routine-----------------------------------;
; copy_i1e8_partial							     ;
;									     ;
;   copy internal 1 bit	to external 8 bit packed pixel,	partial	byte	     ;
;									     ;
;   The	destination is filled with the source data, with each source	     ;
;   bit	expanded to a byte in the destination.	This routine handles	     ;
;   partial bytes where	some portion of	the first or last byte needs	     ;
;   to be saved.							     ;
;									     ;
;   This routine will handle the destination (user's buffer) crossing        ;
;   a segment boundary during the translation of the source byte.	     ;
;   The	source will never cross	a segment boundary since it is an	     ;
;   internal bitmap and	all scans are allocated	to fit within a		     ;
;   segment.								     ;
;									     ;
;   This routine shouldn't be called very often, so a short loop will        ;
;   be sufficient for our needs.					     ;
;									     ;
;   This routine is used for:						     ;
;	internal mono to external eight-bit packed pixels		     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CL     =  number of pixels to xlate				     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
; Error	Returns:							     ;
;	None								     ;
; Registers Preserved:							     ;
;	BP,ES,DS,BP							     ;
; Registers Destroyed:							     ;
;	AX,BX,DX,SI,FLAGS						     ;
; Calls:								     ;
;	None								     ;
; History:								     ;
;	Tue 12-May-1987	16:52:24 -by-  Walt Moore [waltm]		     ;
;	Created.							     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

copy_i1e8_partial proc near

        lea     bx,color_xlate
        lodsb
	mov	ah,al

ci1e8p_next_bit:
	sub	al	,al
	shl	ah,1		; first nibble
        adc     al      ,al
        xlat    ss:[bx]

	cmp	di,-1
	jz	ci1e8p_dest_segx
	stosb

ci1e8p_10:

	dec	cl
	jnz	ci1e8p_next_bit
	ret

ci1e8p_dest_segx:

	call	store_e8_with_seg_check
	jmp	short ci1e8p_10

copy_i1e8_partial endp


store_e8_with_seg_check proc near

	stosb				;Save the byte
        or      di, di                  ;If in the next segment
	jz	swsc_e8_exit		;  then update the selector
        ret
;
swsc_e8_exit:

	cmp	cl,1
	jne	@F
        cmp     scanline_count,1
	je	swsc_e8_x

@@:     push    ax
        push    dx
        mov     dx, es
        add     dx, __NEXTSEG
        mov     es, dx
        assumes es, nothing
        pop     dx
        pop     ax

swsc_e8_x:
	ret

store_e8_with_seg_check endp


page
;--------------------------Private-Routine-----------------------------------;
; copy_i1e24								     ;
;									     ;
;   copy internal 1 bit	to external 24 bit RGB				     ;
;									     ;
;   The	destination is filled with the source data, with each source	     ;
;   bit	expanded to a full RGB triplet in the destination.  The	colors	     ;
;   being translated are black and white, so no	color lookup is	required.    ;
;									     ;
;   It is the caller's responsibility to handle all segment crossings,       ;
;   and	to ensure that there are 24 bytes of destination available to	     ;
;   hold each source byte of data.					     ;
;									     ;
;   This routine is used for:						     ;
;	internal mono to external RGB (24-bit packed pixels)		     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of bytes to xlate				     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

public	copy_i1e24
copy_i1e24      proc    near
;
ci1e24_next_byte:
	mov	dl,8
        lodsb
	mov	dh,al
;
ci1e24_next_bit:
	shl	dh,1
	sbb	al,al			; 0 or ff
	xor	ah,ah

        push    es
	les	bx,lpColorInfo
	shl	ax,1
	shl	ax,1
	add	bx,ax
	mov	ax,es:[bx]
	mov	bl,es:[bx+2]
	pop	es

        cmp     di,0fffch
	jae	ci1e24_eos_check

	stosw				; dump 3 bytes
	xchg	ax,bx
        stosb
;
ci1e24_minor_check:
	dec	dl
	jnz	ci1e24_next_bit
	loop	ci1e24_next_byte
	ret
;
ci1e24_eos_check:
	call	store_e24a_with_seg_check
	xchg	ah,al
	call	store_e24a_with_seg_check
	xchg	ax,bx
	call	store_e24a_with_seg_check
	jmp	short  ci1e24_minor_check

copy_i1e24	endp


store_e24a_with_seg_check proc near

	stosb				;Save the byte
        or      di, di                  ;If in the next segment
	jz	swsc_e24a_exit		  ;  then update the selector
        ret
;
swsc_e24a_exit:

	cmp	dl,1
        jne     @F
        cmp     cl,1
	jne	@F
        cmp     scanline_count,1
	je	swsc_e24a_x

@@:     push    ax
        push    dx
        mov     dx, es
        add     dx, __NEXTSEG
        mov     es, dx
        assumes es, nothing
        pop     dx
        pop     ax

swsc_e24a_x:
	ret

store_e24a_with_seg_check endp




page
;--------------------------Private-Routine-----------------------------------;
; copy_i1e24_partial							     ;
;									     ;
;   copy internal 1 bit	to external 24 bit RGB,	partial	byte		     ;
;									     ;
;   The	destination is filled with the source data, with each source	     ;
;   bit	expanded to a full RGB triplet in the destination.  The	colors	     ;
;   being translated are black and white, so no	color lookup is	required.    ;
;									     ;
;   This routine handles partial bytes where some portion of the first	     ;
;   or last byte needs to be saved.					     ;
;									     ;
;   This routine will handle the destination (user's buffer) crossing        ;
;   a segment boundary during the translation of the source byte.	     ;
;   The	source will never cross	a segment boundary since it is an	     ;
;   internal bitmap and	all scans are allocated	to fit within a		     ;
;   segment.								     ;
;									     ;
;   This routine shouldn't be called very often, so a short loop will        ;
;   be sufficient for our needs.					     ;
;									     ;
;   This routine is used for:						     ;
;	internal mono to external RGB (24-bit packed pixels)		     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CL     =  number of pixels to xlate				     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

copy_i1e24_partial proc	near

	lea	bx,color_xlate
        lodsb
	mov	dh,al
;
ci1e24p_next_bit:
	shl	dh,1
	sbb	al,al			; 0 or ff
	xor	ah,ah

	push	es
	les	bx,lpColorInfo
	shl	ax,1
	shl	ax,1
        add     bx,ax
	mov	ax,es:[bx]
	mov	bl,es:[bx+2]
	pop	es

	cmp	di,0fffch
	jae	ci1e24p_eos_check

	stosw				; dump 3 bytes
	xchg	ax,bx
        stosb
;
ci1e24p_minor_check:
	dec	cl
	jnz	ci1e24p_next_bit
	ret
;
ci1e24p_eos_check:
	call	store_e24_with_seg_check
	xchg	ah,al
	call	store_e24_with_seg_check
	xchg	ax,bx
	call	store_e24_with_seg_check
	jmp	short  ci1e24_minor_check

copy_i1e24_partial endp


store_e24_with_seg_check proc near

	stosb				;Save the byte
        or      di, di                  ;If in the next segment
	jz	swsc_e24_exit		 ;  then update the selector
        ret
;
swsc_e24_exit:

	cmp	cl,1
	jne	@F
        cmp     scanline_count,1
	je	swsc_e24_x

@@:     push    ax
        push    dx
        mov     dx, es
        add     dx, __NEXTSEG
        mov     es, dx
        assumes es, nothing
        pop     dx
        pop     ax

swsc_e24_x:
	ret

store_e24_with_seg_check endp



page
;--------------------------Private-Routine-----------------------------------;
;   store_with_seg_check						     ;
;									     ;
;   The	contents of AL is stored at ES:DI.  If DI becomes 0, then	     ;
;   the	next destination selector (if it exists) will be loaded.	     ;
;									     ;
; Entry:								     ;
;	ES:DI --> destination						     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

store_with_seg_check proc near
	stosb				;Save the byte
	or	di, di			;If in the next segment
	jz	swsc_exit		;  then update the selector
	ret
;
swsc_exit:

	push	ax
	push	dx
	mov	dx, es
	add	dx, __NEXTSEG
	mov	es, dx
	assumes	es, nothing
	pop	dx
	pop	ax
	ret

store_with_seg_check endp

page
;--------------------------Private-Routine-----------------------------------;
; copy_i8e1								     ;
;									     ;
;   copy internal 1 8-bit pixel	to external 1 bit			     ;
;									     ;
;   The	destination is filled with the source data.  All 8 byte	pixels	     ;
;   of the source byte are combined to form the	single destination byte.     ;
;									     ;
;   It is the caller's responsibility to handle all segment crossings,       ;
;   and	to ensure that there are enough	bytes of destination available	     ;
;   to hold the	data.							     ;
;									     ;
;   Since there	will be	information loss in going from four color to	     ;
;   one	color, all colors which	match the !!!??? background color	     ;
;   will be mapped to 1, and all other colors will be mapped to	the	     ;
;   !!!??? forground color.  This is the same strategy used in color	     ;
;   to mono bitblts.							     ;
;									     ;
;   This routine is used for:						     ;
;	internal four-plane to external	mono				     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of bytes to xlate				     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

public	copy_i8e1
public  copy_i8e1
copy_i8e1	proc  near
	lea	bx,color_xlate

ci8e1_next_byte:
	mov	dl, 8
	mov	ah, 0

ci8e1_next_pixel:
	lodsb
	xlat	ss:[bx]
	cmp	ah,al
        rcl     dh, 1
	dec	dl
	jne	ci8e1_next_pixel

	mov	al, dh
	stosb

        loop    ci8e1_next_byte         ;next byte

	ret

copy_i8e1	endp

page
;--------------------------Private-Routine-----------------------------------;
; copy_i8e1_partial							     ;
;									     ;
;   copy internal 1 8-bit pixel	to external 1 bit, partial byte		     ;
;									     ;
;   The	destination is filled with the source data.  All 8 byte	pixels	     ;
;   of the source byte are combined to form the	single destination byte.     ;
;									     ;
;   This routine will handle the destination (user's buffer) crossing        ;
;   a segment boundary during the translation of the source byte.	     ;
;   The	source will never cross	a segment boundary since it is an	     ;
;   internal bitmap and	all scans are allocated	to fit within a		     ;
;   segment.								     ;
;									     ;
;   Since there	will be	information loss in going from four color to	     ;
;   one	color, all colors which	match the !!!??? background color	     ;
;   will be mapped to 1, and all other colors will be mapped to	the	     ;
;   !!!??? forground color.  This is the same strategy used in color	     ;
;   to mono bitblts.							     ;
;									     ;
;   This routine is used for:						     ;
;	internal four-plane to external	mono				     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of bits to xlate (will	always be 8)		     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

copy_i8e1_partial proc near
	mov	cx, 1
	call	full_byte_proc
	dec	di
	jmp	store_i1_with_seg_check

copy_i8e1_partial endp


store_i1_with_seg_check proc near
	stosb				;Save the byte
	or	di, di			;If in the next segment
	jz	swsc_i1_exit		   ;  then update the selector
	ret
;
swsc_i1_exit:

	cmp	scanline_count,1
	je	@F

	push	ax
	push	dx
	mov	dx, es
	add	dx, __NEXTSEG
	mov	es, dx
	assumes	es, nothing
	pop	dx
	pop	ax
@@:
	ret

store_i1_with_seg_check endp



page
;--------------------------Private-Routine-----------------------------------;
; copy_i8e4								     ;
;									     ;
;   copy internal 1 8-bit pixel	to external 4 bit packed pixel		     ;
;									     ;
;   The	destination is filled with the source data.  All four planes	     ;
;   of the source byte are used	to form	the nibble for the destination	     ;
;   byte.								     ;
;									     ;
;   It is the caller's responsibility to handle all segment crossings,       ;
;   and	to ensure that there are enough	bytes of destination available	     ;
;   to hold the	data.							     ;
;									     ;
;   Since there	will be	information loss in going from four color to	     ;
;   one	color, all colors which	match the !!!??? background color	     ;
;   will be mapped to 1, and all other colors will be mapped to	the	     ;
;   !!!??? forground color.  This is the same strategy used in color	     ;
;   to mono bitblts.							     ;
;									     ;
;   This routine is used for:						     ;
;	internal four-plane to external	4-bit packed pixels		     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of bytes to xlate				     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

public	copy_i8e4
copy_i8e4	proc near
	lea	bx,color_xlate

ci8e4_next_byte:
	mov	dl, 4			;8 pixel/byte -	inner loop count

ci8e4_next_pixel:
	lodsb				;load 1	byte pixel
	xlat	ss:[bx]
        mov     ah, al
	shiftl	ah, 4			;use last 4 bits for 1st nibble
	lodsb
	xlat	ss:[bx]
        and     al, 0fh                 ;use last 4 bits for 2nd nibble
	or	al, ah

        stosb                           ;store 1 byte to dest
	dec	dl
	jne	ci8e4_next_pixel

	loop	ci8e4_next_byte		;next byte

	ret

copy_i8e4	endp

page
;--------------------------Private-Routine-----------------------------------;
;									     ;
; copy_i8e4_partial							     ;
;									     ;
;   copy internal 1 8-bit pixel	to external 4 bit packed pixel,	partial	byte ;
;									     ;
;   The	destination is filled with the source data.  All four planes	     ;
;   of the source byte are used	to form	the nibble for the destination	     ;
;   byte.								     ;
;									     ;
;   This routine handles partial bytes where some portion of the first	     ;
;   or last byte needs to be saved.					     ;
;									     ;
;   This routine will handle the destination (user's buffer) crossing        ;
;   a segment boundary during the translation of the source byte.	     ;
;   The	source will never cross	a segment boundary since it is an	     ;
;   internal bitmap and	all scans are allocated	to fit within a		     ;
;   segment.								     ;
;									     ;
;   Since this routine always writes nibbles, it is guaranteed that	     ;
;   the	shift count passed in is even.					     ;
;									     ;
;   This routine is used for:						     ;
;	internal four-plane to external	4-bit packed pixels		     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	BX     =  index	to next	plane					     ;
;	CL     =  number of pixels to xlate				     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

copy_i8e4_partial proc near
	lea	bx,color_xlate
        shr     cl, 1
;
ci8e4p_next_pixel:
	lodsb				;load 1	byte pixel
	xlat	ss:[bx]
        mov     ah, al
	shiftl	ah, 4			;use last 4 bits for 1st nibble
	lodsb
	xlat	ss:[bx]
        and     al, 0fh                 ;use last 4 bits for 2nd nibble
	or	al, ah
	call	store_i4_with_seg_check
	dec	cl
	jne	ci8e4p_next_pixel
	ret

copy_i8e4_partial endp


store_i4_with_seg_check proc near
	stosb				;Save the byte
	or	di, di			;If in the next segment
	jz	swsc_i4_exit		   ;  then update the selector
	ret
;
swsc_i4_exit:

	cmp	cl,1
	jne	@F
        cmp     scanline_count,1
	je	swsc_i4_x

@@:
	push	ax
	push	dx
	mov	dx, es
	add	dx, __NEXTSEG
	mov	es, dx
	assumes	es, nothing
	pop	dx
	pop	ax

swsc_i4_x:
	ret

store_i4_with_seg_check endp




page
;--------------------------Private-Routine-----------------------------------;
;									     ;
; copy_i8e8								     ;
;									     ;
;   copy internal 1 8-bit pixel	to external 8 bit packed pixel		     ;
;									     ;
;   It is the caller's responsibility to handle all segment crossings,       ;
;   and	to ensure that there are enough	bytes of destination available	     ;
;   to hold the	data.							     ;
;									     ;
;   This routine is used for:						     ;
;	internal 8 bit to external 8-bit packed pixels			     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of bytes to xlate				     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
; Error	Returns:							     ;
;	None								     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

public	copy_i8e8
copy_i8e8       proc near
	mov	bx, cx

ci8e8_next_byte:
	mov	cx, 4			;8 pixel/byte
	rep	movsw
	dec	bx
	jne	ci8e8_next_byte
	ret

copy_i8e8	endp

page
;--------------------------Private-Routine-----------------------------------;
;									     ;
; copy_i8e8_partial							     ;
;									     ;
;   copy internal 1 8-bit pixel	to external 8 bit packed pixel,	partial	byte ;
;									     ;
;   The	destination is filled with the source data.  All four planes	     ;
;   of the source byte are used	to form	the byte for the destination.	     ;
;									     ;
;   This routine handles partial bytes where some portion of the first	     ;
;   or last byte needs to be saved.					     ;
;									     ;
;   This routine will handle the destination (user's buffer) crossing        ;
;   a segment boundary during the translation of the source byte.	     ;
;   The	source will never cross	a segment boundary since it is an	     ;
;   internal bitmap and	all scans are allocated	to fit within a		     ;
;   segment.								     ;
;									     ;
;   This routine is used for:						     ;
;	internal four-plane to external	8-bit packed pixels		     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CL     =  number of pixels to xlate				     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

copy_i8e8_partial proc near

ci8e8p_next_pixel:
	lodsb
	call	store_i8_with_seg_check
	dec	cl
	jne	ci8e8p_next_pixel
	ret

copy_i8e8_partial endp


store_i8_with_seg_check proc near
	stosb				;Save the byte
	or	di, di			;If in the next segment
	jz	swsc_i8_exit		   ;  then update the selector
	ret
;
swsc_i8_exit:

	cmp	cl,1
	jne	@F
        cmp     scanline_count,1
	je	swsc_i8_x

@@:
	push	ax
	push	dx
	mov	dx, es
	add	dx, __NEXTSEG
	mov	es, dx
	assumes	es, nothing
	pop	dx
	pop	ax

swsc_i8_x:
	ret

store_i8_with_seg_check endp



page
;--------------------------Private-Routine-----------------------------------;
;									     ;
; copy_i8e24								     ;
;									     ;
;   copy internal 1 8-bit pixel	to external 24 bit RGB			     ;
;									     ;
;   The	destination is filled with the source data.  All four planes	     ;
;   of the source byte are used	to form	the RGB	triplet	for the		     ;
;   destination.							     ;
;									     ;
;   It is the caller's responsibility to handle all segment crossings,       ;
;   and	to ensure that there are enough	bytes of destination available	     ;
;   to hold the	data.							     ;
;									     ;
;   Since there	will be	information loss in going from four color to	     ;
;   one	color, all colors which	match the !!!??? background color	     ;
;   will be mapped to 1, and all other colors will be mapped to	the	     ;
;   !!!??? forground color.  This is the same strategy used in color	     ;
;   to mono bitblts.							     ;
;									     ;
;   This routine is used for:						     ;
;	internal four-plane to external	RGB (24-bit packed)		     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CX     =  number of bytes to xlate				     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

public	copy_i8e24
copy_i8e24      proc near

	; check if we have a colour info table.
	cmp	wptr lpColorInfo[2],0
	jnz	ci8e24_next_byte

	; if not, we just have to convert back to a list of RGBTRIPLEs
	mov	bh,10b	; swap red/blue, only three bytes (not four) per pixel
	mov	bl,[total_depth_bytes]
	shl	bl,3	; convert back to bits
	shl	cx,3	; deal with the "8 pixels/byte" concept
	call	ipc_to_rgb_seq
	ret

ci8e24_next_byte:
	mov	dl, 8			;8 pixels/byte

ci8e24_next_pixel:
	lodsb
	xor	ah, ah

        push    es
	les	bx, lpColorInfo
	shl	ax, 1			;index to table (4 bytes/entry)
	shl	ax, 1
        add     bx, ax
	mov	ax, es:[bx]
	mov	bl, es:[bx+2]
	pop	es

        stosw
	xchg	ax,bx
        stosb
	dec	dl
	jne	ci8e24_next_pixel

	loop	ci8e24_next_byte
	ret

copy_i8e24	endp

page
;--------------------------Private-Routine-----------------------------------;
;									     ;
; copy_i8e24_partial							     ;
;									     ;
;   copy internal 1 8-bit pixel	to external 24 bit RGB,	partial	byte	     ;
;									     ;
;   The	destination is filled with the source data.  All four planes	     ;
;   of the source byte are used	to form	the RGB	triplet	for the		     ;
;   destination.							     ;
;									     ;
;   This routine handles partial bytes where some portion of the first	     ;
;   or last byte needs to be saved.					     ;
;									     ;
;   This routine will handle the destination (user's buffer) crossing        ;
;   a segment boundary during the translation of the source byte.	     ;
;   The	source will never cross	a segment boundary since it is an	     ;
;   internal bitmap and	all scans are allocated	to fit within a		     ;
;   segment.								     ;
;									     ;
;   This routine is used for:						     ;
;	internal four-plane to external	RGB (24-bit packed)		     ;
;									     ;
; Entry:								     ;
;	DS:SI --> source						     ;
;	ES:DI --> destination						     ;
;	CL     =  number of pixels to xlate				     ;
; Returns:								     ;
;	ES:DI --> next destination byte					     ;
;----------------------------------------------------------------------------;

	assumes	ds, nothing
	assumes	es, nothing

copy_i8e24_partial proc	near

ci8e24p_next_pixel:
	cmp	wptr lpColorInfo[2],0
	jnz	@F

	push	es
	push	cx
	push	di
	;stick the RGB colour on the stack
	sub	sp,4
	push	ss
	pop	es
	mov	di,sp
	mov	cx,1			;one colour at a time
	mov	bh,10b	; swap red/blue, only three bytes (not four) per pixel
	mov	bl,[total_depth_bytes]
	shl	bl,3	; convert back to bits
	call	ipc_to_rgb_seq
	;get it from the stack
	pop	ax
	pop	bx
	pop	di
	pop	cx
	pop	es
	jmp	ci8e24p_check_di

@@:	lodsb
	xor	ah, ah

        push    es
	les	bx, lpColorInfo
	shl     ax, 1                   ;index to table (3 bytes/entry)
        shl     ax, 1
        add     bx, ax
	mov	ax, es:[bx]
	mov	bl, es:[bx+2]
	pop	es
ci8e24p_check_di:
	cmp	di, 0FFFDh
	jae	ci8e24p_next_sel

        stosw
	xchg	ax, bx
	stosb

ci8e24p_loop_next:
	dec	cl
	jne	ci8e24p_next_pixel
	ret

ci8e24p_next_sel:
	call	store_i24_with_seg_check
	xchg	al, ah
	call	store_i24_with_seg_check
	xchg	ax, bx
	call	store_i24_with_seg_check
	jmp	ci8e24p_loop_next

copy_i8e24_partial endp


store_i24_with_seg_check proc near
	stosb				;Save the byte
	or	di, di			;If in the next segment
	jz	swsc_i24_exit		    ;  then update the selector
	ret
;
swsc_i24_exit:

	cmp	cl,1
	jne	@F
        cmp     scanline_count,1
	je	swsc_i24_x

@@:
	push	ax
	push	dx
	mov	dx, es
	add	dx, __NEXTSEG
	mov	es, dx
	assumes	es, nothing
	pop	dx
	pop	ax

swsc_i24_x:
	ret

store_i24_with_seg_check endp





sEnd	code
end
