	.xlist
;----------------------------Module-Header------------------------------;
; Module Name: PATTERN.INC
;
; Subroutine for pattern preprocessing.
;
; Entry:
;	BH -  The F0_DEST_IS_COLOR bit should be set if the dest is color.
;	      If this bit is undefined in the calling module, then BH = FF
;	      will suffice to indicate a color dest; BH = 0 will indicate a
;	      mono dest.
;	DS:SI PTR to the physical brush which will be preprocessed
;	ES:DI PTR to the drawmode structure
;	CX:AX PTR to a brush structure where the new munged brush will be
;		  stored.
;
; The code operates as indicated below:
;
; IF the brush type was originally BS_HATCHED then the entire brush structre
; is simply copied from DS:SI into CX:AX and ES:DI will return pointing to
; the mono part of the copy if dest is mono, or the color part of the copy if
; the dest is color. If the brush is BS_PATTERN, things happen as shown in
; the following table. (Note: the GREY_SCALE bit is a 1 if the patterned
; brush was originally defined in mono; otherwise the bit is 0.)
;
;  GREY_SCALE	 DEST IS	MUNGE PATTERN BRUSH IN FOLLOWING MANNER
;      1	  MONO		expand mono pattern to color using fg,bg
;				colors from drawmode structure, then compress
;				the color pattern back to mono using the
;				fg,bg MONO BITS. Store this new mono brush in
;				CX:AX.oem_brush_mono and Return ES:DI
;				pointing to this new mono pattern
;
;      1          COLOR         expand mono pattern to color using fg,bg
;				colors from drawmode structure. Store this
;				new color brush in CX:AX.oem_brush_clr and
;				Return ES:DI pointing to this new color pat.
;
;      0          MONO          Compress the color pattern down to mono
;				using the MONO bit of the color (all the
;				MONO BITS are held in the 256 byte array
;				abPaletteAccl). Store the new mono pattern
;				in CX:AX.oem_nrush_mono and return ES:DI
;				pointing to this new mono pattern
;
;      0	  COLOR 	Copy the color pattern directly into
;				CX:AX.oem_brush_clr. Return ES:DI pointing
;				to this color pattern. (ES:DI = CX:AX)
;
; Returns:
;	ES:DI PTR to new pattern to use (mono if mono dest, clr if clr dest)
;	AL    brush accel bits of the physical brush passed in.
;       Carry flag clear if no error
;
; Error Returns:
;	Carry flag set if error (null lpPBrush, or hollow brush)
;
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.


	assume	ds:nothing
	assume	es:nothing

pattern_prep_error_ws:
	jmp	pattern_prep_error

public	 pattern_preprocessing
pattern_preprocessing	proc	near

	cmp	oem_brush_style[si],BS_HOLLOW
	je	pattern_prep_error_ws	      ;Hollow brush. Abort with error

	push	WORD PTR [si].oem_brush_accel ;Save brush accelerator

	cmp	[si].oem_brush_style, BS_SOLID
	jne	@F
	jmp	pattern_prep_solid_dither

@@:
	cmp	[si].oem_brush_style, BS_HATCHED
	jne	pattern_prep_0
	jmp	pattern_prep_hatched

pattern_prep_0:
	test	oem_brush_accel[si] ,GREY_SCALE
	je	pattern_prep_pattern_color

pattern_prep_pattern_mono:

	test	bh,1				;Is destination color?
	jne	pattern_prep_mono_to_color	; go take care of that case

pattern_prep_mono_to_mono:

	add	si	,oem_brush_mono
	mov	dh,es:[di].bkColor.pcol_fb
	mov	dl,es:[di].TextColor.pcol_fb
	shr	dh	,1			;use mono bits to get colors
	sbb	dh	,dh
	shr	dl	,1			;  for the fg and bg
	sbb	dl	,dl

	mov	es	,cx			;put location to store new
	mov	di	,ax			;  mono pattern in es:di
	add	di	,oem_brush_mono 	;point to mono
	mov	cx	,SIZE_PATTERN

pattern_prep_mono_to_mono0:
	lodsb
	mov	ah	,al
	not	al
	and	al	,dl
	and	ah	,dh
	or	al	,ah
	stosb
	loop	pattern_prep_mono_to_mono0

	sub	di	,SIZE_PATTERN
	jmp	pattern_prep_end


pattern_prep_mono_to_color:

	add	si	,oem_brush_mono
	mov	dh,es:[di].bkColor.pcol_Clr
	mov	dl,es:[di].TextColor.pcol_Clr
	xor	dh	,dl

	mov	es	,cx
	mov	di	,ax

	mov	cl,SIZE_PATTERN 	;Set outer loop count
pattern_prep_outer:
	mov	ch,SIZE_PATTERN 	;Set inner loop count
	lodsb				;Get pixel color
	mov	ah	,al
pattern_prep_inner:
	rol	ah	,1
	sbb	al	,al
	and	al	,dh
	xor	al	,dl		;00 if bkColor
	stosb				;Store color byte
	dec	ch
	jnz	pattern_prep_inner
	loop	pattern_prep_outer   ;(CH is zero)

	sub	di	,SIZE_PATTERN * SIZE_PATTERN
	jmp	pattern_prep_end


pattern_prep_pattern_color:

	test	bh,1				;Is destination color?
	jne	pattern_prep_color_to_color	;..yes, use pattern as is

pattern_prep_color_to_mono:

	push	bx
	lea	bx	,abPaletteAccl
	mov	es	,cx
	mov	di	,ax
	add	di	,oem_brush_mono
        mov     cl      ,SIZE_PATTERN

pattern_prep_color_to_mono0:
	mov	ch	,SIZE_PATTERN

pattern_prep_color_to_mono1:
	lodsb
	push	ds
	mov	ds	,bp
	xlat
	pop	ds
	ror	al	,1
	rcl	ah	,1
	dec	ch
	jne	pattern_prep_color_to_mono1
	mov	al	,ah
	stosb
	loop	pattern_prep_color_to_mono0
	pop	bx

	sub	di	,SIZE_PATTERN
	jmp	pattern_prep_end

pattern_prep_color_to_color:

	mov	es	,cx
	mov	di	,ax
	mov	cx	,oem_brush_mask + SIZE_PATTERN
	rep	movsb
	mov	di	,ax
	jmp	pattern_prep_end

pattern_prep_solid_dither:
pattern_prep_hatched:

	mov	es	,cx
	mov	di	,ax
	mov	cx	,oem_brush_mask + SIZE_PATTERN
	rep	movsb
	mov	di	,ax

	test	bh	,1
	jne	pattern_prep_end

	add	di	,oem_brush_mono

pattern_prep_end:
	pop	ax
	clc
	ret

pattern_prep_error:
	stc
	ret

pattern_preprocessing	endp

