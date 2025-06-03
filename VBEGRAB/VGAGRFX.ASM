;--------------------------------------------------------------------
;
;   Screen Grabber for IBM EGA/VGA adaptor
;
;   Graphics mode painting routines.
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
externFP	PatBlt
externFP	SelectObject
externFP	CreateCompatibleDC
externFP	CreateCompatibleBitmap
externFP	GetNearestColor
externFP	CreateSolidBrush
externFP	BitBlt
externFP	DeleteDC
externFP	DeleteObject
externFP	SetDIBits
externFP	SetDIBitsToDevice
externFP	CreateBitmap
externFP        GlobalAlloc
externFP        GlobalRealloc
externFP        GlobalLock
externFP        GlobalUnlock
externFP        GlobalFree

;-----------------------------------------------
;
; External GRABBER Procedures
;
externNP	SetBitBit
externNP	InvSel
externNP	InvSel2
externNP	LineBlt
externNP	BuildDIBHdr
externNP	XferMonoBits
externNP	ProcessWordD
externNP	ProcessDWordE10

sBegin	code
	assumes cs,code

	public	ModeGrfx
	public	CreateOverScanBrGrx
        public  AllocExtraRes
IFNDEF	GENGRAB
        public  SetBkBitsMode4
        public  SetMonoBits
        public  PixelDoubleModeD
        public  GetBkMaskDEF10
ENDIF
IFDEF   FASTGRAB
        public  DeAllocGrfxRes
ENDIF
;
; Procs shared by grab and paint code
;
        public  GetWinRGB
        public  InitFrameVars
        public  CheckMode
        public  PatBltOverScanColor
        public  BuildDisplayRect
        public  AllocCommonRes
        public  SetParamsCGAMode
        public  SetParamsMode11
IFDEF	MODE13
        public  SetParamsMode13
ENDIF
        public  SkipBkBits
        public  SetParamsPlanarMode
        public  DeAllocAllRes
        public  SetupLineBits
        public  GetDwordDataEF10
        public  GetWordDataD
;
; Table for conversion of IRGB bit color to Windows dword color
;   value. This table is specific to the 4 plane EGA Windows display
;   driver. 
; NOTE: The EGA driver has Low Int. white and gray as the same colors
;       The VGA drivers provides different colors however.
	public	RGBTable
RGBTable     Label   word
	dd	00000000H	; 0000	Black
	dd	00800000H	; 0001	Blue
	dd	00008000H	; 0010	Green
	dd	00808000H	; 0011	Cyan
	dd	00000080H	; 0100	Red
	dd	00800080H	; 0101	Magenta
	dd	00008080H	; 0110	Brown
	dd	00C0C0C0H	; 0111	White (low intensity)
	dd	00808080H	; 1000	Gray
	dd	00FF0000H	; 1001	Light Blue
	dd	0000FF00H	; 1010	Light Green
	dd	00FFFF00H	; 1011	Light Cyan
	dd	000000FFH	; 1100	Light Red
	dd	00FF00FFH	; 1101	Light Magenta
	dd	0000FFFFH	; 1110	Yellow
	dd	00FFFFFFH	; 1111	White (high intensity)

IFNDEF	GENGRAB

VGADAC	dd 0,2a0000h,2a00h,2a2a00h,2ah,2a002ah,2a2ah,2a2a2ah
	dd 150000h,3f0000h,152a00h,3f2a00h,15002ah,3f002ah,152a2ah,3f2a2ah
	dd 1500h,2a1500h,3f00h,2a3f00h,152ah,2a152ah,3f2ah,2a3f2ah
	dd 151500h,3f1500h,153f00h,3f3f00h,15152ah,3f152ah,153f2ah,3f3f2ah
	dd 15h,2a0015h,2a15h,2a2a15h,3fh,2a003fh,2a3fh,2a2a3fh
	dd 150015h,3f0015h,152a15h,3f2a15h,15003fh,3f003fh,152a3fh,3f2a3fh
	dd 1515h,2a1515h,3f15h,2a3f15h,153fh,2a153fh,3f3fh,2a3f3fh
	dd 151515h,3f1515h,153f15h,3f3f15h,15153fh,3f153fh,153f3fh,3f3f3fh

ENDIF

IFDEF	GENGRAB

RGBTable10      Label   word
dd 00000000h,00800000h,00008000h,00808000h,00000080h,00800080h,00008080h,00808080h
dd 00808080h,00FF0000h,00008000h,00FF8000h,00000080h,00FF0080h,00008080h,00FF8080h
dd 00000000h,00800000h,0000FF00h,0080FF00h,00000080h,00800080h,0000FF80h,0080FF80h
dd 00808080h,00FF0000h,0000FF00h,00FFFF00h,00000080h,00FF0080h,0000FF80h,00FF8080h

dd 00000000h,00800000h,00008000h,00808000h,000000FFh,008000FFh,000080FFh,008080FFh
dd 00808080h,00FF0000h,00008000h,00FF8000h,000000FFh,00FF00FFh,000080FFh,00FF80FFh
dd 00000000h,00800000h,0000FF00h,0080FF00h,000000FFh,008000FFh,0000FFFFh,0080FFFFh
dd 00808080h,00FF0000h,0000FF00h,00FFFF00h,000000FFh,00FF00FFh,0000FFFFh,00FFFFFFh


RGBTableDE      Label   word            
dd 00000000h,00800000h,00008000h,00808000h,00000080h,00800080h,00008080h,00C0C0C0h
dd 00000000h,00800000h,00008000h,00808000h,00000080h,00800080h,00008080h,00C0C0C0h
dd 00808080h,00FF0000h,0000FF00h,00FFFF00h,000000FFh,00FF00FFh,0000FFFFh,00FFFFFFh
dd 00808080h,00FF0000h,0000FF00h,00FFFF00h,000000FFh,00FF00FFh,0000FFFFh,00FFFFFFh

dd 00000000h,00800000h,00008000h,00808000h,00000080h,00800080h,00008080h,00C0C0C0h
dd 00000000h,00800000h,00008000h,00808000h,00000080h,00800080h,00008080h,00C0C0C0h
dd 00808080h,00FF0000h,0000FF00h,00FFFF00h,000000FFh,00FF00FFh,0000FFFFh,00FFFFFFh
dd 00808080h,00FF0000h,0000FF00h,00FFFF00h,000000FFh,00FF00FFh,0000FFFFh,00FFFFFFh

externB		XTableMode4

ENDIF

;*****************************************************************************
;
; GetWinRGB - Convert to Windows RGB format 
;
; ENTRY:
;	AL is IRGB in low 4 bits
;	DS:SI -> EXTPAINTSTRUC
; EXIT:
;	DX:AX is Windows RGB
; USES:
;	AX,DX,FLAGS
;
;*****************************************************************************
GetWinRGB proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing

    	bt	[si.GGrbArea.GrbStatusFlags],BlinkTurnedOffBit	; bit set ?
	jc	SHORT GRGB_Cont
        cmp     [si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],3
	jbe	SHORT GRGB_Cont
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],7
	je	SHORT GRGB_Cont
	or	ax,8				; set the 3rd bit
GRGB_Cont:
	push	bx
	and	ax,0000000000001111B		; Mask to bits of interest
	lea	bx,[si.EPGrabDTA.CntrlSt.VDA_EGA_Pal]
	xlat					; get palette entry
	push	edi
	push	es
	push	ecx
	mov	es,[si.RNG1DSSEL]
	mov	edi,[si.GGrbArea.VDDDACOffset]	; get dac offset
	movzx	ecx,al
	mov	ecx,es:[edi][ecx*4]		; get DAC entry
	movzx	ecx,cl				; next redirection
	mov	ecx,es:[edi][ecx*4]		; actual BGRIndex
	shr	ecx,8				; isolate dac values.
	mov	al,cl				; red
	mov	ah,ch				; green
	shr	ecx,8
	movzx	dx,ch				; blue
	shl	al,2				; scale red
	shl	ah,2				; scale grren
	shl	dl,2				; scale blue
	pop	ecx
	pop	es
	pop	edi

	pop	bx
	ret

GetWinRGB endp

IFNDEF	GENGRAB
;*******************************************
; matchpalette:
;	Given a palette entry, looks up the DAC table, tries to match
;	the dac entry with some entry in our table, and gets the corresponding
;	entry as the actual palette entry.
; ENTRY: AL = palette entry
; EXIT:	AL = palette entry
;*******************************************
matchpalette	proc near

	push	es
	push	edi
	push	ecx

	mov	es,[si.RNG1DSSEL]
	mov	edi,[si.GGrbArea.VDDDACOffset]	; get dac offset
	movzx	ecx,al
	mov	ecx,es:[edi][ecx*4]		; get dac entry
	movzx	ecx,cl				; dac index
	mov	ecx,es:[edi][ecx*4]		; dac entry
	shr	ecx,8				; RGB in ecx
	push	eax
	mov	eax,ecx
	and	eax,3f3f3fh			; only 6 bits are important
	mov	ecx,64				; #DAC entries in table
	mov	di, codeOffset VGADAC
	movzx	edi,di
	push	cs
	pop	es				; es:edi -> VGADAC table
	repnz	scasd				; search
	jnz	SHORT DAC_Notmatched		; couldn't find DAC
DAC_Xlate:
	pop	eax				; get back eax
	mov	al,63
	sub	al,cl
	jmp	SHORT DAC_Matched
DAC_NotMatched:
	mov	di,codeoffset VGADAC
	push	ebx
	mov	ebx,eax
	sub	bl,10
	jns	SHORT blfixed
	xor	bl,bl
blfixed:
	sub	bh,10
	jns	SHORT bhfixed
	xor	bh,bh
bhfixed:
	rol	ebx,16
	sub	bl,10
	jns	SHORT hiblfixed
	xor	bl,bl
hiblfixed:
	rol	ebx,16
	add	eax,0a0a0ah			; Upper limit to look for
	xor	ecx,ecx
Cont_Dac_Approx:
	call	comparethisentry
	jz	SHORT DAC_ApproxDone
	inc	cl
	cmp	cl,64
	jnz	SHORT Cont_Dac_Approx
	pop	ebx
	pop	eax
	jmp	SHORT DAC_Matched		; without success
DAC_ApproxDone:
	pop	ebx
	pop	eax
	mov	al,cl
DAC_Matched:
	pop	ecx
	pop	edi
	pop	es
	ret
matchpalette	endp

