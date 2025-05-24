;-----------------------------------------------------------------------------;
;                         PLYBITM8.ASM                                        ;
;                         ------------                                        ;
; This file contains the draw for solid line on byte/pixel BITMAPs and the    ;
; byte/pixel BITMAP move  routines. The file is included in POLYLINE.ASM      ;
;                                                                             ;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.
comment ~

This part contains the slice drawing routines for the byte/pixel BITMAPs.
They are very similar to what we have for VRAM VGA except that now the
organization of the memory is different and also the ROP2 codes will be
handled differently.

                         HANDLING THE ROP2 CODES
                         -----------------------

Given any particular existing pixel value, the ROP2 codes combined with the Pen
color value may affect the pixel in the following four manners:

                       . some bits may be set to 0
                       . some bits may be set to 1
                       . some bits may be inverted
                       . some bits are left unchanged

As the information in the bit map is explicitly organized in terms of color
planes, its makes sense to handle a plane at a time. As each plane contributes
just one bit towards the ultimate pixel value, the ROP2 code depending upon
the particular pen color value may either set the target bit to 0 or 1, invert
it or leave it unchanged. The ROP2 code values have very conveniently been
allocated, if R is the ROP2 code (in the range 0 through 0fh) then the
following relationship holds:

                         if PEN COLOR BIT = 0
                         then let R1 = MOD(R,4)
                         else let R1 = IDIV(R,4)

                         switch (R1)

                          {
                          case 0:  SET BITMAP BIT to ZERO     ; break
                          case 1:  INVERT BIT MAP BIT         ; break
                          case 2:  LEAVE ALONE BIT MAP BIT    ; break
                          case 3:  SET BIT MAP BIT to ONE
                          }

We will use R1 to index into a table which has WORD entries, HIBYTE and LOBYTE
the algorithm followed is if D is the bit map byte containing the bit of our
interest and BL has the rotating bit mask,

                      . get rotating bit mask into AL and AH
                      . AND AL with LOBYTE and AH with HIBYTE
                      . INVERT AL
                      . AND D with AL
                      . XOR D with AH

The INVERT of AL with the subsequent AND ensures that we can set or reset a
particular bit or leave it alone without touching the other bits. The final
XOR does the inversion if necessary.

The following routines take care of the basic DRAW and MOVE routines. They
assume the following values have been calculated:

             wBitmapROP     -----   WORD containing the above XOR,AND mask
             wScan          -----   offset to the next scan line for same plane
             NumScans       -----   number of scan lines per segment
             FillBytes      -----   excess bytes at the end of the segment
             NotFillBytes   -----   last valid address of the segment
             NextSegOff     -----   segment offset to the next segment

These variables must have the correct value, irrespective of whether we have
a small or a huge BITMAP ( NumScans should be 0 for small BITMAPS)

end comment ~
;                                                                             ;
; -by-  Amit Chatteree          Wed 14-Sep-1988    12:00:25                   ;
; -by-  Larry Coffey            1/89, Video 7
;                               Modified to work in VRAM's 256 color modes.   ;
; -by-  Irene Wu                2/89, Video 7                                 ;
;-----------------------------------------------------------------------------;
;                                                                             ;
;                       DRAW AND MOV ROUTINES FOR BITMAPS                     ;
;                       ---------------------------------                     ;
; INPUTS:                                                                     ;
;                                                                             ;
;            DS:DI          -----  current byte in BITMAP memory              ;
;               BL          -----  number of bytes per pixel                  ;
;               SI          -----  offset to next scan line (up or down)      ;
;               CX          -----  number of bits to draw                     ;
;       wBitmapROP          -----  XOR & AND MASK for current pen and ROP     ;
;        FillBytes          -----  extra bytes at the end of the segment      ;
;     NotFillBytes          -----  last valid address in the segment          ;
;       NextSegOff          -----  segment offset to next segment             ;
;                                                                             ;
; RETURNS:                                                                    ;
;            DS:DI          -----  updated NEXT pixel in BITMAP               ;
;               DX          -----  destroyed                                  ;
;               BX          -----  number of bytes per pixel                  ;
;            AX,CX          -----  destroyed                                  ;
;                                                                             ;
; The DRAW routines for the POSITIVE_Y and DIAGONAL_1Q direction map on to the;
; ones for the NEGATIVE_Y and DIAGONAL_4Q after negating SI, the offset to    ;
; the next segment and the filler bytes value, and also scanleft should be    ;
; from the top of the bitmap memory                                           ;
;-----------------------------------------------------------------------------;

