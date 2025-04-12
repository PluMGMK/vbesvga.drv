;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scanline.asm
;
; Copyright (c) 1991 Microsoft Corporation.  All Rights Reserved.
;
; The new improved scanline.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.286
?PLM=1
?WIN=1

incLogical	= 1			; Include control for gdidefs.inc
incDrawMode	= 1			; Include control for gdidefs.inc
incOutput       = 1                     ; Include control for gdidefs.inc

        .xlist
	include cmacros.inc
	include gdidefs.inc
	include display.inc
	include macros.mac
        include njumps.mac
	include vgareg.inc
        .list

ifdef PALETTES
	externB PaletteModified 	; Set when palette is modified
        externFP TranslateBrush         ; 'on-the-fly' translation of brush
        externFP TranslatePen           ; 'on-the-fly' translation of pen
        externFP TranslateTextColor     ; 'on-the-fly' translation of textcol
endif

ifdef	EXCLUSION
	externFP exclude_far		; Exclude area from screen
	externFP unexclude_far		; Clear excluded area
endif

	externFP prep_pattern_far	; In BLTUTIL.ASM
	externFP fill_solid_far		; In ROBJECT.ASM

rscan_type	STRUC

rsiterate       db      0       ;flag: if non 0 then in a Begin/End loop
rstype          db      0       ;dev type:0 = screen, 1 = clr mem, 2 mono mem
rscolor_pattern db      SIZE_PATTERN * SIZE_PATTERN * 4 DUP(?)
rsmono_pattern  db      SIZE_PATTERN DUP (?)
rsstyle         dw      0
rsaccel         db      0
rspattern_len	db	?	;length of a pattern line in bytes
rsxpar_mask     db      SIZE_PATTERN DUP(?)
rsoutput        dw      0       ;rop and bg mode specific output routine
rscan_type      ENDS


sBegin  Data
        externB enabled_flag            ; Non-zero if output allowed
        externW ScratchSel
	externB abPaletteAccl
	externW ScreenSelector
public	rscan
rscan           db      (size rscan_type) DUP (?)


;MONO_TYPE       EQU     0
;COLOR_TYPE      EQU     1
;SCREEN_TYPE     EQU     2

MONO_TYPE       EQU     1
BIT4_TYPE       EQU     4
COLOR_TYPE      EQU     8
SCREEN_TYPE	EQU	2

sEnd	Data

createSeg _SCANLINE,ScanlineSeg,word,public,CODE
sBegin	ScanlineSeg
assumes cs,ScanlineSeg


mono_rop_and_mode_output	LABEL	WORD

dw	 mono_xpar_rop_0
dw       mono_xpar_rop_1
dw       mono_xpar_rop_2
dw       mono_xpar_rop_3
dw       mono_xpar_rop_4
dw       mono_xpar_rop_5
dw       mono_xpar_rop_6
dw       mono_xpar_rop_7
dw       mono_xpar_rop_8
dw       mono_xpar_rop_9
dw       mono_xpar_rop_a
dw       mono_xpar_rop_b
dw       mono_xpar_rop_c
dw       mono_xpar_rop_d
dw       mono_xpar_rop_e
dw       mono_xpar_rop_f

dw       mono_opaque_rop_0
dw	 mono_opaque_rop_1
dw	 mono_opaque_rop_2
dw	 mono_opaque_rop_3
dw	 mono_opaque_rop_4
dw	 mono_opaque_rop_5
dw	 mono_opaque_rop_6
dw	 mono_opaque_rop_7
dw	 mono_opaque_rop_8
dw	 mono_opaque_rop_9
dw	 mono_opaque_rop_a
dw	 mono_opaque_rop_b
dw	 mono_opaque_rop_c
dw	 mono_opaque_rop_d
dw	 mono_opaque_rop_e
dw	 mono_opaque_rop_f

color_rop_and_mode_output	LABEL	WORD

dw	 color_xpar_rop_0
dw	 color_xpar_rop_1
dw	 color_xpar_rop_2
dw	 color_xpar_rop_3
dw	 color_xpar_rop_4
dw	 color_xpar_rop_5
dw	 color_xpar_rop_6
dw	 color_xpar_rop_7
dw	 color_xpar_rop_8
dw	 color_xpar_rop_9
dw	 color_xpar_rop_a
dw	 color_xpar_rop_b
dw	 color_xpar_rop_c
dw	 color_xpar_rop_d
dw	 color_xpar_rop_e
dw	 color_xpar_rop_f

