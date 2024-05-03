        page    ,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	VGASTATE.ASM
;
; Created: 06-Jan-1987
; Author:  Walt Moore [waltm]
;
; Copyright (c) 1987 Microsoft Corporation
;
; Exported Functions:	none
;
;	INIT_HW_REGS is called immediately after the EGA is placed
;	into graphics mode to initialize locations in EGA memory.
;-----------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.


        .xlist
        include cmacros.inc
        include windefs.inc
        include cursor.inc
        include bank.inc

	??_out	vgastate		;;Identify if not in quiet mode
	public	init_hw_regs


        page
sBegin  Code
	assumes cs,Code
	assumes ds,Data
	assumes es,nothing

;-----------------------------Public-Routine----------------------------;
; init_hw_regs
;
; Initialize Hardware Video Registers
;
; Error Returns:
;       none
; Registers Destroyed:
;       AX,BX,DX,FLAGS
; Registers Preserved:
;       SI,DI,BP,DS,ES
;-----------------------------------------------------------------------;

init_hw_regs    proc    far

;
;   Initialize the banking code, set bank 0
;
        mov     bank_select,0FFh
        xor     dx,dx
        call    far_set_bank_select
        ret

init_hw_regs	endp

sEnd    Code

        end
