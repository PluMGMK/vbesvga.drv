;-----------------------------------------------------------------------------
;
;   Screen Grabber for IBM EGA/VGA adaptor
;
;   These routines perform screen grab functions.
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
externFP	CreateBitmap
externFP	SetDIBits
externFP	CreateCompatibleBitmap
externFP	SelectObject
externFP	DeleteObject
externFP	PatBlt
externFP	GetDC
externFP	ReleaseDC

externFP	GlobalFree
externFP	GlobalAlloc
externFP	GlobalLock
externFP	GlobalUnlock
externFP	GetDeviceCaps
ifdef	DBCS
if1
%out DBCS code enabled
endif
externFP	IsDBCSLeadByte
endif	; DBCS

;-----------------------------------------------------------------------------
;
; External GRABBER Procedures
;
externNP        GetTextWidHgt
externNP	ComputeSelTextrect
externNP	CheckCtrlState
externNP	GetVidSel
externNP	ClearVidSel
externNP        InitFrameVars

externNP        GetWinRGB
externNP        CheckMode
externNP        BuildDisplayRect
externNP        SkipBkBits
externNP        AllocCommonRes
externNP        DeAllocAllRes
externNP        SetParamsCGAMode
externNP        SetParamsMode11
externNP        SetParamsPlanarMode
externNP        SetupLineBits
externNP        GetDwordDataEF10
externNP        GetWordDataD
ifdef	DBCS
externNP	IsDBCSMiddleText
endif	; DBCS


;-----------------------------------------------------------------------------

sBegin	code
	assumes cs,code

	public	RenderRectGrxDisplay
	public	RenderRectGrxMono
	public	RenderRectText
        
        public  SetScreenBMBits
        public  XferMonoBits 
        public  BuildDIBHdr
        public  ProcessDwordE10
        public  ProcessWordE10
        public  ProcessByteE10
        public  ProcessWordD
        public  ProcessByteD
        

;*****************************************************************************
;
; GrabComplete - Signal that we are finished with the grab
;
; This is called after the grab is complete. Time to call the VDD
; and have him free the grab memory.
;
; ENTRY:
;	lpPntStruc Extended paint structure
;	wParam = parameter from VDD message (= -1 if VMDOSAPP origin)
;	lParam = parameter from VDD message EVENT ID
; EXIT:
;	None
; USES:
;	C Standard
;
;*****************************************************************************
cProc  GrabComplete,<FAR,PUBLIC>

	ParmD	lpPntStruc
	ParmW	wParam
	ParmD	lParam

	localV	FrameVars,StdGrbFrameSz
cBegin
	push	esi
	push	edi

	InitBasicFrame

	cmp	wParam,-1			; Origin not VDD?
	jz	short GCDone			; Yes, NOP
	lds	si,lpPntStruc
    ;
    ; Reset the controller state bit so that we chuck the grab
    ; controller state and re-get the Paint state.
    ;
	btr	[si.EPStatusFlags],fVValidBit
	mov	ax,GRB_Free_Grab                ; Function number
	mov	ebx,[si.ThisVMHand]             
        call    [si.GGrbArea.VddApiProcAdr]     ; Call VDD
GCDone:
	pop	edi
	pop	esi
cEnd


;*****************************************************************************
;
; GetSelectionSiz - Return size to render selection
;
; NOTE THIS IS NO LONGER AN EXPORT. It is only called internally to the
;	grabber.
;
; ENTRY:
;	lpPntStruc Extended paint structure
;	SizeType == 0 for Normal size (text or MONO bitmap)
;		 != 0 for Display format size of BITMAP (error if text)
;	wParam = parameter from VDD message (= -1 if VMDOSAPP origin)
;	lParam = parameter from VDD message (= 0  if VMDOSAPP origin) Event ID
; EXIT:
;	AX == DX == 0
;	    error
;	Else
;	    DX:AX is size in bytes to render selection
;		NOTE: For graphics renders, the rendering MUST be an EVEN
;			number of bytes wide! This is because Windows
;			Bitmaps are accessed with WORD string instructions.
; USES:
;	C standard
;
;*****************************************************************************
cProc  GetSelectionSiz,<NEAR,PUBLIC>

	ParmD	lpPntStruc
	ParmW	SizeType
	ParmW	wParam
	ParmD	lParam

	localV	FrameVars,StdGrbFrameSz
cBegin
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	esi
	push	edi

	InitBasicFrame

	lds	si,lpPntStruc
    ;
    ; Compute width and height
    ; NOTE: This code works for text and graphics because we know
    ;	byte alignment is maintained for graphics screens, and character
    ;	alignment is maintained for text screens (see ScreenAdjust)
    ;
	call	CheckCtrlState
    ;
    ; Now ds:bx,ds:si -> EXTPAINTSTRUC structure
    ;
	mov	ax,[bx.SelStruc.GrabArea.EndPointX]
	sub	ax,[bx.SelStruc.GrabArea.StartPointX]
	jns	short GotWid
	neg	ax
GotWid:
	mov	dx,[bx.SelStruc.GrabArea.EndPointY]
	sub	dx,[bx.SelStruc.GrabArea.StartPointY]
	jns	short GotHig
	neg	dx
GotHig:
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],7
	je	short TextSel
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],4
	jb	short TextSel
GraphicsSel:
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],10H
IFDEF	SAVEMEM
	je	NoSel
ELSE
	je	short NoDiv
ENDIF
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],0FH
IFDEF	SAVEMEM
	je	NoSel
ELSE
	je	short NoDiv
ENDIF
IFDEF	VGA
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],13H
IFDEF	MODE13
	je	short NoDiv
ELSE
	je	NoSel 		; No grabs in mode 13
ENDIF
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],11H
IFDEF	SAVEMEM
	je	NoSel
ELSE
	je	short NoDiv
ENDIF
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],12H
IFDEF	SAVEMEM
	je	NoSel
ELSE
	je	short NoDiv
ENDIF
ENDIF
	shr	dx,1			; Convert to display
NoDiv:
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],0DH
IFDEF	SAVEMEM
	je	NoSel
ELSE
	je	short Div2
ENDIF
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode],4
	je	short Div2
        jmp     short NoDiv2
Div2:
	shr	ax,1			; Convert to display
NoDiv2:
    ;
    ; Compute size of one plane
    ;
	add	ax,15			; Round up width to multiple of 16
	and	ax,1111111111110000B
	mov	cx,dx
	mul	cx			; DX:AX is number of pixels
	add	ax,7
	adc	dx,0
	mov	cx,8			; 8 pix per byte
	div	cx			; AX is # bytes for one plane
	xor	dx,dx
	cmp	SizeType,0
	jz	short CheckSize 	; For MONO (normal), only one plane
	mov	cx,4			; Display format is 4 planes
	mul	cx			; DX:AX is size for display format
CheckSize:
	mov	bx,ax
	or	bx,dx
	jz	short NoSel
	jmp	short GSSDone

TextSel:
	cmp	SizeType,0		; Valid for text?
	jnz	short NoSel		; No, error

        call    GetTextWidHgt
    ;
    ;	NOTE ABOUT THIS. You will note that this code simply computes
    ;	    the width in chars of the selection rect, adds two for a CR LF,
    ;	    then multiplies this times the height in lines of the selection
    ;	    rect. The actual Rendering done by RenderRect MAY NOT USE ALL OF
    ;	    THIS SPACE. The reason is that the render code "optimizes out
    ;	    trailing spaces" on each line. To compute the TRUE selection size
    ;	    we would have to do the same thing here. WE DON'T because it is
    ;	    simply not worth the trouble. The MAX size of a text grab is:
    ;			(80*43)+(2*43)+1
    ;	    In worst case (grab of totally blank screen) this will get
    ;	    optimized by the render code down to:
    ;			(2*43)+1
    ;	    wasting (80*43)=3,440 bytes of the allocated GRAB buffer.
    ;
    ;	    This amount of space is just not worth the effort required to
    ;	    not include it in the allocation.
    ;
	push	dx
	xor	dx,dx
	add	ax,cx
	dec	ax
	div	cx			; AX is width in chars
	pop	dx
	or	ax,ax
	jz	short NoSel
	inc	ax			; CR
	inc	ax			; LF
ifdef	DBCS
;added two for DBCS character on each side.
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode], 7
	je	DBCS_TextMode
	cmp	[bx.EPGrabDTA.CntrlSt.VDA_EGA_Mode], 3
	jg	@F
DBCS_TextMode:
	inc	ax			; for DBCS char
	inc	ax
@@:
endif	;DBCS
	xchg	dx,ax
	push	dx
	xor	dx,dx
	add	ax,si
	dec	ax
	div	si			; AX is height in lines
	pop	dx
	or	ax,ax
	jz	short NoSel
	mov	cx,dx
	mul	cx			; DX:AX is size in bytes
	add	ax,1			; NUL terminated
	adc	dx,0
	jmp	short CheckSize

NoSel:
	xor	ax,ax
	mov	dx,ax
GSSDone:
	pop	edi
	pop	esi
cEnd

;*****************************************************************************
;
; RenderSelection - Render selection into clipboard format
;
; ENTRY:
;	lpPntStruc Extended paint structure
;	wParam = parameter from VDD message (= -1 if VMDOSAPP origin)
;	lParam = parameter from VDD message (= 0  if VMDOSAPP origin) Event ID
; EXIT:
;       if (DX < 0)
;               Error
;       else if (DX = 0)
;               No Selection
;       else if (DX > 0)
;               DX = format, (CF_OEMTEXT or CF_BITMAP)
;               AX = Handle, <Memory Handle or Bitmap Handle)
;
; USES:
;	C standard      
;
;*****************************************************************************
cProc  RenderSelection,<FAR,PUBLIC>

	ParmD	lpPntStruc
	ParmW	wParam
	ParmD	lParam

	localV	FrameVars,StdGrbFrameSz
        localW  hMemory         ; Memory Handle for the render buffer
                                ; used for mono bitmaps or text renders

