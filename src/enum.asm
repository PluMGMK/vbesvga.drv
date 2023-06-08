	page	,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	ENUM.ASM
;
;   This module contains routines which enumerate a subset of the
;   objects which the device can enumerate.
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
;   A subset of the fonts, pens, and brushes which this driver can
;   support are enumerated for the caller, until all objects of the
;   requested type have been enumerated or the caller aborts.
;
; Restrictions:
;
;-----------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.


;

incLogical	= 1			;Include control for gdidefs.inc
incFont 	= 1			;Include control for gdidefs.inc

	.xlist
	include cmacros.inc
	include gdidefs.inc
	include macros.mac
	.list


	??_out	enum

	externA NUM_PALETTES		;# entries in the color table
	externD adPalette
	externB Palette			; in RGB2IPC.ASM
	externA	NbrofColours		; in RGB2IPC.ASM

createSeg _BLUEMOON,BlueMoonSeg,word,public,CODE
sBegin	BlueMoonSeg
assumes cs,BlueMoonSeg

;;;	externD BlueMoonSeg_color_table ;Color table
page
;--------------------------Exported-Routine-----------------------------;
; EnumDeviceFonts
;
;   Enumerate Device Fonts is called to enumerate the fonts available
;   on a given device.	For each appropriate font, the callback function
;   is called with the information for that font.  The callback function
;   is called until there are no more fonts or the callback function
;   returns zero.
;
;   Since this driver has no fonts to enumerate, all that need be done
;   is return a success flag (1).
;
; Entry:
;	None
; Returns:
;	AX = 1
; Error Returns:
;	None
; Registers Preserved:
;	SI,DI,DS,BP
; Registers Destroyed:
;	None
; Calls:
;	None
; History:
;	Wed 12-Aug-1987 19:16:11 -by-  Walt Moore [waltm]
;	Made non-resident
;
;	Tue 17-Feb-1987 21:17:40 -by-  Walt Moore [waltm]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


assumes ds,Data
assumes es,nothing


cProc	EnumDFonts,<FAR,PUBLIC,WIN,PASCAL> ; ,<si,di>

	parmD	lp_device		;Physical device
	parmD	lp_face_name		;Face name
	parmD	lp_callback_func	;Callback function
	parmD	lp_client_data		;Data to pass the callback function

cBegin	<nogen>
	WriteAux <'EnumDFonts'>
	mov	ax,1			;This is a nop for this driver
	ret	16

cEnd	<nogen>
page
;--------------------------Exported-Routine-----------------------------;
; EnumObject
;
;   The given style of object is enumerated through a callback
;   facility.  Since there are only a few objects within this
;   particular driver, they will all be enumerated.
;
;   If the Callback function returns a zero, then the enumeration
;   will be terminated.
;
; Entry:
;	None
; Returns:
;	AX = last value returned from callback function.
;	AX = 1 if nothing was enumerated.
; Error Returns:
;	None
; Registers Preserved:
;	SI,DI,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,FLAGS
; Calls:
;	None
; History:
;	Tue 17-Feb-1987 21:17:40 -by-  Walt Moore [waltm]
;	Created.
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


assumes ds,Data
assumes es,nothing


cProc	EnumObj,<FAR,PUBLIC,WIN,PASCAL>,<si,di,es>

	parmD	lp_device
	parmW	style
	parmD	lp_callback_func
	parmD	lp_client_data

	localW	old_SP
	localV	obj_area,%(size LogBrush)
	errnz	<(SIZE LogBrush)-(SIZE LogPen)-2>	;Want the biggest!

cBegin
	WriteAux <'EnumObj'>
	mov	old_SP,sp		;Save SP for clean-up
	cmp	style,OBJ_PEN		;Pen?
	je	enum_pen		;  Yes
	cmp	style,OBJ_BRUSH 	;Brush?
	je	enum_brush		;  Yes
	mov	ax,1

