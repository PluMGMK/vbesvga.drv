        page    ,132
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; pixel.asm
;
; Copyright (c) 1991 Microsoft Corporation.  All Rights Reserved.
;
; This module contains the Set/Get Pixel routine.
;
; Created: 22-Feb-1987
;
; Exported Functions:   Pixel
;
; Public Functions:     none
;
; Public Data:          none
;
; General Description:
;
;   Pixel is used to either set a pixel to a given color with the
;   current binary raster operation, or to return the color of the
;   the pixel at the given location.
;
; Restrictions:
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        ??_out  Pixel
;
incDrawMode     = 1                     ; Include control for gdidefs.inc
;
        .xlist
        include cmacros.inc
        include gdidefs.inc
        include display.inc
        include cursor.inc
        include ega.inc
        include macros.mac
        .list
;
	externD adPalette
	externFP sum_rgb_alt_far	; Color mapping routine
;
ifdef   EXCLUSION
        externFP exclude_far            ; Exclude area from screen
        externFP unexclude_far          ; Clear excluded area
endif
;
; Define the type flags used to determine which type of scan needs to be
; performed (color or mono).
;
;COLOR_OP	equ	00000001b

MONO_OP         equ     MONO_BIT

;END_OP 	equ	MONO_BIT shl 1 + (1 shl (NUMBER_PLANES))
;

sBegin  Data

        externB enabled_flag            ; Non-zero if output allowed
	externW	ColourFormat

sEnd    Data

ifdef   PALETTES
	externB PaletteModified		; Set when palette is modified
	externFP TranslateBrush		; 'on-the-fly' translation of brush
	externFP TranslatePen		; 'on-the-fly' translation of pen
	externFP TranslateTextColor	; 'on-the-fly' translation of textcol
endif
;
;
createSeg _PIXEL,PixelSeg,word,public,CODE
sBegin  PixelSeg
assumes cs,PixelSeg

        .xlist
        include drawmod2.asm
        .list
;
rot_bit_tbl     label   byte
                db      10000000b       ; Table to map mono bit index into
                db      01000000b       ; a bit mask
                db      00100000b
                db      00010000b
                db      00001000b
                db      00000100b
                db      00000010b
                db      00000001b
;
;
;--------------------------Exported-Routine-----------------------------;
; Pixel
;
;   Set or Get a Given Pixel
;
;   The given pixel is set to the given color or the given pixel's
;   physical color is returned.
;
;   The physical device may be the screen, a monochrome bitmap, or a
;   bitmap in our color format.
;
;   There will be error checking to see if the bitmap is in our color
;   format. If it isn't, then we'll treat the bitmap as monochrome.
;
;   If lp_draw_mode is NULL, then the physical color of the pixel is
;   returned.  If lp_draw_mode isn't NULL, then the pixel will be set
;   to the physical color passed in, combined with the pixel already
;   at that location according to the raster-op in lp_draw_mode.  Pixel
;   doesn't pay attention to the background mode.
;
;   No clipping of the input value is required.  GDI clips the
;   coordinate before it is passed in, for both Set and Get.
;
; Entry:
;       EGA registers in default state
; Returns:
;       GET operation:
;               DX:AX = physical color if get pixel
;                       For mono:
;				DX=ff00, AX=00ff if set,
;				DX=ff00, AX=0000 if clear.
;                       For Color:
;				DX=ff00, AX=00xx, where xx = 8 bit value
;       SET operation:
;               DX:AX = positive if no error and set was OK.
;
; Error Returns:
;       DX:AX = 8000:0000H if error occured
; Registers Preserved:
;       SI,DI,ES,DS,BP
; Registers Destroyed:
;       AX,BX,CX,DX,FLAGS
; Calls:
;       exclude_far     (far version of exclude)
;       unexclude_far   (far version of unexclude)
; History:
;	Wed 01-Feb-1989 -by-  Doug Cody, Video Seven, Inc
;       Modified for 256 color support
;
;       Sat 31-Oct-1987 00:21:06 -by-  Walt Moore [waltm]
;       Added clipping of the (X,Y)
;
;       Tue 18-Aug-1987 14:50:37 -by-  Walt Moore [waltm]
;       Added test of the disabled flag.
;
;       Wed 12-Aug-1987 19:55:20 -by-  Walt Moore [waltm]
;       Moved to _PIXEL.  Removed stack checking.
;
;       Thu 06-Aug-1987          -by-  Mitch London [mitchl]
;       Put code into segment _LINES
;
;       Tue 03-Mar-1987 20:42:07 -by-  Kent Settle [kentse]
;       Moved a mov instruction in EGA ROP handling code.
;
;       Sun 22-Feb-1987 16:29:09 -by-  Walt Moore [waltm]
;       Created.
;-----------------------------------------------------------------------;
;
;
;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;
;
        assumes ds,Data
        assumes es,nothing
