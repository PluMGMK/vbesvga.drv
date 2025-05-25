PAGE 58,132
;******************************************************************************
TITLE vddphmem.asm -
;******************************************************************************
;
;   (C) Copyright MICROSOFT Corp.  All Rights Reserved, 1989-1991
;
;   Title:	vddphmem.asm -
;
;   Version:	1.00
;
;   Date:	13-Jun-1990
;
;   Author:	RAP
;
;------------------------------------------------------------------------------
;
;   Documentation:
;
;   Physical page # - a number used to identify a 4Kb portion of video memory.
;   Each page is viewed as being made up of 4 planes, so a 4Kb page is really
;   16Kb worth of video memory.  A physical page # is a 0-based value.
;
;   Physical page ownership is tracked with 2 data structures.	This first is
;   an array of Phys_Page_Data entries; 1 entry for each physical page.  If
;   the physical page is owned, then it points to the first owner page handle
;   in the page handle list.  So the 2nd structure is a list of page handles.
;   A page handle exists for each virtual page that VDDVMMEM is using to map
;   physical memory into a VM's address space.  Only a single list is
;   maintained, so it includes page handles from multiple VM's, etc.
;
;   In some modes on some hardware, it is possible to have multiple page
;   handles owning the same physical page, but they must all be for the same
;   VM.  It is NOT possible for different VM's to own different parts of the
;   same physical page!  When multiple page handles own the same physical page
;   the physical page points to the first in the page handle list and the rest
;   of the page handles are linked one after another immediately after it in
;   the list.
;
;
;   PAGE
;	|--------------|	      |--------------------|
;   0	| PPD_LRU_time |<-------------| PDS_physpage	=0 |
;	| PPD_owner_PH |---------|--->| PDS_flags	   |
;	|--------------|	 |    | PDS_virtual_id	=2 |
;   1	| PPD_LRU_time |	 |    | PDS_linear_page =A2|
;	| PPD_owner_PH |	 |    | PDS_owner	   |
;	|--------------|	 |    | PDS_callback	   |
;   2	| PPD_LRU_time |<-----|  |    |--------------------|
;	| PPD_owner_PH |----| |  |
;	|--------------|    | |  |    |--------------------|
;   3	| PPD_LRU_time |    | |   ----| PDS_physpage	=0 |
;	| PPD_owner_PH |    | |       | PDS_flags	   |
;	|--------------|    | |       | PDS_virtual_id	=0 |
;			    | |       | PDS_linear_page =A0|
;			    | |       | PDS_owner	   |
;			    | |       | PDS_callback	   |
;			    | |       |--------------------|
;			    | |
;			    | |       |--------------------|
;			    |  -------| PDS_physpage	=2 |
;			    |-------->| PDS_flags	   |
;				      | PDS_virtual_id	=7 |
;				      | PDS_linear_page =A7|
;				      | PDS_owner	   |
;				      | PDS_callback	   |
;				      |--------------------|
;
;------------------------------------------------------------------------------
;
;   Change log:
;
;      DATE	REV		    DESCRIPTION
;   ----------- --- -----------------------------------------------------------
;   13-Jun-1990 RAP
;   29-Mar-1991 RAP Documentation & code review corrections
;
;==============================================================================

	.386p

.xlist
	INCLUDE VMM.INC
	INCLUDE OPTTEST.INC
	INCLUDE DEBUG.INC
	INCLUDE VDDDEF.INC
	INCLUDE VDDPHMEM.INC
.list


;******************************************************************************
; EXTRN routines
;
VxD_CODE_SEG
	EXTRN	VDD_State_Get_Mem_Mapping:NEAR
	EXTRN	VDD_State_Set_MemC_Planar:NEAR
	EXTRN	VDD_State_Get_Dimensions:NEAR
	EXTRN	VDD_State_Modify_VMs_MemC:NEAR
	EXTRN	VDD_State_Get_Screen_Start:NEAR
	EXTRN	VDD_State_Clear_MemC_Owner:NEAR
	EXTRN	VDD_VM_Mem_Font_Page:NEAR
VxD_CODE_ENDS


;******************************************************************************
; EXTRN data
;
VxD_DATA_SEG
	EXTRN	VT_Flags:DWORD
	EXTRN	Vid_CRTC_VM:DWORD
	EXTRN	Vid_MemC_VM:DWORD
	EXTRN	Vid_CB_Off:DWORD
	EXTRN	Vid_Focus_VM:DWORD
	EXTRN	VDD_Str_CheckVidPgs:BYTE
	EXTRN	Vid_Msg_Pseudo_VM:DWORD
	EXTRN	Vid_Msg_Pseudo_CB:BYTE

PUBLIC	Vid_PhysA0000
Vid_PhysA0000		dd  ?

Vid_Sys_Visible_Pages	dd  -1	; # of visible pages at INT 2F from display driver
				;   -1 means that it hasn't been set yet
Vid_Sys_First_Visible	dw  0
Vid_Latch_Bank		db  ?
Vid_Sys_VM_Latch_Bank	db  0

PUBLIC	Vid_Latch_Addr
Vid_Latch_Addr		dd  ?
Vid_Sys_VM_Latch_Addr	dd  0

PUBLIC	Video_Pages, Video_Page_Table
Video_Pages	    dd	16	; # of physical video pages
Video_Page_Table    dd	?	; ptr to table of Phys_Page_Data strucs
VDD_PageHandle_List dd	?	; list handle for list of page handles

Phys_Page_Data	STRUC
PPD_LRU_time	    dd	?	; sys time of last access
PPD_owner_PH	    dd	?	; page handle of virtual owner
Phys_Page_Data	ENDS

PPD_Index_Factor    equ 3
.errnz SIZE Phys_Page_Data - (1 SHL PPD_Index_Factor)


PPD_Index_to_Ptr MACRO reg
	shl	reg, PPD_Index_Factor
	add	reg, [Video_Page_Table]
ENDM

PPD_Ptr_to_Index MACRO reg
	sub	reg, [Video_Page_Table]
	shr	reg, PPD_Index_Factor
ENDM

IFDEF DEBUG
PUBLIC VDD_DPD
VDD_DPD 	db  0	; non-zero if demoing demand paging
ENDIF

VxD_DATA_ENDS


VxD_ICODE_SEG

;******************************************************************************
;
;   VDD_PH_Mem_Sys_Critical_Init
;
;   DESCRIPTION:    Map A0 thru BF as physical=linear in SYS VM.  Allocate
;		    the video page table.  And create the page handle list.
;
;   ENTRY:	    EBX = SYS VM Handle
;
;   EXIT:	    none
;
;   USES:	    EAX, ECX, EDX, ESI, Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Sys_Critical_Init

;*******
; Set up physical addresses for the video memory
;
	VMMCall _MapPhysToLinear,<0A0000h,20000h,0>
	inc	eax
	jnz	SHORT VDD_SI_GotPhysAddr
	Debug_Out "VDD: Cannot address video memory(A0000h-BFFFFh)"
	jmp	short VDD_SI_ErrPgs
VDD_SI_GotPhysAddr:
	dec	eax
	mov	[Vid_PhysA0000],eax

;*******
; Set up other special physical memory pointers
	add	eax,0AFFFFh-0A0000h
	mov	[Vid_Latch_Addr], eax
	mov	[Vid_Latch_Bank], 0

;
; Allocate Video_Page_Table
;
	mov	eax, [Video_Pages]
	shl	eax, PPD_Index_Factor
	VMMCall _HeapAllocate, <eax, HeapZeroInit>
	test	eax, eax
IFDEF DEBUG
	jnz	short VDD_SI_got_vid_pg_tab
	Debug_Out 'VDD failed to alloc video page table'
ENDIF
	jz	short VDD_SI_ErrExit
VDD_SI_got_vid_pg_tab:
	mov	[Video_Page_Table], eax

;
; Create list for page handles
;
	xor	eax, eax		    ; Flags = 0
	mov	ecx, SIZE Page_Data_Struc   ; ECX = size of each list node
	VMMCall List_Create
	jc	short VDD_SI_ErrExit
	mov	[VDD_PageHandle_List], esi  ; save list handle
	ret

VDD_SI_ErrPgs:
	Fatal_Error <OFFSET32 VDD_Str_CheckVidPgs>

VDD_SI_ErrExit:
	VMMJmp	Fatal_Memory_Error

EndProc VDD_PH_Mem_Sys_Critical_Init

VxD_ICODE_ENDS


VxD_CODE_SEG

;******************************************************************************
;
;   VDD_PH_Mem_Reset_Sys_Visible_Pages
;
;   DESCRIPTION:    Display driver is unloading, so all the info about latch
;		    addresses and visible pages becomes invalid
;
;   ENTRY:	    none
;
;   EXIT:	    Vid_Sys_Visible_Pages == -1
;
;   USES:	    EAX,Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Reset_Sys_Visible_Pages

	; reset visible pages
	xor	eax,eax
	mov	[Vid_Sys_First_Visible], ax
	not	eax
	mov	[Vid_Sys_Visible_Pages], eax

	; reset sys latch address
	not	eax
	mov	[Vid_Sys_VM_Latch_Bank], al
	mov	[Vid_Sys_VM_Latch_Addr], eax

	; reset general latch address
	mov	[Vid_Latch_Bank], al
	mov	eax,[Vid_PhysA0000]
	add	eax,0AFFFFh-0A0000h
	mov	[Vid_Latch_Addr], eax

	; done
	ret

EndProc VDD_PH_Mem_Reset_Sys_Visible_Pages

;******************************************************************************
;
;   VDD_PH_Mem_Set_Sys_Latch_Addr
;
;   DESCRIPTION:
;
;   ENTRY:	    EAX = Latch Addr
;		    CL = Latch Bank
;		    CH = 1st visible page in first bank
;		    EDX = visible pages in first bank
;
;   EXIT:	    none
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Set_Sys_Latch_Addr

	pushad
IFDEF SysVMin2ndBank
	TestMem [VT_Flags], fVT_SysVMin2ndBank
	jz	short @F
	inc	cl
	xor	ch, ch
	xor	edx, edx		    ; no visible pages in first bank
@@:
ENDIF
	mov	[Vid_Sys_VM_Latch_Bank], cl
	mov	[Vid_Sys_VM_Latch_Addr], eax
	mov	[Vid_Sys_Visible_Pages], edx
	movzx	ecx, ch
	mov	[Vid_Sys_First_Visible], cx
;;	  Trace_Out 'Sys latch addr = #ax, Sys visible pages = #dx'
;
; jump into VDD_PH_Mem_Set_Latch_Addr to set the original latch address
;
	jmp	set_sys_latch_adr

EndProc VDD_PH_Mem_Set_Sys_Latch_Addr


;******************************************************************************
;
;   VDD_PH_Mem_Save_Sys_Latch_Addr
;
;   DESCRIPTION:
;
;   ENTRY:	    none
;
;   EXIT:	    none
;
;   USES:	    EAX, Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Save_Sys_Latch_Addr

	push	ebx
	VMMCall Get_Sys_VM_Handle
	add	ebx, [Vid_CB_Off]
	TestMem [ebx.VDD_Flags], fVDD_DspDrvrAware
	pop	ebx
	jnz	short ssla_exit
	call	VDD_PH_Mem_Set_Latch_Addr
	mov	eax, [Vid_Latch_Addr]
	sub	eax, [Vid_PhysA0000]
	add	eax, 4000h			; round to be last byte before
	and	eax, NOT 3FFFh			;   a 16Kb boundary
	dec	eax
	mov	[Vid_Sys_VM_Latch_Addr], eax

	add	eax, [Vid_PhysA0000]
	mov	[Vid_Latch_Addr], eax
IFDEF SysVMin2ndBank
	TestMem [VT_Flags], fVT_SysVMnot1stBank ;Q: sys VM in 1st bank?
	jnz	short ssla_skip_vadjust 	;   N: don't set page variables
						;      because they were set
						;      by a forced call to
						;      VDD_PH_Mem_Set_Sys_Latch_Addr
						;      during device init
ENDIF
	sub	eax, [Vid_PhysA0000]
	shr	eax, 12
	inc	eax
	mov	[Vid_Sys_Visible_Pages], eax
ssla_skip_vadjust:

IFDEF DEBUG_verbose
	push	ecx
	mov	ecx, [Vid_Sys_Visible_Pages]
	Trace_Out 'Sys latch addr = #ax, Sys visible pages = #cx'
	pop	ecx
ENDIF
	call	VDD_PH_Mem_LRU_Sweep		; make sure new pages are
						;   LRU stamped as visible
ssla_exit:
	ret

EndProc VDD_PH_Mem_Save_Sys_Latch_Addr


;******************************************************************************
;
;   VDD_PH_Mem_Set_Latch_Addr
;
;   DESCRIPTION:    Search backwards thru video page table for first page
;		    owned by focus VM or pseudo VM which doesn't have an
;		    LRU stamp (indicating that it is visible) and select the
;		    last byte in this page as the location that VDDSTATE
;		    should use to save/restore the latches.
;
;   ENTRY:	    none
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Set_Latch_Addr

