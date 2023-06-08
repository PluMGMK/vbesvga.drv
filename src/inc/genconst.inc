;----------------------------Module-Header------------------------------;
; Module Name: GENCONST.BLT
;
; Constants for general use in BitBLT.
;
; Created: In Windows' distant past (c. 1983)
;
; Copyright (c) 1983 - 1987  Microsoft Corporation
;
; This file is a catchall for constants for use in BitBLT.
;
; This file is part of a set that makes up the Windows BitBLT function
; at driver-level.
;-----------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.

;	The following equates are for stuffing into the generated BLT.
;	For full 16-bit values, the two bytes are reversed so that they
;	come out correctly when stored in memory (i.e. the 8088 stores
;	the LSB first).


I_ADC_MEM_BYTE_I	equ	01680h	;ADC	byte ptr [####],##
I_ADD_AL_BYTE_I		equ	004h	;ADD	al,##
I_ADD_AX_WORD_I		equ	005h	;ADD	ax,####
I_ADD_BH_BYTE_I		equ	0C780h	;ADD	bh,##
I_ADD_BX_WORD_I		equ	0C318h	;ADD	bx,####
I_ADD_DI_WORD_I		equ	0C781h	;ADD	di,####
I_ADD_DX_BYTE_I		equ	0C283h	;ADD	dx,##
I_ADD_SI_BYTE_I		equ	0C683h	;ADD	si,##
I_ADD_SI_WORD_I		equ	0C681h	;ADD	si,####
I_ADD_MEM_BYTE_I	equ	00680h	;ADD	byte ptr [####],##

I_AND_AL_MEM		equ	00622h	;AND	al,[####]
I_AND_AL_BYTE_I		equ	024h	;AND	al,##
I_AND_AX_BP		equ	0E821h	;AND	ax,bp
I_AND_AX_WORD_I		equ	025h	;AND	ax,####
I_AND_MEM_BYTE_I	equ	02680h	;AND	byte ptr [####],##
I_AND_BP_I		equ	0E581H	;AND	bp,####

I_CALL_FAR		equ	09Ah	;CALL	####:####
I_CBW			equ	098h	;CBW
I_CMP_AL_BYTE_I		equ	03Ch	;CMP	al,##
I_CMP_AX_WORD_I		equ	03Dh	;CMP	ax,####
I_CMP_CX_2		equ	0F983h	;CMP	cx,2
I_CMP_CX		equ	0F983h	;CMP	cx,
I_CS_OVERRIDE           equ     02Eh    ;CS:

I_DEC_AL		equ	0C8FEh	;DEC	al
I_DEC_CX		equ	049h	;DEC	cx
I_DEC_DI		equ	04Fh	;DEC	di
I_DEC_SI		equ	04Eh	;DEC	si
I_DEC_MEM_BYTE		equ	00EFEh	;DEC	byte ptr [####]
I_DEC_MEM_WORD		equ	0EFFh	;dec	word ptr [####]

I_ES_OVERRIDE		equ	026h	;ES:

I_INC_AL		equ	0C0FEh	;INC	al
I_INC_DI		equ	047h	;INC	di
I_INC_SI		equ	046h	;INC	si
I_INC_BP		equ	045h	;INC	bp
I_INC_MEM_BYTE          equ     006FEh  ;INC    byte ptr [####]

I_DEC_BP		equ	04DH	;DEC	bp

I_JC			equ	072h	;JC	...
I_JC_P5H		equ	00372h	;JC	$+5
I_JC_P0DH		equ	00B72h	;JC	$+0Dh
I_JC_P12H		equ	01072h	;JC	$+12h
I_JE			equ	0074h	;JE


I_JMP_NEAR		equ	0E9h	;JMP	near
I_JMP_SHORT		equ	0EBH	;jmp	short

I_JNC			equ	073h	;JNC	...
I_JNC_P12H		equ	01073h	;JNC	$+12h
I_JNS_P6		equ	00479H	;JNS	$+6

I_JZ			equ	074h	;JZ	...
I_JZ_P5			equ	00374h	;JZ	$+5

I_LDS_BX_MEM		equ	01EC5h	;lds	bx,[####]
I_LDS_DX_MEM		equ	016C5h	;lds	dx,[####]
I_LDS_SI_MEM		equ	036C5h	;lds	si,[####]
I_LEA_AX_SI_DISP16	equ	0848Dh	;lea	ax,[si+####]
I_LEA_AX_DI_DISP16	equ	0858Dh	;lea	ax,[di+####]
I_LODSB			equ	0ACh	;LODSB
I_LOOP			equ	0E2h	;LOOP

I_XCHG_AL_AH		equ	0C486H	;xchg	al,ah
I_MOV_AH_BL		equ	0DC88H	;mov	ah,bl
I_XCHG_AL_BL		equ	0C386H	;xchg	al,bl
I_MOV_AH_AL		equ	0C488h	;MOV	ah,al
I_MOV_AH_BYTE_I		equ	0B4h	;MOV	ah,##
I_MOV_AH_SRC		equ	0248AH	;mov	ah,[si]
I_MOV_AH_DEST		equ	0258Ah	;MOV	ah,[di]
I_MOV_AH_SI_DISP16	equ	0A48Ah	;MOV	ah,[si+####]
I_MOV_AL_0FFH		equ	0FFB0h	;MOV	al,0FFH
I_MOV_AL_AH		equ	0C48Ah	;MOV	al,ah
I_MOV_AL_BX		equ	0078Ah	;MOV	al,[bx]
I_MOV_AL_DL		equ	0C28Ah	;MOV	al,dl
I_MOV_AL_DH		equ	0C68Ah	;MOV	al,dh
I_MOV_AL_DEST		equ	0058Ah	;MOV	al,[di]
I_MOV_AL_MEM		equ	0A0h	;MOV	al,[####]
I_MOV_AL_SI_DISP16	equ	0848Ah	;MOV	al,[si+####]
I_MOV_AX_DS		equ	0D88Ch	;MOV	ax,ds
I_MOV_AX_DI		equ	0C78Bh	;MOV	ax,di
I_MOV_AX_ES		equ	0C08Ch	;MOV	ax,es
I_MOV_AX_SI		equ	0C68Bh	;MOV	ax,si
I_MOV_AX_WORD_I		equ	0B8h	;MOV	ax,####
I_MOV_BL_AL		equ	0C388h	;MOV	bl,al
I_MOV_BL_BYTE_I		equ	0B3h	;MOV	bl,##
I_MOV_BH_AH		equ	0E788h	;MOV	bh,ah
I_MOV_BH_BYTE_I		equ	0B7h	;MOV	bh,##
I_MOV_BP_WORD_I		equ	0BDh	;MOV	bp,####
I_MOV_BX_AX		equ	0C389h	;MOV	bx,ax
I_MOV_BX_WORD_I		equ	0BBh	;MOV	bx,####
I_MOV_CX_I		equ	0B9H	;mov	cx,####
I_MOV_CX_DS             equ     0D98Ch  ;MOV    cx,ds
I_MOV_CX_WORD_I		equ	0B9h	;MOV	cx,####
I_MOV_DH_BX_DISP8	equ	0778Ah	;MOV	dh,[bx+##]
I_MOV_DH_BX_DISP16	equ	0B78Ah	;MOV	dh,[bx+####]
I_MOV_DH_BP_DISP16	equ	0B68Ah	;MOV	dh,[bp+####]
I_MOV_DH_SI             equ     0348Ah  ;MOV    dh,[si]
I_MOV_DI_AX		equ	0F88Bh	;MOV	di,ax
I_MOV_DL_AL		equ	0D08Ah	;MOV	dl,al
I_MOV_DL_BYTE_I		equ	0B2h	;MOV	dl,##
I_MOV_DL_MEM		equ	0168Ah	;MOV	dl,[####]
I_MOV_DL_SI_BX		equ	0108Ah	;MOV	dl,[si][bx]
I_MOV_DS_AX		equ	0D88Eh	;MOV	ds,ax
I_MOV_DS_BX		equ	0DB8Eh	;MOV	ds,bx
I_MOV_DS_CX		equ	0D98Eh	;MOV	ds,cx
I_MOV_ES_AX		equ	0C08Eh	;MOV	es,ax
I_MOV_MEM_AL		equ	0A2h	;MOV	[####],al
I_MOV_MEM_BYTE_I	equ	006C6h	;MOV	[####],##
I_MOV_SI_AX		equ	0F08Bh	;MOV	si,ax
I_MOV_SI_WORD_I 	equ	0BEh	;MOV	si,####
I_MOV_BP_I		equ	0BDh	;MOV	bp,####
I_MOVSB 		equ	0A4h	;MOVSB
I_MOVSW			equ	0A5h	;MOVSW

I_NOT_AL		equ	0D0F6h	;NOT	al
I_NOT_AX		equ	0D0F7h	;NOT	ax

I_OR_AL_AH		equ	0C40Ah	;OR	al,ah
I_OR_AL_BH		equ	0F808h	;OR	al,bh
I_OR_AH_AL		equ	0E00Ah	;OR	ah,al

I_POP_BX		equ	05Bh	;POP	bx
I_POP_SI		equ	05Eh	;POP	si
I_POP_DI		equ	05Fh	;POP	di
I_POP_CX		equ	059h	;POP	cx
I_POP_DS		equ	01Fh	;POP	ds
I_PUSH_BX		equ	053h	;PUSH	bx
I_PUSH_SI		equ	056h	;PUSH	si
I_PUSH_CX		equ	051h	;PUSH	cx
I_PUSH_DI		equ	057h	;PUSH	di
I_PUSH_DS		equ	01Eh	;PUSH	ds
I_RCL_AH_1		equ	0D4D0h	;RCL	ah,1
I_REP			equ	0F3h	;REP
I_RET_NEAR		equ	0C3h	;RET	near
I_RET_FAR		equ	0CBh	;RET	far
I_ROL_AL_1		equ	0C0D0h	;ROL	al,1
I_ROL_AL_N		equ	0C0C0h	;ROL	al,#	(286+)
I_ROR_AL_1		equ	0C8D0h	;ROR	al,1
I_ROR_AX_N		equ	0C8C1h	;ROR	ax,#	(286+)
I_ROL_AX_N		equ	0C0C1h	;ROL	al,#	(286+)
I_ROL_BH_1              equ     0C7D0h  ;ROL    bh,1
I_ROL_BL_1		equ	0C3D0h	;ROL	bl,1
I_ROL_BL_N		equ	0C3C0h	;ROL	bl,#
I_ROL_BX_1		equ	0C3D1h	;ROL	bx,1
I_ROL_BX_N		equ	0C3C1h	;ROL	bx,#

I_SBB_AL_AL		equ	0C018h	;SBB	al,al
I_SBB_MEM_BYTE_I	equ	01E80h	;SBB	byte ptr [####],##
I_SHL_BL_1		equ	0E3D0h	;SHL	bl,1
I_SS_OVERRIDE		equ	036h	;SS:
I_STOSB			equ	0AAh	;STOSB
I_STOSW			equ	0ABh	;STOSW
I_SUB_AL_BYTE_I		equ	02Ch	;SUB	al,##
I_SUB_AX_WORD_I		equ	02Dh	;SUB	ax,####
I_SUB_DI_WORD_I		equ	0EF81h	;SUB	di,####
I_SUB_SI_WORD_I		equ	0EE81h	;SUB	si,####
I_SUB_MEM_BYTE_I	equ	02E80h	;SUB	byte ptr [####],##

I_XLAT			equ	0D7h	;XLAT
I_XLAT_SS_BX		equ	0D736H	 ;xlat ss:[bx]

I_XOR_AL_AH		equ	0E030h	;XOR	al,ah
I_XOR_AL_MEM		equ	00632h	;XOR	al,[####]
I_XOR_AL_BYTE_I		equ	034h	;XOR	al,##
I_XOR_AX_WORD_I		equ	035h	;XOR	ax,####
I_XOR_BH_BH		equ	0FF32h	;XOR	BH,BH
I_XOR_MEM_WORD_I	equ	03681H	;XOR	[####],####