;
cProc   Pixel,<FAR,PUBLIC,WIN,PASCAL>,<si,di,es,ds>
        parmD   lp_device               ; Pointer to device.
        parmW   x                       ; X coordinate of pixel.
        parmW   y                       ; Y coordinate of pixel.
        parmD   p_color                 ; Physical color to set pixel to.
        parmD   lp_draw_mode            ; Drawing mode to use, or null if Get.
        localB  is_device               ; set non-zero if the device.
        localB  PCurVidSel              ; current video bank select
	localW	colour_format		; copy of this on stack
;
cBegin
;
WriteAux        <'PIXEL'>
;
;----------------------------------------------------------------------------;
; if the palette manager is supported, do the on-the-fly translation now     ;
;----------------------------------------------------------------------------;
;
ifdef   PALETTES
	cmp	PaletteModified,0ffh	; was the palette modified ?
	jnz	no_translation_needed
;
	push	ds			; save
	lds	si,lp_device		; load the device
	lodsw				; load the type
	pop	ds			; restore own segment
	or	ax,ax			; is it a physical device ?
        jz      no_translation_needed   ; no, so no translation
;
	arg	lp_draw_mode
	cCall	TranslateTextColor	; translate foreground/background cols
	mov	seg_lp_draw_mode,dx
	mov	off_lp_draw_mode,ax	; load the local pen pointer
;
no_translation_needed:

endif
;
;----------------------------------------------------------------------------;
;
	; get the ColourFormat from DS before we point the segreg elsewhere...
	mov	ax,[ColourFormat]
	mov	colour_format,ax

        mov     al,enabled_flag         ; Load this before trashing DS
        lds     si,lp_device            ; --> physical device
;
        assumes ds,nothing
;
; If the X or Y coordinate is outside the surface of the bitmap or device,
; return an error code of 8000:0000.  The test will be performed as an
; unsigned compare to test for the range of 0:n-1.
;
        mov     cx,x
        cmp     cx,[si].bmWidth
        jae     pixel_clipped
        mov     cx,y
        cmp     cx,[si].bmHeight
        jae     pixel_clipped
;
        mov     cx,[si].bmType          ; Get device type
        jcxz    pixel_20                ; Memory bitmap, skip VGA specific code
        or      al,al
        jz      pixel_disabled          ; Disabled, return 8000:0000
;
;-------------------------
; D E V I C E   S E T U P
;-------------------------
;
        mov     is_device,al            ; Non-zero show this is the device
;
; This is the device.  The cursor must be excluded from the pixel
; that will be processed.  The innerloop mask for the device will
; be set for color.  The width of a plane will be set to 1 to flag
; to the loop code that this is COLOR (odd widths are illegal).
;
ifdef   EXCLUSION                       ; If exclusion required
        mov     cx,x                    ; Set left
        mov     dx,y                    ; top
        mov     si,cx                   ; right
        mov     di,dx                   ; bottom
        call    exclude_far             ; Exclude the area
endif
        lds     si,lp_device            ; --> physical device
        assumes ds,nothing
;
	mov	ax,[si].bmWidthBytes 	;Compute starting address of scan
        mul     y                       ; Better on 286 than explicit shifts
;
        add     ax,wptr [si].bmBits     ; add in magic offset
        adc     dl,dh
	mov	cx,[si].bmBitsPixel
	sar	cx,3			; divide by eight to get bytes
	xor	bx,bx
