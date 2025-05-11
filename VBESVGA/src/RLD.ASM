        page    ,132
;-----------------------------Module-Header-----------------------------;
; Module Name:  RLD.ASM - RLE decode module
;
;   This module contains the routines for drawing RLE directly to the
;   screen or a bitmap.
;
;   This code attempts to optimize the very common case where no
;   clipping at all is required.  By using special output functions for
;   clipped and non clipped output.
;
;   The palette tranlate table passed down by GDI is also checked for the
;   identity map, if this is found it is also optimized.
;
; Created: Mon 26-Mar-1990
; Author:  Todd Laney [ToddLa]
;
; Copyright (c) 1984-1990 Microsoft Corporation
;
; Exported Functions:   RleBlt
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
; Restrictions:
;
;   This code draws RLE8 and RLE4 format DIBs to either the device or a
;   color bitmap.  RleBlt will have GDI simulate RLE's drawn to mono
;   bitmaps.
;
;-----------------------------------------------------------------------;
        .286

        .xlist
        include cmacros.inc
        incLogical=1
	incDevice = 1				;Include control for gdidefs.inc
        include gdidefs.inc
        include display.inc
        include macros.mac
        .list

        externA         __AHINCR            ; in KERNEL
        externA         __AHSHIFT           ; in KERNEL
	externA  	__WinFlags          ; in KERNEL

        externFP        OutputDebugString   ; in KERNEL

ifdef EXCLUSION
	externFP	exclude_far		; xeclude cursor from blt area
        externFP        unexclude_far           ; redraw cursor
endif

	externFP	rgb_to_ipc_seq		; in RGB2IPC.ASM

sBegin  Data
	externW		ColourFormat	; in VGA.ASM
	externW		raster_flags	; in BMC_MAIN.ASM
sEnd  Data

HUGE_RLE = 1

ReadRLE macro

        lodsw

ifdef HUGE_RLE
        or      si,si                   ; !!! fix this
        jnz     @f

        mov     cx,ds
        add     cx,__AHINCR
        mov     ds,cx
@@:
endif; HUGE_RLE

        endm

createSeg   _DIMAPS,DIMapSeg,word,public,code
sBegin DIMapSeg
        assumes cs,DIMapSeg
        assumes ds,Data
        assumes es,nothing

ifdef XDEBUG

debug_str_table label word
        dw      str_8
        dw      str_4
        dw      str_8_clip
        dw      str_4_clip
        dw      str_8_xlat
        dw      str_4_xlat
        dw      str_8_clip_xlat
        dw      str_4_clip_xlat
        dw      str_8_huge
        dw      str_4_huge
        dw      str_8_clip_huge
        dw      str_4_clip_huge
        dw      str_8_xlat_huge
        dw      str_4_xlat_huge
        dw      str_8_clip_xlat_huge
        dw      str_4_clip_xlat_huge

        str_8:                  db "RleBlt: RLE8 noxlat noclip <64K",13,10,0
        str_4:                  db "RleBlt: RLE4 noxlat noclip <64K",13,10,0
        str_8_clip:             db "RleBlt: RLE8 noxlat   clip <64K",13,10,0
        str_4_clip:             db "RleBlt: RLE4 noxlat   clip <64K",13,10,0
        str_8_xlat:             db "RleBlt: RLE8   xlat noclip <64K",13,10,0
        str_4_xlat:             db "RleBlt: RLE4   xlat noclip <64K",13,10,0
        str_8_clip_xlat:        db "RleBlt: RLE8   xlat   clip <64K",13,10,0
        str_4_clip_xlat:        db "RleBlt: RLE4   xlat   clip <64K",13,10,0

        str_8_huge:             db "RleBlt: RLE8 noxlat noclip >64K",13,10,0
        str_4_huge:             db "RleBlt: RLE4 noxlat noclip >64K",13,10,0
        str_8_clip_huge:        db "RleBlt: RLE8 noxlat   clip >64K",13,10,0
        str_4_clip_huge:        db "RleBlt: RLE4 noxlat   clip >64K",13,10,0
        str_8_xlat_huge:        db "RleBlt: RLE8   xlat noclip >64K",13,10,0
        str_4_xlat_huge:        db "RleBlt: RLE4   xlat noclip >64K",13,10,0
        str_8_clip_xlat_huge:   db "RleBlt: RLE8   xlat   clip >64K",13,10,0
        str_4_clip_xlat_huge:   db "RleBlt: RLE4   xlat   clip >64K",13,10,0
endif

;
;   the following tables are used to determine the output functions
;   used to decode RLE data.
;
;     x x x x 0
;     | | | |
;     | | | +------------   RLE type  (1=RLE4, 0=RLE8)
;     | | |
;     | | +--------------   clip      (1=clipping required)
;     | |
;     | +----------------   xlat      (1=palette xlat required)
;     |
;     +------------------   huge      (1=rle data greater than 64k)
;
decode_abs_table label word
        dw      decode_abs_8
        dw      decode_abs_4
        dw      decode_abs_8_clip
        dw      decode_abs_4_clip
        dw      decode_abs_8_xlat
        dw      decode_abs_4_xlat
        dw      decode_abs_8_clip_xlat
        dw      decode_abs_4_clip_xlat
        dw      decode_abs_8_huge
        dw      decode_abs_4_huge
        dw      decode_abs_8_clip_huge
        dw      decode_abs_4_clip_huge
        dw      decode_abs_8_xlat_huge
        dw      decode_abs_4_xlat_huge
        dw      decode_abs_8_clip_xlat_huge
        dw      decode_abs_4_clip_xlat_huge

decode_rle_table label word
        dw      decode_rle_8
        dw      decode_rle_4
        dw      decode_rle_8_clip
        dw      decode_rle_4_clip
        dw      decode_rle_8_xlat
        dw      decode_rle_4_xlat
        dw      decode_rle_8_clip_xlat
        dw      decode_rle_4_clip_xlat

;--------------------------Public-Routine-------------------------------;
;
; RleBlt
;
; Entry: per parameters.
;
; Returns: AX = 1 if rle drawn.
;
; Error Returns: AX = 0  if rle not drawn.
;                AX = -1 if we want GDI to simulate
;
; Registers Destroyed: AX,BX,CX,DX,flags.
;
; Registers Preserved: ES,DS,DI,SI.
;
;-----------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

