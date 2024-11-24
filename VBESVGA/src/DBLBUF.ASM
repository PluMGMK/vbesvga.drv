
;
;	FILE:	dblbuf.asm
;	DATE:	31 October 2024
;	AUTHOR: PluMGMK
;
;	This module contains code and data to support double-buffering for
;	improved performance. In fact, this is a full implementation of a
;	"hardware cursor" which is really a software cursor that only gets
;	drawn on the front buffer.
;

TIME_PERIODIC	equ 1		;from MMSYSTEM.H

incDevice = 1			;Include control for gdidefs.inc

	.xlist
	include CMACROS.INC
	include MACROS.MAC
	include GDIDEFS.INC
	include int3.inc
	include windefs.inc
	include	cursor.inc
	.list

	externFP AllocSelector
	externFP FreeSelector
	externFP SetSelectorBase
	externFP SetSelectorLimit
	externFP GetSelectorBase
	externFP GetSelectorLimit
	externFP PrestoChangeoSelector
	externFP LoadLibrary
	externFP GetProcAddress

sBegin	Data

; Selectors
BackBufSel	dw ?
FrontBufSel	dw ?

; Handle to back-buffer memory block
BackBufDPMIHdl	dd ?

; How much data to transfer when swapping buffers
BackBufSize	dd ?

; VTDAPI entry point (preferred to MMSYSTEM if available)
VTDAPIEntry	dd ?

; Function pointers in MMSYSTEM.DLL
TimeGetDevCaps	dd ?
TimeBeginPeriod	dd ?
TimeEndPeriod	dd ?
TimeSetEvent	dd ?
TimeKillEvent	dd ?

; Event handle for fast (MMSYSTEM-based) timer
fast_timer_hdl	dw 0
; Standard-Mode IRQ handler segment for TIMER.DRV:
; if this becomes invalid, we stop the fast timer!
fast_timer_irqseg dw 0

; Approximate time in milliseconds taken to run swap_buffers
frame_budget	dw -1
sb_period_ms	dw ?	; swap_buffers period in milliseconds
max_budget	dw ?	; maximum allowable value for frame_budget

; User-specified refresh rate and maximum frame budget percentage
public	desired_fps,max_budget_pct
desired_fps	db 60
max_budget_pct	db 50

externW		cursor_funcs		; in CURSOR.ASM
externW		cursor_xdraw		; in CURSOR.ASM
externW		cursor_ydraw		; in CURSOR.ASM
externW		save_screen_y		; in SWCURS.ASM
externW		save_screen_x		; in SWCURS.ASM
externW		save_screen_yclip	; in SWCURS.ASM
externW		save_screen_xclip	; in SWCURS.ASM
externD		save_screen_longaddr	; in SWCURS.ASM
externW		save_screen_height	; in SWCURS.ASM
externW		save_screen_width	; in SWCURS.ASM
externW		swcursor_data		; in SWCURS.ASM

; cursor functions for "double-buffering cursor" implementation
dbcursor_funcs	DW	dbcursor_set, dbcursor_move, dbcursor_check
p_cursor_off	DW	dbcursor_off, dbcursor_exclude, dbcursor_unexclude
end_dbcursor_funcs label word

sEnd	Data


sBegin	Code
	assumes cs,Code

EXTRN   MemoryWidth:word
externD		VESALinearBuf		; in VESAFNS.ASM
externNP	common_cursor_set	; in SWCURS.ASM
externNP	swcursor_setaddr	; in SWCURS.ASM
externW		pxbytes			; in SWCURS.ASM
externW		_cstods			; in CURSOR.ASM

externFP	enable_wrcomb		; in MTRR.ASM
externFP	enable_wrthru		; in MTRR.ASM
externFP	disable_wrcomb		; in MTRR.ASM

; cursor functions
dbcursor_set	proc near
;	PARMS:
;       ds      Data segment
;	es:si	ptr to cursorShape structure
	assumes ds,Data
	assumes es,nothing

	; use the software cursor buffer to hold the data
	call	common_cursor_set
	; recalculate where to draw the cursor
	call	swcursor_setaddr

	; check if we have a stale TIMER.DRV segment
	mov	ax,[fast_timer_irqseg]
	test	ax,ax
	jz	@F

	; IRQ segment is already known to us. Is it still valid?
	db	0Fh,02,0C0h		;lar ax,ax
	jz	@F			; valid --> keep going

	; force this to zero and don't try to restart it
	mov	[fast_timer_hdl],0
	ret