IFDEF SysVMin2ndBank
	TestMem [VT_Flags], fVT_SysVMnot1stBank
	jnz	short sla_ret		; if SYS VM not in 1st bank, then
					;   we can always use its latch addr
ENDIF
	pushad
	mov	ebx, [Vid_Focus_VM]
	VMMCall Test_Sys_VM_Handle	    ;Q: SYS VM?
	jne	short @F		    ;	N:
	cmp	[Vid_Sys_VM_Latch_Addr], 0  ;	Y: Q: has display driver specified
					    ;		a latch address?
	jne	short set_sys_latch_adr     ;		Y: use it
@@:
	mov	edx, [Vid_Msg_Pseudo_VM]
	mov	esi, [Video_Page_Table]
	mov	ecx, [Video_Pages]
IFDEF EXT_VGA
IFDEF TLVGA
	;if ET3000, max usable video pages if not hires mode=16 (256k bytes)
	call	Get_Usable_Video_Pages	;->ECX
ENDIF
ENDIF
	mov	eax, ecx
	dec	eax
	shl	eax, PPD_Index_Factor
	add	esi, eax		    ; esi -> last entry in Video_Page_Table
sla_loop:
	mov	eax, [esi.PPD_owner_PH]
	or	eax, eax		    ;Q: phys page owned?
	jz	short sla_next		    ;	N: skip
	cmp	edx, [eax.PDS_owner]	    ;Q: owned by pseudo VM?
	je	short sla_exit		    ;	Y: found latch page
	cmp	ebx, [eax.PDS_owner]	    ;Q: owned by focus VM?
	jne	short sla_next		    ;	N: skip
	cmp	[esi.PPD_LRU_time], 0	    ;Q: page have an LRU timestamp?
	je	short sla_exit		    ;	Y: found latch page

sla_next:
	sub	esi, SIZE Phys_Page_Data
	loop	sla_loop
	add	esi, SIZE Phys_Page_Data    ; default to first page

sla_exit:
	PPD_Ptr_to_Index esi
	mov	eax, esi
IFDEF Ext_VGA
	call	VDD_PH_Mem_Remove_Banking
ELSE
	xor	ecx, ecx
ENDIF
	mov	[Vid_Latch_Bank], cl
	shl	eax, 12
	or	eax, P_SIZE-1
sla_add_phys_base:
	add	eax, [Vid_PhysA0000]
;;Trace_Out 'Vid_Latch_Addr = #eax'
	mov	[Vid_Latch_Addr],eax
	popad
sla_ret:
	ret

set_sys_latch_adr:
	mov	al, [Vid_Sys_VM_Latch_Bank]
	mov	[Vid_Latch_Bank], al
	mov	eax, [Vid_Sys_VM_Latch_Addr]
	jmp	sla_add_phys_base

EndProc VDD_PH_Mem_Set_Latch_Addr


;******************************************************************************
;
;   VDD_PH_Mem_Access_Latch_Page
;
;   DESCRIPTION:    Called from VDDSTATE before saving or restoring the
;		    latches.  The MemC state has already been set planar.
;		    This routine adjusts banking, if necessary, on super VGAs
;		    and then returns the physical byte address that VDDSTATE
;		    can use to read or write the latches.
;
;   ENTRY:	    none
;
;   EXIT:	    ESI = place to save latches
;
;   USES:	    ESI, Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Access_Latch_Page

IFDEF Ext_VGA
%OUT do something with bank select here
IFDEF TLVGA
	push	eax
	push	edx
	TestMem [VT_Flags], fVT_TLVGA		;test if ET3000
	jz	short alp_not_et3000
	movzx	eax,[Vid_Latch_Bank]
	;convert bank in AL to ET3000 segsel reg value (for both read & write):
	mov	ah,al
	shl	ah,3
	and	ax,03807h
	or	al,ah
	or	al,040h
	jmp	short alp_tli_2
alp_not_et3000:
	TestMem [VT_Flags], fVT_TL_ET4000	;test if ET4000
	jz	short alp_not_et4000
	movzx	eax,[Vid_Latch_Bank]
	;convert bank in AL to ET4000 segsel reg value (for both read & write):
	mov	ah,al
	shl	ah,4
	and	ax,0F00Fh
	or	al,ah
alp_tli_2:
	;AL=value for segsel reg
	mov	dx,03CDh
	out	dx,al			;select segment
alp_not_et4000:
	pop	edx
	pop	eax
ENDIF	;TLVGA
ENDIF	;Ext_VGA

IFDEF SysVMin2ndBank
	TestMem [VT_Flags], fVT_SysVMnot1stBank
	jz	short alp_no_bank
IFDEF TLVGA
	TestMem [VT_Flags],fVT_TL_ET4000
	jz	short @F
	push	eax
	push	edx
	movzx	eax, [Vid_Latch_Bank]
	and	al, 0Fh
	mov	ah, al
	shl	ah, 4
	or	al, ah
	mov	dx, 03CDh
	out	dx, al
	queue_out 'alp segment = #al'
	pop	edx
	pop	eax
@@:
ENDIF
ENDIF
alp_no_bank:
	mov	esi, [Vid_Latch_Addr]
	ret

EndProc VDD_PH_Mem_Access_Latch_Page


;******************************************************************************
;
;   VDD_PH_Mem_End_Access_Latch_Page
;
;   DESCRIPTION:    Called from VDDSTATE after save/restore latches to allow
;		    banking to be removed if needed.
;
;   ENTRY:	    none
;
;   EXIT:	    none
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_End_Access_Latch_Page

IFDEF SysVMin2ndBank
	TestMem [VT_Flags], fVT_SysVMnot1stBank
	jz	short ealp_exit
IFDEF TLVGA
	TestMem [VT_Flags], fVT_TL_ET4000
	jz	short ealp_not_tl4000
	push	eax
	push	edx
	xor	al, al			; assume bank 0
	mov	edx, [Vid_MemC_VM]
	or	edx, edx
	jz	short @F
	add	edx, [Vid_CB_Off]
	mov	al, [edx.VDD_Stt.V_Extend.TLI_SegSel]
@@:
	mov	dx, 03CDh
	out	dx, al
;;	  queue_out 'ealp segment = #al'
	pop	edx
	pop	eax
ealp_not_tl4000:
ENDIF
ENDIF
ealp_exit:
	ret

EndProc VDD_PH_Mem_End_Access_Latch_Page


;******************************************************************************
;
;   VDD_PH_Mem_Shared_Page
;
;   DESCRIPTION:    Determine if 2 linear pages share a physical page.
;
;   ENTRY:	    EAX = 1st linear page id
;		    ECX = 2nd linear page id
;		    EBX = VM Handle
;		    EDI -> VM's VDD_CB_Struc
;
;   EXIT:	    Z-flag set, if both linear pages share a physical page
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Shared_Page

	Assert_VDD_ptrs ebx,edi,Pseudo_OK
	push	eax
	push	ecx

	test	[edi.VDD_Stt.C_Mode], 1 	;Q: CGA compatibility?
	jz	short VPMSP_NotShared		;   N:
	push	eax
	mov	al, [edi.VDD_Stt.G_Misc]
	and	al, fGrp6Char OR fGrp6Chain
	cmp	al, fGrp6Char OR fGrp6Chain	;Q: chained graphics mode?
	pop	eax
	jne	short VPMSP_NotShared		;   N:
IFDEF	PVGA
; PVGA mode 5Ah - 1024x768x2 comes to here too. Distinguish it!!! - C. Chiang -
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short sp_not_pvga
	test	[edi.VDD_Stt.C_HDisp], 10h	;Q: PVGA mode 5Ah
	jne	short VPMSP_NotShared		;   N:
sp_not_pvga:
ENDIF	;PVGA
	and	eax, 0Fh			;   Y: 2nd 64K maps over 1st
	and	ecx, 0Fh
	jmp	short sp_exit
VPMSP_NotShared:
	test	[edi.VDD_Stt.S_MMode], fSeq4Chain4
	jz	short sp_exit

IFDEF IBMXGA
	TestMem [edi.VDD_TFlags], fVT_XGAbit ;Q: XGA?
	jnz	short sp_doubleword_linear	;   Y:
ENDIF

IFDEF V7VGA
	TestMem [edi.VDD_TFlags], fVT_V7VGA
	jz	short sp_not_v7vga
	test	[edi.VDD_Stt.S_V7_ExtComp], fSeqFCseqChain4
	jz	short sp_exit
IFDEF Ext_VGA
	test	[edi.VDD_Stt.S_V7_ExtComp], fSeqFCext256e
	jz	short sp_doubleword_linear
%OUT different linear to physical page mapping is in effect
	jmp	short sp_exit
ELSE
	jmp	short sp_doubleword_linear
ENDIF
sp_not_v7vga:
ENDIF

IFDEF TLVGA
	TestMem [edi.VDD_TFlags], <fVT_TLVGA OR fVT_TL_ET4000>
	jnz	short sp_doubleword_linear
	Assumes_Fall_Through sp_exit
ENDIF

sp_exit:
	cmp	eax, ecx
	pop	ecx
	pop	eax
	ret

sp_doubleword_linear:
	shr	eax, 2
	shr	ecx, 2
	jmp	sp_exit

EndProc VDD_PH_Mem_Shared_Page


;******************************************************************************
;
;   VDD_PH_Mem_Get_PPD_Ptr
;
;   DESCRIPTION:    Find the physical page pointer that would physically
;		    map a virtual page id, if it were a physical page id.
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VM's VDD_CB_Struc
;		    EAX = Page ID
;
;   EXIT:	    ESI = PPD Ptr
;
;   USES:	    ESI, Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Get_PPD_Ptr

	Assert_VDD_ptrs ebx,edi,Pseudo_OK
	mov	esi, eax
	test	[edi.VDD_Stt.C_Mode], 1 	;Q: CGA compatibility?
	jz	short VPMGPP_NotChained 	;   Y:
	push	eax
	mov	al, [edi.VDD_Stt.G_Misc]
	and	al, fGrp6Char OR fGrp6Chain
	cmp	al, fGrp6Char OR fGrp6Chain	;Q: chained graphics mode?
	pop	eax
	jne	short VPMGPP_NotChained 	;   N:
IFDEF	PVGA
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short @F
; PVGA mode 5Ah - 1024x768x2 comes to here too. Distinguish it!!! - C. Chiang -
	test	[edi.VDD_Stt.C_HDisp], 10h	;Q: PVGA mode 5Ah
	jne	short VPMGPP_NotChained
@@:
ENDIF	;PVGA
	and	esi, 0Fh			;   Y: 2nd 64K maps over 1st
	jmp	short getppd_exit
VPMGPP_NotChained:

IFDEF TLVGA
	TestMem [edi.VDD_TFlags], fVT_TLVGA
	jz	short getppd_2
	;if ET3000, test ATC 10 bit 6 also for 256 color mode
	test	[edi.VDD_Stt.A_Mode],040h
	jnz	short getppd_doubleword_linear
getppd_2:
ENDIF

	test	[edi.VDD_Stt.S_MMode], fSeq4Chain4
	jz	short getppd_exit

IFDEF IBMXGA
	TestMem [edi.VDD_TFlags], fVT_XGAbit ;Q: XGA?
	jz	short @F		    ;	N:
	shr	esi, 2
	lea	esi, [esi*4][esi]	    ; phys pg = (pg DIV 4) * 5
	jmp	short getppd_exit
@@:
ENDIF

IFDEF V7VGA
	TestMem [edi.VDD_TFlags], fVT_V7VGA
	jz	short getppd_not_v7vga
	test	[edi.VDD_Stt.S_V7_ExtComp], fSeqFCseqChain4
	jz	short getppd_exit
IFDEF Ext_VGA
	test	[edi.VDD_Stt.S_V7_ExtComp], fSeqFCext256e
	jz	short getppd_doubleword_linear
%OUT different linear to physical page mapping is in effect
	jmp	short getppd_exit
ELSE
	jmp	short getppd_doubleword_linear
ENDIF
getppd_not_v7vga:
ENDIF

IFDEF TLVGA
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jnz	short getppd_doubleword_linear
	Assumes_Fall_Through getppd_exit
ENDIF

getppd_exit:
	PPD_Index_to_Ptr esi
	ret

getppd_doubleword_linear:
	shr	esi, 2
	jmp	getppd_exit

EndProc VDD_PH_Mem_Get_PPD_Ptr


;******************************************************************************
;
;   VDD_PH_Mem_VM_Using_All
;
;   DESCRIPTION:    Search thru video page table and check to see if the
;		    VM owns all physical pages and that all of them are
;		    visible (no LRU timestamp).  If this is all true, then
;		    return with Carry set to indicate that the VM needs
;		    and is using all of physical video memory.
;
;   ENTRY:	    EBX = VM Handle
;
;   EXIT:	    Carry set, if VM is using all physical video memory
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_VM_Using_All

	cmp	ebx, [Vid_Focus_VM]
	clc
