	TITLE	VDD - Virtual Display Device for EGA   version 3.10  10/90
;******************************************************************************
;
;VDDSVC - Virtual Display Device Service Routines
;
;   Author: MDW
;
;   (C) Copyright MICROSOFT Corp. 1986-1991
;
;DESCRIPTION:
;
;******************************************************************************

	.386p

DspDrvrRing0Hack = 1	; turn on include of hack to allow display driver to
			; jump into ring 0 to execute time critical code


.xlist
	INCLUDE VMM.INC
	INCLUDE OPTTEST.INC
	INCLUDE VDD.INC
	INCLUDE DEBUG.INC
	INCLUDE VDDDEF.INC
	INCLUDE SHELL.INC
.list

;******************************************************************************
; EXTRN routines
;
VxD_CODE_SEG
	EXTRN	VDD_State_Get_Chgs:NEAR
	EXTRN	VDD_State_Get_State:NEAR
	EXTRN	VDD_State_Save_CRTC_Owner:NEAR
	EXTRN	VDD_State_Copy_Ctlr_State:NEAR
	EXTRN	VDD_State_Set_MemC_Owner:NEAR
	EXTRN	VDD_State_Set_Message_Mode:NEAR
	EXTRN	VDD_State_Clear_Mod_State:NEAR
	EXTRN	VDD_State_Scrn_Off:NEAR
	EXTRN	VDD_State_Scrn_On:NEAR
	EXTRN	VDD_State_Get_Screen_Start:NEAR
	EXTRN	VDD_State_Change_Query:NEAR
	EXTRN	VDD_State_Get_CRTC_Index_Port:NEAR
	EXTRN	VDD_PH_Mem_Set_Sys_Latch_Addr:NEAR
	EXTRN	VDD_VM_Mem_Save_Dirty_State:NEAR
	EXTRN	VDD_Grab_DoGrab:NEAR
	EXTRN	VDD_Grab_Get_Chgs:NEAR
	EXTRN	VDD_Grab_DCopy:NEAR
	EXTRN	VDD_Grab_Clear_Mod_State:NEAR
	EXTRN	VDD_Grab_Get_Text_Copy_Buf:NEAR
	EXTRN	VDD_Grab_Delete_Text_Copy_Buf:NEAR
	EXTRN	VDD_VM_Mem_Change_SaveMem:NEAR
	EXTRN	VDD_VM_Mem_Chk_SaveMem:NEAR
	EXTRN	VDD_OEM_Query_Access:NEAR

	EXTRN	VDD_Int_Set_CanRestore:NEAR

	EXTRN	VDD_Ctl_Set_Focus:NEAR

	EXTRN	VDD_TIO_Set_Trap:NEAR
	EXTRN	VDD_Clr_VM_Time_Out:NEAR
	EXTRN	VDD_Set_VM_Time_Out:NEAR
	EXTRN	VDD_VMDA_Grab:NEAR
	EXTRN	VDD_Update_Window:NEAR
	EXTRN	VDD_VMTimeOut:NEAR

VxD_CODE_ENDS

;******************************************************************************
; EXTRN data
;
VxD_DATA_SEG
	EXTRN Vid_CB_Off:DWORD
	EXTRN Vid_Focus_VM:DWORD
	EXTRN Vid_Flags:DWORD
	EXTRN Vid_PhysA0000:DWORD
	EXTRN Vid_Msg_Pseudo_CB:BYTE
	EXTRN Vid_CRTC_VM:DWORD
	EXTRN Vid_MemC_VM:DWORD
	EXTRN VMB_Str_NoMainMem:BYTE
	EXTRN VMB_Str_NoPagesAvail:BYTE
        EXTRN VMB_Str_NoFGrnd:BYTE
IFDEF MapMonoError
	EXTRN VMB_Str_MapMono:BYTE
ENDIF
	EXTRN VMB_Str_CvtFullScrn:BYTE
	EXTRN VT_Flags:DWORD

PUBLIC Vid_Msg_VM
Vid_Msg_VM	DD  0				; Msg VM handle

PUBLIC Vid_MsgMode_Text_Rows, Vid_MsgMode_Text_Cols
Vid_MsgMode_Text_Rows	dd 0
Vid_MsgMode_Text_Cols	dd 0

PUBLIC Vid_Scrn_Attr
Vid_Scrn_Attr	DB  0				; Screen clear attribute
Vid_Msg_Attr	DB  0				; Msg text mode attribute

PUBLIC PIF_Save
PIF_Save	DW  0				; Pre VM create PIF bits save

PUBLIC Vid_Shadow_Mem_Status_Ptr
Vid_Shadow_Mem_Status_Ptr   DD	0

VxD_DATA_ENDS


VxD_CODE_SEG

BeginDoc
;******************************************************************************
;VDD_Get_Version
;
;DESCRIPTION:
;	Returns version number and device ID.
;
;ENTRY: none
;
;EXIT:	ESI = ptr to 8 byte ID string
;	AH = major version
;	AL = minor version
;
;USES:	flags, AX, ESI
;
;==============================================================================
EndDoc
BeginProc VDD_Get_Version, SERVICE
BeginProc VDD_Get_GrbVersion
.ERRE	VDD_VerNum EQ Grabber_VerNum

	mov	ax,VDD_VerNum			; Pass version number to VMDOSAPP
	mov	esi,OFFSET32 TYPESTRNG
	ret

IFDEF	EGA
TYPESTRNG    db 'VIDEOEGA'
ENDIF
IFDEF	VGA
IFDEF	VGA8514
TYPESTRNG    db 'VIDEOGAD'
ELSE
TYPESTRNG    db 'VIDEOVGA'
ENDIF
ENDIF
EndProc VDD_Get_GrbVersion
EndProc VDD_Get_Version


;******************************************************************************
;
; VDD_Begin_Msg_Mode
;
;DESCRIPTION:
;	This routine is called when a Begin_Message_Mode device control is
;	received. It is followed by a call to the VDD_Msg_ClrScrn routine,
;	which initializes (or sets up an event to initialize) the screen.
;	When the display is finished, an End_Message_Mode device control is
;	made to restore the focus VM's display (focus may change while in
;	message mode, but the screen will not change until End_Message_Mode
;	is called).
;
;ENTRY: EBX = VM handle
;
;EXIT:	none
;
;USES:	flags, EAX, EDX
;
;==============================================================================
EndDoc
BeginProc VDD_Begin_Msg_Mode

	mov	[Vid_Msg_VM], ebx		; owner VM
	clc
	ret

EndProc VDD_Begin_Msg_Mode

;******************************************************************************
;
; VDD_End_Msg_Mode
;
;DESCRIPTION:
;	This routine is called after a sysmodal message box is complete. It
;	restore's the VM's video state.
;
;ENTRY: EBX = VM handle
;
;EXIT:	none
;
;USES:	flags
;
;==============================================================================
BeginProc VDD_End_Msg_Mode

IFDEF	DEBUG
	cmp	[Vid_Msg_VM], 0 		; Q: Message mode?
	jnz	SHORT VEMM_D00			;   Y:
Debug_Out "VDD:End_Msg_Mode not in Msg mode"	;   N:
VEMM_D00:
ENDIF
	cmp	ebx, [Vid_Msg_VM]
IFDEF DEBUG
	je	short VEMM_D01
	push	eax
Debug_Out "VDD:End_Msg_Mode for #ebx when #eax is current owner"
	pop	eax
	jmp	short VEMM_exit
VEMM_D01:
ELSE
	jne	short VEMM_exit
ENDIF

	SetFlag [Vid_Flags], fVid_SysVMI
	jz	short @F
	xor	eax, eax
	VxDCall VDD_Msg_ClrScrn
@@:
	ClrFlag [Vid_Flags], fVid_MsgA
	mov	[Vid_Msg_VM], 0 		; no owner VM

	mov	ebx, [Vid_Focus_VM]
	SetVDDPtr   edi
	call	VDD_Ctl_Set_Focus

VEMM_exit:
	clc
	ret
EndProc VDD_End_Msg_Mode


Assert_Msg_Mode_VM MACRO routine_name
	LOCAL D00, D01
IFDEF	DEBUG
	cmp	[Vid_Msg_VM], 0 		;Q: message mode?
	jne	SHORT D00
Debug_Out "VDD:Msg_&routine_name& not in message mode (vm=#ebx)"
	jmp	SHORT D01

D00:
	cmp	ebx, [Vid_Msg_VM]
	je	SHORT D01
	push	eax
	mov	eax, [Vid_Msg_VM]
Debug_Out "VDD:Msg_&routine_name& req vm #ebx != owner vm #eax"
	pop	eax
D01:
ENDIF
ENDM