; Load colour into AX:DX
loadcol	macro

	mov	ax,TmpColor.lo
	mov	dx,TmpColor.hi
endm

; Do BL bytes of rop/write to DS:DI and ensure BX = bytes written
dopixel	macro	command
	local	@@next

	mov	bh,bl
@@next:
	command
	call	RotColour
	inc	di
	; in 24-bit modes, DI can hit the end of a segment even within a pixel!
	jnz	@F
	; we know DI is supposed to be zero, so we can stash DX in it
	mov	di,dx
	inc	bank_select
	mov	dl,bank_select
	SET_BANK
	mov	dx,di
	xor	di,di
@@:
	dec	bh
	jnz	@@next
endm

loopm	macro	lloop

	dec	cx
	jnz	lloop
;	loop	lloop
endm

	PUBLIC Bm8_Negative_Y
Bm8_Negative_Y  proc    near

		test	DeviceFlags,TYPE_IS_DEV
		jz	@F
		mov	ax,BM8
		cmp	ax,offset BM8_ROPC
		jne	@F
		cmp	FillBytes,0
		je	Bm8_nynoskip
@@:
		jmp	Bm8_nyskip

Bm8_nynoskip:
		loadcol		; mov	al,TmpColor
		dec	cx 	;last pixel addressing?ds:di
		JZ	NEGYLASTP
dobankyPos_loop:
		dopixel <mov	[di],al>
		sub	si,bx
		add	di,si
		lea	si,[bx+si]	; doesn't disturb flags
		jc	dobankyPos

	loopm	dobankyPos_loop
;;	loop	dobankyPos_loop
NEGYLASTP:
		dopixel <mov	[di],al>
		ret
dobankyPos:
		inc	bank_select
		mov	dl,bank_select
		SET_BANK	; call	SetCurrentBankDL
		loadcol		; mov	al,TmpColor
	loopm	dobankyPos_loop
;;	loop	dobankyPos_loop
		dopixel <mov	[di],al>
		ret

Bm8_nyskip:
                loadcol		; mov     al,TmpColor
                dec     cx                  ; take out last pixel from loop
                jz      bm8_nylast
bm8_nyloop:
		call	BM8_wrap
		sub	si,bx
		add	di,si
		lea	si,[bx+si]	; doesn't disturb flags
		jc	bm8_ny_incbank
		cmp	di,NotFillBytes	; past the end of the scanlines?
		ja	bm8_ny_incbank
  	loopm	bm8_nyloop
;;	loop	bm8_nyloop
bm8_nylast:
		call	BM8_wrap
		ret
bm8_ny_incbank:
		test	DeviceFlags,TYPE_IS_DEV
		jz	bm8_ny_segment
		inc	bank_select
		mov	dl,bank_select
		SET_BANK	; call	SetCurrentBankDL
		loadcol		; mov	al,TmpColor
                add     di,FillBytes      ; bypass the filler bytes at end
  	loopm	bm8_nyloop
;;	loop	bm8_nyloop
		call	BM8_wrap
		ret
bm8_ny_segment:
                mov     ax,ds             ; get current segment
                add     ax,NextSegOff     ; positive or negative offset
                mov     ds,ax
		loadcol
                add     di,FillBytes      ; bypass the filler bytes at end
  	loopm	bm8_nyloop
;;	loop	bm8_nyloop
		call	BM8_wrap
		ret
Bm8_Negative_Y  endp

;----------------------------------------------------------------------------;
	PUBLIC Bm8_Positive_Y
Bm8_Positive_Y  proc    near

	test	DeviceFlags,TYPE_IS_DEV
	jz	@F
	mov	ax,BM8
	cmp	ax,offset BM8_ROPC
	jne	@F
	cmp	FillBytes,0
	je	Bm8_pynoskip
@@:
	jmp	Bm8_pyskip

Bm8_pynoskip:
	loadcol		; mov	al,TmpColor
	dec	cx 	;last pixel addressing?ds:di
	jz	pos_y_last
