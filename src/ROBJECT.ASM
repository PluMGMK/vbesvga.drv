        page    ,132
;
;-----------------------------Module-Header-----------------------------;
; Module Name:  ROBJECT.ASM
;
; This module contains the code which realizes the objects required
; by GDI.
;
; Created: 19-Feb-1987
; Author:  Walt Moore [waltm]
;
; Copyright (c) 1983-1987 Microsoft Corporation
;
; Exported Functions:
;       RealizeObejct
; Public Functions:
;       sum_RGB_colors_alt
; Public Data:
;       none
; General Description:
;
; Restrictions:
;
; History:
;	Nov. 15, 1989: Changed to new color dither scheme.
;	Cleaned up some things in realize_solid. [GunterZ]
;
;       Jan 23 1989 11am -by- David Miller, Video Seven Inc
;       Modified to work in VRAM's 256 color modes.
;
;-----------------------------------------------------------------------;
;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.
MM_ALL          equ     0fh             ; all bits of index on
incLogical      =       1               ; Include control for gdidefs.inc
;
        .xlist
        include cmacros.inc
        include gdidefs.inc
        include display.inc
        include macros.mac
        .list
;
        ??_out  robject
;

;DEBUG_PREVIEW_BRUSH	equ 1

sBegin	Data

externB abPaletteAccl
ifdef	DEBUG_PREVIEW_BRUSH
externW	ScreenSelector
endif

dodgy_brush_count	db 1

sEnd    Data




sBegin  Code
assumes cs,Code
        public  sum_RGB_colors_alt      ;Alternate entry point
        public  sum_RGB_alt_far         ;Alternate far entry point
        public  realize_solid
        public  realize_brush
        public  realize_pattern
	public	pattern_copy_numwords
	public	oem_brush_size
ifdef	DEBUG_PREVIEW_BRUSH
	externW	MemoryWidth
endif
        externNP dither                 ;Brush dithering code
	externNP ColorDither
        externNP rgb_to_ipc             ;Logical to physical color conv
        externNP unpack_physclr         ;physical color conv, step two
        externA  BW_THRESHOLD           ;Where black becomes white
	externW _cstods
	externW	ColourFormat_CS		;in VESAFNS.ASM
;
; The following are the definitions for the hatch patterns. They are defined
; by each individual driver based on its resolution.
;
        externA < H_HATCH_BR_0, H_HATCH_BR_1, H_HATCH_BR_2, H_HATCH_BR_3>
        externA < H_HATCH_BR_4, H_HATCH_BR_5, H_HATCH_BR_6, H_HATCH_BR_7>
        externA < V_HATCH_BR_0, V_HATCH_BR_1, V_HATCH_BR_2, V_HATCH_BR_3>
        externA < V_HATCH_BR_4, V_HATCH_BR_5, V_HATCH_BR_6, V_HATCH_BR_7>
        externA <D1_HATCH_BR_0,D1_HATCH_BR_1,D1_HATCH_BR_2,D1_HATCH_BR_3>
        externA <D1_HATCH_BR_4,D1_HATCH_BR_5,D1_HATCH_BR_6,D1_HATCH_BR_7>
        externA <D2_HATCH_BR_0,D2_HATCH_BR_1,D2_HATCH_BR_2,D2_HATCH_BR_3>
        externA <D2_HATCH_BR_4,D2_HATCH_BR_5,D2_HATCH_BR_6,D2_HATCH_BR_7>
        externA <CR_HATCH_BR_0,CR_HATCH_BR_1,CR_HATCH_BR_2,CR_HATCH_BR_3>
        externA <CR_HATCH_BR_4,CR_HATCH_BR_5,CR_HATCH_BR_6,CR_HATCH_BR_7>
        externA <DC_HATCH_BR_0,DC_HATCH_BR_1,DC_HATCH_BR_2,DC_HATCH_BR_3>
        externA <DC_HATCH_BR_4,DC_HATCH_BR_5,DC_HATCH_BR_6,DC_HATCH_BR_7>
;
;
; realize_sizes
;
; realize_sizes contains the size of the memory required to realize
; each of the objects.  These sizes will be returned to GDI when it
; inquires the memory needed for an object.
; PluM: moved this up here to prevent "phase error between passes"
; when referencing oem_brush_size from code in this module.
;
realize_sizes   label   word
oem_pen_size	dw      SIZE oem_pen_def
oem_brush_size	dw      SIZE oem_brush_def4
oem_font_size	dw      0
;
        errnz   OBJ_PEN-1
        errnz   OBJ_BRUSH-OBJ_PEN-1
        errnz   OBJ_FONT-OBJ_BRUSH-1
;
;
;--------------------------Exported-Routine-----------------------------;
; RealizeObject
;
;   RealizeObject - Logical to Physical Object Realization
;
;   RealizeObject performs the task of converting logical objects
;   into physical objects that this driver can manipulate to per-
;   form the various functions requested of it.
;
;   The size needed to realize an object will be returned if the
;   pointer to where the physical realization is to be stored is
;   NULL.
;
;   In some cases where the driver cannot realize the requested object,
;   a solid color pen must be realized which GDI will use when it
;   performs the nessacary simulations.  In other cases, punt.
;
; Entry:
;       None
; Returns:
;       AX = object size if ok
; Error Returns:
;       AX = 0  if error or object unrealizable
; Registers Preserved:
;       SI,DI,ES,DS,BP
; Registers Destroyed:
;       AX,BX,CX,DX,FLAGS
; Calls:
;
; History:
;
;       Fri 16-Nov-1988 09:18:40 -by-  Amit Chatterjee [amitc]
;       GREY_SCALE flag bit abolished from the brush accelarator bits and
;       a note saying why it is thus included.
;
;       Fri 25-Nov-1988 10:42:05 -by-  Amit Chatterjee [amitc]
;         .  The logical_to_physical color conversion was redone ti suite 4
;            plane devices.
;         .  Physical brush structure now has a fourth plane before the
;            monochrome part of the map.
;         .  Dithering for the color planes of a brush uses the algorithm
;            that PM uses, however for the mono brush the original dither
;            process is still used.
;
;       Fri 11-Nov-1988 16:22:35 -by-  Amit Chatterjee [amitc]
;       Realize object can now accept a palette table index instead
;       of a logical color, the code Gets the corresponding color and
;       puts this in place of the logical color before proceeding
;
;       Mon 17-Oct-1987 11:32:30 -by-  Amit Chatterjee [amitc]
;       Adopted interleaved scan line format for small source bitmaps
;       for realizing pattern brushes. Pattern format remains the same
;
;       Mon 16-Feb-1987 18:09:09 -by-  Walt Moore [waltm]
;       Created.
;-----------------------------------------------------------------------;
;
;
;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;
;
        assumes ds,Data
        assumes es,nothing


;
cProc   RealizeObject,<FAR,PUBLIC,WIN,PASCAL>,<es,ds,si,di>
        parmD   lp_device               ; Pointer to Device structure
        parmW   style                   ; Style of realization
        parmD   lp_in_obj               ; Pointer to input (logical) object
        parmD   lp_out_obj              ; Pointer to output (physical) object
        parmD   lp_text_xform           ; Pointer to a text transformation
                                        ; or (x,y) for brush realization
                                        ; Segment = y, Offset = x
