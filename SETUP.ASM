; Assemble as a binary file, should be possible on any platform
;	e.g. jwasm -bin SETUP.ASM
; then rename SETUP.BIN to SETUP.EXE

.model tiny
.8086

.code
; I, the original author of SETUP.EXE, do not own the tools listed in the
; build chain in README.md, so I cross-compile using jwasm -bin; while this
; could easily be changed to use the normal link path to make an exe image,
; I would no longer be able to build it myself.

; While I have a different version of MASM I'm not introducing a two-different
; versions build requirement into this project, so that's that.

; Note the project needs a completely bare MZ header anyway because of the way
; it constructs VBESVGA.EXE from SETUP.EXE in RAM. You could take that out but
; it just makes the code larger for no good reason.

; I am quite pleased the initial binary came out to less than 4K.
; Joshua Hudson <joshudson@gamil.com>

org	0E0h	; Data offsets are actually 0100h but MZ header is generated
mzheader:
setupexetaillen	equ	(_end - mzheader) AND 511
	db	"MZ"
	dw	(512 - setupexetaillen) AND 512 OR setupexetaillen	; number of bytes in last sector
	dw	(_end - mzheader + 511) / 512				; number of 512 byte sectors
	dw	0	; PIC (easy in tiny model)
	dw	2	; Size of header
	dw	0FFFh	; Uses 64KB; I'm too lazy to make it smaller
	dw	0FFFh	; If you're going to be running Windows you can spare it.
	dw	0	; See above
	dw	0FFF0h	; Initial SS
	dw	0	; Checksum - not used
	dw	0	; Initial IP
	dw	0	; Initial CS
	dw	0	; No relocation table
	dw	0	; Main exe
	db	"->H",0	; Overlay info (how to tell SETUP.EXE from VBESVGA.EXE at a glance)

_start:
	mov	[pathoff], 0FFFFh	; Putting in initialized data interferes with VBESVGA generation
env:
	; For some reason JWasm cannot assemble this instruction
	;mov	es, word ptr [2Ch]
	db	8Eh, 06h, 2Ch, 00h
	cmp	byte ptr es:[si], 0
	je	env_eot
	cmp	word ptr [es:si], "AP"
	jne	env_notpa
	cmp	word ptr [es:si + 2], "HT"
	jne	env_notpa
	cmp	byte ptr [es:si + 4], "="
	jne	env_notpa
	lea	ax, [si + 5]
	mov	[pathoff], ax
env_notpa:
	inc	si
	cmp	byte ptr [es:si], 0
	jne	env_notpa
	inc	si
	jmp	env
env_eot:
	inc	si
	lods	word ptr es:[si]
	cmp	ax, 1
	je	haveexepath
	lea	dx, [lowdos]
exit1msg:
	mov	ah, 9
	int	21h
exit1:
	mov	al, 1
	jmp	exit
lowdos	db	"DOS 3.0 required.", 13, 10, "$"
haveexepath:
	mov	[exeoff], si
	call	popvidmodes
	.386			; We now know we have a 386 (and we want large conditional jmp instructions)
	call	pathfromexepath
	lea	si, [systemini]
	call	stpcpy0
	lea	dx, [pname1]
	mov	ax, 3D00h
	int	21h
	jnc	haveexesystemini
noexesystemini:
	jmp	issetupexe
	jmp	exit1msg
noexesysteminimsg:
	db	"VBESVGA.EXE is for reconfiguration only; use SETUP.EXE to install.", 13, 10, "$"
haveexesystemini:
	mov	[hin], ax

	;*** VBESVGA.EXE displays the configuration screen ***
	;Load settings
	call	readfirstline
havesystemini_nextsection:
	test	si, si
	jz	havesystemini_eof
havesystemini_nextsection2:
	lea	di, [svbesvgalower]
	call	section_recognizer
	jz	havesystemini_vbesvga
	call	readnextline
	jmp	havesystemini_nextsection
havesystemini_vbesvga:
	call	readnextline
	test	si, si
	jz	havesystemini_eof
	call	any_section_recognizer
	je	havesystemini_nextsection2
	lea	di, [pwidthlower]
	call	assign_recognizer
	jne	@F
	call	silly_atoi
	mov	[_width], bx
	jmp	havesystemini_vbesvga
@@:	lea	di, [pheightlower]
	call	assign_recognizer
	jne	@F
	call	silly_atoi
	mov	[height], bx
	jmp	havesystemini_vbesvga
@@:	lea	di, [pdepthlower]
	call	assign_recognizer
	jne	@F
	call	silly_atoi
	mov	[depth], bx
	jmp	havesystemini_vbesvga
@@:	lea	di, [pdblbufferlower]
	call	assign_recognizer
	jne	@F
	call	silly_atoi
	mov	[refresh], bx
	jmp	havesystemini_vbesvga
@@:	lea	di, [pfontsz]
	call	assign_recognizer
	jne	@F
	call	silly_char
	mov	[fontsz], al
	jmp	havesystemini_vbesvga
@@:	lea	di, [ppmidlower]
	call	assign_recognizer
	jne	havesystemini_vbesvga
	call	silly_char
	cmp	al, "s"
	jne	@F
	cmp	byte ptr [si], "u"
	jne	@F
	mov	al, "u"
@@:	mov	[pmid], al
	jmp	havesystemini_vbesvga

havesystemini_eof:

	;*** Begin Configuration UI ***
drawscreenanew:
	mov	bx, 17h
	xor	dx, dx
