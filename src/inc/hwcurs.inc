;
;	FILE:	hwcurs.inc
;	DATE:	1/9/91
;	AUTHOR: Jim Keller
;
;	This file handles the hardware cursor on the VRAM I, VRAM II,
;	and 1024I boards. (I think it also works on the VGA16.)

.286

IFNDEF	FILE_HWCURS
	EXTRN	hwcursor_set:NEAR
	EXTRN	hwcursor_move:NEAR
	EXTRN	hwcursor_check:NEAR
	EXTRN	hwcursor_off:NEAR
        EXTRN   hwcursor_exclude:NEAR
	EXTRN	hwcursor_unexclude:NEAR
	EXTRN	hwcursor_kludge:NEAR
ENDIF