cBegin
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	esi
	push	edi

	InitBasicFrame

	or	GrbFlags,GrbFlgs_DoingGrab
	lds	si,lpPntStruc
	cmp	wParam, -1
	jz	short RenderFromPaintState
    ;
    ; Reset the controller state bit so that we chuck the PAINT state
    ;	and get the GRAB state.
    ;
	btr	[si.EPStatusFlags],fVValidBit
	jmp	short RenderFromGrabState

RenderFromPaintState:
	or	GrbFlags,GrbFlgs_DoingWindowSelGrab
RenderFromGrabState:
	call	CheckCtrlState
    ;
    ; Now ds:bx,ds:si -> EXTPAINTSTRUC structure
    ;
	test	[si.EPGrabDTA.CntrlSt.VDA_EGA_Flags],fVDA_V_ScOff
	jnz	RS_Error
	mov	cl,[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode]	; Get mode
	cmp	cl,7
	je	RSText
	cmp	cl,4
	jb	RSText
	test	[si.SelStruc.GrabArea.SelecFlags],SelectOn
	jz	RS_NoSelection
    ;
    ; Check Mode Byte
    ; Valid modes for VGA are 4,5,6,D,E,F,10,11,12
    ; Valid modes for EGA are 4,5,6,D,E,10
    ;
IFDEF VGA
	cmp	cl,12H
ELSE
	cmp	cl,10H
ENDIF
	ja	RS_Error

	cmp	cl,7
	jb	short RSGraphics

	cmp	cl,0DH
	jb	RS_Error
    ;
    ; Graphics (bitmap) render
    ;
RSGraphics:
	mov	bx,[si.SelStruc.GrabArea.StartPointX]
	mov	cx,[si.SelStruc.GrabArea.EndPointX]
	cmp	bx,cx			; This way?
	jbe	short SetLeftRight	; Yes
	xchg	bx,cx			; no, other way
SetLeftRight:
	mov	[si.SelStruc.GrabArea.Irect.rcLeft],bx
	mov	[si.SelStruc.GrabArea.Irect.rcRight],cx
	cmp	bx,cx			; zero width?
	jz	RS_NoSelection		; Yes

	mov	bx,[si.SelStruc.GrabArea.StartPointY]
	mov	cx,[si.SelStruc.GrabArea.EndPointY]
	cmp	bx,cx			; This way?
	jbe	short SetTopBottom	; Yes
	xchg	bx,cx			; no, other way
SetTopBottom:
	mov	[si.SelStruc.GrabArea.Irect.rcTop],bx
	mov	[si.SelStruc.GrabArea.Irect.rcBottom],cx
	cmp	bx,cx			; zero height?
	jz	RS_NoSelection
DisplayFormat:
        call    GetVidSel
        jc      RS_Error
    ;
    ; Get a Display Context
    ;
	cCall	GetDC,<[si.WindHand]>
	or	ax,ax		; Got a Valid hDC?
	jz	RS_Error        ; No
	mov	[si.Pstruct.psHdc], ax
	mov	bx,si
	lea	si,[si.SelStruc.GrabArea.Irect]
        call    RenderRectGrxDisplay
	jc	short TryGrxMonoFormat 	; Barfed, try mono format

        push    ax                      ; preserve Bitmap Handle
        call    ClearVidSel
	cCall	ReleaseDC, <[si.WindHand], [si.Pstruct.psHdc]>
        pop     ax

        mov     dx, CF_BITMAP              ; AX has the handle
	jmp	RS_Done

TryGrxMonoFormat:
	cCall	ReleaseDC, <[si.WindHand], [si.Pstruct.psHdc]>
    ;
    ; Allocate buffer for mono format.
    ;
	cCall	GetSelectionSiz,<lpPntStruc,0,wParam,lParam>   ; mono format size
	mov	cx,ax
	or	cx,dx
	jz	short RS_Error
    ;
    ; Try to allocate the memory
    ;
	regptr	ddSize,dx,ax
	cCall	GlobalAlloc,<GMEM_MOVEABLE+GMEM_ZEROINIT+GMEM_DDESHARE,ddSize>
	or	ax,ax
	jz	short RS_Error
	mov	hMemory,ax
	cCall	GlobalLock,<ax>
	mov	es,dx
	mov	di,ax		; es:di points at save area (mem just alloced)
        or      dx, ax
	jz	short RS_Error

	mov	bx,si
	lea	si,[si.SelStruc.GrabArea.Irect]
        call    RenderRectGrxMono
	jc	short RS_Error
	cCall	GlobalUnLock,<hMemory>
        cCall   GlobalFree,<hMemory>        
        cmp     ax, hMemory
        je      short RS_Error
        mov     dx, CF_BITMAP
	jmp	RS_Done
    ;
    ; Error in Rendering.
    ;
RS_Error:
IFDEF   DEBUG
	mov	bx,si
	mov	esi,codeOffset RendErr
	mov	edx,SHELL_Debug_Out
	call	[bx.ShellCall]
	jmp	short REContinue

RendErr db	"Grabber Got rendering error",0

REContinue:
ENDIF
        mov     dx, -1
	jmp	RS_Done

   ;
   ; No Selection exists to render
   ;
RS_NoSelection:         
        mov     dx, 0
	jmp	RS_Done
    ;
    ; Text Render
    ;
RSText:
	test	[si.SelStruc.GrabArea.SelecFlags],SelectOn
	jz	RS_NoSelection		; Done
	lea	bx,[si.PTVDRect]
	push	ax
	push	dx
	call	ComputeSelTextRect
	mov	bx,dx			; Save dimen of selection
	pop	dx
	pop	ax
	or	bh,bh			; NUL selec?
	jz	RS_NoSelection 	; Yes
	or	bl,bl			; NUL selec?
	jz	RS_NoSelection 	; Yes
	mov	bx,si
    ;
    ; get size of the render buffer 
    ;
	cCall	GetSelectionSiz,<lpPntStruc,0,wParam,lParam>   ; mono format size
	mov	cx,ax
	or	cx,dx
	jz	RS_Error
    ;
    ; Allocate memory for the render buffer
    ;
	regptr	ddSize,dx,ax
	cCall	GlobalAlloc,<GMEM_MOVEABLE+GMEM_ZEROINIT+GMEM_DDESHARE,ddSize>
	or	ax,ax
	jz	RS_Error
	mov	hMemory,ax
	cCall	GlobalLock,<ax>
	mov	es,dx
	mov	di,ax		; es:di points at save area (mem just alloced)
        or      dx, ax
	jz	RS_Error
        push    es
        push    edi
        call    GetVidSel
        pop     edi
        pop     es
        jc      RS_Error
        mov     bx, si
	lea	si,[si.SelStruc.GrabArea.Irect]
        call    RenderRectText
        pushf                           ; save return value 
        lds     si,lpPntStruc
        call    ClearVidSel
	cCall	GlobalUnLock,<hMemory>
        popf
	jc	RS_Error                ; RenderRectText failed?
        mov     ax, hMemory             ; return Memory Handle in AX
	mov     dx, CF_OEMTEXT	        ; set return value
RS_Done:
	pop	edi
	pop	esi
cEnd

;**
;
; RenderRectText - Render the indicated rectangle
;
; ENTRY:
;	DS:BX -> Extended paint structure
;       DS:SI -> Rectangle in Row/Col coords, is Text mode
;		       First word is Row,Col of upper left
;		       Second word is Row,Col of lower right
;		       Third Word is Hight,Width in chars
;	ES:DI -> Memory to place rendering in 
; EXIT:
;	If Error
;               Carry set
;	else
;	        Carry Clear
; USES:
;	ALL but ES,DS

RenderRectText proc near

    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing

    ; 
    ; BX is used to address the local variables in this procedure
    ; Set up local variables
    ;
        push    bx              ; save Old BX
        push    bx              ; space for LinWidTR
	push	[si.rcLeft]
	push	[si.rcTop]
	push	[si.rcRight]
ifdef	DBCS
	push	ds
	mov	bx, sp
	add	bx, 12
else

        mov     bx,sp
        add     bx,10          ; BX is SP on entry to this procedure
endif

OldBX           equ word ptr    ss:[bx-2]
LinWidTR        equ word ptr    ss:[bx-4]
TxTopRw         equ byte ptr    ss:[bx-5]
TxLftCol        equ byte ptr    ss:[bx-6]
TxBotRw         equ byte ptr    ss:[bx-7]
TxRgtCol        equ byte ptr    ss:[bx-8]
TxHgt	        equ byte ptr    ss:[bx-9]
TxWid	        equ byte ptr    ss:[bx-10]
ifdef	DBCS
OldDS		equ word ptr	ss:[bx-12]	
endif	; DBCS

    ;
    ; Compute parameters of rectangle
    ;
	mov	cx,80*2 		; cx is bytes per line
        mov     si,OldBX               ; si = ptr to Ext PAINTSTRUC
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],1
	ja	short GotLinWid
	shr	cx,1			; 40 col lines are half 80 col lines