BeginDoc
;******************************************************************************
;
; VDD_Msg_ClrScrn
;
;DESCRIPTION:
;	This routine is called to initialize the screen for putting up
;	messages.  It is a service called by the shell.  The screen is
;	cleared immediately.  A Begin_Message_Mode device control call
;	must be issued before this service is utilized.
;
;ENTRY: EBX = VM handle
;	EAX = background attribute
;
;EXIT:	EAX = Width in columns
;	EDX = Height in rows
;
;USES:	flags, EAX, EDX
;
;==============================================================================
EndDoc
BeginProc VDD_Msg_ClrScrn, SERVICE

Assert_Msg_Mode_VM ClrScrn

	pushad
	and	al,07h
	shl	eax,4
	or	al,7
	mov	[Vid_Msg_Attr],al
	mov	[Vid_Scrn_Attr],al

	call	VDD_State_Scrn_Off
	call	VDD_State_Set_Message_Mode	  ; Initialize the screen

; Initialize memory to blanks with attribute of [Vid_Scrn_Attr]
	mov	edi,[Vid_PhysA0000]
	add	edi,0B8000h-0A0000h
	mov	al, ' '
	mov	ah, [Vid_Scrn_Attr]
	mov	ecx, [Vid_MsgMode_Text_Rows]
	mov	edx, [Vid_MsgMode_Text_Cols]
	imul	ecx, edx
	rep stosw

	call	VDD_State_Scrn_On
	popad
	mov	eax, [Vid_MsgMode_Text_Cols]
	mov	edx, [Vid_MsgMode_Text_Rows]
	ret
EndProc VDD_Msg_ClrScrn

BeginDoc
;******************************************************************************
;
; VDD_Msg_ForColor
;
;DESCRIPTION:
;	After calling VDD_Begin_Msg_Mode, this service sets up the forground
;	attribute.
;
;ENTRY: EAX = Color (for EGA/VGA driver, a text mode attribute)
;	EBX = VM handle
;
;EXIT:	none
;
;USES:	flags
;
;==============================================================================
EndDoc
BeginProc VDD_Msg_ForColor, SERVICE

Assert_Msg_Mode_VM ForColor

	push	eax
	and	al,0Fh
	mov	ah,[Vid_Msg_Attr]
	and	ah,0F0h
	or	al,ah
	mov	[Vid_Msg_Attr],al
	pop	eax
	ret
EndProc VDD_Msg_ForColor

BeginDoc
;******************************************************************************
;
; VDD_Msg_BakColor
;
;DESCRIPTION:
;	After calling VDD_Begin_Msg_Mode, this service sets up the
;	background attribute.
;
;ENTRY: EAX = Color (for EGA/VGA driver, a text mode attribute)
;	EBX = VM handle
;
;EXIT:	none
;
;USES:	flags
;
;==============================================================================
EndDoc
BeginProc VDD_Msg_BakColor, SERVICE

Assert_Msg_Mode_VM BakColor

	push	eax
	and	al,07h
	shl	eax,4
	mov	ah,[Vid_Msg_Attr]
	and	ah,0Fh
	or	al,ah
	mov	[Vid_Msg_Attr],al
	pop	eax
	ret
EndProc VDD_Msg_BakColor


BeginDoc
;******************************************************************************
;
; VDD_Msg_TextOut
;
;DESCRIPTION:
;	After calling VDD_Begin_Msg_Mode and setting up the forground and
;	background colors, this service puts character on the screen.
;
;ENTRY: ESI = address of string
;	ECX = length of string
;	EAX = Row start
;	EDX = Column start
;	EBX = VM handle
;
;EXIT:	none
;
;USES:	flags
;
;==============================================================================
EndDoc
BeginProc VDD_Msg_TextOut, SERVICE

Assert_Msg_Mode_VM TextOut

IFDEF DEBUG
	or	ecx, ecx
	jz	SHORT VMTO_Exit
ELSE
	jecxz	SHORT VMTO_Exit
ENDIF

	pushad
	call	VDD_State_Set_Message_Mode	; Make sure we're in message mode

IFDEF DEBUG
	cmp	ecx, [esp.Pushad_ECX]
	je	SHORT VMTO_ecx_ok
	Debug_Out 'Warning VDD_Msg_TextOut: ecx changed in VDD_State_Set_Message_Mode'
	mov	ecx, [esp.Pushad_ECX]
VMTO_ecx_ok:
	cmp	esi, [esp.Pushad_ESI]
	je	SHORT VMTO_no_restore
	Debug_Out 'Warning VDD_Msg_TextOut: esi changed in VDD_State_Set_Message_Mode'
	mov	esi, [esp.Pushad_ESI]
ENDIF

VMTO_no_restore:
	mov	edx,160
	mul	dl
	mov	edx, [esp.Pushad_EDX]
	add	eax,edx
	add	eax,edx
	mov	edi,[Vid_PhysA0000]
	add	edi,0B8000h-0A0000h
	add	edi,eax
	mov	ah,[Vid_Msg_Attr]
        cld
VMTO_00:
	lodsb
	stosw
	loopd	VMTO_00
	popad

VMTO_Exit:
	ret
EndProc VDD_Msg_TextOut


BeginDoc
;******************************************************************************
;
; VDD_Msg_SetCursPos
;
;DESCRIPTION:
;	After calling VDD_Begin_Msg_Mode this routine sets the cursor position.
;
;ENTRY: EAX = Row
;	EDX = Column
;	EBX = VM handle
;
;EXIT:	none
;
;USES:	flags
;
;==============================================================================
EndDoc
BeginProc VDD_Msg_SetCursPos, SERVICE

Assert_Msg_Mode_VM SetCursPos

	push	eax
	push	edx
	call	VDD_State_Set_Message_Mode	  ; Initialize the screen
	cmp	eax, [Vid_MsgMode_Text_Rows]
	jae	SHORT VMSCP_Off
	push	edx
	mov	edx, [Vid_MsgMode_Text_Cols]
	mul	dl
	pop	edx
	add	eax,edx

VMSCP_00:
	call	VDD_State_Get_CRTC_Index_Port	; edx=CRTC index

	push	eax
	mov	al,0Fh
	out	dx,al
	pop	eax
	IO_Delay
	inc	edx
	out	dx,al
	dec	edx
	mov	al,0Eh
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,ah
	out	dx,al
	pop	edx
	pop	eax
	ret
VMSCP_Off:
	or	eax,-1
	jmp	SHORT VMSCP_00
EndProc VDD_Msg_SetCursPos



BeginDoc
;******************************************************************************
;
;   VDD_PIF_State
;
;DESCRIPTION:
;	Informs VDD about PIF bits for VM just created.
;
;ENTRY: EBX = VM handle
;	AX = PIF bits
;
;EXIT:	none
;
;USES:	flags
;
;==============================================================================
EndDoc
BeginProc   VDD_PIF_State, SERVICE

	VMMCall Test_Sys_VM_Handle
	jz	SHORT VPS_PreCreate
	push	edi
	SetVDDPtr   edi
	cmp	[edi.VDD_PIF],ax
	jz	SHORT VPS_Exit
	mov	[edi.VDD_PIF],ax
	call	VDD_TIO_Set_Trap
VPS_Exit:
	pop	edi
	ret
VPS_PreCreate:
	mov	[PIF_Save],ax
	ret
EndProc     VDD_PIF_State

BeginDoc
;******************************************************************************
;
;   VDD_Set_HCurTrk
;
;DESCRIPTION:
;	Sets flag passed to VMDOSAPP indicating that VMDOSAPP should
;	maintain cursor position within display window for this application.
;	This is called by the Keyboard driver when a keyboard interrupt
;	is simulated into a VM.
;
;ENTRY: EBX = VM handle
;
;EXIT:	none
;
;USES:	flags
;
;==============================================================================
EndDoc
BeginProc   VDD_Set_HCurTrk,SERVICE
	push	ebx
	add	ebx,[Vid_CB_Off]
	SetFlag [ebx.VDD_Flags],fVDD_HCurTrk
	pop	ebx
	ret
EndProc     VDD_Set_HCurTrk

BeginDoc
;******************************************************************************
;
;   VDD_Get_GrabRtn
;
;DESCRIPTION:
;	Returns address of video grab routine. The grab routine is called
;	by the SHELL device when the appropriate hot key is pressed by the
;	user. It makes a copy of the visible screen and controller state
;	of the current VM. That copy is then accessible via VDD_Get_GrbState
;	and VDD_Get_GrbMem services.
;
;ENTRY: none
;
;EXIT:	ESI = address of grab routine
;
;USES:	flags, ESI
;
;==============================================================================
EndDoc
BeginProc   VDD_Get_GrabRtn, SERVICE

	mov	esi,OFFSET32 VDD_Grab
	ret
EndProc     VDD_Get_GrabRtn


