        page    ,132
;-----------------------------Module-Header-----------------------------;
; Module Name:  DISCREEN.ASM - draw a DIB directly to the display
;
;   This module contains the routines for drawing a 1/4/8/24 bit
;   uncompressed DIB directly to the screen.
;
;   it supports OPAQUE or TRANSPARENT mode
;
; Created: Mon 26-Mar-1990
; Author:  Todd Laney [ToddLa]
; Copyright (c) 1984-1990 Microsoft Corporation
;
; Modified: Thursday 12-Dec-1991 - Steve Glickman - Headland Technology
; Fixed parameter name conflict
;
; Exported Functions:   DibScreenBlt
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
; Restrictions:
;
;-----------------------------------------------------------------------;
        .286
	.xlist
        include cmacros.inc
incDrawMode=1
incDevice=1
	include	gdidefs.inc
	include	display.inc
	include	macros.mac
        .list

;----------------------------------------------------------------------------;
; define the equates and externAs here.                                      ;
;----------------------------------------------------------------------------;

        externA         __AHSHIFT
        externA         __AHINCR

        externA  __WinFlags             ;KERNEL.WinFlags
WF_PMODE        =    0001h
WF_CPU286       =    0002h
WF_CPU386       =    0004h
WF_CPU486       =    0008h

;----------------------------------------------------------------------------;

        externNP        RleBlt                  ; in RLD.ASM
        externFP        FarDeviceSelectDIB      ; in DIBSEL.ASM
        externFP        StretchBlt              ; in STRETCH.ASM
	externFP	rgb_to_ipc_seq		; in RGB2IPC.ASM
	externFP	sum_RGB_alt_far		; in ROBJECT.ASM

ifdef EXCLUSION
	externFP	exclude_far		; xeclude cursor from blt area
        externFP        unexclude_far           ; redraw cursor
endif

sBegin Data
        externB         enabled_flag
        externD         GetColor_addr           ; DeviceColorMatch vector

	externW		ColourFormat

	externW		raster_flags		; in BMC_MAIN.ASM

        externB         PaletteTranslationTable
        externB         bank_select_byte
sEnd

createSeg   _DIMAPS,DIMapSeg,word,public,code

sBegin DIMapSeg
	assumes cs,DIMapSeg
	assumes ds,Data
	assumes es,nothing

;
;   the following table is used to determine the init function
;
;        xx 0
;         |
;         +--------------   bpp       (00=1bpp, 01=4bpp, 10=8bpp, 11=24bpp)
;
InitProc        label   word    ; has the init routine addresses
        dw      init_1
        dw      init_4
        dw      init_8
        dw      init_24

;
;   the following table is used to determine the output function
;
;     x xx 0
;     | |
;     | +--------------   bpp       (00=1bpp, 01=4bpp, 10=8bpp, 11=24bpp)
;     |
;     +----------------   tran      (1=transparent mode)
;
DrawProc        label   word
        dw      copy_1
        dw      copy_4
        dw      copy_8
        dw      copy_24

        dw      copy_1t
        dw      copy_4t
        dw      copy_8t
        dw      copy_24t

