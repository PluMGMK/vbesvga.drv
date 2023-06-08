;
;	FILE:	bs216.asm
;	DATE:	10/22/91
;	AUTHOR: Jim Keller
;
;	This module does non-justified text output to the display on
;	Video7 board (with special case code for 216 mono to color
;	expansion.)
.286

	include cmacros.inc
	include	cursor.inc
	include	gdidefs.inc
	include	display.inc
	include ega.inc
	include macros.mac
	include strblt.inc
        include fontseg.inc
	include vgareg.inc
	include rt.mac

	extrn	build_ret_addr:NEAR
	extrn	build_ret_oem:NEAR
	externW ScreenSelector

sBegin	Data
ALIGN  2
jak_text_buffer DB	2080H DUP(?)
BUFFER_OFFSET_START	EQU	80H
sEnd    Data



sBegin	Code
	assumes cs,Code
	assumes ss,StrStuff

	externB ??BigFontFlags

	define_frame jak_build_string	    ; Define strblt's frame
cBegin	<nogen>
cEnd    <nogen>

;---------------------------Public-Routine------------------------------;
;
; non_justified_text
;
;   This is the simple case for proportional text.  No justification,
;   no width vector.  Just run the string.  If we run out of stack
;   space, then that portion of the string which fits will be displayed,
;   and we'll restart again after that.
;
;   spcl - simple, proportional, clip lhs
;   sfcl - simple, fixed pitch,  clip lhs
;   sc	 - simple, clip rhs
;
; Entry:
;	DS:SI --> current character in the string
;	ES:    =  font segment
;	AL     =  excel flags
;	AH     =  accel flags
;	CX     =  number of characters in the string
;	DI     =  current X position (and therefore starting x)
;	stack frame as per strblt
; Returns:
;	DS:SI --> current character in the string
;	ES:    =  font segment
;	CX     =  number of characters left in string
;	DI     =  string rhs
;	AX     =  next character's X
; Error Returns:
;	none
; Registers Preserved:
;	BP
; Registers Destroyed:
;	AX,BX,CX,DX,SI,DI,DS,ES,FLAGS
; Calls:
;	None
; History:
;	Tue 05-May-1987 wrote it
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,FontSeg
	assumes ss,StrStuff

PUBLIC	jak_non_justified_text
jak_non_justified_text proc near
	mov	jak_first_char,1
        test    al,CLIPPED_LEFT
	jnz	@F
	jmp	sc_no_left_clipping	; No clipping needed on lhs
@@:
	mov	dx,clip.left		; Characters become visible here
	test	ah,FIXED_PITCH
	jz	spcl_next_char		; Proportional font

;-----------------------------------------------------------------------;
;	Fixed pitch, no justification, left hand clipping
;-----------------------------------------------------------------------;

	mov	bx,lfd.font_width	;Fixed pitch font.

sfcl_next_char:
	add	di,bx			;Does this character become visible?
	cmp	dx,di			;DX is clip.left
	jl	sfcl_current_is_visible ;This char is visible
	inc	si
	loop	sfcl_next_char		;See if next character

sfcl_no_chars_visible:
	jmp	build_ret_addr		;Return to caller

sfcl_current_is_visible:
	sub	di,bx			;Restore staring address of character
					;  and just fall into the proportional
					;  code which will handle everything

;-----------------------------------------------------------------------;
;	Proportional, no justification, left hand clipping
;-----------------------------------------------------------------------;

spcl_next_char:
	lodsb
	sub	al,lfd.first_char
	cmp	al,lfd.last_char
	jbe	spcl_good_character
	mov	al,lfd.default_char	;Character was out of range

spcl_good_character:
	xor	ah,ah
	xchg	ax,bx

;----------------------------------------------------------------------------;
; for normal code the header has 2 byte pointer and entry size is 4 per char ;
; for protected mode code, pointers are 4 byte and size of entry is 6 bytes  ;
;----------------------------------------------------------------------------;

rtIF	BigFontFlags
; multiply by 6
	shl	bx,1
	mov	ax,bx
	shl	bx,1
	add	bx,ax
	mov	ax,wptr fs30CharOffset[bx]	; .PROP_WIDTH
rtELSE
; multiply by 4
	shiftl	bx,2
	mov	ax,wptr fsCharOffset[bx]	; .PROP_WIDTH
rtENDIF

