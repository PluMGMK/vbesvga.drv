	page	,132
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; smartfix.asm
;
; Copyright (c) 1991 Microsoft Corporation.  All Rights Reserved.
;
; This module contains the routines for outputting fixed
; pitch characters only.
;
; Created: 24-Jul-1987
;
; Exported Functions:	None
;
; Public Functions:
;	gen_one_in_first
;	gen_two_in_first
;	gen_one_in_cell
;	gen_two_in_cell
;	gen_one_in_last
;	gen_two_in_last
;
;	ega_oc_outer_loop_fix
;	ega_oc_outer_loop_fix_two
;
;
; if SPECIAL_CASE_BM_OBWNC eq 1		;Bitmap, opaque blk on white, no clip
;	bm_obwnc_one_in_cell
;	bm_obwnc_two_in_cell
; endif
;
; if SPECIAL_CASE_BM_TBNC eq 1 		;Bitmap, transp black, non-clipped
;	bm_tbnc_one_in_cell
;	bm_tbnc_two_in_cell
; endif
;
; if SPECIAL_CASE_DEV_ONC eq 1		;Device, opaque, non-clipped
;	dev_onc_one_in_cell
;	dev_onc_two_in_cell
; endif
;
; if SPECIAL_CASE_DEV_TNC eq 1 		;Device, transparent, non-clipped
;	dev_tnc_one_in_cell
;	dev_tnc_two_in_cell
; endif
;
; Public Data:		none
;
; General Description:
;
; Restrictions:
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;	Define the portions of gdidefs.inc that will be needed

incDrawMode	= 1			;Include GDI DrawMode definitions

	.xlist
	include cmacros.inc
	include fontseg.inc
	include gdidefs.inc
	include display.inc
	include macros.mac
	include strblt.inc
	include	ega.inc
	include	egamem.inc
	.list

	externA 	stack_top	;Stack probe location
	externA		ScreenSelector
	externA		SCREEN_W_BYTES

	externW		ega_oc

	externNP	setup_ega_opaque_clip_magic
	externNP	set_ega_opaque_mode
	externNP	bm_trans_color_fix
	externNP	bm_opaque_color_fix

;	Special cases

SPECIAL_CASE_BM_OBWNC	=0		;Opaque black on white, non-clipped
SPECIAL_CASE_BM_TBNC 	=0		;Transparent black, non-clipped
SPECIAL_CASE_DEV_ONC	=1		;Device, opaque, non-clipped
SPECIAL_CASE_DEV_TNC 	=1		;Device, transparent, non-clipped


UNROLL_BY_8 = 1


sBegin	Code
	externNP comp_byte_interval	;Interval calculations
	externNP build_string		;Proportional text output routine
sEnd	Code



;	Equates for indices into ega_oc_dispatch_table.

OC_MASK_TWO_CHAR	equ	010b

OC_ONE_IN_FIRST		equ	000b
OC_TWO_IN_FIRST		equ	010b
OC_ONE_IN_LAST		equ	100b
OC_TWO_IN_LAST		equ	110b


;	Definitions of the bits in smart_flags.

TWO_SOURCES_IN_FIRST	equ	00000001b
TWO_SOURCES_IN_LAST	equ	00000010b


ret_near	macro
	db	0C3h			;Near return, no parameters popped
		endm
page

;--------------------------------Macro----------------------------------;
; char_check
;
;	char_check is a debugging macro turned on to count the
;	number of character offsets popped off the stack.  When
;	this number becomes negative, then offset about to be
;	fetched will be invalid.
;
;	Usage:
;		upd_bm
;-----------------------------------------------------------------------;

char_check	macro
	local	char_is_good
if 0
	cmp	sp,clear_stack
	jb	char_is_good
	int	3
char_is_good:
endif
	endm


;--------------------------------Macro----------------------------------;
; upd_bm
;
;	upd_bm is the macro used for generating the destination update
;	code for a bitmap in the generic handlers.
;
;	Usage:
;		upd_bm
;-----------------------------------------------------------------------;

upd_bm	macro
if DRAW_ADJUST				;;If last logic operation defined
	dec	di			;;  did a stosb, adjust for it
endif
	add	di,ss_next_scan
	jmp	dx			;;Return to caller
	endm


;--------------------------------Macro----------------------------------;
; upd_dev
;
;	upd_dev is the macro used for generating the destination update
;	code for the physical device in the generic handlers.
;
;	Usage:
;		upd_dev
;-----------------------------------------------------------------------;


upd_dev macro
if DRAW_ADJUST				;;If last logic operation defined
	add	di,SCREEN_W_BYTES-1	;;  did a stosb, adjust for it
else
	add	di,SCREEN_W_BYTES
endif
	jmp	dx			;;Return to caller
	endm
page

;--------------------------------Macro----------------------------------;
; clipped_output
;
;	clipped_output is the macro passed to the "x" character macros
;	when the default subroutines are to be called for outputing a
;	clipped character
;
;	Usage:
;		clipped_output fetch
;	Where
;		fetch	is the macro to be invoked for generating
;			the fetching logic
;-----------------------------------------------------------------------;

clipped_output macro fetch
	fetch
	jmp	ss_draw_clipped
	endm


;--------------------------------Macro----------------------------------;
; non_clipped_output
;
;	non_clipped_output is the macro passed to the "x" character
;	macros when the default subroutines are to be called for
;	outputing a non-clipped character
;
;	Usage:
;		non_clipped_output fetch
;	Where
;		fetch	is the macro to be invoked for generating
;			the fetching logic
;-----------------------------------------------------------------------;

non_clipped_output macro fetch
	fetch
	jmp	ss_draw
	endm


;--------------------------------Macro----------------------------------;
; owwc
;
;	owwc  is a macro for generating the character drawing
;	logic for opaque mode, white text, white background, clipped.
;
;	Usage:
;		owwc fetch
;	Where
;		fetch	is the macro to be invoked for generating
;			the fetching logic
;-----------------------------------------------------------------------;

owwc	macro	fetch
	mov	al,ss_clip_mask
	or	es:[di],al
DRAW_ADJUST	= 0			;;STOSB isn't used
	endm


;--------------------------------Macro----------------------------------;
; twc
;
;	twc is a macro for generating the character drawing
;	logic for transparent mode, white text, clipped.
;
;	Usage:
;		twc fetch
;	Where
;		fetch	is the macro to be invoked for generating
;			the fetching logic
;-----------------------------------------------------------------------;

twc	macro	fetch
	fetch
	and	al,ss_clip_mask
	or	es:[di],al
DRAW_ADJUST	= 0			;;STOSB isn't used
	endm


;--------------------------------Macro----------------------------------;
; twnc
;
;	tw_non_clipped is a macro for generating the character drawing
;	logic for transparent mode, white text, non-clipped.
;
;	Usage:
;		twnc fetch
;	Where
;		fetch	is the macro to be invoked for generating
;			the fetching logic
;-----------------------------------------------------------------------;

twnc	macro	fetch
	fetch
	or	es:[di],al
DRAW_ADJUST	= 0			;;STOSB isn't used
	endm


;--------------------------------Macro----------------------------------;
; obbc
;
;	obbc is a macro for generating the character drawing
;	logic for opaque mode, black text, black background, clipped.
;
;	Usage:
;		obbc fetch
;	Where
;		fetch	is the macro to be invoked for generating
;			the fetching logic
;-----------------------------------------------------------------------;

obbc	macro	fetch
	mov	al,ss_clip_mask
	not	al
	and	es:[di],al
DRAW_ADJUST	= 0			;;STOSB isn't used
	endm


;--------------------------------Macro----------------------------------;
; tbc
;
;	tbc is a macro for generating the character drawing
;	logic for transparent mode, black text, clipped.
;
;	Usage:
;		tbc fetch
;	Where
;		fetch	is the macro to be invoked for generating
;			the fetching logic
;-----------------------------------------------------------------------;

tbc	macro	fetch
	fetch
	and	al,ss_clip_mask
	not	al
	and	es:[di],al
DRAW_ADJUST	= 0			;;STOSB isn't used
	endm


;--------------------------------Macro----------------------------------;
; tbnc
;
;	tbnc is a macro for generating the character drawing
;	logic for transparent mode, black text, non-clipped.
;
;	Usage:
;		tbnc fetch
;	Where
;		fetch	is the macro to be invoked for generating
;			the fetching logic
;-----------------------------------------------------------------------;

tbnc	macro	fetch
	fetch
	not	al
	and	es:[di],al
DRAW_ADJUST	= 0			;;STOSB isn't used
	endm


;--------------------------------Macro----------------------------------;
; obwc
;
;	obwc is a macro for generating the character drawing
;	logic for opaque mode, black text, white background, clipped.
;
;	Usage:
;		obwc fetch
;	Where
;		fetch	is the macro to be invoked for generating
;			the fetching logic
;-----------------------------------------------------------------------;

obwc	macro	fetch
	fetch
	not	al
	mov	ah,ss_clip_mask
	and	al,ah
	not	ah
	and	ah,es:[di]
	or	al,ah
	stosb
DRAW_ADJUST	= 1			;;STOSB is used
	endm


;--------------------------------Macro----------------------------------;
; owbc
;
;	owbc is a macro for generating the character drawing
;	logic for opaque mode, white text, black background, clipped.
;
;	Usage:
;		owbc fetch
;	Where
;		fetch	is the macro to be invoked for generating
;			the fetching logic
;-----------------------------------------------------------------------;

