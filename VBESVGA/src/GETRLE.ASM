;
;
;      File:   GETRLE.ASM
;      Author: James Keller
;      Date:   8/15/89
;
;   This module holds all the RLE encoding routines.
;   Internal 1,8 -> External 4,8
;
;      All the copyrle_iXeY routines have the same parameters.
;
;      DS:SI   -       ptr to the data sequence to be run length encoded
;      ES:DI   -       ptr to the location to store the run length encoding
;      CX      -       maximum number of bytes to run length encode
;      AL      -       run length value
;
;      All the copyrle_iXeY routines return the same value.
;
;      CX      -       the number of bytes encoded in this record.
;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.


include cmacros.inc
include windefs.inc
include macros.mac
include gdidefs.inc
include rledat.inc

	externFP	ipc_to_rgb_seq		; in RGB2IPC.ASM
	externFP	ipc_to_rgb_far		; in RGB2IPC.ASM
	externFP	match_to_palette_far	; in RGB2IPC.ASM

ADDITIONAL_STACK        EQU     2048
%out oh no 2K stack !!!

createSeg	_DIMAPS, DIMapSeg, word, public, code
sBegin		DIMapSeg

	assumes	cs, DIMapSeg

        externA         __NEXTSEG       ; offset to next segment

	; near functions defined in BMC_ITE.ASM:
	externNP	setup_colour_table_4
	externNP	setup_colour_table_8

public	encode_scanline_I1
public	encode_scanline_I8
public	encode_scanline_IX

cProc	frame, <FAR,WIN,PASCAL>,<ds,si,di,es>
include	bmc_main.var
cBegin	<nogen>
cEnd	<nogen>

public	scanline_encode_bitmap
scanline_encode_bitmap  proc    near

        lds     si,lp_info_ext
        assumes ds,nothing

	mov	rle_scanmask, 0F0FH

        mov     ax      ,wptr [si].biCompression
	mov	bx	,0
	mov	cx	,OFFSET setup_colour_table_4
	; since DeviceColorMatch isn't used for RLE encoding,
	; abuse that slot on the stack for our 24-bit translation
	; routine (only needed in high-colour modes)
	mov	wptr [DeviceColorMatch],OFFSET translate24_e4
	cmp	ax	,BI_RLE4
	je	scanline_encode_type_found

	mov	rle_scanmask, 0FFFFH
	inc	bx
	mov	cx	,OFFSET setup_colour_table_8
	mov	wptr [DeviceColorMatch],OFFSET translate24_e8
	cmp	ax	,BI_RLE8
	je	scanline_encode_type_found
	xor	ax	,ax		;error code
	xor	dx	,dx
        jmp     scanline_encode_bitmap_done

scanline_encode_type_found:
	call	cx			;setup colour table

	les	si	,lp_dest_dev
	mov	ax	,es:[si].bmHeight
	mov	bitmap_height, ax

        mov     dx      ,255            ;max num of rle color bytes = 255 pixels
	mov	cx	,es:[si].bmWidth
	mov	di	,OFFSET encode_scanline_I8

	cmp	es:[si].bmPlanes, 1		; is it one plane ?
	jnz	scanline_encode_color		; no, so it is color
	cmp	es:[si].bmBitsPixel, 1		; 1 bit per pel
	jnz	scanline_encode_color		; no so it is color

	mov	rle_scanmask, 0FFH
	mov	di	,OFFSET encode_scanline_I1
	add	bx	,NOF_EXTERNAL_RLE_TYPES
        mov     dx      ,31             ;max num of rle mono bytes = 248 pixels
	add	cx	,7
	shiftr	cx	,3
	jmp	SHORT	@F

scanline_encode_color:
	cmp	[use_palette_trans],0
	jnz	@F
	; non-palette colour routines
	mov	di	,OFFSET encode_scanline_IX
	add	bx	,NOF_EXTERNAL_RLE_TYPES*2

@@:	mov	bitmap_width, cx
	mov	encode_scanline ,di
        mov     maximum_encodedline_length, dx
	mov	cx	,es:[si].bmWidthBytes
	mov	int_aligned_width, cx

	add	bx	,bx			  ;specific encode routine
	mov	ax	,cs:encode_rle_table[bx]
	mov	encode_rle	,ax
	mov	ax	,cs:encode_absolute_table[bx]
	mov	encode_absolute ,ax

	mov	ax	,init_scan
	cmp	ax	,bitmap_height
	jl	scanline_encode_bitmap0
	xor	ax	,ax
	xor	dx	,dx			  ;error code
	jmp	scanline_encode_bitmap_done

