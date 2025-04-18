page    ,132
;----------------------------Module-Header------------------------------;
; Module Name: STRETCH.ASM
;
; StretchBLT at level of device driver.
;
; we will handle a stretchblt only if the following is true
;
;       source and dest is a COLOR bitmap
;       rop is SRCCOPY
;       scale factor is a integer multiple
;
; NOTES:
;       - Does not handle mirroring in x or y.
;       - Should this function attempt to handle a non integer stretch?
;
;-----------------------------------------------------------------------;

?PLM=1
?WIN=1

	title   StretchBLT
	%out    StretchBlt

.286

; Define the portions of GDIDEFS.INC that will be needed by bitblt.

incLogical      = 1             ;Include GDI logical object definitions
incDrawMode     = 1             ;Include GDI DrawMode definitions

	.xlist
	include CMACROS.INC
	include GDIDEFS.INC
	include DISPLAY.INC
	include MACROS.MAC
	include NJUMPS.MAC
	.list

	externA  __AHINCR               ;offset to next selector
	externA  __AHSHIFT              ;offset to next selector
	externA  __WinFlags             ;WinFlags from KERNEL

WF_CPU286       =    0002h
WF_CPU386       =    0004h
WF_CPU486       =    0008h

ifdef PALETTES
	externB PaletteModified         ; 0ffh IF palette modified
	externB PaletteTranslationTable ; mem8 -> dev color translation
	externB PaletteIndexTable       ; dev -> mem8 color translation
endif

ifdef   EXCLUSION                       ;If cursor exclusion
	externNP exclude                ;Exclude area from screen
	externNP unexclude              ;Restore excluded area to screen
endif

sBegin  Data

	externB enabled_flag            ;Non-zero if output allowed

sEnd    Data

WORK_BUF_SIZE = 1024                    ;size of work buffer
SRCCOPY_H     = 00CCh                   ;raster op dest=source

sBegin  Code
assumes cs,Code

    externW     _cstods                 ; in CURSOR.ASM
    externW	ColourFormat_CS

WinFlags label word
	dw      __WinFlags

RD_COLOR    equ     000001b                 ; device is color
RD_DEV      equ     000010b                 ; bitmap src
RD_DIB      equ     000100b                 ; dib src
RD_XLAT     equ     001000b                 ; src requires pal index translation
RD_TRANS    equ     001000b                 ; transparent mode.
RD_DEC      equ     001000b                 ; gl_direction == DECRESSING

read_scan_functions label word              ;function table for read_scan routines
	dw      read_scan_bitmap
	dw      read_scan_device
	dw      read_scan_dib
	dw      -1                          ; does not exist
	dw      read_scan_bitmap_xlat
	dw      read_scan_device_xlat
	dw      read_scan_dib_xlat

write_scan_functions label word             ;function table for write_scan routines
	dw      write_scan_bitmap
	dw      write_scan_device
	dw      -1                          ; write_scan_dib,    does not exist
	dw      -1                          ; write_scan_dib_dev does not exist
	dw      write_scan_bitmap_trans
	dw      write_scan_device_trans
	dw      -1                          ; write_scan_dib_trans does not exist

next_src_scan_functions label word          ;function table for next_src_scan
	dw      next_src_scan_bitmap_inc
	dw      next_src_scan_device_inc
	dw      next_src_scan_dib_inc
	dw      -1
	dw      next_src_scan_bitmap_dec
	dw      next_src_scan_device_dec
	dw      next_src_scan_dib_dec

next_dst_scan_functions label word          ;function table for next_dst_scan
	dw      next_dst_scan_bitmap_inc
	dw      next_dst_scan_device_inc
	dw      -1                          ;next_dst_scan_dib
	dw      -1
	dw      next_dst_scan_bitmap_dec
	dw      next_dst_scan_device_dec

;--------------------------------------------------------------------------;
;
;   StretchBlt()
;       Stretch the source bitmap/device onto the destination bitmap/device.
;
;   Entry:
;       Stack based parameters as described below.
;
;   Returns:
;       num scans handled if successfully stretched
;       else -1 indicating bailed out, GDI should handle it
;
;   Registers Preserved:
;       ES,SI,DI,BP
;
;   Entry:
;       Stack based parameters as described below.
;
;   Returns:
;       num scans handled if successfully stretched
;       else -1 indicating bailed out, GDI should handle it
;
;   Registers Preserved:
;       ES,SI,DI,BP
;
;   Registers Destroyed:
;       AX,BX,CX,DX,flags
;
;   Calls:
;       None
;
;   History:
;       Wed May 30 1990 -by- MichaelE
;           Lots of changes to handle DIB as well as DEVICE and BITMAP
;           source/destination for V7.
;
;--------------------------------------------------------------------------;
        assumes ds,Data
        assumes es,nothing        

cProc   StretchBlt,<FAR,PUBLIC,WIN,PASCAL>,<si,di>
        parmD   lpDstDev                ;--> to destination bitmap descriptor
        parmW   DstX                    ;Destination origin - x coordinate
        parmW   DstY                    ;Destination origin - y coordinate
        parmW   DstXE                   ;x extent of the BLT
        parmW   DstYE                   ;y extent of the BLT
        parmD   lpSrcDev                ;--> to source bitmap descriptor
        parmW   SrcX                    ;Source origin - x coordinate
        parmW   SrcY                    ;Source origin - y coordinate
        parmW   SrcXE                   ;x extent of the BLT
        parmW   SrcYE                   ;y extent of the BLT
        parmD   Rop                     ;Raster operation descriptor
        parmD   lpPBrush                ;--> to a physical brush (pattern)
        parmD   lpDrawMode              ;--> to a drawmode
        parmD   lpClip                  ;Clip rect

        localW  dupX                    ;expansion factor in X
        localW  dupY                    ;expansion factor in Y

        localW  errX                    ;expansion error in X
        localW  errY                    ;expansion error in Y

        localW  next_src_scan           ;Next source scan function
	localW	next_dst_scan		;Next destination scan function

	localB	src_bank		;iff device
	localB	dst_bank		;iff device

        localW  read_scan               ;Read scan function
        localW  write_scan              ;Write scan function

        localW  ret_scans               ;#scans actually drawn to dst

        localB  gl_direction            ;Increment/decrement flag
