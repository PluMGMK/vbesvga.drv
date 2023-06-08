	page    64,131
;
;----------------------------------------------------------------------------;
; 				rgb_to_ipc				     ;
;				----------				     ;
;   The given RGB triplet is converted into a 8 plane color index and the    ;
;   physical RGB triplet together with the color accelarator flags are       ;
;   returned.				                                     ;
;									     ;
;   Ordering of the color in a dword is such that when stored in	     ;
;   memory, red is the first byte, green is the second, and blue	     ;
;   is the third.  The high order 8 bits may be garbage when passed	     ;
;   in, and should be ignored.						     ;
;									     ;
;   when in a register:     xxxxxxxxBBBBBBBBGGGGGGGGRRRRRRRR		     ;
;									     ;
;   when in memory:	    db	    red,green,blue			     ;
;									     ;
;									     ;
; Entry:								     ;
;	DS:SI --> RGB triplet to sum	    (for sum_RGB_colors)	     ;
;	AL     =  Red	value of triplet    (for sum_RGB_colors_alt)	     ;
;	AH     =  Green value of triplet    (for sum_RGB_colors_alt)	     ;
;	DL     =  Blue	value of triplet    (for sum_RGB_colors_alt)	     ;
; Returns:								     ;
;       DH     =  Index & accelerator bits                                   ;
;                                                                            ;
;									     ;
;	AL		= Physical red color byte (0,32,128,255)	     ;
;	AH		= Physical green color byte (0,32,128,255)	     ;
;	DL		= Physical blue color byte (0,32,128,255)	     ;
;	DH:C0		= red	bit					     ;
;	DH:C1		= green bit					     ;
;	DH:C2		= blue	bit					     ;
;	DH:C3		= intensity bit					     ;
;	DH:MONO_BIT	= 0 if BX < BWThreashold			     ;
;			= 1 if BX >= BWThreashold			     ;
;	DH:ONES_OR_ZERO = 1 if C0:C3 are all 1's or all 0's		     ;
;	DH:GREY_SCALE	= 0						     ;
;	DH_SOLID_BRUSH	= 0						     ;
;									     ;
; Error Returns:                                                             ;
;	None								     ;
;									     ;
; Registers Preserved:                                                       ;
;	CX,SI,DI,DS,ES							     ;
;									     ;
; Registers Destroyed:                                                       ;
;       FLAGS                                                                ;
;									     ;
; External Calls:							     ;
;	None								     ;
; History:								     ;
;	Fri 16-Jun-1989 -by- Doug Cody, Video Seven, Inc.		     ;
;	Threw out the hack. Implemented the same routine used by the 8514    ;
;	256 color driver.						     ;
;                                                                            ;
;	Mon 05-Jun-1989 -by- Doug Cody, Video Seven, Inc.		     ;
;       re-written (as a quick hack) to support 20 reserved colors instead   ;
;	of 16. Changes have been made to:				     ;
;	  Start of routine. A second routine is called which attempts to     ;
;	  match the RGB to one of the 4 new colors.			     ;
;	  All physical color byte equates. This moved the accelerator bits   ;
;         one position to the left. This affects the return results since    ;
;         caller expects the accerators to begin in bit 4 of DH.             ;
;	  Added equates "PHYS_COLOR_BYTE_7a" through "PHYS_COLOR_BYTE_7d".   ;
;									     ;
;	Fri 25-Nov-1988 11:00:00 -by-  Amit Chatterjee [amitc]		     ;
;  	Created to adopt the 4 plane EGA/VGA model. The code is on the	     ;
;       lines of the code used in PM land.				     ;
;									     ;
; Fri 25-Nov-1988 11:00:00   -by-  Amit Chatterjee [amitc]		     ;
; Adopted the routine for 4 plane EGA/VGA drivers. PM uses plane 0 for Blue  ;
; and plane 2 for Red, for windows the convention is reverse. Changed the    ;
; tables to ensure plane 0 is red and 2 is blue.			     ;
;									     ;
;  Thu 08-Sep-1988 17:35:30  -by-  Charles Whitmer [chuckwh]		     ;
; Changed to the exact mapping algorithm described below.  This 	     ;
; fixes PTR 5760 which noted that the different mapped regions of the	     ;
; RGB cube were not convex.  This is a little more complex than the	     ;
; old method, and also a little slower.  Before my change, the MENU	     ;
; test in FUNTEST took 119 msec.  After my change, it takes 121.	     ;
; On the larger Random Dialogs Test, it stayed the same at 672 msec.	     ;
; So maybe we lost 2% on smaller stuff. 				     ;
;									     ;
;  Wed 27-Jul-1988 15:29:16 -by- Bob Grudem [bobgru]			     ;
; Changed packed_ipc_table so that dimmest colors were chosen in ties	     ;
; instead of brightest.  This resolves the problem of 7FBFFF (supposed	     ;
; to be PALEBLUE) mapping to white, when it is used as background for	     ;
; white text on the title bar!	Moreover, it does it in a consistent	     ;
; way that doesn't break any of the new code.                                ;
;									     ;
;  Tue 19-Jul-1988 15:25:10 -by- Bob Grudem [bobgru]			     ;
; Rewrote from scratch to match color mapping of dithering code.	     ;
; See the discussion above for details. 				     ;
;									     ;
;  Wed 13-Jul-1988 11:23:38 -by- Bob Grudem [bobgru]			     ;
; Added special case checking for intense black (iblk? macro).		     ;
;									     ;
;  Mon 08-Feb-1988 22:42:10 -by-  Walt Moore [waltm]			     ;
; Temp kludge for the rewrite						     ;
;----------------------------------------------------------------------------;
;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.
        include cmacros.inc
	include	macros.mac
