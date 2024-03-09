;
;-----------------------------------------------------------------------;
; This file contains the code for the following few functions in the	;
; palette manager module:						;
;		SetPaletteTranslate ---	Sets the translate table	;
;		GetPaletteTranslate ---	Gets the current translate table;
;		TranslateBrush	    ---	Tranlates indices in a brush	;
;		TranslateTextColor  ---	Translates color in DRAWMODE	;
;		TranslatePen	    ---	Translates indices in a pen	;
;		UpdateColor	    ---	Translate a rect on the screen	;
;-----------------------------------------------------------------------;
;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.
        public  TranslateBrush
	public	TranslateTextColor
	public	TranslatePen
;
incDrawMode = 1				; include the drawmode definitions
;
	.286
        .xlist
	include	cmacros.inc
	include	macros.mac
	include gdidefs.inc
	include display.inc
	include cursor.inc
	include	ega.inc
	.list
;
	externFP exclude_far
	externFP unexclude_far
	externFP far_set_bank_select
	externFP setramdac
;
sBegin	Data
;
; the following variables and values are defined in .\egahires\egahires.asm
; and in .\vga\vga.asm for the ega and vga drivers respectively.
;
	EXTRN	ScreenSelector:word
	externA	NUM_PALETTES
	externA BW_THRESHOLD
	externB	PaletteTranslationTable
	externB	PaletteIndexTable
	externB	PaletteModified
	externB TextColorXlated
	externB device_local_brush
	externB device_local_drawmode
	externB device_local_pen
	externD adPalette
        externB abPaletteAccl
	externB enabled_flag
	externW MemWidth
;

PUBLIC	dac_size
dac_size	DB	0,0	  ;byte quantity but maintain word alignment

sEnd    Data
;
createSeg _PALETTE,PaletteSeg,word,public,CODE
;
sBegin	PaletteSeg
	assumes cs,PaletteSeg
	assumes	ds,nothing
	assumes	es,nothing
;
;-----------------------------------------------------------------------;
;				SetPaletteTranslate			;
;				-------------------			;
;	Sets up the palette tranlation table in own data segment to be	;
;	used by subsequent draw calls.					;
;									;
;	Parameters:							;
;		wNumEntries --	Number of entries in the table. 	;
;									;
;		lpTranslate --	A long pointer to the translate table	;
;				A NULL initializes the table(this case)	;
;				ignore the first parameter		;
;	Returns:		 					;
;		A zero in AX (success)					;
;		Fills in the Translate table in own data segment	;
;									;
;	History:							;
;		Modified to suite 4 plane EGA/VGA drivers.		;
;		-by- Amit Chatterjee [amitc] Thu 01-Dec-1988 09:00:00	;
;									;
;		Created.						;
;		-by- Amit Chatterjee [amitc] Thu 03_Nov-1988 13:50:15	;
;-----------------------------------------------------------------------;
;
cProc	SetPaletteTranslate,<FAR,PUBLIC,WIN,PASCAL>,<si,di,es,ds>
	assumes	ds,Data
	assumes	es,nothing
	parmD	lpTranslate	; long pointer to color translate table
;
cBegin
WriteAux <'SPalXlate'>
	cld
;	
;-----------------------------------------------------------------------;
; get a pointer to the translate table in our own data segment in ES:DI	;
;-----------------------------------------------------------------------;
;
	mov	ax,ds			; get our own data segment
	mov	es,ax
;
	assumes es,nothing

	lds	si,lpTranslate		; load the translation table pointer
	mov	ax,ds			; DS:SI = NULL means initialize table
	or	ax,si		
	jnz	set_translate_table

; the identity map

	sub	bx,bx			; zero base to palettetranslationtable
        mov     cx,NUM_PALETTES         ; no of indices to copy
