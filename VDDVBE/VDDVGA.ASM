       TITLE   VDD - Virtual Display Device for VGA   version 3.10
;******************************************************************************
;
; VDDVGA - VGA specific routines for VDD
;
;   Author: MDW
;
;   (C) Copyright MICROSOFT Corp. 1986-1990
;
;
;DESCRIPTION:
;	This module has the VGA specific routines for VDD
;
;        [1] save Paradise Sequencer extend registers.
;	 [2] add 3c4.13 and 3c4.14 save for PVGA 1D chip.
;        [3] Save 3d4.3e in 1D chip - no lock/unlock process is needed
;            Since you are not supposed to touch this register in 1F chip,
;            we check if 1F and jump.
;	 [4] Special care for 3x4.30 in WDC 1F chip.  In order to read this
;	     register, 3x4.29 must be 85h and both 3x4.34 and 3x4.35 must be
;	     locked.					     [06-28-91]
;                                                            - C. Chiang -
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
VxD_CODE_SEG
EXTRN	VDD_OEM_Pre_Save_Regs:NEAR
EXTRN	VDD_OEM_Post_Save_Regs:NEAR
EXTRN	VDD_OEM_Save_Regs:NEAR
EXTRN	VDD_State_Get_CRTC_Index_Port:NEAR
IFDEF MapMonoError
EXTRN	VDD_Error_MapMono:NEAR
ENDIF
VxD_CODE_ENDS

;******************************************************************************
; EXTRN data
;
VxD_DATA_SEG
EXTRN	Vid_Flags:DWORD
EXTRN	Vid_MemC_VM:DWORD
EXTRN	Vid_CRTC_VM:DWORD
VxD_DATA_ENDS


VxD_CODE_SEG

;******************************************************************************
;VDD_VGA_Save_Regs	 Save any controller state not trapped
;
;DESCRIPTION: Saves the state of the VGA by reading the registers.  Note that
;	    the VDD_VGA_Savexxxx routines must be called in specific order.
;
;ENTRY: [Vid_MemC_VM] = VM currently running in VGA
;
;EXIT:	VGA index registers restored, VDD_Stt structure modified
;
;USES:	Flags
;
;==============================================================================
BeginProc VDD_VGA_Save_Regs, PUBLIC

	pushad
	mov	ebx,[Vid_MemC_VM]
	Assert_VM_Handle ebx
	cmp	ebx,[Vid_CRTC_VM]		; Q: CRTC VM = MemC VM
IFDEF	VGA8514
	jnz	DEBFAR VVSR_Exit		;   N: Other VMs are trapped
ELSE
	jnz	SHORT VVSR_Exit 		;   N: Other VMs are trapped
ENDIF
	SetVDDPtr edi

IFDEF	DEBUG
	TestMem [edi.VDD_Flags],fVDD_NeedRestore
	jz	SHORT VSR_D00
Debug_Out "Saving hardware regs before changed state restored"
VSR_D00:
ENDIF

	call	VDD_State_Get_CRTC_Index_Port

	call	VDD_OEM_Pre_Save_Regs		; Enable access, save some regs
	call	VDD_VGA_Save_Misc		; Save Feat, Misc etc.
	call	VDD_VGA_Save_CRTC		; Save CRTC
	call	VDD_VGA_Save_Grp		; Save Graphics controller
	call	VDD_VGA_Save_Seq		; Save Sequencer
	call	VDD_OEM_Save_Regs		; Save OEM specific registers
	call	VDD_VGA_Save_Attr		; Attribute controller

; Conditionally save the DAC
	TestMem [Vid_Flags], fVid_DOff		;Q: display off?
IFDEF VGA8514
	jnz	SHORT VVSR_SaveDAC		;   Y: save DAC
	VMMCall Test_Sys_VM_Handle		;Q: SYS VM?
	jnz	SHORT VVSR_NoDAC		;   N: skip DAC
						;   Y: save only the 8514 DAC
VVSR_SaveDAC:
ELSE
	jz	SHORT VVSR_NoDAC		;   N: Don't save DAC
ENDIF
	call	VDD_VGA_Save_DAC		;   Y: Save DAC