dw	 color_opaque_rop_0
dw       color_opaque_rop_1
dw       color_opaque_rop_2
dw       color_opaque_rop_3
dw       color_opaque_rop_4
dw       color_opaque_rop_5
dw       color_opaque_rop_6
dw       color_opaque_rop_7
dw       color_opaque_rop_8
dw       color_opaque_rop_9
dw       color_opaque_rop_a
dw       color_opaque_rop_b
dw       color_opaque_rop_c
dw       color_opaque_rop_d
dw       color_opaque_rop_e
dw       color_opaque_rop_f

;--------------------------------------------------------------------------;
;
; DO_SCANLINES
;
; Entry:
;	None
; Return:
;	AX = Non-zero to show success
; Error Returns:
;	None
; Registers Preserved:
;	SI,DI,ES,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,FLAGS
;
;--------------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

cProc   do_scanlines,<FAR,PUBLIC,WIN,PASCAL,NODATA>,<si,di,es,ds>
        parmD   lp_dst_dev              ; --> to the destination
        parmW   style                   ; Output operation
        parmW   count                   ; # of points
        parmD   lp_points               ; --> to a set of points
        parmD   lp_phys_pen             ; --> to physical pen
        parmD   lp_phys_brush           ; --> to physical brush
        parmD   lp_draw_mode            ; --> to a Drawing mode
        parmD   lp_clip_rect            ; --> to a clipping rectange if <> 0

	localB	pixbytes
        localB  current_mono_pattern
        localB  current_xpar_mask
        localV  current_color_pattern,SIZE_PATTERN*4
        localW  start_of_scan           ;address of start of scanline
	localW	bank_of_scan		;bank containing start_of_scan
        localW  draw_output             ;rop and bg mode specific routine
	localW	exclude_flag
cBegin
	WriteAux  <'Scanline'>
	cld				; We are forever doing this

        mov     ax      ,DataBASE
	mov	es	,ax

	assumes ds,nothing
	assumes es,Data

	lds	si	,lp_points
	mov	ax	,ds
	or	ax	,si
        jz      do_scanline_error

        cmp     es:rscan.rsiterate, 0   ;if we are in a begin/end scanline
        jne     bracketed_do_scanline   ;   loop then do not need init stuff

	call	do_begin_scanline
	jc	do_scanline_error

bracketed_do_scanline:
        mov     al,es:[rscan.rstype]
        cmp     al,MONO_TYPE
        je      mono_main_loop
        jmp     color_main_loop         ;this will become screen main loop

do_scanline_error:
        xor     ax,ax
        jmp     do_scanline_exit

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;  mono_main_loop
;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
public	mono_main_loop
mono_main_loop:
	dec	count
        nje     do_scanline_done                  ;   then done

	mov	ax	,es:[rscan.rsoutput]
	mov	draw_output ,ax

	lds	si	,lp_points
						  ;use ycoord to determine
	mov	bx	,[si].ycoord		  ; which byte of the xpar
	mov	ax	,bx
	and	bx	,7			  ; mask and mono pattern to
	mov	cl	,es:[rscan.rsxpar_mask][bx]  ; use. Then place these
	mov	current_xpar_mask, cl		  ; variables on the stack.
	mov	cl	,es:[rscan.rsmono_pattern][bx]
	mov	current_mono_pattern, cl

        les     di,lp_dst_dev
        assumes es,nothing

        call    bmp_ptr
        mov     start_of_scan,di

        add     si      ,4

public	mono_main_draw_loop
mono_main_draw_loop:

	lodsw
	mov	dx	,ax
	lodsw				;dx:ax = xstart:xend
	mov	di	,dx		;compute start addr of interval
	shiftr	di	,3
	add	di	,start_of_scan	;compute left byte masks
	mov	bx	,dx		;
	and	bx	,7
	mov	cl	,cs:[mono_left_edge_mask][bx]
	mov	bx	,ax		;compute right edge byte mask
	and	bx	,7
	mov	ch	,cs:[mono_right_edge_mask][bx]
	and	dx	,not 7		;compute number of whole bytes
	and	ax	,not 7
	sub	ax	,dx
	shiftr	ax	,3
	jne	mono_main_width_bigger_than_a_byte

	and	cl	,ch		;width less than 1 byte, so combine
	mov	ch	,0		;the left and right masks into the
	inc	ax			;left mask and set right mask to 0

