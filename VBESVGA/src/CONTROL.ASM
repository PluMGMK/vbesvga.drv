	page	,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	CONTROL.ASM
;
; This module contains the escape handler for the color display
; drivers.
;
; It also contains stubs for the SetAttribute function and the
; DeviceBitmap function, both of which this driver does not
; support.
;
; Created: 16-Feb-1987
; Author:  Walt Moore [waltm]
;
; Copyright (c) 1983-1987 Microsoft Corporation
;
; Exported Functions:	Control
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
;   Control is the routine which is called when an Escape call
;   is made to GDI.  This driver only implements two of the
;   escape functions.  These functions set and get the color
;   table.  Since the color table is not setable for the display,
;   the current value is just returned.
;
;   Support for QUERYESCSUPPORT has now been added.  This escape
;   function is required of all drivers.  It informs the caller
;   which escape functions are supported (QUERYESCSUPPORT will
;   return TRUE for QUERYESCSUPPORT!).
;
; Restrictions:
;
;-----------------------------------------------------------------------;

incControl	=	1		;Include control for gdidefs.inc
incDevice	=	1		;Include control for gdidefs.inc
	.xlist
	include cmacros.inc
	include gdidefs.inc
	include dci.inc
	include display.inc
	include macros.mac
	.list

sBegin	Data
	EXTRN	adPalette:BYTE
	EXTRN	MemWidth:WORD		;in VESAFNS.ASM
	EXTRN	ColourFormat:WORD	;in VGA.ASM
	EXTRN	raster_flags:WORD
	EXTRN	LinBufSel:WORD		;in DBLBUF.ASM
sEnd    Data

	externFP GlobalAlloc
	externFP GlobalLock
	externFP GlobalUnlock
	externFP GlobalFree

	externFP sum_RGB_alt_far	;in ROBJECT.ASM
	externFP exclude_rect		;in CURSOR.ASM
	externFP unexclude_rect		;in CURSOR.ASM

	??_out	Control

createSeg _BLUEMOON,BlueMoonSeg,word,public,CODE
sBegin	BlueMoonSeg
assumes cs,BlueMoonSeg

page
;--------------------------Exported-Routine-----------------------------;
; Control
;
;   Control is defined so that device specific commands can be issued
;   that are not supported by GDI.  Some of the Control functions have
;   been defined by GDI so that devices that can perform them (and need
;   to) can do so, such as clear device.
;
;   Clear device will not be allowed.  Nobody should do that to the
;   system console!
;
;   Set/Get color table will not be implented for windows 3.0.
;
; Entry:
;	None
; Returns:
;	AX = 1 if success
; Error Returns:
;	AX = 0 if error
; Registers Preserved:
;	SI,DI,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,FLAGS
; Calls:
;	None
; History:
;	Sat 22-April-1989 -by- David Miller [o-davem]
;	Removed color table support for Windows 3.0
;
;	Sun 27-Sep-1987 21:35:42 -by-  Walt Moore [waltm]
;	Added QUERYESCSUPPORT, which is the one required
;	escape function all drivers must support.
;
;	When queried if we support SETCOLORTABLE, we'll
;	return false.  The code will continue to return
;	current color table index if we get the SETCOLORTABLE
;	call.
;
;	Wed 12-Aug-1987 17:29:30 -by-  Walt Moore [waltm]
;	made non-resident
;
;	Wed 18-Mar-1987 14:04:30 -by-  Walt Moore [waltm]
;	Added COLOR_TBL_SIZE so the code can be shared
;	between black/white and color drivers.
;
;	Mon 16-Feb-1987 18:09:09 -by-  Walt Moore [waltm]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


COLOR_TBL_SIZE	equ	100H


assumes ds,Data
assumes es,nothing


cProc   Control,<FAR,PUBLIC,WIN,PASCAL>,<si,di,ds>

	parmD	lp_device
	parmW	function
	parmD	lp_in_data
	parmD	lp_out_data