;
        localB  brush_accel             ; Temp brush accelerator
        localB  prev_dither             ; Brush dither value
        localW  bw_sum                  ; Black & white sum for a brush
        localW  offset_to_phy_brush     ; Offset to physical brush
        localB  dither_flags            ; for dithering
	localW	bw_sum			; Black & white sum for a brush
	localW	my_data_seg		;copy of data segment selector
	; extra stuff for hatching on a 286 (and maybe other things)
	localD	spill_colour_1
	localD	spill_colour_2
;
cBegin
WriteAux <'RlzObj'>
        cld
	mov	my_data_seg,ds
	mov	ax,1			; Assume good exit
        mov     bx,style                ; If delete object, nothing to do
        or      bx,bx                   ; since we don't keep objects
        js      realize_exit            ; This is a delete object
        lds     si,lp_in_obj            ; --> logical object
        assumes ds,nothing
;
        dec     ax                      ; Assume error (AX = 0 as return code)
        dec     bx                      ; Determine style of realization.
        cmp     bx,OBJ_FONT-1           ; Is it a legal object?
        jg      realize_exit            ; Not by our standards, return error
        shl     bx,1                    ; Compute index into dispatch table
;
        les     di,lp_out_obj           ; If lp_out_obj is NULL, then return
        assumes es,nothing              ; size requirement
        mov     cx,es
        or      cx,di
        jz      return_obj_size         ; They want the size
;
        push    bx                      ; Save object type
        call    cs:realize_dispatch[bx] ; Realize a physical object
        pop     bx                      ; Object's size will be return code
;
return_obj_size:
        mov     ax,cs:realize_sizes[bx] ; Get size for the object
;
realize_exit:

cEnd
;
;
;--------------------------Private-Routine------------------------------;
; realize_pen
;
;   Realize Logical Pen Into a Physical Pen
;
;   The given logical pen is realized into a physical pen.
;
;   The pen will be realized regardless of the pen width or
;   style since GDI will need a pen to use for simulations.
;
;   If the width of the pen is >1, then a solid pen will be
;   realized regardless of the pen style.  GDI will use this
;   pen for simulating the wide line.
;
;   If the pen style isn't recognized, then a solid pen of
;   the given color will be realized (this is called punting).
;
; Entry:
;       DS:SI --> logical pen definition
;       ES:DI --> output object
; Returns:
;       AX non-zero to show success
; Error Returns:
;       No error return.
; Registers Preserved:
;       BP,DS,ES
; Registers Destroyed:
;       AX,BX,CX,DX,SI,DI,FLAGS
; Calls:
;       sum_RGB_colors
; History:
;
;       Mon 14-Nov-1988 17:13:40 -by-  Amit Chatterjee [amitc]
;       The logical color structure can now have an index instead of a
;       RGB color value.  If the HIWORD of the color DWORD is 0ffffh, then
;       the LOWORD has an index.
;
;       Thu 19-Feb-1987 14:06:41 -by-  Walt Moore [waltm]
;       Created.
;
;       Mon 23-Jan-1989          -by-  David Miller, Video Seven Inc
;       Modified to support the VRAM's 256 color modes under Windows v 3.0
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
;
realize_pen     proc near
        mov     cx,[si].lopnStyle       ; If a NULL pen, then all that really
        cmp     cx,LS_NOLINE            ; needs to be stored is the pen
        je      realize_pen_20          ; type so it can be recognized
        mov     ax,LS_SOLID             ; Assume solid pen will be required
        cmp     [si].lopnWidth,1        ; If not a nominal width pen,
        ja      realize_pen_10          ; make a solid pen for simulations
        cmp     cx,MaxLineStyle         ; If the line style is unknown
        ja      realize_pen_10          ; make it a solid pen
        xchg    ax,cx                   ; Need to counter following XCHG
;
realize_pen_10:
        xchg    ax,cx                   ; Set pen type into CX
        lea     si,[si].lopnColor       ; --> RGB color
        call    sum_RGB_colors          ; Sum up the color
	call	unpack_physclr		; Extract the accelerators
        errnz   oem_pen_accel-oem_pen_style-1
	mov	ch,bh			; Store accels with the style
;
realize_pen_20:
        errnz   oem_pen_pcol            ; Must be first field
        stosw                           ; Save color of pen
        mov     ax,dx
        stosw
        mov     ax,cx                   ; Save style
        errnz   oem_pen_style-4         ; Style must be 4 bytes into phys pen
        stosw
        ret
;
;        errnz   pcol_Clr                ; Colors must be in this order
;        errnz   pcol_fb-pcol_Clr-1

realize_pen     endp
;
;
;--------------------------Private-Routine------------------------------;
; realize_brush
;
;   Realize Logical Brush Into a Physical Brush
;
;   Four styles of logical brushes may be realized.  These are SOLID,
;   HOLLOW, HATCHED, and PATTERN.
;
;   A SOLID brush is defined with a logical RGB color definition.
;   This color is processed into one of 65 dithers.
;
;   A HATCHED brush is defined with a logical RGB color definition and
;   a hatching type.  The hatch type is mapped to one of the six hatched
;   styles that the driver supports.  All bits in the hatched brush which
;   are 1 are set to the hatch color passed in, and all bits which are
;   0 are set to the background color passed in.
;
;   A PATTERN brush is defined with an 8 X 8 pattern in the form of a
;   physical bitmap.  The bitmap may be monochrome or color.  More
;   discussion on converting is contained under the pattern brush code.
;
;   A HOLLOW brush is one which can never be seen.  The brush style is
;   maintained in the device brush structure so that a check can be
;   made and an abort executed if one is used.  No punting is needed
;   for hollow brushes.
;
;   Brushes will be aligned based at the (x,y) origin passed in via
;   the text transform.
;
; Entry:
;       DS:SI --> logical brush definition
;       ES:DI --> output object
; Returns:
;       None
; Error Returns:
;       None
; Registers Preserved:
;       BP
; Registers Destroyed:
;       AX,BX,CX,DX,SI,DI,ES,DS,FLAGS
; Calls:
;
; History:
;       Thu 19-Feb-1987 14:06:41 -by-  Walt Moore [waltm]
;       Created.
;       Mon 30-Jan-1989 11:00:00 -by- Doug Cody, Video Seven Inc
;       Modified to work in VRAM's 256 color modes.
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
;
realize_brush   proc near
        xor     ax,ax                   ; Assume a solid brush will be needed
        errnz   BS_SOLID                ; Must be 0, and first type of brush
;
        mov     bx,[si].lbStyle         ; Get the brush style.
        cmp     bx,MaxBrushStyle        ; If an illegal brush, create a solid one
        ja      realize_brush_calc_fnptr
        xchg    ax,bx                   ; Need brush style in AX
;
realize_brush_calc_fnptr:
	add     ax,ax                   ; Call routine which will do the
        xchg    ax,bx                   ; actual realization
        call    cs:brush_realizations[bx]
        lds     di,lp_out_obj           ; --> back to start of oem_brush_def
        assumes ds,nothing
