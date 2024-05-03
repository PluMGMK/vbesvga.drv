PAGE 58,132
;******************************************************************************
TITLE vddfonts.asm -
;******************************************************************************
;
;   (C) Copyright MICROSOFT Corp.  All Rights Reserved, 1989, 1990
;
;   Title:	vddfonts.asm -
;
;   Version:	1.00
;
;   Date:	22-Oct-1991
;
;   Author:	RAP
;
;------------------------------------------------------------------------------
;
;   Change log:
;
;      DATE	REV		    DESCRIPTION
;   ----------- --- -----------------------------------------------------------
;   22-Oct-1991 RAP
;
;==============================================================================

	.386p

.xlist
	INCLUDE VMM.INC
	INCLUDE OPTTEST.INC
	INCLUDE VDD.INC
	INCLUDE VDD2.INC
	INCLUDE DEBUG.INC
	INCLUDE VDDDEF.INC
	INCLUDE VDDPHMEM.INC
.list

;******************************************************************************
; EXTRN routines
;
VxD_CODE_SEG

	EXTRN	VDD_VM_Mem_MapNull:NEAR
	EXTRN	VDD_VM_Mem_Disable_Null:NEAR
	EXTRN	VDD_VM_Mem_Lock_SaveMem_Page:NEAR
	EXTRN	VDD_VM_Mem_Unlock_Save_Mem:NEAR
	EXTRN	VDD_VM_Mem_Select_Plane:NEAR
	EXTRN	VDD_VM_Mem_zero_page_no_pushad:NEAR
	EXTRN	VDD_State_Set_MemC_Planar:NEAR
	EXTRN	VDD_OEM_Adjust_Font_Access:NEAR
IFDEF TLVGA
	EXTRN	VDD_OEM_TLVGA_Set_Graphics:NEAR
	EXTRN	VDD_OEM_TLVGA_Reset_Graphics:NEAR
ENDIF

VxD_CODE_ENDS


VxD_IDATA_SEG

	EXTRN	VDD_Use_ROM_Font_Ini:BYTE
	EXTRN	VMPagesBuf:DWORD

Vid_msg_font_handle dd	0
Vid_msg_font_addr   dd	?

Vid_FontLen	    dd	?

ROM_font_flag	    db	0

VxD_IDATA_ENDS


VxD_DATA_SEG
	EXTRN	Vid_Flags:DWORD
	EXTRN	VT_Flags:DWORD
	EXTRN	Vid_Focus_VM:DWORD
	EXTRN	Vid_CRTC_VM:DWORD
	EXTRN	Vid_MemC_VM:DWORD
	EXTRN	Vid_Msg_Pseudo_VM:DWORD
	EXTRN	Vid_PhysA0000:DWORD
	EXTRN	Vid_Msg_VM:DWORD
	EXTRN	Vid_MsgMode_Text_Rows:DWORD
	EXTRN	Vid_MsgMode_Text_Cols:DWORD

Vid_MsgFontH	    dd	0
Vid_MsgFont	    dd	?
Vid_CharHgt	    db	?

VxD_DATA_ENDS


VxD_ICODE_SEG

;******************************************************************************
;
;   VDD_Font_Setup_Msg_Mode_Init
;
;   DESCRIPTION:    Setup for INT 10h mode 3 that VDDState is about to do to
;		    init message mode.	We either map null in A0 & A1, or
;		    alloc memory and map it at A0 & A1.
;
;   ENTRY:	    EBX = VM_Handle of SYS VM
;		    EDI -> VDD CB data
;
;   EXIT:	    Carry set if failed
;
;   USES:
;
;==============================================================================
BeginProc VDD_Font_Setup_Msg_Mode_Init

;
; map null memory for A0-AF to catch font loads
;
	mov	dx, 0A010h
@@:
	movzx	eax, dh
	call	VDD_VM_Mem_MapNull
	inc	dh
	dec	dl
	jnz	@B

	xor	eax, eax		; map save mem for font
	VMMCall _PageAllocate,<2,PG_SYS,eax,eax,eax,eax,eax,PageFixed+PageZeroInit>
	or	eax, eax		;Q: alloc worked?
	jz	short @F		;   N:
	mov	[Vid_msg_font_handle], eax
	mov	[Vid_msg_font_addr], edx
	VMMCall _MapIntoV86,<eax,ebx,0A0h,2,0,0> ; map 2 pgs for font save
@@:

;
; map null memory for B8-BF
;
	mov	dh, 0B8h
	mov	dl, 8
IFDEF VGAMONO
	TestMem [edi.VDD_TFlags],fVT_Mono   ; Q: Mono supported?
	jz	short @F		    ;	N:
	mov	dh, 0B0h
	mov	dl, 16
