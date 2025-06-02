;-----------------------------------------------------------------------------
;
;   Screen Grabber for IBM EGA/VGA adaptor
;
;   Main routines to perform paints.
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
externFP	DestroyCaret
externFP	SetCaretPos
externFP	SelectObject
externFP	PatBlt
externFP	GetUpdateRect
externFP	InvertRect
externFP	ScrollWindow
externFP	UpdateWindow


;-----------------------------------------------------------------------------
;
; External GRABBER Procedures
;
externNP	CursorPos
externNP	CheckCtrlState
externNP	MakeNewCursor
externNP	BuildTextRects
externNP	ModeText
externNP	ModeGrfx
externNP	GetVidSel
externNP	ClearVidSel
externNP	ClearWinMemState


sBegin	code
	assumes cs,code

 	public	PrepPnt
        public  PaintClientRect
        public  SavePaintRect
        public  GetPageBitmap

;*****************************************************************************
;
; Notes on the locking/Unlocking of APPS of during Painting/updating/selecting
; from an OLDAPP screen.
;
;   The VDD/GRABBER/WINOLDAP interfaces for handling screen painting(due to a
;   WM_PAINT msg), updating(APP modifies the video state/memory) and selecting 
;   from an OLDAPP window is very messy and can be cleaned up. The following is
;   an attempt to explain how it works currently.
;   
;   GetDisplayUpd - Locks the APP if not already locked. Does not maintain 
;   any lock count and hence multiple calls are harmless. Typically WINOLDAP 
;   calls this and the grabber calls this again in UpdateScreen to get modfs
;   to the APP window.
;
;   GrbUnLockApp - Unlocks the APP only if Lock count is zero.
;   No lock count maintained.
;   
;   Get_Mem and Free_Mem - Maintain a lock count and they lock/unlock APP if 
;   it is isn't already locked/unlocked. For every Get_mem there should be 
;   a Free_mem. They get/free main memory and not the copy mem maintained by 
;   the VDD.
;
;   PaintScreen:
;     GetVidSel - Locks the APP (main mem Sel returned not used in text modes)
;     Paints the screen.
;     ClearVidSel - Unlocks the APP and frees the main mem sel).
;
;   Note: WINOLDAP has already made a GetDisplayUpd call before calling
;	  PaintScreen.
;
;  UpdateScreen:
;    GetVidSel - Lock the APP and get main mem Sel
;    GetDisplayUpd - returns modfs to window (no locking occurs now)
;    Paint the screen using the modfs
;    Clear the Modfs - transfers main mem to copy mem
;    ClearVidSel - Unlocks the APP
;
;   Note: WINOLDAP could have already made a GetDisplayUpd call which would 
;         have locked the APP. This does not hurt us. In this case we will 
;         just increment lock count during Get_Mem.
;         All updates are done using the main mem and not the copy mem.
;         The modfs are explicitly cleared resulting in main mem being transferred
;         to copy mem.
;         The APP has to be locked during this call.
;  
;  Selection:
;  Selections in a window are done using the main memory and the APP is locked
;  during the selection and rendering. ALT+PRNTSCRNS for a FS VM are done using
;  the copy mem. ALT+PRNTSCRNs in windowed VMs is passed to windows.
;
;
;  Qs 1. Lock/Unlock necessary during a PaintScreen?
;     2. No need to get main mem selector during PaintScreen.
;     3. Can we have a cleaner interface by separating Lock/Unlock,Get_mem,
;        GetDisplayUpds?
;
;   Sometimes the grabber may make a Get_Mod call on behalf of VMDOSAPP
;   and this may not be followed by a Get_Mem call at all(no painting
;   occurs). But it will make the explicit unlock call for the OLD APP
;   from the grabber and this is what gets the APP going again.
;   On a scroll update event from the VDD, grabber calls windows to do the 
;   scrolling(essentially scrolling the copy mem) and the resulting WM_PAINT
;   msg to paint the exposed lines should be done using the main memory and
;   not the copy mem. Thus the Clear_Modf call which follows the ScrollWin call
;   should occur before the UpdateWindow call which sends the Paint msg.
;   The ClearModf also prevents the VDD from returning any more modfs; if this
;   was not the case WINOLDAP would see more updates and will repaint the screen
;   making our scrolling effort a waste. (Makes sense ??)
;
;   The Lock count to match Get_Mem/Free_Mem calls is necessary since the
;   grabber paint code may be reentered in the middle of a window update.
;   The APP should not be unlocked when the reentered painting is over.
;
;*****************************************************************************


