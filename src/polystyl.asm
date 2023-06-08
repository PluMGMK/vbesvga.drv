;-----------------------------------------------------------------------------;
;                             POLYSTYL.ASM                                    ;
;                             ------------                                    ;
; This file has styled line drawing subroutines for VRAM VGA (256 color),     ;
; planar BITMAPs and byte/pixel BITMAPS. The file is included in POLYLINE.ASM ;
;                                                                             ;
;                                                                             ;
;                       STYLED LINE DRAW ROUTINES                             ;
;                       -------------------------                             ;
;  There are 6 different line drawing styles and each of them can be assoc-   ;
;  -iated with a byte mask as shown below:                                    ;
;                                                                             ;
;             STYLE NAME                    BYTE MASK                         ;
;             ----------                    ---------                         ;
;              PS_SOLID                (excluded from styling)                ;
;              PS_DASH                       11001100                         ;
;              PS_DOT                        10101010                         ;
;              PS_DASHDOT                    11100100                         ;
;              PS_DASHDOTDOT                 11101010                         ;
;              PS_NULL                       00000000                         ;
;                                                                             ;
; each one or a zero in the mask actually represents a set of pixel on the    ;
; screen or the map. The no of pixels that each mask bit represents would     ;
; depend on the direction the line is being drawn.                            ;
;                                                                             ;
; The logic adopted is as follows:                                            ;
;                                                                             ;
;          . based on aspect ratio tec the following magic numbers have been  ;
;            arrived at:                                                      ;
;                         . 48 units along X is equivalent to 38 units along Y;
;                           which is equivalent to 61 units along the diagonal;
;                                                                             ;
;                         . The bit from the mask that we select depends on   ;
;                           the direction and how long we have been using the ;
;                           previous bit in the mask. An initial style error  ;
;                           term 0d 122 (2 * 61) has been assumed.            ;
;                                                                             ;
;                         . These figures are so chosen that they do not      ;
;                           exceed 127 as the signed jumps may be used        ;
;                                                                             ;
;                         . After processing one pixel, say in the X direction;
;                           48 is added to the style error. Once the style    ;
;                           error crosses 256, the next bit in the style is   ;
;                           selected and the high byte of the error term neg- ;
;                           -lected to bring the error below 256              ;
;                                                                             ;
;          . The gaps in the style can either be transparent or opaque. If    ;
;            the gap is opaque we have to draw the gaps in a separate pass    ;
;            where we use inverse of the mask to decide which bits are to be  ;
;            set on and which are to be skipped.                              ;
;                                                                             ;
;          . Routines for drawing are very similar to what had been used for  ;
;            solid lines                                                      ;
;                                                                             ;
;          . Move routines are not affected by line styling and remain the    ;
;            same.                                                            ;
;                                                                             ;
; History:
;       2/89, Irene Wu, Video 7
;       Modified to work in VRAM's 256 color modes.
;-----------------------------------------------------------------------------;

;
;*****************************************************************************;
;-----------------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.

comment ~
                  BITMAP STYLED LINE DRAWING ROUTINES
                  -----------------------------------

INPUTS:
         DS:DI    ----    current byte
         BL       ----    rotating bit mask
   bStyleError    ----    current value of style error term
    bStyleMask    ----    current position of rotating style mask
    wDistHoriz    ----    scale factor in HORIZONTAL direction (=48)
     wDistVert    ----    scale factor in VERTICAL direction (=38)
     wDistDiag    ----    scale factor in diagonal direction (=61)
      NextScan    ----    (add) offset to next scanline in direction of move

RETURNS:
         DS:DI, BL and wStyleError are updated.
         SI     retains their values
         CX,BH  destroyed
         AX     number of scanlines left from bottom
         DX     number of scan lines left from top

The draw routines in Positive_Y and Diagonal_1Q direction simply negates the
distance to the next scan line and calls the corresponding routines in the
opposite direction.

end comment ~

StepsTo64KBound	proc	near
; Call with delta_di in si, current bank offset in di.
; Returns number of steps to 64K boundary in si.
	mov	ax,di		; Numerator = remaining bank in dir of move
	neg	ax		;  = 64k - current bank offset
	or	si,si		;   if delta_di is positive
	jg	@F
	neg	si		; Absolute delta_di
	neg	ax		; Numerator = current bank offset
