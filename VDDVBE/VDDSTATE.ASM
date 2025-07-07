       TITLE   VDD - Virtual Display Device for VGA   version 3.1
;******************************************************************************
;
;VDDSTATE  Virtual Display Device Register handling
;
;   Author: MDW
;
;   (C) Copyright MICROSOFT Corp. 1986-1991
;
;
;DESCRIPTION:
;	This module does all modifications to the registers of the display.
;	It also tracks, saves and restores a VM's register state.  It
;	handles all VM I/O as well as I/O from various parts of the VDD.
;	It keeps track of which VM owns the CRT controller state and which
;	VM owns the memory controller state.  Note that sometimes the VDD
;	itself or a pseudo VM will own these states.
;
;	Logically, VDDTIO is part of this module since it also modifies
;	the VM and physical register state.  However, it is separated out
;	because this module would be too large to assemble and do DIFFs.
;	The I/O trapping is only turned off when [Vid_CRTC_VM]=[Vid_MemC_VM].
;	When the CRTC VM loses the MemC state to the VDD or another VM, the
;	I/O trapping is enabled.  With the first access, the I/O trapping
;	is enabled and the MemC state is given to the CRTC state owner.
;	All other VMs (background VMs) only receive the MemC state on memory
;	access.  This gives a bit of priority to the forground application.
;
;******************************************************************************

	.386p

.xlist
	INCLUDE VMM.INC
	INCLUDE OPTTEST.INC
	INCLUDE DEBUG.INC
	INCLUDE VDDDEF.INC
.list

;******************************************************************************
; EXTRN routines
;
VxD_ICODE_SEG
EXTRN	VDD_Device_Init:NEAR
EXTRN	VDD_Font_Setup_Msg_Mode_Init:NEAR
EXTRN	VDD_Font_Save_Msg_Font:NEAR
IFDEF	VRTCTIMER
EXTRN	VDD_Clr_VRTC_Time_Out:NEAR
ENDIF
VxD_ICODE_ENDS

VxD_CODE_SEG
EXTRN	VDD_OEM_Sys_Critical_Init:NEAR
EXTRN	VDD_OEM_Device_Init:NEAR
EXTRN	VDD_OEM_Init_Msg_Mode_State:NEAR
EXTRN	VDD_OEM_System_Exit:NEAR
EXTRN	VDD_OEM_Pre_Restore_CRTC:NEAR
EXTRN	VDD_OEM_Post_Restore_CRTC:NEAR
EXTRN	VDD_OEM_Restore_Seq:NEAR	    ; C. Chiang
EXTRN	VDD_OEM_Pre_Restore_Attr:NEAR
EXTRN	VDD_OEM_Post_Restore_Attr:NEAR
EXTRN	VDD_OEM_Pre_Restore_MemC:NEAR
EXTRN	VDD_OEM_Post_Restore_MemC:NEAR
EXTRN	VDD_OEM_CRTC_Enable:NEAR
EXTRN	VDD_OEM_Save_Latches:NEAR
EXTRN	VDD_OEM_Restore_Latches:NEAR
EXTRN	VDD_OEM_Adjust_Screen_Start:NEAR
EXTRN	VDD_OEM_Chk_CRTC:NEAR
EXTRN	VDD_OEM_Chk_Cursor:NEAR
EXTRN	VDD_OEM_Adjust_Cursor:NEAR
EXTRN	VDD_OEM_Pre_OUT_Misc:NEAR
IFDEF SysVMin2ndBank
EXTRN	VDD_OEM_force_bank:NEAR
ENDIF
IFDEF Handle_VGAEnable
EXTRN	VDD_OEM_Get_VGAEnaPort:NEAR
ENDIF
IFDEF VGA8514
EXTRN	VDD_OEM_VGA_Off:NEAR
ENDIF

EXTRN	VDD_PH_Mem_Access_Latch_Page:NEAR
EXTRN	VDD_PH_Mem_End_Access_Latch_Page:NEAR
EXTRN	VDD_Font_Restore_Msg_Font:NEAR
EXTRN	VDD_VM_Mem_Alloc_Msg_Mode_Mem:NEAR
EXTRN	VDD_VM_Mem_Disable:NEAR
EXTRN	VDD_VM_Mem_Disable_Null:NEAR
EXTRN	VDD_VM_Mem_MapNull:NEAR
EXTRN	VDD_Proc_BGrnd_Notify:NEAR
EXTRN	VDD_TIO_Set_Trap:NEAR

EXTRN	VDD_VGA_Save_Regs:NEAR
EXTRN	VDD_VGA_Restore_DAC:NEAR

EXTRN	@VDD_VMIdle:NEAR
VxD_CODE_ENDS

;******************************************************************************
;
VxD_IDATA_SEG
EXTRN	Vid_Text_Rows_Ini:DWORD
EXTRN	Vid_Text_Rows_Sect:DWORD

IFDEF IBMXGA
EXTRN	VDD_XGA_Ini:BYTE
ENDIF

;*******
; Strings used in Fatal_Exit during initialization only
	EXTRN	VDD_Str_BadMsgMode:BYTE
VxD_IDATA_ENDS


VxD_DATA_SEG
EXTRN	Vid_Flags:DWORD
EXTRN	VT_Flags:DWORD
EXTRN	Vid_CB_Off:DWORD

;*******
;State of the physical registers:
;   The following contain VM handles, pseudo VM handles and zero to indicate
;   VM ownership, special state (such as message mode) and VDD ownership.
;
PUBLIC	Vid_Focus_VM, Vid_CRTC_VM, Vid_MemC_VM
Vid_Focus_VM			DD  0	    ; VM with display focus
Vid_CRTC_VM			DD  0	    ; Owner of CRTC registers
Vid_MemC_VM			DD  0	    ; Owner of Memory Ctlr registers
Vid_Latches_VM			DD  0	    ; Owner of Latches
Vid_Start_SR_MemC_VM		DD  0	    ; MemC owner at start of SR section

;*******
;Message mode pseudo VM state
;   Note that this is a shortened control block.  Only the flags, the
;   register state and the DAC is here.  These must be the first to appear
;   in the control block.
;
;HOWEVER in order to prevent horrible hiddeous "wild pointer" bugs we
;   will pad this thing out to the full VDD CB size so that all the
;   VDD code will "work" when it is pointed at this bogus control
;   block
;
PUBLIC Vid_Msg_Pseudo_VM, Vid_Msg_Pseudo_CB, Vid_Msg_DAC
Vid_Msg_Pseudo_VM		DD  0
Vid_Msg_Pseudo_CB		DD  0,0,0   ; VDD_Flags, VDD_TFlags & VDD_EFlags
.ERRE	0 EQ VDD_Flags
.ERRE	$-Vid_Msg_Pseudo_CB  EQ VDD_Stt
Vid_Msg_Regs			DB  SIZE Reg_State_Struc DUP (?)
.ERRE	$-Vid_Msg_Pseudo_CB  EQ VDD_DAC
Vid_Msg_DAC			DB  DAC_Msg_State_Size DUP (?)

	DB	((SIZE VDD_CB_Struc) - ($-Vid_Msg_Pseudo_CB)) DUP (?)

;*******
;Save/Restore memory VM state pointer (allocated on heap)
;
PUBLIC Vid_Planar_Pseudo_CB
Vid_Planar_Pseudo_CB		DD  0,0,0   ; VDD_Flags, VDD_TFlags & VDD_EFlags
.ERRE	$-Vid_Planar_Pseudo_CB	EQ VDD_Stt
Vid_Planar_State		DB  SIZE Reg_State_Struc DUP (?)

;*******
;Initial VM state variables
;
PUBLIC Vid_Initial_Text_Rows
Vid_Initial_Text_Rows		DB  ?

PUBLIC Vid_Msg_Pages
Vid_Msg_Pages			DB  2

ALIGN 4

IFDEF DEBUG

PUBLIC	VDD_State_MemC_Debug_Event, VDD_State_MemC_Debug_TS
VDD_State_MemC_Debug_Event  dd	-1  ; default to disabled
				    ;	 0	  - enabled but not scheduled
				    ;	-1	  - disabled
				    ;event handle - enabled & scheduled
VDD_State_MemC_Debug_TS     dd	OFFSET32 VDD_State_Schedule_Debug_Event
VDD_State_MemC_Debug_caller dd	?
ENDIF

VxD_DATA_ENDS

VxD_ICODE_SEG
;******************************************************************************
;VDD_State_Sys_Critical_Init
;
;DESCRIPTION:
;	Set up system VM as CRTC and MemC owner, adjust Msg_Pseudo_VM handle.
;
;ENTRY: EBX = VM_Handle of System VM
;	EDI -> VDD CB data
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;ASSUMES:
;	Vid_CB_Off has been defined before calling this routine
;
;==============================================================================
BeginProc VDD_State_Sys_Critical_Init, PUBLIC

	mov	[Vid_Focus_VM],ebx	    ; System VM has focus and is
	mov	[Vid_CRTC_VM],ebx	    ;	running on hardware
	mov	[Vid_MemC_VM],ebx

	mov	eax,OFFSET32 Vid_Msg_Pseudo_CB
	sub	eax,[Vid_CB_Off]	    ; The pseudo VM handle must be
	mov	[Vid_Msg_Pseudo_VM], eax    ; adjusted to have the same
					    ; offset to the start of the
					    ; VDD info as normal VM CBs
	jmp	VDD_OEM_Sys_Critical_Init   ; Do OEM specific state init
EndProc VDD_State_Sys_Critical_Init


IFDEF IBMXGA
;******************************************************************************
;
;   VDD_State_Detect_XGA
;
;   DESCRIPTION:    Attempt to detect XGA by comparing read video memory
;		    before and after the byte mode/word mode bit in the
;		    CRT controller mode register has been toggled.  On XGA
;		    this bit affects CPU addressing of video memory, but it
;		    affects CRTC addressing on VGA.  So, if reading video
;		    memory after the bit has been toggled gives different
;		    results, then we can assume that we running on XGA
;		    hardware.
;
;   ENTRY:	    EBX = VM_Handle of System VM
;		    EDI -> VDD CB data
;
;   EXIT:	    EAX = 0, if not XGA
;			= -1, if XGA
;
;   USES:	    EAX, ECX, EDX, ESI, Flags
;
;==============================================================================
BeginProc VDD_State_Detect_XGA

	push	ebx
	mov	dx, pGrpIndx
	mov	al, 6
	mov	ah, 101b
	out	dx, ax
	mov	esi, 0AFFFCh
	mov	ah, [esi+3]
	mov	al, [esi+2]
	shl	eax, 16
	mov	ah, [esi+1]
	mov	al, [esi+0]
	push	eax
	mov	byte ptr [esi+3], 5Ah
	mov	byte ptr [esi+2], 0A5h
	mov	byte ptr [esi+1], 12h
	mov	byte ptr [esi+0], 0EFh

	call	VDD_State_Get_CRTC_Index_Port
	add	edx, pStatColr-pCRTCIndxColr
.errnz (pStatMono-pCRTCIndxMono) - (pStatColr-pCRTCIndxColr)
	in	al,dx
	test	al,fStatVRTC		    ;Q: in retrace now?
	jz	short VS_DI_wait_retrace    ;	N:
	mov	ecx,8000h		    ;	Y: loop til end of retrace
@@:	in	al,dx
	test	al,fStatVRTC
	loopnz	@B

VS_DI_wait_retrace:
	mov	ecx,8000h		    ; loop til start of retrace
@@:	in	al,dx
	test	al,fStatVRTC
	loopz	@B

;
; Now we're in vertical retrace.  So toggle the byte mode/word mode bit
; to see if it changes how we read video memory.
;
	sub	edx, pStatColr-pCRTCIndxColr

	mov	al, 17h
	out	dx, al
	inc	edx
	in	al, dx
	xor	al, 01000000b		    ; toggle the bit
	out	dx, al

	mov	bh, [esi+3]
	mov	bl, [esi+2]
	shl	ebx, 16
	mov	bh, [esi+1]
	mov	bl, [esi+0]

	xor	al, 01000000b		    ; toggle the bit back
	out	dx, al

;
; restore video memory & graphics controller misc register
;
	pop	eax
	mov	[esi+0], al
	mov	[esi+1], ah
	shr	eax, 16
	mov	[esi+2], al
	mov	[esi+3], ah

	mov	dx, pGrpIndx
	mov	al, 6
	mov	ah, [edi.VDD_Stt.G_Misc]
	out	dx, ax

	xor	eax, eax
	cmp	ebx, 5AA512EFh
	je	short @F
	or	eax, TRUE
@@:
	pop	ebx
	ret

EndProc VDD_State_Detect_XGA
ENDIF


;******************************************************************************
;VDD_State_Device_Init
;
;DESCRIPTION:
;	Set up hardware for Windows environment, do any global register
;	state set up.
;
;ENTRY: EBX = VM_Handle of SYS VM
;	EDI -> VDD CB data
;
;EXIT:	Carry set, if error
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_State_Device_Init, PUBLIC

Assert_VDD_ptrs ebx,edi

; Initialize the control block
	call	VDD_State_Create_VM	    ; Init SYS VM's control block
	jc	SHORT VS_DI_Exit	    ;	If error (never), return CF=1

	call	VDD_VGA_Save_Regs	    ; Save the registers

; Set up initial register values that are needed
	call	VDD_OEM_Device_Init	    ; Init regs if necessary
	jc	SHORT VS_DI_Exit	    ;	If error, return CF=1

IFDEF IBMXGA
	call	VDD_State_Detect_XGA
	push	edi
	xor	esi,esi 		    ; [WIN386] section
	mov	edi, OFFSET32 VDD_XGA_Ini   ; Find this string
	VMMcall Get_Profile_Boolean
	pop	edi
	or	eax, eax
	jz	short @F
	SetFlag [edi.VDD_TFlags], fVT_XGAbit
	SetFlag [VT_Flags], fVT_XGAbit
@@:
ENDIF

	call	VDD_State_Get_Initial_Lines ; Get number of lines

	call	VDD_State_Init_MemC_Planar  ; Set up planar reg state
	jc	SHORT VS_DI_Exit	    ;	If error (never), return CF=1

	call	VDD_State_Init_Message_Mode ; Set up message reg state
	jc	SHORT VS_DI_Exit	    ;	If error, return CF=1

	call	VDD_TIO_Set_Trap
	clc

VS_DI_Exit:
	ret
EndProc VDD_State_Device_Init


;******************************************************************************
;VDD_State_State_Get_Initial_Lines
;
;DESCRIPTION:
;	Saves initial number of lines to create a VM with.  This will either
;	be a SYSTEM.INI value or be the value that the video BIOS reports.
;
;ENTRY: none
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_State_Get_Initial_Lines

	push	edi
	mov	edi, OFFSET32 Vid_Text_Rows_Ini ; Find this string
	mov	esi, OFFSET32 Vid_Text_Rows_Sect ; in this section
	VMMcall Get_Profile_Decimal_Int     ; Q: Initial_Text_Rows spec'd?
	jc	SHORT VS_GIL_TextRowsGet    ;	N: Ask BIOS
	jnz	SHORT VS_GIL_GotRows	    ;	Y: Save value specified

VS_GIL_TextRowsGet:
	BEGIN_Touch_1st_Meg
	movzx	eax, byte ptr ds:[BIOS_Line_Count]
	END_Touch_1st_Meg
	inc	eax

VS_GIL_GotRows:
;
; Round Vid_Initial_Text_Rows to a reasonable value:
;	 25/43/50 lines for VGA
;                        
	cmp	al,50			    ; VGA-Less than 50 => 25 line mode
	jae	SHORT VS_GIL_50Lines
	cmp	al,43
	jb	SHORT VS_GIL_25Lines
	mov	[Vid_Initial_Text_Rows],43
	jmp	SHORT VS_GIL_Exit
VS_GIL_50Lines:
	mov	[Vid_Initial_Text_Rows],50
	jmp	SHORT VS_GIL_Exit
VS_GIL_25Lines:
	mov	[Vid_Initial_Text_Rows],25
VS_GIL_Exit:
	pop	edi
	ret
EndProc VDD_State_Get_Initial_Lines


;******************************************************************************
;VDD_State_Init_MemC_Planar
;
;DESCRIPTION:
;	Saves mode 10 VM state for later programming by Set_MemC_Planar.
;
;ENTRY: EBX = VM_Handle of SYS VM
;	EDI -> VDD CB data
;
;EXIT:	If CF=1, error
;
;USES:	Flags, EAX, EDX, ESI
;
;==============================================================================
BeginProc VDD_State_Init_MemC_Planar, PUBLIC

Assert_VDD_ptrs ebx,edi

;
; map null memory for A0-AF
;
	mov	dh, 0A0h
	mov	dl, 16
@@:
	movzx	eax, dh
	call	VDD_VM_Mem_MapNull
	inc	dh
	dec	dl
	jnz	@B

;*******
; Set video mode via INT 10
;
	mov	eax,10h
	call	VDD_State_Set_Mode	    ; Set video mode

