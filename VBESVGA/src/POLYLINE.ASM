;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; polyline.asm
;
; Copyright (c) 1991 Microsoft Corporation.  All Rights Reserved.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;-----------------------------------------------------------------------------;
;                                                                             ;
;                           DO_POLYLINES                                      ;
;                           ------------                                      ;
;                                                                             ;
;  Given a set of points, draws a set of polylines connecting adjoining points;
;  This routine handles output to EGA as well as to BITMAPS (small or huge)   ;
;                                                                             ;
;  Breshenham's Run Length Slice algorithm is used to draw the lines. Though  ;
;  the algorithm is not derived here, the steps necessary in implementation   ;
;  are explained later.                                                       ;
;                                                                             ;
;  The way the algorithm works can be summarised below:                       ;
;                                                                             ;
;               . To draw any line we have to set on a set of  pixels which   ;
;                 fall on the line or are closest to it.In cases where a line ;
;                 passes exactly between two pixels, we resolve the tie by    ;
;                 setting on the lower pixel                                  ;
;                                                                             ;
;               . As a result of the above approximation, a line will actually;
;                 be drawn as a series of steps.                              ;
;                                                                             ;
;               . At any particular pixel position, the next pixel to set on  ;
;                 depends on the direction of progress and the slope of the   ;
;                 line, but because of the discrete movements, it can be the  ;
;                 next pixel in one of the following 8 directions:            ;
;                                                                             ;
;                             . Positive X / Negative X                       ;
;                             . Positive Y / Negative Y                       ;
;                             . Along one of the 4 diagonals in 1st, 2nd, 3rd ;
;                               or 4th quadrants.                             ;
;                                                                             ;
;               . Depending upon the slope of the line we will actually have  ;
;                 a series of pixels set on in one of the 8 directions, then  ;
;                 a move of 1 pixel in a second direction (one of above 8)    ;
;                 followed by another run of pixels in the first direction    ;
;                 , a move 1 pixel in the second direction and so on ...      ;
;                                                                             ;
;               . A line thus will have an AXIAL direction, along which most  ;
;                 of the pixels are set on and a DIAGONAL (to the axial) dir  ;
;                 which separates one run of pixel on the AXIAL direction     ;
;                 from the other                                              ;
;                                                                             ;
;               . The AXIAL and DIAGONAL directions can be one of the above   ;
;                 8 directions, the exact directions can be calculated from   ;
;                 slope of the line and the direction of progress.            ;
;                                                                             ;
;               . To facilitate the calculation of the run lengths along the  ;
;                 AXIAL direction, we can rotate the line till the AXIAL dir  ;
;                 becomes the POSITIVE X axis and the DIAGONAL direction beco-;
;                 -mes the diagonal in the first quadrant.                    ;
;                                                                             ;
;               . The steps to do the above rotation are:                     ;
;                                                                             ;
;                             . Translate to origin. Let the other end point  ;
;                               be at (Xf,Yf)                                 ;
;                             . Get the line into the first quadrant. So the  ;
;                               end point will now be (|Xf|,|Yf|)             ;
;                             . Get it below the slope=1 line. That is, inter-;
;                               -change the abscissa and ordinate of the end  ;
;                               point to ensure that the abscissa is >= the   ;
;                               ordinate. Let end point now be at (X,Y)       ;
;                             . If the line is above the slope=1/2 line, get  ;
;                               it below by making the end point to be (X,X-Y);
;                                                                             ;
;               . The line thus constructed will be in the same relative posi-;
;                 -tion wrt the +X axis and the 1st. quadrant diagonal, as the;
;                 original line was wrt it's AXIAL and DIAGONAL directions.   ;
;                                                                             ;
;               . If the pseudo line runs from (0,0) to (X,Y), we have to cal-;
;                 -culate the number of pixels to set on, on each of the hori-;
;                 -zontal scan lines at y=0,1,2,...,Y                         ;
;                                                                             ;
;               . Consider scan line at y=i 0<i<Y.                            ;
;                 If the line intersects the scan line at y=i-1/2 at x, then  ;
;                 the first pixel to set on, on the ith scan line is at       ;
;                 floor(x)+1 and the last is at floor(x + s) where s is the   ;
;                 inverse slope.                                              ;
;                                                                             ;
;               . The run length on the ith scan line is thus:                ;
;                             floor(x+s) - floor(x)                           ;
;                                                                             ;
;               . The idea behind the algorithm is to calculate these run len-;
;                 -gths and does so by using the run length on the previous   ;
;                 line and an error term.                                     ;
;                                                                             ;
;               . We finally get a series of run lengths, H0 on i=0, scan line;
;                 HY on the last scan line, and Hi on the intermediate ones.  ;
;                                                                             ;
;               . The pseudo line was just used to calculate the run lengths. ;
;                 While drawing the line, we start at the original starting   ;
;                 point (not at origin) the first run of H0 is in the actual  ;
;                 AXIAL direction, a move of 1 pixel in the DIAGONAL dir,and  ;
;                 so on, till the last run of HY pixel on the AXIAL direction ;
;                 takes us to the actual end point of the line.               ;
;                                                                             ;
;                                                                             ;
;  Certain manipulations are made with the end points to make the code simpler;
;  These are:                                                                 ;
;                                                                             ;
;               . All lines will be drawn towards positive X axis, to do this ;
;                 we will swap the initial and final coordinates if necessary ;
;                 This will elliminate three directions of movement which inv-;
;                 -olve the negative X axis, leaving us with 5 directions.    ;
;                                                                             ;
;               . The code for drawing/moving along the diagonal or vertical  ;
;                 directions require the distance in bytes between one scan   ;
;                 line and the next. If we call the routine which draws in a  ;
;                 direction involving the positive Y axis, with the negative  ;
;                 of the scan line offset, it would actually draw in a the    ;
;                 corresponding direction involving negative Y                ;
;                                                                             ;
;               . With the above two manipulations, we need to implement rout-;
;                 -ines to draw in 3 basic directions, Positive X, Positive Y ;
;                 and the diagonal in the first quadrant.                     ;
;                                                                             ;
;               . Routines to move 1 pixel in the DIAGONAL direction are made ;
;                 separate as we will not set on any pixel during these moves.;
;                 We will thus have 3 move routines too, as the DIAGONAL dire-;
;                 -ction of the line could agagin be one of the 5 basic ones. ;
;                                                                             ;
;               . There are 4 sets of draw routines depending on the device & ;
;                 the type of the line. These are:                            ;
;                             . Solid Lines to EGA                            ;
;                             . Styled Lines to EGA                           ;
;                             . Solid Lines to BITMAPS (huge and small)       ;
;                             . Styled Lines to BITMAPS (huge and small)      ;
;                 Routines are made separate as the organization of memory and;
;                 the method used to process the pixels are different.        ;
;                                                                             ;
;               . There are two sets of MOVE routines, one for EGA and the ot-;
;                 -her for BITMAPS.                                           ;
;                                                                             ;
;               . Styled lines are drawn in two passes, the second pass is to ;
;                 draw the gaps for OPAQUE background modes.                  ;
;                                                                             ;
;               . Windows support 16 Raster Operations for combining the pen  ;
;                 color and the color of the destination, these are implement-;
;                 -ed and are explained below.                                ;
;                                                                             ;
;  For lines which are originally below the X axis, the metric of rounding    ;
;  down to resolve ties for the pseudo line will actually cause the tie cases ;
;  to be rounded to the pixel above the original line. Like wise for lines    ;
;  originally to the left of the slope=1 line, tie cases will be rounded to   ;
;  pixel on the right instead of the one on the left. This is inconsistent    ;
;                                                                             ;
;  To take care of this the metric for the above flipped psudo-lines should   ;
;  be to round up (that is take the floor value and not the ceiling). But we  ;
;  can continue with the original metric if we shift the pseudo line in these ;
;  cases by a minute amount to the left, so as to bias the ties infavour of   ;
;  required pixel but small enough so as to not affect the non-tie cases.     ;
;  The amount of shift can be shown to be (1/2Y) where the Y is the ordinate  ;
;  of the pseudo lines end point.                                             ;
;                                                                             ;
;              .   2/89, Irene Wu, Video 7
;                  Modified to work in VRAM's 256 color modes.
;-----------------------------------------------------------------------------;

?win = 1
?plm = 1

?CHKSTK = 1
?CHKSTKPROC     macro
                endm

?CHKSTKNAME     macro
        call    LineSeg_check_stack
                endm

; Most of the routines in the original driver seemed to assume that segments do
; NOT contain partial scanlines - i.e. each scanline is guaranteed to lie within
; a single bank; no need to bank-switch while running across a scanline.
; This may be true for memory bitmaps (enforced by GDI?) but it is definitely
; not true in general for VESA-compliant graphics cards. This switch enables
; code to calculate drawing positions for cards that have partial scanlines at
; the beginning/end of banks.
?PARTIAL_SCANLINES = 1


