        page    ,132
;
;-----------------------------Module-Header-----------------------------;
; Module Name:	ENABLE.ASM
;
; This module contains the routine which is called when the device
; is to either enable itself or return it's GDIINFO.
;
; Created: 16-Jan-1987
; Author:  Walt Moore [waltm]
;
; Copyright (c) 1983-1987 Microsoft Corporation
;
; Exported Functions:	Enable
;
; Public Functions:	none
;
; Public Data:		_cstods
;
; General Description:
;
;	The Display is called to enable itself on one of two occasions.
;
;	The first situation where the Disable routine is called is
;	when Windows is starting the session.  For this situation,
;	the driver will also be asked to return information about
;	the device hardware (e.g. resolution, etc).
;
;	The second is when an old application was run (e.g. WORD).
;	In this instance, Enable will be called to enable the display
;	hardware after the old application ran.
;
;	Unfortunately, there is no way to distinguish these two modes.
;
; Restrictions:
;
; History:
;
;-----------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.

incDevice	= 1

	.xlist
	include cmacros.inc
	include macros.mac
	include gdidefs.inc
	include display.inc
	include rt.mac
	include int3.inc
        .list

	externNP hook_int_2Fh		;Hook into multiplexed interrupt
	externNP start_double_buf	;Start double-buffering timer if needed
	externA  PHYS_DEVICE_SIZE	;Size of physical device
	externA  __WinFlags		;Windows info bit
        externA  __B800
	externFP FatalExit
	externFP AllocSelector		; allocate a new selector
	externFP PrestoChangeoSelector	; CS <--> DS conversion
	externFP FreeSelector		; free an allocated selector
	externFP AllocCSToDSAlias
	externFP GetPrivateProfileString
        externFP GetPrivateProfileInt   ; Kernel!GetProfileInt
	externFP LoadLibrary
	externFP FreeLibrary
	externFP GetProcAddress
	externFP FindResource
	externFP LoadResource
	externFP FreeResource
	externFP LockResource
	externFP GlobalUnlock

ifdef PALETTES
	externFP SetPaletteTranslate    ;in color\ega\vga\palette.asm
endif

	; DPI sizes in VGA.ASM
	externA	DPI_TINY
	externA	DPI_SMALL
	externA	DPI_LARGE

MAXFNAMELEN	equ	64

OCR_ICOCUR	  =  32647
OCR_NORMAL	  =  32512
RT_ICON         = 3
RT_FONTDIR      = 7
RT_FONT         = 8
DIFFERENCE       =   11
RT_GROUP_ICON    =   RT_ICON + DIFFERENCE

sBegin  Data

EXTRN	cursor_xcoord:WORD
EXTRN	cursor_ycoord:WORD
EXTRN	cursor_xdraw:WORD
EXTRN	cursor_ydraw:WORD
EXTRN	dac_size:byte
EXTRN	windowsVersion:WORD	;Windows version number

dpi_size	dw	DPI_SMALL
Profile_read	dw	0
prefer_bank     dw      0
aszSystemIni	db	"system.ini",0
aszCurDrvFName	db	MAXFNAMELEN DUP(0)
public	garish_palette
garish_palette	db	0
public	special_blits
special_blits   db      1

SYSINI	STRUC
    SYSINI_CMPSTR	DW	0
    SYSINI_CMPLEN	DW	0
    SYSINI_RETVAL	DW	0
SYSINI	ENDS

; error messages
fail_reason	dw	offset general_fail
bad_width	db	'Width < 320 is not allowed',13,10,'$'
bad_height	db	'Height < 200 is not allowed',13,10,'$'
bad_depth	db	'Depth < 8 is not allowed',13,10,'$'
bad_interval	db	'Swap-buffers interval > 55 ms is not allowed',13,10
		db	'(Note that a value of 0 disables double buffering)',13,10,'$'
general_fail	db	'No usable modes found at all, not even "last-resort" MCGA256 mode!',13,10
		db	'This probably means you are trying to run this driver on MDA/CGA/EGA...',13,10,'$'