;
; accelerator bytes
PHY_COLOR_BYTE_00	equ	0010b	    ; black
PHY_COLOR_BYTE_01	equ	0000b	    ; dark red
PHY_COLOR_BYTE_02	equ	0000b	    ; dark green
PHY_COLOR_BYTE_03	equ	0000b	    ; mustard
PHY_COLOR_BYTE_04	equ	0000b	    ; dark blue
PHY_COLOR_BYTE_05	equ	0000b	    ; purple
PHY_COLOR_BYTE_06	equ	0000b	    ; dark turquoise
PHY_COLOR_BYTE_07	equ	0001b	    ; gray
PHY_COLOR_BYTE_07A	equ	0001b	    ; money green
PHY_COLOR_BYTE_07B	equ	0001b	    ; new blue
PHY_COLOR_BYTE_07C	equ	0001b	    ; off-white
PHY_COLOR_BYTE_07D	equ	0001b	    ; med-gray
PHY_COLOR_BYTE_08	equ	0001b	    ; dark gray
PHY_COLOR_BYTE_09	equ	0000b	    ; red
PHY_COLOR_BYTE_10	equ	0001b	    ; green
PHY_COLOR_BYTE_11	equ	0001b	    ; yellow
PHY_COLOR_BYTE_12	equ	0000b	    ; blue
PHY_COLOR_BYTE_13	equ	0000b	    ; magenta
PHY_COLOR_BYTE_14	equ	0001b	    ; cyan
PHY_COLOR_BYTE_15	equ	0011b	    ; white
;
sBegin Data
	assumes	ds,Data

public Palette
Palette         label   byte
	db	0,    0,    0		; 0
	db	080h, 0,    0		; 1
	db	0,    080h, 0		; 2
	db	080h, 080h, 0		; 3
	db	0,    0,    080h	; 4
	db	080h, 0,    080h	; 5
	db	0,    080h, 080h	; 6
	db	0c0h, 0c0h, 0c0h	; 7  Light Grey
;					; we can define some extra system
;					; colors if there are 8 bits per pixel
ExtraColors     label   byte
	db	0c0h, 0dch, 0c0h	; Money Green
	db	0a4h, 0c8h, 0f0h	; cool blue
	db	0ffh, 0fbh, 0f0h	; off white
	db	0a0h, 0a0h, 0a4h	; med grey
;
ExtraPalLength  equ     $-DataOFFSET ExtraColors
NbrofXColors	equ	($-DataOFFSET ExtraColors)/3
;
	db	080h, 080h, 080h	 ; 8  Dark Grey
	db	0ffh,	0 ,   0 	 ; 9
	db	  0 , 0ffh,   0 	 ; a
	db	0ffh, 0ffh,   0 	 ; b
	db	  0 ,	0 , 0ffh	 ; c
	db	0ffh,	0 , 0ffh	 ; d
	db	  0 , 0ffh, 0ffh	 ; e
	db	0ffh, 0ffh, 0ffh	 ; f
;
PaletteLength   equ     $-DataOFFSET Palette
NbrofColours	equ	($-DataOFFSET Palette)/3
public NbrofColours

