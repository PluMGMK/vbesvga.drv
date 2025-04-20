	TITLE	VDD - Virtual Display Device for VBE   version 3.10  04/25
;******************************************************************************
;
;VDDDBUF - Double-Buffering Service Routines
;
;   Author: PluMGMK
;
;DESCRIPTION:
;
;******************************************************************************

	.386p

.xlist
	INCLUDE VMM.INC
	INCLUDE VTD.INC
	INCLUDE DEBUG.INC
.list

;******************************************************************************
; EXTRN routines
;
VxD_CODE_SEG

VxD_CODE_ENDS

;******************************************************************************
; EXTRN data
;
VxD_DATA_SEG

; handle for back-buffer / front-buffer memory pages
Vid_BBuf_Hdl	DD 0
; size of the buffer (passed as ref data to VDD_SwapBuffers)
Vid_BBuf_Size	DD 0

VxD_DATA_ENDS

; cursor data is locked so we don't risk having to swap it in during the
; extremely high-frequency swap-buffer routine
VxD_LOCKED_DATA_SEG

; handle for global timeout
Vid_SB_Timeout	DD 0

; these MUST be the same as in CURSOR.INC
YES_CURSOR	EQU	00000100B
CURSOR_HEIGHT	EQU	20H
CURSOR_WIDTH	EQU	20H

Shared_Cursor_Data	STRUC
	; these MUST be in the same order as in SWCURS.ASM!
	screen_x	DW ?
	screen_y	DW ?
	screen_width	DW ?
	screen_height	DW ?
	screen_xclip	DW ?
	screen_yclip	DW ?
	screen_longaddr	DD ?

	; actual cursor data
	; CURSOR_WIDTH * CURSOR_HEIGHT pixels, times (up to) four bytes per pixel,
	; times two because we have both the cursor image and the AND mask!
	cursor_data	DW CURSOR_WIDTH*CURSOR_HEIGHT*4*2 DUP (?)

	; flags, used to specify whether or not to draw the cursor
	cursor_flags	DW ?
Shared_Cursor_Data	ENDS

; we can expose a copy of this structure to userspace via a small LDT segment
SharedCurSeg	DB (size Shared_Cursor_Data) dup (0)

; selectors used to make it easier to address the front, back and VRAM buffers
FrontBufSel	DW 0
BackBufSel	DW 0
VramSel		DW 0

; info on the screen memory layout
pxbytes		DW 0
MemWidth	DW 0

; how often to swap buffers
sb_period_ms	DB 0

VxD_LOCKED_DATA_ENDS


; extremely high-frequency swap-buffer routine is locked so we don't risk having
; to swap it in
VxD_LOCKED_CODE_SEG

