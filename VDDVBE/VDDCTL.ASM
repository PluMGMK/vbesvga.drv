	TITLE	VDD - Virtual Display Device for VGA  vers 3.1
;******************************************************************************
;
;VDD - Virtual Display Device
;
;   Author: MDW
;
;   (C) Copyright MICROSOFT Corp. 1986 - 1990
;
;DESCRIPTION:
;	This module declares the virtual device (defines the Device Declaration
;	Block or DDB) and has the VDD_Control routine for dispatching messages.
;	It also contains a number of the routines for handling the messages,
;	including VDD_Create_VM, VDD_Destroy_VM, VDD_VM_Critical_Init,
;	VDD_VM_Init, VDD_VM_Set_Device_Focus, VDD_Sys_Critical_Exit and
;	VDD_System_Exit.
;
IFDEF	PVGA
;HISTORY:
;   [1] modified for Paradise 1C which comes with 5 DIP switches.  Switch 5 is
;       used for interlace or non-interlace which does not exist on 1A and 1B
;       board.                          
;   [2] add code for Paradise 1F chip checking
;   [3] set fVid_PVGA flag when Paradise chip but not Paradise Bios Rom.
;                                               - C. Chiang - WDC -
ENDIF
;
;******************************************************************************

	.386p

.xlist
	INCLUDE VMM.INC

	Create_VDD_Service_Table EQU True

	INCLUDE VDD.INC
	INCLUDE OPTTEST.INC
	INCLUDE DEBUG.INC
	INCLUDE VDDDEF.INC
	INCLUDE PAGESWAP.INC

IFDEF	SysVMin2ndBank
Calc_TL4000_MemSize = 1
ELSE
IFDEF	EXT_VGA
Calc_TL4000_MemSize = 1
ENDIF
ENDIF

.list

;******************************************************************************
;		 V I R T U A L	 D E V I C E   D E C L A R A T I O N
;******************************************************************************

Declare_Virtual_Device VDD, 2, 0, VDD_Control, VDD_Device_ID, \
		       VDD_Init_Order,,VDD_PM_API

;******************************************************************************
; EXTRN routines
;
VxD_ICODE_SEG

IFDEF DEBUG
	EXTRN	VDD_Debug_Init:NEAR
ENDIF

; Interrupt trapping routines in VDDINT.ASM
	EXTRN	VDD_Int_Device_Init:NEAR

; Physical memory initialization in VDDPHMEM.ASM
	EXTRN	VDD_PH_Mem_Sys_Critical_Init:NEAR

; Controller state initialization in VDDSTATE.ASM
	EXTRN	VDD_State_Sys_Critical_Init:NEAR
	EXTRN	VDD_State_Device_Init:NEAR
IFDEF VGA8514
	EXTRN	VDD_State_Init_Complete:NEAR
ENDIF

; VM update initialization in VDDPROC.ASM
	EXTRN	VDD_Proc_Device_Init:NEAR

; VM memory state routines in VDDVMMEM.ASM
	EXTRN	VDD_VM_Mem_Device_Init:NEAR
	EXTRN	VDD_VM_Mem_Init_Complete:NEAR

; Initialization routine in VDDTIO.ASM
	EXTRN	VDD_TIO_Sys_Critical_Init:NEAR
	EXTRN	VDD_TIO_Device_Init:NEAR


VxD_ICODE_ENDS

VxD_CODE_SEG
; Interrupt trapping routines in VDDINT.ASM
	EXTRN	VDD_Int_Sys_Critical_Exit:NEAR

	EXTRN
IFDEF	DEBUG
; Debug query handler in VDDDEBUG.ASM
	EXTRN	VDD_DebugQuery:NEAR
ENDIF

; API handler in VDDSVC.ASM
	EXTRN	VDD_PM_API:NEAR

; Message mode handler in VDDSVC.ASM
	EXTRN	VDD_Begin_Msg_Mode:NEAR
	EXTRN	VDD_End_Msg_Mode:NEAR

; Saving dirty video memory
	EXTRN	VDD_Grab_Save_Dirty_Pages:NEAR

; Register state routines in VDDSTATE.ASM
	EXTRN	VDD_State_Create_VM:NEAR
	EXTRN	VDD_State_VM_Init:NEAR
	EXTRN	VDD_State_Destroy_VM:NEAR
	EXTRN	VDD_State_System_Exit:NEAR
	EXTRN	VDD_State_Scrn_Off:NEAR
	EXTRN	VDD_State_Scrn_On:NEAR
	EXTRN	VDD_State_Set_CRTC_Owner:NEAR
	EXTRN	VDD_State_Set_MemC_Owner:NEAR

; VM memory state routines in VDDVMMEM.ASM
	EXTRN	VDD_VM_Mem_Create_VM:NEAR
	EXTRN	VDD_VM_Mem_Destroy_VM:NEAR
	EXTRN	VDD_VM_Mem_Set_Device_Focus:NEAR
	EXTRN	VDD_VM_Mem_VM_Critical_Init:NEAR
	EXTRN	VDD_VM_Mem_VM_Suspend:NEAR
	EXTRN	VDD_VM_Mem_VM_Resume:NEAR

	EXTRN	VDD_PH_Mem_Set_Sys_Latch_Addr:NEAR

; Control call routines in VDDPROC.ASM
	EXTRN	VDD_Proc_VM_Suspend:NEAR
	EXTRN	VDD_Proc_VM_Resume:NEAR

VxD_CODE_ENDS

VxD_DATA_SEG

PUBLIC	Vid_Flags, VT_Flags
PUBLIC	Vid_CB_Off

EXTRN	Vid_Focus_VM:DWORD
EXTRN	Video_Pages:DWORD	; # of 4K by 4 plane pages (from VDDPHMEM)
EXTRN	PIF_Save:WORD

Vid_Flags	dd  ?		; global flags
VT_Flags	dd  ?		; global display type flags
Vid_CB_Off	dd  ?		; Control block offset for VDD

VxD_DATA_ENDS

VxD_CODE_SEG
;******************************************************************************
;VDD_Control
;
;DESCRIPTION:
;
;ENTRY: EAX = control code
;	EBX = VM handle
;	EBP = Client ptr
;
;EXIT:	control code specific return of carry flag indicate aborted operation
;
;USES:	All
;
;==============================================================================
Begin_Control_Dispatch VDD

	Control_Dispatch Set_Device_Focus,  VDD_Set_Device_Focus
	Control_Dispatch Begin_Message_Mode,VDD_Begin_Msg_Mode
	Control_Dispatch End_Message_Mode,  VDD_End_Msg_Mode
	Control_Dispatch VM_Suspend,	    VDD_VM_Suspend
	Control_Dispatch VM_Resume,	    VDD_VM_Resume
	Control_Dispatch Create_VM,	    VDD_Create_VM
	Control_Dispatch Destroy_VM,	    VDD_Destroy_VM
	Control_Dispatch VM_Critical_Init,  VDD_VM_Critical_Init
	Control_Dispatch VM_Init,	    VDD_VM_Init
	Control_Dispatch Sys_VM_Init,	    VDD_Sys_VM_Init
	Control_Dispatch System_Exit,	    VDD_System_Exit
	Control_Dispatch Device_Init,	    VDD_Device_Init
	Control_Dispatch Sys_Critical_Init, VDD_Sys_Critical_Init
IFDEF VGA8514
	Control_Dispatch Init_Complete,     VDD_Init_Complete
ELSE
	Control_Dispatch Init_Complete,     VDD_VM_Mem_Init_Complete
ENDIF
	Control_Dispatch Sys_Critical_Exit, VDD_Sys_Critical_Exit
IFDEF	DEBUG
	Control_Dispatch Debug_Query,	    VDD_DebugQuery
ENDIF

End_Control_Dispatch VDD

VxD_CODE_ENDS

;******************************************************************************
; Initialization data used by VDD_Sys_Critical_Init and VDD_Device_Init
VxD_IDATA_SEG
;*******
; Define instance data for instance data manager
Inst_1 InstDataStruc <,,EGA_I_Addr1,EGA_I_Len1,ALWAYS_Field> ; Video stuff
Inst_2 InstDataStruc <,,EGA_I_Addr2,EGA_I_Len2,ALWAYS_Field> ; EGA variables
Inst_3 InstDataStruc <,,EGA_I_Addr3,EGA_I_Len3,ALWAYS_Field> ; Video parms ptr
Inst_4 InstDataStruc <,,EGA_I_Addr4,EGA_I_Len4,ALWAYS_Field>
Inst_S InstDataStruc <,,SeaB_I_Addr,SeaB_I_Len,ALWAYS_Field> ; SeaBIOS stuff

