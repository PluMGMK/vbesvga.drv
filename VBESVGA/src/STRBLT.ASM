;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; strblt.asm
;
; Copyright (c) 1991 Microsoft Corporation.  All Rights Reserved.
;
; This module contains the strblt function and the ExtendedTextOut
; function.
;
; Created: 17-Mar-1987
;
; Exported Functions:	Strblt
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
; Restrictions:
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


FIXED_PITCH_ON = 0			; en/disables smartfix code
;
; This function will perform private stack checking.  In order for
; private stack checking to occur, two symbols must be defined
; prior to the inclusion of cmacros.inc. ?CHKSTK must be defined
; if the cmacros are to perform stack checking on procedures with
; local parameters.  ?CHKSTKPROC must be defined if private stack
; checking will be used.
;
; The actual macro body for ?CHKSTKPROC will be defined later.
;
?CHKSTK = 1
?CHKSTKPROC	macro
		endm
;
	.xlist
	include cmacros.inc
incFont 	= 1			; Include control for gdidefs.inc
incDrawMode	= 1			; Include control for gdidefs.inc
	include gdidefs.inc
	include display.inc
	include ega.inc
	include macros.mac
	include strblt.inc
	include fontseg.inc

	public	exit_strblt_error
	public	only_draw_o_rect
	public	text_completely_clipped
	public	draw_char_string
	public	draw_dispatch
if  FIXED_PITCH_ON
	public	invoke_string_code
endif
	public	maybe_output_o_rect
	public	strblt_clean_up
	public	exit_strblt_null
	public	exit_strblt
	public	get_mode
	public	get_mode_check_for_dda
	public	get_mode_char_extra
	public	get_mode_finish_char_extra
	public	get_mode_get_background
	public	get_mode_neg_spacing
	public	get_font
	public	get_font_abort
	public	get_clip
	public	null_clip_rect
	public	opaque_rect_given
	public	opaque_isnt_clip
	public	see_if_opaque_is_filled
	public	null_opaque_rect
	public	quick_clip
	public	quick_clip_y_fits_on_top
	public	quick_clip_have_y_ext
	public	quick_clip_do_x
	public	quick_clip_have_right_x
	public	quick_clip_case_1_or_2
	public	quick_clip_case_3_or_4
	public	quick_clip_exit
	public	quick_clip_doesnt_show
	public	peg_out_at_max_int
	public	comp_extent
	public	comp_ext_check_for_just
	public	comp_ext_have_ext
	public	comp_ext_peg_right
	public	comp_ext_hard_way
	public	comp_ext_proportional
	public	comp_ext_no_char_extra
	public	comp_ext_prop_loop
	public	comp_ext_prop_add_width
	public	comp_ext_prop_default
	public	comp_ext_check_dda
	public	comp_ext_scan_break
	public	comp_ext_done_scanning
	public	comp_ext_slow_scan
	public	comp_ext_invalid_char
	public	comp_ext_done_slow_scan
	public	comp_ext_have_breaks
	public	comp_ext_run_dda
	public	comp_ext_dont_distribute
	public	comp_ext_save_err_term
	public	comp_ext_done_dda
	public	comp_ext_peg_and_save
	public	v_comp_ext_peg_right
	public	wce_bad_char
	public	wce_have_break_char
	public	wce_neg_dda
	public	wce_next_char
	public	wce_good_character
	public	wce_have_tot_extra
	public	wce_get_users_width
	public	wce_have_width
	public	wce_char_not_new_rhs
	public	wce_extra_not_new_rhs
	public	wce_see_if_next
	public	wce_peg_out
	public	comp_byte_dont_combine
	public	return_null_interval
	public	color_bitmap_opaque
	public	mono_bitmap_opaque
	public	bitmap_opaque
	public	bo1_first_and_last
	public	bo1_both_loop
	public	bo1_last_only
	public	bo1_first_only
	public	bo1_restore_start_addr
	public	bo1_inner_start
	public	bo_start_inner_loop
	public	bo_inner_loop
	public	bo_done
	public	bitmap_opaque_0s
	public	bo0_first_and_last
	public	bo0_both_loop
	public	bo0_last_only
	public	bo0_first_only
	public	bo0_one_only_loop
	public	bo0_restore_start_addr
	public	oor_check_y_bounds
	public	oor_check_x_bounds
	public	oor_exclusive_rects
	public	oor_inclusive_rects
	public	oor_comp_bottom
	public	oor_comp_middle_y
	public	oor_see_if_top_or_bottom
	public	oor_see_about_bottom
	public	oor_no_bottom_area
	public	oor_see_about_middle
	public	oor_process_rhs
	public	oor_output_one_rect
	public	oor_check_lhs_only
	public	oor_a_return
	public	oor_output_both_sides
	public	oor_overlapping_middle
	public	oor_combine_with_lhs
	public	oor_output_both_anyway
	public	v_gdd_dev_is_bitmap
	public	get_device_data

ifdef	EXCLUSION
	public	gdd_exclude_is_opaque
	public	gdd_exclude_text_or_both
	public	gdd_exclude_have_rect
endif

	public	gdd_dev_is_bitmap
	public	gdd_small_bitmap
	public	gdd_finish_bitmap
	public	gdd_is_color_bitmap
	public	gdd_huge_bitmap
	public	gdd_dont_do_union
	public	gdd_have_y_ext
	public	gdd_have_segment
	public	gdd_have_our_color
	public	gdd_different_segments
	public	gdd_do_next_whole_segment
	public	gdd_do_last_segment

        include cursor.inc
	include rt.mac
	.list
;
	??_out	strblt
;
; Link time constants describing the size and color format
; that the EGA will be running in.
;
ifdef  PALETTES
	externB PaletteModified		; set when palette is modified
endif
;
; Other functions required for strblt.
;
ifdef PALETTES
  	externFP TranslateTextColor
endif
;
if    FIXED_PITCH_ON
	externNP fixed_pitch_strblt	; Fixed pitch 8 wide font code
endif
	externNP build_string		; All other font code
;
ifdef	 EXCLUSION
	externNP exclude		; Exclude area from screen
	externNP unexclude		; Clear excluded area
endif

sBegin	Data
EXTRN	ScreenSelector:word
        externB enabled_flag            ; Non-zero if output allowed
sEnd    Data
;
sBegin	Code
assumes cs,Code
;
	public	??BigFontFlags
??BigFontFlags	db	0		; FALSE = real mode or 286 procesor
					; TRUE	= 386 protected mode
	externW	ColourFormat_CS
	externW	MemoryWidth
	externW	pxbytes
	externNP ipc_to_rgb	; in RGB2IPC.ASM

;--------------------------Exported-Routine-----------------------------;
; Strblt
;
; This is the old strblt entry point.  Null parameters are pushed
; for the ExtTextOut's extra parameters, and control given to
; ExtTextOut.
;
; Entry:
; 	EGA registers in default state
; Returns:
;	DX = Y extent of string if extent call
;	AX = X extent of string if extent call
;	EGA registers in default state
; Error Returns:
;	DX:AX = 8000:0000H
; Registers Preserved:
;	SI,DI,DS,ES,BP
; Registers Destroyed:
;	AX,BX,CX,DX,FLAGS
; Calls:
;	See ExtTextOut
; History:
;	Wed 01-Feb-1989 -by-  Doug Cody, Video Seven, Inc
;       Extensively modified for 256 color support
;
;	Fri 21-Oct-1988 09:10:15 -by-  Amit Chatterjee [amitc]
;       Adopted interleaved scan line format for small bitmaps as well
;
;	Thu 09-Apr-1987 13:36:08 -by-  Walt Moore [waltm]
;	Created.
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
cProc	Strblt,<FAR,PUBLIC,WIN,PASCAL>,<si,di,es,ds>
	parmD	lp_device		; Destination device
	parmW	x			; Left origin of string
	parmW	y			; Top  origin of string
	parmD	lp_clip_rect		; Clipping rectangle
	parmD	lp_string		; The string itself
	parmW	count			; Number of characters in the string
	parmD	lp_font 		; Font to use
	parmD	lp_draw_mode		; Drawmode structure to use
	parmD	lp_xform		; Current text transform
;
; ExtTextOut parameters we have to dummy up.
;
;	parmD	lp_dx			; Widths for the characters
;	parmD	lp_opaque_rect		; Opaquing rectangle
;	parmW	eto_options		; ExtTextOut options
;
cBegin	<nogen>

	WriteAux <'Strblt'>
;
	pop	cx			; Save caller's return address
	pop	bx
	xor	ax,ax
	push	ax			; Push null for lp_dx
	push	ax
	push	ax			; Push null for lp_opaque_rect
	push	ax
	push	ax			; Push null for options
	push	bx			; Restore return address
	push	cx
	errn$	ExtTextOut

cEnd	<nogen>
;
;
;--------------------------Exported-Routine-----------------------------;
; ExtTextOut
;
; Entry:
;	EGA registers in default state
; Returns:
;	DX = Y extent of string if extent call
;	AX = X extent of string if extent call
;	EGA registers in default state
; Error Returns:
;	DX:AX = 8000:0000H
; Registers Preserved:
;	SI,DI,DS,ES,BP
; Registers Destroyed:
;	AX,BX,CX,DX,FLAGS
; Calls:
;	exclude
;	unexclude
;	......
; History:
;	Wed 01-Feb-1989 -by-  Doug Cody, Video Seven, Inc
;       Extensively modified for 256 color support
;
;	Tue 18-Aug-1987 16:30:43 -by-  Walt Moore [waltm]
;	Added saving enabled_flag.
;
;	Thu 09-Apr-1987 13:36:08 -by-  Walt Moore [waltm]
;	Created.
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
	define_frame ExtTextOut 	; Define frame
;
cBegin
;
	lahf

rtIF	BigFontFlags

	.386
	push	esi			; save the high order words 
	push	edi			; of these registers.
	push	ebp
	push	ebx
        .286
rtENDIF
	sahf
;
	if	???			; Do test only if locals
	jnc	skip_ret
	jmp	exit_strblt_error	; No room for locals, return now
skip_ret:
	endif
;
WriteAux	<'ExtTOut'>
;
	mov	al,enabled_flag 	; Save enabled_flag incase we need it
	mov	local_enabled_flag,al
	mov	ax,ds
	mov	driver_data_seg,ax
	mov	ax,ScreenSelector
	mov	local_ScreenSelector,ax
	mov	ax,130
	mov	jak_text_buffer_width,ax
	xor	ax,ax
	mov	ax,VScreen_Width
	mov	local_VScreen_Width,ax
	mov	ax,off_lp_draw_mode
	mov	bx,seg_lp_draw_mode
	mov	off_xlate_draw_mode,ax
	mov	seg_xlate_draw_mode,bx
;
;----------------------------------------------------------------------------;
; at this point we will include the on-the-fly translation of objects for    ;
; drivers which support the palette manager.				     ;
;----------------------------------------------------------------------------;
;
ifdef PALETTES
	cmp	PaletteModified,0ffh	; has the palette been modified ?
	jnz	do_not_translate
;
	push	ds			; save
	lds	si,lp_device		; load the device
	lodsw				; load the type
	pop	ds			; restore own segment
	or	ax,ax			; is it a physical device ?
	jz	do_not_translate	; no, so no translation

	arg	xlate_draw_mode
	cCall	TranslateTextColor

	mov	seg_xlate_draw_mode,dx
	mov	off_xlate_draw_mode,ax
;
do_not_translate:

endif
;
;----------------------------------------------------------------------------;
;
	call	get_mode		; Get data from drawmode, set flags
	call	get_font		; Get font data (aborts if invalid)
;
; If the character count is negative, then the extent of the
; string should be calculated.  If positive, then the string
; should be drawn.
;
	mov	ax,count
	or	ax,ax
;	jg	draw_char_string	; Positive count, output string
	jle	dont_draw_char_string
	jmp	draw_char_string