GotLinWid:
	mov	LinWidTR,cx
	mov	al,TxTopRw
	mul	cl			; ax is byte index of first line
    ;
    ; Note that we ignore errors! This means we will grab "random trash"
    ;
	push	es              ; preserve es:di ptr to render buffer
	push	di
        les     edi,VidAddr
	movzx	eax,ax
	add	edi,eax		; Point to first char of first line
	mov	esi,edi
	push	es
	pop	ds
    ;
    ; Now ds:esi points to first char of first line in video memory
    ;
	pop	di
	pop	es              ; restore ptr to Render buffer
	mov	cl,TxWid
	mov	ch,TxHgt
	xor	edx,edx
	mov	dl,TxLftCol
	shl	dx,1			; edx is byte index of left char
nextlint:
	push	cx			; Save width and height
	push	esi			; Save start of line
	push	di			; Save start of line in target buffer
ifdef	DBCS
	xor	ch,ch			; CX is width
	call	AdjustDBCSRenderRect
else	; DBCS
	add	esi,edx 		; Go to left char of selection
	xor	ch,ch			; CX is width
endif
	cld
Dochr:
        lods    word ptr ds:[esi]
	or	al,al
	jz	short FixNul
NulFixed:
	stosb				; store char
	loop	short Dochr
    ;
    ; Now remove any trailing spaces from this line
    ;
	pop	ax			; This limits how much we will back up
Bkup:
	cmp	di,ax			; Check limit
	jbe	short SetLin		; Hit limit, done
	cmp	byte ptr es:[di-1]," "	; Trailing space?
	jnz	short SetLin		; No, done
	dec	di			; Remove trailing space
	jmp	short Bkup		; Look for more

    ;
    ; NUL is a valid OEM key (looks like a space), but if we stick a NUL in the
    ;	text, it terminates it. So we change NULs to SPACES.
    ;
FixNul:
	mov	al," "
	jmp	short NulFixed

SetLin:
	mov	ax,0A0DH
	stosw				; CR LF at end of line
	pop	esi			; recover start of line
	movzx	ecx,LinWidTR		; Next line
	add	esi,ecx
	pop	cx			; recover height width
	dec	ch			; One line done
	jnz	short nextlint		; More lines

	xor	ax,ax			; null terminate entire string
	stosb
	mov	si,OldBX
ifdef	DBCS
	add	sp, 12
else
        add     sp,10                  ; clean the stack - remove local vars
endif
	clc
        ret
RenderRectText  endp

ifdef	DBCS
;**
;
; AdjustDBCSRenderRect - Adjust render rect for DBCS character
;
; ENTRY:
;       DS:ESI -> Point to first char of the line
;	EDX    = Offset of left char
;	CX     = Width
; EXIT:
;	DS:ESI -> Point to left char of selection
;	CX     = Adjusted width
; USES:
;	ALL FLAGS
;
AdjustDBCSRenderRect	proc	near

    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	di
	push	dx

	mov	di,OldBX
	push	ds
	mov	ax,OldDS
	mov	ds,ax
	mov	al, [di.EPGrabDTA.CntrlSt.VDA_EGA_Mode]
	pop	ds
;Mode 0,1,2,3 and 7 are text modes
	cmp	al, 3			;
	jle	 @F			;
	cmp	al, 7
	jne	ADRX
@@:
	call	IsDBCSMiddleText	;the left bound splits a DBCS ?
	jc	short ADR0
	sub	edx,2			;yes, extend one byte on the left
	inc	cx			;and the width
ADR0:
	push	dx
	add	dx,cx
	add	dx,cx			;dx -> right bound
	call	IsDBCSMiddleText	;does it split a DBCS too?
	jc	short ADR1
	inc	cx			;yes, add the width
ADR1:
	pop	dx
ADRX:
	add	esi,edx
	pop	dx
	pop	di
	ret

AdjustDBCSRenderRect	endp

endif	;DBCS


;**
;RenderRectGrxDisplay 
;
; ENTRY:
;	DS:BX -> Extended paint structure
;       DS:SI -> Rectangle in screen coords
;		  NOTE: X coords known to be byte aligned
;			due to ScreenAdjust
; EXIT:
;       If Error
;	        Carry set
;	else
;	        Carry Clear
;	        DS:SI -> Extended Paint Structure
;	        AX = BITMAP handle
; USES:
;	ALL but ES,DS
;

RenderRectGrxDisplay proc near

	mov	ax,[si.rcLeft]
	mov	[bx.PGVDRect.rcLeft],ax
	mov	ax,[si.rcTop]
	mov	[bx.PGVDRect.rcTop],ax
	mov	ax,[si.rcRight]
	mov	[bx.PGVDRect.rcRight],ax
	mov	ax,[si.rcBottom]
	mov	[bx.PGVDRect.rcBottom],ax
	mov	si,bx
	mov	ah,[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode]
	call	GrabModeGrfx            ; build DIB
	or	ax,ax			; Worked? (clears carry too)
	jz	short RRGD_Error	; No
        clc
	ret

RRGD_Error:
	stc
	ret

RenderRectGrxDisplay endp


;=============================================================================
;
; Documentation for building DIBs in GrabModeGrfx proc:
;
; Mode 4,5 : 
;   Packed pixel format - 2 bits per pixel in the Video memory. 
;   DIBs are also packed pixel and can have 1/4/8 bits per pixel. 
;   Hence choose 4. Extend the 2 bit value to a 4 bit value.
;   Pixel doubling occurs in the Horizontal direction. Therefore 4 bits
;   in Video memory are translated into 16 bits. To speed up the translation
;   build a translation Table of 16 words. For a given 4 bit index representing 
;   2 pixels, extend each 2 bit value to a 4 bit value to get a 8 bit value. 
;   Now double each 4 bit value(pixel doubling) to get a 16 bit value. Since 
;   the bytes get reversed during a store operation reverse the bytes in the 
;   Table.
;
;   Algorithm:
;       Fetch a DWORD PQRS, from Video memory.
;       It exists in memory as SRQP. Hence process bytes in the
;       following order S,R,Q,P.
;
;       Within S(S7-S0) process high nibble first.
;
; XTableMode4:                  After Reversing the bytes 
;
; 0000 | 00000000 00000000      00000000 00000000
; 0001 | 00000000 00010001      00010001 00000000
; 0010 | 00000000 00100010      00100010 00000000
; 0011 | 00000000 00110011      00110011 00000000
;
; 0100 | 00010001 00000000      00000000 00010001
; 0101 | 00010001 00010001      00010001 00010001
; 0110 | 00010001 00100010      00100010 00010001
; 0111 | 00010001 00110011      00110011 00010001
;
; 1000 | 00100010 00000000      00000000 00100010
; 1001 | 00100010 00010001      00010001 00100010
; 1010 | 00100010 00100010      00100010 00100010
; 1011 | 00100010 00110011      00110011 00100010
;
; 1100 | 00110011 00000000      00000000 00110011
; 1101 | 00110011 00010001      00010001 00110011
; 1110 | 00110011 00100010      00100010 00110011
; 1111 | 00110011 00110011      00110011 00110011
;
;
; To build the PelColorTable, we need to fill in only the first four entries,
; 0000,0001,0010,0011. Call GetWinRGB to get the xBGR dword value.
;       
; Mode 6 :
;       1 bit per pixel, packed pixel format in the Video memory. 
;       For the DIB choose 1 bpp.
;       There is no pixel doubling in the Hor. direction. Transfer the bits
;       from the source(video memory) to the destination using REP MOVSD.
; To build the PelColorTable, we need to fill only the first two entries.
; Call GetWinRGB to get the entries.
;
; Mode 11 is similar but the format of the video memory is different.
;
;
; Modes E,10 :
;  4 bits per pixel, four bit number formed by concatenating the bits from 
; Planes 3,2,1,0. 
; 
; Mode E,10: Read a word from 
;                          Plane 3 into edx
;                          Plane 2 into ecx
;                          Plane 1 into ebx
;                          Plane 0 into eax
;
; Process the bytes PQRS in the dword Regs from right to left.
; Process the bits in the byte registers from right to left - two bits at a 
; time, the higher one first.
; After forming a 8 bit code OR it into edi and shl by 8. 
; Thus an 8 bit value gives rise to a 32 bit value to be stored in LineBits.
;
; Mode D: Read a word of info into AX,BX,CX,DX
;         Process bytes from right to left,
;         Exchange nibbles in each byte, since higher nibble has to be
;         processed before the lower nibble.
;
; Complex order of processing the bits in the above cases because of byte
; swapping on 8086.
;
;===================================================================================
public	XTableMode4

XTableMode4 label word
        dw      0000000000000000b
        dw      0001000100000000b
        dw      0010001000000000b
        dw      0011001100000000b
        
        dw      0000000000010001b
        dw      0001000100010001b
        dw      0010001000010001b
        dw      0011001100010001b
        
        dw      0000000000100010b
        dw      0001000100100010b
        dw      0010001000100010b
        dw      0011001100100010b
        
        dw      0000000000110011b
        dw      0001000100110011b
        dw      0010001000110011b
        dw      0011001100110011b


