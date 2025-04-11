; Assemble as a binary file, should be possible on any platform
;	e.g. jwasm -bin VIDMODES.ASM
; then rename VIDMODES.BIN to VIDMODES.COM

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

.code
org	100h
getvendor:
	mov	ax,4F00h	; get SuperVGA info
	lea	di,sig
	int	10h
	cmp	al,4Fh
	jne	@@failure

	cmp	word ptr sig[0],"EV"
	jne	@@failure
	cmp	word ptr sig[2],"AS"
	jne	@@failure

	mov	ah,9		; write to stdout
	lea	dx,card
	int	21h

	mov	ah,9		; write to stdout
	lea	dx,newline
	int	21h

	lds	si,[lpVendr]
	call	prtz

	; Write a space
	mov	ah,2		; write character to stdout
	mov	dl,' '
	int	21h

	lds	si,cs:[lpProd]
	call	prtz

	; Write a space
	mov	ah,2		; write character to stdout
	mov	dl,' '
	int	21h

	lds	si,cs:[lpPrev]
	call	prtz

	push	cs
	pop	ds		; back to tiny model...

	mov	ah,9		; write to stdout
	lea	dx,newline
	int	21h

	mov	ah,9		; write to stdout
	lea	dx,modes
	int	21h

	lds	si,[lpModes]
@@next:
	lodsw
	cmp	ax,-1
	je	@@done

	mov	cx,ax
	mov	ax,4F01h	; SVGA mode info
	lea	di,[wAttrs]
	int	10h
	cmp	ax,4Fh		; check for success
	jne	@@next

	push	ds
	push	cs
	pop	ds		; back to tiny model...

	mov	ax,[wAttrs]
	; Check if supported by current hardware...
	test	al,VESA_ATTR_HWSUPPORT
	jz	@@next
	; ... and if it's actually a graphical mode
	test	al,VESA_ATTR_GRAPHICS
	jz	@@next
	; Is it colour?
	test	al,VESA_ATTR_COLOUR
	jz	@@next

	; Write the mode number
	mov	ax,cx
	call	prtxw

	mov	ah,9		; write to stdout
	lea	dx,colon
	int	21h

	; Write the resolution
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
	jne	@@depth_checked	; otherwise, we have no more info to offer

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
	jz	@@depth_checked

	mov	ah,9		; write to stdout
	lea	dx,nondiv
	int	21h

@@depth_checked:
	mov	ah,9		; write to stdout
	lea	dx,newline
	int	21h

	pop	ds
	jmp	@@next

@@done:
	mov	ax,4C00h	; EXIT with success
	int	21h

@@failure:
	mov	ax,4C01h	; EXIT with failure
	int	21h

; Print ASCIZ string
; In:	DS:SI (string)
; Out:	SI points past end of string
; Kill: AX, DL
;
prtz	proc	near
	mov	ah,2		; write character to stdout
@@:	lodsb
	test	al,al
	jz	@F
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

.data
failure	db "No SVGA BIOS"
newline	db 0Dh,0Ah,"$"
card	db "Your card"
colon	db ": ","$"
modes	db 0Dh,0Ah,"Available modes:",0Dh,0Ah,"$"
nondiv	db " (not byte-aligned => NG for VBESVGA.DRV)","$"

; memory model descriptions
models	dw mtext,mcga,mhgc,mega,mpacked,mseq256,mdirect,myuv
mtext	db " Text (NG for VBESVGA.DRV)",'$'
mcga	db " CGA-type (NG for VBESVGA.DRV)",'$'
mhgc	db " Hercules-type (NG for VBESVGA.DRV)",'$'
mega	db " EGA-type (NG for VBESVGA.DRV)",'$'
mpacked	db " Packed-pixel",'$'
mseq256	db " Non-chain-4 packed-pixel (Mode-X-type, NG for VBESVGA.DRV)",'$'
mdirect	db " Direct-colour, ",'$'
myuv	db " YUV (NG for VBESVGA.DRV)",'$'

align	2
sig	db "VBE2"
.data?
vesaver	dw ?
lpOEM	dd ?
caps	dd ?
lpModes	dd ?
vidmem	dw ?
oemrev	dw ?
lpVendr	dd ?
lpProd	dd ?
lpPrev	dd ?
	dw ?
	dd ?
	db 216 dup (?)
	db 256 dup (?)

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

end	getvendor