;
	; save brush style and accelerator
	mov	cx,bx
	mov	bx,[oem_brush_size]	; point at end of brush
	; then address the common part "backwards" from it
        mov     [bx+di-size oem_brush_com].oem_brush_style,cx
        mov     [bx+di-size oem_brush_com].oem_brush_accel,dh
;
; If this is a solid black or a solid white brush, then no
; rotation is required.  Otherwise, rotate as needed.
;
; Some acceleration can be gained by recognizing that the
; color planes of the brush as solid and not rotating them
;
	test	dh,SOLID_BRUSH
	jne	realize_brush_done	; No rotations will be required
;
        mov     cx,off_lp_text_xform    ; Get the X origin
        and     cx,111b                 ; If at a byte boundary then
        jz      realize_brush_xrot_done ; no X rotation is needed
        call    rotate_brush_x          ; Perform X rotation
;
realize_brush_xrot_done:
        mov     bx,seg_lp_text_xform    ; Get the Y origin
        and     bx,111b                 ; If at a multiple of 8, then
        jz      realize_brush_done      ; no Y rotation is needed
        call    rotate_brush_y          ; Perform Y rotation
;
realize_brush_done:
ifdef	DEBUG_PREVIEW_BRUSH
	; Rudimentary preview of the brush we just created:
	; paint it in the upper-left corner of the screen
	; and do an int3 so we can look at it.
	mov	es,[_cstods]
	assumes	es,Data

        lds     si,lp_out_obj           ; --> back to start of oem_brush_def
	mov	cx,[oem_brush_size]
	sub	cx,size oem_brush_com
	; now CX = size in bytes of the colour portion of the brush
	; divide by eight to get the size of a single line
	shr	cx,3
	errnz	SIZE_PATTERN-8
	mov	bl,SIZE_PATTERN	; BL = number of lines
	shr	cx,1	; Change from bytes to words

	; back up the bank selection
	mov	dl,[bank_select_byte]
	push	dx

	; point ES:DI at top-left of screen
	mov	es,[ScreenSelector]
	assumes	es,nothing
	xor	di,di
	xor	dl,dl
	SET_BANK

	; fill in line-by-line
@@:
	push	di
	push	cx
	rep	movsw
	pop	cx
	pop	di
	add	di,[MemoryWidth]
	dec	bl
	jnz	@B
	; solid brushes seem OK, so only show non-solid ones
        cmp     [si].oem_brush_style,BS_SOLID
	je	@F
	int	3	; show the colour brush
@@:

	; now do the mono part, which DS:SI already points to
	xor	di,di
	; set CX to the bytes per pixel
	; need to SHL 1 to convert words back to bytes
	; then SHR 3 to divide by SIZE_PATTERN again to get single pixel
	; Net: we SHR 2
	shr	cx,2
	; use BX to count pixels: BH for lines, BL for pixels per line
	mov	bh,SIZE_PATTERN
preview_mono_lineloop:
	mov	bl,SIZE_PATTERN
	push	di
	lodsb
	mov	ah,al
@@:
	rcl	ah,1	; move the next bit into CF
	sbb	al,al	; AL becomes FF if the bit was 1, or 00 otherwise
	push	cx
	rep	stosb	; store AL as many times as needed to make a full pixel
	pop	cx
	dec	bl	; next pixel
	jnz	@B

	pop	di
	add	di,[MemoryWidth]
	dec	bh
	jnz	preview_mono_lineloop

	; solid brushes seem OK, so only show non-solid ones
        cmp     [si-SIZE_PATTERN].oem_brush_style,BS_SOLID
	je	@F
	int	3	; show the mono brush
@@:

	; restore bank selection
	pop	dx
	SET_BANK

endif
        ret

realize_brush   endp
;
;
;--------------------------Public-Routine-------------------------------;
; sum_RGB_colors
; sum_RGB_colors_alt
;
;   Sum Given RGB Color Triplet
;
;   The given RGB color triplet is summed, and the result returned
;   to the caller.  Other useful information is also returned.
;
;   It is this routine which maps the colors to the bit planes
;   of the EGA.
;
;   Ordering of the color in a dword is such that when stored in
;   memory, red is the first byte, green is the second, and blue
;   is the third.  The high order 8 bits may be garbage when passed
;   in, and should be ignored.
;
;   when in a register:     xxxxxxxxBBBBBBBBGGGGGGGGRRRRRRRR
;
;   when in memory:         db      red,green,blue
;
;
; Entry:
;       DS:SI --> RGB triplet to sum        (for sum_RGB_colors)
;       AL     =  Red   value of triplet    (for sum_RGB_colors_alt)
;       AH     =  Green value of triplet    (for sum_RGB_colors_alt)
;       DL     =  Blue  value of triplet    (for sum_RGB_colors_alt)
; Returns:
;
; The EGA/VGA supports 2 bits for every color and so the physical color can
; only be one of 4 values. The mapping chosen by experimentation happens to
; be:-
;               Physical Index            Color Vale(0-255)
;               --------------            -----------------
;                    00                          0
;                    01                          128
;                    11                          255
; The intenstity bit,ie, the MS bit of the 4 bit index is common to all the
; 3 planes and an index 10 for all will be used to siginify a dark grey with
; color value being 32 for all 3 colors.
;
;       AL              = Physical color byte
;       AH              = accelarator and mono bit
;       DX              = ff00
; Error Returns:
;       None
; Registers Preserved:
;       CX,SI,DI,DS,ES
; Registers Destroyed:
;       CX,FLAGS
; Calls:
;       None
; History:
;	June-16-1989		 -by- David Miller Video Seven, Inc
;	Modified to simply call RGB_to_IPC, after first checking to
;	see if the input color is already an index.
;
;	Mon 05-Jun-1989 	 -by- Doug Cody, Video Seven, Inc
;       Changed return conditions, from rgb_to_ipc, to accept 5 bits of
;       color, & 3 bits of accelerators.
;
;       Wed 25-Jan-1989          -by- David D. Miller, Video Seven Inc
;       changed the return to match the new 8bpp internal physical
;       color format described in display.inc.  Can still use rgb_to_ipc
;       and simply remap the results.
;
;       Fri 25-Nov-1988 11:00:00 -by-  Amit Chatterjee [amitc]
;       Total rewrite to adopt the 4 plane EGA/VGA model. The code is on the
;       lines of the code used in PM land.
;
;       Thu 19-Feb-1987 14:06:41 -by-  Walt Moore [waltm]
;       Created.
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
;
sum_RGB_alt_far proc far
        call    sum_RGB_colors_alt
        ret

sum_RGB_alt_far    endp
;
;
sum_RGB_colors  proc    near
        mov     ax,word ptr [si]        ; AH = G, AL = R
        mov     dx,word ptr [si][2]     ; DL = B

sum_RGB_colors_alt proc near

        test    dh,dh                   ;is it already physical???
	jnz	sum_RGB_colors_exit

	cCall	rgb_to_ipc		;otherwise convert it to an index
;
;---------------------------------------------------------------------------
;The new internal physical color format is documented in DISPLAY.INC
;---------------------------------------------------------------------------
;
sum_RGB_colors_exit:
        ret

