PAGE 58,132
;******************************************************************************
TITLE vdddebug.asm -
;******************************************************************************
;
;   (C) Copyright MICROSOFT Corp.  All Rights Reserved, 1989, 1990
;
;   Title:	vdddebug.asm -
;
;   Version:	1.00
;
;   Date:	13-Jul-1990
;
;   Author:	RAP
;
;------------------------------------------------------------------------------
;
;   Change log:
;
;      DATE	REV		    DESCRIPTION
;   ----------- --- -----------------------------------------------------------
;   13-Jul-1990 RAP
;
;==============================================================================

	.386p
IFDEF	DEBUG

.xlist
	INCLUDE VMM.INC
	INCLUDE VDD.INC
	INCLUDE VKD.INC
.list

?_fVDD	equ <fVDD_NameTable>	    ; build string tables of flag names
?_fVid	equ <fVid_NameTable>	    ;	for fVDD , FT and fVid flags
?_fVT	equ <fVT_NameTable>
	INCLUDE VDDDEF.INC
.xlist
	INCLUDE DEBUG.INC
.list


VxD_DATA_SEG
IFDEF DEBUG
PUBLIC fVT_NameTable
ENDIF

EXTRN	Vid_CB_Off:DWORD
EXTRN	Vid_Flags:DWORD
EXTRN	VT_Flags:DWORD
EXTRN	Vid_Focus_VM:DWORD
EXTRN	Vid_Msg_VM:DWORD
EXTRN	Vid_CRTC_VM:DWORD
EXTRN	Vid_MemC_VM:DWORD
EXTRN	Vid_Msg_Pseudo_VM:DWORD
EXTRN	VDD_State_MemC_Debug_Event:DWORD
EXTRN	Vid_Planar_Pseudo_CB:BYTE

Vid_QueueOuts_Enabled	db  0


fVidTxtEmulate_nt   db 'fVidTxtEmulate', 0
fVidNoTrpTxt_nt     db 'fVidNoTrpTxt', 0
fVidNoTrpLRGrfx_nt  db 'fVidNoTrpLRGrfx', 0
fVidNoTrpHRGrfx_nt  db 'fVidNoTrpHRGrfx', 0
fVidTextMd_nt	    db 'fVidTextMd', 0
fVidLowRsGrfxMd_nt  db 'fVidLowRsGrfxMd', 0
fVidHghRsGrfxMd_nt  db 'fVidHghRsGrfxMd', 0
fVidRetainAllo_nt   db 'fVidRetainAllo', 0

fVidPIF_NameTable   label dword
	dd  8
	dd  OFFSET32 fVidTxtEmulate_nt
	dd  OFFSET32 fVidNoTrpTxt_nt
	dd  OFFSET32 fVidNoTrpLRGrfx_nt
	dd  OFFSET32 fVidNoTrpHRGrfx_nt
	dd  OFFSET32 fVidTextMd_nt
	dd  OFFSET32 fVidLowRsGrfxMd_nt
	dd  OFFSET32 fVidHghRsGrfxMd_nt
	dd  OFFSET32 fVidRetainAllo_nt

; Accumulated mode state flag values
fVDD_M_None_nt	    db	' ',0
fVDD_M_Ctlr_nt	    db	'fVDD_M_Ctlr',0
fVDD_M_VRAM_nt	    db	'fVDD_M_VRAM',0
fVDD_M_Curs_nt	    db	'fVDD_M_Curs',0
fVDD_M_ScOff_nt     db	'fVDD_M_ScOff',0
fVDD_M_Err_nt	    db	'fVDD_M_Err',0

ModFlag_NameTable   label dword
	dd  7
	dd  OFFSET32 fVDD_M_None_nt
	dd  OFFSET32 fVDD_M_None_nt
	dd  OFFSET32 fVDD_M_None_nt
	dd  OFFSET32 fVDD_M_Ctlr_nt
	dd  OFFSET32 fVDD_M_VRAM_nt
	dd  OFFSET32 fVDD_M_Curs_nt
	dd  OFFSET32 fVDD_M_ScOff_nt