@@:	; now check if the fast (MMSYSTEM-based) timer is
	; running, and attempt to set it up if it isn't.
	cmp	[fast_timer_hdl],0
	jz	start_fast_timer	; need to set up the fast timer
	ret
dbcursor_set	endp

; Attempt to start the fast timer. May fail, and if it does that's OK.
; We will try again at the next call to dbcursor_set.
start_fast_timer proc near
	push	es	; destroyed by WinAPI calls

	cCall	TimeBeginPeriod,<[sb_period_ms]>
	test	ax,ax
	jnz	@F	; failed if NOT zero

	call	find_frame_budget
	cmp	ax,[max_budget]
	jg	too_expensive

	lea	ax,fast_timer_callback
	cCall	TimeSetEvent,<[sb_period_ms],[sb_period_ms],cs,ax,0,0,TIME_PERIODIC>
	mov	[fast_timer_hdl],ax

	; find out who's handling timer IRQs now so we can track
	; when they're unloaded...
	mov	ax,3508h; DOS: get interrupt vector 08
	int	21h
	mov	[fast_timer_irqseg],es
	jmp	@F

too_expensive:
	int	3
	call	far ptr cancel_double_buf

@@:	pop	es
	; fall through to ret below!
start_fast_timer endp

dbcursor_off	proc near
	; this is a no-op as cursor_flags is maintained in CURSOR.ASM
	; and tells us whether or not to draw anything
dbcursor_exclude:
dbcursor_unexclude:
	; also no-ops as the double-buffered cursor doesn't need to
	; be excluded (since all other blits are done onto the back
	; buffer!)
	ret
dbcursor_off	endp

dbcursor_move	proc near
	; update save_screen_{x,y} as they are used in swcursor_setaddr
	mov	ax,[cursor_xdraw]
	mov	dx,[cursor_ydraw]
	mov	[save_screen_x],ax
	mov	[save_screen_y],dx

	; calculate where to draw the cursor
	call	swcursor_setaddr
	ret
dbcursor_move	endp

start_fast_timer_far	proc far
	call	start_fast_timer
	ret
start_fast_timer_far	endp

dbcursor_check	proc near
	; This is called every 54.925 milliseconds by a system timer.
	; We'll take that in a pinch, but once the faster MMSYSTEM
	; timer becomes available, then this slow function doesn't
	; need to do anything anymore.
	cmp	[fast_timer_hdl],0
	jz	swap_buffers
	ret
dbcursor_check	endp