; GrabModeGrfx - Grab a selection and build a DIB
;
;    Our Strategy is as follows:
;	Construct a "screen DC" as large as the paint rectangle.
;       Create a bitmap of the size of the paint rect.        
;       Select the bitmap into the ScreenDC
;	Patblt the background color into the screen DC
;	Look at the physical display bits in the paint rectangle for PELs 
;	which are not background bits
;	When a non-background PEL is found, build the line the PEL is on
;	in local memory then SetDIBits in the bitmap
;
; ENTRY:
;	SS:BP -> Std stack frame
;	DS:SI -> EXTPAINTSTRUC structure of paint
;	AH = Mode byte from controller state
; EXIT:
; 	If (Carry Clear)
;	    Successful grab, return in AX handle to the bitmap
;	else if (Carry Set)
;	    Grab failed, probably low Windows memory problem
; USES:
;	ALL but DS,SI,BP
; NOTE:
;	This routine may set the fGrbProb bit in EPStatusFlags in the
;	Extended paint structure to indicate that this app is in a mode
;	which cannot be rendered into a Window. This routine must return with
;	Carry clear in this case.
;
GrabModeGrfx proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing

        call    InitFrameVars
	or	GrbFlags,GrbFlgs_GrfxGrabBM	; Indicate grabbing BitMap

        call    CheckMode
        jc      SetProbBit
    ;
    ; Build display paint rectangle. This is the same as the paint rect
    ;	except the edges are rounded to convenient dword aligned values
    ;
        call    BuildDisplayRect
        jz      InvalidRect         ;rect was off screen or invalid rect CoOrds

        call    AllocCommonRes
	jc	GMGError        ; alloc failed
    ;
    ; Create the full screen bitmap to the dimensions of the rounded paint rect
    ;
	push	[si.Pstruct.psHdc]
	push	DDRCWid         ; width
	push	DDRCHig         ; height
	cCall	CreateCompatibleBitmap

	or	ax,ax
	jz	GMGError	; Fail.....
	mov	bx,ax
        push    bx
        cCall   SelectObject, <ScreenDC,bx>
        pop     bx
        or      ax,ax
        jz      ReturnBitmap
	mov	ScreenBitMap,bx
    ; 
    ; Build the DIB Hdr depending on the mode
    ;
        call    BuildDIBHdr

IFDEF VGA
	cmp	Gmode,11H		; Mode 11
	jz	short DoBackPat
ENDIF
	cmp	Gmode,0DH		; Plane mode?
	jae	GMGPlaneGrx		; Yes
DoBackPat:
    ;
    ; This is one of the CGA graphics modes (4,5,6) or mode 11
    ; PatBlt the background brush into the paint rectangle to paint in 
    ; the background color
    ; PatBlt(hDC,X,Y,nWidth,nHeight,PATCOPY_H,PATCOPY_L)
    ;
	push	bx
	cCall	PatBlt, <ScreenDC,0,0,DDRCWid,DDRCHig,PATCOPY_H,PATCOPY_L>
	pop	bx

IFDEF VGA
        cmp     Gmode,11h
        je      Mode11Bits
ENDIF

GMGCGAMode:
        call    SetParamsCGAMode
GMGNextLineCGAMode:
    ;
    ; Look for non-background Bits
    ;
	push	edi                     ; push ptr to line in Vid mem
	push	cx                      ; push Line count
        call    SkipBkBits
	jz	GMGLookMoreBits		; All background bits
    ;
    ; Compute line number of line with non-background bits, and backup
    ;	index to the start of this line
    ;
	pop	ax			; Get line left count
	push	ax			; back on stack
	shl	ax,1			; Evens/odds are every other line
	test	GrbFlags,GrbFlgs_GrfxDoOdd
	jz	short EvenLine		; Even line
	dec	ax			; Odd line
EvenLine:
	shl	ax,1			; Convert physical to Bitmap
	sub	ax,DDRCHig
	neg	ax			; Line number
	push	ax			; Line # of this line
    ;
    ; Dispatch to line build code based on mode
    ;
IFDEF	GENGRAB
        test    GrbFlags,GrbFlgs_VgaMonoStatus
        jnz     GMGMode6Line
ENDIF
	mov	esi,edi 		; VidSel:esi -> 1 dword past first non-back
	cmp	Gmode,6
	jz	GMGMode6Line

IFDEF   DEBUG
public GMGMode45Line
ENDIF
GMGMode45Line:
    ;
    ; First store background color in LineBits
    ;
        call    SetupLineBits
        push    edi                    ; save start of LineBits
        xor     eax,eax                ; BkColor is 0000b
        cld
        movzx   ecx,DDPWid             ; DDPWid*32 pixels = DDPWid*32*4 bits
        shl     ecx,2                  ; = DDPWid*32*4/32 Dwords
                                       ; = DDPWid*4 Dwords 
        rep stos dword ptr es:[edi]
;******
	db	67h		       ; Problem Workaround DO NOT REMOVE
	nop
;******
        pop     edi                    ; recover start of LineBits
    ;
    ; Adjust count to skip bk bits and the current dword
    ;  NOTE: EDX -> start of line 
    ;
	movzx	ecx,DDPWid		; This many dwords in plane
	mov	ebx,edx
	sub	ebx,esi
	neg	bx			; This many bytes to 1 dword past first non-back
	shr	bx,1			; byte cnt -> word cnt
	shr	bx,1			; word cnt -> dword cnt
	sub	cx,bx			; Skip in this many
	xchg	esi,edi
        mov     es,VidSel
    ;
    ; Now es:edi -> one dword past a non Bk dword in vid mem
    ;     es:edx -> start of line
    ;     ds:esi -> LineBits
    ;
IFDEF DEBUG
        public GMGNextDword4
ENDIF
GMGNextDword4:				; Found some non-background bits
	mov	eax,dword ptr es:[edi-4]; Get the data
	add	edx,4			; Adjust start to compute index of this DWORD
	sub	edx,edi
	neg	dx			

; DX is byte index of the first non-bk dword in source buffer(w.r.t. start of
; this line)
; dx*8 is the bit index in source
; dx*8/2 is pixel index in source - 2bpp in video memory
; (dx*8*2)/2 is pixel index in destn., after pixel doubling
; dx*8*4 is bit index in destn. - 4bpp
; dx*8*4/8 is the byte index in destn.

        shl     dx,2
	add	si,dx   		; Skip Bk bits in LineBits

NonBkBits4:        
        push    bx
        push    ecx
        push    dx
        push    edi
        mov     cx,4                   ; four bytes in a dword

NextByte4:
        mov     bl,al                  ; get a byte
        xor     bh,bh                  ; clear rest of bx
        push    bx                     ; save the byte
        rol     bl,4                   ; exchange nibbles, Xlate high nibble first
        and     bl,0fh                 ; look at low 4 bits
        shl     bx,1                   ; word index into XTableMode4
        mov     di,bx                  ; move index into index reg
        mov     dx,word ptr XTableMode4[di]
        mov     [si],dx
        add     si,2

        pop     bx                     ; restore the byte
        and     bl,0fh                 ; look at low nibble
        shl     bx,1                   ; word index into XTableMode4
        mov     di,bx                  ; move index into index reg
        mov     dx,word ptr XTableMode4[di]
        mov     [si],dx
        add     si,2

        ror     eax,8                  ; shift the next byte into AL
        loop    NextByte4

        pop     edi
        pop     dx
        pop     ecx
        pop     bx

	jcxz	short LineDone

Bit4Loop4:				; More bits
        push    edi
	cld
	xor	eax,eax
	movzx	ecx, cx
	repe scas dword ptr es:[edi]	; Look for more non-backgrnd bits on this line
	pop	edx
	jz	short LineDone		; Done with line
	jmp	GMGNextDword4

GMGMode6Line:
    ;
    ; when we find a line with non bk bits, we transfer all the bits from the 
    ; video mem to the LineBits array since both the video mem and the DIB 
    ; have the same bit format of 1 bpp
    ; There is no need to first blit in the Bk color in LineBits and then process
    ; the non bk bits as in Mode 4.
    ; 
    ; now, es:edi points to start of LineBits
    ;
        call    XferMonoBits
LineDone:
	pop	ax			; Line #
	push	ss
	pop	ds
	mov	si,SavEXTP
	call	SetScreenBMBits
    ;
    ; Found some (more) non-background bits
    ;
GMGLookMoreBits:
	pop	cx                      ; recover Line count
	pop	edi			; Recover start of line
	add	edi,GrxBitWid640/8 	; Next line
	dec	cx			; One line done
	jnz	GMGNextLineCGAMode	; More lines
	bts	GrbFlags,GrbFlgs_GrfxDoOddBit
IFDEF VGA
	jc	CleanUp		        ; Odd lines done?
ELSE
	jc	short CleanUp		; Odd lines done?
ENDIF
	jmp	GMGCGAMode	        ; Do odd scans

IFDEF VGA
Mode11Bits:
        call    SetParamsmode11
LookBits11:
    ;
    ; Look for non-background Bits
    ;
	push	edi
	push	cx
        call    SkipBkBits
	jz	SHORT LookMoreBits11	; All background bits
    ;
    ; Compute line number of line with non-background bits, and backup
    ;	index to the start of this line
    ;
	pop	ax			; Get line left count
	push	ax			; back on stack
	sub	ax,DDRCHig
	neg	ax			; Line number
    
        call    XferMonoBits            ; copy bits from vid mem to Linebits
	push	ss
	pop	ds
        mov     si,SavEXTP
	call	SetScreenBMBits

LookMoreBits11:
	pop	cx
	pop	edi			; Recover start
	add	edi,GrxBitWid640/8 	; Next line
	dec	cx			; One line done
	jnz	short LookBits11	; More lines
	jmp	SHORT CleanUp		; Done

ENDIF
ReturnBitmap:
        mov     ScreenBitmap,0
        push    bx
        cCall   Deleteobject
        jmp     short GMGError
    ;
    ; Do Plane Mode screen. Modes D,E,10
    ;