owbc	macro	fetch
	fetch
	mov	ah,ss_clip_mask
	and	al,ah
	not	ah
	and	ah,es:[di]
	or	al,ah
	stosb
DRAW_ADJUST	= 1			;;STOSB is used
	endm


;--------------------------------Macro----------------------------------;
; obwnc
;
;	obwnc is a macro for generating the character drawing
;	logic for opaque mode, black text, white background, non-clipped.
;
;	Usage:
;		obwnc fetch
;	Where
;		fetch	is the macro to be invoked for generating
;			the fetching logic
;-----------------------------------------------------------------------;

obwnc	macro	fetch
	fetch
	not	al
	stosb
DRAW_ADJUST	= 1			;;STOSB is used
	endm


;--------------------------------Macro----------------------------------;
; owbnc
;
;	owbnc is a macro for generating the character drawing
;	logic for opaque mode, white text, black background, non-clipped.
;
;	Usage:
;		owbnc fetch
;	Where
;		fetch	is the macro to be invoked for generating
;			the fetching logic
;-----------------------------------------------------------------------;

owbnc	macro	fetch
if FETCH_IS_LODSB			;;If fetch logic is simply a
	movsb				;;  LODSB, then use a MOVSB
else					;;else
	fetch				;;  use passed fetch logic
	stosb
endif
DRAW_ADJUST	= 1			;;STOSB/MOVSB is used
	endm


;--------------------------------Macro----------------------------------;
; obbnc
;
;	obwnc is a macro for generating the character drawing
;	logic for opaque mode, black text, black background, non-clipped.
;
;	Usage:
;		obbnc fetch
;	Where
;		fetch	is the macro to be invoked for generating
;			the fetching logic
;-----------------------------------------------------------------------;

obbnc	macro	fetch
	mov	byte ptr es:[di],0
DRAW_ADJUST	= 0			;;STOSB isn't used
	endm


;--------------------------------Macro----------------------------------;
; owwnc
;
;	owwnc is a macro for generating the character drawing
;	logic for opaque mode, white text, white background, non-clipped.
;
;	Usage:
;		owwnc fetch
;	Where
;		fetch	is the macro to be invoked for generating
;			the fetching logic
;-----------------------------------------------------------------------;

owwnc	macro	fetch
	mov	byte ptr es:[di],0FFh
DRAW_ADJUST	= 0			;;STOSB isn't used
	endm


;--------------------------------Macro----------------------------------;
; ega_onc_fix
;
;	ega_onc_fix is a macro for generating the character drawing
;	logic for opaque mode, non-clipped, for the EGA.  The hardware
;	has been correctly programmed for color.
;
;	Usage:
;		ega_onc_fix fetch
;	Where
;		fetch	is the macro to be invoked for generating
;			the fetching logic
;-----------------------------------------------------------------------;

ega_onc_fix	macro	fetch
if FETCH_IS_LODSB			;;If fetch logic is simply a
	movsb				;;  LODSB, then use a MOVSB
else					;;else
	fetch				;;  use passed fetch logic
	stosb
endif
DRAW_ADJUST	= 1			;;STOSB/MOVSB is used
	endm
page

;--------------------------------Macro----------------------------------;
; ega_tnc_fix
;
;	ega_tnc_fix is a macro for generating the character drawing
;	logic for opaque mode, non-clipped, for the EGA.  The hardware
;	has been correctly programmed for color.
;
;	Usage:
;		ega_tnc_fix fetch
;	Where
;		fetch	is the macro to be invoked for generating
;			the fetching logic
;-----------------------------------------------------------------------;

ega_tnc_fix	macro	fetch
	fetch				;;  use passed fetch logic
	out	dx,al
	xchg	al,es:[di]
DRAW_ADJUST	= 0			;;STOSB/MOVSB is used
	endm
page

;-----------------------------------------------------------------------;
;
; The following macros define the logic involved for processing the
; various combinations of required sources and first/middle/last bytes.
;
;
; The basic control flow is:
;
;	initialization by the invoking macro
;	entry_logic
;	while (count > 0)
;	{
;	    loop_setup
;	    while (scans in font)
;	    {
;		fetch_logic
;		draw_logic
;	    }
;	    loop_logic
;	}
;	exit code by the invoking macro
;
;
; entry_logic:
;
;   The entry_logic macro is invoked to define any preprocessing
;   which may be required for the operation.  This is performed
;   outside the outer most loop.
;
;	Entry:
;	    DS:SI   = font bits of char
;	    ES:DI   = destination pointer
;	    CL	    = phase (shift count)
;	Registers Destroyed:
;	    AX,BX,CH
;	Registers Preserved:
;	    SI,DI,DS,ES
;
;
; loop_setup
;
;   The loop_setup macro is invoked for each destination character
;   which must be accumulated.
;
;	Entry:
;	    DS:SI   = font bits of char or previous char, as determined
;		      by the case being processed
;	    ES:DI   = destination pointer
;	    CL	    = phase (shift count)
;	    SS:SP   = offset of next character if required
;	Exit:
;	    DS:SI   = font bits of char
;	    ES:DI   = destination pointer
;	    CL	    = phase (shift count)
;	    SS:SP   = offset of next character if required
;	    BX	      as required by fetch logic
;	Registers Destroyed:
;	    AX,BX,CH
;	Registers Preserved:
;	    CL,DX,DI,DS,ES
;
;
; fetch_logic:
;
;   The fetch_logic macro is invoked once for each destination byte
;   which must be accumulated.
;
;	Entry:
;	    DS:SI   = font bits of char
;	    ES:DI   = destination pointer
;	    CL	    = phase (shift count)
;	    CH	    = loop count
;	    SS:SP   = offset of next character if required
;	    BX	      as required by fetch logic
;	Exit:
;	    DS:SI   = next font bits of char
;	    ES:DI   = destination pointer
;	    CL	    = phase (shift count)
;	    CH	    = loop count
;	    BX	      as required by fetch logic
;	Registers Destroyed:
;	    AX
;	Registers Preserved:
;	    CX,DX,DI,DS,ES,SP
;
;
; draw_logic:
;
;   The draw_logic macro is invoked once for each destination byte
;   which must be displayed.
;
;	Entry:
;	    AL	    = bits of character to be displayed
;	    DS:SI   = font bits of char
;	    ES:DI   = destination pointer
;	    CL	    = phase (shift count)
;	    CH	    = loop count
;	    BX	      as required by fetch logic
;	Exit:
;	    DS:SI   = next font bits of char
;	    ES:DI   = next destination pointer
;	    CL	    = phase (shift count)
;	    CH	    = loop count
;	Registers Destroyed:
;	    AX
;	Registers Preserved:
;	    BX,CX,DX,SP
;
;
; loop_logic:
;
;   The loop_logic macro is invoked after each complete character
;   has been displayed.  loop_logic takes a parameter which is the
;   label to jump to if more characters exist.	This parameter will
;   only be used for the middle byte routines.
;
;	Entry:
;	    DS:SI   = font bits of char
;	    ES:DI   = destination pointer
;	    CL	    = phase (shift count)
;	    SS:SP   = offset of next character if required
;	Exit:
;	    DS:SI   = font bits of char incase char is required for next
;		      output operation
;	    ES:DI   = start of next char's destination
;	    CL	    = phase (shift count)
;	Registers Destroyed:
;	    AX,BX,CH
;	Registers Preserved:
;	    CL,DX,SP
;
;-----------------------------------------------------------------------;


;--------------------------------Macro----------------------------------;
; one_in_first
;
; one_in_last defines the macros for the case where the first horizontal
; set of bytes contains part or all of only one character.
;
;-----------------------------------------------------------------------;

one_in_first	macro

entry_logic	&macro			;;No entry logic is required
	&endm				;;
					;;
loop_setup	&macro			;;DS:SI is setup for us at entry
	&endm				;;
					;;
FETCH_IS_LODSB = 1			;;Show fetch is only a LODSB
fetch_logic	&macro			;;Bit fetching logic
	lodsb				;;
	shr	al,cl			;;AL = bits to output
	&endm				;;
					;;
loop_logic	&macro	target		;;Outer loop looping logic
	sub	si,clipped_font_height	;;Restore character start
	sub	di,cell_adjust		;;Point to start of next char
	&endm

	endm
page

;--------------------------------Macro----------------------------------;
; two_in_first
;
; two_in_first defines the macros for the case where the first
; horizontal set of bytes contains part of two characters.
;
;-----------------------------------------------------------------------;

two_in_first	macro

entry_logic	&macro			;;No entry logic is required
	&endm				;;
					;;
loop_setup	&macro			;;Outer loop logic setup
	mov	bx,si			;;DS:BX = font bits of first char
	char_check
	pop	si			;;Get offset of second character
	sub	bx,si			;;Using a delta saves an increment
	&endm				;;
					;;
FETCH_IS_LODSB = 0			;;Show fetch is more than a LODSB
fetch_logic	&macro			;;Bit fetching logic
	mov	ah,[bx][si]		;;AH = byte from first char.
	lodsb				;;AL = byte from second char.
	shr	ax,cl			;;AL = bits to output
	&endm				;;
					;;
loop_logic	&macro	target		;;Outer loop looping logic
	sub	si,clipped_font_height	;;Restore character start
	sub	di,cell_adjust		;;Point to start of next char
	&endm

	endm
