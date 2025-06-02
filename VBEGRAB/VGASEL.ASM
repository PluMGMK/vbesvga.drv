;-----------------------------------------------------------------------------
;
;   Screen Grabber for IBM EGA/VGA adaptor
;
;   These routines perform selection functions
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

;-----------------------------------------------------------------------------
;
; External GRABBER Procedures
;
externNP	ScreenAdjust
externNP        GetTextWidHgt
externNP	AdjustSelGrxMax
externNP	AdjustSelTextMax
externNP	CheckCtrlState
ifdef	DBCS
if1
%out DBCS code enabled
endif
externNP	AdjustDBCSBound
endif


;-----------------------------------------------------------------------------

sBegin	code
	assumes cs,code

;*****************************************************************************
;
; BeginSelection - Start up a selection at the indicated point
;
; ENTRY:
;	lpPntStruc Extended paint structure
;	YCoOrd,XCoOrd = (Y,X) screen CoOrd of start point
;		(Here "screen CoOrd" means a window client area position
;		corrected by the scroll bar positions.)
; EXIT:
;	[lpPntStruc.SelStruc.SelctSRect] Display rect in extended paint
;	selection structure set
; USES:
;	C standard
;
;*****************************************************************************
cProc  BeginSelection,<FAR,PUBLIC>

	ParmD	lpPntStruc
	ParmW	YCoOrd
	ParmW	XCoOrd

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
	mov	dx,YCoOrd
	mov	ax,XCoOrd
	mov	[bx.SelStruc.GrabArea.StartPointX],ax
	mov	[bx.SelStruc.GrabArea.StartPointY],dx
	mov	[bx.SelStruc.GrabArea.EndPointX],ax
	mov	[bx.SelStruc.GrabArea.EndPointY],dx
    ;
    ; Adjust for alignment
    ;   Adjust DX, AX for character alignment if text mode
    ;	              for DWORD alignment if graphics mode
    ;	Adjust DX, AX for screen size maxima too
    ;
	call	ScreenAdjust
	mov	[bx.SelStruc.GrabArea.StartPointX],ax
	mov	[bx.SelStruc.GrabArea.StartPointY],dx
	mov	[bx.SelStruc.GrabArea.EndPointX],ax
	mov	[bx.SelStruc.GrabArea.EndPointY],dx
	or	[bx.SelStruc.GrabArea.SelecFlags],SelectOn
	mov	[bx.SelStruc.SelctSRect.rcLeft],ax
	mov	[bx.SelStruc.SelctSRect.rcRight],ax
	mov	[bx.SelStruc.SelctSRect.rcTop],dx
	mov	[bx.SelStruc.SelctSRect.rcBottom],dx

	pop	edi
	pop	esi
cEnd


;*****************************************************************************
;
; EndSelection - Stop selection
;
; ENTRY:
;	lpPntStruc Extended paint structure
; EXIT:
;	Selection stopped
; USES:
;	C standard
;
;*****************************************************************************
cProc  EndSelection,<FAR,PUBLIC>

	ParmD	lpPntStruc

	localV	FrameVars,StdGrbFrameSz
cBegin
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	esi
	push	edi

	InitBasicFrame

	lds	bx,lpPntStruc
	and	[bx.SelStruc.GrabArea.SelecFlags],NOT SelectOn

	pop	edi
	pop	esi
cEnd

;*****************************************************************************
;
; AdjustInitEndPt - Adjust initial selection end point
;
; ENTRY:
;	lpPntStruc Extended paint structure
;	YCoOrd,XCoOrd = (Y,X) point to be adjusted NOTE: NOT IN ANY RELATIVE COORD!!!!
; EXIT:
;	DX,AX = (Y,X) end point adjust down and to right for initial selection
; USES:
;	C Standard
; NOTE:
;	No alignment of this end point can be done as the CoOrd is not in any
;	form that the grabber can understand. Adjustment is purely to "add the
;	right value" to the CoOrd. This is primarily done so the initial move
;	of a keyboard selection endpoint results in a complete character being
;	selected. This routine simply assists in providing visual feedback
;	to the user that he now HAS a selction.
;
;*****************************************************************************
cProc  AdjustInitEndPt,<FAR,PUBLIC>

	ParmD	lpPntStruc
	ParmW	YCoOrd
	ParmW	XCoOrd

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
	mov	ax,XCoOrd
	mov	dx,YCoOrd
	mov	cx,[bx.DefFont.FontWid] ; Assume graphics, will move width of OEM font
	mov	si,[bx.DefFont.FontHgt] ; Assume graphics, will move height of OEM font
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],7
	je	short AIE_Text
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],4
	jae	short GotWidHgt