scanline_encode_bitmap0:
	add	ax	,num_scans
	cmp	ax	,bitmap_height
	jle	scanline_encode_bitmap1
	mov	ax	,bitmap_height
	sub	ax	,init_scan
	mov	ax	,num_scans

scanline_encode_bitmap1:

        mov     dx      ,1
	sub	ax	,ax
	div	int_aligned_width
	mov	scans_per_seg, ax
        neg     dx
	sub	dx	,int_aligned_width
	mov	neg_filler_bytes  ,dx

	cmp	bx	,0
	jne	scanline_encode_color0

	lea	di	,xlati_1_to_4
	mov	WORD PTR ss:[di + 00H] ,00000H
	mov	WORD PTR ss:[di + 02H] ,0F000H
	mov	WORD PTR ss:[di + 04H] ,00F00H
	mov	WORD PTR ss:[di + 06H] ,0FF00H
	mov	WORD PTR ss:[di + 08H] ,000F0H
	mov	WORD PTR ss:[di + 0AH] ,0F0F0H
	mov	WORD PTR ss:[di + 0CH] ,00FF0H
	mov	WORD PTR ss:[di + 0EH] ,0FFF0H

	mov	WORD PTR ss:[di + 10H] ,0000FH
	mov	WORD PTR ss:[di + 12H] ,0F00FH
	mov	WORD PTR ss:[di + 14H] ,00F0FH
	mov	WORD PTR ss:[di + 16H] ,0FF0FH
	mov	WORD PTR ss:[di + 18H] ,000FFH
	mov	WORD PTR ss:[di + 1AH] ,0F0FFH
	mov	WORD PTR ss:[di + 1CH] ,00FFFH
	mov	WORD PTR ss:[di + 1EH] ,0FFFFH

scanline_encode_color0:

	mov	bx	,es:[si].bmSegmentIndex    ;segment step
	lds	si	,es:[si].bmBits 	   ;set the start address
	mov	ax	,init_scan
	add	ax	,num_scans
	mov	dx	,ds

scanline_encode_color1:
	add	dx	,bx
	sub	ax	,scans_per_seg
	ja	scanline_encode_color1

	sub	dx	,bx
	mov	ds	,dx
        add     ax      ,scans_per_seg
	dec	ax
	mul	int_aligned_width
	add	si	,ax

	les	di	,lp_bits_ext
	mov	rle_getlength  ,es
	or	rle_getlength  ,di
	jne	actually_encode
	mov	WORD PTR scan_length, 0
	mov	WORD PTR [scan_length + 2], 0
        mov     ax      ,ss
	mov	es	,ax

actually_encode:
	mov	ax	,num_scans
	mov	scanline_count, ax
        call    block_encode
	mov	ax	,num_scans
	xor	dx	,dx			;return number of scans
	cmp	rle_getlength, 0
	jne	scanline_encode_bitmap_done
	lds	si	,lp_info_ext
	mov	bx	,WORD PTR scan_length
	mov	wptr ds:[si].biSizeImage, bx
	mov	bx	,WORD PTR [scan_length + 2]
	mov	wptr ds:[si].biSizeImage + 2, bx

scanline_encode_bitmap_done:
        ret

scanline_encode_bitmap	endp



public	block_encode
block_encode	proc	near

	sub	sp	,ADDITIONAL_STACK
	cmp	rle_getlength ,0
	jne	block_encode_loop
	mov	di	,sp

block_encode_loop:
	mov	dx	,bitmap_width

        cmp     rle_getlength ,0
        jne     block_encode_doin_it
        sub     di      ,sp                     ;accumulate rle length
	add	WORD PTR scan_length, di
	adc	WORD PTR [scan_length + 2], 0
	mov	di	,sp

block_encode_doin_it:
        call    encode_scanline
	dec	scanline_count
        je      block_encode_end

	mov	ax	,RLE_TYPE_END_OF_LINE
	stosw
	or	di	,di
	jne	no_wrap0
	mov	ax	,es
	add	ax	,__NEXTSEG
	mov	es	,ax

no_wrap0:
	sub	si	,int_aligned_width
	jnc	block_encode_loop
	mov	ax	,ds
	sub	ax	,__NEXTSEG
	mov	ds	,ax
	mov	si	,neg_filler_bytes
	jmp	block_encode_loop

block_encode_end:

	mov	ax	,RLE_TYPE_END_OF_FRAME
	stosw
	or	di	,di
	jne	no_wrap1
	mov	ax	,es
	add	ax	,__NEXTSEG
        mov     es      ,ax