;*******
; Save register state
;
	mov	esi, [edi.VDD_TFlags]
	mov	[Vid_Planar_Pseudo_CB.VDD_TFlags], esi
	push	edi
	lea	esi,[edi.VDD_Stt]	    ; ESI = VM's state
	mov	edi, OFFSET32 Vid_Planar_State ; EDI = planar state save
.ERRNZ	(SIZE Reg_State_Struc) MOD 4
	mov	ecx,SIZE Reg_State_Struc/4
	cld
	rep movsd
	pop	edi
	SetFlag [Vid_Flags],fVid_PlanarInit
	call	VDD_VM_Mem_Disable_Null
	clc
	ret

EndProc VDD_State_Init_MemC_Planar

;******************************************************************************
;VDD_State_Init_Message_Mode
;
;DESCRIPTION:
;	Saves mode 3 VM state for later programming by Set_Message_Mode.
;	Init_MemC_Planar should be called before this for normal operation
;	since Set_MemC_Planar is used to save the font.
;
;ENTRY: EBX = VM_Handle of SYS VM
;	EDI -> VDD CB data
;
;EXIT:	Carry clear, or Fatal_Error called
;
;USES:	Flags, EAX, EDX, ESI
;
;==============================================================================
BeginProc VDD_State_Init_Message_Mode, PUBLIC

Assert_VDD_ptrs ebx,edi

	call	VDD_Font_Setup_Msg_Mode_Init
	; this dies on failure, it doesn't set CF and return

;*******
; Set video mode via INT 10
;
	Push_Client_State
	VMMcall Begin_Nest_Exec 	    ; Get ready for software ints
	mov	[ebp.Client_AX], 1202h	    ; set scan lines to 400
	mov	[ebp.Client_BL], 30h	    ;	to try to force to 8x16 font
	mov	eax, 10h
	VMMcall Exec_Int
Queue_Out "start of mode change for msg mode"
	mov	[ebp.Client_AX], 3	    ; Set mode
	mov	eax,10h
	VMMcall Exec_Int
	VMMcall End_Nest_Exec		    ; All done with software ints
	Pop_Client_State

	call	VDD_OEM_Init_Msg_Mode_State

	call	VDD_State_Get_Dimensions    ; EAX = rows, ECX = columns
	jc	short save_msgf_failed	    ;	fail, if not text mode
	imul	eax, ecx		    ; eax = # of char
	shl	eax, 1			    ; 2 bytes per char
	add	eax, P_SIZE - 1
	shr	eax, 12 		    ; eax = # of pages
	cmp	eax, 2
	jae	short @F
	mov	al, 2
@@:
	mov	[Vid_Msg_Pages], al

;*******
; Save Registers
;
	mov	esi, [edi.VDD_TFlags]
	mov	[Vid_Msg_Pseudo_CB.VDD_TFlags], esi
	push	edi
	lea	esi,[edi.VDD_Stt]	    ; ESI = VM's state
	mov	edi,OFFSET32 Vid_Msg_Regs   ; EDI = Msg mode regs
.ERRNZ	(SIZE Reg_State_Struc) MOD 4
	mov	ecx,SIZE Reg_State_Struc/4
	cld
	rep movsd
	mov	edi, [esp]
	push	ebx
	lea	esi,[edi.VDD_DAC]	    ; ESI = VM's DAC state
	lea	edx,[edi.VDD_Stt.A_Pal]
	mov	edi,OFFSET32 Vid_Msg_DAC    ; EDI = Msg mode DAC state
.ERRNZ	(DAC_Msg_State_Size) MOD 4
	mov	ecx,DAC_Msg_State_Size/4
	xor	bl, bl
imm_copy_msg_dac:
	movzx	ebx, byte ptr [edx]
	mov	eax, [ebx*4][esi]	    ; get specified DAC entry
	stosd
	inc	edx
	loop	imm_copy_msg_dac
	pop	ebx
	pop	edi

;*******
; Save Font
;
	call	VDD_Font_Save_Msg_Font	    ; Save the Font
	; this dies on failure, it doesn't set CF and return
	SetFlag [Vid_Flags], fVid_MsgInit   ; Message mode state init'd
	; at this point, CF should be clear (from the OR instruction)
	ret

save_msgf_failed:
	Fatal_Error <OFFSET32 VDD_Str_BadMsgMode>

EndProc VDD_State_Init_Message_Mode

;******************************************************************************
;VDD_State_Set_Mode
;
;DESCRIPTION:
;	Call BIOS to set mode in AX register
;
;ENTRY: EAX = BIOS mode desired
;	EBX = VM Handle
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc  VDD_State_Set_Mode

	mov	ebp, [ebx.CB_Client_Pointer]
	Push_Client_State
	VMMcall Begin_Nest_Exec 		; Get ready for software ints
	mov	[ebp.Client_AX], AX		; Set mode
	mov	eax,10h
	VMMcall Exec_Int
	VMMcall End_Nest_Exec			; All done with software ints
	Pop_Client_State
	ret

EndProc VDD_State_Set_Mode


IFDEF VGA8514
;******************************************************************************
;
;   VDD_State_Init_Complete
;
;   DESCRIPTION:    set bit 5 in sequencer register 1 to disable VGA screen
;
;   ENTRY:	    EBX = SYS VM Handle
;
;   EXIT:	    nothing
;
;   USES:	    EAX, EDX, Flags
;
;==============================================================================
BeginProc VDD_State_Init_Complete

	call	VDD_OEM_VGA_Off
	clc
	ret

EndProc VDD_State_Init_Complete
ENDIF

VxD_ICODE_ENDS


VxD_CODE_SEG
;******************************************************************************
;VDD_State_Create_VM
;
;DESCRIPTION:
;	Initialize flags and copy the message mode state to the VM.
;
;ENTRY: EBX = VM_Handle
;	EDI -> VDD control block data
;
;EXIT:	Carry flag cleared
;
;USES:	Flags, EAX, ECX, ESI
;
;==============================================================================
BeginProc VDD_State_Create_VM, PUBLIC

	push	edi
	mov	eax,[VT_Flags]
	mov	[edi.VDD_TFlags],eax	    ; Initialize CB display type flags
	VMMCall Test_Sys_VM_Handle	    ; Q: System VM
	cld
	jz	SHORT VSCVM_DACInit	    ;	Y: skip most regs init

;*******
; Initialize VDD_Stt
	mov	esi,OFFSET32 Vid_Msg_Regs   ; ESI = Msg mode state
	push	esi
	lea	edi,[edi.VDD_Stt]	    ; EDI = VM's reg state
.ERRNZ	(SIZE Reg_State_Struc) MOD 4
	mov	ecx,SIZE Reg_State_Struc/4
	rep movsd			    ; Copy primary reg state

;*******
; Initialize VDD_SttCopy
	pop	esi
	mov	edi, [esp]
	lea	edi,[edi.VDD_SttCopy]	    ; EDI = VM's copy reg state
	mov	ecx,SIZE Reg_State_Struc/4
	rep movsd			    ; Copy to copy reg state

;*******
; Initialize DAC state
VSCVM_DACInit:
; Clear DAC values to all zeroes and set indexes
	mov	edi, [esp]
	lea	edi,[edi.VDD_DAC]	    ; EDI = VM's reg state
	push	edi
	mov	ecx,(DAC_State_Size)/4
	xor	eax,eax
VSCVM_00:
	stosd				    ; Clear DAC values
	inc	eax			    ; and set indices
	loopd	VSCVM_00

; Move message state DAC values to new VM
;   Note that Message state DAC values consist of 16 entries where the
;   entry indices are not necessarily equal to 1/4 of the DAC entry offset
;   For VM's, this 4*index = offset relationship is maintained.
	pop	edi			    ; EDI = VM's DAC reg state
	TestMem [Vid_Flags],fVid_MsgInit
	jz	SHORT VSCVM_Exit
	mov	esi,OFFSET32 Vid_Msg_DAC    ; ESI = Msg mode DAC reg state
.ERRNZ	(DAC_Msg_State_Size) MOD 4
	mov	ecx,DAC_Msg_State_Size/4
.ERRNZ	(DAC_State_Size) MOD 4
VSCVM_01:
	lodsd
	movzx	edx,al			    ; Use index to compute offset
	mov	[edi][edx*4],eax	    ; Store new DAC entry
	loopd	VSCVM_01

; Finish init of DAC data
VSCVM_Exit:
	pop	edi
	lea	esi, [edi.VDD_DAC]
	mov	[edi.VDD_PEL_Addr], esi
	mov	[edi.VDD_PEL_Idx], 1
	mov	[edi.VDD_PEL_Mode], vDAC_Read_Mode

;*******
; Initialize Miscellaneous other values

	mov	[edi.VDD_VertCnt],VDD_VERT_PERIOD
	mov	[edi.VDD_HorizCnt],VDD_HORIZ_PERIOD
	xor	eax,eax
	mov	[edi.VDD_Time_Out_Handle],eax
	mov	[edi.VDD_Get_Mem_Count],eax
IFDEF	VRTCTIMER
	; update both bytes in one fell swoop
	.errnz	VDD_Framerate_Recip-VDD_Framerate-1
	mov	word ptr [edi.VDD_Framerate],ax
	mov	[edi.VDD_VRTC_timeout],eax
ENDIF

	call	VDD_TIO_Set_Trap
	clc
	ret
EndProc VDD_State_Create_VM


;******************************************************************************
;VDD_State_VM_Init
;
;DESCRIPTION:
;	Initialize VM's video state.
;
;ENTRY: EBX = VM_Handle
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, ESI
;
;==============================================================================
BeginProc VDD_State_VM_Init, PUBLIC

	SetVDDPtr edi
	VMMCall Test_Sys_VM_Handle	    ; Q: SYSTEM VM?
	jz	VS_VI_SYS_VM		    ;	Y: skip mode setting

	Push_Client_State
	VMMcall Begin_Nest_Exec 	    ; Get ready for software ints

	mov	[ebp.Client_AX], 1202h	    ; Select 400 scan line (50 rows)
	cmp	[Vid_Initial_Text_Rows],43  ; Q: 43 line mode?
	jne	SHORT VS_VI_AdjustMode	    ;	N: go do adjust
	mov	[ebp.Client_AX], 1201h	    ;	Y: 350 scan lines (43 rows)
VS_VI_AdjustMode:
	mov	[ebp.Client_BL], 30h
	mov	eax,10h
	VMMcall Exec_Int		    ; Select 350/400 scan lines
	cmp	[ebp.Client_Al],012h
	jz	SHORT VS_VI_Set_Mode
VS_VI_ErrAdjust:
Trace_Out "Video BIOS error, defaulting to 25 rows"
	mov	[Vid_Initial_Text_Rows],25  ; back to 25 line mode
VS_VI_Set_Mode:
	mov	[ebp.Client_AX], 0003h
	mov	eax,10h
	VMMcall Exec_Int		    ; Select 350/400 scan lines
	cmp	[Vid_Initial_Text_Rows],25  ; Q: 25 line mode?
	je	SHORT VS_VI_25		    ;	Y: All done
	mov	[ebp.Client_AX], 1112h
	mov	[ebp.Client_BL], 0
	mov	eax,10h
	VMMcall Exec_Int		    ; Select 8x8 alpha font, block 0
	mov	[ebp.Client_AX], 0100h
	mov	[ebp.Client_CX], 0407h
	mov	eax,10h
	VMMcall Exec_Int		    ; Set cursor to scan lines 4-7
VS_VI_25:
	VMMcall End_Nest_Exec		    ; All done with software ints
	Pop_Client_State

	TestMem [edi.VDD_Flags],fVDD_Win    ; Q: Windowed?
	jz	SHORT VS_VI_NotWin
	mov	[edi.VDD_Mod_Flag_Save],fVDD_M_Ctlr+fVDD_M_Curs
VS_VI_NotWin:

VS_VI_SYS_VM:
	bt	[edi.VDD_EFlags],bVDE_NoMain; Fail init if mem alloc failed
	ret
EndProc VDD_State_VM_Init


;******************************************************************************
;
;   VDD_State_Begin_SR_Section
;
;   DESCRIPTION:    Begin a "critical" section in which multiple calls will
;		    be made to Set_MemC_Planar and Set_MemC_Owner and we
;		    don't need to repeatedly save the registers or save and
;		    restore the latches.  A matching call to
;		    VDD_State_End_SR_Section must be made to end the special
;		    section.
;
;   ENTRY:	    none
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_State_Begin_SR_Section

IFDEF DEBUG
VxD_DATA_SEG
PUBLIC VDD_NoSR
VDD_NoSR    db	0
VxD_DATA_ENDS

	cmp	[VDD_NoSR], 0
	jne	short bsrs_exit     ; skip SR section processing, if non-zero
ENDIF

IFDEF DEBUG_verbose
	Mono_Out '<',noeol
ENDIF
	bts	[Vid_Flags], bVid_SR_Section
	jc	short bsrs_exit
	ClrFlag [Vid_Flags], <fVid_SR_Latch_res OR fVid_SR_regs_saved>
	push	eax
	mov	eax, [Vid_MemC_VM]
	mov	[Vid_Start_SR_MemC_VM], eax
	pop	eax
bsrs_exit:
	ret

EndProc VDD_State_Begin_SR_Section


;******************************************************************************
;
;   VDD_State_End_SR_Section
;
;   DESCRIPTION:    End a "critical" section in which multiple calls were
;		    made to Set_MemC_Planar and Set_MemC_Owner and we
;		    did't want to repeatedly save the registers or save and
;		    restore the latches.  VDD_State_Begin_SR_Section was
;		    called to start the special section.
;
;   ENTRY:	    EBX = VM handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_State_End_SR_Section

	btr	[Vid_Flags], bVid_SR_Section
	jnc	short esrs_set_memc

	push	eax
IFDEF DEBUG_verbose
	Mono_Out ':',noeol
ENDIF
	mov	eax, [Vid_Start_SR_MemC_VM]
	cmp	eax, ebx
	jne	short esrs_memc_changed
	xor	eax, eax
esrs_memc_changed:
	cmp	ebx, [Vid_MemC_VM]		;Q: memc needs to change?
	je	short esrs_memc_current 	;   N:
	btr	[Vid_Flags], bVid_SR_Latch_res	;   Y: Q: latches saved?
	jnc	short esrs_chg_memc		;	  N: just set memc
	jmp	short esrs_chg_memc_and_latches ;	  Y: set memc & latches

esrs_memc_current:
	cmp	ebx, [Vid_Start_SR_MemC_VM]	;Q: memc changed?
	btr	[Vid_Flags], bVid_SR_Latch_res
	jne	short esrs_chg_memc_and_latches ;   Y: set memc & latches
	jnc	short esrs_exit 		;   N: done, if latches not saved
esrs_chg_memc_and_latches:
	mov	[Vid_Latches_VM], 0
esrs_chg_memc:
	mov	[Vid_MemC_VM], eax
esrs_exit:
	pop	eax

esrs_set_memc:
	call	VDD_State_Set_MemC_Owner
	ClrFlag [Vid_Flags], fVid_SR_regs_saved
IFDEF DEBUG_verbose
	Mono_Out '>',noeol
ENDIF
	ret

EndProc VDD_State_End_SR_Section

;******************************************************************************
;
;   VDD_State_Set_Latches_Owner
;
;   DESCRIPTION:
;
;   ENTRY:	    EBX = VM handle, or 0 if VDD will own latches
;		    EDI -> CRTC VDD CB data
;		    ESI -> MemC VDD CB data
;
;		    If EBX = 0, then EDI and ESI are ignored
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc VDD_State_Set_Latches_Owner

IFDEF DEBUG_verbose
	Mono_Out 'l',noeol
	call	VDD_State_VM_Debug
ENDIF
	push	eax
	mov	eax, ebx
	xchg	eax, [Vid_Latches_VM]
	TestMem [Vid_Flags], fVid_SR_Section	;Q: in SR section?
	jz	short slo_not_SR		;   N: old latches already saved
	or	eax, eax			;   Y: Q: old latches owned?
	jz	short slo_exit			;	  N: return
	bts	[Vid_Flags], bVid_SR_Latch_res	;	  Y: Q: first time?
	jc	short slo_exit			;		N: return
	push	ebx				;		Y: save latches
	push	edi
	push	esi
	mov	ebx, eax
	SetVDDPtr edi
	call	VDD_State_Save_Latches
	pop	esi
	pop	edi
	pop	ebx
	jmp	short slo_exit

slo_not_SR:
	or	ebx, ebx			;Q: assigning new owner?
	jz	short slo_exit			;   N: return
	cmp	ebx, eax			;Q: VM already ownes latches?
	je	short slo_exit			;   Y: return
	push	ebx				;   N: restore latches
	mov	ebx, edi
	sub	ebx, [Vid_CB_Off]
	call	VDD_State_Restore_Latches	; Restore latches
	pop	ebx
slo_exit:
	pop	eax
	ret

EndProc VDD_State_Set_Latches_Owner