ENDIF
@@:
	movzx	eax, dh
	call	VDD_VM_Mem_MapNull
	inc	dh
	dec	dl
	jnz	@B

	clc
	ret

amf_failed:
	Debug_Out "Alloc message mode font mem failed"
	VMMJmp	Fatal_Memory_Error

EndProc VDD_Font_Setup_Msg_Mode_Init


;******************************************************************************
;
;   VDD_Font_Save_Msg_Font
;
;   DESCRIPTION:    Calls VDD_State_Set_MemC_Planar to access the font in
;		    plane 2.  A VGA font is made up of an array of 32 byte
;		    blocks.  One 32 byte block for each character.  This
;		    routine determines the actual font height by looking at
;		    the cell height register (index 9) in the CRT controller.
;		    It then either calls INT 10h function 1130h to find the
;		    location of the ROM font, or it compresses the font from
;		    video save memory into allocated memory by only copying
;		    "cell height" bytes per character instead of 32.
;
;   ENTRY:	    EBX = VM_Handle of SYS VM
;		    EDI -> VDD CB data
;
;   EXIT:	    Carry set, if unable to allocate memory for font save
;			or planar mode not initialized (should never occur)
;
;   USES:	    EAX, ECX, EDX, ESI, Flags
;
;==============================================================================
BeginProc VDD_Font_Save_Msg_Font

Assert_VDD_ptrs ebx,edi

	BEGIN_Touch_1st_Meg
	movzx	eax, byte ptr ds:[BIOS_Line_Count]
	inc	eax
	mov	[Vid_MsgMode_Text_Rows], eax
	movzx	eax, byte ptr ds:[BIOS_Col_Count]
	END_Touch_1st_Meg
	mov	[Vid_MsgMode_Text_Cols], eax

	movzx	ecx, [edi.VDD_Stt.C_CharHgt]
	and	cl, 1Fh 		; isolate 5 bits of height
	inc	ecx
	mov	[Vid_CharHgt], cl
IFDEF DEBUG_verbose
	Trace_Out 'Msg char cell hgt = #cl'
ENDIF
	shl	ecx, 8			; ecx = total # of bytes in font
	mov	[Vid_FontLen], ecx
IFDEF DEBUG_verbose
	Trace_Out 'font length = #cx'
ENDIF

	cmp	[Vid_msg_font_handle],0 ;Q: can we use programmed font?
	jz	short use_rom_font	;   N:

;
; check INI switch to see if we should use the font directly out of ROM
;
	push	edi
	xor	esi,esi 		; [WIN386] section
	mov	edi, OFFSET32 VDD_Use_ROM_Font_Ini ; Find this string
	or	eax, TRUE		; default yes
	VMMcall Get_Profile_Boolean	; Q: use ROM font?
	pop	edi
	jbe	short @F		; jump if not found or empty
	or	al, al
	jz	short @F
	mov	al, 1
@@:
	mov	[ROM_font_flag], al	;0 = false, -1 = true, 1 = forced true
	or	eax, eax
	jz	pack_font		;   N: use programmed font

;
; simulate an INT 10 down in VM to get a pointer to the ROM font
;
use_rom_font:
	push	edi
	movzx	ecx, [Vid_CharHgt]
	push	ecx
	Push_Client_State
	VMMcall Begin_Nest_Exec 	; Get ready for software ints
	mov	al, 6			; assume charhgt = 16
	mov	cl, 16
	cmp	[Vid_CharHgt], cl	;Q: use 8x16 ROM font?
	jae	short @F		;   Y:
	mov	cl, 8
	mov	al, 3
	cmp	[Vid_CharHgt], 14	;Q: use 8x8 ROM font?
	jb	short @F		;   Y:
	mov	al, 2			;   N: use 8x14
	mov	cl, 14
@@:
	xchg	cl, [Vid_CharHgt]
	cmp	[Vid_CharHgt], cl	;Q: available ROM font hgt <= needed?
	jbe	short @F		;   Y: use ROM font
	cmp	[Vid_msg_font_handle],0 ;Q: can we use programmed font?
	jnz	use_soft_font		;   Y: use it, because we can't fit
					;	ROM font very well

