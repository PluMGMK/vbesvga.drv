//----------------------------------------------------------------------------
//  Project Vbesvga
//
//  Copyright 2026. All Rights Reserved.
//
//  SUBSYSTEM:    Vbesvga Application
//  FILE:         vbsvgdlc.cpp
//  AUTHOR:       
//
//  OVERVIEW
//  ~~~~~~~~
//  Source file for implementation of TVbesvgaDlgClient (TDialog).
//
//----------------------------------------------------------------------------

#include <owl/pch.h>

#include "vbsvgapp.h"
#include "vbsvgdlc.h"
#include "vbsvgdmo.h"
#include <stdio.h>
#include <fstream>
#include <iostream>

//
// Build a response table for all messages/commands handled by the application.
//
DEFINE_RESPONSE_TABLE1(TVbesvgaDlgClient, TDialog)
//{{TVbesvgaDlgClientRSP_TBL_BEGIN}}
  EV_WM_SETFONT,
  EV_WM_HSCROLL,
  EV_LBN_SELCHANGE(IDC_DEPTH, LBNSelchange),
  EV_BN_CLICKED(IDOK, BNOKClicked),
  EV_COMMAND(CM_HELPABOUT, CmHelpabout),
  EV_COMMAND(CM_MOREOPTIONSITEM, CmMoreoptionsitem),
  EV_COMMAND(CM_HELPLOAD, CmHelpload),
  EV_BN_CLICKED(IDC_RADIOBUTTON1, BNClickedAuto),
  EV_BN_CLICKED(IDC_RADIOBUTTON2, BNClickedNativeDPI),
  EV_BN_CLICKED(IDC_RADIOBUTTON3, BNClickedTiny),
  EV_BN_CLICKED(IDC_RADIOBUTTON4, BNClickedSmall),
  EV_BN_CLICKED(IDC_RADIOBUTTON5, BNClickedLarge),

  EV_LBN_SELCHANGE(IDC_RESOLUTION, LBNSelchangeResolution),
//{{TVbesvgaDlgClientRSP_TBL_END}}
END_RESPONSE_TABLE;


//{{TVbesvgaDlgClient Implementation}}


//--------------------------------------------------------
// TVbesvgaDlgClient
// ~~~~~~~~~~
// Construction/Destruction handling.
//
static TVbesvgaDlgClientXfer TVbesvgaDlgClientData;

TVbesvgaDlgClient::TVbesvgaDlgClient(TWindow* parent, TResId resId, TModule* module)
:
  TDialog(parent, resId, module)
{
//{{TVbesvgaDlgClientXFER_USE}}
  ResolutionList = new TListBox(this, IDC_RESOLUTION);

  SetTransferBuffer(&TVbesvgaDlgClientData);
//{{TVbesvgaDlgClientXFER_USE_END}}

  // INSERT>> Your constructor code here.

}

