        page    ,132
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scanlr.asm
;
; Copyright (c) 1991 Microsoft Corporation.  All Rights Reserved.
;
; This module contains the ScanLR routine.
;
; Created: 22-Feb-1987
;
; Exported Functions:	ScanLR
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
;   ScanLR is used to search a scanline for a pixel of the given
;   color or one which isn't of the given color.  This is usually
;   used by the floodfill simulation.
;
; Restrictions:
;
; History:
;	Wed 01-Feb-1989 Extensively modified for 256 color support
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

incDrawMode	= 1			; Include control for gdidefs.inc

	.xlist
	include cmacros.inc
	include gdidefs.inc
	include display.inc
	include macros.mac
	.list
;
; Link time constants describing the size and color format
; that the VGA will be running in.
;
;
ifdef	EXCLUSION
	externFP exclude_far		; Exclude area from screen
	externFP unexclude_far		; Clear excluded area
endif
;
; Define the flag values which control the direction and type of the scan.
;
STEP_LEFT	equ	00000010b	; Flag values for DirStyle
STEP_RIGHT	equ	00000000b
FIND_COLOR	equ	00000001b
FIND_NOT_COLOR	equ	00000000b
;
; Define the type flags used to determine which type of scan needs to be
; performed (color or mono).
;
COLOR_OP	equ	NUMBER_PLANES
MONO_OP 	equ	NOT COLOR_OP	; SO NEVER TO BE EQUAL TO COLOR_OP
;
; Define the error conditions which will be returned
;
ERROR_CLIPPED	equ	8000h		; Cooridnate was clipped
ERROR_NOT_FOUND equ	-1		; Stop condition not reached
;
sBegin	Data
;
	externB enabled_flag		; Non-zero if output allowed
	externW	ColourFormat
;
sEnd	Data
;
;
createSeg _BLUEMOON,BlueMoonSeg,word,public,CODE
sBegin	BlueMoonSeg
assumes cs,BlueMoonSeg
;
rot_bit_tbl	label	byte
		db	10000000b	; Table to map bit index into
		db	01000000b	;   a bit mask
		db	00100000b
		db	00010000b
		db	00001000b
		db	00000100b
		db	00000010b
		db	00000001b