;*******
; INI switch strings
	EXTRN	VDD_SVGA_Mem_Ini:BYTE
	EXTRN	VDD_VBESVGA_Sec:BYTE
	EXTRN	VDD_Bounce_Ini:BYTE
IFDEF SysVMin2ndBank
	EXTRN	VDD_2ndBank_Ini:BYTE
ENDIF

;*******
; Strings used in Fatal_Exit during initialization only
	EXTRN	VDD_Str_BadDevice:BYTE
	EXTRN	VDD_Str_BadInst1:BYTE
	EXTRN	VDD_Str_BadInst2:BYTE
	EXTRN	VDD_Str_BadInst3:BYTE
	EXTRN	VDD_Str_BadInst4:BYTE
	EXTRN	VDD_Str_BadInstS:BYTE

VxD_IDATA_ENDS

VxD_ICODE_SEG
;******************************************************************************
;VDD_Sys_Critical_Init
;
;DESCRIPTION:
;    Since interrupts are off, this must be short and sweet.  We must
;    be ready to handle message service calls after this is complete.
;    Initialize minimum amount of global data structures.  Note that
;    control block is cleared to 0 when allocated, so any routines
;    that access the control block must handle 0 values until it is
;    further initialized in Device_Init and Sys_VM_Init.
;
;ENTRY: EBX = Sys VM handle
;	EDX = reference data from real mode init
;	      DL = # of 256Kb blocks-1 available on video adapter
;	      EDX AND NOT 0FFh = initial [VT_Flags] value.
;
;EXIT:	Carry cleared or Fatal_Error called
;
;USES:	All
;
;------------------------------------------------------------------------------
BeginProc VDD_Sys_Critical_Init,PUBLIC

;*******
; Set initial value of flags from real mode INIT
;
IFNDEF	VGA8514	; VBE and 8514 detection are mutually exclusive from VDDDEF.INC
	; undo the hack we do below in VDD_Real_Init
	xor	ecx, ecx
	test	edx, fVT_VBESVGA
	jz	short @F
	xchg	cl, dh				; stash our 'S' in ECX if necessary
@@:
ENDIF

IFDEF DEBUG
mVT_trident	equ fVT_TVGA+fVT_TVGA9100
mVT_ATI 	equ fVT_ATIVGA+fVT_ATIVGA3
mVT_CLV7	equ fVT_CLVGA+fVT_CLVGA_RevC+fVT_V7VGA
ifdef	VGA8514
mVT_IBM 	equ fVT_8514+fVT_XGAbit
else
mVT_IBM 	equ fVT_VBESVGA+fVT_XGAbit
endif
mVT_paradise	equ fVT_PVGA+fVT_PVGA1F
mVT_tsenglabs	equ fVT_TLVGA+fVT_TL_ET4000

VxD_DATA_SEG
EXTRN	fVT_NameTable:BYTE
VxD_DATA_ENDS
EXTRN	VDD_Debug_Dump_Flags:NEAR

	mov	eax, edx
	xor	al, al
	test	eax, NOT (mVT_trident+mVT_ATI+mVT_CLV7+mVT_IBM+mVT_paradise+mVT_tsenglabs+fVT_CTVGA+fVT_RsrvC6C7)
	jz	short @F
	Trace_Out 'WARNING: non-zero flags passed from real mode init [', nocrlf
	mov	esi, OFFSET32 fVT_NameTable
	call	VDD_Debug_Dump_Flags
	Debug_Out ']'
@@:
ENDIF
	movsx	eax, dl 			; # of 256Kb blocks-1
	inc	eax
	jnz	short sci_got_size
	mov	eax, 256			; default to 256Kb
	mov	edi, OFFSET32 VDD_SVGA_Mem_Ini
	xor	esi, esi			; Use [Win386] section
	VMMcall Get_Profile_Decimal_Int
	add	eax, 255			; round up to 256Kb boundary
	shr	eax, 8				; convert to # of 256Kb blocks
%OUT limit video memory specification at all?
sci_got_size:
	shl	eax, 4				; # of 16Kb (4K by 4 plane) pages

IFDEF SysVMin2ndBank
IFDEF Ext_VGA
%OUT this probably doesn't work
ENDIF
IFDEF TLVGA
	test	edx, fVT_TL_ET4000		;Q: TLVGA?
	jz	short @F
	cmp	eax, 16*2			;Q: at least 2 banks of memory?
	jb	short @F			;   N:
	or	eax, TRUE
	xor	esi, esi
	mov	edi, OFFSET32 VDD_2ndBank_Ini
	VMMCall Get_Profile_Boolean
	or	eax, eax			;Q: user forced off?
	jz	short @F			;   Y:
	Trace_Out 'Running SYS VM in 2nd bank of video memory'
						;   N: run Sys VM in 2nd bank
	or	edx, fVT_SysVMnot1stBank OR fVT_SysVMin2ndBank
@@:
ENDIF
ENDIF

IFDEF Ext_VGA
IFDEF V7VGA
	TestReg edx, fVT_V7VGA			;Q: V7VGA?
	jnz	short sci_set_vp		;   Y: use reported size
ENDIF
IFDEF TLVGA
	test	edx, fVT_TLVGA or fVT_TL_ET4000 ;Q: TLVGA?
	jnz	short sci_set_vp		;  Y: use reported size
ENDIF
ENDIF

	mov	eax, 16 			;   N: force 16 pages

sci_set_vp:
	;Trace_Out 'Video_Pages=#ax'
	mov	[Video_Pages], eax

	xor	dl, dl
	mov	[VT_Flags],edx			; Init flags
	mov	[Vid_Flags],0

IFNDEF	VGA8514	; VBE and 8514 detection are mutually exclusive from VDDDEF.INC
	cmp	ecx,'S'				; SeaBIOS detected?
	jne	short @F
	SetFlag	[Vid_Flags],fVid_SeaBIOS
@@:
ENDIF

;*******
;Check if user disabled BG/FG bounce on windowed modeset
;
	or	eax, TRUE			; default = bounce
	mov	esi, OFFSET32 VDD_VBESVGA_Sec
	mov	edi, OFFSET32 VDD_Bounce_Ini
	VMMCall Get_Profile_Boolean
	not	eax				; track this as "don't bounce"
	and	eax, fVid_No_Bounce
	or	[Vid_Flags], eax

;*******
;Allocate part of VM control block for VDD usage
;
	VMMCall _Allocate_Device_CB_Area, <<SIZE VDD_CB_Struc>, 0>
	test	eax, eax
	jnz	SHORT VDD_SI_Got_CB_Area
Debug_Out "VDD ERROR:  Could not allocate control block area"
	VMMJmp	Fatal_Memory_Error
VDD_SI_Got_CB_Area:
	mov	[Vid_CB_Off], eax		; Save CB offset for VDD data

	mov	edi,ebx
	add	edi,eax 			; EDI = VDD ptr for system VM

;*******
; Init State and Physical memory data structures
;
	mov	eax,[VT_Flags]
	mov	[edi.VDD_TFlags],eax		; pass display type to VM CB
	call	VDD_State_Sys_Critical_Init	; Set up phys I/O port access
	call	VDD_PH_Mem_Sys_Critical_Init	; Set up phys memory access

	call	VDD_TIO_Sys_Critical_Init
	jc	VDD_DI_Err

	ret
EndProc VDD_Sys_Critical_Init


;******************************************************************************
;VDD_Device_Init
;
;DESCRIPTION:
;	Specify instance data, do any other initialization necessary
;
;ENTRY: EBX = Sys VM's handle
;
;EXIT:	Carry cleared or Fatal_Error called
;
;USES:	All
;
;==============================================================================
BeginProc VDD_Device_Init,PUBLIC

	TestMem [Vid_Flags], fVid_MsgInit   ;Q: Message mode state init'd?
	jz	short @F		    ;	N:
	ret				    ;	Y: we've already done this...
@@:

	pushad

IFDEF	DEBUG
	call	VDD_Debug_Init
ENDIF

	SetVDDPtr edi

IFDEF	DEBUG
;***************
; Output video display type to debug terminal

