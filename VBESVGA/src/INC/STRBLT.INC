        page    ,132
;
;-----------------------------Module-Header-----------------------------;
; Module Name:	STRBLT.INC
;
;   This module contains the definition of strblt's frame, flag
;   definitions, and anything else common to all the seperate
;   modules which make up the strblt function.
;
; Created: 15-Apr-1987
; Author:  Walt Moore [waltm]
;
; Copyright (c) 1984-1987 Microsoft Corporation
;
; Exported Functions:	None
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
; Restrictions:
;
;-----------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.
;
;
; Definitions for the "accel" flag
;
IS_OPAQUE	equ	00000001b	;Background mode is opaque
HAVE_CHAR_EXTRA equ	00000010b	;Non-zero character extra given
DDA_NEEDED	equ	00000100b	;Justification DDA must be run
HAVE_BRK_EXTRA	equ	00001000b	;Some justification each break char
NEG_SPACING	equ	00010000b	;CharExtra or TBreakExtra was negative
HAVE_WIDTH_VECT equ	00100000b	;Width vector was given
FIXED_PITCH	equ	01000000b	;Font is fixed pitch
WIDTH_IS_8	equ	10000000b	;Font is 8 pixels per character
WEIRD_SPACING	equ	00111110b	;Any of these need special attention
;
;
; Definitions for the "excel" flag
;
OPAQUE_RECT	equ	00000001b	;Opaquing rectangle is present
TEXT_VISIBLE	equ	00000010b	;Some part of the text is visible
BOUNDED_IN_Y	equ	00000100b	;Text fits within opaque rectangle in Y
IS_DEVICE	equ	00001000b	;Destination is our device
FIRST_IN_PREV	equ	00010000b	;First char starts in previous byte
RES_EGA_INNER	equ	00100000b	;Restore EGA for opaque inner loop
CLIPPED_RIGHT	equ	01000000b	;Overhanging right side of clip rect
CLIPPED_LEFT	equ	10000000b	;Overhanging left  side of clip rect
;
;
; Definitions for the "wc_flags"
;
WC_OLD_OPAQUE	equ	00000001b	;Shadow of IS_OPAQUE
WC_SET_LR	equ	00000010b	;Set left/right into text bbox
;		equ	00000100b
STEPPED_BACK	equ	00001000b	;Stepped backwards at somepoint
;		equ	00010000b
;		equ	00100000b
;		equ	01000000b
;		equ	10000000b
;
;
MOST_POS_INT	equ	7FFFh		;Maximum positive integer
MOST_NEG_INT	equ	8000h		;Maximum negative integer
;
PROP_WIDTH	equ	0		;Width entry index for prop fonts
PROP_OFFSET	equ	2		;Offset entry index for prop fonts
;
STACK_SLOP	equ	200		;# of bytes of stack space we cannot
;					;  use when building up a string
;
; Definitions for the eto_options parameters
;
;		equ	00000001b	;Be thankful we removed this bit!
ETO_OPAQUE_FILL equ	00000010b	;Fill opaque rect with background color
ETO_OPAQUE_CLIP equ	00000100b	;Clip to opaque rectangle
;		equ	00001000b
;		equ	00010000b
;		equ	00100000b
;		equ	01000000b
;		equ	10000000b
;
; Index for foreground and background colors stored
; in the frame variable "colors"
;
FOREGROUND	equ	0
BACKGROUND	equ	4
;
;
; frame_data is the definition of the data which is pushed
; into the stack for each character (where a character
; should be defined as a pattern of 8 bits or less).
;
frame_data	struc
fd_width	db	?		;Width of the character
fd_phase	db	?		;X location mod 8
fd_bits_offset	dd	?		;Offset to the font data bits
frame_data	ends			; and real-mode
;
;
; The local font structure has information copied from the
; font structure passed to strblt.  Having the data in a
; structure makes it a little more efficient when copying
; the data to the frame.
;
local_font_def	struc
font_width	dw	0		;Width field for the font
font_height	dw	0		;Height field for the font
max_width	dw	0		;Maximum character width
first_char	db	0		;First character in the font
last_char	db	0		;Last character in the font (mapped)
default_char	db	0		;Default character for out of range
break_char	db	0		;Character to define word breaks
lp_font_bits	dd	0		;Pointer to actual bits of font
local_font_def	ends
;
;
; Certain locations of the stack frame will be used to store
; variables for the actual drawing routines.  No call can be
; outside the driver, or to another segment which could be
; non-resident while these locations are altered!
;
; Note well: only 16 bytes are available!
;
StrStuff	segment at 0
ss_height	dw	0		;# of scans to output
ss_next_scan	dw	?		;Delta to next scan of a bitmap
ss_draw 	dw	?		;Function to do output
ss_draw_clipped dw	?		;Function to do clipped output
ss_phases	dw	?		;Phases for 4 character case
ss_clip_mask	db	?		;Clipping mask
ss_num_chars	db	?		;Number characters for n char case
;ss_colors	dw	?		;Foreground/background colors
ss_pixbytes	dw	?		;Bytes per pixel
ss_p_frame	dw	?		;Link to stack frame
StrStuff	ends
;
;
;--------------------------------Macro----------------------------------;
; UpdBank
;
;	Advances the bank selection after an addition, if necessary
;
;	Assumes:
;		Addition has just been performed (e.g. "add di,ss_next_scan")
;		CF set accordingly
;
;-----------------------------------------------------------------------;
;
UpdBank        macro       ji
ifnb <ji>
	ji	@F