;******************************************************************************
;
;   VDD_State_Clear_MemC_Owner
;
;   DESCRIPTION:    Zero Vid_MemC_VM to indicate that the MemC state isn't
;		    valid for a VM.  This is usually called when the VDD has
;		    modified the physical MemC state from a VM's virtual state
;		    when it is in the process of saving or restoring video
;		    pages.
;
;   ENTRY:	    none
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_State_Clear_MemC_Owner

	mov	[Vid_MemC_VM], 0
IFDEF DEBUG
	pushad
	mov	eax, [esp+SIZE Pushad_Struc]
	call	VDD_State_Schedule_Debug_Event
	popad
ENDIF
	ret

EndProc VDD_State_Clear_MemC_Owner


;******************************************************************************
;VDD_State_Set_MemC_Owner
;
;DESCRIPTION:
;	Modifies the video registers so that the indicated controller state
;	is the one that controls the memory access.  If the CRTC is currently
;	owned and CRTC owner=MemC owner, the CRTC/MemC state is saved first.
;	It is valid to set pseudo VM handles, such as message VM state.
;	If EBX is zero, this should only be transitory since the next call
;	to Set_CRTC_Owner will destroy any memory controller state set here.
;
;ENTRY: EBX = VM_Handle
;	EDI -> VDD CB data
;
;EXIT:	none
;
;USES:	Flags
;
;==============================================================================
BeginProc VDD_State_Set_MemC_Owner, PUBLIC

IFDEF DEBUG
	pushad
	mov	eax, [esp+SIZE Pushad_Struc]
	call	VDD_State_Schedule_Debug_Event
	popad
ENDIF

	pushad
IFDEF	DEBUG
	or	ebx,ebx
	jnz	SHORT VS_SMO_DBG0
Debug_Out "Set_MemC with zero handle?!"
VS_SMO_DBG0:
ENDIF
	cmp	ebx,[Vid_MemC_VM]		; Q: VM own MemC state?
	jz	VS_SMO_Exit			;   Y: do nothing
IFDEF DEBUG
	TestMem [Vid_Flags], fVid_SR_Section	;Q: in SR section?
	jz	short @F			;   N:
	Queue_Out "Set_MemC in SR #EBX"
	jmp	short VS_SMO_DBG01
@@:
	Queue_Out "Set_MemC #EBX"
VS_SMO_DBG01:
ENDIF
	cmp	[Vid_MemC_VM],0 		; Q: Any VM own MemC state?
	jz	SHORT VS_SMO_01 		;   N: No need to save regs
	cmp	ebx,[Vid_CrtC_VM]		; Q: This VM own CRTC?
	jz	SHORT VS_SMO_01 		;   Y: No need to save regs
	call	VDD_State_Save_CRTC_Owner	;   N: Save reg state first
VS_SMO_01:

;*******
;   Update I/O trapping for new MemC owner
;
	push	ebx
	push	edi
	push	[Vid_MemC_VM]
	mov	[Vid_MemC_VM],ebx		; Set new owner
	cmp	ebx,[Vid_Msg_Pseudo_VM] 	; Q: Pseudo VM handle?
	jz	SHORT VS_SMO_03 		;   Y: skip set trap
	TestMem [Vid_Flags], fVid_SR_Section	;Q: in SR section?
	jnz	short VS_SMO_03 		;   Y: skip set trap
	call	VDD_TIO_Set_Trap		; Update I/O trapping
VS_SMO_03:

;*******
; Adjust VM access to I/O ports and video pages for old MemC owner
;
	pop	ebx				; EBX = old MemC owner
	or	ebx,ebx 			; Q: Any VM own MemC before?
IFDEF DEBUG
	jnz	short @F
	Queue_Out 'no previous memc'
@@:
ENDIF
	jz	SHORT VS_SMO_04 		;   N: skip notification
	cmp	ebx,[Vid_Msg_Pseudo_VM] 	; Q: Pseudo VM handle?
IFDEF DEBUG
	jnz	short @F
	Queue_Out 'previous=psuedo'
@@:
ENDIF
	jz	SHORT VS_SMO_04 		;   Y: skip notification
	TestMem [Vid_Flags], fVid_SR_Section	;Q: in SR section?
	jnz	short VS_SMO_04 		;   Y: skip notification
	xor	eax,eax 			; Zero MemC VM in case Set_MemC
	xchg	eax,[Vid_MemC_VM]		;   is reentered
	push	eax				; Save new MemC owner
	SetVDDPtr edi
	cmp	ebx, [Vid_Latches_VM]		;Q: VM own latches?
	jne	SHORT VS_SMO_skip_save		;   N:
	call	VDD_State_Save_Latches		; Save old MemC owner latches
VS_SMO_skip_save:
Queue_Out 'Set MemC calling Mem Disable'
	call	VDD_VM_Mem_Disable		; Disable VM's video mem access
	pop	[Vid_MemC_VM]			; Restore new MemC owner
	call	VDD_TIO_Set_Trap		; Update I/O trapping
VS_SMO_04:
	pop	edi
	pop	ebx

;*******
; Set up pointers to register state structure then restore the state
;
	mov	esi,edi 			; ESI = VDD ptr for MemC state
	cmp	ebx,[Vid_CRTC_VM]		; Q: VM own CRTC state?
	jz	SHORT VS_SMO_05 		;   Y: Use same state
	mov	ebx,[Vid_CRTC_VM]		;   N: EBX = CRTC VM handle
	or	ebx,ebx 			;	Q: VDD own CRTC?
	jz	SHORT VS_SMO_05 		;	    N: Use MemC state
	SetVDDPtr edi				;	    EDI = CRTC owner ptr
VS_SMO_05:

;*******
;   Restore video registers
; EBX = VM handle for CRTC state owner (or 0 if VDD is owning CRTC state)
; ESI -> VDD data for MemC state owner
; EDI -> VDD data for CRTC state owner (or MemC owner if CRTC not owned by VM)
	cmp	ebx,[Vid_Msg_Pseudo_VM] 	; Q: Pseudo VM handle?
	jz	SHORT VS_SMO_06 		;   Y: Don't restore latches
	xor	eax,eax 			; Zero MemC VM in case Set_MemC
	xchg	eax,[Vid_MemC_VM]		;   is reentered
	push	eax				; Save new MemC owner
	push	ebx
	mov	ebx, esi
	sub	ebx, [Vid_CB_Off]
	call	VDD_State_Set_Latches_Owner
	pop	ebx
	pop	[Vid_MemC_VM]			; Restore new MemC owner
VS_SMO_06:
;;Debug_Out "Set_MemC #EBX, #ESI, #EDI"
IFDEF DEBUG_verbose
	Mono_Out '+',noeol
	push	ebx
	mov	ebx, esi
	sub	ebx, [Vid_CB_Off]
	call	VDD_State_VM_Debug
	pop	ebx
ENDIF
	call	VDD_State_Restore_Regs		; Restore the registers
	stc
	call	VDD_State_Restore_Index 	; Restore the MemC indexes
VS_SMO_Exit:
	popad
	ret
EndProc VDD_State_Set_MemC_Owner

;******************************************************************************
;VDD_State_Set_CRTC_Owner
;
;DESCRIPTION:
;	Modifies the video registers so that the indicated controller state
;	is the one that controls the display.  If the CRTC is currently owned,
;	the CRTC state is saved first.	If the VM handle is zero, the display
;	is turned off.	If EDI is also zero, the rest of the CRTC state is
;	not modified (this is a way to assign the CRTC state to nothing).
;	It is valid to set pseudo VM handles, such as message VM state.
;
;ENTRY: EBX = VM_Handle (or 0 if setting up to save/restore video memory)
;		    May be pseudo VM handle for message mode
;	EDI -> VDD CB data
;		(may be special ptr if video mem save/restore, where EBX=0)
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX
;
;==============================================================================
BeginProc VDD_State_Set_CRTC_Owner, PUBLIC

;;Trace_Out "Set_CRTC #EBX"
	pushad
	cmp	ebx,[Vid_CRTC_VM]		; Q: Already own CRTC?
	jz	VS_SCO_Exit			;   Y: Just exit

;
; This code is a hack to force the complete register state for the current
; CRTC owner to be read and saved.  See VDD_State_Save_CRTC_Owner for a
; more complete discussion of why this hack is necessary.
;
	mov	eax, [Vid_CRTC_VM]
	cmp	eax, [Vid_MemC_VM]		; Q: CRTC=MemC?
	je	short VS_SCO_00 		;   Y: save CRTC regs
	push	ebx
	push	edi
	mov	ebx, eax
	SetVDDPtr edi
	call	VDD_State_Set_MemC_Owner
	pop	edi
	pop	ebx
VS_SCO_00:

	call	VDD_State_Save_CRTC_Owner	;   Y: Save reg state first

;*******
; Set up pointers to register state structure then restore the state
;
	mov	esi,edi 			; ESI = VDD ptr
	cmp	ebx,[Vid_MemC_VM]		; Q: VM own MemC state?
	jz	SHORT VS_SCO_02 		;   Y: Use CRTC state
	cmp	[Vid_MemC_VM],0 		;   N: Q: Use current owner?
	jz	SHORT VS_SCO_02 		;	N: Use CRTC state
	mov	esi,[Vid_MemC_VM]		;	Y: ESI = MemC owner ptr
	add	esi,[Vid_CB_Off]
VS_SCO_02:
;;Debug_Out "Set_CRTC #EBX, #ESI, #EDI"

; EBX = VM handle for new CRTC state owner (or 0 if VDD is owning CRTC state)
; ESI -> VDD data for MemC state owner
; EDI -> VDD data for new CRTC state owner
IFDEF DEBUG_verbose
	Mono_Out 'C',noeol
	call	VDD_State_VM_Debug
ENDIF
	call	VDD_State_Restore_Regs		; Restore the registers
	cmp	ebx,[Vid_Msg_Pseudo_VM] 	; Q: Message mode pseudo VM?


;*******
;   Update I/O trapping for new CRTC owner
;
	push	[Vid_CRTC_VM]
	mov	[Vid_CRTC_VM],ebx		; Set new owner
						; Q: Message mode pseudo VM?
	jz	SHORT VS_SCO_04 		;   Y: Skip I/O trap and
						;	indexes update
	SetVDDPtr edi

	clc
	call	VDD_State_Restore_Index 	; Restore MemC and CRTC indexes
	call	VDD_TIO_Set_Trap		; Update I/O trapping
VS_SCO_04:

;*******
; Adjust VM access to I/O ports for old CRTC owner
;
	pop	ebx
IFDEF	DEBUG
	or	ebx,ebx 			; Q: Any VM own CRTC?
	jnz	SHORT VS_SCOD01
Debug_Out "Old CRTC value is ZERO!!"
VS_SCOD01:
	jz	SHORT VS_SCO_05 		;   N: No I/O trapping
ENDIF
	cmp	ebx,[Vid_Msg_Pseudo_VM] 	; Q: Pseudo VM handle?
	jz	SHORT VS_SCO_05 		;   Y: No I/O trapping
	SetVDDPtr edi
	call	VDD_TIO_Set_Trap		;   N: Update I/O trapping
VS_SCO_05:

; All done, return to caller
VS_SCO_Exit:
	popad
	ret
EndProc VDD_State_Set_CRTC_Owner


;******************************************************************************
;
;   VDD_State_Get_CRTC_Index_Port
;
;   DESCRIPTION:
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD CB data
;
;   EXIT:	    EDX = 3D4h or 3B4h	(pCRTCIndxColr or pCRTCIndxMono)
;
;   USES:	    EDX, Flags
;
;==============================================================================
BeginProc VDD_State_Get_CRTC_Index_Port

IFDEF	VGAMONO
	push	eax
	mov	edx,pMiscIn
	in	al,dx
	mov	dl,(pCRTCIndxColr AND 0FFh)
	test	al,1
	pop	eax
	jnz	SHORT @F
	mov	dl,(pCRTCIndxMono AND 0FFh)
@@:
ELSE
	mov	edx,pCRTCIndxColr
ENDIF
	ret

EndProc VDD_State_Get_CRTC_Index_Port


;******************************************************************************
;VDD_State_Restore_Regs
;
;DESCRIPTION:
;	Writes to the physical video registers.  If the handle in EBX is
;	different than the handle in [Vid_CRTC_Owner], does a CRTC reset.
;	The screen should be turned off before this happens!
;
;ENTRY: EBX = VM_Handle of VM getting CRTC state (= 0 if VDD)
;	ESI -> MemC owner VDD CB data
;	EDI -> CRTC owner VDD CB data
;
;EXIT:	none
;
;USES:	Flags
;
;==============================================================================
BeginProc VDD_State_Restore_Regs

	pushad

;;Trace_Out "Res_Regs #EBX" +
IFDEF DEBUG_verbose
      push    eax
      push    ebx
      mov     ebx,[Vid_CRTC_VM]
      mov     eax,[Vid_MemC_VM]
Queue_Out "restore regs #EBX #EAX"
      pop     ebx
      pop     eax
ENDIF

	call	VDD_State_Get_CRTC_Index_Port

;*******
; First only do registers that are part of CRTC state
	cmp	ebx,[Vid_CRTC_VM]		; Q: Changing CRTC owner?
	jz	VDD_State_Restore_MemC		;   N: Change MemC state only

IFDEF DEBUG
	ClrFlag [edi.VDD_Flags],fVDD_NeedRestore
ENDIF

	mov	dl,(pMisc AND 0FFh)
	mov	al,[edi.VDD_Stt.V_Misc]
	call	VDD_OEM_Pre_OUT_Misc
	jz	short @F
	out	dx,al				; Program misc output
@@:

	mov	dl,(pCRTCIndxColr AND 0FFh)	; Recalculate 3Bx or 3Dx
	test	al,1
	jnz	SHORT @F
	mov	dl,(pCRTCIndxMono AND 0FFh)
@@:

;*******
; Do OEM specific enabling.  For some hardware this may be changing
;   modes or display adapters.	If the display adapter is wholly restored
;   by this routine, return Carry Flag set and the rest of the CRTC and
;   MemC state will be aborted.
	call	VDD_OEM_CRTC_Enable
	jc	VSRR_Exit

;*******
; Sequencer and Miscellaneous output
	push	edx
	mov	dx,pSeqIndx
	cld
	xor	eax,eax
	out	dx,al
	IO_Delay
	inc	al				; enter sync reset
	inc	dl
	out	dx,al
	IO_Delay
	dec	dl

; program Clocking Mode
;;	mov	al, 1				; done above
	out	dx, al
	IO_Delay
	mov	al,[edi.VDD_Stt.S_ClMode]
	inc	dl
	out	dx, al
	IO_Delay

; program Char map select
	dec	dl
	mov	al, 3
	out	dx, al
	IO_Delay
	mov	al,[edi.VDD_Stt.S_ChMap]
	inc	dl
	out	dx, al
	IO_Delay

	mov	dl,(pGrpIndx AND 0FFh)
	mov	al,6
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[edi.VDD_Stt.G_Misc]
	out	dx,al
	IO_Delay

	xor	eax,eax
	mov	dl,(pSeqIndx AND 0FFh)
	out	dx,al
	IO_Delay
	mov	al,[edi.VDD_Stt.S_Rst]
	inc	dl				; restore sync reset state
	out	dx,al
	IO_Delay

	call	VDD_OEM_Restore_Seq

;*******
; CRT controller
	pop	edx
	or	ebp,-1				; Default is restore all CRTC

;*******
; Some OEMs require VGA extensions to be restored now
;   Note that EBP = CRTC register restore mask.  The OEM specific
;   restore routine may modify this mask to restore a subset of the
;   CRTC registers.  Bit 0 corresponds to the register with CRTC index 0.
;
; ESI -> MemC owner VDD data
; EDI -> new CRTC owner VDD data
; EBX = new CRTC owner handle (may be 0 if VDD is to own CRTC)
; EBP = -1 (mask for output of CRTC registers)
; DX = 3B4 or 3D4
; enable access CRTC
	mov	al, 11h
	out	dx, al
	IO_Delay
	inc	edx
	in	al, dx
	IO_Delay
	and	al, 7Fh
	out	dx, al
	IO_Delay
	dec	edx

	call	VDD_OEM_Pre_Restore_CRTC	; Restore OEM state, set up
						;   for CRT controller restore
	cld
	push	esi
	lea	esi, [edi.VDD_Stt]
.ERRE	(C_HTotal EQ 0) AND (CRTC EQ 0)

        mov	ecx,C_LnCmp-C_HTotal+1

	xor	eax,eax
	call	VDD_State_OutC_Ctrlr		      ; Program CRTC cond'l on EBP
	pop	esi

;*******
; Some OEMs require additional VGA extensions to be restored after CRTC restore
;
; ESI -> MemC owner VDD data
; EDI -> new CRTC owner VDD data
; EBX = new CRTC owner handle (may be 0 if VDD is to own CRTC)
; DX = 3B4 or 3D4

	call	VDD_OEM_Post_Restore_CRTC	; Restore OEM state, set up
						;   for CRT controller restore

IF 0
;
; pause for a few retrace cycles to allow the screen to re-sync
;
PUBLIC VSRR_sync_delay_lp
	mov	ecx, 5
VSRR_sync_delay_lp:
	push	ecx
	mov	ecx,8000h
