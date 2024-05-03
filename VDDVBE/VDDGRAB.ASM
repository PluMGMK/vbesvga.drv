PAGE 58,132
;******************************************************************************
TITLE vddgrab.asm -
;******************************************************************************
;
;   (C) Copyright MICROSOFT Corp.  All Rights Reserved, 1989, 1990
;
;   Title:	vddgrab.asm - grabber support
;
;   Version:	1.00
;
;   Date:	20-Jan-1992
;
;   Author:	RAP
;
;------------------------------------------------------------------------------
;
;   Change log:
;
;      DATE	REV		    DESCRIPTION
;   ----------- --- -----------------------------------------------------------
;   20-Jan-1992 RAP
;
;==============================================================================

	.386p

.xlist
	INCLUDE VMM.INC
	INCLUDE OPTTEST.INC
	INCLUDE VDD.INC
	INCLUDE DEBUG.INC
	INCLUDE VDDDEF.INC
	INCLUDE VDDPHMEM.INC
	INCLUDE VDDVMMEM.INC
.list


VxD_DATA_SEG
	EXTRN	Vid_Focus_VM:DWORD
	EXTRN	Vid_Flags:DWORD
VxD_DATA_ENDS

VxD_CODE_SEG
	EXTRN	VDD_State_Scrn_Off:NEAR
	EXTRN	VDD_State_Scrn_On:NEAR
	EXTRN	VDD_State_Begin_SR_Section:NEAR
	EXTRN	VDD_State_End_SR_Section:NEAR
	EXTRN	VDD_PH_Mem_Get_Visible_Pages:NEAR
	EXTRN	VDD_PH_Mem_CalcPageAddr:NEAR
	EXTRN	VDD_VM_Mem_Get_PTE:NEAR
	EXTRN	VDD_VM_Mem_Record_VRAM_Mod:NEAR
	EXTRN	VDD_VM_Mem_Save_Page:NEAR
	EXTRN	VDD_VM_Mem_Is_Page_Dirty:NEAR
	EXTRN	VDD_VM_Mem_Adjust_Plane_Sizes:NEAR
	EXTRN	VDD_VM_Mem_Dealloc:NEAR
	EXTRN	VDD_VM_Mem_Realloc:NEAR
	EXTRN	VDD_VM_Mem_Realloc_Plane:NEAR

;******************************************************************************
;
;   VDD_Grab_DoGrab
;
;   DESCRIPTION:    Allocate copy memory, call VDD_Grab_Save_Dirty_Pages
;		    to force save memory to contain all resent changes, then
;		    copy current video memory state from save memory to copy
;		    memory.
;
;   ENTRY:	    EBX = VM handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    Carry set, if memory alloc failed
;
;   USES:	    EAX, ECX, ESI, Flags
;
;==============================================================================
BeginProc VDD_Grab_DoGrab

Assert_VDD_ptrs ebx,edi

	cmp	ebx, [Vid_Focus_VM]
	jne	short g_not_focus

	call	VDD_Grab_ACopy
	jc	short g_alloc_failed

	call	VDD_State_Scrn_Off	    ; turn off screen for user feedback
;

	TestMem [edi.VDD_Flags], fVDD_NoSaveRes ;Q: auto res disabled?
	jnz	DEBFAR g_abnormal_grab		;   Y: do abnormal grab

; save any dirty video pages into the VM's video save memory
;
	call	VDD_Grab_Save_Dirty_Pages
%OUT optimization - save only dirty visible pages

;
; copy save memory to copy memory
;
	push	edi
	lea	esi, [edi.VDD_MStt.MSS_plane0]
	lea	edi, [edi.VDD_MSttCopy.MSS_plane0]

	mov	ecx, 4
g_copy_planes:
	push	ecx
	movzx	ecx, [edi.MSS_plane_size]   ;Q: have plane memory for copy?
	jecxz	short g_no_plane_mem	    ;	N: skip plane
	push	esi
	push	edi
	mov	esi, [esi.MSS_plane_addr]
	mov	edi, [edi.MSS_plane_addr]
	cld
	shl	ecx, 12-2		    ; convert # of pages to # of dwords
	rep	movsd
	pop	edi
	pop	esi
g_no_plane_mem:
	add	esi, SIZE MSS_Plane_Info_Struc
	add	edi, SIZE MSS_Plane_Info_Struc
	pop	ecx
	loop	g_copy_planes
	pop	edi

