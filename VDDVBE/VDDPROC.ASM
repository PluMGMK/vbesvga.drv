	TITLE	VDD - Virtual Display Device for EGA/VGA  vers 3.0a
;******************************************************************************
;
;VDD - Virtual Display Device
;
;   Author: MDW
;
;   (C) Copyright MICROSOFT Corp. 1986 - 1990
;
;DESCRIPTION:
;	This module provides most of routines called by VMM. The VDD_Control
;	procedure dispatches these VMM calls. VDD_VMCreate is called
;	when a VM is being created.  VDD_VMInit is called just before a VM
;	is run for the first time. VDD_VMSetFocus and is called when the
;	display focus is changed. Initialization is done through the
;	VDD_Sys_Critical_Init and VDD_Device_Init.
;
;******************************************************************************

	.386p

.xlist
	INCLUDE VMM.INC
	INCLUDE VDD.INC
	INCLUDE OPTTEST.INC
	INCLUDE DEBUG.INC
	INCLUDE VDDDEF.INC
	INCLUDE SHELL.INC
	INCLUDE VDDGRB.INC
.list

;******************************************************************************
; EXTRN routines
;
VxD_CODE_SEG
	EXTRN	VDD_State_Change_Query:NEAR
	EXTRN	VDD_PH_Mem_VM_Using_All:NEAR
	EXTRN	VDD_Grab_Change_Query:NEAR
	EXTRN	VDD_Grab_DCopy:NEAR
	EXTRN	VDD_VM_Mem_Free_Pages:NEAR
	EXTRN	VDD_VM_Mem_Disable_Null:NEAR
	EXTRN	VDD_VM_Mem_VM_can_use_savemem:NEAR
	EXTRN	VDD_Error_NoFGrnd:NEAR
VxD_CODE_ENDS

;******************************************************************************
; EXTRN data
;
VxD_DATA_SEG
	EXTRN	Vid_Focus_VM:DWORD
	EXTRN	Vid_CB_Off:DWORD
	EXTRN	Vid_Flags:DWORD

;****************
; Delay window update by VDD_Mode_Update_Time to avoid screen
;	size bounce during a 43 line mode change.
; This is related to the fVDD_ModeChange in VM's VDD_Flags.
; At the beginning of a mode change this bit is set,
; at the end of a mode change we set a long time out.  The long timeout
; gives the VM enough time to modify the state further (like change the
; font for 43 line mode) before we do a windowed VM update.
; When the timeout occurs or the VM goes idle, fModeChange is cleared and
; all subsequent timeouts are normal duration.
;
; when fVDD_ModeChange is set - vdd_get_mod returns no changes,
;                      - vdd_VMIdle skips setting a timeout 
;		       - VDD_Set_VM_TimeOut sets a long timeout
; 
;
VDD_ModeChangeDelay	EQU	0100	; long time out during a mode change

PUBLIC	Vid_Win_Update_Time, Vid_Mode_Update_Time
Vid_Win_Update_Time DD	50
Vid_Mode_Update_Time DD VDD_ModeChangeDelay

PUBLIC	Vid_Scroll_Freq
Vid_Scroll_Freq	DD	2

;*******
;procedure address for Release_Time_Slice hook
PUBLIC Vid_VM_Idle_Chain
Vid_VM_Idle_Chain    DD  ?
EXTRN	VDD_Time_Ini:BYTE
EXTRN	VDD_VM_Scroll_Freq_Ini:BYTE

VxD_DATA_ENDS

VxD_CODE_SEG

VxD_ICODE_SEG
;******************************************************************************
;VDD_Proc_Device_Init
;
;DESCRIPTION:
;
;ENTRY: EBX = VM_Handle of SYS VM
;	EDI -> VDD CB data
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_Proc_Device_Init, PUBLIC

; Get window update timeout value
	push	edi
	mov	eax, 50 		    ; default to 50msecs
	mov	edi, OFFSET32 VDD_Time_Ini
	xor	esi, esi		    ; Use [Win386] section
	VMMcall Get_Profile_Decimal_Int
	mov	[Vid_Win_Update_Time],eax   ; Set Window update time
	add	eax,eax
	mov	[Vid_Mode_Update_Time],eax  ; Twice as long for mode changes
	pop	edi

; Get scroll update counter value
	push	edi
	mov	eax,2
	mov	edi, OFFSET32 VDD_VM_Scroll_Freq_Ini
	xor	esi,esi
	VMMCall	Get_Profile_Decimal_Int
	or	eax,eax			    ; has someone been mischievous?
	jnz	SHORT NoPrankster
	mov	eax,2
NoPrankster:
	mov	[Vid_Scroll_Freq],eax
	pop	edi

; Hook Release Time slice so we can do Window updates when app is idle
	mov	esi,OFFSET32 @VDD_VMIdle
	mov	eax,Release_Time_Slice
	VMMCall Hook_Device_Service
	mov	[Vid_VM_Idle_Chain],esi
	ret
EndProc VDD_Proc_Device_Init

VxD_ICODE_ENDS