INCREASING      equ     +1
DECREASING      equ     -1

        localB  local_enable_flag
        localB  local_palette_flag

        localB  gl_flag0

F0_SRC_AND_DST_DEV equ     (F0_DST_IS_DEV+F0_SRC_IS_DEV)

F0_XLAT            equ     (RD_XLAT  shl 4) ;do palette translation on source
F0_SRC_IS_DIB      equ     (RD_DIB   shl 4) ;Source      is a DIB
F0_SRC_IS_DEV      equ     (RD_DEV   shl 4) ;Source      is the device
F0_SRC_IS_COLOR    equ     (RD_COLOR shl 4) ;Source      is color

F0_TRANS           equ     (RD_TRANS shl 0) ;transparent blt.
F0_DST_IS_DIB      equ     (RD_DIB   shl 0) ;Destination is a DIB
F0_DST_IS_DEV      equ     (RD_DEV   shl 0) ;Destination is the device
F0_DST_IS_COLOR    equ     (RD_COLOR shl 0) ;Destination is color

        localV  bmSrc,%(SIZE BITMAP)    ;Source device data
        localV  bmDst,%(SIZE BITMAP)    ;Destination device data

        localV  PalXlatTbl,256          ;palette translation table

        localV  work_buf,WORK_BUF_SIZE  ;Work buffer for 1 expanded scan

        localW  clip_test
        localW  clip_top
        localW  clip_bottom
        localW  clip_left
        localW  clip_right
        localW  clipXE
        localW  clipYE

        localB  bk_color
cBegin
        cld

        test    [WinFlags],WF_CPU286
        jnz     @f
.386
        push    esi
        push    edi
        xor     edi,edi
        xor     esi,esi
.286
@@:
        xor     ax,ax
        mov     ret_scans,ax

        mov     al,enabled_flag         ;Save enabled_flag while we still
        mov     local_enable_flag,al    ;  have DS pointing to Data

        mov     al,[PaletteModified]
        mov     local_palette_flag,al

        ;
        ;   Is this a Blt we will support?
        ;
        ;       rop must be SRCCOPY
        ;       dest size must be greater than source size (expansion)
        ;       scale factor is integer multiple >= 1
        ;       source and destination must be COLOR format
        ;

        mov     ax,wptr Rop[2]          ;Test the ROP first
        cmp     ax,SRCCOPY_H
        jnz     let_gdi_do_it

        mov     ax,DstXE
        mov     bx,SrcXE
        or      ax,ax
        js      let_gdi_do_it           ;mirroring is not cool
        cmp     bx,ax
        ja      let_gdi_do_it           ;if source > dest give it to GDI

        xor     dx,dx                   ;Calculate scale factor, if it is
        div     bx                      ;not even give it to GDI
        mov     errX,dx
        mov     dupX,ax
        or      dx,dx
        jnz     let_gdi_do_it

        mov     ax,DstYE
        mov     bx,SrcYE
        or      ax,ax
        js      let_gdi_do_it           ;mirroring is not cool
        cmp     bx,ax
        ja      let_gdi_do_it           ;if source > dest give it to GDI
        xor     dx,dx                   ;Calculate scale factor, if it is
        div     bx                      ;not even give it to GDI
        mov     errY,dx
        mov     dupY,ax
        or      dx,dx
        jnz     let_gdi_do_it

        or      ax,dupX                 ; test for a 1:1 blit and give to GDI
        cmp     ax,1
        je      let_gdi_do_it

        xor     bh,bh                   ;copy_dev will accumulate flags here
        smov    es,ss

        lds     si,lpSrcDev             ;Test the source device
        assumes ds,nothing
        lea     di,bmSrc
        call    copy_dev
	jc	let_gdi_do_it

        shl     bh,4

        lds     si,lpDstDev             ;Test the dest device
        assumes ds,nothing
        lea     di,bmDst
        call    copy_dev
        jc      let_gdi_do_it

        mov     gl_flag0,bh             ;Copy device set bh = gl_flag0
;
;   Test the enable flag.
;
        test    bh,F0_SRC_AND_DST_DEV
        jz      time_to_stretch         ; neither src or dst is device
                                        ; one or both of src or dst is device
        test    local_enable_flag,0FFh
        jnz     time_to_stretch
        jz      stretchblt_ok

let_gdi_do_it:
        mov     ax,-1
        jmp     short stretchblt_exit

;--------------------------------------------------------------------------;
;
;   We have a StretchBlt we are willing to do!
;
;   ds:si   --> dest PDEVICE
;
;   dupX    expansion factor in X dir
;   dupY    expansion factor in Y dir
;
;--------------------------------------------------------------------------;
time_to_stretch:

        call    stretch_init
        jc      stretchblt_exit

        call    stretch_y_expand

ifdef EXCLUSION
        mov     al,gl_flag0
        test    al,F0_SRC_AND_DST_DEV   
        jz      @f                      ; neither src or dst is device
        call    unexclude               ; one or both of src or dst is device
@@:
endif

stretchblt_ok:
        mov     ax,ret_scans            ; return # scans drawn

stretchblt_exit:
        test    [WinFlags],WF_CPU286
        jnz     @f
.386
        pop     edi
        pop     esi
.286

@@:

cEnd