;
;
;--------------------------Exported-Routine-----------------------------;
; ScanLR
;
;   ScanLR - Scan left or right
;
;   Starting at the given pixel and proceeding in the choosen direction,
;   the pixels are examined for the given color until one is found that
;   matches (or doesn't match depending on the style).  The X coordinate
;   is returned for the pixel that matched (or didn't match).
;
;   The physical device may be the screen, a monochrome bitmap, or a
;   bitmap in our color format.
;
;   There will be no error checking to see if the bitmap is in our
;   color format.  If it isn't, it will be treated as if it were a
;   monochrome bitmap.
;
; Entry:
; 	None
; Returns:
;	AX = x location of sought pixel
; Error Returns:
;	AX = -1 if nothing found
;	AX = 8000h if clipped
; Registers Preserved:
;	SI,DI,DS,ES,BP
; Registers Destroyed:
;	AX,BX,CX,DX,FLAGS
; Calls:
;	exclude
;	unexclude
; History:
;	Sun 22-Feb-1987 16:29:09 -by-  Walt Moore [waltm]
;	Created.
;
;-----------------------------------------------------------------------;
	assumes ds,Data
	assumes es,nothing
;
cProc	ScanLR,<FAR,PUBLIC,WIN,PASCAL>,<si,di,es,ds>
;
	parmD	lp_device		; ptr to a physical device
	parmW	x			; x coordinate of search start
	parmW	y			; y coordinate of search start
	parmD	color			; color for the search
	parmW	dir_style		; control and search style
;
	localW	width_bits		; actual width of scan in pixels
	localW	colour_format		; copy of this on stack
	localB	is_device		; set non-zero if the device
	localB	scan_start_bank		; bank for START of scanline
	localB	scan_crosses_bank	; set non-zero if scanline crosses a bank
;
cBegin
;
WriteAux	<'SCANLR'>
;
	mov	al,enabled_flag 	; Load these before trashing DS
	mov	bx,VScreen_Width
	mov	cx,ColourFormat
	mov	colour_format,cx
	lds	si,lp_device		; --> physical device
	assumes ds,nothing
;
	mov	cx,[si].bmType		; Get bitmap type
	mov	[scan_crosses_bank],cl	; Zero this if not the screen!
	jcxz	scan_30 		; Device is a memory bitmap
	mov	is_device,al		; If not enabled, will skip unexclude
	or	al,al			;   since AL will be 0!
	jz	scan_20 		; Disabled, show clipped
;
;
;----------------------------------------
; D I S P L A Y   D E V I C E   S E T U P
;----------------------------------------
;
; This is the VGA.  Compute and set the exclusion rectangle
; based on the direction of the search.
;

ifdef	EXCLUSION			; REMOVE THE CURSOR
	mov	dx,y			; Set top of exclude area
	mov	di,dx			; Set bottom of exclude area
	mov	si,bx			; Set right
	dec	si
	mov	cx,x			; Assume scanning left to right
	test	bptr dir_style,STEP_LEFT
	jz	scan_10 		; Scanning left to right
	mov	si,cx
	xor	cx,cx			; Scanning right to left
;
scan_10:
	call	exclude_far		; Exclude the scan from the screen
;
; Set up the screen/bitMap segment or selector (again)
;
	lds	si,lp_device		; --> physical device
	assumes ds,nothing
endif
;
; The scanning code doesn't scan outside the bounds of the
; surface, however the starting coordinate must be clipped.
;
	mov	ax,y			; Get starting Y coordinate
        cmp     ax,[si].bmHeight        ; Within the surface of the device?
	jae	scan_20 		;   No, return error
        mov     di,[si].bmWidthBytes    ; Need screen width in bytes
	mul	di			; Compute Y starting address
;
	mov	[scan_start_bank],dl
        SET_BANK                        ; do video h/w ram bank select
;
	; check if the scanline crosses a bank boundary
	mov	bx,ax			; get offset within bank
	add	bx,di			; add scanline width
	jz	@F			; doesn't count if the crossing is at the very end!
	sbb	bl,bl			; BL := FFh if carried, 0 otherwise
@@:	mov	[scan_crosses_bank],bl
;
	mov	bx,x			; Will need X later
        mov     dx,[si].bmWidth
	mov	width_bits,dx		; Save width for final bounds test
        mov     ds,[si].bmBits.sel      ; DS:SI --> start of scan
        mov     si,ax                   ; si holds the starting physical Y
        mov     cl,COLOR_OP		; Show mono search code
	cmp	bx,dx			; Within the surface of the device?
	jb	scan_80 		;   Yes
;
; The coordinate is clipped.  Return the clipped error code.
;
scan_20:
	mov	ax,ERROR_CLIPPED	; Set error code
        jmp     scan_exit               ;   and return it
;
;
;-------------------------
; B I T M A P   S E T U P
;-------------------------
;
; The scanning will be for a memory bitmap.  The scanning code
; doesn't scan outside the bounds of the surface,  however the
; starting coordinate must be clipped.
;
; Currently:	DS:SI -> physical device
;		   CX =  0
;		   AL =  enable flag
scan_30:
	mov	is_device,cl		; Show this is a bitmap
	mov	ax,y			; Get starting Y coordinate
	cmp	ax,[si].bmHeight	; Within the surface of the device?
	jae	scan_20 		;   No, return error
	mov	cx,[si].bmWidth 	; Get width in pixels
	cmp	x,cx			; Within the surface of the device?
	jae	scan_20 		;   No, return error
	mov	width_bits,cx		;   Yes, save width in pixels

	xor	dx,dx			; Set segment bias to 0
	mov	cx,[si].bmSegmentIndex	; Is this a huge bitmap?
	jcxz	scan_50 		;   No
;
; This is a huge bitmap. Compute which segment the Y coordinate
; is in. Assuming that no huge bitmap will be bigger than two
; or three segments, iteratively computing the value would be
; faster than a divide, especially if Y is in the first segment
; (which would always be the case for a huge color bitmap that
; didn't have planes >64K).
;
	mov	bx,[si].bmScanSegment	; Get # scans per segment
;
scan_40:
	add	dx,cx			; Show in next segment
	sub	ax,bx			; See if in this segment
	jnc	scan_40 		; Not in current segment, try next
	add	ax,bx			; Restore correct Y
	sub	dx,cx			; Show correct segment
;
; This is a memory DC.  If this is a monochrome memory DC, set up
; the inner loop so that it will terminate after one time through
; and set the color to be equal to the mono bit in the physical
; color. If it is color, set up the inner loop for all planes,
; same as for the display.
;
; Also handle modifying Y for huge bitmaps is necessary.
;
;
; Currently:
; 	AX     =  Y coordinate
; 	DX     =  Segment bias for huge bitmaps
; 	DS:SI --> PDevice
;
scan_50:
	mov	di,[si].bmWidthBytes	; Get index to next plane
	mov	cl,MONO_OP		; Assume mono loop
	mov	bx,colour_format
	cmp	wptr bmPlanes[si],bx
	jne	scan_70 		; Not our color format, treat as mono
	errnz	bmBitsPixel-bmPlanes-1
	mov	cl,COLOR_OP		; Show color loop
;
scan_70:
	add	dx,wptr [si].bmBits[2]	; Compute segment of the bits
	mov	si,wptr [si].bmBits[0]	; Get offset of the bits
	mov	ds,dx			; Set DS:SI --> to the bits
	assumes ds,nothing
;
	mul	di			; Compute start of scan
	add	si,ax			; DS:SI --> start of scanline byte
	mov	bx,x
;
;
;----------------------------------------------------
; C O L O R / M O N O   S E A R C H   D I S P A T C H
;----------------------------------------------------
;
; Currently:
; 	DS:SI --> start of first plane's scan
;	BX     =  X coordinate
;	DI     =  Scan width
;	CL     =  operation type (mono or color)
;
scan_80:
	mov	ax,ds			; Will be working off both DS: and ES:
	mov	es,ax
	assumes es,nothing
	cmp	cl,COLOR_OP		; color manipulation?
	mov	cx,bx			; (load cx with the scan line count)
	je	scan_8bit
        jmp     scan_200                ; no, continue on...

;
;----------------------------------------------------
; C O L O R   D E V I C E / B I T M A P   S E A R C H
;----------------------------------------------------
;
; Currently:	DS:SI --> bitmap or display
;		ES:SI --> bitmap or display
;               BX = X coordinate
;               CX = X coordinate
;		DI = scan line width
;
scan_8bit:
	xchg	di,si			; we will use SCAS instructions
	mov	ax,bx
	cwd
	mov	bx,[colour_format]
	shiftr	bx,8+3			; BX := bytes per pixel
	mul	bx			; AX counts bytes

	mov	bh,[scan_crosses_bank]	; need to check this again

        add     di,ax                   ; ES:DI --> byte with start pixel
	jnc	@F
	mov	dl,[scan_start_bank]
	inc	dl
	SET_BANK

	; if we're going right, then we don't need to worry about
	; crossing again...
	test	dir_style,STEP_LEFT
	jnz	scan_xbit_pickfunc
	xor	bh,bh
	jmp	short scan_xbit_pickfunc

@@:	; no bank crossing to the left of our starting point,
	; so if we're going left, we don't need to worry about that
	test	dir_style,STEP_LEFT
	jz	scan_xbit_pickfunc
	xor	bh,bh

scan_xbit_pickfunc:
	dec	bl
	shl	bl,1			; index into scas_colour_table
	and	bh,8			; to select the "checked" functions
	or	bl,bh
	xor	bh,bh
	mov	si,cs:scas_colour_table[bx]
;
; Set cx to be the byte count for searching left.  Must adjust it
; to include the byte pixel is in.
;
;dx:ax  - color to search for
;   cx  - remaining pixel count
;
        std                             ; set flag for left movement
	mov	bx,-1			; set negative increment for DI
        test    dir_style,STEP_LEFT     ; moving left?
        jnz     scan_8bit_start         ; yes is left

        cld                             ; no, clear for right movement
	mov	bx,1			; set positive increment for DI
        sub     cx,width_bits           ; calc length to right
        not     cx

scan_8bit_start:
        inc     cx
        mov     ax,color.lo		; load the colour
        mov     dx,color.hi		; load the colour

        test    dir_style, FIND_COLOR   ; looking for a match?
        jz      scan_8bit_find_not_loop ; no, go to other loop

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;   we are searching for pixel that is the given color
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
scan_8bit_find_loop:
	call	si			; SCAS the pixel
        je      scan_found
        loop    scan_8bit_find_loop
        jmp     scan_not_found          ; hey! not found

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;   we are searching for pixel that is not the given color
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
scan_8bit_find_not_loop:
	call	si			; SCAS the pixel
        jne     scan_found
        loop    scan_8bit_find_not_loop
        jmp     scan_not_found          ; hey! not found

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;   we have found a pixel, cx contains the X coordinate if we were searching
;   LEFT or the distance from the right edge if searching RIGHT
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
scan_found:
        dec     cx
        mov     ax,cx
        test    dir_style,STEP_LEFT     ; moving left?
        jnz     scan_found_left         ; yes is left

        sub     ax,width_bits           ; calc length to right
        not     ax

scan_found_left:
        jmp     scan_exit               ; good search...

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;   we have failed to find the requested pixel because we stepped off
;   the right or left edge of the bitmap.
;
;   if we stepped off the right side of the bitmap return width_bits
;
;   if we stepped off the left side of the bitmap return (-1)
;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
scan_not_found:
        mov     ax,ERROR_NOT_FOUND      ; return (-1) for left
        test    dir_style,STEP_LEFT
        jnz     scan_not_found_left
        mov     ax,width_bits           ; return width_bits for right

scan_not_found_left:
        jmp     scan_exit
;
;
;--------------------------------------------------------------
; M O N O C H R O M E   D E V I C E / B I T M A P   S E A R C H
;--------------------------------------------------------------
;
; The desired action of the scan is to be able to do a rep scasb
; over the scanline until either the color is found or not found.
; Once the stopping condition is found, it has to be possible to
; determine which bit was the bit that stopped the scan.
;
; Monochrome notes:
;
;	The color will be used as an XOR mask.  If the result of
;	the XOR is zero, then the byte did not contain any bits of
;	importance, otherwise we made a hit and need to return the
;	location of it.
;
;	If searching for the color, the color must be complemented
;	so that the XOR will set all bits not of the color to zero,
;	and leave all bits of the color 1's.  If searching for NOT
;	the color, then the color can be left as is so that all bits
;	of the color will be set to zero.  The complement also gives
;	the compare value for the scasb instruction.
;
scan_200:
	shiftr	cx,3			; do 8 pixels per byte
	add	si,cx			; DS:SI --> byte with start pixel
;
; Set cx to be the byte count for searching left.  Must adjust it
; to include the byte pixel is in.
;
	inc	cx			; Adjust for partial byte
;
; Compute the mask for the first byte (the partial byte).  Since
; the defaults being set up are for searching left, this can be done
; by getting the rotating bitmask for the pixel and decrementing it,
; then using the logical NOT of the mask.  The mask will be used
; for masking the bits to test in the partial (first) byte.
;
;	Bitmask 	  Mask		NotMask
;
;	10000000	01111111	10000000
;	01000000	00111111	11000000
;	00100000	00011111	11100000
;	00010000	00001111	11110000
;	00001000	00000111	11111000
;	00000100	00000011	11111100
;	00000010	00000001	11111110
;	00000001	00000000	11111111
;
	and	bx,00000111B		; Get bit mask for bit
	mov	bl,rot_bit_tbl[bx]	; Assume we're going left.
	dec	bl			; Create mask
;
; The assumption has been made that the scan will be right to left.
; If the scan is left to right, then the first byte mask and the
; byte count must be adjusted.
;
; Also set up the correct bias for getting back to the interesting
; byte for the rep scasb instruction (DI is always updated by one
; byte too many).
;
	std				; Assume search left
	mov	dx,1			; (to counter post decrement)
	test	bptr dir_style,STEP_LEFT
	jnz	scan_205		; It is left
;
; Compute the first byte mask for the first byte for stepping right.
;
;	Current 	  SHL		  INC		  NOT
;
;	01111111	11111110	11111111	00000000
;	00111111	01111110	01111111	10000000
;	00011111	00111110	00111111	11000000
;	00001111	00011110	00011111	11100000
;	00000111	00001110	00001111	11110000
;	00000011	00000110	00000111	11111000
;	00000001	00000010	00000011	11111100
;	00000000	00000000	00000001	11111110
;
	cld				; Going right, fix up dir flag
	shl	bl,1			; Fix up first bit mask per above
	inc	bl
	not	bl
;
; Compute the number of bytes from current position to end of scanline
; and set adjustment to counter the rep's post increment
;
	sub	cx,di			; Fix up byte count
	neg	cx
	inc	cx
	neg	dx			; (to counter post increment)
;
; Set the pixel count for the entire scan.  The scanning will actually
; continue until the end of the scan as given in bmWidthBytes, and
; the result clipped to bmWidth.
;
; Currently:	DS:SI --> bitmap or display
;		ES:SI --> bitmap or display
;		BL = first byte mask
;		CX = byte count
;		DX = direction bias
;		DI = bits/scanline
;
scan_205:
	not	bl			; Need inverse of the first byte mask
	shiftl	di,3			; Set DI = pixel count of entire scan
;
	mov	ah,bptr dir_style	; If searching for the color,
	shr	ah,1			;   want a mask of 1's to be
	sbb	ah,ah			;   able to invert the result
;
	errnz	FIND_NOT_COLOR		;   of the search
	errnz	FIND_COLOR-1
;
	mov	al,color.SPECIAL	; Get mono search color
	shr	al,1
	errnz	MONO_BIT-00000001b
;
	sbb	al,al
	xor	ah,al			; Invert search color if needed
;
; Check the first byte for a hit or miss.
;
scan_210:
	lodsb				; Get the first byte
	xor	al,ah			; Adjust the color
	and	al,bl			; Mask out the bits that don't count
	jnz	scan_230		;   Hit.  Check it out
;
	mov	al,ah			; Otherwise restore register for scan
	dec	cx			; Any bytes left to check?
        jz      scan_not_found          ;   No, show not found
;
	xchg	si,di			; scasb uses ES:DI
	repe	scasb			; Try for a hit or miss
        jz      scan_not_found          ; Scanned off the end, it's a miss
	inc	cx			; Decremented one time too many
	xchg	si,di
	add	si,dx			; Adjust from post increment/decrement
	lodsb				; Get the byte which we hit on
	xor	al,ah			; Adjust to look for a set bit
;
; Had a hit.  Find which pixel it was really in.
;
; Currently:	CX = byte index pixel is in
;		DI = # pixels in the scan line
;		AL = byte hit was in
;
scan_230:
	shiftl	cx,3			; Convert byte index to pixel index
	test	bptr dir_style,STEP_LEFT;Scanning Right to left?
	jnz	scan_260		;   yes
;
scan_240:
	sub	cx,di			; Compute index of first pixel in byte
	not	cx
;
scan_250:
	inc	cx			; Show next pixel
	shl	al,1			; Was this the hit?
	jnc	scan_250		;   No, try next
	cmp	cx,width_bits		; Is final x value in range?
        jge     scan_not_found          ;   No, show not found
	jmp	short scan_270		;   Yes, return it
;
scan_260:
	dec	cx			; Show next pixel
	shr	ax,1			; Was this the hit?
	jnc	scan_260		;   No, try next
;
scan_270:
	mov	ax,cx			; Return position to caller
;
scan_exit:
        cld

ifdef	EXCLUSION			; If exclusion
	test	is_device,0FFh		; Is this the device?
	jz	scan_290		;   No, skip this stuff

        call    unexclude_far           ; Clear any exclude rectangle

scan_290:
endif

cEnd

;--------------------------Public-Routine------------------------------;
; scas_colour
;
;   Check one pixel of colour in DX:AX
;
; Entry:
;       DX:AX	= physical colour
;	BX	= +1 if UP, -1 if DN
;	ES:DI --> colour buffer to check
; Returns:
;       ZF set or clear
; Error Returns:
;       None
; Registers Preserved:
;       ES,DS,BP,AX,BX,CX,DX,SI
; Registers Destroyed:
;       DI,FLAGS
; Calls:
;       None
; History:
;       See Git.
;
;-----------------------------------------------------------------------;
;
;
;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;
;
        assumes ds,nothing
        assumes es,nothing

scas_colour1_checked	proc near
	sar	bl,1	; BX := 0 if UP, -1 if DN
	cmp	di,bx	; is DI at the beginning of a bank?
	jne	@F

	GET_BANK
	or	bl,1	; restore BX
	add	dx,bx
	SET_BANK
	; we've crossed the bank, no more checking needed!
	mov	si,offset scas_colour1

@@:	or	bl,1	; restore BX
	; fall through
scas_colour1_checked	endp
scas_colour1	proc near
	scasb
	ret
scas_colour1	endp

scas_colour2_checked	proc near
	sar	bl,1	; BX := 0 if UP, -1 if DN
	and	bl,0FEh	; -2 if DN
	cmp	di,bx	; is DI at the beginning of a bank?
	jne	@F

	GET_BANK
	or	bl,1	; restore BX
	add	dx,bx
	SET_BANK
	; we've crossed the bank, no more checking needed!
	mov	si,offset scas_colour2

@@:	or	bl,1	; restore BX
	; fall through
scas_colour2_checked	endp
scas_colour2	proc near
	scasw
	ret
scas_colour2	endp

scas_colour3_checked	proc near
	test	bh,bh
	js	scas_colour3_check_neg

	; UP: check if DI is -2, -1 or 0
	test	di,di
	jnz	@F
	; if it's zero, we just cross and load a full colour
	jmp	scas_colour3_simple_crossing

@@:	cmp	di,-2
	jnb	@F
	jmp	scas_colour3

@@:	; if it's -2 or -1, the pixel itself crosses the bank
	ja	scas_colour3_up_bytethenword
	; if it's -2, we check one word, cross, then one byte
	scasw
	pushf		; save SCAS result
	push	dx	; preserve upper byte of colour!
	GET_BANK
	inc	dl
	SET_BANK
	pop	dx	; restore upper byte of colour
	popf		; restore SCAS result
	; we've crossed the bank, no more checking needed!
	mov	si,offset scas_colour3
	mov	di,1	; we know where DI goes next
	; if comparison failed we're done
	jne	@F
	; otherwise check upper byte too
	cmp	es:[0],dl
@@:	ret

scas_colour3_up_bytethenword:
	; if it's -1, we check one byte, cross, then one word
	scasb
	pushf		; save SCAS result
	push	dx	; preserve upper byte of colour!
	GET_BANK
	inc	dl
	SET_BANK
	pop	dx	; restore upper byte of colour
	popf		; restore SCAS result
	; we've crossed the bank, no more checking needed!
	mov	si,offset scas_colour3
	mov	di,2	; we know where DI goes next
	; if comparison failed we're done
	jne	@F
	; otherwise check upper word too
	mov	dh,dl
	mov	dl,ah
	cmp	es:[0],dx
	mov	dl,dh	; restore DL
@@:	ret

scas_colour3_check_neg:
	; DN: check if DI is -1, -2 or -3
	cmp	di,-3
	; if it's -3, we just cross and load a full colour
	je	scas_colour3_simple_crossing
	ja	@F
	jmp	scas_colour3

@@:	; if it's -2 or -1, the pixel itself crosses the bank
	cmp	di,-2
	ja	scas_colour3_dn_wordthenbyte
	; if it's -2, we check one byte, cross, then one word
	cmp	es:[0],dl
	pushf		; save CMP result
	push	dx	; preserve upper byte of colour!
	GET_BANK
	dec	dl
	SET_BANK
	pop	dx	; restore upper byte of colour
	popf		; restore SCAS result
	; we've crossed the bank, no more checking needed!
	mov	si,offset scas_colour3
	mov	di,-5	; we know where DI goes next
	; if comparison failed we're done
	jne	@F
	; otherwise check lower word too
	cmp	es:[-2],ax
@@:	ret

scas_colour3_dn_wordthenbyte:
	; if it's -1, we check one word, cross, then one byte
	mov	dh,dl
	mov	dl,ah
	cmp	es:[0],dx
	mov	dl,dh	; restore DL
	pushf		; save CMP result
	push	dx	; preserve upper byte of colour!
	GET_BANK
	dec	dl
	SET_BANK
	pop	dx	; restore upper byte of colour
	popf		; restore SCAS result
	; we've crossed the bank, no more checking needed!
	mov	si,offset scas_colour3
	mov	di,-4	; we know where DI goes next
	; if comparison failed we're done
	jne	@F
	; otherwise check lower word too
	cmp	es:[-1],al
@@:	ret

scas_colour3_simple_crossing:
	push	dx	; preserve upper byte of colour!
	GET_BANK
	add	dx,bx
	SET_BANK
	pop	dx	; restore upper byte of colour
	; we've crossed the bank, no more checking needed!
	mov	si,offset scas_colour3
	; fall through
scas_colour3_checked	endp
scas_colour3	proc near
	cmp	dl,es:[di+2]
	je	@F	; if upper byte matches, go check lower word
	; nothing matches, skip the entire pixel (3 bytes)
	lea	di,[bx+di]
	lea	di,[bx+di]
	lea	di,[bx+di]
	ret

@@:	scasw
	; DI has been advanced by two bytes, need to advance it by a third
	lea	di,[bx+di]
	ret
scas_colour3	endp

scas_colour4_checked	proc near
	sar	bl,1	; BX := 0 if UP, -1 if DN
	and	bl,0FCh	; -4 if DN
	cmp	di,bx	; is DI at the beginning of a bank?
	jne	@F

	push	dx	; preserve upper half of colour!
	GET_BANK
	sar	bl,1	; 0 or -2
	inc	bl	; restore BX
	add	dx,bx
	SET_BANK
	pop	dx	; restore upper half of colour
	; we've crossed the bank, no more checking needed!
	mov	si,offset scas_colour4

@@:	sar	bl,1	; 0 or -2
	inc	bl	; restore BX
	; fall through
scas_colour4_checked	endp
scas_colour4	proc near
	cmp	dx,es:[di+2]
	je	@F	; if upper byte matches, go check lower word
	; nothing matches, skip the entire pixel (4 bytes)
	shl	bx,2
	lea	di,[bx+di]
	sar	bx,2	; clears ZF
	ret

@@:	scasw
	; DI has been advanced by two bytes, need to advance it by two more
	; while preserving ZF
	lea	di,[bx+di]
	lea	di,[bx+di]
	ret
scas_colour4	endp

scas_colour_table	label word
	dw	offset	scas_colour1
	dw	offset	scas_colour2
	dw	offset	scas_colour3
	dw	offset	scas_colour4
	dw	offset	scas_colour1_checked
	dw	offset	scas_colour2_checked
	dw	offset	scas_colour3_checked
	dw	offset	scas_colour4_checked

sEnd	BlueMoonSeg
        end