;******************************************************************************
;VDD_SwapBuffers
;
;DESCRIPTION:
;	Copy the entire back buffer onto the front buffer, while putting the
;	cursor over it. Actually, only copy parts that have changed, and if
;	they have, copy them to VRAM as well.
;
;ENTRY: EBX = current VM handle (incidental)
;	ECX = delay in milliseconds (useful for benchmarking?)
;	EDX = size of buffers
;	EBP = current VM client regs (also incidental)
;
;EXIT:
;
;USES:	Flags
;
;ASSUMES:
;
;==============================================================================
BeginProc VDD_SwapBuffers,High_Freq

	pushad	; we will use all the 386 registers!
	push	es
	push	fs
	push	gs

	; We will use the registers like so:
	; EAX = Current dword of graphics data (or word of cursor data)
	; EBX = [UPPER HALF] Next cursor scanline pointer
	; BH  = Cursor scanlines remaining
	; BL  = Cursor byte-pair width (clipped)
	; ECX = Current counter
	; EDX = Total buffer size
	; EBP = [UPPER HALF] MemoryWidth - Cursor byte-pair width
	; BP  = Cursor byte width (total, byte-pair width * 2)
	; ESI = Pointer to back buffer or cursor data
	; EDI = Position in front/back buffer
	; Segment registers:
	; DS = Data
	; ES = Front Buffer
	; FS = Back Buffer
	; GS = Video RAM

	mov	es,[FrontBufSel]
	mov	fs,[BackBufSel]
	mov	gs,[VramSel]
	assume	es:nothing,fs:nothing,gs:nothing
	; point at the start of the front buffer
	cld
	xor	edi,edi

	; assume no cursor scanlines to draw --> zero EBX
	mov	ebx,edi
	test	[SharedCurSeg.cursor_flags],YES_CURSOR
	jz	@@no_cursor

	; Set BX to the beginning of the cursor data, modulo clipping...
	; Start by converting yclip in scanlines to a pixel offset:
	imul	bx,[SharedCurSeg.screen_yclip],CURSOR_WIDTH
	; Add the xclip in pixels:
	add	bx,[SharedCurSeg.screen_xclip]
	; Convert to byte pairs
	imul	bx,[pxbytes]
	; Then to bytes
	shl	bx,1
	; Now BX has a 16-bit offset into the cursor buffer

	; Now move the whole thing into the upper half!
	shl	ebx,10h

	; calculate the full and clipped byte widths of the cursor
	mov	bh,CURSOR_WIDTH
	mov	bl,byte ptr [SharedCurSeg.screen_width]
	; multiply BH and BL at the same time - safe since the maximum result
	; for both bytes is 80h, so this will never carry!
	imul	bx,[pxbytes]
	; BH is now the total cursor byte width, which belongs in BP
	movzx	ebp,bh
	; Convert lower half of EBP to full byte width of the cursor data
	; (since each byte of bitmap data is doubled into an AND and a XOR byte)
	shl	bp,1

	; Get the MemWidth minus cursor width for the upper half of EBP
	mov	ax,[MemWidth]
	xor	bh,bh	; BX becomes full byte-pair width of cursor
	sub	ax,bx
	; Move into upper half
	shl	eax,10h
	; Then into EBP
	or	ebp,eax
	; Now set BH as indicated above:
	mov	bh,byte ptr [SharedCurSeg.screen_height]

	; Set the counter and start the first round of copying
	mov	ecx,[SharedCurSeg.screen_longaddr]
@@copy_loop:
	; We're moving the back to the front buffer, so the source and dest
	; offsets are identical :)
	mov	esi,edi

	shr	ecx,1
	jnc	short @F
	; copy straggling byte
	lods	byte ptr fs:[esi]
	scasb				; any change to front buffer?
	je	short @F
	mov	gs:[edi-1],al		; yes, write this byte to VRAM
	mov	es:[edi-1],al		; and update the front buffer

@@:	shr	ecx,1
	jnc	short @F
	; copy straggling word
	lods	word ptr fs:[esi]
	scasw				; any change to front buffer?
	je	short @F
	mov	gs:[edi-2],ax		; yes, write this word to VRAM
	mov	es:[edi-2],ax		; and update the front buffer

@@:	jecxz	short @F
	; copy everything else dword-by-dword
	lods	dword ptr fs:[esi]
	scasd				; any change to front buffer?
	loope	@B
	je	short @F
	mov	gs:[edi-4],eax		; yes, write this dword to VRAM
	mov	es:[edi-4],eax		; and update the front buffer
	jmp	short @B

@@:	; copy loop done - any cursor scanlines left?
	test	bh,bh
	jz	short @@done

	; right, switch over to loading the cursor data
	; 16-bit source address and counter registers are sufficient for this!
	movzx	cx,bl	; this counts byte PAIRS!
	mov	esi,ebx
	shr	esi,10h	; offset was in upper half of EBX
	add	esi,OFFSET32 SharedCurSeg.cursor_data

	; loop over byte pairs
@@:	jcxz	short @@cursor_scanline_done
	lodsw
	and	al,fs:[edi]		; read byte from back buffer
	xor	al,ah
	scasb				; any change to front buffer?
	loope	@B			; nope, get next word of cursor data
	je	short @@cursor_scanline_done
	mov	gs:[edi-1],al		; yes, write this byte to VRAM
	mov	es:[edi-1],al		; and update the front buffer
	jmp	short @B