;******************************************************************************
;
;   VDD_Grab
;
;   DESCRIPTION:    Attempt to grab a copy of the VM's screen and controller
;		    state and schedule an event for VMDOSAPP.  If unsupported
;		    mode or memory cannot be allocated, then nothing is done.
;
;   ENTRY:	    EBX = VM handle
;
;   EXIT:	    none
;
;   USES:	    anything
;
;==============================================================================
BeginProc VDD_Grab

	SetVDDPtr edi
	call	VDD_State_Save_CRTC_Owner
	call	VDD_Grab_DoGrab 	    ;Q: grab done?
	jc	short grb_exit		    ;	N: just return
	call	VDD_State_Copy_Ctlr_State
	call	VDD_VMDA_Grab
grb_exit:
	ret
EndProc VDD_Grab


BeginDoc
;******************************************************************************
;VDD_Hide_Cursor    Hide/Show cursor in a window
;
;DESCRIPTION:
;	If EAX is non zero, sets a hide cursor flag else clears the flag.
;	This is so that, if the mouse is using a hardware cursor, it can
;	turn off that cursor while the VM is windowed(since the VM will
;	no longer own the mouse).
;
;ENTRY: EAX = 0 if cursor SHOULD be displayed in a window
;	   != 0 if cursor SHOULD NOT be displayed in a window
;	EBX = control block pointer
;
;EXIT:	none
;
;USES:	Flags
;
;==============================================================================
EndDoc
BeginProc VDD_Hide_Cursor, SERVICE

	push	edi
	mov	edi,ebx
	add	edi,[Vid_CB_Off]
Assert_VDD_ptrs ebx,edi
	ClrFlag [edi.VDD_Flags], fVDD_Hide	; assume show cursor
	or	eax,eax                         ; Q: Assumption correct?
	jz	SHORT VHC_Exit                  ;   Y:
	SetFlag [edi.VDD_Flags],fVDD_Hide	;   N: Hide the cursor
; Force cursor change on the next window update event
	mov     WORD PTR [edi.VDD_SttCopy.C_CAddrH], 0FFFFh 
VHC_Exit:
	pop	edi
	ret
EndProc VDD_Hide_Cursor



BeginDoc
;******************************************************************************
;VDD_Query_Access
;
;DESCRIPTION:
;	If the VM were to access its video memory now, would the VDD be
;	able to handle it?  Some devices, such as the Mouse device would
;	like to call software in the VM that will access the video.  However,
;	if this will cause a video display error, it would be better to
;	let the side affect occur rather than generate the error (in the
;	case of the mouse, the mouse cursor will be left on when the
;	VM is displayed in a window).  This call should only be done
;	just before returning to the VM in question (i.e. in a VM Event)
;	since subsequent setfocus calls may make the result incorrect.
;
;ENTRY: EBX = control block pointer
;
;EXIT:	CF = 0 if video access is OK.
;
;USES:	Flags
;
;==============================================================================
EndDoc
BeginProc VDD_Query_Access, SERVICE

	pushad
	mov	edx,ebx
	mov	ebx,[Vid_CRTC_VM]
	SetVDDptr edi
	clc
	call	VDD_OEM_Query_Access
	popad
	ret
EndProc VDD_Query_Access



BeginDoc
;******************************************************************************
;Displaying VM's video memory in a window
;
;   Parameter passing
;	There are several services supplied in order to efficiently render
;	a VM's video memory into a window. These routines are called by the
;	grabber. Since the grabber runs in a virtual machine, parameters
;	are passed in the Client registers and in VM memory pointed to by
;	the Client registers. Other services available use protect mode
;	registers.
;
;   Updating windowed VMs
;	The first step is for the SHELL to call Set_VMType with a parameter
;	indicating that the VM is to be windowed. When the VM is no longer
;	windowed, Set_VMType is called again. When the VMState is not
;	windowed, the Get_Mod call will always return no changes and the
;	video update message will never be generated.
;
;	Note that when a VM's video state changes, including controller state
;	changes such as cursor movement and memory modification, the VDD will
;	send VMDOSAPP a display update message. All the changes made to the
;	video state will accumulate and be reported by Get_Mod until a
;	Clear_Mod call is made. There will only be one display update
;	message per Clear_Mod call.  Also note that immediately after
;	a mode change, the Update message is delayed to allow the application
;	to do a series of mode changes before things settle down.
;
;==============================================================================
EndDoc

BeginDoc
;******************************************************************************
;
;   VDD_Set_VMType
;
;DESCRIPTION:
;	This service is used to inform the VDD of a VM's type. The parameter
;	explicitly passed is the Windowed flag. Implicitly passed are the
;	VM status flags, Exclusive and Background. This should be called
;	prior to running the VM and each time thereafter that any of the
;	VM paramaters are modified. Note that for a system critical Set_Focus
;	this routine may not be called before the Set_Focus. In that case,
;	the VDD is responsible for doing an implied Set_VMType(not windowed).
;
;ENTRY: EAX = state flag (= non zero if changing to windowed VM)
;	EBX = VM handle whose state is to change
;
;EXIT:	none
;
;USES:	flags
;
;==============================================================================
EndDoc
BeginProc VDD_Set_VMType, SERVICE

;;Trace_Out "Set VM #EBX to type #EAX"
; Set Windowed flag, set up VM for new type
	pushad
	SetVDDPtr edi
	SetFlag [edi.VDD_Flags], fVDD_Win	; assume making windowed
	mov	[edi.VDD_Mod_Rect],-1		; look at everything!
	or	eax, eax			;Q: Windowed?
	jnz	SHORT VST_Window		;   Y: Assumption correct
	ClrFlag [edi.VDD_Flags], fVDD_Win	;   N: Clear windowed flag
	call	VDD_Grab_Delete_Text_Copy_Buf	;	 Get rid of copy buf
	call	VDD_Clr_VM_Time_Out		; Cancel previous timeout
	TestMem [edi.VDD_Flags], fVDD_CanRestore;Q: VM can restore screen?
	jz	short VST_notw_00		;   N:
	call	VDD_Int_Set_CanRestore		;   Y: redo CanRestore enabling
VST_notw_00:
	popad
	ret

; Windowed VM
VST_Window:
	btr	[edi.VDD_Flags], bVDD_NoSaveRes ;Q: VM has save mem?
	jnc	short VST_w_00			;   Y: don't need to do anything
	call	VDD_VM_Mem_Change_SaveMem
VST_w_00:
    ;
    ; When windowed from FS VM, force cursor tracking in the window by 
    ; setting up an update event(which has the cursor change).
    ;
						; Force scrn update
	mov	[edi.VDD_Mod_Flag_Save],fVDD_M_Ctlr+fVDD_M_Curs
	SetFlag [edi.VDD_Flags],fVDD_HCurTrk	; Force Hor. cursor trk
	call	VDD_Update_Window		; update event to track cursor
	popad
	ret
EndProc VDD_Set_VMType

BeginDoc
;*****************************************************************************
;
;
;   VDD_Check_Update_Soon
;
;DESCRIPTION:
;	This service can be used by VxDs to direct the VDD to check for 
;	updates soon. This service is useful only for windowed dos apps.
;	VxDs should call this service in response to user actions which
;	generally generate a change in the display of apps. eg. the VDD
;	can call this service when it detects a key press/release etc.
;
;ENTRY: EBX = VM handle
;
;EXIT: NONE
;
;USES: NONE
;
;******************************************************************************
EndDoc
BeginProc VDD_Check_Update_Soon, SERVICE
	pushad
	SetVDDPtr edi
	cmp	[edi.VDD_Recent_User_Action],1	; always 0/1
	jz	SHORT SkipClrVmTimeOut		; small timeout already sched.
	testMem	[edi.VDD_Flags],fVDD_Win	; skip when not windowed
	jz	SHORT SkipClrVmTimeOut
	call	VDD_Clr_VM_Time_Out		; clear the timeout
	mov	eax,5
	mov	edx,edi
	mov	esi,OFFSET32 VDD_VMTimeOut
	VMMCall Set_VM_Time_Out 		; Set display update timeout
	mov	[edi.VDD_Time_Out_Handle],esi	; Save timeout handle
	inc	[edi.VDD_Recent_User_Action]	; either 0/1
	mov	[edi.VDD_Check_Upd_Soon],4
SkipClrVmTimeOut:
	popad
	ret
EndProc VDD_Check_Update_Soon

BeginDoc
;******************************************************************************
;
;   VDD_Get_ModTime
;
;DESCRIPTION:
;	This routine is used to determine if any video activity has occured.
;	The poll device uses it to determine if the VM is idle.
;
;ENTRY: EBX = VM handle
;
;EXIT:	EAX = System Timer at last video modification
;
;USES:	Flags, EAX
;
;==============================================================================
EndDoc
BeginProc VDD_Get_ModTime, SERVICE

