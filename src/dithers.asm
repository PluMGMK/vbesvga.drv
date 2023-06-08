;*********************************Module*Header********************************
;Module name: DITHERS.ASM
;This module contains the new dither routines for the EGA/VGA 4 plane color
;display drivers.
;
; Copyright (c) 1983-1990 Microsoft Corporation.  All rights reserved.
;
;This code will be in the fixed segment of the driver.
;
;This neat algorithm was developed and implemented by Gunter Zieber.  It will
;be commented and described in some detail in a few days.
;History:   Nov 14, 1989    created -by- GÅnter Zieber [GunterZ]
;******************************************************************************
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.

.xlist
include cmacros.inc
include gdidefs.inc
include display.inc
include macros.mac
.list

PATTERNSIZE	equ 64

sBegin	Code

assumes cs, Code
assumes ds, Data
assumes es, nothing

	externW _cstods

SubDivPlanes	label	word
	dw	128, 128, 0
	dw	-1, 0, 0
	dw	128, 128, 0
	dw	-1, -1, 0
	dw	128, 128, 128
	dw	-1, 0, -1
	dw	255, 255, 0
	dw	-1, 0, 0

TransformTable	label	word
	db	32, 32, 0
	db	-2, 0, 0
	db	2, -2, 0
	db	0, 0, 2
	db	2, 0, 1, 3		;pts 3, 1, 2, 4

	db	32, 32, 0
	db	-2, -2, 0
	db	2, 0, 0
	db	0, 0, 2
	db	2, 1, 4, 3		;pts 3, 2, 5, 4

	db	32, 32, 0
	db	1, -1, 0
	db	1, 1, 0
	db	0, 0, 2
	db	2, 4, 5, 3		;pts 3, 5, 6, 4

	db	64, 0, 0
	db	-2, 0, 0
	db	0, 1, -1
	db	1, 0, 1
	db	4, 3, 5, 6		;pts 5, 4, 6, 7

PColorMap	label	byte
	db	0
	db	1
	db	3
	db	8
	db	9
	db	0bh
	db	0fh

PColorIntensities   label   byte
	db	0	      ;0  black
	db	02h	      ;1  dark red
	db	03h	      ;2  dark green
	db	06h	      ;3  dark yellow
	db	01h	      ;4  dark blue
	db	04h	      ;5  dark magenta
	db	05h	      ;6  dark cyan
	db	0ffh
        db      07h           ;7  grey
	db	0ah	      ;9  red
	db	0bh	      ;10 green
	db	0eh	      ;11 yellow
	db	09h	      ;12 blue
	db	0ch	      ;13 magenta
	db	0dh	      ;14 cyan
	db	0fh	      ;15 white

DitherPatternTable  label   byte
    db	 0, 32,  8, 40,  2, 34, 10, 42
    db	48, 16, 56, 24, 50, 18, 58, 26
    db	12, 44,  4, 36, 14, 46,  6, 38
    db	60, 28, 52, 20, 62, 30, 54, 22
    db	 3, 35, 11, 43,  1, 33,  9, 41
    db	51, 19, 59, 27, 49, 17, 57, 25
    db	15, 47,  7, 39, 13, 45,  5, 37
    db	63, 31, 55, 23, 61, 29, 53, 21


ColorCount  struc
    ccCount db	?
    ccIndex db	?
ColorCount  ends


Transformation	struc
    xOrigin	db  3 dup(0)
    xMatrix	db  9 dup(0)
    xCOrigin	db  0
    xBase	db  3 dup(0)
Transformation	ends


cProc	Compute256Indices, <NEAR, PUBLIC>,<si>
cBegin
	jcxz	comp256_exit
comp256_loop:
	lods	word ptr ss:[si]
	cmp	ah,8
	jb	comp256_loop2
	and	ah,7
	add	ah,0f8h
	mov	ss:[si-1],ah
;
comp256_loop2:
	loop	comp256_loop