; This initially gets called every 54.925 milliseconds, and once we
; get MMSYSTEM / VTDAPI up and running, every 16 milliseconds.
; Its job is to copy the entire back buffer onto the front buffer,
; while putting the cursor over it.
; FIXME: On real H/W, for large buffers, this is REALLY expensive,
; and it negates any performance benefit. We need to look into
; modifying some MTRRs (with the help of the VxD) to put the front
; buffer in write-combining mode on the CPU. This will mean that
; this function only writes to a cache buffer, which hopefully will
; make it return much quicker...
swap_buffers	proc near
	.386	; if we get this far we have a 386 (required for lin framebuf)
	pushad	; we will use all the 386 registers!
	push	es
	push	fs

	; We will use the registers like so:
	; AX  = Current word of cursor data
	; EBX = [UPPER HALF] Next cursor scanline pointer
	; BH  = Cursor scanlines remaining
	; BL  = Cursor byte-pair width (clipped)
	; ECX = Current counter
	; EBP = [UPPER HALF] MemoryWidth - Cursor byte-pair width
	; BP  = Cursor byte width (total, byte-pair width * 2)
	; ESI = Pointer to back buffer or cursor data
	; EDI = Position in front/back buffer
	; Segment registers:
	; DS = Data
	; ES = Front Buffer
	; FS = Back Buffer

	mov	es,[FrontBufSel]
	mov	fs,[BackBufSel]
	; point at the start of the front buffer
	cld
	xor	edi,edi

	; assume no cursor scanlines to draw --> zero EBX
	mov	ebx,edi
	test	[cursor_flags],YES_CURSOR
	jz	@@no_cursor

	; Set BX to the beginning of the cursor data, modulo clipping...
	; Start by converting yclip in scanlines to a pixel offset:
	imul	bx,[save_screen_yclip],CURSOR_WIDTH
	; Add the xclip in pixels:
	add	bx,[save_screen_xclip]
	; Convert to byte pairs
	imul	bx,[pxbytes]
	; Then to bytes
	shl	bx,1
	; Finally add the pointer to the cursor data itself
	lea	bx,swcursor_data[bx]

	; Now move the whole thing into the upper half!
	shl	ebx,10h

	; calculate the full and clipped byte widths of the cursor
	mov	bh,CURSOR_WIDTH
	mov	bl,byte ptr [save_screen_width]
	; multiply BH and BL at the same time - safe since the maximum result
	; for both bytes is 80h, so this will never carry!
	imul	bx,[pxbytes]
	; BH is now the total cursor byte width, which belongs in BP
	movzx	ebp,bh
	; Convert lower half of EBP to full byte width of the cursor data
	; (since each byte of bitmap data is doubled into an AND and a XOR byte)
	shl	bp,1

	; Get the MemoryWidth minus cursor width for the upper half of EBP
	mov	ax,[MemoryWidth]
	xor	bh,bh	; BX becomes full byte-pair width of cursor
	sub	ax,bx
	; Move into upper half
	shl	eax,10h
	; Then into EBP
	or	ebp,eax
	; Now set BH as indicated above:
	mov	bh,byte ptr [save_screen_height]

	; Set the counter and start the first round of copying
	mov	ecx,[save_screen_longaddr]
@@copy_loop:
	; We're moving the back to the front buffer, so the source and dest
	; offsets are identical :)
	mov	esi,edi

	shr	ecx,1
	jnc	@F
	; copy straggling byte
	movs	byte ptr es:[edi], byte ptr fs:[esi]
; 386 bug. 32-bit string instruction must be followed by a 32-bit instruction.
	db	67h
	nop
@@:	shr	ecx,1
	jnc	@F
	; copy straggling word
	movs	word ptr es:[edi], word ptr fs:[esi]
; 386 bug. 32-bit string instruction must be followed by a 32-bit instruction.
	db	67h
	nop
@@:	; copy everything else dword-by-dword
	rep	movs dword ptr es:[edi], dword ptr fs:[esi]
; 386 bug. 32-bit string instruction must be followed by a 32-bit instruction.
	db	67h
	nop

	; copy loop done - any cursor scanlines left?
	test	bh,bh
	jz	@@done

	; right, switch over to loading the cursor data
	; 16-bit source address and counter registers are sufficient for this!
	movzx	cx,bl	; this counts byte PAIRS!
	mov	esi,ebx
	shr	esi,10h	; pointer was in upper half of EBX

	; loop over byte pairs
	jcxz	@@cursor_scanline_done
@@:	lodsw
	and	al,fs:[edi]		;read byte from back buffer
	xor	al,ah
	stos	byte ptr es:[edi]	;write dword to front buffer
	loop	@B

@@cursor_scanline_done:
	dec	bh			; decrement scanline counter
	jz	@@no_cursor		; done with the cursor completely
	ror	ebx,10h			; get pointer into lower half
	add	bx,bp			; point at next scanline of cursor data
	ror	ebx,10h			; shove back into upper half

	; set the counter so we copy the rest of the buffer's current scanline
	mov	ecx,ebp
	shr	ecx,10h			; counter was in upper half of EBP
	jmp	@@copy_loop

@@no_cursor:
	; done with the cursor altogether (or had none in the first place),
	; so just chug through the rest of the buffer copy and we're done
	mov	ecx,[BackBufSize]
	; account for any progress made so far
	sub	ecx,edi
	jmp	@@copy_loop

@@done:	pop	fs
	pop	es
	popad
	.286
	ret
swap_buffers	endp

; this gets called every 16 milliseconds - just call swap_buffers
cProc   fast_timer_callback,<FAR,PUBLIC,PASCAL,NODATA>,<ds>
        parmW	wTimerID
        parmW	wMsg
	parmD	dwUser	; not used
	parmD	dw1
	parmD	dw2