page

;--------------------------------Macro----------------------------------;
; one_in_last
;
; one_in_last handles the case when the last horizontal set of bytes
; contains part or all of only one character.
;
;-----------------------------------------------------------------------;

one_in_last	macro

entry_logic	&macro
	sub	cl,8			;;Reverse phase on entry.  Phase
	neg	cl			;;  will not be used again as this
	and	cl,7			;;  is the last character
	&endm				;;
					;;
loop_setup	&macro			;;No outer loop logic is required
	&endm				;;
					;;
FETCH_IS_LODSB = 0			;;Show fetch is more than a LODSB
fetch_logic	&macro			;;Bit fetching logic
	lodsb				;;
	shl	al,cl			;;AL = bits to output
	&endm				;;
					;;
loop_logic	&macro	target		;;No outer loop looping logic is
	&endm				;;  needed as this is last char

	endm
page

;--------------------------------Macro----------------------------------;
; two_in_last
;
; two_in_last handles the case when the last horizontal set of bytes
; contains parts of two characters.
;
;-----------------------------------------------------------------------;

two_in_last	macro

entry_logic	&macro			;;No entry logic is required
	&endm				;;
					;;
loop_setup	&macro			;;Outer loop logic setup
	mov	bx,si			;;DS:BX = font bits of first char
	char_check
	pop	si			;;Get offset of second character
	sub	bx,si			;;Using a delta saves an increment
	&endm				;;
					;;
FETCH_IS_LODSB = 0			;;Show fetch is more than a LODSB
fetch_logic	&macro			;;Bit fetching logic
	mov	ah,[bx][si]		;;AH = byte from first char.
	lodsb				;;AL = byte from second char.
	shr	ax,cl			;;AL = bits to output
	&endm				;;
					;;
loop_logic	&macro	target		;;No outer loop looping logic is
	&endm				;;  needed as this is last char

	endm

page

;--------------------------------Macro----------------------------------;
; two_in_cell
;
; two_in_cell handles a variable number of middle bytes (not first
; or last byte), where two source characters are required to make
; up a destination byte.
;
;-----------------------------------------------------------------------;

two_in_cell	macro

entry_logic	&macro			;;No entry logic is required
	&endm				;;
					;;
loop_setup	&macro			;;Outer loop logic setup
	mov	bx,si			;;DS:BX = font bits of first char
	char_check
	pop	si			;;Get offset of second character
	sub	bx,si			;;Using a delta saves an increment
	&endm				;;
					;;
FETCH_IS_LODSB = 0			;;Show fetch is more than a LODSB
fetch_logic	&macro			;;Bit fetching logic
	mov	ah,[bx][si]		;;AH = byte from first char.
	lodsb				;;AL = byte from second char.
	shr	ax,cl			;;AL = bits to output
	&endm				;;
					;;
loop_logic	&macro	target		;;Outer loop looping logic
	sub	si,clipped_font_height	;;Restore character start
	sub	di,cell_adjust		;;Point to start of next char
	dec	count			;;Update inner byte count
	jnz	target			;;If more characters exist
	&endm

long_loop_logic	&macro	target		;;Outer loop looping logic
local	foo
	sub	si,clipped_font_height	;;Restore character start
	sub	di,cell_adjust		;;Point to start of next char
	dec	count			;;Update inner byte count
	jz	foo
	jmp	target			;;If more characters exist
foo:
	&endm
	endm
page

;--------------------------------Macro----------------------------------;
; one_in_cell
;
; one_in_cell handles a variable number of middle bytes (not first
; or last byte), where one source character is required to make
; up a destination byte.  This will be the case when the characters
; are byte aligned.
;
;-----------------------------------------------------------------------;

one_in_cell	macro

entry_logic	&macro			;;No entry logic is required
	&endm				;;
					;;
loop_setup	&macro			;;Outer loop logic setup
	char_check
	pop	si			;;Get offset of next character
	&endm				;;
					;;
FETCH_IS_LODSB = 1			;;Show fetch is only a LODSB
fetch_logic	&macro			;;
	lodsb				;;AL = bits to output
	&endm				;;
					;;
loop_logic	&macro	target		;;Outer loop looping logic
	sub	di,cell_adjust		;;Point to start of next char
	dec	count			;;Update inner byte count
	jnz	target			;;If more characters exist
	&endm

	endm
page

;--------------------------------Macro----------------------------------;
; spec_case
;
;	spec_case is the macro invoked to define a special case
;	The special case loop will be unrolled by 8.
;
;	Usage:
;		spec_case name,logic,draw,ur
;	Where
;		name	is the name of the procedure being defined
;		logic	is the name of the macro which will define
;			the following macros:
;			    entry_logic - one shot entry preprocessing
;			    loop_setup	- character offset fetching
;			    fetch_logic - logic to fetch character bits
;			    loop_logic	- per char looping
;		draw	is the name of the macro to perform the actual
;			drawing of the bits
;-----------------------------------------------------------------------

spec_case	macro	name,logic,draw
if1
name&_DEST_ADJ = 0
endif
	logic				;;Define required macros

name&_disp_table label byte
	db	name&_loop_0-name&_loop
	db	name&_loop_1-name&_loop
	db	name&_loop_2-name&_loop
	db	name&_loop_3-name&_loop
if UNROLL_BY_8
	db	name&_loop_4-name&_loop
	db	name&_loop_5-name&_loop
	db	name&_loop_6-name&_loop
	db	name&_loop_7-name&_loop
endif

	public	name
name	proc	near
	mov	bl,byte ptr clipped_font_height
if UNROLL_BY_8
	and	bx,0007h
else
	and	bx,0003h
endif
	mov	bl,name&_disp_table[bx]
	add	bx,CodeOFFSET name&_loop
	mov	unrolled_entry_point,bx
	mov	dx,ss_next_scan 	;;Index to next scan of a bitmap
if name&_DEST_ADJ
	dec	dx
else
	nop
endif
	entry_logic			;;Any specific entry logic required

name&_outer_loop proc near
	loop_setup			;;Char offset fetching
	mov	ch,byte ptr clipped_font_height
	jmp	unrolled_entry_point

	even
name&_loop:
name&_loop_0:
	draw	<fetch_logic>
	add	di,dx
name&_DEST_ADJ = DRAW_ADJUST		;;Need to know if a stosb was used

if UNROLL_BY_8
name&_loop_7:
	draw	<fetch_logic>
	add	di,dx

name&_loop_6:
	draw	<fetch_logic>
	add	di,dx

name&_loop_5:
	draw	<fetch_logic>
	add	di,dx

name&_loop_4:
	draw	<fetch_logic>
	add	di,dx
endif

name&_loop_3:
	draw	<fetch_logic>
	add	di,dx

name&_loop_2:
	draw	<fetch_logic>
	add	di,dx

name&_loop_1:
	draw	<fetch_logic>
	add	di,dx
if UNROLL_BY_8
	sub	ch,8
else
	sub	ch,4
endif
	ja	name&_loop

name&_done_char:
	loop_logic name&_outer_loop
	jmp	ret_addr		;To caller

name&_outer_loop endp

name	endp
	endm
page

;--------------------------------Macro----------------------------------;
; o_spec_case
;
;	o_spec_case is the macro invoked to define the opaque special
;	case for the EGA.
;	
;	The special case loop will be unrolled by 8.
;
;	Usage:
;		o_spec_case name,logic,draw,ur
;	Where
;		name	is the name of the procedure being defined
;		logic	is the name of the macro which will define
;			the following macros:
;			    entry_logic - one shot entry preprocessing
;			    loop_setup	- character offset fetching
;			    fetch_logic - logic to fetch character bits
;			    loop_logic	- per char looping
;		draw	is the name of the macro to perform the actual
;			drawing of the bits
;-----------------------------------------------------------------------

o_spec_case	macro	name,logic,draw
if1
name&_DEST_ADJ = 0
endif
	logic				;;Define required macros

name&_disp_table label byte
	db	name&_loop_0-name&_loop
	db	name&_loop_1-name&_loop
	db	name&_loop_2-name&_loop
	db	name&_loop_3-name&_loop
if UNROLL_BY_8
	db	name&_loop_4-name&_loop
	db	name&_loop_5-name&_loop
	db	name&_loop_6-name&_loop
	db	name&_loop_7-name&_loop
endif

	public	name
name	proc	near
	mov	bl,byte ptr clipped_font_height
if UNROLL_BY_8
	and	bx,0007h
else
	and	bx,0003h
endif
	mov	bl,name&_disp_table[bx]
	add	bx,CodeOFFSET name&_loop
	mov	unrolled_entry_point,bx
	mov	dx,ss_next_scan 	;;Index to next scan of a bitmap
if name&_DEST_ADJ
	dec	dx
else
	nop
endif
	entry_logic			;;Any specific entry logic required

name&_outer_loop proc near
	loop_setup			;;Char offset fetching
	mov	ch,byte ptr clipped_font_height
	jmp	unrolled_entry_point

	even
name&_loop:
name&_loop_0:
	draw	<fetch_logic>
	add	di,dx
name&_DEST_ADJ = DRAW_ADJUST		;;Need to know if a stosb was used

if UNROLL_BY_8
name&_loop_7:
	draw	<fetch_logic>
	add	di,dx

name&_loop_6:
	draw	<fetch_logic>
	add	di,dx

