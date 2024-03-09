;
;	FILE:	blt11.asm
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module contains routines that deal with mono to mono blts.
;

SRCFILE_BLT11	equ	1
incLogical	=	1
incDrawMode	=	1

include cmacros.inc
include gdidefs.inc
include macros.mac
include njumps.mac
include genconst.inc
include bblt.inc
include bitblt.var
include compblt.inc

.286
sBegin	Code
assumes cs,Code
assumes ds,Nothing
assumes es,Nothing
assumes ss,Nothing


;
;	blt11
;
;	PARMS:
;	ES:DI	ptr to location to compile code
;

PUBLIC	blt11
blt11	PROC	NEAR

	test	word ptr rop_flags,PATTERN_PRESENT
	je	@F
	call	compile_mono_pattern_fetch

@@:	cmp	first_edge_mask,0FF00H		;If there is no left edge
	je	@F				; partial byte then move on
	call	compile_mtom_first_edge 	;else do it

@@:	cmp	word ptr inner_loop_count,0	;if there is no inner loop to
	je	@F				; bo done then move on
	call	compile_mtom_loop

@@:	call	compile_mtom_last_edge		;there is always a last edge
						;If only part of one byte
						; is present, that will be the
						; last edge
	call	compile_outer_loop
	call	compile_src_memory_yupdate
	call	compile_dst_memory_yupdate
	call	compile_jmp_back_to_start
@@:	ret

blt11	ENDP			;

;
;	compile_mtom_first_edge
;
;	A few things to note. First the blt may go either right to left or
;	left to right. The routine set_directions did several fixups to allow
;	a little more common code here. For example, the left edge mask and
;	right edge mask were switched if the blt goes from right to left so
;	that there are the two masks first_edge_mask and last_edge_mask. The
;	first_edge_mask is the one you come to first during the blt -- if the
;	blt is left to right this is the left edge mask; if the blt is right
;	to left then first_edge_mask is the right edge mask.
;	Also the align shift count always has the correct absolute value to
;	shift, but it will be negative if a left rotation is needed.
;
;	Here is the template for the code generated:
;	IF  SRC is used in blt
;	    lodsb
;
;	    IF	(ROTATING RIGHT & BLT X-) or (ROTATING LEFT & BLT is X+)
;		mov	ah,al
;		lodsb
;		IF  BLT is X+
;		    dec  si
;		IF  BLT is X-
;		    inc  si
;
;		xchg	al,ah
;		IF  ROTATING RIGHT
;		    ror ax,align_rotate_count
;		IF  ROTATING LEFT
;		    rol ax,-align_rotate_count
;
;	    IF	(ROTATING RIGHT & BLT X+) or (ROTATING LEFT & BLT X-)
;		IF  ROTATING RIGHT
;		    ror ax,align_rotate_count
;		IF  ROTATING LEFT
;		    rol ax,-align_rotate_count
;
;	ROP CODE which leaves the result in al
;
;	EDGE MASK CODE
;

PUBLIC	compile_mtom_first_edge
compile_mtom_first_edge PROC	NEAR

	test	word ptr rop_flags,SOURCE_PRESENT  ;skip src stuff if not used
	je	cmtomfe_ropcode

	mov	al,I_LODSB
	stosb

	mov	cx,align_rotate_count
	jcxz	cmtomfe_ropcode
	mov	bx,dst_xExt_bytes
	xor	ch,bh				;if blt X+ and rotating left
	jns	@F				; or blt X- and rotating right
	mov	ax,I_MOV_AH_SRC 		; then mov ah,[si]
	stosw
	jmp	short cmtomfe_rot

@@:	mov	al,I_DEC_SI			;backup to the start byte again
	or	bx,bx				; if blt X+ and rot right or
	jns	@F				; blt X- and rot left. the
	mov	al,I_INC_SI			; backup direction depends on
@@:	stosb					; the blt direction of course

cmtomfe_rot:
	mov	ax,I_ROR_AX_N			;assume rotate right
	or	cl,cl				;if cl is signed, rotate left
	jns	@F
	neg	cl				;get magnitude of rotate
	mov	ax,I_ROL_AX_N
@@:	stosw
	mov	al,cl
	stosb

cmtomfe_ropcode:
	call	compile_rop			;compile on the rop code
	mov	ax,first_edge_mask
	call	compile_edge_mask		;mask the edge correctly
	ret