comparethisentry proc near
	cmp	ebx,es:[edi][ecx*4]	; testing lower limit
	ja	SHORT NotInRange
	cmp	eax,es:[edi][ecx*4]
	jb	SHORT NotInRange
	xor	al,al			; set zero
NotInRange:
	ret
comparethisentry endp

ENDIF

IFNDEF	GENGRAB
;*****************************************************************************
;
; SetLineBitsMode4 - Sets bits in one color plane of LineBits
;                    Mode 4,5 only (Paint code only)   
;
; Process a dword of pixel info in EAX(2 bpp, 16 pixels)
; 
; For each 2 bit pel value      {               
;    get Palette contents
;    if (Palette has the given color)
;        set bits in LineBits at that color plane
; }
;
; ENTRY: DS:SI -> I/R/G/B plane in LineBits
;        EAX = a dword from video memory
;        DH = 00000011B, DL = 11111100 - masks for extracting 2 bit pel value
;        EDI = Mask for Bk bits
;
; Parameters:
;       Label1 - Loop label
;       Label2 - 
;       ColorMask - mask to look at the color bit in the Palette contents,
;               00010000 for looking at I bit
;               00000100 for looking at R bit
;               00000010 for looking at G bit
;               00000001 for looking at B bit
;
; EXIT:  Bits stored in LineBits at the current plane that SI points to 
;        and advances SI to next color plane.
;
; USES : CX, BX
;        
;*****************************************************************************

SetLineBitsMode4        MACRO Label1, Label2, ColorMask 

	push	eax
	mov	cx,16			;; 16 PELs per dword
&Label1:
	test	al,dh			;; Background PEL?
	jz	short &Label2		;; Yes
    ;;
    ;; The two bits of the PEL tell us which Palette register (1-3) to use
    ;;
	push	ax
	lea	bx,Palette0
	xor	ah,ah
	and	al,dh			;; AX is PEL value
	add	bx,ax
	mov	bh,byte ptr ss:[bx]	;; Get Palette for this PEL
	pop	ax
	and	al,dl			;; Turn off bits
	test	bh, &ColorMask		;; Given color in PEL?
	jz	short &Label2		;; No
	or	al,dh			;; Yes, set bits
&Label2:
	ror	eax,2
	loop	short &Label1
	and	dword ptr [si],edi	;; Erase background at foreground pix
	or	dword ptr [si],eax	;; Set given color for foreground bits
	pop	eax

        ENDM
ENDIF

;*****************************************************************************
;
; AllocExtraRes - Allocate additional resources for paint code 
;                 (Paint code only)
;
; ENTRY: DS:SI -> EXTPAINTSTRUC
;
; EXIT: carry flag set if error
;
;*****************************************************************************

AllocExtraRes proc near

IFDEF   FASTGRAB
    ;
    ; If we're using the persistent objects, don't bother creating
    ; the temporary ones
    ;
        cmp     [fpScanBuf].sel,0
        jne     short AERDone
ENDIF
    ;
    ; Create a memory DC for one line compatible with the display
    ;
	cCall	CreateCompatibleDC,<[si.Pstruct.psHdc]>
	or	ax,ax
	jz	short AERError
	mov	LineDC,ax
    ;
    ; Create a one line bitmap as wide as the dword rounded paint rect
    ;
	cCall	CreateCompatibleBitmap,<[si.Pstruct.psHdc],DDRCWid,1>
	or	ax,ax
	jz	short AERError
	mov	LineBitMap,ax
    ;
    ; Select the one line bitmap into the one line DC
    ;
	cCall	SelectObject,<LineDC,ax>
	or	ax,ax
	jz	short AERError
    ;
    ; Select the background brush into the line DC
    ;
	cCall	SelectObject,<LineDC,BkBrush>
	or	ax,ax
	jz	short AERError

AERDone:
        clc
        ret

AERError:
        stc
        ret

AllocExtraRes endp

IFNDEF	GENGRAB

;*****************************************************************************
;
; SetBkBitsMode4 - Set Background bits in LineBits for mode 4,5
;                  (Paint code only)
;
; ENTRY: es:edi -> LineBits
; 
; EXIT: es:edi -> LineBits, Background color stored in LineBits      
;
;*****************************************************************************
SetBkBitsMode4 proc near
    ;
    ; Mode 4, 320 pel, 2 bits/pel line
    ;
	push	di
	cld
    ;
    ; First blit in the background color (Palette0)
    ;
	xor	eax,eax 		; Assume no red in background
	test    Palette0, 00000100B	; Red in background?
	jz	short SetRedB		; No, assumption correct
	dec	eax			; Red in background
SetRedB:
	mov	cx,DDPWid		; This many dwords in plane
	rep	stosd

	xor	eax,eax 		; Assume no Green in background
	test    Palette0, 00000010B	; Green in background?
	jz	short SetGrnB		; No, assumption correct
	dec	eax			; Green in background
SetGrnB:
	mov	cx,DDPWid		; This many dwords in plane
	rep	stosd

	xor	eax,eax 		; Assume no Blue in background
	test    Palette0, 00000001B	; Blue in background?
	jz	short SetBluB		; No, assumption correct
	dec	eax			; Blue in background
SetBluB:
	mov	cx,DDPWid		; This many dwords in plane
	rep	stosd

	xor	eax,eax 		; Assume no Intensity in background
	test    Palette0, 00010000B	; Intensity in background?
	jz	short SetIntB		; No, assumption correct
	dec	eax			; Intensity in background
SetIntB:
	mov	cx,DDPWid		; This many dwords in plane
	rep	stosd


	pop	di
        ret

SetBkBitsMode4 endp

;*****************************************************************************
;
; SetLineBitsMode6 - Sets bits in one color plane of LineBits 
;                    Modes 6 and 11 (Paint code only)
; ENTRY:
;  DS:ESI -> Line in Vid mem
;  ES:EDI -> LineBits
;
;  ColorMask 00010000 for setting bits in the Intensity Plane
;  ColorMask 00000100 for setting bits in the Red Plane
;  ColorMask 00000010 for setting bits in the Green Plane
;  ColorMask 00000001 for setting bits in the Blue Plane
;
; Description:
; Setup BH,BL
;     BH is non zero if given color present in the Bk color
;     BL is non zero if given color present in the Fg color
; Then call SetBitBit to set the bits in LineBits.
;
;*****************************************************************************

SetLineBitsMode6     MACRO   ColorMask

        push    esi             ; save ptr in Vid mem
        mov     bh, Palette0
        mov     bl, Palette1
        and     bh, &ColorMask  ; Color in Bk?
        and     bl, &ColorMask  ; Color in Fg?
        call    SetBitBit
        pop     esi             ; recover Vid mem ptr

        ENDM


;*****************************************************************************
; 
; SetMonoBits - Set bits in Linebits - Mode 6 and 11 only
;               (Paint code only)
;
; ENTRY: ES:EDI -> LineBits
;        ES:EDX -> start of line (in Vid mem)
;
;*****************************************************************************

SetMonoBits proc near
	mov	ds,VidSel
	mov	esi,edx 		; ds:esi -> start of line
    ;
    ; Set bits in the R,G,B,I planes in LineBits
    ;
        SetLineBitsMode6 00000100B      ; set bits in the R Plane
        SetLineBitsMode6 00000010B      ; set bits in the G Plane
        SetLineBitsMode6 00000001B      ; set bits in the B Plane
        SetLineBitsMode6 00010000B      ; set bits in the I Plane

        ret

SetMonoBits endp

;
; Table for mode D bit doubling of low nibble to byte
;
NibbleDoubleTable label byte
	db	00000000B			; 0000
	db	00000011B			; 0001
	db	00001100B			; 0010
	db	00001111B			; 0011
	db	00110000B			; 0100
	db	00110011B			; 0101
	db	00111100B			; 0110
	db	00111111B			; 0111
	db	11000000B			; 1000
	db	11000011B			; 1001
	db	11001100B			; 1010
	db	11001111B			; 1011
	db	11110000B			; 1100
	db	11110011B			; 1101
	db	11111100B			; 1110
	db	11111111B			; 1111

;*****************************************************************************
;
; BitDoubleWord - Bit Double the word in AX to get a dword in EAX
;                 Used in Mode D pixel doubling.
;                 (Paint code only)
; ENTRY:
;       AX = Word to be bit doubled
;       BX = ptr to NibbleDoubleTable
; EXIT:
;       Word in AX bit doubled to a dword in EAX
;
;*****************************************************************************

BitDoubleWord   MACRO   

	sar	ax,1			; Double Bit 15
	rcl	eax,1
	shl	eax,1
	sar	ax,1			; Double Bit 14
	shl	eax,2
	sar	ax,1			; Double Bit 13
	shl	eax,2
	sar	ax,1			; Double Bit 12
	shl	eax,2
	sar	ax,1			; Double Bit 11
	shl	eax,2
	sar	ax,1			; Double Bit 10
	shl	eax,2
	sar	ax,1			; Double Bit 9
	shl	eax,2
	sar	ax,1			; Double Bit 8
	shl	eax,2
	xchg	ah,al			; High byte (bits 0-7) to AL
	sar	al,1			; Double Bit 7
	rcl	ax,1
	shl	ax,1
	sar	al,1			; Double Bit 6
	shl	ax,2
	sar	al,1			; Double Bit 5
	shl	ax,2
	sar	al,1			; Double Bit 4
	shl	ax,2
	shr	al,4			; Bits 4-7 to bits 0-3 of AL
	xlat	cs:[bx] 		; Double bits 0-3
        
        ENDM

;*****************************************************************************
; 
; PixelDoubleModeD - Bit double pixel info in AX to EAX and so on
;                    (Paint code only)   
;
; Used by paint code only, bit double AX to EAX (I bits)
;                                     BX to EBX (R bits)
;                                     CX to ECX (G bits)   
;                                     DX to EDX (B bits)
;
;*****************************************************************************
PixelDoubleModeD proc near
    ;
    ; Must bit double word to a dword in mode D
    ;
    ;  NOTE!!!!!!!! The 8086 family is byte swapped!!!!!
    ;	for correct doubling the nibbles must be reversed!
    ;
	rol	dl,4			; Reverse nibbles for doubling
	rol	dh,4
	rol	cl,4			; Reverse nibbles for doubling
	rol	ch,4
	rol	bl,4			; Reverse nibbles for doubling
	rol	bh,4
        rol     al, 4                   ; Reverse nibbles for doubling
        rol     ah, 4                   
    ;
    ; DX is Blue bits,CX is Green,BX is Red,AX is Intensity 
    ; SI is background mask
    ;
	mov	esi,ebx 		; save red info 
	mov	bx,codeOffset NibbleDoubleTable
    ;
    ; Double INTENSITY, Bit Double AX to EAX
    ;
        BitDoubleWord                   ; Bit double AX to EAX  
    ;
    ; Double RED, Bit Double SI to ESI
    ;
        xchg    eax,esi
        BitDoubleWord                   ; Bit double AX to EAX  
        xchg    eax,esi
    ;
    ; Double Green, Bit Double CX to ECX
    ;
	xchg	eax,ecx 		
        BitDoubleWord                   ; Bit double AX to EAX  
	xchg	eax,ecx 		
    ;
    ; Double BLUE, Bit Double DX to EDX
    ;
        xchg    eax, edx
        BitDoubleWord                   ; Bit double AX to EAX  
        xchg    eax, edx

	mov	ebx,esi 		; RED back in EBX
        ret
