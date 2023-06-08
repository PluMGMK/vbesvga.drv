;***************************************************************************
;									   *
;   Copyright (C) 1985-1989 by Microsoft Inc.                              *
;									   *
;***************************************************************************

        title   Control Panel Color Table
	%out	config
	page	,132


RGB     macro   R, G, B
        db      R,G,B,0
	endm



COLORTABLE  segment public

        dw  48                  ; # colors in table
        RGB 0FFh,080h,080h
        RGB 0FFh,0FFh,0E8h
        RGB 0FFh,0FBh,0F0h
        RGB 000h,0FFh,080h
        RGB 080h,0FFh,0FFh
        RGB 000h,080h,0FFh
        RGB 0FFh,080h,0C0h
        RGB 0FFh,080h,0FFh
        RGB 0FFh,000h,000h
        RGB 0FFh,0FFh,080h
        RGB 080h,0FFh,000h
        RGB 0C0h,0DCh,0C0h
        RGB 000h,0FFh,0FFh
	RGB 0A4h,0C8h,0F0h	; cool blue
        RGB 080h,080h,0C0h
        RGB 0FFh,000h,0FFh
        RGB 080h,040h,040h
        RGB 0FFh,0FFh,000h
        RGB 000h,0FFh,000h
        RGB 000h,080h,080h
        RGB 000h,040h,080h
        RGB 080h,080h,0FFh
        RGB 080h,000h,040h
        RGB 0FFh,000h,080h
        RGB 080h,000h,000h
        RGB 0FFh,080h,000h
        RGB 000h,080h,000h
        RGB 000h,080h,040h
        RGB 000h,000h,0FFh
        RGB 000h,000h,040h
        RGB 080h,000h,080h
        RGB 080h,000h,0FFh
        RGB 040h,000h,000h
        RGB 080h,040h,000h
        RGB 000h,040h,000h
        RGB 000h,040h,040h
        RGB 000h,000h,080h
        RGB 0A0h,0A0h,0A0h
        RGB 040h,000h,040h
        RGB 040h,000h,080h
        RGB 000h,000h,000h
        RGB 080h,080h,000h
        RGB 080h,080h,040h
        RGB 080h,080h,080h
        RGB 040h,080h,080h
        RGB 0C0h,0C0h,0C0h
        RGB 040h,000h,040h
        RGB 0FFh,0FFh,0FFh
COLORTABLE     ends
end