name&_loop_5:
	draw	<fetch_logic>
	add	di,dx

name&_loop_4:
	draw	<fetch_logic>
	add	di,dx
endif

name&_loop_3:
	draw	<fetch_logic>
	add	di,dx

name&_loop_2:
	draw	<fetch_logic>
	add	di,dx

name&_loop_1:
	draw	<fetch_logic>
	add	di,dx
if UNROLL_BY_8
	sub	ch,8
else
	sub	ch,4
endif
	ja	name&_loop

name&_done_char:
	loop_logic name&_outer_loop
	jmp	ret_addr		;To caller

name&_outer_loop endp

name	endp
	endm
page

;--------------------------------Macro----------------------------------;
; t1_spec_case
;
;	t1_spec_case is the macro invoked to define the transparent
;	special case for the EGA.
;
;	The special case loop will be unrolled by 8.
;
;	Usage:
;		t_spec_case name,logic,draw,ur
;	Where
;		name	is the name of the procedure being defined
;		logic	is the name of the macro which will define
;			the following macros:
;			    entry_logic - one shot entry preprocessing
;			    loop_setup	- character offset fetching
;			    fetch_logic - logic to fetch character bits
;			    loop_logic	- per char looping
;		draw	is the name of the macro to perform the actual
;			drawing of the bits
;-----------------------------------------------------------------------

t1_spec_case	macro	name,logic,draw
if1
name&_DEST_ADJ = 0
endif
	logic				;;Define required macros

name&_disp_table label byte
	db	name&_loop_0-name&_loop
	db	name&_loop_1-name&_loop
	db	name&_loop_2-name&_loop
	db	name&_loop_3-name&_loop
if UNROLL_BY_8
	db	name&_loop_4-name&_loop
	db	name&_loop_5-name&_loop
	db	name&_loop_6-name&_loop
	db	name&_loop_7-name&_loop
endif

	public	name
name	proc	near
	mov	bl,byte ptr clipped_font_height
if UNROLL_BY_8
	and	bx,0007h
else
	and	bx,0003h
endif
	mov	bl,name&_disp_table[bx]
	add	bx,CodeOFFSET name&_loop
	mov	unrolled_entry_point,bx

	entry_logic			;;Any specific entry logic required

name&_outer_loop proc near
	loop_setup			;;Char offset fetching
	mov	ch,byte ptr clipped_font_height
	mov	dx,EGA_BASE + GRAF_DATA
	jmp	unrolled_entry_point

	even
name&_loop:
name&_loop_0:
	draw	<fetch_logic>
	add	di,SCREEN_W_BYTES - DRAW_ADJUST
name&_DEST_ADJ = DRAW_ADJUST		;;Need to know if a stosb was used

if UNROLL_BY_8
name&_loop_7:
	draw	<fetch_logic>
	add	di,SCREEN_W_BYTES - DRAW_ADJUST

name&_loop_6:
	draw	<fetch_logic>
	add	di,SCREEN_W_BYTES - DRAW_ADJUST

name&_loop_5:
	draw	<fetch_logic>
	add	di,SCREEN_W_BYTES - DRAW_ADJUST

name&_loop_4:
	draw	<fetch_logic>
	add	di,SCREEN_W_BYTES - DRAW_ADJUST
endif

name&_loop_3:
	draw	<fetch_logic>
	add	di,SCREEN_W_BYTES - DRAW_ADJUST

name&_loop_2:
	draw	<fetch_logic>
	add	di,SCREEN_W_BYTES - DRAW_ADJUST

name&_loop_1:
	draw	<fetch_logic>
	add	di,SCREEN_W_BYTES - DRAW_ADJUST
if UNROLL_BY_8
	sub	ch,8
else
	sub	ch,4
endif
	ja	name&_loop

name&_done_char:
	loop_logic name&_outer_loop
	jmp	ret_addr		;To caller

name&_outer_loop endp

name	endp
	endm
page

;--------------------------------Macro----------------------------------;
; t2_spec_case
;
;	t_spec_case is the macro invoked to define the transparent
;	special case for the EGA.
;
;	The special case loop will be unrolled by 8.
;
;	Usage:
;		t_spec_case name,logic,draw,ur
;	Where
;		name	is the name of the procedure being defined
;		logic	is the name of the macro which will define
;			the following macros:
;			    entry_logic - one shot entry preprocessing
;			    loop_setup	- character offset fetching
;			    fetch_logic - logic to fetch character bits
;			    loop_logic	- per char looping
;		draw	is the name of the macro to perform the actual
;			drawing of the bits
;-----------------------------------------------------------------------

t2_spec_case	macro	name,logic,draw
if1
name&_DEST_ADJ = 0
endif
	logic				;;Define required macros

name&_disp_table label byte
	db	name&_loop_0-name&_loop
	db	name&_loop_1-name&_loop
	db	name&_loop_2-name&_loop
	db	name&_loop_3-name&_loop
if UNROLL_BY_8
	db	name&_loop_4-name&_loop
	db	name&_loop_5-name&_loop
	db	name&_loop_6-name&_loop
	db	name&_loop_7-name&_loop
endif

	public	name
name	proc	near
	mov	bl,byte ptr clipped_font_height
if UNROLL_BY_8
	and	bx,0007h
else
	and	bx,0003h
endif
	mov	bl,name&_disp_table[bx]
	add	bx,CodeOFFSET name&_loop
	mov	unrolled_entry_point,bx

	entry_logic			;;Any specific entry logic required

name&_outer_loop proc near
	loop_setup			;;Char offset fetching
	mov	ch,byte ptr clipped_font_height
	mov	dx,EGA_BASE + GRAF_DATA
	jmp	unrolled_entry_point

	even
name&_loop:
name&_loop_0:
	draw	<fetch_logic>
	add	di,SCREEN_W_BYTES - DRAW_ADJUST
name&_DEST_ADJ = DRAW_ADJUST		;;Need to know if a stosb was used

if UNROLL_BY_8
name&_loop_7:
	draw	<fetch_logic>
	add	di,SCREEN_W_BYTES - DRAW_ADJUST

name&_loop_6:
	draw	<fetch_logic>
	add	di,SCREEN_W_BYTES - DRAW_ADJUST

name&_loop_5:
	draw	<fetch_logic>
	add	di,SCREEN_W_BYTES - DRAW_ADJUST

name&_loop_4:
	draw	<fetch_logic>
	add	di,SCREEN_W_BYTES - DRAW_ADJUST
endif

name&_loop_3:
	draw	<fetch_logic>
	add	di,SCREEN_W_BYTES - DRAW_ADJUST

name&_loop_2:
	draw	<fetch_logic>
	add	di,SCREEN_W_BYTES - DRAW_ADJUST

name&_loop_1:
	draw	<fetch_logic>
	add	di,SCREEN_W_BYTES - DRAW_ADJUST
if UNROLL_BY_8
	sub	ch,8
else
	sub	ch,4
endif
	ja	name&_loop

name&_done_char:
	long_loop_logic name&_outer_loop
	jmp	ret_addr		;To caller

name&_outer_loop endp

name	endp
	endm
page

;--------------------------------Macro----------------------------------;
; general_case
;
;	general_case is the macro invoked to define a generic handler.
;	It must be passed a call through ss_draw or ss_draw_clipped
;	for the drawing logic.
;
;	Usage:
;		general_case name,logic,draw
;	Where
;		name	is the name of the procedure being defined
;		logic	is the name of the macro which will define
;			the following macros:
;			    entry_logic - one shot entry preprocessing
;			    loop_setup	- character offset fetching
;			    fetch_logic - logic to fetch character bits
;			    loop_logic	- per char looping logic
;		draw	is the name of the macro to perform the actual
;			drawing of the bits
;
;-----------------------------------------------------------------------;

general_case macro   name,logic,draw

	logic				;;Define required macros

	public	name
name	proc	near
	entry_logic			;;Any specific entry logic required
	mov	dx,CodeOFFSET name&_loop

name&_outer_loop:
	loop_setup			;;Char offset fetching
	mov	ch,byte ptr clipped_font_height
	inc	ch			;;For entry into the loop

name&_loop:
	dec	ch
	jz	name&_done_char
	draw	<fetch_logic>

name&_done_char:
	loop_logic name&_outer_loop
	jmp	ret_addr		;To caller

name	endp
	endm
page

sBegin	Code
assumes cs,Code

;-----------------------------------------------------------------------;
; SmartFix
;
; Entry:
;	stack frame as per strblt
; Returns:
;
; Error Returns:
;
; Registers Destroyed:
;	AX,BX,CX,DX,SI,DI,DS,ES,FLAGS
; Registers Preserved:
;	BP
; Calls:
;
; History:
;  Mon 03-Aug-1987 16:13:24 -by-  Walt Moore [waltm]
; rewrote it
;  Wed Feb 11, 1987 02:55:13a	-by-  Tony Pisculli	[tonyp]
; wrote it
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,nothing
	assumes ss,StrStuff

