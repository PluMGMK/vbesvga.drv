; Assemble as a binary file, should be possible on any platform
;	e.g. jwasm -bin MODETEST.ASM
; then rename MODETEST.BIN to MODETEST.COM

.model tiny
.8086

; VESA Mode Attributes
VESA_ATTR_HWSUPPORT	= 0000000000000001b
VESA_ATTR_OPTINFO	= 0000000000000010b
VESA_ATTR_BIOS_OP	= 0000000000000100b
VESA_ATTR_COLOUR	= 0000000000001000b
VESA_ATTR_GRAPHICS	= 0000000000010000b
VESA_ATTR_NONVGA	= 0000000000100000b
VESA_ATTR_NOBANKSWITCH	= 0000000001000000b
VESA_ATTR_LINEAR	= 0000000010000000b
VESA_ATTR_DBLSCAN	= 0000000100000000b
VESA_ATTR_INTERLACED	= 0000001000000000b
VESA_ATTR_HWTRIPLEBUF	= 0000010000000000b
VESA_ATTR_HWSTEREO	= 0000100000000000b
VESA_ATTR_DUAL		= 0001000000000000b

; VESA Window Attributes
VESA_WINATTR_EXISTS	= 00000001b
VESA_WINATTR_READ	= 00000010b
VESA_WINATTR_WRITE	= 00000100b
; Shortcut for the only type of window VBESVGA.DRV knows how to use
VESA_WINATTR_NORMAL	= VESA_WINATTR_EXISTS+VESA_WINATTR_READ+VESA_WINATTR_WRITE

.code
org	100h
checkprocessor:
	; print version
	mov	ah,9		; write to stdout
	lea	dx,verstr
	int	21h

	; indicate processor generation in BP - start with 0 for 8086...
	xor	bp,bp

	; switch on the Nested Task (NT) flag and see how the CPU reacts...
	pushf	; save original flags
	pushf
	pop	ax
	or	ah,40h
	push	ax
	popf
	pushf
	pop	ax
	popf	; restore original flags

	; take a look at the modified flags
	; on 8086, NT is always on; on 286 in Real Mode, it's always off
	test	ah,40h
	jnz	@F
	mov	bp,2		; NT stayed off --> it's a 286, and we must be in Real Mode
	jmp	short @@realmode

@@:	; if NT is on, then it's either an 8086 (always on)
	; or a 386 (accepted switching it on), so check the
	; flag just above it.
	test	ah,80h		; always on on 8086, always off on 286/386
	jnz	@@realmode	; definitely an 8086

	mov	bp,3		; flag is off, but NT came on --> it's a 386
	.386
	smsw	ax
	bt	ax,0		; Protected Mode?
	jnc	@@realmode

	lea	dx,vm86
	jmp	@@failure

@@realmode:
	.8086
	; parse the mode given on the command line
	cld
	mov	si,81h		; cmdline in PSP
	xor	bx,bx		; accumulate mode number here
	mov	ch,bl		; cmdline length in PSP:
	mov	cl,byte ptr ds:[80h]
	test	cl,cl
	jz	@@print_usage

@@get_char:
	lodsb
	cmp	al,'A'
	jb	@@not_capital
	cmp	al,'F'
	ja	@@not_capital
	sub	al,'A'-0Ah
	jmp	short @@accum

@@not_capital:
	cmp	al,'a'
	jb	@@not_small
	cmp	al,'f'
	ja	@@not_small
	sub	al,'a'-0Ah
	jmp	short @@accum

@@not_small:
	cmp	al,'0'
	jb	@@not_digit
	cmp	al,'9'
	ja	@@not_digit
	sub	al,'0'
@@accum:
	; bitwise shift for 8086 compatibility - also lets us
	; check (via CF) if user gave us too many digits!
	shl	bx,1
	jc	@@print_usage
	shl	bx,1
	jc	@@print_usage
	shl	bx,1
	jc	@@print_usage
	shl	bx,1
	jc	@@print_usage
	or	bl,al
@@not_digit:
	loop	@@get_char

	; Write the mode number
	mov	ax,bx
	mov	si,ax
	call	prtxw

	mov	ah,9		; write to stdout
	lea	dx,colon
	int	21h

	; we have what looks like a mode number in SI,
	; go query it...
	mov	cx,si
	mov	ax,4F01h	; SVGA mode info
	lea	di,[wAttrs]
	int	10h
	cmp	ax,4Fh		; check for success
	je	@F

	lea	dx,failure
	jmp	@@failure

