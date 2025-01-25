       TITLE   VDD - Virtual Display Device	    version 3.1
;******************************************************************************
;
;VDDOEM    Virtual Display OEM Device specific routines
;
;   Author: MDW
;
;   (C) Copyright MICROSOFT Corp. 1986-1991
;
;
;DESCRIPTION:
;	This module is called from various other modules to perform operations
;	specific to an OEM's hardware or the operation is slightly different
;	on different pieces of hardware for one VDD.
;
;******************************************************************************

	.386p

	INCLUDE VMM.INC
	INCLUDE OPTTEST.INC
	INCLUDE DEBUG.INC
	INCLUDE VDDDEF.INC


VxD_Data_SEG
EXTRN	Vid_Flags:DWORD
EXTRN	VT_Flags:DWORD
EXTRN	Vid_CB_Off:DWORD
EXTRN	Vid_Focus_VM:DWORD
EXTRN	Vid_CRTC_VM:DWORD
EXTRN	Vid_MemC_VM:DWORD

IFDEF CLV7VGA
; Table of masks for extended sequencer registers
;
; Note that some bits actually affect the CRTC as well as MemC, most notably,
;   the special 256 color mode bits in register FC.  These are assigned to
;   the CRTC and if a background application has these bits different than
;   the CRTC owner the results are undefined (don't do that)!
mVid_CLV7_MemC LABEL BYTE
;		   0	1    2	  3    4    5	 6    7
	DB	   0,	0,   0,   0,   0,   0,	 0,   0    ;80
	DB	   0,	0,   0,   0,   0,   0,	 0,   0    ;88
	DB	   0,	0,   0,   0,   0,   0,	 0,   0    ;90
	DB	   0,	0,   0,   0,   0,   0,	 0,   0    ;98
	DB	   0,	0,   0,   0,   0,   0,	 0,   0    ;A0
	DB	   0,	0,   0,   0,   0,   0,	 0,   0    ;A8
	DB	   0,	0,   0,   0,   0,   0,	 0,   0    ;B0
	DB	   0,	0,   0,   0,   0,   0,	 0,   0    ;B8
	DB	   0,	0,   0,   0,   0,   0,	 0,   0    ;C0
	DB	   0,	0,   0,   0,   0,   0,	 0,   0    ;C8
	DB	   0,	0,   0,   0,   0,   0,	 0,   0    ;D0
	DB	   0,	0,   0,   0,   0,   0,	 0,   0    ;D8
First_Memc_Reg	EQU 0E0h
%OUT register E0 is not documented - is this right?
	DB	0DAh,	0,   0,   0,   0,   0,	 0,   0    ;E0
	DB	   0,	0,   0,   0,0FFh,0FFh,0FFh,0FFh    ;E8
	DB	   0,033h,   0,003h,0FFh,0FFh,00Fh,   0    ;F0
	DB	   0,001h,00Fh,00Fh,036h,   0,00Eh,00Fh    ;F8
.errnz $-mVid_CLV7_MemC-128
ENDIF

IFDEF NEWCLVGA
;----------------------------------------------------------------------------
; 
; 0 - unused, not a valid extension register
; 1 - CRTC extension register
; 2 - Not a CRTC extension register(MemC extension register)
;
        ;       0 1 2 3 4 5 6 7 8 9 a b c d e f

;
; ok, the new scheme is that 0-7fh will be stored into the V_Extend part
; of the Reg_State_Struc, and 80 to DF will be stored in the C_Extension
; part of the CRTC block of the Reg_State_Struc.
;
.errnz (CL_Resvd LE 60h)
.errnz (Extended_Reg_Size LT 80h)
MIN_NewCLTable  equ     00dh
NewCLExtRegTable:
        db      0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,2         ; 0
        db      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0         ; 1
        db      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0         ; 2
        db      1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0         ; 3
        db      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0         ; 4
        db      1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1         ; 5
        db      1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1         ; 6
        db      1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1         ; 7
MAX_V_Extend equ 7fh
MIN_C_Extension equ 80h
        db      1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1         ; 8
        db      1,1,1,1,1,1,1,1,1,0,1,1,0,0,2,2         ; 9
        db      2,2,1,1,1,1,2,2,2,2,2,2,2,2,2,2         ; a
        db      0,0,1,1,1,1,1,1,1,1,2,2,2,2,2,2         ; b
        db      1,1,0,0,0,0,1,1,1,1,1,1,1,1,1,1         ; c
        db      1,1,1,1,1,1,1,1,1,0,1,1,1,0,0,0         ; d
MAX_C_Extension equ MIN_C_Extension+60h
; dont cares    
;        db      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0         ; e
;        db      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0         ; f

;MAX_NewCLTable  equ     0e0h
;LEN_NewCLTable  equ     $-NewCLExtRegTable
.errnz ($-NewCLExtRegTable-0e0h)
ENDIF ; NEWCLVGA

;*******
; OEM Specific global values
;

IFDEF CLV7VGA
; For Video 7 and Cirrus Logic VGAs, the following contains the values
;   that are output to Seq.6 reg to enable/disable the extension registers
;   Note that the value must directly follow the Index so we can load word.
Vid_Enable_IV_Word  LABEL WORD
		    DB	6
Vid_Enable_Ext_Val  DB	?
.ERRE Vid_Enable_Ext_Val EQ Vid_Enable_IV_Word+1

Vid_Disable_IV_Word LABEL WORD
		    DB	6
Vid_Disable_Ext_Val DB	?
.ERRE Vid_Disable_Ext_Val EQ Vid_Disable_IV_Word+1
ENDIF

IFDEF Handle_VGAEnable
Vid_OEM_Port_Enable DW	?
ENDIF

VxD_Data_ENDS

VxD_IData_SEG
IFDEF	ATIVGA
; ATI VGA extended registers
Begin_VxD_IO_Table Vid_ATIVGA_IO_Table
; ATI's extended registers can be located other than at 1CE & 1CF
	VxD_IO	  1CEh, VIOT_ATI
	VxD_IO	  1CFh, VIOT_ATI
End_VxD_IO_Table Vid_ATIVGA_IO_Table
ENDIF
VxD_IData_ENDS



VxD_Code_SEG
EXTRN	VDD_VGA_Restore_DAC:NEAR
EXTRN	VDD_State_Attr_Out:NEAR
EXTRN	VDD_State_Set_MemC_Owner:NEAR
EXTRN	VDD_State_OutC_Ctrlr:NEAR
IFDEF	DEBUG
EXTRN	VDD_Reg_Dump:NEAR
ENDIF
EXTRN	VDD_State_Get_CRTC_Index_Port:NEAR
IFNDEF	VGA8514	; VBE and 8514 detection are mutually exclusive from VDDDEF.INC
EXTRN	VDD_State_Get_Mode:NEAR
EXTRN	VDD_State_Set_Mode:NEAR
ENDIF	;VGA8514
VxD_Code_ENDS


VxD_DATA_SEG

IFDEF TLVGA
PUBLIC TL_Switches
TL_Switches   db  0
ENDIF

IFNDEF	VGA8514	; VBE and 8514 detection are mutually exclusive from VDDDEF.INC
VBE_Int10_Buf	dd ?
VBE_Int10_Off	dw ?
VBE_Int10_Seg	dw ?
ENDIF	;VGA8514

VxD_DATA_ENDS


VxD_ICode_SEG
;******************************************************************************
;VDD_OEM_Sys_Critical_Init
;
;DESCRIPTION:
;
;	state set up.
;
;ENTRY: EBX = VM_Handle of SYS VM
;	EDI -> VDD CB data of SYS VM
;
;EXIT:	If error, Carry is set
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_OEM_Sys_Critical_Init

IFDEF	TLVGA
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jz	short sci_not_tlvga
;
; read switches
;
	mov	dx, pStatColr
	mov	ecx,8000h
@@:
	in	al,dx
	test	al,fStatVRTC
	loopz	@B

	mov	dx, pMiscRead
	in	al, dx
	mov	ah, al
	sub	dl, (pMiscRead - pMisc) AND 0FFh
	and	al, 11110011b
	mov	cl, al
	mov	ch, 1000b		; use as an end signal
@@:
	mov	al, cl
	out	dx, al
	in	al, dx
	add	cl, 100b
	bt	eax, 4
	rcr	ch, 1
	jnc	@B
	mov	al, ah
	out	dx, al
	shr	ch, 4
	mov	[TL_Switches], ch
	jmp	sci_exit

sci_not_tlvga:
ENDIF	;TLVGA

IFDEF	CLV7VGA
	TestMem [edi.VDD_TFlags],<fVT_V7VGA+fVT_CLVGA>
	jz	SHORT VOSCI_NotCLV7VGA
	mov	dx,pMiscRead 	        ; misc output read back
	in	al,dx		        ; read misc output
	mov	dx,pCRTCIndxColr        ; assume 3dx addressing
	test	al,1		        ; really 3dx addressing ?
	jnz	SHORT save_crc	        ; yes
	mov	dx,pCRTCIndxMono        ; nope, 3bx addressing
save_crc:	
        mov	al,0ch		        ; screen a start address hi
	out	dx,al		        ; select index
	inc	edx			; point to data
	mov	ah,al		        ; save index in ah
	in	al,dx		        ; get screen a start address hi
	xchg	ah,al		        ; swap index and data
	push	eax		        ; save old value
	push	edx		        ; save crtc address
	xor	al,al		        ; clear crc
	out	dx,al		        ; and out to the crtc

	mov	al,1fh		        ; Eagle ID register
	dec	edx			; back to index
	out	dx,al		        ; select index
	inc	edx			; point to data
	in	al,dx		        ; read the id register
	mov	ch,al		        ; and save it in ch

        pop	edx		        ; restore crtc address
	dec	edx			; point to index
	pop	eax		        ; recover crc index and data
	out	dx,ax		        ; restore crc value
; ch has enable value
        mov     al,ch
	mov	[Vid_Enable_Ext_Val],al
        rol     al,4
	mov	[Vid_Disable_Ext_Val],al

VOSCI_NotCLV7VGA:
ENDIF ;CLV7VGA

IFDEF CTVGA
;*******
;Disable traps on CRT Regs by resetting trap bit in CRT emulation mode Reg.
;
IFDEF	VGAMONO
;;;???
%OUT	Need 3Dx/3Bx addressing detection here
ENDIF	;VGAMONO
        mov     dx,pIndx6845Colr
        mov     ax,0FFh                     ; Emulation mode Reg-CRT Reg in CTVGA
        out     dx,ax
	inc	edx
        in      ax,dx
        and     ax,11011111B                ; Reset trap bit 5, others unchanged 
        out     dx,ax

	mov	byte ptr [edi.VDD_Stt.G_CTCtl],20h
	mov	byte ptr [edi.VDD_Stt.C_CT400],7Ch
	mov	byte ptr [edi.VDD_Stt.C_CTTempFE],07h
ENDIF	;CTVGA

IFNDEF	VGA8514	; VBE and 8514 detection are mutually exclusive from VDDDEF.INC
	TestMem [edi.VDD_TFlags],<fVT_VBESVGA>
	jz	VOSCI_NotVBE
	; create a dual-use buffer in conventional memory that we can use to:
	; * get mode info from int 10h
	; * pass CRTC Info block to int 10h if needed
	VMMCall _Allocate_Global_V86_Data_Area, <VESAModeSize, 0>
.ERRE	((SIZE VBE3_CRTCInfoBlock) LE VESAModeSize)	; buffer has to fit either of these (not together)
	or	eax, eax
	jnz	SHORT alloc_ok
Debug_Out "ERROR: Could not allocate global VM data area for communication with int 10h"
	VMMCall Fatal_Memory_Error
alloc_ok:
	mov	[VBE_Int10_Buf],eax
	mov	dx,ax
	and	dx,0Fh
	shr	eax,4
	mov	[VBE_Int10_Seg],ax
	mov	[VBE_Int10_Off],dx
VOSCI_NotVBE:
ENDIF	;VGA8514

sci_exit:
	clc
	ret
EndProc VDD_OEM_Sys_Critical_Init

;******************************************************************************
;VDD_OEM_Device_Init
;
;DESCRIPTION:
;	Set up hardware for Windows environment, do any global register
;	state set up.
;
;ENTRY: EBX = VM_Handle of SYS VM
;	EDI -> VDD CB data of SYS VM
;
;EXIT:	If error, Carry is set
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_OEM_Device_Init

	clc
IFDEF	ATIVGA
; ATI VGA extended registers
	TestMem [edi.VDD_TFlags],fVT_ATIVGA
	jz	SHORT VIOTIOT_NotATIVGA
	push	edi
	mov	edi, OFFSET32 Vid_ATIVGA_IO_Table
	VMMCall Install_Mult_IO_Handlers	; Install the port traps
	pop	edi
VIOTIOT_NotATIVGA:
ENDIF
	ret
EndProc VDD_OEM_Device_Init


;******************************************************************************
;
;   VDD_OEM_Init_Msg_Mode_State
;
;   DESCRIPTION:    Some OEM's program the VGA to support multiple fonts
;		    during the normal INT 10h AX=0003 mode set.  For message
;		    mode the VDD only attempts to handle a single font, so
;		    this routine gives OEM's the opportunity to change the
;		    register state, before it is saved away as the message
;		    mode state, so that only a single font is assumed.
;
;   ENTRY:	    EDI -> VDD CB data of SYS VM
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_OEM_Init_Msg_Mode_State

%OUT does this need to be done for NEWCLVGA also?
IFDEF CLVGA
	TestMem [edi.VDD_TFlags], fVT_CLVGA
	jz	short imms_not_clvga
IFDEF DEBUG
	push	eax
	mov	al, [edi.VDD_Stt.S_ChMap]
	or	al, al
	jz	short @F
	Trace_Out 'VDD: forcing char map to 0 from #al for CLVGA'
@@:
	pop	eax
ENDIF
	mov	[edi.VDD_Stt.S_ChMap], 0
imms_not_clvga:
ENDIF
	ret

EndProc VDD_OEM_Init_Msg_Mode_State

VxD_ICode_ENDS

VxD_Code_SEG
;******************************************************************************
;VDD_OEM_System_Exit
;
;DESCRIPTION:
;	Set up hardware and BIOS for exiting Windows environment.
;
;ENTRY: EBX = VM_Handle of SYS VM
;	EDI -> VDD CB data of SYS VM
;
;EXIT:	None
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_OEM_System_Exit
	ret
EndProc VDD_OEM_System_Exit


;******************************************************************************
;VDD_OEM_Query_Access
;
;DESCRIPTION:
;	Determine if a page access in a VM without the focus will cause the
;	VM to be suspended because of inability to handle the page fault.
;
;ENTRY: EBX = VM_Handle of CRTC VM
;	EDI -> VDD control block data of CRTC VM
;	EDX = VM_Handle of VM for which we want to touch the video memory
;	Carry flag clear
;
;EXIT:	Set Carry flag if touching memory causes problems
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_OEM_Query_Access
	clc
	ret
EndProc VDD_OEM_Query_Access

;******************************************************************************
;VDD_OEM_Chk_CRTC
;
;DESCRIPTION:
;	This routine is called when a VM is running in a window to see if
;	the CRTC state has changed.  The normal CRTC registers will be
;	checked if this routine does not indicate any changes, so those
;	registers need not be checked here.  This routine should check
;	for differences in the VDD_Stt and VDD_SttCopy structures.
;
;ENTRY: EBX = VM_Handle of VM getting CRTC state (= 0 if VDD)
;	EDI -> VDD CB data
;
;EXIT:	Carry flag, if set indicates a changes was detected
;
;USES:	EAX, Flags
;
;==============================================================================
BeginProc VDD_OEM_Chk_CRTC, PUBLIC
IFNDEF	VGA8514	; VBE and 8514 detection are mutually exclusive from VDDDEF.INC
	TestMem [edi.VDD_TFlags],<fVT_VBESVGA>
	jz	short chkcrtc_not_vbe

	mov	ax,[edi.VDD_Stt.V_Extend.VBE_VidModeP1]
	cmp	ax,[edi.VDD_SttCopy.V_Extend.VBE_VidModeP1]
	je	short @F

	; different modes --> there's been a change!
	stc
	ret

@@:	; check for a difference in the CRTC structure if applicable
	dec	ax
	bt	ax,bVESA_UCRTC
	jnc	short chkcrtc_not_vbe	; no change if same mode

	push	esi
	push	edi
	push	ecx
	lea	esi,[edi.VDD_Stt.V_Extend.VBE_CRTC]
	lea	edi,[edi.VDD_SttCopy.V_Extend.VBE_CRTC]
	mov	ecx,(size VBE3_CRTCInfoBlock) SHR 2
.errnz	(size VBE3_CRTCInfoBlock) AND 3
	repe	cmpsd
	pop	ecx
	pop	edi
	pop	esi
	je	short chkcrtc_not_vbe	; no difference in CRTC Info Block

	; there's a change!
	stc
	ret

chkcrtc_not_vbe:
ENDIF

	clc
	ret
EndProc VDD_OEM_Chk_CRTC


;******************************************************************************
;VDD_OEM_Chk_Cursor
;
;DESCRIPTION:
;	This routine is called when a VM is running in a window to see if
;	the cursor position has changed.  The normal cursor address registers
;	in the CRTC will be checked if this routine does not indicate any
;	changes, so those registers need not be checked here.  This routine
;	should check for differences in the VDD_Stt and VDD_SttCopy structures.
;
;ENTRY: EBX = VM_Handle of VM getting CRTC state (= 0 if VDD)
;	EDI -> VDD CB data
;
;EXIT:	Zero flag, if clear indicates cursor movement.
;
;USES:	EAX, Flags
;
;==============================================================================
BeginProc VDD_OEM_Chk_Cursor,PUBLIC

	cmp	eax,eax
	ret
EndProc VDD_OEM_Chk_Cursor

;******************************************************************************
;VDD_OEM_Mode_Switch_Done
;
;DESCRIPTION:
;	This routine is called when a VM has just finished a mode switch.
;
;ENTRY: EBX = VM_Handle of VM getting CRTC state (= 0 if VDD)
;	EDI -> VDD CB data
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, ESI
;
;==============================================================================
BeginProc VDD_OEM_Mode_Switch_Done
IFNDEF	VGA8514	; VBE and 8514 detection are mutually exclusive from VDDDEF.INC
	TestMem [edi.VDD_TFlags],<fVT_VBESVGA>
	jz	msd_not_vbe

	Assert_Client_Ptr ebp
	mov	ax,[ebp.Client_AX]
	cmp	al,4Fh			;Q: attempted VBE modeset?
	je	short @F		;   Y: go check status
	mov	[edi.VDD_Stt.V_Extend.VBE_VidModeP1],0 ;N: indicate non-VBE mode
	ret

@@:	test	ah,ah			;Q: was modeset successful?
	jnz	msd_not_vbe		;   N: do nothing
	mov	ax,[ebp.Client_BX]	;   Y: get the mode

	inc	ax			; Store mode+1 so zero always means "invalid"
	mov	[edi.VDD_Stt.V_Extend.VBE_VidModeP1],ax
	dec	ax

	bt	ax,bVESA_UCRTC		;Q: custom CRTC info block?
	jnc	short @F		;   N: skip this bit

	push	edi
	push	eax
	mov	ax,(Client_ES SHL 8) + Client_DI
	VMMCall	Map_Flat
	mov	esi,eax
	lea	edi,[edi.VDD_Stt.V_Extend.VBE_CRTC]
	mov	ecx,(size VBE3_CRTCInfoBlock) SHR 2
.errnz	(size VBE3_CRTCInfoBlock) AND 3
	Begin_Touch_1st_Meg
	rep	movsd
	End_Touch_1st_Meg
	pop	eax
	pop	edi

@@:	; get the mode info struct
	VMMcall	Begin_Nest_V86_Exec
	Push_Client_State
	mov	[ebp.Client_AX],4F01h	; Get mode info
	mov	[ebp.Client_CX],ax	; mode number
	mov	ax,[VBE_Int10_Off]
	mov	[ebp.Client_DI],ax
	mov	ax,[VBE_Int10_Seg]
	mov	[ebp.Client_ES],ax
	mov	eax,10h
	VMMcall	Exec_Int

	cmp	[ebp.Client_AX],4Fh	;Q: Successful?
	je	short @F		;   Y: go ahead
	mov	ax,[ebp.Client_CX]
Debug_Out "Could not get mode info for #AX"

	; failsafe: unconditional access to all memory in range A0000h-C0000h
	mov	[edi.VDD_Stt.V_Extend.VBE_WinSize],80h
	mov	[edi.VDD_Stt.V_Extend.VBE_WinASeg],0A000h
	mov	[edi.VDD_Stt.V_Extend.VBE_LinearBuf],0A0000h
	; default mode attributes
	mov	[edi.VDD_Stt.V_Extend.VBE_ModeAttrs],fVModeAttr_HWSupport + fVModeAttr_Colour + fVModeAttr_Graphics + fVModeAttr_NonVGA + fVModeAttr_LinearSupport
	jmp	short msd_got_info

@@:	Begin_Touch_1st_Meg
	; copy window size and segment
	mov	esi,[VBE_Int10_Buf]
.errnz	VESAWinASeg-VESAWinSize-2
	mov	eax,dword ptr [esi.VESAWinSize]
.errnz	VBE_WinASeg-VBE_WinSize-2
	mov	dword ptr [edi.VDD_Stt.V_Extend.VBE_WinSize],eax
	; copy mode attributes
	mov	ax,[esi.VESAModeAttrs]
	mov	[edi.VDD_Stt.V_Extend.VBE_ModeAttrs],ax
	; copy linear buffer location
	mov	eax,[esi.VESALinearBuf]
	mov	[edi.VDD_Stt.V_Extend.VBE_LinearBuf],eax
	End_Touch_1st_Meg
msd_got_info:
	; done with the interrupt
	Pop_Client_State
	VMMcall	End_Nest_Exec

msd_not_vbe:
ENDIF
	ret
EndProc VDD_OEM_Mode_Switch_Done

IFDEF VGA8514
;******************************************************************************
;
;   VDD_OEM_VGA_Off
;
;   DESCRIPTION:    set bit 5 in sequencer register 1 to disable VGA screen
;
;   ENTRY:	    none
;
;   EXIT:	    none
;
;   USES:	    EAX, EDX, Flags
;
;==============================================================================
BeginProc VDD_OEM_VGA_Off

	mov	dx, pSeqIndx
	mov	al, 1
	out	dx, al
	IO_Delay
	inc	edx
	in	al, dx
	IO_Delay
	or	al, 100000b		; disable the VGA screen
	out	dx, al
	ret

EndProc VDD_OEM_VGA_Off

ELSE	;VBE and 8514 detection are mutually exclusive from VDDDEF.INC

;******************************************************************************
;
;   VDD_OEM_Set_Mode_Nested
;
;   DESCRIPTION:    use int10h to set the VBE/VGA mode, pre-setting modeset
;		    flag to ensure that we don't accidentally trap the call,
;		    or anything that happens inside it.
;
;   ENTRY:	    AX = desired mode
;		    CF = set to use VBE modeset, clear to use old BIOS
;		    EDI -> VDD CB data
;
;   EXIT:	    none
;
;   USES:	    EAX, ECX, EDX, Flags
;
;==============================================================================
BeginProc VDD_OEM_Set_Mode_Nested

	setc	cl			; save carry flag
	Push_Client_State
	push	ebp

	push	ebx
	VMMCall	Get_Cur_VM_Handle
	mov	ebp,[ebx.CB_Client_Pointer]
	SetVDDPtr edx
	pop	ebx

	test	cl,cl			; carry flag was set?
	jnz	short @F
	mov	[ebp.Client_AX], AX	; Set mode (AH=0)
	jmp	short smn_regs_setup

@@:	mov	[ebp.Client_AX], 4F02h	; Set mode
	mov	[ebp.Client_BX], AX

	bt	ax,bVESA_UCRTC
	jnc	smn_regs_setup

	; set CRTC Info Block pointer
	mov	ax,[VBE_Int10_Off]
	mov	[ebp.Client_DI],ax
	mov	ax,[VBE_Int10_Seg]
	mov	[ebp.Client_ES],ax

	; copy the info block into the buffer
	push	esi
	push	edi
	lea	esi,[edi.VDD_Stt.V_Extend.VBE_CRTC]
	mov	edi,[VBE_Int10_Buf]
	mov	ecx,(size VBE3_CRTCInfoBlock) SHR 2
.errnz	(size VBE3_CRTCInfoBlock) AND 3
	Begin_Touch_1st_Meg
	rep	movsd
	End_Touch_1st_Meg
	pop	edi
	pop	esi

smn_regs_setup:
	VMMcall Begin_Nest_V86_Exec 	; Get ready for software ints

	; set the modeset flag so that nothing inside the V86 exec
	; will get trapped back into the VDD's modeset routine and
	; muck around with any state that we're trying to preserve!
	SetFlag	[edi.VDD_Flags],fVDD_ModeSet
	mov	eax,10h
	VMMcall Exec_Int
	ClrFlag	[edi.VDD_Flags],fVDD_ModeSet

	VMMcall End_Nest_Exec		; All done with software ints
	Pop_Client_State

	ret

EndProc VDD_OEM_Set_Mode_Nested
ENDIF


;******************************************************************************
;VDD_OEM_CRTC_Enable
;
;DESCRIPTION:
;	This routine is called at the beginning of VDD_State_Restore_Regs to
;	do whatever is necessary to enable that code to access the CRTC as
;	if it were a standard VGA.  In some cases, it will do all of the
;	programming necessary for the adapter, in which case it returns carry
;	set.  Note that this is not called when the CRTC owner is not changing.
;
;ENTRY: EBX = VM_Handle of VM getting CRTC state (= 0 if VDD)
;	ESI -> VDD CB data of MemC VM
;	EDI -> VDD CB data of CRTC VM
;
;EXIT:	Carry flag = if set, indicates do not do any additional register restore
;
;USES:	EAX, ECX, Flags
;
;==============================================================================
BeginProc VDD_OEM_CRTC_Enable, High_Freq, PUBLIC

	push	edx
IFDEF	VGA8514
	VMMCall Test_Sys_VM_Handle		; Q: Sys VM getting CRTC?
	jne	SHORT VSRR_TurnOnVGA		;   N: Turn on VGA

;*******
; Give the display to the 8514
TurnOn8514:					;   Y: Turn on 8514
	mov	ax,7				;set misc I/O back to VGA
	mov	dx,4ae8h
	out	dx,ax
	pop	edx

; We never save/restore the 8514 state since it is never modified, except
; for the DAC, which is shared between the 8514 and the VGA circuits.
	call	VDD_VGA_Restore_DAC
	stc
	ret
        
;*******
; Give the display to the VGA
VSRR_TurnOnVGA:
	mov	ax,6				;set misc I/O back to VGA
	mov	dx,4ae8h
	out	dx,ax

ELSE	;VBE and 8514 detection are mutually exclusive from VDDDEF.INC

	TestMem [edi.VDD_TFlags],<fVT_VBESVGA>
	jz	short oce_not_vbe

	; if the VM we're switching to is in a NON-VBE MODE, then use
	; int 10h AH=00h to reset the mode and ensure the device is
	; in a VGA-compatible state
	int	3
	push	ebx
	; ensure we have a valid client pointer to use for modeset calls
	cmp	ebx,[Vid_Msg_Pseudo_VM]
	je	short @F
	test	ebx,ebx
	jnz	short oce_have_vm
@@:	; if the VDD or message mode is getting control of CRTC, then
	; the system VM is appropriate for this call
	VMMcall	Get_Sys_VM_Handle
oce_have_vm:
	SetVDDPtr ecx			; so we can set the modeset flag
	pop	ebx

	mov	ax,[edi.VDD_Stt.V_Extend.VBE_VidModeP1]
	dec	ax			; we stored mode+1
	cmp	ax,-1			; so now -1 means "invalid"
	jnz	short set_vbe_mode
	; determine the non-VBE mode from the saved state...
	call	VDD_State_Get_Mode
	test	ah,ah			;Q: valid mode?
	jnz	short @F		;   N: skip modeset
	; then call the BIOS to reset the VGA to that mode!
	push	edi
	mov	edi,ecx			; get the state pointer
	; CF is clear from "test" above so this will do non-VBE modeset
	call	VDD_OEM_Set_Mode_Nested
	pop	edi
@@:	jmp	short oce_not_vbe

set_vbe_mode:
	push	edi
	mov	edi,ecx

	; if VM knows how to restore their own state, then skip
	TestMem [edi.VDD_Flags], fVDD_CanRestore
	jnz	short @F

	; just use the BIOS to set the mode...
	stc	; use VBE modeset
	call	VDD_OEM_Set_Mode_Nested

@@:	; we're done, the state is fully restored
	pop	edi
	pop	edx
	stc
	ret

oce_not_vbe:
ENDIF	;VGA8514

IFDEF Handle_VGAEnable
%OUT REMOVE ACCESS TO VIDEO SUBSYSTEM??
;*******
; Enable access to video subsystem
	mov	dx,pVGAEna

IFDEF	TLVGA
;; Tseng labs has video subsystem enable on two diff ports depending
;;	on value in feature control.  Also has another bit to worry about.

	mov	ah,fVGAEna
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jz	SHORT VSRR_NotTLEnaRd
;;	mov	dx,pFeatRead
;;	in	al,dx
;;	and	al,3
;;	cmp	al,3
;;	mov	dx,pVGAEna
;;	jnz	SHORT VSRR_NotTLEnaRd
	or	ah,8				; Other bit that must be set
	mov	dx,46E8h			; Other VGA Enable port
VSRR_NotTLEnaRd:
	in	al,dx
	IO_Delay
	mov	[edi.VDD_Stt.V_VGAEna],al
	or	al,ah				; Make sure enable is true
ELSE	;not TLVGA
	in	al,dx
	IO_Delay
	mov	[edi.VDD_Stt.V_VGAEna],al
	or	al,fVGAEna			; Make sure enable is true
ENDIF	;TLVGA
	out	dx,al
	IO_Delay
ENDIF	;Handle_VGAEnable

IFDEF TLVGA
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jz	short VOCE_TL_2
	;turn on "key":
	mov	dx,03BFh
	mov	al,3
	out	dx,al
	IO_Delay
	;[color addrs may not be set so select correct mode reg port]
IFDEF VGAMONO
	mov	dx,pMiscRead
	in	al,dx
	IO_Delay
	mov	dx,03D8h
	test	al,1
	jnz	short VOCE_TL_1
	mov	dx,03B8h
VOCE_TL_1:
ELSE
	mov	dx,03D8h
ENDIF
	;DX=mode reg
	mov	al,0A0h
	out	dx,al
	IO_Delay
;
	TestMem [edi.VDD_TFlags],fVT_TLVGA
	jz	short VOCE_TL_2
	;if ET3000, avoid problem when reset [TLI extra] bit 1 while bit 0=0:
	; (TS 1 will be set from saved value after this proc rets)
	mov	dx,pSeqIndx
	mov	al,1
	out	dx,al
	IO_Delay
	inc	edx
	in	al,dx		;read TS 1
	IO_Delay
	dec	edx
	test	al,2		;don't do following unless TS 1 bit 1=1
	jz	short VOCE_TL_2
	push	eax
	mov	ax,0100h
	out	dx,ax		;reset seq (1->TS 0)
	IO_Delay
	pop	eax		;AL=TS 1 value
	or	al,1
	mov	ah,1
	xchg	al,ah
	out	dx,ax		;set TS 1 bit 0=1
	IO_Delay
	mov	ax,0300h
	out	dx,ax		;restart the seq so above takes effect 
VOCE_TL_2:
ENDIF	; TLVGA

	pop	edx
	clc
	ret
EndProc VDD_OEM_CRTC_Enable


;******************************************************************************
;VDD_OEM_Pre_Restore_CRTC
;
;DESCRIPTION:
;	This routine is called after the sequencer and miscellaneous register
;	have been programmed and VDD_State_Restore_Regs is about to program
;	the CRTC.  This code should do any CRTC programming necessary before
;	the standard CRTC programming occurs.  Also note that it can adjust
;	which CRTC registers are programmed by modifying the bit mask in EBP.
;	Note that this is not called when the CRTC owner is not changing.
;	The screen is off and in SYNC reset when this is called.
;
;ENTRY: EBX = VM_Handle of VM getting CRTC state (= 0 if VDD)
;	ESI -> VDD CB data of MemC VM
;	EDI -> VDD CB data of CRTC VM
;	DX = 3B4 or 3D4
;	EBP = -1 (mask for output of CRTC registers)
;
;EXIT:	EBP = mask for output of CRTC registers
;
;USES:	EAX, ECX, EBP, Flags
;
;==============================================================================
BeginProc VDD_OEM_Pre_Restore_CRTC, High_Freq, PUBLIC

IFDEF NEWCLVGA

	TestMem [edi.VDD_TFlags],<fVT_NEWCLVGA>
	jz	CL_RCRTC_Exit

	push	eax
	push	ebx
	push	edx
	push	esi
;
; now, save the state of the extended registers access bit
;
	mov	edx,pGrpIndx
        in      al,dx
        push    eax

	mov	al,0AH
	IO_Delay
	out	dx,al
	inc	edx
	IO_Delay
	in	al,dx
	dec	edx
        cmp     al,1                    ; Q: Ext. enabled?
	je	SHORT CLRCRTC_10	;  Y: Don't need to enable again
	mov	ax,0EC0Ah		; (value to enable it)
	IO_Delay
	out	dx,ax			;  N: enable it
CLRCRTC_10:

;
	mov	edx,pSeqIndx
	IO_Delay
        in      al,dx
        push    eax             ; save Seq index 

	mov	ax,0100h		; Do all extended stuff
	IO_Delay
	out	dx,ax			;  in sync. reset
;
	mov	edx,pGrpIndx

; start the restore...
;
        push    edi

;
	lea	esi,cs:NewCLExtRegTable.MIN_NewCLTable
	lea	edi,[edi.VDD_Stt.V_Extend.MIN_NewCLTable]
	mov	ecx,MAX_V_Extend+1-MIN_NewCLTable
;
; we will restore CRTC registers
;
	mov	bh,MIN_NewCLTable
;
        cld
CLReCRTC_20:
        lods    byte ptr cs:[esi]                ; flag from NewCLExtRegTable
        cmp     al,1            ; crtc=1, all others ignore
	jnz	short @F	;
        mov     al,bh           ; index to al
        mov     ah,[edi]        ; data to ah
        out     dx,ax
@@:
        inc     edi
        inc     bh
	loop	CLReCRTC_20
;
        pop     edi
        push    edi
; now do the 2nd half of the values
	lea	esi,cs:NewCLExtRegTable.MIN_C_Extension
	lea	edi,[edi.VDD_Stt.C_Extension.0]
	mov	ecx,MAX_C_Extension-MIN_C_Extension
;
; we will restore CRTC registers
;
	mov	bh,MIN_C_Extension
;
        cld
IIndCLReCRTC_20:
        lods    byte ptr cs:[esi]                ; flag from NewCLExtRegTable
        cmp     al,1            ; crtc=1, all others ignore
	jnz	short @F	;
        mov     al,bh           ; index to al
        mov     ah,[edi]        ; data to ah
        out     dx,ax
@@:
        inc     edi
        inc     bh
	loop	IIndCLReCRTC_20

        pop     edi
	mov	edx,pSeqIndx
        mov     ax,0300h
	IO_Delay
	out	dx,ax			; End sync. reset

        pop     eax             ; restore Seq. index
	IO_Delay
        out     dx,al
;                                       
; leave the extensions enabled
;
	mov	edx,pGrpIndx
        pop     eax
	IO_Delay
        out     dx,al           ; restore saved graphics index
;
	pop	esi
	pop	edx
	pop	ebx
	pop	eax
;
CL_RCRTC_Exit:

ENDIF ;NEWCLVGA

	push	edx

IFDEF TTVGA
;	Restore TVGA special register		- Henry Zeng
	TestMem [edi.VDD_TFlags], fVT_TVGA
	jz	short @f
	call	VDD_OEM_TVGA_Restore
@@:

ENDIF ;TTVGA

IFDEF IBMXGA
;
; see comment in vdddef.inc for a description about this hack
;
	TestMem [edi.VDD_TFlags], fVT_XGAbit
	jz	short @F
	call	VDD_OEM_Out_CRTC_Mode
	btr	ebp, C_Mode		; clear bit from EBP so that
	jmp	VOPRC_Exit		;   VDDState routine doesn't try to
					;   modify this register, since we've
					;   already done it.
@@:
ENDIF

IFDEF	PVGA
; More CRTC registers for WDC 			- C. Chiang -
	TestMem [edi.VDD_TFlags],fVT_PVGA
	jz	short VOPRC_PVGAexit
	push	esi
	push	ebp

        ;------------------
        ; unlock CRTC
        ;------------------

;;cc	mov	eax,C_P29-C_HTotal		;
;;cc	out	dx,al
;;cc	IO_Delay
;;cc	inc	edx
;;cc	mov	al, 085h		     	; Unlock access
;;cc	out	dx,al
;;cc	IO_Delay
;;cc	dec	edx
;;cc	; restore WDC 3x4.2A - 3x4.30

	lea	esi,[edi.VDD_Stt.C_HTotal.02Ah]		;pt. to CRTC 2A value
	mov	ah,C_P2a
	mov	ecx,C_P30-C_P2A+1
	mov	ebp,-1
	call	VDD_State_OutC_Ctrlr	     ;set the CRTC regs

	;-------------------------------------------------------------------
	;     Restore 3d4.3e in 1D chip - no lock/unlock process is needed
	;     Since you are not supposed to touch this register in 1F chip,
	;     we check if 1F and jump.	Save is in vddvga.asm
	;-------------------------------------------------------------------
	TestMem [edi.VDD_TFlags],fVT_PVGA1F
	jnz	short VOPRC_skip1F

	lea	esi,[edi.VDD_Stt.C_HTotal.03Eh]	;pt. to CRTC 3E value
	mov	ah,C_P3e
	mov	ecx,1
	mov	ebp,-1
	call	VDD_State_OutC_Ctrlr	     ;set the CRTC regs

VOPRC_skip1F:

	pop	ebp
	pop	esi

VOPRC_PVGAexit:
ENDIF	;PVGA

IFDEF TLVGA
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jz	short VOPRC_5
	;["key", unprotect are on, color addrs set]
	push	esi
	push	ebp
	mov	dx,pSeqIndx
	lea	esi,[edi.VDD_Stt.S_Rst.6]	;pt. to TS 6 value
	mov	ah,6
	mov	ecx,2
	mov	ebp,-1
	call	VDD_State_OutC_Ctrlr		;set TS 6,7
	;set CRTC 1B-25 if ET3000, CRTC 31,33-35 if ET4000:
	mov	dx,pCRTCIndxColr
	;set ET3000 params:
	lea	esi,[edi.VDD_Stt.C_HTotal.01Bh]	;pt. to CRTC 1B value
	mov	ah,01Bh
	mov	ecx,11
	mov	ebp,-1
	TestMem [edi.VDD_TFlags],fVT_TL_ET4000	    ;test ET4000
	jz	short VOPRC_2
	;set ET4000 params:
IFDEF SysVMin2ndBank
	TestMem [edi.VDD_TFlags], fVT_SysVMin2ndBank
	jz	short @F
	TestMem [Vid_Flags], fVid_DspDrvr_Init
	jz	short @F
	mov	[edi.VDD_Stt.C_HTotal.033h], 0
	VMMCall Test_Sys_VM_Handle
	jnz	short @F
	or	[edi.VDD_Stt.C_HTotal.033h], 1
@@:
ENDIF
	lea	esi,[edi.VDD_Stt.C_HTotal.031h]	;pt. to CRTC 31 value
	mov	ah,031h
	mov	ecx,5
	mov	ebp,0FDh		;skip 2nd one
VOPRC_2:
	call	VDD_State_OutC_Ctrlr	     ;set the CRTC regs
	pop	ebp
	pop	esi
VOPRC_5:
ENDIF	; TLVGA

IFDEF CLV7VGA
	TestMem [edi.VDD_TFlags],<fVT_V7VGA+fVT_CLVGA>
	jz	VOPRC_SkipCLV7
;
; Enable access to extended registers
;
	mov	dl,(pSeqIndx AND 0FFh)
	mov	al,6
	out	dx,al
	inc	edx
	in	al,dx
	dec	edx
        cmp     al,1                    ; Q: Ext. enabled?
	je	SHORT CLV7RCRTC_10	;  Y: Don't need to enable again
	mov	ax,[Vid_Enable_IV_Word] ; (value to enable it)
	out	dx,ax			;  N: enable it
CLV7RCRTC_10:

;
; First registers not in sync reset common to both CL and V7
;

	mov	ecx,0A5h		; Cursor attributes
	call	VDD_OEM_CLV7_Reg_Out

	TestMem [edi.VDD_TFlags],fVT_V7VGA  ; Q:Video 7?
	jz	SHORT VOPRC_NotV7	;    Y: Skip V7 specific regs

	mov	cl,0E0h 		; What is this reserved register?
	call	VDD_OEM_CLV7_Reg_Out
	mov	cl,0F6h 		; RAM bank select
	call	VDD_OEM_CLV7_Reg_Out
	mov	cl,0FCh 		; compatibility control register
	call	VDD_OEM_CLV7_Reg_Out
	mov	cl,0FFh 		; 16 bit interface control
	call	VDD_OEM_CLV7_Reg_Out

	mov	ax,0100h		; Do these extended regs
	cli
	out	dx,ax			;  in sync. reset

	mov	cl,0A4h 		; clock select
	call	VDD_OEM_CLV7_Reg_Out
	mov	cl,0F8h 		; extended clock control
	call	VDD_OEM_CLV7_Reg_Out
	mov	cl,0FDh 		; extended timing select
	call	VDD_OEM_CLV7_Reg_Out

        mov     ax,0300h
	out	dx,ax			; End sync. reset
	sti
VOPRC_CLV7_Restore:

;
; Restore access to extended registers
;
	cmp	[edi.VDD_Stt.S_Rst.6],1 ; Q: Ext. enabled?
	mov	ax,[Vid_Enable_IV_Word] ; (value to enable it)
	je	SHORT CLV7RCRTC_40	;  Y: enable it then
	mov	ax,[Vid_Disable_IV_Word];     disable value
CLV7RCRTC_40:
	out	dx,ax
	jmp	VOPRC_Exit
VOPRC_NotV7:

;
; Do Cirrus Logic CRTC pre restore
;
	mov	ax,0100h		; Do these extended regs
	cli				;  in sync. reset
	out	dx,ax

	mov	cl,0A4h 		; clock select
	call	VDD_OEM_CLV7_Reg_Out

        mov     ax,0300h
	out	dx,ax			; End sync. reset
	sti
	jmp	VOPRC_CLV7_Restore

VOPRC_SkipCLV7:
ENDIF	;CLV7VGA

IFDEF ATIVGA
	TestMem [edi.VDD_TFlags],fVT_ATiVGA
	jz	VOPRC_SkipATI

MAP256_I	equ	0b2h
FIX_UP		equ	040h
SYNC_I		equ	0b8h
L_3C2		equ	010h
L_ALL		equ	001h
DATA_I		equ	0bbh
HI_MIS_OUTPUT_R equ	03cch
ATI_REG 	equ	01ceh
DUMMY_COUNT	equ	0100h
SEL_8BIT_ROM	equ	008h		;3c2 bit 3

;;Debug_Out "ATI Pre restore CRTC"
	mov	dl,(pSeqIndx AND 0FFh)
	mov	ax,100h
	cli
	out	dx,ax			;sync reset
;
	mov	dx,ATiVGA_extended_reg
	mov	al,0b2h
	mov	ah,[edi.VDD_Stt.V_Extend.ATI_Regs+012h]  ;no meaning for V4 and above
	TestMem [edi.VDD_TFlags],fVT_ATiVGA3
	jz	SHORT ATiVGA_b2restore
	test	ah,40h
	jnz	SHORT ATiVGA_b2restore
	push	eax
	out	dx,al
	inc	edx
	in	al,dx		;
	dec	edx
	test	al,40h		;if yes, do nothing and exit
	jz	SHORT bit_off
	mov	al,SYNC_I	;make sure that the misc. output
	out	dx,al		;register is unlocked
	inc	edx
	in	al,dx
	mov	ch,al
	mov	ah,al
	and	ah,not ( L_3C2 or L_ALL)
	mov	al,SYNC_I
	dec	edx
	out	dx,ax
;
	mov	al,DATA_I	;get current 8 or 16-bit ROM
	out	dx,al		;status stored in the scratch registers
	inc	edx
	in	al,dx
	mov	ah,al
	mov	dx,HI_MIS_OUTPUT_R
	in	al,dx
	mov	cl,al		;save. the misc output register
	and	al,not SEL_8BIT_ROM
	shr	ah,1
	and	ah,SEL_8BIT_ROM
	or	al,ah
	or	al,4		;make sure 10xxx is not selected
	mov	dl,0c2h 	;because there might be no clock there
	out	dx,al		;set the 8 or 16-bit ROM
	mov	ax,MAP256_I or ( ( not FIX_UP ) * 100h)
;
	push	edx
	push	ecx
	mov	dx,ATI_REG
	cli
	out	dx,al		;program index
	mov	cl,al		;save the index
	inc	edx
	in	al,dx		;read data
	and	ah,al		;and
	mov	al,cl		;set index
	dec	edx
	out	dx,ax		;progam index and data
	sti
	mov	ecx,DUMMY_COUNT ;wait for some time to generate the
tog_lo1:			;the pulse width
	loop	tog_lo1
	pop	ecx
	pop	edx
	mov	al,cl
	out	dx,al		;restore the misc. output register
;
	push	ecx		;wait for some time to generate
	mov	ecx,DUMMY_COUNT ;the pulse width
tog_lo2:
	loop	tog_lo2
	pop	ecx
;
	mov	dx,ATI_REG
	mov	al,SYNC_I
	mov	ah,ch
	out	dx,ax		;restore the lock status
;
;
bit_off:
	pop	eax
ATiVGA_b2restore:
	out	dx,ax			;clock select 1 for Merlyn 2
;
	mov	al,0b1h
	mov	ah,[edi.VDD_Stt.V_Extend.ATI_Regs+11h]
	out	dx,ax
;
	mov	al,0b3h 			    ; Mask with 0BFh and merge?
	mov	ah,[edi.VDD_Stt.V_Extend.ATI_Regs+13h]
	out	dx,ax
;
	mov	al,0b6h 			    ; Mask with 05Ch and merge?
	mov	ah,[edi.VDD_Stt.V_Extend.ATI_Regs+16h]
	out	dx,ax
;
	mov	al,0b5h
	mov	ah,[edi.VDD_Stt.V_Extend.ATI_Regs+015h]   ;I/O ???, safer to restore in
	out	dx,ax			;in case of timing problem
;
	mov	al,0b8h
	mov	ah,[edi.VDD_Stt.V_Extend.ATI_Regs+018h]
	out	dx,ax			;clock divider 
;
	mov	al,0b9h
	mov	ah,[edi.VDD_Stt.V_Extend.ATI_Regs+019h]
	and	ah,07fh			;handle difference in Merlyn 2
	out	dx,ax			;for clock chip only
;
	mov	al,0beh
	mov	ah,[edi.VDD_Stt.V_Extend.ATI_Regs+01eh]   ;for Merlyn 4 and above
	out	dx,ax
;
	mov	dx,03cch
	in	al,dx	
	mov	dx,03c2h		;toggle clock select information into
	out	dx,al			;the clock chip, to make it effective 
;
	mov	dx,pSeqIndx
	mov	ax,300h
	out	dx,ax			;end sync reset
	sti
	jmp	SHORT VOPRC_Exit

VOPRC_SkipATI:
ENDIF	;ATIVGA

IFDEF CTVGA
%OUT what should DX be here?
Debug_Out what should DX be here?
	mov	al,17h
	out	dx,al
	inc	edx
	in	al,dx
	or	al,10h
	out	dx,al				; Enable extended read mode
	dec	edx
	mov	al,xC_CT400
	out	dx,al
	inc	edx
	in	al,dx
	or	al,80h				; Read CRTC cursor posn regs
	out	dx,al
	dec	edx
ENDIF	;CTVGA

VOPRC_Exit:
	pop	edx
	ret
EndProc VDD_OEM_Pre_Restore_CRTC


IFDEF TTVGA
;******************************************************************************
;VDD_OEM_TVGA_Save
;
;DESCRIPTION:
;	Save TVGA special registers		
;	- Trident, Henry Zeng
;
;ENTRY:
;
;EXIT:	none
;
;USES:	EAX, Flags
;
;==============================================================================
BeginProc VDD_OEM_TVGA_Save

	push	edx

	mov	edx,pSeqIndx

        ;set to 128K mode:
	mov	al, 0bh
	out	dx, al
        inc	edx
	out	dx, al
        dec	edx

        ;save 3c5.d0
	mov	al, 0dh
	out	dx, al
	inc	edx
	in	al, dx
	mov	[EDI.VDD_Stt.TVGA_3C5_D0],al
	dec	edx

        ;save 3c5.e0
	mov	al, 0eh
	out	dx, al
	inc	edx
	in	al, dx
	mov	[EDI.VDD_Stt.TVGA_3C5_E0],al
	dec	edx

        ;set to 64K mode:
	mov	al, 0bh
	out	dx, al
	inc	edx
	in	al, dx
	mov	[EDI.VDD_Stt.TVGA_3C5_B_v],al
	dec	edx

        ;save 3c5.d1
	mov	al, 0dh
	out	dx, al
	inc	edx 
	in	al, dx
	mov	[EDI.VDD_Stt.TVGA_3C5_D1],al
	dec	edx
        
        ;save 3c5.e1, ????
	mov	al, 0eh
	out	dx, al
	inc	edx
	in	al, dx
	mov	[EDI.VDD_Stt.TVGA_3C5_E1], al
	dec	edx

IF 0 ;TVGA8900C
	; save 3c5.c1
	mov	al, 0ch
	out	dx, al
	inc	edx
	in	al, dx
	mov	[edi.VDD_Stt.S_Rst][0ch], al
	dec	edx
ENDIF

	cmp	[EDI.VDD_Stt.TVGA_3C5_B], TVGA_3C5_B_RdMode
	jz	short @f
        ;change back to 3c5.b write mode
	mov	al, 0bh
	out	dx,al
        inc	edx
	out	dx,al
        dec	edx
@@:

	mov	edx,pSeqIndx
	mov	al,[edi.VDD_Stt.S_Indx]
	out	dx, al

if 0 ;HICOLOR
	; Add for HiColor
	mov	dx, 3C8h	; R 3C8
	in	al, dx
	mov	dx, 3C6h	; R 3C6 4 times
	in	al, dx
	in	al, dx
	in	al, dx
	in	al, dx

	in	al, dx
	mov	[edi.VDD_Stt.TVGA_3C6], al
endif

	pop	edx
	ret

EndProc VDD_OEM_TVGA_Save


;******************************************************************************
;VDD_OEM_TVGA_Restore
;
;DESCRIPTION:
;	Restore TVGA special registers		
;	- Trident, Henry Zeng
;
;ENTRY:
;
;EXIT:	none
;
;USES:	EAX, Flags
;
;==============================================================================
BeginProc VDD_OEM_TVGA_Restore

        push    edx

	mov	edx, pSeqIndx
        in      al, dx
	push	eax		; save index

        ;set to 128K mode:
	mov	ax, 0bh
	out	dx, ax

        ;restore 3c5.d0
	mov	al, 0dh
	mov	ah, [EDI.VDD_Stt.TVGA_3C5_D0]
	out	dx, ax

        ;restore 3c5.e0
	mov	al, 0eh
	mov	ah, [EDI.VDD_Stt.TVGA_3C5_E0]
	out	dx, ax

        ;set to 64K mode:
	mov	al, 0bh
	out	dx, al
	inc	edx
	in	al, dx
	dec	edx

        ;restore 3c5.d1
	mov	al, 0dh
	mov	ah, [EDI.VDD_Stt.TVGA_3C5_D1]
	out	dx, ax
        
IF 0; TVGA8900C
        ;restore 3c5.c1
	mov	al, 0ch
	out	dx, al
        inc	edx
	in	al, dx
	dec	edx
	cmp	al, [edi.VDD_Stt.S_Rst][0ch]
	jz	short @f
	mov	ax, 0800Eh	; enable write 3C5.C
	out	dx, ax
	mov	al, 0Ch
	mov	ah, [edi.VDD_Stt.S_Rst][0ch]
	out	dx, ax
@@:
ENDIF

        ;restore 3c5.e1
	mov	al, 0eh
	mov	ah, [EDI.VDD_Stt.TVGA_3C5_E1]
	and	ah, 0F0h	; ??? have to do this for 1024x768 16c
				; but will lost BANK infor.
	xor	ah, 2
	out	dx, ax

        ;now is in 64K mode. check if we need to change
	cmp	[EDI.VDD_Stt.TVGA_3C5_B], TVGA_3C5_B_RdMode
	jz	short @f
        ;change back to 3c5.b write mode
	mov	ax, 0bh
	out	dx, ax
@@:

	pop	eax		; restore index
        out     dx, al

if 0 ;HICOLOR
;	Add for HiColor
	cmp	byte ptr [EDI.VDD_Stt.TVGA_3C6_ReadCnt], 4
	jb	@f
	mov	dx, 3C8h
	in	al, dx
	mov	dx, 3C6h
	in	al, dx
	in	al, dx
	in	al, dx
	in	al, dx
	mov	al, [EDI.VDD_Stt.TVGA_3C6]
	out	dx, al
@@:
endif

        pop     edx
        ret

EndProc VDD_OEM_TVGA_Restore

ENDIF ;TTVGA

IFDEF CLV7VGA
;******************************************************************************
;VDD_OEM_CLV7_Reg_Out
;
;DESCRIPTION:
;	This routine merges MemC and CRTC state and outputs value
;
;ENTRY: ECX = port to output
;	ESI -> VDD data of VM owning MemC state
;	EDI -> VDD data of VM getting CRTC state
;
;EXIT:	none
;
;USES:	EAX, Flags
;
;==============================================================================
BeginProc VDD_OEM_CLV7_Reg_Out
	mov	al,[mVid_CLV7_MemC][ecx-80h]
	mov	ah,[esi.VDD_Stt.V_Extend][ecx-080h]
	and	ah,al
	not	al
	and	al,[edi.VDD_Stt.V_Extend][ecx-080h]
	or	ah,al
	mov	al,cl
IFDEF Ext_VGA
	cmp	al,0FFh
	jnz	SHORT VOCLV7RO_Out
	int 1
%OUT this probably isn't correct for all CLV7 cards!!!!!!!!
	or	ah,10000b		; force 256K Bank Enable
VOCLV7RO_Out:
ENDIF
	out	dx,ax
	ret
EndProc VDD_OEM_CLV7_Reg_Out
ENDIF


;******************************************************************************
;VDD_OEM_Post_Restore_CRTC
;
;DESCRIPTION:
;	This routine is called at the end of the CRTC state programming.
;	This code should do any additional CRTC programming necessary.
;	Note that this is not called when the CRTC owner is not changing.
;
;ENTRY: EBX = VM_Handle of VM getting CRTC state (= 0 if VDD)
;	ESI -> VDD CB data of MemC VM
;	EDI -> VDD CB data of CRTC VM
;	DX = 3B4 or 3D4
;
;EXIT:	none
;
;USES:	EAX, EBP, Flags
;
;==============================================================================
BeginProc VDD_OEM_Post_Restore_CRTC, High_Freq, PUBLIC

IFDEF CLVGA

	TestMem [edi.VDD_TFlags],fVT_CLVGA
	jz	PR_CRTC_SkipCL
        push    edx
        push    esi
        push    edi
        push    ebp
	mov	ebp,edx

	mov	edx,pSeqIndx
	mov	al,6				; get index of ext enable
	out	dx,al  				; select ext enable
	IO_Delay
	inc	edx				; get data port
	in	al,dx				; get ext enable state
	test	al,1				; are we enabled
	mov	ah,Vid_Enable_Ext_Val           ; get enable value
	jnz	short CL_RestCtlr_20		; yes - jump
	mov	al,ah                           ; get enable value
	out	dx,al				; enable extensions
	mov	ah,Vid_Disable_Ext_Val		; get value to disable
CL_RestCtlr_20:
	lea	esi,[edi.VDD_Stt.V_Extend]	; get address of ext regs

	mov	al,6 				; get index of enable reg
	push	eax				; save for future restore
	dec	edx				; set for index
	xor	al,al				; select reset reg
	mov	ah,1				; set to sync reset
        cli
	out	dx,ax				; reset the sequencer

	mov	al,CL_ER_START+CL_ER_WRC
	out	dx, al
	inc	edx
	in	al, dx
	and	al, 01000000b
	TestMem [edi.VDD_TFlags],fVT_CLVGA_RevC ; Q: RevC. chipset?
	jnz	short @F			; Y:
	xor	al, al
@@:
	out	dx, al
	dec	edx

	mov	al,CL_ER_START+CL_ER_CLK	; clock reg
	mov	ah,[esi].CL_ER_Clk
	out	dx,ax

	mov	al,CL_ER_START+CL_ER_BWC  	; band width control reg
	mov	ah,[esi].CL_ER_BWC
	out	dx,ax
	
	mov	al,CL_ER_START+CL_ER_TC		; timing control reg
	mov	ah,[esi].CL_ER_TC
	out	dx,ax

	mov	al,CL_ER_START+CL_ER_LCDCNTL1	; lcd extension reg 
	mov	ah,[esi].CL_ER_LCDCNTL1
	out	dx,ax

	mov	al,CL_ER_START+CL_ER_LCDCNTL2	; LCD control register 2
	mov	ah,[esi].CL_ER_LCDCNTL2
	out	dx,ax
	
	xor	al,al
	mov	ah,[edi.VDD_Stt.S_Rst]		; undo sequencer reset
	out	dx,ax

	sti
	push	ebp				; Save CRTC base

	lea	esi,[esi].CL_ER_ROMC
	mov	ecx,CL_ER_VRTCStrt-CL_ER_ROMC 	; Restore up to, not including,
	mov	ah,CL_ER_START+CL_ER_ROMC	;  vertical retrace start
	mov     ebp,-1                          ; set output mask
	call	VDD_State_OutC_Ctrlr

	add	esi,CL_ER_LPEN-CL_ER_VRTCStrt 	; Restore LPEN thru   
	mov	ecx,CL_ER_LATCH0-CL_ER_LPEN	;   Pointer position
	mov	ah,CL_ER_START+CL_ER_LPEN				      
	mov     ebp,-1                          ; set output mask
	call	VDD_State_OutC_Ctrlr

	add	esi,CL_ER_CURS-CL_ER_LATCH0	; Restore up to STATE
	mov	ecx,CL_ER_STATE-CL_ER_CURS				      
	mov	ah,CL_ER_START+CL_ER_CURS				      
	mov     ebp,-1                          ; set output mask
	TestMem [edi.VDD_TFlags],fVT_CLVGA_RevC ; Q: RevC. chipset?
	jnz	short NoMask			; Y:
	and	ebp, not 0Ch			; N: mask write of ERA7-ERA8
NoMask:
	call	VDD_State_OutC_Ctrlr

	add	esi,CL_ER_SCRATCh0-CL_ER_STATE	  ; Restore SCRATCH regs
	mov	ecx,CL_ER_CPURAR-CL_ER_SCRATCH0	; scratch regs
	mov	ah,CL_ER_START+CL_ER_SCRATCH0 			     
	mov     ebp,-1                          ; set output mask
	call	VDD_State_OutC_Ctrlr
	
	mov	al,0D0H
	out     dx,al				
	inc	edx
	in      al,dx
	dec	edx
	cmp	al,[edi.VDD_Stt.V_Extend.CL_ER_VRTCStrt] ; Q: Register 90 = D0?
	jnz	SHORT CL_RestCtlr_25		 ;  N:

	mov	al,0D1H 			 ;  Y:
	out     dx,al				
	inc	edx
	in      al,dx
	dec	edx
	cmp	al,[edi.VDD_Stt.V_Extend.CL_ER_VRTCEnd] ; compare register 91 to D1
	jz    	SHORT CL_RestCtlr_30			; jump if equal

CL_RestCtlr_25:
						;
	mov	ecx,CL_ER_Resvd-CL_ER_CPURAR	; and other extended regs
	mov	ah,CL_ER_START+CL_ER_CPURAR 			     
	mov     ebp,-1                          ; set output mask
	call	VDD_State_OutC_Ctrlr

CL_RestCtlr_30:
	mov	edx,pSeqIndx
	mov	al,0
	mov	ah,1
	out	dx,ax				; Reset the sequencer

	mov	ah,[edi.VDD_Stt.S_MMode]	; memory mode
	mov     al,4
	out     dx,ax

	mov	ah,[edi.VDD_Stt.S_ClMode]	; clocking mode
	mov     al,1
	out     dx,ax

	xor	al,al
	mov	ah,[edi.VDD_Stt.S_Rst]
	out	dx,ax				; Take the reset off sequencer

	lea	esi,[edi.VDD_Stt.V_Extend]	; get address of ext regs

	mov     al,CL_ER_START+CL_ER_LCDCNTLIII	; get shadow register port
	mov     ah,[esi].CL_ER_LCDCNTLIII  	; get old value
	and     ah,0FBH				; turn off shadow bit
	out	dx,ax  	                	; turn off the shadow

        mov     al,CL_ER_START+CL_ER_VRTCEnd	; get crt reg 0-7 protect register port
	mov     ah,[esi].CL_ER_VRTCEnd     	; get old value
	and     ah,07FH				; turn off protection bit
	out	dx,ax                   	; turn off the shadow

	pop	edx				; DX = CRTC base
	in      al,dx
	push    eax                             ; save the index
	push	edx				; save for later

	mov     al,6				; st for register 6
	mov     ah,[esi].CL_ShadowCRT6     	; get saved value
	out     dx,ax                   	; restore shadowed value
	
	mov     al,7				; st for register 6
	mov     ah,[esi].CL_ShadowCRT7     	; get saved value
	out     dx,ax                   	; restore shadowed value

	mov	dx,pSeqIndx
        mov     al,CL_ER_START+CL_ER_LCDCNTLIII	; get shadow register port
	mov     ah,[esi].CL_ER_LCDCNTLIII  	; get old value
	out	dx,ax                   	; turn off the shadow

	pop	edx				; get crt reg port
	mov	al,6                    	; set to restore fake values
	mov     ah,[edi.VDD_Stt.CRTC.C_VTotal]  ; get saved value
	out     dx,ax	                  	; restore the fake value

	mov	al,7                    	; set to restore fake values
	mov     ah,[edi.VDD_Stt.CRTC.C_Ovflw] 	; get saved value
	out     dx,ax	                  	; restore the fake value

	push	edx				; save again for later

	mov	dx,pSeqIndx
	mov     al,CL_ER_START+CL_ER_VRTCEnd	; get crt protection register port
	mov     ah,[esi].CL_ER_VRTCEnd  	; get old value
	out	dx,ax                   	; restore protection
	mov     al,[edi.VDD_Stt.V_Feat]         ; get feature control value
	mov     edx,pFeatColr
	out     dx,al                           ; set feature control

; Reprogram the 4 CRTC registers that 6845 writes thru

	pop	edx				; get the 6845 base address

	mov	ah,C_AddrH-C_HTotal
	mov	ecx,C_CAddrL-C_AddrH+1
	mov     ebp,-1
	lea	esi,[edi.VDD_Stt.CRTC.C_AddrH]
	call	VDD_State_OutC_Ctrlr

	pop     eax                             ; get the old index
	out     dx,al                           ; restore the index

; Restore current Cirrus extensions on/off state
	mov	dx,pSeqIndx
	pop	eax
	out	dx,ax
	IO_Delay

        pop     ebp
        pop     edi
        pop     esi
        pop     edx


PR_CRTC_SkipCL:
ENDIF
	ret
EndProc VDD_OEM_Post_Restore_CRTC, PUBLIC

;******************************************************************************
;
;   VDD_OEM_In_CRTC
;
;   DESCRIPTION: Handles OEM variations on reading a CRT controller register.
;	The VM may be owner of one or both of the MemC and CRTC state.
;	Note that each OEM specific code must restore the registers to the
;	initial state if that code does not handle the I/O.
;
;   ENTRY:  EBX = VM handle
;	    ECX = CRTC index register
;	    DX = 3B4 or 3D4
;	    Carry flag clear, Zero flag set
;
;   EXIT:   If Zero flag clear, AL = input byte, else do normal processing
;
;   USES:   EAX, Flags
;
;==============================================================================
BeginProc VDD_OEM_In_CRTC

IFDEF CLV7VGA
	TestMem [edi.VDD_TFlags],<fVT_CLVGA+fVT_V7VGA> ; is it a cirrus or V7?
	jz	SHORT inCRTC_notCLV7		    ; no - jump
	cmp	cl, 1Fh 			    ;Q: id register?
	jne	short @F			    ;	N:
	mov	al, [edi.VDD_Stt.CRTC+0Ch]	    ;	Y: return reg 0Ch
	xor	al, [Vid_Enable_Ext_Val]	    ;	    XOR'ed with enable
	jmp	SHORT inCRTC_have_value 	    ;	    value
@@:
	TestMem [edi.VDD_TFlags],fVT_CLVGA	    ; is it a cirrus?
	jz	short inCRTC_notCLV7		    ; no
	test	[edi.VDD_Stt.V_Extend.CL_ER_LCDCNTLIII], 04H ; shadowing ?
	jnz	SHORT inCRTC_notCLV7		    ; yes - jump

	cmp	cl,6				    ; is it register 6 ?
	jne	SHORT @F			    ; no - jump

	mov	al,[edi.VDD_Stt.V_Extend.CL_ShadowCRT6] ; get shadow reg 6 value
	jmp	SHORT inCRTC_have_value 	    ; go return value

@@:
	cmp	cl,7				    ; is it register 6 ?
	jne	SHORT inCRTC_notCLV7		    ; no - get unshadowed value
	mov	al,[edi.VDD_Stt.V_Extend.CL_ShadowCRT7] ; get shadow reg 7 value
inCRTC_have_value:
	or	cl, 1				    ; clear Z flag
	jmp	SHORT inCRTC_exit		    ; yes - go return value

inCRTC_notCLV7:
	cmp	al, al				    ; return with Z flag set
ENDIF
inCRTC_exit:
	ret

EndProc VDD_OEM_In_CRTC



;******************************************************************************
;VDD_OEM_Out_CRTC
;
;DESCRIPTION: Handles OEM variations on saving output to CRT controller.
;	The VM may be owner of one or both of the MemC and CRTC state.
;	Note that each OEM specific code must restore the registers to the
;	initial state if that code does not handle the I/O.
;
;ENTRY: EBX = VM handle
;	AL = BYTE to output to port.
;	ECX = CRTC index register
;	DX = 3B4 or 3D4
;	Carry flag clear, Zero flag set
;
;EXIT:	AL = BYTE to output to port
;	If Carry flag set, do output
;	If Zero flag clear skip normal processing, just exit
;
;USES:	Flags, AL, ESI
;
;==============================================================================
BeginProc VDD_OEM_Out_CRTC, High_Freq, PUBLIC

IFDEF CLVGA
	TestMem [edi.VDD_TFlags],fVT_CLVGA
        jz      SHORT VO_Out_CRTC_notCLVGA

	cmp	cl,10h			; is it vertical retrace start
	jnz     SHORT CRT_CL_Special_10 ; no - go try other regs

	mov	[edi.VDD_Stt.V_Extend.CL_ER_VRTCStrt],al ; save extended reg copy
        jmp      SHORT CRT_CL_Special_End     ; done

CRT_CL_Special_10:
	cmp	cl,11h			; is it vertical retrace end
	jnz     SHORT CRT_CL_Special_20 ; no - go try other regs

	mov	[edi.VDD_Stt.V_Extend.CL_ER_VRTCEnd],al ; save extended reg copy
        jmp      SHORT CRT_CL_Special_End     ; done

CRT_CL_Special_20:
	cmp	cl,06h			        ; is it vertical total
	jnz     SHORT CRT_CL_Special_30         ; no - go try other regs

	test	[edi.VDD_Stt.V_Extend.CL_ER_LCDCNTLIII], 04H ; shadowing ?
	jnz     SHORT CRT_CL_Special_End

	mov	[edi.VDD_Stt.V_Extend.CL_ShadowCRT6],al ; save extended reg copy
	jmp	SHORT CRT_CL_Special_End     ; done

CRT_CL_Special_30:
	cmp	cl,07h			; is it overflow ?
	jnz     SHORT CRT_CL_Special_End      ; no - go try other regs

	test	[edi.VDD_Stt.V_Extend.CL_ER_LCDCNTLIII], 04H ; shadowing ?
	jnz     SHORT CRT_CL_Special_End

	mov	[edi.VDD_Stt.V_Extend.CL_ShadowCRT7],al ; save extended reg copy
CRT_CL_Special_End:
	cmp	edx, edx		    ; let vddtio handle as normal
        jmp     SHORT VO_Out_CRTC_End
;
VO_Out_CRTC_notCLVGA:
ENDIF ; CLVGA

IFDEF   CTVGA
%OUT Does this belong here?  Currently not called
;*******
; C&T 441 specific handling
	pushfd
        cmp     cl,xC_CT400
	jne	SHORT VO_OC_CT01
	mov	cl,25				    ; xC_CT400 - index is 25
	popfd
	ret					    ; ZF=1, CF=0; normal
VO_OC_CT01:
	cmp	cl, 0FEh
	jne	SHORT VO_OC_CT02
	mov	cl,26
	popfd
	ret					    ; ZF=1, CF=0; normal
VO_OC_CT02:
	popfd
ENDIF	;CTVGA

IFDEF SysVMin2ndBank
IFDEF TLVGA
	pushfd
	cmp	cl, 33h
	jne	short @F
	TestMem [edi.VDD_TFlags], fVT_TL_ET4000
	jz	short @F
	TestMem [Vid_Flags], fVid_DspDrvr_Init
	jz	short @F
	TestMem [edi.VDD_TFlags], fVT_SysVMin2ndBank
	jz	short @F
	VMMCall Test_Sys_VM_Handle
	jnz	short @F
	or	al, 1
@@:
	popfd
ENDIF
ENDIF
VO_Out_CRTC_End:
	ret

EndProc VDD_OEM_Out_CRTC

;******************************************************************************
;VDD_OEM_Restore_Seq
;
;DESCRIPTION:
;	This routine does any setup necessary for Seq state programming.
;
;ENTRY: EBX = VM_Handle of VM getting CRTC state (= 0 if VDD)
;	ESI -> VDD CB data of MemC VM
;	EDI -> VDD CB data of CRTC VM
;	DX = 3B4 or 3D4
;
;EXIT:	none
;
;USES:	EAX, Flags
;
;==============================================================================
BeginProc  VDD_OEM_Restore_Seq, High_Freq, PUBLIC

IFDEF	PVGA

        ; unlock Paradise Sequencer extended register access Lock/Unlock

	TestMem [edi.VDD_TFlags],fVT_PVGA	; Q: Paradise VGA?
	jz	VRC_PVGA_EXIT			; N: exit
        mov     dx, 3c4h
	mov	al, S_PVGA20-S_Rst		;   Y: restore paradise regs
	out	dx, al
	IO_Delay
	inc	edx
	mov	al, 48h				; Unlock access
	out	dx, al
	IO_Delay
	dec	edx

VRC_PVGA21:
        mov     dx, 3c4h

	mov	al, S_PVGA21-S_Rst		;
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[edi.VDD_Stt.S_PVGA21]      	;
	out	dx,al
	IO_Delay
	dec	edx

        ;---------------------------------------------------------------------
        ; check # of sequencer registers?
        ; if = 7 => 1B or 1F chip, do not restore sequencer 10, 11 and 12
        ;           since they wrap around and over write register 0, 1 and 2.
        ;           Thus, only bit 0-2 are used in 1B and 1F.
        ; if != 7 => restore all 10, 11, 12. This is 1C board
        ;           Thus,  bit 0-6 are used in 1C and 1CB.
        ;---------------------------------------------------------------------

        in      al, dx                  ; save sequencer index
        IO_Delay
        push    eax
        mov     al, 0ffh
        out     dx, al
        IO_Delay
        in      al, dx
        IO_Delay
        cmp     al, 7
        pop     eax
        out     dx, al                  ; restore sequencer index
        IO_Delay
        je      SHORT board1B1F


        ;---------------------------------------------------------------
        ; register index - 8 and 9 are for Paradise 1CB, 1D board               
        ;---------------------------------------------------------------
VRC_PVGA_1CB1:
	mov	al, S_PVGA_1CB1-S_Rst
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[edi.VDD_Stt.S_PVGA_1CB1] 
	out	dx,al
	IO_Delay
	dec	edx

VRC_PVGA_1CB2:
	mov	al, S_PVGA_1CB2-S_Rst
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[edi.VDD_Stt.S_PVGA_1CB2] 
	out	dx,al
	IO_Delay
	dec	edx

        ;---------------------------------------------------------------
        ; register index - 10, 11 and 12 are for Paradise 1C board               
        ;---------------------------------------------------------------
VRC_PVGA22:

	mov	al, S_PVGA22-S_Rst 
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[edi.VDD_Stt.S_PVGA22]  
	out	dx,al
	IO_Delay
	dec	edx

VRC_PVGA23:

	mov	al, S_PVGA23-S_Rst 
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[edi.VDD_Stt.S_PVGA23]  
	out	dx,al
	IO_Delay
	dec	edx

VRC_PVGA24:

	mov	al, S_PVGA24-S_Rst 
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[edi.VDD_Stt.S_PVGA24]  
	out	dx,al
	IO_Delay
	dec	edx


        ;---------------------------------------------------------------
        ; register index - 13 and 14 are for Paradise 1D board               
        ;---------------------------------------------------------------
VRC_PVGA_1Dpr33:

	mov	al, S_PVGA_1Dpr33-S_Rst 
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[edi.VDD_Stt.S_PVGA_1Dpr33]  
	out	dx,al
	IO_Delay
	dec	edx

VRC_PVGA_1Dpr34:

	mov	al, S_PVGA_1Dpr34-S_Rst 
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[edi.VDD_Stt.S_PVGA_1Dpr34]  
	out	dx,al
	IO_Delay
	dec	edx

board1B1F:
VRC_PVGA_EXIT:
ENDIF	;PVGA

	ret
EndProc  VDD_OEM_Restore_Seq

;******************************************************************************
;VDD_OEM_Pre_Restore_MemC
;
;DESCRIPTION:
;	This routine does any setup necessary for MemC state programming.
;
;ENTRY: EBX = VM_Handle of VM getting CRTC state (= 0 if VDD)
;	ESI -> VDD CB data of MemC VM
;	EDI -> VDD CB data of CRTC VM
;	DX = 3B4 or 3D4
;
;EXIT:	none
;
;USES:	EAX, Flags
;
;==============================================================================
BeginProc  VDD_OEM_Pre_Restore_MemC, High_Freq, PUBLIC

	ret
EndProc  VDD_OEM_Pre_Restore_MemC


;******************************************************************************
;VDD_OEM_Post_Restore_MemC
;
;DESCRIPTION:
;	This routine does any additional MemC state programming necessary.
;
;ENTRY: EBX = VM_Handle of VM getting CRTC state (= 0 if VDD)
;	ESI -> VDD CB data of MemC VM
;	EDI -> VDD CB data of CRTC VM
;	DX = 3B4 or 3D4
;
;EXIT:	none
;
;USES:	EAX, ECX, Flags
;
;==============================================================================
BeginProc  VDD_OEM_Post_Restore_MemC, High_Freq, PUBLIC

	push	edx

;
; see comment in vdddef.inc for a description about this hack
;
IFDEF IBMXGA
	TestMem [edi.VDD_TFlags], fVT_XGAbit
	jz	short @F
	call	VDD_OEM_Out_CRTC_Mode
@@:
ENDIF

IFDEF TLVGA
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jz	short VOPRM_5
	;restore Segment Select reg:
	mov	dx,03CDh
	mov	al,[esi.VDD_Stt.V_Extend.TLI_SegSel]
IFDEF SysVMin2ndBank
	TestMem [edi.VDD_TFlags], fVT_SysVMin2ndBank
	jz	short @F
	xor	al, al				    ; assume non-sys VM
	TestMem [Vid_Flags], fVid_DspDrvr_Init
	jz	short @F
	push	ebx
	mov	ebx, [Vid_MemC_VM]
	VMMCall Test_Sys_VM_Handle
	pop	ebx
	jnz	short @F
	mov	al, 11h
@@:
ENDIF
	out	dx,al
;;	  queue_out 'memc segment = #al'
	IO_Delay
;restore "key":
;[color addrs may not be set so select correct mode reg port]
IFDEF VGAMONO
	mov	dx,pMiscRead
	in	al,dx
	IO_Delay
	mov	dx,03D8h
	test	al,1
	jnz	short VOPRM_3
	mov	dx,03B8h
VOPRM_3:
ELSE
	mov	dx,03D8h
ENDIF
;DX=mode reg
	mov	cl, 5	 ;if ET4000, restore 3BF bit 1 from bit 6 of AL:
	mov	al,[edi.VDD_Stt.V_Extend.TLI_Key]   ;[assume key in CRTC state]
	TestMem [edi.VDD_TFlags],fVT_TL_ET4000
	jnz	short VOPRM_4			    ; jump, if ET4000
	mov	dl, 0CAh
	mov	cl, 4	 ;if ET3000, restore 3BF bit 1 from bit 5 of AL:
VOPRM_4:
	out	dx,al
	IO_Delay
	shr	al, cl
	and	al, 3
	or	al,1		; set bit 0???
	mov	dx,03BFh
	out	dx,al
VOPRM_5:
ENDIF	;TLVGA

IFDEF	PVGA
;*******
; Restore Paradise Graphic controller extended registers
;
	TestMem [edi.VDD_TFlags],fVT_PVGA	    ; Q: Paradise VGA?
	jz	VRC_PVGA9 		;   N: skip Paradise restore

;!!  Paradise 1F chip Set 3CE.0C = 0
;!!  before restore 3c2 register
;   This gives you timing re-syn problems on windowed DOS in standard modes
;   under Windows 3.1
;	TestMem [edi.VDD_TFlags],fVT_PVGA1F	; Q: Paradise VGA 1F chip ?
;	jz	SHORT @@notPVGA1F
;	push	edx
;	mov	dx, 3ceh
;	mov	al, 0ch
;	out	dx, al
;	IO_Delay
;	inc	edx
;	mov	al, 0
;	out	dx, al
;	IO_Delay
;	pop	edx
;@@notPVGA1F:

	mov	al,G_PVGA5-G_SetRst		;   Y: restore paradise regs
	mov	dl,(pGrpIndx AND 0FFh)
	out	dx,al
	IO_Delay
	inc	edx
	mov	al, 5				; Unlock access
	out	dx,al
	IO_Delay
	dec	edx
VRC_PVGA1:

	mov	al,G_PVGA0A-G_SetRst
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.VDD_Stt.G_PVGA0A]	; Restore Addr0A
	out	dx,al
	IO_Delay
	dec	edx