AIE_Text:
    ;
    ; Text, move by one char or line
    ;
        call    GetTextWidHgt   ; returns font width, height in CX and SI
GotWidHgt:
	add	ax,cx		; Right
	add	dx,si		; Down

	pop	edi
	pop	esi
cEnd

;*****************************************************************************
;
; KeySelection - Keyboard Selection
;
; ENTRY:
;	lpPntStruc Extended paint structure
;	StartType == 0 if SHIFT key UP
;		  != 0 if SHIFT key DOWN
;	MFunc == 0 To right
;	      == 1 To Left
;	      == 2 Down
;	      == 3 Up
; EXIT:
;	DX,AX = (Y,X) screen CoOrd of new selection end point
;		Here "screen CoOrd" means a window client area position
;		corrected by the scroll bar positions. We don't care about
;		the scroll bars here, VMDOSAPP takes care of the correction.
;	NOTE: Selection structure in extended paint structure should not
;		be updated. A call to MakeSelctRect or BeginSelection
;		will follow.
; USES:
;	C standard
;
; Algorithm:
;     If SHIFT key UP(StartType == 0) return new start point;
;        if (LEFT Key)
;                return (X-DELTAx, Y);
;        else if (RIGHT Key)
;                return (X+DELTAx, Y);
;        else if (DOWN Key)
;                return (X, Y+DELTAy);
;        else if (UP Key)
;                return (X, Y-DELTAy);
;
;        where <X,Y> is the current start point
;        DELTAx DELTAy are the font width and height in text mode,
;                      are some appropriate value in graphics mode
;
;    If SHIFT key DOWN(StartType != 0) return new End Point;
;        Similar to above except <X,Y> is current end point.
;
;*****************************************************************************
cProc  KeySelection,<FAR,PUBLIC>

	ParmD	lpPntStruc
	ParmW	StartType
	ParmW	Mfunc

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
    ; Assume SHIFT key UP
    ;
	mov	ax,[bx.SelStruc.GrabArea.StartPointX]
	mov	dx,[bx.SelStruc.GrabArea.StartPointY]
	cmp	StartType,0
	jz	short GotPT		; Assumption correct
    ;
    ; SHIFT key is DOWN, start from previous end point
    ;
	mov	ax,[bx.SelStruc.GrabArea.EndPointX]
	mov	dx,[bx.SelStruc.GrabArea.EndPointY]
    ;
    ; Get Width in CX, Height in SI, depending on the mode
    ;
GotPT:
	mov	cx,64		; Assume graphics mode 0D or 13
				; WARNING!!!! This value is carefully chosen.
				; See proc ScreenAdjust, graphics mode code
	mov	si,[bx.DefFont.FontHgt]  ; Assume graphics, will move height of OEM font
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],0DH
	je	short KS_GotWidHgt
IFDEF VGA
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],13H
	je	short KS_GotWidHgt
ENDIF
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],7
	je	short KS_Text
	mov	cx,32		; Assume other graphics mode
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],4
	jae	short KS_GotWidHgt
KS_Text:
    ;
    ; Text mode, move by one char or line
    ;
        call    GetTextWidHgt   ; returns font width, height in CX and SI
KS_GotWidHgt:
	cmp	Mfunc,0
	jnz	short TLeft
	add	ax,cx		; Right
	jmp	short CheckXY
TLeft:
	dec	Mfunc
	jnz	short TDown
	sub	ax,cx		; Left
	jmp	short CheckXY
TDown:
	dec	Mfunc
	jnz	short IsUp
	add	dx,si		; Down
	jmp	short CheckXY
IsUp:
	sub	dx,si		; Up
