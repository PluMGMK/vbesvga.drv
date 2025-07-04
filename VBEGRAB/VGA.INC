;-----------------------------------------------------------------------------
;
;   Screen Grabber for IBM EGA adaptor in EGA compatible modes
;
;    INCLUDE FILE FOR EGA GRABBER
;
;    (C) Copyright MICROSOFT Corp. 1986-1990
;
;    ************* MICROSOFT CONFIDENTIAL ******************
;
;-----------------------------------------------------------------------------

IF1
    IFDEF   VGA
    %out VGA version
    ELSE
    %out EGA version
    ENDIF
ENDIF

IFNDEF  GENGRAB
    FASTGRAB equ 1              ; fast device-dependent bitmap support
ENDIF

;
; Grabber version EQUs
;
GRB_VER_HIGH	EQU	3
IFDEF	VGA31
GRB_VER_LOW	EQU	0ah
ELSE
GRB_VER_LOW	EQU	0
ENDIF

IFDEF	GENGRAB
GrxBitWid8514	equ	1024	; Width of graphics bitmaps on 8514.
ENDIF
GrxBitWid640	equ	640	; Width of graphics bitmaps
GrxBitHeight400	equ	400	; Height of graphics bitmaps (200*2)
GrxBitHeight350	equ	350	; Height of graphics bitmaps (350)
IFDEF	VGA
GrxBitHeight480	equ	480	; Height of graphics bitmaps (480)
ENDIF

seloff  struc
    off dw  ?
    sel dw  ?
seloff  ends

;
; Definition of layout for GrabArea in selection structure
;	See GrabArea in Selection.inc
;
MySelectStruc	struc
	StartPointX	DW	?	; Start X screen coord (fixed end point)
	StartPointY	DW	?	; Start Y screen coord (fixed end point)
	EndPointX	DW	?	; End X screen coord (active end point)
	EndPointY	DW	?	; End Y screen coord (active end point)
	Irect		DB	(size RECT) dup(?) ; Selection rect
	SelecFlags	DW	?	; Various flags
MySelectStruc	ends

;
; Bit defs for SelecFlags flag word
;
SelectOn	equ	0000000000000001B

IF2
    IF (SIZE MySelectStruc) GT (SIZE GrabArea)
	%out ******* ERROR !!!!! GrabArea Overflowed!!!!!
	Syntax error
    ENDIF
ENDIF

;
; Template for accessing data at EPGrabDTA in EXTPAINTSTRUC. 
; This piece of data is managed by the grabber only.
; 
;
GrbData STRUC

CntrlSt 	db	(SIZE VDA_EGA_State) dup (?)
CurCursBeg	dw	?
CurCursEnd	dw	?
DispMod         db      SIZE VDD_MOD_STATE dup (?)
CurCursMode	db	?

; Data for fast graphics support
GrfxMode        db      ?
GrfxhDC         dw      ?
GrfxhBitmap     dw      ?
GrfxhScanBuf    dw      ?

GrbData ENDS

IF2
    IF (SIZE GrbData) GT (SIZE EPGrabDTA)
	%out ****** ERROR !!!!!!! EPGrabDTA overflowed!!!!!!
	Syntax error
    ENDIF
ENDIF

;
; Template for accessing data Global Grabber Area, GGrbArea in EXTPAINTSTRUC
; GLOBALGRBSIZEMAX(=12) bytes long
; Data stored in this area(e.g. VddApiProcAdr got in GetGrbVersion) is 
; propagated to future instances of the grabber.
; This should not be combined with EPGrabDTA
;
GGrbAreaStruc   struc
    VddApiProcAdr   dd  ?
    GrbStatusFlags  dd  ?
    VDDDacOffset    dd  ?
    ; no unused bytes
GGrbAreaStruc   ends
        
;
; DIB related structure - should be consistent with the definition in GDI
;
BitmapInfoHeader    struc
    biSize          dd  0
    biWidth         dd  0
    biHeight        dd  0
    biPlanes        dw  0
    biBitCount      dw  0

    biCompression   dd  0
    biSizeImage     dd  0
    biXPelsPerMeter dd  0
    biYPelsPerMeter dd  0
    biClrUsed       dd  0
    biClrImportant  dd  0
BitmapInfoHeader    ends
;
; RGBTriple structure for PelColorTable entries in DIBs
;
MyRGBTriple     struc
    rgbBlue     db      ?
    rgbGreen    db      ?
    rgbRed      db      ?
    rgbResvd    db      0
MyRGBTriple     ends

;
; Structure for storing line numbers corresponding to various video pages
; Used in UpdateScreen
;
LineTabStruc    struc
    StartLine   dw      ?
    EndLine     dw      ?
LineTabStruc    ends

;
; Common frame variables
;
GrbFlags        equ     word ptr [bp-4]     ;
VidSel          equ     word ptr [bp-6]     ; Video memory selector
PgOffst         equ    dword ptr [bp-10]    ; Offset in vid mem of start
VidAddr         equ    fword ptr [bp-10]    ; Above as an fword
Gmode           equ     byte ptr [bp-12]    ; Storage for mode byte
MemState	equ	byte ptr [bp-12-(SIZE VDA_Mem_State)]

