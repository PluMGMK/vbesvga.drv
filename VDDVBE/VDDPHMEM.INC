;******************************************************************************
;
; VDDPHMEM.INC	  Include file for Virtual Display Devices for EGA/VGA/8514
;
;	Author: RAP
;	Copyright (c) Microsoft 1986-1990
;
;DESCRIPTION:
;	This defines constants and data structures for EGA/VGA/8514
;       Virtual Display Devices(VDD).
;
;******************************************************************************

;******************************************************************************
;
; Notifcation flags sent by VDDPHMEM to registered page owner callbacks
;
fPHM_notify_page_free	    equ 0	; owner is about to lose page, owner
					;   should save current memory, or
					;   return with Carry set, to indicate
					;   that the page cannot be freed.
fPHM_notify_page_unmap	    equ 1	; page is no longer accessable with
					;   current memory controller state,
					;   owner should unmap physical page
fPHM_notify_page_changed    equ 2	; VDDPHMEM wants to substitute a new
					;   physical page for the one currently
					;   owned.  Owner can copy memory from
					;   the old page to the new one and then
					;   start using the new page handle!


;
; A page handle is a ptr to a Page_Data_Struc block
;
Page_Data_Struc STRUC
PDS_physpage	dw  ?		; index into table of physical pages
		db  ?
PDS_flags	db  ?
PDS_virtual_id	dw  ?		; virtual page ID
PDS_linear_page dw  ?		; set & used by VDDVMEM routines
PDS_owner	dd  ?		; owner VM handle
PDS_callback	dd  ?		; handler callback proc address
Page_Data_Struc ENDS


Next_Planar_Page_Id	equ 1

IFDEF DEBUG
PD_Debug_Mask	equ 00001111b	; bottom 4 bits must be clear in a page handle
ENDIF

DefFlag PDS_Saved   0
DefFlag PDS_Dirty   6
.errnz fPDS_Dirty - P_DIRTY	; must be the same bit!
