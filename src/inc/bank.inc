;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.
.286
        public  bank_select

        public  set_bank
        public  set_bank_select
        public  far_set_bank_select


sBegin  Data

	public bank_select_byte
bank_select_byte label byte
bank_select         db      0FFh        ;Used to keep track of VRAM VGA's
                                        ; currently selected bank
sEnd    Data

sBegin  Code
	assumes cs,Code

far_set_bank_select proc far
;	call	set_bank_select
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

;        call    set_bank
        push    bx
        push    dx
        mov     bl,dl
        and     bl,1                    ; BL = extended page select
        mov     ah,dl
        and     ah,2
	shl	ah,4			; AH = page select bit
        and     dl,00ch
        mov     bh,dl
	shr	dl,2
        or      bh,dl                   ; BH = 256K bank select

        EnterCrit
;
        mov     dx,03cch
        in      al,dx                   ; Get Miscellaneous Output Register
        and     al,not 20h              ; Clear page select bit
        or      al,ah                   ; Set page select bit (maybe)
        mov     dl,0c2h                 ; Write Miscellaneous Output Register
        out     dx,al
;
        mov     dl,0c4h                 ; Sequencer
        mov     al,0f9h                 ; Extended page select register
        mov     ah,bl                   ; Extended page select value
        out     dx,ax
;
        mov     al,0f6h                 ; 256K bank select
        out     dx,al
        inc     dx                      ; Point to data
        in      al,dx
        and     al,0f0h                 ; Clear out bank select banks
        or      al,bh                   ; Set bank select banks (maybe)
        out     dx,al
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
;       Assume: VRAM VGA in extended 256 color mode
;               Extensions are enabled
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

;        call    set_bank
        push    bx
        push    dx
        mov     bl,dl
        and     bl,1                    ; BL = extended page select
        mov     ah,dl
        and     ah,2
	shl	ah,4			; AH = page select bit
        and     dl,00ch
        mov     bh,dl
	shr	dl,2
        or      bh,dl                   ; BH = 256K bank select

        EnterCrit
;
        mov     dx,03cch
        in      al,dx                   ; Get Miscellaneous Output Register
        and     al,not 20h              ; Clear page select bit
        or      al,ah                   ; Set page select bit (maybe)
        mov     dl,0c2h                 ; Write Miscellaneous Output Register
        out     dx,al
;
        mov     dl,0c4h                 ; Sequencer
        mov     al,0f9h                 ; Extended page select register
        mov     ah,bl                   ; Extended page select value
        out     dx,ax
;
        mov     al,0f6h                 ; 256K bank select
        out     dx,al
        inc     dx                      ; Point to data
        in      al,dx
        and     al,0f0h                 ; Clear out bank select banks
        or      al,bh                   ; Set bank select banks (maybe)
        out     dx,al
;
	LeaveCrit  a			; Okay to interrupt now

        pop     dx
        pop     bx

sbs_exit:
	pop	ax
	pop	ds
        ret
set_bank_select endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;  Code for V7 VRAM card
;
;

%out Driver for Video 7 VRAM board

SC_INDEX        equ     03C4h           ; Sequence Controller Index register
SC_MAP          equ     002h
SC_MEM          equ     004h
SC_EXTEND       equ     006h            ; not in parameter table, don't count
ER_BACK_LATCH   equ     0F2h
ER_PAGE_SEL     equ     0F9h            ; Extended page select (bit 0)
ER_BANK_SEL     equ     0F6h            ; 256K bank select

GC_INDEX        equ     03CEh           ; Graphics Controller Index register
GC_MODE         equ     005h

MISC_OUTPUT     equ     03C2h           ; Miscellaneous Output register
MISC_INPUT      equ     03CCh           ; Miscellaneous Output register read

;
;
;       Set A000:0000 to point to a specific bank of 64K
;
;       Entry:  DL = bank select
;       Exit:   none
;
;       Assume: VRAM VGA in extended 256 color mode
;               Extensions are enabled
;
set_bank proc    near
        push    ax
        push    bx
        push    dx
;
if	0
	shiftl	dl,4
	mov	ah,dl
;	 or	 ah,1

	mov	dx,03c4h
	mov	al,0e8h
	out	dx,ax
else

        mov     bl,dl
        and     bl,1                    ; BL = extended page select
        mov     ah,dl
        and     ah,2
	shl	ah,4			; AH = page select bit
        and     dl,00ch
        mov     bh,dl
	shr	dl,2
        or      bh,dl                   ; BH = 256K bank select

        EnterCrit
;
        mov     dx,03cch
        in      al,dx                   ; Get Miscellaneous Output Register
        and     al,not 20h              ; Clear page select bit
        or      al,ah                   ; Set page select bit (maybe)
        mov     dl,0c2h                 ; Write Miscellaneous Output Register
        out     dx,al
;
        mov     dl,0c4h                 ; Sequencer
        mov     al,0f9h                 ; Extended page select register
        mov     ah,bl                   ; Extended page select value
        out     dx,ax
;
        mov     al,0f6h                 ; 256K bank select
        out     dx,al
        inc     dx                      ; Point to data
        in      al,dx
        and     al,0f0h                 ; Clear out bank select banks
        or      al,bh                   ; Set bank select banks (maybe)
        out     dx,al
;
	LeaveCrit  a			; Okay to interrupt now
endif
        pop     dx
        pop     bx
        pop     ax
        ret
set_bank endp



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;  Code for GENERIC VGA card.
;
;

ifdef IBMVGA

%out Driver for Generic VGA

set_bank proc    near
        ret
set_bank endp

endif

sEnd Code