mono_main_width_bigger_than_a_byte:
	dec	ax
	mov	bx	,cx		;bh:bl = right:left edge masks
	mov	cx	,ax
	mov	ah	,current_mono_pattern
	and	ah	,current_xpar_mask
	call	draw_output		;do the output rop routine

	dec	count
        jne     mono_main_draw_loop

	jmp	do_scanline_done

mono_left_edge_mask	LABEL	BYTE
db	0FFH, 07FH, 03FH, 01FH, 00FH, 007H, 003H, 001H

mono_right_edge_mask	LABEL	BYTE
db	000H, 080H, 0C0H, 0E0H, 0F0H, 0F8H, 0FCH, 0FEH

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;  color_main_loop
;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
        assumes ds,nothing
	assumes es,Data

public  color_main_loop
color_main_loop:
	dec	count
        nje     do_scanline_done                ;   then done

	mov	ax	,es:[rscan.rsoutput]
        mov     draw_output ,ax

        mov     exclude_flag ,0
	cmp	es:[rscan.rstype] ,SCREEN_TYPE
	jne	color_main_loop_noex

@@:
        mov     al,es:[enabled_flag]            ; check for a disabled display
        or      al,al
        njz     do_scanline_done

ifdef EXCLUSION
	mov	exclude_flag ,1
	lds	si	,lp_points
	mov	dx	,[si].ycoord
	mov	di	,dx
	mov	bx	,count
	shiftl	bx	,2
	mov	cx	,[si+4].xcoord
	mov	si	,[bx + si].ycoord
	push	es
	call	exclude_far
        pop     es
endif

color_main_loop_noex:
	lds	si	,lp_points
        mov     bx      ,[si].ycoord              ;use ycoord to determine
	mov	ax	,bx			  ; which byte of the xpar
	and	bx	,7
	mov	cl	,es:[rscan.rsxpar_mask][bx]  ; mask and mono pattern to
	mov	current_xpar_mask, cl		  ; use. Then place these
						  ; variables on the stack.
	errnz	SIZE_PATTERN-8
	; multiply BL by number of bytes per pattern line
	xchg	ax	,bx
	mul	es:[rscan.rspattern_len]
	xchg	ax	,bx

	push	ds
	mov	dx	,si

	mov	cx	,es
	mov	si	,ss
	mov	ds	,cx
	mov	es	,si
        assume  es:nothing

	lea	di	,current_color_pattern
	lea	si	,rscan.rscolor_pattern[bx]
	mov	cl	,ds:[rscan.rspattern_len]
	shr	cl	,1	; convert to word count
	xor	ch	,ch
	cld
	rep	movsw

	; restore the pointer to the list of points
	mov	si	,dx
	pop	ds

        les     di,lp_dst_dev
        push    es:[di].bmType                  ; save device type

	mov	cl	,es:[di.bmBitsPixel]
	shr	cl	,3		; convert to bytes
	mov	[pixbytes],cl

	call	bmp_ptr 			; set ES:DI --> scan line
        mov     start_of_scan ,di               ; save offset

	mov	bank_of_scan,-1			; default to no banking
        pop     ax                              ; get BITMAP type back
        or      ax,ax                           ; is it the device?
        jz      @f                              ;   No

        SET_BANK                                ; set bank iff DEVICE
	mov	bank_of_scan,dx
@@:

        lea     bx      ,[si+4]

public	color_main_draw_loop
color_main_draw_loop:

	mov	ax	,[bx]			;ax = xstart
	add	bx	,2
	mov	cx	,ax			;save it
	and	cx	,7			;compute the pattern rotation
	lea	si	,current_color_pattern

	mov	dl	,pixbytes
	push	ax
	mov	al	,cl
	mul	dl
	add	si	,ax
	pop	ax

	mov	di	,start_of_scan
	xor	dh	,dh
	mul	dx
	add	di	,ax
	jnc	@F
	mov	dx	,bank_of_scan
	inc	dx
	jz	@F
	SET_BANK