PixelDoubleModeD endp

;*****************************************************************************
;
; GetBkMaskDEF10 - return a mask for the background bits in ESI
;                 (Paint code only)
;
; ENTRY: I,R,G,B info in EAX,EBX,ECX,EDX
;
; EXIT: return in ESI mask for background bits
;
;*****************************************************************************
GetBkMaskDEF10 proc near

	mov	esi,edx 		; OR blue into background mask
	or	esi,ecx 		; OR green into background mask
	or	esi,ebx 		; OR Red into background mask
        or      esi,eax                 ; OR Intensity into background mask
	not	esi			; 1s in spots which are background
        ret

GetBkMaskDEF10 endp

ENDIF

;*****************************************************************************
;
; NOTE:
;
; The following procs are shared by the paint and the grab code
; The paint code is in ModeGrfx, grab code is in GrabModeGrfx
;
;*****************************************************************************

;*****************************************************************************
; Initialize frame variables used by grab and paint code
;
;*****************************************************************************
InitFrameVars proc near
	xor	bx,bx
	mov	LineDC,bx               ; not used during grabs
	mov	LineBitMap,bx           ; not used during grabs
	mov	ScreenDC,bx
	mov	ScreenBitMap,bx
	mov	BkBrush,bx
	mov	OvscnBrsh,bx
IFDEF   FASTGRAB
        mov     [fpScanBuf].sel,bx
ENDIF
	mov	Gmode,ah
        mov     SavEXTP,si
        ret
InitFrameVars endp

;*****************************************************************************
; CheckMode - Check for valid EGA/VGA mode
;
; ENTRY: AH = video mode
;        DS:SI -> EXTPAINTSTRUC
;
; EXIT:  Carry set if mode is invalid
;
;*****************************************************************************
CheckMode proc near

IFDEF	VGA
	cmp	ah,13H
    IFDEF MODE13
	ja	short BadMode
    ELSEIFDEF DEBUG
	ja	short BadMode
	je	short GrbProblem
    ELSE
	jae	short BadMode
    ENDIF
ELSE
	cmp	ah,10H
	ja	short BadMode
ENDIF
	cmp	ah,7
	jb	short CMDone
	cmp	ah,0DH
	jae	short CMDone
BadMode:
IFDEF DEBUG
	mov	bx,si
	mov	esi,codeOffset ModeErr
	mov	edx,SHELL_Debug_Out
	call	[bx.ShellCall]
	jmp	short CMContinue
ModeErr  db	 "Grabber bad video mode in AH (paint/grab)",0
CMContinue:
        mov     si,bx
ENDIF
GrbProblem:
        stc
        ret
CMDone:
        clc
        ret
CheckMode endp

;*****************************************************************************
;
; PatBltOverScanColor - PatBlt the overscan color into the paint rect
;
; Called when the paint rect is off screen
; Creates OverScan brush. Deletes it after the PatBlt
;
;*****************************************************************************
PatBltOverScanColor proc near

	call	CreateOverScanBrGrx
	jz	short DeleteOverScanBr	; Hmmm.... Barfed don't complain though
	push	ax  		        ; Save old brush
	lea	di,[si.Pstruct.PSrcPaint]
	mov	ax,[di.rcRight]
	sub	ax,[di.rcLeft]
	mov	dx,[di.rcBottom]
	sub	dx,[di.rcTop]
    ;
    ; PatBlt(hDC,X,Y,nWidth,nHeight,PATCOPY_H,PATCOPY_L)
    ;
	cCall	PatBlt,<[si.Pstruct.psHdc],[di.rcLeft],[di.rcTop],ax,dx,PATCOPY_H,PATCOPY_L>
	pop	ax			; Recover previous brush
	cCall	SelectObject, <[si.Pstruct.psHdc],ax>
    ;
    ; Delete Overscan brush if any
    ;
DeleteOverScanBr:
        mov     cx,OvscnBrsh
        jcxz    short NoOverScanBr
        cCall   DeleteObject, <cx>
NoOverScanBr:
        ret        
PatBltOverScanColor endp

;*****************************************************************************
;
; BuildDisplayRect - Build display paint rectangle. 
;                    (Paint Rect CoOrds rounded to dword aligned values)
;
; ENTRY: DS:SI -> EXTPAINTSTRUC
; 
; EXIT: Zero flag set - rect is offscreen OR invalid paint rect
;                                            (bot < top or right < left)
;
;*****************************************************************************
;
BuildDisplayRect proc near

	mov	bx,[si.PGVDRect.rcLeft]
	and	bx,1111111111100000B	; Round down to DWORD (32 bit) boundary
	cmp	bx,GrxBitWid640		; Is paint rect "on screen"?
	jae	RectOffScreen		; No
	mov	DDRCLeft,bx
IFDEF	MODE13
	cmp	ah,13H
	je	@F			; 1pix==1byte, but screen half as wide
ENDIF
	shr	bx,3			; Divide by 8 for Byte index of this loc
	cmp	ah,0DH			; Q: Mode 0D?
	jne	short SetBI             ;   N:
@@:	shr	bx,1			;   Y: screen is half as wide
SetBI:
	mov	DDRCLeftBI,bx
	mov	bx,[si.PGVDRect.rcRight]
	add	bx,31
	and	bx,1111111111100000B	; Round up to DWORD (32 bit) boundary
	cmp	bx,GrxBitWid640		; Limit to max size of physical screen
	jbe	short OkBWid
	mov	bx,GrxBitWid640
OkBWid:
	mov	DDRCRight,bx
	sub	bx,DDRCLeft
IFDEF	MODE13
	jbe	InvalidCoOrd
ELSE
	jbe	short InvalidCoOrd
ENDIF
	mov	DDRCWid,bx
IFDEF	MODE13
	shr	bx,1			; at least account for the doubling of pixels
	cmp	ah,13H
	je	@F			; 1pix==1byte, no further division needed
	shr	bx,2			; divide again by four to convert half-bits to bytes
@@:
ELSE
	shr	bx,3			; Divide Width by 8 to get width in Bytes
ENDIF
	mov	DBPWid,bx		; NOTE: For mode 0D display this is width in NIBBLES
	mov	BDsWid,bx
	cmp	ah,0DH			; Q: Mode 0D?
	jne	short NoDv3             ;   N:
	shr	BDsWid,1		;   Y: screen if half as wide
NoDv3:
	shr	bx,2			; Divide Width by 32 to get width in DWORDS
	mov	DDPWid,bx		; NOTE: For mode 0D display this is width in WORDS!
	mov	bx,[si.PGVDRect.rcTop]
    ;
    ; What follows is to round the top and height to a mult of 4 except in mode 10H.
    ;  We do this so that the first line is always an even scan line, and
    ;  the height represents equal numbers of even and odd scan lines. This
    ;  prevents us from having to do wierd boundary checks to make sure we
    ;  don't overflow the full screen bitmap.
    ;
	mov	cx,0FFFFH		; Top, Height round is none
	xor	dx,dx			; Top, Height round is none
IFDEF VGA
IFDEF MODE13
	cmp	ah,13H
	je	short @F		; Mode 13 is only 400 and needs rounding!
ENDIF
	mov	di,GrxBitHeight480	; Max height of mode 11,12H
	cmp	ah,11H
	jae	short GotVals
@@:
ENDIF
	mov	di,GrxBitHeight350	; Max height of mode 10H
	cmp	ah,10H
	je	short GotVals
	cmp	ah,0FH
	je	short GotVals
	mov	di,GrxBitHeight400 	; Max height of other modes
	inc	dx			; Top, Height round is 2 modes D and E
	dec	cx			; Top, Height round is 2 modes D and E
	cmp	ah,0DH
	jae	short GotVals		; Modes D,E have round of 2
	mov	cx,1111111111111100B	; Top, Height round is 4 on CGA modes
	mov	dx,3			; Top, Height round is 4 on CGA modes
GotVals:
	and	bx,cx			; Round top down to mult
	cmp	bx,di			; Is paint rect "on screen"?
	jae	short RectOffScreen		; NO
	mov	DDRCTop,bx
	mov	ax,[si.PGVDRect.rcBottom]
	cmp	ax,di
	jbe	short OkBHig2 		; Limit to physical screen
	mov	ax,di
OkBHig2:
	sub	bx,ax
	jae	short InvalidCoOrd
	neg	bx
	add	bx,dx			; Round height up to mult
	and	bx,cx
	cmp	bx,di			; Limit to height of physical screen
	jbe	short OkBHig
	mov	bx,di
OkBHig:
	mov	DDRCHig,bx
        mov     ax,1                    
        or      ax,ax                   ; clear zero flag 
        ret
RectOffScreen:
    ;
    ; PatBlt the overscan color into the paint rect and return
    ;
        call    PatBltOverScanColor
InvalidCoOrd:
        mov     ax,0
        or      ax,ax                   ; set zero flag
        ret

BuildDisplayRect endp

;*****************************************************************************
;
; SetParamsCGAMode - Return index into video memory for the first line and
;                     number of lines to paint, for Modes 4,5,6
;
; ENTRY: DS:SI -> EXTPAINTSTRUC
;
; EXIT: ES:EDI -> first line of paint rect
;       CX = # of lines in paint rect
;
;*****************************************************************************
SetParamsCGAMode proc near

	les	edi,VidAddr             ; es:edi -> Video page 0

	xor	edx,edx 		; Assume doing evens, Vid pgs 0 and 1
	test	GrbFlags,GrbFlgs_GrfxDoOdd
	jz	short AddPageIndex	; Assumption correct
	mov	edx,2 * 4096		; Doing odds, vid pgs 2 and 3
    ;
    ; Note: The even scans run from B8000 -> BA000 which is two pages
    ;	    The odd scans run from BA000 -> BC000 which is two pages
    ;