sepatr_05:
	mov	es:PaletteTranslationTable[bx],bl ;save the xlat table
	mov	es:PaletteIndexTable[bx],bl	  ; save the reverse index
	inc	bx				  ; move to the next entry
	loop	sepatr_05
	mov	es:PaletteModified,0	   ; reset
	jmp	SetPaletteTranslate_Ret

set_translate_table:
	mov	cx,NUM_PALETTES 	; no of indices to copy
	lea	di	,[PaletteTranslationTable]


@@:
	lodsw
	stosb
	loop	@b

; construct the inverse table; do not modify system indexes; go backwards

IF	0
	mov	cx,NUM_PALETTES - 20	; no of indices to copy
	mov	si	,245
ELSE
	mov	cx,NUM_PALETTES 	; no of indices to copy
	mov	si	,255
ENDIF
	sub	bh	,bh

sepatr_06:
	mov	bl	,es:[si][PaletteTranslationTable]

IF      0
	cmp	bl	,10
	jb	sepatr_07
	cmp	bl	,245
	ja	sepatr_07
ENDIF
	mov	ax	,si
	mov	es:[bx][PaletteIndexTable] ,al
sepatr_07:
        dec     si
	loop	sepatr_06

	mov	es:PaletteModified,0ffh    ; palette has been modified

SetPaletteTranslate_Ret:
	xor	ax,ax			; set the success code
	cwd

cEnd
;
;-----------------------------------------------------------------------;
;			GetPaletteTranslate				;
;			-------------------				;
;	Returns the drivers palette translation table.			;
;									;
;	Parameters:							;
;		lpTranlate -- a long pointer to a buffer to store the	;
;			      translation table.			;
;	Returns:		 					;
;		A zero in AX (success)					;
;		A 0FFH in AX if a NULL pointer was passed in		;
;		Fills in the Translate table in the buffer provided	;
;									;
;	History:							;
;		Created.						;
;		-by- Amit Chatterjee [amitc] Thu 03_Nov-1988 14:42:50	;
;-----------------------------------------------------------------------;
;
cProc	GetPaletteTranslate,<FAR,PUBLIC,WIN,PASCAL>,<si,di,es>
	assumes	ds,Data
	assumes	es,nothing
	parmD	lpTranslate	; long pointer to translate table 
;
cBegin
WriteAux <'GPalXlate'>
	cld
;	
	les	di,lpTranslate	; ES:DI points to GDI buffer
	mov	ax,es
	or	ax,di		; A NULL ptr is invalid
	jz	GetPaletteTranslate_Ret
;
; DS is already our own segment, set SI to point to the translation table
;
	mov	si,DataOFFSET PaletteTranslationTable
;
; now copy the indices
;
	mov	cx,NUM_PALETTES
	sub	ah,ah
;
gepatr_05:
	lodsb			; read bytes
	stosw			; write words
	loop	gepatr_05
;
	mov	ax,1		; will be turned to zero below
;
GetPaletteTranslate_Ret:
	dec	ax		; set success/failure code
	cwd

cEnd
;
;-------------------------------------------------------------------------;
;				TranslateBrush				  ;
;				--------------				  ;
;	Creates a new brush structure in local datasegment from the brush ;
;	pattern passed in by any of the output routines and the current	  ;
;	translate table.						  ;
;									  ;
;	Parameters:							  ;
;		lpBrush	-- A long pointer to an OEM brush structure	  ;
;	Returns:							  ;
;		DX:AX	-- A long pointer to the re-realized brush	  ;
;									  ;
;	History:							  ;
;		Created.						  ;
;		 -by- Amit Chatterjee [amitc] Thu 03_Nov-1988 17:31:00	  ;
;									  ;
;		 Modified to support 256 colors for Windows 3.0		  ;
;		 -by- Doug Cody, Video Seven inc Mon 30-Jan-1989 15:00:00 ;
;-------------------------------------------------------------------------;
;
cProc	TranslateBrush,<FAR,PUBLIC,WIN,PASCAL>,<es,si,di,bx,cx>
	parmD	lpBrush			; pointer to the brush
