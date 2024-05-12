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
	include gdidefs.inc
	include display.inc
	include	macros.mac
;
	externA		BW_THRESHOLD
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
	assumes ds, nothing
	assumes es, nothing
;
	extrn	_cstods:word		; our data segment
        externB ??BigFontFlags
	externW	pxbytes
	externB	red_shr
	externB	red_shl
	externB	green_shr
	externB	green_shl
	externB	blue_shr
	externB	blue_shl

;
; At this point,
;    AL contains the RED intensity that we're going to use.
;    AH contains the GREEN intensity that we're going to use.
;    DL contains the BLUE intensity that we're going to use.
;    DH contains the colour index.
;
cProc	rgb_to_ipc, <NEAR, PUBLIC>, <si, di, cx, bx>
	localW	lMinLo
	localW	wIndex
	localB	lMinHi
;
cBegin
	WriteAux <'rgb-to_ipc'>

	mov	bx, ax			; logical colors are in
        sub     cx, cx                  ; bl: red, bh: green, dl: blue

	cmp	[red_shr],-1
	je	@F
	jmp	NoPalette

@@:	; We only need the DS for the palette
	push	ds
	mov	ds,cs:_cstods
	assumes	ds,Data

	; PluM: Why is this restricted to system colours?
	; Is it because other colours could change at a moment's notice?
	; I'm too afraid to change it tbh...
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
	mov	ch, ah			    ; preserve accels to return ZF/CF

	; DS no longer needed since we're done with the palette
	pop	ds
	assumes	ds,nothing
	jmp	RGB2IPC_Done

NoPalette:
	; Here BL=red, BH=green, DL=blue
	; Store the out colour in SI:DI
	xor	si,si
	mov	di,si
	; And keep the accelerator bits in CH:
	; initially assume all ones or zeros, until we find out otherwise!
	mov	ch,ONES_OR_ZEROS

	; do red:
	mov	al,bl
	mov	ah,al
	mov	cl,red_shr
	shr	al,cl	; AL := actual colour data
	sar	ah,cl	; AH := sign-extended colour to check all 1s or 0s
	mov	dh,ah	; keep track of this
	mov	cl,red_shl
	call	colour_contribution

	; do green:
	mov	al,bh
	mov	ah,al
	mov	cl,green_shr
	shr	al,cl	; AL := actual colour data
	sar	ah,cl	; AH := sign-extended colour to check all 1s or 0s
	cmp	ah,dh	; is the sign-extended green equal to the red?
	je	@F
	and	ch,NOT ONES_OR_ZEROS	; if not, it can't be "all" one or zero!
@@:	mov	cl,green_shl
	call	colour_contribution

	; do blue:
	mov	al,dl
	mov	ah,al
	mov	cl,blue_shr
	shr	al,cl	; AL := actual colour data
	sar	ah,cl	; AH := sign-extended colour to check all 1s or 0s
	cmp	ah,dh	; is the sign-extended blue equal to the red?
	je	@F
	and	ch,NOT ONES_OR_ZEROS	; if not, it can't be "all" one or zero!
@@:	mov	cl,blue_shl
	call	colour_contribution

	; also do a straight sum on the colours to determine the mono bit
	mov	al,bl
	xor	ah,ah
	add	al,bh
	adc	ah,0
	add	al,dl
	adc	ah,0
	cmp	ax,BW_THRESHOLD
	jb	@F

	; OK, it's white!
	or	ch,MONO_BIT

@@:
	; return the colour
	mov	dx,si
	mov	ax,di

RGB2IPC_Done:
	; use flags to return the accelerators
	xor	ch,ONES_OR_ZEROS
	test	ch,ONES_OR_ZEROS	; ZF:=ONES_OR_ZEROS
	rcr	ch,1			; CF:=MONO_BIT
	; now to get the accelerators back, the caller can do:
	; setz	<reg>
	; rcl	<reg>,1
cEnd

; Take a colour component (R/G/B) in AL, and OR it into SI:DI shifted left by CL
; Also clear ONES_OR_ZEROS flag in CH if AH is not all ones or zeros
colour_contribution	proc near
	test	ah,ah	; is AH all zeros?
	jz	@F
	inc	ah	; is it all ones?
	jz	@F
	; nope, clear the flag!
	and	ch,NOT ONES_OR_ZEROS

@@:
	test	[??BigFontFlags],-1
	jz	@@hard_way

	.386
	push	eax
	movzx	eax,al
	shl	eax,cl
	or	di,ax
	shr	eax,10h
	or	si,ax
	pop	eax
	ret