@@:	mov	dl	,1			;dl will have 1 in the bit
	rol	dl	,cl			;position corresponding to
	mov	dh	,current_xpar_mask	;the current pattern byte
	rol	dh	,cl			;rotate the xpar mask

	mov	cx	,[bx]			;cx = xend
	add	bx	,2

	xchg	cx	,ax
	push	dx
	mov	dl	,pixbytes
	xor	dh	,dh
	mul	dx
	pop	dx
	xchg	cx	,ax

	sub	cx	,ax			;cx = xend - xstart
	jz	color_main_draw_loop_skip
	call	draw_output

color_main_draw_loop_skip:
	dec	count
        jne     color_main_draw_loop

do_scanline_color_done:

ifdef EXCLUSION
	cmp	exclude_flag ,1
	jne	do_scanline_done
        call    unexclude_far
endif

do_scanline_done:
        mov     ax,1                    ; show success

do_scanline_exit:

cEnd

;--------------------------------------------------------------------------;
;
; BEGIN_SCANLINE
;
; Entry:
;	None
; Return:
;	AX = Non-zero to show success
; Error Returns:
;	None
; Registers Preserved:
;	SI,DI,ES,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,FLAGS
;
;--------------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

cProc   begin_scanline,<FAR,PUBLIC,WIN,PASCAL,NODATA>,<si,di,es,ds>
        parmD   lp_dst_dev              ; --> to the destination
        parmW   style                   ; Output operation
        parmW   count                   ; # of points
        parmD   lp_points               ; --> to a set of points
        parmD   lp_phys_pen             ; --> to physical pen
        parmD   lp_phys_brush           ; --> to physical brush
        parmD   lp_draw_mode            ; --> to a Drawing mode
        parmD   lp_clip_rect            ; --> to a clipping rectange if <> 0
cBegin
        mov     cx,DataBASE
        mov     es,cx                   ; cx holds ds from 'output' fixup

        assumes ds,nothing
	assumes es,Data

	call	do_begin_scanline

	mov	es:[rscan.rsiterate], al ;Flag start of scanline loop
cEnd

;--------------------------------------------------------------------------;
;
; DO_BEGIN_SCANLINE
;
; Entry:
;	None
; Return:
;	AX = 1 to show success, 0 to show failure
; Error Returns:
;	None
; Registers Preserved:
;	SI,DI,ES,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,FLAGS
;
;--------------------------------------------------------------------------;

        assumes ds,nothing
	assumes es,Data

do_begin_scanline proc near

        lds     si      ,lp_dst_dev

	cmp	[si].bmType, 0		;if the bitmap type is 0 then
        jne     begin_scanline_screen   ;  the device is the screen

        mov     bl,[si].bmBitsPixel
        mov     es:[rscan.rstype] ,bl   ;mark the type of the dst dev

        cmp     bl, 8                   ;if there are 8 bits/pixel then
        je      begin_scanline_color    ;  the device is color memory
        cmp     bl, 1                   ;if there are 1 bits/pixel then
        je      begin_scanline_mono     ;  the device is mono

begin_scanline_error:
        xor     ax,ax
	stc
	ret

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;  begin_scanline_mono
;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
public  begin_scanline_mono
begin_scanline_mono:

        xor     bh,bh                   ;mono dest
	call	get_fill_data		;returns bx as the background mode
                                        ;        ax is the rop # [0-F]
	jc	begin_scanline_error

	shiftl	bx	,4
	add	bx	,ax
	shiftl	bx	,1
	and	bx	,3FH
        mov     ax      ,DataBASE
	mov	es	,ax
	mov	ax	,cs:[mono_rop_and_mode_output][bx]
	mov	es:[rscan.rsoutput] ,ax

        jmp     begin_scanline_done

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
;  begin_scanline_color
;
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
        assumes ds,nothing
	assumes es,Data

begin_scanline_screen:
        mov     bl      ,SCREEN_TYPE
	mov	es:[rscan.rstype] ,bl	;mark the type of the dst dev

        public  begin_scanline_color
