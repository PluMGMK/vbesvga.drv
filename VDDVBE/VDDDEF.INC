;******************************************************************************
;
; VDDDEF.INC	Include file for Virtual Display Devices for VGA/8514
;
;	Author: MDW
;	Copyright (c) Microsoft 1986-1991
;
;DESCRIPTION:
;	This defines constants and data structures for VGA/8514
;       Virtual Display Devices(VDD).
;
;******************************************************************************


;**************************************
; Specific video adaptor conditional assembly map to generic conditionals
;
ISVGA	MACRO
IFNDEF VGA
VGA EQU -1
ENDIF
ENDM

ISVGAMONO	MACRO
IFNDEF VGAMONO
VGAMONO EQU -1
ENDIF
ENDM

;***************************************
; Flavors of VGA
IFDEF	VGA8514 			; 8514 gets VGA also
ISVGA
ISVGAMONO
ENDIF

IFDEF	CTVGA 			        ; Chips and Technologies 82C441 "VGA"
ISVGA
ENDIF

IFDEF	V7VGA				; Video 7 VGA
CLV7VGA EQU -1
ISVGA
ENDIF

IFDEF	CLVGA				; Cirrus Logic VGA
CLV7VGA EQU -1
ISVGA
ENDIF

IFDEF	VGAMONO 			; Monochrome VGA
ISVGA
ENDIF

IFDEF	PVGA				; Paradise VGA
ISVGA
ENDIF

IFDEF	IBMVGA				; True blue
ISVGA
ENDIF

IFDEF	TLVGA				; Tseng Labs VGA
ISVGA
ENDIF

IFDEF	TTVGA				; Trident TVGA
ISVGA
ENDIF

IFDEF	ATIVGA				 ; Tseng Labs VGA
ISVGA
ENDIF

IFDEF	GENVGA				 ; GENOA VGA
ISVGA
ENDIF

;***************************************
; Default VGA
RESERVEROMC6C7	EQU	-1		; Turn on detection and reserve of ROM
;;IFNDEF  VGA8514			  ; 8514 and CHIPs are special VDD's
IFNDEF	CTVGA
ATIVGA		EQU	-1		; Turn on ATI VGA Wonder code
IBMVGA		EQU	-1		; Turn on IBM VGA code
GENVGA		EQU	-1		; Turn on GENOA SuperVGA code
CLVGA		EQU	-1		; Turn on Cirrus Logic code
NEWCLVGA	EQU	-1		; Turn on Cirrus Logic code
V7VGA		EQU	-1		; Turn on Video 7 code
;;Ext_VGA	  EQU	  -1 ;Turn on Video 7 banking code
TLVGA		EQU	-1		; Turn on Tseng Labs code
TTVGA		EQU	-1		; Turn on Trident code
PVGA		EQU	-1		; Turn on Paradise VGA code
VGAMONO 	EQU	-1		; Turn on VGA support for mode 7 and F
RESERVEROMC6C7	EQU	-1		; Turn on detection and reserve of ROM
VRTCTIMER	EQU	-1		; Turn on framerate timer for VRTC
ENDIF	; NOT CTVGA
;;ENDIF   ; NOT VGA8514

IFDEF	V7VGA				; Video 7 VGA
CLV7VGA EQU -1
ELSE
IFDEF	CLVGA				; Cirrus Logic VGA
CLV7VGA EQU -1
ENDIF
ENDIF

IF1
IFDEF	VGA8514 			; 8514 gets VGA also
%OUT	---- 8514 support	    ----
ENDIF
IFDEF	CTVGA 			        ; Chips and Technologies 82C441 "VGA"
%OUT	---- CHIPS 441 VGA support  ----
ENDIF
IFDEF	V7VGA				; Video 7 VGA
%OUT	---- Video 7 support	    ----
ENDIF
IFDEF	CLVGA				; Cirrus Logic
%OUT	---- Cirrus Logic support   ----
ENDIF
IFDEF	NEWCLVGA			; Cirrus Logic
%OUT	---- Cirrus Logic 6410 support --
ENDIF
IFDEF	PVGA				; Paradise VGA
%OUT	---- Paradise VGA support   ----
ENDIF
IFDEF	IBMVGA				; True blue
%OUT	---- IBM VGA support	    ----
ENDIF
IFDEF	TLVGA				; Tseng Labs VGA
%OUT	---- Tseng Labs VGA support ----
ENDIF
IFDEF	TTVGA				; Trident TVGA
%OUT	---- Trident TVGA support   ----
ENDIF
IFDEF	ATIVGA				 ; Tseng Labs VGA
%OUT	---- ATI VGA Wonder support ----
ENDIF
IFDEF	GENVGA				 ; GENOA VGA
%OUT	---- GENOA VGA support	    ----
ENDIF
IFDEF	VGAMONO 			; Monochrome VGA
%OUT	---- Monochrome VGA support ----
ENDIF
IFDEF	RESERVEROMC6C7			; Support for ROM w/o signature
%OUT	---- C6, C7 w/o sig support ----
ENDIF
IFDEF	VRTCTIMER			; Support for vertical retrace timing
%OUT	---- VSync timing support   ----
ENDIF
%OUT
ENDIF	;IF1

	INCLUDE VMDAVGA.INC		; Grabber interface definitions


StartFlagSet MACRO flagset
DefTableName MACRO tn
?DF_TableName equ <&&tn&&>
ENDM
IFDEF DEBUG
IFDEF ?_&flagset
?DefFlagTable = 1
DefTableName %?_&flagset
ENDIF
ENDIF
ENDM

EndFlagSet MACRO flagset, size
IFDEF DEBUG
IFDEF ?_&flagset
BuildDefFlagNameTable %?DF_TableName, size
?DefFlagTable = 0
ENDIF
ENDIF
ENDM

DefFlag MACRO name, bit
DefName MACRO ename
ename&&_&bit	db 'f&name&', 0
ENDM
f&name		EQU	1 SHL bit
b&name		EQU	bit
IFDEF DEBUG
IFDEF ?DefFlagTable
IF ?DefFlagTable
VxD_DATA_SEG noalign
DefName %?DF_TableName
VxD_DATA_ENDS
ENDIF
ENDIF
ENDIF
ENDM

IFDEF DEBUG
BuildDefFlagNameTable MACRO name, size
DefFlagTableEntry MACRO bit
IFDEF name&&_&&bit
	dd  OFFSET32 name&&_&&bit
ELSE
	dd  0
ENDIF
ENDM

VxD_DATA_SEG
name	label	dword
	dd  size
?DF_bit = 0
REPT size
DefFlagTableEntry %?DF_bit
?DF_bit = ?DF_bit + 1
ENDM
VxD_DATA_ENDS
ENDM
ENDIF


;****************************************************************************
;****************************************************************************
;
; Structure definitions
;

MemC_Mod_Struc STRUC
MMS_data_port	dw  ?	; port value
MMS_index	db  ?	; index, if necessary (graphics controller, sequencer)
MMS_ANDmask	db  ?	; mask ANDed with new value
MMS_ORmask	db  ?	; mask ORed with AND result
MMS_flags	db  ?
		db  2 DUP(?)	; 8 byte aligned
MemC_Mod_Struc ENDS