VxD_DATA_ENDS

VxD_ICODE_SEG

;******************************************************************************
;
;   VDD_Debug_Init
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
BeginProc VDD_Debug_Init

IF 0
	pushad
	mov	ax, 58h 		    ; F12
	mov	ebx, HKSS_Ctrl		    ; look for a Shift key
	mov	cl, CallOnPress
	mov	esi, OFFSET32 VDD_FlipCRTC
	VxDCall VKD_Define_Hot_Key
	popad
ENDIF
	ret

EndProc VDD_Debug_Init

VxD_ICODE_ENDS


VxD_CODE_SEG

EXTRN	VDD_PH_Mem_Debug_Dump_Pages:NEAR
EXTRN	VDD_VM_Mem_Debug_Dump_Pages:NEAR
EXTRN	VDD_State_Set_CRTC_Owner:NEAR
EXTRN	VDD_OEM_Debug_RegDump:NEAR


IF 0
;******************************************************************************
;
;   VDD_FlipCRTC
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
BeginProc VDD_FlipCRTC

	pushad
	mov	ebx, [Vid_Focus_VM]
	cmp	ebx, [Vid_CrtC_VM]
	jne	short @F
	VMMCall Get_Sys_VM_Handle
@@:
	SetVDDPtr   edi
	call	VDD_State_Set_CRTC_Owner
	popad
	ret

EndProc VDD_FlipCRTC
ENDIF


;******************************************************************************
;
;   VDD_Queue_Debug_String
;
;   DESCRIPTION:
;
;   ENTRY:	    ESI points to string,
;		    2 value parameters are on the stack
;
;		    stack frame:    [esp+0]   return address
;				    [esp+4]   value 2
;				    [esp+8]   value 1
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc VDD_Queue_Debug_String

	cmp	[Vid_QueueOuts_Enabled], 0
	je	short @F
	VMMJmp	Queue_Debug_String

@@:
	pop	esi		    ; get return address
	add	esp, 2*4	    ; skip 2 dword stack params
	push	esi
	ret

EndProc VDD_Queue_Debug_String


;******************************************************************************
;
;   VDD_Debug_Dump_Flags
;
;   DESCRIPTION:
;
;   ENTRY:	    EAX = flags DWORD
;		    ESI -> flag name table
;			    first dword = # of flag bits
;			    dword offset to bit 0 name
;			    ...
;
;   EXIT:
;
;   USES:
;
;==============================================================================
BeginProc VDD_Debug_Dump_Flags

	push	eax
	push	esi
	mov	ecx, [esi]
ddf_lp:
	add	esi, 4			; point to offset of next flag name
	shr	eax, 1
	jnc	short ddf_not_set
	pushad
	mov	esi, [esi]
	VMMCall Out_Debug_String
	mov	al, ' '
	VMMCall Out_Debug_Chr
	popad

ddf_not_set:
	loop	ddf_lp

	pop	esi
	pop	eax
	ret

EndProc VDD_Debug_Dump_Flags


;******************************************************************************
;VDD_DebugQuery
;
;DESCRIPTION:
;	Dump appropriate VDD state information for each VM.
;
;ENTRY: none
;
;EXIT:	none
;
;USES: Flags
;
;==============================================================================
BeginProc VDD_DebugQuery, PUBLIC

	pushad

