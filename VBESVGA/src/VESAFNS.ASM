
;
;	FILE:	vesafns.asm
;	DATE:	6 May 2023
;	AUTHOR: PluMGMK
;
;	This module contains code and data needed for interfacing with VESA
;	BIOS functions.
;

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

; Protected Mode Interface struct (taken straight from VBE 3.0 spec)
PMInfoBlock	struc
Signature	dd ?	; PM Info Block Signature, always "PMID"
EntryPoint	dw ?	; Offset of PM entry point within BIOS
PMInitialize	dw ?	; Offset of PM initialization entry point
BIOSDataSel	dw ?	; Selector to BIOS data area emulation block
A0000Sel	dw ?	; Selector to access A0000h physical mem
B0000Sel	dw ?	; Selector to access B0000h physical mem
B8000Sel	dw ?	; Selector to access B8000h physical mem
CodeSegSel	dw ?	; Selector to access code segment as data
InProtectMode	db ?	; Set to 1 when in protected mode
Checksum	db ?	; Checksum byte for structure
PMInfoBlock	ends


sBegin	Data

externW	ScreenSelector
externW	ColourFormat
EXTRN	dac_size:byte

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

public	PM_STACK_LEN
PM_STACK_LEN	equ 406h
BIOS_DATA_LEN	equ 600h

PMIntHandles	label word
hPMcode		dw 0
hBIOSdata	dw 0
; hPMstack	dw 0
NUM_PMINT_HDLS	equ ($ - PMIntHandles) SHR 1

PMIntEntry	FARPOINTER <?,?>

; Real-Mode buffer for palette entries (if needed)
RMPaletteSel	dw 0
RMPaletteSeg	dw 0

; Scan line length for ease of access in certain parts of the driver...
public	MemWidth
MemWidth	dw ?

sEnd	Data


.286


;---------------------------------Macro---------------------------------;
; CALL_PMINT
;
; calls the VESA Protected Mode Interface, equivalent to int 10h
;
; usage
;
;     CALL_PMINT
;
; Entry:
;       DS      = Data
;	Other registers as per desired int 10h call
; Returns:
;	As per desired int 10h call
; Error Returns:
;	As per desired int 10h call
; Registers Destroyed:
;	As per desired int 10h call
; Registers Preserved:
;	As per desired int 10h call
; History:
;	see Git
;-----------------------------------------------------------------------;
CALL_PMINT	macro
	; we need to save and restore the stack pointer since the spec
	; seems to leave undefined whether the PM interface should return
	; with an IRET or a RETF - i.e. the stack may or may not have
	; flags on it after PMIntEntry returns...
	push	bp
	mov	bp,sp
	pushf
	call	[PMIntEntry]
	mov	sp,bp
	pop	bp
	endm

sBegin  Code
assumes cs,Code

externW		_cstods		; in CURSOR.ASM
externW		pxbytes		; in SWCURS.ASM

; From INT10.ASM
externFP	DoInt10h

; This goes in the Code segment for ease of access, and in case the
; BankSwitch function is included in the buffer (unlikely?)
VESAModeStruct	label byte

OFF_VESA_ATTRS	equ $-VESAModeStruct
VESAModeAttrs	dw ?
VESAWinAAttrs	db ?
VESAWinBAttrs	db ?
VESAGranularity	dw ?	; in kiB, hopefully == 64
VESAWinSize	dw ?	; in kiB, hopefully == 64
VESAWinASeg	dw ?
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
OFF_VBE3	equ $-VESAModeStruct
VESAVBE3p0	db ?	; 1 if VBE 3.0, zero if less
OFF_VESA_RDEPTH	equ $-VESAModeStruct
VESARFieldSize	db ?
VESARFieldPos	db ?
OFF_VESA_GDEPTH	equ $-VESAModeStruct
VESAGFieldSize	db ?
VESAGFieldPos	db ?
OFF_VESA_BDEPTH	equ $-VESAModeStruct
VESABFieldSize	db ?
VESABFieldPos	db ?
VESAAFieldSize	db ?
VESAAFieldPos	db ?
VESADirectMode	db ?	; Bit 0 = programmable ramp, 1 = usable alpha channel
VESALinearBuf	LONG <?,?>	; 32-bit Physical Address
VESAOSMem	LONG <?,?>	; Off-Screen Memory
VESAOSMemSize	dw ?	; in kiB
OFF_VESA_SLLIN	equ $-VESAModeStruct
VESAScanLineLin	dw ?	; same as VESAScanLineLen but for linear modes
VESAImgsBanked	dw ?
VESAImgsLinear	dw ?
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
	jmp	DoInt10h