VVSR_NoDAC:
	call	VDD_OEM_Post_Save_Regs		; Restore access register

VVSR_Exit:
	popad
	ret
EndProc VDD_VGA_Save_Regs

;******************************************************************************
;VDD_VGA_Save_Attr
;
;DESCRIPTION: Saves the state of the Attribute controller by reading the
;	    registers.
;
;ENTRY: EBX = VM handle
;	EDI = VDD data ptr for VM
;	DX = 3B5 or 3D5
;
;EXIT:	VGA index registers restored, VDD_Stt structure modified
;
;USES:	Flags, EAX, ECX, ESI
;
;==============================================================================
BeginProc VDD_VGA_Save_Attr

	push	edx
	add	edx, pStatColr-pCRTCIndxColr
.errnz (pStatMono-pCRTCIndxMono) - (pStatColr-pCRTCIndxColr)
	mov	si,pAttr
	in	al,dx				; Set toggle to index register
	IO_Delay
	xchg	edx,esi
	TestMem [Vid_Flags],fVid_DOff		; Q: Globally turned off?
	jnz	SHORT VSV_A0			;   Y: don't read the index
	TestMem [edi.VDD_Flags],fVDD_AxRd	; Q: Index saved and mod'd?
	jnz	SHORT VSV_A0			;   Y: Don't read it again
	in	al,dx				; Read Attribute index register
	IO_Delay
	and	[edi.VDD_Stt.A_Indx],fVAI_Indx
	and	al,not fVAI_Indx
	or	[edi.VDD_Stt.A_Indx],al 	;	and save it
VSV_A0:
	push	edi
	mov	ecx,A_Color-A_Pal+1
IFDEF	CTVGA
	dec	ecx				; no 14h for CTVGA
ENDIF
IFDEF TLVGA
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jz	short VSV_A0a
	mov	cl,018h				;save thru ATC 17
VSV_A0a:
ENDIF
	xor	ah,ah
	TestMem [Vid_Flags],fVid_DOff		; Q: Globally turned off?
	jnz	SHORT VSV_A1			;   Y: Read all the regs
	test	[edi.VDD_Stt.A_Indx],fVAI_ScOn	; Q: Screen on?
	jz	SHORT VSV_A1a			;   N: leave off
	or	ah,fVAI_ScOn			;   Y: leave on
VSV_A1a:
	add	edi,10h 			;   N: don't read the palette
	or	ah,10h				;	start at reg. 10h
	sub	cl,10h
VSV_A1:
	lea	edi,[edi.VDD_Stt.A_Pal]
; AH  = Attribute index
; ECX = number of registers
; EDX = Attribute  port
; ESI = Status port
; EDI = Attribute state structure address
        cld
	TestMem [Vid_Flags],fVid_DOff		; Q: Is video off?
	jnz	short VSV_skip_retrace_chk	;   Y: ignore retrace
	test	ah,10h				; Q: Modifying palette?
	jnz	SHORT VSV_skip_retrace_chk	;   N: ignore retrace
	push	ecx
	mov	ecx, 10000h
	xchg	edx,esi
VSV_A_Loop:
	in	al,dx				; read status
	IO_Delay
	test	al,8
	loopz	VSV_A_Loop
	xchg	edx,esi
	pop	ecx
VSV_skip_retrace_chk:

; loop thru and save regs
;
VSV_A_Loop2:
	xchg	edx,esi
	in	al,dx				; Set toggle to index register
	IO_Delay
	xchg	edx,esi
	mov	al,ah
	out	dx,al				; Select a register
	IO_Delay
	inc	edx
	in	al,dx				; Read it
	IO_Delay
	dec	edx
	stosb					; Save it
	inc	ah
	loop	VSV_A_Loop2

	xchg	edx,esi
	in	al,dx
	IO_Delay
	xchg	edx,esi
	pop	edi
	mov	al,[edi.VDD_Stt.A_Indx]
	and	al,0FFh-fVAI_Indx
	TestMem [Vid_Flags],fVid_DOff		; Q: Is video off?
	jz	SHORT VSV_A2			;   N: Continue
	and	al,not fVAI_ScOn		;   Y: Keep it off