IFDEF DEBUG
public GMGPlaneGrx
ENDIF
GMGPlaneGrx:
        call    SetParamsPlanarMode

NextLineDEF10:
	push	cx                      ; push # of lines still left
        call    SetupLineBits
	mov	cx,DDPWid		; Width in Dwords (words mode D)
    ;
    ; Store background color in LineBits.
    ;
        push    ecx
        push    edi
    ;
    ; Width in bytes of a color plane in LineBits=DBPWid
    ; Width in dwords of a color plane=DBPWid/4
    ; Width in dwords of 4 planes=(DBPWid/4)*4
    ;
        movzx   ecx,DBPWid              ; Width in bytes of a color plane in LineBits
        xor     eax,eax
        cld 
        rep stos dword ptr es:[edi]
;******
	db	67h			; Problem Workaround DO NOT REMOVE
	nop
;******
        pop     edi
        pop     ecx

NextDwordDEF10:
	push	cx

	cmp	Gmode,0DH
	je	short DoModeD
DoModeEF10:
        call    GetDwordDataEF10
        call    ProcessDwordE10
        jmp     short ModeEF10Continue
DoModeD:
        call    GetWordDataD
        call    ProcessWordD
ModeEF10Continue:
	pop	cx
	loop	NextDwordDEF10 		

IFDEF DEBUG
public GMGLineDoneDEF10
ENDIF
GMGLineDoneDEF10:
	movzx	eax,LineSkip
	add	VideoIndex,eax 		; Advance to next line
	pop	ax			; Get line left count
	push	ax
	cmp	Gmode,0FH
	jae	short LinCntOK
	shl	ax,1			; Convert physical to Bitmap
LinCntOK:
	sub	ax,DDRCHig
	neg	ax			; AX is Line number
	push	ss
	pop	ds
	mov	si,SavEXTP
	call	SetScreenBMBits 	; Blast the line
	pop	cx			; Line count
	loop	NextLineDEF10

	jmp	short CleanUp		; All Done

SetProbBit:
	bts	[si.EPStatusFlags],fGrbProbBit ; Tell caller we can't deal with this
InvalidRect:
        clc
        ret     

CleanUp:
        call    DeAllocAllRes
        mov     ax,ScreenBitmap
	clc
	ret
GMGError:
        call    DeAllocAllRes
        mov     ax,0
	stc
        ret

GrabModeGrfx endp

;***************************************************************************
;
; XferMonoBits - Transfer bits from Vid mem to LineBits - Mode 6,11 only
;
; ENTRY: None
;
; EXIT: Bits transferred 
;
; USES: es,edi,ds,esi
;
;
;***************************************************************************

XferMonoBits proc near

	push	ax			; Line # of this line

        call    SetupLineBits
        mov     ds,VidSel
        mov     esi,edx                 ; ds:esi -> start of line in video mem
        cld
        movzx   ecx,DDPWid              ; DDPWid*32pixels = DDPWid*32 bits
        rep movs dword ptr es:[edi], dword ptr ds:[esi] ; ds:esi = video mem, es:edi = LineBits
;******
	db	67h			; Problem Workaround DO NOT REMOVE
	nop
;******

	pop	ax			; Line #
        ret

XferMonoBits endp

;**
;
; SetScreenBMBits - Set bits in the Screen bitmap
;
; ENTRY:
;	SS:BP -> Graphics paint frame
;	DS:SI -> ExtPaintStruc
;	AX = Line # in display bitmap of line
;	LineBits on stack has the DIB
;       DIBHdr on stack is the DIB Header
;
; Alg:
;       Do SetDIBits into ScreenBM at AX and AX.1 
;       except in mode 10H,11H and 12H
;
; EXIT:
;
; USES:
;	ALL but DI,SI,BP,DS
;
SetScreenBMBits proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
        
    ;
    ; DIB is upside Line L is actually (DDRCHig-L-1)
    ;
        neg     ax
        add     ax,DDRCHig
        dec     ax

        push    ax                      ; Line #
    ; 
    ; call SetDIBits(hDC, hBM, nStartScan, nNumScans, lpBits, lpDIBHdr, wUsage)
    ; 
        push    ScreenDC                ; hDC
	push	ScreenBitmap		; hBitmap
        push    ax                      ; nStartScan
        push    1                       ; nNumScans
	push	ss			; lpBits
	lea	ax,LineBits
	test	ax,0000000000000011B	; Dword aligned?
	jz	short DwAlign21		; Yes
	inc	ax			; Go to dword align
	inc	ax
DwAlign21:
	push	ax
        push    ss                      ; DIBHdr
        lea     ax,DIBHdr
        push    ax                      
        push    0                       ; wUsage

	cmp	Gmode,10H
	je	short SSB_OnlyOne
	cmp	Gmode,0FH
	je	short SSB_OnlyOne
IFDEF VGA
	cmp	Gmode,11H
	je	short SSB_OnlyOne
	cmp	Gmode,12H
	je	short SSB_OnlyOne
ENDIF
	cCall	SetDIBits
IFDEF DEBUG
        or      ax,ax
        jnz     short SSBContinue1
        push    bx
        push    esi
        push    edx
	mov	bx,si
	mov	esi,codeOffset SetDIBErr
	mov	edx,SHELL_Debug_Out
	call	[bx.ShellCall]
        pop     edx
        pop     esi
        pop     bx
	jmp	short SSBContinue1

SetDIBErr db "SetDIBits failed",0

SSBContinue1:
ENDIF
        pop     ax                      ; Get Line # back
        push    ax

        push    ScreenDC                ; hDC
	push	ScreenBitmap		; hBitmap
        dec     ax                      ; DIB is upside down,hence dec for next line
        push    ax                      ; nStartScan
        push    1                       ; nNumScans
	push	ss			; lpBits
	lea	ax,LineBits
	test	ax,0000000000000011B	; Dword aligned?
	jz	short DwAlign22		; Yes
	inc	ax			; Go to dword align
	inc	ax
DwAlign22:
	push	ax
        push    ss                      ; DIBHdr
        lea     ax,DIBHdr
        push    ax                      
        push    0                       ; wUsage
SSB_OnlyOne:
	cCall	SetDIBits
IFDEF DEBUG
        or      ax,ax
        jnz     short SSBContinue2
        push    bx
        push    esi
        push    edx
	mov	bx,si
	mov	esi,codeOffset SetDIBErr
	mov	edx,SHELL_Debug_Out
	call	[bx.ShellCall]
        pop     edx
        pop     esi
        pop     bx
	jmp	short SSBContinue2

SSBContinue2:
ENDIF
        pop     ax                      ; Line #
	ret
SetScreenBMBits endp

;***********************************************************************************
; BuildDIBHdr - Build Device Independent Bitmap Header
; 
;       In the PelColorTable, need only 
;               4 entries for Mode 4,5 since 2 bpp
;               2 entries for Mode 6,11 since 1 bpp
;               16 entries for Mode D,E,10,12 since 4 bpp
;
;***********************************************************************************

;
; Maps Mode to # of entries in PelColorTable
; ModeToEntries[Mode] = # of entries in PelColorTable
; 
ModeToEntries label byte
        db      0,0,0,0,4,4,2,0,0
        db      0,0,0,0,16,16,0,16
        db      2,16,0

;
; Special PelColorTable for Inverse Ventura Palette
;
VenturaPCT label dword
        dd      00FFFFFFh,0h,0h,0h,0h,0h,0h,0h,0h,0h,0h,0h,0h,0h,0h,0h

; Pel Color Table for mode F DIBs
ModeFPCT label dword
        dd      0,0,0,0,0,0,0,00C0C0C0H,00808080H,0,0,0,0,0,0,00FFFFFFH

IFDEF	GENGRAB
BuildDIBHdr1Bit proc near

        push    di
        push    eax
   ;
   ; Fill PelColorTable entries
   ;
        lea     di,PelColorTable
        mov     [di.rgbRed],0
        mov     [di.rgbGreen],0
        mov     [di.rgbBlue],0
        mov     [di.rgbResvd],0
        add     di,4
        mov     [di.rgbRed],0FFh
        mov     [di.rgbGreen],0FFh
        mov     [di.rgbBlue],0FFh
        mov     [di.rgbResvd],0

        lea     di,DIBHdr
        mov     [di.biSize],40               ; 40 bytes
        movzx   eax,DDRCWid
        mov     [di.biWidth],eax             ; Width
        movzx   eax,DDRCHig
        mov     [di.biHeight],eax            ; height
        mov     [di.biPlanes],1              ; # of planes

        mov     [di.biCompression],0         ; set to 0
        mov     [di.biSizeImage],0           ; 
        mov     [di.biXPelsPerMeter],0       ; 
        mov     [di.biYPelsPerMeter],0       ; 
        mov     [di.biClrused],0             ; use all colors - default
        mov     [di.biClrImportant],0        ; 

        mov     [di.biBitCount],1            ; 1 bit per pixel

        pop     eax
        pop     di
        ret

BuildDIBHdr1Bit endp
ENDIF

BuildDIBHdr proc near

        push    eax
        push    bx
        push    cx
        push    dx
        push    di
	push	si
IFDEF	GENGRAB
        and     GrbFlags,NOT GrbFlgs_VgaMonoStatus  ;initialize.
	cCall	GetDeviceCaps,<[si.Pstruct.psHdc], PLANES>
	cmp	ax,1
	ja	short NotVgaMono	;VGA	
	cCall	GetDeviceCaps,<[si.Pstruct.psHdc], BITSPIXEL>
	cmp	ax,1
	ja	short NotVgaMono	;8514
	cmp	GMode,7
	jae	short NotVgaMono	;we want to treat this as 4 bits/pixel
        or      GrbFlags,GrbFlgs_VgaMonoStatus      ;for vgamono, mode 4=5=6.
	call	BuildDIBHdr1Bit
	jmp	BDH_Done		