CheckXY:
	or	ax,ax
	jns	short KS_xOK    ; AX >= 0?
	xor	ax,ax           ; No, Make AX = 0
KS_xOK:
	or	dx,dx           ; DX >= 0?
	jns	short KS_yOK    ; No, Make DX = 0
	xor	dx,dx
KS_yOK:
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],7
	je	short KSText1
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],4
	jae	short KSGraphics
KSText1:
	call	AdjustSelTextMax        ; Adjust max for AX,DX - Text mode
	jmp	short KSDone
KSGraphics:
	call	AdjustSelGrxMax         ; Adjust max for AX,DX - Graphics mode
KSDone:
	pop	edi
	pop	esi
cEnd

;*****************************************************************************
;
; SetSelRect - Using selection (StartPt,EndPt) set Selection Rect in PAINTSTRUC
;
; ENTRY: DS:BX -> EXTPAINTSTRUC
;        
; EXIT:  DS:[BX.SelStruc.SelctRect set
;
; USES:  AX, CX
;
;*****************************************************************************

SetSelRect proc near

	mov	ax,[bx.SelStruc.GrabArea.EndPointX]
	mov	cx,[bx.SelStruc.GrabArea.StartPointX]
	cmp	cx,ax			; This way?
	jle	short SSR1		; yes
	xchg	ax,cx			; no, other way
SSR1:
	mov	[bx.SelStruc.SelctSRect.rcLeft],cx
	mov	[bx.SelStruc.SelctSRect.rcRight],ax

	mov	ax,[bx.SelStruc.GrabArea.EndPointY]
	mov	cx,[bx.SelStruc.GrabArea.StartPointY]
	cmp	cx,ax			; This way?
	jle	short SSR2		; yes
	xchg	ax,cx			; no, other way
SSR2:
	mov	[bx.SelStruc.SelctSRect.rcTop],cx
	mov	[bx.SelStruc.SelctSRect.rcBottom],ax

        ret
SetSelRect endp

;*****************************************************************************
;
; MakeSelctRect - Set a new selection
;
; ENTRY:
;	lpPntStruc Extended paint structure
;	YCoOrd,XCoOrd = (Y,X) screen CoOrd of new end point
;		(Here "screen CoOrd" means a window client area position
;		corrected by the scroll bar positions)
; EXIT:
;	[lpPntStruc.SelStruc.SelctSRect] Display rect in extended paint
;		selection structure set
;	AX == 0
;	    if no change was made to selection parameters
;		NOTE: [lpPntStruc.SelStruc.SelctSRect] MUST STILL BE SET in
;		this case!!!!
; USES:
;	C Standard
;
;*****************************************************************************
cProc  MakeSelctRect,<FAR,PUBLIC>

	ParmD	lpPntStruc
	ParmW	YCoOrd
	ParmW	XCoOrd

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
	mov	dx,YCoOrd
	mov	ax,XCoOrd
	call	ScreenAdjust
	cmp	ax,[bx.SelStruc.GrabArea.EndPointX]
	jnz	short SaveFlags
	cmp	dx,[bx.SelStruc.GrabArea.EndPointY]
SaveFlags:
	pushf				; Save whether end point is different
	mov	[bx.SelStruc.GrabArea.EndPointX],ax
	mov	[bx.SelStruc.GrabArea.EndPointY],dx

        call    SetSelRect

	popf				; recover end point compare
	mov	ax,0			; DO NOT XOR!!!!!!
	jz	short MSRDone
	inc	ax
MSRDone:
	pop	edi
	pop	esi
cEnd

;*****************************************************************************
;
; ConsSelecRec - Make display rectangle consistent with selection
;
; ENTRY:
;	lpPntStruc Extended paint structure
; EXIT:
;	[lpPntStruc.SelStruc.SelctSRect] Display rect in extended paint
;	    selection structure set
;
;	What we are doing here is simply making sure that SelctSRect is
;	a TRUE correct representation of the selection. Basically this
;	is where any of the selection alignment additions or subtractions
;	to the rectangle CoOrds get resolved.
;
; USES:
;	C standard
;
;*****************************************************************************
cProc  ConsSelecRec,<FAR,PUBLIC>

	ParmD	lpPntStruc

	localV	FrameVars,StdGrbFrameSz
cBegin
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	esi
	push	edi

	InitBasicFrame
	lds	bx,lpPntStruc
        call    SetSelRect

	pop	edi
	pop	esi
cEnd

;*****************************************************************************
;
; InvertSelection - Invert selection so that all paints will paint selection
;                   inverted from its current state.
;
;  Note this may mostly be a NOP. In which case the only important thing 
;  is to set the return value
;
; ENTRY:
;	lpPntStruc Extended paint structure
; EXIT:
;	DX,AX = (Y,X) screen CoOrd of "active" selection endpoint
; USES:
;	ALL
;
;*****************************************************************************
cProc  InvertSelection,<FAR,PUBLIC>

	ParmD	lpPntStruc

	localV	FrameVars,StdGrbFrameSz
cBegin
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	esi
	push	edi

	InitBasicFrame

	lds	bx,lpPntStruc
	mov	ax,[bx.SelStruc.GrabArea.EndPointX]
	mov	dx,[bx.SelStruc.GrabArea.EndPointY]

	pop	edi
	pop	esi
cEnd

ifdef	DBCS
;*****************************************************************************
;
; AdjustDBCSRect - Adjust rectangle for DBCS text. 
;
; ENTRY:
;	lpSlctRect - Points to a RECT data that specifies selected region.
;	lpDBCSRect - Points to a RECT data that returns adjusted region.
;		     
; EXIT:
;	AX = TRUE Continue
;	   = FALSE End, no more text need to invert
; USES:
;	C standard
;
;*****************************************************************************
cProc  AdjustDBCSRect,<FAR,PUBLIC>

	ParmD	lpPntStruc
	ParmD	lpSlctRect
	ParmD	lpDBCSRect

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
    ; Now ds:bx,ds:si -> EXTPAINTSTRUCT structure
    ;
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],03h	
	jle	short ADR0	; if (Mode == 3) {
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode], 7
	je	short ADR0
	lds	si,lpSlctRect	;    lpDBCSRect = lpSlctRect;
