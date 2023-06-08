;
;-----------------------------Module-Header-----------------------------;
; Module Name:  DRAWMOD2.ASM
;
;   This module contains tables for using the special EGA
;   hardware for the bianry raster operations.
;
; Created: 22-Feb-1987
; Author:  Walt Moore [waltm]
;
; Copyright (c) 1984-1987 Microsoft Corporation
;
; Exported Functions:   none
;
; Public Functions:     none
;
; Public Data:          SINGLE_OK
;                       dm_flags
;                       dm_data_r
;                       dm_pen_and
;                       dm_pen_xor
;
; General Description:
;
;   The EGA card has special drawing logic where a logical
;   operation may be performed between the display memory
;   and data from the processor.  There is also drawing
;   logic that allows a byte from the processor to be
;   taken as a color to be written into all enabled bits
;   and enabled planes of a particular byte.  By combining
;   these operations, most of the binary drawing modes
;   specified by GDI can be implemented in one pass over
;   EGA memory.
;
;   12 of the 16 GDI binary drawing modes can be done in one pass
;   if writing a solid color using the EGA color write mode.
;
;   Scanline must also deal with background modes.  Brushes
;   implicitly handle opaque mode by the colors they are realized
;   in.  For transparent mode, a mask is computed from the
;   brush for background and NOT background.  By using this mask
;   in the EGA's Bit Mask register, only those bits that are
;   forground will be changed.  Scanline can use the same 12
;   EGA drawing modes as lines if the color is solid.
;
;   Dithered patterns cannot be performed in one pass since
;   they are not solid.
;
;
;   EGA special support possible:
;
;           Operation     Single Pass
;              DDx             y
;              DPon
;              DPna            y
;              Pn              y
;              PDna
;              Dn              y
;              DPx             y
;              DPan
;              DPa             y
;              DPxn            y
;              D               y
;              DPno            y
;              P               y
;              PDno
;              DPo             y
;              DDxn            y
;
;
;
;
;   The following cannot be performed in one pass using the
;   EGA hardware.  They can be performed in two seperate
;   operations to the EGA.  This will be done in the following
;   manner:
;
;       The color will be used for the Write Plane Enable Mask
;       after it has possibly been inverted to sync for the
;       output mode being used (xor or set)
;
;       A write with 0's or 1's in drSet mode will occur.
;       This will set bits to either 1's or 0's as needed.
;
;       After this write occurs, the color will be inverted
;       for use as the Write Plane Enable Mask for those
;       planes which must be XORed to get ~dest.  An XOR
;       will occur to toggle those bits which must be toggled.
;
;
;             Color  Result
;
;       DPon    0    ~dest   for color bits which are 0, xor with 1
;               1      0     for color bits which are 1, set to   0
;
;       PDna    0      0     for color bits which are 0, set to   0
;               1    ~dest   for color bits which are 1, xor with 1
;
;       DPan    0      1     for color bits which are 0, set to   1
;               1    ~dest   for color bits which are 1, xor with 1
;
;       PDno    0    ~dest   for color bits which are 0, xor with 1
;               1      1     for color bits which are 1, set to   1
;
; Restrictions:
;
;-----------------------------------------------------------------------;
;
; The following equates are used for those raster operations
; which can be performed in one operation on the EGA card.
; The values are ANDed and XORed with the pen to get the
; desired color to use for the raster operation.
;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.
ZERO_PEN        equ     00000h          ;AND with 00000000b, XOR with 00000000b
PEN             equ     000FFh          ;AND with 11111111b, XOR with 00000000b
ONE_PEN         equ     0FF00h          ;AND with 00000000b, XOR with 11111111b
NOT_PEN         equ     0FFFFh          ;AND with 11111111b, XOR with 11111111b
;
; The following equates are used for those raster operations
; which required two operations to the VGA.
;
INVERT          equ     0FFh            ;INVERT color before using as plane mask
NO_INVERT       equ     000h            ;Use the color directly as plane mask
SET_TO_1S       equ     0FFh            ;For the Set, use 1's
SET_TO_0S       equ     000h            ;For the Set, use 0's
;
SINGLE_OK       equ    00000001b        ;Single pass ok
;
;
; dm_data_r contains the value which will be output to the
; Data Rotate Register for the raster operations.  For
; those raster operations which require two passes, the
; value in this table will always be drSet.
;
;if 0
;