NotVgaMono:
ENDIF		
        cld
	test	GrbFlags,GrbFlgs_GrfxInvPal
        jz      SHORT BDH_ProperPalette        
    ;
    ; Special PelColorTable for Inverse Ventura Palette
    ;        
        push    ss
        pop     es
        lea     di,PelColorTable
        push    cs
        pop     ds
        mov     si,codeOffset VenturaPCT
        mov     cx,16
        rep     movsd   
        push    ss
        pop     ds
        jmp     SHORT BDH_00

BDH_ProperPalette:

IFDEF	MODE13
        cmp     GMode,13h               ; Q: Mode 13 ?
        jnz     SHORT @F                ;   N: Check Mode F next
        mov     ecx,256                 ;   Y: Pull in entire VGA palette
	push	esi
	push	edi
	mov	ds,[si.RNG1DSSEL]
        mov     esi,[si.GGrbArea.VDDDACOffset]
        push    ss
        pop     es
	xor	edi,edi
        lea     di,PelColorTable
        rep     movsd
        push    ss
        pop     ds
	pop	edi
	pop	esi
        jmp     SHORT BDH_00
@@:
ENDIF

        cmp     GMode,0Fh               ; Q: Mode F ?
        jnz     SHORT BuildPCT          ;   N: Build PelColorTable
        mov     ecx,16                  ;   Y: Special PelColorTable
        push    cs
        pop     ds
        mov     si, codeOffset ModeFPCT
        push    ss
        pop     es
        lea     di,PelColorTable
        rep     movsd
        push    ss
        pop     ds
        jmp     SHORT BDH_00
BuildPCT:
   ;
   ; Fill PelColorTable entries
   ;
        xor     ax,ax                  ; color index, start with 0
        lea     di,PelColorTable
        xor     bh,bh
        mov     bl,Gmode
        xor     ch,ch
        mov     cl,ModeToEntries[bx]   ; 2/4/16 entries
BDH_Loop:
        push    ax
        call    GetWinRGB
        mov     [di.rgbRed],al
        mov     [di.rgbGreen],ah
        mov     [di.rgbBlue],dl
        mov     [di.rgbResvd],0
        add     di,4
        pop     ax
        inc     ax
        loop    BDH_Loop

BDH_00:
        lea     di,DIBHdr
        mov     [di.biSize],40               ; 40 bytes
        movzx   eax,DDRCWid
        mov     [di.biWidth],eax             ; Width
        movzx   eax,DDRCHig
        mov     [di.biHeight],eax            ; height
        mov     [di.biPlanes],1              ; # of planes

        mov     [di.biCompression],0         ; set to 0
        mov     [di.biSizeImage],0           ; 
        mov     [di.biXPelsPerMeter],0       ; 
        mov     [di.biYPelsPerMeter],0       ; 
        mov     [di.biClrused],0             ; use all colors - default
        mov     [di.biClrImportant],0        ; 

        mov     [di.biBitCount],1            ; assume mode 6 or 11
        cmp     Gmode,6
        je      short BDH_Done          ; assumption correct
        cmp     Gmode,011h
        je      short BDH_Done          ; assumption correct
        mov     [di.biBitCount],4            ; Mode 4,5,d,e,10,F
BDH_Done:  
	pop	si      
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     eax

        ret
BuildDIBHdr endp


;****************************************************************************
;
; ProcessDwordE10 - process a dword of data in Mode E and 10
;
; ENTRY: Dword of data from Planes 0,1,2,3 in edx, ecx, ebx and eax respectively
;        ES:EDI -> LineBits
;
; EXIT: Set 32*4bpp bits in LineBits, update edi
;       eax, ebx, ecx, edx destroyed
;
;****************************************************************************

ProcessDwordE10 proc near

    ; 
    ; check if all are background bits
    ;
        push    eax
        or      eax,ebx
        or      eax,ecx
        or      eax,edx
        pop     eax
        jz      short PDBkBits
        call    ProcessWordE10
    ;
    ; upper words preserved across the above call
    ;
        shr     eax,16
        shr     ebx,16
        shr     ecx,16
        shr     edx,16
        call    ProcessWordE10

        ret

PDBkBits:
    ;
    ; All background bits, skip 32*4bpp bits or 16 bytes in LineBits
    ;
        add     edi,16
        ret

ProcessDwordE10    endp

;***********************************************************************************
;
; ProcessWordE10 - process a word in mode E and 10
;
; ENTRY: word in dx, cx, bx, ax, ptr to LineBits in edi
;
; EXIT: Set 16*4bpp bits in LineBits,edi updated. 
;        ax, bx, cx and dx destroyed. 
;        upper words in eax, ebx, ecxand edx preserved.
;
;**************************************************************************************

ProcessWordE10     proc near

        push    ax
        or      ax,bx
        or      ax,cx
        or      ax,dx                   
        pop     ax
        jz      short PWBkBits          ; Background bits?

        call    ProcessByteE10
        call    ProcessByteE10
        ret

PWBkBits:
        add     edi,8                   ; skip 8 bytes in LineBits
        ret

ProcessWordE10  endp

;***************************************************************************
;
; Form4BitCode - Macro to create a 4bit code in DI - Mode D only
;                using a bit from planes 3,2,1,0
;                Plane 3,2,1,0 = I,R,G,B. AX has the MSB
;
;
;***************************************************************************

Form4BitCode    MACRO

        xor     edi,edi
        shr     ax,1                   ;ax has the MSB
        rcl     di,1
        shr     bx,1
        rcl     di,1
        shr     cx,1
        rcl     di,1
        shr     dx,1
        rcl     di,1                   ; 4 bit code in DI

        ENDM        

;***************************************************************************
;
; Form8BitCode - Macro to create a 8bit code in DI - Mode E,10 only
;
; Concatenate bits from LSB1 to form a 4 bit code. Store it as high nibble of DI
; Concatenate bits from LSB0 to form another 4 bits code. Store this
; in DI as the low nibble
;
; (Plane 3,2,1,0 = I,R,G,B. AX has the MSB)
;
;
;***************************************************************************

Form8BitCode    MACRO

        xor     edi,edi
    ;
    ; Prepare to form 4 bit code from LSB1        
    ;
        ror     ax,1                   
        ror     bx,1                   
        ror     cx,1                   
        ror     dx,1                   
    ;
    ; form 4 bit code from LSB1
    ;
        shr     ax,1                    
        rcl     di,1
        shr     bx,1                    
        rcl     di,1
        shr     cx,1                    
        rcl     di,1
        shr     dx,1                    
        rcl     di,1
    ;
    ; Prepare to form 4 bit code from LSB0
    ;
        rol     ax,2 
        rol     bx,2 
        rol     cx,2 
        rol     dx,2 

    ;
    ; LSB 0 is back in place
    ; form 4 bit code from LSB0
    ;
        shr     ax,1
        rcl     di,1
        shr     bx,1
        rcl     di,1
        shr     cx,1
        rcl     di,1
        shr     dx,1
        rcl     di,1                   ; 4 bit code in DI
    ;
    ; 8 bit code in DI
    ;
    ; now throw away LSB1
    ;
        shr     ax,1
        shr     bx,1
        shr     cx,1
        shr     dx,1

        ENDM        


                
;******************************************************************************
;
; ProcessByteE10 - Process a byte in mode E and 10
;
; Entry - Byte in dl, cl, bl, al, ptr to LineBits in es:edi
;
; Exit  - edi updated. al, bl, cl and dl destroyed and replaced with original
;         ah, bh, ch, dh. Upper words in eax, ebx, ecx and edx preserved.
;
; Algorithm:
;       Processing a byte
;       Process 2 bits at a time from right to left.
;       Within each two bits, process higher bit first.
;       Form8BitCode macro returns two 4 bit codes in DI - the code from LSB0
;       is in the high nibble of DI, code formed from LSB1 is in the low
;       nibble of DI. This weird order is because of Intel's byte swapped
;       memory.
;       
;**************************************************************************************

ProcessByteE10     proc near
        
        push    ax                      
        or      al,bl
        or      al,cl
        or      al,dl                   
        pop     ax                      ; Q: Background bits?
        jnz     short NonBkByteE        ;  N: 
        add     edi,4                   ;  Y: skip 4 bytes in LineBits
    ;
    ; may need to prepare al, bl, cl, dl for the next call.
    ; need to shift the other high byte into low byte
    ;
        mov     al,ah
        mov     bl,bh
        mov     cl,ch
        mov     dl,dh
        ret

NonBkByteE:
        push    edi                     ; push ptr to LineBits
        xor     esi,esi
        
        Form8BitCode                    ; 8 bit code in DI
        or      esi,edi                 ; mov the code into ESI
        shl     esi,8                   ; make room for the next byte

        Form8BitCode                    ; 8 bit code in DI
        or      esi,edi                 ; mov the code into ESI
        shl     esi,8                   ; make room for the next byte

        Form8BitCode                    ; 8 bit code in DI
        or      esi,edi                 ; mov the code into ESI
        shl     esi,8                   ; make room for the next byte

        Form8BitCode                    ; 8 bit code in DI
        or      esi,edi                 ; mov the code into ESI

        pop     edi                     ; get back Ptr to LineBits
        mov     dword ptr es:[di],esi   ; store the 8 four bit codes in LineBits
        add     di,4
        ret