dont_draw_char_string:
	jz	only_draw_o_rect	; No chars, might have opaque rect
	mov	accel,bh		; Need to save flags for extent code
	mov	excel,bl
	call	comp_extent		; Compute extents, update BrkErr
	jmp	exit_strblt
;
exit_strblt_error:
	xor	ax,ax			; Return DX:AX = 8000:0000
	mov	dx,8000h		; to show an error
	jmp	exit_strblt
;
v_exit_strblt_null:
	jmp	exit_strblt_null
;
; There are no characters to output.  If there is an opaquing
; rectangle to be filled with the background color, we still
; must do that.
;
only_draw_o_rect:
ifdef debug
int 1
endif

        call    get_clip                ; Aborts if NULL clip region
;;;;;;;;call	quick_clip
;
text_completely_clipped:
	test	bl,OPAQUE_RECT
	jz	v_exit_strblt_null	; No opaque rectangle
	mov	accel,bh
	mov	excel,bl
	call	get_device_data 	; Get device specific parameters
	jmp	maybe_output_o_rect
;
; Normal text output is to occur.  Perform a quick rejection
; on the string. If the string is clipped then we can abort
; now.
;
draw_char_string:
	call	get_clip		; Aborts if NULL clip region
	call	quick_clip
	test	bl,TEXT_VISIBLE
;	jz	text_completely_clipped ; Nothing shows, see about opaque rect
	jnz	text_not_completely_clipped
	jmp	text_completely_clipped
text_not_completely_clipped:
	mov	accel,bh
	mov	excel,bl
	call	get_device_data 	; Get device specific parameters
;
; Based on the characteristics of the strblt operation,
; dispatch to the correct handler.
;
	mov	bl,accel		; If transparent mode and
	test	bl,IS_OPAQUE		; there is an opaque rectangle
	jnz	draw_dispatch		; then it must be output now.
	mov	al,excel
	test	al,OPAQUE_RECT
	jz	draw_dispatch
	and	al,not OPAQUE_RECT
	mov	excel,al
	xchg	ax,bx			; Need excel in BL
	call	output_o_rect
	mov	bl,accel
;
draw_dispatch:
	mov	ax,CodeOFFSET build_string
;
if FIXED_PITCH_ON
	xor	bl,WIDTH_IS_8
	test	bl,WEIRD_SPACING+WIDTH_IS_8
	jnz	invoke_string_code
	mov	ax,CodeOFFSET fixed_pitch_strblt
;
invoke_string_code:
endif
;
   	assumes ss,StrStuff
;
if 0
;
; This code shows whats really happening, but is larger and
; takes longer to execute than the rep mosvw below.
;
   	push	ss_height		; Save those stack locations which
   	push	ss_next_scan		; will be trashed
   	push	ss_draw
   	push	ss_draw_clipped
   	push	ss_phases
   	push	word ptr ss_clip_mask
   	errnz	ss_num_chars-ss_clip_mask-1
 	push	ss_pixbytes
	push	ss_p_frame
endif
;
					;JAK low-stack copy suspicious
	mov	dx,ds			; save low paragraph of stack seg
	mov	bx,ss
	mov	ds,bx
	mov	es,bx
	xor	si,si
	lea	di,ss_save_area
;
	mov	cx,8
	cld
	rep	movsw
;
	mov	ds,dx
;
   	call	ax			; This guy does the real work
;
	mov	dx,ds			; restore low paragraph of stack seg
	mov	bx,ss
	mov	ds,bx
	mov	es,bx
	lea	si,ss_save_area
	xor	di,di
;
	mov	cx,8
	cld
	rep	movsw
;
	mov	ds,dx
;
if 0
;
; This code shows whats really happening, but is larger and
; takes longer to execute than the rep mosvw above.
;
	pop	ss_p_frame
 	pop	ss_pixbytes
   	errnz	ss_num_chars-ss_clip_mask-1
   	pop	word ptr ss_clip_mask
   	pop	ss_phases
   	pop	ss_draw_clipped
   	pop	ss_draw
   	pop	ss_next_scan
   	pop	ss_height
   	assumes ss,nothing
endif
;
maybe_output_o_rect:
	mov	bl,excel
	test	bl,OPAQUE_RECT
	jz	strblt_clean_up
	call	output_o_rect
;
strblt_clean_up:
	test	excel,IS_DEVICE 	; If this is the device,
	jz	exit_strblt_null	; then some cleanup is in order
;
ifdef	EXCLUSION
	call	unexclude
endif
;
exit_strblt_null:
	xor	ax,ax			; Return DX:AX = 0000:0000
	cwd				; to show success
;
exit_strblt:
;
rtIF	BigFontFlags

	.386
	pop	ebx
        pop     ebp                     ; restore the high order words 
	pop	edi			; of these registers.
	pop	esi
        .286
rtENDIF

cEnd

;
;--------------------------Private-Routine------------------------------;
; get_mode
;
;   Get Mode Parameters
;
;   The text/background colors and any justification information
;   is retrieved from the DrawMode structure and saved on the frame.
;
;
;   The following "accel" flags will be set accordingly:
;
;	HAVE_BRK_EXTRA	Set if extra pixels to insert each break character
;
;	DDA_NEEDED	Set if some number of pixels to distribute over
;			the break characters.  BrkRem, BrkErr, and
;			BrkCount are only valid if this bit is set.
;
;	HAVE_CHAR_EXTRA Set if there are extra pixels to be instered
;			between every character.  CharXtra is only
;			valid if this bit is set
;
;	IS_OPAQUE	Set if the background mode is opaque
;
;	HAVE_WIDTH_VECT Set if a non-null width vector was given
;
;
;
;   The following "excel" flags will be set if needed:
;
;	None
;
;
;   The following frame variables are initialized:
;
;	colors		Text/background colors
;	tot_brk_extra	Total break extra
;	char_xtra	# extra pixels to add each char
;
;
;   The following frame variables are initialized if needed:
;
;	brk_extra	# extra pixels to add each break char
;	brk_err 	Justification DDA error term
;	brk_count	DDA - # breaks into which brk_rem
;	brk_rem 	   extra pixels are distributed
;
; Entry:
;	None
; Returns:
;	BH = accel flags
;	BL = excel flags
; Error Returns:
;	None
; Registers Preserved:
;	DX,DI,ES,BP
; Registers Destroyed:
;	AX,CX,SI,DS,FLAGS
; Calls:
;	None
; History:
;	Wed 01-Feb-1989 -by-  Doug Cody, Video Seven, Inc
;	Modified for 256 color support
;
;	Thu 19-Feb-1987 14:06:41 -by-  Walt Moore [waltm]
;	Created.
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
get_mode proc	near
	mov	bx,off_lp_dx
	or	bx,seg_lp_dx
	neg	bx			; 'C' set if width vector
	sbb	bx,bx			; BX = FFFF if width vector, else 0
	and	bx,HAVE_WIDTH_VECT shl (8-2) ; Also clears BL for "excel" flags
;
        lds     si,lp_device
	mov	cl,[si].bmBitsPixel	; mono=1,color>=8
	mov	BitsaPixel,cl
;
	lds	si,xlate_draw_mode	; Most information is in the DrawMode
	assumes ds,nothing
;
	xchg	ch,bh			; stash BH for the moment
	; Get text color info
	mov	ax,[si].TextColor.lo
	mov	dx,[si].TextColor.hi
	cmp	cl,1			   ; is this a mono case?
	jnz	@F			   ; no, use the color
	; For the mono case, just set/clear the LSB...
	call	ipc_to_rgb		   ; get accelerators in DH
	and	dh,1
	errnz	MONO_BIT-00000001B
	mov	al,dh
	cbw
	cwd
@@:
	mov	colors.FOREGROUND.lo,ax
	mov	colors.FOREGROUND.hi,dx

	; Get background color info
	mov	ax,[si].bkColor.lo
	mov	dx,[si].bkColor.hi
	cmp	cl,1			   ; is this a mono case?
	jnz	@F			   ; no, use the color
	; For the mono case, just set/clear the LSB...
	call	ipc_to_rgb		   ; get accelerators in DH
	and	dh,1
	errnz	MONO_BIT-00000001B
	mov	al,dh
	cbw
	cwd
@@:
	mov	colors.BACKGROUND.lo,ax
	mov	colors.BACKGROUND.hi,dx
	xchg	bh,ch			; get BH back

					;JAK color problem perhaps?
;
	mov	ax,[si].TBreakExtra	; Get any justification
	mov	tot_brk_extra,ax	; Needed for QuickClip code
	or	ax,ax
	jz	get_mode_char_extra	; No justification
;
; Some text justification will be required for the string.
; If BreakRem is zero, then the only action required is to
; adjust by BreakExtra pixels for each break character
; encountered.  If BreakRem is non-zero, then the DDA must
; be run to distribute the remaining pixels.
;
	mov	cx,[si].BreakExtra
	mov	brk_extra,cx		; Save for justification code
	jcxz	get_mode_check_for_dda	; None to add
	or	bh,HAVE_BRK_EXTRA shr 2 ; Show some form of justification
	errnz	HAVE_BRK_EXTRA-00001000b; Don't want to shift it too far
;
get_mode_check_for_dda:
	mov	cx,[si].BreakRem	; Will the DDA be required?
	jcxz	get_mode_char_extra	; No
	mov	brk_rem,cx		; Yes, save count of odd pixels
	or	bh,DDA_NEEDED shr 2	; show DDA is needed
	mov	cx,[si].BreakErr	; save the DDA error term
	mov	brk_err,cx		;
	mov	cx,[si].BreakCount	; save DDA addback value
	mov	brk_count,cx
	errnz	DDA_NEEDED-00000100b	; Don't want to shift it too far
;
get_mode_char_extra:
	mov	cx,[si].CharExtra	; Get possible CharExtra
	mov	char_xtra,cx		; Must save regardless of being 0
	or	ax,cx			; Combine with TBreakExtra
	jl	get_mode_neg_spacing	; Could be stepping backwards
;
get_mode_finish_char_extra:
	neg	cx			; 'C' if CX is non-zero (extra pixels)
	rcl	bh,1			; Show CHAR EXTRA if present
	errnz	HAVE_CHAR_EXTRA-00000010b
;
get_mode_get_background:
        mov     al,bptr [si].bkMode     ; Get BkMode
        sub     al,OPAQUE               ; set al to zero if OPAQUE
        neg     al                      ; 'C' set if not OPAQUE
	cmc				; 'C' set if opaque
	rcl	bh,1			; Set/Clear opaque bit
	errnz	TRANSPARENT-1
	errnz	OPAQUE-2
	errnz	IS_OPAQUE-00000001b
	ret
;
get_mode_neg_spacing:
	or	bh,NEG_SPACING shr 2	; Show step backwards possible
	jmp	get_mode_finish_char_extra

get_mode endp
;
;
;--------------------------Private-Routine------------------------------;
; get_font
;
;   Get Font Parameters
;
;   The following frame variables are initialized:
;
;	lfd			local font definition structure
;	null_char_offset	offset of the null character
;
; Entry:
;	BH = accel flags
; Returns:
;	BH = new accel flags
;	ES = SS
; Error Returns:
;	To exit_strblt_error if font isn't supported
; Registers Preserved:
;	BL,CX,DX
; Registers Destroyed:
;	AX,SI,DI,DS,FLAGS
; Calls:
;	None
; History:
;	Tue 17-Mar-1987 15:22:11 -by-  Walt Moore [waltm]
;	Created.
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
get_font proc	near
	lds	si,lp_font		; Prepare for copying data from font
	assumes ds,FontSeg
;
	lea	di,lfd			; Set ES:DI --> local font definition
	mov	ax,ss
	mov	es,ax
	assumes es,nothing
;
	cmp	si,offset fsType	; Is offset where we need it?
	jne	get_font_abort		; Cannot use fontseg, abort