incLogical      = 1                     ;Include GDI Logical object definitions
incDrawMode     = 1                     ;Include GDI DrawMode definitions
incOutput       = 1                     ;Include GDI Output definitions


.xlist
        include lines.inc
        include cmacros.inc
        include gdidefs.inc
        include macros.mac
        include polyline.inc
        include display.inc
        include cursor.inc
.list

??_out polyline

        public  Clip_Line
        public  ega_line_dispatch
        public  Draw_Line
        public  mask_needed
        public  calculate_mask
        public  Draw_Engine
        public  find_out_dda
        public  tests_done
        public  save_vars
        public  do_another_pass
        public  draw_loop
        public  do_the_last_scan
        public  all_passes_done
        public  style_draw_pass
        public  style_advance
        public  Bm_Positive_X
        public  Bm_Negative_Y
        public  Bm_Positive_Y
        public  Bm_Diagonal_4Q
        public  Bm_Diagonal_1Q

	public	StBm_Positive_X
	public	StBm_Diagonal_4Q
	public	StBm_Negative_Y
	public	StBm_Diagonal_4Q
	public	StBm_Positive_X
	public	StBm_Diagonal_1Q
	public	StBm_Positive_Y
	public	StBm_Diagonal_1Q
	public	StBm8_Positive_X
	public	StBm8_Diagonal_4Q
	public	StBm8_Negative_Y
	public	StBm8_Diagonal_4Q
	public	StBm8_Positive_X
	public	StBm8_Diagonal_1Q
	public	StBm8_Positive_Y
	public	StBm8_Diagonal_1Q

ifdef PALETTES
        externB PaletteModified
endif

        externFP LineSeg_check_stack
        externFP ipc_to_rgb_far

ifdef PALETTES
        externFP TranslateBrush         ;'on-the-fly' translation of brush
        externFP TranslatePen           ;'on-the-fly' translation of pen
        externFP TranslateTextColor     ;'on-the-fly' translation of textcol
endif

ifdef   EXCLUSION
        externFP exclude_far            ; exclude area from screen.
        externFP unexclude_far          ; clear excluded area.
endif

externB bank_select_byte
sBegin          Data

TYPE_IS_DEV     equ     10000000b       ; indicates drawing device is screen
TYPE_IS_HUGE    equ     01000000b       ; drawing device is huge bitmap
TYPE_IS_BYTEMAP equ	00000010b	; drawing device is byte/pixel bitmap
TYPE_IS_STYLED  equ     00000001b       ; indicates lines are styled
wDistHoriz      equ     40h             ; Horiz. scale factor for style mask
wDistVert       equ     55h             ; Vert. scale factor for style mask
OPAQUE          equ     2               ; indicates OPAQUE background mode
HALF_FLIP       equ     0001h           ; half flip done
XY_XCHG         equ     0002h           ; X and Y interchanged
Y_FLIP          equ     0004h           ; vertical flip done
VERTICAL_FLIP   equ     0100h           ; HALF_FLIP XOR Y_FLIP
LEFT_XCHG       equ     0080h           ; forced left to right
CLIP_TOBE_DONE  equ     0001h           ; clipping done by driver
PS_SOLID        equ     0               ; solid lines
PS_NULL         equ     5               ; null lines

externB         enabled_flag            ; non zero if output to screen allowed
externB		red_shr

sEnd            Data

createSeg       _LINES,LineSeg,word,public,CODE
sBegin          LineSeg

assumes         cs,LineSeg


; the following stores the address of the draw routines for solid EGA lines

DrawTable_solid_bm	dw	offset Bm_Positive_X
                        dw      offset Bm_Diagonal_4Q
                        dw      offset Bm_Negative_Y
                        dw      offset Bm_Diagonal_4Q
                        dw      offset Bm_Positive_X
                        dw      offset Bm_Diagonal_1Q
                        dw      offset Bm_Positive_Y
                        dw      offset Bm_Diagonal_1Q

DrawTable_styled_bm	dw	offset StBm_Positive_X
                        dw      offset StBm_Diagonal_4Q
                        dw      offset StBm_Negative_Y
                        dw      offset StBm_Diagonal_4Q
                        dw      offset StBm_Positive_X
                        dw      offset StBm_Diagonal_1Q
                        dw      offset StBm_Positive_Y
                        dw      offset StBm_Diagonal_1Q

DrawTable_solid_bm8	dw	offset Bm8_Positive_X
                        dw      offset Bm8_Diagonal_4Q
                        dw      offset Bm8_Negative_Y
                        dw      offset Bm8_Diagonal_4Q
                        dw      offset Bm8_Positive_X
                        dw      offset Bm8_Diagonal_1Q
                        dw      offset Bm8_Positive_Y
                        dw      offset Bm8_Diagonal_1Q

DrawTable_styled_bm8    dw      offset StBm8_Positive_X
                        dw      offset StBm8_Diagonal_4Q
                        dw      offset StBm8_Negative_Y
                        dw      offset StBm8_Diagonal_4Q
                        dw      offset StBm8_Positive_X
                        dw      offset StBm8_Diagonal_1Q
                        dw      offset StBm8_Positive_Y
                        dw      offset StBm8_Diagonal_1Q

; Move routine addresses for EGA

; Move routine addresses for BITMAPS

MoveTable_bm            dw      offset Bm_Move_Diagonal_4Q
                        dw      offset Bm_Move_Positive_X
                        dw      offset Bm_Move_Diagonal_4Q
                        dw      offset Bm_Move_Negative_Y
			dw	offset Bm_Move_Diagonal_1Q
                        dw      offset Bm_Move_Positive_X
			dw	offset Bm_Move_Diagonal_1Q
			dw	offset Bm_Move_Positive_Y

; Move routine addresses for byte/pixel BITMAPS or SCREEN
; TODO: bm16/24/32 versions of these too

MoveTable_bm8           dw      offset Bm8_Move_Diagonal_4Q
                        dw      offset Bm8_Move_Positive_X
                        dw      offset Bm8_Move_Diagonal_4Q
                        dw      offset Bm8_Move_Negative_Y
			dw	offset Bm8_Move_Diagonal_1Q
                        dw      offset Bm8_Move_Positive_X
			dw	offset Bm8_Move_Diagonal_1Q
			dw	offset Bm8_Move_Positive_Y

; logical operation routine addresses for BM8 functions

BM8_ROP_Table	    dw	    offset BM8_ROP0
			dw	offset BM8_ROP1
			dw	offset BM8_ROP2
			dw	offset BM8_ROP3
			dw	offset BM8_ROP4
			dw	offset BM8_ROP5
			dw	offset BM8_ROP6
			dw	offset BM8_ROP7
			dw	offset BM8_ROP8
			dw	offset BM8_ROP9
			dw	offset BM8_ROPA
			dw	offset BM8_ROPB
			dw	offset BM8_ROPC
			dw	offset BM8_ROPD
			dw	offset BM8_ROPE
			dw	offset BM8_ROPF
BM16_ROP_Table	    dw	    offset BM16_ROP0
			dw	offset BM16_ROP1
			dw	offset BM16_ROP2
			dw	offset BM16_ROP3
			dw	offset BM16_ROP4
			dw	offset BM16_ROP5
			dw	offset BM16_ROP6
			dw	offset BM16_ROP7
			dw	offset BM16_ROP8
			dw	offset BM16_ROP9
			dw	offset BM16_ROPA
			dw	offset BM16_ROPB
			dw	offset BM16_ROPC
			dw	offset BM16_ROPD
			dw	offset BM16_ROPE
			dw	offset BM16_ROPF
BM24_ROP_Table	    dw	    offset BM24_ROP0
			dw	offset BM24_ROP1
			dw	offset BM24_ROP2
			dw	offset BM24_ROP3
			dw	offset BM24_ROP4
			dw	offset BM24_ROP5
			dw	offset BM24_ROP6
			dw	offset BM24_ROP7
			dw	offset BM24_ROP8
			dw	offset BM24_ROP9
			dw	offset BM24_ROPA
			dw	offset BM24_ROPB
			dw	offset BM24_ROPC
			dw	offset BM24_ROPD
			dw	offset BM24_ROPE
			dw	offset BM24_ROPF
BM32_ROP_Table	    dw	    offset BM32_ROP0
			dw	offset BM32_ROP1
			dw	offset BM32_ROP2
			dw	offset BM32_ROP3
			dw	offset BM32_ROP4
			dw	offset BM32_ROP5
			dw	offset BM32_ROP6
			dw	offset BM32_ROP7
			dw	offset BM32_ROP8
			dw	offset BM32_ROP9
			dw	offset BM32_ROPA
			dw	offset BM32_ROPB
			dw	offset BM32_ROPC
			dw	offset BM32_ROPD
			dw	offset BM32_ROPE
			dw	offset BM32_ROPF