bad_hardware	db	'VESA BIOS says function not supported by current hardware configuration',13,10,'$'
bad_mode	db	'VESA BIOS says function not supported in current mode',13,10,'$'
real_alloc_fail	db	'Unrecoverable DOS memory allocation error during mode search',13,10,'$'
prot_alloc_fail	db	'Unrecoverable memory allocation / mapping error during mode search',13,10,'$'
press_key	db	'Press any key to abort booting Windows...',13,10,'$'

; map of return codes from FindMode to error messages
vesa_err_msgs	dw	offset general_fail
		dw	offset bad_hardware
		dw	offset bad_mode
		dw	offset real_alloc_fail
		dw	offset prot_alloc_fail

boot_category   db      "VBESVGA.DRV",0

width_member	db	"Width",0
height_member	db	"Height",0
depth_member	db	"Depth",0

interval_member	db	"SwapBuffersInterval",0

allow3b_member	db	"Allow3ByteMode",0

font_member	db	"fontsize",0
dpi_auto	db	"auto",0
dpi_nat		db	"nativedpi",0
dpi_tiny	db	"tiny",0
dpi_small	db	"small",0
dpi_large	db	"large",0
sysini_fontstruc	LABEL	BYTE
SYSINI	<dpi_auto,4,0>	; detect fonts.fon size
SYSINI	<dpi_nat,9,-1>	; detect actual screen dpi
SYSINI	<dpi_tiny,4,DPI_TINY>
SYSINI	<dpi_small,5,DPI_SMALL>
SYSINI	<dpi_large,5,DPI_LARGE>

dac_member	db	"dacdepth",0
dac_depth_6	db	"6",0
dac_depth_8	db	"8",0
dac_depth_auto	db	"auto",0
sysini_dacstruc        LABEL   BYTE
SYSINI	<dac_depth_6,1,2>
SYSINI	<dac_depth_8,1,0>
SYSINI	<dac_depth_auto,4,0FFh>

PreferBank_member	db	"PreferBankedModes",0
GarishPalette_member	db	"GarishSystemPalette",0
SpecialBlit_member	db	"EnableSpecialCaseLinearBlits",0

	externW ScreenSelector		; screen selector
        externW ScratchSel              ; the free selector

	externW	sb_period_ms		; in DBLBUF.ASM
	externB	ThreeByte		; in VESAFNS.ASM

sEnd	Data


createSeg _INIT,InitSeg,word,public,CODE
sBegin	InitSeg
assumes cs,InitSeg


	externNP FindMode		;from vesafns.asm
	externNP QueryGeometry		;from vesafns.asm
	externNP vesa_gdi_fixup		;from vesafns.asm
	externNP physical_enable	;Enable routine
	externNP match_dpi		;from vga.asm
	externB  physical_device	;Device physical data
	externB  info_table_base	;GDIInfo table
page
;--------------------------Exported-Routine-----------------------------;
; INT Enable(lpDevice,style,lpDeviceType,lpOutputFile,lpStuff)
; DEVICE lpDevice;		//device block or GDIInfo destination
; INT	 style; 		//Style of initialization
; LPSTR  lpDeviceType;		//Device type (i.e FX80, HP7470, ...)
; LPSTR  lpOutputFile;		//DOS output file name (if applicable)
; LPSTR  lpStuff;		//Device specific information
;
; Enable - Enable Device
;
; The given device is either initialized or the GDI information
; for the given device is returned.
;
; If style=InquireInfo, then GDI is asking that the parameters
; passed be interpreted and the appropriate GDI information
; for the device be returned in lpDevice.
;
; If style=EnableDevice, then GDI is requesting that the device
; be initialized and lpDevice be initialized with whatever
; data is needed by the device.
;
; The three other pointers passed in will be the same for both
; calls, allowing for the device to request only the minimum
; required for a device that is supported.  These will be
; ASCIIZ strings or NULL pointers if no parameter was given.
; These strings are ignored by the display drvier.
;
; For the inquire function, the number of bytes of GDIINFO placed
; into lpDevice is returned.  For the enable function, non-zero is
; returned for success.  In both cases, zero is returned for an error.
;
;
; Warnings:
;	Destroys AX,BX,CX,DX,ES,FLAGS
;-----------------------------------------------------------------------;

	assumes ds,Data
	assumes es,nothing