MaxMemCMods	equ 16

DefFlag MMS_OEM_extension   0
DefFlag MMS_no_index	    1

MSS_Plane_Info_Struc struc
MSS_plane_handle    dd	?	    ; handle of memory alloc'ed, or 0
MSS_plane_addr	    dd	?	    ; linear address of memory alloc'ed
MSS_plane_size	    dw	?	    ; size needed for plane
MSS_plane_alloced   dw	?	    ; size alloc'ed for plane
MSS_Plane_Info_Struc ends

Mem_State_Struc struc
MSS_planes	db  (SIZE MSS_Plane_Info_Struc) * 4 DUP(?)
MSS_fontmap	db  8 DUP(?)
Mem_State_Struc ends

MSS_plane0 equ byte ptr MSS_planes
MSS_plane1 equ byte ptr MSS_planes + 1 * (SIZE MSS_Plane_Info_Struc)
MSS_plane2 equ byte ptr MSS_planes + 2 * (SIZE MSS_Plane_Info_Struc)
MSS_plane3 equ byte ptr MSS_planes + 3 * (SIZE MSS_Plane_Info_Struc)


;****************
; CRTC registers structure definition
;

IFDEF	PVGA
CL_Resvd	EQU	7+32+64 	; WDC CRTC regs fill out to 128 (2**7)
ELSE
CL_Resvd	EQU	7+32		; Fill out to 64 bytes (power of 2)
ENDIF	;PVGA

CRTC_Struc	STRUC
C_HTotal	DB	?		; Horizontal total
C_HDisp 	DB	?		; Horizontal Displacement
C_HBlnkStrt	DB	?		; Horizontal Blank start
C_HBlnkEnd	DB	?		; Horizontal Blank end
C_HRTCStrt	DB	?		; Horizontal retrace start
C_HRTCEnd	DB	?		; Horizontal retrace end
C_VTotal	DB	?		; Vertical total
C_Ovflw 	DB	?		; 8th bit for following
C_RowScn	DB	?		; First row after VRTC
C_CharHgt	DB	?		; Character Cell Height
C_CStart	DB	?		; Cursor start scan line
C_CEnd		DB	?		; Cursor end scan line
C_AddrH 	DB	?		; VRAM address high byte
C_AddrL 	DB	?		; VRAM address low byte
C_CAddrH	DB	?		; Cursor address high byte
C_CAddrL	DB	?		; Cursor address low byte
; Note following two registers have read values as noted
C_VRTCStrt	DB	?		; Vertical retrace start (write only)
					; Light pen address high byte(read only)
C_VRTCEnd	DB	?		; Vertical retrace end(write only)
					; Light pen address low byte(read only)
C_VDspEnd	DB	?		; Vertical display end line
C_LnOff 	DB	?		; Offset to next line
C_UndrLn	DB	?		; Underline
C_VBlnkStrt	DB	?		; Vertical blanking start
C_VBlnkEnd	DB	?		; Vertical blanking end
C_Mode		DB	?		; Mode
C_LnCmp 	DB	?		; Line compare for MA clearing
C_Extension	DB	CL_Resvd-1 DUP (?); Fill out to power of 2
C_Last		DB	?
CRTC_Struc	ENDS

C_MaxScan	equ byte ptr C_CharHgt

;****************
;
; Extensions to CRTC state for various versions defined as offsets
;	from the last entry.  Set C_Last to the offset of the
;	last defined entry
;
IFDEF   CTVGA
C_CT400 	EQU	C_Extension
C_CTTempFE	EQU	C_Extension+1
.ERRE C_Last GE C_CTTempFE
ELSE

IFDEF	TLVGA
C_TLVGA_Unused	EQU	C_Extension	; Unused - 2 index positions
C_XZ_Strt	EQU	C_Extension+2	; X Zoom Start
C_XZ_End	EQU	C_Extension+3	; X Zoom End
C_YZ_StrtLo	EQU	C_Extension+4	; Y Zoom Start Low
C_YZ_EndLo	EQU	C_Extension+5	; Y Zoom End Low
C_YZ_StEndHi	EQU	C_Extension+6	; Y Zoom Start/End Hi
C_Z_StLo	EQU	C_Extension+7	; Zoom Start Lo
C_Z_StMid	EQU	C_Extension+8	; Zoom Start Mid
;;		EQU	C_Extension+9	; Unused
C_Extd_Strt	EQU	C_Extension+10	; Extended start address
C_Compat	EQU	C_Extension+11	; Compatibility
C_OvflwHi	EQU	C_Extension+12	; More overflow bits
.ERRE C_Last GE C_OvflwHi
ENDIF ; TLVGA
ENDIF ; NOT CTVGA

IFDEF   PVGA
; Define Paradise VGA CRTC Controller extensions
C_PVGA_Unused	EQU	C_Extension
; extended registers added for WDC VGA chips except 1A
C_P29		EQU	C_Extension+16
C_P2a		EQU	C_Extension+17
C_P2b		EQU	C_Extension+18
C_P2c		EQU	C_Extension+19
C_P2d		EQU	C_Extension+20
C_P2e		EQU	C_Extension+21
C_P2f		EQU	C_Extension+22
C_P30		EQU	C_Extension+23
; extended registers added for WDC VGA 1F chips
C_P31		EQU	C_Extension+24
C_P32		EQU	C_Extension+25
C_P33		EQU	C_Extension+26
C_P34		EQU	C_Extension+27
C_P35		EQU	C_Extension+28
C_P36		EQU	C_Extension+29
C_P37		EQU	C_Extension+30
C_P38		EQU	C_Extension+31
C_P39		EQU	C_Extension+32
C_P3a		EQU	C_Extension+33
C_P3b		EQU	C_Extension+34
C_P3c		EQU	C_Extension+35
C_P3d		EQU	C_Extension+36
C_P3e		EQU	C_Extension+37
C_P3f		EQU	C_Extension+38
.ERRE C_Last GE C_P3f
ENDIF	; PVGA


IFDEF	PVGA
SL_Resvd	EQU	11+16		; WDC extensions to Sequencer indx 1F
ELSE
SL_Resvd	EQU	11		; OEM extensions to Sequencer
ENDIF	;PVGA

GL_Resvd	EQU	23		; OEM extensions to Graphics controller

Extended_Reg_Size EQU	80h		; OEM other extended regs

Reg_State_struc     STRUC

