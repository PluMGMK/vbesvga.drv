        page    ,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	FB.ASM
;
;   This module contains code for the FastBorder function.
;
; Created: 27-May-1987
; Author:  Bob Grudem [bobgru]
;
; Copyright (c) 1984-1987 Microsoft Corporation
;
; Exported Functions:	FastBorder
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
;	This subroutine draws the four edges of a window border.  It
;	clips the border to the clipping rectangle passed in.
;
;	The following is a legend of symbols used in this file:
;
;		corners for input rect: 	(x1,y1), (x2,y2)
;		border thickness horizontally:	bth
;		  (i.e. the width of the left
;		   and right segments of the
;		   border)
;		border thickness vertically:	btv
;		  (i.e. the height of the top
;		   and bottom segments of the
;		   border)
;		corners of clipping region:	(u1,v1), (u2,v2)
;		top left corner of blt:		(destx,desty)
;		width of blt:			xext
;		height of blt:			yext
;
;
;	The shapes of the edges drawn are shown below. If no clipping
;	is necessary, the edges are drawn in the order top, bottom,
;	right, left.  Otherwise, they are drawn in the order top, right,
;	bottom, left.  The latter order is more visually pleasing, but
;	the former order is faster because some blt parameters do not
;	change between successive calls to do_blt.
;
;
	page
;			+-----------------------+---+
;			|			|   |
;			|			|   |
;			+---+-------------------+   |
;			|   |			|   |
;			|   |			|   |
;			|   |			|   |
;			|   |			|   |
;			|   |			|   |
;			|   |			|   |
;			|   |			|   |
;			|   +-------------------+---+
;			|   |			    |
;			|   |			    |
;			+---+-----------------------+
;
;
;
; Restrictions:
;
;	The clipping rectangle (hRaoClip) is a SIMPLEREGION.
;	Rectangle corners have been sorted.
;
;-----------------------------------------------------------------------

;	This function will perform private stack checking.  In order for
;	private stack checking to occur, two symbols must be defined
;	prior to the inclusion of cmacros.inc.  ?CHKSTK must be defined
;	if the cmacros are to perform stack checking on procedures with
;	local parameters.  ?CHKSTKPROC must be defined if private stack
;	checking will be used.
;
;	The actual macro body for ?CHKSTKPROC will be defined later.
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.


?CHKSTK = 1
?CHKSTKPROC	macro
		endm

	.xlist
	include cmacros.inc
	include gdidefs.inc
	include macros.mac
	.list


	externFP BitBlt

sBegin	Data
PUBLIC	fborder_count
fborder_count	dw	0
sEnd    Data

sBegin	Code
assumes cs,Code
assumes ds,nothing
assumes es,nothing
page

;--------------------------Exported-Routine-----------------------------;
; FastBorder
;
;   Draw a border inside a rectangle, clipping to a second rectangle.
;
; Entry:
;	See parameter definitions below.
; Returns:
;	AX = ~0
; Error Returns:
;	AX = 0, if stack overflows allocating local variables
; Registers Preserved:
;	SI,DI,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,FLAGS
; Calls:
;	do_blt
; History:
;	Wed 27-May-1987 16:29:09 -by-  Bob Grudem [bobgru]
;	 Created.
;	Thu 11-Jun-1987 19:49:30 -by-  Bob Grudem [bobgru]
;	 Cleaned up comments.
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


cProc	FastBorder,<FAR,PUBLIC,WIN,PASCAL>,<si,di,ds>

	parmD	lprect			;--> rectangle to frame
	parmW	bth			;border thickness horizontally
	parmW	btv			;border thickness vertically
	parmD	rop			;raster op
	parmD	lpPDevice		;--> physical device structure
	parmD	lpPBrush		;--> physical brush structure
	parmD	lpDrawMode		;--> drawing mode structure
	parmD	lprectclip		;--> clipping rectangle

	localW	x1			;corners of rectangle to frame
	localW	y1
	localW	x2
	localW	y2

	localW	u1			;corners of clipping rectangle
	localW	v1
	localW	u2
	localW	v2

	localW	widepart		;max width of top and bottom edges
	localW	tallpart		;max height of right and left edges

	localW	destx			;destination coordinates and extents
	localW	desty			;of clipped rectangle
	localW	xext
	localW	yext

	localW	oldSP

