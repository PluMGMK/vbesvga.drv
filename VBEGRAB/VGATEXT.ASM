;--------------------------------------------------------------------
;
;   Screen Grabber for IBM EGA/VGA adaptor
;
;   Text mode painting routines.
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

;-----------------------------------------------
;
; External Windows Procedures
;
externFP	SelectObject
externFP	GetNearestColor
externFP	CreateSolidBrush
externFP	DeleteObject
externFP	PatBlt
externFP	SetBkColor
externFP	TextOut
externFP	SetTextColor
externFP	ScrollWindowEx
ifdef	DBCS
if1
%out DBCS code enabled
endif
externFP	IsDBCSLeadByte
endif	; DBCS

;-----------------------------------------------
;
; External GRABBER Procedures
;
IFDEF   FASTGRAB
externNP        DeAllocGrfxRes
ENDIF
externNP	ComputeSelTextrect
externNP	GetWinRGB
ifdef	DBCS
externNP	IsDBCSMiddleText
endif	; DBCS

sBegin	code
	assumes cs,code

	public	ModeText
	public	BuildTextRects
	public	AdjustSelText
	public	Outline
	public	CreateOverScanBrTxt
        public  SetParamsText
        public  SelectTextFont
        public  PaintExtraAreaText
        public  SetNewBkFg
        public  DeAllocResText
	public	ClearWinMemState


	extrn	RGBTable:word

;****************************************************************************
;
; ModeText - Paint a text mode display
;
;    This routine Paints the old app text screen into a window
;
;    Our strategy is:
;	PatBlt the background color of the last char on the top line
;	    of the paint rectangle into the paint rectangle in the display DC.
;	For each text line in the paint rectangle build a text line
;	    from the display memory and use TextOut to output it into
;	    the paint rectangle
;	    Pieces of lines that are spaces in the background color PatBlted
;		above may be skipped over if they are long enough
;
; ENTRY:
;	SS:BP -> Std stack frame
;	DS:SI -> EXTPAINTSTRUC structure of paint
;
; EXIT:
;	Carry Clear
;	    Screen Painted
;	Carry Set
;	    Screen not painted, probably low Windows memory problem
; USES:
;	ALL but DS,SI,BP
;
;****************************************************************************
ModeText proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing

    ;
    ; Initialize text frame vars
    ;
	xor	ax,ax
	mov	BkTxtBrsh,ax
	mov	WidRgt,ax
	mov	HigBot,ax
	mov	OldBrshHand,ax
	mov	OldFontHand,ax
	mov	ax,80
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],1
	jbe	SHORT MT_GotColumns
	mov	ax,160
MT_GotColumns:
	mov	BytesPerLine,ax

IFNDEF GENGRAB
    ;
    ; Make sure we deallocate any residual graphics info
    ;
        call    DeAllocGrfxRes
ENDIF
    ;
    ; If there is a selection, compute selection rectangle
    ;
	lea	bx,[si.PTVDRect]
	test	[si.SelStruc.GrabArea.SelecFlags],SelectOn
	jz	short NoSel
	call	ComputeSelTextRect
NoSel:
    ;
    ; Compute various parameters of the paint and See if the paint rect is
    ;	"on screen"
    ;
        call    SetParamsText
	jc	MTDone			; Rect is Off screen or invalid rect

    ;
    ; BytesPerLine,BytesToRight set 
    ; ES:EDI -> first line of paint rect
    ; ES:EDX -> corresponding first line of WinMemState (or 0 if no WinMemState)
    ;
	push	edi
	push	edx
        call    SelectTextFont          ; based on mode
	jc	MTError

        call    PaintExtraAreaText

	pop	edx
	pop	edi
	push	edi
	push	edx
	movzx	eax,BytesToRight
	add	edi,eax
	or	edx,edx 		; Q: WinMemState exist?
	jz	SHORT NoWinMem00	;   N: leave EDX zero
	add	edx,eax
NoWinMem00:
	mov	es,VidSel
	mov	ax,word ptr es:[edi]	; Get attribute of first char in AH
	call	AdjustSelText		; Do adjustment if needed
	mov	word ptr Currcols,ax	;  initial set
	not	BYTE PTR CurrCols.1
	call	SetBkFgIfZero
	jmp	SHORT FirstLineText

    ;
    ; Set up for next line
    ;
NextLineText:
	push	edi
	push	edx
	movzx	eax,BytesToRight
	add	edi,eax
	or	edx,edx 		; Q: WinMemState exist?
	jz	SHORT NoWinMem01	;   N: leave EDX zero
	add	edx,eax
NoWinMem01:

FirstLineText:
	lea	ax,ToutBuf
	mov	pToutBuf,ax		; Buffer ptr -> start of buffer
ifdef	DBCS
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],3
	jle	@F
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode], 7
	jne	NoMode30
@@:
	push	esi
	push	edx
	mov	esi,edi
	movzx	edx,BytesToRight
	sub	esi,edx
	push	ds
	push	es
	pop	ds
	call	IsDBCSMiddleText	;the left side is 2nd byte of a DBCS?
	pop	ds
	pop	edx
	pop	esi
	mov	cx,WidPaint
	mov	ax,[bx.TPXpos]		    ; X
	jc	short @F
	dec	edi			;left side is DBCS 2nd byte
	dec	edi			;extend the left side to DBCS 1st byte
	inc	cx			;so is the line width
	sub	ax,[bx.TPFntWid]	;and x starting position
@@:
	mov	TLineXPos,ax
	jmp	short NextChar
NoMode30:
endif	; DBCS

	mov	ax,[bx.TPXpos]
	mov	TLineXPos,ax		; Set graphical X position
	mov	cx,WidPaint
NextChar:
    ;
    ; Get the next char and adjust it if it's in the selection rectangle
    ;
	mov	ax,word ptr es:[edi]
	call	AdjustSelText		; adjust char for selection...
	inc	edi
	inc	edi
	or	edx,edx 		; Q: WinMemState exist?
	jz	SHORT DoChar		;   N: Output all characters
	cmp	word ptr es:[edx],ax
	pushfd
	mov	word ptr es:[edx],ax	; Update WinMemState
	inc	edx
	inc	edx
	popfd				; Q: Screen change this char?
	jnz	SHORT DoChar		; Y: Keep on storing.
	or	ax,ax			; zeros ?
	jz	SHORT DoChar		; maybe due to paint
	call	LookPastSomeMore	; N. Q: Should we add same chars?
	jnz	SHORT DoCharincCx	;    Y: keep on storing
	or	cx,cx
ifdef	DBCS
	jz	LineDoneText
else
	jz	SHORT LineDoneText		; get out if line done
endif
    ; ax = size ofcommon area
	inc	ax			; for the char which was already done
	push	ax
	mov	ax,es:[edi]		; this is new bk,fg...
	call	SetNewBkFg		; Flush and set new bk,fg if necessary
	pop	ax
	push	cx
	mov	cx,[bx.TPFntWid]
	mul	cl			; AX has result
	add	TLineXPos,ax		; Set new X coord
	pop	cx
	jmp	NextChar

DoCharincCx:
	inc	cx
    ;
    ; Set new colors if needed
    ;
DoChar:
;;	call	AdjustSelText		; now, done before
	cmp	ah,byte ptr Currcols.1	; Q:Colors changed?
	jz	short StoreChar 	;  No
	call	SetNewBkFg		;  Yes, flush ToutBuf and change attr