@@hard_way:
	.286
	; We're on a 286, need to restrict ourselves to 16-bit registers...
	; There are three cases to deal with:
	; 1. CL <= 8 --> just SHL AX,CL and OR into DI
	; 2. CL >= 16 --> just SHL AX,(CL-16) and OR into SI
	; 3. 8 < CL < 16 --> multiple steps involved...
	cmp	cl,8
	jna	@@simple_di
	cmp	cl,10h
	jnb	@@simple_si

	; OK, life is complicated!
	push	ax
	call	@@simple_di	; do the easy bit first
	pop	ax
	sub	cl,10h
	neg	cl		; CL:=(16-CL)
	shr	ax,cl		; shift it right by that much
	jmp	@@exit_si

@@simple_di:
	shl	ax,cl
	or	di,ax
	ret

@@simple_si:
	sub	cl,10h
	shl	ax,cl
@@exit_si:
	or	si,ax
	ret
colour_contribution	endp

;
; Takes physical colour in DX:AX, and upon return,
;    AL contains the RED intensity.
;    AH contains the GREEN intensity.
;    DL contains the BLUE intensity.
;    DH contains the accelerator flags.
;
public	ipc_to_rgb_far
ipc_to_rgb_far	proc far
	call ipc_to_rgb
	retf
ipc_to_rgb_far	endp
;
cProc	ipc_to_rgb, <NEAR, PUBLIC>, <si, di, cx, bx>
;
cBegin
	assumes	ds,nothing
	WriteAux <'ipc-to_rgb'>

	; check again for system palette colour
	; usually, DH==FFh indicates palette index, but if we have four bytes
	; per pixel, it instead encodes actual colour data.
	cmp	[pxbytes],4
	je	@F
	cmp	dh,0FFh
	jne	@F

; the color value we want to return is in Palette (the VGA simulated
; colors).  so convert the index to the 20 entry table of TRIPLES and
; get the color.

	mov	bh,ah			; save the accel flags
	xor	ah,ah
	cmp	ax,10
	jl	lower_end
	cmp	ax,245
	jle	non_sys_colour
	sub	ax,236			; shift upper-256 indices to upper-20

lower_end:
	; get us access to Palette
	push	ds
	mov	ds,cs:_cstods
	assumes	ds,Data

	mov	si,ax
	shl	si,1
	add	si,ax			; index into a TRIPLEs table
	mov	ax,word ptr Palette[si+0]
	mov	dx,word ptr Palette[si+2]

	pop	ds
	assumes	ds,nothing
	jmp	short @@ret_accel

non_sys_colour:
	; Return the index unaltered (match old ColorInfo behaviour).
	; The purpose appears to be to allow GDI clients to setup custom colours
	; in the VGA palette and make brushes / pens with them, without GDI
	; needing to know their true values. Strange, but OK...
	mov	ah,bh			; get the accelerators back into AH
	xor	dx,dx
	mov	bh,-1			; set up FFh "index" sig to put in DH
	jmp	short @@ret_accel

@@:
	; set up to invert the operation of colour_contribution above
	mov	si,dx
	mov	di,ax

	; firstly, is it all zero?
	mov	bh,ONES_OR_ZEROS	; MONO_BIT set to zero
	or	ax,dx
	jz	@@ret_accel

	; extract blue:
	mov	cl,blue_shl
	call	ext_colour_contribution
	mov	cl,blue_shr
	test	cl,cl
	jz	@F
	call	rest_colour_8bit
@@:	mov	dl,al
	mov	bh,al	; track whether or not it's all ones

	; extract green:
	mov	cl,green_shl
	call	ext_colour_contribution
	mov	cl,green_shr
	test	cl,cl
	jz	@F
	call	rest_colour_8bit
@@:	mov	bl,al	; can't use AH since it gets destroyed below
	and	bh,al	; track whether or not it's all ones

	; extract red:
	mov	cl,red_shl
	call	ext_colour_contribution
	mov	cl,red_shr
	test	cl,cl
	jz	@F
	call	rest_colour_8bit
@@:	; nothing, AL is already red! :)
	mov	ah,bl	; but we have to restore green from BL!
	and	bh,al	; track whether or not it's all ones

	inc	bh	; if it's all ones, this sets ZF
	mov	bh,ONES_OR_ZEROS OR MONO_BIT
	jz	@@ret_accel

	; no shortcuts, need to determine MONO_BIT here
	; do a straight sum on the colours to determine the mono bit
	mov	bl,al
	xor	bh,bh
	add	bl,ah
	adc	bh,0
	add	bl,dl
	adc	bh,0
	cmp	bx,BW_THRESHOLD

	mov	bh,0
	jb	@@ret_accel
	; OK, it's white!
	or	bh,MONO_BIT

@@ret_accel:
	mov	dh,bh
	assumes	ds,nothing
cEnd

; Inverse operation of colour_contribution above: extract a colour component
; from bits CL-(CL+7) of SI:DI and put it in AL (clearing AH).
ext_colour_contribution	proc near
	test	[??BigFontFlags],-1
	jz	@@ext_hard_way

	.386
	push	ebx
	mov	bx,si
	shl	ebx,10h
	mov	bx,di
	shr	ebx,cl
	movzx	ax,bl
	pop	ebx
	ret

