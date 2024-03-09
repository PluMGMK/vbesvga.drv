	page	,132
;-----------------------------Module-Header-----------------------------;
; Module Name:  DIBSEL.ASM
;
; This module contains the routines for selecting a DIB as the
; drawing surface for a PDevice
;
; Created: 11-30-89
; Author:  Todd Laney [ToddLa]
;
; Copyright (c) 1983-1987 Microsoft Corporation
;
; Exported Functions:   none
;
; Public Functions:     DeviceSelectDIB
;
; Public Data:		none
;
; General Description:
;
;
; Restrictions:
;
;-----------------------------------------------------------------------;

	.xlist
	include cmacros.inc
	include gdidefs.inc
        include display.inc
	include macros.mac
        .list

        externA         __AHINCR

sBegin  Code
        assumes cs,Code

page
;--------------------------Public-Routine-----------------------------;
; DeviceSelectDIB
;
;   This function will make a DIB (Device independent bitmap) the drawing
;   surface of the passed physical device.
;
;   This function is called by control.asm in response to a Escape call
;   from a aplication, or from ENABLE.ASM in response to the Enable() call
;
;   The bits are assumed to follow the COLOR TABLE after the BITMAPINFO
;
; Entry:
;       lpDevice                - Physical device to select DIB into
;       lpBitmapInfo            - Pointer to BITMAPINFO
;       lpBits                  - if NULL bits are assumed to follow BITMAPINFO
; Returns:
;	AX = 1 if success
; Error Returns:
;	AX = 0 if error
; Registers Preserved:
;	SI,DI,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,FLAGS
; Calls:
;	None
; History:
;
;       11-30-89 -by-  Todd Laney [ToddLa]
;	Created.
;-----------------------------------------------------------------------;

        assumes ds,nothing
        assumes es,nothing

cProc   FarDeviceSelectDIB,<FAR,PUBLIC,PASCAL,NODATA>,<>

        parmD   lpDevice        ; Physical device to select DIB into
        parmD   lpBitmapInfo    ; Pointer to BITMAPINFO
        parmD   lpBits          ; Pointer to the bitmap bits (can be NULL)

cBegin
        cCall   DeviceSelectDIB, <lpDevice,lpBitmapInfo,lpBits>
cEnd

cProc   DeviceSelectDIB,<NEAR,PUBLIC,PASCAL>,<ds,si,di>

        parmD   lpDevice        ; Physical device to select DIB into
        parmD   lpBitmapInfo    ; Pointer to BITMAPINFO
        parmD   lpBits          ; Pointer to the bitmap bits (can be NULL)

cBegin
        les     di,lpDevice

        xor     ax,ax
        mov     cx,(size int_phys_device) / 2
        errnz   <(size int_phys_device) and 1>
        push    di
        rep     stosw
        pop     di

        ;
        ;   Do some sanity checks on the BITMAPINFO.  We only support
        ;   8 bpp or 1 bpp DIBs
        ;
        mov     ax,lpBitmapInfo.off
        or      ax,lpBitmapInfo.sel
        jz      select_dib_null

        lds     si,lpBitmapInfo
        assumes ds,nothing

        cmp     wptr ds:[si].biSize,size BitmapInfoHeader
        jne     select_dib_fail

        cmp     wptr ds:[si].biPlanes,1
        jne     select_dib_fail

        cmp     wptr ds:[si].biCompression,BI_RGB
        jne     select_dib_fail

        cmp     wptr ds:[si].biBitCount,8
        je      select_dib_ok

        cmp     wptr ds:[si].biBitCount,1
        je      select_dib_ok

        cmp     wptr ds:[si].biBitCount,4
        je      select_dib_fail

        cmp     wptr ds:[si].biBitCount,24
        je      select_dib_fail

select_dib_fail:
        xor     ax,ax
        jmp     select_dib_exit

;
;   A NULL pointer was passed, fail
;
select_dib_null:
        jmp     select_dib_exit

;
;   The passed DIB is valid copy the DIBINFO parameters to the
;   pDevice
;
select_dib_ok:
        assumes ds,nothing

        mov     ax,wptr ds:[si].biWidth
        mov     bx,wptr ds:[si].biHeight
        mov     cx,wptr ds:[si].biBitCount
        mov     dx,wptr ds:[si].biPlanes

        mov     es:[di].bmType,BMTYPE_DIB
        mov     es:[di].bmWidth,ax
        mov     es:[di].bmHeight,bx
        mov     es:[di].bmPlanes,dl
        mov     es:[di].bmBitsPixel,cl

        ;
        ;   calculate the width of a scanline, making sure to DWORD align
        ;
        mul     cx
        add     ax,31
        and     ax,not 31
        shiftr  ax,3

        mov     es:[di].bmWidthBytes,ax

        ;
        ;   is the lpBits param non NULL if so use it, else assume the
        ;   bits follow the BITMAPINFO and color table.
        ;
        mov     ax,lpBits.off
        mov     dx,lpBits.sel
        or      dx,dx
        jnz     select_dib_have_bits

        ;
        ;   set the pointer to the bits, this assumes the bitmap bits
        ;   follow the color table, and the color table is RGBQUADs
        ;   (ie not pal indexes)
        ;
        mov     ax,wptr ds:[si].biClrUsed
        or      ax,ax
        jnz     select_dib_have_num_colors

        mov     cx,wptr ds:[si].biBitCount
        cmp     cx,24
        je      select_dib_have_num_colors
        mov     ax,1
        shl     ax,cl

select_dib_have_num_colors:
        shiftl  ax,2                        ; ax = ax * sizeof(RGBQUAD)

        mov     dx,ds
        add     ax,si
        add     ax,wptr ds:[si].biSize

select_dib_have_bits:
        mov     es:[di].bmBits.sel,dx
        mov     es:[di].bmBits.off,ax

        ;
        ;   does the DIB span a segment?
        ;
        mov     bx,ax
        mov     ax,es:[di].bmWidthBytes
        mul     es:[di].bmHeight            ; DX:AX contains size of DIB
        add     bx,ax                       ; add in base offset
        adc     dx,0
        jz      select_dib_small_dib        ; is dx==0 (ie < 64k)

        mov     ax,__AHINCR                 ; Mark as a HUGE bitmap!
        mov     es:[di].bmSegmentIndex,ax

select_dib_small_dib:
        ;
        ;   save the lpBitmapInfo pointer away so we can get it back if needed
        ;
        mov     dx,ds
        mov     es:[di].bmlpPDevice.sel,dx
        mov     es:[di].bmlpPDevice.off,si

select_dib_exit_ok:
        mov     ax,1

select_dib_exit:
cEnd

sEnd

end