@@:
	mov	[ebp.Client_BH], al
	mov	[ebp.Client_AX], 1130h	; Get font ptr
	mov	eax,10h
	VMMcall Exec_Int
	movzx	esi, [ebp.Client_ES]
	movzx	ecx, [ebp.Client_BP]
	shl	esi, 4
	add	esi, ecx		; ptr to font
	VMMcall End_Nest_Exec		; All done with software ints
	Pop_Client_State

	cmp	[ROM_font_flag], 1
	je	short smf_use_rom

	xor	eax, eax
	VMMCall _Get_Device_V86_Pages_Array,<eax,<OFFSET32 VMPagesBuf>,eax>
	mov	ecx, esi
	shr	ecx, 12
	bt	[VMPagesBuf], ecx	;Q: page claimed by a device?
	jnc	short smf_use_rom	;   N: must be okay
	pop	ecx			;   Y: assume bad
	jmp	short smf_no_rom_font

smf_use_rom:
	mov	ecx, [Vid_FontLen]
	VMMCall _MapPhysToLinear,<esi,ecx,0>
	pop	ecx			; ecx = original Vid_CharHgt
	inc	eax
	jnz	SHORT smf_GotPhysAddr
	Trace_Out "VDD: Cannot address video ROM font memory @#esi"
smf_no_rom_font:
	pop	edi
	mov	[Vid_CharHgt], cl	; restore original Vid_CharHgt
	cmp	[Vid_msg_font_handle],0 ;Q: can we use programmed font?
	jne	short pack_font 	;   Y:
	jmp	smf_failed		;   N:

smf_GotPhysAddr:
	dec	eax
	mov	[Vid_MsgFont], eax
	mov	eax, [Vid_msg_font_handle]
	or	eax, eax
	jz	smf_done
	VMMCall _PageFree,<eax,0> ; free tmp font mem
	jmp	smf_done

use_soft_font:
	Trace_Out 'forced to programmed font (height=#cl)'
	VMMcall End_Nest_Exec		; All done with software ints
	Pop_Client_State
	pop	ecx
	mov	[Vid_CharHgt], cl	; restore original Vid_CharHgt
	pop	edi

;
; Pack the font that was programmed by the ROM during the mode change.
;
pack_font:
	mov	ecx, [Vid_FontLen]
	add	ecx, P_SIZE - 1
	shr	ecx, 12 		; ecx = # of pages for font save
	cmp	ecx, 2
	jb	short @F
	mov	[Vid_CharHgt], 32	; force no packing
@@:
	xor	eax, eax
	VMMCall _PageAllocate,<ecx,PG_SYS,eax,eax,eax,eax,eax,PageLocked>
	or	eax, eax		;Q: alloc worked?
	jz	short smf_failed	;   N:
	mov	[Vid_MsgFontH], eax
	mov	[Vid_MsgFont], edx

	push	edi
	movzx	eax, [Vid_CharHgt]	; save cell height
	mov	ecx, 256		; # of chars in font
	mov	esi, [Vid_msg_font_addr]
	mov	edi, edx
	cld

save_fchar:
	push	ecx
	push	esi
	mov	ecx, eax
	rep	movsb
	pop	esi
	add	esi, 32 		; start of next char in font ram
	pop	ecx
	loop	save_fchar

	mov	edi, [esp]
	mov	eax, 0A0h		    ; map null memory over the 2 pages
	call	VDD_VM_Mem_MapNull	    ;	of font save memory previously
	mov	eax, 0A1h		    ;	mapped at A0 & A1, so that we
	call	VDD_VM_Mem_MapNull	    ;	can free the pages calling
					    ;	VDD_VM_Mem_Disable_Null will
					    ;	unmap the null memory later
	VMMCall _PageFree,<[Vid_msg_font_handle],0> ; free tmp font mem

IF 0
;
; This code attempts to scan the ROM for a font match, but now we just use
; an INT 10h call to get a ptr to a ROM font.
;
	mov	edi, 0C0000h
smf_loop:
	push	edi
	mov	esi, [Vid_MsgFont]
	mov	ecx, [Vid_FontLen]
	repe	cmpsb
	pop	edi
	je	short smf_found
	inc	edi
	cmp	edi, 0D0000h
	jb	smf_loop
	Trace_Out 'font not found (not an error)'
	jmp	short smf_done
smf_found:
	Trace_Out 'font found @#edi, freeing font save block'
	mov	eax, [Vid_FontLen]
	VMMCall _MapPhysToLinear,<edi,eax,0>
	inc	eax
	jnz	SHORT smf_GotPhysAddr
	Debug_Out "VDD: Cannot address video ROM font memory @#edi"
	jmp	short smf_done
smf_GotPhysAddr:
	dec	eax
	mov	[Vid_MsgFont], eax
	xor	eax, eax
	xchg	eax, [Vid_MsgFontH]
	VMMCall _PageFree,<eax,0>
ENDIF

smf_done:
	clc