StoreChar:
	push	di
	mov	di,pToutBuf		; Char goes here
	mov	byte ptr [di],al
	inc	pToutBuf		; Next char
	pop	di
ifdef	DBCS
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode], 3
	jle	short MT_DBCSText
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],7
	jne	short @F
MT_DBCSText:
	xor	ah,ah
	push	bx
	push	cx
	cCall	IsDBCSLeadByte,<ax>
	pop	cx
	pop	bx
	or	ax,ax
	jz	short @F
	mov	ax,word ptr es:[edi]

	call	AdjustSelText
	cmp	ah,byte ptr Currcols.1
	jz	short NoColChg

	push	dx
	push	cx
	push	ax
	mov	eax,edi
	sub	eax,PgOffst
	xor	dx,dx
	mov	cx,BytesPerLine
	div	cx			; AX is row, DX is col*2
	shr	dx,1			; DX is col
	cmp	dl,byte ptr [si.SelStruc.GrabArea.Irect.rcLeft]
	jne	short NoSelLft
	cmp	al,byte ptr [si.SelStruc.GrabArea.Irect.rcLeft.1]
	jb	short NoSelLft
	cmp	al,byte ptr [si.SelStruc.GrabArea.Irect.rcTop.1]
	jae	short NoSelLft

	pop	ax
	push	ax
	dec	pToutBuf
	call	SetNewBkFg
	push	ax
	mov	ax,word ptr es:[edi-2]
	push	edi
	mov	di,pToutBuf
	mov	byte ptr [di],al
	inc	pToutBuf
	pop	edi
	pop	ax
NoSelLft:
	pop	ax
	pop	cx
	pop	dx
NoColChg:
	inc	edi
	inc	edi
	push	edi
	mov	di,pToutBuf
	mov	byte ptr [di],al
	inc	pToutBuf
	pop	edi
	dec	cx
@@:
endif	; DBCS
	dec	cx			; Faster than loop to label which is too far
ifdef	DBCS
;cx might be negative if we have DBCS on the right side.
	jg	NextChar
else	; DBCS
	jnz	NextChar
endif
LineDoneText:
	call	OutLine 		; Flush
    ;
    ; Next line
    ;
	pop	edx
	pop	edi
	movzx	eax,BytesPerLine
	add	edi,eax 		; Next line in vid buff
	or	edx,edx 		; Q: WinMemState exist?
	jz	SHORT NoWinMem02	;   N: leave EDX zero
	add	edx,eax
NoWinMem02:
	mov	ax,[bx.TPFntHgt]
	add	[bx.TPYpos],ax		; Next line on display
	dec	HigPaint		; One line done
	jnz	NextLineText		; More lines
        
MTDone:

IFDEF	testing				; checks if mem rendered correctly
 
	push	esi
	push	bx
	lea	bx,[si.PTVDRect]
	call	SetParamsText
	mov	esi,edx
	mov	ax,HigPaint
	movzx	ebx,BytesPerLine
	movzx	ecx,WidPaint
@@:
	push	ecx
	push	esi
	push	edi
	rep cmps WORD PTR ES:[EDI],WORD PTR ES:[ESI]
	pop	edi
	pop	esi
	pop	ecx
	jnz	SHORT @F
	add	esi,ebx
	add	edi,ebx
	dec	ax
	jnz	SHORT @B
	jmp	SHORT NoErr
@@:
	int	3
NoErr:
	pop	bx
	pop	esi
ENDIF
        call    DeAllocResText
        clc
	ret

MTError:
	pop	edx
	pop	edi
        call    DeAllocResText
        stc
        ret

ModeText endp

Min_Equal_Count	equ	10

;*****************************************************************************
;
; LookPastSomeMore
;  we try to check if next Min_Equal_Count / remaining chars on the line
;  are same. We must do better during flush time.
; Entry:
;	ES:EDX => copy mem, ES:EDI => main mem
; 
;*****************************************************************************
LookPastSomeMore proc near

	dec	cx
	jz	SHORT LPSM_fover
	push	esi
	push	ecx

	movzx	ecx,cx			; zero out higher word of ecx

	mov	esi,edx
	cld
	rep cmps WORD PTR ES:[EDI],WORD PTR ES:[ESI]
	jnz	SHORT LPSM_over		; difference found
LPSM_First:
	pop	ecx			; get old count
	sub	esi,edx			; size of compare
	mov	ax,si			; size of compare
	shr	ax,1			; convert to char (words)
	sub	cx,ax			; new count is set
	add	edx,esi			; edx is set too, edi already correct
	xor	si,si			; set flag
	pop	esi
	ret
LPSM_over:
	; if ((pToutBuf == offset ToutBuf) && (equal > min_equal_count)) then 
	;  update ecx,edx,ecx,TlinexPos go back
	; else get out with NZ flag
	sub	esi,2
	sub	edi,2			; they were different
	push	si
	lea	si,ToutBuf
	cmp	si,pToutBuf
	pop	si
	jz	SHORT LPSM_First		; still in searching phase
	mov	ecx,esi			; storing phase!!!
	sub	ecx,edx			; ecx-2 words are same from edx
	shr	cx,1			; to words(chars)
	cmp	cx,min_equal_count
	jae	SHORT LPSM_First		; yes, flush it

	sub	esi,edx			; count of compare
	sub	edi,esi			; edi shifted back
	xor	cx,cx			; set zero flag
	inc	cx			; make it non zero
	pop	ecx
	pop	esi
LPSM_fover:
	ret

LookPastSomeMore endp

;*****************************************************************************
;
; SetParamsText - 
;
; ENTRY: BX = SI.PTVDRect
;
; EXIT: 
;       If Carry Set 
;           Rect is Off Screen or invalid rect
;		or VM's memory not allocated
;       else
;           Set
;               - BytesToRight
;               - ES:EDI -> first line of paint rect
;		- ES:EDX -> corresponding first line of WinMemState
;			 (or 0 if no WinMemState)
;*****************************************************************************

SetParamsText proc near
    ;
    ; Compute various parameters of the paint and See if the paint rect is
    ;	"on screen"
    ;
	mov	dx,BytesPerLine 	; DX = screen width
	shr	dx,1			; Two bytes per char in vid buff

	cmp	dx,[bx.TPRect.rcLeft]	; Paint rect "on screen"?
	jbe	NulPntTxt		; No

	mov	cx,[bx.TPRect.rcRight]
	cmp	cx,dx			; Q: Part of paint rect "off screen"?
	jbe	short WidOkTx		;  N:
	xchg	cx,dx			;  Y: Limit to screen
WidOkTx:
	sub	cx,[bx.TPRect.rcLeft]
	mov	WidPaint,cx
	jbe	InvalidRectText 	; Invalid Rect
	mov	ax,cx
	mul	[bx.TPFntWid]		; AX is width of paint text in pixels
	add	ax,[bx.TPXpos]
	cmp	ax,[si.Pstruct.PSrcPaint.rcRight]
	jb	ExtrR
NoExtrR:
	movzx	cx,[si.EPGrabDTA.CntrlSt.VDA_EGA_Rows]
	mov	dx,cx			; DX = Rows on screen
	cmp	cx,[bx.TPRect.rcTop]	; Paint rect "on screen"?
	jbe	short NulPntTxt		; NO

	mov	cx,[bx.TPRect.rcBottom]
	cmp	cx,dx			; Q: Part of paint rect "off screen"?
	jbe	short HigOkTx		;   N:
	mov	cx,dx			;   Y: Limit to screen