AddPageIndex:
	add	edi,edx 		; Point to start of evens or odds

	mov	ax,DDRCTop		; Get index to first line
	shr	ax,2			; Convert to phys disp and /2 for even or odd
    ; 
    ; Mode 4,5 - 2 bpp and 320 pels wide
    ; Mode 6   - 1 bpp and 640 pels wide
    ; i.e. in both cases 640 bits/line or (640/8) bytes/line
    ; 
	mov	cx,GrxBitWid640/8	; This many bytes per line
	mul	cx			; This many bytes in

	movzx	eax,ax
	add	edi,eax 		; Point to start of this line
	mov	cx,DDRCHig		; This many lines to do
	shr	cx,2			; Convert to phys disp and evens and odds are half of screen
	movzx	edx,DDRCLeftBI
	add	edi,edx 		; Index to left edge in display mem
        ret

SetParamsCGAMode endp

;*****************************************************************************
;
; SetParamsMode11 - Set params for Mode 11
; 
; ENTRY: 
;
; EXIT: ES:EDI -> first line of paint rect
;       CX = # of lines to paint
;
;*****************************************************************************

SetParamsMode11 proc near

	mov	ax,DDRCTop		; Get index to first line
	mov	cx,GrxBitWid640/8	; This many bytes per line
	mul	cx			; This many bytes in
	les	edi,VidAddr             ; es:edi -> Video page 0
	movzx	eax,ax
	add	edi,eax 		; Point to start of this line
	mov	cx,DDRCHig		; This many lines to do
	movzx	edx,DDRCLeftBI		; Index to left edge in display mem
	add	edi,edx
        ret

SetParamsMode11 endp

IFDEF	MODE13
;*****************************************************************************
;
; SetParamsMode13 - Set params for Mode 13
; 
; ENTRY: 
;
; EXIT: ES:EDI -> first line of paint rect
;       CX = # of lines to paint
;
;*****************************************************************************

SetParamsMode13 proc near

	mov	ax,DDRCTop		; Get index to first line
	shr	ax,1			; Convert to phys disp
	mov	cx,GrxBitWid640/2	; This many bytes per line
	mul	cx			; This many bytes in
	les	edi,VidAddr             ; es:edi -> Video page 0
	movzx	eax,ax
	add	edi,eax 		; Point to start of this line
	mov	cx,DDRCHig		; This many lines to do
	shr	cx,1			; Convert to phys disp
	movzx	edx,DDRCLeftBI		; Index to left edge in display mem
	add	edi,edx
        ret

SetParamsMode13 endp
ENDIF

;*****************************************************************************
;
; SkipBkBits - Skip across background bits(modes 4,5,6,11 only)
;
; ENTRY: es:edi -> start of line in video memory
;        
; EXIT:  es:edx -> start of line
;        If (Zero flag set)
;               Only Bk bits in the line
;        else
;               es:edi -> first non-bk dword  in the line
;
;*****************************************************************************

SkipBkBits proc near
    ;
    ; Look for non-background Bits
    ; Mode 4,5 - convert to phy display(/2) and 2 bpp(*2)
    ; Thus width in mode 4,5 = (DDPWid/2)*2 dwords
    ; Mode 6,11   - 1 bpp and phy disp 640 wide
    ; Mode 6,11 is DDPWid dwords
    ;
    ;	If memory is not allocated, indicates all bits are background
    ;
	mov	edx,edi 		; Save start of this line
	movzx	ecx,DDPWid		; This many Dwords wide
	mov	es,VidSel
	lea	eax,[edx][ecx*4]
	sub	eax,PGOffSt
        cmp     eax,[MemState].VDA_Mem_Size_P0  ; Q: At end of vid mem?
	jae	SHORT SBB_NoMem
	xor	eax,eax
	cld
	repe	scas dword ptr es:[edi] ; Look for non background
        ret
SBB_NoMem:
IFDEF DEBUG
	push	esi
	push	edx
	mov	esi,codeOffset SkipErr
	mov	edx,SHELL_Debug_Out
	call	[bx.ShellCall]
	jmp	short SBBContinue
skipErr  db	 "Grabber: skip line ending at offset [AX], no video save memory"
SBBContinue:
	pop	edx
	pop	esi
ENDIF
	lea	edi,[edi][ecx*4]	; EDI = first DWORD beyond line
	xor	eax,eax 		; Set zero flag
	ret

SkipBkbits endp


;*****************************************************************************
;
; AllocCommonRes - Allocate resources common to paint code and grab code
;
; ENTRY: DS:SI -> EXTPAINTSTRUC
;
; EXIT: carry flag set if error
;
;*****************************************************************************

IFDEF   FASTGRAB
ModeTableEntry  equ 7           ; size of a modetable entry

ModeTable label byte
        db      10h             ; mode 10h (640x350)
        dw      GrxBitWid640    ;
        dw      53              ; maximum scanlines that can span a 4k page
        dw      (GrxBitWid640/8)*4*53
        db      12h             ; mode 12h (640x480)
        dw      GrxBitWid640    ;
        dw      53              ; maximum scanlines that can span a 4k page
        dw      (GrxBitWid640/8)*4*53
ModeTableEnd label byte
ENDIF

AllocCommonRes proc near

IFDEF   FASTGRAB
        push    di

	test	[si.SelStruc.GrabArea.SelecFlags],SelectOn
	jnz	ACRSlow
        test    GrbFlags,GrbFlgs_GrfxGrabBM OR GrbFlgs_GrfxInvPal  
        jnz     ACRSlow         ; if grabbing, do it the old way

        mov     al,[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode]
        mov     di,codeOffset ModeTable

ACRMode:
        cmp     al,cs:[di]      ; is this mode supported fast?
        je      short ACRFast   ; yes
        add     di,ModeTableEntry
        cmp     di,codeOffset ModeTableEnd
        jb      ACRMode         ; continue looking for mode match

        cmp     [si.EPGrabDTA.GrfxhDC],0; is an old DC laying around?
        je      ACRSlow         ; no
        call    DeAllocAllRes   ; yes, clean everything up first
        jmp     ACRSlow         ;

ACRFast:
        cmp     al,[si.EPGrabDTA.GrfxMode]
        je      short ACRCont   ;
        mov     [si.EPGrabDTA.GrfxMode],al
        call    DeAllocGrfxRes  ; mode has changed, free old stuff first

ACRCont:
        cmp     [si.EPGrabDTA.GrfxhDC],0; do we already have a DC?
        jne     short ACRJustLock
    ;
    ; Create a memory DC for full screen compatible with the display
    ;
	cCall	CreateCompatibleDC, <[si.Pstruct.psHdc]>
	or	ax,ax
        jz      ACRError
        mov     [si.EPGrabDTA.GrfxhDC],ax
    ;
    ; Create the "full page" bitmap used to blt lines to the screen.
    ; If this fails (lack of memory), then continue execution using the old
    ; method.
    ;
        cCall   CreateCompatibleBitmap,<[si.Pstruct.psHdc], cs:[di+1], cs:[di+3]>
	or	ax,ax
        jz      ACRSlow
        mov     [si.EPGrabDTA.GrfxhBitmap],ax
    ;
    ; Allocate a scanline conversion buffer that is large enough for at
    ; least one page of data.  If this fails (lack of memory), then free the
    ; above bitmap and continue execution using the old method...
    ;
        cCall   GlobalAlloc,<GMEM_MOVEABLE+GMEM_ZEROINIT+GMEM_DISCARDABLE, 0, cs:[di+5]>

        mov     [si.EPGrabDTA.GrfxhScanBuf],ax
	or	ax,ax
        jnz     short ACRPrepLock

        cCall   DeleteObject,<[si.EPGrabDTA.GrfxhBitmap]>
        mov     [si.EPGrabDTA.GrfxhBitmap],0
        jmp     short ACRSlow

ACRPrepLock:
    ;
    ; Select the bitmap into the memory DC
    ;
        cCall   SelectObject,<[si.EPGrabDTA.GrfxhDC],[si.EPGrabDTA.GrfxhBitmap]>
	or	ax,ax                   
        jz      ACRError

ACRJustLock:
        cCall   GlobalLock,<[si.EPGrabDTA.GrfxhScanBuf]>
        or      dx,dx           ; did lock succeed?
        jnz     short ACRLocked ; yes

        cCall   GlobalRealloc,<[si.EPGrabDTA.GrfxhScanBuf], 0, cs:[di+5], GMEM_MOVEABLE+GMEM_ZEROINIT+GMEM_DISCARDABLE>
        or      ax,ax           ; did realloc succeed?
        jz      short ACRError  ; no
        mov     [si.EPGrabDTA.GrfxhScanBuf],ax

        cCall   GlobalLock,<ax>
        or      dx,dx           ; did lock succeed?
        jz      short ACRError  ; no

ACRLocked:
        mov     [fpScanBuf].off,ax
        mov     [fpScanBuf].sel,dx
        mov     [pScanCur],ax
        mov     ax,cs:[di+5]
        mov     [pScanMax],ax
        xor     ax,ax           ; we don't need AX = 0 so much as carry clear
        mov     [nScanLines],ax
        jmp     short ACRDone

ACRSlow:

ENDIF  ;FASTGRAB
    ;
    ; Create a memory DC for full screen compatible with the display
    ;
	cCall	CreateCompatibleDC, <[si.Pstruct.psHdc]>
	mov	ScreenDC,ax
	or	ax,ax
	jz	short ACRError
    ;
    ; Set the background color
    ;
	xor	ax,ax		; The background is color palette 0
	call	GetWinRGB	; Get bkgrnd color
	mov	BcolHigh,dx
	mov	BcolLow,ax
    ;
    ; Create a brush in the background color
    ;
	cCall	GetNearestColor,<[si.Pstruct.psHdc],BColHigh,BColLow>

	push	dx
	push	ax
	cCall	CreateSolidBrush

	mov	BkBrush,ax
	or	ax,ax
	jz	short ACRError
    ;
    ; Select the background brush into the screen DC
    ;
	cCall	SelectObject,<ScreenDC,ax>
	or	ax,ax                   
        jnz     short ACRDone

ACRError:
        stc

ACRDone:
IFDEF   FASTGRAB
        pop     di
ENDIF
        ret

AllocCommonRes endp

;*****************************************************************************
;
; DeAllocAllRes - Deallocate all allocated resources 
;
; ENTRY: DS:SI -> EXTPAINTSTRUC
;
; EXIT: Resources if allocated are deallocated
;
;*****************************************************************************

