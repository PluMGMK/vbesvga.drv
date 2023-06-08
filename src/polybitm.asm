;-----------------------------------------------------------------------------;
;		          POLYBITM.ASM			                      ;
;		          ------------			                      ;
; This file contains the draw for solid line on BITMAPs and the BITMAP move   ;
; routines. The file is included in POLYLINE.ASM			      ;
;									      ;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.
comment ~

This part contains the slice drawing routines for the BITMAPs. The are very
similar to what we have for EGA except that now the organization of the memory
is different and also the ROP2 codes will be handled differently.

                     MEMORY ORGANIZATION SMALL BITMAPS
                     ---------------------------------

Small bitmap are held in a single segment some where in memory. This segment
organizes the memory in terms of colour planes. The first part stores all the
bits for the first plane, then the second plane starts and then the third ...

The first plane corresponds to rightmost bit of the color value, the next plane
corresponds to the next bit to the left and so on.

                     MEMORY ORGANIZATION HUGE BITMAPS
                     --------------------------------

Huge BITMAPs span over more than one segment. For huge BITMAPs the bits are
stored on a scanline basis. That is the first few bytes correspond to first
scan line of plane 1, the next maps scan line of plane 2, the third maps the
first scan line of plane 3 and so on till the first scan line of all the planes
are covered. Then it maps the second scan line of all the planes in the same
manner. This mapping implies that there may be some bytes lefto over at the
end of the segment which are not sufficient to draw a scan line. These bytes
will be ignored and the next scanline will start on a new segment.

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
it or leave it unchanged. The ROP2 code values have very conviniently been 
allocated, if R is the ROP2 code (in the range 0 through 0fh) then the         
following realtionship holds:

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
the algorith followed is if D is the bit map byte containing the bit of our    
interest and BL has the rotating bit mask,

                      . get rotating bit mask into AL and AH
                      . AND AL with LOBYTE and AH with HIBYTE   
                      . INVERT AL
                      . AND D with AL
                      . XOR D with AH

The INVERT of AL with the subsequnet AND ensures that we can set or reset a
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
;									      ;
; -by-	Amit Chatteree		Wed 14-Sep-1988    12:00:25		      ;
;-----------------------------------------------------------------------------;
;				                                              ;
;                       DRAW AND MOV ROUTINES FOR BITMAPS                     ;
;                       ---------------------------------                     ;
; INPUTS:                                                                     ;
;				                                              ;
;            DS:DI          -----  current byte in BITMAP memory              ;
;               BL          -----  rotating bit mask for current pixel        ;
;               SI          -----  offset to next scan line (up or down)      ;
;               CX          -----  number of bits to draw                     ;
;       wBitmapROP          -----  XOR & AND MASK for current pen and ROP     ;
;        FillBytes          -----  extra bytes at the end of the segment      ;
;       NextSegOff          -----  segment offset to next segment             ;
;               DX          -----  number of scan lines left in the segment   ;
;			                                                      ;
; RETURNS:								      ;
;            DS:DI          -----  updated current byte in BITMAP             ;
;               BL          -----  updated rotating bit mask		      ;
;               DX          -----  updated numver of scan lines left          ;
;                                    this value is maintained in ScanLeft     ;
;            AX,CX          -----  destroyed                                  ;
;					                                      ;
; The DRAW routines for the POSITIVE_Y and DIAGONAL_1Q direction map on to the;
; ones for the NEGATIVE_Y and DIAGONAL_4Q after negating SI, the offset to    ;
; the next segment and the filler bytes value, and also scanleft should be    ;
; from the top of the bitmap memory                                           ;
;-----------------------------------------------------------------------------;

Bm_Negative_Y	proc	near

                mov	al,bl               ; get rotating bit mask
		mov	ah,al		    ; also into ah
		and	ax,wBitmapROP       ; get the mask into the AND,XOR msk 
		not	al		    ; invert the AND mask
		dec	cx	            ; take out last pixel from loop
		jz	Bm_Y_last_pixel
Bm_Y_loop:
		and	[di],al
		xor	[di],ah		    ; process one pixel

; now move to the next scan line

		dec	dx	          ; one more scan line taken up      
		jnz	Bm_Y_same_segment ; still in same seg,ent
		mov	dx,ds		  ; get current segment	
		add	dx,NextSegOff     ; positive or negative offset
		mov	ds,dx
		add	di,FillBytes      ; bypass the filler bytes at end   
		mov	dx,wScans         ; number of scans in full segment
Bm_Y_same_segment:
		add	di,si		  ; next scan in same segment
		loop	Bm_Y_loop	  ; process all the pixels

; do the last pixel

Bm_Y_last_pixel:

		and	[di],al
		xor	[di],ah		    ; process the last pixel
		ret

Bm_Negative_Y	endp
;----------------------------------------------------------------------------;
Bm_Positive_Y	proc	near

	        neg	NextSegOff	  ; since we will be going to low addr
	        neg     FillBytes          

;    The no of scan lines left now to be taken fromm top
  
		neg	dx
		add	dx,wScans
		inc	dx		  ; dx now has scansleft from top

;    now call Bm_Negative_Y

		call	Bm_Negative_Y     ; line segment drawn
                
;    now DX has the number of scanlines from top, we will calculate the no of
;    scan lines left from thr bottom from DX
 
		neg	dx
		add	dx,wScans
		inc	dx		  ; DX now has no of scans from bot 

;    restore back the values which where negated

		neg	FillBytes
		neg	NextSegOff
		ret

Bm_Positive_Y	endp
;---------------------------------------------------------------------------;
Bm_Positive_X	proc	near

		push	si		; save the offset to next scan line
		mov	si,wBitmapROP	; get the XOR,AND mask
		