;
rtIF	BigFontFlags
	cmp	fsVersion,300h		; If not a version 3.00 font,
	jne	get_font_abort		; cannot use it
rtELSE
	cmp	fsVersion,200h		; If not a version 2.00 font,
	jne	get_font_abort		; cannot use it
rtENDIF
;
; Save the width of the characters.  If the font is fixed-pitch,
; this field will be non-zero and the width of all characters.
; If this field is zero, then the font is proportional, and
; the width table will have to be used to compute the individual
; character widths.
;
; The accelerators for FIXED_PITCH and WIDTH_IS_8 will be
; set based on this field.
;
	mov	si,offset fsPixWidth	; --> first field of interest
	lodsw
	stosw
	errnz	font_width		; Must be first field
;
	rol	bh,1			; Prepare the accel flag for rotating
	rol	bh,1			; in the fixed-pitch and 8-wide flags
	neg	ax			; 'C' set if fixed pitch font (AX <> 0)
	rcr	bh,1			; Rotate in fixed pitch flag
	errnz	FIXED_PITCH-01000000b
;
	add	ax,8			; Make AX = 0 if eight wide fixed pitch
	cmp	ax,1			; 'C' if 8 wide fixed pitch
	rcr	bh,1			; Rotate in 8 wide flag
	errnz	WIDTH_IS_8-10000000b
;
; Save the height of the font.  It will be required for both
; clipping and output.
;
	movsw				; Move height of the font
	errnz	font_height-font_width-2
	errnz	fsPixHeight-fsPixWidth-2
;
; Save the maximum width of a character.	This can be useful if
; a quick clippping test were made to see if any clipping is
; required for the string.
;
	add	si,fsMaxWidth-fsPixHeight-2
	movsw
	errnz	max_width-font_height-2
;
; Save the value of the first and last characters.  Bias the
; last character value by the first character before saving
; it.  This will eliminate one comparison when performing the
; range check on the character.
;
; This
; 	sub	al,lfd.first_char
; 	cmp	al,lfd.last_char
; 	ja	use_default
;
; is better than
;
; 	cmp	al,lfd.last_char
; 	ja	use_default
; 	sub	al,lfd.first_char
; 	jb	use_default
;
	lodsw				; AL = fsFirstChar, AH = fsLastChar
	sub	ah,al			; Bias last char by first char
	stosw
	errnz	last_char-first_char-1
	errnz	first_char-max_width-2
	errnz	fsFirstChar-fsMaxWidth-2
	errnz	fsLastChar-fsFirstChar-1
;
; Both the break character and the default character are already
; biased by fsFirstChar. Just copy them to the frame
;
	movsw
	errnz	default_char-last_char-1
	errnz	break_char-default_char-1
	errnz	fsDefaultChar-fsLastChar-1
	errnz	fsBreakChar-fsDefaultChar-1
;
	xchg	ah,al			; Compute and save the offset of
	xor	ah,ah			; the null character
	inc	ax
;
;----------------------------------------------------------------------------;
; for normal code each entry is 4 bytes with last two bytes being offset to  ;
; bits, for protected mode code each entry is 6 bytes with last 4 bytes being;
; pointer to bits.							     ;
;----------------------------------------------------------------------------;
;
rtIF	BigFontFlags
	.386
	shl	ax,1
     	mov	si,ax
	shl	ax,1
	add	si,ax
	mov	eax,dword ptr fs30CharOffset[si][PROP_OFFSET+0]
	mov	null_char_offset,eax		; 32 bit offset
        .286
rtELSE
	shiftl	ax,2
	mov	si,ax
	mov	ax,wptr fsCharOffset[si][PROP_OFFSET+0]
	mov	wptr null_char_offset+0,ax	; only an offset, no segment
rtENDIF
;
;----------------------------------------------------------------------------;
;
; fsBitsPointer is the pointer to the top scan of the first
; character in the font.  Copy it as is.  It will be altered later.
;
	mov	si,offset fsBitsPointer
	movsw
	lodsw
	stosw
	errnz	lp_font_bits-break_char-1
	ret
;
; This driver doesn't handle the given font.  Remove the
; caller's return address and exit strblt with an error
;
get_font_abort:
	pop	ax			; Remove return address
	jmp	exit_strblt_error

get_font endp
;
;
;--------------------------Private-Routine------------------------------;
; get_clip
;
; Entry:
;	BH = accel flags
; Returns:
;	BH = accel flags
;	BL = excel flags
;	clip   structure initialized
;	o_rect structure initialized if opaque rectangle given
; Error Returns:
;	None
; Registers Preserved:
;	None
; Registers Destroyed:
;	AX,CX,DX,SI,DI,DS,ES,FLAGS
; Calls:
;	None
; History:
;	Thu 09-Apr-1987 23:15:27 -by-  Walt Moore [waltm]
;	Created.
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
get_clip	proc   near
	cld
	lds	si,lp_clip_rect
	assumes ds,nothing
;
	mov	ax,eto_options
	test	ax,ETO_OPAQUE_CLIP+ETO_OPAQUE_FILL
	jnz	opaque_rect_needed
;
; Only a clip rectangle is needed.  Simply copy it to the frame
; and exit.
;
	mov	ax,ss
	mov	es,ax
	lea	di,clip
	movsw				; We assume that we will never
	movsw				; get passed a null rectangle
	movsw
	movsw
	ret
;
; The intersection of the clipping rectangle and the opaque
; rectangle was null, and we were asked to use the result as
; the real clipping rectangle.  Nothing to do now but exit.
;
null_clip_rect:
	pop	bx
	jmp	exit_strblt_null
;
opaque_rect_needed:
	mov	cx,seg_lp_opaque_rect	; If no rectangle, pretend it is
	jcxz	null_clip_rect		; clipped
	mov	di,off_lp_opaque_rect
	mov	es,cx
	assumes es,nothing
;
opaque_rect_given:
	test	ax,ETO_OPAQUE_CLIP
	jz	opaque_isnt_clip
;
; The opaque rectangle is to be intersected with the clipping
; region, and the result used as the actual clip region.
;
	lodsw				; Clip left
	errnz	left
	mov	cx,es:[di].left
	cmp	ax,cx
	jg	short @f
	mov	ax,cx
@@:
	mov	o_rect.left,ax
	mov	clip.left,ax
;
	lodsw				; Clip top
	errnz	top-left-2
	mov	cx,es:[di].top
	cmp	ax,cx
	jg	short @f
	mov	ax,cx
@@:
	mov	o_rect.top,ax
	mov	clip.top,ax
;
	lodsw				; Clip right
	errnz	right-top-2
	mov	cx,es:[di].right
	cmp	ax,cx
	jl	short @f
	mov	ax,cx
@@:
	cmp	ax,clip.left
	jle	short null_clip_rect	; Right side <= left side, doesn't show
	mov	o_rect.right,ax
	mov	clip.right,ax
;
	lodsw				; Clip bottom
	errnz	bottom-right-2
	mov	cx,es:[di].bottom
	cmp	ax,cx
	jl	short @f
	mov	ax,cx
@@:
	cmp	ax,clip.top
	jle	null_clip_rect		; Bottom <= top, doesn't show
	mov	o_rect.bottom,ax
	mov	clip.bottom,ax
	jmp	see_if_opaque_is_filled
;
; The opaque rectangle is to be intersected with the clipping
; region.  It will not be used as the actual clip rectangle.
;
opaque_isnt_clip:
	lodsw				; Clip left
	mov	clip.left,ax
	errnz	left
	mov	cx,es:[di].left
	cmp	ax,cx
	jg	short @f
	mov	ax,cx
@@:
	mov	o_rect.left,ax
;
	lodsw				; Clip top
	mov	clip.top,ax
	errnz	top-left-2
	mov	cx,es:[di].top
	cmp	ax,cx
	jg	short @f
	mov	ax,cx
@@:
	mov	o_rect.top,ax
;
	lodsw				; Clip right
	mov	clip.right,ax
	errnz	right-top-2
	mov	cx,es:[di].right
	cmp	ax,cx
	jl	short @f
	mov	ax,cx
@@:
	mov	o_rect.right,ax
;
; We set the condition code for a null oapque rectangle now, but
; we cannot make the jump until we've saved the bottom of the
; clip region.
;
	cmp	ax,o_rect.left
	lodsw				; Clip bottom
	mov	clip.bottom,ax
	jle	null_opaque_rect	; Right side <= left side, doesn't show
	errnz	bottom-right-2
	mov	cx,es:[di].bottom
	cmp	ax,cx
	jl	short @f
	mov	ax,cx
@@:
	cmp	ax,o_rect.top
	jle	null_opaque_rect	; Bottom <= top, doesn't show
	mov	o_rect.bottom,ax
;
; If the user has specified that the opaque rectangle is to
; be filled,  then show that the rectangle is present.
;
see_if_opaque_is_filled:
	test	eto_options,ETO_OPAQUE_FILL
	jz	null_opaque_rect
	or	bl,OPAQUE_RECT		; Show it really exists
;
null_opaque_rect:
	ret

get_clip	endp
;
;
;--------------------------Private-Routine------------------------------;
; quick_clip
;
;   Quick Clip Test
;
;   A quick test is made to see if the given string is entirely
;   clipped, possibly clipped, or completely visible.
;
;   An entirely clipped string can be discarded immediately.  A
;   completely visible string can skip the clipping code while
;   the stack data is being constructed.  A possibly clipped
;   string may or may not be clipped.  The clipping code must
;   be run while the stack data is being constructed in this
;   case.
;
;   At the same time, the string's bounding box minimum left and
;   maximum right edges are computed and saved.  This will be used
;   by the cursor exclusion code.
;
; Entry:
;	AX = character count
;	BH = accel flags
;	BL = excel flags
; Returns:
;	BH = new accel flags
;	BL = excel flags
;	text_bbox structure initialized if any text is visible
; Error Returns:
;	None
; Registers Preserved:
;	None
; Registers Destroyed:
;	AX,CX,DX,SI,DI,DS,ES,FLAGS
; Calls:
;	None
; History:
;	Tue 17-Mar-1987 15:22:11 -by-  Walt Moore [waltm]
;	Created.
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
quick_clip	proc   near
;
;
;-----------------------------------------------------------------------
;
;				   ----
;				       | compute how many scans are in
;	stuff here is clipped	       | this area.  These scans are
;				       | clipped out
;				       |
;	 -----------------------   ----
;	| top			|      | these scans fit
;	|			|  ----
;	|			|
;	|   clip rectangle	|
;	|			|
;	|			|
;	| bottom		|
;	 -----------------------
;
;
;	stuff here is clipped
;
;
;-----------------------------------------------------------------------
;
	xor	dx,dx			; Amount clipped on top is 0
	mov	cx,y			; Need starting Y coordinate
	mov	di,lfd.font_height	; and height of the font
	mov	ax,cx			; Don't destroy Y coordinate
	sub	ax,clip.top		; Is Y clipped on top?
	jge	quick_clip_y_fits_on_top;  No, Y fits within top
;
; The Y coordinate is less than the top of the clip rectangle.
; Move the Y coordinate down the screen (+Y) by the amount
; clipped.  If the amount clipped is >= the font height, then
; the entire string is clipped and can be discarded.
;
	add	di,ax			; Subtract clip overhang from height
	jle	quick_clip_doesnt_show	; Nothing shows, exit now
	sub	cx,ax			; Offset starting Y coordinate
	neg	ax
	xchg	ax,dx
;
quick_clip_y_fits_on_top:
	mov	text_bbox.top,cx	; Save new Y coordinate
	mov	amt_clipped_on_top,dx	; Save for output routines
