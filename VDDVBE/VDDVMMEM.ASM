PAGE 58,132
;******************************************************************************
TITLE vddvmmem.asm -
;******************************************************************************
;
;   (C) Copyright MICROSOFT Corp.  All Rights Reserved, 1986 - 1991
;
;   Title:	vddvmmem.asm -
;
;	    This module handles all of the manipulation of a VM's video memory
;	space. This includes mapping of physical device, mapping normal RAM for
;	emulation of physical device and null pages.  The pages are disabled 
;	and hooked when they have not been allocated to the VM and when the
;	mode of the controller has changed.
;
;   Version:	1.00
;
;   Date:	14-Jun-1990
;
;   Author:	RAP
;
;------------------------------------------------------------------------------
;
;   Change log:
;
;      DATE	REV		    DESCRIPTION
;   ----------- --- -----------------------------------------------------------
;   14-Jun-1990 RAP
;
;==============================================================================

	.386p

.xlist
	INCLUDE VMM.INC
	INCLUDE OPTTEST.INC
	INCLUDE VDD.INC
	INCLUDE VDD2.INC
	INCLUDE DEBUG.INC
	INCLUDE VDDDEF.INC
	INCLUDE VDDPHMEM.INC
	INCLUDE VDDVMMEM.INC
.list

;******************************************************************************
; EXTRN routines
;
VxD_CODE_SEG
	EXTRN	VDD_Error_NoPagesAvail:NEAR
	EXTRN	VDD_Error_NoMainMem:NEAR
	EXTRN	VDD_Error_Cvt_FullScrn:NEAR
	EXTRN	VDD_State_Set_MemC_Owner:NEAR
	EXTRN	VDD_State_Clear_MemC_Owner:NEAR
	EXTRN	VDD_State_Set_MemC_Planar:NEAR
	EXTRN	VDD_State_Get_Mem_Mapping:NEAR
	EXTRN	VDD_State_Save_CRTC_Owner:NEAR
	EXTRN	VDD_State_Begin_SR_Section:NEAR
	EXTRN	VDD_State_End_SR_Section:NEAR
	EXTRN	VDD_State_Set_Latches_Owner:NEAR
IFDEF DEBUG
	EXTRN	VDD_State_Schedule_Debug_Event:NEAR
ENDIF
	EXTRN	VDD_Proc_Chk_Bkgnd_Usage:NEAR
	EXTRN	VDD_Proc_Notify_Bkgnd_VMs:NEAR
	EXTRN	VDD_Proc_BGrnd_Notify:NEAR
	EXTRN	VDD_Proc_Force_Cur_VM_Fgrnd:NEAR
	EXTRN	VDD_PH_Mem_Shared_Page:NEAR
	EXTRN	VDD_PH_Mem_Get_Visible_Pages:NEAR
	EXTRN	VDD_PH_Mem_Alloc_Video_Page:NEAR
	EXTRN	VDD_PH_Mem_Free_Page:NEAR
	EXTRN	VDD_PH_Mem_Get_Page_Owner:NEAR
	EXTRN	VDD_PH_Mem_Access_Page:NEAR
	EXTRN	VDD_PH_Mem_Page_Accessible:NEAR
	EXTRN	VDD_PH_Mem_CalcPageId:NEAR
	EXTRN	VDD_PH_Mem_CalcPageAddr:NEAR
	EXTRN	VDD_PH_Mem_CalcPagePhys:NEAR
	EXTRN	VDD_PH_Mem_Release_Page:NEAR
	EXTRN	VDD_PH_Mem_Change_Page:NEAR
	EXTRN	VDD_PH_Mem_update_LRU:NEAR
	EXTRN	VDD_PH_Mem_Mapped_Phys:NEAR
	EXTRN	VDD_PH_Mem_LRU_Sweep:NEAR
	EXTRN	VDD_PH_Mem_Set_Latch_Addr:NEAR
	EXTRN	VDD_PH_Mem_Clear_MemC_mods:NEAR
	EXTRN	VDD_Font_save_font:NEAR
	EXTRN	VDD_Font_restore_font:NEAR
	EXTRN	VDD_OEM_Adjust_Font_Access:NEAR
	EXTRN	VDD_Grab_Delete_Text_Copy_Buf:NEAR
	EXTRN	VDD_Grab_Clear_Mod_State:NEAR

IFDEF IBMXGA
	EXTRN	VDD_OEM_Chk_DoubleWord:NEAR
	EXTRN	VDD_OEM_Restore_DoubleWord:NEAR
ENDIF
IFDEF TLVGA
	EXTRN	VDD_OEM_TLVGA_Set_Graphics:NEAR
	EXTRN	VDD_OEM_TLVGA_Reset_Graphics:NEAR
ENDIF
IFDEF Ext_VGA
	EXTRN	VDD_PH_Mem_Get_First_PageId_of_Bank:NEAR
	EXTRN	VDD_PH_Mem_Assign_Video_Page:NEAR
	EXTRN	VDD_PH_Mem_Get_Alt_Bank_Page:NEAR
ENDIF
IFDEF	PVGA	;******************* C. Chiang
	EXTRN	VDD_OEM_PVGA_Adjust_Page_Mode_Regs:NEAR
	EXTRN	VDD_OEM_PVGA_Adjust_Page_Mode_X_Regs:NEAR
ENDIF	;PVGA
VxD_CODE_ENDS

;******************************************************************************
; EXTRN data
;
VxD_IDATA_SEG
	EXTRN	VDD_Rsrv_C6C7_Ini:BYTE
	EXTRN	VDD_Mono_Text_Ini:BYTE
	EXTRN	VDD_2nd_Ini:BYTE
	EXTRN	VDD_VM_SaveRes_Ini:BYTE
	EXTRN	VDD_Str_CheckVidPgs:BYTE
	EXTRN	VDD_BkGnd_Notify_Time:BYTE
	EXTRN	Vid_Shadow_Mem_Status_Ptr:DWORD

PUBLIC VMPagesBuf
VMPagesBuf	dd  9 dup (?)			       ; Buf for reserving pgs

VxD_IDATA_ENDS

VxD_DATA_SEG
	EXTRN	Vid_Flags:DWORD
	EXTRN	VT_Flags:DWORD
	EXTRN	Vid_Focus_VM:DWORD
	EXTRN	Vid_CRTC_VM:DWORD
	EXTRN	Vid_MemC_VM:DWORD
	EXTRN	Vid_Msg_Pseudo_VM:DWORD
	EXTRN	Vid_PhysA0000:DWORD
	EXTRN	Vid_Msg_VM:DWORD
	EXTRN	Vid_Initial_Text_Rows:BYTE
	EXTRN	Vid_Msg_Pages:BYTE
	EXTRN	Vid_Scroll_Freq:DWORD
	EXTRN	VDD_SuspMsg_Ini:BYTE
	EXTRN	VDD_NoSusp_Ini:BYTE
;FROM VDDPHMEM.ASM
	EXTRN	Video_Pages:DWORD

Reserved_ROM_Page   dd	?	; C6 or E6

Vid_PageAllocFlags  dd	PageZeroInit OR PageLocked

Vid_Unaccessed_Page dd	0	; Set by VDD_VM_Mem_Unmap_Page as the page
				; handle of a page that was never accessed
				; before it was unmapped

VxD_DATA_ENDS


VxD_ICODE_SEG

	EXTRN	VDD_Font_Init_Complete:NEAR


;******************************************************************************
;
;   VDD_VM_Mem_Device_Init
;
;   DESCRIPTION:    Allocate pagemaps for SYS VM.  Read auto restore INI
;		    switches.  Reserve and hook video pages A0-AF, B8-BF and
;		    B0-B7, if necessary.  Hook ROM pages C6 and C7 on machines
;		    where the video ROM BIOS is not properly identified.
;		    And hook in the VDD's page fault handler, VDD_PFault.
;
;   ENTRY:	    EBX = SYS VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    Carry clear, or Fatal_Error called
;
;   USES:	    EAX, ECX, EDX, ESI, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Device_Init

	Assert_VDD_ptrs ebx,edi

	mov	eax, [Video_Pages]
	call	VDD_VM_Mem_Alloc_PageMaps

IF 0
;
; The following switch was removed from 3.1 for lack of testing.  I didn't
; want to document a switch controlled feature that hadn't gotten enough
; testing.
;

VxD_IDATA_SEG
	EXTRN	VDD_SysVM_SaveRes_Ini:BYTE
VxD_IDATA_ENDS

;
; Check for auto save/restore of SYS VM INI switch
;
	xor	eax, eax			; default to false
	xor	esi, esi			; [WIN386] section
	push	edi
	mov	edi, OFFSET32 VDD_SysVM_SaveRes_Ini
	VMMCall Get_Profile_Boolean
	pop	edi
	or	eax, eax			;Q: save/restore SYS VM
	jnz	short VSIV_sys_saveres		;   Y: Yes, don't set flag
ENDIF

	SetFlag [edi.VDD_TFlags], fVT_NoSaveResSysVM
	Trace_Out 'auto save/restore of SYS VM disabled'
VSIV_sys_saveres:

;
; Check for no suspend in background INI switch
;
	xor	eax,eax
	xor	esi, esi			; [WIN386] section
	push	edi
	mov	edi, OFFSET32 VDD_NoSusp_Ini
	VMMCall Get_Profile_Boolean
	pop	edi
	or	eax, eax			;Q: Suspend VMs in background?
	jz	short VSIV_SuspendVM		;   N: Continue
	SetFlag [edi.VDD_TFlags],fVT_NoSuspend
VSIV_SuspendVM:

;
; Check for no message on suspend or video corruption in background INI switch
;
	or	eax, -1
	xor	esi, esi			; [WIN386] section
	push	edi
	mov	edi, OFFSET32 VDD_SuspMsg_Ini
	VMMCall Get_Profile_Boolean
	pop	edi
	or	eax, eax			;Q: Give background suspend msg
	jnz	short VSIV_GiveSuspMsg		;   Y: Continue
	SetFlag [edi.VDD_TFlags],fVT_SuprsMsg
VSIV_GiveSuspMsg:
;
; Check for auto save/restore of other intelligent VMs INI switch
;
	or	eax, -1
	xor	esi, esi			; [WIN386] section
	push	edi
	mov	edi, OFFSET32 VDD_VM_SaveRes_Ini
	VMMCall Get_Profile_Boolean
	pop	edi
	or	eax, eax			;Q: save/restore other VMs
	jnz	short VSIV_saveres		;   Y: Don't set flag
	SetFlag [edi.VDD_TFlags], fVT_NoSaveResOthers
	Trace_Out 'auto save/restore of other VMs disabled'
VSIV_saveres:

;
; Check for background notify time INI switch
;
IFDEF VGA8514
	xor	eax, eax			; default to FALSE
ELSE
	or	eax, -1 			; default to TRUE
ENDIF
	xor	esi, esi			; [WIN386] section
	push	edi
	mov	edi, OFFSET32 VDD_BkGnd_Notify_Time
	VMMCall Get_Profile_Boolean
	pop	edi
	or	eax, eax			;Q: save/restore other VMs
	jz	short VSIV_not_pftime		;   N: Don't set flag
	SetFlag [edi.VDD_TFlags], fVT_Notify_at_PF
	Trace_Out 'notify bkgnd at pfault time'
VSIV_not_pftime:

;**********************************************************************
; Reserve and hook pages A0-AF and B8-BF  AND
;
;   IF
;	1) Secondary VDD does not exist (it will reserve it)
;	    AND
;	2) "DUALDISPLAY=YES" OR Secondary display is detected
;	    AND
;	3) Other VxD (e.g. Upper Memory Blocks) has not reserved pages B0-B7
;
;   THEN Reserve and map pages B0-B7 physical for secondary display
;
;   ELSE IF
;	1) Secondary VDD does not exist (it will reserve it)
;	    AND
;	2) "DUALDISPLAY=NO" OR Secondary display is not detected
;	    AND
;	3) NOT ("VGAMONOTEXT=NO")
;	    AND
;	4) "VGAMONOTEXT=YES" OR Windows started when video in mono mode
;	    AND
;	5) Other VxD (e.g. Upper Memory Blocks) has not reserved pages B0-B7
;
;   THEN Reserve and hook pages B0-B7 for VGA mono support
;
;   ELSE VGA Mono not supported, pages B0-B7 not handled
;
; If user sets "DUALDISPLAY=NO" with monochrome adapter attached the results
;	are undefined.
;
;*******
; Note that fVT_Mono has been set if user started Windows in mono video mode
;
	VxDCall VDD2_Get_Version		; Q: 2nd VDD exist?
	jnc	VDD_SI_B0_No_Mono_Support	;   Y: Don't support B0-B7

	xor	esi,esi 			; [WIN386] section
	push	edi
	mov	edi, OFFSET32 VDD_2nd_Ini	; Find this string
	VMMcall Get_Profile_Boolean		; Q: DUALDISPLAY Value spec'd?
	pop	edi
	jc	SHORT VDD_SI_B0_Check		;   N: Check for mono display
	jz	SHORT VDD_SI_B0_Check		;   N: Check for mono display

	or	eax,eax 			;   Y: Q: DUALDISPLAY=YES?
IFDEF	VGAMONO
	jz	SHORT VDD_SI_Not_Dual_Display	;	N: DUALDISPLAY=NO
VDD_SI_Is_Dual_Display:
	ClrFlag [edi.VDD_TFlags], fVT_Mono	    ;	    Y: No VGA mono,
	SetFlag [edi.VDD_TFlags],fVT_ResvB0	    ;	       but we own B0-B7
ELSE
	jz	VDD_SI_B0_Done			;	N: Leave memory alone
ENDIF
	jmp	short VDD_SI_B0_Resv		;	   go reserve memory

;*******
; No DUALDISPLAY .INI switch,
;   check for memory at B0000 with VGA not mapped at B0000
;
VDD_SI_B0_Check:
	mov	dx,pGrpIndx
	in	al,dx
	mov	ah,al
	mov	al,6
	out	dx,al
	inc	edx
	in	al,dx
	push	eax
	or	al,0Ch				; Force mapping at B8000
	out	dx,al
	mov	esi,[Vid_PhysA0000]
	add	esi,0B0000h-0A0000h
	mov	ax,[esi]			; read original
	mov	ecx, eax
	xor	cx,05555h			; write modified value
	mov	[esi], cx
	xchg	ax, [esi]			; restore original
	cmp	eax,ecx 			; Q: Memory at B0000h?
IFNDEF	 VGAMONO
	pop	eax
	pushfd
	out	dx,al				; Restore graphics controller
	dec	edx
	mov	al,ah
	out	dx,al
	popfd
	jnz	VDD_SI_B0_Done			;   N: All done
ELSE
	jne	SHORT VDD_SI_B0_Chk_Done	;   N: Not a dual display
	add	esi, 2
	mov	ax, [esi]			; read 2nd original to verify
	mov	ecx, eax
	xor	cx,0AAAAh			; write modified value
	mov	[esi], cx
	xchg	ax, [esi]			; restore original
	cmp	eax, ecx			; Q: Memory at B0000h?
VDD_SI_B0_Chk_Done:
	pop	eax
	pushfd
	out	dx,al				; Restore graphics controller
	dec	edx
	mov	al,ah
	out	dx,al
	popfd
	je	SHORT VDD_SI_Is_Dual_Display	;   Y: This is dual display

;*******
; Either "DualDisplay=NO" or did not find memory at pages B0-B7
;	Check for "VGAMonoText=NO"
VDD_SI_Not_Dual_Display:
	xor	esi,esi 			; [WIN386] section
	push	edi
	or	eax, -1 			; default to TRUE
	mov	edi, OFFSET32 VDD_Mono_Text_Ini ; Find this string
	VMMcall Get_Profile_Boolean		; Q: VGAMonoText spec'd?
	pop	edi
	SetFlag [edi.VDD_TFlags],fVT_Mono	; Assume want Mono support
	or	eax,eax 			; Q: VGAMonoText=TRUE?
	jnz	SHORT VDD_SI_B0_Resv		;   Y: Reserve the memory
	jmp	SHORT VDD_SI_B0_No_Mono_Support ;   N: No mono support

;*******
; VGAMONOTEXT not specified.
;   If were in mono when started windows, include mono support, else skip it
;
VDD_SI_B0_Maybe_Resv:
	TestMem [edi.VDD_TFlags],fVT_Mono	; Q: Mono on start up?
	jz	SHORT VDD_SI_B0_Done		;   N: All done
Assumes_Fall_Through VDD_SI_B0_Resv		;   Y: Try to reserve the mem
ENDIF

;*******
; Attempt to reserve B0-B7
;   If not successful, clear fVT_Mono (may be set) and fVT_ResvB0
;
VDD_SI_B0_Resv:
IFDEF	DEBUG
	xor	eax,eax
	VMMCall _Get_Device_V86_Pages_Array,<eax,<OFFSET32 VMPagesBuf>,eax>
	mov	eax,[VMPagesBuf+((0A0h/32)*4)]
	test	eax,000FF0000h			;   N: Q: B0-B7 already resvd?
	jnz	SHORT VDD_SI_B0_Cant_resv	;	Y: Forget it (weird)
ENDIF
	xor	eax,eax
	VMMCall _Assign_Device_V86_Pages,<0B0h,8,eax,eax>
	or	eax,eax 			; Q: Successful?
	jnz	SHORT VDD_SI_B0_Done		;   Y: Either Mono VGA or
						;	dual display

;*******
; No Mono VGA support or dual display support
;
VDD_SI_B0_Cant_resv:
	Trace_Out "VDD: Mono pages already reserved: #EAX"

VDD_SI_B0_No_Mono_Support:
	ClrFlag [edi.VDD_TFlags], <fVT_Mono+fVT_ResvB0>

;*******
; Either B0-B7 reserved or not, and
;	if reserved, if fVT_Mono set, VGA mono supported
;	    else B0-B7 should be mapped physical (dual display)
VDD_SI_B0_Done:
IFDEF	DEBUG
	TestMem [edi.VDD_TFlags],fVT_Mono
	jz	SHORT VDD_SI_B0_DBG1
Trace_Out "VGA Mono text support"
VDD_SI_B0_DBG1:
	TestMem [edi.VDD_TFlags],fVT_ResvB0
	jz	SHORT VDD_SI_B0_DBG2
Trace_Out "Secondary Mono text support"
VDD_SI_B0_DBG2:
ENDIF

	xor	eax,eax
	VMMCall _Get_Device_V86_Pages_Array,<eax,<OFFSET32 VMPagesBuf>,eax>
	mov	eax,[VMPagesBuf+((0A0h/32)*4)]
	test	eax,0FF00FFFFh	; bits corresponding to A0-AF and B8-BF
	jz	SHORT VDD_SI_PagesFree
Debug_Out "VDD ERROR:  Video pages already allocated: #EAX"
	jmp	SHORT VDD_SI_ErrPgs

VDD_SI_PagesFree:
	xor	eax,eax
	VMMCall _Assign_Device_V86_Pages,<0A0h,16,eax,eax>
	or	eax,eax
	jnz	SHORT VDD_SI_GotGrap
Debug_Out "VDD ERROR:  Could not allocate A0-AF video pages"
	jmp	SHORT VDD_SI_ErrPgs

VDD_SI_GotGrap:
	xor	eax,eax
	VMMCall _Assign_Device_V86_Pages,<0B8h,8,eax,eax>
	or	eax,eax
	jnz	SHORT VDD_SI_GotText
Debug_Out "VDD ERROR:  Could not allocate B8-BF video pages"
VDD_SI_ErrPgs:
	Fatal_Error <OFFSET32 VDD_Str_CheckVidPgs>
	stc
	ret

VDD_SI_GotText:
IFDEF	RESERVEROMC6C7
;*******
; Many VGAs have ROM without signature at C6, C7 pages
;	Either the real mode INIT set fVT_RsrvC6C7 or
;	there is a SYSTEM.INI entry
	push	edi
	xor	esi,esi 			; [WIN386] section
	mov	edi, OFFSET32 VDD_Rsrv_C6C7_Ini ; Find this string
	VMMcall Get_Profile_Boolean		; Q: ReserveVideoRom spec'd?
	pop	edi
	jc	SHORT VDD_SI_GotROMIni		;   N: Continue
	jz	SHORT VDD_SI_GotROMIni		;   N: Continue
	ClrFlag [edi.VDD_TFlags], fVT_RsrvC6C7
	or	eax,eax 			;      Q: = TRUE?
	jz	SHORT VDD_SI_GotROMIni		;	N: leave flag clear
	SetFlag [edi.VDD_TFlags], fVT_RsrvC6C7