VSV_A2:
	out	dx,al				; Restore index register
	IO_Delay
	xchg	edx,esi 			; Restore EDX to pStat
	test	[edi.VDD_Stt.A_Indx],fVAI_Indx	; Q: 3C0 = access data?
	jz	SHORT VSV_A3			;   Y: all done
	in	al,dx				;   N: reset toggle to index
	IO_Delay
VSV_A3:
	pop	edx
	ret
EndProc VDD_VGA_Save_Attr

;******************************************************************************
;VDD_VGA_Save_Misc
;
;DESCRIPTION: Reads the Miscellaneous register and other OEM specific registers.
;
;ENTRY: EBX = VM handle
;	EDI = VDD data ptr for VM
;	DX = 3B4 or 3D4
;
;EXIT:	VGA index registers restored, VDD_Stt structure modified
;
;USES:	Flags, EAX, ESI
;
;==============================================================================
BeginProc VDD_VGA_Save_Misc

	push	edx
IFDEF	CTVGA
;*******
; Enable CTVGA special register read mode
	mov	al,17h
	out	dx,al
	IO_Delay
	inc	edx
	in	al,dx
	IO_Delay
	push	eax
	or	al,10h
	out	dx,al				; Enable extended read mode
	IO_Delay
	dec	edx
	mov	al,xC_CT400
	out	dx,al
	IO_Delay
	inc	edx
	in	al,dx
	IO_Delay
        mov     [edi.VDD_Stt.C_CT400],al
	push	eax
	and	al,7Fh				; Read Misc and Feat regs
	out	dx,al
	IO_Delay
	dec	edx

;*******
; Miscellaneous register
	mov	al,xC_CTMiscRead
	out	dx,al
	IO_Delay
	inc	edx
	in	al,dx
	IO_Delay
	mov	[edi.VDD_Stt.V_Misc],al 	; Save Misc reg
	dec	edx

;*******
; Feature control register
	mov	al,xC_CTFeatRead
	out	dx,al
	IO_Delay
	inc	edx
	in	al,dx
	IO_Delay
	mov	[edi.VDD_Stt.V_Feat],al 	;	and save it

;*******
; Graphics control register
	mov	dl,(pGrpIndx AND 0FFh)
	mov	al,xG_CTCtl
	out	dx,al
	IO_Delay
	inc	edx
	in	al,dx
	IO_Delay
	mov	[edi.VDD_Stt.xG_CTCtl],al	; Save Graphics control reg
	dec	edx
	mov	al,[edi.VDD_Stt.G_Indx]
	out	dx,al				; Restore Graphics ctlr index
	IO_Delay

;*******
; Restore the CRTC
	pop	edx				; Restore DX=3D4 or 3B4
	mov	al,xC_CT400
	out	dx,al
	IO_Delay
	inc	edx
	pop	eax
	out	dx,al				; Restore 400 line register
	IO_Delay
	dec	edx
	mov	al,17h
	out	dx,al
	IO_Delay
	inc	edx
	pop	eax
	out	dx,al				; Restore reg 17h
	IO_Delay
	dec	edx
	mov	al,[edi.VDD_Stt.C_Indx] 	; Restore index
	out	dx,al
	IO_Delay
	ret
ELSE

;*******
; Miscellaneous register
	mov	dl,(pMiscRead AND 0FFh)
	in	al,dx				; Read the Misc. register
	IO_Delay
	mov	[edi.VDD_Stt.V_Misc],al 	;	and save it

;*******
; Feature control register
	mov	dl,(pFeatRead AND 0FFh)
	in	al,dx				; Read the Feature register
	IO_Delay
	mov	[edi.VDD_Stt.V_Feat],al 	;	and save it
	pop	edx
	ret
ENDIF
EndProc VDD_VGA_Save_Misc