IFDEF	TLVGA
	TestMem [edi.VDD_TFlags],fVT_TLVGA
	jz	SHORT VDI_Not_TL3000
Trace_Out "Tseng Labs ET3000 support"
VDI_Not_TL3000:
	TestMem [edi.VDD_TFlags],fVT_TL_ET4000
	jz	SHORT VDI_Not_TL4000
Trace_Out "Tseng Labs ET4000 support"
VDI_Not_TL4000:
ENDIF
IFDEF	V7VGA
	TestMem [edi.VDD_TFlags],fVT_V7VGA
	jz	SHORT VDI_Not_V7
Trace_Out "Video 7 VGA support"
VDI_Not_V7:
ENDIF
IFDEF	PVGA
	TestMem [edi.VDD_TFlags],fVT_PVGA
	jz	SHORT VDI_Not_PVGA
Trace_Out "Paradise VGA support"
VDI_Not_PVGA:
	TestMem [edi.VDD_TFlags],fVT_PVGA1F
	jz	SHORT VDI_Not_PVGA1F
Trace_Out "     chip version 1F"
VDI_Not_PVGA1F:
ENDIF
IFDEF	ATIVGA
	TestMem [edi.VDD_TFlags],fVT_ATIVGA
	jz	SHORT VDI_Not_ATIVGA
Trace_Out "ATI VGA support"
VDI_Not_ATIVGA:
ENDIF
IFDEF CLVGA
	TestMem [edi.VDD_TFlags],fVT_CLVGA
	jz	SHORT @F
Trace_Out "Cirrus Logic VGA support"
@@:
	TestMem [edi.VDD_TFlags],fVT_CLVGA_RevC
	jz	SHORT @F
Trace_Out "Cirrus Logic 610/620 VGA support"
@@:
ENDIF
IFDEF NEWCLVGA
	TestMem [edi.VDD_TFlags],fVT_NEWCLVGA
	jz	SHORT @F
Trace_Out "Cirrus Logic 6410 VGA support"
@@:
ENDIF
IFDEF TTVGA
	TestMem [edi.VDD_TFlags],fVT_TVGA
	jz	SHORT VDI_Not_TVGA
Trace_Out "Trident TVGA support"
VDI_Not_TVGA:
ENDIF
	TestMem [edi.VDD_TFlags],fVT_RsrvC6C7
	jz	SHORT @F
Trace_Out "ROM Pages C6, C7 excluded"
@@:
ENDIF

IFDEF SysVMin2ndBank
;
; init latch address
;
	TestMem [VT_Flags], fVT_SysVMin2ndBank
	jz	short @F
	mov	eax, 0FFFFh
	xor	ecx, ecx
	xor	edx, edx
	call	VDD_PH_Mem_Set_Sys_Latch_Addr
@@:
ENDIF

;*******
; Set up interrupt trapping
;
	call	VDD_Int_Device_Init
	jc	VDD_DI_Err		;   If error, quit

;*******
; Set up Virtual Video memory state
;
	call	VDD_VM_Mem_Device_Init
	jc	VDD_DI_Err		;   If error, quit

;*******
; Initialize port trapping
;
	call	VDD_TIO_Device_Init
	jc	VDD_DI_Err		;   If error, quit

;*******
; Set up VM controller state
;
	call	VDD_State_Device_Init
	jc	VDD_DI_Err		;   If error, quit

;*******
; Set up VM windowed update interaction
;
	call	VDD_Proc_Device_Init

;*******
;Specify instanced RAM (BIOS data area)
;
	VMMCall _AddInstanceItem, <<OFFSET32 Inst_1>, 0>
	mov	esi,OFFSET32 VDD_Str_BadInst1
	test	eax,eax
	jz	SHORT VDD_Inst_Err
	VMMCall _AddInstanceItem, <<OFFSET32 Inst_2>, 0>
	mov	esi,OFFSET32 VDD_Str_BadInst2
	test	eax,eax
	jz	SHORT VDD_Inst_Err
	VMMCall _AddInstanceItem, <<OFFSET32 Inst_3>, 0>
	mov	esi,OFFSET32 VDD_Str_BadInst3
	test	eax,eax
	jz	SHORT VDD_Inst_Err
	VMMCall _AddInstanceItem, <<OFFSET32 Inst_4>, 0>
	mov	esi,OFFSET32 VDD_Str_BadInst4
	test	eax,eax
	jz	SHORT VDD_Inst_Err

	TestMem	[Vid_Flags],fVid_SeaBIOS
	jz	SHORT @F
	VMMCall _AddInstanceItem, <<OFFSET32 Inst_S>, 0>
	mov	esi,OFFSET32 VDD_Str_BadInstS
	test	eax,eax
	jz	SHORT VDD_Inst_Err

@@:	clc
	popad
	ret

VDD_DI_Err:
	Fatal_Error <OFFSET32 VDD_Str_BadDevice>

VDD_Inst_Err:
	; ESI has been set to the error message,
	; and EAX is zero, clearing all flags
	VMMjmp	Fatal_Error_Handler

EndProc VDD_Device_Init

IFDEF VGA8514
;******************************************************************************
;
;   VDD_Init_Complete
;
;   DESCRIPTION:
;
;   ENTRY:
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc VDD_Init_Complete

	call	VDD_VM_Mem_Init_Complete
	call	VDD_State_Init_Complete
	clc
	ret

EndProc VDD_Init_Complete
ENDIF

VxD_ICODE_ENDS

VxD_CODE_SEG

;******************************************************************************
;VDD_Create_VM
;
;DESCRIPTION:
;	Init data structures, allocate initial video memory save buffers.
;	Only error possible is failure to allocate memory.  Note that
;	Device_Init is the Create_VM for the SYSTEM VM.
;
;ENTRY: EBX = VM Handle
;
;EXIT:	CF = 1 if Error
;
;USES:	All
;
;ASSUMES:
;	VDD_PIF_State has already been called (except for SYS VM).
;
;==============================================================================
BeginProc VDD_Create_VM, PUBLIC

	SetVDDPtr   edi
	mov	ax,[PIF_Save]			; Get pre-passed PIF state
	mov	[edi.VDD_PIF],ax
	call	VDD_VM_Mem_Create_VM		; Init VM's memory state
	jc	SHORT VMC_Ex			; If error, quit

	call	VDD_State_Create_VM		; Init VM's controller state

	clc					; return with no error
VMC_Ex:
	ret
EndProc VDD_Create_VM

;******************************************************************************
;
;   VDD_Sys_VM_Init
;
;   DESCRIPTION:
;
;   ENTRY:
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc VDD_Sys_VM_Init

	call	VDD_VM_Init
	SetFlag [Vid_Flags], fVid_SysVMI
	ret

EndProc VDD_Sys_VM_Init


;******************************************************************************
;VDD_VM_Init
;
;DESCRIPTION: Initialize VM's memory, enable/disable I/O port trapping and
;	      initialize device state by calling INT 10.
;
;ENTRY: EBX = VM Handle
;
;EXIT:	CF = 1 if error
;
;USES:	All
;
;==============================================================================
BeginProc VDD_VM_Init

	SetVDDPtr   edi

	call	VDD_State_VM_Init		; State Init

	clc
	ret
EndProc VDD_VM_Init


;******************************************************************************
;
;    VDD_Set_Device_Focus
;
;    DESCRIPTION:
;	    Is called when switching the display focus.
;
;    ENTRY: EBX = VM Handle of VM to switch display focus to
;
;    EXIT:  CF = 0
;
;    USES:  All
;
;
;   VDD_Ctl_Set_Focus
;
;   DESCRIPTION:
;
;   ENTRY:  EBX = VM Handle of VM to switch display focus to
;	    EDI -> VM's VDD CB data
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc VDD_Set_Device_Focus

	test	edx, edx			;Q: Critical set focus call?
	je	SHORT VSF_00			;   Y: Do it
	cmp	edx, VDD_Device_ID		;   N: Q: VDD set focus?
	jne	VSF_Ex			;	   N: Nothing to do
VSF_00:

	cmp	ebx, [Vid_Focus_VM]		;Q: VM already has focus?
	je	VSF_Ex				;   Y: Nothing to do

VDD_Ctl_Delayed_Set_Focus:

IFDEF	PVGA
   ;
   ; On Western Digital VGA cards a switch between VMs in
   ; certain mode combinations, leads to "wrong" saving of video
   ; memory if the saving is not done at this time.
   ;
	TestMem	[VT_Flags],fVT_PVGA
	jz	SHORT SkipPVGASave
	pushad
	mov	ebx,[Vid_Focus_VM]
	VMMCall	Test_Sys_VM_Handle
	je	SHORT SkipSaveDirtyPages
	SetVDDPtr edi
	call	VDD_Grab_Save_Dirty_Pages	; grab it
SkipSaveDirtyPages:
	popad
SkipPVGASave:
ENDIF

	SetVDDPtr   edi
	
	mov	[Vid_Focus_VM], ebx
	TestMem [Vid_Flags], fVid_MsgA		;Q: are we in msg mode?
	jnz	SHORT VSF_Ex			;   Y: postpone until end msg mode
	TestMem [Vid_Flags], fVid_Crit		;Q: OK to set focus now?
	jnz	SHORT VSF_Busy			;   N: Do it when leave crit sec

BeginProc VDD_Ctl_Set_Focus
	call	VDD_State_Scrn_Off		; So display is not haywire
						;   during VM mem restore
	call	VDD_State_Set_CRTC_Owner
	call	VDD_VM_Mem_Set_Device_Focus	; Release display mem owner
						;   and restore new VMs mem
	call	VDD_State_Set_MemC_Owner	; Set up ctlr state
	call	VDD_State_Scrn_On
VSF_Ex:
	clc
	ret

EndProc VDD_Ctl_Set_Focus

VSF_Busy:
	SetFlag [Vid_Flags],fVid_SFPending	; Indicate Set Focus pending
	jmp	VSF_Ex

EndProc VDD_Set_Device_Focus


;******************************************************************************
;
;   VDD_Ctl_End_Dsp_Crit
;
;   DESCRIPTION:    Handle a pending set focus, if necessary
;
;   ENTRY:	    nothing
;
;   EXIT:	    nothing
;
;   USES:	    EBX, EDI, flags (possibly more)
;
;==============================================================================
BeginProc VDD_Ctl_End_Dsp_Crit

	btr	[Vid_Flags], bVid_SFPending ;Q: set focus pending?
	jc	short sf_pending
	ret

sf_pending:
	mov	ebx, [Vid_Focus_VM]
	jmp	VDD_Ctl_Delayed_Set_Focus

EndProc VDD_Ctl_End_Dsp_Crit



;******************************************************************************
;VDD_Destroy_VM
;
;DESCRIPTION:
;	Deallocate the pages used for video ram.
;
;ENTRY: EBX = VM Handle of VM that is being destroyed
;
;EXIT:	CF = 0
;
;USES:	All
;
;==============================================================================
BeginProc VDD_Destroy_VM,PUBLIC

	SetVDDPtr   edi

	call	VDD_State_Destroy_VM		; Release resources
	call	VDD_VM_Mem_Destroy_VM		; Release resources

	clc
	ret
EndProc VDD_Destroy_VM

;******************************************************************************
;VDD_VM_Suspend
;
;DESCRIPTION:
;
;ENTRY: EBX = VM Handle of VM that is being suspended
;
;EXIT:	CF = 0
;
;USES:	All
;
;==============================================================================
BeginProc VDD_VM_Suspend

	SetVDDPtr   edi

	call	VDD_Proc_VM_Suspend
	call	VDD_VM_Mem_VM_Suspend		; Unlock VM's memory

	clc
	ret
EndProc VDD_VM_Suspend

;******************************************************************************
;VDD_VM_Resume
;
;DESCRIPTION:
;
;ENTRY: EBX = VM handle of VM to resume
;
;EXIT:	CF = 1 if cannot resume
;
;USES:	All
;
;==============================================================================
BeginProc VDD_VM_Resume

	SetVDDPtr   edi

	call	VDD_VM_Mem_VM_Resume		; Q: VM's save memory locked?
	jc	SHORT VVMR_Fail 		;   N: Exit with fail to resume
	call	VDD_Proc_VM_Resume

	clc
VVMR_Fail:
	ret
EndProc VDD_VM_Resume


;******************************************************************************
;VDD_System_Exit
;
;DESCRIPTION: Initialize VM's memory, enable/disable I/O port trapping and
;	      initialize device state by calling INT 10.
;
;ENTRY: EBX = VM Handle
;
;EXIT:	CF = 0
;
;USES:	All
;
;==============================================================================
BeginProc VDD_System_Exit

	SetVDDPtr   edi

	call	VDD_State_System_Exit	    ; Return VM video state to normal

	clc
	ret
EndProc VDD_System_Exit


;******************************************************************************
;VDD_Sys_Critical_Exit
;
;DESCRIPTION:
;	Restore original system VM state
;
;ENTRY: nothing
;
;EXIT:	nothing
;
;USES:	All
;
;==============================================================================
BeginProc VDD_Sys_Critical_Exit

	SetVDDPtr   edi

	call	VDD_Int_Sys_Critical_Exit

	ret

EndProc VDD_Sys_Critical_Exit


;******************************************************************************
;VDD_VM_Critical_Init
;
;DESCRIPTION:
;	Finish setting up VM for execution
;
;ENTRY: EBX = VM's handle
;
;EXIT:	CF = 0
;
;USES:	All
;
;==============================================================================

BeginProc VDD_VM_Critical_Init, PUBLIC

	SetVDDPtr   edi

	call	VDD_VM_Mem_VM_Critical_Init

	clc
	ret
EndProc VDD_VM_Critical_Init


VxD_CODE_ENDS

;******************************************************************************
;******************************************************************************
;
; Real mode initialization code
;
;******************************************************************************

VxD_REAL_INIT_SEG


;******************************************************************************
;
;   VDD_Real_Init
;
;   DESCRIPTION:
;	This does some detection of video hardware/software and returns
;	an initial value for VT_Flags
;
;   ENTRY:
;	AX = VMM version number
;	BX = flags (see VMM.INC)
;	SI = environment segment
;	EDX = reference data when device specified from INT 2F (not applicable)
;
;   EXIT:
;	AX = Device_Load_Ok
;	BX = 0
;	EDX = Initial value for VT_Flags
;
;   USES:
;	Flags, AX, BX, CX, DX, BP, SI, DI
;
;==============================================================================
IFDEF	PVGA
str_Paradise	DB  "PARADISE"
len_str_Paradise EQU $-str_Paradise
str_WDIGITAL	DB  "WESTERN DIGITAL"
len_str_WDIGITAL EQU $-str_WDIGITAL
; followings are for Paradise 1F chip check 	- C. Chiang 
bSave0F		db	0	; Unlock\Lock PR0-PR4
bSave29		db	0	; Unlock\Lock PR11-PR17
bSave34		db	0	; Unlock\Lock Flat Panel
bSave35		db	0	; Unlock\Lock Mapping Ram
str_PVGA1F      db     "OPYRIGHT1990WDC"
len_str_1F      equ     $-str_PVGA1F
str_PVGA1FC     db     "OPYRIGHTWD90C22"
len_str_1FC     equ     $-str_PVGA1FC
str_1F_GEN      db      "WD90C2"
len_str_GEN     equ     $-str_1F_GEN
String          db      len_str_1F dup(?)
ENDIF
IFDEF	ATIVGA
ATI_Sig:	DB  " 761295520"    ; ATI signature at in ROM at offset 30
ATI_Sig_Len	EQU $-ATI_Sig
ENDIF
IFDEF TTVGA
TVGA_Sig	DB	"TRIDENT MICROSYSTEMS"
TVGA_Sig_Len	EQU	$-TVGA_Sig
ENDIF

BeginProc VDD_Real_init

	mov	ax, 1130h
	mov	bh, 2
	int	10h		    ; es:bp -> ROM font, so use es as ROM segment

;********************************
; VGA real mode adapter detection
;	Note that individual adapter detection routines must either
;	jump to VRI_Exit with EDX = VT_Flags value or preserve
;	the ES and DX register.  ES is the adapter ROM segment (usually C000h)
;	and DX is the status register port address (for resetting the
;	attribute controller index/value toggle).

;*******
; Load status port value in DX
;	This is to prevent duplication in OEM specific detection
;
IFDEF VGAMONO
	mov	dx,pMiscIn
	in	al,dx
	test	al,1
	mov	dl,(pStatColr AND 0FFh)
	jnz	SHORT VSI_Colr
	mov	dl,(pStatMono AND 0FFh)