@@:
	xor	dx,dx		; Numerator in dx:ax
	div	si		; Max number of steps before bound in ax
	mov	si,ax		; Get it in si
	inc	si		; Test is after dec
	ret
StepsTo64KBound	endp

;---------------------------------------------------------------------------;
StBm_Negative_Y proc    near

        push    si                  ; save
        push    bx                  ; save mask

	mov	si,NextScan	; delta_di = NextScan
	call	StepsTo64KBound	; Get number of steps to 64K boundary in si

        mov     al,bl               ; get rotating bit mask
        mov     ah,al               ; also into ah
        and     ax,wBitmapROP       ; get the mask into the AND,XOR msk
        not     al                  ; invert the AND mask
        mov     dl,bStyleError      ; the current value of style error
        mov     bh,bStyleMask       ; current position of style mask
        dec     cx                  ; take out last pixel from loop
        jz      StBm_Y_last_pixel
StBm_Y_loop:
        or      bh,bh               ; does mask permit bit to be set on
        jns     stbm_vert_ignore    ; no
        and     [di],al
        xor     [di],ah             ; process one pixel

stbm_vert_ignore:

; advance the style mask

        xor     dh,dh               ; will hold the hibyte of err add
        add     dx,wDistVert        ; sacle factor in vertical dir
        xchg    cl,dh               ; if DH = 1, the mask has to shift
        rol     bh,cl               ; rotate if necessary
        mov     cl,dh               ; restore count

; now move to the next scan line

        dec     si                ; one more scan line taken up
        jnz     StBm_Y_same_segment ; still in same seg,ent


        mov     si,ds             ; get current segment
        add     si,NextSegOff     ; positive or negative offset
        mov     ds,si
        add     di,FillBytes      ; bypass the filler bytes at end
        mov     si,wScans         ; number of scans in full segment

StBm_Y_same_segment:
        add     di,NextScan       ; next scan in same segment
        loop    StBm_Y_loop       ; process all the pixels

; do the last pixel

StBm_Y_last_pixel:

        or      bh,bh               ; can last pixel be set on
        jns     stbm_vert_return    ; no
        and     [di],al
        xor     [di],ah             ; process the last pixel
stbm_vert_return:
        mov     bStyleError,dl      ; save
        mov     bStyleMask,bh       ; save style mask
        mov     dx,si               ; get scan lines left
        pop     bx                  ; get back mask
        pop     si                  ; restore
        ret

StBm_Negative_Y endp

;-----------------------------------------------------------------------------;
StBm_Positive_Y proc    near

        neg     NextSegOff        ; since we will be going to low addr
        neg     FillBytes
        neg     NextScan          ; (add) offset to next scan line

        call    StBm_Negative_Y     ; line segment drawn

;  calculate the no of scan lines left from the bottom from DX which has no
;  of scan lines left from the top

        neg     dx
        add     dx,wScans
        inc     dx

;    restore back the values which where negated

        neg     FillBytes
        neg     NextSegOff
        neg     NextScan
        ret

StBm_Positive_Y endp

;----------------------------------------------------------------------------;
StBm_Positive_X proc    near

; load relevent values into the registers

        push    si              ; will actually not need the value here
        push    dx              ; save scan line information
        mov     al,bl           ; the rotating bit mask
        mov     ah,al           ; get it into ah also for AND,XOR masking
        and     ax,wBitmapROP   ; do the AND,XOR masking for selected bit
        not     al              ; adjust the AND mask to not affect other bits
        mov     dl,bStyleError  ; current value of the error term
        mov     bh,bStyleMask   ; current position of the rotating style mask
        mov     si,wDistHoriz   ; load the vertical scale factor

; the draw loop

        dec     cx              ; leave out the last pixel from the loop
        jz      stbm_horiz_last

stbm_horiz_loop:

; draw the pixel if the mask says so

        or      bh,bh           ; the msb of the mask is the one to inspect
        jns     stbm_horiz_ignore ; pixel not to be drawn
        and     [di],al         ; use the AND mask
        xor     [di],ah         ; use the XOR mask