@@:	add	bx,x
	loop	@B
        add     ax,bx                   ; add in x offset
        adc     dl,dh

        SET_BANK                        ; perform the video h/w bank select
;
        mov     bx,[si].bmBits.sel      ; Set screen segment
        mov     ds,bx
        mov     si,ax                   ; DS:SI is pointer of the color pixel
;
        assumes ds,nothing              ; Don't allow addressing off DS
;
        mov     cl,p_color.pcol_Clr     ; Show color in case this is GetPixel
;
        mov     di,1                    ; Next scan index = 1 indicates display
        jmp     short pixel_70          ; (odd width is illegal)
;
pixel_clipped:
pixel_disabled:
        mov     dx,8000h
        xor     ax,ax
        jmp     pixel_exit
;
;
;-----------------------------------------------
; M O N O / C O L O R   B I T M A P   S E T U P
;-----------------------------------------------
;
; The device is a memory bitmap. If it is a huge bitmap, special processing
; must be performed to compute the Y address.
;
pixel_20:
        mov     is_device,cl            ; Show this is a bitmap
        mov     ax,y                    ; Need Y coordinate a few times
        xor     dx,dx                   ; Set segment bias to 0
        mov     cx,[si].bmSegmentIndex  ; Is this a huge bitmap?
        jcxz    pixel_40                ; No