compile_mtom_first_edge ENDP			;

;
;	compile_mtom_loop
;
;	A few things to note. First the blt may go either right to left or
;	left to right. The routine set_directions did several fixups to allow
;	a little more common code here. Also the align shift count always has
;	the correct absolute value to shift, but it will be negative if a left
;	rotation is needed.
;	NOTE: The five lodsbs in the template below with @@ in front of them
;	are mutually exclusive -- only one will get generated.
;
;	Here is the template for the code generated:
;	    IF	inner_loop_count > 1
;		mov    cx,inner_loop_count
;	    IF	SRC is used in blt
;
;		IF  NO ROTATING
;		    @@: lodsb
;
;		IF  (ROTATING RIGHT & BLT X+) or (ROTATING LEFT AND BLT X-)
;		    lodsb
;		    mov bl,al
;		    @@: lodsb
;		    mov    ah,bl
;		    mov    bl,al
;		    IF	ROTATING RIGHT
;			ror    ax,align_shift_count
;		    IF	ROTATING LEFT
;			rol    ax,-align_shift_count
;
;		IF  (ROTATING RIGHT AND BLT X-) or (ROTATING LEFT AND BLT X+)
;		    lodsb
;		    mov    bl,al
;		    @@:    lodsb
;		    xchg   al,bl
;                   mov    ah,bl
;		    IF	ROTATING RIGHT
;			ror    ax,align_shift_count
;		    IF	ROTATING LEFT
;			rol    ax,-align_shift_count
;
;	    ROP CODE
;
;	    stosb
;	    loop @B
;
;	    IF	SRC is used in blt
;		IF  ROTATING LEFT or ROTATING RIGHT
;		    IF	BLT is X+
;			dec    si
;		    IF	BLT is X-
;			inc    si
;

PUBLIC	compile_mtom_loop
compile_mtom_loop	PROC	NEAR

	call	compile_inner_loop_start
        mov     dx,di                           ;save possible looping address
	test	word ptr rop_flags,SOURCE_PRESENT  ;skip src stuff if not used
	je	cmtomil_ropcode

        or      word ptr device_flags,DEVFLAG_MOVSB or DEVFLAG_REP
	mov	al,I_LODSB			;lodsb
        stosb

	mov	cx,align_rotate_count		;if there is no rotate count
	jcxz	cmtomil_ropcode 		; and go right to the ropcode

	and	word ptr device_flags,NOT DEVFLAG_MOVSB
	mov	ax,I_MOV_BL_AL			;mov bl,al
	stosw
	mov	dx,di				;save looping address
	mov	al,I_LODSB			;lodsb
        stosb

	mov	ax,I_MOV_AH_BL			;based on bltdirection XOR
	mov	bx,I_MOV_BL_AL			; rotatedirection do two
	xor	cx,dst_xExt_bytes		; different instruction
	jns	@F				; sequences
	mov	ax,I_XCHG_AL_BL
	mov	bx,I_MOV_AH_BL
@@:	stosw
	mov	ax,bx
	stosw

	mov	ax,I_ROR_AX_N			;xoring bx with dst_xExt_bytes
	xor	cx,dst_xExt_bytes		; recovers align_rotate_count
	jns	@F				; and sets the flags as to the
	mov	ax,I_ROL_AX_N			; rotate direction -- cool!
	neg	cl				;if rotate left (signed) get
@@:	stosw					; rotate absolute value
	mov	al,cl
	stosb

cmtomil_ropcode:
	push	dx				;save looping address
	call	compile_rop			;put rop on stack
	mov	al,I_STOSB			;a final stosb
	stosb
	pop	bx				;pass looping address to LOOP X
	call	compile_inner_loop_end		;generate LOOP X if needed

	test	word ptr device_flags,DEVFLAG_MOVSB
	je	cmtomil_nomovsb
	sub	di,2
	test	word ptr device_flags,DEVFLAG_REP
	je	@F
	sub	di,2
	mov	al,I_REP
	stosb
@@:	mov	al,I_MOVSB
	stosb

