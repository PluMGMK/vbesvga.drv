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
	.xlist
	include cmacros.inc
	include gdidefs.inc
	include macros.mac
	.list

sBegin	Data
	EXTRN	adPalette:BYTE
sEnd    Data

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
	assumes ds,nothing
	mov	si,function

        les     bx,lp_in_data           ;Get pointer to the data

	cmp	si,GETCOLORTABLE
	je	get_color_table

        cmp     si,QUERYESCSUPPORT
	jne	exit_control		;Is not set, get, query

        mov     si,wptr es:[bx]         ;Get queried escape function number
	cmp	si,QUERYESCSUPPORT
	je	exit_control_inc_ax
        cmp     si,GETCOLORTABLE
	je	exit_control_inc_ax

        jmp     short exit_control      ;We don't support it

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




sEnd	BlueMoonSeg

	ifdef	PUBDEFS
	public	exit_control
        endif

end
