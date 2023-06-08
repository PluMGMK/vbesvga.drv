	page	,132
;----------------------------Module-Header------------------------------;
; Module Name: polyline.inc
;
; Brief Description: Continas equates used by Polyline.
;
; Created: 3/30/87
; Author: Kent Settle	(kentse)
;
; Copyright (c) 1983 - 1987  Microsoft Corporation
;-----------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.


SECOND_PASS	equ	00000010b	; Second pass flag.

DEST_IS_DEV	equ	10000000b	;Device is the screen (us)
DEST_IS_BITMAP	equ	00000000b	;Device is bitmap.
DEST_IS_HUGE	equ	01000000b	;Device is a huge bitmap
DEST_IS_COLOR	equ	00000001b	;Device is color


;	The following bit indexes are combined to index into the previous
;	axis update tables.  The placement of the entries are dependant
;	on these indexes.  If one changes, so must the other.

Y_MAJOR 	equ	00000001b	;Y is the major axis
DIAGONAL	equ	00000010b	; stepping along a diagonal
STEP_UP 	equ	00000100b	;The DDA is stepping up
STEP_LEFT	equ	00001000b	;The DDA is stepping right
HUGE_UPDATE	equ	01000000b	;Huge bitmap update

CASE_TABLE_MASK equ	00000011b	; only worry about diagonal + y major.

FIRST_PLANE	equ	00100001b	;Plane indicator

BITMAP_DO_NOTHING   equ 00h

ONLY_ONE_PLANE	equ	01
RASTER_OP_MASK	equ	000Fh
PARTIAL_BYTE_MASK equ	00000111b


