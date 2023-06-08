;******************************************************************************
;
;	File:	RLECOM.ASM
;	Author: James Keller
;	Date:	8/14/89
;
;   This module holds routines common to the RLE encoding and decoding
;   tasks.
;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.
;******************************************************************************


include	cmacros.inc
include macros.mac
include gdidefs.inc
include rledat.inc


	externA   __NEXTSEG

createSeg	_DIMAPS, DIMapSeg, word, public, code
sBegin		DIMapSeg
    assumes	cs, DIMapSeg

cProc	frame, <FAR,WIN,PASCAL>,<ds,si,di,es>
include	bmc_main.var
cBegin	<nogen>
cEnd	<nogen>

;******************************************************************************
; entry
;   al - has the source bits
;   ah - undefined, available for use
;   bx - undefined, available for use
;   cl - has the run length
;   ch - has the current bit position
;   es:[di] - points to the destination
;   ds:[si] - points to the source
;   ss:[bx] - points to the xlat table

public	copyrle_exi1
copyrle_exi1	proc	near

	mov	bx,cx

	; check for more than one byte of destination
	neg	ch		    ; how many bits in first byte?
	add	ch,8
	sub	cl,ch		    ; subtract first bytes from total
	jb	copyrle_exi_only_one_byte

	mov	ah,cl
	shiftr	ah,3		    ; compute middle count

	; compute last mask
	and	cl,7
	mov	bl,0ffh
	shr	bl,cl
	not	bl

	; compute first mask
	mov	cl,0ffh
	xchg	cl,bh
	shr	bh,cl		    ; first mask is in ch now

	; now we have
	;   al - has the mono pixel data
	;   ah - contains middle count
	;   bl - contains last mask
	;   bh - contains first mask
	;   cx - is available for use

	; do the first byte
	not	bh
	and	es:[di],bh	    ; preserve unaffected bits in destination
	not	bh
	and	bh,al
	or	es:[di],bh	    ; lay in new pixel data bits
	inc	di

	mov	cl,ah
	xor	ch,ch
	rep	stosb		    ; do middle count

	or	bl,bl		    ; is there a final byte?
	jz	@F

	not	bl		    ; mask the final byte and lay it in
	and	es:[di],bl
	not	bl
	and	al,bl
	or	es:[di],al
@@:
	ret

copyrle_exi_only_one_byte:
	;compute first mask
	mov	ch,0ffh
	mov	cl,bh
	shr	ch,cl

	add	cl,bl		    ; last bit position
	neg	cl
	add	cl,8
	mov	bh,0ffh
	shl	bh,cl

	and	ch,bh

	not	ch
	and	es:[di],ch
	not	ch
	and	ch,al
	or	es:[di],ch

	ret

copyrle_exi1	endp


;******************************************************************************
public	copyrle_e4i1
copyrle_e4i1	proc	near
       mov     ah      ,al	       ; save color 1

       and     al      ,0fh	       ; mask off color 0
       shiftl  al      ,1	       ;form index into
       or      al      ,1	       ;    color table
       xlat    ss:[bx]		       ;
       shr     al      ,1	       ;get mono bit
       sbb     al      ,al	       ;spread it out to a byte
       and     al      ,0ch	       ; save only two bits of it

       xchg    ah      ,al	       ; do the same with color 1
       and     al      ,0f0h
       shiftr  al      ,3
       or      al      ,1
       xlat    ss:[bx]
       shr     al      ,1
       sbb     al      ,al
       and     al      ,5
       or      al      ,al	       ; now colors have been merged

       test    ch      ,1	       ; align with destination
       jne     @F
       ror     al      ,1
@@:
       call    copyrle_exi1	       ;run the value throughtout the length
       ret

copyrle_e4i1	endp


;******************************************************************************
public	copyrle_e8i1
copyrle_e8i1	proc	near
       xor     ah      ,ah	       ;prepare for color mapping
       shiftl  ax      ,1	       ;form index into
       or      ax      ,1	       ;    color table
       add     bx      ,ax	       ;
       mov     al      ,ss:[bx]        ;al now holds the remapped color
       shr     al      ,1	       ;get mono bit
       sbb     al      ,al	       ;spread it out to a byte

       call    copyrle_exi1	       ;run the value throughtout the length
       ret

copyrle_e8i1	endp