cProc	Enable,<FAR,PUBLIC,WIN,PASCAL>,<ds,es,si,di>

	parmD	lp_device		;Physical device or GDIinfo destination
	parmW	style			;Style, Enable Device, or Inquire Info
	parmD	lp_device_type		;Device type (i.e FX80, HP7470, ...)
	parmD	lp_output_file		;DOS output file name (if applicable)
	parmD	lp_stuff		;Device specific information

cBegin
ifdef	INT3
	int	3
endif
	WriteAux <'Enable'>

;----------------------------------------------------------------------------;

;	Autores detect

	call	enable_read_profile		;sets up resolution, etc.
	test	ax,ax
	jnz	@F

	; fail immediately (AX == 0)
	jmp	exit_enable

@@:
;----------------------------------------------------------------------------;
; initialize the palette translation table by invoking SetPaletteTranslate   ;
; with a NULL pointer. Do this only if the palette manager is supported      ;
;----------------------------------------------------------------------------;

ifdef	PALETTES
	test	[info_table_base.dpRaster],RC_PALETTE
	jz	@F

	xor	ax,ax
	farPtr  <lpNULL>,ax,ax		; set up a null pointer

	arg	lpNULL
	cCall	SetPaletteTranslate     ; initialize the palette trans. table
@@:
endif

	push	ds
        mov     dx,cs                           ;Set up ds=cs
        mov     ds,dx
        assumes ds,InitSeg

	cld
	les	di,lp_device		;--> device structure or GDIinfo dest.
	assumes es,nothing

	and	style,InquireInfo	;Is this the inquire function?
	jnz	inquire_gdi_info	;  Yes, return GDIinfo
	errnz	InquireInfo-00000001b
	errnz	EnableDevice-00000000b
	errnz	InfoContext-8000h	;Ignore infomation context flag

; Initialize passed device block
; also change the slector in physical_device at this point

;MMSUBS 2/19/91
;	Initialize passed device block

	lea	si,physical_device	;DS:SI --> physical device to copy

	mov	cx,PHYS_DEVICE_SIZE		;Set move count
        rep     movsb
	pop	ds
        assumes ds,Data
;MMENDS

	call	hook_int_2Fh		;Hook into multiplexed interrupt
	call	physical_enable 	;Enable device

	call	start_double_buf	;Start double-buffering timer if needed
	jmp	short exit_enable
page

;	inquire_gdi_info - Inquire Device Specific Information
;
;	The GDI device specific information is returned to the caller
;
;	The information is based on the three pointers passed in.
;	Normally this data would be interpreted and the correct
;	GDINFO returned.  This allows for dynamically returning
;	the info based on the specifics of the device actually
;	being used (i.e. a driver supporting two similar plotters
;	could return the extents of the actual plotter in use).
;
;	These parameters are ignored for display drivers.
;
;	Currently:
;		ES:DI --> where GDIINFO goes
;		DS    =   CS

public	inquire_gdi_info
inquire_gdi_info:
        mov     si,InitSegOFFSET info_table_base

	mov	cx,size GDIINFO
	mov	ax,cx				; return size of GDIInfo
	rep	movsb

	pop	ds
	assumes ds,Data
exit_enable:

cEnd


;	enable_read_profile
;
;	This routine reads the system.ini file and gets the profile string
;	which determines the spatial resolution, color depth, etc. --
;	basically any variable parameters that affect display control as
;	desired by the OEM.
;	This routine may be executed more than one time during Window's
;	operation, because the physical device block may be reloaded.
;	The first time, data read from system.ini is saved.
;	On subsequent calls, this saved data is used, to avoid disk I/O.
;
;   if ( !GetPrivateProfileString( "boot", "display.drv",
;	  NULL, aszCurDrvFName, MAXFNAMELEN, aszSystemIni ) ) {
;	DestroyWindow( hwnd );
;	return( FALSE );
;	};
;
;       PARMS:
;	ds	Data segment