;--------------------------------------------------------------------------;
;
;   stretch_y_expand
;
;   a y expand StretchBlt (DstYE > SrcYE) is handled , currently the expand
;   factor is assumed constant.
;
;   Entry:
;       ds:si   --> start of source scan
;       es:di   --> start of destination scan
;   Returns:
;
;   Error Returns:
;       None
;   Registers Preserved:
;       ES,DI,BP
;   Registers Destroyed:
;       AX,BX,CX,DX,SI,flags
;   Calls:
;       None
;   History:
;
;--------------------------------------------------------------------------;

        ?_pub   stretch_y_expand
stretch_y_expand PROC NEAR

; write the first (clipped scan)
        mov     ax,SrcYE
        mov     ret_scans,ax                    ; for successful return value

stretchblt_first:
        call    [read_scan]
        mov     cx,dupY
        sub     cx,clip_top

        dec     SrcYE
        jz      stretchblt_last_1

        call    [write_scan]

        dec     SrcYE
        jz      stretchblt_last

; write the non-clipped scans
;
stretch_scan_loop:
        call    [read_scan]
        mov     cx,dupY
        call    [write_scan]

        dec     SrcYE
        jnz     stretch_scan_loop

; write the last clipped scan
;
stretchblt_last:
        call    [read_scan]
        mov     cx,dupY
stretchblt_last_1:
        sub     cx,clip_bottom
        jcxz    stretch_y_expand_exit
        call    [write_scan]

stretch_y_expand_exit:
        ret
stretch_y_expand ENDP

;--------------------------------------------------------------------------;
;
;   stretch_read_scan
;
;   (CX) scanlines from the source are read in and expanded,
;   the expanded version is placed in work_buf
;
;   Entry:
;       ds:(e)si--> begining of scan (dword aligned)
;       ss:bp   --> StretchBlt stack frame
;   Returns:
;       work_buf contains expanded scanline
;       ds:(e)si--> advanced to next scan
;   Error Returns:
;       None
;   Registers Preserved:
;       ES,(E)DI,BP
;   Registers Destroyed:
;       AX,BX,CX,DX,SI,flags
;   Calls:
;       None
;   History:
;       Wed May 30 1990 -by- MichaelE
;           More funcs for DIB/BMP/DEV special cases, faster inner loop.
;   
;--------------------------------------------------------------------------;
        ?_pub   stretch_read_scan_expand
stretch_read_scan_expand PROC NEAR
;
; source is the DEVICE
;
read_scan_device:
;
;   If both the source and dest are the device, we may need to
;   set the bank
;
        test    gl_flag0,F0_DST_IS_DEV
        jz      @f
	mov	dl,src_bank	    ; both src and dst are the device
        SET_BANK
@@:
        errn$   read_scan_bitmap

;
; source is the BITMAP (or DEVICE)
;
read_scan_bitmap:
        push    es
        push    di

        mov     di,ss
        mov     es,di

        lea     di,work_buf
        mov     bx,SrcXE
        shr     bx,1                    ;reduce #inner loop iterations by 2
        mov     dx,dupX

next_read_scan_bitmap:
        lodsw
        mov     cx,dx
        rep     stosb   ;1
        mov     al,ah
        mov     cx,dx
        rep     stosb   ;2

        dec     bx
        jnz     next_read_scan_bitmap

        call    [next_src_scan]

        pop     di
        pop     es
        ret
;
; source is the DEVICE and translating colors
;
read_scan_device_xlat:
;
;   If both the source and dest are the device, we may need to
;   set the bank
;
        test    gl_flag0,F0_DST_IS_DEV
        jz      @f
	mov	dl,src_bank		; both src and dst are the device
        SET_BANK
@@:
        errn$   read_scan_bitmap_xlat
;
; source is either DEVICE, BITMAP
;
read_scan_bitmap_xlat:
        push    es
        push    di

        mov     di,ss
        mov     es,di

        lea     di,work_buf
        mov     dx,SrcXE
        shr     dx,1                    ;reduce #inner loop iterations by 2
;
; NOTE, could probably assume SrcXE <= 1024 and use dh for dupX below
; 
        lea     bx,PalXlatTbl

next_read_scan_bitmap_xlat:
        lodsw
        xlat    ss:[bx]
        mov     cx,dupX
        rep     stosb                   ; 1
        mov     al,ah
        xlat    ss:[bx]
        mov     cx,dupX
        rep     stosb                   ; 2

        dec     dx
        jnz     next_read_scan_bitmap_xlat

        call    [next_src_scan]

        pop     di
        pop     es
        ret
.386
;
; source is a DIB on a 386/486
;
read_scan_dib:
        push    es
        push    di

        mov     di,ss
        mov     es,di

        lea     di,work_buf
        mov     dx,SrcXE
        shr     dx,2                    ;reduce #inner loop iterations by 4
        mov     bx,dupX

next_read_scan_dib:
        lods    dword ptr ds:[esi]

        mov     cx,bx
        rep     stosb                   ;1
        mov     al,ah
        mov     cx,bx
        rep     stosb                   ;2
        ror     eax,16
        mov     cx,bx
        rep     stosb                   ;3
        mov     al,ah
        mov     cx,bx
        rep     stosb                   ;4

        dec     dx
        jnz     next_read_scan_dib

        call    [next_src_scan]

        pop     di
        pop     es
        ret
;
; source is a DIB on a 386/486, and translating indices
;
read_scan_dib_xlat:
        push    es
        push    di

        mov     di,ss
        mov     es,di

        lea     di,work_buf
        mov     dx,SrcXE
        shr     dx,2                    ;reduce #inner loop iterations by 4
        lea     bx,PalXlatTbl           ; es:bx -> local copy of xlat table

next_read_scan_dib_xlat:
        lods    dword ptr ds:[esi]

        xlat    ss:[bx]
        mov     cx,dupX
        rep     stosb                   ; 1
        mov     al,ah
        xlat    ss:[bx]
        mov     cx,dupX
        rep     stosb                   ; 2
        ror     eax,16
        xlat    ss:[bx]
        mov     cx,dupX
        rep     stosb                   ; 3
        mov     al,ah
        xlat    ss:[bx]
        mov     cx,dupX
        rep     stosb                   ; 4

        dec     dx
        jnz     next_read_scan_dib_xlat

        call    [next_src_scan]