;******************************************************************************
public	copyrle_exi8
copyrle_exi8   proc    near

	push	ax
	test	di	,1		;if di is on an odd boundary
	je	copyrle_exi8_3
	stosb				;store the odd byte
	dec	cx			;decrement the count
	xchg	al	,ah		;swap low and high for word storage

copyrle_exi8_3:
	shr	cx	,1
	rep	stosw			;store all word aligned values
	rcl	cx	,1
	rep	stosb

	pop	ax
        ret

copyrle_exi8   endp


;******************************************************************************
public	copyrle_e4i8
copyrle_e4i8	proc	near

	mov	ch	,0
	jnc	copyrle_e4i8_0
	ror	al	,1
	ror	al	,1
        ror     al      ,1
        ror     al      ,1

copyrle_e4i8_0:
	mov	ah	,al
	shl	al	,1
	and	al	,1EH
        xlat    ss:[bx]                 ;get the remapped color value
	xchg	ah	,al
	shiftr	al	,3		;form index into
	and	al	,1EH
        xlat    ss:[bx]
	call	copyrle_exi8
	ret

copyrle_e4i8	endp

;******************************************************************************
public	copyrle_e8i8
copyrle_e8i8	proc	near

       mov	ch	,0
       xor     ah      ,ah
       shiftl  ax      ,1	       ;form index into
       add     bx      ,ax	       ;   a word table
       mov     al      ,ss:[bx]        ;get the remapped color value
       mov     ah      ,al	       ;two identical bytes for quick storage
       call    copyrle_exi8
       ret

copyrle_e8i8	endp


;******************************************************************************
public	copyabs_e4i1
copyabs_e4i1	proc	near
	; set up ch to contain a rotating bit for the position
	mov	ah,080h
	xchg	ch,cl
	shr	ah,cl
	xchg	ch,cl
	mov	ch,ah
	xor	ah,ah			; clear it out for later xlats

	; fetch destination
	mov	dh,es:[di]
	push	bp
	jmp	short copyabs_e4i1_loop

; now we have
; al - is available for use
; ah - zero
; bx - points to base of xlat table
; cl - absolute run length
; ch - rotateing current bit
; dl - is available
; dh - current working byte of destination

copyabs_e4i1_set_bit:
	or	dh,ch
	dec	cl			; more bits?
	jz	copyabs_e4i1_done
	ror	ch,1
	jc	copyabs_e4i1_nextbyte

copyabs_e4i1_loop:
	; fetch next pixel in absolute run
	mov	al,es:[di]
	; xlate the pixel
	mov	bp,bx			; get base of xlat table
	and	al,0f0h
	shiftr	al,3
	or	al,1
	add	bp,ax			; pixel value
	mov	al,ss:[bp]
	shr	al,1			; put mono bit in carry

	jc	copyabs_e4i1_5
	;clear the bit
	mov	dl,ch
	not	dl
	and	dh,dl
	jmp	short copyabs_e4i1_10
copyabs_e4i1_5:
	;set the bit
	or	dh,ch
copyabs_e4i1_10:
	;are we done?
	dec	cl
	jz	copyabs_e4i1_done
	;new byte needed?
	ror	ch,1
	jnc	copyabs_e4i1_20

	mov	al,dh
	stosb
	mov	dh,es:[di]
copyabs_e4i1_20:
	;do second pixel in source byte
	lodsb
	and	al,0fh
	or	si,si			; check for segment overflow
	jne	@F
	mov	si,ds
	add	si,__NEXTSEG
	mov	ds,si
	sub	si,si
@@:
	; xlate the pixel
	mov	bp,bx			; get base of xlat table
	shl	al,1			; *2+1
	or	al,1
	add	bp,ax			; pixel value
	mov	al,ss:[bp]
	shr	al,1			; put mono bit in carry

	jc	copyabs_e4i1_set_bit

	; clear the bit
	mov	dl,ch
	not	dl
	and	dh,dl
	dec	cl
	jz	copyabs_e4i1_done
	ror	ch,1
	jnc	copyabs_e4i1_loop

copyabs_e4i1_nextbyte:
	mov	al,dh
	stosb
	mov	dh,es:[di]
	jmp	short copyabs_e4i1_loop

copyabs_e4i1_done:
	; store current working byte
	ror	ch,1
	jnc	copyabs_e4i1_really_done
	mov	al,dh
	stosb
	jmp	short copyabs_e4i1_really_really_done