IFDEF DEBUG
	je	short vua_D00
	Trace_Out 'VDD_PH_Mem_VM_Using_All not called with focus VM'
vua_D00:
ENDIF
	jne	short vua_not_focus
	push	eax
	push	ecx
	push	esi

IFDEF IBMXGA
IF 0
	TestMem [edi.VDD_TFlags], fVT_XGAbit ;Q: XGA?
	jnz	short vua_using_all		;   Y:
ENDIF
ENDIF

	mov	esi, [Video_Page_Table]
	mov	ecx, [Video_Pages]
IFDEF EXT_VGA
IFDEF TLVGA
	;if ET3000, max usable video pages if not hires mode=16 (256k bytes)
	call	Get_Usable_Video_Pages	;->ECX
ENDIF
ENDIF
vua_loop:
	mov	eax, [esi.PPD_owner_PH]
	or	eax, eax		    ;Q: phys page owned?
	jz	short vua_exit		    ;	N: free page found, so return no
	cmp	ebx, [eax.PDS_owner]	    ;Q: owned by focus VM?
	clc
	jne	short vua_exit		    ;	N: return no, VM doesn't use all
	cmp	[esi.PPD_LRU_time], 0	    ;Q: page have an LRU timestamp?
	clc
	jne	short vua_exit		    ;	Y: return no, page not visible
	add	esi, SIZE Phys_Page_Data
	loop	vua_loop
vua_using_all:
	stc

vua_exit:
	pop	esi
	pop	ecx
	pop	eax
vua_not_focus:
	ret

EndProc VDD_PH_Mem_VM_Using_All


;******************************************************************************
;
;   VDD_PH_Mem_CalcPagePhys
;
;   DESCRIPTION:    Find the physical page # and bank # for a given page handle
;
;   ENTRY:	    EAX = page handle
;		    EBX = VM Handle or 0, if in planar mode
;		    EDI -> VM's VDD_CB_Struc
;
;   EXIT:	    AL = phys page #
;		    AH = phys page # base (i.e. A0, B0 or B8)
;		    ECX = bank #
;
;   USES:	    EAX, ECX, Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_CalcPagePhys

IFDEF DEBUG
	or	ebx, ebx
	jz	short cpp_planar
	Assert_VDD_ptrs ebx,edi,Pseudo_OK
cpp_planar:
ENDIF
	push	edx

	mov	ecx, eax
	movzx	eax, [ecx.PDS_physpage]

	or	ebx, ebx			;Q: valid VM handle?
	jz	short cpp_exit			;   N: assume planar mode

	test	[edi.VDD_Stt.C_Mode], 1 	;Q: CGA compatibility?
	jz	short cpp_NotChainedGrp 	;   N:
	mov	dl, [edi.VDD_Stt.G_Misc]
	and	dl, fGrp6Char OR fGrp6Chain
	cmp	dl, fGrp6Char OR fGrp6Chain	;Q: chained graphics mode?
	jne	short cpp_NotChainedGrp 	;   N:

IFDEF	PVGA
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short @F
; PVGA mode 5Ah - 1024x768x2 comes to here too. Distinguish it!!! - C. Chiang -
	test	[edi.VDD_Stt.C_HDisp], 10h	;Q: CGA compatibility enabled?
	jne	short cpp_NotChainedGrp
@@:
ENDIF	;PVGA

;
; SoftKicker is a GEM utility that allows GEM to work on a large virtual
; display, where the user can pan and scroll the virtual display in the
; window of the physical screen.  To provide this capability, it programs
; the display in a chained graphics mode with 128Kb of video memory mapped
; at A0.  In chained graphics mode, even addresses map bytes in planes 0 & 1,
; and odd addresses map bytes in planes 2 & 3.	Addresses below B0 map
; even bytes and addresses above map odd bytes.  So page ids 0 and 16 both
; map the same physical page, and when we detect chained graphics mode we
; subtract 16 from page ids greater than 15 to deal with this double mapping.
;
; example of chained graphics mapping:
;
;   CPU addresses:    A0000 A0001 A0002 A0003 B0000 B0001 B0002 B0003
;
;
;   video addresses:	-------------------------     -------------------------
;			|Plane 1		|     |Plane 3		      |
;			|			|     | 		      |
;		     -------------------------	|  -------------------------  |
;		     |Plane 0		     |	|  |Plane 2		   |  |
;		     |			     |---  |			   |---
;		     |A0000|B0000|A0002|B0002|	   |A0001|B0001|A0003|B0003|
;		     |			     |	   |			   |
;		     -------------------------	   -------------------------
;
;
	movzx	edx, [ecx.PDS_virtual_id]
	and	edx, 10h
	or	eax, edx
	jmp	short cpp_exit
cpp_NotChainedGrp:

IFDEF TLVGA
	TestMem [edi.VDD_TFlags], fVT_TLVGA
	jz	short cpp_2
	;if ET3000, test ATC 10 bit 6 also for 256 color mode
	test	[edi.VDD_Stt.A_Mode],040h
	jnz	short cpp_sequential_chain4
cpp_2:
ENDIF

	test	[edi.VDD_Stt.S_MMode], fSeq4Chain4  ;Q: 256 color (mode 13)?
	jz	short cpp_exit			    ;	N:

IFDEF Ext_VGA
IFDEF V7VGA
	TestMem [edi.VDD_TFlags], fVT_V7VGA
	jz	short cpp_not_v7vga
	test	[edi.VDD_Stt.S_V7_ExtComp], fSeqFCseqChain4
	jnz	short cpp_sequential_chain4
cpp_not_v7vga:
ENDIF
ENDIF

IFDEF IBMXGA
	TestMem [edi.VDD_TFlags], fVT_XGAbit	;Q: XGA?
	jz	short @F			;   N:
	and	eax, 11b			;   Y: mask phys page & use
	jmp	short cpp_sequential_chain4	;	same formula as TLVGA
@@:
ENDIF

IFDEF TLVGA
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jnz	short cpp_sequential_chain4
;
; Tseng Labs maps their mode 13 differently.  They use the bottom 2 bits for a
; plane select like IBM, but they shift the address right 2 when they peel the
; bottom 2 bits off.  The result is that 4 linear pages are mapped to the same
; physical page and all of the physical pages memory is used.  In IBM's mapping
; the address isn't shifted, so only every fourth byte of physical memory is
; used and only 1 virtual page is mapped to a physical page.  This means that
; in mode 13 requires 16 physical pages with IBM's mapping (leaving no free
; pages to demand page), where Tseng Labs mapping only uses 4 pages (leaving
; 12 free pages for demand usage!)
;
; Video-7's higher resolution 256 color modes use this same mapping, but use
; the extra sequential chain4 bit in register Seq.FC to control it.
;
ENDIF
	jmp	short cpp_exit

cpp_sequential_chain4:
cpp_4:
	movzx	edx, [ecx.PDS_virtual_id]
	and	edx, 11b
	shl	eax, 2
	add	eax, edx
IFDEF DEBUG_verbose
	movzx	edx, [ecx.PDS_virtual_id]
	Trace_Out '#dx->#ax'
ENDIF

cpp_exit:

IFDEF Ext_VGA
	call	VDD_PH_Mem_Remove_Banking
ELSE
	xor	ecx, ecx    ; for now!!!!!!!!!!
ENDIF
	mov	edx, eax
	call	VDD_State_Get_Mem_Mapping
	movzx	eax, al
	mov	ah,al			    ; Save phys base in AH
	add	al,dl			    ; AL = phys page #
	pop	edx
	ret

EndProc VDD_PH_Mem_CalcPagePhys


;******************************************************************************
;
;   VDD_PH_Mem_Mapped_Phys
;
;   DESCRIPTION:    Determine if a virtual page id is currently mapped to
;		    the correct physical page.	(linear=physical)
;
;   ENTRY:	    EAX = page id
;		    ECX = page handle
;		    EBX = VM Handle
;		    EDI -> VM's VDD_CB_Struc
;
;   EXIT:	    Z-flag set, if correctly mapped
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Mapped_Phys

	Assert_VDD_ptrs ebx,edi,Pseudo_OK
	push	ecx
	push	esi
	call	VDD_PH_Mem_Get_PPD_Ptr
	movzx	ecx, [ecx.PDS_physpage]
	PPD_Index_to_Ptr ecx
	cmp	ecx, esi
	pop	esi
	pop	ecx
	ret

EndProc VDD_PH_Mem_Mapped_Phys


;******************************************************************************
;
;   VDD_PH_Mem_Get_Visible_Pages
;
;   DESCRIPTION:    Return the # of pages that are "visible" in terms of the
;		    CRT controller.
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VM's VDD_CB_Struc
;
;   EXIT:	    EAX = 1st visible page number
;		    ECX = # of visible pages
;		    Carry set, if graphics mode
;
;   USES:	    EAX, ECX, Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Get_Visible_Pages

	VMMCall Test_Sys_VM_Handle
	jne	short @F
	mov	ecx, [Vid_Sys_Visible_Pages]
	inc	ecx
	jecxz	short @F		    ; calculate, if -1
	dec	ecx
	movzx	eax, [Vid_Sys_First_Visible]
	stc
	ret
@@:
	push	edx
	call	VDD_State_Get_Dimensions    ; EAX = rows, ECX = columns
	jnc	short gvp_text
IFDEF DEBUG_verbose
	push	eax
	push	ecx
	VMMCall Debug_Convert_Hex_Decimal
	xchg	eax, ecx
	VMMCall Debug_Convert_Hex_Decimal
	Trace_Out 'Graphics #AXX#CX'
	pop	ecx
	pop	eax
ENDIF
	imul	ecx, eax		    ; ecx = total # of pixels

IFDEF TLVGA
	TestMem [edi.VDD_TFlags], fVT_TLVGA
	jz	short gvp_2
	;if ET3000, test ATC 10 bit 6 also for 256 color mode
	test	[edi.VDD_Stt.A_Mode],040h
	jnz	short gvp_exit
gvp_2:
ENDIF
	test	[edi.VDD_Stt.S_MMode], fSeq4Chain4  ;Q: packed pixel mode?
; Western Digital incompatible S_MMode (3C4.04) for mode 5Bh  - C. Chiang -
IFDEF	PVGA
	jz	short @F
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short gvp_exit			    ;	Y: bytes = pixels
	; PVGA mode 5Bh - 1024x768x4 comes to here too. Distinguish it!!!
	test	[edi.VDD_Stt.G_Mode], 01000000b	    ;Q: real packed pixel mode?
	jnz	short gvp_exit			    ;	Y: bytes = pixels
@@:
ELSE
	jnz	short gvp_exit			    ;	Y: bytes = pixels
ENDIF
	shr	ecx, 2				    ; assume 4 pixels per byte
	test	[edi.VDD_Stt.G_Mode], fGrp5CGA	    ;Q: 4 color CGA graphics mode?
IFDEF	PVGA
	jz	short @F
; Western Digital mode 5Bh is different than mode 4 & 5   - C. Chiang -
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short gvp_exit
	test	[edi.VDD_Stt.S_MMode], fSeq4Chain4  ;Q: PVGA mode 5Bh special bit
	jz	short gvp_exit			    ; N: bytes = pixels / 4
						    ;    - mode 4, 5
						    ; Y: mode 5Bh
@@:
ELSE
	jnz	short gvp_exit			    ;	Y: bytes = pixels / 4
ENDIF
	shr	ecx, 1				    ;	N: bytes = pixels / 8
	clc
	jmp	short gvp_exit

gvp_text:
IFDEF DEBUG_verbose
	push	eax
	push	ecx
	VMMCall Debug_Convert_Hex_Decimal
	xchg	eax, ecx
	VMMCall Debug_Convert_Hex_Decimal
	Trace_Out 'Text #AXX#CX'
	pop	ecx
	pop	eax
ENDIF
	imul	eax, ecx		    ; eax = # of char
	shl	eax, 1			    ; 2 bytes per char
	mov	ecx, eax
	stc

gvp_exit:
	cmc
	pushfd
	call	VDD_State_Get_Screen_Start  ; EAX = screen start offset
IFDEF DEBUG
	cmp	[VDD_DPD], 0
	je	short gvp_D00
	xor	eax, eax
gvp_D00:
ENDIF
	push	eax
	and	eax, P_SIZE - 1 	    ; Mask to page offset
	add	ecx, eax		    ; Add to total length
	add	ecx, P_SIZE - 1
	shr	ecx, 12 		    ; ecx = # of pages
IFDEF	PVGA
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short gvp_OK
;; Force max. page # save = 10h at this version
;; If packed mode, save 10h page with all 4 planes give 
;; you up to 256-K memory save/restore		- C. Chiang -
	cmp	ecx, 10h
	jbe	short gvp_OK
	cmp	byte ptr [edi.VDD_Stt.C_LnOff], 28h    ;Q: > mode 13h?
	jg	short @F				; Y: use max pages
	cmp	byte ptr [edi.VDD_Stt.C_HDisp], 7Fh    ;Q: modes 5Ah or 5Bh
	jnz	short gvp_OK				; N: use calc'd pages