@@:	in	al,dx
	test	al,fStatVRTC
	loopz	@B
	mov	ecx,8000h		    ; retrace started
@@:	in	al, dx
	test	al,fStatVRTC
	loopnz	@B
	pop	ecx			    ; retrace ended
	loop	VSRR_sync_delay_lp
ENDIF


;*******
; Some OEMs require VGA extensions to be restored now
;
;   Note that EBP = ATTR register restore mask.  The OEM specific
;   restore routine may modify this mask to restore a subset of the
;   ATTR registers.  Bit 0 corresponds to the register with CRTC index 0.
;
; ESI -> MemC owner VDD data
; EDI -> new CRTC owner VDD data
; EBX = new CRTC owner handle (may be 0 if VDD is to own CRTC)
; EBP = 0FFFFFFFFh (mask for output of ATTR registers 32 registers)
; DX = 3B4 or 3D4
	or	ebp,-1
	push	edx
	add	edx, pStatColr-pCRTCIndxColr
.errnz (pStatMono-pCRTCIndxMono) - (pStatColr-pCRTCIndxColr)
	call	VDD_OEM_Pre_Restore_ATTR	; Restore OEM state, set up
						;   for ATTR restore
	push	esi
	lea	esi,[edi.VDD_Stt.A_Pal]
	mov	ecx,32			;[enough to get TLI's ATC 16,17]
	xor	ah,ah
        cld
VSRR_Attr0:
	lodsb					; Get a value
	shr	ebp,1				; Q: Program this register?
	jnc	SHORT VSRR_Attr1		;   N: next
	xchg	ah,al
	call	VDD_State_Attr_Out		;   Y: Program it
	xchg	ah,al
VSRR_Attr1:
	inc	ah				; next register index
	loopd	VSRR_Attr0			; Program next attribute
	pop	esi
	xchg	edx,[esp]			; Restore EDX=3D4 or 3B4

	call	VDD_VGA_Restore_DAC		; Restore the DAC

; Some OEMs require VGA extensions to be restored after programming ATTR ctlr
	xchg	edx,[esp]			; Restore EDX=3DA or 3BA
	call	VDD_OEM_Post_Restore_Attr
	pop	edx				; Restore EDX=3D4 or 3B4

;*******
; Registers specific to CRTC state have been restored.	Now restore the
;   MemC state registers and the mixed registers
PUBLIC VDD_State_Restore_MemC
VDD_State_Restore_MemC:
	push	esi
	push	edi
	push	edx
	call	VDD_OEM_Pre_Restore_MemC
	lea	edi,[edi.VDD_Stt]		; EDI = VDD_Stt ptr for CRTC
	lea	esi,[esi.VDD_Stt]		; ESI = VDD_Stt ptr for MemC

	mov	dl,(pSeqIndx AND 0FFh)
;*******
; Restore Sequencer write mask
	mov	al,02h
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.S_Mask]
	out	dx,al
	IO_Delay
	dec	edx

;*******
; Restore Sequencer memory mode
	mov	al,04h
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.S_MMode]
	mov	ah,[edi.S_MMode]
	and	ax,01FEh			; strip CRT font select bit
	or	al,ah				; Add bit from CRTC VM
	out	dx,al
	IO_Delay

;*******
; pass through Set/Reset
;
	mov	dl,(pGrpIndx AND 0FFh)
	mov	al,0
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.G_SetRst]
	out	dx,al
	IO_Delay
	dec	edx

;*******
; pass through enable Set/Reset
;
	mov	al,1
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.G_SREna]
	out	dx,al
	IO_Delay
	dec	edx

;*******
; pass through Color Compare
;
	mov	al,2
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.G_CComp]
	out	dx,al
	IO_Delay
	dec	edx

;*******
; pass through Raster OP function
;
	mov	al,3
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.G_Func]
	out	dx,al
	IO_Delay
	dec	edx

;*******
; pass through Read Map Select
;
	mov	al,4
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.G_MSlct]
	out	dx,al
	IO_Delay
	dec	edx

;*******
; Preserve Mode Odd/Even bits bit from CRTC VM
;
	mov	al,5
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.G_Mode]
	mov	ah,[edi.G_Mode]
	and	ax,609Fh			; Preserve CRTC Shift bit
						;   and Shift 256 bit
	or	al,ah
	out	dx,al
	IO_Delay
	dec	edx

;*******
; Preserve Misc. Text/Graphics bit from CRTC VM
;
;   NOTE:  This register was programmed above with the correct CRTC state for
;	   bit 0 under sync reset, if CRTC changed, so we don't need to worry
;	   about the bit changing here.
;
	mov	al,6
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.G_Misc]
	mov	ah,[edi.G_Misc]
	and	ax,01FEh			; strip odd/even bits bit
						; Add in bit from focus VM
	or	al,ah
	out	dx,al
	IO_Delay
	dec	edx

;*******
; pass through Color Don't Care
;
	mov	al,7
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.G_DCare]
	out	dx,al
	IO_Delay
	dec	edx

;*******
; pass through bit mask
;
	mov	al,08h
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.G_Mask]
	out	dx,al
	IO_Delay

;*******
; program MemC bits 1 & 5 in misc output register
;
;   NOTE:  This register was programmed above with the correct CRTC state for
;	   bits 2 & 3 under sync reset, if CRTC changed, so we don't need to
;	   worry about those bits changing here.
;
	mov	dl,(pMisc AND 0FFh)
	mov	al,[edi.V_Misc]
	mov	ah,[esi.V_Misc]
	and	ax, 22DDh			; merge MemC bits 1 & 5
	or	al, ah
	call	VDD_OEM_Pre_OUT_Misc
	jz	short @F
	out	dx,al				; Program misc output
@@:

;*******
; Do OEM specific MemC restoring
;
	pop	edx
	pop	edi				; EDI = CRTC VM VDD ptr
	pop	esi				; ESI = MemC VM VDD ptr
	call	VDD_OEM_Post_Restore_MemC

;*******
; Do MemC modifications, if any
;
	TestMem [esi.VDD_Flags], fVDD_MemCmods
	jz	short VSRR_Exit
	movzx	ecx, [esi.VDD_MemC_ModCnt]
	jecxz	VSRR_Exit
	lea	edi, [esi.VDD_MemC_Mods]
VSRR_do_mods:
	test	[edi.MMS_flags], fMMS_OEM_extension
	jnz	short VSRR_next_mod
	mov	dx, [edi.MMS_data_port]
	test	[edi.MMS_flags], fMMS_no_index
	jnz	short VSRR_no_index
	dec	dl
	mov	al, [edi.MMS_index]
	out	dx, al
	IO_Delay
	inc	dl
	jmp	short VSRR_mod_data
VSRR_no_index:
IFNDEF CTVGA
	cmp	dx, pMisc
	jne	short VSRR_mod_data
	add	dl, pMiscIn-pMisc
	in	al, dx
	sub	dl, pMiscIn-pMisc
	and	al, [edi.MMS_ANDmask]
	or	al, [edi.MMS_ORmask]
	call	VDD_OEM_Pre_OUT_Misc
	jz	short VSRR_next_mod
	jmp	short VSRR_out_value
ELSE
.err how do we read miscellaneous output on CTVGA
ENDIF
VSRR_mod_data:
	in	al, dx
	IO_Delay
	and	al, [edi.MMS_ANDmask]
	or	al, [edi.MMS_ORmask]
VSRR_out_value:
	out	dx, al

VSRR_next_mod:
	add	edi, SIZE MemC_Mod_Struc
	loop	VSRR_do_mods

VSRR_Exit:
	popad
	ret

EndProc VDD_State_Restore_Regs


;******************************************************************************
;VDD_State_Attr_Out
;
;DESCRIPTION:
;	Outputs to Attribute controller
;
;ENTRY: AL  = controller index
;	AH  = controller value
;	DX = 3BA or 3DA (indicating mono or color mode)
;
;EXIT:	none
;
;USES:	Flags
;
;==============================================================================
BeginProc VDD_State_Attr_Out

	push	edx
	push	eax
	in	al, dx				; Reset address toggle
	IO_Delay
	pop	eax

	mov	dl,(pAttr AND 0FFh)
	out	dx,al
	IO_Delay
	xchg	al,ah
	out	dx,al
	xchg	al,ah
	pop	edx
	ret
EndProc VDD_State_Attr_Out

;******************************************************************************
;VDD_State_OutC_Ctrlr
;
;DESCRIPTION:
;	Outputs to video registers in sequence conditionally on bits in EBP
;
;ENTRY: AH  = controller index
;	ECX = number of registers
;	DX = controller port
;	EBP = controller port index bit mask
;	ESI = controller registers values ptr
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, ESI
;
;==============================================================================
BeginProc VDD_State_OutC_Ctrlr, PUBLIC

        cld
VDD_PSc0:
	lodsb
	shr	ebp,1
	jnc	SHORT VDD_PSc1
	xchg	ah,al
	out	dx,al				; Set index register
	IO_Delay
	xchg	ah,al
	inc	dl
	out	dx,al				; Set data register
	dec	dl
VDD_PSc1:
	inc	ah
	loopd	VDD_PSc0
	ret
EndProc VDD_State_OutC_Ctrlr

;******************************************************************************
;
;   VDD_State_Get_Screen_Start
;
;   DESCRIPTION:    Get screen start address in EAX
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VM's VDD_CB_Struc
;
;   EXIT:	    EAX = screen start address
;
;   USES:	    EAX, flags
;
;==============================================================================
BeginProc VDD_State_Get_Screen_Start

	movzx	eax,WORD PTR [edi.VDD_Stt.C_AddrH]
	xchg	ah,al			    ; EAX = screen offset
	clc
	call	VDD_OEM_Adjust_Screen_Start ; Do OEM specific adjust
	jc	SHORT gvp_01
	test	[edi.VDD_Stt.C_UndrLn],40h  ; Q: DWORD mode?
	jz	SHORT gvp_00		    ;	N: continue
	lea	eax,[eax*4]		    ;	Y: Shift offset by 4
	jmp	SHORT gvp_01
gvp_00:
	test	[edi.VDD_Stt.C_Mode],40h    ; Q: WORD mode?
	jnz	SHORT gvp_01		    ;	N: continue
	add	eax,eax 		    ;	Y: Shift offset by 2
gvp_01:
	ret
EndProc VDD_State_Get_Screen_Start

;******************************************************************************
;
;   VDD_State_Get_Dimensions, VDD_State_Get_Display_Dimensions
;
;   DESCRIPTION:    Get row & column dimensions for a VM's display.  It returns
;		    values in # of characters for text modes, and # of pixels
;		    for graphics modes.  It also returns with the Carry flag
;		    set to indicate that the VM's display is in graphics mode.
;		    Get_Display_Dimensions returns the size of the display and
;		    Get_Dimensions returns the size of the memory used.
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VM's VDD_CB_Struc
;
;   EXIT:	    EAX = # of rows
;		    ECX = # of columns
;		    Carry set, if in a graphics mode
;
;   USES:	    EAX, ECX, flags
;
;==============================================================================
BeginProc VDD_State_Get_Display_Dimensions

	movzx	eax, [edi.VDD_Stt.CRTC.C_HDisp]
	inc	eax
	jmp	SHORT gd_00


BeginProc VDD_State_Get_Dimensions

	movzx	eax, [edi.VDD_Stt.CRTC.C_LnOff]

IFDEF	PVGA
; Make more room for PVGA mode 5Ah & 5Bh.  Register 3x4.13 return weird 
; values for these modes.			- C. Chiang -
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short gdd_not_pvga
	cmp	eax, 20h
	jnz 	short gdd_not_pvga
	shl	eax, 1
gdd_not_pvga:
ENDIF	; PVGA

	shl	eax, 1		    ; offset is always half of actual

	mov	cl, [edi.VDD_Stt.CRTC.C_Mode]
	test	cl, 00001000b	    ;Q: count by 2?
	jz	short gvp_got_horiz ;	N:
	shl	eax, 1		    ;	Y: double offset value
IFDEF TLVGA
	TestMem [edi.VDD_TFlags],fVT_TL_ET4000	    ;if ET4000
	jz	short gvp_got_horiz
;if ET4000 and both CRTC 17 bit 3=1 and CRTC 14 bit 5=1, halve offset
	test	[edi.VDD_Stt.CRTC.C_UndrLn],020h
	jz	short gvp_got_horiz
	shr	eax,2		    ; Divide by 4 to get to half
ENDIF
gvp_got_horiz:

gd_00:
	push	edx
	push	eax
	movzx	eax, [edi.VDD_Stt.CRTC.C_VDspEnd]
	mov	cl, [edi.VDD_Stt.CRTC.C_Ovflw]
	shr	cl, 2		    ; retrieve bit8 of VDspEnd, from bit1 of
	adc	ah, 0		    ; of Overflow register

	shr	cl, 3
	and	cl, 10b 	    ; retrieve bit9 of VDspEnd, from bit6 of
	or	ah, cl		    ; of Overflow register

	inc	eax		    ; # of vertical lines

	mov	cl, [edi.VDD_Stt.CRTC.C_Mode]
	test	cl, 100b	    ;Q: multiply vertical by 2?
	jz	short gvp_single    ;	N:
	shl	eax, 1		    ;	Y:
gvp_single:
	mov	edx, eax	    ; edx = vertical display total

	mov	cl, [edi.VDD_Stt.CRTC.C_CharHgt]
	test	cl, 10000000b	    ;Q: double scan?
	jz	short gvp_not_dblscan ; N:
	shr	edx, 1		    ;	Y: divide vert dsp total by 2
gvp_not_dblscan:
	pop	eax

IFDEF TLVGA
%OUT What is this register??
;;;	TestMem [edi.VDD_TFlags],fVT_TLVGA	    ;if ET3000
;;;	jz	short gvp_tl_4
;;;	;if ET3000 and interlace, double vert dsp total
;;;	test	[edi.VDD_Stt.CRTC.C_Htotal+025h],080h
;;;	jz	short gvp_tl_2
;;;	shl	edx,1
gvp_tl_2:
%OUT really ET4000!?
	TestMem [edi.VDD_TFlags],fVT_TL_ET4000	    ;if ET3000
	jz	short gvp_tl_4
	;if ET3000 and hires, double offset
	test	[edi.VDD_Stt.A_Pal+016h],010h
	jz	short gvp_tl_4
	shl	eax,1
gvp_tl_4:
ENDIF

	test	[edi.VDD_Stt.G_Misc], fGrp6Char ;Q: graphics mode?
	jz	short gvp_text			;   N: text

gvp_graphics:

IFDEF	PVGA
	TestMem [edi.VDD_TFlags],fVT_PVGA
	jz	short pvga_not_768
; Check for Western Digital 768 vertical resolution and set vertical 
; line total to actual size for 5Ah, 5Bh, 5Dh and 60h.	- C. Chiang -
	cmp	edx, 384
	jnz	short pvga_not_768
	shl	edx,1
pvga_not_768:
ENDIF	;PVGA

;
; final calculations for graphics mode
;	edx = vert total (row blocks), eax = horiz total (chars)
;

	mov	cl, [edi.VDD_Stt.CRTC.C_Mode]
	test	cl, 00000001b	    ;Q: CGA compatible mode?
	jnz	short gvp_not_CGA   ;	N:
	shl	edx, 1		    ;	Y: double logical dsp hgt
gvp_not_CGA:
	movzx	ecx, [edi.VDD_Stt.CRTC.C_CharHgt]
	and	cl, 00011111b	    ; isolate block height
	jz	short gvp_hgt_1     ; jump, if height = 1
	inc	ecx
	push	eax
	mov	eax, edx
	xor	edx, edx
	div	ecx
	mov	edx, eax
	pop	eax
gvp_hgt_1:
	mov	cl, [edi.VDD_Stt.A_Mode]
	test	cl, 40h 	    ;Q: half speed clocking?
	jz	short gvp_not_half  ;	N:

IFDEF	PVGA
	TestMem [edi.VDD_TFlags],fVT_PVGA
	jz	SHORT gvp_not_PVGA
	; 256-color modes come in here
	; if 3ce.0e bit 0 == 1 => WDC 256-color mode 5Ch, 5Eh, 5Fh and 60h
	; else standard 256-color mode 13h	 	- C. Chiang -
	test	[edi.VDD_Stt.G_PVGA4],1		; Q: WDC 256-color modes?
	jnz	short gvp_not_half		;    Y :
gvp_not_PVGA:					;    N : must be mode 13h
ENDIF	;PVGA

	shr	eax, 1		    		;    N: divide horiz total by 2
gvp_not_half:
	mov	cl, [edi.VDD_Stt.S_ClMode]
	test	cl, fSeq1DPCh	    ;Q: 8 or 9 dots char width?
	mov	ecx, eax
	jz	short gvp_9dots     ;	9: ecx = eax
	xor	ecx, ecx	    ;	8: ecx = 0
gvp_9dots:
	shl	eax, 3		    ; eax = eax * 8
	add	ecx, eax	    ;	9: ecx = eax * 8 + eax = eax * 9
				    ;	8: ecx = eax * 8 + 0   = eax * 8
	mov	eax, edx
	stc			    ; flag as graphics mode
	jmp	short gvp_exit

