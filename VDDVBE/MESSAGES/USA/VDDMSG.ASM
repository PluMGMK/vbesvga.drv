	TITLE	VDD - Virtual Display Device for VGA
;******************************************************************************
;
;VDDMSG.ASM	Messages for VDD
;
;   Author: MDW
;
;   (C) Copyright MICROSOFT Corp. 1986 - 1991
;
;DESCRIPTION:
;
;******************************************************************************

        .386p

	INCLUDE VMM.INC

VxD_IDATA_SEG

BeginMsg
;***************
; Load time error messages
;
; The following is a message that results from incorrect installation of
;   device drivers. Another device driver is conflicting with the VDD.
PUBLIC VDD_Str_CheckVidPgs
VDD_Str_CheckVidPgs DB	"Cannot run Windows because of video device "
		    DB	"conflict. You need to run the Setup program "
		    DB	"again.",0

; The following is a message that results from incorrect initialization of
;   of the VDD, probably due to insufficient memory, incorrect display
;   adapter or bad files. User should verify that enough system memory
;   is available and that SETUP was completed properly.
PUBLIC VDD_Str_BadDevice
VDD_Str_BadDevice   DB	"Video initialization failed. You need to run "
		    DB	"the Setup program again.",0

;******************************************************************************
;
; INI entry for window update time.
;
PUBLIC VDD_Time_Ini
VDD_Time_Ini db "WindowUpdateTime", 0

;******************************************************************************
;
; INI entry to disable message when background application is suspended or
;   its display becomes corrupt due to inability to handle video memory access.
;   Default is true, the message will be generated.
;
;   This allows users to run background applications that they know get
;   suspended sometimes but don't want to deal with the error message.
;
PUBLIC VDD_SuspMsg_Ini
VDD_SuspMsg_Ini db "VideoBackgroundMsg", 0

;******************************************************************************
;
; INI entry to allow VM display corruption in background, rather
;	than suspending the VM.  When this occurs the "NoMainMem" message
;	will be generated unless the SuspMsg INI switch is set false.
;	Default is false, the application will be suspended.
;
PUBLIC VDD_NoSusp_Ini
VDD_NoSusp_Ini db "VideoSuspendDisable", 0

;******************************************************************************
;
; INI entry for Initial number of text rows
;
PUBLIC Vid_Text_Rows_Ini,Vid_Text_Rows_Sect
Vid_Text_Rows_Ini db "ScreenLines", 0
Vid_Text_Rows_Sect db "NonWindowsApp", 0	; System.ini section name

; INI entres that detemine whether the VDDVGA will manage the monochrome
;	text (B0000h-B7000h) address area or leave it alone, allowing
;	other devices to use the address space.  Note that the
;	VGAMONOTEXT entry is new for 3.1.  It provides for the case
;	where there is no secondary display or secondary display
;	device but the user still does not want VGA mono support.
;	Also note that for 3.1 it is not an error if we attempt to
;	provide VGA mono support but some other device has grabbed
;	the address space already (we just won't support VGA mono).
;	Following is a description of the logic followed:
;
;   IF
;	1) Secondary VDD does not exist (it will reserve it)
;	    AND
;	2) "DUALDISPLAY=YES" OR Secondary display is detected
;	    AND
;	3) Other VxD (e.g. Upper Memory Blocks) has not reserved pages B0-B7
;
;   THEN Reserve and map pages B0-B7 physical for secondary display.
;	    The memory is address space is not available for any use other
;	    than accessing the physical memory at pages B0-B7.
;
;   ELSE IF
;	1) Secondary VDD does not exist (it will reserve it)
;	    AND
;	2) "DUALDISPLAY=NO" OR Secondary display is not detected
;	    AND
;	3) NOT ("VGAMONOTEXT=NO")
;	    AND
;	4) "VGAMONOTEXT=YES" OR Windows started when video in mono mode
;	    AND
;	5) Other VxD (e.g. Upper Memory Blocks) has not reserved pages B0-B7
;
;   THEN Reserve and hook pages B0-B7 for VGA mono support.
;
;   ELSE VGA Mono not supported, pages B0-B7 not handled.  The address space
;	    is available for any use.  This may be by a 2nd VDD or by a
;	    DOS UMB or by translation buffers from protected mode to virtual
;	    mode.
;
; If user sets "DUALDISPLAY=NO" with monochrome adapter attached the results
;	are undefined.	In this case we may provide VGA mono support which
;	will conflict with the existing secondary monochrome display.
;
PUBLIC VDD_2nd_Ini
VDD_2nd_Ini  db "DualDisplay", 0
PUBLIC VDD_Mono_Text_Ini
VDD_Mono_Text_Ini   db "VGAMonoText", 0

