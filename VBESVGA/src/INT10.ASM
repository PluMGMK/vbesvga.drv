page            ,132
title           Wrapper for int 10h allowing use of Real-Mode segments
.286c


.xlist
include	INT31.INC
include CMACROS.INC
include MACROS.MAC	; for FARPOINTER
include GDIDEFS.INC	; for DISPLAY to work
include DISPLAY.INC	; for WF_*
.list


subttl  Static & External Data Definitions -- DATA SEGMENT
page +

PM_STACK_LEN	equ 406h

externA		__WinFlags		;LSB set --> we're in protect mode
externFP	GlobalDosAlloc
externFP	AllocCSToDSAlias	; change a CS selector to DS
externFP	FreeSelector		; free the selector

sBegin  	Data

public	int10h_es,int10h_ds
int10h_es	dw ?
int10h_ds	dw ?
int10h_retflags	dw ?	; temp location to store flags we pop off the stack

; Real-Mode stack for int 10h calls
Int10Stack	FARPOINTER <PM_STACK_LEN,?>
sEnd		Data

subttl  External Declarations -- Code Segment
page +
sBegin          Code
assumes         cs,Code

externW         _cstods                 ;in CURSOR.ASM

subttl          Perform an int 10h from Protected Mode
page +

public	DoInt10h
DoInt10h	proc far
	push	ds
	push	es
	mov	ds,[_cstods]
	assumes	ds,Data

@@start_logic:
	; build RMCS on the stack
	push	[Int10Stack.sel]; SS
	push	[Int10Stack.off]; SP
	sub	sp,4	; CS:IP = garbage (ignored)
	push	0	; GS = 0
	push	0	; FS = 0
	push	[int10h_ds]
	push	[int10h_es]
	pushf		; setup the flags correctly

@@286_pushad:
	; Default to 286 code, to be overwritten on a 386
	push	0
	push	ax
	push	0
	push	cx
	push	0
	push	dx
	push	0
	push	bx
	push	0
	push	0	; SP is reserved
	push	0
	push	bp
	push	0
	push	si
	push	0
	push	di

@@regs_pushed:
	push	ss
	pop	es
	mov	di,sp
	mov	word ptr es:[di+0Ch],0	; ESP is reserved
	mov	word ptr es:[di+0Ch+2],0; ESP is reserved

	mov	ax,(Int31_Trans_Serv SHL 8) + Trans_Sim_Int
	mov	bx,10h	; int 10h, don't reset int controller / A20
	xor	cx,cx	; don't copy words from stack
	int	31h

@@286_popad:
	; Default to 286 code, to be overwritten on a 386
	pop	di
	add	sp,2
	pop	si
	add	sp,2
	pop	bp
	add	sp,6	; SP is reserved
	pop	bx
	add	sp,2
	pop	dx
	add	sp,2
	pop	cx
	add	sp,2
	pop	ax
	add	sp,2

@@regs_popped:
	pop	[int10h_retflags]
	pop	[int10h_es]
	pop	[int10h_ds]

	add	sp,0Ch
	push	[int10h_retflags]
	popf		; set the flags as necessary

	pop	es
	pop	ds
	assumes	ds,nothing
	ret
DoInt10h	endp

sEnd	Code

subttl          Setup optimal DoInt10h for current machine
page +

createSeg _INIT,InitSeg,byte,public,CODE
sBegin  InitSeg
assumes cs,InitSeg

public	SetupInt10h
SetupInt10h	proc near
	push	es
	push	si
	push	di

	; allocate a 1-kiB stack in low memory for int 10h calls
	cCall	GlobalDosAlloc,<0,PM_STACK_LEN>	; zero-pad to dword
	test	ax,ax
	jz	@@done

	mov	ax,seg Int10Stack
	mov	es,ax
	assumes	es,Data

	mov	[Int10Stack.sel],dx

	mov	ax,__WinFlags
	test	al,WF_PMODE	;are we in protect mode?
	jz	@@real

	test	al,WF_CPU286	; are we on a 286 processor?
	jnz	@@ok		; no need to change anything then

	; On a 386, so replace the long push/pop sequences with pushad/popad
	push	seg DoInt10h
	cCall	AllocCSToDSAlias	; param pushed just above
	test	ax,ax
	jz	@@done
	mov	es,ax
	assumes	es,Code

	mov	di,CodeOFFSET @@286_pushad
	mov	ax,6066h; PUSHAD
	stosw

	mov	ax,CodeOFFSET @@regs_pushed
	sub	ax,di	; get length of needed jump
	sub	ax,2	; subtract length of jmp instruction itself
	mov	ah,al
	mov	al,0EBh	; JMP short
	stosw

	mov	di,CodeOFFSET @@286_popad
	mov	ax,6166h; POPAD
	stosw

	mov	ax,CodeOFFSET @@regs_popped
	sub	ax,di	; get length of needed jump
	sub	ax,2	; subtract length of jmp instruction itself
	mov	ah,al
	mov	al,0EBh	; JMP short
	stosw

	; free the alias
	cCall	FreeSelector,<es>
	assumes	es,nothing
	jmp	@@ok

@@real:
	mov	si,seg DoInt10h
	mov	es,si
	assumes	es,Code

	lea	si,DoInt10h_Real
	mov	di,CodeOFFSET @@start_logic
	mov	cx,size DoInt10h_Real
	cld
	rep	movs byte ptr es:[di],cs:[si]
@@ok:
	assumes	es,nothing
	mov	ax,1
@@done:
	pop	di
	pop	si
	pop	es
	ret
SetupInt10h	endp


DoInt10h_Real	proc far
	assumes	cs,Code			; this gets copied into Code,
	assumes	ds,Data			; at @@start_logic (which has DS=Data)

	mov	es,[int10h_es]
	mov	ds,[int10h_ds]
	assumes	ds,nothing
	int	10h

	push	ds
	mov	ds,[_cstods]
	assumes	ds,Data
	pop	[int10h_ds]
	mov	[int10h_es],es

	pop	es
	pop	ds
	ret
DoInt10h_Real	endp

sEnd	 InitSeg
end