stbm_horiz_ignore:

        ror     al,1            ; set up bitmask for next bit
        ror     ah,1
        ror     bl,1            ; update for final return
        adc     di,0            ; next byte if wrap aroud occurs

; advance the mask if necessary

        xor     dh,dh           ; zero out high byte for add result
        add     dx,si           ; add the horizontal scale factor to error
        xchg    cl,dh           ; if BH is 1, the mask has to be rotated
        rol     bh,cl           ; rotate the mask
        mov     cl,dh           ; get back the count
        loop    stbm_horiz_loop ; process all the pixels

; draw the last pixel if the mask says so.

stbm_horiz_last:
        or      bh,bh           ; test the mask
        jns     stbm_horiz_return ; not to be drawn
        and     [di],al         ; use the AND mask
        xor     [di],ah         ; use the XOR mask
stbm_horiz_return:

; save the current values of the error term and the style mask

        mov     bStyleError,dl
        mov     bStyleMask,bh
        pop     dx              ; get scan line information back
        pop     si              ; restore saved value
        ret

StBm_Positive_X endp

;-----------------------------------------------------------------------------;
StBm_Diagonal_4Q proc   near

        push    si              ; save

	mov	si,NextScan	; delta_di = NextScan
	call	StepsTo64KBound	; Get number of steps to 64K boundary in si

        mov     al,bl           ; get rotating bit mask
        mov     ah,al
        and     ax,wBitmapROP   ; combine with the ROP masks
        not     al              ; adjust the AND mask
        mov     dl,bStyleError  ; the current value of the style error
        mov     bh,bStyleMask   ; current value of the style mask
        dec     cx              ; leave out the last pixel
        jz      StBm_diag_last_pixel
StBm_Diag_loop:
        or      bh,bh           ; test mask MSB
        jns     stbm_diag_ignore  ; ignore this pel
        and     [di],al
        xor     [di],ah         ; process 1 pixel
stbm_diag_ignore:

; advance the style mask if  necessary

        xor     dh,dh           ; will hold the high byte of err add
        add     dx,wDistDiag    ; scale distance along diagonal
        xchg    cl,dh           ; if DH=1, style mask has to rotate
        rol     bh,cl           ; rotate the mask
        mov     cl,dh           ; restore count

; move to next scan

        ror     al,1
        ror     ah,1
        ror     bl,1            ; the rotating bit mask updated
        adc     di,NextScan
        dec     si              ; dec no of scans left in dir of move
        jnz     stbm_diag_same_seg

; move to next (prior) huge scan

        mov     si,ds
        add     si,NextSegOff   ; offset of required segment
        mov     ds,si
        add     di,FillBytes    ; no of left over bytes
        mov     si,wScans       ; new value of number of scans left
stbm_diag_same_seg:
        loop    StBm_Diag_loop

; do the last pixel

StBm_diag_last_pixel:

        or      bh,bh           ; does mak permit last pixel
        jns     stbm_diag_return ; no
        and     [di],al
        xor     [di],ah
stbm_diag_return:
        mov     bStyleError,dl  ; save the current value of the error
        mov     bStyleMask,bh   ; save value of rotating style mask
        mov     dx,si           ; get the no of scans left
        pop     si              ; restore
        ret

StBm_Diagonal_4Q endp

;----------------------------------------------------------------------------;
StBm_Diagonal_1Q proc   near

        neg     NextSegOff      ; offset to next segment
        neg     FillBytes       ; number of bytes left over
        neg     NextScan        ; offset to prior scan line
        call    StBm_Diagonal_4Q        ; draw the slice

; now calculate the no of scan lines left from the bottom from the value in DX
; which is equal to the no of scan lines left from the top

        neg     dx
        add     dx,wScans
        inc     dx

        neg     FillBytes       ; make them positive again
        neg     NextSegOff
        neg     NextScan        ; get back offset to next scan
        ret

StBm_Diagonal_1Q endp

;-----------------------------------------------------------------------------;

comment ~
                  BYTE/PIXEL BITMAP STYLED LINE DRAWING ROUTINES
                  ----------------------------------------------