;******************************************************************************
;VDD_VMIdle	    Check for screen update while VM is idle
;
;DESCRIPTION:
;	Display changes are checked for after a VM has been executing for
;	a fixed period of time, or the VM has become idle(e.g. waiting for
;	keyboard input) in which case the VM will not be executing at
;	all. This is the routine that gets called when the VM is idle.
;
;ENTRY: EBX = VM handle
;
;EXIT:	none
;
;USES:	Flags
;
;==============================================================================
BeginProc VDD_VMIdle,SERVICE,High_Freq

	pushad
	SetVDDPtr edi, ebx
	TestMem [edi.VDD_Flags],fVDD_Win
	jz	SHORT VMI_Exit
IFDEF	RECTDEBUG
Trace_Out "I",NOEOL
ENDIF
IFDEF DEBUG
	bt	[edi.VDD_Flags],fVDD_ModeSet	; Q: During mode change?
	jnc	SHORT VMI_DBG0			;   N: ignore
Trace_Out "IDLE during video mode change!!"	;   Y: Not supposed to happen
VMI_DBG0:
ENDIF
	call	VDD_Clr_VM_Time_Out		; Clear pending timeout
	ClrFlag [edi.VDD_Flags],fVDD_ModeChange ; Clear flag 1st idle after
						;	a mode change
	TestMem [edi.VDD_Flags],fVDD_Upd	; Q: During screen update?
	jz	SHORT VMI_00			;   N: Check update now
	SetFlag [edi.VDD_Flags],fVDD_IdleUpdate ;   Y: need to check chgs when
						;	update is done
	jmp	SHORT VMI_Exit
VMI_00:
	call	VDD_Update_Window		; Do screen update if necessary
VMI_Exit:
	popad
	jmp	[Vid_VM_Idle_Chain]
EndProc VDD_VMIdle


;******************************************************************************
;VDD_VMTimeOut	    Check for screen update after VM has executed for awhile
;
;DESCRIPTION:
;	Display changes are checked for after a VM has been executing for
;	a fixed period of time, or the VM has become idle(e.g. waiting for
;	keyboard input) in which case the VM will not be executing much at
;	all. This is the routine that gets called when the VM has executed
;	for awhile
;
;ENTRY: EBX = VM handle
;	EDX = VM's VDD ptr
;
;EXIT:
;
;USES:	Flags
;
;ASSUMES:
;
;==============================================================================
BeginProc VDD_VMTimeOut,PUBLIC,High_Freq

IFDEF	RECTDEBUG
Trace_Out "to",NOEOL
ENDIF
	mov	edi,edx 			; EDI = VM's VDD CB ptr
	mov	[edi.VDD_Time_Out_Handle],0
	TestMem [edi.VDD_Flags],fVDD_ModeSet	; Q: During mode change?
	jnz	SHORT VVTO_Exit 		;   Y: ignore
	ClrFlag [edi.VDD_Flags],fVDD_ModeChange ; Clear 1st timeout after
						;	mode chg
	TestMem [edi.VDD_Flags],fVDD_Win	; Q: Windowed VM?
        jz      SHORT VVTO_Exit                 ;   N: Return
        xor     eax,eax
        xchg    [edi.VDD_Postponed_TimeOuts],al ;
        btr     [edi.VDD_Flags],bVDD_PageFault  ; Q: Page fault since last time out?
        jnc     SHORT VDD_Update_Window         ;   N: Check for window update
        cmp     al,8                            ; Q: Have we postponed enough?
        jae     SHORT VDD_Update_Window         ;   Y: Update window
        inc     eax                             ;   N: Increment postponement
        mov     [edi.VDD_Postponed_TimeOuts],al ;      counter and set new timeout
        jmp     SHORT VDD_Set_VM_Time_Out       ;
VVTO_Exit:
	ret
EndProc VDD_VMTimeOut


;******************************************************************************
;VDD_Update_Window
;
;DESCRIPTION:	Check for screen update
;
;ENTRY: EBX = VM handle
;	EDI = VM's VDD ptr
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI, EDI
;
;==============================================================================
BeginProc VDD_Update_Window,High_Freq

	mov	[edi.VDD_Recent_User_Action],0

IFDEF	RECTDEBUG
Trace_Out "U?",NOEOL
ENDIF
	bt	[edi.VDD_Flags],bVDD_Upd	; Only one update allowed
	jc	SHORT VVU_Exit			;   at a time
	call	VDD_State_Change_Query		;Q: Video state changed?
	jc	SHORT uw_Update 		;   Y: schedule update
	call	VDD_Grab_Change_Query		;Q: Video memory changed?
	jnc	SHORT VVU_no_update		;   N: schedule timeout
						;   Y: schedule update
uw_update:
	SetFlag [edi.VDD_Flags],fVDD_Upd	; Only one update allowed
IFDEF	RECTDEBUG
Trace_Out ".",NOEOL
ENDIF
	inc	[edi.VDD_Update_Hit_Cnt]

	push	ebx
	cmp	[edi.VDD_Stt.V_BiosMode],0Dh	; if bios mode >= 0D,Use time
	jae	SHORT GetTimeLater		; at get_mem time
	VMMcall Get_Sys_VM_Handle
	VMMCall	Get_VM_Exec_Time		; get exec time for sysVM
	mov	[edi.VDD_Upd_Start], eax        ; Store as start time for 
                                                ; window update