@@:	mov	ax,cs:[wAttrs]
	; Check if supported by current hardware...
	test	al,VESA_ATTR_HWSUPPORT
	jnz	@F

	lea	dx,nohwsup
	jmp	@@failure

@@:	; ... and if it's actually a graphical mode
	test	al,VESA_ATTR_GRAPHICS
	jnz	@F

	lea	dx,nograph
	jmp	@@failure

@@:	; Is it colour?
	test	al,VESA_ATTR_COLOUR
	jnz	@F

	lea	dx,mono
	jmp	@@failure

@@:	; Write the resolution
	mov	ax,[wWidth]
	call	prtdw
	mov	ah,2		; write character to stdout
	mov	dl,'*'
	int	21h

	mov	ax,[wHeight]
	call	prtdw
	mov	ah,2		; write character to stdout
	mov	dl,'*'
	int	21h

	mov	al,[bDepth]
	xor	ah,ah
	call	prtdw

	; Write the memory model
	xor	bh,bh
	mov	bl,[bModel]
	shl	bx,1
	mov	ah,9		; write to stdout
	mov	dx,models[bx]
	int	21h

	; If packed-pixel, we can check the depth's divisibility
	; by eight straight away
	mov	bl,[bDepth]
	cmp	dx,offset mpacked
	je	@@check_depth

	; If direct, we need to calculate total & significant depths
	cmp	dx,offset mdirect
	lea	dx,emptystr	; last message already printed
	jne	@@failure	; otherwise, we have no more info to offer

	; Significant depth = red + green + blue
	xor	bh,bh
	mov	bl,[bRSize]
	add	bl,[bGSize]
	add	bl,[bBSize]
	mov	ax,bx
	call	prtdw
	mov	ah,2		; write character to stdout
	mov	dl,'S'		; significant
	int	21h
	mov	dl,'/'
	int	21h

	; Total depth includes padding bits
	add	bl,[BRsSize]
	; Sometimes the firmware doesn't fill out the ADEPTH field, expecting
	; us to infer the padding from the advertised DEPTH. Check for this
	; by comparing the calculated total to the advertised depth, and pick
	; whichever is bigger.
	mov	al,[bDepth]
	cmp	bl,al
	jae	@F
	mov	bl,al
@@:	mov	ax,bx
	call	prtdw
	mov	ah,2		; write character to stdout
	mov	dl,'T'		; total
	int	21h

@@check_depth:
	test	bl,7
	lea	dx,nondiv
	jnz	@@failure

	mov	cl,3
	shr	bl,cl
	mov	[pxbytes],bl

	; check whether user wants linear or banked mode
	test	si,4000h	; linear mode flag
	jz	@@user_wants_banked

	mov	bx,[wAttrs]
	test	bl,VESA_ATTR_LINEAR
	lea	dx,nolin
	jz	@@failure
	mov	ah,9		; write to stdout
	lea	dx,linear
	int	21h

	; print framebuffer location
	mov	ax,word ptr pFBuf[2]
	mov	bl,ah		; need to check upper byte in a minute...
	call	prtxw
	mov	ax,word ptr pFBuf[0]
	call	prtxw

	; does our processor support this linear mode?
	cmp	bp,2
	lea	dx,need286
	; 8086 can't do linear modes
	jb	@@failure
	; 386 can always do linear modes
	ja	@F
	; 286 can only do linear modes with a 24-bit address
	test	bl,bl
	lea	dx,need386
	jnz	@@failure

@@:	jmp	@@await_keypress
	
