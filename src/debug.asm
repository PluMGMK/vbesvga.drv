;
;	FILE:	debug.asm
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module contains routines thatassist in debugging the display
;	driver.

SRCFILE_DEBUG	equ	1
incLogical	=	1
incDrawMode     =       1

include cmacros.inc
include gdidefs.inc
include macros.mac
include display.inc
include cursor.inc
include njumps.mac
include vgareg.inc


sBegin	Data

;	This holds the reg indexes so that they can be restored properly
;	after the VGA state is read. The 4 bytes in order from lowest
;	address to highest address are: Seq, Crt, Grph, Crt3
;	Crt3-bit7 needs to be a 1 in order to read back vertical retrace
;	registers Crt10 and Crt11 properly. So it must be saved.

PUBLIC	saved_reg_indexes
saved_reg_indexes	LABEL	BYTE
db	0,0,0,0

PUBLIC	debug_dump_regs_string
debug_dump_regs_string	LABEL	BYTE
db	9,9
db	48,48,32,48,49,32,48,50,32,48,51,32
db	48,52,32,48,53,32,48,54,32,48,55,32
db	13,10,13,10

db	"Misc 3CC:",9
PUBLIC	Misc_reg
Misc_reg	LABEL	BYTE
db      0,0,13,10

db	"PixMask 3C6:",9
PUBLIC	Pixmask_reg
Pixmask_reg  LABEL   BYTE
db      0,0,13,10

db	"VidEnbl 3C3:",9
PUBLIC	Videnbl_reg
Videnbl_reg  LABEL   BYTE
db      0,0,13,10

db	"AltEnbl 102:",9
PUBLIC	Altenbl_reg
Altenbl_reg  LABEL   BYTE
db      0,0,13,10

db	"VSC 46E8:",9
PUBLIC	VSC_reg
VSC_reg LABEL	BYTE
db      0,0,13,10

db	"Seq 0-6:",9
PUBLIC	Seq_06_reg
Seq_06_reg	LABEL	BYTE
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10

db	"Crt 0-18",9
PUBLIC	Crt_018_reg
Crt_018_reg	 LABEL	 BYTE
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,13,10

db	"Grph 0-8:",9
PUBLIC	Grph_08_reg
Grph_08_reg	LABEL	BYTE
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,13,10

db	"Attr 0-14:",9
PUBLIC	Attr_014_reg
Attr_014_reg	 LABEL	 BYTE
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10

db	"Ext 80-FF:",9
PUBLIC	Ext_regs
Ext_regs	LABEL	BYTE
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10,9,9
db	0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,32,0,0,13,10

db	13,10,13,10,9,9
db	48,48,32,48,49,32,48,50,32,48,51,32
db	48,52,32,48,53,32,48,54,32,48,55,32
db	13,10,0

sEnd    Data

.286
sBegin	Code
assumes cs,Code
assumes ds,Data
assumes es,Nothing
assumes ss,Nothing


;
;	debug_dump_vgaregs
;
;	This routine dumps out the Video 7 VGA registers to com port 1.
;	PARMS:
;	Data	the driver data segment

PUBLIC	debug_dump_vgaregs
debug_dump_vgaregs	PROC	FAR

	push	bp
	mov	bp,sp
	pusha
	pushf
	push	ds
	push	es
	mov	ax,[bp+ 6]
	mov	es,ax
	mov	ds,ax
        call    debug_save_state

	mov	dx,03CCH
	in	al,dx
	call	convert_byte_to_hex
	mov	di,DataOFFSET Misc_reg
	stosw

	mov	dx,03C6H
	in	al,dx
	call	convert_byte_to_hex
	mov	di,DataOFFSET Pixmask_reg
	stosw

	mov	dx,03C3H
	in	al,dx
	call	convert_byte_to_hex
	mov	di,DataOFFSET Videnbl_reg
	stosw

	mov	dx,0102H
	in	al,dx
	call	convert_byte_to_hex
	mov	di,DataOFFSET Altenbl_reg
	stosw

	mov	dx,046E8H
	in	al,dx
	call	convert_byte_to_hex
	mov	di,DataOFFSET VSC_reg
	stosw

	mov	dx,3C4H
	mov	al,0
	mov	di,DataOFFSET Seq_06_reg
	mov	cx,7
	call	convert_array_of_regs

        mov     dx,3D4H
	mov	al,0
	mov	di,DataOFFSET Crt_018_reg
	mov	cx,19H
	call	convert_array_of_regs

	mov	dx,3CEH
	mov	al,0
	mov	di,DataOFFSET Grph_08_reg
	mov	cx,9
        call    convert_array_of_regs

	mov	dx,3C0H
	mov	al,20H
	mov	di,DataOFFSET Attr_014_reg
	mov	cx,15H
	call	convert_attr_regs

	mov	dx,3C4H
	mov	al,80H
	mov	di,DataOFFSET Ext_regs
	mov	cx,80H
        call    convert_array_of_regs

	mov	si,DataOFFSET debug_dump_regs_string
	call	write_string_to_com1

