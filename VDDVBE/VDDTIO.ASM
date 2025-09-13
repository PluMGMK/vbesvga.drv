       TITLE   VDD - Virtual Display Device for EGA   version 3.1
;******************************************************************************
;
; VDDTIO.ASM - Virtual EGA I/O Register emulation
;
;   Author: MDW, RAP
;
;   (C) Copyright MICROSOFT Corp. 1986 - 1991
;
;DESCRIPTION:
;   I/O trapping routines for video device.  When a VM owns both the CRTC
;   state and the MemC state, trapping is usually disabled, allowing the
;   VM direct access to the video hardware.  When the VM with the CRTC state
;   does not have the MemC state, trapping is enabled until first access
;   at which point it regains the MemC state.  At any rate, trapping is
;   always enabled during mode changes in order to catch memory mapping
;   transitions.
;
;******************************************************************************

	.386p

.xlist
	INCLUDE VMM.inc
	INCLUDE OPTTEST.INC
	INCLUDE vdd.inc
	INCLUDE vdd2.inc
	INCLUDE debug.inc
	INCLUDE vdddef.inc
.list

;******************************************************************************
; EXTRN routines
;
VxD_CODE_SEG
EXTRN	VDD_State_Set_MemC_Owner:NEAR

EXTRN	VDD_VM_Mem_Disable:NEAR
EXTRN	VDD_VM_Mem_Adjust_Visible_Pages:NEAR

IFDEF MapMonoError
;
; This seemed like a good idea, but we have too many BIOS'es and other
; software which map 128Kb when they are trying to program something in A0.
; They don't actually touch memory at B0-B7, but we can't detect that.
; So I'm going to remove all of the checking for this case.
;
EXTRN	VDD_Error_MapMono:NEAR
ENDIF

EXTRN	VDD_OEM_PO_Seq:NEAR
IFDEF TTVGA
EXTRN	VDD_OEM_PI_Seq:NEAR			; add for Trident TVGA
ENDIF
EXTRN	VDD_OEM_VO_Seq:NEAR
EXTRN	VDD_OEM_VI_Seq:NEAR
EXTRN	VDD_OEM_PO_Grp:NEAR
EXTRN	VDD_OEM_VO_Grp:NEAR
EXTRN	VDD_OEM_VI_Grp:NEAR
EXTRN	VDD_OEM_In_CRTC:NEAR
EXTRN	VDD_OEM_Out_CRTC:NEAR
EXTRN	VDD_OEM_Enable_Local_Traps:NEAR
EXTRN	VDD_OEM_Disable_Local_Traps:NEAR
IFDEF DEBUG
EXTRN	VDD_State_Schedule_Debug_Event:NEAR
ENDIF
IFDEF VRTCTIMER
EXTRN	VDD_State_Calc_Framerate:NEAR
EXTRN	VDD_Set_VRTC_Time_Out:NEAR
EXTRN	VDD_Int_Clear_VRTC_IRQ:NEAR
ENDIF

VxD_CODE_ENDS


VxD_IDATA_SEG

IFDEF	VGAMONO
Begin_VxD_IO_Table Vid_Mono_IO_Table
	VxD_IO	3BAh,VIOT_Disp		   ; Feature controller/ Status
	VxD_IO	3B4h,VIOT_Disp
	VxD_IO	3B5h,VIOT_Disp		   ; CRT controller registers
End_VxD_IO_Table Vid_Mono_IO_Table
ENDIF

Begin_VxD_IO_Table Vid_IO_Table
	VxD_IO	3C0h,VIOT_Disp
	VxD_IO	3C1h,VIOT_Disp		    ; Attribute controller registers
	VxD_IO	3C2h,VIOT_Disp		    ; Miscellaneous register
	VxD_IO	3C3h,VIOT_Disp
	VxD_IO	3C4h,VIOT_Disp
	VxD_IO	3C5h,VIOT_Disp		    ; Sequencer registers
	VxD_IO	3C6h,VIOT_Disp		    ; COMPAQ special, ignore if bckgrnd
	VxD_IO	3C7h,VIOT_Disp		    ; VGA DAC registers
	VxD_IO	3C8h,VIOT_Disp
	VxD_IO	3C9h,VIOT_Disp
	VxD_IO	3CAh,VIOT_Disp
	VxD_IO	3CBh,VIOT_Disp
	VxD_IO	3CCh,VIOT_Disp		    ; Grx ctrl pos reg,Misc O/P Read Reg
	VxD_IO	3CDh,VIOT_Disp
	VxD_IO	3CEh,VIOT_Disp
	VxD_IO	3CFh,VIOT_Disp		    ; Graphics controller registers
	VxD_IO	3D0h,VIOT_Disp
	VxD_IO	3D1h,VIOT_Disp
	VxD_IO	3D2h,VIOT_Disp
	VxD_IO	3D3h,VIOT_Disp
	VxD_IO	3D4h,VIOT_Disp
	VxD_IO	3D5h,VIOT_Disp		    ; CRT controller registers
	VxD_IO	3D6h,VIOT_Disp
	VxD_IO	3D7h,VIOT_Disp
	VxD_IO	3D8h,VIOT_Disp
	VxD_IO	3D9h,VIOT_Disp
	VxD_IO	3DAh,VIOT_Disp		    ; Feature controller/Status
	VxD_IO	3DBh,VIOT_Disp		    ; Light pen reset
	VxD_IO	3DCh,VIOT_Disp		    ; Light pen set
	VxD_IO	3DDh,VIOT_Disp
	VxD_IO	3DEh,VIOT_Disp
	VxD_IO	3DFh,VIOT_Disp
End_VxD_IO_Table Vid_IO_Table

IFDEF	VGA8514
Begin_VxD_IO_Table Vid_8514_IO_Table
;;;	VxD_IO	  100h, VIOT_8514_Null	    ; POS ports are not 8514 specific
;;;	VxD_IO	  101h, VIOT_8514_Null	    ;	allowing access should not
;;;	VxD_IO	  102h, VIOT_8514_Null	    ;	cause display problems...
	VxD_IO	  2E8h, VIOT_8514_Null
	VxD_IO	  2E9h, VIOT_8514_Null
	VxD_IO	  2EAh, VIOT_8514_Null
	VxD_IO	  2EBh, VIOT_8514_Null
	VxD_IO	  2ECh, VIOT_8514_Null
	VxD_IO	  2EDh, VIOT_8514_Null
	VxD_IO	  6E8h, VIOT_8514_Null
	VxD_IO	  6E9h, VIOT_8514_Null
	VxD_IO	 0AE8h, VIOT_8514_Null
	VxD_IO	 0AE9h, VIOT_8514_Null
	VxD_IO	 0EE8h, VIOT_8514_Null
	VxD_IO	 0EE9h, VIOT_8514_Null
	VxD_IO	 12E8h, VIOT_8514_Null
	VxD_IO	 12E9h, VIOT_8514_Null
	VxD_IO	 16E8h, VIOT_8514_Null
	VxD_IO	 16E9h, VIOT_8514_Null
	VxD_IO	 1AE8h, VIOT_8514_Null
	VxD_IO	 1AE9h, VIOT_8514_Null
	VxD_IO	 1EE8h, VIOT_8514_Null
	VxD_IO	 1EE9h, VIOT_8514_Null
	VxD_IO	 22E8h, VIOT_8514_Null
	VxD_IO	 22E9h, VIOT_8514_Null
	VxD_IO	 42E8h, VIOT_8514_Null
	VxD_IO	 42E9h, VIOT_8514_Null
	VxD_IO	 46E8h, VIOT_8514_Null
	VxD_IO	 46E9h, VIOT_8514_Null
	VxD_IO	 4AE8h, VIOT_8514_Null
	VxD_IO	 4AE9h, VIOT_8514_Null
	VxD_IO	 82E8h, VIOT_8514_Null
	VxD_IO	 82E9h, VIOT_8514_Null
	VxD_IO	 86E8h, VIOT_8514_Null
	VxD_IO	 86E9h, VIOT_8514_Null
	VxD_IO	 8AE8h, VIOT_8514_Null
	VxD_IO	 8AE9h, VIOT_8514_Null
	VxD_IO	 8EE8h, VIOT_8514_Null
	VxD_IO	 8EE9h, VIOT_8514_Null
	VxD_IO	 92E8h, VIOT_8514_Null
	VxD_IO	 92E9h, VIOT_8514_Null
	VxD_IO	 96E8h, VIOT_8514_Null
	VxD_IO	 96E9h, VIOT_8514_Null
	VxD_IO	 9AE8h, VIOT_8514_Null
	VxD_IO	 9AE9h, VIOT_8514_Null
	VxD_IO	 9EE8h, VIOT_8514_Null
	VxD_IO	 9EE9h, VIOT_8514_Null
	VxD_IO	0A2E8h, VIOT_8514_Null
	VxD_IO	0A2E9h, VIOT_8514_Null
	VxD_IO	0A6E8h, VIOT_8514_Null
	VxD_IO	0A6E9h, VIOT_8514_Null
	VxD_IO	0AAE8h, VIOT_8514_Null
	VxD_IO	0AAE9h, VIOT_8514_Null
	VxD_IO	0AEE8h, VIOT_8514_Null
	VxD_IO	0AEE9h, VIOT_8514_Null
	VxD_IO	0B2E8h, VIOT_8514_Null
	VxD_IO	0B2E9h, VIOT_8514_Null
	VxD_IO	0B6E8h, VIOT_8514_Null
	VxD_IO	0B6E9h, VIOT_8514_Null
	VxD_IO	0BAE8h, VIOT_8514_Null
	VxD_IO	0BAE9h, VIOT_8514_Null
	VxD_IO	0BEE8h, VIOT_8514_Null
	VxD_IO	0BEE9h, VIOT_8514_Null
	VxD_IO	0E2E8h, VIOT_8514_Null
	VxD_IO	0E2E9h, VIOT_8514_Null
	;  [1] WD enhanced registers  C. Chiang
        VxD_IO  028E9h, VIOT_8514_Null           ; Dummy read/enable 96E8
;;**    VxD_IO  0BEE9h, VIOT_8514_Null          ; Dummy read/enable 96E8 EISA
						; which has been hooked already
        VxD_IO  036E8h, VIOT_8514_Null           ; EPROM select-AT bus only
        
End_VxD_IO_Table Vid_8514_IO_Table
ENDIF

;*******
; Strings used in Fatal_Exit during initialization only
	EXTRN	VDD_Str_BadIO:BYTE

VxD_IDATA_ENDS


;******************************************************************************
VxD_DATA_SEG

;*******
; EXTRN data
EXTRN	Vid_CB_Off:DWORD
EXTRN	Vid_Flags:DWORD
EXTRN	VT_Flags:DWORD
EXTRN	Vid_CRTC_VM:DWORD
EXTRN	Vid_MemC_VM:DWORD

