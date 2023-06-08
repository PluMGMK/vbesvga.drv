;------------------------------------------------------------------------------;
;		            CLIP_LINE					       ;
;			    ---------					       ;
;  	       Clips a line segment to a rectangle                             ;
; INPUTS:								       ;
;	       (BX,CX) and (DI,SI)   ------  unclipped end points of the line  ;
;              [X1,X2]               ------  X clipping interval               ;
;              [Y1,Y2]               ------  Y clipping interval               ;
;									       ;
;              The rectangle is inclusive on lower left and exclusive          ;
;              on the upper right.					       ;
;									       ;
; The routine clips and transforms the line as is required by Breshenham's     ;
; algorithm. The transformation steps and the clipped end points are calculated;
;									       ;
;------------------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.

Clip_Line	proc	near

	cmp	bx,di			; ensure line goes from left to right
	jle	cl_is_left_to_right	; is in correct direction
	xchg	bx,di
	xchg	cx,si			; swap the end points
	or	XformFlags,LEFT_XCHG	; record the transformation
cl_is_left_to_right:
	mov	StartX,bx
	mov	StartY,cx		; save the start points

; load Y clipping, normalize coordinates relative to first end point (BX,CX)

	mov	ax,Y1			
	mov	dx,Y2			; (AX,DX) is the y clip range
	sub	ax,cx
	sub	dx,cx			; translate 
	sub	si,cx			; normalize the other end point
	jge	cl_line_above_X		; line is above X axis
	neg	si			; reflect about X axis
	neg	ax			
	neg	dx			; reflect the rectangle also
	inc	ax
	inc	dx			; retain inclusive/exclusive property
	xchg	ax,dx			; [AX,DX) is the Y clip region
	or	XformFlags,Y_FLIP+VERTICAL_FLIP
cl_line_above_X:

; load X clipping, normalize coordinates relative to first end point (BX,CX)

	neg	bx
	add	di,bx
	mov	cx,X2			; the right X boundary
	add	cx,bx
	add	bx,X1			; [BX,CX) the X clip range

; make the line X major

	cmp	si,di
	jbe	cl_we_are_X_major	; it is a X major line
	xchg	si,di			; swap end points
	xchg	ax,bx
	xchg	cx,dx			; swap the X clip boundaries
	or	XformFlags,XY_XCHG	; record the transformation
cl_we_are_X_major:

; adjust the X clip for overflow

	cmp	cx,bx			; if not well ordered,the lower was neg
	jae	x_well_ordered
	xor	bx,bx			; round up left margin to zero
x_well_ordered:

; clip against the right X margin

	cmp	cx,di			; test end point against right margin
	jbe	clip_to_rt		; clip to right margin
	lea	cx,[di][1]		; set rt margin to just exclude end
clip_to_rt:
	cmp	cx,bx			; test clipped rt against lt margin
	ja	x_interval_ok		; there is a nonzero X interval
draw_no_pels:
	mov	Xa,1
	mov	Xb,0			; Xa<Xb => totaly clipped line
	jmp	clip_line_done

x_interval_ok:
	dec	cx			; exclude last pel
	mov	Xa,bx
	mov	Xb,cx			; [Xa,Xb) is the first choice interval


;------------------------------------------------------------------------------;
; precompute  BX = ceil((dx - 2dy.f0) / 2)				       ;
;------------------------------------------------------------------------------;

	mov	bx,di			; has dx
	cmp	byte ptr XformFlags[1],1 
	.errnz	(VERTICAL_FLIP - 100h)
	cmc				; carry now set for flipped line
	adc	bx,0			; dx - 2dy.f0
	shr	bx,1			; divide by 2
	adc	bx,0			; take the ceiling

; clip the line against the bottom of the rectangle

	mov	cx,dx			; save top in cx
	cmp	cx,ax			; wrap => overflow => no bottom clip
	jb	bottom_y_clipped
	or	ax,ax			
	jz	bottom_y_clipped	; bottom is below our line
	cmp	ax,si			; test end point against the bottom
	ja	draw_no_pels		; line is below rectangle
	or	si,si
	jz	bottom_y_clipped	; horizontal line

;------------------------------------------------------------------------------;
; we now know that the line intersects the bottom of the rectangle. The point  ;
; of intersection is at:						       ;
; 									       ;
;   Xa = floor( (2dx.y - dx + 2dy.f0) / 2dy) + 1			       ;
;      = floor( (dx.y - ceil((dx - 2dy.f0) /2)) / dy) + 1		       ;
;------------------------------------------------------------------------------;

	mul	di			; ax had y
	sub	ax,bx			; bx was precomputed
	sbb	dx,0			
	div	si			; divide by dy
	inc	ax

; use the above Xa as the lower X limit if it is more restrictive

	cmp	ax,Xa			; compare with the left margin
	jb	bottom_y_clipped	; we are ok
	mov	Xa,ax			; the new limit is more restrictive
bottom_y_clipped:

; perform obvious top clipping

	cmp	cx,si
	ja	clip_line_done		; top is above our line
	jcxz	draw_no_pels		; horizontal gets totally clipped now

;------------------------------------------------------------------------------;
; use the precomputed value of BX to calculate the intersection with the top   ;
;									       ;
; Xb = floor((dx.y - ceil((dx - 2dy.f0) / 2)) / dy)			       ;
;------------------------------------------------------------------------------;

	mov	ax,cx			; ax gets y, the top margin
	mul	di			; * dx
	sub	ax,bx			; bx was precomputed
	sbb	dx,0
	div	si			; divide by dy

; use the value of AX as the upper limit if it is more restrictive

	cmp	ax,Xb			; Xb had the original upper limit
	ja	clip_line_done		; the original is more restictive
	mov	Xb,ax			; save the more restrictive limit

clip_line_done:
	ret

Clip_Line	endp