;******************************************************************************
;
;   Some VGA adapters have ROM at C6 and C7 but do not put a ROM signature
;   in the ROM, so the V86MMGR determines that it is free address space and
;   uses it for buffers.  If this is set TRUE, or the VDD detects one of these
;   ROMs, we will exclude the memory from C6000h to C7FFFh from other usage
;   and the memory will always be addressable.	If this is set FALSE, we will
;   not do anything and the address space may be reused by the system or used
;   for any other reason.
PUBLIC VDD_Rsrv_C6C7_Ini
VDD_Rsrv_C6C7_Ini   DB	"ReserveVideoROM",0

;******************************************************************************
;
; INI entry for specifying the amount of video memory on the VGA adapter
;   Default is 256, use this switch to specify the amount of memory
;   installed on the VGA adapter in kilo bytes (Kb)
;
PUBLIC VDD_SVGA_Mem_Ini
VDD_SVGA_Mem_Ini	db 'SVGAmemory', 0


;******************************************************************************
;
; INI entry for disabling automatic save/restore of other display API aware
;   applications.
;   Default is TRUE, so that automatic save/restore is enabled.  Setting this
;   switch to FALSE, avoids allocating save memory for applications which
;   notify enhanced mode Windows that they know how to restore/repaint their
;   screen themselves.	By setting this switch to FALSE, switching to some
;   applications may be somewhat slower, because the application will be
;   responsible for repainting its screen which usually takes more time than
;   if Windows handles the screen restore automatically.
;
PUBLIC VDD_VM_SaveRes_Ini
VDD_VM_SaveRes_Ini   db 'AutoRestoreScreen', 0

;******************************************************************************
;
; INI entry for adjusting the scrolling frequency for dos apps. VDD will attempt
;   to scroll once in these many times. This does NOT provide a guarantee that
;   an update will be generated once for n lines. Updates might be generated
;   more often due to asynch events such as mouse clicks.
;
PUBLIC VDD_VM_Scroll_Freq_Ini
VDD_VM_Scroll_Freq_Ini   db 'ScrollFrequency',0

;******************************************************************************
;
; INI entry for changing when the automatic save/restore background
; notification is sent.  For displays that don't have special display
; hardware (e.g. blitters), it is possible to hold off sending a
; background notification into a VM until it actually page faults.
; The VDD will then send the notification and map NULL memory so the
; VM can proceed, but doesn't access actual video memory.  For displays
; that do have special display hardware, waiting until a page fault
; may be to late, because it may be trying to access video memory
; directly on the adapter, so there may not even be a page fault!  On
; these displays it is necessary to send the background notification
; as early as possible.
;
; Setting this switch to FALSE forces the early notification, setting it
; to TRUE specifies that the notification can wait until page fault time.
;
; The default setting for VGA is TRUE, and for 8514 it is FALSE.
;
PUBLIC VDD_BkGnd_Notify_Time
VDD_BkGnd_Notify_Time db 'BkGndNotifyAtPFault', 0

;******************************************************************************
;
; INI entry for disabling the use of the soft font stored in the video ROM for
; the message mode font (the font used in full screen message text and in the
; switcher screen displayed when switching away from a DOS VM.)  Set this
; switch to FALSE to disable.  This switch would be used on machines where a
; different soft font is programmed by a TSR or device driver, etc. or where
; the video ROM is banked so that the font isn't always addressable.  The
; first possibility would be identified by seeing that the font in message
; mode is different from the normally used font.  The second possibility would
; be identified by seeing random dots and weird shapes that appear in rows and
; columns like text, but aren't readable; this condition indicates that the
; font is not programmed correctly.
;
PUBLIC VDD_Use_ROM_Font_Ini
VDD_Use_ROM_Font_Ini db 'UseROMfont', 0