;
;-----------------------------------------------------------------------
;
;	The starting Y has been computed.  Compute how many scans must
;	be clipped off the bottom of the font.	The clipping can be done
;	by adjusting the height.
;
;	stuff here is clipped
;
;
;	 -----------------------
;	| top			|
;	|			|
;	|			|
;	|   clip rectangle	|
;	|			|
;	|			|  ----
;	| bottom		|      | these scans fit
;	 -----------------------   ----
;				       | compute how many scans are in
;				       | this area.  These scans are
;	stuff here is clipped	       | clipped out
;				       |
;				   ----
;
;-----------------------------------------------------------------------
;
	mov	ax,cx			; Leave CX = text_bbox.top
	add	ax,di			; Compute text_bbox.bottom
	mov	dx,ax
	sub	ax,clip.bottom		; Is Y clipped on the bottom?

;----------------------------------------------------------------------------;
; ax could go negative at this point, so we have to treat that as a big numbr;
; as we don't want a wrap over. If the end of the character was genuinenly   ;
; negative, we will not get here. So do a unsigned compare.		     ;
;----------------------------------------------------------------------------;

	jb	quick_clip_have_y_ext	; No, height fits within clip rect

;----------------------------------------------------------------------------;
        sub     di,ax                   ; Clip height
	jle	quick_clip_doesnt_show	; Nothing shows, exit
	sub	dx,ax			; Clip bottom of text box
;
; The string has been clipped in Y, and at least one scan will be visible.
;
quick_clip_have_y_ext:
	mov	clipped_font_height,di	; Save height of what will be drawn
	mov	text_bbox.bottom,dx
;
; If the vertical portion of the text fits within the opaque
; rectangle, then set the BOUNDED_IN_Y flag for the code which
; creates the stack data.  When this flag is set, that code
; should attempt to fill to byte boundaries.
;
	test	bl,OPAQUE_RECT
	jz	quick_clip_do_x
	cmp	dx,o_rect.bottom
	jg	quick_clip_do_x 	; Text extends below opaque bottom
	cmp	cx,o_rect.top
	jl	quick_clip_do_x 	; Text extends above opaque top
	or	bl,BOUNDED_IN_Y
;
;-----------------------------------------------------------------------
;
;	Clip the string in X.  An attempt will be made to detect
;	the following five cases based on the starting X, the
;	character count, and the maximum width of a character.
;
;	Because of interactions with maximum character width,
;	intercharacter spacing, or break character spacing, it
;	is possible for a case1 or case3 string to incorrectly
;	show that clipping is required.
;
;	If a negative character extra, negative total break extra,
;	or the delta vector is present, then we cannot perform the
;	quick clipping since we could be stepping backwards.
;
;
;		 -----------------------
;		|			|
;		|			|
;    case1   case2	 case3	      case4   case5
;		|			|
;		|   clip rectangle	|
;		|			|
;		|			|
;		|			|
;		 -----------------------
;	       left		      right
;
;
;-----------------------------------------------------------------------
;
; As long as we don't allow a pixel to be drawn at a location
; less than the starting X, we can test for Case 5 before we
; test for width_vector and negative spacing.
;
quick_clip_do_x:

if 1
	mov	cx,clip.right		; Must be in cx for cant_quick_clip
	mov	di,x
	mov	text_bbox.left,di	; X is bounding box left hand side
	cmp	di,cx
	jge	quick_clip_doesnt_show	; Case 5
	test	bh,HAVE_WIDTH_VECT+NEG_SPACING
	jnz	peg_out_at_max_int
else
	mov	cx,clip.right		; Must be in cx for cant_quick_clip
	test	bh,HAVE_WIDTH_VECT+NEG_SPACING
	jnz	cant_quick_clip
	mov	di,x
	mov	text_bbox.left,di	; X is bounding box left hand side
	cmp	di,cx
	jge	quick_clip_doesnt_show	; Case 5
endif
;
; Compute the maximum extent of the string.  This is:
;
;     #chars * (maximum_width + char_extra) + total_break_extra
;
	mov	ax,lfd.max_width
	add	ax,char_xtra
	imul	count
	jo	peg_out_at_max_int
	add	ax,tot_brk_extra	; Add any extra pixels
	jo	peg_out_at_max_int
	add	ax,di			; AX = maximum right hand side
	jo	peg_out_at_max_int
;
; If the starting X is less than the left side of the clip
; rectangle, then the test will be made for cases 1,2, and 4.
; If the starting X is within the clip rectangle, then the
; test will be made for cases 3 or 4.
;
quick_clip_have_right_x:
	mov	dx,clip.left
	cmp	di,dx
	jge	quick_clip_case_3_or_4
;
quick_clip_case_1_or_2:
	cmp	ax,dx			; Crossing into the left side?
	jl	quick_clip_doesnt_show	; Case 1
	or	bl,CLIPPED_LEFT 	; Show clipped on left side
	mov	text_bbox.left,dx	; Set new lhs for text
;
quick_clip_case_3_or_4:
	cmp	ax,cx			; Overhanging the right side?
	jl	quick_clip_exit 	; No
	or	bl,CLIPPED_RIGHT	; Right clipping needed
;
quick_clip_exit:
	or	bl,TEXT_VISIBLE 	; Some part of the text may show
	mov	text_bbox.right,ax	; Save bounding box right hand side
;
quick_clip_doesnt_show:
	ret
;
; We handle the case where the string extent is unknown by
; setting the left and right hand sides of the strings to
; the most negative and most positive numbers and falling
; through the normal case code.

if	0
cant_quick_clip:
	mov	di,MOST_NEG_INT
	mov	text_bbox.left,di	; Save bounding box left hand side
endif
;
peg_out_at_max_int:
	mov	ax,MOST_POS_INT 	; Make rhs as large as possible
	jmp	quick_clip_have_right_x

quick_clip	endp
;
;
;--------------------------Private-Routine------------------------------;
; comp_extent
;
;   Compute Extents of the String
;
;   The extents of the string are computed and returned to the caller.
;   DrawMode data and font information has already been saved on the
;   frame.
;
; Entry:
;	AX = - character count
;	BH = accel flags
;	BL = excel flags
; Returns:
;	AX = extent of the string
;	DX = height of the string (font height)
; Error Returns:
;	None
; Registers Preserved:
;	BP
; Registers Destroyed:
;	AX,BX,CX,DX,SI,DI,ES,DS,FLAGS
; Calls:
;
; History:
;	Wed 01-Feb-1989 -by-  Doug Cody, Video Seven, Inc
;	Modified for 256 color support
;
;	Thu 09-Apr-1987 13:36:08 -by-  Walt Moore [waltm]
;	Created.
;-----------------------------------------------------------------------;
;
;
;------------------------------Pseudo-Code------------------------------;
; {
; // The computation for fixed-pitch font extents is:
; //
; //	Y extent = height of character
; //	X extent = (width+CharExtra)*#chars + DDA interspersed pixels
; //
; //	since all characters are the same width, including the default
; //	character, and any character extra is applied to all characters.
; //
; //
; // The computation for proportional font extents is:
; //
; //	Y extent = height of character
; //					   count-1
; //					    ---
; //					    \
; //	X extent = DDA interspersed pixels +   >  width(char(n))+CharExtra
; //					    /
; //					    ---
; //					   n = 0
; //
; // If the width vector is present, or there is any negative character
; // justification, then the above doesn't hold true.  The extents must
; // be computed by checking each and every character, and tracking the
; // justification.
; }
;-----------------------------------------------------------------------;
;
	assumes ds,nothing
	assumes es,nothing
;
comp_extent	proc near
	neg	ax			; Make character count positive
	test	bh,HAVE_WIDTH_VECT+NEG_SPACING
	jnz	comp_ext_hard_way	; Could step backwards
	test	bh,FIXED_PITCH
	jz	comp_ext_proportional	; Proportional font
;
	mov	dx,lfd.font_width	; Fixed pitch font
	add	dx,char_xtra		; Always add in character extra
	imul	dx			; AX = string width in pixels
	jo	comp_ext_peg_right	; Too large
;
comp_ext_check_for_just:
	test	bh,HAVE_BRK_EXTRA+DDA_NEEDED
	jnz	comp_ext_check_dda	; Justification is needed
;
; The extent has been computed and is in ax.  Add the left side
; of the string to the exclusive right hand side.
;
comp_ext_have_ext:
	mov	dx,lfd.font_height	; Set height
	ret
;
; The extent of the string overflowed.  Return the most positive
; number for the right hand side.
;
comp_ext_peg_right:
	mov	dx,x			; Set left hand side
	mov	ax,MOST_POS_INT 	; Set right hand side
	ret
;
;
;-----------------------------------------------------------------------;
;
;	Compute the extent for a string which has some form of
;	negative justification and/or a width vector.  The string
;	will be run one character at a time in the same manner as
;	when we build it up on the stack.
;
;	The actual extent code is a subroutine since it can be
;	called by the drawing code at output time, in which case
;	the dda locations must not be updated.
;
;	Currently:
;	    AX	   =  character count
;
;-----------------------------------------------------------------------;
;
comp_ext_hard_way:
	xchg	ax,cx
	call	worst_case_ext		; BX = X extent
	mov	ax,brk_err		; Need break remainder in AX
	jmp	comp_ext_save_err_term
;
;
;-----------------------------------------------------------------------;
;	The font is a proportional font.  Sum up the widths of all
;	the characters.  The summation loop will use the following
;	registers:
;
;	    DS:SI --> string
;	    ES	  --> font
;	    AX	   =  sum
;	    BX	   =  work register
;	    CX	   =  character count
;	    DL	   =  First Character
;	    DH	   =  Last Chararacter
;
;	Currently:
;	    AX	   =  character count
;	    BH	   =  accel flags
;-----------------------------------------------------------------------;
;
comp_ext_proportional:
	xchg	ax,cx			; CX = character count for scanning
	xor	ax,ax			; Initial string width = 0
	test	bh,HAVE_CHAR_EXTRA	; Any CharExtra?
	jz	comp_ext_no_char_extra	; No CharExtra, so skip multiply
	mov	ax,char_xtra
	imul	cx			; AX = initial width
%OUT EGA driver include following line
        jo      comp_ext_peg_right      ; Too large
;
comp_ext_no_char_extra:
	mov	dl,lfd.first_char
	mov	dh,lfd.last_char	; Last char was mapped by get_font
	lds	si,lp_string
	assumes ds,nothing
;
	mov	es,seg_lp_font
	assumes es,FontSeg
;
comp_ext_prop_loop:
	mov	bl,[si] 		; Get next character
	inc	si			; --> next character
	sub	bl,dl			; Make character zero based
	cmp	bl,dh			; Is this character out of range?
	ja	comp_ext_prop_default	; Yes, use default character
;
comp_ext_prop_add_width:
	xor	bh,bh			; Compute pointer to the offset
;
;----------------------------------------------------------------------------;
; for normal code each entry in header table is 4 bytes with the last 2 bytes;
; being the pointer to the bits. For protected mode code each entry is of 6  ;
; bytes with the last 4 bytes being the pointer to the bits.		     ;
;----------------------------------------------------------------------------;
;
rtIF	BigFontFlags
	push	ax
	shl	bx,1
	mov	ax,bx
	shl	bx,1
	add	bx,ax
	pop	ax
	add	ax,wptr fs30CharOffset[bx][PROP_WIDTH]
rtELSE
	shiftl	bx,2
	add	ax,wptr fsCharOffset[bx][PROP_WIDTH]
rtENDIF
;
;----------------------------------------------------------------------------;
;
	jo	comp_ext_peg_right	; Too large
	loop	comp_ext_prop_loop
	mov	bh,accel		; DDA code expects this
	jmp	comp_ext_check_for_just ; Have the extent, maybe exit?
;
comp_ext_prop_default:
	mov	bl,lfd.default_char	; Load default character
	jmp	comp_ext_prop_add_width