Trace_Out   "VDD video state dump for all Virtual Machines:"

	mov	eax, [Vid_Flags]
	mov	esi, OFFSET32 fVid_NameTable
	Trace_Out 'Vid_Flags         = ', nocrlf
	call	VDD_Debug_Dump_Flags
	Trace_Out ' '
	mov	eax, [VT_Flags]
	mov	esi, OFFSET32 fVT_NameTable
	Trace_Out 'VT_Flags          = ', nocrlf
	call	VDD_Debug_Dump_Flags
	Trace_Out ' '
	mov	eax, [Vid_CB_Off]
	Trace_Out "Vid_CB_Off        = #eax"
	mov	eax, [Vid_Focus_VM]
	Trace_Out "Vid_Focus_VM      = #eax"
	mov	eax, [Vid_Msg_VM]
	Trace_Out "Vid_Msg_VM        = #eax"
	mov	eax, [Vid_CrtC_VM]
	Trace_Out "Vid_CrtC_VM       = #eax"
	mov	eax, [Vid_MemC_VM]
	Trace_Out "Vid_MemC_VM       = #eax"
	mov	eax, [Vid_Msg_Pseudo_VM]
	Trace_Out "Vid_Msg_Pseudo_VM = #eax"
	Trace_Out " "
	Trace_Out "Select Option"
	Trace_Out "  1 - display VM register states"
	Trace_Out "  2 - display VM memory usage"
	Trace_Out "  3 - dump video page info"
	Trace_Out "  4 - display msg mode register state"
	Trace_Out "  5 - display planar mode register state"
	Trace_Out "  6 - read DAC"
	Trace_Out "  7 - display VM DAC states"

	cmp	[Vid_QueueOuts_Enabled], 0
	je	short @F
	Trace_Out "  8 - disable Queue_Outs"
	jmp	short VDQ_memc
@@:
	Trace_Out "  8 - enable Queue_Outs"
VDQ_memc:

	cmp	[VDD_State_MemC_Debug_Event], -1
	je	short VDQ_MemCE_disabled
	Trace_Out "  9 - disable MemC debug event"
	jmp	short VDQ_take_input
VDQ_MemCE_disabled:
	Trace_Out "  9 - enable MemC debug event"

VxD_DATA_SEG
Query_Jmp_Table label	dword
	dd  OFFSET32 VDQ_Dump_VMregs	    ;[1]
	dd  OFFSET32 VDQ_DumpVMmem	    ;[2]
	dd  OFFSET32 VDQ_DumpPhys	    ;[3]
	dd  OFFSET32 VDQ_DumpMsgState	    ;[4]
	dd  OFFSET32 VDQ_DumpPlanarState    ;[5]
	dd  OFFSET32 VDQ_DumpCurDAC	    ;[6]
	dd  OFFSET32 VDQ_DumpDACs	    ;[7]
	dd  OFFSET32 VDQ_Toggle_QOs	    ;[8]
	dd  OFFSET32 VDQ_Toggle_MemCE	    ;[9]
query_max equ ($ - Query_Jmp_Table) / 4
VxD_DATA_ENDS

VDQ_take_input:
	VMMcall In_Debug_Chr
	jz	VDQ_Ex
	sub	al, '1'
	jb	VDQ_Ex
	cmp	al, query_max
	ja	VDQ_Ex

	movzx	eax, al
	jmp	[eax*4][Query_Jmp_Table]


VDQ_Dump_VMregs:
	VMMCall Get_Cur_VM_Handle
VDQ_00:
	call	Vid_DumpState
	VMMCall Get_Next_VM_Handle
	VMMCall Test_Cur_VM_Handle
	jnz	VDQ_00
	jmp	VDQ_Ex

VDQ_DumpPlanarState:
	mov	ebx,OFFSET32 Vid_Planar_Pseudo_CB
	sub	ebx,[Vid_CB_Off]
	call	Vid_DumpState
	jmp	VDQ_Ex

VDQ_DumpMsgState:
	mov	ebx, [Vid_Msg_Pseudo_VM]
	call	Vid_DumpState
	jmp	VDQ_Ex

VDQ_DumpVMmem:
	VMMCall Get_Cur_VM_Handle
VDQ_01:
	call	Vid_Dump_VM_Mem
	VMMCall Get_Next_VM_Handle
	VMMCall Test_Cur_VM_Handle
	jz	VDQ_Ex
	VMMcall In_Debug_Chr
	jnz	VDQ_01
	jmp	VDQ_Ex

