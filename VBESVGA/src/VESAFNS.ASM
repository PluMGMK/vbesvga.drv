
;
;	FILE:	vesafns.asm
;	DATE:	6 May 2023
;	AUTHOR: PluMGMK
;
;	This module contains code and data needed for interfacing with VESA
;	BIOS functions.
;

; We probably don't need to move these into the common VESADEFS.INC...
; VESA Capabilities
VESA_CAP_DAC_8BSWITCH	= 00000001b
VESA_CAP_NONVGA		= 00000010b
VESA_CAP_DAC_BLANKPROG	= 00000100b
VESA_CAP_VBEAF		= 00001000b
VESA_CAP_CALL_EDA	= 00010000b
VESA_CAP_HWCURSOR	= 00100000b
VESA_CAP_HWCLIP		= 01000000b
VESA_CAP_TRANSBLT	= 10000000b

; VESA Mode Number Bitfields
VESA_FLAG_SVGA		= 0000000100000000b
VESA_FLAG_UCRTC		= 0000100000000000b
VESA_FLAG_VBEAFINIT	= 0010000000000000b
VESA_FLAG_LINEAR	= 0100000000000000b
VESA_FLAG_PRESERVEMEM	= 1000000000000000b

; VESA Mode Attributes
VESA_ATTR_HWSUPPORT	= 0000000000000001b
VESA_ATTR_OPTINFO	= 0000000000000010b
VESA_ATTR_BIOS_OP	= 0000000000000100b
VESA_ATTR_COLOUR	= 0000000000001000b
VESA_ATTR_GRAPHICS	= 0000000000010000b
VESA_ATTR_NONVGA	= 0000000000100000b
VESA_ATTR_NOBANKSWITCH	= 0000000001000000b
VESA_ATTR_LINEAR	= 0000000010000000b
VESA_ATTR_DBLSCAN	= 0000000100000000b
VESA_ATTR_INTERLACED	= 0000001000000000b
VESA_ATTR_HWTRIPLEBUF	= 0000010000000000b
VESA_ATTR_HWSTEREO	= 0000100000000000b
VESA_ATTR_DUAL		= 0001000000000000b