cBegin
	assumes	ds,nothing
	; do this to avoid having to declare an export...
	mov	ds,[_cstods]
	assumes	ds,Data
	call	swap_buffers
cEnd

; This calls p_cursor_off. Its purpose is to be called immediately after
; p_cursor_off gets set to point at the swcurs function, to ensure that
; a stale software cursor doesn't get stuck on the back buffer!
far_cursor_off	proc far
	call	[p_cursor_off]
	ret
far_cursor_off	endp

; Find the minimum timer period supported (used for counting the frame budget)
get_min_period	proc near
	mov	ax,[VTDAPIEntry.sel]
	test	ax,ax
	jz	@F

	; the VTDAPI way
	sub	sp,0Ch	; VTDAPI function 0 returns three dwords
	mov	ax,ss
	mov	es,ax
	mov	bx,sp
	xor	ax,ax	; function 0 gets version and capabilities
	call	[VTDAPIEntry]
	; check if successful
	cmp	ax,1	; sets CF if AX is zero (VTDAPI not working)
	; minimum period is the second dword returned
	mov	ax,ss:[bx+4]
	lea	sp,[bx+0Ch]
	ret

@@:	; the MMSYSTEM way
	sub	sp,4	; timeGetDevCaps returns two words
	mov	bx,sp
	; this call takes a long pointer to a buffer,
	; and the size, which needs to be exactly 4.
	cCall	TimeGetDevCaps,<ss,bx,4>
	; check if successful
	cmp	ax,1
	cmc		; sets CF if AX is NOT zero (MMSYSTEM error)
	; minimum period is the first word returned
	mov	ax,ss:[bx]
	lea	sp,[bx+4]
	ret
get_min_period	endp

; Find the approximate frame budget (i.e. how long it takes to run swap_buffers)
; in milliseconds, and return it. This can be used to decide to cancel double
; buffering, if it's eating up too much CPU time.
find_frame_budget proc near
	; value already stored?
	mov	ax,[frame_budget]
	test	ax,ax
	js	@F	; if negative, it means we need to calculate it...
	ret

@@:	; if we're already running the fast timer, this should not be done
	cmp	[fast_timer_hdl],0
	jz	@F
	int	3
	ret

@@:	; find out what resolution we can use
	call	get_min_period
	jnc	@F	; if we failed to find it, go no further
	sbb	ax,ax	; AX becomes -1 because CF is 1
	ret

@@:	; create a timer at the min resolution - note that we are passing
	; AX three times: as the period, the resolution AND the dwUser value!
	lea	bx,frame_budget_counter
	cCall	TimeSetEvent,<ax,ax,cs,bx,0,ax,TIME_PERIODIC>
	mov	[fast_timer_hdl],ax	; to prevent CheckCursor from calling swap_buffers
	test	ax,ax
	jnz	@F	; if NULL then go no further
	dec	ax	; AX becomes -1
	ret

@@:	; do the buffer swap with the counter timer running
	call	swap_buffers
	; done, so kill the counter
	cCall	TimeKillEvent,<[fast_timer_hdl]>
	; allow CheckCursor to run normally again
	mov	[fast_timer_hdl],0
	; increment the frame budget since it would have started at -1 when
	; this function was called, rather than zero
	inc	[frame_budget]

	mov	ax,[frame_budget]
	ret
find_frame_budget endp

; increment the frame budget counter as often as possible
cProc   frame_budget_counter,<FAR,PUBLIC,PASCAL,NODATA>,<ds>
        parmW	wTimerID
        parmW	wMsg
	parmD	dwPeriod
	parmD	dw1
	parmD	dw2
cBegin
	assumes	ds,nothing
	; do this to avoid having to declare an export...
	mov	ds,[_cstods]
	assumes	ds,Data
	mov	ax,word ptr [dwPeriod]
	add	[frame_budget],ax
cEnd

; Internal implementations of MMSYSTEM time functions, which call VTDAPI directly
; **THESE REQUIRE DS == Data**
cProc   IntBeginPeriod,<FAR,PUBLIC,PASCAL,NODATA>
        parmW	wPeriod
cBegin
	push	ss
	pop	es
	lea	bx,wPeriod
	mov	ax,1	; TimeBeginPeriod
	call	[VTDAPIEntry]
	; VTDAPI returns zero on failure and wPeriod on success,
	; whereas this function needs to return zero on success!
	xor	ax,[wPeriod]