; AND/XOR mask definitions for ROP codes on BITMAPS

BitmapMaskTable         dw      000ffh          ; set to zero
                        dw      0ff00h          ; invert destination
                        dw      00000h          ; leave alone
                        dw      0ffffh          ; set to one

; Mask values for STYLED lines

style_table     label   byte
                db      11111111b,11111111b     ; solid line
                db      11100111b,11100111b     ; dashed
                db      10101010b,01010101b     ; dotted
                db      11100100b,00100111b     ; dot_dash
                db      11101010b,01010111b     ; dash_dot_dot

.xlist
include drawmod2.asm    ; includes the AND/XOR flags and combine functions
                        ; as well as the no of passes required for EGA ROPs
.list


;--------------------------Public-Routine-------------------------------;
; do_polylines(lp_dst_dev,style,count,lp_points,lp_phys_pen,lp_phys_brush,
;              lp_draw_mode,lp_clip_rect)
;
; DWORD lp_dst_dev                      // pointer to destination.
; short style                           // output operation.
; short count                           // number of points.
; DWORD lp_points                       // pointer to set of points.
; DWORD lp_phys_pen                     // pointer to physical pen.
; DWORD lp_phys_brush                   // pointer to physical brush.
; DWORD lp_draw_mode                    // pointer to drawing mode.
; DWORD lp_clip_rect                    // pointer to clipping rect if <> 0.
;
; do_polylines initializes things for the line drawing routines.  if
; the lines are being drawn to the EGA, then the EGA is initialized
; as necessary and the exclusion area is handled.  if the lines are
; being written to a bitmap, information about the bitmap is loaded.
; necessary tables and pointers are set up depending on line style and
; destination device.  When all of the necessary initialization is
; complete, we jump to polyline_loop which does the DDA and the line
; drawing.
;
; Entry: per parameters.
;
; Returns: AX = 1 if polylines drawn.
;
; Error Returns: AX = 0 if polylines not drawn.
;
; Registers Destroyed: AX,BX,CX,DX,flags.
;
; Registers Preserved: ES,DS,DI,SI.
;
;-----------------------------------------------------------------------;
        assumes ds,nothing
        assumes es,nothing

cProc   do_polylines,<FAR,PUBLIC,NODATA,WIN,PASCAL>,<es,ds,si,di>

        parmD   lp_dst_dev              ;--> to the destination
        parmW   style                   ;Output operation
        parmW   count                   ;# of points
        parmD   lp_points               ;--> to a set of points
        parmD   lp_phys_pen             ;--> to physical pen
        parmD   lp_phys_brush           ;--> to physical brush
        parmD   lp_draw_mode            ;--> to a Drawing mode
        parmD   lp_clip_rect            ;--> to a clipping rectange if <> 0

        localD  BackColor               ; background color
	localD	ForeColor
	localW	DrawModeIndex		; ROP code
        localD  TmpColor                ; pen color
        localB  DeviceFlags             ; identifies type of device
	localB	BytesPerPixel		; how big is each pixel for an RGB map?

; following params are necessary for BITMAPS

        localW  BitmapSegment           ; start segment for small/huge maps
        localW  BitmapOffset            ; offset of start of map
        localW  NextScan                ; offset to next scan line in map
        localW  wScans                  ; no of scan lines in huge map segment
        localW  FillBytes               ; filler bytes at end of huge segment
        localW  NextSegOff              ; offset to next hugemap segment
        localW  BM8                     ; point to BM8_... dataROT routine

; following variables are used for styled lines

        localW  StyleFlags              ; HIWORD has background mode,LO -- mask
        localB  BackMode                ; back ground mode

; following variables are used during the draw routines

        localW  S1                      ; stores principle dir draw
        localW  S1_Move                 ; routine which handles S1 move
        localW  TempCurSeg              ; a copy of CurSeg
        localW  TempCurOff              ; a copy of video offset
                                        ; === specially for 256 color mode ===
        localW  TempCurByte             ; a copy of CurByte
        localW  TempCurByteSty          ; one more saved for style pass
        localB  TempCurBit              ; a copy of rotating bit mask
        localW  ScansLeftFromBot        ; # of scan lines from bottom
        localB  ROPcolor                ; temp value of pen color (for mono)
        localW  wBitmapROP              ; XOR,AND mask for bitmaps
        localW  style_pass_init         ; ega init tobe called before
                                        ; style pass
        localB  StylePass               ; style gap pass indicator
        localB  bStyleError             ; style error term
        localB  bTempStyleError         ; saves the error term
        localB  bStyleMask              ; rotating style mask
        localB  bTempStyleMask          ; saves the style mask
        localW  StyleAdvOrBypass        ; addr of style advance routine/null

        localW  StartX                  ; starting point abscissa
        localW  StartY                  ; starting point ordinate
        localW  Xa                      ; start clip point X
        localW  Ya                      ; start clip point Y
        localW  Xb                      ; end clip point X
        localW  Yb                      ; end clip point Y
        localW  f1                      ; style error first multiplier
        localW  f2                      ; style error second multiplier
        localW  wStyleCounter           ; saved style counter
        localW  wStyleMask              ; forward and reverse style masks
        localW  wFracS                  ; keeps frac(s)
        localW  cm                      ; keeps m = floor(s)
        localW  wError                  ; error term
        localW  Ca                      ; first slice length
        localW  Cb                      ; last slice length
        localW  XformFlags              ; records transformations done
        localW  cdy                     ; stores pseudo line minor coord
        localW  cScanMove               ; offset to next scan line
        localW  cScanStep               ; sidestep error add factor
        localB  LineStyle               ; value of line style
        localW  cScans                  ; no of scans lines for pseudo line
        localW  cTempScans              ; save for later passes
        localW  wDistDiag               ; style error add for diag draw
        localW  ClipFlag                ; clip to be done indicator
        localW  SideStep                ; side step contribution to error
        localB  cRotation               ; no of bits to rotate on sidestep
        localW  davidw
	localB	bank_select		; VRAM VGA's current bank
        localB  TempBank

; the following variables define the clipping rectangle

        localW  X1                      ; left margin
        localW  X2                      ; right margin
        localW  Y1                      ; bottom margin
        localW  Y2                      ; top margin

cBegin
WriteAux <'do_polylines'>
	mov	ax,DataBASE
        mov     ds,ax
        assumes ds,Data

        jnc     stack_space_ok
	jmp	error_exit		; exit with error on stack overflow
stack_space_ok:
        cld
;----------------------------------------------------------------------------;
; if palette manager is supported do the on-the-fly object translations now  ;
;----------------------------------------------------------------------------;

ifdef PALETTES
	cmp	[red_shr],-1
	jne	no_translation_needed	; not using a palette

        cmp     PaletteModified,0ffh    ; was the palette modified ?
        jnz     no_translation_needed   ; no
        push    ds                      ; save own ds
        lds     si,lp_dst_dev           ; the device information block
        lodsw                           ; get the device type
        pop     ds                      ; get back own segment
        or      ax,ax                   ; is the target physical device ?
        jz      no_translation_needed   ; no!, so no translation is needed

;	 arg	 lp_phys_brush
;	 cCall	 TranslateBrush 	 ;translate the brush
;	 mov	 seg_lp_phys_brush,dx
;	 mov	 off_lp_phys_brush,ax	 ;load the local brush pointer

        arg     lp_phys_pen
        cCall   TranslatePen            ;translate the pen
        mov     seg_lp_phys_pen,dx
        mov     off_lp_phys_pen,ax      ;load the local pen pointer

        arg     lp_draw_mode
        cCall   TranslateTextColor      ;translate foreground/background cols
        mov     seg_lp_draw_mode,dx
        mov     off_lp_draw_mode,ax     ;load the local pen pointer
no_translation_needed:

endif

;----------------------------------------------------------------------------;

	mov	al	,enabled_flag
	lds	si,lp_dst_dev		; DS:SI points to device structure
        assumes ds,nothing

        mov     di,word ptr [si].bmBits
        mov     TempCurOff,di
        mov     di,word ptr [si].bmBits+2
        mov     TempCurSeg,di           ; store segment value
	mov	DeviceFlags,0
	mov	cx,[si].bmType		; get the device type
        jcxz    get_bitmap_info         ; calculate params for bitmaps
ifdef VGA256X
        mov     ax,-1
        jmp     polyline_return
endif
	cmp	al,0			;is the screen enabled?
	jne	jump_error_exit_skip	; no, exit with error
	jmp	error_exit
jump_error_exit_skip:
	or	DeviceFlags,TYPE_IS_DEV + TYPE_IS_BYTEMAP
					; lines to be drawn on VRAM

