;	FILE:	dosxbfix.asm
;	DATE:	2025-09-15
;	AUTHOR: PluMGMK
;
;	DOSX.EXE, the default DOS extender used by Windows in
;	Standard Mode, has a bug that prevents linear
;	framebuffers from being mapped into the address space,
;	when a memory manager like EMM386 is used. However,
;	it turns out that it gives us full access to the page
;	tables, via some (undocumented?) GDT selectors, so we
;	can reimplement the functionality from Ring3!
;

; hard-coded GDT selectors provided by DOSX to access page tables
DOSX_PD_SEL	equ 0EBh	; selector for Page Directory
DOSX_PT_SEL	equ 0F3h	; selector for contiguous Page Tables

; base address for the memory regions we will map into address space
PHYS_MAP_BASE	equ 0C0000000h

	.xlist
	include CMACROS.INC
	include MACROS.MAC
	.list

	externFP GlobalAlloc
	externFP GlobalLock
	externFP GetSelectorBase

sBegin	Data

; we hook int 31h so store the old vector
old_int31	dd 0
; we allocate our own page tables using GlobalAlloc
pagetable_hdl	dw ?	; handle from GlobalAlloc
pagetable_ptr	dd ?	; selector/offset from GlobalLock
pagetable_addx	dd ?	; base address from GetSelectorBase

sEnd	Data

; createSeg must be done in 286 mode, otherwise it seems to create a
; 32-bit segment and confuse the life out of the linker!
.286

createSeg _INIT,InitSeg,word,public,CODE
sBegin	InitSeg

assumes	cs,InitSeg
assumes	ds,Data

; This function is called from VESAFNS.ASM when it determines that
; a linear framebuffer is required but that it's running under DOSX
; with paging enabled. Its purpose is to set up auxiliary page tables
; and hook int 31h to provide the PHYSICAL ADDRESS MAPPING service
; properly using the new tables.
;
; Returns CF clear if int 31h hooked successfully,
; CF set if something went wrong!
;
; Destroys ES, AX, BX, CX, DX
public	setup_dosx_bugfix
setup_dosx_bugfix	proc near
	; check if int 31h is already hooked
	cmp	[old_int31.sel],0
	jz	@F
	; CMP with 0 always clears CF
	ret

; if we have this bug, we're definitely on a CPU with paging!
; P is required to use LSL instruction (even though that isn't actually
; a privileged instruction :/)
.386p

@@:	; start with a few sanity checks
	mov	eax,DOSX_PD_SEL
	lsl	eax,eax
	; if we don't have access to the selector, we can't continue
	jnz	not_dosx
	; if the limit is not 0FFFh, then it's not the Page Directory
	cmp	eax,0FFFh
	jne	not_dosx

	; OK, it looks like we have the Page Directory, but let's check
	; the Page Tables too...
	mov	eax,DOSX_PT_SEL
	lsl	eax,eax
	; if we don't have access to the selector, we can't continue
	jnz	not_dosx
	; if the limit doesn't end with 0FFFh, then it's not the Page Tables
	and	eax,0FFFh
	cmp	eax,0FFFh
	je	@F

not_dosx:
	stc
	ret

@@:	; we're reasonably confident that we're running under DOSX
	; and can play with the page tables!

	; allocate a full 16k segment, i.e. four page tables, covering
	; 4 MiB of address space
	; 42h == GHND, 2000h == GMEM_SHARE
	cCall	GlobalAlloc,<2042h, 1,0000h>
	test	ax,ax
	mov	[pagetable_hdl],ax
	jz	not_dosx
	; lock it
	cCall	GlobalLock,<ax>
	test	dx,dx
	mov	[pagetable_ptr.off],ax
	mov	[pagetable_ptr.sel],dx
	jz	not_dosx

	push	esi
	push	edi
	push	ecx
	push	fs

	; and get its base address
	mov	di,ax
	cCall	GetSelectorBase,<dx>
	mov	[pagetable_addx.lo],ax
	mov	[pagetable_addx.hi],dx

	; The next thing we want to do is take the five Page Table
	; entries that cover our freshly-allocated memory block,
	; and copy them into the *Page Directory* at our chosen
	; base address. This will turn our memory block into a set
	; of page tables over which we have full control!
	mov	esi,[pagetable_addx]
	mov	edi,PHYS_MAP_BASE SHR 20; convert to offset in Page Directory
	shr	esi,10			; convert to offset in Page Tables
	and	esi,NOT 3
	mov	ax,DOSX_PT_SEL
	mov	dx,DOSX_PD_SEL
	mov	fs,ax
	mov	es,dx
	cld
	mov	ecx,5	; copy five entries (DWORDs)
	rep	movs dword ptr es:[edi],dword ptr fs:[esi]

	pop	fs
	pop	ecx
	pop	edi
	pop	esi

	; now that this is sewn up, we need to hook int 31h to
	; actually make use of this!
	mov	ax,3531h; get INT 31h vector
	int	21h
	mov	[old_int31.off],bx
	mov	[old_int31.sel],es

	push	ds
	mov	ax,seg dosx_fix_int31
	mov	ds,ax
	assumes	ds,nothing
	mov	dx,offset dosx_fix_int31
	mov	ax,2531h; set INT 31h vector
	int	21h
	pop	ds
	assumes	ds,Data

	; all done!
	clc
	ret