DR_SET          equ     00000000b
DR_AND          equ     00001000b
DR_OR           equ     00010000b
DR_XOR          equ     00011000b


dm_data_r       label byte
                db      DR_SET          ;DDx
                db      DR_SET          ;DPon   ;Two operations required
                db      DR_AND          ;DPna
                db      DR_SET          ;Pn
                db      DR_SET          ;PDna   ;Two operations required
                db      DR_XOR          ;Dn
                db      DR_XOR          ;DPx
                db      DR_SET          ;DPan   ;Two operations required
                db      DR_AND          ;DPa
                db      DR_XOR          ;DPxn
                db      DR_OR           ;D
                db      DR_OR           ;DPno
                db      DR_SET          ;P
                db      DR_SET          ;PDno   ;Two operations required
                db      DR_OR           ;DPo
                db      DR_SET          ;DDxn
;endif
;
; dm_flags contains flags indicating if the raster operation
; may be performed in one operation or if two operations are
; required.
;
dm_flags        label   byte
                db      SINGLE_OK       ;DDx
                db      0               ;DPon   ;Two operations required
                db      SINGLE_OK       ;DPna
                db      SINGLE_OK       ;Pn
                db      0               ;PDna   ;Two operations required
                db      SINGLE_OK       ;Dn
                db      SINGLE_OK       ;DPx
                db      0               ;DPan   ;Two operations required
                db      SINGLE_OK       ;DPa
                db      SINGLE_OK       ;DPxn
                db      SINGLE_OK       ;D
                db      SINGLE_OK       ;DPno
                db      SINGLE_OK       ;P
                db      0               ;PDno   ;Two operations required
                db      SINGLE_OK       ;DPo
                db      SINGLE_OK       ;DDxn
;
dm_pen_and      label   byte
                db      LOW ZERO_PEN    ;DDx
                db      LOW SET_TO_0S   ;DPon   ;Two operations required
                db      LOW NOT_PEN     ;DPna
                db      LOW NOT_PEN     ;Pn
                db      LOW SET_TO_0S   ;PDna   ;Two operations required
                db      LOW ONE_PEN     ;Dn
                db      LOW PEN         ;DPx
                db      LOW SET_TO_1S   ;DPan   ;Two operations required
                db      LOW PEN         ;DPa
                db      LOW NOT_PEN     ;DPxn
                db      LOW ZERO_PEN    ;D
                db      LOW NOT_PEN     ;DPno
                db      LOW PEN         ;P
                db      LOW SET_TO_1S   ;PDno   ;Two operations required
                db      LOW PEN         ;DPo
                db      LOW ONE_PEN     ;DDxn
;
dm_pen_xor      label   byte
                db      HIGH ZERO_PEN   ;DDx
                db           NO_INVERT  ;DPon   ;Two operations required
                db      HIGH NOT_PEN    ;DPna
                db      HIGH NOT_PEN    ;Pn
                db           INVERT     ;PDna   ;Two operations required
                db      HIGH ONE_PEN    ;Dn
                db      HIGH PEN        ;DPx
                db           INVERT     ;DPan   ;Two operations required
                db      HIGH PEN        ;DPa
                db      HIGH NOT_PEN    ;DPxn
                db      HIGH ZERO_PEN   ;D
                db      HIGH NOT_PEN    ;DPno
                db      HIGH PEN        ;P
                db           NO_INVERT  ;PDno   ;Two operations required
                db      HIGH PEN        ;DPo
                db      HIGH ONE_PEN    ;DDxn