get_bitmap_info:

        mov	al,[si].bmBitsPixel
	shr	al,3
	mov	BytesPerPixel,al
        jz	get_bitmap_info_10	; if bmBitsPixel < 8 then ZF is set
	or	DeviceFlags,TYPE_IS_BYTEMAP

get_bitmap_info_10:

	mov	di,word ptr [si].bmWidthBytes
        mov     NextScan,di                 ; # of bytes per scan line

;;;;;;;;        test    DeviceFlags, TYPE_IS_DEV
;;;;;;;;        je      get_bitmap_info_20
;;;;;;;;        mov     NextScan, BYTES_PER_LINE
;;;;;;;;
;;;;;;;;get_bitmap_info_20:

	mov	di,word ptr [si].bmBits+2
        mov     BitmapSegment,di            ; start segment of the bitmap
        mov     di,word ptr [si].bmBits
        mov     BitmapOffset,di             ; offset of the start of the map

; anticipating small bitmaps we will initialize some of the variables

        mov     wScans,0ffffh               ; assume 64k scan lines!
        mov     NextSegOff,0                ; reset
        mov     FillBytes,0                 ; reset

	mov	cx,[si].bmSegmentIndex	    ; is it a huge bitmap
        test    DeviceFlags, TYPE_IS_DEV
	je	skip_set_size_for_screen
	inc	cx

skip_set_size_for_screen:
	jcxz	get_clipping		    ; no, skip the segment calcs

; cx has the segment offset to the next huge bitmap segment

        mov     NextSegOff,cx               ; save the segment offset
        or      DeviceFlags,TYPE_IS_HUGE    ; set the indicator for huge maps

        mov     cx,[si].bmFillBytes         ; no of filler bytes at the end
        mov     FillBytes,cx
        mov     cx,[si].bmScanSegment
        mov     wScans,cx                   ; no of scan lines per segment

get_clipping:
ifdef   EXCLUSION
        xor     cx,cx                   ; assume entire screen
        mov     dx,cx
        mov     di,[si].bmHeight
        mov     si,[si].bmWidth
endif
	mov	ClipFlag,0
        lds     bx,lp_clip_rect         ; DS:BX points to clip rectangle
        assumes ds,nothing
        mov     ax,ds
        or      ax,bx                   ; NULL pointer means no clipping
        jz      do_no_clipping
        mov     ax,[bx].left
        mov     X1,ax                   ; the left margin
        mov     ax,[bx].top
        mov     Y1,ax                   ; for us this is bottom margin
        mov     ax,[bx].right
        mov     X2,ax                   ; the right margin
        mov     ax,[bx].bottom
        mov     Y2,ax                   ; for us this is the top margin
	mov	ClipFlag,CLIP_TOBE_DONE     ; turn on clipping

ifdef   EXCLUSION
        mov     cx,X1                   ; set exclusion to passed rectangle
        mov     dx,Y1                   ; for exclude scan this is top
        mov     si,X2                   ; right margin
        mov     di,Y2                   ; for exclude scan this is bottom
endif

do_no_clipping:

ifdef   EXCLUSION
        call    exclude_far             ; exclude the scan from the screen
endif

; now load the pen color

load_fg_color:

	assume	ds:nothing
        lds     si,lp_phys_pen              ; DS:SI points to the pen structure
        mov     ax,[si].oem_pen_pcol.lo
        mov     dx,wptr [si].oem_pen_pcol.hi
	test	DeviceFlags,TYPE_IS_BYTEMAP  ; mono maps color bit is SPECIAL
	jnz	short ld_fg_color2
        mov     ah,[si].oem_pen_accel
	shr	ah,1			    ; expand 1 to 32 bits
	sbb	ax,ax
	cwd
ld_fg_color2:
	mov	ForeColor.lo,ax		    ; save the pen color
	mov	ForeColor.hi,dx

load_bg_color:
	assume	es:nothing
	les	di,lp_draw_mode 	    ; point to the draw mode block
	mov	dx,es:[di].bkMode	    ; get the background mode
        mov     BackMode,dl                 ; save it
	mov	ax,byte ptr es:[di].bkColor.lo
	mov	dx,word ptr es:[di].bkColor.hi
	test	DeviceFlags,TYPE_IS_BYTEMAP
	jnz	short ld_bg_color2
	call	ipc_to_rgb_far		    ; get accelerators in DH
	shr	dh,1			    ; expand 1 to 32 bits
	errnz	MONO_BIT-00000001B
	sbb	ax,ax
	cwd
ld_bg_color2:
        mov     BackColor.lo,ax	    ; save the background color
        mov     BackColor.hi,dx

	mov	bx,es:[di].Rop2 	    ; get the ROP code
        dec     bx                          ; make it zero based
        and     bx,RASTER_OP_MASK           ; only 4 bits are significant
        mov     DrawModeIndex,bx            ; save a copy

	; choose which table to index (BM8, BM16, etc.)
	mov	cl,BytesPerPixel
	dec	cl
	shl	cl,RASTER_OP_SHL
	or	bl,cl

	shiftl	bx,1
	mov	bx	,cs:[BM8_ROP_Table][bx]
	mov	BM8	,bx

	mov	cx,[si].oem_pen_style	    ; get the requested style
        mov     LineStyle,cl                ; save style
        cmp     cl,MaxLineStyle             ; test for validity
        jg      jump_error_exit1            ; illegal style
	jl	get_style_info		    ; if legal, then deal with style
	jmp	exit

jump_error_exit1:
	jmp	error_exit

get_style_info:
	xor	ch,ch			    ; blank upper byte!
	mov	si,cx			    ; the passed in line style
        shl     si,1                        ; 2 bytes of mask per style
        mov     ax,word ptr cs:style_table[si]      ; get the style mask
        mov     wStyleMask,ax               ; save both the mask
        mov     wStyleCounter,0             ; initialize it
        mov     bStyleMask,al               ; save it
        mov     StyleAdvOrBypass,offset style_advance_bypass
	jcxz	start_draw		    ; skip code for solid line styles
        mov     StyleAdvOrBypass, offset style_advance
        or      DeviceFlags,TYPE_IS_STYLED  ; set indicator for styled lines

start_draw:

        lds     si,lp_points               ; DS:SI points to point array
        lodsw
        mov     dx,ax                      ; first X coordinate
        lodsw
        mov     cx,ax                      ; first Y coordinate
        push    es                         ; es will be trashed
        cCall   ega_line_dispatch          ; draws the set of poly lines
        pop     es                         ; restore es
        mov     ax,1                       ; show success
        jmp     short exit

error_exit:
        xor     ax,ax
        errn$   exit
exit:
ifdef   EXCLUSION
        call    unexclude_far              ; remove any exclusion area
endif

polyline_return:
cEnd

;-----------------------------------------------------------------------------;
;                        EGA_LINE_DISPATCH                                    ;
;                        -----------------                                    ;
;                                                                             ;
; Draws the set of polylines after all parameters for the target device and   ;
; various masks have been calculated.                                         ;
;                                                                             ;
; Inputs:                                                                     ;
;                  CX    ---    first Y coordinate                            ;
;                  DX    ---    first X coordinate                            ;
;               DS:SI    ---    points to table of subsequent points          ;
;           assumes that various masks and scanline next plane details        ;
;           for BITMAPS are already loaded.                                   ;
;                                                                             ;
; AX, BX, CX, DX, Di, SI are trashed                                          ;
;                                                                             ;
;-----------------------------------------------------------------------------;

cProc ega_line_dispatch,<PUBLIC,NEAR>
cBegin
        mov     ax,count                ; no of points
        dec     ax                      ; no of lines will be one less

; if a single point is to be drawn, we can go back as either the first or the
; last point of a line is never drawn, and if the line is a point, it implies,
; that the point will not be drawn

        jz      return_back             ; point not to be drawn

        mov     bx,cx                   ; BX gets Yi
        mov     cx,ax                   ; cx gets count of lines
dispatch_loop:
        push    cx                      ; save count
        lodsw                           ; get Xf
        mov     di,ax
        lodsw                           ; get Yf
        push    si                      ; save table pointer
        mov     si,ax                   ; (DI:SI) has end point
        mov     cx,dx
        xchg    cx,bx                   ; (BX:CX) has start point
        push    si
        push    di                      ; save end points
        push    ds                      ; save table segment
        call    Draw_Line               ; draw the line
        pop     ds
        pop     dx                      ; old Xf = new Xi
        pop     bx                      ; old Yf = new Yi
        pop     si                      ; get back table pointer
        pop     cx                      ; get back count of line
        loop    dispatch_loop           ; draw all the lines
return_back:

