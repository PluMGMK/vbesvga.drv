;-----------------------------------------------------------------------------
;
;   Screen Grabber for IBM EGA/VGA adaptor
;
;   These routines perform misc grabber functions
;           (functions other than paint/grab etc)
;
;    (C) Copyright MICROSOFT Corp. 1986-1990
;
;    ************* MICROSOFT CONFIDENTIAL ******************
;
;-----------------------------------------------------------------------------

.386p
?386 = 1

memS	equ	1

	.xlist
	include wcmacros.inc

	NOTEXT		= 1
	NOGDICAPMASKS	= 1
	NOMB		= 1
	NOVK		= 1
	NOWH		= 1
	NOMST		= 1
	NORASTOPS	= 1
	NOMETAFILE	= 1
	NOWM		= 1
	NOMDI		= 1
	NOWINMESSAGES	= 1
	NOSYSMETRICS	= 1
	NOCOLOR 	= 1
	NOCOMM		= 1

	include    windows.inc
	include    vmda.inc
	include    int2fapi.inc
	include    grabpnt.inc
	include    grabmac.inc
	include    vmdavga.inc
	include    vga.inc
	include    statusfl.inc
	.list

IF1
    IFDEF DEBUG
	%out DEBUG VERSION!!!!!
    ENDIF
ENDIF

;-----------------------------------------------------------------------------
;
; External Windows Procedures
;
externFP	DestroyCaret
externFP	GetPrivateProfileString

;-----------------------------------------------------------------------------
;
; External GRABBER Procedures
;
externNP        GetTextWidHgt
externNP	CursorPos
externNP	CheckCtrlState
externNP	MakeNewCursor
IFDEF   FASTGRAB
externNP        DeAllocGrfxRes
ENDIF


;-----------------------------------------------------------------------------

sBegin	code
	assumes cs,code

;
; This is the VDD type string that we expect as part of the version check
;
IFDEF VGA
VDD_Type db	"VIDEOVGA"
ELSE
VDD_Type db	"VIDEOEGA"
ENDIF

;*****************************************************************************
;
; GrabEvent - Private VDD -> Grabber messages
;
;   Provides a private channel of event communication between the VDD
;   and the grabber. EGA/VGA grabbers do not use this.
;
; ENTRY:
;	lpPntStruc Extended paint structure
;	wParam = parameter from VDD message
;	lParam = parameter from VDD message EVENT ID
; EXIT:
;	None
; USES:
;	C Standard
;
;*****************************************************************************
cProc  GrabEvent,<FAR,PUBLIC>

	ParmD	lpPntStruc
	ParmW	wParam
	ParmD	lParam

	localV	FrameVars,StdGrbFrameSz
cBegin
;	    push    esi
;	    push    edi
;
;	    InitBasicFrame
;
;	    pop     edi
;	    pop     esi
cEnd

;*****************************************************************************
;
; ScreenFree - Free any stuff associated with this app
;
;   Frees any resources associated with this app
;   that are not allocated on an as need basis local to
;   each call on the stack, or staticly stored in the grabber
;   area of the extended paint structure.
;
;   FOR THE EGA/VGA grabbers this routine is a NOP.
;
; ENTRY:
;	lpPntStruc Extended paint structure
; EXIT:
;	Any allocated stuff associated with app is freed
; USES:
;	C standard
;
;*****************************************************************************
cProc  ScreenFree,<FAR,PUBLIC>

	ParmD	lpPntStruc

;;;     localV  FrameVars,StdGrbFrameSz
cBegin
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing

;;;     InitBasicFrame

IFDEF   FASTGRAB
        push    si
        lds     si,lpPntStruc
        call    DeAllocGrfxRes  ; free any persistent graphics data
        pop     si
ENDIF
cEnd

;*****************************************************************************
;
; SetPaintFnt - Set the paint font
;
; This routine Sets the font for painting in the Extended paint structure
;	so that WINOLDAP can compute the paint rectangle for us on PaintScreen
;	calls. This is called right before a call to PaintScreen. It is also
;	called right before a call to UpdateScreen.
;
; ENTRY:
;	lpPntStruc Extended paint structure
;	lpWidFullScr	word pointer for width return
;	lpHeightFullScr word pointer for height return
; EXIT:
;	FntHgt and FntWid values in EXTPAINTSTRUC set
;	NOTE: Values set to 0 if graphics screen!!!!!
;	[lpWidFullScr] = Width of full screen in pix (text or Graphics)
;	[lpHeightFullScr] = Height of full screen in pix (text or Graphics)
;	DX is height of full screen in scan lines if Graphics
;				   in text lines if Text
;	AX is width of full screen in Pix if Graphics
;				   in chars if Text
; USES:
;	C Standard
;
;*****************************************************************************
cProc  SetPaintFnt,<FAR,PUBLIC>

	ParmD	lpPntStruc
	ParmD	lpWidFullScr
	ParmD	lpHeightFullScr

	localV	FrameVars,StdGrbFrameSz