ProcessByteE10 endp


;******************************************************************************
;
; ProcessWordD - Process a word in Mode D
;
; Entry - ax, bx, cx, dx contain a word from Planes 3,2,1,0 respectively.
;         es:edi - ptr into LineBits
; Exit  - ax, bx, cx, dx destroyed. edi updated.
;
;*****************************************************************************

ProcessWordD     proc near

        push    ax
        or      ax,bx
        or      ax,cx
        or      ax,dx                   ; Q: BackGround bits ?
        pop     ax
        jnz     short NonBkWordD        ;   N: 
        add     edi,16                  ;   Y: skip 16 bytes in LineBits.
        ret

NonBkWordD:
    ;
    ; while processing bytes in al,bl,cl,dl the upper bytes get destroyed.
    ; Therefore save it for later use.
    ;
        push    ax
        push    bx
        push    cx
        push    dx

        call    ProcessByteD
    ;
    ; restore upper bytes
    ; 
        pop     dx
        pop     cx
        pop     bx
        pop     ax

        mov     al,ah
        mov     bl,bh
        mov     cl,ch
        mov     dl,dh

        call    ProcessByteD
        ret

ProcessWordD  endp

;***************************************************************************
;
; ProcessByteD - Process a byte in al, bl, cl, dl in Mode D
;
; Entry - byte of data from Planes 0,1,2,3 in dl, cl, bl, al
;         edi = ptr to LineBits
;
; Exit  - destroys ax, bx, cx, dx. Updates edi
;
; Algorithm:
;
;     if PQ exists in the 16 bit registers process byte Q and then P
;     since in memory they exist as QP. 
;     Within a byte process higher nibble first
;     Within a nibble process bits from right to left.
;     For pixel doubling, store each four bit code twice.
;
;****************************************************************************

ProcessByteD     proc near
        
        push    ax                      ; preserve data in AL
        or      al, bl
        or      al,cl
        or      al,dl                   
        pop     ax                         
        jnz     short NonBkByteD        ; Non Background bits ?
        add     edi,8                   ; N: skip 8 bytes in LineBits
        ret

NonBkByteD:
        
        push    edi                     ; save ptr into LineBits
        xor     esi,esi

    ; 
    ; 8086 is byte swapped, exchange nibbles for processing the pixels in
    ; the right order.
    ; 
        rol     al,4
        rol     bl,4
        rol     cl,4
        rol     dl,4


        Form4BitCode                    ; get 4 bit code in DI
        or      si,di                   ; mov it into si
        shl     esi,4                   ; make room for the next nibble
        or      si,di                   ; store the same code again - pixel doubling
        shl     esi,4 


        Form4BitCode                    
        or      si,di                  
        shl     esi,4                   
        or      si,di                  
        shl     esi,4 

        Form4BitCode                    
        or      si,di                  
        shl     esi,4                   
        or      si,di                  
        shl     esi,4 

        Form4BitCode                    
        or      si,di                  
        shl     esi,4                   
        or      si,di                  

        pop     edi                     ; get ptr to LineBits
        mov     dword ptr es:[di],esi   ; store the 8 four bit codes in LineBits
        add     di,4

        push    edi                     ; save ptr into LineBits
        xor     esi,esi

        Form4BitCode                    
        or      si,di                  
        shl     esi,4                   
        or      si,di                  
        shl     esi,4 

        Form4BitCode                    
        or      si,di                  
        shl     esi,4                   
        or      si,di                  
        shl     esi,4 

        Form4BitCode                    
        or      si,di                  
        shl     esi,4                   
        or      si,di                  
        shl     esi,4 

        Form4BitCode                    
        or      si,di                  
        shl     esi,4                   
        or      si,di                  
        
        pop     edi             ; get ptr to LineBits
        mov     dword ptr es:[di],esi     ; store the 8 four bit codes in LineBits
        add     di,4
        ret

ProcessByteD endp


; RenderRectGrxMono - Render the rectangle for graphics mode in monochrome
;                     bitmap format.
;
; ENTRY:
;	DS:BX -> Extended paint structure
;       DS:SI -> Rectangle in screen coords, is graphics mode
;		  NOTE: X coords known to be byte aligned
;			due to ScreenAdjust
;		  NOTE: The bits are rendered in INVERSE format (black
;			on white) as this is more like Windows format
;			than normal which is white on black.
;	ES:DI -> Memory to create the monochrome bitmap
;
; EXIT: If Error
;              Carry Set 
;       else
;              Carry Clear 
;              ax - handle

RenderRectGrxMono proc near

%OUT RenderRectGrxMono not functional!
        stc
        ret

IF 0


	push	bx			; ExtPSav
	push	[si.rcLeft]
	push	[si.rcTop]
	push	[si.rcRight]
	push	[si.rcBottom]
	sub	sp,6			; room for GBGWid and GBGHig and GBGSkip

    ;
    ; BX is used to access local variables.
    ;
        mov     bx,sp
        add     bx,16                   ; BX is SP on entry to this procedure

ExtPSav equ	word ptr ss:[bx-2]
GRLft	equ	word ptr ss:[bx-4]
GRTop	equ	word ptr ss:[bx-6]
GRRgt	equ	word ptr ss:[bx-8]
GRBot	equ	word ptr ss:[bx-10]
GBGWid	equ	word ptr ss:[bx-12]
GBGHig	equ	word ptr ss:[bx-14]
GBGSkip equ	word ptr ss:[bx-16]

;
; FOR CGA MODES (4,5,6)
;   Since the area to render is of arbitrary height which we don't want to
;   round, we have to deal with all sorts of cases:
;
;	First scan is ODD
;	    Height is even
;		Have same number of evens and odds
;	    Height is odd
;		Have one more odd than even
;	First scan is EVEN
;	    Height is even
;		Have same number of evens and odds
;	    Height is odd
;		Have one more even than odd
;

        push    di
	mov	ax,GRRgt
	sub	ax,GRLft
        mov     si,ExtPSav
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],0DH
	jne	short NtMD1
DoDv10:
	shr	ax,1			; Convert to display
NtMD1:
	mov	cx,ax			; Save width in cx
	shr	cx,3			; / by 8 is width in bytes
	inc	cx			; Make CX even, Note this may cause
	and	cx,1111111111111110B	;   an extra byte which is NOT part
					;   of the width to be stored. We must
					;   do this because windows requires
					;   bitmaps to be an even number of
					;   bytes wide. What is in these extra
					;   bits doesn't matter.
	mov	ax,GRBot
	sub	ax,GRTop
IFDEF VGA
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],11H
	je	short NtM101
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],12H
	je	short NtM101
ENDIF
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],10H
	je	short NtM101
	shr	ax,1			; Convert to display
NtM101:
	mov	dx,ax			; Save height in dx
;
;  DX = Height of rectangle in scan lines
;  CX = Width of rectangle in BYTES
;  GRLft,GRTop,GRRgt,GRBot form rectangle
;  ES:(TOS) -> Grab Structure to place grab in
;  DS:si -> ExtPaintstruct (si saved at ExtPSav)
;
	mov	GBGWid,cx               ; save width and height
	mov	GBGHig,dx

	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],0DH
	jae	PlaneGrb
CGAGrb:
    ;
    ; GRAB a CGA Mode interlaced graphics screen
    ;
	mov	ax,GRTop
	shr	ax,1			; Convert to display
	test	ax,0000000000000001B
	jz	short StrtEvn
	or	GrbFlags,GrbFlgs_GrfxDoOdd + GrbFlgs_StrOdd  ; Odds first
StrtEvn:
	shr	dx,1
	jnc	short NextScans 	; Even Height
    ;
    ; Height is odd, have an extra even or odd line
    ;
	test	GrbFlags,GrbFlgs_StrOdd
	jz	short ExtEv
	or	GrbFlags,GrbFlgs_ExtrOdd
	jmp	short NextScans

ExtEv:
	or	GrbFlags,GrbFlgs_ExtrEvn

NextScans:
	mov	ax,GRTop
	shr	ax,2			; Convert to display and /2 for even/odd is half of display
	test	GrbFlags,GrbFlgs_StrOdd
	jz	short SkipIn		; Did evens first
	test	GrbFlags,GrbFlgs_GrfxDoOdd  ; Doing odds
	jnz	short SkipIn		; Yes, doing odds and am start odd
	inc	ax			; Am doing evens on start odd, one more
SkipIn:
	push	dx
        push    bx
	mov	bx,GrxBitWid640/8	; Bytes per line
	mul	bx			; ax is byte index to first line
        pop     bx
	push	es
	xor	edx,edx 		; Assume doing evens, pages 0 1
	test	GrbFlags,GrbFlgs_GrfxDoOdd
	jz	short GetpgB		; Assumption correct
	mov	edx,2 * 4096		; Doing odds, pages 2 and 3
GetpgB:
	mov	si,ExtPSav
    ;
    ; Note that we ignore errors! This means we will grab "random trash"
    ;
	call	GetVidSel		; Set up
	movzx	eax,ax
	add	eax,edi
	add	eax,edx 		; Point to first char of first line
	mov	esi,eax
	push	es
	pop	ds
	pop	es
	pop	dx

	push	di
    ; ds:esi - Video memory
    ; es:di - Render Buffer
    ; dx    - height in scan lines

	test	GrbFlags,GrbFlgs_SecScns ; Doing second set of scan lines?
	jz	short Fscan		; No
	add	di,cx			; Skip in one scan line for second set
