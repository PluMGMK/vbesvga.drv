; Assemble as a binary file, should be possible on any platform
;	e.g. jwasm -bin VIDMODES.ASM
; then rename VIDMODES.BIN to VIDMODES.COM

.model tiny
.8086

LAST_RESORT_MODE	= 13h

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

; Detailed Timing Description
DTD	struc
pixclock_10kHz	dw ?	; pixel clock in 10-kHz units
			; NOTE: RBIL and OSDev wiki both claim that this
			; is two bytes, the first being the horizontal
			; rate in kHz and the second being the vertical
			; rate in Hz - but I can't find any evidence that
			; this was ever the case!
horizpixels_low	db ?	; width in pixels
horizblnk_low	db ?	; blanking pixels
horiz_high	db ?	; each nibble is high bits of previous two numbers
vertlines_low	db ?	; height scanlines
vertblnk_low	db ?	; blanking scanlines
vert_high	db ?	; each nibble is high bits of previous two numbers
horizporch_low	db ?
horizsync_low	db ?
vert_low	db ?	; nibbles are low bits of vertical porch and sync
porch_sync_high	db ?	; two highest bits of each of four previous numbers!
horiz_size_mmlo	db ?	; width in millimetres
vert_size_mmlo	db ?	; height in millimetres
size_mmhi	db ?	; each nibble is high bits of previous two numbers
horiz_border	db ?
vert_border	db ?
display_type	db ?
DTD	ends

; Display Descriptor Tag values
TAG_DUMMY	=  10h
TAG_ESTTIMINGS	= 0F7h	; third set of established timings
TAG_CVT3BYTE	= 0F8h
TAG_DCMDATA	= 0F9h
TAG_STDTIMINGS	= 0FAh
TAG_COLOURPTS	= 0FBh
TAG_PRODNAME	= 0FCh
TAG_RANGELIMS	= 0FDh
TAG_ASCII	= 0FEh
TAG_SERIALNO	= 0FFh

DspDesc	struc
resd0	dw ?	; zero
resd2	db ?	; zero
tag	db ?	; see TAG_*
rlimitf	db ?	; Display Range Limits Offsets: FLAGS
descdat	db 13 dup (?)
DspDesc	ends

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

	cmp	[vesaver],200h	; VBE 2.00 or later?
	jnb	@F

	; on VBE 1.x, we only have the "OEM name" available
	lds	si,[lpOEM]
	jmp	@@print_oem_str

@@:	lds	si,[lpVendr]
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
@@print_oem_str:
	call	prtz

	push	cs
	pop	ds		; back to tiny model...

	mov	ah,9		; write to stdout
	lea	dx,newline
	int	21h

	; Next query the monitor
	mov	ah,9		; write to stdout
	lea	dx,newline
	int	21h
	mov	ah,9		; write to stdout
	lea	dx,screen
	int	21h
	mov	ah,9		; write to stdout
	lea	dx,newline
	int	21h

	; first make sure VBE DDC functions are supported
	mov	ax,4F15h
	xor	bl,bl		; installation check
	int	10h
	cmp	ax,4Fh		; successful call?
	jne	@@EDID_call_fail

	mov	ax,4F15h	; get EDID info
	mov	bl,1
	xor	cx,cx
	mov	dx,cx
	lea	di,edid_hdr
	int	10h
	cmp	ax,4Fh		; successful call?
	jne	@@EDID_call_fail

	mov	al,0FFh		; check for valid header block
	mov	ah,[di]
	cmp	ah,al		; first byte should be 0 or FFh
	je	@F
	test	ah,ah
	jnz	@@EDID_bad_header
@@:	; bytes 1-6 should be FFh
	inc	di
	mov	cx,6
	cld
	repe	scasb
	jne	@@EDID_bad_header
	; last byte should be same as first
	mov	al,ah
	scasb
	jne	@@EDID_bad_header

	; now check the checksum - the full structure should sum to zero
	xor	ah,ah
	lea	cx,edid_checksum[1]
	lea	si,edid_hdr[0]
	sub	cx,si