;*****************************************************************************
;
; PaintScreen - Paint the indicated region of the screen
;
;     This routine Paints the old app screen into a window
;     Origin of this is a WINDOWS paint as opposed to a display
;     update (handled in UpdateScreen)
;
; ENTRY:
;	lpPntStruc Extended paint structure
; EXIT:
;	AX != 0
;	    Screen Painted
;	AX == 0
;	    Screen not painted, probably low Windows memory problem
; USES:
;	C Standard
; NOTE:
;	This routine may set the fGrbProb bit in EPStatusFlags in the
;	Extended paint structure to indicate that this app is in a mode
;	which cannot be rendered into a Window. This routine must return
;	AX != 0 in this case.
;
;*****************************************************************************
cProc  PaintScreen,<FAR,PUBLIC>

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

	call	GetVidSel	    ; FREEZE the app
	jc	SHORT PS_Error		  ; paint screen black if error

    ;
    ; Check to see if the screen is off
    ;
	test	[si.EPGrabDTA.CntrlSt.VDA_EGA_Flags],fVDA_V_ScOff
	jnz	SHORT NulScreen
	mov	ah,[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode]
	cmp	ah,7
	je	SHORT PSText		; 0 1 2 3 7 are text
	cmp	ah,4
	jae	SHORT PSGraphics
PSText:

    ;
    ; Clear the area to be painted in the WinMemState, forcing paint to occur
    ;

	call	ClearWinMemState
	call	ModeText
	pushf				; Save returned CF
    ;
    ; If we have the focus, we'll do the cursor
    ;
	bt	[si.EPStatusFlags],fFocusBit
	jnc	short PS_NoCursor		; Don't have focus, no cursor
	bt	[si.EPStatusFlags],fSelectBit
	jc	short PS_NoCursor		; In Select mode, don't do cursor
	call	CursorPos
	inc	dx
	jz	short PS_NoCursor	; No cursor
	dec	dx
	sub	ax,[si.ColOrg]		; Org X onto display
	sub	dx,[si.RowOrg]		; Org Y onto display
	cCall	SetCaretPos,<ax,dx>     ; Position Cursor
PS_NoCursor:
	popf				; Recover carry setting
	jmp	short PS_SetAX


PSGraphics:
IFDEF VGA
        cmp     ah,13h
        je      short PS_Error
ENDIF
IFDEF SAVEMEM
	; we don't attempt to render modes for which VDDVBE can't use savemem
	cmp	ah,0Dh
	jb	short @F
	cmp	ah,12h
	jbe	short PS_Error
@@:
ENDIF
	call	ModeGrfx		
	jmp	short PS_SetAX          ;no cursor in graphics mode!

PS_Error:
	bts	[si.EPStatusFlags],fGrbProbBit ; cannot render

;;      call    PaintWindowBlack        ; Paint with the Black Brush
;;	stc
;;      jmp     short PS_SetAX

NulScreen:
        call    PaintWindowBlack        ; Paint with the Black Brush
PS_SkipPaint:
	clc
PS_SetAX:
	mov	ax,0			; DO NOT XOR!!!!!!!!
	jc	short PS_Done
	inc	ax
PS_Done:
	push	ax
ifdef	Compatible
	or	ax,ax			; error ?
	jnz	short NoPaintWindowBlack
	call	PaintWindowBlack	; Paint with the Black Brush
NoPaintWindowBlack:
endif
	call	ClearVidSel
	pop	ax

	pop	edi
	pop	esi
cEnd

;*****************************************************************************
;
; PaintWindowBlack - Paint client area with the Black brush
;
; ENTRY: DS:SI -> EXTPAINTSTRUC
;
; EXIT: NONE
; 
; USES: 
;
;*****************************************************************************

PUBLIC PaintWindowBlack

PaintWindowBlack proc

        push    di

	cCall	SelectObject,<[si.Pstruct.psHdc],[si.BlkBrshH]>
        
	lea	di,[si.Pstruct.PSrcPaint]
	mov	ax,[di.rcRight]
	sub	ax,[di.rcLeft]
	mov	dx,[di.rcBottom]
	sub	dx,[di.rcTop]
	cCall	PatBlt,<[si.Pstruct.psHdc],[di.rcLeft],[di.rcTop],ax,dx,PATCOPY_H,PATCOPY_L>

        pop     di
        ret

PaintWindowBlack endp