HigOkTx:

; Limit rows to paint by amount of memory actually allocated to VM
	movzx	eax,cx
	mul	BytesPerLineByte	; AX = len from top of screen to rcBot
        add     eax,[MemState].VDA_Mem_DPagOff  ; EAX = offset in disp mem
        cmp     eax,[MemState].VDA_Mem_Size_P0  ; Q: memory allocated?
        jbe     SHORT HaveMem                   ;   Y: continue
        mov     eax,[MemState].VDA_Mem_Size_P0  ;   N: Truncate at end
        sub     eax,[MemState].VDA_Mem_DPagOff
	jae	SHORT PagOffGtSize		; jif savemem OK.
   ;
   ; Not enough save memory has been allocated. The offset of start
   ; of mem is BEYOND the extent of the allocated memory.
   ; This change will show garbage in the window but should avoid
   ; a page fault.
   ;
ifdef	debug
	int	3
endif
	mov	eax,[MemState].VDA_Mem_Size_P0
	mov	DWORD PTR [MemState.VDA_Mem_Addr_Win_State],0
PagOffGtSize:
	xor	dx,dx
	div	BytesPerLine		; AX = rows from top of screen to bottom
	mov	cx,ax			; CX = new TPRect.rcBottom
HaveMem:
	sub	cx,[bx.TPRect.rcTop]
	mov	HigPaint,cx		; Set rows to paint
	jbe	short InvalidRectText
	mov	ax,cx
	mul	[bx.TPFntHgt]		; AX is height of text
	add	ax,[bx.TPYpos]
	cmp	ax,[si.Pstruct.PSrcPaint.rcBottom]
	jb	short ExtrB
NoExtrB:
	mov	ax,[bx.TPRect.rcLeft]
	shl	ax,1			; Two bytes per char in vid buff
	mov	BytesToRight,ax
    ;
    ; Index into vid buffer to first char of top line of paint
    ;
	les	edi,VidAddr		; EDI->start of displayed VM video mem
	movzx	eax,[bx.TPRect.rcTop]
	mul	BytesPerLine		; EAX=offset of first byte of first line
	mov	edx,DWORD PTR [MemState.VDA_Mem_Addr_Win_State]
	or	edx,edx 		; Q: WinMemState exist?
	jz	SHORT SPT_Exit		;   N: leave EDX zero
	add	edx,eax 		; EDX -> WinMemState start to paint
SPT_Exit:

	add	edi,eax 		; EDI -> VM mem start to paint
        clc
        ret

NulPntTxt:
	call	CreateOverScanBrTxt
	lea	di,[si.Pstruct.PSrcPaint]
	mov	ax,[di.rcRight]
	sub	ax,[di.rcLeft]
	mov	dx,[di.rcBottom]
	sub	dx,[di.rcTop]
	cCall	PatBlt,<[si.Pstruct.psHdc],[di.rcLeft],[di.rcTop],ax,dx,PATCOPY_H,PATCOPY_L>
InvalidRectText:
        stc
        ret

ExtrR:
	mov	XRgt,ax
	sub	ax,[si.Pstruct.PSrcPaint.rcRight]
	neg	ax
	mov	WidRgt,ax
	jmp	NoExtrR

ExtrB:
	mov	YBot,ax
	sub	ax,[si.Pstruct.PSrcPaint.rcBottom]
	neg	ax
	mov	HigBot,ax
	jmp	NoExtrB

SetParamsText endp


;****************************************************************************
;
; SelectTextFont - Select the appropriate text font into hDC
;                  Returns Font handle in AX
;
; EXIT: Carry set if error
;
;****************************************************************************
SelectTextFont proc near

	cmp	BytesPerLine,40*2
	jz	short Font40
Font80:
	mov	ax,[si.AltFnt1.FontHand]	; Assume 25 line
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Rows],25
	jbe	short SelFont
	mov	ax,[si.AltFnt3.FontHand]	; > 25 line

SelFont:
	or	ax,ax
	jnz	short OkFnt
	mov	ax,[si.DefFont.FontHand]    ; AIGGGGHHHHH!!!! use def font
OKFnt:
	push	bx
	cCall	SelectObject,<[si.Pstruct.psHdc],ax>
	pop	bx
	or	ax,ax
	jz	short STFError        ; Low memory most likely

	mov	OldFontHand,ax
        clc
        ret
Font40:
	mov	ax,[si.AltFnt2.FontHand]	; Assume 25 line
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Rows],25
	jbe	short SelFont
	mov	ax,[si.AltFnt4.FontHand]	; > 25 line
	jmp	short SelFont

STFError:
        stc
        ret

SelectTextFont endp

;****************************************************************************
;
; PaintExtraAreaText - Paint the Extra areas with Over scan brush
;
;****************************************************************************
PaintExtraAreaText proc near

        push    bx
	push	dx
	call	CreateOverScanBrTxt
    ;
    ; PatBlt the black brush into "extra areas" (if any)
    ;
	cmp	WidRgt,0
	jz	short CheckHig
	mov	ax,[si.Pstruct.PSrcPaint.rcTop]
	mov	cx,[si.Pstruct.PSrcPaint.rcBottom]
	sub	cx,ax
	cCall	PatBlt,<[si.Pstruct.psHdc],XRgt,ax,WidRgt,cx,PATCOPY_H,PATCOPY_L>
CheckHig:
	cmp	HigBot,0
	jz	short PEADone
	mov	ax,[si.Pstruct.PSrcPaint.rcLeft]
	mov	cx,[si.Pstruct.PSrcPaint.rcRight]
	sub	cx,ax
	cCall	PatBlt,<[si.Pstruct.psHdc],ax,YBot,cx,HigBot,PATCOPY_H,PATCOPY_L>
PEADone:        
	pop    dx
        pop    bx
        ret

PaintExtraAreaText endp

;****************************************************************************
;
; SetNewBkFg - Set New Bk and Fg colors if necessary
;
; EXIT: CurrCols updated
;
; Algorithm:
;     Flush chars in the buffer in prev colors
;     Turn Off Blink bit in CurrCols and given attribute
;     if (Bk Color has changed)  {  /* AH.Bk != CurrCols.Bk) */
;         if (char in Sel) /* Indicated Color != True Color */
;             Get Win RGB for Indicatedcolor.Bk
;         else
;             Get Win RGB for TrueColor.Bk
;         SetBkColor
;     }
;     if (Fg Color has changed)  {  /* AH.Fg != CurrCols.Fg) */
;         if (char in Sel) /* Indicated Color != True Color */
;             Get Win RGB for Indicatedcolor.Fg
;         else
;             Get Win RGB for TrueColor.Fg
;         SetTextColor
;     }
;
;****************************************************************************
SetNewBkFg proc near

	call	OutLine 		; Flush chars in prev colors

SetNewBkFgWoLine:

	push	es
	push	dx
	push	bx
	push	cx
	push	ax

    ;
    ; Set new background color
    ;

	mov	bx,word ptr Currcols
	mov	bl,ah			; BH is old bk, BL is new bk
	and	bx,01111000011110000B	; Mask to bits of interest
	cmp	bh,bl			; Changed?
	jz	short SameBk		; No
SetBk:
	mov	cl,ah			; CL is indicated color
	mov	al,TrueColor		; AL is TRUE color
	mov	ch,al			; CH is TRUE color
	cmp	cl,ch			; Color effected by selection?
	jz	short GetBk		; No - pick true color for Bk
        mov     al,cl                   ; Yes - pick indicated color for Bk