GetTimeLater:
	mov	eax, Low_Pri_Device_Boost
	mov	ecx, PEF_Wait_For_STI+PEF_Wait_Not_Crit+PEF_Always_Sched
	mov	edx,edi 			; Pass VDD CB ptr to call back
	mov	esi, OFFSET32 VDD_Update_Event
	VMMcall Call_Priority_VM_Event
	pop	ebx
VVU_Exit:
	ret

VVU_no_update:
	mov	[edi.VDD_Update_Hit_Cnt], 0
Assumes_Fall_Through VDD_Set_VM_Time_Out

EndProc VDD_Update_Window


;******************************************************************************
;VDD_Set_VM_Time_Out
;
;DESCRIPTION:
;
;ENTRY: EBX = VM handle
;	EDI = VM's VDD ptr
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI, EDI
;
;==============================================================================
BeginProc VDD_Set_VM_Time_Out,PUBLIC,High_Freq

	TestMem [edi.VDD_Flags],fVDD_Win	; Q: Windowed VM?
	jz	SHORT VSVTO_Exit		;   N:
	cmp	[edi.VDD_Time_Out_Handle],0	; Q: Timeout active?
	jnz	SHORT VSVTO_Exit		;   Y:
	mov	eax, [Vid_Mode_Update_Time]	; Mode change delay
	TestMem [edi.VDD_Flags],fVDD_ModeChange ; Q: In a mode change?
	jnz	short VSVTO_01			;   Y: use it
	mov	eax, [Vid_Win_Update_Time]	;   N: Use display update time
	cmp	[edi.VDD_Update_Hit_Cnt], 3	; Q: constant updating?
	jb	short VSVTO_01			;   N: continue
	shl	eax, 2				;   Y: increase timeout time

VSVTO_01:
IFDEF	RECTDEBUG
Trace_Out "TO",NOEOL
ENDIF
	mov	edx,edi
	mov	esi,OFFSET32 VDD_VMTimeOut
	VMMCall Set_VM_Time_Out 		; Set display update timeout
	mov	[edi.VDD_Time_Out_Handle],esi	; Save timeout handle
VSVTO_Exit:
	ret
EndProc VDD_Set_VM_Time_Out


IFDEF	VRTCTIMER
;******************************************************************************
; EXTRN locked data
;
VxD_LOCKED_DATA_SEG
	EXTRN	sb_period_ms:BYTE
VxD_LOCKED_DATA_ENDS


;******************************************************************************
;VDD_VRTCTimeOut    Set VRTC flag every frame
;
;DESCRIPTION:
;	Display changes are checked for after a VM has been executing for
;	a fixed period of time, or the VM has become idle(e.g. waiting for
;	keyboard input) in which case the VM will not be executing much at
;	all. This is the routine that gets called when the VM has executed
;	for awhile
;
;ENTRY: EBX = currently-running VM handle (MAY NOT BE requesting VM)
;	EDX = requesting VM's VDD ptr
;
;EXIT:
;
;USES:	Flags
;
;ASSUMES:
;
;==============================================================================
BeginProc VDD_VRTCTimeOut,PUBLIC,High_Freq

	mov	ebx,edx
	sub	ebx,[Vid_CB_Off]
	VMMCall Validate_VM_Handle		; Q: VM still active?
	jc	SHORT VVRTCTO_Exit 		;   N: No update possible

	mov	edi,edx 			; EDI = VM's VDD CB ptr
	mov	[edi.VDD_VRTC_timeout],0
	TestMem [edi.VDD_Flags],fVDD_Win	; Q: Windowed VM?
        jz      SHORT VVRTCTO_Exit              ;   N: Return
	; check if VM has been polling the VRTC flag - it should be clear if
	; they've polled it VDD_VERT_PERIOD times since the last timeout.
	; FIXME: once we implement the IRQ then we will also need to check
	; if the VM has been acknowledging IRQs before abandoning the timer!
	test	[edi.VDD_Stt.V_Stat1],fstatVRTC
	jnz	SHORT VVRTCTO_Exit		; don't bother with more timeouts
	; start the VRTC cycle (see VIOT_VI_Stat1 in VDDTIO.ASM for details)
	mov	[edi.VDD_VertCnt],VDD_VERT_PERIOD
	or	[edi.VDD_Stt.V_Stat1],fstatVRTC+fstatEna
	; check for IRQ
	test	[edi.VDD_Stt.C_VRTCEnd],fVRTCEndIRQEna
	jnz	SHORT @F			; 1 means disabled (yep...)
	bts	[edi.VDD_Stt.V_Stat0],bStt0VRTC	; Q: flip-flop already high?
	jc	SHORT @F			;    Y: no new IRQ
IFDEF	DEBUG
	Debug_Out "#EBX requires VRTC IRQ, not implemented yet..."
ENDIF
@@:     jmp     SHORT VDD_Set_VRTC_Time_Out
VVRTCTO_Exit:
	ret
EndProc VDD_VRTCTimeOut