;*****************************************************************************
;
; GetDisplayUpd - Call the VDD to get a display update
;
;     This routine gets the update (if any) and stores it in the Paint struct
;
;     NOTE: This call "locks" the app (prevents furthur changes from occuring).
;	    The app starts again via:
;
;	    o Call to UpdateScreen
;
;	    o Call to PaintScreen
;
;	    o Call to GrbUnlockApp
;
; ENTRY:
;	lpPntStruc Extended paint structure
;	wParam = parameter from VDD message (= -1 if VMDOSAPP origin)
;	lParam = parameter from VDD message (= 0  if VMDOSAPP origin) Event ID
; EXIT:
;	AX = Display update flags (see grabpnt.inc for fDisp_ flags
; USES:
;	C Standard
;
;*****************************************************************************
cProc  GetDisplayUpd,<FAR,PUBLIC>

	ParmD	lpPntStruc
	ParmW	wParam
	ParmD	lParam

	localV	FrameVars,StdGrbFrameSz
cBegin
	push	esi
	push	edi

	InitBasicFrame
    ;
    ; NOTE THAT THIS ROUTINE MUST NOT CALL ClearVidSel. This will open a
    ;	race window in the call from UpdateScreen.
    ;
	lds	si,lpPntStruc

	push	ds
	pop	es

	mov	ax,GRB_Get_Mod
	mov	ebx,[si.ThisVMHand]
        mov     cx,VDD_MOD_MAX                  ; Size of DispMod structure
	lea	di,[si.EPGrabDTA.DispMod]
	movzx	edi,di
	push	ebx
        call    [si.GGrbArea.VddApiProcAdr]
	or	cx,cx
	jz	SHORT RetHere			; no mods!!!
	cmp     [si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],7
	je	SHORT GDU_Text_Mode
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],3
	ja	SHORT RetHere			; no fixes...
GDU_Text_Mode:
	shl	ebx,8
	movzx	bx,bh
	mov	[di.Vdd_Mod_List.rcRight],bx	; !OPT
	shr	ebx,8
	movzx	bx,bh
	mov	[di.Vdd_Mod_List.rcBottom],bx	; !OPT
	mov	bx,ax
	shl	ebx,8
	movzx	bx,bh
	mov	[di.Vdd_Mod_List.rcLeft],bx
	shr	ebx,8
	movzx	bx,bh
	mov	[di.Vdd_Mod_List.rcTop],bx
RetHere:
	pop	ebx
	btr	[si.GGrbArea.GrbStatusFlags],BlinkTurnedOffBit
	test	dx,01000b
	jnz	SHORT BlinkOn
	or	[si.GGrbArea.GrbStatusFlags],BlinkTurnedOff
BlinkOn:
IFDEF   DEBUG
        or      cx,cx
	jnz	short GDUContinue2
	push	si
	push	bx
	push	dx
	mov	bx,si
	mov	esi,codeOffset GetModErr
	mov	edx,SHELL_Debug_Out
	call	[bx.ShellCall]
	jmp	short GDUContinue1

GetModErr db	  "Grabber Got error trying to get mods",0

GDUContinue1:
	pop	dx
	pop	bx
	pop	si
GDUContinue2:
ENDIF
	mov	ax,[di.VDD_Mod_Flag]
	test	ax,fVDD_M_Err
	jnz	short NoCtrlChng
	test	ax,fVDD_M_Ctlr+fVDD_M_Curs
	jz	short NoCtrlChng
	btr	[si.EPStatusFlags],fVValidBit
	call	CheckCtrlState
NoCtrlChng:
	and	ax,fDisp_Ctlr+fDisp_VRAM+fDisp_Curs

.erre	fVDD_M_Ctlr	    EQ	 fDisp_Ctlr
.erre	fVDD_M_VRAM	    EQ	 fDisp_VRAM
.erre	fVDD_M_Curs	    EQ	 fDisp_Curs

	test	[si.EPGrabDTA.CntrlSt.VDA_EGA_Flags],fVDA_V_HCurTrk
	jz	short NoHTrk
	or	ax,fDisp_HCurTrack
NoHTrk:
	pop	edi
	pop	esi
cEnd

;*****************************************************************************
;
; UpdateScreen - Update changed portions of screen indicated
;
;   NOTE: We know SetPaintFnt has been called
;
; ENTRY:
;	lpPntStruc Extended paint structure
;	wParam = parameter from VDD message
;	lParam = parameter from VDD message EVENT ID
; EXIT:
;	AX == 1
;	    Screen Painted
;	AX == 0
;	    Screen not painted, probably low Windows memory problem
; USES:
;	C Standard
; NOTE:
;	This routine may set the fGrbProb bit in EPStatusFlags in the
;	Extended paint structure to indicate that this app is in a mode
;	which cannot be rendered into a Window. This routine must return with
;	AX == 1 in this case.
;
; Alg:
;	call	GetVidSel - get video save memory from VDD
;       call    GetDisplayUpd   - get latest controller state
;       
;       if (Change in controller state)
;	    paint whole client area and do cursor
;       else if (no video Ram change)
;	    do cursor
;       else    {    /* video ram change */
;	    if (page bitmap and Grx mode)
;		convert to Rects and paint each
;	    else if (page bitmap and Text mode) {
;		While (More changes) {
;		    form a change rect
;		    if (Scroll of change rect)
;			Textscroll
;			convert rect to display co-ords
;			continue;
;		    convert rect to display co-ords
;		    PrepPnt
;		    ModeText
;		    }
;		do cursor;
;		}
;	    }
;*****************************************************************************

