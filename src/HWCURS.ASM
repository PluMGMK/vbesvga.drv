;
;	FILE:	hwcurs.asm
;	DATE:	1/9/91
;	AUTHOR: Jim Keller
;
;	This file handles the hardware cursor on the VRAM I, VRAM II,
;	and 1024I boards. (I think it also works on the VGA16.)
;
;	NOTE: In the hwcurs_move routine, the Double_pump bit (bit 6 in AT11)
;	needs to be checked to determine whether the x coordinate needs to be
;	double before stuffing it in the cursor x position registers. The
;	x coordinate should be doubled if the bit is a 1. Unfortunately
;	accessing an attribute register blanks the screen. I could check
;	the status of this bit at setmode time, but will the bit state still
;	be valid in the nulti-resolution driver context. Basically I need
;	to set a variable every time this bit gets changed. I will have to
;	figure out how and when this can occur.



.286
FILE_HWCURS	EQU	1

include cmacros.inc
include macros.mac
include windefs.inc
include gdidefs.inc
include vgareg.inc
include cursor.inc
include hwcurs.inc



NEW_DATA	EQU	00000001B

sBegin  Data
EXTRN	ScreenSelector:word
PUBLIC	hwcursor_rotated, hwcursor_newdata, hwcursor, hwcursor_data
hwcursor_rotated	DW		0
hwcursor_newdata	DW		1	;first time forces reload
hwcursor		cursorShape	<>
hwcursor_data		DB		256 DUP (0)
sEnd    Data


sBegin	Code
	assumes cs,Code
	assumes ds,Data

;       hwcursor_set
;
;	This routine is called when there is a new cursor pattern to install.
;	PARMS:
;       ds      Data segment
;	es:si	ptr to cursor pattern

PUBLIC	hwcursor_set
hwcursor_set	PROC	NEAR

	push	ds
	push	es
	pop	ds
	pop	es
	lea	di,hwcursor
	mov	cx,(SIZE cursorShape) / 2 + 80H
	rep	movsw

        push    es
        pop     ds
	mov	hwcursor_newdata,1
	call	hwcursor_on
	ret

hwcursor_set	ENDP



;	hwcursor_move
;
;       This routine moves the cursor to the specified position.
;       The coordinates of the desired location for the cursor hot spot
;       are cursor_xdraw, cursor_ydraw.
;       PARMS:
;       ds      Data segment

PUBLIC  hwcursor_move
hwcursor_move   PROC    NEAR

        sub     si,si                           ;when done with this section
        mov     cx,cursor_xdraw                 ; si will hold the x rotation
        sub     cx,hwcursor.csHotX              ; value, and cx will hold the
        jns     @F                              ; x coordinate to place in
        sub     si,cx                           ; the cursor location regs
        sub     cx,cx

@@:     sub     di,di                           ;when done with this section
        mov     bx,cursor_ydraw                 ; di will hold the y rotation
        sub     bx,hwcursor.csHotY              ; value, and bx will hold the
        jns     @F                              ; y coordinate to place in
        sub     di,bx                           ; the cursor location regs
        sub     bx,bx

@@:     mov     ax,si                           ;if this move does not cause
        or      ax,di                           ; cursor to be rotated, and
        or      ax,hwcursor_rotated             ; cursor not currently rotated
	or	ax,hwcursor_newdata		; cursor is a new pattern
        je      @F                              ; then skip call
        push    cx
        push    bx
        call    hwcursor_copy_data_rotated
        pop     bx
        pop     cx

@@:	test	cursor_flags,DOUBLE_PUMP
	je	@F
	shl	cx,1

@@:	mov	dx,VGAREG_SQ_ADDR
	in	al,dx
	push	ax				;now update the cursor position
	mov	al,VGAREG_SQ_HORZ_POSITION_HIGH ; registers. The vert position
	mov	ah,ch				; low register should be
	out	dx,ax				; updated last.

	mov	al,VGAREG_SQ_HORZ_POSITION_LOW
	mov	ah,cl
	out	dx,ax

        mov     al,VGAREG_SQ_VERT_POSITION_HIGH
        mov     ah,bh
        out     dx,ax

        mov     al,VGAREG_SQ_VERT_POSITION_LOW
        mov     ah,bl
        out     dx,ax

	pop	ax				;restore index
	out	dx,al
        ret

hwcursor_move   ENDP



;       hwcursor_off
;
;	This routine turns the hwcursor off.

PUBLIC	hwcursor_off
hwcursor_off	PROC	NEAR

	mov	dx,VGAREG_SQ_ADDR
	in	al,dx
	mov	ah,al
	mov	al,VGAREG_SQ_CURSOR
	out	dx,al
	inc	dx
	in	al,dx
	and	al,7FH
	out	dx,al
	dec	dx
	mov	al,ah
	out	dx,al
	ret

hwcursor_off	ENDP



;	hwcursor_on
;
;	This routine turns the hwcursor on. If the cursor data has changed
;	since the cursor was last on, the new data is put into place before
;	the cursor is turned on.
;	PARMS:
;	ds	Data segment

PUBLIC	hwcursor_on
hwcursor_on	PROC	NEAR

	or	hwcursor_newdata,0
	je	@F
	call	hwcursor_move

@@:	mov	dx,VGAREG_SQ_ADDR
	in	al,dx
	mov	ah,al
	mov	al,VGAREG_SQ_CURSOR
	out	dx,al
	inc	dx
	in	al,dx
	or	al,80H
	out	dx,al
	dec	dx
	mov	al,ah
	out	dx,al
	ret

hwcursor_on	ENDP