;******************************************************************************
;VDD_VGA_Save_CRTC
;
;DESCRIPTION: Reads the CRTC registers.
;
;ENTRY: EBX = VM handle
;	EDI = VDD data ptr for VM
;	DX = 3B4 or 3D4
;
;EXIT:	VGA index registers restored, VDD_Stt structure modified
;
;USES:	Flags, EAX, EDX, ESI
;
;==============================================================================
BeginProc VDD_VGA_Save_CRTC

	in	al,dx				; Read CRTC index register
	IO_Delay
	mov	[edi.VDD_Stt.C_Indx],al 	;	and save it
	and	[edi.VDD_Stt.C_Indx],mx_CRTC	; Mask to index bits
IFDEF	CTVGA
	test	al,20h				; Q: Was it CTVGA special reg?
	jz	SHORT VSVC_0			;   N: continue
	or	[edi.VDD_Stt.C_Indx],0F0h	; Add in more bits
VSVC_0:
	mov	al,17h
	out	dx,al
	IO_Delay
	inc	edx
	in	al,dx
	IO_Delay
	push	eax
	or	al,10h
	out	dx,al				; Enable extended read mode
	IO_Delay
	dec	edx
	mov	al,xC_CT400
	out	dx,al
	IO_Delay
	inc	edx
	in	al,dx
	IO_Delay
	mov	[edi.VDD_Stt.C_CT400],al	; Save 400 line register
	or	al,80h				; Read CRTC cursor posn regs
	out	dx,al
	IO_Delay
	dec	edx
ENDIF

	push	edi
	mov	ecx,C_LnCmp-C_HTotal+1

IFDEF	PVGA
	TestMem [edi.VDD_TFlags], fVT_PVGA
	jz	short scrtexit
;
; Unlock Paradise CRTC registers        - C. Chiang -
	mov	eax,C_P29-C_HTotal 
	out	dx,al
	IO_Delay
	inc	edx
	mov	al, 085h    			; Unlock access
	out	dx,al
	IO_Delay
	dec	edx
; More registers for WDC VGA		- C. Chiang -
	; check if 1A board by write/read 3x4.29
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
	push	eax			; save 3x4 index
	mov	al, 29h
	out	dx, al
	inc	dx
	in	al, dx			; save 3x4.29 value
	push	eax
	mov	al, 085h		; 	 - 3x4.29.05 exits?
 	out	dx, al			; 		N: exit
	jmp	$+2
	in	al, dx
	cmp	al, 085h
	pop	eax
	out	dx, al			; restore 3x4.29 no matter what
	jnz	short @F		; 1A - no ext CRTC registers

;[4]**	mov     ecx,C_P30-C_HTotal+1    
	mov     ecx,C_P2f-C_HTotal+1    ; special care for 3x4.30 in 1F chip
@@:
	pop	eax
	dec	dx
	out	dx, al			; restore 3x4 index

	pop	edx
	pop	eax
scrtexit:
ENDIF	;PVGA


IFDEF TLVGA
	TestMem [edi.VDD_TFlags], fVT_TLVGA
	jz	short VSV_C_1
	mov	cl,026h				;save thru CRTC 25
	jmp	short VSV_C_2
VSV_C_1:
	TestMem [edi.VDD_TFlags],fVT_TL_ET4000	    ;if ET4000
	jz	short VSV_C_2
	mov	cl,036h				;save thru CRTC 35
VSV_C_2:
ENDIF
	lea	edi,[edi.VDD_Stt.C_HTotal]
	xor	ah,ah

; AH  = CRTC index
; ECX = number of registers
; EDX = CRTC port
; EDI = CRTC state structure address
        cld
VSV_C_Loop:
	mov	al,ah
	out	dx,al				; Select a register
	IO_Delay
	inc	edx
	in	al,dx				; Read it
	IO_Delay
	dec	edx
	stosb					; Save it
	inc	ah
	loop	VSV_C_Loop
	pop	edi

IFDEF	PVGA
	TestMem [edi.VDD_TFlags], fVT_PVGA	    ; Q: Paradise VGA?
	jz	SHORT notPVGA00			;   N: read IBM regs only