GetBk:
	shr	al,4			; Background to low 4 bits
	call	GetWinRGB
	cCall	SetBkColor,<[si.Pstruct.psHdc],dx,ax>
SameBk:
    ;
    ; Set new foreground color
    ;
	pop	ax
	push	ax
	mov	bx,word ptr Currcols
	mov	bl,ah			; BH is old foreground, BL new
	and	bx,0000111100001111B	; Mask to bits of interest
	cmp	bh,bl			; Changed?
	jz	short SameFg		; no
SetFg:
	mov	cl,ah			; CL is indicated color
	mov	al,TrueColor		; AL is TRUE color
	mov	ch,al			; CH is TRUE color
	cmp	cl,ch			; Color effected by selection?
	jz	short GetFg		; No - pick true color for Fg
        mov     al,cl                   ; Yes - pick indicated color for Fg
GetFg:
	call	GetWinRGB
	cCall	SetTextColor,<[si.Pstruct.psHdc],dx,ax>
SameFg:
	pop	ax
	pop	cx
	pop	bx
	pop	dx
	pop	es
	mov	word ptr Currcols,ax	; Set current colors

        ret

SetNewBkFg endp

public	SetBkFgIfZero

;*****************************************************************************
; SetBkFgIfZero:
; The problem: Initially, CurrCols.1 = not(attr). What happens if attr is
; FF, then CurrCols.1=00. Later in setnew bkfg, 0 will not be set if some
; changes occur.
; Solution: if fg/bg is zero, then we explicitly set it.
; Entry: ah= attr  CurrCols = not attr
;*****************************************************************************
SetBkFgIfZero proc near
	push	ax
	mov	ah,BYTE PTR CurrCols.1	; is bg zero?
	mov	al,ah			; save
	and	ah,00Fh			; adjust bg
	jnz	SHORT CheckCCFg		; Bg OK
	inc	al			; adjust bg
	inc	BYTE PTR CurrCols.1	; Bg adjusted
CheckCCFg:
	mov	ah,al			; get back
	and	ah,0F0h			; adjust fg
	jnz	SHORT SavedCurrCols
	rol	ah,4
	inc	ah
	rol	ah,4			; different currcols...
	mov	BYTE PTR CurrCols.1,ah
SavedCurrCols:
	pop	ax
	cmp	ah,BYTE PTR CurrCols.1	; did we change?
	jz	SHORT CurrColsOK
	call	SetNewBkFgWoLine
CurrColsOK:
	ret
SetBkFgIfZero endp

;****************************************************************************
;
; DeAllocResText - DeAlloc allocated resources
;
;****************************************************************************

DeAllocResText proc near

	mov	cx,OldBrshHand
	jcxz	BkTextBr
	cCall	SelectObject,<[si.Pstruct.psHdc],cx>
BkTextBr:
	mov	cx,BkTxtBrsh
	jcxz	RestoreFont
	cCall	DeleteObject,<cx>
RestoreFont:
	mov	cx,OldFontHand
	jcxz	DTDone
	cCall	SelectObject,<[si.Pstruct.psHdc],cx>
DTDone:
        ret
DeAllocResText endp

;****************************************************************************
;
; AdjustSelText - Adjust current char if it is in the selection rect
;
; ENTRY:
;	SS:BP -> Text paint frame
;	DS:SI -> Extended paint structure
;	AX is attr/char of interest
;	EDI indicates AX's location in the video buffer
;	   together with pgOffst
; EXIT:
;	AH adjusted if in selection rectangle
;	TrueColor on stack frame set to input AH
;	NOTE: High bit of AH (blink bit) is turned off by this routine
;	      iff the app hasn't turned it off.
; USES:
;	AH,FLAGS
;
AdjustSelText proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing

if 0
	bt	[si.GGrbArea.GrbStatusFlags],BlinkTurnedOffBit
	jnc	SHORT DoBlinkLogic			; no
	jc	SHORT AST_00			;  Y: don't turn off blinking

DoBlinkLogic:
	and	ah,01111111B			; Ignore blink bit

    ;
    ; Set intensity bit for Bk Color(except Black/grey) 
    ;
        test    ah,01110000B            ; Q: Black Bk color?
        jz      SHORT AST_00            ;   Y: Skip turning on intensity bit
        push    ax
        and     ah,01110000B
        cmp     ah,01110000B            ; Q: Low Int white Bk color?
        pop     ax                      
        je      SHORT AST_00            ;   Y: Skip turning on intensity bit

        or      ax,8000h                ;   N: use intense Bk colors always
endif
AST_00:
	mov	TrueColor,ah
	test	[si.SelStruc.GrabArea.SelecFlags],SelectOn ; Selection active?
	jnz	short LSel				   ; Yes
	ret

LSel:
    ;
    ; Compute row,col of char
    ;
	push	dx
	push	cx
	push	ax
	mov	eax,edi
	sub	eax,PgOffst	; AX is byte index into Text buffer
	xor	dx,dx
	mov	cx,BytesPerLine
	div	cx		; AX is row, DX is col*2
	shr	dx,1		; DX is col
    ;
    ; Is char in selection rect
    ;
	cmp	al,byte ptr [si.SelStruc.GrabArea.Irect.rcLeft.1]
	jb	short NotInSelRect
	cmp	al,byte ptr [si.SelStruc.GrabArea.Irect.rcTop.1]
	jae	short NotInSelRect
	cmp	dl,byte ptr [si.SelStruc.GrabArea.Irect.rcLeft]
	jb	short NotInSelRect
	cmp	dl,byte ptr [si.SelStruc.GrabArea.Irect.rcTop]
	jae	short NotInSelRect
    ;
    ; Char is in selection, NOT its attribute to invert the colors
    ;
	pop	ax
	not	ah
	and	ah,011111111B			; Ignore blink bit
	push	ax
NotInSelRect:
	pop	ax
	pop	cx
	pop	dx
	ret

AdjustSelText endp

;****************************************************************************
;
; Outline - Output a line in current color setting
;
; ENTRY:
;	SS:BP is stack frame pointer for text frame
;	DS:SI -> Extended paint structure
;	DS:BX -> Text sub structure of extended paint structure
; EXIT:
;	Chars in ToutBuf output at current location indicated by text sub struct
;	TLineXPos advanced to next char after last output
;	ToutBuf emptied
; USES:
;	ALL but ES,DS,AX,BX,CX,DX,BP
;
Outline proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing

	push	es
	push	ax
	push	edx
	push	cx
	push	bx
	lea	cx,ToutBuf
	xchg	cx,pToutBuf			; Reset and get current
	sub	cx,pToutBuf			; Size
	jcxz	short nochars			; Empty, done
	mov	ax,[bx.TPFntWid]
	mul	cx				; AX is with in pix
	add	ax,TLineXPos			; AX is new X coord
	xchg	ax,TLineXPos			; Set new, get old X coord
	push	[si.Pstruct.psHdc]		  ; hDC
	push	ax				; X
IFDEF DEBUG
public LineNum
LineNum:
ENDIF
	push	[bx.TPYpos]			; Y
	push	ss				; pBuff
	push	pToutBuf
	push	cx				; Size
	cCall	TextOut
nochars:
	pop	bx
	pop	cx
	pop	edx
	pop	ax
	pop	es
	ret
Outline endp

