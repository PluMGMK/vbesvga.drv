        page    ,132
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; vga.asm
;
; Copyright (c) 1991 Microsoft Corporation.  All Rights Reserved.
;
; This module contains functions and definitions specific to
; the VGA Display Driver.
;
; Created: 22-Feb-1987
;
; Exported Functions:	none
;
; Public Functions:	physical_enable
;			physical_disable
;
; Public Data:
;		PHYS_DEVICE_SIZE		info_table_base
;               SSB_EXTRA_SCANS                 Number of extra scanlines
;               SSB_EXTRA_PELS                  Number of extra columns
;		BW_THRESHOLD			physical_device
;		COLOR_FORMAT			rot_bit_tbl
;		SCREEN_W_BYTES			color_table
;		SCREEN_WIDTH			Code_palette
;		SCREEN_HEIGHT			
;		COLOR_TBL_SIZE			
;		COLOR_DONT_CARE
;		SSB_EXTRA_SCANS
;		ScreenSelector
;
;		HYPOTENUSE
;		Y_MAJOR_DIST
;		X_MAJOR_DIST
;		Y_MINOR_DIST
;		X_MINOR_DIST
;		MAX_STYLE_ERR
;
;		 H_HATCH_BR_0, H_HATCH_BR_1, H_HATCH_BR_2, H_HATCH_BR_3
;		 H_HATCH_BR_4, H_HATCH_BR_5, H_HATCH_BR_6, H_HATCH_BR_7
;		 V_HATCH_BR_0, V_HATCH_BR_1, V_HATCH_BR_2, V_HATCH_BR_3
;		 V_HATCH_BR_4, V_HATCH_BR_5, V_HATCH_BR_6, V_HATCH_BR_7
;		D1_HATCH_BR_0,D1_HATCH_BR_1,D1_HATCH_BR_2,D1_HATCH_BR_3
;		D1_HATCH_BR_4,D1_HATCH_BR_5,D1_HATCH_BR_6,D1_HATCH_BR_7
;		D2_HATCH_BR_0,D2_HATCH_BR_1,D2_HATCH_BR_2,D2_HATCH_BR_3
;		D2_HATCH_BR_4,D2_HATCH_BR_5,D2_HATCH_BR_6,D2_HATCH_BR_7
;		CR_HATCH_BR_0,CR_HATCH_BR_1,CR_HATCH_BR_2,CR_HATCH_BR_3
;		CR_HATCH_BR_4,CR_HATCH_BR_5,CR_HATCH_BR_6,CR_HATCH_BR_7
;		DC_HATCH_BR_0,DC_HATCH_BR_1,DC_HATCH_BR_2,DC_HATCH_BR_3
;		DC_HATCH_BR_4,DC_HATCH_BR_5,DC_HATCH_BR_6,DC_HATCH_BR_7
;
; General Description:
;
; Restrictions:
;
; History: modified for VRAM's 256 color modes 1/21/88
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

incDevice = 1				;Include control for gdidefs.inc
incDrawMode = 1                         ;Include DRAWMODE structure
FILE_VGA	EQU	1

	.xlist
	include cmacros.inc
	include gdidefs.inc
	include ega.inc
	include display.inc
	include macros.mac
	include	cursor.inc
	include rt.mac
	include vgareg.inc
	include	int3.inc

;	Additional Raster Capabilities

	.list

	externA	 __NEXTSEG		; an import from the kernel
	externA  __WinFlags		; LSB set in protected mode
	externA	 __A000			; selector for linear range A0000h-AFFFFh
        externFP AllocSelector          ; create a new selector
	externFP AllocCSToDSAlias	; change a CS selector to DS
	externFP AllocDSToCSAlias	; change a DS selector to CS
	externFP FreeSelector		; free the selector
	externFP GetProfileInt		; Kernel!GetProfileInt

ifndef lo
; The following structure should be used to access high and low
; words of a DWORD.  This means that "word ptr foo[2]" -> "foo.hi".

LONG    struc
lo      dw      ?
hi      dw      ?
LONG    ends
endif

ifndef off
FARPOINTER      struc
off     dw      ?
sel     dw      ?
FARPOINTER      ends
endif

	externFP init_hw_regs		;Initialize ega state code
        externFP SetPalette             ;loads palette
	externNP set_dacsize		;in VESAFNS.ASM