;
;-----------------------------------------------------------------------;
;	Justification other than the width vector is involved for
;	the string.  Compute how many extra pixels would be added
;	to the string if it were drawn.  Also update the DDA error
;	term.
;
;	Currently:
;		AX = X extent so far
;		BH = accel flags
;-----------------------------------------------------------------------;
;
comp_ext_check_dda:
	cld				; Yech!
	xchg	ax,bx			; BX = extent so far
	xor	dx,dx			; Clear break char count
	mov	cx,count		; Set count of characters to search
	neg	cx			; Remember that it was negative
	mov	al,lfd.break_char	; Load break character for scanning
	mov	ah,al			; Keep copy for default=break case
	add	al,lfd.first_char	; Break char is relative to first char
	les	di,lp_string
	assumes es,nothing
;
comp_ext_scan_break:
	repne	scasb			; Search for a match
	jne	comp_ext_done_scanning	; Ran out of text
	inc	dx			; Show one more match
	inc	cx			; Must handle the condition where
	loop	comp_ext_scan_break	; the match was on the last character
;
comp_ext_done_scanning:
;
;-----------------------------------------------------------------------;
;	If the default character is the same as the break character,
;	then the string must be scanned looking for all characters
;	which are out of range.
;
;	This is handled seperately from the loop above since all of
;	the raster fonts shipped with Windows have the default char
;	different from the break char, and I don't want to waste the
;	time if I don't have to.
;-----------------------------------------------------------------------;
;
	cmp	ah,lfd.break_char	; Is break and default the same?
	jne	comp_ext_have_breaks	; No, have found all break chars
	mov	di,dx			; Set DI = breaks detected so far
	mov	dl,lfd.first_char
	mov	dh,lfd.last_char	; Last char was mapped by get_font
	mov	cx,count		; Set count of characters to search
	neg	cx
	lds	si,lp_string
	assumes ds,nothing
;
comp_ext_slow_scan:
	lodsb				; Get next character
	sub	al,dl			; Make character zero based
	cmp	al,dh			; Is character out of range?
	ja	comp_ext_invalid_char	; Yes, go show one more break
	loop	comp_ext_slow_scan
	jmp	short comp_ext_done_slow_scan
;
comp_ext_invalid_char:
	inc	di
	loop	comp_ext_slow_scan
;
comp_ext_done_slow_scan:
	mov	dx,di			; Need break char count in DX
;
;-----------------------------------------------------------------------;
;	The number of break characters has been found.	If too many
;	were found, then we could limit them to the maximum specified
;	by BreakCount.	 There is a problem with this:
;
;	    The string to be output could be passed via multiple
;	    calls to STRBLT.  Since there would be no way of keeping
;	    track of the number of BreakChars encountered over these
;	    multiple calls, the output routine could actually recognize
;	    more than BreakCount BreakChars, making the string longer
;	    than the extent returned by this routine.
;
;	Therefore, BreakCount will not be recognized by this code.  It
;	is the caller's responsibility to make sure BreakCount was set
;	correctly.
;
;	Currently:
;		BX = extent so far
;		DX = number of break characters found
;-----------------------------------------------------------------------;
;
comp_ext_have_breaks:
	mov	cx,dx			; CX = # break characters found
	jcxz	comp_ext_done_dda	; No break chars, don't update BreakErr
	mov	ax,brk_extra		; Will always add BreakExtra
	mul	cx			; for each break character
	add	bx,ax			; (TBreakExtra must have been <32k)
	jo	v_comp_ext_peg_right	; Too large
;
;-----------------------------------------------------------------------;
;	The extent for all the characters, CharExtra, and BreakExtra
;	has been computed.  All that needs to be done now is run the DDA.
;
;	Currently:	BX     =  X extent so far
;			CX     =  # break characters in string (or BreakCount)
;			DI     =  BreakCount
;			DS:SI --> DrawMode
;
;
;	The DDA will use the following registers:
;
;		AX = BreakErr
;		BX = X extent so far
;		CX = # break characters in string
;		DX = BreakRem
;		DI = BreakCount
;-----------------------------------------------------------------------;
;
	test	accel,DDA_NEEDED
	jz	comp_ext_done_dda
	mov	dx,brk_rem
	mov	ax,brk_err
	mov	di,brk_count		; Get max # of break characters
;
comp_ext_run_dda:
	sub	ax,dx			; BreakErr -= BreakRem
	jg	comp_ext_dont_distribute;Don't distribute pixel here
	add	ax,di			; BreakErr += BreakCount
	inc	bx			; Distribute one pixel here
	jo	comp_ext_peg_and_save	; Too large
;
comp_ext_dont_distribute:
	loop	comp_ext_run_dda
;
comp_ext_save_err_term:
	lds	si,xlate_draw_mode
	assumes ds,nothing
	mov	[si].BreakErr,ax	; Set new remainder
;
comp_ext_done_dda:
	xchg	ax,bx			; Need X extent in AX
	jmp	comp_ext_have_ext
;
comp_ext_peg_and_save:
	mov	bx,MOST_POS_INT 	; Return maximum value
	jmp	comp_ext_save_err_term	; and update BreakErr
;
v_comp_ext_peg_right:
	jmp	comp_ext_peg_right

comp_extent	endp
;
;
;--------------------------Private-Routine------------------------------;
; worst_case_ext
;
;   Compute Extents for Worst Case String
;
;   Compute the extent for a string which has some form of
;   negative justification and/or a width vector.  The string
;   will be run one character at a time in the same manner as
;   when we build it up on the stack.
;
;   Since it is possible for characters to overlap, the extent
;   of the string may be greater than where the next character
;   would start (think about a "w" and an "i" which started at
;   the same location).
;
;   The actual extent code is a subroutine since it can be
;   called by the drawing code at output time, in which case
;   the dda locations must not be updated.
;
; Entry:
;	CX = character count
; Returns:
;	BX = extent of the string
; Error Returns:
;	None
; Registers Preserved:
;	BP
; Registers Destroyed:
;	AX,BX,CX,DX,SI,DI,ES,DS,FLAGS
; Calls:
;
; History:
;	Thu 09-Apr-1987 13:36:08 -by-  Walt Moore [waltm]
;	Created.
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
	public worst_case_ext
worst_case_ext	proc   near
	lds	si,lp_string
	assumes ds,nothing
;
	mov	es,seg_lp_font
	assumes es,FontSeg
;
	xor	di,di			; DI will be char's starting X
	mov	num_null_pixels,di	; Keep rhs in here
	jmp	short wce_next_char
;
wce_bad_char:
	mov	al,lfd.default_char	; Character was out of range,
	jmp	short wce_good_character
;
wce_have_break_char:
	mov	bl,accel
	and	bl,DDA_NEEDED+HAVE_BRK_EXTRA
	jz	wce_have_tot_extra	; Must have only been char extra
	add	dx,brk_extra		; Extra every break (0 if none)
	test	bl,DDA_NEEDED
	jz	wce_have_tot_extra
	mov	bx,brk_rem		; If the dda is stepping left instead
	or	bx,bx			; of stepping right, then brk_rem
	jl	wce_neg_dda		; will be negative
	sub	brk_err,bx		; Run dda and add in an extra pixel
	jg	wce_have_tot_extra	; if needed.
	mov	bx,brk_count
	add	brk_err,bx
	inc	dx			; Add one pixel for the dda
	jmp	short wce_have_tot_extra
;
wce_neg_dda:
	add	brk_err,bx		; Run dda and subtract an extra pixel
	jg	wce_have_tot_extra	; if needed.
	mov	bx,brk_count
	add	brk_err,bx
	dec	dx			; Subtract one pixel for the dda
	jmp	short wce_have_tot_extra
;
wce_next_char:
	lodsb
	sub	al,lfd.first_char
	cmp	al,lfd.last_char
	ja	wce_bad_char
;
wce_good_character:
	mov	dx,char_xtra		; Base amount of extra pixels needed
	cmp	al,lfd.break_char
	je	wce_have_break_char	; Go compute dda added pixels
;
wce_have_tot_extra:
	xor	ah,ah
	xchg	ax,bx
;
;----------------------------------------------------------------------------;
; for normal code each entry in header table is 4 bytes with the last 2 bytes;
; being the pointer to the bits. For protected mode code each entry is of 6  ;
; bytes with the last 4 bytes being the pointer to the bits.		     ;
;----------------------------------------------------------------------------;
;
rtIF	BigFontFlags
	push	ax
	shl	bx,1
	mov	ax,bx
	shl	bx,1
	add	bx,ax
	pop	ax
	mov	ax,wptr fs30CharOffset[bx][PROP_WIDTH]
rtELSE
	shiftl	bx,2
	mov	ax,wptr fsCharOffset[bx][PROP_WIDTH]
rtENDIF
;
;----------------------------------------------------------------------------;
;
	assumes ds,nothing
	test	accel,HAVE_WIDTH_VECT
	jz	wce_have_width
;
wce_get_users_width:
	lds	bx,lp_dx
	assumes ds,nothing
	add	dx,wptr [bx]		; DX is delta to next char's start
	inc	bx
	inc	bx
	mov	off_lp_dx,bx
	mov	ds,seg_lp_string
	assumes ds,nothing
	sub	dx,ax			; DX = number extra pixels
;
; DX contains any adjustment to the next characters starting
; position.  If this number is negative, then we'll be stepping
; over the previous character.
;
; We don't allow a character to start before the previous character.
; We'll have to enforce this at this point by making sure that any
; negative adjustment is less than or equal to the character width.
;
; Whenever we step backwards, we set a flag for the output routine
; that backwards stepping can occur, except on the very last char.
;
wce_have_width:
	or	dx,dx
	jge	wce_adjustment_ok
	dec	cx
	jz	wce_step_back_on_last
	or	wc_flags,STEPPED_BACK
	add	dx,ax			; Don't allow the backwards step
	sbb	bx,bx			; character
	and	dx,bx
	sub	dx,ax
;
wce_step_back_on_last:
	inc	cx
;
wce_adjustment_ok:
	mov	bx,num_null_pixels	; Want to determine the maximum right
	add	di,ax			; side of the string, which is kept
	jo	wce_peg_out		; in num_null_pixels
	cmp	bx,di
	jg	wce_char_not_new_rhs
	mov	bx,di
;
wce_char_not_new_rhs:
	add	di,dx			; Add in any adjustment to next char's
	jo	wce_peg_out		; starting position.
	cmp	bx,di
	jg	wce_extra_not_new_rhs
	mov	bx,di
;
wce_extra_not_new_rhs:
	mov	num_null_pixels,bx
;
wce_see_if_next:
	dec	cx
	jcxz	@F
	jmp	wce_next_char		; until all characters processed
@@:	ret				; Return X extent in BX
;
wce_peg_out:
	mov	bx,MOST_POS_INT
	ret

worst_case_ext	endp
;
;
;--------------------------Private-Routine------------------------------;
; comp_byte_interval
;
;   A interval will be computed for byte boundaries.
;
;   A first mask and a last mask will be calculated, and possibly
;   combined into the inner loop count. If no first byte exists,
;   the start address will be incremented to adjust for it.
;
; Entry:
;	BX    = right coordinate (exclusive)
;	DX    = left coordinate  (inclusive)
; Returns:
;	'C' clear
;	DI    = offset to first byte to be altered in the scan
;	SI    = inner loop count
;	AL    = first byte mask (possibly 0)
;	AH    = last  byte mask (possibly 0)
; Error Returns:
;	'C' if interval is null
; Registers Preserved:
;	ES,BP
; Registers Destroyed:
;	AX,BX,CX,DX,SI,FLAGS
; Calls:
;	None
; History:
;	Wed 01-Feb-1989 -by-  Doug Cody, Video Seven, Inc
;	Modified for 256 color support
;
;	Sat 11-Apr-1987 20:39:10 -by-  Walt Moore [waltm]
;	Created.
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
	public	comp_byte_interval
comp_byte_interval proc near
	sub	bx,dx			; Compute extent of interval
	jle	return_null_interval	; Null interval, skip it
	dec	bx			; Make interval inclusive
	mov	di,dx			; Don't destroy starting X