BankSwitchInt10	endp

BankSwitchPMInt	proc far
	push	ds
	mov	ax,seg PMIntEntry
	mov	ds,ax
	assumes	ds,Data
	mov	ax,(VBE_INT10_FN SHL 8) OR VBE_BANKSWITCH
	CALL_PMINT
	pop	ds
	assumes	ds,nothing
	ret
BankSwitchPMInt	endp

sEnd	Code


createSeg _PALETTE,PaletteSeg,word,public,CODE
sBegin	PaletteSeg

;
;	setramdac
;	PARMS:
;	ax	index to 1st palette entry
;	cx	count of indices to program
;	ds:si	-> 256 double words  (ds MUST!! be driver data segment)
;
;	TODO: fallback to port I/O if VBE < 2.0
;

.286
assumes  cs,PaletteSeg
assumes  ds,Data
assumes  es,nothing

PUBLIC	setramdac
setramdac	PROC	FAR

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

	cmp	[PMIntEntry.sel],0
	jz	@F
	CALL_PMINT

setramdac_exit:
	; restore original byte order
	call	switcheroo
	pop	di
	pop	es
        ret

@@:
	; the way less travelled...
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
	jz	setramdac_exit

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
	jmp	setramdac_exit

setramdac	ENDP

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

assumes	cs,InitSeg
assumes	ds,Data
;--------------------------------------------------------------------------;
; SetupPMInt
;	sets up Protected-Mode Interface to VBE, if needed and available
; Entry:
;	DS	= Data
;	AL	= PMID integrity checking (0=NONE!, 1=checksum, 2=sanity)
; Returns:
;	DX:AX	= selector:offset of VBE entry point
; Error Returns:
;	DX:AX	= zero
; Registers Destroyed:
;	AX,BX,CX,DX,FLAGS
; Registers Preserved:
;	SI,DI,BP,DS,ES
; Calls:
;	AllocDSToCSAlias
;	GlobalAlloc
;	GlobalLock
;	GlobalUnlock
;	GlobalFree
;	FreeSelFromSeg
; History:
;	see Git
;--------------------------------------------------------------------------;
public	SetupPMInt
SetupPMInt	proc near
	test	al,80h	; negative => disable?
	jnz	@@skip
	mov	bh,al	; save the integrity-check mode

	mov	ax,__WinFlags
	test	ax,WF_PMODE
	jnz	@F

@@skip:
	xor	ax,ax	; Real Mode, no PM interface!
@@retnull:
	cwd
	ret

@@:
	push	es
	push	di
	push	si
	push	bp

	mov	ax,__C000
	mov	es,ax
	mov	dx,40h		; assume 32k length if not informed otherwise
	; check if it's an Option ROM
	cmp	word ptr es:[0],0AA55h
	jne	@F
	; if so, get its length in sectors (DH already == 0 from above)
	mov	dl,byte ptr es:[2]
@@:
	shl	dx,9		; convert sectors to bytes

	; scan for the "PMID" signature
	; it does not have to be DWORD- or even WORD-aligned,
	; so we just search for 'P' and check the rest when we find it
	mov	al,'P'
	mov	cx,dx			; search the full length
	xor	di,di			; from the beginning
	sub	cx,size PMInfoBlock	; but don't run off the end!
	cld
@@resume:
	repne	scasb
	je	@F
	; jne @@notfound is too long for 286!
	jmp	@@notfound
