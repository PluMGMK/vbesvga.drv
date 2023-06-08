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
;               BL          -----  rotating bit mask for current pixel        ;
;               SI          -----  offset to next scan line (up or down)      ;
;               CX          -----  number of bits to draw                     ;
;       wBitmapROP          -----  XOR & AND MASK for current pen and ROP     ;
;        FillBytes          -----  extra bytes at the end of the segment      ;
;       NextSegOff          -----  segment offset to next segment             ;
;               DX          -----  number of scan lines left in the segment   ;
;                                                                             ;
; RETURNS:                                                                    ;
;            DS:DI          -----  updated current byte in BITMAP             ;
;               BL          -----  updated rotating bit mask                  ;
;               DX          -----  updated numver of scan lines left          ;
;                                    this value is maintained in ScanLeft     ;
;            AX,CX          -----  destroyed                                  ;
;                                                                             ;
; The DRAW routines for the POSITIVE_Y and DIAGONAL_1Q direction map on to the;
; ones for the NEGATIVE_Y and DIAGONAL_4Q after negating SI, the offset to    ;
; the next segment and the filler bytes value, and also scanleft should be    ;
; from the top of the bitmap memory                                           ;
;-----------------------------------------------------------------------------;

loopm	macro	lloop

	dec	cx
	jnz	lloop
;	loop	lloop
	endm

	PUBLIC Bm8_Negative_Y
Bm8_Negative_Y  proc    near

		test	DeviceFlags,TYPE_IS_DEV
		jz	Bm8_nyskip
		mov	ax,BM8
		cmp	ax,offset BM8_ROPC
		jne	Bm8_nyskip
		cmp	FillBytes,0
		jne	Bm8_nyskip

		mov	al,TmpColor
		dec	cx 	;last pixel addressing?ds:di
		JZ	NEGYLASTP
dobankyPos_loop:
		mov	[di],al
		add	di,si
		jc	dobankyPos

	loopm	dobankyPos_loop
;;	loop	dobankyPos_loop
NEGYLASTP:
		mov	[di],al
		ret
dobankyPos:
		inc	bank_select
		mov	dl,bank_select
		call	SetCurrentBankDL
		mov	al,TmpColor
	loopm	dobankyPos_loop
;;	loop	dobankyPos_loop
		mov	[di],al
		ret

Bm8_nyskip:
                mov     al,TmpColor
                dec     cx                  ; take out last pixel from loop
                jz      bm8_nylast
bm8_nyloop:
		call	BM8
		add	di,si
		jc	bm8_ny_incbank
  	loopm	bm8_nyloop
;;	loop	bm8_nyloop
bm8_nylast:
		call	BM8
		ret
bm8_ny_incbank:
		test	DeviceFlags,TYPE_IS_DEV
		jz	bm8_ny_segment
		inc	bank_select
		mov	dl,bank_select
		call	SetCurrentBankDL
		mov	al,TmpColor
                add     di,FillBytes      ; bypass the filler bytes at end
  	loopm	bm8_nyloop
;;	loop	bm8_nyloop
		call	BM8
		ret
bm8_ny_segment:
                mov     dx,ds             ; get current segment
                add     dx,NextSegOff     ; positive or negative offset
                mov     ds,dx
                add     di,FillBytes      ; bypass the filler bytes at end
  	loopm	bm8_nyloop
;;	loop	bm8_nyloop
		call	BM8
		ret
Bm8_Negative_Y  endp

;----------------------------------------------------------------------------;
	PUBLIC Bm8_Positive_Y
Bm8_Positive_Y  proc    near

	test	DeviceFlags,TYPE_IS_DEV
	jz	Bm8_pyskip
	mov	ax,BM8
	cmp	ax,offset BM8_ROPC
	jne	Bm8_pyskip
	cmp	FillBytes,0
	jne	Bm8_pyskip

	mov	al,TmpColor
	dec	cx 	;last pixel addressing?ds:di
	jz	pos_y_last
dobankyNeg_loop:
	mov	[di],al
	add	di,si
	jnc	dobankyNeg
  loopm	dobankyNeg_loop
;;loop	dobankyNeg_loop
pos_y_last:
	mov	[di],al
	ret
dobankyNeg:
	dec	bank_select
	mov	dl,bank_select
	call	SetCurrentBankDL
	mov	al,TmpColor
  loopm	dobankyNeg_loop
;;loop	dobankyNeg_loop
	mov	[di],al
	ret

Bm8_pyskip:
        mov     al,TmpColor
        dec     cx                  ; take out last pixel from loop
        jz      bm8_pylast
bm8_pyloop:
	call	BM8
	add	di,si
	jnc	bm8_py_decbank
  loopm	bm8_pyloop
;;loop	bm8_pyloop
bm8_pylast:
	call	BM8
	ret

