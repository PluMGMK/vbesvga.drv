//----------------------------------------------------------------------------
//  Project Vbesvga
//  
//  Copyright 2026. All Rights Reserved.
//
//  SUBSYSTEM:    Vbesvga Application
//  FILE:         vbsvgapp.cpp
//  AUTHOR:       
//
//  OVERVIEW
//  ~~~~~~~~
//  Source file for implementation of TVbesvgaApp (TApplication).
//
//----------------------------------------------------------------------------

#include <owl/pch.h>

#include <owl/buttonga.h>
#include <owl/statusba.h>
#include <classlib/cmdline.h>
#include <winsys/registry.h>
#include <stdio.h>
#include <vector>
#include <algorithm>
#include <numeric>

#include "vbsvgapp.h"
#include "vbsvgdlc.h"                        // Definition of client class.
//using namespace std;

string defaultSettings[11] = {"1024", "768", "24", "auto", "auto", "16",
                              "0", "0", "1", "1", "1"};

string settings[11][2] = {{"Width", "1024"},
                          {"Height", "768"},
                          {"Depth", "24"},
                          {"fontsize", "auto"},
                          {"dacdepth", "auto"},
                          {"SwapBuffersInterval", "16"},
                          {"PreferBankedModes", "0"},
                          {"GarishSystemPalette", "0"},
                          {"EnableSpecialCaseLinearBlits", "1"},
                          {"Allow3ByteMode", "1"},
                          {"BounceOnModeSet", "1"}};

int driverInstalled = 0;
int foundDriverLine = 0;

std::vector<string> vbeModes;



bool compareResolutions(const Resolution& a, const Resolution& b)
{
    if (a.width != b.width)
    {
        return a.width < b.width;
    }

    if (a.height != b.height)
    {
        return a.height < b.height;
    }

    return a.depth < b.depth;
}



std::vector<Resolution> vbeModesSorted;
Resolution *exportModes;
int numberModeEntries = 0;

//{{TVbesvgaApp Implementation}}


//
// Build a response table for all messages/commands handled
// by the application.
//
DEFINE_RESPONSE_TABLE1(TVbesvgaApp, TApplication)
//{{TVbesvgaAppRSP_TBL_BEGIN}}
  EV_COMMAND(CM_HELPABOUT, CmHelpAbout),
//{{TVbesvgaAppRSP_TBL_END}}
END_RESPONSE_TABLE;


//--------------------------------------------------------
// TVbesvgaApp
//
TVbesvgaApp::TVbesvgaApp() : TApplication("Display Properties")
{

  // INSERT>> Your constructor code here.
}


TVbesvgaApp::~TVbesvgaApp()
{
  // INSERT>> Your destructor code here.
}


//--------------------------------------------------------
// TVbesvgaApp
// ~~~~~
// Application intialization.
//
void TVbesvgaApp::InitMainWindow()
{
  if (nCmdShow != SW_HIDE)
    nCmdShow = (nCmdShow != SW_SHOWMINNOACTIVE) ? SW_SHOWNORMAL : nCmdShow;

  TSDIDecFrame* frame = new TSDIDecFrame(0, GetName(), 0, true);
  frame->SetFlag(wfShrinkToClient);

  frame->Attr.Style |= DS_ABSALIGN | WS_BORDER | WS_CAPTION | WS_CLIPCHILDREN | WS_MINIMIZEBOX | WS_SYSMENU | WS_VISIBLE;
  frame->Attr.Style &= ~(WS_THICKFRAME | WS_CHILD | WS_MAXIMIZEBOX);

  // Assign icons for this application.
  //
  frame->SetIcon(this, IDI_SDIAPPLICATION);
  frame->SetIconSm(this, IDI_SDIAPPLICATION);

  frame->Attr.AccelTable = IDM_SDI;

  SetMainWindow(frame);

  frame->SetMenuDescr(TMenuDescr(IDM_SDI));

}


//--------------------------------------------------------
// TVbesvgaApp
// ~~~~~
// Application instance initialization.
//
void TVbesvgaApp::InitInstance()
{
  TApplication::InitInstance();

  ProcessCmdLine(lpCmdLine);
}