VDD_SI_GotROMIni:
	TestMem [edi.VDD_TFlags], fVT_RsrvC6C7
	jz	VDD_SI_Not_RsrvC6C7

	Push_Client_State
	VMMcall Begin_Nest_Exec 	; Get ready for software ints
	mov	[ebp.Client_AX], 1130h	; Get font ptr
	mov	[ebp.Client_BH], 2
	mov	eax,10h
	VMMcall Exec_Int
	movzx	ecx, [ebp.Client_ES]	; ES = ROM segment
	VMMcall End_Nest_Exec		; All done with software ints
	Pop_Client_State

; Reserve additional address space for ROM without ROM ID

	cmp	ch, 0C0h
	jb	short VDD_SI_Not_RsrvC6C7
	test	cx, 0FFFh
	jnz	short VDD_SI_Not_RsrvC6C7
	shr	ecx, 8			; C0 or E0
	mov	eax, ecx
	shr	eax, 5			; eax = ecx/32
	shl	eax, 2			; eax = (ecx/32)*4
	mov	eax, [VMPagesBuf+eax]
	test	al,11000000b
	jnz	SHORT VDD_SI_no_C6C7

	xor	eax,eax
	add	ecx, 6			; C6 or E6
	mov	[Reserved_ROM_Page], ecx
	VMMCall _Assign_Device_V86_Pages,<ecx,2,eax,eax> ; Reserve the address
	or	eax,eax
	jnz	SHORT VDD_SI_GotRom

VDD_SI_no_C6C7:
	ClrFlag [edi.VDD_TFlags], fVT_RsrvC6C7
	Trace_Out "VDD: C6-C7 ROM pages already allocated"

VDD_SI_GotRom:
VDD_SI_Not_RsrvC6C7:
ENDIF	;RESERVEROMC6C7

	mov	esi,OFFSET32 VDD_PFault
	mov	eax,0A0h
	mov	ecx,16
VDD_SI_NxtPgGrap:
	VMMCall Hook_V86_Page
	inc	eax
	loopd	VDD_SI_NxtPgGrap

	mov	eax,0B8h
	mov	ecx,8
VDD_SI_NxtPgText:
	VMMCall Hook_V86_Page
	inc	eax
	loopd	VDD_SI_NxtPgText

IFDEF	VGAMONO
	TestMem [edi.VDD_TFlags],fVT_Mono	; Q: Mono supported?
	jz	SHORT VDD_SI_NotMono		;   N: Don't hook pages
	mov	eax,0B0h			;   Y: Hook B0-B7
	mov	ecx,8
VDD_SI_NxtPgMono:
	VMMCall Hook_V86_Page
	inc	eax
	loopd	VDD_SI_NxtPgMono

VDD_SI_NotMono:
ENDIF
	mov	eax,[edi.VDD_TFlags]		; Update global flags
	mov	[VT_Flags],eax
	call	VDD_VM_Mem_Create_VM		; Init SYS VM control block
	call	VDD_VM_Mem_VM_Critical_Init	; Map the ROM in system VM
	ret

EndProc VDD_VM_Mem_Device_Init


;******************************************************************************
;
;   VDD_VM_Mem_Init_Complete
;
;   DESCRIPTION:    Init Vid_PageAllocFlags & call VDD_Font_Init_Complete
;
;   ENTRY:	    EBX = SYS VM Handle
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Init_Complete

	mov	[Vid_PageAllocFlags], PageZeroInit OR PageLockedIfDP
	CallRet VDD_Font_Init_Complete

EndProc VDD_VM_Mem_Init_Complete

VxD_ICODE_ENDS


VxD_CODE_SEG

;******************************************************************************
;
;   VDD_VM_Mem_Alloc_PageMaps
;
;   DESCRIPTION:    Allocate the 2 pagemap arrays that record which page handles
;		    are allocated for each virtual page # and flags for each
;		    virtual page #.
;
;   ENTRY:	    EBX = VM handle
;		    EDI -> VDD_CB_Struc
;		    EAX = new VDD_VideoPages value
;
;   EXIT:	    Carry set, if allocation failed
;
;   USES:	    EAX, ECX, EDX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Alloc_PageMaps

Assert_VDD_ptrs ebx,edi
	mov	[edi.VDD_VideoPages], eax
	shl	eax, 2
	VMMCall _HeapAllocate, <eax, HeapZeroInit>
	test	eax, eax
IFDEF DEBUG
	jnz	short apm_got_pagemap
	Debug_Out "VDD ERROR:  Could not allocate pagemap"
apm_got_pagemap:
ENDIF
	jz	short apm_exit
	mov	[edi.VDD_PageMap], eax

	mov	eax, [edi.VDD_VideoPages]
	VMMCall _HeapAllocate, <eax, HeapZeroInit>
	test	eax, eax
IFDEF DEBUG
	jnz	short apm_got_pageflags
	Debug_Out "VDD ERROR:  Could not allocate pageflags"
apm_got_pageflags:
ENDIF
	jz	short apm_exit
	mov	[edi.VDD_PageFlags], eax
	stc
apm_exit:
	cmc
	ret

EndProc VDD_VM_Mem_Alloc_PageMaps


;******************************************************************************
;
;   VDD_VM_Mem_Grow_PageMaps
;
;   DESCRIPTION:    Attempt to grow the 2 pagemap arrays for the given VM.
;
;   ENTRY:	    EBX = VM handle
;		    EDI -> VDD_CB_Struc
;		    EAX = new VDD_VideoPages value-1
;
;   EXIT:	    Carry set, if allocation failed
;
;   USES:	    ECX, EDX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Grow_PageMaps

Assert_VDD_ptrs ebx,edi
	push	eax
	inc	eax
	shl	eax, 2
	VMMCall _HeapReAllocate, <[edi.VDD_PageMap], eax, HeapZeroInit>
	test	eax, eax
IFDEF DEBUG
	jnz	short gpm_got_pagemap
Debug_Out "VDD ERROR:  Could not allocate pagemap"
gpm_got_pagemap:
ENDIF
	jz	short gpm_exit
	mov	[edi.VDD_PageMap], eax

	mov	eax, [esp]
	inc	eax
	VMMCall _HeapReAllocate, <[edi.VDD_PageFlags], eax, HeapZeroInit>
	test	eax, eax
IFDEF DEBUG
	jnz	short gpm_got_pageflags
Debug_Out "VDD ERROR:  Could not allocate pageflags"
gpm_got_pageflags:
ENDIF
	jz	short gpm_exit
	mov	[edi.VDD_PageFlags], eax
	mov	eax, [esp]
	inc	eax
	mov	[edi.VDD_VideoPages], eax
	stc
gpm_exit:
	cmc
	pop	eax
	ret

EndProc VDD_VM_Mem_Grow_PageMaps


;******************************************************************************
;
;   VDD_VM_Mem_VM_Critical_Init
;
;   DESCRIPTION:    Map physical pages for video BIOS pages 6 & 7 into the
;		    current VM, if the VDD reserved the pages in
;		    VDD_VM_Mem_Device_Init (usually these will be pages C6 & C7
;		    or E6 & E7).
;
;   ENTRY:	    EBX = VM handle
;		    EDI -> VDD CB data
;
;   EXIT:	    Carry cleared
;
;   USES:	    EDX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_VM_Critical_Init

IFDEF	ReserveROMC6C7
	TestMem [edi.VDD_TFlags], fVT_RsrvC6C7
	jz	SHORT VVCI_NoRsrvC6C7
	mov	edx, [Reserved_ROM_Page]
	VMMCall _PhysIntoV86,<edx,ebx,edx,2,0>	; Map Phys=Linr for BIOS pages 6 & 7
VVCI_NoRsrvC6C7:
ENDIF
	TestMem [edi.VDD_TFlags], fVT_ResvB0
	jz	SHORT VVCI_NoRsrvB0
	mov	edx, 0B0h
	VMMCall _PhysIntoV86,<edx,ebx,edx,8,0> ; Map Phys=Linr from B0 to B7
VVCI_NoRsrvB0:
	clc
	ret

EndProc VDD_VM_Mem_VM_Critical_Init


;******************************************************************************
;
;   VDD_VM_Mem_alloc_visible_page
;
;   DESCRIPTION:    This routine is called in by VDD_VM_Mem_Set_Device_Focus
;		    to allocate a page of visible video memory, or a font page.
;		    It handles unmapping save memory pages that might be mapped
;		    into the VM, if it is in a text or CGA mode.  It also
;		    handles moving pages around, if the page indentified in
;		    EAX is already mapped to a different physical page.  After
;		    a page is allocated, its saved contents are restored by
;		    a call to VDD_VM_Mem_Restore_Page.
;
;   ENTRY:	    EAX = linear page id
;		    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    ESI, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_alloc_visible_page

Assert_VDD_ptrs ebx,edi
	push	edx
	push	ecx
	push	eax

	mov	ecx, [edi.VDD_PageFlags]
	test	byte ptr [ecx][eax], fPageSaveMem
	jz	short avp_not_savemem_page
	mov	ecx, eax
	call	VDD_VM_Mem_Unmap_SaveMem
	mov	eax, ecx
avp_not_savemem_page:

	push	ebx
	call	VDD_PH_Mem_Get_Page_Owner
	mov	ecx, ebx
	pop	ebx
	jc	short avp_not_owned
	cmp	ebx, ecx		    ;Q: VM already owns this page?
	jne	short avp_free_page	    ;	N: free the page
	movzx	ecx, [eax.PDS_virtual_id]   ;	Y:
	cmp	ecx, [esp]		    ;Q: correct page id?
	je	DEBFAR avp_have_page	    ;	Y: leave it alone
	xchg	eax, [esp]		    ; eax = linear pg id
	call	VDD_PH_Mem_Shared_Page	    ;Q: eax & ecx share phys page?
	xchg	eax, [esp]
	jz	short avp_alloc_new	    ;	Y: alloc virtual page [esp]
					    ;	N: if it is lower we should
					    ;	   have already gotten it moved
					    ;	   if it is higher, then we just
					    ;	   free it, rather than mess
					    ;	   with further conflicts
avp_free_page:
	call	VDD_PH_Mem_Free_Page	    ;	N: free the page
IFDEF DEBUG
	jnc	short avp_skip_D00
	Debug_Out 'failed to free visible page for new focus'
avp_skip_D00:
ENDIF
	jc	DEBFAR avp_error

avp_not_owned:
	mov	eax, [esp]		    ;linear page id
	mov	esi, [edi.VDD_PageMap]
	cmp	dword ptr [eax*4][esi], 0   ;Q: VM owns a page for this
					    ;	linear page?
	je	short avp_alloc_new	    ;	N: alloc the phys page
	mov	ecx, eax
	mov	eax, [eax*4][esi]
	xor	esi, esi		    ; no change to handler proc
	call	VDD_PH_Mem_Change_Page
	jnc	short avp_record_page
	Debug_Out 'failed to move a video page'
	jmp	short avp_error

avp_alloc_new:
	mov	eax, [esp]		    ;linear page id
	mov	ecx, eax
	mov	esi, OFFSET32 VDD_VM_Mem_Page_Handler
	call	VDD_PH_Mem_Alloc_Video_Page ; returns eax = page handle
IFDEF DEBUG
	jnc	short @F
	Debug_Out "VDD_VM_Mem_alloc_visible_page failed to alloc page #cx"
@@:
ENDIF
	jc	short avp_error
avp_record_page:
	mov	esi, [edi.VDD_PageMap]
	mov	[esi][ecx*4], eax
	mov	esi, [edi.VDD_PageFlags]
	add	esi, ecx
	and	byte ptr [esi], fPageGblFlags

	call	VDD_VM_Mem_Restore_Page

avp_have_page:
	mov	esi, eax
	call	VDD_PH_Mem_update_LRU

avp_exit:
	pop	eax
	pop	ecx
	pop	edx
	ret

avp_error:
	call	VDD_Error_NoPagesAvail
	jmp	avp_exit

EndProc VDD_VM_Mem_alloc_visible_page


;******************************************************************************
;
;   VDD_VM_Mem_Chk_VideoPages
;
;   DESCRIPTION:    Grow page maps, if needed based on call to
;		    VDD_PH_Mem_Get_Visible_Pages
;
;   ENTRY:	    EAX = first page id
;		    ECX = # of pages
;
;   EXIT:	    If Carry clear then
;			page maps large enough
;		    else
;			page maps too small and realloc failed
;
;   USES:	    EDX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Chk_VideoPages

Assert_VDD_ptrs ebx,edi
	push	ecx
	lea	edx, [eax+ecx]
	cmp	[edi.VDD_VideoPages], edx   ;Q: pages within limits?
	jae	short @F		    ;	Y: (carry clear)
	Trace_Out 'growing page maps in VDD_VM_Mem_Chk_VideoPages (#edx)'
	push	eax
	lea	eax, [edx-1]
	call	VDD_VM_Mem_Grow_PageMaps	;   N: grow the pagemap tables
						;	(carry set, if failed)
	pop	eax
@@:
	pop	ecx			    ; restore ecx
	ret

EndProc VDD_VM_Mem_Chk_VideoPages


;******************************************************************************
;
;   VDD_VM_Mem_Set_Device_Focus
;
;   DESCRIPTION:    Allocate all visible video pages for the new focus VM and
;		    restore the VM's saved video memory into these allocated
;		    pages.  If the VM already owns video pages for some of
;		    these visible pages, then they will be used or moved as
;		    necessary to force the visible pages to all be contiguous
;		    video pages.  If the new focus has all availble video pages
;		    visible, then we must suspend all background VM's which
;		    need video memory.
;
;   ENTRY:	    EBX = Handle of VM to receive the display focus
;
;   EXIT:	    none
;
;   USES:	    EAX, ECX, EDX, ESI, EDI, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Set_Device_Focus

	queue_out 'set dev focus to #ebx'
IFDEF DEBUG_verbose
EXTRN VDD_State_VM_Debug:NEAR
	Trace_Out 'F',noeol
	call	VDD_State_VM_Debug
ENDIF
	SetVDDPtr edi

	call	VDD_Proc_Notify_Bkgnd_VMs

	call	VDD_VM_Mem_MemC_about_to_change

	call	VDD_State_Begin_SR_Section

IFDEF SysVMin2ndBank
	TestMem [edi.VDD_TFlags], fVT_SysVMnot1stBank
	jz	short @F
	VMMCall Test_Sys_VM_Handle
	je	give_sys_vm_focus
@@:
ENDIF
	call	VDD_PH_Mem_Get_Visible_Pages ; returns eax = first page id
					    ; ecx = # of pages
	pushfd				    ; save graphics/text indicator (Carry flag)
IFNDEF Ext_VGA
	cmp	ecx, 16
	jbe	short @F
	Debug_Out 'visible pages (#cx) is greater than 16'
	mov	ecx, 16
@@:
ENDIF
	call	VDD_VM_Mem_Chk_VideoPages
	jnc	short got_pages
	pushad
	call	VDD_Error_NoMainMem
	popad
	mov	ecx, [edi.VDD_VideoPages]   ; adjust visible down to alloc'ed
	sub	ecx, eax		    ; adjust total by 1st
					    ; ecx = adjusted visible page cnt
got_pages:
	mov	[edi.VDD_first_page], al
	mov	[edi.VDD_visible_pages], cl

alloc_visible_pages:
	call	VDD_VM_Mem_alloc_visible_page
	inc	eax			    ; eax = next linear page id
	loop	alloc_visible_pages

	popfd
	jc	short sdf_exit		    ; jump if graphics mode
					    ; else alloc loaded text pages
	movzx	ecx, [edi.VDD_fontpages]
	xor	eax, eax
sdf_alloc_font_pages:
	jecxz	short sdf_exit		    ; no more font pages to alloc
	shr	ecx, 1
	jnc	short sdf_font_not_loaded
	call	VDD_VM_Mem_alloc_visible_page	; alloc first page of font
	inc	eax
	call	VDD_VM_Mem_alloc_visible_page	; alloc 2nd page of font
	dec	eax
sdf_font_not_loaded:
	add	eax, 2
	jmp	sdf_alloc_font_pages

sdf_exit:
	call	VDD_PH_Mem_LRU_Sweep
	call	VDD_PH_Mem_Set_Latch_Addr
	call	VDD_Proc_Chk_Bkgnd_Usage
	call	VDD_State_End_SR_Section

	VMMCall Test_Cur_VM_Handle
	jnz	short sdf_skip_fgrnd
	call	VDD_State_Set_MemC_Owner
	call	VDD_Proc_Force_Cur_VM_Fgrnd
sdf_skip_fgrnd:
	ret

IFDEF SysVMin2ndBank
give_sys_vm_focus:
	mov	al, 0A0h
	movzx	eax, al
	VMMCall _PhysIntoV86,<eax,ebx,eax,16,0> ; map all 16 pages
	jmp	sdf_exit
ENDIF

EndProc VDD_VM_Mem_Set_Device_Focus


;******************************************************************************
;
;   VDD_VM_Mem_Create_VM
;
;   DESCRIPTION:    Unmap all video memory in the VM's page table and allocate
;		    initial video save memory for the VM.
;
;   ENTRY:	    EBX = VM handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    If error, CF = 1
;
;   USES:	    EAX, ECX, EDX, ESI,
;
;==============================================================================
BeginProc VDD_VM_Mem_Create_VM

	Assert_VDD_ptrs ebx,edi

	mov	eax,[Vid_Scroll_Freq]
	mov	[edi.VDD_Scroll_Cntr],ax	; initialize scroll frequency
	VMMCall Test_Sys_VM_Handle		;Q: create SYS VM?
	jz	short dont_alloc_pagemaps	;   Y: pagemaps already allocated
	mov	eax, [Video_Pages]		;   N: allocate default pagemaps
	call	VDD_VM_Mem_Alloc_PageMaps
IFDEF DEBUG
	jnc	short cvm_D00
	Debug_Out 'failed to allocate pagemap tables for new VM'
cvm_D00:
ENDIF
	jc	mcvm_alloc_pm_failed
dont_alloc_pagemaps:

	xor	eax,eax 			; EAX = 0
	VMMCall _ModifyPageBits,<ebx,0A0h,16,<NOT P_AVAIL>,eax,PG_HOOKED,eax>
	xor	eax,eax 			; EAX = 0
	VMMCall _ModifyPageBits,<ebx,0B8h,8,<NOT P_AVAIL>,eax,PG_HOOKED,eax>
IFDEF	VGAMONO
	TestMem [edi.VDD_TFlags], fVT_Mono
	jz	SHORT mcvm_01
	xor	eax,eax 			; EAX = 0
	VMMCall _ModifyPageBits,<ebx,0B0h,8,<NOT P_AVAIL>,eax,PG_HOOKED,eax>
mcvm_01:
ENDIF

	push	edi
	mov	eax,0A0A0A0Ah			; 4 planes of 10 pages
	TestMem [edi.VDD_PIF],fVidHghRsGrfxMd	; Q: Alloc hi res mode mem?
	jnz	SHORT mcvm_alloc		;   Y:
	mov	eax, 4
	TestMem [edi.VDD_PIF],fVidLowRsGrfxMd	; Q: Alloc lo res mode mem?
	jnz	SHORT mcvm_alloc		;   Y:
	movzx	eax, [Vid_Initial_Text_Rows]
	shl	eax, 5				; rows * 32
	lea	eax, [eax*4][eax]+P_SIZE-1	; (rows * 32) * 5 = rows * 160
	shr	eax, 12 			; # of pages
	or	eax, 00020000h			; Assume text mode alloc
						;   with 2 pages of font
mcvm_alloc:
	lea	edi, [edi.VDD_MStt.MSS_plane0]
	mov	ecx, 4
	xor	esi, esi
mcvm_init_lp:
	movzx	edx, al
	mov	[edi.MSS_plane_handle], esi
	mov	[edi.MSS_plane_addr], esi
	mov	[edi.MSS_plane_size], dx
	mov	[edi.MSS_plane_alloced], si
	add	edi, SIZE MSS_Plane_Info_Struc
	shr	eax, 8				; move size for next pg into AL
	loop	mcvm_init_lp

	pop	edi
	lea	esi, [edi.VDD_MStt]
	call	VDD_VM_Mem_Realloc
	jc	short mcvm_alloc_failed

	mov	[edi.VDD_fontpages], 1	; only first font is loaded

	SetFlag [edi.VDD_Flags], fVDD_MInit
	clc
	ret