bm8_py_decbank:
	test	DeviceFlags,TYPE_IS_DEV
	jz	bm8_py_segment
	dec	bank_select
	mov	dl,bank_select
	call	SetCurrentBankDL
	mov	al,TmpColor
        sub     di,FillBytes      ; bypass the filler bytes at end
  loopm	bm8_pyloop
;;loop	bm8_pyloop
	call	BM8
	ret

bm8_py_segment:
        mov     dx,ds             ; get current segment
        sub     dx,NextSegOff     ; positive or negative offset
        mov     ds,dx
        sub     di,FillBytes      ; bypass the filler bytes at end
  loopm	bm8_pyloop
;;loop	bm8_pyloop
	call	BM8
	ret

Bm8_Positive_Y  endp
;---------------------------------------------------------------------------;
	PUBLIC Bm8_Positive_X
Bm8_Positive_X	proc	near

	mov	ax,BM8
	cmp	ax,offset BM8_ROPC
	jne	bm8_px_skip
	cmp	cx,8
	jge	@F

	mov	al,TmpColor
	dec	cx
	jz	bm8_px_last
bm8_px_loop:
	mov	[di],al
	inc	di
  loopm	bm8_px_loop
;;loop	bm8_px_loop
bm8_px_last:
	mov	[di],al
	ret

bm8_px_skip:
        mov     al,TmpColor
        dec     cx
        jz      bm8_x_do_last
bm8_x_output_loop:
        call    BM8
        inc     di
  loopm   bm8_x_output_loop
;;loop    bm8_x_output_loop
bm8_x_do_last:
        call    BM8
        ret

@@:
	push	es
	mov	ax,ds
	mov	es,ax
	mov	al,TmpColor
	mov	ah,al
	shr	cx,1
	jc	plh_rop_c_odd
	test	di,1
	jnz	plh_rop_c_ena
	rep	stosw	;even alined
	dec	di
	pop	es
	ret
plh_rop_c_ena:
	dec	cx
	stosb
	rep	stosw
	mov	es:[di],al
	pop	es
	ret
plh_rop_c_odd:
	test	di,1
	jnz	plh_rop_c_ona
	rep	stosw
	mov	es:[di],al
	pop	es
	ret
plh_rop_c_ona:
	stosb
	rep	stosw
	dec	di
	pop	es
	ret

Bm8_Positive_X	endp


;---------------------------------------------------------------------------;
	PUBLIC	Bm8_Diagonal_4Q
Bm8_Diagonal_4Q proc	near

	test	DeviceFlags,TYPE_IS_DEV
	jz	Bm8_d4qskip
	mov	ax,BM8
	cmp	ax,offset BM8_ROPC
	jne	Bm8_d4qskip
	cmp	FillBytes,0
	jne	Bm8_d4qskip

	mov     al,TmpColor
        dec     cx              ; leave out the last pixel
        jz      Bm8_d4q_last_pixel
Bm8_d4q_iloop:
	mov	[di],al
	inc	di
	add	di,si
	jc	Bm8_d4q_incbank
  loopm	Bm8_d4q_iloop
;;loop	Bm8_d4q_iloop
Bm8_d4q_last_pixel:
	mov	[di],al
	ret		;exit	      
Bm8_d4q_incbank:
	inc	bank_select
	mov	dl,bank_select
	call	SetCurrentBankDL
	mov	al,TmpColor
  loopm	Bm8_d4q_iloop
;;loop	Bm8_d4q_iloop
	mov	[di],al
	ret   		;exit

Bm8_d4qskip:
        mov     al,TmpColor
        dec     cx              ; leave out the last pixel
        jz      Bm8_diag_last_pixel
Bm8_Diag_loop:
        call    BM8
	inc	di
	add	di,si
	jc	Bm8_Diag_incbank
  loopm	Bm8_Diag_loop
;;loop	Bm8_Diag_loop
Bm8_diag_last_pixel:
	call	BM8
	ret

Bm8_Diag_incbank:
	test	DeviceFlags,TYPE_IS_DEV
	jz	bm8_diag_segment
	inc	bank_select
	mov	dl,bank_select
	call	SetCurrentBankDL
	mov	al,TmpColor
        add     di,FillBytes      ; bypass the filler bytes at end
  loopm	Bm8_Diag_loop
;;loop	Bm8_Diag_loop
	call	BM8
	ret

bm8_diag_segment:
	mov     dx,ds             ; get current segment
        add     dx,NextSegOff     ; positive or negative offset
        mov     ds,dx
        add     di,FillBytes      ; bypass the filler bytes at end
  loopm	Bm8_Diag_loop
;;loop	Bm8_Diag_loop
	call	BM8
	ret
         
Bm8_Diagonal_4Q endp

;-----------------------------------------------------------------------------;
	PUBLIC Bm8_Diagonal_1Q