@@:	mov	ah, 2
	int	10h
	mov	cx, 80
	mov	ax, 920h
	int	10h
	inc	dh
	cmp	dh, 25
	jb	@B
	lea	si, [configvbe]
	mov	dx, 1Ah
	call	drawstringat
	mov	dx, 0810h
	lea	si, [enterbase]
	call	drawstringat
	mov	dx, 0910h
	lea	si, [escbase]
	call	drawstringat
	mov	dx, 210h
	lea	si, [modebase]
	call	drawstringat
	lea	si, [dblbuffbase]
	mov	dx, 310h
	call	drawstringat
	lea	si, [fontsizebase]
	mov	dx, 410h
	call	drawstringat
	lea	si, [pmidbase]
	mov	dx, 510h
	call	drawstringat

drawscreen:
	lea	si, [default]
	cmp	[_width], 0
	je	@F
	lea	si, [_width]
	lea	di, [genln]
	push	di
	call	mode2text
	pop	si
@@:	mov	dx, 22Bh
	call	blankfield
	call	drawstringat
drawscreen2:
	lea	di, [genln]
	push	di
	mov	ax, [refresh]
	call	itoa
	mov	al, "$"
	stosb
	pop	si
	mov	dx, 32Bh
	call	blankfield
	call	drawstringat
	call	decodefontsize
	call	decodedefault
	mov	dx, 042Bh
	call	blankfield
	call	drawstringat
	call	decodepmid
	call	decodedefault
	mov	dx, 052Bh
	call	blankfield
	call	drawstringat
	
basecfgstate:
	mov	ah, 0
	int	16h
	cmp	al, "F"
	je	togglef
	cmp	al, "f"
	je	togglef
	cmp	al, "P"
	je	togglep
	cmp	al, "p"
	je	togglep
	cmp	al, "D"
	je	setrefresh
	cmp	al, "d"
	je	setrefresh
	cmp	al, "M"
	je	setmode
	cmp	al, "m"
	je	setmode
	cmp	al, 13
	je	exit_save
	cmp	al, 10
	je	exit_save
	cmp	al, 27
	je	exit_nosave
	cmp	al, 3
	je	exit_nosave
	cmp	al, "x"
	je	exit_nosave	; Panic button; x tends to work on messed-up scan codes
	cmp	al, "X"
	je	exit_nosave
	jmp	basecfgstate

togglef:
	mov	al, [fontsz]
	cmp	al, 's'
	je	toggleflarge
	cmp	al, 0
	je	togglefsmall
	mov	al, 0
toggleffinal:
	mov	[fontsz], al
	jmp	drawscreen
toggleflarge:
	mov	al, 'l'
	jmp	toggleffinal
togglefsmall:
	mov	al, 's'
	jmp	toggleffinal

togglep:
	mov	al, [pmid]
	cmp	al, 0
	je	togglepsanity
	cmp	al, 's'
	je	togglepnone
	cmp	al, 'n'
	je	togglepdisabled
	cmp	al, 'd'
	je	togglepsum
	mov	al, 0
togglepfinal:
	mov	[pmid], al
	jmp	drawscreen
togglepsanity:
	mov	al, 's'
	jmp	togglepfinal
togglepnone:
	mov	al, 'n'
	jmp	togglepfinal
togglepdisabled:
	mov	al, 'd'
	jmp	togglepfinal
togglepsum:
	mov	al, 'u'
	jmp	togglepfinal

setrefresh:
	mov	dx, 32Bh
	mov	ah, 2
	int	10h
	mov	bx, 70h
	mov	cx, 4
	mov	ax, 920h
	int	10h

setrefresh_value:
	mov	bp, [refresh]
setrefresh_draw:
	lea	di, [genln]
	mov	si, di
	mov	ax, bp
	call	itoa
	push	bp		; Some implementation destory BP for int10h due to bug
	mov	bh, 0
	mov	dx, 32Bh
@@:	mov	ah, 2
	int	10h
	lodsb
	mov	ah, 0Ah
	mov	cx, 1
	int	10h
	inc	dl
	cmp	si, di
	jb	@B
	push	dx
@@:	mov	bh, 0
	mov	ah, 2h
	int	10h
	mov	cx, 1
	mov	ax, 0A20h
	int	10h
	inc	dl
	cmp	dl, 2Fh
	jb	@B
	pop	dx
	mov	bh, 0
	mov	ah, 2
	int	10h
	pop	bp

setrefresh_key:
	mov	ah, 0
	int	16h
	cmp	al, "0"
	jb	@F
	cmp	al, "9"
	ja	@F
	jmp	setrefresh_digit
@@:	cmp	al, 8
	je	setrefresh_bksp
	cmp	al, 27
	je	setrefresh_esc
	cmp	al, "X"
	je	setrefresh_esc
	cmp	al, "x"
	je	setrefresh_esc
	cmp	al, 13
	je	setrefresh_set
	cmp	al, 10
	je	setrefresh_set
	jmp	setrefresh_key

setrefresh_digit:
	mov	bl, al
	mov	bh, 0
	sub	bl, "0"
	xchg	ax, bp
	mov	cx, 10
	mul	cx
	add	ax, bx
	cmp	ax, 255
	jbe	@F
	mov	ax, 255
@@:	xchg	ax, bp
	jmp	setrefresh_draw

setrefresh_bksp:
	xchg	ax, bp
	xor	dx, dx
	mov	cx, 10
	div	cx
	xchg	ax, bp
	jmp	setrefresh_draw

setrefresh_set:
	mov	[refresh], bp
setrefresh_esc:
	jmp	drawscreenanew

setmode:	; Select video mode from popup
	; Draws the popup
	mov	dx, 32Bh
	mov	bx, 70h
	mov	ah, 2
	int	10h
	mov	ax, 09DAh
	mov	cx, 1
	int	10h
	inc	dl
	mov	ah, 2
	int	10h
	mov	cx, 15
	mov	ax, 09C4h
	int	10h
	add	dl, cl
	mov	ah, 2
	int	10h
	mov	cl, 1
	mov	ax, 09BFh
	int	10h
	inc	dh
