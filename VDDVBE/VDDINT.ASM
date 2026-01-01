       TITLE   VDD - Virtual Display Device for EGA   version 2.30  1/88
;******************************************************************************
;
;VDDINT - Virtual Display Device INT 10h handling
;
;   Author: MDW
;
;   (C) Copyright MICROSOFT Corp. 1986-1990
;
;DESCRIPTION:
;	This module handles the INT 10h interrupt.  It emulates the write TTY,
;	function 0Eh and does some additional processing during mode changes,
;	function 0 and function 11h(not sub function 30h).  It also does some
;	special processing during function 5 for a VM that is not currently
;	being trapped.
;
;******************************************************************************

	.386p

.xlist
	INCLUDE VMM.Inc
	INCLUDE OPTTEST.INC
	INCLUDE	vpicd.inc
	INCLUDE vdd.inc
	INCLUDE debug.inc
	INCLUDE vdddef.inc
.list


;******************************************************************************
; EXTRN routines and data
;
VxD_CODE_SEG
	EXTRN	VDD_TIO_Set_Trap:NEAR
	EXTRN	VDD_Clr_VM_Time_Out:NEAR
	EXTRN	VDD_Set_VM_Time_Out:NEAR
	EXTRN	VDD_Proc_BGrnd_Notify:NEAR
	EXTRN	VDD_VM_Mem_Disable:NEAR
	EXTRN	VDD_VM_Mem_Free_Pages:NEAR
	EXTRN	VDD_VM_Mem_End_Mode_Chg:NEAR
	EXTRN	VDD_VM_Mem_Change_SaveMem:NEAR
	EXTRN	VDD_VM_Mem_Record_VRAM_Mod:NEAR
	EXTRN	VDD_PH_Mem_Get_Visible_Pages:NEAR
	EXTRN	VDD_PH_Mem_Save_Sys_Latch_Addr:NEAR
	EXTRN	VDD_PH_Mem_Reset_Sys_Visible_Pages:NEAR
	EXTRN	VDD_Ctl_End_Dsp_Crit:NEAR
	EXTRN	VDD_OEM_Mode_Switch_Done:NEAR
IFDEF SysVMin2ndBank
	EXTRN	VDD_OEM_force_bank:NEAR
ENDIF
	EXTRN	VDD_State_Save_CRTC_Owner:NEAR
	EXTRN	VDD_State_Scrn_Off:NEAR
	EXTRN	VDD_State_Scrn_On:NEAR
	EXTRN	VDD_State_Get_Screen_Start:NEAR
	EXTRN	VDD_State_Get_Dimensions:NEAR
	EXTRN	VDD_Update_Window:NEAR
VxD_CODE_ENDS

VxD_DATA_SEG
	EXTRN	Vid_Flags:DWORD
	EXTRN	Vid_CB_Off:DWORD
	EXTRN	Vid_CRTC_VM:DWORD
	EXTRN	Vid_Msg_VM:DWORD
	EXTRN	Vid_Scroll_Freq:DWORD
	EXTRN	Vid_PhysA0000:DWORD

;*******
; INT 10h real mode seg:offset hook vectors
;
	PUBLIC	Vid_I10_OldVector
Vid_I10_OldVector   DD	    0			; Previous INT 10h vector
	PUBLIC	Vid_Stub_I10_Vector
Vid_Stub_I10_Vector DD	    ?			; Address of our INT 10h routine

;*******
; INT 10h protect mode selector:offset
;
	PUBLIC	Vid_I10_Next_CS
	PUBLIC	Vid_I10_Next_EIP
Vid_I10_Next_CS     DD	    ?
Vid_I10_Next_EIP    DD	    ?

IFDEF	VRTCTIMER
;*******
; IRQ2/9 handle for vertical retrace interrupt
;
VDD_VRTC_IRQ_Handle DD      ?
ENDIF

;*******
; INT 2Fh protect mode selector:offset to chain to if not our INT 2Fh
;
	PUBLIC	Vid_I2F_Next_CS
	PUBLIC	Vid_I2F_Next_EIP
Vid_I2F_Next_CS     DD	    ?
Vid_I2F_Next_EIP    DD	    ?

;*******
; number of times entered video (INT 2F) critical section
;
Vid_Crit_Cnt	    DB	    ?
Vid_Alt_Int9	    DB	    1
		    DB	    ?,?

; SHOULD BE DWORD ALIGNED!!!

VxD_DATA_ENDS


IFDEF	VRTCTIMER
VxD_IDATA_SEG
;*******
; IRQ2/9 descriptor for vertical retrace interrupt
;
VDD_VRTC_IRQ_Desc LABEL DWORD
VPICD_IRQ_Descriptor <2,VPICD_Opt_Can_Share,		\
		      OFFSET32 VDD_Int_VRTC_HW_IRQ,,	\
		      OFFSET32 VDD_Int_VRTC_EOI,,,>
VxD_IDATA_ENDS
ENDIF

VxD_ICODE_SEG

;******************************************************************************
;
;   VDD_Int_10_Stub
;
;   DESCRIPTION:    Stub of code which is copied down into V86 memory and is
;		    hooked into the INT 10 chain so that VDD can be notified
;		    of mode change INT 10's.  Note that this is real mode 16
;		    bit code but since it is in a 32 bit segment as far as the
;		    assembler is concerned, we specify everything as DWORD.
;		    Do not use any protect mode instructions herein.
;
;   ENTRY:	    none - this routine is not to be called in pmode!!!!!!!!!
;
;   EXIT:
;
;   USES:
;
;==============================================================================
%OUT Add SYSTEM.INI switch to disable this stuff (just use INT 10 trap)
VDD_Int_10_Stub PROC NEAR    ;don't use BeginProc/EndProc to avoid any
				;preamble stuff!
	push	di			    ; really EDI
	or	ah, ah			    ;Q: Mode setting?
	je	SHORT VIS_mode		    ;	Y: notify VDD and reflect
	cmp	eax,4F02h		    ; Q: Mode setting (VBE)?
	;This kinda sucks: we had to use EAX in the above instruction since it's
	; being assembled in a 32-bit segment but will be run in a 16-bit one.
	; That means we've two bytes gone begging, so we have to move the
	; pointer back by two to overwrite them...
	org	$-2
	jz	SHORT VIS_mode		    ;	Y: notify VDD and reflect
	cmp	ah,05h			    ;Q: Page changeing?
	jz	SHORT VIS_mode		    ;	Y: notify VDD and reflect
	cmp	ah, 11h 		    ;Q: Mode setting(via char set chg)?
	jne	SHORT VIS_reflect	    ;	N: reflect
	cmp	al, 3			    ;Q: Set char map
	je	SHORT VIS_reflect	    ;	Y: reflect
	cmp	al, 30h 		    ;Q: Get font info?
	je	SHORT VIS_reflect	    ;	Y: reflect
VIS_mode:
	; allow the end breakpoint handler to see what was originally in EAX,
	; by stuffing it into EDI (which should be unaffected by any of these
	; calls)
	mov	di,ax			    ; really EDI,EAX
VIS_start_bp equ $ - VDD_Int_10_Stub
	nop				    ; a V86 brkpt will be installed here

	pushfd				    ; in 16 bit segment this is a pushf
	;call old handler
	db	9Ah
VIS_call equ $ - VDD_Int_10_Stub
	dd	?

VIS_end_bp equ $ - VDD_Int_10_Stub
	nop				    ; a V86 brkpt will be installed here
	pop	di			    ; really EDI
	iretd				    ; in 16 bit segment this is an iret

VIS_reflect:
	pop	di			    ; really EDI

	cmp	eax,4F03h		    ; Q: Mode getting (VBE)?
	;This kinda sucks: we had to use EAX in the above instruction since it's
	; being assembled in a 32-bit segment but will be run in a 16-bit one.
	; That means we've two bytes gone begging, so we have to move the
	; pointer back by two to overwrite them...
	org	$-2
	je	SHORT VIS_modeget

	;jmp to old handler
	db	0EAh
VIS_jmp equ $ - VDD_Int_10_Stub
	dd	?

VIS_modeget:
VIS_modeget_bp equ $ - VDD_Int_10_Stub
	; trap to VDD, which simulates an IRET for us
	nop

VIS_stub_size equ $ - VDD_Int_10_Stub

VDD_Int_10_Stub ENDP



;******************************************************************************
;
;   VDD_Int_Device_Init
;
;   DESCRIPTION:    Set up interrupt vectors and INT 10h stub.
;
;   ENTRY:  EBX = VM_Handle of System VM
;	    EDI = VDD control block data ptr
;
;   EXIT:   Carry cleared or Fatal_Memory_Error called
;
;   USES:   Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_Int_Device_Init