PUBLIC	enable_read_profile
enable_read_profile	PROC	NEAR

	push	bp

	cmp	Profile_read,1
	jne	@F
	jmp	enable_read_profile_done
@@:	mov     Profile_read,1

	lea	ax,boot_category
	lea	bx,PreferBank_member
	lea	cx,aszSystemIni 		;ptr to "system.ini" string
	; default to 0:
        cCall   GetPrivateProfileInt,<ds,ax,ds,bx,0,ds,cx>
	test	ax,ax
	jz	@F
	mov	ax,1				;any non-zero value becomes 1!
@@:	mov	prefer_bank,ax

	lea	ax,boot_category
	lea	ax,GarishPalette_member
	lea	cx,aszSystemIni 		;ptr to "system.ini" string
	; default to 0:
        cCall   GetPrivateProfileInt,<ds,ax,ds,bx,0,ds,cx>
	test	al,al
	jz	@F
	mov	al,1				;any non-zero value becomes 1!
@@:	mov	garish_palette,al

	lea	ax,boot_category
	lea	ax,SpecialBlit_member
	lea	cx,aszSystemIni 		;ptr to "system.ini" string
	; default to 1:
        cCall   GetPrivateProfileInt,<ds,ax,ds,bx,1,ds,cx>
	test	al,al
	jz	@F
	mov	al,1				;any non-zero value becomes 1!
@@:	mov	special_blits,al

	lea	ax,boot_category
        push    ds
        push    ax
	lea	ax,dac_member
        push    ds
        push    ax
	push	ds				;this is the default as well
        push    ax
        lea     ax,aszCurDrvFName
        push    ds
        push    ax
        push    MAXFNAMELEN
	lea	ax,aszSystemIni 		;ptr to "system.ini" string
        push    ds                              ;long ptr
        push    ax
	call	GetPrivateProfileString

	mov	ax,0FFh			       ;default return value
	mov	bx,3				;number different modes
        lea     si,aszCurDrvFName
	lea	bp,sysini_dacstruc
        call    enable_find_substring
	mov	dac_size,al

	lea	ax,boot_category
	lea	bx,width_member
	lea	cx,aszSystemIni 		;ptr to "system.ini" string
        cCall   GetPrivateProfileInt,<ds,ax,ds,bx,-1,ds,cx>
	cmp	ax,320
	jnb	@F
	mov	[fail_reason],offset bad_width
	jmp	enable_read_profile_fail
@@:	mov	VScreen_Width,ax

	lea	ax,boot_category
	lea	bx,height_member
	lea	cx,aszSystemIni 		;ptr to "system.ini" string
        cCall   GetPrivateProfileInt,<ds,ax,ds,bx,-1,ds,cx>
	cmp	ax,200
	jnb	@F
	mov	[fail_reason],offset bad_height
	jmp	enable_read_profile_fail
@@:	mov	VScreen_Height,ax

	lea	ax,boot_category
	lea	bx,depth_member
	lea	cx,aszSystemIni 		;ptr to "system.ini" string
        cCall   GetPrivateProfileInt,<ds,ax,ds,bx,24,ds,cx>
	cmp	al,8
	jnb	@F
	mov	[fail_reason],offset bad_depth
	jmp	enable_read_profile_fail
@@:	mov	VScreen_Depth,al

	lea	ax,boot_category
	lea	bx,interval_member
	lea	cx,aszSystemIni 		;ptr to "system.ini" string
        cCall   GetPrivateProfileInt,<ds,ax,ds,bx,16,ds,cx>
	cmp	ax,55
	jng	@F
	mov	[fail_reason],offset bad_interval
	jmp	enable_read_profile_fail
