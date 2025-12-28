;
;	FILE:	cursor.asm
;	DATE:	1/9/91
;	AUTHOR: Jim Keller
;
;	This module is the cursor windows-cursor display driver interface.
;	It controls two other modules: hwcurs.asm and swcurs.asm the
;	hardware and software cursor modules. A hardware cursor is always
;	preferable, but depending upon the mode, resolution, board, etc.
;	sometimes only a software cursor can be displayed. Which cursor
;	type (HW or SW) to use is also dependent upon the cursor data, and
;	hence the decision is made every time SetCursor is called.

.286
FILE_CURSOR	EQU	1

ifdef	DEBUGAUX
PUBDEFS	equ	1
endif

include cmacros.inc
include macros.mac
include windefs.inc
include gdidefs.inc
include vgareg.inc
include display.inc
include swcurs.inc
include cursor.inc


curs_func	STRUC
	CURSFUNC_SET		DW	0
        CURSFUNC_MOVE           DW      0
	CURSFUNC_CHECK		DW	0
	CURSFUNC_OFF		DW	0
	CURSFUNC_EXCLUDE	DW	0
	CURSFUNC_UNEXCLUDE	DW	0
curs_func	ENDS

sBegin	Data

EXTRN	enabled_flag:WORD

PUBLIC  exclude_rect_left, exclude_rect_right
PUBLIC	exclude_rect_top, exclude_rect_bottom, exclude_global
PUBLIC	exclude_rect_valid, cursor_flags, cursor_funcs
PUBLIC	cursor_xcoord, cursor_ycoord
PUBLIC	cursor_xdraw, cursor_ydraw
PUBLIC  screen_busy

screen_busy		DB	1,0
cursor_xcoord		DW	0
cursor_ycoord		DW	0
cursor_xdraw		DW	0
cursor_ydraw		DW	0
cursor_flags		DW	0
exclude_global		DW	0
exclude_rect_valid      DW      0
exclude_rect_left	DW	0
exclude_rect_right	DW	0
exclude_rect_top	DW	0
exclude_rect_bottom	DW	0
cursor_data		LABEL	WORD
cursor_hdr		DB	(SIZE cursorShape) DUP(?)
; the AND mask is always one bit per pixel, packed
cursor_andmask		DB	(CURSOR_HEIGHT * CURSOR_WBYTEMNO) DUP (?)
; the XOR mask can be colour, so allocate up to four BYTES per pixel
cursor_xormask		DB	(CURSOR_HEIGHT * CURSOR_WBYTECLR) DUP (?)
cursor_state_lock	DW	0
saved_bank_select	DB	0
cursor_funcs	DW	swcursor_set, swcursor_move, swcursor_check
		DW	swcursor_off, swcursor_exclude, swcursor_unexclude

sEnd    Data


createSeg _BLUEMOON,BlueMoonSeg,word,public,CODE
sBegin  BlueMoonSeg
;       inquire_data contains information about mouse acceleration
;       which the window manager uses.
PUBLIC	inquire_data
inquire_data    CURSORINFO   <X_RATE,Y_RATE>
sEnd    BlueMoonSeg

sBegin	Code
	assumes cs,Code
	assumes ds,Data

externW	pxbytes				;lives in SWCURS.ASM, set in VESAFNS.ASM

;
;	SetCursor	- change cursor shape
;

	org	$+1			;The data segment value will
PUBLIC	_cstods 			;  be stuffed here and kept
_cstods label	word			;  current by the kernel
	org	$-1

cProc	SetCursor,<FAR,PUBLIC,WIN,PASCAL>,<si,di,es,ds>
	parmD	lp_cursor			;Far ptr to new cursor shape
cBegin
	cmp	enabled_flag,00H
	jne	SetCursor_enabled
