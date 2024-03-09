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
THE216	EQU	1

incLogical	= 1			; Include control for gdidefs.inc
incDrawMode	= 1			; Include control for gdidefs.inc
incOutput       = 1                     ; Include control for gdidefs.inc

        .xlist
	include cmacros.inc
	include gdidefs.inc
	include display.inc
;       include cursor.inc
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

rscan_type	STRUC

rsiterate       db      0       ;flag: if non 0 then in a Begin/End loop
rstype          db      0       ;dev type:0 = screen, 1 = clr mem, 2 mono mem
rscolor_pattern db      SIZE_PATTERN * SIZE_PATTERN  DUP(?)
rsmono_pattern  db      SIZE_PATTERN DUP (?)
rsstyle         dw      0
rsaccel         db      0
rsxpar_mask     db      SIZE_PATTERN DUP(?)
rsoutput        dw      0       ;rop and bg mode specific output routine
IF THE216
rop		dw	0
ENDIF
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

IF	THE216
sl216_mode_output	LABEL	WORD
dw	sl216_xpar_rop
dw      sl216_opaque_rop

PUBLIC	remap_slrop
remap_slrop	  LABEL   BYTE
DB	00H, 01H, 04H, 05H, 02H, 03H, 06H, 07H
DB	08H, 09H, 0CH, 0DH, 0AH, 0BH, 0EH, 0FH

PUBLIC	read_modify_write_needed_sl
read_modify_write_needed_sl	   LABEL   BYTE
DB	00H, 20H, 20H, 20H, 20H, 00H, 20H, 20H
DB	20H, 20H, 00H, 20H, 20H, 20H, 20H, 00H


ENDIF

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

        localB  current_mono_pattern
        localB  current_xpar_mask
        localV  current_color_pattern,8
        localW  start_of_scan           ;address of start of scanline
        localW  draw_output             ;rop and bg mode specific routine
	localW	exclude_flag
cBegin
	WriteAux  <'Scanline'>
	int	3
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
	je	@F
	jmp	color_main_loop_noex

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

IF	THE216
PUBLIC	the216_start
the216_start:
	test	byte ptr es:Video_Board_Flags,BOARD_FLAG_ENABLE_216  ;216?
	jnz	@F
	jmp	color_main_loop_noex
@@:
	mov	bx,es:[rscan.rop]
	mov	bl,cs:remap_slrop[bx]	;Oops! hardware rops are backwards
	test	cs:read_modify_write_needed_sl[bx],20H
	jz	@F
        jmp     color_main_loop_noex
@@:
	lds	si	,lp_points
	mov	ax,ds:[si + 6]
	sub	ax,ds:[si + 4]
	cmp	ax,24
	jae	@F
	jmp	color_main_loop_noex
@@:
        mov     bx      ,[si].ycoord              ;use ycoord to determine
	mov	ax	,bx			  ; which byte of the xpar
	and	bx	,7
	mov	cl	,es:[rscan.rsxpar_mask][bx]  ; mask to use and save
	mov	current_xpar_mask, cl		  ; on the stack

;	copy the pattern row into video memory so extended bg latches
;	   can be loaded

	push	ax

	mov	dx,VGAREG_SQ_ADDR	;find bank location of hardware cursor
	mov	al,0FFH 		; which is always the last bank in mem
	out	dx,al
	inc	dx
	in	al,dx
	and	al,60H

	shr	ax,3
	mov	dl,al
	SET_BANK

	push	es
	pop	ds
	mov	dx,ScreenSelector
	mov	es,dx
	mov	di,07FFFH - 100H - 03FH ;end of memory - 256 - 64

	shiftl	bx	,3
	mov	ax	,WORD PTR ds:[rscan.rscolor_pattern][bx + 0]
	stosw
	mov	ax	,WORD PTR ds:[rscan.rscolor_pattern][bx + 2]
	stosw
	mov	ax	,WORD PTR ds:[rscan.rscolor_pattern][bx + 4]
	stosw
	mov	ax	,WORD PTR ds:[rscan.rscolor_pattern][bx + 6]
	stosw
	mov	al,es:[di - 8]		;loads Xbg latches

	push	ds
	pop	es			;restore data segment into es

	mov	dx,VGAREG_SQ_ADDR
        mov     al,VGAREG_SQ_FOREBACK_MODE
        out     dx,al
        inc     dx
        in      al,dx                           ;use the bg latches as
        or      al,0CH                          ; input A into the ALU
        out     dx,al

        mov     dx,VGAREG_SQ_ADDR
        mov     ax,VGAREG_SQ_XALU_CONTROL +  (0C2H SHL 8)
	out	dx,ax				;enable XALU
	mov	bx,es:[rscan.rop]
	mov	bl,cs:remap_slrop[bx]	;Oops! hardware rops are backwards

        mov     al,VGAREG_SQ_XALU
        mov     ah,0CH                          ;bgrop = 'B' (input B to ALU)
        shl     bl,4
        or      ah,bl
        out     dx,ax                           ;specify the rop being used

	pop	ax
        les     di,lp_dst_dev
        assume  es:nothing
	mov	dx,es:[di].bmWidthBytes
	shr	dx,3
	mul	dx
	les	di,es:[di].bmBits
	add	di,ax
	adc	dl,0
	mov	start_of_scan ,di		; save offset
	SET_BANK

	lds	si	,lp_points
        add     si      ,4

