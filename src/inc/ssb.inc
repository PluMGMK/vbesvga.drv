        page    ,132
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ssb.inc
;
; Copyright (c) 1991 Microsoft Corporation.  All Rights Reserved.
;
; This file contains the external definitions for the SaveScreenBitmap
; functions
;
; Created: 14-Jan-1990
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;	shadow_mem_status contains flags controlling access to unused
;	video memory which will be used for saving the memory underneath
;       menus and dialog boxes.
;       the SHADOW_TRASHED bit will be set whenever the we are switched
;       to background
;

SHADOW_EXISTS   equ     00000001b       ;Shadow memory exists
SHADOW_IN_USE	equ	00000010b	;Shadow contains valid image
SHADOW_TRASHED	equ	00000100b	;Shadow contents have been destroyed