mcvm_alloc_failed:
	Debug_Out 'failed to allocate save memory for new VM'
	call	VDD_VM_Mem_DMain
	stc
mcvm_alloc_pm_failed:
	ret

EndProc VDD_VM_Mem_Create_VM


;******************************************************************************
;
;   VDD_VM_Mem_Destroy_VM
;
;   DESCRIPTION:    Deallocate any video pages which the VM has allocated and
;		    deallocate the video save memory.
;
;   ENTRY:	    EBX = VM handle
;
;   EXIT:	    none
;
;   USES:	    EAX, ECX, ESI, EDI, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Destroy_VM

	SetVDDPtr edi
	ClrFlag [edi.VDD_Pif], fVidRetainAllo ; Release all the mem now
	call	VDD_VM_Mem_Free_Pages
	call	VDD_VM_Mem_DMain
	call	VDD_Grab_Delete_Text_Copy_Buf
	ret

EndProc VDD_VM_Mem_Destroy_VM


;******************************************************************************
;
;   VDD_VM_Mem_VM_Resume
;
;   DESCRIPTION:    Lock the VM's video save memory
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    Carry set, if can't resume VM
;
;   USES:	    EAX, ECX, EDX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_VM_Resume

Assert_VDD_ptrs ebx,edi
	push	esi
	lea	esi, [edi.VDD_MStt.MSS_plane0]

	mov	ecx, 4
vmr_lock_planes:
	push	ecx
	mov	eax, [esi.MSS_plane_handle]
	or	eax, eax
	jz	short vmr_no_plane_mem
	movzx	ecx, [esi.MSS_plane_alloced]
	VMMCall _PageLock,<eax, ecx, 0, PageLockedIfDP>
	or	eax, eax
	jz	short vmr_resume_failed
vmr_no_plane_mem:
	add	esi, SIZE MSS_Plane_Info_Struc
	pop	ecx
	loop	vmr_lock_planes
vmr_exit:
	clc
	pop	esi
	ret

vmr_resume_failed:
	pop	ecx
	neg	ecx
	add	ecx, 4			; # of planes to unlock again
	jecxz	short vmr_fail_exit	; jump if no planes locked
	call	VDD_VM_Mem_Unlock_Save_Mem

vmr_fail_exit:
	stc
	pop	esi
	ret

EndProc VDD_VM_Mem_VM_Resume


;******************************************************************************
;
;   VDD_VM_Mem_VM_Suspend
;
;   DESCRIPTION:    Unlock the VM's video save memory
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    EAX, ECX, EDX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_VM_Suspend

	mov	ecx, 4
Assumes_Fall_Through VDD_VM_Mem_Unlock_Save_Mem

EndProc VDD_VM_Mem_VM_Suspend


;******************************************************************************
;
;   VDD_VM_Mem_Unlock_Save_Mem
;
;   DESCRIPTION:    Unlock planes of save memory starting with first plane
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;		    ECX = # of planes that need to be unlocked
;
;   EXIT:	    none
;
;   USES:	    EAX, ECX, EDX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Unlock_Save_Mem

	push	esi
	lea	esi, [edi.VDD_MStt.MSS_plane0]
vms_unlock_planes:
	push	ecx
	mov	eax, [esi.MSS_plane_handle]
	or	eax, eax
	jz	short vms_no_plane_mem
	movzx	ecx, [esi.MSS_plane_alloced]
	VMMCall _PageUnLock,<eax, ecx, 0, PageLockedIfDP>
vms_no_plane_mem:
	add	esi, SIZE MSS_Plane_Info_Struc
	pop	ecx
	loop	vms_unlock_planes
	pop	esi
	ret

EndProc VDD_VM_Mem_Unlock_Save_Mem


;******************************************************************************
;
;   VDD_VM_Mem_Dealloc
;
;   DESCRIPTION:    Deallocate all video save memory pages allocated to a
;		    Mem_State_Struc (either VDD_MStt or VDD_MSttCopy)
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;		    ESI -> Mem_State_Struc
;
;   EXIT:	    none
;
;   USES:	    EAX, ECX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Dealloc

	Assert_VDD_ptrs ebx,edi

	push	esi
	lea	esi, [esi.MSS_plane0]

	mov	ecx, 4
mc_free_planes:
	push	ecx
	xor	eax, eax
	mov	[esi.MSS_plane_addr], eax
	mov	[esi.MSS_plane_size], ax
	mov	[esi.MSS_plane_alloced], ax
	xchg	eax, [esi.MSS_plane_handle]
	or	eax, eax
	jz	short mc_no_plane_mem
	VMMCall _PageFree,<eax, 0>
mc_no_plane_mem:
	add	esi, SIZE MSS_Plane_Info_Struc
	pop	ecx
	loop	mc_free_planes
	pop	esi
	ret

EndProc VDD_VM_Mem_Dealloc


;******************************************************************************
;
;   VDD_VM_Mem_DMain
;
;   DESCRIPTION:    Deallocate all video save memory pages allocated to a
;		    VDD_MStt.
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    EAX, ECX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_DMain

	push	esi
	lea	esi, [edi.VDD_MStt]
	call	VDD_VM_Mem_Dealloc
	pop	esi
	ret

EndProc VDD_VM_Mem_DMain


;******************************************************************************
;
;   VDD_VM_Mem_Adjust_Plane_Sizes
;
;   DESCRIPTION:    Adjust the plane sizes needed to save the current video
;		    memory state.  This routine just modifies the
;		    MSS_plane_size fields in the Mem_State_Struc.  It does
;		    not allocate or deallocate memory.	A subsequent call
;		    to VDD_VM_Mem_Realloc can be made to change the actual
;		    memory allocations.
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;		    ESI -> Mem_State_Struc
;		    EDX = 0, if main memory alloc
;			 -1, if copy memory alloc
;
;   EXIT:	    none
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Adjust_Plane_Sizes

	Assert_VDD_ptrs ebx,edi

	pushad

	call	VDD_PH_Mem_Get_Visible_Pages ; returns eax = first page id
	add	eax, ecx		    ; eax = # of pages

	xor	ebx, ebx		    ; assume 0 for planes 1 & 2
	xor	ecx, ecx

IFDEF TLVGA
	TestMem [edi.VDD_TFlags],fVT_TLVGA	    ;if ET3000
	jz	short mr_2
	;if ET3000, test ATC 10 bit 6 also for 256 color mode
	test	[edi.VDD_Stt.A_Mode],040h
	jnz	short mr_zero_3
mr_2:
ENDIF
	test	[edi.VDD_Stt.S_MMode], fSeq4Chain4 ;Q: in chain4 mode? (256 color)
	jnz	short mr_zero_3 	    ;	Y:

	mov	dl, [edi.VDD_Stt.G_Misc]
	test	[edi.VDD_Stt.C_Mode], 1     ;Q: CGA compatibility enabled?
	jz	short mr_oddeven	    ;	Y: mode 4, 5 or 6 use 1 plane

	and	dl, fGrp6Char OR fGrp6Chain
	cmp	dl, fGrp6Char OR fGrp6Chain ;Q: chained graphics mode?
IFDEF	PVGA
	jne	short @F
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short mr_chained
; PVGA mode 5Ah - 1024x768x2 comes to here too. Distinguish it!!! - C. Chiang -
; PVGA mode 5Ah returns G_Misc (3ce.06) with value - 07h.
; This turns out to be the same as chained graphics mode used by GEM 
; Softkicker which running under modified mode 10h.  We use CRTC HDisp
; register bit #4 to distinguish them.  In PVGA mode 5Ah, 3x4.01 == 7Fh.
; However, in mode 10h, 3x4.01 = 4Fh.		- C. Chiang -
	test	[edi.VDD_Stt.C_HDisp], 10h  ;Q: PVGA mode 5Ah
	jz	short mr_chained	    ;	N: must be chained graphics mode
@@:
ELSE
	je	short mr_chained	    ;	Y:
ENDIF

	test	[edi.VDD_Stt.S_MMode], fSeq4SqAd ;Q: in odd/even mode? (text & CGA)
	jnz	short mr_not_oddeven	    ;	N:

; PVGA mode 5Ah - 1024x768x2 comes to here too. Distinguish it!!! - C. Chiang -
IFDEF	PVGA
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short @F
	push	edx
	mov	dl, [edi.VDD_Stt.C_HDisp]
	cmp	dl, 07Fh			;Q: WDC mode 5Ah?
	pop	edx
	je	short mr_not_oddeven	    ;	Y:
@@:
ENDIF	;PVGA

mr_oddeven:
	test	dl, fGrp6Char		    ;Q: graphics mode?
	jnz	short mr_zero_3 	    ;	Y: 0 planes 1, 2 & 3
	or	dh, dh			    ;Q: copy memory alloc?
	jnz	short mr_zero_3 	    ;	Y: don't alloc for font
	movzx	ebx, [edi.VDD_fontpages]
mr_fp_cnt_lp:
	adc	ecx, 0
	shr	ebx, 1
	jc	mr_fp_cnt_lp
	jnz	mr_fp_cnt_lp
					    ; ecx = # of fonts, ebx = 0
	shl	ecx, 1			    ; ecx = # of font pages needed
	jmp	short mr_zero_3

mr_not_oddeven:
	mov	ebx, eax		    ; plane 1 needs all pages
	mov	ecx, eax		    ; plane 2 needs all pages
	push	eax			    ; plane 3 needs all pages
	jmp	short mr_set_all

mr_chained:				    ; chained odd to even graphics mode
	mov	ecx, eax		    ; need to alloc planes 0 & 2

mr_zero_3:
	push	0			    ; plane 3 doesn't need memory

;
; ENTRY:    AX = new size for plane 0
;	    BX = new size for plane 1
;	    CX = new size for plane 2
;	    new size for plane 3 on the stack
mr_set_all:
	lea	ebp, [esi.MSS_plane0.MSS_plane_size]
	call	mr_mod_plane_size	    ; update plane 0 size
	mov	eax, ebx
	lea	ebp, [esi.MSS_plane1.MSS_plane_size]
	call	mr_mod_plane_size	    ; update plane 1 size
	mov	eax, ecx
	lea	ebp, [esi.MSS_plane2.MSS_plane_size]
	call	mr_mod_plane_size	    ; update plane 2 size
	pop	eax
	lea	ebp, [esi.MSS_plane3.MSS_plane_size]
	call	mr_mod_plane_size	    ; update plane 3 size
	popad
	ret

;
; ENTRY:    AX = new size for plane
;	    EBP -> [MSS_plane_size]
;
mr_mod_plane_size:

	TestMem [edi.VDD_PIF], fVidRetainAllo ;Q: PIF requested no mem shrink?
	jnz	short mr_chk_grow	    ;	Y: check for alloc growing
	TestMem [edi.VDD_Flags], fVDD_MdSvRam ;Q: Saving RAM during mode change?
	jz	short mr_do_mod 	    ;	N: change size
mr_chk_grow:
	cmp	ax, [ebp]		    ;Q: size increasing?
	jbe	short mr_no_mod 	    ;	N: don't change size
mr_do_mod:
	mov	[ebp], ax		    ;	Y: change size
mr_no_mod:
	ret

EndProc VDD_VM_Mem_Adjust_Plane_Sizes


;******************************************************************************
;
;   VDD_VM_Mem_Realloc_Plane
;
;   DESCRIPTION:    Change the memory allocations associated with a plane
;		    in the Mem_State_Struc.  This routine handles deallocating
;		    a plane's memory, if the size shrinks to 0.  And doing a
;		    new allocation, if the plane currently doesn't own any
;		    memory.
;
;   ENTRY:	    EBX = VM Handle
;		    ESI -> MSS_Plane_Info_Struc
;		    EDI -> VDD CB data
;
;   EXIT:	    Carry set, if allocation failed
;
;   USES:	    EAX, EDX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Realloc_Plane

	push	ecx
	movzx	eax, [esi.MSS_plane_size]
	mov	ecx, [esi.MSS_plane_handle]
	or	eax, eax			;Q: need memory for plane?
	jz	short rap_no_plane		;   N:
	jecxz	short rap_alloc_handle	    ;jump if handle previously freed
	VMMCall _PageReAllocate,<ecx,eax,[Vid_PageAllocFlags]>
	jmp	short rap_alloc_called

rap_alloc_handle:
	xor	ecx, ecx
	VMMCall _PageAllocate,<eax,PG_HOOKED,ebx,ecx,ecx,ecx,ecx,[Vid_PageAllocFlags]>
rap_alloc_called:
	or	eax, eax
	jnz	short rap_store_result
	stc
	jmp	short rap_exit

rap_no_plane:
	jecxz	short rap_already_freed
	VMMCall _PageFree,<ecx,0>
rap_already_freed:
	xor	eax, eax
	xor	edx, edx

rap_store_result:
	mov	[esi.MSS_plane_handle], eax
	mov	[esi.MSS_plane_addr], edx
	movzx	edx, [esi.MSS_plane_size]
	mov	[esi.MSS_plane_alloced], dx
	clc
rap_exit:
	pop	ecx
	ret

EndProc VDD_VM_Mem_Realloc_Plane


;******************************************************************************
;
;   VDD_VM_Mem_Realloc
;
;   DESCRIPTION:    Change the memory allocations associated with each plane
;		    in the Mem_State_Struc.  This routine handles deallocating
;		    a plane's memory, if the size shrinks to 0.  And doing a
;		    new allocation, if the plane currently doesn't own any
;		    memory.
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;		    ESI -> Mem_State_Struc
;
;   EXIT:	    Carry set, if allocation failed, all memory that was
;		    allocated remains allocated.
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Realloc

	Assert_VDD_ptrs ebx,edi

	pushad
	TestMem [edi.VDD_TFlags], fVT_NoSaveResSysVM
	jz	short rm_doit
	VMMCall Test_Sys_VM_Handle
	jz	short rm_exit		    ; don't alloc mem for sys VM
rm_doit:
	ClrFlag [edi.VDD_EFlags], fVDE_NoMain ; clear flag
	lea	esi, [esi.MSS_plane0]

	mov	ecx, 4			    ; Four planes
rm_alloc_planes:

	movzx	eax, [esi.MSS_plane_alloced]
	cmp	ax, [esi.MSS_plane_size]
	jz	short rm_next		    ; jump if required = alloc'ed
	jb	short rm_alloc_more
	TestMem [edi.VDD_PIF], fVidRetainAllo ; Q: PIF requested no mem shrink?
	jnz	short rm_next		    ;	Y: Don't shrink alloc
rm_alloc_more:
	push	eax
	cmp	[edi.VDD_savemem_maps], 0   ;Q: save mem pages mapped?
	je	short rm_skip_disable	    ;	N: don't need to disable mem
	push	ecx
IFDEF DEBUG_verbose
	Trace_Out 'VDD_VM_Mem_Realloc calling disable to unmap save mem'
ENDIF
	call	VDD_VM_Mem_Disable
	pop	ecx
rm_skip_disable:
	call	VDD_VM_Mem_Realloc_Plane
	pop	eax
	jc	short rm_alloc_failed
	cmp	cl, 4			    ;Q: plane 0?
	jne	short rm_next		    ;	N:
	test	[edi.VDD_Stt.G_Misc], fGrp6Char ;Q: text mode?
	jnz	short rm_next		    ;	N:
	cmp	ax, [esi.MSS_plane_alloced] ;Q: allocation grew?
	jae	short rm_next		    ;	N:
;
; init new text pages
;
	push	ecx
	push	edi
	mov	edi, [esi.MSS_plane_addr]
	movzx	ecx, [esi.MSS_plane_alloced]
	sub	ecx, eax		    ; ecx = # of pages in new region
	shl	ecx, 12 - 2		    ; ecx = # of dwords in new region
	shl	eax, 12
	add	edi, eax		    ; edi -> start of new pages
	mov	eax, 07200720h
	cld
	rep	stosd
	pop	edi
	pop	ecx

rm_next:
	add	esi, SIZE MSS_Plane_Info_Struc
	loop	rm_alloc_planes
	clc
rm_exit:
	popad
	ret

rm_alloc_failed:
IFDEF DEBUG
	neg	ecx
	add	ecx, 4
	Trace_Out 'failed to allocate memory for plane #cl'
ENDIF
	SetFlag [edi.VDD_EFlags], fVDE_NoMain	; set error flag
	stc
	jmp	rm_exit

EndProc VDD_VM_Mem_Realloc


;******************************************************************************
;
;   VDD_VM_Mem_Font_Page
;
;   DESCRIPTION:    Return carry set, if the page is part of a loaded text
;		    mode font, else return with carry clear.
;
;		    This routine is only called by VDD_PH_Mem_update_LRU to
;		    determine if a video page is a necessary part of the
;		    visible screen of the focus VM.  It first checks for
;		    visible pages and if the page being checked isn't
;		    visible it calls here to see if it might be part of a
;		    font.  An example is that the 2nd page is not visible
;		    in 80 by 25 text, but it is part of the 1st font, so
;		    it is required.
;
;   ENTRY:	    EAX = page id
;		    EBX = VM Handle
;		    EDI -> VM's VDD_CB_Struc
;
;   EXIT:	    Carry set, if page is part of a loaded font when VM is
;		    in text mode.
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Font_Page

	test	[edi.VDD_Stt.G_Misc], fGrp6Char ;Q: graphics mode?
	jnz	short fp_exit			;   Y: return carry clear
	push	eax
	shr	eax, 1
	bt	dword ptr [edi.VDD_fontpages], eax
	pop	eax
fp_exit:
	ret

EndProc VDD_VM_Mem_Font_Page


;******************************************************************************
;
;   VDD_VM_Mem_End_Mode_Chg
;
;   DESCRIPTION:    adjust memory allocation after a mode change
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_VM_Mem_End_Mode_Chg

IFDEF DEBUG_verbose
	Trace_Out 'A',noeol
	call	VDD_State_VM_Debug
ENDIF
	Assert_VDD_ptrs ebx,edi
	pushad
	TestMem [edi.VDD_Flags], fVDD_NoSaveRes ;Q: auto res disabled?
	jnz	short emc_skip_realloc		;   Y: don't realloc save mem
	lea	esi, [edi.VDD_MStt]
	xor	edx, edx
	call	VDD_VM_Mem_Adjust_Plane_Sizes
	call	VDD_VM_Mem_Realloc		; Realloc the memory
emc_skip_realloc:

	cmp	ebx, [Vid_Focus_VM]		;Q: focus VM?
	jne	short @F			;   N:
	call	VDD_PH_Mem_Set_Latch_Addr	;   Y: set latch address &
	call	VDD_Proc_Chk_Bkgnd_Usage	;      enable/disable bkgnd VM's
@@:

	xor	ebp, ebp
	call	VDD_PH_Mem_Get_Visible_Pages	; returns eax = first page id
	jc	short emc_graphics
	movzx	ebp, [edi.VDD_fontpages]
emc_graphics:
	call	VDD_VM_Mem_Chk_VideoPages
	jnc	short emc_maps_ok
	mov	ecx, [edi.VDD_VideoPages]   ; adjust visible down to alloc'ed
	sub	ecx, eax		    ; adjust total by 1st
					    ; ecx = adjusted visible page cnt
emc_maps_ok:
	lea	edx, [eax+ecx-1]		; edx = last visible page
	push	edi
	mov	esi, [edi.VDD_PageMap]
	mov	ecx, [edi.VDD_PageFlags]
	push	[edi.VDD_VideoPages]
	xor	edi, edi
emc_loop:
;
; if allocated page is not visible, then free it
;
	push	eax
	mov	eax, edi
	shr	eax, 1
	bt	ebp, eax			;Q: page part of a loaded font?
	pop	eax
	jc	short emc_visible		;   Y: treat as a visible page

	cmp	edi, eax			;Q: below first visible?
	jb	short emc_free			;   Y: free page
	cmp	edx, edi			;Q: above last visible?
	jb	short emc_free			;   Y: free page

emc_visible:
	cmp	ebx, [Vid_CRTC_VM]		;Q: CRTC VM?
	je	short emc_next			;   Y: leave page allocated
	call	VDD_VM_Mem_VM_can_use_savemem	;Q: VM in mode which can have
						;      save mem mapped
	jc	short emc_next			;   N: leave page allocated