;	hwcursor_copy_data_rotated
;
;	This routine takes the cursor data and places it in video memory.
;	The registers which tell the VGA chip where to fetch the cursor
;	data from are consulted to determine where in video memory to
;	place the cursor data. Hence, these registers must have been
;	set previously. If the HW cursor is at the top or left edge of
;	the screen, then the data will have to be rotated properly to make
;	it appear as if the cursor is clipped at these edges. Hardware
;	performs right and bottom edge clipping automatically.
;
;       PARMS:
;	ds	Data segment
;	si	x rotation amount
;	di	y rotation amount

PUBLIC	hwcursor_copy_data_rotated
hwcursor_copy_data_rotated	PROC	NEAR

	push	bp
	mov	bp,sp
	cld
	sub	sp,8
	mov	[bp - 2],si
	mov	[bp - 4],di
	mov	word ptr [bp - 6],20H
	sub	[bp - 6],di
	mov	ax,si				;need to keep track of whether
	or	ax,di				; cursor data in memory is
	mov	hwcursor_rotated,ax		; rotated or not

	call	cursor_save_state		;save vgaregs
	call	hwcursor_setaddr		;set addressing

	lea	si,hwcursor_data
	mov	ax,[bp - 4]			;perform y rotation
	shl	ax,2
	add	si,ax
	mov	ax,ScreenSelector
	mov	es,ax
	mov	di,0FF00H
	cmp	word ptr [bp - 2],0
	je	hwcursor_no_column_rotate

PUBLIC	hwcursor_rotate_column
hwcursor_rotate_column:

	mov	ax,[bp - 2]
	mov	[bp - 8],ax
	mov	dx,[si + 80H]
	mov	cx,[si + 80H + 2]
	lodsw
	mov	bx,ax
	lodsw
	xchg	dl,dh
	xchg	cl,ch				;XOR mask is in dx:cx
	xchg	al,ah
	xchg	bl,bh				;AND mask is in bx:ax

@@:	stc					;AND mask needs 1s rotated in
	rcl	ax,1
	rcl	bx,1
	shl	cx,1				;OR mask needs 0s rotated in
	rcl	dx,1
	dec	word ptr [bp - 8]
	jne	@B

	xchg	cl,ch
	xchg	dl,dh
	xchg	al,ah
	xchg	bl,bh
        mov     es:[di + 80H],dx
	mov	es:[di + 80H + 2],cx
	mov	es:[di],bx
	add	di,2
	stosw
	dec	word ptr [bp - 6]
	jne	hwcursor_rotate_column
	jmp	hwcursor_column_rotated

hwcursor_no_column_rotate:

	mov	cx,[bp - 6]			;special case if no rotation
	shl	cx,1				; column rotation required
@@:	mov	ax,[si + 80H]			; which happens ALOT
	mov	es:[di + 80H],ax
	movsw
	loop	@B

hwcursor_column_rotated:
	mov	ax,0FFFFH			;Make remaining rows xparent
	sub	bx,bx				; by setting AND mask to FFFFH
	mov	cx,[bp - 4]			; and XOR mask to 0000H
	shl	cx,1
	je	short hwcursor_done_rotating

@@:	mov	es:[di + 80H],bx
	stosw
	loop	@B

hwcursor_done_rotating:

	call	cursor_restore_state		;restore vgaregs
	mov	sp,bp
	pop	bp
	mov	hwcursor_newdata,0
	ret

hwcursor_copy_data_rotated	ENDP



;	hwcursor_setaddr
;
;	This routine sets the write bank and page to the 64K page where the
;	cursor data should go.
;	PARMS:
;	ds	Data segment

PUBLIC	hwcursor_setaddr
hwcursor_setaddr	PROC	NEAR

        mov     dx,VGAREG_SQ_ADDR               ;set correct write bank for
        mov     al,VGAREG_SQ_INTERFACE          ; writing in cursor data
        out     dx,al                           ; by using the bank from
        inc     dx                              ; which the hardware will
        in      al,dx                           ; be fetching the data
        shr     al,5
        mov     ah,al

        dec     dx
	mov	al,VGAREG_SQ_BANK_SELECT
        out     dx,al
        inc     dx
        in      al,dx
        and     ax,03FCH
        or      al,ah
        out     dx,al

	dec	dx					;hardware forces the
	mov	ax,VGAREG_SQ_EXTENDED_PAGE + 100H	; cursor data to come
	out	dx,ax					; from offset 192K
	mov	dx,VGAREG_MISC_R			; within a 256K bank.
	in	al,dx					; 192K is the third 64K
	mov	dx,VGAREG_MISC_W			; page when the pages
	or	al,20H					; are numbered 0,1,2,3
	out	dx,al
	ret

hwcursor_setaddr	ENDP



;	hwcursor_dummy_ret
;
;	This routine is used when calls from higher layers are calling a
;	cursor function that is a NOP from the hardware cursor perspective.

PUBLIC	hwcursor_exclude, hwcursor_unexclude, hwcursor_check

PUBLIC	hwcursor_dummy_ret
hwcursor_dummy_ret	PROC	NEAR

hwcursor_exclude:
hwcursor_unexclude:
hwcursor_check:

	ret

hwcursor_dummy_ret	ENDP


;	hwcursor_kludge
;
;	This routine forces a reload of the hardware cursor data. It is used
;	when coming back from a DOS shell.
;	PARMS:
;	ds	Data segment

PUBLIC	hwcursor_kludge
hwcursor_kludge 	PROC	NEAR

	mov	hwcursor_newdata,1
	call	hwcursor_on
	ret

hwcursor_kludge 	ENDP

sEnd    Code

END