begin_scanline_color:

	lds	di	,[lp_dst_dev]

        mov     bh,0FFh                 ;color dest
	call	get_fill_data		;returns bx as the background mode
					;	 ax is the rop # [0-F]
	jc	begin_scanline_error

@@:
	shiftl	bx	,4
	add	bx	,ax
	shiftl	bx	,1
        and     bx      ,3FH
        mov     ax      ,DataBASE
	mov	es	,ax
	mov	ax	,cs:[color_rop_and_mode_output][bx]
        mov     es:[rscan.rsoutput] ,ax

        errn$   begin_scanline_done

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -;
begin_scanline_done:
        mov     ax,1                    ; show success
	clc
        ret

do_begin_scanline endp

;--------------------------------------------------------------------------;
;
; END_SCANLINE
;
; Entry:
;	None
; Return:
;	AX = Non-zero to show success
; Error Returns:
;	None
; Registers Preserved:
;	SI,DI,ES,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,FLAGS
;
;--------------------------------------------------------------------------;
        assume  ds:nothing
        assume  es:nothing

cProc   end_scanline,<FAR,PUBLIC,WIN,PASCAL,NODATA>,<si,di,es,ds>
	parmD	lp_dst_dev		; --> to the destination
	parmW	style			; Output operation
	parmW	count			; # of points
	parmD	lp_points		; --> to a set of points
	parmD	lp_phys_pen		; --> to physical pen
	parmD	lp_phys_brush		; --> to physical brush
	parmD	lp_draw_mode		; --> to a Drawing mode
	parmD	lp_clip_rect		; --> to a clipping rectange if <> 0

cBegin
        mov     ax,DataBASE
        mov     ds,ax

	mov	ds:[rscan.rsiterate] ,0
cEnd

;--------------------------------------------------------------------------;
;
;	get_fill_data
;
;	The routine will only copy the necessary data to local storage
;	depending upon the background mode (opaque or transparent) and the
;       type of the destination (mono or color).
;
;       entry
;           BL = device type
;           BH = color/mono     0=mono, FF=color
;       exit
;           BX = BkMode     0=TRANSPARENT, 1=OPAQUE
;           AX = Rop2       0-15
;
;--------------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,Data

	public	get_fill_data
get_fill_data	proc near

	lds	si	,lp_phys_brush
	mov	ax	,ds
	or	ax	,si
	jne	get_fill_brush

get_fill_pen:

        lds     si,lp_phys_pen                  ; --> physical pen
	cmp	es:PaletteModified,0ffh ; was the palette modified ?
	jne	no_pen_xlat_needed
	cmp	bl	,SCREEN_TYPE
	jne	no_pen_xlat_needed

        smov    ds      ,DataBASE
	arg	lp_phys_pen
        cCall   TranslatePen                 ; translate the pen
        mov     ds      ,dx
        mov     si      ,ax                  ; load the local pen pointer

no_pen_xlat_needed:

	mov	ax	,[si].oem_pen_pcol.lo
	mov	dx	,[si].oem_pen_pcol.hi
	mov	di	,DataOFFSET rscan.rscolor_pattern
	call	fill_solid_far

	; figure out how much pattern has been put at ES:DI
	mov	cx	,di
	sub	cx	,DataOFFSET rscan.rscolor_pattern
	; get length of a single line
	shr	cx	,3
	errnz	SIZE_PATTERN-8
	mov	[rscan.rspattern_len],cl

	mov	cx	,SIZE_PATTERN
	mov	al	,0FFH
	mov	di	,DataOFFSET rscan.rsxpar_mask
	rep	stosb

	shr	ah	,1			;MONO BIT of the pen color
	sbb	al	,al			; determines the mono pattern
	mov	cx	,SIZE_PATTERN
	mov	di	,DataOFFSET rscan.rsmono_pattern
        rep     stosb

	mov	bx	,OPAQUE - 1
	lds	si	,lp_draw_mode
	mov	ax	,[si].Rop2
	dec	ax
	clc
	ret


