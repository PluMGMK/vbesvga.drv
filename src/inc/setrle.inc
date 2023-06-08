;
;
;      File:   SETRLE.INC
;      Author: James Keller
;      Date:   7/16/89
;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.

createSeg	_DIMAPS, DIMapSeg, word, public, code
sBegin		DIMapSeg

	assumes	cs, DIMapSeg

extrn	scanline_decode_bitmap:near

sEnd	DIMapSeg