static void SaveData()
{
    char systemINI[255];
    char systemINInew[255];
    char line_buffer[255];
    int foundDriverLine = -1;

    GetWindowsDirectory(systemINI, 255);
    strcpy(systemINInew, systemINI);
    strcat(systemINInew, "\\SYSTEM.VBE");
    strcat(systemINI, "\\SYSTEM.INI");

    FILE *fp = fopen(systemINI, "r");
    FILE *fp_t = fopen(systemINInew, "w");

    // Create a temporary SYSTEM.VBE to copy off SYSTEM.INI. Overwrite the [VBESVGA.DRV] entries with the user's choice
    // Then, delete SYSTEM.INI and rename SYSTEM.VBE afterward

    while (fgets(line_buffer, sizeof(line_buffer), fp) != NULL)
    {
        if ((strstr(line_buffer, "[VBESVGA.DRV]") != NULL) ||
            (strstr(line_buffer, "[vbesvga.drv]") != NULL))
        {
            fputs(line_buffer, fp_t);
            foundDriverLine = 1;
        }
        else if (foundDriverLine == 1 || foundDriverLine == 2)
        {
            if (strstr(line_buffer, "[") != NULL)
            {
                fputs(line_buffer, fp_t);
                foundDriverLine = 0;
            }
            else if (foundDriverLine == 1)
            {
                for (int i = 0; i < 11; i++)
                {
                    if (settings[i][1] != defaultSettings[i])
                    {
                        strcpy(line_buffer, settings[i][0].c_str());
                        strcat(line_buffer, "=");
                        strcat(line_buffer, settings[i][1].c_str());
                        strcat(line_buffer, "\n\0");
                        fputs(line_buffer, fp_t);
                    }
                }
                fputs("\n", fp_t);
                foundDriverLine = 2;
            }
        }
        else
        {
            if (strstr(line_buffer, "oemfonts.fon") != NULL)
            {
                if (settings[3][1] == "auto" || settings[3][1] == "nativedpi")
                {
                    fputs(line_buffer, fp_t);
                }
                else if (settings[3][1] == "tiny")
                {
                    fputs("oemfonts.fon=lroem.fon\n", fp_t);
                }
                else if (settings[3][1] == "small")
                {
                    fputs("oemfonts.fon=vgaoem.fon\n", fp_t);
                }
                else
                {
                    fputs("oemfonts.fon=8514oem.fon\n", fp_t);
                }
            }
            else if (strstr(line_buffer, "fixedfon.fon") != NULL)
            {
                if (settings[3][1] == "auto" || settings[3][1] == "nativedpi")
                {
                    fputs(line_buffer, fp_t);
                }
                else if (settings[3][1] == "tiny")
                {
                    fputs("fixedfon.fon=lrfix.fon\n", fp_t);
                }
                else if (settings[3][1] == "small")
                {
                    fputs("fixedfon.fon=vgafix.fon\n", fp_t);
                }
                else
                {
                    fputs("fixedfon.fon=8514fix.fon\n", fp_t);
                }
            }
            else if (strstr(line_buffer, "fonts.fon") != NULL)
            {
                if (settings[3][1] == "auto" || settings[3][1] == "nativedpi")
                {
                    fputs(line_buffer, fp_t);
                }
                else if (settings[3][1] == "tiny")
                {
                    fputs("fonts.fon=lrsys.fon\n", fp_t);
                }
                else if (settings[3][1] == "small")
                {
                    fputs("fonts.fon=vgasys.fon\n", fp_t);
                }
                else
                {
                    fputs("fonts.fon=8514sys.fon\n", fp_t);
                }
            }
            else
            {
                fputs(line_buffer, fp_t);
            }
        }
    }

    fclose(fp);
    fclose(fp_t);

    if (foundDriverLine == -1)
    {
        remove(systemINInew);
    }
    else
    {
        remove(systemINI);
        rename(systemINInew, systemINI);
        remove(systemINInew);
    }
}


TVbesvgaDlgClient::~TVbesvgaDlgClient()
{
    Destroy();

    // INSERT>> Your destructor code here.
}

HBRUSH TVbesvgaDlgClient::EvCtlColor(HDC dc, HWND hWndChild, uint ctlType)
{
    HBRUSH result;

    result = TDialog::EvCtlColor(dc, hWndChild, ctlType);

    // INSERT>> Your code here.

    return result;
}


void TVbesvgaDlgClient::BNClickedSmall()
{
    settings[3][1] = "small";
    CheckDlgButton(IDC_RADIOBUTTON1, 0);
    CheckDlgButton(IDC_RADIOBUTTON2, 0);
    CheckDlgButton(IDC_RADIOBUTTON3, 0);
    CheckDlgButton(IDC_RADIOBUTTON5, 0);
}


void TVbesvgaDlgClient::BNClickedLarge()
{
    settings[3][1] = "large";
    CheckDlgButton(IDC_RADIOBUTTON1, 0);
    CheckDlgButton(IDC_RADIOBUTTON2, 0);
    CheckDlgButton(IDC_RADIOBUTTON3, 0);
    CheckDlgButton(IDC_RADIOBUTTON4, 0);
}