SetCursor_locally:
	push	ds
	pop	es
	and	cursor_flags,NOT YES_CURSOR
        lds     si,lp_cursor
	mov	ax,ds
	or	ax,si
	je	SetCursor_Busy
	lea	di,cursor_data
	call	cursor_sanitize			;convert to internal format
	or	es:cursor_flags,LOCAL_LOAD + YES_CURSOR
	jmp	SetCursor_Busy

SetCursor_enabled:
	sub	cx,cx				;check for screen busy and
	xchg	screen_busy,cl			; prevent reentrance
	jcxz	SetCursor_Busy

	test	cursor_flags,NEW_COORDS
	jz	SetCursor_OldXY
	EnterCrit
	mov	cx,cursor_xcoord
	mov	bx,cursor_ycoord
	mov	cursor_xdraw,cx 		;these will be the coordinates
	mov	cursor_ydraw,bx 		; the cursor will be drawn at
	and     cursor_flags,not NEW_COORDS
	LeaveCrit b
SetCursor_OldXY:

	mov	exclude_global,1		;OFF flag for other modules
        and     cursor_flags,NOT YES_CURSOR
	call	cursor_funcs.CURSFUNC_OFF	;turn off current cursor
        les     si,lp_cursor                    ;NULL pointer -- no cursor
	mov	ax,es
        or      ax,si
        je      SetCursor_Exit
	mov	exclude_global,0
        or      cursor_flags,YES_CURSOR

	call	cursor_check_sane		;check if we need to sanitize
	jz	@F

	; need to sanitize the cursor before passing it in - swap segs...
	push	es
	push	ds
	pop	es
	pop	ds
	; place sanitized cursor in our internal buffer:
	lea	di,cursor_data
	push	di
	call	cursor_sanitize			;convert to internal format
	; now point the submodule function at that buffer instead:
	pop	si
	; now we need DS == ES == Data :3
	push	es
	pop	ds

@@:	call	cursor_funcs.CURSFUNC_SET	;pass cursor info to submodule

SetCursor_Exit:
	mov	screen_busy,1

SetCursor_Busy:

cEnd




;       MoveCursor
;
;	This routine moves the cursor hot spot to a designated x,y coord.


cProc	MoveCursor,<FAR,PUBLIC,WIN,PASCAL>,<si,di,es,ds>
	parmW	abs_x				;x coordinate of cursor
	parmW	abs_y				;y coordinate of cursor
cBegin
	mov	ax,abs_x
        mov     dx,abs_y

	; sanity check:
	cmp	ax,[VScreen_Width]
	ja	MoveCursor_Busy
	cmp	dx,[VScreen_Height]
	ja	MoveCursor_Busy

	EnterCrit				;need a coherent state here
	mov	cursor_xcoord,ax
	mov	cursor_ycoord,dx
	or	cursor_flags,NEW_COORDS
	LeaveCrit a

	test	cursor_flags,YES_CURSOR 	;if NULL cursor data, done
	jz	MoveCursor_Busy

	sub	cx,cx				;check for screen busy and
	xchg	screen_busy,cl			; prevent reentrance
	jcxz	MoveCursor_Busy

Move_cursor_busy_0:
	EnterCrit				;obtain a coherent state
	mov	cx,cursor_xcoord
	mov	bx,cursor_ycoord
	mov	cursor_xdraw,cx 		;these will be the coordinates
	mov	cursor_ydraw,bx 		; the cursor will be drawn at
	and	cursor_flags,NOT NEW_COORDS
	LeaveCrit a

	test	cursor_flags,LOCAL_LOAD
	jz	@F
	push	ds
	pop	es
	lea	si,cursor_data
	call	cursor_funcs.CURSFUNC_SET	;pass cursor info to submodule
	and	cursor_flags,NOT LOCAL_LOAD

@@:
	call	cursor_funcs.CURSFUNC_MOVE
	test	cursor_flags,NEW_COORDS 	;if cursor moved since drawing
	jnz	Move_cursor_busy_0		; began, draw at new coords
	mov	screen_busy,1