no_wrap1:
	sub	di	,sp			;accumulate rle length
	add	WORD PTR scan_length, di	;  the rle, this is unneeded
	adc	WORD PTR [scan_length + 2], 0	;  but it will not hurt

        add     sp      ,ADDITIONAL_STACK
        ret

block_encode	endp



encode_scanline_I1	proc	near

	push	si

encode_scanline_I1_loop:
	mov	cx	,dx
	cmp	cx	,MAXIMUM_RLE_LENGTH_I1
	jl	encode_scanline_i1max
	mov	cx	,MAXIMUM_RLE_LENGTH_I1

encode_scanline_i1max:
	mov	al	,ds:[si]
	mov	ah	,al
	cmp	cx	,MINIMUM_ABSOLUTE_LENGTH
	jle	encode_scanline_i1rle
	inc	ah
	and	ah	,0FEH
	je	encode_scanline_i1rle

encode_scanline_i1abs:
	mov	bx	,di
	add	di	,2

	call	encode_absolute
	inc	di
	and	di	,0FFFEH
        mov     BYTE PTR es:[bx] ,0
	mov	BYTE PTR es:[bx + 1] ,cl
        jmp     encode_scanline_i1loop

encode_scanline_i1rle:
	call	encode_rle
	mov	BYTE PTR es:[di] ,cl
	mov	BYTE PTR es:[di + 1] ,al
	add	di	,2

encode_scanline_i1loop:
	sub	dx	,cx
	jne	encode_scanline_I1_loop

	pop	si
        ret

encode_scanline_I1	endp



encode_scanline_I8	proc	near

	push	si

encode_scanline_I8_loop:
	mov	cx	,dx
	cmp	cx	,MAXIMUM_RLE_LENGTH_I8
	jl	encode_scanline_i8max
	mov	cx	,MAXIMUM_RLE_LENGTH_I8

encode_scanline_i8max:
	cmp	cx	,1
	ja	encode_scanline_gt1
	lodsb
	xlat	ss:[bx]
	cmp	wptr [DeviceColorMatch],OFFSET translate24_e4
	jne	@F
	shiftl	al	,4 ;4-bit bitmap --> shift pixel into upper nibble
@@:	mov	ah	,al
	mov	al	,1
	stosw
	jmp	short	encode_scanline_i8loop

encode_scanline_gt1:
	lea	bx	,color_xlate
	mov	ax	,ds:[si]
	xlat	ss:[bx]
	and	ax	,rle_scanmask
	xchg	ah	,al
	xlat	ss:[bx]
	and	ax	,rle_scanmask
	xchg	al	,ah

	cmp	cx	,MINIMUM_ABSOLUTE_LENGTH
	jle	encode_scanline_i8rle
	cmp	al	,ah
	je	encode_scanline_i8rle

encode_scanline_i8abs:
	push	di
	push	es
	add	di	,2

	jne	no_wrap9
	mov	ax	,es
	add	ax	,__NEXTSEG
        mov     es      ,ax

no_wrap9:
	call	encode_absolute
	or	di	,di
	je	no_wrap2
	inc	di
	and	di	,0FFFEH
	jne	no_wrap2
	mov	ax	,es
	add	ax	,__NEXTSEG
        mov     es      ,ax

no_wrap2:
	mov	ax	,es
	pop	es
	pop	bx
	mov	BYTE PTR es:[bx] ,0
	mov	BYTE PTR es:[bx + 1] ,cl
	mov	es	,ax
	jmp	encode_scanline_i8loop

encode_scanline_i8rle:
	call	encode_rle
	mov	BYTE PTR es:[di] ,cl
	mov	BYTE PTR es:[di + 1] ,al
	add	di	,2
	jne	no_wrap3
	mov	ax	,es
	add	ax	,__NEXTSEG
        mov     es      ,ax

no_wrap3:

encode_scanline_i8loop:
	sub	dx	,cx
	je	encode_scanline_I8_loop_skip
	jmp	encode_scanline_I8_loop

encode_scanline_I8_loop_skip:
	pop	si
        ret

encode_scanline_I8	endp



encode_scanline_IX	proc	near

	push	si

encode_scanline_IX_loop:
	mov	cx	,dx
	cmp	cx	,MAXIMUM_RLE_LENGTH_I8
	jl	encode_scanline_iXmax
	mov	cx	,MAXIMUM_RLE_LENGTH_I8

encode_scanline_iXmax:
	cmp	cx	,1
	ja	encode_scanline_IX_gt1
	push	dx
	call	[lods_pixel]
	call	ipc_to_rgb_far
	call	wptr [DeviceColorMatch]	;translate24
	pop	dx
	cmp	wptr [DeviceColorMatch],OFFSET translate24_e4
	jne	@F
	shiftl	al	,4 ;4-bit bitmap --> shift pixel into upper nibble