//--------------------------------------------------------
// TVbesvgaApp
// ~~~~~
// Process command line parameters.
//
void TVbesvgaApp::ProcessCmdLine(char * CmdLine)
{
  TCmdLine cmd(CmdLine);

  while (cmd.Kind != TCmdLine::Done) {
    if (cmd.Kind == TCmdLine::Option) {
      if (strnicmp(cmd.Token, "unregister", cmd.TokenLen) == 0) {
        UnRegisterInfo();
        return;
      }
    }
    cmd.NextToken();
  }

  RegisterInfo();
}


//--------------------------------------------------------
// TVbesvgaApp
// ~~~~~
// Register application info.
//
void TVbesvgaApp::RegisterInfo()
{
  TAPointer<char> buffer = new char[_MAX_PATH];

  GetModuleFileName(buffer, _MAX_PATH);

  TRegKey(TRegKey::ClassesRoot, "Vbesvga.Application\\DefaultIcon").SetDefValue(0, REG_SZ, buffer, strlen(buffer));
  strcat(buffer, ",1");
}


//--------------------------------------------------------
// TVbesvgaApp
// ~~~~~
// Unregister application info.
//
void TVbesvgaApp::UnRegisterInfo()
{
  TAPointer<char> buffer = new char[_MAX_PATH];

  GetModuleFileName(buffer, _MAX_PATH);

  TRegKey(TRegKey::ClassesRoot, "Vbesvga.Application").DeleteKey("DefaultIcon");
  TRegKey(TRegKey::ClassesRoot, "Vbesvga.Document.1").DeleteKey("DefaultIcon");

  TRegKey::ClassesRoot.DeleteKey("Vbesvga.Application");
}



//
// Build a response table for all messages/commands handled by the application.
//
DEFINE_RESPONSE_TABLE1(TSDIDecFrame, TDecoratedFrame)
//{{TSDIDecFrameRSP_TBL_BEGIN}}
  EV_COMMAND(CM_MOREOPTIONSITEM, CmMoreoptionsitem3),
  EV_COMMAND(CM_HELPLOAD, CmHelpload),
//{{TSDIDecFrameRSP_TBL_END}}
END_RESPONSE_TABLE;


//{{TSDIDecFrame Implementation}}


TSDIDecFrame::TSDIDecFrame(TWindow* parent, const char far* title, TWindow* clientWnd, bool trackMenuSelection, TModule* module)
:
  TDecoratedFrame(parent, title, !clientWnd ? new TVbesvgaDlgClient(0) : clientWnd, trackMenuSelection, module)
{
  // INSERT>> Your constructor code here.

}


TSDIDecFrame::~TSDIDecFrame()
{
  // INSERT>> Your destructor code here.
}


void TSDIDecFrame::SetupWindow()
{
  TDecoratedFrame::SetupWindow();
  TRect  r;
  GetWindowRect(r);

  r.bottom += 30;
  SetWindowPos(0, r, SWP_NOZORDER | SWP_NOMOVE);

  // INSERT>> Your code here.                                  

}


//--------------------------------------------------------
// TVbesvgaApp
// ~~~~~~~~~~~
// Menu Help About Vbesvga command
//
void TVbesvgaApp::CmHelpAbout()
{
}