VRC_PVGA2:

	mov	al,G_PVGA0B-G_SetRst
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.VDD_Stt.G_PVGA0B]	; Restore Addr0B
	out	dx,al
	IO_Delay
	dec	edx

VRC_PVGA3:
	mov	al,G_PVGA1-G_SetRst
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.VDD_Stt.G_PVGA1]	; Restore memory configuration
	out	dx,al
	IO_Delay
	dec	edx


;----------------------------------------------------------------
; restore PR2 and PR3 also
; see problem in 1024x768 mode when switching back and forth
; between Windows screen and DOS full screen.
; 3CE.0C should be 0 in 1024x768 and should be 2 in DOS mode 3
;----------------------------------------------------------------
;
;      check if LCD or CRT side (Paradise 1F chip only)
;
;  1. Unlock 3?5.34 with value of A6h
;  2. Read 3?5.32
;     if 3?5.32 bit #5 = 1 ---> CRT side
;             set 3?5.34 to A6h     
;             set 3CF.0C bit #1 to 1             
;
;     if 3?5.32 bit #4 = 1 ---> LCD side
;             set 3?5.34 to 0     
;             set 3CF.œ0C bit #1 to 0             
;


	TestMem [edi.VDD_TFlags],fVT_PVGA1F	; Q: Paradise VGA 1F chip ?
	jz	SHORT notPVGA1F


        push    edx


        mov     edx,3cch
        in      al,dx
        IO_Delay
        test    al,1
        mov     dl,0d4h
        jnz     SHORT it_is_3d4
        mov     dl,0b4h