cProc   RleBlt,<NEAR,PUBLIC,PASCAL>,<si,di,es,ds>

        parmD   lpDevice                ; PDevice;  bitmap or surface
        parmW   DstX                    ; in dest's logical coords
        parmW   DstY
        parmD   lpBits                  ; -->RLE bits
        parmD   lpBitmapInfo            ; -->BITMAPINFO + XLAT table
        parmD   lpClipRect              ; -->cliping rectangle

        localB  BltFlags                ; flags describing RleBlt

            RLE_RLE8    equ     0001h   ; RLE8 format
            RLE_RLE4    equ     0002h   ; RLE4 format
            RLE_CLIPX   equ     0004h   ; x clipping is needed
            RLE_XLAT    equ     0008h   ; palette xlat is needed
            RLE_HUGE    equ     0010h   ; RLE data > 64k
            RLE_DEVICE  equ     0020h   ; output is to the device
            RLE_CLIPY   equ     0040h   ; y clipping is needed
            RLE_DIB     equ     0080h   ; output is to a DIB bitmap
            RLE_CLIPPED equ     RLE_CLIPX+RLE_CLIPY

        localW  WidthBytes              ; width of a scanline
        localW  FillBytes               ; segment fill bytes

        localW  fn_decode_abs           ; function to output a abs scan
        localW  fn_decode_rle           ; function to output a solid scan
        localW  fn_next_scan            ; function to jump in Y
	localW	fn_stos			; function to store one pixel of xlated colour
	localW	fn_adv_dest		; function to advance by AX pixels
	localW	fn_rep_stos		; function to store CX pixels of xlated colours
	localW	fn_rep_stos_pair	; function to store CX pixels of two xlated colours

	localW	fn_stos_checked		; fn_stos with wrap checking
	localW	fn_adv_dest_checked	; fn_adv_dest with wrap checking
	localW	fn_rep_stos_checked	; fn_rep_stos with wrap checking
	localW	fn_rep_stos_pair_checked; fn_rep_stos_pair with wrap checking

        localW  scan_start              ; start of current scan

        localW  xExt                    ; blt width
        localW  yExt                    ; blt height

        localV  ClipRect, %(size RECT)
        localV  color_xlat,1024         ;translate table

	localW	colour_format

	localB	use_palette_trans	;non-zero iff device uses a palette
        localB  cur_bank

	localW	DstXBytes		;DstX * bytes per pixel
cBegin
        cld

	; stick this on the stack since we will be using DS for the bitmap
	mov	ax,seg ColourFormat
	mov	ds,ax
	assumes	ds,Data
	mov	ax,[ColourFormat]
	mov	[colour_format],ax

	; check if we're supposed to use palette translation
	mov	ax,[raster_flags]
	and	ax,RC_PALETTE
	mov	[use_palette_trans],ah	; RC_PALETTE is in upper byte!

        call    RleBltInit
        jnc     RleBltStart
        jmp     RleBltExit

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
; Start of RLE decoding
;
;   DS:SI   --> RLE bits
;   ES:DI   --> screen/bitmap output
;   SS:BX   --> color xlat table
;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
RleBltStart:

RleBltNext:
        ReadRLE                     ; al=count ah=color

        or      al,al               ; is it a escape?
        jz      RleBltEscape

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
; We have found a encoded run (al != 0)
;
;   al - run length
;   ah - run color
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
RleBltEncodedRun:
        xor     ch,ch                   ; call decode function
        mov     cl,al                   ;  with CX=length, AX=data
        mov     al,ah

        call    [fn_decode_rle]
        jmps    RleBltNext

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
; We have found a RLE escape code (al=0)
; Possibilities are:
;       . End of Line            -  ah = 0
;       . End of RLE             -  ah = 1
;       . Delta                  -  ah = 2
;       . Unencoded run          -  ah = 3 or more
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
RleBltEscape:
        cmp     ah,al
        je      RleBltEOL

        inc     al
        cmp     ah,al
	jne	@F
        jmp     RleBltEOF

@@:     inc     al
        cmp     ah,al
        je      RleBltDelta
        errn$   RleBltUnencodedRun

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
; We have found a un-encoded run (ah >= 3)
;
;   ah          is pixel count
;   DS:SI   --> pixels
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
RleBltUnencodedRun:
        xor     ch,ch
        mov     cl,ah

        call    [fn_decode_abs]

        test    si,0001h            ; re-align source pointer
        jz      RleBltNext

        dec     si
        ReadRLE
        jmps    RleBltNext

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
; We have found a delta jump, the next two bytes contain the jump values
; note the the jump values are unsigned bytes, x first then y
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
RleBltDelta:
        ReadRLE                     ; al = deltaX, ah = deltaY

        or      ah,ah
        jnz     RleBltDeltaXY

RleBltDeltaX:
        call	[fn_adv_dest_checked]
        jmp     short RleBltNext

RleBltDeltaXY:
        mov     cl,ah
        xor     ch,ch               ; cx = deltaY
        mov     ah,ch               ; ax = deltaX
	; NOT checked since we're not actually going to draw here!
        call	[fn_adv_dest]       ; adjust curX
;
        mov     dx,DstY
        sub     dx,cx               ; adjust curY
        cmp     dx,ClipRect.top
        mov     DstY,dx
        jl      RleBltEOF
;
        mov     ax,di
        sub     ax,scan_start       ; ax = curX
        sub     di,ax               ; di = scan_start
RleBltDeltaYLoop:
        call    [fn_next_scan]
        loop    RleBltDeltaYLoop
        mov     scan_start,di       ; save start of scan
        add	di,ax               ; get back curX
	jnc	@F
	call	adv_bank
@@:     jmp     RleBltNext

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
; We have found a end of line marker, point ES:DI to the begining of the
; next scan
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
RleBltEOL:
        dec     DstY
        mov     ax,DstY
        cmp     ax,ClipRect.top
        jl      RleBltEOF
;
        mov     di,scan_start       ; get start of scan back
        call    [fn_next_scan]      ; advance to next scan
        mov     scan_start,di
        add     di,DstXBytes
	jnc	@F
	call	adv_bank
@@:     jmp     RleBltNext          ; go get some more

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
; We have found a end of rle marker, clean up and exit.
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
RleBltEOF:
        errn$   RleBltDone

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
RleBltDone:

ifdef EXCLUSION
        test    BltFlags, RLE_DEVICE
        jz      @f
        call    unexclude_far
@@:
endif
        mov     ax,1

RleBltExit:
cEnd

;--------------------------Private-Routine-------------------------------;
; RleBltInit
;
;   handle initialization for RleBlt
;
; Entry:
;       SS:BP --> frame of RleBlt
; Return:
;       ES:DI points to start of first output scan
;       DS:SI rle bits
;       SS:BX color xlat table
;
;       carry clear
; Error Returns:
;       AX = return code for RleBlt
;       carry set
; Registers Preserved:
;       none
; Registers Destroyed:
;       AX,BX,CX,DX,DS,ES,SI,DI,FLAGS
; Calls:
;
; History:
;       Mon 26-Mar-1990 -by-  Todd Laney [ToddLa]
;-----------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

rle_init_fail:
        xor     ax,ax
        stc
        ret

rle_init_simulate:
        mov     ax,-1
        stc
        ret