sum_RGB_colors_alt endp
sum_RGB_colors     endp
;
;
;--------------------------Private-Routine------------------------------;
; realize_solid
;
;   Realize Solid Style Brush
;
;   The given logical solid brush is realized.  Each color for
;   the brush (RGB) is dithered for the color brushes.
;
;   The sum of all the colors is used to determine the dither
;   to use for monochrome portion of the brush.
;
; Entry:
;       DS:SI --> logical object
;       ES:DI --> output object
; Returns:
;	DH = oem_brush_accel flags
; Error Returns:
;       None
; Registers Preserved:
;       BP,ES,DS,FLAGS
; Registers Destroyed:
;       AX,BX,CX,DX,SI,DI,FLAGS
; Calls:
;       dither
;       sum_RGB_colors_alt
; History:
;
;       26-Jan_1989 -by- David D. Miller, Video Seven Inc.
;       Modified for new 256 color brush def'n as described in display.inc
;
;       Mon 14-Nov-1988 17:15:00 -by-  Amit Chatterjee [amitc]
;       The logical color structure can now have an index instead of a
;       RGB color value.  If the HIWORD of the color DWORD is 0ffffh, then
;       the LOWORD has an index.
;
;       Thu 19-Feb-1987 14:06:41 -by-  Walt Moore [waltm]
;       Created.
;-----------------------------------------------------------------------;
;
;
;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;
;
;
RGB_202020      equ     80h
;
;----------------------------------------------------------------------------;
;
assumes ds,nothing
assumes es,nothing

realize_solid   proc    near
        mov     ax,wptr [si].lbColor    ;AL = Red, AH = Green
	mov	dx,wptr [si].lbColor[2] ;DL = Blue, DH the 4th byte
;
;
        cmp     dh,0FFh                 ; if this is an index then process
	jne	@F
;
        call    realize_solid_with_index ; realize the brush with the index
	jmp	solid_brush_done	 ; dh returns with accelerators
;
@@:
	xor	dh,dh			 ; flush for 2nd 'jmp @f'
;
; quick check for a black brush
;
	mov	bx, ax
	or	bl, dl
	or	bl, ah
	jz	RSBlackBrush
;
; quick check for a white brush
;
	mov	bl, 0FFH
	and	bl, al
	and	bl, dl
	and	bl, bh
	inc	bl
        jz      RSWhiteBrush

;----------------------------------------------------------------------------;
; do a weightage average of the color for a momo chrome driver.		     ;
; the sum is (R+B)/4 + G/2						     ;
;----------------------------------------------------------------------------;

	push	ax
	push	dx			;save blue
	mov	bl	,al
	sub	bh	,bh
	sub	dh	,dh
	add	bx	,dx		;R+B
	shr	bx	,1		;(R+B)/2
	mov	al	,ah
	sub	ah	,ah
	add	bx	,ax
	shr	bx	,1		; G/2 + (R + B) / 4
	mov	bw_sum	,bx		;save it
	pop	dx			;restore back the blue
	pop	ax

;----------------------------------------------------------------------------;
; now call the color matcher routine to get the nearest color index and the  ;
; accelarator bits in DH, ignore the physical color values returned in AL,AH ;
; and DL.								     ;
;----------------------------------------------------------------------------;

	call	sum_RGB_colors_alt	; map into index
	; At this point:
	; *IF WE HAVE A PALETTE*
	; - AL = physical colour
	; - AH = accelerator flags
	; - DH = FFh
	; *IF WE DON'T HAVE A PALETTE*
	; - DL:AH:AL = physical colour
	; - DH = accelerator and other flags != FFh
	push	bx
	call	unpack_physclr
	mov	brush_accel,bh
	pop	bx
	jc	RSUsePalette

	or	brush_accel,SOLID_BRUSH	; no dithering, so set the solid bit
FillSolidPlane:
	; if "somehow" we have 1-byte colours without a
	; palette, the same code path will work for them too:
	cmp	[oem_brush_size],SIZE oem_brush_def
	je	RSSetPlanesLoop_8bit

	; Now we have the *actual* physical colour representation in DX:AX
	mov	cx,SIZE_PATTERN*SIZE_PATTERN
RSSetPlanesPref	label byte
	nop	; Can replace this nop (90h) with a rep (F3h)
@@:	stosw
RSSetPlanesXchg:
	xchg	ax,dx
RSSetPlanesStos	label byte
	stosw	; Can decrement this stosw (ABh) to a stosb (AAh)
	xchg	ax,dx
	loop	@B
RSSetPlanesDone:

	; move onto the mono piece
	test	brush_accel,SOLID_BRUSH
	jnz	do_mono_brush		;JAK
	; This may be a hatched brush with identical fg and bg colours:
	jmp	realize_hatch20

RSUsePalette:
	and	ah,not SOLID_BRUSH	; to be set later
	mov	brush_accel,ah		; save the tentative accelarators
	test	ah,80h			; is it an exact match?
	jz	RSDitherBrush		; no, so we have to dither it...
	or	ah,SOLID_BRUSH		; yes, so set the solid bit
	mov	brush_accel,ah
;
; create a solid color brush
;
RSSetPlanesLoop_8bit:
	mov	dh,ah
	mov	cx, SIZE_PATTERN * SIZE_PATTERN / 2
	mov	ah,al
	rep	stosw
	test	brush_accel,SOLID_BRUSH
	jnz	do_mono_brush		;JAK
	; This may be a hatched brush with identical fg and bg colours:
	jmp	realize_hatch20

;
; create a solid white brush (& mono brush portion too)
;
RSWhiteBrush:
	not	bl			; create 0ffh for white color
;
; create a solid black brush (& mono brush portion too)
;
RSBlackBrush:
	mov	dh,SOLID_BRUSH+ONES_OR_ZEROS
        mov     al,bl
	cbw
	; calculate the size of the colour + mono buffer
	mov	cx,[oem_brush_size]
	; pull off the "common" bit to get the colour buffer (but keep mono bit)
	sub	cx,size oem_brush_com - size oem_brush_mono
	; divide by two since we're storing words
	shr	cx,1
	rep	stosw
	jmp	short solid_brush_done
;
RSDitherBrush:
;
; do the color part of the brush
;
        mov     ax,wptr [si].lbColor    ;AL = Red, AH = Green
	mov	dx,wptr [si].lbColor[2] ;DL = Blue, DH the 4th byte
        cCall   ColorDither
;
do_mono_brush:
;
; do the mono chrome part of the brush
;
	xor	si,si			;clear GREY indicators
	mov	dx,bw_sum		;get color value for mono plane
	; FIXME: Need to update dither to work with multi-byte colours!
	call	dither			;do the pattern
	or	si,si			;test for solid or bad dithers
	jz	set_up_return		;neither solid nor bad dither
	test	si,100b			;ignore solid color
	jnz	set_up_return
;
; we have a bad dither for the mono plane set it correct
;
	add	si,si			;index into DWORD
	and	si,7
	mov	ax,cs:greys[si][-2]	;get the better looking dither pattern
	sub	di,SIZE_PATTERN		;go to start of mono brush
	stosw
	stosw
	stosw
	stosw
	errnz	SIZE_PATTERN-8
;
set_up_return:
	mov	dh,brush_accel		;the accelarator bute
;
solid_brush_done:
	mov	bx,BS_SOLID		;brush type solid
	ret