it_is_3d4:

        ; unlock PR1B flat panel unlock register for 
        ; PR18-1A, PR36-41 and PR44
	mov	eax,C_P34-C_HTotal		;
	out	dx,al
	IO_Delay
	inc	edx
	mov	al, 0A6h		     	; Unlock access
	out	dx,al
	IO_Delay
	dec	edx

	mov	eax,C_P32-C_HTotal		;
	out	dx,al
	IO_Delay
	inc	edx
	in      al, dx
	IO_Delay
	dec	edx

        test    al, 20h         ; if bit # 5 = 1 -> CRT side
        jnz     SHORT CRT_side
        test    al, 10h         ; if bit # 4 = 1 -> LCD side
        jz      SHORT CRT_side

        ; if LCD side -> set 3?5.34 to 0
        ; if LCD side -> set 3CF.0C bit # 1 to 0
	mov	eax,C_P34-C_HTotal		;
	out	dx,al
	IO_Delay
	inc	edx
	mov	al, 0
	out	dx,al
	IO_Delay
	dec	edx

        mov     edx, 3ceh
	mov	al,G_PVGA2-G_SetRst
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.VDD_Stt.G_PVGA2]        ; Restore memory configuration
        and     al, 0FCh                ; LCD side -> 3CF.0C bit # 1 -> 0
	out	dx,al
	IO_Delay
	dec	edx
        jmp     SHORT EXIT_1F