smf_exit:
IFDEF DEBUG
	mov	edi, [Vid_MsgFont]
	Trace_Out 'Msg Mode Font @#edi'
ENDIF
	pop	edi
	pushfd
	call	VDD_VM_Mem_Disable_Null
	popfd
	ret

smf_failed:
	Debug_Out "Save Message font failed"
	VMMJmp	Fatal_Memory_Error

EndProc VDD_Font_Save_Msg_Font


;******************************************************************************
;
;   VDD_Font_Init_Complete
;
;   DESCRIPTION:    Unlock msg mode font save page and SYS VM's save memory,
;		    if system is running with an intelligent (direct hardware)
;		    pageswap device.
;
;   ENTRY:	    EBX = SYS VM Handle
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_Font_Init_Complete

	pushad
	mov	eax, [Vid_MsgFontH]
	or	eax, eax
	jz	short ic_no_msg_font_page
	mov	ecx, [Vid_FontLen]
	add	ecx, P_SIZE - 1
	shr	ecx, 12 		; ecx = # of pages for font save
	VMMCall _PageUnLock,<eax, ecx, 0, PageLockedIfDP>
ic_no_msg_font_page:

	SetVDDPtr   edi
	mov	ecx, 4
	call	VDD_VM_Mem_Unlock_Save_Mem
	popad
	clc
	ret

EndProc VDD_Font_Init_Complete

VxD_ICODE_ENDS


VxD_CODE_SEG

;******************************************************************************
;
;   VDD_Font_save_font
;
;   DESCRIPTION:    Copy a 4Kb page of a text mode RAM font from physical
;		    video memory to a page of VM save memory.  This routine
;		    requires that the hardware be set up for the font read.
;		    It handles finding a free spot in the fontmap table in
;		    VDD_MStt, if not already assigned.
;
;   ENTRY:	    EAX = page handle
;		    EBX = owner VM handle
;		    EDI = VDD CB ptr
;		    ECX = physical page #
;		    ESI -> MMS_Plane_Info_Struc for plane being saved
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_Font_save_font

	pushad
	movzx	edx, [eax.PDS_virtual_id]
	mov	ecx, edx
	shr	edx, 1			    ; font index  (carry set, if 2nd page)
	jz	short cf_font0		    ; don't need table lookup for font0
	movzx	ecx, [edx][edi.VDD_MStt.MSS_fontmap]
	jecxz	short cf_need_pos
	jmp	short cf_font_has_pos

cf_need_pos:
;
; locate free position for font in save memory
;
	lea	ebx, [edi.VDD_MStt.MSS_fontmap+1]
	mov	ecx, 7
	mov	ebp, 11111110b
cf_find_free:
	movzx	edx, byte ptr [ebx]
	shr	edx, 1
	btr	ebp, edx
	inc	ebx
	loop	cf_find_free
	bsf	ecx, ebp
	shl	ecx, 1
	movzx	edx, [eax.PDS_virtual_id]
	shr	edx, 1			    ; font index
	mov	[edx][edi.VDD_MStt.MSS_fontmap], cl ; record save mem page offset
cf_font_has_pos:
	adc	ecx, 0			    ; inc start page, if 2nd page of font
cf_font0:
	mov	edx, ecx
	call	VDD_VM_Mem_Lock_SaveMem_Page
	jc	short cf_exit
	mov	edi, ecx
	shl	edi, 12
	add	edi, [esi.MSS_plane_addr]   ; edi -> copy dst in copy mem
	mov	esi, [esp.Pushad_ECX+2*4]   ;	(WARNING 2 extra values on
					    ;	 stack after PUSHAD frame)
	shl	esi, 12 		    ; convert src page # to adr
	sub	esi, 0A0000h
	add	esi, [Vid_PhysA0000]	    ; convert phys adr to linear
	mov	ecx, P_SIZE
	cld
	rep	movsb
	pop	ecx			    ; pop page # & mem handle from call
	pop	eax			    ; to VDD_VM_Mem_Lock_SaveMem_Page
	VMMCall _PageUnLock,<eax,1,ecx,0>
cf_exit:
	popad
	ret

EndProc VDD_Font_save_font


;******************************************************************************
;
;   VDD_Font_restore_font
;
;   DESCRIPTION:    Copy a 4Kb page of a text mode RAM font from VM save
;		    memory to a physical video memory page.  This routine
;		    requires that the hardware be set up for the font write.
;
;   ENTRY:	    EAX = page handle
;		    EBX = owner VM handle
;		    EDI = VDD CB ptr
;		    ECX = physical page #
;		    ESI -> MMS_Plane_Info_Struc for plane being restored
;
;   EXIT:	    none
;
;   USES:	    flags
;
;==============================================================================
BeginProc VDD_Font_restore_font

	pushad