RleBltInit proc near

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;   get the BITMAPINFO pointer and copy needed info
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
        lds     si, lpBitmapInfo        ; get bitmap info

        mov     ax,wptr [si].biWidth    ; get width and height
        mov     dx,wptr [si].biHeight
        mov     xExt,ax                 ; and save for later
        mov     yExt,dx

        mov     ax,DstY                 ; flip over DstY (DIBs are upside down)
        add     ax,dx
        dec     ax
        mov     DstY,ax

        mov     bx,wptr [si].biCompression

        cmp     bx,BI_RLE4
        ja      rle_init_simulate       ; unknown RLE format

        and     bl,BI_RLE8+BI_RLE4      ; get RLE format 4 or 8
        jz      rle_init_fail           ; not a RLE bitmap!

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;   determine if the RLE bits cross a segment boundry.  note if the
;   biSizeImage field is 0 we must assume a segment cross.
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
        or      bl,RLE_HUGE             ; assume >64k

        xor     ax,ax
        cmp     [si].biSizeImage.hi,ax
        jnz     rle_init_huge
        cmp     [si].biSizeImage.lo,ax  ; if biSizeImage == 0, assume >64k
        jz      rle_init_huge
        mov     ax,lpBits.off
        add     ax,[si].biSizeImage.lo
        jc      rle_init_huge

        and     bl,not RLE_HUGE

rle_init_huge:
        mov     BltFlags,bl

        errnz   <BI_RGB-0>
        errnz   <BI_RLE8-1>
        errnz   <BI_RLE4-2>
        errnz   <BI_RLE8-RLE_RLE8>
        errnz   <BI_RLE4-RLE_RLE4>

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
        call    create_color_table

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
        call    init_clip

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
        lds     si,lpDevice
        mov     ax,[si].bmWidthBytes
        mov     WidthBytes,ax
        mov     ax,[si].bmFillBytes
        mov     FillBytes,ax

        mov     ax,word ptr [si].bmPlanes
        cmp     ah,1
        je      rle_init_simulate       ; let gdi handle mono bitmaps
        cmp     ax,[colour_format]
        jne     rle_init_fail           ; fail other formats

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
	shr	ax,8+3			; change bpp in AH to Bpp in AX
	mov	bx,ax
	dec	bx			; 1 Bpp --> offset zero
	shl	bx,1			; convert index to offset
	mov	ax,cs:stos_colour_table[bx]
	mov	dx,cs:adv_dest_table[bx]
	mov	[fn_stos],ax
	mov	[fn_stos_checked],ax
	mov	[fn_adv_dest],dx
	mov	[fn_adv_dest_checked],dx
	mov	ax,__WinFlags
	test	ax,WF_CPU386 OR WF_CPU486
	jz	@F
	add	bx,8			; address second half of table
@@:	; CS: prefixes required to avoid dreaded phase error between passes
	mov	ax,cs:rep_stos_colour_table[bx]
	mov	dx,cs:rep_stos_colpair_table[bx]
	mov	[fn_rep_stos],ax
	mov	[fn_rep_stos_checked],ax
	mov	[fn_rep_stos_pair],dx
	mov	[fn_rep_stos_pair_checked],dx

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
        mov     bl,BltFlags
        and     bx,011110b

        mov     ax,decode_abs_table[bx]
        mov     fn_decode_abs,ax

        and     bl,not RLE_HUGE         ; huge does not matter. for these
        mov     ax,decode_rle_table[bx]
        mov     fn_decode_rle,ax

ifdef XDEBUG
        mov     bl,BltFlags
        and     bx,011110b

        mov     ax,debug_str_table[bx]
        cCall   OutputDebugString,<cs,ax>
endif

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
        mov     cx,[si].bmType
        jcxz    rle_init_bitmap

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
; handle specific initialization for the device
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
rle_init_device:

ifdef EXCLUSION
        push    ds
        push    si

        mov     cx,ClipRect.left
        mov     dx,ClipRect.top
        mov     si,ClipRect.right
        mov     di,ClipRect.bottom
        call    exclude_far

        pop     si
        pop     ds
endif
        lea     ax,next_scan_device
        mov     fn_next_scan,ax

        les     di,[si].bmBits
        mov     ax,DstY
        mul     WidthBytes
        add     di,ax
        adc     dl,dh

        mov     cur_bank,dl
        SET_BANK

	; setup the "checked" versions of the functions if necessary
	; start by checking if (10000h-FillBytes)/WidthBytes leaves a remainder
	mov	ax,[FillBytes]
	cwd
	neg	ax
	test	ax,ax
	jnz	@F
	mov	dx,1	; FillBytes=0 => our numerator is 10000h
@@:	div	[WidthBytes]

	test	dx,dx	; remainder?
	jz	rle_init_no_wrapcheck

	; if there is a remainder, we need to bring in the wrap checks!
	lea	ax,adv_dest_checked
	lea	dx,stos_colour_checked
	cmp	bptr colour_format[1],24
	jne	@F
	lea	dx,stos_colour3_checked     ; special case...
@@:	mov	[fn_adv_dest_checked],ax
	mov	[fn_stos_checked],dx

	lea	ax,rep_stos_colour_checked
	lea	dx,rep_stos_colpair_checked
	mov	[fn_rep_stos_checked],ax
	mov	[fn_rep_stos_pair_checked],dx

rle_init_no_wrapcheck:
        or      BltFlags,RLE_DEVICE         ; mark the fact it is the device
        jmps    rle_init_success

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
rle_init_bitmap:
        lea     ax,next_scan_bitmap
        mov     fn_next_scan,ax

        mov     di,[si].bmBits.off
        mov     ax,DstY
        mov     bx,[si].bmBits.sel
        mov     cx,[si].bmSegmentIndex
        mov     dx,[si].bmScanSegment
        jcxz    bmp_ptr_small

bmp_ptr_loop_huge:
        cmp     ax,dx
        jb      bmp_ptr_small
        add     bx,cx
        sub     ax,dx
        jmps    bmp_ptr_loop_huge

bmp_ptr_small:
        mov     es,bx
        mul     WidthBytes
        add     di,ax

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
rle_init_success:
        mov     scan_start,di       ; remember the start of scan

	; calculate offset of starting byte from beginning of scanline
	mov	ax,DstX
	call	[adv_dest_checked]
	mov	ax,di
	sub	ax,[scan_start]
	mov	[DstXBytes],ax

        lds     si,lpBits
        lea     bx,color_xlat
        clc
        ret

RleBltInit endp

;--------------------------Private-Routine-------------------------------;
; copy_color_table
;
;   copy the color table in the DIB to local storage
;
; Entry:
;       DS:SI --> BITMAPINFO
; Return:
;       color_xlat filled in
; Error Returns:
;       none
; Registers Preserved:
;       BX,DS,ES,SI,DI
; Registers Destroyed:
;       AX,CX,DX,FLAGS
; Calls:
;       none
; History:
;       Mon 26-Mar-1990 -by-  Todd Laney [ToddLa]
;-----------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