greys   label   word
        db      088h,022h               ; Dark grey dither
        db      0AAh,055h               ; Grey dither
        db      0DDh,077h               ; Light grey dither

realize_solid	endp
;
;----------------------------------------------------------------------------;
;                       realize_solid_with_index                             ;
;                       ------------------------                             ;
; ES:DI --- points to the start of the physical brush structure              ;
; AX    --- has an index value (last 4 bits significant)                     ;
;                                                                            ;
; This routine creates a 4 plane color brush pattern where every pel has the ;
; passed in index value. The monochrome part of the brush is going to be all ;
; black if the index is 0 or else it is going to be white (for anyother index;
; value). The brush accelarator will be set, with the mono bit being 0 if    ;
; index is 0 else it will be 1.                                              ;
;                                                                            ;
; This routine returns BS_SOLID in BX and the accelarator flag in DH         ;
;									     ;
; History:								     ;
;   26-Jan-1989       -by-  David D. Miller, Video Seven Inc.		     ;
;   Modified for VRAM 256 color modes, see brush def'n in display.inc        ;
;----------------------------------------------------------------------------;
;
realize_solid_with_index proc	near
	cld			; make no assumption about this
	mov	dx,ax		; save index and flags for later
	mov	cx,SIZE_PATTERN*SIZE_PATTERN/2 ; this many words in color brush
	mov	ah,al		; setup for word outs
	rep	stosw		; fill in color portion of pattern
;
; now we will complete the monochrome part of the map
;
	ror	dh,1		; if zero set all bits to 0, check mono_bit
	rol	dh,1		; preserve dh
	sbb	ax,ax		; fill ax with mono_bit
	mov	cx,4		; 4 words for the mono part
	rep	stosw		; complete that part
;
; set a bit indicating a solid brush
;
	or	dh,SOLID_BRUSH
	mov	bx,BS_SOLID	; solid brush code
	ret

realize_solid_with_index endp
;
;
;--------------------------Private-Routine------------------------------;
; realize_pattern
;
;   Realize Pattern brush
;
;   The given bitmap is copied for use as a 8x8 bit pattern brush.
;   Any information beyond the first 8x8 bits is not required to be
;   maintained as part of the brush, even though GDI does allow
;   you to do this if desire.
;
;   If the bitmap is a monochrome bitmap, it is to be expanded up
;   into a black/white bitmap.  If the bitmap is a color bitmap,
;   then to compute the monochrome portion of the brush, the planes
;   will be ANDed together (this favors a white background).
;
;   This code doesn't correctly handle huge bitmaps as the source
;   for a pattern.
;
; Entry:
;       DS:SI --> logical object
;       ES:DI --> output object
; Returns:
;       DL = oem_brush_accel flags
; Error Returns:
;       None
; Registers Preserved:
;       BP,ES,FLAGS
; Registers Destroyed:
;       AX,BX,CX,DX,SI,DI,DS,FLAGS
; Calls:
;       None
; History:
;       Wed 25-Jan-1989  -by- David Miller, Video Seven Inc
;       Modified to accomodate VRAM's 256 color modes and the
;       associated internal color bitmap format as well as the
;       changed brush defintion.
;
;       Mon 18-Oct-1987 11:34:15 -by-  Amit Chatterjee [amitc]
;       Adopted interleaved scan line format for the source bitmap.
;       It will still not handle huge maps. The brush structure will still
;       group together all scan lines in a plane.
;
;       Thu 19-Feb-1987 14:06:41 -by-  Walt Moore [waltm]
;       Created.
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
;
realize_pattern proc near
        mov     brush_accel,0           ; No accelerators set for the brush
        lds     si,[si].lbPattern       ; Get pointer to the bitmap
        assumes ds,nothing

        mov     dx,[si].bmWidthBytes    ; Get physical width of bitmap
;
; DX will have the offset to the next scan line for the source.
;
	dec	dx			; to take care of auto inc in MOVSB
        cmp     [si].bmBitsPixel,1      ; Clear 'Z' if color
        lds     si,[si].bmBits          ; --> where the bits are
        je      pattern_copy_mono       ; Handling monochrome source
;
; COLOR ==> COLOR  (just copy pels to brush)
;
	mov	cx,[oem_brush_size]
	sub	cx,size oem_brush_com
	shr	cx,3			; divide by SIZE_PATTERN==8
	dec	cx			; counteract the "dec dx" above
	sub	dx,cx
	mov	ah,SIZE_PATTERN 	; no of scans to move
	push	di

pattern_copy_colour_loop:
        ;mov     cx,SIZE_PATTERN         ; Set # bytes to move
	db	0B9h			; == mov cx,
pattern_copy_numwords	dw SIZE_PATTERN SHL 1	; 16 words = 8*32 bits
        rep     movsw                   ; Move word by word
        add     si,dx                   ; Skip rest of scanline
        dec     ah
        jnz     pattern_copy_colour_loop

	pop	si
	;mov	ax	,my_data_seg
	;mov	ds	,ax
	mov	ds	,my_data_seg
	lea	bx	,abPaletteAccl
	mov	cl	,SIZE_PATTERN

realize_pattern11:
	mov	ch	,SIZE_PATTERN

realize_pattern12:
	lods	BYTE PTR es:[si]
	xlat
	ror	al	,1
	rcl	ah	,1
	dec	ch
	jne	realize_pattern12
	mov	al	,ah
	stosb
	loop	realize_pattern11
        jmp     realize_pattern_done

pattern_copy_mono:

;
; MONOCHROME ==> MONOCHROME  (just copy the pixels)
;
; Handle the monochrome plane of the brush.
;

	add	di	,[oem_brush_size]
	sub	di	,size oem_brush_com
	mov	brush_accel,GREY_SCALE	; This is a grey scale

	movsb
        add     si,dx                   ; update to next scan
        movsb
        add     si,dx
        movsb
        add     si,dx
        movsb
        add     si,dx
        movsb
        add     si,dx
        movsb
        add     si,dx
        movsb
        add     si,dx
        movsb
        add     si,dx
        .errnz  SIZE_PATTERN-8


realize_pattern_done:

	mov	bx,BS_PATTERN
        mov     dh,brush_accel                  ; No brush accelerators
        ret

realize_pattern endp
;
;
;--------------------------Private-Routine------------------------------;
; realize_hatch
;
;   Realize a Hatched Brush
;
;   The requested hatched brush is realized.  Two colors are involved
;   for hatched brushes, the background color, and the hatch color.
;   If these two colors are the same, then the brush will be a
;   solid brush, and the solid brush code will be invoked
;
;   If not, then all 0 bits in the hatch pattern will be set to the
;   background color, and all 1 bits will be set to the foreground
;   color.  Note that hatched colors are solid colors; no dithering
;   takes place for their realization.
;
; Entry:
;       DS:SI --> logical object
;       ES:DI --> output object
; Returns:
;       DL = oem_brush_accel flags
; Error Returns:
;       None
; Registers Preserved:
;       BP,ES,DS,FLAGS
; Registers Destroyed:
;       AX,BX,CX,DX,SI,DI,FLAGS
; Calls:
;       move_hatch
; History:
;       Mon 14-Nov-1988 17:34:50 -by-  Amit Chatterjee [amitc]
;       The logical color structure can now have an index instead of a
;       RGB color value.  If the HIWORD of the color DWORD is 0ffffh, then
;       the LOWORD has an index.
;
;       Thu 19-Feb-1987 14:06:41 -by-  Walt Moore [waltm]
;       Created.
;
;       Mon 30-Jan-1989 11:00:00 -by- Doug Cody, Video Seven Inc
;       Modified to work in VRAM's 256 color modes.
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


        public  realize_hatch