Bm8_Diagonal_1Q proc	near

	test	DeviceFlags,TYPE_IS_DEV
	jz	Bm8_d1qskip
	mov	ax,BM8
	cmp	ax,offset BM8_ROPC
	jne	Bm8_d1qskip
	cmp	FillBytes,0
	jne	Bm8_d1qskip

	mov	al,TmpColor
	dec	cx 	;last pixel addressing?ds:di
	jz	d1q_lastpixel
Bm8_d1q_dloop:
	mov	[di],al
	inc	di
	add	di,si
	jnc	Bm8_d1q_decbank
  loopm	Bm8_d1q_dloop
;;loop	Bm8_d1q_dloop
d1q_lastpixel:
	mov	[di],al
	ret
Bm8_d1q_decbank:
	dec	bank_select
	mov	dl,bank_select
	call	SetCurrentBankDL
	mov	al,TmpColor
  loopm	Bm8_d1q_dloop
;;loop	Bm8_d1q_dloop
	mov	[di],al
	ret

Bm8_d1qskip:
        mov     al,TmpColor
        dec     cx              ; leave out the last pixel
        jz      diag_last_pixel
Diag_loop:
        call    BM8
	inc	di
	add	di,si
	jnc	Diag_decbank
  loopm	Diag_loop
;;loop	Diag_loop
diag_last_pixel:
	call	BM8
	ret

Diag_decbank:
	test	DeviceFlags,TYPE_IS_DEV
	jz	diag_segment
	dec	bank_select
	mov	dl,bank_select
	call	SetCurrentBankDL
	mov	al,TmpColor
        sub     di,FillBytes      ; bypass the filler bytes at end
  loopm	Diag_loop
;;loop	Diag_loop
	call	BM8
	ret

diag_segment:
	mov     dx,ds             ; get current segment
        sub     dx,NextSegOff     ; positive or negative offset
        mov     ds,dx
        sub     di,FillBytes      ; bypass the filler bytes at end
  loopm	Diag_loop
;;loop	Diag_loop
	call	BM8
	ret

Bm8_Diagonal_1Q endp

;-----------------------------------------------------------------------------;
Bm8_Move_Positive_X proc        near

        inc     di
        ret

Bm8_Move_Positive_X     endp

;----------------------------------------------------------------------------;
Bm8_Move_Diagonal_4Q proc near

        inc     di

PUBLIC	Bm8_Move_Negative_Y
	Bm8_Move_Negative_Y proc        near

	add	di,si
	jc	@F
	ret
@@:	test	DeviceFlags,TYPE_IS_DEV
	jz	@F

	inc	bank_select
	mov	dl,bank_select
	call	SetCurrentBankDL
	add	di,FillBytes
	ret
@@:
	mov	dx,ds
        add     dx,NextSegOff   ; nect segment
        mov     ds,dx
        add     di,FillBytes    ; skip over filler bytes
        ret

	Bm8_Move_Negative_Y     endp

Bm8_Move_Diagonal_4Q    endp

;---------------------------------------------------------------------------;
Bm8_Move_Diagonal_1Q proc near

        inc     di

PUBLIC	Bm8_Move_Positive_Y
	Bm8_Move_Positive_Y proc        near

	add	di,si
	jnc	@F
	ret
@@:
	test	DeviceFlags, TYPE_IS_DEV
	jz	@F

	dec	bank_select
	mov	dl,bank_select
	call	SetCurrentBankDL
	sub	di,FillBytes
	ret
@@:
	mov	dx,ds
	sub	dx,NextSegOff	; nect segment
        mov     ds,dx
        sub     di,FillBytes    ; skip over filler bytes
        ret

	Bm8_Move_Positive_Y     endp

Bm8_Move_Diagonal_1Q    endp

;---------------------------------------------------------------------------;
	PUBLIC	SetCurrentBankDL
SetCurrentBankDL proc near

	PUSH 	DS
	MOV 	AX,DGROUP
	MOV 	DS,AX
	assume ds:DGROUP
	MOV 	bank_select_byte,dl
	POP 	DS
	assume ds:nothing

	;push	ax
	push	bx
	push	dx

	;destroys ax,bx,dx
	mov	bl,dl
	and	bl,1
	mov	ah,dl
	and	ah,2
	shl	ah,4
	and	dl,0ch
	mov	bh,dl
	shr	dl,2
	or	bh,dl
	mov	dx,3cch
	in	al,dx
	and	al,not 20h
	or	al,ah
	mov	dx,3c2h
	out	dx,al
	mov	dx,3c4h		;sequencer
	mov	al,0f9h		;extended page select
	mov	ah,bl
	out	dx,ax
	mov	al,0f6h		;256k bank select
	out	dx,al
	inc	dx		;data
	in	al,dx
	and	al,0f0h		;clear bank bits
	or	al,bh		;set bank bits
	out	dx,al

	pop	dx
	pop	bx
	;pop	ax
	ret

SetCurrentBankDL endp


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