; VESA Mode Memory Models
VESA_MEM_TEXT	= 0
VESA_MEM_CGA	= 1
VESA_MEM_HGC	= 2
VESA_MEM_EGA	= 3
VESA_MEM_PACKED	= 4
VESA_MEM_SEQ256	= 5
VESA_MEM_DIRECT	= 6	; no palette switching
VESA_MEM_YUV	= 7	; no... :(

incDevice = 1				;Include control for gdidefs.inc

	.xlist
	include CMACROS.INC
	include MACROS.MAC
	include GDIDEFS.INC
	include DISPLAY.INC	; for WF_*
	include VESADEFS.INC
	include int3.inc
	.list

        externA  __A000
        externA  __B000
        externA  __B800
        externA  __C000
        externA  __D000
        externA  __E000
        externA  __F000

	externA  __WinFlags		;Windows info bit
	externFP AllocSelector		; allocate a new selector
	externFP FreeSelector		; free an allocated selector
	externFP SetSelectorBase
	externFP AllocDSToCSAlias
	externFP AllocCSToDSAlias
	externFP GlobalDosAlloc
	externFP GlobalDosFree
	externFP GlobalAlloc
	externFP GlobalFree
	externFP GlobalLock
	externFP GlobalUnlock

; Taken from ..\..\8514\source\genconst.blt
GMEM_FIXED      =   0000h
GMEM_MOVEABLE   =   0002h
GMEM_NOCOMPACT  =   0010h
GMEM_NODISCARD  =   0020h
GMEM_ZEROINIT   =   0040h
GMEM_MODIFY     =   0080h
GMEM_DISCARDABLE=   0100h
GMEM_NOT_BANKED =   1000h
GMEM_DDESHARE   =   2000h
GMEM_SHARE	=   2000h
GMEM_NOTIFY     =   4000h
GMEM_LOWER      =   GMEM_NOT_BANKED
GHND    =    GMEM_MOVEABLE+GMEM_ZEROINIT
GPTR    =    GMEM_FIXED+GMEM_ZEROINIT


sBegin	Data

externW	ScreenSelector
externW	ColourFormat
EXTRN	dac_size:byte
externW	raster_flags		; in BMC_MAIN.ASM
externD	setramdac
externD	VDDEntry

; From INT10.ASM
externW	int10h_ds
externW	int10h_es

; TODO: Move this into InitSeg to save a bit of space at runtime?
; Would make it harder to query card OEM info, which might be nice to display
; in a GUI program or something...
VESAInfoStruct	label byte

VESASig		db "VBE2"
VESAVer		label word
VESAMinVer	db ?
VESAMajVer	db ?
VESAOEM		FARPOINTER <?,?>
VESACaps	LONG <?,?>
VESAModes	FARPOINTER <?,?>
VESATotMem	dw ?	; total video memory in 64k blocks
VESAOEMVer	label word
VESAOEMMinVer	db ?
VESAOEMMajVer	db ?
VESAVendor	FARPOINTER <?,?>
VESAProduct	FARPOINTER <?,?>
VESAProductRev	FARPOINTER <?,?>
VESAAFVer	label word
VESAAFMinVer	db ?
VESAAFMajVer	db ?
VESAAFModes	FARPOINTER <?,?>
VESAScratch1	db 216 dup (?)
VESAScratch2	db 100h dup (?)

VESA_INFO_LEN	equ $ - VESAInfoStruct
BIOS_DATA_LEN	equ 600h

; Real-Mode buffer for palette entries (if needed)
RMPaletteSel	dw 0
RMPaletteSeg	dw 0

; Low-memory display buffer selector for VDD hack...
public	DummyLoMemSel
DummyLoMemSel	dw 0

; Scan line length for ease of access in certain parts of the driver...
public	MemWidth
MemWidth	dw ?
; Total framebuffer size for the same purpose
public	MemSize
MemSize		dd ?

; Keep track of available depths so we can give the user some more helpful info
; if we can't find the exact depth they requested...
public	DepthList,EndDepthList
DepthList	db 15 dup (0)
EndDepthList	label byte

; Are we using a 3-byte-per-pixel video mode, or allowed to search for one?
public	ThreeByte
ThreeByte	db 0

sEnd	Data


.286


sBegin  Code
assumes cs,Code

externB		??BigFontFlags
externW		_cstods		; in CURSOR.ASM
externW		pxbytes		; in SWCURS.ASM
externFP	DoInt10h	; in INT10.ASM
externFP	find_mtrrs	; in MTRR.ASM

; This goes in the Code segment for ease of access, and in case the
; BankSwitch function is included in the buffer (unlikely?)
VESAModeStruct	label byte

OFF_VESA_ATTRS	equ $-VESAModeStruct
VESAModeAttrs	dw ?
VESAWinAAttrs	db ?
VESAWinBAttrs	db ?
VESAGranularity	dw ?	; in kiB, hopefully == 64
VESAWinSize	dw ?	; in kiB, hopefully == 64
VESAWinASeg	dw ?	; copy of ScreenSelector in CS, for bank switching!
VESAWinBSeg	dw ?
public	VESABankSwitch
VESABankSwitch	FARPOINTER <?,?>
OFF_VESA_SLL	equ $-VESAModeStruct
public	MemoryWidth
MemoryWidth	label word	; Alias to avoid overusing "VESA" elsewhere...
VESAScanLineLen	dw ?	; in bytes
OFF_VESA_WIDTH	equ $-VESAModeStruct
VESAWidth	dw ?	; in pixels
OFF_VESA_HEIGHT	equ $-VESAModeStruct
VESAHeight	dw ?	; in pixels
VESACharCellW	db ?	; in pixels
VESACharCellH	db ?	; in pixels
public	ColourFormat_CS
ColourFormat_CS	label word	; Colour Format in "Code" segment
VESAMemPlanes	db ?
OFF_VESA_DEPTH	equ $-VESAModeStruct
VESABPP		db ?	; bits per pixel, must be at least 8
VESABanks	db ?
OFF_VESA_MODEL	equ $-VESAModeStruct
VESAMemModel	db ?	; see VESA_MEM_*
VESABankSize	db ?	; in kiB
VESAImagePages	db ?
		db ?	; supposedly 1 if VBE 3.0, zero if less
OFF_VESA_RDEPTH	equ $-VESAModeStruct
VESARFieldSize	db ?
VESARFieldPos	db ?
OFF_VESA_GDEPTH	equ $-VESAModeStruct
VESAGFieldSize	db ?
VESAGFieldPos	db ?
OFF_VESA_BDEPTH	equ $-VESAModeStruct
VESABFieldSize	db ?
VESABFieldPos	db ?
OFF_VESA_ADEPTH	equ $-VESAModeStruct
VESAAFieldSize	db ?
VESAAFieldPos	db ?
VESADirectMode	db ?	; Bit 0 = programmable ramp, 1 = usable alpha channel
public	VESALinearBuf
VESALinearBuf	LONG <?,?>	; 32-bit Physical Address
VESAOSMem	LONG <?,?>	; Off-Screen Memory
VESAOSMemSize	dw ?	; in kiB
OFF_VESA_SLLIN	equ $-VESAModeStruct
VESAScanLineLin	dw ?	; same as VESAScanLineLen but for linear modes
VESAImgsBanked	db ?
VESAImgsLinear	db ?
; Same as above but for linear modes
OFF_VESA_LDEPTH	equ $-VESAModeStruct
VESALRFieldSize	db ?
VESALRFieldPos	db ?
VESALGFieldSize	db ?
VESALGFieldPos	db ?
VESALBFieldSize	db ?
VESALBFieldPos	db ?
VESALAFieldSize	db ?
VESALAFieldPos	db ?
VESAMaxPixClock	LONG <?,?>	; in Hz
VESAModeScratch	db 190 dup (?)

VESA_MODE_LEN	equ $ - VESAModeStruct

; these are all to help with colour conversion - set to FFh if using palettes
public	red_shr
red_shr		db 0FFh	; how far right to shift red byte (8-RFieldSize)
public	red_shl
red_shl		db 0FFh	; how far left to shift it before ORing in (RFieldPos)
public	green_shr
green_shr	db 0FFh	; how far right to shift green byte (8-GFieldSize)
public	green_shl
green_shl	db 0FFh	; how far left to shift it before ORing in (GFieldPos)
public	blue_shr
blue_shr	db 0FFh	; how far right to shift blue byte (8-BFieldSize)
public	blue_shl
blue_shl	db 0FFh	; how far left to shift it before ORing in (BFieldPos)


; Functions to switch bank if the mode doesn't include a pointer
; (for whatever reason...)
BankSwitchInt10	proc far
	mov	ax,(VBE_INT10_FN SHL 8) OR VBE_BANKSWITCH
	int	10h
	ret
BankSwitchInt10	endp

; This function emulates bank-switching for linear modes.
; It allows me to start programming support for linear modes,
; while still fully stress-testing the bank-switching code paths.
BankSwitchSoft	proc far
	; Since we're calling a Win16 API function, save these:
	push	dx
	push	cx
	push	bx
	push	es

	; DX is the bank index, so we just add that to the
	; upper half of the 32-bit buffer address.
	add	dx,[VESALinearBuf.hi]
	; Note that this doesn't trap into Ring0 at all, as
	; the Windows "KERNEL" can modify the LDT directly
	; from Ring3...
	cCall	SetSelectorBase,<[VESAWinASeg],dx,[VESALinearBuf.lo]>

	; If needed, DS should be reloaded already. Now we also reload ES:
	pop	es
	; And restore the other saved regs
	pop	bx
	pop	cx
	pop	dx
	ret
BankSwitchSoft	endp

sEnd	Code


createSeg _PALETTE,PaletteSeg,word,public,CODE
sBegin	PaletteSeg

; from TRN_PAL.ASM
externFP setramdac_vga

;
;	setramdac_vbe
;	PARMS:
;	ax	index to 1st palette entry
;	cx	count of indices to program
;	ds:si	-> 256 double words  (ds MUST!! be driver data segment)
;

.286
assumes  cs,PaletteSeg
assumes  ds,Data
assumes  es,nothing

PUBLIC	setramdac_vbe
setramdac_vbe	PROC	FAR

	push	es
	push	di

	; fixup byte order
	call	switcheroo

	; set ES:DI = DS:SI for VBE function 09
	mov	di,ds
	mov	es,di	
	mov	di,si

	; set the other registers appropriately
	mov	dx,ax	; first colour index
	xor	bl,bl	; set primary palette
	mov	ax,(VBE_INT10_FN SHL 8) + VBE_PALENTRIES

	mov	di,ax
	cmp	[RMPaletteSel],0
	jnz	@F

	; need to allocate this DOS buffer (only once!)
	; 4 bytes per colour * 100h colours
	push	bx
	push	cx
	push	dx
	cCall	GlobalDosAlloc,<0,400h>	; zero-pad to dword
	mov	[RMPaletteSel],ax
	mov	[RMPaletteSeg],dx
	pop	dx
	pop	cx
	pop	bx

	test	ax,ax
	mov	ax,(ERR_REAL_ALLOC SHL 8) + VBE_INT10_FN
	jz	setramdac_vbe_exit

@@:
	mov	ax,[RMPaletteSeg]
	mov	[int10h_es],ax
	mov	ax,di

	; copy the palette entries into the RM buffer
	mov	es,[RMPaletteSel]
	xor	di,di

	push	di
	push	si
	push	cx
	shl	cx,1	; two words per colour
	cld
	rep	movsw
	pop	cx
	pop	si
	pop	di

	call	DoInt10h

setramdac_vbe_exit:
	; restore original byte order
	call	switcheroo
	pop	di
	pop	es

	; success?
	cmp	ax,VBE_INT10_FN
	jne	setramdac_need_vga
        ret

setramdac_need_vga:
	; VBE cannot be used to set RAMDAC, so fall back to VGA implementation
	; by updating the function pointer and jumping to it
	mov	[setramdac.lo],offset setramdac_vga
	; get back the index into AX
	mov	ax,dx
	; go to the VGA function
	jmp	[setramdac]

setramdac_vbe	ENDP

; At least some BIOS implementations expect a big-endian list of colours, i.e.
; where blue is the LSB, whereas Windows gives red as the LSB (which also agrees
; with what is written in the RBIL for int 10H AH=4F09H...)
; This function deals with that - TODO: check if always needed, and if not,
; create a way to turn it off...
switcheroo	proc near
	push	ax
	push	si
	push	cx

@@:	mov	al,[si]
	xchg	al,[si+2]
	mov	[si],al
	lea	si,[si+4]
	loop	@B

	pop	cx
	pop	si
	pop	ax
	ret
switcheroo	endp

sEnd	PaletteSeg

createSeg _INIT,InitSeg,word,public,CODE
sBegin	InitSeg

externNP	init_modal_realizations	; in ROBJECT.ASM
externNP	setup_double_buf		; in DBLBUF.ASM

assumes	cs,InitSeg
assumes	ds,Data

;--------------------------------------------------------------------------;
; GetVBEInfo
;	fills in VESAInfoStruct by calling the BIOS
; Entry:
; Returns:
;	AX	= zero
; Error Returns:
;	AX	= error code
; Registers Destroyed:
;	DX,FLAGS
; Registers Preserved:
;	BX,CX,SI,DI,DS,ES,BP
; Calls:
;	DoInt10h
;	FixupFarPtr
; History:
;	see Git
;--------------------------------------------------------------------------;
cProc	GetVBEInfo,<NEAR,PUBLIC>,<es,di,bx,si,cx>
cBegin
	; Check if the buffer is filled already
	; If so, it will begin with "VESA"
	cmp	word ptr [VESASig],"EV"
	jne	@F
	cmp	word ptr [VESASig+2],"AS"
	jne	@F
	; We're already done
	xor	di,di
	jmp	VBEInfo_Done

@@:
	assumes	es,nothing
	; Allocate a Real-Mode memory block to transfer the info
	cCall	GlobalDosAlloc,<0,VESA_INFO_LEN>	; zero-pad to dword
	test	ax,ax
	mov	di,ERR_REAL_ALLOC
	jz	@F

	; Set the ES segment for the int 10h call appropriately
	mov	[int10h_es],dx

	; Copy our buffer in there...
	mov	es,ax
	assumes	es,nothing
	xor	di,di	; buffer is at beginning of the segment
	mov	cx,VESA_INFO_LEN SHR 1
	lea	si,VESAInfoStruct
	cld
	rep	movsw

	; Call the BIOS
	mov	ax,(VBE_INT10_FN SHL 8) OR VBE_GETINFO
	xor	di,di	; buffer is at beginning of the segment
	call	DoInt10h

	; Copy the buffer back out...
	push	ds
	push	es
	pop	ds
	assumes	ds,nothing
	pop	es
	assumes	es,Data
	mov	cx,VESA_INFO_LEN SHR 1
	lea	di,VESAInfoStruct
	xor	si,si	; buffer is at beginning of the segment
	cld
	rep	movsw

	mov	si,ax	; stash int 10h result in SI

	; Done with the Real-Mode buffer
	mov	ax,ds
	push	es
	pop	ds
	assumes	ds,Data
	cCall	GlobalDosFree,<ax>
	push	ds
	pop	es	; ensure ES==DS even after kernel call

	; Check if function succeeded
	cmp	si,VBE_INT10_FN
	mov	di,VBE_ERR_FAIL
	jne	VBEInfo_Done

	; Check if the buffer is filled correctly
	; It should now begin with "VESA"
	cmp	word ptr [VESASig],"EV"
	jne	VBEInfo_Done
	cmp	word ptr [VESASig+2],"AS"
	jne	VBEInfo_Done

	; Fix up all the far pointers
	mov	dx,[int10h_es]
	lea	bx,VESAInfoStruct

	lea	si,VESAOEM
	xor	cx,cx	; not code
	call	FixupFarPtr
	test	ax,ax
	mov	di,ERR_PROT_ALLOC
@@:	; label to facilitate long jump
	jz	VBEInfo_Done

	lea	si,VESAModes
	xor	cx,cx	; not code
	call	FixupFarPtr
	test	ax,ax
	mov	di,ERR_PROT_ALLOC
	jz	VBEInfo_Done

	; If VBE version < 2.0, we're done
	cmp	[VESAVer],200h
	jb	@F

	lea	si,VESAVendor
	xor	cx,cx	; not code
	call	FixupFarPtr

	lea	si,VESAProduct
	xor	cx,cx	; not code
	call	FixupFarPtr

	lea	si,VESAProductRev
	xor	cx,cx	; not code
	call	FixupFarPtr

	; If no VBE/AF, we're done
	test	[VESACaps.lo],VESA_CAP_VBEAF
	jz	@F

	lea	si,VESAAFModes
	xor	cx,cx	; not code
	call	FixupFarPtr

@@:
	xor	di,di	; success
VBEInfo_Done:
	mov	ax,di	; get return code
	cwd		; as a DWORD
cEnd

;--------------------------------------------------------------------------;
; FindMode
;	runs through the list of available SVGA modes, finds one that
;	matches the desired criteria, and fills its info (including the
;	bank-switch function pointer) into the VESAModeStruct
; Entry:
;	profile should have been read
; Returns:
;	AX	= zero
; Error Returns:
;	AX	= error code
; Registers Destroyed:
;	DX,FLAGS
; Registers Preserved:
;	BX,CX,SI,DI,DS,ES,BP
; Calls:
;	SegToSel
;	AllocCSToDSAlias
;	FreeSelector
;	
;	DoInt10h
;	FixupFarPtr
; History:
;	see Git
;--------------------------------------------------------------------------;
cProc	FindMode,<NEAR,PUBLIC>,<es,ds,di,bx,si,cx>
	parmB	bLinear	; zero if bank-switched mode is desired
	localW	CodeSel	; RW selector to Code segment
cBegin
	cmp	[bLinear],0
	jz	@F

	; do a few checks before agreeing to search for a linear mode
	mov	ax,__WinFlags
	mov	di,-1		; in case we return with error
	test	ax,WF_ENHANCED
	jnz	@F		; linear modes will work in enhanced mode

	test	ax,WF_PMODE
	jz	LinRealMode

	; DOSX can screw us over because it always codes int 31h 800h as a
	; no-op, even when it's using paging (via VCPI).
	test	ax,WF_CPU386 OR WF_CPU486
	jz	@F		; no paging, int 31h 800h as a no-op is fine

	; Check if a different DPMI host is being used, rather than
	; DOSX (e.g. HX-DOS extender)
	mov	ax,400h		; Get DPMI version
	int	31h
	test	bl,1		; 32-bit?
	jnz	@F		; OK, it's not DOSX, so we're probably OK

	; Windows in Standard Mode always tells us there's no paging, even
	; when there is. We have to go to deeper to find the truth...
	mov	ax,200h		; get real-mode interrupt vector
	mov	bl,67h		; EMS / VCPI
	int	31h
	or	cx,dx
	jz	@F		; no VCPI, we're fine

	; attempt to ask VCPI about the contents of CR0
	.386
	pushad			; in case stuff gets trashed
	xor	ebx,ebx
	mov	ax,0DE07h	; VCPI: read CR0
	int	67h		; this should reflect through to VM86 mode
	bt	ebx,1Fh
	popad
	.286
	jnc	@F		; no paging

ifdef	INT3
public	LinStdModePaging
LinStdModePaging:
	int	3
endif
	WriteAux <'Linear framebuffer not usable in Standard Mode with Paging.'>
	jmp	FindMode_reterr

LinRealMode:
ifdef	INT3
public	LinRealMode
	int	3
endif
	WriteAux <'Linear framebuffer not usable in Real Mode.'>
	jmp	FindMode_reterr

@@:	; ensure that VBE Info is populated before we use it!
	call	GetVBEInfo

ifdef	INT3
public	VBEInfoReady
VBEInfoReady:
	int	3
endif
	; set the DAC size to the best available if necessary
	cmp	[dac_size],-1	; "auto" setting?
	jne	@F

	mov	al,byte ptr [VESACaps.lo]
	not	al
	and	al,VESA_CAP_DAC_8BSWITCH
	; now AL == 1 if it CANNOT be switched to 8-bit, 0 if it can
	shl	al,1	; set to 2 (i.e. 8 minus 6) if applicable
.errnz	(VESA_CAP_DAC_8BSWITCH - (2 SHR 1))
	mov	[dac_size],al

@@:
	push	seg VESAModeStruct
	cCall	AllocCSToDSAlias
	mov	[CodeSel],ax
	test	ax,ax
	mov	di,ERR_PROT_ALLOC
	jnz	@F
	jmp	FindMode_reterr

@@:
	; Real Mode buffer
	cCall	GlobalDosAlloc,<0,VESA_MODE_LEN>	; zero-pad to dword
	test	ax,ax
	jnz	@F

	mov	di,ERR_REAL_ALLOC
	jmp	FindMode_done
@@:
	; Point both Real and Protected Mode ES:DI to the allocated buffer
	mov	[int10h_es],dx
	mov	es,ax
	assumes	es,nothing
	xor	di,di

FindMode_bufready:
	; start going through the modes
	mov	si,[VESAModes.off]
FindMode_loop:
	push	ds
	mov	ds,[VESAModes.sel]
	assumes	ds,nothing
	cld
	lodsw
	cmp	ax,-1
	pop	ds
	assumes	ds,Data

	mov	cx,ax
	jne	@F
	jmp	ModeFound	; return -1 to say "no mode found"

@@:
	mov	ax,(VBE_INT10_FN SHL 8) OR VBE_GETMODEINFO
	call	DoInt10h

	mov	ax,es:[di.OFF_VESA_ATTRS]
	; Is it supported by the current hardware?
	test	al,low VESA_ATTR_HWSUPPORT
	jz	FindMode_loop	; NEXT!
	; Is it graphical (not text)?
	test	al,low VESA_ATTR_GRAPHICS
	jz	FindMode_loop	; NEXT!
	; Is it colour (not BW)?
	test	al,low VESA_ATTR_COLOUR
	jz	FindMode_loop	; NEXT!

	cmp	[bLinear],0
	jnz	@F
	; Does it support bank switching?
	test	al,low VESA_ATTR_NOBANKSWITCH
jnelp:	; extra label to allow for short JNE instructions
	jne	FindMode_loop	; NEXT!
	jmp	FindMode_attrsOK
@@:
	; Does it support linear operation?
	test	al,low VESA_ATTR_LINEAR
	jz	FindMode_loop	; NEXT!
	; Set the "linear" flag in the mode number
	or	ch,high VESA_FLAG_LINEAR
	; And make sure vesa_gdi_fixup gets the right data!
	cmp	[VESAMajVer],3
	; VBE 2.0 and lower didn't specify separate bitnesses for linear and
	; banked versions of the same mode
	jb	FindMode_attrsOK
	mov	ax,es:[di.OFF_VESA_SLLIN]
	mov	es:[di.OFF_VESA_SLL],ax
	; And also the depth-checking code below
	mov	ax,es:[di.OFF_VESA_LDEPTH]
	mov	es:[di.OFF_VESA_RDEPTH],ax
	mov	ax,es:[di.OFF_VESA_LDEPTH+2]
	mov	es:[di.OFF_VESA_RDEPTH+2],ax
	mov	ax,es:[di.OFF_VESA_LDEPTH+4]
	mov	es:[di.OFF_VESA_RDEPTH+4],ax
	mov	ax,es:[di.OFF_VESA_LDEPTH+6]
	mov	es:[di.OFF_VESA_RDEPTH+6],ax

FindMode_attrsOK:
	; TODO: fill these in if needed for "standard" modes on VBE < 2.0...
	; Is it the right width?
	mov	ax,es:[di.OFF_VESA_WIDTH]
	cmp	ax,[VScreen_Width]
	jne	jnelp		; NEXT!
	; Is it the right height?
	mov	ax,es:[di.OFF_VESA_HEIGHT]
	cmp	ax,[VScreen_Height]
	jne	jnelp		; NEXT!

	mov	al,es:[di.OFF_VESA_DEPTH]
	mov	ah,al
	; Packed pixel?
	cmp	byte ptr es:[di.OFF_VESA_MODEL],VESA_MEM_PACKED
	je	@F		; depth is as given

	; Direct colour?
	cmp	byte ptr es:[di.OFF_VESA_MODEL],VESA_MEM_DIRECT
	; We don't support other models
	jne	jnelp		; NEXT!

	; save the advertised depth in BL since we'll check it again
	mov	bl,al

	; calculate significant and total depth for non-packed mode
	mov	al,es:[di.OFF_VESA_RDEPTH]	; sig depth is sum of R/G/B vals
	add	al,es:[di.OFF_VESA_GDEPTH]
	add	al,es:[di.OFF_VESA_BDEPTH]
	mov	ah,al				; save significant depth in AH
	add	al,es:[di.OFF_VESA_ADEPTH]	; get total depth in AL

	; Sometimes the firmware doesn't fill out the ADEPTH field, expecting
	; us to infer the padding from the advertised DEPTH. Check for this
	; by comparing the calculated total to the advertised depth, and pick
	; whichever is bigger.
	cmp	al,bl
	jae	@F
	mov	al,bl

@@:	; here AL = total depth and AH = significant depth
	test	al,7		; is our pixel an integer number of bytes?
	jz	@F
baddepth:
	jmp	FindMode_loop	; NEXT!

@@:	; if the total depth is three bytes, only use it if explicitly allowed
	cmp	al,24
	jne	@F
	cmp	[ThreeByte],0
	jz	baddepth	; NEXT!

@@:
	; Set the depth field equal to the total depth so we don't confuse
	; any other logic later on...
	mov	es:[di.OFF_VESA_DEPTH],al

	; At this point, we know the mode is usable, so find a slot and
	; put its depth on the list
	lea	bx,[DepthList]
@@:	cmp	bx,offset EndDepthList
	jnb	@F		; no more slots available

	mov	al,[bx]
	cmp	al,ah
	je	@F		; already on the list

	inc	bx
	test	al,al		; free slot?
	jnz	@B		; not free, try next slot

	mov	[bx-1],ah	; fill the slot

@@:	; Is it the right significant depth?
	cmp	ah,[VScreen_Depth]
	jne	baddepth	; NEXT!

	; OK, we've found the mode!
	mov	[Vmode],cx
	xor	ax,ax		; return success

ModeFound:
	test	ax,ax		; returning success?
	mov	si,es		; if not, put the DOS buffer in SI
	jnz	@F

	; we have to do a load of segment translation...
	push	ds
	; Copy the buffer back out...
	push	es
	pop	ds
	assumes	ds,nothing
	; DS:SI = Real Mode buffer
	xor	si,si

	mov	es,[CodeSel]
	assumes	es,Code
	; ES:DI = Protected Mode buffer
	lea	di,VESAModeStruct

	mov	cx,VESA_MODE_LEN SHR 1
	cld
	rep	movsw

	; Done with the Real-Mode buffer
	mov	si,ds
	pop	ds
	assumes	ds,Data
@@:
	assumes	es,nothing	; ES may not be set; GlobalDosFree will unset it
	mov	di,ax		; save our return code
	cCall	GlobalDosFree,<si>

	mov	es,[CodeSel]
	assumes	es,Code

	test	di,di		; returning success?
	jnz	@F

	; Prepare to fix up the far pointer if needed
	lea	si,VESABankSwitch
	lea	bx,VESAModeStruct
	mov	cx,seg VESABankSwitch	; code may be placed in this segment!

	; But if we've a linear mode, that's not necessary...
	test	[Vmode],VESA_FLAG_LINEAR
	jnz	FindMode_setuplin

	; Fix up the far pointer
	mov	dx,[int10h_es]
	call	FixupFarPtr
	test	ax,ax
	mov	di,ERR_PROT_ALLOC
	jz	@F

	; Fix up the segments too
	xor	cx,cx		; want data segments!
	mov	ax,[VESAWinASeg]
	call	SegToSel
	mov	[VESAWinASeg],ax

	mov	ax,[VESAWinBSeg]
	call	SegToSel
	mov	[VESAWinBSeg],ax

	xor	di,di	; all good!
@@:	jmp	FindMode_done

FindMode_setuplin:
ifdef	INT3
public	FindMode_setuplin
	int	3
endif
	; Map the framebuffer into virtual memory if needed.
	; Start by calculating its size:
	mov	ax,[MemoryWidth]
	mul	[VESAHeight]
	mov	si,dx
	mov	di,ax
	; Now just set its location:
	mov	cx,[VESALinearBuf.lo]
	mov	bx,[VESALinearBuf.hi]
	; Take this opportunity to check for MTRRs
	call	find_mtrrs
	; And call:
	mov	ax,800h		; PHYSICAL ADDRESS MAPPING
	int	31h
	mov	di,ERR_PROT_ALLOC
	jc	FindMode_done
	; Now we can put the linear address back where we got the physical one
	mov	[VESALinearBuf.lo],cx
	mov	[VESALinearBuf.hi],bx

	; IF we're in a linear mode AND the VDD is loaded, then we need to
	; "artificially" touch the pages in the low-memory (banked) buffer
	; (usually A0000h-AFFFFh) to make sure it knows we own them.
	cmp	[VDDEntry.sel],0
	jz	@F

	mov	ax,[VESAWinASeg]
	xor	cx,cx		; want a data segment
	call	SegToSel
	mov	[DummyLoMemSel],ax

@@:	; Create a selector that will be used to access 64k at a time
	; (we can copy __A000 and then change its base dynamically)
	cCall	AllocSelector,<__A000>
	mov	es,[CodeSel]	; ES gets stomped when we call the C function
	test	ax,ax
	jz	FindMode_done

	; Set the selector base as appropriate
	cCall	SetSelectorBase,<ax,[VESALinearBuf.hi],[VESALinearBuf.lo]>
	mov	es,[CodeSel]	; ES gets stomped when we call the C function
	test	ax,ax
	jz	FindMode_done
	; Helpfully, SetSelectorBase gives back the selector value in AX again.
	mov	[VESAWinASeg],ax

	; Set the bank-switching function to our "soft" implementation
	mov	[VESABankSwitch.sel],seg BankSwitchSoft
	mov	[VESABankSwitch.off],offset BankSwitchSoft

	; Also ensure the window size is correctly set to 64k
	mov	[VESABankSize],64

	xor	di,di
FindMode_done:
	.286
	test	di,di
	jnz	@F

	; Set ScreenSelector based on what has taken place above
	mov	ax,[VESAWinASeg]
	mov	[ScreenSelector],ax

	; while we're here with a code segment alias,
	; setup modal functions / data for brush realization
	mov	ax,__WinFlags			; setup for 3.0 fonts
        test    ax,WF_PMODE                     ; protected mode?
        jz      @@bffisset
        test    ax,WF_CPU386+WF_CPU486          ; 386/486 protected mode?
        jz      @@bffisset
;
; change our code segment based variable to reflect the mode
;
	mov	byte ptr es:[??BigFontFlags],-1

@@bffisset:
	mov	al,[VESABPP]
	shr	al,3	; bits to bytes
	cbw
	mov	[pxbytes],ax

	; mark whether or not we end up using a three-byte mode
	; (in theory this could be used to enable/disable awkward code paths)
	xor	ah,ah
	cmp	al,3
	jne	@F
	inc	ah
@@:	mov	[ThreeByte],ah

	mov	dh,[VESAMemModel]
	xor	dh,VESA_MEM_DIRECT	; zero if NO palette, else non-zero
	mov	ah,dh
	call	init_modal_realizations

	; while we're at it, set the full colour conversion parameters
	test	dh,dh
	; if using a palette, we don't do this.
	jnz	@@skipcolourloop

	push	si
	push	di
	lea	si,VESARFieldSize
	lea	di,red_shr
	mov	cx,3	; three colours to setup
	cld
@@colourloop:
	lods	word ptr es:[si]
	sub	al,8
	neg	al	; AL = 8 - FieldSize
	stosw
	loop	@@colourloop
	pop	di
	pop	si

@@skipcolourloop:
	; setup a fallback bank-switch function, just in case we somehow got
	; this far without one...
	cmp	[VESABankSwitch.sel],0
	jnz	@F

	mov	[VESABankSwitch.sel],seg BankSwitchInt10
	mov	[VESABankSwitch.off],offset BankSwitchInt10

@@:
	; time to free the selector
	cCall	FreeSelector,<[CodeSel]>
	assumes	es,nothing

FindMode_reterr:
	mov	ax,di		; get error code
cEnd

;--------------------------------------------------------------------------;
; vesa_gdi_fixup
;	takes pointers to GDIInfo and BITMAP structures, and fills them in
;	with info for the currently-selected VESA SVGA video mode.
; Entry:
;	DS	= Data
;	ES:SI	= GDIInfo structure
;	ES:DI	= int_phys_device structure
;	
; Returns:
;	Nothing
; Registers Destroyed:
;	AX,BX,CX,DX,FLAGS
; Registers Preserved:
;	SI,DI,DS,ES,BP
; Calls:
;	Nothing
; History:
;	see Git
;--------------------------------------------------------------------------;
public	vesa_gdi_fixup
vesa_gdi_fixup	proc near
	assumes	ds,Data
	assumes	es,nothing

	push	ds
	mov	ax,seg VESAModeStruct
	mov	ds,ax
	assumes	ds,Code		; read-only access to VESA Mode Struct

	; Fill in the GDI structures with the relevant mode info
	mov	ax,[VESAWidth]
	mov	bx,[VESAHeight]
	mov	cx,[VESAWinASeg]
	mov	dx,[ColourFormat_CS]
	mov	es:[si].dpHorzRes,ax
        mov     es:[di].bmWidth,ax
	mov	es:[si].dpVertRes,bx
        mov     es:[di].bmHeight,bx
        mov     es:[di].bmBits.sel,cx           ;fixup device pointer
	mov	wptr es:[di].bmPlanes,dx	;also covers bmBitsPixel

	; set planes and depth (one word each) in GDIInfo
	xor	ah,ah
	mov	al,dh
	mov	es:[si].dpBitsPixel,ax
	mov	al,dl
	mov	es:[si].dpPlanes,ax

	mov	ax,[VESAScanLineLen]
	mov	cx,ax
        mov     es:[di].bmWidthBytes,ax
        mul     bx
        mov     es:[di].bmWidthPlanes.lo,ax
        mov     es:[di].bmWidthPlanes.hi,dx
	; set the # of scanlines per segment
	mov	ax,[VESAWinSize]
	cwd		; set DX to zero for the DIV we do below
	mov	bx,40h	; 64 kiB is size of segment
	sub	bx,ax	; is the VESA window any smaller than 64k?
	jb	@F
	shl	bx,10	; convert to bytes
	mov	es:[di].bmFillBytes,bx

@@:
	shl	ax,9	; HALF the window size in bytes (so it fits in AX)
	shl	ax,1	; now double it
	rcl	dx,1	; and carry into DX (set to zero by CWD above)
	div	cx
	mov	es:[di].bmScanSegment,ax

	; TODO: set the geometric stuff in the GDIInfo struct

	; we only support palettes for packed-pixel modes
	cmp	[VESAMemModel],VESA_MEM_PACKED
	je	@F
	and	es:[si].dpRaster, NOT RC_PALETTE
@@:
	; set the big font flag as appropriate
	cmp	[??BigFontFlags],0
	jz	@F
	or	wptr es:[si].dpRaster,RC_BIGFONT ; set the big fonts bit
@@:
	; now set the ColourFormat too
	pop	ds
	assumes	ds,Data
        mov     ax,wptr es:[di].bmPlanes
	mov	[ColourFormat],ax

	; and the MemWidth / Size
	mov	ax,es:[di].bmWidthBytes
	mov	bx,es:[di].bmWidthPlanes.lo
	mov	cx,es:[di].bmWidthPlanes.hi
	mov	[MemWidth],ax
	mov	[MemSize.lo],bx
	mov	[MemSize.hi],cx

	; keep a copy of the raster flags in Data, as InitSeg is discardable!
	mov	ax,es:[si].dpRaster
	mov	[raster_flags],ax

	; setup double-buffering if possible / necessary
	test	[Vmode],VESA_FLAG_LINEAR
	jz	@F
	call	setup_double_buf
@@:	ret
vesa_gdi_fixup	endp



;	set_dacsize
;
;	This routine sets the DAC to use either 8 bit DAC mode or 6 bit
;	DAC mode. If an attempt is mode to set 8 bit DAC mode and the
;	DAC does not support 8 bits, it will be left in 6 bit mode.
;	PARMS:
;       ds      Data
;       bx      1 = set 8 bit mode, 0 = set 6 bits mode

PUBLIC	far_set_dacsize
far_set_dacsize 	PROC	FAR

	call	set_dacsize
	ret

far_set_dacsize 	ENDP


; TODO: Fall back to port I/O if VBE < 1.2 ??
PUBLIC  set_dacsize
set_dacsize	PROC	NEAR
	assumes ds,Data
	assumes es,nothing

	mov	ax,(VBE_INT10_FN SHL 8) + VBE_DACSIZE
	test	bx,bx
	mov	bh,6		; just go set it to six
	jz	common_vesafun

	mov	bx,800h		; prepare to set (BL=0) to eight (BH=8)
	cmp	[dac_size],2	; does the user not want 8-bit DAC?
	jne	common_vesafun	; they do, go set it

	; if we're here, dac_size was 2, so there's no need to set it
	ret

set_dacsize	ENDP


;---------------------------Public-Routine------------------------------;
; setmode
;
;   Places the card in graphics mode
;
; Entry:
;	ES:DI --> our pDevice
;	DS:    =  Data
; Returns:
;	AX = VBE_INT10_FN
; Error Returns:
;	AL = VBE_INT10_FN
;	AH = Error Code
; Registers Preserved:
;	CX,DX,BP,SI,DI,ES,DS
; Registers Destroyed:
;	AX,BX,FLAGS
; Calls:
;	int 10h
; History:
;	See Git
;-----------------------------------------------------------------------;
public	setmode
setmode	proc near
	assumes ds,Data
	assumes es,nothing

ifdef	INT3
	int	3
endif
	mov	ax,(VBE_INT10_FN SHL 8) + VBE_SETMODE
	mov	bx,[Vmode]

common_vesafun:
	; there's no point in messing around with VM86 redirects or PMIDs here
	; since this is a really simple operation that doesn't use any data
	; segments - and anyway, this way it's easier for the VxD to trap it!
	int	10h
	ret

setmode	endp

;--------------------------------------------------------------------------;
; FixupFarPtr
;	converts a far pointer returned by a Real-Mode VBE function, which
;	may or may not point to data within the same block, to a Protected
;	Mode version
; Entry:
;	DX:00	= Real-Mode address from which data block was copied
;	ES:BX	= base of copied data block
;	ES:SI	= points to the pointer we want to fixup (within the block)
;	CX	= CS alias of ES, zero if pointer is to data
;	
; Returns:
;	AX	= fixed-up segment
; Error Returns:
;	AX	= zero
; Registers Destroyed:
;	FLAGS
; Registers Preserved:
;	BX,CX,DX,SI,DI,DS,ES,BP
; Calls:
;	SegToSel
; History:
;	see Git
;--------------------------------------------------------------------------;
FixupFarPtr	proc near
	assumes	es,nothing
	assumes	ds,nothing

	cmp	es:[si.sel],dx
	jne	@@NotWithinBlock

	mov	ax,cx
	test	ax,ax
	jnz	@F
	mov	ax,es
@@:
	add	es:[si.off],bx
@@setsel:
	mov	es:[si.sel],ax
	ret

@@NotWithinBlock:
	mov	ax,es:[si.sel]
	push	cx
	push	di
	call	SegToSel
	pop	di
	pop	cx
	jmp	@@setsel
FixupFarPtr	endp

;--------------------------------------------------------------------------;
; SegToSel
;	takes a Real-Mode segment and returns a Protected-Mode selector
;	pointing to the same memory, reusing ones from the Windows kernel
;	if possible
; Entry:
;	AX	= segment
;	CX	= zero if pointer is to data, nonzero if to code
;	
; Returns:
;	AX	= selector
; Error Returns:
;	AX	= zero
; Registers Destroyed:
;	CX,DI,FLAGS
; Registers Preserved:
;	BX,DX,SI,DS,ES,BP
; Calls:
;	AllocDSToCSAlias
;	AllocSelector
;	SetSelectorBase
; History:
;	see Git
;--------------------------------------------------------------------------;
SegToSel	proc near
	mov	di,__WinFlags
	test	di,WF_PMODE
	jnz	@F
	ret	; Real Mode, just give it back as a segment

@@:
	; check if Windows already has an alias for this (e.g. for screen mem)
	test	al,al	; all these ones end with 00
	jnz	@@NotSpecial

	test	ah,ah	; NULL?
	jnz	@F
	ret	; give it back as NULL

@@:
	cmp	ah,0A0h
	jb	@@NotSpecial
	ja	@F
	mov	ax,__A000
	jmp	@@setseltype

@@:
	cmp	ah,0B0h
	jb	@@NotSpecial
	ja	@F
	mov	ax,__B000
	jmp	@@setseltype

@@:
	cmp	ah,0B8h
	jb	@@NotSpecial
	ja	@F
	mov	ax,__B800
	jmp	@@setseltype

@@:
	cmp	ah,0C0h
	jb	@@NotSpecial
	ja	@F
	mov	ax,__C000
	jmp	@@setseltype

@@:
	cmp	ah,0D0h
	jb	@@NotSpecial
	ja	@F
	mov	ax,__D000
	jmp	@@setseltype

@@:
	cmp	ah,0E0h
	jb	@@NotSpecial
	ja	@F
	mov	ax,__E000
	jmp	@@setseltype

@@:
	cmp	ah,0F0h
	jne	@@NotSpecial
	mov	ax,__F000
@@setseltype:
	test	cx,cx
	jz	@F
	push	es	; this gets destroyed by kernel call
	push	dx	; this gets destroyed by kernel call
	cCall	AllocDSToCSAlias,<ax>
	pop	dx
	pop	es
@@:
	ret

@@NotSpecial:
	; OK, we have to set up a new selector to point to this!
	push	es	; this gets destroyed by kernel call
	push	dx	; this gets destroyed by kernel call
	mov	di,ax
	; Copy the screen-buffer selector since it's the right size and type
	test	cx,cx	; Should it be code?
	jz	@F
	cCall	AllocDSToCSAlias,<__A000>
	jmp	@@copied
@@:
	cCall	AllocSelector,<__A000>
@@copied:
	mov	cx,di
	shr	cx,12
	shl	di,4
	cCall	SetSelectorBase,<ax,cx,di>	; CX:DI passed as two words
	pop	dx
	pop	es
	ret
SegToSel	endp

;--------------------------------------------------------------------------;
; FreeSelFromSeg
;	Frees a selector returned by SegToSel, if necessary
; Entry:
;	AX	= segment
;	CX	= zero if pointer is to data, nonzero if to code
;	
; Returns:
;	AX	= zero
; Error Returns:
;	AX	= selector
; Registers Destroyed:
;	CX,DI,FLAGS
; Registers Preserved:
;	BX,DX,SI,DS,ES,BP
; Calls:
;	FreeSelector
; History:
;	see Git
;--------------------------------------------------------------------------;
FreeSelFromSeg	proc near
	cmp	ax,__A000
	je	@@retzero
	cmp	ax,__B000
	je	@@retzero
	cmp	ax,__B800
	je	@@retzero
	cmp	ax,__C000
	je	@@retzero
	cmp	ax,__D000
	je	@@retzero
	cmp	ax,__E000
	je	@@retzero
	cmp	ax,__F000
	je	@@retzero

	push	bx
	push	cx
	push	dx
	cCall	FreeSelector,<ax>
	pop	dx
	pop	cx
	pop	bx
	ret

@@retzero:
	xor	ax,ax
	ret
FreeSelFromSeg	endp

sEnd	InitSeg

END