;	public	SSB_EXTRA_SCANS 	;Number of extra scanlines
;	public	SSB_EXTRA_PELS		;Number of extra columns
;	public	SSB_SAVE_X		;X cord of save area
;	public	SSB_SAVE_Y		;Y cord of save area
	public	PHYS_DEVICE_SIZE	;Number of bytes in physical device
	public	BW_THRESHOLD		;Black/white threshold
;	public	COLOR_FORMAT		;Color format
;	public	SCREEN_W_BYTES		;Screen width in bytes
;	public	SCREEN_WIDTH		;Screen width in pixels
;	public	SCREEN_HEIGHT		;Screen height in scans
	public	ScratchSel

	public	NUM_PALETTES		;Number of palette registers
;	public	PaletteSupported	;whether palette manager supported

	public	physical_enable 	;Enable routine
	public	physical_disable	;Disable

	public	physical_device 	;Physical device descriptor
	public	info_table_base 	;GDIInfo table base address

	public	HYPOTENUSE
	public	Y_MAJOR_DIST
	public	X_MAJOR_DIST
	public	Y_MINOR_DIST
	public	X_MINOR_DIST
	public	MAX_STYLE_ERR

	public	 H_HATCH_BR_0, H_HATCH_BR_1, H_HATCH_BR_2, H_HATCH_BR_3
	public	 H_HATCH_BR_4, H_HATCH_BR_5, H_HATCH_BR_6, H_HATCH_BR_7
	public	 V_HATCH_BR_0, V_HATCH_BR_1, V_HATCH_BR_2, V_HATCH_BR_3
	public	 V_HATCH_BR_4, V_HATCH_BR_5, V_HATCH_BR_6, V_HATCH_BR_7
	public	D1_HATCH_BR_0,D1_HATCH_BR_1,D1_HATCH_BR_2,D1_HATCH_BR_3
	public	D1_HATCH_BR_4,D1_HATCH_BR_5,D1_HATCH_BR_6,D1_HATCH_BR_7
	public	D2_HATCH_BR_0,D2_HATCH_BR_1,D2_HATCH_BR_2,D2_HATCH_BR_3
	public	D2_HATCH_BR_4,D2_HATCH_BR_5,D2_HATCH_BR_6,D2_HATCH_BR_7
	public	CR_HATCH_BR_0,CR_HATCH_BR_1,CR_HATCH_BR_2,CR_HATCH_BR_3
	public	CR_HATCH_BR_4,CR_HATCH_BR_5,CR_HATCH_BR_6,CR_HATCH_BR_7
	public	DC_HATCH_BR_0,DC_HATCH_BR_1,DC_HATCH_BR_2,DC_HATCH_BR_3
	public	DC_HATCH_BR_4,DC_HATCH_BR_5,DC_HATCH_BR_6,DC_HATCH_BR_7


;-----------------------------------------------------------------------;
;	The hatched brush pattern definitions
;-----------------------------------------------------------------------;

H_HATCH_BR_0	equ	00000000b	;Horizontal Hatched brush
H_HATCH_BR_1	equ	00000000b
H_HATCH_BR_2	equ	00000000b
H_HATCH_BR_3	equ	00000000b
H_HATCH_BR_4	equ	11111111b
H_HATCH_BR_5	equ	00000000b
H_HATCH_BR_6	equ	00000000b
H_HATCH_BR_7	equ	00000000b

V_HATCH_BR_0	equ	00001000b	;Vertical Hatched brush
V_HATCH_BR_1	equ	00001000b
V_HATCH_BR_2	equ	00001000b
V_HATCH_BR_3	equ	00001000b
V_HATCH_BR_4	equ	00001000b
V_HATCH_BR_5	equ	00001000b
V_HATCH_BR_6	equ	00001000b
V_HATCH_BR_7	equ	00001000b

D1_HATCH_BR_0	equ	10000000b	;\ diagonal brush
D1_HATCH_BR_1	equ	01000000b
D1_HATCH_BR_2	equ	00100000b
D1_HATCH_BR_3	equ	00010000b
D1_HATCH_BR_4	equ	00001000b
D1_HATCH_BR_5	equ	00000100b
D1_HATCH_BR_6	equ	00000010b
D1_HATCH_BR_7	equ	00000001b