;****************************************************************************
;
; BuildTextRects
;
; ENTRY:
;	AX = modified pages bit mask
;	CX = visible pages count
;	DS:SI -> Extended paint structure
;	BP = standard stack frame
;	DS:DI -> buffer for modified rects (size = SIZE OF DISPMOD)
;
; EXIT: if ZF = 1, no modifications detected (CX=0)
;	DS:DI -> list of modified rects
;	CX = count of rects
;
; USES:
;	AX, BX, CX, DX, DI, ES
;
mVisPages    LABEL BYTE 	    ; Pages count mapped to bit mask
	DB  0,1,3,7
VPgsLen equ $-mVisPages-1

public BuildTextRects

BuildTextRects proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing

	cmp	cx,VPgsLen
	jbe	SHORT BTR_GoodPgCount
	mov	cx,VPgsLen
BTR_GoodPgCount:
;
; Justify modified pages bit mask to displayed pages
;
	mov	ebx,DWORD PTR [MemState.VDA_Mem_DPagOff]
	shr	ebx,12			; EBX = page num display off * 2
	xchg	bx,cx
	shr	ax,cl			; justify page bit map
	xor	ah,ah
	and	al,mVisPages[bx]	; Q: Any visible pages modified?
	mov	bx,di			;	BX = rect pointer
	jz	BTR_Exit			;   N: All done

;
; Pretend that no pages are visible if rcBottom <= rcTop
;
	mov	cl,BYTE PTR [si.Pstruct.PTVDRect.rcBottom]
	cmp	cl,BYTE PTR [si.Pstruct.PTVDRect.rcTop]
	jbe	BTR_Exit

;
; Set up for showing screen.
;   BytesPerLine = byte width of rows
;   AH = modified pages mask, adjusted for start of display
;   AL = first row (zero)

	mov	cx,80
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],1
	jbe	SHORT BTR_GotColumns
	mov	cx,160
BTR_GotColumns:
	mov	BytesPerLine,cx 		; Set bytes per row

	mov	ecx,DWORD PTR [MemState.VDA_Mem_DPagOff]
BTR_AdjustOffsetLp:
	sub	ecx,1000h
	jae	SHORT BTR_AdjustOffsetLp
	add	ecx,1000h

	xor	dx,dx
	les	edi,VidAddr			; EDI -> start of display mem


;
; Build rectangles for contiguous changed pages
;
;   AL = dirty page mask (at least one dirty)
;   DL = start row number (zero)
;   EDI -> start of first displayed row
;   ECX = offset within page to start of video display
;   SI -> extended paint structure
;
	shr	ax,1				; Q: This page modified?
	jc	SHORT BTR_1stPage		;   Y: Start at first page
	shr	ax,1				; Q: Just last page modified?
	mov	ax,2000h			; only page 2 modified.
	jnc	SHORT BTR_ModFromAX		;   Y: make rectangle for that

; The second and possibly third page are modified
;   Since the last row on the this page passes over the page boundary,
;   we are actually calculating for the row number and address of the last row
;   that starts on the this page.  If there were an exact number of rows on
;   the this page, then this would correctly calculate the first row
;   of the next page.
	mov	ax,1000h			; page 1 till end modified.
; AX = offset to start of page 1 or page 2 from page 0 start
BTR_ModFromAX:

	sub	ax,cx				; AX = offset to start of pg
						;	from first displayed row
	push	ax				; save this offset
	xor	dx,dx				; for div by a word
	div	BytesPerLine			; find # line offset
	mov	cx,dx				; CX = bytes to start of next
						;   page from start of the first
						;   row on the next page
	mov	dx,ax				; DL=first row on next page
	pop	ax
	sub	ax,cx				; Offset from first displayed
						;   row to first row next pg
	movzx	eax,ax
	add	edi,eax 			; EDI->first row next page start
BTR_Mod_To_End:
	mov	cl,[si.EPGrabDTA.CntrlSt.VDA_EGA_Rows] ; CL=rows to display end
	sub	cl,dl				; Q: Any displayed mods?
	ja	SHORT BTR_MakeRects		;   Y: go build rects
	jmp	BTR_Exit			;   N: exit with no mods

BTR_1stPage:
; Here we include modifications all the way to the end if there are any more
;   modified pages.  In the case of 52 line mode, this is overkill and could
;   be handled better.	However, it is VERY UNUSUAL for anyone to have 3
;   pages of text so we are not going to worry about the fact that page 2
;   may not be modified and we are going to act as though it is.
	mov	eax,0				; Start at row 0
	mov	dl,al
						; Q: More than 1st page mod'd?
	jnz	SHORT BTR_Mod_To_End		;   Y: assume all screen mod'd
						;   N: just one page mod'd
	mov	ax,1000h
	sub	ax,cx
	div	BytesPerLineByte		; AL = rows to end of page
	or	ah,ah
	jz	SHORT BTR_1P_0
	inc	al				; include partial line
BTR_1P_0:
	mov	cl,al				; CL = page count
	cmp	al,[si.EPGrabDTA.CntrlSt.VDA_EGA_Rows] ; Q: end > display end?
	jbe	SHORT BTR_1P_1			;	    N: Use page end
	mov	cl,[si.EPGrabDTA.CntrlSt.VDA_EGA_Rows] ;    Y: use display end
BTR_1P_1:
	xor	eax,eax 			; Start at row 0
	mov	dl,al

; Scan the text and make enclosing rectangles
;   EAX = byte offset to row DL from start of display
;   CL = count of rows
;   DL = start row number
;   BX -> modified rectangles structure
;   SI -> extended paint structure
;   EDI -> start of row DL
BTR_MakeRects:
	push	esi
	cmp	DWORD PTR [MemState.VDA_Mem_Addr_Win_State],0 ;Q: WinMemState?
	jz	BTR_MakePageRect		;   N: make page rects

	cmp	dl,BYTE PTR [si.PStruct.PTVDRect.rcTop]	; Q: Start row visible?
	jae	SHORT BTRMR_01			;   Y: use it
	add	cl,dl				;   N: recalc using visible row
	mov	dl,BYTE PTR [si.PStruct.PTVDRect.rcTop]
	sub	cl,dl
	sub	edi,eax
	movzx	eax,dl
	mul	BytesPerLineByte
	add	edi,eax 			; EDI -> start of row DL
BTRMR_01:
	push	edx
	push	eax
	mov	ax,[si.PStruct.PTVDRect.rcBottom]
	sub	al,dl
	cmp	al,cl				; Q: Last row visible?
	jae	SHORT BTRMR_02_5		;   Y: use it
	mov	cl,al				;   N: use count to last visible
BTRMR_02_5:
	movzx	eax,cl
	mul	BytesPerLineByte
        mov     edx,[MemState].VDA_Mem_Size_P0  ; Truncate at end
	cmp	eax,edx
	jbe	SHORT BTRMR_02
IFDEF	DEBUG
	int	3
ENDIF
	mov	eax,edx				; truncated!
	div	BytesPerLineByte		; last line
	mov	cl,al

BTRMR_02:
	mov	dx,[si.PStruct.PTVDRect.rcRight]
	shl	dx,1
	cmp	dx,BytesPerLine 		; Q: Right beyond end of line?
	jbe	SHORT BTRMR_03			;   N: Use it
	mov	dx,BytesPerLine 		;   Y: Truncate it
