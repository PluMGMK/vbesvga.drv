;
;	FILE:	bltspec.inc
;	DATE:	2025-08-17
;	AUTHOR: PluMGMK
;
;	This module contains routines for blitting directly to/from
;	a linear framebuffer.
;

IFNDEF	SRCFILE_BLTSPEC
EXTRN	blt_spec_pattern:NEAR
ENDIF

EXTRN	GetLinBufPtr:FAR	; in VESAFNS.ASM