IFDEF debug_verbose
	Trace_Out 'm',noeol
ENDIF
	pushad
	SetVDDPtr edi
	TestMem [edi.VDD_Flags],fVDD_ModeChange ; Q: In middle of mode set?
	jz	SHORT VGMT_01			;   N: Check last mem access
VGMT_00:
	VMMCall Get_Last_Updated_System_Time	;   Y: Video busy right now
IFDEF	RECTDEBUG
Trace_Out "i",NOEOL
ENDIF
	jmp	SHORT VGMT_Ex
VGMT_01:
	call	VDD_State_Change_Query		; Q: Windowed update pending?
	jc	SHORT VGMT_00			;   Y: Video busy right now
IFDEF debug_verbose
	mov	esi, [edi.VDD_ModTime]
ENDIF
	call	VDD_VM_Mem_Save_Dirty_State	; updates VDD_ModTime, if changes
	mov	eax, [edi.VDD_ModTime]		; EAX = last time video mod'd
IFDEF debug_verbose
	cmp	eax, esi
	jne	short VGMT_Ex
	Trace_Out '=',noeol
ENDIF
VGMT_Ex:
	mov	[esp.Pushad_EAX], eax
	popad
	ret
EndProc VDD_Get_ModTime


;******************************************************************************
;
;   VDD_PM_API
;
;DESCRIPTION:
;	This routine dispatches to the various service routines required
;	by the grabber.  It is called only by the grabber in the SYS VM.
;
;ENTRY: EBX = Current VM handle = SYS VM handle
;	EBP = Client stack frame ptr
;	Client_EBX = VM Handle (except for function 0, get version)
;	Client_AX = Device function
;
;EXIT:	dispatch to API service routines
;
;USES:	flags, EAX, EBX, ECX, EDX, ESI, EDI
;
;==============================================================================
BeginProc VDD_PM_API

	VMMCall Test_Sys_VM_Handle
IFDEF	DEBUG
	jz	SHORT VPA_D00
Debug_Out   "VDD:API call made by VM #EBX, non system VM"
VPA_D00:
ENDIF
	jnz	SHORT VPA_Exit
	movzx	ecx,[ebp.Client_AX]
	cmp	cl,GRB_Unlock_APP
	ja	SHORT VPA_not_grabber
; Get VM pointers for VM
	mov	edx,ebx 			; EDX = SYS VM handle
	or	ecx,ecx
	jz	SHORT VPA_00
	mov	ebx,[ebp.Client_EBX]		; EBX = other VM's handle
	mov	edi,ebx
	add	edi,[Vid_CB_Off]
	VMMCall Validate_VM_Handle
VPA_00:
	jmp	DWORD PTR Grb_JumpTable[ecx*4]

VPA_not_grabber:

IFDEF DspDrvrRing0Hack
	cmp	cl,Private_DspDrvr_1
	je	VDD_Init_DspDrv_Ring0
ENDIF
	cmp	cl, DspDrvr_Version
	je	VDD_SVC_Dsp_Version
	cmp	cl, DspDrvr_Addresses
	je	VDD_SVC_Set_Addresses

VPA_Exit:
	ret

GrbEntry MACRO svcnum, label
.erre svcnum*4 EQ $-Grb_JumpTable
	dd  OFFSET32 label
ENDM

;VDD virtual mode services for the grabber
Grb_JumpTable	LABEL DWORD
GrbEntry GRB_Get_Version, VDD_Grb_Version    ; Get version number and ID string ptr
GrbEntry GRB_Get_Mem,	  VDD_Get_Mem	     ; Get selector and map to video memory
GrbEntry GRB_Get_State,   VDD_Get_State      ; Get video state
GrbEntry GRB_Get_Mod,	  VDD_Get_Mod	     ; Get state changes
GrbEntry GRB_Clear_Mod,   VDD_Clear_Mod      ; Clear state change accumulation
GrbEntry GRB_Free_Mem,	  VDD_Free_Mem	     ; Free memory
GrbEntry GRB_Get_GrbMem,  VDD_Get_GrbMem     ; Get selector and map to video grab mem
GrbEntry GRB_Free_Grab,   VDD_Free_Grab      ; Free grab memory and controller state
GrbEntry GRB_Get_GrbState,VDD_Get_GrbState   ; Get grab video state
GrbEntry GRB_Unlock_APP,  VDD_Unlock_APP     ; Unlock the APP

EndProc VDD_PM_API

;******************************************************************************
;VDD_Grb_Version
;
;DESCRIPTION:
;	This routine dispatches to the various service routines required
;	by the grabber.  It is called only by the grabber in the SYS VM.
;
;ENTRY: EBX = Current VM handle = SYS VM handle
;	EBP = Client stack frame ptr
;	Client ES:EDI = buffer to store 8 byte name
;
;EXIT:	Client EAX = Version information
;
;USES:	flags, EAX, EBX, ECX, EDX, ESI, EDI
;
;==============================================================================
BeginProc VDD_Grb_Version

	call	VDD_Get_GrbVersion
	mov	[ebp.Client_EAX],eax	; Pass version number to grabber
	movzx	edi,[ebp.Client_ES]	; Get create structure segment
	push	edx
	VMMCall _SelectorMapFlat,<edx,edi,0>
	pop	edx
	inc	eax
IFDEF DEBUG
	jnz	short VGV_D00
Debug_Out "SelectorMapFlat failed VDD_Grb_DeviceVersion"
VGV_D00:
ENDIF
	jz	SHORT VGV_Exit
	dec	eax
	mov	edi,eax
	add	edi,[ebp.Client_EDI]	; EDI -> Target Buffer for version string
	cld
	movsd				; Copy 8 byte name
	movsd
VGV_Exit:
	ret
EndProc VDD_Grb_Version

BeginDoc
;******************************************************************************
;VDD_Get_State, VDD_Get_GrbState
;
;DESCRIPTION:
;	These routines are called by the grabber. Since the grabber is a
;	virtual machine piece of code, all parameters exist on the stack
;	in the Client registers. These routines return a video state
;	structure (see VDD.INC). The Get_GrbState version of the
;	routine returns the state of the video for the VM specified at the
;	point when the GrabRtn was called. The Get_State version of the
;	routine returns the current state of the VM. The Get_State routine
;	should be called after the Get_Mem call, before the Free_Mem call.
;
;	Note that a state structure size of zero, returned in CX,
;	indicates an error.
;
;ENTRY: EDX = Sys VM handle
;	IF CF = 1, call was made with invalid VM Handle
;	EBX = VM handle of VM for whom call is made
;	EDI = VDD CB ptr
;	EBP = Client stack frame ptr
;	Client_ES:Client_EDI = SELECTOR:OFFSET of buffer to store state structure
;	Client_EBX = VM Handle
;	Client_CX = size of buffer to hold state structure (DEBUG ONLY!)
;
;EXIT:	Client_SI = size of state structure returned (DEBUG ONLY!)
;	State structure saved in buffer indicated
;
;USES:	flags, Client_CX
;
;==============================================================================
EndDoc

BeginProc VDD_Get_GrbState
IFDEF CPDEBUG
	pushad
	mov	ax,[ebp.Client_CS]
	mov	cx,[ebp.Client_IP]
Trace_Out "Get_State at #AX:#CX"
	popad
ENDIF
	jc	SHORT VGS_Err0
	clc
	jmp	SHORT VGS_Start
EndProc VDD_Get_GrbState

BeginProc VDD_Get_State

	jc	SHORT VGS_Err0
	stc
VGS_Start:
	pushfd

;*******
; Verify parameters
IFDEF	DEBUG
	cmp	[ebp.Client_CX],SIZE VDA_EGA_State ; Q: State buffer big enough?
	jnc	SHORT VGS_D02
	mov	ax,[ebp.Client_CX]
Debug_Out   "VDD:Get_State buffer too small, is #AX"
VGS_D02:
	jb	SHORT VGS_Error 		;   N: return no changes
	mov	[ebp.Client_CX],SIZE VDA_EGA_State ; Set size of state returned
ENDIF

;*******
; Get address of buffer to return state information
	push	edx
	movzx	esi,[ebp.Client_ES]		; Get state structure selector
	VMMCall _SelectorMapFlat,<edx,esi,0>
	pop	edx
	inc	eax
IFDEF DEBUG
	jnz	short VGS_D03
	debug_out "VDD: SelectorMapFlat failed for Get_State"
VGS_D03:
ENDIF
	jz	SHORT VGS_Error
	dec	eax
	add	eax,[ebp.Client_EDI]
	mov	esi,eax 			; ESI -> State VM structure

