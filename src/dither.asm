        page    ,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	DITHER.ASM
;
; This file contains the brush dithering algorithm for brushes.
;
; Created: 17-Jan-1987
; Author:  Walt Moore [waltm]
;
; Copyright (c) 1985-1987 Microsoft Corporation
;
; Exported Functions:	none
;
; Public Functions:	dither
;
; Public Data:		none
;
; General Description:
;
;	The dithering algorithm is called to generate the patterns
;	used for brushes.  Two versions of the code can be assembled.
;	One version favors devices with a 2:1 asspect ration (like
;	the CGA), and the other version favors 1:1 aspect ration
;	devices.
;
; Restrictions:
;	The dithering algorithm assumes that the size of the brush is
;	8 x 8.
;
;-----------------------------------------------------------------------;

	.xlist
	include cmacros.inc
	include macros.mac
	.list


sBegin	Code
assumes cs,Code
page
;-----------------------------Public-Routine----------------------------;
; dither
;
; Dither(value, lpBrush)
;
;   This function takes value between 0 - 255 and uses it to create
;   an 8x8 pile of bits that can be used as a brush.  It does this
;   by reducing the input value to a number between 0 - 64 and then
;   turns on that many bits in the 8x8 field.  Thus the value 0 leads
;   to brush of all zeros, a 255 value leads to a brush of all 1's,
;   and a value of 128 leads to grey.
;
;   The algorithm is equivalent to turning on bits based on an array:
;
;	 0 32  8 40  2 34 10 42
;	48 16 56 24 50 18 58 26
;	12 44  4 36 14 46  6 38 	This table favors devices like
;	60 28 52 20 62 30 54 22 	the Hercules card where the
;	 3 35 11 43  1 33  9 41 	aspect ratio is close to 1:1
;	51 19 59 27 49 17 57 25
;	15 47  7 39 13 45  5 37
;	63 31 55 23 61 29 53 21
;
;	 0 32 16 48  2 34 18 50
;	24 56  8 40 26 58 10 42 	This table favors devices like
;	 4 36 20 52  6 38 22 54 	the CGA card where the aspect
;	28 60 12 44 30 62 14 46 	ratio is close to 2:1
;	 3 35 19 51  1 33 17 49
;	27 59 11 43 25 57  9 41
;	 7 39 23 55  5 37 21 53
;	31 63 15 47 29 61 13 45
;
;
;   Where given a value between 0 - 64, turn on the bit if the array
;   value is less then the desired value.
;
;   When dithering for color drivers, where each plane is dither
;   independantly, this algorithm has a nice side effect in that
;   for any value n < m, n is a proper subset of m (any bit turned
;   on in n must have been turned on in m!).
;
;   For the 1:1 table, undesirable patterns are generated for light
;   and dark grey.  These will be flagged when encountered.  For the
;   2:1 table,	vertical lines are generated for grey, so they will
;   be flagged when encountered.  The brush realization routines
;   can then substitute the correct grey (we cannot do it because
;   we do not know if the other planes of a color brush were the
;   same pattern).
;
;   Reference:	A Survey of Techniques for the Display of Continuous
;		Tone Pictures on Bilevel Displays,;
;		Jarvis, Judice, & Ninke;
;		COMPUTER GRAPHICS AND IMAGE PROCESSING 5, pp 13-40, (1976)
;
; Entry:
;	DL     =  value to dither
;	ES:DI --> destination
;	SI     =  previous grey indicator
; Returns:
;	ES:DI --> next destination (ES:DI + SIZE_PATTERN)
;	DH     =  dither value (0-64)
;	SI     =  New grey indicator (SI << 3 || grey_indicator)
;		    D2:D0 = 001b for dark  grey
;		    D2:D0 = 010b for grey
;		    D2:D0 = 011b for light grey
;		    D2:D0 = 100b for black
;		    D2:D0 = 101b for white
;		    D2:D0 = 000b otherwise
; Error Returns:
;       none
; Registers Destroyed:
;	AX,BX,CX,DX,DS,FLAGS
; Registers Preserved:
;	none
; Calls:
;	none
; History:
;	Sun 15-Feb-1987 18:35:01 -by-  Walt Moore [waltm]
;	Initial version
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


	public	dither