VDQ_DumpPhys:
	call	VDD_PH_Mem_Debug_Dump_Pages
	jmp	VDQ_Ex

VDQ_DumpDACs:
	VMMCall Get_Cur_VM_Handle
VDQ_DAC00:
	Trace_Out 'VM #ebx DAC dump', nocrlf
	VMMcall In_Debug_Chr
	jz	short VDQ_DAC02
	mov	esi, [Vid_CB_Off]
	add	esi, ebx
	lea	esi, [esi.VDD_DAC]
	mov	ecx, 256
	cld
VDQ_DAC01:
	lodsd			    ; bgri
	xchg	al, ah		    ; bgir
	ror	eax, 16 	    ; irbg
	xchg	al, ah		    ; irgb
	test	eax, 7000000h
	jnz	short @F
	Trace_Out ' '
@@:
	Trace_Out '#eax ', nocrlf
	loop	VDQ_DAC01
VDQ_DAC02:
	VMMCall Get_Next_VM_Handle
	VMMCall Test_Cur_VM_Handle
	jnz	VDQ_DAC00
	jmp	VDQ_Ex

VDQ_DumpCurDAC:
	push	ebx
	mov	dx, 3DAh
	in	al, dx
	mov	dl, 0C0h
	in	al, dx
	push	eax
	xor	al, al
	out	dx, al
	mov	dl, 0C7h
	xor	ah, ah
	mov	ecx, 256
DAC_lp:
	mov	al, ah
	out	dx, al
	mov	bh, al
	add	dl, 2
	in	al, dx
	mov	bl, al
	shl	ebx, 16
	in	al, dx
	mov	bh, al
	in	al, dx
	mov	bl, al
	test	ebx, 7000000h
	jnz	short @F
	Trace_Out ' '
@@:
	Trace_Out '#ebx ', nocrlf
	sub	dl, 2
	inc	ah
	loop	DAC_lp
	Trace_Out ' '
	mov	dl, 0DAh
	in	al, dx
	mov	dl, 0C0h
	pop	eax
	out	dx, al
	pop	ebx
	jmp	short VDQ_Ex

VDQ_Toggle_QOs:
	xor	[Vid_QueueOuts_Enabled], 0FFh
	jmp	short VDQ_Ex

VDQ_Toggle_MemCE:
	or	ecx, -1
	xchg	[VDD_State_MemC_Debug_Event], ecx
	jecxz	short VDQ_Ex		; jump if just disabled & no event scheduled
	inc	ecx			;Q: MemCE was disabled (= -1)?
	jecxz	short VDQ_enable_MemCE	;   Y: change to 0, to enable
	dec	ecx			;   N: ecx is a real event handle,
	mov	esi, ecx		;      so cancel the scheduled event
	VMMCall Cancel_Global_Event	;      and -1 has been moved in to disable
	jmp	short VDQ_Ex

VDQ_enable_MemCE:
	mov	[VDD_State_MemC_Debug_Event], ecx

VDQ_Ex:
	popad
	ret

;------------------------------------------------------------------------------
Vid_DumpState:
Trace_Out	"***********************************"
	cmp	ebx,[Vid_Focus_VM]
	jz	SHORT VDQ_0
Trace_Out	"VM #EBX does not have display focus.  [ESC to skip]"
	jmp	SHORT VDQ_1
VDQ_0:
Trace_Out	"VM #EBX has display focus.  [ESC to skip]"
VDQ_1:

	SetVDDPtr   edi

	mov	al,[edi.VDD_Stt.V_BIOSMode]
	Trace_Out "BIOS Mode = #AL"

	test	[edi.VDD_Flags],fVDD_Win
	jz	SHORT VDS_00
	mov	eax,[edi.VDD_Mod_Flag_Save]
	mov	esi, OFFSET32 ModFlag_NameTable
	Trace_Out "Grabber Mod state = ", nocrlf
	call	VDD_Debug_Dump_Flags
	test	[edi.VDD_Mod_Flag_Save], fVDD_M_Err
	jz	SHORT VDS_00a
	mov	esi,OFFSET32 fVDD_M_Err_nt
	VMMCall Out_Debug_String