CFrm		equ	(12+(SIZE VDA_Mem_State))

InitBasicFrame	MACRO
	mov	GrbFlags,0
	mov	VidSel,0
	ENDM

;
; Masks for GrbFlags
;
GrbFlgs_GrfxDoOdd		equ	0000000000000001B
GrbFlgs_GrfxDoOddBit		equ	0
GrbFlgs_GrfxGrabBM		equ	0000000000000010B
GrbFlgs_GrfxGrabBMBit		equ	1
GrbFlgs_GrfxInvPal		equ	0000000000000100B
GrbFlgs_GrfxInvPalBit		equ	2
GrbFlgs_GrfxDispBlt		equ	0000000000001000B
GrbFlgs_GrfxDispBltBit		equ	3
GrbFlgs_GrfxInvSelReComp	equ	0000000000010000B
GrbFlgs_GrfxInvSelReCompBit	equ	4
;
; Causes us to do Get_GrbMem instead of Get_Mem unless
;  GrbFlgs_DoingWindowSelGrab is set (doing a selection via VMDOSAPP
;  on a VM in a window)
;
GrbFlgs_DoingGrab		equ	0000000000100000B
GrbFlgs_DoingGrabBit		equ	5
GrbFlgs_DoingWindowSelGrab	equ	0000000001000000B
GrbFlgs_DoingWindowSelGrabBit	equ	6

GrbFlgs_StrOdd			equ	0000000010000000B
GrbFlgs_StrOddBit		equ	7
GrbFlgs_SecScns 		equ	0000000100000000B
GrbFlgs_SecScnsBit		equ	8
GrbFlgs_ExtrOdd 		equ	0000001000000000B
GrbFlgs_ExtrOddBit		equ	9
GrbFlgs_ExtrEvn 		equ	0000010000000000B
GrbFlgs_ExtrEvnBit		equ	10
GrbFlgs_FlushLines              equ     0000100000000000B
GrbFlgs_FlushLinesBit           equ     11
IFDEF   GENGRAB
GrbFlgs_VgaMonoStatus           equ     0001000000000000B
GrbFlgs_VgaMonoStatusBit        equ     12
ENDIF

;
; masks for GrbStatusFlags
;
BlinkTurnedOff		equ	00000000000000000000000000000001b
BlinkTurnedOffBit	equ	0

;
; Define the graphics stack frame
;
IFDEF	MODE13
; if we support mode 13h, we need to make room for 256 colour entries on the stack
PalSize		equ	256
ELSE
; otherwise, 16 entries are enough...
PalSize		equ	16
ENDIF

IFDEF	MODE13
; Need a full 640 bytes per scanline, since we need to stretch the 320-byte scanlines 2x!
SzGrxFrm        equ     CFrm+90+(PalSize*4)+4+(SIZE BitmapInfoHeader)+(GrxBitWid640)
ELSEIFNDEF	GENGRAB
SzGrxFrm        equ     CFrm+90+(PalSize*4)+4+(SIZE BitmapInfoHeader)+((GrxBitWid640*4)/8)
ELSE
SzGrxFrm        equ     CFrm+90+(PalSize*4)+4+(SIZE BitmapInfoHeader)+((GrxBitWid8514*4*1)/8)
ENDIF

BcolHigh	equ	word ptr [bp-CFrm-02]	; High word of background RGB color
BcolLow 	equ	word ptr [bp-CFrm-04]	; Low word of background RGB color
BcolBlu 	equ	byte ptr [bp-CFrm-02]	; background Blue
BcolGrn 	equ	byte ptr [bp-CFrm-03]	; background Green
BcolRed 	equ	byte ptr [bp-CFrm-04]	; background Red
LineDC		equ	word ptr [bp-CFrm-06]	; hMemDC for one line
LineBitMap	equ	word ptr [bp-CFrm-08]	; hMemBitmap for one line
ScreenDC	equ	word ptr [bp-CFrm-10]	; hMemDC for whole screen
ScreenBitMap	equ	word ptr [bp-CFrm-12]	; hMemBitmap for whole screen
BkBrush 	equ	word ptr [bp-CFrm-14]	; hBrush for background
;
; NOTE Palettes MUST be contiguous and in 0,1,2,3 INCREASING order!
;
Palette3	equ	byte ptr [bp-CFrm-15]	; Palette reg 3 for mode 4, Intensity plane # for Hi-Res
Palette2	equ	byte ptr [bp-CFrm-16]	; Palette reg 2 for mode 4, Red plane # for Hi-Res
Palette1	equ	byte ptr [bp-CFrm-17]	; Palette reg 1 for mode 4, Green plane # for Hi-Res
Palette0	equ	byte ptr [bp-CFrm-18]	; Palette reg 0 for mode 4, Blue plane # for Hi-Res