BTRMR_03:
	shr	dx,1
	movzx	eax,[si.PStruct.PTVDRect.rcLeft]
	sub	dx,ax
	mov	WidPaint,dx			; WidPaint = chars/line visible
	shl	ax,1				; EAX = byte offset to left col
	pop	edx
	add	edi,eax 			; EDI -> left col of first row
	add	eax,edx 			; EAX = byte offset to left col
	pop	edx				;	of row DL
	mov	esi,DWORD PTR [MemState.VDA_Mem_Addr_Win_State]
	add	esi,eax 			; ESI -> row DL left col
	cld
; Changes are defined by differences between data pointed
;   to by ES:EDI and DS:ESI within CL rows
;   and within WidPaint words on each row

	mov	al,cl
	mov	ah,dl
	movzx	edx,BytesPerLineByte
; Find first changed line

BTR_NoChg_NextLine:
	push	esi
	push	edi
	movzx	ecx,WidPaint
	cld
	repe cmps WORD PTR ES:[EDI],WORD PTR ES:[ESI]
	pop	edi
	pop	esi
	jnz	SHORT BTR_ChgLine
	add	esi,edx
	add	edi,edx
	inc	ah
	dec	al
	jnz	SHORT BTR_NoChg_NextLine
; Found no changes

	pop	esi
; Return DI->mod structure, CX=mod count
BTR_Exit:
	cld					; just to be nice
	mov	di,bx				; DI = data structure pointer
	mov	cx,[di.VDD_Mod_Count]		; CX = rectangle count
	test	cx,cx
	ret

;   CL = count of rows
;   DL = start row number
;
BTR_MakePageRect:
	add	cl,dl				; CL = last row + 1
	mov	dh,dl				; DH = top row
	mov	ax,[si.PStruct.PTVDRect.rcLeft]
	mov	dl,al				; DL = leftmost column
	mov	ax,[si.PStruct.PTVDRect.rcRight]; AL = rightmost column + 1
	mov	ah,cl				; AH = last row + 1
; Have change rectangle from row DH, column DL to row (AH - 1), column AL
	call	EmitChgRect
	pop	esi
	jmp	BTR_Exit

;
; AH = first changed line
; AL = count of lines to end
; CL = WidPaint - col of change - 1
; ESI, EDI -> start of first changed line
;
BTR_ChgLine:

	push	esi
	push	edi				; Save ptrs to first changed row
	push	ax				; Save row, count to end
	mov	dx,WidPaint
	dec	al
	mul	BytesPerLineByte		; AX=offset to last line start
	add	ax,dx
	add	ax,dx
	sub	ax,2
	movzx	eax,ax				; EAX=offset to last line end
	add	esi,eax 			; ESI, EDI -> end of last row
	add	edi,eax
	pop	ax
	sub	dl,cl
	mov	dh,ah				; DH = row of change
	dec	dl				; DL = column of change
	push	dx
	add	ah,al				; AH = last row + 1
						; AL = row count + 1
	movzx	edx,BytesPerLineByte
	or	al,al
	jz	SHORT BTR_LastChgLine
BTR_FindLastChg:
	push	esi
	push	edi
	movzx	ecx,WidPaint
	std
	repe cmps WORD PTR ES:[EDI],WORD PTR ES:[ESI]
	cld					; BE SAFE!!!
	pop	edi
	pop	esi
	jnz	SHORT BTR_LastChgLine
	sub	esi,edx
	sub	edi,edx
	dec	ah				; previous row number
	dec	al				; Q: Any more rows?
	jnz	SHORT BTR_FindLastChg		;   Y: compare previous

	pop	ax
	pop	eax
	pop	eax
	pop	esi
; No changes found!! VERY STRANGE, what happened to change found earlier?

IFDEF   DEBUG
	push	edx
	push	ebx
	mov	bx,si
	mov	esi,codeOffset DiffErr
	mov	edx,SHELL_Debug_Out
	call	[bx.ShellCall]
	mov	si,bx
	pop	ebx
	pop	edx
	jmp	short BTRContinue0

DiffErr  db	  "Grabber Main mem and Copy mem identical!",0

BTRContinue0:
ENDIF

	jmp	BTR_Exit

BTR_LastChgLine:
	pop	dx				; DH,DL = start row, column
	pop	edi				; ESI, EDI -> start row
	pop	esi
	inc	cl
	mov	al,cl				; AL = end column + 1
	pop	ecx
	push	ecx
	xchg	esi,ecx
	inc	dh
	cmp	dh,ah
	jnz	SHORT BTR_MultLineChange
	add	dl,BYTE PTR [si.PStruct.PTVDRect.rcLeft]
	add	al,BYTE PTR [si.PStruct.PTVDRect.rcLeft]
	dec	dh
;
; Have change from row DH, column DL through column (AL - 1)
;
	call	EmitChgRect
	pop	esi
	jmp	BTR_Exit

BTR_MultLineChange:

	mov	dl,BYTE PTR [si.PStruct.PTVDRect.rcLeft]
	mov	al,BYTE PTR [si.PStruct.PTVDRect.rcRight]
	xchg	esi,ecx			; ESI -> mod'd row
	dec	dh			; DX = (a,b) , AX = (c,d)
if 0
   ;
   ; This is Unnecessarily complicated by the fact that scrollwindowsex
   ; will generate a clip region if the window is covered and a zillion
   ; ways can be imagined where the updateregion will be the complete
   ; window!!!!
   ; However....
   ; If you want to see the performance without scrolling, take out
   ; the next few lines (till NoScrollInEffect)
   ;
	push	eax	
	push	edx
	push	ebx
   ;
   ; ShrinkRect returns with CY if a scroll is done. 
   ; In this case, we have to look at only one line.
   ; and dx = (a,d-1)...
   ;
	call	ShrinkRect
	pop	ebx
	pop	edx
	pop	eax
	jnc	SHORT NoScrollInEffect
	mov	dh,ah
	dec	dh				; 
	jae	SHORT NoScrollInEffect
	mov	dh,0
NoScrollInEffect:
endif

	call	EmitChgRect		; for modetext
	pop	esi
	jmp	BTR_Exit

BuildTextRects endp

if 0
;*****************************************************************************
; ShrinkRect:
; Looks for scroll of 1, and scrolls (by bitblitting) the scrollrect.
; Entry: DX = (top,left) first change
;	 AX = (bottom, right) last change
;	 ESI = mod'd row
;	 CX = src to Pstruct
; Exit: CY if scroll was detected else NC
; Uses: EBX, EDX (through BltScrolledRect)
;*****************************************************************************

public ShrinkRect

ShrinkRect proc near
	push	esi
	push	edi
	call	CheckScroll		; has rect scrolled ?
	pop	edi
	pop	esi			; All registers same as before.
	jnc	SHORT NoShrinkReq	; get out, no scroll

	call	BltScrolledRect		; blit the scrolled rectangle
	jnc	SHORT NoShrinkReq

	push	esi
	push	edi
	push	ecx
	push	eax			; AH = # of changed lines

	dec	ah			; only one line has scrolled.
	movzx	ebx,BytesPerLine
	movzx	ecx,WidPaint
	xchg	esi,edi
	cld
CSRStart:
	push	ecx
	push	edi
	push	esi
	rep movs WORD PTR ES:[ESI],WORD PTR ES:[EDI]	; main mem => copy mem
	pop	esi
	pop	edi
	pop	ecx
	add	esi,ebx
	add	edi,ebx
	dec	ah
	jnz	SHORT CSRStart
 ;
 ; The remaining region doesn't need to be touched because the mem is
 ; still there...
 ;
	pop	eax
	pop	ecx
	pop	edi
	pop	esi
	stc				; SCROLLED!