read_scan_dib_xlat_exit:
        pop     di
        pop     es
        ret
.286

stretch_read_scan_expand ENDP


;--------------------------------------------------------------------------;
;
;   stretch_write_scan
;
;   output the scan in work_buf to the destination duplicating it CX times
;
;   Entry:
;       es:di   --> begining of output scan
;       cx          duplication count for scanline
;       work_buf contains expanded scanline to output
;   Returns:
;       es:di   --> advanced to next scan
;   Error Returns:
;       None
;   Registers Preserved:
;       ES,DI,BP
;   Registers Destroyed:
;       AX,BX,CX,DX,SI,flags
;   Calls:
;       None
;   History:
;
;--------------------------------------------------------------------------;
        ?_pub   stretch_write_scan
stretch_write_scan PROC NEAR

write_scan_device:

;
;   If both the source and dest are the device, we may need to
;   set the bank
;
        test    gl_flag0,F0_SRC_IS_DEV
        jz      @f
	mov	dl,dst_bank		; both src and dst are the device
        SET_BANK
@@:

write_scan_bitmap:
        mov     bx,cx                   ; bx contains scanline count
	push	si

write_scan_loop:
        lea     si,work_buf
        add     si,clip_left
        mov     cx,clipXE

        REPMOVSB es:[di],ss:[si]
        call    [next_dst_scan]

        dec     bx
        jnz     write_scan_loop

write_scan_exit:
        pop     si
        ret

stretch_write_scan ENDP

stretch_write_scan_transparent PROC NEAR

write_scan_device_trans:

;
;   If both the source and dest are the device, we may need to
;   set the bank
;
        test    gl_flag0,F0_SRC_IS_DEV
        jz      @f
	mov	dl,dst_bank		; both src and dst are the device
        SET_BANK
@@:

write_scan_bitmap_trans:
        mov     bx,cx                   ; bx contains scanline count
        push    si

write_scant_loop:
        mov     ah,bk_color             ; get bkColor
        lea     si,work_buf
        add     si,clip_left
        mov     cx,clipXE

write_scant_loop1:
        lods    bptr ss:[si]
        cmp     ah,al
        je      @f
        mov     es:[di],al
@@:     inc     di
        loop    write_scant_loop1

        call    [next_dst_scan]

        dec     bx
        jnz     write_scant_loop

write_scant_exit:
        pop     si
        ret

stretch_write_scan_transparent ENDP

;--------------------------------------------------------------------------;
;
;   next_src_scan
;
;   advance the source pointer ds:[si] to point to the next scan
;
;   Entry:
;       ds:si   --> end of current source scan
;   Returns:
;       ds:si   --> advanced to begining of next scan
;   Error Returns:
;       None
;   Registers Preserved:
;       ES,DI,BP
;   Registers Destroyed:
;       AX,BX,CX,DX,SI,flags
;   Calls:
;       None
;   History:
;
;--------------------------------------------------------------------------;

;
;   next_src_scan function used if the source is the device
;
next_src_scan_device PROC NEAR

next_src_scan_device_inc:
        sub     si,SrcXE
        add     si,bmSrc.bmWidthBytes
        jc      next_src_scan_device_wrap
        ret

next_src_scan_device_dec:
        sub     si,SrcXE
        sub     si,bmSrc.bmWidthBytes
        jc      next_src_scan_device_wrap
        ret

next_src_scan_device_wrap:
        mov     dl,gl_direction
        add     src_bank,dl
	mov	dl,src_bank
        SET_BANK
        ret

next_src_scan_device ENDP

;
;   next_src_scan function used if the source is a bitmap
;
next_src_scan_bitmap PROC NEAR

next_src_scan_bitmap_inc:
        sub     si,SrcXE
        add     si,bmSrc.bmWidthBytes
        jc      next_src_scan_bitmap_inc_wrap
        mov     ax,bmSrc.bmFillBytes
        add     ax,si
        jc      next_src_scan_bitmap_inc_wrap
        ret

next_src_scan_bitmap_inc_wrap:
        cmp     SrcYE,0
        jz      next_src_scan_bitmap_exit
        add     si,bmSrc.bmFillBytes
        mov     ax,ds
        add     ax,__AHINCR
        mov     ds,ax
        ret

next_src_scan_bitmap_dec:
        sub     si,SrcXE
        sub     si,bmSrc.bmWidthBytes
        jc      next_src_scan_bitmap_dec_wrap
        ret

next_src_scan_bitmap_dec_wrap:
        cmp     SrcYE,0
        jz      next_src_scan_bitmap_exit
        sub     si,bmSrc.bmFillBytes
        mov     ax,ds
        sub     ax,__AHINCR
        mov     ds,ax

next_src_scan_bitmap_exit:
        ret

next_src_scan_bitmap ENDP

;
;   next_src_scan function for a DIB
;
next_src_scan_dib PROC NEAR
.386

next_src_scan_dib_inc:
        movsx   eax, SrcXE
        sub     esi, eax
        movsx   eax, bmSrc.bmWidthBytes
        sub     esi, eax
        ret

next_src_scan_dib_dec:
        movsx   eax, SrcXE
        sub     esi, eax
        movsx   eax, bmSrc.bmWidthBytes
        add     esi, eax
        ret
.286
        
next_src_scan_dib ENDP