copyabs_e4i1_really_done:
	mov	es:[di],dh
copyabs_e4i1_really_really_done:

	pop	bp
	ret
copyabs_e4i1	endp


;******************************************************************************
public	copyabs_e8i1
copyabs_e8i1	proc	near
	; set up ch to contain a rotating bit for the position
	mov	ah,080h
	xchg	ch,cl
	shr	ah,cl
	xchg	ch,cl
	mov	ch,ah
	xor	ah,ah			; clear it out for later xlats

	; fetch destination
	mov	dh,es:[di]
	push	bp
	jmp	short copyabs_e8i1_loop

; now we have
; al - is available for use
; ah - zero
; bx - points to base of xlat table
; cl - absolute run length
; ch - rotateing current bit
; dl - is available
; dh - current working byte of destination

copyabs_e8i1_set_bit:
	or	dh,ch
	dec	cl			; more bits?
	jz	copyabs_e8i1_done
	ror	ch,1
	jc	copyabs_e8i1_nextbyte

copyabs_e8i1_loop:
	; fetch next pixel in absolute run
	lodsb
	or	si,si			; check for segment overflow
	jne	@F
	mov	si,ds
	add	si,__NEXTSEG
	mov	ds,si
	sub	si,si
@@:
	; xlate the pixel
	mov	bp,bx			; get base of xlat table
	shl	al,1			; *2+1
	or	al,1
	add	bp,ax			; pixel value
	mov	al,ss:[bp]
	shr	al,1			; put mono bit in carry

	jc	copyabs_e8i1_set_bit

	; clear the bit
	mov	dl,ch
	not	dl
	and	dh,dl
	dec	cl
	jz	copyabs_e8i1_done
	ror	ch,1
	jnc	copyabs_e8i1_loop

copyabs_e8i1_nextbyte:
	mov	al,dh
	stosb
	mov	dh,es:[di]
	jmp	short copyabs_e8i1_loop

copyabs_e8i1_done:
	; store current working byte
	ror	ch,1
	jnc	copyabs_e8i1_really_done
	mov	al,dh
	stosb
	jmp	short copyabs_e8i1_really_really_done
copyabs_e8i1_really_done:
	mov	es:[di],dh
copyabs_e8i1_really_really_done:

	pop	bp
	ret

copyabs_e8i1	endp


;******************************************************************************
public	copyabs_e4i8
copyabs_e4i8	proc	near

	mov	ch,0
	jnc	copyabs_e4i8_loop
        lodsb
	or	si	,si
	jne	copyabs_e4i8_1
	mov	si	,ds
	add	si	,__NEXTSEG
	mov	ds	,si
	sub	si	,si
	jmp	copyabs_e4i8_1

copyabs_e4i8_loop:
	lodsb
        or      si      ,si
	jne	copyabs_e4i8_0
	mov	si	,ds
	add	si	,__NEXTSEG
	mov	ds	,si
	sub	si	,si

copyabs_e4i8_0:
       mov     ah      ,al
       shiftr  al      ,3
       and     al      ,1EH
       xlat    ss:[bx]
       stosb
       dec     cx
       je      copyabs_e4i8_done

       mov     al      ,ah
copyabs_e4i8_1:
       and     al      ,0FH
       shl     al      ,1
       xlat    ss:[bx]
       stosb
       loop    copyabs_e4i8_loop
       stc
       ret

copyabs_e4i8_done:
       clc
       ret

copyabs_e4i8	endp


;******************************************************************************
public	copyabs_e8i8
copyabs_e8i8	proc	near

       push    bp
       mov     ch      ,0

copyabs_e8i8_loop:
       mov     bp      ,bx
       lodsb
       or      si      ,si
       jne     copyabs_e8i8_0
       mov     si      ,ds
       add     si      ,__NEXTSEG
       mov     ds      ,si
       sub     si      ,si

copyabs_e8i8_0:
       xor     ah      ,ah
       shiftl  ax      ,1	       ;form index into
       add     bp      ,ax	       ;   a word table
       mov     al      ,ss:[bp]        ;get the remapped color value
       stosb
       loop    copyabs_e8i8_loop

       clc			       ;return value for DIB TO SCREEN
       pop     bp
       ret

copyabs_e8i8	endp



sEnd	DIMapSeg

END
