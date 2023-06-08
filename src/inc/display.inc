
;-----------------------------Module-Header-----------------------------;
; Module Name:	DISPLAY.INC
;
; This file contains definitions of OEM defined objects used by
; the driver.
;
; Created: Tue 17-Feb-1987
; Author:  Walt Moore [waltm]
;
; Copyright (c) 1984-1987 Microsoft Corporation
;
; Exported Functions:	none
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
; Restrictions:
;
; History:
; Modified for 8 bits/pixel (fat pixel) displays,
;   David Miller [o-davem] - Video Seven Inc.
;-----------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.

NUM_RESERVED_COLORS = 20

EXCLUSION	 =	1		;Assemble cursor exclusion code
GEN_COLOR_BLT	 =	1		;Assemble color BitBLT code

NUMBER_PLANES	equ	1		;3 plane format
OLD_MEM 	equ	1		;Old planer format for small bitmaps
GEN_COLOR	equ	1		;Generate code for a color driver



;	The color structure is how this driver stores its physical
;	colors in memory.  The color consists of four bytes (dword),
;	one byte for the color and one byte for some flag bits which
;	can be used to accelerate various graphics operations.

phys_color	struc
pcol_Clr	db	?		;8 bit color
pcol_fb 	db	?		;accelerator flags as defined below
		db	?		;reserved
		db	?		;reserved
phys_color	ends


;	Definitions for the pcol_fb byte of the physical color
;
;	Some of these definitions have limitations as to when they
;	are valid.  They are as follows:
;
;	MONO_BIT	mono  device, phys color
;	ONES_OR_ZEROS	color device, phys color, solid brushes if SOLID_COLOR
;	GREY_SCALE	color device, dithered solid and hatched brushes
;	SOLID_BRUSH	color device, solid brush qualifier
;
;	There may be brushes where the accelerators could have been set,
;	but wasn't.  That's life.


SPECIAL 	equ	pcol_fb 	;Special information is here
MONO_BIT	equ	00000001b	;  Monochrome bit
ONES_OR_ZEROS	equ	00000010b	;  Color is really all 1's or all 0's
GREY_SCALE	equ	00000100b	;  Indicates a real grey scale brush
SOLID_BRUSH	equ	00001000b	;  Indicates a solid color brush
WORD_BRUSH	equ	00010000b	;  Indicates a WORD repeating brush

	errnz	<(size phys_color) - 4> ;Must be a double word



;	The brush structure is OEM dependant, and can contain whatever
;	information that is needed to realize the given brush.
;
;	For this implementation, the brush will consist of an 8x8 byte
;	pattern for the color representation, and another 8x8 pattern
;	for monochrome devices and for monochrome to color conversion
;	(for something like a hatched brush, this would contain the
;	monochrome mask used to create the brush).
;
;	The style will also be stored in the brush and is used to
;	catch hollow brushes and exit early.
;
;	A flag specific to the EGA is also stored in the brush.  This
;	flag indicates that the brush is a solid brush and that the
;	color for each plane is a solid color (all 1's or all 0's).
;	Patterns which are solid in each plane can be handle as a
;	special case in Bitblt when the raster op is P or Pn.


SIZE_PATTERN	equ	8		;Size of an 8 by 8 pattern in bytes


oem_brush_def	struc
oem_brush_clr	db	SIZE_PATTERN * SIZE_PATTERN dup (?)    ;color brush
oem_brush_mono	db	SIZE_PATTERN dup (?)	;Mono portion
oem_brush_style dw	0			;Style of the brush
oem_brush_accel db	0			;Accellerator for solids
oem_brush_mask	db	SIZE_PATTERN dup (?)	;transparency mask
						;(it is the hatch pattern)
oem_brush_def   ends                            ;  (same as "Special" above)



;	The pen structure is OEM dependant, and can contain whatever
;	information that is needed to realize the given pen.  For this
;	implementation, this will be the style of the pen and the
;	physical color of the pen.
;
;	The style is used to catch pens of style NO_LINE and exit if
;	encountered.

oem_pen_def	struc
oem_pen_pcol	db	(size phys_color) dup (0);Physical color
oem_pen_style	dw	0			 ;Pen style
oem_pen_def	ends



;	The Internal Physical Device will look very similar to a bitmap,
;	with the exception that a couple of extra bytes will be tagged
;	onto the end to store the configuration of the screen and the
;	equipment flags
;
;	A flag which will also be used to inicatte that output is
;	enabled to the device.	This is required because it is possible
;	under Win386 to be asked to do output while the OEM layer is
;	disabled.
;
;       The bmType field will be used to determine a DIB DC from a DC to
;       the physical device.
;
;       if bmType contains:
;           0           - pDevice for a BITMAP
;           BMTYPE_DEV  - pDevice for the device
;           BMTYPE_DIB  - pDevice for a DIB
;

BMTYPE_MEM      equ     0
BMTYPE_DIB      equ     'DI'
BMTYPE_DEV      equ     0FFFFh




int_phys_device struc
		db	(size BITMAP) dup (?)
ipd_format	db	0		;Old screen format
ipd_equipment	db	0		;Old equipment switch values
; ipd_enabled	db	0		;0 if output is disabled
int_phys_device ends

;
;	The following bit flags were extracted from windows.inc. If that
;	file should change, we're hosed...
;

WF_PMODE	=    0001h
WF_CPU286       =    0002h
WF_CPU386       =    0004h
WF_CPU486       =    0008h
WF_STANDARD	=    0010h
WF_WIN286	=    0010h
WF_ENHANCED	=    0020h
WF_WIN386	=    0020h
WF_CPU086	=    0040h
WF_CPU186	=    0080h
WF_LARGEFRAME   =    0100h
WF_SMALLFRAME   =    0200h
WF_80x87        =    0400h


;	Flags for the Video Board set bu set_board_flags in vga.asm

BOARD_FLAG_VRAM 	EQU	10000000B
BOARD_FLAG_SPLITBANK    EQU     01000000B
BOARD_FLAG_ENABLE_216	EQU	00100000B

IFNDEF	FILE_VGA
sBegin  Data
	EXTRN	Video_Board_Id:WORD
	EXTRN	Video_Memory_Banks:BYTE
	EXTRN	Video_Board_Flags:BYTE

	EXTRN VScreen_Width:WORD
	EXTRN VScreen_Height:WORD
	EXTRN VScreen_Depth:BYTE
	EXTRN Vmode:WORD
sEnd    Data
ENDIF