;******************************************************************************
;
; INI entry to disable "bouncing" the focus VM to background then foreground
; when a windowed / background VM does a modeset.  Set this switch to FALSE
; to disable.  This switch would be used on machines where the BIOS doesn't
; touch any registers unknown to VDDVBE during a VGA modeset, so the correct
; video state is recoverable after a non-focus modeset without an expensive
; reset of the VBE mode.
;
PUBLIC VDD_VBESVGA_Sec
VDD_VBESVGA_Sec db "VBESVGA.DRV", 0	; put this config option with the others
PUBLIC VDD_Bounce_Ini
VDD_Bounce_Ini db 'BounceOnModeset', 0

IFDEF SysVMin2ndBank
;******************************************************************************
;
; INI entry for disabling the option of running the Windows VM in the 2nd bank
; of video memory.  Many super VGA adapters have 512Kb or more of video memory.
; On some of these it is possible for the VDD to run the Windows VM in the 2nd
; bank of 256Kb when using the standard VGA.DRV or SUPERVGA.DRV.  This allows
; switching from DOS VM's back to the Windows VM without repainting all of the
; Windows apps.  Setting this switch to FALSE disables this feature.
;
PUBLIC VDD_2ndBank_Ini
VDD_2ndBank_Ini db 'SysVMin2ndBank', 0
ENDIF
EndMsg


IFDEF IBMXGA
;******************************************************************************
;
; INI entry for enabling the software fix for a compatibility difference
; between standard VGA and some IBM implementations of VGA.  This switch
; needs to be set to TRUE on machines that have XGA hardware enabled, but
; Windows is installed with the VGA driver.  And it should also be set to
; TRUE on other IBM machines, such as the Model 75 portable, where the user
; experiences problems with windowed text mode VM's.  Usually the problem
; shows as missing every other character in the windowed VM, and if the VM
; is switched to full screen the display is total trash, because the font
; is no longer programmed correctly.  Currently we only know of this being
; a problem on IBM PS/2 machines, and we don't know which models actually
; have this problem.
;
PUBLIC VDD_XGA_Ini
VDD_XGA_Ini db 'IBMVGAfix', 0
ENDIF


VxD_IDATA_ENDS


VxD_DATA_SEG

BeginMsg
;***************
; Load time error messages
;
; The following is a message that results from the inability of the VDD
;   to allocate GDT selectors for the display driver's use.
PUBLIC	DspDrvInitFailed
DspDrvInitFailed db "Display-driver ring transition initialization failed.", 0

IFDEF MapMonoError
;***************
; Video Message Box text.
;	The caption of the message box is always the VM name. Note that
;	the messages that indicate that the application cannot run in the
;	background may be transitory. Many applications will change their
;	screen mode in the course of program execution.
;
;
; The following is a message that appears when the virtual display device
;   has detected a VM which has mapped video memory at page B0 when
;   that mapping is not supported by the VDD.  The user can get the
;   VDD to support mono mapping by either starting Windows when in a
;   monochrome video mode or setting "VGAMONOTEXT=TRUE" in SYSTEM.INI
PUBLIC VMB_Str_MapMono
VMB_Str_MapMono     DB	13, 10
		    DB	"This application has attempted to enter a video mode that is not ", 13, 10
		    DB	"supported.  Change your SYSTEM.INI file to include the line: ",0Dh,0Ah
		    DB	"VGAMONOTEXT=TRUE",0Dh,0Ah
		    DB	"in the [386Enh] section, and then restart Windows.",13,10,0
ENDIF


; The following is a message that appears when the virtual display device
;   attempts to save the state of the video adapter and runs out of memory
;   The display for the app is probably corrupted. The user should free up
;   some memory by closing another application or getting another application
;   to free up some of its data and then get the application to redraw its
;   display. In some cases, the user will need to exit the application and
;   start it up again in order to redraw the display.
PUBLIC VMB_Str_NoMainMem
VMB_Str_NoMainMem   DB	"There is not enough available memory for this "
		    DB	"application to correctly display information. "
		    DB	"Make sure the application's PIF settings are "
		    DB	"correct.",0