define_frame	fixed_pitch_strblt
cBegin	<nogen>

	cmp	clipped_font_height,255 ;Height is kept in a byte register
	ja	use_proportional_code	;Too big, pass it to proportional code

	xor	si,si			;# chars to bias string start by
	mov	di,x			;X will be used many times
	mov	cx,di			;Set CL = phase (starting X mod 8)
	and	cx,7			;  and CH = smart_flags = 0
	mov	phase,cx		;Save phase for later

	mov	dx,di			;Assume lhs is starting X
	mov	ax,clip.left
	cmp	ax,dx			;If clip.left < X
	jle	only_one_in_first	;  then no left side clipping
	mov	dx,ax			;Set new lhs
	sub	ax,di			;Compute number of complete bytes
	shiftr	ax,3			;  clipped off the fron tof the string
	xchg	ax,si			;SI is bias to string start
	mov	al,dl			;If lhs-phase < phase
	and	al,7			;  then two sources are required
	cmp	al,cl			;  for the first destination byte
	jge	only_one_in_first
	or	ch,TWO_SOURCES_IN_FIRST

only_one_in_first:
	mov	bx,count
	test	bh,11100000b		;If any of these bits are set, we'll
	jnz	use_proportional_code	;  overflow on shifting!
	shiftl	bx,3			;Compute rhs of string
	add	bx,di

	mov	ax,clip.right		;If rhs =< clip.right
	cmp	bx,ax			;  then no clipping needed
	jle	only_one_in_last
	sub	bx,ax			;Compute complete bytes clipped
	shiftr	bx,3			;  and remove them from the count
	sub	count,bx		;  of characters to display
	mov	bx,ax			;BX = rhs = clip.right
	and	al,7			;If rhs-phase > phase
	cmp	al,cl			;  then two sources will be required
	jle	only_one_in_last	;  for the last byte
	or	ch,TWO_SOURCES_IN_LAST

only_one_in_last:
	mov	smart_flags,ch
	mov	string_start_bias,si
	call	comp_byte_interval	;BX,DX are parameters
	jnc	got_the_interval
	jmp	exit_smart_font 	;Interval doesn't show

use_proportional_code:
	jmp	build_string		;Default to using proportional code

got_the_interval:
	mov	scan_start,di
	mov	left_clip_mask,al
	mov	right_clip_mask,ah

	mov	ax,count		;Adjust count for the complete
	sub	ax,string_start_bias	;  chars clipped on lhs
	mov	cx,ax
	mov	count,si		;Set inner loop count
	add	ax,ax			;If not enough stack space for the
	add	ax,ss:stack_top 	;  string, pass it to the
	add	ax,STACK_SLOP		;  proportional code (20 for slop)
	cmp	ax,sp
	ja	use_proportional_code

	lds	si,lp_string		;--> last character of the string
	assumes ds,nothing		;  which will be visible
	add	si,string_start_bias
	add	si,cx
	dec	si
	std				;!!
	mov	es,seg_lp_font
	assumes es,FontSeg
	jmp	short push_char_offsets


;-----------------------------------------------------------------------;
;
;	push_font_bits
;
;	This loop is used to push the offset of each character
;	onto the stack.  The offset accounts for any clipping
;	which may have occured.  Any character out of range will
;	have the default character's offset pushed for it.
;
;	Currently:
;		DS:SI --> current character in the string
;		ES:    =  font segment
;		CX     =  number of characters to process
;
;-----------------------------------------------------------------------;


pco_bad_char:
	mov	al,lfd.default_char	;Character was out of range,
	jmp	short pco_good_char


	public	push_char_offsets
push_char_offsets:
	mov	di,amt_clipped_on_top	;Adjustment for any clipping
	mov	dl,lfd.first_char	;First valid character
	mov	dh,lfd.last_char	;Last valid character



;	It is possible for our code to indicate that two characters
;	are required for the first byte, when in fact only one
;	character is left in the string.  We're going to cheat
;	by pushing the offset of the null character.  If we use it,
;	the fine, and if we don't, we'll be restoring the old SP
;	so it will be cleaned off the stack.

	mov	clear_stack,sp
	push	null_char_offset

pco_next_char:
	lodsb				;Get next character
	sub	al,dl			;Bias by first valid
	cmp	al,dh			;If out of range
	ja	pco_bad_char		;  go get the default character

pco_good_char:
	xor	ah,ah
	xchg	ax,bx
	shiftl	bx,2			;Index into width/offset table
	mov	bx,wptr fsCharOffset[bx][PROP_OFFSET]
	add	bx,di			;Adjust pointer for any clipping
	push	bx			;Save offset
	loop	pco_next_char
	cld


;-----------------------------------------------------------------------;
;
;	All the character offsets have been pushed onto the stack.
;	Compute the starting address of the first character and
;	dtart drawing characters (that is the reason we came here).
;
;-----------------------------------------------------------------------;

	call	preset_fix_text
	les	di,lp_surface
	assumes	es,nothing
	mov	ax,text_bbox.top
	mul	next_scan
	add	di,ax
	add	di,scan_start
	mov	ds,seg_lp_font
	assumes ds,FontSeg

	mov	cx,phase		;CL = phase
	or	cl,cl
	jnz	phase_non_0


;-----------------------------------------------------------------------;
;	The destination starts on a byte boundary.  A single source
;	character is all which is needed for each destination.	No
;	rotation will be required for this case.
;-----------------------------------------------------------------------;

phase_0_do_first:
	mov	al,left_clip_mask	;If the left clip mask is non-zero
	or	al,al			;  then a partial byte will have to
	jz	phase_0_do_inner	;  be processed on the lhs
	mov	ss_clip_mask,al 	;Generic handlers require this
	mov	ret_addr,CodeOFFSET phase_0_do_inner
	char_check
	pop	si			;Offset to bits of first character
	mov	al,OC_ONE_IN_FIRST
	or	excel,RES_EGA_INNER
	jmp	vect_one_in_first

phase_0_do_inner:
	cmp	count,0 		;Inner loop will exist only if count
	je	phase_0_do_last 	;  is non-zero
	mov	ret_addr,CodeOFFSET phase_0_do_last
	mov	ss_clip_mask,0FFh
	jmp	vect_one_in_middle

phase_0_do_last:
	mov	al,right_clip_mask	;If the right clip mask is non-zero
	or	al,al			;  then a partial byte will have to
	jz	fixed_text_clean_up	; be processed on rhs
	mov	ss_clip_mask,al
	mov	ret_addr,CodeOFFSET fixed_text_clean_up
	char_check
	pop	si			;Offset to bits of last character
	mov	al,OC_ONE_IN_LAST
	jmp	vect_one_in_last


;-----------------------------------------------------------------------;
;	The destination doesn't start on a byte boundary.  Two source
;	characters will be needed for each destination.  Rotation of
;	the sources will be required for this case.  Either one or two
;	source characters will be required for the first and last bytes,
;	depending on the clipping mask.
;-----------------------------------------------------------------------;

phase_non_0:
	char_check
	pop	si			;Offset to first character's bits
	mov	al,left_clip_mask	;If the left clip mask is non-zero
	or	al,al			;  then a partial byte will have to
	jz	phase_non_0_do_inner	;  be processed on the lhs
	mov	ss_clip_mask,al 	;Generic handlers require this
	mov	ret_addr,CodeOFFSET phase_non_0_do_inner
	or	excel,RES_EGA_INNER
	test	smart_flags,TWO_SOURCES_IN_FIRST
	jz	phase_non_0_one_in_first
	mov	al,OC_TWO_IN_FIRST
	jmp	vect_two_in_first
phase_non_0_one_in_first:
	mov	al,OC_ONE_IN_FIRST
	jmp	vect_one_in_first

phase_non_0_do_inner:
	cmp	count,0 		;Inner loop will exist only if count
	je	phase_non_0_do_last	;  is non-zero
	mov	ret_addr,CodeOFFSET phase_non_0_do_last
	mov	ss_clip_mask,0FFh
	jmp	vect_two_in_middle

phase_non_0_do_last:
	mov	al,right_clip_mask	;If the right clip mask is non-zero
	or	al,al			;  then a partial byte will have to
	jz	fixed_text_clean_up	; be processed on rhs
	mov	ss_clip_mask,al
	mov	ret_addr,CodeOFFSET fixed_text_clean_up
	test	smart_flags,TWO_SOURCES_IN_LAST
	jz	phase_non_0_one_in_last
	mov	al,OC_TWO_IN_LAST
	jmp	vect_two_in_last
phase_non_0_one_in_last:
	mov	al,OC_ONE_IN_LAST
	jmp	vect_one_in_last

fixed_text_clean_up:
	mov	sp,clear_stack		;Restore incase null char not used

exit_smart_font:

	ret_near

cEnd	<nogen>
page

;--------------------------Private-Routine------------------------------;
; ega_oc_outer_loop
;
;   Overall control logic for opaque clipped text to the EGA.
;
;   For fixed pitch text, this function supersedes the clipped bit
;   gathering functions (xxx_one_in_first, xxx_two_in_last, etc.).  In
;   either case, it sets up two passes through the appropriate generic
;   bit gathering functions.
;
;   Since the drawing function changes between passes, ss_draw_clipped
;   must be set here as needed.
;
; Entry:
;	AL     =  index into ega_oc_dispatch_table
;	CL     =  phase
;	DS:SI --> font bits
;	ES:DI --> destination byte (ES = ScreenSelector)
;	ret_addr = return address offset
; Returns:
;	ES:DI  --> destination
; Error Returns:
;	None
; Registers Preserved:
;	CX,DX,DI,DS,ES
; Registers Destroyed:
;	AX,BX,SI,BP
; Calls:
;	None
; History:
;	Sun 22-Aug-1987 00:28:00 -by-  Bob Grudem [bobgru]
;	Wrote it.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,nothing
	assumes ss,StrStuff

	public	ega_oc_outer_loop_fix_two
	public	ega_oc_outer_loop_fix