;
; final calculations for text mode
;	edx = vert total (pixels), eax = horiz total (chars)
;
gvp_text:
	movzx	ecx, [edi.VDD_Stt.CRTC.C_CharHgt]
	and	cl, 00011111b
	cmp	cl, 2		    ;Q: small cell height?
	jbe	gvp_graphics	    ;	Y: assume graphics mode
	inc	ecx
	xchg	eax, edx
	push	edx		    ; save # of columns
	xor	edx, edx
	div	ecx		    ; eax = # of rows
	pop	ecx		    ; ecx = # of columns
	clc			    ; flag as text mode

gvp_exit:
	pop	edx
	ret

EndProc VDD_State_Get_Dimensions
EndProc VDD_State_Get_Display_Dimensions

IFDEF	VRTCTIMER
;******************************************************************************
;VDD_State_Calc_Framerate
;
;DESCRIPTION:
;	This routine calculates the framerate based on the CRTC and Misc
;	registers, and updates VDD_Framerate and VDD_Framerate_Recip
;	accordingly.
;
;ENTRY: EBX = running VM handle
;	EDI -> VDD CB data
;
;EXIT:	AL = framerate (Hz)
;	AH = millieseconds per frame
;
;USES:	Flags, EAX
;
;==============================================================================
BeginProc VDD_State_Calc_Framerate, PUBLIC

	push	ecx
	push	edx
	mov	eax,(16*100h)+60; default to 60fps, 16 ms per frame
	or	ebx,ebx
	jz	SHORT VS_CFR_Exit

	; cancel any pending time-out since we're recalculating the framerate
	call	VDD_Clr_VRTC_Time_Out

	movzx	ecx, [edi.VDD_Stt.V_Misc]
	and	ecx, fMiscDot
	mov	eax, [ecx+DotClockTable]

	movzx	ecx, [edi.VDD_Stt.C_HTotal]
	add	ecx, 5		; for some reason, C_HTotal is HTotal-5
	mov	dl, [edi.VDD_Stt.S_ClMode]
	test	dl, fSeq1DPCh	; Q: 8 or 9 dots char width?
	mov	edx, ecx
	jz	short @F	;   9: edx = ecx
	xor	edx, edx	;   8: edx = 0
@@:	lea	ecx,[edx+ecx*8]

	cdq
	jecxz	VS_CFR_BadState	; some BIOSes may set HTotal to 0 in modeset...
	div	ecx		; EAX := horiz refresh rate

	movzx	ecx, [edi.VDD_Stt.C_VTotal]
	mov	ch, [edi.VDD_Stt.CRTC.C_Ovflw]
	mov	dl, ch
	and	ch, 1		; retrieve bit8 of VTotal, from bit0 of Ovflw
	shr	dl, 5-1
	and	dl, 2		; retrieve bit9 of VTotal, from bit5 of Ovflw
	or	ch, dl
	test	[edi.VDD_Stt.C_Mode],4
	jz	short @F
	shl	ecx,1		; divide scan line clock by 2 --> double scanlines
@@:	cdq
	jecxz	VS_CFR_BadState	; some BIOSes set VTotal to 0 in modeset...
	div	ecx		; EAX := vertical refresh rate

	; Now AL is hopefully the framerate in Hz. We divide 1000 by AL to get
	; milliseconds per frame, and stuff that into AH, then update the state
	; structure accordingly.
	test	ah,ah		; Q: Framerate > 255?
	jz	short @F	;    N: keep going
	xor	ax,ax		;    Y: too fast, abandon calculation
	jmp	short VS_CFR_Update_State

@@:	mov	cl,al
	mov	ax,1000
	cmp	ah,cl		; Q: divide will overflow?
	jb	short @F	;    N: keep going
	xor	ax,ax		;    Y: too slow, abandon calculation
	jmp	short VS_CFR_Update_State

@@:	div	cl
	mov	ah,al		; milliseconds per frame in AH
	mov	al,cl		; fps in AL

VS_CFR_Update_State:
	; update both bytes in one fell swoop
	.errnz	VDD_Framerate_Recip-VDD_Framerate-1
	mov	word ptr [edi.VDD_Framerate],ax

VS_CFR_Exit:
	pop	edx
	pop	ecx
	ret

VS_CFR_BadState:
	; here ECX == 0, and we want AX == 0
	mov	eax,ecx
	jmp	short VS_CFR_Exit

VxD_DATA_SEG
DotClockTable label	dword	; clock select bits
		dd	25175000;     00 (IBM)
		dd	28322000;     01 (IBM)
		dd	39000000;     10 (Genoa SuperEGA)
		dd	26824000;     11 (Genoa SuperEGA)
VxD_DATA_ENDS

EndProc VDD_State_Calc_Framerate
ENDIF	;VRTCTIMER


;******************************************************************************
;VDD_State_Scrn_On
;
;DESCRIPTION:
;	turns on CRT
;
;ENTRY: EBX = VM_Handle
;
;EXIT:	none
;
;USES:	Flags, EAX
;
;==============================================================================
BeginProc VDD_State_Scrn_On, PUBLIC

%OUT what about using Seq.1 bit 5 instead?
	push	ebx
	push	edx
	push	edi
IFDEF	VGAMONO
	mov	dx,pMiscIn
	in	al,dx
	mov	dl,(pStatColr AND 0FFh) 	; Assume color port addr(3Dx)
	test	al,1
	jnz	SHORT VS_On_00
	mov	dl,(pStatMono AND 0FFh)
VS_On_00:
ELSE
	mov	dx,pStatColr			; Assume color port addr(3Dx)
ENDIF
	in	al,dx				; Set attribute reg to index
	push	edx
	IO_Delay
	mov	dl,(pAttr AND 0FFh)
	mov	ebx,[Vid_CRTC_VM]
	in	al,dx				; Get current index
	or	al,fVAI_ScOn			; Set bit to turn on display
	test	ebx,ebx 			; Q: Any VM own CRTC?
	jz	SHORT VS_On_01			;   N: don't save index
	cmp	ebx, [Vid_Msg_Pseudo_VM]	; Q: Message pseudo VM
	jz	SHORT VS_On_01			;   Y: don't save index
	SetVDDPtr edi

	ClrFlag [Vid_Flags], fVid_DOff
	push	edx
	call	VDD_TIO_Set_Trap		; disable trapping, if possible
	pop	edx
	ClrFlag [edi.VDD_Flags], fVDD_AXRd
	mov	al,[edi.VDD_Stt.A_Indx]
	test	[edi.VDD_Stt.A_Indx],fVAI_Indx
VS_On_01:
	out	dx,al				; Turn on the video
	IO_Delay
	pop	edx
	jz	SHORT VS_On_02
	in	al,dx
VS_On_02:
	pop	edi
	pop	edx
	pop	ebx
	ret
EndProc VDD_State_Scrn_On


;******************************************************************************
;VDD_State_Scrn_Off
;
;DESCRIPTION:
;	turns off CRT
;
;ENTRY: EBX = VM_Handle
;
;EXIT:	none
;
;USES:	Flags, EAX
;
;==============================================================================
BeginProc VDD_State_Scrn_Off, PUBLIC
	push	ebx
	push	edx
	push	edi

	call	VDD_State_Blank_Screen		; Turn off the video

	mov	ebx,[Vid_CRTC_VM]
	test	ebx,ebx 			; Q: Any VM own CRTC?
	jz	SHORT VSO_01			;   N: Nothing to save
	cmp	ebx, [Vid_Msg_Pseudo_VM]	; Q: Message pseudo VM
	je	SHORT VSO_01			;   Y: don't read the index
	bts	[Vid_Flags],bVid_DOff		; Q: Already turned off?
	jc	SHORT VSO_01			;   Y: don't read the index
	SetVDDPtr edi
	bts	[edi.VDD_Flags],bVDD_AXRd	; Q: Index already saved?
	jc	SHORT VSO_00			;   Y: Don't save again
	and	[edi.VDD_Stt.A_Indx],fVAI_Indx
	and	al,NOT fVAI_Indx
	or	[edi.VDD_Stt.A_Indx],al 	; Save it, preserving fVAI_Indx
VSO_00:
	call	VDD_State_Save_CRTC_Owner	; read current reg state
	push	edx
	call	VDD_TIO_Set_Trap		; enable trapping
	pop	edx
VSO_01:
	pop	edi
	pop	edx
	pop	ebx
	ret

EndProc VDD_State_Scrn_Off


;******************************************************************************
;
;   VDD_State_Blank_Screen
;
;   DESCRIPTION:    Blank the screen by clear bit 5 of the attribute controller
;		    index register.
;
;   ENTRY:	    none
;
;   EXIT:	    AL = old attribute index
;
;   USES:	    EAX, EDX, Flags
;
;==============================================================================
BeginProc VDD_State_Blank_Screen

IFDEF	VGAMONO
	mov	dx,pMiscIn
	in	al,dx
	mov	dl,(pStatColr AND 0FFh) 	; Assume color port addr(3Dx)
	test	al,1
	jnz	SHORT VSO_0
	mov	dl,(pStatMono AND 0FFh)
VSO_0:
ELSE
	mov	dx,pStatColr			; Assume color port addr(3Dx)
ENDIF
	in	al,dx				; Set attribute reg to index
	IO_Delay
	mov	dl,(pAttr AND 0FFh)
	in	al, dx
	mov	ah, al
	xor	al, al
	out	dx, al
	mov	al, ah
	ret

EndProc VDD_State_Blank_Screen


;******************************************************************************
;VDD_State_Restore_Index
;
;DESCRIPTION:
;	Restores video index registers.  It will leave the video off if the
;	fVid_DOff bit is set in Vid_Flags, regardless of the virtual machine's
;	display state.	Note that the some of the index registers are owned
;	by the MemC state and some by the CRTC state.  Specifically, the
;	CRTC and Attribute controller indexes are owned by CRTC and the
;	Sequencer and Graphics controller indexes are owned by the MemC.
;
;ENTRY: EBX = VM_Handle of CRTC owner
;	EDI -> CRTC owner VDD CB data
;	ESI -> MemC owner VDD CB data
;	If Carry set, only do MemC indexes (i.e. not CRTC or Attribute indexes)
;
;EXIT:	None
;
;USES:	Flags, EAX
;
;==============================================================================
BeginProc VDD_State_Restore_Index, PUBLIC

	push	edx
	mov	dx,pGrpIndx
	mov	al,[esi.VDD_Stt.G_Indx]
	out	dx,al				; Update Graphics ctrlrs index
	IO_Delay

	mov	dl,(pSeqIndx AND 0FFh)
	mov	al,[esi.VDD_Stt.S_Indx]
	out	dx,al				; Update Sequencer index reg.
	IO_Delay
	jc	SHORT VS_RI_NotCRTC

	call	VDD_State_Get_CRTC_Index_Port	; edx=CRTC index
	mov	al,[edi.VDD_Stt.C_Indx]
	out	dx,al				; Update CRTC index
	IO_Delay

	add	edx, pStatColr-pCRTCIndxColr
.errnz (pStatMono-pCRTCIndxMono) - (pStatColr-pCRTCIndxColr)
	in	al,dx				; Reset Attr index/reg toggle
	IO_Delay
	mov	al,[edi.VDD_Stt.A_Indx]
	and	al,mx_Attr			; assume leave video off
	push	edx
	mov	dl,(pAttr AND 0FFh)
	test	[edi.VDD_Stt.A_Indx],fVAI_ScOn
	jz	SHORT Dspy_Off			;   Y: leave video off
	TestMem [Vid_Flags],fVid_DOff		; Q: Globally turned off?
	jnz	SHORT Dspy_Off			;   Y: leave video off
	or	al,fVAI_ScOn			;   N: turn video on
Dspy_Off:
	out	dx,al
	IO_Delay
	pop	edx
	test	[edi.VDD_Stt.A_Indx],fVAI_Indx	; Q: ctrlr expecting data?
	jz	SHORT Dspy_On_1 		;   Y: Leave ctrlr rdy for data
	in	al,dx				;   N: leave ctrlr rdy for index
	IO_Delay
Dspy_On_1:

	ClrFlag [edi.VDD_Flags], fVDD_AXRd	; Attribute index reg restored

IFDEF Handle_VGAEnable
;*******
; Restore VGA enable bit
	mov	al,[esi.VDD_STT.V_VGAEna]
	call	VDD_OEM_Get_VGAEnaPort
	out	dx,al
ENDIF	;Handle_VGAEnable

VS_RI_NotCRTC:

	pop	edx
	ret

EndProc VDD_State_Restore_Index


;******************************************************************************
;
;   VDD_State_Modify_VMs_MemC
;
;   DESCRIPTION:    Used by VDDPHMEM to modify a VM's MemC state.  It is
;		    often necessary to change the memory mapping to allow
;		    a VM access to a video page that is not within its
;		    address range.  This routine can be used to change
;		    the mapping of text at B8h to A0h, or for changing the
;		    "banking" of SuperVGA cards which have more than 256Kb
;		    of video memory.
;
;   ENTRY:	    EBX = VM handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_State_Modify_VMs_MemC

IFDEF	DEBUG
	or	ebx, ebx
	jz	SHORT VS_VMV_DBG0
	Assert_VM_Handle EBX
	cmp	ebx, [Vid_MemC_VM]
	jz	SHORT VS_VMV_DBG0
	cmp	[Vid_MemC_VM], 0
	je	SHORT VS_VMV_DBG0
Trace_Out "Modify_VMs_MemC when VM is not MemC owner #EBX"
VS_VMV_DBG0:
ENDIF

;*******
; adjust VM access to I/O ports
;
	TestMem [Vid_Flags], fVid_SR_Section	;Q: in SR section?
	jnz	short VS_MVM_00 		;   Y: skip set_trap
	pushad
	call	VDD_TIO_Set_Trap		; enable trapping
	popad
VS_MVM_00:
	ret

EndProc VDD_State_Modify_VMs_MemC


;******************************************************************************
;VDD_State_Set_MemC_Planar
;
;DESCRIPTION:
;	Programs registers that affect CPU addressing, ready for saving or
;	restoring the video memory in 4 planar fashion.  This is done by
;	passing a mode 10h state to Restore_Regs that was saved during init.
;	After this routine, the VDD will own the MemC state.
;
;ENTRY: none
;
;EXIT:	If carry flag set, Planar mode not initialized
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_State_Set_MemC_Planar, PUBLIC

IFDEF DEBUG
;;Trace_Out "Set_Plan #EBX"
VxD_DATA_SEG
PUBLIC	last_set_planar_caller
last_set_planar_caller	dd  0
VxD_DATA_ENDS

	xchg	eax, [esp]
	mov	[last_set_planar_caller], eax
	xchg	eax, [esp]
ENDIF
	call	VDD_State_Save_CRTC_Owner	; Save CRTC VM state

;*******
; Clear MemC_VM and adjust VM access to I/O ports for old MemC owner
;
	push	ebx
	push	edi
	xor	ebx,ebx
	xchg	ebx,[Vid_MemC_VM]		; EBX = old MemC owner
	or	ebx, ebx			; Q: Any previous VM
	jz	SHORT VS_SMP_01 		;   N: No I/O trapping changes
	cmp	ebx, [Vid_Msg_Pseudo_VM]	;   Y: Q: Message pseudo VM?
	jz	SHORT VS_SMP_01 		;	Y: No I/O trap changes
	TestMem [Vid_Flags], fVid_SR_Section	;Q: in SR section?
	jnz	short VS_SMP_01 		;   Y: No I/O trap changes
	SetVDDPtr edi				;	N: Update I/O trapping
	cmp	ebx, [Vid_Latches_VM]		;Q: VM own latches?
	jne	short VS_SMP_00 		;   N:
	call	VDD_State_Save_Latches		;	  and save old latches
VS_SMP_00:
	VMMCall Test_Cur_VM_Handle
	je	short @F
	Queue_Out 'set planar calling Mem Disable'
	call	VDD_VM_Mem_Disable
@@:
	call	VDD_TIO_Set_Trap
VS_SMP_01:
	TestMem [Vid_Flags],fVid_PlanarInit
	jz	SHORT VS_SMP_02
	mov	ebx,[Vid_CRTC_VM]
	SetVDDPtr edi				;   Y: Use CRTC VM state
	mov	esi,OFFSET32 Vid_Planar_Pseudo_CB ; ESI = planar state

; EBX = CRTC_VM handle
; ESI -> VDD data for MemC state owner
; EDI -> VDD data for CRTC state owner
;;Debug_Out "Set_Plan #EBX, #ESI, #EDI"
IFDEF DEBUG_verbose
	Mono_Out '-',noeol
ENDIF
;TLVGA note: For the ET3000, we want here ATC 16 bit 4 to be unchanged, since
; otherwise we won't be able to access the memory right; this should be true,
; since VDD_State_Restore_Regs doesn't change ATC regs if CRTC owner isn't
; changing. (We also need ATC 10 bit 6=0 but that should be true here.)
	call	VDD_State_Restore_Regs		; Restore the registers
