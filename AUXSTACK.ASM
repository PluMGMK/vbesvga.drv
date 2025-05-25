; Assemble as a binary file, should be possible on any platform
;	e.g. jwasm -bin auxstack.asm
; then rename auxstack.bin to auxstack.com

	.8086
	.model	tiny

;The purpose of this TSR, as the name suggests, is to provide an Auxiliary Stack
;For what, you ask? For int 10h calls, I say! But why?
;
; The problem arises with the logo-display (and removal) code in WIN.COM, which
; calls int 10h several times to set the video mode, #scanlines, cursor attrs,
; etc. WIN.COM provides a paltry 200-odd bytes of stack space, whereas VBE
; implementations of int 10h can theoretically require up to 1024 bytes. On my
; machine, I've found that using the traditional modeset function (AH=00h) to
; return to text mode uses 256 bytes of stack, thus overwriting WIN.COM's buffer
; containing the path to DSWAP.EXE - d'oh!
;
; This TSR solves this problem by intercepting each int 10h call, checking to
; see if it's coming from WIN.COM's logo code (which helpfully includes the
; signature "LOGO" at the beginning of the code segment) and, if it is,
; switching to a more generous internal stack of 1024 bytes. Unfortunately,
; this means it consumes a little over 1K of conventional memory, but this is
; the price to pay for reliability in this particular case...

	.code
	org	100h
stack_space	label word
start:	jmp	real_start

	; skip 1024 bytes to make space for the stack
	; (but leave only the bare minimum 60h for PSP!)
	org	460h
stack_top	label word

intercept_count	dw 0
interrupt_lock	dw 0
old_int10h	dd 0
saved_stack	dd 0
signature	db "LOGO"

;This is 6175h, which _technically_ collides with "HUNTER 16" (move cursor to
; graphics co-ordinates) - but in reality DX (the row) gets set to 7873h for
; the installation check, which corresponds to 30835 => never gonna happen :)
INSTCHECK_AX_ENTRY	equ ('a' SHL 8) + 'u'
INSTCHECK_DX_ENTRY	equ ('x' SHL 8) + 's'
INSTCHECK_AX_EXIT	equ 'ta'
INSTCHECK_DX_EXIT	equ 'ck'

hooked_int10h	proc near
	;first see if this is an installation check...
	cmp	ax,INSTCHECK_AX_ENTRY
	jne	@F
	cmp	dx,INSTCHECK_DX_ENTRY
	jne	@F
	;just set AX and DX, and return immediately!
	mov	ax,INSTCHECK_AX_EXIT
	mov	dx,INSTCHECK_DX_EXIT
	iret

@@:	push	bp
	mov	bp,sp
	push	es
	push	ax
	push	dx

	mov	es,[bp+4]	;CS on interrupt stack frame
	mov	ax,es:[0]
	mov	dx,es:[2]
	cmp	ax,word ptr cs:signature[0]
	jne	@F
	cmp	dx,word ptr cs:signature[2]
	jne	@F
	;signature matches, but make sure our stack isn't locked!
	mov	ax,1
	xchg	cs:[interrupt_lock],ax
	test	ax,ax
	jnz	@F

	;OK, all the conditions are met to switch stacks and call through!
	;clear off the current stack before switching to the new one
	pop	dx
	pop	ax
	pop	es
	pop	bp

	;save the current stack pointer
	mov	word ptr cs:saved_stack[0],sp
	mov	word ptr cs:saved_stack[2],ss
	;switch to ours
	push	cs
	pop	ss
	lea	sp,stack_top

	;and call through!
	pushf
	call	cs:old_int10h

	;we're back, so restore the stack
	mov	ss,word ptr cs:saved_stack[2]
	mov	sp,word ptr cs:saved_stack[0]
	;unlock our stack and log that we've intercepted a call
	dec	cs:[interrupt_lock]
	inc	cs:[intercept_count]
	;and return! :)
	iret

@@:	;not intercepting, so just restore the registers and jump to the normal
	; interrupt handler
	pop	dx
	pop	ax
	pop	es
	pop	bp
	jmp	cs:old_int10h
hooked_int10h	endp

end_resident_code	label byte

real_start:
	;first check if we're already installed...
	mov	ax,INSTCHECK_AX_ENTRY
	mov	dx,INSTCHECK_DX_ENTRY
	push	ds		;just in case this call clobbers it...
	int	10h
	pop	ds
	cmp	ax,INSTCHECK_AX_EXIT
	jne	@F
	cmp	dx,INSTCHECK_DX_EXIT
	jne	@F

	mov	ah,9		;output string to stdout
	lea	dx,already_inst
	int	21h
	ret			;hit the int 20h in the PSP :)

@@:	mov	ax,3510h	;get interrupt vector 10h
	int	21h
	mov	word ptr old_int10h[0],bx
	mov	word ptr old_int10h[2],es

	mov	ax,2510h	;set interrupt vector 10h
	lea	dx,hooked_int10h
	int	21h

	;print welcome message
	lea	dx,welcome_msg
	mov	ah,9		;output string to stdout
	int	21h

	;print location of intercept counter
	mov	ax,cs
	call	prtxw
	mov	al,':'
	call	prtch
	lea	ax,intercept_count
	call	prtxw
	mov	al,0Dh
	call	prtch
	mov	al,0Ah
	call	prtch

	;before we go resident, tidy up a few more things:
	;* free environment to save Conventional Memory
	mov	es,ds:[2Ch]	;get env segment
	mov	ah,49h		;free memory
	int	21h
	;* go through JFT sarching for open files, and close 'em all!
	push	ds
	pop	es
	cld
	mov	di,18h		;offset of JFT
	mov	cx,20		;default JFT length
file_check_loop:
	mov	al,-1		;closed file indicator
@@:	scasb
	loope	@B

	mov	ah,3Eh		;close file
	lea	bx,[di-1-18h]	;get file index
	int	21h
	inc	cx
	loop	file_check_loop

@@:	mov	ax,3100h	;KEEP with status 0 (OK)
	mov	cl,4
	lea	dx,end_resident_code[0Fh]
	shr	dx,cl		;convert resident code length to para count
	int	21h
	
welcome_msg	db "Auxiliary stack provider for int 10h installed.",0Dh,0Ah
		db "Intercept counter located at ",'$'
already_inst	db "Auxiliary stack provider already installed.",0Dh,0Ah,'$'


; Print ASCII character
; In:	AL
; Out:	Nothing
; Kill: AX, CL, DL
;
prtch	proc	near
	mov	dl, al
	mov	ah, 2		; console output
	int	21h
	ret
prtch	endp


; Print hex nibble
; In:	AL (low nibble)
; Out:	Nothing
; Kill: AX, CL, DL
;
prtxn	proc	near
	cmp	al, 10
	jb	not_asc
	add	al, 'A' - '0' - 10
not_asc:
	add	al, '0'
	call	prtch
	ret
prtxn	endp


; Print hex byte
; In:	AL
; Out:	Nothing
; Kill: AX, CL, DX
;
prtxb	proc	near
	mov	dh, al
	mov	cl, 4
	shr	al, cl
	call	prtxn
	mov	al, dh
	and	al, 0fh
	call	prtxn
	ret
prtxb	endp


; Print hex word
; In:	AX
; Out:	Nothing
; Kill: AX, CL, DL
;
prtxw	proc	near
	push	ax
	xchg	al, ah
	call	prtxb
	pop	ax
	call	prtxb
	ret
prtxw	endp

end	start