VSI_Colr:
ELSE
	mov	dx,pStatColr
ENDIF

IFNDEF	VGA8514	; VBE and 8514 detection are mutually exclusive from VDDDEF.INC
	push	es
	push	cs
	pop	es
	mov	ax,4F00h	; get VBE adapter info
	lea	di,VESAInfoStruct
	int	10h
	pop	es
	cmp	al,4Fh		; function supported?
	jne	@F

	; we have VRAM in 64k blocks, convert to 256k blocks and stuff it into DL
	movzx	edx,cs:[VESATotMem]
	shr	dx,2		; convert from 64k to 256k
	dec	dl		; need #blocks minus one
	or	edx,fVT_VBESVGA

	; detect SeaBIOS because we have to setup extra instance data for that...
	push	es
	les	di,cs:[VESAOEM]
	lea	si,SeaBIOS_name
	cld
	mov	cx,SeaBIOS_len
	repe	cmps byte ptr cs:[si],es:[di]
	pop	es
	jne	VRI_Exit	; not SeaBIOS, don't detect anything else
	; This is a little unorthodox... Let's set the fVT_VBESVGA flag as normal,
	; and then ALSO set DH to 'S' to indicate that it's specifically SeaBIOS
	; VBE. As long as the PM code checks this before checking anything else,
	; and normalizes the flags, we *should* be OK...
	.errnz	0FF00h AND fVT_VBESVGA	; ensure fVT_VBESVGA is not part of DH
	mov	dh,'S'
	jmp	VRI_Exit	; don't detect anything else!

VESAInfoStruct	label byte
VESASig		db "VBE2"
VESAVer		label word
VESAMinVer	db ?
VESAMajVer	db ?
VESAOEM		dd ?
VESACaps	dd ?
VESAModes	dd ?
VESATotMem	dw ?	; total video memory in 64k blocks
VESAOEMVer	label word
VESAOEMMinVer	db ?
VESAOEMMajVer	db ?
VESAVendor	dd ?
VESAProduct	dd ?
VESAProductRev	dd ?
VESAAFVer	label word
VESAAFMinVer	db ?
VESAAFMajVer	db ?
VESAAFModes	dd ?
VESAScratch1	db 216 dup (?)
VESAScratch2	db 100h dup (?)

SeaBIOS_name	db "SeaBIOS"
SeaBIOS_len	equ $-SeaBIOS_name

@@:
ENDIF

IFDEF	GENVGA
;*******
; Genoa SuperVGA detection
;
	mov	bx,WORD PTR ES:[0037h]
;
; If there is no ROM at this address, then we need to validate that BX is
; something reasonable, because some pmode guys do not emulate segment
; wrap correctly.
;
	cmp	bx, 0FFFCh
	ja	SHORT Not_GENVGA
	mov	eax,ES:[bx]
	cmp	eax,66991177h
	je	SHORT Is_GENVGA
	cmp	eax,66992277h
	jnz	SHORT Not_GENVGA

; It is a GENOA VGA
Is_GENVGA:
	mov	edx,fVT_RsrvC6C7    ; GENOA SuperVGA
%OUT determine adapter memory size for Genoa
	mov	dl, -1	    ; flag as unknown for now
	jmp	VRI_Exit
Not_GENVGA:
ENDIF

IFDEF	V7VGA
;*******
;
; check for any V7 board
;
	push	dx
	xor	bx,bx		; clear it out
        mov     ax,6f00h
	int	10h
	cmp	bx,'V7'         ; any of the products?
	jnz	SHORT VRI_NotV7 ; nope...
;
; check the chip version #
;
	mov	cx,0ffffh
	mov	ax,06f07h	; get the # from the bios
	int	10h
	xor	dx,dx		; Assume no flags passed in
	or	cx,cx		; zero?
	jne	SHORT VRI_NotV7
	cmp	bh,70h		; V7VGA chip?
	jl	SHORT VRI_NotV7 ; nope...  must be in range 70h-7fh
;
; if we get here it is a video seven board with all the trimmings
;
; well, it's a VRAM, Fastwrite, or 1024i
;
	add	sp,2		; Throw away DX on stack
	mov	edx,fVT_V7VGA OR fVT_RsrvC6C7 ; DX = Video 7, reserve C6,c7
	and	ah, 01111111b	; clear bit 7, DRAM/VRAM indicator
	mov	dl, ah		;   so dl = # of 256Kb blocks of video memory
	dec	dl
	jz	VRI_Exit

IFDEF Ext_VGA
%OUT this isn't correct for all V7 cards
%OUT Does bank enable belong here? We do set mode INT 10s later on...
;
; turn on banking so we can access additional memory
;
	push	dx
	mov	dx, pSeqIndx
	mov	ax, 0EA06h
	out	dx, ax
	mov	al, 0FFh
	out	dx, al
	inc	dl
	in	al, dx
	or	al, 10h 		; force banking enabled
	out	dx, al
	pop	dx
ENDIF

	jmp	VRI_Exit

VRI_NotV7:
	pop	dx
ENDIF ; V7VGA

IF TTVGA
;*******
; Trident TVGA detection
;
;	Try to find "TRIDENT MICROSYSTEMS" from ROM BIOS.
;	Search C000h. If not found, try E000h, some motherboard makers
;	put our BIOS there.
;	- Trident, Henry Zeng
;
	lea	si, TVGA_Sig
	xor	di, di
	mov	cx, 128
SearchTrident:
	push	si
	push	di
	push	cx
	mov	cx, TVGA_Sig_Len
	repe	cmpsb  			; ? Trident
	pop	cx
	pop	di
	pop	si
	jz	short ISTVGA		; Gotcha!
	inc	di
	loop	SearchTrident
	jmp	short NotTVGA

public IsTVGA
IsTVGA:
	mov	edx, fVT_TVGA OR fVT_RsrvC6C7 ; Trident TVGA, reserve C6,c7

	; Check if TVGA9100
	push	dx     			; ? version # (3C5.B) == 93h
	mov	dx, 03C4h
	mov	al, 0Bh
	out	dx, al
	inc	dx
	in	al, dx
	pop	dx
	cmp	al, 93h
	jnz	short @f
	or	edx, fVT_TVGA9100	; Is TVGA9100
@@:
	jmp	VRI_Exit

NotTVGA:				; The other guy
			
ENDIF ; TTVGA

IFDEF	PVGA
;*******
; Paradise VGA detection
;
; [1]
; Paradise 1C has 5 DIP switches, not 4 any more.  The 5th switch
; controls if interlace or non-interlace is used.  Register 3CE.0F
; bit 0-2 used for lock/unlock PR0-PR4, bit 3-7 used to return
; DIP switch information.  This affects flag fvid_pvga used for other
; modules if paradise is selected.              - C. Chiang -        
;
	push	dx
	mov	dl,(pGrpIndx AND 0FFh)
	mov	al,0Fh
	out	dx,al
	inc	dx
	in	al,dx
	push	ax
;;;	and	al,0F0h
	and	al,0F8h                         
	mov	ah,al
;;;	xor	al,0F0h 			; Reverse upper 4 bits
	xor	al,0F8h 			; Reverse upper 5 bits
	or	al,5
	out	dx,al
	IO_Delay
	in	al,dx
	xor	al,ah				; Q: Are lower bits 5 and
	cmp	al,5				;	upper bits unchanged?
	pop	ax
	out	dx,al				; Restore original value
	jnz	NotPVGA 			;   N: Must not be PVGA
; Paradise VGA, check for Paradise VGA ROM
	mov	si,OFFSET str_Paradise
	xor	di,di
	mov	cx,128
	mov	edx,fVT_PVGA			; Assume not Paradise ROM
PVGA_FindROMLoop:
	push	di
	push	si
	push	cx
	mov	cx,len_str_Paradise
	repe cmpsb				; Q: Paradise ROM?
	pop	cx
	pop	si
	pop	di
	jz	SHORT IsPVGARom 		;   Yes
	inc	di
	loop	PVGA_FindROMLoop		;   No, look thru 128 bytes
; PARADISE not found, now look for WESTERN DIGITAL
	mov	si,OFFSET str_WDIGITAL
	xor	di,di
	mov	cx,128