emc_free:	; enter with carry set, if non-visible page
	push	eax
	pushfd
	mov	eax, [esi][edi*4]
	or	eax, eax			;Q: have an alloc'ed page
	jz	short emc_next_w_pop		;   N:
	popfd
	pushfd					;Q: non-visible page?
	jnc	short emc_save_page		;   N: save & free the page

	and	byte ptr [ecx][edi], NOT fPageSaved
	pushad
	xor	ecx, ecx
	xchg	cx, [eax.PDS_linear_page]
	jecxz	short @F
	xor	eax, eax
	VMMCall _ModifyPageBits,<ebx,ecx,1,<NOT P_AVAIL>,eax,PG_HOOKED,eax>
@@:
	popad
	and	[eax.PDS_flags], NOT fPDS_Dirty ;   Y: we don't need to save

emc_save_page:
	call	VDD_State_Begin_SR_Section
	call	VDD_PH_Mem_Free_Page

emc_next_w_pop:
	popfd
	pop	eax

emc_next:
	inc	edi
	cmp	edi, [esp]
	jb	emc_loop
	add	esp, 4				; discard saved page count
	pop	edi
	call	VDD_VM_Mem_Disable_Null
	call	VDD_Grab_Clear_Mod_State

	call	VDD_State_End_SR_Section
	popad
	ret

EndProc VDD_VM_Mem_End_Mode_Chg


;******************************************************************************
;
;   VDD_VM_Mem_Change_SaveMem
;
;   DESCRIPTION:    Deallocate VM's save memory, if the VM has just enabled
;		    the CanRestore bit and auto restore is disabled for the
;		    VM (sys VM/other VMs).  Or, reallocate VM's save memory,
;		    if the VM has just disabled the CanRestore bit and auto
;		    restore is disabled for the VM.
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    EDX, ESI, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Change_SaveMem

	Assert_VDD_ptrs ebx,edi

	TestMem [edi.VDD_Flags], fVDD_NoSaveRes ;Q: auto res disabled?
	jnz	short csm_free_savemem		;   Y: free savemem
;
; CanRestore was just disabled by VM, so we need to try to realloc save mem again
;
	lea	esi, [edi.VDD_MStt]
	xor	edx, edx
	call	VDD_VM_Mem_Adjust_Plane_Sizes
	call	VDD_VM_Mem_Realloc	    ; Realloc the memory
	jmp	short csm_exit

csm_free_savemem:
;
; CanRestore was just enabled by VM, so we can free all save mem
;
	call	VDD_VM_Mem_DMain

csm_exit:
	ret

EndProc VDD_VM_Mem_Change_SaveMem


;******************************************************************************
;
;   VDD_VM_Mem_Adjust_Visible_Pages
;
;   DESCRIPTION:    Check and adjust visible pages allocation if necessary
;		    based upon CRTC start address.
;
;   ENTRY:	    EBX = VM Handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Adjust_Visible_Pages

Assert_VDD_ptrs ebx,edi
IFDEF DEBUG_verbose
	queue_out 'adjusting visible pages'
ENDIF
	push	eax
	push	ecx
	call	VDD_PH_Mem_Get_Visible_Pages	; returns eax = first page id
	mov	[edi.VDD_first_page], al
	mov	[edi.VDD_visible_pages], cl
	push	edx
	lea	edx, [eax+ecx]
	cmp	edx, [edi.VDD_VideoPages]	;Q: pages within limits?
IFDEF	DEBUG
	jbe	short CCS_alloc_OK		;   Y:
	Debug_Out 'Too many pages visible in VDD_VM_Mem_Adjust_Visible_Pages (#edx)'
CCS_alloc_OK:
ENDIF
	pop	edx
	jbe	short CCS_alloc_visible_pages	;   Y:
	mov	ecx, [edi.VDD_VideoPages]	;   N: adjust # of pages
	sub	ecx, eax
CCS_alloc_visible_pages:
	call	VDD_VM_Mem_alloc_visible_page
	inc	eax				; eax = next linear page id
	loopd	CCS_alloc_visible_pages
	dec	eax
	call	VDD_VM_Mem_Chk_Alloc		; Alloc up to last page id
	call	VDD_PH_Mem_Set_Latch_addr
	pop	ecx
	pop	eax
	ret

EndProc VDD_VM_Mem_Adjust_Visible_Pages


;******************************************************************************
;
;   VDD_VM_Mem_Chk_Alloc
;
;   DESCRIPTION:    Check and adjust save memory allocation if necessary based
;		    upon a faulting page id.
;
;   ENTRY:	    EAX = page id
;		    EBX = VM Handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    Carry set, if can't allocate memory for this request
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Chk_Alloc

Assert_VDD_ptrs ebx,edi
	pushad
	TestMem [edi.VDD_Flags], fVDD_NoSaveRes ;Q: auto res disabled?
	jnz	ca_exit 			;   Y: don't alloc save mem
	mov	ecx, eax
	inc	ecx			    ; ecx = needed allocation

	test	[edi.VDD_Stt.C_Mode], 1     ;Q: CGA compatibility enabled?
	jz	short ca_chk_plane0	    ;	Y:
	mov	dl, [edi.VDD_Stt.G_Misc]
	and	dl, fGrp6Char OR fGrp6Chain
	cmp	dl, fGrp6Char OR fGrp6Chain ;Q: chained graphics mode?
IFDEF	PVGA
; PVGA mode 5Ah - 1024x768x2 comes to here too. Distinguish it!!! - C. Chiang -
	jne	short @F
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	SHORT ca_chained
	test	[edi.VDD_Stt.C_HDisp], 10h  ;Q: PVGA mode 5Ah
	jz	short ca_chained	    ;	Y:
@@:
ELSE
	je	short ca_chained	    ;	Y:
ENDIF	;PVGA

	mov	dl, [edi.VDD_Stt.S_MMode]
	test	dl, fSeq4SqAd		    ;Q: in odd/even mode?
IFDEF	PVGA
	jnz	short @F
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	SHORT ca_chk_plane0
; PVGA mode 5Ah - 1024x768x2 comes to here too. Distinguish it!!! - C. Chiang -
	push	edx
	mov	dl, [edi.VDD_Stt.C_HDisp]
	cmp	dl, 07Fh			;Q: WDC mode 5Ah?
	pop	edx
	jne	short ca_chk_plane0	    ;	N:
@@:
ELSE
	jz	short ca_chk_plane0	    ;	Y:
ENDIF	;PVGA
	test	dl, fSeq4Chain4 	    ;Q: in chain4 mode?
	jz	short ca_planar 	    ;	N:

ca_chk_plane0:
;
; chk allocation of plane 0
;
	cmp	cx, [edi.VDD_MStt.MSS_plane0.MSS_plane_size]
	jbe	short ca_okay	    ; jump if current allocation is okay
	mov	[edi.VDD_MStt.MSS_plane0.MSS_plane_size], cx
	jmp	short ca_realloc

ca_chained:
	mov	dl, 101b		    ; only update planes 0 & 2
	jmp	short ca_start_checking

ca_planar:
;;	  mov	  dl, [edi.VDD_Stt.S_Mask]    ; update unmasked planes

;
; determine which planes are needed
;
ca_start_checking:
	xor	dh, dh
	mov	eax, ecx
	lea	esi, [edi.VDD_MStt.MSS_plane0]
	mov	ecx, 4
ca_chk_planes:
;;	  shr	  dl, 1
;;	  jnc	  short ca_skip_plane
	cmp	ax, [esi.MSS_plane_size]    ;Q: allocation okay?
	jbe	short ca_skip_plane	    ;	Y:
	mov	[esi.MSS_plane_size], ax    ;	N: adjust size
	inc	dh

ca_skip_plane:
	add	esi, SIZE MSS_Plane_Info_Struc
	loop	ca_chk_planes
	or	dh, dh			;Q: any planes changed
	jz	short ca_okay		;   N:

ca_realloc:
;;	Trace_Out 'VDD_VM_Mem_Chk_Alloc calling realloc'
	lea	esi, [edi.VDD_MStt]
IFDEF DEBUG_verbose
	queue_out 'calling mem_realloc from mem_chk_alloc'
ENDIF
	call	VDD_VM_Mem_Realloc	; Realloc the memory

ca_exit:
	popad
	ret

ca_okay:
	clc
	jmp	ca_exit

EndProc VDD_VM_Mem_Chk_Alloc


;******************************************************************************
;
;   VDD_VM_Mem_MemC_about_to_change
;
;   DESCRIPTION:    Call VDD_VM_Mem_Disable for previous MemC owner VM, if
;		    it was owned by a VM other than the Pseudo VM.  This
;		    routine is called when changing focus and when entering
;		    message mode.
;
;   ENTRY:	    EBX = VM handle to get MemC
;		    EDI = VDD CB ptr
;
;   EXIT:	    none
;
;   USES:	    ECX, EDX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_MemC_about_to_change

	push	eax
	mov	eax, [Vid_MemC_VM]
	cmp	eax, ebx		    ;Q: new focus already owns memC?
	je	short atc_same_VM	    ;	Y:
	or	eax, eax		    ;Q: memC owned by a VM?
	jz	short atc_no_disable	    ;	N:
atc_chk_pseudo:
	cmp	eax, [Vid_Msg_Pseudo_VM]    ;Q: Pseudo VM handle?
	je	short atc_no_disable	    ;	Y:
	pushad
	mov	ebx, eax
	SetVDDPtr edi

IFDEF Ext_VGA
	TestMem [edi.VDD_TFlags], fVT_V7VGA
	jz	short atc_not_V7VGA
	test	[edi.VDD_Stt.S_V7_ExtComp], fSeqFCseqChain4
	jz	short atc_not_V7VGA
%OUT is this the only mode when we need to handle banking?
;
; make sure that we have an allocated page handle for all visible pages
;
	call	VDD_PH_Mem_Get_Visible_Pages
	call	VDD_VM_Mem_Chk_VideoPages
%OUT handle error if carry set

	mov	edx, [edi.VDD_PageMap]
	lea	edx, [edx][eax*4]
assign_visible_pages:
	push	eax
	mov	esi, [edx]
	or	esi, esi		    ;Q: have page handle?
	jnz	short atc_skip		    ;	Y:
	mov	esi, OFFSET32 VDD_VM_Mem_Page_Handler
	call	VDD_PH_Mem_Assign_Video_Page
	mov	[edx], eax
	mov	esi, eax
atc_skip:
%OUT mark all assigned pages dirty
	or	[esi.PDS_flags], fPDS_Dirty ; mark everything dirty
	movzx	eax, [esi.PDS_virtual_id]
	call	VDD_PH_Mem_CalcPageAddr
	mov	[esi.PDS_linear_page], ax
	pop	eax
	inc	eax			    ; eax = next linear page id
	add	edx, 4
	loop	assign_visible_pages
	int 1
;
%OUT ; copy dirty bits into all banks
;
atc_not_V7VGA:
ENDIF

;
; disable any mapped memory and copy dirty bits
;
	call	VDD_VM_Mem_Disable
	popad

atc_no_disable:
	pop	eax
	ret

atc_same_VM:
	TestMem [edi.VDD_Flags], fVDD_MemCmods	;Q: MemC mods for VM?
	jz	atc_no_disable			;   N: don't call disable
	jmp	atc_chk_pseudo			;   Y: disable anyway

EndProc VDD_VM_Mem_MemC_about_to_change


;******************************************************************************
;
;   VDD_VM_Mem_Disable
;
;   DESCRIPTION:    Called by VDDState when memory controller state is changing.
;
;   ENTRY:	    EBX = previous owner VM handle, or 0
;		    EDI -> previous owner VM's VDD_CB_Struc, or 0
;
;   EXIT:	    VM's owned video pages have been unmapped
;
;   USES:	    EAX, ECX, EDX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Disable

Assert_VDD_ptrs ebx,edi
IFDEF DEBUG
	xchg	eax, [esp]
	queue_out 'disable mem called from ?eax'
	xchg	eax, [esp]
ENDIF
%OUT perhaps this would be more efficient if it scheduled an event to do the unmapping
	TestMem [Vid_Flags], fVid_MsgInit   ;Q: Message mode state init'd?
	jz	short md_exit		    ;	N:
	or	ebx, ebx
	jz	short md_exit
IFDEF SysVMin2ndBank
	TestMem [edi.VDD_TFlags], fVT_SysVMnot1stBank
	jz	short @F
	VMMCall Test_Sys_VM_Handle
	je	short disable_sys_vm_mem
@@:
ENDIF
IFDEF DEBUG_verbose
	Trace_Out 'd',noeol
	call	VDD_State_VM_Debug
ENDIF
	push	ebp
	push	esi
	mov	esi, [edi.VDD_PageMap]
	mov	ebp, [edi.VDD_PageFlags]
	call	VDD_PH_Mem_Clear_MemC_mods

	xor	ecx, ecx
md_lp:
	test	byte ptr [ecx][ebp], fPageSaveMem
	jz	short not_savemem_page

	call	VDD_VM_Mem_Unmap_SaveMem    ; ecx = page id
	jmp	short d_next_page

not_savemem_page:
	mov	eax, [ecx*4][esi]
	or	eax, eax
	jz	short d_next_page
	call	VDD_VM_Mem_Unmap_Page

d_next_page:
	inc	ecx
	cmp	ecx, [edi.VDD_VideoPages]
	jb	md_lp

	pop	esi
	pop	ebp
	CallRet VDD_VM_Mem_Disable_Null

md_exit:
	ret

IFDEF SysVMin2ndBank
disable_sys_vm_mem:
	xor	eax, eax
	VMMCall _ModifyPageBits,<ebx,0A0h,16,<NOT P_AVAIL>,eax,PG_HOOKED,eax>
	ret
ENDIF

EndProc VDD_VM_Mem_Disable


IFDEF Ext_VGA
;******************************************************************************
;
;   VDD_VM_Mem_Disable_Inaccessible
;
;   DESCRIPTION:
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc VDD_VM_Mem_Disable_Inaccessible

	pushad
	mov	esi, [edi.VDD_PageMap]
	xor	ecx, ecx
di_lp:
	mov	eax, [ecx*4][esi]
	or	eax, eax			    ;Q: phys page owned?
	jz	short di_next_page		    ;	N:
	cmp	[eax.PDS_linear_page], 0	    ;Q: phys page mapped?
	je	short di_next_page		    ;	N:
	call	VDD_PH_Mem_Page_Accessible	    ;Q: is it accessible?
	jc	short di_next_page		    ;	Y: leave it
IFDEF DEBUG  ;_verbose
	movzx	edx, [eax.PDS_linear_page]
	Trace_Out '#eax not accessible as #dl'
ENDIF
	call	VDD_VM_Mem_Unmap_Page		    ;	N: unmap it
di_next_page:
	inc	ecx
	cmp	ecx, [edi.VDD_VideoPages]
	jb	di_lp
	popad
	ret

EndProc VDD_VM_Mem_Disable_Inaccessible


;******************************************************************************
;
;   VDD_VM_Mem_Rearrange_Pages
;
;   DESCRIPTION:
;
;   ENTRY:	    EAX = page handle of page that just faulted
;		    [Vid_Unaccessed_Page] = page handle of page unmapped which
;					    hadn't been accessed
;		    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Rearrange_Pages

	pushad
IFDEF DEBUG
	cmp	[Vid_Unaccessed_Page], 0	;Q: unmapped any unaccessed pages?
	jne	short mrp_D00			;   Y:
	Debug_Out 'VDD_VM_Mem_Rearrange_Pages called when [Vid_Unaccessed_Page] = 0'
IFDEF Ext_VGA
	jmp	mrp_exit
ELSE
	jmp	SHORT mrp_exit
ENDIF
mrp_D00:
ENDIF

	call	VDD_PH_Mem_CalcPagePhys 	; eax = page #, ecx = bank
	mov	edx, ecx			; edx = bank for cur page
	movzx	esi, al 			; esi = page # for cur page
	mov	eax, [Vid_Unaccessed_Page]
	call	VDD_PH_Mem_CalcPagePhys 	; eax = page #, ecx = bank
	movzx	eax,al
IFDEF Ext_VGA
	cmp	ecx, edx			;Q: banks differ?
	je	short mrp_no_bank_chg		;   N:
;
; attempt to move the page we just unmapped into the same bank as cur page
;
	Debug_Out 'debug moving page from current bank'
	mov	ecx, edx			; ecx = bank of cur page
	call	VDD_PH_Mem_Get_First_PageId_of_Bank ;ecx = 1st page id
	mov	eax, [Vid_Unaccessed_Page]
	movzx	edx, [eax.PDS_virtual_id]
	xor	esi, esi
	call	VDD_PH_Mem_Change_Page
	jc	short mrp_chg_page_failed
	mov	ecx, edx
	mov	[eax.PDS_virtual_id], dx
	mov	esi, [edi.VDD_PageMap]
	mov	[esi][ecx*4], eax		; update pagemap
	call	VDD_VM_Mem_Restore_Page
	jmp	short mrp_exit			; we're done!

mrp_chg_page_failed:
;
; attempt to move cur page into the same bank as the page we just unmapped
;
	Debug_Out 'VDD_PH_Mem_Change_Page failed in VDD_VM_Mem_Rearrange_Pages'
	jmp	short mrp_exit

mrp_no_bank_chg:
ENDIF

IFDEF DEBUG
	mov	eax, [esp.Pushad_EAX]
	mov	ecx, [Vid_Unaccessed_Page]
	Debug_Out 'deadlock between pages #eax and #ecx'
ENDIF

mrp_exit:
	popad
	ret

EndProc VDD_VM_Mem_Rearrange_Pages
ENDIF


;******************************************************************************
;
;   VDD_VM_Mem_VM_can_use_savemem
;
;   DESCRIPTION:    Return Carry clear, if VM is in a text mode, a CGA graphics
;		    mode, or a packed pixel (256 color) mode.
;
;   ENTRY:	    EDI -> VM's VDD_CB_Struc
;
;   EXIT:	    Carry clear, if VM can use savemem
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_VM_can_use_savemem

	test	[edi.VDD_Stt.S_MMode], fSeq4SqAd    ;Q: in odd/even mode?
;;;IFDEF   PVGA
; PVGA mode 5Ah - 1024x768x2 comes to here too. Distinguish it!!! - C. Chiang -
;
; This part will cause memory save/restore problem when you issue a command
; on small windowed DOS like "dir" and switch the screen using <ALT+ENTER>
; to DOS full screen.  The memory is not right at this point.
; This happens because the exit condition is not right from the following
; instructions.  For instance, for mode 3 VM, this routine should exit with
; CARRY clear and no ZERO flag.  However, after checking of VDD_Stt.C_HDisp,
; the exit conditions will be CARRY set and ZERO flag set.
; Since this routine can only be called when VM running under windowed DOS
; small screen, we comment these codes since no extended modes are supported
; in Grabbers to run these modes in small windowed DOS screen.
;						06-20-91 - C. Chiang -
;;;	jnz	short @F
;;;	TestMem [edi.VDD_TFlags], fVT_PVGA
;;;	jz	SHORT cus_chkmode
;;;	push	edx
;;;	mov	dl, [edi.VDD_Stt.C_HDisp]
;;;	cmp	dl, 07Fh			;Q: WDC mode 5Ah?
;;;	pop	edx
;;;	jne	short cus_chkmode		    ;	Y: map save mem page
;;;@@:
;;;ELSE
	jz	short cus_chkmode		    ;	Y: map save mem page
;;;ENDIF   ;PVGA
	test	[edi.VDD_Stt.C_Mode], 1 	    ;Q: CGA compatibility enabled?
	jz	short cus_chkmode		    ;	Y: map save mem page
IFDEF TLVGA
	TestMem [edi.VDD_TFlags],fVT_TLVGA	    ;if ET3000
	jz	short cus_2
	;if ET3000, test ATC 10 bit 6 also for 256 color mode
	test	[edi.VDD_Stt.A_Mode],040h
	jnz	short cus_chkmode
cus_2:
ENDIF
	test	[edi.VDD_Stt.S_MMode], fSeq4Chain4  ;Q: in chain4 mode?
	jz	short cus_no			    ;	N: can't use save mem