cEnd

cProc   IntEndPeriod,<FAR,PUBLIC,PASCAL,NODATA>
        parmW	wPeriod
cBegin
	push	ss
	pop	es
	lea	bx,wPeriod
	mov	ax,2	; TimeEndPeriod
	call	[VTDAPIEntry]
	; VTDAPI returns zero on failure and wPeriod on success,
	; whereas this function needs to return zero on success!
	xor	ax,[wPeriod]
cEnd

cProc   IntSetEvent,<FAR,PUBLIC,PASCAL,NODATA>
	parmW	uDelay
	parmW	uResolution
	parmD	lpFunction
	parmD	dwUser
	parmW	uFlags
cBegin
	push	ss
	pop	es
	; This one's awkward because the arguments are passed to us in Pascal
	; order, whereas VTDAPI requires them in a buffer in C order...
	mov	dx,sp	; save this...
	.386		; we know we're in 386 Enhanced Mode so this is safe
	push	[uFlags]
	push	[dwUser]
	push	[lpFunction]
	push	[uResolution]
	push	[uDelay]
	.286
	mov	bx,sp
	mov	ax,5	; TimeSetEvent
	call	[VTDAPIEntry]
	; restore stack pointer
	mov	sp,dx
cEnd

cProc   IntKillEvent,<FAR,PUBLIC,PASCAL,NODATA>
        parmW	wTimerID
cBegin
	push	ss
	pop	es
	lea	bx,wTimerID
	mov	ax,6	; TimeKillEvent
	call	[VTDAPIEntry]
cEnd

sEnd	Code


.286

createSeg _INIT,InitSeg,word,public,CODE
sBegin	InitSeg

assumes	cs,InitSeg
assumes	ds,Data

mmsystem_dll		db "MMSYSTEM.DLL",0
TimeGetDevCaps_name	db "timeGetDevCaps",0
TimeBeginPeriod_name	db "timeBeginPeriod",0
TimeEndPeriod_name	db "timeEndPeriod",0
TimeSetEvent_name	db "timeSetEvent",0
TimeKillEvent_name	db "timeKillEvent",0

;--------------------------------------------------------------------------;
; setup_double_buf
;	prepares to start double-buffering, by getting the timer function
;	addresses and allocating memory for the back-buffer
; Entry:
;	DS	= Data
;	SI:DI	= int_phys_device structure
;	The driver must be setup to use a linear framebuffer
; Returns:
;	BackBufSel and FrontBufSel populated, pointing at respective buffers
; Error Returns:
;	BackBufSel and/or FrontBufSel NULL
; Registers Destroyed:
;	FLAGS
; Registers Preserved:
;	AX,BX,CX,DX,SI,DI,DS,ES,BP
; Calls:
;	LoadLibrary
;	GetProcAddress
;	int 31h
; History:
;	see Git
;--------------------------------------------------------------------------;
cProc	setup_double_buf,<NEAR,PUBLIC>,<es,ax,bx,cx,dx,si,di,bp>
cBegin
	; first of all check if double-buffering is already set up
	mov	ax,[BackBufSel]
	mov	bx,[FrontBufSel]
	or	ax,bx
	jz	@F
	jmp	setup_done

@@:	; Calculate the relevant periods
	mov	ax,1000		; milliseconds per second
	div	[desired_fps]	; AL := milliseconds per frame, AH := remainder
	xor	ah,ah		; we don't care about the remainder
	mov	[sb_period_ms],ax

	mul	[max_budget_pct]; AX := max frame budget in tens of microseconds
	mov	cl,100
	div	cl		; AL := max frame budget in milliseconds
	xor	ah,ah		; we don't care about the remainder
	mov	[max_budget],ax

	; If the frame budget breaks the bank, go no further.
	; Note that initially the frame budget is unknown, so the -1 will
	; always be "less than" the max. This is just to prevent the setup
	; code from rerunning after it's all been torn down...
	cmp	ax,[frame_budget]
	jge	@F
	jmp	setup_done

