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
	externA  PHYS_DEVICE_SIZE	;Size of physical device
	externA  __WinFlags		;Windows info bit
	externFP AllocSelector		; allocate a new selector
	externFP PrestoChangeoSelector	; CS <--> DS conversion
	externFP FreeSelector		; free an allocated selector
	externFP AllocCSToDSAlias
	externFP GetPrivateProfileString
        externFP GetPrivateProfileInt   ; Kernel!GetProfileInt

ifdef PALETTES
	externFP SetPaletteTranslate    ;in color\ega\vga\palette.asm
endif

MAXFNAMELEN	equ	64

OCR_ICOCUR	  =  32647

sBegin  Data

EXTRN	cursor_xcoord:WORD
EXTRN	cursor_ycoord:WORD
EXTRN	cursor_xdraw:WORD
EXTRN	cursor_ydraw:WORD
EXTRN	dac_size:byte
EXTRN	windowsVersion:WORD	;Windows version number

dpi_size	dw	96
Profile_read	dw	0
aszSystemIni	db	"system.ini",0
aszCurDrvFName	db	MAXFNAMELEN DUP(0)
PUBLIC	enable_216
enable_216      dw      0

SYSINI	STRUC
    SYSINI_CMPSTR	DW	0
    SYSINI_CMPLEN	DW	0
    SYSINI_RETVAL	DW	0
SYSINI	ENDS

boot_category   db      "VBESVGA.DRV",0

chk_member	db	"PMIDcheck",0
chk_disable	db	"disable",0	; allow disabling it if it crashes
chk_none	db	"none",0
chk_sum		db	"sum",0
chk_sanity	db	"sanity",0
sysini_chkstruc	LABEL	BYTE
SYSINI	<chk_disable,7,-1>
SYSINI	<chk_none,4,0>
SYSINI	<chk_sum,3,1>
SYSINI	<chk_sanity,6,2>

edid_member	db	"UseEDID",0
width_member	db	"Width",0
height_member	db	"Height",0
depth_member	db	"Depth",0

font_member	db	"fontsize",0
dpi_96		db	"small",0
dpi_120 	db	"large",0
sysini_fontstruc	LABEL	BYTE
SYSINI	<dpi_96,5,96>
SYSINI	<dpi_120,5,120>

dac_member	db	"dacdepth",0
dac_depth_6	db	"6",0
dac_depth_8	db	"8",0
sysini_dacstruc        LABEL   BYTE
SYSINI	<dac_depth_6,1,2>
SYSINI	<dac_depth_8,1,0>

Enable216_member	db	"Enable216_features",0
Enable216_on		db	"1",0
Enable216_off		db	"0",0
sysini_216struc        LABEL   BYTE
SYSINI	<Enable216_on,1,1>
SYSINI	<Enable216_off,1,0>

mode_number	LABEL	BYTE
DB	67H, 68H, 69H, 6AH

mode_screen_width       LABEL   WORD
DW	640, 720, 800, 1024

mode_screen_height	LABEL	WORD
DW	480, 512, 600, 768

	externW ScreenSelector		; screen selector
        externW ScratchSel              ; the free selector
        externW ssb_mask                ;Mask for save save screen bitmap bit

sEnd	Data


sBegin	Code
        externB ??BigFontFlags
sEnd    Code


	externA __NEXTSEG		;WINDOWS runtime segment selector

createSeg _INIT,InitSeg,word,public,CODE
sBegin	InitSeg
assumes cs,InitSeg


	externNP FindMode		;from vesafns.asm
	externNP SetupPMInt		;from vesafns.asm
	externNP vesa_gdi_fixup		;from vesafns.asm
	externNP physical_enable	;Enable routine
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
	mov	bx,ssb_mask
	and	es:[di].dpRaster[-size GDIINFO],bx

	push	ax
	mov	ax,__WinFlags			; setup for 3.0 fonts
        test    ax,WF_PMODE                     ; protected mode?
        jz      @F
        test    ax,WF_CPU386+WF_CPU486          ; 386/486 protected mode?
        jz      @F
	or	wptr es:[di].dpRaster[-size GDIINFO],RC_BIGFONT ; set the big fonts bit