cus_chkmode:
	push	eax
	mov	al, [edi.VDD_Stt.G_Mode]
	and	al, 3				    ; isolate write mode
	pop	eax
	jnz	short cus_no			    ; jump if not write mode 0
	ret

cus_no:
	stc
	ret

EndProc VDD_VM_Mem_VM_can_use_savemem


;******************************************************************************
;VDD_PFault
;
;DESCRIPTION:
;	VIDEO page faults occur in a number of cases.  For full screen VMs
;	they can occur when there is a mode change. After doing a few
;	checks to make sure that the mode change does not adversely
;	affect other VMs, the correct physical memory is remapped and
;	execution continues.  Full screen VMs can also page fault when
;	the application accesses more memory than has been set aside for
;	the VM, forcing the VM to run full screen, not background. For
;	windowed VMs, the same cases arise, but the action is a little
;	different.
;
;ENTRY: EAX = page number of faulting page
;
;EXIT:	PTE fixed or VM state modified so it won't run
;
;USES:	Flags, EAX, EBX, ECX, EDX, ESI, EDI
;
;==============================================================================
BeginProc VDD_PFault

IFDEF DEBUG
	pushad
	xor	eax, eax
	call	VDD_State_Schedule_Debug_Event
	popad
ENDIF

	SetVDDPtr edi

IFDEF DEBUG_verbose
	VMMCall Test_Sys_VM_Handle
	je	short pf_d001
	Trace_Out 'p',noeol
	jmp	short pf_d002
pf_d001:
	Trace_Out 'P',noeol
pf_d002:
	Trace_Out '#al',noeol
ENDIF

	mov	ecx, (Block_Svc_If_Ints_Locked OR Block_Enable_Ints)
	VMMCall Begin_Critical_Section
	queue_out 'VDD pfault #ax'

IFDEF SysVMin2ndBank
	TestMem [edi.VDD_TFlags], fVT_SysVMnot1stBank
	jz	short @F
	VMMCall Test_Sys_VM_Handle
	je	VDD_SYS_VM_PFault
@@:
ENDIF

	push	eax
	SetFlag [edi.VDD_Flags],<fVDD_PageFault OR fVDD_InPFault>

	TestMem	[Vid_Flags], fVid_NestedModeSet	;Q: nested modeset ongoing?
	jnz	pf_map_null			;   Y: no access to memory!

	cmp	ebx, [Vid_CRTC_VM]		;Q: CRTC owner?
	jne	short @F			;   N: trapping is enabled
	cmp	ebx, [Vid_MemC_VM]		;Q: MemC owner also?
	jne	short @F			;   N: trapping is enabled
	call	VDD_State_Save_CRTC_Owner	;   Y: make sure reg state is
@@:
	call	VDD_PH_Mem_CalcPageId
IFDEF DEBUG
	jnc	short pf_D00
	mov	eax, [esp]
	Trace_Out 'VDD_PH_Mem_CalcPageId for page #al failed in PFault for #ebx'
pf_D00:
ENDIF
	jc	pf_map_null			; jump if page is not legal in
						;   current memory mapping

	cmp	eax, [edi.VDD_VideoPages]	;Q: pagemap tables large enough?
	jb	short pf_pgmp_ok		;   Y:
	call	VDD_VM_Mem_Grow_PageMaps	;   N: grow the pagemap tables
	jc	pf_map_null

pf_pgmp_ok:
	TestMem [edi.VDD_Flags], fVDD_Font	;Q: loading a font?
	jnz	short pf_recordfontload 	;   Y:

;
;   Check for font loading.  When loading a font without using the INT 10h
;   function, the controller state has to be modified so that the 3rd memory
;   plane can be accessed, so the MemC state is modified for a pseudo planar
;   state, but the CRTC state is left unmodified.  So we check first for a
;   character cell height greater than 2, if it is 2 or less, then we assume
;   that the VM is in a normal graphics mode and do no further checks.	If
;   char cell hgt is greater than 2, then we assume the VM is in a text mode
;   and check to see if the MemC looks right.  Some chipsets (specifically
;   the Tseng Labs ET3000) require the graphics mode bit (0) in graphics
;   controller miscellaneous register (index 6) to be set, indicating
;   graphics mode to load the font, so we check this bit first; and if it is
;   set, then we assume that a font is being loaded.  Otherwise we just check
;   to see if the graphics controller is still in chained odd to even mode
;   by checking bit 1 in the graphics controller miscellaneous register; if
;   not, then we assume that a font is being loaded, because fonts are stored
;   in consecutive bytes in plane 3.
;
	mov	cl, [edi.VDD_Stt.CRTC.C_CharHgt]
	and	cl, 00011111b
	cmp	cl, 2				;Q: small cell height?
	jbe	short pf_chk_pgmp		;   Y: assume graphics mode
	mov	cl, [edi.VDD_Stt.G_Misc]
	test	cl, fGrp6Char			;Q: graphics mode?
	jnz	short pf_dir_font		;   Y: assume font loading
	test	cl, fGrp6Chain			;Q: odd/even?
	jnz	short pf_chk_pgmp		;   Y: assume text mode
pf_dir_font:
;;	  Trace_Out 'font loading detected in VDD_PFault'
	SetFlag [edi.VDD_Flags], fVDD_DirFont	; flag font load mode

pf_recordfontload:
	mov	ecx, eax
	shr	ecx, 1
	bts	dword ptr [edi.VDD_fontpages], ecx

pf_chk_pgmp:
IFDEF Prefer_Physical	; use physical pages if the VM already owns them
	mov	esi, [edi.VDD_PageMap]		; table of physical pages
	lea	esi, [esi][eax*4]
	mov	ecx, [esi]
	or	ecx, ecx			;Q: VM owns a phys page for this one?
	jnz	short pf_have_page		;   Y: map it into the VM
ENDIF

;
; Check to see if we can map regular save memory into the VM.  The VM must
; be in a text, CGA graphics or 256 color graphics mode (none of which are
; planar modes.)
;
; For efficiency of CRTC VM, we give the VM physical memory, even though
; we could treat this as virtual video page
	cmp	ebx, [Vid_CRTC_VM]		;Q: VM owns CRTC?
	je	short pf_cant_map_savemem	;   Y: must use video memory
	TestMem [edi.VDD_Flags], fVDD_WaitAtt	;Q: VM waiting to be attached?
	jnz	pf_map_null			;   Y: just map null mem

	TestMem [edi.VDD_Flags], <fVDD_Font OR fVDD_DirFont>
						;Q: loading a font?
	jnz	short pf_map_savemem		;   Y: map save memory
	call	VDD_VM_Mem_VM_can_use_savemem	;Q: VM can use save mem?
	jc	short pf_cant_map_savemem	;   N: must use video memory
pf_map_savemem:
	mov	ecx, [esp]			;   Y: attempt to map save mem
	call	VDD_VM_Mem_Map_SaveMem
	jc	short pf_cant_map_savemem	; jump, if couldn't do it
	pop	eax
	jmp	pf_exit
pf_cant_map_savemem:

IFNDEF Prefer_Physical
	mov	esi, [edi.VDD_PageMap]		; table of physical pages
	lea	esi, [esi][eax*4]
	mov	ecx, [esi]
	or	ecx, ecx			;Q: VM owns a phys page for this one?
	jnz	short pf_have_page		;   Y: map it into the VM
ENDIF
	TestMem [edi.VDD_Flags], fVDD_ModeSet
	jnz	short pf_alloc_page
	call	VDD_VM_Mem_Chk_Alloc
	jmp	short pf_alloc_page

pf_have_page:
	cmp	ebx, [Vid_CRTC_VM]		;Q: VM owns CRTC?
	jne	short pf_map_page		;   N: map phys page
	call	VDD_PH_Mem_Mapped_Phys		;Q: alloc'd page handle (ecx)
						;   maps correct phys pg
						;   for page id (eax)?
	jz	short pf_map_page		;   Y: map phys page
	xchg	eax, ecx
	call	VDD_State_Begin_SR_Section
	call	VDD_PH_Mem_Free_page		;   N: free current alloc'd pg
	mov	eax, ecx			;      & alloc correct page

pf_alloc_page:
	call	VDD_State_Begin_SR_Section
	push	eax				; page id
	push	esi				; ptr to pagemap entry

	mov	esi, OFFSET32 VDD_VM_Mem_Page_Handler
	mov	[Vid_Unaccessed_Page], 0	; flag no unaccessed pages
	call	VDD_PH_Mem_Alloc_Video_Page
;
; warning: the Carry flag return check is below, so carry flag needs to be
; preserved...
;
	jc	short @F
	cmp	[Vid_Unaccessed_Page], 0	;Q: any unaccessed pages?
	je	short @F			;   N:
	mov	esi, OFFSET32 VDD_Error_Cvt_FullScrn
	VMMCall Schedule_VM_Event		;	 to notify VM
	clc
@@:
	pop	esi
	mov	ecx, eax
	pop	eax
;
; check return from VDD_PH_Mem_Alloc_Video_Page
;
	jc	short pf_alloc_failed

	mov	[esi], ecx
	add	eax, [edi.VDD_PageFlags]
	and	byte ptr [eax], fPageGblFlags
	mov	esi, eax
	mov	eax, ecx			; eax = page handle
	call	VDD_VM_Mem_Restore_Page
	mov	ecx, eax

pf_map_page:
	cmp	ebx, [Vid_CRTC_VM]		;Q: VM owns CRTC?
	jnz	short pf_no_vis_changes 	;   N: don't adjust visible pages
	TestMem [edi.VDD_Flags], fVDD_ModeSet	;Q: in a mode change?
	jnz	short pf_no_vis_changes 	;   Y: don't adjust visible pages
	push	ecx
	call	VDD_PH_Mem_Get_Visible_Pages	; returns eax = first page id
	cmp	cl, [edi.VDD_visible_pages]	;Q: # of visible pages changed?
	pop	ecx
	jne	short @F			;   Y:
	cmp	al, [edi.VDD_first_page]	;Q: first visible page changed?
	je	short pf_no_vis_changes 	;   N:
@@:						;   Y: make sure visible pages
;;	  Trace_Out 'adjusting visible pages'
	call	VDD_VM_Mem_Adjust_Visible_Pages ;      are allocated & restored
pf_no_vis_changes:

	mov	eax, ecx			; phys page handle
	call	VDD_State_End_SR_Section
						; eax = page handle of page to map
	mov	edx, 1				; going to map page
	call	VDD_PH_Mem_Access_Page		; ecx = phys address

IFDEF Ext_VGA
	jnc	short pf_do_map 		; jump if MemC not modified
;
; Unmap any mapped physical pages which are no longer accessible with the
; modified MemC state which resulted from the call to VDD_PH_Mem_Access_Page.
;
; If VDD_VM_Mem_Unmap_Page is called to unmap a page which hasn't been
; accessed since it was mapped, then we are in a deadlock situation with the
; VM executing a MOVS instruction.  We took a page fault and mapped a
; destination page, but when the instruction was restarted we page faulted
; on the source which we are currently trying to map in, and we need to
; unmap the destination again, which hasn't been accessed yet.  So if we
; detect the condition of unmapping a page that hasn't been accessed, then
; we need to move either the current page which we are trying to map, or the
; page that we are unmapping, so that they both can be mapped at the same
; time.
;
	mov	[Vid_Unaccessed_Page], 0	; flag no unaccessed pages
	call	VDD_VM_Mem_Disable_Inaccessible
	cmp	[Vid_Unaccessed_Page], 0	;Q: unmapped any unaccessed pages?
	je	short pf_do_map 		;   N:
	call	VDD_VM_Mem_Rearrange_Pages	;   Y: re-arrange pages
pf_do_map:
ENDIF
	mov	esi, eax
 	cmp	[esi.PDS_Linear_Page],0		; is this page already mapped?
 	je	SHORT pageunmapped
 	call	VDD_VM_Mem_Unmap_Page		; eax = page handle
pageunmapped:
	pop	eax				; eax = faulting linear page #
	mov	[esi.PDS_linear_page], ax
	VMMCall _PhysIntoV86,<ecx,ebx,eax,1,0>
%OUT optimization here - map in all pages that the VM owns
	jmp	short pf_exit

pf_alloc_failed:
	call	VDD_State_End_SR_Section
IFDEF DEBUG
	mov	eax, [esp]
	Trace_Out 'VDD_PH_Mem_Alloc_Video_Page failed for #al in #ebx'
ENDIF
	TestMem [edi.VDD_Flags], fVDD_CanRestore;Q: alloc failed VM which
						;     can restore display?
	jz	short pf_map_null_with_error	;   N: just map null
	TestMem [edi.VDD_TFlags], fVT_Notify_at_PF  ;Q: suppose to notify here?
	jz	short pf_map_null		;   N: just map null
	call	VDD_Proc_BGrnd_Notify		;   Y: simulate INT 2F notification
	jmp	SHORT pf_map_null

pf_map_null_with_error:
; We've gotten here, because the VM can't allocate a page of video memory.
; We are going to map a NUL page, so it is possible that the VM's display
; will end up corrupt.	If the VM is doing a mode change, then we will
; assume that this is just the process of initializing memory, so we won't
; give an error message, otherwise we will.

	TestMem [edi.VDD_Flags], fVDD_ModeSet	;Q: in a mode change?
	jnz	short pf_map_null		;   Y: skip error msg
	TestMem [edi.VDD_TFlags],fVT_SuprsMsg	;Q: Suppress error message?
	jnz	SHORT pf_map_null		;   Y:
	call	VDD_Error_NoPagesAvail		;   N: Report video mem corrupt
pf_map_null:
	call	VDD_State_End_SR_Section
	pop	eax				; eax = faulting linear page #
	call	VDD_VM_Mem_MapNull

pf_exit:
Assert_VDD_ptrs ebx,edi
	ClrFlag [edi.VDD_Flags], <fVDD_DirFont OR fVDD_InPFault>
IFDEF DEBUG_verbose
	VMMCall End_Critical_Section
	queue_out 'end_pfault'
	ret
ELSE
	VMMJmp	End_Critical_Section
ENDIF

IFDEF SysVMin2ndBank
	PUBLIC VDD_SYS_VM_PFault
VDD_SYS_VM_PFault:
	queue_out 'VDD Sys VM pfault #ax'
	cmp	ebx, [Vid_MemC_VM]	;Q: SYS VM owns MemC?
	je	short @F		;   Y:
	call	VDD_State_Set_MemC_Owner;   N: take it
@@:
	cmp	al, 0B0h
	jae	short vsvp_map_text
	mov	al, 0A0h
	mov	cl, 16
vsvp_exit:
	movzx	ecx, cl
	VMMCall _PhysIntoV86,<eax,ebx,eax,ecx,0>    ; map all 16 pages
	VMMJmp	End_Critical_Section

vsvp_map_text:
	and	al, NOT 7		; round down to B0 or B8
	mov	cl, 8
	jmp	vsvp_exit
ENDIF

EndProc VDD_PFault


;******************************************************************************
;
;   VDD_VM_Mem_Map_SaveMem
;
;   DESCRIPTION:    Directly map a page of the VM's video save memory into
;		    the VM.  This routine is called by VDD_PFault for VM's
;		    which can run in the background without using demand
;		    paged video memory.  Text, CGA graphics and 256 color
;		    graphics modes all operate with a single logical plane
;		    of memory, so we can just map normal memory into the
;		    required video space and the VM can modify it directly.
;
;   ENTRY:	    EAX = page id
;		    ECX = page number
;		    EBX = VM_Handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    Carry set, if page not available in save memory
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Map_SaveMem

Assert_VDD_ptrs ebx,edi
	pushad
	lea	esi, [edi.VDD_MStt.MSS_plane0]
	TestMem [edi.VDD_Flags], <fVDD_Font OR fVDD_DirFont>
					    ;Q: loading a font?
	jz	short msm_notfont	    ;	      N: map plane 0
;;	  Trace_Out 'mapping save memory for font load'
	add	esi, (SIZE MSS_Plane_Info_Struc) * 2 ;Y: map plane 2
	cmp	ax, [esi.MSS_plane_size]    ;Q: memory for font save?
	jb	short msm_chk_alloc	    ;	Y:
	mov	ecx, eax
	or	cl, 1			    ; 2 pages per font, so force to 2nd
	inc	ecx			    ; convert page id to # of pages
	mov	[esi.MSS_plane_size], cx
	jmp	short msm_attempt_alloc
msm_notfont:
	cmp	ax, [esi.MSS_plane_size]    ;Q: memory valid in plane?
IFDEF DEBUG_verbose
	jb	short @F
	Trace_Out 'not enough save memory to map for page #cx'
@@:
ENDIF
	jae	DEBFAR msm_error	    ;	N:
msm_chk_alloc:
	cmp	ax, [esi.MSS_plane_alloced] ;Q: memory allocated for plane?
	jb	short msm_havemem	    ;	Y:
msm_attempt_alloc:
	push	eax
	call	VDD_VM_Mem_Realloc_Plane
	pop	eax
	jnc	short msm_havemem	    ; jump if we got it allocated
	TestMem [edi.VDD_Flags], <fVDD_Font OR fVDD_DirFont>
	jz	DEBFAR msm_error	    ; not critical, if not font loading
;
; We couldn't allocate save memory at this time, and since this is for loading
; a font, we don't want to proceed with null memory, because the font will be
; lost.  So, we do a critical set focus to convert the VM to full screen.
; Now the VM will own physical video memory, and we can just return a failure
; from this routine.  VDD_Pfault will see the failure, but will also see that
; the VM owns a physical page so it will just use it.
;
	call	VDD_Error_Cvt_FullScrn	    ; VM is converted to full screen
	clc				    ;	as a desired side effect of
	jmp	DEBFAR msm_error	    ;	SHELL_SYSMODAL_Message

msm_havemem:
;
; Force a page lock in case we have an intelligent pageswap device, in
; which case the mmgr won't do an implied lock.
;
	VMMCall _PageLock,<[esi.MSS_plane_handle],1,eax,0>
	or	eax, eax
IFDEF DEBUG
	jnz	short @F
	mov	ecx, [esp.Pushad_ECX]
	Debug_Out 'page lock on save memory failed for page #cx'
@@:
ENDIF
	jz	short msm_error
	mov	eax, [esp.Pushad_EAX]	    ; restore page id
	mov	ecx, [esp.Pushad_ECX]	    ; restore page #
	VMMCall _MapIntoV86,<[esi.MSS_plane_handle],ebx,ecx,1,eax,0>
IFDEF DEBUG
	or	eax, eax
	jnz	short msm_D00
	Debug_Out 'MapIntoV86 failed in VDD_VM_Mem_Map_SaveMem'
%OUT possible bug here if MapIntoV86 fails the memory won't be unlocked
	jz	short msm_error
msm_D00:
ENDIF

	inc	[edi.VDD_savemem_maps]
IFNDEF Prefer_Physical
	mov	esi, [edi.VDD_PageMap]
	mov	ecx, [esp.Pushad_EAX]
	mov	eax, [ecx*4][esi]
	or	eax, eax
	jz	short @F
	call	VDD_PH_Mem_Free_Page
@@:
ENDIF
	mov	esi, [edi.VDD_PageFlags]    ; table of pages flags
	mov	eax, [esp.Pushad_EAX]
	or	byte ptr [eax][esi], fPageSaveMem
	TestMem [edi.VDD_Flags], <fVDD_Font OR fVDD_DirFont>
					    ;Q: loading a font?
	jz	short msm_skipfontflag	    ;	N: don't set font flag
	or	byte ptr [eax][esi], fPageFontMem
msm_skipfontflag:
	stc

msm_error:
	cmc
	popad
	ret

EndProc VDD_VM_Mem_Map_SaveMem


;******************************************************************************
;
;   VDD_VM_Mem_Unmap_SaveMem
;
;   DESCRIPTION:    Copy dirty bit status from the VM's page table into the
;		    VM's VDD_PageFlags table.  Then, unmap the page.
;
;   ENTRY:	    ECX = page id
;		    EBX = VM_Handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    none
;
;   USES:	    EAX, EDX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Unmap_SaveMem