;
cBegin
WriteAux <'XlatBrsh'>
        mov     ax,off_lpBrush
        mov     dx,seg_lpBrush
        or      ax,dx
        jz      translate_brush_exit
;
; es:di points to the brush area where we will put the translated bits
;
	mov	ax,ds
	mov	es,ax			; get our own segment in es
	assumes	es,Data
        mov     di,DataOFFSET device_local_brush
;
        lds     si,lpBrush              ; DS:SI ==> to realized brush pattern
        assumes ds,nothing
;
	mov	cx,SIZE_PATTERN		; number of columns to translate
	mov	dl,cl			; number of rows to translate
        mov     dh,cl                   ; dh will reload cl at the outter loop

        xor     bh,bh
;
row_process_loop:
;
; load the next color byte from the source brush
;
	lodsb
;
; translate it through the palette tables	
;
        mov     bl,al
        mov     al,byte ptr es:PaletteTranslationTable[bx]
;
; then store just the byte color in the target brush
;
	stosb
	loop	row_process_loop	; convert all the colums in the pattern
	mov	cl,dh
	dec	dl			; done with the rows?
	jnz	row_process_loop	; not yet...
;
;----------------------------------------------------------------------------;
; we have converted the color part of the map, the mono chrome part of the   ;
; map and upto but not including the flags etc at the end of the brush will  ;
; be copied as is. We shall reset the solid brush indicator in the flag to 0 ;
;----------------------------------------------------------------------------;
;
; the monochrome map will not be translated, just moved
;
	mov	cx,SIZE_PATTERN/2	; ds:si ==>mono brush data
	rep	movsw			; es:di ==>our brush data segment
;
; now DS:SI and ES:DI are pointing to the flag bytes, copy it by resetting
; the solid_brush indicator
;
	lodsw				; get the style
	or	ax,ax			; was it a solid brush
	jnz	donot_change_style	; force a solid style to pattern
	mov	ax,3			; force it to be pattern
;
donot_change_style:
	stosw
;
; we are forcing our brush to be a pattern brush even if it is solid,
; however in case of WHITENESS/BLACKNESS, PATBLT expects the color in the
; accelarator flag, so lets get the value of pel1 and load it here, all other
; accelarator bits will be reset
;
        lodsb

;
; al has the color in case of solid brush, garbage otherwise
;
	stosb				; save accelartor byte
;
; set up DX:AX to point to the structure in local memory
;
	mov	dx,es
	mov	ax,DataOFFSET device_local_brush
translate_brush_exit:
cEnd
;
;----------------------------------------------------------------------------;
;				TranslateTextColor			     ;
;				------------------			     ;
;	Here we translate the text foreground and textbackground colors	     ;
;	which are stored in the drawmode structure . Also a flag will be set ;
;	indicating that the foreground and background color in the drawmode  ;
;	have been translated. This flag will be reset when a set foreground  ;
;	or set background color call is made next.			     ;
;									     ;
;	Parameters:							     ;
;			lpDrawMode -- A long pointer to an drawmode structure;
;	Returns:		 					     ;
;			translates the foreground and background colors in   ;
;			the structure and sets TextColorXlated flag on       ;
;	History:							     ;
;		Created.						     ;
;		-by- Amit Chatterjee [amitc]	Mon 07-Nov-1988	17:31:00     ;
;----------------------------------------------------------------------------;
;
cProc	TranslateTextColor,<FAR,PUBLIC,WIN,PASCAL>,<es,si,di,bx,cx>
	assumes	ds,Data
	assumes es,nothing
	parmD	lpDrawMode		; pointer to the drawmode structure
;
cBegin
WriteAux <'XltTxtClr'>
        mov     ax,off_lpDrawMode
        mov     dx,seg_lpDrawMode
        or      ax,dx
        jz      translate_text_color_exit