CRT_side:
        mov     edx, 3ceh
	mov	al,G_PVGA2-G_SetRst
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.VDD_Stt.G_PVGA2]        ; Restore memory configuration
        or      al, 2                   ; CRT side -> 3CF.0C bit # 1 -> 1
	out	dx,al
	IO_Delay
	dec	edx

EXIT_1F:
        pop     edx
        jmp     SHORT VRC_done2

notPVGA1F:

        mov	al,G_PVGA2-G_SetRst
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.VDD_Stt.G_PVGA2] 	; Restore memory configuration
	out	dx,al
	IO_Delay
	dec	edx

VRC_done2:

	mov	al,G_PVGA3-G_SetRst
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[esi.VDD_Stt.G_PVGA3]	; Restore memory configuration
	out	dx,al
	IO_Delay
	dec	edx

VRC_PVGA4:
        mov     al,G_PVGA4-G_SetRst
        out     dx,al
        IO_Delay
        inc     edx
        mov     al,[esi.VDD_Stt.G_PVGA4]       ; Restore memory configuration
        out     dx,al
        IO_Delay
        dec     edx

VRC_PVGA5:
; This will cause problem in PVGA 1F board when setting the modes which 
; need to program the bank register 3x4.09 in DOS full screen.  The value 
; from [VDD_Stt.G_PVGA5] is not correct for 1F board.  This won't unlock 
; extended Graphic controller.				C. Chiang
; 
;***	mov	al,G_PVGA5-G_SetRst		; Restore access lock/unlock
;***	out	dx,al
;***	IO_Delay
;***	inc	edx
;***	mov	al,[esi.VDD_Stt.G_PVGA5]
;***	out	dx,al
;***	dec	edx
	jmp	VRC_Exit

VRC_PVGA9:
ENDIF	;PVGA

;
; this is Post_Restore_MemC
;
IFDEF NEWCLVGA
	TestMem [edi.VDD_TFlags],<fVT_NEWCLVGA>
	jz	CLRCTLR_Exit

	push	eax
	push	ebx
	push	ecx
	push	edx
	push	esi
;
; now, save the state of the extended registers access bit
;
	mov	edx,pGrpIndx
        in      al,dx
        push    eax

	mov	al,0AH
	IO_Delay
	out	dx,al
	inc	edx
	IO_Delay
	in	al,dx
	dec	edx
        cmp     al,1                    ; Q: Ext. enabled?
	je	SHORT CLRCTLR_10	;  Y: Don't need to enable again
	mov	ax,0EC0Ah		; (value to enable it)
	IO_Delay
	out	dx,ax			;  N: enable it
CLRCTLR_10:

;
; start the restore...
;
        push    edi
	lea	esi,cs:NewCLExtRegTable.MIN_NewCLTable
	lea	edi,[edi.VDD_Stt.V_Extend.MIN_NewCLTable]
	mov	ecx,MAX_V_Extend+1-MIN_NewCLTable
;
; we will restore MemC registers
;
	mov	bh,MIN_NewCLTable
;
        cld
CLReCT_20:
        lods    byte ptr cs:[esi]                ; flag from NewCLExtRegTable
        cmp     al,2            ; not crt=2, all others ignore
	jnz	short @F	;
        mov     al,bh           ; index to al
        mov     ah,[edi]        ; data to ah
        out     dx,ax           ;
@@:
        inc     edi
        inc     bh
	loop	CLReCT_20
;
        pop     edi
        push    edi
;
	lea	esi,cs:NewCLExtRegTable.MIN_C_Extension
	lea	edi,[edi.VDD_Stt.C_Extension.0]
	mov	ecx,MAX_C_Extension-MIN_C_Extension
;
; we will restore MemC registers
;
	mov	bh,MIN_C_Extension
;
        cld
IIndCLReCT_20:
        lods    byte ptr cs:[esi]                ; flag from NewCLExtRegTable
        cmp     al,2            ; not crt=2, all others ignore
	jnz	short @F	;
        mov     al,bh           ; index to al
        mov     ah,[edi]        ; data to ah
        out     dx,ax           ;
@@:
        inc     edi
        inc     bh
	loop	IIndCLReCT_20
;
        pop     edi

	cmp	[edi.VDD_Stt.V_Extend.0Ah],1 ; Q: Ext. enabled?
	mov	ax,0EC0Ah		; (value to enable it)
;	je	SHORT CLRCTLR_30	;  Y: enable it then
;	mov	ax,0CE0Ah		;     disable value
CLRCTLR_30:
	IO_Delay
	out	dx,ax
;
        pop     eax
	IO_Delay
        out     dx,al           ; restore index
;
	pop	esi
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
CLRCTLR_Exit:

ENDIF ;NEWCLVGA

IFDEF	CLV7VGA
	TestMem [edi.VDD_TFlags],<fVT_V7VGA+fVT_CLVGA>
	jz	VORM_SkipCLV7
;
; save the state of the extended registers access bit and enable extensions
;
	mov	dl,(pSeqIndx AND 0FFh)
	mov	al,6
	out	dx,al
	inc	edx
	in	al,dx
	dec	edx
        cmp     al,1                    ; Q: Ext. enabled?
	je	SHORT CLV7RCTLR_10	  ;  Y: Don't need to enable again
	mov	ax,[Vid_Enable_IV_Word] ; (value to enable it)
	out	dx,ax			;  N: enable it
CLV7RCTLR_10:

;
; Restore all the MemC registers
;
%OUT Do we need different CL and V7 tables?
	mov	ecx,080h
CLV7ReCT_20:
	test	[mVid_CLV7_MemC][ecx-80h],-1
	jz	SHORT CLV7ReCT_skip
	call	VDD_OEM_CLV7_Reg_Out
;
CLV7ReCT_skip:
	inc	cl			; Q: Do all regs from 80h to FFh?
	jz	SHORT CLV7ReCT_Done
IFDEF	CLVGA
	TestMem [edi.VDD_TFlags],fVT_CLVGA
	jz	CLV7ReCT_20		;   N: continue
	cmp	cl,0E0h 		; Q: At end of CL regs?
	jae	SHORT CLV7ReCT_Done	;   Y: Done
ENDIF
	jmp	CLV7ReCT_20		;   N: continue
CLV7ReCT_Done:
;
; do any MemC modifications
;
	TestMem [edi.VDD_Flags], fVDD_MemCmods
	jz	short CLV7ReCT_no_mods
	movzx	ecx, [edi.VDD_MemC_ModCnt]
	jecxz	short CLV7ReCT_no_mods
	lea	esi, [edi.VDD_MemC_Mods]
	mov	dx, pSeqIndx
CLV7ReCT_loop:
	test	[esi.MMS_flags], fMMS_OEM_extension
	jz	short CLV7ReCT_next
	cmp	[esi.MMS_data_port], pSeqData
	jne	short CLV7ReCT_next
	mov	al, [esi.MMS_index]
	out	dx, al
	inc	dl
	in	al, dx
	and	al, [esi.MMS_ANDmask]
	or	al, [esi.MMS_ORmask]
	out	dx, al
	dec	dl
CLV7ReCT_next:
	add	esi, SIZE MemC_Mod_Struc
	loop	CLV7ReCT_loop

CLV7ReCT_no_mods:

	cmp	[edi.VDD_Stt.S_Rst.6],1 ; Q: Ext. enabled?
	mov	ax,[Vid_Enable_IV_Word] ;	(value to enable it)
	je	SHORT CLV7RCTLR_30	  ;   Y: enable it then
	mov	ax,[Vid_Disable_IV_Word];	(disable value)
CLV7RCTLR_30:
	out	dx,ax
	jmp	SHORT VRC_Exit
VORM_SkipCLV7:
ENDIF	;CLV7VGA

IFDEF ATIVGA
	TestMem [edi.VDD_TFlags],fVT_ATiVGA
	jz	SHORT VORM_SkipATI
;
;;Debug_Out "ATI Post restore MemC"
%OUT During SYNC RESET? We better be in VRTC!!	Do we need to merge any regs?
IF 0
	push	ecx
IFDEF	DEBUG
int 1
	jmp	SHORT VORM_Got_VRTCDIxx
ENDIF
	mov	dl,(pStatColr AND 0FFh)
IFDEF	VGAMONO
	test	[edi.VDD_Stt.V_Misc],fMiscPnum
	jz	SHORT VORM_Colr
	mov	dl,(pStatMono AND 0FFh)
VORM_Colr:
ENDIF
	mov	ah,2
VORM_Wait_VRTC:
	mov	ecx,8000h
VORM_VRTC_Loop:
	in	al,dx
	test	al,fStatVRTC
	jnz	SHORT VORM_Got_VRTC
	loop	VORM_VRTC_Loop
VORM_Got_VRTCDIxx:
	cli
	jmp	SHORT VORM_Got_VRTCDI
VORM_Got_VRTC:
	cli
	in	al,dx
	test	al,fStatVRTC
	jnz	SHORT VORM_Got_VRTCDI
	dec	ah
	jz	SHORT VORM_Got_VRTCDI
	sti
	jmp	VORM_Wait_VRTC

VORM_Got_VRTCDI:
	pop	ecx
ENDIF

	mov	dx,ATIVGA_extended_reg
	mov	al,0b0h 			    ; Mask with 040h and merge?
	mov	ah,[esi.VDD_Stt.V_Extend.ATI_Regs+010h]
	out	dx, al
	inc	edx
	in	al, dx
	and	al, 1
	or	ah, al
	mov	al, 0b0h
	dec	edx
	out	dx,ax

	test	[edi.VDD_TFlags],fVT_ATiVGA3
	jnz	SHORT VORM_skip_b2

	mov	al,0b2h
	mov	ah,[esi.VDD_Stt.V_Extend.ATI_Regs+12h]
	out	dx,ax

VORM_skip_b2:
	sti
;
;
VORM_SkipATI:
ENDIF	;ATIVGA

VRC_Exit:
	pop	edx
	ret
EndProc VDD_OEM_Post_Restore_MemC,PUBLIC


;******************************************************************************
;VDD_OEM_Pre_Restore_Attr
;
;DESCRIPTION:
;	This routine does any programming of the Attribute controller that
;	is not done straight, in line (i.e. starting at register 0 up to
;	register 1Fh).
;
;ENTRY: EBX = VM_Handle of VM getting CRTC state (= 0 if VDD)
;	ESI -> VDD CB data of MemC VM
;	EDI -> VDD CB data of CRTC VM
;	EBP = 0FFFFFFFFh (mask for output of ATTR registers)
;	DX = 3BA or 3DA
;
;EXIT:	EBP = mask for output of attribute controller registers
;
;USES:	EAX, ECX, EBP, Flags
;
;==============================================================================
BeginProc VDD_OEM_Pre_Restore_Attr, High_Freq, PUBLIC

	push	edx

;*******
; Attribute controller regs 10,12,13
	mov	al,A_Mode-A_Pal
	mov	ah,[edi.VDD_Stt.A_Mode]
	call	VDD_State_Attr_Out
	mov	al,A_PlEna-A_Pal
	mov	ah,[edi.VDD_Stt.A_PlEna]
	call	VDD_State_Attr_Out
	mov	al,A_HPan-A_Pal
	mov	ah,[edi.VDD_Stt.A_HPan]
	call	VDD_State_Attr_Out

;*******
; Attribute controller regs 14,0-F, 11
IFNDEF CTVGA
	mov	al,A_Color-A_Pal
	mov	ah,[edi.VDD_Stt.A_Color]
	call	VDD_State_Attr_Out
ENDIF	;CTVGA

	mov	dl,(pSeqIndx AND 0FFh)
	mov	al,1
	out	dx,al
	mov	al,[edi.VDD_Stt.S_ClMode]
	inc	edx
	or	al,20h				; Turn screen off
	out	dx,al

	pop	edx
	and	ebp,00001FFFFh			; Just do first 17 registers
	ret
EndProc VDD_OEM_Pre_Restore_Attr

;******************************************************************************
;VDD_OEM_Post_Restore_Attr
;
;DESCRIPTION:
;	This routine does any additional Attr or DAC state programming necessary.
;
;ENTRY: EBX = VM_Handle of VM getting CRTC state (= 0 if VDD)
;	ESI -> VDD CB data of MemC VM
;	EDI -> VDD CB data of CRTC VM
;	DX = 3BA or 3DA
;
;EXIT:	none
;
;USES:	EAX, ECX, Flags
;
;==============================================================================
BeginProc VDD_OEM_Post_Restore_Attr, High_Freq, PUBLIC

	push	edx
	mov	al,A_OvScn-A_Pal
	mov	ah,[edi.VDD_Stt.A_OvScn]
	call	VDD_State_Attr_Out

	mov	dl,(pSeqIndx AND 0FFh)

	mov	al,1
	out	dx,al
	mov	al,[edi.VDD_Stt.S_ClMode]
	inc	edx
	out	dx,al				; Restore clocking mode

	pop	edx
	ret
EndProc VDD_OEM_Post_Restore_Attr, PUBLIC


;******************************************************************************
;VDD_OEM_Pre_Save_Regs, VDD_OEM_Post_Save_Regs
;
;DESCRIPTION:
;	Set up for saving of registers (Pre) and then restore that state (Post)
;	Pre_Save_Regs must be called before Post_Save_Regs.
;
;ENTRY: EBX = VM_Handle
;	EDI -> VDD CB data
;	DX = 3B4 or 3D4
;
;EXIT:	none
;
;USES:	Flags, EAX
;
;==============================================================================
BeginProc VDD_OEM_Pre_Save_Regs

IFDEF Handle_VGAEnable
	push	edx
; Make sure video enabled
	mov	dx,pVGAEna
IFDEF	TLVGA
; Tseng labs has video subsystem enable on two diff ports depending
;	on value in feature control.  Also has another bit to worry about.

	mov	ah,fVGAEna
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jz	SHORT VSC_NotTLEnaRd
;;	mov	dx,pFeatRead
;;	in	al,dx
;;	and	al,3
;;	cmp	al,3
;;	mov	dx,pVGAEna
;;	jnz	SHORT VSC_NotTLEnaRd
	or	ah,8
	mov	dx,46E8h			; Other VGA Enable port
VSC_NotTLEnaRd:
	in	al,dx
	IO_Delay
	mov	[edi.VDD_STT.V_VGAEna],al
	or	al,ah				; Make sure enable is true
ELSE
	in	al,dx
	IO_Delay
	mov	[edi.VDD_STT.V_VGAEna],al
	or	al,fVGAEna			; Make sure enable is true
ENDIF	;TLVGA
	out	dx,al
	IO_Delay
	mov	[Vid_OEM_Port_Enable],dx

	pop	edx
ENDIF	;Handle_VGAEnable
	ret
EndProc VDD_OEM_Pre_Save_Regs

BeginProc VDD_OEM_Post_Save_Regs

IFDEF	NEWCLVGA
	call	NewCL_SaveExtRegs      		; save 'NEW'cirrus logic ext 
ENDIF

IFDEF Handle_VGAEnable
	push	edx

; Restore VM's video subsystem enable register
	mov	dx,[Vid_OEM_Port_Enable]
	mov	al, [edi.VDD_STT.V_VGAEna]
	out	dx,al
	pop	edx
ENDIF	;Handle_VGAEnable
	ret
EndProc VDD_OEM_Post_Save_Regs

;******************************************************************************
;VDD_OEM_Save_Regs
;	Save the non standard VGA registers
;	The screen may be on or off (See Vid_Flags, fVid_DOff).  If the
;	registers cannot be read with the screen on, this routine must
;	provide special handling so that the screen is turned off in a
;	non-destructive way and the display DOES NOT FLICKER.
;	One possible way to do this is to do all operations during vertical
;	retrace (if this does a CLI, make it QUICK).  Note that the VM for whom
;	the registers are being saved will ALWAYS be the CRTC owner AND the
;	MemC owner.
;	Also note that if the screen is ON, it is only necessary to save
;	the registers that affect the MemC state.
;
;ENTRY: EBX = VM_Handle
;	EDI -> VDD CB data
;	DX = 3B4 or 3D4
;
;EXIT:	none
;
;USES:	EAX, ECX, ESI, Flags
;
;==============================================================================
BeginProc VDD_OEM_Save_Regs, High_Freq, PUBLIC

	push	edx

IFDEF TTVGA
;	Save TVGA special regs.		- Henry Zeng
	TestMem [edi.VDD_TFlags],<fVT_TVGA>
	jz	short @f
	call	VDD_OEM_TVGA_Save
@@:
ENDIF ; TTVGA


IFDEF TLVGA
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jz	short VOSR_TLI_2
	mov	dx,03CDh		;segment select reg
	in	al,dx
IFDEF SysVMin2ndBank
IFDEF DEBUG
	TestMem [edi.VDD_TFlags], fVT_SysVMin2ndBank
	jz	short @F
	VMMCall Test_Sys_VM_Handle
	jz	short @F
	or	al, al
	jz	short @F
	Debug_Out 'VDD: non-SysVM writing non-zero (#al) value to segment reg'
@@:
ENDIF
ENDIF
	mov	[edi.VDD_Stt.V_Extend.TLI_SegSel],al

	;save "key":
	mov	dx, 3CAh		; assume ET3000
	TestMem [edi.VDD_TFlags],fVT_TL_ET4000
	jz	short @F
	mov	dl,0D8h 		;mode reg (assume color addrs set)
					; (on ET4000, bit 3D8.6=3BF bit 1)
@@:					; (on ET3000, bit 3CA.5=3BF bit 1)
	in	al,dx
	mov	[edi.VDD_Stt.V_Extend.TLI_Key],al
	jmp	SHORT VOS_SR_Exit
VOSR_TLI_2:
ENDIF

IFDEF	CLVGA
	call	CL_SaveExtRegs			; save cirrus logic ext regs
ENDIF

IFDEF	V7VGA
	TestMem [edi.VDD_TFlags],fVT_V7VGA		; Q: Video 7?
	jz	SHORT VOS_SR_V7_Skip		    ;	N: Skip