create_color_table      proc    near

        lea     di,color_xlat           ; ES:DI --> color_xlat
        mov     ax,ss
        mov     es,ax

        mov     ax,wptr [si].biClrUsed  ; is the color table size specifed?
        or      ax,ax
        jnz     xlate_have_num_colors   ; yes, go for it

        inc     ax                      ; ax is now 1
        mov     cl,bptr [si].biBitCount
        shl     ax,cl                   ; compute num colors 1<<BitsPixel

xlate_have_num_colors:
        mov     cx,ax
        add     si,wptr [si].biSize     ; DS:SI --> color table in DIB

	cmp	[use_palette_trans],0	; device uses palette?
	jz	xlate_no_palette

        xor     bl,bl                   ; Bl will range from 0-255
        xor     dx,dx                   ; DX is ident mapping error
xlate_next_color:
        lodsw                           ; get palette index from GDI
        stosw                           ; store it on the stack
        sub     al,bl                   ; test for a 1<-->1 translate
        add     dx,ax                   ; accumulate the error
	mov	ax,0FF00h		; indicate a palette index in the upper word
	stosw
        inc     bl
        loop    xlate_next_color

        or      dx,dx
        jz      create_color_table_exit
	jmp	set_xlat_flag

xlate_no_palette:
	mov	bl,20h			; we want 32 bits per colour in the output table
	mov	bh,11b			; RGBQUAD --> 4 bytes input, need to swap red and blue
	call	rgb_to_ipc_seq

set_xlat_flag:
        or      BltFlags,RLE_XLAT       ; not the identity table, set the bit

create_color_table_exit:
	ret

create_color_table      endp

;--------------------------Private-Routine-------------------------------;
; init_clip
;
;   calculate the clip rect for rle_blt
;
; Entry:
;
; Return:
;       ClipRect
; Error Returns:
;       none
; Registers Preserved:
;       BX,DS,ES,SI,DI
; Registers Destroyed:
;       AX,CX,DX,FLAGS
; Calls:
;       none
; History:
;       Mon 26-Mar-1990 -by-  Todd Laney [ToddLa]
;-----------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

        public  init_clip
init_clip proc near

        cmp     lpClipRect.sel,0
        je      init_clip_null

        lds     si,lpClipRect

        mov     ax,[si].left
        mov     bx,[si].top
        mov     cx,[si].right
        mov     dx,[si].bottom

        mov     ClipRect.left  ,ax
        mov     ClipRect.top   ,bx
        mov     ClipRect.right ,cx
        mov     ClipRect.bottom,dx

        cmp     ax,DstX
        jg      init_clip_clipped

        mov     ax,DstX
        add     ax,xExt
        cmp     cx,ax
        jl      init_clip_clipped

        mov     ax,DstY
        cmp     ax,dx
        jge     init_clip_clipped

        sub     ax,yExt
        inc     ax
        cmp     ax,bx
        jl      init_clip_clipped

init_clip_exit:
        ret

init_clip_clipped:
        or      BltFlags, RLE_CLIPPED
        ret

init_clip_null:
        mov     ax,DstX
        mov     ClipRect.left,ax
        add     ax,xExt
        mov     ClipRect.right,ax

        mov     ax,DstY
        inc     ax
        mov     ClipRect.bottom,ax
        sub     ax,yExt
        mov     ClipRect.top,ax
        ret

init_clip endp

;--------------------------Private-Routine-------------------------------;
; next_scan
;
; Entry:
;       ES:DI   - destination
; Return:
;       advanced to next scan, with all bank/segment crossing detected
; Error Returns:
;       none
; Registers Preserved:
;       AX,BX,DX,DS,ES,SI
; Registers Destroyed:
;       CX,FLAGS,DI
; Calls:
;       none
; History:
;       Mon 26-Mar-1990 -by-  Todd Laney [ToddLa]
;-----------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

        public  next_scan
next_scan   proc near

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
next_scan_device_restbank:
	; if adv_bank has moved the bank forward, this gets called to
	; move it back before doing the next scanline
        mov     dl,cur_bank
        SET_BANK
	; set the pointer back to normal to avoid excessive calls to
	; SET_BANK...
	lea	dx,next_scan_device
	mov	[fn_next_scan],dx
	
next_scan_device:
        sub     di,WidthBytes
        jc      next_scan_device_wrap
        ret

next_scan_device_wrap:
        dec     cur_bank
        mov     dl,cur_bank
        SET_BANK
        ret

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
next_scan_bitmap:
        sub     di,WidthBytes
        jc      next_scan_bitmap_wrap
        ret

next_scan_bitmap_wrap:
        sub     di,FillBytes
        mov     dx,es
        sub     dx,__AHINCR
        mov     es,dx
        ret

next_scan   endp

;--------------------------Private-Routine-------------------------------;
; load_xlated_colour
;
; Entry:
;	AL	- colour index
;       SS:BX   - colour table (four bytes each)
; Return:
;       DX:AX	- translated physical colour
; Error Returns:
;       none
; Registers Preserved:
;       AX,BX,DX,DS,ES,SI
; Registers Destroyed:
;       CX,FLAGS,DI
; Calls:
;       none
; History:
;       Mon 26-Mar-1990 -by-  Todd Laney [ToddLa]
;-----------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

        public  load_xlated_colour
load_xlated_colour   proc near

	push	bx	; save this
	xor	ah,ah	; ensure AX == index
	shl	ax,2	; convert index to offset in pcolour table
	add	bx,ax	; get the offset of the colour in SS
	mov	ax,ss:[bx]
	mov	dx,ss:[bx+2]
	pop	bx	; restore base pointer of table
        ret

load_xlated_colour   endp

;--------------------------Private-Routine-------------------------------;
; decode_abs_8
;
; Entry:
;       CX      - count of pixels
;       DS:SI   - pixel data bytes for RLE8, nibbles for RLE4
;       ES:DI   - destination
;       SS:BX   - xlat table
; Return:
;       ES:DI   - advanced
;       DS:SI   - advanced
;       CX      - zero
; Error Returns:
;       none
; Registers Preserved:
;       BX,DS,ES,SI
; Registers Destroyed:
;       AX,CX,DX,FLAGS,DI
; Calls:
;       none
; History:
;       Mon 26-Mar-1990 -by-  Todd Laney [ToddLa]
;-----------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

        public  decode_abs8
decode_abs8  proc near

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
decode_abs_8_clip_huge:
        call    clip_rle            ; returns AX=clip_left, DX=clip_right
        jnc     decode_abs_8_huge

        call	[fn_adv_dest_checked]

@@:     add     si,ax
        jnc     @f
        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax

@@:     jcxz    @f
        call    decode_abs_8_huge
	mov	ax,dx
        call	[fn_adv_dest_checked]
        add     si,ax
        jnc     @f
        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax
@@:     ret

decode_abs_8_clip:
        call    clip_rle            ; returns AX=clip_left, DX=clip_right
        jnc     decode_abs_8

        call	[fn_adv_dest_checked]
        add     si,ax
        jcxz    @f
        call    decode_abs_8
        mov     ax,dx
        call	[fn_adv_dest_checked]
        add     si,ax
@@:     ret

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
decode_abs_8_huge:
        mov     ax,si
        add     ax,cx
        jc      decode_abs_8_ack

decode_abs_8:
decode_abs_8_loop:
        REPMOVSB
        ret

decode_abs_8_ack:
        sub     cx,ax
        push    ax
        call    decode_abs_8_loop

        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax

        pop     cx
        jcxz    decode_abs_8_xlat_exit
        jmps    decode_abs_8_loop

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
decode_abs_8_clip_xlat_huge:
        call    clip_rle            ; returns AX=clip_left, DX=clip_right
        jnc     decode_abs_8_xlat_huge

        call	[fn_adv_dest_checked]; update dest

@@:     add     si,ax
        jnc     @f
        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax

@@:     jcxz    @f
        call    decode_abs_8_xlat_huge
	mov	ax,dx
        call	[fn_adv_dest_checked]
        add     si,ax
        jnc     @f
        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax
@@:     ret

decode_abs_8_clip_xlat:
        call    clip_rle            ; returns AX=clip_left, DX=clip_right
        jnc     decode_abs_8_xlat
        call	[fn_adv_dest_checked]; update dest
        add     si,ax
        jcxz    @f
        call    decode_abs_8_xlat
	mov	ax,dx
        call	[fn_adv_dest_checked]; update dest
        add     si,ax
@@:     ret

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
decode_abs_8_xlat_huge:
        mov     ax,si
        add     ax,cx
        jc      decode_abs_8_xlat_ack

decode_abs_8_xlat:
	push	dx	; save this in case we're called from clip version
decode_abs_8_xlat_loop:
        lodsb

        call	load_xlated_colour
        call	[fn_stos_checked]

        loop    decode_abs_8_xlat_loop

decode_abs_8_xlat_exit:
	pop	dx
        ret

decode_abs_8_xlat_ack:
        sub     cx,ax
        push    ax
        call    decode_abs_8_xlat

        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax

        pop     cx
        jcxz    decode_abs_8_xlat_exit
        jmps    decode_abs_8_xlat

decode_abs8  endp

;--------------------------Private-Routine-------------------------------;
; decode_abs_4
;
; Entry:
;       CX      - count of pixels
;       DS:SI   - pixel data bytes for RLE8, nibbles for RLE4
;       ES:DI   - destination
;       SS:BX   - xlat table
; Return:
;       ES:DI   - advanced
;       DS:SI   - advanced
;       CX      - zero
; Error Returns:
;       none
; Registers Preserved:
;       BX,DS,ES,SI
; Registers Destroyed:
;       AX,CX,DX,FLAGS,DI
; Calls:
;       none
; History:
;       Mon 26-Mar-1990 -by-  Todd Laney [ToddLa]
;-----------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

        public  decode_abs4
decode_abs4  proc near

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
decode_abs_4_clip_xlat_huge:
decode_abs_4_clip_xlat:
decode_abs_4_clip_huge:
decode_abs_4_clip:
        call    clip_rle            ; returns AX=clip_left, DX=clip_right
        jnc     decode_abs_4

        call	[fn_adv_dest_checked]; advance dest

        shr     ax,1                ; test for a odd nibble clip!
        jnc     decode_abs_4_clip_even

        add     si,ax
        jnc     @f
        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax

@@:	lodsb			; Remember to get the extra nibble
        jcxz    decode_abs_4_clip_exit
        and     al,0Fh
	push	dx
	call	load_xlated_colour
        call	[fn_stos_checked]
	pop	dx
        loop    decode_abs_4_clip_out
        ret

decode_abs_4_clip_even:
        add     si,ax
        jnc     @f
        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax
@@:     jcxz    decode_abs_4_clip_exit

decode_abs_4_clip_out:
        mov     ax,cx
        add     ax,dx
        shr     ax,1
        adc     ax,si
        push    ax
        call    decode_abs_4
	mov	ax,dx
        call	[fn_adv_dest_checked]
        mov     ax,si
        pop     si
        cmp     si,ax
        jae     decode_abs_4_clip_exit
        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax

decode_abs_4_clip_exit:
        ret

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
decode_abs_4_xlat:
decode_abs_4_xlat_huge:
decode_abs_4:
decode_abs_4_huge:
        mov     ax,cx               ; test for source segment overflow
        shr     ax,1
        adc     ax,si
        jc      decode_abs_4_ack

decode_abs_4_start:
        push    cx
        shr     cx,1
        jcxz    decode_abs_4_no_loop

	push	dx	; save this in case we're called from clip version
decode_abs_4_loop:
        lodsb
        mov     ah,al
        shr     al,4

        push	ax
	call	load_xlated_colour
        call	[fn_stos_checked]
	pop	ax

        xchg    al,ah
        and     al,0Fh
	call	load_xlated_colour
        call	[fn_stos_checked]

        loop    decode_abs_4_loop
	pop	dx

decode_abs_4_no_loop:
        pop     ax
        shr     ax,1
        jc      decode_abs_4_odd

decode_abs_exit:
        ret

decode_abs_4_odd:
        lodsb
        shr     al,4
	push	dx	; save this in case we're called from clip version
	call	load_xlated_colour
        call	[fn_stos_checked]
	pop	dx
        ret

decode_abs_4_ack:
        mov     ax,si
        shl     ax,1
        add     ax,cx
        push    ax
        sub     cx,ax
        call    decode_abs_4_start

        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax

        pop     cx
        jcxz    decode_abs_exit
        jmps    decode_abs_4_start

decode_abs4  endp

;--------------------------Private-Routine-------------------------------;
; decode_rle_8
;
; Entry:
;       AL      - pixel  a byte for RLE8, 2 nibbles for RLE4
;       CX      - count of pixels
;       ES:DI   - destination
;       SS:BX   - xlat table
; Return:
;       ES:DI   - advanced
;       CX      - zero
; Error Returns:
;       none
; Registers Preserved:
;       BX,DS,ES,SI
; Registers Destroyed:
;       AX,CX,DX,FLAGS,DI
; Calls:
;       none
; History:
;       Mon 26-Mar-1990 -by-  Todd Laney [ToddLa]
;-----------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

        public  decode_rle8
decode_rle8  proc near

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
decode_rle_8_clip_xlat:
        call	load_xlated_colour