@@:	mov	ah	,al
	mov	al	,1
	stosw
	jmp	encode_scanline_iXloop

encode_scanline_IX_gt1:
	lea	bx	,color_xlate
	; at this point, we peek at the next two pixels and make sure
	; they're equal (otherwise there's no run length to encode!)
	push	dx
	push	cx
	push	si	; we're only peeking!
	call	[lods_pixel]
	call	ipc_to_rgb_far
	call	wptr [DeviceColorMatch]	;translate24
	and	ax	,rle_scanmask
	mov	ch	,al
	call	[lods_pixel]
	call	ipc_to_rgb_far
	call	wptr [DeviceColorMatch]	;translate24
	mov	ah	,al
	mov	al	,ch
	; now we have the next two xlated pixels in AL and AH
	pop	si
	pop	cx
	pop	dx

	cmp	cx	,MINIMUM_ABSOLUTE_LENGTH
	jle	encode_scanline_iXrle
	cmp	al	,ah
	je	encode_scanline_iXrle

encode_scanline_iXabs:
	push	di
	push	es
	add	di	,2

	jne	esliX_no_wrap9
	mov	ax	,es
	add	ax	,__NEXTSEG
        mov     es      ,ax

esliX_no_wrap9:
	call	encode_absolute
	or	di	,di
	je	esliX_no_wrap2
	inc	di
	and	di	,0FFFEH
	jne	esliX_no_wrap2
	mov	ax	,es
	add	ax	,__NEXTSEG
        mov     es      ,ax

esliX_no_wrap2:
	mov	ax	,es
	pop	es
	pop	bx
	mov	BYTE PTR es:[bx] ,0
	mov	BYTE PTR es:[bx + 1] ,cl
	mov	es	,ax
	jmp	encode_scanline_iXloop

encode_scanline_iXrle:
	call	encode_rle
	mov	BYTE PTR es:[di] ,cl
	mov	BYTE PTR es:[di + 1] ,al
	add	di	,2
	jne	esliX_no_wrap3
	mov	ax	,es
	add	ax	,__NEXTSEG
        mov     es      ,ax

esliX_no_wrap3:

encode_scanline_iXloop:
	sub	dx	,cx
	je	encode_scanline_IX_loop_skip
	jmp	encode_scanline_IX_loop

encode_scanline_IX_loop_skip:
	pop	si
        ret

encode_scanline_IX	endp




public	copyrle_i1e4, copyrle_i1e8
copyrle_i1e4   proc    near
copyrle_i1e8:

	push	ax
        push    dx
	mov	dx	,cx		;save maximum bytes to encode
	cmp	al	,0FFH
	je	copyrle_i1e4
	mov	al	,0FFH

copyrle_i1e4_loop0:
	inc	si
	cmp	al	,ds:[si]	;while pixel is not FF (off)
	loopne	copyrle_i1e4_loop0	;  run length keeps going
	jmp	copyrle_i1e4_done

copyrle_i1e4_loop1:
	inc	si
	cmp	al	,ds:[si]	;while pixel is FF (on)
	loope	copyrle_i1e4_loop1	;  run length keeps going

copyrle_i1e4_done:
        sub     dx      ,cx
	shiftl	cx	,3
        mov     cx      ,dx
	pop	dx
	pop	ax
	ret

copyrle_i1e4   endp



public	copyrle_i8e4
copyrle_i8e4   proc    near

        push    dx
	mov	ah	,al
	mov	dx	,cx		;save maximum bytes to encode

copyrle_i8e4_loop:
	mov	al	,ds:[si]
	xlat	ss:[bx]
	and	al	,0FH
	cmp	al	,ah		;if not the same pixel value, then done
	jne	copyrle_i8e4_done
	inc	si
	loop	copyrle_i8e4_loop

copyrle_i8e4_done:
	sub	dx	,cx
	mov	cx	,dx
        mov     al      ,ah
	shiftl	al	,4
	or	al	,ah
	pop	dx
	ret

copyrle_i8e4   endp



public	copyrle_i8e8
copyrle_i8e8   proc    near

	push	dx
        mov     ah      ,al
	mov	dx	,cx		;save maximum bytes to encode

copyrle_i8e8_loop:
	mov	al	,ds:[si]	;if not the same pixel value, then done
	xlat	ss:[bx]
	cmp	al	,ah
	jne	copyrle_i8e8_done
	inc	si
	loop	copyrle_i8e8_loop