cBegin
	WriteAux <'fb'>
	jnc	fb_stack_ok
	clc
	jmp	fb_exit_error

fb_stack_ok:
	cld

	assumes ds,Data
	inc	fborder_count		;JAK -- for 216 debugging purposes
	assumes ds,Nothing

;	Get corners of rectangle to frame.

	lds	si,lprect
	assumes ds,nothing

	lodsw
	xchg	ax,dx
	lodsw
	xchg	ax,cx
	lodsw
	xchg	ax,bx
	lodsw

	mov	x1,dx			;left
	mov	y1,cx			;top
	mov	x2,bx			;right
	mov	y2,ax			;bottom

	sub	bx,dx			;compute max width of horiz parts
	sub	bx,bth
	mov	widepart,bx

	sub	ax,cx			;compute max height of vert parts
	sub	ax,btv
	mov	tallpart,ax


;	Get corners of clipping rectangle.

	lds	si,lprectclip
	assumes ds,nothing

	lodsw
	mov	u1,ax			;left
	lodsw
	mov	v1,ax			;top
	lodsw
	mov	u2,ax			;right
	lodsw
	mov	v2,ax			;bottom


;	Check for disjoint destination and clipping rectangles.

	mov	ax,x1
	cmp	ax,u2
	jge	fb_rejected

	mov	ax,y1
	cmp	ax,v2
	jge	fb_rejected

	mov	ax,x2
	cmp	ax,u1
	jle	fb_rejected

	mov	ax,y2
	cmp	ax,v1
	jnle	fb_check_no_clipping

fb_rejected:
	jmp	fb_exit_ok


fb_check_no_clipping:

;	Check for special case in which no clipping is needed.

	mov	ax,u1
	cmp	ax,x1
	jle	fb_chk_clip_1
	jmp	fb_clipping

fb_chk_clip_1:
	mov	ax,v1
	cmp	ax,y1
	jle	fb_chk_clip_2
	jmp	fb_clipping

fb_chk_clip_2:
	mov	ax,u2
	cmp	ax,x2
	jge	fb_chk_clip_3
	jmp	fb_clipping

fb_chk_clip_3:
	mov	ax,v2			;if all comparisons are "<=", then
	cmp	ax,y2			;do special case without clipping
	jge	fb_no_clipping
	jmp	fb_clipping


fb_no_clipping:


	mov	si,bth			;load commonly used values
	mov	di,btv



;	top:
;
;	destx = x1
;	desty = y1
;	xext  = widepart
;	yext  = btv


	or	di,di
	jz	fb_chk_sides

	mov	ax,x1
	mov	destx,ax
	mov	ax,y1
	mov	desty,ax
	mov	ax,widepart
	mov	xext,ax
	mov	yext,di

	call	do_blt


;	bottom:
;
;	destx = x1 + bth
;	desty = y1 + tallpart
;	xext  = widepart
;	yext  = btv

	add	destx,si
	mov	ax,tallpart
	add	desty,ax

	call	do_blt



;	right edge:
;
;	destx = x1 + widepart = x2 - bth
;	desty = y1
;	xext  = bth
;	yext  = tallpart


fb_chk_sides:

	or	si,si
	jz	fb_easy_way_done

	mov	ax,x2
	sub	ax,si
	mov	destx,ax
	mov	ax,y1
	mov	desty,ax
	mov	xext,si
	mov	ax,tallpart
	mov	yext,ax

	call	do_blt