;*******
; Set the state structure(windowed VM's main state, grabbed VM's copy state)
	popfd					; CF = 1 indicates main state
	jmp	VDD_State_Get_State		; Build state structure at ESI

;*******
; Set the state structure to zero length on error
VGS_Err0:
	pushfd
VGS_Error:
	xor	eax,eax
	mov	[ebp.Client_ECX],eax
	popfd
	ret
EndProc VDD_Get_State


BeginDoc
;******************************************************************************
;VDD_Get_Mod
;
;DESCRIPTION:
;	This routine is called to get changes in a VM's video state.
;	The changes are passed to the grabber in a buffer that includes
;	a flag indicating what kind of changes occured and what type of
;	a memory change list follows. The flag is followed by a count of
;	memory change list entries and the change list itself. Note that
;	a change structure size of zero, returned in CX, indicates an error.
;
;	This routine will return cumulative changes until Clear_Mod is called.
;
;ENTRY: EDX = Sys VM handle
;	IF CF = 1, call was made with invalid VM Handle
;	EBX = VM handle of VM for whom call is made
;	EDI = VDD CB ptr
;	Client_ES:Client_EDI = SELECTOR:OFFSET of buffer to store chgs structure
;	Client_EBX = VM Handle
;	Client_CX = size of buffer to hold changes structure (DEBUG ONLY!)
;
;EXIT:	Client_CX = size of change structure returned (DEBUG ONLY!)
;	Client_AX = location (bottom,right)
;	Client_BX = (top,left)
;	Client_DX = A_Mode
;	Changes structure saved in buffer indicated
;
;USES:	flags, Client_CX, Client_AX, Client_BX
;
;==============================================================================
EndDoc

BeginProc VDD_Get_Mod
	jc	DEBFAR VGM_No_Buff_Error
IFDEF CPDEBUG
	pushad
	mov	ax,[ebp.Client_CS]
	mov	cx,[ebp.Client_IP]
Trace_Out "Get_Mod at #AX:#CX"
	popad
ENDIF
IFDEF RECTDEBUG
Queue_Out "VDD: Get_Mod"
ENDIF
IFDEF	DEBUG
	cmp	[ebp.Client_CX],SIZE VDD_Mod_State
	jnc	SHORT VGM_D01
	mov	ax,SIZE VDD_Mod_State
	mov	cx,[ebp.Client_CX]
Debug_Out   "VDD:Get_Mod buffer too small, is #CX, need #AX"
	jmp	VGM_No_Buff_Error
VGM_D01:
ENDIF

; Get address of buffer to return state information
	push	edx
	movzx	esi,[ebp.Client_ES]		; Get state structure selector
	VMMCall _SelectorMapFlat,<edx,esi,0>
	pop	edx
	inc	eax
IFDEF DEBUG
	jnz	short VGM_D02
	debug_out "VDD: SelectorMapFlat failed for Get_Mod"
VGM_D02:
ENDIF
	jz	SHORT VGM_No_Buff_Error
	dec	eax
	add	eax,[ebp.Client_EDI]
	mov	esi,eax 			; ESI -> State VM structure

;;;	call	VDD_Suspend_NormSch		; Lock the APP on Get_Mod call

;
; check for special cases.
;
	call	VDD_VM_Mem_Chk_SaveMem
	jc	SHORT VGM_NoMain		; jump, if not enough main mem
	TestMem [edi.VDD_Flags],fVDD_MInit	; Q: VMInit done yet?
	jz	SHORT VGM_NoChg 		;   Y: Report no changes
;
; During a mode change report no changes - avoids screen size bounce
;
	TestMem [edi.VDD_Flags],fVDD_ModeChange ; Q: During mode change?
	jnz	SHORT VGM_NoChg 		;   Y: Report no changes

	call	VDD_State_Get_Chgs		; Build controller changes struc
	call	VDD_Grab_Get_Chgs		; Build memory changes struc
VGM_Ex: 					; ecx = # of bytes in VDD_Mod_List
	add	ecx, VDD_Mod_List		; add size of VDD_Mod_Flag &
						;   VDD_Mod_Count fields
.erre VDD_Mod_List GT VDD_Mod_Flag
.erre VDD_Mod_List GT VDD_Mod_Count
VGM_Ex_No_Mod:
	mov	[ebp.Client_CX],cx		; Return length of change buf
	mov	ecx,0FFFF0000h			; zero out the rect
	xchg	ecx,[edi.VDD_Mod_Rect]		; modified rect here.
	mov	[ebp.Client_BX],cx		; return (a,b)
	shr	ecx,16
	mov	[ebp.Client_AX],cx		; return (c,d)
	movzx	cx,[edi.VDD_Stt.A_Mode]
	mov	[ebp.Client_DX],cx
	ret

VGM_NoChg:
	xor	eax,eax
	jmp	SHORT VGM_NoList

VGM_NoMain:
	push	esi
	call	VDD_Error_NoMainMem
	pop	esi
	mov	eax,fVDD_M_Err
VGM_NoList:
	xor	ecx, ecx
	mov	[esi.VDD_Mod_Flag],ax		; Save state change flags
	mov	[esi.VDD_Mod_Count],cx
	jmp	VGM_Ex

VGM_No_Buff_Error:
	xor	ecx, ecx
	jmp	VGM_Ex_No_Mod

EndProc VDD_Get_Mod

BeginDoc
;******************************************************************************
;VDD_Clear_Mod
;
;DESCRIPTION:
;	This routine is called to clear the change state of a VM.
;
;ENTRY: EDX = Sys VM handle
;	IF CF = 1, call was made with invalid VM Handle
;	EBX = VM handle of VM for whom call is made
;	EDI = VDD CB ptr
;
;EXIT:	none
;
;USES:	flags
;
;==============================================================================
EndDoc

BeginProc VDD_Clear_Mod
	jc	SHORT VCM_Exit
IFDEF CPDEBUG
	pushad
	mov	ax,[ebp.Client_CS]
	mov	cx,[ebp.Client_IP]
Trace_Out "Clr_Mod at #AX:#CX"
	popad
ENDIF
IFDEF RECTDEBUG
Queue_Out "VDD: Clear_Mod"
ENDIF
	call	VDD_State_Clear_Mod_State	; Clear ctlr changes
	call	VDD_Grab_Clear_Mod_State	; Clear memory changes
VCM_Exit:
	ret
EndProc VDD_Clear_Mod

BeginDoc
;******************************************************************************
;VDD_Get_Mem, VDD_Get_GrbMem
;
;DESCRIPTION:
;	Return flat address and allocation bit map for VM's video memory.
;
;	The main difference between these two routines is that Get_Mem
;	returns the main video save memory and Get_GrbMem a copy of the
;	memory that was made by VDD_Grab. An addional important difference
;	is that Get_Mem boosts the scheduling priority of the system VM, as
;	mentioned below.
;
;	In order to assure that the memory does not change from the point
;	that Get_Mem is called until Free_Mem is called, we will
;	boost the system VM's priority by a Low_Priority_Device_Boost.
;	This will inhibit normal scheduling but will not hamper scheduling
;	of VM's to handle events such as interrupts.
;
;	THE ALLOCATION OF MEMORY TO THE BIT MAP IS DYNAMIC. The grabber
;	must make this call each time that it wants to access the memory.
;
;	Get_Mem call MUST BE FOLLOWED by a Free_Mem call AS SOON AS POSSIBLE.
;	No other VM's will be scheduled until the Free_Mem call is made.
;
;	If the client buffer is not big enough or the selector is bad or if
;	GrbMem is called when no grab is active, an error return will be done,
;	that is, Client SI = 0.
;
;ENTRY: EDX = Sys VM handle
;	IF CF = 1, call was made with invalid VM Handle
;	EBX = VM handle of VM for whom call is made
;	EDI = VDD CB ptr
;	EBP = Client stack frame ptr
;	Client_EBX = VM Handle
;	Client_ES:Client_EDI = SELECTOR:OFFSET of buffer to store VDA_Mem_State
;	Client_CX = size of buffer to hold VDA_Mem_State (DEBUG ONLY!)
;
;EXIT:	Mem structure modified for current state of memory
;	Client_CX = size of structure (=0 if error)
;	Client_DX = Attribute mode controller register value
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
EndDoc

BeginProc VDD_Get_Mem
	jc	SHORT VGMm_Error
IFDEF CPDEBUG
	pushad
	mov	ax,[ebp.Client_CS]
	mov	cx,[ebp.Client_IP]
Trace_Out "Get_Mem at #AX:#CX"
	popad
