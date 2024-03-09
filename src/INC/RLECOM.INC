
;
;	File:	RLECOM.INC
;	Date:	7/24/89
;	Author:	James Keller
;
;	This module handles routines common to getting and setting rle DIBs.
;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.


createSeg	_DIMAPS, DIMapSeg, word, public, code
sBegin		DIMapSeg

	assumes	cs, DIMapSeg

extrn	copyrle_e4i1:near
extrn	copyrle_e8i1:near
extrn	copyrle_e4i8:near
extrn	copyrle_e8i8:near

extrn	copyabs_e4i1:near
extrn	copyabs_e8i1:near
extrn	copyabs_e4i8:near
extrn	copyabs_e8i8:near

sEnd	DIMapSeg


