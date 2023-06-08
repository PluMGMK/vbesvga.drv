;
;	File: RLEDAT.ASM
;	Date: 7/24/89
;	Author: James Keller
;
;	This file contains some data structures and constants that are
;	specific to the rle encoding and decoding of bitmaps.
;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.



include	cmacros.inc
include	macros.mac
include	gdidefs.inc
include getrle.inc
include rlecom.inc

                              
createSeg	_DIMAPS, DIMapSeg, word, public, code
sBegin		DIMapSeg

	assumes	cs, DIMapSeg

public	encode_rle_table
encode_rle_table        label   word
dw	OFFSET	copyrle_i8e4
dw	OFFSET	copyrle_i8e8
dw	OFFSET	copyrle_i1e4
dw	OFFSET	copyrle_i1e8


public	encode_absolute_table
encode_absolute_table   label   word
dw	OFFSET	copyabs_i8e4
dw	OFFSET	copyabs_i8e8
dw	OFFSET	copyabs_i1e4
dw	OFFSET	copyabs_i1e8


public	decode_rle_table
decode_rle_table        label   word
dw	OFFSET	copyrle_e4i8
dw	OFFSET	copyrle_e8i8
dw	OFFSET	copyrle_e4i1
dw	OFFSET	copyrle_e8i1


public	decode_absolute_table
decode_absolute_table   label   word
dw	OFFSET	copyabs_e4i8
dw	OFFSET	copyabs_e8i8
dw	OFFSET	copyabs_e4i1
dw	OFFSET	copyabs_e8i1

sEnd	DIMapSeg

END