;
; change our code segment based variable to reflect the mode
;
	push	es
;
	xor	ax,ax
	push	ax
	cCall	AllocSelector		; get a free selector
	mov	bx,_TEXT
	cCall	PrestoChangeoSelector,<bx,ax>
	mov	es,ax
	assumes es,Code
	mov	byte ptr es:[??BigFontFlags],-1

	push	es
	cCall	FreeSelector
;
        pop     es
	assumes es,nothing
;
@@:
	pop	ax
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
        push    ds
        push    ax
	lea	ax,chk_member
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

	mov	ax,1				;default return value = checksum
	mov	bx,4				;number different modes
        lea     si,aszCurDrvFName
	lea	bp,sysini_chkstruc
	call	enable_find_substring
	call	SetupPMInt

	; TODO: Use EDID settings as default
	lea	ax,boot_category
	lea	bx,width_member
	lea	cx,aszSystemIni 		;ptr to "system.ini" string
        cCall   GetPrivateProfileInt,<ds,ax,ds,bx,1024,ds,cx>
	cmp	ax,640
	jnb	@F
ifdef	INT3
	int	3
endif
	WriteAux <'Width < 640 is not allowed'>
	jmp	enable_read_profile_fail
@@:	mov	VScreen_Width,ax

	lea	ax,boot_category
	lea	bx,height_member
	lea	cx,aszSystemIni 		;ptr to "system.ini" string
        cCall   GetPrivateProfileInt,<ds,ax,ds,bx,768,ds,cx>
	cmp	ax,480
	jnb	@F
ifdef	INT3
	int	3
endif
	WriteAux <'Height < 480 is not allowed'>
	jmp	enable_read_profile_fail
@@:	mov	VScreen_Height,ax

	lea	ax,boot_category
	lea	bx,depth_member
	lea	cx,aszSystemIni 		;ptr to "system.ini" string
        cCall   GetPrivateProfileInt,<ds,ax,ds,bx,24,ds,cx>
	cmp	al,8
	jnb	@F
ifdef	INT3
	int	3
endif
	WriteAux <'Depth < 8 is not allowed'>
	jmp	enable_read_profile_fail
@@:	mov	VScreen_Depth,al

	; Linear=0 for now
	; TODO: bring it in if we detect 32-bit DPMI
	cCall	FindMode,<0>
	test	ax,ax
	jz	@F
	jmp	enable_read_profile_fail
	; Vmode should now be set

@@:	lea	ax,boot_category
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

	mov	ax,96				;default return value
	mov	bx,2				;number different modes
        lea     si,aszCurDrvFName
	lea	bp,sysini_fontstruc
	call	enable_find_substring
        mov     dpi_size,ax

@@:	lea	ax,boot_category
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

	mov	ax,2			       ;default return value
	mov	bx,2				;number different modes
        lea     si,aszCurDrvFName
	lea	bp,sysini_dacstruc
        call    enable_find_substring
	mov	dac_size,al

@@:	lea	ax,boot_category
        push    ds
        push    ax
	lea	ax,Enable216_member
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

	mov	ax,0			       ;default return value
	mov	bx,2				;number different modes
        lea     si,aszCurDrvFName
	lea	bp,sysini_216struc
        call    enable_find_substring
	mov	enable_216,ax

enable_read_profile_done:
	push	es
        cCall   AllocCSToDSAlias, <cs>          ;physical_device is in code seg
        mov     es,ax
	push	ax				; parameter for FreeSelector

        mov     si,InitSegOFFSET info_table_base
        lea     di,physical_device
	mov	ax,windowsVersion 	;fixup GDI info table
	mov	es:[si].dpVersion,ax
        mov     ax,dpi_size
	mov	es:[si].dpLogPixelsX,ax
        mov     es:[si].dpLogPixelsY,ax

	call	vesa_gdi_fixup		;fixup GDI info table

        xor     bx,bx
        mov     es,bx                   ;invalidate es before freeing
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
@@:
	pop	bp
	ret