PVGA_FindROMLoop1:
	push	di
	push	si
	push	cx
	mov	cx,len_str_WDigital
	repe cmpsb				; Q: Paradise ROM?
	pop	cx
	pop	si
	pop	di
	jz	SHORT IsPVGARom 		;   Yes
	inc	di
	loop	PVGA_FindROMLoop1		;   No, look thru 128 bytes

        ;--------------------------------------------------------------------
        ; [3] It is Paradise Chip, but not Paradise BIOS ROM.  In this case,
        ;     set the flag to fVid_PVGA in order for OEMs who use their own 
        ;     BIOS and our Chip to work properly.       - Chiang -
        ;---------------------------------------------------------------

	mov	edx,fVT_PVGA			;***Chiang

	jmp	SHORT PVGA_getsize
IsPVGARom:
	mov	edx,fVT_PVGA OR fVT_RsrvC6C7
PVGA_getsize:
IFDEF EXT_VGA
	mov	eax, edx			; save flags
	mov	dx, pGrpIndx
	mov	al, 0Bh
	out	dx, al
	IO_Delay
	inc	dl
	in	al, dx
	shr	al, 6				; bits 6 & 7 specify mem size
	mov	bl, al
	xor	bh, bh
	mov	al, cs:[bx+PVGA_MemTable]
	mov	edx, eax			; ref data = flags & mem size
ELSE
	mov	dl,0				; 256k
ENDIF

;------------------------------------------------------------------S
;  [2] following are for Paradise chip type checking     - C. Chiang -
;------------------------------------------------------------------

Chk_1F:

	push	es

        ; SAVE 3CE.0F
	mov	dx, 3CEh
	mov	al, 0Fh
	out	dx, al
	inc	dx
	in	al,dx		; Read 3CF.F
	mov	bSave0F, al	; Save the lock register state


        ; get 3D4 or 3b4

	xor	ax, ax
	mov	es, ax
	mov	dx, es:463h	; Fetch the register address to use
        mov     ax, ds          ; DS = ES
        mov     es, ax
	mov	cx, len_str_1F
	lea	di, String	; Get the String ptr;******************
 	mov	bx, 31h

;--- For 1F we need to unlock\lock the regs:
;---   3?4.29 - Unlock PR11-PR17
;	mov	al, 29h		; Select PR10
;	out	dx, al
;	inc	dx
;	in	al, dx		; Read the contents
;	mov	bSave29, al	;   and save it
;	mov	al, 80h		; Unlock the date code register
;	out	dx, al
;	dec	dx

;---   3?4.34 - Lock Flat Panel
	mov	al, 34h		; Select PR1B
	out	dx, al
	inc	dx
	in	al, dx		; Read the contents
	mov	bSave34, al	;   and save it
	mov	al, 0		; Lock the flat panel
	out	dx, al
	dec	dx

;---   3?4.35 - Lock Mapping Ram
	mov	al, 35h		; Select PR30
	out	dx, al
	inc	dx
	in	al, dx		; Read the contents
	mov	bSave35, al	;   and save it
	mov	al, 0		; Lock the mapping ram
	out	dx, al
	dec	dx


loopit:	mov	al, bl		; Loop to read the chip ID
	out	dx, al
	inc	dx
	in	al, dx
	stosb
	dec	dx
	inc	bx
	loop	loopit


;--- For 1F we need to restore the regs

;---   3?4.35 - Lock Mapping Ram
	mov	al, 35h		; Select PR30
	out	dx, al
	mov	al, bSave35	;   and restore it
	cmp	al, 30h		; If wasn't unlocked
	jne	SHORT skip1		;   then leave alone
	inc	dx
	out	dx, al
	dec	dx
skip1:

;---   3?4.34 - Lock Flat Panel
	mov	al, 34h		; Select PR1B
	out	dx, al
	mov	al, bSave34	;   and restore it
	cmp	al, 0A6h		; If wasn't unlocked
	jne	SHORT skip2		;   then leave alone
	inc	dx
	out	dx, al
	dec	dx
skip2:

;--- IT TURNS OUT THAT THE BIOS NEVER LOCKS THESE
;---   3?4.29 - Unlock\lock PR11-PR17
;	mov	al, 29h		; Select PR10
;	out	dx, al
;	inc	dx
;	mov	al, bSave29	;   and restore it
;	out	dx, al
;	dec	dx

;--- Restore the state of the lock/unlock register: 3CF.F
exit_pgm:
	mov	dx, 3CEh
	mov	al, 0Fh
	out	dx, al
	inc	dx
	mov	al, bSave0F	; Restore lock/unlock status
	out	dx, al

;--- Now, the chip signature is in String

	mov	si, OFFSET str_PVGA1F   ; check string "OPYRIGHT1990WDC"
        mov     di, OFFSET String
        mov     cx, len_str_1F
	repe cmpsb				; Q: 
        jz      SHORT isPVGA1F
	mov	si, OFFSET str_PVGA1FC  ; check string "OPYRIGHTWD90C22"
        mov     di, OFFSET String
        mov     cx, len_str_1FC
	repe cmpsb				; Q: 
        jz      SHORT isPVGA1F
	mov	si, OFFSET str_1F_GEN  ; check string "OPYRIGHTWD90C22"
        mov     di, OFFSET String
        mov     cx, len_str_GEN
	repe cmpsb				; Q: 
        jnz     SHORT Exit_1F_check
isPVGA1F:        
	or	edx, fVT_PVGA1F                 ; set flag for Paradise 1F chip
Exit_1F_check:
	xor	dx, dx
	.errnz	(fVT_PVGA OR fVT_PVGA1F OR fVT_RsrvC6C7) AND 0FFFFh
	pop	es

        ;----------------------------------------------
        ;       end of Paradise 1F chip checking       
        ;----------------------------------------------

	add	sp,2				; discard saved DX
	jmp	VRI_Exit

PVGA_MemTable	label byte
	db	0		; 00 = 256Kb
	db	0		; 01 = 256Kb
	db	1		; 10 = 512Kb
	db	3		; 11 = 1024Kb

NotPVGA:
	pop	dx
ENDIF ; PVGA

IFDEF	ATIVGA
	push	dx
	push	bp
	mov	ax,1203h
	mov	bx,5506h
	mov	bp,0ffffh
	int	10h
	cmp	bp,0ffffh
	pop	bp
	je	short Not_ATI_VGA
	mov	si,OFFSET ATI_Sig
	mov	di,30h
	mov	cx, ATI_Sig_Len
	rep cmpsb
	jnz	SHORT Not_ATI_VGA
; Further checks for version of ATI VGA
	cmp	es:byte ptr [40h],'3'		;VGAWONDER product code ?
	jne	SHORT Not_ATI_VGA
	add	sp,2
	mov	edx,fVT_ATiVGA
	cmp	es:byte ptr [43h],'1'		;VGAWONDDER V3 ?
	jne	VRI_Exit
	or	edx,fVT_ATiVGA3
	jmp	VRI_Exit
Not_ATI_VGA:
	pop	dx
ENDIF ;ATIVGA

IFDEF	TLVGA
;*******
; Tseng Labs VGA detection
;	Attribute Controller Reg 16h is known to exist only on Tseng Labs VGA
;
	push	dx
	mov	bl,0			;ET3000/ET4000 flag (0=ET3000)
	mov	dx, 3BFh
	xor	al, al
	out	dx, al
	pop	dx
	push	dx
	sub	dl, pStatColr-03D8h	; mode control register is 3B8 or 3D8
	in	al, dx
	test	al, 01000000b		;Q: writing 0 to 3BF cleared bit 6 of
					;   mode control port?
	jnz	SHORT tlvga_2		;   N: not ET4000
	mov	dx, 3BFh
	mov	al, 10b
	out	dx, al
	pop	dx
	push	dx
	sub	dl, pStatColr-03D8h	; mode control register is 3B8 or 3D8
	IO_Delay
	in	al, dx
	test	al, 01000000b		;Q: writing 10b to 3BF set bit 6 of
					;   mode control port?
	jz	SHORT tlvga_2	 	;   N: not ET4000
					;   Y: possibly an ET4000

	mov	bl,1			;flag ET4000 not ET3000
;
; attempt to write ET4000 "KEY"
;
	mov	dx, 3BFh
	mov	al, 3
	out	dx, al
	pop	dx
	push	dx
	sub	dl, pStatColr-03D8h	; mode control register is 3B8 or 3D8
	in	al, dx
	mov	ah, al
	IO_Delay
	mov	al, 0A0h
	out	dx, al
