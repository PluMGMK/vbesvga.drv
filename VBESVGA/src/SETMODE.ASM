	page	,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	SETMODE.ASM
;
; This module contains the routine which is called by the control
; panel when a device is to change modes.
;
; Created: 16-Jan-1987
; Author:  Walt Moore [waltm]
;
; Copyright (c) 1983-1987 Microsoft Corporation
;
; Exported Functions:	DeviceMode
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
;	This function is a nop for all display drivers.
;
; Restrictions:
;
;-----------------------------------------------------------------------;
;	Copyright February, 1990  HEADLAND TECHNOLOGY, INC.

	.xlist
	include cmacros.inc
	include macros.mac
	.list


createSeg _BLUEMOON,BlueMoonSeg,word,public,CODE
sBegin	BlueMoonSeg
assumes cs,BlueMoonSeg
page
;--------------------------Exported-Routine-----------------------------;
; INT DeviceMode(hWnd,hInst,lpDeviceType,lpOutputFile)
; HWND	hWnd;
; HINST hInst;
; LPSTR lpDeviceType;
; LPSTR lpOutputFile;
; 
; This routine is a nop for all display drivers.  It returns -1 to
; show success, just to keep everyone happy.
;
; Warnings:
;	none
; Effects:
;	none
; Calls:
;	none
; History:
;	Wed 12-Aug-1987 17:29:30 -by-  Walt Moore [waltm]
;	made non-resident
;
;	Fri 16-Jan-1987 17:52:12 -by-  Walt Moore [waltm]
;	Initial version
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; INT DeviceMode(hWnd,hInst,lpDeviceType,lpOutputFile)
; HWND	hWnd;
; HINST hInst;
; LPSTR lpDeviceType;
; LPSTR lpOutputFile;
; {
;   return (-1);
; }
;-----------------------------------------------------------------------;


cProc	DeviceMode,<FAR,PUBLIC,WIN,PASCAL>,<si,di>

	parmW	h_wnd			;Handle to window
	parmW	h_inst			;Handle to instance
	parmD	lp_device_type		;Pointer to device (e.g. "HP7470")
	parmD	lp_output_file		;Pointer to output file (e.g. COM1:)


cBegin	<nogen>
	WriteAux <'DeviceMode'>
	mov	ax,-1			;Show success
	ret	12			;Return, popping parameters

cEnd	<nogen>

sEnd	BlueMoonSeg
end