decode_rle_8_clip:
	push	bx
	push	dx
        push    ax
        call    clip_rle
        call	[fn_adv_dest_checked]
	mov	bx,dx	; save second clip retval in BX
        pop     ax
	pop	dx
        jcxz    @f
        call	[fn_rep_stos_checked]
	mov	ax,bx
        call	[fn_adv_dest_checked]
@@:	pop	bx
	ret

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
decode_rle_8_xlat:
        call	load_xlated_colour
decode_rle_8:
        call	[fn_rep_stos_checked]
        ret

decode_rle8  endp

;--------------------------Private-Routine-------------------------------;
; decode_rle_4
;
; Entry:
;       AL      - pixel  a byte for RLE8, 2 nibbles for RLE4
;       CX      - count of pixels
;       ES:DI   - destination
;       SS:BX   - xlat table
; Return:
;       ES:DI   - advanced
;       CX      - zero
; Error Returns:
;       none
; Registers Preserved:
;       BX,DS,ES,SI
; Registers Destroyed:
;       AX,CX,DX,FLAGS,DI
; Calls:
;       none
; History:
;       Mon 26-Mar-1990 -by-  Todd Laney [ToddLa]
;-----------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

        public  decode_rle4
decode_rle4  proc near

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
decode_rle_4_clip_xlat:
	; translation is unconditional as we will always have at least
	; 256 colours, i.e. more than 16, so it can't be a 1:1 map.
decode_rle_4_clip:
        push    ax
        call    clip_rle
        jnc     decode_rle_4_not_clipped

        call	[fn_adv_dest_checked]

        pop     ax
        jnc     @f
        rol     al,4
@@:     jcxz    @f
        call    decode_rle_4_xlat
	mov	ax,dx
        call	[fn_adv_dest_checked]
@@:     ret

decode_rle_4_not_clipped:
        pop     ax
        errn$   decode_rle_4
        errn$   decode_rle_4_xlat

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
decode_rle_4_xlat:
	; translation is unconditional as we will always have at least
	; 256 colours, i.e. more than 16, so it can't be a 1:1 map.
decode_rle_4:
	push	bp
	push	bx
	push	dx	; save this in case we're called from clip version

	; load this pointer before we trash BP!
	push	offset decode_rle_4_ret
	push	[fn_rep_stos_pair]

        mov     ah,al
        and     al,0Fh
        shr     ah,4
	mov	bp,ax	; backup the left colour
        call	load_xlated_colour

	push	dx
	push	ax
	mov	ax,bp	; get back the left colour
	mov	al,ah	; put it in AL
        call	load_xlated_colour
	pop	bx
	pop	bp
	; now the right colour is in BP:BX and the left in DX:AX!

decode_rle_4_1:
        ret	; this "returns" to fn_rep_stos_pair, which then returns to:

decode_rle_4_ret:
	pop	dx
	pop	bx
	pop	bp
        ret

decode_rle4  endp

;--------------------------Private-Routine-------------------------------;
; clip_rle
;
; Entry:
;       ES:DI       - screen
;       CX          - count of pixels
;       ClipRect    - clipping rect
;       DstY        - y coord
; Return:
;       C           - span is clipped
;       NC          - span is not clipped
;       AX          - amount clipped on left
;       DX          - amount clipped on right
;       CX          - new (clipped) count of pixels
; Error Returns:
;       none
; Registers Preserved:
;       BX,DS,ES,SI,DI
; Registers Destroyed:
;       AX,CX,DX,FLAGS
; Calls:
;       none
; History:
;       Mon 26-Mar-1990 -by-  Todd Laney [ToddLa]
;
;-----------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

        public  clip_rle
clip_rle  proc near

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;
;  we will divide the region surrounding the clip rectangle into 4 areas as
;  shown below. The segment is toattly clipped if it lies toatly in any of
;  the four regions. If it is not totall cliped, there can be 4 ways that
;  the segment mwy reside. These are all shown below.
;
;                               region-1
;                 +--------------------------------------+
;                 |                                      |
;                 |                                      |
;                 |                                      |
;    region-4     |          The Clip Rectangle          |  region-2
;                 |                                      |
;           type_1|              type_2            type_3|
;           ------|------      ----------          ------|-----
;           ------|--------------------------------------|----- type_4
;                 +--------------------------------------+
;                               region-3
;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;   check the span for being totaly clipped (in Y) region 1 or 3
;   !!!this should not be needed!!! if the Y clipping is handled
;   at a higher level
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
        mov     ax,DstY                 ; get curY

        cmp     ax,ClipRect.bottom      ; check for region-3
        jge     clip_rle_invisible

;;;;;;;;cmp     ax,ClipRect.top         ; check for region-1
;;;;;;;;jl      clip_rle_invisible

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;   check the span for being totaly clipped (in X) region 2 or 4
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
        mov     ax,di                   ; get screen pointer
        sub     ax,scan_start           ; convert into curX in bytes

	push	cx
	mov	cx,[colour_format]
	shr	cx,8+3			; convert bpp in DH to Bpp in DX
	div	cx			; convert into curX in pixels
	pop	cx

        cmp     ax,ClipRect.right       ; check for region-2
        jge     clip_rle_invisible

        add     ax,cx                   ; check for region-4
        cmp     ax,ClipRect.left
        jl      clip_rle_invisible

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;   the span is visible, now determine what to clip, type 1,2,3,4
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
clip_rle_right:
        mov     dx,ClipRect.right       ; check for type3 and type4
        sub     dx,ax                   ; how much is clipped on the right?
        neg     dx
        jge     clip_rle_left
        xor     dx,dx                   ; nothing is clipped on right

clip_rle_left:
        sub     ax,cx                   ; get back curX
        sub     ax,ClipRect.left        ; how much is clipped?
        neg     ax
        jge     clip_rle_visible
        xor     ax,ax                   ; nothing on the left

clip_rle_visible:
        sub     cx,ax                   ; remove the clipped part from
        sub     cx,dx                   ; ...the span width

        cmp     ax,dx                   ; test for type2
        jne     clip_rle_clipped
        or      ax,ax
        jnz     clip_rle_clipped

clip_rle_not_clipped:
        clc
        ret

clip_rle_invisible:
        mov     ax,cx
        xor     cx,cx
        mov     dx,cx

clip_rle_clipped:
        stc
        ret

clip_rle  endp

; advance the pointer ES:DI by AX *pixels* and set CF on wrap
adv_dest1 proc near
	add	di,ax
	ret
adv_dest1 endp

adv_dest2 proc near
	shl	ax,1
	add	di,ax
	; need to restore AX and also preserve CF
	adc	al,0
	shr	ax,1
	ret
adv_dest2 endp

adv_dest3 proc near
	; TODO: is there a way to do this without the stack?
	push	dx
	mov	dx,ax
	shl	ax,1
	add	ax,dx
	add	di,ax
	mov	ax,dx
	pop	dx
	ret
adv_dest3 endp