;--------------------------------------------------------------------------;
;
;   next_dst_scan
;
;   advance the destination pointer es:[di] to point to the next scan
;
;   Entry:
;       es:di   --> end of current destination scan
;   Returns:
;       es:di   --> advanced to begining of next scan
;   Error Returns:
;       None
;   Registers Preserved:
;       ES,DI,BP
;   Registers Destroyed:
;       AX,BX,CX,DX,SI,flags
;   Calls:
;       None
;   History:
;       Wed May 30 1990 -by- MichaelE
;           Changed inc/dec to always add offset to next scan.
;
;--------------------------------------------------------------------------;
;
;   next_dst_scan function used if the destination is the device
;
next_dst_scan_device PROC NEAR

next_dst_scan_device_inc:
        sub     di,clipXE
        add     di,bmDst.bmWidthBytes
        jc      next_dst_scan_device_wrap
        ret

next_dst_scan_device_dec:
        sub     di,clipXE
        sub     di,bmDst.bmWidthBytes
        jc      next_dst_scan_device_wrap
        ret

next_dst_scan_device_wrap:
        mov     dl,gl_direction
        add     dst_bank,dl
	mov	dl,dst_bank
        SET_BANK
        ret

next_dst_scan_device ENDP

;
;   next_dst_scan function used if the destination is a bitmap
;
next_dst_scan_bitmap PROC NEAR

next_dst_scan_bitmap_inc:
        sub     di,clipXE
        add     di,bmDst.bmWidthBytes
        jc      next_dst_scan_bitmap_inc_wrap
        mov     ax,bmDst.bmFillBytes
        add     ax,di
        jc      next_dst_scan_bitmap_inc_wrap
        ret

next_dst_scan_bitmap_inc_wrap:
        cmp     SrcYE,0
        jz      next_dst_scan_bitmap_exit
        add     di,bmDst.bmFillBytes
        mov     ax,es
        add     ax,__AHINCR
        mov     es,ax
        ret

next_dst_scan_bitmap_dec:
        sub     di,clipXE
        sub     di,bmDst.bmWidthBytes
        jc      next_dst_scan_bitmap_dec_wrap
        ret

next_dst_scan_bitmap_dec_wrap:
        cmp     SrcYE,0
        jz      next_dst_scan_bitmap_exit
        sub     di,bmDst.bmFillBytes
        mov     ax,es
        sub     ax,__AHINCR
        mov     es,ax

next_dst_scan_bitmap_exit:
        ret
next_dst_scan_bitmap ENDP

;--------------------------------------------------------------------------;
;
;   stretch_init
;
;   init local frame vars for StretchBlt
;
;   ENTRY:
;       ss:bp   --> stretchblt frame
;
;   EXIT:
;       CARRY if GDI should do the StretchBlt
;
;--------------------------------------------------------------------------;
stretch_init_fail_286:
        mov     ax,-1
        stc
        ret

stretch_init PROC NEAR

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;
;  Setup 286 vs. 386/486 flag
;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
        test    gl_flag0, F0_SRC_IS_DIB+F0_DST_IS_DIB
        jz      stretch_init_start_clip

        test    [WinFlags],WF_CPU286    ; 386 or 486 CPU?
        jnz     stretch_init_fail_286   ;   nope

stretch_init_start_clip:
        lds     si,lpClip

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;
;   Input Clipping
;
;   clip the StretchBlt source rectangle (SrcX,SrcY,SrcXE,SrcYE) to the
;   extents of the source Bitmap/Device
;
;   modify the parameters of the stretch to compensate
;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

        mov     ax,SrcY       ; max(0,-SrcY) * dupY
        neg     ax
        max_ax  0
        add     SrcY,ax
        sub     SrcYE,ax
        mul     dupY
        add     DstY,ax
        sub     DstYE,ax

        mov     ax,SrcX       ; max(0,-SrcX) * dupX
        neg     ax
        max_ax  0
        add     SrcX,ax
        sub     SrcXE,ax
        mul     dupX
        add     DstX,ax
        sub     DstXE,ax

        mov     ax,SrcY       ; max(0,SrcY+SrcYE-BitmapHeight) * dupY
        add     ax,SrcYE
        sub     ax,bmSrc.bmHeight
        max_ax  0
        sub     SrcYE,ax
        mul     dupY
        sub     DstYE,ax

        mov     ax,SrcX       ; max(0,SrcX+SrcXE-BitmapWidth) * dupX
        add     ax,SrcXE
        sub     ax,bmSrc.bmWidth
        max_ax  0
        sub     SrcXE,ax
        mul     dupY
        sub     DstXE,ax

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;
;   Output clipping
;
;   clip the StretchBlt destination rectangle (DstX,DstY,DstXE,DstYE)
;   to the clip retangle suplied by GDI (lpClip)
;
;   if clipping is required, set the following values:
;
;   clip_test    non zero if clipping is needed
;   clip_top     num scans clipped above
;   clip_bottom  num scans clipped below
;   clip_left    num pixels clipped on left
;   clip_right   num pixels clipped on right
;   clipXE       total pixels visible in a scan
;   clipYE       total scans visible
;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

        xor     bx,bx               ; Total clip error is kept in bx

        mov     ax,[si].top         ; clip_top = max(0,clip.top - DstY)
        sub     ax,DstY
        max_ax  0
        mov     clip_top,ax
        add     bx,ax

        mov     ax,DstY             ; clip_bottom = max(0,DstY + DstYE - clip.bottom)
        add     ax,DstYE
        sub     ax,[si].bottom
        max_ax  0
        mov     clip_bottom,ax
        add     bx,ax

        mov     ax,[si].left        ; clip_left = max(0,clip.left - DstX)
        sub     ax,DstX
        max_ax  0
        mov     clip_left,ax
        add     bx,ax
                                    ; clip_right = max(0,DstX + DstXE - clip.right)
        mov     ax,DstX
        add     ax,DstXE
        sub     ax,[si].right
        max_ax  0
        mov     clip_right,ax
        add     bx,ax

        mov     clip_test,bx
        or      bx,bx
        njz     stretch_no_clipping

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;
;   Adjust the parameters of the stretch so we only do minimal work to
;   fill in the clipped area
;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

        ?_pub stretch_clip_Y_top