@@:	mov	[sb_period_ms],ax

	lea	ax,boot_category
	lea	bx,allow3b_member
	lea	cx,aszSystemIni 		;ptr to "system.ini" string
        cCall   GetPrivateProfileInt,<ds,ax,ds,bx,1,ds,cx>
	test	ax,ax
	jz	@F
	mov	al,1
@@:	mov	ThreeByte,al

	; Find the screen geometry and (if needed) preferred resolution
	call	QueryGeometry
	cmp	[VScreen_Width],-1
	jne	@F
	mov	[VScreen_Width],ax
@@:	cmp	[VScreen_Height],-1
	jne	@F
	mov	[VScreen_Height],dx
@@:
	; Linear = AX = 1 iff prefer_bank == 0
	mov	ax,[prefer_bank]
	xor	ax,1
	cCall	FindMode,<ax>
	test	ax,ax
	jz	@F

	dec	ax	; error codes start from 1, not 0!
	mov	bx,ax
	shl	bx,1
	mov	ax,vesa_err_msgs[bx]
	mov	[fail_reason],ax
	jmp	enable_read_profile_fail

@@:	; Vmode should now be set
	lea	ax,boot_category
        push    ds
        push    ax
	lea	ax,font_member
        push    ds
        push    ax
	push	ds				;this is the default as well
        push    ax
        lea     ax,aszCurDrvFName
        push    ds
        push    ax
        push    MAXFNAMELEN
	lea	ax,aszSystemIni 		;ptr to "system.ini" string
        push    ds                              ;long ptr
        push    ax
	call	GetPrivateProfileString

	xor	ax,ax				;default return value = auto
	mov	bx,5				;number different modes
        lea     si,aszCurDrvFName
	lea	bp,sysini_fontstruc
	call	enable_find_substring

	test	ax,ax				;set to auto?
	jnz	@F				; nope, continue
	call	enable_check_sysfontsize	; yep, detect fonts.fon size
@@:	mov     dpi_size,ax

enable_read_profile_done:
	push	es
        cCall   AllocCSToDSAlias, <cs>          ;physical_device is in init seg
        mov     es,ax
	push	ax				;parameter for FreeSelector

        mov     si,InitSegOFFSET info_table_base
        lea     di,physical_device
	mov	ax,windowsVersion
	mov	es:[si].dpVersion,ax
        mov     ax,dpi_size
	mov	es:[si].dpLogPixelsX,ax
        mov     es:[si].dpLogPixelsY,ax

	call	vesa_gdi_fixup			;fixup GDI info table
	; update DPI in case the fixup routine made any change:
        mov     ax,es:[si].dpLogPixelsX
	mov	dpi_size,ax

        xor     bx,bx
        mov     es,bx                   	;invalidate es before freeing
        cCall   FreeSelector
        pop     es

	mov	ax,VScreen_Width
	shr	ax,1
	mov	cursor_xdraw,ax
	dec	ax
	mov	cursor_xcoord,ax
	mov	ax,VScreen_Height
	shr	ax,1
	mov	cursor_ydraw,ax
        dec     ax
	mov	cursor_ycoord,ax

	mov	ax,1
	pop	bp
	ret

enable_read_profile_fail:
	; similar failure strategy to other SVGA drivers I've studied:
	; * Switch to text mode (i.e. get rid of Windows splash screen)
	; * Print the failure reason
	; * Invite the user to press a key
	; * FatalExit, which may not do anything...
	; * Exit to DOS
	mov	ax,3	; text mode
	int	10h
	mov	dx,[fail_reason]
	mov	ah,9	; write string to stdout
	int	21h
	cmp	[VScreen_Depth],0
	jz	@F
	; if the settings are fully loaded, then tell the user a little bit about them:
	call	enable_print_info
