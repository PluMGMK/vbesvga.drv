;
;	FILE:	cursor.inc
;	DATE:	1/9/91
;	AUTHOR: Jim Keller
;
;	This file (unfortunately because of the way it developed) contains
;	not only the extrn functions declarations for the routines in
;	cursor.asm but also many globally needed screen parameters.
;
;       Copyright February, 1990  HEADLAND TECHNOLOGY, INC.


CUR_HEIGHT	equ	32			;Height of cursor/icon
MAX_BUF_HEIGHT  equ     64                      ;Number of scans in work buffer

CUR_ICON_WIDTH	equ	4			;Width in bytes of cursor/icon
SAVE_WIDTH	equ	CUR_ICON_WIDTH+1	;Width of save area
BUF_WIDTH	equ	SAVE_WIDTH+CUR_ICON_WIDTH  ;Width of work buffer
MASK_LENGTH	equ	SAVE_WIDTH*CUR_HEIGHT	;#bytes in AND/XOR mask
FARTHEST	equ	(CUR_ICON_WIDTH+1)*8	;How far apart in X old and
						;  new cursor may be for
						;  both to fit in work buffer

X_RATE		equ	1			;X mickeys/pixel rate
Y_RATE		equ	2			;Y mickeys/pixel rate

CUR_ROUND_LEFT	equ	0FFF0h			;Round down to a word
CUR_ROUND_RIGHT equ	0000Fh			;Round up   to a word

NEW_COORDS      EQU     00000001B
DOUBLE_PUMP	EQU	00000010B
YES_CURSOR	EQU	00000100B
LOCAL_LOAD	EQU	00001000B

CURSOR_HEIGHT	EQU	20H
CURSOR_WIDTH	EQU	20H

IFNDEF	FILE_CURSOR
	EXTRN	exclude:NEAR
	EXTRN	exclude_far:FAR
	EXTRN	unexclude:NEAR
	EXTRN	unexclude_far:FAR
	EXTRN	cursor_save_state:NEAR
	EXTRN	cursor_restore_state:NEAR

    sBegin	Data
	EXTRN	cursor_xdraw:WORD
	EXTRN	cursor_ydraw:WORD
	EXTRN	cursor_flags:WORD
	EXTRN	exclude_global:WORD
	EXTRN	exclude_rect_valid:WORD
        EXTRN   exclude_rect_left:WORD
	EXTRN	exclude_rect_right:WORD
	EXTRN	exclude_rect_top:WORD
	EXTRN	exclude_rect_bottom:WORD
    sEnd	Data
ENDIF

