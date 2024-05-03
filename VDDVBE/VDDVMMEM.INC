;******************************************************************************
;
; VDDVMMEM.INC	  Include file for Virtual Display Devices for EGA/VGA/8514
;
;	Author: RAP
;	Copyright (c) Microsoft 1986-1992
;
;DESCRIPTION:
;	This defines constants and data structures for EGA/VGA/8514
;       Virtual Display Devices(VDD).
;
;******************************************************************************


;
; Flag bits in each word of pagemap array
;
DefFlag PageSaved	0	; flag set, if page has been saved to
				;   VM's virtual video memory
DefFlag PageSaveMem	1	; a save memory page is mapped
DefFlag PageFontMem	2	; a font save memory page is mapped
DefFlag PageModified	3	; flag set, if page has been modified
				;   and should be repainted, if VM windowed
fPageGblFlags	equ fPageSaved	; flags to maintain over alloc's