cProc  UpdateScreen,<FAR,PUBLIC>

	ParmD	lpPntStruc
	ParmW	wParam
	ParmD	lParam

	localV	FrameVars,StdGrbFrameSz
	LocalW	RecBottom
	LocalW	RecRight
	LocalW	RecTop
	LocalW	RecLeft
	LocalV	UpdateRect,(4*2)
cBegin
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
	push	esi
	push	edi

	InitBasicFrame

	lds	si,lpPntStruc
	call	GetVidSel		; Get the memory and FREEZE the app
        jc      US_Error                ; failed to get video mem
	test	[si.EPGrabDTA.DispMod.VDD_Mod_Flag],fVDD_M_Err
	jnz	US_Error
IFDEF VGA
	cmp     [si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],13h
        je      US_Error
ENDIF
IFDEF SAVEMEM
	; we don't attempt to render modes for which VDDVBE can't use savemem
	mov	ah,[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode]
	cmp	ah,0Dh
	jb	short @F
	cmp	ah,12h
	jbe	US_Error
@@:
ENDIF
	test	[si.EPGrabDTA.DispMod.VDD_Mod_Flag],fVDD_M_Ctlr
	jz	short DoUpdates 	; Controller state is unchanged

    ;
    ; Controller state has changed, paint whole client area. 
    ; Paint rect is set to whole client area, so we're ready to paint
    ;
        call    PaintClientRect
	jmp	JustCursor		; Check on cursor

    ; 
    ; Controller state is unchanged but video RAM might have changed
    ; 
DoUpdates:
	test	[si.EPGrabDTA.DispMod.VDD_Mod_Flag],fVDD_M_VRAM
	jz	JustCursor		; Just Cursor change, carry clear if jmp

    ;
    ; Given a page bitmap of the modified pages for the video memory,
    ; convert it to rectangles on screen and paint it.
    ;
IFDEF DEBUG
	mov	ax,[si.EPGrabDTA.DispMod.VDD_Mod_Flag]
	and	ax,fVDD_M_Type
	cmp	ax,fVDD_M_Type_Page
	jz	short NoStallBM
	push	si
	push	bx
	push	dx
	mov	bx,si
	mov	esi,codeOffset PageErr
	mov	edx,SHELL_Debug_Out
	call	[bx.ShellCall]
	jmp	short USContinue1

PageErr db	"Grabber expecting fVDD_M_Type_Page got AX",0

USContinue1:
	pop	dx
	pop	bx
	pop	si
NoStallBM:
ENDIF
        call    SavePaintRect           ; Save the client rect on the stack

	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],3
IFDEF DEBUG
	jbe	DoText
ELSE
	jbe	short DoText
ENDIF
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],7
IFDEF DEBUG
	je	DoText
ELSE
	je	short DoText
ENDIF
	mov	cx,[si.EPGrabDTA.DispMod.VDD_Mod_Count]
IFDEF DEBUG
	or	cx,cx
	jnz	short NoStallRCTA
	push	si
	push	bx
	push	dx
	mov	bx,si
	mov	esi,codeOffset CountErr
	mov	edx,SHELL_Debug_Out
	call	[bx.ShellCall]
	jmp	short USContinue2

CountErr db	 "Grabber mod count = 0 Page type",0

USContinue2:
	pop	dx
	pop	bx
	pop	si
NoStallRCTA:
ENDIF
	or	cx,cx
	jz	JustCursor	; Hmmm.... Bit lied, carry clear if jmp

        mov     bx,si           
    ;
    ; get page bitmap in AX, LinesTable ptr in SI
    ;
        call    GetPageBitmap
    ; 
    ; Scan the PageBitmap for 1s
    ; 
NextPageBit:
        or      ax, ax          ; All pages done?
        jz      short PageBitsDone    ; Yes, Carry clear if jmp
        shr     ax, 1
        jnc     short NextTableEntry
    ;
    ; Setup update rect on the stack in "screen CoOrds" - client area CoOrds
    ; corrected for scroll bar. 
    ;
        lea     di,UpdateRect
        push    ax                      ; save PageBitmap
        mov     ax,[bx.ColOrg]
	mov	[di.rcLeft],ax
	add	ax,[bx.Pstruct.PSrcPaint.rcRight]
	mov	[di.rcRight],ax
        mov     ax,cs:[si.StartLine]
	mov	[di.rcTop],ax
        mov     ax,cs:[si.EndLine]
	mov	[di.rcBottom],ax

        add     si,4                    ; Next entry in the LinesTable

        push    si
        push    bx
        lds     si,lpPntStruc           ; restore DS
    ; 
    ; set up EXTPAINTSTRUC for painting the UpdateRect
    ; 
        call    PrepPnt
        pop     bx
        pop     si
        pop     ax                      ; restore PageBitmap
        jc      NextPageBit             ; Rect is off screen
    ; 
    ; Rect is not off screen, paint it
    ; 
        push    ax
        push    si
        push    bx
        lds     si,lpPntStruc
	mov	ah,[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode]
        call    ModeGrfx               
        pop     bx
        pop     si
        pop     ax
        jc      short PageBitsDone
	btc	GrbFlags,GrbFlgs_GrfxDoOddBit
        jmp     short NextPageBit              