;*******
;Copy INT 10 stub down into V86 memory and save old Int vector
;
	mov	eax, 10h
	VMMCall Get_V86_Int_Vector
	shl	ecx, 16
	mov	cx, dx
	mov	[Vid_I10_OldVector], ecx

	push	ecx
	VMMCall _Allocate_Global_V86_Data_Area, <VIS_stub_size, 0>
	pop	edx
	or	eax, eax
	jnz	SHORT alloc_ok
Debug_Out "ERROR: Could not allocate global VM data area for VDD int 10 hook"
	VMMCall Fatal_Memory_Error
alloc_ok:
	push	edi
	mov	edi, eax
	mov	esi, OFFSET32 VDD_Int_10_Stub
	mov	ecx, VIS_stub_size
	cld
	Begin_Touch_1st_Meg
	rep	movsb
	mov	edi, eax
	mov	[edi+VIS_call], edx	    ; patch CALL to point to old handler
	mov	[edi+VIS_jmp], edx	    ; patch JMP to point to old handler
	End_Touch_1st_Meg
	shr	eax, 4
	movzx	ecx, ax
	mov	edx, edi
	and	edx, 0Fh
	mov	eax, 10h
	VMMCall Set_V86_Int_Vector
	mov	eax, ecx
	shl	eax, 16
	add	eax, edx
	mov	[Vid_Stub_I10_Vector], eax  ; save our new vector setting
	add	eax, VIS_start_bp
	xor	edx, edx
	mov	esi, OFFSET32 VDD_Int_10_Mode_Switch
	VMMCall Install_V86_Break_Point
	add	eax, VIS_end_bp - VIS_start_bp
	mov	esi, OFFSET32 VDD_Int_10_Mode_Sw_Done
	VMMCall Install_V86_Break_Point
	add	eax, VIS_modeget_bp - VIS_end_bp
	mov	esi, OFFSET32 VDD_Int_10_Mode_Get
	VMMCall Install_V86_Break_Point
	pop	edi
	mov	esi,OFFSET32 VDD_Int_10     ; ESI = address of handler
	mov	eax,10h
	VMMCall Hook_V86_Int_Chain	    ; Hook Int 10h

;
; hook int 16 and int 9 for idle detection....
;

	mov	esi,OFFSET32 VDD_Int_16
	mov	eax,16h
	VMMCall	Hook_V86_Int_Chain	    ; hook int 16
	mov	esi,OFFSET32 VDD_Int_9
	mov	eax,9
	VMMCall	Hook_V86_Int_Chain	    ; hook int 9

;
; hook PM int 10 chain
;
	mov	eax, 10h
	VMMcall Get_PM_Int_Vector
	mov	[Vid_I10_Next_CS], ecx
	mov	[Vid_I10_Next_EIP], edx

	mov	esi, OFFSET32 VDD_Int_10_PM
	VMMcall Allocate_PM_Call_Back

	movzx	edx, ax
	mov	ecx, eax
	shr	ecx, 16
	mov	eax, 10h
	VMMcall Set_PM_Int_Vector

;
; hook int 2F chains
;
	mov	esi,OFFSET32 VDD_Int_2F     ; ESI = address of handler
	mov	eax,2Fh
	VMMCall Hook_V86_Int_Chain	    ; Hook V86 Int 2Fh

	mov	eax, 2Fh
	VMMcall Get_PM_Int_Vector
	mov	[Vid_I2F_Next_CS], ecx
	mov	[Vid_I2F_Next_EIP], edx

	mov	esi, OFFSET32 VDD_Int_2F_PM
	VMMcall Allocate_PM_Call_Back

	movzx	edx, ax
	mov	ecx, eax
	shr	ecx, 16
	mov	eax, 2Fh
	VMMcall Set_PM_Int_Vector

IFDEF	VRTCTIMER
;
; setup VRTC IRQ virtualization
;
	push	ebx
	VxDCall	VPICD_Get_Version
	test	ebx,1					; Q: cascaded PICs?
	pop	ebx					;
	jz	short @F				;    N: VRTC is IRQ2 
	mov	[VDD_VRTC_IRQ_Desc.VID_IRQ_Number],9	;    Y: VRTC is IRQ9

@@:	push	edi
	mov	edi, OFFSET32 VDD_VRTC_IRQ_Desc
	VxDCall	VPICD_Virtualize_IRQ
	pop	edi
	jc	short @F				; no big deal if we can't
	mov	[VDD_VRTC_IRQ_Handle],eax
@@:
ENDIF

	clc
	ret

EndProc VDD_Int_Device_Init

VxD_ICODE_ENDS


IFDEF	VRTCTIMER
;---------------------------------------------------------------------------;
;                   N O N P A G E A B L E   C O D E
;---------------------------------------------------------------------------;

VxD_LOCKED_CODE_SEG

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;   VDD_Int_VRTC_HW_IRQ
;
;   DESCRIPTION:
;       Reflects interrupt to current owner or handles it if no owner.
;
;   ENTRY:
;       EAX = IRQ Handle
;       EBX = Current VM Handle
;
;   EXIT:
;	CF clear if we handled it
;	CF set if it's not ours
;
;   USES:
;       Flags, EAX, EBX
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
BeginProc VDD_Int_VRTC_HW_IRQ

	push	edx
	mov	dx,pStt0EGA
	in	al,dx			; get misc status
	pop	edx
	test	al,fStt0VRTC		; Q: VRTC interrupt asserted?
	jnz	short @F		;    Y: Pass it to CRTC owner
	stc				;    N: not ours, don't service
	ret

@@:	mov	ebx,[Vid_CRTC_VM]
	VMMCall	Validate_VM_Handle	; Q: CRTC owned by valid VM?
	jc	short @F		;    N: handle it ourselves
        VxDcall VPICD_Set_Int_Request   ;    Y: set int request and return
	push	ecx
	VxDcall	VPICD_Get_Complete_Status
	test	ecx,VPICD_Stat_Virt_Mask; Q: CRTC owner has masked the IRQ?
	pop	ecx			;
	jz	short @F		;    N: let it send the EOI
	VxDcall	VPICD_Phys_EOI		;    Y: send EOI NOW while virtual IRQ pending
@@:     clc
        ret

@@:	; we're handling the IRQ ourselves - reset the IRQ Clear bit,
	; and send EOI
	push	edx
	push	eax

	mov	dx,pCRTCIndxColr
	in	al,dx
	mov	bl,al			; save index

	mov	al,C_VRTCEnd-C_HTotal
	out	dx,al
	inc	dx
	in	al,dx
	and	al,NOT fVRTCEndIRQClr	; turn off IRQ Clear bit
	out	dx,al
	or	al,fVRTCEndIRQClr	; turn it back on
	out	dx,al

	dec	dx
	mov	al,bl			; restore index
	out	dx,al

	pop	eax
	pop	edx
        VxDcall	VPICD_Phys_EOI		; physical end of interrupt
	clc
	ret

EndProc VDD_Int_VRTC_HW_IRQ

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;   VDD_Int_VRTC_EOI
;
;   DESCRIPTION:
;       Clears the interrupt request and does the physical EOI
;
;   ENTRY:
;       EAX = IRQ Handle
;       EBX = Current VM Handle
;
;   EXIT:
;
;   USES:
;       Flags
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
BeginProc VDD_Int_VRTC_EOI

	cmp	ebx,[Vid_CRTC_VM]	; Q: EOI came from CRTC owner?
	jne	short @F		;    N: it's a virtual IRQ
        VxDcall VPICD_Clear_Int_Request	;    Y: clear virtual IRQ request

	push	ecx
	VxDcall	VPICD_Get_Complete_Status
	test	ecx,VPICD_Stat_Phys_In_Serv
	pop	ecx			; Q: IRQ still in service?
	jz	short VIVE_done		;    N: we're finished
	VxDjmp	VPICD_Phys_EOI		;    Y: physical end of interrupt

@@:	; this is a virtual IRQ, check if it's been acked correctly
	push	edi
	SetVDDPtr edi
	TestMem	[edi.VDD_Stt.V_Stat0],fStt0VRTC
	pop	edi
	jnz	short @F
VIVE_done:
	ret

@@:	; If the virtual flip-flop stayed high, it means the VM didn't
	; acknowledge the VRTC IRQ correctly before sending EOI.
	; This means we need to clear the request NOW rather than
	; assuming it was done already. It also probably means that
	; the VM didn't really want a VRTC IRQ, but just programmed
	; the registers incorrectly. Since the flip-flop stays high,
	; they won't be bothered again, but let's make a note of it...
IFDEF	DEBUG
	Debug_Out "#EBX did not ack VRTC IRQ before sending EOI!"
ENDIF
	VxDcall	VPICD_Clear_Int_Request	; clear request anyway
	ret