adv_dest4 proc near
	shl	ax,2
	add	di,ax
	; need to restore AX and also preserve CF
	adc	al,1	; adds 1 if NC, 2 if CY
	shr	ax,1	; if we added 1, we get rid of it here
	shr	ax,1	; if we added 2, it sets CF here
	ret
adv_dest4 endp

adv_dest_table	label word
	dw	offset	adv_dest1
	dw	offset	adv_dest2
	dw	offset	adv_dest3
	dw	offset	adv_dest4

adv_dest_checked proc near
	call	[fn_adv_dest]
	jc	adv_bank
	ret
adv_dest_checked endp

adv_bank	proc near
	push	dx

	; don't update cur_bank, because that's supposed to indicate
	; the BEGINNING of the current scanline! We will never be in
	; a situation where "inc dl" doesn't suffice, because that
	; would imply that a single scanline crosses more than one
	; bank, which is impossible...
	mov	dl,cur_bank
	inc	dl
	SET_BANK

	; make sure the current bank is restored when we're ready to
	; go up to the next scanline...
	lea	dx,next_scan_device_restbank
	mov	[fn_next_scan],dx

	pop	dx
	ret
adv_bank	endp

;--------------------------Public-Routine------------------------------;
; stos_colour
;
;   Write one pixel of colour in DX:AX
;
; Entry:
;       DX:AX	= physical colour
;	ES:DI --> colour pattern destination (64*bpp bytes)
; Returns:
;       None
; Error Returns:
;       None
; Registers Preserved:
;       ES,DS,BP,BX,DX,SI
; Registers Destroyed:
;       AX,CX,DI,FLAGS
; Calls:
;       None
; History:
;       See Git.
;
;-----------------------------------------------------------------------;
;
;
;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;
;
        assumes ds,nothing
        assumes es,nothing

stos_colour1	proc near
	stosb
	ret
stos_colour1	endp

stos_colour2	proc near
	stosw
	ret
stos_colour2	endp

stos_colour3	proc near
	stosw
	mov	al,dl
	stosb
	ret
stos_colour3	endp

stos_colour4	proc near
	stosw
	mov	ax,dx
	stosw
	ret
stos_colour4	endp

stos_colour_checked	proc near
	call	[fn_stos]
	test	di,di
	jz	@F
	ret

@@:	jmp	adv_bank
stos_colour_checked	endp

stos_colour3_checked	proc near
	; this case is a bit more complicated than the others because
	; the pixel itself could cross a bank boundary!
	cmp	di,-3		; will the pixel cross the bank end?
	jb	stos_colour3	; nope, just do the normal thing...
	; first byte
	stosb
	test	di,di
	jnz	@F
	call	adv_bank
@@:	; second byte
	mov	al,ah
	stosb
	test	di,di
	jnz	@F
	call	adv_bank
@@:	; third byte
	mov	al,dl
	stosb
	test	di,di
	jnz	@F
	call	adv_bank
@@:	ret
stos_colour3_checked	endp

;--------------------------Public-Routine------------------------------;
; rep_stos_colour
;
;   Write CX pixels of colour in DX:AX
;
; Entry:
;       DX:AX	= physical colour
;	CX	= number of desired pixels
;	ES:DI --> colour pattern destination (64*bpp bytes)
; Returns:
;       None
; Error Returns:
;       None
; Registers Preserved:
;       ES,DS,BP,BX,DX,SI
; Registers Destroyed:
;       AX,CX,DI,FLAGS
; Calls:
;       None
; History:
;       See Git.
;
;-----------------------------------------------------------------------;
;
;
;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;
;
        assumes ds,nothing
        assumes es,nothing

rep_stos_colour1	proc near
	REPSTOSB
	ret
rep_stos_colour1	endp

rep_stos_colour2	proc near
	; no need to check alignment because a 16-bit bitmap
	; will always have pixels on 16-bit boundaries
	rep	stosw
@@:	ret
rep_stos_colour2	endp

rep_stos_colour3	proc near
	jcxz	@B	; go back to the ret above
@@:	stosw
	xchg	al,dl
	stosb
	xchg	al,dl
	loop	@B
@@:	ret
rep_stos_colour3	endp

rep_stos_colour4_286	proc near
	jcxz	@B	; go back to the ret above
@@:	stosw
	xchg	ax,dx
	stosw
	xchg	ax,dx
	loop	@B
@@:	ret
rep_stos_colour4_286	endp

rep_stos_colour4_386	proc near
	jcxz	@B	; go back to the ret above
	.386
	ror	eax,10h
	xchg	ax,dx	; stash the upper half of EAX in DX
	ror	eax,10h

	rep	stosd

	ror	eax,10h
	xchg	ax,dx	; restore the upper half of EAX from DX
	ror	eax,10h
	.286
	ret
rep_stos_colour4_386	endp

;--------------------------Public-Routine------------------------------;
; rep_stos_colpair
;
;   Write CX pixels of alternating colours in DX:AX and BP:BX
;
; Entry:
;       DX:AX	= physical colour for first pixel
;	BP:BX	= physical colour for second pixel
;	CX	= number of desired pixels
;	ES:DI --> colpair pattern destination (64*bpp bytes)
; Returns:
;       None
; Error Returns:
;       None
; Registers Preserved:
;       ES,DS,BP,BX,DX,SI
; Registers Destroyed:
;       AX,CX,DI,FLAGS
; Calls:
;       None
; History:
;       See Git.
;
;-----------------------------------------------------------------------;
;
;
;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;
;
        assumes ds,nothing
        assumes es,nothing

rep_stos_colpair1	proc near
	cmp	al,bl	; colours the same?
	je	rep_stos_colour1

	mov	ah,bl
	test	di,1	; check alignment
	jz	@F
	stosb
	xchg	ah,al
	dec	cx
@@:	shr	cx,1
	rep	stosw
	adc	cl,cl	; get back the bit we shifted out
	rep	stosb

@@:	ret
rep_stos_colpair1	endp

rep_stos_colpair2_286	proc near
	cmp	ax,bx	; colours the same?
	je	rep_stos_colour2

	mov	dx,bx
	shr	cx,1
	; if an even number, go straight to the 32-bit routine
	jnc	rep_stos_colour4_286
	; if odd, do one pixel, then swap order and go 32-bit for the rest
	stosw
	xchg	ax,dx
	jmp	rep_stos_colour4_286
rep_stos_colpair2_286	endp

rep_stos_colpair2_386	proc near
	cmp	ax,bx	; colours the same?
	je	rep_stos_colour2

	mov	dx,bx
	shr	cx,1
	; if an even number, go straight to the 32-bit routine
	jnc	rep_stos_colour4_386
	; if odd, do one pixel, then swap order and go 32-bit for the rest
	stosw
	xchg	ax,dx
	jmp	rep_stos_colour4_386
rep_stos_colpair2_386	endp