@@ext_hard_way:
	.286
	; We're on a 286, need to restrict ourselves to 16-bit registers...
	; There are three cases to deal with:
	; 1. CL <= 8 --> just copy DI into AX and SHR AX,CL
	; 2. CL >= 16 --> just copy SI into AX and SHR AX,(CL-16)
	; 3. 8 < CL < 16 --> multiple steps involved...
	cmp	cl,8
	jna	@@ext_simple_di
	cmp	cl,10h
	jnb	@@ext_simple_si

	; OK, life is complicated!
	call	@@ext_simple_di	; do the easy bit first
	sub	cl,10h
	neg	cl		; CL:=(16-CL)
	push	bx
	mov	bx,si
	shl	bx,cl		; shift it left by that much
	or	al,bl
	pop	bx
	ret

@@ext_simple_di:
	mov	ax,di
	shr	ax,cl
	xor	ah,ah
	ret

@@ext_simple_si:
	sub	cl,10h
	mov	ax,si
	shr	ax,cl
	xor	ah,ah
	ret
ext_colour_contribution	endp

; Restore a colour component in AL to its full eight bits, by left-shifting CL
; bits; rounds up if result >= 80h
rest_colour_8bit	proc near
	; need to shift left; use resulting sign bit to decide value of LSBs
	inc	cl	;shift one too far to get the sign bit into CF
	shl	al,cl
	jnc	@F
	shr	al,cl	;go back
	inc	al	;add one to round up
	shl	al,cl	;shift again
	dec	al	;fill all the LSBs with ones
@@:	ror	al,1	;if we jumped to here, MSB will get zero by default
	dec	cl
	ret
rest_colour_8bit	endp

; Sequence functions to help creating colour palettes and/or translating 24-bit
; bitmaps to/from device format.
cProc	rgb_to_ipc_seq, <FAR,PUBLIC,NODATA>
	; local variables as a cache
	localD	previous_rgb
	localD	previous_ipc
cBegin
	; Call rgb_to_ipc_seq as follows:
	; * DS:SI -> sequence of RGB colours
	; * ES:DI -> output sequence of physical colours
	; * CX = number of colours to process
	; * BH = input flags (1 = 4 bytes per pixel, 2 = swap red/blue)
	; * BL = output bits per pixel | flag (LSB indicates monochrome value)

	; initialize "previous" values as -1, to be overwritten immediately
	mov	ax,-1
	mov	[previous_rgb].lo,ax
	mov	[previous_rgb].hi,ax
	mov	[previous_ipc].lo,ax
	mov	[previous_ipc].hi,ax

rgb_load_loop:
	; prepare to load next colour
	xor	ax,ax
	cwd

	lodsw
	mov	dx,ax
	lodsb
	shl	ax,8	; get AL into AH, and zero out AL itself
	test	bh,1
	jz	@F
	; load fourth byte into AL if needed
	lodsb
@@:	;Now we have:
	; DL = red (or blue)
	; DH = green
	; AH = blue (or red)
	; AL = 0
	;We want:
	; AL = red
	; AH = green
	; DL = blue
	; DH = 0
	xchg	al,ah	;get blue (or red) in AL
	xchg	ah,dh	;get green in AH as needed
	test	bh,2
	jnz	@F
	; if we're NOT swapping red and blue, then we DO need to swap AL/DL!
	xchg	al,dl
@@:	;Now we're ready to call rgb_to_ipc
	; but first, let's check the cache...
	cmp	ax,[previous_rgb].lo
	jne	@F
	cmp	dx,[previous_rgb].hi
	jne	@F

	mov	ax,[previous_ipc].lo
	mov	dx,[previous_ipc].hi
	jmp	short store_ipc

@@:
	;OK, we didn't use the cache, but set it for the next round:
	mov	[previous_rgb].lo,ax
	mov	[previous_rgb].hi,dx

	;Convert the colour!
	call	rgb_to_ipc
	;Save the MONO_BIT in the MSB of BL, and rotate the mono output flag
	; out into CF
	rcr	bl,1
	jnc	@F
	rcl	bl,1	; get MONO_BIT back into CF
	sbb	ax,ax	; convert single bit to word
	cwd		; and to dword!
	jmp	short cache_ipc
@@:
	shl	bl,1	; restore original BL (which had LSB unset)
cache_ipc:
	mov	[previous_ipc].lo,ax
	mov	[previous_ipc].hi,dx
store_ipc:
	test	bl,20h	; storing 32 bits?
	jz	@F
	stosw
	mov	ax,dx
	jmp	short next_word
@@:
	test	bl,10h	; storing (at least) 16 bits?
	jz	@F
next_word:
	stosw
	mov	al,dl
@@:
	test	bl,8	; storing an odd number of bytes?
	jz	@F
	stosb
@@:
	loop	rgb_load_loop

cEnd

sEnd	Code
;
end
