;
;	FILE:	bblt.inc
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module holds routines that are useful in a fairly general
;	context throughout most of the device driver.
;

; PluM: extended device flags - all device_flags code seems to treat it as a
; word, so it shouldn't be a problem to add a second byte of flags...
; (just a bit inelegant maybe...)
; These indicate if scanlines in the src/dest can cross segment boundaries
; (which makes life more difficult in determining when to bank-switch!)
DEVFLAG_SRC_SCAN_X_SEG	EQU	00000010b SHL 8
DEVFLAG_DST_SCAN_X_SEG	EQU	00000001b SHL 8
DEVFLAG_SCAN_X_SEG	EQU	00000011b SHL 8	; check both at once
DEVFLAG_SPECIAL_ALLOWED	EQU	00000100b SHL 8	; track global flag on our stack

DEVFLAG_MOVSB		EQU	10000000b
DEVFLAG_REP		EQU	01000000b
DEVFLAG_PALETTE_MODIFIED EQU    00100000b
DEVFLAG_XLAT_REQUIRED   EQU     00010000b
DEVFLAG_SRC_SCREEN	EQU	00001000b
DEVFLAG_SRC_COLOR	EQU	00000100b
DEVFLAG_DST_SCREEN	EQU	00000010b
DEVFLAG_DST_COLOR	EQU	00000001b

DEVFLAG_HUE_AND_TYPE	EQU	00001111b

DEVFLAG_SRC_COLOR_DST_COLOR_SCREEN EQU (DEVFLAG_SRC_COLOR or DEVFLAG_DST_COLOR or DEVFLAG_DST_SCREEN)
DEVFLAG_SRC_COLOR_SCREEN_DST_COLOR EQU (DEVFLAG_SRC_COLOR or DEVFLAG_SRC_SCREEN or DEVFLAG_DST_COLOR)
DEVFLAG_BOTH_SCREEN		EQU  (DEVFLAG_SRC_SCREEN OR DEVFLAG_DST_SCREEN)

IFNDEF	SRCFILE_BBLT
ENDIF