;----------------------------------------------------------------------------;

	add	di,ax			;0 width chars won't change x position
	cmp	dx,di			;DX is clip.left
	jl	spcl_current_is_visible ;This char is visible

spcl_see_if_next:
	loop	spcl_next_char		;See if next character
	jmp	build_ret_addr		;Return to caller

spcl_current_is_visible:
	sub	di,ax			;Restore starting x of character

rtIF	BigFontFlags
	.386
	push	ax
	movzx	eax,amt_clipped_on_top	;Adjust pointer for any clipping
	mov	ebx,dword ptr fs30CharOffset[bx][PROP_OFFSET] ;32 bit offset
	add	ebx,eax
	pop	ax
        .286
rtELSE
	mov	bx,wptr fsCharOffset[bx][PROP_OFFSET+0] ;offset
	add	bx,amt_clipped_on_top	;Adjust pointer for any clipping
rtENDIF

;-----------------------------------------------------------------------;
;	Instead of incrementing the current position by 8 and
;	having to recover the real current position, we just
;	slide the clip region left.  It has the same effect.
;-----------------------------------------------------------------------;

	sub	dx,di			;Compute bits until we're visible
	je	spcl_save_first 	;Starts on clip edge
	sub	dx,8			;Is current byte visible?
	jl	spcl_have_vis_start	;  Yes


spcl_step_clipped_char:
	sub	ax,8			;Shorten the width of the character
	add	di,8			;Move current position right

rtIF	BigFontFlags
	.386
	push	ax
	movzx	eax,wptr lfd.font_height
	add	ebx,eax
	pop	ax
	.286
rtELSE
	add	bx,lfd.font_height	;Move to next column of character
rtENDIF

	sub	dx,8			;Is current byte visible?
	jge	spcl_step_clipped_char	;  No

;-----------------------------------------------------------------------;
;	If the lhs of the clip region and the starting X of the
;	character are in different bytes, then the FIRST_IN_PREV
;	flag must be set.  Only a clipped character can set this
;	flag.
;-----------------------------------------------------------------------;

spcl_have_vis_start:
	add	dx,8			; adjust back to last calculation
	mov	ColorPhase,dl		; save the left clip character phase

	mov	dx,clip.left
	xor	dx,di
	and	dx,not 7
	jz	spcl_save_first 	;In same byte
	or	excel,FIRST_IN_PREV

;-----------------------------------------------------------------------;
;	We have the start of the first character which is visible
;	Determine which loop (clipped/non-clipped) will process it.
;	We let the routine we're about to call push the character
;	since it will handle both right clipping (if needed) and
;	fat characters.
;-----------------------------------------------------------------------;

spcl_save_first:
	mov	jak_start_text,di
	jmp	short scc_clip_enters_here

sc_no_left_clipping:
	mov	jak_start_text,di
        jmp     short scc_next_char

;-----------------------------------------------------------------------;
;	scc - simple case, rhs clipping.
;	This loop is used when it is possible for the character
;	to be clipped on the rhs.  lhs clipping has already
;	been performed.  There is no justification.
;
;	Currently:
;		DS:SI --> current character in the string
;		ES:    =  font segment
;		DI     =  current X position
;		CX     =  number of bytes left in the string
;-----------------------------------------------------------------------;

scc_bad_char:
	mov	al,lfd.default_char	;Character was out of range,
	jmp	short scc_good_char

scc_next_char:
	lodsb
	sub	al,lfd.first_char
	cmp	al,lfd.last_char
	ja	scc_bad_char

scc_good_char:
	xor	ah,ah
	xchg	ax,bx

;----------------------------------------------------------------------------;
; for normal code the header has 2 byte pointer and entry size is 4 per char ;
; for protected mode code, pointers are 4 byte and size of entry is 6 bytes  ;
;----------------------------------------------------------------------------;

rtIF	BigFontFlags
	.386
; multiply by 6
        shl     bx,1
	mov	ax,bx
	shl	bx,1
	add	bx,ax
	mov	ax,wptr fs30CharOffset[bx][PROP_WIDTH]
	mov	ebx,dword ptr fs30CharOffset[bx][PROP_OFFSET+0] ; 32 bit offset
        .286
rtELSE
; multiply by 4
	shiftl	bx,2
	mov	ax,wptr fsCharOffset[bx][PROP_WIDTH]
	mov	bx,wptr fsCharOffset[bx][PROP_OFFSET+0] ; 16 bit offset