g_done:
	call	VDD_State_Scrn_On	    ; turn screen back on
;;	Trace_Out 'Grab done'
	clc
	ret

g_alloc_failed:
	Debug_Out 'failed to allocate memory for grab'
	call	VDD_Grab_DCopy
	jmp	short g_fail

g_not_focus:
	Debug_Out "GRAB for VM other than focus - should not get this - GRAB IGNORED!!"
g_fail:
	stc
	ret

;
; abnormal grab is done when a VM has done the INT2F to inform us that it
; CanRestore and AutoRestore has been disabled with the INI switch.  In this
; case the VM does not have any save memory allocated, so we copy MSttCopy
; into MStt so that the copy memory looks like save memory.  Then we call
; VDD_VM_Mem_Save_Page for all visible pages to copy the physical video
; memory state into the copy memory, and then we clear MStt.
;
g_abnormal_grab:
;
; copy memory state in VDD_MSttCopy to VDD_MStt
;
	push	edi
	lea	esi, [edi.VDD_MSttCopy]
	lea	edi, [edi.VDD_MStt]
	mov	ecx, (SIZE Mem_State_Struc) / 4
	cld
	rep	movsd
	pop	edi

;
; call save_page for all visible pages to save video memory into copy memory
;
	call	VDD_PH_Mem_Get_Visible_Pages ; returns eax = first page id
					     ; ecx = # of pages
	mov	esi, [edi.VDD_PageMap]
	lea	esi, [esi][eax*4]
g_loop:
	mov	eax, [esi]
	or	eax, eax
	jz	short g_next
	pushad
	call	VDD_VM_Mem_Save_Page
	popad
g_next:
	add	esi, 4
	loop	g_loop

;
; clear VDD_MSttCopy
;
	push	edi
	lea	edi, [edi.VDD_MStt]
	xor	eax, eax
	mov	ecx, (SIZE Mem_State_Struc) / 4
	cld
	rep	stosd
	pop	edi
	jmp	g_done

EndProc VDD_Grab_DoGrab


;******************************************************************************
;
;   VDD_Grab_ACopy
;
;   DESCRIPTION:    Allocate copy memory (VDD_MSttCopy)
;
;   ENTRY:	    EBX = VM handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    Carry set, if allocation failed
;
;   USES:	    ESI, Flags
;
;==============================================================================
BeginProc VDD_Grab_ACopy

Assert_VDD_ptrs ebx,edi
	lea	esi, [edi.VDD_MSttCopy]
	or	edx, -1 		; don't alloc font plane for text modes
	call	VDD_VM_Mem_Adjust_Plane_Sizes
	call	VDD_VM_Mem_Realloc	; Realloc the memory

	ret

EndProc VDD_Grab_ACopy


;******************************************************************************
;
;   VDD_Grab_DCopy
;
;   DESCRIPTION:    Deallocate copy memory (VDD_MSttCopy)
;
;   ENTRY:	    EBX = VM handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    none
;
;   USES:	    ESI, Flags
;
;==============================================================================
BeginProc VDD_Grab_DCopy

Assert_VDD_ptrs ebx,edi
;;	Trace_Out 'Grab_DCopy'
	lea	esi, [edi.VDD_MSttCopy]
	call	VDD_VM_Mem_Dealloc
	ret

EndProc VDD_Grab_DCopy

;******************************************************************************
;
;   VDD_Grab_Get_Text_Copy_Buf
;
;   DESCRIPTION:    Allocate a copy memory buffer for the grabber.
;
;   ENTRY:	    EBX = VM handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    EDX = copy buffer address (or 0)
;		    ECX = copy buffer size
;
;   USES:	    Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_Grab_Get_Text_Copy_Buf

Assert_VDD_ptrs ebx,edi
	call	VDD_PH_Mem_Get_Visible_Pages	; ECX = size of vis pgs
	lea	esi, [edi.VDD_Copy_Buf]
	cmp	cx,[esi.MSS_plane_alloced]	; Q: Already correct size?
	jne	SHORT GTCB_Alloc		;   N: go realloc
	cmp	[esi.MSS_plane_addr],0		; Q: Any memory alloced?
	jnz	SHORT GTCB_Exit 		;   Y: just return