ega_oc_outer_loop_fix_two	proc	near

;	The two_in_cell type drawing functions pop the stack for the
;	next character offset.  Since we must save registers between
;	passes, the second char offset must come off the stack, and
;	go back on after registers have been saved.  Upon return from
;	the lower level code, the stack is ready to restore the saved
;	registers.

	pop	ega_oc_saved_data

ega_oc_outer_loop_fix:

	mov	bx,ret_addr
	mov	ret_addr_2,bx

	mov	ret_addr,CodeOFFSET ega_oc_outer_loop_ret_1

	cbw
	xchg	bx,ax
	mov	ss_draw_clipped,CodeOFFSET ega_opaque_clip_1_fix

	push	bx			;save registers for next pass
	push	cx
	push	si
	push	di

	call	setup_ega_opaque_clip_magic

	test	bl,OC_MASK_TWO_CHAR
	errnz	<OC_MASK_TWO_CHAR and 0FF00h>
	jz	ega_oc_outer_loop_do_1

	push	ega_oc_saved_data	;if two_in_cell, put back data

ega_oc_outer_loop_do_1:
	add	bx,CodeOFFSET ega_oc_dispatch_table
	jmp	cs:[bx] ;do first pass
;	jmp	wptr cs:ega_oc_dispatch_table[bx]

ega_oc_outer_loop_ret_1:
	mov	dx,EGA_BASE + SEQ_DATA
	mov	al,bptr colors[BACKGROUND]
	out	dx,al

	pop	di			;restore registers for second pass
	pop	si
	pop	cx
	pop	bx


;	The next block of code determines if the second pass is
;	necessary.
;
;	Note that the EGA has been programmed to allow writing only to
;	the planes composing the background color. Since we're writing
;	opaque text, all planes in the background color also in the
;	foreground have been set by the first pass.  The second
;	pass cleans up the background planes not in the foreground
;	color.  If there aren't any, then skip the second pass.

	mov	ax,ss_colors
	xor	al,ah			;determine mismatching bits
	and	al,ah			;isolate those in the bk color
	jz	ega_oc_outer_loop_skip_pass_2

	mov	ret_addr,CodeOFFSET ega_oc_outer_loop_ret_2
	sub	ss_draw_clipped,2
	errnz	<CodeOFFSET ega_opaque_clip_1_fix - CodeOFFSET ega_opaque_clip_2_fix - 2>
	test	bl,OC_MASK_TWO_CHAR
	errnz	<OC_MASK_TWO_CHAR and 0FF00h>
	jz	ega_oc_outer_loop_do_2

	push	ega_oc_saved_data	;if two_in_cell, put back data

ega_oc_outer_loop_do_2:
	add	bx,CodeOFFSET ega_oc_dispatch_table
	jmp	cs:[bx]			;do second pass
;	jmp	wptr cs:ega_oc_dispatch_table[bx]

ega_oc_outer_loop_ret_2:
	test	excel,RES_EGA_INNER	;is there a middle part to string?
	jz	ega_oc_outer_loop_exit	;if no, skip EGA register setup
	call	set_ega_opaque_mode	;else, prepare EGA for full opaque
	and	excel,not RES_EGA_INNER	;prevent this at end of string

ega_oc_outer_loop_exit:
	jmp	ret_addr_2


;	Update ES:DI as would have been done by second pass, then check
;	to see if EGA reprogramming is necessary for a non-clipped section
;	of opaque text.

ega_oc_outer_loop_skip_pass_2:
	test	bl,OC_MASK_TWO_CHAR
	errnz	<OC_MASK_TWO_CHAR and 0FF00h>
	jz	ega_oc_outer_loop_si_ok
	mov	si,ega_oc_saved_data	;if two_in_cell, put back data

ega_oc_outer_loop_si_ok:
	inc	di			;update di for whoever follows
	jmp	short ega_oc_outer_loop_ret_2


ega_oc_outer_loop_fix_two	endp
	page

;--------------------------Private-Routine------------------------------;
;   ega_opaque_clip_2_fix
;   ega_opaque_clip_1_fix
;
;   Device drawing functions for:
;
;	opaque, clipped
;
;   Two passes are required for this mode of text output.  Label
;   ega_opaque_clip_x is the drawing function for pass x.
;
; Entry:
;	AL = character to output
;	ES:DI --> destination byte
; Returns:
;	ES:DI --> same byte, next scan
; Error Returns:
;	None
; Registers Preserved:
;	BX,CX,DX,SI,DI,DS,ES,BP
; Registers Destroyed:
;	AX
; Calls:
;	None
; History:
;	Wed 22-Jul-1987 17:54:46 -by-  Walt Moore [waltm]
;	Wrote it.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


	assumes ds,nothing
	assumes es,nothing
	assumes ss,StrStuff

	public	ega_opaque_clip_2_fix
	public	ega_opaque_clip_1_fix
ega_opaque_clip_2_fix:
	not	al
ega_opaque_clip_1_fix:
	xchg	al,es:[di]

DRAW_ADJUST	= 0			;STOSB is not used
	upd_dev <ret>			;Will generate the ret
page

;--------------------------Private-Routine------------------------------;
; ega_opaque_non_clip_fix:
;
;   Standard device drawing functions for:
;
;	opaque, black on white, non-clipped
;	opaque, white on black, non-clipped
;
;	EGA opaque mode (color combination does not matter)
;
; Entry:
;	AL = character to output
;	ES:DI --> destination byte
; Returns:
;	ES:DI --> same byte, next scan
; Error Returns:
;	None
; Registers Preserved:
;	BX,CX,DX,SI,DI,DS,ES,BP
; Registers Destroyed:
;	AX
; Calls:
;	None
; History:
;	Wed 22-Jul-1987 17:54:46 -by-  Walt Moore [waltm]
;	Wrote it.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,nothing
	assumes ss,StrStuff

ega_opaque_non_clip_fix:
	stosb

DRAW_ADJUST	= 1			;STOSB is used
	upd_dev <ret>			;Will generate the ret
page

;--------------------------Private-Routine------------------------------;
;   ega_trans_clip_fix
;   ega_trans_non_clip_fix
;
;   Drawing routines for EGA, transparent mode, clipped and non-clipped.
;
; Entry:
;	AL = character to output
;	ES:DI --> destination byte
; Returns:
;	ES:DI --> same byte, next scan
; Error Returns:
;	None
; Registers Preserved:
;	BX,CX,DX,SI,DI,DS,ES,BP
; Registers Destroyed:
;	AX
; Calls:
;	None
; History:
;	Wed 22-Jul-1987 17:54:46 -by-  Walt Moore [waltm]
;	Wrote it.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,nothing
	assumes ss,StrStuff

ega_trans_clip_fix:
	and	al,ss_clip_mask
if SPECIAL_CASE_DEV_TNC eq 1
	push	dx
	mov	dx,EGA_BASE + GRAF_DATA
	out	dx,al
	pop	dx
	xchg	al,es:[di]
DRAW_ADJUST = 0				;stosb is not used
	upd_dev	<ret>			;will generate ret
endif

ega_trans_non_clip_fix:
if SPECIAL_CASE_DEV_TNC eq 1
else
	push	dx
	mov	dx,EGA_BASE + GRAF_DATA
	out	dx,al
	pop	dx
	xchg	al,es:[di]
DRAW_ADJUST = 0				;stosb is not used
	upd_dev	<ret>			;will generate ret
endif
page

;--------------------------Private-Routine------------------------------;
; opaque_white_on_white_clip
; trans_white_clip
; trans_white
;
;   Standard bitmap drawing functions for:
;
;	opaque, white on white, clipped
;	transparent, white, clipped
;	transparent, white, non-clipped
;
; Entry:
;	AL = character to output
;	ES:DI --> destination byte
;	DX = return address
; Returns:
;	ES:DI --> same byte, next scan
; Error Returns:
;	None
; Registers Preserved:
;	BX,CX,DX,SI,DI,DS,ES,BP
; Registers Destroyed:
;	AX
; Calls:
;	None
; History:
;	Wed 22-Jul-1987 17:54:46 -by-  Walt Moore [waltm]
;	Wrote it.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,nothing
	assumes ss,StrStuff

opaque_white_on_white_clip:
	mov	al,0FFh

trans_white_clip:
	and	al,ss_clip_mask

trans_white:
	or	es:[di],al

DRAW_ADJUST	= 0			;STOSB isn't used
	upd_bm				;Will generate the ret
page

;--------------------------Private-Routine------------------------------;
; opaque_black_on_black_clip
; trans_black_clip
; trans_black
;
;   Standard bitmap drawing functions for:
;
;	opaque, black on black, clipped
;	transparent, black, clipped
;	transparent, black, non-clipped
;
; Entry:
;	AL = character to output
;	ES:DI --> destination byte
;	DX = return address
; Returns:
;	ES:DI --> same byte, next scan
; Error Returns:
;	None
; Registers Preserved:
;	BX,CX,DX,SI,DI,DS,ES,BP
; Registers Destroyed:
;	AX
; Calls:
;	None
; History:
;	Wed 22-Jul-1987 17:54:46 -by-  Walt Moore [waltm]
;	Wrote it.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,nothing
	assumes ss,StrStuff

opaque_black_on_black_clip:
	mov	al,0FFh