IFDEF	TLVGA
EXTRN	TL_Switches:BYTE
ENDIF

;*******
; MemC state register masks for bits owned by MemC
;
;   NOTE: the undefined bits are zero in these masks.  This means that when
;	they change, we will ignore them when running VMs in the background.
;	This should not matter.
;
; Table of Sequencer register masks
mSeq_MemC   LABEL BYTE
	DB	0,0,00Fh,0,00Eh
IFDEF	PVGA
; add Western Digital Seq. controller extended register masks - C. Chiang -
mSeq_PVGA   LABEL BYTE
	DB	0,0FFh,0FFh,0FFh,0FFh,0,0,0,0,0,0,0FFh,0FFh,0FFh,0FFh,0FFh
len_mSeq_PVGA	EQU $-mSeq_PVGA
	DB	(SL_Resvd-16) DUP (0)
ELSE
	DB	SL_Resvd DUP (0)
ENDIF	;PVGA
.ERRE ($-mSeq_MemC) EQ S_IMax+1

; Table of Graphics controller register masks
mGrp_MemC   LABEL BYTE
	DB	00Fh,00Fh,00Fh,01Fh,003h,01Bh,00Eh,00Fh,0FFh
; add Western Digital Graphics controller extended register masks - C. Chiang -
IFDEF	PVGA
mGrp_PVGA   LABEL BYTE
	DB	0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
len_mGrp_PVGA	EQU $-mGrp_PVGA
	DB	(GL_Resvd-7) DUP (0)
ELSE
	DB	GL_Resvd DUP (0)
ENDIF	;PVGA
.ERRE ($-mGrp_MemC) EQ G_IMax+1

IFDEF DEBUG
PUBLIC VDD_Force_Trapping
VDD_Force_Trapping  db 0
VDD_Forced_Trap     db 0
ENDIF

	ALIGN 4

;*******
; Mask of CRTC only ports - 3C0, 3C1, 3C6-3C9. 3C4, 3D5
Vid_CRTC_Port	DD  00000000001100000000001111000011b
;

;*******
DispEntry MACRO index, routine
index = ($ - VIOT_Dispatch)
	DD  OFFSET32 routine
ENDM

; Routine addresses for handling I/O traps
VIOT_Dispatch	LABEL DWORD
    DispEntry $ignore, VIOT_Ignore
    DispEntry $3C0,    VIOT_3C0
    DispEntry $3C1,    VIOT_3C1 	; Attribute controller registers
    DispEntry $3C2,    VIOT_3C2 	; Miscellaneous register
    DispEntry $3C4,    VIOT_3C4
    DispEntry $3C5,    VIOT_3C5 	; Sequencer registers
    DispEntry $3C6,    VIOT_3C6 	; COMPAQ special, ignore if bckgrnd
    DispEntry $3C7,    VIOT_3C7 	; VGA DAC registers
    DispEntry $3C8,    VIOT_3C8
    DispEntry $3C9,    VIOT_3C9
    DispEntry $3CA,    VIOT_3CA
    DispEntry $3CC,    VIOT_3CC 	; Grx ctrl pos reg,Misc O/P Read Reg
IFDEF TLVGA
    DispEntry $3CD,    VIOT_3CD
ELSE
    DispEntry $3CD,    VIOT_Ignore
ENDIF
    DispEntry $3CE,    VIOT_3CE
    DispEntry $3CF,    VIOT_3CF 	; Graphics controller registers
    DispEntry $3DB,    VIOT_3DB 	; Light pen reset * set
	      $3DC = $3DB
    DispEntry $3D4,    VIOT_CRTC
    DispEntry $3D5,    VIOT_CRTC	; CRT controller registers
    DispEntry $3DA,    VIOT_CRTC	; Feature controller
    DispEntry $3D4a,   VIOT_3D4
    DispEntry $3D5a,   VIOT_3D5 	; CRT controller registers
    DispEntry $3DAa,   VIOT_3DA 	; Feature controller
$actual = $3D4a - $3D4
.errnz $3D5a - $3D5 - $actual
.errnz $3DAa - $3DA - $actual

VIOT_Index	LABEL BYTE
	db  $3C0    ; 3C0
	db  $3C1    ; 3C1
	db  $3C2    ; 3C2
	db  $ignore ; 3C3
	db  $3C4    ; 3C4
	db  $3C5    ; 3C5
	db  $3C6    ; 3C6
	db  $3C7    ; 3C7
	db  $3C8    ; 3C8
	db  $3C9    ; 3C9
	db  $3CA    ; 3CA
	db  $ignore ; 3CB
	db  $3CC    ; 3CC
	db  $3CD    ; 3CD
	db  $3CE    ; 3CE
	db  $3CF    ; 3CF
	db  $ignore ; 3D0
	db  $ignore ; 3D1
	db  $ignore ; 3D2
	db  $ignore ; 3D3
	db  $3D4    ; 3D4
	db  $3D5    ; 3D5
	db  $ignore ; 3D6
	db  $ignore ; 3D7
	db  $ignore ; 3D8
	db  $ignore ; 3D9
	db  $3DA    ; 3DA
	db  $3DB    ; 3DD
	db  $3DC    ; 3DC
	db  $ignore ; 3DD
	db  $ignore ; 3DE
	db  $ignore ; 3DF
.ERRNZ	($-VIOT_Index)-(3E0h-3C0h)

VxD_DATA_ENDS

VxD_ICODE_SEG

;******************************************************************************
;
;   VDD_TIO_Sys_Critical_Init
;
;   DESCRIPTION:
;
;   ENTRY:
;
;   EXIT:	Carry cleared
;
;   USES:
;
;==============================================================================
BeginProc VDD_TIO_Sys_Critical_Init

IFDEF	VGA8514
;
; Install 8514 I/O trapping routines
;
; globally 8514 I/O ports are always trapped, but we disable trapping in the
; SYS VM, so Windows can have free reign
;
	mov	edi, OFFSET32 Vid_8514_IO_Table ; Table of ports
	VMMCall Install_Mult_IO_Handlers	; Install the port traps
	jc	SHORT VIOSCI_Exit

	movzx	ecx, [edi.VxD_IO_Ports]
	add	edi, SIZE VxD_IOT_Hdr
VIOI_disable_SYS_trapping:
	movzx	edx, [edi.VxD_IO_Port]
	add	edi, SIZE VxD_IO_Struc
	VMMCall Disable_Local_Trapping
	loop	VIOI_disable_SYS_trapping
ENDIF

	clc

VIOSCI_Exit:
	ret

EndProc VDD_TIO_Sys_Critical_Init


;******************************************************************************
; VDD_TIO_Device_Init
;
;DESCRIPTION:
;	Sets up trapping for VDD I/O ports
;
;ENTRY: EBX = SYS VM handle
;	EDI = VDD CB ptr for SYS VM
;
;EXIT:	CF = 0, or Fatal_Error called
;
;USES:	Flags
;
BeginProc VDD_TIO_Device_Init

	pushad
	push	edi

;
; Set initial state for I/O trapping in sys VM
;
	SetFlag [edi.VDD_PIF], <fVidNoTrpTxt+fVidNoTrpLRGrfx+fVidNoTrpHRGrfx>
	bts	[edi.VDD_Flags],bVDD_IOT	; Ports trapped in SYS VM
	mov	[edi.VDD_TrapEnable],-1 	;   All ports trapped
;
; Install I/O trapping routines
;
	mov	edi, OFFSET32 Vid_IO_Table	; Table of ports
	VMMCall Install_Mult_IO_Handlers	; Install the port traps
	jc	VIOI_TrapFailed

IFDEF	VGAMONO
;
; Install mono I/O trapping routines
;
	mov	edi,[esp]
	TestMem [edi.VDD_TFlags],fVT_ResvB0	; Q: Dual display support?
	jnz	SHORT DI_NoMono 		;   Y: Don't support mono modes
	VxDCall VDD2_Get_Version		; Q: 2nd VDD exist?
	jnc	SHORT DI_NoMono 		;   Y: Don't support mono modes
	mov	edi, OFFSET32 Vid_Mono_IO_Table
	VMMCall Install_Mult_IO_Handlers	; Install the port traps
	mov	edi,[esp]
	jnc	short DI_HaveMono		; If successful

; If mono mem is owned by the VDD and we don't have Mono ports trapped, we
;   turn support into dual display support (i.e. mono video mem is global)
	btr	[edi.VDD_TFlags],bVT_Mono	; Q: Mono mem supported?
	jnc	SHORT DI_NoMono 		;   N: No Mono support
Trace_Out "Disabling mono modes support"
	ClrFlag [VT_Flags],fVT_Mono		;   Y: Turn mono support into
	SetFlag [edi.VDD_TFlags],fVT_ResvB0	;	dual display support
	SetFlag [VT_Flags],fVT_ResvB0
DI_NoMono:
	ClrFlag [edi.VDD_TFlags],fVT_MonoPorts	; ELSE	Mono ports not supported
	ClrFlag [VT_Flags],fVT_MonoPorts
	jmp	SHORT DI_MonoDone

; Mono I/O ports trapped
DI_HaveMono:
	SetFlag [VT_Flags],fVT_MonoPorts	; Mono port traps are supported
	SetFlag [edi.VDD_TFlags],fVT_MonoPorts
	bts	[edi.VDD_Flags], bVDD_IOTmono	; Mono ports trapped in SYS VM
	TestMem [edi.VDD_TFlags],fVT_Mono	;Q: VDD handles MONO mem?
	jnz	SHORT DI_MonoDone		;   Y: leave trapping on
	mov	edx, 3B4h			;   N: Turn off mono port traps
	VMMCall Disable_Global_Trapping
	inc	edx				; 3B5
	VMMCall Disable_Global_Trapping
	mov	dl, 0BAh			; 3BA
	VMMCall Disable_Global_Trapping
	btr	[edi.VDD_Flags], bVDD_IOTmono
DI_MonoDone:
ENDIF

IFDEF PVGA
	TestMem [edi.VDD_TFlags],fVT_PVGA	; Q: Western Digital chip?
	jnz	SHORT VIOI_NotPVGA
	cld
	xor	eax,eax 			;   N: zero MemC masks
	mov	ecx,len_mGrp_PVGA
	mov	edi,OFFSET32 mGrp_PVGA
	rep stosb
	mov	ecx,len_mSeq_PVGA
	mov	edi,OFFSET32 mSeq_PVGA
	rep stosb
VIOI_NotPVGA:
ENDIF
	clc					; return with no error

	pop	edi
	popad
	ret