@@cursor_scanline_done:
	dec	bh			; decrement scanline counter
	jz	short @@no_cursor	; done with the cursor completely
	ror	ebx,10h			; get pointer into lower half
	add	bx,bp			; point at next scanline of cursor data
	ror	ebx,10h			; shove back into upper half

	; set the counter so we copy the rest of the buffer's current scanline
	mov	ecx,ebp
	shr	ecx,10h			; counter was in upper half of EBP
	jmp	short @@copy_loop

@@no_cursor:
	; done with the cursor altogether (or had none in the first place),
	; so just chug through the rest of the buffer copy and we're done
	mov	ecx,edx
	; account for any progress made so far
	sub	ecx,edi
	jnz	@@copy_loop

@@done:	pop	gs
	pop	fs
	pop	es
	assume	es:FLAT
	popad

	; schedule the next call
	call	VDD_Schedule_SwapBuffers
	ret
EndProc VDD_SwapBuffers

;******************************************************************************
;VDD_Schedule_SwapBuffers
;
;DESCRIPTION:
;	Schedule the next buffer-swap.
;
;ENTRY: EDX = size of buffers
;
;EXIT:	Vid_SB_Timeout updated
;
;USES:	Flags
;
;ASSUMES:
;
;==============================================================================
BeginProc VDD_Schedule_SwapBuffers,High_Freq
	push	eax
	push	esi
	movzx	eax,[sb_period_ms]
	mov	esi,OFFSET32 VDD_SwapBuffers
	VMMcall	Set_Global_Time_Out
	mov	[Vid_SB_Timeout],esi
	pop	esi
	pop	eax
	ret
EndProc VDD_Schedule_SwapBuffers

VxD_LOCKED_CODE_ENDS

VxD_CODE_SEG

BeginDoc
;******************************************************************************
;VDD_DblBuf_Service
;
;DESCRIPTION:
;	Dispatch to setup / start / stop double-buffering
;
;ENTRY: EBX = current VM handle
;	EDX = 0
;	EBP = current VM client regs
;	Client_AX = function number
;
;EXIT:	dispatch to double-buffer service routines
;
;USES:	flags, AX, ESI
;
;==============================================================================
EndDoc

; double-buffering service numbers
DB_Setup EQU 0
DB_Start EQU 1
DB_Stop  EQU 2
DB_Last  EQU DB_Stop

BeginProc VDD_DblBuf_Service, PUBLIC

	VMMcall	Simulate_Far_Ret
	movzx	ecx,[ebp.Client_AX]
	cmp	cl,DB_Stop
	ja	SHORT VDBS_Exit
	VMMCall Validate_VM_Handle
	jmp	DWORD PTR DblBuf_JumpTable[ecx*4]
VDBS_Exit:
	ret

DblBufEntry MACRO svcnum, label
.erre svcnum*4 EQ $-DblBuf_JumpTable
	dd  OFFSET32 label
ENDM

;VDD virtual mode services for the grabber
DblBuf_JumpTable	LABEL DWORD
DblBufEntry DB_Setup, VDD_DblBuf_Setup	; Create buffers and selectors
DblBufEntry DB_Start, VDD_DblBuf_Start	; Start periodic swap-buffers loop
DblBufEntry DB_Stop, VDD_DblBuf_Stop	; Stop periodic swap-buffers loop
EndProc VDD_DblBuf_Service


BeginDoc
;******************************************************************************
;VDD_DblBuf_Setup
;
;DESCRIPTION:
;	Create buffers and selectors needed for double-buffering
;
;ENTRY: EBX = current VM handle
;	EDX = 0
;	EBP = current VM client regs
;	Client_AX = 0
;	Client_BL = bytes per pixel
;	Client_BH = desired period in milliseconds
;	Client_ECX = physical size of VRAM buffer
;	Client_DX = physical size of a single scanline
;	Client_SI = number of words of screen_* cursor data user plans to copy
;	Client_EDI = physical address of VRAM buffer
;
;EXIT:	Client_AX = LDT selector for cursor data
;	Client_ESI = linear address of back buffer
;	Client_EDI = linear address of VRAM buffer
;
;USES:	flags, EAX, ECX, EDX, ESI, EDI
;
;==============================================================================
EndDoc