@@:	lea	dx,[press_key]
	mov	ah,9	; write string to stdout
	int	21h
	mov	ah,8	; read character from stdin
	int	21h

	; Under WIN386 (i.e. in 386 Enhanced Mode), the DOS prompt's cursor gets
	; reset to the top of the screen after we exit, resulting in a weird
	; comingling of the prompt with our message. Prevent that by clearing
	; the framebuffer, but don't do it under DOSX (Standard Mode), which
	; handles this situation correctly!
	mov	ax,__WinFlags
	test	ax,WF_ENHANCED
	jz	@F

	; clear framebuffer...
	mov	ax,__B800
	mov	es,ax
	xor	di,di
	mov	ax,720h	; grey-on-black spaces
	mov	cx,80*25
	rep	stosw

@@:	cCall	FatalExit,<0>
	; So FatalExit can return, which is not good enough for a possible
	; user-facing failure mode! It seems all we can do is exit directly to
	; DOS! (I know this works because it happened successfully when we were
	; accidentally getting divide-by-zero errors further along; but it still
	; feels pretty evil...)
	mov	ax,4CFFh	; exit with code 255
	int	21h

enable_read_profile	ENDP


;
;       enable_check_sysfontsize
;
;       This routine loads FONTS.FON, checks the DPI of its first (presumably
;	only!) font resource, and chooses the closest DPI we can use.
;
;	PARMS:
;	ds	Data
;
;       RETURNS:
;       ax	DPI value to set for us (DPI_TINY, DPI_SMALL or DPI_LARGE)

fonts_fon	db "FONTS.FON",0
orig_boot_cat	db "BOOT",0
fontdir		db "FONTDIR",0

cProc	enable_check_sysfontsize,<NEAR,PUBLIC,NODATA>,<si,di>
	localW	retval
cBegin
	; ; default to -1, meaning "nativedpi"
	; mov	[retval],-1
	mov	[retval],96

	; find out who FONTS.FON is
	lea	ax,orig_boot_cat
        push    cs
        push    ax
	lea	ax,fonts_fon
        push    cs
        push    ax
	push	cs				;this is the default as well
        push    ax
        lea     ax,aszCurDrvFName
        push    ds
        push    ax
        push    MAXFNAMELEN
	lea	ax,aszSystemIni 		;ptr to "system.ini" string
        push    ds                              ;long ptr
        push    ax
	call	GetPrivateProfileString

	; load it up...
	lea	ax,aszCurDrvFName
	cCall	LoadLibrary,<ds,ax>
	cmp	ax,20h	; HINSTANCE_ERROR
	jnb	@F
	jmp	check_sysfontsize_done

@@:	; find the fontdir
	lea	dx,fontdir
	mov	di,ax	; stash the library handle
	; lpszType is passed as an INT, with the "selector" 0
	cCall	FindResource,<ax,cs,dx,0,RT_FONTDIR>
	test	ax,ax	; NULL?
	jz	check_sysfontsize_freelib

	; load it up
	cCall	LoadResource,<di,ax>
	test	ax,ax	; NULL?
	jz	check_sysfontsize_freelib
	mov	si,ax	; stash the resource handle

	; lock it into memory
	cCall	LockResource,<ax>
	test	dx,dx
	jz	check_sysfontsize_freeres
	mov	es,dx
	mov	bx,ax
	; the ordinal of the first font resource should be at offset 2
	mov	ax,es:[bx+2]
	push	ax

	; free the FONTDIR
	cCall	GlobalUnlock,<si>
	cCall	FreeResource,<si>

	; now load the font itself
	pop	ax	; get back the ordinal
	; lpszName and Type are both passed as INTs, with the "selectors" 0
	cCall	FindResource,<di,0,ax,0,RT_FONT>
	test	ax,ax	; NULL?
	jz	check_sysfontsize_freelib

	; load it up
	cCall	LoadResource,<di,ax>
	test	ax,ax	; NULL?
	jz	check_sysfontsize_freelib
	mov	si,ax	; stash the resource handle

	; lock it into memory
	cCall	LockResource,<ax>
	test	dx,dx
	jz	check_sysfontsize_freeres
	mov	es,dx
	mov	bx,ax

	; the version at offset 0 should be 0200h, meaning a Windows 2.00 font
	cmp	word ptr es:[bx],0200h
	jne	@F	; wrong version, we don't know how to check this!
	; with this version, the X-DPI should be at offset 46h
	mov	ax,es:[bx+46h]
	; match it to one of our internal values
	call	match_dpi
	mov	[retval],ax