setup_dosx_bugfix	endp

sEnd	InitSeg

sBegin	Code
	assumes cs,Code

externW	_cstods		; in CURSOR.ASM

; our INT 31h handler
dosx_fix_int31	proc far
	push	ds
	push	bp
	mov	bp,sp
	mov	ds,[_cstods]
	assumes	ds,Data

	cmp	ax,800h		; PHYSICAL ADDRESS MAPPING
	je	int31_pam

	; not ours, pass through...
	push	dword ptr [bp]	; stack:	BP DS BP DS IP CS FL
	push	[old_int31]	;     IP31 CS31 BP DS BP DS IP CS FL
	pop	dword ptr [bp]	; 		BP DS IP31 CS31 IP CS FL
	pop	bp		; 		   DS IP31 CS31 IP CS FL
	pop	ds		; 		      IP31 CS31 IP CS FL
	ret			; far return to CS31:IP31 w/ correct stack frame

int31_pam:
	; At this point, we know thw following:
	; AX	== 800h
	; BX:CX	== physical address to map
	; SI:DI == size of region to map

	; get the params into 32-bit registers
	ror	ebx,10h
	xchg	bx,cx
	ror	esi,10h
	xchg	si,di
	; so now:
	; EBX	== physical address to map
	; ESI	== size of region to map

	push	edi
	push	ecx
	push	eax
	push	esi
	push	es

	; convert the size to pages
	add	esi,0FFFh
	shr	esi,0Ch

	; scan through our own page table until we find the first NULL entry
	les	di,[pagetable_ptr]
	movzx	edi,di
	; just in case Windows threw us a curveball and allocated memory
	; that wasn't DWORD-aligned...
	add	edi,3
	and	edi,NOT 3

	; then find the number of whole DWORDs to the end of the segment
	mov	eax,es
	lsl	ecx,eax
	inc	ecx
	sub	ecx,edi
	shr	ecx,2

	; scan for NULL
	cld
	xor	eax,eax
	repne	scas dword ptr es:[edi]
	db	067h,090h	; 386 bug
	jne	@F

	; we've scanned past the first NULL page, so rewind...
	inc	ecx
	sub	edi,4

@@:	; see if we have enough pages left to allocate
	or	byte ptr [bp+8],1;assume failure, set CF in FLAGS image
	cmp	esi,ecx
	ja	map_done

	; OK, we have enough pages to actually do this
	mov	eax,ebx		; address to map
	mov	al,07h		; set writable, user-accessible, present
	and	ah,0F0h		; clear bits 11-8, not part of the address
	and	ebx,0FFFh	; leave only the non-page-aligned piece in return value...
	mov	ecx,[pagetable_addx]
	and	ecx,0FFFh
	add	ecx,edi
	shl	ecx,10		; convert PT offset to linear address offset from PT base
	or	ebx,ecx		; OR in the offset
	or	ebx,PHYS_MAP_BASE;and the base itself
	int	3

	; fill in the addresses of the pages, one by one
	mov	ecx,esi
	jecxz	map_done
@@:	stos	dword ptr es:[edi]
	db	067h,090h	; 386 bug
	add	eax,1000h	; next page...
	db	066h		; use ECX
	loop	@B

	and	byte ptr [bp+8],NOT 1;all good, clear CF in FLAGS image
map_done:
	pop	es
	pop	esi
	pop	eax
	pop	ecx
	pop	edi

	xchg	bx,cx
	ror	ebx,10h
	xchg	si,di
	ror	esi,10h

	pop	bp
	pop	ds
	iret
dosx_fix_int31	endp

sEnd	Code


END