VIOI_TrapFailed:
	; at this point, EDX has the index of a port that couldn't be trapped,
	; so fill it into the error message and print it out.
	mov	al,dl				; fetch two lower digits
	mov	ah,al
	and	ah,0Fh
	shr	al,4

	or	ax,'00'				; convert to decimal numbers
	cmp	ah,'0'+0Ah			; Q: >= 10?
	jb	short @F			;    N: next digit
	add	ah,'A'-'0'+0Ah			;    Y: convert to hex
@@:	cmp	al,'0'+0Ah			; Q: >= 10?
	jb	short @F			;    N: next digit
	add	al,'A'-'0'+0Ah			;    Y: convert to hex
@@:	shl	eax,10h				; move lower digits into upper half (big-endian!)
	
	mov	al,dh				; fetch two upper digits
	mov	ah,al
	and	ah,0Fh
	shr	al,4

	or	ax,'00'				; convert to decimal numbers
	cmp	ah,'0'+0Ah			; Q: >= 10?
	jb	short @F			;    N: next digit
	add	ah,'A'-'0'+0Ah			;    Y: convert to hex
@@:	cmp	al,'0'+0Ah			; Q: >= 10?
	jb	short @F			;    N: done
	add	al,'A'-'0'+0Ah			;    Y: convert to hex
@@:
	mov	dword ptr [VDD_Str_BadIO],eax
	Fatal_Error <OFFSET32 VDD_Str_BadIO>

EndProc VDD_TIO_Device_Init

VxD_ICODE_ENDS


VxD_CODE_SEG



;******************************************************************************
; VDD_TIO_Set_Trap
;
;DESCRIPTION:
;	Adjust VM's I/O trapping according to ownership of MemC and CRTC state
;	and the video mode and PIF bits
;
;ENTRY: EBX = VM handle
;	EDI -> VDD_CB_Struc
;
;EXIT:	none
;
;USES:	Flags, EDX
;
;*******************************
BeginProc VDD_TIO_Set_Trap,PUBLIC

Assert_VDD_ptrs ebx,edi

	TestMem	[Vid_Flags], fVid_NestedModeSet	;Q: nested modeset ongoing?
	jnz	VIOST_Disable_Local		;   Y: no trappy trappy!

IFDEF DEBUG
	cmp	[VDD_Force_Trapping], 1 	;Q: force trapping for debugging?
	jz	VIOST_Enable_Local		;   Y: trap all ports
	cmp	[VDD_Force_Trapping], 2 	;Q: force trapping for debugging?
	jz	VIOST_Disable_Local
ENDIF
	TestMem [Vid_Flags], fVid_MsgInit	; Q: Message mode init'd?
	jz	SHORT VIOST_Enable_Local	;   N: trap all ports
	TestMem [edi.VDD_Flags],<fVDD_ModeSet+fVDD_PageChg>; Q: Doing mode set?
	jnz	SHORT VIOST_Enable_Local	;   Y: trap all ports

	cmp	ebx,[Vid_CRTC_VM]		; Q: VM own CRTC state?
	jnz	SHORT VIOST_Enable_Local	;   N: trap all ports
	TestMem [Vid_Flags], fVid_DOff		; Q: Display off?
	jnz	SHORT VIOST_Enable_Local	;   Y: trap all ports
	cmp	ebx,[Vid_MemC_VM]		; Q: VM own MemC state?
	jnz	SHORT VIOST_Enable_Local	;   N: trap all ports
	TestMem [edi.VDD_Flags], fVDD_MemCmods	; Q: VM's MemC state modified?
	jnz	SHORT VIOST_Enable_Local	;   Y: trap all ports

	TestMem [edi.VDD_Flags], fVDD_CanRestore; Q: Special VM type?
	jnz	SHORT VIOST_Disable_Local	;   Y: No trapping

;*******
; check the PIF NoTrap bits for Attached VM
;
mVidNoTrapPIF EQU fVidNoTrpTxt+fVidNoTrpLRGrfx+fVidNoTrpHRGrfx
	TestMem [edi.VDD_PIF],mVidNoTrapPIF	; Q: No trapping enabled?
	jz	SHORT VIOST_Enable_Local	;   N: trap all ports

	TestMem [edi.VDD_Stt.G_Misc], fGrp6Char ; Q: Text mode?
	jnz	SHORT VIOST_01			;   N: continue
	TestMem [edi.VDD_PIF],fVidNoTrpTxt	; Q: No trapping enabled?
	jnz	SHORT VIOST_Disable_Local	;   Y: No trapping
	jmp	SHORT VIOST_Enable_Local	;   N: Do trapping
VIOST_01:
	test	[edi.VDD_Stt.S_MMode], fSeq4SqAd;Q: in odd/even mode?
	jz	short VIOST_01a 		;   Y:
	test	[edi.VDD_Stt.C_Mode], 1 	;Q: CGA compatibility enabled?
	jnz	short VIOST_02			;   N:
%OUT mode13 could be considered lo-res, but is more difficult to detect
VIOST_01a:
	TestMem [edi.VDD_PIF],fVidNoTrpLRGrfx	; Q: No trapping enabled?
	jnz	SHORT VIOST_Disable_Local	;   Y: No trapping
	jmp	SHORT VIOST_Enable_Local	;   N: Do trapping
VIOST_02:
	TestMem [edi.VDD_PIF],fVidNoTrpHRGrfx	; Q: No trapping enabled?
	jnz	SHORT VIOST_Disable_Local	;   Y: No trapping
Assumes_Fall_Through VIOST_Enable_Local 	;   N: Do trapping
        
;*******
; Enable local trapping for VM for all ports
;	except for CRTC only ports for CRTC owner and not special situations
VIOST_Enable_Local:
IFDEF DEBUG
	cmp	[VDD_Force_Trapping], 3 	;Q: force trapping for debugging?
	jne	short VIOST_Enable_Local_D00
	mov	[VDD_Forced_Trap], 0
VIOST_Enable_Local_D00:
ENDIF
	call	VDD_OEM_Enable_Local_Traps
	SetFlag [edi.VDD_Flags],fVDD_IOT	; Trapping some ports
	call	VIOST_Trap_Mono
	mov	edx,3C0h
VIOST_NextPort:
	call	VIOST_EnableTrap
	inc	edx
	cmp	dl,0E0h
	jb	VIOST_NextPort
VIOST_ELExit:
	ret

;*******
; Disable local trapping for VM
VIOST_Disable_Local:
IFDEF DEBUG
	cmp	[VDD_Force_Trapping], 3 	;Q: force trapping for debugging?
	jne	short @F
	mov	[VDD_Forced_Trap], 1
	jmp	VIOST_Enable_Local_D00
@@:
ENDIF
	call	VDD_OEM_Disable_Local_Traps
	btr	[edi.VDD_Flags],bVDD_IOT	; Q: Already trapped?
	jnc	SHORT VIOST_DLExit		;   N: All done
	mov	edx,3C0h
	mov	[edi.VDD_TrapEnable],0		;   Y: all port traps disabled
VIOST_DL0:
	VMMCall Disable_Local_Trapping
	inc	edx
	cmp	dl,0E0h
	jb	VIOST_DL0

IFDEF VGAMONO
	btr	[edi.VDD_Flags], bVDD_IOTmono
	jnc	SHORT @F
	mov	dl,0B4h
	VMMCall Disable_Local_Trapping
	inc	edx				; 3B5
	VMMCall Disable_Local_Trapping
	mov	dl,0BAh
	VMMCall Disable_Local_Trapping
@@:
ENDIF
VIOST_DLExit:
	ret

;*******
; Conditionally enable port trap on port in EDX
;
VIOST_EnableTrap:
	push	edx
	and	edx,001Fh
	bt	[Vid_CRTC_Port],edx		; Q: CRTC only port?
	jc	SHORT VIOST_CRTC_Chk		;   Y: see if CRTC owner
VIOST_EnablePortTrap:				;	and enable local traps
	bts	[edi.VDD_TrapEnable],edx	; Q: This port trap enabled?
	jc	SHORT VIOST_SkipPort		;   Y: skip enable again
	pop	edx
	VMMJmp	Enable_Local_Trapping

; CRTC only port
;   Don't trap if CRTC owner and either not doing modeset or doing pageChg or
;	display is off or PIF does not indicate trap ports
VIOST_CRTC_Chk:
	cmp	ebx,[Vid_CRTC_VM]		; Q: CRTC owner?
	jnz	VIOST_EnablePortTrap		;   N: enable trapping
	TestMem [edi.VDD_Flags],<fVDD_ModeSet+fVDD_PageChg>; Q: Doing mode set?
	jnz	VIOST_EnablePortTrap		;   Y: trap all ports
	TestMem [Vid_Flags], fVid_DOff		; Q: Display off?
	jnz	VIOST_EnablePortTrap		;   Y: trap all ports
VIOST_SkipPort:
	pop	edx
	ret					;   N: no trapping this port
EndProc VDD_TIO_Set_Trap

IFDEF VGAMONO
;******************************************************************************
; VIOST_Trap_Mono
;
;DESCRIPTION:
;	Adjust VM's mono port I/O trapping according to ownership of MemC
;	and CRTC state and global mono port responsibility of VDD.
;
;ENTRY: EBX = VM handle
;	EDI -> VDD_CB_Struc
;
;EXIT:	none
;
;USES:	Flags
;
;*******************************
BeginProc VIOST_Trap_Mono

	TestMem [edi.VDD_TFlags],fVT_Mono	; Q: Mono supported?
	jnz	short @F			;   Y: trap mono ports
	test	[edi.vdd_Stt.V_Misc],fMiscPNum	;Q: CRTC at color addrs?
	jnz	SHORT VIOST_NoMono		;   Y: Don't trap mono ports
	TestMem [edi.VDD_TFlags],fVT_MonoPorts	; Q: Mono ports supported?
	jz	SHORT VIOST_NoMono		;   N: Don't trap mono ports
@@:
	bts	[edi.VDD_Flags], bVDD_IOTmono
	jc	short VIOST_NoMono		; jump if already trapped
	push	edx
	xor	edx, edx
	xchg	edx, [edi.VDD_TrapEnable]
	push	edx
	mov	edx,3B4h
	call	VIOST_EnableTrap
	inc	edx				; 3B5
	call	VIOST_EnableTrap
	mov	dl,0BAh
	call	VIOST_EnableTrap
	pop	[edi.VDD_TrapEnable]
	pop	edx
VIOST_NoMono:
	ret
EndProc VIOST_Trap_Mono
ENDIF