;
; This is a huge bitmap. Compute which segment the Y coordinate is in.
; Assuming that no huge bitmap will be bigger than two or three segments,
; iteratively computing the value would be faster than a divide, especially
; if Y is in the first segment (which would always be the case for a huge
; color bitmap that didn't have planes >64K).
;
        mov     bx,[si].bmScanSegment   ; Get # scans per segment
;
pixel_30:
        add     dx,cx                   ; Show in next segment
        sub     ax,bx                   ; See if in this segment
        jnc     pixel_30                ; Not in current segment, try next
        add     ax,bx                   ; Restore correct Y
        sub     dx,cx                   ; Show correct segment
;
; Handle modifying Y for huge bitmaps is necessary.
;
; Currently:
;       AX     =  Y coordinate
;       DX     =  Segment bias for huge bitmaps
;       DS:SI --> PDevice
;
pixel_40:
        mov     di,[si].bmWidthBytes    ; Get index to next plane
	mov	bx,colour_format
        cmp     wptr [si].bmPlanes,bx	; color bit map?
        mov     bx,di                   ; (and Y multiplier)
        mov     cl,MONO_OP              ; cl = 1 (only plane 0 is on)
        jne     pixel_60                ; Not our color format, treat as mono
;
        mov     cl,p_color.pcol_Clr     ; load the 8 bit color
        mov     di,1                    ; force a change to display handling
        mov     is_device,1             ; fake it, color is same as display
;
pixel_60:
        add     dx,wptr [si].bmBits[2]  ; Compute segment of the bits
        mov     si,wptr [si].bmBits[0]  ; Get offset of the bits
        mov     ds,dx                   ; Set DS:SI --> to the bits
;
        assumes ds,nothing
;
        mul     bx                      ; Compute start of scan
        add     si,ax                   ; DS:SI--> start of scanline byte is in
        mov     ax,x                    ; Get X coordinate
        mov     bx,ax
        cmp     is_device,0             ; mono or color maps?
        jne     @F                      ; color use x as true pointer
        shiftr  ax,3                    ; AX = byte offset from start of scan
;
@@:
        add     si,ax                   ; ds:si --> byte of pixel
        and     bx,00000111B            ; Get bit mask for mono bit
        mov     ch,rot_bit_tbl[bx]      ; loaded for mono, ignored by color
;
;
;-----------------------------------------------------------
; D I S P A T C H   T O   G E T / S E T   O P E R A T I O N
;-----------------------------------------------------------
;
; Currently:
;       DS:SI --> the bitmap, to the exact byte
;       DI = Index to next plane of the scan
;            1 if the display (odd width illegal)
;       CH = rotation bit mask for mono maps
;
pixel_70:                               ; Display code enters here
        mov     dx,di                   ; Need index to next plane here
        mov     di,off_lp_draw_mode     ; If a drawmode was given
        mov     bx,seg_lp_draw_mode     ; then set the pixel, else
        mov     ax,bx                   ; return it's physical color
        or      ax,di
        jnz     pixel_100               ; Given, operation is set pixel
        jmp     pixel_200               ; Not given, return pixel color
;
;
;---------------------------------------
; S E T   P I X E L   O P E R A T I O N
;---------------------------------------
;
; The operation to be performed is SetPixel.  Currently:
;
;       DS:SI --> byte pixel is to be set in
;       BX:DI --> physical drawing mode
;       CH    =   bit mask
;       CL    =   color - pixel, mono - don't care
;       DX    =   Index to next plane
;                 1 if the display
;
pixel_100:
        mov     es,bx                   ; ES:DI --> drawmode
;
        assumes es,nothing
;
        mov     bx,es:[di].Rop2         ; Get drawing mode to use
        dec     bx                      ; Make it zero based
        and     bx,000Fh                ; Keep it valid
        test    dl,00000001b            ; mono bitmap?
        jz      pixel_130               ; Yes, can't use special drawing modes
;
;-----------------------------------------------
; D I S P L A Y / C O L O R   S E T   P I X E L
;-----------------------------------------------
;
        test    dm_flags[bx],SINGLE_OK
        jz      pixel_110
        and     cl,dm_pen_and[bx]       ; Set correct color for the ROP
        xor     cl,dm_pen_xor[bx]
        mov     ah,dm_data_r[bx]
        shiftr  ah,3
        or      ah,ah
        jne     dr_more1
        mov     [si],cl
        jmp     short dr_morex
dr_more1:
        dec     ah
        jne     dr_more2
        and     [si],cl
        jmp     short dr_morex
dr_more2:
        dec     ah
        jne     dr_more3
        or      [si],cl
        jmp     short dr_morex
dr_more3:
        xor     [si],cl
dr_morex:
        jmp     pixel_160
;
;---------------------------------------
;       2 pass ROP
;---------------------------------------
;
pixel_110:
        xor     cl,dm_pen_xor[bx]
        mov     ch,cl
        not     ch
        mov     ax,cx
        and     cl,dm_pen_and[bx]
        and     ch,[si]
        or      cl,ch

        mov     ch,cl
        not     ch
        and     ch,ah
        and     cl,al
        or      cl,ch
        mov     [si],cl
        jmp     short pixel_160
;
;
;------------------------------
; M O N O   S E T   P I X E L
;------------------------------
;
; The SetPixel operation is to be performed on a monochrome bitmap.
;
; The loop will use the following registers:
;
;       CH The bitmask
;       BX draw mode
;       DS:SI destination pointer
;
pixel_130:
        shl     bx,1                    ; Set rop_indexes table address
        lea     di,cs:rop_indexes[bx]   ; for the given rop
        mov     ah,ch                   ; cl = change bit mask
        mov     al,ah
        not     ah                      ; ch = save bit mask
        mov     ch,p_color.pcol_Clr
        mov     bl,ch                   ; Get pen color
        and     bl,cl                   ; Mask color for current plane
        cmp     bl,1                    ; 'C' if pen is a 0 for this plane
        sbb     bx,bx                   ; BX = -1 if black, 0 if white
        inc     bx                      ; BX = 0  if black, 1 if white
        mov     bl,bptr cs:[di][bx]     ; Get delta to the drawing function
        add     bx,PixelSegOFFSET pixel_base_address
        jmp     bx                      ; Invoke the function
;
pixel_base_address:                     ; Deltas are computed from here
;
pixel_is_0:
        and     [si],ah                 ; Set pixel to 0
        jmpnext
;
pixel_is_inverted:
        xor     [si],al                 ; Invert destination
        jmpnext
;
pixel_is_1:
        or      [si],al                 ; Set pixel to 1
        jmpnext stop
;
pixel_is_dest:
;       nop operation
;
pixel_160:
        xor     ax,ax                   ; Set DX:AX = 0:0
        cwd
        jmp     short pixel_300         ; Return 0:0 to show success
;
;
;---------------------------------------
; G E T   P I X E L   O P E R A T I O N
;---------------------------------------
;
; The operation to be performed is get pixel.  The color of the pixel will be
; returned.  The color of the pixel will be composed from all planes if a
; color bitmap and the result "AND"ed to produce the mono bit in the physical
; color (this is the same as bitblt when blting from color to monochrome).
;
; If this is a monochrome bitmap, then the color will simply be black or white.
;
; Currently:
;
;       CH     =  bit mask
;       CL     =  loop mask
;       DX     =  index to next plane
;                 1 if physical device
;       DS:SI --> byte bit is to be set in
;
pixel_200:
	test	dl,00000001b		; mono bitmap?
        jne     pixel_250               ; No, go load it...
;
; mono map, isolate the bit & return some value
;
	mov	dx,0ff00h		; dx:ax = ff00:0000
	xor	ax,ax	 ; 0200h
        test    [si],ch                 ; pixel black?
	jz	pixel_exit		; yes, skip out...
	not	al	 ; 03ffh	; dx:ax = ff00:00ff
	jmp	short pixel_exit
;
pixel_250:
;
; color map, load the color & return in dx:ax
;
	mov	dx,0ff00h		; return ff00h in dx
	xor	ax,ax			; clear out ax
	lodsb				; grab the pixel
;
pixel_300:
        test    is_device,0FFh
        jz      pixel_exit

ifdef   EXCLUSION
        call    unexclude_far           ; Clear any exclude rectangle
endif

pixel_exit:

cEnd
;
;
; make_rop - Make a ROP For Pixel
;
; MakeROP makes a raster operation for the pixel routine.
; The raster operation generated is based on the following
; table which shows the ROP broken down into the boolean
; result for each plane based on what the pen color is for
; the plane.
;
;
;
;       Color     Result                        Color     Result
;
; DDx     0         0                   DPa       0         0
;         1         0                             1        dest
;
; DPon    0       ~dest                 DPxn      0       ~dest
;         1         0                             1        dest
;
; DPna    0        dest                 D         0        dest
;         1         0                             1        dest
;
; Pn      0         1                   DPno      0         1
;         1         0                             1        dest
;
; PDna    0         0                   P         0         0
;         1       ~dest                           1         1
;
; Dn      0       ~dest                 PDno      0       ~dest
;         1       ~dest                           1         1
;
; DPx     0        dest                 DPo       0        dest
;         1       ~dest                           1         1
;
; DPan    0         1                   DDxn      0         1
;         1       ~dest                           1         1
;
;
make_rop macro  l,ops
ifdef   PUBDEFS
pixel_&l&:                              ;; & keeps grep from matching
endif
irp x,<ops>
ifidn   <&&x>,<0>
        db      pixel_is_0-pixel_base_address
endif
ifidn   <&&x>,<1>
        db      pixel_is_1-pixel_base_address
endif
ifidn   <&&x>,<~dest>
        db      pixel_is_inverted-pixel_base_address
endif
ifidn   <&&x>,<dest>
        db      pixel_is_dest-pixel_base_address
endif
endm
endm
;
rop_indexes     label   byte
make_rop DDx,<0,0>
make_rop DPon,<~dest,0>
make_rop DPna,<dest,0>
make_rop Pn,<1,0>
make_rop PDna,<0,~dest>
make_rop Dn,<~dest,~dest>
make_rop DPx,<dest,~dest>
make_rop DPan,<1,~dest>
make_rop DPa,<0,dest>
make_rop DPxn,<~dest,dest>
make_rop D,<dest,dest>
make_rop DPno,<1,dest>
make_rop P,<0,1>
make_rop PDno,<~dest,1>
make_rop DPo,<dest,1>
make_rop DDxn,<1,1>
;
ifdef   PUBDEFS
        .xlist
	public	pixel_20
	public	pixel_30
	public	pixel_40
	public	pixel_60
	public	pixel_70
	public	pixel_100
	public	pixel_110
	public	pixel_130
	public	pixel_is_0
	public	pixel_is_inverted
	public	pixel_is_1
	public	pixel_is_dest
	public	pixel_160
	public	pixel_200
	public	pixel_300
	public	rop_indexes
        .list
endif
;
sEnd    PixelSeg
        end