dither	proc	near

	mov	ax,cs
	mov	ds,ax
	assumes ds,Code

	mov	cx,3			;Will be usefull
	xor	bx,bx			;Need a zero a few times
	xchg	ax,si			;Need SI later
	shl	ax,cl			;Update old grey flags
	inc	cx			;4 will be useful later

	shr	dl,1			;Convert value 0-255 into
	adc	dl,bl			;  value 0 - 64
	shr	dl,1
	mov	bl,dl			;base_pattern index is D6:D2
	mov	dh,dl			;Return mapped value to caller in DL
	and	bl,11111100b

	lea	si,cs:base_patterns[bx] ;Copy the base pattern
	cld
	movsw
	movsw
	sub	si,cx			;Duplicate for second half of brush
	movsw
	movsw
	xchg	ax,si			;Restore grey flags

	test	dl,00000011b		;A base pattern?
	jnz	not_base_pattern
	test	dl,00001111b		;A grey to special case?
	jnz	is_base_pattern 	;  No, it is not
	shr	bx,cl			;D6:D4 is index into grey_flags
	mov	bl,cs:grey_flags[bx]	;Or in grey flag
	or	si,bx

is_base_pattern:
	ret

not_base_pattern:
	shr	bx,1			;D5:D2 will index into rows_and_masks
	and	bl,0FEh 		;Indexing into words, must be 0
	mov	ax,cs:rows_and_masks[bx];AL = base row, AH = base mask
	mov	bl,al			;Set base row
	sub	bx,8			;Adjust for di pointing past brush
	mov	al,ah			;Shift pattern for proper use
	shr	al,cl			;AH is base pattern, AL is base >> 4

	and	dl,11b			;Dispatch as needed
	cmp	dl,2			;CL = 2
	jb	first_bit
	je	second_bit

third_bit:
	or	es:[di][bx][0],al	;Set third bit

second_bit:
	or	es:[di][bx][4],al	;Set second bit

first_bit:
	or	es:[di][bx][0],ah	;Set first bit

	ret

dither	endp

page
;	The grey_flags table contains the values to OR into the
;	accumulated grey flag for colors which mapped to the
;	greys which must be special cased.


grey_flags	label	byte

		db	100b		 ;Black      (00)
		db	001b		 ;Dark Grey  (16)
		db	010b		 ;Grey	     (32)
		db	011b		 ;Light Grey (48)
		db	101b		 ;White      (64)