;
	cmp	BitsaPixel,1		; mono map?
        je      comp_byte_interval_mono

        inc     bx

	xor	cx,cx
	mov	cl,BitsaPixel
	shr	cx,3
	cmp	cx,1
	je	@F

	; multiple bytes per pixel, need to do some more work...
	mov	ax,di
	mul	cx
	mov	di,ax
	mov	ax,bx
	mul	cx
	mov	bx,ax

@@:
        mov     si,bx
        xor     ax,ax                   ; null clipping masks

	clc				; Carry clear to show there is something
        ret

comp_byte_interval_mono:

        shiftr  di,3                    ; /8 for byte address
;
;
; We now have to determine how many bits will be affected,
; and how they are aligned within the bytes.
;
; (left_x MOD word_size) will give us the starting pixel
; within the left byte/word.  Adding the inclusive extent
; of the interval to left_x MOD word_size) and taking the
; result MOD word_size will give us the last pixel affected
; in the last byte/word.  These pixel indexes (0:7 for bytes,
; 0:15 for words), can be used to create the first and last
; altered bits mask.
;
; To compute the number of bytes/words in the inner loop,
; use the second calculation above
;
; 	(left_x MOD word_size) + inclusive_extent
;
; and divide it by the word size (8/16). This gives you
; the following:
;
;    1)	If the result is 0, then only one destination
; 	byte/word is being altered.  In this case, the
; 	start & ending masks should be ANDed together,
; 	the innerloop count set to zero, and last_mask
; 	set to to all 0's (don't alter any bits).
;
; 		|      x x x x x|		|
; 		|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|
; 		 0 1 2 3 4 5 6 7
;
; 		start MOD 8 = 3,  extent-1 = 4
; 		3+7 DIV 8 = 0, only altering one byte
;
;    2)	If the result is 1, then only two bytes/words
; 	will be altered.  In this case, the start and
; 	ending masks are valid, and all that needs to
; 	be done is set the innerloop count to 0.
;
; 		|  x x x x x x x|x x x x x x x|
; 		|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|
; 		 0 1 2 3 4 5 6 7
;
; 		start MOD 8 = 1,  extent-1 = 14
; 		3+14 DIV 8 = 1.  There is a first and last
; 		byte but no innerloop count
;
;
;
;    3) If the result is > 1, then some number of entire
; 	bytes/words will be altered by the innerloop.  In
; 	this case the number of innerloop bytes/words will
; 	be the result - 1.
;
; 		|	       x|x x x x x x x x|x
; 		|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|
; 		 0 1 2 3 4 5 6 7
;
; 		start MOD 8 = 7,  extent-1 = 9
; 		7+9  DIV 8 = 2.  There is a first and last
; 		byte and an innerloop count of 1 (result - 1)
;
;
; Compute the starting bit position on the left and the ending
; bit position on the right
;
	and	dl,00000111b		; Compute bit index for left side
	xor	dh,dh
	add	bx,dx			; Compute bit index for right side
	mov	si,bx			; (save for inner loop count)
	and	bl,00000111b
	mov	cl,dl			; Compute left side altered bits mask
	mov	ax,0FFFFh
	mov	dx,ax			; Need this here later
	shr	al,cl			; AL = left side altered bytes mask
	mov	cl,bl			; Compute right side altered bits mask
	mov	ah,80h
	sar	ah,cl			; AH = right side altered bits mask
	shiftr	si,3			; Compute inner byte count
	jnz	comp_byte_dont_combine	; loop count + 1 > 0, check it out
;
; Only one byte will be affected.  Combine the first and
; last byte masks, and set the loop count to 0.
;
	and	al,ah			; Will use first byte mask only
	xor	ah,ah			; Want last byte mask to be 0
	inc	si			; Fall through to set 0
;
comp_byte_dont_combine:
	dec	si			; Dec inner loop count (might become 0)
;
; If all pixels in the first byte are altered, combine the
; first byte into the inner loop and clear the first byte
; mask.  Ditto for the last byte
;
	cmp	al,dl			; Set 'C' if not all pixels 1
	sbb	si,dx			; If no 'C', sub -1 (add 1), else sub 0
	cmp	al,dl			; Set 'C' if not all pixels 1
	sbb	al,dl			; If no 'C', sub -1 (add 1), else sub 0
;
	cmp	ah,dl			; Set 'C' if not all pixels 1
	sbb	si,dx			; If no 'C', sub -1 (add 1), else sub 0
	cmp	ah,dl			; Set 'C' if not all pixels 1
	sbb	ah,dl			; If no 'C', sub -1 (add 1), else sub 0
;
	clc				; Carry clear to show there is something
	ret
;
return_null_interval:			; Null interval, skip it
	stc
	ret

comp_byte_interval endp
;
;
;--------------------------Private-Routine------------------------------;
; mono_bitmap_opaque
;
;   Fill the given bitmap with all 1's or all 0's
;
; Entry:
;	AL = first byte mask
;	AH = last byte mask
;	BX = height
;	DX = next scan increment
;	SI = inner loop count
;	ES:DI --> destination
;	DS:DI --> destination
; Returns:
;	None
; Error Returns:
;	None
; Registers Preserved:
;	DX,SI,DS,ES,BP
; Registers Destroyed:
;	AX,BX,CX,DX,DI,FLAGS
; Calls:
;	None
; History:
;	Wed 01-Feb-1989 -by-  Doug Cody, Video Seven, Inc
;	Modified for 256 color support
;
;	Sat 11-Apr-1987 22:43:48 -by-  Walt Moore [waltm]
;	Created.
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
mono_bitmap_opaque   proc near
	mov	cl,bptr colors[BACKGROUND] ; Set 'C' to fill color
	shr	cl,1
	errn$	bitmap_opaque

mono_bitmap_opaque   endp
;
;
;--------------------------Private-Routine------------------------------;
; bitmap_opaque
;
;   Fill the given bitmap with all 1's or all 0's
;
; Entry:
;	AL = first byte mask
;	AH = last byte mask
;	BX = height
;	DX = next scan increment
;	SI = inner loop count
;	ES:DI --> destination
;	DS:DI --> destination
;	'C' set   if to fill with 1's
;	'C' clear if to fill with 0's
; Returns:
;	None
; Error Returns:
;	None
; Registers Preserved:
;	DX,SI,DS,ES,BP
; Registers Destroyed:
;	AX,BX,CX,DX,DI,FLAGS
; Calls:
;	None
; History:
;	Wed 01-Feb-1989 -by-  Doug Cody, Video Seven, Inc
;	Modified for 256 color support
;
;	Sat 11-Apr-1987 22:43:48 -by-  Walt Moore [waltm]
;	Created.
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
bitmap_opaque	proc near
	cld
	jnc	bitmap_opaque_0s	; Filling with 0's
;
; Filling the bitmap with all 1's.  Simply OR in the first
; and/or last byte masks, and STOSW 0FFFF for the inner loop.
;
	or	ax,ax			; If no first or last byte
	jz	bo1_inner_start 	; then only inner loop exists
	mov	cx,di			; If there is a first byte, then
	cmp	al,1			; increment destination pointer
	sbb	cx,-1			; for the inner loop.
	push	cx			; Save inner loop start addr
	mov	cx,bx			; Set CX = height
	or	ah,ah
	jz	bo1_first_only		; No last byte
	or	al,al
	jz	bo1_last_only		; No first byte
;
bo1_first_and_last:
	xchg	bx,si			; Set BX = delta from first to last
	inc	bx
;
bo1_both_loop:
	or	[di],al 		; Do first
	or	[di][bx],ah		; Do last
	add	di,dx			; --> next scan line
	loop	bo1_both_loop
	dec	bx
	xchg	bx,si
	jmp	short bo1_restore_start_addr
;
bo1_last_only:
	add	di,si			; --> last byte of first scan
	xchg	al,ah
;
bo1_first_only:
	or	[di],al 		; Do first
	add	di,dx			; --> next scan line
	loop	bo1_first_only
;
bo1_restore_start_addr:
	pop	di			; --> to first byte for inner loop
;
bo1_inner_start:
	mov	ax,0FFFFh		; Filling with 1's
;
; Inner loop for filling with both 0's and 1's, or whatever is in AX.
;
bo_start_inner_loop:
	or	si,si			; SI = inner loop count
	jz	bo_done 		; No inner loop
	sub	dx,si			; BX = delta to next scan line
;
bo_inner_loop:
	mov	cx,si
	shr	cx,1
	rep	stosw
	rcl	cx,1
	rep	stosb
	add	di,dx
	dec	bx
	jnz	bo_inner_loop
	add	dx,si			; Restore next scan increment
;
bo_done:
	ret
;
; Filling the bitmap with all 0's.  Simply AND in the inverse of the first
; and/or last byte masks, and STOSW 0000 for the inner loop.
;
bitmap_opaque_0s:
	or	ax,ax			; If no first or last byte
	jz	bo_start_inner_loop	; then only inner loop exists
	mov	cx,di			; If there is a first byte, then
	cmp	al,1			; increment destination pointer
	sbb	cx,-1			; for the inner loop.
	push	cx			; Save inner loop start addr
	mov	cx,bx			; Set CX = height
	or	ah,ah
	jz	bo0_first_only		; No last byte
	or	al,al			; 'C' if AL was non-zero
	jz	bo0_last_only		; No first byte
;
bo0_first_and_last:
	xchg	bx,si			; Set BX = delta from first to last
	inc	bx
	not	ax
;
bo0_both_loop:
	and	[di],al 		; Do first
	and	[di][bx],ah		; Do last
	add	di,dx			; --> next scan line
	loop	bo0_both_loop
	dec	bx
	xchg	bx,si
	pop	di			; --> to first byte for inner loop
	xchg	ax,cx			; Set AX = 0
	jmp	short bo_start_inner_loop
;
bo0_last_only:
	add	di,si			; --> last byte of first scan
	xchg	al,ah
;
bo0_first_only:
	not	al
;
bo0_one_only_loop:
	and	[di],al
	add	di,dx			; --> next scan line
	loop	bo0_one_only_loop
;
bo0_restore_start_addr:
	pop	di			; --> to first byte for inner loop
	xchg	ax,cx			; Set AX = 0
	jmp	bo_start_inner_loop

bitmap_opaque	endp
;
;
;------------------------------Private-Routine------------------------------;
; color_bitmap_opaque
;
;   Fill the given bitmap with the background color. This works for
;   both displays and internal bitmaps.
;
; Entry:
;	AL = first byte mask
;	AH = last byte mask
;	BX = height
;	SI = inner loop count
;	ES:DI --> destination
;	DS:DI --> destination
;
; Returns:
;	None
; Error Returns:
;	None
; Registers Preserved:
;	SI,DS,ES,BP
; Registers Destroyed:
;	AX,BX,CX,DX,DI,FLAGS
; Calls:
;	None
; History:
;	Wed 01-Feb-1989 -by-  Doug Cody, Video Seven, Inc
;	Modified for 256 color support
;
;	Sat 11-Apr-1987 22:43:48 -by-  Walt Moore [waltm]
;	Created.
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
	public	color_bitmap_opaque
color_bitmap_opaque     proc near
	push    si                      ; do not disturb...
;
	mov	cx,si			; load length in bytes
	jcxz	cobiop_done		; exit if nop
	mov	dl,CurVidSel		; make sure bank is correct
	SET_BANK
	mov	dx,si			; dx holds full length
        sub     dx,next_scan            ; dx holds -(remaining length)
        neg     dx
	mov	ax,cx			; keep the length in AX
;
cobiop_loop:
	; copy the physical background colour directly from the stack to the BM
	mov	cx,pxbytes
	lea	si,[colors.BACKGROUND]