realize_hatch   proc near

	mov	cx,[si].lbHatch 	; Get hatch style
	cmp	cx,MaxHatchStyle	; Hatch style within range?
        jbe     realize_hatch_actual        ; Yes
        jmp     realize_solid           ; No, create a solid brush

realize_hatch_actual:
	push	ds
	push	cx

	; A lot of spillage here! It is impossible to keep this many 32-bit
	; colours in registers on a 286. Once we're happy this works, we should
	; look into using BigFontFlags to select a 386 version which doesn't
	; spill any colours onto the stack.

	lea	si,[si].lbBkColor	; Compute background color
        call    sum_RGB_colors
	call	unpack_physclr
	; spill_colour_1 := ACTUAL physical representation of BG colour
	mov	[spill_colour_1.lo],ax
	mov	[spill_colour_1.hi],dx

        sub     si,lbBkColor-lbColor    ; Compute foreground color
        call    sum_RGB_colors
	call	unpack_physclr
	xor	ax,[spill_colour_1.lo]
	xor	dx,[spill_colour_1.hi]

	; spill_colour_2 := FG colour XOR BG colour (physical reps of both)
	mov	[spill_colour_2.lo],ax
	mov	[spill_colour_2.hi],dx

	pop	cx
	mov	si,cx			; Compute address of hatch pattern
	shiftl	si,3
	lea	si,hatched_brushes[si]	; bx --> hatch pattern to use
        errnz   SIZE_PATTERN-8          ; Pattern must be this size


;	State of regs:desired regs
;	AX - lower word of fg XOR bg:	SI - hatch pattern:
;	BX -				DI - color brush:
;	CX -				DS - input object seg:
;	DX - upper word of fg XOR bg:	ES - output object seg:

;
;	MOVE THE COLOR HATCH portion of the brush

	or	dx,ax			; see if colors are the same (XOR == 0)
	jnz	realize_hatch_17

	; The colors are the same, so just create a solid plane of the color,
	; reusing the modal code we have setup for solid brushes!
	mov	ax,[spill_colour_1.lo]
	mov	dx,[spill_colour_1.hi]
	jmp	FillSolidPlane

realize_hatch_17:
	mov	cl,SIZE_PATTERN 	; cl = outer loop count

realize_hatch_outer_loop:
	mov	ch,SIZE_PATTERN 	; ch = inner loop count
	lods	bptr cs:[si]		; Get next byte of pattern
	mov	bh,al

realize_hatch_inner_loop:
	rol	bh,1
	sbb	ax,ax			; ffff = fg
	cwd
	and	ax,[spill_colour_2.lo]
	; If the bit was 1, then [DX:]AX == fg xor bg, otherwise [DX:]AX == 0
	; When we XOR it with the bg, we get either (fg xor bg) xor bg == fg
	; or 0 xor bg == bg, as desired :)
	xor	ax,[spill_colour_2.lo]
realize_hatch_first_stos label byte
	stosw
realize_hatch_second_word:
	and	dx,[spill_colour_2.hi]
	xor	dx,[spill_colour_2.hi]
	mov	ax,dx
realize_hatch_second_stos label byte
	stosw
realize_hatch_second_word_done:
	dec	ch
	jnz	realize_hatch_inner_loop
	loop	realize_hatch_outer_loop


;       State of regs: desired regs
;	AX -				SI - end hatch pattern:color brush
;	BX - :abPaletteAccl		DI - mono brush
;	CX - :SIZE_PATTERN,SIZE_PATTERN DS - input object seg:our data seg
;	DX -				ES - output object seg


;	MOVE THE MONO HATCH portion of the brush

realize_hatch20:

        sub     si,SIZE_PATTERN         ; Restore hatch pointer
	push	si
	;lea	si	,[di - SIZE_PATTERN * SIZE_PATTERN]
	mov	si	,lp_out_obj.off
	;mov	ax	,my_data_seg
	;mov	ds	,ax
	mov	ds	,my_data_seg
	lea	bx	,abPaletteAccl
	mov	cl	,SIZE_PATTERN

realize_hatch11:
	mov	ch	,SIZE_PATTERN

realize_hatch12:
	; FIXME: What if we don't have a palette?
	lods	BYTE PTR es:[si]
	xlat
	ror	al	,1
	rcl	ah	,1
	dec	ch
	jne	realize_hatch12
	mov	al	,ah
	stosb
	loop	realize_hatch11
	pop	si

;	MOVE THE TRANSPARENCY MASK

;	State of the registers:What we want
;	AX -				SI - hatch pattern:
;	BX -				DI - end mono brush:brush xpar mask
;	CX - 0: 			DS - our data seg
;	DX -				ES - output object seg


	add	di	,oem_brush_mask - oem_brush_mono - SIZE_PATTERN
	mov	ax	,cs
	mov	ds	,ax
	mov	cx,SIZE_PATTERN/2	; Set up move for a single plane
	rep	movsw

;	MOVE THE TRANSPARENCY MASK portion of the brush

	mov	bx,BS_HATCHED		; Set brush style
	xor	dh,dh			; No brush accelerator
	pop	ds
	ret

realize_hatch   endp

;
;--------------------------Private-Routine------------------------------;
; realize_hollow
;
;   Realize Hollow Brush
;
;   This is sleazy.  Hollow brushes are implemented by checking
;   the style flag, and ignoring the contents of the oem_brush_def
;   structure
;
; Entry:
;       DS:SI --> logical object
;       ES:DI --> temp brush area
; Returns:
;       DL = oem_brush_accel flags
; Error Returns:
;       None
; Registers Preserved:
;       BP,DI,ES,DS,FLAGS
; Registers Destroyed:
;       BX
; Calls:
;       None
; History:
;       Thu 19-Feb-1987 14:06:41 -by-  Walt Moore [waltm]
;       Created.
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
;
realize_hollow  proc near
        mov     bx,BS_HOLLOW
	mov	dh,SOLID_BRUSH+ONES_OR_ZEROS
;
realize_just_a_return:
        ret