bool TVbesvgaDlgClient::EvInitDialog(HWND hWndFocus)
{
    bool result;
    int setNumberOfModeEntries = 0;
    int listBoxIndex = 0;
    char resolutionText[14];
    int widthCheck = 0;
    int heightCheck = 0;
    result = TDialog::EvInitDialog(hWndFocus);

    // Initial dialog setup
    // Ensure gray color background and then set dialog boxes, radio butons and list boxes to the configured settings

    SetBkgndColor(TColor::LtGray);

    if (settings[3][1] == "auto")
    {
        CheckDlgButton(IDC_RADIOBUTTON1, 1);
    }
    else if (settings[3][1] == "nativedpi")
    {
        CheckDlgButton(IDC_RADIOBUTTON2, 1);
    }
    else if (settings[3][1] == "tiny")
    {
        CheckDlgButton(IDC_RADIOBUTTON3, 1);
    }
    else if (settings[3][1] == "small")
    {
        CheckDlgButton(IDC_RADIOBUTTON4, 1);
    }
    else
    {
        CheckDlgButton(IDC_RADIOBUTTON5, 1);
    }

    for (int i = 0; i < numberModeEntries; i++)
    {
        sprintf(resolutionText, "%d x %d", exportModes[i].width, exportModes[i].height);
        if (widthCheck != exportModes[i].width || (heightCheck != exportModes[i].height && widthCheck == exportModes[i].width))
        {
            SendDlgItemMsg(IDC_RESOLUTION, LB_ADDSTRING, 0, (long) resolutionText);
            if (widthCheck == atoi(settings[0][1].c_str()) && heightCheck == atoi(settings[1][1].c_str()))
            {
                SendDlgItemMsg(IDC_RESOLUTION, LB_SETCURSEL, setNumberOfModeEntries-1, 0);
            }

            setNumberOfModeEntries++;
            widthCheck = exportModes[i].width;
            heightCheck = exportModes[i].height;
        }
    }

    for (int i = 0; i < numberModeEntries; i++)
    {
        if (exportModes[i].width == atoi(settings[0][1].c_str()) && exportModes[i].height == atoi(settings[1][1].c_str()))
        {
            if (exportModes[i].depth == 8)
            {
                SendDlgItemMsg(IDC_DEPTH, LB_ADDSTRING, 0, (long) "256 (8-bit)");
                if (settings[2][1] == "8")
                {
                    SendDlgItemMsg(IDC_DEPTH, LB_SETCURSEL,listBoxIndex,0);
                }
                listBoxIndex++;
            }
            else if (exportModes[i].depth == 15)
            {
                SendDlgItemMsg(IDC_DEPTH, LB_ADDSTRING, 0, (long) "32K (15-bit)");
                if (settings[2][1] == "15")
                {
                    SendDlgItemMsg(IDC_DEPTH, LB_SETCURSEL,listBoxIndex,0);
                }
                listBoxIndex++;
            }
            else if (exportModes[i].depth == 16)
            {
                SendDlgItemMsg(IDC_DEPTH, LB_ADDSTRING, 0, (long) "64K (16-bit)");
                if (settings[2][1] == "16")
                {
                    SendDlgItemMsg(IDC_DEPTH, LB_SETCURSEL,listBoxIndex,0);
                }
                listBoxIndex++;
            }
            else if (exportModes[i].depth == 24 || exportModes[i].depth == 32)
            {
                SendDlgItemMsg(IDC_DEPTH, LB_ADDSTRING, 0, (long) "True Color (24-bit)");
                if (settings[2][1] == "24" || settings[2][1] == "32")
                {
                    SendDlgItemMsg(IDC_DEPTH, LB_SETCURSEL,listBoxIndex,0);
                }
                listBoxIndex++;
            }
        }
    }

    return result;
}


void TVbesvgaDlgClient::EvSetFont(HFONT hFont, bool redraw)
{
    LOGFONT lf = {0};
    lf.lfWeight = FW_THIN;
    hFont = CreateFontIndirect(&lf);
    TDialog::EvSetFont(hFont, redraw);
}


void TVbesvgaDlgClient::LBNSelchange()
{
    int listSel = 0;
    long check = SendDlgItemMsg(IDC_DEPTH, LB_GETCURSEL,0,0);
    char setDepth[3];

    for (int i = 0; i < numberModeEntries; i++)
    {
        if (exportModes[i].width == atoi(settings[0][1].c_str()) && exportModes[i].height == atoi(settings[1][1].c_str()))
        {
            if (listSel == check)
            {
                sprintf(setDepth, "%d", exportModes[i].depth);
                if (exportModes[i].depth > 24)
                {
                    sprintf(setDepth, "%d", 24);
                }
                settings[2][1] = setDepth;
            }
            listSel++;
        }
    }
}