;
comp256_exit:
cEnd


cProc	ComputeSymmetry, <NEAR, PUBLIC>
cBegin
	sub	ax, ax
	mov	ch, dl			;now: BL: red, CL: green, CH: blue
	cmp	bl, ch			;is red greater of equal blue?
	jnc	CheckPlane2		;if so, don't transpose R and B
	xchg	bl, ch			;transpose R and B
CheckPlane2:
	rcl	ax, 1			;put carry flag into LSB of AX
	cmp	cl, ch			;is green greater or equal blue?
	jnc	CheckPlane3
	xchg	cl, ch
CheckPlane3:
	rcl	ax, 1
	cmp	bl, cl			;is red greater or equal green?
	jnc	ComputeSymmetryDone
	xchg	bl, cl
ComputeSymmetryDone:
	rcl	ax, 1
cEnd


cProc	ComputeSubSpace, <NEAR, PUBLIC>
cBegin
	mov	si, CodeOFFSET SubDivPlanes
	push	bp
CSSMainLoop:
	sub	di, di			;BL: red, CH: blue, CL: green
	mov	bp, 3
CSSLoop:
	sub	ax, ax
	mov	al, bl
	sub	ax, word ptr cs:[si]
	imul	word ptr cs:[si][6]
	inc	si
	inc	si
	xchg	bl, cl
	xchg	cl, ch
	add	di, ax
	dec	bp
	jnz	CSSLoop
	inc	bh
	add	si, 6
	or	di, di
	js	CSSMainLoop
	mov	al, bh
	dec	ax
	pop	bp
cEnd


cProc	ComputeTransform, <NEAR, PUBLIC>
cBegin
	xchg	bx, bp			;SS:BP->RGB,CS:SI->Xform,SS:BX->locals
	sub	di, di			;DI: index.
	mov	cx, 3
CTMoveOriginLoop:
	lods	byte ptr cs:[si]
	sub	[bp][di], ax
	inc	di
	inc	di
	loop	CTMoveOriginLoop

	push	bx			;save offset to local variables
	mov	cx, 3
CTMainLoop:
	push	cx
	sub	di, di
	sub	bx, bx
	mov	cx, 3
CTXformLoop:
	lods	byte ptr cs:[si]
	imul	byte ptr [bp][di]
	inc	di
	inc	di
	add	bx, ax
	loop	CTXformLoop

	pop	cx
	shr	di, 1
	sub	di, cx
	shl	di, 1
	mov	[bp][di][6], bx
	loop	CTMainLoop

	pop	bx
	add	bp, 6
	xchg	bx, bp
cEnd


cProc   ComputePColor, <NEAR, PUBLIC>, <si>
cBegin
	mov	ch, al
CPCMainLoop:
	lods	word ptr ss:[si]
	mov	al, ah
	xlatb	cs:[bx]
	shr	al, 1
	sbb	dl, dl
	shr	al, 1
	sbb	dh, dh
	shr	al, 1
	sbb	ah, ah
	push	ax
	mov	al, ch
	shr	al, 1
	jnc	CPCNoSwap_10
	xchg	dl, dh
CPCNoSwap_10:
	shr	al, 1
	jnc	CPCNoSwap_20
	xchg	dh, ah
CPCNoSwap_20:
	shr	al, 1
	jnc	CPCNoSwap_30
	xchg	dl, ah
CPCNoSwap_30:
	shr	ah, 1
	pop	ax
	rcl	al, 1
	shr	dh, 1
	rcl	al, 1
	shr	dl, 1
	rcl	al, 1
	mov	ss:[si][-1], al
	dec	cl
	jnz	CPCMainLoop
cEnd


cProc   MakeColorCntTable, <NEAR, PUBLIC>
cBegin
	sub	dx, dx
	xchg	bp, bx
	mov	ax, PATTERNSIZE
	sub	ax, ss:[di][0]
	sub	ax, ss:[di][2]
	sub	ax, ss:[di][4]
	mov	ah, al
	lods	byte ptr cs:[si]
	jz	MCTNoBaseCount
	xchg	al, ah
	mov	[bp], ax
	inc	dx
	inc	bp
	inc	bp