realize_hollow  endp
;
;
;--------------------------Private-Routine------------------------------;
; rotate_brush_x
;
;   Rotate Brush in X
;
;   The brush is rotated right by the given amount.  This is done
;   so that areas of the screen can be moved, and by realizing a
;   new brush with the correct (x,y), a pattern continued correctly
;   with a previous pattern.
;
; Entry:
;       DS:DI --> oem_brush_def
;       CL     =  alignment count (#ROR's required)
;       DL     =  oem_brush_accel SOLID_BRUSH flag bit
; Returns:
;       None
; Error Returns:
;       None
; Registers Preserved:
;       CH,DH,DI,DS,BP
; Registers Destroyed:
;       AL,SI,FLAGS
; Calls:
;       None
; History:
;       Thu 19-Feb-1987 14:06:41 -by-  Walt Moore [waltm]
;       Created.
;
;       Mon 30-Jan-1989 11:00:00 -by- Doug Cody, Video Seven Inc
;       Modified to work in VRAM's 256 color modes.
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
;
        errnz   SIZE_PATTERN-8
        errnz   oem_brush_clr
        errnz   oem_brush_clr2
        errnz   oem_brush_clr3
        errnz   oem_brush_clr4
        errnz   oem_brush_com1-SIZE_PATTERN*SIZE_PATTERN
        errnz   oem_brush_com2-SIZE_PATTERN*SIZE_PATTERN*2
        errnz   oem_brush_com3-SIZE_PATTERN*SIZE_PATTERN*3
        errnz   oem_brush_com4-SIZE_PATTERN*SIZE_PATTERN*4
;
        PUBLIC  rotate_brush_x
rotate_brush_x  proc near

	sub	cl,SIZE_PATTERN 	; reverse the rotation direction
	neg	cl

        and     cl,07h                  ;check is work needed?
	jne	rotate_brush_x_done_skip
	jmp	rotate_brush_x_done

rotate_brush_x_done_skip:
        push    dx                      ;need to preserve these
        push    bp
        push    di
        push    es
        mov     ax,ds
        mov     es,ax

        ;save rotate count
        push    cx                      ;save rotate count
        mov     si,SIZE_PATTERN

        ;rotate color brush
rotate_brush_x_scan_loop:
        pop     bp                      ;get count of rotate
        push    bp

        ;load scan of colors
        mov     ax,[di]
        mov     bx,[di+2]
        mov     cx,[di+4]
        mov     dx,[di+6]

        ror     bp,1
        jnc     rbx_by_twos
rbx_by_ones:
        xchg    al,ah
        xchg    ah,bl
        xchg    bl,bh
        xchg    bh,cl
        xchg    cl,ch
        xchg    ch,dl
        xchg    dl,dh

rbx_by_twos:
        ror     bp,1
        jnc     rbx_by_fours

        xchg    ax,bx
        xchg    bx,cx
        xchg    cx,dx

rbx_by_fours:
        ror     bp,1
        jnc     rbx_save_result

        xchg    ax,cx
        xchg    bx,dx

rbx_save_result:
        stosw
        mov     ax,bx
        stosw
        mov     ax,cx
        stosw
        mov     ax,dx
        stosw

        dec     si
        jnz     rotate_brush_x_scan_loop

;now we need to rotate the mono mask, note that di
;already points to it's start!!!
        pop     cx
	push	cx

        mov     si,di
        rept    SIZE_PATTERN
          lodsb
          rol   al,cl
          stosb
        endm


;now we need to rotate the xpar mask, note that di
;already points to it's start!!!
	pop	cx

	add	di,oem_brush_mask - oem_brush_mono - SIZE_PATTERN
	mov	si,di

	rept	SIZE_PATTERN
	  lodsb
	  rol	al,cl
	  stosb
	endm

        pop     es
        pop     di
        pop     bp
        pop     dx
rotate_brush_x_done:
        ret

rotate_brush_x  endp
;
;
;--------------------------Private-Routine------------------------------;
; rotate_brush_y
;
;   Rotate Brush in Y
;
;   The brush is rotated in Y by the given amount.  This is done
;   so that areas of the screen can be moved, and by realizing a
;   new brush with the correct (x,y), a pattern continued correctly
;   with a previous pattern.
;
; Entry:
;       DS:DI --> oem_brush_def
;       BX = Y adjustment (ANDed with 111b)
;       CH = 0
;       DL = oem_brush_accel SOLID_BRUSH flag bit
; Returns:
;       None
; Error Returns:
;       None
; Registers Preserved:
;       DH,DI,DS,BP
; Registers Destroyed:
;       AX,BX,CX,DX,SI,FLAGS
; Calls:
;       None
; History:
;       Thu 19-Feb-1987 14:06:41 -by-  Walt Moore [waltm]
;       Created.
;
;       Mon 30-Jan-1989 11:00:00 -by- Doug Cody, Video Seven Inc
;       Modified to work in VRAM's 256 color modes.
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

        errnz   SIZE_PATTERN-8
        errnz   oem_brush_clr

rotate_brush_y  proc near
        push    es
        push    ds
        push    di
        push    si
        push    dx

	sub	bl,SIZE_PATTERN		; reverse the rotation direction
	neg	bl
	and	bl,07

        cld                             ;(INSURANCE)
        xor     ch,ch                   ;(INSURANCE)

        sub     sp,SIZE_PATTERN*SIZE_PATTERN-SIZE_PATTERN

rby_color:
        mov     dx,di

;  set up word count of rotated bytes

        shl     bl,1                    ; bl *= SIZE_PATTERN/2
        shl     bl,1
        mov     cl,bl

;  == copy words from brush to stack

        mov     si,di                   ; ds:si => brush

        mov     ax,ss
        mov     es,ax
        mov     di,sp                   ; es:di => stack

        rep     movsw

;  == copy remaining words to front of brush

        mov     ax,ds
        mov     es,ax
        mov     di,dx                   ; es:di => brush

        mov     cl,SIZE_PATTERN*SIZE_PATTERN/2
        sub     cl,bl
        rep     movsw

;  == copy words from stack to brush

        mov     ax,ss
        mov     ds,ax
        mov     si,sp

        mov     cl,bl
        rep     movsw

;  == frabjous day, es:di => mono brush
;     callous, callay

	mov	dx,di
        shr     bl,1
        shr     bl,1

;  == copy byte(s) from brush to stack

        mov     ax,es
        mov     ds,ax
        mov     si,di

        mov     ax,ss
        mov     es,ax
        mov     di,sp

        mov     cl,bl
        rep     movsb

;  == copy byte(s) to front of brush

        mov     ax,ds
        mov     es,ax
        mov     di,dx

        mov     cl,SIZE_PATTERN
        sub     cl,bl
        rep     movsb

;  == copy bytes(s) from stack to brush

        mov     ax,ss
        mov     ds,ax
        mov     si,sp

        mov     cl,bl
        rep     movsb


;  == Twas brillig and the slithey toad did, es:di => end mono brush
;     gyre and gymbal in the wabe

	add	di	,oem_brush_mask - oem_brush_mono - SIZE_PATTERN
	mov	dx,di

;  == copy byte(s) from brush to stack

        mov     ax,es
        mov     ds,ax
        mov     si,di

        mov     ax,ss
        mov     es,ax
        mov     di,sp

        mov     cl,bl
        rep     movsb

;  == copy byte(s) to front of brush

        mov     ax,ds
        mov     es,ax
        mov     di,dx

        mov     cl,SIZE_PATTERN
        sub     cl,bl
        rep     movsb

;  == copy bytes(s) from stack to brush

        mov     ax,ss
        mov     ds,ax
        mov     si,sp

        mov     cl,bl
        rep     movsb


;  ** restore sanity

        add     sp,SIZE_PATTERN*SIZE_PATTERN-SIZE_PATTERN

        pop     dx
        pop     si
        pop     di
        pop     ds
        pop     es
        ret

rotate_brush_y  endp
;
;
;--------------------------Private-Routine------------------------------;
; realize_font
;
;   Realize a Font
;
;   Realize font is the routine that realizes a logical font into a
;   physical font.  It is possible to punt on this routine and have
;   GDI's font manager realize the desired font, or something close
;   to it, by returning the error code (ax = 0).  That's what I'm
;   going to do.
;
; Entry:
;       AX = 0
; Returns:
;       AX = 0
; Error Returns:
;       AX = 0
; Registers Preserved:
;       BP
; Registers Destroyed:
;       None
; Calls:
;       None
; History:
;       Thu 19-Feb-1987 14:06:41 -by-  Walt Moore [waltm]
;       Created.
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
;
realize_font equ realize_just_a_return
;
; brush_realizations  --  brush_realizations contains the address of
;                         the function that performs the realization
;                         of the desired type of brush.
;
brush_realizations label word
        dw      realize_solid
        dw      realize_hollow
        dw      realize_hatch
        dw      realize_pattern
;
        errnz   BS_SOLID
        errnz   BS_HOLLOW-BS_SOLID-1
        errnz   BS_HATCHED-BS_HOLLOW-1
        errnz   BS_PATTERN-BS_HATCHED-1
;
; Predefined Hatched Brushes
;
; The following brushes are the predefined hatched brushes that
; this driver knows about.
;
hatched_brushes label   byte
        db       H_HATCH_BR_0, H_HATCH_BR_1, H_HATCH_BR_2, H_HATCH_BR_3
        db       H_HATCH_BR_4, H_HATCH_BR_5, H_HATCH_BR_6, H_HATCH_BR_7
        db       V_HATCH_BR_0, V_HATCH_BR_1, V_HATCH_BR_2, V_HATCH_BR_3
        db       V_HATCH_BR_4, V_HATCH_BR_5, V_HATCH_BR_6, V_HATCH_BR_7
        db      D1_HATCH_BR_0,D1_HATCH_BR_1,D1_HATCH_BR_2,D1_HATCH_BR_3
        db      D1_HATCH_BR_4,D1_HATCH_BR_5,D1_HATCH_BR_6,D1_HATCH_BR_7
        db      D2_HATCH_BR_0,D2_HATCH_BR_1,D2_HATCH_BR_2,D2_HATCH_BR_3
        db      D2_HATCH_BR_4,D2_HATCH_BR_5,D2_HATCH_BR_6,D2_HATCH_BR_7
        db      CR_HATCH_BR_0,CR_HATCH_BR_1,CR_HATCH_BR_2,CR_HATCH_BR_3
        db      CR_HATCH_BR_4,CR_HATCH_BR_5,CR_HATCH_BR_6,CR_HATCH_BR_7
        db      DC_HATCH_BR_0,DC_HATCH_BR_1,DC_HATCH_BR_2,DC_HATCH_BR_3
        db      DC_HATCH_BR_4,DC_HATCH_BR_5,DC_HATCH_BR_6,DC_HATCH_BR_7
;
        errnz   HS_HORIZONTAL
        errnz   HS_VERTICAL-HS_HORIZONTAL-1
        errnz   HS_FDIAGONAL-HS_VERTICAL-1
        errnz   HS_BDIAGONAL-HS_FDIAGONAL-1
        errnz   HS_CROSS-HS_BDIAGONAL-1
        errnz   HS_DIAGCROSS-HS_CROSS-1
        errnz   MaxHatchStyle-HS_DIAGCROSS
;
;
; realize_dispatch
;
; realize_dispatch contains the address of the procedure which
; is invoked to realize a given object.
;
realize_dispatch label  word
        dw      realize_pen
        dw      realize_brush
        dw      realize_font
;
        errnz   OBJ_PEN-1
        errnz   OBJ_BRUSH-OBJ_PEN-1
        errnz   OBJ_FONT-OBJ_BRUSH-1
;
sEnd    Code
;

createSeg _INIT,InitSeg,word,public,CODE
sBegin	InitSeg
assumes cs,InitSeg

;--------------------------------------------------------------------------;
; init_modal_realizations
;	modifies the code above to create brushes of the appropriate size
;	for the configured graphics depth
; Entry:
;	ES	= Code
;	AL	= Bytes (not bits!) per pixel
; Returns:
;	AL	= trashed
; Registers Destroyed:
;	AX,FLAGS
; Registers Preserved:
;	BX,CX,DX,SI,DI,BP,DS,ES
; Calls:
;	-
; History:
;	see Git
;--------------------------------------------------------------------------;
public	init_modal_realizations
init_modal_realizations	proc near
	assumes	es,Code

	dec	al
	jnz	@F

	mov	[pattern_copy_numwords],SIZE_PATTERN SHR 1	; 4 words
	mov	[oem_brush_size],size oem_brush_def

	; only need to store one byte at a time for hatched brush
	dec	[realize_hatch_first_stos]
	push	di
	push	cx
remove_second_word:
	lea	di,[realize_hatch_second_word]
	lea	cx,[realize_hatch_second_word_done]
	sub	cx,di
	cld
	mov	al,90h	; blank out the sequence with nops
	rep	stosb

	pop	cx
	pop	di
	ret

@@:
	dec	al
	jnz	@F

	; two bytes, allowing a major simplification of the above code
	mov	[RSSetPlanesPref],0F3h	; make a simple "rep stosw"
	push	di
	push	cx

	lea	di,[RSSetPlanesXchg]
	lea	cx,[RSSetPlanesDone]
	sub	cx,di
	cld
	mov	al,90h	; blank out the sequence with nops
	rep	stosb

	mov	[oem_brush_size],size oem_brush_def2
	mov	[pattern_copy_numwords],SIZE_PATTERN	; 8 words = 8*16 bits
	jmp	remove_second_word	; shared code with 8-bit case

@@:
	dec	al
	jnz	@F

	; three bytes, meaning the second stosw needs to become a stosb
	dec	[RSSetPlanesStos]
	dec	[realize_hatch_second_stos]
	mov	[pattern_copy_numwords],SIZE_PATTERN+(SIZE_PATTERN SHR 1)
	mov	[oem_brush_size],size oem_brush_def3
	ret

@@:
	dec	al
	; no jnz because there shouldn't be any case where AL >= 5

	; the code above should work without issue
	ret
init_modal_realizations	endp

sEnd	InitSeg

        ifdef   PUBDEFS
	public	return_obj_size
	public	realize_exit
	public	realize_pen
	public	realize_pen_10
	public	realize_pen_20
	public	realize_brush
	public	realize_brush_calc_fnptr
	public	realize_brush_xrot_done
	public	realize_brush_done
	public	sum_RGB_colors
	public	sum_RGB_colors_exit
	public	realize_solid
	public	solid_brush_done
	public	greys
	public	realize_pattern
	public	pattern_copy_colour_loop
	public	pattern_copy_mono
	public	realize_hatch
	public	realize_hatch_actual
	public	realize_hollow
	public	realize_just_a_return
	public	rotate_brush_x
	public	rotate_brush_y
	public	realize_font
	public	brush_realizations
	public	hatched_brushes
	public	realize_dispatch
	public	realize_sizes
        endif
;
end