VS_SMP_02:
	pop	edi
	pop	ebx

IFDEF DEBUG
	pushad
	mov	eax, [esp+SIZE Pushad_Struc]
	call	VDD_State_Schedule_Debug_Event
	popad
ENDIF
	bt	[Vid_Flags],bVid_PlanarInit
	cmc
	ret
EndProc VDD_State_Set_MemC_Planar

;******************************************************************************
;
;   VDD_State_Internal_Set_MemC_Planar
;
;   DESCRIPTION:    Called by VDD_State_Save_Latches to avoid re-entering
;		    VDD_State_Set_MemC_Planar.	Also everything else is
;		    already saved, so there is no problem in just restoring
;		    the registers from Vid_Planar_State.
;
;   ENTRY:	    none
;
;   EXIT:	    none
;
;   USES:	    ESI
;
;==============================================================================
BeginProc VDD_State_Internal_Set_MemC_Planar

	push	ebx
	push	edi
	xor	ebx, ebx
	mov	[Vid_MemC_VM], ebx
	TestMem [Vid_Flags],fVid_PlanarInit
	jz	SHORT VSISMP_Error
	mov	ebx,[Vid_CRTC_VM]
	SetVDDPtr edi				;   Y: Use CRTC VM state
	mov	esi,OFFSET32 Vid_Planar_Pseudo_CB ; ESI = planar state

; EBX = CRTC_VM handle
; ESI -> VDD data for MemC state owner
; EDI -> VDD data for CRTC state owner
;;Debug_Out "Set_Plan #EBX, #ESI, #EDI"
IFDEF DEBUG_verbose
	Mono_Out '=',noeol
ENDIF
;TLVGA note: For the ET3000, we want here ATC 16 bit 4 to be unchanged, since
; otherwise we won't be able to access the memory right; this should be true,
; since VDD_State_Restore_Regs doesn't change ATC regs if CRTC owner isn't
; changing. (We also need ATC 10 bit 6=0 but that should be true here.)
	call	VDD_State_Restore_Regs		; Restore the registers
VSISMP_Error:
	pop	edi
	pop	ebx
	bt	[Vid_Flags],bVid_PlanarInit
	cmc
	ret

EndProc VDD_State_Internal_Set_MemC_Planar


;******************************************************************************
;VDD_State_Set_Message_Mode
;
;DESCRIPTION:
;	Programs CRTC and MemC state for Message mode.
;
;ENTRY: none
;
;EXIT:	none
;
;USES:	Flags
;
;==============================================================================
BeginProc VDD_State_Set_Message_Mode, PUBLIC

;;Trace_Out "Set_Mesg #EBX"
	pushad
	bts	[Vid_Flags], bVid_MsgA
	jc	DEBFAR VS_SMM_Reentered

	VMMCall Get_Cur_VM_Handle

;*******
; If necessary, save current CRTC state owner registers
;
	TestMem [Vid_Flags], fVid_MsgInit	; Q: Message mode initialized?
	jnz	SHORT VS_SMM_01 		;   Y:
	mov	eax, 3
	call	VDD_State_Set_Mode
	call	VDD_Device_Init 		;   N: do the initialization

VS_SMM_01:
;*******
; Notify the current VM that it is losing display focus, if necessary

IFNDEF VGA8514
	SetVDDPtr edi

IFDEF SysVMin2ndBank
	TestMem [edi.VDD_TFlags], fVT_SysVMnot1stBank
	jz	short @F
	VMMCall Test_Sys_VM_Handle		; we'll do message mode in
	je	short smm_no_bknotify		;   the first bank of memory
						;   so we don't need to notify
						;   the sys VM, because it is
						;   running in the 2nd bank
						;   and won't lose it's memory
@@:
ENDIF
	TestMem [edi.VDD_Flags], fVDD_NoSaveRes     ;Q: auto res disabled?
	jz	short smm_no_bknotify		    ;	N: chk next VM
	TestMem [edi.VDD_Flags], fVDD_WaitAtt	    ;Q: already suspended?
	jnz	short smm_no_bknotify		    ;	Y: skip VM
	call	VDD_Proc_BGrnd_Notify
smm_no_bknotify:
ENDIF

;*******
; set MemC state and CRTC state to message pseudo VM

	mov	ebx, [Vid_Msg_Pseudo_VM]	; Get message pseudo VM handle
	SetVDDPtr edi
	call	VDD_State_Set_CRTC_Owner
	call	VDD_VM_Mem_Alloc_Msg_Mode_Mem	; Set up for message mode
	call	VDD_Font_Restore_Msg_Font	; Restore font
VS_SMM_02:
	call	VDD_State_Set_MemC_Owner
VS_SMM_03:
	popad
	ret

VS_SMM_Reentered:
	TestMem [Vid_Flags], fVid_MsgInit	; Q: Message mode initialized?
	jz	VS_SMM_03			;   N: skip MemC setting
	mov	ebx, [Vid_Msg_Pseudo_VM]	; Get message pseudo VM handle
	SetVDDPtr edi
	jmp	VS_SMM_02


EndProc VDD_State_Set_Message_Mode


;******************************************************************************
;VDD_State_Save_CRTC_Owner
;
;DESCRIPTION:
;	This routine is called to update any registers in the controller
;	data structure that are not correct for the VM running in the hardware.
;
;ENTRY: EBX = running VM handle
;	EDI -> owner VDD CB data
;
;EXIT:	none
;
;USES:	Flags, EAX
;
;==============================================================================
BeginProc VDD_State_Save_CRTC_Owner,PUBLIC

IFDEF DEBUG_verbose
	Mono_Out '.',noeol
ENDIF
	push	ebx
	push	edi
;;Trace_Out "Sav_CRTC #EBX" +
	mov	ebx,[Vid_CRTC_VM]		; EBX = CRTC owner
	or	ebx,ebx 			; Q: Any VM own CRTC?
	jz	short VS_SvCO_Exit		;   N: skip reg save
	cmp	ebx, [Vid_Msg_Pseudo_VM]	; Q: Message mode in CRTC?
	jz	short VS_SvCO_Exit		;   Y: skip reg save
	SetVDDPtr edi

	cmp	ebx,[Vid_MemC_VM]		; Q: CRTC VM = MemC VM?
	jnz	SHORT VS_SvCO_Exit		;   N: Skip reg save

;
; This next check is a hack!  The problem is that if a background VM owns the
; MemC state when we are trying to change the focus, then we never get the
; complete register state read for the current CRTC owner.  All of the other
; code assumes that the complete register state is read whenever
; VDD_VGA_Save_Regs is called, and the code would be correct if it did.  But,
; if the display is still enabled when VDD_VGA_Save_Regs is called, then
; some registers, such as the Attribute controller palette registers, are
; not read.  So when this routine was called during a focus change, it would
; either see that the MemC was different or that I/O trapping was enabled and
; assume that the register state was known.  I added a hack to
; VDD_State_Set_CRTC_Owner to force MemC = CRTC before calling this routine,
; but if the screen has been disabled, then I/O trapping is enabled, but we
; still haven't read the complete state, so the hack is to skip the check
; for I/O trapping and save the regs anyway.  RAP 10/6/91
;

	TestMem [Vid_Flags],fVid_DOff		; Q: Screen globally turned off?
	jnz	short @F

	TestMem [edi.VDD_Flags],fVDD_IOT	; Q: I/O trapped?
	jnz	SHORT VS_SvCO_Exit		;   N: skip reg save

@@:
	TestMem [Vid_Flags], fVid_SR_regs_saved ;Q:regs saved?
	jnz	short VS_SvCO_Exit		;   Y: exit
	TestMem [Vid_Flags], fVid_SR_Section	;Q: in SR section?
	jz	short VS_SvCO_saveregs		;   N: save regs
	SetFlag [Vid_Flags], fVid_SR_regs_saved ;   Y: flag that regs are saved
VS_SvCO_saveregs:
IFDEF DEBUG_verbose
	Mono_Out 'S',noeol
	call	VDD_State_VM_Debug
ENDIF
	call	VDD_VGA_Save_Regs		;   N: Save the registers
IFDEF VRTCTIMER
	push	eax
	call	VDD_State_Calc_Framerate
	pop	eax
ENDIF
VS_SvCO_Exit:
	pop	edi
	pop	ebx
	ret

EndProc VDD_State_Save_CRTC_Owner


;******************************************************************************
;VDD_State_Restore_Latches
;
;DESCRIPTION:
;	This routine restores the current video latches.  Note that it may
;	call VDD_State_Set_MemC_Planar so it is necessary to set the
;	MemC state explicitly after calling this routine.
;
;ENTRY: EBX = CRTC VM handle
;	EDI -> CRTC owner VDD CB data
;	ESI -> MemC owner VDD CB data
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX
;
;==============================================================================
BeginProc VDD_State_Restore_Latches

;;	  queue_out 'restore latches #eax for #ebx', [esi.VDD_Latches], esi
IFDEF DEBUG_verbose
	Mono_Out 'r',noeol
	push	ebx
	mov	ebx, esi
	sub	ebx, [Vid_CB_Off]
	call	VDD_State_VM_Debug
;;	  mov	  eax, dword ptr [esi.VDD_Latches]
;;	  Trace_Out '#eax',noeol
	pop	ebx
ENDIF
	TestMem [esi.VDD_Flags], fVDD_ModeSet	;Q: in a mode change?
	jnz	short VS_RL_00			;   Y: ignore latches
	test	[esi.VDD_Stt.G_Misc],8		; Q: Graphics mode, not CGA?
	jz	SHORT VS_RL_01			;   Y: Restore latches
VS_RL_00:
	ret					;   N: Skip restore latches
VS_RL_01:

	call	VDD_OEM_Restore_Latches 	; Q: OEM specific restore?
	jc	SHORT VS_RL_00			;   Y: skip standard restore

	push	ebx
	mov	ebx,esi
IFDEF	DEBUG
VxD_DATA_SEG
Vid_Latches_Ptr  DD ?
VxD_DATA_ENDS
	mov	[Vid_Latches_Ptr],ebx
ENDIF
	call	VDD_State_Internal_Set_MemC_Planar

; Write all four latches
	call	VDD_PH_Mem_Access_Latch_Page	; ESI = place to save latches
	mov	dx,pSeqIndx
	mov	al,2
	out	dx,al
	IO_Delay
	inc	edx
	xor	ecx,ecx 			; Plane 0 index
	mov	ah,1				; Plane 0 write mask
VRL_00:
	mov	al,ah
	out	dx,al				; select next plane for write
	IO_Delay
	mov	al,[ebx.VDD_Latches][ecx]
	mov	BYTE PTR [esi],al		; write this plane's latch value
	inc	cl
	shl	ah,1
	cmp	cl,3
	jbe	VRL_00

	mov	al,BYTE PTR [esi]		; Read data into latches

	call	VDD_PH_Mem_End_Access_Latch_Page

IFDEF	DEBUG
	cmp	[Vid_Latches_Ptr],ebx
	jz	SHORT VRL_DExit
Debug_Out "Reentered Restore latches"
VRL_DExit:
ENDIF
	mov	esi,ebx
	pop	ebx
	ret
EndProc VDD_State_Restore_Latches

;******************************************************************************
;VDD_State_Save_Latches
;
;DESCRIPTION:
;	This routine saves the current video latches.  Note that it may
;	call VDD_State_Set_MemC_Planar so it is necessary to set the
;	MemC state explicitly after calling this routine.
;
;ENTRY: EBX = VM handle
;	EDI -> VDD CB data
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_State_Save_Latches

IFDEF DEBUG_verbose
	Mono_Out 's',noeol
	call	VDD_State_VM_Debug
ENDIF
	TestMem [edi.VDD_Flags], fVDD_ModeSet	;Q: in a mode change?
	jnz	short VS_SL_00			;   Y: ignore latches
	test	[edi.VDD_Stt.G_Misc],8		; Q: Graphics mode, not CGA?
	jz	SHORT VS_SL_01			;   Y: Save latches
VS_SL_00:
	ret					;   N: Skip save latches
VS_SL_01:

	call	VDD_OEM_Save_Latches		; Q: OEM specific save?
	jc	VS_SL_00			;   Y: skip standard save

IFDEF	DEBUG
	mov	[Vid_Latches_Ptr],edi
ENDIF
	call	VDD_State_Internal_Set_MemC_Planar

	push	ebx
	mov	ebx,[Vid_CRTC_VM]
	add	ebx,[Vid_CB_Off]		; EBX = CRTC VM data ptr

; set write to all planes
	mov	dx,pSeqIndx
	mov	al,02h
	out	dx,al
	IO_Delay
	inc	dl
	mov	al,0Fh				; Write mask for all planes
	out	dx,al
	IO_Delay
	dec	dl

; set write mode 1
	mov	dx,pGrpIndx
	mov	al,05h
	out	dx,al
	IO_Delay
	inc	dl
	mov	al,[ebx.VDD_Stt.G_Mode]
	and	al,60h				; Preserve CRTC Shift bit
						;   and Shift 256 bit
	or	al,1				; Set write mode 1
	out	dx,al
	IO_Delay
	dec	dl
	call	VDD_PH_Mem_Access_Latch_Page	; ESI = place to save latches
	mov	BYTE PTR [esi],al		; Write the latches

; set read mode 0, write mode 0
	mov	al,05h
	out	dx,al
	IO_Delay
	inc	dl
	mov	al,[ebx.VDD_Stt.G_Mode]
	and	al,60h				; Preserve CRTC Shift bit
						;   and Shift 256 bit
	out	dx,al
	IO_Delay
	dec	dl

; read the latches
	mov	al,4
	out	dx,al
	IO_Delay
	inc	dl
	xor	ecx,ecx 			; Start with plane 3
VS_SL_03:
; select next plane
	mov	al,cl
	out	dx,al
	IO_Delay

; Read and save the latch
	mov	al,BYTE PTR [esi]

	mov	[edi.VDD_Latches][ecx],al
	inc	ecx
	cmp	cl,3
	jbe	VS_SL_03

	call	VDD_PH_Mem_End_Access_Latch_Page

IFDEF	DEBUG
;;	  mov	  ebx, [esp]
;;	  queue_out 'save latches #eax for #ebx', [edi.VDD_Latches]
	cmp	[Vid_Latches_Ptr],edi
	jz	SHORT VSL_DExit
Debug_Out "Reentered save latches"
VSL_DExit:
ENDIF
	pop	ebx
	ret
EndProc VDD_State_Save_Latches

;******************************************************************************
;VDD_State_Get_Mode
;
;DESCRIPTION:
;	This routine returns the BIOS mode for the VM.
;
;ENTRY: EBX = running VM handle
;	EDI -> VDD CB data
;
;EXIT:	EAX = mode
;
;USES:	Flags
;
;==============================================================================
BeginProc  VDD_State_Get_Mode, PUBLIC

Assert_VDD_ptrs ebx,edi
	pushad
	call	VDD_State_Get_Display_Dimensions
	jc	short gm_graphics

; EAX : # of rows in chars; ECX : # of columns in chars
	xor	edx, edx
	cmp	cl, 40			;Q: mode 0 or 1?
	je	SHORT gm_exit		;   Y: return mode 0
	mov	dl, 3
	cmp	cl, 80			;Q: 80 column text?
; PVGA - unnecessary checking for modes unsupported by grabber
;;;IFDEF   PVGA 			   ; C. Chiang
;;;	jnz	SHORT pvga_text132		; N: chk if WDC text 132 mode
;;;	TestMem [edi.VDD_TFlags],fVT_PVGA
;;;	jz	SHORT @F
;;;	cmp	ax, 34			; Y: Q: if 34 line text?
;;;	jnz	short @F		;	N: must be 25 line text
;;;	mov	dl, 41h
;;;	jmp	SHORT gm_exit		;	Y: return mode 41h
;;;@@:
;;;ELSE
	jnz	gm_unknown		;   N: unknown mode
;;;ENDIF   ;PVGA
	test	[edi.VDD_Stt.V_Misc],1	;   Y: Q: Mono mode?
	jnz	SHORT gm_exit		;	N: return mode 3
	mov	dl,7
	jmp	SHORT gm_exit		;	Y: return mode 7

;;;IFDEF   PVGA 			   ; C. Chiang
; add Western Digital 132-column text mode checking	- C. Chiang -
;;;pvga_text132:
;;;	TestMem [edi.VDD_TFlags],fVT_PVGA
;;;	jz	SHORT gm_exit
;;;	cmp	cl, 132
;;;	jnz	gm_unknown		;   N: unknown mode
;;;	test	[edi.VDD_Stt.V_Misc],1	;   Y: Q: Mono mode?
;;;	jz	SHORT pvga_mono_text132 ; Y: WDC mode 56h, 57h
;;;	mov	dl, 54h 		; N: WDC mode 54h, 55h
;;;	jmp	SHORT pvga_text132_43
;;;pvga_mono_text132:
;;;	mov	dl, 56h
;;;pvga_text132_43:
;;;	cmp	al, 43			; Q: 43 line?
;;;	jz	SHORT gm_exit		;    Y: return mode 54h
;;;	cmp	al, 44			; Q: 44 line in 1D chip
;;;	jz	SHORT gm_exit		;    Y: return mode 54h for 1D chip
;;;	cmp	al, 28			; Q: 132x28 mode
;;;	jnz	short pvga_text132_25	;    N
;;;	mov	dl, 46h
;;;	test	[edi.VDD_Stt.V_Misc],1	;    Y: Q: Mono mode?
;;;	jz	short @F		;	   Y: return mode 46h
;;;	inc	dl			;	   N; return mode 47h
;;;@@:
;;;	jz	SHORT gm_exit
;;;
;;;pvga_text132_25:
;;;	inc	dl
;;;	jmp	SHORT gm_exit		;    N: return mode 55h
;;;ENDIF   ;PVGA