void TVbesvgaDlgClient::BNOKClicked()
{
    int result = IDNO;
    SaveData();
    result = MessageBox("You will need to restart Windows before the new settings will take effect.\n\nRestart Windows now?",
                        "VBESVGA", MB_YESNO | MB_ICONQUESTION);

    switch (result)
    {
        case IDYES:
        {
            ExitWindows(EW_RESTARTWINDOWS, 0);
            break;
        }
        case IDNO:
        {
            exit(EXIT_SUCCESS);
            break;
        }
    }
}


void TVbesvgaDlgClient::LBNSetfocus()
{
  // INSERT>> Your code here.
}


void TVbesvgaDlgClient::CmHelpabout()
{
    MessageBox("VBESVGA: PluMGMK\nGUI: Stupendous Man (Stupend0usMan)\nWritten in Borland C++ 5.02\nPlease check github.com/PluMGMK/vbesvga.drv for any updates.",
    "About", MB_OK);
}


void TVbesvgaDlgClient::CmMoreoptionsitem()
{
    TVbesvgaDlgMoreOptions *moreOptions = new TVbesvgaDlgMoreOptions(this);
    moreOptions->SetBkgndColor(TColor::LtGray);
    moreOptions->Create();
}


void TVbesvgaDlgClient::CmHelpload()
{
    string intro = "Welcome to the VBESVGA Control Panel! This GUI will help provide more flexibility to the driver.";
    string mainMenuHelp = "The GUI runs VIDMODES to verify all supported video modes from your graphics card. "
    "The settings are then initialized to what was provided in your SYSTEM.INI file. "
    "Driver defaults are assumed if the settings were not provided.\n\n"
    "Set color depth on the upper left corner of the window. "
    "This list gets updated as the resolution bar is sliding left or right.\n\n"
    "Change resolution by sliding the bar all the way to the left or right.\n\n"
    "Adjust font size between 48, 96 and 120 dpi by deciding whether you want the driver to:\n"
    "\t - Automatically detect the DPI of the currently installed font (auto)\n"
    "\t - Calculate the physical dots per inch of your screen and pick the closest of the three modes (Native DPI)\n"
    "\t - Use tiny fonts (48 dpi)\n"
    "\t - Use small fonts (96 dpi)\n"
    "\t - Use large fonts (120 dpi)";
    string moreOptionsHelp = "DAC Depth: Significant bits to use per color in 256-color modes. "
    "Auto means 8 if the BIOS advertises that 8 is supported, 6 otherwise. "
    "If 8 is specified then the driver attempts to use 8 regardless of what the BIOS says!\n\n"
    "Swap Buffers Interval: Time in milliseconds between buffer swaps if double-buffering is enabled. "
    "Specifying a value of 0 disables double buffering.\n\n"
    "Prefer Banked Modes: If set to 1, then the driver searches for bank-switching modes before searching for linear modes. "
    "May be useful for debugging.";
    string moreOptionsHelpSecondPage =
    "Garish System Palette: This affects color rendering on the Windows GUI when the driver is in 8 bit mode. "
    "When set to 1, the dark colors are rendered significantly brighter than their internal representation, "
    "like they are in most Windows 3.1 drivers. "
    "When set to 0 (the default), the internal and external representations are the same, which is easier on the eye.\n\n"
    "Enable Special Case Linear Blits: If set to 1 (the default), then the driver completely bypasses bank-switching "
    "code paths to speed up certain common bit-blit operations when using a linear mode (this option is only for debugging)\n\n"
    "Allow 3 Byte Mode: Allow using modes with a total depth of 24 bits. "
    "Disable this to prefer 32-bit modes which give the same color depth but use more RAM.";
    string moreOptionsHelpThirdPage =
    "Bounce on modeset: This causes the Windows GUI to bounce to the background and immediately return to the foreground, "
    "when a windowed or background DOS box does a modeset (e.g. when starting up a windowed DOS box). Usually required to "
    "display corruption, but does cause an unpleasant flash. You can try disabling it to prevent the flash, but if it causes "
    "display corruption you will need to turn it back on! (It is safe to disable this under VirtualBox and DOSBox-X, but not "
    "under QEMU or Microsoft Virtual PC.)";
    string additionalSupport = "Check github.com/PluMGMK/vbesvga.drv for any updates. Please report any issues on the driver or this GUI "
    "to the issue tracker. Enjoy!";

    MessageBox(intro.c_str(), "Help", MB_OK);
    MessageBox(mainMenuHelp.c_str(), "Help", MB_OK);
    MessageBox(moreOptionsHelp.c_str(), "Help", MB_OK);
    MessageBox(moreOptionsHelpSecondPage.c_str(), "Help", MB_OK);
    MessageBox(moreOptionsHelpThirdPage.c_str(), "Help", MB_OK);
    MessageBox(additionalSupport.c_str(), "Help", MB_OK);
}

