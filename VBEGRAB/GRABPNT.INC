;----------------------------------------------------------------
;
; INCLUDE file which defines the Extended PAINTSTRUCT used on re-paints
;
;    (C) Copyright MICROSOFT Corp. 1986-1990
;
;    ************* MICROSOFT CONFIDENTIAL ******************
;

    include	selectio.inc

GLOBALGRBSIZEMAX	EQU	12

PNTFONTSTRUC   STRUC
FontHand	DW	?
FontHgt 	DW	?
FontWid 	DW	?
PNTFONTSTRUC   ENDS

;
; These are the flag bits associated with display updates which are returned
; from the grabber up to WINOLDAP.MOD to tell him what to do.
;
fDisp_Ctlr	      equ 0000000000001000B
fDisp_CtlrBit	      equ 3		      ; flag indicating controller state chg
fDisp_VRAM	      equ 0000000000010000B
fDisp_VRAMBit	      equ 4		      ; flag indicating Video RAM change
fDisp_Curs	      equ 0000000000100000B
fDisp_CursBit	      equ 5		      ; flag indicating Cursor change
;;;;fDisp_	     equ 0000000001000000B
;;;;fDisp_Bit	     equ 6
fDisp_HCurTrack       equ 0000000010000000B
fDisp_HCurTrackBit    equ 7		      ; Horiz cursor track required


EXTPAINTSTRUCT STRUC
    Pstruct		db	(SIZE PAINTSTRUCT) DUP (?)
    PGVDRect		DB	(size RECT) dup(?)
    HScrlPos		DW	?
    VScrlPos		DW	?
    ColOrg		DW	?
    RowOrg		DW	?
    VM1_Hnd		DD	?
    DefFont		db	(SIZE PNTFONTSTRUC) DUP (?)
    AltFnt1		db	(SIZE PNTFONTSTRUC) DUP (?)
    AltFnt2		db	(SIZE PNTFONTSTRUC) DUP (?)
    AltFnt3		db	(SIZE PNTFONTSTRUC) DUP (?)
    AltFnt4		db	(SIZE PNTFONTSTRUC) DUP (?)
    AltFnt5		db	(SIZE PNTFONTSTRUC) DUP (?)
    AltFnt6		db	(SIZE PNTFONTSTRUC) DUP (?)
    WhtBrshH		DW	?
    BlkBrshH		DW	?
    RNG1DSSEL		DW	?
    ShellCall		DD	?
    GGrbArea		db	GLOBALGRBSIZEMAX dup (?)
    PTVDRect		DB	(size RECT) dup(?)
    TDXpos		DW	?
    TDYpos		DW	?
    FntHgt		DW	?
    FntWid		DW	?
    ThisVMHand		DD	?
    WindHand		DW	?
    BoxPrntHand 	DW	?
    hThisInst		DW	?
    SelStruc		DB	(size TTYSelect) dup(?)
    EPDispMod		DB	VDD_MOD_MAX dup(?)
    EPGrabDTA		DB	VDD_CTRL_STATE_MAX DUP (?)
    EPStatusFlags	DD	?
    VerStrng		DB	8 dup(?)
EXTPAINTSTRUCT ENDS

TXTPAINTSUB STRUC
    TPRect	DB	(size RECT) dup(?)
    TPXpos	DW	?
    TPYpos	DW	?
    TPFntHgt	DW	?
    TPFntWid	DW	?
TXTPAINTSUB ENDS