; calculate start mask, ensd mask and the byte count

		dec	cx		; exclude the last pixel
		mov	ax,cx	      	; AX has last bit no.
		shiftr	ax,3 		; no of bytes to move
		and	cx,7		; no of bits left after that
		mov	bh,bl		; get the rotating bit mask
		ror	bl,cl		; bl has the last bit map
		mov	cx,ax		; no of bytes to move
		cmp	bh,bl		; test for wrap around	
		adc	cx,0		; one more byte in this case
		mov	al,bh		; initial bit mask
		mov	bh,bl		; ending mask
		neg	bh		; all bits to its left set to 1
		add	al,al
		dec	al		; all bits to right set to 1
		jcxz	Bm_X_do_last	; only one byte involved

; put out the first byte

		mov	ah,al
		and	ax,si		; mask just the pixels selected in byte
		not	al		; adjust the and mask
		and	[di],al		; set required bits to zero|unchanged  
		xor	[di],ah		; invert required bits
		inc	di		; next byte

; do intermediate bytes

		dec	cx
		jz	Bm_X_finish_up
		mov	ax,si		; the ROP mask
		not	al
Bm_X_output_loop:
		and	[di],al
		xor	[di],ah
		inc	di
		loop	Bm_X_output_loop

; do the last byte (combine end mask and previous mask)

Bm_X_finish_up:
		mov	al,0ffh		; previous mask if not just 1 byte mov
Bm_X_do_last:
		and	al,bh		; al has initial mask for 1 byte move
		mov	ah,al
		and	ax,si		; combine with the ROP
		not	al		; adjust AND mask
		and	[di],al
		xor	[di],ah
		pop	si		; save offset to next scan
		ret

Bm_Positive_X	endp
;-----------------------------------------------------------------------------;
Bm_Diagonal_4Q	proc	near

		mov	al,bl		; get rotating bit mask
		mov	ah,al
		and	ax,wBitmapROP   ; combine with the ROP masks
		not	al		; adjust the AND mask
		dec	cx		; leave out the last pixel
		jz	Bm_diag_last_pixel
Bm_Diag_loop:
		and	[di],al
		xor	[di],ah		; process 1 pixel

; move to next scan

		ror	al,1
		ror	ah,1
		ror	bl,1		; the rotating bit mask updated
		adc	di,si
		dec	dx		; dec no of scans left in dir of move
		jnz	bm_diag_same_seg

; move to next (prior) huge scan

		mov	dx,ds
		add	dx,NextSegOff	; offset of required segment
		mov	ds,dx
		add	di,FillBytes	; no of left over bytes
		mov	dx,wScans	; new value of number of scans left
bm_diag_same_seg:
	        loop	Bm_Diag_loop
	
; do the last pixel

Bm_diag_last_pixel:
		
		and	[di],al
		xor	[di],ah
		ret

Bm_Diagonal_4Q	endp
;-----------------------------------------------------------------------------;
Bm_Diagonal_1Q	proc	near

		neg	NextSegOff	; offset to next segment
		neg	FillBytes	; number of bytes left over
		neg	dx
		add	dx,wScans
		inc	dx		; dx now has scans left from the top
		call	Bm_Diagonal_4Q	; draw the slice

;    now DX has the number of scanlines from top, we will calculate the no of
;    scan lines left from thr bottom from DX
 
		neg	dx
		add	dx,wScans
		inc	dx		  ; DX now has no of scans from bot 
		neg	FillBytes	; make them positive again
		neg	NextSegOff
		ret

Bm_Diagonal_1Q	endp
;-----------------------------------------------------------------------------;
Bm_Move_Negative_Y proc	near

		add	di,si		; next scan line
		dec	dx		; reduce no of scanlines left
		jnz	bm_move_in_same_seg_positive
		mov	dx,ds
		add	dx,NextSegOff	; nect segment
		mov	ds,dx
		add	di,FillBytes	; skip over filler bytes
		mov	dx,wScans	; no of scan lines left    
bm_move_in_same_seg_positive:
		ret

Bm_Move_Negative_Y 	endp
;-----------------------------------------------------------------------------; 
Bm_Move_Positive_Y proc	near

		add	di,si		; previous scan line
		neg	dx
		add	dx,wScans	; scan lines left in direction of move
		or	dx,dx
		jnz	bm_move_in_same_seg_negative
		mov	dx,ds
		sub	dx,NextSegOff	; previous segment
		mov	ds,dx
		sub	di,FillBytes	; skip over filler bytes
		mov	dx,wScans
bm_move_in_same_seg_negative:
		neg	dx
		add	dx,wScans	; no of scans left from bottom
		inc	dx		; include current line in count
	        ret

Bm_Move_Positive_Y	endp
;----------------------------------------------------------------------------;
Bm_Move_Positive_X proc	near

		ror	bl,1		; next to the right
		adc	di,0		; next byte if wrap around
		ret

Bm_Move_Positive_X	endp
;----------------------------------------------------------------------------;
Bm_Move_Diagonal_4Q proc near

		ror	bl,1		; next bit position
		adc	di,0		; next byte if necessary
		call	Bm_Move_Negative_Y
		ret

Bm_Move_Diagonal_4Q	endp
;---------------------------------------------------------------------------;
Bm_Move_Diagonal_1Q proc near

		ror	bl,1		; next bit position
		adc	di,0		; nexy byte if wrap around
		call	Bm_Move_Positive_Y
		ret

Bm_Move_Diagonal_1Q	endp
;---------------------------------------------------------------------------;
