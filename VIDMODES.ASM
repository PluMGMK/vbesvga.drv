; Assemble as a binary file, should be possible on any platform
;	e.g. jwasm -bin vidmodes.asm
; then rename vidmodes.bin to vidmodes.com

.model tiny
.8086

.code
org	100h
getvendor:
	mov	ax,4F00h	; get SuperVGA info
	lea	di,sig
	int	10h
	cmp	al,4Fh
	jne	@@failure

	.386	; if we have a VESA bios, we must have a 386!
	cmp	dword ptr [sig],"ASEV"
	jne	@@failure

	mov	ah,9		; write to stdout
	lea	dx,card
	int	21h

	mov	ah,9		; write to stdout
	lea	dx,newline
	int	21h

	; FIXME: this int2F service isn't implemented in Dosbox!
	lds	si,[lpVendr]
	mov	ax,1225h	; get length of ASCIZ string
	int	2Fh

	mov	ah,40h		; WRITE
	mov	bx,1		; stdout
	; CX set from above
	dec	cx
	mov	dx,si
	int	21h

	; Write a space
	mov	ah,2		; write character to stdout
	mov	dl,' '
	int	21h

	; FIXME: this int2F service isn't implemented in Dosbox!
	lds	si,cs:[lpProd]
	mov	ax,1225h	; get length of ASCIZ string
	int	2Fh

	mov	ah,40h		; WRITE
	mov	bx,1		; stdout
	; CX set from above
	dec	cx
	mov	dx,si
	int	21h

	; Write a space
	mov	ah,2		; write character to stdout
	mov	dl,' '
	int	21h

	; FIXME: this int2F service isn't implemented in Dosbox!
	lds	si,cs:[lpPrev]
	mov	ax,1225h	; get length of ASCIZ string
	int	2Fh

	mov	ah,40h		; WRITE
	mov	bx,1		; stdout
	; CX set from above
	dec	cx
	mov	dx,si
	int	21h

	push	cs
	pop	ds		; back to tiny model...

	mov	ah,9		; write to stdout
	lea	dx,newline
	int	21h

	mov	ah,9		; write to stdout
	lea	dx,modes
	int	21h

	lfs	si,[lpModes]
@@next:
	lods	word ptr fs:[si]
	cmp	ax,-1
	je	@@done

	mov	cx,ax
	mov	ax,4F01h	; SVGA mode info
	lea	di,[wAttrs]
	int	10h
	cmp	ax,4Fh		; check for success
	jne	@@next

	; Check if supported by current hardware...
	bt	[wAttrs],0
	jnc	@@next
	; ... and if it's actually a graphical mode
	bt	[wAttrs],4
	jnc	@@next

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
	mov	ah,9		; write to stdout
	lea	dx,newline
	int	21h

	jmp	@@next

@@done:
	mov	ax,4C00h	; EXIT with success
	int	21h

@@failure:
	mov	ax,4C01h	; EXIT with failure
	int	21h


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

bRMask	db ?
bRPos	db ?
bGMask	db ?
bGPos	db ?
bBMask	db ?
bBPos	db ?
bRsMask	db ?
bRsPos	db ?
bDCAttr	db ?

pFBuf	dd ?
dOSoff	dd ?
wOSsize	dw ?
	db 206 dup (?)

end	getvendor