; The following is a message that appears when the virtual display device
;   attempts to provide an application with physical memory, but because
;   of other VM usage of the video memory, it was unable to satisfy the
;   need.  The display for the app is probably corrupted. The user should
;   disable running this application in the background or just redraw the
;   display using application specific redraw command or, if the application
;   does not support redraw, the user should exit and restart the application.
PUBLIC VMB_Str_NoPagesAvail
VMB_Str_NoPagesAvail DB "This application was unable to access the video "
		    DB	"display. Its display was not updated. "
		    DB	"Check the PIF settings to ensure they are correct. "
		    DB	"If the display is erratic, redraw the display or "
		    DB	"restart the application.",0

; The following is a message that appears when the virtual display device
;   is not able to run a background VM because the forground VM is running
;   in a mode that does not support high resolution graphics in the
;   background and this VM runs in high resolution graphics.  When the
;   screen focus changes, this VM may start to run again.
PUBLIC VMB_Str_NoFGrnd
VMB_Str_NoFGrnd     DB	"You cannot run this application while another "
		    DB	"high-resolution application is running in a full "
		    DB	"screen. The application will be suspended until a "
		    DB	"low-resolution or text application is running in a "
		    DB	"full screen. Check the PIF settings to ensure "
		    DB	"they are correct.",0

; The following is a message notify the user that an application is being
;   converted to full screen so that memory needs can be satisfied.  By
;   converting the application to full screen it can continue to run
;   without screen corruption.	The application can probably be windowed
;   again once the critical memory needs have been satisfied.
PUBLIC VMB_Str_CvtFullScrn
VMB_Str_CvtFullScrn DB	"This application was unable to allocate necessary "
		    DB	"display memory. It is being converted to a full "
		    DB	"screen so that display memory can be allocated. "
		    DB	"Check the PIF video memory settings to ensure they "
		    DB	"are correct.", 0

;************************************************************
; The following are not used in the 3.1 VDDVGA

IF 0
; The following is a message that appears when the virtual display device
;   detects an application that is using the display in a way so that it
;   cannot run simultaneously with Windows or other high resolution graphics
;   applications. Text mode applications can run in the background while
;   this application runs in the forground.
PUBLIC VMB_Str_Exclusive
VMB_Str_Exclusive   DB	"You cannot run this application in a window or in "
		    DB	"the background. You can display it in a window, "
		    DB	"but it will be suspended until you run it in a "
		    DB	"full screen. Check the PIF settings to ensure "
		    DB	"they are correct.",0

; The following is a message that appears when the virtual display device
;   detects an application that using the display in a way so that it
;   cannot run in the background or be displayed in a window. Text mode
;   applications can run in the background while this application runs in
;   the forground.
PUBLIC VMB_Str_NotWindow
VMB_Str_NotWindow   DB	"You cannot display this application in a window "
		    DB	"or run it in the background. It will be suspended "
		    DB	"until you display it in a full screen. Check the "
		    DB	"PIF settings to ensure they are correct.",0

; The following is a message that appears when the virtual display device
;   is not able to correctly handle a mode change or video memory access
;   by a VM.  This will usually occur for a high resolution VM running in
;   the background or not exclusive.  The user should run this application
;   in full screen, exclusive mode and not in the background.  The display
;   for the app is probably corrupted. In some cases, the user will need
;   to exit the application and start it up again in order to redraw the
;   display.
PUBLIC VMB_Str_NoSupMode
VMB_Str_NoSupMode   DB	"This application will be suspended until you run it "
		    DB	"in a full screen. Check the PIF settings to ensure "
		    DB	"they are correct. If you need to restore the "
		    DB	"display, restart the application.",0
ENDIF

EndMsg

IF 0
; The following switch was removed from 3.1 for lack of testing.  I didn't
; want to document a switch controlled feature that hadn't gotten enough
; testing.
;
;******************************************************************************
;
; INI entry for disabling automatic save/restore of SYS VM
;   Default is FALSE, so that automatic save/restore is disabled.  Setting this
;   switch to FALSE, avoids allocating save memory for the SYS VM, but then
;   requires Windows to repaint all Windows applications when focus is restored
;   to the SYS VM.
;
PUBLIC VDD_SysVM_SaveRes_Ini
VDD_SysVM_SaveRes_Ini	db 'AutoRestoreWindows', 0
ENDIF


VxD_DATA_ENDS

END
