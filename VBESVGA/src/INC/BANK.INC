;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.
.286
        public  bank_select

        public  set_bank_select
        public  far_set_bank_select


sBegin  Data

	public bank_select_byte
bank_select_byte label byte
bank_select         db      0FFh        ;Used to keep track of VRAM VGA's
                                        ; currently selected bank
	public bank_granfac_m1
bank_granfac_m1     db      0		;size-to-granularity multiplication
					; factor, minus one
sEnd    Data

sBegin  Code
	assumes cs,Code

	externD	VESABankSwitch		; in VESAFNS.ASM

far_set_bank_select proc far
        push    ds
	push	ax
;
	mov	ax,DGROUP
	mov	ds,ax
        ;
        ;   compare requested bank against the current one
        ;
        cmp     dl,ds:[bank_select]
        jz      far_sbs_exit
        ;
        ;   we need to modify the BANK registers
        ;
        mov     ds:[bank_select],dl

        push    bx
        push    dx

	; get the size-to-granularity multiplication factor, minus 1
	mov	ah,ds:[bank_granfac_m1]
	test	ah,ah
	jz	@F			; factor == 1 so no need to multiply

	inc	ah
	mov	al,dl
	mul	ah
	mov	dl,al

@@:	EnterCrit
;
	xor	bx,bx			; BH = 0 = "set", BL = 0 = window 0
	xor	dh,dh			; DX = DL = bank number (gran. units)
	push	es			; some firmware trashes ES (e.g. VMware)
	pushf				; to maintain DF during blits!
	call	VESABankSwitch
	popf
	pop	es
;
	LeaveCrit  a			; Okay to interrupt now

        pop     dx
        pop     bx


far_sbs_exit:
	pop	ax
	pop	ds
	ret
far_set_bank_select endp

;
;
;       Set A000:0000 to point to a specific bank of 64K
;
;       Entry:  DL = bank select
;       Exit:   none
;
set_bank_select proc    near
        push    ds
	push	ax
;
	mov	ax,DGROUP
	mov	ds,ax

        ;
        ;   compare requested bank against the current one
        ;
        cmp     dl,ds:[bank_select]
        jz      sbs_exit
        ;
        ;   we need to modify the BANK registers
        ;
        mov     ds:[bank_select],dl

        push    bx
        push    dx

	; get the size-to-granularity multiplication factor, minus 1
	mov	ah,ds:[bank_granfac_m1]
	test	ah,ah
	jz	@F			; factor == 1 so no need to multiply

	inc	ah
	mov	al,dl
	mul	ah
	mov	dl,al

@@:	EnterCrit
;
	xor	bx,bx			; BH = 0 = "set", BL = 0 = window 0
	xor	dh,dh			; DX = DL = bank number (gran. units)
	push	es			; some firmware trashes ES (e.g. VMware)
	pushf				; to maintain DF during blits!
	call	VESABankSwitch
	popf
	pop	es
;
	LeaveCrit  a			; Okay to interrupt now

        pop     dx
        pop     bx

sbs_exit:
	pop	ax
	pop	ds
        ret
set_bank_select endp

sEnd Code