rtENDIF

;----------------------------------------------------------------------------;

	or	ax,ax			;If width is 0, ignore character
	jz	scc_see_if_next

rtIF	BigFontFlags
	.386
	push	ax
	movzx	eax,amt_clipped_on_top
	add	ebx,eax			;Adjust pointer for any clipping
	pop	ax
        .286
rtELSE
	add	bx,amt_clipped_on_top	;Adjust pointer for any clipping
rtENDIF



;JAK
;	at this point, assume
;       jak_ptr_start_scan   points to the start of the scanline

scc_clip_enters_here:
        mov     dx,di                   ;Compute phase
        and     dl,7
        add     di,ax                   ;DI = next char's X position
        cmp     di,clip.right
        jge     scc_char_is_clipped     ;Clipped (or first pixel of next is)

scc_been_clipped:
	sub	di,ax			;JAK
rtIF	BigFontFlags
	call	jak_386_scc_build
rtELSE
	call	jak_286_scc_build
rtENDIF
	mov	jak_first_char,0
        add     di,ax

scc_see_if_next:
	dec	cx
	jcxz	@F
	jmp	scc_next_char		;Until all characters pushed
	mov	ax,di			;Next character starts here
@@:
PUBLIC	jak_change
jak_change:
	test	local_board_flags,BOARD_FLAG_ENABLE_216
	jz	@F
	call	text216_mono_to_color
	jmp	short jak_scc_is_done
@@:
	call	textv7_mono_to_color

jak_scc_is_done:
	mov	count,cx		; Save count
	mov	x,ax			; Save next char's start
	mov	off_lp_string,si	; Save next character
        mov     current_rhs,di          ; Save rhs
;	 jmp	 build_ret_addr
	jmp	build_ret_oem

;-----------------------------------------------------------------------;
;	This character is either clipped, or its last pixel is
;	the last pixel which will fit within the clipping rhs.
;	Adjust its width so it fits, set the remaining character
;	count to 1 so the loop will terminate, and reenter the
;	code where we came from.
;-----------------------------------------------------------------------;

scc_char_is_clipped:
	mov	cx,clip.right		;Compute number of pixels
	sub	di,cx			;  which have to be clipped
	sub	ax,di			;Set new character width
	mov	di,cx			;Set new rhs
	mov	cx,1			;Show this as last character
	jmp	scc_been_clipped	;Finish here

jak_non_justified_text endp




text_mask_tbl   LABEL   BYTE
DB	000H,	080H,	0C0H,	0E0H
DB	0F0H,	0F8H,	0FCH,	0FEH


;	jak_386_scc_build
;
;	This routine builds a mono bitmap of the text in the driver data
;	segment.
.386
PUBLIC	jak_386_scc_build
jak_386_scc_build	PROC	NEAR

	push	ds
        push    si
        push    di
        push    cx
        push    ax
	mov	ds,driver_data_seg
	lea	si,jak_text_buffer
	add	si,BUFFER_OFFSET_START

        mov     cl,dl
	xchg	di,ax
	sar	ax,3
	add	si,ax			;ptr to starting byte of current char
        mov     ax,clipped_font_height
        mov     jak_temp_height,ax

;       This next section copies all font scan lines of a given character
;       into a mono bitmap located in the driver data segment rotating the
;       font data to properly align the bits within a byte JUST AS IF this
;	mono bitmap were the actual Destination bitmap. Notice that some
;	font data that is left of the left clip edge and right of the right
;	clip edge may get laid into the mono map (basically bits at the
;	beginning and end of the left edge byte and right edge byte
;       respectively). These will be masked later when going to the screen.

jak3_scc_scan_loop:
	push	ebx
        push    si
        push    di
        cmp     jak_first_char,0
	je	short jak3_scc_start
	mov	byte ptr ds:[si],0
	jmp	short jak3_scc_start

jak3_scc_full_byte:
	mov	al,es:[ebx]
	sub	ah,ah
	ror	ax,cl
	or	ds:[si],al
	inc	si
	mov	ds:[si],ah
	movzx	eax,lfd.font_height
	add	ebx,eax
        sub     di,8
	je	jak3_scc_next_scan