stretch_clip_Y_top:
        mov     ax,clip_top
        mov     bx,dupY
        cmp     ax,bx
        jl      stretch_clip_Y_bottom

        xor     dx,dx
        mov     cx,ax               ; save clip_top
        div     bx                  ; dx = clip_top % dupY, ax = clip_top / dupY
        sub     cx,dx               ; cx = clip_top / dupY * dupY

        mov     clip_top,dx
        add     SrcY,ax
        sub     SrcYE,ax
        add     DstY,cx
        sub     DstYE,cx

stretch_clip_Y_bottom:
        mov     ax,clip_bottom
        mov     bx,dupY
        cmp     ax,bx
        jl      stretch_clip_X_left

        xor     dx,dx
        mov     cx,ax               ; save clip_bottom
        div     bx                  ; dx = clip_bottom % dupY, ax = clip_bottom / dupY
        sub     cx,dx               ; cx = clip_bottom / dupY * dupY

        mov     clip_bottom,dx
        sub     SrcYE,ax
        sub     DstYE,cx

stretch_clip_X_left:
        mov     ax,clip_left
        mov     bx,dupX
        cmp     ax,bx
        jl      stretch_clip_X_right

        xor     dx,dx
        mov     cx,ax               ; save clip_left
        div     bx                  ; dx = clip_left % dupY, ax = clip_left / dupY
        sub     cx,dx               ; cx = clip_left / dupY * dupY

        mov     clip_left,dx
        add     SrcX,ax
        sub     SrcXE,ax
        add     DstX,cx
        sub     DstXE,cx

stretch_clip_X_right:
        mov     ax,clip_right
        mov     bx,dupX
        cmp     ax,bx
        jl      stretch_no_clipping

        xor     dx,dx
        mov     cx,ax               ; save clip_bottom
        div     bx                  ; dx = clip_bottom % dupY, ax = clip_bottom / dupY
        sub     cx,dx               ; cx = clip_bottom / dupY * dupY

        mov     clip_right,dx
        sub     SrcXE,ax
        sub     DstXE,cx