@@:	mov	dl, 2Bh
	mov	ah, 2
	int	10h
	mov	ax, 09B3h
	int	10h
	inc	dl
	mov	ah, 2
	int	10h
	mov	cl, 15
	mov	ax, 0920h
	int	10h
	add	dl, cl
	mov	ah, 2
	int	10h
	mov	cl, 1
	mov	ax, 09B3h
	int	10h
	inc	dh
	cmp	dh, 15
	jb	@B
	mov	dl, 2Bh
	mov	ah, 2
	int	10h
	mov	ax, 09C0h
	int	10h
	inc	dl
	mov	ah, 2
	int	10h
	mov	cl, 15
	mov	ax, 09C4h
	int	10h
	add	dl, cl
	mov	ah, 2
	int	10h
	mov	cl, 1
	mov	ax, 09D9h
	int	10h
	xor	bp, bp	; Base into
	
setmode_drawtext:
	lea	si, [modes + bp]
	push	bp			; Some INT10h implementations destroy BP
	mov	dx, 042Ch
	push	si
	lea	si, [default0]
	test	bp, bp
	jz	@F
	lea	si, [less]
@@:	call	drawstringat
	inc	dh
	pop	si
setmode_drawtextn:
	mov	dl, 2Ch
	cmp	word ptr [si], 0
	je	setmode_drawtextt
	lea	di, [genln]
	mov	al, dh
	add	al, "0" - 4
	stosb
	mov	al, ")"
	stosb
	mov	al, " "
	stosb
	push	si
	push	dx
	call	mode2text
	pop	dx
	lea	si, [genln]
	call	blankfield
	call	drawstringat
	pop	si
	inc	dh
	add	si, 6
	cmp	dh, 14
	jb	setmode_drawtextn
	mov	dl, 2Ch
	call	blankfield
	cmp	word ptr [si], 0
	je	setmode_drawtextend
	lea	si, [more]
	call	drawstringat
	jmp	setmode_drawtextend
setmode_drawtextt:	; No more groups of 9
	call	blankfield
	inc	dh
	cmp	dh, 15
	jb	setmode_drawtextt
setmode_drawtextend:
	pop	bp

setmode_keyboard:
	mov	ah, 0
	int	16h

	test	bp, bp
	jnz	@F
	cmp	al, "0"
	jne	@F
	xor	ax, ax
	mov	[_width], ax
	mov	[height], ax
	mov	[depth], ax
	jmp	setmode_exit	; short jmp to near jmp
@@:	lea	si, [modes + bp]
	mov	bl, "1"
@@:	cmp	word ptr [si], 0
	je	setmode_nomorekeys
	cmp	al, bl
	je	setmode_this
	add	si, 6
	inc	bl
	cmp	bl, "9"
	jbe	@B
	cmp	word ptr [si], 0
	je	setmode_nomorekeys
	cmp	ah, 81		; PGDN
	jne	setmode_nomorekeys
@@:	add	bp, 9*6
	jmp	setmode_drawtext
setmode_this:
	mov	ax, [si]
	mov	bx, [si + 2]
	mov	cx, [si + 4]
	mov	[_width], ax
	mov	[height], bx
	mov	[depth], cx
setmode_exit:
	jmp	drawscreenanew
setmode_nomorekeys:
	test	bp, bp
	jz	@F
	cmp	ah, 73		; PGUP
	jnz	@F
	sub	bp, 9*6
	jmp	setmode_drawtext
@@:	cmp	al, 27
	je	setmode_exit
	cmp	al, "x"
	je	setmode_exit
	cmp	al, "X"
	je	setmode_exit
	jmp	setmode_keyboard

mode2text:
	mov	ax, word ptr [si]
	call	itoa
	mov	al, "x"
	stosb
	mov	ax, word ptr [si + 2]
	call	itoa
	mov	al, "x"
	stosb
	mov	ax, word ptr [si + 4]
	call	itoa
	mov	al, "$"
	stosb
	ret

blankfield:
	mov	bh, 0
	mov	ah, 2
	int	10h
	mov	cx, 15
	mov	ax, 0A20h
	int	10h
	ret

drawstringat:
	mov	bh, 0
	mov	ah, 2
	int	10h
	lodsb
	cmp	al, "$"
	je	@F
	mov	cx, 1
	mov	bh, 0
	mov	ah, 0Ah
	int	10h
	inc	dl
	jmp	drawstringat
@@:	ret

eraseui:
	mov	bx, 7h
	xor	dx, dx
@@:	mov	ah, 2
	int	10h
	mov	cx, 80
	mov	ax, 920h
	int	10h
	inc	dh
	cmp	dh, 25
	jb	@B
	xor	dx, dx
	mov	ah, 2
	int	10h
	ret
	;*** End Configuration UI ***

decodedefault:
	test	si, si
	jnz	@F
	lea	si, [default]
@@:	ret

decodefontsize:		; returns string for font size in si
	mov	al, [fontsz]
	cmp	al, "s"
	je	decodefontsizesmall
	cmp	al, "l"
	je	decodefontsizelarge
	xor	si, si
	ret
decodefontsizesmall:
	lea	si, [small]
	ret
decodefontsizelarge:
	lea	si, [large]
	ret

decodepmid:		; returns string for pmid in si
	mov	al, [pmid]
	cmp	al, "u"
	je	decodepmidsum
	cmp	al, "s"
	je	decodepmidsanity
	cmp	al, "n"
	je	decodepmidnone
	cmp	al, "d"
	je	decodepmiddisable
	xor	si, si
	ret