;******************************************************************************
; VIOT_DISP	Trap I/O for ports 3C0 .. 3DF and 3B0-3BF for mono support
;
;DESCRIPTION:
;	Handles I/O port traps
;
;ENTRY: EBX = VM handle
;	EAX/AX/AL = DWORD/WORD/BYTE to output to port.
;	EDX = port address for I/O.
;	ECX = I/O length/direction descriptor
;	SS:EBP = Client stack
;
;EXIT:	EAX/AX/AL = emulated input value from port.
;
;USES:	Flags, ECX, EDX, ESI, EDI
;
;*******************************
;
;   The I/O port trap routines labeling conventions
;
;	VIOT_nnn	    Video I/O trap entry point for port nnn
;	VIOT_tt_xxxxx	    Video Input/Output Trap routine where:
;	    tt	    =	 In - input
;		    =	 VI - virtual input
;		    =	 PI - physical input
;		    =	 Out - output
;		    =	 PO - physical output
;		    =	 VO - virtual output
;	    xxxxx   =	 Name of chip (e.g. Seq for sequencer, CRTC for CRT
;					controller, Grp for Graphics controller)
;
;==============================================================================
BeginProc VIOT_Disp, High_Freq, PUBLIC
	SetVDDPtr edi
	Emulate_Non_Byte_IO

	clc
	pushfd

IFDEF DEBUG
	pushad
	xor	eax, eax
	call	VDD_State_Schedule_Debug_Event
	popad

	cmp	[VDD_Forced_Trap], 0
	je	short @F
	popfd
	jecxz	short viot_log_in
	Queue_Out 'viot out #BX,#AL',eax,edx
	out	dx, al
	ret

viot_log_in:
	in	al, dx
	Queue_Out 'viot in #AL,#BX',eax,edx
	ret
@@:
ENDIF

	cmp	ebx,[Vid_CRTC_VM]		    ; Q: CRTC VM?
	jne	SHORT @f			    ;	N: Leave carry clear
	TestMem [Vid_Flags], fVid_MsgInit	    ; Q: Message mode init'd?
	jz	short @F			    ;	N:
	SetFlag [esp],CF_Mask			    ;	Y: Set carry
@@:
	popfd
	pushfd					    ; Q: Input?
	jnz	SHORT VIOT_Disp0		    ;	Y: Skip MemC assign
	TestMem [edi.VDD_Flags], fVDD_WaitAtt	    ; Q: VM is detached?
	jnz	short VIOT_Disp_Ignore		    ;	Y: ignore output
	cmp	ebx,[Vid_CRTC_VM]		    ; Q: CRTC VM?
	jnz	SHORT VIOT_Disp0		    ;	N: Skip MemC assign
	call	VDD_State_Set_MemC_Owner	    ; Assign MemC state
VIOT_Disp0:
;	When dispatching, bits 5 and 6 are or'd into the port address to
;	yield the dispatch offset (divided by 4), so that 3Bx and 3Dx are
;	mapped to 3Fx and 3Cx ports are mapped to 3Ex.
	mov	esi,edx
	or	esi,60h 			    ; Map ports: 3Bx=3Fx,
	movzx	esi, VIOT_Index[esi-3E0h]

	popfd
PUBLIC VIOT_Dispatch_Jump
VIOT_Dispatch_Jump:
	jmp	VIOT_Dispatch[esi]

IFDEF	DEBUG
;
; patching out the jump instruction at "VIOT_Dispatch_Jump" will result
; in falling thru to this code which logs all trapped I/O
;
	pushfd
	jne	SHORT xxcvx01
Queue_Out "VIOT Out #BX,#AL" ,eax,edx
xxcvx01:
	call	VIOT_Dispatch[esi]
	popfd
	je	SHORT xxcvx02
Queue_Out "VIOT In #AL,#BX" ,eax,edx
xxcvx02:
	ret
ENDIF

VIOT_Disp_Ignore:
	popfd
	ret

EndProc VIOT_Disp


BeginProc VIOT_CRTC

	pushfd
	mov	ah, [edi.VDD_Stt.V_Misc]
	jnc	SHORT @F		    ; jump, if not CRTC owner
	push	edx			    ; is CRTC owner, so read physical
	mov	dl, pMiscIn AND 0FFh	    ;	misc output register
	mov	ah, al
	in	al, dx
	xchg	al, ah
	pop	edx
@@:
	shl	ah, 6			    ; shift low bit to bit 6
	xor	ah, dl
	test	ah, 01000000b		    ;Q: matching modes?
					    ;	0, if dx = 3Bx & V_Misc.0 = 0
					    ;	     or dx = 3Dx & V_Misc.0 = 1
	jnz	short crtc_ignore	    ;	N: ignore i/o
IFDEF CLVGA
	TestMem [edi.VDD_TFlags],fVT_CLVGA  ; is it a cirrus chip ?
	jz	SHORT @F		    ; no - jump
	mov	ah, [edi.VDD_Stt.V_Extend.CL_ER_STATE]
	test	ah, 3			    ;Q: state select for CRTC?
	jnz	short crtc_ignore	    ;	N: ignore i/o
@@:
ENDIF
	popfd				    ;	Y: pass on to handler
	jmp	VIOT_Dispatch[esi+$actual]

crtc_ignore:
	popfd
	mov	al, -1
	ret

EndProc VIOT_CRTC


;*******************************
; Undefined ports
;

BeginProc VIOT_In_Undef,High_Freq
	in	al,dx
	ret
EndProc VIOT_In_Undef

BeginProc VIOT_Ignore,High_Freq
	jnz	VIOT_In_Undef
	out	dx,al
	ret
EndProc VIOT_Ignore





;******************************************************************************
; VDD_TIO_MemC_Mod
;
;DESCRIPTION:
;	Handles I/O port traps for when Mod_MemC state is active
;
;ENTRY: EBX = VM handle
;	EDI -> VDD_CB_Ptr
;	AL = BYTE to output to port.
;	DX = port address for output
;	ECX = index (zero for ports without index)
;
;EXIT:	AL = modified output value
;
;USES:	Flags, AL
;
;==============================================================================
BeginProc VDD_TIO_MemC_Mod, PUBLIC

	cmp	[edi.VDD_MemC_ModCnt], 0
	jne	SHORT VT_MM_00
	ret

VT_MM_00:
	push	ebx
	push	ecx
	push	esi
	mov	ebx,ecx
	lea	esi, [edi.VDD_MemC_Mods]
	movzx	ecx, [edi.VDD_MemC_ModCnt]
VT_MM_01:
	cmp	dx,[esi.MMS_data_port]
	jz	SHORT VT_MM_Do_Modify
VT_MM_Next:
	add	esi,SIZE MemC_Mod_Struc
	loopd	VT_MM_01
VT_MM_Done:
	pop	esi
	pop	ecx
	pop	ebx
	ret

VT_MM_Do_Modify:
	cmp	bl,[esi.MMS_index]
	jnz	VT_MM_Next
	and	al,[esi.MMS_ANDmask]
	or	al,[esi.MMS_ORmask]
	jmp	VT_MM_Done

EndProc VDD_TIO_MemC_Mod


IFDEF	VGA8514
BeginProc VIOT_8514_Null, High_Freq

	Dispatch_Byte_IO Fall_Through, <SHORT VIOT_8514_Out>

VIOT_8514_In:
	xor	al, al

VIOT_8514_Out:
	ret

EndProc VIOT_8514_Null
ENDIF

;***************    Attribute controller(port 3C0 and port 3C1)
;   Index and registers all belong to CRTC owner
BeginProc VIOT_3C0,High_Freq
	jnz	SHORT VIOT_In_3C0
	jnc	SHORT VIOT_VO_Attr		    ; Not CRTC owner

	test	[edi.VDD_Stt.A_Indx],fVAI_Indx	    ; Q: Setting index?
	jz	SHORT VIOT_PO_Attr		    ;	N: do phys out
	TestMem [Vid_Flags], fVid_DOff		    ;Q: display turned off?
	jz	SHORT VIOT_PO_Attr		    ;	N: do phys out
	mov	[edi.VDD_Stt.A_Indx],al 	    ;	Y: save virtual value
	and	al, NOT fVAI_ScOn		    ;	    clear ScOn bit
	out	dx, al				    ;	    do phys out
	jmp	SHORT VIOT_ASv2

VIOT_In_3C0:				
%OUT Physical Attribute reading?
; Note that if trapping is disabled and the index register is written to
;   and then trapping is enabled and the index is read, the value will
;   be bogus.  We don't know of any software that depends on this.
	mov	al, [edi.VDD_Stt.A_Indx]
	and	al, NOT fVAI_Indx	
	ret

BeginProc VIOT_3C1,High_Freq
	jnz	SHORT VIOT_In_3C1
	jnc	SHORT VIOT_VO_Attr
VIOT_PO_Attr:
	out	dx,al
VIOT_VO_Attr:
	test	[edi.VDD_Stt.A_Indx],fVAI_Indx	    ; Q: Setting index?
	jnz	SHORT VIOT_AIndx		    ;	Y: go set it
	movzx	ecx,[edi.VDD_Stt.A_Indx]	    ;	N: it's data reg output
	test	cl, 00010000b			    ; Q: Setting palette?
	jnz	SHORT VIOT_VOA0 		    ;	N: Access OK
IFDEF CLVGA
;
;  Cirrus allows access with display on
;
	TestMem [edi.VDD_TFlags],fVT_CLVGA		; is it a cirrus chip ?
	jnz	SHORT VIOT_VOA0 		    ; yes - jump

ENDIF
	test	cl, fVAI_ScOn			    ;	Y: Q: Display on?
	jnz	SHORT VIOT_ASv1 		    ;	    Y: ignore
VIOT_VOA0:
	and	cl, NOT fVAI_ScOn
	cmp	cl,A_IMax			    ; Q: index valid?
	ja	SHORT VIOT_ASv1 		    ;	N: ignore
	mov	[edi.VDD_Stt.A_Pal][ecx],al	    ; Save the Attr reg. value
VIOT_ASv1:
	or	[edi.VDD_Stt.A_Indx],fVAI_Indx	    ; Attr ready for index
IFDEF	CLV7VGA

	TestMem [edi.VDD_TFlags],<fVT_CLVGA+fVT_V7VGA> ; cirrus or V7 chip ?
	jz	SHORT VIOT_Asv3 		    ; no - jump
	and	[edi.VDD_Stt.V_Extend.CL_ER_ARX],07fh ; set for index ready
VIOT_Asv3:
ENDIF
	jmp	SHORT VIOT_ASv2

VIOT_AIndx:
	and	al, NOT fVAI_Indx
	mov	[edi.VDD_Stt.A_Indx],al

IFDEF CLV7VGA
	TestMem [edi.VDD_TFlags],<fVT_CLVGA+fVT_V7VGA> ; cirrus or V7 chip ?
	jz	SHORT VIOT_Asv2 		    ; no - jump

	or	al,80h				    ; set for ready for data
	mov	[edi.VDD_Stt.V_Extend.CL_ER_ARX],al   ; save extended reg copy
	and	al,7fh				    ; clear high order bit
ENDIF

VIOT_ASv2:
	ret