Fscan:
	push	dx
	test	GrbFlags,GrbFlgs_GrfxDoOdd  ; Doing odds?
	jz	short ChkEE		; no
	test	GrbFlags,GrbFlgs_ExtrOdd ; Have an extra odd?
	jz	short gbg5		; No count is correct
	jmp	short gbg5A		; Increase count by one

ChkEE:
	test	GrbFlags,GrbFlgs_ExtrEvn ; Have an extra even?
	jz	short gbg5		; No, count is correct
gbg5A:
	inc	dx
gbg5:
	or	dx,dx			; Any lines?
	jz	short gbg2		; No, done
    ;
    ; Next line
    ;
        push    bx
	mov	bx,GRLft
	shr	bx,3			; bx is byte index to left edge
	movzx	ebx,bx
gbg0:
	push	esi
	add	esi,ebx 		; Index left edge
	push	cx
	cld
Cloop:
	lods byte ptr ds:[esi]		; Bits
	not	al			; Not bits for windows
	stosb				; Stored
	loop	Cloop
	pop	cx
	pop	esi			; Back up to start of line
        pop     bx
	add	esi,GrxBitWid640/8 	; Next even/odd line on source
	add	di,cx			; Skip dest line since we do every other
	dec	dx			; One line done
	jnz	short gbg0		; More lines
gbg2:
	push	ss
	pop	ds
	mov	si,ExtPSav
	btc	GrbFlags,GrbFlgs_GrfxDoOddBit	; Next set is other type
	bts	GrbFlags,GrbFlgs_SecScnsBit ; Already done second scan set?
	pop	dx
	jnc	NextScans		; No, do second scan set
	call	ClearVidSel
    ;
    ; We now want to point to the end of the bitmap. If there was an extra
    ;	even or odd scan we need to skip ahead one line from where we are now.
    ;
	test	GrbFlags,GrbFlgs_ExtrEvn + GrbFlgs_ExtrOdd
	jz	short FinishGrxGrb
	add	di,cx			; Adjust DI to end of map
FinishGrxGrb:
        pop     di
    ;
    ; cCall CreateBitmap(width, height, nPlanes, nBitsPerPixel,lpBits)
    ;
        push    es
        cCall   CreateBitmap, <GBGWid,GBGHig,1,1,0,0>
        pop	es
        or	ax,ax			; Q: Created Bitmap?
        jz	short RRGM_Error	; No
        push    ax              ; save handle to bitmap
    ;
    ; Set up DIBHdr
    ;
%OUT Set up DIB Header here
;        mov     biSize,12
;        mov     ax,GBGWid
;        mov     biWidth,ax
;        mov     ax,GBGHig
;        mov     biHeight,ax
;        mov     biPlanes,1
;        mov     biBitCount,1
;        push    es
;        push    di
;        push    ss
;        pop     es
;        lea     di,PelColorTable
;        mov     [di.rgbRed],0           ; First entry <0,0,0>
;        mov     [di.rgbBlue],0
;        mov     [di.rgbGreen],0
;        add     di,3                    ; next PelColorTable entry
;        mov     [di.rgbRed],0ffh
;        mov     [di.rgbBlue],0ffh
;        mov     [di.rgbGreen],0ffh
;        pop     di
;        pop     es

        pop     ax                      ; get bitmap handle
    ;
    ; cCall SetDIBits(hDC, hBM, nStartScan, nNumScans, lpBits, lpDIBHdr, wUsage)
    ;
        regptr lpRenderBuffer,es,di
        push    ax
        lea     ax,DIBHdr
        regptr lpDIBHdr,ss,ax
        pop     ax
	cCall SetDIBits,<[si.Pstruct.psHdc],ax,0,GBGHig,lpRenderBuffer,lpDIBHdr,0>
    ;
    ; check for error
    ;
        add     sp,16           ; clean locals from stack
	clc
	ret
RRGM_Error:
        add     sp,16           ; clean locals from stack
        stc
        ret

;
;  GBGHig = DX = Height of rectangle in scan lines
;  GBGWid = CX = Width of rectangle in BYTES
;  GRLft,GRTop,GRRgt,GRBot form rectangle
;  ES:(TOS) -> Grab Structure to place grab in
;  DS:BX -> ExtPaintstruct (BX saved at ExtPSav)
;
;  GRAB an EGA Hi-Res screen. This we do in Plane mode. We combine the
;    bits of each of the 4 planes to get monochrome and NOT it so that
;    White on Black comes out Black on White (more like Windows).
;
;  For VGA, mode 11 is a special case, Mode 13 is not handled
;
PlaneGrb:
	mov	ax,GRTop
IFDEF VGA
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],11H
	je	short NoConv3
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],12H
	je	short NoConv3
ENDIF
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],10H
	je	short NoConv3
	shr	ax,1			; Convert to display
NoConv3:
	mov	cx,GrxBitWid640/8	; Bytes per line
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],0DH
	jne	short NoConv4
	shr	cx,1			; Mode D screen is half as wide
NoConv4:
	mov	GBGSkip,cx		; Save this
	mul	cx			; ax is byte index to first line
	mov	cx,GRLft
	shr	cx,3			; cx is byte index to left edge
NoConv8:
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],0DH
	jne	short NotMDDx
	shr	cx,1			; Mode 0D is half as wide
NotMDDx:
IFDEF VGA
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],11H
	je	SHORT Grab11
ENDIF
	push	es
	add	ax,cx			; AX is Index to first byte
	mov	si,ExtPSav
    ;
    ; Note that we ignore errors! This means we will grab "random trash"
    ;
	call	GetVidSel		; Set up
	movzx	eax,ax
	add	eax,edi 		; Point to first char of first line
	mov	esi,eax
	push	es
	pop	ds
	pop	es			; ES:DI -> GRAB
	pop	di
	push	di
	mov	ax,GBGWid		; Width to grab
	sub	GBGSkip,ax		; Skip this many bytes to get to next line
RRGM_NextLine:
	mov	cx,GBGWid		; Width to grab
NextLine2:
	push	cx
;
; This is the Color to mono mapping implemented here.
;
;  Palette information is ignored, Std palette assumed
;	 Plane 0 = Blue
;	 Plane 1 = Green
;	 Plane 2 = Red
;	 Plane 3 = Ignored, Intensity
;
;
;		 PPPP
;		 llll
;		 aaaa
;		 nnnn
;		 eeee
;		 3210
;
;		 0000 -> 1
;		 0001 -> 1
;		 0010 -> 1
;		 0011 -> 1
;		 0100 -> 1
;		 0101 -> 1
;		 0110 -> 1
;		 0111 -> 0
;		 1000 -> 1
;		 1001 -> 1
;		 1010 -> 1
;		 1011 -> 1
;		 1100 -> 1
;		 1101 -> 1
;		 1110 -> 1
;		 1111 -> 0
;
	cld
	lods byte ptr ds:[esi]
	mov	ah,byte ptr [esi+(32768*1)-1] ; plane 1 bits in ah
	mov	bl,byte ptr [esi+(32768*2)-1] ; plane 2 bits in bl
;	 mov	 rr,byte ptr [esi+(32768*3)-1] ; plane 3 bits IGNORED

	mov	dl,00000001B		; Useful masks
	mov	dh,11111110B
	mov	bh,al			; plane 0 bits in bh
	mov	al,0FFH 		; Most values are set bits
	mov	cx,8			; 8 bits in byte
BitLoop:
    ;
    ; For pixel to be 0, all three planes must be "on"
    ;
	test	bh,dl
	jz	short NoChng
	test	bl,dl
	jz	short NoChng
	test	ah,dl
	jz	short NoChng
	and	al,dh			; Turn off pixel
NoChng:
	ror	al,1			; Next bit
	ror	ah,1
	ror	bl,1
	ror	bh,1
	loop	BitLoop
	stosb				; "GRAB" it
	pop	cx
	loop	NextLine2
LinDng:
	movzx	edx,GBGSkip
	add	esi,edx 		; Index next line
	dec	GBGHig			; Line completed
	jnz	RRGM_NextLine		; More lines
	mov	si,ExtPSav
	push	ss
	pop	ds
	push	es
	push	di
	call	ClearVidSel		; Clear
	pop	di
	pop	es
	jmp	FinishGrxGrb		; All done


IFDEF VGA
Grab11:
	push	es
	add	ax,cx			; AX is Index to first byte
	mov	si,ExtPSav
    ;
    ; Note that we ignore errors! This means we will grab "random trash"
    ;
	call	GetVidSel		; Set up
	movzx	eax,ax
	add	eax,edi 		; Point to first char of first line
	mov	esi,eax
	push	es
	pop	ds
	pop	es			; ES:DI -> GRAB
	pop	di
	push	di
	mov	ax,GBGWid		; Width to grab
	sub	GBGSkip,ax		; Skip this many bytes to get to next line
NextLine11:
	mov	cx,GBGWid		; Width to grab
DoLin11:
	cld
	lods byte ptr ds:[esi]		; Get bits
	not	al			; Invert for Windows
	stosb				; "GRAB" it
	loop	DoLin11
	movzx	edx,GBGSkip
	add	esi,edx 		; Index next line
	dec	GBGHig			; Line completed
	jnz	NextLine11		; More lines
	mov	si,ExtPSav
	push	ss
	pop	ds
	push	es
	push	di
	call	ClearVidSel		; Clear map
	pop	di
	pop	es
	jmp	FinishGrxGrb		; All done
ENDIF

ENDIF                   ; ENDIF for IF 0

RenderRectGrxMono endp


sEnd	code
        end