int OwlMain(int , char* [])
{
    char systemINI[255];
    char vidModes[255];
    char runVidmodesCommand[255];
    char line_buffer[255];
    int parseModes = 0;
    int runVidModes = 0;
    int result = 0;
    foundDriverLine = 0;

    GetWindowsDirectory(systemINI, 255);

    strcpy(vidModes, systemINI);
    strcpy(runVidmodesCommand, "command.com /C ");
    strcat(runVidmodesCommand, systemINI);
    strcat(runVidmodesCommand, "\\VIDMODES.COM > ");
    strcat(runVidmodesCommand, systemINI);
    strcat(runVidmodesCommand, "\\VIDMODES.CFG");
    //MessageBox(NULL, runVidmodesCommand, "test", MB_OK);
    strcat(vidModes, "\\VIDMODES.CFG");

    strcat(systemINI, "\\SYSTEM.INI");

    FILE *fp = fopen(systemINI, "r");

    while (fgets(line_buffer, sizeof(line_buffer), fp) != NULL)
    {
        if ((strstr(line_buffer, "[VBESVGA.DRV]") != NULL) ||
            (strstr(line_buffer, "[vbesvga.drv]") != NULL))
        {
            foundDriverLine = 1;
        }
        else if (foundDriverLine == 1)
        {
            for (int i = 0; i < 11; i++)
            {
                if(strstr(line_buffer, settings[i][0].c_str()) != NULL)
                {
                    line_buffer[strcspn(line_buffer, "\n")] = '\0';
                    string getValue = line_buffer;
                    int pos = getValue.find('=');
                    getValue = getValue.substr(0, pos);
                    for (int i = 0; i < 11; i++)
                    {
                        if(strstr(line_buffer, settings[i][0].c_str()) != NULL)
                        {
                            line_buffer[strcspn(line_buffer, "\n")] = '\0';
                            string getValue = line_buffer;
                            int pos = getValue.find('=');
                            getValue = getValue.substr(pos + 1, getValue.length());
                            settings[i][1] = getValue;
                        }
                    }
                }
            }
        }
    }

    fclose(fp);

    if (foundDriverLine == 0)
    {
        MessageBox(NULL, "Entry [VBESVGA.DRV] was not found in your SYSTEM.INI file. Please ensure VBESVGA was installed from SETUP and try again.", NULL, MB_OK);
        exit(EXIT_SUCCESS);
    }


    fp = fopen(vidModes, "r");
    while (fp == NULL)
    {
        WinExec(runVidmodesCommand, SW_SHOWMINNOACTIVE);
        result = MessageBox(NULL, "VIDMODES.CFG needs to be generated in your Windows folder. Ensure the MS-DOS prompt that ran has finished and press OK to attempt reading the file again or press CANCEL to exit.", NULL, MB_OKCANCEL);
        if (result == IDCANCEL)
        {
            exit(EXIT_SUCCESS);
        }
        fp = fopen(vidModes, "r");
    }

    while (fgets(line_buffer, sizeof(line_buffer), fp) != NULL)
    {
        if (strstr(line_buffer, "Available VBE video modes:") != NULL)
        {
            parseModes = 1;
        }
        else if (parseModes == 1 && line_buffer[0] != '\n')
        {
            if (strstr(line_buffer, "NG for VBESVGA.DRV") == NULL)
            {
                char buffer[255];
                char *buffer2;
                char *resWidth;
                char *resHeight;
                char *colorDepth;

                string getValue = line_buffer;
                strcpy(buffer, getValue.c_str());

                buffer2 = strtok(buffer, " ");
                buffer2 = strtok(NULL, " ");

                resWidth = strtok(buffer2, "*");
                resHeight = resWidth;
                resHeight = strtok(NULL, "*");
                colorDepth = resHeight;
                colorDepth = strtok(NULL, "*");

                int resWidthNum = atoi(resWidth);
                int resHeightNum = atoi(resHeight);
                int colorDepthNum = atoi(colorDepth);

                string vbeCombined = resWidth;
                string vbeSpace = " ";
                vbeCombined.append(vbeSpace);
                vbeCombined.append(resHeight);
                vbeCombined.append(vbeSpace);
                vbeCombined.append(colorDepth);

                std::vector<string>::iterator checkString = std::find(vbeModes.begin(), vbeModes.end(), vbeCombined);

                if(checkString == vbeModes.end())
                {
                    vbeModes.push_back(vbeCombined);
                    Resolution t = {resWidthNum, resHeightNum, colorDepthNum};
                    vbeModesSorted.push_back(t);
                }
            }
        }
        else
        {
            parseModes = 0;
        }
    }

    fclose(fp);

    std::sort(vbeModesSorted.begin(), vbeModesSorted.end(), compareResolutions);

    char tt[55];
    for (int i = 0; i < vbeModesSorted.size(); i++)
    {
        sprintf(tt, "%d %d %d", vbeModesSorted[i].width, vbeModesSorted[i].height, vbeModesSorted[i].depth);
    }

    exportModes = new Resolution[vbeModesSorted.size()];
    for (int i = 0; i < vbeModesSorted.size(); i++)
    {
        exportModes[i] = vbeModesSorted[i];
        numberModeEntries++;
    }

    TVbesvgaApp   app;
    return app.Run();
}

void TSDIDecFrame::CmCursorcolor()
{
  // INSERT>> Your code here.

}


void TSDIDecFrame::CmMoreoptionsitem3()
{
  // INSERT>> Your code here.

}


void TSDIDecFrame::CmHelpload()
{
  // INSERT>> Your code here.

}