MoveCursor_Busy:

cEnd



;	CheckCursor
;
;	This Routine is called every 54.925 msecs by the system. If
;	anything needs to happen to the cursor, this is your chance!!

cProc	CheckCursor,<FAR,PUBLIC,WIN,PASCAL>,<si,di,es,ds>
cBegin
	sub	cx,cx				;check for screen busy and
	xchg	screen_busy,cl			; prevent reentrance
	jcxz	CheckCursor_Busy
	test	cursor_flags,LOCAL_LOAD
	jz	@F
	push	ds
	pop	es
	lea	si,cursor_data
	call	cursor_funcs.CURSFUNC_SET	;pass cursor info to submodule
	and	cursor_flags,NOT LOCAL_LOAD

@@:
        call    cursor_funcs.CURSFUNC_CHECK
	mov	screen_busy,1

CheckCursor_Busy:
cEnd



;	exclude
;
;	This routine dispatches to the hwcurs or swcurs routine. Those
;	routines will decide whether or not to perform the exclude.
;	Presumably, the hwcurs routine will not exclude the cursor and the
;	swcurs routine will.
;
;       PARMS:
;	cx	left
;	dx	top
;	si	right (inclusive)
;	di	bottom (inclusive)

PUBLIC	exclude_far
exclude_far	PROC	FAR

	call	exclude
	ret

exclude_far	ENDP


PUBLIC	exclude
exclude PROC	NEAR

	push	ds
	push	ax
	mov	ax,_cstods
	mov	ds,ax

	mov	screen_busy,0			;lock the screen
	mov	exclude_rect_valid,1		;these variables are used
	mov	exclude_rect_left,cx		; by interrupt time code
	mov	exclude_rect_right,si		; so they need to be set
	mov	exclude_rect_top,dx		; inside the screen lock
        mov     exclude_rect_bottom,di

        test    cursor_flags,YES_CURSOR
        jz      @F
	call	cursor_funcs.CURSFUNC_EXCLUDE

@@:	mov	screen_busy,1
	pop	ax
	pop	ds
	ret

exclude ENDP


; helper function for DCI
cProc   exclude_rect,<FAR,PUBLIC,PASCAL,NODATA>,<ds,si,di>
	parmD	lpSurface
	parmD	lpRect
cBegin
	assumes	ds,nothing
	lds	si,[lpRect]
	mov	cx,[si.left]
	mov	dx,[si.top]
	mov	di,[si.bottom]
	mov	si,[si.right]
	call	exclude
	; return zero status
	xor	ax,ax
	cwd
cEnd




;	unexclude
;
;	This routine dispatches to the hwcurs or swcurs routine.

PUBLIC	unexclude_far
unexclude_far	PROC	FAR

	call	unexclude
	ret

unexclude_far	ENDP


PUBLIC	unexclude
unexclude	PROC	NEAR

	push	ds
	push	ax
	push	dx
	mov	ax,_cstods
	mov	ds,ax
	assumes	ds,Data

	mov	screen_busy,0			;lock the screen
        mov     exclude_rect_valid,0
        test    cursor_flags,YES_CURSOR
        jz      @F
	call	cursor_funcs.CURSFUNC_UNEXCLUDE
@@:	mov	screen_busy,1

	pop	dx
	pop	ax
	pop	ds
	ret

unexclude	ENDP


; helper function for DCI
cProc   unexclude_rect,<FAR,PUBLIC,PASCAL,NODATA>
	parmD	lpSurface
cBegin
	assumes	ds,nothing
	call	unexclude
cEnd