ENDIF
IFDEF RECTDEBUG
Queue_Out "VDD_Get_Mem"
ENDIF

	inc	[edi.VDD_Get_Mem_Count]		; one more call to Get_Mem

	cmp	[edi.VDD_Stt.V_BIOSMode],0Dh
	jb	SHORT TimeAlreadySet
	xchg	edx,ebx				; get sys_vm handle
	VMMCall	Get_VM_Exec_Time		; get exec time for sysVM
	mov	[edi.VDD_Upd_Start], eax        ; Store as start time for 
                                                ; window update
	xchg	edx,ebx
TimeAlreadySet:

	lea	esi, [edi.VDD_MSTT]		; ESI = VM's Mem state ptr
	call	VGMm_Set_Struc			; Pass the structure
	jc	SHORT VGMm_Exit
	call	VDD_Suspend_NormSch

VGMm_Exit:
	ret
VGMm_Error:
	mov	[ebp.Client_CX],0		; Return length of change buf
	ret
EndProc VDD_Get_Mem

BeginProc VDD_Get_GrbMem

	jc	SHORT VGMm_Error
	lea	esi,[edi.VDD_MSTTCopy]		; ESI = VM's copy Mem state ptr
	cmp	[esi.MSS_plane0.MSS_plane_addr], 0 ;Q: copy mem alloc'ed?
	jnz	SHORT VGMm_Set_Struc
	lea	esi,[edi.VDD_MSTT]		; ESI = VM's save Mem state ptr
	Assumes_Fall_Through VGMm_Set_Struc
EndProc VDD_Get_GrbMem

;******************************************************************************
;VGMm_Set_Struc
;
;DESCRIPTION: Copy memory state structure to client buffer, including addresses
;	for each of the planes and size of each of the four planes (zero size
;	for planes not allocated).
;
;ENTRY: EDX = Sys VM handle
;	EBX = VM handle of VM for whom call is made
;	EDI = VDD CB ptr
;	EBP = Client stack frame ptr
;	ESI -> Mem_State_Struc
;	Client_EBX = VM Handle
;	Client_CX = size of buffer to hold mem structure
;	Client_ES:Client_EDI = SELECTOR:OFFSET of buffer to store mem structure
;
;EXIT:	Mem structure copied to client buffer
;	Client_ECX = size of structure copied (=0 and CF=1 if error)
;	Client_DX = Attribute controller register 10h
;USES:	Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VGMm_Set_Struc

	movzx	eax,[edi.VDD_Stt.A_Mode]
	mov	[ebp.Client_DX],ax		; return

	push	edi
IFDEF	DEBUG
	cmp	[ebp.Client_CX],SIZE VDA_Mem_State
	jnc	SHORT VGMm_D01
	mov	ax,SIZE VDA_Mem_State
	mov	cx,[ebp.Client_CX]
Debug_Out   "VDD:Get_Mem buffer too small, is #CX, need #AX"
VGMm_D01:
	jc	VGMmS_Error
ENDIF
	mov	[ebp.Client_CX],SIZE VDA_Mem_State ; Set size of buff returned
	movzx	eax,[ebp.Client_ES]		; Get state structure selector
	push	edx
	VMMCall _SelectorMapFlat,<edx,eax,0>
	pop	edx
	inc	eax
IFDEF DEBUG
	jnz	short VGMm_D02
	debug_out "VDD: SelectorMapFlat failed for Get_Mem"
VGMm_D02:
ENDIF
	jz	SHORT VGMmS_Error
	dec	eax
	add	eax,[ebp.Client_EDI]

	lea	ecx, [edi.VDD_DAC]
	mov	[eax.VDA_Mem_DACOff],ecx

IFDEF	CPDEBUG
Trace_Out "Get Vid Selector: "
ENDIF
	mov	ecx, [esi.MSS_plane0.MSS_plane_addr]
	mov	[eax.VDA_Mem_Addr_P0], ecx
IFDEF	CPDEBUG
Trace_Out "Plane 0: @#ECX, for ", nocrlf
ENDIF
	movzx	ecx, [esi.MSS_plane0.MSS_plane_size]
	shl	ecx,12
	mov	[eax.VDA_Mem_Size_P0], ecx
IFDEF	CPDEBUG
Trace_Out "#ECX bytes"
ENDIF
	test	[edi.VDD_Stt.G_Misc],fGrp6Char	    ;Q: graphics mode?
	jz	SHORT VGMmS_text		    ;	N: return text struc
	mov	ecx, [esi.MSS_plane1.MSS_plane_addr]
	mov	[eax.VDA_Mem_Addr_P1], ecx
IFDEF	CPDEBUG
Trace_Out "Plane 1: @#ECX, for ", nocrlf
ENDIF
	movzx	ecx, [esi.MSS_plane1.MSS_plane_size]
	shl	ecx,12
	mov	[eax.VDA_Mem_Size_P1], ecx
IFDEF	CPDEBUG
Trace_Out "#ECX bytes"
ENDIF

	mov	ecx, [esi.MSS_plane2.MSS_plane_addr]
	mov	[eax.VDA_Mem_Addr_P2], ecx
IFDEF	CPDEBUG
Trace_Out "Plane 2: @#ECX, for ", nocrlf
ENDIF
	movzx	ecx, [esi.MSS_plane2.MSS_plane_size]
	shl	ecx,12
	mov	[eax.VDA_Mem_Size_P2], ecx
IFDEF	CPDEBUG
Trace_Out "#ECX bytes"
ENDIF

	mov	ecx, [esi.MSS_plane3.MSS_plane_addr]
	mov	[eax.VDA_Mem_Addr_P3], ecx
IFDEF	CPDEBUG
Trace_Out "Plane 3: @#ECX, for ", nocrlf
ENDIF
	movzx	ecx, [esi.MSS_plane3.MSS_plane_size]
	shl	ecx,12
	mov	[eax.VDA_Mem_Size_P3], ecx
IFDEF	CPDEBUG
Trace_Out "#ECX bytes"
ENDIF
VGMmS_Finish:
	push	eax
	call	VDD_State_Get_Screen_Start
	pop	edi
	mov	[edi.VDA_Mem_DPagOff], eax
	pop	edi
	clc
	ret

VGMmS_Error:
	xor	eax, eax
	mov	[ebp.Client_CX], ax		    ; Save size of buf returned
	pop	edi
	stc
	ret

VGMmS_text:
; Pass copy buffer address to grabber
	push	esi
	push	edx
	push	eax
	call	VDD_Grab_Get_Text_Copy_Buf
	pop	eax
.ERRE	VDA_Mem_Addr_P1 EQ VDA_Mem_Addr_Win_State
	mov	[eax.VDA_Mem_Addr_P1], edx
	shl	ecx,12
.ERRE	VDA_Mem_Size_P1 EQ VDA_Mem_Size_Win_State
	mov	[eax.VDA_Mem_Size_P1],ecx
IFDEF	CPDEBUG
Trace_Out "Text copy buffer (plane 1): @#EDX, for #ECX bytes"
ENDIF
	pop	edx
	pop	esi

; Pass font to grabber, just for fun
	mov	ecx, [esi.MSS_plane2.MSS_plane_addr]
	mov	[eax.VDA_Mem_Addr_P2], ecx
IFDEF	CPDEBUG
Trace_Out "Font (plane 2): @#ECX, for ", nocrlf
ENDIF
	movzx	ecx, [esi.MSS_plane2.MSS_plane_size]
	shl	ecx,12
	mov	[eax.VDA_Mem_Size_P2],ecx
IFDEF	CPDEBUG
Trace_Out "#ECX bytes"
ENDIF
	mov	[eax.VDA_Mem_Size_P3],0
IFDEF	CPDEBUG
Trace_Out "Plane 3: (not defined, length 0)"
ENDIF
	jmp	VGMmS_Finish

EndProc VGMm_Set_Struc


;******************************************************************************
;VDD_Suspend_NormSch
;
;   DESCRIPTION:
;
;   ENTRY:	    EDX = SYS VM handle
;		    EDI = CB ptr for VM being Locked
;
;   EXIT:
;
;   USES:	    EAX, Flags
;
;==============================================================================
BeginProc VDD_Suspend_NormSch

IFDEF RECTDEBUG
Queue_Out "VDD_Suspend_NormSch"
ENDIF
        push    ebx
        push    edi

	mov	ebx, edx
	mov	edi, ebx
	add	edi, [Vid_CB_Off]
	bts	[edi.VDD_Flags], bVDD_Boost	; Q: SYS VM Boosted already?
	jc	SHORT VNS_Exit                  ;   Y: 

	mov	eax, VDD_Pri_Device_Boost	; Boost SYS VM
	VMMCall Adjust_Exec_Priority
VNS_Exit:
        pop     edi
        pop     ebx
	ret
EndProc VDD_Suspend_NormSch