@@user_wants_banked:
	test	bl,VESA_ATTR_NOBANKSWITCH
	lea	dx,nobank
	jnz	@@failure

	mov	bl,[bWinA]
	test	bl,VESA_WINATTR_EXISTS
	jz	@@failure

	; announce that the window exists, and where it is
	mov	ah,9		; write to stdout
	lea	dx,wina
	int	21h
	mov	ax,[wWinAseg]
	call	prtxw

	; give its attributes
	mov	ah,9		; write to stdout
	; address this table using bits 2-1 of the attrs
	xor	bh,bh
	mov	dx,winattrs[bx-VESA_WINATTR_EXISTS]
	int	21h
	; Check 1: is Window A read-write?
	cmp	bl,VESA_WINATTR_NORMAL
	lea	dx,emptystr	; last message already printed
	jne	@@failure

	; announce the size
	mov	ah,9		; write to stdout
	lea	dx,colon
	int	21h
	mov	ax,[wWinsize]
	mov	bx,ax
	call	prtdw
	mov	ah,2		; write character to stdout
	mov	dl,'k'		; kiB
	int	21h

	; Check 2: is the window size 64k or smaller?
	cmp	bx,64
	lea	dx,toobig
	ja	@@failure

	; announce the granularity
	; N.B. BP gets trashed here! BUT this is only for banked modes!
	mov	ah,2		; write character to stdout
	mov	dl,'/'
	int	21h
	mov	ax,[wWingran]
	mov	bp,ax
	call	prtdw
	mov	ah,2		; write character to stdout
	mov	dl,'k'		; kiB
	int	21h

	; Check 3: is the window size an integer multiple of the granularity?
	mov	ax,bx
	mov	dx,bp
	div	dl		; single-byte division to match VBESVGA itself
	test	ah,ah
	lea	dx,nonint
	jnz	@@failure

	; Check 4: is the window size either 64k or an integer multiple of
	; the memory width?
	mov	ax,bx
	cmp	ax,64
	je	@@await_keypress
	; here we know we have WinSize < 64k, since we already discounted 
	; > 64k in Check 2
	mov	cl,10
	shl	ax,cl		; convert kiB to bytes
	cwd
	div	[wPitch]
	test	dx,dx		; check remainder
	lea	dx,nonints
	jnz	@@failure

@@await_keypress:
	mov	ah,9		; write to stdout
	lea	dx,instruc
	int	21h
	mov	ah,7		; direct character input, no echo
	int	21h		; wait for char input...

	; if we're going into a direct-framebuffer mode, then we need
	; to write actual RGB colours to memory, so grab the palette
	cmp	[bModel],6	; direct colour
	jne	@@switch_mode

	; convert palette indices to RGB colours
	lea	di,colours
	mov	ch,16		; 16 colours in standard palette
@@:	xor	ax,ax
	mov	bx,ax
	xchg	al,[di]		; get palette index
	mov	dx,3C7h		; PEL address reg (read mode)
	out	dx,al
	mov	dl,0C9h		; PEL data reg

	in	al,dx		; red contribution
	mov	bx,word ptr [bRSize]
	call	colour_contrib
	in	al,dx		; green contribution
	mov	bx,word ptr [bGSize]
	call	colour_contrib
	in	al,dx		; blue contribution
	mov	bx,word ptr [bBSize]
	call	colour_contrib

	lea	di,[di+4]
	dec	ch
	jnz	@B

@@switch_mode:
	mov	ax,4F02h	; set SuperVGA mode
	mov	bx,si
	int	10h

	test	si,4000h	; linear mode?
	jz	@@fill_framebuffer

	; setup Protected Mode...
	.286p
	; we're not going to set up an IDT at all, so prevent interrupts...
	cli

	; fill in our own framebuffer and bank-switch pointers
	mov	[wWinAseg],(viddesc-gdt)
	mov	word ptr lpWinPos[0],offset bankemu
	mov	word ptr lpWinPos[2],(csdesc-gdt)

	; set bases for our selectors
	mov	ax,cs
	mov	[savedcs],ax
	mov	dl,ah
	mov	cl,4
	shl	ax,cl
	shr	dl,cl
	mov	[csdesc.segdesc.base_lo],ax
	mov	[dsdesc.segdesc.base_lo],ax
	mov	[csdesc.segdesc.base_3],dl
	mov	[dsdesc.segdesc.base_3],dl
	; and for the GDT itself
	add	ax,offset gdt
	adc	dl,0
	mov	[gdtbasl],ax
	mov	[gdtbash],dl

	; set the base for the framebuffer
	mov	ax,word ptr pFBuf[0]
	mov	dx,word ptr pFBuf[2]
	mov	[viddesc.segdesc.base_lo],ax
	mov	[viddesc.segdesc.base_3],dl
	mov	[viddesc.segdesc.base_4],dh

	; BP is still the processor generation here,
	; because we're not using a banked mode...
	cmp	bp,2
	ja	@F
	; on a 286, we need to do some additional setup for
	; returning to Real Mode...

	; set reset address in BDA
	push	es
	mov	ax,40h
	mov	es,ax
	lea	si,savedcs[-2]
	mov	di,67h		; offset of reset vector in BDA
	movsw
	movsw
	pop	es

	; tell CMOS to restart execution from there
	mov	al,8Fh		; leave NMI on, select register 0Fh
	out	70h,al		; select CMOS register 0Fh
	mov	al,0Ah		; reset jump to 40:67 pointer
	out	71h,al		; write to CMOS register

	; put three NULL words on the stack...
	xor	ax,ax
	push	ax
	push	ax
	push	ax
	; and load a NULL IDT, to give a nice clean, fast
	; triple-fault on the MOV CR0 instruction later!
	mov	bx,sp
	lidt	fword ptr [bx]
	lea	sp,[bx+6]

