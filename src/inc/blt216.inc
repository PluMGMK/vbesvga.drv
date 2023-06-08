;
;	FILE:	blt216.inc
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module contains routines that deal with screen to screen blts
;	using 216 advanced hardware features (align src to dst and ROP hw.)
;

EXTRN	blt216_src_dst:NEAR
EXTRN	blt216_pat_dst:NEAR