NextTableEntry:
        add     si,4
        jmp     NextPageBit
PageBitsDone:
        mov     si,bx                   ; restore si -> EXTPAINTSTRUC
	jmp	SHORT JustCursor
DoText:

    ;
    ; Build change rects and repaint them
    ;
	lea	di,[si.EPGrabDTA.DispMod]
    ;
    ; if VDD_Mod_List contains a rect of <(0,0), (0,0)>
    ;  signal error
    ; else if VDD_Mod_List contains a rect of <(ff,ff),(00,00)>
    ;   then no OPT...
    ; else
    ;  decrement rcleft, increment rcbottom.
    ;
	mov	ax,[di.VDD_Mod_list.rcLeft]
	cmp	ax,0ffh			; look at everything?
	jz	SHORT DOComplete	; yes
	or	ax,ax
	jz	SHORT DOAxNoInc
	dec	ax
DOAxNoInc:
	mov	[di.VDD_Mod_List.rcLeft],ax
	mov	ax,[di.VDD_Mod_List.rcBottom]
	inc	ax
	mov	[di.VDD_Mod_List.rcBottom],ax
	mov	cx,1
	mov	[di.VDD_Mod_Count],cx	
	lea	di,[di.VDD_Mod_List]
	jmp	SHORT DoTextLoop
DOComplete:
	xor	ax,ax
	mov	cx,ax
	xchg	ax,WORD PTR [di.VDD_Mod_List]
	xchg	cx,[di.VDD_Mod_Count]

    ; AX = modified pages bit map, CX = count of visible pages
	
	call	BuildTextRects		; Q: Any modifications?
	jcxz	SHORT NoTextRects	;   N: All done
	lea	di,[di.VDD_Mod_List]	;   Y: CX = count, DI -> rect list

IFDEF DEBUG
public DoTextLoop
ENDIF

    ;
    ; DI -> List of modified rectangles, CX = count of rectangles
    ;

DoTextLoop:
	push	di
	push	cx

NormRect:
;IFDEF RECTDEBUG
;        push    eax
;        push    ebx
;        push    ecx
;        push    edx
;        push    edi
;        push    esi
;
;	mov	bx,si
;	mov	esi,codeOffset Msg
;	mov	edx,SHELL_Debug_Out
;        
;	mov	ax,[di.rcLeft]
;        shl     eax,16
;	mov	ax,[di.rcTop]
;
;	mov	cx,[di.rcRight]
;        shl     ecx,16
;	mov	cx,[di.rcBottom]
;	call	[bx.ShellCall]
;	jmp	short USCont
;
;Msg db	  "Grabber:L,T,R,B-",0
;
;USCont:
;        pop     esi
;        pop     edi
;        pop     edx
;        pop     ecx
;        pop     ebx
;        pop     eax
;
;ENDIF

    ;
    ; Convert Rect in Cols & Rows to pixel CoOrds
    ;

	mov	cx,[si.FntWid]
	mov	ax,[di.rcLeft]
	mul	cx
	mov	[di.rcLeft],ax
	mov	ax,[di.rcRight]
	mul	cx
	mov	[di.rcRight],ax
	mov	cx,[si.FntHgt]
	mov	ax,[di.rcTop]
	mul	cx
	mov	[di.rcTop],ax
	mov	ax,[di.rcBottom]
	mul	cx
	mov	[di.rcBottom],ax
DoTextRect:
	call	PrepPnt
	jc	short NextRect
	call	ModeText
	jc	short UpdPntErr
NextRect:
	pop	cx
	pop	di
	add	di,SIZE Rect
	dec	cl
	jnz	DoTextLoop


NoTextRects:
	clc				; All ok
JustCursor:
	pushf				; Save carry setting
	bt	[si.EPStatusFlags],fFocusBit
	jnc	short SetReturnAX		; Don't have focus, no cursor
	bt	[si.EPStatusFlags],fSelectBit
	jc	short SetReturnAX		; In Select mode, don't do cursor
	call	CursorPos		; Get new cursor
	inc	dx
	jz	short NoCursor		; Cursor gone
	dec	dx
	mov	cl,[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode]
	cmp	cl,[si.EPGrabDTA.CurCursMode]	; Change in cursor mode?
	jnz	short MkNCur		; Yes
	mov	cx,[si.EPGrabDTA.CntrlSt.VDA_EGA_CurEnd]
	cmp	cx,[si.EPGrabDTA.CurCursEnd]	; Change in cursor shape?
	jnz	short MkNCur		; Yes
	mov	cx,[si.EPGrabDTA.CntrlSt.VDA_EGA_CurBeg]
	cmp	cx,[si.EPGrabDTA.CurCursBeg]	; Change in cursor shape?
	jz	short SetCurPos 	; No, just change in position