cobiop_pixel_loop:
	movs	byte ptr es:[di],ss:[si]; one byte at a time
	test	di,di
	UpdBank	jnz
	dec	ax
	loop	cobiop_pixel_loop
	jnz	cobiop_loop		; if AX is not zero, loop around

        add     di,dx                   ; advance to next scan line
	UpdBank
        pop     ax			; reload length count
	push	ax			; and store again for later
	dec	bx			; check for end of fill
	jnz	cobiop_loop		; loop if not done...
;
cobiop_done:
	pop     si
	ret

color_bitmap_opaque	endp
;
;
;--------------------------Private-Routine------------------------------;
; output_o_rect
;
;   Fill the opaque rectangle with the background color.
;
; Entry:
;	BL = excel flags
; Returns:
;	None
; Error Returns:
;	None
; Registers Preserved:
;	BP
; Registers Destroyed:
;	AX,BX,CX,DX,SI,DI,DS,ES,FLAGS
; Calls:
;	???
; History:
;	Wed 01-Feb-1989 -by-  Doug Cody, Video Seven, Inc
;	Modified for 256 color support
;
;	Tue 14-Apr-1987 12:22:31 -by-  Walt Moore [waltm]
;	Created.
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
	public	output_o_rect
output_o_rect	proc	near
	mov	ax,seg_lp_surface	; DS and ES will always point to the
	mov	ds,ax			; segment of the destination
	assumes ds,nothing		; surface while in this routine
	mov	es,ax
	assumes es,nothing
;
	shiftr	bl,2
	jnc	oor_exclusive_rects	; No text, just output opaque rect
	errnz	TEXT_VISIBLE-00000010b
;
	test	accel,IS_OPAQUE 	; If in transparent mode, must always
	jz	oor_exclusive_rects	; opaque the rectangle
;
	shr	bl,1
	jc	oor_check_x_bounds	; Skip Y range check
	errnz	BOUNDED_IN_Y-00000100b
;
; We have no idea if any of the text bounding box intersects
; with the opaque rectangle.  If the intersection is empty,
; then we can output the opaque rectangle using the same code
; for when there isn't any text.
;
oor_check_y_bounds:
	mov	ax,text_bbox.top
	cmp	ax,o_rect.bottom
	jge	oor_exclusive_rects
	mov	ax,text_bbox.bottom
	cmp	ax,o_rect.top
	jle	oor_exclusive_rects
;
; The rectangles overlap in Y.  Check to see if they overlap in X.
;
oor_check_x_bounds:
	mov	ax,text_bbox.left
	cmp	ax,o_rect.right
	jge	oor_exclusive_rects
	mov	ax,text_bbox.right
	cmp	ax,o_rect.left
	jnle	oor_inclusive_rects	; Rectangles intersect somehow
;
; The rectangles are exclusive.  Just fill the opaque rectangle and exit.
;
oor_exclusive_rects:
	mov	bx,o_rect.right
	mov	dx,o_rect.left
	call	comp_byte_interval
	xchg	ax,cx			; Save first/last mask
	mov	ax,o_rect.top		; Compute height of box and leave
	mov	bx,o_rect.bottom	; it in BX for the opaquing
	sub	bx,ax			; subroutines
;
	mul	next_scan		; Add in Y component
	add	di,ax
	adc	dl,dh
	add	di,off_lp_surface	; Add any original offset into surface
	adc	dl,dh
	mov	CurVidSel,dl
;
	xchg	ax,cx			; First/last masks need to be in AX
	mov	dx,next_scan		; Need increment to next scan line
	jmp	opaque_routine
;
;
;-----------------------------------------------------------------------;
;
;	The rectangles overlap in some unknown manner.	Compute
;	all the areas which need to be opaqued, and opaque them
;	(easier said than done).
;
;
;	First the area completely above and below the text bounding
;	box will be opaqued.  The scanline information will be the
;	same for both areas (same first/last masks and inner loop
;	counts).  Remember that any of the areas could be null.
;
;
;	heights
;
;		------------------------------------  o_rect.top
;	       |				    |
;	 top   |	  opaque rectangle	    |
;	       |				    |
;	       |     --------------------------     | text_bbox.top
;	       |    |			       |    |
;	middle |    |	 text bounding box     |    |
;	       |    |			       |    |
;	       |     --------------------------     | text_bbox.bottom
;	bottom |				    |
;	       |				    |
;		------------------------------------  o_rect.bottom
;
;
;	For the top rectangle:
;
;		starting Y is o_rect.top
;		height is MAX(text_bbox.top-o_rect.top,0)
;
;	For the bottom rectangle:
;
;		starting Y is text_bbox.top
;		height is MAX(o_rect.bottom-text_bbox.bottom,0)
;
;	For the middle rectangle:
;
;		starting Y is o_rect.top + height of top
;		height is MAX(text_bbox.bottom-starting Y,0)
;
;-----------------------------------------------------------------------;
;
oor_inclusive_rects:
	mov	CurVidSel,0
	mov	dx,text_bbox.top	; Compute opaque rect area above the
	mov	ax,o_rect.top		; text bounding box
	sub	dx,ax
	sbb	cx,cx
	not	cx
	and	cx,dx			; CX = height of top, or 0
	jz	oor_comp_bottom
	mul	next_scan
	xchg	bx,ax			; Set BX = offset to start of top scan
	mov	CurVidSel,dl
;
oor_comp_bottom:
	mov	ax,text_bbox.bottom	; Compute opaque rect area below the
	mov	dx,o_rect.bottom	; text bounding box
	sub	dx,ax
	sbb	si,si
	not	si
	and	si,dx			; SI = height of bottom, or 0
	jz	oor_comp_middle_y
	mul	next_scan		; DX:AX = offset to start of top scan
;
oor_comp_middle_y:
	mov	di,o_rect.top		; Add o_rect.top and height of top
	add	di,cx			; area to get middle Y
;
oor_see_if_top_or_bottom:
	push	dx			; Save bottom bank if applicable
	mov	dx,si			; If both heights are 0, then
	or	dx,cx			; no top and no bottom
	pop	dx			; Get back bottom bank
	jz	oor_see_about_middle
;
; There is at least a top or a bottom.  Compute the scan interval
; and fill the areas.
;
	push	di			; Save middle area Y
	push	dx			; Save bottom area Y bank
	push	ax			; Save bottom area Y offset
	push	si			; Save bottom area height
	push	bx			; Save top    area Y offset
	push	cx			; Save top    area height
	mov	bx,o_rect.right
	mov	dx,o_rect.left
	call	comp_byte_interval
	mov	dx,next_scan		; Set next scan increment incase bitmap
	add	di,off_lp_surface	; Add any initial offset to bits/device
	adc	CurVidSel,0
	pop	bx			; Get top area height
	pop	cx			; Get top area Y offset
	or	bx,bx
	jz	oor_see_about_bottom	; There is no top area
	push	di			; Save X component of start address
	push	ax			; Save first/last mask
	add	di,cx			; --> first byte
	adc	CurVidSel,0
	call	opaque_routine
	pop	ax			; Restore first/last mask
	pop	di			; Restore X component of start address
;
oor_see_about_bottom:
	pop	bx			; Get bottom area height
	pop	cx			; Get bottom area Y offset
	pop	dx			; Get bottom area Y bank
	or	bx,bx
	jz	oor_no_bottom_area	; There is no bottom area
	add	di,cx			; --> first byte
	adc	dl,dh			; DH should be zero
	mov	CurVidSel,dl
	call	opaque_routine
;
oor_no_bottom_area:
	pop	di			; Restore middle Y coordinate
;
oor_see_about_middle:
	mov	ax,o_rect.bottom	; Bottom of middle bytes is
	mov	bx,text_bbox.bottom	; minimum of these two
	min_ax	bx
	sub	ax,di			; Compute height of middle area
	jle	oor_a_return		; This should never occur, but....
	mov	opaque_height,ax
	mov	ax,next_scan		; Compute Y offset of middle start
	mul	di
	add	ax,off_lp_surface
	adc	dl,dh
	mov	temp_off_lp_bits,ax
	mov	CurVidSel,dl
;
	mov	dx,text_bbox.right	; Compute rhs interval
	mov	bx,o_rect.right
	call	comp_byte_interval
	mov	bx,text_bbox.left	; For lhs interval computation
	mov	dx,o_rect.left
	jc	oor_check_lhs_only	; No rhs
	push	si			; Save inner loop count
	push	di			; Save X offset into scan
	push	ax			; Save first/last mask
	push	wptr CurVidSel		; Save current bank
	call	comp_byte_interval
	jnc	oor_output_both_sides	; There was a left and a right