D2_HATCH_BR_0	equ	00000001b	;/ diagonal hatched brush
D2_HATCH_BR_1	equ	00000010b
D2_HATCH_BR_2	equ	00000100b
D2_HATCH_BR_3	equ	00001000b
D2_HATCH_BR_4	equ	00010000b
D2_HATCH_BR_5	equ	00100000b
D2_HATCH_BR_6	equ	01000000b
D2_HATCH_BR_7	equ	10000000b

CR_HATCH_BR_0	equ	00001000b	;+ hatched brush
CR_HATCH_BR_1	equ	00001000b
CR_HATCH_BR_2	equ	00001000b
CR_HATCH_BR_3	equ	00001000b
CR_HATCH_BR_4	equ	11111111b
CR_HATCH_BR_5	equ	00001000b
CR_HATCH_BR_6	equ	00001000b
CR_HATCH_BR_7	equ	00001000b

DC_HATCH_BR_0	equ	10000001b	;X hatched brush
DC_HATCH_BR_1	equ	01000010b
DC_HATCH_BR_2	equ	00100100b
DC_HATCH_BR_3	equ	00011000b
DC_HATCH_BR_4	equ	00011000b
DC_HATCH_BR_5	equ	00100100b
DC_HATCH_BR_6	equ	01000010b
DC_HATCH_BR_7	equ	10000001b


;-----------------------------------------------------------------------;
;	Line style definitions for the EGA Card
;
;	Since the style update code in the line DDA checks for a sign,
;	the values chosen for distances, HYPOTENUSE, and MAX_STYLE_ERR
;	must not be bigger than 127+min(X_MAJOR_DIST,Y_MAJOR_DIST).  If
;	this condition is met, then the sign bit will always be cleared
;	on the first subtraction after every add-back.
;-----------------------------------------------------------------------;

HYPOTENUSE	=	51		;Distance moving X and Y
Y_MAJOR_DIST	=	36		;Distance moving Y only
X_MAJOR_DIST	=	36		;Distance moving X only
Y_MINOR_DIST	=	HYPOTENUSE-X_MAJOR_DIST
X_MINOR_DIST	=	HYPOTENUSE-Y_MAJOR_DIST
MAX_STYLE_ERR	=	HYPOTENUSE*2	;Max error before updating
					;  rotating bit mask

;-----------------------------------------------------------------------;
;	The black/white threshold is used to determine the split
;	between black and white when summing an RGB Triplet
;-----------------------------------------------------------------------;
BW_THRESHOLD	equ	(3*0FFh)/2
page

sBegin	Data

PUBLIC	VScreen_Width, VScreen_Height, VScreen_Depth, Vmode

VScreen_Width		DW	0
VScreen_Height		DW	0
Vmode			DW	0
VScreen_Depth		DB	0

EXTRN   dac_size:BYTE
externD	setramdac
externB bank_select
externD	VDDEntry
externD	MemSize				; in VESAFNS.ASM

globalW ScreenSelector,0                ;the screen selector
globalW ScratchSel,0			;have a scratch selector

globalB enabled_flag,0			;Display is enabled if non-zero

NUM_PALETTES	 equ	256		; number of palettes
;PaletteSupported equ	1		; palette manager not supported
globalB	device_local_brush ,0,<SIZE oem_brush_def>; for translate palette
globalB PaletteTranslationTable,0, NUM_PALETTES	  ; the tranlate table
globalB PaletteIndexTable,0, NUM_PALETTES	  ; the reverse index table
globalB PaletteModified,0			  ; table tampered ?
globalB TextColorXlated,0			  ; text colors translated
globalB device_local_drawmode,0,<SIZE DRAWMODE>   ; local drawmode structure
globalB device_local_pen,0,<SIZE oem_pen_def>	  ; local pen definitions
globalW is_protected,__WinFlags 	;LSB set in protected mode
	public is_protected

STOP_IO_TRAP	equ 4000h		; stop io trapping
START_IO_TRAP	equ 4007h		; re-start io trapping