Assert_VDD_ptrs ebx,edi
	push	esi
	mov	eax, ecx
	push	eax			    ; save page id
	call	VDD_PH_Mem_CalcPageAddr
	push	eax			    ; save page #
	mov	ecx, eax
	shl	ecx, 12
	add	ecx, [ebx.CB_High_Linear]
	shr	ecx, 12 		    ; high linear page #
	sub	esp, 4			    ; reserve dword for page table copy
	mov	eax, esp
	VMMCall _CopyPageTable,<ecx,1,eax,0>
	pop	ecx			    ; pop page table entry into ecx
	test	cl, P_DIRTY
	pop	ecx			    ; restore ecx = page #
	mov	eax, [esp]		    ; restore eax = page id
	mov	esi, [edi.VDD_PageFlags]
	jz	short sm_not_dirty
	or	byte ptr [eax][esi], fPageSaved
	call	VDD_VM_Mem_Record_VRAM_Mod
sm_not_dirty:
	and	byte ptr [eax][esi], NOT fPageSaveMem
	dec	[edi.VDD_savemem_maps]

	VMMCall _ModifyPageBits,<ebx,ecx,1,<NOT P_AVAIL>,0,PG_HOOKED,0>

;
; Unlock the mapped page.
;
	pop	ecx			    ; restore ecx = page id
	btr	dword ptr [ecx][esi], bPageFontMem
	lea	esi, [edi.VDD_MStt.MSS_plane0]	; esi -> plane 0 MSS_Plane_Info_Struc
	jnc	short sm_not_fontpage
	lea	esi, [edi.VDD_MStt.MSS_plane2]	; esi -> font's MSS_Plane_Info_Struc
sm_not_fontpage:
	cmp	cx, [esi.MSS_plane_alloced]
	jae	short sm_exit
	VMMCall _PageUnLock,<[esi.MSS_plane_handle],1,ecx,0>
sm_exit:
	pop	esi
	ret

EndProc VDD_VM_Mem_Unmap_SaveMem



;******************************************************************************
;
;   VDD_VM_Mem_MapNull
;
;   DESCRIPTION:    Maps null page at page # EAX
;
;   ENTRY:	    EAX = page number
;		    EBX = VM_Handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    none
;
;   USES:	    EAX, ECX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_MapNull

Assert_VDD_ptrs ebx,edi
	push	edx
	push	eax			    ; save linear page #
	mov	edx, eax
	sub	edx, 0A0h
	bts	[edi.VDD_nullpages], edx    ; indicate mapped page
	VMMCall _GetNulPageHandle
	pop	edx			    ; edx = linear page #
	VMMCall _MapIntoV86,<eax,ebx,edx,1,0,0>
	pop	edx
	ret

EndProc VDD_VM_Mem_MapNull


;******************************************************************************
;
;   VDD_VM_Mem_Disable_Null
;
;   DESCRIPTION:    Unmap all pages mapped into a VM.
;
;   ENTRY:	    EBX = VM handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    none
;
;   USES:	    EAX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Disable_Null

IFDEF DEBUG_verbose
	queue_out 'disable null mem'
ENDIF
Assert_VDD_ptrs ebx,edi
	mov	eax, [edi.VDD_nullpages]
	or	eax, eax
	jz	short VDD_MDis_Ex
	pushad
	mov	ebp, eax
	mov	esi, 0A0h
dn_loop:
	shr	ebp, 1
	jnc	short dn_next			; jump if page not mapped
	xor	eax,eax 			; EAX = 0
	VMMCall _ModifyPageBits,<ebx,esi,1,<NOT P_AVAIL>,eax,PG_HOOKED,eax>
	or	al, 1				; force Z-flag clear
dn_next:
	jz	short dn_done			; jump if no more pages mapped
	inc	esi				; next page #
	jmp	dn_loop

dn_done:
	mov	[edi.VDD_nullpages], ebp	; clear bit table
	popad
VDD_MDis_Ex:
	ret

EndProc VDD_VM_Mem_Disable_Null


;------------------------------------------------------------------------------
;------------------------------------------------------------------------------

;******************************************************************************
;
;   VDD_VM_Mem_Page_Handler
;
;   DESCRIPTION:    Handler for all demand paged video pages owned by VMs.
;		    It handles tracking a page's dirty bit, saving the memory
;		    contents to the VM's save memory and unmapping the page
;		    as required.
;
;   ENTRY:	    EAX = page handle
;		    EBX = owner VM handle
;		    EDI = VDD CB ptr
;		    ECX = notification id
;			    0 - page is about to be freed
;			    1 - page is no longer accessible with the
;				current memory access state
;			    2 - physical page assignment is changing
;		    EDX = new page handle, if ECX = 2
;
;   EXIT:	    Carry clear for ECX # 2, otherwise Carry set for ECX = 2,
;		    to indicate that page assignment changing is not supported
;
;   USES:	    EAX, ECX, EDX, ESI, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Page_Handler

IFDEF DEBUG_verbose
	queue_out 'page handler called for #eax, owner=#ebx'
ENDIF
Assert_VDD_ptrs ebx,edi
	jecxz	short ph_free_page

	cmp	ecx, 2
	je	short abort_req
	jb	DEBFAR unmap_page
	Debug_Out 'VDD_VM_Mem_Page_Handler unknow page notification - #ecx'
	clc
	ret

abort_req:
	stc
	ret

ph_free_page:
	xor	edx, edx
	call	VDD_VM_Mem_Is_Page_Dirty    ;Q: page dirty?
	jz	short ph_not_dirty	    ;	N:
	call	VDD_VM_Mem_Save_Page
	mov	dl, fPageSaved
	push	eax
	movzx	eax, [eax.PDS_virtual_id]
	call	VDD_VM_Mem_Record_VRAM_Mod
	pop	eax

ph_not_dirty:

; remove handle from VM's psuedo page table
;
	movzx	ecx, [eax.PDS_virtual_id]
	mov	esi, [edi.VDD_PageMap]
IFDEF DEBUG
Assert_VDD_ptrs ebx,edi
	cmp	ecx, [edi.VDD_VideoPages]	;Q: pagemap tables large enough?
	jb	short @F
	Debug_Out 'VDD: bad virtual id'
@@:
	cmp	dword ptr [ecx*4][esi], eax
	je	short @F
	Debug_Out 'VDD: clearing invalid page handle entry'
@@:
ENDIF
	mov	dword ptr [ecx*4][esi], 0   ; clear page handle
	add	ecx, [edi.VDD_PageFlags]
	and	byte ptr [ecx], fPageGblFlags ; clear owned bit & phys page #
	or	byte ptr [ecx], dl
;
; Set SHADOW_TRASHED bit in display driver if necessary
;
	TestMem [edi.VDD_Flags], fVDD_DspDrvrAware
	jz	short unmap_page
	pushad
	movzx	eax, word ptr [Vid_Shadow_Mem_Status_Ptr+2]
	or	ax, ax
	jz	short @F
	VMMCall _SelectorMapFlat,<ebx, eax, 0>
	inc	eax
	jz	short @F
	dec	eax
	movzx	ecx, word ptr [Vid_Shadow_Mem_Status_Ptr]
	add	eax, ecx
	test	byte ptr [eax], SHADOW_IN_USE
	jz	short @F
	or	byte ptr [eax], SHADOW_TRASHED
@@:
	popad

unmap_page:
	call	VDD_VM_Mem_Unmap_Page

BeginProc VDD_VM_Mem_Msg_Page_Handler
	clc
	ret
EndProc VDD_VM_Mem_Msg_Page_Handler

EndProc VDD_VM_Mem_Page_Handler


;******************************************************************************
;
;   VDD_VM_Mem_Unmap_Page
;
;   DESCRIPTION:    Unmap a physical video page from a VM.  ORing the current
;		    state of physical dirty bit into the pageflags entry for
;		    the virtual page.
;
;   ENTRY:	    EAX = page handle
;		    EBX = VM handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    EAX, EDX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Unmap_Page

IFDEF DEBUG_verbose
	xchg	ebx, [esp]
	queue_out 'unmap page #eax called from ?ebx'
	xchg	ebx, [esp]
ENDIF

Assert_VDD_ptrs ebx,edi
	push	ecx
	movzx	ecx, [eax.PDS_linear_page]
	jecxz	short up_not_mapped
	TestMem [edi.VDD_Flags], fVDD_InPFault
	jz	short up_accessed	    ; don't chk accessed, if not pfault
	VMMCall Test_Cur_VM_Handle	    ;Q: page belongs to cur VM?
	jne	short up_accessed	    ;	N: don't chk accessed bit
	call	VDD_VM_Mem_Get_PTE	    ; ECX = PTE
	test	cl, P_ACC
	jnz	short up_accessed
;;	  Trace_Out 'unmapping #eax which was never accessed'
	mov	[Vid_Unaccessed_Page], eax
up_accessed:
	call	VDD_VM_Mem_Is_Page_Dirty
	jc	short up_not_mapped
	jz	short up_not_dirty
	push	eax
	movzx	eax, [eax.PDS_virtual_id]
	call	VDD_VM_Mem_Record_VRAM_Mod
	pop	eax
up_not_dirty:
	xor	ecx, ecx
	xchg	cx, [eax.PDS_linear_page]
	call	VDD_PH_Mem_Release_Page
	VMMCall _ModifyPageBits,<ebx,ecx,1,<NOT P_AVAIL>,0,PG_HOOKED,0>
up_not_mapped:
	pop	ecx
	ret

EndProc VDD_VM_Mem_Unmap_Page


;******************************************************************************
;
;   VDD_VM_Mem_Get_PTE
;
;   DESCRIPTION:    Get Page Table Entry for linear page number in ECX
;
;   ENTRY:	    ECX = Linear page number
;		    EBX = VM handle
;
;   EXIT:	    ECX = PTE
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Get_PTE

	push	edx
	push	eax
	shl	ecx, 12
	add	ecx, [ebx.CB_High_Linear]
	shr	ecx, 12
	sub	esp, 4			    ; reserve dword for page table copy
	mov	eax, esp
	VMMCall _CopyPageTable,<ecx,1,eax,0>
	pop	ecx			    ; pop page table entry into ecx
	pop	eax			    ; restore eax
	pop	edx
	ret

EndProc VDD_VM_Mem_Get_PTE



;******************************************************************************
;
;   VDD_VM_Mem_Is_Page_Dirty
;
;   DESCRIPTION:    Or page table dirty bit into page handle's flags, and
;		    check to see if dirty bit is set in page handle's flags.
;
;   ENTRY:	    EAX = page handle
;		    EBX = VM handle
;
;   EXIT:	    Z-flag set, if page is NOT dirty
;		    Carry set, if page not mapped
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Is_Page_Dirty

	push	ecx
	movzx	ecx, [eax.PDS_linear_page]
	jecxz	short ipd_not_mapped	    ;jump if page not mapped
	test	[eax.PDS_flags], fPDS_Dirty
	jnz	short ipd_dirty
	call	VDD_VM_Mem_Get_PTE
IFDEF	PVGA
; Mark all pages modified - dirty bit = FFFFFFFF for extended PVGA
; modes; This solves the problem during DOS old apps screen scrolling while
; switching back to Windows. This is caused in VDDMEM.ASM routine VDD_Mem_Chg.  In 
; this routine - VMC_Scan use "VMMCall _CopyPageTable" to get the addr. of
; bit mask for dirty pages, which seems not right for PVGA extended modes.
;					  Chung-I Chiang - 06-17-91 -
	TestMem [VT_Flags], fVT_PVGA
	jz	short ipd_pvga_skip
	VMMCall Test_Sys_VM_Handle	;Q: SYS VM?
	jz	short ipd_pvga_skip		; don't do this for sys VM
	push	edi
	SetVDDPtr edi
	cmp	byte ptr [edi.VDD_Stt.C_LnOff], 28h    ;Q: > mode 13h?
	jg	short @F
	cmp	byte ptr [edi.VDD_Stt.C_HDisp], 7Fh    ;Q: modes 5Ah or 5Bh
	jnz	short ipd_pvga_not_dirty
@@:
	or	cl, P_DIRTY		; make it dirty
ipd_pvga_not_dirty:
	pop	edi
ipd_pvga_skip:
ENDIF
	and	cl, P_DIRTY		    ; isolate dirty bit
	jz	short ipd_not_dirtied
	or	[eax.PDS_flags], cl	    ; or dirty bit into page handle flags
IF 0
IFDEF Ext_VGA
	int 1
	push	esi
	xor	esi, esi
ipd_nxt_alt:
	call	VDD_PH_Mem_Get_Alt_Bank_Page
	jc	short ipd_no_alt
	or	[esi.PDS_flags], cl
	jmp	ipd_nxt_alt
ipd_no_alt:
	pop	esi
ENDIF
ENDIF
ipd_not_dirtied:
	test	[eax.PDS_flags], fPDS_Dirty
	pop	ecx
	ret

ipd_not_mapped:
	test	[eax.PDS_flags], fPDS_Dirty
	stc
ipd_dirty:
	pop	ecx
	ret

EndProc VDD_VM_Mem_Is_Page_Dirty


;******************************************************************************
;
;   VDD_VM_Mem_Chk_SaveMem
;
;   DESCRIPTION:    Try to alloc required save mem for VM, if we weren't
;		    able to before
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    Carry set, if not enough save mem for VM
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Chk_SaveMem

	TestMem [edi.VDD_EFlags], fVDE_NoMain	;Q: need to try alloc again?
	jz	short chksm_exit		;   N: VM has all memory it needs
	pushad
	lea	esi, [edi.VDD_MStt.MSS_plane0]
	mov	ecx, 4
chksm_chk_planes:
	movzx	eax, [esi.MSS_plane_size]
	cmp	ax, [esi.MSS_plane_alloced]
	jbe	short chksm_size_ok
	call	VDD_VM_Mem_Realloc_Plane
	jc	short chksm_realloc_failed
chksm_size_ok:
	add	esi, SIZE MSS_Plane_Info_Struc
	loop	chksm_chk_planes
	ClrFlag [edi.VDD_EFlags], fVDE_NoMain	; clear flag
chksm_realloc_failed:
	popad

chksm_exit:
	ret

EndProc VDD_VM_Mem_Chk_SaveMem

;******************************************************************************
;
;   VDD_VM_Mem_Chk_MemC_State
;
;   DESCRIPTION:    Update the MemC state if necessary to allow reading &
;		    writing video memory for save/restore routines.
;
;   ENTRY:	    EDI -> VDD_CB_Struc
;		    DL = write plane mask for sequencer
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Chk_MemC_State

	push	eax
	push	edx
	mov	dx, 3CEh
	cmp	[edi.VDD_Stt.G_SREna], 0
	je	short @F
	mov	eax, 000001h	    ; or mask = 0, and mask = 0, index = 1
	call	update_reg
@@:
	cmp	[edi.VDD_Stt.G_Func], 0
	je	short @F
	mov	eax, 000003h	    ; or mask = 0, and mask = 0, index = 3
	call	update_reg
@@:
	mov	al, [edi.VDD_Stt.G_Mode]
	and	al, 1011b
	jz	short @F
	mov	eax, 00F405h	    ; or mask = 0, and mask = NOT 1011b, index = 5
	call	update_reg
@@:
	cmp	[edi.VDD_Stt.G_Mask], -1
	jne	short @F
	mov	eax, 0FF0008h	    ; or mask = FF, and mask = 0, index = 8
	call	update_reg
@@:
	mov	dl, 0C4h
	mov	al, [esp]
	cmp	al, [edi.VDD_Stt.S_Mask]
	je	short @F
	shl	eax, 16 	    ; mov requested or mask into high word
	mov	ax, 0002h	    ; and mask = 0, index = 8
	call	update_reg
@@:
	pop	edx
	pop	eax
	ret

update_reg:			; eax = or mask | and mask | index
	out	dx, al		; out index
	IO_Delay
	inc	edx		; point to data port
	in	al, dx		; read current data
	IO_Delay
	and	ah, al		; and with and mask
	shr	eax, 8		; shift or mask to AH and and result to AL
	or	al, ah		; OR in or mask
	out	dx, al		; out result
	IO_Delay
	dec	edx		; point back to index port
	call	VDD_State_Clear_MemC_Owner ; flag that MemC is owned by VDD
	ret

EndProc VDD_VM_Mem_Chk_MemC_State


;******************************************************************************
;
;   VDD_VM_Mem_Save_Page
;
;   DESCRIPTION:    Copy a video page's data into the VM's copy memory, based
;		    on the current mode of memory access for the VM.
;
;		    if odd/even mode
;			if chained 4 color graphics
;			    access page
;			    modify planar to chain odd to even
;			    select plane 0
;			    save 4Kb to save plane 0
;			    select plane 2
;			    save 4Kb to save plane 2
;			else
;			    access page
;			    save 4Kb
;			    if text mode
;				set memc planar
;				access page
;				select plane 2
;				save 4Kb
;		    elsif chain4
;			access page
;			save 4Kb
;		    else
;			set memc planar
;			access page
;			select plane 0
;			save 4Kb
;			select plane 1
;			save 4Kb
;			select plane 2
;			save 4Kb
;			select plane 3
;			save 4Kb
;
;   ENTRY:	    EAX = page handle
;		    EBX = owner VM handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    If carry set, save page failed
;
;   USES:	    ECX, EDX, ESI, flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Save_Page

Assert_VDD_ptrs ebx,edi

	mov	ecx, (Block_Svc_If_Ints_Locked OR Block_Enable_Ints)
	VMMCall Begin_Critical_Section
	queue_out 'save page #eax'

	and	[eax.PDS_flags], NOT fPDS_Dirty
IFDEF DEBUG_verbose
;;	  Trace_Out 's',noeol
ENDIF
;
; Try to fill out save memory, if we haven't been able to allocate it yet
;
	call	VDD_VM_Mem_Chk_SaveMem

;
; tell VDDSTATE that the latches are about to be modified
;
	cmp	ebx, [Vid_MemC_VM]	    ;Q: VM owns MemC?
	jne	short @F		    ;	N: latches will be saved by
					    ;	    set_memc_owner
	push	ebx
	xor	ebx, ebx
	call	VDD_State_Set_Latches_Owner
	pop	ebx
@@:
	call	VDD_State_Set_MemC_Owner

	test	[edi.VDD_Stt.C_Mode], 1     ;Q: CGA compatibility enabled?
	jz	short sp_oddeven	    ;	Y: mode 4, 5 or 6 use 1 plane

	mov	dl, [edi.VDD_Stt.G_Misc]
	and	dl, fGrp6Char OR fGrp6Chain
	cmp	dl, fGrp6Char OR fGrp6Chain ;Q: chained graphics mode?

IFDEF	PVGA
	jne	short @F
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	sp_chained
; PVGA mode 5Ah - 1024x768x2 comes to here too. Distinguish it!!! - C. Chiang -
	test	[edi.VDD_Stt.C_HDisp], 10h  ;Q: PVGA mode 5Ah
	jz	sp_chained		    ;	Y:
@@:
ELSE
	je	sp_chained		    ;	Y:
ENDIF

	mov	dl, [edi.VDD_Stt.S_MMode]
	test	dl, fSeq4Chain4 	;Q: in chain4 mode?
	jnz	sp_chain4		;   Y: save 1 plane
	test	dl, fSeq4SqAd		;Q: in odd/even mode?
	jnz	sp_not_oddeven		;   N:

; PVGA mode 5Ah - 1024x768x4 comes to here too. Distinguish it!!! - C. Chiang -
IFDEF	PVGA
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	SHORT sp_oddeven
	push	edx
	mov	dl, [edi.VDD_Stt.S_ClMode]     ;Q: PVGA 5Ah mode
	cmp	dl, 5
	pop	edx
	je	sp_not_oddeven		;   Y:
ENDIF

sp_oddeven:
;
; copy planes 0 & 1 as 1 plane, and then copy the font in plane 2
;
	xor	edx, edx
	call	VDD_PH_Mem_Access_Page	; ecx = phy pg # for copy source
	mov	dl, 3			; enable writes to planes 0 & 1 (moot)
	call	VDD_VM_Mem_Chk_MemC_State
	lea	esi, [edi.VDD_MStt.MSS_plane0]
	call	VDD_VM_Mem_copy_from_plane

	test	[edi.VDD_Stt.G_Misc], fGrp6Char ;Q: graphics mode?
	jnz	sp_exit 		;   Y: don't copy font plane

	push	eax
	call	VDD_State_Set_MemC_Planar
	call	VDD_OEM_Adjust_Font_Access  ; some OEM adapters need to modify
					    ;	the planar state for saving or
					    ;	restoring the soft text fonts.
	pop	eax