@@:	; OK, ready to load the GDT and switch!
	lgdt	fword ptr [gdtlim]
	smsw	ax
	or	al,1		; Protected Mode!
	lmsw	ax

	; far jmp to clear prefetch queue...
	db	0EAh
	dw	offset @F
	dw	(csdesc-gdt)
@@:	; now set data selectors
	mov	ax,(dsdesc-gdt)
	mov	ds,ax
	mov	es,ax
	mov	ss,ax
	mov	sp,sp		; SP is already OK

@@fill_framebuffer:
	.8086
	; set up to copy into framebuffer
	mov	es,[wWinAseg]
	xor	di,di
	mov	[curbank],di
	lea	si,colours
@@nextcolour:
	; each colour fills one sixteenth of the screen
	mov	bx,[wHeight]
	mov	cl,4
	shr	bx,cl
	mov	cx,bx
	; load the colour into DX:BX...
	lodsw
	mov	bx,ax
	lodsw
	mov	dx,ax
	; track bytes per pixel in AH
	mov	ah,[pxbytes]
@@colourloop:
	mov	bp,[wPitch]
@@lineloop:
	; store byte-by-byte, rinse and repeat
	; this code doesn't have to be super-efficient, since it's
	; a once-off to draw a still test card to the screen
	mov	al,bl
	stosb
	test	di,di
	jnz	@F
	call	next_bank
@@:	dec	bp
	jz	@@nextline
	cmp	ah,1
	jna	@@lineloop
	mov	al,bh
	stosb
	test	di,di
	jnz	@F
	call	next_bank
@@:	dec	bp
	jz	@@nextline
	cmp	ah,2
	jna	@@lineloop
	mov	al,dl
	stosb
	test	di,di
	jnz	@F
	call	next_bank
@@:	dec	bp
	jz	@@nextline
	cmp	ah,3
	jna	@@lineloop
	mov	al,dh
	stosb
	test	di,di
	jnz	@F
	call	next_bank
@@:	dec	bp
	jnz	@@lineloop
@@nextline:
	loop	@@colourloop
	; another colour to load?
	cmp	si,offset end_colours
	jb	@@nextcolour

	; back to tiny model
	mov	ax,ds
	mov	es,ax

	; are we in Protected Mode?
	cmp	ax,(dsdesc - gdt)
	jne	@@await_keypress_again

	.286p
	; set up for returning from PM if on a 286
	mov	[savedsp],sp

	; Now, on a 386 we can use CR0 to take us out of PM.
	; On a 286, this will triple-fault (invalid instruction 
	; plus invalid IDT), and jump to 40:67 on reset.
	.386p
	mov	eax,cr0
	and	al,NOT 1	; turn off PE
	mov	cr0,eax
	; far JMP to clear prefetch queue
	db	0EAh
	dw	offset @F
savedcs	dw	?

@@:	.286p
	; now restore the segment registers
	mov	ax,cs
	mov	ds,ax
	mov	es,ax
	mov	ss,ax
	mov	sp,[savedsp]

	; we're ready to receive interrupts again!
	sti

@@await_keypress_again:
	.8086
	mov	ah,7		; direct character input, no echo
	int	21h		; wait for char input...

	; back to text mode
	mov	ax,3
	int	10h
	ret			; back to int 20h in PSP! :3

@@print_usage:
	lea	dx,usage
@@failure:
	mov	ah,9		; write to stdout
	int	21h
	lea	dx,newline
	int	21h

	mov	ax,4C01h	; EXIT with failure
	int	21h

; Print ASCIZ (or LF-terminated) string
; In:	DS:SI (string)
; Out:	SI points past end of string
; Kill: AX, DL
;
prtz	proc	near
	mov	ah,2		; write character to stdout
@@:	lodsb
	test	al,al
	jz	@F
	cmp	al,0Ah		; LF terminator (needed for EDID)
	je	@F
	mov	dl,al
	int	21h
	jmp	@B