debug_dump_vgaregs_done:

	call	debug_restore_state
	pop	es
	pop	ds
	popf
	popa
	mov	sp,bp
	pop	bp
	ret

debug_dump_vgaregs	ENDP


;
;	debug_save_state
;
;	This routine saves the state of some registers which get changed
;	during the debug proceedings. They can be restored later.

PUBLIC	debug_save_state
debug_save_state	PROC	NEAR

	mov	si,DataOFFSET saved_reg_indexes

	mov	dx,3C4H
	in	al,dx
	mov	[si],al
        mov     dx,3CEH
        in      al,dx
        mov     [si + 2],al
	mov	dx,3D4H
	in	al,dx
	mov	[si + 1],al
	mov	al,3
	out	dx,al
	inc	dx
	in	al,dx
	mov	[si + 3],al
	or	al,80H
	out	dx,al
	ret

debug_save_state	ENDP


;
;	debug_restore_state
;
;	This routine restores the state of some registers which get changed
;	during the debug proceedings.

PUBLIC	debug_restore_state
debug_restore_state	   PROC    NEAR

	mov	si,DataOFFSET saved_reg_indexes

	mov	dx,3C4H
	mov	al,[si]
	out	dx,al
        mov     dx,3CEH
	mov	al,[si + 2]
	out	dx,al
	mov	dx,3D4H
        mov     al,3
        out     dx,al
        inc     dx
	mov	al,[si + 3]
	out	dx,al
	dec	dx
	mov	al,[si + 1]
	out	dx,al
	ret

debug_restore_state	   ENDP


;
;	convert_array_of_regs
;
;	This routine converts many regs values into hex bytes and places
;	them in a formatted string.
;	PARMS:
;	dx	IO port address of address register
;	al	first index to read
;	di	ptr to string where value is to be placed
;		string looks like: 0,0,32,0,0,32,0,0,32
;		The zeros should be replaced by the reg values
;	cx	number of registers to write

PUBLIC	convert_array_of_regs
convert_array_of_regs	PROC	NEAR

	push	cx
	mov	bx,cx
	shr	bx,3
	je	less_than_8

card1:	mov	cx,8
cardo:	push	ax
	out	dx,al
	inc	dx
	in	al,dx
	dec	dx
	call	convert_byte_to_hex
	stosw
	inc	di			;move past the space
	pop	ax
	inc	al
	loop	cardo
	add	di,3			;move past <crlf>
	dec	bx
	jg	card1
	js	cardone

less_than_8:
	pop	cx
	and	cx,7
	jne	cardo

cardone:
	ret

convert_array_of_regs   ENDP


;
;	convert_attr_regs
;
;	This routine is virtually identical to convert_array_of_regs.
;	The attribute controller addressing is slightly screwed so I
;	made a different routine for it.
;	PARMS:
;	al	first index to read
;	di	ptr to string where value is to be placed
;		string looks like: 0,0,32,0,0,32,0,0,32
;		The zeros should be replaced by the reg values
;	cx	number of registers to write

PUBLIC	convert_attr_regs
convert_attr_regs   PROC    NEAR

	push	cx
	mov	bx,cx
	shr	bx,3
	je	less_than_e

catd1:	mov	cx,8
catdo:	push	ax
	push	ax
	mov	dx,3DAH
	in	al,dx
	mov	dx,3C0H
	pop	ax
	out	dx,al
	inc	dx
	in	al,dx
	dec	dx
	call	convert_byte_to_hex
	stosw
	inc	di			;move past the space
	pop	ax
	inc	al
	loop	catdo
	add	di,3			;move past <crlf>
	dec	bx
	jg	catd1
	js	catdone

less_than_e:
	pop	cx
	and	cx,7
	jne	catdo

catdone:
	ret

convert_attr_regs	ENDP


;
;	convert_byte_to_hex
;
;	This routine converts the byte in al into two hex digits inax.
;	PARMS:
;	al	byte to convert
;
;	RETURNS:
;	ax	two hex digits

PUBLIC	convert_byte_to_hex
convert_byte_to_hex	PROC	NEAR

	mov	ah,al
        and     al,0FH
	add	al,30H
	cmp	al,39H
	jbe	@F
	add	al,07H

@@:     xchg    al,ah
        and     al,0F0H
        shr     al,4
	add	al,30H
	cmp	al,39H
	jbe	@F
        add     al,07H
@@:	ret

convert_byte_to_hex	ENDP


;
;	write_string_to_com1
;
;	This routine uses the BIOS int 14H which writes a character to com1.
;	Each character in the string is written until a NULL terminator is
;	found.
;	PARMS:
;	ds:si	ptr to string to write


PUBLIC	write_string_to_com1
write_string_to_com1	PROC	NEAR

@@:	lodsb
	or	al,al
	je	@F
	mov	ah,01H
	int	14H
	jmp	@B
@@:	ret

write_string_to_com1	ENDP


sEnd    CODE

END