DeAllocAllRes proc near

IFDEF   FASTGRAB
        cmp     [fpScanBuf].sel,0
        je      short DAAGrfx
    ;
    ; Because fpScanBuf.sel is non-zero, we were using the persistent
    ; DC, Bitmap and ScanBuf, which stay around until the app changes
    ; modes or terminates -- we should not have been using the temporary
    ; LineDC, LineBitmap, ScreenDC or ScreenBitmap variables (those
    ; objects should not exist) -- so just unlock ScanBuf and leave
    ;
        cCall   GlobalUnlock,<[si.EPGrabDTA.GrfxhScanBuf]>
        jmp     short DAAOverScanBr
    ;
    ; If fpScanBuf.sel IS zero, then there's probably just temporary
    ; objects to free, but we also need to check for any existing
    ; persistent objects, in case some error occurred while attempting to
    ; create a persistent object
    ;
DAAGrfx:
        call    DeAllocGrfxRes
ENDIF

DAALDC:
	mov	cx,LineDC
        jcxz    short DAALBM
	cCall	DeleteDC,<cx>
DAALBM:
	mov	cx,LineBitMap
        jcxz    short DAASDC
	cCall	DeleteObject,<cx>
DAASDC:
	mov	cx,ScreenDC
        jcxz    short DAASBM
	cCall	DeleteDC,<cx>
DAASBM:
	mov	cx,ScreenBitMap
        jcxz    short DAABkBr
	bt	GrbFlags,GrbFlgs_GrfxGrabBMBit	; Keep This?
        jc      short DAABkBr                   ; Yes
	cCall	DeleteObject,<cx>
DAABkBr:
	bt	GrbFlags,GrbFlgs_GrfxDispBltBit
        jnc     short DAADelBkBr
    ;
    ; Select back the Old brush into hDC and then delete the BkBrush
    ;
	cCall	SelectObject,<[si.Pstruct.psHdc],SavOldBr>
DAADelBkBr:
	mov	cx,BkBrush
        jcxz    short DAAOverScanBr
	cCall	DeleteObject,<cx>
DAAOverScanBr:
	mov	cx,OvscnBrsh
	jcxz	short DAADone
	cCall	DeleteObject,<cx>
DAADone:
	ret

DeAllocAllRes endp

IFDEF   FASTGRAB

;*****************************************************************************
;
; DeAllocGrfxRes - Deallocate all allocated resources for graphics mode
;
; ENTRY: DS:SI -> EXTPAINTSTRUC
;
; EXIT: Resources if allocated are deallocated
;
;*****************************************************************************

DeAllocGrfxRes proc near

        mov     cx,[si.EPGrabDTA.GrfxhDC]
        jcxz    short DAGBM
        cCall   DeleteDC,<cx>
        mov     [si.EPGrabDTA.GrfxhDC],0
DAGBM:
        mov     cx,[si.EPGrabDTA.GrfxhBitmap]
        jcxz    short DAGSB
        cCall   DeleteObject,<cx>
        mov     [si.EPGrabDTA.GrfxhBitmap],0
DAGSB:
        mov     cx,[si.EPGrabDTA.GrfxhScanBuf]
        jcxz    short DAGDone
        cCall   GlobalFree,<cx>
        mov     [si.EPGrabDTA.GrfxhScanBuf],0
DAGDone:
	ret

DeAllocGrfxRes endp

ENDIF  ;FASTGRAB

;*****************************************************************************
;
; SetParamsPlanarMode - Used only for modes D,E,F,10
; 
; ENTRY:
;
; EXIT: Sets up 
;       VideoIndex = offset of the first line in Video mem
;         LineSkip = Bytes to skip to next line of Paint rect in Vid mem
;               CX = # of lines
;
;*****************************************************************************
SetParamsPlanarMode proc near
    ;
    ; Skip in to first line of paint
    ;
	mov	ax,DDRCTop		; Get index to first line
	mov	cx,GrxBitWid640/8	; This many bytes per line modes E,F and 10
	cmp	Gmode,0FH
	jae	short SPPM_00
	shr	ax,1			; Convert to phys disp,modes D,E
	cmp	Gmode,0DH
	jne	short SPPM_00
	shr	cx,1			; Mode D screen is half as wide
SPPM_00:
	mov	LineSkip,cx		; Save this val
	mul	cx			; This many bytes in
	add	ax,DDRCLeftBI		; Index to left edge in display mem
	movzx	eax,ax
        mov     VideoIndex,eax          ; save index to the left edge
	mov	cx,DDRCHig		; This many lines to do
	cmp	Gmode,10H
	jae	short SPPM_01
	cmp	Gmode,0FH
	je	short SPPM_01
	shr	cx,1			; Convert to phys disp,modes D,E
SPPM_01:
IFDEF   FASTGRAB
        cmp     [fpScanBuf].sel,0
        jne     short SPPM_02
ENDIF
	mov	ax,BDsWid
	sub	LineSkip,ax		; Value to skip to next line in display
SPPM_02:
        ret

SetParamsPlanarMode endp

;*****************************************************************************
;
; SetupLineBits - return ptr to LineBits in ES:EDI(dword aligned)
;                 (All modes)
;
;*****************************************************************************
SetupLineBits proc near
	push	ss
	pop	es
        xor     edi,edi
	lea	di,LineBits		; es:di -> bits
	test	di,0000000000000011B	; Line bits dword aligned?
	jz	short SLDone		; Yes
	inc	di			; Adjust to dword align
	inc	di
SLDone:
        ret
SetupLineBits endp

IFDEF   FASTGRAB

;*****************************************************************************
; 
; CopyScanLine - Transfer an entire scanline from VideoIndex to ES:EDI
;                Returns CARRY set if failed, clear otherwise
; 
;*****************************************************************************

        public  CopyScanLine
CopyScanLine proc near

        cmp     [fpScanBuf].sel,0
        stc
        je      short CSLExit
	cld
        push    ds
        mov     ds,VidSel
        mov     es,[fpScanBuf].sel
        movzx   edi,[pScanCur]
    ;
    ; Copy the RED plane first
    ;
        mov     esi,VideoIndex
        add     esi,RPlaneOffset
        mov     cx,RPlaneSize
        call    CopyScanLinePlane
    ;
    ; Copy the GREEN plane next
    ;
        mov     esi,VideoIndex
        add     esi,GPlaneOffset
        mov     cx,GPlaneSize
        call    CopyScanLinePlane
    ;
    ; Copy the BLUE plane subsequently
    ;
        mov     esi,VideoIndex
        add     esi,BPlaneOffset
        mov     cx,BPlaneSize
        call    CopyScanLinePlane
    ;
    ; Copy the INTENSITY plane last
    ;
        mov     esi,VideoIndex
        add     esi,IPlaneOffset
        mov     cx,IPlaneSize
        call    CopyScanLinePlane

        pop     ds
        clc
CSLExit:
        ret

CopyScanLine endp

;*****************************************************************************
; 
; CopyScanLinePlane - Transfer a single plane portion of a scanline
; 
;*****************************************************************************

        public  CopyScanLinePlane
CopyScanLinePlane proc near

        movzx   eax,DDPWid
        sub     cx,[VideoIndex].off
        jbe     short CSLZeroPlane
        shr     cx,2                    ; values should be DWORD multiples
        cmp     cx,ax
        jbe     short CSLCopyPlane
        mov     cx,ax
CSLCopyPlane:
        movzx   ecx,cx
        sub     eax,ecx
        rep movs dword ptr es:[edi],dword ptr ds:[esi]
        db      67h                     ; Problem Workaround DO NOT REMOVE
	nop
CSLZeroPlane:
        mov     ecx,eax
        xor     eax,eax
        rep stos dword ptr es:[edi]
        db      67h                     ; Problem Workaround DO NOT REMOVE
	nop
        mov     ax,GrxBitWid640/8
        sub     ax,DBPWid
        add     edi,eax                 ; advance bitmap pointer to next plane
        ret

CopyScanLinePlane endp

ENDIF  ;FASTGRAB

;*****************************************************************************
; 
; GetDwordDataEF10 - return a dword of pixel info, Modes E,F,10 only
;                   EAX = I bits,EBX = R bits,ECX = G bits,EDX = B bits
; 
; NOTE: Mode F, Plane 3 and 1(I & G planes )data is always 0
;	When memory plane has not been allocated, zero is returned
;
;*****************************************************************************

GetDwordDataEF10 proc near

        mov     ds,VidSel
	cld
	mov	eax,VideoIndex

	xor	edx,edx
	cmp	ax,BPlaneSize
	ja	SHORT NoBlueMem
        mov     esi,BPlaneOffset        ; Point at Blue plane
	mov	edx,[esi][eax]
NoBlueMem:

        cmp     Gmode,0Fh
        je      SHORT SkipGPlane
	xor	ecx,ecx
	cmp	ax,GPlaneSize
	ja	SHORT NoGreenMem
        mov     esi,GPlaneOffset        ; Point at green
	mov	ecx,[esi][eax]
NoGreenMem:

SkipGPlane:
	xor	ebx,ebx
        cmp     ax,RPlaneSize
	ja	SHORT NoRedMem
        mov     esi,RPlaneOffset        ; Point at Red
	mov	ebx,[esi][eax]
NoRedMem:

        cmp     Gmode,0Fh
        je      SHORT SkipIPlane
        mov     esi,IPlaneOffset
	add	esi,eax
	cmp	ax,IPlaneSize
	mov	eax,0
	ja	SHORT GDE_Exit
	mov	eax, [esi]		; Get Intensity in EAX
        jmp     SHORT GDE_Exit

SkipIPlane:
        mov     eax,ebx
        mov     ecx,edx
        mov     ebx,edx
GDE_Exit:
        add     VideoIndex,4            ; Advance to next dword for Mode E,F,10
        ret     

GetDwordDataEF10 endp

;*****************************************************************************
; 
; GetWordDataD - return a word of pixel info in AX,BX,CX,DX
;                AX = I bits, BX = R bits, CX = G bits, DX = B bits
;
; NOTE: When memory plane has not been allocated, zero is returned
;*****************************************************************************
GetWordDataD proc near

        mov     ds,VidSel
	cld
	mov	eax,VideoIndex

	xor	dx,dx
	cmp	ax,BPlaneSize
	ja	SHORT GDD_NoBluMem
        mov     esi,BPlaneOffset        ; Point at Blue plane
	mov	dx, ds:[esi][eax]	; Blue in DX