@@:	; free the FONT
	cCall	GlobalUnlock,<si>
check_sysfontsize_freeres:
	cCall	FreeResource,<si>
check_sysfontsize_freelib:
	cCall	FreeLibrary,<di>
check_sysfontsize_done:
	mov	ax,[retval]
cEnd


;
;       enable_print_info
;
;       This routine is called just before a fatal exit, and imports WSPRINTF
;	from USER.EXE to quickly print out some troubleshooting info about
;	the way the driver is currently (mis)configured.
;	PARMS:
;	ds	Data
;
;       RETURNS:
;       nothing

user_exe	db "USER.EXE",0
wsprintf_name	db "_WSPRINTF",0
info_format	db "Selected resolution: %u*%u",13,10
		db "Selected bit depth:  %u bits",13,10,0

cProc	enable_print_info,<NEAR,PUBLIC,NODATA>
	localD	wsprintf
	localV	outbuf,400h
cBegin
	; Load USER.EXE so we can use wsprintf function - this has to be
	; done at runtime, as DISPLAY.DRV cannot depend on DLLs other than
	; KERNEL!
	lea	ax,user_exe
	cCall	LoadLibrary,<cs,ax>
	cmp	ax,20h	; HINSTANCE_ERROR
	jnb	@F
	jmp	print_info_done

@@:	; get the wsprintf pointer
	lea	dx,wsprintf_name
	cCall	GetProcAddress,<ax,cs,dx>
	test	dx,dx	; NULL?
	jnz	@F
	jmp	print_info_done

@@:	mov	[wsprintf.off],ax
	mov	[wsprintf.sel],dx

	; format configuration information
	mov	si,sp	; save stack pointer since wsprintf is _cdecl!
	xor	ax,ax
	mov	al,[VScreen_Depth]
	push	ax
	push	[VScreen_Height]
	push	[VScreen_Width]
	lea	ax,info_format
	push	cs
	push	ax
	lea	ax,outbuf
	push	ss
	push	ax
	call	[wsprintf]
	mov	sp,si	; restore stack pointer

	; then print it
	mov	si,ax	; get length of output string
	; replace null terminator with dollar terminator
	mov	byte ptr outbuf[si],'$'
	push	ds
	mov	ax,ss
	mov	ds,ax
	lea	dx,outbuf
	mov	ah,9	; write string to stdout
	int	21h
	pop	ds

	; finish the whole thing off with a newline
	mov	ah,2
	mov	dl,0Dh
	int	21h
	mov	dl,0Ah
	int	21h

print_info_done:
	; don't worry about freeing pointers, we're about to crash the
	; entire system anyway!
cEnd


;
;       enable_find_substring
;
;       This routine finds a substring and returns the value associated
;       with that substring -- see the SYSINI structure for more information.
;       PARMS:
;       ds:si   points to string
;       bx      number of options
;       bp      ptr to XXX structure
;       ax      defualt return value
;
;       RETURNS:
;       ax      value in the SYSINI.retval member if a match is found
;               if no match found, return is same as what was passed in.

PUBLIC  enable_find_substring
enable_find_substring   PROC    NEAR

	push	ds
        pop     es

ef_next_cmp_string:
        push    si
        jmp     short ef_st

ef_more_src_string:
        mov     di,ds:[bp].SYSINI_CMPSTR
        mov     cx,ds:[bp].SYSINI_CMPLEN
        rep     cmpsb
	je	enable_found_substring
        inc     si
ef_st:  cmp     byte ptr [si],0
        jne     ef_more_src_string

	add	bp,SIZE SYSINI
        pop     si
        dec     bx
        jne     ef_next_cmp_string
        ret