;       Get_Cursor_Width_Mask
;
;	This routine forms a 32 bit mask that is defined to have a 1 in bit
;	position i if ANY row of the cursor has non-transparent data at bit
;	position i; otherwise bit i is a 0. The mask is left aligned by
;	shifting all 32 bits to the left until the high bit is a 1. This
;	left-shifted mask is returned in bx:ax and dx holds the left-alignment
;	shift count. (NOTE: if all the data is transparent -- certainly an
;	uninteresting cursor -- then bx:ax will of course = 0:0 and dx = 0.)
;
;	PARMS:
;	es:si	pointer to cursor structure (not just the data)
;
;	RETURNS:
;	bx:ax	left aligned mask
;       dx      left alignment shift count

PUBLIC	Get_Cursor_Width_Mask
Get_Cursor_Width_Mask	PROC	NEAR

	push	di
	mov	cx,CURSOR_HEIGHT		;number of rows of cursor data
	mov	dx,0FFFFH
	mov	di,dx
	sub	ax,ax
	mov	bx,ax
	add	si,SIZE cursorShape

@@:	and	di,es:[si]			;form a 32 bit mask which has
	and	dx,es:[si + 2]			; a 1 in a bit position i if
	or	ax,es:[si + 80H]		; ANY row of cursor data is
	or	bx,es:[si + 80H + 2]		; not transparent at that bit
	add	si,4				; position; otherwise bit
	loop	@B				; position i holds a 0
	sub	si,(80H + SIZE cursorShape)

	not	dx
	not	di
	mov	cx,CURSOR_WIDTH / 2		;32 bit mask is in bx:ax. If
	or	ax,di				; bx signed, non-xparent data
	or	bx,dx				; exists at cursor's left edge
	xchg	al,ah
	xchg	bl,bh

@@:	or	ax,ax				; otherwise left align the
	js	Get_Cursor_Width_Mask_Done	; non-xparent data keeping
	shl	bx,1				; track of how many xparent
	rcl	ax,1				; bits there were at left edge
	loop	@B

Get_Cursor_Width_Mask_Done:

	xchg	bx,ax
	mov	dx,CURSOR_WIDTH / 2		;cx should contain # of bits
	sub	dx,cx				; needed for left-alignment
	pop	di
	ret

Get_Cursor_Width_Mask	ENDP



;	cursor_save_state
;
;	This routine saves the current bank select byte for restoration later.
;	PARMS:
;	ds	Data segment

PUBLIC  cursor_save_state
cursor_save_state	PROC	NEAR
	assumes	ds,Data

	cmp	cursor_state_lock,0
	je	@F
	jmp	cursor_save_state_0

@@:	mov	al,[bank_select_byte]
	mov	[saved_bank_select],al

cursor_save_state_0:
        mov     cursor_state_lock,1
	ret

cursor_save_state	ENDP



;	cursor_restore_state
;
;	This routine restores the VGA state saved by cursor_save_state.
;	PARMS:
;	ds	Data segment

PUBLIC	cursor_restore_state
cursor_restore_state	PROC	NEAR

	mov	dl,[saved_bank_select]
	SET_BANK

	mov	cursor_state_lock,0
        ret

cursor_restore_state	ENDP


;	cursor_kludge
;
;	This routine, at the time it was written was used only by the hardware
;	cursor to force a reload of the cursor data when there was a screen
;	switch from DOS.
;	PARMS:
;	ds	Data segment

PUBLIC	cursor_kludge
cursor_kludge	PROC	FAR
; 
; 	lea	ax,hwcursor_set
; 	cmp	ax,[cursor_funcs]
; 	jne	cursor_kludge_done
; 
; 	sub	cx,cx				;check for screen busy and
; 	xchg	screen_busy,cl			; prevent reentrance
; 	jcxz	cursor_kludge_done
; 
; 	call	hwcursor_kludge 		;this forces a cursor reload
; 	mov	screen_busy,1
; 
cursor_kludge_done:
	ret

cursor_kludge	ENDP


;	cursor_check_sane
;
;	This routine checks if a cursor is the right size, and returns ZF set
;	if so, clear if not. If ZF clear, then cursor_sanitize needs to be run
;	before the data can be used!
;
;	PARMS:
;	es:si	external cursor