BeginDoc
;******************************************************************************
;VDD_Free_Grab
;
;DESCRIPTION:
;	This routine is used to release the copy of the video memory that
;	was allocated when a screen grab was done.
;
;ENTRY: EDX = Sys VM handle
;	EBX = VM handle of VM for whom call is made
;	EDI = VDD CB ptr
;	EBP = Client stack frame ptr
;	Client_EBX = VM Handle to free grab for
;
;EXIT:	none
;
;USES:	Flags
;
;==============================================================================
EndDoc

BeginProc VDD_Free_Grab
	jc	SHORT VFG_Exit
	TestMem [edi.VDD_Flags],fVDD_Win	; Q: Windowed?
	jz	VDD_Grab_DCopy			;  N: Deallocate copy mem
VFG_Exit:
        ret                                     ;  Y: Keep copy memory
EndProc VDD_Free_Grab

BeginDoc
;******************************************************************************
;VDD_Free_Mem
;
;DESCRIPTION:
;	This routine is used to release the scheduling freeze that occurred
;	when the Get_Mem call was made. See Get_Mem documentation.
;
;ENTRY: EDX = Sys VM handle
;	IF CF = 1, call was made with invalid VM Handle
;	EBX = VM handle of VM for whom call is made
;	EDI = VDD CB ptr
;	EBP = Client stack frame ptr
;	Client_EBX = VM Handle to free mem for
;
;EXIT:	none
;
;USES:	Flags
;
;==============================================================================
EndDoc

BeginProc VDD_Free_Mem
	jc	SHORT VFM_Exit
IFDEF CPDEBUG
	pushad
	mov	ax,[ebp.Client_CS]
	mov	cx,[ebp.Client_IP]
Trace_Out "Free_Mem at #AX:#CX"
	popad
ENDIF
	dec	[edi.VDD_Get_Mem_Count]	  ; one less call to Free_Mem

IFDEF RECTDEBUG
Queue_Out "VDD: Free_Mem"
ENDIF
        clc                               ; safety
        call    VDD_Unlock_APP
VFM_Exit:
	ret
EndProc VDD_Free_Mem

BeginDoc
;******************************************************************************
;VDD_Unlock_APP
;
;DESCRIPTION:
;	This routine is used to Unlock the Windowed OLDAPP from the grabber.
;	Called from VDD_Free_Mem also.
;
;	This does not take into account updating TWO VMs at once or that other
;	    windows programs are running, but is the best we can do.
;
;ENTRY: EDX = Sys VM handle
;	IF CF = 1, call was made with invalid VM Handle
;	EBX = VM handle of VM for whom call is made
;	EDI = VDD CB ptr
;	EBP = Client stack frame ptr
;	Client_EBX = VM Handle to free mem for
;
;EXIT:	none
;
;USES:	EAX,Flags
;
;==============================================================================
EndDoc
BeginProc VDD_Unlock_APP

	jc	SHORT VRN_Exit
IFDEF CPDEBUG
	pushad
	mov	ax,[ebp.Client_CS]
	mov	cx,[ebp.Client_IP]
Trace_Out "Unlock_App at #AX:#CX"
	popad
ENDIF
        mov     eax, [edi.VDD_Get_Mem_Count]
        or      eax,eax
        jnz     SHORT VRN_Exit

        push    edi
	mov	edi, edx
	add	edi,[Vid_CB_Off]
	btr	[edi.VDD_Flags], bVDD_Boost ; Q: SYS VM boosted for update?
        pop     edi
	jnc	SHORT VRN_Exit_0    	    ;	N: All done

	xchg	edx, ebx
	mov	eax,- VDD_Pri_Device_Boost
	VMMCall Adjust_Exec_Priority

VRN_Exit_0:

	VMMcall Get_VM_Exec_Time	    ; EAX = SYS VM's current time
	sub	eax, [edi.VDD_Upd_Start]    ; Subtract value at start of update
	VMMcall Adjust_Execution_Time	    ; Adjust time of SYS VM
	xchg	edx, ebx
	neg	eax
	VMMcall Adjust_Execution_Time	    ; Sub time to updated VM

VRN_Exit:
	ret

EndProc VDD_Unlock_APP


;******************************************************************************
;
;   VDD_SVC_Dsp_Version
;
;   DESCRIPTION:    Service for the display driver to determine level of
;		    support provided by VDD.
;
;   ENTRY:	    none
;
;   EXIT:	    Client_AX = VDD version #
;		    Client_DX = flags (currently 0)
;
;   USES:	    none
;
;==============================================================================
BeginProc VDD_SVC_Dsp_Version

	mov	[ebp.Client_AX], VDD_VerNum
	mov	[ebp.Client_DX], 0
	ret

EndProc VDD_SVC_Dsp_Version


;******************************************************************************
;
;   VDD_SVC_Set_Addresses
;
;   DESCRIPTION:    This service is called by the display driver BEFORE it
;		    does the INT 2Fh to indicate that it knows how to restore
;		    its screen.  This service is used to tell us where we
;		    can interface with the display driver.
;
;		    One of the addresses passed is the location of a byte of
;		    video memory that we can safely use to save/restore latches.
;
;		    The 2nd address passed is the location of the flag byte
;		    used by the display driver to determine the availability
;		    and validity of the "save screen bits" area.  The display
;		    driver copies portions of the visible screen to non-visible
;		    memory to save original contents when dialog boxes or menus
;		    area displayed.  Since this is non-visible memory, it is
;		    subject to demand paging and be stolen for use by a
;		    different VM.  If a page is stolen from the sys VM, then
;		    any data that was in the page is lost, because we don't
;		    maintain a copy, so we need to indicate to the display
;		    driver that the "save screen bits" area is now invalid.
;
;
;   ENTRY:	    EBX = VM Handle
;		    EBP = Client stack frame ptr
;		    Client_AX = function #
;		    Client_BX = offset of address in display segment
;		    Client_DX is reserved and must be 0
;		    ClientDS:Client_SI -> shadow_mem_status
;
;   EXIT:	    Client_AX is returned with a copy of Client_BX to
;			indicate that the service is implemented
;
;   USES:	    EAX, ECX, Flags
;
;==============================================================================
BeginProc VDD_SVC_Set_Addresses

	SetVDDPtr edi
	movzx	eax, [ebp.Client_BX]
	mov	[ebp.Client_AX], ax
	movzx	edx, [ebp.Client_DX]
	or	edx, edx
	jz	short sa_no_flags
IFDEF TLVGA
	TestMem [edi.VDD_TFlags], fVT_TL_ET4000
IFDEF DEBUG
	jz	short sa_debug_invalid_flags
	test	edx, NOT 1
	jnz	short sa_debug_invalid_flags
ELSE
	jz	short sa_no_flags
ENDIF
IFDEF SysVMin2ndBank
	ClrFlag [VT_Flags], fVT_SysVMin2ndBank
	ClrFlag [edi.VDD_TFlags], fVT_SysVMin2ndBank
ENDIF

	xor	edx, edx
	movzx	ecx, [ebp.Client_CL]
	or	cl, cl			    ;Q: display driver put latch byte
					    ;	  in different bank?
	jnz	short sa_complete	    ;	Y: so no pages are required
					    ;	    in 1st bank
	inc	edx			    ;	N: we have to reserve a pg
	mov	ch, ah			    ;	    in the 1st bank
	shr	ch, 4			    ; CH page # to reserve
	jmp	short sa_complete
ENDIF

sa_no_flags:
	xor	ecx, ecx
	mov	edx, eax
	shr	edx, 12
	inc	edx			    ; edx = # of visible pages
					    ;	 this assumes latch page is
					    ;	 last visible page
sa_complete:
	SetFlag [edi.VDD_Flags], fVDD_DspDrvrAware
;;	  Trace_Out 'Display driver set latch addr to #ax'
	call	VDD_PH_Mem_Set_Sys_Latch_Addr
	mov	ax, [ebp.Client_DS]
	mov	cx, [ebp.Client_SI]
	mov	word ptr [Vid_Shadow_Mem_Status_Ptr], cx
	mov	word ptr [Vid_Shadow_Mem_Status_Ptr+2], ax
	ret

IFDEF DEBUG
sa_debug_invalid_flags:
	Debug_Out 'invalid flags passed to VDD_SVC_Set_Addresses (#dx)'
	ret
ENDIF

EndProc VDD_SVC_Set_Addresses


IFDEF DspDrvrRing0Hack
;******************************************************************************
;
;   VDD_Init_DspDrv_Ring0
;
;   DESCRIPTION:
;
;   ENTRY:  EBX = VM handle
;	    EBP = Client stack frame ptr
;	    Client_AX = Device function
;	    Client_CX = ring 3 CS
;
;   EXIT:   Client_DX:AX -> call address to switch to ring 0
;	    Client_CX:BX -> call address to switch back to ring 3
;
;   USES:
;
;==============================================================================
BeginProc VDD_Init_DspDrv_Ring0