@@:
	cmp	byte ptr es:[di],'M'
	jne	@@resume
	cmp	byte ptr es:[di+1],'I'
	jne	@@resume
	cmp	byte ptr es:[di+2],'D'
	jne	@@resume

	; found it! Now make sure it all checks out...
	lea	si,[di-1]	; point at the beginning of the structure
	test	bh,bh		; any integrity checking?
	jz	@@pmidok
	cmp	bh,1
	jna	@@checksum	; go straight to check the sum

	; for BH>1, allow a weaker form of sanity checking
	; (but fall back to checksum if it fails)
	cmp	es:[si.BIOSDataSel],0
	jne	@@checksum
	cmp	es:[si.A0000Sel],0A000h
	jne	@@checksum
	cmp	es:[si.B0000Sel],0B000h
	jne	@@checksum
	cmp	es:[si.B8000Sel],0B800h
	jne	@@checksum
	cmp	es:[si.CodeSegSel],0C000h
	jne	@@checksum
	cmp	es:[si.InProtectMode],0
	je	@@pmidok

@@checksum:
	push	cx
	mov	cx,size PMInfoBlock
	xor	ax,ax
@@:
	lods	byte ptr es:[si]
	add	ah,al
	loop	@B
	pop	cx
	mov	al,'P'
	; AH should now be zero, and ZF set
	jnz	@@resume	; if not, keep looking...

@@pmidok:
	; use BP since it is not destroyed by kernel calls
	lea	bp,[di-1]	; point at the beginning of the structure
	mov	di,dx		; likewise keep length in preserved register

	; now we need to allocate two blocks of memory:
	; 1. one of length DI==DX to contain a copy of the Video BIOS ROM
	; 2. one of length 600h to serve as a surrogate IVT+BDA
	; (the stack is already allocated by SetupInt10h)
	cCall	GlobalAlloc, <GMEM_FIXED,0,di>	; fixed for CS alias
	assumes	es,nothing	; kernel call may destroy ES!
	test	ax,ax
	jnz	@F
	; jnz @@retnull_es is too long for 286!
	jmp	@@retnull_es
@@:
	mov	[hPMcode],ax

	; GHND to make it all zero
	cCall	GlobalAlloc, <GHND,0,BIOS_DATA_LEN>
	test	ax,ax
	jnz	@F
	jmp	@@freehdls
@@:
	mov	[hBIOSdata],ax

	; Got 'em, now lock 'em!
	cCall	GlobalLock, <[hPMcode]>
	test	dx,dx
	jnz	@F
	jmp	@@freehdls

@@:
	; Get ready to start copying stuff into this buffer...
	push	ds
	mov	es,dx

	push	es
	cCall	GlobalLock, <[hBIOSdata]>
	pop	es	; kernel call may destroy ES!
	test	dx,dx
	jnz	@F
	jmp	@@unlockpmcode
@@:
	mov	si,dx

	; finally, get a CS alias for the PM code...
	push	es
	cCall	AllocDSToCSAlias, <es>
	pop	es	; kernel call may destroy ES!
	test	ax,ax
	jz	@@unlockbiosdata
ifdef	INT3
	int	3
endif
	mov	[PMIntEntry.sel],ax

	; OK, now it's time to fill it all in!
	mov	ax,__C000
	mov	ds,ax
	assumes	ds,nothing
	mov	cx,di	; we saved the length in DI
	shr	cx,1	; divide by two to move wordwise
	mov	dx,si	; we put the BIOS data selector in SI

	xor	si,si	; copy the whole lot from the beginning!
	xor	di,di
	cld
	rep	movsw

	; get back the proper DS
	pop	ds
	assumes	ds,Data

	; fill in the selectors as needed
ifdef	INT3
	int	3
endif
	mov	es:[bp.BIOSDataSel],dx
	mov	es:[bp.A0000Sel],__A000
	mov	es:[bp.B0000Sel],__B000
	mov	es:[bp.B8000Sel],__B800
	mov	es:[bp.CodeSegSel],es
	mov	es:[bp.InProtectMode],1

	; get the initialization function and call it
	mov	ax,es:[bp.PMInitialize]
	mov	[PMIntEntry.off],ax
	call	[PMIntEntry]
	; now it's been initialized, the actual entry point is usable!
	mov	ax,es:[bp.EntryPoint]
	mov	[PMIntEntry.off],ax

	; all done!
	pop	bp
	pop	si
	pop	di
	mov	dx,es
	pop	es
	ret