exit_enum_obj:
	mov	sp,old_SP		;Remove any return addresses from stack

cEnd
page
;--------------------------Private-Routine------------------------------;
; call_client
;
;   The client callback routine is called with the current
;   logical object in obj_area.
;
; Entry:
;	object in obj_area
; Returns:
;	AX = non-zero
; Error Returns:
;	jumps to exit_enum_obj if user aborts enumeration
; Registers Preserved:
;	SI,DI,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,ES,FLAGS
; Calls:
;	[lp_callback_func] - user supplied callback procedure
; History:
;	Tue 17-Feb-1987 21:17:40 -by-  Walt Moore [waltm]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


assumes ds,nothing
assumes es,nothing


call_client	proc	near
	push	es
	lea	ax,obj_area
	farPtr	ptr1,ss,ax
	cCall	lp_callback_func,<ptr1,lp_client_data>
	pop	es
	or	ax,ax
	jz	exit_enum_obj		;Client is bailing out
	ret

call_client	endp
page
;--------------------------Private-Routine------------------------------;
; enum_pen
;
;   The pens which this driver can realize are enumerated for
;   the caller until either all pens have been enumerated or
;   the user aborts.
;
;
;   This driver supports five styles of pens, in the number of
;   colors appropriate for the driver.
;
;   The NULL Pen is not enumerated.
;
; Entry:
;	None
; Returns:
;	AX = non-zero
; Error Returns:
;	jumps to exit_enum_obj if user's aborts enumeration
; Registers Preserved:
;	DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,SI,DI,ES,FLAGS
; Calls:
;	do_color
; History:
;	Tue 17-Feb-1987 21:17:40 -by-  Walt Moore [waltm]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


assumes ds,nothing
assumes es,nothing


enum_pen proc	near
	xor	si,si				;Initialize pen style
	mov	obj_area.lopnWidth.xcoord,si	;Set nominal width
	mov	obj_area.lopnWidth.ycoord,si	;Set width

enum_pen_10:
	mov	obj_area.lopnStyle,si		;Set style

enum_pen_20:
	lea	di,obj_area.lopnColor		;--> pen color
	call	do_color			;Step all 8 colors
	inc	si				;Set next pen style
	cmp	si,LS_NOLINE			;At maximum line style?
	jb	enum_pen_10			;  No, continue

enum_pen_30:
	jmp	exit_enum_obj			;Done enumerating stuff

	errnz	LS_SOLID
	errnz	LS_DASHED-1
	errnz	LS_DOTTED-2
	errnz	LS_DOTDASHED-3
	errnz	LS_DASHDOTDOT-4
	errnz	LS_NOLINE-5			;Not enumerated
	errnz	MaxLineStyle-LS_NOLINE		;Should be no other pens

enum_pen endp
page
;--------------------------Private-Routine------------------------------;
; enum_brush
;
;   The brushes that the driver supports will be enumerated.
;
;   This driver supports 256K worth of ditherd brushes, so only
;   a few of them will enumerated.  These will be based on the
;   five grey scales defined in brush_colors.  All hatched brushes
;   will be enumerated.  The background color for hatched brushes
;   is not enumerated.
;
;   The Hollow Brush will not be enumerated.
;
; Entry:
;	None
; Returns:
;	AX = non-zero
; Error Returns:
;	jumps to exit_enum_obj if user's aborts enumeration
; Registers Preserved:
;	DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,SI,DI,ES,FLAGS
; Calls:
;	do_color
; History:
;	Tue 17-Feb-1987 21:17:40 -by-  Walt Moore [waltm]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


;	The Logical colors that will be returned for the enumeration
;	of the solid brushes


brush_colors label byte

	db	000h			;Black brush color
	db	040h			;DkGrey brush color
	db	080h			;Grey brush color
	db	0C0h			;LtGrey brush color
	db	0FFh			;White brush color

NUMBER_GREYS	=	 $-brush_colors ;Number of greys to enumerate