VDS_00a:
	Trace_Out ' '

VDS_00:
	mov	eax, [edi.VDD_Flags]
	mov	esi, OFFSET32 fVDD_NameTable
	Trace_Out 'VDD_Flags = ', nocrlf
	call	VDD_Debug_Dump_Flags
	Trace_Out ' '

	movzx	eax, [edi.VDD_PIF]
	mov	esi, OFFSET32 fVidPIF_NameTable
	Trace_Out 'VDD_PIF   = ', nocrlf
	call	VDD_Debug_Dump_Flags
	Trace_Out ' '

	VMMcall In_Debug_Chr
	jz	skip_vm_dump

Trace_Out	"Registers:"
	mov	al, [edi.VDD_Stt.V_Misc]
Trace_Out	"Misc: #al"
Trace_Out	"CRTC:" +

IFDEF	PEGA
	mov	al,[edi.VDD_Stt.C_Indx]
Trace_Out	"(#AL)"

;******* Dump unscrambled, unlocked regs
	mov	ecx,DWORD PTR [edi.VDD_Stt.VC_PCUnUMsk]
Trace_Out	" #CX:   " +
	mov	ecx,(SIZE CRTC_Struc)/2
	lea	esi,[edi.VDD_Stt.CRTC]
	call	VDD_Reg_Dump
	mov	ecx,(SIZE CRTC_Struc)/2
Trace_Out	" "
Trace_Out	"         " +
	call	VDD_Reg_Dump
Trace_Out	" "

;******* Dump unscrambled, locked regs, if any
	mov	ecx,DWORD PTR [edi.VDD_Stt.VC_PCUnLMsk]
	or	ecx,ecx 		    ; Q: Any locked CRTC values?
	jz	SHORT VDQ_ScU		    ;	N: skip
Trace_Out	" #CX:   " +
	mov	ecx,(SIZE CRTC_Struc)/2
	lea	esi,[edi.VDD_Stt.VC_PCUnL]
	call	VDD_Reg_Dump
	mov	ecx,(SIZE CRTC_Struc)/2
Trace_Out	" "
Trace_Out	" Lok     " +
	call	VDD_Reg_Dump
Trace_Out	" "

;******* Dump scrambled, unlocked regs, if any
VDQ_ScU:
	mov	ecx,DWORD PTR [edi.VDD_Stt.VC_PCScUMsk]
	or	ecx,ecx 		    ; Q: Any scrm'd, unlocked values?
	jz	SHORT VDQ_ScL		    ;	N: skip
Trace_Out	" #CX:   " +
	mov	ecx,(SIZE CRTC_Struc)/2
	lea	esi,[edi.VDD_Stt.VC_PCScU]
	call	VDD_Reg_Dump
	mov	ecx,(SIZE CRTC_Struc)/2
Trace_Out	" "
Trace_Out	" Scrm    " +
	call	VDD_Reg_Dump
Trace_Out	" "

;******* Dump scrambled, locked regs, if any
VDQ_ScL:
	mov	ecx,DWORD PTR [edi.VDD_Stt.VC_PCScLMsk]
	or	ecx,ecx 		    ; Q: Any scrm'd, unlocked values?
	jz	SHORT VDQ_CRTC_Done	    ;	N: skip
Trace_Out	" #CX:   " +
	mov	ecx,(SIZE CRTC_Struc)/2
	lea	esi,[edi.VDD_Stt.VC_PCScL]
	call	VDD_Reg_Dump
	mov	ecx,(SIZE CRTC_Struc)/2
Trace_Out	" "
Trace_Out	" Scrm,Lok" +
	call	VDD_Reg_Dump
Trace_Out	" "
VDQ_CRTC_Done:

ELSE
	mov	al,[edi.VDD_Stt.C_Indx]