public	sl216_main_draw_loop
sl216_main_draw_loop:

	mov	cx	,[si]			;ax = xstart
	and	cl,7
	mov	al,current_xpar_mask		;the current pattern byte
	rol	al,cl				;rotate the xpar mask
	xor	cl,7
	mov	bx,2
	shl	bx,cl
	dec	bx				;al holds left edge mask

	mov	cx,[si + 2]
	dec	cx
	and	cl,7
	mov	bh,80H
	sar	bh,cl				;ah holds right edge mask

	mov	dx,[si]
	cmp	dx,[si + 2]
	jae	sl216_main_draw_loop_skip

        shr     dx,3
	mov	cx,[si + 2]
	dec	cx
	shr	cx,3
	sub	cx,dx
	je	bpd_prep_combine_edges

	dec	cx
	jmp	short @F

bpd_prep_combine_edges:

	and	bl,bh
	sub	bh,bh
@@:
	mov	di,start_of_scan
	mov	dx,[si]
	add	si,4
	shr	dx,3
	add	di,dx
	call	draw_output

sl216_main_draw_loop_skip:
	dec	count
	jne	sl216_main_draw_loop

	mov	dx,VGAREG_SQ_ADDR
	mov	al,VGAREG_SQ_FOREBACK_MODE
	out	dx,al
	inc	dx
	in	al,dx
	and	al,NOT 0CH
	out	dx,al

	dec	dx
	mov	ax,VGAREG_SQ_XALU_CONTROL + (00H SHL 8)
	out	dx,ax
	jmp	do_scanline_color_done
ENDIF



color_main_loop_noex:
	lds	si	,lp_points
        mov     bx      ,[si].ycoord              ;use ycoord to determine
	mov	ax	,bx			  ; which byte of the xpar
	and	bx	,7
	mov	cl	,es:[rscan.rsxpar_mask][bx]  ; mask and mono pattern to
	mov	current_xpar_mask, cl		  ; use. Then place these
						  ; variables on the stack.
	shiftl	bx	,3
	mov	cx	,WORD PTR es:[rscan.rscolor_pattern][bx + 0]
	mov	WORD PTR [current_color_pattern + 0], cx
	mov	cx	,WORD PTR es:[rscan.rscolor_pattern][bx + 2]
	mov	WORD PTR [current_color_pattern + 2], cx
	mov	cx	,WORD PTR es:[rscan.rscolor_pattern][bx + 4]
	mov	WORD PTR [current_color_pattern + 4], cx
	mov	cx	,WORD PTR es:[rscan.rscolor_pattern][bx + 6]
	mov	WORD PTR [current_color_pattern + 6], cx

        les     di,lp_dst_dev
        assume  es:nothing

        push    es:[di].bmType                  ; save device type

	call	bmp_ptr 			; set ES:DI --> scan line
        mov     start_of_scan ,di               ; save offset

        pop     ax                              ; get BITMAP type back
        or      ax,ax                           ; is it the device?
        jz      @f                              ;   No

        SET_BANK                                ; set bank iff DEVICE
@@:

        add     si      ,4
        mov     bx      ,si

public	color_main_draw_loop
color_main_draw_loop:

	mov	ax	,[bx]			;ax = xstart
	add	bx	,2
	mov	cx	,ax			;save it
	and	cx	,7			;compute the pattern rotation
	lea	si	,current_color_pattern
	add	si	,cx
	mov	dl	,1			;dl will have 1 in the bit
	rol	dl	,cl			;position corresponding to
	mov	dh	,current_xpar_mask	;the current pattern byte
	rol	dh	,cl			;rotate the xpar mask
	mov	cx	,[bx]			;cx = xend
	add	bx	,2
	sub	cx	,ax			;cx = xend - xstart
	je	color_main_draw_loop_skip
	mov	di	,start_of_scan
	add	di	,ax
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

        mov     bh,0FFh                 ;color dest
	call	get_fill_data		;returns bx as the background mode
					;	 ax is the rop # [0-F]
	jc	begin_scanline_error

IF	THE216
PUBLIC	the216_begin
the216_begin:
	cmp	bl,0
	je	@F
        push    ax
        mov     ax      ,DataBASE
        mov     es      ,ax
        pop     ax
	test	byte ptr Video_Board_Flags,BOARD_FLAG_ENABLE_216  ;216?
	je	@F
	and	bx	,1
	shiftl	bx	,1
	and	ax,0FH
	mov	es:[rscan.rop],ax
	mov	ax	,cs:[sl216_mode_output][bx]
        mov     es:[rscan.rsoutput] ,ax
        jmp     short   begin_scanline_done
ENDIF

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

	mov	ax	,wptr [si].oem_pen_pcol.pcol_Clr
	mov	cx	,SIZE_PATTERN * SIZE_PATTERN
	mov	di	,DataOFFSET rscan.rscolor_pattern
	rep	stosb

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

	mov	ax,[si].oem_brush_style ; Get brush style
	cmp	ax,MaxBrushStyle	; Legal?
	ja	get_fill_brush_2	; Outside range, return error
	cmp	ax,BS_HOLLOW		; Hollow?
	je	get_fill_brush_2	; Yes, return now.

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
	mov	ax	,DataOFFSET rscan.rscolor_pattern
	les	di	,lp_draw_mode
	assume	es:nothing
        pushem  bp,si
        mov     bp      ,DataBASE
	call	pattern_preprocessing
        popem   bp,si

get_fill_brush_1:
        mov     cx,     [si].oem_brush_style

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

get_fill_brush_2:
	stc
	ret

get_fill_data	endp

	include monostuf.inc
        include clrstuff.inc
	include sl216.inc
	include pattern.inc

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