dobankyNeg_loop:
	dopixel <mov	[di],al>
	sub	si,bx
	add	di,si
	lea	si,[bx+si]	; doesn't disturb flags
	jnc	dobankyNeg
  loopm	dobankyNeg_loop
;;loop	dobankyNeg_loop
pos_y_last:
	dopixel <mov	[di],al>
	ret
dobankyNeg:
	dec	bank_select
	mov	dl,bank_select
	SET_BANK	; call	SetCurrentBankDL
	loadcol		; mov	al,TmpColor
  loopm	dobankyNeg_loop
;;loop	dobankyNeg_loop
	dopixel <mov	[di],al>
	ret

Bm8_pyskip:
        loadcol		; mov     al,TmpColor
        dec     cx                  ; take out last pixel from loop
        jz      bm8_pylast
bm8_pyloop:
	call	BM8_wrap
	sub	si,bx
	add	di,si
	lea	si,[bx+si]	; doesn't disturb flags
	jnc	bm8_py_decbank
  loopm	bm8_pyloop
;;loop	bm8_pyloop
bm8_pylast:
	call	BM8_wrap
	ret

bm8_py_decbank:
	test	DeviceFlags,TYPE_IS_DEV
	jz	bm8_py_segment
	dec	bank_select
	mov	dl,bank_select
	SET_BANK	; call	SetCurrentBankDL
	loadcol		; mov	al,TmpColor
        sub     di,FillBytes      ; bypass the filler bytes at end
  loopm	bm8_pyloop
;;loop	bm8_pyloop
	call	BM8_wrap
	ret

bm8_py_segment:
        mov     ax,ds             ; get current segment
        sub     ax,NextSegOff     ; positive or negative offset
        mov     ds,ax
	loadcol
        sub     di,FillBytes      ; bypass the filler bytes at end
  loopm	bm8_pyloop
;;loop	bm8_pyloop
	call	BM8_wrap
	ret

Bm8_Positive_Y  endp
;---------------------------------------------------------------------------;
externA	__WinFlags
WF_486	equ 8
WF_386	equ 4
	PUBLIC Bm8_Positive_X
Bm8_Positive_X	proc	near

	mov	ax,BM8
	cmp	ax,offset BM8_ROPC
	jne	bm8_px_skip
	cmp	bl,3	; difficult to make 24-bit case more efficient
	je	@F
	mov	ax,__WinFlags
	rcl	al,1	; if 2 bytes or fewer, set LSB of AX
	test	al,((WF_486 OR WF_386) SHL 1) OR 1
	jz	@F
	cmp	cx,8
	jge	plh_rop_c
@@:
	loadcol		; mov	al,TmpColor
	dec	cx
	jz	bm8_px_last
bm8_px_loop:
	dopixel <mov	[di],al>
	loop	bm8_px_loop
bm8_px_last:
	dopixel <mov	[di],al>
	ret

bm8_px_skip:
        loadcol		; mov     al,TmpColor
        dec     cx
        jz      bm8_x_do_last
bm8_x_output_loop:
        call	BM8_wrap
	loop    bm8_x_output_loop
bm8_x_do_last:
        call	BM8_wrap
        ret

plh_rop_c:
	; when we get here, bytes per pixel is guaranteed to be a power of 2,
	; and if it is 4, we are guaranteed to be able to use 386 registers.
	push	es
	mov	ax,ds
	mov	es,ax

	; turn CX into the total number of bytes, to check if we wrap
	mov	bh,bl
@@:	shr	bh,1
	jc	@F	;once we shift out the one, we're done
	shl	cx,1
	jmp	@B
@@:
	xor	dx,dx
	add	di,cx
	jnc	@F
	mov	dx,di	;DX is the #bytes left over after the current bank
@@:	sub	di,cx	;restore original DI
	sub	cx,dx	;CX is just the #bytes in the current bank
	
	cmp	bl,4
	jb	@F
	.386
	mov	eax,[TmpColor]
	.8086
@@:	mov	ax,[TmpColor.lo]

setup_count:
	cmp	bl,4
	jnb	plh_rop_c_32bit

	cmp	bl,1
	ja	@F
	mov	ah,al
@@:	shr	cx,1
	jc	plh_rop_c_odd
	test	di,1
	jnz	plh_rop_c_ena
	rep	stosw	;even aligned
	jmp	short count_done
plh_rop_c_ena:
	dec	cx
	stosb
	rep	stosw
	stosb
	jmp	short count_done