GTCB_Alloc:
	cmp	cx,[esi.MSS_plane_alloced]	; Q: Shrinking mem alloc?
	ja	SHORT GTCB_Grow 		;   N: Do alloc
	TestMem [edi.VDD_PIF], fVidRetainAllo	; Q: PIF requested no mem shrink?
	jnz	SHORT GTCB_Exit 		;   Y: Don't shrink it.
GTCB_Grow:
IFDEF CPDEBUG
	push	eax
	mov	ax,[esi.MSS_plane_size]
Trace_Out "Realloc copy buf from #AX to #CX"
	pop	eax
ENDIF
	mov	[esi.MSS_plane_size], cx
	call	VDD_VM_Mem_Realloc_Plane
GTCB_Exit:
	mov	edx, [esi.MSS_plane_addr]	; EDX = memory address
	movzx	ecx, [esi.MSS_plane_alloced]
	ret

EndProc VDD_Grab_Get_Text_Copy_Buf


;******************************************************************************
;
;   VDD_Grab_Delete_Text_Copy_Buf
;
;   DESCRIPTION:    Free grabber copy memory buffer, if it exists.
;
;   ENTRY:	    EBX = VM handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    none
;
;   USES:	    Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_Grab_Delete_Text_Copy_Buf

Assert_VDD_ptrs ebx,edi
IFDEF CPDEBUG
Trace_Out "Delete copy buf"
ENDIF
	TestMem [edi.VDD_PIF], fVidRetainAllo	; Q: PIF requested no mem shrink?
	jnz	SHORT dtcb_no_plane_mem 	;   Y: don't dealloc it.
	xor	eax, eax
	mov	[edi.VDD_Copy_Buf.MSS_plane_addr], eax
	mov	[edi.VDD_Copy_Buf.MSS_plane_size], ax
	mov	[edi.VDD_Copy_Buf.MSS_plane_alloced], ax
	xchg	eax, [edi.VDD_Copy_Buf.MSS_plane_handle]
	or	eax, eax
	jz	short dtcb_no_plane_mem
	VMMCall _PageFree,<eax, 0>
dtcb_no_plane_mem:
	ret

EndProc VDD_Grab_Delete_Text_Copy_Buf


;******************************************************************************
;
;   VDD_Grab_Change_Query
;
;   DESCRIPTION:    Check if any mods recorded in mod array, or if any
;		    mapped pages have been dirtied, to determine if
;		    the VM's window should be updated.
;
;   ENTRY:	    EBX = VM handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    Carry set, if update needed
;
;   USES:	    EAX, Flags
;
;==============================================================================
BeginProc VDD_Grab_Change_Query

Assert_VDD_ptrs ebx,edi
	mov	eax, [edi.VDD_VRAM_Mods]    ;Q: mods recorded in mod array?
IFDEF Ext_VGA
	or	eax, [edi.VDD_VRAM_Mods+4]
.errnz VRAM_Mod_List_Size - 64	; error if not 2 dwords
ELSE
	or	eax, eax
ENDIF
	stc
	jnz	short cq_exit		    ;	Y: return carry set

 	cmp	[edi.VDD_Mod_Rect],0FFFF0000h ; maintained rect 0 ?
 	stc
 	jnz	short cq_exit		    ;   no...

	pushad
	call	VDD_PH_Mem_Get_Visible_Pages ; returns eax = first page id
	mov	edx, ecx		    ; edx = # of pages
	call	VDD_PH_Mem_CalcPageAddr
	mov	ecx, eax
	shl	ecx, 12
	add	ecx, [ebx.CB_High_Linear]
	shr	ecx, 12
	shl	edx, 2
	sub	esp, edx		    ; reserve dword for page table copy
	mov	eax, esp
	shr	edx, 2
	push	edx			    ; save # of pages

	VMMCall _CopyPageTable,<ecx,edx,eax,0>

	pop	ecx			    ; pop # of pages
	mov	eax, esp
	lea	edx, [ecx*4]
	xor	ebx, ebx
cq_chk_pgs:
	or	bl, byte ptr [eax]	    ; or all of the access bits together
	add	eax, 4
	loop	cq_chk_pgs
	add	esp, edx
	bt	ebx, P_DIRTYBit
	popad
cq_exit:
	ret

EndProc VDD_Grab_Change_Query