;
	mov	ax,ds
	mov	es,ax			; get our own segment in es
	assumes es,Data
;
	mov	di,DataOFFSET device_local_drawmode
;
	lds	si,lpDrawMode		; get the drawmode structure
	assumes	ds,nothing
;
; first make a complete local copy
;
	push	di
	push	si			; save the pointers
	mov	cx, (SIZE DRAWMODE)/2
	rep	movsw
	errnz  <(SIZE DRAWMODE) AND 1>
	pop	si
	pop	di
;
; now translate the colors
;
	xor	bx,bx
	mov	bl,[si].bkColor.pcol_Clr
	cCall	TranslateColor
	mov	es:[di].bkColor.pcol_Clr,dh ; save the translated index
	mov	es:[di].bkColor.pcol_fb,bl  ; save the translated flags
;
; now do a similar translation on the foreground color
;
	xor	bx,bx
	mov	bl,[si].TextColor.pcol_Clr
	cCall	TranslateColor
	mov	es:[di].TextColor.pcol_Clr,dh	; save the translated index
	mov	es:[di].TextColor.pcol_fb,bl
;
; return local structure in DX:AX
;

	mov	es:TextColorXlated,0ffh
	mov	ax,di
	mov	dx,es
translate_text_color_exit:
cEnd
;
;
;------------------------------------------------------------------------;
;				TranslatePen				 ;
;				------------				 ;
;	The pen color has a structure similar to the text background and ;
;	foreground color and will be translated in a similar fashion.	 ;
;									 ;
;	Parameters:							 ;
;		lpPen -- A pointer to a pen structure			 ;
;	Returns:		 					 ;
;		Translated physical color in the pen			 ;
;	History:							 ;
;		Created.						 ;
;		-by- Amit Chatterjee [amitc]	Mon 07-Nov-1988	13:35:00 ;
;------------------------------------------------------------------------;
;
cProc	TranslatePen,<FAR,PUBLIC,WIN,PASCAL>,<es,si,di,bx,cx>
	parmD	lpPen			; a pointer to a pen color
	assumes ds,Data
;
cBegin
WriteAux <'XlatPen'>
        mov     ax,off_lpPen
        mov     dx,seg_lpPen
        or      ax,dx
        jz      translate_pen_exit
;
	mov	ax,ds
	mov	es,ax			; get our own segment in es
	assumes	es,Data
;
	mov	di,DataOFFSET device_local_pen
;
	lds	si,lpPen		; point to the pen structure
	assumes ds,nothing
	mov	bl,[si].pcol_Clr	; get the byte with the index in it
;
; call a routine which does the translation as done for TextColors
;
	cCall	TranslateColor
	mov	es:[di].pcol_Clr,dh	; the translated index
	mov	es:[di].pcol_fb,bl	; the translated flags
;
; now copy the pen style
;	
	mov	ax,[si].oem_pen_style	; load the original style
	mov	es:[di].oem_pen_style,ax; store it in local pen structure
;
; finally return a pointer to the local pen structure in DX:AX
;
	mov	dx,es
	mov	ax,di
translate_pen_exit:
cEnd
;
;-----------------------------------------------------------------------;
;				TranslateColor				;
;				--------------				;
;	This local routine gets an old index in BL, looks up the	;
;	translation table and gets the new index in LONIBBLE of DH. 	;
;	It the calls the IndexToColor routine to get the corresponding	;
;	h/w colors into AL(red), AH(green) and DL(blue) and the accl	;
;	flag in the high nibble of DH.					;
;									;
;	Parameters:							;
;		BL -- original index					;
;		ES -- own data segment					;
;	Returns:							;
;		BL -- accelerator flags 				;
;		DH -- new index 					;
;		DL -- Blue value (0,32,128 or 255)			;
;		AH -- Green value (0,32,128 or 255)			;
;		AL -- Red value (0,32,128 or 255)			;
;	History:							;
;		Created.						;
;		-by- Amit Chatterjee [amitc] Mon 07-Nov-1988 13:49:30	;
;									;
;		Modified to support 256 colors for Windows 3.0		;
;		-by- Doug Cody, Video Seven inc, Tue 31-Jan-1989	;
;-----------------------------------------------------------------------;
;
cProc	TranslateColor,<NEAR,PUBLIC>
	assumes	es,Data