plh_rop_c_odd:
	test	di,1
	jnz	plh_rop_c_ona
	rep	stosw
	stosb
	jmp	short count_done
plh_rop_c_ona:
	stosb
	rep	stosw
	jmp	short count_done
plh_rop_c_32bit:
	.386
	shr	cx,2
	rep	stosd
	db	67h,90h
	.8086

count_done:
	; check if we need a second round...
	xchg	cx,dx
	jcxz	@F
	call	inc_bank_select
	jmp	short setup_count
@@:	pop	es
	ret

Bm8_Positive_X	endp


;---------------------------------------------------------------------------;
	PUBLIC	Bm8_Diagonal_4Q
Bm8_Diagonal_4Q proc	near

	test	DeviceFlags,TYPE_IS_DEV
	jz	@F
	mov	ax,BM8
	cmp	ax,offset BM8_ROPC
	jne	@F
	cmp	FillBytes,0
	je	Bm8_d4qnoskip
@@:
	jmp	Bm8_d4qskip

Bm8_d4qnoskip:
	loadcol		; mov     al,TmpColor
        dec     cx              ; leave out the last pixel
        jz      Bm8_d4q_last_pixel
Bm8_d4q_iloop:
	dopixel <mov	[di],al>
	add	di,si
	jc	Bm8_d4q_incbank
  loopm	Bm8_d4q_iloop
;;loop	Bm8_d4q_iloop
Bm8_d4q_last_pixel:
	dopixel <mov	[di],al>
	ret		;exit	      
Bm8_d4q_incbank:
	inc	bank_select
	mov	dl,bank_select
	SET_BANK	; call	SetCurrentBankDL
	loadcol		; mov	al,TmpColor
  loopm	Bm8_d4q_iloop
;;loop	Bm8_d4q_iloop
	dopixel <mov	[di],al>
	ret   		;exit

Bm8_d4qskip:
        loadcol		; mov     al,TmpColor
        dec     cx              ; leave out the last pixel
        jz      Bm8_diag_last_pixel
Bm8_Diag_loop:
        call	BM8_wrap
	add	di,si
	jc	Bm8_Diag_incbank
	cmp	di,NotFillBytes
	ja	Bm8_Diag_incbank
  loopm	Bm8_Diag_loop
;;loop	Bm8_Diag_loop
Bm8_diag_last_pixel:
	call	BM8_wrap
	ret

Bm8_Diag_incbank:
	test	DeviceFlags,TYPE_IS_DEV
	jz	bm8_diag_segment
	inc	bank_select
	mov	dl,bank_select
	SET_BANK	; call	SetCurrentBankDL
	loadcol		; mov	al,TmpColor
        add     di,FillBytes      ; bypass the filler bytes at end
  loopm	Bm8_Diag_loop
;;loop	Bm8_Diag_loop
	call	BM8_wrap
	ret

bm8_diag_segment:
	mov     ax,ds             ; get current segment
        add     ax,NextSegOff     ; positive or negative offset
        mov     ds,ax
	loadcol
        add     di,FillBytes      ; bypass the filler bytes at end
  loopm	Bm8_Diag_loop
;;loop	Bm8_Diag_loop
	call	BM8_wrap
	ret
         
Bm8_Diagonal_4Q endp

;-----------------------------------------------------------------------------;
	PUBLIC Bm8_Diagonal_1Q
Bm8_Diagonal_1Q proc	near

	test	DeviceFlags,TYPE_IS_DEV
	jz	@F
	mov	ax,BM8
	cmp	ax,offset BM8_ROPC
	jne	@F
	cmp	FillBytes,0
	je	Bm8_d1qnoskip
@@:
	jmp	Bm8_d1qskip

Bm8_d1qnoskip:
	loadcol		; mov	al,TmpColor
	dec	cx 	;last pixel addressing?ds:di
	jz	d1q_lastpixel
Bm8_d1q_dloop:
	dopixel <mov	[di],al>
	add	di,si
	jnc	Bm8_d1q_decbank
  loopm	Bm8_d1q_dloop
;;loop	Bm8_d1q_dloop
d1q_lastpixel:
	dopixel <mov	[di],al>
	ret
