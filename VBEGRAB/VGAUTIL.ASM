;--------------------------------------------------------------------
;
;   Screen Grabber for IBM EGA/VGA adaptor
;
;   Various helper routines for the grabber functions
;
;    (C) Copyright MICROSOFT Corp. 1986-1990
;
;    ************* MICROSOFT CONFIDENTIAL ******************
;

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
	NOMETAFILE	= 1
	NOWM		= 1
	NOMDI		= 1
	NOWINMESSAGES	= 1
	NOSYSMETRICS	= 1
	NOCOLOR 	= 1
	NOCOMM		= 1

	include    windows.inc
	include    vmda.inc
	include    grabpnt.inc
	.list
	include    grabmac.inc
	include    vmdavga.inc
	include    vga.inc
	include    statusfl.inc

IF1
    IFDEF DEBUG
	%out DEBUG VERSION!!!!!
    ENDIF
ENDIF

;-----------------------------------------------
;
; External Windows Procedures
;
externFP	BitBlt
externFP	InvertRect
externFP	CreateCaret
externFP	SetCaretPos
externFP	SetBitmapBits
ifdef	DBCS
if1
%out DBCS code enabled
endif
externFP	IsDBCSLeadByte
endif

;-----------------------------------------------
;
; External GRABBER Procedures
;

sBegin	code
	assumes cs,code

	public	StandardPal
	public	LookupPalette
	public	ScreenAdjust
	public	ComputeSelTextrect
	public	SetBitBit
	public	InvSel,InvSel2
        public  GetTextWidHgt
	public	AdjustSelGrxMax
	public	AdjustSelTextMax
	public	CursorPos
	public	CheckCtrlState
	public	GetVidSel
	public	ClearVidSel
	public	MakeNewCursor
	public	LineBlt
ifdef	DBCS
	public	AdjustDBCSBound
	public	IsDBCSMiddleText
endif


;**
;
; SetBitBit - Set one color plane of bits
;
; ENTRY:
;	SS:BP -> Graphics paint frame
;	DS:ESI -> mono bits (one line) to render
;	ES:DI -> buffer for plane
;	BH is background value for color
;	BL is foreground value for color
; EXIT:
;	DI advanced by one bit plane
; USES:
;	AX,CX,DI,SI,FLAGS
;
SetBitBit proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	cld
	mov	cx,DDPWid		; This many dwords in plane
	or	bx,bx
	jz	short NoCol		; No color in foreground or background
	or	bh,bh
	jz	short ColFor		; Foreground has color, background doesn't
	mov	eax,0FFFFFFFFH		; Assume for and back both have color
	or	bl,bl
	jnz	short StoreCol		; Both for and back have color
	; Background has color, foreground doesn't
ColLoop:
	lods dword ptr ds:[esi]
	not	eax
	stosd
;******
	db	67h			; Problem Workaround DO NOT REMOVE
	nop
;******
	loop	short ColLoop
	ret

ColFor:
	movzx	edi,di
	movzx	ecx,cx
	rep movs dword ptr es:[edi],dword ptr ds:[esi]
;******
	db	67h			; Problem Workaround DO NOT REMOVE
	nop
;******
	ret

NoCol:
	xor	eax,eax 		; No color
StoreCol:
	rep	stosd
;******
	db	67h			; Problem Workaround DO NOT REMOVE
	nop
;******
	ret

SetBitBit endp


;**
;
; ComputeSelTextrect - Compute bounds of text selection rectangle
;
; ENTRY:
;	DS:SI -> Extended paint structure
;	DS:BX -> TXTPAINTSUB sub structure of DS:SI
; EXIT:
;	[si.SelStruc.GrabArea.Irect] contains text rectangle info
;	    First Word is Row,Col of Upper Left
;	    Second Word is Row,Col of Lower Right
;	    Third Word is Hight,Width in chars of rect
;	DX = The Third word (can be tested for zero to detect NUL selection)
; USES:
;	AX,CX,DX,FLAGS
;
ComputeSelTextrect proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	mov	ax,[si.SelStruc.GrabArea.StartPointX]
	mov	cx,[si.SelStruc.GrabArea.EndPointX]
	cmp	ax,cx				; This way?
	jbe	short OkIX2			; Yes
	xchg	ax,cx				; Nope, other way
OkIX2:
	mov	dx,[bx.TPFntWid]
	div	dl				; AL is Left Col
	xchg	ax,cx				; CL is Left Col
	div	dl				; AL is Right Col
	mov	ah,cl				; AH is Left Col
	push	ax

	mov	ax,[si.SelStruc.GrabArea.StartPointY]
	mov	cx,[si.SelStruc.GrabArea.EndPointY]
	cmp	ax,cx				; This way?
	jbe	short OkIY2			; Yes
	xchg	ax,cx				; Nope, other way
OkIY2:
	mov	dx,[bx.TPFntHgt]
	div	dl				; AL is Top Row
	xchg	ax,cx				; CL is Top Row
	div	dl				; AL is Bottom Row
	mov	ah,cl				; AH is Top Row, AL is Bottom Row
	pop	dx				; DH is Left Col, DL is Right Col
	xchg	al,dh				; AH is Top Row, AL is Left Col
						; DH is Bottom Row, DL is Right Col
	mov	[si.SelStruc.GrabArea.Irect.rcLeft],ax
	mov	[si.SelStruc.GrabArea.Irect.rcTop],dx
	sub	dh,ah				; DH is height in Lines
	sub	dl,al				; DL is Width in Cols
	mov	[si.SelStruc.GrabArea.Irect.rcRight],dx
	ret

ComputeSelTextrect endp

;**
;
; InvSel InvSel2 - Invert selection
;
;   InvSel computes the invert rectangle
;   InvSel2 assumes InvSel called previously to compute rectangle
;
; ENTRY:
;	SS:BP is graphics paint frame pointer
;	DS:SI -> Extended paint structure
; EXIT:
;	Selection region inverted in ScreenDC if selection is on
; USES:
;	ALL but DS,SI,DI
;
InvSel proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	test	[si.SelStruc.GrabArea.SelecFlags],SelectOn ; In progress?
	jz	NoSelP				; No, done

	mov	ax,[si.SelStruc.GrabArea.StartPointX]
	mov	cx,[si.SelStruc.GrabArea.EndPointX]
	cmp	ax,cx				; This way?
	jbe	short OkIX			; Yup
	xchg	ax,cx				; Nope, other way
OkIX:
	mov	[si.SelStruc.GrabArea.Irect.rcLeft],ax
	mov	[si.SelStruc.GrabArea.Irect.rcRight],cx

	mov	ax,[si.SelStruc.GrabArea.StartPointY]
	mov	cx,[si.SelStruc.GrabArea.EndPointY]
	cmp	ax,cx				; This way?
	jbe	short OkIY			; Yup
	xchg	ax,cx				; Nope, other way
