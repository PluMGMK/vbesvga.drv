	page	,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	SSWITCH.ASM
;
;   This module contains the functions:
;
;
; Created: 16-Sep-1987
; Author:  Bob Grudem [bobgru]
;
; Copyright (c) 1984-1987 Microsoft Corporation
;
; Exported Functions:	none
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
; Restrictions:
;
;-----------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.


	??_out	sswitch


ifdef	OS2_ONLY
	.286c
endif

	.xlist
	include cmacros.inc
	include macros.mac
	.list

	externFP ScreenSwitchEnable	;Imported from KEYBOARD.DRV
	externFP GetModuleHandle
	externFP GetProcAddress
	externNP dev_to_background	;Switch to background code
	externNP dev_to_foreground	;Switch to foreground code
	externFP dev_initialization	;Other boot-time initialization
	externFP AllocCSToDSAlias	;get a DS alias for CS
	externFP FreeSelector		;frees up selectors
	EXTRN	 cursor_kludge:FAR

SCREEN_SWITCH_OUT equ   4001h           ;Moving 3xBox to background
SCREEN_SWITCH_IN  equ	4002h		;Moving 3xBox to foreground
;DOS_VERSION	  equ	1000h		;Earliest DOS we must support (10.00)
DOS_VERSION	  equ	0310h		;Earliest DOS we must support (03.10)
HOT_KEY_VERSION   equ	1000h		;Version with hot key support (10.00)


INT_MULT	equ	2Fh		;Multiplexed interrupt number


sBegin	Data


CUR_OFF         equ     10000000b       ;  Null cursor has been specified
CUR_EXCLUDED	equ	01000000b	;  Cursor has been excluded
CUR_HARD	equ	00100000b	;hardware cursor
CUR_FULL	equ	00010000b	;cursor data is valid

        externB         screen_busy     ;screen semaphore

old_screen_busy	db	?		;saved value of screen semaphore
IS_BUSY	equ	0			;should be public in cursors.asm!


pre_switch	label	word
		dw	pre_switch_to_background
		dw	pre_switch_to_foreground

post_switch	label	word
		dw	post_switch_to_background
		dw	post_switch_to_foreground

switch_table	label	word		;Screen switch dispatch table
		dw	dev_to_background
		dw	dev_to_foreground

switch_control	db	0		;Switch control flags
PREVENT_SWITCH	equ	10000000b	;Don't allow switch (DOS 3.x, 4.x)
DO_SWITCHING	equ	01000000b	;Have to do switching
INT_2F_HOOKED	equ	00000001b	;Have hooked int 2Fh
DISABLE_HOT_KEY equ	00000010b	;Set if keyboard disabling required

FLAGS_ON_STACK	equ	4		;iret --> offset(0), seg(2), flags(4)
CARRY_FLAG	equ	00000001b


REPAINT_EXPORT_INDEX	equ	275
repaint_disable db	0h		;ok to call user to repaint
repaint_pending	db	0		;repaint is pending.
repaint_addr    dd      0
user_string	db	'USER',0

	public GetColor_addr
GetColor_addr   dd      0
DEVICECOLORMATCH_EXPORT_INDEX	equ	449
gdi_string     db      'GDI',0

sEnd    Data


sBegin	Code
assumes cs,Code

	externW		_cstods

prev_int_2Fh	dd	0		;Previous int 2Fh vector
page

;----------------------------------------------------------------------------;
; UserRepaintDisable:							     ;
;								             ;
; USER calls this function to tell the display driver whether it expects     ;
; the repaint call to be postponed or not.			             ;
;								             ;
; If RepaintDisable is TRUE then the display driver should not send          ;
; repaint requests to USER immediately but wait till it is enabled again.    ;
; USER will enable repaint by seting RepaintDisable to FALSE.		     ;
;----------------------------------------------------------------------------;

cProc	UserRepaintDisable,<FAR,PASCAL,PUBLIC>

	parmB	RepaintDisable		;TRUE to Disable/FALSE to enable

cBegin
	WriteAux <'URD'>
	assumes	ds,Data

	mov	al,RepaintDisable	;get the value
	mov	repaint_disable,al	;save it
	or	al,al			;being enabled again
	jnz	@f			;no.
	cmp	repaint_pending,0ffh	;pending repaint ?
	jnz	@f			;no.
	call	pre_switch_to_foreground;call repaint
	mov	repaint_pending,0	;done with pending call