INPUTS:
         DS:DI    ----    current byte
   bStyleError    ----    current value of style error term
    bStyleMask    ----    current position of rotating style mask
    wDistHoriz    ----    scale factor in HORIZONTAL direction (=48)
     wDistVert    ----    scale factor in VERTICAL direction (=38)
     wDistDiag    ----    scale factor in diagonal direction (=61)
      NextScan    ----    (add) offset to next scanline in direction of move

RETURNS:
         DS:DI and wStyleError are updated.
         SI     retains their values
         CX,BH  destroyed
         AX     number of scanlines left from bottom
         DX     number of scan lines left from top

The draw routines in Positive_Y and Diagonal_1Q direction simply negates the
distance to the next scan line and calls the corresponding routines in the
opposite direction.

end comment ~

;---------------------------------------------------------------------------;
StBm8_Negative_Y        proc    near

        push    si                  ; save
        push    bx                  ; save mask

	mov	si,NextScan	; delta_di = NextScan
	call	StepsTo64KBound	; Get number of steps to 64K boundary in si

        mov     al,TmpColor
        mov     dl,bStyleError      ; the current value of style error
        mov     bh,bStyleMask       ; current position of style mask
        dec     cx                  ; take out last pixel from loop
        jz      StBm8_Y_last_pixel
StBm8_Y_loop:
        or      bh,bh               ; does mask permit bit to be set on
        jns     stbm8_vert_ignore   ; no
        call    BM8

stbm8_vert_ignore:

; advance the style mask

        xor     dh,dh               ; will hold the hibyte of err add
        add     dx,wDistVert        ; scale factor in vertical dir
        xchg    cl,dh               ; if DH = 1, the mask has to shift
        rol     bh,cl               ; rotate if necessary
        mov     cl,dh               ; restore count

; now move to the next scan line

        dec     si                ; one more scan line taken up
        jnz     StBm8_Y_same_segment ; still in same seg,ent

		test	DeviceFlags, TYPE_IS_DEV
		jz	stBm8_update_selector

		; update bank
		mov	si,NextSegOff
		or	si,si
		js	stBm8_Dec_Bank

		call	inc_bank_select
		jmp	short stBm8_update_offset

stBm8_Dec_Bank: call	dec_bank_select
		jmp	short stBm8_update_offset

stBm8_update_selector:
		mov	si,ds		  ; get current segment
		add	si,NextSegOff	  ; positive or negative offset
		mov	ds,si
stBm8_update_offset:
                add     di,FillBytes      ; bypass the filler bytes at end
                mov     si,wScans         ; number of scans in full segment

StBm8_Y_same_segment:
        add     di,NextScan       ; next scan in same segment
        loop    StBm8_Y_loop      ; process all the pixels

; do the last pixel

StBm8_Y_last_pixel:

        or      bh,bh               ; can last pixel be set on
        jns     stbm8_vert_return    ; no
        call    BM8
stbm8_vert_return:
        mov     bStyleError,dl      ; save
        mov     bStyleMask,bh       ; save style mask
        mov     dx,si               ; get scan lines left
        pop     bx                  ; get back mask
        pop     si                  ; restore
        ret

StBm8_Negative_Y	endp

;---------------------------------------
StBm8_Positive_Y        proc    near

        neg     NextSegOff        ; since we will be going to low addr
        neg     FillBytes
        neg     NextScan          ; (add) offset to next scan line
        call    StBm8_Negative_Y     ; line segment drawn

;  calculate the no of scan lines left from the bottom from DX which has no
;  of scan lines left from the top

        neg     dx
        add     dx,wScans
        inc     dx

;    restore back the values which where negated

        neg     FillBytes
        neg     NextSegOff
        neg     NextScan
        ret

StBm8_Positive_Y        endp

;----------------------------------------------------------------------------;
StBm8_Positive_X proc   near

; load relevent values into the registers

        push    si              ; will actually not need the value here
        push    dx              ; save scan line information
        mov     al,TmpColor
        mov     dl,bStyleError  ; current value of the error term
        mov     bh,bStyleMask   ; current position of the rotating style mask
        mov     si,wDistHoriz   ; load the vertical scale factor

; the draw loop

        dec     cx              ; leave out the last pixel from the loop
        jz      stbm8_horiz_last