OkIY:
	mov	bx,DDRCTop
	cmp	bx,cx
	ja	NoSelSet			; Bottom of sel is above paint
	add	bx,DDRCHig			; BX is bottom of paint
	cmp	bx,ax
	jb	NoSelSet			; Top of sel is below paint
	sub	ax,DDRCTop
	jae	short SetST
	xor	ax,ax
SetST:
	mov	[si.SelStruc.GrabArea.Irect.rcTop],ax
	mov	ax,DDRCHig
	sub	bx,cx
	jae	short SetSB
	xor	bx,bx
SetSB:
	sub	ax,bx
	mov	[si.SelStruc.GrabArea.Irect.rcBottom],ax
	mov	ax,[si.SelStruc.GrabArea.Irect.rcLeft]
	mov	cx,[si.SelStruc.GrabArea.Irect.rcRight]
	cmp	DDRCLeft,cx
	ja	NoSelSet			; Sel right is to left of paint
	mov	bx,DDRCRight
	cmp	bx,ax
	jb	NoSelSet			; Sel left is to right of paint
	sub	ax,DDRCLeft
	jae	short SetSL
	xor	ax,ax
SetSL:
	mov	[si.SelStruc.GrabArea.Irect.rcLeft],ax
	mov	ax,DDRCWid
	sub	bx,cx
	jae	short SetSR
	xor	bx,bx
SetSR:
	sub	ax,bx
	mov	[si.SelStruc.GrabArea.Irect.rcRight],ax

InvSel2:
	test	[si.SelStruc.GrabArea.SelecFlags],SelectOn
	jz	NoSelP
	cmp	[si.SelStruc.GrabArea.Irect.rcTop],-1	; InvSel comp ok?
	jz	short NoSelP			; No
	bt	GrbFlags,GrbFlgs_GrfxDispBltBit	; Special stuff?
	jnc	short DoInvScreen		; No
	bts	GrbFlags,GrbFlgs_GrfxInvSelReCompBit
	jc	short DoInvSelDisp		; Already done computation
    ;
    ; [si.SelStruc.GrabArea.Irect] is selction rect in Full Screen DC which
    ;	we are not using. We need to modify the rect a little bit to undo
    ;	the rounding then convert it in to a rectangle on the screen
    ;
	lea	bx,[si.SelStruc.GrabArea.Irect]
    ;
    ; Resolve Right and Left
    ;
	mov	ax,[si.PGVDRect.rcLeft]
	sub	ax,DDRCLeft
	sub	[bx.rcLeft],ax
	sub	[bx.rcRight],ax
	mov	ax,[si.Pstruct.PSrcPaint.rcLeft]
	add	[bx.rcRight],ax
	add	[bx.rcLeft],ax
	cmp	[bx.rcLeft],ax
	jae	short InvS10
	mov	[bx.rcLeft],ax
InvS10:
	mov	ax,[si.Pstruct.PSrcPaint.rcRight]
	cmp	[bx.rcRight],ax
	jbe	short InvS20
	mov	[bx.rcRight],ax
InvS20:
	mov	ax,[bx.rcRight]
	cmp	ax,[bx.rcLeft]
	jbe	short NoSelSet
    ;
    ; Resolve Bottom and Top
    ;
	mov	ax,[si.PGVDRect.rcTop]
	sub	ax,DDRCTop
	sub	[bx.rcTop],ax
	sub	[bx.rcBottom],ax
	mov	ax,[si.Pstruct.PSrcPaint.rcTop]
	add	[bx.rcBottom],ax
	add	[bx.rcTop],ax
	cmp	[bx.rcTop],ax
	jae	short InvS30
	mov	[bx.rcTop],ax
InvS30:
	mov	ax,[si.Pstruct.PSrcPaint.rcBottom]
	cmp	[bx.rcBottom],ax
	jbe	short InvS40
	mov	[bx.rcBottom],ax
InvS40:
	mov	ax,[bx.rcBottom]
	cmp	ax,[bx.rcTop]
	jbe	short NoSelSet
DoInvSelDisp:
	push	[si.Pstruct.psHdc]		  ; hSrcDC
	jmp	short DoInvSel

DoInvScreen:
    ;
    ; Invert this rect in the screen DC
    ;
	push	ScreenDC			; hSrcDC

DoInvSel:
	push	ds				; lpRect
	lea	ax,[si.SelStruc.GrabArea.Irect]
	push	ax
	cCall	InvertRect

NoSelP:
	ret

NoSelSet:
	mov	[si.SelStruc.GrabArea.Irect.rcTop],-1	; Flag InvSel2
	ret
InvSel	endp

;**
;
; AdjustSelGrxMax - Adjust Graphics Selection end point for MAX X,Y
;
; INPUT:
;	DX,AX is Y,X of endpoint
;	DS:BX -> Extended Paint structure
; EXIT:
;	DX,AX adjusted
;       Ensures AX <= 640
;               DX <= 400 for modes 4,5,6,D,E
;                  <= 350 for modes F,10
;                  <= 480 for modes 11,12 - VGA/8514 only
;
; USES:
;	DX,AX,FLAGS
;
AdjustSelGrxMax proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	cmp	ax,GrxBitWid640
	jbe	short CheckHeight
	mov	ax,GrxBitWid640
CheckHeight:
IFDEF VGA
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],11H
	je	short Height480
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],12H
	je	short Height480
ENDIF
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],0FH
	je	short Height350
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],10H
	je	short Height350
Height400:
	cmp	dx,GrxBitHeight400
	jbe	short AGM_Done
	mov	dx,GrxBitHeight400
AGM_Done:
        ret

        
Height350:
	cmp	dx,GrxBitHeight350
	jbe	short AGM_Done
	mov	dx,GrxBitHeight350
	jmp	short AGM_Done

IFDEF VGA
Height480:
	cmp	dx,GrxBitHeight480
	jbe	short AGM_Done
	mov	dx,GrxBitHeight480
	jmp	short AGM_Done
ENDIF

AdjustSelGrxMax endp

;**
;
; AdjustSelTextMax - Adjust Text Selection end point for MAX X,Y
;
; INPUT:
;	DS:BX -> Extended paint structure
;	DX,AX is Y,X of endpoint
;	CX is Font width
;	SI is Font height
; EXIT:
;	DX,AX adjusted
;          Set AX = MIN(AX, 40 * FontWid)  for Mode 0,1
;              AX = MIN(AX, 80 * FontWid)  for Mode 2,3
;          Set DX = MIN(DX, Rows * FontHeight)
; USES:
;	DX,AX,CX,FLAGS
;