cursor_check_sane	PROC	NEAR
	assumes	ds,nothing
	assumes	es,nothing

	cmp	es:[si.csHeight],CURSOR_HEIGHT
	jne	@F
	cmp	es:[si.csWidth],CURSOR_WIDTH
@@:	ret
cursor_check_sane	ENDP

;	cursor_sanitize
;
;	This routine converts an external mono or colour cursor of arbitrary
;	size to our internal 32*32, truncating if necessary
;
;	PARMS:
;	ds:si	external cursor
;	es:di	destination

?_pub	cursor_sanitize
cursor_sanitize	PROC	NEAR
	assumes	ds,nothing
	assumes	es,nothing

	push	bp	; we will use this as an inner-loop counter

	cld
	; copy in the header
	mov	cx,(SIZE cursorShape) SHR 1
	rep	movsw

	; check whether we're sanitizing a mono or colour cursor
	cmp	es:[di-(SIZE cursorShape)].csColor,0101h
	je	set_width_bytes_mono
	mov	bx,[pxbytes]
	; multiply by cursor width to get width in bytes:
	mov	cl,5
	shl	bx,cl
.errnz	(CURSOR_WIDTH - (1 SHL 5))
	jmp	short fix_width_bytes
set_width_bytes_mono:
	mov	bx,CURSOR_WBYTEMNO