VIOT_In_3C1:
%OUT this isn't correct - if screen on and CRTC != MemC, then pallete wasn't read
	movzx	eax, [edi.VDD_Stt.A_Indx]
	and	al, (NOT fVAI_ScOn) AND mx_Attr     ; make sure index valid
	mov	al, [edi.VDD_Stt.A_Pal][eax]	    ; Get the Attr reg. value
	ret

EndProc VIOT_3C1
EndProc VIOT_3C0


;***************    Miscellaneous register
; Bit 1 (enable RAM access) and bit 5 (odd even lsb of address) belong to the
;	MemC state and the rest of the bits belong to the CRTC state.
BeginProc VIOT_3C2,High_Freq
	jnz	SHORT VIOT_In_Stat0
	push	eax
						    ; Q: CRTC VM?
	jc	SHORT VIOT_PO_Misc		    ;	Y: do physical output
	cmp	ebx, [Vid_MemC_VM]		    ; Q: MemC VM?
	jnz	SHORT VIOT_VO_Misc		    ;	N: do virtual output
	TestMem [Vid_Flags], fVid_MsgInit	    ; Q: Message mode init'd?
	jz	short VIOT_VO_Misc		    ;	N:
	mov	esi,[Vid_CRTC_VM]		    ;	Y: Merge CRTC with MemC
	add	esi,[Vid_CB_Off]
	mov	ah,[esi.VDD_Stt.V_Misc] 	    ; Get CRTC value
	mov	ecx,0DD22h
	and	eax,ecx 			    ; Mask to appropriate bits
	or	al,ah				    ; Merge
VIOT_PO_Misc:
	call	VDD_TIO_MemC_Mod		    ; Modify if necessary
	out	dx,al
VIOT_VO_Misc:
	pop	eax
	mov	[edi.vdd_Stt.V_Misc],al 	    ; Save Misc output value

IFDEF VRTCTIMER
	push	eax
	call	VDD_State_Calc_Framerate	    ; In case dot clock changed
	pop	eax
ENDIF

IFDEF CLVGA
	TestMem [edi.VDD_TFlags],fVT_CLVGA		; is it a cirrus chip ?
	jz	SHORT @F			    ; no - jump
	push    eax				    ; save the current value
	and     al,00CH                             ; save clock select bits 
	mov     ah,al                               ; plave in ah
	mov	al,[edi.vdd_Stt.V_Extend.CL_ER_CLK]   ; get extension reg value
	and     al, not 00CH                        ; clear clock bits
	or      al,ah                               ; add new clock bits
	mov	[edi.vdd_Stt.V_Extend.CL_ER_CLK],al   ; set extension reg value
	pop	eax
@@:
ENDIF


IFDEF VGAMONO
	TestMem [edi.VDD_TFlags],fVT_Mono	    ;Q: VDD handles MONO mem?
	jnz	SHORT @F			    ;	Y: trapping already handled
	test	al, fMiscPNum			    ;Q: CRTC at color or mono addrs?
	jnz	SHORT @F			    ;	Color: do nothing
Trace_Out 'VM just mapped CRTC to mono port address'
	call	VIOST_Trap_Mono 		    ; If possible, trap mono ports
@@:
ENDIF

VIOT_MSv_Ret:
	ret

;***************    Status 0 register
;
VIOT_In_Stat0:
	jnc	SHORT VIOT_VI_Stat0
	in	al,dx
	ret
VIOT_VI_Stat0:
	mov	al,[edi.VDD_Stt.V_Stat0]
	or	al, al
	jnz	short @F
	in	al, dx
@@:
IFDEF TLVGA
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jz	short in_3c2_not_tlvga
	and	al, 11101111b
	mov	cl, [edi.vdd_Stt.V_Misc]	    ; Get Misc output value
	shr	cl, 2
	and	cl, 3
	mov	ch, [TL_Switches]
	shr	ch, cl
	and	ch, 1
	shl	ch, 4
	or	al, ch
in_3c2_not_tlvga:
ENDIF
IFDEF DEBUG_virtualization
	mov	ah, al
	in	al, dx
	cmp	al, ah
	je	short @F
	xchg	al, ah
	Debug_Out "3C2 read different"
@@:
ENDIF
	ret
EndProc VIOT_3C2

;***************    Sequencer index
;   MemC owns index register, CRTC and MemC own pieces of rest of the registers
BeginProc VIOT_3C4,High_Freq
	jnz	SHORT VIOT_In_SeqI
	cmp	ebx,[Vid_MemC_VM]
	jnz	SHORT VIOT_VO_SeqI
	TestMem [Vid_Flags], fVid_MsgInit	    ; Q: Message mode init'd?
	jz	short VIOT_VO_SeqI		    ;	N:
	out	dx,al
VIOT_VO_SeqI:
	mov	[edi.VDD_Stt.S_Indx],al
VIOT_Out_SeqIRet:
	ret

VIOT_In_SeqI:
	cmp	ebx,[Vid_MemC_VM]
	jnz	SHORT VIOT_VI_SeqI
	TestMem [Vid_Flags], fVid_MsgInit	    ; Q: Message mode init'd?
	jz	short VIOT_VI_SeqI		    ;	N:
	in	al,dx
	ret
VIOT_VI_SeqI:
	mov	al, [edi.VDD_Stt.S_Indx]	    ; get virtual value
	ret
EndProc VIOT_3C4

;***************    Sequencer data
;
BeginProc VIOT_3C5,High_Freq
	movzx	ecx,[edi.VDD_Stt.S_Indx]	    ; ECX = sequencer index
	jnz	VIOT_In_Seq			    ; Go do input

;*******
; SEQUENCER "OUT DX,AL"
	push	eax
						    ; Q: CRTC (and MemC) owner?
	jnc	SHORT VIOT_VO_Seq		    ;	N: Virtual output
	call	VDD_TIO_MemC_Mod		    ; Modify if necessary

; Physical output
;   AL = value
;   ECX = index
;   Zero flag set, Carry flag clear
	cmp	eax,eax
	call	VDD_OEM_PO_Seq			    ; Q: OEM register
	jc	SHORT VIOT_Out_Seq_NoOut	    ;	Y: don't output it
	jnz	SHORT VIOT_Out_Seq_DoOut	    ;	Y: Output it
						    ;	N: treat normally

; Physical output of non-OEM extension register, save the value and output it
	cmp	cl,S_IMax			    ; Q: Normal range?
	ja	SHORT VIOT_Out_Seq_DoOut	    ;	N: ignore it
	xchg	eax,[esp]
	mov	[edi.VDD_Stt.S_Rst][ecx],al	    ;	Y: Save value
	xchg	eax,[esp]

;*******
; Sequencer physical output
; Output value in AL then restore EAX and exit
VIOT_Out_Seq_DoOut:
; AL = actual value to output (merged CRTC and MemC value)
	out	dx,al
VIOT_Out_Seq_NoOut:
	pop	eax
	ret

;*******
; Sequencer virtual output (not both CRTC and MemC owner)
;
VIOT_VO_Seq:
	cmp	eax,eax
	call	VDD_OEM_VO_Seq			    ; Q: OEM specific value?
	jc	VIOT_Out_Seq_NoOut		    ;	Y: Do output
	jnz	VIOT_Out_Seq_NoOut		    ;	Y: All done

; Not handled by OEM specific routine, do normal processing
	cmp	cl,S_IMax			    ; Q: IBM range?
	ja	VIOT_Out_Seq_NoOut		    ;	N: ignore it
	cmp	[edi.VDD_Stt.S_Rst][ecx],al	    ; Q: Value change?
	jz	VIOT_Out_Seq_NoOut		    ;	N: all done

; If this VM owns MemC state, we need to merge with CRTC state and do
;   the physical output
	mov	esi,[Vid_CRTC_VM]
	add	esi,[Vid_CB_Off]
	mov	ah,[esi.VDD_Stt.S_Rst][ecx]	    ; AH = CRTC VM value
	mov	esi,ebx
	mov	bl,[mSeq_MemC][ecx]		    ; BL = MemC bits mask
	or	bl,bl				    ; Q: Any MemC bits?
	jz	SHORT VIOT_VO_Seq_NoMemCChg	    ;	N: Skip output

; Merge CRTC value with MemC value and output it
	and	al,bl				    ; AL = MemC bits
	not	bl
	and	ah,bl				    ; AH = CRTC bits
	or	al,ah				    ; AL = merged CRTC/MemC bits
	mov	ah,al
	xor	ah,[edi.VDD_Stt.S_Rst][ecx]	    ; AH = changed VM bits
	not	bl
	test	ah,bl				    ; Q: Any MemC bits change?
	jz	SHORT VIOT_VO_Seq_NoMemCChg	    ;	N: Skip output
	mov	ebx,esi 			    ; restore VM handle
	cmp	ebx,[Vid_MemC_VM]		    ; Q: MemC owner?
	jnz	SHORT VIOT_VO_Seq_NoOut 	    ;	N: No output
	TestMem [Vid_Flags], fVid_MsgInit	    ; Q: Message mode init'd?
	jz	short VIOT_VO_Seq_NoOut 	    ;	N:
	call	VDD_TIO_MemC_Mod		    ; Modify if necessary
	out	dx,al				    ;	Y: Output merged bits
VIOT_VO_Seq_NoOut:
	pop	eax				    ; AL = VM's output value

;*******
; Process change in Sequencer register MemC value
;   AL	= value
;   EBX = VM handle
;   ECX = index(register number)
;   EDX = port address
;   EDI = VDD control block structure ptr
	mov	[edi.VDD_Stt.S_Rst][ecx],al	    ; Save new value
VIOT_VO_Seq_Exit:
	ret

; No MemC state bits changed, just return
VIOT_VO_Seq_NoMemCChg:
	mov	ebx,esi
	pop	eax

	mov	[edi.VDD_Stt.S_Rst][ecx],al	    ; Save new value
	jmp	VIOT_VO_Seq_Exit

;*******
; SEQUENCER "IN AL,DX"
;
VIOT_In_Seq:
						    ; Q: CRTC owner?
	jnc	SHORT VIOT_VI_Seq		    ;	N: Do virtual input
	cmp	ebx,[Vid_MemC_VM]		    ; Q: MemC owner?
	jnz	SHORT VIOT_VI_Seq		    ;	N: Do virtual input

;*******
; Sequencer physical input
IFDEF TTVGA
;	TVGA Need specail care even for physical input
;	- Henry Zeng
	call	VDD_OEM_PI_Seq			    ; Q: OEM extension
ENDIF

VIOT_In_Seq_DoIn:
	in	al,dx
VIOT_In_Seq_NoIn:
	ret

;*******
; Sequencer virtual input (not both MemC and CRTC owner)
VIOT_VI_Seq:
	cmp	eax,eax
	call	VDD_OEM_VI_Seq			    ; Q: OEM extension