enable_read_profile_fail:
ifdef	INT3
	int	3
endif
	WriteAux <'Unsuitable settings for current driver / hardware'>
	xor	ax,ax
	jmp	@B

enable_read_profile	ENDP


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


COMMENT ~

;
;	enable_findmode
;
;	This routine returns the mode number in string pointed to by ds:si.
;	Only mode numbers between 66H and 6AH inclusive are recognized (these
;	are the 256 color modes.) The number returned is the mode number
;	found. If no mode number exists, then 0 is returned.
;	PARMS:
;	ds:si	points	 to string
;
;       RETURNS:
;	cx	Video 7 mode number
;	bx	Index 0=67, 1=68, 2=69, 3=6A

PUBLIC	enable_findmode
enable_findmode 	PROC	NEAR

	mov	ax,ds
	mov	es,ax
	mov	bx,6			;this will be the mode # index * 2

ef_next_cmp_string:
        push    si
	jmp	short ef_st

ef_more_src_string:
        mov     di,moderes_string[bx]
        mov     cx,moderes_length[bx]
	rep	cmpsb
	je	enable_foundmode
	inc	si
ef_st:	cmp	byte ptr [si],0
	jne	ef_more_src_string

	pop	si
	sub	bx,2
	jne	ef_next_cmp_string
	push	si			;to counteract next instruction

enable_foundmode:
	pop	si
	shr	bx,1
	mov	cx,bx
	add	cx,67H
	ret

enable_findmode 	ENDP


;
;	enable_finddpi
;
;	This routine returns the desired dpi as an integer in ax. 96 will be
;	returned if there is no size indicated in the profile string.
;	PARMS:
;	ds:si	points	 to string
;
;       RETURNS:
;	ax	Video 7 mode number

PUBLIC	enable_finddpi
enable_finddpi		PROC	NEAR

	mov	ax,ds
	mov	es,ax
	mov	bx,2			;this will be the mode # index * 2

efd_next_cmp_string:
        push    si
	jmp	short efd_st

efd_more_src_string:
	mov	di,dpires_string[bx]
	mov	cx,dpires_length[bx]
	rep	cmpsb
	je	enable_founddpi
	inc	si
efd_st: cmp	byte ptr [si],0
	jne	efd_more_src_string

	pop	si
	sub	bx,2
	jne	efd_next_cmp_string
	push	si			;to counteract next instruction

enable_founddpi:
	pop	si
	mov	ax,dpires_number[bx]
	ret

enable_finddpi		ENDP

~	;end COMMENT


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
; if f96DPI is not set to MULTIRES_96DPI then do not map
; (use 120 dpi resources).
;-----------------------------------------------------------------
;	 cmp	 byte ptr f96DPI, MULTIRES_96DPI
;	 jne	 short GDR_Exit

	cmp	dpi_size,96
	jne	short GDR_Exit

;-----------------------------------------------------------------
; if the ID identifies an icon or cursor then do not map it. 
; Otherwise, map it by subtracting 2000 from it.  If the ID
; is a 1 or 3, add 2000 to it.
;-----------------------------------------------------------------
	mov	dx,2000
        cmp     ax, OCR_ICOCUR          ;ICOCUR is the "largest" icon/cursor
	jg	short GDR_MapIt		;ID.  If the ID is bigger than this
        cmp	ax,1                    ;it must be a bitmap
	je	short @f
        cmp     ax,3
	je	short @f
	jmp	short GDR_Exit
@@:
;	neg	dx
GDR_MapIt:
        add     ax,dx                   ;96 dpi resource IDs are +2000
GDR_Exit:
	xor	dx,dx		        ;dx must be zero.                
GDR_Exit2:
cEnd GetDriverResourceID

sEnd	InitSeg

end