MCTNoBaseCount:
	mov	cx, 3
MCTCopyLoop:
	mov	ah, ss:[di]
	inc	di
	inc	di
	lods	byte ptr cs:[si]
	or	ah, ah
	jz	MCTBottomOfLoop
	xchg	al, ah
	mov	[bp], ax
	inc	bp
	inc	bp
	inc	dx
MCTBottomOfLoop:
	loop	MCTCopyLoop

	mov	ax, dx
	shl	dx, 1
	sub	bp, dx
	xchg	bp, bx
cEnd


cProc   SortColorCntTable, <NEAR, PUBLIC>
cBegin
	cmp	cl, 1
	jbe	SCTExit
	push	bp
	mov	ax, cx
	shl	ax, 1
	sub	sp, ax
	mov	bp, sp
	push	ax
	mov	dh, cl
	mov	di, bx
SCTOuterLoop:
	push	cx
	push	si
	sub	bx, bx
	mov	cl, dh
	mov	dl, -1
SCTInnerLoop:
	lods	word ptr ss:[si]
	mov	al, ah
	xchg	bx, di
	xlatb	cs:[bx]
	xchg	bx, di
	cmp	al, dl
	ja	SCTNextIteration
	mov	dl, al
	mov	bh, bl
SCTNextIteration:
	inc	bx
	loop	SCTInnerLoop

	pop	si
	mov	bl, bh
	sub	bh, bh
	shl	bx, 1
	mov	ax, ss:[bx][si]
	mov	[bp], ax
	inc	bx
	inc	bp
	inc	bp
	mov	byte ptr ss:[si][bx], 07h
	pop	cx
	loop	SCTOuterLoop

	mov	cl, dh
	pop	dx
	sub	bp, dx
	xchg	si, bp
	mov	di, bp
SCTCopyLoop:
	lods	word ptr ss:[si]
	mov	[bp], ax
	inc	bp
	inc	bp
	loop	SCTCopyLoop

	add	sp, dx
	pop	bp
	mov	si, di
SCTExit:
cEnd


cProc	MakeDitherBitmap, <NEAR, PUBLIC>, <di>
	parmW	nNumberOfColors

	localW	nOldColorCount
	localW	iLoop
cBegin
	sub	ax, ax
	mov	nOldColorCount, ax
MDBMainLoop:
	mov	iLoop, 8
	push	di
	push	dx
	push	bx
	mov	ax, nOldColorCount
	add	al, ss:[si]
	.errnz	ccCount
	mov	nOldColorCount, ax
	mov	ch, al			;CH: value to compare with
	inc	si

MDBOuterLoop:
	xchg	dx, bp			;SS:BP-->pattern bit mask
	mov	ah, [bp]		;get the previous pattern into AH
	mov	cl, 8			;a byte has 8 bits

MDBInnerPatternLoop_10: 		;compute next bit mask in AL
	cmp	cs:[bx], ch		;if CY make that bit a 1
	rcl	al, 1
	inc	bx
	dec	cl
	jnz	MDBInnerPatternLoop_10

	mov	[bp], al		;save new bitmask
	inc	bp
	xor	al, ah			;exclude bits from previous mask
	mov	ah, al
	mov	al, ss:[si]		;get color index in AL
	mov	cl, 8

MDBInnerPatternLoop_20:
	shl	ah, 1
	jnc	MDBInnerPatternLoop_30
	mov	ss:[di], al

MDBInnerPatternLoop_30:
	inc	di
	dec	cl
	jnz	MDBInnerPatternLoop_20

	xchg	dx, bp			;can access local variables again
	dec	iLoop
	jnz	MDBOuterLoop

	inc	si			;SS:SI-->next color index count
	pop	bx
	pop	dx
	pop	di
	dec	nNumberOfColors
	jnz	MDBMainLoop
