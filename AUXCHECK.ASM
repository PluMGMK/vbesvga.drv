; Assemble as a binary file, should be possible on any platform
;	e.g. jwasm -bin AUXCHECK.ASM
; then rename auxcheck.bin to auxcheck.com

	.8086
	.model	tiny

; A little program that simulates int 10h calls from Windows logo code to
; determine whether or not AUXSTACK is needed. It prints a message and
; sets the errorlevel to 1 to indicate AUXSTACK needed, or 0 otherwise.

; this is the amount of stack (in bytes) provided in the logo takedown code:
LOGO_STACK_SIZE	equ 0A8h
; and this is the amount of stack (in bytes) needed for VBE int 10h:
FULL_STACK_SIZE	equ 400h

	.code
	org	100h

start:	; first set our stack pointer
	lea	ax,stack_top_ours
	cmp	sp,ax
	jnb	@F

	; if DOS loaded us with SP smaller than what we need,
	; that means that's all the memory we have, which isn't
	; enough to do this check safely!
	lea	dx,badmem
	mov	ah,9		;output string to stdout
	int	21h

	; exit with status 2 to indicate... God knows what...
	mov	ax,4C02h
	int	21h

@@:	mov	sp,ax
	; start going through the sentinel values
	mov	cx,NUM_SENTINEL_VALS
	lea	si,sentinel_vals
@@:	; load sentinel value and do modeset
	lodsw
	call	modeset_check
	loope	@B

	; here, if ZF is set, then all sentinel values were OK;
	; otherwise the VBIOS used too much stack!
	je	@@all_good

	; tell the user they need AUXSTACK
	lea	dx,auxneeded
	mov	ah,9		;output string to stdout
	int	21h

	; exit with status 1 to indicate it's needed
	mov	ax,4C01h
	int	21h

@@all_good:
	; tell the user they don't need AUXSTACK
	lea	dx,notneeded
	mov	ah,9		;output string to stdout
	int	21h

	; exit with status 0 to indicate it's not needed
	mov	ax,4C00h
	int	21h
	
badmem		db "Insufficent memory to setup stack sentinel!",0Dh,0Ah,'$'
notneeded	db "Your VBIOS did NOT trash the stack sentinel, so you don't need AUXSTACK.COM :)",0Dh,0Ah,'$'
auxneeded	db "Your VBIOS trashed the stack sentinel, so you NEED to load AUXSTACK.COM",0Dh,0Ah
		db "IF you intend to run Windows in Standard Mode and launch DOS prompt(s)!",0Dh,0Ah,'$'

; try a few different sentinel values to make sure we catch it...
sentinel_vals	dw 0,0AA55h,055AAh,-1
NUM_SENTINEL_VALS equ ($-sentinel_vals) SHR 1

; modeset_check - reset text mode and check the sentinel value
; Entry: AX = sentinel value to use
; Exit:  ZF set if sentinel matches, clear if it's been trashed
modeset_check	proc near
	mov	[stack_sentinel],ax
	push	ax

	mov	ax,3		;set text mode
	int	10h

	pop	ax
	cmp	[stack_sentinel],ax
	ret
modeset_check	endp

.data?
	align	2
stack_base	label word
	; provide a total of 1 kiB of stack, as required for VBE int 10h
	db	(FULL_STACK_SIZE - LOGO_STACK_SIZE) dup (?)
	; and put a sentinel in the middle of it so we can check how much
	; stack the BIOS uses!
stack_sentinel	label word
	db	LOGO_STACK_SIZE dup (?)
stack_top_int	label word
	; an extra DWORD needed for our own stack use (calling functions)
	dd	?
stack_top_ours	label word

end	start