AdjustSelTextMax proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	dx
	push	ax
	mov	ax,80
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],1	  ; 80 col?
	ja	short DoXB		; Yes
	shr	ax,1			; no, 40 col
DoXB:
	mul	cx			; AX is max width
	mov	dx,ax
	pop	ax
	cmp	ax,dx
	jbe	short OKX
	xchg	ax,dx
OKX:
	mov	cx,ax
	xor	ax,ax
	mov	al,[bx.EPGrabDTA.CntrlSt.VDA_EGA_Rows]
	mul	si			; AX is max height
	pop	dx
	cmp	dx,ax
	jbe	short OKY
	xchg	ax,dx
OKY:
	mov	ax,cx
	ret

AdjustSelTextMax endp

;**
; GetTextWidHgt
;
; ENTRY: DS:BX -> EXTPAINTSTRUC
;
; EXIT: Font width in CX, 
;       Font Height in SI
;
; USES: CX, SI, FLAGS
;
GetTextWidHgt proc near

	mov	cx,[bx.AltFnt1.FontWid] 	; 80 column 25 line
	mov	si,[bx.AltFnt1.FontHgt]
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Rows],25
	jbe	short CheckCols
	mov	cx,[bx.AltFnt3.FontWid] 	; 80 column 43 line
	mov	si,[bx.AltFnt3.FontHgt]
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],1
	ja	short Done
	mov	cx,[bx.AltFnt4.FontWid] 	; 40 column 43 line
	mov	si,[bx.AltFnt4.FontHgt]
	jmp	short Done

CheckCols:
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],1
	ja	short Done
	mov	cx,[bx.AltFnt2.FontWid] 	; 40 column 25 line
	mov	si,[bx.AltFnt2.FontHgt]
Done:
        ret
GetTextWidHgt endp

;**
;
; ScreenAdjust - Adjust end point if appropriate
;
; ENTRY:
;	DX,AX = (Y,X) screen coord of new end point
;	DS:BX -> Extended Paint structure
; EXIT:
;	DX,AX adjusted for screen size maxima
;	      adjusted for character alignment if text mode screen
;	      Adjusted for DWORD alignment if graphics mode screen
; USES:
;	AX,DX,CX,SI,FLAGS
;
; For Text: 
;       Get Font Width and Height
;       /* Round EndPointX to nearest char boundary */
;       If (EndPointX > StartPointX) /* forward sel */
;                EndPointX = ((EndPointX+FontWid-1)/FontWid) * FontWid;
;       else    
;                EndPointX = EndPointX/FontWid;
;       Similarly for EndPointY using Font Height.
;
;       Adjust end point for maxima
;
; Graphics:
;       /* Round EndPointX to Dword boundary */
;       If (EndPointX > StartPointX) /* forward sel */
;                EndPointX = ((EndPointX+32-1)/32) * 32;  Use 64 for mode D,13
;       else    
;                EndPointX = EndPointX/32;    Use 64 for mode D,13
;       /* Round EndPointY to Word boundary */
;          Skip this for modes 10,11,12
;       If (EndPointY > StartPointY) /* downward selection */
;               EndPointY =((EndPointY+1)/2) * 2;
;       else
;               EndPointY = EndPointY/2;
;       Adjust end point for maxima

ScreenAdjust proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],7
	je	short SA_Text
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],4
	jae	short SA_Grfx
    ;
    ; Text, Adjust to char boundaries
    ;
SA_Text:
    ;
    ; get font width, height in CX and SI
    ;
        call    GetTextWidHgt
	cmp	ax,[bx.SelStruc.GrabArea.StartPointX]
	jbe	short RoundDownX
	add	ax,cx
	dec	ax
RoundDownX:
	push	dx
	xor	dx,dx
	div	cx
	mul	cx
	pop	dx
DoY:
	xchg	ax,dx
	cmp	ax,[bx.SelStruc.GrabArea.StartPointY]
	jbe	short RoundDownY
	add	ax,si
	dec	ax
RoundDownY:
	push	dx
	xor	dx,dx
	div	si
	mul	si
	pop	dx
	xchg	ax,dx
	call	AdjustSelTextMax
	ret
    ;
    ; Graphics adjust
    ;
SA_Grfx:
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],0DH
	je	short QuadAlignX
IFDEF VGA
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],13H
	je	short QuadAlignX
ENDIF
	cmp	ax,[bx.SelStruc.GrabArea.StartPointX]
	jbe	short RoundDownGrxX
	add	ax,31
RoundDownGrxX:
	and	ax,1111111111100000B
DoYGrx:
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],10H
	je	short NoGrxYAdjust
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],0FH
	je	short NoGrxYAdjust
IFDEF VGA
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],11H
	je	short NoGrxYAdjust
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],12H
	je	short NoGrxYAdjust
ENDIF
	cmp	dx,[bx.SelStruc.GrabArea.StartPointY]
	jbe	short RoundDownGrxY
	inc	dx
RoundDownGrxY:
	and	dx,1111111111111110B
NoGrxYAdjust:
	call	AdjustSelGrxMax
	ret

;
; MODE D (and mode 13) screens are 320 wide. To get DWORD selection alignment
;   we must align the window points on QWORD boundaries so that when we divide
;   by 2 we are still aligned.
;
QuadAlignX:
	cmp	ax,[bx.SelStruc.GrabArea.StartPointX]
	jbe	short RoundDownGrxXD13
	add	ax,63
RoundDownGrxXD13:
	and	ax,1111111111000000B
	jmp	short DoYGrx

ScreenAdjust endp

;**
;
; CheckCtrlState - Check if the controller state is valid
;
; ENTRY:
;	SS:BP -> Std stack frame
;	DS:SI -> EXTPAINTSTRUC structure
; EXIT:
;	DS:BX -> EXTPAINTSTRUC structure
;	DS:SI -> EXTPAINTSTRUC structure
; USES:
;	ALL but BP,AX,DX
;
CheckCtrlState	proc	near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	mov	bx,si
	bts	[si.EPStatusFlags],fVValidBit	; Valid state(?)
	jc	short CCSR			; Yes, done
    ;
    ; Suck out the current controller state
    ;
        push    eax

	test	GrbFlags,GrbFlgs_DoingGrab
	jz	short NotGrab3
%OUT Does the following make sense?
	test	GrbFlags,GrbFlgs_DoingWindowSelGrab
	jnz	short NotGrab3
	mov	ax,GRB_Get_GrbState
	jmp	short GetGrbCtrl
NotGrab3:
	mov	ax,GRB_Get_State
GetGrbCtrl:
	mov	ebx,[si.ThisVMHand]
;;IFDEF   DEBUG
	mov	cx,(SIZE VDA_EGA_State)