else
	jnc	@F
endif
	push	dx
	GET_BANK
	inc	dx
	SET_BANK
	pop	dx
@@:
	endm
;
;
;---------------------------------Macro---------------------------------;
; define_frame
;
; Macro for defining the frame for strblt functions
;
; This file allows the frame definiton to be shared by all
; the modules whoch make up the strblt function.
;
; Calls:
;	none
; History:
;	Wed 15-Apr-1987 17:06:26 -by-  Walt Moore [waltm]
;	Initial version
;-----------------------------------------------------------------------;
;
define_frame macro  name
cProc	name,<FAR,PUBLIC,WIN,PASCAL>,<si,di,es,ds>
	parmD	lp_device		;Destination device
	parmW	x			;Left origin of string
	parmW	y			;Top  origin of string
	parmD	lp_clip_rect		;Clipping rectangle
	parmD	lp_string		;The string itself
	parmW	count			;Number of characters in the string
	parmD	lp_font 		;Font to use
	parmD	lp_draw_mode		;Drawmode structure to use
	parmD	lp_xform		;Current text transform
	parmD	lp_dx			;Widths for the characters
	parmD	lp_opaque_rect		;Opaquing rectangle
	parmW	eto_options		;ExtTextOut options
;
	localB	local_enabled_flag	;local copy of the enabled_flag
	localB	smart_flags
	localB	left_clip_mask		;lhs clip mask (00 if no partial left)
	localB	right_clip_mask 	;rhs clip mask (00 if no partial byte)
	localB	accel			;Accelerator flags
	localB	excel			;Accelerator flags
	localB	num_planes		;Number of planes in a bitmap
	localB	wc_flags		;Flags for worst case text
	localQ	colors			;Text/background colors
;
	localW	char_xtra		;# extra pixels to add each char
	localW	brk_extra		;# extra pixels to add each break char
	localW	brk_err 		;Justification DDA error term
	localW	brk_count		;DDA - # breaks into which BrkRem
	localW	brk_rem 		;  extra pixels are distributed
	localW	tot_brk_extra		;Total break extra
;
	localW	next_scan		;Index to get to next scan line
	localW	opaque_routine		;Routine which does actual opaquing
	localW	opaque_height		;Height of opaque box (sometimes)
	localD	lp_surface		;Pointer to first byte of destination
	localW	temp_off_lp_bits	;Intermediate pointer to dev surface
	localW	scan_start		;Delta from start of scan
;
	localW	clipped_font_height	;Actual height of bits to be drawn
	localW	amt_clipped_on_top	;# of font scans clipped off top
;
	localW	cell_adjust		;Delta to get from one column to next
	localW	buffer			;Offset of buffer on the stack
;
	localD	null_char_offset	;Offset of the special null character
;
	localW	num_null_pixels 	;Number of pixels to add
;
	localW	clear_stack		;SP value used to clean up stack
	localW	min_stack		;SP where we run out of stack
	localW	build_proc		;Procedure which builds stack data
;
	localW	phase
	localW	inner_loop
;
	localW	clipped_table		;Dispatch table for clipped characters
	localW	non_clipped_table	;Dispatch table for non-clipped chars
	localW	inner_byte_count	;Number of whole dest bytes altered
;
	localW	current_lhs		;LHS of current sub-string
	localW	current_rhs		;RHS of current sub-string
	localW	wc_opaque_lhs		;Left  side opaqued by worst case code
	localW	wc_opaque_rhs		;Right side opaqued by worst case code
;
	localW	string_start_bias	;# chars skipped at start of string
	localW	ret_addr		;Fixed pitch draw routine return addr
	localW	unrolled_entry_point	;Start addr for unrolled loops
;
	localW	vect_one_in_first	;Dispatch vectors for fixed pitch code
	localW	vect_two_in_first
	localW	vect_one_in_middle
	localW	vect_two_in_middle
	localW	vect_one_in_last
	localW	vect_two_in_last
;
	localV	lfd,%(size local_font_def)
	localV	clip,%(size RECT)
	localV	text_bbox,%(size RECT)
	localV	o_rect,%(size RECT)
;
	localV	ss_save_area,16
	localW	ret_addr_2
	localW	ega_oc_saved_data
;
; Video 7 Additions
;
	localB	CurVidSel		; holds the video segment #
	localB	BitsaPixel		; number of bits'a pixel
	localB	ColorPhase		; holds color map phase shift
	localW	FontSelector		; protected mode font selector storage
	localD	xlate_draw_mode 	; translated Drawmode structure to use
	localW	local_VScreen_Width	; VScreen_Width from Data segment
	localW	driver_data_seg
	localW	jak_temp_height
	localW	jak_text_buffer_width
	localW	local_ScreenSelector
	localW	jak_start_text
	localW	jak_first_char
	localW	jak_text_left_edge_mask
	localW	jak_text_right_edge_mask
	localW	jak_text_full_byte_count
	localW	local_board_flags

;
	endm
;