copyrle_i8e8_done:
        sub     dx      ,cx
	mov	cx	,dx
	mov	al	,ah
	pop	dx
	ret

copyrle_i8e8   endp



public	copyrle_iXe4
copyrle_iXe4   proc    near

	push	di
        push    dx
	push	cx			;save maximum bytes to encode
	.errnz	MAXIMUM_RLE_LENGTH_I8 AND (NOT 0FFh)
	mov	ch	,al		;CL is counter, CH is colour
	mov	di	,si		;DI points at "previous pixel"

copyrle_iXe4_loop:
	call	[lods_pixel]
	call	ipc_to_rgb_far
	cCall	match_to_palette_far,<ss,bx,16>
	and	al	,0FH
	cmp	al	,ch		;if not the same pixel value, then done
	jne	copyrle_iXe4_done
	mov	di	,si		;update "previous pixel" pointer
	dec	cl
	jnz	copyrle_iXe4_loop

copyrle_iXe4_done:
	mov	si	,di		;go to "previous pixel" if necessary
	mov	ah	,ch
	xor	ch	,ch		;get that colour out of CX!

	pop	dx			;get back max bytes to encode
	sub	dx	,cx
	mov	cx	,dx
        mov     al      ,ah
	shiftl	al	,4
	or	al	,ah
	pop	dx
	pop	di
	ret

copyrle_iXe4   endp



public	copyrle_iXe8
copyrle_iXe8   proc    near

	push	di
        push    dx
	push	cx			;save maximum bytes to encode
	.errnz	MAXIMUM_RLE_LENGTH_I8 AND (NOT 0FFh)
	mov	ch	,al		;CL is counter, CH is colour
	mov	di	,si		;DI points at "previous pixel"

copyrle_iXe8_loop:
	call	[lods_pixel]
	call	ipc_to_rgb_far
	; use two bits for blue, three for green, three for red
	and	al	,11100000b
	shr	ah	,8-3-2
	and	ah	,11100b
	or	al	,ah
	shr	dl	,8-2
	or	al	,dl
	cmp	al	,ch
	jne	copyrle_iXe8_done
	mov	di	,si		;update "previous pixel" pointer
	dec	cl
	jnz	copyrle_iXe8_loop

copyrle_iXe8_done:
	mov	si	,di		;go to "previous pixel" if necessary
	mov	al	,ch
	xor	ch	,ch		;get that colour out of CX!

	pop	dx			;get back max bytes to encode
        sub     dx      ,cx
	mov	cx	,dx
	pop	dx
	pop	di
	ret

copyrle_iXe8   endp




public	copyabs_i1e4
copyabs_i1e4   proc    near

	push   ax
	push   bx
        push   dx
	mov    dx      ,cx	       ;save maximum encode length

copyabs_i1e4_next_byte:

       lea     bx      ,xlati_1_to_4
       mov     al      ,ds:[si]
       shiftr  ax      ,3
       and     ax      ,01EH
       add     bx      ,ax
       mov     ax      ,[bx]
       stosw

       lea     bx      ,xlati_1_to_4
       lodsb
       and     ax      ,01EH
       add     bx      ,ax
       mov     ax      ,[bx]
       stosw			       ;store 4 pixels: each is 4 bits/pixel

       mov     al      ,ds:[si]
       inc     al		       ;if next 8 pixels are not all the same
       and     al      ,0FEH	       ;   i.e. al != 0   and al != FF
       loopne  copyabs_i1e4_next_byte  ;   then stay in absolute encoding

       sub     dx      ,cx	       ;compute number of bytes in absolute run
       shiftl  dx      ,3	       ;there were 8 pixels per byte
       mov     cx      ,dx             ;return that value in cx

       pop     dx
       pop     bx
       pop     ax
       ret

copyabs_i1e4   endp





public	copyabs_i1e8
copyabs_i1e8   proc    near

       push	ax
       push	bx
       push	dx
       mov	bx     ,cx

ci1e8_next_pixel:
       lodsb
       mov     dh      ,al
       rcl     dh      ,1
       sbb     al      ,al
       rcl     dh      ,1
       sbb     ah      ,ah
       stosw

       rcl     dh      ,1
       sbb     al      ,al
       rcl     dh      ,1
       sbb     ah      ,ah
       stosw

       rcl     dh      ,1
       sbb     al      ,al
       rcl     dh      ,1
       sbb     ah      ,ah
       stosw

       rcl     dh      ,1
       sbb     al      ,al
       rcl     dh      ,1
       sbb     ah      ,ah
       stosw

       mov     al      ,ds:[si]
       inc     al                      ;if next 8 pixels are not all the same
       and     al      ,0FEH	       ;   i.e. al != 0   and al != FF
       loopne  ci1e8_next_pixel        ;   then stay in absolute encoding

       sub     dx      ,cx	       ;compute number of bytes in absolute run
       shiftl  dx      ,3	       ;8 times as many destination pixels
       mov     cx      ,dx

       pop     dx
       pop     bx
       pop     ax
       ret