IFDEF	DEBUG
	jnc	SHORT sp_DB_00
Debug_Out "Text mode font save failed"
sp_DB_00:
ENDIF
	xor	edx, edx
	push	ebx
	xor	ebx, ebx		; flag as planar mode
	call	VDD_PH_Mem_Access_Page	; ecx = phy pg # for copy source
	pop	ebx
	mov	dx, 402h		; select plane 2
	call	VDD_VM_Mem_Select_Plane
IFDEF	PVGA
	call	VDD_OEM_PVGA_Adjust_Page_Mode_Regs
ENDIF
	lea	esi, [edi.VDD_MStt.MSS_plane2]	; point to plane 2 info
	call	VDD_Font_save_font
IFDEF	PVGA
	call	VDD_OEM_PVGA_Adjust_Page_Mode_Regs
ENDIF
	call	VDD_State_Set_MemC_Owner
sp_no_font:
	or	cl, -1			; clear Z-flag
	jmp	sp_exit

sp_chained:
	xor	edx, edx
	call	VDD_PH_Mem_Access_Page	; ecx = phy pg # for copy source
;
; modify state to insure that we're reading planes 0 & 1
;
	call	VDD_State_Clear_MemC_Owner ; flag that MemC is owned by VDD
	mov	dl, 3			; enable writes to planes 0 & 1 (moot)
	call	VDD_VM_Mem_Chk_MemC_State
	xor	edx, edx
	call	VDD_VM_Mem_Select_Plane ; reads from planes 0 & 1
	lea	esi, [edi.VDD_MStt.MSS_plane0]
	call	VDD_VM_Mem_copy_from_plane
	mov	dl, 2
	call	VDD_VM_Mem_Select_Plane ; reads from planes 2 & 3
	lea	esi, [edi.VDD_MStt.MSS_plane2]
	call	VDD_VM_Mem_copy_from_plane
IFDEF TLVGA
	jmp	sp_exit
ELSE
	jmp	short sp_exit
ENDIF

sp_not_oddeven:
IFDEF TLVGA
	TestMem [edi.VDD_TFlags],fVT_TLVGA	    ;if ET3000
	jz	short sp_2
	;if ET3000, test ATC 10 bit 6 also for 256 color mode
	test	[edi.VDD_Stt.A_Mode],040h
	jnz	short sp_4
sp_2:
ENDIF

	test	dl, fSeq4Chain4 	;Q: in chain4 mode?
	jz	short sp_not_chain4	;   N: save all 4 planes
					;   Y: ignore plane request

sp_chain4:

;********************************************************************
IF 0
IFDEF	PVGA
; Now, all the 256-color modes come here.  For 256K memory save/restore,
; save 4 planes for PVGA extended 256-color modes will have the same result
; of saving 4 banks.  The standard mode 13h, only one 64k bank is used.  
; However, this copy-1-plane code will not work if extended 256-color Windows
; display driver is used.  ????????? 
;							- C. Chinag -
;?????????
%OUT Western Digital ALWAYS save 4 planes!?!
;   MW - Find way of distinguishing 13h from extended 256 color modes
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short spp_not_5pvga
;;???	cmp	byte ptr [edi.VDD_Stt.C_LnOff], 28h	; Q: mode 13h?
;;???	jnz	short sp_not_chain4	;   N: save all 4 planes
	jmp	short sp_not_chain4	;   N: save all 4 planes
spp_not_5pvga:
ENDIF	;PVGA
ENDIF	;0
;********************************************************************

IFDEF TLVGA
sp_4:
ENDIF
;
; copy 1 plane
;
	xor	edx, edx
	call	VDD_PH_Mem_Access_Page	; ecx = phy pg # for copy source
IFDEF TLVGA
	TestMem [edi.VDD_TFlags], <fVT_TLVGA OR fVT_TL_ET4000>
	jz	short sp_6
	push	eax
	call	VDD_OEM_TLVGA_Set_Graphics
	xchg	eax, [esp]
sp_6:
ENDIF
	mov	dl, 0Fh 		; enable writes to all planes (moot)
	call	VDD_VM_Mem_Chk_MemC_State
	lea	esi, [edi.VDD_MStt.MSS_plane0]
IFDEF IBMXGA
	call	VDD_OEM_Chk_DoubleWord
ENDIF

	call	VDD_VM_Mem_copy_from_plane

IFDEF IBMXGA
	call	VDD_OEM_Restore_DoubleWord
ENDIF
IFDEF TLVGA
	TestMem [edi.VDD_TFlags], <fVT_TLVGA OR fVT_TL_ET4000>
	jz	short sp_8
	xchg	eax, [esp]
	call	VDD_OEM_TLVGA_Reset_Graphics
	pop	eax
sp_8:
ENDIF
	or	cl, -1			; clear Z-flag
	jmp	short sp_exit

sp_not_chain4:
;
; copy all 4 planes
;
	push	eax
	call	VDD_State_Set_MemC_Planar
	pop	eax
IFDEF	DEBUG
	jnc	SHORT sp_DB_01
Debug_Out "Graphics mode save failed"
sp_DB_01:
ENDIF
	xor	edx, edx
	push	ebx
	xor	ebx, ebx		; flag as planar mode
	call	VDD_PH_Mem_Access_Page
	pop	ebx
	lea	esi, [edi.VDD_MStt.MSS_plane0]
	xor	edx, edx		; start with plane 0
sp_save_lp:
	call	VDD_VM_Mem_Select_Plane
	cmp	[esi.MSS_plane_size], 0 ;Q: any save memory for plane?
	jne	short sp_normal_save	;   Y: do normal save
	cmp	dl, 1			;Q: saving plane 1?
	jne	short sp_normal_save	;   N: do normal save
;
; We are probably saving a text page while the VM is temporarily in a
; planar mode while it is loading a soft font, so we need to save the
; attribute bytes into plane 0 save mem.
;
	TestMem [edi.VDD_Flags], <fVDD_Font OR fVDD_DirFont>
					    ;Q: VM loading a font
IFDEF DEBUG_verbose
	jnz	short spf_D00
	Debug_Out 'saving plane 1 with no save mem and not loading font'
spf_D00:
ENDIF
	jz	short sp_normal_save	    ;	N: normal save
	sub	esi, SIZE MSS_Plane_Info_Struc
	call	VDD_VM_Mem_save_attribute_page
	add	esi, (SIZE MSS_Plane_Info_Struc)*2
	jmp	short sp_next_plane

sp_normal_save:
	call	VDD_VM_Mem_copy_from_plane
	add	esi, SIZE MSS_Plane_Info_Struc
sp_next_plane:
	inc	dl
	cmp	dl, 4
	jb	sp_save_lp
	call	VDD_State_Set_MemC_Owner
	or	cl, -1			    ; clear Z-flag

sp_exit:
	queue_out 'end save page #eax'
	VMMCall End_Critical_Section
	clc
	ret
EndProc VDD_VM_Mem_Save_Page


;******************************************************************************
;
;   VDD_VM_Mem_Restore_Page
;
;   DESCRIPTION:    Restore a video page's data from the VM's copy memory,
;		    based on the current mode of memory access for the VM.
;
;		    if odd/even mode
;			if chained 4 color graphics
;			    access page
;			    modify planar to chain odd to even
;			    select plane 0
;			    restore 4Kb from save plane 0
;			    select plane 2
;			    restore 4Kb from save plane 2
;			else
;			    access page
;			    restore 4Kb
;			    if text mode
;				set memc planar
;				access page
;				select plane 2
;				restore 4Kb
;		    elsif chain4
;			access page
;			restore 4Kb
;		    else
;			set memc planar
;			access page
;			select plane 0
;			restore 4Kb
;			select plane 1
;			restore 4Kb
;			select plane 2
;			restore 4Kb
;			select plane 3
;			restore 4Kb
;
;   ENTRY:	    EAX = page handle
;		    EBX = owner VM handle
;		    EDI = VDD CB ptr
;		    ESI -> VM's page flags entry for page to restore
;
;   EXIT:	    If carry flag set, restore page failed
;
;   USES:	    ECX, EDX, ESI, flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Restore_Page

VxD_DATA_SEG
VDD_restore_graphics	dd ?
VDD_restore_text	dd ?
VDD_restore_font	dd ?
VxD_DATA_ENDS

IFDEF DEBUG_verbose
Queue_Out 'restore page #eax for #ebx'
ENDIF

Assert_VDD_ptrs ebx,edi

	mov	ecx, (Block_Svc_If_Ints_Locked OR Block_Enable_Ints)
	VMMCall Begin_Critical_Section
	queue_out 'restore page #eax'

if	0
IFDEF	PVGA
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short VVMRP_NotPVGA
; Take care of 32K BIOS ROM in PVGA 1F board. The standard ROM space is
; 24K only.  Setting bit #0 in 3x4.30 to 0 enables access to all 32K
; addresses of the BIOS ROM form C0000-C7FFFh.  Since this only happens
; under WDC 1F demo board with 24K addressing, comment these out.
; Actually, this should be done during saving the CRTC registers which
; checks if WDC 1F board and set only bit#0 of 3x4.30 to 0 to map memory
; C6000-C7FFF in.				- C. Chiang -
	push	eax
	push	edx
        mov     edx,3cch
        in      al,dx
        IO_Delay
        test    al,1
        mov     dl,0d4h
        jnz     SHORT @F
        mov     dl,0b4h
@@:
	in	al, dx
	push	eax
	mov	ax, 30h		; write 3x4.30 with 0 to enable C6000-C7fff ROM
	out	dx, ax
	pop	eax
	out	dx, al
	pop	edx
	pop	eax
VVMRP_NotPVGA:
ENDIF
endif
	test	byte ptr [esi], fPageSaved
.erre fPageSaved AND 0FFh
	jz	short rp_not_saved
	mov	edx, OFFSET32 VDD_VM_Mem_copy_to_plane
	mov	[VDD_restore_graphics], edx
	mov	[VDD_restore_text], edx
	mov	[VDD_restore_font], OFFSET32 VDD_Font_restore_font
	jmp	short rp_start
rp_not_saved:
	mov	[VDD_restore_graphics], OFFSET32 VDD_VM_Mem_zero_page
	mov	[VDD_restore_text], OFFSET32 VDD_VM_Mem_init_text
	mov	[VDD_restore_font], OFFSET32 VDD_VM_Mem_zero_page

rp_start:
	call	VDD_State_Set_MemC_Owner
	test	[edi.VDD_Stt.C_Mode], 1     ;Q: CGA compatibility enabled?
	jz	short rp_oddeven	    ;	Y: mode 4, 5 or 6 use 1 plane

	mov	dl, [edi.VDD_Stt.G_Misc]
	and	dl, fGrp6Char OR fGrp6Chain
	cmp	dl, fGrp6Char OR fGrp6Chain ;Q: chained graphics mode?
IFDEF	PVGA
	jnz	short rpp_not_pvga
; PVGA mode 5Ah - 1024x768x2 comes to here too. Distinguish it!!! - C. Chiang -
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	rp_chained
	test	[edi.VDD_Stt.C_HDisp], 10h  ;Q: PVGA mode 5Ah
	jz	rp_chained	    ;	N: must be chained graphics mode
rpp_not_pvga:
ELSE
	je	DEBFAR rp_chained	    ;	Y:
ENDIF

	mov	dl, [edi.VDD_Stt.S_MMode]
	test	dl, fSeq4Chain4 	;Q: in chain4 mode?
	jnz	rp_chain4		;   Y: save 1 plane
	test	dl, fSeq4SqAd		;Q: in odd/even mode?
	jnz	rp_not_oddeven		;   N:

IFDEF	PVGA
; PVGA mode 5Bh - 1024x768x4 comes to here too. Distinguish it!!! - C. Chiang -
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	SHORT @F
	push	edx
	mov	dl, [edi.VDD_Stt.S_ClMode]     ;Q: PVGA 5Ah mode
	cmp	dl, 5
	pop	edx
	je	rp_not_oddeven		;   Y:
@@:
ENDIF

rp_oddeven:
;
; copy planes 0 & 1 as 1 plane, and then copy the font in plane 2
;
	xor	edx, edx
	call	VDD_PH_Mem_Access_Page	; ecx = phy pg # for copy source
	lea	esi, [edi.VDD_MStt.MSS_plane0]
	mov	dl, 3			; enable writes to planes 0 & 1
	call	VDD_VM_Mem_Chk_MemC_State

	test	[edi.VDD_Stt.G_Misc], fGrp6Char ;Q: graphics mode?
	jz	short rp_text		;   N:
	call	[VDD_restore_graphics]	;   Y: restore CGA graphics page
	jmp	rp_exit
rp_text:
	call	[VDD_restore_text]

	movzx	ecx, [eax.PDS_virtual_id]
	shr	ecx, 1
	bt	dword ptr [edi.VDD_fontpages], ecx;Q: page part of a loaded font?
	jnc	rp_exit 		;   N: don't attempt font restore
	push	eax
	call	VDD_State_Set_MemC_Planar
	call	VDD_OEM_Adjust_Font_Access  ; some OEM adapters need to modify
					    ;	the planar state for saving or
					    ;	restoring the soft text fonts.
	pop	eax
IFDEF	DEBUG
	jnc	SHORT rp_DB_00
Debug_Out "Text mode font restore failed"
rp_DB_00:
ENDIF
	xor	edx, edx
	push	ebx
	xor	ebx, ebx		; flag as planar mode
	call	VDD_PH_Mem_Access_Page	; ecx = phy pg # for copy dest
	pop	ebx
	mov	dx, 402h		; select plane 2
	call	VDD_VM_Mem_Select_Plane
	lea	esi, [edi.VDD_MStt.MSS_plane2]
	call	[VDD_restore_font]
	jmp	rp_exit

rp_chained:
	xor	edx, edx
	call	VDD_PH_Mem_Access_Page	; ecx = phy pg # for copy source
;
; modify state to insure that we're reading planes 0 & 1
;
	call	VDD_State_Clear_MemC_Owner ; flag that MemC is owned by VDD
	mov	dl, 3
	call	VDD_VM_Mem_Chk_MemC_State
	mov	dx, 300h		; reads & writes for planes 0 & 1
	call	VDD_VM_Mem_Select_Plane ; select plane 0
	lea	esi, [edi.VDD_MStt.MSS_plane0]
	call	[VDD_restore_graphics]
	mov	dx, 0C02h		; reads & writes for planes 2 & 3
	call	VDD_VM_Mem_Select_Plane ; select plane 2
	lea	esi, [edi.VDD_MStt.MSS_plane2]
	call	[VDD_restore_graphics]
IFDEF TLVGA
	jmp	rp_exit
ELSE
	jmp	short rp_exit
ENDIF

rp_not_oddeven:

;********************************************************************
IF 0
IFDEF	PVGA
; Now, all the 256-color modes come here.  For 256K memory save/restore,
; save 4 planes for PVGA extended 256-color modes will have the same result
; of saving 4 banks.  The standard mode 13h, only one 64k bank is used.  
; However, this copy-1-plane code will not work if extended 256-color Windows
; display driver is used.  ????????? 
;							- C. Chinag -
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short rpp_not_5pvga
;;???	cmp	byte ptr [edi.VDD_Stt.C_LnOff], 28h	; Q: mode 13h?
;;???	jnz	short rp_not_chain4	;   N: restore all 4 planes
	jmp	short rp_not_chain4	;   N: restore all 4 planes
rpp_not_5pvga:
ENDIF	;PVGA
ENDIF	;0
;********************************************************************

IFDEF TLVGA
	TestMem [edi.VDD_TFlags],fVT_TLVGA	    ;if ET3000
	jz	short rp_2
	;if ET3000, test ATC 10 bit 6 also for 256 color mode
	test	[edi.VDD_Stt.A_Mode],040h
	jnz	short rp_chain4
rp_2:
ENDIF

	test	dl, fSeq4Chain4 	;Q: in chain4 mode?
	jz	short rp_not_chain4	;   N: restore all 4 planes
					;   Y: ignore plane request

rp_chain4:
;
; copy 1 plane
;
	xor	edx, edx
	call	VDD_PH_Mem_Access_Page	; ecx = phy pg # for copy source
	mov	dl, 0Fh 		; enable writes to all planes
	call	VDD_VM_Mem_Chk_MemC_State
	lea	esi, [edi.VDD_MStt.MSS_plane0]
IFDEF TLVGA
	TestMem [edi.VDD_TFlags], <fVT_TLVGA OR fVT_TL_ET4000>
	jz	SHORT rp_Not_TL00
	push	eax
	call	VDD_OEM_TLVGA_Set_Graphics
	xchg	eax, [esp]
rp_Not_TL00:
ENDIF
IFDEF IBMXGA
	call	VDD_OEM_Chk_DoubleWord
ENDIF

	call	[VDD_restore_graphics]

IFDEF IBMXGA
	call	VDD_OEM_Restore_DoubleWord
ENDIF
IFDEF TLVGA
	TestMem [edi.VDD_TFlags], <fVT_TLVGA OR fVT_TL_ET4000>
	jz	SHORT rp_Not_TL01
	xchg	eax, [esp]
	call	VDD_OEM_TLVGA_Reset_Graphics
	pop	eax
rp_Not_TL01:
ENDIF

	jmp	rp_exit

rp_not_chain4:
;
; copy all 4 planes
;
	push	eax
	call	VDD_State_Set_MemC_Planar
	pop	eax
IFDEF	DEBUG
;	jnc	SHORT rp_DB_01
;race_Out "Graphics mode restore failed"
;p_DB_01:
ENDIF
	xor	edx, edx
	push	ebx
	xor	ebx, ebx		; flag as planar mode
	call	VDD_PH_Mem_Access_Page
	pop	ebx
	lea	esi, [edi.VDD_MStt.MSS_plane0]
	xor	edx, edx		; start with plane 0
	inc	dh
rp_save_lp:
	call	VDD_VM_Mem_Select_Plane

IFDEF	PVGA
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short @F
; Set WDC special hardware for 132-column text mode font on plane 2.
; Since Windows 3.1 restore window screen registers before clearing plane 2
; area occupied by font in DOS full screen.  Special care needs to be done
; for WDC 132-column text modes which are in page modes. - C. Chiang -
	test	dh, 100b
	jz	short @F
	call	VDD_OEM_PVGA_Adjust_Page_Mode_X_Regs
@@:
ENDIF
	cmp	[esi.MSS_plane_size], 0 ;Q: any save memory for plane?
	jne	short rp_normal_res	;   Y: do normal restore
	cmp	dl, 1			;Q: restoring plane 1?
	jne	short rp_normal_res	;   N: do normal restore
;
; We are probably restoring a text page while the VM is temporarily in a
; planar mode while it is loading a soft font, so we need to restore plane 1
; as a copy of plane 0 shifted 1 byte
;
	TestMem [edi.VDD_Flags], <fVDD_Font OR fVDD_DirFont>
					    ;Q: VM loading a font
IFDEF DEBUG_verbose
	jnz	short rpf_D00
	Debug_Out 'restoring plane 1 with no save mem and not loading font'
rpf_D00:
ENDIF
	jz	short rp_normal_res	    ;	N: normal restore
	sub	esi, SIZE MSS_Plane_Info_Struc
	call	VDD_VM_Mem_restore_attribute_page
	add	esi, (SIZE MSS_Plane_Info_Struc)*2
	jmp	short rp_next_plane

rp_normal_res:
	call	[VDD_restore_graphics]
	add	esi, SIZE MSS_Plane_Info_Struc
rp_next_plane:

IFDEF	PVGA
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short no_reset
; Reset WDC special hardware for 132-column plane 2 (font in page mode)
	test	dh, 100b		; plane 2?
	jz	short no_reset		;    N: don't do this
	call	VDD_OEM_PVGA_Adjust_Page_Mode_X_Regs

; Reset 3x4.29 scratch bit #4 to back to 0 for all WDC modes
	push	edx			; save 3x4
	push	eax			; save 3x4

        mov     edx,3cch
        in      al,dx
        IO_Delay
        test    al,1
        mov     dl,0d4h
        jnz     SHORT @F
        mov     dl,0b4h
@@:
	in	al, dx
	push	eax			; save 3x4 index

	mov	al, 29h
	out	dx, al
	inc	dx
;;	mov	al, 85h
	in	al, dx
	jmp	$+2
	and	al, not 10h		; clear scratch bit #4 for all modes
	out	dx, al
	dec	dx

	pop	eax			; restore 3x4 index
	out	dx, al

	pop	eax
	pop	edx