; placing colpair4 before colpair3 to allow short jumps to colour4
rep_stos_colpair4_286	proc near
	jcxz	@B	; go back to the ret above (in colpair1)

	cmp	ax,bx	; colours the same?
	jne	@F
	cmp	dx,bp
	je	rep_stos_colour4_286

	shl	cx,1
@@:	stosw
	xchg	dx,ax
	xchg	bx,dx
	xchg	bp,bx
	loop	@B
@@:	ret
rep_stos_colpair4_286	endp

rep_stos_colpair4_386	proc near
	jcxz	@B	; go back to the ret above

	cmp	ax,bx	; colours the same?
	jne	@F
	cmp	dx,bp
	je	rep_stos_colour4_386

@@:	.386
	ror	eax,10h
	xchg	ax,dx	; stash the upper half of EAX in DX
	ror	eax,10h
	ror	ebx,10h
	xchg	bx,bp	; stash the upper half of EBX in BP
	ror	ebx,10h

@@:	stosd
	xchg	eax,ebx
	loop	@B

	ror	ebx,10h
	xchg	bx,bp	; restore the upper half of EBX from BP
	ror	ebx,10h
	ror	eax,10h
	xchg	ax,dx	; restore the upper half of EAX from DX
	ror	eax,10h
	.286
	ret
rep_stos_colpair4_386	endp

rep_stos_colpair3	proc near
	; We want to store DL:AX followed by BPL:BX (BPL is not a thing on IA-32)...
	; Let's turn it into BX:DX:AX so it can be a nice stream of STOSWs
	mov	dh,bl
	xor	bl,bl
	and	bp,0FFh
	or	bx,bp
	xchg	bl,bh

	test	cx,1	; odd number?
	jz	@F
	stosw
	xchg	dl,al
	stosb
	; swap order
	xchg	bh,al	; since we just did XCHG DL,AL above!
	xchg	bl,ah
	xchg	dh,dl

@@:	; multiply CX by 3/2
	mov	bp,cx
	shr	bp,1
	add	cx,bp

	; FIXME: this could all end up being misaligned...
@@:	stosw
	xchg	dx,ax
	xchg	bx,dx
	loop	@B
	ret
rep_stos_colpair3	endp

stos_colour_table	label word
	dw	offset	stos_colour1
	dw	offset	stos_colour2
	dw	offset	stos_colour3
	dw	offset	stos_colour4
rep_stos_colour_table	label word
	dw	offset	rep_stos_colour1
	dw	offset	rep_stos_colour2
	dw	offset	rep_stos_colour3
	dw	offset	rep_stos_colour4_286
	dw	offset	rep_stos_colour1
	dw	offset	rep_stos_colour2
	dw	offset	rep_stos_colour3
	dw	offset	rep_stos_colour4_386
rep_stos_colpair_table	label word
	dw	offset	rep_stos_colpair1
	dw	offset	rep_stos_colpair2_286
	dw	offset	rep_stos_colpair3
	dw	offset	rep_stos_colpair4_286
	dw	offset	rep_stos_colpair1
	dw	offset	rep_stos_colpair2_386
	dw	offset	rep_stos_colpair3
	dw	offset	rep_stos_colpair4_386

rep_stos_colour_checked	proc near
	push	di
	xchg	cx,ax
	call	[fn_adv_dest]	; NOT checked: we only want to know CF
	xchg	cx,ax
	pop	di
	jc	@F
	jmp	[fn_rep_stos]

@@:	; if we get here, it means advancing DI by CX pixels moves past
	; the end of the current bank, so we need to handle that!
	push	ax
	push	cx

	; figure out how many pixels will fit in the rest of the
	; current bank...
	push	ax
	push	dx
	mov	ax,di
	neg	ax
	cwd	; AX should always be <8000h in this situation
	mov	cx,[colour_format]
	shr	cx,3+8
	div	cx
	; now AX = whole pixels remaining in bank, and DX = leftover bytes
	mov	cx,ax	; fill this many pixels
	test	dx,dx	; check for remainder
	; get back our colour:
	pop	dx
	pop	ax

	; and save the pixel count, and the flags so we remember whether
	; or not there was a remainder:
	push	cx
	pushf
	; fill the rest of the bank
	call	[fn_rep_stos]
	; get back flags and count
	popf
	pop	cx

	; if there was a remainder, then do an extra checked pixel...
	jz	@F
	push	ax
	push	dx
	call	[fn_stos_checked] ; destroys AX/DX
	pop	dx
	pop	ax
	inc	cx
	jmp	rep_stos_checked_innextbank

@@:	call	adv_bank
rep_stos_checked_innextbank:
	pop	ax	; get back the original count
	sub	ax,cx	; subtract the pixels we've done so far
	mov	cx,ax	; make that our new count
	pop	ax	; get back the colour
	; and go!
	jmp	[fn_rep_stos]
rep_stos_colour_checked	endp

rep_stos_colpair_checked	proc near
	push	di
	xchg	cx,ax
	shl	ax,1
	call	[fn_adv_dest]	; NOT checked: we only want to know CF
	; need to restore AX and also preserve CF
	adc	al,0
	shr	ax,1
	xchg	cx,ax
	pop	di
	jc	@F
	jmp	[fn_rep_stos_pair]

@@:	; if we get here, it means advancing DI by CX pixels moves past
	; the end of the current bank, so we need to handle that!
	push	ax
	push	cx

	; figure out how many pixels will fit in the rest of the
	; current bank...
	push	ax
	push	dx
	mov	ax,di
	neg	ax
	cwd	; AX should always be <8000h in this situation
	mov	cx,[colour_format]
	shr	cx,3+8-1; -1 since we're counting pixel pairs
	and	cl,not 1
	div	cx
	; now AX = whole pixels remaining in bank, and DX = leftover bytes
	mov	cx,ax	; fill this many pixels
	test	dx,dx	; check for remainder
	; get back our first colour:
	pop	dx
	pop	ax

	; and save the pixel pair count, and the flags so we remember whether
	; or not there was a remainder:
	push	cx
	pushf
	; fill the rest of the bank
	call	[fn_rep_stos]
	; get back flags and count
	popf
	pop	cx

	; if there was a remainder, then do an extra pair of checked pixels...
	jz	@F
	push	ax
	push	dx
	call	[fn_stos_checked] ; destroys AX/DX
	mov	ax,bx
	mov	dx,bp
	call	[fn_stos_checked] ; destroys AX/DX
	pop	dx
	pop	ax
	inc	cx
	jmp	rep_stos_pair_checked_innextbank

@@:	call	adv_bank
rep_stos_pair_checked_innextbank:
	pop	ax	; get back the original count
	sub	ax,cx	; subtract the pixels we've done so far
	mov	cx,ax	; make that our new count
	pop	ax	; get back the colour
	; and go!
	jmp	[fn_rep_stos_pair]
rep_stos_colpair_checked	endp

sEnd
end