EndProc VDD_Int_VRTC_EOI

VxD_LOCKED_CODE_ENDS
ENDIF	;VRTCTIMER


VxD_CODE_SEG

IFDEF	VRTCTIMER
;******************************************************************************
;
;   VDD_Int_Set_VRTC_IRQ
;
;   DESCRIPTION:    Send a virtual VRTC IRQ to the VM
;
;   ENTRY:  EBX = VM handle
;
;   EXIT:   none
;
;   USES:   Flags
;
;==============================================================================
BeginProc VDD_Int_Set_VRTC_IRQ

	push	eax
	mov	eax, [VDD_VRTC_IRQ_Handle]
	test	eax, eax
IFDEF	DEBUG
	jnz	SHORT @F
	Debug_Out "#EBX requires VRTC IRQ, which we failed to virtualize"
@@:
ENDIF
	jz	SHORT @F
	VxDcall	VPICD_Set_Int_Request
@@:	pop	eax
	ret

EndProc VDD_Int_Set_VRTC_IRQ

;******************************************************************************
;
;   VDD_Int_Clear_VRTC_IRQ
;
;   DESCRIPTION:    Turn off a virtual VRTC IRQ for the VM
;
;   ENTRY:  EBX = VM handle
;
;   EXIT:   none
;
;   USES:   Flags
;
;==============================================================================
BeginProc VDD_Int_Clear_VRTC_IRQ

	push	eax
	mov	eax, [VDD_VRTC_IRQ_Handle]
	test	eax, eax
	jz	SHORT @F
	VxDcall	VPICD_Clear_Int_Request
@@:	pop	eax
	ret

EndProc VDD_Int_Clear_VRTC_IRQ
ENDIF	;VRTCTIMER


;******************************************************************************
;
;   VDD_Int_Sys_Critical_Exit
;
;   DESCRIPTION:    Restore hooked V86 interrupts
;
;   ENTRY:  none
;
;   EXIT:   none
;
;   USES:   Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_Int_Sys_Critical_Exit

IFDEF	VRTCTIMER
	mov	eax, [VDD_VRTC_IRQ_Handle]
	test	eax, eax
	jz	SHORT @F
	VxDCall VPICD_Force_Default_Behavior
ENDIF

@@:	mov	ecx, [Vid_I10_OldVector]
	jecxz	SHORT VSCE_Return
	movzx	edx, cx
	shr	ecx, 16
	mov	eax, 10h
	VMMCall Set_V86_Int_Vector
VSCE_Return:
	ret

EndProc VDD_Int_Sys_Critical_Exit


;******************************************************************************
;
;   VDD_Int_Can_Emulate
;
;   DESCRIPTION:    Return Z-flag set, if we can emulate an INT 10.
;		    The VidTxtEmulate flag must be set, the INT 10 vector
;		    must be the same as when we started, and the BIOS mode
;		    40:49 must state mode 3.
;
;   ENTRY:  EBX = VM_Handle of System VM
;	    EDI -> VDD control block data
;
;   EXIT:	    Z-flag set, if emulation is possible
;		    ESI = start of video memory
;
;   USES:	    flags, ESI
;
;==============================================================================
BeginProc VDD_Int_Can_Emulate

	TestMem [edi.VDD_PIF],fVidTxtEmulate; Q: INT 10 Emulate ON?
	jz	short ce_cant		    ;	N: Don't emulate
	BEGIN_Touch_1st_Meg
	mov	eax,DWORD PTR ds:[10h*4]
	cmp	eax,[Vid_Stub_I10_Vector]   ; Q: Has anybody hooked INT 10?
	jne	short ce_exit		    ;	Y: not emulated
	cmp	WORD PTR ds:[44Ah],80	    ; Q: 80 columns ?
	jne	short ce_exit		    ;   N: No, don't emulate
	mov	esi,0B8000h
	cmp	BYTE PTR ds:[449h], 3	    ; Q: Really mode 3?
	je	short ce_exit		    ;	N: not emulated
	TestMem [edi.VDD_TFlags],fVT_Mono	; Q: mono supported
	jz	SHORT ce_cant		    ;	N: not emulated
	cmp	BYTE PTR ds:[449h], 7	    ; Q: Really mode 7?
	jne	short ce_exit		    ;	N: not emulated
	mov	esi,0B0000h
ce_exit:
	END_Touch_1st_Meg
	jnz	SHORT esi_ok
	add	esi, [ebx.CB_High_Linear]
	cmp	ebx,[Vid_CRTC_VM]	    ; focus VM ?
	je	SHORT esi_ok	            ; yes, b800, is ok...
	Begin_Touch_1st_Meg
	cmp	BYTE PTR ds:[462h],0
	End_Touch_1st_Meg
	jne	short ce_noalt		    ; no alternate
	call	VDD_VM_Mem_Free_Pages	    ; make sure phys pages are freed
					    ;	so we will restore from save
					    ;	when VM gets focus again
	mov	esi, [edi.VDD_MStt.MSS_plane0.MSS_plane_addr] ; use alternate!!
ce_noalt:
	cmp	esi, esi		    ; return with Z flag set
esi_ok:
	ret

ce_cant:
	END_Touch_1st_Meg
	or	al, 1			    ; clear Z-flag
	ret

EndProc VDD_Int_Can_Emulate

;******************************************************************************
;
; VDD_Int_9
;
;DESCRIPTION: Set key in flag!
;
;ENTRY: EBX = current VM handle
;	EBP = client register pointer
;
;EXIT:	CF = 1
;
;USES:	Flags
;
;==============================================================================
BeginProc VDD_Int_9
	cmp	ebx,[Vid_CRTC_VM]		; Int 9s not seen for bkgnd VMs.
	je	SHORT SkipSetKbdFlag
	xor	[Vid_Alt_Int9],1		; 0 becomes 1, 1 becomes 0.
	jnz	SHORT SkipSetKbdFlag		; look at down, not up
	VxdCall	VDD_Check_Update_Soon
SkipSetKbdFlag:
	stc
	ret
EndProc	VDD_Int_9

;******************************************************************************
;
; VDD_Int_16
;
;DESCRIPTION: If this is a get keyboard status call, then check if video needs
;	      to be updated...
;
;ENTRY: EBX = current VM handle
;	EBP = client register pointer
;
;EXIT:	CF = 1
;
;USES:	Flags
;
;==============================================================================
BeginProc VDD_Int_16
	SetVDDPtr edi
	testMem	[edi.VDD_Flags],fVDD_Win
	jz	SHORT skipBreak			; not windowed
	mov	eax,[ebp.Client_EAX]
	cmp	ah,01h
	jz	SHORT breakHere
	cmp	ah,11h
	jnz	SHORT skipBreak
breakHere:
	cmp	[edi.VDD_Recent_User_Action],0
	je	SHORT skipBreak			; No recent user event
	dec	[edi.VDD_Check_Upd_Soon]
	jnz	SHORT skipBreak
	dec	[edi.VDD_Recent_User_Action]	; we have responded to user
	call	VDD_Clr_VM_Time_Out		;   Y: clear time out and
	SetFlag [edi.VDD_Flags], fVDD_BoostUpdate
	call	VDD_Update_Window		;      paint...
skipBreak:
	stc
	ret
EndProc	VDD_Int_16

;***************************************************************
; UpdateModRect:
;	Updates the mode rect maintained by vdd for windowed dos
;	apps. For full-screen apps, VDD_Mod_Rect = -1.
;
; ENTRY: DH = row, DL = column, EBX = VM handle
; EXIT: NONE
; USES: EAX, ECX
;****************************************************************

BeginProc UpdateModRect

	SetVDDPtr eax			    ; eax points to CB_STRUC
	mov	ecx,[eax.VDD_Mod_Rect]	    ; ecx = <(a,b),(c,d)>
	cmp	ecx,-1
	jz	SHORT UMRDone
	xchg	cl,ch			    ; <a,b,d,c>
	ror	ecx,8			    ; <c,a,b,d>
	cmp	dl,ch			    ; expansion at left required?
	jae	SHORT UMRLeftOK		    ; NO
	mov	ch,dl			    ; expand...
UMRLeftOK:
	cmp	dl,cl			    ; Right ok?
	jbe	SHORT UMRRightOK	    ; YES
	mov	cl,dl			    ; fix it
UMRRightOK:
	ror	ecx,16			    ; <b,d,c,a>
	cmp	dh,cl			    ; top ok?
	jae	SHORT UMRTopOK
	mov	cl,dh
UMRTopOK:
	cmp	dh,ch			    ; bot ok?
	jbe	SHORT UMRBotOK
	mov	ch,dh
