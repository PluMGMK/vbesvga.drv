;
;	FILE:	compblt.inc
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module contains routines that generate code into a dest.
;	Every routine in this module assumes that es:di points to the
;	place to store the compiled code.
;

IFNDEF	SRCFILE_COMPBLT
EXTRN	compile_mono_pattern_fetch:NEAR
EXTRN	compile_color_pattern_fetch:NEAR
EXTRN   compile_pattern_yupdate:NEAR
EXTRN	compile_rop:NEAR
EXTRN	compile_edge_mask:NEAR
EXTRN	compile_inner_loop_start:NEAR
EXTRN	compile_inner_loop_end:NEAR
EXTRN	compile_inner_loop_wraps:NEAR
EXTRN	compile_outer_loop:NEAR
EXTRN	compile_src_memory_yupdate:NEAR
EXTRN	compile_src_screen_yupdate:NEAR
EXTRN	compile_dst_memory_yupdate:NEAR
EXTRN	compile_screen_yupdate:NEAR
EXTRN   compile_jmp_back_to_start:NEAR
EXTRN	compile_src_splitbank_yupdate:NEAR
EXTRN	compile_dst_splitbank_yupdate:NEAR
EXTRN	compile_color_stosb:NEAR
ENDIF