get_fill_brush:

	cmp	es:PaletteModified,0ffh ; was the palette modified ?
	jne	no_brush_xlat_needed
	cmp	bl	,SCREEN_TYPE
	jne	no_brush_xlat_needed

        smov    ds      ,DataBASE
	arg	lp_draw_mode
        cCall   TranslateTextColor      ; translate foreground/background cols
        mov     seg_lp_draw_mode,dx
        mov     off_lp_draw_mode,ax     ; load the local pen pointer

        smov    ds      ,DataBASE
	arg	lp_phys_brush		;this call preserves es,si,di,bx,cx
	cCall	TranslateBrush		; translate the brush
	mov	ds	,dx
        mov     si      ,ax                  ; load the local pen pointer

no_brush_xlat_needed:
	mov	cx	,es
        push    bp
	les	di	,lp_draw_mode
	assume	es:nothing
	; push the background then foreground on the stack
	push	es:[di].bkColor.hi
	push	es:[di].bkColor.lo
	push	es:[di].TextColor.hi
	push	es:[di].TextColor.lo
	; then point BP at them
        mov     bp      ,sp
	; point ES:DI back at the pattern dest
	mov	es	,cx
	assumes es,Data
	mov	di	,DataOFFSET rscan.rscolor_pattern
	; indicate whether mono or colour
	mov	dl	,bh

	call	prep_pattern_far
	add	sp	,8
        pop     bp

	; figure out how much pattern has been put at ES:DI
	mov	cx	,di
	sub	cx	,DataOFFSET rscan.rscolor_pattern
	; get length of a single line
	shr	cx	,3
	errnz	SIZE_PATTERN-8
	mov	[rscan.rspattern_len],cl

get_fill_brush_1:
	;DS:SI should now point to the "common" part of the brush,
	; so this offset is valid:
        mov     cx	,[si].oem_brush_style
	;TODO: Move these checks back to the beginning. Right now there's no
	; straightforward way to get the style before we've run all the way
	; through the preprocessing routine...
	cmp	cx,MaxBrushStyle	; Legal?
	ja	get_fill_brush_2	; Outside range, return error
	cmp	cx,BS_HOLLOW		; Hollow?
	jne	@F			; If yes, return now.

get_fill_brush_2:
	stc
	ret

@@:
        lds     si      ,lp_draw_mode
        mov     bx      ,OPAQUE-1       ; default to OPAQUE mode

        cmp     cx      ,BS_HATCHED     ; we only care about opaque/trans
        jne     get_fill_brush_0        ; for hatched brushes

        mov     cx      ,[si].bkMode
        cmp     cx      ,OPAQUE
        je      get_fill_brush_0
        dec     bx                      ; set TRANSPARENT mode
        jmps    get_fill_brush_exit

        errnz   OPAQUE-2
        errnz   TRANSPARENT-1

get_fill_brush_0:

	mov	cx	,SIZE_PATTERN
	mov	al	,0FFH
	mov	di	,DataOFFSET rscan.rsxpar_mask
	rep	stosb

get_fill_brush_exit:

        mov     ax      ,[si].Rop2      ; get ROP 1-16
        dec     ax                      ; make 0-15
	clc
        ret

get_fill_data	endp

	include monostuf.inc
        include clrstuff.inc

;-----------------------------------------------------------------------;
; bmp_ptr
;
; computes a pointer to a given BMP scanline
;
; Entry:
;       ES:DI           pointer to the PDevice
;       ax              index of scanline to point to
; Returns:
;       ES:DI           pointer to begining of given scanline
;
; Error returns:
;       none
;
; Registers Destroyed:
;       AX,BX,CX,DX,FLAGS
;
; History:
;
;  Mon 26-Mar-1990 18:37:23  -by-  Todd Laney [ToddLa]
; Wrote it!
;-----------------------------------------------------------------------;
	assumes ds,nothing
	assumes es,nothing

bmp_ptr proc near

        mov     bx,es:[di].bmBits.sel
        mov     cx,es:[di].bmSegmentIndex
        jcxz    bmp_ptr_small

        mov     dx,es:[di].bmScanSegment

bmp_ptr_loop_huge:
        add     bx,cx
        sub     ax,dx
        jae     bmp_ptr_loop_huge

        sub     bx,cx
        add     ax,dx

bmp_ptr_small:
        mul     es:[di].bmWidthBytes
        add     ax,es:[di].bmBits.off
        adc     dl,dh

        mov     es,bx
        mov     di,ax

        ret

bmp_ptr endp

_SCANLINE       ends

       end
