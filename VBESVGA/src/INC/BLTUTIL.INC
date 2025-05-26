;
;	FILE:	bltutil.inc
;	DATE:	9/1/90
;	AUTHOR: Jim Keller
;
;	This module holds routines that are useful in a fairly general
;	context throughout most of the device driver.
;

IFNDEF	SRCFILE_BLTUTIL
EXTRN	blt_clip:NEAR
EXTRN	blt_set_directions:NEAR
EXTRN	set_memory_address:NEAR
EXTRN	get_edge_masks_bytes:NEAR
EXTRN	prep_pattern_far:FAR
EXTRN	prep_pattern_norotate:NEAR
EXTRN	pattern_rotate:NEAR
EXTRN   get_exclusion_region:NEAR
EXTRN	sanitize_binary_rop:FAR
EXTRN	sanitize_ternary_rop:NEAR
ENDIF