VxD_DATA_SEG
VDD_Return_To_Ring3_CS	dd  0
EXTRN DspDrvInitFailed:BYTE
VxD_DATA_ENDS

	mov	eax, [VDD_Return_To_Ring3_CS]
	or	eax, eax
	jnz	short @F
	VMMcall _BuildDescriptorDWORDs, <<OFFSET32 VDD_Jump_To_Ring3>, 1000h, Code_Type, D_DEF32, BDDExplicitDPL>
	VMMcall _Allocate_GDT_Selector, <edx, eax, 0>
	or	eax, eax
	jz	short iddr0_failed
	mov	[VDD_Return_To_Ring3_CS], eax
@@:
	xchg	ax, [ebp.Client_CX]	; ax is display driver's ring 3 CS
	mov	[ebp.Client_BX], 0

	movzx	eax, ax
	VMMcall _GetDescriptor, <eax, ebx, 0>
	and	dh, NOT D_DPL3		; make DPL=0
	VMMcall _Allocate_GDT_Selector, <edx, eax, 0>	; ax = ring 0 alias
	or	eax, eax
	jz	short iddr0_failed

	mov	edx, eax		; reference data is ring 0 alias
	mov	esi, OFFSET32 VDD_Jump_To_Ring0
	VMMCall Allocate_PM_Call_Back
	or	eax, eax
	jz	short iddr0_failed

	mov	[ebp.Client_AX], ax
	shr	eax, 16
	mov	[ebp.Client_DX], ax
	ret

iddr0_failed:
	Debug_Out 'VDD: failed to allocate GDT selector for return_to_ring3'
	Fatal_Error <OFFSET32 DspDrvInitFailed>

EndProc VDD_Init_DspDrv_Ring0


;******************************************************************************
;
;   VDD_Jump_To_Ring0
;
;   DESCRIPTION:    Call-Back entered as far call from VM's pmode code.
;
;   ENTRY:	    regular client frame
;		    EDX = ring 0 alias
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc VDD_Jump_To_Ring0

	VMMCall Simulate_Far_Ret
	pop	eax			; get our ret-to address
	push	cs			; convert to a far ret
	push	eax
	push	ebp			; save client ptr
	push	edx			; push ring 0 alias
	movzx	eax, [ebp.Client_IP]
	push	eax			; push dsp drvr's ip

IFNDEF VGA8514
	cmp	ebx, [Vid_MemC_VM]
	je	short @F
	call	VDD_State_Set_MemC_Owner
@@:
ENDIF
	Client_Ptr_Flat eax, ss, bp	; eax = linear address of Client_SS:BP

	mov	es, [ebp.Client_ES]
	mov	ds, [ebp.Client_DS]
	mov	ecx, [ebp.Client_ECX]
	mov	esi, [ebp.Client_ESI]
	mov	edi, [ebp.Client_EDI]
	mov	ebp, eax		; ebp -> display driver's stack frame
	retf				; ret to dsp drvr just after call to
					;   switch to ring 0

EndProc VDD_Jump_To_Ring0


;******************************************************************************
;
;   VDD_Jump_To_Ring3
;
;   DESCRIPTION:    Special routine that is a non-flat ring 0 entry point for
;		    the display driver to use to get back to ring 3.  The
;		    non-flat ip of this routine is 0.
;
;   ENTRY:	    Entered as FAR CALL from ring0 code in display driver
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc VDD_Jump_To_Ring3, no_log

	pop	eax			; pop ring0 cs:ip
	pop	ebp			; pop saved client ptr
	mov	[ebp.Client_IP], ax
	mov	[ebp.Client_ECX], ecx
	mov	[ebp.Client_ESI], esi
	mov	[ebp.Client_EDI], edi
	mov	ax, ss
	mov	ds, ax
	mov	es, ax
	retf				; ret to caller of VDD_Jump_To_Ring0

EndProc VDD_Jump_To_Ring3
ENDIF


;****************************************************************************
; 
; Msg code:
;
;****************************************************************************

;******************************************************************************
;
;   VDD_Error_Cvt_FullScrn
;
;   DESCRIPTION:    Force a full screen message to inform the user that
;		    their application is being forced to full screen.
;
;   ENTRY:	    EBX = VM Handle
;
;   EXIT:	    VM has been forced to full screen
;
;   USES:	    EAX, ECX, EDX, ESI, EDI, Flags
;
;==============================================================================
BeginProc VDD_Error_Cvt_FullScrn

	xor	edi, edi		    ; use VM caption
	xor	esi, esi		    ; no callback
	mov	eax, MB_OK+MB_ICONEXCLAMATION+MB_ASAP+MB_SYSTEMMODAL+MB_NOWINDOW
	mov	ecx, OFFSET32 VMB_Str_CvtFullScrn
	VxDJmp	SHELL_SYSMODAL_Message

EndProc VDD_Error_Cvt_FullScrn


IFDEF MapMonoError
;******************************************************************************
;VDD_Error_MapMono
;
;DESCRIPTION: VM has attempted Mono memory mapping when it is not supported.
;
;ENTRY: EBX = VM for whom message is generated
;	EDI = VM's VDD CB ptr
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;***************
BeginProc VDD_Error_MapMono

	VMMCall Test_Sys_VM_Handle
	jz	short just_quit

	mov	eax, MB_OK+MB_ICONEXCLAMATION+MB_ASAP
	mov	ecx, OFFSET32 VMB_Str_MapMono
	mov	dl,bVDE_NoMono
	jmp	SHORT VDD_Error_Message

just_quit:
	Fatal_Error <OFFSET32 VMB_Str_MapMono>

EndProc VDD_Error_MapMono
ENDIF


;******************************************************************************
;VDD_Error_NoPagesAvail
;
;DESCRIPTION:
;
;ENTRY: EBX = VM for whom message is generated
;	EDI = VM's VDD CB ptr
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;***************
BeginProc VDD_Error_NoPagesAvail

	mov	ecx, OFFSET32 VMB_Str_NoPagesAvail
	mov	dl, bVDE_NoPAMsg
	jmp	short VDD_Error_Message

EndProc VDD_Error_NoPagesAvail


;******************************************************************************
;VDD_Error_NoFGrnd
;
;DESCRIPTION:
;
;ENTRY: EBX = VM for whom message is generated
;	EDI = VM's VDD CB ptr
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;***************
BeginProc VDD_Error_NoFGrnd

	mov	ecx, OFFSET32 VMB_Str_NoFGrnd
	mov	dl, bVDE_NoFGMsg
	jmp	short VDD_Error_Message

EndProc VDD_Error_NoFGrnd


;******************************************************************************
;VDD_Error_NoMainMem
;
;DESCRIPTION:
;
;ENTRY: EBX = VM for whom message is generated
;	EDI = VM's VDD CB ptr
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;***************
BeginProc VDD_Error_NoMainMem

	mov	ecx, OFFSET32 VMB_Str_NoMainMem
	mov	dl, bVDE_NoMMsg
	Assumes_Fall_Through VDD_Error_Message

EndProc VDD_Error_NoMainMem


;******************************************************************************
;VDD_Message & VDD_Error_Message
;
;DESCRIPTION:	Call SHELL_Message to display a dialog box message, and if
;		SHELL fails the call, then call SHELL_SYSMODAL_Message to
;		force a fullscreen error dialog.
;
;		VDD_Error_Message is the same as VDD_Message except that it
;		forces EAX to MB_OK+MB_ICONEXCLAMATION+MB_ASAP (the standard
;		flags for error dialogs)
;
;ENTRY: EBX = VM for whom message is generated
;	EAX = message box flags
;	ECX = ptr to ASCIIZ message text
;	EDI = VM's VDD CB ptr
;	DL  = VDD_EFlags bit to set and check it avoid duplication of error
;	      messages
;
;EXIT:	none
;
;USES:	Flags, EAX, EDX
;
;***************
BeginProc VDD_Error_Message

	mov	eax, MB_OK+MB_ICONEXCLAMATION+MB_ASAP

BeginProc VDD_Message

	movzx	edx, dl
	bts	[edi.VDD_EFlags], edx		;Q: already given message?
	jc	short m_exit			;   Y: don't repeat it
	push	edi
	push	eax
	xor	edi,edi 			; Use VM name for caption
	xor	esi,esi 			; No call back
	VxDCall SHELL_Message			; send message to Windows
	pop	eax
						; Q: Successful?
	jnc	short @F			;   Y:
	or	eax, MB_SYSTEMMODAL		;   N: Do sysmodal msg NOW
	VxDCall SHELL_SYSMODAL_Message		; Get user response in EAX
@@:
	pop	edi
m_exit:
	ret
EndProc VDD_Message
EndProc VDD_Error_Message


VxD_CODE_ENDS

	END
