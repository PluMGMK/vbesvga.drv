        page    ,132
;
;-----------------------------Module-Header-----------------------------;
; Module Name:	DCI.INC
;
;   This module contains DCI defnitions adapted from dciddi.h in the
;   DCI Development Kit.
;
; Created: 23-Aug-2025
; Author:  PluMGMK
;
; Exported Functions:	None
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
; Restrictions:
;
;-----------------------------------------------------------------------;

; DCI Command Escapes                                                                
DCICOMMAND			equ 3075
DCI_VERSION			equ 0100h

DCICREATEPRIMARYSURFACE		equ 1 
DCICREATEOFFSCREENSURFACE       equ 2 
DCICREATEOVERLAYSURFACE         equ 3
DCIENUMSURFACE                  equ 4 
DCIESCAPE                       equ 5

; DCI-Defined error codes 
DCI_OK                          equ 0 ; success 

; Hard errors -- DCI will be unavailable 
DCI_FAIL_GENERIC                equ -1
DCI_FAIL_UNSUPPORTEDVERSION     equ -2
DCI_FAIL_INVALIDSURFACE         equ -3
DCI_FAIL_UNSUPPORTED            equ -4    

; Soft errors -- DCI may be available later 
DCI_ERR_CURRENTLYNOTAVAIL       equ -5
DCI_ERR_INVALIDRECT             equ -6
DCI_ERR_UNSUPPORTEDFORMAT       equ -7
DCI_ERR_UNSUPPORTEDMASK         equ -8
DCI_ERR_TOOBIGHEIGHT            equ -9
DCI_ERR_TOOBIGWIDTH             equ -10
DCI_ERR_TOOBIGSIZE              equ -11
DCI_ERR_OUTOFMEMORY             equ -12
DCI_ERR_INVALIDPOSITION         equ -13
DCI_ERR_INVALIDSTRETCH          equ -14
DCI_ERR_INVALIDCLIPLIST         equ -15
DCI_ERR_SURFACEISOBSCURED       equ -16
DCI_ERR_XALIGN			equ -17
DCI_ERR_YALIGN			equ -18
DCI_ERR_XYALIGN			equ -19
DCI_ERR_WIDTHALIGN		equ -20
DCI_ERR_HEIGHTALIGN		equ -21
											 
; success messages -- DCI call succeeded, but specified item changed 
DCI_STATUS_POINTERCHANGED       equ  1
DCI_STATUS_STRIDECHANGED        equ  2
DCI_STATUS_FORMATCHANGED        equ  4
DCI_STATUS_SURFACEINFOCHANGED   equ  8
DCI_STATUS_CHROMAKEYCHANGED     equ 16				
DCI_STATUS_WASSTILLDRAWING      equ 32


; DCI Capability Flags 
DCI_SURFACE_TYPE		equ 0000000Fh
DCI_PRIMARY                 	equ 00000000h
DCI_OFFSCREEN               	equ 00000001h
DCI_OVERLAY                 	equ 00000002h

DCI_VISIBLE                 	equ 00000010h
DCI_CHROMAKEY               	equ 00000020h
DCI_1632_ACCESS             	equ 00000040h
DCI_DWORDSIZE               	equ 00000080h
DCI_DWORDALIGN              	equ 00000100h
DCI_WRITEONLY               	equ 00000200h
DCI_ASYNC                   	equ 00000400h

DCI_CAN_STRETCHX            	equ 00001000h
DCI_CAN_STRETCHY            	equ 00002000h
DCI_CAN_STRETCHXY           	equ (DCI_CAN_STRETCHX | DCI_CAN_STRETCHY)

DCI_CAN_STRETCHXN           	equ 00004000h
DCI_CAN_STRETCHYN           	equ 00008000h
DCI_CAN_STRETCHXYN          	equ (DCI_CAN_STRETCHXN | DCI_CAN_STRETCHYN)


DCI_CANOVERLAY                  equ 00010000h

; supplementing BI_* in gdidefs.inc
BI_BITFIELDS    equ	   3h

