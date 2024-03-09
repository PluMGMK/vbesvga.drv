;
;	FILE:	swcurs.inc
;	DATE:	1/9/91
;	AUTHOR: Jim Keller
;
;	This file handles the software cursor on the VRAM I, VRAM II,
;	and 1024I boards. (I think it also works on the VGA16.) This

.286

IFNDEF	FILE_SWCURS
	EXTRN	swcursor_set:NEAR
	EXTRN	swcursor_move:NEAR
	EXTRN	swcursor_check:NEAR
	EXTRN	swcursor_off:NEAR
        EXTRN   swcursor_exclude:NEAR
	EXTRN	swcursor_unexclude:NEAR
ENDIF