tlvga_2:
	pop	dx
	push	dx
	push	ax
	push	bx
	call	Check_Writing_ATC16	;sets ECX=0 or VT_Flags for ET3000
	pop	bx
	pop	ax
	sub	dl, pStatColr-03D8h	; mode control register is 3B8 or 3D8
	mov	al, ah
	out	dx, al			; restore mode control register
	mov	dx,03BFh
	mov	al,1
	out	dx,al			;restore 3BF to normal value
	or	ecx,ecx
	jz	SHORT Not_TLVGA 	; jump if not ET3000/ET4000
;
	pop	dx
	or	bl,bl			;test if ET4000
	jnz	short tlvga_4
	;is an ET3000:
	mov	cl,0			;256k
IFDEF EXT_VGA
	call	chk_mem_512		;rets Z=1 if have 512k
	jnz	short tlvga_gotsize
	mov	cl,1			;512k
ENDIF
	jmp	short tlvga_gotsize
tlvga_4:
	;is an ET4000:
	mov	ecx,fVT_TL_ET4000+0    ;if ET4000 with 256k

IFDEF Calc_TL4000_MemSize
;
; try to read ET4000 memory size
;
	sub	dl, pStatColr-pCRTCIndxColr
	mov	al, 37h
	out	dx, al
	inc	dl
	in	al, dx
	mov	cl,0
	test	al,8
	jz	short tlvga_gotsize	;size=256k if have 64kx4 memory chips
	mov	cl, al
	and	cl, 11b 		; isolate memory bus width
	jz	short tlvga_gotsize
	cmp	cl, 11b 		;Q: 32 bit?
	je	short tlvga_gotsize	;   Y: return size=1Mb
	dec	cl
	jz	short tlvga_gotsize	;   N: if cl was 1, return size=256Kb
	test	al, 80h 		;Q: VRAM memory?
	jz	short tlvga_gotsize	;   N: cl was 2, so return size=512Kb
	call	tst_vram_1meg		;rets Z=1 if 1 Meg
	jnz	short tlvga_gotsize
	mov	cl,3
ENDIF

tlvga_gotsize:
	mov	edx,ecx
	jmp	VRI_Exit

Not_TLVGA:
	pop	dx
ENDIF ; TLVGA

IFDEF   CLVGA        
;*******
; Cirrus Logic VGA detection
;
; First save SR6 and SRIndx
	push	dx
	xor	cx,cx			; assume not CLVGA
	mov	dl,(pSeqIndx AND 0FFh)
        in      al,dx
        IO_Delay
	mov	bh,al			; BH = SR index
        mov     al,6
        out     dx,al
	IO_Delay
	inc	dx
        in      al,dx                    
        IO_Delay
	mov	bl,al			; BH=SRindx,BL=SR6 value

;enable extension register in the CLVGA
	mov	ecx,fVT_CLVGA	       ; ECX = potential VT_Flags

	mov	al,0ECh                 ; extension enable value
        out     dx,al        
	IO_Delay

        in      al,dx
	IO_Delay
	cmp	al,1			; Q: Could enable Ext?
	jnz	SHORT Not_CLVGA
; now check to see if we can disable the extensions        
	mov	al,0CEh                 ; extension disable value
        out     dx,al        
	IO_Delay

        in      al,dx
	IO_Delay
	and     al,al                   ; Q: extensions disabled successfully?
	jnz	SHORT Not_CLVGA 	; N: no, not a CL chipset
					  ; Y: its Cirrus logic


; we know its a Cirrus chipset, now find out if it is a 610/620 Rev. C.
; chipset.
;
	push	ecx		; save flag value
	push	dx
	mov	ah,12h
	mov	bl,80h
	int	10h		; Inquire VGA type
	cmp	al,3		; returns 3 for 610/620 LCD controller
	jnz	short Not610
; its a 610/620, now find out if its RevC or not.
	cmp	bl,80h
	jz	short CheckChip
	cmp	bl,2
	jnz	short Not610
IsRevC:
	mov	eax,fVT_CLVGA_RevC
	jmp	short Done610
CheckChip:
	mov	dx,3c4h
	mov	al,8eh
	out	dx,al
	inc	dx
	in	al,dx		; 8Eh is chip revision.
	cmp	al,0ach
	jz	IsRevC
Not610:
	xor	eax,eax
Done610:
	pop	dx
	pop	ecx
	or	ecx,eax
	jmp	short Restor_CLVGA	; all done, now get outa here


Not_CLVGA:
	xor	ecx,ecx 		; Indicate not CL VGA
Restor_CLVGA:
	dec	dx
        mov     al,6
        out     dx,al           
	IO_Delay
	mov	al,bl                   ; old value of SR6
	or	ecx,ecx 		; Q: CL VGA?
	jz	SHORT Restor_SR6	;   N: output value read
	mov	bl,0ECh
Restor_Ena:
	or	al,al			; Q: extensions enabled?
	mov	al,bl			;	AL = 0ECh (enable)
	jnz	SHORT Restor_SR6	;   Y: output enable value
	ror	al,4			;   N: output disable (0CEh)

Restor_SR6:
	inc	dx
	out	dx,al			; Restore value of SR6
	IO_Delay
	mov	al,bh
	dec	dx
	out	dx,al			; Restore index
	IO_Delay
	or	ecx,ecx
	jz	SHORT Is_Not_CLVGA
	add	sp,2
IFDEF EXT_VGA
%OUT determine adapter memory size for Cirrus Logic
	mov	cl, -1	    ; flag as unknown for now
ELSE
	mov	cl,0	    ; 256k
ENDIF
	mov	edx,ecx
	jmp	SHORT VRI_Exit
Is_Not_CLVGA:
	pop	dx
ENDIF ; CLVGA

IFDEF NEWCLVGA
        xor     ecx,ecx         ; assume not CLVGA
        mov     dx,3ceh         ; graphics controller
        in      al,dx
        mov     ah,al           ; AH = SR index
        mov     al,0Ah
	IO_Delay
        out     dx,al

        inc     dx

	IO_Delay
        in      al,dx                    
        push    ax             ; AH = GR index, AL = GR0a value

        mov     al,0CEh
	IO_Delay
        out     dx,al
	IO_Delay
        in      al,dx                   ;
        cmp     al,0
        jnz     short NotNewCirrus
        mov     al,0ECh
	IO_Delay
        out     dx,al
	IO_Delay
        in      al,dx
        cmp     al,1                    ; leave extensions enabled!
        jnz     short NotNewCirrus            
        
        mov     ecx,fVT_NEWCLVGA
NotNewCirrus:
        pop     ax                     ; ah, index, al gr0a value
	IO_Delay
        out     dx,al           ; gr0a value, not written if new cirrus chips
        dec     dx
        mov     al,ah
	IO_Delay
        out     dx,al

	mov	edx,ecx
	or	edx,edx
        jnz     SHORT VRI_Exit
 
ENDIF ; NEWCLVGA

	xor	edx,edx
;
; DX = initial flags for VDD
;	Add in fVT_Mono if video currently in mono mode
;
VRI_Exit:
	push	dx
	mov	ax,0F00h
	int	10h			; Get BIOS mode
	pop	dx
	cmp	al,7			; Q: Mono text mode?
	je	SHORT VRI_Mono		;   Y: Assume want Mono VGA support
	cmp	al,0Fh			; Q: Mono graphics mode?
	jne	SHORT VRI_NotMono	;   N: Assume do not want Mono VGA
VRI_Mono:
	or	edx,fVT_Mono	       ; Probably want Mono VGA support
VRI_NotMono:
	xor	bx,bx			; No pages to exclude
	mov	si,bx			; No instance data
	mov	ax, Device_Load_Ok	; Continue with load
	ret

EndProc VDD_Real_init