;;ENDIF
	push	ds
	pop	es
	lea	di,[si.EPGrabDTA.CntrlSt]
	movzx	edi,di
        call    [si.GGrbArea.VddApiProcAdr]
IFDEF   DEBUG
        or      cx,cx
        jnz     short CCSContinue1
	mov	bx,si
	mov	esi,codeOffset StateErr
	mov	edx,SHELL_Debug_Out
	call	[bx.ShellCall]
	mov	si,bx
	jmp	short CCSContinue1

StateErr  db	  "Grabber zero return on Get State",0

CCSContinue1:
ENDIF
	mov	bx,si
        pop     eax
CCSR:
	ret

CheckCtrlState	endp

GetFontHeight proc near
	mov	cx,[si.AltFnt1.FontHgt] 	; 80 column 25 line
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Rows],25
	jbe	short GFH_EGA25402
	mov	cx,[si.AltFnt3.FontHgt] 	; 80 column 43 line
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],1
	ja	short GFH1
	mov	cx,[si.AltFnt4.FontHgt] 	; 40 column 43 line
	jmp	short GFH1
GFH_EGA25402:
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],1
	ja	short GFH1
	mov	cx,[si.AltFnt2.FontHgt] 	; 40 column 25 line
GFH1:
	ret
GetFontHeight endp

GetDosCursorSize proc near
	mov	cx,14
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Rows],25
	jbe	SHORT GDCS1
	mov	cx,8
GDCS1:
	ret
GetDosCursorSize endp

;**************************************************************************
; GetCursorHeight: returns cursor height in windowed dos box
; Entry: ax = end scan line of cursor dx = start scan line of cursor
; Exit: ax = cursor height
; Uses: ax,cx,dx
;************************************************************************** 
GetCursorHeight	proc near

	call	GetDosCursorSize
	cmp	ax,cx				; bound ax in cx
	jbe	SHORT CurEndInCell
	mov	ax,cx
CurEndInCell:
	cmp	dx,ax				; bound dx in ax
	jbe	SHORT CurBegInCell0
	mov	dx,ax
CurBeginCell0:
	sub	ax,dx
	inc	ax
    ;
    ; The height now depends on font also...
    ; height = height*fntheight/14
    ;
	call	GetFontHeight			; cx = fontheight
	mul	cx				; ax = height*fntheight
	call	GetDosCursorSize
	div	cx
	shr	cx,1				; for rounding off
	cmp	dx,cx
	jbe	SHORT GotTPHeight
	inc	ax
GotTPHeight:
	ret

GetCursorHeight endp

;**
;
; MakeNewCursor - Create, position, and Display a new cursor
;
; ENTRY:
;	DS:SI -> Extended paint structure
;	DX,AX = (Y,X) screen coord of lower left of cursor
;	      = (-1,-1) if no cursor
; EXIT:
;	Carret created and displayed in window
; USES:
;	ALL
;
MakeNewCursor proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	inc	dx
	jz	COR	; No cursor
	dec	dx
	sub	ax,[si.ColOrg]	; Org onto display
	push	ax		; X for call to SetCaretPos
	sub	dx,[si.RowOrg]	; Org onto display
	push	dx		; Y for call to SetCaretPos
    ;
    ; Create the caret
    ;
	push	[si.WindHand]	; hWnd
	push	0		; hBitmap (flashing block)

	mov	ax,[si.AltFnt1.FontWid] 	; 80 column 25 line
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Rows],25
	jbe	short CheckEGA25401
	mov	ax,[si.AltFnt3.FontWid] 	; 80 column 43 line
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],1
	ja	short GotTWid
	mov	ax,[si.AltFnt4.FontWid] 	; 40 column 43 line
	jmp	short GotTWid

CheckEGA25401:
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],1
	ja	short GotTWid
	mov	ax,[si.AltFnt2.FontWid] 	; 40 column 25 line

GotTWid:
	push	ax		; nWidth
	mov	al,[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode]
	mov	[si.EPGrabDTA.CurCursMode],al
	mov	ax,[si.EPGrabDTA.CntrlSt.VDA_EGA_CurEnd]
	mov	[si.EPGrabDTA.CurCursEnd],ax
	mov	dx,[si.EPGrabDTA.CntrlSt.VDA_EGA_CurBeg]
	mov	[si.EPGrabDTA.CurCursBeg],dx

	call	GetCursorHeight			; get cursor height

	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Rows],25
	jae	short HgtOK
    ;
    ; CONVERT. The EGA character fonts are 14 tall. The EGA High Res
    ;	fonts are 12 high. The conversion factor is 12/14 = 6/7.
    ;	This applies only to modes where def EGA font is used
    ;
	mov	cx,ax
	shl	ax,1		; AX = (AX * 2)
	add	ax,cx		; AX = (AX * 3)
	shl	ax,1		; AX = (AX * 6)
	mov	cx,7
	xor	dx,dx
	div	cx		; AX = (AX * 6)/7
	or	ax,ax
	jnz	short HgtOK
	inc	ax		; Make it at least one
HgtOK:
	push	ax		; nHeight
	cCall	CreateCaret
    ;
    ; Put the caret at its correct position
    ;
	cCall	SetCaretPos
	ret

COR:
	mov	[si.EPGrabDTA.CurCursEnd],ax
	mov	[si.EPGrabDTA.CurCursBeg],ax
	mov	[si.EPGrabDTA.CurCursMode],al
	ret

MakeNewCursor endp


;**
;
; GetVidSel - Get selector to video memory, 
;             For graphics planar modes the offsets for the color planes too
;
; ENTRY:
;	SS:BP -> Std stack frame
;	DS:SI -> EXTPAINTSTRUC structure
; EXIT:
;	Carry Clear
;	    ES:EDI -> start of first video page
;	    If Graphics planar mode(D,E,10,11)
;		  IPlaneOffset  = offset in the Vid Mem for the I plane
;		  RPlaneOffset  = offset in the Vid Mem for the R plane
;		  GPlaneOffset  = offset in the Vid Mem for the G plane
;		  BPlaneOffset  = offset in the Vid Mem for the B plane
;		  
;	    If Text mode(0-4,7) get main mem,
;		  VDA_Mem_Addr_P0 = offset for the Text
;		  VDA_Mem_Addr_Win_State = offset for the WinMemState buffer
;		  
;	Carry Set
;	    ERROR!!! App cant run in a Window
;
;       NOTE: The I,R,G,B planes are not necessarily Planes 3,2,1 and 0.
;             LookUpPalette determines which planes correspond to I,R,G and B
;             planes and sets Palette3,Palette2,Palette1,Palette0 to I,R,G,B
;             Plane numbers respectively. IPlaneOffset is calculated using 
;             Palette3 and so on for the rest of them. This routine should be 
;             called AFTER LookUpPalette.
; USES:
;	EDI, ES, FLAGS
;
GetVidSel proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	esi
	push	ecx
	push	ebx
	push	eax

	lea	di,MemState
	movzx	edi,di
	cmp	VidSel,0
	jnz	MapDone
	mov	ax,[si.RNG1DSSEL]
	mov	VidSel,ax

	push	ss
	pop	es

	push	edx

	test	GrbFlags,GrbFlgs_DoingGrab
	jz	short NotGrab1
	test	GrbFlags,GrbFlgs_DoingWindowSelGrab
	jnz	short NotGrab1
	mov	ax,GRB_Get_GrbMem
	jmp	short GetMemCall