;	left edge:
;
;	destx = x1
;	desty = y1 + btv
;	xext  = bth
;	yext  = tallpart

	mov	ax,x1
	mov	destx,ax
	add	desty,di

	call	do_blt

fb_easy_way_done:
	jmp	fb_exit_ok


;	If we get here then we must do each parameter of each edge of
;	border.  We know that there is at least one blt to do.

fb_clipping:

	mov	si,bth			;load some commonly used values
	mov	di,btv


;	top border:
;
;	if (v1 >= (y1+btv))
;		goto clip_right_border
;	if (u1 >= (x2-bth))
;		goto clip_right_border
;	destx = max(x1, u1)
;	desty = max(y1, v1)
;	tempx = min(u2, (x2-bth))
;	tempy = min((y1+btv), v2)
;	xext  = min(widepart, (tempx-destx))
;	yext  = min(btv, (tempy-desty))

	or	di,di
	jz	fb_clip_right_border

	mov	ax,y1
	mov	cx,ax			;save for future use
	add	ax,di
	cmp	ax,v1
	jle	fb_clip_right_border

	mov	ax,x2
	sub	ax,si
	cmp	ax,u1
	jle	fb_clip_right_border

	mov	ax,x1
	mov	bx,u1
	max_ax	bx
	mov	destx,ax

	mov	ax,cx
	mov	bx,v1
	max_ax	bx
	mov	desty,ax

	mov	ax,x2			;compute tempx - destx
	sub	ax,si
	mov	bx,u2
	min_ax	bx
	sub	ax,destx
	mov	bx,widepart
	min_ax	bx
	mov	xext,ax

	add	cx,di			;compute tempy - desty
	mov	ax,v2
	min_ax	cx
	sub	ax,desty
	min_ax	di
	mov	yext,ax

	call	do_blt


;	right border:
;
;	clip_right_border:
;
;	if (v1 >= (y2-btv))
;		goto clip_bottom_border
;	if (u2 <= (x2-bth))
;		goto clip_bottom_border
;	destx = max((x2-bth), u1)
;	desty = max(y1, v1)
;	tempx = min(x2, u2)
;	tempy = min((y2-btv), v2)
;	xext  = min(bth, (tempx-destx))
;	yext  = min(tallpart, (tempy-desty))

fb_clip_right_border:

	or	si,si
	jz	fb_clip_bottom_border

	mov	ax,y2
	sub	ax,di
	cmp	ax,v1
	jle	fb_clip_bottom_border

	mov	ax,x2
	mov	cx,ax			;save for future use
	sub	ax,si
	cmp	ax,u2
	jge	fb_clip_bottom_border

	mov	ax,cx
	sub	ax,si
	mov	bx,u1
	max_ax	bx
	mov	destx,ax

	mov	ax,y1
	mov	bx,v1
	max_ax	bx
	mov	desty,ax

	mov	ax,u2			;compute tempx - destx
	min_ax	cx
	sub	ax,destx
	min_ax	si
	mov	xext,ax

	mov	ax,y2			;compute tempy - desty
	sub	ax,di
	mov	bx,v2
	min_ax	bx
	sub	ax,desty
	mov	bx,tallpart
	min_ax	bx
	mov	yext,ax

	call	do_blt



;	bottom border:
;
;	clip_bottom_border:
;
;	if (v2 <= (y2-btv))
;		goto clip_left_border
;	if (u2 <= (x1+bth))
;		goto clip_left_border
;	destx = max((x1+bth), u1)
;	desty = max((y2-btv), v1)
;	tempx = min(x2, u2)
;	tempy = min(y2, v2)
;	xext  = min(widepart, (tempx-destx))
;	yext  = min(btv, (tempy-desty))

fb_clip_bottom_border:

	or	di,di
	jz	fb_clip_left_border

	mov	ax,y2
	mov	cx,ax
	sub	ax,di
	cmp	ax,v2
	jge	fb_clip_left_border

	mov	ax,x1
	add	ax,si
	cmp	ax,u2
	jge	fb_clip_left_border