;******************************************************************************
;VDD_Set_VRTC_Time_Out
;
;DESCRIPTION:
;
;ENTRY: EBX = VM handle
;	EDI = VM's VDD ptr
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI, EDI
;
;==============================================================================
BeginProc VDD_Set_VRTC_Time_Out,PUBLIC,High_Freq

	TestMem [edi.VDD_Flags],fVDD_Win	; Q: Windowed VM?
	jz	SHORT VSVRTCTO_Exit		;   N:
	cmp	[edi.VDD_VRTC_timeout],0	; Q: Timeout active?
	jnz	SHORT VSVRTCTO_Exit		;   Y:
	movzx	eax,[edi.VDD_Framerate_Recip]	; get nominal time-out period
	cmp	eax,[Vid_Win_Update_Time]	; Q: Shorter than Win update?
	jae	SHORT VSVRTCTO_01		;   N: CPU should be well able
	; if we have double-buffering enabled, we can check against the
	; swap-buffers interval as a secondary heuristic
	movzx	edx,[sb_period_ms]
	test	edx,edx				; Q: Double-buf enabled?
	jz	SHORT VSVRTCTO_Exit		;   N: no further checking
	cmp	eax,edx				; Q: Shorter than swap-buffers?
	jb	SHORT VSVRTCTO_Exit		;   Y: too short, may overwhelm CPU
						;   N: CPU should handle it OK
VSVRTCTO_01:
	mov	edx,edi
	mov	esi,OFFSET32 VDD_VRTCTimeOut
	VMMCall Set_Global_Time_Out 		; Set VRTC timeout
	mov	[edi.VDD_VRTC_timeout],esi	; Save timeout handle
VSVRTCTO_Exit:
	ret
EndProc VDD_Set_VRTC_Time_Out

;******************************************************************************
;VDD_Clr_VRTC_Time_Out
;
;DESCRIPTION: Clear any pending VRTC timeout for VM
;
;ENTRY: EBX = VM handle
;	EDI -> VM's VDD data
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI, EDI
;
;==============================================================================
BeginProc VDD_Clr_VRTC_Time_Out,PUBLIC,High_Freq

	xor	esi, esi
	xchg	esi, [edi.VDD_VRTC_timeout]
	VMMCall Cancel_Time_Out 		; Cancel pending update timeout
	ret
EndProc VDD_Clr_VRTC_Time_Out
ENDIF	;VRTCTIMER

;******************************************************************************
;VDD_Clr_VM_Time_Out
;
;DESCRIPTION: Clear any pending video update timeout for VM
;
;ENTRY: EBX = VM handle
;	EDI -> VM's VDD data
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI, EDI
;
;==============================================================================
BeginProc VDD_Clr_VM_Time_Out,PUBLIC,High_Freq

	xor	esi, esi
	xchg	esi, [edi.VDD_Time_Out_Handle]
	VMMCall Cancel_Time_Out 		; Cancel pending update timeout
IFDEF	RECTDEBUG
Trace_Out "CO",NOEOL
ENDIF
	ret
EndProc VDD_Clr_VM_Time_Out

;******************************************************************************
;VDD_Update_Event    Send update event to VMDOSAPP
;
;DESCRIPTION: Call Shell_Event with update event for VMDOSAPP.	This should
;	    only be called when critical section is unowned.
;
;ENTRY: EBX = SYS VM handle
;	EDX -> VDD CB data for which grab occurred
;
;EXIT:	none
;
;USES:	Flags, EAX, EBX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_Update_Event

	mov	ebx,edx
	sub	ebx,[Vid_CB_Off]
	VMMCall Validate_VM_Handle		; Q: VM still active?
	jc	SHORT VVUE_Exit 		;   N: No update possible
	mov	esi,OFFSET32 VDD_Upd_CallBack	; Clear grab flag on completion
	mov	ecx,VDA_Display_Event		; Display event
	mov	eax,VDA_DE_DispChngMin
	btr	[edx.VDD_Flags], bVDD_BoostUpdate
	jnc	short @F
	or	eax, SE_WP_DispUpdBoost
@@:
						; subfunction - display change
                                                ;       no ctlr change
	VxDCall Shell_Event			; Queue up the event
	jc	SHORT VDD_Upd_CallBack
VVUE_Exit:
	ret
EndProc VDD_Update_Event

;******************************************************************************
;VDD_Upd_CallBack
;
;DESCRIPTION: This routine is called when update event is completed
;
;ENTRY: EBX = SYS VM handle
;	EDX -> VDD CB data for which grab occurred
;
;EXIT:	none
;
;USES:	Flags, EAX, EBX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_Upd_CallBack
IFDEF	RECTDEBUG
Trace_Out "=",NOEOL
ENDIF
	ClrFlag [edx.VDD_Flags], fVDD_Upd
	mov	edi,edx
	mov	ebx,edx
	sub	ebx,[Vid_CB_Off]
	VMMCall Validate_VM_Handle		; Q: VM still active?
	jc	SHORT VUCB_Exit 		;   N: No more updates
	btr	[edi.VDD_Flags],bVDD_IdleUpdate ; Q: VM go idle during update?
	jnc	VDD_Set_VM_Time_Out		;   N: schedule next timeout
	jmp	VDD_Update_Window		;   Y: do any update now