; [4] Take care of 3x4.30 - in WDC 1F, in order to read this register,
;     set 3x4.29 = 85h, and both 3x4.34 and 3x4.35 need to be locked.
	mov	ax, 34h		; lock 3x4.34
	out	dx, ax
        IO_Delay
	mov	ax, 35h		; lock 3x4.35
	out	dx, ax
        IO_Delay

	mov	al, 30h		; read 3x4.30
	out	dx, al
        IO_Delay
	inc	edx
	in	al, dx
        IO_Delay
	mov	[edi.VDD_Stt.C_P30],al		; Save 3x4.30
	dec	edx

	mov	ax, 0A634h		; unlock 3x4.34
	out	dx, ax

	mov	al, 32h
	out	dx, al
        IO_Delay
	inc	edx
	in	al, dx
        IO_Delay
	dec	edx
	test	al, 10000b		; 3x4.32 bit #4: 1 -> LCD
	mov	ax, 34h
	jnz	short @F		; LCD side -> keep 3x4.34 = 0
	mov	ah, 0A6h		; CRT side -> keep 3x4.34 = A6
@@:
	out	dx, ax

	mov	ax, 03035h		; unlock 3x4.35
	out	dx, ax
        IO_Delay

	TestMem [edi.VDD_TFlags], fVT_PVGA1F
	jnz	SHORT isPVGA1F

	;-------------------------------------------------------------------
	; [3] Save 3d4.3e in 1D chip - no lock/unlock process is needed
	;     Since you are not supposed to touch this register in 1F chip,
	;     we check if 1F and jump.			CChiang
	;-------------------------------------------------------------------
	mov	eax,C_P3e-C_HTotal 
	out	dx,al
	IO_Delay
	inc	edx
	in	al, dx
        IO_Delay
	mov	[edi.VDD_Stt.C_P3e], al
	dec	edx
isPVGA1F:

notPVGA00:

ENDIF	;PVGA

IFDEF	CTVGA
        mov	al, 0FEh
        out	dx,al
	IO_Delay
        inc	edx
        in	al,dx
	IO_Delay
        mov	[edi.VDD_Stt.C_CTTempFE],al
        dec	edx

        mov	al,xC_CT400
        out	dx,al
	IO_Delay
        inc	edx
        mov	al,[edi.VDD_Stt.C_CT400] 	
        out	dx,al				; Restore 400 line register
	IO_Delay
        dec	edx
        mov	al,17h
        out	dx,al
	IO_Delay
        inc	edx
        pop	eax
        out	dx,al				; Restore reg 17h
	IO_Delay
        mov	[edi.VDD_Stt.C_Mode],al 	;   and put correct val in data
        dec	edx
ENDIF

	mov	al,[edi.VDD_Stt.C_Indx]
	out	dx,al				; Restore index register
	IO_Delay
	ret
EndProc VDD_VGA_Save_CRTC

;******************************************************************************
;VDD_VGA_Save_Grp
;
;DESCRIPTION: Reads the Graphics controller registers.
;
;ENTRY: EBX = VM handle
;	EDI = VDD data ptr for VM
;	DX = 3B4 or 3D4
;
;EXIT:	VGA index registers restored, VDD_Stt structure modified
;
;USES:	Flags, EAX, ECX, ESI
;
;ASSUMES: 3Dx addressing!!
;
;==============================================================================
BeginProc VDD_VGA_Save_Grp

	push	edx
	mov	dx,pGrpIndx
	in	al,dx				; Read Graphics controller index
	IO_Delay
	mov	[edi.VDD_Stt.G_Indx],al 	;	and save it
	and	[edi.VDD_Stt.G_Indx],mx_Grp	; Mask to index bits
IFDEF	CTVGA
	test	al,20h				; Q: Was it CTVGA special reg?
	jz	SHORT VSV_G_IBM			;   N: continue
	or	[edi.VDD_Stt.G_Indx],0F0h	; Add in more bits
VSV_G_IBM:
ENDIF
	mov	ecx,G_Mask-G_SetRst+1
IFDEF	PVGA
	TestMem [edi.VDD_TFlags], fVT_PVGA	    ; Q: Paradise VGA?
	jz	SHORT VSVG0			;   N: read IBM regs only