GDD_NoBluMem:

	xor	cx,cx
	cmp	ax,GPlaneSize
	ja	SHORT GDD_NoGrnMem
        mov     esi,GPlaneOffset        ; Point at Green
	mov	cx, ds:[esi][eax]	; Green in CX
GDD_NoGrnMem:

	xor	bx,bx
	cmp	ax,RPlaneSize
	ja	SHORT GDD_NoRedMem
        mov     esi,RPlaneOffset
	mov	bx, ds:[esi][eax]	; Get Red in BX
GDD_NoRedMem:

        mov     esi,IPlaneOffset        ; Point at Intensity plane
	add	esi,eax
	cmp	ax,IPlaneSize
	mov	ax,0
	ja	SHORT GDD_NoIntMem
	mov	ax, ds:[esi]		; Get Intensity in AX
GDD_NoIntMem:

        add     VideoIndex,2            ; Advance to next word 
        ret

GetWordDataD endp

;*****************************************************************************
;
; ModeGrfx - Paint a graphics mode display
;
;    This routine Paints the old app graphics screen into a window
;
;    Our Strategy is as follows:
;	Construct a "screen DC" as large as the paint rectangle
;	Construct a "line DC" as wide as the paint rectangle and one scan high
;	Patblt the background color into the screen DC
;	Look at the physical display bits in the paint rectangle for PELs which
;		are not background
;	    When a non-background PEL is found, build the line the PEL is on
;		in the Line Bitmap then BitBlt the line into the screen DC
;	BitBlt the screen DC onto the Display DC where the paint rectangle is
;
; ENTRY:
;	SS:BP -> Std stack frame
;	DS:SI -> EXTPAINTSTRUC structure of paint
;	AH = Mode byte from controller state
; EXIT:
; 	If (Carry Clear)
;	    Screen Painted
;	else if (Carry Set)
;	    Screen not painted, probably low Windows memory problem
; USES:
;	ALL but DS,SI,BP
; NOTE:
;	This routine may set the fGrbProb bit in EPStatusFlags in the
;	Extended paint structure to indicate that this app is in a mode
;	which cannot be rendered into a Window. This routine must return with
;	Carry clear in this case.
;
;*****************************************************************************

ModeGrfx proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing

        call    InitFrameVars

        call    CheckMode
        jc      SetProbBit

    ;
    ; Build display paint rectangle. This is the same as the paint rect
    ;	except the edges are rounded to convenient dword aligned values
    ;
        call    BuildDisplayRect
        jz      InvalidRect     ; rect was off screen or invalid rect CoOrds

        call    AllocCommonRes
        jc      MGError         ; alloc failed

        call    AllocExtraRes   ; Alloc additional resources for paint code
        jc      MGError         ; alloc failed

IFDEF   FASTGRAB
    ;
    ; If we're using the persistent objects, don't bother creating
    ; the temporary ones
    ;
        cmp     [fpScanBuf].sel,0
        jne     short NoScreenBM
ENDIF
    ;
    ; Create the full screen bitmap to the dimensions of the rounded paint rect
    ; If this fails (lack of memory) set GrbFlgs_GrfxDispBlt to cause blt 
    ; directly into display DC instead of ScreenDC.
    ;
	cCall	CreateCompatibleBitmap, <[si.Pstruct.psHdc],DDRCWid,DDRCHig>
	or	ax,ax
	jnz	short GotScreenBM

	or	GrbFlags,GrbFlgs_GrfxDispBlt 	; Set Display DC blit mode
    ;
    ; Select the background brush into the Display DC
    ;
	cCall	SelectObject,<[si.Pstruct.psHdc],BkBrush>
	or	ax,ax
	jz	MGError
        mov     SavOldBr,ax
	jmp	short NoScreenBM

GotScreenBM:
	mov	bx,ax
    ;
    ; Select the full screen bitmap into the full screen DC
    ;
	push	bx
	cCall	SelectObject,<ScreenDC,bx>
	pop	bx

	or	ax,ax
	jz	ReturnBitmap
	mov	ScreenBitMap,bx

NoScreenBM:
IFDEF	GENGRAB

	call	BuildDIBHdr
ENDIF

IFDEF VGA
	cmp	Gmode,11H		; Mode 11
	jz	short DoBackPat
ENDIF
IFDEF MODE13
	cmp	Gmode,13H		; Mode 13
	jz	short DoBackPat
ENDIF
	cmp	Gmode,0DH		; Plane mode?
	jae	PlaneGrx		; Yes
DoBackPat:
    ;
    ; This is one of the CGA graphics modes (4,5,6) or mode 11 or 13
    ; PatBlt the background brush into the full screen DC, or the paint
    ;	rectangle to paint in the background color
    ;
	push	bx
	bt	GrbFlags,GrbFlgs_GrfxDispBltBit
	jnc	short ScrDCPB
	push	[si.Pstruct.psHdc]	  ; hDC
	lea	bx,[si.Pstruct.PSrcPaint]
	mov	ax,[bx.rcRight]
	sub	ax,[bx.rcLeft]
	mov	dx,[bx.rcBottom]
	sub	dx,[bx.rcTop]
	push	[bx.rcLeft]		  ; X
	push	[bx.rcTop]		  ; Y
	push	ax			; nWidth
	push	dx			; nHeight
	jmp	short ScrDCPBDo

ScrDCPB:
	push	ScreenDC		; hDC
	push	0			; X
	push	0			; Y
	push	DDRCWid 		; nWidth
	push	DDRCHig 		; nHeight
ScrDCPBDo:
	push	PATCOPY_H
	push	PATCOPY_L
	cCall	PatBlt
	pop	bx
IFNDEF	GENGRAB
GetPalettes:
    ;
    ; Get Palette 0 and Palette 1
    ; 
    	mov     al, byte ptr [si.EPGrabDTA.CntrlSt.VDA_EGA_Pal] 
	call	matchpalette
	mov	Palette0,al
	mov	al, byte ptr [si.EPGrabDTA.CntrlSt.VDA_EGA_Pal.1]
	call	matchpalette
	mov	Palette1,al
    ;
    ; Get Palette 2 and Palette 3
    ;
    	mov     al, byte ptr [si.EPGrabDTA.CntrlSt.VDA_EGA_Pal.2] 
	call	matchpalette
	mov	Palette2,al
	mov	al, byte ptr [si.EPGrabDTA.CntrlSt.VDA_EGA_Pal.3]
	call	matchpalette
	mov	Palette3,al
ENDIF
IFDEF VGA
	cmp	Gmode,11H
	jz	Mode11Bits
ENDIF
IFDEF MODE13
	cmp	Gmode,13H
	jz	Mode13Bits
ENDIF
CGAMode:
        call    SetParamsCGAMode
NextLineCGAMode:
    ;
    ; Look for non-background Bits
    ;
	push	edi                     ; push ptr to line in Vid mem
	push	cx                      ; push line count
        call    SkipBkBits
	jz	LookMoreBits		; All background bits
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
        jnz     Mode6Line
ENDIF
	mov	esi,edi 		; VidSel:esi -> 1 dword past first non-back
IFNDEF	GENGRAB
        call    SetupLineBits
ENDIF
	cmp	Gmode,6
	jz	Mode6Line
IFDEF   DEBUG
        public Mode45Line
ENDIF
Mode45Line:
    ;
    ; First blit in the background color (Palette0)
    ;
IFNDEF	GENGRAB
        call    SetBkBitsMode4
ELSE
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

ENDIF
    ;
    ; Adjust count to skip bk bits and the current dword
    ;  NOTE: EDX -> start of line 
    ;
	mov	cx,DDPWid		; This many dwords in plane
	mov	ebx,edx
	sub	ebx,esi
	neg	bx			; This many bytes to 1 dword past first non-back
	shr	bx,2			; byte cnt -> dword cnt
	sub	cx,bx			; Skip in this many
	xchg	esi,edi
	mov	es,VidSel
    ;
    ; Now es:edi -> one dword past a non Bk dword in vid mem
    ;     es:edx -> start of line
    ;     ds:esi -> LineBits
    ; Found some non-background bits
    ;

IFDEF	GENGRAB
NextDword4:				; Found some non-background bits
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

        test    cx,cx
        jz      short LineDone

Bit4Loop4:				; More bits
        push    edi
	cld
	xor	eax,eax
	repe scas dword ptr es:[edi]	; Look for more non-backgrnd bits on this line
	pop	edx
	jz	short LineDone		; Done with line
	jmp	NextDword4
ELSE

NextDword4:             
	mov	eax,dword ptr es:[edi-4] ; Get the data
	add	edx,4			; Adjust start to compute index of this DWORD
	sub	edx,edi
	neg	dx			; DX is index in buffer
	add	si,dx			; Skip Bk bits in LineBits
	mov	dl,11111100B		; Non-PEL mask
	mov	dh,00000011B		; PEL mask

	push	cx
	push	edi                     
	push	si                      ; Current ptr into I Plane In LineBits
    ; 
    ; Get Bk mask in EDI
    ; 
	xor	edi,edi 		; Init background mask
	push	eax
	mov	cx,16			; 16 PELs / dword
NextPix4:
	test	al,dh			; Background PEL?
	jnz	short NonBkPix	        ; No 
	or	di,0000000000000011B    ; yes, build bkgrnd PEL mask
NonBkPix:
	ror	edi,2			; Next Pel
	ror	eax,2			
	loop	short NextPix4
	pop	eax
    ;
    ; Set bits in the R plane
    ;
        SetLineBitsMode4     Red4Bits, NoRed, 00000100B
    ;
    ; Set bits in the G plane
    ;
	add	si,DBPWid		; Advance to next color plane
        SetLineBitsMode4     Grn4Bits, NoGrn, 00000010B
    ;
    ; Set bits in the B plane
    ;
	add	si,DBPWid		; Advance to next color plane
        SetLineBitsMode4     Blu4Bits, NoBlu, 00000001B
    ;
    ; Set bits in the I plane
    ;
	add	si,DBPWid		; Advance to next color plane
        SetLineBitsMode4     Int4Bits, NoInt, 00010000B

	pop	si
	add	si,4			; Next dword in LineBits
	pop	edi
	pop	cx

	jcxz	LineDone		; Done with line
    ;
    ; Look for more non-backgrnd bits on this line
    ;
	push	edi
	cld
	xor	eax,eax
	movzx	ecx,cx
	repe	scas dword ptr es:[edi] 
	pop	edx
	jz	short LineDone		; Done with line
	jmp	NextDword4
ENDIF

IFDEF DEBUG
        public Mode6Line