VUCB_Exit:
	ret
EndProc VDD_Upd_CallBack

;******************************************************************************
;VDD_VMDA_Grab	    Send grab event to VMDOSAPP
;
;DESCRIPTION: If no Grab event is already queued, set up event to call
;	Shell_Event with grab event for VMDOSAPP.
;
;ENTRY: EBX = VM handle for which grab occurred
;	EDI = VDD CB ptr
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_VMDA_Grab,PUBLIC

Assert_VDD_ptrs ebx,edi

	bts	[edi.VDD_Flags],bVDD_Grab    ; Only one grab allowed
	jc	SHORT VVG_Exit
	push	ebx
	VMMcall Get_Sys_VM_Handle
	mov	eax, Low_Pri_Device_Boost
	mov	ecx, PEF_Wait_For_STI+PEF_Wait_Not_Crit+PEF_Always_Sched
	mov	edx,edi 			; Pass VDD CB ptr to call back
	mov	esi, OFFSET32 VDD_Grab_Event
	VMMcall Call_Priority_VM_Event
	pop	ebx
VVG_Exit:
	ret
EndProc VDD_VMDA_Grab

;******************************************************************************
;VDD_Grab_Event      Send grab event to VMDOSAPP
;
;DESCRIPTION: call Shell_Event with grab event for VMDOSAPP.
;
;ENTRY: EDX = VDD CB ptr
;
;EXIT:	none
;
;USES:	Flags, EAX, EBX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_Grab_Event,PUBLIC

	mov	ebx, edx
	sub	ebx, [Vid_CB_Off]
	VMMCall Validate_VM_Handle
	jc	SHORT VGE_Exit
	mov	esi, OFFSET32 VDD_Grab_CallBack ; Clear grab flag on completion
	mov	ecx, VDA_Display_Event		; Display event
	mov	eax, VDA_DE_ScreenGrabMin+SE_WP_PrtScBoost ; Screen grab
	VxDCall Shell_Event			; Queue up the event
IFDEF	DEBUG
	jnc	SHORT VGE_DBG0
Trace_Out "VDD failed to post message for grabber"
VGE_DBG0:
ENDIF
	jc	SHORT VDD_Grab_CallBack
VGE_Exit:
	ret
EndProc VDD_Grab_Event

;******************************************************************************
;VDD_Grab_CallBack
;
;DESCRIPTION: Finished with grab.  Delete grab memory.
;
;ENTRY: EDX -> VDD CB data
;
;EXIT:	none
;
;USES:	Flags, EAX, EBX, ECX, EDX, ESI, EDI
;
;==============================================================================
BeginProc VDD_Grab_CallBack

	ClrFlag [edx.VDD_Flags], fVDD_Grab
	mov	edi, edx
	mov	ebx, edx
	sub	ebx, [Vid_CB_Off]
	jmp	VDD_Grab_DCopy			; Deallocate copy mem
EndProc VDD_Grab_CallBack


;------------------------------------------------------------------------------
;------------------------------------------------------------------------------

;******************************************************************************
;
;   VDD_Proc_VM_Resume
;
;   DESCRIPTION:
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    ESI, Flags
;
;==============================================================================
BeginProc VDD_Proc_VM_Resume

	TestMem [edi.VDD_Flags], fVDD_CanRestore;Q: CanRestore VM?
	jz	short vmr_exit			;   N: do nothing
	btr	[edi.VDD_Flags], bVDD_WaitAtt
	jnc	short vmr_exit			; jump if not WaitAtt
	cmp	[edi.VDD_NotifyEvent], 0	;Q: bgrnd notify pending?
	jne	short vmr_exit			;   Y: just clear WaitAtt
	mov	esi, OFFSET32 VDD_Proc_FGrnd_INT2F ;N: schedule event
	VMMCall Schedule_VM_Event		;	 to notify VM
	mov	[edi.VDD_NotifyEvent], esi
vmr_exit:
	ret

EndProc VDD_Proc_VM_Resume


;******************************************************************************
;
;   VDD_Proc_VM_Suspend
;
;   DESCRIPTION:
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:
;
;==============================================================================
BeginProc VDD_Proc_VM_Suspend

	TestMem [edi.VDD_Flags], fVDD_NoSaveRes ;Q: CanRestore with auto disabled?
	jz	short sus_no_bgrnd		;   N: don't queue notify
	call	VDD_Proc_BGrnd_Notify		;   Y: schedule notification
sus_no_bgrnd:
	ret

EndProc VDD_Proc_VM_Suspend


;******************************************************************************
;
;   VDD_Proc_BGrnd_INT2F
;
;   DESCRIPTION:    Simulate INT 2F, AX=4001h into VM
;
;   ENTRY:	    EBX = VM Handle
;
;   EXIT:	    EDI -> VDD_CB_Struc
;
;   USES:	    EAX, ECX, ESI, EDI, Flags
;
;==============================================================================
BeginProc VDD_Proc_BGrnd_INT2F

	SetVDDPtr edi
	mov	[edi.VDD_NotifyEvent], 0
	Trace_Out 'VDD bgrnd notify #ebx'