@@notfound:
	xor	ax,ax
@@retnull_es:
	cwd
	pop	bp
	pop	si
	pop	di
	pop	es
	ret

@@unlockbiosdata:
	cCall	GlobalUnlock, <[hBIOSdata]>
@@unlockpmcode:
	pop	es
	cCall	GlobalUnlock, <[hPMcode]>
	pop	ds

@@freehdls:
	mov	cx,NUM_PMINT_HDLS
	lea	si,PMIntHandles
	cld
@@:
	lodsw
	test	ax,ax
	jz	@F
	cCall	GlobalFree, <ax>
	loop	@B
@@:
	jmp	@@notfound
SetupPMInt	endp

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
;	PMIntEntry
;	- OR -
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
	cmp	[PMIntEntry.sel],0
	jz	GetVBEInfo_Real

	push	ds
	pop	es
	assumes	es,Data
	mov	ax,(VBE_INT10_FN SHL 8) OR VBE_GETINFO
	lea	di,VESAInfoStruct
	CALL_PMINT

	; Check if function succeeded
	cmp	ax,VBE_INT10_FN
	mov	di,VBE_ERR_FAIL
	jne	@F

	; Check if the buffer is filled correctly
	; It should now begin with "VESA"
	cmp	word ptr [VESASig],"EV"
	jne	@F
	cmp	word ptr [VESASig+2],"AS"
	jne	@F

	; Success!
	xor	di,di
@@:
	jmp	VBEInfo_Done

GetVBEInfo_Real:	; fallback to Real Mode interface
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
;	PMIntEntry
;	- OR -
;	DoInt10h
;	FixupFarPtr
; History:
;	see Git
;--------------------------------------------------------------------------;
cProc	FindMode,<NEAR,PUBLIC>,<es,ds,di,bx,si,cx>
	parmB	bLinear	; zero if bank-switched mode is desired
	localW	CodeSel	; RW selector to Code segment
cBegin
	; ensure that VBE Info is populated before we use it!
	call	GetVBEInfo

ifdef	INT3
	int	3
endif
	; fail fast if the DAC cannot be set as desired
	cmp	[dac_size],2
	je	@F	; 6-bit DAC is always possible

	test	[VESACaps.lo],VESA_CAP_DAC_8BSWITCH
	jnz	@F	; we're OK

ifdef	INT3
	int	3
endif
	WriteAux <'8-bit DAC specified in profile but not supported by card'>
	mov	di,-1
	jmp	FindMode_reterr

@@:
	push	seg VESAModeStruct
	cCall	AllocCSToDSAlias
	mov	[CodeSel],ax
	test	ax,ax
	mov	di,ERR_PROT_ALLOC
	jnz	@F
	jmp	FindMode_reterr

@@:
	cmp	[PMIntEntry.sel],0
	jz	@F

	; Protected Mode buffer
	mov	es,[CodeSel]
	assumes	es,Code
	lea	di,VESAModeStruct
	jmp	FindMode_bufready

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
	cmp	[PMIntEntry.sel],0
	jz	@F
	CALL_PMINT
	jmp	FindMode_ChkInfo
@@:
	call	DoInt10h

FindMode_ChkInfo:
	mov	ax,es:[di.OFF_VESA_ATTRS]
	; Is it supported by the current hardware?
	test	ax,VESA_ATTR_HWSUPPORT
	jz	FindMode_loop	; NEXT!
	; Is it graphical (not text)?
	test	ax,VESA_ATTR_GRAPHICS
	jz	FindMode_loop	; NEXT!
	; Is it colour (not BW)?
	test	ax,VESA_ATTR_COLOUR
	jz	FindMode_loop	; NEXT!

	cmp	[bLinear],0
	jnz	@F
	; Does it support bank switching?
	test	ax,VESA_ATTR_NOBANKSWITCH