@@:
	mov	ecx, 10h				; Use max pages
gvp_OK:
ENDIF	;PVGA

	pop	eax
	shr	eax, 12 		    ; eax = start page
gvp_ret:

IF 0
; don't limit this anymore, because we can attempt to demand page with a single
; page, or detect when we can't and force the VM full screen.
IFNDEF Ext_VGA
	inc	ecx
	cmp	ecx, [Video_Pages]	    ;Q: all but 1 page visible?
	je	short @F		    ;	Y: can't demand page with 1 page
					    ;	    so return 1 greater than actual
	dec	ecx			    ;	N: use calculated size
@@:
ENDIF
ENDIF

	cmp	[edi.VDD_saved_visible], 0  ;Q: saved size?
	je	short @F		    ;	N:
	cmp	edi, OFFSET32 Vid_Msg_Pseudo_CB
	je	short @F
	add	ecx, eax
	xor	eax, eax
	cmp	ecx, [edi.VDD_saved_visible] ;Q: saved size larger?
	jae	short @F		    ;	N:
	mov	ecx, [edi.VDD_saved_visible];	Y: return saved size
@@:
	popfd
	pop	edx
IFNDEF Ext_VGA
IFDEF DEBUG
	pushfd
	push	eax
	add	eax, ecx
	cmp	eax, 16
	jbe	short @F
	Debug_Out 'VDD: visible pages (#ax) > 16'
@@:
	pop	eax
	popfd
ENDIF
ENDIF

IFDEF DEBUG_verbose
	xchg	edx, [esp]
	Trace_Out 'Visible #ax, #cx (from ?edx)'
	xchg	edx, [esp]
ENDIF
	ret

EndProc VDD_PH_Mem_Get_Visible_Pages


;******************************************************************************
;
;   VDD_PH_Mem_Page_Visible
;
;   DESCRIPTION:    Return with the Zero flag set, if the page is visible,
;		    else return with the zero flag clear.
;
;   ENTRY:	    EAX = page id
;		    EBX = VM Handle
;		    EDI -> VM's VDD_CB_Struc
;
;
;   EXIT:	    Zero flag set, if page is visible
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Page_Visible

	push	ecx
	push	edx
	mov	edx, eax
	call	VDD_PH_Mem_Get_Visible_Pages
	xchg	eax, edx		    ; eax = requested, edx = 1st visible
	cmp	eax, edx		    ;Q: page before 1st visible?
	jb	short pv_no		    ;	Y: return not visible
	add	edx, ecx
	cmp	eax, edx		    ;Q: page beyond last visible?
	jae	short pv_no		    ;	Y: return not visible
	xor	dl, dl			    ; page visible, so set Z-flag
	jmp	short pv_exit

pv_no:	or	dl, 1			    ; page not visible, clear Z-flag

pv_exit:
	pop	edx
	pop	ecx
	ret

EndProc VDD_PH_Mem_Page_Visible


;******************************************************************************
;
;   VDD_PH_Mem_CalcPageId
;
;   DESCRIPTION:    Convert a video page #, like from a page fault, to a
;		    linear page id.
;
;   ENTRY:	    EAX = video page #	(A0 - BFh)
;		    EBX = VM Handle
;		    EDI -> VM's VDD_CB_Struc
;
;   EXIT:	    IF Carry clear THEN
;			EAX = PH Mem's abstract page id
;
;   USES:	    EAX, Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_CalcPageId

	Assert_VDD_ptrs ebx,edi,Pseudo_OK
	push	ecx
	mov	ecx, eax
	call	VDD_State_Get_Mem_Mapping
	push	eax
	movzx	eax, al
	sub	ecx, eax
	pop	eax
	jb	short cpi_exit
	cmp	cl, ah		    ;Q: result >= max page
	cmc			    ; clear carry, iff page < max
	jc	short cpi_exit	    ; jump if page >= max

	xchg	eax, ecx
IFDEF Ext_VGA
	call	VDD_PH_Mem_Add_Banking
ENDIF
	clc

cpi_exit:
	pop	ecx
	ret

EndProc VDD_PH_Mem_CalcPageId


;******************************************************************************
;
;   VDD_PH_Mem_CalcPageAddr
;
;   DESCRIPTION:    Opposite of VDD_PH_Mem_CalcPageId.	Find the video page
;		    # that corresponds to a linear page id.  This routine
;		    just discards any banking information.
;
;   ENTRY:	    EAX = page id
;		    EBX = VM Handle
;		    EDI -> VM's VDD_CB_Struc
;
;   EXIT:	    EAX = video page #
;
;   USES:	    EAX, Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_CalcPageAddr

	Assert_VDD_ptrs ebx,edi,Pseudo_OK

IFDEF Ext_VGA
	push	ecx
	call	VDD_PH_Mem_Remove_Banking
	pop	ecx
ENDIF
	push	edx
	mov	edx, eax
	call	VDD_State_Get_Mem_Mapping
	movzx	eax, al
	add	eax, edx
	pop	edx
	ret

EndProc VDD_PH_Mem_CalcPageAddr


IFDEF Ext_VGA
;******************************************************************************
;
;   VDD_PH_Mem_Assign_Video_Page
;
;   DESCRIPTION:    Similar to VDD_PH_Mem_Alloc_Video_Page, but it assumes
;		    that the VM already owns the physical memory and just
;		    allocates the necessary page handle structure.  This is
;		    neeeded in superVGA systems where multiple banks of video
;		    memory exist.  In the interest of maintaining performance
;		    we don't trap I/O ports, so we don't see when banking is
;		    changed, thus we will probably alloc pages in one bank
;		    due to page faults, but will never alloc additional
;		    logical pages in different banks.
;
;		    VDD_VM_Mem_MemC_about_to_change calls this routine to
;		    insure that we have a page handle allocated for all
;		    visible pages.
;
;   ENTRY:	    EAX = requested page id
;		    EBX = VM Handle
;		    EDI = VDD CB ptr
;		    ESI = notification callback address
;
;   EXIT:	    EAX = page handle of allocated page
;
;   USES:	    EAX, Flags
;
;   CALL BACK:	    (same as VDD_PH_Mem_Alloc_Video_Page below)
;
;==============================================================================
BeginProc VDD_PH_Mem_Assign_Video_Page

	pushad

	mov	ecx, eax
	push	ebx
	call	VDD_PH_Mem_Get_Page_Owner
	pop	ebx
	xchg	eax, ecx
	jc	short asvp_no_owner
	cmp	ax, [ecx.PDS_virtual_id]    ;Q: correct page?
	je	short asvp_exit 	    ;	Y: return page handle
	movzx	esi, [ecx.PDS_physpage]
	PPD_Index_to_Ptr esi		    ; esi -> PPD
	jmp	alloc_page		    ; jump into VDD_PH_Mem_Alloc_Video_Page

asvp_no_owner:
	call	VDD_PH_Mem_Get_PPD_Ptr	    ; esi -> PPD
	jmp	alloc_page		    ; jump into VDD_PH_Mem_Alloc_Video_Page

asvp_exit:
	mov	[esp.Pushad_EAX], eax
	popad
	ret

EndProc VDD_PH_Mem_Assign_Video_Page
ENDIF ;Ext_VGA


;******************************************************************************
;
;   VDD_PH_Mem_Alloc_Video_Page
;
;   DESCRIPTION:    Allocate a video page for use by a VM
;
;   ENTRY:	    EAX = requested page id
;		    EBX = VM Handle
;		    EDI = VDD CB ptr
;		    ESI = notification callback address
;
;   EXIT:	    IF Carry clear THEN
;			EAX = page handle of allocated page
;		    ELSE
;			no page available
;			EAX = 0
;
;   USES:	    EAX, Flags
;
;   CALL BACK:	    ENTRY:
;			EAX = page handle (-> Page_Data_Struc)
;			EBX = owner VM handle
;			EDI = VDD CB ptr
;			ECX = notification id
;				fPHM_notify_page_free	    (0)
;				    page is about to be freed
;				fPHM_notify_page_unmap	    (1)
;				    page is no longer accessible with the
;				    current memory access state
;				fPHM_notify_page_changed    (2)
;				    physical page assignment is changing
;					(EDX = new page handle)
;			Proc can modify EAX, EBX, ECX, EDX, ESI, EDI, and flags
;
;		    EXIT
;			IF ECX entered with fPHM_notify_page_free, THEN
;			    return Carry SET, if page can not be freed
;
;==============================================================================
BeginProc VDD_PH_Mem_Alloc_Video_Page

Assert_VDD_ptrs ebx,edi,Pseudo_OK

	pushad

	call	VDD_PH_Mem_Get_PPD_Ptr
	mov	edx, [esi.PPD_owner_PH]
	or	edx, edx		;Q: phys page owned?
	jz	alloc_page		;   N: go ahead and take it
	cmp	ebx, [edx.PDS_owner]	;Q: page owned by same VM?
	jne	short avp_not_chained	;   N: can't be multiply mapped
	movzx	eax, [edx.PDS_virtual_id]
	mov	edx, esi
	call	VDD_PH_Mem_Get_PPD_Ptr
	mov	eax, [esp.Pushad_EAX]
	cmp	esi, edx		;Q: current owner maps same phys page?
	je	alloc_page		;   Y: alloc new PH which maps same
					;      phys page
	mov	esi, edx		; esi = correct PPD ptr

avp_not_chained:
	cmp	ebx, [Vid_CRTC_VM]	;Q: alloc for focus VM?
	je	alloc_specific		;   Y: try to give requested page

find_page:
	mov	esi, [Video_Page_Table]
	VMMCall Get_Last_Updated_System_Time
	mov	ecx, [Video_Pages]
IFDEF EXT_VGA
IFDEF TLVGA
	;if ET3000, max usable video pages if not hires mode=16 (256k bytes)
	call	Get_Usable_Video_Pages	;->ECX
ENDIF
ELSE
IFDEF TLVGA
	TestMem [edi.VDD_TFlags], <fVT_TLVGA OR fVT_TL_ET4000>
	jz	short @F
	test	[edi.VDD_Stt.S_MMode], fSeq4Chain4  ;Q: 256 color?
	jz	short @F			    ;	N:
	mov	ecx, 4				    ;	Y: can't map pages above A3
@@:
ENDIF
ENDIF
	xor	ebx, ebx
	xor	edi, edi
scan_table:
	cmp	[esi.PPD_owner_ph], 0	;Q: phys page owned?
	jz	short alloc_page_free	;   N: take it
	cmp	[esi.PPD_LRU_time], 0	;Q: visible focus page?
	je	short avp_more_recent	;   Y: skip LRU check
	mov	ebp, eax
	sub	ebp, [esi.PPD_LRU_time]
	cmp	ebp, ebx		;Q: available for a longer time?
	jb	short avp_more_recent	;   N:
	mov	ebx, ebp		;   Y: record time
	mov	edi, esi		;	& page handle
avp_more_recent:
	add	esi, SIZE Phys_Page_Data
	loop	scan_table

	mov	esi, edi
	mov	edi, [esp.Pushad_EDI]
	mov	ebx, [esp.Pushad_EBX]

	or	esi, esi		;Q: LRU candidate found?
	jz	short no_page_free	;   N:
	mov	eax, [esi.PPD_owner_PH] ;   Y: free the page
	call	VDD_PH_Mem_Free_Page
	mov	eax, [esp.Pushad_EAX]

IFDEF DEBUG_verbose
	jc	short free_failed
	Trace_Out 'stole page handle #esi for page #ax for VM #ebx'
ENDIF
	jnc	DEBFAR alloc_page	;      & take it

free_failed:
	Trace_Out 'LRU candidate failed to be freed (#esi)'
	mov	eax, [esi.PPD_owner_PH]
	call	VDD_PH_Mem_update_LRU
	jmp	find_page

alloc_page_free:
	mov	edi, [esp.Pushad_EDI]
	mov	ebx, [esp.Pushad_EBX]
	mov	eax, [esp.Pushad_EAX]
	jmp	SHORT alloc_page

IFDEF DEBUG
illegal_page:
	Debug_Out 'VDD_PH_Mem_Alloc_Video_Page called with invalid page # (#eax)'
ENDIF

no_page_free:
	xor	eax, eax
	stc
	jmp	DEBFAR alloc_exit

alloc_specific:
IFDEF DEBUG
	push	eax

	test	[edi.VDD_Stt.C_Mode], 1 	;Q: CGA compatibility?
	jz	short alloc_no_wrap		;   N:
	push	edx
	mov	dl, [edi.VDD_Stt.G_Misc]
	and	dl, fGrp6Char OR fGrp6Chain
	cmp	dl, fGrp6Char OR fGrp6Chain	;Q: chained graphics mode?
	pop	edx
	jne	short alloc_no_wrap		;   N:

IFDEF	PVGA
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short alloc_wrap
; PVGA mode 5Ah - 1024x768x2 comes to here too. Distinguish it!!! - C. Chiang -
	test	[edi.VDD_Stt.C_HDisp], 10h	;Q: PVGA mode 5Ah
	jnz	short alloc_no_wrap
ENDIF	;PVGA
alloc_wrap:
	and	eax, 0Fh			;   Y: 2nd 64K maps over 1st
alloc_no_wrap:

IFDEF TLVGA
	TestMem [edi.VDD_TFlags], fVT_TLVGA
	jz	short alloc_D_2
	;if ET3000, test ATC 10 bit 6 also for 256 color mode
	test	[edi.VDD_Stt.A_Mode],040h
	jnz	short alloc_D_4
alloc_D_2:
ENDIF

	test	[edi.VDD_Stt.S_MMode], fSeq4Chain4
	jz	short alloc_D00

alloc_D_4:
	shr	eax, 2
alloc_D00:

IFDEF EXT_VGA
IFDEF TLVGA
	;if ET3000, max usable video pages if not hires mode=16 (256k bytes)
	mov	ecx,[Video_Pages]
	call	Get_Usable_Video_Pages	;->ECX
	cmp	eax,ecx
ELSE
	cmp	eax, [Video_Pages]
ENDIF	;TLVGA
ELSE
	cmp	eax, [Video_Pages]
ENDIF	;EXT_VGA
	pop	eax
	jae	illegal_page
ENDIF
	mov	ecx, eax		    ; ecx = requested page id
	mov	eax, [esi.PPD_owner_PH]

%OUT optimization: move allocated pages if possible

	call	VDD_PH_Mem_Free_Page	    ; free the page
	jc	no_page_free
	mov	eax, ecx

alloc_page:				    ; esi = PPD pointer
					    ; eax = page id
					    ; ebx = VM handle
	mov	edx, eax
	mov	ecx, esi
	mov	esi, [VDD_PageHandle_List]
	VMMCall List_Allocate
	jc	no_page_free
	mov	[eax.PDS_virtual_id], dx
	mov	[eax.PDS_linear_page], 0
	mov	[eax.PDS_owner], ebx
	mov	[eax.PDS_flags], 0

	cmp	[ecx.PPD_owner_ph], 0
	je	short alloc_no_prev

	push	ecx
	mov	ecx, [ecx.PPD_owner_ph]
	VMMCall List_Insert
	pop	ecx
	jmp	short alloc_00

alloc_no_prev:
	mov	[ecx.PPD_owner_ph], eax
	VMMCall List_Attach
alloc_00:
	PPD_Ptr_to_Index ecx
	mov	[eax.PDS_physpage], cx
	mov	esi, eax
	call	VDD_PH_Mem_update_LRU
	mov	ecx, [esp.Pushad_ESI]
	mov	[eax.PDS_callback], ecx
	clc
	Queue_Out 'VDD alloc pgh #eax for #ebx'

Assert_VDD_ptrs ebx,edi,Pseudo_OK
	inc	[edi.VDD_Owned_Pages]

alloc_exit:
	mov	[esp.Pushad_EAX], eax
	popad
	ret

EndProc VDD_PH_Mem_Alloc_Video_Page


;******************************************************************************
;
;   VDD_PH_Mem_LRU_Sweep
;
;   DESCRIPTION:    Search thru all physical video pages and make sure that
;		    all pages that don't belong to the focus VM have an LRU
;		    timestamp so that they are eligible for reuse.
;
;   ENTRY:	    none
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_PH_Mem_LRU_Sweep

	pushad
	mov	ebx, [Vid_Focus_VM]
	SetVDDPtr edi
	mov	esi, [Video_Page_Table]
	mov	ecx, [Video_Pages]
IFDEF EXT_VGA
IFDEF TLVGA
	;if ET3000, max usable video pages if not hires mode=16 (256k bytes)
	call	Get_Usable_Video_Pages	;->ECX
ENDIF
ENDIF
ls_loop:
	mov	eax, [esi.PPD_owner_PH]
	or	eax, eax		    ;Q: phys page owned?
	jz	short ls_next		    ;	N: skip
	cmp	ebx, [eax.PDS_owner]	    ;Q: owned by focus VM?
	je	short ls_focus_page	    ;	Y: make sure it is stamped correctly
	cmp	[esi.PPD_LRU_time], 0	    ;Q: page have an LRU timestamp?
	jne	short ls_next		    ;	Y: skip
	VMMCall Get_Last_Updated_System_Time;	N: give it current time
	mov	[esi.PPD_LRU_time], eax
	jmp	short ls_next

ls_focus_page:
	cmp	[esi.PPD_LRU_time], 0	    ;Q: page have an LRU timestamp?
	je	short ls_next		    ;	N: skip
	movzx	eax, [eax.PDS_virtual_id]
	call	VDD_PH_Mem_Page_Visible     ;Q: page visible?
	jnz	short ls_next		    ;	N: ship
	mov	[esi.PPD_LRU_time], 0

ls_next:
	add	esi, SIZE Phys_Page_Data
	loop	ls_loop
	popad
	ret

EndProc VDD_PH_Mem_LRU_Sweep


;******************************************************************************
;
;   VDD_PH_Mem_update_LRU
;
;   DESCRIPTION:    Update the last used time for the page, if it is not a
;		    visible page for the focus VM.
;
;   ENTRY:	    ESI = page handle
;		    EBX = VM Handle
;		    EDI -> VM's VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_update_LRU

	push	eax
	push	ecx
	push	esi
	push	0
	mov	eax, [esi.PDS_owner]
	cmp	eax, [Vid_CrtC_VM]	    ;Q: page for CRTC owner VM?
	jne	short add_to_LRU_end	    ;	N: add it back on the end of the LRU
	movzx	eax, [esi.PDS_physpage]
	mov	ecx, eax
	PPD_Index_to_Ptr eax
	mov	esi, [eax.PPD_owner_PH]     ; get first page handle assigned to page
uLRU_chk_vis:
	movzx	eax, [esi.PDS_virtual_id]
	call	VDD_PH_Mem_Page_Visible     ;Q: focus owned page visible?
	jz	short uLRU_leave_it_out     ;	Y: leave it out of the LRU
	call	VDD_VM_Mem_Font_Page	    ;Q: focus owned page part of font?
	jc	short uLRU_leave_it_out     ;	Y: leave it out of the LRU
					    ;	N: add it onto the end
uLRU_nxt_pgh:
	mov	eax, esi
	mov	esi, [VDD_PageHandle_List]
	VMMCall List_Get_Next
	mov	esi, eax
	jz	short uLRU_not_vis	    ; jump if no more page handles
	cmp	cx, [esi.PDS_physpage]	    ;Q: new page handle maps same phys pg?
	je	uLRU_chk_vis		    ;	Y:

uLRU_not_vis:
	mov	esi, [esp+4]		    ; restore esi as original page handle
IFDEF DEBUG_verbose
	mov	ax, [esi.PDS_virtual_id]
	Trace_Out 'page #ax (#esi) is not visible, so adding to LRU'
ENDIF
add_to_LRU_end:
	VMMCall Get_Last_Updated_System_Time
	mov	[esp], eax

uLRU_leave_it_out:
	movzx	eax, [esi.PDS_physpage]
	PPD_Index_to_Ptr eax
	pop	[eax.PPD_LRU_time]
	pop	esi
	pop	ecx
	pop	eax
	ret

EndProc VDD_PH_Mem_update_LRU


;******************************************************************************
;
;   VDD_PH_Mem_Change_Page
;
;   DESCRIPTION:    Change the physical page assignment of an allocated page.
;		    The page's callback function will be called.
;
;   ENTRY:	    EAX = page handle
;		    EBX = VM Handle
;		    EDI = VDD CB ptr
;		    ECX = requested page id
;		    ESI = new callback (0, if no change)
;
;   EXIT:	    IF Carry clear THEN
;			EAX = new page handle
;		    ELSE
;			couldn't alloc new page
;			EAX = original page handle, which is still allocated
;
;   USES:
;
;==============================================================================
BeginProc VDD_PH_Mem_Change_Page

	pushad
IFDEF DEBUG
	call	VDD_PH_Mem_Debug_Validate_PH
	jc	short mcp_exit
ENDIF

	mov	edx, eax
	movzx	eax, [eax.PDS_virtual_id]
	push	esi
	call	VDD_PH_Mem_Get_PPD_Ptr
	PPD_Ptr_to_Index esi
	cmp	si, [eax.PDS_physpage]	    ;Q: page handle already mapped
	pop	esi			    ;	to correct phys page?
	je	short mcp_change_callback   ;	Y:

	or	esi, esi		    ;Q: new callback given?
	jnz	short mcp_new_callback	    ;	Y:
	mov	esi, [edx.PDS_callback]     ;	N: retrieve old callback
mcp_new_callback:
	mov	eax, ecx		    ; new page id
	call	VDD_PH_Mem_Alloc_Video_Page ; alloc the new page
IFDEF DEBUG
	jnc	short mcp_skip_D00
	Debug_Out 'failed to alloc new page for VDD_PH_Mem_Change_Page'
mcp_skip_D00:
ENDIF
	jc	short mcp_exit
					    ; eax = handle of new page
					    ; edx = handle of old page
;
; free old page
;
	mov	[esp.Pushad_EAX], eax
	mov	eax, edx		    ; eax = old
	call	VDD_PH_Mem_Free_Page	    ; this will force the memory to
	clc				    ; be copied out, if necessary

mcp_exit:
	popad
	ret

mcp_change_callback:
	or	esi, esi		    ;Q: new callback given?
	jz	mcp_exit		    ;	N: no change, so exit
	mov	[edx.PDS_callback], esi     ;	Y: change callback & exit
	clc
	jmp	mcp_exit

EndProc VDD_PH_Mem_Change_Page


;******************************************************************************
;
;   VDD_PH_Mem_Get_Page_Owner
;
;   DESCRIPTION:    Return page handle and owner VM for a specified page #,
;		    If multiple page handles own the same phys page, then
;		    the page handle with the same page id will be returned,
;		    if it exists, else the last page handle that owns the
;		    phys page will be returned.
;
;   ENTRY:	    EAX = page id
;		    EBX = VM Handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    IF Carry clear THEN
;			EAX = page handle
;			EBX = owner VM handle
;		    ELSE
;			page is not owned
;
;   USES:	    EAX, EBX, Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Get_Page_Owner

	push	ecx
	push	edx
	push	esi
	mov	ecx, eax
	call	VDD_PH_Mem_Get_PPD_Ptr
	mov	eax, [esi.PPD_owner_PH]
	or	eax, eax		;Q: physical page owned?
	jz	short gpo_no_owner	;   N:
	mov	dx, [eax.PDS_physpage]	;   Y: save phys page id
gpo_chk_id_match:
	mov	ebx, eax
	cmp	cx, [eax.PDS_virtual_id];Q: actual page match?
	je	short gpo_got_owner	;   Y: return this page handle
	mov	esi, [VDD_PageHandle_List] ;N: see if next maps same phys pg
	VMMCall List_Get_Next
	jz	short gpo_got_owner	; jump, if no more page handles
	cmp	dx, [eax.PDS_physpage]	;Q: next handle maps same phys page?
	je	short gpo_chk_id_match	;   Y: check for id match
gpo_got_owner:
	mov	eax, ebx
	mov	ebx, [eax.PDS_owner]
	stc

gpo_no_owner:
	cmc
	pop	esi
	pop	edx
	pop	ecx
	ret

EndProc VDD_PH_Mem_Get_Page_Owner


;******************************************************************************
;
;   VDD_PH_Mem_Free_Page
;
;   DESCRIPTION:    Free a video page.	The page's callback function will be
;		    called.
;
;   ENTRY:	    EAX = page handle
;
;   EXIT:	    Carry clear, if page freed
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Free_Page

	pushad
IFDEF DEBUG
	mov	ebx, [eax.PDS_owner]
	or	ebx, ebx
	jnz	short @F
	Debug_Out 'VDD_PH_Mem_Free_Page attempt to free unowned page'
@@:
IFDEF DEBUG_verbose
	Queue_Out 'VDD free pgh #eax owned by #ebx'
ENDIF
	mov	ebx, [esp.Pushad_EBX]

	call	VDD_PH_Mem_Debug_Validate_PH
	jc	free_exit
ENDIF

	movzx	ebp, [eax.PDS_physpage]
	PPD_Index_to_Ptr ebp
	mov	eax, [ebp.PPD_owner_PH]     ; make sure we have first mapped PH

	mov	ebx, [eax.PDS_owner]
	SetVDDPtr edi

fp_free_handle_lp:
	mov	[ebp.PPD_owner_PH], eax

	xor	ecx, ecx