;
; Reset VM's controller state [VDD_STT] to what was saved when the VM notified
; us that it could restore its own screen.
;
	mov	esi, [edi.VDD_SavedStt]
	or	esi, esi			;Q: saved state?
	jz	short bn_no_saved_state 	;   N:
	push	edi
	lea	edi, [edi.VDD_Stt]
	mov	ecx, (SIZE Reg_State_struc) / 4
	cld
	rep	movsd
	pop	edi
IFDEF	DEBUG
	SetFlag [edi.VDD_Flags],fVDD_NeedRestore ; Don't save regs over state
ENDIF
bn_no_saved_state:

	push	ebp
	mov	ebp, [ebx.CB_Client_Pointer]
	Push_Client_State
	VMMcall Begin_Nest_Exec
	mov	[ebp.Client_AX], 4001h
	mov	eax,2Fh
	VMMcall Exec_Int			; VM detaches from display
	TestMem [edi.VDD_Flags], fVDD_WaitAtt	;Q: need fgrnd notify also?
	jz	short fn_simulate_2f		;   Y: jump into VDD_Proc_FGrnd_INT2F
	VMMcall End_Nest_Exec
	Pop_Client_State
	pop	ebp
	ret

EndProc VDD_Proc_BGrnd_INT2F


;******************************************************************************
;
;   VDD_Proc_FGrnd_INT2F
;
;   DESCRIPTION:    Simulate INT 2F, AX=4002h into VM
;
;   ENTRY:	    EBX = VM Handle
;
;   EXIT:	    EDI -> VDD_CB_Struc
;
;   USES:	    EAX, EDI, Flags
;
;==============================================================================
BeginProc VDD_Proc_FGrnd_INT2F

	SetVDDPtr edi
	mov	[edi.VDD_NotifyEvent], 0
	TestMem [edi.VDD_Flags], fVDD_WaitAtt	;Q: still need fgrnd notify?
IFDEF DEBUG
	jz	short fn_D00
	Trace_Out 'BGrnd cancelled need for FGrnd notify'
fn_D00:
ENDIF
	jnz	short fn_skip_notify		;   N:
	push	ebp
	mov	ebp, [ebx.CB_Client_Pointer]
	Push_Client_State
	VMMcall Begin_Nest_Exec
fn_simulate_2f:
	Trace_Out 'VDD fgrnd notify #ebx'
	mov	[ebp.Client_AX], 4002h
	mov	eax,2Fh
	SetFlag [edi.VDD_Flags], fVDD_InInt2F
	VMMcall Exec_Int			; VM reinitializes display
	ClrFlag [edi.VDD_Flags], fVDD_InInt2F
	VMMcall End_Nest_Exec
	Pop_Client_State
	pop	ebp
fn_skip_notify:
	ret

EndProc VDD_Proc_FGrnd_INT2F


;******************************************************************************
;
;   VDD_Proc_BGrnd_Notify
;
;   DESCRIPTION:    Schedule/Call VDD_Proc_BGrnd_INT2F
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    ESI, Flags
;
;==============================================================================
BeginProc VDD_Proc_BGrnd_Notify

	cmp	[edi.VDD_NotifyEvent], 0    ;Q: event scheduled?
	je	short bn_no_event	    ;	N:
	TestMem [edi.VDD_Flags], fVDD_WaitAtt ;Q: VM waiting?
	jnz	short bn_exit		    ;	Y: don't do anything
	SetFlag [Vid_Flags], fVid_VMsSuspended
	SetFlag [edi.VDD_Flags], fVDD_WaitAtt ; N: flag that VM is waiting
	jmp	short bn_exit

bn_no_event:
	SetFlag [Vid_Flags], fVid_VMsSuspended
	SetFlag [edi.VDD_Flags], fVDD_WaitAtt
	VMMCall Test_Cur_VM_Handle
	jnz	short bn_schedule
	TestMem [ebx.CB_VM_Status], VMStat_Suspended
	jnz	short bn_schedule	    ; schedule event, if VM suspended
	call	VDD_Proc_BGrnd_INT2F	    ; notify VM that it doesn't
					    ;	have the display
bn_exit:
	ret

bn_schedule:
	mov	esi, OFFSET32 VDD_Proc_BGrnd_INT2F
	VMMCall Schedule_VM_Event
	mov	[edi.VDD_NotifyEvent], esi
	ret

EndProc VDD_Proc_BGrnd_Notify


;******************************************************************************
;
;   VDD_Proc_Notify_Bkgnd_VMs
;
;   DESCRIPTION:    Do bkgnd notifications for background VM's that have
;		    done the INT 2F to tell us that they know how to restore
;		    their screen, if auto save/restore is not enabled.
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_Proc_Notify_Bkgnd_VMs

	TestMem [edi.VDD_TFlags], <fVT_NoSaveResSysVM OR fVT_NoSaveResOthers>
	jz	short nbv_skip
	push	edi
	push	ebx