jak3_scc_start:
        cmp     di,8
	jae	jak3_scc_full_byte

        mov     dl,text_mask_tbl[di]
        sub     dh,dh
        ror     dx,cl

	mov	al,es:[ebx]
        sub     ah,ah
        ror     ax,cl
	and	ax,dx
        or      ds:[si],al
	test	dx,0FF01H
	jz	jak3_scc_next_scan
        inc     si
        mov     ds:[si],ah

jak3_scc_next_scan:
        pop     di
        pop     si
	pop	ebx
	inc	ebx
	add	si,jak_text_buffer_width
	dec	jak_temp_height
	jne	jak3_scc_scan_loop

        pop     ax
        pop     cx
        pop     di
        pop     si
        pop     ds
	ret

.286
jak_386_scc_build	ENDP





;	jak_286_scc_build
;
;	This routine builds a mono bitmap of a text char in the driver data
;	segment.
PUBLIC	jak_286_scc_build
jak_286_scc_build	PROC	NEAR

	push	ds
        push    si
        push    di
        push    cx
        push    ax
	mov	ds,driver_data_seg
	lea	si,jak_text_buffer
	add	si,BUFFER_OFFSET_START

        mov     cl,dl
	xchg	di,ax
	sar	ax,3
	add	si,ax			;ptr to starting byte of current char
        mov     ax,clipped_font_height
        mov     jak_temp_height,ax

;       This next section copies all font scan lines of a given character
;       into a mono bitmap located in the driver data segment rotating the
;       font data to properly align the bits within a byte JUST AS IF this
;	mono bitmap were the actual Destination bitmap. Notice that some
;	font data that is left of the left clip edge and right of the right
;	clip edge may get laid into the mono map (basically bits at the
;	beginning and end of the left edge byte and right edge byte
;       respectively). These will be masked later when going to the screen.

jak2_scc_scan_loop:
	push	bx
        push    si
        push    di
        cmp     jak_first_char,0
	je	short jak2_scc_start
	mov	byte ptr ds:[si],0
	jmp	short jak2_scc_start

jak2_scc_full_byte:
	mov	al,es:[bx]
	sub	ah,ah
	ror	ax,cl
	or	ds:[si],al
	inc	si
	mov	ds:[si],ah
	add	bx,lfd.font_height
        sub     di,8
	je	jak2_scc_next_scan

jak2_scc_start:
        cmp     di,8
	jae	jak2_scc_full_byte

        mov     dl,text_mask_tbl[di]
        sub     dh,dh
        ror     dx,cl

	mov	al,es:[bx]
        sub     ah,ah
        ror     ax,cl
	and	ax,dx
        or      ds:[si],al
	test	dx,0FF01H
	jz	jak2_scc_next_scan
        inc     si
        mov     ds:[si],ah

jak2_scc_next_scan:
        pop     di
        pop     si
	pop	bx
	inc	bx
	add	si,jak_text_buffer_width
	dec	jak_temp_height
	jne	jak2_scc_scan_loop

        pop     ax
        pop     cx
        pop     di
        pop     si
        pop     ds
	ret

jak_286_scc_build	ENDP





;       textv7_mono_to_color
;
;	This routine takes the mono bitmap that was built in the driver
;	data segment and expands it to color on the screen.
;	PARMS:
;	di	right edge (not-inclusive) of text region
;
;       The left edge pixel of the mono bitmap is at:
;	Data   byte:jak_ptr_txt_buf + (clip.left >> 3)	 bit:(clip.left & 7)
;
;	The left edge of the screen bitmap is at:
;	ScreenSelector	 byte:text_bbox.top * next_scan + clip.left

PUBLIC	textv7_mono_to_color
textv7_mono_to_color	PROC	NEAR

	pusha
	push	ds
	push	es

	mov	cx,di			;cx has extent in pixels
	sub	cx,jak_start_text

	mov	ds,driver_data_seg
	lea	si,jak_text_buffer
	add	si,BUFFER_OFFSET_START
	mov	ax,jak_start_text
	sar	ax,3
	add	si,ax

	mov	es,local_ScreenSelector
	mov	ax,text_bbox.top	;Compute Y component of the string
	mul	next_scan		; dl holds bank select bits
	mov	di,ax
	add	di,jak_start_text	; Add delta into scan
	adc	dl,dh			; add in segment carry
        SET_BANK                        ; do the video h/w bank select

	mov	dx,clipped_font_height
	mov	jak_temp_height,dx
	mov	dx,jak_start_text
	and	dx,7
	xchg	cx,dx
	mov	bx,ss_colors		;bh = bgcolor	 bl=fgcolor

	test	accel,IS_OPAQUE
	jz	tv7tmc_left_edge
        xor     bl,bh