NotGrab1:
	mov	ax,GRB_Get_Mem
GetMemCall:
	mov	ebx,[si.ThisVMHand]
;;IFDEF   DEBUG
        mov     cx, (SIZE VDA_Mem_State)
;;ENDIF
	xor	edx,edx
        call    [si.GGrbArea.VddApiProcAdr]
	and	[si.GGrbArea.GrbStatusFlags],NOT BlinkTurnedOff
	test	dx,01000b
	jnz	SHORT BlinkOn
	or	[si.GGrbArea.GrbStatusFlags],BlinkTurnedOff
BlinkOn:
	pop	edx

IFDEF   DEBUG
        or      cx,cx
        jnz     short GVSContinue1
	push	edx
	push	bx
	push	esi
	mov	bx,si
	mov	esi,codeOffset GMErr
	mov	edx,SHELL_Debug_Out
	call	[bx.ShellCall]
	pop	esi
	pop	bx
	pop	edx
	jmp	short GVSContinue1

GMErr  db      "Grabber zero return on Get Mem",0
GVSContinue1:
ENDIF        
	mov	ecx,ss:[edi.VDA_Mem_DacOff]
	mov	[si.GGrbArea.VDDDacOffset],ecx	; save dac offset.
MapDone:
	xor	ecx,ecx 		; Plane 0 in text mode is text buffer
	GetStartDispAddr eax,edi,ecx,ss
	mov	PgOffst,eax
    ;
    ; Graphics Planar mode, set more variables
    ;
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],0Dh
        jae     short GVS_SetColorPlanes      

GVS_TestPageAlign:
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],7
	je	short GVS_Text
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],4
	jb	short GVS_Text
GVS_TestPageAlignPlanes:
    ;
    ; If not on a 4k boundary, MUST be a Text mode
    ;
	and	ax,0FFFH
	jz	short VarsSet
    ;
    ; Have a graphics mode which doesn't fall on a 4k page boundary ERROR!
    ;
IFDEF DEBUG
	mov	bx,si
	mov	esi,codeOffset AlignErr
	mov	edx,SHELL_Debug_Out
	call	[bx.ShellCall]
	jmp	short GVSContinue3

AlignErr  db	  "Grabber Graphics mode not on 4k boundary",0

GVSContinue3:
	mov	si,bx
ENDIF
	bts	[si.EPStatusFlags],fGrbProbBit ; Tell caller we can't deal with this
	stc				; Flag error
	jmp	short BadMap		; Bomb out

GVS_Text:

VarsSet:
	les	edi,VidAddr
	clc
BadMap:
	pop	eax
	pop	ebx
	pop	ecx
	pop	esi
	ret

GVS_SetColorPlanes:
        push    edi
	call	LookupPalette		; Look up Palette
        pop     edi
	jc	GVSNonStdPgrm		; Yipe!!!!
        
        xor     ecx,ecx
	mov	cl,Palette3           ; Intensity Plane #
	GetStartDispAddr eax,edi,ecx,ss
        mov     IPlaneOffset,eax

	mov	eax,ss:[edi.VDA_Mem_Size_P0][ecx*4]
	sub	eax, 1			; size - 1
	adc	ax, 0			; IF size was 0, force it back to 0
	mov	IPlaneSize,ax

	mov	cl,Palette2           ; Red Plane #
	GetStartDispAddr eax,edi,ecx,ss
        mov     RPlaneOffset,eax
	mov	eax,ss:[edi.VDA_Mem_Size_P0][ecx*4]
	sub	eax, 1			; size - 1
	adc	ax, 0			; IF size was 0, force it back to 0
	mov	RPlaneSize,ax

	mov	cl,Palette1           ; Green Plane #
	GetStartDispAddr eax,edi,ecx,ss
        mov     GPlaneOffset,eax
	mov	eax,ss:[edi.VDA_Mem_Size_P0][ecx*4]
	sub	eax, 1			; size - 1
	adc	ax, 0			; IF size was 0, force it back to 0
	mov	GPlaneSize,ax

	mov	cl,Palette0           ; Blue Plane #
	GetStartDispAddr eax,edi,ecx,ss
        mov     BPlaneOffset,eax
	mov	eax,ss:[edi.VDA_Mem_Size_P0][ecx*4]
	sub	eax, 1			; size - 1
	adc	ax, 0			; IF size was 0, force it back to 0
	mov	BPlaneSize,ax

        mov     eax,PgOffst
	jmp	GVS_TestPageAlignPlanes

GVSNonStdPgrm:
IFDEF	DEBUG
	mov	bx,si
	mov	esi,codeOffset PalErr
	mov	edx,SHELL_Debug_Out
	call	[bx.ShellCall]
	jmp	short GVSContinue4

PalErr	db	"Grabber unrecognized palette program",0

GVSContinue4:
	mov	si,bx
ENDIF
	bts	[si.EPStatusFlags],fGrbProbBit ; Tell caller we can't deal with this
	jmp	GVS_TestPageAlign

        
GetVidSel endp

;
; This table defines the pallete programs we understand and know how to
;	interpret.
;
;   First is an array of pallete settings = Size of the pallete array - 1
;	(pallete 0 is the background which we ignore)
;   Next is one byte of special flags. These flags are ORed into the low byte
;	of GrbFlgs.
;   Next is four bytes. The first byte tells us which plane is BLUE
;			 The second byte tells us which plane is GREEN
;			 The third byte tells us which plane is RED
;			 The fourth byte tells us which plane is INTENSITY
;

StandardPal	Label	word
	; The special "Inverse palette" used by GEM, Ventura publisher
	db	000H,000H,000H,000H,000H,000H,000H,000H,000H,000H,000H,000H,000H,000H,000H
	db	GrbFlgs_GrfxInvPal
	db	0,1,2,3
IFDEF	VGA
	; The special alternate "Inverse palette" used by GEM, Ventura publisher
	db	001H,002H,003H,004H,005H,006H,007H,008H,009H,00AH,00BH,00CH,00DH,00EH,00FH
	db	0		             ;GrbFlgs_GrfxInvPal
	db	0,1,2,3