BeginProc VDD_DblBuf_Setup

	; first of all check if double-buffering is already set up
	cmp	[VramSel],dx	; DX == 0
	jnz	setup_done

	; has user force-disabled double buffering?
	mov	ax,[ebp.Client_BX]
	test	ah,ah
	mov	[sb_period_ms],ah
	jz	setup_done

	; check if the driver is planning to copy the correct amount of
	; screen_* cursor data...
	mov	si,[ebp.Client_SI]
	shl	si,1		; convert to bytes
	cmp	si,cursor_data	; offset of cursor_data is end of screen_*
	je	short @F

Trace_Out   "VDD: double buffer API version mismatch"
	jmp	setup_done

@@:	; fill in the other info
	mov	ah,dh		; zero AH
	mov	[pxbytes],ax
	mov	esi,[ebp.Client_ECX]
	mov	dx,[ebp.Client_DX]
	mov	eax,[ebp.Client_EDI]
	mov	[Vid_BBuf_Size],esi
	mov	[MemWidth],dx

	; map VRAM into linear memory
	VMMcall	_MapPhysToLinear, <eax,esi,0>
	cmp	eax,-1
	je	setup_done
	mov	[ebp.Client_EDI],eax
	mov	edi,eax

	; Allocate the back buffer memory.
	; we need twice this much memory - one for the true back-buffer,
	; and again for the write-through front buffer!
	mov	edx,esi
	shl	edx,1
	; round up to nearest page
	add	edx,0FFFh
	shr	edx,0Ch

	; System Pages (not tied to any VM), initialized to zero so
	; stale data doesn't get thrown up as Windows is booting, and
	; fixed becuase we will be using it for as long as Windows is
	; running...
	VMMcall	_PageAllocate, <edx,PG_SYS,0,0,0,0,0,PageZeroInit+PageFixed>
	mov	[Vid_BBuf_Hdl],eax
	or	eax,edx
	jz	setup_done
	mov	[ebp.Client_ESI],edx

	; Allocate selectors for front and back buffer
	mov	ecx,esi		; get buffer size again
	; Limit == size-1
	dec	ecx
	; Convert limit to pages
	shr	ecx,0Ch

	push	edx
	; R_Data_Type since we don't write to the back buffer
	VMMcall _BuildDescriptorDWORDs, <edx, ecx, R_Data_Type, D_PAGE32, BDDExplicitDPL>
	push	ecx	; contrary to docs, Allocate_GDT_Selector destroys this
	VMMcall _Allocate_GDT_Selector, <edx, eax, 0>
	pop	ecx
	pop	edx
	test	eax,eax
	jz	setup_done
	mov	[BackBufSel],ax

	; Now make one for the write-through front buffer:
	; Set the selector to the base of the front buffer.
	; It's the second half of the large memory block we
	; just allocated, of which the base is in SI:DI
	add	edx,esi
	; RW_Data_Type since we always write to the front buffer
	VMMcall _BuildDescriptorDWORDs, <edx, ecx, RW_Data_Type, D_PAGE32, BDDExplicitDPL>
	push	ecx	; contrary to docs, Allocate_GDT_Selector destroys this
	VMMcall _Allocate_GDT_Selector, <edx, eax, 0>
	pop	ecx
	test	eax,eax
	jz	short setup_done
	mov	[FrontBufSel],ax

	; Now make one for the VRAM buffer
	; RW_Data_Type since we always write to the VRAM buffer
	VMMcall _BuildDescriptorDWORDs, <edi, ecx, RW_Data_Type, D_PAGE32, BDDExplicitDPL>
	push	ecx	; contrary to docs, Allocate_GDT_Selector destroys this
	VMMcall _Allocate_GDT_Selector, <edx, eax, 0>
	pop	ecx
	test	eax,eax
	jz	short setup_done
	mov	[VramSel],ax

	; Lastly create LDT selector for cursor data...
	mov	eax,SIZE Shared_Cursor_Data
	dec	eax	; limit = size - 1
	mov	edx,OFFSET32 SharedCurSeg
	VMMcall _BuildDescriptorDWORDs, <edx, eax, RW_Data_Type+D_DPL3, D_DEF16, BDDExplicitDPL>
	VMMcall _Allocate_LDT_Selector, <ebx, edx, eax, 1, 0>
	mov	[ebp.Client_AX],ax