nbv_loop:
	VMMCall Get_Next_VM_Handle
	cmp	ebx, [esp]			    ;Q: starting VM?
	je	short nbv_exit			    ;	Y: exit loop
IFDEF SysVMin2ndBank
	TestMem [edi.VDD_TFlags], fVT_SysVMnot1stBank
	jz	short @F
	VMMCall Test_Sys_VM_Handle		    ; sys VM running in 2nd bank
	je	nbv_loop			    ;	so we don't need to
						    ;	notify it, because it
						    ;	never loses it's memory
@@:
ENDIF
	TestMem [ebx.CB_VM_Status], VMStat_Background ;Q: background bit set?
	jz	nbv_loop			    ;	N: skip VM
	SetVDDPtr edi
	TestMem [edi.VDD_Flags], fVDD_WaitAtt	    ;Q: already notified?
	jnz	nbv_loop			    ;	Y: skip VM
	TestMem [edi.VDD_Flags], fVDD_NoSaveRes     ;Q: auto res disabled?
	jz	nbv_loop			    ;	N: chk next VM
	call	VDD_VM_Mem_Free_Pages		    ;	Y: free video pages,
	call	VDD_Proc_BGrnd_Notify		    ;	   notify bkgnd
	jmp	nbv_loop			    ;	    & continue

nbv_exit:
	pop	ebx
	pop	edi
nbv_skip:
	ret

EndProc VDD_Proc_Notify_Bkgnd_VMs


;******************************************************************************
;
;   VDD_Proc_Chk_Bkgnd_Usage
;
;   DESCRIPTION:    This routine is called by VDD_VM_Mem_Set_Device_Focus and
;		    VDD_VM_Mem_End_Mode_Chg for the current focus VM.  It is used
;		    to check to see if the focus VM has all video pages
;		    visible.  If all pages are visible, then any background
;		    VM's which needs demand paged video memory must be
;		    suspended.	If all pages are not visible, then any VMs
;		    which the VDD might have previously suspended can be
;		    resumed again.
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_Proc_Chk_Bkgnd_Usage

	Assert_VDD_ptrs ebx,edi
IFDEF DEBUG
	cmp	ebx, [Vid_Focus_VM]
	je	short cbu_D00
	Debug_Out 'VDD_Proc_Chk_Bkgnd_Usage should only be called for focus VM'
cbu_D00:
ENDIF
	call	VDD_PH_Mem_VM_Using_All 	  ;Q: VM needs all video pages?
	jnc	DEBFAR VDD_Proc_Resume_Bkgnd_VMs  ;   N:
Assumes_Fall_Through VDD_Proc_Suspend_Bkgnd_VMs   ;   Y: suspend other VM's

EndProc VDD_Proc_Chk_Bkgnd_Usage


;******************************************************************************
;
;   VDD_Proc_Suspend_Bkgnd_VMs
;
;   DESCRIPTION:    Go thru VM list and suspend any background VM's which
;		    need video memory (not text, CGA graphics or 256 color
;		    graphics modes) and don't know how to restore themselves.
;
;   ENTRY:	    EBX = VM handle
;		    EDI -> VDD_CB_Struc
;
;   EXIT:	    none
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_Proc_Suspend_Bkgnd_VMs

	push	edi
	push	ebx
	TestMem [edi.VDD_TFlags],fVT_NoSuspend
	jnz	DEBFAR sbv_exit
;
; loop thru all VM's and suspend any background VM's that need video memory
;
suspend_bkgnd_VMs:
	VMMCall Get_Next_VM_Handle
	cmp	ebx, [esp]				;Q: starting VM?
	je	DEBFAR sbv_exit 			;   Y: exit loop
	TestMem [ebx.CB_VM_Status], VMStat_Background	;Q: background bit set?
	jz	suspend_bkgnd_VMs			;   N: skip VM
	SetVDDPtr edi
	TestMem [edi.VDD_Flags], fVDD_WaitAtt		;Q: already suspended?
	jnz	suspend_bkgnd_VMs			;   Y: skip VM
	TestMem [edi.VDD_Flags], fVDD_CanRestore	;Q: VM can restore screen?
	jz	short sbv_suspend			;   N: attempt suspend
	TestMem [edi.VDD_TFlags], fVT_Notify_at_PF	    ;Q: notify here?
	jnz	suspend_bkgnd_VMs			;   N: skip VM
	call	VDD_Proc_BGrnd_Notify			;   Y: give notification
	jmp	suspend_bkgnd_VMs			;	& continue

sbv_suspend:
	call	VDD_VM_Mem_VM_can_use_savemem		;Q: VM needs video mem?
	jnc	suspend_bkgnd_VMs			;   N: skip VM
IFDEF DEBUG
	VMMCall Test_Cur_VM_Handle
	jne	short sbvm_D00
	Trace_Out 'VDD_Proc_Suspend_Bkgnd_VMs attempting to suspend current VM #ebx'