trans_black_clip:
	and	al,ss_clip_mask

trans_black:
	not	al
	and	es:[di],al

DRAW_ADJUST	= 0			;STOSB isn't used
	upd_bm				;Will generate the ret
page

;--------------------------Private-Routine------------------------------;
; opaque_black_on_white
; opaque_white_on_black
;
;   Standard bitmap drawing functions for:
;
;	opaque, black on white, non-clipped
;	opaque, white on black, non-clipped
;
; Entry:
;	AL = character to output
;	ES:DI --> destination byte
;	DX = return address
; Returns:
;	ES:DI --> same byte, next scan
; Error Returns:
;	None
; Registers Preserved:
;	BX,CX,DX,SI,DI,DS,ES,BP
; Registers Destroyed:
;	AX
; Calls:
;	None
; History:
;	Wed 22-Jul-1987 17:54:46 -by-  Walt Moore [waltm]
;	Wrote it.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,nothing
	assumes ss,StrStuff

opaque_black_on_white:
	not	al

opaque_white_on_black:
	stosb

DRAW_ADJUST	= 1			;STOSB is used
	upd_bm				;Will generate the ret
page

;--------------------------Private-Routine------------------------------;
; opaque_black_on_white_clip
; opaque_white_on_black_clip
;
;   Standard bitmap drawing functions for:
;
;	opaque, black on white, clipped
;	opaque, white on black, clipped
;
; Entry:
;	AL = character to output
;	ES:DI --> destination byte
;	DX = return address
; Returns:
;	ES:DI --> same byte, next scan
; Error Returns:
;	None
; Registers Preserved:
;	BX,CX,DX,SI,DI,DS,ES,BP
; Registers Destroyed:
;	AX
; Calls:
;	None
; History:
;	Wed 22-Jul-1987 17:54:46 -by-  Walt Moore [waltm]
;	Wrote it.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,nothing
	assumes ss,StrStuff

opaque_black_on_white_clip:
	not	al

opaque_white_on_black_clip:
	mov	ah,ss_clip_mask
	and	al,ah
	not	ah
	and	ah,es:[di]
	or	al,ah
	stosb

DRAW_ADJUST	= 1			;STOSB is used
	upd_bm				;Will generate the ret
page

;--------------------------Private-Routine------------------------------;
; opaque_white_on_white
; opaque_black_on_black
;
;   Standard bitmap drawing functions for:
;
;	opaque, white on white, non-clipped
;	opaque, black on black, non-clipped
;
; Entry:
;	AL = character to output
;	ES:DI --> destination byte
;	DX = return address
; Returns:
;	ES:DI --> same byte, next scan
; Error Returns:
;	None
; Registers Preserved:
;	BX,CX,DX,SI,DI,DS,ES,BP
; Registers Destroyed:
;	AX
; Calls:
;	None
; History:
;	Wed 22-Jul-1987 17:54:46 -by-  Walt Moore [waltm]
;	Wrote it.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,nothing
	assumes ss,StrStuff

opaque_white_on_white:
	mov	al,0FFh
	jmpnext

opaque_black_on_black:
	xor	al,al
	jmpnext stop
	stosb

DRAW_ADJUST	= 1			;STOSB is used
	upd_bm				;Will generate the ret
page


;-----------------------------------------------------------------------;
;
;	Define the drawing logic tables.  These tables are used to
;	fetch the address of the output function for the combination
;	of foreground/background colors, opaque/transparent mode,
;	and device/bitmap.
;
;	The tables are indexed as follows:
;
;	  DEV/BM O/T FG BK  0;
;	    |	  |   |  |
;	    |	  |   |   ----------  background color (0/1)
;	    |	  |   |
;	    |	  |    -------------  foreground color (0/1)
;	    |	  |
;	    |	   -----------------  0 if transparent, 1 if opaque
;	    |
;	     ------------------------ 0 if a bitmap, 1 if the device
;-----------------------------------------------------------------------;

MASK_DEVBM	equ	00010000b
MASK_OT		equ	00001000b
MASK_FG		equ	00000100b
MASK_BK		equ	00000010b

MASK_DEV_ONC	equ	MASK_DEVBM or MASK_OT	;MASK_BK, MASK_FG wildcards
MASK_DEV_TNC	equ	MASK_DEVBM		;MASK_BK, MASK_FG wildcards
MASK_DEV_OC	equ	MASK_DEVBM or MASK_OT	;MASK_BK, MASK_FG wildcards
MASK_DEV_TC	equ	MASK_DEVBM		;MASK_BK, MASK_FG wildcards

MASK_BM_OBWNC	equ	MASK_OT or MASK_BK
MASK_BM_OWBNC	equ	MASK_OT or MASK_FG
MASK_BM_TBNC	equ	0			;MASK_BK is a wildcard
MASK_BM_TWNC	equ	MASK_FG			;MASK_BK is a wildcard


clipped_drawing_functions label word

	dw	CodeOFFSET  bm_trans_color_fix
	dw	CodeOFFSET  bm_trans_color_fix
	dw	CodeOFFSET  bm_trans_color_fix
	dw	CodeOFFSET  bm_trans_color_fix
	dw	CodeOFFSET  bm_opaque_color_fix
	dw	CodeOFFSET  bm_opaque_color_fix
	dw	CodeOFFSET  bm_opaque_color_fix
	dw	CodeOFFSET  bm_opaque_color_fix
	dw	CodeOFFSET ega_trans_clip_fix
	dw	CodeOFFSET ega_trans_clip_fix
	dw	CodeOFFSET ega_trans_clip_fix
	dw	CodeOFFSET ega_trans_clip_fix
	dw	4 dup (0)		;these are a special case


non_clipped_drawing_functions label word

	dw	CodeOFFSET  bm_trans_color_fix
	dw	CodeOFFSET  bm_trans_color_fix
	dw	CodeOFFSET  bm_trans_color_fix
	dw	CodeOFFSET  bm_trans_color_fix
	dw	CodeOFFSET  bm_opaque_color_fix
	dw	CodeOFFSET  bm_opaque_color_fix
	dw	CodeOFFSET  bm_opaque_color_fix
	dw	CodeOFFSET  bm_opaque_color_fix
	dw	CodeOFFSET ega_trans_non_clip_fix
	dw	CodeOFFSET ega_trans_non_clip_fix
	dw	CodeOFFSET ega_trans_non_clip_fix
	dw	CodeOFFSET ega_trans_non_clip_fix
	dw	CodeOFFSET ega_opaque_non_clip_fix
	dw	CodeOFFSET ega_opaque_non_clip_fix
	dw	CodeOFFSET ega_opaque_non_clip_fix
	dw	CodeOFFSET ega_opaque_non_clip_fix


mono_non_clipped_drawing_functions label word

	dw	CodeOFFSET  trans_black
	dw	CodeOFFSET  trans_black
	dw	CodeOFFSET  trans_white
	dw	CodeOFFSET  trans_white
	dw	CodeOFFSET  opaque_black_on_black
	dw	CodeOFFSET  opaque_black_on_white
	dw	CodeOFFSET  opaque_white_on_black
	dw	CodeOFFSET  opaque_white_on_white
page


;	The table ega_oc_dispatch_table is used by ega_oc_outer_loop
;	to determine which case to call for each pass at drawing text.


ega_oc_dispatch_table	label	word
	dw	CodeOFFSET gen_one_in_first
	dw	CodeOFFSET gen_two_in_first
	dw	CodeOFFSET gen_one_in_last
	dw	CodeOFFSET gen_two_in_last


;--------------------------Private-Routine------------------------------;
; preset_fix_text
;
;  Set any frame variables and stack locations (in the StrStuff segment)
;  required to output text with the current attributes.
;
; Entry:
;	SS = StrStuff
; Returns:
;	None
; Error Returns:
;	None
; Registers Preserved:
;	DX,SI,DI,BP,DS
; Registers Destroyed:
;	AX,BX,CX,ES,FLAGS
; Calls:
;	None
; History:
;	Tue 04-Aug-1987 18:37:26 -by-  Walt Moore [waltm]
;	Wrote it.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,nothing
	assumes ss,StrStuff

	public	preset_fix_text
preset_fix_text proc	near

	mov	ss_p_frame,bp
	mov	cx,next_scan
	mov	ss_next_scan,cx
	mov	cx,colors
	mov	ss_colors,cx

;	Accumulate foreground/background colors, opaque/transparent mode,
;	and device/bitmap to determine which drawing functions will be
;	used.

	mov	bl,accel
	mov	ah,excel
	and	bx,IS_OPAQUE		;BL = 0000000 O/T
	errnz	IS_OPAQUE-00000001
;	mov	cx,colors
	shr	cl,1
	rcl	bl,1			;BL = 000000 O/T FG
	errnz	FOREGROUND
	shr	ch,1			;BL = 00000 O/T FG BK
	rcl	bl,1
	errnz	BACKGROUND-FOREGROUND-1
	and	ah,IS_DEVICE
	or	bl,ah			;BL = 0000 DEV/BM O/T FG BK
	errnz	IS_DEVICE-00001000b
	shl	bx,1			;BX = 00000000 000 DEV/BM O/T FG BK 0