gm_graphics:
	cmp	eax, 200		;Q: low res?
	jne	short gm_hi_res 	;   N:
	cmp	ecx, 320		;Q: 320X200?
	jne	short gm_not_320	;   N:
	mov	dl, 13h
	test	[edi.VDD_Stt.S_MMode], fSeq4Chain4  ;Q: chain4 (mode 13)?
	jnz	short gm_exit			    ;	Y: return mode 13h
	mov	dl, 4
	test	[edi.VDD_Stt.S_MMode], fSeq4SqAd    ;Q: odd/even (mode 4 or 5)?
	jz	short gm_exit			    ;	Y: return mode 4
	mov	dl, 0Dh 			    ;	N: return mode 0Dh
gm_exit:
	mov	[esp.Pushad_EAX], edx
IFDEF	PVGA
; set flag for PVGA 132-column page mode purpose	- C. Chiang -
;;	mov	byte ptr [edi.VDD_PVGA_132Flags], 0  ; invalidate value
ENDIF	;PVGA
	popad
;;;	Trace_Out 'Get_Mode = #al'
	ret

gm_not_320:
	cmp	ecx, 640		;Q: 640X200?

;;;IFDEF   PVGA
; PVGA - unnecessary checking for modes unsupported by grabber
; add Western Digital extended graphic mode checking	- C. Chiang -
;;;	jz	SHORT gm_X_640		; goto 640-wide mode
;;;	cmp	eax, 600		; Q: 600 vertical lines?
;;;	jnz	SHORT pvga_768		;    N: must be 768 vertical lines
;;;	mov	dl, 5Ch
;;;	test	[edi.VDD_Stt.G_PVGA4],1 ; Q: WDC 256-color 5Ch mode?
;;;	jz	short @F
;;;	jmp	gm_exit 		;   Y: return mode 5Ch
;;;@@:
;;;	mov	dl, 58h
;;;	test	[edi.VDD_Stt.V_Misc],1	;   N: Q: Mono mode?
;;;	jz	short @F
;;;	jmp	gm_exit 		;	   Y: return mode 59h
;;;@@:
;;;	inc	dl
;;;	jmp	gm_exit 		;	   N: return mode 58h

;;;pvga_768:
;;;	test	[edi.VDD_Stt.G_PVGA4],1 ;Q: WDC 256-color 60h mode?
;;;	jz	short @F
;;;	mov	dl, 60h
;;;	jmp	gm_exit 		;   Y: return 1024x768x256 mode 60h
;;;@@:
;;;	test	[edi.VDD_Stt.S_MMode],fSeq4Chain4 ; Q: Mode 5B special bit?
;;;	jz	short @F
;;;	mov	dl, 5Bh
;;;	jmp	gm_exit 		;   Y: return 1024x768x4 mode 5Bh
;;;@@:
;;;	test	[edi.VDD_Stt.S_MMode],fSeq4SqAd ;Q: Seq'l mem addr'ing(vs. odd/even)
;;;	jz	short @F
;;;	mov	dl, 5Dh
;;;	jmp	gm_exit 		;   Y: return 1024x768x16 mode 5Dh
;;;@@:
;;;	mov	dl, 5Ah
;;;	jmp	gm_exit 		;   N: return 1024x768x2 mode 5Ah

;;;gm_X_640:

;;;ELSE
	jne	short gm_unknown	;   N: unknown mode
;;;ENDIF   ;PVGA

	jne	short gm_unknown	;   N:
	mov	dl, 6
	test	[edi.VDD_Stt.C_Mode], 1 ;Q: compatibility (mode 6)?
	jz	short gm_exit		;   Y: return mode 6
	mov	dl, 0Eh 		;   N: return mode 0Eh
	jmp	short gm_exit

gm_hi_res:
	cmp	ecx, 640		;Q: 640 wide graphics?
	jne	short gm_unknown	;   N: unknown mode
IFDEF TLVGA
	TestMem [edi.VDD_TFlags],fVT_TLVGA
	jz	short gm_2
	;if ET3000, test ATC 10 bit 6 also for 256 color mode
	test	[edi.VDD_Stt.A_Mode],040h
	jnz	short gm_unknown
gm_2:
ENDIF
	test	[edi.VDD_Stt.S_MMode],fSeq4Chain4
;;;IFDEF   PVGA
; PVGA - unnecessary checking for modes unsupported by grabber
;;;	jz	short @F
;;;	TestMem [edi.VDD_TFlags],fVT_PVGA
;;;	jz	SHORT gm_exit
;
; if (3c4.04 & 80h) == 1
;        -> WDC mode 5Eh or 5Fh 640-wide 256-color    - C. Chiang -
;;;	mov	dl, 5Eh
;;;	cmp	eax, 480		;Q: WDC 640X480x256 - mode 5F?
;;;	jz	short pvga_5F			;   Y: return mode 5Fh
;;;	jmp	gm_exit
;;;pvga_5F:
;;;	inc	dl			;   N: return mode 5Eh
;;;	jmp	gm_exit
;;;@@:
;;;ELSE
	jnz	short gm_unknown
;;;ENDIF   ;PVGA
	cmp	eax, 350		;Q: 640X350 (mode 10h)?
	je	short gm_Hi_Res_EGA	;   Y: return mode 10h or 0Fh
	cmp	eax, 480		;Q: 640X480?
	jne	short gm_unknown	;   N: unknown mode
	mov	dl, 11h
	test	[edi.VDD_Stt.C_Mode], 100000b ;Q: mode 11h (2 color)?
	jz	gm_exit 		;   Y: return mode 11h
	inc	dl			;   N: return mode 12h
	jmp	gm_exit

gm_Hi_Res_EGA:
	mov	dl, 10h
	test	[edi.VDD_Stt.V_Misc],1	;Q: Mono mode?
	jnz	short gm_exit		;   N: return mode 10
	mov	dl, 0Fh 		;   Y: return mode F
	jmp	gm_exit

gm_unknown:
	Debug_Out 'unknown video mode #ax X #cx'
	or	edx, -1
	jmp	gm_exit

EndProc VDD_State_Get_Mode

;******************************************************************************
;VDD_State_Get_Mem_Mapping
;
;DESCRIPTION:
;	This routine returns the start page # for the video memory.
;
;ENTRY: EBX = running VM handle
;	EDI -> VDD CB data
;
;EXIT:	AL = video start page number
;	AH = # of pages
;
;USES:	Flags, EAX
;
;==============================================================================
BeginProc VDD_State_Get_Mem_Mapping, PUBLIC

IFNDEF	VGA8514	; VBE and 8514 detection are mutually exclusive from VDDDEF.INC
	TestMem [edi.VDD_TFlags],<fVT_VBESVGA>
	jz	short VS_GMM_NotVBE

	mov	ax,[edi.VDD_Stt.V_Extend.VBE_VidModeP1]
	test	ax,ax
	jz	short VS_GMM_NotVBE	; not in VBE mode!

	TestMem	[edi.VDD_Flags],<fVDD_ModeSet>
	; if VM is modesetting, then trust the misc register for now...
	jnz	short VS_GMM_NotVBE

	; use the WinA segment and window size to define available pages
	mov	ax,[edi.VDD_Stt.V_Extend.VBE_WinSize]
	; convert kiB in AX to pages (4-kiB units) in AH
	shl	ax,(8-2)
	; upper byte of seg index is page index:
	mov	al,byte ptr [edi.VDD_Stt.V_Extend.VBE_WinASeg+1]
	ret