@@:

cEnd
;-------------------------Interrupt-Handler-----------------------------;
; screen_switch_hook
;
; Watches calls to the OS/2 multiplex interrupt chain, and traps calls
; to the driver to save or restore the state of the display hardware
; before a context switch.
;
; If a save/restore call is recognized, then it will be dispatched
; to the device dependent handler unless PREVENT_SWITCH is
; set in switch_control.
;
;   Currently under OS/2, we inform the keyboard driver that the
;   hot key is not to be passed along to DOS whenever the display
;   driver cannot save it's state (this currently only occurs when
;   we've already saved the EGA state).  Since OS/2 will only take
;   the screen away from us when the hot key is pressed, we should
;   never see the PREVENT_SWITCH bit set).
;
;   If we're not running under OS/2, it is possible a pop-up not
;   caused by a hot key could try and grab the screen away from us .
;   In this case, we'll return with 'C' set to show that it's a real
;   bad time and try again later (they may still grab it, though).
;   In this case, PREVENT_SWITCH could be set.
;
; Entry:
;	AH = multiplex number
;	AL = function code
; Returns:
;	'C' set if screen switch cannot occur (DOS's < 10.0)
;	'C' clear otherwise
; Registers Preserved:
;	AL,BX,CX,DX,SI,DI,BP,DS,ES,SS
; Registers Destroyed:
;	AH,FLAGS
; Calls:
;	dev_to_background
;	dev_to_foreground
; History:
;	Sun 20-Sep-1987 23:02:58 -by-  Walt Moore [waltm]
;	Added switch_control flag,
;
;	Wed 16-Sep-1987 20:17:08 -by-  Bob Grudem [bobgru]
;	Wrote it.
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,nothing

screen_switch_hook proc far

	WriteAux <'SSH'>
	cmp	ax,SCREEN_SWITCH_IN
	je	screen_switch_occurring
	cmp	ax,SCREEN_SWITCH_OUT
	je	screen_switch_occurring
	jmp	prev_int_2Fh		;Not ours, pass it along

screen_switch_occurring:
	push	bp			;set up frame for altering flags
	mov	bp,sp

	push	ds
	mov	ds,[_cstods]
	assumes	ds,Data

	mov	ah,switch_control
	add	ah,ah
	jc	exit_screen_switch_error
	errnz	PREVENT_SWITCH-10000000b


ifdef	OS2_ONLY
	pusha
else
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
endif
	push	es
	and	ax,00000010b		;Use D1 of function to index into
	xchg	ax,bx			;  the two word dispatch table
	errnz	SCREEN_SWITCH_OUT-4001h
	errnz	SCREEN_SWITCH_IN-4002h
	call	pre_switch[bx]
	push	bx
	push	ds
	call	switch_table[bx]	;this guy only saved BP
	pop	ds
	assumes	ds,Data
	pop	bx
	call	post_switch[bx]
        pop     es
	assumes es,nothing

ifdef	OS2_ONLY
	popa
else
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
endif

	pop	ds
	assumes ds,nothing


;	Note that BP is still on the stack (hence FLAGS_ON_STACK+2).

	and	wptr [bp][FLAGS_ON_STACK][2],not CARRY_FLAG
	pop	bp
	iret

exit_screen_switch_error:
	pop	ds
	assumes ds,nothing

	or	wptr [bp][FLAGS_ON_STACK][2],CARRY_FLAG
	pop	bp
	iret

screen_switch_hook	endp
page



;---------------------------Public-Routine-----------------------------;
; pre_switch_to_foreground
;
; This function is called when switching to the foreground, before
; any device-specific code has executed.
;
; Entry:
;	DS = Data
; Returns:
;	DS = Data
; Registers Preserved:
;	BX,SI,DI,BP,DS
; Registers Destroyed:
;	AX,CX,DX,ES,FLAGS
; Calls:
; History:
;	Mon 05-Oct-1987 20:13:46 -by-  Walt Moore [waltm]
;	Moved repaint address fetch to hook_int_2F
;
;	Mon 05-Oct-1987 20:17:08 -by-  Bob Grudem [bobgru]
;	Wrote it.
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,Data
	assumes es,nothing

pre_switch_to_foreground	proc	near

	push	bx			;Save dispatch table index
	mov	ax,wptr repaint_addr[0] ;We expect to always have the
	or	ax,wptr repaint_addr[2] ;  address, but let's be sure
	jz	pre_switch_to_fore_exit
        cmp     repaint_disable,0       ;is repaint enabled ?
	jz	@f			;yes.
	mov	repaint_pending,0ffh	;repaint pending
	jmp	short pre_switch_to_fore_exit
@@:
        call    repaint_addr            ;Force repaint of all windows

pre_switch_to_fore_exit:
	pop	bx
	ret

pre_switch_to_foreground	endp


;---------------------------Public-Routine-----------------------------;
; pre_switch_to_background
;
; This function is called when switching to the background, before
; any device-specific code has executed.
;
; Entry:
;	DS = Data
; Returns:
;	DS = Data
; Registers Preserved:
;	AH,BX,CX,DX,SI,DI,BP,DS,ES,FLAGS
; Registers Destroyed:
;	AL
; Calls:
; History:
;	Mon 05-Oct-1987 20:17:08 -by-  Bob Grudem [bobgru]
;	Wrote it.
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,Data
	assumes es,nothing

pre_switch_to_background	proc	near

	mov	al,IS_BUSY		;disable mouse cursor drawing code
	cli
	xchg	al,screen_busy		;say it's busy
	xchg	al,old_screen_busy	;store old flag semaphore value
	sti

	ret

pre_switch_to_background	endp


;---------------------------Public-Routine-----------------------------;
; post_switch_to_foreground
;
; This function is called when switching to the foreground, after
; any device-specific code has executed.
;
; Entry:
;	DS = Data
; Returns:
;	DS = Data
; Registers Preserved:
;	AH,BX,CX,DX,SI,DI,BP,DS,ES,FLAGS
; Registers Destroyed:
;	AL
; Calls:
; History:
;	Mon 05-Oct-1987 20:17:08 -by-  Bob Grudem [bobgru]
;	Wrote it.
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,Data
	assumes es,nothing

post_switch_to_foreground	proc	near

	cli
	mov	al,old_screen_busy	;reenable mouse cursor drawing code
	xchg	al,screen_busy		;set semaphore to old value
	sti
	call	cursor_kludge
	ret

post_switch_to_foreground	endp


;---------------------------Public-Routine-----------------------------;
; post_switch_to_background
;
; This function is called when switching to the background, after
; any device-specific code has executed.
;
; Entry:
;	DS = Data
; Returns:
;	DS = Data
; Registers Preserved:
;	AX,BX,CX,DX,SI,DI,BP,DS,ES,FLAGS
; Registers Destroyed:
;	None
; Calls:
; History:
;	Mon 05-Oct-1987 20:17:08 -by-  Bob Grudem [bobgru]
;	Wrote it.
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,Data
	assumes es,nothing

post_switch_to_background	proc	near

	ret

post_switch_to_background	endp


;---------------------------Public-Routine-----------------------------;
; disable_switching
;
; This function is called whenever we need to prevent a screen switch
; from occuring.
;
; Entry:
;	DS = Data
; Returns:
;	DS = Data
; Registers Preserved:
;	SI,DI,BP,DS
; Registers Destroyed:
;	AX,BX,CX,DX,ES,FLAGS
; Calls:
;	ScreenSwitchEnable in keybaord.drv
; History:
;	Sun 20-Sep-1987 19:00:13 -by-  Walt Moore [waltm]
;	Added switch_control flag.
;
;	Wed 16-Sep-1987 20:17:08 -by-  Bob Grudem [bobgru]
;	Wrote it.
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,Data
	assumes es,nothing

	public	disable_switching

disable_switching proc	near

	push	es
	mov	al,switch_control	;Must have correct DOS version
	test	al,DO_SWITCHING
	jz	disable_switching_exit
	test	al,DISABLE_HOT_KEY	;Only call keyboard driver if
	jz	show_switch_disabled	;  we need to
	xor	ax,ax
	cCall	ScreenSwitchEnable,<ax>

show_switch_disabled:
	or	switch_control,PREVENT_SWITCH

disable_switching_exit:
	pop	es
	ret

disable_switching endp
page

;---------------------------Public-Routine-----------------------------;
; enable_switching
;
; This function is called whenever we can allow a screen group switch.
;
; Entry:
;	DS = Data
; Returns:
;	DS = Data
; Registers Preserved:
;	SI,DI,BP,DS
; Registers Destroyed:
;	AX,BX,CX,DX,ES,FLAGS
; Calls:
;	ScreenSwitchEnable in keybaord.drv
; History:
;	Sun 20-Sep-1987 19:00:13 -by-  Walt Moore [waltm]
;	Added switch_control flag.
;
;	Wed 16-Sep-1987 20:17:08 -by-  Bob Grudem [bobgru]
;	Wrote it.
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,Data
	assumes es,nothing

	public	enable_switching

enable_switching proc	near

	push	es
	mov	al,switch_control
	and	al,not PREVENT_SWITCH
	mov	switch_control,al
	test	al,DISABLE_HOT_KEY
	jz	enable_switching_exit
	mov	ax,0FFFFh
	cCall	ScreenSwitchEnable,<ax>

enable_switching_exit:
	pop	es
	ret

enable_switching endp

sEnd	Code
page

createSeg _INIT,InitSeg,word,public,CODE
sBegin	InitSeg
assumes cs,InitSeg


;---------------------------Public-Routine-----------------------------;
; hook_int_2Fh
;
; Installs a link in the 2Fh multiplex interrupt chain to watch for
; calls to the driver to save or restore the state of the display
; hardware before a context switch.
;
; This function is called whenever the driver recieves an enable call.
;
; Entry:
;	DS = Data
; Returns:
;	DS = Data
; Registers Preserved:
;	BX,CX,DX,SI,DI,BP,DS,ES
; Registers Destroyed:
;	AX,flags
; Calls:
;	none
; History:
;	Mon 05-Oct-1987 20:13:46 -by-  Walt Moore [waltm]
;	Moved getting the repaint procedure address to this
;	routine.
;
;	Sun 20-Sep-1987 19:00:13 -by-  Walt Moore [waltm]
;	Added addressibility to the Code segment where stuff
;	is stored.  Added switch_control flag.
;
;	Wed 16-Sep-1987 20:17:08 -by-  Bob Grudem [bobgru]
;	Wrote it.
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,Data
	assumes es,nothing

		public	hook_int_2Fh
hook_int_2Fh	proc	near

	push	bx
	push	cx
	push	dx
	push	ds
	push	es

;	See if we already have repaint_addr.
	mov	ax,wptr [repaint_addr][0]
	or	ax,wptr [repaint_addr][2]
	jnz	hook_int_2f_repaint_addr
;
; Need module handle to pass to GetProcAddress.
;
        mov     ax,DataOFFSET user_string
	farPtr	module_name,ds,ax
	cCall	GetModuleHandle,<module_name>
	
;	Get the value of repaint_addr.
IFDEF DEBUG
%OUT take this out!!!
int 1
ENDIF
	xchg	ax,bx
	mov	ax,REPAINT_EXPORT_INDEX
	cwd
	farPtr	func_number,dx,ax
	cCall	GetProcAddress,<bx,func_number>
	mov	wptr [repaint_addr][0],ax
	mov	wptr [repaint_addr][2],dx

; Need module handle to pass to GetProcAddress.
	mov	ax,DataOFFSET gdi_string
	farPtr	module_name,ds,ax
	cCall	GetModuleHandle,<module_name>
	
; Get the value of DEVICECOLORMATCH address.
	xchg	ax,bx
	mov	ax,DEVICECOLORMATCH_EXPORT_INDEX
	cwd
	farPtr	func_number,dx,ax
	cCall	GetProcAddress,<bx,func_number>
	mov	wptr [GetColor_addr][0],ax
	mov	wptr [GetColor_addr][2],dx

hook_int_2f_repaint_addr:

	mov	al,switch_control	;Only hook if we have the correct DOS
	xor	al,INT_2F_HOOKED
	test	al,DO_SWITCHING+INT_2F_HOOKED
	jz	hook_int_done		;Don't need to hook it

	cli	
	or	switch_control,INT_2F_HOOKED
	xor	ax,ax

;----------------------------------------------------------------------------;
; have to change the vectors properly to vaoid GP faults in protected mode   ;
;----------------------------------------------------------------------------;

	push	ds			; save
	mov	ax,CodeBASE		; get the CS selector
	cCall	AllocCSToDSAlias,<ax>	; get a data segment alias
	mov	ds,ax
	push	ax			; save for later FreeSelector call
        assumes ds,Code                 ; do this to save address in CS

	mov	ax,3500h+INT_MULT	; get the vector
	int	21h	
	
	mov	wptr prev_int_2Fh[0],bx
	mov	wptr prev_int_2Fh[2],es

	mov	dx,CodeOFFSET screen_switch_hook
	mov	ax,CodeBASE
	mov	ds,ax
	assumes ds,nothing

	mov	ax,2500h+INT_MULT	; set the vector
	int	21h

	cCall	FreeSelector		; selector is on the stack

	pop	ds			; get back own data segment
	assumes	ds,Data

	sti

hook_int_done:
	pop	es
	assumes es,nothing
	pop	ds
	assumes ds,nothing
	pop	dx
	pop	cx
	pop	bx
	ret

hook_int_2Fh	endp
page

;---------------------------Public-Routine-----------------------------;
; restore_int_2Fh
;
; If we installed ourselves into int 2Fh, we'll restore the previous
; vector.
;
; This function is called whenever the driver receives a disable call.
;
; Entry:
;	ES = Data
; Returns:
;	ES = Data
; Registers Preserved:
;	BX,CX,DX,SI,DI,BP,DS
; Registers Destroyed:
;	AX,ES,flags
; Calls:
;	none
; History:
;	Sun 20-Sep-1987 19:00:13 -by-  Walt Moore [waltm]
;	Added addressibility to the Code segment where stuff
;	is stored.  Added switch_control flag.
;
;	Wed 16-Sep-1987 20:17:08 -by-  Bob Grudem [bobgru]
;	Wrote it.
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,Data

		public	restore_int_2Fh

restore_int_2Fh proc	near

	test	switch_control,INT_2F_HOOKED
	jz	restore_done
	cli	
	and	switch_control,not INT_2F_HOOKED

	push	es
	push	ds

	mov	ax,CodeBASE		; get the code address
	cCall	AllocCSToDSAlias,<ax>	; get a data alias out of it
	mov	es,ax
	push	ax			; save for FreeSelector call
	assumes es,Code

	push	dx			; save
	lds	dx,prev_int_2Fh		; get the saved vector
	mov	ax,252fh		; set vector 2F
	int	21h
	pop	dx			; restore

	sti

	cCall	FreeSelector		; selector is on the stack

        pop     ds
	assumes ds,nothing
	pop	es
	assumes	es,Data

restore_done:
	ret

restore_int_2Fh endp
page

;---------------------------Public-Routine-----------------------------;
; driver_initialization
;
; Windows display driver initialization.  All display drivers which
; require special support for screen group switching will have this
; as their load time entry point.  This function will perform its
; initialization, then call the device specific initialization code.
;
; The DOS version number is checked, and the internal flags for
; screen group switching are set.
;
; Entry:
;	CX = size of heap
;	DI = module handle
;	DS = automatic data segment
;	ES:SI = address of command line (not used)
; Returns:
;	DS = Data
; Registers Preserved:
;	SI,DI,BP,DS
; Registers Destroyed:
;	AX,BX,CX,DX,ES,FLAGS
; Calls:
;	none
; History:
;	Sun 20-Sep-1987 19:00:13 -by-  Walt Moore [waltm]
;	Wrote it.
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	assumes ds,Data
	assumes es,nothing

cProc	driver_initialization,<FAR,PUBLIC>,<si,di>

cBegin
	mov	ah,30h			;Check DOS version number
        int     21h
	xchg	al,ah			;Correct order for comparing
	xor	bl,bl			;Accumulate flags here
	cmp	ax,DOS_VERSION		;Earliest DOS we must support (10.0)			 ;10 or higher means OS/2
	jb	dont_support_switching
	or	bl,DO_SWITCHING 	;Have to handle screen group switches
	cmp	ax,HOT_KEY_VERSION
	jb	save_switch_control
	or	bl,DISABLE_HOT_KEY	;Can disable hot key

save_switch_control:
	mov	switch_control,bl

dont_support_switching:
	call	dev_initialization	;Device specific initialization

cEnd

sEnd	InitCode
end	driver_initialization

