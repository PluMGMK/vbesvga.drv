	page	,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	CHKSTK.ASM
;
; This file contains the stack checking function used by display drivers.
;
; Created: 16-Jan-1987
; Author:  Walt Moore [waltm]
;
; Copyright (c) 1984-1987 Microsoft Corporation
;
; Exported Functions:	none
;
; Public Functions:	my_check_stack
;
; Public Data:		none
;
; General Description:
;
;	A stack probe will be performed to see if the requested amount
;	of stack space is available.  If not, either a RIP will be
;	performed, or an error returned, based on the DEBUG flag.
;
; Restrictions:
;
;-----------------------------------------------------------------------;


	.xlist
	include cmacros.inc
	include macros.mac
	include int3.inc
	.list


	ifdef	DEBUG
	externFP FatalExit		;If debugging, error will abort
	endif


;	Define the stack overflow error code.

stack_overflow	equ	-1


;	The driver cannot link to the library containing the
;	definitions for the stack probe locations, so they
;	have to be defined here.

	public	stack_top
	public	stack_bot
	public	stack_min

stack_top	equ	000Ah		;Topmost location of stack
stack_bot	equ	000Eh		;Bottom  location of stack
stack_min	equ	000Ch		;Smaller top value


sBegin	Code
assumes cs,Code
page
;-----------------------------Public-Routine----------------------------;
; my_chkstk
;
; Our own stack probe which will allow us to gracefully abort out
; of the display driver routines if there isn't enough stack space.
; Routines like STRBLT take a lot of space, and should return an
; error if not enough room to perform the operation instead of
; trashing or ripping.
;
; Entry:
;	AX = Number of bytes of stack space needed
; Returns:
;	SP = new stack top if room
;	'C' clear
;	SS:stack_min = new low if achieved
; Error Returns:
;	'C' set if no room
;	DX:AX = 8000:0000h
;	FatalExit if DEBUG enabled
; Registers Destroyed:
;	AX,BX,Flags
;	DX if no room
; Registers Preserved:
;	CX,SI,DI,BP,DS,ES
; Calls:
;	FatalExit if DEBUG enabled
; History:
;	Fri 16-Jan-1987 19:59:47 -by-  Walt Moore [waltm]
;	Initial version
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; DWORD my_check_stack(size)
; int size;
; {
;   if ((SP =< size) || ((SP-size) < stack_top))
;   {
;	stack_min = stack_top;
;	return(0x800000000L);
;   }
;   if (new_SP < new_minimun)
;	stack_min = new_SP;
;   SP = new_SP;
;   return();
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,nothing

cProc	my_check_stack,<NEAR,PUBLIC>

cBegin	<nogen>

	pop	bx			;Save return address
	sub	ax,sp			;See if room
	jnc	no_room 		;No room, return error
	neg	ax			;Make it positive for other checks
	cmp	ss:stack_top,ax 	;Used up too much stack?
	ja	no_room 		;  Yes, return error
	cmp	ss:stack_min,ax 	;Lowest we've received?
	jbe	not_smaller		;  No
	mov	ss:stack_min,ax 	;  Yes, set new minimum

not_smaller:
	mov	sp,ax			;Set new stack
	clc				;Clear 'C' to show room
	jmp	bx			;To caller

no_room:
	mov	ax,ss:stack_top 	;Show user that all of the
	mov	ss:stack_min,ax 	;  stack has been used

	ifdef	DEBUG
	mov	ax,stack_overflow	;Stack overflow
	push	bx			;Save return address
	cCall	FatalExit,<ax>
	pop	bx
	endif				;Returning to caller

	xor	ax,ax			;Set error code(s)
	mov	dx,8000h
	stc				;Show no room
	jmp	bx

cEnd	<nogen>

sEnd	Code
page

createSeg _LINES,LineSeg,word,public,CODE
sBegin	LineSeg
assumes cs,LineSeg

;-----------------------------Public-Routine----------------------------;
; LineSeg_check_stack
;
; Our own stack probe which will allow us to gracefully abort out
; of the display driver routines if there isn't enough stack space.
; Routines like STRBLT take a lot of space, and should return an
; error if not enough room to perform the operation instead of
; trashing or ripping.
;
; Entry:
;	AX = Number of bytes of stack space needed
; Returns:
;	SP = new stack top if room
;	'C' clear
;	SS:stack_min = new low if achieved
; Error Returns:
;	'C' set if no room
;	DX:AX = 8000:0000h
;	FatalExit if DEBUG enabled
; Registers Destroyed:
;	AX,BX,Flags
;	DX if no room
; Registers Preserved:
;	CX,SI,DI,BP,DS,ES
; Calls:
;	FatalExit if DEBUG enabled
; History:
;	Fri 16-Jan-1987 19:59:47 -by-  Walt Moore [waltm]
;	Initial version
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; DWORD my_check_stack_nr(size)
; int size;
; {
;   if ((SP =< size) || ((SP-size) < stack_top))
;   {
;	stack_min = stack_top;
;	return(0x800000000L);
;   }
;   if (new_SP < new_minimun)
;	stack_min = new_SP;
;   SP = new_SP;
;   return();
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,nothing

cProc	LineSeg_check_stack ,<NEAR,PUBLIC>

cBegin	<nogen>

	pop	bx			;Save return address
	sub	ax,sp			;See if room
	jnc	no_room_ls		;No room, return error
	neg	ax			;Make it positive for other checks
	cmp	ss:stack_top,ax 	;Used up too much stack?
	ja	no_room_ls		;  Yes, return error
	cmp	ss:stack_min,ax 	;Lowest we've received?
	jbe	not_smaller_ls		;  No
	mov	ss:stack_min,ax 	;  Yes, set new minimum

not_smaller_ls:
	mov	sp,ax			;Set new stack
	clc				;Clear 'C' to show room
	jmp	bx			;To caller

no_room_ls:
	mov	ax,ss:stack_top 	;Show user that all of the
	mov	ss:stack_min,ax 	;  stack has been used

ifdef	DEBUG
	mov	ax,stack_overflow	;Stack overflow
	push	bx			;Save return address
	cCall	FatalExit,<ax>
	pop	bx
endif					;Returning to caller

	xor	ax,ax			;Set error code(s)
	mov	dx,8000h
	stc				;Show no room
	jmp	bx

cEnd	<nogen>

sEnd	LineSeg
page

createSeg _SCANLINE,ScanlineSeg,word,public,CODE
sBegin	ScanlineSeg
assumes cs,ScanlineSeg

;-----------------------------Public-Routine----------------------------;
; ScanlineSeg_check_stack
;
; Our own stack probe which will allow us to gracefully abort out
; of the display driver routines if there isn't enough stack space.
; Routines like STRBLT take a lot of space, and should return an
; error if not enough room to perform the operation instead of
; trashing or ripping.
;
; Entry:
;	AX = Number of bytes of stack space needed
; Returns:
;	SP = new stack top if room
;	'C' clear
;	SS:stack_min = new low if achieved
; Error Returns:
;	'C' set if no room
;	DX:AX = 8000:0000h
;	FatalExit if DEBUG enabled
; Registers Destroyed:
;	AX,BX,Flags
;	DX if no room
; Registers Preserved:
;	CX,SI,DI,BP,DS,ES
; Calls:
;	FatalExit if DEBUG enabled
; History:
;	Fri 16-Jan-1987 19:59:47 -by-  Walt Moore [waltm]
;	Initial version
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; DWORD my_check_stack_nr(size)
; int size;
; {
;   if ((SP =< size) || ((SP-size) < stack_top))
;   {
;	stack_min = stack_top;
;	return(0x800000000L);
;   }
;   if (new_SP < new_minimun)
;	stack_min = new_SP;
;   SP = new_SP;
;   return();
; }
;-----------------------------------------------------------------------;

	assumes ds,nothing
	assumes es,nothing

cProc	ScanlineSeg_check_stack,<NEAR,PUBLIC>

cBegin	<nogen>

	pop	bx			;Save return address
	sub	ax,sp			;See if room
	jnc	no_room_sl		;No room, return error
	neg	ax			;Make it positive for other checks
	cmp	ss:stack_top,ax 	;Used up too much stack?
	ja	no_room_sl		;  Yes, return error
	cmp	ss:stack_min,ax 	;Lowest we've received?
	jbe	not_smaller_sl		;  No
	mov	ss:stack_min,ax 	;  Yes, set new minimum

not_smaller_sl:
	mov	sp,ax			;Set new stack
	clc				;Clear 'C' to show room
	jmp	bx			;To caller

no_room_sl:
	mov	ax,ss:stack_top 	;Show user that all of the
	mov	ss:stack_min,ax 	;  stack has been used

ifdef	DEBUG
	mov	ax,stack_overflow	;Stack overflow
	push	bx			;Save return address
	cCall	FatalExit,<ax>
	pop	bx
endif					;Returning to caller

	xor	ax,ax			;Set error code(s)
	mov	dx,8000h
	stc				;Show no room
	jmp	bx

cEnd	<nogen>

sEnd	ScanlineSeg


;ifdef	PUBDEFS
	public	not_smaller
	public	no_room
	public	not_smaller_ls
	public	no_room_ls
	public	not_smaller_sl
	public	no_room_sl
;endif

end