IFDEF DEBUG_virtualization
	jc	short @F			    ;	Y: Do input
	jnz	short @F			    ;	Y: return value
	mov	al, [edi.VDD_Stt.S_Rst][ecx]	    ; return virtual value
@@:
	mov	ah, al
	dec	edx
	mov	al, cl
	out	dx, al
	IO_Delay
	inc	edx
	in	al, dx
	cmp	al, ah
	je	short @F
	xchg	al, ah
	Debug_Out "3C5 read different"
@@:
ELSE
	jc	VIOT_In_Seq_DoIn		    ;	Y: Do input
	jnz	VIOT_In_Seq_NoIn		    ;	Y: return value
	mov	al, [edi.VDD_Stt.S_Rst][ecx]	    ; return virtual value
ENDIF
	jmp	VIOT_In_Seq_NoIn

EndProc VIOT_3C5


;***************    Miscellaneous register
;   Disable output for VM that does not own CRTC
BeginProc VIOT_3C6,High_Freq
	jnz	VIOT_In_Undef
	jnc	SHORT VIOT_VO_CPQ
	out	dx,al
VIOT_VO_CPQ:
	ret
EndProc VIOT_3C6

;***************    Digital to Analog Converter (DAC)
;   Completely owned by CRTC
; IN:	DAC State Register
; OUT:	Read mode PEL address
;
BeginProc VIOT_3C7,High_Freq
	jnz	SHORT VIOT_In_3C7
	jnc	SHORT VIOT_VO_3C7
	out	dx,al

VIOT_VO_3C7:
	movzx	edx, al
	shl	edx, 2
	lea	edx, [edi.VDD_DAC][edx] 	    ; EDX points to start of PEL

	mov	[edi.VDD_PEL_Addr], edx
IFDEF	DEBUG
	cmp	[edx],al
	jz	SHORT VIOT_VO_3C7DBG0
Debug_Out "VO_3C7 DAC entry index not correct"
VIOT_VO_3C7DBG0:
ENDIF
	mov	[edi.VDD_PEL_Idx], 1
	mov	[edi.VDD_PEL_Mode], vDAC_Read_Mode
	ret

VIOT_In_3C7:
	jnc	SHORT VIOT_VI_3C7
	in	al,dx
	ret

VIOT_VI_3C7:
	mov	al, [edi.VDD_PEL_Mode]
	ret

EndProc VIOT_3C7

;***************    Digital to Analog Converter (DAC)
;   Completely owned by CRTC
; IN:	Write mode PEL address
; OUT:	Write mode PEL address
;
BeginProc VIOT_3C8,High_Freq
	jnz	SHORT VIOT_In_3C8
	jnc	SHORT VIOT_VO_3C8
	out	dx,al

VIOT_VO_3C8:
	movzx	edx, al
	shl	edx, 2
	lea	edx, [edi.VDD_DAC][edx] 	    ; edx points to start of PEL
	mov	[edi.VDD_PEL_Addr], edx
IFDEF	DEBUG
	cmp	[edx],al
	jz	SHORT VIOT_VO_3C8DBG0
Debug_Out "VO_3C8 DAC entry index not correct"
VIOT_VO_3C8DBG0:
ENDIF
	mov	[edi.VDD_PEL_Idx], 1
	mov	[edi.VDD_PEL_Mode], vDAC_Write_Mode
	ret

VIOT_In_3C8:
	jnc	SHORT VIOT_VI_3C8
	in	al,dx
	ret

VIOT_VI_3C8:
	mov	edx, [edi.VDD_PEL_Addr]
	lea	eax, [edi.VDD_DAC]
IFDEF	DEBUG
	neg	eax
	add	eax, edx
	shr	eax, 2				    ; al = PEL index
	cmp	al, [edx]
	jz	SHORT VIOT_VI_3C8DBG0
Debug_Out "VI_3C8 DAC entry index not correct"
VIOT_VI_3C8DBG0:
ELSE
	cmp	edx, eax			    ; PEL_Addr valid?
	mov	al, 0				    ;	assume no
	jbe	short @F			    ;	N:
	mov	al, [edx]			    ;	Y: read index
@@:
ENDIF
	ret
EndProc VIOT_3C8


;***************    Digital to Analog Converter (DAC)
;   Completely owned by CRTC
; IN:	Read current PEL data byte
; OUT:	Write current PEL data byte
;
BeginProc VIOT_3C9,High_Freq
	jnz	SHORT VIOT_In_3C9
	jnc	SHORT VIOT_VO_3C9

IFDEF CLVGA
;                               ; fixes a bug in palette writes 
                                ; on CL LCD controllers
	TestMem [edi.VDD_TFlags],fVT_CLVGA	    ; cirrus logic ?
	jz	SHORT VO_3c9_NotCL
	push    eax
	push    ecx
	push    edx

	cmp	[edi.VDD_PEL_Mode], vDAC_Read_Mode ;Q: read mode?
	je	SHORT DAC_Special_10

	movzx	ecx, [edi.VDD_PEL_Idx]
	cmp     cl,3
	jne	SHORT DAC_Special_10

	mov	esi, [edi.VDD_PEL_Addr]

      	lodsb
	dec	edx
	out     dx,al
	IO_Delay

	inc	edx
	dec	ecx
DAC_Special_5:
      	lodsb
	out     dx,al
	loopd	DAC_Special_5


DAC_Special_10:
	pop	edx
	pop	ecx
	pop	eax
VO_3c9_NotCL:
ENDIF
	out	dx, al

VIOT_VO_3C9:
	mov	esi, [edi.VDD_PEL_Addr]
	movzx	edx, [edi.VDD_PEL_Idx]
	cmp	[edi.VDD_PEL_Mode], vDAC_Read_Mode  ; Q: read mode?
IFDEF DEBUG
	jne	SHORT VIOT_3C9_write_ok
	Debug_Out 'VDD: write DAC data in read mode (port 3C9)'
	jmp	SHORT VIOT_update_DAC_ptr
VIOT_3C9_write_ok:
ELSE
	je	SHORT VIOT_update_DAC_ptr	    ;	Y: skip write update
ENDIF
	SetFlag	[edi.VDD_Flags],fVDD_DacChg	; dacs have changed
	mov	[esi+edx], al
	jmp	SHORT VIOT_update_DAC_ptr

VIOT_In_3C9:
	jnc	SHORT VIOT_VI_3C9
	in	al,dx
	ret
VIOT_VI_3C9:
	mov	esi, [edi.VDD_PEL_Addr]
	movzx	edx, [edi.VDD_PEL_Idx]
	mov	al, [esi+edx]
VIOT_update_DAC_ptr:
	cmp	edx, 3				    ; Q: last byte in PEL?
	jb	SHORT VIOT_3C9_not_last 	    ;	N:
	xor	edx, edx			    ;	Y: INC to next entry
	add	esi, 4
	push	eax				    ; don't stomp on AL
	lea	eax, [edi.VDD_PEL_Addr]
	cmp	esi, eax			    ; Q: end of DAC table?
	pop	eax
	jb	SHORT VIOT_3C9_no_wrap		    ;	N:
	lea	esi, [edi.VDD_DAC]		    ;	Y: wrap to start
VIOT_3C9_no_wrap:
	mov	[edi.VDD_PEL_Addr], esi
VIOT_3C9_not_last:
	inc	edx
	mov	[edi.VDD_PEL_Idx], dl
	ret
EndProc VIOT_3C9

;***************    Graphics controller 2 position
;			    Constant - never saved/restored
BeginProc VIOT_3CA,High_Freq
	jnz	VIOT_In_Undef
	jnc	SHORT VIOT_VO_GPos2

IFDEF CLVGA
	TestMem [edi.VDD_TFlags],fVT_CLVGA		; is it a cirrus chip ?
	jz	SHORT VIOT_VO_GPos2_10		; no - then jump
	mov	[edi.VDD_Stt.V_Extend.CL_ER_Gpos2],al ; save extended reg copy
VIOT_VO_GPos2_10:
ENDIF
	out	dx,al
VIOT_VO_GPos2:
	ret
EndProc VIOT_3CA

;***************    Graphics controller 1 position
;			    Constant - never saved/restored
BeginProc VIOT_3CC,High_Freq
	jnz	SHORT VIOT_In_MiscOP_Read
	jnc	SHORT VIOT_VO_GPos1
IFDEF CLVGA
	TestMem [edi.VDD_TFlags],fVT_CLVGA		; is it a cirrus chip ?
	jz	SHORT VIOT_VO_GPos1_10		; no - then jump
	mov	[edi.VDD_Stt.V_Extend.CL_ER_Gpos1],al ; save extended reg copy
VIOT_VO_GPos1_10:
ENDIF
	out	dx,al
VIOT_VO_GPos1:
	ret

VIOT_In_MiscOP_Read:
	jnc	SHORT VIOT_VI_MiscOP_Read
        in      al,dx
	ret

VIOT_VI_MiscOP_Read:
        mov     al,[edi.VDD_Stt.V_Misc]
IFDEF DEBUG_virtualization
	mov	ah, al
	in	al, dx
	cmp	al, ah
	je	short @F
	xchg	al, ah
	Debug_Out "3CC read different"
@@:
ENDIF
	ret

EndProc VIOT_3CC

IFDEF TLVGA
;******************************************************************************
;
;   VIOT_3CD
;
;   DESCRIPTION:
;
;   ENTRY:	    EBX = VM Handle
;		    EDI -> VDD_CB_Ptr
;		    EAX/AX/AL = DWORD/WORD/BYTE to output to port.
;		    EDX = port address for I/O.
;		    ECX = I/O length/direction descriptor
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc VIOT_3CD

	pushfd
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jz	short V3CD_Ignore
	popfd
	jnz	short V3CD_In
IFDEF SysVMin2ndBank
	TestMem [edi.VDD_TFlags], fVT_SysVMin2ndBank
	jz	short @F
IFDEF DEBUG
	or	al, al
	jz	short v3CD_TL_D00
	Debug_Out 'VDD: writing non-zero (#al) to segment reg'
v3CD_TL_D00:
ENDIF
	VMMCall Test_Sys_VM_Handle
	jnz	short @F
	TestMem [Vid_Flags], fVid_DspDrvr_Init
	jz	short @F
	mov	al, 11h
@@:
ENDIF
	mov	[edi.VDD_Stt.V_Extend.TLI_SegSel], al
	cmp	ebx, [Vid_MemC_VM]
	jne	short @F
	out	dx, al
@@:
	ret

V3CD_In:
	mov	al, [edi.VDD_Stt.V_Extend.TLI_SegSel]
	cmp	ebx, [Vid_MemC_VM]
	jne	short @F
	in	al, dx
@@:
	ret