;
; There was only a rhs.  Restore the saved interval parameters
; and output the rectangle.
;
oor_process_rhs:
	pop	dx			; Restore bank
	mov	CurVidSel,dl		; (it's only one byte!)
	pop	ax			; Restore first/last mask
	pop	di			; Restore X offset
	pop	si			; Restore inner loop count
;
oor_output_one_rect:
	add	di,temp_off_lp_bits	; --> first byte
	adc	CurVidSel,0
	mov	bx,opaque_height	; Set height
	mov	dx,next_scan		; Set index to next scanline
	jmp	opaque_routine		; Invoke opaquing routine and exit
;
; There was only a lhs.  Compute the interval parameters
; and see if the text string was bounded in Y.  If it was,
; then any portion of the last byte of the lhs interval
; will have been handled by the string output code.
;
oor_check_lhs_only:
	call	comp_byte_interval	; Compute lhs interval
	jc	oor_a_return		; No interval exists, exit
	jmp	oor_output_one_rect
;
oor_a_return:
	ret
;
; The parameters for the lhs and rhs have been computed.
; If the lhs stops in the same byte that the rhs starts,
; then we'll want to combine the lhs last byte mask with
; the rhs first byte mask.
;
oor_output_both_sides:
	mov	cx,text_bbox.left	; Compute the byte address of the
	and	cl,11111000b		; start and end of the text string
	mov	dx,text_bbox.right
	and	dl,11111000b
	cmp	dx,cx
	jne	oor_output_both_anyway	; Ends/starts in different bytes
;
; We have to combine the last byte mask of the lhs with the
; first byte mask of the rhs.  If one of the intervals consists
; only of the mask, we want to make it disappear.  Both the last
; byte mask for the lhs and the first byte mask for the rhs must
; exist.
;
oor_overlapping_middle:
	pop	dx			; Restore bank
	mov	CurVidSel,dl		; (it's only one byte!)
	pop	bx			; Restore rhs first/last mask
	pop	dx			; Restore rhs X offset
	pop	cx			; Restore rhs inner loop count
;
	or	si,si			; If an inner loop for lhs, combine
	jnz	oor_combine_with_lhs	; rhs first mask with lhs last mask
	or	ah,ah			; If a last byte mask for lhs, combine
	jnz	oor_combine_with_lhs	; rhs first byte mask with it
;
; There is only a first byte on the lhs. Combine it with the
; rhs byte.  This will eliminate the entire lhs. We don't
; have to worry about there not being a rhs first byte mask
; (and therefore decrementing the destination pointer) since
; there must be one for the bytes to overlap.
;
	or	ax,bx			; Combine lhs mask with rhs masks
	mov	si,cx			; Set inner loop count
	mov	di,dx
	jmp	oor_output_one_rect
;
oor_combine_with_lhs:
	or	ah,bl			; Combine the masks
	xor	bl,bl			; Clear old mask
	inc	dx			; Increment rhs start offset
	push	cx			; Save inner loop count
	push	dx			; Save X offset into scan
	push	bx			; Save first/last mask
	push	wptr CurVidSel		; Save current bank
;
oor_output_both_anyway:
	call	oor_output_one_rect	; Do whatever for lhs
	jmp	oor_process_rhs 	; Do whatever for rhs
;
output_o_rect	endp
;
;
;--------------------------Private-Routine------------------------------;
; get_device_data
;
;   All device specific local variables are intialized.
;
;   This function must be called after both get_clip and quick_clip
;   (when the character count is positive) have been called.  This
;   requirement is because of the manner in which huge bitmaps are
;   handled), and for cursor exclusion.
;
; Entry:
;	None
; Returns:
;	None
; Error Returns:
;	to exit_strblt_error if device isn't enabled
; Registers Preserved:
;	BP
; Registers Destroyed:
;	AX,BX,CX,DX,SI,DI,DS,ES,FLAGS
; Calls:
;	???
; History:
;	Tue 18-Aug-1987 16:30:43 -by-  Walt Moore [waltm]
;	Added test of the disabled flag.
;
;	Tue 14-Apr-1987 12:22:31 -by-  Walt Moore [waltm]
;	Created.
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
v_gdd_dev_is_bitmap:
	jmp	gdd_dev_is_bitmap
;
gdd_device_isnt_enabled:
	pop	ax
	jmp	exit_strblt_error
;
get_device_data proc near
	lds	si,lp_device
	mov	cx,[si].bmType
	jcxz	v_gdd_dev_is_bitmap
	test	local_enabled_flag,0FFh
	jz	gdd_device_isnt_enabled
	or	excel,IS_DEVICE
;
;-----------------------------------------------------------------------;
;	This is the display.  Exclude the cursor from the union of
;	the opaque rectangle and the estimated text bounding box.
;
;	Because of the approximation technique used for the text
;	bounding box, text X coordinates must be clipped to the
;	EGA's physical dimensions.
;
;	Exclusion code expects:
;		(cx) = left
;		(dx) = top
;		(si) = right  (inclusive)
;		(di) = bottom (inclusive)
;-----------------------------------------------------------------------;
;
ifdef	EXCLUSION
	mov	bl,excel
	test	bl,TEXT_VISIBLE 	    ; If no visible text, then opaque
	jz	gdd_exclude_is_opaque	    ; rect is the exclusion area
	test	bl,OPAQUE_RECT		    ; If no opaque rectangle
        jz      gdd_exclude_text_or_both    ; clip to text bbox
	test	eto_options,ETO_OPAQUE_CLIP ; If text isn't clipped to opaque
        jz      gdd_exclude_text_or_both    ; rect, clip to the union
;
gdd_exclude_is_opaque:
	mov	cx,o_rect.left
	mov	dx,o_rect.top
	mov	si,o_rect.right
	mov	di,o_rect.bottom
	jmp	gdd_exclude_have_rect
;
gdd_exclude_text_or_both:
        mov     ax,text_bbox.left       ; Clip text left to screen left
        min_ax  0                       ; AX = min(AX,0)
        mov     cx,ax
	mov	ax,text_bbox.right	; Clip text right to screen right
	min_ax	local_VScreen_Width
        mov     si,ax                   ; SI is now rhs
	mov	dx,text_bbox.top
	mov	di,text_bbox.bottom
	test	bl,OPAQUE_RECT
	jz	gdd_exclude_have_rect
;
; We have to exclude the union of the opaque rectangle and
; the text bounding box.
;
	mov	bx,dx			; BX = text_bbox.top
	mov	ax,o_rect.top
	min_ax	bx
        mov     bx,ax
	mov	ax,o_rect.left
	min_ax	cx
        mov     cx,ax
	mov	ax,o_rect.right
	max_ax	si
        mov     si,ax
	mov	ax,o_rect.bottom
	max_ax	di
        mov     di,ax
	mov	dx,bx
;
gdd_exclude_have_rect:
	dec	si			; Want rhs and bottom to be inclusive
        dec     di
	call	exclude
endif
;
; The exclusion has been taken care of.  Now initialize
; the frame variables for the display.
;
	mov	ax,MemoryWidth 		; Compute adjustment from bottom
	mov	next_scan,ax		; of character to top of
	mul	clipped_font_height	; AX holds next row offset
	mov	bx,ax			; bx holds the text size (for below)
	errnz	SIZE_PATTERN-8
	sub	al,BitsaPixel		; make it a zero based count.
	sbb	ah,dh			; (dh = 0)
;
        mov     cell_adjust,ax          ; saved for the actual text output
	mov	opaque_routine,CodeOFFSET color_bitmap_opaque
        lds     si,lp_device            ; get the pointer again for bitmap code

        mov     dx,[si].bmBits.sel
        mov     ax,[si].bmBits.off
        mov     seg_lp_surface,dx
        mov     off_lp_surface,ax

        jmp     gdd_huge_bitmap		; go to common code
;
;-----------------------------------------------------------------------;
; This is a memory bitmap.  Initialize the frame variables for either	;
; a color or a monochrome bitmap.					;
;-----------------------------------------------------------------------;
;
	assumes ds,nothing
	assumes es,nothing
;
gdd_dev_is_bitmap:
	cmp	cx,[si].bmSegmentIndex	; If bmSegmentIndex is non-zero,
	jne	gdd_huge_bitmap 	; then this is a huge bitmap
;
gdd_small_bitmap:
;
; small bitmaps will now have interleaved scan line format
;
	mov	ax,[si].bmWidthBytes	; Compute index to next plane and
;;;     mov     next_plane,ax           ; to the next scan
	mov	bx,[ColourFormat_CS]
	xor	bh,bh
	mul	bx
	mov	next_scan,ax
;
	mov	ax,wptr [si].bmBits[0]	; Save pointer to the bits
	mov	off_lp_surface,ax
	mov	ax,wptr [si].bmBits[2]
	mov	seg_lp_surface,ax
;
gdd_finish_bitmap:
	mov	ax,next_scan		; Compute adjustment from bottom
	mul	clipped_font_height	; of character to top of
;
	errnz	SIZE_PATTERN-8
	sub	al,BitsaPixel		; add in distance to next pixel
	sbb	ah,dh			; dh must be 0
	mov	cell_adjust,ax
	mov	ax,wptr [si].bmPlanes
	errnz	bmBitsPixel-bmPlanes-1
	cmp	ax,[ColourFormat_CS]
	je	gdd_is_color_bitmap
;
	mov	num_planes,1		; Use constant incase bad color format
	mov	opaque_routine,CodeOFFSET mono_bitmap_opaque
	ret
;
; This is a small color bitmap.
; 
gdd_is_color_bitmap:
	mov	num_planes,1
	errnz	bmBitsPixel-bmPlanes-1
	mov	opaque_routine,CodeOFFSET color_bitmap_opaque
;
gdd_exit:
        ret
;
; This is a huge bitmap. If the text or opaque rectangle
; spans a segment boundary, then we'll recurse (curse?) to
; handle the string, setting a clipping rectangle which is
; appropriate for each 64K segment of the string.
;
; Both the opaque rectangle and the text bounding box have
; already been clipped in Y to the actual clipping rectangle,
; so we are guaranteed not to overflow the real clipping
; rectangle's Y range.
;
gdd_huge_bitmap:
	mov	al,excel		; If we have both, then the union
	not	al			; of the two will be needed
	and	al,OPAQUE_RECT+TEXT_VISIBLE
	mov	ax,text_bbox.top
	mov	bx,text_bbox.bottom
	mov	cx,o_rect.top
	mov	di,o_rect.bottom
	jnz	gdd_dont_do_union	; Only have one rectangle
	min_ax	cx
	xchg	ax,bx
	max_ax	di
	xchg	ax,bx			; AX = top, BX = bottom
	jmp	short gdd_have_y_ext
;
gdd_dont_do_union:
	test	excel,TEXT_VISIBLE	; Y top and bottom for text only
	jnz	gdd_have_y_ext		; is already set in AX, BX
	xchg	ax,cx			; Need Y top and bottom for the
	xchg	bx,di			; opaque rectangle
;
gdd_have_y_ext:
	mov	clip.bottom,bx		; Save bottom and top incase
	mov	clip.top,ax		; we cross a segment
	mov	di,[si].bmScanSegment	; #  of scanlines in each segment
	xor	dx,dx			; Compute segment and starting
	div	di			; scan of top line
	xchg	ax,bx
	mov	cx,dx
	xor	dx,dx			; Compute segment and scan of the
	dec	ax			; last line (want the calc to be
	div	di			; inclusive of last line).
;
;
; We now have the following information:
;
;     BX = segment number of the starting scan line
;     CX = starting scan line within the segment
;     AX = segment number of the last scan line
;     DX = ending scan line within the segment
;     DI = # scans per segment
;
; If everything is contained within one segment, then we blow
; off the recursion and just output the stuff.  If seperate
; segments are involved, we dummy up a clip rectangle and
; call ourselves again.  If only one segment is involved,
; we just alter the Y values a little to adjust for the actual
; segment, and pretend we're a small bitmap.
;
	cmp	ax,bx	; ax - bx
	jg	gdd_different_segments
	jl	gdd_exit		; Should never happen
;
        test    excel,IS_DEVICE		; if a device huge bitmap, then exit
	jnz	gdd_exit
;
	or	ax,ax			; If in first segment, don't need
	jz	gdd_have_segment	; to adjust Y values
	mul	di			; Compute the number of scans to
	sub	text_bbox.top,ax	; subtract off of the original
	sub	text_bbox.bottom,ax	; Y's to bring them within the
	sub	o_rect.top,ax		; allowable range for this segment
	sub	o_rect.bottom,ax
	mov	ax,[si].bmSegmentIndex	; Compute the adjustment to the
	mul	bx			; selector
;
gdd_have_segment:
	add	ax,wptr [si].bmBits[2]	; Save pointer to the bits
	mov	seg_lp_surface,ax
	mov	ax,wptr [si].bmBits[0]
	mov	off_lp_surface,ax
	mov	ax,[si].bmWidthBytes	; Compute index to next plane and
	mov	bx,[ColourFormat_CS]
	cmp	bx,wptr [si].bmPlanes
	je	gdd_have_our_color
	mov	bl,1			; Force it to be mono
;
gdd_have_our_color:
	xor	bh,bh
	mul	bx
	mov	next_scan,ax
	jmp	gdd_finish_bitmap
;
gdd_different_segments:
	push	clip.bottom		; Save until we need it
;
; We now have the following information:
;
; BX = segment number of the starting scan line
; CX = starting scan line within the segment
; AX = segment number of the last scan line
; DX = ending scan line within the segment
; DI = # scans per segment
;
	sub	ax,bx			; Number of times we'll make the call
	xchg	ax,si			; Keep count in SI
	xchg	ax,bx			; Get segment index of first scan
	inc	ax
	mul	di			; Compute end of first segment
;
gdd_do_next_whole_segment:
	mov	clip.bottom,ax
;
gdd_do_last_segment:
	lea	ax,clip

	farPtr	lp_new_clip_rect,ss,ax

	arg	lp_device		; Destination device
	arg	x			; Left origin of string
	arg	y			; Top  origin of string
	arg	lp_new_clip_rect	; Clipping rectangle
	arg	lp_string		; The string itself
	arg	count			; Number of characters in the string
	arg	lp_font 		; Font to use
	arg	xlate_draw_mode 	; Drawmode structure to use
	arg	lp_xform		; Current text transform
	arg	lp_dx			; Widths for the characters
	arg	lp_opaque_rect		; Opaquing rectangle
	arg	eto_options		; ExtTextOut options
	cCall	ExtTextOut

; If all went well, the first portion of the text has been
; displayed.  Let's just keep doing it until we've done all
; remaining segments.
;
	mov	ax,clip.bottom		; Set start of next segment
	mov	clip.top,ax
	add	ax,di
	dec	si
	jg	gdd_do_next_whole_segment
;
; A little slime here folks.  The first time we'll pop the real
; bottom scan line.  The second time, we'll pop the return address.
;
	pop	clip.bottom		; Set last scan
	jz	gdd_do_last_segment
;;;;;;;;jmp     exit_strblt_null
        jmp     strblt_clean_up         ; so unexclude will be called.
get_device_data endp


sEnd	Code
	end