cBegin
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	esi
	push	edi

	InitBasicFrame

	lds	si,lpPntStruc
	call	CheckCtrlState
    ;
    ; Now ds:bx,ds:si -> EXTPAINTSTRUC structure
    ;
	mov	dl,[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode]
	cmp	dl,7
	je	short FontYes
	cmp	dl,4
	jb	short FontYes
    ;
    ; Graphics screen
    ;
	xor	ax,ax
	mov	[bx.FntHgt],ax
	mov	[bx.FntWid],ax
	mov	cx,GrxBitWid640
	mov	bx,GrxBitHeight400
IFDEF VGA
	cmp	dl,0FH
	jb	short LowScrS
	cmp	dl,13H
	je	short LowScrS
	mov	bx,GrxBitHeight350
	cmp	dl,10H
	je	short LowScrS
	cmp	dl,0FH
	je	short LowScrS
	mov	bx,GrxBitHeight480
ELSE
	cmp	dl,10H
	jne	short LowScrS
	cmp	dl,0FH
	je	short LowScrS
	mov	bx,GrxBitHeight350
ENDIF
LowScrS:
	mov	dx,bx
	mov	ax,cx
	jmp	short SPDone

FontYes:
    ;
    ; Text, set font parms
    ;
        call    GetTextWidHgt
	mov	[bx.FntWid],cx
	mov	[bx.FntHgt],si
	xor	ax,ax
	mov	al,[bx.EPGrabDTA.CntrlSt.VDA_EGA_Rows]
	push	dx
	mul	si
	pop	dx
	mov	si,bx
	mov	bx,ax			; BX is height in PIX of full screen

	mov	ax,80			; Assume 80 cols
	cmp	dl,1
	ja	short TxtFW
	shr	ax,1			; 40 cols
TxtFW:
	push	ax			; Save total columns
	mul	cx
	mov	cx,ax			; CX is width in PIX of full screen
	pop	ax
	xor	dx,dx
	mov	dl,[si.EPGrabDTA.CntrlSt.VDA_EGA_Rows]
SPDone:
	les	di,lpWidFullScr
	mov	word ptr es:[di],cx
	les	di,lpHeightFullScr
	mov	word ptr es:[di],bx

	pop	edi
	pop	esi
cEnd


ProfileSect	db	"386ENH",0
ProfileFile	db	"SYSTEM.INI",0

;*
;
; The following table defines the 6 extra fonts we want VMDOSAPP to load for
;	us (actually only need four extra).

FontList	Label	byte
F1	db	"EGA80WOA.FON",0	; Name	 <= 25 line mode 80 column
.erre ($-F1) EQ 13
	dw	12			; Height
	dw	8			; Width

F2	db	"EGA40WOA.FON",0	; Name	 <= 25 line mode 40 column
.erre ($-F2) EQ 13
	dw	12			; Height
	dw	16			; Width

F3	db	"CGA80WOA.FON",0	; Name	 >  25 line mode 80 column
.erre ($-F3) EQ 13
	dw	8			; Height
	dw	8			; Width

F4	db	"CGA40WOA.FON",0	; Name	 >  25 line mode 40 column
.erre ($-F4) EQ 13
	dw	8			; Height
	dw	16			; Width

	db	13 DUP (0)		; Unused
	dw	0
	dw	0

	db	13 DUP (0)		; Unused
	dw	0
	dw	0
FListSize equ	 $-FontList

;*****************************************************************************
;
; GetFontList - Return pointer to font list
;
; This routine returns a pointer to the list of extra fonts we want loaded
;
; ENTRY:
;	lpFontBuf -> Buffer for font info
; EXIT:
;	Font Buffer filled in
; USES:
;	C standard
;
;*****************************************************************************
cProc  GetFontList,<FAR,PUBLIC>

	ParmD	lpFontBuf

	localV	FrameVars,StdGrbFrameSz
cBegin
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	esi
	push	edi

	InitBasicFrame

	push	cs
	pop	ds
	mov	si,codeOffset FontList
	les	di,lpFontBuf
	mov	cx,FListSize
	cld
	rep	movsb

	lds	di,lpFontBuf
	mov	cx,4
	regptr	pFnt,ds,di
GetProLoop:
	mov	ax,codeOffset ProfileSect
	regptr	pSect,cs,ax
	mov	bx,codeOffset ProfileFile
	regptr	pFnm,cs,bx
	push	cx
	cCall	GetPrivateProfileString,<pSect,pFnt,pFnt,pFnt,13,pFnm>
	pop	cx
	add	di,17
	loop	GetProLoop

	pop	edi
	pop	esi