MkNCur:
	push	ax
	push	dx
	cCall	DestroyCaret
	pop	dx
	pop	ax
	call	MakeNewCursor		; Make new cursor
	jmp	short SetReturnAX

UpdPntErr:
	add	sp,4			; Discard saved DI and CX
	stc
	jmp	short JustCursor

NoCursor:
	mov	[si.EPGrabDTA.CurCursEnd],ax
	mov	[si.EPGrabDTA.CurCursBeg],ax
	mov	cl,[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode]
	mov	[si.EPGrabDTA.CurCursMode],cl
	cCall	DestroyCaret
	jmp	short SetReturnAX

US_Error:

	bts	[si.EPStatusFlags],fGrbProbBit ; cannot render
        call    PaintWindowBlack        ; paint window black
        mov     ax,1                    ; return no error
        jmp     SHORT ClearModf

SetCurPos:
	sub	ax,[si.ColOrg]	; Org onto display
	push	ax		; X for call to SetCaretPos
	sub	dx,[si.RowOrg]	; Org onto display
	push	dx		; Y for call to SetCaretPos
    ;
    ; Position Cursor
    ;
	cCall	SetCaretPos
SetReturnAX:
	popf
	mov	ax,0		; DO NOT XOR!!!!
	jc	short ClearModf
	inc	ax
ClearModf:
	push	ax		; Save return
    ;
    ; Clear off the MODs, app still "frozen"
    ;
	mov	ax,GRB_Clear_Mod
	mov	ebx,[si.ThisVMHand]
        call    [si.GGrbArea.VddApiProcAdr]

	call	ClearVidSel     ; Unfreeze the app
	pop	ax		; Recover return

	pop	edi
	pop	esi
cEnd

;****************************************************************************
; 
; PaintClientRect - Calls the ModeGrfx/ModeText depending on mode
;  
; ENTRY: DS:SI -> EXTPAINTSTRUC
;
; EXIT: returns CF set by paint code
;
; USES:	ALL but DS,SI,BP
;
;****************************************************************************
PaintClientRect proc near

	mov	ah,[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode]
	cmp	ah,7
	je	short PCText
	cmp	ah,4
	jb	short PCText
	call	ModeGrfx
	jmp	short PCDone
PCText:
	call	ClearWinMemState
	call	ModeText
PCDone:
        ret
PaintClientRect endp

;****************************************************************************
;
; SavePaintRect - save the PSrcPaint rect in EXTPAINTSTRUC on stack
;
; ENTRY: DS:SI -> EXTPAINTSTRUC
;
; EXIT: Paint rect copied to stack
;
; USES: BX,ES,DI
;
; Note: Called only from UpdateScreen where RectLeft is defined
;
;****************************************************************************

SavePaintRect proc near 
    ; 
    ; Save the client rect on the stack
    ; 
	mov	bx,si
	push	ss
	pop	es
	lea	di,RecLeft
	lea	si,[bx.Pstruct.PSrcPaint]
	cld
	movsw				
	movsw
	movsw
	movsw
	mov	si,bx
        ret
SavePaintRect endp

;****************************************************************************
;
; GetPageBitmap -  return PageBitmap in AX, LinesTable ptr in SI
;
; ENTRY: DS:SI -> EXTPAINTSTRUC
;
; EXIT:  AX = PageBitmap, DS:SI -> LinesTable
;
; USES: AX,DL,DS,SI
;
; Loads the Page bitmap(16 bits) from the modification structure and masks it.
; Atmost 2 4K pages in Mode D, 4 in Mode E, 7 in Mode10, 10 in Mode12 and 
; Mode11.
;
; Also loads SI with ptr to appropriate LinesTable.
;
; Note: called from UpdateRect only
;
;****************************************************************************

GetPageBitmap   proc near
	mov     ax,word ptr [si.EPGrabDTA.DispMod.VDD_Mod_List] ; Load Page Bitmap
	mov	dl,[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode]
        cmp     dl,0Dh
        je      short GPModeD
        cmp     dl,0Eh
        je      short GPModeE
IFDEF VGA
	cmp	dl,11h
	je	short GPMode1112
        cmp     dl,12H           
        jne     short GPModeF10

GPMode1112:
	and	ax,0000001111111111B	; Mode 12 - 10 pages atmost
        mov     si,codeOffset LinesTable12
        ret