NoShrinkReq:
	ret
ShrinkRect endp

;****************************************************************************
; BltScrolledRect:
;  This calls scrollwindowEx
; Entry: DX = (top,left) first change
;	 AX = (bottom, right) last change
;	 ESI,EDI = mod'd row
;	 CX = src to Pstruct
;  NOTE:!!!!
;  DH = 0  , AH = bottom, size of scroll = ah - 1
;  ESI = EDI = first changed line.
;
; EXIT:
;
; USES: EDX (probably scrollwindow uses it)
;
;****************************************************************************

BltScrolledRect proc near
	push	esi
	push	edi
	push	ebx
	push	ecx
	push	dx

	push	esi
	push	edi

 ;
 ; first find the width of scrolled rect.
 ; This opt can reduce the size by half! 
 ; collect it in dh
 ;
	movzx	dx,ah			; dh = 0!
	dec	dl			; # of lines to check for
	movzx	ecx,WidPaint		; size of compare
	std
SrchForMaxRight:
	push	ecx
	push	esi
	push	edi
	shl	ecx,1
	add	esi,ecx			; advance to end of widpaint
	add	edi,ecx			; advance to end of widpaint
	shr	ecx,1
	sub	edi,2			; for rep, come back 2 bytes
	sub	esi,2
	rep cmps WORD PTR ES:[EDI],WORD PTR ES:[ESI]	; compare main, copy mem
	pop	edi
	pop	esi
	cmp	dh,cl			; new dh = max(dh,cl)
	jae	SHORT dhOK
	mov	dh,cl
dhOK:
	movzx	ecx,BytesPerLine	; advance esi, edi to next line 
	add	esi,ecx
	add	edi,ecx
	pop	ecx			; get back widpaint
	add	dh,4			; if dh+4 > cl, then no point in
	cmp	dh,cl			; checking furthur, use the whole
	jae	SHORT dh_discard
	sub	dh,4
	dec	dl			; end of lines?
	jnz	SHORT SrchForMaxRight	; No, continue
	movzx	cx,dh			; cx = width of scroll
	inc	cx			; add one, be safe
dh_discard:
	pop	edi
	pop	esi

	push	cx
;
; Now try to find the first leftmost char to scroll, 
; collect it in bh
;
	movzx	bx,ah			; height of scroll
	dec	bl			; bh = 0
	dec	bh			; bh = -1
	movzx	ecx,WidPaint		; size of compare
	cld
SrchForMinLeft:
	push	ecx
	push	esi
	push	edi
	rep cmps WORD PTR ES:[EDI],WORD PTR ES:[ESI]	; compare main, copy mem
	pop	edi
	pop	esi
	cmp	bh,cl			; new bh = min (bh,cl?)
	jbe	SHORT bhOK
	mov	bh,cl
bhOK:
	movzx	ecx,BytesPerLine	; advance esi, edi to next line 
	add	esi,ecx
	add	edi,ecx
	pop	ecx			; get back widpaint
	cmp	bh,3			; is left < 3 ?
	jb	SHORT StartLeft
	dec	bl			; end of lines?
	jnz	SHORT SrchForMinLeft	; No, continue
	mov	cx,WidPaint
	sub	cl,bh
	mov	bh,cl			; start of rect
StartLeft:
	xor	bh,bh			; leftmost is the start

	pop	cx
	mov	ch,bh
	pop	dx			; (top,left)
	pop	esi			; was ecx
	push	esi			; si -> Pstruct
	push	ax			; (bottom,right)
	push	es			; selector for video memory

	movzx	bx,cl
	sub	bl,ch			; width of scroll
	add	bx,20
	cmp	bx,WidPaint		; is width ok? 
	ja	SHORT SkipScrollRectLarge	; No, get out with carry clear
 ;
 ; ch = horizontal start of scroll
 ; cl = horizontal extent of scroll in chars
 ; ah is height of scroll rectangle as windows sees it...
 ;
	sub	sp, SIZE RECT		; create space
	mov	bx,sp			; bx points to it now

	movzx	ax,ah
	mul	[si.FntHgt]		; height of scroll rect
	add	ax,[si.Pstruct.PsrcPaint.rcTop]
	mov	[bx.rcBottom],ax	; AX = bottom of scroll rect
	mov	ax,[si.Pstruct.PsrcPaint.rcTop]
	mov	[bx.rcTop],ax		; AX = top of scroll
	mov	ax,[si.FntWid]
	mul	ch
	add	ax,[si.Pstruct.PsrcPaint.rcLeft]
	mov	[bx.rcLeft],ax
	mov	ax,[si.FntWid]
	mul	cl			; cx is width of scroll
	add	ax,[si.Pstruct.PsrcPaint.rcLeft]
	mov	[bx.rcRight],ax
	mov	ax,[si.FntHgt]
	push	[si.WindHand]		; hWnd
	push	0			; XAmount
	neg	ax			; reverse!
	push	ax			; YAmount
	push	ss			; lpRect
	push	bx
	push	ss			; lpClipRect
	push	bx
	push	0			; HrgnUpdate
	push	0			; lpSomething
	push	0
	push	0			; flags
	cCall	ScrollWindowEx
	add	sp, SIZE RECT
	stc

SkipScrollRectLarge:

	pop	es
	pop	ax
	pop	ecx
	pop	ebx
	pop	edi
	pop	esi
	ret	
BltScrolledRect endp

;****************************************************************************
; CheckScroll:
;
; DESCRIPTION:
;
; First check: is DH = 0? 
; If no, get out... (scroll of just one is good)
; Then look for a scroll of 1.
;
; ENTRY:
;	DH = first changed line, DL = rcLeft
;	AH = last changed line
;	ESI, EDI -> row DH at column DL
;
; EXIT: CF = 1 one line scroll
;	CF = 0 Otherwise
;
; USES: ESI, EDI
;
public CheckScroll

CheckScroll proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing

	push	ecx
	push	ebx
	push	eax			; save ecx,ebx,eax
	or	dh,dh			; is this first row?
	jnz	DetectNoScroll		; NO, no scroll
	movzx	ebx,BytesPerLine	; offset to next line
	add	esi,ebx			; next line
	movzx	ecx,WidPaint		; # of words to compare
	dec	ah			; ah is line+1
	jz	DetectNoScroll		; ah = 1

NextLineMem:
	push	ecx
	push	edi
	push	esi
	rep cmps WORD PTR ES:[EDI],WORD PTR ES:[ESI]	; compare line
	pop	esi
	pop	edi
	pop	ecx
	jnz	DetectNoScroll		; difference found, No scroll
	add	esi,ebx
	add	edi,ebx			; advance to next line
	dec	ah
	jnz	SHORT NextLineMem	; at end?
	stc				; yes, found scroll
	jc	SHORT ScrollDetect
DetectNoScroll:
	clc
ScrollDetect:
	pop	eax
	pop	ebx
	pop	ecx
	ret
CheckScroll endp

endif

if 0
Min_equal_row	equ	12