UMRBotOK:
	ror	ecx,8			    ; <a,b,d,c>
	xchg	ch,cl
	mov	[eax.VDD_Mod_Rect],ecx	    ; save...
UMRDone:
	ret
EndProc UpdateModRect

;******************************************************************************
;
; VDD_Int_10
;
;DESCRIPTION: Emulate WRITE TTY (Speed hack) and do some state
;	changes for mode change INT 10h's and Page select.
;
;ENTRY: EBX = current VM handle
;	EBP = client register pointer
;
;EXIT:	CF = 1 indicates interrupt is to be reflected, else it has been emulated
;
;USES:	Flags, EAX, ECX, EDX
;
;==============================================================================
BeginProc   VDD_Int_10

	TestMem [Vid_Flags], fVid_MsgInit	; Q: Message mode init'd?
	jz	short @F
	TestMem [Vid_Flags], fVid_DspDrvr_Init
	jnz	short @F
	bts	[Vid_Flags], bVid_Dont_Set_Mode
	jc	short @F
	Push_Client_State
	VMMcall Begin_Nest_V86_Exec		; Get ready for software ints
	mov	[ebp.Client_AX], 0003h		; Set mode
	mov	eax,10h
	VMMcall Exec_Int
	VMMcall End_Nest_Exec			; All done with software ints
	Pop_Client_State
@@:

	SetVDDPtr edi
	mov	eax,[ebp.Client_EAX]
	cmp	ah, 2			    ;Q: set cursor position?
	je	VI10SetCurs		    ;	Y:
	cmp	ah, 3			    ;Q: get cursor position?
	je	VI10GetCurs		    ;	Y:
	cmp	ah, 6
	je	VI10_ScrollWin
	cmp	ah, 7
	je	VI10_ScrollWin
	cmp	ah,9
	je	SHORT VI10_WCA		    ; write char/attr at cursor.
	cmp	ah, 0Eh 		    ;Q: Write TTY function code?
	je	VI10TTY		    	    ;	Y: No TTY to emulate
	or	ah,ah			    ; Q: Mode setting?
	jz	SHORT VI10_mode 	    ;	 Y: notify VDD and reflect
	cmp	ax,4F02h		    ; Q: Mode setting?
	jz	SHORT VI10_mode 	    ;	 Y: notify VDD and reflect
	cmp	ax,4F03h		    ; Q: Mode getting?
	jz	VDD_Int_10_Get_Mode	    ;	 Y: go straight to mode-get fn!
	cmp	ah,11h			    ; Q: Mode setting(via char set chg)?
	jnz	SHORT VI10_Reflect	    ;	N: reflect
	cmp	al,3			    ; Q: Set char map
	jz	SHORT VI10_Reflect	    ;	Y: reflect
	cmp	al,30h			    ; Q: Get font info?
	jz	SHORT VI10_Reflect	    ;	Y: reflect
	cmp	al,20h			    ; Q: setting char map in graphics mode?
	jb	short VI10_Mode 	    ;	N:
	cmp	al,24h
	jbe	short VI10_Reflect	    ;	Y: reflect

VI10_Mode:
	TestMem [edi.VDD_Flags],fVDD_ModeSet; Q: Already doing mode set?
	jnz	SHORT VI10_Reflect    	    ;  Y: Just reflect
	call	VDD_Int_10_Mode_Change_Start
	mov	eax, 5000
	mov	esi, OFFSET32 VDD_Int_10_Mode_Change_End
	mov	edx, [ebp.Client_EAX]
	VMMCall Call_When_VM_Returns
	mov	[edi.VDD_Mod_Rect],-1	    ; !!!look at everything
VI10_Reflect:
	stc				    ; We did not emulate this INT 10h
	ret

;
; Emulate function 9
;
VI10_WCA:
	mov	ecx,eax 		    ; CL = character
	cmp	[ebp.Client_CX],1	    ;Q: write one char only?
	jnz	VI10_Reflect		    ; emulate only one char
	call	VDD_Int_Can_Emulate	    ;Q: can emulate INT 10?
	jnz	VI10_Reflect		    ;	N:
	mov	edi,esi 		    ; EDI = VRAM address
	mov	edx,[ebp.Client_EBX]
	BEGIN_Touch_1st_Meg
	push	edx
	movzx	eax,WORD PTR DS:[44Ch]	    ; crt_len
	movzx	edx,dh
	mul	edx			    ; eax = offset!
	pop	edx
	add	esi,eax 		    ; ESI = address of specified page
	mov	ch,dl			    ; ch = attrib byte

; Emulate TTY out for attribute/character in CX

	movzx	edx,BYTE PTR DS:[462h]	    ; EDX = active page
	movzx	edx,WORD PTR DS:[450h+edx*2] ; DH=row, DL=column
	END_Touch_1st_Meg

; Put character in display memory

	push	ebx
	mov	eax,0A0h		    ; Line Length
	mul	dh			    ; EAX = offset to start of line
	add	eax,esi 		    ; EAX = addr of start of line
	movzx	ebx,dl
	shl	ebx,1			    ; EBX = offset in line to column
	add	eax,ebx 		    ; EAX = addr of char to modify
	mov	[eax],cx		    ; Save character
	pop	ebx			    ; Restore VM handle
	inc	dl			    ; following code assumes
     ;
     ; DH = row, DL = column, EBX = VM handle
     ;
     	call	UpdateModRect		    ; updates the mod rect
	jmp	VI10ExitEmYes	    	    ; don't reflect

;
; Emulate this TTY output call, if possible
;
VI10TTY:
	mov	ecx,eax 		    ; CL = character
	cmp	cl,7			    ; Q: Bell?
	jz	VI10_Reflect		    ;	Y: not emulated
	cmp	cl,0Dh
	jne	SHORT SmoothScroll
	testMem	[edi.VDD_Flags],fVDD_Win    ; windowed?
	jz	SHORT SmoothScroll	    ; Why bother
	dec	[edi.VDD_Scroll_Cntr]
	jnz	SHORT SmoothScroll
	pushad
	mov	eax,[Vid_Scroll_Freq]
	mov	[edi.VDD_Scroll_Cntr],ax    ; reinitialize
	mov	[edi.VDD_Recent_User_Action],1
	call	VDD_Clr_VM_Time_Out	    ; clear time out...
	SetFlag [edi.VDD_Flags], fVDD_BoostUpdate
	call	VDD_Update_Window	    ; update it
	popad
SmoothScroll:
	call	VDD_Int_Can_Emulate	    ;Q: can emulate INT 10?
	jnz	VI10_Reflect		    ;	N:
	mov	edi,esi 		    ; EDI = VRAM address
	BEGIN_Touch_1st_Meg
	movzx	eax,WORD PTR DS:[44Eh]	    ; EAX = offset to active page
	add	esi,eax 		    ; ESI = address of active video page

; Emulate TTY out for character in CL
	movzx	edx,BYTE PTR DS:[462h]	    ; EDX = active page
	movzx	edx,WORD PTR DS:[450h+edx*2] ; DH=row, DL=column
	END_Touch_1st_Meg

	cmp	cl,0Dh			    ; Q: Carriage return?
	jz	SHORT VI10Return	    ;	Y: set column to zero
	cmp	cl,08h			    ; Q: Backspace?
	jz	SHORT VI10BackSp	    ;	Y: back up one col.(unless on edge)
	cmp	cl,0Ah			    ; Q: Linefeed?
	jz	short VI10LineFd	    ;	Y: increment row or scroll

; Put character in display memory

	push	ebx
	mov	eax,0A0h		    ; Line Length
	mul	dh			    ; EAX = offset to start of line
	add	eax,esi 		    ; EAX = addr of start of line
	movzx	ebx,dl
	shl	ebx,1			    ; EBX = offset in line to column
	add	eax,ebx 		    ; EAX = addr of char to modify
	mov	[eax],cl		    ; Save character
	pop	ebx			    ; Restore VM handle
	inc	dl
     ;
     ; DH = row, DL = column, EBX = VM handle
     ;
     	call	UpdateModRect		    ; update the modification rect
	BEGIN_Touch_1st_Meg
	cmp	dl,BYTE PTR DS:[44Ah]
	END_Touch_1st_Meg
	jnz	short VI10SetPos
	xor	dl,dl			    ; should we do update_window?
VI10LineFd:
	BEGIN_Touch_1st_Meg
	cmp	dh,BYTE PTR DS:[484h]
	END_Touch_1st_Meg
	jz	short VI10Scroll
	ja	VI10_Reflect
	inc	dh
     ;
     ; DH = row, DL = column, EBX = VM handle
     ;
VI10SetPos:
	BEGIN_Touch_1st_Meg
	movzx	ecx,BYTE PTR DS:[462h]	    ; ECX = active page
	END_Touch_1st_Meg
	call	VDD_Dspy_SetPosn