;----------------------------------------------------------------------------;
; we first define the equates for the fixed palette and color mapping for the;
; EGA and VGA drivers. The low nibble of the bytes  are the color indices &  ;
; the high nibble has the accelarator bytes as discussed above.		     ;
;----------------------------------------------------------------------------;

PHY_COLOR_BYTE_00	equ	0010b	    ; black
PHY_COLOR_BYTE_01	equ	0000b	    ; dark red
PHY_COLOR_BYTE_02	equ	0000b	    ; dark green
PHY_COLOR_BYTE_03	equ	0000b	    ; mustard
PHY_COLOR_BYTE_04	equ	0000b	    ; dark blue
PHY_COLOR_BYTE_05	equ	0000b	    ; purple
PHY_COLOR_BYTE_06	equ	0000b	    ; dark turquoise
PHY_COLOR_BYTE_07	equ	0001b	    ; gray
PHY_COLOR_BYTE_07a	equ	0001b	    ; money green
PHY_COLOR_BYTE_07b	equ	0001b	    ; new blue
PHY_COLOR_BYTE_07c	equ	0001b	    ; off-white
PHY_COLOR_BYTE_07d	equ	0001b	    ; med-gray
PHY_COLOR_BYTE_08	equ	0001b	    ; dark gray
PHY_COLOR_BYTE_09	equ	0000b	    ; red
PHY_COLOR_BYTE_10	equ	0001b	    ; green
PHY_COLOR_BYTE_11	equ	0001b	    ; yellow
PHY_COLOR_BYTE_12	equ	0000b	    ; blue
PHY_COLOR_BYTE_13	equ	0000b	    ; magenta
PHY_COLOR_BYTE_14	equ	0001b	    ; cyan
PHY_COLOR_BYTE_15	equ	0011b	    ; white

;----------------------------------------------------------------------------;
; The next set of equates define the physical color bytes for the types      ;
; supported by the driver.						     ;
;----------------------------------------------------------------------------;


PHY_COLOR_DATA_00       equ     00000000h       ; black
PHY_COLOR_DATA_01       equ     000000BFh       ; dark red
PHY_COLOR_DATA_02       equ     0000BF00h       ; dark green
PHY_COLOR_DATA_03       equ     0000BFBFh       ; mustard
PHY_COLOR_DATA_04       equ     00BF0000h       ; dark blue
PHY_COLOR_DATA_05       equ     00BF00BFh       ; purple
PHY_COLOR_DATA_06       equ     00BFBF00h       ; dark turquoise
PHY_COLOR_DATA_07       equ     00C0C0C0h       ; gray

PHY_COLOR_DATA_07a      equ     00C0DCC0h       ; money green
PHY_COLOR_DATA_07b	equ	00F0C8A4h	; new blue
PHY_COLOR_DATA_07c	equ	00F0FBFFh	; off-white
PHY_COLOR_DATA_07d      equ     00A4A0A0h       ; med-gray

PHY_COLOR_DATA_08	equ	00808080h	; dark gray
PHY_COLOR_DATA_09	equ	000000FFh	; red			
PHY_COLOR_DATA_10	equ	0000FF00h	; green			
PHY_COLOR_DATA_11	equ	0000FFFFh	; yellow		
PHY_COLOR_DATA_12	equ	00FF0000h	; blue			
PHY_COLOR_DATA_13	equ	00FF00FFh	; pink (magenta)	
PHY_COLOR_DATA_14	equ	00FFFF00h	; cyan			
PHY_COLOR_DATA_15	equ	00FFFFFFh	; white			

	public	adPalette
adPalette	equ	this dword	; Color Palette
	dd	PHY_COLOR_DATA_00
	dd	PHY_COLOR_DATA_01
	dd	PHY_COLOR_DATA_02
	dd	PHY_COLOR_DATA_03
	dd	PHY_COLOR_DATA_04
	dd	PHY_COLOR_DATA_05
	dd	PHY_COLOR_DATA_06
	dd	PHY_COLOR_DATA_07
        dd      PHY_COLOR_DATA_07a
        dd      PHY_COLOR_DATA_07b

        dd      236 dup(0)

        dd      PHY_COLOR_DATA_07c
        dd      PHY_COLOR_DATA_07d
	dd	PHY_COLOR_DATA_08
	dd	PHY_COLOR_DATA_09
	dd	PHY_COLOR_DATA_10
	dd	PHY_COLOR_DATA_11
	dd	PHY_COLOR_DATA_12
	dd	PHY_COLOR_DATA_13
	dd	PHY_COLOR_DATA_14
	dd	PHY_COLOR_DATA_15

        public  abPaletteAccl