@@:	lods	byte ptr [si]
	add	ah,al
	loop	@B
	; AH should now be zero, and ZF should be set
	jnz	@@EDID_bad_checksum

	; we have good EDID data: print as much info as we can
	; about the manufacturer / model
	mov	ah,2		; write character to stdout
	; start with the three-letter manufacturer name
	mov	bx,[id_mfg_name]
	mov	dx,bx
	mov	cl,10
	shr	dx,cl		; bits 14-10 = first letter
	and	dl,1Fh
	or	dl,40h		; 1 --> 'A', 2 --> 'B', etc.
	int	21h
	mov	dx,bx
	mov	cl,5
	shr	dx,cl		; bits 9-5 = second letter
	and	dl,1Fh
	or	dl,40h		; 1 --> 'A', 2 --> 'B', etc.
	int	21h
	mov	dx,bx
	and	dl,1Fh
	or	dl,40h		; 1 --> 'A', 2 --> 'B', etc.
	int	21h
	mov	dl,' '		; space before model number
	int	21h

	; check if there's a textual model number
	lea	si,desc0
@@:	cmp	[si].DspDesc.resd0,0	; if first word is zero, could be text
	jne	@@EDID_check_next_desc
	cmp	[si].DspDesc.resd2,0	; if third byte is also zero, it's text
	jne	@@EDID_check_next_desc
	cmp	[si].DspDesc.tag,TAG_PRODNAME
	je	@@EDID_print_prodname
@@EDID_check_next_desc:
	add	si,size DspDesc
	cmp	si,offset desc3
	jna	@B
	ja	@@EDID_prodname_done
@@EDID_print_prodname:
	lea	si,[si].DspDesc.descdat
	inc	si		; skip initial zero
	call	prtz
@@EDID_prodname_done:

	; now print the physical size in centimetres
	mov	ah,9		; write to stdout
	lea	dx,scrsize
	int	21h
	xor	ah,ah
	mov	al,[horiz_size_cm]
	call	prtdw
	mov	ah,9		; write to stdout
	lea	dx,cm_x
	int	21h
	xor	ah,ah
	mov	al,[vert_size_cm]
	call	prtdw
	mov	ah,9		; write to stdout
	lea	dx,cm_y
	int	21h

	; finally print the preferred resolution, from the first DTD,
	; just like VBESVGA.DRV itself does (there are other ways, but
	; the only one helpful to users of this program is the one that
	; matches the behaviour of the driver itself!)
	cmp	[desc0.pixclock_10kHz],0
	jz	@@EDID_no_prefres

	mov	al,[desc0.horizpixels_low]
	mov	ah,[desc0.horiz_high]
	mov	cl,4
	shr	ah,cl	; upper nibble
	mov	[wcheck],ax
	call	prtdw
	mov	ah,2		; write character to stdout
	mov	dl,'*'
	int	21h
	mov	al,[desc0.vertlines_low]
	mov	ah,[desc0.vert_high]
	mov	cl,4
	shr	ah,cl	; upper nibble
	mov	[hcheck],ax
	call	prtdw

	; print the physical size *of this specific mode* in millimetres
	; (confusing, I know...)
	mov	ah,9		; write to stdout
	lea	dx,scrsize
	int	21h
	mov	al,[desc0.horiz_size_mmlo]
	mov	bx,word ptr [desc0.vert_size_mmlo]
	mov	ah,bh
	; extract the upper nibble of size_mmhi to get the upper byte
	; of the width...
	mov	cl,4
	shr	ah,cl
	; and the lower nibble of size_mmhi to get the upper byte of
	; the height - confused yet?
	and	bh,0Fh
	call	prtdw		; print width
	mov	ah,9		; write to stdout
	lea	dx,mm_x
	int	21h
	mov	ax,bx
	call	prtdw		; print height
	mov	ah,9		; write to stdout
	lea	dx,mm_y
	int	21h
	jmp	@@EDID_all_done

@@EDID_call_fail:
	lea	dx,ef_call
	jmp	@@EDID_failure_message
@@EDID_bad_header:
	lea	dx,ef_bhdr
	jmp	@@EDID_failure_message
@@EDID_bad_checksum:
	lea	dx,ef_bchk
	jmp	@@EDID_failure_message
@@EDID_no_prefres:
	lea	dx,ef_pres
@@EDID_failure_message:
	mov	ah,9		; write to stdout
	int	21h

@@EDID_all_done:
	; parse the command line
	xor	ch,ch
	mov	cl,ds:[80h]	; length of cmdtail
	mov	di,81h		; address of cmdtail
@@find_next_switch:
	mov	al,'/'		; search for switches
	repne	scasb
	jcxz	@@cmdtail_done

	; found a switch
	mov	si,di
	lodsb			; get the name of the switch
	mov	di,si		; we've moved to next character!
	or	al,' '		; force lowercase

	lea	bx,wcheck
	cmp	al,'w'
	je	@F
	lea	bx,hcheck
	cmp	al,'h'
	je	@F
	lea	bx,dcheck
	cmp	al,'d'
	je	@F
	loop	@@find_next_switch
	jmp	@@cmdtail_done	; if loop terminates, we're done