tv7omc_left_edge:
	push	si
	push	di
	push	dx
	lodsb				;get first byte of mono scanline data
	mov	ah,al
	shl	ah,cl			;align first pixel to output
	mov	ch,1
	shl	ch,cl			;align rotating bit counter

tv7omc_loop:
	shl	ah,1
	sbb	al,al
	and	al,bl
	xor	al,bh
	stosb
	dec	dx
	je	tv7omc_next_scan
	rol	ch,1
	jnc	tv7omc_loop
	lodsb
	mov	ah,al
        jmp     short tv7omc_loop

tv7omc_next_scan:
	pop	dx
	pop	di
	pop	si
	add	si,jak_text_buffer_width
	add	di,MEMORY_WIDTH
	dec	jak_temp_height
	jne	tv7omc_left_edge
	jmp	tv7mc_done


tv7tmc_left_edge:
	push	si
	push	di
	push	dx
	lodsb				;get first byte of mono scanline data
	mov	ah,al
	shl	ah,cl			;align first pixel to output
	mov	ch,1
	shl	ch,cl			;align rotating bit counter

tv7tmc_loop:
	shl	ah,1
	jnc	@F
	mov	es:[di],bl
@@:	inc	di
	dec	dx
	je	tv7tmc_next_scan
	rol	ch,1
	jnc	tv7tmc_loop
	lodsb
	mov	ah,al
        jmp     short tv7tmc_loop

tv7tmc_next_scan:
	pop	dx
	pop	di
	pop	si
	add	si,jak_text_buffer_width
	add	di,MEMORY_WIDTH
	dec	jak_temp_height
	jne	tv7tmc_left_edge

tv7mc_done:
	pop	es
	pop	ds
	popa
	ret

textv7_mono_to_color	ENDP





;	text216_mono_to_color
;
;	This routine takes the mono bitmap that was built in the driver
;	data segment and expands it to color on the screen using the 216
;	mono to color expansion hardware.
;	PARMS:
;	di	right edge (not-inclusive) of text region
;
;       The left edge pixel of the mono bitmap is at:
;	Data   byte:jak_ptr_txt_buf + (clip.left >> 3)	 bit:(clip.left & 7)
;
;	The left edge of the screen bitmap is at:
;	ScreenSelector	 byte:text_bbox.top * next_scan + clip.left

PUBLIC	text216_mono_to_color
text216_mono_to_color	 PROC	 NEAR

	pusha
	push	ds
	push	es

	mov	cx,jak_start_text
        and     cx,7
        neg     cx
        add     cx,8
	mov	ax,1
	shl	ax,cl
	dec	ax
	mov	byte ptr jak_text_left_edge_mask,al

	mov	cx,di
	dec	cx
	and	cx,7
	mov	al,80H
	sar	al,cl
	mov	byte ptr jak_text_right_edge_mask,al

	mov	ax,jak_start_text
	mov	bx,di
	sar	ax,3
        dec     bx
	sar	bx,3
        sub     bx,ax
	je	bsd_prep_combine_edges

	dec	bx
	mov	jak_text_full_byte_count,bx
	jmp	short bsd_prep_done_edges

bsd_prep_combine_edges:

	mov	ax,jak_text_left_edge_mask
	and	ax,jak_text_right_edge_mask
	mov	jak_text_left_edge_mask,ax
	sub	ax,ax
	mov	jak_text_full_byte_count,ax
	mov	jak_text_right_edge_mask,ax

