;
;
;      File:   GETRLE.INC
;      Author: James Keller
;      Date:   7/16/89
;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.

createSeg	_DIMAPS, DIMapSeg, word, public, code
sBegin		DIMapSeg

	assumes	cs, DIMapSeg

extrn	scanline_encode_bitmap:near
extrn	copyrle_i1e4:near
extrn	copyrle_i1e8:near
extrn	copyrle_i8e4:near
extrn	copyrle_i8e8:near

extrn	copyabs_i1e4:near
extrn	copyabs_i1e8:near
extrn	copyabs_i8e4:near
extrn	copyabs_i8e8:near

sEnd    DIMapSeg