V3CD_ignore:
	popfd
	jmp	VIOT_Ignore

EndProc VIOT_3CD
ENDIF


;***************    Graphics controller index register
;	MemC owns index
BeginProc VIOT_3CE,High_Freq
	jnz	SHORT VIOT_In_GrpI
	cmp	ebx,[Vid_MemC_VM]
	jnz	SHORT VIOT_VO_GrpI
	TestMem [Vid_Flags], fVid_MsgInit	    ; Q: Message mode init'd?
	jz	short VIOT_VO_GrpI		    ;	N:
	out	dx,al
VIOT_VO_GrpI:
	mov	[edi.VDD_Stt.G_Indx],al
	ret

;*******
; Graphics controller index input
VIOT_In_GrpI:
	cmp	ebx,[Vid_MemC_VM]
	jnz	SHORT VIOT_VI_GrpI
	TestMem [Vid_Flags], fVid_MsgInit	    ; Q: Message mode init'd?
	jz	short VIOT_VI_GrpI		    ;	N:
	in	al,dx
	ret

VIOT_VI_GrpI:
	mov	al, [edi.VDD_Stt.G_Indx]	    ; get virtual value
	ret
EndProc VIOT_3CE

;***************    Graphics controller data register
;   CRTC and MemC share data registers
BeginProc VIOT_3CF,High_Freq
	movzx	ecx,[edi.VDD_Stt.G_Indx]
	jnz	VIOT_In_Grp

	push	eax
						    ; Q: CRTC owner?
	jnc	SHORT VIOT_VO_Grp		    ;	N: process virtually
	call	VDD_TIO_MemC_Mod		    ; Modify if necessary

; Physical output
;   AL = value
;   ECX = index
;   Zero flag set, Carry flag clear
	cmp	eax,eax
	call	VDD_OEM_PO_Grp			    ; Q: OEM register
	jc	SHORT VIOT_Out_Grp_NoOut	    ;	Y: don't output it
	jnz	SHORT VIOT_Out_Grp_DoOut	    ;	Y: Output it
						    ;	N: treat normally

; Physical output of non-OEM extension register, save the value and output it
	cmp	cl,G_IMax			    ; Q: Valid index?
	ja	SHORT VIOT_Out_Grp_DoOut	    ;	N: ignore it
	xchg	eax,[esp]			    ; Get back VM's out value
	cmp	cl,6				    ; Q: misc register?
	jnz	SHORT VIOT_Out_Grp_Save 	    ;	N: ignore it
	mov	esi,eax
	xor	al,[edi.VDD_Stt.G_Misc]
	test	al,00Ch 			    ; Q: mem mapping change
	mov	eax,esi
	jz	SHORT VIOT_Out_Grp_Save 	    ;	N: continue
	push	ecx
	push	edx
	push	eax
	call	VDD_VM_Mem_Disable		    ;	Y: unmap pages for remap
IFDEF MapMonoError
IFDEF	VGAMONO
	TestMem [edi.VDD_TFlags],<fVT_Mono OR fVT_ResvB0>
						    ; Q: B0 mapping supported?
	jnz	SHORT @F			    ;	Y: continue
	TestMem [esp],4 			    ; Q: B0 page mapped?
	jnz	SHORT @F			    ;	N: continue
	call	VDD_Error_MapMono		    ;	Y: Warn user
@@:
ENDIF
ENDIF
	pop	eax
	pop	edx
	pop	ecx

VIOT_Out_Grp_Save:
	mov	[edi.VDD_Stt.G_SetRst][ecx],al	    ;	    Save value
	xchg	eax,[esp]

;*******
; Graphics controller physical output
; Output value in AL then restore EAX and exit
VIOT_Out_Grp_DoOut:
; AL = actual value to output (merged CRTC and MemC value)
	out	dx,al
VIOT_Out_Grp_NoOut:
	pop	eax
	ret


;*******
; Virtual output of Graphics controller data register
VIOT_VO_Grp:
	cmp	eax,eax
	call	VDD_OEM_VO_Grp			    ; Q: OEM specific value?
	jc	VIOT_Out_Grp_DoOut		    ;	Y: Output value
	jnz	VIOT_Out_Grp_NoOut		    ;	Y: All done

; Not handled by OEM specific routine, do normal processing
	cmp	cl,G_IMax			    ; Q: Valid index?
	ja	SHORT VIOT_Out_Grp_NoOut	    ;	N: Exit
	cmp	[edi.VDD_Stt.G_SetRst][ecx],al	    ; Q: Did register chg?
	jz	SHORT VIOT_Out_Grp_NoOut	    ;	N: Exit

; If this VM owns MemC state, we need to merge with CRTC state and do
;   the physical output
	mov	esi,[Vid_CRTC_VM]
	add	esi,[Vid_CB_Off]
	mov	ah,[esi.VDD_Stt.G_SetRst][ecx]	    ; AH = CRTC VM value
	mov	esi,ebx
	mov	bl,[mGrp_MemC][ecx]		    ; BL = MemC bits mask
	or	bl,bl				    ; Q: Any MemC bits?
	jz	short VIOT_VO_Grp_NoMemCChg	    ;	N: Skip output

; Merge CRTC value with MemC value and output it
	and	al,bl				    ; AL = MemC bits
	not	bl
	and	ah,bl				    ; AH = CRTC bits
	or	al,ah				    ; AL = merged CRTC/MemC bits
	mov	ah,al
	xor	ah,[edi.VDD_Stt.G_SetRst][ecx]	    ; AH = changed VM bits
	not	bl
	test	ah,bl				    ; Q: Any MemC bits change?
	mov	ebx,esi 			    ; restore VM handle
	jz	SHORT VIOT_VO_Grp_NoMemCChg	    ;	N: Skip output
	cmp	ebx,[Vid_MemC_VM]		    ; Q: MemC owner?
	jnz	SHORT VIOT_VO_Grp_NoOut 	    ;	N: No output
	TestMem [Vid_Flags], fVid_MsgInit	    ; Q: Message mode init'd?
	jz	short VIOT_VO_Grp_NoOut 	    ;	N:
	call	VDD_TIO_MemC_Mod		    ; Modify if necessary
	out	dx,al				    ;	Y: Output merged bits
VIOT_VO_Grp_NoOut:
	mov	al, byte ptr [esp]		    ; AL = VM's output value

IF 0
;
; This code was an attempt to fix the problem caused by Cirrus Logic BIOS'
; which jump into planar mode to do text scrolls.  The fix partially worked,
; but affects most graphics apps, so we added code to emulate the text scroll
; int 10h's in VDDINT, so this fix isn't necessary.
;
	cmp	cl, 5				    ; Q: mode register?
	jne	short @F			    ;	N:
	mov	ch, al				    ;	N: disable mem if write mode changing
	and	ch, 3
	mov	ah, [edi.VDD_Stt.G_Mode]
	and	ah, 3
	cmp	ch, ah				    ; Q: write mode changed?
	mov	ch, 0
	je	short VIOT_VO_Grp_Save		    ;	N:
	push	ecx
	push	edx
	push	eax
	call	VDD_VM_Mem_Disable		    ;	Y: unmap pages for remap
	pop	eax
	pop	edx
	pop	ecx
	jmp	short VIOT_VO_Grp_Save
@@:
ENDIF
	cmp	cl,6
	jnz	SHORT VIOT_VO_Grp_Save
	test	ah,00Ch 			    ; Q: Memory mapping change?
	jz	SHORT VIOT_VO_Grp_Save		    ;	N: Don't tell VM_Mem

;*******
; Process change in Graphics ctrlr MemC value
;   AL	= VM's output value
;   EBX = VM handle
;   ECX = index(register number)
;   EDX = port address
;   EDI = VDD control block structure ptr
	push	ecx
	call	VDD_VM_Mem_Disable
	pop	ecx
IFDEF MapMonoError
IFDEF	VGAMONO
	TestMem [edi.VDD_TFlags],<fVT_Mono OR fVT_ResvB0>
						    ; Q: B0 mapping supported?
	jnz	SHORT @F			    ;	Y: continue
	TestMem [esp],4 			    ; Q: B0 page mapped?
	jnz	SHORT @F			    ;	N: continue
	call	VDD_Error_MapMono		    ;	Y: Warn user
@@:
ENDIF
ENDIF
VIOT_VO_Grp_Save:
	pop	eax				    ; AL = VM's output value
	mov	[edi.VDD_Stt.G_SetRst][ecx],al
VIOT_VO_Grp_Exit:
	ret

; No MemC state bits changed, save value (CRTC bits might have changed)
VIOT_VO_Grp_NoMemCChg:
	pop	eax
	mov	[edi.VDD_Stt.G_SetRst][ecx],al	    ; Save changed value
	jmp	VIOT_VO_Grp_Exit

;*******
; Graphics controller data input
VIOT_In_Grp:
						    ; Q: CRTC owner?
	jnc	SHORT VIOT_VI_Grp		    ;	N: Do virtual input
	cmp	ebx,[Vid_MemC_VM]		    ; Q: MemC owner?
	jnz	SHORT VIOT_VI_Grp		    ;	N: Do virtual input

;*******
; Graphics controller physical input
VIOT_In_Grp_DoIn:
	in	al,dx
VIOT_In_Grp_NoIn:
	ret

;*******
; Graphics controller virtual input (not both MemC and CRTC owner)
VIOT_VI_Grp:
	cmp	eax,eax
	call	VDD_OEM_VI_Grp			    ; Q: OEM extension
IFDEF DEBUG_virtualization
	jc	short @F			    ;	Y: Do input
	jnz	short @F			    ;	Y: return value
	mov	al, [edi.VDD_Stt.G_SetRst][ecx]     ; return virtual value
@@:
	mov	ah, al
	dec	edx
	mov	al, cl
	out	dx, al
	IO_Delay
	inc	edx
	in	al, dx
	cmp	al, ah
	je	short @F
	xchg	al, ah
	Debug_Out "3CF read different"
@@:
ELSE
	jc	VIOT_In_Grp_DoIn		    ;	Y: Do input
	jnz	VIOT_In_Grp_NoIn		    ;	Y: return value
	mov	al, [edi.VDD_Stt.G_SetRst][ecx]     ; return virtual value
ENDIF
	jmp	VIOT_In_Grp_NoIn

EndProc VIOT_3CF


;***************     CRT controller index register
;   This is owned by CRTC owner
BeginProc VIOT_3D4,High_Freq
	jnz	SHORT VIOT_In_CRTI
	jnc	SHORT VIOT_VO_CRTI
	out	dx,al
VIOT_VO_CRTI:
	mov	[edi.VDD_Stt.C_Indx],al 	    ; Save curr index reg value
	ret

;*******
; CRTC index input
VIOT_In_CRTI:
	jnc	SHORT VIOT_VI_CRTI
	in	al,dx
	ret
