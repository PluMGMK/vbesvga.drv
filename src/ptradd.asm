        page    ,132
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ptradd.asm
;
; Copyright (c) 1991 Microsoft Corporation.  All Rights Reserved.
;
; KERNELs LongPtrAdd function, (private version)
;
; Created: Mon 26-Mar-1990
;
; Exported Functions:   none
;
; Public Functions:     LongPtrAdd
;                       CopyPtr
;                       AllocPtr
;
; Public Data:		none
;
; General Description:
;
; Restrictions:
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        .286

        ?PLM=1
        ?WIN=1

        .xlist
        include CMACROS.INC
        include MACROS.MAC
        .list

        externFP        GetSelectorBase
        externFP        SetSelectorBase
        externFP        GetSelectorLimit
        externFP        SetSelectorLimit
;	externFP	SelectorAccessRights
        externFP        AllocSelector
        externFP        PrestoChangeoSelector

sBegin Code
        assumes cs,Code
	assumes ds,nothing
	assumes es,nothing

;-----------------------------------------------------------------------;
; LongPtrAdd
;
; Performs segment arithmetic on a long pointer and a DWORD offset
; The resulting pointer is normalized to a paragraph boundary.
; The offset cannot be greater than a megabyte.
;
; Entry:
;       long_ptr            base pointer
;       delta               amount to add to pointer
;
; Returns:
;	DX:AX new segment:offset
;
; Error returns:
;	DX:AX = 0
;
; Registers Destroyed:
;       AX,BX,CX,DX,ES
;
;-----------------------------------------------------------------------;
	assumes ds,nothing
        assumes es,nothing

cProc   LongPtrAdd,<PUBLIC,FAR,NODATA>,<bx,cx,es,si,di>
        parmD   long_ptr
	parmD	delta
cBegin
        mov     si,long_ptr.sel
        cCall   GetSelectorBase,<si>
        add     ax,long_ptr.off
        adc     dx,0
        add     ax,delta.lo
        adc     dx,delta.hi

        push    ax
        and     ax,0FFF0h

        cCall   SetSelectorBase,<si,dx,ax>

        pop     ax
        and     ax,000Fh
        mov     dx,si
cEnd

;-----------------------------------------------------------------------;
; CopySel
;
; given a selector will make a copy of it.
;
; Entry:
;
; Returns:
;       AX new selector
;
; Error returns:
;       none
;
; Registers Destroyed:
;       DS,ES,SI,DI
;
;-----------------------------------------------------------------------;
	assumes ds,nothing
	assumes es,nothing

cProc   CopySel,<PUBLIC,FAR,NODATA>,<es>
        parmW   selD            ; destination selector
        parmW   selS            ; source selector
cBegin
        mov     ax,selD
        push    selS
        push    ax
        push    ax
        push    ax
        cCall   PrestoChangeoSelector       ; copy source to dest, set CODE
        cCall   PrestoChangeoSelector       ; copy dest to dest, clear CODE
cEnd

;-----------------------------------------------------------------------;
; AllocPtr
;
; converts a 16:32 pointer into a 16:16 pointer.
;
; Entry:
;       16:32 pointer
; Returns:
;       DX:AX new 16:16 pointer (selector must be freed with FreeSelector)
;
; Error returns:
;       none
;
; Registers Destroyed:
;       AX,BX,CX,DX,FLAGS
;
;-----------------------------------------------------------------------;
	assumes ds,nothing
	assumes es,nothing

cProc   AllocPtr,<PUBLIC,FAR,NODATA>,<es>
        parmW   ptr_sel         ; selector of far pointer
        parmD   ptr_off         ; far pointer offset
cBegin
        cCall   AllocSelector,<ptr_sel>
        cCall   LongPtrAdd,<ax,0,ptr_off>
cEnd

sEnd

end
