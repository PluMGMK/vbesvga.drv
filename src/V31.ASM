; v31.asm
; 11 November 1991
; Steve Glickman
; Headland Technology
;
; This module allocates public word windowsVersion
; and initializes it to 310h for Windows 3.10

	.xlist
	include cmacros.inc
	.list

	sBegin	Data

	public	windowsVersion
windowsVersion	dw	030ah

	sEnd    Data

	end