abPaletteAccl   equ     this byte       ; Accelerator flags for palette
        db      PHY_COLOR_BYTE_00
        db      PHY_COLOR_BYTE_01
        db      PHY_COLOR_BYTE_02
        db      PHY_COLOR_BYTE_03
        db      PHY_COLOR_BYTE_04
        db      PHY_COLOR_BYTE_05
        db      PHY_COLOR_BYTE_06
        db      PHY_COLOR_BYTE_07
        db      PHY_COLOR_BYTE_07a
        db      PHY_COLOR_BYTE_07b

        db      236 dup(0)

        db      PHY_COLOR_BYTE_07c
        db      PHY_COLOR_BYTE_07d
        db      PHY_COLOR_BYTE_08
        db      PHY_COLOR_BYTE_09
        db      PHY_COLOR_BYTE_10
        db      PHY_COLOR_BYTE_11
        db      PHY_COLOR_BYTE_12
        db      PHY_COLOR_BYTE_13
        db      PHY_COLOR_BYTE_14
        db      PHY_COLOR_BYTE_15

NumOfLines	db	0	; number of lines in text mode

; Runtime adjustable "colour format" (msbyte = bits/pel; lsbyte = # planes)
public	ColourFormat
ColourFormat	dw	COLOR_FORMAT

; Remember where we put the latch save address
public	LatchAddx
LatchAddx	dw	0
; Essentially useless byte required to satisfy function contract with VDD
ShadowMemStatus db	0

sEnd	Data
page

createSeg _INIT,InitSeg,word,public,CODE
sBegin	InitSeg
assumes cs,InitSeg


COLOR_FORMAT	equ	(0801h) 	;msbyte = bits/pel; lsbyte = # planes

;-----------------------------------------------------------------------;
;	PhysDeviceSize is the number of bytes that the enable routine
;	is to copy into the passed PDevice block before calling the
;	physical_enable routine.  For this driver, the length is the
;	size of the bitmap structure.
;-----------------------------------------------------------------------;

PHYS_DEVICE_SIZE equ	size BITMAP



;-----------------------------------------------------------------------;
;       Allocate the physical device block for the display Card.
;	For this driver, physical devices will be in the same format
;	as a normal bitmap descriptor.	This is very convienient since
;	it simplifies the structures that the code must work with.
;
;	The bmWidthPlanes field will be set to zero to simplify some
;	of the three plane code.  By setting it to zero, it can be
;	added to a memory bitmap pointer without changing the pointer.
;	This allows the code to add this in regardless of the type of
;	the device.
;
;	The actual physical block will have some extra bytes stuffed on
;	the end (IntPhysDevice structure), but only the following is static
;-----------------------------------------------------------------------;

SCRSEL          equ     0FFFFh
P		equ	 COLOR_FORMAT AND 000FFh	;# color planes
B		equ	(COLOR_FORMAT AND 0FF00h) SHR 8	;# bits per pixel
H		equ	480		;this may be fixed up at enable time
W		equ	640		;this may be fixed up at emable time
WB		equ	1024		;display width, bytes (fixed up @enable)
IS		equ	00000h		;index to next segment
SSG		equ	64		;scanlines per segment(fixed up @enable)

physical_device BITMAP <SCRSEL,W,H,WB,P,B,0A0000000H,0,0,IS,SSG,0,0,0>

sEnd

sBegin	InitSeg
assumes cs,InitSeg

;-----------------------------------------------------------------------;
;	The GDIInfo data Structure.  The specifics of the EGA
;	mode are passed to GDI via this structure.
;-----------------------------------------------------------------------;

info_table_base label byte

	dw	0			;Version
	errnz	dpVersion

	dw	DT_RASDISPLAY		;Device classification
	errnz	dpTechnology-dpVersion-2

	dw	0			;Horizontal size in millimetres (fixed
					; up by enable.asm at boot time)
	errnz	dpHorzSize-dpTechnology-2

	dw	0			;Vertical size in millimetres (fixed
					; up by enable.asm at boot time)
	errnz	dpVertSize-dpHorzSize-2

	dw	0			;Horizontal width in pixels (fixed up
					; by enable.asm at boot time)
	errnz	dpHorzRes-dpVertSize-2

	dw	0			;Vertical width in pixels (fixed up by
					; enable.asm at boot time)
	errnz	dpVertRes-dpHorzRes-2

	dw	8			;Number of bits per pixel
	errnz	dpBitsPixel-dpVertRes-2

	dw	1			;Number of planes
	errnz	dpPlanes-dpBitsPixel-2

	dw	-1			;Number of brushes the device has
	errnz	dpNumBrushes-dpPlanes-2 ;  (Show lots of brushes)

	dw	20*5			;Number of pens the device has
	errnz	dpNumPens-dpNumBrushes-2;  (256 colors * 5 styles)

	dw	0			;Reserved

	dw	0			;Number of fonts the device has
	errnz	dpNumFonts-dpNumPens-4

        dw      NUM_RESERVED_COLORS     ;Number of colors in color table
	errnz	dpNumColors-dpNumFonts-2

	dw	size int_phys_device	;Size required for device descriptor
	errnz	dpDEVICEsize-dpNumColors-2

	dw	CC_NONE 		;Curves capabilities
	errnz	dpCurves-dpDEVICEsize-2

	dw	LC_POLYLINE;+LC_STYLED	;Line capabilities
	errnz	dpLines-dpCurves-2

                                        ;Polygonal capabilities
        dw      PC_SCANLINE;;;;;;;;;;;;;;+PC_POLYGON+PC_INTERIORS
        errnz   dpPolygonals-dpLines-2

	dw	TC_CP_STROKE+TC_RA_ABLE ;Text capabilities
	errnz	dpText-dpPolygonals-2

	dw	CP_RECTANGLE 		;Clipping capabilities
        errnz   dpClip-dpText-2

RC_DI_BITMAP	equ 0000000010000000b	; can do device independent bitmaps
RC_PALETTE	equ 0000000100000000b	; can do color palette management
RC_DIBTODEV	equ 0000001000000000b	; can do SetDIBitsToDevice
RC_BIGFONT      equ 0000010000000000b   ; can do fonts > 64k
;RC_TRANSPARENT equ 1000000000000000b	 ; can do transparent BitBlt

                                        ;BitBlt capabilities
;	 dw	 RC_TRANSPARENT+RC_BITBLT+RC_BITMAP64+RC_GDI20_OUTPUT+RC_DI_BITMAP+RC_DIBTODEV+RC_PALETTE+RC_STRETCHBLT+RC_STRETCHDIB
	dw	RC_BITBLT+RC_BITMAP64+RC_GDI20_OUTPUT+RC_DI_BITMAP+RC_DIBTODEV+RC_PALETTE+RC_STRETCHBLT+RC_STRETCHDIB
        errnz   dpRaster-dpClip-2

	dw	X_MAJOR_DIST		;Distance moving X only
	errnz	dpAspectX-dpRaster-2

	dw	Y_MAJOR_DIST		;Distance moving Y only
	errnz	dpAspectY-dpAspectX-2

	dw	HYPOTENUSE		;Distance moving X and Y
	errnz	dpAspectXY-dpAspectY-2

	dw	MAX_STYLE_ERR		;Length of segment for line styles
	errnz	dpStyleLen-dpAspectXY-2

	errnz	dpMLoWin-dpStyleLen-2	;Metric  Lo res WinX,WinY,VptX,VptY
	dw	15 			;  HorzSize * 10
	dw	15 			;  VertSize * 10
	dw	4			;  HorizRes
	dw	-4 			;  -VertRes

	errnz	dpMHiWin-dpMLoWin-8	;Metric  Hi res WinX,WinY,VptX,VptY
	dw	150			;  HorzSize * 100
	dw	150			;  VertSize * 100
	dw	4			;  HorizRes
	dw	-4 			;  -VertRes

	errnz	dpELoWin-dpMHiWin-8	;English Lo res WinX,WinY,VptX,VptY
	dw	375 			;  HorzSize * 1000
	dw	375 			;  VertSize * 1000
	dw	254 			;  HorizRes * 254
	dw	-254			;  -VertRes * 254

	errnz	dpEHiWin-dpELoWin-8	;English Hi res WinX,WinY,VptX,VptY
	dw	3750			;  HorzSize * 10000
	dw	3750			;  VertSize * 10000
	dw	254 			;  HorizRes * 254
	dw	-254			;  -VertRes * 254

	errnz	dpTwpWin-dpEHiWin-8	;Twips		WinX,WinY,VptX,VptY
	dw	5400			;  HorzSize * 14400
	dw	5400			;  VertSize * 14400
	dw	254 			;  HorizRes * 254
	dw	-254			;  -VertRes * 254

	dw	96			;Logical Pixels/inch in X
	errnz	dpLogPixelsX-dpTwpWin-8

	dw	96			;Logical Pixels/inch in Y
	errnz	dpLogPixelsY-dpLogPixelsX-2

	dw	DC_IgnoreDFNP		;dpDCManage
	errnz	dpDCManage-dpLogPixelsY-2

C1_TRANSPARENT  equ     0001h           ;driver supports transparency in BitBlt
        dw      C1_TRANSPARENT          ;CAPS1

	dw	0			;Reserved fields
	dw	0
	dw	0
	dw	0

; start of entries in version 3.0 of this structure
	dw	256 			; number of palette entries
        dw      NUM_RESERVED_COLORS     ; number of reserved entries
	dw	18			; DAC resolution for RGB


page

;---------------------------Public-Routine------------------------------;
; physical_enable
;
;   VGA graphics mode is enabled.  The VGA's Color-Don't-Care
;   register and palettes are set for an 8-color mode of operation.
;   The EGA state restoration code is initialized.
;
; Entry:
;	ES:DI --> our pDevice
;	DS:    =  Data
; Returns:
;	AX = non-zero to show success
; Error Returns:
;	AX = 0
; Registers Preserved:
;	BP
; Registers Destroyed:
;	AX,BX,CX,DX,SI,DI,ES,DS,FLAGS
; Calls:
;	INT 10h
;	init_hw_regs
; History:
;	Tue 18-Aug-1987 18:09:00 -by-  Walt Moore [waltm]
;	Added enabled_flag
;
;	Thu 26-Feb-1987 13:45:58 -by-  Walt Moore [waltm]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,Data
	assumes es,nothing

physical_enable proc near
	WriteAux    <'Physical Enable'>
;----------------------------------------------------------------------------;
; allocate the scratch selector here				             ;
;----------------------------------------------------------------------------;

	push	es

        push    es
	xor	ax,ax
	push	ax
	cCall	AllocSelector		; get a free selector
	mov	ScratchSel,ax		; save it
        pop     es

	push	es
	push	bp
	mov	ax,1130h
	mov	bh,0
	int	10h
	mov	NumOfLines,dl		; save the # of lines on the screen

	mov	ax,040h 		; bogus for keyboard !!!
	mov	es,ax
	mov	BYTE PTR es:[49h],06h

	pop	bp
	pop	es

	;some of these pushes and pops probably aren't necessary
	push	di
	push	si
	call	setmode


	mov	bx,1			;attempt to set 8 bit DAC mode
        call    set_dacsize

	test	[info_table_base.dpRaster],RC_PALETTE
	jz	@F

	mov	si,DataOFFSET adPalette ;load pointer to color table
	xor	ax,ax			;starting index
	mov	cx,NUM_PALETTES
        call    setramdac

@@:
        call    init_hw_regs

	pop	si
	pop	di
	pop	es

        mov     enabled_flag,0ffh       ; show enabled

;----------------------------------------------------------------------------;
; at this point notify kernel that driver is cable of doing a save/restore   ;
; of its state registers and kernel should stop I/O trapping.		     ;
; Do this only if we are in protected mode.				     ;
;----------------------------------------------------------------------------;
	
	mov	ax,is_protected
	and	ax,(WF_PMODE OR WF_WIN386)
	test	ax,WF_PMODE
	jz	phys_enable_ok		;not in protected mode

	; check if we have a VDD entry pointer (EGAINIT should have set it)
	cmp	[VDDEntry.sel],0
	jz	novdd
	; call it to set the latch position - we put it at the end of the last
	; *visible* page of VRAM in the range A0000h-AFFFFh, so that VDD knows
	; what pages are visible!
	mov	ax,0Ch			;VDDsetaddresses
	mov	bx,[MemSize.lo]
	mov	cx,[MemSize.hi]		;TODO: implement bank awareness in VDD
	; NOTE: we are in Chain4 mode, but the VDD will enter planar mode to
	; save the latches, so the saving will (in theory) be at an address
	; four times higher than the one we spec here. But what really matters
	; is that we mark ALL our pages as visible, in Chain4 mode, so VDD won't
	; try to steal them based on some putative LRU value!
	dec	bx			;convert buffer length to last address
	test	cl,cl			;more than 64k bytes?
	jz	@F
	mov	bx,-1			;just tell it we're taking all 16 pages
@@:	or	bx,0FFFh		;round up to end of page
	xor	dx,dx			;no flags - TODO: bank flag for VDD
	lea	si,ShadowMemStatus
	call	[VDDEntry]
	mov	[LatchAddx],bx

	OWN_ALL_PAGES

novdd:	mov	ax,STOP_IO_TRAP		
	int	2fh		
;
phys_enable_ok:
        mov     ax,1                    ;indicate success
        ret

physical_enable endp
page

;---------------------------Public-Routine------------------------------;
; physical_disable
;
;   VGA 640x480, or 720x512 graphics mode is exited.  The previous mode
;   of the adapter is restored.
;
; Entry:
;	DS:SI --> int_phys_device
;	ES:    =  Data
; Returns:
;	AX = non-zero to show success
; Error Returns:
;	None
; Registers Preserved:
;	BP
; Registers Destroyed:
;	AX,BX,CX,DX,SI,DI,ES,DS,FLAGS
; Calls:
;	INT 10h
;	init_hw_regs
; History:
;	Tue 18-Aug-1987 18:09:00 -by-  Walt Moore [waltm]
;	Added enabled_flag
;
;	Thu 26-Feb-1987 13:45:58 -by-  Walt Moore [waltm]
;	Created.
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,Data

physical_disable proc near
	WriteAux <'Physical Disable'>
;----------------------------------------------------------------------------;
; disbale the selector here				                     ;
;----------------------------------------------------------------------------;

	push	es
	mov	ax,ScratchSel		; get the scratch selector
	cCall	FreeSelector,<ax>	; free it
	pop	es

;----------------------------------------------------------------------------;

	xor	ah,ah
	mov	enabled_flag,ah 	;Show disabled

        mov     ax,0003h
	int	10h
	cmp	es:[NumOfLines],25-1	; 25 line display?
	jz	phdi_exit
;
@@:
	mov	ax,1201h
	cmp	es:[NumOfLines],43-1
	jz	@F
	inc	ax			; 1202h
	cmp	es:[NumOfLines],50-1
	jnz	phdi_exit		; leave @25 line mode
;
@@:
	mov	bx,30h
	int	10h
	mov	ax,1112h
	mov	bx,0h
	int	10h
;
phdi_exit:

;----------------------------------------------------------------------------;
; at this point as the kernel to do the io trapping again, provided we are in;
; protected mode.							     ;
;----------------------------------------------------------------------------;
	
	mov	ax,is_protected
	and	ax,(WF_PMODE OR WF_WIN386)
	test	ax,WF_PMODE
	jz	phys_disable_ret	;we are in real mode
	mov	ax,START_IO_TRAP
	int	2fh			;start i/o trapping
;
phys_disable_ret:
	push	es
	pop	ds
	sub	bx,bx				;set 6 bit DAC mode
        call    set_dacsize
        mov     ax,1
        ret

physical_disable endp
page


	assumes ds,Data
	assumes es,nothing
	externNP setmode	; in VESAFNS.ASM
	public	farsetmode
farsetmode     proc    far
	call	setmode
	ret

farsetmode      endp

sEnd

end