sbvm_D00:
ENDIF
	VMMCall Suspend_VM
	jc	suspend_bkgnd_VMs	    ; jump if suspend failed
	Trace_Out 'VDD suspended #ebx'
	SetFlag [edi.VDD_Flags], fVDD_WaitAtt
	SetFlag [edi.VDD_EFlags], fVDE_NoFGrnd
	SetFlag [Vid_Flags], fVid_VMsSuspended
	TestMem [edi.VDD_TFlags],fVT_SuprsMsg	; Q: report suspend?
	jnz	suspend_bkgnd_VMs	    ;	N: continue
	call	VDD_Error_NoFGrnd	    ;	Y: report suspension
	jmp	suspend_bkgnd_VMs

sbv_exit:
	pop	ebx
	pop	edi
	ret

EndProc VDD_Proc_Suspend_Bkgnd_VMs


;******************************************************************************
;
;   VDD_Proc_Resume_Bkgnd_VMs
;
;   DESCRIPTION:    Go thru VM list and resume any background VM's which
;		    we previously suspended in VDD_Proc_Suspend_Bkgnd_VMs.
;		    Also schedule a notification event for any VM's which
;		    know how to restore their own screens and already got
;		    a background INT 2F notification from us in VDD_PFault.
;
;   ENTRY:	    EBX = current VM handle
;
;   EXIT:	    none
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_Proc_Resume_Bkgnd_VMs

	btr	[Vid_Flags], bVid_VMsSuspended	;Q: any VM's suspended by VDD?
	jnc	DEBFAR rbv_exit 		;   N:
	push	edi
	push	ebx
	jmp	short resume_lp_chk_cur_VM
;
; loop thru all VM's and resume any background VM's that need video memory
;
resume_bkgnd_VMs:
	VMMCall Get_Next_VM_Handle
	cmp	ebx, [esp]			;Q: starting VM?
	je	DEBFAR rbv_done 		;   Y: exit loop
resume_lp_chk_cur_VM:
	TestMem [ebx.CB_VM_Status], VMStat_Background	;Q: background bit set?
	jz	resume_bkgnd_VMs			;   N: skip VM
	SetVDDPtr edi
	TestMem [edi.VDD_Flags], fVDD_WaitAtt	;Q: VM suspended?
	jz	resume_bkgnd_VMs		;   N: skip VM
	TestMem [edi.VDD_Flags], fVDD_CanRestore;Q: VM will restore display?
	jz	short rbv_call_resume		;   N: call resume
	cmp	ebx, [Vid_Focus_VM]		;Q: focus VM?
	je	short rbv_notify		;   Y: send notification
	TestMem [edi.VDD_Flags], fVDD_NoSaveRes ;Q: auto res disabled?
	jz	short rbv_notify		;   N: notify VM
	SetFlag [Vid_Flags], fVid_VMsSuspended	;   Y: we're leaving a
	jmp	resume_bkgnd_VMs		;	 VM suspended
rbv_notify:
	push	eax				;   Y: disable mapped null
	call	VDD_VM_Mem_Disable_Null 	;      memory &
	pop	eax
	ClrFlag [edi.VDD_Flags], fVDD_WaitAtt
	cmp	[edi.VDD_NotifyEvent], 0	;Q: bgrnd notify pending?
	jne	resume_bkgnd_VMs		;   Y: just clear WaitAtt
	mov	esi, OFFSET32 VDD_Proc_FGrnd_INT2F ;N: schedule event
	VMMCall Schedule_VM_Event		;	 to notify VM
	mov	[edi.VDD_NotifyEvent], esi
	jmp	resume_bkgnd_VMs

rbv_call_resume:
	ClrFlag [edi.VDD_Flags], fVDD_WaitAtt
	Trace_Out 'VDD resuming #ebx'
	VMMCall No_Fail_Resume_VM
	jmp	resume_bkgnd_VMs

rbv_done:
	pop	ebx
	pop	edi

rbv_exit:
	ret

EndProc VDD_Proc_Resume_Bkgnd_VMs


;******************************************************************************
;
;   VDD_Proc_Force_Cur_VM_Fgrnd
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
BeginProc VDD_Proc_Force_Cur_VM_Fgrnd

	TestMem [edi.VDD_Flags], fVDD_WaitAtt	;Q: new VM waiting?
	jz	short fcf_skip_notify		;   N:
	TestMem [edi.VDD_Flags], fVDD_CanRestore;Q: VM will restore display?
	jz	short fcf_skip_notify		;   N: resume will be done by
						;	 VDD_Proc_Chk_Bkgnd_Usage
	call	VDD_VM_Mem_Disable_Null 	;   Y: disable mapped null
						;	 memory &
;
; We don't need to do special processing of possible scheduled notify events,
; because we the current VM are running, so either any pending event was already
; processed, or one wouldn't be scheduled!

IFDEF DEBUG
	cmp	[edi.VDD_NotifyEvent], 0	;Q: bgrnd notify pending?
	je	short fcf_notify		;   N: give INT 2F notification
	Debug_Out 'giving FGrnd notification when NotifyEvent != 0'
fcf_notify:
ENDIF
	ClrFlag [edi.VDD_Flags], fVDD_WaitAtt
	call	VDD_Proc_FGrnd_INT2F
fcf_skip_notify:
	ret

EndProc VDD_Proc_Force_Cur_VM_Fgrnd


VxD_CODE_ENDS

	END