; CRT controller(must be first in EGA state struc so can access using CRTC
;   structure definitions
CRTC		DB	SIZE CRTC_Struc DUP (?)

; Index registers
A_Indx		DB	?		; Attribute controller index register
S_Indx		DB	?		; Sequencer index register
C_Indx		DB	?		; CRT controller index register
G_Indx		DB	?		; Graphics controller index register

; Attribute controller
A_Pal		DB	16 DUP (?)	; Color palette
A_Mode		DB	?		; Mode
A_OvScn 	DB	?		; Over scan color
A_PlEna 	DB	?		; Plane enable to attr reg
A_HPan		DB	?		; Horizontal panning
A_Color 	DB	?		; VGA color register
A_Extension	DB	10 DUP (?)	; up to 32 (power of 2)
A_Last		DB	1

; Sequencer
S_Rst		DB	?		; Reset
S_ClMode	DB	?		; Clocking mode
S_Mask		DB	?		; Map mask
S_ChMap 	DB	?		; Char map select
S_MMode 	DB	?		; Memory mode
S_Extension	DB  SL_Resvd-1 DUP (?)	; Up to 16 (power of 2)
S_Last		DB	1

; Graphics controller
G_SetRst	DB	?		; Set/Reset on write
G_SREna 	DB	?		; Set/Reset enable
G_CComp 	DB	?		; Color compare
G_Func		DB	?		; Data rotate and function
G_MSlct 	DB	?		; Read Map select
G_Mode		DB	?		; Mode
G_Misc		DB	?		; Miscellaneous
G_DCare 	DB	?		; Color don't care on compare reads
G_Mask		DB	?		; Mask for data/latches on write
G_Extension	DB  GL_Resvd-1 DUP (?)	; up to 32 (power of 2)
G_Last		DB	1

; Miscellaneous
V_Misc		DB	?		; Miscellaneous output

; Miscellaneous registers
G_Pos1		DB	?		; Graphics 1 position(must be 0)
G_Pos2		DB	?		; Graphics 1 position(must be 1)
V_Feat		DB	?		; Feature connector output
V_VGAEna	DB	?		; VGA - subsystem enable

; Status(input) registers
V_Stat0 	DB	?		; Status 0
V_Stat1 	DB	?		; Status 1

V_BIOSMode	DB	?		; Video BIOS mode

V_Extend	DB	Extended_Reg_Size DUP (?) ; Save area for extended regs.

Reg_State_Struc 	ENDS

.errnz	(SIZE Reg_State_Struc) MOD 4	; make sure struc is dword aligned

; CRT Controller Info Block (taken straight from VBE 3.0 spec)
VBE3_CRTCInfoBlock	struc
CRTC_HorzTotal		dw ?		; Horizontal total in pixels
CRTC_HorzSyncStart	dw ?		; Horizontal sync start in pixels
CRTC_HorzSyncEnd	dw ?		; Horizontal sync end in pixels
CRTC_VertTotal		dw ?		; Vertical total in lines
CRTC_VertSyncStart	dw ?		; Vertical sync start in lines
CRTC_VertSyncEnd	dw ?		; Vertical sync end in lines
CRTC_Flags		dw ?		; Flags (Interlaced, Double Scan etc.)
CRTC_PixelClock		dd ?		; Pixel clock in units of Hz
CRTC_RefreshRate	dw ?		; Refresh rate in units of 0.01 Hz
			db 40 dup (?)	; reserved
VBE3_CRTCInfoBlock	ends

; VBE mode info struct - we won't store the full thing, but we
; need to know where all the fields are to get the info we want!
VESAModeStruct	STRUC
VESAModeAttrs	dw ?
VESAWinAAttrs	db ?
VESAWinBAttrs	db ?
VESAGranularity	dw ?	; in kiB
VESAWinSize	dw ?	; in kiB
VESAWinASeg	dw ?
VESAWinBSeg	dw ?
VESABankSwitch	dd ?
VESAScanLineLen	dw ?	; in bytes
VESAWidth	dw ?	; in pixels
VESAHeight	dw ?	; in pixels
VESACharCellW	db ?	; in pixels
VESACharCellH	db ?	; in pixels
VESAMemPlanes	db ?
VESABPP		db ?	; bits per pixel, must be at least 8
VESABanks	db ?
VESAMemModel	db ?	; see VESA_MEM_*
VESABankSize	db ?	; in kiB
VESAImagePages	db ?
		db ?	; supposedly 1 if VBE 3.0, zero if less
VESARFieldSize	db ?
VESARFieldPos	db ?
VESAGFieldSize	db ?
VESAGFieldPos	db ?
VESABFieldSize	db ?
VESABFieldPos	db ?
VESAAFieldSize	db ?
VESAAFieldPos	db ?
VESADirectMode	db ?	; Bit 0 = programmable ramp, 1 = usable alpha channel
VESALinearBuf	dd ?	; 32-bit Physical Address
VESAOSMem	dd ?	; Off-Screen Memory
VESAOSMemSize	dw ?	; in kiB
VESAScanLineLin	dw ?	; same as VESAScanLineLen but for linear modes
VESAImgsBanked	db ?
VESAImgsLinear	db ?
VESALRFieldSize	db ?
VESALRFieldPos	db ?
VESALGFieldSize	db ?
VESALGFieldPos	db ?
VESALBFieldSize	db ?
VESALBFieldPos	db ?
VESALAFieldSize	db ?
VESALAFieldPos	db ?
VESAMaxPixClock	dd ?	; in Hz
VESAModeScratch	db 190 dup (?)
VESAModeStruct	ENDS

VESAModeSize	equ	SIZE VESAModeStruct

VBE_Reg_Struc	STRUC
VBE_VidModeP1	DW	?		; BX value from int 10h 4F02h, plus one!
VBE_WinSize	DW	?		; in kiB
VBE_WinASeg	DW	?
VBE_ModeAttrs	DW	?
VBE_LinearBuf	DD	?
VBE_CRTC	DB	(SIZE VBE3_CRTCInfoBlock) DUP (?)
VBE_Reg_Struc	ENDS

.ERRE	((SIZE VBE_Reg_Struc) LE  Extended_Reg_Size)

IFDEF CLVGA

CL_ER_START     equ     80h
CL_ER_COUNT     equ     0e0h-80h        ; 60h registers 80H thru DFH

CL_ER_Struc	struc

CL_ER_Misc1		db	?	    ;80 ; Hardware test
CL_ER_GPos1 		db	?	    ;81 ; Miscellaneous output
CL_ER_GPos2		db	?	    ;82 ; Feature control
CL_ER_ARX		db	?	    ;83 ; Attribute control index
CL_ER_WRC		db	?	    ;84 ; Write control
CL_ER_TC		db	?	    ;85 ; Timing control
CL_ER_BWC		db	?	    ;86 ; Bandwidth control
CL_ER_ROMC 		db	3 dup (?)   ;87 ;
CL_ER_LCDCNTL1     	db      6 dup (?)   ;8A
CL_ER_VRTCStrt		db	?	    ;90 ; Vertical retrace start
CL_ER_VRTCEnd		db	?	    ;91 ; Vertical retrace end
CL_ER_LPEN 		db	2 dup (?)   ;92 ; Light Pen
CL_ER_PPA		db	?	    ;94 ; Pointer pattern address
			db	7 dup (?)   ;95 ; Caret stuff
CL_ER_PXH		db	?	    ;9c ; Pointer Horizontal Position High
			db	3 dup (?)	;
CL_ER_LATCH0		db	?	    ;a0 ; Latch for plane 0
CL_ER_LATCH1		db	?	    ;a1 ; Latch for plane 1
CL_ER_LATCH2		db	?	    ;a2 ; Latch for plane 2
CL_ER_LATCH3		db	?	    ;a3 ; Latch for plane 3
CL_ER_CLK		db	?	    ;a4 ; Extended clock select
CL_ER_CURS 		db	?	    ;a5 ; Cursor attributes
			db	?	    ;a6 ;
CL_ER_SWITCH		db	?	    ;a7 ; Mode switch control
			db	7 dup (?)   ;a8 ;
CL_ER_STATE		db	?	    ;af ; Active adapter state
CL_ER_SCRATCH0		db	15 dup (?)  ;B0 ; Scratch ram 0-E
CL_ER_SCRATCHF		db	?	    ;BF ; Scratch ram F
CL_ER_CPURAR		db      2 dup (?)   ;c0 ;
CL_ER_LCDCNTL2     	db      5 dup (?)   ;c2	;
CL_ER_LCDCNTLIII   	db      ?           ;c7 ; LCD Control Register 3
                	db      24 dup (?)  ;c8 ;
CL_ER_Resvd		db	30 dup (?)	; Future expansion
CL_ShadowCRT6  	 	db      ?
CL_ShadowCRT7   	db      ?
CL_ER_Struc	ends

.errnz	((size CL_ER_Struc) - Extended_Reg_Size)
ENDIF


IFDEF	ATIVGA
ATI_Reg_Count	EQU	1Fh+4		; Size of ATI regs
ATI_Reg_Struc	STRUC
ATI_Regs	DB	ATI_Reg_Count DUP (?) ; The extended register save area
ATI_Indx	DB	?		; Extended reg index
ATI_Reg_Struc	ENDS

.ERRE	((SIZE ATI_Reg_Struc) LE  Extended_Reg_Size)
ENDIF ; ATIVGA

IFDEF	TLVGA
TLVGA_Regs_Struc STRUC
TLI_SegSel	DB	?
TLI_Key		DB	?
TLVGA_Regs_Struc ENDS
ENDIF

; Make sure CRTC is first in Reg_State_Struc
.ERRNZ	CRTC

IFDEF TTVGA
; Trident TVGA Special Register
TVGA_Unused		EQU	S_Extension
TVGA_3C5_B_v		EQU	S_Extension+1
TVGA_3C5_B		EQU	S_Extension+2	
TVGA_3C5_D0		EQU	S_Extension+3	; Old Definition (Wr 3c4.b)
TVGA_3C5_D1		EQU	S_Extension+4	; New Definition (Rd 3c4.b)
TVGA_3C5_E0		EQU	S_Extension+5	; Old
TVGA_3C5_E1		EQU	S_Extension+6	; New
TVGA_3C5_E1_flag	EQU	S_Extension+7	
TVGA_Rsrv		EQU	S_Extension+8
.ERRE S_Last GE TVGA_Rsrv
ENDIF ;TTVGA

IFDEF	PVGA
; Define Paradise VGA Graphics Controller extensions
G_PVGA0A	EQU	G_Extension	; Address A
G_PVGA0B	EQU	G_Extension+1	; Address B
G_PVGA1 	EQU	G_Extension+2	; Memory size
G_PVGA2 	EQU	G_Extension+3	; Video select
G_PVGA3 	EQU	G_Extension+4	; CRT control
G_PVGA4 	EQU	G_Extension+5	; Video control
G_PVGA5 	EQU	G_Extension+6	; Enable features if out 3CF,0X5h
; Make sure we don't go past end of data area for graphics controller
.ERRE G_PVGA5 LE G_Last

; Define Paradise VGA Sequencer Controller extensions
S_PVGA_Unused	EQU	S_Extension
S_PVGA20 	EQU	S_Extension+1
S_PVGA21 	EQU	S_Extension+2
S_PVGA_1CB1     EQU	S_Extension+3
S_PVGA_1CB2     EQU	S_Extension+4
;;		EQU	S_Extension+6
;;		EQU	S_Extension+7
;;		EQU	S_Extension+8
;;		EQU	S_Extension+9
;;		EQU	S_Extension+10
;;		EQU	S_Extension+11
S_PVGA22 	EQU	S_Extension+12		; memory interface and FIFO cntrl
S_PVGA23 	EQU	S_Extension+13		; system interface control
S_PVGA24 	EQU	S_Extension+14		; miscellaneous control 4
S_PVGA_1Dpr33 	EQU	S_Extension+15		; 1D chip DRAM timing and zero wait
S_PVGA_1Dpr34 	EQU	S_Extension+16		; 1D video memory mapping 02-06-91
; Make sure we don't go past end of data area for Sequencer controller
.ERRE S_PVGA_1Dpr34 LE S_Last
ENDIF	;PVGA

IFDEF   CTVGA
G_CTCtl 	EQU	G_Extension
ENDIF

IFDEF	CLV7VGA
S_V7_BankSel	EQU	BYTE PTR V_Extend+0F6h-80h
S_V7_ExtPageSel EQU	BYTE PTR V_Extend+0F9h-80h
S_V7_ExtComp	EQU	BYTE PTR V_Extend+0FCh-80h
ENDIF

;****************
; Control Block (CB) structure definition
;
DAC_State_Size	    EQU 256*4
DAC_Msg_State_Size  EQU 16*4

IFDEF Ext_VGA
VRAM_Mod_List_Size  EQU  64/8		; 64 pages/8 bits per byte
ELSE
VRAM_Mod_List_Size  EQU  32/8		; 32 pages/8 bits per byte
ENDIF
.ERRE	VRAM_Mod_List_Size LE ModListMax

VDD_CB_Struc	 STRUC
; Flags, state of VM's controller, state of VM's video memory
VDD_Flags	DD  ?			; VDD flags
VDD_TFlags	DD  ?			; VDD Type flags
VDD_EFlags	DD  ?			; VDD Event flags
VDD_Stt 	DB  SIZE Reg_State_struc DUP (?) ; Controller state structure

; This must directly follow VDD_Stt!!
VDD_DAC 	DB  DAC_State_Size DUP(?) ; DAC save space
VDD_PEL_Addr	DD  ?			; address within VDD_DAC array
VDD_PEL_Idx	DB  ?			; byte index within PEL DWORD entry (1-3)
VDD_PEL_Mode	DB  ?			; 0 - read mode, 3 - write mode

VDD_fontpages	DB  ?			; a set bit indicates a loaded font
					;   in this order 73625140

VDD_MemC_ModCnt DB  ?
VDD_MemC_Mods	DB  (SIZE MemC_Mod_Struc) * MaxMemCMods DUP (?)
VDD_TrapEnable	DD  ?			; One bit for each port trapped
IFDEF Ext_VGA
VDD_Bank_Select DD  ?			; bank select for extended VGA's
ENDIF
VDD_Latches	DB  4 DUP (?)		; Video memory latches

VDD_SttCopy	DB  SIZE Reg_State_struc DUP (?) ; Controller state copy
VDD_MStt	DB  SIZE Mem_State_Struc DUP (?) ; Memory state structure
VDD_MSttCopy	DB  SIZE Mem_State_Struc DUP (?) ; Memory state structure
VDD_VideoPages	DD  ?			; # of entries in following tables
VDD_PageMap	DD  ?			; pointer to page map array
VDD_PageFlags	DD  ?			; pointer to page flags array
VDD_VRAM_Mods	DD  VRAM_Mod_List_Size/4 DUP (?)
VDD_Grab_Mods	DD  VRAM_Mod_List_Size/4 DUP (?)
VDD_Mod_Rect	DD  0			; rectangle of change <(a,b),(c,d)>
VDD_Recent_User_Action DW 0		; recently event occured
VDD_Check_Upd_Soon DW 0			; check update
VDD_Scroll_Cntr	DW  0			; generate 1 update for so many scrolls
VDD_Last_Int10	DW  0			; what was the last int 10?
VDD_NotifyEvent DD  ?			; event handle for VDD_Int_FGrnd_Notify
					;   or VDD_Int_BGrnd_Notify events
VDD_nullpages	DD  ?			; bitmap of mapped null pages
VDD_SavedStt	DD  ?			; address of saved VDD_STT for VM's
					;   with CanRestore set in VDD_Flags
VDD_VertCnt	DB  ?			; Hold VRTC Counter
VDD_HorizCnt	DB  ?			; Toggle HRTC Counter
VDD_PIF 	DW  ?			; VDD PIF bits
VDD_Time_Out_Handle DD	?		; Display update timeout handle
VDD_ModTime	DD  ?			; System time at last video mod
VDD_Upd_Start	DD  ?			; Start time of window update
VDD_Mod_Flag_Save DD  ? 		; cumulative flags passed to grabber
VDD_Copy_Buf	DB SIZE MSS_Plane_Info_Struc DUP(?) ; buffer used by grabber
					;   for determining memory changes
VDD_Get_Mem_Count   DD	?		; Match calls VDD_Get_Mem/VDD_Free_Mem
                                        ; VDD_UnLock_APP unfreezes the App only
					; if this count is Zero.
VDD_Update_Hit_Cnt  DB	?
VDD_savemem_maps    DB	?		; # of save mem pages mapped in VM
VDD_first_page	    DB	?
VDD_visible_pages   DB	?

VDD_saved_visible   DD	?

VDD_Postponed_TimeOuts	DB  ?		; # of time-outs that have been postponed
VDD_Owned_Pages     DB	?		; count of physical pages alloc'ed

IFDEF	VRTCTIMER
VDD_Framerate	    DB	?		; frames per second for current VGA mode
VDD_Framerate_Recip DB	?		; milliseconds per frame
VDD_VRTC_timeout    DD	?		; timeout event for Vertical Retrace
ELSE
VDD_Padding	    DB	2 dup(?)	; for padding only, reclaim as needed
ENDIF

VDD_CB_Struc	 ENDS

.errnz (SIZE VDD_CB_Struc) MOD 4

.errnz VDD_DAC - VDD_Stt - (SIZE Reg_State_struc)  ; VDD_DAC must follow VDD_Stt

.errnz VDD_VideoPages MOD 4		; make sure these are dword aligned
.errnz VDD_Time_Out_Handle MOD 4


;***************
; VDD Flag bit definitions for VDD_Flags     (fVDD_ & bVDD_)
;
StartFlagSet fVDD
DefFlag VDD_Win 	0   ; VM is displayed in window
DefFlag VDD_ModeSet	1   ; Video in INT 10 mode set
DefFlag VDD_ModeChange	2   ; Mode change in progress for windowed VM
DefFlag VDD_MdSvRAM	3   ; RAM not destroyed during mode chg
DefFlag VDD_PageChg	4   ; Video in INT 10 page change
DefFlag VDD_Font	5   ; Memory mapped for font load INT 10
DefFlag VDD_DirFont	6   ; Mem mapped for font load (directly programmed)
DefFlag VDD_WaitAtt	7   ; VDD suspended VM until attached
DefFlag VDD_DspDrvrAware 8  ; Set if display driver told us where its
			    ;	video memory resident data is kept
DefFlag VDD_HCurTrk	9   ; Track cursor horizontally
DefFlag VDD_Grab       10   ; Grab event pending
DefFlag VDD_Upd        11   ; Update event pending
DefFlag VDD_IdleUpdate 12   ; VM went idle during window update
DefFlag VDD_MemCmods   13   ; Set if MemC mods are required for VM
DefFlag VDD_MappedA0   14   ; Mem mapped at A0 in CGA/text mode
DefFlag VDD_AXRd       15   ; Attribute index read(VGA)
DefFlag VDD_IOT        16   ; I/O ports presently trapped
DefFlag VDD_CanRestore 17   ; VM knows how to restore its screen
DefFlag VDD_Boost      18   ; SYS VM boosted for memory read
DefFlag VDD_Hide       19   ; Hide cursor in window
DefFlag VDD_PVGA_Ena   20   ; Paradise VGA regs are enabled
DefFlag VDD_ATIEna     21   ; ATI register is enabled
DefFlag VDD_NoSaveRes  22   ; set if VM must restore screen
DefFlag VDD_IOTmono    23   ; mono CRTC I/O ports presently trapped
DefFlag VDD_InInt2F    24   ; set while exec'ing foreground INT 2Fh
DefFlag VDD_NeedRestore 25  ; We have modified VM state but not hardware
DefFlag VDD_PageFault  26   ; page fault occurred recently (cleared by timeout)
DefFlag VDD_InPFault   27   ; currently processing a page fault
DefFlag VDD_DacChg     28   ; DACs have changed since last clear_mod
DefFlag VDD_BoostUpdate 29  ; Boost complete update
DefFlag VDD_MInit      31   ; Display mem initialized
EndFlagSet fVDD, 32

;***************
; VDD_EFlags definitions, error and error msg status  (fVDE_ & bVDE_)
;	Note that Msg bits are error bits shifted left 8
;
DefFlag VDE_NoMain	8   ; Out of main, display not accurate
DefFlag VDE_NoCopy	9   ; Out of copy, window not accurate
DefFlag VDE_NoFGrnd    10   ; Cannot run bkgrnd with fgrnd VM
DefFlag VDE_NoWind     11   ; Cannot window this VM
DefFlag VDE_Excl       12   ; Background high Res excluded
DefFlag VDE_NoSupMode  13   ; Mode not supported
DefFlag VDE_NoPgAvail  14   ; Unable to satisfy video memory request
DefFlag VDE_NoMono     15   ; Mapped mono when mono pages not supported
DefFlag VDE_NoMMsg     16   ; User told out of main
DefFlag VDE_NoCMsg     17   ; User told out of copy
DefFlag VDE_NoFGMsg    18   ; User told cannot run with fgrnd
DefFlag VDE_NoWMsg     19   ; User told cannot window
DefFlag VDE_ExclMsg    20   ; User told VM exclusive
DefFlag VDE_NoSMsg     21   ; User told mode not supported
DefFlag VDE_NoPAMsg    22   ; Unable to satisfy video memory request
DefFlag VDE_NoMonoMsg  23   ; Mapped mono when mono pages not supported

;***************
; The following equates and .ERRNZ make sure that the I/O trap routines
;   correctly do not write beyond the end of the save area reserved for
;   each of the controllers.
A_IMax		EQU	A_Last-A_Pal
mx_Attr 	EQU	1Fh		; Mask for Attribute index
.ERRE		mx_Attr EQ A_IMax

G_IMax		EQU	G_Last-G_SetRst
mx_Grp		EQU	1Fh		; Mask for Graphics controller index
.ERRE		mx_Grp EQ G_IMax

S_IMax		EQU	S_Last-S_Rst
IFDEF	PVGA
mx_Seq		EQU	1Fh		; Mask for Sequencer index
ELSE
mx_Seq		EQU	0Fh		; Mask for Sequencer index
ENDIF	;PVGA
.ERRE		mx_Seq EQ S_IMax

IFDEF	PVGA		
.ERRE 128 EQ SIZE CRTC_Struc
mx_CRTC 	EQU	7Fh		; Mask for CRTC index
ELSE
.ERRE 64 EQ SIZE CRTC_Struc
mx_CRTC 	EQU	3Fh		; Mask for CRTC index
ENDIF	;PVGA

C_IMax		EQU	C_Last-C_HTotal
.ERRE		mx_CRTC EQ C_IMax

;***************
;
; VDD global flag definitions for video type [VDD_TFlags]  (fVT_ &  bVT_)
;	There is a global copy kept in [VT_Flags] and local copy in each CB,
;	for efficiency.  The initial value of many of these flags are passed
;	from real mode initialization code that detects Video adapter type.
;
StartFlagSet fVT
; Flags valued 0-7 cannot be passed from Real Mode init.  They are
;	initialized to zero.  The size of the video mem is passed there instead
DefFlag VT_NoSaveResSysVM    0	; Save/restore SYS VM enabled
DefFlag VT_NoSaveResOthers   1	; Save/restore other VMs enabled
DefFlag VT_Mono 	     2	; VDD supports Mono VGA memory (B0-B7)
DefFlag VT_MonoPorts	     3	; VDD supports Mono VGA ports
DefFlag VT_Notify_at_PF      4	; bkgnd INT 2F notification done at pfault time
DefFlag VT_ResvB0	     5	; Reserve memory from B0 to B7
DefFlag VT_SuprsMsg	     6	; Do not message NoFGrnd and NoAvailPages
DefFlag VT_NoSuspend	     7	; Do not suspend application, map null memory
DefFlag VT_SysVMnot1stBank   8	; Set if Sys VM not running in 1st bank of
				;   video memory
DefFlag VT_SysVMin2ndBank    9	; Set if Sys VM is running in 2nd bank of video
				;   memory (VT_SysVMnot1stBank must be set also)
DefFlag VT_TVGA 	    16	; Trident TVGA
DefFlag VT_TVGA9100	    17	; Trident TVGA 9100 (need special care)
DefFlag VT_ATIVGA	    18	; ATI VGA Wonder
DefFlag VT_ATIVGA3	    19	; ATI VGA Wonder V3 and below
DefFlag VT_NEWCLVGA	    20	; Cirrus Logic VGA 6410
DefFlag VT_CLVGA	    21	; Cirrus Logic VGA, 0ECh enable (more regs)
DefFlag VT_CLVGA_RevC	    22	; Cirrus Logic 610/620 chip set Rev C
				;   (this bit will only be set, if VT_CLVGA is)
DefFlag VT_V7VGA	    23	; Video 7 VGA (more regs)
ifdef	VGA8514
DefFlag VT_8514 	    24	; IBM 8514
else
DefFlag	VT_VBESVGA	    24	; VBE detected, we can run VBE code
endif
DefFlag VT_XGAbit	    25	; Set for machines where IBM has redefined the
				;   meaning of bit 6 of CRT.17h.  Normally
				;   this bit selects byte/word addressing for
				;   the CRT controller and belongs to the CRTC
				;   owner.  On IBM's implementation of XGA
				;   this bit selects byte/word addressing of
				;   the graphics controller and thus belongs
				;   to the MemC owner!
DefFlag VT_CTVGA	    26	; CHIPS VGA(82c441) controller
DefFlag VT_PVGA 	    27	; Running on Paradise VGA (more regs)
DefFlag VT_PVGA1F	    28	; Running on Paradise VGA version 1F (more regs)
DefFlag VT_TLVGA	    29	; Running on Tseng Labs VGA (more regs!)
DefFlag VT_TL_ET4000	    30	; Tseng Labs ET4000 VGA
DefFlag VT_RsrvC6C7	    31	; Reserve C6 & C7 as ROM without a signature
EndFlagSet fVT, 32

;
; VESA Mode Number Bitfields
;
StartFlagSet fVESA
DefFlag	VESA_SVGA	     8	; This is an SVGA mode
DefFlag	VESA_UCRTC	    11	; Use custom CRTCInfoBlock
DefFlag	VESA_VBEAFInit	    13	; VBE/AF initializes accelerator hardware
DefFlag	VESA_Linear	    14	; Use linear framebuffer
DefFlag	VESA_PreserveMem    15	; Preserve contents of VRAM
EndFlagSet fVESA,16

;
; VESA Mode Attribute Bitfields
;
StartFlagSet fVModeAttr
DefFlag	VModeAttr_HWSupport	0
DefFlag	VModeAttr_OptInfo	1
DefFlag	VModeAttr_BIOSOutput	2
DefFlag	VModeAttr_Colour	3
DefFlag	VModeAttr_Graphics	4
DefFlag	VModeAttr_NonVGA	5
DefFlag	VModeAttr_NoBankSwitch	6
DefFlag	VModeAttr_LinearSupport	7
DefFlag	VModeAttr_DoubleScan	8
DefFlag	VModeAttr_Interlaced	9
DefFlag	VModeAttr_HWTripleBuf	10
DefFlag	VModeAttr_HWStereo	11
DefFlag	VModeAttr_DualStartAddr	12
EndFlagSet fVModeAttr,16

;
; VDD global flag definitions for [Vid_Flags]  (fVid_ &  bVid_)
;
StartFlagSet fVid
DefFlag Vid_MsgInit	     0	; Message mode INIT complete
DefFlag Vid_DOff	     1	; Display is off(during save/restore)
DefFlag Vid_SysVMI	     2	; Sys VM initialization complete
DefFlag Vid_Crit	     3	; In video critical section
DefFlag Vid_VMsSuspended     4	; VM's have been suspended by VDD
DefFlag Vid_MsgA	     6	; System message mode active
DefFlag Vid_SFPending	     7	; Set Focus is pending
DefFlag Vid_PlanarInit	     8	; Planar mode is initialized
DefFlag Vid_DspDrvr_Init     9	; set on first INT 10h mode call from pmode
DefFlag Vid_Dont_Set_Mode   10	; set after a forced mode change, if done before
				;    Vid_DspDrvr_Init is set
DefFlag Vid_SR_Section	    12	; Special save restore "critical" section
DefFlag Vid_SR_Latch_res    13	; Restore latches at end of SR section
DefFlag Vid_SR_regs_saved   14	; regs saved for CRTC owner while in SR section
DefFlag	Vid_No_Bounce	    15	; don't do BG/FG bounce for focus VM on modeset
EndFlagSet fVid, 32

;***************************************************************************
;***************************************************************************
;
;  Video display register equates
;	...Colr are for CGA and EGA color modes
;	...Mono are for EGA/VGA monochrome modes
;
;NAMING CONVENTIONS
; pXXXXX is a I/O port definition
; fXXXXX is a bit mask
; bXXXXX is a bit number
; mXXXXX is a bit mask (multiple fXXXX)
; vXXXXX is a value to output/input to/from a port
; xXXXXX is a specific index

;***************
pCRTCIndxColr	EQU	3D4h		; CRTC index register
pCRTCIndxMono	EQU	3B4h

pCRTCDataColr	EQU	3D5h		; CRTC data register
pCRTCDataMono	EQU	3B5h

fVRTCEndIRQEna	EQU	00100000b	; default-on bit DISABLES the IRQ (yep...)
fVRTCEndIRQClr	EQU	00010000b	; used to reset the flip-flop

;***************
pStatColr	EQU	3DAh		; Status register
pStatMono	EQU	3BAh
fStatEna	EQU	00000001b	;   Video RAM access OK for processor
fStatLPTr	EQU	00000010b	;   Light pen triggered
fStatLPSw	EQU	00000100b	;   Light pen switch is "on"
fStatVRTC	EQU	00001000b	;   Vertical retrace in progress
mStat_IVal	EQU	fStatEna+fStatVRTC  ; Initial value for pseudo status

;***************
pFeatColr	EQU	pStatColr	; Feature control
pFeatMono	EQU	pStatMono
pFeatVGAIn	EQU	3CAh		; VGA feature control read
fFeatFC0	EQU	00000001b	;   FC0
fFeatFC1	EQU	00000010b	;   FC1

;***************
pLPen1Colr	EQU	3DBh		; Light pen latch clear
pLPen1Mono	EQU	3BBh
pLPen2Colr	EQU	3DCh		; Light pen latch set
pLPen2Mono	EQU	3BCh

;***************
pMisc		EQU	3C2h		; Miscellaneous output
IFNDEF CTVGA
pMiscIn 	EQU	3CCh		; VGA read Misc. output
ENDIF
fMiscPNum	EQU	00000001b	;   3Dx port numbers(vs. 3Bx)
fMiscREna	EQU	00000010b	;   Ram enable
fMiscDot	EQU	00001100b	;   Dot clock select
fMiscOSrc	EQU	00010000b	;   Output source
fMiscPage	EQU	00100000b	;   Page bit for odd/even mode
fMiscHPol	EQU	01000000b	;   Horizontal retrace polarity
fMiscVPol	EQU	10000000b	;   Vertical retrace polarity
mMiscCRTC	EQU	fMiscREna+fMiscPage ; Mask for CRTC bits
mMiscMemC	EQU	0FFh - mMiscCRTC    ; Mask for MemC bits

;***************
pStt0EGA	EQU	pMisc		; Miscellaneous status
fStt0Swit	EQU	00010000b	;   Switch sense(addr'd by dot clk sel)
fStt0FCI0	EQU	00100000b	;   Feature card input 0
fStt0FCI1	EQU	01000000b	;   Feature card input 1
fStt0VRTC	EQU	10000000b	;   VRTC IRQ flip-flop
bStt0VRTC	EQU	7

;***************
pAttr		EQU	3C0h		; Attribute(palette) address/data
fVAI_Indx	EQU	10000000b	; sign bit of Attribute index is
bVAI_Indx	EQU	7		;   flag indicating port is index
fVAI_ScOn	EQU	00100000b	; Indicates screen is on
bVAI_ScOn	EQU	5

;***************
pSeqIndx	EQU	3C4h		; Sequencer address
pSeqData	EQU	3C5h		; Sequencer data
fSeq0ARst	EQU	00000001b	;   0:Async reset
fSeq0SRst	EQU	00000010b	;   0:Sync reset
fSeq1DPCh	EQU	00000001b	;   1:Dots per character
fSeq1BWid	EQU	00000010b	;   1:Band Width
fSeq1ShLd	EQU	00000100b	;   1:Shift load(0=every char, 1=skip)
fSeq1DClk	EQU	00001000b	;   1:Dot clock(=1 if halved)
mSeq2WMsk	EQU	00001111b	;   2:Write mask
mSeq3ChrB	EQU	00000011b	;   3:Char map B select(attr bit 3 = 0)
mSeq3ChrA	EQU	00001100b	;   3:Char map A select(attr bit 3 = 1)
fSeq4Alph	EQU	00000001b	;   4:Alpha mode(char gen enabled)
fSeq4ExtM	EQU	00000010b	;   4:Extended memory installed
fSeq4SqAd	EQU	00000100b	;   4:Seq'l mem addr'ing(vs. odd/even)
fSeq4Chain4	EQU	00001000b	;   4:Chain 4 (double odd/even) for
					;     256 color (mode 13)
IFDEF CLV7VGA

fSeqF9extpgsel	EQU	00000001b	;V7F9:Extended page select
fSeqFCext256m	EQU	00000010b	;V7FC:Extended 256 color mode
fSeqFCext256e	EQU	00000100b	;V7FC:Extended 256 color enable
fSeqFCseqChain4 EQU	00100000b	;V7FC:Sequential Chain 4
ENDIF

;***************
pGrp1Pos	EQU	3CCh		; Graphics posn 1(=0)
pGrp2Pos	EQU	3CAh		; Graphics posn 2(=1)
pGrpIndx	EQU	3CEh		; Graphics controller address
pGrpData	EQU	3CFh		; Graphics controller data
fGrp0StV0	EQU	00000001b	;   0:Value for plane 0 if enabled
fGrp0StV1	EQU	00000010b	;   0:Value for plane 1 if enabled
fGrp0StV2	EQU	00000100b	;   0:Value for plane 2 if enabled
fGrp0StV3	EQU	00001000b	;   0:Value for plane 3 if enabled
fGrp1Ena0	EQU	00000001b	;   1:Enable for plane 0
fGrp1Ena1	EQU	00000010b	;   1:Enable for plane 1
fGrp1Ena2	EQU	00000100b	;   1:Enable for plane 2
fGrp1Ena3	EQU	00001000b	;   1:Enable for plane 3
mGrp2Colr	EQU	00001111b	;   2:Color compare value
mGrp3RCnt	EQU	00000111b	;   3:Rotate left count for mode 0
mGrp3Func	EQU	00011000b	;   3:Function for modes 0 and 2
mGrp4RMsk	EQU	00000111b	;   4:Read map select
mGrp5WMod	EQU	00000011b	;   5:Write mode
fGrp5Test	EQU	00000100b	;   5:Test condition
fGrp5RMod	EQU	00001000b	;   5:Read mode(0=plane,1=compare)
fGrp5SqAd	EQU	00010000b	;   5:Seq'l mem addr'ing(vs. odd/even)
fGrp5CGA	EQU	00100000b	;   5:CGA 4 color mode addressing
fGrp6Char	EQU	00000001b	;   6:Char or graphics
fGrp6Chain	EQU	00000010b	;   6:Chain odd maps after even
mGrp6Addr	EQU	00001100b	;   6:Processor view of VRAM start addr
					;	00=A000 for 128kb
					;	01=A000 for 64kb
					;	10=B000 for 32kb
					;	11=B800 for 32kb
bGrp6Addr	EQU	     2		;     First of 2 bits for start addr
mGrp7Colr	EQU	00001111b	;   7:Color don't care for read compare
					;   8:Mask: use latch value vs. data

;****** VGA subsystem enable
pVGAEna 	EQU	3C3h		; VGA enable register
fVGAEna 	EQU	00000001b	;   Enable access to VGA

;****** VGA DAC
pDACWindx	EQU	3C8h		; DAC Write index(R/W)
pDACRindx	EQU	3C7h		; DAC Read index(RO)
pDACState	EQU	pDACRindx	; DAC state
pDACData	EQU	3C9h		; DAC data(3 successive accesses)
pDACMask	EQU	3CAh		; DAC mask

;****** VGA read access to write only registers
pMiscRead	EQU	3CCh		; Port to read Misc output register
pFeatRead	EQU	3CAh		; Port to read Feature output register

IFDEF VGA8514
;****** 8514 DAC
p8514DACWindx	EQU	2ECh		; DAC Write index(R/W)
p8514DACRindx	EQU	2EBh		; DAC Read index(RO)
p8514DACState	EQU	pDACRindx	; DAC state
p8514DACData	EQU	2EDh		; DAC data(3 successive accesses)
ENDIF

;******
; values returned from reads of port pDACState:
;
vDAC_Read_Mode	EQU	0
vDAC_Write_Mode EQU	3


IFDEF	CTVGA
xC_CTMiscRead	EQU	0Fh		; CHIPS Misc output read index
xC_CTFeatRead	EQU	0Eh		; CHIPS Feat output read index
xC_CT400	EQU	0F9h		; CHIPS 400 line reg index
xC_CTTempFE	EQU	0FEh		; CHIPS CRTC temp reg FEh
xG_CTCtl	EQU	0F7h		; CHIPS control reg index
ENDIF

;***************
pCMode		EQU	3C6h		; Control mode(Compaq specific)

IFDEF ATIVGA
ATiVGA_extended_reg	EQU	01ceh
ENDIF

IFDEF TTVGA
TVGA_3C5_B_WrMode	equ	0
TVGA_3C5_B_RdMode	equ	1
ENDIF

;***************************************************************************
;***************************************************************************
;
;   Miscellaneous equates
;
; BIOS instance definitions
;
EGA_I_Addr1 EQU 449h
EGA_I_Len1  EQU 1Eh
EGA_I_Addr2 EQU 484h
EGA_I_Len2  EQU 7
EGA_I_Addr3 EQU 4A8h
EGA_I_Len3  EQU 4
EGA_I_Addr4 EQU 410h
EGA_I_Len4  EQU 2


BIOS_Col_Count	EQU 44Ah
BIOS_Line_Count EQU 484h

;***************
; Timeout period to check for video updates when VM is windowed
;
VDD_Def_Update_Time EQU 50		; Default window update time = 50ms

;***************
; Priority boost for System VM when grabber is rendering VM into a window.
;
VDD_Pri_Device_Boost EQU Low_Pri_Device_Boost

;***************
; Instance Map equates
;   VxD_IM_Len	defines the number of instance map ranges to reserve
;   VxD_IMV_Len defines the number of bytes those ranges represent
;
VDD_IM_Len	EQU	4		; 4 ranges of RAM in instance data
VDD_IMV_Len	EQU	1*4+1Eh+5+1	; 1 pointer, 1Eh bytes, 5 bytes, 1 byte

;***************
; Init values for V_VertCnt and V_HorizCnt
VDD_VERT_PERIOD EQU	12		; Must be at lease 11 for Wordstar 2000
VDD_HORIZ_PERIOD EQU	255		; Trial Value must not be too big


;*****************************************************************************
;*****************************************************************************
; MACROS

;****************
; Macro for loading register with VDD CB ptr
SetVDDPtr MACRO VPTR_Reg, VMHand
IFNDEF	Vid_CB_Off
VxD_DATA_SEG NO_ALIGN
EXTRN	Vid_CB_Off:DWORD
VxD_DATA_ENDS
ENDIF
IFNB <VMHand>
 VMMCall Get_Cur_VM_Handle
ELSE
 Assert_VDD_VMH EBX,Pseudo_OK
ENDIF
 mov VPTR_Reg,[Vid_CB_Off]
 add VPTR_Reg,ebx
ENDM

;****************
; Macro that checks for valid pointers in registers
Assert_VDD_VMH MACRO R_Handle,Pseudo_OK
LOCAL AVP_Ok
IFDEF DEBUG
 pushfd
IFNB <Pseudo_OK>
IFNDEF Vid_Msg_Pseudo_VM
EXTRN Vid_Msg_Pseudo_VM:DWORD
ENDIF
 cmp ebx,[Vid_Msg_Pseudo_VM]
 je  SHORT AVP_Ok
ENDIF
Assert_VM_Handle R_Handle
AVP_Ok:
 popfd
ENDIF
ENDM

Assert_VDD_ptrs MACRO R_Handle,R_VDDptr,Pseudo_OK
LOCAL AVP_Ok
IFDEF DEBUG
IFNDEF Vid_CB_Off
EXTRN Vid_CB_Off:DWORD
ENDIF
Assert_VDD_VMH R_Handle,Pseudo_OK
 pushfd
 push R_VDDptr
 sub  R_VDDptr,[Vid_CB_Off]
 cmp  R_Handle,R_VDDptr
 pop  R_VDDptr
 je   SHORT AVP_Ok
Debug_Out "VDD ptr not correct, #&R_VDDptr"
AVP_Ok:
 popfd
ENDIF
ENDM


;
; This structure comes from the VGA display driver sources.  If the display
; driver doesn't call us thru a PM API to tell us where we can save/restore
; latches, then we assume that this structure is the last 16 bytes of page
; 0Bh in video memory.
;
Display_Driver_Data STRUC
current_brush	  db	8 dup (?)	;8 bytes for a brush
tonys_bar_n_grill db	?		;1 byte for a solid color
shadow_mem_status db	?		;Staus flags for upper 16/32K of mem
known_word	  dw	?		;Required locations for state
shadowed_mode	  db	?		;  detection code
plane_index	  db	?
enable_test	  db	?
saved_latches	  db	?
Display_Driver_Data ENDS

;
; flag bits in shadow_mem_status
;
SHADOW_EXISTS	equ	00000001b	;Shadow memory exists
SHADOW_IN_USE	equ	00000010b	;Shadow contains valid image
SHADOW_TRASHED	equ	00000100b	;Shadow contents have been destroyed


IFDEF DEBUG
IF1
IFNDEF Queue_Out
.err  debug.inc must be included before vdddef.inc
ENDIF
ENDIF
ENDIF
PURGE Queue_Out

;******************************************************************************
;
;   Queue_Out
;
;------------------------------------------------------------------------------

Queue_Out MACRO S, V1, V2
	LOCAL	Str_Off
IFDEF DEBUG

_LDATA SEGMENT
Str_Off db S, 0Dh,0Ah, 0
_LDATA ENDS

	pushfd
	push	esi
IFNB <V1>
    IF	TYPE V1 GT 0
	push	dword ptr V1
    ELSE
	push	V1
    ENDIF
ELSE
	push	eax		; dummy value1
ENDIF
IFNB <V2>
    IF	TYPE V2 GT 0
	push	dword ptr V2
    ELSE
	push	V2
    ENDIF
ELSE
	push	ebx		; dummy value2
ENDIF
	mov	esi, OFFSET32 Str_Off
IFNDEF VDD_Queue_Debug_String
EXTRN VDD_Queue_Debug_String:NEAR
ENDIF
	call	VDD_Queue_Debug_String
	pop	esi
	popfd
ENDIF
	ENDM