.errnz fPHM_notify_page_free
	push	eax
	push	ebp
	call	[eax.PDS_callback]
	pop	ebp
	pop	eax
	jc	short free_exit
	dec	[edi.VDD_Owned_Pages]
IFDEF DEBUG
	jnc	short @F
	Debug_Out 'VDD: decrementing owned_pages thru 0'
@@:
ENDIF
	xor	edx, edx
	mov	[ebp.PPD_owner_PH], edx
IFDEF DEBUG
	mov	[eax.PDS_owner], edx
ENDIF
	mov	edx, eax
	mov	esi, [VDD_PageHandle_List]
	VMMCall List_Get_Next
	xchg	eax, edx
	VMMCall List_Remove
	movzx	ecx, [eax.PDS_physpage]
	VMMCall List_Deallocate 	    ; discard freed page handle
	or	edx, edx		    ;Q: another handle in list?
	jz	short fp_handles_freed	    ;	N: mark phys page as free
	mov	eax, edx
	cmp	cx, [eax.PDS_physpage]	    ;Q: next handle maps same phys page?
	je	fp_free_handle_lp	    ;	Y: attempt to free next handle

fp_handles_freed:
	clc

free_exit:
	popad
	ret

EndProc VDD_PH_Mem_Free_Page


;******************************************************************************
;
;   VDD_PH_Mem_Restore_Mapping
;
;   DESCRIPTION:    Physically reset the graphics controller mapping to
;		    the VM's current state.
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Restore_Mapping

	push	eax
	push	edx
	mov	ah, [edi.VDD_Stt.G_Misc]
	and	ah, mGrp6Addr
	jmp	short sam_set_mapping

EndProc VDD_PH_Mem_Restore_Mapping


;******************************************************************************
;
;   VDD_PH_Mem_Set_A0_Mapping
;
;   DESCRIPTION:    Fill in MemC_Mod_Struc with A0mapping mod and physically
;		    modify the graphics controller for A0 64K mapping.
;
;   ENTRY:	    EBX = VM Handle, or 0 if forced planar mode
;		    ESI -> MemC_Mod_Struc
;
;   EXIT:	    none
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Set_A0_Mapping

	or	ebx, ebx
	jz	short sam_set_phys
	mov	[esi.MMS_data_port], pGrpData
	mov	[esi.MMS_index], 6
	mov	[esi.MMS_ANDmask], NOT mGrp6Addr
	mov	[esi.MMS_ORmask], 00000100b
	mov	[esi.MMS_flags], 0
sam_set_phys:

	push	eax
	push	edx
	mov	ah, 100b
sam_set_mapping:
	mov	dx, pGrpIndx
	in	al, dx		    ; read current index
	push	eax
	mov	al, 6
	out	dx, al
	IO_Delay
	inc	edx
	in	al, dx
	and	al, NOT mGrp6Addr
	or	al, ah
	out	dx, al
	dec	edx
	IO_Delay
	pop	eax
	out	dx, al		    ; restore index
	pop	edx
	pop	eax
	ret

EndProc VDD_PH_Mem_Set_A0_Mapping


;******************************************************************************
;
;   VDD_PH_Mem_Modify_VMs_MemC
;
;   DESCRIPTION:    Set/Clear fVDD_MemCmods in VDD_Flags and call
;		    VDD_State_Modify_VMs_MemC, if EBX != 0
;
;   ENTRY:	    EBX = VM handle, 0, if forced planar
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Modify_VMs_MemC

IFDEF	DEBUG
	or	ebx, ebx
	jz	SHORT MVM_DBG0
	Assert_VM_Handle EBX
	cmp	ebx, [Vid_MemC_VM]
	jz	SHORT MVM_DBG0
	cmp	[Vid_MemC_VM], 0
	je	SHORT MVM_DBG0
Trace_Out "Modify_VMs_MemC when VM is not MemC owner #EBX"
MVM_DBG0:
ENDIF
	ClrFlag [edi.VDD_Flags], fVDD_MemCmods
	cmp	[edi.VDD_MemC_ModCnt], 0
	je	short MVM_no_mods
	SetFlag [edi.VDD_Flags], fVDD_MemCmods
MVM_no_mods:

	or	ebx, ebx
	jz	short MVM_skip_state_call
	call	VDD_State_Modify_VMs_MemC
MVM_skip_state_call:
	ret

EndProc VDD_PH_Mem_Modify_VMs_MemC


;******************************************************************************
;
;   VDD_PH_Mem_Clear_MemC_mods
;
;   DESCRIPTION:    Clear any outstanding MemC mods
;
;   ENTRY:	    EBX = VM handle
;		    EDI -> VM's VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Clear_MemC_mods

	btr	[edi.VDD_Flags], bVDD_MemCmods
	jnc	short cmm_exit
	cmp	ebx, [Vid_MemC_VM]	;Q: VM owns MemC?
	jne	short @F		;   N:
	call	VDD_State_Clear_MemC_Owner ;Y: since the VM's state was modified
					;      we now have to flag that the VDD
					;      owns the MemC state instead
@@:
	ClrFlag [edi.VDD_Flags], fVDD_MappedA0
	mov	[edi.VDD_MemC_ModCnt], 0
IFDEF Ext_VGA
	mov	[edi.VDD_Bank_Select], 0
ENDIF
	call	VDD_State_Modify_VMs_MemC
cmm_exit:
	ret

EndProc VDD_PH_Mem_Clear_MemC_mods


;******************************************************************************
;
;   VDD_PH_Mem_Access_Page
;
;   DESCRIPTION:    Modify current memory controller state to access the
;		    specified page.
;
;   ENTRY:	    EAX = page handle
;		    EBX = VM handle, 0, if forced planar mode
;		    EDX = flags
;			  bit 0, set if page to be mapped into VM
%OUT bit 0 flag is currently ignored, but reserved for future
;			    (all others reserved and should be set to 0)
;		    EDI = VDD CB ptr
;
;   EXIT:	    ECX = physical page #
;		    Carry set, if MemC state was modified to access this page
;
;   USES:	    ECX, Flags
;
;   ASSUMES:	    VM EBX is MemC owner
;
;==============================================================================
BeginProc VDD_PH_Mem_Access_Page

IFDEF DEBUG_verbose
	queue_out 'access page #eax for #ebx'
ENDIF
IFDEF DEBUG
	or	ebx, ebx			;Q: forced planar?  (VM handle=0)
	jz	short ap_planar 		;   Y:
	Assert_VDD_ptrs ebx,edi,Pseudo_OK
ap_planar:
	test	edx, NOT 1
	jz	short @F
	Debug_Out 'non-zero reserved flags passed to VDD_PH_Mem_Access_Page'
@@:
ENDIF

	pushad

IFDEF DEBUG
	call	VDD_PH_Mem_Debug_Validate_PH
	jnc	short ap_D00
	VMMCall Crash_Cur_VM
ap_D00:
ENDIF

	mov	esi, eax
	call	VDD_PH_Mem_update_LRU

IFDEF DEBUG
	cmp	ebx, [Vid_MemC_VM]
	je	short ap_D01
	cmp	[Vid_MemC_VM], 0
	je	short ap_D01
	Debug_Out "VDD_PH_Mem_Access_Page called when VM not MemC owner"
ap_D01:
ENDIF

	mov	esi, eax
	call	VDD_PH_Mem_CalcPagePhys
	xchg	eax, ecx			; eax=bank #; cl,ch=page #,base
	xor	edx, edx			; flags for changes
						;   bit 0, set if change made
IFDEF Ext_VGA
	inc	edx				; assume bank change
	cmp	eax, [edi.VDD_Bank_Select]	;Q: bank changed?
	jne	short ap_bank_change		;   Y:
	xor	edx, edx			; no bank change
	or	eax, eax			;Q: 1st bank?
	jz	short ap_not_banked		;   Y:
ap_bank_change:
	mov	[edi.VDD_Bank_Select], eax
	mov	[edi.VDD_MemC_ModCnt], 0

IFDEF 	PVGA
; Western Digital bank switching		- C. Chiang -
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short ap_not_pvga
	;AL=value for segsel reg
	call	PVGA_Select_Bank
	jmp	short ap_return		;[or do all the stuff Video 7 does]
ap_not_pvga:
ENDIF	;PVGA

IFDEF TLVGA
	TestMem [edi.VDD_TFlags], fVT_TLVGA
	jz	short ap_not_et3000
	;convert bank in AL to ET3000 segsel reg value (for both read & write):
	mov	ah,al
	shl	ah,3
	and	ax,03807h
	or	al,ah
	or	al,040h
	jmp	short ap_tli_2
ap_not_et3000:
	TestMem [edi.VDD_TFlags], fVT_TL_ET4000     ;test if ET4000
	jz	short ap_not_et4000
	;convert bank in AL to ET4000 segsel reg value (for both read & write):
	mov	ah,al
	shl	ah,4
	and	ax,0F00Fh
	or	al,ah
ap_tli_2:
	;AL=value for segsel reg
	call	TLVGA_Select_Bank
	jmp	short ap_return		;[or do all the stuff Video 7 does]
ap_not_et4000:
ENDIF	;TLVGA

IFDEF V7VGA
	TestMem [edi.VDD_TFlags], fVT_V7VGA
	jz	short ap_not_V7VGA
	call	V7VGA_Change_Bank
	or	ebx, ebx			;Q: forced planar?  (VM handle=0)
	jz	ap_return			;   Y: we're done
	or	eax, eax			;Q: first bank
	jz	short ap_bank0_selected 	;   Y: restore mem mapping
	call	VDD_PH_Mem_Set_A0_Mapping	;   N: force A0 mapping
	inc	[edi.VDD_MemC_ModCnt]		;   N: include A0 mapping mod with
						;      bank mods
	cmp	ch, 0B0h			;Q: text page?
	jb	short ap_mod_memc		;   N:
	sub	cl, ch				;   Y: convert to A0 mapping
	add	cl, 0A0h
	jmp	short ap_mod_memc

ap_bank0_selected:
	call	VDD_PH_Mem_Restore_Mapping	; restore VM's mapping
	call	VDD_PH_Mem_Modify_VMs_MemC	;  & clear modified MemC state
	jmp	short ap_chk_mapping

ap_not_V7VGA:
ENDIF	;V7VGA
	jmp	short ap_return

ap_not_banked:
ENDIF	;Ext_VGA

ap_chk_mapping:
	or	ebx, ebx			;Q: forced planar?  (VM handle=0)
	jz	short ap_return 		;   N: forced A0 mapping, so exit
	cmp	ch, 0B0h			;Q: Graphics mapping?
	jb	short ap_no_mod 		;   Y: leave mapping alone
	cmp	cl, 0C0h			;Q: Beyond the VRAM range?
	jnb	short @F			;   Y: definitely remap!
	cmp	ebx, [Vid_CRTC_VM]		;Q: VM owns CRTC?
	jz	short ap_No_mod 		;   Y: leave mapping alone
@@:	sub	cl, ch				;   N: convert to A0 mapping
	add	cl,0A0h
	bts	[edi.VDD_Flags], bVDD_MappedA0	;Q: A0 currently mapped?
	jc	short ap_return 		;   Y: return

;
; change the memory mapping from B8 or B0 to A0, so the VM can access more
; than just 8 pages of video memory
;

	or	dl, 1				; flag mapping change
	lea	esi, [edi.VDD_MemC_Mods]
	call	VDD_PH_Mem_Set_A0_Mapping
	mov	[edi.VDD_MemC_ModCnt], 1
;;Trace_Out 'adjusting mapping to A0'
	jmp	short ap_mod_memc

ap_no_mod:
	btr	[edi.VDD_Flags], bVDD_MappedA0	;Q: A0 currently mapped?
	jnc	short ap_return 		;   N: return
	or	dl, 1
	call	VDD_PH_Mem_Restore_Mapping	; restore VM's mapping
	mov	[edi.VDD_MemC_ModCnt], 0	; clear MemC mods

ap_mod_memc:
	call	VDD_PH_Mem_Modify_VMs_MemC	;  & clear modified MemC state

ap_return:
	movzx	ecx,cl
	mov	[esp.Pushad_ECX], ecx
	bt	edx, 0				;Q: state changed?
						;   Y: return carry set

access_exit:
	popad
	ret

EndProc VDD_PH_Mem_Access_Page


;******************************************************************************
;
;   VDD_PH_Mem_Page_Accessible
;
;   DESCRIPTION:    Determine if a given page is accessible with the current
;		    MemC state.  This routine is called by VDDVMMEM for each
;		    mapped physical page after a call to VDD_PH_Mem_Access_Page
;		    to identify which mapped pages need to be unmapped, since
;		    they are no longer accessible because of a modification
;		    done to the MemC state to access the page passed to
;		    VDD_PH_Mem_Access_Page.
;
;   ENTRY:	    EAX = page handle
;		    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    Carry clear, if page not accessible
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Page_Accessible

	push	eax
	push	ecx
	call	VDD_PH_Mem_CalcPagePhys ; EAX = phys page #, ECX = bank #