@@:	; so we're querying a user-specified mode, rather than
	; the default - adjust our output to reflect this!
	cmp	byte ptr [fault],'f'
	jne	@F

	push	si
	push	di
	push	cx
	lea	si,sired
	lea	di,fault
	mov	cx,SIRED_FAULT_LEN
	rep	movsb
	pop	cx
	pop	di
	pop	si

@@:	; next thing to do is parse a number
	xor	bp,bp		; accumulate the number in BP
@@:	lodsb
	cmp	al,'0'
	jb	@F
	cmp	al,'9'
	ja	@F
	; AL contains a digit - convert to a number in AX
	sub	al,'0'
	xor	ah,ah
	xchg	bp,ax
	mov	dx,10
	mul	dx		; multiply previous number by 10
	add	bp,ax		; and accumulate
	loop	@B
@@:	; number is finished, store it
	mov	[bx],bp
	jcxz	@@cmdtail_done
	; SI points beyond the "next" character (the one that isn't a digit),
	; so rewind by one position when checking the next switch!
	lea	di,[si-1]
	inc	cl
	jmp	@@find_next_switch

@@cmdtail_done:
	mov	ah,9		; write to stdout
	lea	dx,modes
	int	21h

	mov	[total_found],0
	lds	si,[lpModes]
@@next:
	lodsw
	cmp	ax,-1
	jne	@F
	; if we're out of modes, maybe we need to check the last resort?
	cmp	cs:[score],0
	; if we've a perfect match, then there's no need
	jz	@@done

	cmp	cs:[lastresortchecked],0
	jnz	@@done

	; we know all the checks will pass, so go straight to score calc
	push	ds
	push	cs
	pop	ds		; back to tiny model...

	mov	[curmode],LAST_RESORT_MODE
	mov	[wWidth],320
	mov	[wHeight],200
	mov	[cur_sigdepth],8

	; this will ensure we don't loop back around here
	mov	[lastresortchecked],2
	jmp	@@check_score

@@:	; Are we checking the last resort mode as part of the list?
	; (e.g. with SeaBIOS)
	cmp	ax,LAST_RESORT_MODE
	jne	@F
	mov	[lastresortchecked],1

@@:	mov	cx,ax
	mov	ax,4F01h	; SVGA mode info
	lea	di,[wAttrs]
	int	10h
	cmp	ax,4Fh		; check for success
	jne	@@next

	mov	ax,cs:[wAttrs]
	; Check if supported by current hardware...
	test	al,VESA_ATTR_HWSUPPORT
	jz	@@next
	; ... and if it's actually a graphical mode
	test	al,VESA_ATTR_GRAPHICS
	jz	@@next
	; Is it colour?
	test	al,VESA_ATTR_COLOUR
	jz	@@next

	push	ds
	push	cs
	pop	ds		; back to tiny model...

	; Write the mode number
	mov	ax,cx
	mov	[curmode],ax
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
	mov	[cur_sigdepth],bl
	cmp	dx,offset mpacked
	je	@@check_depth

	; If direct, we need to calculate total & significant depths
	cmp	dx,offset mdirect
	jne	@@next_mode	; otherwise, we have no more info to offer

	; Significant depth = red + green + blue
	xor	bh,bh
	mov	bl,[bRSize]
	add	bl,[bGSize]
	add	bl,[bBSize]
	mov	[cur_sigdepth],bl
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
	jz	@F
	mov	ah,9		; write to stdout
	lea	dx,nondiv
	int	21h
	jmp	@@next_mode

@@:	; now check the attributes and window attributes
	mov	bx,[wAttrs]
	test	bl,VESA_ATTR_LINEAR
	jz	@F
	mov	ah,9		; write to stdout
	lea	dx,linear
	int	21h
	
@@:	test	bl,VESA_ATTR_NOBANKSWITCH
	jnz	@@check_score	; no windows to check

	mov	bl,[bWinA]
	test	bl,VESA_WINATTR_EXISTS
	jz	@@check_score

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
	jne	@@invalid_window

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
	jbe	@F

	mov	ah,9		; write to stdout
	lea	dx,toobig
	int	21h
	jmp	short @@invalid_window

@@:	; announce the granularity
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
	jz	@F

	mov	ah,9		; write to stdout
	lea	dx,nonint
	int	21h
	jmp	short @@invalid_window

@@:	; Check 4: is the window size either 64k or an integer multiple of
	; the memory width?
	mov	ax,bx
	cmp	ax,64
	je	@@check_score
	; here we know we have WinSize < 64k, since we already discounted 
	; > 64k in Check 2
	mov	cl,10
	shl	ax,cl		; convert kiB to bytes
	cwd
	div	[wPitch]
	test	dx,dx		; check remainder
	jz	@@check_score
	mov	ah,9		; write to stdout
	lea	dx,nonints
	int	21h

@@invalid_window:
	; check again if it's linear-addressable
	mov	bx,[wAttrs]
	test	bl,VESA_ATTR_LINEAR
	; if not, then it's not usable at all
	jz	@@next_mode

@@check_score:
	; check how well this mode matches the default / desired one
	mov	al,[cur_sigdepth]
	sub	al,[dcheck]
	jns	@F
	neg	al	; ensure positive
@@:	cbw
	mov	dx,ax	; track score

	mov	ax,[wWidth]
	sub	ax,[wcheck]
	jns	@F
	neg	ax	; ensure positive
@@:	add	dx,ax

	mov	ax,[wHeight]
	sub	ax,[hcheck]
	jns	@F
	neg	ax	; ensure positive
@@:	add	dx,ax

	cmp	dx,[score]
	jnb	@@next_mode
	; if it's better than any other, then update...
	mov	[score],dx
	mov	ax,[curmode]
	mov	[bstmode],ax

	; if it's a _perfect_ match, then change the message!
	test	dx,dx
	jnz	@@next_mode

	push	si
	push	di
	push	cx
	lea	si,perfec
	lea	di,closes
	mov	cx,PERFEC_CLOSES_LEN
	rep	movsb
	pop	cx
	pop	di
	pop	si

@@next_mode:
	; have we already reached the end of the list?
	cmp	[lastresortchecked],2
	jae	@@done

	mov	ah,9		; write to stdout
	lea	dx,newline
	int	21h

	pop	ds
	inc	cs:[total_found]
	jmp	@@next

@@done:
	; restore our own data segment
	push	cs
	pop	ds

	; indicate which mode VBESVGA.DRV will try to boot with
	mov	ah,9		; write to stdout
	lea	dx,closest
	int	21h

	; state which mode we checked
	mov	ax,[wcheck]
	call	prtdw
	mov	ah,2		; write character to stdout
	mov	dl,'*'
	int	21h

	mov	ax,[hcheck]
	call	prtdw
	mov	ah,2		; write character to stdout
	mov	dl,'*'
	int	21h

	mov	al,[dcheck]
	cbw
	call	prtdw

	; print the mode number
	mov	ah,9		; write to stdout
	lea	dx,colon
	int	21h

	mov	ax,[bstmode]
	cmp	ax,LAST_RESORT_MODE
	jne	@F
	cmp	[lastresortchecked],2
	jb	@F

	; if we ended up going to the last resort, and it wasn't
	; on the list, then print its name instead of its number
	mov	ah,9		; write to stdout
	lea	dx,lrname
	int	21h
	jmp	short @@mode_printed

@@:	call	prtxw

@@mode_printed:
	mov	ah,9		; write to stdout
	lea	dx,check
	int	21h

	; print version and total modes found
	lea	dx,verstr
	int	21h
	mov	ax,[total_found]
	call	prtdw

	mov	ax,4C00h	; EXIT with success
	cmp	[score],1
	cmc			; CF := 1 if score >= 1 (i.e. imperfect match)
	rcl	al,1		; AL := 1 (failure) if imperfect match
	int	21h

@@failure:
	mov	ah,9		; write to stdout
	lea	dx,failure
	int	21h
	lea	dx,newline
	int	21h

	mov	ax,4C02h	; EXIT with failure (distinct from "bad mode" above)
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

.data
failure	db "No SVGA BIOS - VBESVGA.DRV will attempt to boot in "
lrname	db "MCGA256 mode (aka 13h)","$"
card	db "Your card"
colon	db ": ","$"
screen	db "Your monitor: ","$"
scrsize	db 0Dh,0Ah,"- Physical size: ","$"
cm_x	db " cm * ","$"
cm_y	db " cm",0Dh,0Ah	; runs onto next string...
prefres	db "- Preferred resolution: ","$"
mm_x	db " mm * ","$"
mm_y	db " mm"
newline	db 0Dh,0Ah,"$"
modes	db 0Dh,0Ah,"Available VBE video modes:",0Dh,0Ah,"$"
nondiv	db " (not byte-aligned => NG for VBESVGA.DRV)","$"
linear	db ", linOK","$"
wina	db ", winA@","$"
; these window error messages are very long and will wrap across lines,
; but hopefully not many people will ever have a reason to see them!
toobig	db ">64k => NG for VBESVGA.DRV",'$'
nonint	db " = non-integer ratio => NG for VBESVGA.DRV",'$'
nonints	db "(not 64k or integer multiple of scanline pitch => NG for VBESVGA.DRV)","$"
closest	db 0Dh,0Ah
closes	db "Closest usable match for de"
fault	db "fault mode ","$"
check	db 0Dh,0Ah, "VBESVGA.DRV will attempt to boot in that mode."
	db 0Dh,0Ah,0Dh,0Ah
	db "To check another mode, use /w, /h and /d switches",0Dh,0Ah
	db "to specify desired width / height / depth - e.g.:",0Dh,0Ah
	db 9,"vidmodes/w800/h600/d16",0Dh,0Ah,"$"

; five characters to change "default" to "desired" above
sired	db "sired"
SIRED_FAULT_LEN	equ $-sired
; six characters to change "Closest" to "Perfect" above
perfec	db "Perfec"
PERFEC_CLOSES_LEN equ $-perfec

; EDID failure messages
ef_call	db "[VBIOS failed to return EDID data]",0Dh,0Ah,"$"
ef_bhdr	db "[Invalid EDID header]",0Dh,0Ah,"$"
ef_bchk	db "[EDID data checksum failure]",0Dh,0Ah,"$"
ef_pres	db "[Preferred resolution not specified in first EDID DTD]",0Dh,0Ah,"$"

; version string
verstr	db 0Dh,0Ah,"VIDMODES.COM from "
ifdef	VIDMODES_COMMIT
	db "Git commit ",VIDMODES_COMMIT
else
	db "uncontrolled debug build"
endif
; runs into this one
	db 0Dh,0Ah,"Total modes found: ","$"

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

; window attribute descriptions
winattrs dw invalid,ronly,wonly,rw
invalid	db " (invalid, NG for VBESVGA.DRV)",'$'
ronly	db " (read-only, NG for VBESVGA.DRV)",'$'
wonly	db " (write-only, NG for VBESVGA.DRV)"
; read-write is the default, so don't print anything
rw	db '$'

align	2
; track the best score of any mode enumerated
score	dw -1			; start at worst possible value
bstmode	dw LAST_RESORT_MODE	; mode which had that score
curmode	dw -1			; current mode we're checking

; specific mode to check for when determining if driver will boot
; (1024*768*24 is the default, width/height will be overridden by EDID)
wcheck	dw 1024
hcheck	dw 768
dcheck	db 24

; checked the last resort mode yet?
; 1 = it appeared in the list
; 2 = we're checking it at the end of the list
lastresortchecked db 0

align	2
; VBE card info
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

; Monitor info
edid_hdr	db 8 dup (?)
; Vendor & Product Identification
id_mfg_name	dw ?
id_prod_code	dw ?
id_serial	dd ?
mfg_week	db ?	; or FFh to indicate model year
mfg_year	db ?	; or model year
; EDID Structure Version & Revision
edid_ver	db ?
edid_rev	db ?
; Basic Display Parameters & Features
vid_input_def	db ?
horiz_size_cm	db ?	; physical monitor width in centimetres
vert_size_cm	db ?	; physical monitor height in centimetres
gamma		db ?
features	db ?
; Colour Characteristics
rg_low_bits	db ?	; Red / Green
bw_low_bits	db ?	; Blue / White
rx_high_bits	db ?	; Red-x
ry_high_bits	db ?	; Red-y
gx_high_bits	db ?	; Green-x
gy_high_bits	db ?	; Green-y
bx_high_bits	db ?	; Blue-x
by_high_bits	db ?	; Blue-y
wx_high_bits	db ?	; White-x
wy_high_bits	db ?	; White-y
; Established Timings
est_timings	dw ?
oem_timings	db ?
; Standard Timings
std_timings	dw 8 dup (?)
; 18-Byte Data Blocks
desc0		DTD <?>	; if EDID >= 1.3, this HAS to be Preferred Timing Desc
desc1		DspDesc <?>
desc2		DspDesc <?>
desc3		DspDesc <?>
; Extension Block Count N
n_extblocks	db ?
; Checksum C
edid_checksum	db ?

total_found	dw ?

; current significant depth - for check
cur_sigdepth	db ?

end	getvendor
