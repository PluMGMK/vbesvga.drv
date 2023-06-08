;*********************************Module*Header********************************
;This module contains the routines that perform the RGB to physical index
;color matching.
;
; Copyright (c) 1983-1990 Microsoft Corporation.  All rights reserved.
;
;This neat algorithm was developed and implemented by GÅnter Zieber.  It will
;be commented and described in some detail in a few days.
;Created -by- GÅnter Zieber [GunterZ] on Nov. 20, 1989
;******************************************************************************
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.

.xlist
include cmacros.inc
include macros.mac
.list

SCALEFACTOR	    equ     128
COLOR_THRESHOLD     equ     40

sBegin	Data
externB nSymmetryIndex			;in DITHERS.ASM
externB wRGB				;in DITHERS.ASM
sEnd	Data

sBegin	Code

externB PAccelTable			;defined in ?GA.ASM
externB PColorTable			;defined in ?GA.ASM
externB PMatchTable1			;defined in ?GA.ASM
externB PMatchTable2
externB PMatchTable3
externB PIndexTable1
externB PIndexTable2
externB PIndexTable3
externW _cstods

externA NUMBER_CL1_COLORS
externA NUMBER_CL2_COLORS
externA NUMBER_CL3_COLORS

externNP    ComputeSymmetry		;in DITHERS.ASM
externNP    ComputePColor		;in DITHERS.ASM

assumes cs, Code
assumes ds, nothing
assumes es, nothing

AxisHashTable	label	byte
	db	0
	db	2
	db	0
	db	0
	db	4
	db	2
	db	4
	db	0

ParameterOffsetTable	label	word
	dw	CodeOFFSET PMatchTable1
	dw	CodeOFFSET PIndexTable1
	dw	NUMBER_CL1_COLORS
	dw	CodeOFFSET PMatchTable2
	dw	CodeOFFSET PIndexTable2
	dw	NUMBER_CL2_COLORS
	dw	CodeOFFSET PMatchTable3
	dw	CodeOFFSET PIndexTable3
	dw	NUMBER_CL3_COLORS

cProc	rgb_to_ipc, <NEAR, PUBLIC>, <bx, cx, si, di>
cBegin
	WriteAux <'Colors'>
	mov	dh, ah
	sub	ah, ah
	mov	bx, ax			;BX: red
	mov	al, dh
	mov	cx, ax			;CX: green
	mov	dh, ah			;DX: blue
	cCall	ComputeSymmetry 	;make R >= G >= B
	mov	ds, _cstods
	assumes ds, Data
	mov	[nSymmetryIndex], al	;save original position in RGB space
	mov	byte ptr [wRGB], bl	;save this for possible color dithering
	mov	word ptr [wRGB][1], cx	;later on BL: red, CL: green, CH: blue
	or	bl, bl			;is it black we're dealing with?
	jnz	DoPreProcessing 	;no. Do normal stuff
	sub	ax, ax
	jmp	short Blackness 	;yes.
DoPreProcessing:
	mov	di, bx			;DI: red
	mov	bl, cl
	mov	si, bx			;SI: green
	mov	bl, ch			;BX: blue transformed (and un-Xformed)
	mov	cx, si
	sub	cx, bx			;CX: green transformed
	mov	dx, di
	sub	dx, si			;DX: red transformed

	xchg	bx, dx			;BX: R, CX: Y, DX: W
	cCall	ComputeSymmetry
	cbw
	mov	si, ax
	mov	al, cs:[si].AxisHashTable
	mov	si, ax
	shl	ax, 1
	add	si, ax
	add	si, CodeOFFSET ParameterOffsetTable
	lods	word ptr cs:[si]	;get P match table
	mov	dx, ax
	lods	word ptr cs:[si]	;get P index table
	mov	di, ax
	lods	word ptr cs:[si]	;get P match table item count
	mov	cx, ax
	mov	ch, al
	mov	si, dx			;CS:SI-->P match table
	mov	dx, -1			;DX: min. error
	mov	bl, byte ptr [wRGB]
SearchLoop:
	lods	byte ptr cs:[si]
	sub	al, bl
	sbb	ah, ah
	xor	al, ah
	sub	al, ah
	jz	ExactMatchFound
	cmp	al, dh
	jb	SetNewMinStuff
	dec	cl
	jnz	SearchLoop
	jmp	short MatchFound
ExactMatchFound:
	mov	dl, cl
	jmp	short MatchFound
SetNewMinStuff:
	mov	dl, cl
	mov	dh, al
	dec	cl
	jnz	SearchLoop
MatchFound:
	mov	bx, di			;CS:BX-->physical index table
	mov	ah, ch
	sub	ah, dl
	push	ax
	mov	si, sp
	mov	al, [nSymmetryIndex]
	mov	cx, 1
	cCall	ComputePColor
	pop	ax
Blackness:
	mov	dh, ah
	mov	al, ah
	cbw
	mov	bx, ax			    ;BX: physical color index
	or	dh, cs:[bx].PAccelTable     ;DH: phy. color index with accel.
	mov	ax, bx
	shl	bx, 1
	add	bx, ax
	mov	ax, word ptr cs:[bx].PColorTable[0] ;actual R and G in AX
	mov	dl, cs:[bx].PColorTable[2]  ;actual B in DL
cEnd

cProc	IndexToColor, <FAR, PUBLIC>, <si>
cBegin	nogen
	push	si			    ;save SI
	mov	al, dh			    ;get index into AL
	and	ax, 0fh 		    ;Modulo 16
	mov	si, ax			    ;SI: color index mod 16
	or	dh, cs:[si].PAccelTable     ;add accel. bits into dh
	shl	ax, 1
	add	si, ax			    ;SI: 3*color index mod 16
	mov	ax, word ptr cs:[si].PColorTable[0] ;AX: red, green
	mov	dl, cs:[si].PColorTable[2]  ;DL: blue
	pop	si			    ;restore SI
	retf				    ;return
cEnd	nogen

sEnd	Code
end