IFDEF DEBUG
	EXTRN	VDD_VM_Mem_Chk_Bank_DEBUG:NEAR
	call	VDD_VM_Mem_Chk_Bank_DEBUG
ENDIF
	movzx	edx, [eax.PDS_virtual_id]
	mov	eax, edx
	shr	eax, 1			    ; font index  (carry set, if 2nd page)
	jz	short rf_font0		    ; don't need table lookup for font0
	movzx	edx, [eax][edi.VDD_MStt.MSS_fontmap]
	mov	eax, edx
	adc	edx, 0			    ; inc start page, if 2nd page of font
	or	eax, eax
	jz	VDD_VM_Mem_zero_page_no_pushad ; jump if no font
rf_font0:				    ; edx = page id, ecx = phys page #
	call	VDD_VM_Mem_Lock_SaveMem_Page
	jc	VDD_VM_Mem_zero_page_no_pushad ; jump into VDD_VM_Mem_zero_page
	shl	edx, 12
	add	edx, [esi.MSS_plane_addr]   ; edx -> copy src in copy mem
	shl	ecx, 12 		    ; convert dst page # to adr
	sub	ecx, 0A0000h
	add	ecx, [Vid_PhysA0000]	    ; convert phys adr to linear
	mov	edi, ecx
	mov	esi, edx
	mov	ecx, P_SIZE
	cld
	rep	movsb
	pop	ecx
	pop	eax
	VMMCall _PageUnLock,<eax,1,ecx,0>
rf_exit:
	popad
	ret

EndProc VDD_Font_restore_font


;******************************************************************************
;
;   VDD_Font_Restore_Msg_Font
;
;   DESCRIPTION:    Restore packed msg mode font into the first 2 pages of
;		    video memory.
;
;   ENTRY:	    EBX = owner VM handle
;		    EDI = VDD CB ptr
;
;   EXIT:	    If carry flag set, restore failed
;
;   USES:	    EAX, ECX, EDX, ESI, Flags
;
;==============================================================================
BeginProc VDD_Font_Restore_Msg_Font

Assert_VDD_ptrs ebx,edi,Pseudo_OK

	call	VDD_State_Set_MemC_Planar
	call	VDD_OEM_Adjust_Font_Access  ; some OEM adapters need to modify
					    ;	the planar state for saving or
					    ;	restoring the soft text fonts.
IFDEF	DEBUG
	jnc	SHORT VMRMF_DB_00
Debug_Out "Message mode font restore failed"
VMRMF_DB_00:
ENDIF
	jc	SHORT VMRMF_Exit
	mov	dx, 402h
	call	VDD_VM_Mem_Select_Plane

IFDEF TLVGA
	TestMem [edi.VDD_TFlags], <fVT_TLVGA OR fVT_TL_ET4000>
	jz	SHORT rmf_Not_TL00
	call	VDD_OEM_TLVGA_Set_Graphics
	push	eax
rmf_Not_TL00:
ENDIF

	push	edi
	mov	edi, [Vid_PhysA0000]	; EDI = start of VRAM
	call	VDD_Font_Expand_Msg_Font
	pop	edi

IFDEF TLVGA
	TestMem [edi.VDD_TFlags], <fVT_TLVGA OR fVT_TL_ET4000>
	jz	SHORT rmf_Not_TL01
	pop	eax
	call	VDD_OEM_TLVGA_Reset_Graphics
rmf_Not_TL01:
ENDIF
	clc
VMRMF_Exit:
	ret

EndProc VDD_Font_Restore_Msg_Font


;******************************************************************************
;
;   VDD_Font_Expand_Msg_Font
;
;   DESCRIPTION:    Copy packed message mode font into the expanded 32 byte
;		    per character form used in video memory.
;
;   ENTRY:	    EDI -> memory to receive expanded font
;
;   EXIT:	    none
;
;   USES:	    EAX, ECX, ESI, Flags
;
;==============================================================================
BeginProc VDD_Font_Expand_Msg_Font

	push	edx
	mov	dl, [Vid_CharHgt]	; save cell height
	mov	dh, 32
	sub	dh, dl
	mov	ecx, 256		; # of chars in font
	mov	esi, [Vid_MsgFont]
	cld
	xor	eax, eax
restore_fchar:
	push	ecx
	movzx	ecx, dl
	rep	movsb
	movzx	ecx, dh
	rep	stosb
	pop	ecx
	loop	restore_fchar
	pop	edx
	ret

EndProc VDD_Font_Expand_Msg_Font


VxD_CODE_ENDS

	END