GPModeF10:                              ; Mode 0FH or 10H
ENDIF
	cmp	dl,06h
	jbe	short GPModeCGA
        and     ax,0000000001111111B   ; Mode 10 - 7 pages atmost
        mov     si,codeOffset LinesTableF10
        ret
GPModeD:
        and     ax,0000000000000011B   ; Mode D - 2 pages atmost
        mov     si,codeOffset LinesTableD
        ret
GPModeE:
        and     ax,0000000000001111B   ; Mode E - 4 pages atmost
        mov     si,codeOffset LinesTableE
        ret
GPModeCGA:
	mov	ah,al
	and	ax,0000001100001100B	; Mode 4,5,6 - 4 pages with scan lines
	shr	al,2			;   repeated in pages 0,2 and 1,3
	or	al,ah
	xor	ah,ah
	mov	si,codeOffset LinesTableCGA
	ret
    ; 
    ; Each 4K of video memory corresponds to a set of lines on the screen
    ; These tables map video page number to the line number range on the screen 
    ; 
%OUT Check for lines that go between pages: is this correct?
LinesTableCGA LABEL BYTE		    ; CGA (4,5,6) modes same as mode D
LinesTableD LineTabStruc <0,103*2>
            LineTabStruc <103*2,400>
LinesTableE LineTabStruc <0,52*2>
            LineTabStruc <52*2,104*2>
            LineTabStruc <104*2,156*2>
            LineTabStruc <156*2,400>
LinesTableF10 LineTabStruc    <0,52>	    ;	<0,52>
	    LineTabStruc     <52,103>	    ;  <52,104>
	    LineTabStruc    <103,154>	    ; <104,156>
	    LineTabStruc    <154,205>	    ; <156,208>
	    LineTabStruc    <205,256>	    ; <208,260>
	    LineTabStruc    <256,308>	    ; <260,312>
	    LineTabStruc    <308,350>	    ; <312,350>
IFDEF	VGA
LinesTable12 LineTabStruc     <0,52>	    ;	<0,52>
	     LineTabStruc    <52,103>	    ;  <52,104>
	     LineTabStruc   <103,154>	    ; <104,156>
	     LineTabStruc   <154,205>	    ; <156,208>
	     LineTabStruc   <205,256>	    ; <208,260>
	     LineTabStruc   <256,308>	    ; <260,312>
	     LineTabStruc   <308,359>	    ; <312,364>
	     LineTabStruc   <359,410>	    ; <364,416>
	     LineTabStruc   <410,461>	    ; <416,468>
	     LineTabStruc   <461,480>	    ; <468,480>
ENDIF

GetPageBitmap endp