@@:	ret
prtz	endp

; Print hex nibble
; In:	AL (low nibble)
; Out:	Nothing
; Kill: AX, DL
;
prtxn	proc	near
	cmp	al, 10
	jb	not_asc
	add	al, 'A' - '0' - 10
not_asc:
	add	al, '0'
	mov	ah,2		; write character to stdout
	mov	dl,al
	int	21h
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


; Print decimal word
; In:	AX, ES==CS
; Out:	Nothing
; Kill: AX, CX, DX, DI
;
	dw 1	; protect from division by zero
pow10	dw 1,10,100,1000,10000
prtdw	proc	near
	cld
	lea	di,pow10
@@:	scasw
	jnb	@B
	sub	di,2
@@:	xor	dx,dx
	div	word ptr es:[di-2]
	sub	di,2
	; AL now contains the coefficient of the current power of ten
	mov	cx,dx	; save the remainder
	call	prtxn
	mov	ax,cx	; get the remainder back
	cmp	word ptr es:[di],1
	ja	@B
	ret
prtdw	endp


; Add single byte contribution to physical colour slot at DS:DI
; In:	AX = colour byte
;	BL = size of contribution in bits
;	BH = position of contribution in bits
; Out:	AX ORed into correct position at DS:DI
; Kill: AX, BX, CL
;
colour_contrib	proc	near
	mov	cl,2
	shl	al,cl		; convert 6-bit to 8-bit palette entry
	mov	cl,8
	sub	cl,bl
	shr	al,cl		; keep only significant bits
	mov	bl,bh
	mov	cl,3
	shr	bl,cl		; BL = byte offset of red contribution
	and	bh,111b		; BH = bit offset of red contribution
	mov	cl,bh
	shl	ax,cl		; AX = red contribution shifted left
	xor	bh,bh
	or	[bx+di],ax	; slot it in at correct byte
	ret
colour_contrib	endp


next_bank	proc	near
	push	dx
	push	bx
	push	ax

	xor	bx,bx		; set (BH=0) window A (BL=0)
	mov	dx,[curbank]
	inc	dx
	call	[lpWinPos]	; call far window positioning function
	mov	[curbank],dx

	pop	ax
	pop	bx
	pop	dx
	ret
next_bank	endp


; Protected-Mode "bank-switch" function to update the framebuf seg base
; Ignores BX, takes bank in DX, returns AX = 4Fh (success)
; ASSUMES DS POINTS AT US, AND ES AT FRAMEBUF!
bankemu	proc	far
	mov	ax,dx
	add	ax,word ptr pFBuf[2]	; upper word of framebuf base
	mov	[viddesc.base_3],al
	mov	[viddesc.base_4],ah
	mov	ax,es
	mov	es,ax			; flush selector cache
	mov	ax,4Fh			; indicate success
	ret
bankemu	endp

.data
vm86	db "Need to be in Real Mode, try rebooting into DOS without EMM386",10,13,'$'
colon	db ": ","$"
failure	db "VBE call to query this mode failed - either the mode doesn't exist",0Dh,0Ah
	db "or there is no SVGA BIOS at all!",'$'
nohwsup	db "Not supported by your hardware",'$'
nograph	db "Text mode",'$'
mono	db "Non-colour mode",'$'
nondiv	db " (not byte-aligned => NG for VBESVGA - aborting)","$"
linear	db ", linear framebuffer @ ","$"
nolin	db ", linear mode NOT supported but requested - aborting","$"
need286	db 0Dh,0Ah,"Linear mode requested but requires at least a 286 - aborting","$"
need386	db 0Dh,0Ah,"Framebuffer above 00FFFFFF requires at least a 386 - aborting","$"
nobank	db ", no winA, probably linear-only mode - aborting",0Dh,0Ah
	db "(add 4000 to mode number to try linear mode)",'$'
wina	db ", winA@","$"
; these window error messages are very long and will wrap across lines,
; but hopefully not many people will ever have a reason to see them!
toobig	db ">64k => NG for VBESVGA - aborting",'$'
nonint	db " = non-integer ratio => NG for VBESVGA - aborting",'$'
nonints	db "(not 64k or integer multiple of scanline pitch => NG for VBESVGA - aborting)","$"
; tell the user how to proceed
instruc	db 0Dh,0Ah
	db "Press any key to switch to this mode and draw a test card to the screen",0Dh,0Ah
	db "Then, press any key again to switch back to text mode and end the program",0Dh,0Ah,'$'