;	mov	ax,x1			;ax already contains x1+bth
;	add	ax,si
	mov	bx,u1
	max_ax	bx
	mov	destx,ax

	mov	ax,cx
	sub	ax,di
	mov	bx,v1
	max_ax	bx
	mov	desty,ax

	mov	ax,x2			;compute tempx - destx
	mov	bx,u2
	min_ax	bx
	sub	ax,destx
	mov	bx,widepart
	min_ax	bx
	mov	xext,ax

	mov	ax,v2			;compute tempy - desty
	min_ax	cx
	sub	ax,desty
	min_ax	di
	mov	yext,ax

	call	do_blt



;	left border:
;
;	clip_left_border:
;
;	if (v2 <= (y1+btv))
;		goto fb_exit_ok
;	if (u1 >= (x1+bth))
;		goto fb_exit_ok
;	destx = max(x1, u1)
;	desty = max((y1+btv), v1)
;	tempx = min(x1+bth, u2)
;	tempy = min(y2, v2)
;	xext  = min(bth, (tempx-destx))
;	yext  = min(tallpart, (tempy-desty))

fb_clip_left_border:

	or	si,si
	jz	fb_exit_ok

	mov	ax,y1
	add	ax,di
	cmp	ax,v2
	jge	fb_exit_ok

	mov	ax,x1
	mov	cx,ax
	add	ax,si
	cmp	ax,u1
	jle	fb_exit_ok

	mov	ax,cx
	mov	bx,u1
	max_ax	bx
	mov	destx,ax

	mov	ax,y1
	add	ax,di
	mov	bx,v1
	max_ax	bx
	mov	desty,ax

	add	cx,si			;compute tempx - destx
	mov	ax,u2
	min_ax	cx
	sub	ax,destx
	min_ax	si
	mov	xext,ax

	mov	ax,y2			;compute tempy - desty
	mov	bx,v2
	min_ax	bx
	sub	ax,desty
	mov	bx,tallpart
	min_ax	bx
	mov	yext,ax

	call	do_blt

fb_exit_ok:
	stc

;	Carry = 0 --> error
;	      = 1 --> success

fb_exit_error:
	sbb	ax,ax

fb_exit:

cEnd
page

;---------------------------Private-Routine-----------------------------;
; do_blt
;
;   Shovel parameters to BitBlt.
;
; Entry:
;	None
; Returns:
;	AX = return value from BitB t
; Registers Preserved:
;	SI,DI,BP
; Registers Destroyed:
;	BX,CX,DX,DS,ES,FLAGS (inside BitBlt)
; Calls:
;	BitBlt
; History:
;	Wed 27-May-1987 16:29:09 -by-  Bob Grudem [bobgru]
;	 Created.
;	Thu 11-Jun-1987 19:49:30 -by-  Bob Grudem [bobgru]
;	 Cleaned up comments.  
;-----------------------------------------------------------------------;

do_blt	proc	near

	mov	oldSP,sp		;I don't know why but we need to do this

	xor	ax,ax			;generic null-parameter

	arg	<lpPDevice,destx,desty,ax,ax,ax,ax,xext,yext,rop,lpPBrush,lpDrawMode>
	cCall	BitBlt

	mov	sp,oldSP

	ret

do_blt	endp


ifdef	PUBDEFS
	public	fb_stack_ok
	public	fb_rejected
	public	fb_check_no_clipping
	public	fb_chk_clip_1
	public	fb_chk_clip_2
	public	fb_chk_clip_3
	public	fb_no_clipping
	public	fb_chk_sides
	public	fb_easy_way_done
	public	fb_clipping
	public	fb_clip_right_border
	public	fb_clip_bottom_border
	public	fb_clip_left_border
	public	fb_exit_ok
	public	fb_exit_error
	public	fb_exit

	public	do_blt
endif

sEnd	Code
end