copyabs_i1e8   endp




public	copyabs_i8e4
copyabs_i8e4   proc    near

        push    ax
	push	dx
	mov	dx	,cx		;save maximum bytes to encode

	lodsb
	xlat	ss:[bx]
	and	al	,0FH
	mov	ah	,al
	lodsb
	xlat	ss:[bx]
	and	al	,0FH
	shiftl	ah	,4
	or	al	,ah
	stosb

        or      di      ,di
	jne	no_wrap4
        mov     ax      ,es
        add     ax      ,__NEXTSEG
        mov     es      ,ax
no_wrap4:

	lodsb
	xlat	ss:[bx]
	and	al	,0FH
        mov     ah      ,al
	lodsb
	xlat	ss:[bx]
	and	al	,0FH
        shiftl  ah      ,4
	or	al	,ah
        stosb

	or	di	,di
	jne	no_wrap13
	mov	ax	,es
	add	ax	,__NEXTSEG
	mov	es	,ax
no_wrap13:

	sub	cx	,5
	js	copyabs_i8e4_done
	je	copyabs_i8e4_1left

copyabs_i8e4_loop:

	lodsb
	xlat	ss:[bx]
	and	al	,0FH
        mov     ah      ,al
	lodsb
	xlat	ss:[bx]
	and	al	,0FH
        cmp     al      ,ah
	je	copyabs_i8e4_match
	shiftl	ah	,4
	or	al	,ah
	stosb

	or	di	,di
	jne	no_wrap14
	mov	ax	,es
	add	ax	,__NEXTSEG
	mov	es	,ax
no_wrap14:

	sub	cx	,2
	ja	copyabs_i8e4_loop
	js	copyabs_i8e4_done

copyabs_i8e4_1left:
	lodsb
	xlat	ss:[bx]
	and	al	,0FH
        shiftl  al      ,4
	stosb

	or	di	,di
	jne	no_wrap5
	mov	ax	,es
	add	ax	,__NEXTSEG
	mov	es	,ax
no_wrap5:
	dec	cx

copyabs_i8e4_done:
	inc	cx
	sub	dx	,cx
	mov	cx	,dx
	pop	dx
        pop     ax
	ret

copyabs_i8e4_match:
        sub     si      ,2
        jmp     copyabs_i8e4_done

copyabs_i8e4   endp




public	copyabs_i8e8
copyabs_i8e8   proc    near

	push	dx
	mov	dx	,cx

	lodsb
	xlat	ss:[bx]
        stosb
	lodsb
	xlat	ss:[bx]
        stosb

	or	di	,di
	jne	no_wrap7
	mov	ax	,es
	add	ax	,__NEXTSEG
	mov	es	,ax
no_wrap7:

	lodsb
        xlat    ss:[bx]
        stosb
	or	di	,di
	jne	no_wrap11
	mov	ax	,es
	add	ax	,__NEXTSEG
	mov	es	,ax
no_wrap11:

	sub	cx	,4
	js	copyabs_i8e8_fini
	je	copyabs_i8e8_endloop

copyabs_i8e8_loop:
	mov	al	,ds:[si]
	xlat	ss:[bx]
        mov     ah      ,al
	mov	al	,ds:[si + 1]
	xlat	ss:[bx]
        cmp     al      ,ah
	je	copyabs_i8e8_fini

	mov	al	,ah
	stosb
	or	di	,di
	jne	no_wrap8
	mov	ax	,es
	add	ax	,__NEXTSEG
	mov	es	,ax
no_wrap8:
	inc	si
	loop	copyabs_i8e8_loop

copyabs_i8e8_endloop:
	lodsb
	xlat	ss:[bx]
        stosb
	or	di	,di
	jne	no_wrap21
	mov	ax	,es
	add	ax	,__NEXTSEG
	mov	es	,ax
no_wrap21:

public	copyabs_i8e8_done
copyabs_i8e8_done:
	sub	dx	,cx
        mov     cx      ,dx             ;restore cx
	pop	dx
	ret

public	copyabs_i8e8_fini
copyabs_i8e8_fini:
	inc	cx
	sub	dx	,cx
	mov	cx	,dx
	pop	dx
	ret