IF 0
	TestMem [Vid_Flags],fVid_DOff		    ; Q: Video off
%OUT We need to save a subset of the registers!
	jz	SHORT VOS_SR_Exit
ENDIF
;
; Enable access to extended registers and save state
;
	mov	dl,(pSeqIndx AND 0FFh)
	mov	al,6
	out	dx,al
	IO_Delay
	inc	edx
	in	al,dx
	dec	edx
	mov	[edi.VDD_Stt.S_Rst.6],al; Save enable value
        cmp     al,1                    ; Q: Ext. enabled?
	mov	ax,[Vid_Enable_IV_Word]
	jz	SHORT VOS_SR_V7_10
	out	dx,ax			;  N: enable it, save
	mov	ax,[Vid_Disable_IV_Word];    disable value
VOS_SR_V7_10:
	push	eax			; save for later restore

;
; Save all registers
;
	mov	ecx,080h
        cld
VOS_SR_V7_Loop:
	mov	al,cl
	out	dx,al
	inc	edx
	IO_Delay
        in      al,dx
	mov	[edi.VDD_Stt.V_Extend][ecx-80h],al
	dec	edx
	inc	cl
	jnz	SHORT VOS_SR_V7_Loop

	pop	eax			; Restore enable/disable state
        out     dx,ax
	IO_Delay

        mov     al,[edi.VDD_Stt.S_Indx]
	out	dx,al			; Restore index register
;
	jmp	SHORT VOS_SR_Exit
VOS_SR_V7_Skip:
ENDIF	;V7VGA

IFDEF ATIVGA
	TestMem [edi.VDD_TFlags],fVT_ATIVGA
	jz	SHORT VOSR_Skip_ATI

%OUT Correct registers being saved?
;; Debug_Out "ATI save regs"
; Just save registers B0-BE (not BF-AF)
	mov	ecx,0B0h
	mov	dx,ATIVGA_extended_reg

ATiVGA_save_xlp:
	mov	al,cl
	out	dx,al
	inc	edx
	in	al,dx
	dec	edx
	mov	[edi.VDD_Stt.V_Extend.ATI_Regs][ecx-0A0h],al
	inc	ecx
	cmp	cl,0bfh
	jb	ATiVGA_save_xlp

VOSR_Skip_ATI:
ENDIF	;ATIVGA

VOS_SR_Exit:
	pop	edx
	ret
EndProc VDD_OEM_Save_Regs


;******************************************************************************
;VDD_OEM_Save_Latches
;
;DESCRIPTION:
;	Save latches.  Assumes VM specified by EBX, EDI currently owns latches.
;	That is, it is just being removed from the MemC state.
;
;ENTRY: EBX = VM handle
;	EDI points to the VM control block
;
;EXIT:	If CF=1 latches are saved, else no OEM way to restore latches
;
;USES:	Flags, EAX, ECX, EDX
;
;==============================================================================
BeginProc VDD_OEM_Save_Latches,PUBLIC
Assert_VDD_ptrs ebx,edi

IFDEF TLVGA
	;no reason to save latches in 256 color mode
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jz	short VO_SL_TL_4
	TestMem [edi.VDD_TFlags],fVT_TLVGA	    ;test if ET3000
	jz	short VO_SL_TL_2
	;if ET3000, test ATC 10 bit 6 also for 256 color mode
	test	[edi.VDD_Stt.A_Mode],040h
	jnz	short VO_SL_NoLatches
VO_SL_TL_2:
	test	[edi.VDD_Stt.S_MMode],fSeq4Chain4
	jz	short VO_SL_SaveLatches
VO_SL_NoLatches:
	stc
VO_SL_SaveLatches:
	ret

VO_SL_TL_4:
ENDIF

IFDEF NEWCLVGA
	TestMem [edi.VDD_TFlags],<fVT_NEWCLVGA>
	jz	SHORT VO_SL_NotNewCL

	mov	dx,pGrpIndx
	in	al,dx
	push	eax
	mov	ax,0EC0Ah
	IO_Delay
	out	dx,ax			; enable extensions
	IO_Delay
	mov	ah,0C5h 		; AH = latch #3 index
	mov	ecx,4

NCLSvLT_30:
	mov	al,ah
	out	dx,al			; Select a latch
	IO_Delay
	inc	edx
	in	al,dx			; Get the latch and save it
	mov	[edi.VDD_Latches][ecx-1],al
	dec	edx
	dec	ah			; Next latch
	loopd	NCLSvLT_30
	pop	eax
	IO_Delay
	out	dx,al
	stc
	ret
VO_SL_NotNewCL:
ENDIF	;NEWCLVGA

IFDEF CLV7VGA
	TestMem [edi.VDD_TFlags],<fVT_V7VGA+fVT_CLVGA>
	jz	SHORT VO_SL_NotCLV7

	mov	dx,pSeqIndx
	in	al,dx
	push	eax
	mov	ax,[Vid_Enable_IV_Word]
	out	dx,ax			; enable extensions
	IO_Delay
	mov	ah,0A3h 		; AH = latch #3 index
	mov	ecx,4

V7SvLT_30:
	mov	al,ah
	out	dx,al			; Select a latch
	IO_Delay
	inc	edx
	in	al,dx			; Get the latch and save it
	mov	[edi.VDD_Latches][ecx-1],al
	dec	edx
	dec	ah			; Next latch
	loopd	V7SvLT_30
	pop	eax
	out	dx,al
	stc
	ret
VO_SL_NotCLV7:
ENDIF	;CLV7VGA

	clc
	ret
EndProc VDD_OEM_Save_Latches

;******************************************************************************
;VDD_OEM_Restore_Latches
;
;DESCRIPTION:
;	Restore latches
;
;ENTRY: EBX = CRTC VM handle
;	EDI -> VDD CB data of CRTC VM
;	ESI -> VDD CB data of MemC VM
;
;EXIT:	If CF=1 latches are restored, else no OEM way to restore latches
;
;USES:	Flags, EAX, ECX, EDX
;
;==============================================================================
BeginProc VDD_OEM_Restore_Latches,PUBLIC
Assert_VDD_ptrs ebx,edi

IFDEF TLVGA
;no reason to restore latches in 256 color mode
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jz	short VO_RL_NotTL
	TestMem [edi.VDD_TFlags],fVT_TLVGA	    ;test if ET3000
	jz	short VO_RL_TL_2
	;if ET3000, test ATC 10 bit 6 also for 256 color mode
	test	[edi.VDD_Stt.A_Mode],040h
	jnz	short VO_RL_TL_NoLatches
VO_RL_TL_2:
	test	[edi.VDD_Stt.S_MMode],fSeq4Chain4
	jnz	SHORT VO_RL_TL_NoLatches
VO_RL_TL_RestLatches:
	clc
	ret
VO_RL_TL_NoLatches:
	stc
	ret
VO_RL_NotTL:
ENDIF

IFDEF NEWCLVGA
	TestMem [edi.VDD_TFlags],<fVT_NEWCLVGA>
	jz	SHORT VO_RL_NotNewCL

	mov	dx,pGrpIndx
	in	al,dx
	push	eax
	mov	ax,0EC0Ah
	IO_Delay
	out	dx,ax			; enable extensions
	IO_Delay
	mov	al,0C5h 		; AL = latch #3 index
	mov	ecx,4
NCLReLT_30:
	mov	ah,[esi.VDD_Latches][ecx-1]
	out	dx,ax
	dec	al
	loopd	NCLReLT_30
	pop	eax
	IO_Delay
	out	dx,al
	stc
	ret
VO_RL_NotNewCL:
ENDIF	;NEWCLVGA

IFDEF CLV7VGA
	TestMem [edi.VDD_TFlags],<fVT_V7VGA+fVT_CLVGA>
	jz	SHORT VO_RL_NotCLV7

	mov	dx,pSeqIndx
	in	al,dx
	push	eax
	mov	ax,[Vid_Enable_IV_Word]
	out	dx,ax			; enable extensions
	IO_Delay
	mov	al,0A3h 		; AL = latch #3 index
	mov	ecx,4
V7ReLT_30:
	mov	ah,[esi.VDD_Latches][ecx-1]
	out	dx,ax
	dec	al
	loopd	V7ReLT_30
	pop	eax
	out	dx,al
	stc
	ret
VO_RL_NotCLV7:
ENDIF	;CLV7VGA

	clc
	ret
EndProc VDD_OEM_Restore_Latches


;******************************************************************************
;VDD_OEM_Enable_Local_Traps
;
;DESCRIPTION: Enable OEM specific I/O traps
;
;ENTRY: EBX = VM handle
;	EDI -> VDD CB data
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_OEM_Enable_Local_Traps

IFDEF ATIVGA
	TestMem [edi.VDD_TFlags],fVT_ATIVGA
	jz	SHORT VO_ELT_NotATIVGA
	mov	edx,ATiVGA_extended_reg
	VMMCall Enable_Local_Trapping
	inc	edx
	VMMCall Enable_Local_Trapping
VO_ELT_NotATIVGA:
ENDIF
	ret
EndProc VDD_OEM_Enable_Local_Traps


;******************************************************************************
;VDD_OEM_Disable_Local_Traps
;
;DESCRIPTION: Disable OEM specific I/O traps
;
;ENTRY: EBX = VM handle
;	EDI -> VDD CB data
;
;EXIT:	none
;
;USES:	Flags, EAX, ECX, EDX, ESI
;
;==============================================================================
BeginProc VDD_OEM_Disable_Local_Traps

IFDEF ATIVGA
	TestMem [edi.VDD_TFlags],fVT_ATIVGA
	jz	SHORT VO_DLT_NotATIVGA
	mov	edx,ATiVGA_extended_reg
	VMMCall Disable_Local_Trapping
	inc	edx
	VMMCall Disable_Local_Trapping
VO_DLT_NotATIVGA:
ENDIF
	ret
EndProc VDD_OEM_Disable_Local_Traps


IFDEF SysVMin2ndBank
;******************************************************************************
;
;   VDD_OEM_force_bank
;
;   DESCRIPTION:
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD CB data of VM
;		    AL = bank # (0 or 1)
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc VDD_OEM_force_bank

	TestMem [edi.VDD_TFlags], fVT_SysVMin2ndBank
	jz	short OEM_f_exit
	TestMem [Vid_Flags], fVid_DspDrvr_Init
	jz	short OEM_f_exit
	VMMCall Test_Sys_VM_Handle
	jnz	short OEM_f_exit

IFDEF TLVGA
	TestMem [edi.VDD_TFlags], fVT_TL_ET4000
	jz	short @F

	push	ecx
	mov	cl, al
	call	VDD_State_Get_CRTC_Index_Port
	in	al, dx
	mov	ah, al
	mov	al, 33h
	out	dx, al
	inc	edx
	mov	al, cl			; extended start address
	mov	[edi.VDD_Stt.C_HTotal.033h], al
	out	dx, al
	mov	al, ah
	dec	edx
	out	dx, al

	mov	al, cl			; set both read & write banks
	shl	al, 4
	or	al, cl
	mov	[edi.VDD_Stt.V_Extend.TLI_SegSel], al
	mov	dx, 03CDh
	out	dx, al
	pop	ecx
@@:
ENDIF

OEM_f_exit:
	ret

EndProc VDD_OEM_force_bank
ENDIF ;SysVMin2ndBank


;******************************************************************************
;
;   VDD_OEM_Adjust_Font_Access
;
;   DESCRIPTION:    Adjust planar state for saving/restoring the text soft
;		    font.
;
;   ENTRY:	    EDI -> VDD CB data of MemC VM
;
;   EXIT:	    none
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_OEM_Adjust_Font_Access

IFDEF IBMXGA
;
; see comment in vdddef.inc for a description about this hack
;
	TestMem [edi.VDD_TFlags], fVT_XGAbit
	jz	short @F
	pushad
	mov	esi, edi
	mov	edi, [Vid_CRTC_VM]
	add	edi, [Vid_CB_Off]
	call	VDD_State_Get_CRTC_Index_Port
	call	VDD_OEM_Out_CRTC_Mode
	popad
	Assumes_Fall_Through OEM_afa_exit   ; change to jump if more code added
@@:
ENDIF

OEM_afa_exit:
	ret

EndProc VDD_OEM_Adjust_Font_Access


IFDEF IBMXGA
;******************************************************************************
;
;   VDD_OEM_Out_CRTC_Mode
;
;   DESCRIPTION:    This routine is a hack to handle the redefinition of bit
;		    6 of CRT.17h for some IBM implementations.	Normally
;		    this bit selects byte/word addressing for the CRT
;		    controller and belongs to the CRTC owner.  On some IBM
;		    implementations (XGA, Model 75 Portable,...) this bit
;		    selects byte/word addressing of the graphics controller
;		    and thus belongs to the MemC owner!  So this routine
;		    updates CRT.17h with the merged bits from the CRTC owner
;		    and bit 6 of the MemC owner.
;
;   ENTRY:
;	ESI -> VDD CB data of MemC VM
;	EDI -> VDD CB data of CRTC VM
;	DX = 3B4 or 3D4
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc VDD_OEM_Out_CRTC_Mode

IFDEF DEBUG
	TestMem [edi.VDD_TFlags], fVT_XGAbit
	jnz	short @F
	Debug_Out 'WARNING: VDD_OEM_Out_CRTC_Mode called without fVT_XGAbit set'
@@:
ENDIF
	mov	al, C_Mode
	out	dx, al
	inc	edx
	mov	al, [edi.VDD_Stt.C_Mode]
	mov	ah, [esi.VDD_Stt.C_Mode]
	and	ax, 0100000010111111b
	or	al, ah
	out	dx, al
	ret

EndProc VDD_OEM_Out_CRTC_Mode

