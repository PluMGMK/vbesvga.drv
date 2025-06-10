;
;	File: RLEDAT.INC
;	Date: 7/24/89
;	Author: James Keller
;
;	This file contains some data structures and constants that are
;	specific to the rle encoding and decoding of bitmaps.
;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.


COLOR_TABLE_SIZE		EQU	0100H
MINIMUM_ABSOLUTE_LENGTH 	EQU	3

RLE_TYPE_END_OF_LINE		EQU	0000H
RLE_TYPE_END_OF_FRAME		EQU	0100H
RLE_TYPE_SKIP			EQU	0200H
RLE_TYPE_ABSOLUTE		EQU	00H

MAXIMUM_RLE_LENGTH_I1		EQU	001FH
MAXIMUM_RLE_LENGTH_I8		EQU	00FFH
NOF_EXTERNAL_RLE_TYPES		EQU	2