VI10ExitEmYes:
	clc
	ret

VI10Return:
	xor	dl,dl
	jmp	VI10SetPos
VI10BackSp:
	or	dl,dl
	jz	VI10SetPos
	dec	dl
	jmp	VI10SetPos
VI10Scroll:
	BEGIN_Touch_1st_Meg
	movzx	ecx,BYTE PTR DS:[462h]	    ; ECX = active page
	END_Touch_1st_Meg
	SetVDDPtr eax			    ; eax points to CB_STRUC
	mov	[eax.VDD_Mod_Rect],-1	    ; !!look at everything
	call	VDD_Dspy_SetPosn
	mov	edi,esi 		    ; EDI = addr of start of video page
	mov	eax,0A0h		    ; EAX = bytes per line
	lea	esi,[edi][eax]		    ; ESI = start of 2nd line
	mul	dh			    ; EAX = number of bytes to move
	or	eax,eax 		    ; Q: Any lines to scroll?
	jz	short VI10ClrLine	    ;	N: Just clear bottom line
	mov	ecx,eax
; NOTE: this must be byte move because 386 locks out DMA during word or dword
;	    moves to video(byte wide) memory
	rep movsb			    ;	Y: Scroll the video memory
VI10ClrLine:
	mov	eax,[edi]		    ; Get char on last line
	mov	al,20h			    ; Make it a blank(save attribute)
	mov	ecx,0A0h/2
	cld
	rep stosw			    ; Clear the line with blanks
	jmp	VI10ExitEmYes		    ; Output emulated, exit

;
; Emulate this Get Cursor Position call, if possible
;
VI10GetCurs:
	call	VDD_Int_Can_Emulate	    ;Q: can emulate INT 10?
	jnz	VI10_Reflect		    ;	N:
	movzx	ecx,[ebp.Client_BH]	    ; ECX = output page
	BEGIN_Touch_1st_Meg
	mov	ax, WORD PTR DS:[460h]	    ; get top & bottom lines of cursor
	mov	[ebp.Client_CX],ax	    ; Client CH,CL = cursor type
	mov	ax, WORD PTR DS:[450h+ecx*2]; get row/column
	END_Touch_1st_Meg
	mov	[ebp.Client_DX],ax	    ; Client DH,DL = cursor posn
	jmp	VI10ExitEmYes		    ; Call emulated, exit

;
; Emulate this Set Cursor Position call, if possible
;
VI10SetCurs:

	movzx	ecx,[ebp.Client_BH]	    ; ECX = output page
	BEGIN_Touch_1st_Meg
	cmp	cl,BYTE PTR ds:[462h]	    ; Q: active page?
	END_Touch_1st_Meg
	jne	VI10_Reflect		    ;	N: reflect
	call	VDD_Int_Can_Emulate	    ;Q: can emulate INT 10?
	jnz	VI10_Reflect		    ;	N:
	mov	edi,esi
	BEGIN_Touch_1st_Meg
	movzx	eax,WORD PTR ds:[44Eh]	    ; EAX = offset to active page
	END_Touch_1st_Meg
	add	esi,eax 		    ; ESI = address of active video page
	mov	edx,[ebp.Client_EDX]	    ; DH,DL = cursor posn desired
	call	VDD_Dspy_SetPosn
	or	dl,dl			    ; set to first col?
	jnz	DEBFAR VI10_Not_First_Col

	SetVDDPtr edi
	testMem	[edi.VDD_Flags],fVDD_Win    ; windowed ?
	jz	SHORT VI10_Not_First_Col

	xchg	dx,[edi.VDD_Last_Int10]	    ; save it
	cmp	dx,[edi.VDD_Last_Int10]	    ; is old row == new row?
	jb	SHORT VI10_Not_First_Col    ; old row < new row
	je	SHORT VI10_Carriage_Return  ; carriage return
	BEGIN_Touch_1st_Meg
	cmp	dh, BYTE PTR ds:[484h]	    ; num_rows
	END_Touch_1st_Meg
	jne	SHORT VI10_Not_First_Col    ; maybe not weird stuff
	dec	dh			    ; look at it again
	cmp	dx,[edi.VDD_Last_Int10]
	jne	SHORT VI10_Not_First_Col    ; Not this stuff
	inc	[edi.VDD_Scroll_Cntr]	    ; ANSI.sys doing funny things.
	jmp	SHORT VI10_Not_First_Col
VI10_Carriage_Return:
	dec	[edi.VDD_Scroll_Cntr]	    ; one line carriage returned
	jnz	SHORT VI10_Not_First_Col    ; counter not zero yet.

	mov	eax,[Vid_Scroll_Freq]	    ; scroll frequency
	mov	[edi.VDD_Scroll_Cntr],ax    ; initialize again
	mov	[edi.VDD_Recent_User_Action],1

	call	VDD_Clr_VM_Time_Out
	SetFlag [edi.VDD_Flags], fVDD_BoostUpdate
	call	VDD_Update_Window

VI10_Not_First_Col:
	jmp	VI10ExitEmYes		    ; Call emulated, exit

;
; Emulate INT 10 Fn 06,07 - Scroll a given a rect up/down
; Client Regs: AH = Fn Number (06 for Up, 07 for Down)
;              AL = number of lines to scroll
;		    if 0,clear the window
;              BH = attribute for blanked area
;              <CH,CL> == <x,y> upper left corner
;              <DH,DL> == <x,y> lower right corner
;
; win386 supports only scrolling full lines
;	i.e. assume CL = 0 and DL is right most col.
VI10_ScrollWin:
	cmp	ebx, [Vid_CRTC_VM]	;Q: focus VM?
	je	VI10_Reflect		;   Y: Don't emulate
	mov	[edi.VDD_Mod_Rect],-1	    ; !!!look at everything

%OUT we may want to add a way to globally disabled emulation of scroll calls

	push	[ebp.Client_EAX]
	push	[ebp.Client_ECX]
	push	[ebp.Client_EDX]

    ; validate that we are dealing with a vga
    ; validate params in client regs
    ;	Ensure CH <= MaxLine, DH <= MaxLine
    ;   Ensure DH >= CH and AL <= (DH-CL)

	mov	al,[ebp.Client_CH]
	BEGIN_Touch_1st_Meg
	test	BYTE PTR DS:[487h],8	; Q: Video subsystem active ?
	jnz	VI10ReflectScroll	;   N: reflect
        cmp     al,BYTE PTR DS:[484h]   ; Q: Start Line OK?
        jbe     SHORT StartLineOK       ;   Y:
        mov     al,BYTE PTR DS:[484h]   ;   N: Clip to max line
        mov     [ebp.Client_CH],al      ;

StartLineOK:
        mov     al,[ebp.Client_DH]
        cmp     al,BYTE PTR DS:[484h]   ; Q: End Line OK?
        jbe     SHORT EndLineOK         ;   Y:
        mov     al,BYTE PTR DS:[484h]   ;   N: Clip to max line
        mov     [ebp.Client_DH],al      ;

EndLineOK:
	END_Touch_1st_Meg
        sub     al,[ebp.Client_CH]      ; Q: End Line >= Start Line?
	jb	VI10ignorescroll	;   N: ignore call

        inc     al                      ; AL = Lines in rect
        cmp     [ebp.Client_AL],al      ; Q: Lines to scroll <= Lines in Rect
	jbe	SHORT Lines_OK		;   Y:
        mov     [ebp.Client_AL],al      ;   N: Clip Lines to scroll to max value

Lines_OK:
	mov	esi, [edi.VDD_MStt.MSS_plane0.MSS_plane_addr]
	call	VDD_State_Get_Screen_Start
	add	esi, eax
	mov	edx, eax
	call	VDD_State_Get_Dimensions
	jc	VI10reflectscroll	; can't emulate if in graphics mode
	mov	eax, ecx		; ecx = # of columns
	mul	[ebp.Client_DH]
	xchg	eax, edx		; eax = start offset
	add	edx, eax		; edx = offset of start of last row
	add	edx, ecx		; edx = offset of start of next row
	add	edx, ecx		;	  after last
	dec	edx
	shr	eax, 12 		; convert byte offsets to page #'s
	shr	edx, 12
@@:
	call	VDD_VM_Mem_Record_VRAM_Mod
	inc	eax
	cmp	eax, edx
	jb	@B

	mov	eax, ecx		; ecx = # of columns

	dec	cl
	cmp	[ebp.Client_CL], cl	;clip columns
	jbe	short @F
	mov	[ebp.Client_CL], cl
@@:
	cmp	[ebp.Client_DL], cl
	jbe	short @F
	mov	[ebp.Client_DL], cl