cEnd

;*****************************************************************************
;
; GrbUnlockApp - Unlock the application (allow it to run)
;
;     This routine undoes the implied LOCK OUT of app changes done by
;	GetDisplayUpd
;
; ENTRY:
;	lpPntStruc Extended paint structure
; EXIT:
;	None
; USES:
;	C Standard
;
;*****************************************************************************
cProc  GrbUnlockApp,<FAR,PUBLIC>

	ParmD	lpPntStruc

	localV	FrameVars,StdGrbFrameSz
cBegin
	push	esi
	push	edi

	InitBasicFrame

	lds	si,lpPntStruc

	mov	ax,GRB_Unlock_APP
	mov	ebx,[si.ThisVMHand]
        call    [si.GGrbArea.VddApiProcAdr]

	pop	edi
	pop	esi
cEnd

;*****************************************************************************
;
; CursorOn - Create cursor for app if it has one
;
; ENTRY:
;	lpPntStruc Extended paint structure
; EXIT:
;	Carret created
; USES:
;	C standard
;
;*****************************************************************************
cProc  CursorOn,<FAR,PUBLIC>

	ParmD	lpPntStruc

	localV	FrameVars,StdGrbFrameSz
cBegin
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	esi
	push	edi

	InitBasicFrame

	lds	si,lpPntStruc
	call	CheckCtrlState
    ;
    ; now, ds:bx,ds:si -> EXTPAINTSTRUC
    ;
	call	CursorPos
	call	MakeNewCursor

	pop	edi
	pop	esi
cEnd

;*****************************************************************************
;
; CursorOff - Destroy cursor for app
;
; ENTRY:
;	lpPntStruc Extended paint structure
; EXIT:
;	Carret Destroyed
; USES:
;	C standard
;
;*****************************************************************************
cProc  CursorOff,<FAR,PUBLIC>

	ParmD	lpPntStruc

	localV	FrameVars,StdGrbFrameSz
cBegin
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	esi
	push	edi

	InitBasicFrame

	lds	si,lpPntStruc
	call	CheckCtrlState
    ;
    ; now, ds:bx,ds:si -> EXTPAINTSTRUC
    ;
	mov	[si.EPGrabDTA.CurCursEnd],-1
	mov	[si.EPGrabDTA.CurCursBeg],-1
	mov	[si.EPGrabDTA.CurCursMode],-1
	cCall	DestroyCaret

	pop	edi
	pop	esi
cEnd

;*****************************************************************************
;
; CursorPosit - Return position of cursor on display
;
; ENTRY:
;	lpPntStruc Extended paint structure
; EXIT:
;	DX,AX = (Y,X) screen CoOrd of upper left of cursor
;	      = (-1,-1) if no cursor
; USES:
;	C Standard
;
;*****************************************************************************
cProc  CursorPosit,<FAR,PUBLIC>,<esi,edi>

	ParmD	lpPntStruc

	localV	FrameVars,StdGrbFrameSz
cBegin
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	esi
	push	edi

	InitBasicFrame

	lds	si,lpPntStruc
	call	CheckCtrlState
    ;
    ; now, ds:bx,ds:si -> EXTPAINTSTRUC
    ;
	call	CursorPos

	pop	edi
	pop	esi
cEnd

;*****************************************************************************
; TranslateWinToFScreen
;
; ENTRY:
;	ds:si -> lpPntStruc
;	edi = (X,Y) in windowed coordinated
; EXIT:
;	edi = (X,Y) in full-screen coordinates
;*****************************************************************************
cProc TranslateWinToFScreen,<FAR,PUBLIC>,<dx>
	parmD	lpPntStruc
cBegin
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing

    ;
    ; No translation for text modes 2,3,7
    ;
	lds	bx,lpPntStruc

	mov	dl,[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode]
	cmp	dl,1
	ja	SHORT DontDoubleX
	rol	edi,16
	shl	di,1
	rol	edi,16
	jmp	SHORT WinTOFScreenDone	; mode 0,1 40 X 25 lines...
DontDoubleX:
	cmp	dl,7
	je	SHORT WinTOFScreenDone
	cmp	dl,4
	jb	SHORT WinTOFScreenDone
	cmp	dl,13h			; double mode 13
	jne	SHORT Done13
	shr	di,1
	rol	edi,16
	shr	di,1
	rol	edi,16
	jmp	SHORT WinToFScreenDone
Done13:
	cmp	dl,0Fh
	jae	SHORT WinToFScreenDone	; >= F are correct representations
	shr	di,1			; all are doubled on Y