;	The order in which the rows of the dither are accessed
;	are as follows:
;
;	    0,4,0,4,2,6,2,6		;For low resolution
;	    1,5,1,5,3,7,3,7
;	    0,4,0,4,2,6,2,6
;	    1,5,1,5,3,7,3,7
;	    0,4,0,4,2,6,2,6
;	    1,5,1,5,3,7,3,7
;	    0,4,0,4,2,6,2,6
;	    1,5,1,5,3,7,3,7
;
;	    0,4,0,4,2,6,2,6		;For high resolution
;	    0,4,0,4,2,6,2,6
;	    1,5,1,5,3,7,3,7
;	    1,5,1,5,3,7,3,7
;	    0,4,0,4,2,6,2,6
;	    0,4,0,4,2,6,2,6
;	    1,5,1,5,3,7,3,7
;	    1,5,1,5,3,7,3,7
;
;
;	The order in which bits are turned on is as follows:
;
;	    80,08,08,80,80,08,08,80	;For low resolutions
;	    20,02,02,20,20,02,02,20
;	    20,02,02,20,20,02,02,20
;	    80,08,08,80,80,08,08,80
;	    40,04,04,40,40,04,04,40
;	    10,01,01,10,10,01,01,10
;	    10,01,01,10,10,01,01,10
;	    40,04,04,40,40,04,04,40
;
;	    80,08,08,80,20,02,02,20	;For high resolution
;	    20,02,02,20,80,08,08,80
;	    40,04,04,40,10,01,01,10
;	    10,01,01,10,40,04,04,40
;	    40,04,04,40,10,01,01,10
;	    10,01,01,10,40,04,04,40
;	    80,08,08,80,20,02,02,20
;	    20,02,02,20,80,08,08,80
;
;
;	If you work in groups of four, the following observations
;	can be made about how the pixels are visited:
;
;	The rows are always accessed as follows:
;
;		row n
;		row n+4
;		row n
;		row n+4
;
;
;	The bits are always manipulated as follows:
;
;		bit n
;		bit n >> 4
;		bit n >> 4
;		bit n
;
;
;	Since base patterns are defined at intervals of four, the
;	algorithm for turning on the remaining 1, 2, or 3 bits
;	can be table driven.
;
;
;	The following table will contain the row and the bitmask to
;	use for turning on the remaining 1, 2, or 3 bits of the pattern.
;	Bits D5:D2 of the mapped color are used to index into this table.
;	The format is:
;
;		db	base row, base bit


rows_and_masks	label	word

	ifdef	LORES
	db	0,80h
	db	2,80h
	db	1,20h
	db	3,20h
	db	0,20h
	db	2,20h
	db	1,80h
	db	3,80h
	db	0,40h
	db	2,40h
	db	1,10h
	db	3,10h
	db	0,10h
	db	2,10h
	db	1,40h
	db	3,40h
	else
	db	0,80h
	db	2,20h
	db	0,20h
	db	2,80h
	db	1,40h
	db	3,10h
	db	1,10h
	db	3,40h
	db	0,40h
	db	2,10h
	db	0,10h
	db	2,40h
	db	1,80h
	db	3,20h
	db	1,20h
	db	3,80h
	endif


base_patterns:

	ifdef	LORES
	db	000h,000h,000h,000h
	db	088h,000h,000h,000h
	db	088h,000h,022h,000h
	db	0AAh,000h,022h,000h
	db	0AAh,000h,0AAh,000h
	db	0AAh,044h,0AAh,000h
	db	0AAh,044h,0AAh,011h
	db	0AAh,055h,0AAh,011h
	db	0AAh,055h,0AAh,055h
	db	0EEh,055h,0AAh,055h
	db	0EEh,055h,0BBh,055h
	db	0FFh,055h,0BBh,055h
	db	0FFh,055h,0FFh,055h
	db	0FFh,0DDh,0FFh,055h
	db	0FFh,0DDh,0FFh,077h
	db	0FFh,0FFh,0FFh,077h
	db	0FFh,0FFh,0FFh,0FFh
	else
	db	000h,000h,000h,000h
	db	088h,000h,000h,000h
	db	088h,000h,088h,000h
	db	088h,022h,088h,000h
	db	088h,022h,088h,022h
	db	0AAh,022h,088h,022h
	db	0AAh,022h,0AAh,022h
	db	0AAh,0AAh,0AAh,022h
	db	0AAh,0AAh,0AAh,0AAh
	db	0EEh,0AAh,0AAh,0AAh
	db	0EEh,0AAh,0EEh,0AAh
	db	0EEh,0BBh,0EEh,0AAh
	db	0EEh,0BBh,0EEh,0BBh
	db	0FFh,0BBh,0EEh,0BBh
	db	0FFh,0BBh,0FFh,0BBh
	db	0FFh,0FFh,0FFh,0BBh
	db	0FFh,0FFh,0FFh,0FFh
	endif

	ifdef	PUBDEFS
	public	is_base_pattern
	public	not_base_pattern
	public	third_bit
	public	second_bit
	public	first_bit
	public	grey_flags
	public	rows_and_masks
	public	base_patterns
        endif

sEnd	Code
end