;******************************************************************************
;
;   VDD_Grab_Clear_Mod_State
;
;   DESCRIPTION:    Clear the screen modified bit in the VM flags (VDD_Flags)
;		    and clear the VDD_VRAM_Mods table.
;
;   ENTRY:	    EBX = VM handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    none
;
;   USES:	    EAX, ECX, Flags
;
;==============================================================================
BeginProc VDD_Grab_Clear_Mod_State

IFDEF DEBUG_verbose
;;	  Trace_Out 'c',noeol
ENDIF

Assert_VDD_ptrs ebx,edi
	mov	ecx, VRAM_Mod_List_Size/4
	push	edi
	lea	edi, [edi.VDD_Grab_Mods]
	cld
	xor	eax, eax
	rep	stosd
	pop	edi

	ret

EndProc VDD_Grab_Clear_Mod_State


;******************************************************************************
;
;   VDD_Grab_Save_Dirty_Pages
;
;   DESCRIPTION:    Walk thru list of all video pages owned by a VM, force
;		    any dirtied pages to be saved to the VM's save memory
;		    and clear all dirty bits.
;
;   ENTRY:	    EBX = VM handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    none
;
;   USES:	    EAX, ECX, Flags
;
;==============================================================================
BeginProc VDD_Grab_Save_Dirty_Pages

Assert_VDD_ptrs ebx,edi
IFDEF DEBUG_verbose
	Trace_Out 'D',noeol
	call	VDD_State_VM_Debug
ENDIF
	push	esi
	mov	esi, [edi.VDD_PageMap]
	xor	ecx, ecx
sdp_loop:
	mov	eax, [esi][ecx*4]
	or	eax, eax
	jz	short sdp_check_PTE

	call	VDD_VM_Mem_Is_Page_Dirty    ;Q: page dirty?
	jz	short sdp_next		    ;	N:
	push	ecx
	push	esi

; copy video memory to VM's save memory
	call	VDD_State_Begin_SR_Section
	call	VDD_VM_Mem_Save_Page

; clear the dirty bit in the page table, since we've copied the memory
	movzx	ecx, [eax.PDS_linear_page]
	jecxz	short sdp_not_mapped
sdp_save_dirty:
	push	ecx
	VMMCall _ModifyPageBits,<ebx,ecx,1,0FFFFFFFFh,0,PG_IGNORE,0>
	pop	ecx
;
; Touch page to set its accessed bit so that we don't think that we are in
; a dead lock situation at page fault time.  Basically, in the unmap page
; routine we check to see if we are unmapping a page that hasn't been
; accessed.  If we are processing a page fault, then that means that the
; page is probably being unmapped because it is being demanded to satisfy
; a request for a different page.  If this is the case, then we assume that
; we've reached a dead lock situation where we are trying to satisfy requests
; for 2 video pages at the same time when there is only 1 page of video memory
; available.  To break out of this deadlock situation we force the VM to
; full screen.	If we don't preserve the access bit here, then we can wrongly
; detect that this page hasn't been accessed and convert a VM to fullscreen.
;
	shl	ecx, 12 		    ; convert to linear address
	add	ecx, [ebx.CB_High_Linear]
	mov	cl, [ecx]

sdp_not_mapped:

	pop	esi
	pop	ecx
	mov	eax, [edi.VDD_PageFlags]
	or	byte ptr [eax][ecx], fPageSaved
	mov	eax, ecx
	call	VDD_VM_Mem_Record_VRAM_Mod
sdp_next:
	inc	ecx
	cmp	ecx, [edi.VDD_VideoPages]
	jb	sdp_loop
	pop	esi
	TestMem [Vid_Flags], fVid_SR_Section
	jz	short @F
	call	VDD_State_End_SR_Section
@@:
	ret

sdp_check_PTE:
	push	ecx
	push	esi
	mov	eax,ecx
	call	VDD_PH_Mem_CalcPageAddr
	cmp	eax, 0C0h		    ;Q: page in range of video memory?
	jae	short sdp_not_valid	    ;	N: skip it
	push	eax
	mov	ecx,eax
	call	VDD_VM_Mem_Get_PTE
	test	cl, P_DIRTY		    ; isolate dirty bit
	jnz	short sdp_is_dirty
	add	esp,4
sdp_not_valid:
	pop	esi
	pop	ecx
	jmp	sdp_next