; Note that count is one less since we are reading GRP.15 here, not in loop
	mov	ecx,G_PVGA5-G_SetRst		;   Y: read Paradise regs also
	mov	al,cl				;	Read GRP.15 first
	out	dx,al
	IO_Delay
	inc	edx
	in	al,dx
	IO_Delay
	mov	[edi.VDD_Stt.G_PVGA5],al	; Save value of Paradise VGA 5
	and	al,07
	ClrFlag [edi.VDD_Flags], fVDD_PVGA_Ena
	cmp	al,5
	jnz	SHORT VSVG00
	SetFlag [edi.VDD_Flags],fVDD_PVGA_Ena
VSVG00:
	mov	al,5
	out	dx,al
	IO_Delay
	dec	edx
VSVG0:
ENDIF
	push	edi
	lea	edi,[edi.VDD_Stt.G_SetRst]
	xor	ah,ah

; AH  = Graphics controller index
; ECX = number of registers
; EDX = Graphics controller port
; EDI = Graphics controller state structure address
        cld
VSV_G_Loop:
	mov	al,ah
	out	dx,al				; Select a register
	IO_Delay
	inc	edx
	in	al,dx				; Read it
	IO_Delay
	dec	edx
	stosb					; Save it
	inc	ah
	loop	VSV_G_Loop
	pop	edi

IFDEF	PVGA
	TestMem [edi.VDD_TFlags], fVT_PVGA	    ; Q: Paradise VGA?
	jz	SHORT VSVG1			;   N: read IBM regs only
; Restore the LOCK register
	mov	al,G_PVGA5-G_SetRst
	out	dx,al
	IO_Delay
	inc	edx
	mov	al,[edi.VDD_Stt.G_PVGA5]	; Restore Paradise VGA 5
	out	dx,al
	IO_Delay
	dec	edx
VSVG1:
ENDIF

; Restore the index
	mov	al,[edi.VDD_Stt.G_Indx]
	out	dx,al				; Restore index register

IFDEF MapMonoError
IFDEF	VGAMONO
; If mono mapped memory and VGAMONO not supported, report error

	TestMem [edi.VDD_TFlags],fVT_Mono	    ; Q: B0 mapping supported?
	jnz	SHORT @F			    ;	Y: continue
	TestMem [edi.VDD_Stt.G_Misc],4		    ; Q: B0 page mapped?
	jnz	SHORT @F			    ;	N: continue
	pushad
	call	VDD_Error_MapMono		    ;	Y: Warn user
	popad
@@:
ENDIF
ENDIF

	pop	edx
	ret
EndProc VDD_VGA_Save_Grp

;******************************************************************************
;VDD_VGA_Save_Seq
;
;DESCRIPTION: Reads the Sequencer registers.
;
;ENTRY: EBX = VM handle
;	EDI = VDD data ptr for VM
;	DX = 3B4 or 3D4
;
;EXIT:	VGA index registers restored, VDD_Stt structure modified
;
;USES:	Flags, EAX, ECX, ESI
;
;==============================================================================
BeginProc VDD_VGA_Save_Seq

	push	edx
	mov	dx,pSeqIndx
	in	al,dx				; Read CRTC index register
	IO_Delay
	and	al,mx_Seq
	mov	[edi.VDD_Stt.S_Indx],al 	;	and save it
	push	edi
	mov	ecx,S_MMode-S_Rst+1

IFDEF   PVGA
	TestMem [edi.VDD_TFlags], fVT_PVGA	    ; Q: Paradise VGA?
	jz	short @F
;--------------------------------------------------------------------------
;        save Paradise Sequencer extend registers      - C. Chiang -
;--------------------------------------------------------------------------
; unlock Paradise Seq extend register access lock/unlock  
; Since the unlock/lock register is WRITE only, no restore can occur

	mov	ecx,S_PVGA20-S_Rst		;  
	mov	al,cl				;  
	out	dx,al
	IO_Delay
	inc	edx
        mov	al,48h                          ; enable R/W of PR.11-PR.17
	out	dx,al
	IO_Delay
	dec	edx

	mov	ecx,S_PVGA_1Dpr34-S_Rst+1	; 1D 3c4.13 and 3c4.14 02-06-91
@@:
ENDIF   ;PVGA


IFDEF TLVGA
	TestMem [edi.VDD_TFlags],<fVT_TLVGA+fVT_TL_ET4000>
	jz	short VSV_S_1
	mov	cl,8				;save thru TS 7