Bm8_d1q_decbank:
	dec	bank_select
	mov	dl,bank_select
	SET_BANK	; call	SetCurrentBankDL
	loadcol		; mov	al,TmpColor
  loopm	Bm8_d1q_dloop
;;loop	Bm8_d1q_dloop
	dopixel <mov	[di],al>
	ret

Bm8_d1qskip:
        loadcol		; mov     al,TmpColor
        dec     cx              ; leave out the last pixel
        jz      diag_last_pixel
Diag_loop:
        call	BM8_wrap
	add	di,si
	jnc	Diag_decbank
  loopm	Diag_loop
;;loop	Diag_loop
diag_last_pixel:
	call	BM8_wrap
	ret

Diag_decbank:
	test	DeviceFlags,TYPE_IS_DEV
	jz	diag_segment
	dec	bank_select
	mov	dl,bank_select
	SET_BANK	; call	SetCurrentBankDL
	loadcol		; mov	al,TmpColor
        sub     di,FillBytes      ; bypass the filler bytes at end
  loopm	Diag_loop
;;loop	Diag_loop
	call	BM8_wrap
	ret

diag_segment:
	mov     ax,ds             ; get current segment
        sub     ax,NextSegOff     ; positive or negative offset
        mov     ds,ax
	loadcol
        sub     di,FillBytes      ; bypass the filler bytes at end
  loopm	Diag_loop
;;loop	Diag_loop
	call	BM8_wrap
	ret

Bm8_Diagonal_1Q endp

;-----------------------------------------------------------------------------;
Bm8_Move_Positive_X proc        near

        ; this does nothing since the Bm8_* routine should automatically have
	; incremented the pixel in the X direction!
        ret

Bm8_Move_Positive_X     endp

;----------------------------------------------------------------------------;
Bm8_Move_Diagonal_4Q proc near

	; previous Bm8_* routine should automatically have moved us forward,
	; so we only need to go down to the next scanline, with no adjustment
	add	di,si
	jc	@F
	ret

PUBLIC	Bm8_Move_Negative_Y
	Bm8_Move_Negative_Y proc        near

	; need to move back to previous pixel before going down
	sub	si,bx
	add	di,si
	lea	si,[bx+si]	; doesn't disturb flags
	jc	@F
	cmp	di,NotFillBytes
	ja	@F
	ret
@@:	test	DeviceFlags,TYPE_IS_DEV
	jz	@F

	inc	bank_select
	mov	dl,bank_select
	SET_BANK	; call	SetCurrentBankDL
	loadcol
	add	di,FillBytes
	ret
@@:
	mov	ax,ds
        add     ax,NextSegOff   ; nect segment
        mov     ds,ax
	loadcol
        add     di,FillBytes    ; skip over filler bytes
        ret

	Bm8_Move_Negative_Y     endp

Bm8_Move_Diagonal_4Q    endp

;---------------------------------------------------------------------------;
Bm8_Move_Diagonal_1Q proc near

	; previous Bm8_* routine should automatically have moved us forward,
	; so we only need to go up to the next scanline, with no adjustment
	add	di,si
	jnc	@F
	ret

PUBLIC	Bm8_Move_Positive_Y
	Bm8_Move_Positive_Y proc        near

	; need to move back to previous pixel before going up
	sub	si,bx
	add	di,si
	lea	si,[bx+si]	; doesn't disturb flags
	jnc	@F
	ret
@@:
	test	DeviceFlags, TYPE_IS_DEV
	jz	@F

	dec	bank_select
	mov	dl,bank_select
	SET_BANK	; call	SetCurrentBankDL
	loadcol
	sub	di,FillBytes
	ret
@@:
	mov	ax,ds
	sub	ax,NextSegOff	; nect segment
        mov     ds,ax
	loadcol
        sub     di,FillBytes    ; skip over filler bytes
        ret

	Bm8_Move_Positive_Y     endp

Bm8_Move_Diagonal_1Q    endp


; colour rotation routines, to ensure the next byte to write is in AL
;---------------------------------------------------------------------------;
RotateColour8	proc	near
		; in the 8-bit case, it's always in AL, so do nothing
                ret
RotateColour8	endp
;---------------------------------------------------------------------------;
RotateColour16	proc	near
		; just need to swap two bytes
		xchg	al,ah
                ret