;	All clipped text will use the generic handlers, though text
;	destined for the display needs special consideration, as two
;	passes at drawing may be required.

	mov	ax,bx			;check for EGA,opaque,clip
	and	ax,MASK_DEV_OC
	cmp	ax,MASK_DEV_OC
	jne	preset_fix_text_def_clip_fun

	mov	ax,CodeOFFSET ega_oc_outer_loop_fix ;special case
	mov	cx,CodeOFFSET ega_oc_outer_loop_fix_two
	mov	vect_one_in_first,ax
	mov	vect_two_in_first,cx
	mov	vect_one_in_last,ax
	mov	vect_two_in_last,cx
	jmp	short preset_fix_text_set_clip_draw_fun

preset_fix_text_def_clip_fun:
	mov	vect_one_in_first,CodeOFFSET gen_one_in_first
	mov	vect_two_in_first,CodeOFFSET gen_two_in_first
	mov	vect_one_in_last,CodeOFFSET  gen_one_in_last
	mov	vect_two_in_last,CodeOFFSET  gen_two_in_last

preset_fix_text_set_clip_draw_fun:
	mov	ax,clipped_drawing_functions[bx]
	mov	ss_draw_clipped,ax
	mov	ax,next_scan
	mov	ss_next_scan,ax


;	Set any special case middle byte routines


if SPECIAL_CASE_DEV_ONC eq 1
	mov	ax,bx
	and	al,MASK_DEV_ONC
	cmp	al,MASK_DEV_ONC
	errnz	<MASK_DEV_ONC and 0FF00h>
	jne	preset_fix_text_not_dev_onc

	mov	ax,CodeOFFSET dev_onc_one_in_cell
	mov	cx,CodeOFFSET dev_onc_two_in_cell
	jmp	preset_fix_text_finish

preset_fix_text_not_dev_onc:
endif

if SPECIAL_CASE_DEV_TNC eq 1
	mov	ax,bx
	and	al,MASK_DEV_TNC
	cmp	al,MASK_DEV_TNC
	errnz	<MASK_DEV_TNC and 0FF00h>
	jne	preset_fix_text_not_dev_tnc

	mov	ax,CodeOFFSET dev_tnc_one_in_cell
	mov	cx,CodeOFFSET dev_tnc_two_in_cell
	jmp	preset_fix_text_finish

preset_fix_text_not_dev_tnc:
endif

if SPECIAL_CASE_BM_OBWNC eq 1
	mov	ax,CodeOFFSET bm_obwnc_one_in_cell
	mov	cx,CodeOFFSET bm_obwnc_two_in_cell
	cmp	bl,INDEX_OBW
	je	preset_fix_text_finish
endif


if SPECIAL_CASE_BM_TBNC eq 1
	mov	ax,CodeOFFSET bm_tbnc_one_in_cell
	mov	cx,CodeOFFSET bm_tbnc_two_in_cell
	cmp	bl,INDEX_TB
	je	preset_fix_text_finish
	cmp	bl,INDEX_TB_ALT
	je	preset_fix_text_finish
endif

	mov	ax,mono_non_clipped_drawing_functions[bx]

	cmp	num_planes,1		;assumes color display
	je	preset_fix_text_set_nc_draw_fun ;if mono bitmap, jump

	mov	ax,non_clipped_drawing_functions[bx]

preset_fix_text_set_nc_draw_fun:
	mov	ss_draw,ax
	mov	ax,CodeOFFSET gen_one_in_cell
	mov	cx,CodeOFFSET gen_two_in_cell

preset_fix_text_finish:

	mov	vect_one_in_middle,ax
	mov	vect_two_in_middle,cx

	test	bl,MASK_DEVBM
	errnz	<MASK_DEVBM and 0FF00h>
	jz	preset_fix_text_exit


;	These last initializations are only for the EGA.

	test	bl,MASK_OT
	errnz	<MASK_OT and 0FF00h>
	jnz	preset_fix_text_opaque
	call	preset_fix_ega_trans_mode
	jmp	short preset_fix_text_exit

preset_fix_text_opaque:
	call	preset_fix_ega_opaque_mode

preset_fix_text_exit:
	ret

preset_fix_text endp
page

;--------------------------Private-Routine------------------------------;
; preset_fix_ega_opaque_mode
;
;  Do any one-time initialization of the EGA hardware for opaque text.
;
; Entry:
;	BP = local variable frame
;	SS = StrStuff
; Returns:
;	None
; Error Returns:
;	None
; Registers Preserved:
;	BX,CX,SI,DI,BP,DS
; Registers Destroyed:
;	AX,DX,ES,FLAGS
; Calls:
;	None
; History:
;	Tue 25-Aug-1987 17:00:00 -by-  Bob Grudem [bobgru]
;	Made into subroutine.
;	Late spring, 1987        -by-  Tony Pisculli [tonyp]
;	Wrote it.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,nothing
	assumes ss,StrStuff

preset_fix_ega_opaque_mode	proc	near

	mov	ax,ScreenSelector
	mov	es,ax
	assumes	es,EGAMem

	mov	dx,EGA_BASE + SEQ_DATA
	mov	al,MM_ALL
	out	dx,al
	mov	dl,GRAF_ADDR		; DX = GRAF_ADDR
	mov	ax,0FFh shl 8 + GRAF_BIT_MASK
	out16	dx,ax
	mov	ax,0000b shl 8 + GRAF_ENAB_SR
	out16	dx,ax
	cli
	mov	ax,(M_COLOR_WRITE + M_DATA_READ) shl 8 + GRAF_MODE
	out16	dx,ax
	mov	al,byte ptr colors[BACKGROUND]
	mov	tonys_bar_n_grill,al
	mov	al,tonys_bar_n_grill
	mov	ax,(M_PROC_WRITE + M_DATA_READ) shl 8 + GRAF_MODE
	out16	dx,ax
	sti
	mov	ah,byte ptr colors[FOREGROUND]
	xor	ah,byte ptr colors[BACKGROUND]
	mov	al,GRAF_SET_RESET
	out16	dx,ax
	not	ah
	mov	al,GRAF_ENAB_SR
	out16	dx,ax
	mov	ax,DR_XOR shl 8 + GRAF_DATA_ROT
	out16	dx,ax

	ret

preset_fix_ega_opaque_mode	endp

;--------------------------Private-Routine------------------------------;
; preset_fix_ega_trans_mode
;
;  Do any one-time initialization of the EGA hardware for transparent
;  text.
;
; Entry:
;	BP = 
;	SS = StrStuff
; Returns:
;	None
; Error Returns:
;	None
; Registers Preserved:
;	BX,CX,SI,DI,BP,DS,ES
; Registers Destroyed:
;	AX,DX,FLAGS
; Calls:
;	None
; History:
;	Tue 25-Aug-1987 17:00:00 -by-  Bob Grudem [bobgru]
;	Made into subroutine.
;	Late spring, 1987        -by-  Tony Pisculli [tonyp]
;	Wrote it.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,nothing
	assumes ss,StrStuff

preset_fix_ega_trans_mode	proc	near

	mov	dx,EGA_BASE + GRAF_ADDR
	mov	ah,byte ptr colors[FOREGROUND]
	mov	al,GRAF_SET_RESET
	out16	dx,ax
	mov	ax,(MM_C0 + MM_C1 + MM_C2) shl 8 + GRAF_ENAB_SR
	out16	dx,ax
	mov	al,GRAF_BIT_MASK
	out	dx,al

	ret

preset_fix_ega_trans_mode	endp


;-----------------------------------------------------------------------;
;
;	The following cases are the general purpose routines for
;	outputting the text.  They will call through the stack
;	locations ss_draw and ss_draw_clipped to perform the
;	actual output operations.
;
;	Following the general purpose routines are any special
;	case routines.
;
;-----------------------------------------------------------------------;

	general_case	<gen_one_in_first>,<one_in_first>,<clipped_output>
	general_case	<gen_two_in_first>,<two_in_first>,<clipped_output>
	general_case	<gen_one_in_cell>,<one_in_cell>,<non_clipped_output>
	general_case	<gen_two_in_cell>,<two_in_cell>,<non_clipped_output>
	general_case	<gen_one_in_last>,<one_in_last>,<clipped_output>
	general_case	<gen_two_in_last>,<two_in_last>,<clipped_output>


if SPECIAL_CASE_BM_OBWNC eq 1		;Bitmap, opaque blk on white, no clip
	spec_case   <bm_obwnc_one_in_cell>,<one_in_cell>,<obwnc>
	spec_case   <bm_obwnc_two_in_cell>,<two_in_cell>,<obwnc>
endif

if SPECIAL_CASE_BM_TBNC eq 1 		;Bitmap, transp black, non-clipped
	spec_case   <bm_tbnc_one_in_cell>,<one_in_cell>,<tbnc>
	spec_case   <bm_tbnc_two_in_cell>,<two_in_cell>,<tbnc>
endif

if SPECIAL_CASE_DEV_ONC eq 1		;Device, opaque, non-clipped
	o_spec_case   <dev_onc_one_in_cell>,<one_in_cell>,<ega_onc_fix>
	o_spec_case   <dev_onc_two_in_cell>,<two_in_cell>,<ega_onc_fix>
endif

if SPECIAL_CASE_DEV_TNC eq 1 		;Device, transparent, non-clipped
	t1_spec_case   <dev_tnc_one_in_cell>,<one_in_cell>,<ega_tnc_fix>
	t2_spec_case   <dev_tnc_two_in_cell>,<two_in_cell>,<ega_tnc_fix>
endif

sEnd	Code
	end