VSV_S_1:
ENDIF
	lea	edi,[edi.VDD_Stt.S_Rst]
	xor	ah,ah

; AH  = Sequencer index
; ECX = number of registers
; EDX = Sequencer port
; EDI = Sequencer state structure address
        cld
VSV_S_Loop:
	mov	al,ah
	out	dx,al				; Select a register
	IO_Delay
	inc	edx
	in	al,dx				; Read it
	IO_Delay
	dec	edx
	stosb					; Save it
	inc	ah
	loop	VSV_S_Loop
	pop	edi
	mov	al,[edi.VDD_Stt.S_Indx]
	out	dx,al				; Restore index register
	IO_Delay
	pop	edx
	ret
EndProc VDD_VGA_Save_Seq

;******************************************************************************
;VDD_VGA_Save_DAC
;
;DESCRIPTION: Reads the Digital to Analog Converter (DAC) registers.
;
;ENTRY: EBX = VM handle
;	EDI = VDD data ptr for VM
;	DX = 3B4 or 3D4
;
;EXIT:	VGA index registers restored, VDD_Stt structure modified
;
;USES:	Flags, EAX, ECX, ESI
;
;==============================================================================
BeginProc VDD_VGA_Save_DAC

	push	edx
	push	edi
	lea	edi, [edi.VDD_DAC]
	xor	ecx,ecx
	cld
IFDEF VGA8514
	VMMCall Test_Sys_VM_Handle
	mov	edx, p8514DACRindx
	je	short VVSDAC_1
ENDIF

	mov	dx,pDACRindx
VVSDAC_1:
	mov	al,cl
	stosb
	out	dx,al				; Set index then read data
	IO_Delay
	add	edx, 2				; mov	  edx,pDACData
.errnz pDACData - pDACRindx - 2
IFDEF VGA8514
.errnz p8514DACData - p8514DACRindx - 2
ENDIF
	in	al,dx				; Get red
	IO_Delay
	stosb
	in	al,dx				; Get green
	IO_Delay
	stosb
	in	al,dx				; Get blue
	IO_Delay
	stosb
	sub	edx, 2				; mov	  edx,pDACRindx
	inc	cl
	jnz	VVSDAC_1
VVS_exit:
	pop	edi
	pop	edx
	ret
EndProc VDD_VGA_Save_DAC

;******************************************************************************
;VDD_VGA_Restore_DAC
;
;DESCRIPTION:	 Restore DAC registers
;
;ENTRY:     EBX = VM handle
;	    EDI = VDD CB ptr
;
;EXIT:	    none
;
;USES:	    flags, EAX, ECX
;
;==============================================================================
BeginProc VDD_VGA_Restore_DAC, PUBLIC

	push	edx
	push	esi
	lea	esi,[edi.VDD_DAC]
	mov	ecx,DAC_State_Size/4		; 256 DAC registers
	TestMem [Vid_Flags], fVid_MsgA		; Q: Message mode?
	jz	SHORT VVRDAC_0			;   N: continue
	mov	ecx,DAC_Msg_State_Size/4	;   Y: only restore 16 colors
VVRDAC_0:

        cld

IFDEF VGA8514
	VMMCall Test_Sys_VM_Handle
	mov	edx, p8514DACWindx
	je	SHORT VVRDAC_1
ENDIF
	mov	dx,pDACWindx
VVRDAC_1:
	lodsd
	out	dx,al				; Set index then data
	IO_Delay
	inc	edx				; mov	  edx,pDACData
.errnz pDACData - pDACWindx - 1
IFDEF VGA8514
.errnz p8514DACData - p8514DACWindx - 1
ENDIF
	shr	eax,8
	out	dx,al				; Output red
	IO_Delay
	shr	eax,8
	out	dx,al				; Output green
	IO_Delay
	shr	eax,8
	out	dx,al				; Output blue
	IO_Delay
	dec	edx				; mov	  edx,pDACWindx
	loopd	VVRDAC_1
	pop	esi
	pop	edx
	ret

EndProc VDD_VGA_Restore_DAC

VxD_CODE_ENDS

	END