WinToFScreenDone:
cEnd

;*****************************************************************************
;
; CheckGRBVersion - Check out the VDD version
;
; ENTRY:
;	lpPntStruc Extended paint structure
; EXIT:
;	AX == 0
;	    OK
;	AX != 0   Bad version
;	    AX == 1
;		Version # error
;	    AX == 2
;		Display type mismatch
;	DX = Grabber Version number
; USES:
;	C Standard
;
;*****************************************************************************
cProc  CheckGRBVersion,<FAR,PUBLIC>

	ParmD	lpPntStruc

	localV	FrameVars,StdGrbFrameSz
cBegin
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	esi
	push	edi

	InitBasicFrame
    ;
    ; Get address of the procedure to call for VDD services
    ;
        mov     bx,SHELL_Call_Dev_VDD 	
	mov	ax,(W386_Int_Multiplex SHL 8) OR W386_Get_Device_API
	int	W386_API_Int
        mov     cx,es           
        or      cx,di
        jz      short cgv1              ; Invalid address, return version check failure
	lds	bx,lpPntStruc           
    ;
    ; Save the far proc address 
    ;
	mov	word ptr [bx.GGrbArea.VddApiProcAdr],di
	mov	word ptr [bx.GGrbArea.VddApiProcAdr.2],es

	mov	ax,GRB_Get_Version
	push	ds
	pop	es
	lea	di,[bx.VerStrng]		; ES:DI -> type string
	movzx	edi,di
        call    [bx.GGrbArea.VddApiProcAdr]
	cmp	ax,Grabber_VerNum
	je	short cgv2			; Version OK
cgv1:
	mov	ax,1
	jmp	short cgv3
cgv2:
	push	cs
	pop	ds
    assumes ds,code
IFNDEF	GENGRAB
	mov	si,codeOffset VDD_Type
	mov	cx,4
	cld
	repe	cmpsw
	mov	ax,2				; Assume bad
	jne	short cgv3			; Type Bad
ENDIF
	xor	ax,ax
cgv3:
	mov	dx,(GRB_VER_HIGH SHL 8) OR GRB_VER_LOW

	pop	edi
	pop	esi
cEnd


;*****************************************************************************
;
; GrbGetTextColor - given a Windows RGB Color return text color in display
;                specific format
;
; ENTRY: 
;	lpPntStruc Extended paint structure
;       RGBValue a windows RGB color
;
; EXIT: DX:AX = text color in display specific format (IRGB for EGA/VGA)
;
; USES: C standard
;
;*****************************************************************************
cProc   GrbGetTextColor,<FAR,PUBLIC>

        ParmD   lpPntStruc
        ParmD   RGBValue

	localV	FrameVars,StdGrbFrameSz
cBegin
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	esi
	push	edi

	InitBasicFrame

        xor     dx,dx
        xor     ax,ax

        mov     ebx,RGBValue
        or      ebx,ebx                ; Q: Black ?
        jz      SHORT NoInt            ;   Y: Don't set Int bit
        or      al,00001000B           ;   N: Set Int bit for all other colors
NoInt:
        mov     cx,bx
        shr     ebx,8
    ;
    ; CL = Red, CH = Green, BH = Blue
    ;
        or      cl,cl
        jz      short NoRed
        or      al,00000100B           ; Set red
NoRed:
        or      ch,ch
        jz      short NoGreen
        or      al,00000010B           ; Set green
NoGreen:
        or      bh,bh
        jz      short NoBlue
        or      al,00000001B           ; set blue
NoBlue:
        pop     edi
        pop     esi
cEnd

;*****************************************************************************
;
; WEP - DLL Exit proc (does nothing in grabber case)
;
; ENTRY:
;	fSysExit word param != 0 if System Exit as opposed to just LIB exit
; EXIT:
;	None
; USES:
;	FLAGS
;
;*****************************************************************************
cProc	Wep,<FAR,PUBLIC,NODATA>

cBegin	nogen
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	ret	2
cEnd	nogen

;*****************************************************************************
;
; InitGrabber - Library Initialization Routine
;
; ENTRY:
;	DI = Module handle of the library
;	CX = Size of local heap (should be 0)
;	DS = Seg addr of library data segment (isn't one)
; EXIT:
;	AX == 0
;	  Init Error
;	AX != 0
;	  OK
; USES:
;	AX, FLAGS
;
;*****************************************************************************
cProc	InitGrabber,<FAR,PUBLIC,NODATA>

cBegin
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	esi
	push	edi

	xor	ax,ax
	inc	ax		; Set non-zero return

	pop	edi
	pop	esi
cEnd
sEnd	code
	end	InitGrabber