@@:
	mov	cl, [ebp.Client_CL]
	cmp	cl, [ebp.Client_DL]
	jg	short VI10ignorescroll	; ignore call

	shl	eax, 1
	push	eax			; save Line Length in bytes
	mul	[ebp.Client_CH] 	;
	add	esi,eax 		; ESI = Start of rect
        pop     eax

	push	edi
	movzx	edx, [ebp.Client_DL]	; ending column
	movzx	edi, [ebp.Client_CL]	; starting column
	add	esi, edi		; esi -> first byte of scroll region
	add	esi, edi
	sub	edx, edi
	inc	edx			; EDX = # of columns in the rect
	mov	edi, esi
        cmp     [ebp.Client_AL],0       ; Q: Clear Window Fn?
	je	SHORT BlankWin		;   Y:
        cmp     [ebp.Client_AH],06      ; Q: Scroll Up?
	je	SHORT ScrollUpFn	;   Y:
        call    ScrollWinDown           ;   N:
	jmp	short UpdateAfterScroll
ScrollUpFn:
        call    ScrollWinUp
	jmp	short UpdateAfterScroll

BlankWin:
	xchg	eax, edx		; EAX = # of columns
	sub	edx, eax		; EDX = # of bytes from end of
	sub	edx, eax		;   rect to start of rect in next row
	movzx	ecx,[ebp.Client_DH]
	sub	cl,[ebp.Client_CH]
	inc	cl			; ECX = # of lines in rect
	call	ClearRegion

UpdateAfterScroll:
	pop	edi
%OUT causes problem in pcmail. The stupid program in fact blanks
%OUT some of its part before rewriting the same text! This
%OUT now leads to flashing screen
	SetFlag [edi.VDD_Flags], fVDD_BoostUpdate
	call	VDD_Update_Window
VI10ignorescroll:
	pop	[ebp.Client_EDX]
	pop	[ebp.Client_ECX]
	pop	[ebp.Client_EAX]
	jmp	VI10ExitEmYes

VI10reflectscroll:
	pop	[ebp.Client_EDX]
	pop	[ebp.Client_ECX]
	pop	[ebp.Client_EAX]
	jmp	VI10_Reflect

EndProc VDD_Int_10


;*****************************************************************************
;
; ScrollWinUp
;
; ENTRY: EAX = Line length in bytes
;	 EDX = # of columns in the rect
;        EBX = VM Handle
;        ESI = EDI = Start of Scroll rect
;        EBP = Client Regs Ptr
;
;*****************************************************************************
BeginProc ScrollWinUp

	push	edx			; save # of columns
	mov	edx, eax
        mul     [ebp.Client_AL]
	add	esi,eax 		; ESI = Start of scrolled rect

	movzx	ecx,[ebp.Client_DH]
        sub     cl,[ebp.Client_CH]
        inc     cl                      ; CL = # of lines in the rect
	sub	cl,[ebp.Client_AL]	; CL = # of lines to move

	pop	eax			; eax = # of columns
	sub	edx, eax		; EDX = extra bytes to get to start
	sub	edx, eax		;   of rect in next row

	jecxz	short SWU_BlankScrolledArea
	cld
@@:
	push	ecx
	mov	ecx, eax
	rep	movsw
	add	esi, edx
	add	edi, edx
	pop	ecx
	loop	@B
;
; clear area exposed by the scroll
;
SWU_BlankScrolledArea:
	movzx	ecx,[ebp.Client_AL]

;
; EAX = # of columns
; ECX = # of rows
; EDI -> start of rect to clear
; EDX = # of bytes from end of rect to start of rect in next row
;
ClearRegion:
	mov	esi, eax
        mov     ah,[ebp.Client_BH]      ; use specified attribute
        mov     al,20h
	cld
@@:
	push	ecx
	mov	ecx, esi
	rep stosw			; clear the scrolled area
	add	edi, edx		; add offset to start of rect on next line
	pop	ecx
	loop	@B
        ret

EndProc ScrollWinUp