copyabs_i8e8   endp




public	copyabs_iXe4
copyabs_iXe4   proc    near

        push    ax
	push	dx
	push	cx			;save maximum bytes to encode

	; NOTE: it is safe to load four pixels here, because the
	; caller has ensured that CX is not less than OR EQUAL to
	; MINIMUM_ABSOLUTE_LENGTH, i.e., 3. In other words, CX>=4.
	call	[lods_pixel]
	call	ipc_to_rgb_far
	cCall	match_to_palette_far,<ss,bx,16>
	and	al	,0FH
	.errnz	MAXIMUM_RLE_LENGTH_I8 AND (NOT 0FFh)
	mov	ch	,al		;CL is counter, CH is colour
	call	[lods_pixel]
	call	ipc_to_rgb_far
	cCall	match_to_palette_far,<ss,bx,16>
	and	al	,0FH
	shiftl	ch	,4
	or	al	,ch
	stosb

        or      di      ,di
	jne	caiX_no_wrap4
        mov     ax      ,es
        add     ax      ,__NEXTSEG
        mov     es      ,ax
caiX_no_wrap4:

	call	[lods_pixel]
	call	ipc_to_rgb_far
	cCall	match_to_palette_far,<ss,bx,16>
	and	al	,0FH
	.errnz	MAXIMUM_RLE_LENGTH_I8 AND (NOT 0FFh)
	mov	ch	,al		;CL is counter, CH is colour
	call	[lods_pixel]
	call	ipc_to_rgb_far
	cCall	match_to_palette_far,<ss,bx,16>
	and	al	,0FH
	shiftl	ch	,4
	or	al	,ch
	stosb

        or      di      ,di
	jne	caiX_no_wrap13
        mov     ax      ,es
        add     ax      ,__NEXTSEG
        mov     es      ,ax
caiX_no_wrap13:

	sub	cl	,5
	js	copyabs_iXe4_done
	je	copyabs_iXe4_1left

copyabs_iXe4_loop:

	call	[lods_pixel]
	call	ipc_to_rgb_far
	cCall	match_to_palette_far,<ss,bx,16>
	and	al	,0FH
	.errnz	MAXIMUM_RLE_LENGTH_I8 AND (NOT 0FFh)
	mov	ch	,al		;CL is counter, CH is colour
	call	[lods_pixel]
	call	ipc_to_rgb_far
	cCall	match_to_palette_far,<ss,bx,16>
	and	al	,0FH
        cmp     al      ,ch
	je	copyabs_iXe4_match
	shiftl	ch	,4
	or	al	,ch
	stosb

	or	di	,di
	jne	caiX_no_wrap14
	mov	ax	,es
	add	ax	,__NEXTSEG
	mov	es	,ax
caiX_no_wrap14:

	sub	cl	,2
	ja	copyabs_iXe4_loop
	js	copyabs_iXe4_done

copyabs_iXe4_1left:
	call	[lods_pixel]
	call	ipc_to_rgb_far
	cCall	match_to_palette_far,<ss,bx,16>
	and	al	,0FH
        shiftl  al      ,4
	stosb

	or	di	,di
	jne	caiX_no_wrap5
	mov	ax	,es
	add	ax	,__NEXTSEG
	mov	es	,ax
caiX_no_wrap5:
	dec	cl

copyabs_iXe4_done:
	xor	ch	,ch		;get that colour out of CX!
	inc	cl
	pop	dx			;get back max bytes to encode
	sub	dx	,cx
	mov	cx	,dx
	pop	dx
        pop     ax
	ret

copyabs_iXe4_match:
	; rewind two pixels
	mov	al	,[total_depth_bytes]
	xor	ah	,ah
	shl	ax	,1
        sub     si      ,ax
        jmp     short	copyabs_iXe4_done

copyabs_iXe4   endp




public	copyabs_iXe8
copyabs_iXe8   proc    near

	push	bx
	push	dx
	push	cx

	call	[lods_pixel]
	call	ipc_to_rgb_far
	; use two bits for blue, three for green, three for red
	and	al	,11100000b
	shr	ah	,8-3-2
	and	ah	,11100b
	or	al	,ah
	shr	dl	,8-2
	or	al	,dl
        stosb
	call	[lods_pixel]
	call	ipc_to_rgb_far
	; use two bits for blue, three for green, three for red
	and	al	,11100000b
	shr	ah	,8-3-2
	and	ah	,11100b
	or	al	,ah
	shr	dl	,8-2
	or	al	,dl
        stosb

	or	di	,di
	jne	caiX_no_wrap7
	mov	ax	,es
	add	ax	,__NEXTSEG
	mov	es	,ax