;*****************************************************************************
;
; PrepPnt - Prepare paint rects
;
; ENTRY:
;	DS:SI -> Extended Paint structure
;	ES:DI -> Input screen CoOrd rect
;	SS:BP -> Stack frame set at DoRects
; EXIT:
;	Carry Clear
;	    Extended paint structure variables set up to paint this rect
;	Carry Set
;	    Rectangle is off the screen
; USES:
;	ALL but DS,SI,BP
;
;
; Alg:
;       Let given rect be L,R,T,B- Left etc
;        L =- ColOrg, R =- ColOrg
;        If (R <= 0 || L > RecRight)
;                It is Offscreen
;        Ensure L >=0 R <= RecRight
;        
;        Similarly for T and B using RowOrg
;
;      - Build params in ext paint structure
;	 PSrcPaint.rcRight = R; .rcLeft = L; .rcTop = T; .rcBottom = B;
;        (Client area CoOrds)
;      - In PGVDRect,
;                Left = L + ColOrg
;                Right = R + ColOrg
;                Top = T + RowOrg
;                Bottom = B + RowOrg
;        "Screen" CoOrds (in pixels)
;        
;      - if (Text mode)
;            PTVDRect - "Screen" CoOrds in Cols & Rows
;		 PTVDRect.rcLeft = PGVDRect.rcLeft/FontWid - first col of repaint
;		 TDXPos = PTVDRect.rcLeft*FontWid - ColOrg;
;                                - bit position on the screen
;		 PTVDRect.rcTop = PGVDRect.rcTop/FontHgt - first row of repaint
;		 TDYPos = PTVDRect.rcTop*FontHgt - RowOrg;
;                                - bit position on the screen
;         
;            # of rows being painted
;	     = AX = (PSrcPaint.rcBottom - TDYPos + FontHgt - 1)/FontHgt
;            Max # of rows that can be painted
;            = CX = (# of rows - first row of repaint)
;                Ensure AX <= CX
;		 PTVDRect.rcBottom = AX + first row of repaint
;            # of cols being painted
;	     AX = (PSrcPaint.rcRight - TDXPos + FontWid - 1)/FontWid
;            Max # of cols that can be painted
;            CX = (# of cols - first col of repaint)
;                Ensure AX <= CX
;		 PTVDRect.rcRight = AX + first col of repaint
;
;*****************************************************************************

PrepPnt proc	near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
    ;
    ; Org the Right and Left boundaries onto the display and
    ;	adjust them to client area
    ;
	mov	ax,[si.ColOrg]
	sub	[di.rcRight],ax
	jbe	Cret			; Rect is off screen to left, ignore
	sub	[di.rcLeft],ax
	jnc	short NoAdjL
	mov	[di.rcLeft],0
NoAdjL:
	mov	ax,RecRight		; Right edge of client area
	cmp	ax,[di.rcLeft]
	jbe	Cret			; Rect is off screen to right, ignore
	cmp	ax,[di.rcRight]
	jae	short NoAdjR
	mov	[di.rcRight],ax
NoAdjR:
    ;
    ; Org the Top and Bottom boundaries onto the display and
    ;	adjust them to client area
    ;
	mov	ax,[si.RowOrg]
	sub	[di.rcBottom],ax
	jbe	Cret			; Rect is off screen to Top, ignore
	sub	[di.rcTop],ax
	jnc	short NoAdjT
	mov	[di.rcTop],0
NoAdjT:
	mov	ax,RecBottom		; Bottom edge of client area
	cmp	ax,[di.rcTop]
	jbe	Cret			; Rect is off screen to bottom, ignore
	cmp	ax,[di.rcBottom]
	jae	short NoAdjB
	mov	[di.rcBottom],ax
NoAdjB:
    ;
    ; Build Other parms in Extended paint structure
    ;
    ; Set paint rect
    ;
	mov	eax,dword ptr [di.rcRight]
	mov	dword ptr [si.Pstruct.PSrcPaint.rcRight],eax
	mov	eax,dword ptr [di.rcLeft]		   ; AX is Left
	mov	dword ptr [si.Pstruct.PSrcPaint.rcLeft],eax
    ;
    ; Figure left col of repaint
    ;
	mov	bx,[si.ColOrg]
	mov	di,[si.FntWid]
	add	ax,bx
	mov	[si.PGVDRect.rcLeft],ax
	mov	dx,[si.Pstruct.PSrcPaint.rcRight]
	add	dx,bx
	mov	[si.PGVDRect.rcRight],dx
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],7	; Text mode?
        je      SHORT PPText1
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],4	; Text mode?
	jae	short NotText1		; No, skip
PPText1:
	cwd
	idiv	di
	mov	[si.PTVDRect.rcLeft],ax   ; first column of repaint
	mul	di
	sub	ax,bx
	mov	[si.TDXpos],ax		; bit position on screen
NotText1:
    ;
    ; Figure Top Row of repaint
    ;
	mov	ax,[si.Pstruct.PSrcPaint.rcTop]
	mov	bx,[si.RowOrg]
	mov	cx,[si.FntHgt]
	add	ax,bx
	mov	[si.PGVDRect.rcTop],ax
	mov	dx,[si.Pstruct.PSrcPaint.rcBottom]
	add	dx,bx
	mov	[si.PGVDRect.rcBottom],dx
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],7	; Text mode?
        je      SHORT PPText2
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],4	; Text mode?
	jae	short NotText2		; No, skip
PPText2:
	cwd
	idiv	cx
	mov	[si.PTVDRect.rcTop],ax	  ; First line of repaint
	mul	cx
	sub	ax,bx
	mov	[si.TDYpos],ax		; Bit position on screen
    ;
    ; Figure Bottom Row of repaint
    ;
	sub	ax,[si.Pstruct.PSrcPaint.rcBottom]
	neg	ax
	add	ax,cx
	dec	ax
	cwd
	idiv	cx
	xor	cx,cx
	mov	cl,[si.EPGrabDTA.CntrlSt.VDA_EGA_Rows]
	sub	cx,[si.PTVDRect.rcTop]
	cmp	ax,cx
	jle	short pnt1
	mov	ax,cx
pnt1:	add	ax,[si.PTVDRect.rcTop]
	mov	[si.PTVDRect.rcBottom],ax
    ;
    ; Figure Right Col of repaint
    ;
	mov	ax,[si.Pstruct.PSrcPaint.rcRight]
	sub	ax,[si.TDXpos]
	add	ax,di			; add in character width
	dec	ax
	cwd
	idiv	di
	mov	cx,80
	sub	cx,[si.PTVDRect.rcLeft]
	cmp	ax,cx
	jle	short pnt2
	mov	ax,cx
pnt2:	add	ax,[si.PTVDRect.rcLeft]
	mov	[si.PTVDRect.rcRight],ax
NotText2:
	clc
	ret

Cret:
	stc
	ret

PrepPnt endp


sEnd	code

        end