enable_found_substring:
        pop     si
        shr     bx,1
        mov     ax,ds:[bp].SYSINI_RETVAL
        ret

enable_find_substring   ENDP


;****************************************************************
;*  cProc   GetDriverResourceID,<FAR,PUBLIC,WIN,PASCAL>,<si,di>
;*
;*  Description: 
;*
;*           DWORD  GetDriverResourceID(iResId, lpResType)
;*
;*           This function will be called by Windows before an
;*           icon, cursor, bitmaps, or OEMBIN resources are
;*           loaded from the display driver. This gives the
;*           display driver an opportunity to map the given
;*           resource id onto another resource id and return
;*           it.
;*
;*           Parameter 
;*                    Type/Description
;*
;*           iResId    
;*                    INT    Id of the requested resource
;*
;*           lpResType          
;*                    LPSTR  Pointer to the
;*                           requested resource type; If the HIWORD
;*                           of this parameter is NULL, then the
;*                           LOWORD contains the resource type id.
;*
;*       Return Value
;*           The return value indicates a resource id
;*           which is the result of the mapping done by this
;*           function.  The HIWORD should be 0?
;*
;*       Comments
;*           This function must be exported by the
;*           driver with an ordinal number of 450.
;*
;*           If the function decides not to do any mapping, it
;*           must return the value passed in through "iResId"
;*           parameter.
;*
;*           The type of the resource returned by this function
;*           is the same as the type of the resource passed in
;*           to this function.  That is, this function should
;*           not attempt to map a resource of one type onto a
;*           resource of another type.
;*
;****************************************************************
cProc   GetDriverResourceID,<FAR,PUBLIC,WIN,PASCAL>
        parmW  iResID
        parmD  lpResType
cBegin
	mov	ax,iResID		;Get res id into ax.

;-----------------------------------------------------------------
; if DPI is > DPI_SMALL (i.e. 96), then do not map
; (use 120 dpi resources).
;-----------------------------------------------------------------
	cmp	dpi_size,DPI_SMALL
	ja	short GDR_Exit

;-----------------------------------------------------------------
; if the ID identifies an icon or cursor then do not map it. 
; Otherwise, map it by adding 2000 to it.
;-----------------------------------------------------------------
	mov	dx,2000
        cmp     ax, OCR_ICOCUR          ;ICOCUR is the "largest" icon/cursor
	jg	short GDR_MapIt		;ID.  If the ID is bigger than this
        cmp	ax,1                    ;it must be a bitmap
	je	short GDR_MapIt
        cmp     ax,3
	je	short GDR_MapIt
	jmp	short @F
GDR_MapIt:
        add     ax,dx                   ;96 dpi resource IDs are +2000
@@:
;-----------------------------------------------------------------
; now check 48dpi - in this case, we DO map cursors, but still
; not icons. Unfortunately, the IDs for icons and cursors overlap,
; so we need to check lpResType...
;-----------------------------------------------------------------
	cmp	dpi_size,DPI_TINY
	ja	short GDR_Exit

	; handle OEMBIN resources first - 2001 (CONFIG.BIN) needs
	; to become 4001, but 2003 (FONTS.BIN) can stay the same:
	cmp	ax,2001
	je	short GDR_MapItAgain
	cmp	ax,OCR_NORMAL		;OCR_NORMAL is first cursor
	jb	short @F		; if lower, no need to map
	; let's assume that RT_GROUP_ICON is ALWAYS passed as 0000:000E
	; (should be valid since developers are only supposed to
	;  use LoadIcon, instead of messing with FindResource.)
	cmp	[lpResType.sel],0
	jnz	short GDR_MapItAgain
        cmp     [lpResType.off],RT_GROUP_ICON
	je	short @F		;if an icon, skip mapping
GDR_MapItAgain:
        add     ax,dx                   ;48 dpi resource IDs are +2000
@@:
GDR_Exit:
	xor	dx,dx		        ;dx must be zero.                
GDR_Exit2:
cEnd GetDriverResourceID

sEnd	InitSeg

end