;--------------------------Public-Routine-------------------------------;
;
; DibToDevice
;
;   draw a DIB bitmap directly to the display, takes weird params (like
;   the ones given to Get/SetDIBits()
;
;   all we do is fiddle with params and call DibBlt()
;
; Entry: per parameters.
;
; Returns:
;   AX = 1 if DIB drawn.
;
; Error Returns:
;   AX = 0  if dib not drawn.
;   AX = -1 if we want GDI to simulate
;
; Registers Destroyed: AX,BX,CX,DX,ES,flags.
;
; Registers Preserved: BP,DS,DI,SI.
;
;-----------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

cProc   DibToDevice,<FAR,PUBLIC,PASCAL,WIN>,<>
; Give DibToDevice parms unique names,
; so DibBlt doesn't accidentally use them
        parmD   DTD_lpPDevice	; pointer to device structure
        parmW   DTD_DstX	; Screen origin X coordinate
        parmW   DTD_DstY	; Screen origin Y coordinate
        parmW   DTD_StartScan	; start DIB scan
        parmW   DTD_NumScans	; number of scans
        parmD   DTD_lpClipRect
        parmD   DTD_lpDrawMode
        parmD   DTD_lpBits	; pointer to DI bits
        parmD   DTD_lpbi	; pointer to bitmap info block
        parmD   DTD_lpColorInfo	; GDI supplied value for color matching
cBegin
        les     bx,DTD_lpbi

        mov     cx,wptr es:[bx].biWidth    ; cx = biWidth
        mov     dx,wptr es:[bx].biHeight   ; dx = biHeight

; DstY = DstY + MapHeight - (StartScan + NumScans)

	mov	bx,DTD_DstY
	add	bx,dx
	sub	bx,DTD_StartScan
	sub	bx,DTD_NumScans

        xor     ax,ax
        farPtr  lpNULL,ax,ax

        arg     DTD_lpPDevice		; dest device
	arg	<DTD_DstX,bx>		; DstX, DstY
        arg     DTD_lpbi		; source device
	arg	DTD_lpBits
	arg	<ax,ax>			; SrcX, SrcY = (0,0)
	arg	<cx,DTD_NumScans>	; xExt, yExt
	arg	<00CCh,0020h>		; Rop = SRCCOPY
        arg     lpNULL			; brush = NULL
        arg     DTD_lpDrawMode		; draw mode
	arg	DTD_lpClipRect
        arg	DTD_lpColorInfo	; GDI supplied value for color matching

	cCall	DibBlt
cEnd

;--------------------------Private-Routine------------------------------;
; DibBlt  - blt a DIB to a device context
;
; Entry: per parameters.
;
; Returns:
;       AX = 1 if DIB drawn.
;
; Error Returns:
;       AX = 0  if dib not drawn.
;       AX = -1 if we want GDI to simulate
;
; Entry:
;
; Registers Preserved:
;       DS,SI,DI,BP
; Registers Destroyed:
;       AX,BX,CX,DX,ES,FLAGS
;
; History:
;       11/1 -by-  Todd Laney [ToddLa]
;       Created.
;-----------------------------------------------------------------------;
        assumes ds,Data
        assumes es,nothing

cProc	DibBlt,<NEAR,PUBLIC,PASCAL>,<ds,si,di>

        parmD   lpPDevice               ; pointer to device structure
        parmW   DstX                    ; Screen origin X coordinate
        parmW   DstY                    ; Screen origin Y coordinate
        parmD   lpbi                    ; pointer to bitmap info block
        parmD   lpBits                  ; pointer to DI bits
	parmW	SrcX			; dib origin X coordinate
	parmW	SrcY			; dib origin Y coordinate
        parmW   xExt
        parmW   yExt
	parmD	Rop
	parmD	lpBrush
	parmD	lpDrawMode
	parmD	lpClipRect
        parmD   lpColorInfo		; GDI supplied value for color matching

        localD  bk_color                ; background color for TRANSPARENT mode

        localB  fbFlags                 ; flag bytes

MAP_BPP         equ     0000000110b     ; bpp field
MAP_TRANSPARENT equ     0000001000b     ; transparent blt
MAP_TRANSLATE   equ     0000010000b     ; translate table is not 1:1
MAP_IS_HUGE     equ     0000100000b     ; source maps spans segments
DEV_PALETTE	equ	0001000000b	; device uses a palette

	localW	MapWidth		; width of map in pels
	localW	MapHeight		; height of map in scans
	localW	MapBitCount		; no of bits per map pel
	localW	next_map_scan		; offset to next map scan

	localD	lp_screen		; pointer to start byte of screen

        localW  next_screen_scan        ; offset to next screen scan

        localV  color_xlate,1024        ; the local color xlate table (256dword)

        localD  DeviceColorMatch        ; GDI color match routine

	localW	colour_format		; copy of this on stack

        localW  draw_proc               ; routine to call to blt a byte/scan
	localW	SourceBytesPerScanBlt	; no of bytes in map for 1 scan blt
	localB	bank_select		; track the current bank of display

	localW	scans_copied		; return value
cBegin
        cld

        xor     al,al                   ; reset the flag byte
        mov     fbFlags,al

	; get the ColourFormat from DS before we point the segreg elsewhere...
	mov	ax,[ColourFormat]
	mov	colour_format,ax

        cmp     Rop.hi, 00CCh           ; is the ROP SRCCOPY?
        jne     let_gdi_do_it           ; not get out'a here

	mov	al,enabled_flag		; error if screen is not enabled
	or	al,al
        jnz     device_is_enabled
        jmp     parameter_error

let_gdi_do_it:
        mov     ax,-1
        jmp     discreen_ret            ; error return

device_is_enabled:
	test	[raster_flags],RC_PALETTE
	jz	@F
	or	[fbFlags],DEV_PALETTE

@@:     lds     si,lpbi                 ; DS:SI --> BITMAPINFO
        assumes ds,nothing

;----------------------------------------------------------------------------;
; is the DIB a RLE DIB, if so call rle_to_screen
;----------------------------------------------------------------------------;
        mov     ax,wptr [si].biCompression
        or      ax,ax
        jz      not_encoded
        cmp     ax,BI_RLE4
        ja      let_gdi_do_it

        errnz   BI_RGB-0
        errnz   BI_RLE8-1
        errnz   BI_RLE4-2

        arg     lpPDevice               ; pointer to device structure
        arg     DstX                    ; Screen origin X coordinate
        arg     DstY                    ; Screen origin Y coordinate
        arg     lpBits                  ; pointer to DI bits
        arg     lpbi                    ; pointer to bitmap info block
        arg     lpClipRect              ; clipping rectangle

        cCall   RleBlt
        jmp     discreen_ret

not_encoded:

;----------------------------------------------------------------------------;
; grab info from the draw mode, and set/clear MAP_TRANSPARENT in fbFlags
;----------------------------------------------------------------------------;
        les     di,lpDrawMode

        cmp     bptr es:[di].bkMode,3       ; NEWTRANSPARENT mode?
        jne     discreen_not_transparent

        mov     bx,es:[di].bkColor.lo       ; get BkColor
        mov     cx,es:[di].bkColor.hi
        or      dl,dl                       ; are we in background mode?
        jz      discreen_not_background     ; no, nothing to do

        smov    es,DataBASE                 ; yes, we must pass BkColor
        assumes es,Data                     ; through PaletteTranslateTable
        xor     bh,bh
        mov     bl,PaletteTranslationTable[bx]
        assumes es,nothing

discreen_not_background:
        mov     bk_color.lo,bx
        mov     bk_color.hi,cx

        or      fbFlags, MAP_TRANSPARENT    ; set flag

discreen_not_transparent:

;----------------------------------------------------------------------------;
; do a few validations at this point:
;               .  pointer to bits must not be NULL
;               .  destination must be a device and not a bitmap
;               .  calculate the actual blt rectangle on the screen, this
;                  has to be clipped against the clip rectangle and can't
;                  be NULL
; currently:
;       DS:SI --> BITMAPINFO
;----------------------------------------------------------------------------;

; test for souce pointer to be non NULL

        mov     cx,lpBits.sel           ; NULL implies error
        jcxz    parameter_error         ; can't support NULL pointer

        les     di,lpPDevice            ; get the pdevice structure
	assumes	es,nothing

; test for target to be a screen

	mov	cx,es:[di].bmType	; test the type of the structure
        jcxz    let_gdi_do_it           ; can't support memory bitmaps here

        mov     ax,word ptr es:[di].bmPlanes
	cmp	ax,colour_format	; our screen format?
        jnz     parameter_error         ; don't support this format

; save screen-relevant parameters

	mov	ax,wptr	es:[di].bmBits[0]
        mov     lp_screen.off,ax
	mov	ax,wptr	es:[di].bmBits[2]
        mov     lp_screen.sel,ax

	mov	ax,es:[di].bmWidthBytes
	mov	next_screen_scan,ax

; calculate the exclusion area

	mov	ax,wptr [si].biWidth	; the horixontal extent of map
	mov	MapWidth,ax		; save it
	mov	ax,wptr [si].biHeight	; the height of the map
	mov	MapHeight,ax		; save it
	mov	ax,[si].biBitCount	; get the bits per pel
	mov	MapBitCount,ax		; save it

;----------------------------------------------------------------------------;
; validate the bits/pel count at this point. It has to be 1/4/8 or 24        ;
;----------------------------------------------------------------------------;
	xor	cx,cx			; will build up the serial no
	mov	scans_copied,cx		; while we're at it, zero our retval
	IRP	x,<1,4,8,24>
	cmp	ax,x
	je	bit_count_ok		; valid count
	inc	cl
        ENDM

parameter_error:
	xor	ax,ax
        jmp     discreen_ret            ; error return

bit_count_ok:
        shl     cl,1
        or      fbFlags,cl              ; set bpp in the flags

        errnz   MAP_BPP-0110b

;----------------------------------------------------------------------------;

	cmp	[si].biPlanes,1		; no of color planes has to be 1
        jnz     parameter_error         ; its an error

        call    clip_dib                ; handle all cliping
        jc      parameter_error         ; nothing to draw

;----------------------------------------------------------------------------;
; exclude the cursor from the blt area of the screen.                        ;
;----------------------------------------------------------------------------;

ifdef EXCLUSION
        mov     cx,DstX                 ; X1
        mov     dx,DstY                 ; Y1
        mov     si,cx
        mov     di,dx
        add     si,xExt                 ; X2
        add     di,yExt                 ; Y2
	call	exclude_far		; exclude cursor from blt area
endif

;----------------------------------------------------------------------------;
; calculate the offset to the next scan in the map (scans there are DWORD
; alligned ).
;
; assume that the offset to the next scan fits in  a word, ignore DX
;----------------------------------------------------------------------------;

	mov	ax,MapWidth		; get the no of pels in a scan
	mul	MapBitCount		; bits per pel
	add	ax,31
        and     ax,not 31               ; ax has multiple of 32 bits
	shiftr	ax,3			; get the no of bytes
	mov	next_map_scan,ax	; save it

;----------------------------------------------------------------------------;
; we shall also calculate the no of byte in the source map that correspond to
; xExt bits, as we shall use this information to test whther we cross a segm-
; -ent on the source during the blt of xExt pels on a scan.
;----------------------------------------------------------------------------;
        mov     ax,SrcX                 ; get the X offset of the map
	mul	MapBitCount
	mov	bx,ax
        and     bx,0111b                ; align to a byte

	mov	ax,xExt			; get the no of bits in 1 scan blt
	mul	MapBitCount		; multiply be no of bits per pel
        add     ax,bx                   ; handle fist byte
        add     ax,7                    ; handle last byte
	shiftr	ax,3			; get the number of bytes
	mov	SourceBytesPerScanBlt,ax; save it for use later

;----------------------------------------------------------------------------;
; calculate the offset to the start byte in the map and the screen and the
; position of the first pel in the screen byte.
;----------------------------------------------------------------------------;
        mov     ax,SrcX                 ; get the X offset of the map
	mul	MapBitCount
	mov	bx,ax
        shiftr  bx,3                    ; number of bytes into scan line

        mov     ax,SrcY                 ; get the Y origin of the map
	mul	next_map_scan		; the result is in DX:AX

        xor     cx,cx
	add	ax,bx
        adc     dx,cx
        add     ax,lpBits.off
        adc     dx,cx

        mov     cx,__AHSHIFT
        shl     dx,cl
        add     lpBits.sel,dx           ; update the segment part of ptr
        mov     lpBits.off,ax           ; update the offset

; lpBits now points to the first byte of the map in the blt area

;----------------------------------------------------------------------------;
;  the starting scan no might not have crossed a segment but the blt area
;  might still cross a segment, test for that.
;----------------------------------------------------------------------------;
if 0; not used mabey in the future?
	mov	ax,yExt			; get the Y ext of the blt
	mul	next_map_scan		; bytes per scan on the map
        add     ax,lpBits.off           ; add the first byte offset
        adc     dx,0                    ; do a 32 bit addition
	jz	blt_area_in_1_segment
	or	fbFlags,MAP_IS_HUGE	; will have to test for segment update
blt_area_in_1_segment:
endif

;----------------------------------------------------------------------------;
; now calculate the address of the start byte in the screen blt area.
;----------------------------------------------------------------------------;
        mov     ax,DstY                 ; get the Y origin (top scan)
	add	ax,yExt			; start from bottom
	dec	ax
	mul	next_screen_scan	; no of bytes in a scan
					; dx:ax = bank:offset
	mov	si,dx			; save these so we can reuse DX:AX
	mov	bx,ax

	mov	cx,colour_format	;CH := bits per pixel
	shr	cx,0Bh			; Shift right 8+3 to get bytes in CL
	mov	ax,DstX
	mul	cx			;DX:AX := X origin in bytes

	add	ax,bx
	adc	dx,si
        add     ax,lp_screen.off        ; this is the start offset
	adc	dl,dh
	mov	bank_select,dl

        mov     lp_screen.off,ax        ; save it
        SET_BANK                        ; set bank to dl

; lp_screen now has the pointer to the first byte in the screen blt area

;----------------------------------------------------------------------------;
; bias next_screen_scan by xExt, so we can update pointers from the end
; of the scan not the begining.
;----------------------------------------------------------------------------;
;;;;;;;;mov     ax,xExt
;;;;;;;;add     next_screen_scan,ax

        mov     ax,SourceBytesPerScanBlt
        sub     next_map_scan,ax

;----------------------------------------------------------------------------;
; now get the address of the full and partial byte proces that we will be
; using depending on the bits per pel.
;----------------------------------------------------------------------------;
        lds     si,lpbi                 ; DS:SI points to the info block

        mov     ax,wptr [si].biClrUsed
        or      ax,ax
        jnz     copy_color_table

        inc     ax
        mov     cl,bptr [si].biBitCount
        cmp     cl,24
        je      no_color_table
        shl     ax,cl

copy_color_table:
        mov     cx,ax
        add     si,wptr [si].biSize     ; DS:SI has the color table
        call    create_color_table      ; translates the color into indices

no_color_table:
        xor     bh,bh                   ; get the bits per pel serial num
        mov     bl,fbFlags
        and     bl,001110b              ; make into a table index
        mov     ax,DrawProc[bx]         ; get draw routine
        mov     draw_proc,ax            ; ..and save it

        and     bl,MAP_BPP              ; init routines only care about bpp
        jmp     InitProc[bx]            ; get the appropriate init procs addr

        errnz   <MAP_BPP         - 0000000110b>
        errnz   <MAP_TRANSPARENT - 0000001000b>
        errnz   <MAP_TRANSLATE   - 0000010000b>

;----------------------------------------------------------------------------;
;  the format specific initialization routines follow here.                  ;
;----------------------------------------------------------------------------;

;----------------------------------------------------------------------------;
;----------------------------------------------------------------------------;
init_1:
	jmp	init_done

;----------------------------------------------------------------------------;
;----------------------------------------------------------------------------;
init_4:
	jmp	init_done

;----------------------------------------------------------------------------;
;----------------------------------------------------------------------------;
init_8:

	; If our native format is NOT 8-bit, then this isn't a special case!
	cmp	byte ptr colour_format[1],8	; 8 bits per pixel
	jne	init_done

	; if scanlines don't fit evenly into banks (i.e. not powers of two),
	; this also isn't a special case...
	mov	dx,1
	xor	ax,ax
	div	[next_screen_scan]
	test	dx,dx	; check remainder
	jnz	init_done

;----------------------------------------------------------------------------;
; If we are on a 386, use fast special code.  We will only do this if the
; DIB matches the native format of the screen (ie 8 bpp) and transparency is
; not active
;----------------------------------------------------------------------------;
        mov     bl,fbFlags
        mov     ax,__WinFlags

        test    ax,WF_CPU286
        jnz     special_case286
        errn$   special_case386

special_case386:
        test    bl,MAP_TRANSPARENT
        jnz     special_case286

        call    diScreen386
        jmp     discreen_exit

special_case286:
        test    bl,MAP_TRANSPARENT+MAP_TRANSLATE
        jnz     cant_special_case
        mov     draw_proc,offset copy_8i
        errn$   cant_special_case

cant_special_case:
        jmp     init_done

;----------------------------------------------------------------------------;
;----------------------------------------------------------------------------;
init_24:
        mov     ax,DataBASE
        mov     es,ax
        assumes es,Data
        mov     ax,es:GetColor_addr.off
        mov     dx,es:GetColor_addr.sel
        mov     DeviceColorMatch.off,ax
        mov     DeviceColorMatch.sel,dx
        assumes es,nothing

        jmp     init_done

;----------------------------------------------------------------------------;
; the color convert routine reads a color triplet from the map specific color;
; table - converts it into an index and stores it in a table on the stack. It;
; does the conversion for the count of triplets passed in CX                 ;
;----------------------------------------------------------------------------;

create_color_table	proc	near

; CX     ---  count of triplets to converts
; DS:SI  ---  place where the color table is stored

        push    ss
        pop     es
        lea     di,color_xlate          ; index into xlate table on stack

	test	[fbFlags],DEV_PALETTE
	jz	colour_table_nopalette

        xor     bl,bl                   ; BL will range from 0-255
        xor     dx,dx                   ; DX is ident mapping error
xlate_next_color:
        lodsw                           ; get palette index from GDI
        stosw                           ; store it on the stack
        sub     al,bl                   ; test for a 1<-->1 translate
        add     dx,ax                   ; accumulate the error
	mov	ax,0FF00h		; set upper word to indicate palette idx
	stosw
        inc     bl
        loop    xlate_next_color

        or      dx,dx
        jz      create_color_table_exit

        or      fbFlags,MAP_TRANSLATE   ; not the identity table, set the bit
        jmp     create_color_table_exit

colour_table_nopalette:
	mov	bx,320h	; BL:=32 == #bytes we want
			; BH:=11b --> 4 bytes input, need to swap red and blue
	call	rgb_to_ipc_seq
	
create_color_table_exit:
	ret

create_color_table	endp

init_done:

;----------------------------------------------------------------------------;
;----------------------------------------------------------------------------;
        assumes ds,nothing
	assumes	es,nothing

        lds     si,lpBits               ; the strting point of the bits
        les     di,lp_screen            ; the start on the screen
        lea     bx,color_xlate          ; address of the xlate table

blt_next_scan:
	mov	cx,xExt			; the no of pels to blt
	push	di
        call    draw_proc               ; do the blt of a scan
	inc	scans_copied
	pop	di

	; in case the bank rolled over during that scanline
	mov	dl,bank_select
        SET_BANK

        dec     yExt                    ; blt all the scans
        jz      blt_done

	sub	di,next_screen_scan	; we map top to bottom
	jnc	new_scan_in_bank

        dec     bank_select
	mov	dl,bank_select
        SET_BANK

new_scan_in_bank:
	add	si,next_map_scan	; update to the next scan
        jnc     blt_next_scan           ; the new scan is in segment

	mov	ax,ds			; get current DS
        add     ax,__AHINCR             ; update to the next segment
	mov	ds,ax
        jmp     blt_next_scan

blt_done:
        jmp     discreen_exit           ; return success to the caller

; Move to next bank WITHOUT updating "bank_select" on stack.
; This is to be used if we cross a boundary in the middle of a scanline.
; State will be restored after scanline subroutine returns.
next_bank	proc near
	push	ds
	push	dx
	mov	dx,DataBASE
	mov	ds,dx
	assumes	ds,Data
	mov	dl,[bank_select_byte]
	inc	dl
	SET_BANK
	pop	dx
	pop	ds
	assumes	ds,nothing
	ret
next_bank	endp

;----------------------------------------------------------------------------;
;                       copy_1
;                       ------
;  handles the blt of a scan or a part of it for 1 bits per pixel case
;
;  Entry:
;               DS:SI     --      current byte in the map
;               ES:DI     --      current byte in the screen
;               SS:BX     --      address of color_xlate table
;                  CX     --      number of pels to convert
;
;  Returns:
;               DS:SI,ES:DI --    next bytes in respective areas
;                           --    unchanged
;               BX,DX,AL,CX --    destroyed
;----------------------------------------------------------------------------;

copy_1  proc    near

	; at this point, "color_xlate" points at the physical background colour
	; and "color_xlate+4" points at the physical foreground colour
	mov	ax, color_xlate[0].lo
	mov	dx, color_xlate[0].hi
	; get fg XOR bg
	xor	ax, color_xlate[4].lo
	xor	dx, color_xlate[4].hi
	; and stash it at "color_xlate+8" since we have plenty of room
	mov	color_xlate[8].lo, ax
	mov	color_xlate[8].hi, dx

	; use both nibbles of BL as counters
	mov	bl,bptr colour_format[1] ; BL := bits per pixel
	shl	bl, 1	; BYTES per pixel in upper nibble

copy_1_next_byte:
	or	bl, 8	; lower nibble
	lodsb
	mov	bh, al

; Note:	this could be made more efficient (fewer insts, no stack spillage)
;       with 386 registers - should look into making it modal
copy_1_next_pixel:
	shl	bh, 1
	sbb	ax, ax
	cwd
	and	ax, color_xlate[8].lo	;if 1 select fg XOR bg
	xor	ax, color_xlate[0].lo	;if 0 select bg

        stosb
	test	di,di
	jnz	@F
	call	next_bank

@@:	cmp	bl, 20h			;byte counter (upper nibble) >= 2?
	jb	copy_1_dec_counter
	mov	al,ah
	stosb
	test	di,di
	jnz	@F
	call	next_bank

@@:	cmp	bl, 30h			;byte counter (upper nibble) >= 3?
	jb	copy_1_dec_counter
	mov	ax,dx
	stosb
	test	di,di
	jnz	@F
	call	next_bank

@@:	cmp	bl, 40h			;byte counter (upper nibble) >= 4?
	jb	copy_1_dec_counter
	mov	al,ah
	stosb
	test	di,di
	jnz	copy_1_dec_counter
	call	next_bank

copy_1_dec_counter:
	dec	bl
	test	bl, 0Fh			;is lower nibble zero?
	loopnz	copy_1_next_pixel

	jcxz	@F
	jmp	copy_1_next_byte

@@:	ret

;----------------------------------------------------------------------------;
;   copy_1 with transparency
;----------------------------------------------------------------------------;
copy_1t:
        mov     al,bk_color
        mov     ah,0FFh                 ; mask = FF
        mov     bx,wptr color_xlate     ; bl=fg color, bh=bk color

        cmp     al,bh                   ; is bk color transp?
        je      @f                      ; yes
        cmp     al,bl                   ; is bk color transp?
        ;jne     copy_1                  ; no copy normaly
        not     ah                      ; yes invert mask
        xchg    bl,bh
@@:     mov     bh,ah                   ; bl = color, bh = mask

        call    get_byte                ; al = first byte
        xor     al,bh                   ; invert byte
        mov     dh,al                   ; dh = current byte
        mov     dl,01h                  ; dl = alignment bit

        mov     ah,cl                   ; save CX
        mov     cl,bptr SrcX            ; align first byte
        and     cl,0111b
        shl     dx,cl
        mov     cl,ah                   ; restore CX

copy_1t_loop:
        shl     dh,1                    ; get the next pel into carry
        jnc     @f
        mov     es:[di],bl              ; write pixel
@@:     inc     di
        dec     cx
        jz      copy_1t_done            ; another pel?

        rol     dl,1                    ; another bit in current byte?
        jnc     copy_1t_loop

        lodsb                           ; get next byte into al
        xor     al,bh
        mov     dh,al                   ; place in dh for loop
        or      si,si                   ; did we wrap a seg?
        jnz     copy_1t_loop            ; ..no go do some more

        mov     ax,ds                   ; ..yes increment selector
        add     ax,__AHINCR             ; ..and loop
        mov     ds,ax
        jmp     copy_1t_loop

copy_1t_done:
        ret

copy_1  endp

;----------------------------------------------------------------------------;
;                       copy_4
;                       ------
;  handles the blt of a scan or a part of it for 4 bits per pixel case
;
;  Entry:
;               DS:SI     --      current byte in the map
;               ES:DI     --      current byte in the screen
;                  BX     --      address of color_xlate table on stack
;                  CX     --      number of pels to convert
;
;  Returns:
;               DS:SI,ES:DI --    next bytes in respective areas
;                        BX --    unchanged
;                  AL,CX,DX --    destroyed
;----------------------------------------------------------------------------;

copy_4  proc    near

	mov	dx,[colour_format]
	shr	dh,3			; output bytes per pixel in DH

	push	bp
        test    SrcX,1                  ; if sign is odd then do low
        je      copy_4_loop             ;    nibble of byte
        call    get_byte                ; process first byte separately

copy_4_lownib:
	and	al,0fh			; get the lower 4 bits
	shiftl	al,2			; index the four-byte palette table
	mov	bp,cx			; save count
	mov	cl,dh			; refresh bytes per pixel
	mov	ch,al			; save the index
copy_4_lownib_xlat:
	xlat	ss:[bx]			; get the mapping index
	stosb
	test	di,di			; wrapped end of bank?
	jnz	@F
	call	next_bank
@@:	inc	ch			; next byte in palette table
	dec	cl			; any bytes left to write?
	mov	al,ch
	jnz	copy_4_lownib_xlat
	mov	cx,bp			; get back count
        dec     cx                      ; one more pel done
        jz      copy_4_done

copy_4_loop:
        lodsb                           ; get byte
        or      si,si                   ; check for wrap
        jz      copy_4_wrap

copy_4_wrap_resume:
	mov	ah,al			; save the byte
	and	al,0f0h			; get the upper 4 bits
	shiftr	al,2			; get the high nibble into middle pos
	mov	bp,cx			; save count
	mov	cl,dh			; refresh bytes per pixel
	mov	ch,al			; save the index
copy_4_highnib_xlat:
	xlat	ss:[bx]			; get the mapping index
	stosb
	test	di,di			; wrapped end of bank?
	jnz	@F
	call	next_bank
@@:	inc	ch			; next byte in palette table
	dec	cl			; any bytes left to write?
	mov	al,ch
	jnz	copy_4_highnib_xlat
	mov	cx,bp			; get back count
        mov     al,ah                   ; get back pel
        loop    copy_4_lownib           ; process all the remaining pels

copy_4_done:
	pop	bp
	ret

copy_4_wrap:
        mov     bp,ds
        add     bp,__AHINCR
        mov     ds,bp
        jmp     copy_4_wrap_resume

;----------------------------------------------------------------------------;
;   copy_4 with transparency
;----------------------------------------------------------------------------;
copy_4t:
        mov     dl,bk_color

        test    SrcX,1                  ; if sign is odd then do low
        je      copy_4t_loop            ;    nibble of byte
        call    get_byte                ; process first byte separately

copy_4t_lownib:
	and	al,0fh			; get the lower 4 bits
        xlat    ss:[bx]                 ; get the mapping index
        cmp     al,dl
        je      @f
        mov     es:[di],al
@@:     inc     di
        dec     cx                      ; one more pel done
        jz      copy_4t_done

copy_4t_loop:
        lodsb                           ; get byte
        or      si,si                   ; check for wrap
        jz      copy_4t_wrap

copy_4t_wrap_resume:
	mov	ah,al			; save the byte
	shiftr	al,4			; get the high nibble into low pos
        xlat    ss:[bx]                 ; get the mapping index
        cmp     al,dl
        je      @f
        mov     es:[di],al
@@:     inc     di
        mov     al,ah                   ; get back pel
        loop    copy_4t_lownib          ; process all the remaining pels

copy_4t_done:
	ret

copy_4t_wrap:
        mov     si,ds
        add     si,__AHINCR
        mov     ds,si
        xor     si,si
        jmp     copy_4t_wrap_resume

copy_4  endp

;----------------------------------------------------------------------------;
;                       copy_8
;                       ------
;  handles the blt of a scan or a part of it for 8 bits per pixel case
;
;  Entry:
;               DS:SI     --      current byte in the map
;               ES:DI     --      current byte in the screen
;                  BX     --      address of color_xlate table on stack
;                  CX     --      number of pels to convert
;
;  Returns:
;               DS:SI,ES:DI --    next bytes in respective areas
;                        BX --    unchanged
;                  AL,CX,DX --    destroyed
;----------------------------------------------------------------------------;

copy_8  proc    near

;----------------------------------------------------------------------------;
;   copy_8 with a translate table, and without transparency
;----------------------------------------------------------------------------;
        mov     ax, si              ; check for a segment cross in the source
        add     ax, cx
        sbb     dx, dx              ; if C DX=FFFF, NC DX=0000
        and     dx, ax              ; DX amount to copy later
        sub     cx, dx              ; CX contains amount to copy now

	push	dx		    ; put "amount to copy later" on the stack
	mov	dl,bptr colour_format[1] ; DL := bits per pixel
	shr	dl,3		    ; DL := bytes per pixel

copy_8x_loop:
	lodsb
	xor	ah,ah
	xchg	ax,si
	mov	dh,dl		    ; get #bytes into counter
	shl	si,2		    ; index into DWORD table
	add	si,bx
copy_8x_byte:
	movs	byte ptr es:[di],ss:[si]
	test	di,di		    ; wrapped bank?
	jnz	@F
	call	next_bank
@@:	dec	dh
	jnz	copy_8x_byte
	mov	si,ax
	loop	copy_8x_loop

	pop	cx		    ; get back "amount to copy later"
        or      si,si
        jz      copy_8x_wrap
        ret

copy_8x_wrap:
        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax

        jcxz	@F
	push	cx		    ; fix the stack to go through loop again
	jmp	copy_8x_loop

@@:	ret

;----------------------------------------------------------------------------;
;   copy_8 without a translate table, and without transparency
;----------------------------------------------------------------------------;
copy_8i:
        mov     ax, si              ; check for a segment cross in the source
        add     ax, cx
        sbb     dx, dx              ; if C DX=FFFF, NC DX=0000
        and     dx, ax              ; DX amount to copy later
        sub     cx, dx              ; CX contains amount to copy now

copy_8i_loop:
        REPMOVSB
        or      si,si
        jz      copy_8i_wrap
        ret

copy_8i_wrap:
        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax

        or      cx,dx               ; cx <-- dx, note cx==0!
        jnz     copy_8i_loop
        ret

;----------------------------------------------------------------------------;
;   copy_8 with a translate table, and with transparency
;----------------------------------------------------------------------------;
copy_8t:
        mov     ax, si              ; check for a segment cross in the source
        add     ax, cx
        sbb     dx, dx              ; if C DX=FFFF, NC DX=0000
        and     dx, ax              ; DX amount to copy later
        sub     cx, dx              ; CX contains amount to copy now

        mov     ah,bk_color         ; get BkColor for compares

copy_8t_loop:
        lodsb                       ; get the next source byte
        xlat    ss:[bx]             ; get the mapping index value
        cmp     al,ah               ; compare to bkColor
        je      @f
        mov     es:[di],al          ; xfer it to the screen
@@:     inc     di
        loop    copy_8t_loop        ; repeat till all bytes processed

        or      si,si
        jz      copy_8t_wrap
        ret

copy_8t_wrap:
        mov     si,ds
        add     si,__AHINCR
        mov     ds,si
        xor     si,si

        or      cx,dx               ; cx <-- dx, note cx==0!
        jnz     copy_8t_loop
        ret

copy_8  endp

;----------------------------------------------------------------------------;
;                       copy_24
;                       -------
;  handles the blt of a scan or a part of it for 24 bits per pixel case
;
;  Entry:
;               DS:SI     --      current byte in the map
;               ES:DI     --      current byte in the screen
;                  CX     --      number of pels to convert
;
;  Returns:
;               DS:SI,ES:DI --    next bytes in respective areas
;                           --    unchanged
;               DX,AL,BX,CX --    destroyed
;----------------------------------------------------------------------------;

copy_24 proc    near

copy_24t:
	mov	bl,bptr colour_format[1]; BL = bits per pixel
	shr	bl,3			; BL = bytes per pixel

c24_loop:
        xor     dh,dh

	cmp	si,0fffdh
        jb      c24_get_rgb

        call    get_byte                ; get the blue pel
	mov	dl,al			; have blue in dl
        call    get_byte                ; get green
	mov	ah,al			; have it in ah
        call    get_byte                ; get red in al
        jmp     c24_compare

c24_get_rgb:
        lodsw                           ; al=Blue, ah=Green
        mov     dl,al
        lodsb                           ; al=Red, ah=Green, dl=Blue

c24_compare:

	test	fbFlags, DEV_PALETTE
	jz	@F
        xchg    dl,al			; swap Red/Blue for DeviceColorMatch
        save    <es,cx>
        cCall   DeviceColorMatch, <dx,ax, lpColorInfo>
	jmp	c24_checktrans

@@:	; this situation is a bit more complicated than DeviceBitmapBits
	; so we can't use the more efficient rgb_to_ipc_seq... Reasons:
	; * In DeviceBitmapBits, the input (DIB) can cross a segment
	;   boundary, but the output (device bitmap) cannot; here both
	;   can cross a segment boundary, because we're writing directly
	;   to the firmware-provided framebuffer.
	; * Here, we may additionally have to deal with transparency.
	call	sum_RGB_alt_far

c24_checktrans:
        test    fbFlags, MAP_TRANSPARENT
	mov	bh,bl			; initialize bpp counter
        jnz     c24_transparent_store

c24noconvert:
        stosb

	test	di,di
	jnz	@F
	call	next_bank
@@:
	dec	bh
	jz	c24_next
	mov	al,ah
	stosb

	test	di,di
	jnz	@F
	call	next_bank
@@:
	dec	bh
	jz	c24_next
	mov	al,dl
	stosb

	test	di,di
	jnz	@F
	call	next_bank
@@:
	dec	bh
	jz	c24_next
	mov	al,dh
	stosb

	test	di,di
	jnz	@F
	call	next_bank
@@:
	dec	bh
c24_next:
        loop    c24_loop

copy_24_exit:
        ret

c24_transparent_store:
        cmp     ax,bk_color.lo
        jne	c24noconvert
	cmp	dx,bk_color.hi
	jne	c24noconvert
	; right, this pixel is the background colour, so skip it
	xor	bh,bh			; reset bpp counter
	add	di,bx			; skip bpp bytes
	jnc	@F
	call	next_bank		; increment bank if necessary
@@:	jmp     c24_next

copy_24 endp

;----------------------------------------------------------------------------;
;----------------------------------------------------------------------------;

get_byte proc    near
	lodsb				; get the current byte
	or	si,si			; si wraps to 0 ?
        jz      get_byte_wrap           ; no, we are in same segment
        ret

get_byte_wrap:
        mov     si,ds                   ; get current segment
        add     si,__AHINCR             ; go to the next segment
        mov     ds,si                   ; update segment
        xor     si,si
	ret				; get back

get_byte endp

;----------------------------------------------------------------------------;
; return back with success code
;----------------------------------------------------------------------------;
discreen_exit:

ifdef	EXCLUSION
	call	unexclude_far		; re-draw the cursor
endif
        mov     ax,scans_copied         ; success code

discreen_ret:

cEnd

;--------------------------Private-Routine------------------------------;
; clip_dib
;
;   clips the DibToDevice params to the GDI passed clipping rectangle
;
; Entry:
;       es:di ==> PDevice
;       ds:si ==> BITMAPINFO
;	ss:bp ==> DibBlt frame
;
;           DstX
;           DstY
;           xExt
;           yExt
;           SrcX
;           SrcY
; Returns:
;       C   - nothing to draw
;
;	NC  - following stack variables changed:
;
;           DstX
;           DstY
;           xExt
;           yExt
;           SrcX
;           SrcY
;
; Registers Preserved:
;       BP
; Registers Destroyed:
;       AX,BX,CX,DX,ES,DS,FLAGS
;
; History:
;       11/1 -by-  Todd Laney [ToddLa]
;       Created.
;-----------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

clip_dib_error:
        stc
        ret

clip_dib proc near

        lds     bx,lpClipRect
        mov     ax,ds
        or      ax,bx
        jz      clip_dib_error

;----------------------------------------------------------------------------;
;
;   fix a bogus cliprect, by doing a intersection with the bitmap/display
;   surface, we should not need this if GDI is always passing valid rects
;
;----------------------------------------------------------------------------;
;;;;;;;;les     di,lpPDevice

        mov     ax,[bx].left
        max_ax  0
        mov     [bx].left,ax

        mov     ax,[bx].top
        max_ax  0
        mov     [bx].top,ax

        mov     cx,es:[di].bmWidth
        mov     ax,[bx].right
        min_ax  cx
        mov     [bx].right,ax

        mov     cx,es:[di].bmHeight
        mov     ax,[bx].bottom
        min_ax  cx
        mov     [bx].bottom,ax

;----------------------------------------------------------------------------;
;   y clipping
;----------------------------------------------------------------------------;
        mov     si,DstY                 ; si = DstY
	mov	di,yExt 		; di = yExt
        mov     cx,SrcY                 ; cx = SrcY

; clip_top = max(clip.top - DstY, 0)

        mov     ax,[bx].top
        sub     ax,si
        max_ax  0
        add     si,ax                   ; DstY += clip_top
        sub     di,ax                   ; yExt -= clip_top
        jle     clip_dib_clipped

; clip_top = max(MapHeight - SrcY+yExt, 0)

        mov     ax,cx
        add     ax,di
        sub     ax,MapHeight
        max_ax  0
        add     si,ax                   ; DstY += clip_top
        sub     di,ax                   ; yExt -= clip_top
        jle     clip_dib_clipped

; clip_bottom = max(DstY + yExt - clip.bottom, 0)

        mov     ax,si
        add     ax,di
        sub     ax,[bx].bottom
        max_ax  0
        add     cx,ax                   ; SrcY += clip_bottom
        sub     di,ax                   ; yExt -= clip_bottom
        jle     clip_dib_clipped

; clip_bottom = max(-SrcY,0)

        mov     ax,cx
        neg     ax
        max_ax  0
        add     cx,ax                   ; SrcY += clip_bottom
        sub     di,ax                   ; yExt -= clip_bottom
        jg      clip_done_y

clip_dib_clipped:
        stc
        ret

clip_done_y:
        mov     DstY,si
        mov     yExt,di
        mov     SrcY,cx

;----------------------------------------------------------------------------;
;   x clipping
;----------------------------------------------------------------------------;
        mov     si,DstX                 ; si = DstX
        mov     di,xExt                 ; di = xExt
        mov     cx,SrcX                 ; cx = SrcX

; clip_left = max(0,clip.left-DstX)

        mov     ax,[bx].left
        sub     ax,si
        max_ax  0
        add     cx,ax                   ; SrcX += clip_left
        add     si,ax                   ; DstX += clip_left
        sub     di,ax                   ; xExt -= clip_left
        jle     clip_dib_clipped

; clip_left = max(0,-SrcX)

        mov     ax,cx
        neg     ax
        max_ax  0
        add     cx,ax                   ; SrcX += clip_left
        add     si,ax                   ; DstX += clip_left
        sub     di,ax                   ; xExt -= clip_left
        jle     clip_dib_clipped

; clip_right = max(0,DstX + xExt - clip.right)

        mov     ax,si
        add     ax,di
        sub     ax,[bx].right
        max_ax  0
        sub     di,ax                   ; xExt -= clip_right
        jle     clip_dib_clipped

; clip_right = max(0,SrcX + xExt - MapWidth)

        mov     ax,cx
        add     ax,di
        sub     ax,MapWidth
        max_ax  0
        sub     di,ax                   ; xExt -= clip_right
        jle     clip_dib_clipped

        mov     DstX,si
        mov     xExt,di
        mov     SrcX,cx

;----------------------------------------------------------------------------;
;----------------------------------------------------------------------------;
clip_complete:
        clc
        ret

clip_dib    endp


;--------------------------Private-Routine------------------------------;
; diScreen386
;
; Special case SetDIBitsToDevice using 386 code.
; This routine only works with DIBs in the native format (8bpp)
;
; Entry:
;       ss:bp ==> DIBScreenBlt frame
; Returns:
;       carry clear if success
; Error Returns:
;       carry set if error
; Registers Preserved:
;       ESI,EDI,BP
; Registers Destroyed:
;       AX,BX,CX,DX,ES,DS,FLAGS
; Calls:
;
; History:
;       11/1 -by-  Todd Laney [ToddLa]
;       Created.
;-----------------------------------------------------------------------;

.386
public diScreen386
diScreen386 proc NEAR

        push    esi
        push    edi

        movzx   esi,si
        movzx   edi,di

        les     di,lp_screen
        lds     si,lpBits

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;
;  Things are ready to go, go into special iner loops depending
;  on wether we need to do index translation or not
;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
        mov     bl,fbFlags
        test    bl,MAP_TRANSLATE
        jnz     diScreen386x
        jz      diScreen386i

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
diScreen386_Exit:
        pop     edi
        pop     esi
        ret

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;
; diScreen386i      - no translation of index's is required
;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
diScreen386i:
        movzx   ecx,cx
        mov     bx,yExt

diScreen386i_Start:
        movsx   edx,next_map_scan
diScreen386i_Start_Scan:
        mov     cx,xExt
        REPMOVSB  es:[edi],ds:[esi]
	inc	scans_copied

        dec     bx
        jz      diScreen386_Exit

        add     esi,edx
        movzx   edi,di
        sub     di,xExt
        sub     di,next_screen_scan
        jnc     diScreen386i_Start_Scan

diScreen386i_Bank_Underflow:
        dec     bank_select
        mov     dl,bank_select
        SET_BANK
        jmp     short diScreen386i_Start

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;
; diScreen386x      - translation of index's is required
;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
diScreen386x:
        lea     bx, color_xlate

diScreen386x_Start:
        movsx   edx,next_map_scan
diScreen386x_Start_Scan:
        mov     cx,xExt
        REPMOVSBXLAT es:[edi], ds:[esi], di, ss:[bx]
	inc	scans_copied

        dec     yExt
        jz      diScreen386_Exit

        add     esi,edx
        movzx   edi,di
        sub     di,xExt
        sub     di,next_screen_scan
        jnc     diScreen386x_Start_Scan

diScreen386x_Bank_Underflow:
        dec     bank_select
        mov     dl,bank_select
        SET_BANK
        jmp     short diScreen386x_Start

diScreen386 endp
.286

;--------------------------------------------------------------------------;
;
;   StretchDIBits()
;       Stretch the source DIB onto the destination bitmap/device.
;
;   Entry:
;       Stack based parameters as described below.
;
;   Returns:
;       num scans handled if successfully stretched
;       else -1 indicating bailed out, GDI should handle it
;
;   Registers Preserved:
;       SI,DI,BP,DS
;
;   Registers Destroyed:
;       AX,BX,CX,DX,ES,flags
;
;   Calls:
;       DibBlt
;
;   History:
;       Wed May 30 1990 -by- ToddLa
;       Created.
;
;   Notes:
;       either calls DibBlt for 1:1 blt or, calls StretchBlt()
;
;--------------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

cProc   StretchDIBits,<FAR,PUBLIC,WIN,PASCAL>,<>
        parmD   lpPDevice               ; PDevice;  bitmap or surface
        parmW   GetOrSet                ; 0 --> set;  1-->get (FUTURE)
        parmW   DstX                    ; in dest's logical coords
        parmW   DstY
        parmW   DstXE
        parmW   DstYE
        parmW   SrcX                    ; in DIB'S (inverted) coords
        parmW   SrcY
        parmW   SrcXE
        parmW   SrcYE
        parmD   lpBits                  ; -->DIB's bitmap
        parmD   lpbi
        parmD   lpTranslate             ; (ignored by non-pal devices)
	parmD	Rop
        parmD   lpBrush                 ; current brush
        parmD   lpDrawMode
        parmD   lpClipRect

        localV  dib_src,%(SIZE int_phys_device) ; source device (DIB) data
cBegin
        cmp     GetOrSet,1
        je      FailStretchDIBits       ; only handle a set operation

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;   check for RLE,  we don't do RLE here.
;   because we need GDI to fix up a clipping rect and call
;   SetDIBitsToDevice()
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
        les     bx,lpbi
        test    wptr es:[bx].biCompression, 0FFFFh
        jnz     FailStretchDIBits

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
; test for a 1:1 stretch
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
        mov     ax,SrcYE
        cmp     ax,DstYE
        jne     StretchDIBitsNot1to1
        or      ax,ax
        js      StretchDIBitsNot1to1

        mov     ax,SrcXE
        cmp     ax,DstXE
        jne     StretchDIBitsNot1to1
        or      ax,ax
        js      StretchDIBitsNot1to1

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
StretchDIBits1to1:
        arg     lpPDevice           ; dest device
        arg     <DstX,DstY>         ; DstX, DstY
        arg     lpbi                ; source device
        arg     lpBits
        arg     <SrcX,SrcY>         ; SrcX, SrcY
        arg     <SrcXE,SrcYE>       ; xExt, yExt
        arg     Rop                 ; Rop
        arg     lpBrush             ; brush = NULL
        arg     lpDrawMode          ; draw mode = NULL
        arg     lpClipRect
        arg     lpTranslate         ; GDI supplied value for color matching

	cCall	DibBlt
        jmp     ExitStretchDIBits

FailStretchDIBits:
        mov     ax,-1
        jmp     ExitStretchDIBits

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
StretchDIBitsNot1to1:

; init the DIB's device struct
        lea     ax,dib_src
        farPtr  lpDIB,ss,ax
        cCall   FarDeviceSelectDIB,<lpDIB,lpbi,lpBits>
        or      ax,ax
        jz      FailStretchDIBits

; pass the paramaters through for StretchBlt to do all the work
	mov	ax,dib_src.bmHeight     ; transform SrcY to be relative to top
        sub     ax,SrcY
        sub     ax,SrcYE
        mov     SrcY,ax

        lea     ax,dib_src
        farPtr  lpDIB,ss,ax

        arg     <lpPDevice>
        arg     <DstX, DstY, DstXE, DstYE>
        arg     <lpDIB>
        arg     <SrcX, SrcY, SrcXE, SrcYE>
        arg     <Rop,lpBrush,lpDrawMode,lpClipRect>

        cCall   StretchBlt
        errn$   ExitStretchDIBits

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
ExitStretchDIBits:

cEnd

sEnd

end