;
cBegin
WriteAux <'XlatClr'>
        sub     bh,bh                               ; make it 16 bits for
        mov     bl,es:PaletteTranslationTable[bx]   ; get the translated index
        mov     dh,bl                               ; save new index
;
; we assume that the index is in the LOBYTE and we ignore the high byte
;
        shl     bx,1                                ; index into dword
        shl     bx,1

        mov     ax,word ptr es:[bx][adPalette]      ; get the red+green color
	mov	dl,byte ptr es:[bx][adPalette+2]    ; blue color

; now get the accelarators

        sub     bh,bh
	mov	bl,dh				; index into a byte table
        mov     bl,es:abPaletteAccl[bx]         ; get the index and accl flags
cEnd
;
;----------------------------------------------------------------------------;
;			 UpdateColor (lp_rect)				     ;
;			 ---------------------				     ;
;									     ;
; This routine translates the pixel values in a rectangular region of the    ;
; EGA/VGA screen based on the current translate table maintained by the      ;
; driver.								     ;
;									     ;
; ENTRY:								     ;
;									     ;
;									     ;
; RETURNS:								     ;
;	nothing.							     ;
;									     ;
; HISTORY:								     ;
;	Mon Nov-21-1988	-by-	Amit Chatterjee [amitc] 08:26:14	     ;
;	Created.							     ;
;									     ;
;	Tue Jan-31-1989 -by- Doug Cody, Video Seven inc			     ;
;	Modified to support 256 colors for Windows 3.0			     ;
;----------------------------------------------------------------------------;
;
cProc	UpdateColors,<FAR,PUBLIC,WIN,PASCAL>,<ds,es,si,di>
	parmW	wStartX
	parmW	wStartY
	parmW	wExtX
	parmW	wExtY
	parmD	lpTranslate
	localB	UCBankSelect		; current bank select
	localW	nRows			; no of rows
	localW	mWidth			; save MemWidth on the stack
	assumes ds,Data
	assumes es,nothing
;
cBegin
WriteAux <'UpdClr'>
;
	mov	al,enabled_flag
	or	al,al
	jz	update_colors_exit

ifdef   EXCLUSION
;
; load the rectangle coordinates & exclude the cursor from that region.
;
	mov	cx,wStartX		; cx = left
	mov	si,cx
	mov	dx,wStartY		; dx = top
	mov	di,dx
	add	si,wExtX		; si = right
	add	di,wExtY		; di = bottom
	call	exclude_far		; exclude the cursor
endif
;
; calculate the starting offset into DI and load ES
;
	mov	ax,ScreenSelector	; the screen segment
	mov	es,ax
	assumes es,nothing
	mov	ax,wStartY		; the starting row
	mov	bx,MemWidth
	mov	mWidth,bx		; save on stack for later
	mul	bx
	mov	di,wStartX		; the starting X coordinate
	mov	cx,di			; save it in cx
	add	di,ax			; ES:DI has starting byte position
	adc	dl,dh			; collect the carry
	mov	UCBankSelect,dl		; save for possible later use
	call	far_set_bank_select	; and set it for the current segment
;
; load a far pointer to the translate table
;
	lds	si,lpTranslate
	assumes ds,nothing
	mov	bx,wExtY		; initialize row count
	mov	nRows,bx
;
pel_convert_loop:
	push	di			; save row start address
	mov	cx,wExtX		; no of bytes to touch