no_reset:
ENDIF
	inc	dl
	shl	dh, 1			; enable write to next plane
	cmp	dl, 4
	jb	rp_save_lp

rp_exit:
	queue_out 'end restore page #eax'
	VMMCall End_Critical_Section
	clc
	ret

EndProc VDD_VM_Mem_Restore_Page


;******************************************************************************
;
;   VDD_VM_Mem_Select_Plane
;
;   DESCRIPTION:    Set read & write of specified plane
;
;   ENTRY:	    DL = plane # (0, 1, 2, or 3)
;		    DH = plane write mask for Seq.2
;
;   EXIT:	    none
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Select_Plane

	push	eax
	push	edx
	mov	edx, pGrpIndx
	mov	al, 4
	out	dx, al
	IO_Delay
	inc	dl
	mov	al, [esp]
	out	dx, al
	IO_Delay
	mov	edx, pSeqIndx
	mov	al, 2
	out	dx, al
	IO_Delay
	inc	dl
	mov	al, [esp+1]		; al = plane mask
	out	dx, al
	pop	edx
	pop	eax
	ret

EndProc VDD_VM_Mem_Select_Plane


;******************************************************************************
;
;   VDD_VM_Mem_Chk_Plane_Size
;
;   DESCRIPTION:    Determine if page is part of allocated VM's save memory
;		    for a particular plane.
;
;   ENTRY:	    DX = page index into plane
;		    ESI -> MSS_Plane_Info_Struc
;		    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    Carry set, if save memory doesn't include page
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Chk_Plane_Size

	cmp	dx, [esi.MSS_plane_alloced] ;Q: page alloc'ed in plane?
	jb	short cps_exit		    ;	Y: jump with carry set
	cmp	dx, [esi.MSS_plane_size]    ;Q: page within valid size of plane?
	jae	short cps_exit		    ;	Y: jump with carry clear
	VMMCall Test_Sys_VM_Handle	    ;Q: error in SYS VM?
	jz	short @F		    ;	Y: no message
	pushad				    ;	N: notify user of error
	call	VDD_Error_NoMainMem
	popad
@@:
	clc

cps_exit:
	cmc
	ret

EndProc VDD_VM_Mem_Chk_Plane_Size


;******************************************************************************
;
;   VDD_VM_Mem_Lock_SaveMem_Page
;
;   DESCRIPTION:
;
;   ENTRY:	    DX = page index into plane
;		    ESI -> MSS_Plane_Info_Struc
;		    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    Carry set, if savemem page doesn't exit, or can't be locked
;
;		    WARNING:  This modifies the stack!!!!!!!!!!!!!!!!!!!!!
;
;			If Carry clear, then
;			    [esi.MSS_plane_handle] and EDX have been saved on
;			    the stack
;
;
;   USES:
;
;==============================================================================
BeginProc VDD_VM_Mem_Lock_SaveMem_Page

	call	VDD_VM_Mem_Chk_Plane_Size
	jc	short lsp_exit
	push	edx
	push	ecx
	VMMCall _PageLock,<[esi.MSS_plane_handle],1,edx,0>
	pop	ecx
	pop	edx
	or	eax, eax
	stc
	jz	short lsp_exit
	pop	eax			; save return address
	push	[esi.MSS_plane_handle]
	push	edx
	push	eax			; restore return address
	clc

lsp_exit:
	ret

EndProc VDD_VM_Mem_Lock_SaveMem_Page


;******************************************************************************
;
;   VDD_VM_Mem_copy_from_plane
;
;   DESCRIPTION:    Copy a 4Kb page from physical video memory to a page of
;		    VM save memory.  This routine just does a straight
;		    4K REP MOVSB, so it will copy 4K bytes from which ever
;		    plane(s) is(are) selected.
;
;   ENTRY:	    EAX = page handle
;		    EBX = owner VM handle
;		    EDI = VDD CB ptr
;		    ECX = physical page #
;		    ESI -> MMS_Plane_Info_Struc for plane being saved
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_VM_Mem_copy_from_plane

	pushad
	movzx	edx, [eax.PDS_virtual_id]
	call	VDD_VM_Mem_Lock_SaveMem_Page
	jc	short cfp_exit
	mov	edi, edx
	shl	edi, 12
	add	edi, [esi.MSS_plane_addr]   ; edi -> copy dst in copy mem
	shl	ecx, 12 		    ; convert src page # to adr
	sub	ecx, 0A0000h
	add	ecx, [Vid_PhysA0000]	    ; convert phys adr to linear
	mov	esi, ecx
	mov	ecx, P_SIZE
	cld
	rep	movsb
	pop	ecx			    ; pop page # & mem handle from call
	pop	eax			    ; to VDD_VM_Mem_Lock_SaveMem_Page
	VMMCall _PageUnLock,<eax,1,ecx,0>
cfp_exit:
	popad
	ret

EndProc VDD_VM_Mem_copy_from_plane


;******************************************************************************
;
;   VDD_VM_Mem_save_attribute_page
;
;   DESCRIPTION:    Copy a 4Kb page of text attribute bytes (even bytes from
;		    plane 1) into the odd bytes in plane 0 save memory.
;		    This routine requires that the hardware be set up in
;		    planar read mode.
;
;   ENTRY:	    EAX = page handle
;		    EBX = owner VM handle
;		    EDI = VDD CB ptr
;		    ECX = physical page #
;		    ESI -> MMS_Plane_Info_Struc for plane 0
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_VM_Mem_save_attribute_page

	pushad
	movzx	edx, [eax.PDS_virtual_id]
	call	VDD_VM_Mem_Lock_SaveMem_Page
	jc	short sap_exit
	mov	edi, edx
	shl	edi, 12
	add	edi, [esi.MSS_plane_addr]   ; edi -> copy dst in copy mem
	shl	ecx, 12 		    ; convert src page # to adr
	sub	ecx, 0A0000h
	add	ecx, [Vid_PhysA0000]	    ; convert phys adr to linear
	mov	esi, ecx
	mov	ecx, P_SIZE/2		    ; # of attribute bytes to copy
	cld
sap_loop:
	inc	edi			    ; skip character byte in savemem
	movsb
	inc	esi			    ; skip undefined byte
	loop	sap_loop
	pop	ecx			    ; pop page # & mem handle from call
	pop	eax			    ; to VDD_VM_Mem_Lock_SaveMem_Page
	VMMCall _PageUnLock,<eax,1,ecx,0>
sap_exit:
	popad
	ret

EndProc VDD_VM_Mem_save_attribute_page


IFDEF DEBUG
BeginProc VDD_VM_Mem_Chk_Bank_DEBUG

	TestMem [VT_Flags], fVT_TL_ET4000
	jz	short mcb_D00_exit
	push	eax
	push	edx
	mov	edx, 3CDh
	in	al, dx
	or	al, al
	jz	short @F
	Debug_Out 'segment select register not correct #al'
@@:
	pop	edx
	pop	eax
mcb_D00_exit:
	ret

EndProc VDD_VM_Mem_Chk_Bank_DEBUG
ENDIF


;******************************************************************************
;
;   VDD_VM_Mem_restore_attribute_page
;
;   DESCRIPTION:    Copy a 4Kb page of a text mode plane 0 save memory
;		    to a physical video memory page.  This routine
;		    requires that the hardware be set up for a planar write.
;
;   ENTRY:	    EAX = page handle
;		    EBX = owner VM handle
;		    EDI = VDD CB ptr
;		    ECX = physical page #
;		    ESI -> MMS_Plane_Info_Struc for plane 0
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_VM_Mem_restore_attribute_page

	pushad
IFDEF DEBUG
	call	VDD_VM_Mem_Chk_Bank_DEBUG
ENDIF
	movzx	edx, [eax.PDS_virtual_id]
	call	VDD_VM_Mem_Lock_SaveMem_Page
	jc	short init_attribute_page
	shl	edx, 12
	add	edx, [esi.MSS_plane_addr]   ; edx -> copy src in copy mem
	inc	edx			    ; copy plane 0 to plane 1 shift
	mov	edi, ecx		    ;	 1 byte to left
	mov	ecx, P_SIZE-1		    ; we can ignore the last byte
	jmp	short ctp_do_plane_copy     ; jump into VDD_VM_Mem_copy_to_plane

init_attribute_page:
	mov	ax,  2007h		    ; even bytes get 07's and odd bytes
					    ;	get 20's
	jmp	DEBFAR MIT_do_text_init     ; jump into VDD_VM_Mem_Init_Text


EndProc VDD_VM_Mem_restore_attribute_page


;******************************************************************************
;
;   VDD_VM_Mem_copy_to_plane
;
;   DESCRIPTION:    Copy a 4Kb page from VM save memory to a physical video
;		    memory page.  This routine just does a straight
;		    4K REP MOVSB, so it will copy 4K bytes to which ever
;		    plane(s) is(are) selected.
;
;   ENTRY:	    EAX = page handle
;		    EBX = owner VM handle
;		    EDI = VDD CB ptr
;		    ECX = physical page #
;		    ESI -> MMS_Plane_Info_Struc for plane being restored
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_VM_Mem_copy_to_plane

	pushad
IFDEF DEBUG
	call	VDD_VM_Mem_Chk_Bank_DEBUG
ENDIF
	movzx	edx, [eax.PDS_virtual_id]
	call	VDD_VM_Mem_Lock_SaveMem_Page
	jc	short VDD_VM_Mem_zero_page_no_pushad ; jump into
					    ; VDD_VM_Mem_zero_page
	shl	edx, 12
	add	edx, [esi.MSS_plane_addr]   ; edx -> copy src in copy mem
	mov	edi, ecx
	mov	ecx, P_SIZE
ctp_do_plane_copy:
	shl	edi, 12 		    ; convert dst page # to adr
	sub	edi, 0A0000h
	add	edi, [Vid_PhysA0000]	    ; convert phys adr to linear
	mov	esi, edx
	cld
	rep	movsb
	pop	ecx			    ; pop page # & mem handle from call
	pop	eax			    ; to VDD_VM_Mem_Lock_SaveMem_Page
	VMMCall _PageUnLock,<eax,1,ecx,0>
	popad
	ret

EndProc VDD_VM_Mem_copy_to_plane


;******************************************************************************
;
;   VDD_VM_Mem_zero_page
;
;   DESCRIPTION:    Default restore routine which will write a 4Kb page with
;		    0's, if VDD_VM_Mem_Restore_Page is called for a page
;		    which has never been saved.
;
;   ENTRY:	    EAX = page handle
;		    EBX = owner VM handle
;		    EDI = VDD CB ptr
;		    ECX = physical page #
;		    ESI -> MMS_Plane_Info_Struc for plane being saved
;
;   EXIT:	    none
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_zero_page

	pushad
IFDEF DEBUG
	call	VDD_VM_Mem_Chk_Bank_DEBUG
ENDIF

PUBLIC VDD_VM_Mem_zero_page_no_pushad
VDD_VM_Mem_zero_page_no_pushad:
zp_do_zeroing:
	shl	ecx, 12 		    ; convert dst page # to adr
	sub	ecx, 0A0000h
	add	ecx, [Vid_PhysA0000]	    ; convert phys adr to linear
	mov	edi, ecx
	xor	eax, eax
	mov	ecx, P_SIZE
	cld
	rep	stosb
	popad
	ret

EndProc VDD_VM_Mem_zero_page


;******************************************************************************
;
;   VDD_VM_Mem_init_text
;
;   DESCRIPTION:    Default restore routine which will write a 4Kb page with
;		    [' ', 7]'s (a character space and an attribute of 7), if
;		    VDD_VM_Mem_Restore_Page is called for a text page which
;		    has never been saved.
;
;   ENTRY:	    EAX = page handle
;		    EBX = owner VM handle
;		    EDI = VDD CB ptr
;		    ECX = physical page #
;		    ESI -> MMS_Plane_Info_Struc for plane being saved
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_VM_Mem_init_text

	pushad
IFDEF DEBUG
	call	VDD_VM_Mem_Chk_Bank_DEBUG
ENDIF
	mov	ax,  0720h		    ; odd bytes get 07's and even bytes
					    ;	get 20's
MIT_do_text_init:
	shl	ecx, 12 		    ; convert dst page # to adr
	sub	ecx, 0A0000h
	add	ecx, [Vid_PhysA0000]	    ; convert phys adr to linear
	mov	edi, ecx
	mov	ecx, P_SIZE/2
	cld
MIT_Loop:
	stosb
	xchg	ah,al
	stosb
	xchg	ah,al
	loopd	MIT_Loop
	popad
	ret

EndProc VDD_VM_Mem_init_text


;******************************************************************************
;
;   VDD_VM_Mem_Alloc_Msg_Mode_Mem
;
;   DESCRIPTION:    Allocate the visible pages of video memory needed for
;		    message mode for VDD use.
;
;		    By allocating them from VDDPHMem we force the current
;		    memory to be saved for the current owner.
;
;   ENTRY:	    none
;
;   EXIT:	    none
;
;   USES:	    EAX, EBX, ESI, EDI, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Alloc_Msg_Mode_Mem

	mov	ebx, [Vid_Msg_Pseudo_VM]		; owned by VDD
	SetVDDPtr edi
	call	VDD_VM_Mem_MemC_about_to_change
	xor	edx, edx
	mov	esi, OFFSET32 VDD_VM_Mem_Msg_Page_Handler
	movzx	ecx, [Vid_Msg_Pages]
@@:
	mov	eax, edx
	call	VDD_PH_Mem_Alloc_Video_Page
	inc	edx
	loop	@B
	ret

EndProc VDD_VM_Mem_Alloc_Msg_Mode_Mem


;******************************************************************************
;
;   VDD_VM_Mem_Save_Dirty_State
;
;   DESCRIPTION:    Walk thru list of all video pages owned by a VM; OR the
;		    physical dirty bits from the page table of any mapped
;		    page into the page flags for that page and clear the
;		    physical dirty bit.
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    EAX, ECX, EDX, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Save_Dirty_State

Assert_VDD_ptrs ebx,edi
	push	esi
	mov	esi, [edi.VDD_PageMap]
	xor	ecx, ecx
sds_loop:
	mov	eax, [esi][ecx*4]
	or	eax, eax
	jz	short sds_next

%OUT optimization: copy whole page table instead of using VDD_VM_Mem_Get_PTE
	push	ecx
	movzx	ecx, [eax.PDS_linear_page]
	jecxz	short sds_not_dirty	    ;jump if page not mapped
	call	VDD_VM_Mem_Get_PTE
	test	cl, P_DIRTY		    ;Q: dirty bit set?
	jz	short sds_not_dirty
	or	[eax.PDS_flags], fPDS_Dirty
	movzx	ecx, [eax.PDS_linear_page]
	push	ecx
	VMMCall _ModifyPageBits,<ebx,ecx,1,0FFFFFFFFh,0,PG_IGNORE,0>
	pop	ecx
;
; touch page to set its accessed bit so that we don't think that we are in
; a dead lock situation at page fault time
;
	shl	ecx, 12 		    ; convert to linear address
	add	ecx, [ebx.CB_High_Linear]
	mov	cl, [ecx]

	mov	eax, [esp]
	call	VDD_VM_Mem_Record_VRAM_Mod
sds_not_dirty:
	pop	ecx
sds_next:
	inc	ecx
	cmp	ecx, [edi.VDD_VideoPages]
	jb	sds_loop
	pop	esi
	ret

EndProc VDD_VM_Mem_Save_Dirty_State


;******************************************************************************
;
;   VDD_VM_Mem_Free_Pages
;
;   DESCRIPTION:    Free all video pages owned by VM
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    EAX, ESI, Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Free_Pages

Assert_VDD_ptrs ebx,edi
	cmp	[edi.VDD_Owned_Pages], 0	    ;Q: VM own physical pages?
	je	short fps_exit

	pushad
	call	VDD_VM_Mem_Disable
	mov	esi, [edi.VDD_PageMap]
	xor	edx, edx
fp_dealloc_lp:
	mov	eax, [edx*4][esi]
	or	eax, eax			    ;Q: page owned?
	jz	short fp_next			    ;	N:
IFDEF DEBUG
;
; Verify that all phys pages have been unmapped by calling
; VDD_VM_Mem_Is_Page_Dirty.  VDD_VM_Mem_Disable, called above, should have
; unmapped all pages and called VDD_VM_Mem_Is_Page_Dirty in the process so
; that the physical dirty bit was OR'ed into PDS_flags.
;
	call	VDD_VM_Mem_Is_Page_Dirty
	jc	short fp_D00
	Debug_Out 'phys page still mapped at end of VDD_VM_Mem_Free_Pages'
fp_D00:
ENDIF
	and	[eax.PDS_flags], NOT fPDS_Dirty     ; we don't need to save the page
	call	VDD_PH_Mem_Free_Page
fp_next:
	inc	edx
	cmp	edx, [edi.VDD_VideoPages]
	jb	fp_dealloc_lp
	popad
fps_exit:
	ret

EndProc VDD_VM_Mem_Free_Pages


;******************************************************************************
;
;   VDD_VM_Mem_Record_VRAM_Mod
;
;   DESCRIPTION:    Record a video page modification (indicated by the dirty
;		    bit being set) by setting the VM flag in VDD_Flags and
;		    by setting the page bit in the modified pages array
;		    (VDD_VRAM_Mods).
;
;   ENTRY:	    EAX = virtual page id
;		    EBX = VM handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    none
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_VM_Mem_Record_VRAM_Mod

Assert_VDD_ptrs ebx,edi
	push	eax
	VMMCall Get_Last_Updated_System_Time
	mov	[edi.VDD_ModTime], eax
	pop	eax
	bts	[edi.VDD_VRAM_Mods], eax
	ret

EndProc VDD_VM_Mem_Record_VRAM_Mod


IFDEF DEBUG
;******************************************************************************
;
;   VDD_VM_Mem_Debug_Dump_Pages
;
;   DESCRIPTION:    Dump a list of table showing VM memory usage for debugging.
;
;   ENTRY:	    EBX = VM handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    none
;
;   USES:	    anything
;
;==============================================================================
BeginProc VDD_VM_Mem_Debug_Dump_Pages

Assert_VDD_ptrs ebx,edi
	pushad
	mov	al, [edi.VDD_Owned_Pages]
	Trace_Out 'Display virtual video page table, VM owns #al phys pages'
	mov	esi, [edi.VDD_PageMap]
	mov	ebp, [edi.VDD_PageFlags]
	call	VDD_State_Get_Mem_Mapping
	movzx	edx, al
	mov	ebx, eax
	xor	bl, bl
	mov	eax, 16
	cmp	dl, 0A0h
	je	short ddp_graphics
	mov	al, 8
ddp_graphics:
	push	eax
	push	ebx
	mov	ebx, [esp.Pushad_EBX+8]
	call	VDD_PH_Mem_Get_Visible_Pages
	pop	ebx
	add	ecx, eax
	cmp	ecx, [esp]
	jbe	short ddp_got_length
	mov	[esp], ecx
ddp_got_length:
	mov	ecx, edx
	xor	eax, eax
	jmp	short ddp_first

ddp_loop:
	test	al, 11b
	jnz	short ddp_no_hdr
	Trace_Out ' '
ddp_first:
	Trace_Out '#dx  ', NOEOL
ddp_no_hdr:

	push	edx
	mov	dl, [eax][ebp]
	test	dl, fPageSaveMem
	jz	short ddp_get_handle
	Trace_Out '  #ax   #dl ', NOEOL
	jmp	short ddp_nxt_pg

ddp_get_handle:
	push	eax
	mov	eax, [eax*4][esi]
	Trace_Out '#eax #dl ', NOEOL
	pop	eax

ddp_nxt_pg:
	pop	edx
	inc	eax
	inc	dl			; inc page #
	inc	bl			; inc page within bank counter
	cmp	bl, bh
	jb	short ddp_no_bank_inc
	inc	dh			; inc bank counter
	xor	bl, bl			; zero page within bank counter
	mov	dl, cl			; reset base page within mapping
ddp_no_bank_inc:
	cmp	eax, [esp]
	jb	ddp_loop
	pop	eax			; discard saved max count
	popad
	Trace_Out ' '
	ret

EndProc VDD_VM_Mem_Debug_Dump_Pages
ENDIF

VxD_CODE_ENDS

	END