RightWid	equ	word ptr [bp-CFrm-20]	; Width of "extra" on right
RightXpos	equ	word ptr [bp-CFrm-22]	; X coord of "extra" on right
BottomHig	equ	word ptr [bp-CFrm-24]	; Height of "extra" on bottom
BottomYpos	equ	word ptr [bp-CFrm-26]	; Y coord of "extra" on bottom
DDRCLeft	equ	word ptr [bp-CFrm-28]	; Left of paint rect rounded down DD
DDRCTop 	equ	word ptr [bp-CFrm-30]	; Top of paint rect rounded down DD
DDRCRight	equ	word ptr [bp-CFrm-32]	; Right of paint rect rounded up DD
DDRCWid 	equ	word ptr [bp-CFrm-34]	; Width of Screen Bitmap
DDRCHig 	equ	word ptr [bp-CFrm-36]	; Height of Screen Bitmap
DDPWid		equ	word ptr [bp-CFrm-38]	; Width of screen Bitmap in Dwords
DDRCLeftBI	equ	word ptr [bp-CFrm-40]	; Byte index of DDRCLeft
DBPWid		equ	word ptr [bp-CFrm-42]	; Width of screen Bitmap in bytes
OvscnBrsh	equ	word ptr [bp-CFrm-44]	; Brush in overscan color
LineSkip	equ	word ptr [bp-CFrm-46]	; Bytes of line not in paint rect
BDsWid		equ	word ptr [bp-CFrm-48]	; Bytes of line in display
VideoIndex      equ    dword ptr [bp-CFrm-52]   ; ptr into Video mem
SavEXTP         equ     word ptr [bp-CFrm-54]   ; save area for ptr to EXTP
SavOldBr        equ     word ptr [bp-CFrm-56]   ; Old Br in hDC - direct Blt code only
;
; Offsets to the 4 planes in the video mem are stored only for Planar modes 
; D,E,10. LookUpPalette determines the color planes. GetVidSel sets the 
; following four variables based on this.
;
IPlaneOffset    equ    dword ptr [bp-CFrm-60]   ; I Plane Offset
RPlaneOffset    equ    dword ptr [bp-CFrm-64]   ; R Plane Offset
GPlaneOffset    equ    dword ptr [bp-CFrm-68]   ; G Plane Offset
BPlaneOffset    equ    dword ptr [bp-CFrm-72]   ; B Plane Offset
IPlaneSize      equ     word ptr [bp-CFrm-74]   ; I Plane Offset
RPlaneSize      equ     word ptr [bp-CFrm-76]   ; R Plane Offset
GPlaneSize      equ     word ptr [bp-CFrm-78]   ; G Plane Offset
BPlaneSize      equ     word ptr [bp-CFrm-80]   ; B Plane Offset

fpScanBuf       equ    dword ptr [bp-CFrm-84]   ; far pointer to scanbuff
pScanCur        equ     word ptr [bp-CFrm-86]   ; offset of current scanline
pScanMax        equ     word ptr [bp-CFrm-88]   ; offset of first invalid address
nScanLines      equ     word ptr [bp-CFrm-90]   ; # of scanlines buffered
PelColorTable   equ     [bp-CFrm-90-PalSize*4]  ; Color table in DIB Hdr
DIBHdr          equ     [bp-CFrm-90-PalSize*4-SIZE BitmapInfoHeader] ; DIB Header
LineBits        equ     byte ptr [bp-SzGrxFrm]  ; One line of bits

;
; Define the text stack frame
;
SzTxtFrm equ	CFrm+32+84

StartBuf        equ     word ptr [bp-CFrm-02]   ; Save for pointer to save area
BytesPerLine    equ     word ptr [bp-CFrm-04]   ; Bytes per text line in vid mem
BytesPerLineByte equ    byte ptr [bp-CFrm-04]   ; Bytes per text line in vid mem
WidPaint        equ     word ptr [bp-CFrm-06]   ; Width in chars of paint
HigPaint        equ     word ptr [bp-CFrm-08]   ; Height in char lines of paint
BytesToRight    equ     word ptr [bp-CFrm-10]   ; Index in vid buf to left char
PToutBuf        equ     word ptr [bp-CFrm-12]   ; Pointer to text buffer
Currcols        equ     [bp-CFrm-14]            ; Current text colors set
BkTxtBrsh       equ     word ptr [bp-CFrm-16]   ; Background brush
WidRgt          equ     word ptr [bp-CFrm-18]   ; Width of extra on right
XRgt            equ     word ptr [bp-CFrm-20]   ; X of extra
HigBot          equ     word ptr [bp-CFrm-22]   ; Height of extra on Bottom
YBot            equ     word ptr [bp-CFrm-24]   ; Y of extra
TLineXPos       equ     word ptr [bp-CFrm-26]   ; X pos in line
OldBrshHand     equ     word ptr [bp-CFrm-28]   ; Save for DC brush
TrueColor       equ     byte ptr [bp-CFrm-29]   ; True color in selection invert
Unused          equ     byte ptr [bp-CFrm-30]
OldFontHand     equ     word ptr [bp-CFrm-32]   ; Save for stock font
ToutBuf         equ     byte ptr [bp-SzTxtFrm]  ; Text buffer

StdGrbFrameSz	equ	SzGrxFrm

.erre	SzGrxFrm GE SzTxtFrm