@@:	; linear mode - check if the buffer is below the 1-MiB boundary:
	mov	eax,[edi.VDD_Stt.V_Extend.VBE_LinearBuf]
	cmp	eax,100000h

	; linear buffer in extended memory: there shouldn't be any reason
	; to access the low-memory buffers; so just fall back to the misc
	; register (because if it's wrong we don't really care...
	jnb	short VS_GMM_NotVBE

@@:	; linear buffer in low memory - assume it extends as far as C0000h...
	shr	eax,12	; convert address to page number
	mov	ah,0C0h	; page for C0000h
	sub	ah,al	; convert to page count
	ret

VS_GMM_NotVBE:
ENDIF	;VGA8514

	push	ecx
	mov	eax,010A0h
	or	ebx,ebx
	jz	SHORT VS_GMM_Exit
	movzx	ecx, [edi.VDD_Stt.G_Misc]
	shr	ecx, 1
	and	cl, 110b
	mov	ax, [ecx+MemMappingTable]
VS_GMM_Exit:
	pop	ecx
	ret

VxD_DATA_SEG
MemMappingTable label	word	; map def bits
		dw	20A0h	;     00
		dw	10A0h	;     01
		dw	08B0h	;     10
		dw	08B8h	;     11
VxD_DATA_ENDS

EndProc VDD_State_Get_Mem_Mapping

;******************************************************************************
;VDD_State_System_Exit
;
;DESCRIPTION:
;	This routine resets the hardware for Windows exit
;
;ENTRY: EBX = System VM handle
;	EDI -> VDD CB data
;
;EXIT:	None
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc  VDD_State_System_Exit, PUBLIC

IFDEF SysVMin2ndBank
	TestMem [edi.VDD_TFlags], fVT_SysVMin2ndBank
	jz	short @F
	call	VDD_State_Blank_Screen
	xor	al, al
	call	VDD_OEM_force_bank
@@:
ENDIF
	jmp	VDD_OEM_System_Exit	    ; Reset hardware if necessary
EndProc  VDD_State_System_Exit


;******************************************************************************
;VDD_State_Destroy_VM
;
;DESCRIPTION:
;
;ENTRY: EBX = VM Handle
;	EDI -> VDD CB data
;
;EXIT:	none
;
;USES:	EAX, ECX, EDX, ESI, Flags
;
;==============================================================================
BeginProc VDD_State_Destroy_VM, PUBLIC

IFDEF DEBUG
	cmp	ebx, [Vid_Focus_VM]
	jne	short dvm_not_focus
	Debug_Out 'VDD_State_Destroy_VM called for focus VM #ebx'
dvm_not_focus:
ENDIF

	cmp	ebx, [Vid_CRTC_VM]	    ;Q: crtc owner being destroyed?
	jne	short dvm_not_crtc	    ;	N:
	Debug_Out 'VDD_State_Destroy_VM called for CRTC owner #ebx'
	call	VDD_State_Scrn_Off	    ;	Y: turn off screen
	mov	[Vid_CRTC_VM], 0	    ;	     & clear owner handle
dvm_not_crtc:

	cmp	ebx, [Vid_MemC_VM]	    ;Q: memc owner being destroyed?
	jne	short dvm_not_memc	    ;	N:
	push	ebx
	mov	ebx, [Vid_CRTC_VM]	    ;	Y: set memc owner to crtc owner
	or	ebx, ebx		    ;Q: crtc owned?
	jz	short dvm_no_crtc	    ;	N: set memc planar
	SetVDDPtr edi
	call	VDD_State_Set_MemC_Owner    ;	Y: set memc owner
	jmp	short dvm_memc_changed
dvm_no_crtc:
	call	VDD_State_Set_MemC_Planar
dvm_memc_changed:
	pop	ebx

dvm_not_memc:
	ret

EndProc VDD_State_Destroy_VM


;******************************************************************************
;VDD_State_Change_Query
;
;DESCRIPTION:
;
;ENTRY: EBX = VM Handle
;	EDI -> VDD CB data
;
;EXIT:	none
;
;USES:	EAX, ECX, EDX, ESI, Flags
;
;==============================================================================
BeginProc VDD_State_Change_Query, PUBLIC

	TestMem [edi.VDD_Flags],fVDD_Win	    ; Q: Windowed VM?
	jz	SHORT VSCQ_NoChange		    ;	N: report no change
	TestMem [edi.VDD_Flags],fVDD_MInit	    ; Q: memory initialized?
	jz	SHORT VSCQ_NoChange		    ;	N: report no change
	TestMem [edi.VDD_Flags],fVDD_ModeChange     ; Q: Mode change ongoing?
	jnz	SHORT VSCQ_NoChange		    ;	Y: report no change

	call	VDD_State_Chk_Cursor		    ; Q: Cursor move?
	jnz	SHORT VSCQ_Changed		    ;	Y: report change

	call	VDD_State_Chk_CRTC		    ; Q: Other controller chg?
	jc	SHORT VSCQ_Changed		    ;	Y: report change

VSCQ_NoChange:
	clc
	ret
VSCQ_Changed:
	stc
	ret
EndProc VDD_State_Change_Query

;******************************************************************************
;VDD_State_Get_Chgs	Build ctlr change state by comparing prev. with cur.
;
;DESCRIPTION:
;	Compares the fields in the VM's VDD_Stt and VDDSttCopy and
;	sets bits in the message flag word pointed to by ESI. If only the cursor
;	position or size changed, just the cursor flag bit is set. If any
;	additional changes are detected, the controller change flag bit is set.
;	In order to catch changes that might occur between a Get_Mod call from
;	the grabber and a Clear_Mod call, we copy the controller state in
;	this routine but maintain a cumulative status to return to the
;	grabber.  When Clear_Mod is called, that cumulative status is cleared.
;
;ENTRY: EBX = VM_Handle
;	EDI -> VDD CB data
;	ESI = Place to build message
;
;EXIT:	EAX = VDD_Mod_Flag bits to pass to VMDOSAPP
;
;USES:	Flags, EAX
;
;ASSUMES:
;	This is called only for windowed VMs.
;
;==============================================================================
BeginProc VDD_State_Get_Chgs, PUBLIC

Assert_VDD_ptrs ebx,edi
;*******
; First check whether screen is turned off
	ClrFlag [edi.VDD_Mod_Flag_Save], fVDD_M_ScOff
	TestMem [edi.VDD_Flags],fVDD_MInit	    ; Q: memory initialized?
	jz	SHORT VSGC_NoChg		    ;	N: report screen off
	TestMem [edi.VDD_Flags],fVDD_ModeChange     ; Q: Mode change ongoing?
	jnz	SHORT VSGC_NoChg		    ;	Y: report screen off
	call	VDD_State_Chk_CRTC
	jnz	SHORT VSGC_ScreenOn
	pushfd
	SetFlag [edi.VDD_Mod_Flag_Save], fVDD_M_ScOff
	popfd
VSGC_ScreenOn:
	jc	SHORT VSGC_Chg_Ctl

	call	VDD_State_Chk_Cursor		    ; Q: Cursor moved?
	jne	SHORT VSGC_Chg_Curs		    ;	Y: return cursor changed

VSGC_NoChg:
	xor	eax,eax
	jmp	SHORT VSGC_Exit

; CRTC cursor size or address changed
VSGC_Chg_Curs:
	mov	eax,fVDD_M_Curs 		    ; Set cursor changed flag
	jmp	SHORT VSGC_Exit

; CRTC register affecting display changed
VSGC_Chg_Ctl:
	mov	[edi.VDD_Stt.V_BIOSMode],al	    ; Save current BIOS mode
	cmp	al,0Bh
	jz	SHORT VSGC_NoChg		    ; No changes for mode B
	mov	eax,fVDD_M_Ctlr+fVDD_M_Curs	    ; Set ctrlr chg flag

VSGC_Exit:
	or	[edi.VDD_Mod_Flag_Save], eax	    ; Accumulate chgd flags
	call	VDD_State_Copy_Ctlr_State	    ; Update copy of ctlr state
	mov	eax, [edi.VDD_Mod_Flag_Save]
	mov	[esi.VDD_Mod_Flag],ax		    ; Pass state change flags
	ret					    ;	to grabber
EndProc VDD_State_Get_Chgs


;******************************************************************************
;VDD_State_Chk_CRTC
;
;DESCRIPTION:
;	Compares the fields in the VM's VDD_Stt and VDDSttCopy and
;	returns Carry flag set if any changes found.  Also returns Zero flag
;	set if screen is turned off via attribute controller.
;
;ENTRY: EBX = VM_Handle
;	EDI -> VDD CB data
;
;EXIT:	EAX = BIOS mode
;	Carry flag set if change detected
;	Zero flag set if screen off
;
;USES:	Flags, EAX
;
;==============================================================================
BeginProc VDD_State_Chk_CRTC

; Check whether video BIOS mode is the same as last Clear_Mod value
	call	VDD_State_Get_Mode		    ; EAX = VM's video mode
	push	eax
	cmp	al,[edi.VDD_SttCopy.V_BIOSMode]     ; Q: Same as last time?
	jnz	VSCC_Chg_Ctl			    ;	N: return ctlr chged

; Check if screen was turned on or off
	test	[edi.VDD_Stt.A_Indx],fVAI_ScOn
	jnz	SHORT VSCC_On
	test	[edi.VDD_SttCopy.A_Indx],fVAI_ScOn  ; Q: Screen off change?
	jnz	SHORT VSCC_Chg_Ctl		    ;	Y: return ctlr chged
	jmp	SHORT VSCC_1
VSCC_On:
	test	[edi.VDD_SttCopy.A_Indx],fVAI_ScOn  ; Q: Screen off change?
	jz	SHORT VSCC_Chg_Ctl		    ;	Y: return ctlr chged
VSCC_1:

; Also check the "43 line mode" register, for which the mode is the same
	mov	al,[edi.VDD_Stt.C_MaxScan]
	cmp	al,[edi.VDD_SttCopy.C_MaxScan]	    ; Q: Mode change?
	jne	SHORT VSCC_Chg_Ctl		    ;	Y: return ctlr changed
	mov	al,[edi.VDD_Stt.C_VDspEnd]
	cmp	al,[edi.VDD_SttCopy.C_VDspEnd]	    ; Q: Mode change?
	jne	SHORT VSCC_Chg_Ctl		    ;	Y: return ctlr changed

; Check for change in display offset
	mov	ax,WORD PTR [edi.VDD_Stt.C_AddrH]
	cmp	ax,WORD PTR [edi.VDD_SttCopy.C_AddrH] ; Q: Offset change?
	jne	SHORT VSCC_Chg_Ctl		    ;	Y: return ctlr changed

; Check for change in DACs
	btr	[edi.VDD_Flags],bVDD_DacChg	; dacs changed
	jc	SHORT VSCC_Chg_Ctl

; Check for change in attributes
	mov	eax,DWORD PTR [edi.VDD_Stt.A_Pal]
	cmp	eax,DWORD PTR [edi.VDD_SttCopy.A_Pal] ; Q: Palette chg?
	jne	SHORT VSCC_Chg_Ctl		    ;	Y: return ctlr changed
	mov	eax,DWORD PTR [edi.VDD_Stt.A_Pal+4]
	cmp	eax,DWORD PTR [edi.VDD_SttCopy.A_Pal+4] ; Q: Palette chg?
	jne	SHORT VSCC_Chg_Ctl		    ;	Y: return ctlr changed
	mov	eax,DWORD PTR [edi.VDD_Stt.A_Pal+8]
	cmp	eax,DWORD PTR [edi.VDD_SttCopy.A_Pal+8]  ; Q: Palette chg?
	jne	SHORT VSCC_Chg_Ctl		    ;	Y: return ctlr changed
	mov	eax,DWORD PTR [edi.VDD_Stt.A_Pal+12]
	cmp	eax,DWORD PTR [edi.VDD_SttCopy.A_Pal+12] ; Q: Palette chg?
	jne	SHORT VSCC_Chg_Ctl		    ;	Y: return ctlr changed

; Check for OEM specific controller changes
	call	VDD_OEM_Chk_CRTC		    ; Q: OEM CRTC changed?
	jc	SHORT VSCC_Chg_Ctl		    ;	Y: return ctlr changed

; No change in controller state
VSCC_NoChange:
	pop	eax
	test	[edi.VDD_Stt.A_Indx],fVAI_ScOn
	clc
	ret

; Change in controller state
VSCC_Chg_Ctl:
	pop	eax
	test	[edi.VDD_Stt.A_Indx],fVAI_ScOn
	stc
	ret
EndProc VDD_State_Chk_CRTC


;******************************************************************************
;VDD_State_Clear_Mod_State
;
;DESCRIPTION:
;	Clears accumulation of modified controller state flags
;
;ENTRY: EBX = VM Handle
;	EDI -> VDD CB data
;
;EXIT:	none
;
;USES:	flags
;
;==============================================================================
BeginProc VDD_State_Clear_Mod_State

	mov	[edi.VDD_Mod_Flag_Save],0
	ClrFlag [edi.VDD_Flags], fVDD_HCurTrk	; Clear Horiz Cursor tracking
	ret
EndProc VDD_State_Clear_Mod_State


;******************************************************************************
;VDD_State_Chk_Cursor	      Determine if Cursor changed state
;
;DESCRIPTION:
;
;ENTRY: EBX = VM handle
;	EDI -> VDD CB data
;
;EXIT:	ZF = 0 indicates change detected
;
;USES:	Flags, EAX
;
;==============================================================================
BeginProc VDD_State_Chk_Cursor

Assert_VDD_ptrs ebx,edi

	call	VDD_OEM_Chk_Cursor		; Q: OEM cursor change?
	jne	SHORT VSCC_Change		;   Y: return cursor changed
; Check for change in cursor
	mov	ax,WORD PTR [edi.VDD_Stt.C_CAddrH]
	cmp	ax,WORD PTR [edi.VDD_SttCopy.C_CAddrH] ; Q: Curs off chg?
	jne	SHORT VSCC_Change		;   Y: return cursor changed
	mov	ax,WORD PTR [edi.VDD_Stt.C_CStart]
	cmp	ax,WORD PTR [edi.VDD_SttCopy.C_CStart] ; Q: Curs scan chg?
VSCC_Change:
	ret
EndProc VDD_State_Chk_Cursor


;******************************************************************************
;VDD_State_Get_State
;
;DESCRIPTION:
;
;ENTRY: EBX = VM Handle
;	EDI -> VDD CB data
;	ESI -> buffer for building message
;	CF = 1, use VDD_Stt; CF = 0, use VDD_SttCopy
;
;EXIT:
;
;USES:
;
;==============================================================================
BeginProc VDD_State_Get_State

	pushfd
	lea	edx, [edi.VDD_SttCopy]
	jnc	short gs_0
	lea	edx, [edi.VDD_Stt]
gs_0:
	call	VDD_State_Get_Mode
	mov	[esi.VDA_EGA_Mode], al

	call	VDD_State_Get_Display_Dimensions ; EAX = rows, ECX = columns
	jc	short gs_graphics
	mov	[esi.VDA_EGA_Rows], al
gs_graphics:

	mov	al, [edx.A_OvScn]
	mov	[esi.VDA_EGA_Colr], al
	popfd
	jnc	SHORT gs_palette

;*******
; Pass cursor position and "type"
;   Note that grab ignores these
	call	VDD_State_Get_Cursor_Posn	    ; Get position
	mov	[esi.VDA_EGA_CurX],cx		    ; Set cursor X position
	mov	[esi.VDA_EGA_CurY],ax		    ; Set cursor Y position

; The following calculates the cursor start and end position based on
;	the values output to the registers. Note that the complicated
;	algorithm takes into account several different "features" of
;	varying hardware, including how the cursor appears if END=START
;	and scan lines beyond the max scan line.

	TestMem [edi.VDD_Flags],fVDD_Hide	    ; Q: cursor hidden?
	jnz	SHORT VSGS_None 		    ;	Y: return no cursor
	movzx	eax,[edx.C_CStart]		    ; AX = start scan line
	and	al,1Fh				    ; mask out other bits
	movzx	ecx,[edx.C_CEnd]		    ; CL = end scan line
	and	cl,1Fh				    ; mask out other bits
	mov	ch,[edx.C_MaxScan]		    ; CH = max scan line
	call	VDD_OEM_Adjust_Cursor		    ; Q: Cursor valid?
	jnc	SHORT VSGS_GotCursor		    ;	Y: return scan lines
VSGS_None:
	xor	eax,eax 			    ;	N: return no cursor
	mov	ecx,eax
VSGS_GotCursor:
	mov	[esi.VDA_EGA_CurBeg],ax 	    ; Set start scan line
	mov	ch,ah				    ; zero CH
	mov	[esi].VDA_EGA_CurEnd,cx 	    ; Set end scan line

; Pass palette values
gs_palette:
	mov	eax, dword ptr [edx.A_Pal]
	mov	dword ptr [esi.VDA_EGA_Pal], eax
	mov	eax, dword ptr [edx.A_Pal+4]
	mov	dword ptr [esi.VDA_EGA_Pal+4], eax
	mov	eax, dword ptr [edx.A_Pal+8]
	mov	dword ptr [esi.VDA_EGA_Pal+8], eax
	mov	eax, dword ptr [edx.A_Pal+12]
	mov	dword ptr [esi.VDA_EGA_Pal+12], eax

; check for GEM Ventura special DAC 0 entry
	and	[esi.VDA_EGA_Flags], NOT fVDA_V_InvDAC
	mov	eax, dword ptr [edi.VDD_DAC]
	or	eax, eax
	jz	short gs_notGEM
; DAC zero entry is white instead of black, unusual but used by GEM Ventura
; return flag to indicate first DAC entry is nonzero for GEM Ventura,
; grabber needs to use white for palette entry 0
	or	[esi.VDA_EGA_Flags], fVDA_V_InvDAC
gs_notGEM:

; Return the screen ON/OFF flag
	and	[esi.VDA_EGA_Flags], NOT fVDA_V_ScOff
	test	[edx.A_Indx], fVAI_ScOn 	    ;Q: Is screen off?
	jnz	short gs_6			    ;	N:
	or	[esi.VDA_EGA_Flags], fVDA_V_ScOff   ;	Y: flag screen off
gs_6:
	TestMem [edi.VDD_Flags], fVDD_MInit	    ;Q: VMInit done yet?
	jnz	short gs_MainMemCheck		    ;	Y:
	or	[esi.VDA_EGA_Flags], fVDA_V_ScOff   ;	N: flag screen off
	jmp	short gs_7

gs_MainMemCheck:
	TestMem [edi.VDD_EFlags], fVDE_NoMain	    ;Q: no main mem?
	jz	short gs_7			    ;	N:
	or	[esi.VDA_EGA_Flags], fVDA_V_ScOff   ;	Y: flag screen off

gs_7:
;Return the horizontal cursor tracking flag
	and	[esi.VDA_EGA_Flags], NOT fVDA_V_HCurTrk
	TestMem [edi.VDD_Flags], fVDD_HCurTrk	    ;Q: HCurTrk on?
	jz	short gs_8			    ;	N:
	or	[esi.VDA_EGA_Flags], fVDA_V_HCurTrk ;	Y: set flag
gs_8:
	ret
EndProc VDD_State_Get_State

;******************************************************************************
;VDD_State_Get_Cursor_Posn	 Return current character position
;
;DESCRIPTION:
;	Determine current position from controller state
;
;ENTRY: EDX = VDD_Stt ptr
;
;EXIT:	AX = Current Line for cursor
;	CX = Current Offset within line
;
;USES:	Flags, EAX, ECX
;
BeginProc VDD_State_Get_Cursor_Posn

	push	edx
	movzx	ecx,[edx.C_AddrL]
	mov	ch,[edx.C_AddrH]
	movzx	eax,[edx.C_CAddrL]
	mov	ah,[edx.C_CAddrH]
	sub	eax,ecx 			; EAX = byte offset into cur page
	movzx	ecx,[edx.C_HDisp]
	inc	cl
	xor	edx,edx
	div	cx				; AX = line number, DX = offset
	mov	ecx,edx
	pop	edx
	ret
EndProc VDD_State_Get_Cursor_Posn

;******************************************************************************
;VDD_State_Copy_Ctlr_State
;
;DESCRIPTION:
;	Copies the fields in the VM's VDD_Stt to VDDSttCopy
;
;ENTRY: EBX = VM_Handle
;	EDI -> VDD CB data
;
;EXIT:
;
;USES:	ECX
;
;==============================================================================
BeginProc VDD_State_Copy_Ctlr_State
Assert_VDD_ptrs ebx,edi
	pushfd
	push	esi
	push	edi
	lea	esi,[edi.VDD_Stt]		; ESI = current state ptr
	lea	edi,[edi.VDD_SttCopy]		; EDI = copy of state ptr
	mov	ecx,size Reg_State_struc/4	; ECX = size of state
.ERRNZ size Reg_State_struc mod 4
	cld
	rep movsd
	pop	edi
	pop	esi
	popfd
	ret

EndProc VDD_State_Copy_Ctlr_State


IFDEF DEBUG
;******************************************************************************
;
;   VDD_State_Chk_MemC
;
;   DESCRIPTION:    Debug only event routine that verifies that the MemC owner
;		    is correct and that the VM about to get control only has
;		    video pages mapped if it is the MemC owner.
;
;   ENTRY:	    none
;
;   EXIT:	    none
;
;   USES:	    anything
;
;==============================================================================
BeginProc VDD_State_Chk_MemC

	mov	[VDD_State_MemC_Debug_Event], 0
	cmp	[Vid_MemC_VM], 0
	jne	short debug_memc_ok
	mov	esi, [VDD_State_MemC_Debug_caller]
	Trace_Out 'warning MemC = 0, at return to VM time; set by ?esi'

debug_memc_ok:
	cmp	ebx, [Vid_MemC_VM]
	je	debug_memc_exit
	SetVDDPtr edi
	TestMem [edi.VDD_Flags], fVDD_IOT
	jnz	short @F
	Debug_Out 'VDD: returning to VM #ebx without I/O trapping and not MemC owner'
@@:
	mov	ecx, [ebx.CB_High_Linear]
	shr	ecx, 12
	add	ecx, 0A0h		; high linear page #
	sub	esp, 32*4
	mov	eax, esp
	VMMCall _CopyPageTable,<ecx,32,eax,0>
	mov	esi, esp
	mov	ecx, 16
	cld
dm_lp1:
	lodsd
	test	eax, 1
	jz	short @F
	shr	eax, 12
	cmp	eax, 0A0h
	jb	short @F
	cmp	eax, 0BFh
	jbe	short mapped_page_fnd
@@:
	loop	dm_lp1
	add	esi, 8*4
	mov	cl, 8
dm_lp2:
	lodsd
	test	eax, 1
	jz	short @F
	shr	eax, 12
	cmp	eax, 0A0h
	jb	short @F
	cmp	eax, 0BFh
	jbe	short mapped_page_fnd
@@:
	loop	dm_lp2
debug_memc_exit_w_buf:
	add	esp, 32*4

debug_memc_exit:
	ret

mapped_page_fnd:
	sub	esi, esp
	shr	esi, 2
	add	esi, 0A0h - 1
	Debug_Out 'VDD: returning to VM #ebx with page #si mapped'
	jmp	debug_memc_exit_w_buf


EndProc VDD_State_Chk_MemC


;******************************************************************************
;
;   VDD_State_Schedule_Debug_Event
;
;   DESCRIPTION:    Debug only routine to schedule a global event to ensure
;		    that the video hardware is in the correct state before
;		    returning to a VM.
;
;   ENTRY:	    EAX = caller; VM handle or routine address
;
;   EXIT:	    none
;
;   USES:	    ESI, Flags
;
;==============================================================================
BeginProc VDD_State_Schedule_Debug_Event

	cmp	[VDD_State_MemC_Debug_Event], 0
	jnz	short ssde_exit
	push	eax
	xor	esi, esi
	xchg	esi, [VDD_State_MemC_Debug_TS]
	or	esi, esi
	jz	short @F
	VMMCall Call_When_Task_Switched
@@:
	mov	esi, OFFSET32 VDD_State_Chk_MemC
	VMMCall Schedule_Global_Event
	mov	[VDD_State_MemC_Debug_Event], esi
	pop	eax
	mov	[VDD_State_MemC_Debug_caller], eax
ssde_exit:
	ret

EndProc VDD_State_Schedule_Debug_Event


IFDEF DEBUG_verbose
BeginProc VDD_State_VM_Debug

	or	ebx, ebx
	jnz	short vdm_D00
	Mono_Out '0',noeol
	jmp	short vdm_D01
vdm_D00:
	VMMCall Test_Sys_VM_Handle
	jz	short vdm_D01
	Mono_Out '2',noeol
vdm_D01:
	ret

EndProc VDD_State_VM_Debug

BeginProc VDD_State_Chk_Latches

	pushad
	mov	ebx, [Vid_MemC_VM]
	or	ebx, ebx
	jz	cl_exit
	cmp	ebx, [Vid_Msg_Pseudo_VM]
	je	cl_exit

	VMMCall Get_Next_VM_Handle
	cmp	ebx, [Vid_MemC_VM]
	je	short cl_00
	SetVDDPtr edi
	TestMem [edi.VDD_Flags], fVDD_IOT
	jnz	short cl_00
	Debug_Out "VM #ebx doesn't own MemC, and doesn't have IO trapping enabled"
cl_00:
	mov	ebx, [Vid_MemC_VM]
	SetVDDPtr edi
	push	dword ptr [edi.VDD_Latches]
	call	VDD_State_Save_Latches
	pop	eax
	cmp	eax, dword ptr [edi.VDD_Latches]
	je	short cl_exit
	Debug_Out "latches don't match MemC owner state"
cl_exit:
	popad
	ret

EndProc VDD_State_Chk_Latches


ENDIF


ENDIF


VxD_CODE_ENDS

	END