ADR3:
	les	di,lpDBCSRect	;    return (0);
	mov	cx,4		; }
	rep	movsw
	xor	ax,ax
	jmp	short ADRX
ADR0:
	lds	si,lpSlctRect
	mov	ax,[si.rcBottom]
	cmp	ax,[si.rcTop]
	jz	short ADR3
	mov	ax,[si.rcRight]
	cmp	ax,[si.rcLeft]
	jz	short ADR3

	call	GetTextWidHgt	; GetTextWidHgt();
	mov	dx,si		; if (lpDBCSRect.rcBottom == 0)
	lds	si,lpSlctRect	;    lpDBCSRect.rcTop = lpSlctRect.rcTop;
	lds	di,lpDBCSRect	; else
	cmp	[di.rcBottom],0	;    lpDBCSRect.rcTop += Hgt;
	jnz	short ADR1
	mov	ax,[si.rcTop]
	mov	[di.rcTop],ax
	jmp	short ADR2
ADR1:
	add	[di.rcTop],dx
ADR2:
	mov	ax,[di.rcTop]	; lpDBCSRect.rcBottom = lpDBCSRect.rcTop+Hgt;
	add	ax,dx
	mov	[di.rcBottom],ax
	mov	ax,[si.rcLeft]	; lpDBCSRect.rcLeft = lpSlctRect.rcLeft;
	mov	[di.rcLeft],ax	
	mov	cx,[si.rcRight]	; lpDBCSRect.rcRight = lpSlctRect.rcRight;
	mov	[di.rcRight],cx	; AdjustDBCSBound();
	mov	dx,[di.rcTop]
	call	AdjustDBCSBound ;He will adjust left and right side for the row
	mov	[di.rcLeft],ax
	mov	[di.rcRight],cx
	mov	ax,[si.rcBottom] ; if (lpDBCSRect.rcBottom >=
	cmp	[di.rcBottom],ax ;		lpSlctRect.rcBottom)
	mov	ax,0		 ;    return(0);
	jge	ADRX		 ; else
	not	ax		 ;    return(-1);
ADRX:
	pop	edi
	pop	esi
cEnd

endif	; DBCS

sEnd	code
        end