decodepmidsum:
	lea	si, [sum]
	ret
decodepmidsanity:
	lea	si, [sanity]
	ret
decodepmidnone:
	lea	si, [none]
	ret
decodepmiddisable:
	lea	si, [disable]
	ret

exit_save:
	call	eraseui

	;Step 1: Locate [boot] and add
save_fboot:
	call	readfirstlineagain
@@:	test	si, si
	jz	save_no_boot
	lea	di, [sboot]
	call	section_recognizer
	je	save_boot
	call	readnextline
	jmp	@B
save_no_boot:
	lea	si, [buf]
	lea	di, [sboot]
	call	insert_line
	jmp	save_boot_insert
save_boot:
	call	readnextline
	test	si, si
	jnz	@F
	lea	di, [pdisplaydrv]
	call	append_line
	jmp	save_fenh
@@:	mov	bp, si
save_boot_nextline:
	call	readnextline
save_boot_nextline2:
	test	si, si
	jz	@F
	call	any_section_recognizer
	je	@F
	lea	di, [pdisplaydrv]
	call	assign_recognizer
	jne	save_boot_nextline
	call	remove_line
	jmp	save_boot_nextline2
@@:	mov	si, bp
save_boot_insert:
	lea	di, [pdisplaydrv]
	call	insert_line
	
	;Step 2: Locate [386Enh] and add
save_fenh:
	call	readfirstlineagain
@@:	test	si, si
	jz	save_no_enh
	lea	di, [senhlower]
	call	section_recognizer
	je	save_enh
	call	readnextline
	jmp	@B
save_no_enh:
	lea	si, [buf]
	lea	di, [senh]
	call	insert_line
	jmp	save_enh_insert
save_enh:
	call	readnextline
	test	si, si
	jnz	@F
	lea	di, [pdisplay]
	call	append_line
	jmp	save_fvbesvga
@@:	mov	bp, si
save_enh_nextline:
	call	readnextline
save_enh_nextline2:
	test	si, si
	jz	@F
	call	any_section_recognizer
	je	@F
	lea	di, [pdisplay]
	call	assign_recognizer
	jne	save_enh_nextline
	call	remove_line
	jmp	save_enh_nextline2
@@:	mov	si, bp
save_enh_insert:
	lea	di, [pdisplay]
	call	insert_line

	;Step 3: locate [VBESVGA] and add
save_fvbesvga:
	call	readfirstlineagain
@@:	test	si, si
	jz	save_no_vbesvga
	lea	di, [svbesvgalower]
	call	section_recognizer
	je	save_vbesvga
	call	readnextline
	jmp	@B
save_no_vbesvga:
	lea	di, [nlsvbesvga]
	call	append_line
	jmp	save_vbesvga_insert
save_vbesvga:
	call	readnextline
	test	si, si
	jnz	@F
	mov	si, [inend]
	jmp	save_vbesvga_insert
@@:	mov	bp, si
save_vbesvga_nextline:
	call	readnextline
save_vbesvga_nextline2:
	test	si, si
	jz	save_vbesvga_insert_top
	call	any_section_recognizer
	je	save_vbesvga_insert_top
	lea	di, [pwidthlower]
	call	assign_recognizer
	je	save_vbesvga_remove
	lea	di, [pheightlower]
	call	assign_recognizer
	je	save_vbesvga_remove
	lea	di, [pdepthlower]
	call	assign_recognizer
	je	save_vbesvga_remove
	lea	di, [pfontsz]
	call	assign_recognizer
	je	save_vbesvga_remove
	lea	di, [ppmidlower]
	call	assign_recognizer
	je	save_vbesvga_remove
	lea	di, [pdblbufferlower]
	call	assign_recognizer
	je	save_vbesvga_remove
	jmp	save_vbesvga_nextline
save_vbesvga_remove:
	call	remove_line
	jmp	save_vbesvga_nextline2
save_vbesvga_insert_top:
	mov	si, bp
save_vbesvga_insert:
	mov	ax, [_width]	; Width=
	or	ax, ax
	jz	@F
	lea	di, [pwidth]
	call	insertpropnumeric
@@:	mov	ax, [height]	; Height=
	or	ax, ax
	jz	@F
	lea	di, [pheight]
	call	insertpropnumeric
@@:	mov	ax, [depth]	; Depth=
	or	ax, ax
	jz	@F
	lea	di, [pdepth]
	call	insertpropnumeric
@@:	push	si		; fontize=
	call	decodefontsize
	xchg	ax, si
	pop	si
	test	ax, ax
	jz	@F
	lea	di, [pfontsz]
	call	insertpropstring
@@:	mov	ax, [refresh]	; DoubleBufRefreshRate= (always generated)
	lea	di, [pdblbuffer]
	call	insertpropnumeric
	push	si
	call	decodepmid
	xchg	ax, si
	pop	si
	test	ax, ax
	jz	save_buffer
	lea	di, [ppmid]
	call	insertpropstring
save_buffer:
	lea	si, [pname1]	; Now save buffer
	lea	di, [pname2]
	mov	dx, di
	call	stpcpy0
	mov	word ptr [di - 1], 35	; SYSTEM.IN# and null
	;mov	byte ptr [si], "$"	; uncomment for debugging
	;mov	byte ptr [di + 1], "$"	; not needed in final version
	xor	cx, cx
	mov	ah, 3Ch
	int	21h
	jc	ioerror
	mov	[hout], ax
	call	writeblockx
	mov	ah, 3Eh		; SYSTEM.IN# handle is left in the register
	int	21h
	jc	ioerror
	lea	dx, [pname1]	; Delete SYSTEM.INI
	mov	ah, 41h
	int	21h
	jc	ioerror
	mov	di, dx		; Rename SYSTEM.IN# to SYSTEM.INI
	lea	dx, [pname2]
	mov	ah, 56h
	int	21h
	jc	ioerror
	;It would be nice to display a message telling the user to
	;restart Windows if it is running, but I don't know how to do that yet.
	jmp	exit0