bsd_prep_done_edges:

	mov	ds,driver_data_seg
	lea	si,jak_text_buffer
	add	si,BUFFER_OFFSET_START
	mov	ax,jak_start_text
	sar	ax,3
	add	si,ax

	mov	es,local_ScreenSelector
	mov	ax,text_bbox.top	;Compute Y component of the string
	mov	dx,MEMORY_WIDTH / 8
	mul	dx			;for 216 mono to color expansion,
	mov	di,ax			; the hw mulitplies the address by 8
	mov	ax,jak_start_text
	sar	ax,3
	add	di,ax
	adc	dl,dh			; add in segment carry
        SET_BANK                        ; do the video h/w bank select

        mov     bx,ss_colors            ;bh = bgcolor    bl=fgcolor
	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_FOREGROUND_COLOR
	mov	ah,bl
	out	dx,ax
	mov	al,VGAREG_SQ_BACKGROUND_COLOR
	mov	ah,bh
	out	dx,ax

	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_FOREBACK_MODE
	out	dx,al
	inc	dx
	in	al,dx				;use the fg/bg color regs as
	and	al,NOT 0CH			; input A into the ALU using
	or	al,06H				; the CPU byte as the select
	out	dx,al				; between fg and bg

	mov	dx,VGAREG_SQ_ADDR
	mov	ax,VGAREG_SQ_XALU +  (0AAH SHL 8)
        out     dx,ax

        mov     dx,clipped_font_height
        mov     jak_temp_height,dx

;	 test	 accel,IS_OPAQUE
;	 jz	 t216tmc_left_edge

PUBLIC	t216omc_left_edge
t216omc_left_edge:
	push	si
	push	di
        mov     dx,VGAREG_SQ_ADDR
	mov	ax,VGAREG_SQ_XALU_CONTROL +  (0A2H SHL 8)
	out	dx,ax					    ;turn on rmw

	mov	dx,VGAREG_GR_ADDR
	mov	al,VGAREG_GR_BITMASK
	mov	ah,byte ptr jak_text_left_edge_mask
	out	dx,ax
	mov	ah,es:[di]		;read from DM to fix 216 RMW bug!
	movsb				; left edge preserved by rmw/bitmask

	mov	ah,0FFH
	out	dx,ax
	mov	dx,VGAREG_SQ_ADDR
	mov	ax,VGAREG_SQ_XALU_CONTROL +  (082H SHL 8)
	out	dx,ax					    ;turn off rmw

	mov	cx,jak_text_full_byte_count
	or	cx,cx
	je	nofb
	test	di,1
	je	@F
	movsb
	dec	cx
@@:	shr	cx,1
	rep	movsw
	rcl	cx,1
	rep	movsb
nofb:
	mov	dx,VGAREG_SQ_ADDR
	mov	ax,VGAREG_SQ_XALU_CONTROL +  (0A2H SHL 8)
	out	dx,ax					    ;turn on rmw

        mov     dx,VGAREG_GR_ADDR
        mov     ah,byte ptr jak_text_right_edge_mask
	out	dx,ax
	mov	ah,es:[di]		;read from DM to fix 216 RMW bug!
        movsb                           ; left edge bits then do the write

	pop	di
	pop	si
	add	si,jak_text_buffer_width
	add	di,MEMORY_WIDTH / 8
	dec	jak_temp_height
	jne	t216omc_left_edge
	jmp	t216mc_done


t216tmc_left_edge:
	push	si
	push	di
	push	dx
	lodsb				;get first byte of mono scanline data
	mov	ah,al
	shl	ah,cl			;align first pixel to output
	mov	ch,1
	shl	ch,cl			;align rotating bit counter

t216tmc_loop:
	shl	ah,1
	jnc	@F
	mov	es:[di],bl
@@:	inc	di
	dec	dx
	je	t216tmc_next_scan
	rol	ch,1
	jnc	t216tmc_loop
	lodsb
	mov	ah,al
	jmp	short t216tmc_loop

t216tmc_next_scan:
	pop	dx
	pop	di
	pop	si
	add	si,jak_text_buffer_width
	add	di,MEMORY_WIDTH
	dec	jak_temp_height
	jne	t216tmc_left_edge


t216mc_done:
	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_FOREBACK_MODE
	out	dx,al
	inc	dx
	in	al,dx				;use the cpu byte as the
	and	al,NOT 0CH			; input into the ALU
	out	dx,al

	mov	dx,VGAREG_SQ_ADDR
	mov	ax,VGAREG_SQ_XALU_CONTROL +  (00H SHL 8)
	out	dx,ax

	mov	dx,VGAREG_GR_ADDR
	mov	ax,VGAREG_GR_BITMASK + (0FFH SHL 8)
	out	dx,ax

	pop	es
	pop	ds
	popa
	ret

text216_mono_to_color	 ENDP

sEnd    Code

END