ENDIF

    ;
    ; NOTE!!!! THIS PALLETE MUST BE LAST!!!!! it is the default pallete that is
    ;	used for apps who's pallete we don't really understand.
    ;
	db	0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH
	db	0
	db	0,1,2,3
StandardPalCnt	equ	($-StandardPal)/((SIZE VDA_EGA_Pal)+5)

IF2
    IF (SIZE VDA_EGA_Pal) NE 16
	%out ****** ERROR !!!!!!! Change in size of EGA Palette array
	Syntax error
    ENDIF
ENDIF

;*****************************************************************************
;
; LookupPalette - See if we recognize the EGA pallete
;
; ENTRY:
;	DS:SI -> EXTPAINTSTRUC structure of paint
;	SS:BP -> Std GRAPHICS stack frame
;
; DESCRIPTION:
;	This grabber treats the planes of the EGA as COLOR planes. This is
;	NOT really correct, but it would be very slow to actually do what
;	the EGA does and treat each pixel 4 bit value as a palette index
;	which determines the color of that pixel. What this routine does
;	is determine which planes correspond to the RED GREEN BLUE and
;	"INTENSITY" COLORS.
;
; EXIT:
;	Carry Set
;	    Palette program is not recognized, application cannot be displayed
;			in a Window
;	Carry Clear
;	    Palette0 on Stack frame set to Plane Number of BLUE plane
;	    Palette1 on Stack frame set to Plane Number of GREEN plane
;	    Palette2 on Stack frame set to Plane Number of RED plane
;	    Palette3 on Stack frame set to Plane Number of INTENSITY plane
;	    Extra GrbFlags set from palette table
; USES:
;	ES,DI,CX,FLAGS
;
; NOTE: We should a PaletteID to the StandardPal entries. Whenever we match 
;       a palette entry in StandardPal,we should set the appropriate PaletteID
;       in some variable. GetWinRGB should use this(instead of the mode) while
;       translating 4 bit color values to Windows RGB value. Everything goes 
;       on as before but when we have an APP using a non-standard palette, 
;       the GetWinRGB routine can use a six bit index into a 64 dword table 
;       which is setup according to say Mode10 DAC. This should provide a 
;       better color matching for APPS that use a non-standard palette 
;       e.g. columns.exe running in Mode 12. This applied to VGA APPS only.
;       8514 always goes through the Palette for the color translation and hence
;       does not encounter this problem.
;
; Additional NOTE:
;	The problem with the above approach is that palette entries need
;	NOT necessarily stand for the color we think they stand for.
;	Instead of depending on the palette, we should depend on the DAC 
;	values it represents to determine the RGB planes.
;*****************************************************************************
LookupPalette proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	si
	cld
	lea	si,[si.EPGrabDTA.CntrlSt.VDA_EGA_Pal.1]
	push	cs
	pop	es
	mov	di,codeOffset StandardPal
	mov	cx,StandardPalCnt
LkLp:
	push	si
	push	cx
	mov	cx,(SIZE VDA_EGA_Pal) - 1
	repe	cmpsb
	je	short FoundPal
	add	di,cx
	add	di,5
	pop	cx
	pop	si
	loop	LkLp
        add     di,(SIZE VDA_EGA_Pal)-1     ; Point to default palette flags
	jmp	short LKUDn1

FoundPal:
	add	sp,4			; Clean stack
LkUDn:
	movzx	cx,byte ptr es:[di]
.erre GrbFlgs_GrfxInvPalBit	   LE	 7

	or	GrbFlags,cx		 ; Set bits from palette lookup
IFDEF   VGA
        pop     si
        push    si
	test	[si.EPGrabDTA.CntrlSt.VDA_EGA_Flags],fVDA_V_InvDAC
        jz      SHORT NotGEM
        or      GrbFlags,GrbFlgs_GrfxInvPal     ;Inverse palette used by GEM Ventura
NotGEM:
ENDIF
LkUDn1:
	mov	cx,word ptr es:[di.1]
	mov	Palette0,cl
	mov	Palette1,ch
	mov	cx,word ptr es:[di.3]
	mov	Palette2,cl
	mov	Palette3,ch
	clc
	pop	si
	ret

LookupPalette endp

;**
;
; ClearVidSel - Release the Vid selector
;
; ENTRY:
;	SS:BP -> Std stack frame
;	DS:SI -> EXTPAINTSTRUC structure
; EXIT:
;	Selector released
;
; NOTE: This routine is a NOP if GrbFlgs_DoingGrab is set
;	and GrbFlgs_DoingWindowSelGrab is clear. We release
;	Grab memory in a different place (GrabComplete)
;
; USES:
;	ALL but DS,SI,DI,BP (C standard)
;
ClearVidSel proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing

	xor	cx,cx
	xchg	cx,VidSel
	jcxz	short CVMR
	test	GrbFlags,GrbFlgs_DoingGrab
	jz	short NotGrab2
	test	GrbFlags,GrbFlgs_DoingWindowSelGrab
	jz	short CVMR
NotGrab2:
	mov	ax,GRB_Free_Mem
	mov	ebx,[si.ThisVMHand]
        call    [si.GGrbArea.VddApiProcAdr]
CVMR:
	ret

ClearVidSel endp

;**
;
; CursorPos - Return position of cursor on display
;
; ENTRY:
;	DS:SI -> EXTPAINTSTRUC structure
; EXIT:
;	DX,AX = (Y,X) screen coord of upper left of cursor
;	      = (-1,-1) if no cursor
; USES:
;	AX,CX,DX,FLAGS
;
CursorPos  proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],7
	je	SHORT CPText
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],4	 
IFDEF VGA
	jae	CPR
ELSE
	jae	SHORT CPR
ENDIF
CPText:
	mov	ax,[si.EPGrabDTA.CntrlSt.VDA_EGA_CurY]
	or	ah,ah
	jnz	CPR			; Cursor is off screen
	cmp	al,[si.EPGrabDTA.CntrlSt.VDA_EGA_Rows]
	jae	short CPR		; Cursor is off screen

	call	GetFontHeight		; cx = fontheight
	mul	cx
	mov	dx,[si.EPGrabDTA.CntrlSt.VDA_EGA_CurBeg]
	cmp	dx,[si.EPGrabDTA.CntrlSt.VDA_EGA_CurEnd] ; height!
	jae	short CPR			; cursor height of < 0
  ;
  ; Now we need to calculate the X coordinate...
  ; X coord = CurBeg*FontHgt/Dos cell height (rounded off)
  ; We don't round it off here. We will round it off for size only.
	push	ax
	mov	ax,dx
	mul	cx
	push	cx
	call	GetDosCursorSize
	div	cx
	push	ax				; save curbeg
	mov	ax,[si.EPGrabDTA.CntrlSt.VDA_EGA_CurEnd]
	mov	dx,[si.EPGrabDTA.CntrlSt.VDA_EGA_CurBeg]
	call	GetCursorHeight			; ax = cursor height
	pop	dx				; get back curbeg
	add	ax,dx				; ax = cursor end + 1
	dec	ax				; ax = cursor end
	pop	cx
	jb	SHORT CurEndInCell1
	dec	cx				; last scan line
	sub	ax,cx				; ax = CurEnd - CharCell
	jbe	SHORT CurEndInCell1		; cursor end inside char cell
	sub	dx,ax
	jae	SHORT CurEndInCell1		; dx >= 0
	xor	dx,dx				; set it to zero
