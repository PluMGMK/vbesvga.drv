
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

; VESA Window Attributes
VESA_WINATTR_EXISTS	= 00000001b
VESA_WINATTR_READ	= 00000010b
VESA_WINATTR_WRITE	= 00000100b
; Shortcut for the only type of window we know how to use (for now)
VESA_WINATTR_NORMAL	= VESA_WINATTR_EXISTS+VESA_WINATTR_READ+VESA_WINATTR_WRITE

; VESA Mode Memory Models
VESA_MEM_TEXT	= 0
VESA_MEM_CGA	= 1
VESA_MEM_HGC	= 2
VESA_MEM_EGA	= 3
VESA_MEM_PACKED	= 4
VESA_MEM_SEQ256	= 5
VESA_MEM_DIRECT	= 6	; no palette switching
VESA_MEM_YUV	= 7	; no... :(

; Use MCGA256 mode as a last resort
LASTRESORT_MODE	= 13h
LASTRESORT_WDTH	= 320
LASTRESORT_HGHT	= 200
LASTRESORT_DPTH	= 8

; Detailed Timing Description
DTD	struc
pixclock_10kHz	dw ?	; pixel clock in 10-kHz units
			; NOTE: RBIL and OSDev wiki both claim that this
			; is two bytes, the first being the horizontal
			; rate in kHz and the second being the vertical
			; rate in Hz - but I can't find any evidence that
			; this was ever the case!
horizpixels_low	db ?	; width in pixels
horizblnk_low	db ?	; blanking pixels
horiz_high	db ?	; each nibble is high bits of previous two numbers
vertlines_low	db ?	; height scanlines
vertblnk_low	db ?	; blanking scanlines
vert_high	db ?	; each nibble is high bits of previous two numbers
horizporch_low	db ?
horizsync_low	db ?
vert_low	db ?	; nibbles are low bits of vertical porch and sync
porch_sync_high	db ?	; two highest bits of each of four previous numbers!
horiz_size_mmlo	db ?	; width in millimetres
vert_size_mmlo	db ?	; height in millimetres
size_mmhi	db ?	; each nibble is high bits of previous two numbers
horiz_border	db ?
vert_border	db ?
display_type	db ?
DTD	ends

; Display Descriptor Tag values
TAG_DUMMY	=  10h
TAG_ESTTIMINGS	= 0F7h	; third set of established timings
TAG_CVT3BYTE	= 0F8h
TAG_DCMDATA	= 0F9h
TAG_STDTIMINGS	= 0FAh
TAG_COLOURPTS	= 0FBh
TAG_PRODNAME	= 0FCh
TAG_RANGELIMS	= 0FDh
TAG_ASCII	= 0FEh
TAG_SERIALNO	= 0FFh

DspDesc	struc
resd0	dw ?	; zero
resd2	db ?	; zero
tag	db ?	; see TAG_*
rlimitf	db ?	; Display Range Limits Offsets: FLAGS
descdat	db 13 dup (?)
DspDesc	ends

; EDID info struct (based on VESA E-EDID Standard Release A2)
EDIDblk	struc
; Header
hdr		db 8 dup (?)
; Vendor & Product Identification
id_mfg_name	dw ?
id_prod_code	dw ?
id_serial	dd ?
mfg_week	db ?	; or FFh to indicate model year
mfg_year	db ?	; or model year
; EDID Structure Version & Revision
edid_ver	db ?
edid_rev	db ?
; Basic Display Parameters & Features
vid_input_def	db ?
horiz_size_cm	db ?	; physical monitor width in centimetres
vert_size_cm	db ?	; physical monitor height in centimetres
gamma		db ?
features	db ?
; Colour Characteristics
rg_low_bits	db ?	; Red / Green
bw_low_bits	db ?	; Blue / White
rx_high_bits	db ?	; Red-x
ry_high_bits	db ?	; Red-y
gx_high_bits	db ?	; Green-x
gy_high_bits	db ?	; Green-y
bx_high_bits	db ?	; Blue-x
by_high_bits	db ?	; Blue-y
wx_high_bits	db ?	; White-x
wy_high_bits	db ?	; White-y
; Established Timings
est_timings	dw ?
oem_timings	db ?
; Standard Timings
std_timings	dw 8 dup (?)
; 18-Byte Data Blocks
desc0		db (size DTD) dup (?) ; if EDID >= 1.3, this HAS to be Preferred Timing Desc
desc1		db (size DspDesc) dup (?)
desc2		db (size DspDesc) dup (?)
desc3		db (size DspDesc) dup (?)
; Extension Block Count N
n_extblocks	db ?
; Checksum C
checksum	db ?
EDIDblk	ends

.errnz	(size DTD) - 18
.errnz	(size DspDesc) - 18
.errnz	(size EDIDblk) - 80h

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
	externFP GetSelectorBase
	externFP SetSelectorBase
	externFP AllocDSToCSAlias
	externFP AllocCSToDSAlias
	externFP GlobalDosAlloc
	externFP GlobalDosFree

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
externB	bank_granfac_m1		; in BANK.INC

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

; Are we using a 3-byte-per-pixel video mode, or allowed to search for one?
public	ThreeByte
ThreeByte	db 0

; Physical screen geometry - default to 180-mm tall monitor (same as V7VGA),
; with default width calculated based on aspect ratio of user-chosen resolution
ScreenWidthMM	dw 0	; calculate at runtime
ScreenHeightMM	dw 180

; Which BIOS function to use to set the mode - either 4F02h, or 0013h
ModeSetFn	dw (VBE_INT10_FN SHL 8) + VBE_SETMODE

sEnd	Data


.286


sBegin  Code
assumes cs,Code

externB		??BigFontFlags
externW		_cstods		; in CURSOR.ASM
externW		pxbytes		; in SWCURS.ASM
externFP	sum_RGB_alt_far	; in ROBJECT.ASM
externFP	DoInt10h	; in INT10.ASM
externD		white		; in BLTUTIL.ASM
externD		notwhite	; in BLTUTIL.ASM

; This goes in the Code segment for ease of access, and in case the
; BankSwitch function is included in the buffer (unlikely?)
VESAModeStruct	label byte

OFF_VESA_ATTRS	equ $-VESAModeStruct
VESAModeAttrs	dw ?
OFF_VESA_WATTRS	equ $-VESAModeStruct
VESAWinAAttrs	db ?
VESAWinBAttrs	db ?
OFF_VESA_GRAN	equ $-VESAModeStruct
VESAGranularity	dw ?	; in kiB, hopefully == 64
OFF_VESA_WSIZE	equ $-VESAModeStruct
VESAWinSize	dw ?	; in kiB, hopefully == 64
OFF_VESA_WSEG	equ $-VESAModeStruct
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
OFF_VESA_PLANES	equ $-VESAModeStruct
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
public	red_shl
red_shl		label byte	; how far left to shift red byte before ORing in
VESARFieldPos	db ?
OFF_VESA_GDEPTH	equ $-VESAModeStruct
VESAGFieldSize	db ?
public	green_shl
green_shl	label byte	; how far left to shift green byte before ORing in
VESAGFieldPos	db ?
OFF_VESA_BDEPTH	equ $-VESAModeStruct
VESABFieldSize	db ?
public	blue_shl
blue_shl	label byte	; how far left to shift blue byte before ORing in
VESABFieldPos	db ?
public	PaddingBits
PaddingBits	label byte
OFF_VESA_ADEPTH	equ $-VESAModeStruct
VESAAFieldSize	db ?
VESAAFieldPos	db ?
VESADirectMode	db ?	; Bit 0 = programmable ramp, 1 = usable alpha channel
OFF_VESA_LINBUF	equ $-VESAModeStruct
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
public	green_shr
green_shr	db 0FFh	; how far right to shift green byte (8-GFieldSize)
public	blue_shr
blue_shr	db 0FFh	; how far right to shift blue byte (8-BFieldSize)

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

	; if VBE version < 2.00, then we know immediately we need
	; to do it the old way!
	cmp	[VESAMajVer],2
	jb	setramdac_need_vga

	push	es
	push	di

	; hold onto the first index in a register we won't be trashing
	mov	bx,ax

	cmp	[RMPaletteSel],0
	jnz	@F

	; need to allocate this DOS buffer (only once!)
	; 4 bytes per colour * 100h colours
	push	bx
	push	cx
	cCall	GlobalDosAlloc,<0,400h>	; zero-pad to dword
	mov	[RMPaletteSel],ax
	mov	[RMPaletteSeg],dx
	pop	cx
	pop	bx

	test	ax,ax
	mov	ax,(ERR_REAL_ALLOC SHL 8) + VBE_INT10_FN
	mov	dx,bx	; need this in case we fail
	jz	setramdac_vbe_exit

@@:	mov	ax,[RMPaletteSeg]
	mov	[int10h_es],ax
	; copy the palette entries into the RM buffer
	mov	es,[RMPaletteSel]
	xor	di,di

	; Now we have 8-bit RGBA entries at DS:SI.
	; Per the VBE spec, we require 6/8-bit BGRA entries at ES:DI.
	; Copy them over and convert them as we go!
	push	di
	push	si
	push	cx

	cld
	; put entry count in CH (zero means the loop runs 256 times)
	mov	ch,cl
	; and shift count in CL
	mov	cl,[dac_size]

@@:	; load the colour...
	lodsw
	mov	dx,ax
	lodsw
	; now we have DH=Green, DL=Red, AH=Padding, AL=Blue
	xchg	dh,ah
	; becomes DH=Padding, DL=Red, AH=Green, AL=Blue.
	; now change to 6-bit if needed:
	shr	dl,cl
	; this may put two used bits in the upper end of AL, but
	; the BIOS and hardware will ignore them, so it's OK:
	shr	ax,cl
	; store converted colour
	stosw
	mov	ax,dx
	stosw
	dec	ch
	jnz	@B

	pop	cx
	pop	si
	pop	di

	mov	dx,bx	; first colour index
	xor	bl,bl	; set primary palette
	mov	ax,(VBE_INT10_FN SHL 8) + VBE_PALENTRIES
	call	DoInt10h

setramdac_vbe_exit:
	pop	di
	pop	es

	; success?
	cmp	ax,VBE_INT10_FN
	; get back the index into AX
	mov	ax,dx
	jne	setramdac_need_vga
        ret

setramdac_need_vga:
	; VBE cannot be used to set RAMDAC, so fall back to VGA implementation
	; by updating the function pointer and jumping to it
	mov	[setramdac.lo],offset setramdac_vga
	; go to the VGA function
	jmp	[setramdac]

setramdac_vbe	ENDP

sEnd	PaletteSeg

createSeg _INIT,InitSeg,word,public,CODE
sBegin	InitSeg

externNP	init_modal_realizations	; in ROBJECT.ASM
externNP	setup_double_buf	; in DBLBUF.ASM
externNP	setup_dosx_bugfix	; in DOSXBFIX.ASM

assumes	cs,InitSeg
assumes	ds,Data

;--------------------------------------------------------------------------;
; QueryGeometry
;	allocates a Real-Mode buffer and reads the main monitor's EDID data
;	into it, to determine the screen geometry and preferred resolution
; Entry:
; Returns:
;	AX	= preferred width from first detailed timing description
;	DX	= preferred height from first detailed timing description
;	ScreenWidthMM and ScreenHeightMM set to values from first DTD
;	(or failing that, calculated from centimetre values in EDID block)
; Error Returns:
;	AX	= 1024 (sane default)
;	DX	=  768 (sane default)
;	ScreenWidthMM and ScreenHeightMM remain at default values
; Registers Destroyed:
;	FLAGS
; Registers Preserved:
;	BX,CX,SI,DI,DS,ES,BP
; Calls:
;	GlobalDosAlloc
;	DoInt10h
; History:
;	see Git
;--------------------------------------------------------------------------;
cProc	QueryGeometry,<NEAR,PUBLIC>,<es,di,bx,si,cx>
cBegin
	; start with an installation check
	mov	ax,(VBE_INT10_FN SHL 8) OR VBE_GETEDID
	xor	bl,bl
	int	10h
	cmp	ax,VBE_INT10_FN	; success?
	je	@F
	; ensure we don't try to free a DOS memory block
	; that hasn't even been allocated yet!
	xor	ax,ax
	mov	es,ax
	jmp	EDIDInfo_fail

@@:	mov	ax,size EDIDblk
	cCall	GlobalDosAlloc,<0,ax>	; zero-pad to dword
	mov	es,ax
	test	ax,ax
	jnz	@F
	jmp	EDIDInfo_fail

@@:	; Set ES:DI for int 10h call
	mov	[int10h_es],dx
	xor	di,di

	mov	ax,(VBE_INT10_FN SHL 8) OR VBE_GETEDID
	mov	bl,1
	xor	cx,cx
	xor	dx,dx
	call	DoInt10h
	cmp	ax,VBE_INT10_FN	; success?
	je	@F
	jmp	EDIDInfo_fail

@@:	; check for valid header block
	mov	al,0FFh
	mov	ah,es:[di]
	; first byte should be 0 or FFh
	cmp	ah,al
	je	@F
	test	ah,ah
	jnz	EDIDInfo_fail
@@:	; bytes 1-6 should be FFh
	inc	di
	mov	cx,6
	cld
	repe	scasb
	jne	EDIDInfo_fail
	; last byte should be same as first
	mov	al,ah
	scasb
	jne	EDIDInfo_fail

	; now check the checksum - the full structure should sum to zero
	xor	ah,ah
	mov	cx,size EDIDblk
	xor	si,si
@@:
	lods	byte ptr es:[si]
	add	ah,al
	loop	@B
	; AH should now be zero, and ZF should be set
	jnz	EDIDInfo_fail

	; get the screen geometry
	mov	cl,10		; cm -> mm conversion factor
	; physical width
	mov	al,es:[horiz_size_cm]
	test	al,al
	jz	EDIDInfo_fail	; invalid geometry
	mul	cl
	mov	dx,ax
	; physical height
	mov	al,es:[vert_size_cm]
	test	al,al
	jz	EDIDInfo_fail	; invalid geometry
	mul	cl
	; save the geometry from the EDID block
	mov	[ScreenWidthMM],dx
	mov	[ScreenHeightMM],ax

	; now try to find the preferred resolution - should be in the
	; first detailed timing descriptor
	cmp	es:[desc0.pixclock_10kHz],0
	; FIXME: should we be using this pixel clock value for something?
	jz	EDIDInfo_fail	; this is not a timing descriptor!
	; NOTE: we're not going to bother looking at standard timings
	; or any of that nonsense - let's just provide ONE resolution
	; that the user can override if it doesn't suit. Otherwise
	; things will get really confusing with potentially multiple
	; calls to FindMode, and only being able to report the results
	; of the last one, and stuff like that...

	; get the geometry associated with this timing
	mov	al,es:[desc0.horiz_size_mmlo]
	mov	dx,word ptr es:[desc0.vert_size_mmlo]
	mov	ah,dh
	; extract the upper nibble of size_mmhi to get the upper byte
	; of the width...
	shr	ah,4
	; and the lower nibble of size_mmhi to get the upper byte of
	; the height - confused yet?
	and	dh,0Fh
	; save the geometry from the timing descriptor
	mov	[ScreenWidthMM],ax
	mov	[ScreenHeightMM],dx

	; get the actual resolution
	mov	al,es:[desc0.horizpixels_low]
	mov	ah,es:[desc0.horiz_high]
	shr	ah,4	; upper nibble
	mov	dl,es:[desc0.vertlines_low]
	mov	dh,es:[desc0.vert_high]
	shr	dh,4	; upper nibble

	; put them in SI/DI to prepare for return
	mov	si,ax
	mov	di,dx
	jmp	EDIDInfo_done
	
EDIDInfo_fail:
	; setup to return default values
	mov	si,1024
	mov	di,768

EDIDInfo_done:
	; free the Real-Mode block
	mov	ax,es
	test	ax,ax
	jz	@F
	cCall	GlobalDosFree,<es>

@@:	mov	ax,si
	mov	dx,di
cEnd

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
;	runs through the list of available SVGA modes, scoring each one
;	by the 1-norm of its distance from the desired criteria in config
;	space (coords are width and height in pixels, depth in bits, and
;	binary banked/linear) - it then fills the info (including the
;	bank-switch function pointer) for the lowest-scoring mode into
;	the VESAModeStruct
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
	; bLinear states:
	; 1 = linear mode is desired - score penalty for banked-only modes
	; 0 = linear mode NOT desired - score penalty for linear-only modes
	; -1 = linear mode _impossible_ - skip linear-only modes
	parmB	bLinear

	; locals:
	localW	CodeSel	; RW selector to Code segment
	localW	BestScore
	localB	GranFac	; granularity factor for current mode
	localB	LastResortChecked

	; temporary storage for global variables that may need to change
	; if we fall into last-resort mode:
	localW	LocalModeSetFn
	localB	LocalDacSize
cBegin
	; initialize "best score" to worst possible value
	or	[BestScore],-1
	; we have not checked the last-resort mode yet
	mov	[LastResortChecked],0
	mov	[LocalModeSetFn],(VBE_INT10_FN SHL 8) + VBE_SETMODE

	; do a few checks before agreeing to search for a linear mode
	mov	ax,__WinFlags
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
	call	setup_dosx_bugfix
	; if CF set, then set bLinear to -1 to indicate linear impossible
	sbb	al,al
	or	[bLinear],al
	jmp	short @F

LinRealMode:
ifdef	INT3
public	LinRealMode
	int	3
endif
	WriteAux <'Linear framebuffer not usable in Real Mode.'>
	; set bLinear to -1 to indicate linear impossible
	mov	[bLinear],-1

@@:	; ensure that VBE Info is populated before we use it!
	call	GetVBEInfo

ifdef	INT3
public	VBEInfoReady
VBEInfoReady:
	int	3
endif
	; set the DAC size to the best available if necessary
	mov	al,[dac_size]
	cmp	al,-1	; "auto" setting?
	jne	@F

	mov	al,byte ptr [VESACaps.lo]
	not	al
	and	al,VESA_CAP_DAC_8BSWITCH
	; now AL == 1 if it CANNOT be switched to 8-bit, 0 if it can
	shl	al,1	; set to 2 (i.e. 8 minus 6) if applicable
.errnz	(VESA_CAP_DAC_8BSWITCH - (2 SHR 1))
@@:	mov	[LocalDacSize],al

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
	jne	getmodeinfo

	; if we're at the end of the line, we may still need
	; to check the last-resort mode...
	cmp	[LastResortChecked],0
	jz	@F
	; if it's already been checked, go to end of loop
	jmp	ModeFound

@@:	; ensure next round of loop will turn up -1 again
	sub	si,2
	call	check_last_resort
	; for last-resort mode, use old BIOS function (AH=0) for modeset
	mov	[LocalModeSetFn],cx
	; and force 6-bit (8 minus 2) DAC
	mov	[LocalDacSize],2
	jmp	short gotmodeinfo

getmodeinfo:
	mov	ax,(VBE_INT10_FN SHL 8) OR VBE_GETMODEINFO
	call	DoInt10h

gotmodeinfo:
	; is this the last-resort mode we're checking?
	; (some BIOSes, like SeaBIOS, include it in the list,
	; so this case may come up naturally!)
	cmp	cx,LASTRESORT_MODE
	jne	@F
	mov	[LastResortChecked],1

@@:	mov	bx,es:[di.OFF_VESA_ATTRS]
	mov	al,bl
	and	al,low (VESA_ATTR_HWSUPPORT OR VESA_ATTR_GRAPHICS OR VESA_ATTR_COLOUR)
	; Is it supported by the current hardware, AND graphical (not text),
	; AND colour (not BW)?
	cmp	al,low (VESA_ATTR_HWSUPPORT OR VESA_ATTR_GRAPHICS OR VESA_ATTR_COLOUR)
; extra label to allow short JNE instruction further down
jnelp:	jne	FindMode_loop	; NEXT!

	; if this mode can be bank-switched, then sanity-check the window
	test	bl,low VESA_ATTR_NOBANKSWITCH
	jnz	@F

	; Check 1: is Window A read-write? If not, then it's probably something
	; like Window A to read and Window B to write, or vice versa, which is
	; cool, don't get me wrong, but not something we support here...
	cmp	byte ptr es:[di.OFF_VESA_WATTRS],VESA_WINATTR_NORMAL
	jne	@@winbad

	; Check 2: is the window size 64k or smaller? We can't address more
	; than one segment of memory at a time.
	mov	ax,es:[di.OFF_VESA_WSIZE]
	cmp	ax,64
	ja	@@winbad
	; we will reuse the results of this comparison in a minute
	lahf
	mov	dx,ax

	; Check 3: is the window size an integer multiple of the granularity?
	cbw
	div	byte ptr es:[di.OFF_VESA_GRAN]
	test	ah,ah
	jnz	@@winbad
	; while we're at it, record the multiplication factor
	mov	[GranFac],al
	
	; Check 4: is the window size either 64k or an integer multiple of
	; the memory width? All the code that handles scanlines crossing
	; a window boundary assumes those boundaries are at the end of a
	; segment, i.e. 64k intervals, so don't mess with that assumption!
	; get back window size and results of comparison
	mov	ax,dx
	sahf
	je	@F		; if equal, then WinSize == 64k, so we're good
	; here we know we have WinSize < 64k, since we already discounted 
	; > 64k in Check 2
	cbw
	shl	ax,10		; convert kiB to bytes
	cwd
	; FIXME: we do this exact same calculation later on in vesa_gdi_fixup,
	; but there, unlike here, it's unconditional - even so, a bit wasteful?
	div	word ptr es:[di.OFF_VESA_SLL]
	test	dx,dx		; check remainder
	jz	@F
@@winbad:
	; right, we can't bank-switch this mode, so don't try
	or	bl,low VESA_ATTR_NOBANKSWITCH

@@:	; If we're on a 286, we can't handle an address with over 24 bits
	mov	ax,__WinFlags
	test	ax,WF_CPU286
	jz	@F
	cmp	byte ptr es:[di.OFF_VESA_LINBUF+3],0
	jz	@F
	; clear linear attribute since we can't use it as a linear mode
	and	bl,NOT (low VESA_ATTR_LINEAR)

@@:	; at this point, the sanity checks may have left us with a mode that
	; can be neither bank-switched nor linear, which isn't a whole lot of
	; use to anyone!
	mov	al,bl
	and	al,low (VESA_ATTR_LINEAR OR VESA_ATTR_NOBANKSWITCH)
	cmp	al,low VESA_ATTR_NOBANKSWITCH
	jne	@F
	jmp	FindMode_loop	; NEXT!

@@:	mov	al,[bLinear]
	cbw
	; Now bLinear (in AX) is tri-state, and there are two relevant binary
	; attrs (in BX), so the truth table is theoretically quite complex...
	; Abbreviations:
	; * "NBS" = state of VESA_ATTR_NOBANKSWITCH bit
	; * "LIN" = state of VESA_ATTR_LINEAR bit
	; * "UBM" = use banked mode for score calculation
	; * "ULM" = use linear mode for score calculation
	; * "PEN" = score += 1 ("penalty")
	; * "SKIP" = skip mode without calculating score
	; +-----+-------++--------------+---------------+---------------+
	; | NBS	| LIN	|| bLinear -1	| bLinear 0	| bLinear 1	|
	; +-----+-------++--------------+---------------+---------------+
	; | 0	| 0	|| UBM		| UBM		| UBM, PEN	|
	; | 0	| 1	|| UBM		| UBM		| ULM		|
	; | 1	| 0	|| ============ this can't happen! ============ |
	; | 1	| 1	|| SKIP		| ULM, PEN	| ULM		|
	; +-----+-------++--------------+---------------+---------------+
	and	ah,bl	; AH & NBS := 1 if bLinear == -1, 0 otherwise
	test	ah,low VESA_ATTR_NOBANKSWITCH
	jnz	jnelp	; NEXT!

	; Now that we've dealt with the SKIP case, the truth table can
	; be simplified to the following:
	; +-----+-------++--------------+---------------+
	; | NBS	| LIN	|| bLinear -1/0	| bLinear 1	|
	; +-----+-------++--------------+---------------+
	; | 0	| 0	|| UBM		| UBM, PEN	|
	; | 0	| 1	|| UBM		| ULM		|
	; | 1	| 1	|| ULM, PEN	| ULM		|
	; +-----+-------++--------------+---------------+

	; we can condense the -1 and 0 cases into a single 0 case like so:
	inc	al
	shr	al,1
	cbw	; zero AH

	; now set AH := PEN == (bLinear & !LIN) | (NBS & !bLinear)
	; (note that "NBS" and "!LIN" are mutually exclusive, so
	;  the two sides of the "|" can be checked independently)
	test	bl,low VESA_ATTR_LINEAR
	jnz	@F
	; !LIN => AH := PEN == bLinear
	mov	ah,al

@@:	test	bl,low VESA_ATTR_NOBANKSWITCH
	jz	@F
	; NBS => AH := PEN == !bLinear
	mov	ah,al
	xor	ah,1

@@:	; start accumulating the score in DX
	mov	dh,ah
	shr	dx,8		; DX := zero-extended DH

	; now that PEN is calculated in AH, and the binary bLinear
	; is in AL, the truth table is further simplified as follows:
	; +-------------++--------------+---------------+
	; | AH (PEN)	|| AL == 0	| AL == 1	|
	; +-------------++--------------+---------------+
	; | 0		|| UBM		| ULM		|
	; | 1		|| ULM		| UBM		|
	; +-------------++--------------+---------------+
	; since PEN just means we're using a mode that's the opposite
	; of what we want. So it's just a XOR now!
	xor	ah,al
	; Zero <=> UBM
	jz	FindMode_attrsOK

	; Set the "linear" flag in the mode number
	or	ch,high VESA_FLAG_LINEAR
	mov	[GranFac],1
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
	; Calculate score contribution for the width...
	mov	ax,es:[di.OFF_VESA_WIDTH]
	sub	ax,[VScreen_Width]
	jns	@F
	; ensure positive
	neg	ax
@@:	add	dx,ax

	; Calculate score contribution for the height...
	mov	ax,es:[di.OFF_VESA_HEIGHT]
	sub	ax,[VScreen_Height]
	jns	@F
	; ensure positive
	neg	ax
@@:	add	dx,ax

	mov	al,es:[di.OFF_VESA_DEPTH]
	mov	ah,al
	; Packed pixel?
	cmp	byte ptr es:[di.OFF_VESA_MODEL],VESA_MEM_PACKED
	je	@F		; depth is as given

	; Direct colour?
	cmp	byte ptr es:[di.OFF_VESA_MODEL],VESA_MEM_DIRECT
	; We don't support other models
	jne	baddepth	; NEXT!

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
	; set the ADEPTH field which may be used elsewhere in the driver
	sub	bl,ah
	mov	es:[di.OFF_VESA_ADEPTH],bl

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

	; Calculate score contribution for the significant depth...
	sub	ah,[VScreen_Depth]
	jns	@F
	; ensure positive
	neg	ah
@@:	shr	ax,8		; AX := zero-extended AH
	add	dx,ax

	; check the score...
	cmp	dx,[BestScore]
	jb	@F
	; if it's no better than anything else we've checked,
	; forget about this mode
	jmp	FindMode_loop

@@:	; if this is a good candidate, then update the best score!
	mov	[BestScore],dx

	; then set the parameters for the driver...
	mov	[Vmode],cx
	mov	al,[GranFac]
	mov	ah,[LocalDacSize]
	dec	al
	mov	cx,[LocalModeSetFn]
	mov	[bank_granfac_m1],al
	mov	[dac_size],ah
	mov	[ModeSetFn],cx

	; we have to do a load of segment translation...
	push	ds
	push	si
	push	es
	push	di

	push	es
	pop	ds
	assumes	ds,nothing
	; DS:SI = Real Mode buffer
	xor	si,si

	mov	es,[CodeSel]
	assumes	es,Code
	; ES:DI = Protected Mode buffer
	lea	di,VESAModeStruct

	; Copy the buffer back out...
	mov	cx,VESA_MODE_LEN SHR 1
	cld
	rep	movsw

	; Put back the segments...
	pop	di
	pop	es
	assumes	es,nothing
	pop	si
	pop	ds
	assumes	ds,Data

	; perfect score?
	test	dx,dx
	jz	ModeFound	; if so, we're done
	jmp	FindMode_loop	; otherwise, go check next mode...

ModeFound:
	; done with the Real Mode buffer, so free it
	cCall	GlobalDosFree,<es>

	mov	es,[CodeSel]
	assumes	es,Code

	mov	di,VBE_ERR_FAIL	; error code to return if no mode found
	cmp	[Vmode],0
	jz	@@segfix_done

	; set pxbytes now because we may need it for setup_double_buf
	mov	al,[VESABPP]
	shr	al,3	; bits to bytes
	cbw
	mov	[pxbytes],ax

	; mark whether or not we end up using a three-byte mode
	; (in theory this could be used to enable/disable awkward code paths)
	cmp	al,3
	jne	@F
	inc	ah
@@:	mov	[ThreeByte],ah

	; Calculate total framebuffer size:
	mov	ax,[MemoryWidth]
	mul	[VESAHeight]
	; again we may need it for setup_double_buf
	mov	[MemSize.hi],dx
	mov	[MemSize.lo],ax

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
	jz	@@segfix_done

	; Fix up the segments too
	xor	cx,cx		; want data segments!
	test	[VESAWinAAttrs],VESA_WINATTR_EXISTS
	jz	@F
	mov	ax,[VESAWinASeg]
	call	SegToSel
	mov	[VESAWinASeg],ax

@@:	test	[VESAWinBAttrs],VESA_WINATTR_EXISTS
	jz	@F
	mov	ax,[VESAWinBSeg]
	call	SegToSel
	mov	[VESAWinBSeg],ax

@@:	xor	di,di	; all good!
@@segfix_done:
	jmp	FindMode_done

FindMode_setuplin:
ifdef	INT3
public	FindMode_setuplin
	int	3
endif
	; Even if we're not doing double buffering, this function handles
	; mapping the linear framebuffer.
	call	setup_double_buf
	; Ensure the map succeeded
	mov	ax,[VESALinearBuf.lo]
	or	ax,[VESALinearBuf.hi]
	mov	di,ERR_PROT_ALLOC
	jz	FindMode_done

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

	; Also ensure the window size and granularity are correctly set to 64k
	mov	ax,64
	mov	[VESAWinSize],ax
	mov	[VESAGranularity],ax

	; Our soft window is read-write and definitely exists
	mov	[VESAWinAAttrs],VESA_WINATTR_NORMAL

	xor	di,di
FindMode_done:
	test	di,di
	jz	@F
	jmp	@@donewithsel

@@:	; Set ScreenSelector based on what has taken place above
	mov	ax,[VESAWinASeg]
	mov	[ScreenSelector],ax

	; and feed back into VScreen_*, since they may not exactly match
	; what was requested!
	mov	ax,[VESAWidth]
	mov	dx,[VESAHeight]
	mov	[VScreen_Width],ax
	mov	[VScreen_Height],dx

	; while we're here with a code segment alias,
	; setup modal functions / data for brush realization
	mov	ax,__WinFlags			; setup for 3.0 fonts
        test    ax,WF_PMODE                     ; protected mode?
        jz      @F
        test    ax,WF_CPU386+WF_CPU486          ; 386/486 protected mode?
        jz      @F
;
; change our code-segment-based variable to reflect the mode
;
	mov	byte ptr es:[??BigFontFlags],-1
@@:	mov	dh,[VESAMemModel]
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
	stosb
	loop	@@colourloop
	pop	di
	pop	si

@@skipcolourloop:
	; now that the "shl" and "shr" bytes are set correctly, we can get
	; the physical representation of "white", to be used (if needed)
	; by masking functions
	xor	ax,ax
	mov	dh,al
	not	ax
	mov	dl,al
	call	sum_RGB_alt_far
	mov	[white.lo],ax
	mov	[white.hi],dx
	not	ax
	not	dx
	mov	[notwhite.lo],ax
	mov	[notwhite.hi],dx

	; setup a fallback bank-switch function, just in case we somehow got
	; this far without one...
	cmp	[VESABankSwitch.sel],0
	jnz	@@donewithsel

	mov	[VESABankSwitch.sel],seg BankSwitchInt10
	mov	[VESABankSwitch.off],offset BankSwitchInt10

@@donewithsel:
	; time to free the selector
	cCall	FreeSelector,<[CodeSel]>
	assumes	es,nothing

FindMode_reterr:
	mov	ax,di		; get error code
cEnd

;--------------------------------------------------------------------------;
; check_last_resort
;	fills in a pseudo-mode-descriptor at ES:DI, corresponding to
;	MCGA256 mode, which is our mode of last resort
; Entry:
;	ES:DI	= destination buffer
; Returns:
;	ES:DI filled
;	CX	= mode number (13h)
;
; Registers Destroyed:
;	None
; Registers Preserved:
;	AX,BX,DX,SI,DI,DS,ES,BP,FLAGS
; Calls:
;	Nothing
; History:
;	see Git
;--------------------------------------------------------------------------;
check_last_resort	proc near
	; the following attributes apply to MCGA256 mode:
	mov	word ptr es:[di.OFF_VESA_ATTRS],VESA_ATTR_HWSUPPORT OR VESA_ATTR_BIOS_OP OR VESA_ATTR_COLOUR OR VESA_ATTR_GRAPHICS OR VESA_ATTR_DBLSCAN
	; the window is a normal one, at A000h
	mov	byte ptr es:[di.OFF_VESA_WATTRS],VESA_WINATTR_NORMAL
	mov	word ptr es:[di.OFF_VESA_WSEG],0A000h
	; pretend we've a granularity and window size of 64 kiB
	; (in fact it's a size of 64 kB, not kiB, and no granularity
	; since there's no bank switching)
	mov	word ptr es:[di.OFF_VESA_GRAN],64
	mov	word ptr es:[di.OFF_VESA_WSIZE],64
	; set the actual attributes
	mov	word ptr es:[di.OFF_VESA_SLL],LASTRESORT_WDTH
	mov	word ptr es:[di.OFF_VESA_WIDTH],LASTRESORT_WDTH
	mov	word ptr es:[di.OFF_VESA_HEIGHT],LASTRESORT_HGHT
	mov	byte ptr es:[di.OFF_VESA_DEPTH],LASTRESORT_DPTH
	; single plane, packed pixel
	mov	byte ptr es:[di.OFF_VESA_PLANES],1
	mov	byte ptr es:[di.OFF_VESA_MODEL],VESA_MEM_PACKED
	; finally, set the mode number
	mov	cx,LASTRESORT_MODE
	ret
check_last_resort	endp

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

	mov	cx,[VESAScanLineLen]
        mov     es:[di].bmWidthBytes,cx
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

	; and the MemWidth
	mov	ax,es:[di].bmWidthBytes
	mov	[MemWidth],ax
	mov	ax,[MemSize.lo]
	mov	dx,[MemSize.hi]
        mov     es:[di].bmWidthPlanes.lo,ax
        mov     es:[di].bmWidthPlanes.hi,dx

	; geometry
	push	bp
	push	di
	mov	bp,es:[si].dpHorzRes
	mov	di,es:[si].dpVertRes

	mov	bx,[ScreenWidthMM]
	mov	cx,[ScreenHeightMM]
	test	bx,bx
	jnz	screen_size_known

	; we failed to detect the screen width, so calculate it from the height
	; and the aspect ratio of the specified resolution
	cmp	bp,640
	ja	@F

	; if we're on one of those old small CGA/EGA-era resolutions, the geometry
	; is for a 4:3 screen, even if the pixels are a bit squished!
	mov	ax,cx
	shl	ax,2	; multiply by 4
	cwd
	mov	bx,3
	div	bx	; divide by 3
	mov	bx,ax
	jmp	screen_size_known

@@:	mov	ax,cx
	mul	bp
	div	di
	mov	bx,ax

screen_size_known:
	mov	es:[si].dpHorzSize,bx
	mov	es:[si].dpVertSize,cx

	; calculate parameters related to the physical size
	; metric low-res window: dpMLoWin / dpMLoVpt = dpHorzSize*10 / dpHorzRes
	; since dpMLoVpt == 4, we multiply by 10*4=40 and divide by dp{Horz,Vert}Res
	mov	ax,bx
	mov	dx,40
	mul	dx
	div	bp
	mov	es:[si].dpMLoWin.xcoord,ax
	mov	ax,cx
	mov	dx,40
	mul	dx
	div	di
	mov	es:[si].dpMLoWin.ycoord,ax
	; metric high-res window: dpMHiWin / dpMHiVpt = dpHorzSize*100 / dpHorzRes
	; since dpMHiVpt == 4, we multiply by 100*4==400 and divide by dp{Horz,Vert}Res
	mov	ax,bx
	mov	dx,400
	mul	dx
	div	bp
	mov	es:[si].dpMHiWin.xcoord,ax
	mov	ax,cx
	mov	dx,400
	mul	dx
	div	di
	mov	es:[si].dpMHiWin.ycoord,ax
	; English low-res window: dpELoWin / dpELoVpt = dpHorzSize*1000 / dpHorzRes*254
	; since dpELoVpt == 254, we multiply by 1000 and divide by dp{Horz,Vert}Res
	mov	ax,bx
	mov	dx,1000
	mul	dx
	div	bp
	mov	es:[si].dpELoWin.xcoord,ax
	mov	ax,cx
	mov	dx,1000
	mul	dx
	div	di
	mov	es:[si].dpELoWin.ycoord,ax
	; English high-res window: dpEHiWin / dpEHiVpt = dpHorzSize*10000 / dpHorzRes*254
	; since dpEHiVpt == 254, we multiply by 10000 and divide by dp{Horz,Vert}Res
	mov	ax,bx
	mov	dx,10000
	mul	dx
	div	bp
	mov	es:[si].dpEHiWin.xcoord,ax
	mov	ax,cx
	mov	dx,10000
	mul	dx
	div	di
	mov	es:[si].dpEHiWin.ycoord,ax
	; Twip window: dpTwpWin / dpTwpVpt = dpHorzSize*14400 / dpHorzRes*254
	; since dpTwpVpt == 254, we multiply by 14400 and divide by dp{Horz,Vert}Res
	mov	ax,bx
	mov	dx,14400
	mul	dx
	div	bp
	mov	es:[si].dpTwpWin.xcoord,ax
	mov	ax,cx
	mov	dx,14400
	mul	dx
	; QUESTION: can this overflow, and hence crash Windows on boot?
	; ANSWER: minimum denominator in this situation is DI==480==1E0h, so we would
	;	  need to have a situation where dpVertSize*14400 >= 1E00000h, meaning
	;	  dpVertSize >= 2185, i.e. 2.185 metres - I'd say it's unlikely!
	div	di
	mov	es:[si].dpTwpWin.ycoord,ax

	; lastly, correct the pixel aspect ratio if we're using an old sub-640*480 res
	mov	dl,byte ptr es:[si].dpAspectX
	mov	dh,byte ptr es:[si].dpAspectY
	mov	ax,es:[si].dpAspectXY

	cmp	bp,640
	ja	geometry_done
	jb	check_320

	cmp	di,480
	jae	geometry_done
	; 640*400 is 4:2.5, implying 2.5:3 pixels
	mov	dl,30	; 36*2.5/3
	mov	ax,47	; approx sqrt(30^2 + 36^2)
	cmp	di,400
	jae	fix_dpi
	; 640*350: use the values from EGA.ASM
	mov	dl,38
	mov	dh,48
	mov	ax,61
	cmp	di,350
	jae	fix_dpi
	; 640*200 is 4:1.25, implying 1.25:3 pixels
	mov	dl,20	; 48*1.25/3
	mov	ax,52	; exactly sqrt(20^2 + 48^2)
	cmp	di,200
	jae	fix_dpi
	; unreachable since DI < 200 is not allowed!

check_320:
	cmp	bp,320
	ja	geometry_done
	cmp	di,200
	ja	geometry_done
	; 320*200 is 4:2.5, implying 2.5:3 pixels
	mov	dl,30	; 36*2.5/3
	mov	ax,47	; approx sqrt(30^2 + 36^2)

fix_dpi:
	; first set the new hypotenuse
	mov	es:[si].dpAspectXY,ax
	; then correct the DPI aspect ratio based on the pixel one
	mov	al,byte ptr es:[si].dpLogPixelsX
	mul	dl
	div	dh
	mov	byte ptr es:[si].dpLogPixelsY,al

geometry_done:
	; done with the geometric calculations
	pop	di
	pop	bp

	; keep a copy of the raster flags in Data, as InitSeg is discardable!
	mov	ax,es:[si].dpRaster
	mov	[raster_flags],ax
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
	mov	ax,[ModeSetFn]
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