@@:	; First try to get the VTDAPI entry point - in 386 Enhanced Mode,
	; this will allow us to schedule fast timer events in a way that's
	; completely independent of USER.EXE, so it's a lot cleaner.
	xchg	dx,di		; hold onto our pointer
	mov	ax,1684h	; get VxD entry point
	mov	bx,0442h	; VTDAPI
	xor	di,di		; NULL default return value
	mov	es,di		; NULL default return value
	int	2Fh
	mov	ax,es
	test	ax,ax		; Still NULL?
	xchg	dx,di		; get back our pointer
	jz	@F

	mov	[VTDAPIEntry.off],dx
	mov	[VTDAPIEntry.sel],es

	; use our internal implementations of the MMSYSTEM time functions
	mov	dx,seg IntBeginPeriod
	lea	ax,IntBeginPeriod
	mov	[TimeBeginPeriod.off],ax
	mov	[TimeBeginPeriod.sel],dx
	lea	ax,IntEndPeriod
	mov	[TimeEndPeriod.off],ax
	mov	[TimeEndPeriod.sel],dx
	lea	ax,IntSetEvent
	mov	[TimeSetEvent.off],ax
	mov	[TimeSetEvent.sel],dx
	lea	ax,IntKillEvent
	mov	[TimeKillEvent.off],ax
	mov	[TimeKillEvent.sel],dx

	jmp	fnptrs_setup_done

@@:	; Load MMSYSTEM.DLL so we can use timer functions - this has to be
	; done at runtime, as DISPLAY.DRV cannot depend on DLLs other than
	; KERNEL!
	lea	ax,mmsystem_dll
	cCall	LoadLibrary,<cs,ax>
	cmp	ax,20h	; HINSTANCE_ERROR
	jnb	@F
	jmp	setup_done

@@:	; Get the required functions
	mov	bp,ax	; stash the HINSTANCE value
	lea	ax,TimeBeginPeriod_name
	cCall	GetProcAddress,<bp,cs,ax>
	test	dx,dx	; NULL?
	jnz	@F
	jmp	setup_done

@@:	mov	[TimeBeginPeriod.off],ax
	mov	[TimeBeginPeriod.sel],dx

	lea	ax,TimeGetDevCaps_name
	cCall	GetProcAddress,<bp,cs,ax>
	test	dx,dx	; NULL?
	jnz	@F
	jmp	setup_done

@@:	mov	[TimeGetDevCaps.off],ax
	mov	[TimeGetDevCaps.sel],dx

	lea	ax,TimeEndPeriod_name
	cCall	GetProcAddress,<bp,cs,ax>
	test	dx,dx	; NULL?
	jnz	@F
	jmp	setup_done

@@:	mov	[TimeEndPeriod.off],ax
	mov	[TimeEndPeriod.sel],dx

	lea	ax,TimeSetEvent_name
	cCall	GetProcAddress,<bp,cs,ax>
	test	dx,dx	; NULL?
	jnz	@F
	jmp	setup_done

@@:	mov	[TimeSetEvent.off],ax
	mov	[TimeSetEvent.sel],dx

	lea	ax,TimeKillEvent_name
	cCall	GetProcAddress,<bp,cs,ax>
	test	dx,dx	; NULL?
	jnz	@F
	jmp	setup_done

@@:	mov	[TimeKillEvent.off],ax
	mov	[TimeKillEvent.sel],dx