CurEndInCell1:
	mov	ax,dx
	cmp	ax,cx				; ax = beg, cx = font height
	jbe	SHORT CurBegInCell2
	mov	ax,cx
CurBegInCell2:
	pop	dx
	add	ax,dx

	push	ax
	mov	ax,[si.EPGrabDTA.CntrlSt.VDA_EGA_CurX]
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],2
	jb	short col40Cur
col80Cur:
	cmp	ax,79
	ja	short CPRP		; Cursor is off screen
	mov	cx,[si.AltFnt1.FontWid] 	; 80 column 25 line
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Rows],25
	jbe	short CP1
	mov	cx,[si.AltFnt3.FontWid] 	; 80 column 43 line
	jmp	short CP1

col40Cur:
	cmp	ax,39
	ja	short CPRP		; Cursor is off screen
	mov	cx,[si.AltFnt2.FontWid] 	; 40 column 25 line
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Rows],25
	jbe	short CP1
	mov	cx,[si.AltFnt4.FontWid] 	; 40 column 43 line
CP1:
	mul	cx			; AX is X pos of cursor
	pop	dx			; Y pos to dx
	ret

CPRP:
	pop	ax			; Clean stack
CPR:
	mov	dx,-1
	mov	ax,dx
	ret

CursorPos endp

;**
;
; LineBlt - Blit the one line bitmap into the display bitmap
;
; ENTRY:
;	SS:BP -> Graphics paint frame
;	DS:SI -> ExtPaintStruc
;	AX = Line # in display bitmap of line
;	     Blits line at AX and AX.1 except in mode 0FH,10H
;	LineBits contains bits of line
; EXIT:
;	DI advanced by one bit plane
; USES:
;	ALL but DI,SI,BP,DS
;
LineBlt proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing

IFDEF   FASTGRAB
        push    di

        cmp     [fpScanBuf].sel,0
        je      short LBNormal
    ;
    ; When using the page DC, bitmap and ScanBuf, this function
    ; simply advances pScanCur until it reaches pScanMax, at which point
    ; it performs a SetBitmapBits from ScanBuf to the bitmap, resets
    ; pScanCur to pScanMax, and blts the bitmap to the screen.  The screen
    ; blt is done using the code that normally blts from the single-line DC
    ; to the screen;  in this case, we just set LineDC to page DC, because
    ; no real LineDC was ever allocated.  The only other change is setting
    ; the nHeight parameter from DI rather than always 1.
    ;
        mov     di,[nScanLines]         ;
        sub     ax,di                   ; Adjust line #
        btr     GrbFlags,GrbFlgs_FlushLinesBit
        jnc     short LBNoFlush         ;
        or      di,di                   ; If no lines are buffered,
        jz      LBExit                  ; flush is a no-op; just leave
        jmp     short LBSetBits         ; otherwise, set them and display them
LBNoFlush:
        inc     di                      ;
        mov     [nScanLines],di         ;
        mov     dx,[pScanCur]           ; Advance current scan line pointer
        add     dx,(GrxBitWid640*4)/8   ;
        mov     [pScanCur],dx           ;
        cmp     dx,[pScanMax]           ;
        jb      LBExit                  ;
LBSetBits:
        push    ax                      ; Save line #
        push    [si.EPGrabDTA.GrfxhBitmap]  ; hBitmap
	push	0			; dwCount
        push    [pScanMax]              ;
        push    [fpScanBuf].sel         ; lpBits
        push    [fpScanBuf].off         ;
        cCall   SetBitmapBits           ;
        pop     ax                      ; Recover line #

        mov     dx,[fpScanBuf].off      ;
        mov     [pScanCur],dx           ;
        mov     [nScanLines],0          ;
        mov     dx,[si.EPGrabDTA.GrfxhDC]   ; Pretend that our page DC is
        mov     [LineDC],dx             ; a line DC when doing DispLineBlt
        jmp     DispLineBlt             ;
ENDIF  ;FASTGRAB

LBNormal:
	push	ax			; Save line #
	push	LineBitMap		; hBitmap
	mov	ax,DBPWid               ; width in bytes of 1 plane
	shl	ax,2			; * 4 planes
	push	0			; dwCount
	push	ax
	push	ss			; lpBits
	lea	ax,LineBits
	test	ax,0000000000000011B	; Q: LineBits Dword aligned?
	jz	short DW_Aligned	;  Y: 
	inc	ax			;  N: Do it 
	inc	ax
DW_Aligned:
	push	ax
	cCall	SetBitmapBits
        pop     ax                      ; Recover line #
    ;
    ; Blit the line into the screen bitmap
    ;
        mov     di,1                    ; # of lines
	bt	GrbFlags,GrbFlgs_GrfxDispBltBit	; Q: Display or ScreenDC?
	jc	short DispLineBlt	        ;   Y: Display
	push	ScreenDC		; hDestDC
	push	0			; X
	push	ax			; Y
	push	DDRCWid 		; nWidth
	push	1			; nHeight
	push	LineDC			; hSrcDC
	push	0			; XSrc
	push	0			; YSrc
	push	SRCCOPY_H		; dwRop
	push	SRCCOPY_L
	cmp	Gmode,10H
	je	short LB_OnlyOnce
	cmp	Gmode,0FH
	je	short LB_OnlyOnce
IFDEF VGA
	cmp	Gmode,11H
	je	short LB_OnlyOnce
	cmp	Gmode,12H
	je	short LB_OnlyOnce
ENDIF
	push	ScreenDC		; hDestDC
	push	0			; X
	inc	ax
	push	ax			; Y
	push	DDRCWid 		; nWidth
	push	1			; nHeight
	push	LineDC			; hSrcDC
	push	0			; XSrc
	push	0			; YSrc
	push	SRCCOPY_H		; dwRop
	push	SRCCOPY_L
	cCall	BitBlt
LB_OnlyOnce:
	cCall	BitBlt
        jmp     LBExit