void TVbesvgaDlgClient::BNClickedTiny()
{
    settings[3][1] = "tiny";
    CheckDlgButton(IDC_RADIOBUTTON1, 0);
    CheckDlgButton(IDC_RADIOBUTTON2, 0);
    CheckDlgButton(IDC_RADIOBUTTON4, 0);
    CheckDlgButton(IDC_RADIOBUTTON5, 0);
}


void TVbesvgaDlgClient::BNClickedNativeDPI()
{
    settings[3][1] = "nativedpi";
    CheckDlgButton(IDC_RADIOBUTTON1, 0);
    CheckDlgButton(IDC_RADIOBUTTON3, 0);
    CheckDlgButton(IDC_RADIOBUTTON4, 0);
    CheckDlgButton(IDC_RADIOBUTTON5, 0);
}


void TVbesvgaDlgClient::BNClickedAuto()
{
    settings[3][1] = "auto";
    CheckDlgButton(IDC_RADIOBUTTON2, 0);
    CheckDlgButton(IDC_RADIOBUTTON3, 0);
    CheckDlgButton(IDC_RADIOBUTTON4, 0);
    CheckDlgButton(IDC_RADIOBUTTON5, 0);
}


void TVbesvgaDlgClient::LBNSelchangeResolution()
{
    char rtext[14];
    char setDepth[3];
    ResolutionList->GetSelString(rtext, 14);
    char *getWidth = strtok(rtext, " x ");
    char *getHeight = getWidth;
    int listBoxIndex = 0;
    getHeight = strtok(NULL, " x ");
    settings[0][1] = getWidth;
    settings[1][1] = getHeight;
    string getPreviousDepth = settings[2][1];

    SendDlgItemMsg(IDC_DEPTH, LB_RESETCONTENT, 0, 0);

    for (int i = 0; i < numberModeEntries; i++)
    {
        if (exportModes[i].width == atoi(settings[0][1].c_str()) && exportModes[i].height == atoi(settings[1][1].c_str()))
        {
            // Get support depths for newly selected resolution
            if (exportModes[i].depth == 8)
            {
                SendDlgItemMsg(IDC_DEPTH, LB_ADDSTRING, 0, (long) "256 (8-bit)");
            }
            else if (exportModes[i].depth == 15)
            {
                SendDlgItemMsg(IDC_DEPTH, LB_ADDSTRING, 0, (long) "32K (15-bit)");
            }
            else if (exportModes[i].depth == 16)
            {
                SendDlgItemMsg(IDC_DEPTH, LB_ADDSTRING, 0, (long) "64K (16-bit)");
            }
            else if (exportModes[i].depth == 24 || exportModes[i].depth == 32)
            {
                SendDlgItemMsg(IDC_DEPTH, LB_ADDSTRING, 0, (long) "True Color (24-bit)");
            }
            listBoxIndex++;

            // Keep new depth in line with previous resolution unless not supported
            // If not supported, use a lower depth
            if (exportModes[i].depth <= atoi(getPreviousDepth.c_str()) ||
                ((exportModes[i].depth == 24 || exportModes[i].depth == 32) &&
                (getPreviousDepth == "24" || getPreviousDepth == "32")))
            {
                SendDlgItemMsg(IDC_DEPTH, LB_SETCURSEL, listBoxIndex-1, 0);
                sprintf(setDepth, "%d", exportModes[i].depth);
                settings[2][1] = setDepth;
            }
            else if (listBoxIndex == 1 && (exportModes[i].depth > atoi(getPreviousDepth.c_str())))
            {
                // Some NVIDIA cards may have a 2048x1536x32 VESA mode. Need this just in case
                SendDlgItemMsg(IDC_DEPTH, LB_SETCURSEL, 0, 0);
                sprintf(setDepth, "%d", exportModes[i].depth);
                settings[2][1] = setDepth;
            }
        }
    }

    if (settings[2][1] == "32")
    {
        settings[2][1] = "24";
    }
}