IFDEF Ext_VGA
	cmp	ecx, [edi.VDD_Bank_Select]  ;Q: same bank?
	clc
	jne	short pa_exit		    ;	N: return carry clear
ENDIF
	cmp	ebx, [Vid_CRTC_VM]	    ;Q: VM owns CRTC?
	jne	short pa_chk_B8 	    ;	N: check for B8 mapping
	cmp	cl, 0C0h		    ;Q: page beyond allowable?
	jb	short pa_no_chg 	    ;	N:
pa_chk_B8:
	cmp	cl, 0B8h		    ;Q: CGA mapping?
	mov	cl, 0
pa_no_chg:
	cmc
	adc	cl, 0			    ; cl = 1, if A0 mapping forced
	bt	[edi.VDD_Flags], bVDD_MappedA0
	sbb	cl, 0			    ; cl = 0, if no change, else
					    ;	 = 1 or -1
	shr	cl, 1			    ; move bit 0 into Carry

pa_exit:
	pop	ecx
	pop	eax
pa_skip:
	ret

EndProc VDD_PH_Mem_Page_Accessible


;******************************************************************************
;
;   VDD_PH_Mem_Release_Page
;
;   DESCRIPTION:    This call informs VDDPHMEM that a page is no longer being
;		    accessed.  VDDPHMEM does NOT free the page, and it does
;		    NOT change the MemC state.
;
;   ENTRY:	    EAX = page handle
;
;   EXIT:	    none
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Release_Page

IFDEF DEBUG
	call	VDD_PH_Mem_Debug_Validate_PH
	jc	short release_exit
ENDIF

	push	esi
	mov	esi, eax
	call	VDD_PH_Mem_Update_LRU
	pop	esi
release_exit:
	ret

EndProc VDD_PH_Mem_Release_Page


IFDEF Ext_VGA
;******************************************************************************
;
;   VDD_PH_Mem_Get_First_PageId_of_Bank
;
;   DESCRIPTION:
;
;   ENTRY:	    ECX = bank #
;
;   EXIT:	    ECX = page id
;
;   USES:	    ECX, Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Get_First_PageId_of_Bank

IFDEF	PVGA
	TestMem [VT_Flags],fVT_PVGA
	jz	short gfpb_not_pvga
	shl	ecx, 4
gfpb_not_pvga:
ENDIF

IFDEF TLVGA
	TestMem [VT_Flags],<fVT_TLVGA+fVT_TL_ET4000>
	jz	short gfpb_not_tli
	shl	ecx, 4
gfpb_not_tli:
ENDIF

IFDEF V7VGA
	TestMem [VT_Flags], fVT_V7VGA
	jz	short gfpb_not_V7VGA
	shl	ecx, 4
gfpb_not_V7VGA:
ENDIF
	ret

EndProc VDD_PH_Mem_Get_First_PageId_of_Bank


;******************************************************************************
;
;   VDD_PH_Mem_Get_Alt_Bank_Page
;
;   DESCRIPTION:    Find page handle for a page in an alternate bank which has
;		    the same bank relative page #.
;
;   ENTRY:	    EAX = page handle
;		    ESI = last page returned, or 0
;		    EBX = VM Handle
;		    EDI -> VM's VDD_CB_Struc
;
;   EXIT:	    IF Carry clear THEN
;			ESI = page id in alternate bank
;		    ELSE
;			no more alternate banks
;
;   USES:	    ESI, Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Get_Alt_Bank_Page

	push	ecx
	xor	ecx, ecx
IFDEF V7VGA
	TestMem [edi.VDD_TFlags], fVT_V7VGA
	jz	short gabp_not_V7VGA

	test	[edi.VDD_Stt.S_V7_ExtComp], fSeqFCseqChain4
	jz	short gabp_not_V7VGA
	mov	cl, 3
	test	[edi.VDD_Stt.S_MMode], fSeq4Chain4
	jz	short gabp_got_max
	mov	cl, 7
	jmp	short gabp_got_max
gabp_not_V7VGA:
ENDIF

	jecxz	short gabp_exit
gabp_got_max:
	pushad
	or	esi, esi		    ;Q: first time?
	jnz	short gabp_next_bank	    ;	N:
	movzx	eax, [eax.PDS_virtual_id]
	call	VDD_PH_Mem_Remove_Banking   ; eax = bank rel page #, ecx = bank #
	xor	ecx, ecx
	jmp	short gabp_create_id

gabp_next_bank:
	movzx	eax, [esi.PDS_virtual_id]
	call	VDD_PH_Mem_Remove_Banking   ; eax = bank rel page #, ecx = bank #
	inc	ecx
gabp_create_id:
	cmp	ecx, [esp.Pushad_ecx]	    ;Q: beyond max bank?
	ja	short gabp_no_more	    ;	Y: quit
	shl	ecx, 4
	or	eax, ecx		    ; eax = new page id
	call	VDD_PH_Mem_Get_Page_Owner
	mov	esi, eax
	cmp	eax, [esp.Pushad_eax]	    ;Q: starting point?
	je	gabp_next_bank		    ;	Y: skip to next
	cmp	ebx, [esp.Pushad_ebx]	    ;Q: same owner VM?
	jne	gabp_next_bank		    ;	N: skip to next
	mov	[esp.Pushad_ESI], eax
	popad
	clc
	pop	ecx
	ret

gabp_no_more:
	popad
gabp_exit:
	xor	esi, esi
	stc
	pop	ecx
	ret

EndProc VDD_PH_Mem_Get_Alt_Bank_Page


;******************************************************************************
;
;   VDD_PH_Mem_Add_Banking
;
;   DESCRIPTION:
;
;   ENTRY:	    EAX = page id in current bank
;		    EBX = VM Handle
;		    EDI -> VM's VDD_CB_Struc
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc VDD_PH_Mem_Add_Banking

%OUT what about read/write, access since most SVGAs provide separate banking
IFDEF	PVGA
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short ab_not_pvga
	push	ecx
	movzx	ecx,[edi.VDD_Stt.G_PVGA0A]
	shl	ecx,4
	add	eax,ecx
	pop	ecx
	jmp	SHORT ab_exit
ab_not_pvga:
ENDIF	;PVGA

IFDEF TLVGA
	TestMem [edi.VDD_TFlags], fVT_TLVGA
	jz	short ab_not_et3000
	push	ecx
	mov	cl,[edi.VDD_Stt.V_Extend.TLI_SegSel]
	mov	ch,cl
	and	cx,03807h	; ch = read bank bits, cl = write bank bits
	shr	ch,3
	jmp	short ab_tli_2	;go to common code with ET4000
ab_not_et3000:
	TestMem [edi.VDD_TFlags],fVT_TL_ET4000	    ;test if ET4000
	jz	short ab_not_et4000
	push	ecx
	mov	cl,[edi.VDD_Stt.V_Extend.TLI_SegSel]
	mov	ch,cl
	and	cx,0F00Fh	; ch = read bank bits, cl = write bank bits
	shr	ch,4
ab_tli_2:
	cmp	cl,ch			;Q: read bank = write bank?
	je	short ab_tli_ok		;   Y:
	Debug_Out 'read & write banking differ in VDD_PH_Mem_Add_Banking'
ab_tli_ok:
	movzx	ecx,cl
	shl	ecx,4
	add	eax,ecx
	pop	ecx
	jmp	SHORT ab_exit
ab_not_et4000:
ENDIF

IFDEF V7VGA
	TestMem [edi.VDD_TFlags], fVT_V7VGA
	jz	short ab_not_V7VGA
	push	ecx
	mov	ecx, eax
	call	V7VGA_Read_Bank     ; read 2 or 4 bank bits into EAX
	shl	eax, 4		    ; shift them into position
	add	eax, ecx	    ; add page # within bank
	pop	ecx
	Assumes_Fall_Through ab_exit
ab_not_V7VGA:
ENDIF

ab_exit:
	ret

EndProc VDD_PH_Mem_Add_Banking


;******************************************************************************
;
;   VDD_PH_Mem_Remove_Banking
;
;   DESCRIPTION:
;
;   ENTRY:	    EAX = page id
;		    EBX = VM Handle
;		    EDI -> VM's VDD_CB_Struc
;
;   EXIT:	    EAX = page id in current bank
;		    ECX = bank
;
;   USES:	    EAX, ECX, Flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Remove_Banking

IFDEF PVGA
	TestMem [edi.VDD_TFlags],fVT_PVGA
	jz	short rb_not_pvga
	mov	ecx, eax
	and	eax, 0Fh
	shr	ecx, 4
rb_not_pvga:
ENDIF

IFDEF V7VGA
	TestMem [edi.VDD_TFlags], fVT_V7VGA
	jz	short rb_not_V7VGA
%OUT not right for V7 extended chain4 modes
	mov	ecx, eax
	and	eax, 00001111b
	shr	ecx, 4
rb_not_V7VGA:
ENDIF

IFDEF TLVGA
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jz	short rb_not_tli
	mov	ecx, eax
	and	eax, 0Fh
	shr	ecx, 4
rb_not_tli:
ENDIF
	ret
EndProc VDD_PH_Mem_Remove_Banking


IFDEF V7VGA
;******************************************************************************
;
;   V7VGA_Read_Bank
;
;   DESCRIPTION:
;
;   ENTRY:	    EBX = VM Handle, or 0 if forced planar mode
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    AL = 4 bits of bank select
;
;   USES:
;
;==============================================================================
BeginProc V7VGA_Read_Bank

	TestMem [edi.VDD_Flags], fVDD_IOT   ;Q: trapping enabled?
	jnz	short vrb_trapped	    ;	Y:
	mov	dx, pSeqIndx		    ;	N: read physical bank state
	in	al, dx			    ; read current seq. index
	push	eax			    ; save it
	mov	ax,[Vid_Enable_IV_Word]
	out	dx, ax			    ; enable extensions
	IO_Delay
	mov	al, 0F6h		    ; read V7's bank select register
	out	dx, al
	IO_Delay
	inc	edx
	in	al, dx
	IO_Delay
	mov	[edi.VDD_Stt.S_V7_BankSel], al
	dec	edx
	mov	al, 0F9h		    ; read V7's extended page select reg
	out	dx, al
	IO_Delay
	inc	edx
	in	al, dx
	IO_Delay
	mov	[edi.VDD_Stt.S_V7_ExtPageSel], al
	pop	eax
	dec	edx
	out	dx, al			    ; restore seq. index
	mov	dx, pMiscRead		    ; read the miscellaneous register
	in	al, dx
	mov	[edi.VDD_Stt.V_Misc], al
vrb_trapped:

	mov	al, [edi.VDD_Stt.S_V7_BankSel]
IFDEF DEBUG
	push	ecx
%OUT not checking V7 extended chain4 bit in VDD_PH_Mem_Add_Banking
	mov	cl, al
	mov	ch, cl
	and	cx, 0000110000000011b	; ch = read bank bits, cl = write bank bits
	shr	ch, 2
	cmp	cl, ch			;Q: read bank = write bank?
	je	short ab_ok		;   Y:
	Debug_Out 'read & write banking differ in VDD_PH_Mem_Add_Banking'
ab_ok:
	pop	ecx
ENDIF
	and	al, 3
	test	[edi.VDD_Stt.S_MMode], fSeq4Chain4
	jz	short v7rb_exit
	test	[edi.VDD_Stt.S_V7_ExtComp], fSeqFCseqChain4
	jz	short v7rb_exit
	mov	ah, [edi.VDD_Stt.V_Misc]
	shl	ah, 3			; move bit 5 into carry
	rcl	al, 1			; roll carry into bank select as bit 1
	mov	ah, [edi.VDD_Stt.S_V7_ExtPageSel]
	shr	ah, 1			; move bit 0 into carry
	rcl	al, 1			; roll carry into bank select as bit 0
v7rb_exit:
	movzx	eax, al
	ret

EndProc V7VGA_Read_Bank


;******************************************************************************
;
;   V7VGA_Select_Bank
;
;   DESCRIPTION:
;
;   ENTRY:	    AL = 4 bits of bank select
;		    EBX = VM Handle, or 0 if forced planar mode
;		    EDI -> VDD_CB_Struc
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc V7VGA_Select_Bank

	pushad
	mov	cl, al			; al = 4 bits of bank select
	mov	dx, pSeqIndx
	in	al, dx
	IO_Delay
	push	eax			; save original Seq. index
	mov	ax,[Vid_Enable_IV_Word]
	out	dx, ax			; enable extensions
	test	[edi.VDD_Stt.S_MMode], fSeq4Chain4
	jz	short @F
	test	[edi.VDD_Stt.S_V7_ExtComp], fSeqFCseqChain4
	jz	short @F
	mov	al, 0F9h
	xor	ah, ah
	shr	cl, 1			; shift bank bit 0 into carry
	rcl	ah, 1			; shift carry into bit 0
	out	dx, ax
	mov	dx, pMiscIn
	in	al, dx
	rcl	al, 3			; rotate bit 5 into carry
	shr	cl, 1			; shift bank bit 1 into carry
	rcr	al, 3			; rotate carry back into bit 5
	mov	dx, pMisc
	out	dx, al