VIOT_VI_CRTI:
	mov	al, [edi.VDD_Stt.C_Indx]	    ; get virtual value
	ret
EndProc VIOT_3D4

;***************     CRT controller data register
;   Owned by CRTC owner
BeginProc VIOT_3D5,High_Freq

IFDEF	VRTCTIMER
	jnz	VIOT_In_CRT
ELSE
	jnz	SHORT VIOT_In_CRT
ENDIF
	movzx	ecx,[edi.VDD_Stt.C_Indx]	    ; ECX = index
;   AL = value
;   ECX = index
;   Zero flag set, Carry flag clear
	cmp	eax,eax
	call	VDD_OEM_Out_CRTC		    ; Q: OEM specific?
IFDEF	VRTCTIMER
	jc	VIOT_Out_CRTC_OutOnly		    ;	Y: Value handled, exit
	jnz	VIOT_Out_Exit			    ;	Y: Don't do output
ELSE
	jc	SHORT VIOT_Out_CRTC_OutOnly	    ;	Y: Value handled, exit
	jnz	SHORT VIOT_Out_Exit		    ;	Y: Don't do output
ENDIF
	cmp	ebx,[Vid_CRTC_VM]		    ;	N: Q: CRTC owner?
	jnz	SHORT VIOT_Out_CRTC_NoOut	    ;	    N: Don't do output
	TestMem [Vid_Flags], fVid_MsgInit	    ; Q: Message mode init'd?
	jnz	short @F			    ;	Y: go ahead
	cmp	cl,C_IMaxIBM			    ;	N: Q: unknown OEM reg?
	jna	SHORT VIOT_Out_CRTC_NoOut	    ;	    N: Don't do output
	; If the OEM routine didn't handle this unknown register, then just do
	; the physical output of both the index and the data, which is valid
	; since this is the CRTC owner, just with MsgMode not inited yet.
	; This is required for NVIDIA GeForces which expose some weird APIs via
	; extended CRTC registers. The approach here mirrors the one used in
	; Win9x's VDD.VXD.
	Debug_Out "Output value #AL to unknown CRTC register #CL before MsgMode inited"
	dec	dl
	mov	ah,al
	mov	al,cl
	out	dx,ax
	jmp	short VIOT_Out_Exit
@@:	cmp	cl,C_AddrH-C_HTotal		    ; Q: CRTC start address chg?
	jb	SHORT VIOT_Out_CRTC_DoOut	    ;	N: continue
	cmp	cl,C_AddrL-C_HTotal
	ja	SHORT VIOT_Out_CRTC_DoOut	    ;	N: continue
	cmp	[edi.VDD_Stt.CRTC][ecx],al
	jz	SHORT VIOT_Out_CRTC_DoOut	    ;	N: continue
	mov	[edi.VDD_Stt.CRTC][ecx],al	    ;	Y: set new value and
	call	VDD_VM_Mem_Adjust_Visible_Pages     ;	    let VM MEM adjust
VIOT_Out_CRTC_DoOut:
	out	dx,al
VIOT_Out_CRTC_NoOut:
	cmp	cl,C_IMax			    ; Q: Valid index?
	ja	SHORT VIOT_Out_Exit		    ;	N: ignore the value
IFDEF	VRTCTIMER
	; check VRTC IRQ setting / status - old and new state are both important
	; (for some reason), so check before committing...
	cmp	cl,C_VRTCEnd-C_HTotal
	jne	SHORT VIOT_Out_CRTC_notIRQ
	mov	cl,[edi.VDD_Stt.CRTC][ecx]
	xor	cl,al
	test	cl,fVRTCEndIRQClr		    ; Q: toggled "IRQ clear" bit?
	jz	SHORT VIOT_Out_CRTC_IRQ_Cleared	    ;	N: next check
	test	al,fVRTCEndIRQClr		    ;	Y: Q: new value 1?
	jz	SHORT @F			    ;	    N: clear the IRQ
	ClrFlag	[edi.VDD_Stt.V_Stat0],fStt0VRTC	    ;	    Y: clear the flip-flop
	jmp	SHORT VIOT_Out_CRTC_IRQ_Cleared
@@:	call	VDD_Int_Clear_VRTC_IRQ
VIOT_Out_CRTC_IRQ_Cleared:
	mov	cl,C_VRTCEnd-C_HTotal		    ; restore CL value
	test	al,fVRTCEndIRQEna		    ; Q: IRQ Enable bit set to zero?
	jnz	SHORT VIOT_Out_CRTC_notIRQ	    ;	N: IRQ NOT enabled (yep...)
	xor	ecx,ecx				    ;	Y: ensure timer event
	call	VDD_Set_VRTC_Time_Out		    ;      exists to deliver IRQ
	mov	cl,C_VRTCEnd-C_HTotal		    ; restore CL value
VIOT_Out_CRTC_notIRQ:
ENDIF
	mov	[edi.VDD_Stt.CRTC][ecx],al
IFDEF	VRTCTIMER
	; if mode control (including SLDIV), or horizontal or vertical total
	; (latter includes an overflow bit) change, update framerate
	cmp	cl,C_Mode-C_HTotal
	je	SHORT @F
	cmp	cl,C_Ovflw-C_HTotal
	je	SHORT @F
	cmp	cl,C_HTotal-C_HTotal
	je	SHORT @F
	cmp	cl,C_VTotal-C_HTotal
	jne	SHORT VIOT_Out_Exit
@@:	call	VDD_State_Calc_Framerate
ENDIF
VIOT_Out_Exit:
	ret

VIOT_Out_CRTC_OutOnly:
	cmp	ebx,[Vid_CRTC_VM]		    ;	N: Q: CRTC owner?
	jnz	SHORT VIOT_Out_Exit		    ;	    N: Don't do output
	TestMem [Vid_Flags], fVid_MsgInit	    ; Q: Message mode init'd?
	jz	short VIOT_OUT_Exit		    ;	N:
	out	dx, al
	ret

;*******
; CRTC data input
VIOT_In_CRT:
	jnc	SHORT VIOT_VI_CRT
	in	al,dx
	ret

VIOT_VI_CRT:
	movzx	ecx, [edi.VDD_Stt.C_Indx]

	cmp	eax,eax
	call	VDD_OEM_In_CRTC
	jnz	short VIOT_VI_CRT_End
	cmp	cl,C_IMaxIBM
	jna	short @F
	; If the OEM routine didn't handle this unknown register, then just do
	; the physical output of the index and input of the data.
	; This is required for NVIDIA GeForces which expose some weird APIs via
	; extended CRTC registers. The approach here mirrors the one used in
	; Win9x's VDD.VXD.
	Debug_Out "Input from unknown CRTC register #CL"
	dec	dl
	mov	al,cl
	out	dx,al
	inc	dl
	in	al,dx
	jmp	short VIOT_VI_CRT_End

@@:	mov	al, [edi.VDD_Stt.CRTC][ecx]	    ; get virtual value
VIOT_VI_CRT_End:
IFDEF DEBUG_virtualization
	mov	ah, al
	mov	al, cl
	dec	edx
	out	dx, al
	IO_Delay
	inc	edx
	in	al, dx
	cmp	al, ah
	je	short @F
	xchg	al, ah
	Debug_Out "CRTC read different"
@@:
ENDIF
	ret

EndProc VIOT_3D5

;***************    Feature controller output/Status 1 input
;   Owned by CRTC
BeginProc VIOT_3DA,High_Freq
	jnz	SHORT VIOT_In_Stat1
	jnc	SHORT VIOT_VO_Feat
	out	dx,al
VIOT_VO_Feat:

	mov     [edi.VDD_Stt.V_Feat],al 	   ; set value
	ret

;***************    Status 1 input
;
VIOT_In_Stat1:
	jnc	SHORT VIOT_VI_Stat1
	or	[edi.VDD_Stt.A_Indx],fVAI_Indx	    ; Attr ready for index
; Even for VM's with focus, we need to fake the status because some software
;   will end up looping on this forever since interrupts and scheduling of
;   VMs may make the software not ever detect the start of VRTC.  Note that
;   this algorithm has been tuned to work with all known popular software.
;;;;	in	al, dx
;;;;	ret
VIOT_VI_Stat1:
; N Times On, M Times Toggle Algorithm:
	mov	al,[edi.VDD_Stt.V_Stat1]	    ; Get value of pseudo status
	cmp	[edi.VDD_VertCnt],0		    ; Q: In Simulated VRTC?
	je	SHORT VIOT_VI_Stt1_NotVert	    ;	N: continue
	dec	[edi.VDD_VertCnt]		    ;	Y: count down retrace
	jnz	SHORT VIOT_VI_Stt1_Merge
	and	[edi.VDD_Stt.V_Stat1],NOT fstatVRTC ; next query will be out of VRTC
IFDEF	VRTCTIMER
	xor	ecx,ecx
	call	VDD_Set_VRTC_Time_Out		    ; if timeouts lapsed, re-enable them
ENDIF
	jmp	SHORT VIOT_VI_Stt1_Merge
VIOT_VI_Stt1_NotVert:
IFDEF	VRTCTIMER
	cmp	[edi.VDD_VRTC_timeout],0	    ; Q: VRTC managed by a time-out?
	jnz	SHORT @F			    ;   Y: don't bother counting down horiz
ENDIF
	dec	[edi.VDD_HorizCnt]		    ; count down horiz
	jz	SHORT VIOT_VI_Stt1_EndHoriz	    ; End of period
; Note Most General Algorithm would have duration counter for horizontal here
@@:	xor	al,fstatEna			    ; Toggle dot stream bit
	jmp	SHORT VIOT_VI_Stt1_SaveMerge
VIOT_VI_Stt1_EndHoriz:
	mov	[edi.VDD_VertCnt],VDD_VERT_PERIOD
	mov	[edi.VDD_HorizCnt],VDD_HORIZ_PERIOD
	or	al,fstatVRTC+fstatEna		    ; Retrace Active Bits ON
VIOT_VI_Stt1_SaveMerge:
	mov	[edi.VDD_Stt.V_Stat1],al	    ; Save val of pseudo status
VIOT_VI_Stt1_Merge:
	mov	cl,al
	in	al,dx
	and	al,not mStat_IVal
	or	al,cl
	or	[edi.VDD_Stt.A_Indx],fVAI_Indx	    ; Attr ready for index
	ret
EndProc VIOT_3DA

;***************    Light pen reset or set
;
BeginProc VIOT_3DB,High_Freq
BeginProc VIOT_3DC
	jnz	VIOT_In_Undef
	jnc	short VIOT_VO_LPen	; jump if VM not CRTC
	out	dx,al
VIOT_VO_LPen:
	ret
EndProc VIOT_3DC
EndProc VIOT_3DB

VxD_CODE_ENDS

	END