;
; Win32 RGNDATA structure.  This will be used for  cliplist info. passing.
;

RECTL	struc
rl_left		dd ?
rl_top		dd ?
rl_right	dd ?
rl_bottom	dd ?
RECTL	ends

RDH_RECTANGLES  equ 0

RGNDATAHEADER	struc
_dwSize		dd ?			; size of structure             
iType		dd ?			; Will be RDH_RECTANGLES        
nCount		dd ?			; # of clipping rectangles      
nRgnSize	dd ?			; size of buffer -- can be zero 
rcBound		db (size RECTL) dup (?)	; bounding  rectangle for region
RGNDATAHEADER	ends

RGNDATA	struc
rdh		db (size RGNDATAHEADER) dup (?)
Buffer		db ?
RGNDATA	ends

;*************************************************************************
;	input structures
;*************************************************************************

;
; Used by a DCI client to provide input parameters for the 
; DCICREATEPRIMARYSURFACE escape.
;
DCICMD	struc
dwCommand	dd ?
dwParam1	dd ?
dwParam2	dd ?
dwVersion	dd ?
dwReserved	dd ?
DCICMD	ends

;
; This structure is used by a DCI client to provide input parameters for 
; the DCICREATE... calls.  The fields that are actually relevant differ for 
; each of the three calls.  Details are in the DCI Spec chapter providing 
; the function specifications.
;
DCICREATEINPUT	struc
CIcmd		db (size DCICMD) dup (?); common header structure 
dwCICompression	dd ?      		; format of surface to be created
dwCIMask	dd 3 dup (?)		; for  nonstandard RGB (e.g. 5-6-5, RGB32)
dwCIWidth	dd ?			; height of the surface to be created
dwCIHeight	dd ?			; width of input surfaces
dwCIDCICaps	dd ?			; capabilities of surface wanted
dwCIBitCount	dd ?			; bit depth of format to be created
lpSurface	dd ?			; pointer to an associated surface
DCICREATEINPUT	ends


;
; This structure is used by a DCI client to provide input parameters for the 
; DCIEnumSurface call.
;
DCIENUMINPUT	struc
EIcmd		db (size DCICMD) dup (?); common header structure 
rSrc		db (size RECT) dup (?)	; source rect. for stretch  
rDst		db (size RECT) dup (?)	; dest. rect. for stretch       
EnumCallback	dd ?			; callback for supported formats
		; sig void EnumCallback(LPDCISURFACEINFO, LPVOID);
lpContext	dd ?
DCIENUMINPUT	ends

;*************************************************************************
;	surface info. structures
;*************************************************************************

;
; This structure is used to return information about available support
; during a DCIEnumSurface call.  It is also used to create a primary 
; surface, and as a member of the larger structures returned by the 
; offscreen and overlay calls.
;
DCISURFACEINFO	struc
dwSize		dd ?		; size of structure
dwSIDCICaps	dd ?		; capability flags (stretch, etc.)
dwSICompression	dd ?      	; format of surface to be created
dwSIMask	dd 3 dup (?)	; for BI_BITMASK surfaces

dwSIWidth	dd ?		; width of surface
dwSIHeight	dd ?		; height of surface
lStride		dd ?		; distance in bytes betw. one pixel
		    		; and the pixel directly below it
dwSIBitCount	dd ?		; Bits per pixel for this dwCompression
dwOffSurface	dd ?		; offset of surface pointer
wSelSurface	dw ?		; selector of surface pointer
wReserved	dw ?	

dwReserved1	dd ?		; reserved for provider
dwReserved2	dd ?		; reserved for DCIMAN
dwReserved3	dd ?		; reserved for future
BeginAccess	dd ?		; BeginAccess callback
		; sig DCIRVAL BeginAccess(LPVOID, LPRECT);
EndAccess	dd ?		; EndAcess callback
		; sig void EndAccess(LPVOID);
DestroySurface	dd ?		; Destroy surface callback
		; sig void DestroySurface(LPVOID);
DCISURFACEINFO	ends