cEnd
;------------------------------------------------------------------------------;
;                        DRAW_LINE                                             ;
;                        ---------                                             ;
;                                                                              ;
;  This routine takes two end points of a line and does all the transformations;
;  necessary to get the pseudo line in the first one-fourth quadrant. It also  ;
;  clips the line against the clipping rectangle and for styled lines computes ;
;  the style mask and the style error term to start with, and the value of     ;
;  these terms at the end of the line.                                         ;
;                                                                              ;
;  Once all the transformations have been done, it calls the DRAW_ENGINE to    ;
;  actually draw the line.                                                     ;
;                                                                              ;
;------------------------------------------------------------------------------;

Draw_Line       proc    near


;---------------------------------------------------------------------------;
; We have now obtained the two end points:				    ;
;                                                                           ;
;               (BX,CX)  ---  X and Y coordinates of 1st end point          ;
;               (DI,SI)  ---  X and Y cordinates of the other end point     ;
;---------------------------------------------------------------------------;
;
; handle clipping separately
;
        mov     XformFlags,0            ; initialize the transformation flags
        test    ClipFlag,CLIP_TOBE_DONE
        jz      no_clipping             ; we shall not do clipping
        call    Clip_Line               ; clip the line

; above routine will clip the line against the clipping rectangle and wiill set
; the clipping boundary to the inclusive interval [Xa,Xb]

        jmp     region_clip_done

no_clipping:

; make sure that the line goes from left to right, exchange the end points if
; not
        cmp     bx,di                   ; compare the two abscissas
        jle     is_left_to_right        ; direction is OK
        xchg    bx,di
        xchg    cx,si                   ; exchange the coordinates
        or      XformFlags,LEFT_XCHG    ; line will be drawn from other end

is_left_to_right:

; we will save the starting coordinates to be used later for start point
; address in memory calculation

        mov     StartX,bx
        mov     StartY,cx

; translate the coordinates so that the first point is at origin

        sub     di,bx                   ; translate the end point
        sub     si,cx
        jge     line_above_horizontal   ; line already in 1st quadrant
        neg     si                      ; bring the end point into 1st quadrant
        or      XformFlags,Y_FLIP+VERTICAL_FLIP

line_above_horizontal:

; now get the line below the 45 degree line.

        cmp     si,di
        jbe     line_below_45           ; we are already X major
        xchg    di,si                   ; exchange the end points
        or      XformFlags,XY_XCHG      ; record the transformation

line_below_45:

; as we here we are not clipping the line, the clipping interval will be set
; to the two end of the line.

        mov     Xa,0                    ; left hand clip margin
        mov     Xb,di                   ; right hand clip margin

region_clip_done:

; if the first pel is not to be drawn we will actually restrict the clipping
; interval if it has not already excluded the first pel.
; we skip the first pel only when the line moves from end to start but for the
; actual direction of the line, the last pel is clipped.

        test    XformFlags,LEFT_XCHG
        jz      clip_last_pel           ; clip off the last pel
        cmp     Xa,1                    ; is the first pel already clipped ?
        jae     end_pel_processed       ; yes
        mov     Xa,1                    ; clip the first pel
        jmp     short end_pel_processed
clip_last_pel:
        cmp     Xb,di                   ; is the last pel already clipped?
        jb      end_pel_processed       ; yes, so no more to clip
        dec     di                      ; take out last pel from line
        mov     Xb,di
        inc     di
        jnz     end_pel_processed       ; watch out for zero pel line

; we want to continue with zero length lines still as the start style for the
; next line has to be decided next.

        mov     Xa,1
        mov     Xb,0                    ; Xa>Xb would tell us about 0 length
end_pel_processed:

;----------------------------------------------------------------------------;
;               COMPUTE THE STYLE MASK/ERR AT BOTH ENDS OF LINE              ;
;----------------------------------------------------------------------------;

        cmp     LineStyle,PS_SOLID      ; is the line a solid line
        jz      bypass_mask             ; ignore for solid lines
        cmp     LineStyle,PS_NULL       ; invisible line
        jz      bypass_mask             ; ignore for NULL lines too
        jmp     short mask_needed       ; calculate masks
bypass_mask:
        jmp     do_halfflip             ; do half flip if required

mask_needed:
; if X and Y have been interchanged, get them back for the comparisions

        test    XformFlags,XY_XCHG      ; where they interchanged ?
        jz      not_xchged              ; no
        xchg    di,si                   ; get them back for the timebeing
not_xchged:

; now di has X and si has Y
; determine the stylistically major direction of the line

        mov     ax,wDistHoriz           ; horizontal style err add factor
        mov     bx,wDistVert            ; vertical style error add factor
        mul     di                      ; di has X
        xchg    ax,bx                   ; get Y into BX, save AX
        mov     cx,dx                   ; save all 32 bits of mul
        mul     si                      ; si has Y

; now DX:AX has Y*fy and CX:BX has X*fx, compare them

        cmp     dx,cx                   ; compare HIWORD
        jb      styled_as_X_major
        ja      styled_as_Y_major
        cmp     ax,bx                   ; HIWORD tied, compare LOWORD
        ja      styled_as_Y_major
styled_as_X_major:
        mov     ax,wDistHoriz           ; fx
        mov     f1,ax                   ; f1=f2=fd=ax
        mov     f2,ax
        mov     wDistDiag,ax
        mov     SideStep,ax
        mov     cx,ax                   ; ax has f1, cx has f2
        jmp     short calculate_mask
styled_as_Y_major:
        mov     ax,wDistVert
        mov     f1,ax
        mov     cx,ax                   ; f1=f2=fd=sidestep = fy
        mov     f2,ax
        mov     wDistDiag,ax
        mov     SideStep,ax             ; assume normally Y major case

; if the line is normaly X major, then side step will be 0 else fy

        cmp     di,si                   ; compare X with Y
        jb      calculate_mask
        mov     SideStep,0              ; actually X major line.

calculate_mask:

; AX has f1, CX has f2,  totall add factor z = f1 * (major-minor) + minor * Y
; we will have to get back major into DI

        test    XformFlags,XY_XCHG      ; were the ends shuffled ?
        jz      major_in_di             ; no
        xchg    di,si                   ; major in di, minor in si
major_in_di:
        mov     bx,di
        sub     bx,si                   ; BX gets X - Y
        mul     bx                      ; f1*(X-Y)
        xchg    ax,cx                   ; save result, get f2
        mul     si                      ; f2*Y
        add     ax,cx                   ; get the total err add needed
        mov     bx,wStyleCounter        ; the state and error at start
        add     ax,bx
        mov     wStyleCounter,ax        ; the state and error at end

; if we are going to draw the line from the far end, the reverse of the mask
; and the state from the end of the line is to be used

        mov     dx,wStyleMask           ; dh has the reverse mask
        test    XformFlags,LEFT_XCHG    ; are we going reverse
        jz      not_reverse             ; no
        mov     bx,ax                   ; style counter at end
        not     bx                      ; we are going reverse from end
        mov     dl,dh                   ; use the reverse of the mask
not_reverse:
        mov     bStyleError,bl          ; the error term to use
        mov     cl,bh                   ; the state
        and     cl,7                    ; we had not done mod 8 earlier
        rol     dl,cl                   ; rotate the default state
        mov     bStyleMask,dl           ; the new style maska

; now we will do the half flip, if necessary, for styled lines.
; the code below is done for non styled lines too. For them f1 and f2 make
; no sense, but executing the code on f1 and f2 is not going to harm us

do_halfflip:
        mov     ax,si                   ; minor
        add     ax,ax                   ; 2*minor
        cmp     ax,di                   ; 2*minor versus major
        jbe     halfflip_not_req        ; line already in 1st one 4th quad
        sub     si,di
        neg     si                      ; new minor = major-minor
        xor     XformFlags,HALF_FLIP + VERTICAL_FLIP
halfflip_not_req:

; now the equation for Z was for the original coordinates of the line, but
; now we have flipped the line. Thus although the major remains the same
; the minor has become major-minor. If we continue to use the same equation
; with the new major and minor values, then interms of the original values
; we will have:     z = minor*f1 + (major-minor)*f2, which will be wrong unless
; we interchange f1 and f2.

; Thus we will now interchange f1 and f2 and continue to use the original
; equation for z even for the flipped line. fd and sidestep were calculated
; for the original line and they should not be affected.

        mov     ax,f1
        xchg    f2,ax                   ; f2 gets f1 and ax gets f2
        mov     f1,ax

; at this point all the transformations have been done and we are ready to
; draw the line.

        mov     ax,Xa
        cmp     ax,Xb                   ; test for valid clip interval
        ja      Draw_Line_Ret           ; line is totally clipped
        mov     cdy,si
        call    Draw_Engine             ; draw the line

Draw_Line_Ret:
        ret                             ; one more line drawn