setup_done:
	ret

EndProc VDD_DblBuf_Setup

BeginDoc
;******************************************************************************
;VDD_DblBuf_Start
;
;DESCRIPTION:
;	Create swap-buffer timer event
;
;ENTRY: EBX = current VM handle
;	EDX = 0
;	EBP = current VM client regs
;	Client_AX = 1
;	Client_ES:DI -> pointer to linear framebuffer base
;	BackBufSel and FrontBufSel populated, pointing at respective buffers
;
;EXIT:	Client_AX = 0 on success, unchanged on failure
;	Pointer @ Client ES:DI points at back buffer
;
;USES:	flags, EAX, ECX, EDX, EDI
;
;==============================================================================
EndDoc

BeginProc VDD_DblBuf_Start

	; first of all check if double-buffering is actually set up
	cmp	[VramSel],dx	; DX == 0
	jz	short start_done

	; make sure it's not already started
	cmp	[Vid_SB_Timeout],edx
	jnz	short start_done

	; eliminate stale data from the front buffer
	mov	edx,[Vid_BBuf_Size]
	push	es
	mov	es,[FrontBufSel]
	assume	es:nothing
	xor	eax,eax
	mov	ecx,edx
	mov	edi,eax
	shr	ecx,1
	jnc	short @F
	stosb
@@:	shr	ecx,1
	jnc	short @F
	stosw
@@:	rep	stosd
	pop	es
	assume	es:FLAT

	; attempt to start the fast timer
	movzx	eax,[sb_period_ms]
	VxDCall	VTD_Begin_Min_Int_Period
	jc	short start_done
	call	VDD_Schedule_SwapBuffers
	; check if it succeeded...
	xor	edx,edx
	cmp	[Vid_SB_Timeout],edx
	je	short start_done

	; success: set client's AX to zero
	mov	[ebp.Client_AX],dx
	; and update its linear framebuffer pointer
	Client_Ptr_Flat	edi, ES, DI
	movzx	eax,[BackBufSel]
	VMMcall	_GetDescriptor, <eax, 0, 0>
	; upper half of EAX is lower half of Base
	shr	eax,10h
	mov	[edi],ax
	; lower and upper bytes of EDX are the upper half
	mov	[edi+2],dl
	shr	edx,18h
	mov	[edi+3],dl

start_done:
	ret

EndProc VDD_DblBuf_Start

BeginDoc
;******************************************************************************
;VDD_DblBuf_Stop
;
;DESCRIPTION:
;	Stop swap-buffer timer event
;
;ENTRY: EBX = current VM handle
;	EDX = 0
;	EBP = current VM client regs
;	Client_AX = 2
;	Client_ES:DI -> pointer to linear framebuffer base
;
;EXIT:	Pointer @ Client ES:DI points at VRAM
;
;USES:	flags, EAX, ECX, EDX, EDI
;
;==============================================================================
EndDoc

BeginProc VDD_DblBuf_Stop

	; check if swap_buffers is actually set to run
	mov	esi,[Vid_SB_Timeout]
	test	esi,esi
	jz	short stop_done

	VMMcall	Cancel_Time_Out
	movzx	eax,[sb_period_ms]
	VxDCall	VTD_Begin_Min_Int_Period
	mov	[Vid_SB_Timeout],edx

	; update client's linear framebuffer pointer
	Client_Ptr_Flat	edi, ES, DI
	movzx	eax,[VramSel]
	VMMcall	_GetDescriptor, <eax, 0, 0>
	; upper half of EAX is lower half of Base
	shr	eax,10h
	mov	[edi],ax
	; lower and upper bytes of EDX are the upper half
	mov	[edi+2],dl
	shr	edx,18h
	mov	[edi+3],dl

stop_done:
	ret

EndProc VDD_DblBuf_Stop

VxD_CODE_ENDS

	END