fnptrs_setup_done:
	; Allocate the back buffer memory. Use DPMI directly, since
	; GlobalAlloc/GlobalLock would allocate a whole bunch of selectors
	; which we don't actually need!
	mov	es,si
	mov	ax,501h				; Allocate memory block
	mov	bx,es:[di].bmWidthPlanes.hi
	mov	cx,es:[di].bmWidthPlanes.lo
	mov	dx,di				; Stash this offset

	; set BackBufSize while we're at it
	mov	[BackBufSize.lo],cx
	mov	[BackBufSize.hi],bx

	int	31h
	xchg	dx,di				; Get back the offset we stashed
	jc	setup_done
	mov	[BackBufDPMIHdl.lo],dx
	mov	[BackBufDPMIHdl.hi],si

	; Lock it straight away - we will keep the physical memory for
	; the back buffer in use for as long as Windows is running...
	; (It is a LOT of physical memory, so we don't want to lose it!)
	mov	ax,600h				; Lock linear region
	mov	si,es:[di].bmWidthPlanes.hi
	mov	dx,es:[di].bmWidthPlanes.lo
	xchg	dx,di
	int	31h
	xchg	dx,di				; Get back the offset we stashed
	jc	setup_done

	; Allocate selectors for front and back buffer
	mov	si,es
	push	bx
	push	cx
	cCall	AllocSelector,<es:[di].bmBits.sel>
	pop	cx
	pop	bx
	test	ax,ax
	jz	setup_done
	mov	[BackBufSel],ax

	; Set the selector to the base of the back buffer.
	cCall	SetSelectorBase,<ax,bx,cx>

	; And set its limit - SetSelectorBase should have returned the same
	; value in AX again
	mov	es,si
	mov	dx,es:[di].bmWidthPlanes.lo
	mov	cx,es:[di].bmWidthPlanes.hi
	; Limit == size-1
	sub	dx,1
	sbb	cx,0
	; Page-align the limit
	or	dx,0FFFh
	; Stash the selector before calling the function
	mov	bx,ax
	; Have to use DPMI instead of Windows KERNEL since the latter doesn't
	; know how to set page-granular limits...
	mov	ax,8	;set segment limit
	int	31h

	; Now copy the selector, to make one for the front buffer
	cCall	AllocSelector,<bx>
	test	ax,ax
	jz	setup_done
	mov	[FrontBufSel],ax

	; Set the selector to the base of the front buffer.
	mov	dx,seg VESALinearBuf
	mov	es,dx
	assumes	es,Code
	cCall	SetSelectorBase,<ax,[VESALinearBuf.hi],[VESALinearBuf.lo]>
	assumes	es,nothing			; C function stomps it

setup_done:
cEnd

; does the opposite of setup_double_buf, as a far function
; so it can be called from Code...
cProc	cancel_double_buf,<FAR,PUBLIC,NODATA>,<es,ax,bx,cx,dx,si,di>
cBegin
	call	stop_double_buf

	; Forget the selectors (but don't free them since
	; this seems to cause mayhem throughout the LDT...)
	xor	di,di
	mov	[FrontBufSel],di
	xchg	[BackBufSel],di

	; Unlock the back buffer memory
	test	di,di
	jz	@F
	cCall	GetSelectorBase,<di>
	xchg	di,ax
	mov	si,dx

	mov	ax,601h				; Unlock linear region
	mov	bx,si
	mov	cx,di
	mov	si,[BackBufSize.hi]
	mov	di,[BackBufSize.lo]
	int	31h

@@:	; and free it.
	mov	ax,502h				; Free memory block
	mov	di,[BackBufDPMIHdl.lo]
	mov	si,[BackBufDPMIHdl.hi]
	int	31h

	; the least we can offer in this case is write-through, so reading
	; from the screen mightn't always be so painfully slow...
	call	enable_wrthru
cEnd

;--------------------------------------------------------------------------;
; start_double_buf
;	actually starts the double-buffering: the linear framebuffer pointer
;	is switched to the back buffer and the swap-buffer timer event is
;	created.
; Entry:
;	DS	= Data
;	BackBufSel and FrontBufSel populated, pointing at respective buffers
; Registers Destroyed:
;	FLAGS
; Registers Preserved:
;	AX,BX,CX,DX,SI,DI,DS,ES,BP
; Calls:
; History:
;	see Git
;--------------------------------------------------------------------------;
cProc	start_double_buf,<NEAR,PUBLIC>,<es,ax,bx,cx,dx,si,di>
cBegin
	; first of all check if double-buffering is actually set up
	mov	ax,[BackBufSel]
	mov	bx,[FrontBufSel]
	or	ax,bx
	jz	start_done

	; make sure it's not already set up
	lea	ax,dbcursor_set
	cmp	[cursor_funcs],ax
	je	start_done

	; setup write combining if possible so swap_buffers isn't slow
	call	enable_wrcomb

	; install our cursor functions
	call	swap_cursor_funcs

	; now point the driver bitmap at the back buffer
	mov	di,[BackBufSel]
	call	change_lin_buf

	; attempt to start the fast timer, but if we fail it's OK
	call	start_fast_timer_far

start_done:
cEnd

;--------------------------------------------------------------------------;
; stop_double_buf
;	actually stops the double-buffering: the linear framebuffer pointer
;	is switched to the front buffer and the swap-buffer timer event is
;	killed.
; Entry:
;	DS	= Data
; Registers Destroyed:
;	FLAGS
; Registers Preserved:
;	AX,BX,CX,DX,SI,DI,DS,ES,BP
; Calls:
; History:
;	see Git
;--------------------------------------------------------------------------;
cProc	stop_double_buf,<NEAR,PUBLIC>,<es,ax,bx,cx,dx,di>
cBegin
	; check if swap_buffers is actually set to run
	lea	ax,dbcursor_set
	cmp	[cursor_funcs],ax
	jne	stop_done

	; disable it by putting back the swcurs functions
	call	swap_cursor_funcs

	; disable the timer event too
	mov	ax,[VTDAPIEntry.sel]
	test	ax,ax
	jnz	@F		; skip segment validity check if using VTDAPI

	db	0Fh,02,06	;lar ax,word ptr
	dw	offset fast_timer_irqseg
	jnz	timer_disabled	; invalid segment - so avoid Time* calls!

@@:	cCall	TimeKillEvent,<[fast_timer_hdl]>
	cCall	TimeEndPeriod,<[sb_period_ms]>
timer_disabled:
	mov	[fast_timer_hdl],0

	; now point the driver bitmap at the front buffer
	mov	di,[FrontBufSel]
	call	change_lin_buf

stop_done:
	; make front buffer uncacheable again - do this unconditionally
	; since even if we abandoned double-buffereing we may have enabled
	; write-through instead!
	call	disable_wrcomb
cEnd

; far entry points for use in 3XSWITCH.ASM
public	far_start_dblbuf
public	far_stop_dblbuf
far_start_dblbuf	proc far
	call	start_double_buf
	ret
far_start_dblbuf	endp
far_stop_dblbuf	proc far
	call	stop_double_buf
	ret
far_stop_dblbuf	endp

; Change VESALinearBuf to point at the base of the selector pointed to by DI,
; and reset the bank pointer to ensure reads/writes go to the right place
change_lin_buf	proc near
	push	bp
	push	si

	; We need to modify Code, so repurpose the ES selector momentarily.
	; It is imperative that nothing interrupts us while this is going on.
	EnterCrit
	; Save the selector params
	.386	; if we get this far we have a 386 (required for lin framebuf)
	push	eax
	db	66h,0Fh,03h,0C7h	;lsl eax,edi
	push	eax
	cCall	GetSelectorBase,<di>
	; Set BP:SI to the new pointer we want to set
	mov	bp,dx
	mov	si,ax

	; Point the selector at Code
	mov	ax,seg VESALinearBuf
	cCall	PrestoChangeoSelector,<ax,di>
	; Load it into ES
	mov	es,di
	assumes	es,Code
	mov	[VESALinearBuf.lo],si
	mov	[VESALinearBuf.hi],bp

	; Now restore the original selector base and limit
	cCall	SetSelectorBase,<es,bp,si>
	assumes	es,nothing
	pop	dx
	pop	cx
	mov	bx,di
	; Have to use DPMI instead of Windows KERNEL since the latter doesn't
	; know how to set page-granular limits...
	mov	ax,8	;set segment limit
	int	31h

	pop	eax
	.286

	; We can be interrupted again
	LeaveCrit b

	; Now force the bank to be reset
	mov	dl,-1
	xchg	dl,[bank_select_byte]
	SET_BANK

	pop	si
	pop	bp
	ret
change_lin_buf	endp

; this function swaps the list of functions at cursor_funcs with that at
; dbcursor_funcs, hence installing or uninstalling our cursor implementation
;
; requires DS to point to Data
swap_cursor_funcs	proc near
	push	si
	push	di
	push	cx

	lea	si,cursor_funcs
	lea	di,dbcursor_funcs
	mov	cx,(end_dbcursor_funcs - dbcursor_funcs) SHR 1

@@:	mov	ax,[si]
	xchg	ax,[di]
	xchg	ax,[si]
	lea	si,[si+2]
	lea	di,[di+2]
	loop	@B

	; ensure the old cursor is OFF
	call	far_cursor_off

	pop	cx
	pop	di
	pop	si
	ret
swap_cursor_funcs	endp

sEnd	InitSeg

END