Trace_Out	"(#AL)" +
	mov	ecx,SIZE CRTC_Struc
	lea	esi,[edi.VDD_Stt.CRTC]
	call	VDD_Reg_Dump
Trace_Out	" "
ENDIF

Trace_Out	"Attr:" +
	mov	al,[edi.VDD_Stt.A_Indx]
Trace_Out	"(#AL)" +
	lea	esi,[edi.VDD_Stt.A_Pal]
	mov	ecx,A_IMax+1
	call	VDD_Reg_Dump
Trace_Out	" "
Trace_Out	"Grp: " +
	mov	al,[edi.VDD_Stt.G_Indx]
Trace_Out	"(#AL)" +
	mov	ecx,G_IMax+1
	lea	esi,[edi.VDD_Stt.G_SetRst]
	call	VDD_Reg_Dump
Trace_Out	" "
Trace_Out	"Seq: " +
	mov	al,[edi.VDD_Stt.S_Indx]
Trace_Out	"(#AL)" +
	mov	ecx,S_IMax+1
	lea	esi,[edi.VDD_Stt.S_Rst]
	call	VDD_Reg_Dump
Trace_Out	" "
	call	VDD_OEM_Debug_RegDump
skip_vm_dump:
	ret

;------------------------------------------------------------------------------
; Dump CX regs at ESI
BeginProc VDD_Reg_Dump
	xor	edx,edx
        cld
VRD_Lp:
	lodsb
Trace_Out " #AL" +
	inc	edx
	and	edx,00Fh
	jnz	SHORT VRD_LpNext
Trace_Out	" "
Trace_Out	"         " +
VRD_LpNext:
	loop	VRD_lp
	ret
EndProc VDD_Reg_Dump

;------------------------------------------------------------------------------
Vid_Dump_VM_Mem:
	SetVDDPtr   edi
	mov	ecx, 4
	push	ebx
	push	edi
	lea	esi, [edi.VDD_MStt.MSS_planes]
	lea	edi, [edi.VDD_MSttCopy.MSS_planes]
	Trace_Out ' '
	Trace_Out '   MStt for VM #ebx                  MSttCopy'
;				  xxxxxxxx		    MSttCopy'
	Trace_Out ' handle    addr   size alloc     handle    addr   size alloc'
;		   xxxxxxxx xxxxxxxx xxxx xxxx	   xxxxxxxx xxxxxxxx xxxx xxxx
Vid_MemH_Dump:
	push	ecx
	mov	eax, [esi.MSS_plane_handle]
	mov	ebx, [esi.MSS_plane_addr]
	movzx	edx, [esi.MSS_plane_size]
	movzx	ecx, [esi.MSS_plane_alloced]
	Trace_Out '#eax #ebx #dx #cx', NOEOL
	mov	eax, [edi.MSS_plane_handle]
	mov	ebx, [edi.MSS_plane_addr]
	movzx	edx, [edi.MSS_plane_size]
	movzx	ecx, [edi.MSS_plane_alloced]
	Trace_Out '     #eax #ebx #dx #cx'
	add	esi, SIZE MSS_Plane_Info_Struc
	add	edi, SIZE MSS_Plane_Info_Struc
	pop	ecx
	loop	Vid_MemH_Dump
	pop	edi
	pop	ebx
	mov	esi,[edi.VDD_Copy_Buf.MSS_plane_addr]
	or	esi,esi
	jz	VDD_VM_Mem_Debug_Dump_Pages
	movzx	ecx,[edi.VDD_Copy_Buf.MSS_plane_size]
	shl	ecx,12
	movzx	eax,[edi.VDD_Copy_Buf.MSS_plane_alloced]
	shl	eax,12
	Trace_Out " "
	Trace_Out "   Grabber mem is at #ESI for #ECX bytes, alloc #EAX"

	jmp	VDD_VM_Mem_Debug_Dump_Pages

EndProc VDD_DebugQuery

VxD_CODE_ENDS

ENDIF

END