caiX_no_wrap7:

	call	[lods_pixel]
	call	ipc_to_rgb_far
	; use two bits for blue, three for green, three for red
	and	al	,11100000b
	shr	ah	,8-3-2
	and	ah	,11100b
	or	al	,ah
	shr	dl	,8-2
	or	al	,dl
        stosb
	or	di	,di
	jne	caiX_no_wrap11
	mov	ax	,es
	add	ax	,__NEXTSEG
	mov	es	,ax
caiX_no_wrap11:

	sub	cx	,4
	je	copyabs_iXe8_endloop
	jns	copyabs_iXe8_loop
	jmp	copyabs_iXe8_fini

copyabs_iXe8_loop:
	; if we're here, we're guaranteed that CH is zero (SF clear)
	mov	bx	,si		;save current pointer
	call	[lods_pixel]
	call	ipc_to_rgb_far
	; use two bits for blue, three for green, three for red
	and	al	,11100000b
	shr	ah	,8-3-2
	and	ah	,11100b
	or	al	,ah
	shr	dl	,8-2
	or	al	,dl
	mov	ch	,al		;CL is counter, CH is colour
	call	[lods_pixel]
	mov	si	,bx		;restore pointer
	call	ipc_to_rgb_far
	; use two bits for blue, three for green, three for red
	and	al	,11100000b
	shr	ah	,8-3-2
	and	ah	,11100b
	or	al	,ah
	shr	dl	,8-2
	or	al	,dl
	mov	ah	,ch
	; we can restore CH to zero, as noted above
	xor	ch	,ch		;get that colour out of CX!
        cmp     al      ,ah
	je	copyabs_iXe8_fini

	mov	al	,ah
	stosb
	or	di	,di
	jne	caiX_no_wrap8
	mov	ax	,es
	add	ax	,__NEXTSEG
	mov	es	,ax
caiX_no_wrap8:
	; move forward one pixel
	mov	al	,[total_depth_bytes]
	xor	ah	,ah
        add     si      ,ax
	loop	copyabs_iXe8_loop

copyabs_iXe8_endloop:
	call	[lods_pixel]
	call	ipc_to_rgb_far
	; use two bits for blue, three for green, three for red
	and	al	,11100000b
	shr	ah	,8-3-2
	and	ah	,11100b
	or	al	,ah
	shr	dl	,8-2
	or	al	,dl
        stosb
	or	di	,di
	jne	caiX_no_wrap21
	mov	ax	,es
	add	ax	,__NEXTSEG
	mov	es	,ax
caiX_no_wrap21:

public	copyabs_iXe8_done
copyabs_iXe8_done:
	pop	dx			;get back max bytes to encode
	sub	dx	,cx
        mov     cx      ,dx             ;restore cx
	pop	dx
	pop	bx
	ret

public	copyabs_iXe8_fini
copyabs_iXe8_fini:
	pop	dx			;get back max bytes to encode
	inc	cx
	sub	dx	,cx
	mov	cx	,dx
	pop	dx
	pop	bx
	ret

copyabs_iXe8   endp


public	encode_rle_table
encode_rle_table        label   word
dw	OFFSET	copyrle_i8e4
dw	OFFSET	copyrle_i8e8
dw	OFFSET	copyrle_i1e4
dw	OFFSET	copyrle_i1e8
dw	OFFSET	copyrle_iXe4
dw	OFFSET	copyrle_iXe8


public	encode_absolute_table
encode_absolute_table   label   word
dw	OFFSET	copyabs_i8e4
dw	OFFSET	copyabs_i8e8
dw	OFFSET	copyabs_i1e4
dw	OFFSET	copyabs_i1e8
dw	OFFSET	copyabs_iXe4
dw	OFFSET	copyabs_iXe8


; These functions translate a 24-bit colour in DX:AX
; to the appropriate external format (4-bit or 8-bit),
; based on our preset palette. Used only in the common
; encode_scanline_IX code.
; Returns in AL.
public	translate24_e4
translate24_e4	proc	near
	push	bx
	lea	bx,color_xlate
	cCall	match_to_palette_far,<ss,bx,16>
	pop	bx
	ret
translate24_e4	endp

public	translate24_e8
translate24_e8	proc	near
	; use two bits for blue, three for green, three for red
	and	al,11100000b
	shr	ah,8-3-2
	and	ah,11100b
	or	al,ah
	shr	dl,8-2
	or	al,dl
	ret
translate24_e8	endp


sEnd	DIMapSeg

END
