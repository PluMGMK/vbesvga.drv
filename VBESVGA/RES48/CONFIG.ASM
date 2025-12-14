;***************************************************************************
;									   *
;   Copyright (C) 1985-1989 by Microsoft Inc.                              *
;									   *
;***************************************************************************

	title	Hardware Dependent Parameters
	%out	config
	page	,132


RGB     macro   R, G, B
        db      R,G,B,0
	endm



OEM	segment public

;	Machine dependent parameters

        dw      10                      ;Height of vertical thumb
        dw      10                      ;Width of horizontal thumb
	dw	4			;Icon horiz compression factor
	dw	4			;Icon vert compression factor
	dw	1			;Cursor horz compression factor
	dw	1			;Cursor vert compression factor
	dw	0			;Kanji window height
	dw	1			;cxBorder (thickness of vertical lines)
	dw	1			;cyBorder (thickness of horizontal lines)


;       Default system color values

        RGB 192,192,192     ;clrScrollbar
        RGB 160,160,164     ;clrDesktop
        RGB 164,200,240     ;clrActiveCaption
        RGB 255,255,255     ;clrInactiveCaption
        RGB 255,255,255     ;clrMenu
        RGB 255,255,255     ;clrWindow
        RGB 000,000,000     ;clrWindowFrame
        RGB 000,000,000     ;clrMenuText
        RGB 000,000,000     ;clrWindowText
        RGB 000,000,000     ;clrCaptionText
        RGB 192,192,192     ;clrActiveBorder
        RGB 192,192,192     ;clrInactiveBorder
        RGB 255,251,240     ;clrAppWorkspace
        RGB 164,200,240     ;clrHiliteBk
        RGB 000,000,000     ;clrHiliteText
        RGB 192,192,192     ;clrBtnFace
        RGB 128,128,128     ;clrBtnShadow
        RGB 192,192,192     ;clrGrayText
        RGB 000,000,000     ;clrBtnText


;	dw	0			;Unused words
;	dw	0
;	dw	0
;	dw	0
;	dw	0
;	dw	0
	dw	0
	dw	0

OEM	ends
end