ENDIF
Mode6Line:
    ;
    ; Set bits in the I,R,G,B planes in LineBits
    ;
IFDEF	GENGRAB
	call	XferMonoBits
ELSE
        call    SetMonoBits
ENDIF
LineDone:
	pop	ax			; Line #
	push	ss
	pop	ds
        mov     si,SavEXTP
IFDEF	GENGRAB
	call	SetScreenGENBMBits
ELSE
	call	LineBlt
ENDIF
    ;
    ; Found some (more) non-background bits
    ;
LookMoreBits:
	pop	cx                      ; recover Line count
	pop	edi			; Recover start of line
	add	edi,GrxBitWid640/8 	; Next line
	dec	cx
	jnz	NextLineCGAMode 	; More lines

	bts	GrbFlags,GrbFlgs_GrfxDoOddBit
IFDEF	MODE13
	jc	DisplayMap		; Odd lines done?
ELSE
	jc	short DisplayMap	; Odd lines done?
ENDIF
	jmp	CGAMode		        ; Do odd scans

IFDEF VGA

Mode11Bits:
        call    SetParamsMode11
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
IFDEF	GENGRAB
	call	XferMonoBits
ELSE
	push	ax			; Line # of this line
        call    SetupLineBits           ; es:edi -> LineBits
    ;
    ; Set bits in the I,R,G,B planes in LineBits
    ;
        call    SetMonoBits
	pop	ax			; Line #
ENDIF
	push	ss
	pop	ds
        mov     si,SavEXTP
IFDEF	GENGRAB
	call	SetScreenGENBMBits
ELSE
	call	LineBlt
ENDIF

LookMoreBits11:
	pop	cx
	pop	edi			; Recover start
	add	edi,GrxBitWid640/8 	; Next line
	loop	LookBits11		; More lines
	jmp	SHORT DisplayMap	; Done

ENDIF

IFDEF MODE13

Mode13Bits:
        call    SetParamsMode13
LookBits13:
    ;
    ; Look for non-background Bits
    ;
	push	edi
	push	cx			; and lines left
        call    SkipBkBits
	;jz	SHORT LookMoreBits13	; All background bits
    ;
    ; Compute line number of line with non-background bits, and backup
    ;	index to the start of this line
    ;
	pop	ax			; Get line left count
	push	ax			; back on stack
	shl	ax,1
	sub	ax,DDRCHig
	neg	ax			; Line number

	push	ax
	call	SetupLineBits
	mov	ds,VidSel
	mov	esi,edx
	cld
	mov	cx,DBPWid		; #bytes == #pixels
@@:	lods	byte ptr ds:[esi]
	mov	ah,al			; Double the pixel
	stos	word ptr es:[edi]
	loop	@B
	pop	ax

	push	ss
	pop	ds
        mov     si,SavEXTP
	; the fact that this isn't IFDEF-protected means that it's
	; impossible to compile with MODE13 but not GENGRAB - 
	; that's fine...
	call	SetScreenGENBMBits

LookMoreBits13:
	pop	cx			; Recover lines left
	pop	edi			; Recover start
	add	edi,GrxBitWid640/2 	; Next line
	loop	LookBits13		; More lines
	jmp	SHORT DisplayMap	; Done

ENDIF

ReturnBitmap:
        mov     ScreenBitmap,0
        cCall   Deleteobject,<bx>
        jmp     MGError

AdjWid:
	xchg	cx,bx			; Don't overrun screen bitmap
	sub	bx,cx			; BX is width of "extra" on right
	mov	RightWid,bx
	mov	dx,[si.Pstruct.PSrcPaint.rcRight]
	sub	dx,bx			; DX is Left side of it (X coord)
	mov	RightXpos,dx
	jmp	short widok

AdjHig:
	xchg	cx,bx			; Don't overrun screen bitmap
	sub	bx,cx			; BX is height of "extra" on bottom
	mov	BottomHig,bx
	mov	dx,[si.Pstruct.PSrcPaint.rcBottom]
	sub	dx,bx			; DX is Top side of it (Y coord)
	mov	BottomYpos,dx
	jmp	short HighOK

IFDEF DEBUG
public DisplayMap
ENDIF
DisplayMap:
IFDEF   FASTGRAB
        cmp     [fpScanBuf].sel,0
        je      short SkipLineFlush
        mov     ax,DDRCHig
        or      GrbFlags,GrbFlgs_FlushLines OR GrbFlgs_GrfxDispBlt
        call    LineBlt
SkipLineFlush:
ENDIF
    ;
    ; Display the paint part of the Screen Bitmap if not GrbFlgs_GrfxDispBlt 
    ;
    ; Because of rounding and scroll bar position the paint rect may overflow
    ;  the physical display causing an "extra" area on the top or bottom or
    ;  both. We deal with these by blitting them in the overscan color.
    ;
    ; Init "extra" parts to NONE
    ;
	xor	ax,ax
	mov	RightWid,ax
	mov	BottomHig,ax
    ;
    ; Invert the selction, if any, in the screen bitmap, or on the display if
    ;	GrbFlgs_GrfxDispBlt
    ;
	call	InvSel
    ;
    ; Blit the screen bitmap into the display paint rect
    ;
        push    [si.Pstruct.psHdc]      ; hDestDC
	mov	ax,[si.Pstruct.PSrcPaint.rcLeft]
	mov	cx,[si.Pstruct.PSrcPaint.rcRight]
	sub	cx,ax			; CX = width
	push	ax			; X
	mov	ax,[si.Pstruct.PSrcPaint.rcTop]
	push	ax			; Y
	mov	bx,GrxBitWid640
	sub	bx,[si.PGVDRect.rcLeft] ; BX = display width
	cmp	cx,bx			; Q: Rect exceed display width?
	ja	short AdjWid		;   Y: Set up Extra patblt
widok:
	push	cx			; nWidth
	mov	cx,[si.Pstruct.PSrcPaint.rcBottom]
	sub	cx,ax			; CX = rect height
IFDEF VGA
IFDEF MODE13
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],13H
	je	short @F		; Mode 13 is only 400!
ENDIF
	mov	bx,GrxBitHeight480
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],11H
	jae	short GotGHGT
@@:
ENDIF
	mov	bx,GrxBitHeight400
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],10H
	je	short Height350
	cmp	[si.EPGrabDTA.CntrlSt.VDA_EGA_Mode],0FH
	jne	short GotGHGT
Height350:
	mov	bx,GrxBitHeight350
GotGHGT:
	sub	bx,[si.PGVDRect.rcTop]	; BX = display height
	cmp	cx,bx			; Q: Rect exceed display height?
	ja	short AdjHig		;   Y: Set up Extra patblt
HighOK:
	bt	GrbFlags,GrbFlgs_GrfxDispBltBit
	jnc	short DoDispMapBlt
	add	sp,4*2			; Clear off BitBlt args pushed so far
	jmp	short DoDispMapExtra

DoDispMapBlt:
	push	cx			; nHeight
	push	ScreenDC		; hSrcDC
	mov	ax,[si.PGVDRect.rcLeft]
	sub	ax,DDRCLeft
	push	ax			; XSrc
	mov	ax,[si.PGVDRect.rcTop]
	sub	ax,DDRCTop
	push	ax			; YSrc
	push	SRCCOPY_H		; dwRop
	push	SRCCOPY_L
	cCall	BitBlt
    ;
    ; Un-Invert the selection rectangle, if any
    ;
    ;	 call	 InvSel2     ; We don't need to do this since we will shortly
    ;			     ;	 Discard the screen DC and bitmap

DoDispMapExtra:
    ;
    ; Is there any "extra" area?
    ;
	mov	ax,RightWid
	or	ax,BottomHig
	jz	GrxPdone
DoExtra:
    ;
    ; PatBlt the overscan color into the "extra" areas.
    ;
	call	CreateOverScanBrGrx
	jz	GrxPdone		; Hmmm.... Barfed don't complain though
	push	ax			; Save old brush
	cmp	RightWid,0		; Extra on right?
	jz	short TryBot		; No

	push	[si.Pstruct.psHdc]	  ; hDestDC
	push	RightXPos		; X
	push	[si.Pstruct.PSrcPaint.rcTop]; Y
	push	RightWid		; nWidth
	mov	ax,[si.Pstruct.PSrcPaint.rcBottom]
	sub	ax,[si.Pstruct.PSrcPaint.rcTop]
	push	ax			; nHeight
	push	PATCOPY_H
	push	PATCOPY_L
	cCall	PatBlt

TryBot:
	cmp	BottomHig,0		; Extra on bottom?
	jz	short Selback		; No

	push	[si.Pstruct.psHdc]	  ; hDestDC
	push	[si.Pstruct.PSrcPaint.rcLeft] ; X
	push	BottomYPos		; Y
	mov	ax,[si.Pstruct.PSrcPaint.rcRight]
	sub	ax,[si.Pstruct.PSrcPaint.rcLeft]
	push	ax			; nWidth
	push	BottomHig		; nHeight
	push	PATCOPY_H
	push	PATCOPY_L
	cCall	PatBlt
    ;
    ; Put back the previous brush
    ;
Selback:
	pop	ax			; Recover previous brush
	cCall	SelectObject,<[si.Pstruct.psHdc],ax>
	jmp	GrxPdone
IFNDEF	GENGRAB
Inv1:
    ;
    ; NOTE: This is not actually particularly correct. But since the
    ;	only app we care about is Ventura publisher, which is basically
    ;	a MonoChrome guy, this "sleazy trick" of simply inverting which
    ;	pixels are foreground and which are background makes it work.
    ;
	not	esi
	not	eax
	not	ebx
	not	ecx
	not	edx
	jmp	short InvDn1
ENDIF
    ;
    ; Do Plane Mode screen. Modes D,E,10
    ;
IFDEF DEBUG
        public  PlaneGrx
ENDIF
PlaneGrx:
        call    SetParamsPlanarMode

NextLineDEF10:
	push	cx                      ; push # of lines still left

IFDEF   FASTGRAB
        call    CopyScanLine            ; if we can do a fast copy, do it
        jnc     LineDoneDEF10           ;
ENDIF

        call    SetupLineBits           ; %can move this out of the loop
	mov	cx,DDPWid		; Width in Dwords (words mode D)
IFDEF	GENGRAB
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
ENDIF
NextDwordDEF10:
	push	cx
	cmp	Gmode,0DH
	je	short DData
        call    GetDwordDataEF10
IFDEF	GENGRAB
	call	ProcessDWordE10
	jmp	short ModeEF10Continue
ELSE
        jmp     short GotData