cEnd

cProc	WritePBrush, <NEAR, PUBLIC>
cBegin

	; write the color portion of the brush

        mov     cx, SIZE_PATTERN*SIZE_PATTERN ;this is the loop counter
	rep	movs byte ptr es:[di], byte ptr ss:[si]
cEnd


;*********************************Public*Routine*******************************
;This routine contains the main procedure body for color dithering.
;
;On entry:  ES:DI-->output object
;******************************************************************************


cProc	ColorDither, <NEAR, PUBLIC>
	localW	nColors
	localV	wMappedColors, 12
	localV	BitMask, 8
	localV	BrushPixels, 8
	localV	TempPatternBitmap, 64
	localV	wRGB,4
	localB	nSymmetryIndex

cBegin

	mov	dh, ah
	sub	ah, ah
	mov	bx, ax			;BX: red
	mov	al, dh
	mov	cx, ax			;CX: green
	mov	dh, ah			;DX: blue
	cCall	ComputeSymmetry 	;make R >= G >= B
	mov	nSymmetryIndex,al
	mov	byte ptr [wRGB], bl	;save this for possible color dithering
	mov	word ptr [wRGB][1], cx	;later on BL: red, CL: green, CH: blue

	sub	ax, ax			;need to initialize a few local
	mov	word ptr BitMask[0], ax ; variables to zero
	mov	word ptr BitMask[2], ax
	mov	word ptr BitMask[4], ax
	mov	word ptr BitMask[6], ax
	mov	bl, byte ptr [wRGB]	;fetch RGB.  They were computed in
	mov	cx, word ptr [wRGB][1]	;rgb_to_ipc; no need to do it again
	sub	bh, bh
	push	di			;save offset to output object
	cCall	ComputeSubSpace 	;compute which subspace to use
	shiftl	ax, 4
	.errnz	(size Transformation)-16
	mov	si, ax
	add	si, CodeOFFSET TransformTable
	mov	al, bl
	shr	al, 1
	adc	al, ah
	shr	al, 1
	mov	word ptr wMappedColors[0], ax
	mov	al, cl
	shr	al, 1
	adc	al, ah
	shr	al, 1
	mov	word ptr wMappedColors[2], ax
	mov	al, ch
	shr	al, 1
	adc	al, ah
	shr	al, 1
	mov	word ptr wMappedColors[4], ax
	lea	bx, wMappedColors
	cCall	ComputeTransform	;on ret. CS:SI-->xCOrigin and
	mov	di, bx			;  SS:BX-->transformed colors
	lea	bx, BrushPixels 	;SS:BX-->where to put color cnt. struc.
	cCall	MakeColorCntTable
	mov	nColors, ax
	mov	si, bx			;SS:SI-->color cnt struc.
	mov	bx, CodeOFFSET PColorMap
	mov	cx, ax			;CX: number of colors to Xform
	mov	al, [nSymmetryIndex]	;AL: operation to perform
	cCall	ComputePColor		;on ret.: P colors in clr. cnt. struc.
	mov	cx, nColors
	mov	bx, CodeOFFSET PColorIntensities
	cCall	SortColorCntTable

	mov	cx,nColors		; convert to 256 color indices
	cCall	Compute256Indices

        lea     di, TempPatternBitmap   ;SS:DI-->output obj., SS:SI--> clr.c.
	lea	dx, BitMask		;SS:DX-->previous pattern bitmask
	mov	bx, CodeOFFSET DitherPatternTable
	arg	nColors 		;CS:BX-->pattern generation table
	cCall	MakeDitherBitmap	;go do the magic.  SS:DI-->tmp bmp
	mov	si, di			;SS:SI-->tmp pattern bitmap (8x8 bytes)
	pop	di			;ES:DI-->output object
	cCall	WritePBrush		;convert to ?GA format

cEnd

sEnd	Code
end