PhysicalIndexTable label   byte
	db	  0,PHY_COLOR_BYTE_00
	db	  1,PHY_COLOR_BYTE_01
	db	  2,PHY_COLOR_BYTE_02
	db	  3,PHY_COLOR_BYTE_03
	db	  4,PHY_COLOR_BYTE_04
	db	  5,PHY_COLOR_BYTE_05
	db	  6,PHY_COLOR_BYTE_06
	db	  7,PHY_COLOR_BYTE_07
	db	  8,PHY_COLOR_BYTE_07A
	db	  9,PHY_COLOR_BYTE_07B
	db	246,PHY_COLOR_BYTE_07C
	db	247,PHY_COLOR_BYTE_07D
	db	248,PHY_COLOR_BYTE_08
	db	249,PHY_COLOR_BYTE_09
	db	250,PHY_COLOR_BYTE_10
	db	251,PHY_COLOR_BYTE_11
	db	252,PHY_COLOR_BYTE_12
	db	253,PHY_COLOR_BYTE_13
	db	254,PHY_COLOR_BYTE_14
	db	255,PHY_COLOR_BYTE_15
;
SystemPaletteColors	equ	20
;
sEnd Data
;
;-------------------------==============================-----------------------
;-------------------------====< start of execution >====-----------------------
;-------------------------==============================-----------------------
;
sBegin Code
	assumes cs, Code
	assumes ds, Data
	assumes es, nothing
;
	extrn	_cstods:word		; our data segment
;
; At this point,
;    AL contains the RED intensity that we're going to use.
;    AH contains the GREEN intensity that we're going to use.
;    DL contains the BLUE intensity that we're going to use.
;    DH contains the colour index.
;
cProc	rgb_to_ipc, <NEAR, PUBLIC>, <ds, si, di, cx, bx>
	localW	lMinLo
	localW	wIndex
	localB	lMinHi
;
cBegin
	WriteAux <'rgb-to_ipc'>

	mov	bx, ax			; logical colors are in
	mov	ds,cs:_cstods
        sub     cx, cx                  ; bl: red, bh: green, dl: blue
	mov	cl, SystemPaletteColors ; CX=Size of Physical Palette
	xor	ax, ax
	dec	ax
	mov	lMinLo, ax		; initialize error term to some
	mov	lMinHi, al		; hideously large value (00ffffffh)
	mov	si, DataOFFSET Palette	; DS:SI-->Physical palette (RGB)
;
LetsBoogy:
	sub	dh, dh			; initialize true error to 0
	lodsb				; get physical red into AL
	sub	al, bl			; subtract red we want
	ja	SquareRed		; if the result was negative change
	neg	al			; the sign of the difference
;
SquareRed:
	mul	al			; square differnce now
	mov	di, ax			; and save error squared in di
	lodsb				; now do the same thing with green
	sub	al, bh
	ja	SquareGreen
	neg	al
;
SquareGreen:
	mul	al
	add	di, ax
	adc	dh, dh
	lodsb				; now compute delta B squared
	sub	al, dl
	ja	SquareBlue
	neg	al
;
SquareBlue:
	mul	al
	add	di, ax
	adc	dh, 0
	or	di, di			; look for exact match
	jz	PossibleExactMatch
;
NotExactMatch:
	cmp	lMinHi, dh		; Compare current error term
	ja	SetNewlMin		; with minimal error found previously
	jb	MatchLoopBottom 	; and swap them if necessary
	cmp	lMinLo, di
	ja	SetNewlMin
;
MatchLoopBottom:
	loop	LetsBoogy
	jmp	short ExitCleanup
;
SetNewlMin:
	mov	wIndex, cx
	mov	lMinHi, dh
	mov	lMinLo, di
	loop	LetsBoogy
	jmp	short ExitCleanup
;
PossibleExactMatch:
	or	dh, dh
	jnz	NotExactMatch

        mov     bx, SystemPaletteColors
	sub	bx, cx			    ; it is an exact match
	mov	ax,08000h		    ; exact match flag!!!
	jmp	short EndItNow
;
ExitCleanup:
	xor	ax, ax
	mov	bx,SystemPaletteColors
	sub	bx,wIndex
;
EndItNow:
	xor	bh,bh
	shl	bx,1
	mov	si, DataOFFSET PhysicalIndexTable
	or	ax, [bx+si]		    ; preserve exact match flag!!
	mov	dx, 0ff00h
cEnd

sEnd	Code
;
end