cBegin
WriteAux <'Ctrl'>
	xor	ax,ax			;Assume error
	mov	si,function

        les     bx,lp_in_data           ;Get pointer to the data

	cmp	si,DCICOMMAND
	je	dci_command

	cmp	si,GETCOLORTABLE
	je	get_color_table

        cmp     si,QUERYESCSUPPORT
	jne	exit_control		;Is not set, get, query

        mov     si,wptr es:[bx]         ;Get queried escape function number
	cmp	si,QUERYESCSUPPORT
	je	exit_control_inc_ax
        cmp     si,GETCOLORTABLE
	je	exit_control_inc_ax
        cmp     si,DCICOMMAND
	je	exit_control_inc_ax

        jmp     short exit_control      ;We don't support it

dci_command:
	mov	ax,DCI_FAIL_UNSUPPORTED	;assume failure until we know otherwise
	cwd
	cmp	es:[bx.dwVersion.lo],100h
	jne	exit_control
	cmp	es:[bx.dwVersion.hi],0
	jne	exit_control
	cmp	es:[bx.dwCommand.lo],DCICREATEPRIMARYSURFACE
	jne	exit_control		;minimal implementation

	; break it out into a separate function to avoid cluttering this
	; too much...
	les	bx,lp_out_data
	call	DCICreatePrimarySurface
	jmp	short exit_control

get_color_table:
        mov     si, es:[bx]             ;color table index
        cmp     si, 255
        ja      exit_control
                                        ; *4 (size RGBQUAD)
        shl     si, 2
        add     si, DataOFFSET adPalette; DS:SI --> RGBQUAD
        les     di, lp_out_data

	cld
        movsw                           ; Copy Red + Green
        movsb                           ; Copy Blue
        stosb                           ; Set reserved to zero

        errn$   exit_control_inc_ax     ; all done

exit_control_inc_ax:
	inc	ax			;Return 1 to show OK

exit_control:

cEnd

cProc DeviceBitmap,<FAR,PUBLIC,WIN,PASCAL> ; ,<si,di>

      parmD lpDevice
      parmW command
      parmD lpBitmap
      parmD lpBits

cBegin	<nogen>
WriteAux <'Ctrl:devbitmap'>
	xor	ax,ax
	ret	14

cEnd	<nogen>


cProc SetAttribute,<FAR,PUBLIC,WIN,PASCAL> ; ,<si,di>

      parmD  lpDevice
      parmW  stateNum
      parmW  index
      parmD  attribute

cBegin	<nogen>
WriteAux <'Ctrl:SetAttr'>
	xor	ax,ax
	ret	12

cEnd	<nogen>



; DCICreatePrimarySurface()
;
; Parameters:     ES:BX
;                     FAR pointer at which to place pointer to output structure
;
; Description:    Function to acquire on-screen display surface in the current 
;                 video mode. 
;
; Returns:        DCI_OK on success, or an error code on failure.
;
; Side Effects:   Allocates space for a DCISURFACEINFO + all instance data and 
;                 returns the structure off at ES:BX.  All fields of 
;                 DCISURFACEINFO structure set to on screen "Primary" surface
DCICreatePrimarySurface	proc near
	mov	dx,[LinBufSel]
	test	dx,dx
	jnz	@F

	; no direct linear framebuffer access --> no DCI
	mov	ax,DCI_FAIL_UNSUPPORTED
	cwd
	ret

@@:	push	bx
	push	dx	; save segment of linear framebuffer
	push	es
	mov	ax,size DCISURFACEINFO
	; 42h == GHND, 2000h == GMEM_SHARE
	cCall	GlobalAlloc,<2042h, 0, ax>
	test	ax,ax
	jnz	@F

	pop	es
	pop	dx
	pop	bx
	mov	ax,DCI_ERR_OUTOFMEMORY
	cwd
	ret

