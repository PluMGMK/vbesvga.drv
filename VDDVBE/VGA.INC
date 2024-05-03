ifdef  INC_LIST
	.XLIST
    subttl  VGA device equates
endif

;******************************************************************************
;
;VGA.INC    Definitions for VGA
;
;	Author: Marc Wilson
;	Copyright (c) Microsoft 1986
;	October, 1986
;
;DESCRIPTION:
;
;USE:
;	INCLUDE VGA.INC after VDD.INC
;
;******************************************************************************

;CHIPTECH   equ -1			; define CHIPTECH for 82C440 board

;****** VGA I/O port definitions

pVGAEna 	equ	3C3h		; VGA enable register
fVGAEna 	equ	00000001b	;   Enable access to VGA

pDACWindx	equ	3C8h		; DAC Write index(R/W)
pDACRindx	equ	3C7h		; DAC Read index(RO)
pDACState	equ	pDACRindx	; DAC state
pDACData	equ	3C9h		; DAC data(3 successive accesses)
pDACMask	equ	3CAh		; DAC mask

pMiscRead	equ	3CCh		; Port to read Misc output register
pFeatRead	equ	3CAh		; Port to read Feature output register

IFDEF VGA8514
p8514DACWindx	equ	2ECh		; DAC Write index(R/W)
p8514DACRindx	equ	2EBh		; DAC Read index(RO)
p8514DACState	equ	pDACRindx	; DAC state
p8514DACData	equ	2EDh		; DAC data(3 successive accesses)
ENDIF

;
; values returned from reads of port pDACState:
;
DAC_Read_Mode	equ	0
DAC_Write_Mode	equ	3


ifdef	CTVGA
xC_CTMiscRead	equ	0Fh		; CHIPS Misc output read index
xC_CTFeatRead	equ	0Eh		; CHIPS Feat output read index
xC_CT400	equ	0F9h		; CHIPS 400 line reg index
xC_CTTempFE     equ     0FEh            ; CHIPS CRTC temp reg FEh
xG_CTCtl	equ	0F7h		; CHIPS control reg index
endif


;***************
;VM1's VRAM save address for mode 12(VGA) display.drv
VM1_VGA_VRAM_Addr   equ     0ABFF0h
VM1_VGA_VRAMX_Addr  equ     0A8FF0h


;****** VGA detection macro
;  ENTRY: nothing, no parameters
;
;   EXIT: ZF = 1 indicates VGA exists
;	  CF = 1 indicate CHIPS VGA(82C441)
;
;   USES: Flags
;
;ASSUMES: INT 10 function 1A does nothing if not defined. If defined(beware
;	clones!) it behaves as code indicates ONLY IF VGA!
;
VDD_Test_VGA	macro
    local   VTV_VGA
    local   VTV_Done
    pusha
    mov     ax,1A00h
    xor     bx,bx
    int     10h
    cmp     al,1Ah
    jnz     short VTV_Done
    cmp     bl,7
    jz	    short VTV_VGA
    cmp     bl,8
ifdef	CHIPTECH
    jnz     short VTV_Done
VTV_VGA:
    mov     dx,pMiscRead
    in	    al,dx
    push    ax
    mov     dl,0D4h
    mov     al,017h
    out     dx,al
    inc     dx
    in	    al,dx
    or	    al,10h
    out     dx,al
    dec     dx
    mov     al,0f9h
    out     dx,al
    inc     dx
    in	    al,dx
    and     al,07fh
    out     dx,al
    dec     dx
    mov     al,xC_CTMiscRead
    out     dx,al
    inc     dx
    in	    al,dx
    push    ax
    mov     dx,pMiscEGA
    mov     al,0A5h
    out     dx,al
    mov     dl,0D4h
    mov     al,xC_CTMiscRead
    out     dx,al
    inc     dx
    in	    al,dx
    cmp     al, 0A5h
    mov     dx,pMiscEGA
    jne     VDD_ibm_vga
    mov     al,055h
    out     dx,al
    mov     dl,0D4h
    mov     al,xC_CTMiscRead
    out     dx,al
    inc     dx
    in	    al,dx
    mov     dx,pMiscEGA
    cmp     al,055h
    jne     VDD_ibm_vga
    pop     ax
    out     dx, al
    add     esp,2
    cmp     ax,ax
    stc
    jmp     VTV_Done

VDD_ibm_vga:
    add     esp,2
    pop     ax
    out     dx, al
    cmp     ax,ax
    clc
else
VTV_VGA:
endif
VTV_Done:
    popa
    endm