fix_width_bytes:
	xchg	bx,es:[di-(SIZE cursorShape)].csWidthBytes

	; regularize the size
	mov	cx,CURSOR_HEIGHT
	mov	dx,CURSOR_WIDTH
	xchg	cx,es:[di-(SIZE cursorShape)].csHeight
	xchg	dx,es:[di-(SIZE cursorShape)].csWidth

	; regularize the hotspot (in case they gave us a cursor that's too big!)
	cmp	es:[di-(SIZE cursorShape)].csHotX,CURSOR_WIDTH
	jna	@F
	mov	es:[di-(SIZE cursorShape)].csHotX,CURSOR_WIDTH

@@:	cmp	es:[di-(SIZE cursorShape)].csHotY,CURSOR_HEIGHT
	jna	@F
	mov	es:[di-(SIZE cursorShape)].csHotY,CURSOR_HEIGHT

@@:	; at this point, CX is the number of rows of cursor data, and we have
	; to copy this many rows of 1bpp AND mask.
	push	cx
	cmp	cx,CURSOR_HEIGHT
	jbe	@F
	mov	cx,CURSOR_HEIGHT

@@:	; set 0FFh so we pad the AND mask with ones
	mov	al,0FFh

and_mask_loop:
	mov	bp,CURSOR_WIDTH
	cmp	dx,bp
	jae	@F	; if cursor width correct or too wide, go copy 32 cols
	mov	bp,dx	; if too narrow, only copy as many cols as given
@@:	sar	bp,3	; convert to mono bytes
	xchg	bp,cx	; use CX for the actual REP instruction
	rep	movsb
	mov	cx,bp	; get back outer loop counter
	; now check if we've to skip any bytes in src or dest
	mov	bp,dx
	sub	bp,CURSOR_WIDTH
	loope	and_mask_loop
	je	and_mask_copy_done

	ja	and_mask_skip_src
	; BP negative --> we need to pad -BP pixels in the destination with ones
	neg	bp
	sar	bp,3	; convert to mono bytes
	xchg	bp,cx	; use CX for the actual REP instruction
	rep	stosb
	mov	cx,bp	; get back outer loop counter
	jcxz	and_mask_copy_done
	jmp	short and_mask_loop
and_mask_skip_src:
	; BP positive --> we need to skip +BP pixels in the source
	sar	bp,3	; convert to mono bytes
	lea	si,[bp+si]
	jcxz	and_mask_copy_done
	jmp	short and_mask_loop

and_mask_copy_done:
	pop	cx
	; now check if we've to skip any rows in src or dest
	mov	bp,cx
	sub	bp,CURSOR_HEIGHT
	je	and_mask_done

	ja	and_mask_skip_src_rows
	; BP negative --> we need to pad -BP rows in the destination with ones
	neg	bp
	xchg	bp,cx	; use CX for the actual REP instruction
	shl	cx,5-3	; convert to width of mono row in bytes
.errnz	(CURSOR_WBYTEMNO - (1 SHL (5-3)))
	rep	stosb
	mov	cx,bp	; get back outer loop counter
	jmp	short and_mask_done

and_mask_skip_src_rows:
	; BP positive --> we need to skip +BP rows in the source
	push	dx
	xchg	bp,cx	; use CX for the actual LOOP instruction
	shr	dx,3	; convert to mono bytes
@@:	add	si,dx
	loop	@B
	mov	cx,bp	; get back outer loop counter
	pop	dx

and_mask_done:
	; Now the XOR mask. If it's mono, then we basically do the exact same
	; thing again, whereas if it's colour things are a bit different...
	inc	al			; make it 0 if it was 0FFh
	jnz	cursor_sanitize_done	; if it was already 0, we're done

	push	cx
	cmp	cx,CURSOR_HEIGHT
	jbe	@F
	mov	cx,CURSOR_HEIGHT

@@:	; if it's mono, then widthbytes (== BX) < width (== DX)
	cmp	bx,dx
	jb	and_mask_loop		; go do the same thing we did before!

xor_mask_loop:
	mov	ax,CURSOR_WIDTH
	cmp	dx,ax
	jae	@F	; if cursor width correct or too wide, go copy 32 cols
	mov	ax,dx	; if too narrow, only copy as many cols as given
@@:	mov	ah,byte ptr pxbytes[0]
	mul	ah	; convert AX to colour bytes
	xchg	ax,cx	; use CX for the actual REP instruction
	rep	movsb
	mov	cx,ax	; get back outer loop counter
	; now check if we've to skip any bytes in src or dest
	mov	ax,dx
	sub	ax,CURSOR_WIDTH
	loope	xor_mask_loop
	je	xor_mask_copy_done

	ja	xor_mask_skip_src
	; AX negative --> we need to pad -AX pixels in dest with black
	neg	ax
	mov	ah,byte ptr pxbytes[0]
	mul	ah	; convert AX to colour bytes
	mov	bp,cx	; save outer loop counter
	mov	cx,ax	; use CX for the actual REP instruction
	xor	al,al	; zero - black
	rep	stosb
	mov	cx,bp	; get back outer loop counter
	jcxz	xor_mask_copy_done
	jmp	short xor_mask_loop
xor_mask_skip_src:
	; AX positive --> we need to skip +AX pixels in the source
	mov	bp,ax
	mov	ax,cx	; save outer loop counter
	mov	cx,[pxbytes]
@@:	lea	si,[bp+si]
	loop	@B
	mov	cx,ax	; get back outer loop counter
	jcxz	xor_mask_copy_done
	jmp	short xor_mask_loop

xor_mask_copy_done:
	pop	cx
	; now check if we've to skip any rows in src or dest
	mov	ax,cx
	sub	ax,CURSOR_HEIGHT
	; we're done with the source, so we don't bother to skip rows in it -
	; hence done if **above or** equal!
	jae	cursor_sanitize_done

	; AX negative --> we need to pad -AX rows in the destination with black
	neg	ax
	mov	ah,byte ptr pxbytes[0]
	mul	ah	; convert AX to colour bytes
	xchg	ax,cx	; use CX for the actual REP instruction
	shl	cx,5	; convert to width of row in bytes
.errnz	(CURSOR_WIDTH - (1 SHL 5))
	rep	stosb
	mov	cx,ax	; get back outer loop counter

cursor_sanitize_done:
	pop	bp
	ret

cursor_sanitize	ENDP

sEnd    Code

END