jnelp:	; extra label to allow for short JNE instructions
	jne	FindMode_loop	; NEXT!
	jmp	FindMode_attrsOK
@@:
	; Does it support linear operation?
	test	ax,VESA_ATTR_LINEAR
	jz	FindMode_loop	; NEXT!
	; Set the "linear" flag in the mode number
	or	cx,VESA_FLAG_LINEAR
	; And make sure vesa_gdi_fixup gets the right data!
	cmp	byte ptr es:[di.OFF_VBE3],0
	jz	FindMode_attrsOK
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
	test	al,7		; is our pixel an integer number of bytes?
	jnz	jnelp		; NEXT!

	; Packed pixel?
	cmp	byte ptr es:[di.OFF_VESA_MODEL],VESA_MEM_PACKED
	je	@F				; depth is as given

	; Direct colour?
	cmp	byte ptr es:[di.OFF_VESA_MODEL],VESA_MEM_DIRECT
	; We don't support other models
	jne	jnelp		; NEXT!
	mov	al,es:[di.OFF_VESA_RDEPTH]	; depth is sum of R/G/B vals
	add	al,es:[di.OFF_VESA_GDEPTH]
	add	al,es:[di.OFF_VESA_BDEPTH]

@@:
	; Is it the right depth?
	cmp	al,[VScreen_Depth]
	jne	jnelp		; NEXT!

	; OK, we've found the mode!
	mov	[Vmode],cx
	xor	ax,ax		; return success

ModeFound:
	; if we used the PM interface, then we're done here
	cmp	[PMIntEntry.sel],0
	mov	di,ax		; save our return code
	jnz	FindMode_done

	test	ax,ax		; returning success?
	mov	si,es		; if not, put the DOS buffer in SI
	jnz	@F

	; otherwise, we have to do a load of translation...
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

	test	di,di		; returning success?
	jnz	FindMode_done

	mov	es,[CodeSel]
	assumes	es,Code		; on this codepath, we are sure what ES is
	; Fix up the far pointer
	mov	dx,[int10h_es]
	lea	bx,VESAModeStruct

	lea	si,VESABankSwitch
	mov	cx,seg VESABankSwitch	; code may be placed in this segment!
	call	FixupFarPtr
	test	ax,ax
	mov	di,ERR_PROT_ALLOC
	jz	FindMode_done

	; Fix up the segments too
	xor	cx,cx		; want data segments!
	mov	ax,[VESAWinASeg]
	call	SegToSel
	mov	[VESAWinASeg],ax
	mov	[ScreenSelector],ax
	mov	ax,[VESAWinBSeg]
	call	SegToSel
	mov	[VESAWinBSeg],ax

	xor	di,di	; all good!
FindMode_done:
	test	di,di
	jnz	@F

	; while we're here with a code segment alias,
	; setup modal functions / data for brush realization
	mov	al,[VESABPP]
	shr	al,3	; bits to bytes
	cbw
	mov	[pxbytes],ax
	call	init_modal_realizations

	; while we're at it, set the full colour conversion parameters
	cmp	[VESAMemModel],VESA_MEM_PACKED
	; if using a palette, we don't do this.
	je	@@skipcolourloop

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

	cmp	[PMIntEntry.sel],0
	jz	@F
	mov	[VESABankSwitch.off],offset BankSwitchPMInt

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
RC_PALETTE	equ 0000000100000000b	; can do color palette management
	and	es:[si].dpRaster, NOT RC_PALETTE
@@:

	; now set the ColourFormat too
	pop	ds
	assumes	ds,Data
        mov     ax,wptr es:[di].bmPlanes
	mov	[ColourFormat],ax

	; and the MemWidth
	mov	ax,es:[di].bmWidthBytes
	mov	[MemWidth],ax

	ret
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
	mov	bx,6		; just go set it to six
	jz	common_vesafun

	mov	bx,8		; prepare to set to eight
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
;	ES:DI --> ipd_format in our pDevice
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