;
byte_loop:
;
; fetch and translate...
;	
	mov	bl,es:[di]		; 1 => color compares
	xor	bh,bh
	shl	bx,1
	mov	ax,ds:[bx+si]
	stosb				; save the translated value
	loop	byte_loop		; complete all the bytes
;
; all done with this row, advance the pointer and possibly, the segment
;
	pop	di			; get back the start address
	add	di,mWidth 		; go to the next scan
	jnc	row_completed		; no segment wrap, continue on...
	inc	UCBankSelect		; advance the bank select bit
	mov	dl,UCBankSelect		; load & set...
	call	far_set_bank_select
;
row_completed:
	dec	nRows			; count down the rows
	jnz	pel_convert_loop	; loop if not done...
;	
ifdef	EXCLUSION
	call	unexclude_far		; get the cursor back
endif
;
update_colors_exit:

	xor	ax,ax			; show success
cEnd

;--------------------------------------------------------------------------
; SetPalette - new windows 3.0 function which sets the values in the ramdac
;
; History:
;    Wed 3/1/89 -by- David D. Miller, Video Seven Inc.
;    Created it.
;--------------------------------------------------------------------------
;
cProc	SetPalette,<FAR,PUBLIC,WIN,PASCAL>,<si,di,es,ds>
	parmW	wStartIndex		; starting index in the Palette
	parmW	wNumEntries		; no of indexes in the Palette
	parmD	lpPalette		; long pointer to color Palette
;
        assumes ds,Data
	assumes	es,nothing
;
cBegin
WriteAux <'SetPal'>

	mov	al,enabled_flag 	; get this while DS == DGROUP

        mov     bx,ds                   ; get our own data segment
	mov	es,bx

; test for null pointer

	lds	si,lpPalette		; get pointer to new table
	mov	bx,ds			; check for null pointer
	or	bx,si
	jz	sp_exit 		; null pointer is illegal

; compute start address

	mov	di,wStartIndex
	shiftl	di,2			; *4
	add	di,DataOFFSET adPalette

	mov	cx,wNumEntries
	shiftl	cx,1			; *2
        push    di
	rep	movsw
        pop     si

	or	al,al			; is the display enabled?
        jz      sp_exit                 ; no don't actualy set the DACs

        mov     ax,es                   ; DS:SI --> RGBs
	mov	ds,ax

        mov     cx,wNumEntries          ; number of entries to program
	mov	ax,wStartIndex		; first index
	call	setramdac		; do it!!!

sp_exit:
	xor	ax,ax			; show success

cEnd
;
;--------------------------------------------------------------------------
; GetPalette - new windows 3.0 function which returns the current Palette
;	       in the array pointed to by lpPalette.
;
; History:
;    Wed 3/1/89 -by- David D. Miller, Video Seven Inc.
;    Created it.
;--------------------------------------------------------------------------
;
cProc	GetPalette,<FAR,PUBLIC,WIN,PASCAL>,<si,di,es>
	parmW	wStartIndex	; starting point in the Palette
	parmW	wNumEntries	; no of indexes in the Palette
	parmD	lpPalette	; long pointer to color Palette
;
	assumes	ds,Data
	assumes	es,nothing
;
cBegin
WriteAux <'GetPal'>

	les	di,lpPalette		; point to destination array
	mov	bx,es			; check for null pointer
	or	bx,di
	jz	gp_exit

	mov	si,wStartIndex		; point to current color palette
	shiftl	si,2			; *4
	add	si,DataOFFSET adPalette

	mov	cx,wNumEntries		; get number of entries to move
	xor	al,al			; zero out al

gp_10:
;
; now move the data and gaurantee that the flag byte is zero
;
	movsw				; copy blue and green
	movsb				; copy red
	stosb				; zero remaining byte
	inc	si
	loop	gp_10

gp_exit:
	xor	ax,ax			; show success

cEnd
sEnd	PaletteSeg
;
END