usage	db "Usage: MODETEST <modenum>",0Dh,0Ah
	db " where <modenum> is one of the modes found by VIDMODES.COM",0Dh,0Ah
	db "E.g.: MODETEST 01D4",0Dh,0Ah
	db " or, to check a linear mode, add 4000 to the number",0Dh,0Ah
	db "E.g.: MODETEST 42D4",0Dh,0Ah,'$' 
newline	db 0Dh,0Ah,"$"

; version string
verstr	db 0Dh,0Ah,"MODETEST.COM from "
ifdef	MODETEST_COMMIT
	db "Git commit ",MODETEST_COMMIT
else
	db "uncontrolled debug build"
endif
; runs into this one
	db 0Dh,0Ah,0Dh,0Ah,"$"

; memory model descriptions
models	dw mtext,mcga,mhgc,mega,mpacked,mseq256,mdirect,myuv
mtext	db " Text (NG for VBESVGA - aborting)",'$'
mcga	db " CGA-type (NG for VBESVGA - aborting)",'$'
mhgc	db " Hercules-type (NG for VBESVGA - aborting)",'$'
mega	db " EGA-type (NG for VBESVGA - aborting)",'$'
mpacked	db " Packed-pixel",'$'
mseq256	db " Non-chain-4 packed-pixel (Mode-X-type, NG for VBESVGA - aborting)",'$'
mdirect	db " Direct-colour, ",'$'
myuv	db " YUV (NG for VBESVGA - aborting)",'$'

; window attribute descriptions
winattrs dw invalid,ronly,wonly,rw
invalid	db " (invalid, NG for VBESVGA - aborting)",'$'
ronly	db " (read-only, NG for VBESVGA - aborting)",'$'
wonly	db " (write-only, NG for VBESVGA - aborting)"
; read-write is the default, so don't print anything
emptystr label byte
rw	db '$'

align	2
; GDT segment descriptor
segdesc	struct
lim_lo	dw ?	; low word of limit (the only word on 286)
base_lo	dw ?	; low word of base
base_3	db ?	; third byte of base (highest on 286)
access	db ?	; access byte
lim_fl	db ?	; high nibble of limit and flags nibble
base_4	db ?	; fourth byte of base (386 only)
segdesc	ends
; segment types:
CODE_SEG_ACCESS	equ 10011010b	; present, non-system, exec, readable
DATA_SEG_ACCESS	equ 10010010b	; present, non-system, writable

; our GDT selectors - "?"s to be filed in at runtime
gdt	label qword
nuldesc	dq	0
csdesc	segdesc	<0FFFFh,?,?,CODE_SEG_ACCESS,0,0>; our code seg
dsdesc	segdesc	<0FFFFh,?,?,DATA_SEG_ACCESS,0,0>; our data seg
viddesc	segdesc	<0FFFFh,?,?,DATA_SEG_ACCESS,0,?>; framebuffer window

gdtlim	dw	($ - gdt - 1)
gdtbasl	dw	?
gdtbash	db	?,0	; one byte to be set, highest byte always zero

; sixteen colours we will stick up on the screen as a test card
; (by default they are simply 0-F, rendered using a palette in packed-pixel mode)
colours	dd 0,1,2,3,4,5,6,7,8,9,0Ah,0Bh,0Ch,0Dh,0Eh,0Fh
end_colours label dword

.data?
pxbytes	db ?

align	2
; Mode info
wAttrs	dw ?
bWinA	db ?
bWinB	db ?
wWingran dw ?
wWinsize dw ?
wWinAseg dw ?
wWinBseg dw ?
lpWinPos dd ?
wPitch	dw ?
wWidth	dw ?
wHeight	dw ?
bCharW	db ?
bCharH	db ?
bPlanes	db ?
bDepth	db ?
bBanks	db ?
bModel	db ?
bBankSize db ?
bImgPgs	db ?
bResd	db ?

bRSize	db ?
bRPos	db ?
bGSize	db ?
bGPos	db ?
bBSize	db ?
bBPos	db ?
bRsSize	db ?
bRsPos	db ?
bDCAttr	db ?

pFBuf	dd ?
dOSoff	dd ?
wOSsize	dw ?
	db 206 dup (?)

; current bank
curbank	dw ?

; for returning from Protected Mode on 286
savedsp	dw ?

end	checkprocessor