exit_nosave:
	call	eraseui
	;jmp	exit0

	;*** Common helper routines used by init, setup, and other stuffs ***
	.8086
exit0:
	mov	al, 0
exit:
	mov	ah, 4Ch
	int	21h

	;Sets di to pname1, then copies executable directory name into di; return di = end of directory name
	;destroys al, si
pathfromexepath:
	lea	di, [pname1]
	mov	si, [exeoff]
	push	ds
	;mov	ds, word ptr [2Ch]
	db	8Eh, 1Eh, 2Ch, 00h
@@:	lodsb	
	cmp	al, 0
	je	@F
	stosb
	jmp	@B
@@:	pop	ds
@@:	dec	di
	cmp	byte ptr [di], 92
	jne	@B
	inc	di
	ret

itoa:	; Writes ax to di in decimal, clobbers ax, bx, cx, dx; di now points after number
	mov	bx, 10
	xor	cx, cx
@@:	xor	dx, dx
	div	bx
	add	dl, "0"
	inc	cx
	push	dx
	or	ax, ax
	jnz	@B
@@:	pop	ax
	stosb
	loop	@B
	ret

	;Seeks to first nonwhitespace after = (which won't be end of line)
silly_char:
	lodsb
	cmp	al, "="
	jne	silly_char	; We know this exists, don't have to check
@@:	lodsb
	cmp	al ,32
	je	@B
	cmp	al, 9
	je	@B
	cmp	al, 10
	jne	silly_char_end
silly_atoi_end:
	dec	si
silly_char_end:
	ret

	;Reads number after = into ax
silly_atoi:
	call	silly_char
	xor	bx, bx
	mov	cx, 10
silly_atoi_next:
	cmp	al, 10
	je	silly_atoi_end
	sub	al, "0"
	jb	@F
	cmp	al, 9
	ja	@F
	mov	ah, 0
	xchg	ax, bx
	mul	cx
	add	bx, ax
@@:	lodsb
	jmp	silly_atoi_next

	; String copy routines; destroys ax, si; di points to string terminator
stpcpydollar:
	mov	ah, "$"
	jmp	stpcpyh
stpcpy0:
	mov	ah, 0
stpcpyh:
	lodsb
	stosb
	cmp	al, ah
	je	@F
	jmp	stpcpyh
@@:	dec	di
	ret

nosvgabios:
	lea	dx, [nosvgabiosmsg]
	jmp	exit1msg

popvidmodes:	; Fills MODES structure with video modes, stopping it with an all zeros entry
	push	ds
	pop	es
	lea	di, [buf]
	mov	word ptr [di], "VB"
	mov	word ptr [di + 2], "E2"
	mov	ax, 4F00h
	int	10h
	cmp	al, 4Fh
	jne	nosvgabios
	cmp	word ptr [di], "EV"	; I'm convinced the assembler is bugged here; the constant is actually VE
	jne	nosvgabios
	cmp	word ptr [di + 2], "AS"
	jne	nosvgabios
	.386	; VESA yes, therefore 386 yes
	lfs	si, [di + 14]
	lea	bx, [modes]
popnextvidmode:
	lods	word ptr fs:[si]
	cmp	ax, 0FFFFh
	je	poplastvidmode
	mov	cx, ax
	push	bx		; I do not trust 4F01h to not trash BX
	mov	ax, 4F01h
	lea	di, [buf + 512]
	int	10h
	pop	bx
	cmp	ax, 04Fh
	jne	popnextvidmode
	bt	word ptr [di], 0
	jnc	popnextvidmode
	bt	word ptr [di], 4
	jnc	popnextvidmode
	mov	ax, [di + 18] ; Width
	mov	dx, [di + 20] ; Height
	mov	cl, [di + 25] ; Depth
	;Depth code might be wrong and might have to be changed to unpack masks
	cmp	cl, 8
	jb	popnextvidmode	; Unusable
	cmp	cl, 24
	jbe	@F
	mov	cl, 24
@@:	mov	[bx], ax
	inc	bx
	inc	bx
	mov	[bx], dx
	inc	bx
	inc	bx
	mov	ch, 0
	mov	[bx], cx
	inc	bx
	inc	bx
	lea	bp, [modes + 4090]
	cmp	bx, bp
	jbe	popnextvidmode
poplastvidmode:
	xor	ax, ax
	mov	word ptr [bx], ax
	mov	word ptr [bx + 2], ax
	mov	word ptr [bx + 4], ax
	cmp	word ptr [modes], 0
	je	novidmodes
	ret

novidmodes:
	lea	dx, [novidmodesmsg]
	jmp	exit1msg

	; si = target location, di = property name, ax = property value
insertpropnumeric:
	push	si
	push	ax
	mov	si, di
	lea	di, [genln]
	call	stpcpydollar
	pop	ax
	call	itoa
	mov	al, "$"
	stosb
	pop	si
	lea	di, [genln]
	jmp	insert_line

	; si = target location, di = property name, ax = property value
insertpropstring:
	push	si
	push	ax
	mov	si, di
	lea	di, [genln]
	call	stpcpydollar
	pop	si
	call	stpcpydollar
	pop	si
	lea	di, [genln]
	jmp	insert_line

	; Verifies if si points to a section; destroys al
any_section_recognizer:
	push	si
@@:	lodsb
	cmp	al, 32
	je	@B
	cmp	al, 9
	je	@B
	cmp	al, "["
	pop	si
	ret

	; Verifies if si points to section pointed to in di; destroys ax, di
section_recognizer:
	push	si
@@:	lodsb
	cmp	al, 32
	je	@B
	cmp	al, 9
	je	@B
	dec	si
@@:	lodsb
	call	al_tolower
	mov	ah, [di]
	inc	di
	cmp	al, ah
	jne	@F
	cmp	al, "]"
	jne	@B
@@:	pop	si
	ret

	; Verifies if si points to properter pointed to in di; destroys ax, di
assign_recognizer:
	push	si
@@:	lodsb
	cmp	al, 32
	je	@B
	cmp	al, 9
	je	@B
	dec	si
@@:	mov	ah, byte ptr [di]
	inc	di
	cmp	ah, "="
	je	assign_recognizer_eos
	lodsb
	call	al_tolower
	cmp	al, ah
	je	@B
	pop	si
	ret
assign_recognizer_eos:
	lodsb
	cmp	al, 32
	je	assign_recognizer_eos
	cmp	al, 9
	je	assign_recognizer_eos
	cmp	al, "="
	pop	si
	ret
	
al_tolower:
	cmp	al, "A"
	jb	@F
	cmp	al, "Z"
	ja	@F
	add	al, 32
@@:	ret

;SYSTEM.INI should never get bigger than the buffer size, that would cause too many problems
;so we don't need to handle this case. Too much code, too hard to debug, too little gain.
;Just manipulate the entire file in memory at once.
readfirstline_toobig:
	lea	dx, [systeminitoobig]
	jmp	exit1msg

	; returns SI = start of line or 0 for empty file
	; clobbers everything but BP
readfirstline:
	call	readblockx
	lea	si, [buf]
	mov	di, [inend]
	mov	cx, di
	sub	cx, si
	jnz	@F
	xor	si, si	; Empty file
	ret
@@:	cmp	cx, bufsz
	jae	readfirstline_toobig
	cmp	byte ptr [di - 1], 10
	jne	@F
	ret
@@:	cmp	byte ptr [di - 2], 13
	jne	@F
	cmp	cx, bufsz - 1
	jae	readfirstline_toobig
	mov	al, 10
	stosb
	mov	[inend], di
	ret
@@:	cmp	cx, bufsz - 2
	jae	readfirstline_toobig
	mov	ax, 0D0Ah
	stosw
	mov	[inend], di
	ret
	;Returns start of buffer in SI or 0 for empty file
readfirstlineagain:
	lea	si, [buf]
	cmp	si, [inend]
	jbe	@F
	xor	si, si
@@:	ret
	;Advance to next line; return in SI; clobbers AL
readnextline:
	lodsb
	cmp	al, 10
	jne	readnextline
	cmp	si, [inend]
	jb	@F
	xor	si, si
@@:	ret

append_line:
	mov	si, [inend]
	;Insert line pointed to by di (terminated by $, CRLF not included) into buffer at si
	;Advances si, Clobbers everything but bx, si and bp
insert_line:
	push	di
	mov	cx, -1
	mov	al, "$"
	repne	scasb
	dec	di
	mov	cx, di
	pop	di
	sub	cx, di
	inc	cx
	inc	cx
	mov	dx, [inend]
	add	dx, cx
	lea	ax, [buf + bufsz]
	cmp	dx, ax
	jae	insert_line_toobig
	push	si
	push	di
	push	cx
	mov	di, dx		; SI = insert here, DI = buffer top
	mov	[inend], di
	xchg	si, dx
	sub	si, cx
	mov	cx, dx		; CX = insert here, SI = copy from, DI = buffer top
	sub	cx, si
	neg	cx
	dec	si
	dec	di
	std
	rep	movsb
	cld
	pop	cx
	pop	si		; SI and DI swapped
	pop	di
	dec	cx
	dec	cx
	rep	movsb
	mov	ax, 0A0Dh
	stosw
	mov	si, di
	ret

insert_line_toobig:
	lea	dx, [systeminitoogro]
	jmp	exit1msg

	;Removes the current line referred to by si; Clobbers AL, CX, DI
remove_line:
	push	si
	mov	di, si
	mov	cx, -1
	mov	al, 10
	repne	scasb
	xchg	si, di
	mov	cx, [inend]
	sub	cx, si
	rep	movsb
	mov	[inend], di
	pop	si
	cmp	si, [inend]
	jb	@F
	xor	si, si
@@:	ret

	; readblockx: read into buffer
readblockx:
	lea	dx, [buf]
	mov	cx, bufsz
	mov	bx, [hin]
@@:	mov	ah, 3Fh
	int	21h
	jc	ioerror
	test	ax, ax
	jz	readblockx_eof
	add	dx, ax
	sub	cx, ax
	jnz	@B
	mov	word ptr [inend], dx
	ret
readblockx_eof:
	mov	word ptr [inend], dx
	mov	ah, 3Eh
	int	21h
	mov	[hin], 0
	ret

ioerror:lea	si, [ioerrormsg]
	lea	di, [genln]
	call	stpcpydollar
	mov	al, 32
	stosb
	mov	ah, 59h
	int	21h
	call	itoa
	lea	si, [newline]
	call	stpcpydollar
	lea	dx, [genln]
	jmp	exit1msg
ioerrormsg	db	"IO Error$"

	; write bytes from buffer
writeblockx:
	lea	dx, [buf]
	mov	cx, [inend]
	sub	cx, dx
	mov	bx, [hout]
writeblock:
	mov	ah, 40h
	int	21h
	jc	ioerror
	or	ax, ax
	jz	ioerror
	add	dx, ax
	sub	cx, ax
	ja	writeblock
	ret

nosvgabiosmsg	db	"No SVGA BIOS"	; Continues into next message for newline
newline		db	13, 10, "$"
novidmodesmsg	db	"No usable video modes", 13, 10, "$"
systeminitoobig	db	"SYSTEM.INI too big", 13, 10, "$"
systeminitoogro	db	"SYSTEM.INI would be too big", 13, 10, "$"
configvbe	db	"Configure SVGA Video Settings$"
modebase	db	"M  Video Mode$"
dblbuffbase	db	"D  Double Buffer Refresh$"
fontsizebase	db	"F  Font Size$"
pmidbase	db	"P  PMID Check$"
enterbase	db	"ENTER  Save & Exit$"
escbase		db	"ESC    Exit$"

systemini	db	"SYSTEM.INI", 0
svbesvgalower	db	"[vbesvga.drv]"
nlsvbesvga	db	13, 10
svbesvga	db	"[VBESVGA.DRV]$"
senhlower	db	"[386enh]"
senh		db	"[386Enh]$"
sboot		db	"[boot]$"

pdisplay	db	"display=vddvbe.386$"
pdisplaydrv	db	"display.drv=vbesvga.drv$"
pwidthlower	db	"width="
pwidth		db	"Width=$"
pheightlower	db	"height="
pheight		db	"Height=$"
pdepthlower	db	"depth="
pdepth		db	"Depth=$"
pfontsz		db	"fontsize=$"
ppmidlower	db	"pmidcheck="
ppmid		db	"PMIDcheck=$"
pdblbufferlower	db	"doublebufrefreshrate="
pdblbuffer	db	"DoubleBufRefreshRate=$"
small		db	"small$"
large		db	"large$"
sum		db	"sum$"
sanity		db	"sanity$"
none		db	"none$"
disable		db	"disable$"
more		db	"PG/DN More$"
less		db	"PG/UP Prev$"
default0	db	"0) "
default		db	"default$"

	ALIGN 2

_width	dw	0	; Initialized to not found ...
height	dw	0
depth	dw	0
pmid	db	0
fontsz	db	0
refresh	dw	60

issetupexe:
	;*** SETUP.EXE copies VGASVGA.DRV, VDDVBE.386, VIDMODES.COM, VBESVGA.TXT
	;*** generates VBESVGA.EXE, then runs configuration screen

	; This generates VBESVGA.EXE's body
	lea	dx, [noexesysteminimsg]
	mov	word ptr [noexesystemini + 1], dx
	mov	byte ptr [noexesystemini], 0BAh	; mov dx, constant
	xor	bp, bp

	;Try 1: check for command line argument, if present try no other
	mov	si, 81h
	mov	byte ptr [si + 7Eh], 0Dh	; known elephant in Cairo
@@:	lodsb
	cmp	al, 0Dh
	je	nocmdargument
	cmp	al, 32
	je	@B
	cmp	al, 9
	je	@B
	dec	si
	mov	ah, 0Dh
	lea	di, [pname2]
	call	stpcpyh
	cmp	byte ptr [di - 1], 92
	je	@F
	cmp	byte ptr [di - 1], 47
	je	@F
	mov	al, 92
	stosb
@@:	call	checkwindir
	jnc	foundwindir
	jmp	error_nowindir

	;Last try: Guess C:\WINDOWS
nousablepathentry:
	lea	si, [cwindows]
	lea	di, [pname2]
	call	stpcpy0
	call	checkwindir
	jnc	foundwindir
error_nowindir:
	lea	dx, [nowindir]
	test	bp, 1
	jz	@F
	lea	dx, [nosysdir]
@@:	jmp	exit1msg

	;Try 2: decode path (note that . is implicitly in the path so we do that first)
nocmdargument:
	lea	di, [pname2]
	call	checkwindir
	jnc	foundwindir
	mov	si, [pathoff]
@@:	call	nextpathentry
	jz	nousablepathentry
	push	si
	call	checkwindir
	pop	si
	jc	@B
foundwindir:
	push	di
	test	bp, 2
	jnz	foundwindir_nadj	; System directory is overlaid on windows directory
	add	di, 7			; Always SYSTEM\
foundwindir_nadj:
	lea	si, [vbesvgadrv]
	call	copyfile
	jc	ioerror
	lea	si, [vddvbe386]
	call	copyfile
	jc	ioerror
	pop	di
	lea	si, [vidmodescom]
	call	copyfile
	;Executive decision: VIDMODES.COM is an optional component
	lea	si, [vbesvgatxt]
	call	copyfile
	;No error check here as this file isn't ready yet.
	lea	dx, [vbesvgaexes]
	mov	ah, 9
	int	21h
	lea	si, [vbesvgaexe]
	push	di
	call	stpcpy0
	pop	di
	lea	dx, [pname2]
	xor	cx, cx
	mov	ah, 3Ch
	int	21h
	jc	ioerror
	xchg	ax, bx
	lea	dx, [vbemzheader]
	mov	cx, 32
	call	writeblock
	mov	dx, _start
	mov	cx, issetupexe - _start
	call	writeblock
	mov	dx, [exeoff]
	push	ds
	;mov	ds, word ptr [2Ch]
	db	8Eh, 1Eh, 2Ch, 00h
	mov	ax, 3D00h
	int	21h
	pop	ds
	jc	vbesvganosetattr
	push	bx
	xchg	ax, bx
	mov	ax, 5700h
	int	21h
	pushf
	mov	ah, 3Eh
	int	21h
	popf
	pop	bx
	jc	vbesvganosetattr
	mov	ax, 5701h
	int	21h
vbesvganosetattr:
	mov	ah, 3Eh
	int	21h
	jc	ioerror
	lea	si, [systemini]
	call	stpcpy0
	stosb
	lea	si, [pname2]
	lea	di, [pname1]
	call	stpcpy0
	stosb
	lea	dx, [pname1]
	xor	cx, cx
	mov	ax, 3D00h
	int	21h
	jc	ioerror
	jmp	haveexesystemini	; Install successful; configure it

; Copies a file; si = filename to copy, di = out path endpoint:
; preserves di
copyfile:
	push	si
	push	di
	push	si
	call	pathfromexepath
	pop	si
	mov	dx, di
	call	stpcpy0
	mov	word ptr [di], 2420h
	mov	ah, 9
	int	21h
	mov	byte ptr [di], 0
	pop	di
	pop	si
	push	di
	call	stpcpy0
	pop	di
	lea	dx, [pname1]
	mov	ax, 3D00h
	int	21h
	jnc	@F
	cmp	al, 2
	jne	ioerror
	stc
	ret				; Caller decides if file not found is an error
@@:	mov	[hin], ax
	lea	dx, [pname2]
	xor	cx, cx
	mov	ah, 3Ch
	int	21h
	jc	ioerror
	mov	[hout], ax
@@:	mov	bx, [hin]
	lea	dx, [buf]
	mov	cx, bufsz
	mov	ah, 3Fh
	int	21h
	jc	ioerror
	or	ax, ax
	jz	copyfile_eof
	mov	bx, [hout]
	xchg	ax, cx
	call	writeblock
	mov	dl, "."
	mov	ah, 2
	int	21h
	jmp	@B
copyfile_eof:
	mov	bx, [hin]
	mov	ax, 5700h
	int	21h
	jc	ioerror
	mov	ah, 3Eh
	int	21h
	mov	bx, [hout]
	mov	ax, 5701h
	int	21h
	mov	ah, 3Eh
	int	21h
	jc	ioerror
	lea	dx, [newline]
	mov	ah, 9
	int	21h
	clc
	ret

	;Checks if [pname2] contains a windows directory
	;returns CF clear if it does, set otherwise, preserves DI
checkwindir:
	lea	dx, [pname2]
	push	di
	lea	si, [systemini]
	call	stpcpy0
	pop	di
	mov	ax, 4300h
	int	21h
	jc	isnotwindir
	mov	bp, 1
	push	di
	lea	si, [systemdir]
	call	stpcpy0
	lea	si, [dosxexe]
	call	stpcpy0
	pop	di
	mov	ax, 4300h
	int	21h
	jnc	issysdosx
	push	di
	lea	si, [dosxexe]
	call	stpcpy0
	pop	di
	mov	ax, 4300h
	int	21h
	jc	isnotwindir
	or	bp, 2
	clc
	ret
issysdosx:
	clc
	ret
isnotwindir:
	stc
	ret

	;Copies path entry into PNAME2, returns DI points past end of entry, or ZF set if no more
nextpathentry:
	cmp	si, 0FFFFh
	je	nomorepathentry
	push	ds
	;mov	ds, word ptr [2Ch]
	db	8Eh, 1Eh, 2Ch, 00h
	lea	di, [pname2]
	mov	cx, di
@@:	lodsb
	cmp	al, ";"
	je	@F
	cmp	al, 0
	je	@F
	stosb
	jmp	@B
@@:	cmp	cx, di
	je	@F
	cmp	byte ptr es:[di - 1], 92
	je	@F
	cmp	byte ptr es:[di - 1], 47
	je	@F
	push	ax
	mov	al, 92
	stosb
	pop	ax
@@:	cmp	byte ptr [si - 1], 0
	pop	ds
	je	@F
	ret			; There's another entry
@@:	mov	si, 0FFFFh
	test	si, si		; Clear ZF
nomorepathentry:
	ret
	
cwindows	db	"C:\WINDOWS\", 0
systemdir	db	"SYSTEM\", 0
dosxexe		db	"DOSX.EXE", 0
vbesvgadrv	db	"VBESVGA.DRV", 0
vddvbe386	db	"VDDVBE.386", 0
vidmodescom	db	"VIDMODES.COM", 0
vbesvgatxt	db	"VBESVGA.TXT", 0
vbesvgaexes	db	"VBESVGA.EXE $"
vbesvgaexe	db	"VBESVGA.EXE", 0
nowindir	db	"Windows directory not found; try running SETUP C:\WINDIR", 13, 10, "$"
nosysdir	db	"System directory not found or DOSX.EXE missing", 13, 10, "$"

	ALIGN 2

vbemzheader:
vbemztaillen	equ	(issetupexe - mzheader) AND 511
	db	"MZ"
	dw	(512 - vbemztaillen) AND 512 OR vbemztaillen	; number of bytes in last sector
	dw	(issetupexe - mzheader + 511) / 512		; number of 512 byte sectors
	dw	0	; PIC (easy in tiny model)
	dw	2	; Size of header
	dw	0FFFh	; Uses 64KB; I'm too lazy to make it smaller
	dw	0FFFh	; If you're going to be running Windows you can spare it.
	dw	0	; See above
	dw	0FFF0h	; Initial SS
	dw	0	; Checksum - not used
	dw	0	; Initial IP
	dw	0	; Initial CS
	dw	0	; No relocation table
	dw	0	; Main exe
	db	"SVGA"	; Overlay info (how to tell SETUP.EXE from VBESVGA.EXE)

_end:
.data?
	;ALIGN 4 - should work bout doesn't
pathoff	dw	?
exeoff	dw	?
hin	dw	?
hout	dw	?
inend	dw	?
	;dw	?	and since ALIGN 4 doesn't work padding to 4 doesn't need to be done
pname1	db	128 dup(?)
pname2	db	128 dup(?)
genln	db	256 dup(?)
buf	db	32768 dup(?)
bufsz	equ	32768
modes	db	4096 dup(?)
end