;*****************************************************************************
;
; ScrollWinDown
;
; ENTRY: EAX = Line length in bytes
;	 EDX = # of columns in the rect
;        EBX = VM Handle
;        ESI = EDI = Start of Scroll rect
;        EBP = Client Regs Ptr
;
;*****************************************************************************
BeginProc ScrollWinDown

	push	ebx
	mov	ebx, eax
	add	esi, edx		; point to first byte beyond end of row
	add	esi, edx
	mov	edi, esi
	movzx	ecx,[ebp.Client_DH]
        sub     cl,[ebp.Client_CH]
        mul     cl
        add     edi,eax                 ; EDI = 1 byte past the end of rect

	mov	eax, ebx
	sub	ebx, edx		; ebx = # of bytes from start to
	sub	ebx, edx		;   end of previous row
	sub	edi, 2			; EDI -> last word in the dest
	sub	cl,[ebp.Client_AL]	; CL =	(# of lines to copy) - 1
	jl	short SWD_BlankScrolledArea
        mul     cl
	add	esi,eax
	sub	esi, 2			; ESI -> last word in the source

	inc	cl			; CL = # of lines to copy
	std
@@:
	push	ecx
	mov	ecx, edx
	rep movsw
	sub	esi, ebx
	sub	edi, ebx
	pop	ecx
	loop	@B

;
; clear area exposed by the scroll
;
;   EDX = # of columns
;   EBX = # of bytes from start to end of previous row
SWD_BlankScrolledArea:
        mov     cl,[ebp.Client_AL]
        mov     ah,[ebp.Client_BH]      ; use specified attribute
	mov	al,20h
	std
@@:
	push	ecx
	mov	ecx, edx
	rep stosw
	sub	edi, ebx
	pop	ecx
	loop	@B
	cld				; safety
	pop	ebx
        ret

EndProc ScrollWinDown


;******************************************************************************
;
;   VDD_Dspy_SetPosn
;
;   DESCRIPTION:
;
;   ENTRY:	    EBX = VM handle
;		    DX = row, column
;		    ECX = active page number
;		    ESI = address of start of video page
;		    EDI = address of start of video memory
;
;   EXIT:
;
;   USES:	    EAX, ECX, flags
;
;==============================================================================
BeginProc VDD_Dspy_SetPosn

	BEGIN_Touch_1st_Meg
	mov	WORD PTR DS:[450h+ecx*2],dx ; save row/column
	END_Touch_1st_Meg
	mov	eax,0A0h
	mul	dh			    ; EAX = offset to start of line
	add	eax,esi 		    ; EAX = addr of start of line
	movzx	ecx,dl
	shl	ecx,1
	add	eax,ecx 		    ; EAX = addr of char to modify
	sub	eax,edi 		    ; EAX = offset from start of VRAM
	shr	eax,1
	xchg	ah,al
	mov	ecx,ebx
	add	ecx,[Vid_CB_Off]
	mov	WORD PTR [ecx.VDD_Stt.C_CAddrH],ax
	sub	ecx,[Vid_CB_Off]
	cmp	ecx,[Vid_CrtC_VM]	    ; Q: Does this VM own CRTC?
	jnz	short VI10SP_exit	    ;	N: Don't do output
	push	edx
	push	eax
	BEGIN_Touch_1st_Meg
	mov	dx,WORD PTR DS:[463h]	    ; DX=CRTC port
	END_Touch_1st_Meg
	mov	al,0Fh
	out	dx,al			    ; Select cursor low addr reg
	inc	edx
	mov	al,ah
	out	dx,al
	dec	edx
	mov	al,0Eh
	out	dx,al			    ; Select cursor high addr reg
	inc	edx
	pop	eax
	out	dx,al
	pop	edx
VI10SP_exit:
	ret
EndProc VDD_Dspy_SetPosn


;******************************************************************************
;
;   VDD_Int_10_Mode_Switch & VDD_Int_10_Mode_Change_Start
;
;   DESCRIPTION:    V86 Breakpoint handler that receives notification from V86
;		    stub when a mode switch or a page change is starting.
;
;   ENTRY:
;	EBX = Current VM Handle
;	EBP -> Client register structure
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc VDD_Int_10_Mode_Switch

	Assert_Cur_VM_Handle ebx
	Assert_Client_Ptr ebp
	inc	[ebp.Client_IP] 		; inc past the brkpt
	SetVDDPtr edi
	cmp	[ebp.Client_AH],05
	jz	VI10_Page_Change

	bt	[edi.VDD_Flags],bVDD_ModeSet	; Q: Already doing mode set?
	jnc	short VDD_Int_10_Mode_Change_Start
	; if we're already modesetting, then skip over the second breakpoint!
	mov	eax,(VIS_reflect - VDD_Int_10_Stub) - (VIS_start_bp+1)
	add	[ebp.Client_IP],ax

; This entry point is used by the INT 10h trapping code
PUBLIC VDD_Int_10_Mode_Change_Start
VDD_Int_10_Mode_Change_Start:

	TestMem [Vid_Flags], fVid_SysVMI	; Q: SYS VM initialized?
	jz	short VI10_Exit 		;   N: ignore the mode switch

	cmp	[ebp.Client_AH], 11h		;Q: font load int10?
	jne	short VI10_not_fontload 	;   N:
	SetFlag [edi.VDD_Flags], fVDD_Font	;   Y: indicate font programming
	jmp	short VI10_skip_font_clr
VI10_not_fontload:
%OUT this is a problem, we don't know when we can stop holding a loaded font
	mov	[edi.VDD_fontpages], 1		; assume only 1 font loaded
VI10_skip_font_clr:

	call	VDD_VM_Mem_Disable

	bts	[edi.VDD_Flags],bVDD_ModeSet	; Q: Already doing mode set?
	jc	SHORT VI10_exit 		;   Y: Just reflect
	call	VDD_TIO_Set_Trap		; Adjust I/O trapping
	mov	eax, High_Pri_Device_Boost	; Hurry through the mode change
	VMMCall Adjust_Exec_Priority

	TestMem [edi.VDD_Flags], fVDD_Win	; Q: Windowed VM?
	jz	SHORT VI10_ChkSvRam		;   N: No stuff for Windowed VMs
	call	VDD_Clr_VM_Time_Out		;   Y: Clear VM timeout and
	SetFlag [edi.VDD_Flags],fVDD_ModeChange ;	doing mode change

; NOTE that when doing a 11xx font change xx never has sign bit set and
;   so the RAM would not be flagged to be saved, but it is suppose to be
;   so we check for font change explicitly and set the save ram flag.
VI10_ChkSvRam:
        mov     ax,[ebp.Client_AX]
	cmp	ah,4Fh
	jne	SHORT @F
	bt	[ebp.Client_BX],bVESA_PreserveMem; Q: Save RAM during mode set?
	jc	SHORT VI10_SetSvRAMBit	    	;   Y: Remember RAM saved
@@:     cmp     ah,11h
	je	SHORT VI10_SetSvRAMBit
	or	al, al				; Q: Save RAM during mode set?
	js	SHORT VI10_SetSvRAMBit		;   Y: flag RAM save
	call	VDD_VM_Mem_Free_Pages		;   N: free current pages w/o saving
	mov	[edi.VDD_saved_visible], 0	; clear saved size
	jmp	SHORT VI10_exit

VI10_SetSvRAMBit:
	SetFlag [edi.VDD_Flags],fVDD_MdSvRam	;   Y: Remember RAM saved
	call	VDD_PH_Mem_Get_Visible_Pages
	add	eax, ecx			; eax = total pages to save
;;
;; we don't need to check here, because VDD_PH_Mem_Get_Visible_Pages will be
;; returning the current value of [edi.VDD_saved_visible] if it is not 0
;;
;;	  cmp	  eax, [edi.VDD_saved_visible]	  ;Q: more pages then previous save?
;;	  jbe	  short VI10_exit		  ;   N:
;;
	mov	[edi.VDD_saved_visible], eax	;   Y: update save size

VI10_exit:
	ret

VI10_Page_Change:
	cmp	ebx,[Vid_CRTC_VM]		; Q: Own CRTC state?
	jnz	SHORT VI10_Exit 		;   N: Already trapping I/O
	bts	[edi.VDD_Flags],bVDD_PageChg	;   Y: update trapping
	jc	SHORT VI10_Exit
	call	VDD_TIO_Set_Trap
	jmp	VI10_Exit

EndProc VDD_Int_10_Mode_Switch

;******************************************************************************
;
;   VDD_Int_10_Mode_Sw_Done & VDD_Int_10_Mode_Change_End
;
;   DESCRIPTION:    V86 Breakpoint handler that receives notification from V86
;		    stub when an INT 10 mode switch has completed.
;
;   ENTRY:
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc VDD_Int_10_Mode_Sw_Done
	Assert_Client_Ptr ebp

	inc	[ebp.Client_IP] 		; inc past the brkpt
	mov	edx,[ebp.Client_EDI]		; get original EAX

; This entry point is from call back if mode change is detected from
; INT 10 trap instead of breakpoint.
PUBLIC VDD_Int_10_Mode_Change_End
VDD_Int_10_Mode_Change_End:
	; this has to happen first to satisfy function contract for
	; VDD_OEM_Mode_Switch_Done below!
	VMMCall Get_Cur_VM_Handle
	SetVDDPtr edi

	call	VDD_OEM_Mode_Switch_Done

	TestMem [Vid_Flags], fVid_SysVMI	; Q: SYS VM initialized?
	jz	SHORT VIR_exit			;   N: ignore the mode switch

	btr	[edi.VDD_Flags],bVDD_PageChg	; Q: end of page change?
	jc	SHORT VIR_Change_Done		;   Y: Adjust mem and trapping

	call	VDD_Set_VM_Time_Out		; Restart window update timeout
						;   if VM is windowed
	btr	[edi.VDD_Flags],bVDD_ModeSet	; No longer critical region
	jnc	SHORT VIR_exit			; Skip unboost if already done


	mov	eax, -High_Pri_Device_Boost
	VMMCall Adjust_Exec_Priority
	call	VDD_VM_Mem_End_Mode_Chg 	; Adjust memory for new mode

IFDEF SysVMin2ndBank
	mov	al, 1
	call	VDD_OEM_force_bank		; switch to 2nd bank, if SYS VM
						;    and we're forcing the SYS
						;    VM into the 2nd bank
ENDIF

VIR_Change_Done:
	call	VDD_TIO_Set_Trap
	ClrFlag [edi.VDD_Flags], <fVDD_MdSvRam OR fVDD_Font>

VIR_exit:
	ret

EndProc VDD_Int_10_Mode_Sw_Done

;******************************************************************************
;
;   VDD_Int_10_Mode_Get & VDD_Int_10_Get_Mode
;
;   DESCRIPTION:    V86 Breakpoint handler that receives notification from V86
;		    stub when an app asks for current VBE mode via INT 10 stub.
;
;   ENTRY:
;
;   EXIT:	In VBE mode: Client_AX == 4Fh, Client_BX == VM's mode
;		In non-VBE mode: Client_AX == 34Fh ("bad mode" error code)
;
;   USES:
;
;==============================================================================
BeginProc VDD_Int_10_Mode_Get

	Assert_Client_Ptr ebp
	VMMCall	Simulate_Iret

; This entry point is from call back if mode change is detected from
; INT 10 trap instead of breakpoint.
PUBLIC VDD_Int_10_Get_Mode
VDD_Int_10_Get_Mode:
	VMMCall Get_Cur_VM_Handle
	SetVDDPtr edi

	mov	[ebp.Client_AX],34Fh	; assume "bad mode"
	mov	cx,[edi.VDD_Stt.V_Extend.VBE_VidModeP1]
	jcxz	short @F

	mov	[ebp.Client_AH],0	; nullify error code
	dec	cx
	mov	[ebp.Client_BX],cx	; report the mode

@@:	clc				; indicate we handled the int
	ret

EndProc VDD_Int_10_Mode_Get


;******************************************************************************
;
;   VDD_Int_10_PM
;
;   DESCRIPTION:    Ignore block set pallete registers, AH=10h, AL=2, when
;		    done during processing of the INT 2F foreground notify.
;
;   ENTRY:	    EBX = VM Handle
;		    Client_AH = function
;		    Client_AL = sub-function
;
;			For Client_AX = 1002h:
;
;			    Client_ES:DX -> 17 byte table
;
;   EXIT:	    none
;
;   USES:	    Preserves Seg registers
;
;==============================================================================
BeginProc VDD_Int_10_PM

	bts	[Vid_Flags], bVid_DspDrvr_Init
	mov	eax, [ebp.Client_EAX]
	cmp	ax, 1002h
	je	short VI10_PM_chk
VI10_PM_Reflect:
	mov	ecx, [Vid_I10_Next_CS]
	mov	edx, [Vid_I10_Next_EIP]
	VMMjmp	Simulate_Far_Jmp

VI10_PM_chk:
	SetVDDPtr edi
	TestMem [edi.VDD_Flags], fVDD_InInt2F
	jz	VI10_PM_Reflect
	VMMjmp	Simulate_Iret

EndProc VDD_Int_10_PM


;******************************************************************************
;
;   VDD_Int_2F_PM
;
;   DESCRIPTION:
;
;   ENTRY:	    EBX = VM handle
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc VDD_Int_2F_PM, High_Freq

	call	VDD_Int_2F
	jnc	SHORT VI2F_PM_Eat_It
	mov	ecx, [Vid_I2F_Next_CS]
	mov	edx, [Vid_I2F_Next_EIP]
	VMMjmp	Simulate_Far_Jmp

VI2F_PM_Eat_It:
	VMMjmp	Simulate_Iret

EndProc VDD_Int_2F_PM


;******************************************************************************
; VDD_Int_2F
;
;DESCRIPTION: Display critical section and enable/disable trapping.
;
;ENTRY: EBX = VM handle
;	EBP = client register pointer
;
;EXIT:	CF = 1 indicates interrupt is to be reflected, else it has been emulated
;
;USES:	Flags
;
;==============================================================================
BeginProc   VDD_Int_2F

	mov	eax,[ebp.Client_EAX]
	cmp	ah,40h			    ; Q:My Int 2F?
	jz	SHORT VI2F_00		    ;	Y: go check subfunction
	stc
	ret				    ;	N: return, CF=1
VI2F_00:
IF 0
	cmp	ax,4040h
	jz	SHORT VI2F_Debug
ENDIF
	or	al,al
	je	SHORT VI2F_CanRestore
	cmp	al,3
	je	VI2F_EnterCrit
	cmp	al,4
	je	VI2F_ExitCrit
	cmp	al,7
	je	SHORT VI2F_CantRestore
	stc
	ret

;******
; VM doesn't know how to restore the screen
;
VI2F_CantRestore:
	SetVDDPtr edi
	ClrFlag [edi.VDD_Flags], <fVDD_CanRestore OR fVDD_NoSaveRes>

	VMMCall Test_Sys_VM_Handle		    ;Q: Sys VM?
	jne	short @F			    ;	N: go free SavedStt
	; When display driver did its ENABLE routine, it may have set its
	; latch address right before doing the "CanRestore" call, and hence
	; set it's # visible pages and the "Aware" flag.
	; Right now it's doing its DISABLE routine, so presumably after that
	; it will no longer be "Aware", and the # visible pages will no
	; longer be valid because it's going back to text mode.
	; So, reset all that stuff here too!
	ClrFlag	[edi.VDD_Flags], <fVDD_DspDrvrAware>
	call	VDD_PH_Mem_Reset_Sys_Visible_Pages
	jmp	VI2F_SetTrap

@@:	xor	eax, eax
	xchg	eax, [edi.VDD_SavedStt]
	or	eax, eax			    ;Q: have SavedStt mem?
	jz	VI2F_SetTrap			    ;	N: can't free SavedStt
	VMMCall _HeapFree, <eax, 0>		    ;	Y: free SavedStt mem
	jmp	VI2F_SetTrap

;******
; VM knows how to restore the screen
;
VI2F_CanRestore:
	dec	al
	mov	[ebp.Client_AL], al
	SetVDDPtr edi

;------------------------------------------------------------------------------
; VDD_Int_Set_CanRestore
;
; Alternate entry point for getting NoSaveRes set again and freeing save mem
; if necessary, after a set type call service call is made to indicate that
; the VM is no longer windowed.
;
PUBLIC VDD_Int_Set_CanRestore
VDD_Int_Set_CanRestore:
	SetFlag [edi.VDD_Flags], fVDD_CanRestore
	VMMCall Test_Sys_VM_Handle
	jne	short @F
	call	VDD_PH_Mem_Save_Sys_Latch_Addr
	TestMem [edi.VDD_Flags], fVDD_DspDrvrAware
	jnz	short @F
;
; Since this display driver apparently isn't 3.1 aware, we will attempt to
; indicate to it that it doesn't have any memory available for "save screen
; bits"
;
	call	VDD_PH_Mem_Get_Visible_Pages
	add	ecx, eax
	shl	ecx, 12
	sub	ecx, SIZE Display_Driver_Data
	add	ecx, [Vid_PhysA0000]

	mov	dx, pGrpIndx
	in	al, dx			; read current grp index
	mov	ah, al			; save in AH
	mov	al, 5			; set grp index = 5 (mode reg)
	IO_Delay
	out	dx, al
	inc	edx
	IO_Delay
	in	al, dx			; read current mode reg
	push	eax			; save AH & AL
	and	al, 11110100b
	IO_Delay
	out	dx, al			; set write mode 0
	mov	dx, pSeqIndx
	IO_Delay
	in	al, dx			; read current seq index
	mov	ah, al			; save in AH
	mov	al, 2			; set seq index = 2 (map mask reg)
	IO_Delay
	out	dx, al
	inc	edx
	IO_Delay
	in	al, dx			; read current map mask
	push	eax			; save AH & AL
	mov	al, 0Fh
	IO_Delay
	out	dx, al			; set to write to all 4 planes
	mov	[ecx.shadow_mem_status], 0  ; write a 0
	pop	eax			; pop saved AH & AL
	IO_Delay
	out	dx, al			; restore map mask
	dec	edx
	mov	al, ah			; restore seq index
	IO_Delay
	out	dx, al
	mov	dx, pGrpData
	pop	eax			; pop saved grp index & mode reg
	IO_Delay
	out	dx, al			; restore mode reg
	dec	edx
	mov	al, ah
	IO_Delay
	out	dx, al			; restore grp index
@@:

;
; copy current controller state
;
	lea	eax, [edi.VDD_SttCopy]
	VMMCall Test_Sys_VM_Handle		    ;Q: Sys VM?
	jz	short VI2F_save_ptr		    ;	Y: use SttCopy for copy
	mov	eax, [edi.VDD_SavedStt]
	or	eax, eax			    ;Q: already have SavedStt?
	jnz	short VI2F_got_savedstt 	    ;	Y:
	VMMCall _HeapAllocate, <<SIZE Reg_State_struc>, 0>
VI2F_save_ptr:
	mov	[edi.VDD_SavedStt], eax
	or	eax, eax
	jz	short VI2F_no_savedstt

VI2F_got_savedstt:
	cmp	ebx, [Vid_CRTC_VM]		    ;Q: VM CRTC owner?
	jne	short @F			    ;	N:
	push	eax
	call	VDD_State_Scrn_Off		    ;	Y: turn off screen
	call	VDD_State_Save_CRTC_Owner	    ;	    & save regs
	call	VDD_State_Scrn_On		    ;	      turn scrn back on
	pop	eax
@@:
	lea	esi, [edi.VDD_Stt]
	push	edi
	mov	edi, eax
	mov	ecx, (SIZE Reg_State_struc) / 4
	cld
	rep	movsd
	pop	edi
VI2F_no_savedstt:

	VMMCall Test_Sys_VM_Handle
	jnz	short VI2F_not_sys_vm
	TestMem [edi.VDD_TFlags], fVT_NoSaveResSysVM	;Q: save/res of sys VM?
	jmp	short VI2F_chk_flag
VI2F_not_sys_vm:
	TestMem [edi.VDD_TFlags], fVT_NoSaveResOthers	;Q: save/res of this VM?
VI2F_chk_flag:
	jz	short VI2F_SetTrap		    ;	Y: set trapping & exit
	SetFlag [edi.VDD_Flags], fVDD_NoSaveRes
	TestMem [ebx.CB_VM_Status], VMStat_Suspended;Q: VM already suspended?
	jz	short VI2F_SetTrap		    ;	N: set trapping & exit
	call	VDD_Proc_BGrnd_Notify		    ;	Y: schedule BGrnd notify
VI2F_SetTrap:
	call	VDD_VM_Mem_Change_SaveMem
	call	VDD_TIO_Set_Trap
VI2F_Emulated:
	clc
	ret

;******
; Enter critical section
;
VI2F_EnterCrit:
	bts	[Vid_Flags],bVid_Crit
	jc	SHORT VI2F_Already_Crit
	mov	eax, Critical_Section_Boost
	VMMCall Adjust_Exec_Priority
	mov	[Vid_Crit_Cnt],0
VI2F_Already_Crit:
	inc	[Vid_Crit_Cnt]
	jmp	short VI2F_Emulated

;******
; Exit critical section
;
VI2F_ExitCrit:
	dec	[Vid_Crit_Cnt]
	jnz	SHORT VI2F_Emulated
	btr	[Vid_Flags],bVid_Crit
	jnc	SHORT VI2F_Emulated
	mov	eax, -Critical_Section_Boost
	VMMCall Adjust_Exec_Priority

;******
; Do actions (like set focus) that were delayed because of critical section
;
	call	VDD_Ctl_End_Dsp_Crit
	clc
	ret

IF   0
VI2F_Debug:

	pushad
; Temp testing code goes here. Invoked by INT 2F, AX = 4040h from VM.
	stc
	popad
	ret
ENDIF
EndProc   VDD_Int_2F



VxD_CODE_ENDS

	END