;****************************************************************************
; BreakRectIfPossible:
; Description:
;	We would like to break this huge rect in (DX,AX) down into two if
;	possible. This is useful in word/edit etc. where (col,row) is 
;	maintained at the bottom and any change in current char produces
;	a change in this area.
; Entry:
;	DX = (start row, start col), AX = (end row+1, end col)
;	ESI, EDI -> start row...
;****************************************************************************
BreakRectIfPossible proc near

	push	ebx
	mov	bh,ah
	sub	bh,dh			; height of Rect
	cmp	bh,Min_equal_row
	jbe	SHORT ScanOver
	movzx	bx,ah
	mov	bh,dh			; last different line...
	sub	bl,bh			; bl = #to scan, bh = #last diff.
BRP_Look:
	movzx	ecx,WidPaint
	shl	ecx,1			; to bytes
	add	esi,ecx
	add	edi,ecx			; go to next line
	shr	ecx,1			; to words...
	dec	bl			; reduce #scan
	jz	SHORT ScanOver		; finish scan...
	push	esi
	push	edi
	cld				; BE SAFE!!!
	rep cmps WORD PTR ES:[EDI],WORD PTR ES:[ESI]
	pop	edi
	pop	esi
	jz	SHORT BRP_Look
	mov	ch,ah
	sub	ch,bl			; different row
	mov	cl,ch
	sub	ch,bh			; how much distance ?
   ;
   ; If the difference is more than Min_equal_row, then we break
   ; and quit!!!
	cmp	ch,Min_equal_row	; is it ?
	xchg	bh,cl			; save and init...
	jb	SHORT BRP_Look		; set and go look for more...
   ; cl = the last diff row to break at. bh = current row for new break.
	mov	ch,bh			; cx has all info!
	pop	ebx
	push	ebx			; save for later pop
	xchg	cl,ah
	inc	ah			; (DX,AX) set properly...
	push	cx
	call	EmitChgRect		; emit it..
	pop	cx
	xchg	cl,ah			; AX set again
	mov	dh,ch			; DX set again
ScanOver:
	pop	ebx
	ret
BreakRectIfPossible endp
endif

;****************************************************************************
; EmitChgRect
;
; Add rectangle row DH, column DL; row AH, column AL to Mod_List
;
; ENTRY:
;   BX -> change structure
;   DH,DL = top, left
;   AH,AL = bottom, right
;
; EXIT:
;   If CF = 1, Mod_List is full
;   CX,SI destroyed
;
public EmitChgRect

EmitChgRect proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing

	mov	cx,ax
	mov	si,[bx.VDD_Mod_Count]		; DX = current rectangle number
	inc	[bx.VDD_Mod_Count]		; Another rectangle
	shl	si,3				; 8 bytes per rectangle
	cmp	si,(SIZE VDD_MOD_STATE)-VDD_Mod_List-1 ; Q: Too many rects?
	cmc
	jc	SHORT BTR_NR_None		;	Y: Stop here
	add	si,bx
	movzx	ax,dh
	mov	[si.VDD_Mod_List.rcTop],ax	; Set top of rectangle
	movzx	ax,dl
	mov	[si.VDD_Mod_List.rcLeft],ax	; Set left
	movzx	ax,ch
	mov	[si.VDD_Mod_List.rcBottom],ax	; Set bottom
	movzx	ax,cl
	mov	[si.VDD_Mod_List.rcRight],ax
	clc
	mov	ax,cx
BTR_NR_None:
	ret
EmitChgRect endp

;****************************************************************************
;
; ClearWinMemState - Init WinMemState to zeroes
;
; ENTRY: AH = BIOS mode
;	 DS:SI -> EXTPAINTSTRUC
;
; EXIT: NONE
; 
; USES: 
;
;*****************************************************************************
ClearWinMemState proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing

	cmp	ah,1
	mov	ax,80
	jbe	SHORT PST_40Col
	mov	ax,160
PST_40Col:
	mov	BytesPerLine,ax

	mul	[si.PTVDRect.TPRect.rcTop]
	movzx	eax,ax			; EAX=index of first byte of first line
	mov	es,VidSel
	mov	edi,DWORD PTR [MemState.VDA_Mem_Addr_Win_State]
	or	edi,edi
	jz	SHORT PST_NoWinMemState
	add	edi,eax
	movzx	eax,[si.PTVDRect.TPRect.rcLeft]
	add	edi,eax
	add	edi,eax
	mov	cx,[si.PTVDRect.TPRect.rcRight]
	sub	cx,ax
	mov	dx,[si.PTVDRect.TPRect.rcBottom]
	movzx	ax,[si.EPGrabDTA.CntrlSt.VDA_EGA_Rows]
	cmp	dx,ax
	jbe	SHORT PST_GoodRows
	mov	dx,ax
PST_GoodRows:
	push	dx
	mov	dx,WORD PTR [MemState.VDA_Mem_Size_Win_State+2]
	mov	ax,WORD PTR [MemState.VDA_Mem_Size_Win_State]
	div	BytesPerLine
	pop	dx
	cmp	ax,dx			; Q: rows within memory allocated?
	jae	SHORT PST_GotMem	;   Y: continue
; We are ignoring partial line clearing here.  The partial line will
;   get repainted shortly because of the controller state change (which caused
;   us to want to paint memory that is not allocated in the first place).
	mov	dx,ax			;   N: Use mem allocated
PST_GotMem:
	sub	dx,[si.PTVDRect.TPRect.rcTop]
	jbe	SHORT PST_NulRect
    ;
    ; ES:DI -> start of paint in WinMemState
    ; CX = characters per line
    ; DX = number of lines
    ;
	cld
	xor	ax,ax
PST_ClearLoop:
	push	cx
	push	edi
	movzx	ecx,cx
	rep stos WORD PTR es:[edi]
;******
	db	67h			; Problem Workaround DO NOT REMOVE
	nop
;******
	pop	edi
	movzx	ecx,BytesPerLine
	add	edi,ecx
	pop	cx
	dec	dx
	jnz	SHORT PST_ClearLoop

PST_NulRect:
PST_NoWinMemState:
	ret
ClearWinMemState endp

;****************************************************************************
;
; CreateOverScanBrTxt - Create the overscan brush for text mode and select it
;
; ENTRY:
;	DS:SI -> EXTPAINTSTRUC structure of paint
;	SS:BP -> Text mode paint frame
; EXIT:
;	Correct brush selected in display DC
; USES:
;	ALL but DS,SI,DI,BP
;
CreateOverScanBrTxt proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
    ;
    ; Try to create a brush in the overscan color
    ;
	mov	bl,[si.EPGrabDTA.CntrlSt.VDA_EGA_Colr]	; Get overscan color
	mov	bh,bl
	and	bl,00000111B		; Mask to RGB values
	shl	bl,1
	and	bh,00010000B		; Mask to intensity bit
	or	bl,bh
	xor	bh,bh			; bx is IRGB color * 2
	shl	bx,1			; * 4 for table
	mov	ax,bx
	cCall	GetNearestColor,<[si.Pstruct.psHdc],[bx.RGBTable.2],[bx.RGBTable]>
	cCall	CreateSolidBrush,<dx,ax>
	or	ax,ax
	jz	short DefOvscBr
GotOvscBr:
	mov	BkTxtBrsh,ax
    ;
    ; Select the brush into the display DC
    ;
	cCall	SelectObject,<[si.Pstruct.psHdc],ax>
	mov	OldBrshHand,ax
	ret

DefOvscBr:
	mov	ax,[si.BlkBrshH]	; Black background brush selected
	jmp	short GotOvscBr


CreateOverScanBrTxt endp

sEnd	code
	end