IFDEF	TLVGA
;******************************************************************************
;
;   Check_Writing_ATC16
;
;   DESCRIPTION:
;
;   ENTRY:	    DX = status port
;
;   EXIT:	    ECX = 0, if NOT TLVGA, else (fVT_TLVGA OR fVT_RsrvC6C7)
;
;   USES:	    AX, BX, ECX, Flags
;
;==============================================================================
BeginProc Check_Writing_ATC16

	push	dx
	in	al,dx
	IO_Delay
	mov	dl,(pAttr AND 0FFh)
	in	al,dx
	mov	bh,al				; BH = current Attr index
	IO_Delay
	mov	al,16h+20h			; Select 16h (leave video on)
	out	dx,al
	IO_Delay
	inc	dx
	in	al,dx
	IO_Delay
	dec	dx
	mov	bl,al				; Save current reg 16h in BL
	xor	al,10h				; Complement bit 4
	out	dx,al				; Write it out
	IO_Delay
	pop	dx
	push	dx
	in	al,dx
	mov	dl,(pAttr AND 0FFh)
	mov	al,16h+20h			; Select 16h (leave video on)
	out	dx,al
	IO_Delay
	inc	dx
	in	al,dx
	IO_Delay
	xor	ecx,ecx 			; CX = flag (not TLVGA)
	dec	dx
	xor	al,10h
	cmp	al,bl				; Q: Is value same as written?
	jnz	SHORT Restore16 		;   N: Is not TLVGA
	mov	ecx,fVT_TLVGA OR fVT_RsrvC6C7 ;   Y: Is TLVGA
Restore16:
	mov	al,bl
	out	dx,al
	IO_Delay
	pop	dx
	push	dx
	in	al,dx
	IO_Delay
	mov	dl,(pAttr AND 0FFh)
	mov	al,bh
	out	dx,al
	pop	dx
	ret

EndProc Check_Writing_ATC16


IFDEF	Calc_TL4000_MemSize
BeginProc get_internal_reg
	;DX=port, AH=index; ret AL=value (preserve regs<>AL)
	mov	al,ah
	out	dx,al
	inc	dx
	IO_Delay
	in	al,dx
	dec	dx
	ret
EndProc get_internal_reg

BeginProc set_internal_reg
	;DX=port, AH=index, AL=value to set (preserve regs)
	xchg	al,ah
	out	dx,ax
	xchg	al,ah
	ret
EndProc set_internal_reg

BeginProc tst_planar_mem_1
	;passed AL=value for segsel reg for segment to test
	;set plane graphics and test if memory in plane 0, location 1
	; (need to test an odd location for chk_mem_512 (bank 2 on ET3000))
	;ret Z=1 if have mem there, else Z=0
	;preserve all regs
	push	ax
	push	bx
	push	cx
	push	dx
	push	ds
	mov	cl,al			;save segsel value in CL
	mov	dx,03CDh
	in	al,dx
	push	ax
	mov	dx,pSeqIndx
	mov	ah,2
	call	get_internal_reg
	push	ax
	mov	ah,4
	call	get_internal_reg
	push	ax
	mov	dx,pGrpIndx
	mov	ah,1
	call	get_internal_reg
	push	ax
	mov	ah,3
	call	get_internal_reg
	push	ax
	mov	ah,4
	call	get_internal_reg
	push	ax
	mov	ah,5
	call	get_internal_reg
	push	ax
	mov	ah,6
	call	get_internal_reg
	push	ax
	mov	ah,8
	call	get_internal_reg
	push	ax
	;
	mov	dx,pSeqIndx
	mov	ax,0201h		;write plane 0
	call	set_internal_reg
	mov	ax,0406h		;non-chain 4, non-odd/even
	call	set_internal_reg
	mov	dx,pGrpIndx
	mov	ax,0100h		;no set/reset
	call	set_internal_reg
	mov	ax,0300h		;no rotate/func
	call	set_internal_reg
	mov	ax,0400h
	call	set_internal_reg	;read plane 0
	mov	ah,5
	call	get_internal_reg
	and	al,060h			;write/read mode 0 (preserve att bits)
	call	set_internal_reg	; non-odd/even
	mov	ah,6
	call	get_internal_reg
	and	al,1			;preserve graphics bit
	or	al,4			;buffer at A000, non-odd/even
	call	set_internal_reg
	mov	ax,08FFh		;bitmask=all bits
	call	set_internal_reg
	mov	dx,03CDh		;segment select reg
	mov	al,cl
	out	dx,al			;set segment
	;
	mov	ax,0A000h
	mov	ds,ax
	mov	bx,1		;test loc 1
	mov	ah,[bx]		;AH=orig value
	mov	al,055h
tm1m_1:
	mov	[bx],al
	push	ax
	push	bx
	mov	cx,4	;flush ET4000 cache by refing 4 different 8-byte blocks
tm1m_lp:
	add	bx,8
	mov	al,[bx]
	loop	tm1m_lp
	pop	bx
	pop	ax
	cmp	al,[bx]
	jnz	short tm1m_2
	cmp	al,0AAh
	mov	al,0AAh
	jnz	short tm1m_1
tm1m_2:
	mov	[bx],ah			;restore orig value
	;
	pushf
	pop	cx			;save flag in CX
	mov	dx,pGrpIndx
	pop	ax
	call	set_internal_reg
	pop	ax
	call	set_internal_reg
	pop	ax
	call	set_internal_reg
	pop	ax
	call	set_internal_reg
	pop	ax
	call	set_internal_reg
	pop	ax
	call	set_internal_reg
	mov	dx,pSeqIndx
	pop	ax
	call	set_internal_reg
	pop	ax
	call	set_internal_reg
	mov	dx,03CDh
	pop	ax
	out	dx,al
	push	cx
	popf				;recover flag
	pop	ds
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
EndProc tst_planar_mem_1


BeginProc tst_vram_1meg
	;called when have 512k or 1 Meg of vram memory (ET4000)
	;test and ret Z=1 if have 1 Meg, else Z=0
	;preserve all regs
	push	ax
	mov	al,022h			;segsel value for segment to test
	call	tst_planar_mem_1	;test if have memory there
	pop	ax
	ret
EndProc tst_vram_1meg
ENDIF	;Calc_TL4000_MemSize

IFDEF	EXT_VGA
BeginProc reset_att_ff	;reset ATC flip-flop to pt to index (preserve regs)
	push	ax
	push	dx
	mov	dx,pStatColr
	in	al,dx
	IO_Delay
if VGAMONO
	mov	dl,pStatMono and 0FFh
	in	al,dx
endif
	pop	dx
	pop	ax
	ret
EndProc reset_att_ff

BeginProc get_att_reg
	;AH=index; ret AL=value of ATC reg (preserve regs<>AL)
	push	dx
	call	reset_att_ff
	mov	dx,pAttr
	mov	al,ah
	out	dx,al
	inc	dx
	IO_Delay
	in	al,dx
	pop	dx
	ret
EndProc get_att_reg

BeginProc set_att_reg
	;AH=index, AL=value to set in ATC reg (preserve regs)
	push	dx
	call	reset_att_ff
	mov	dx,pAttr
	xchg	al,ah
	out	dx,al
	IO_Delay
	xchg	al,ah
	out	dx,al
	pop	dx
	ret
EndProc set_att_reg

BeginProc chk_mem_512
	;ret Z=1 if have 512k of video memory (ET3000)
	;preserve all regs
	push	ax
	push	cx
	push	dx
	mov	dx,pAttr
	in	al,dx			;read ATC index (incl addr-on bit)
	push	ax
	mov	ah,016h
	call	get_att_reg
	push	ax
	mov	ah,010h
	call	get_att_reg
	push	ax
	mov	dx,pGrpIndx
	mov	ah,6
	call	get_internal_reg
	push	ax
;
	or	al,1
	call	set_internal_reg	;set graphics bit in GDC 6
	mov	ax,01610h		;set hires
	call	set_att_reg
	mov	ax,01001h		;ATC 10 bit 6=0 for chain 2
	call	set_att_reg
	mov	ax,040h			;value for segsel in tst_planar_mem_1
	call	tst_planar_mem_1	;test loc 1=bank 2 in chain2 mode
	pushf
	pop	cx			;save flag in CX
	;restore regs:
	pop	ax
	call	set_internal_reg	;[DX still=pGrpIndx]
	pop	ax
	call	set_att_reg
	pop	ax
	call	set_att_reg
	call	reset_att_ff
	pop	ax
	mov	dx,pAttr
	out	dx,al			;restore index, addr-on bit
	push	cx
	popf				;recover flag
	pop	dx
	pop	cx
	pop	ax
	ret
EndProc chk_mem_512
ENDIF	;EXT_VGA
ENDIF	;TLVGA

VxD_REAL_INIT_ENDS

	END VDD_Real_init