ENDIF
DData:
        call    GetWordDataD
IFDEF	GENGRAB
	call	ProcessWordD
ELSE
        call    PixelDoubleModeD

GotData:
        call    GetBkMaskDEF10
	test	GrbFlags,GrbFlgs_GrfxInvPal
	jnz	Inv1
InvDn1:
;
; % what should we do here ?
;        cmp     BcolInt, 0
;        jz      short   NoBkInt
;        or      eax, esi
;NoBkInt:
	cmp	BcolRed,0		; Red in background?
	jz	short NoBkRed		; No
	or	ebx,esi 		; Set RED background
NoBkRed:
	cmp	BcolGrn,0		; Green in Background?
	jz	short NoBkGrn		; No
	or	ecx,esi 		; Set Green background
NoBkGrn:
	cmp	BcolBlu,0		; Blue in background?
	jz	short NoBkBlu		; No
	or	edx,esi 		; Set blue background
NoBkBlu:
    ; 
    ; LineBits has R,G,B,I planes - windows expects this in this order
    ; 
        xchg    eax,ebx

	cld
	stosd				; Store Red Plane 
	push	di                      ; save new ptr to R plane in LineBits

	add	di,DBPWid		; Index Green plane
	sub	di,4
	mov	eax,ecx 		; Move Green to EAX
	stosd				; Set Green

	add	di,DBPWid		; Index Blue plane
	sub	di,4
	mov	eax,edx 		; Move Blue to EAX
	stosd				; Set Blue

	add	di,DBPWid		; Index Int plane
	sub	di,4
        mov     eax,ebx                 ; Move Int to eax
        stosd                           ; store Int Plane

	pop	di                      ; recover ptr to R Plane in LineBits
ENDIF
ModeEF10Continue:

	pop	cx
	dec	cx
	jnz	NextDwordDEF10 		; Faster than loop to label that is too far
IFDEF DEBUG
public LineDoneDEF10
ENDIF
LineDoneDEF10:
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
IFDEF	GENGRAB
	call	SetScreenGENBMBits
ELSE
	call	LineBlt 		; Blast the line
ENDIF
	pop	cx			; Line count
	dec	cx
	jnz	NextLineDEF10
	jmp	DisplayMap		; All Done

SetProbBit:
	bts	[si.EPStatusFlags],fGrbProbBit ; Tell caller we can't deal with this
InvalidRect:
	clc
        ret     

GrxPdone:
        call    DeAllocAllRes
	clc
	ret

MGError:
        call    DeAllocAllRes
	stc
        ret

ModeGrfx endp

;**
;
; CreateOverScanBrGrx - Create the overscan brush for graphics mode and select it
;
; ENTRY:
;	DS:SI -> EXTPAINTSTRUC structure of paint
;	SS:BP -> Graphics mode paint frame
; EXIT:
;	Zero flag clear
;	    Correct brush selected in display DC
;	    AX is old brush handle from display DC
;	Zero flag set
;	    Attempt to select brush failed
;	OvscnBrsh is handle to brush (zero if not created)
; USES:
;	ALL but DS,SI,DI,BP
;
CreateOverScanBrGrx proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing
    ;
    ; Create a brush in the Overscan color.
    ;
	mov	bl,[si.EPGrabDTA.CntrlSt.VDA_EGA_Colr]	; Get overscan color
	push	[si.Pstruct.psHdc]	  ; hDestDC

IFDEF	GENGRAB	

	xor	bh,bh
    ;
    ; BX has the 6 bit value for modes D,E,F,10,12
    ;
        cmp     Gmode, 0Dh
        je      short COBGModeDE
        cmp     Gmode, 0Eh
        je      short COBGModeDE
        cmp     Gmode, 0Fh
        je      short COBGMode10
        cmp     Gmode, 10h
        je      short COBGMode10
        cmp     Gmode, 12h
        je      short COBGMode10
ENDIF

	mov	bh,bl
IFNDEF	GENGRAB
	test	GrbFlags,GrbFlgs_GrfxInvPal
	jz	short NotInvP
	not	bl
NotInvP:
ENDIF
	and	bl,00000111B		; Mask to RGB values
	shl	bl,1
	and	bh,00010000B		; Mask to intensity bit
	or	bl,bh
	xor	bh,bh			; bx is IRGB color * 2
	shl	bx,1			; * 4 for table
	push	[bx.RGBTable.2]
	push	[bx.RGBTable]

IFDEF	GENGRAB
	jmp	short COBGModeDone
COBGModeDE:
	push	[bx.RGBTableDE.2]
	push	[bx.RGBTableDE]
        jmp     short COBGModeDone        
COBGMode10:
	push	[bx.RGBTable10.2]               ; Modes 10, 12
	push	[bx.RGBTable10]
COBGModeDone:
ENDIF	

	cCall	GetNearestColor

	push	dx
	push	ax
	cCall	CreateSolidBrush
	or	ax,ax			; Worked?
	jnz	short SelB		; Yes
	mov	ax,BkBrush		; Try to use the background brush
	or	ax,ax			; got one?
	jnz	short SelB2		; Yes, use it
	mov	ax,[si.WhtBrshH]	; No, use white brush
	jmp	short SelB2

SelB:
	mov	OvscnBrsh,ax		; Brush handle
SelB2:
	push	[si.Pstruct.psHdc]	  ; hDestDC
	push	ax
	cCall	SelectObject
	or	ax,ax
	ret

CreateOverScanBrGrx endp

IFDEF	GENGRAB

;**
;
; SetScreenGENBMBits - Set bits in the Screen bitmap
;
; ENTRY:
;	SS:BP -> Graphics paint frame
;	DS:SI -> ExtPaintStruc
;	AX = Line # in display bitmap of line
;	LineBits on stack has the DIB
;       DIBHdr on stack is the DIB Header
;
; Alg:
;	If (ScreenBM exists)
;              Do SetDIBits into ScreenBM at AX and AX.1 
;              except in mode F,10H,11H and 12H
;       else  /* DispBltBit set */
;              Does a SetDIBitsToDevice to Display at AX and AX.1 
;              except in Modes F,10h,11h,12h
;
; EXIT:
;
; USES:
;	ALL but DI,SI,BP,DS
;
SetScreenGENBMBits proc near
    assumes ds,nothing
    assumes es,nothing
    assumes ss,nothing

	bt	GrbFlags,GrbFlgs_GrfxDispBltBit	; Display or ScreenDC?
	jc	DispLineBlt	                ; Display
        
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
        lea     di, DIBHdr
        push    di                      
        push    0                       ; wUsage

	cmp	Gmode,10H
	je	short OnlyOne
	cmp	Gmode,0FH
	je	short OnlyOne
	cmp	Gmode,11H
	je	short OnlyOne
	cmp	Gmode,12H
	je	short OnlyOne

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
        lea     di, DIBHdr
	push    di                      
        push    0                       ; wUsage
OnlyOne:
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

;
; AX is line number in ScreenDC
;
DispLineBlt:
        push    di

	mov	cx,[si.PGVDRect.rcTop]
	sub	cx,DDRCTop		; Rounding error in lines from top
	mov	dx,ax
	cmp	Gmode,0FH
	je	short OnlyOneA
	cmp	Gmode,10H
	je	short OnlyOneA
	cmp	Gmode,11H
	je	short OnlyOneA
	cmp	Gmode,12H
	je	short OnlyOneA
	inc	dx			; Line number of second line
OnlyOneA:
	mov	bx,[si.Pstruct.PSrcPaint.rcRight]
	sub	bx,[si.Pstruct.PSrcPaint.rcLeft]  ; Width parameter
	push	dx
	mov	dx,GrxBitWid640
	sub	dx,[si.PGVDRect.rcLeft]
	cmp	bx,dx
	jbe	short newwidok
	xchg	dx,bx			; Don't overrun bitmap
newwidok:
	pop	dx
	cmp	dx,cx
	jb	DispBltDone
	sub	dx,cx			; Second Line number relative to top paint line
	sub	ax,cx			; First Line number relative to top paint line
	jae	short LBOK1
	mov	ax,dx			; First line is off paint rect
					; second line isn't, change first to
					; second and say no second
LBOK1:
	add	ax,[si.Pstruct.PSrcPaint.rcTop]
	add	dx,[si.Pstruct.PSrcPaint.rcTop]
	cmp	ax,[si.Pstruct.PSrcPaint.rcBottom]
	jae	DispBltDone
	push	[si.Pstruct.psHdc]	  ; hDC
	push	[si.Pstruct.PSrcPaint.rcLeft] ;DestX
	push	ax			; DestY
	push	bx			; nWidth
	push	1			; nHeight
	mov	cx,[si.PGVDRect.rcLeft]
	sub	cx,DDRCLeft
	push	cx			; XSrc
	push	0			; YSrc
	push	0                       ; nStartScan
	push	1                       ; nNumScans
	push	ss			; lpBits
	lea	di,LineBits
	test	di,0000000000000011B	; Dword aligned?
	jz	short DwAlign23		; Yes
	inc	di			; Go to dword align
	inc	di
DwAlign23:
	push	di
        push    ss                      ; lpBitmapInfo
        lea     di, DIBHdr
        push    di                      
        push    0                       ; wUsage
	cmp	ax,dx			; Only one line?
	je	short OnlyOneB		; Yes.
	cmp	dx,[si.Pstruct.PSrcPaint.rcBottom] ; Second line off paint rect?
	jae	short OnlyOneB		; Yes, only do one
	push	[si.Pstruct.psHdc]	  ; hDestDC
	push	[si.Pstruct.PSrcPaint.rcLeft] ; X
	push	dx			; Y
	push	bx			; nWidth
	push	1			; nHeight
	push	cx			; XSrc
	push	0			; YSrc
	push	0                       ; nStartScan
	push	1                       ; nNumScans
	push	ss			; lpBits
	lea	di,LineBits
	test	di,0000000000000011B	; Dword aligned?
	jz	short DwAlign24		; Yes
	inc	di			; Go to dword align
	inc	di
DwAlign24:
	push	di
        push    ss                      ; lpBitmapInfo
        lea     di, DIBHdr
        push    di                      
        push    0                       ; wUsage

	cCall	SetDIBitsToDevice
OnlyOneB:
	cCall	SetDIBitsToDevice
IFDEF DEBUG
        or      ax,ax
        jnz     short SSBContinue3
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
	jmp	short SSBContinue3

SSBContinue3:
ENDIF
DispBltDone:
        pop     di
	ret

SetScreenGENBMBits endp

ENDIF

sEnd	code
	end