stretch_no_clipping:

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;
;  alignment clipping
;
;  Adjust SrcX,XE DstX,XE, clip_left to force dword alignment on Src (Dst
;  (adjustments done below are to compensate for the additional Src bytes)
;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

stretch_src_align:
        mov     bx,001b                 ; WORD align for a BMP
        mov     al,gl_flag0
        test    al,F0_SRC_IS_DIB        ; was assuming BMP OK?
        jz      @f
        mov     bx,011b                 ; DWORD align for a DIB

@@:     mov     ax,SrcX
        and     ax,bx                   ; #bytes to adjust Src
        jz      stretch_srcx_aligned
        sub     SrcX,ax
        add     SrcXE,ax
        mul     dupX                    ; #bytes to adjust Dst cause of Src
        sub     DstX,ax
        add     DstXE,ax
        add     clip_left,ax
stretch_srcx_aligned:

        mov     ax,SrcXE
        and     ax,bx
        jz      stretch_srcxe_aligned
        xor     ax,bx
        inc     ax

        add     SrcXE,ax
        mul     dupX                    ; #bytes to adjust Dst cause of Src
        add     DstXE,ax
        add     clip_right,ax
stretch_srcxe_aligned:

; NOTE, for even MORE speed Dst alignment could be added here!

        xor     ax,ax               ; set the return value, incase fail

        mov     bx,DstXE            ; clipXE = DstXE - clip_left - clip_right
        sub     bx,clip_left
        sub     bx,clip_right
        jle     stretch_init_fail
        mov     clipXE,bx

        mov     bx,DstYE            ; clipYE = DstYE - clip_top - clip_bottom
        sub     bx,clip_top
        sub     bx,clip_bottom
        jle     stretch_init_fail
        mov     clipYE,bx

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;
;   After clipping a destination scanline must be able to fit into
;   our work buffer or we can't do it
;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
        mov     ax,-1                   ; so GDI will do it
        mov     bx,DstXE                ;if dest > work_buf give to GDI
        cmp     bx,WORK_BUF_SIZE
        jbe     stretch_init_buffer_size_ok

stretch_init_fail:
        stc
        ret

stretch_init_buffer_size_ok:

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;
;   Determine the direction of the Stretch
;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

;  assume most favorable case

        mov     ah,INCREASING

;  source present
;  check if source and destination are same bitmaps

        mov     dx,off_lpSrcDev
        cmp     dx,off_lpDstDev
        jne     step_dir_found

        mov     dx,seg_lpSrcDev
        cmp     dx,seg_lpDstDev
        jne     step_dir_found

;  source and destination are the same
;  check if rectangles overlap

        mov     dx,SrcXE
        add     dx,SrcX
        cmp     dx,DstX                 ; src.x + src.dx <= dest.x ?
        jbe     step_dir_found          ; --yes

        mov     dx,DstXE
        add     dx,DstX
        cmp     dx,SrcX                 ; dst.x + dst.dx <= src.x ?
        jbe     step_dir_found          ; --yes

        mov     dx,SrcYE
        add     dx,SrcY
        cmp     dx,DstY                 ; src.y + src.dy <= dest.y ?
        jbe     step_dir_found          ; --yes

        mov     dx,DstYE
        add     dx,DstY
        cmp     dx,SrcY                 ; dst.y + dst.dy <= src.y ?
        jbe     step_dir_found          ; --yes
;
;   rectangles overlap
;
;   determine which direction to process by comparing the distances shown below
;   if A > B go forward else go backward.
;
;       +-----------------+
;       |Dst    ^         |
;       |       |------------------ A = SrcY - DstY
;       |       v         |
;       |    +------+     |
;       |    |Src   |     |
;       |    |      |     |
;       |    +------+     |
;       |       ^         |
;       |       |------------------ B = (DstY + DstYE) - (SrcY + SrcYE)
;       |       |         |
;       |       v         |     A - B = 2SrcY - 2DstY - DstYE - SrcYE
;       +-----------------+
;
        mov     bx,SrcY
        mov     cx,DstY
        add     bx,bx
        add     cx,cx
        sub     bx,cx
        sub     bx,DstYE
        sub     bx,SrcYE
        jge     step_dir_found

;  overlap requires move start at high end

        mov     ah,DECREASING

;  save the results

step_dir_found:
        mov     gl_direction,ah

        ;   if we are going backward, switch the meaning of clip_top
        ;   and clip_bottom

        cmp     ah,INCREASING
        je      @f
        mov     ax,clip_top
        mov     bx,clip_bottom
        mov     clip_top,bx
        mov     clip_bottom,ax
@@:

        subttl  Cursor Exclusion
        page
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;       Cursor Exclusion
;
;       If either device or both devices are for the display, then
;       the cursor must be excluded.  If both devices are the display,
;       then a union of both rectangles must be performed to determine
;       the exclusion area.
;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

ifdef   EXCLUSION
        mov     al,gl_flag0
        and     al,F0_SRC_AND_DST_DEV   ;Are both memory bitmaps?
        jz      cursor_exclusion_end    ;  Yes, no exclusion needed

        mov     cx,DstX                 ;Assume only a destination on the
        mov     dx,DstY                 ;  display
        mov     si,DstXE
        mov     di,DstYE

        test    al,F0_SRC_IS_DEV        ;Is the source a memory bitmap?
        jz      cursor_exclusion_no_union;  Yes, go set right and bottom

        test    al,F0_DST_IS_DEV        ;  (set 'Z' if dest is memory)
        xchg    ax,cx                   ;  No, prepare for the union
        mov     bx,dx

        mov     cx,SrcX                 ;Set source org
        mov     dx,SrcY
        mov     si,SrcXE
        mov     di,SrcYE

        jz      cursor_exclusion_no_union;Dest is memory. Set right and bottom

;       The union of the two rectangles must be performed.  The top left
;       corner will be the smallest x and smallest y.  The bottom right
;       corner will be the largest x and the largest y added into the
;       extents

        add     si,cx                   ;si = SrcX + SrcXE
        add     di,dx                   ;di = SrcY + SrcYE

        cmp     cx,ax                   ;Get smallest x
        jle     cursor_exclusion_y      ;CX is smallest
        mov     cx,ax                   ;AX is smallest

cursor_exclusion_y:
        cmp     dx,bx                   ;Get smallest y
        jle     cursor_exclusion_union  ;DX is smallest
        mov     dx,bx                   ;BX is smallest

cursor_exclusion_union:
        mov     ax,DstX                 ;ax = DstX + DstXE
        add     ax,DstXE
        cmp     si,ax
        jge     @f
        mov     si,ax
@@:
        mov     ax,DstY                 ;ax = DstY + DstYE
        add     ax,DstYE
        cmp     di,ax
        jge     @f
        mov     di,ax
@@:
        jmp     short cursor_exclusion_do_it    ;Go do exclusion

cursor_exclusion_no_union:
        add     si,cx                   ;Set right
        add     di,dx                   ;Set bottom

cursor_exclusion_do_it:
        dec     si                      ;Make the extents inclusive of the
        dec     di                      ;  last point

        call    exclude                 ;Exclude the area from the screen

endif   ;EXCLUSION

cursor_exclusion_end:

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;
;   setup the palette translation table
;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
ifdef   PALETTES
        test    gl_flag0,F0_SRC_IS_DIB  ; DIB format?
	jz	stretch_init_not_dib	;   no, must be BMP <--> DEV

        lds     si,bmSrc.bmlpPDevice   ;   yep, ds:si -> DIB's BitmapInfo
        add     si,[si].biSize.lo       ; ds:si -> DIB's color xlat table
        lea     di,PalXlatTbl
        smov    es,ss                   ; ss:di -> local copy of xlat table
	mov	cx,256			; cx = #color indices
	xor	bx,bx
	xor	dx,dx

stretch_init_next_color:
        lodsw
	stosb
	sub	al,bl			; compute error from 1:1
	add	dx,ax			; accum error
	inc	bl
	loop	stretch_init_next_color

	;
	; check for identity palette
	;
	or	dx,dx
	jz	stretch_init_no_xlat	; 1:1 xlat
	jnz	stretch_init_xlat

stretch_init_not_dib:
        cmp     local_palette_flag,0ffh ; need to xlat the palette?
        jne     stretch_init_no_xlat    ;   nope

        mov     ds,[_cstods]
        assumes ds,Data                 ; GDI's xlat table is in our data seg

        lea     si,PaletteIndexTable    ;   yep, use dev->mem8 xlat direction
        mov     al,gl_flag0
        test    al,F0_SRC_IS_DEV
        jnz     @f
        lea     si,PaletteTranslationTable ; oh, it's mem8->dev xlat direction
@@:     lea     di,PalXlatTbl
        smov    es,ss                   ; es:di -> local copy of xlat table
        mov     cx,128
        rep     movsw
        assumes ds,nothing
        errn$   stretch_init_xlat

stretch_init_xlat:
        or      gl_flag0,F0_XLAT

stretch_init_no_xlat:

endif   ;PALETTES

stretch_init_done_xlat:

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;
;  check for transparent mode (lpDrawMode.bkMode == 3)
;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
	lds	si,lpDrawMode
        cmp     [si].bkMode,3
        jne     stretch_init_opaque

	mov	es,[_cstods]
        assumes es,Data
        xor     bh,bh
        mov     bl,bptr [si].bkColor
        mov     bl,es:PaletteTranslationTable[bx]
	mov	bk_color,bl
	or	gl_flag0, F0_TRANS
        assumes es,nothing

stretch_init_opaque:

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;
;  Setup read_scan and write_scan function pointers
;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
        xor     bx,bx                   ; build read_scanIndex in bl
        mov     dl,gl_direction
        and     dl,RD_DEC

	mov	bl,gl_flag0
	shr	bl,4
        and     bl,RD_DIB+RD_DEV+RD_XLAT
	mov	ax,read_scan_functions[bx]
        mov     read_scan,ax

        and     bl,RD_DIB+RD_DEV
        or      bl,dl
	mov	ax,next_src_scan_functions[bx]
        mov     next_src_scan,ax

	mov	bl,gl_flag0
        and     bl,RD_DIB+RD_DEV+RD_TRANS
	mov	ax,write_scan_functions[bx]
        mov     write_scan,ax

        and     bl,RD_DIB+RD_DEV
        or      bl,dl
	mov	ax,next_dst_scan_functions[bx]
        mov     next_dst_scan,ax

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;
;  Set up the initial source and dest pointers
;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
        mov     bx,DstX
        mov     ax,DstY
        add     bx,clip_left            ; figure clipping into start X
        add     ax,clip_top
        cmp     gl_direction,INCREASING
        je      @f
        sub     ax, clip_top
        add     ax, clip_bottom
        add     ax, clipYE
        dec     ax
@@:
        lea     si,bmDst
        call    map_address
        mov     di,ax
        mov     es,dx
	mov	dst_bank,bl

        mov     bx,SrcX
        mov     ax,SrcY
        cmp     gl_direction,INCREASING
        je      @f
        add     ax,SrcYE
        dec     ax
@@:
        lea     si,bmSrc
        call    map_address
        mov     si,ax
	mov	ds,dx
	mov	src_bank,bl

	test	gl_flag0, F0_SRC_IS_DIB
	jz	stretch_init_success
	.386
	mov	esi,eax
	.286

stretch_init_success:
        clc
        ret

stretch_init ENDP

;--------------------------Public-Routine-------------------------------;
; map_address
;
;   Convert X,Y coordinate to initial pointer.
;
; Entry:
;       AX = Y
;       BX = X
;       SS:SI -> local BITMAP structure
; Return:
;       DX:(E)AX points to (x,y)
;	BL  is bank for device
; Error Returns:
;       none
; Registers Preserved:
;       none
; Registers Destroyed:
;       AX,BX,CX,DX,DS,ES,SI,DI,FLAGS
; Calls:
;       None
; History:
;       Wed May 30 1990 -by- ToddLa
;-----------------------------------------------------------------------;

map_address     proc    near

        add     bx,ss:[si].bmBits.off   ; bias X cord
        mov     cx,ss:[si].bmType       ; is it a bitmap?
        jcxz    map_memory

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;  the physical DEVICE
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
map_device:
        cmp     cx,BMTYPE_DIB
        je      map_dib

        mul     ss:[si].bmWidthBytes
        add     ax,bx
        adc     dl,dh
	mov	bl,dl

        SET_BANK

        mov     dx,ss:[si].bmBits.sel
        ret

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;  DIB BITMAP
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
map_dib:
        sub     ax,ss:[si].bmHeight         ; scan line order in..
        not     ax                          ; ..DIBs is backwards

	.386
	movzx	eax,ax
	movzx	ebx,bx
	movzx	edx,ss:[si].bmWidthBytes
	mul	edx
	add	eax,ebx 		    ; add in pixel offset
	.286
        mov     dx,ss:[si].bmBits.sel       ; Compute segment of the bits
        ret

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;  MEMORY BITMAP
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
map_memory:
        xor     dx,dx
        div     ss:[si].bmScanSegment       ; DX = new Y, AX = segment number

        mov     cx,__AHSHIFT
        shl     ax,cl
        add     ax,ss:[si].bmBits.sel

        mov     cx,ax                       ; save segment
        mov     ax,dx                       ; AX = new Y

        mul     ss:[si].bmWidthBytes        ; AX  = Y*WidthBytes
        add     ax,bx                       ; AX += X
        mov     dx,cx                       ; get segment number.
        ret

map_address     endp

;----------------------------Private-Routine---------------------------;
; copy_dev
;
; Copy device information to frame.
;
; Entry:
;	DS:SI --> device
;       ES:DI --> frame BITMAP structure
;       BH     =  gl_flag0, accumulated so far
; Returns:
;       BH     =  gl_flag0, accumulated so far
;           RD_DIB
;           RD_DEV
;           RD_COLOR
;	Carry clear if no error
; Error Returns:
;	Carry set if error (bad color format)
; Registers Preserved:
;	BX,CX,DX,DS,ES,BP
; Registers Destroyed:
;	AX,SI,DI,flags
; Calls:
;	None
; History:
;  Sun 22-Feb-1987  Created.
;-----------------------------------------------------------------------;

copy_dev	proc near
        mov     cx,(size BITMAP) / 2
        rep     movsw
        sub     si,(size BITMAP)
        sub     di,(size BITMAP)

        mov     ax,[si].bmType

        cmp     ax,BMTYPE_DIB           ;is it a DIB?
        jne     copy_dev_not_dib        ;  nope
        or      bh,RD_DIB               ;  yep
        jmps    copy_dev_bitmap

copy_dev_not_dib:
        or      ax,ax
        jz      copy_dev_bitmap
        or      bh,RD_DEV               ; it is the device

copy_dev_bitmap:
        mov     ax,wptr [si].bmPlanes

;       cmp     ax,0101H                ;Monochrome?
;       je      copy_dev_success        ;  Yes  success.

	cmp	ax,[ColourFormat_CS]	;Our color?
        jne     copy_dev_bad_clr_format ;  No, complain about color format

copy_dev_20:
        or      bh,RD_COLOR

copy_dev_success:
	clc
	ret

copy_dev_bad_clr_format:
	stc
	ret

copy_dev        endp

sEnd    Code

end