RotateColour16	endp
;---------------------------------------------------------------------------;
RotateColour24	proc	near
		; here's where it gets tricky...
		; suppose AL:AH:DL = |1|2|3|
		xchg	al,dl
		; now AL:AH:DL = |3|2|1|
		xchg	al,ah
		; now AL:AH:DL = |2|3|1| --> this is what we want :)
                ret
RotateColour24	endp
;---------------------------------------------------------------------------;
RotateColour32	proc	near
		; trickier...
		; suppose AL:AH:DL:DH = |1|2|3|4|
		xchg	al,dh
		; now AL:AH:DL:DH = |4|2|3|1|
		xchg	al,ah
		; now AL:AH:DL:DH = |2|4|3|1|
		xchg	ah,dl
		; now AL:AH:DL:DH = |2|3|4|1| --> this is what we want :)
                ret
RotateColour32	endp
;---------------------------------------------------------------------------;

; Wrapper for BM8 that allows for multiple bytes per pixel.
; This is a subroutine since instantiating the dopixel macro everywhere
; would seriously blow up the code size in this module...
;---------------------------------------------------------------------------;
public	BM8_wrap ; for debugging
BM8_wrap	proc	near
		dopixel <call	BM8>
		ret
BM8_wrap	endp
;---------------------------------------------------------------------------;

;---------------------------------------------------------------------------;
BM8_ROP0	proc	near
		mov	BYTE PTR [di],0
                ret
BM8_ROP0	endp
;---------------------------------------------------------------------------;
BM8_ROP1	proc	near
		or	BYTE PTR [di],al
		not	BYTE PTR [di]
                ret
BM8_ROP1	endp
;---------------------------------------------------------------------------;
BM8_ROP2	proc	near
		mov	ah	,al
		not	ah
		and	BYTE PTR [di],ah
		ret
BM8_ROP2	endp
;---------------------------------------------------------------------------;
BM8_ROP3	proc	near
		mov	ah	,al
		not	ah
		mov	BYTE PTR [di],ah
		ret
BM8_ROP3	endp
;---------------------------------------------------------------------------;
BM8_ROP4	proc	near
		mov	ah	,BYTE PTR [di]
		not	ah
		and	ah	,al
		mov	BYTE PTR [di],ah
		ret
BM8_ROP4	endp
;---------------------------------------------------------------------------;
BM8_ROP5	proc	near
		not	BYTE PTR [di]
		ret
BM8_ROP5	endp
;---------------------------------------------------------------------------;
BM8_ROP6	proc	near
		xor	BYTE PTR [di],al
		ret
BM8_ROP6	endp
;---------------------------------------------------------------------------;
BM8_ROP7	proc	near
		and	BYTE PTR [di],al
		not	BYTE PTR [di]
                ret
BM8_ROP7	endp
;---------------------------------------------------------------------------;
BM8_ROP8	proc	near
		and	BYTE PTR [di],al
                ret
BM8_ROP8	endp
;---------------------------------------------------------------------------;
BM8_ROP9	proc	near
		xor	BYTE PTR [di],al
		not	BYTE PTR [di]
                ret
BM8_ROP9	endp
;---------------------------------------------------------------------------;
BM8_ROPA	proc	near
                ret
BM8_ROPA	endp
;---------------------------------------------------------------------------;
BM8_ROPB	proc	near
		mov	ah	,al
		not	ah
		or	BYTE PTR [di],ah
		ret
BM8_ROPB	endp
;---------------------------------------------------------------------------;
BM8_ROPC	proc	near
		mov	 BYTE PTR [di],al
		ret
BM8_ROPC	endp
;---------------------------------------------------------------------------;
BM8_ROPD	proc	near
		not	BYTE PTR [di]
		or	BYTE PTR [di] ,al
		ret
BM8_ROPD	endp
;---------------------------------------------------------------------------;
BM8_ROPE	proc	near
		or	BYTE PTR [di] ,al
		ret
BM8_ROPE	endp
;---------------------------------------------------------------------------;
BM8_ROPF	proc	near
		mov	BYTE PTR [di] ,0FFH
		ret
BM8_ROPF	endp


; TRUTH TABLE
;P D  0 1 2 3 4 5 6 7 8 9 a b c d e f
;0 0  0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1
;0 1  0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1
;1 0  0 0 0 0 1 1 1 1 0 0 0 0 1 1 1 1
;1 1  0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1