@@:
	and	cl, 3
	mov	ch, cl
	shl	ch, 2
	or	cl, ch
	mov	dx, pSeqIndx
	mov	al, 0F6h
	out	dx, al
	IO_Delay
	inc	edx			; edx=pSeqData
	in	al, dx
	IO_Delay
	and	al, 0F0h
	or	al, cl
	out	dx, al
	IO_Delay
	dec	edx			; edx=pSeqIndx
	pop	eax
	out	dx, al			; restore Seq index
	popad
	ret

EndProc V7VGA_Select_Bank


;******************************************************************************
;
;   V7VGA_Change_Bank
;
;   DESCRIPTION:    V7VGA bank selection routine - set VDD_MemC_ModCnt and
;		    fills in the VDD_MemC_Mods table in the VM's control block.
;
;   ENTRY:	    AL = 4 bits of bank select
;		    EBX = VM Handle, or 0 if forced planar mode
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    Extended Sequencer Registers & Misc Output Register
;		    programming has been modified to select the specified bank
;		    for reading and writing.
;		    ESI -> next available entry in VDD_MemC_Mods table
;
;   USES:	    Flags
;
;==============================================================================
BeginProc V7VGA_Change_Bank

	pushad
	mov	cl, al			; al = 4 bits of bank select

	lea	esi, [edi.VDD_MemC_Mods]
%OUT V7VGA_Change_Bank needs to check extended chain4 modes for extra 2 bits of bank select
IF 1
%OUT deal with low 2 bits of bank select
	test	[edi.VDD_Stt.S_MMode], fSeq4Chain4
	jz	short @F
	test	[edi.VDD_Stt.S_V7_ExtComp], fSeqFCseqChain4
	jz	short @F
IF 1
	mov	dx, pSeqIndx
	mov	al, 0F9h
	xor	ah, ah
	shr	cl, 1			; shift bank bit 0 into carry
	rcl	ah, 1			; shift carry into bit 0
	out	dx, ax

	mov	dx, pMiscIn
	in	al, dx
	rcl	al, 3			; rotate bit 5 into carry
	shr	cl, 1			; shift bank bit 1 into carry
	rcr	al, 3			; rotate carry back into bit 5
	mov	dx, pMisc
	out	dx, al
ELSE
	shr	cl, 2
ENDIF
@@:
ENDIF
	and	cl, 3
	mov	ch, cl
	shl	ch, 2
	or	cl, ch

	or	ebx, ebx		;Q: forced planar mode?
	jz	short V7SB_set_phys	;   Y: just set phys state

	mov	[esi.MMS_data_port], pSeqData
	mov	[esi.MMS_index], 0F6h
	mov	[esi.MMS_ANDmask], 11110000b
	mov	[esi.MMS_ORmask], cl
	mov	[esi.MMS_flags], fMMS_OEM_extension
	add	esi, SIZE MemC_Mod_Struc
	mov	[esp.Pushad_ESI], esi
	mov	[edi.VDD_MemC_ModCnt], 1 ;~~~~~~~~~~~~~~only 1 entry for now!

V7SB_set_phys:
	mov	dx, pSeqIndx
	mov	ax,[Vid_Enable_IV_Word]
	out	dx, ax			; enable extensions
	mov	al, 0F6h
	out	dx, al
	inc	dl
	in	al, dx
	and	al, 11110000b
	or	al, cl
	out	dx, al
	popad
	ret
EndProc V7VGA_Change_Bank
ENDIF	;V7VGA

IFDEF PVGA
;******************************************************************************
;
;   PVGA_Select_Bank
;
;   DESCRIPTION:    PVGA bank selection routine - inc VDD_MemC_ModCnt and
;		    fills in the VDD_MemC_Mods table in the VM's control block.
;
;   ENTRY:	    AL = value for Segment Select register (converted from
;			bank no. appropriately for PVGA)
;		    EBX = VM Handle, or 0 if forced planar mode
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    Segment Select Register
;		    programming has been modified to select the specified bank
;		    for reading and writing.
;
;   USES:	    Flags
;
;   AUTHOR:	    C. Chiang
;
;==============================================================================
BeginProc PVGA_Select_Bank

	pushad
	mov	cl, al
	lea	esi, [edi.VDD_MemC_Mods]
	or	ebx, ebx		;Q: forced planar mode?
	jz	short PVGASB_set_phys	;   Y: just set phys state

	mov	[esi.MMS_data_port], 03CEh
	mov	[esi.MMS_index], 9
	mov	[esi.MMS_ANDmask], 0
	mov	[esi.MMS_ORmask], cl
	mov	[esi.MMS_flags], fMMS_OEM_extension
	add	esi, SIZE MemC_Mod_Struc
	inc	[edi.VDD_MemC_ModCnt]

PVGASB_set_phys:
	push	dx
	mov	dx,03CEh
	mov	al, 9
	out	dx,al
	inc	dx
	mov	al, cl
	out	dx,al
	pop	dx
	popad
	ret

EndProc PVGA_Select_Bank
ENDIF	;PVGA


IFDEF TLVGA
;******************************************************************************
;
;   TLVGA_Select_Bank
;
;   DESCRIPTION:    TLVGA bank selection routine - inc VDD_MemC_ModCnt and
;		    fills in the VDD_MemC_Mods table in the VM's control block.
;
;   ENTRY:	    AL = value for Segment Select register (converted from
;			bank no. appropriately for ET3000 or ET4000)
;		    EBX = VM Handle, or 0 if forced planar mode
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    Segment Select Register
;		    programming has been modified to select the specified bank
;		    for reading and writing.
;		    ESI -> next available entry in VDD_MemC_Mods table
;
;   USES:	    Flags
;
;==============================================================================
BeginProc TLVGA_Select_Bank

	lea	esi, [edi.VDD_MemC_Mods]
	or	ebx, ebx		;Q: forced planar mode?
	jz	short TLSB_set_phys	;   Y: just set phys state

	mov	[esi.MMS_data_port], 03CDh
	mov	[esi.MMS_index], 0
	mov	[esi.MMS_ANDmask], 0
	mov	[esi.MMS_ORmask], al
	mov	[esi.MMS_flags], fMMS_OEM_extension or fMMS_no_index
	add	esi, SIZE MemC_Mod_Struc
	inc	[edi.VDD_MemC_ModCnt]

TLSB_set_phys:
	push	dx
	mov	dx,03CDh
	out	dx,al
	pop	dx
	ret

EndProc TLVGA_Select_Bank
ENDIF	;TLVGA


IFDEF TLVGA
;******************************************************************************
;
;   Get_Usable_Video_Pages
;
;   DESCRIPTION:    Limits video pages to 16 in certain circumstances
;
;   ENTRY:	    ECX = pages
;
;   EXIT:	    ECX = pages
;
;   USES:	    ECX, flags
;
;==============================================================================
BeginProc Get_Usable_Video_Pages
	;enter with ECX=value of Video_Pages variable
	;return ECX=value for Video_Pages such that max=16 (256k bytes) if
	; chip=ET3000 and ATC 16 bit 4=0 (non-hires mode)
	;preserve regs<>ECX
	TestMem [VT_Flags], fVT_TLVGA
	jz	short guvp_4
	cmp	ecx,16
	jbe	short guvp_4
	push	ebx
	push	edi
	mov	ebx,[Vid_CRTC_VM]  ;handle of VM currently running on hardware
	SetVDDPtr edi
	test	[edi.VDD_Stt.A_Pal+016h],010h
	jnz	short guvp_2
	mov	ecx,16
guvp_2:
	pop	edi
	pop	ebx
guvp_4:
	ret
EndProc Get_Usable_Video_Pages
ENDIF
ENDIF	;Ext_VGA


IFDEF DEBUG
;******************************************************************************
;
;   VDD_PH_Mem_Debug_Validate_PH
;
;   DESCRIPTION:    Debug routine to validate a page handle.
;
;   ENTRY:	    EAX = page handle
;
;   EXIT:	    Carry clear, if Page Handle valid
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_PH_Mem_Debug_Validate_PH

	pushad
	mov	esi, [VDD_PageHandle_List]
	mov	ecx, eax
	movzx	eax, [ecx.PDS_physpage]
	mov	edx, eax
	PPD_Index_To_Ptr eax
	mov	eax, [eax.PPD_owner_PH]
	or	eax, eax
	jz	short dvph_bad
dvph_chk_ph_lp:
	cmp	eax, ecx		    ;Q: phys page points to PH?
	je	short dvph_ok		    ;	Y: handle okay
	VMMCall List_Get_Next
	jz	short dvph_ok		    ; jump, if no more entries in list
	cmp	[eax.PDS_physpage], dx	    ;Q: next PH maps same phys page?
	je	dvph_chk_ph_lp		    ;	Y: check if same PH as ecx

dvph_bad:
	mov	eax, ecx
	mov	ecx, [esp+SIZE Pushad_Struc]; get return address
	Debug_Out 'Bad Page Handle #eax passed to ?ecx'
	stc
	jmp	short dvph_exit
dvph_ok:
	clc
dvph_exit:
	popad
	ret

EndProc VDD_PH_Mem_Debug_Validate_PH


;******************************************************************************
;
;   VDD_PH_Mem_Debug_Dump_Pages
;
;   DESCRIPTION:    Debug routine which dumps the video page table and
;		    the page handle list.
;
;   ENTRY:	    none
;
;   EXIT:	    none
;
;   USES:	    anything
;
;==============================================================================
BeginProc VDD_PH_Mem_Debug_Dump_Pages

	pushad
	Trace_Out ' '
	Trace_Out 'Display physical video page table'
	mov	esi, [VDD_PageHandle_List]
	mov	edi, [Video_Page_Table]
	xor	ecx, ecx
ddp_loop:
	test	cl, 1111b
	jnz	short ddp_no_hdr
	Trace_Out '      handle   owner     LRU    virt linr'
;;		   xxxx xxxxxxxx xxxxxxxx xxxxxxxx xxxx xxxx
ddp_no_hdr:
	Trace_Out '#cx ', NOEOL
	shl	ecx, PPD_Index_Factor
	mov	eax, [ecx][edi.PPD_owner_PH]
	or	eax, eax
	jz	short ddp_no_owner
	mov	ebx, [eax.PDS_owner]
	mov	edx, [ecx][edi.PPD_LRU_time]
	Trace_Out '#eax #ebx #edx ', NOEOL
ddp_map_lp:
	movzx	ebx, [eax.PDS_virtual_id]
	movzx	edx, [eax.PDS_linear_page]
	Trace_Out '#bx #dx  ', NOEOL
	movzx	edx, [eax.PDS_physpage]
	VMMCall List_Get_Next
	jz	short ddp_end_loop
	cmp	dx, [eax.PDS_physpage]
	je	ddp_map_lp
	jmp	short ddp_end_loop

ddp_no_owner:
	Trace_Out 'free', NOEOL

ddp_end_loop:
	Trace_Out ' '
	shr	ecx, PPD_Index_Factor
	inc	ecx
	cmp	ecx, [Video_Pages]
	jae	short ddp_dump_virt_list
	test	cl, 1111b
	jnz	ddp_loop
	VMMcall In_Debug_Chr
	jnz	ddp_loop

ddp_dump_virt_list:
	Trace_Out 'Display page handle list'
	VMMcall In_Debug_Chr
	jz	short ddp_exit

	mov	esi, [VDD_PageHandle_List]
	VMMCall List_Get_First
	xor	ecx, ecx
ddp_virt_lp:
	test	cl, 1111b
	jnz	short ddp_no_virt_hdr
	Trace_Out ' handle   owner   phys virt linr fl callback'
;;		   xxxxxxxx xxxxxxxx xxxx xxxx xxxx xx xxxxxxxxxxxxxxx
ddp_no_virt_hdr:
	mov	ebx, [eax.PDS_owner]
	movzx	edx, [eax.PDS_physpage]
	Trace_Out '#eax #ebx #dx ', NOEOL
	movzx	ebx, [eax.PDS_virtual_id]
	movzx	edx, [eax.PDS_linear_page]
	Trace_Out '#bx #dx ', NOEOL
	mov	bl, [eax.PDS_flags]
	mov	edx, [eax.PDS_callback]
	Trace_Out '#bl ?edx'
	VMMCall List_Get_Next
	jz	short ddp_exit
	inc	ecx
	test	cl, 1111b
	jnz	ddp_virt_lp
	push	eax
	VMMcall In_Debug_Chr
	pop	eax
	jnz	ddp_virt_lp

ddp_exit:
	popad
	ret

EndProc VDD_PH_Mem_Debug_Dump_Pages

ENDIF

VxD_CODE_ENDS

	END