sdp_is_dirty:
	pop	ecx
	jmp	sdp_save_dirty

EndProc VDD_Grab_Save_Dirty_Pages


;******************************************************************************
;
;   VDD_Grab_Get_Chgs
;
;   DESCRIPTION:    Force dirty pages to be saved to the VM's save memory,
;		    OR dirty bits into the VDD_VRAM_Mods bit array and clear
;		    dirty bits.
;
;   ENTRY:	    EBX = VM handle
;		    EDI = VDD CB ptr
;		    ESI -> grabber's VDD_Mod_State buffer
;		    ECX = 0
;
;   EXIT:	    ECX = # of bytes in esi.VDD_Mod_List
;
;   USES:	    EAX, ECX, Flags
;
;==============================================================================
BeginProc VDD_Grab_Get_Chgs

Assert_VDD_ptrs ebx,edi
	call	VDD_Grab_Save_Dirty_Pages

	call	VDD_PH_Mem_Get_Visible_Pages ; returns eax = first page id
	SetFlag [esi.VDD_Mod_Flag], fVDD_M_VRAM;Y: Indicate modified pages
	mov	[esi.VDD_Mod_Count], cx     ; ecx = # of pages
	add	ecx, 7
	shr	ecx, 3			    ; 8 pages (bits) per byte
IFDEF DEBUG
	cmp	ecx, VRAM_Mod_List_Size
	jbe	SHORT VMGC_DBG0
Debug_Out "Visible pages exceeds VRAM_Mod_List_Size"
VMGC_DBG0:
ENDIF

	push	ebx
IFNDEF Ext_VGA
	push	ecx
	mov	ecx,eax
	xor	eax, eax
	xchg	eax, [edi.VDD_VRAM_Mods]
	or	eax, [edi.VDD_Grab_Mods]
	mov	[edi.VDD_Grab_Mods], eax
IFDEF	DEBUG_VERBOSE
	jecxz	SHORT StartPage0
	Trace_Out 'Grab_Get_Chgs: Starting Page = #cl, mods = #eax'
ENDIF
	shr	eax,cl
StartPage0:
	mov	dword ptr [esi.VDD_Mod_List], eax
	or	eax, eax		    ; Q: Any dirty pages to report?
	pop	ecx
	jnz	SHORT VMGC_ModPages	    ;	Y: All done
ELSE
	push	ecx
	push	esi
	push	edi
	xor	ch, ch
	lea	ebx, [edi.VDD_VRAM_Mods]
	lea	edi, [edi.VDD_Grab_Mods]
	lea	esi, [esi.VDD_Mod_List]
	xchg	edi,esi
	cld

VMGC_ModPageLoop:
	mov	al,BYTE PTR [ebx]	    ; Get current VRAM_Mods pages
	mov	BYTE PTR [ebx], 0	    ;	and clear them
	or	al, BYTE PTR [esi]	    ; diff of VRAM and grabber state
	mov	BYTE PTR [esi], al	    ; Combine with grabber state
	or	ch,al			    ; Remember if any modified pages
	stosb				    ; Save new value in grabber data
	inc	ebx
	inc	esi
	dec	cl
	jnz	VMGC_ModPageLoop

	pop	edi
	pop	esi
	or	ch,ch			    ; Q: Any dirty pages to report?
	pop	ecx
	jnz	SHORT VMGC_ModPages	    ;	Y: All done
ENDIF
    ;
    ; for VGA31 grabbers, we keep track of mod_rect. If VDD_Mod_Rect
    ; is 0FFFF0000h, then there are no mods. else there are and we 
    ; return 0 in ecx
    ;
 	cmp	[edi.VDD_Mod_Rect],0FFFF0000h ; Q: any emulation of WriteTTY
	jnz	short VMGC_Mod_Emulated       ;   Y: we are maintaining a rect!
	and	[esi.VDD_Mod_Flag], NOT fVDD_M_VRAM;N: Clear mod'd pages flag
	xor	ecx,ecx 		    ; No pages in mod'd pages list
VMGC_Mod_Emulated:
 	pop	ebx
 	ret
VMGC_ModPages:
 	mov	[edi.VDD_Mod_Rect],-1	    ; APP TOUCHED IT DIRECTLY...
	pop	ebx
	ret

EndProc VDD_Grab_Get_Chgs

VxD_CODE_ENDS

END
