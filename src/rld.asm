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
        include gdidefs.inc
        include display.inc
        include macros.mac
        .list

        externA         __AHINCR            ; in KERNEL
        externA         __AHSHIFT           ; in KERNEL

        externFP        OutputDebugString   ; in KERNEL

ifdef EXCLUSION
	externFP	exclude_far		; xeclude cursor from blt area
        externFP        unexclude_far           ; redraw cursor
endif

sBegin  Data
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

        localW  scan_start              ; start of current scan

        localW  xExt                    ; blt width
        localW  yExt                    ; blt height

        localV  ClipRect, %(size RECT)
        localV  color_xlat,256          ;translate table

        localB  cur_bank
cBegin
        cld

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
        je      RleBltEOF

        inc     al
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
        add     di,ax
        jmp     short RleBltNext

RleBltDeltaXY:
        mov     cl,ah
        xor     ch,ch               ; cx = deltaY
        mov     ah,ch               ; ax = deltaX
        add     di,ax               ; adjust curX
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
        add     di,ax               ; get back curX
        jmp     RleBltNext

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
        add     di,DstX
        jmp     RleBltNext          ; go get some more

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

        mov     al,[si].bmBitsPixel
        cmp     al,1
        je      rle_init_simulate       ; let gdi handle mono bitmaps
        cmp     al,8
        jne     rle_init_fail           ; fail other formats

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
        add     di,DstX
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

        xor     bl,bl                   ; Bl will range from 0-255
        xor     dx,dx                   ; DX is ident mapping error
xlate_next_color:
        lodsw                           ; get palette index from GDI
        stosb                           ; store it on the stack
        sub     al,bl                   ; test for a 1<-->1 translate
        add     dx,ax                   ; accumulate the error
        inc     bl
        loop    xlate_next_color

        or      dx,dx
        jz      create_color_table_exit

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

        add     di,ax

@@:     add     si,ax
        jnc     @f
        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax

@@:     jcxz    @f
        call    decode_abs_8_huge
        add     di,dx
        add     si,dx
        jnc     @f
        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax
@@:     ret

decode_abs_8_clip:
        call    clip_rle            ; returns AX=clip_left, DX=clip_right
        jnc     decode_abs_8

        add     di,ax
        add     si,ax
        jcxz    @f
        call    decode_abs_8
        add     di,dx
        add     si,dx
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

        add     di,ax               ; update dest

@@:     add     si,ax
        jnc     @f
        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax

@@:     jcxz    @f
        call    decode_abs_8_xlat_huge
        add     di,dx
        add     si,dx
        jnc     @f
        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax
@@:     ret

decode_abs_8_clip_xlat:
        call    clip_rle            ; returns AX=clip_left, DX=clip_right
        jnc     decode_abs_8_xlat
        add     di,ax               ; update dest
        add     si,ax
        jcxz    @f
        call    decode_abs_8_xlat
        add     di,dx
        add     si,dx
@@:     ret

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
decode_abs_8_xlat_huge:
        mov     ax,si
        add     ax,cx
        jc      decode_abs_8_xlat_ack

decode_abs_8_xlat:
decode_abs_8_xlat_start:
        test    di,0001h
        jz      @f

        lodsb
        xlat    ss:[bx]
        stosb

        dec     cx
@@:     shr     cx,1
        jz      decode_abs_8_xlat_end

decode_abs_8_xlat_loop:
        lodsw

        xchg    al,ah
        xlat    ss:[bx]
        xchg    al,ah
        xlat    ss:[bx]

        stosw
        loop    decode_abs_8_xlat_loop

decode_abs_8_xlat_end:
        jnc     decode_abs_8_xlat_exit
        lodsb
        xlat    ss:[bx]
        stosb

decode_abs_8_xlat_exit:
        ret

decode_abs_8_xlat_ack:
        sub     cx,ax
        push    ax
        call    decode_abs_8_xlat_start

        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax

        pop     cx
        jcxz    decode_abs_8_xlat_exit
        jmps    decode_abs_8_xlat_start

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

        add     di,ax               ; advance dest

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
        xlat    ss:[bx]
        stosb
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
        add     di,dx
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

decode_abs_4_loop:
        lodsb
        mov     ah,al
        and     al,0Fh
        xlat    ss:[bx]
        xchg    al,ah
        shr     al,4
        xlat    ss:[bx]
        stosw
        loop    decode_abs_4_loop

decode_abs_4_no_loop:
        pop     ax
        shr     ax,1
        jc      decode_abs_4_odd

decode_abs_exit:
        ret

decode_abs_4_odd:
        lodsb
        shr     al,4
        xlat    ss:[bx]
        stosb
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
        xlat    ss:[bx]
decode_rle_8_clip:
        push    ax
        call    clip_rle
        add     di,ax
        pop     ax
        jcxz    @f
        REPSTOSB
        add     di,dx
@@:     ret

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
decode_rle_8_xlat:
        xlat    ss:[bx]
decode_rle_8:
        REPSTOSB
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
decode_rle_4_clip:
        push    ax
        call    clip_rle
        jnc     decode_rle_4_not_clipped

        add     di,ax

@@:     shr     ax,1
        pop     ax
        jnc     @f
        rol     al,4
@@:     jcxz    @f
        call    decode_rle_4_xlat
        add     di,dx
@@:     ret

decode_rle_4_not_clipped:
        pop     ax
        errn$   decode_rle_4
        errn$   decode_rle_4_xlat

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
decode_rle_4_xlat:
decode_rle_4:
        mov     ah,al
        and     al,0Fh
        shr     ah,4
        xlat    ss:[bx]
        xchg    al,ah
        xlat    ss:[bx]

decode_rle_4_1:
        test    di,0001h
        jz      @f
        stosb
        xchg    al,ah
        dec     cx
@@:     shr     cx,1
        rep     stosw
        adc     cl,cl
        rep     stosb

decode_rle_4_ret:
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
        sub     ax,scan_start           ; convert into curX

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

sEnd
end