assumes ds,nothing
assumes es,nothing


enum_brush proc near

	xor	ax,ax
	mov	obj_area.lbStyle,ax		;Set brush style
	errnz	BS_SOLID
	mov	obj_area.lbHatch,ax		;Clear hatch index
	lea	di,obj_area.lbColor

	call	do_color
	jmp	exit_enum_obj

enum_brush endp
page
;--------------------------Private-Routine------------------------------;
; do_color
;
;   The client callback routine is called with the given object
;   with all 8 of the solid colors this driver supports.
;
; Entry:
;	SS:DI --> where to stuff color
; Returns:
;	AX = non-zero
; Error Returns:
;	Handled by call_client
; Registers Preserved:
;	SI,DI,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,ES,FLAGS
; Calls:
;	call_client
; History:
;	Tue 17-Feb-1987 21:17:40 -by-  Walt Moore [waltm]
;	Created.
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


assumes ds,nothing
assumes es,nothing

PUBLIC	do_color
do_color proc   near
	push	si			;Save user's stuff

	lea	si,Palette
	cld
	mov	cx,NbrofColours
	sub	cx,7
	add	si,cx
	shl	cx,1			; (data is in triples)
	add	si,cx			; data:SI --> hi intensity EGA colors
	mov	cx,7			; first get hi intensity 7

; first return the hi-intensity EGA colors.

do_EGAcolor_loop:
	push	ds
	mov	ax,DataBASE
	mov	ds,ax
	lodsw
	mov	wptr ss:[di],ax
	lodsb				; Palette is a set of triples
	xor	ah,ah			; 0 out high byte
	mov	wptr ss:[di][2],ax
	pop	ds			; restore data segment
	push	cx
	call	call_client
	pop	cx
	loop	do_EGAcolor_loop

; now get the rest of the static colors

	lea	si,Palette
	mov	cx,NbrofColours
	sub	cx,7

do_othercolor_loop:
	push	ds
	mov	ax,DataBASE
	mov	ds,ax
	lodsw
	mov	wptr ss:[di],ax
	lodsb				; Palette is a set of triples
	xor	ah,ah			; 0 out high byte
	mov	wptr ss:[di][2],ax
	pop	ds			; restore data segment
	push	cx
	call	call_client
	pop	cx
	loop	do_othercolor_loop
	
if 0
;---------------------------------------------
	mov	si,256			;Set initial color table index
	shiftl	si,2			;Indexing into dwords
do_color_10:
	push	ds			;save call back's data segment
	mov	ax,DataBASE		; get data segment for color table
	mov	ds,ax
	cld
	mov	ax,wptr ds:adPalette[si][-4]
	mov	wptr ss:[di],ax
	mov	ax,wptr ds:adPalette[si][-2]
	mov	wptr ss:[di][2],ax
	pop	ds			;restore data segment
	call	call_client
	sub	si,4			;All colors processed yet?
	cmp	si,(256*4)-(10*4) ; 256-4*8
	jne	do_color_10		;  No

	mov	si,10			;Set initial color table index
	shiftl	si,2			;Indexing into dwords
do_color_20:
	push	ds			;save call back's data segment
	mov	ax,DataBASE		; get data segment for color table
	mov	ds,ax
	cld
	mov	ax,wptr ds:adPalette[si][-4]
	mov	wptr ss:[di],ax
	mov	ax,wptr ds:adPalette[si][-2]
	mov	wptr ss:[di][2],ax
	pop	ds			;restore data segment
	call	call_client
	sub	si,4			;All colors processed yet?
	jne	do_color_20		;  No
;---------------------------------------------
endif	
	
	pop	si
	ret

do_color endp


sEnd	BlueMoonSeg

	ifdef	PUBDEFS
	public	exit_enum_obj
	public	call_client
	public	enum_pen
	public	enum_brush
	public	do_color
;;;;	public	do_color_10
        endif

end