;******************************************************************************
;
;   VDD_OEM_Chk_DoubleWord
;
;   DESCRIPTION:    On IBM's implementation of XGA the doubleword bit
;		    (bit 6 in CRTC.14h) applies to both CRTC state and MemC
;		    state.  This affects the ability to save & restore
;		    mode 13h (IBM's 256 color VGA mode)  This routine forces
;		    this bit to 1 so that VDDVMMEM can access video memory
;		    correctly.	The sibling routine VDD_OEM_Restore_DoubleWord
;		    can be called to restore the bit according to the current
;		    CRTC owner's state.
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD CB data
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_OEM_Chk_DoubleWord

	TestMem [edi.VDD_TFlags], fVT_XGAbit
	jz	short oem_chkdw_exit
	push	eax
	push	edx
	call	VDD_State_Get_CRTC_Index_Port
	in	al, dx		    ; read & save current index
	mov	ah, al
	mov	al, 14h 	    ; change index to 14h
	out	dx, al
	inc	edx
	in	al, dx		    ; read current value and OR in bit 6
	or	al, 01000000b
	out	dx, al
	dec	edx		    ; restore index
	mov	al, ah
	out	dx, al
	pop	edx
	pop	eax
oem_chkdw_exit:
	ret

EndProc VDD_OEM_Chk_DoubleWord


;******************************************************************************
;
;   VDD_OEM_Restore_DoubleWord
;
;   DESCRIPTION:    This routine is used to restore the state of the doubleword
;		    bit to the correct state for the current CRTC owner.  See
;		    VDD_OEM_Chk_DoubleWord for a more complete description.
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD CB data
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_OEM_Restore_DoubleWord

	TestMem [edi.VDD_TFlags], fVT_XGAbit
	jz	short oem_rdw_exit
	push	eax
	push	edx
	call	VDD_State_Get_CRTC_Index_Port
	in	al, dx		    ; read & save current index
	push	eax
	mov	al, 14h 	    ; change index to 14h
	out	dx, al
	inc	edx
	in	al, dx		    ; read current value and OR in bit 6
	push	ebx
	mov	ebx, [Vid_CRTC_VM]
	add	ebx, [Vid_CB_Off]
	mov	ah, [ebx.VDD_Stt.C_HTotal+14h]
	pop	ebx
.errnz C_UndrLn - C_HTotal - 14h
	and	ax, 0100000010111111b
	or	al, ah
	out	dx, al		    ; restore bit value from CRTC owner
	dec	edx		    ; restore index
	pop	eax
	out	dx, al
	pop	edx
	pop	eax
oem_rdw_exit:
	ret

EndProc VDD_OEM_Restore_DoubleWord
ENDIF


;******************************************************************************
;
;   VDD_OEM_Pre_OUT_Misc
;
;   DESCRIPTION:
;
;   ENTRY:	    EDI -> VDD CB data VM
;		    AL = new value
;		    DX = pMisc
;
;   EXIT:	    Z flag set, if value equals old value so that out
;			isn't necessary
;
;   USES:	    Flags
;
;==============================================================================
BeginProc VDD_OEM_Pre_OUT_Misc

IFDEF ATIVGA
	TestMem [edi.VDD_TFlags],fVT_ATIVGA
	jz	SHORT pomisc_not_ati

	push	edx
	push	eax
	mov	ah, al
	add	dl, pMiscIn-pMisc
	in	al, dx
	sub	dl, pMiscIn-pMisc
	cmp	al, ah			;Q: new value same as old?
	je	short pomisc_ati_exit	;   Y: we're done

	mov	dl,(pStatColr AND 0FFh)
IFDEF	VGAMONO
	test	[edi.VDD_Stt.V_Misc],fMiscPnum
	jz	SHORT @F
	mov	dl,(pStatMono AND 0FFh)
@@:
ENDIF
	push	ecx
	mov	ecx,8000h
@@:
	in	al,dx
	test	al,fStatVRTC
	loopz	@B
	pop	ecx
	or	edi, edi		; clear Z flag

pomisc_ati_exit:
	pop	eax
	pop	edx
	jmp	short pomisc_exit

pomisc_not_ati:
ENDIF
	or	edi, edi		; clear Z flag
pomisc_exit:
	ret

EndProc VDD_OEM_Pre_OUT_Misc


IFDEF ATIVGA
;******************************************************************************
;VIOT_ATI
;
;DESCRIPTION: Handles ATI specific I/O ports.  Only trapped when ATIVGA is true.
;
;ENTRY: EBX = VM handle
;	AL = BYTE to output to port.
;	EDX = port address for I/O.
;	ECX = I/O type
;
;EXIT:	I/O has been handled
;
;USES:	Flags, AL, ECX, ESI
;
;==============================================================================
BeginProc VIOT_ATI,High_Freq
	SetVDDPtr edi
	Emulate_Non_Byte_IO		
	pushfd
	jnz	SHORT VIOT_ATI0
	cmp	ebx,[Vid_CRTC_VM]		    ; Q: CRTC owner?
	jnz	SHORT VIOT_ATI0
	call	VDD_State_Set_MemC_Owner	    ;	Y: Assign MemC state
VIOT_ATI0:
	cmp	dx,01CEh			    ; Q: Index register?
	jnz	SHORT VDD_OEM_IO_1CF		    ;	N: must be data
	popfd
	jnz	SHORT VIOT_In_ATI_Indx
	cmp	ebx,[Vid_CRTC_VM]		    ; Q: CRTC owner?
	jnz	SHORT VIOT_VO_1CE		    ;	N: skip physical output
	TestMem [Vid_Flags], fVid_MsgInit	    ; Q: Message mode init'd?
	jz	short VIOT_VO_1CE		    ;	N:
	out	dx,al
VIOT_VO_1CE:
	cmp	al,0a0h
	jb	SHORT VIOT_ATI_1ce_Ret
	cmp	al,0bfh
	ja	SHORT VIOT_ATI_1ce_Ret
	SetFlag [edi.VDD_Flags],fVDD_ATIEna
	mov	[edi.VDD_Stt.V_Extend.ATI_Indx],al

VIOT_ATI_1ce_Ret:
	ret

VIOT_In_ATI_Indx:
	ClrFlag [edi.VDD_Flags], fVDD_ATIEna
	cmp	ebx, [Vid_MemC_VM]
	jnz	SHORT VIOT_VI_ATI_Indx

; Physical input
VIOT_ATI_1CE_In:
	in	al,dx
	ret

; Virtual input
VIOT_VI_ATI_Indx:
	mov	al,[edi.VDD_Stt.V_Extend.ATI_Indx]
	ret

PUBLIC VDD_OEM_IO_1CF
VDD_OEM_IO_1CF:
	popfd
	jnz	SHORT VIOT_In_ATI_Data
IFDEF	DEBUG
	push	edx
	movzx	edx,[edi.VDD_Stt.V_Extend.ATI_Indx]
Queue_Out "ATI Out #AX,Index=#BX",eax,edx
	pop	edx
ENDIF ; DEBUG

; Physical output
	TestMem [edi.VDD_Flags],fVDD_ATIEna	; Q: Enabled?
	jz	SHORT VIOT_1CF_Exit		;   N: Ignore
	push	eax
	movzx	ecx,[edi.VDD_Stt.V_Extend.ATI_Indx]
	mov	[edi.VDD_Stt.V_Extend.ATI_Regs][ecx - 0A0h],al ; Save value
	mov	ah,al	
	mov	al,cl
	TestMem [Vid_Flags], fVid_MsgInit	; Q: Message mode init'd?
	jz	short VIOT_VO_ATI_Data		;   N:
	cmp	ebx, [Vid_CRTC_VM]		; Q: Own CRTC (and MemC)?
	jz	SHORT VIOT_PO_ATI_Data		;   Y: Do physical output
	cmp	ebx, [Vid_MemC_VM]		;   N: Own MemC?
	jnz	SHORT VIOT_VO_ATI_Data		;	N: skip output
						;	Y: Merge MemC, CRTC


;
; MemC != CRTC
; only let writes to extended registers 12h & 13h thru
;
	cmp	al, 0B2h
	jb	short VIOT_VO_ATI_Data
	cmp	al, 0B3h
	ja	short VIOT_VO_ATI_Data

VIOT_PO_ATI_Data:
	dec	edx
	out	dx,ax
	inc	edx
VIOT_VO_ATI_Data:
	pop	eax

VIOT_1CF_Exit:
	ClrFlag [edi.VDD_Flags], fVDD_ATIEna
	ret

VIOT_In_ATI_Data:
	cmp	ebx, [Vid_CRTC_VM]
	jnz	SHORT VIOT_VI_ATI_Data
	TestMem [Vid_Flags], fVid_MsgInit	    ; Q: Message mode init'd?
	jz	short VIOT_VI_ATI_Data		    ;	N:
; Physical input
	ClrFlag [edi.VDD_Flags], fVDD_ATIEna
VIOT_ATI_DoIn:
	in	al,dx
IFDEF	DEBUG
	jmp	SHORT VIOT_ATI_In_Exit
ELSE
	ret
ENDIF ; DEBUG

VIOT_VI_ATI_Data:
; Virtual input
	TestMem [edi.VDD_Flags],fVDD_ATIEna
	jz	SHORT VIOT_ATI_DoIn
	movzx	ecx,[edi.VDD_Stt.V_Extend.ATI_Indx]
	ClrFlag [edi.VDD_Flags], fVDD_ATIEna
	mov	al,[edi.VDD_Stt.V_Extend.ATI_Regs][ecx-0a0h]
	cmp	cl, 0B0h
	jae	short VIOT_ATI_In_Exit
	dec	edx
	in	al, dx			    ; read current index
	push	eax			    ; save it
	mov	al, cl			    ; write new index
	out	dx, al
	inc	edx
	in	al, dx			    ; read phys value
	mov	ch, al			    ; save it
	dec	edx
	pop	eax
	and	al, 1Fh 		    ; mask off offset bits
	add	al, 0A0h		    ; add in known offset bits
	out	dx, al			    ; restore original index
	inc	edx
	mov	al, ch			    ; al = phys value
VIOT_ATI_In_Exit:
IFDEF	DEBUG
	push	edx
	movzx	edx,[edi.VDD_Stt.V_Extend.ATI_Indx]
Queue_Out "ATI IN #AX,Index=#BX",eax,edx
	pop	edx
ENDIF ; DEBUG
	ret
EndProc VIOT_ATI

ENDIF

;******************************************************************************
;VDD_OEM_PO_Seq
;
;DESCRIPTION: Handles OEM variations on physical output to Sequencer.
;	The VM is owner of the CRTC state and the MemC state.
;
;ENTRY: EBX = VM handle
;	AL = BYTE to output to port.
;	EDX = port address for I/O.
;	ECX = Sequencer index register
;	Carry flag clear, Zero flag set
;
;EXIT:	AL = BYTE to output to port
;	If Carry flag set, don't do output
;	If Zero flag clear skip normal processing, just do output
;
;USES:	Flags, AL, ESI
;
;==============================================================================
BeginProc VDD_OEM_PO_Seq, High_Freq, PUBLIC
IFDEF TTVGA
	TestMem [edi.VDD_TFlags],<fVT_TVGA>	    ; Q: Trident TVGA?
	jnz	VO_PO_Seq_TVGA		    ;	Y: check for extensions
ENDIF ;TTVGA

IFDEF CLV7VGA
	TestMem [edi.VDD_TFlags],<fVT_V7VGA+fVT_CLVGA> ; Q: V7 or Cirrus Logic?
	jnz	SHORT VO_PO_Seq_CLV7		    ;	Y: check for extensions
						    ;	N: return CF = 0, ZF = 1
ENDIF	;CLV7VGA
VO_PO_Seq_NotOEM:               		    ;	do normal processing
        cmp     eax,eax         ; carry reset, z set
	ret


IFDEF CLV7VGA
VO_PO_Seq_CLV7:
	cmp	cl,6				    ; Q: Extensions enable reg?
	je	SHORT VO_PO_Seq_EnableExt	    ;	Y: save state of reg
	TestMem [edi.VDD_TFlags],fVT_CLVGA		; Q:Cirrus Logic?
	jz	SHORT @f			    ; No, dont combine dups.
	call	VO_CL_DupRegAdjust		    ; combine duplicate regs
@@:
	or	cl,cl				    ; Q: Extension register?
	jns	SHORT VO_PO_Seq_NotOEM	            ; N: go back, young man

; This is Video 7 extended register physical output
VO_PO_Seq_ExtReg:
; Check to see if Video 7 extensions are physically enabled
	push	eax
	dec	edx
	mov	al,6
	out	dx,al
	inc	edx
	in	al,dx
	mov	[edi.VDD_Stt.S_Rst.6],al	    ; Save ext. enable value
	mov	al,cl
	dec	edx
	out	dx,al
	inc	edx
	pop	eax
	cmp	[edi.VDD_Stt.S_Rst.6],1 	    ; Q: Ext. enabled?
	jne	SHORT VO_PO_Seq_DoOut		    ;	N: ignore the value
	cmp	cl,083h 			    ; Q: Special attr index reg?
	jz	SHORT VO_PO_Seq_SetAttr 	    ;	Y: Save Attr index data

; Video 7 extended register save then do physical output
%OUT special handling for fast latch loading (F0-F2) necessary
	mov	[edi.VDD_Stt.V_Extend][ecx-80H],al
	cmp	ebx,[Vid_CRTC_VM]		    ; Q: CRTC owner?
	jnz	SHORT VO_PO_Seq_CLV7_Merge	    ;	N: Merge CRTC bits first
						    ;	Y: Go do physical output
VO_PO_Seq_DoOut:
	or	ebx,ebx 			    ; CF = 0, ZF = 0
	ret

; Save Video 7 Attribute index register in appropriate place
VO_PO_Seq_SetAttr:
	xor	al,fVAI_Indx			    ; reverse meaning of bit
	mov	[edi.VDD_Stt.A_Indx],al 	    ; Set attribute index
	xor	al,fVAI_Indx			    ; Restore AL
	jmp	SHORT VO_PO_Seq_DoOut 		    ; Go do output

; Clear/set extension enable flag.
; V7 Extensions are enabled by writing an 0EAh (CLVGA uses 0CAh) to SR 6
; and are disabled by writing an 0AEh (0ACh) to SR 6. The hardware returns
; a 1 in SR 6 if extensions are enabled. It returns a 0 if extensions are
; disabled.  This routine transforms the output value to that returned by
; the hardware.
; ECX = 6
VO_PO_Seq_EnableExt:
	xor	cl,cl
	cmp	al,[Vid_Enable_Ext_Val] 	    ; Q: Enable extensions?
	jne	SHORT VO_PO_Seq_EnableExt_10	    ;	N: see if disable command
	inc	cl
	mov	[edi.VDD_Stt.S_Rst.6],cl	    ;	Extensions are enabled
	mov	cl,6
	jmp	SHORT VO_PO_Seq_DoOut
VO_PO_Seq_EnableExt_10:
	cmp	al,[Vid_Disable_Ext_Val]	    ; Q: Enable extensions?
	jne	VO_PO_Seq_DoOut 		    ;	N: ignore
	mov	[edi.VDD_Stt.S_Rst.6],cl	    ;	Y: Extensions disabled
	mov	cl,6
	jmp	SHORT VO_PO_Seq_DoOut

; Merge CRTC bits
VO_PO_Seq_CLV7_Merge:
	mov	esi,[Vid_CRTC_VM]
	add	esi,[Vid_CB_Off]
	xchg	esi, edi			    ; esi->MemC CB, edi->CRTC CB
	call	VDD_OEM_CLV7_Reg_Out
	xchg	esi, edi
	stc					    ; I/O handled
	ret

ENDIF	;CLV7VGA

IFDEF TTVGA
;----------------------------------------------------------------
;	Handles Trident TVGA Special Registers
;	Physical Output
;	- Henry Zeng
;----------------------------------------------------------------

VO_PO_Seq_TVGA:
	cmp	cl, 0Bh				; 3C5.B ?
	jb	VO_PO_Seq_NotOEM		; not Trident stuff
public PO_TVGA_3C5	
PO_TVGA_3C5:
	jnz	short @f
	mov	[edi.VDD_Stt.TVGA_3C5_B_v], al	; 3C5.B
	mov	[edi.VDD_Stt.TVGA_3C5_B], TVGA_3C5_B_WrMode
	jmp	short VO_PO_TVGA_3C5_DoOut
@@:

IF 0
IF TVGA8900C
	cmp	cl, 0Ch			; read/write
	jnz	short @f
	cmp	[edi.VDD_Stt.TVGA_3C5_E1_flag], 1
	jz	VIOT_OSeq_SaveAL	; write
	jmp	VIOT_Out_SeqRet
@@:
	cmp	cl, 0Fh
	jnz	short @f
	cmp	[edi.VDD_Stt.TVGA_3C5_E1_flag], 1
	jz	short VIOT_OSeq_SaveAL	; write
	jmp	short VIOT_Out_SeqRet
@@:
ELSE
	cmp	cl, 0Ch			; read only
	jz	short VIOT_Out_SeqRet
	cmp	cl, 0Fh
	jz	short VIOT_Out_SeqRet
ENDIF
ENDIF

	cmp	cl, 0Dh					; Q: 3C5.D ?
	jnz	short @f
	cmp	[edi.VDD_Stt.TVGA_3C5_B], TVGA_3C5_B_WrMode
	jz	short VO_PO_TVGA_3C5_D0
	mov	[edi.VDD_Stt.TVGA_3C5_D1], al		; 3C5.D1
	jmp	short VO_PO_TVGA_3C5_DoOut
VO_PO_TVGA_3C5_D0:
	mov	[edi.VDD_Stt.TVGA_3C5_D0], al		; 3C5.D0
	jmp	short VO_PO_TVGA_3C5_DoOut
@@:
		
	cmp	cl, 0Eh					; Q: 3C5.E ?
	jnz	short VO_PO_TVGA_3C5_DoOut
	cmp	[edi.VDD_Stt.TVGA_3C5_B], TVGA_3C5_B_WrMode
	jz	short VO_PO_TVGA_3C5_E0
							; 3C5.E1
	test	al, 80h					; Q: protect ?
	jz	short @f
	mov	[edi.VDD_Stt.TVGA_3C5_E1_flag], 1
	jmp	short VO_PO_TVGA_3C5_DoOut
@@:
	cmp	[edi.VDD_Stt.TVGA_3C5_E1_flag], 1
	mov	[edi.VDD_Stt.TVGA_3C5_E1_flag], 0
	jz	short VO_PO_TVGA_3C5_DoOut
	push	eax
	mov	ah, al
	and	al, 0Fh
	xor	al, 2  				; low 4 bit
	and	ah, 0F0h			; hi 4 bit
	jnz	short @f
	mov	ah, [edi.VDD_Stt.TVGA_3C5_E1]	; for protect bit 4-7
	and	ah, 0F0h
@@:
	or	al, ah
	mov	[edi.VDD_Stt.TVGA_3C5_E1], al
	pop	eax
	jmp	short VO_PO_TVGA_3C5_DoOut
VO_PO_TVGA_3C5_E0:				
	mov	[edi.VDD_Stt.TVGA_3C5_E0], al	; 3C5.E0

VO_PO_TVGA_3C5_DoOut:				; Do output
	or	ebx,ebx				; CF = 0, ZF = 0
	ret
ENDIF ;TTVGA

EndProc VDD_OEM_PO_Seq


;******************************************************************************
;VDD_OEM_VO_Seq
;
;DESCRIPTION: Handles OEM variations on physical output to Sequencer.  The VM
;	is not owner of the CRTC state, but might be owner of MemC state.
;
;ENTRY: EBX = VM handle
;	AL = BYTE to output to port.
;	EDX = port address for I/O.
;	ECX = Sequencer index register
;	Carry flag clear, Zero flag set
;
;EXIT:	AL = BYTE to output to port
;	If Carry flag set, do output
;	If Zero flag clear skip normal processing, just exit
;
;USES:	Flags, AL, ESI
;
;==============================================================================
BeginProc VDD_OEM_VO_Seq, High_Freq, PUBLIC

IFDEF TTVGA
	TestMem [edi.VDD_TFlags],<fVT_TVGA>	    ; Q: Trident TVGA?
	jnz	VO_VO_Seq_TVGA		    ;	Y: check for extensions
ENDIF ;TTVGA

IFDEF CLV7VGA
	TestMem [edi.VDD_TFlags],<fVT_V7VGA+fVT_CLVGA> ; Q: V7 or Cirrus Logic?
	jnz	SHORT VO_VO_Seq_V7		    ;	Y: check for extensions
						    ;	N: return CF = 0, ZF = 1
ENDIF	;CLV7VGA

; This is not OEM extension, handle normally
VO_VO_Seq_NotOEM:
	cmp	eax,eax 			    ; CF=0, ZF=1; do normal proc
	ret

VO_VO_Seq_IgnoreOEM:
	or	ebx,ebx 			    ; CF=0, ZF=0; ingore output
	ret

IFDEF CLV7VGA
; Check for Video 7 or Cirrus Logic extensions
VO_VO_Seq_V7:
	cmp	cl,6				    ; Q: Extensions enable reg?
	je	SHORT VO_VO_Seq_EnableExt	    ;	Y: save state of reg

	TestMem [edi.VDD_TFlags],fVT_CLVGA		; Q:Cirrus Logic?
	jz	SHORT @f			    ; No, dont combine dups.
	call	VO_CL_DupRegAdjust		    ; combine duplicate registers
@@:
	or	cl,cl				    ; Q: Extensions register?
	jns	SHORT VO_VO_Seq_NotOEM		    ;	N: do normal processing
; This is Video 7 or Cirrus Logic extension register
	cmp	[edi.VDD_Stt.S_Rst.6],1 	    ; Q: Ext. enabled?
	jne	SHORT VO_VO_Seq_IgnoreOEM	    ;	N: ignore the value
	cmp	cl,083h 			    ; Q: Set attribute index?
	jz	SHORT VO_VO_Seq_V7SetAttr	    ;	Y: Special save

; Save extended register to save area
VO_VO_Seq_V7Save:

; If this VM owns MemC state, we need to merge with CRTC state and do
;   the physical output
%OUT special handling for fast latch loading (F0-F2) necessary
	push	eax
	mov	esi,[Vid_CRTC_VM]
	add	esi,[Vid_CB_Off]
	mov	ah,[esi.VDD_Stt.V_Extend][ecx-80H]    ; AH = CRTC VM value
	mov	esi,ebx
	mov	bl,[mVid_CLV7_MemC][ecx-80h]	    ; BL = MemC bits mask
	or	bl,bl				    ; Q: Any MemC bits?
	jz	SHORT VO_VO_Seq_NoOut		    ;	N: Skip output

; Merge CRTC value with MemC value and output it
	and	al,bl				    ; AL = MemC bits
	not	bl
	and	ah,bl				    ; AH = CRTC bits
	or	al,ah				    ; AL = merged CRTC/MemC bits
IFDEF Ext_VGA
	cmp	cl,0FFh
	jnz	SHORT @F
	int 1
%OUT this probably isn't correct for all V7 cards!!!!!!!!
	or	al,10000b			    ; force 256K Bank Enable
@@:
ENDIF
	mov	ah,al
	not	bl
	xor	ah,[edi.VDD_Stt.V_Extend][ecx-80H]    ; AH = changed VM bits
	and	ah,bl				    ; Q: Any MemC bits change?
	jz	SHORT VO_VO_Seq_NoOut		    ;	N: Skip output
VO_VO_Seq_Out:
	cmp	esi,[Vid_MemC_VM]		    ; Q: MemC owner?
	jnz	SHORT VO_VO_Seq_NoOut		    ;	N: No output
VO_VO_Seq_DoOut:
	TestMem [Vid_Flags], fVid_MsgInit	    ; Q: Message mode init'd?
	jz	short VO_VO_Seq_NoOut		    ;	N:
	out	dx,al				    ;	Y: Output merged bits
VO_VO_Seq_NoOut:
	mov	ebx,esi 			    ; restore VM handle
	pop	eax				    ; AL = VM's output value
	mov	[edi.VDD_Stt.V_Extend][ecx-80H],al
	jmp	SHORT VO_VO_Seq_IgnoreOEM

; Attribute index at alternate port.  This belongs to CRTC
VO_VO_Seq_V7SetAttr:
	mov	esi,ebx
	push	eax
	xor	al,fVAI_Indx			    ; Reverse bit meaning
	mov	[edi.VDD_Stt.A_Indx],al 	    ; Save attribute index
	cmp	esi,[Vid_CRTC_VM]		    ; Q: This VM own CRTC?
	jz	VO_VO_Seq_DoOut 		    ;	Y: Do output
	jmp	VO_VO_Seq_NoOut 		    ;	N: skip output

; Clear/set extension enable flag.
; V7 Extensions are enabled by writing an 0EAh (CLVGA uses 0CAh) to SR 6 and are
; disabled by writing an 0AEh (0ACh) to SR 6. The hardware returns a 1 in SR 6
; if extensions are enabled. It returns a 0 if extensions are disabled.
; This routine transforms the output value to that returned by the hardware
; ECX = 6
VO_VO_Seq_EnableExt:
	mov	esi,ebx
	push	eax
	xor	cl,cl				    ;	Y: set disable value
	cmp	al,[Vid_Enable_Ext_Val] 	    ; Q: Enable extensions?
	jne	SHORT VO_VO_Seq_EnableExt_10	    ;	N: see if disable
	inc	cl
	mov	[edi.VDD_Stt.S_Rst.6],cl
	jmp	SHORT VO_VO_Seq_Out
VO_VO_Seq_EnableExt_10:
	cmp	al,[Vid_Disable_Ext_Val]	    ; Q: Enable extensions?
	jne	VO_VO_Seq_Out			    ;	N: ignore this value
	mov	[edi.VDD_Stt.S_Rst.6],cl
	jmp	SHORT VO_VO_Seq_Out
ENDIF ;CLV7VGA

IFDEF TTVGA
;----------------------------------------------------------------
;	Handles Trident TVGA Special Registers
;	Vitrual Output
;	- Henry Zeng
;
; ??? can not handle MemC state, do later
;----------------------------------------------------------------

VO_VO_Seq_TVGA:
	cmp	cl, 0Bh				; 3C5.B ?
	jb	VO_VO_Seq_NotOEM		; not Trident stuff
public VO_TVGA_3C5	
VO_TVGA_3C5:
	jnz	short @f
	mov	[edi.VDD_Stt.TVGA_3C5_B_v], al
	mov	[edi.VDD_Stt.TVGA_3C5_B], TVGA_3C5_B_WrMode
	jmp	short VO_VO_TVGA_3C5_Done
@@:

	cmp	cl, 0Dh					; Q: 3C5.D ?
	jnz	short @f
	cmp	[edi.VDD_Stt.TVGA_3C5_B], TVGA_3C5_B_WrMode
	jz	short VO_VO_TVGA_3C5_D0
	mov	[edi.VDD_Stt.TVGA_3C5_D1], al		; 3C5.D1
	jmp	short VO_VO_TVGA_3C5_Done
VO_VO_TVGA_3C5_D0:
	mov	[edi.VDD_Stt.TVGA_3C5_D0], al		; 3C5.D0
	jmp	short VO_VO_TVGA_3C5_Done
@@:
		
	cmp	cl, 0Eh					; Q: 3C5.E ?
	jnz	short VO_VO_TVGA_3C5_Done
	cmp	[edi.VDD_Stt.TVGA_3C5_B], TVGA_3C5_B_WrMode
	jz	short VO_VO_TVGA_3C5_E0
							; 3C5.E1
	test	al, 80h					; Q: protect ?
	jz	short @f
	mov	[edi.VDD_Stt.TVGA_3C5_E1_flag], 1
	jmp	short VO_VO_TVGA_3C5_Done
@@:
	cmp	[edi.VDD_Stt.TVGA_3C5_E1_flag], 1
	mov	[edi.VDD_Stt.TVGA_3C5_E1_flag], 0
	jz	short VO_VO_TVGA_3C5_Done
	push	eax
	mov	ah, al
	and	al, 0Fh
	xor	al, 2  				; low 4 bit
	and	ah, 0F0h			; hi 4 bit
	jnz	short @f
	mov	ah, [edi.VDD_Stt.TVGA_3C5_E1]	; for protect bit 4-7
	and	ah, 0F0h
@@:
	or	al, ah
	mov	[edi.VDD_Stt.TVGA_3C5_E1], al
	pop	eax
	jmp	short VO_VO_TVGA_3C5_Done
VO_VO_TVGA_3C5_E0:				
	mov	[edi.VDD_Stt.TVGA_3C5_E0], al	; 3C5.E0

VO_VO_TVGA_3C5_Done:				; all done
	or	ebx,ebx				; CF = 0, ZF = 0
	ret
ENDIF ;TTVGA

EndProc VDD_OEM_VO_Seq

IFDEF CLVGA
;******************************************************************************
; VO_CL_DupRegAdjust
;
; DESCRIPTION: Handles the combination of duplicate registers in
;               CIRRUS LOGIC VGA products ONLY.
;
;ENTRY: EBX = VM handle
;	AL = BYTE to output to port.
;	EDX = port address for I/O.
;	ECX = Sequencer index register
;
;EXIT:	Changes Nothing
;
;******************************************************************************

BeginProc VO_CL_DupRegAdjust, High_Freq, PUBLIC

	cmp     cl,01h				    ; is it clocking mode reg
	jz      SHORT VIOT_VO_CLClkMode             ; duplicate clock mode bits

	cmp	[edi.VDD_Stt.S_Rst.6],1 	    ; Q: Ext. enabled?
	jne	SHORT DupRegAdjust_End		    ;	N: ignore the value

	cmp     cl,85h				    ; clocking ext reg ?
	jz      SHORT VIOT_VO_CLClkMode             ; duplicate clock mode bits

CLVGA_ROM_Banking = 1
IFDEF CLVGA_ROM_Banking
	cmp	cl,08Ah 			    ; rom bank register ?
	jz	SHORT VIOT_VO_CLRomBank 	    ; yes - jump
ENDIF
		
	cmp	cl,083h				    ; attribute index ?
	jz	SHORT VIOT_VO_CLAttr                ; yes - jump

	cmp     cl,090h                             ; vertical retrace start ?
	jz      SHORT VIOT_VO_CLVrStart             ; yes - jump

	cmp     cl,091h                             ; vertical retrace end ?
	jz      SHORT VIOT_VO_CLVrEnd               ; yes - jump

	cmp     cl,0A4H                             ; clock select (misc output)
	jz      SHORT VIOT_VO_CLClk                 ; yes - jump

	cmp     cl,0A0h                             ; memory latch ?
	jb	SHORT DupRegAdjust_End		    ; no - then jump

	cmp     cl,0A3h                             ; memory latch ?
	jbe    	SHORT VIOT_VO_CLMemLatch            ; yes - then jump

DupRegAdjust_End:
	ret
; ------------------------------------
;	Special Case For Seq reg 01h - Clock Mode Reg
;       bits 0 - bit 0 is duplicated as bit 0 of extension reg 85h.

VIOT_VO_CLClkMode:
	push	eax				    ; save the reg value
	and	al,1				    ; save bit 0
	
	and	[edi.VDD_Stt.V_Extend.CL_ER_TC],0feh  ; clear bit in ext reg
	or	[edi.VDD_Stt.V_Extend.CL_ER_TC],al    ; setup bit in ext reg
	
	and	[edi.VDD_Stt.S_ClMode],0feh	    ; clear bit in ext reg
	or	[edi.VDD_Stt.S_ClMode],al	    ; setup bit in ext reg

	pop	eax
	jmp	DupRegAdjust_End		    ; go save ext value


IFDEF CLVGA_ROM_Banking
; ------------------------------------
;	Special Case For Cirrus Extension Reg 8AH
;       bits 0 - 2 control rom bank addressing for last 8 k of rom. Must
;                  be passed through to hardware so rom can get to banked
;                  routines even in virtusl mode.
VIOT_VO_CLRomBank:
	push	eax				    ; save registers
	push	ebx
	push	edx

	dec	edx				    ; point to index reg
	mov	ah,al				    ; place write value in ah
	in	al,dx				    ; get current index
	mov	bh,al				    ; save for later
	mov	al,cl				    ; get index of register
	out	dx,al				    ; select the register

	inc	edx				    ; point to data
	in	al,dx				    ; get current value
	and	ah,7				    ; keep the rom bits
	and	al,0F8H 			    ; keep all but rom
	or	ah,al				    ; create new value
	mov	al,cl				    ; get the index
	dec	edx				    ; point to index reg
	out	dx,ax				    ; select the rom

	mov	al,bh				    ; get old index
	out	dx,al				    ; restore index
	pop	edx
	pop	ebx				    ; restore regs
	pop	eax
	jmp	DupRegAdjust_End		    ; go save ext value
ELSE
%OUT Multiple ROM banks not supported
ENDIF

; ------------------------------------
;	Special Case For Cirrus Extension Reg 83H
;       bits 0 - 6 - are duplicates of the attribute index
;                7 - indicates the state of index/data latch (0-index/1-data)
;
;            Any change to this register should be reflected in the 
;       attribute index regs and index/data state.
;

VIOT_VO_CLAttr:
	xor	al,fVAI_Indx			    ; reverse state for flag
	mov	[edi.VDD_Stt.A_Indx],al		    ; set attribute index
	xor	al,fVAI_Indx			    ; reverse to ext state
	jmp	DupRegAdjust_End 		    ; go save ext value

;--------------------------------------
;	Special Case For Cirrus Extension Reg 90H
;       bits 0 - 7 - are duplicates of the CRTC reg 10h
;            Any change to this register should be reflected in the 
;       CRTC register.

VIOT_VO_CLVrStart:
	mov	[edi.VDD_Stt.CRTC.C_VRTCStrt],al    ; set vertical start
	jmp	DupRegAdjust_End   		    ; go save ext value

;--------------------------------------
;	Special Case For Cirrus Extension Reg 91H
;       bits 0 - 7 - are duplicates of the CRTC reg 11h
;            Any change to this register should be reflected in the 
;       CRTC register.

VIOT_VO_CLVrEnd:
	mov	[edi.VDD_Stt.CRTC.C_VRTCEnd],al     ; set vertical end
	jmp	DupRegAdjust_End   		    ; go save ext value


;--------------------------------------
;	Special Case For Cirrus Extension Reg A4H
;       bits 2,3 - are duplicates of the bits 2,3 in Misc Output Reg
;            Any change to this register should be reflected in the 
;       Misc Output register.

VIOT_VO_CLClk:
	push	eax				    ; save the current value
	mov	ah,al				    ; place value in ah
	and	ah,00Ch 			    ; keep duplicate clk bits
	mov	al,[edi.VDD_Stt.V_Misc] 	    ; get the save MOR value
	and	al,NOT 00Ch			    ; keep all but the clk bits
	or	al,ah				    ; merge in new clk bits
	mov	[edi.VDD_Stt.V_Misc],al 	    ; set the save MOR value
	pop	eax				    ; restore the reg
	and	al, NOT 1			    ; clear bit 0
	jmp	DupRegAdjust_End		    ; go save ext value

;--------------------------------------
;	Special Case For Cirrus Extension Regs A0H to 0A3
;	These registers are duplicates of the memory plane latches.

VIOT_VO_CLMemLatch:
	push	ecx				    ; save the index values
	and	cl,3				    ; keep the latch number
	mov	[edi.VDD_Latches][ecx],al	    ; save the latch value
	pop	ecx				    ; restore the ext index
	jmp	DupRegAdjust_End		    ; go save ext value

EndProc VO_CL_DupRegAdjust


ENDIF   ; CLVGA


IFDEF TTVGA
;******************************************************************************
;VDD_OEM_PI_Seq
;
;DESCRIPTION: Handles OEM variations on physical input from Sequencer.
;	      Added for handling Trident special case.
;	      - Henry Zeng
;
;ENTRY: EBX = VM handle
;	EDX = port address for I/O.
;	ECX = Sequencer index register
;	Zero flag set
;
;EXIT:
;
;USES:	Flags
;
;==============================================================================
BeginProc VDD_OEM_PI_Seq, High_Freq, PUBLIC
	cmp	cl, 0Bh
	jnz	short @f
	mov	[edi.VDD_Stt.TVGA_3C5_B], TVGA_3C5_B_RdMode
@@:
	ret
EndProc VDD_OEM_PI_Seq
ENDIF ; TTVGA

;******************************************************************************
;VDD_OEM_VI_Seq
;
;DESCRIPTION: Handles OEM variations on virtual input from Sequencer.  The VM
;	is not owner of both the MemC and CRTC state but may be owner of one.
;
;ENTRY: EBX = VM handle
;	EDX = port address for I/O.
;	ECX = Sequencer index register
;	Zero flag set
;
;EXIT:	If Zero flag clear, AL = input byte, else do normal processing
;
;USES:	Flags, AL, ESI
;
;==============================================================================
BeginProc VDD_OEM_VI_Seq, High_Freq, PUBLIC
IFDEF TTVGA
	TestMem [edi.VDD_TFlags],<fVT_TVGA>	; Q: Tident TVGA?
	jnz	short VO_VI_Seq_TVGA			;   Y: check for extensions
ENDIF ;TTVGA

IFDEF CLV7VGA
	TestMem [edi.VDD_TFlags],<fVT_V7VGA+fVT_CLVGA> ; Q: V7 or Cirrus Logic?
	jnz	SHORT VO_VI_Seq_V7		    ;	Y: check for extensions
						    ;	N: return ZF = 1
ENDIF	;CLV7VGA
	ret

IFDEF CLV7VGA
; Video 7 extensions virtual input
VO_VI_Seq_V7:
	or	cl,cl				    ; Q: V7 extension register?
	jns	short VO_VI_Seq_NoOEM		    ;	N: not handled

	mov	al, [edi.VDD_Stt.V_Extend][ecx-80H]   ; get virtual value
	cmp	cl,083h 			    ; Q: Attr index register
	jnz	SHORT VO_VI_Seq_Done		    ;	N: Go return
	mov	al,[edi.VDD_Stt.A_Indx] 	    ;	Y: return index value
	xor	al,fVAI_Indx			    ; reverse meaning of bit
VO_VI_Seq_Done:
	test	ecx,ecx 			    ; ZF = 0 (handled here)
	ret
ENDIF	;CLV7VGA

IFDEF TTVGA
; Trident TVGA extensions virtual input
VO_VI_Seq_TVGA:
	cmp	cl, 0Ah
	jnz	short @f
	mov	al, 0A5h		; For BIOS to aviod save/restore MAP3
	jmp	short VO_VI_Seq_Done
@@:
	cmp	cl, 0Bh
	jb	short VO_VI_Seq_NoOEM
public VI_TVGA_3C5	
VI_TVGA_3C5:
	jnz	short @f
	mov	[edi.VDD_Stt.TVGA_3C5_B], TVGA_3C5_B_RdMode
	mov	al, [edi.VDD_Stt.TVGA_3C5_B_v]
	jmp	short VO_VI_Seq_Done
@@:
	cmp	cl, 0Dh
	jnz	short @f
	mov	al, [edi.VDD_Stt.TVGA_3C5_D1]
	cmp	[edi.VDD_Stt.TVGA_3C5_B], TVGA_3C5_B_RdMode
	jz	short VO_VI_Seq_Done
	mov	al, [edi.VDD_Stt.TVGA_3C5_D0]
	jmp	short VO_VI_Seq_Done
@@:
	cmp	cl, 0Eh
	jnz	short VIOT_VI_Seq_Ret
	mov	al, [edi.VDD_Stt.TVGA_3C5_E1]
	cmp	[edi.VDD_Stt.TVGA_3C5_B], TVGA_3C5_B_RdMode
	jz	short VO_VI_Seq_Done
	mov	al, [edi.VDD_Stt.TVGA_3C5_E0]
	jmp	short VO_VI_Seq_Done

ENDIF ; TTVGA

VO_VI_Seq_NoOEM:
	cmp	eax,eax 			    ; ZF = 1 (not handled)

VIOT_VI_Seq_Ret:
	ret

EndProc VDD_OEM_VI_Seq

;******************************************************************************
;VDD_OEM_PO_Grp
;
;DESCRIPTION: Handles OEM variations on physical output to Graphics controller.
;	The VM is owner of the CRTC state and the MemC state.
;
;ENTRY: EBX = VM handle
;	AL = BYTE to output to port.
;	EDX = port address for I/O.
;	ECX = Sequencer index register
;	Carry flag clear, Zero flag set
;
;EXIT:	AL = BYTE to output to port
;	If Carry flag set, don't do output
;	If Zero flag clear skip normal processing, just do output
;
;USES:	Flags, AL, ESI
;
;==============================================================================
BeginProc VDD_OEM_PO_Grp, High_Freq, PUBLIC
IFDEF   CTVGA
	pushfd
	cmp	cl,xG_CTCtl			    ; Q: CTVGA control reg?
	jne	SHORT VO_PO_Grp00		    ;	N: continue
	mov	cl,09				    ;	Y: Index is 9 in struc
VO_PO_Grp00:
	popfd
ENDIF	;CTVGA
IFDEF	PVGA
	TestMem [edi.VDD_TFlags],fVT_PVGA		; Q: possible PVGA?
	jnz	SHORT VO_PO_Grp_PVGA		    ;	Y: check for extensions
ENDIF	;PVGA
IFDEF NEWCLVGA
	TestMem [edi.VDD_TFlags],fVT_NEWCLVGA       ; Q: possible New Cirrus?
	jnz	SHORT VO_PO_Grp_NewCLVGA	    ;	Y: check for extensions
ENDIF	;NEWCLVGA
VO_PO_Grp_Not_OEM:
	cmp	eax, eax			    ; Return, CF=0, ZF=1
	ret

IFDEF NEWCLVGA
VO_PO_Grp_NewCLVGA:
        cmp     cl,08
        jbe     VO_PO_Grp_Not_OEM
        cmp     cl,0Ah
        jnz     short VO_PO_Grp_NewCLVGA_005
        cmp     al,0ECh
	jnz	short VO_PO_Grp_NewCLVGA_001
	mov     [edi.VDD_Stt.V_Extend.0Ah],1    ; set enable extension value
VO_PO_Grp_NewCLVGA_001:
        cmp     al,0CEh                         ; if not EC or CE, leave alone
	jnz	short VO_PO_Grp_NewCLVGA_005
	mov     [edi.VDD_Stt.V_Extend.0Ah],0    ; set disable extension value
VO_PO_Grp_NewCLVGA_005:         
	or	eax,eax         ; CY clear, ZR clear, means do output
        ret
ENDIF ;NEWCLVGA

IFDEF	PVGA
; Check for PVGA lock unlock extensions
VO_PO_Grp_PVGA:
	push	eax
	cmp	cl,5				    ; Q: Lock/Unlock?
	jnz	SHORT VO_PO_Grp_PVGA03		    ;	N: continue
	and	eax,7
	xor	al,5				    ; Q: Unlocking PVGA?
	jnz	SHORT VO_PO_Grp_PVGA01		    ;	N: it is locked
	SetFlag [edi.VDD_Flags],fVDD_PVGA_Ena	    ;	Y: It is enabled
	jmp	SHORT VO_PO_Grp_PVGA03
VO_PO_Grp_PVGA01:
	ClrFlag [edi.VDD_Flags], fVDD_PVGA_Ena
VO_PO_Grp_PVGA03:
	pop	eax
ENDIF	;PVGA
	cmp	eax,eax
	ret					    ; Return, CF=0, ZF=1

EndProc VDD_OEM_PO_Grp

;******************************************************************************
;VDD_OEM_VO_Grp
;
;DESCRIPTION: Handles OEM variations on physical output to Graphics controller.
;	The VM is not owner of the CRTC state, but might be owner of MemC state.
;
;ENTRY: EBX = VM handle
;	AL = BYTE to output to port.
;	EDX = port address for I/O.
;	ECX = Sequencer index register
;	Carry flag clear, Zero flag set
;
;EXIT:	AL = BYTE to output to port
;	If Carry flag set, do output
;	If Zero flag clear skip normal processing, just exit
;
;USES:	Flags, AL, ESI
;
;==============================================================================
BeginProc VDD_OEM_VO_Grp, High_Freq, PUBLIC

IFDEF   CTVGA
	pushfd
        cmp     cl,xG_CTCtl
	jne	SHORT VO_VO_Grp00
	mov	cl,09				    ; Grp F7 reg's index is 09h
VO_VO_Grp00:
	popfd
ENDIF	;CTVGA

IFDEF NEWCLVGA
	TestMem [edi.VDD_TFlags],<fVT_NEWCLVGA>     ; Q: New Cirrus Logic?
	jnz	SHORT VO_VO_Grp_NewCLVGA	    ;	Y: check for extensions
						    ;	N: return CF = 0, ZF = 1
ENDIF	;NEWCLVGA

VO_VO_Grp_Not_OEM:
	cmp	eax,eax                         ; CF=0, ZF=1; do normal proc
	ret

VO_VO_Grp_IgnoreOEM:
	or	ebx,ebx 			    ; CF=0, ZF=0; ingore output
	ret


IFDEF NEWCLVGA
;
VO_VO_Grp_NewCLVGA:
        cmp     cl,08h                          ; Q: regular Grp reg?
        jbe     VO_VO_Grp_Not_OEM               ; Y: ignore here
        cmp     cl,0Ah                          ; N: Q: extension OPEN/CLOSE
	jz	short VO_VO_Grp_NCL_EnExt	    ;	 Y: special code
	cmp	[edi.VDD_Stt.V_Extend.0Ah],1 	    ; Q: Ext. enabled?
	jne	SHORT VO_VO_Grp_IgnoreOEM	    ;	N: ignore the value
; the following is BS cause the storage data struct
; had to be split 
        cmp     cl,MAX_V_Extend
	ja	short VO_VO_UseC_Extension
	mov     [edi.VDD_Stt.V_Extend][ecx],al	    ; Store Ext. Value
	jmp	SHORT VO_VO_Grp_NewCLVGA_005       ; i/o taken care of

VO_VO_UseC_Extension:
        cmp     cl,MAX_C_Extension
        ja      VO_VO_Grp_IgnoreOEM      
	mov     [edi.VDD_Stt.C_Extension][ecx-MIN_C_Extension],al ; Store Ext. Value
	jmp	SHORT VO_VO_Grp_NewCLVGA_005       ; i/o taken care of

VO_VO_Grp_NCL_EnExt:
        cmp     al,0ECh
	jnz	short VO_PO_Grp_NewCLVGA_001
	mov     [edi.VDD_Stt.V_Extend.0Ah],1    ; set enable extension value
VO_VO_Grp_NewCLVGA_001:
        cmp     al,0CEh                         ; if not EC or CE, leave alone
	jnz	short VO_PO_Grp_NewCLVGA_005
	mov     [edi.VDD_Stt.V_Extend.0Ah],0    ; set disable extension value
VO_VO_Grp_NewCLVGA_005:         
	cmp	eax,eax
        ret
ENDIF	;NEWCLVGA

EndProc VDD_OEM_VO_Grp

;******************************************************************************
;VDD_OEM_VI_Grp
;
;DESCRIPTION: Handles OEM variations on virtual input from Graphics controller.
;	The VM is not owner of both the MemC and CRTC state but may be owner
;	of one.
;
;ENTRY: EBX = VM handle
;	EDX = port address for I/O.
;	ECX = Sequencer index register
;	Zero flag set
;
;EXIT:	If Zero flag clear, AL = input byte, else do normal processing
;
;USES:	Flags, AL, ESI
;
;==============================================================================
BeginProc VDD_OEM_VI_Grp, High_Freq, PUBLIC

IFDEF NEWCLVGA
	TestMem [edi.VDD_TFlags],<fVT_NEWCLVGA>     ; Q: New Cirrus Logic?
	jnz	SHORT VO_VI_Grp_NewCLVGA	    ;	Y: check for extensions
ENDIF	; NEWCLVGA

VO_VI_Grp_IgnoreOEM:
	cmp	eax,eax 			    ;	N: ZF = 1 (not handled)
	ret

IFDEF NEWCLVGA
VO_VI_Grp_NewCLVGA:
        cmp     cl,8
        jbe     short VO_VI_Grp_IgnoreOEM
        cmp     cl,MAX_V_Extend         ; overflow check on data structure
	ja	short VO_VI_UseC_Extension
	mov	al, [edi.VDD_Stt.V_Extend][ecx]         ; get virtual value
	test	ecx,ecx 			    ; ZF = 0 (handled here)
        ret

VO_VI_UseC_Extension:
        cmp     cl,MAX_C_Extension      ; overflow check on data structure
        jae     short VO_VI_Grp_IgnoreOEM
	mov	al, [edi.VDD_Stt.C_Extension][ecx-MIN_C_Extension]; get virtual value
	test	ecx,ecx 			    ; ZF = 0 (handled here)
        ret
ENDIF	;NEWCLVGA

EndProc VDD_OEM_VI_Grp

IFDEF Handle_VGAEnable
;******************************************************************************
;VDD_OEM_Get_VGAEnaPort
;
;DESCRIPTION: If 3C3 is not the correct port, return correct port in DX.
;
;ENTRY: EBX = VM handle
;	EDI -> VDD CB data
;	EDX = VGA enable port address for I/O (3C3)
;	AL = VGA Enable port value
;
;EXIT:	If Carry Flag set, ignore VGA enable port
;	    else DX = VGA enable port, AL = value
;
;USES:	Flags, AL, EDX
;
;==============================================================================
BeginProc VDD_OEM_Get_VGAEnaPort

	mov	dx,pVGAEna
IFDEF	TLVGA
; Tseng labs has video subsystem enable on two diff ports depending
;	on value in feature control.  Also has another bit to worry about.

	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jz	SHORT VRI_NotTLEnaRd
%OUT Why is checking the Feature control value not valid for Tseng Labs?
;;	push	eax
;;	mov	al, [esi.VDD_Stt.V_Feat]
;;	and	al,3
;;	cmp	al,3
;;	pop	eax
;;	jnz	SHORT VRI_NotTLEnaRd
	mov	dx,46E8h			; Other VGA Enable port
VRI_NotTLEnaRd:
ENDIF	; TLVGA
	ret
EndProc VDD_OEM_Get_VGAEnaPort
ENDIF	;Handle_VGAEnable

;******************************************************************************
;VDD_OEM_Adjust_Screen_Start
;
;DESCRIPTION: Adjust screen start value taken from CRTC to correct CPU memory
;	offset.
;
;ENTRY: EAX = Screen start offset, Carry Flag cleared
;	EBX = VM handle
;	EDI -> VDD CB data
;
;EXIT:	EAX = adjusted screen start
;	Carry Flag set if normal VGA adjust is not to be applied to value in EAX
;
;USES:	Flags, AL, ESI
;
;==============================================================================
BeginProc VDD_OEM_Adjust_Screen_Start

	ret
EndProc VDD_OEM_Adjust_Screen_Start

;******************************************************************************
;VDD_OEM_Adjust_Cursor
;
;DESCRIPTION: Adjust cursor start and end scan line based on hardware
;	idiosyncracies.
;
;ENTRY: EAX = cursor start line
;	ECX = cursor end line
;	EBX = VM handle
;	EDI -> VDD CB data
;
;EXIT:	IF carry flag set, cursor not visible (EAX, ECX undefined), else:
;	    EAX = adjusted cursor start line
;	    ECX = adjusted cursor end line
;
;USES:	Flags, EAX, ECX
;
;==============================================================================
BeginProc VDD_OEM_Adjust_Cursor

IFDEF CLVGA
;----------------------------------------------------------------------------
;	The following mask has been modified to support a cursor for text
;	modes using a 9x19 font. This font is used on 480 line flat panel
;       displays using Cirrus parts to expand 25 line text modes from
;       400 lines to 475 lines to fill as much of the panel as possible.
;----------------------------------------------------------------------------
	and	ch,1Fh				    ; for expanded cursor
	TestMem [edi.VDD_TFlags],fVT_CLVGA		; Q: Cirrus Logic?
	jnz	SHORT VOAC_1			    ;	Y: don't mask further
ENDIF
	and	ch,0Fh
VOAC_1:
	cmp	al,ch				    ; Q: start beyond max?
	ja	SHORT VOAC_None 		    ;	Y: set to null cursor
VOAC_2:
	cmp	al,cl				    ; Q: start = end?
	jnz	SHORT VOAC_3			    ;	N: continue
	inc	cl				    ;	Y: one line cursor
VOAC_3:
	or	cl,cl				    ; Q: is end at 0
	jnz	SHORT VOAC_4			    ;	N: continue
	mov	cl,ch				    ;	Y: make end max+1
	inc	cl
VOAC_4:
	cmp	al,cl				    ; Q: start before end?
	jb	SHORT VOAC_4a			    ;	Y: save values
	xchg	al,cl				    ;	N: No split crsr support
VOAC_4a:
	cmp	al,ch				    ; Q: start beyond max?
	jbe	SHORT VOAC_CType		    ;	N: Good value
	mov	cl,ch				    ;	Y: Give VM big block
	inc	cl
	xor	al,al
VOAC_CType:

; more special code to detect LCD expanded cursor
IFDEF CLVGA
	TestMem [edi.VDD_TFlags],fVT_CLVGA		; Q: Cirrus Logic?
	jz	SHORT notExpandedCursor 	    ;	N: Nothing further
	cmp	ch,12h
	jne	short notExpandedCursor 	    ; jump if not expanded

	cmp	ax,0FH				    ; check for expanded cursor
	jb	short notExpandedCursor 	    ; jump if not expanded
	cmp	ax,11H				    ; check for expanded cursor
	ja	short notExpandedCursor 	    ; jump if not expanded

	cmp	cl,10H
	jb      short notExpandedCursor
	cmp	cl,12H
	ja      short notExpandedCursor

	mov     ax,0dH
	mov     cl,0eH
notExpandedCursor:
ENDIF
	clc
	ret
VOAC_None:
	stc
	ret
EndProc VDD_OEM_Adjust_Cursor

IFDEF	PVGA
;==============================================================================
; PVGA_Adjust_Page_Mode_Regs
;	Adjust page mode bit #2 in 3x4.2E and text/graphic bit #0 
;	in 3C0.10 for WDC90C00 and above for 132-column text modes
;
;	Since Windows 3.1 VDD restore the registers for Windows screen
;	before saving the font plane when toggle from DOS full screen
;	back to Windows.  The above 2 bits have been set to be in the
;	graphic mode state.  We have to turn on the Page mode bit in reg
;	3x4.2E and clear text/graphic bit in 3C0.10 before the font can
;	be visible and readable.  Restore these 2 bits to the previous
;	whatever state after saving the font.  In fact, just clear the
;	page mode bit and set graphic bit after the font is saved.
;	
; Entry Conditions:
;	EDI points to the VM control block
;
; Exit Conditions:
;	No cpu registers modified
;
; AUTHOR: C. Chiang
;==============================================================================
PUBLIC VDD_OEM_PVGA_Adjust_Page_Mode_Regs
BeginProc VDD_OEM_PVGA_Adjust_Page_Mode_Regs

	TestMem [edi.VDD_TFlags],fVT_PVGA   ; PVGA controller?
	jz	SHORT PVGAAPMR_Exit	    ; no - don't do this

	pushad

;cc	call	VDD_State_Get_Mode
;cc	cmp	ax, 54h
;cc	jb	not_132_00
;cc	cmp	ax, 57h
;cc	jg	not_132_00

	cmp	byte ptr [edi.VDD_Stt.C_HDisp], 83h    ;Q: modes 54h - 57h
	jnz	short not_132_00
	
        mov     edx,3cch
        in      al,dx
        IO_Delay
        test    al,1
        mov     dl,0d4h
        jnz     SHORT @F
        mov     dl,0b4h
@@:
	push	edx			; save 3x4
	in	al, dx
	push	eax			; save 3x4 index

; test extended register 2Ah to see if 3x4.29 is lock or unlock state
; if unlock - set it to unlock state (85h) when done, else set to (80h)
	mov	al, 2Ah
	out	dx, al
	inc	edx
	in	al, dx
	mov	bl, al
	not	al
	out	dx, al
	jmp	$+2
	in	al, dx
	cmp	al, bl
	mov	al, 0		; it is locked
	je	SHORT @F
	mov	al, 85h		; readable and writable
@@:
	mov	cl, al		; save lock/unlock state

	mov	al, bl
	out	dx, al		; restore 2Ah
	dec	edx

; use 3x4.29 scratch bit #4 as the 132-column mode flag and set it
; this register only exist on WDC 1B and above
;;	mov	al, 29h
;;	out	dx, al
;;	mov	al, 95h
;;	inc	edx
;;	out	dx, al
;;	dec	edx

; Reset 3d4.2e bit #2 to 1 (page mode) for WDC 132-column text modes
; When comes here, the first time the bit must be 0 since it is already
; in graphic mode (Windows screen).  Use XOR to toggle will be fine.
	mov	al, 2eh
	out	dx, al
	inc	edx
	in	al, dx			
	xor	al, 4			; turn on page mode bit
	out	dx, al

; 3C0.10 bit #0 must be 0 for WDC 132-column text mode before reading font
; When comes here, the first time the bit must be 1 since it is already
; in graphic mode (Windows screen).  Use XOR to toggle will be fine.
	add	dx, 5	  		; DX - 3DA
	in	al, dx
	mov	dx, 3c0h
	in	al, dx
	push	eax			; save 3C0 index

 	mov	al, 10h
	out	dx, al
	inc	edx
	in	al, dx				; read 3c1

	xor	al, 1			; zero bit #0 for paradise 132-column
	dec	edx
	out	dx, al

	pop	eax
	out	dx, al 			; restore 3C0 index
	pop	eax   			; restore 3x4 index
	pop	edx			; restore 3x4 base address
	push	eax			; save 3x4 index again
	or	cl, 10h			; set bit #4 scratch bit for 132-column
	mov	ah, cl
	mov	al, 29h			; set 3x4.29 to previous state
	out	dx, ax			; whatever is lock/unlock
	pop	eax
	out	dx, al

not_132_00:
	popad

PVGAAPMR_Exit:
	ret

EndProc VDD_OEM_PVGA_Adjust_Page_Mode_Regs

;==============================================================================
; PVGA_Adjust_Page_Mode_X_Regs
;	Adjust page mode bit #2 in 3x4.2E and text/graphic bit #0 
;	in 3C0.10 for WDC90C00 and above for 132-column text modes
;
;	Since Windows 3.1 VDD restore the registers for Windows screen
;	before saving the font plane when toggle from DOS full screen
;	back to Windows.  The above 2 bits have been set to be in the
;	graphic mode state.  We have to turn on the Page mode bit in reg
;	3x4.2E and clear text/graphic bit in 3C0.10 before the font can
;	be visible and readable.  Restore these 2 bits to the previous
;	whatever state after saving the font.  In fact, just clear the
;	page mode bit and set graphic bit after the font is saved.
;	
; Entry Conditions:
;	EDI points to the VM control block
;
; Exit Conditions:
;	No cpu registers modified
;
; AUTHOR: Chung-I Chiang  Western Digital Corp.
;==============================================================================
PUBLIC VDD_OEM_PVGA_Adjust_Page_Mode_X_Regs
BeginProc VDD_OEM_PVGA_Adjust_Page_Mode_X_Regs

	TestMem [edi.VDD_TFlags],fVT_PVGA   ; PVGA controller?
	jz	SHORT X_PVGAAPMR_Exit	    ; no - don't do this

	pushad

        mov     edx,3cch
        in      al,dx
        IO_Delay
        test    al,1
        mov     dl,0d4h
        jnz     SHORT @F
        mov     dl,0b4h
@@:
	push	edx			; save 3x4
	in	al, dx
	push	eax			; save 3x4 index

	mov	al, 29h
	out	dx, al
	inc	edx
	in	al, dx
	test	al, 10h			; check bit #4 - 132-column?
	jz	short APMX_exit		; N: exit
	push	eax			; Y: Check if WDC 1A board?
	mov	al, 085h		; 	 - 3x4.29.05 exits?
 	out	dx, al			; 		N: exit
	jmp	$+2
	in	al, dx
	cmp	al, 085h
	pop	eax
	out	dx, al			; restore 3x4.29 no matter what
	jnz	short APMX_exit
	dec	edx

; Reset 3d4.2e bit #2 to 1 (page mode) for WDC 132-column text modes
; When comes here, the first time the bit must be 0 since it is already
; in graphic mode (Windows screen).  Use XOR to toggle will be fine.
	mov	al, 2eh
	out	dx, al
	inc	edx
	in	al, dx
	xor	al, 4			; toggle page mode bit
	out	dx, al

; 3C0.10 bit #0 must be 0 for WDC 132-column text mode before reading font
; When comes here, the first time the bit must be 1 since it is already
; in graphic mode (Windows screen).  Use XOR to toggle will be fine.
	add	dx, 5	  		; DX - 3DA
	in	al, dx
	mov	dx, 3c0h
	in	al, dx
	push	eax			; save 3C0 index

 	mov	al, 10h
	out	dx, al
	inc	edx
	in	al, dx 			; read 3c1

	xor	al, 1			; toggle bit #0 for paradise 132-column
	dec	edx
	out	dx, al

	pop	eax
	out	dx, al 			; restore 3C0 index
APMX_exit:
	pop	eax   			; restore 3x4 index
	pop	edx			; restore 3x4 base address
	out	dx, al

X_not_132_00:
	popad

X_PVGAAPMR_Exit:
	ret

EndProc VDD_OEM_PVGA_Adjust_Page_Mode_X_Regs


ENDIF	;PVGA


IFDEF NEWCLVGA
;==============================================================================
;
; NewCL_SaveExtRegs
;	Save New Cirrus Logic extended registers.
;
; Entry Conditions:
;	EDI points to the VM control block
;
; Exit Conditions:
;	Cirrus controller extended registers restored.
;	No cpu registers modified
;
; Assumes that the extension registers are already enabled.
; 
;==============================================================================
BeginProc NewCL_SaveExtRegs, PUBLIC
Assert_VDD_ptrs ebx,edi, Pseudo_OK


	TestMem [edi.VDD_TFlags],fVT_NewCLVGA  ; cirrus controller ?
	jz      NewCLSCTLR_Exit            ; no - don't do cirrus save

	push    eax			; save registers
	push	ecx
	push	edx
	push    esi
	push    edi

	mov	edx,pGrpIndx 		; get sequencer index register
	in	al,dx 			; get current index value

	push	eax			; Save sequencer index for restore 
	mov	al,0Ah			; get index of ext enable reg
	IO_Delay
	out	dx,al 		       	; select the enable register
	mov	ah,al			; save index for later
	inc	edx			; point to data port
	IO_Delay
	in	al,dx 			; get the current state of ext enable

	mov     [edi.VDD_Stt.V_Extend.0Ah],al ; save the enable state
	cmp	al,1			; Q: Extensions enabled ?
	mov	al,0ECh                 ;  assume value to re-enable
	jz	short NewCL_SaveExtRegs20 ;  Y: assume was correct
	mov	al,0CEh                 ; get value to disable
NewCL_SaveExtRegs20:
	xchg	al,ah			; Index in AL, extension data in AH
	push	eax			; Save enable extension state
;
	mov	al,0ECh                 ; enable extension value
	out	dx,al 			; Enable extensions
	IO_Delay

	dec	edx			; point to index register
 
        push    edi     

	lea	esi,cs:NewCLExtRegTable+MIN_NewCLTable
	lea	edi, [edi.VDD_Stt.V_Extend.MIN_NewCLTable] ; get extended register area
	mov	ecx,MAX_V_Extend+1-MIN_NewCLTable
	mov	ah,MIN_NewCLTable               ; set for first extension register
NewCL_SaveExtRegs30:
        lods    byte ptr cs:[esi]                ; flag from NewCLExtRegTable
        and     al,al
	jz	short @f
	mov	al,ah 			; place index in al
	out	dx,al 			; select an extension register
	inc	edx			; point to data register
	IO_Delay
	in	al,dx 			; get current value
	dec	edx
	mov     es:[edi],al             ; save in ext. regs. save area
@@:
        inc     edi
	inc	ah			; next index
	loop	NewCL_SaveExtRegs30
;
        pop     edi
        push    edi

	lea	esi,cs:NewCLExtRegTable.MIN_C_Extension
	lea	edi,[edi.VDD_Stt.C_Extension.0]
	mov	ecx,MAX_C_Extension-MIN_C_Extension
	mov	ah,MIN_C_Extension
IIndNewCL_SaveExtRegs30:
        lods    byte ptr cs:[esi]                ; flag from NewCLExtRegTable
        and     al,al
	jz	short @f
	mov	al,ah 			; place index in al
	out	dx,al 			; select an extension register
	inc	edx			; point to data register
	IO_Delay
	in	al,dx 			; get current value
	dec	edx
	mov     es:[edi],al             ; save in ext. regs. save area
@@:
        inc     edi
	inc	ah			; next index
	loop	IIndNewCL_SaveExtRegs30
;
        pop     edi
;
	pop	eax			; get extension enable state
	out     dx,ax                   ; restore the extension state
	IO_Delay 
	pop     eax                     ; get the original index
	out     dx,al                   ; restore index

	pop     edi			; restore registers used   
	pop     esi
	pop     edx
	pop     ecx
	pop     eax

NewCLSCTLR_Exit:
	ret

EndProc  NewCL_SaveExtRegs
;==============================================================================
ENDIF ; NEWCLVGA

IFDEF CLVGA

;==============================================================================
;
; CL_SaveExtRegs
;	Save Cirrus extended registers.
;
; Entry Conditions:
;	EDI points to the VM control block
;
; Exit Conditions:
;	Cirrus controller extended registers restored.
;	No cpu registers modified
;
; Assumes that the extension registers are already enabled.
; 
;==============================================================================
BeginProc CL_SaveExtRegs, PUBLIC
Assert_VDD_ptrs ebx,edi, Pseudo_OK


	TestMem [edi.VDD_TFlags],fVT_CLVGA  ; cirrus controller ?
	jz      CLSCTLR_Exit            ; no - don't do cirrus save

	push    eax			; save registers
	push	ecx
	push	edx
	push    esi
	push    edi

	mov	edx,pSeqIndx 		; get sequencer index register
	in	al,dx 			; get current index value
	IO_Delay
	push	eax			; Save sequencer index for restore 
	mov	al,6			; get index of ext enable reg
	out	dx,al 		       	; select the enable register
	mov	ah,al			; save index for later
	IO_Delay
	inc	edx			; point to data port
	in	al,dx 			; get the current state of ext enable
	mov     [edi.VDD_Stt.S_Rst.6],al ; save the enable state
	cmp	al,1			; Q: Extensions enabled ?
	jnz	short CL_SaveExtRegs10	;  N: Go save value to re-disable
	mov	al,Vid_Enable_Ext_Val	;  Y: Save value to re-enable
	jmp	short CL_SaveExtRegs20	; go save registers

CL_SaveExtRegs10:
	mov	al,Vid_Disable_Ext_Val  ; get value to disable

CL_SaveExtRegs20:
	xchg	al,ah			; Index in AL, extension data in AH
	push	eax			; Save enable extension state
;

	mov	al,Vid_Enable_Ext_Val   ; set to enable extensions
	out	dx,al 			; Enable extensions
	IO_Delay

	dec	edx			; point to index register
      
	mov     esi,edi                 ; save address of VM control block

	lea	edi, [edi.VDD_Stt.V_Extend] ; get extended register area

	mov	ecx,CL_ER_Count		; All extended registers
	mov	ah,CL_ER_Start          ; set for first extension register

; Don't alter CGA/EGA state register save area here. This has been altered
;  to allow us to get to this point.

	mov	al,[edi].CL_ER_State	; get original emulation state
	push	eax			; save for restore later
	mov     al,[edi].CL_ER_WRC      ; get write control reg
	push    eax
;
	push	edi			; save extension regs buffer ptr

CL_SaveExtRegs30:
	test	[VT_Flags],fVT_CLVGA_RevC ; cirrus controller ?
        jnz     short noskipEver
; skip a6,a7, and a8 if not on RevC.    ; DLP 3/1/91
        cmp     ah,0a6h
        jz      short skipit
        cmp     ah,0a7h
        jz      short skipit
        cmp     ah,0a8h
        jz      short skipit
noskipEver:
	mov	al,ah 			; place index in al
	out	dx,al 			; select an extension register
	IO_Delay
	inc	edx			; point to data register
	in	al,dx 			; get current value
	IO_Delay
	dec	edx
skipit:
	stosb				; save in ext. regs. save area
	inc	ah			; next index
	loop	CL_SaveExtRegs30
;
	pop	edi
	pop	eax
	mov	[edi].CL_ER_WRC,al	; Restore write control state
	pop	eax
	mov	[edi].CL_ER_State,al	; Restore adapter state value


	push    edx			; save register
        mov     al,CL_ER_START+CL_ER_LCDCNTLIII ; get shadow register port
	out     dx,al                   ; select the register
	inc     edx                     ; point to data reg
	mov     al,[edi.CL_ER_LCDCNTLIII]  ; get old value
	and     al,0FBH			; turn off shadow bit
	out	dx,al                   ; turn off the shadow
	dec     edx			; point to the index register

        mov     al,CL_ER_START+CL_ER_VRTCEnd	; get crt reg 0-7 protect register port
	out     dx,al                   ; select the register
	inc     edx                     ; point to data reg
	mov     al,[edi].CL_ER_VRTCEnd     ; get old value
	and     al,07FH			; turn off protection bit
	out	dx,al                   ; turn off the shadow

	mov     edx,pMiscRead	; set to get misc output reg
	in      al,dx                   ; get  reg

	mov     edx,pCRTCIndxColr       ; set for CRT registers
	test    al,1                    ; color ?
	jnz     short ShadowGet2        ; yes - jump
	mov     edx,pCRTCIndxMono       ; set for Mono CRT registers
ShadowGet2:
	
	push	edx			; save for later
	mov     al,6			; st for register 6
	out     dx,al 			; select register 6
	inc     edx                     ; point to data reg
	in      al,dx                   ; read shadow value
	mov     [edi].CL_ShadowCRT6,al  ; save the value
	dec     edx                     ; point to index
	
	mov     al,7			; st for register 6
	out     dx,al 			; select register 6
	inc     edx                     ; point to data reg
	in      al,dx                   ; read shadow value

	mov     al,1FH			; kludge for chip bug

	mov     [edi].CL_ShadowCRT7,al  ; save the value
	dec     edx                     ; point to index

	mov     ah,al			; save value in ah
	mov     al,7			; set for register 7
	out     dx,ax                   ; restore crt reg 7

	mov	edx,pSeqIndx
        mov     al,CL_ER_START+CL_ER_LCDCNTLIII	; get shadow register port
	out     dx,al                   ; select the register
	inc     edx                     ; point to data reg
	mov     al,[edi].CL_ER_LCDCNTLIII  ; get old value
	out	dx,al                   ; turn off the shadow

	pop	edx			; get crt reg port
	mov     al,[edi].CL_ER_STATE	; get the state
	test    al,3                    ; 6845 on ?
	jnz     short CL_SaveExtRegs40  ; yes - don't output fake values


	mov	al,6                    ; set to restore fake values
	out     dx,al                   ; select reg 6
	inc     edx                     ; point to data port
	mov     al,[esi].VDD_Stt.CRTC.C_VTotal ; get saved value
	out     dx,al                   ; restore the fake value
	dec     edx                     ; point to index reg

	mov	al,7                    ; set to restore fake values
	out     dx,al                   ; select reg 6
	inc     edx                     ; point to data port
	mov     al,[esi].VDD_Stt.CRTC.C_Ovflw ; get saved value
	out     dx,al                   ; restore the fake value

CL_SaveExtRegs40:
	mov	edx,pSeqIndx
	mov     al,CL_ER_START+CL_ER_VRTCEnd	; get crt protection register port
	out     dx,al                   ; select the register
	inc     edx                     ; point to data reg
	mov     al,[edi].CL_ER_VRTCEnd  	; get old value
	out	dx,al                   ; restore protection

	pop     edx                     ; restore sequencer index

	pop	eax			; get extension enable state
	out     dx,ax                   ; restore the extension state
	IO_Delay 
	pop     eax                     ; get the original index
	out     dx,al                   ; restore index

	pop     edi			; restore registers used   
	pop     esi
	pop     edx
	pop     ecx
	pop     eax

CLSCTLR_Exit:
	ret

EndProc  CL_SaveExtRegs
ENDIF


IFDEF TLVGA
;******************************************************************************
;
;   VDD_OEM_TLVGA_Set_Graphics
;
;   DESCRIPTION:    Force Tseng Labs chip sets into graphics mode by setting
;		    bit 0 in the Graphics Controller Miscellaneous register,
;		    in order to read the text mode font ram (ET3000 only) or
;		    256 color memory, since this is a restriction on those chip
;		    sets.
;
;   ENTRY:	    none
;
;   EXIT:	    AL = original value of Graphics Controller Misc register
;
;   USES:	    EAX, Flags
;
;==============================================================================
BeginProc VDD_OEM_TLVGA_Set_Graphics

	push	edx
;   Because of a bug in the Tseng Labs chip set, we must go into graphics mode
;   in order to read the FONT ram or 256 color memory
	mov	edx, pGrpIndx
	mov	al, 6
	out	dx, al
	IO_Delay
	inc	dl
	in	al, dx
	mov	ah, al
	mov	al, 05h 		; enable graphics mode and 64K at A000
	out	dx, al
	IO_Delay
	dec	dl
	movzx	eax, ah
	pop	edx
	ret

EndProc VDD_OEM_TLVGA_Set_Graphics


;******************************************************************************
;
;   VDD_OEM_TLVGA_Reset_Graphics
;
;   DESCRIPTION:    Restore bit 0 in the Graphics Controller Miscellaneous
;		    register to its original value which was modified by a
;		    previous call to VDD_OEM_TLVGA_Set_Graphics.
;
;   ENTRY:	    AL = original value of Graphics Controller Misc register
;
;   EXIT:	    none
;
;   USES:	    EAX, Flags
;
;==============================================================================
BeginProc VDD_OEM_TLVGA_Reset_Graphics

	push	edx
	mov	edx, pGrpIndx
	mov	ah, al
	mov	al, 6
	out	dx, al
	IO_Delay
	inc	dl
	mov	al, ah
	out	dx, al
	pop	edx
	ret

EndProc VDD_OEM_TLVGA_Reset_Graphics
ENDIF


IF 0	    ; Too much code for general VGA VDD - machine speed specific!
ifdef TLVGA

procs	proc	near

wait_vtrace:  ;passed DX=Input Status Reg 1 port
	;wait for vert retrace (at beg); ret AX=no. loops till happened
	push	ebx
	sub	ebx,ebx
	;loop until not vert retrace:
wvt_lp1:
	mov	al,16		;(have inner loop so delay count not too big)
wvt_lp1a:
	push	eax
	pop	eax
	dec	al
	jnz	short wvt_lp1a		;inner loop
	inc	bx
	jz	short wvt_8
	in	al,dx
	test	al,8	;VERTICAL_RETRACE_BIT
	jnz	short wvt_lp1
;
	;loop until vert retrace:
wvt_lp2:
	mov	al,16		;(have inner loop so delay count not too big)
wvt_lp2a:
	push	eax
	pop	eax
	dec	al
	jnz	short wvt_lp2a		;inner loop
	inc	bx
	jz	short wvt_8
	in	al,dx
	test	al,8	;VERTICAL_RETRACE_BIT
	jz	short wvt_lp2
;
	inc	bx
wvt_8:
	dec	bx	;set=FFFF if overflowed
	mov	eax,ebx
	pop	ebx
	ret

time_vtraces:	;ret AX=loop count for complete vert period (bet 2 retraces)
	push	edx
	pushfd
	mov	dx,03DAh	;INPUT_STATUS_1_C
	cli
	call	wait_vtrace		;make sure starting at beg
	call	wait_vtrace		;get count
	popfd
	pop	edx
	ret

tst_45_65:
	;test if have 45 or 65 MHz clock installed; ret AL=0 if 45, 1 if 65
	;also ret AH=0 if interlaced is set, =1 if not set
	;assume mode 37 has just been set (clock=45 or 65 MHz, color addrs)
	;save regs<>EAX and restore video regs
	push	ebx
	push	ecx
	push	edx
	call	time_vtraces
	mov	ecx,eax			;CX=loop cnt bet retraces at 45/65 MHz
;
	call	key_on
	call	unprotect
;
	mov	dx,pMisc
	in	al,dx
	IO_Delay
	mov	bh,al			;save orig MiscOut reg in BH
	and	al,0F3h
	mov	dl,pMisc and 0FFh
	out	dx,al			;set MiscOut for clk=0, assume=25 MHz
;
	mov	dl,pCRTCIndxColr and 0FFh
	mov	ah,024h 	;CRTC_COMPAT_CTRL
	call	get_internal_reg
	push	eax		;save orig CRTC 24 val
	and	al,0Ch
	call	set_internal_reg	;set CRTC 34 for no XL, not 6845, CS2=0
					;(XL, 6845 should be off anyway)
	call	time_vtraces
	;AX=loop count bet retraces at 25 MHz, CX=cnt at 45/65 MHz
;
	;say 45 MHz if CX>=(AX/2) else 65 MHz  (set BL=0 or 1)
	mov	bl,0
	shr	ax,1
	cmp	cx,ax
	jae	short t4565_2
	mov	bl,1		;65 MHz
t4565_2:
	;set CS1=1/0 corres to whether want 16-bit read/write enabled or not
	; prior to setting CS2 (in CRTC 24) because if CS2 moves from 0 to 1
	; some ET3000 boards will set 16-bit enabled/disabled based on CS1
	; (assume bit 6 of 0:489 says disable 16-bit if 1):
	mov	dl,pMisc and 0FFh
	mov	al,bh
	and	al,0F7h
	BEGIN_Touch_1st_Meg
	test	byte ptr ds:[0489h],040h	;chk if 16-bit enabled (NZ=>no)
	END_Touch_1st_Meg
	jnz	short t4565_4
	or	al,8				;set CS1 bit approp
t4565_4:
	out	dx,al			;set MiscOut
;
	mov	dl,pCRTCIndxColr and 0FFh
	pop	eax			;AH=024, AL=orig CRTC 24 val
	call	set_internal_reg	;restore CRTC 24
	mov	dl,pMisc and 0FFh
	mov	al,bh
	out	dx,al			;restore orig MiscOut
;
	;chk if interlace is set:
	mov	dl,pCRTCIndxColr and 0FFh
	mov	ah,025h 	;CRTC_OVERFLOW_HIGH
	call	get_internal_reg
	not	al
	rol	al,1
	and	al,1
	mov	ah,al		;AH=0 if interlace bit=1, else=1
;
	mov	al,bl		;AL=0 if 45 MHz, 1 if 65 MHz
	call	protect
	call	key_off
	pop	edx
	pop	ecx
	pop	ebx
	ret


mode37i_fix_tab	label	byte
	db	3, 080h		;TS 1, CRTC 25
;
	db	04Ah, 03Fh, 03Fh, 00Eh, 044h, 0Eh	;CRTC 0-18
	db	097h, 01Fh, 00h, 040h, 00h, 00h
	db	00h, 00h, 00h, 00h, 080h, 084h
	db	07Fh, 020h, 00h, 07Fh, 098h, 0C3h
	db	0FFh

mode37ni_fix_tab label	byte
	db	1, 0		;TS 1, CRTC 25
;
	db	04Eh, 03Fh, 040h, 011h, 044h, 00Fh	;CRTC 0-18
	db	026h, 0FDh, 000h, 060h, 000h, 000h
	db	000h, 000h, 000h, 000h, 002h, 084h
	db	0FFh, 020h, 000h, 004h, 023h, 0C3h
	db	0ffh

fix_mode37:	;based on AL=0 or 1, fix parms for interlaced or non-interlaced
	; mode 37; set CRTC 0-18, seq 1 (needs key on), CRTC 25
	;preserve all regs
	push	eax
	push	ebx
	push	ecx
	push	edx
	call	key_on
	call	unprotect
;
	mov	ebx,offset32 mode37i_fix_tab
	or	al,al
	je	short fm37_2
	mov	ebx,offset32 mode37ni_fix_tab
fm37_2:
	;EBX pts to: value for TS 1, value for CRTC 25, values for CRTC 0-18
	mov	dx,pSeqIndx
	mov	ah,1
	mov	al,cs:[ebx]
	call	set_internal_reg	;set TS 1
	inc	ebx
	mov	dl,pCRTCIndxColr and 0FFh
	mov	ah,025h		;CRTC_OVERFLOW_HIGH
	mov	al,cs:[ebx]
	call	set_internal_reg	;set CRTC 25
	inc	ebx
	;set CRTC 0-18:
	mov	ah,0
	mov	ecx,019h
fm_lp:
	mov	al,cs:[ebx]
	call	set_internal_reg
	inc	ebx
	inc	ah
	loopd	fm_lp
;
	call	key_off
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	ret

unprotect:	;reset bit 7 of CRTC 11 to unprotect certain regs
	;assume color addrs are set
	;preserve all regs
	push	eax
	push	edx
	mov	dx,pCRTCIndxColr
	mov	ah,011h
	call	get_internal_reg
	and	al,06Fh		;special: reset bit 4 to make sure int off
	call	set_internal_reg
	pop	edx
	pop	eax
	ret

protect:	;set bit 7 of CRTC 11 to protect certain regs
	;assume color addrs are set
	;preserve all regs
	push	eax
	push	edx
	mov	dx,pCRTCIndxColr
	mov	ah,011h
	call	get_internal_reg
	and	al,0EFh		;special: reset bit 4 to make sure int off
	or	al,080h
	call	set_internal_reg
	pop	edx
	pop	eax
	ret

key_on:		;turn "key" on (unprotect); assume color addrs are set
		;preserves all regs
	push	eax
	mov	ax,0A003h
	;
key_on_off_2:	;come here also from key_off
	push	edx
	mov	dx,03BFh	;MONO_CONFIG
	out	dx,al
	IO_Delay
	mov	dl,03D8h and 0FFh	;MODE_C
	mov	al,ah
	out	dx,al
	pop	edx
	pop	eax
	ret
;
key_off:	;turn "key" off (protect); assume color addrs are set
		;leaves MODE reg=029, MONO_CONFIG=1
		;preserves all regs
	push	eax
	mov	ax,02901h
	jmp	short key_on_off_2

get_internal_reg:  ;enter EDX=port, AH=index; ret AL=val (preserve regs<>AL)
	mov	al,ah
	out	dx,al
	IO_Delay
	inc	edx
	in	al,dx
	dec	edx
	ret

set_internal_reg:  ;enter EDX=port, AH=index, AL=val to output (preserve regs)
	xchg	al,ah
	out	dx,ax
	xchg	al,ah
	ret

procs	endp

endif ;TLVGA
ENDIF ;0
;-------------------------------------------------


IFDEF DEBUG
;******************************************************************************
;VDD_OEM_Debug_RegDump
;
;DESCRIPTION: Dump OEM specific registers
;
;ENTRY: EBX = VM handle
;	EDI -> VDD CB data
;
;EXIT:
;
;USES:	All registers except EBX, EDI
;
;==============================================================================
_LDATA SEGMENT
IFDEF V7VGA
szV7Regs       DB  "Video 7 ",0
ENDIF
IFDEF CLVGA
szCLRegs       DB  "Cirrus Logic ",0
ENDIF
IFDEF NEWCLVGA
szNCLRegs      DB  "Cirrus Logic 6410 ",0
ENDIF
IFDEF ATIVGA
szATIVGARegs   DB  "ATI (10-1E) ",0
ENDIF
IFDEF TLVGA
szTLVGARegs    DB  "Tseng Labs segment register ",0
ENDIF
szDump	       DB  "Dump ",0
szESCtoSkip    DB  "OEM regs (ESC to skip)",0Dh,0Ah,0
_LDATA ENDS

BeginProc VDD_OEM_Debug_RegDump

IFDEF V7VGA
	mov	esi,OFFSET32 szV7Regs
	lea	eax,[edi.VDD_Stt.V_Extend]
	mov	ecx,80h
	TestMem [edi.VDD_TFlags],fVT_V7VGA
	jnz	SHORT VRD_Dump
ENDIF
IFDEF CLVGA
	mov	esi,OFFSET32 szCLRegs
	lea	eax,[edi.VDD_Stt.V_Extend]
	mov	ecx,80h
	TestMem [edi.VDD_TFlags],fVT_CLVGA
	jnz	SHORT VRD_Dump
ENDIF
IFDEF NEWCLVGA
	mov	esi,OFFSET32 szNCLRegs
	lea	eax,[edi.VDD_Stt.V_Extend]
	mov	ecx,80h
	TestMem [edi.VDD_TFlags],fVT_NEWCLVGA
	jz	SHORT @f
        call    VRD_Dump
	lea	eax,[edi.VDD_Stt.V_Extend]
	lea	eax,[edi.VDD_Stt.C_Extension]
	mov	ecx,80h
	jmp	short VRD_Dump
@@:
ENDIF
IFDEF ATIVGA
	mov	esi,OFFSET32 szATIVGARegs
	lea	eax,[edi.VDD_Stt.V_Extend+10h]
	mov	ecx,0Fh
	TestMem [edi.VDD_TFlags],fVT_ATIVGA
	jnz	SHORT VRD_Dump
ENDIF
IFDEF TLVGA
	mov	esi,OFFSET32 szTLVGARegs
	lea	eax,[edi.VDD_Stt.V_Extend]
	mov	ecx, 1
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jnz	SHORT VRD_Dump
ENDIF
VRD_Exit:
	ret

VRD_Dump:
	push	eax
	push	esi
	mov	esi,OFFSET32 szDump
	VMMCall Out_Debug_String
	pop	esi
	VMMCall Out_Debug_String
	mov	esi,OFFSET32 szESCtoSkip
	VMMCall Out_Debug_String
	VMMcall In_Debug_Chr
	pop	eax
	jz	VRD_Exit
Trace_Out	"Extended " +
	mov	esi,eax
	call	VDD_Reg_Dump
Trace_Out	" "
	jmp	VRD_Exit
EndProc VDD_OEM_Debug_RegDump
ENDIF

VxD_Code_ENDS

	END