;
; Blit directly to display
; AX is line number in ScreenDC
;
DispLineBlt:
	mov	cx,[si.PGVDRect.rcTop]
	sub	cx,DDRCTop		; Rounding error in lines from top
	mov	dx,ax
	cmp	Gmode,10H
	je	short DLB_OnlyOnce
	cmp	Gmode,0FH
	je	short DLB_OnlyOnce
IFDEF VGA
	cmp	Gmode,11H
	je	short DLB_OnlyOnce
	cmp	Gmode,12H
	je	short DLB_OnlyOnce
ENDIF
	inc	dx			; Line number of second line
DLB_OnlyOnce:
	mov	bx,[si.Pstruct.PSrcPaint.rcRight]
	sub	bx,[si.Pstruct.PSrcPaint.rcLeft]  ; Width parameter
	push	dx
	mov	dx,GrxBitWid640
	sub	dx,[si.PGVDRect.rcLeft]
	cmp	bx,dx
	jbe	short WidthOK
	xchg	dx,bx			; Don't overrun bitmap
WidthOK:
	pop	dx
	cmp	dx,cx
        jb      short LBExit
	sub	dx,cx			; Second Line number relative to top paint line
	sub	ax,cx			; First Line number relative to top paint line
	jae	short DLB_00
	mov	ax,dx			; First line is off paint rect
					; second line isn't, change first to
					; second and say no second
DLB_00:
	add	ax,[si.Pstruct.PSrcPaint.rcTop]
	add	dx,[si.Pstruct.PSrcPaint.rcTop]
	cmp	ax,[si.Pstruct.PSrcPaint.rcBottom]
        jae     short LBExit
	push	[si.Pstruct.psHdc]	  ; hDestDC
	push	[si.Pstruct.PSrcPaint.rcLeft] ; X
	push	ax			; Y
	push	bx			; nWidth
        push    di                      ; nHeight
	push	LineDC			; hSrcDC
	mov	cx,[si.PGVDRect.rcLeft]
	sub	cx,DDRCLeft
	push	cx			; XSrc
	push	0			; YSrc
	push	SRCCOPY_H		; dwRop
	push	SRCCOPY_L
	cmp	ax,dx			; Q: Only one line?
	je	short DLB_OnlyOne	;   Y:
	cmp	dx,[si.Pstruct.PSrcPaint.rcBottom] ; Q:2nd line off paint rect?
	jae	short DLB_OnlyOne	           ;  Y: only do one
	push	[si.Pstruct.psHdc]	  ; hDestDC
	push	[si.Pstruct.PSrcPaint.rcLeft] ; X
	push	dx			; Y
	push	bx			; nWidth
        push    di                      ; nHeight
	push	LineDC			; hSrcDC
	push	cx			; XSrc
	push	0			; YSrc
	push	SRCCOPY_H		; dwRop
	push	SRCCOPY_L
	cCall	BitBlt
DLB_OnlyOne:
	cCall	BitBlt

LBExit:
IFDEF   FASTGRAB
        pop     di
ENDIF
	ret

LineBlt endp

ifdef	DBCS
;**
;
; AdjustDBCSBound - Adjust coordinate for DBCS charcter
;
; ENTRY:
;	DS:BX -> Extended paint structure
;	DX,AX = (Y,X) screen coord of upper left
;	DX,CX = (Y,X) screen coord of upper right
; EXIT:
;	DX,AX = (Y,X) Adjusted screen coord of upper left
;	DX,CX = (Y,X) Adjusted screen coord of upper right
; USES:
;	FLAGS	
;
AdjustDBCSBound proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	si
	push	edi
	push	es
	push	bx

	mov	si,bx
	call	GetVidSel

	push	cx
	call	GetTextWidHgt
	call	IsDBCSMiddlePos
	jc	ADB0
	sub	ax,cx			;extend left side
ADB0:
	xchg	sp, bp			; xchg ax, [esp]
	xchg	ax, [bp]
	xchg	sp, bp
	call	IsDBCSMiddlePos
	jc	ADB1
	add	ax,cx			;extend right side
ADB1:
	mov	cx,ax
	pop	ax

	pop	bx
	pusha
	mov	si,bx
	call	ClearVidSel
	popa

	pop	es
	pop	edi
	pop	si
	ret

AdjustDBCSBound	endp

;**
;
; IsDBCSMiddlePos - Test if the coord is middle of DBCS character
;
; ENTRY:
;	DS:BX -> EXTPAINTSTRUCT
;	ES:EDI -> Start of first video page
;	DX,AX = (Y,X) screen coord of upper left
;	SI,CX = (Hight, Width) of character
; EXIT:
;	Carry ON = Not middle of DBCS character
;             OFF =  Middle of DBCS character
; USES:
;	FLAGS	
;
IsDBCSMiddlePos proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	pushad

	push	dx
	xor	dx,dx
	div	cx
	mov	cx,ax
	pop	ax
	xor	dx,dx
	div	si		; CX,AX = (X, Y)
	mov	dx,80*2
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode], 2	;80x25?
	jge	@F				;
	shr	dx, 1				;no, 40x25
@@:
	mul	dx
	movzx	esi,ax		; ES:ESI = Start line pos.
	add	esi,edi
	shl	cx,1
	add	ax,cx
	movzx	eax,ax
	add	edi,eax		; ES:EDI = Check pos.
IDP0:
	cmp	esi,edi
	je	short IDP2
	ja	short IDP3
	mov	ax,es:[esi]
	xor	ah,ah
	cCall	IsDBCSLeadByte,<ax>
	or	ax,ax
	jz	short IDP1
	add	si,2
IDP1:
	add	si,2
	jmp	short IDP0
IDP2:
	stc
	jmp	short IDPX
IDP3:
	clc
IDPX:
	popad
	ret

IsDBCSMiddlePos endp

;**
;
; IsDBCSMiddleText - Test if the character is middle of DBCS char
;
; ENTRY:
;       DS:ESI -> Point to first char of the line
;	EDX    = Offset of the char
; EXIT:
;	Carry ON = Not middle of DBCS character
;             OFF = Middle of DBCS character
; USES:
;	ALL FLAGS
;
IsDBCSMiddleText	proc	near

    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	pushad
IDM0:
	or	dx,dx
	jz	short IDM2
	js	short IDM3
	lods	word ptr ds:[esi]
	xor	ah,ah
	push	dx
	cCall	IsDBCSLeadByte,<ax>
	pop	dx
	or	ax,ax
	jz	short IDM1
	add	esi,2
	sub	dx,2
IDM1:
	sub	dx,2
	jmp	short IDM0
IDM2:
	stc
	jmp	short IDMX
IDM3:
	clc
IDMX:
	popad
	ret

IsDBCSMiddleText	endp

endif	; DBCS

sEnd	code
	end