cmtomil_nomovsb:
	test	word ptr rop_flags,SOURCE_PRESENT  ;skip src stuff if not used
	je	cmtomil_done
	or	word ptr align_rotate_count,0
	je	cmtomil_done			;if rotating either direction,
	mov	al,I_DEC_SI			; always read 1 byte too far
	or	word ptr dst_xExt_bytes,0	; so dec si if blt x+
	jns	@F				; and inc si if blt x-
	mov	al,I_INC_SI
@@:	stosb

cmtomil_done:
	ret

compile_mtom_loop	ENDP			;



;
;	compile_mtom_last_edge
;
;	A few things to note. First the blt may go either right to left or
;	left to right. The routine set_directions did several fixups to allow
;	a little more common code here. Also the align shift count always has
;	the correct absolute value to shift, but it will be negative if a left
;	rotation is needed.
;	This code will be very similar to the compile_mtom_inner_loop code.
;
;	Here is the template for the code generated:
;	IF  SRC is used in blt
;	    lodsb
;
;	IF  src_more_than_1byte (which is the case if the first edge mask != 0)
;	    IF	(ROTATING RIGHT and BLT X+)
;		IF  (left SHIFTING of the last edge mask by n != 0)
;		    mov ah,al
;		    lodsb
;
;	    IF	(ROTATING LEFT and BLT X-)
;		IF  (right SHIFTING of the last edge mask by n != 0)
;		    mov ah,al
;		    lodsb
;
;           IF  NO ROTATING
;		----		no code generated
;
;	IF  ROTATING RIGHT
;	    ror ax,-align_rotate_count
;
;	IF  ROTATING LEFT
;	    rol ax,-align_rotate_count
;
;	ROP CODE
;
;	EDGE MASK CODE
;

PUBLIC	compile_mtom_last_edge
compile_mtom_last_edge	PROC	NEAR

	test	word ptr rop_flags,SOURCE_PRESENT  ;skip src stuff if not used
	jne	@F
	jmp	cmtomle_ropcode

@@:     mov     al,I_LODSB
	stosb

	mov	cx,align_rotate_count		;if the rotate count is 0, then
	or	cx,cx
	jne	@F
	jmp	cmtomle_ropcode 		; proceed to the ropcode
@@:
	cmp	word ptr src_more_than_1byte,1	;if width of src blt rect only
	je	cmtomle_no_last_load		; 1 byte, then skip below

        mov     bx,dst_xExt_bytes
	or	bx,bx
	js	blt11_xleft

	or	cx,cx
	js	blt11_xright_rotleft
	mov	ax,I_MOV_AH_AL
	stosw
	mov	al,last_edge_mask
	shl	al,cl
	je	@F
	mov	al,I_LODSB
	stosb
@@:	mov	ax,I_ROR_AX_N
	jmp	short	cmtomle_rotate

blt11_xright_rotleft:
	neg	cl
	mov	al,last_edge_mask
	ror	al,cl
	or	al,al
	jns	@F
	mov	ax,I_MOV_AH_AL
	stosw
	mov	al,I_LODSB
	stosb
	mov	ax,I_XCHG_AL_AH
	stosw
@@:	mov	ax,I_ROL_AX_N
	jmp	short	cmtomle_rotate

blt11_xleft:
	or	cx,cx
	js	blt11_xleft_rotleft
	mov	al,last_edge_mask
	rol	al,cl
	ror	al,1
	or	al,al
	jns	@F
        mov     ax,I_MOV_AH_AL
        stosw
        mov     al,I_LODSB
        stosb
        mov     ax,I_XCHG_AL_AH
        stosw
@@:	mov	ax,I_ROR_AX_N
	jmp	short	cmtomle_rotate

blt11_xleft_rotleft:
	neg	cl
	mov	ax,I_MOV_AH_AL
	stosw
	mov	al,last_edge_mask
	shr	al,cl
	je	@F
	mov	al,I_LODSB
	stosb
@@:	mov	ax,I_ROL_AX_N
	jmp	short	cmtomle_rotate

cmtomle_no_last_load:
	mov	ax,I_ROR_AX_N
	or	cx,cx
	jns	cmtomle_rotate
	mov	ax,I_ROL_AX_N
	neg	cl

cmtomle_rotate:
	stosw
	mov	al,cl
	stosb

cmtomle_ropcode:
	call	compile_rop
	mov	ax,last_edge_mask
	call	compile_edge_mask
	ret

compile_mtom_last_edge	ENDP

sEnd	CODE

END