stbm8_horiz_loop:

; draw the pixel if the mask says so

        or      bh,bh           ; the msb of the mask is the one to inspect
        jns     stbm8_horiz_ignore ; pixel not to be drawn
        call    BM8

stbm8_horiz_ignore:

        inc     di

; advance the mask if necessary

        xor     dh,dh           ; zero out high byte for add result
        add     dx,si           ; add the horizontal scale factor to error
        xchg    cl,dh           ; if BH is 1, the mask has to be rotated
        rol     bh,cl           ; rotate the mask
        mov     cl,dh           ; get back the count
        loop    stbm8_horiz_loop        ; process all the pixels

; draw the last pixel if the mask says so.

stbm8_horiz_last:
        or      bh,bh           ; test the mask
        jns     stbm8_horiz_return ; not to be drawn
        call    BM8
stbm8_horiz_return:

; save the current values of the error term and the style mask

        mov     bStyleError,dl
        mov     bStyleMask,bh
        pop     dx              ; get scan line information back
        pop     si              ; restore saved value
        ret

StBm8_Positive_X	endp

;---------------------------------------
StBm8_Diagonal_4Q proc  near

        push    si              ; save

	mov	si,NextScan	; delta_di = NextScan + 1
	inc	si
	call	StepsTo64KBound	; Get number of steps to 64K boundary in si

        mov     al,TmpColor
        mov     dl,bStyleError  ; the current value of the style error
        mov     bh,bStyleMask   ; current value of the style mask
        dec     cx              ; leave out the last pixel
        jz      StBm8_diag_last_pixel
StBm8_Diag_loop:
        or      bh,bh           ; test mask MSB
        jns     stbm8_diag_ignore  ; ignore this pel
        call    BM8
stbm8_diag_ignore:

; advance the style mask if  necessary

        xor     dh,dh           ; will hold the high byte of err add
        add     dx,wDistDiag    ; scale distance along diagonal
        xchg    cl,dh           ; if DH=1, style mask has to rotate
        rol     bh,cl           ; rotate the mask
        mov     cl,dh           ; restore count

; move to next scan

        add     di,NextScan	; delta_di = NextScan + 1
        inc     di
        dec     si              ; dec no of scans left in dir of move
        jnz     stbm8_diag_same_seg

		test	DeviceFlags, TYPE_IS_DEV
		jz	stBm8D_update_selector

		; update bank
		mov	si,NextSegOff
		or	si,si
		js	stBm8D_Dec_Bank

		call	inc_bank_select
		jmp	short stBm8D_update_offset

stBm8D_Dec_Bank: call	 dec_bank_select
		jmp	short stBm8D_update_offset

stBm8D_update_selector:
		mov	si,ds		  ; get current segment
		add	si,NextSegOff	  ; positive or negative offset
		mov	ds,si
stBm8D_update_offset:
                add     di,FillBytes      ; bypass the filler bytes at end
                mov     si,wScans         ; number of scans in full segment

stbm8_diag_same_seg:
        loop    StBm8_Diag_loop

; do the last pixel

StBm8_diag_last_pixel:
        or      bh,bh           ; does mak permit last pixel
        jns     stbm8_diag_return ; no
        call    BM8

stbm8_diag_return:
        mov     bStyleError,dl  ; save the current value of the error
        mov     bStyleMask,bh   ; save value of rotating style mask
        mov     dx,si           ; get the no of scans left
        pop     si              ; restore
        ret

StBm8_Diagonal_4Q endp

;----------------------------------------------------------------------------;
StBm8_Diagonal_1Q proc  near

	neg     NextSegOff      ; offset to next segment
	neg     FillBytes       ; number of bytes left over
	neg     NextScan        ; offset to prior scan line
	call    StBm8_Diagonal_4Q       ; draw the slice

; now calculate the no of scan lines left from the bottom from the value in DX
; which is equal to the no of scan lines left from the top

        neg     dx
        add     dx,wScans
        inc     dx

        neg     FillBytes       ; make them positive again
        neg     NextSegOff
        neg     NextScan        ; get back offset to next scan
        ret

StBm8_Diagonal_1Q endp