@@:	push	ax	; save handle
	cCall	GlobalLock,<ax>
	pop	cx	; becomes our handle
	pop	es
	pop	di	; becomes segment of linear framebuffer
	pop	bx
	; return our new pointer to the place it was requested
	mov	es:[bx.off],ax
	mov	es:[bx.sel],dx
	; and now look at it ourselves
	mov	es,dx
	mov	bx,ax
	; use "reserved for provider" field to store our handle
	mov	es:[bx.dwReserved1.lo],cx

	; fill out all the surface info
	; at this point, BP:SI:DI is the linear framebuffer ptr
	mov	es:[bx.dwSize.lo],size DCISURFACEINFO
	mov	es:[bx.dwSIDCICaps.lo],DCI_PRIMARY+DCI_VISIBLE

	; dwCompression and dwMask depend on whether or not we're using a palette
	test	[raster_flags],RC_PALETTE
	; "RGB" can also mean using a palette, apparently...
	mov	es:[bx.dwSICompression.lo],BI_RGB
	jnz	@F
	; OK, not using a palette, so specify the bitfields explicitly
	mov	es:[bx.dwSICompression.lo],BI_BITFIELDS
	; mask for RED:
	mov	ax,00FFh
	cwd
	call	sum_RGB_alt_far
	mov	es:[bx.dwSIMask.lo][0*4],ax
	mov	es:[bx.dwSIMask.hi][0*4],dx
	; mask for GREEN:
	mov	ax,0FF00h
	xor	dx,dx
	call	sum_RGB_alt_far
	mov	es:[bx.dwSIMask.lo][1*4],ax
	mov	es:[bx.dwSIMask.hi][1*4],dx
	; mask for BLUE:
	xor	ax,ax
	mov	dx,00FFh
	call	sum_RGB_alt_far
	mov	es:[bx.dwSIMask.lo][2*4],ax
	mov	es:[bx.dwSIMask.hi][2*4],dx

@@:	mov	ax,[VScreen_Width]
	mov	dx,[VScreen_Height]
	mov	cx,[MemWidth]
	mov	es:[bx.dwSIWidth.lo],ax
	mov	es:[bx.dwSIHeight.lo],dx
	mov	es:[bx.lStride.lo],cx
	mov	ax,[ColourFormat]
	mov	byte ptr es:[bx.dwSIBitCount],ah
	; ALWAYS set offset to zero because some DCI Clients ignore it anyway
	; and assume it's zero (lookin' at you, Ecco the Dolphin...)
	xor	ax,ax
	mov	es:[bx.dwOffSurface.lo],ax
	mov	es:[bx.dwOffSurface.hi],ax
	mov	es:[bx.wSelSurface],di

	; lastly, the callbacks - these two are in CURSOR.ASM...
	mov	es:[bx.BeginAccess.off],offset exclude_rect
	mov	es:[bx.BeginAccess.sel],seg exclude_rect
	mov	es:[bx.EndAccess.off],offset unexclude_rect
	mov	es:[bx.EndAccess.sel],seg unexclude_rect
	; ... and this one is straight below!
	mov	es:[bx.DestroySurface.off],offset DCIDestroySurface
	mov	es:[bx.DestroySurface.sel],seg DCIDestroySurface

	; success!
	mov	ax,DCI_OK
	cwd
	ret
DCICreatePrimarySurface	endp

cProc   DCIDestroySurface,<FAR,PUBLIC,PASCAL,NODATA>,<ds,si>
	parmD	lpSurfaceInfo
cBegin
	assumes	ds,nothing
	lds	si,[lpSurfaceInfo]
	mov	ax,ds
	; don't free NULL pointer
	test	ax,ax
	jz	@F

	mov	si,[si.dwReserved1.lo]
	cCall	GlobalUnlock,<si>
	cCall	GlobalFree,<si>
@@:
cEnd




sEnd	BlueMoonSeg

	ifdef	PUBDEFS
	public	exit_control
        endif

end
