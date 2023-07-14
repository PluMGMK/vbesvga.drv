;
;	FILE:	vgautil.inc
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module holds routines that are useful in a fairly general
;	context throughout most of the device driver.
;

FUNC_COPY		EQU	00000000b
FUNC_AND		EQU	00001000b
FUNC_OR 		EQU	00010000b
FUNC_XOR		EQU	00011000b

SET_RESET_FOREGROUND	EQU	00000000b
DITHERED_FOREGROUND	EQU	00010000b

WRITE_MODE_0		EQU	00000000b
WRITE_MODE_1		EQU	00000001b

PLANAR_MODE		EQU	00000001b
SEQ_CHAIN_4_MODE	EQU	00000011b

IFNDEF	SRCFILE_VGAUTIL
EXTRN	get_edge_masks_nibbles:NEAR
EXTRN	vga_set_features:NEAR
EXTRN   set_page:NEAR
EXTRN	far_set_page:FAR
EXTRN	set_both_pages:NEAR
EXTRN	far_set_both_pages:FAR
ENDIF