Draw_Line       endp
;------------------------------------------------------------------------------;
;                          DRAW_ENGINE                                         ;
;                          -----------                                         ;
; This routine implements BRESHENHAM'S RUN LENGTH SLICE ALGORITHM              ;
;                                                                              ;
; The description of the algorithm can be obtained from the file LINE.DOC      ;
;                                                                              ;
; The pseudo line runs from (0,0) to (DI,SI)                                   ;
;                                                                              ;
; AX, BX, CX, DX, DI, SI, DS are trashed                                       ;
;                                                                              ;
;------------------------------------------------------------------------------;

Draw_Engine     proc    near

        or      si,si                   ; is the line horizontal ?
        jnz     non_horizontal          ; no

; we have got a horizontal line on scan line on the X axis

        mov     Ya,si                   ; the only scan line
        mov     cScans,si               ; no more lines to scan
        mov     ax,Xb
        sub     ax,Xa                   ; will give no of points to set on
        inc     ax                      ; include both end points
        mov     Cb,ax                   ; give last scan length slice
        jmp     find_out_dda            ; decide direction of draw/move

non_horizontal:

;------------------------------------------------------------------------------;
; compute the various slope quantities                                         ;
;                                                                              ;
; m      = floor(s)                                                            ;               ;
; wFracS = frac(s)  (fraction in units of 1/dy)                                ;
;------------------------------------------------------------------------------;

        mov     ax,di                   ; has dx
        xor     dx,dx                   ; reset for division
        div     si                      ; AX has quotient = floor(s)
        mov     cm,ax                   ; save m
        mov     wFracS,dx               ; DX has remainder

;------------------------------------------------------------------------------;
; compute the starting scan no:                                                ;
;                                                                              ;
; Divide [2dy.xa - 2dy.f0 + dx - 1] by 2dx                                     ;
; ya = quotient of the division, rm the remainder                              ;
;                                                                              ;
; remember 2dx may overflow into 17 bits                                       ;
;------------------------------------------------------------------------------;

        add     si,si                   ; 2dy
        mov     ax,Xa
        mul     si                      ; 2dy.xa
        mov     bx,di                   ; dx
        dec     bx                      ; dx - 1
        xor     cx,cx

; 2dyf0 will be -1 if the LSB of the HIBYTE of XformFlags is 1

        cmp     byte ptr XformFlags[1],1
        .errnz  (VERTICAL_FLIP - 100h)

        cmc                             ; carry will be one if 2dyf0 = -1
        adc     ax,bx
        adc     dx,cx                   ; DX:AX has dividend

        shr     dx,1
        rcr     ax,1                    ; we have divided by 2
        adc     cx,cx                   ; store carry out

; as we have divided by 2 by shifting, the final carry out will contribute
; to rm

        div     di                      ; divide result by dx
        mov     Ya,ax                   ; quotient gives start scan ordinate

; DX has the remainder of division by dx, where the dividend happened to be
; the quotient after the divide by 2 above. Therefore rm that we need is actually
; now,
;               rm = 2.DX + CX

;------------------------------------------------------------------------------;
; compute the first run                                                        ;
;                                                                              ;
; Ca = floor (s - (rm+1)/2dy) + 1                                              ;
;                                                                              ;
; remember SI has 2dy                                                          ;
;                                                                              ;
; s - (rm+1)/2dy  =  (2dx - rm - 1)/2dy  = (2(dx-DX) - (CX+1))/2dy             ;
;------------------------------------------------------------------------------;

        mov     ax,di                   ; get dx
        sub     ax,dx                   ; dx - DX
        xor     dx,dx                   ; zeroise for addition overflow
        add     ax,ax
        adc     dx,dx                   ; DX:AX has 2(dx-DX)
        inc     cx
        sub     ax,cx
        sbb     dx,0                    ; DX:AX has dividend
        div     si                      ; divide by 2dy
        inc     ax
        mov     Ca,ax                   ; sace Ca

;------------------------------------------------------------------------------;
; compute the initial error term                                               ;
;                                                                              ;
;  f1' = frac(s -(rm+1)/2dy) + frac(s) - 1                                     ;
;                                                                              ;
;  DX has currently the first frac in units of 1/2dy, frac(s) was calculated in;
;  terms of 1/dy.  As just the sign of f1' is used in decision, we shall get   ;
;  first term also in units of 1/dy                                            ;
;------------------------------------------------------------------------------;

        shr     dx,1                    ; get frac in units of 1/dy
        add     dx,wFracS
        sub     dx,cdy                  ; subtract 1 in units of 1/dy
        mov     wError,dx               ; the first error term
        mov     davidw,dx                   ; es will be used as work err register

;------------------------------------------------------------------------------;
; compute the last scanline ordinate:                                                  ;
;                                                                              ;
; Divide [2dy.xb - 2dy.f0 + dx - 1] by 2dx                                     ;
; yb = quotient of the division, rm' the remainder                             ;
;                                                                              ;
; remember 2dx may overflow into 17 bits                                       ;
;------------------------------------------------------------------------------;

        mov     ax,Xb
        mul     si                      ; 2dy.xb
        mov     bx,di                   ; dx
        dec     bx                      ; dx - 1
        xor     cx,cx

; 2dyf0 will be -1 if the LSB of the HIBYTE of XformFlags is 1

        cmp     byte ptr XformFlags[1],1
        .errnz  (VERTICAL_FLIP - 100h)

        cmc                             ; carry will be one if 2dyf0 = -1
        adc     ax,bx
        adc     dx,cx                   ; DX:AX has dividend

        shr     dx,1
        rcr     ax,1                    ; we have divided by 2
        adc     cx,cx                   ; store carry out

; as we have divided by 2 by shifting, the final carry out will contribute
; to rm'

        div     di                      ; divide result by dx
        mov     Yb,ax                   ; quotient gives start scan ordinate

; DX has the remainder of division by dx, where the dividend happened to be
; the quotient after the divide by 2 above. Therefore rm that we need is actually
; now,
;               rm' = 2.DX + CX

        sub     ax,Ya                   ; will give the no of scan lines
        mov     cScans,ax

; if Ya = Yb then we are clipped to be horizontal

        jnz     still_not_horizontal

; we have got a horizontal line on scan line Ya

        mov     ax,Xb
        sub     ax,Xa           ; no of pels to set on
        inc     ax                      ; include both end points
        mov     Cb,ax                   ; save slice length
        jmp     short find_out_dda      ; decide on draw/move directions
still_not_horizontal:

;------------------------------------------------------------------------------;
;compute the last slice length:                                                ;
;                                                                              ;
; Cb = ceil(rm' + 1)/2dy                                                       ;
;                                                                              ;
; note rm' = 2DX + CX                                                          ;
;------------------------------------------------------------------------------;

        mov     ax,dx
        xor     dx,dx                   ; reset for add overflow
        add     ax,ax
        adc     dx,dx                   ; DX:AX has 2DX
        inc     cx                      ; include the 1 to be added
        add     ax,cx
        adc     dx,0                    ; DX:AX has rm' + 1
        div     si                      ; divide by 2.dy
        neg     dx                      ; if there was rem, carry will be set
        adc     ax,0                    ; gives the ceiling value
        mov     Cb,ax                   ; save last slice length

find_out_dda:

;------------------------------------------------------------------------------;
;we will first have to advance the style mask for clipping:                    ;
;                                                                              ;
;The portion of the line which is being skipped corresponds to (0,0) to (xa,ya);
;we will use the formula  z = (major-minor)*f1 + minor*f2 to decide by how much;
;the style mask and the error term has to be advanced.                         ;
;                                                                              ;
;------------------------------------------------------------------------------;

        cmp     LineStyle,PS_SOLID      ; skip for solid lines
        jz      no_style_adjust
        cmp     LineStyle,PS_NULL       ; skip for null lines too
        jz      no_style_adjust

; now the portion of the line from (0,0) to (xa,ya) is not going to be drawn
; so the style mask has to be advanced. We will use the formula:
;               z = f1*(major-minor) + f2*minor
; f1 and f2, we have ensured, have the correct values depending on the actual
; direction of progress of the line.

        mov     ax,Xa                   ; the major coordinate
        mov     bx,Ya                   ; the minor coordinate
        sub     ax,bx
        mul     f1                      ; f1*(major-minor)
        xchg    ax,bx                   ; get the minor coordinate
        mul     f2
        add     ax,bx                   ; total add factor
        add     bStyleError,al          ; update the error term
        adc     ah,0                    ; ah has the style mask state
        mov     cl,ah
        and     cl,7                    ; sate can be from 0 to 7
        rol     bStyleMask,cl           ; get the mask into position
no_style_adjust:

;------------------------------------------------------------------------------;
; the move routine for the side step has  two functions:                       ;
;                                                                              ;
;               . it rotates the current bit position by 1 bit (oe does not)   ;
;               . moves the byte position to the next scan (or does not)       ;
;                                                                              ;
; it may do one or both of the above steps depending on the direction of the   ;
; move.  We will use two flags cRotate and cStep. cRotate (either 0 or 1) tell ;
; us by how much we rotate the current bit and cStep (either 0,NextScan or     ;
; -NextScan) tell us by how much the current byte has to be stepped. CL will be;
; the temporary storage for rotation flag and CH will tell us whether we need  ;
; step to next scan or not. We start with CL = 1 and CH = 1, ie, we need to do ;
; rotation and step in positive Y direction. We will test the transformations  ;
; we have undergone to get to the correct decision.                            ;
;                                                                              ;
; Note, to calculate the address in memory of the first point, we need to step ;
; back (xa,ya) through the reverse of the transformations and translate them   ;
; wrt the start point of the line. We do all these below:                      ;
;------------------------------------------------------------------------------;

        mov     si,NextScan             ; distance to the next scan line
        mov     bx,Xa
        mov     ax,Ya                   ; (Xa,Ya) the clipped pseudo start pt
        mov     cx,101h

; so our default decision is that we are moving towards higher memory, ie Y
; value increases, and that the step direction is really diagonal. This makes
; us assume that we are in the first fourth quadrant.

; test whether the half_flip was done or not

        mov     di,XformFlags
        test    di,HALF_FLIP
        jz      test_XY_XCHG            ; it was not done

; for HALF FLIP, the actual value of the ordinate of the end point can be
; obtained by subtracting the transformed ordinate from the abscissa. The
; actual and the transformed abscissa are the same. I a line has been half-
; -flipped, the step direction is horizontal so, CH should be set to false

        sub     ax,bx
        neg     ax                      ; the ordinate before transformation
        xor     ch,ch                   ; reset step scan flag for side step

; test for reflection about 45 degree line

test_XY_XCHG:
        test    di,XY_XCHG
        jz      test_Y_FLIP             ; reflection was not done
        xchg    ax,bx                   ; actual end point coordinates
        xchg    ch,cl                   ; rotation and step interchanged

; test for reflection about the X axis

test_Y_FLIP:
        test    di,Y_FLIP
        jz      tests_done
        neg     ax                      ; actual Y is -Y
        neg     si                      ; will be going up in display mem

tests_done:
        mov     cRotation,cl            ; no of bits to ratate by (0 or 1)
        mov     cScanMove,si            ; offset to move to next(prev) scan
        neg     ch                      ; setting up mask
        mov     cl,ch                   ; make it a word
        and     si,cx

; si will be forced to zero if no scan move during step is necessary

        mov     cScanStep,si            ; offset used in step routines

; now we will calculate the offset in the display memory of the first point

; first we translate the clipped start point wrt the actual start

        add     bx,StartX
        add     ax,StartY
        mov     di,bx                   ; load Xi into di
        xor     dx,dx                   ; will hold SEGMENT value for MAPS

; we will set the no of scans left from bot to a large value for small maps
; we will set it to 1/2 of wScans for small bitmaps
        mov     ScansLeftFromBot,0ffffh/2

if	?PARTIAL_SCANLINES
	test	DeviceFlags,TYPE_IS_DEV
        jnz     calculate_for_screen       ; target is ega
endif
	; DI := BX * BytesPerPixel
	mov	cl,BytesPerPixel
@@:
	dec	cl
	jz	@F
	lea	di,[bx+di]
	jmp	@B

@@:
ife	?PARTIAL_SCANLINES
	test	DeviceFlags,TYPE_IS_DEV
        jnz     calculate_for_screen       ; target is ega
endif
        test    DeviceFlags,TYPE_IS_HUGE
        jz      calculate_for_small     ; small bit maps

; calculate address for huge maps here

get_segment_loop:
        sub     ax,wScans               ; subtract no of scans/seg from Y
        jc      positioned_in_segment
        add     dx,NextSegOff           ; move onto the next segment
        jmp     short get_segment_loop  ; continue till postioned in req seg
positioned_in_segment:
        neg     ax                      ; ax has no of scan lines from bot
        mov     ScansLeftFromBot,ax     ; save it
        neg     ax
        add     ax,wScans               ; ax now has scan pos from top of seg

; at this point the segment offset has been calculated and we can do the
; code below for both small and huge maps

calculate_for_small:

	push	dx			; has offset to correct segment
        mul     NextScan                ; mutiply relative Y by bytes/scan
        pop     dx                      ; get back segment value
        add     ax,BitmapOffset         ; start offset of map
        add     dx,BitmapSegment        ; start segment for map
        mov     TempCurSeg,dx           ; save start segment value
        mov     ds,dx                   ; load ds

        test    DeviceFlags,TYPE_IS_BYTEMAP
        jnz     calculate_for_bytemap

        mov     cx,di                   ; get Xi into cx
        shiftr  di,3                    ; divide by 8 to get # bytes to move
        add     ax,di                   ; this is the byte offset
        mov     TempCurByte,ax          ; save it
        mov     TempCurByteSty,ax       ; save another copy for styled lines
        and     cx,7                    ; get the bit offset in the byte
        mov     bl,80h                  ; initial bit mask
        ror     bl,cl                   ; get the initial bit mask
        mov     TempCurBit,bl           ; save it
        jmp     short calculate_addr_for_draw

; calculate address for byte/pixel "byte"map here

calculate_for_bytemap:
        add     ax,di
        mov     TempCurByte,ax
        mov     TempCurByteSty,ax
	mov	bl,BytesPerPixel
        mov     TempCurBit,bl
        jmp     short calculate_addr_for_draw

calculate_for_screen:

ife	?PARTIAL_SCANLINES
	inc	dx
	sub	ax,wScans		; subtract no of scans/seg from Y
	jnc	calculate_for_screen

	dec	dx
	neg	ax			; ax has no of scan lines from bot
	mov	ScansLeftFromBot,ax	; save it
	neg	ax
	add	ax,wScans		; ax now has scan pos from top of seg
else
;
;	Let's try some new code to handle the general case...
;	Remember we now have DI == BX == StartX, AX == StartY
;
        mul     NextScan	; DX:AX := Beginning of scanline
	mov	cx,dx
	xchg	ax,bx
	; Now CX:BX == Beginning of Yi scanline, AX == StartX
	xor	dx,dx
	mov	dl,BytesPerPixel
	mul	dx		; DX:AX := Beginning position w/i scanline
	; Now DX:AX = Offset of Xi within current scanline
	add	bx,ax
	adc	cx,dx
	; Now CX:BX = Offset of desired Xi,Yi point, in densely-packed case
	; What if there are unused bytes in each segment?
	mov	di,FillBytes
	test	di,di
	jz	no_fill

	neg	di	; 64K - FillBytes = actual # of used bytes per segment
	mov	dx,cx
	mov	ax,bx
	div	di
	; Now AX:DX = Offset of desired Xi,Yi point, plus FillBytes per seg
	mov	cx,ax
	mov	bx,dx

no_fill:
	; Set DX:DI to the offset
	mov	dx,cx
	mov	di,bx
endif	; Back to common code...

	mov	bank_select,dl		; initialize current bank
        mov     TempBank,dl

        SET_BANK 

	mov	ds,TempCurSeg		; for EGA segment value saved

if	?PARTIAL_SCANLINES
	mov	ax,di			; all the multiplying up's already done
else
        mul     NextScan
        add     ax,di                   ; make DS:DX:AX = absolute video address
endif

        add     ax,TempCurOff           ; + screen begin offset
        mov     TempCurByte,ax
        mov     TempCurByteSty,ax
	mov	bl,BytesPerPixel
        mov     TempCurBit,bl

	; TODO: Ensure all the subfunctions return the right reg vals?

calculate_addr_for_draw:
        xor     ax,ax
        mov     al,DeviceFlags
        and     al,0fh                  ; get the low nibble
        push    ax                      ; save it
        shiftl  al,4                    ; * 16, each table of 16 bytes
        mov     si,ax                   ; si selects the table
        mov     bx,XformFlags           ; get flags
        and     bx,0fh                  ; index is the last nibble
        shl     bx,1                    ; each entry 2 bytes
	mov	ax,[DrawTable_solid_bm][si][bx]
        mov     S1,ax                   ; the draw direction
        pop     ax                      ; get back device flag
        shr     al,1                    ; take out styl info
        shiftl  al,4                    ; multiply by 16
        mov     si,ax
	mov	ax,[MoveTable_bm][si][bx]
        mov     S1_Move,ax

; for BITMAPS calculate the masks for the ROP codes

        test    DeviceFlags,TYPE_IS_DEV ; is it screen ?
        jnz     save_vars
	mov	al,bptr ForeColor	; color of the pen
        mov     ROPcolor,al		; to be used for ROP mask calculations

save_vars:

; save the variables wchich will be used for style draw pass
	mov	ax,ForeColor.lo
	mov	dx,ForeColor.hi
	mov	TmpColor.lo,ax		; save forground color
	mov	TmpColor.hi,dx		; save forground color

	mov	ax,cScans
        mov     cTempScans,ax           ; save it
        mov     al,bStyleError          ; error at start
        mov     bTempStyleError,al      ; save it
        mov     al,bStyleMask           ; mask at start of line
	not	al			;JAK bg = 1 fg = 0
	mov	bTempStyleMask,al	; save it
        mov     StylePass,0             ; reset style pass var

	mov	si,cScanMove		; offset to move to next scan
        mov     di,TempCurByte          ; current byte offset
do_another_pass:
	; Initialize and/xor masks for mono bitmaps
	test	DeviceFlags,TYPE_IS_BYTEMAP
	jnz	@F

	push	bx			; I don't know if this is necessary

	mov	bx, DrawModeIndex	; has the zero based rop code
	ror	ROPcolor,1		; rotate the color
	jnc	color_bit_is_0		; the color for this plane is 0
	shiftr	bx,2			;IDIV by 4

color_bit_is_0:
	and	bx,3			; MOD 4
	add	bx,bx			; double up for word retrieval
	mov	ax,[BitmapMaskTable][bx]
	mov	wBitmapROP,ax		; save it

	pop	bx


@@:	; continue on initializing
        mov     ax,TempCurSeg           ; get the start segment
        mov     ds,ax
        mov     dx,ScansLeftFromBot
        mov     bl,TempCurBit           ; bl has current bit mask
        mov     ax,cTempScans           ; the initial value of cScans
        mov     cScans,ax               ; reload it

        or      ax,ax                   ; is cScans = 0

;current 8 bytes out of range
;        jz      do_the_last_scan        ; one slice line
	jnz	@F
	jmp 	do_the_last_scan
@@:


; draw the first slice

        mov     cx,Ca                   ; first slice length

	mov	ax,StyleAdvOrBypass
	cmp	ax,offset style_advance_bypass
	jne	dl_jmpexit

	test	DeviceFlags,TYPE_IS_DEV
	jz	dl_jmpexit
	mov	ax,BM8
	cmp	ax,offset BM8_ROPC
	jne	dl_jmpexit
	cmp	FillBytes,0
	jne	dl_jmpexit

	mov	ax,S1_Move
	cmp	ax,offset Bm8_Move_Positive_X 
	je	dl_Diagonal
	jmp	dl_draw_loop
dl_jmpexit:
	jmp	dl_exit

dl_Diagonal:
	mov	ax,S1
	cmp	ax,offset Bm8_Diagonal_1Q
	mov	dh,byte ptr TmpColor
	je	dl_Diag_1Q_posx

dl_draw_loop:
        call    S1                      ; draw the slice
        call    S1_Move                 ; step to the next slice

        dec     cScans                  ; one more scan done
        jz      dl_do_last_scan

newErTmMAC macro
;---------------------------------------
; get the intermediate run length and the new error term

        mov     cx,cm                   ; m
        mov     ax,davidw                   ; the error term
        or      ax,ax
        js      @F
        inc     cx                      ; one more pel to draw

;------------------------------------------------------------------------------;
; note that we had had,                                                        ;
; fn+1' = fn' + frac(s) - 1        if fn' positive                             ;
;       = fn' + frac(s)            if fn' negative                             ;
;                                                                              ;
; the fractions are all in units of 1/dy, so 1 in the above equation will be dy;
;------------------------------------------------------------------------------;

        sub     ax,cdy                  ; add '1' in units of 1/dy
@@:
        add     ax,wFracS               ; this is the new error
        mov     davidw,ax                   ; save it
	endm

	newErTmMAC

	jmp short dl_draw_loop
dl_do_last_scan:
	jmp	do_the_last_scan


dl_Diag_1Q_posx:
	;Single Line Diagonal

	;S1==Bm8_Diagonal_1Q
	;S1_Move==Bm8_Move_Positive_X
dl_Q1posx_loop:

        call    S1                      ; draw the slice

	;mov	dh,TmpColor
	dec	cx 	;last pixel addressing?ds:di
	jz	dl_Q1_lastpixel
dl_Q1_loop:
	;mov	[di],dh
	inc	di
	add	di,si
	jnc	dl_Q1_decbank
dl_Q1_lcont:
	dec	cx
	jnz	dl_Q1_loop

dl_Q1_lastpixel:
	;mov	[di],dh
	inc	di

        dec     cScans                  ; one more scan done
        jz      dl_do_last_scan

	newErTmMAC 

	jmp short dl_Q1posx_loop

dl_Q1_decbank:
	dec	bank_select
	mov	dl,bank_select
	SET_BANK	;call	SetCurrentBankDL
  dec	cx	
  jnz	dl_Q1_loop
	jmp	dl_Q1_lastpixel

;	jmp short dl_Q1_lcont

dl_exit:
;------------------------

draw_loop:
WriteAux <'DrwS1'>
        call    S1                      ; draw the slice
        call    S1_Move                 ; step to the next slice
        call    StyleAdvOrBypass        ; advance style for styled lines

        dec     cScans                  ; one more scan done
        jz      do_the_last_scan

; get the intermediate run length and the new error term

        mov     cx,cm                   ; m
        mov     ax,davidw                   ; the error term
        or      ax,ax
        js      last_err_negative
        inc     cx                      ; one more pel to draw

;------------------------------------------------------------------------------;
; note that we had had,                                                        ;
; fn+1' = fn' + frac(s) - 1        if fn' positive                             ;
;       = fn' + frac(s)            if fn' negative                             ;
;                                                                              ;
; the fractions are all in units of 1/dy, so 1 in the above equation will be dy;
;------------------------------------------------------------------------------;

        sub     ax,cdy                  ; add '1' in units of 1/dy
last_err_negative:
        add     ax,wFracS               ; this is the new error
        mov     davidw,ax                   ; save it
        jmp     short draw_loop

	;-------------------------------------------------------
do_the_last_scan:
        mov     cx,Cb                   ; the last slice length
        call    S1                      ; draw the slice

all_passes_done:

        test    DeviceFlags,TYPE_IS_STYLED
	jz	return_from_engine	; we are done
        cmp     BackMode,OPAQUE         ; opaque background ?
	jne	return_from_engine	; do not have to draw gaps

;
; we begin the style draw pass for the gaps
;
style_draw_pass:
	xor	StylePass,1		; set indicator
	je	return_from_engine
	mov	ax,BackColor.lo		; background color
	mov	dx,BackColor.hi		; background color
        mov     TmpColor.lo,ax
        mov     TmpColor.hi,dx
        mov     ROPcolor,al		; to be used for BITMAP masks
        mov     di,TempCurByteSty       ; initial byte offset
        mov     dl,TempBank
        mov     bank_select,dl

        SET_BANK

        mov     TempCurByte,di          ; reload it into work var
        mov     ax,wError               ; initial ereror term
        mov     davidw,ax                   ; load it into work variable
        mov     al,bTempStyleError      ; error at start of draw
        mov     bStyleError,al          ; reload it
        mov     al,bTempStyleMask       ; mask at start of draw
        mov     bStyleMask,al           ; load mask for gaps
        jmp     do_another_pass         ; start afresh

return_from_engine:
        ret

Draw_Engine     endp
;-----------------------------------------------------------------------------;
;                       STYLE_ADVANCE                                         ;
;                       -------------                                         ;
;  Advances the style error term and the mask after the side step             ;
;-----------------------------------------------------------------------------;

style_advance   proc    near

        mov     cl,bStyleError          ; the current error term
        xor     ch,ch
        add     cx,SideStep             ; add the step error term
        mov     bStyleError,cl          ; update
        mov     cl,ch                   ; rotate if ch nonzero
        rol     bStyleMask,cl           ; rotate mask
style_advance_bypass:
        ret

style_advance   endp


;
; V7VGA - 256K bank select routines
;
; Written by: Larry Coffey
; Date: 1/21/89
;
;       Set A000:0000 to point to the next bank of 64K
;
;       Entry:  none
;       Exit:   none
;
;       Assume: VRAM VGA in extended 256 color mode
;
inc_bank_select proc    near
        push    dx
        mov     dl,bank_select
        inc     dl
        inc     bank_select

        SET_BANK

        pop     dx
        ret
inc_bank_select endp
;
;
;       Set A000:0000 to point to the previous bank of 64K
;
;       Entry:  none
;       Exit:   none
;
;       Assume: VRAM VGA in extended 256 color mode
;
dec_bank_select proc    near
        push    dx
        mov     dl,bank_select
        dec     dl
        dec     bank_select

        SET_BANK

        pop     dx
        ret
dec_bank_select endp
;                                                                            ;
;----------------------------------------------------------------------------;

include clip.asm
include polybitm.asm
include plybitm8.asm
include polystyl.asm

sEnd    LineSeg

        END
