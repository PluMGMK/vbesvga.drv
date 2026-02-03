//----------------------------------------------------------------------------
//  Project Vbesvga
//  
//  Copyright 2026. All Rights Reserved.
//
//  SUBSYSTEM:    Vbesvga Application
//  FILE:         vbsvgapp.h
//  AUTHOR:       
//
//  OVERVIEW
//  ~~~~~~~~
//  Class definition for TVbesvgaApp (TApplication).
//
//----------------------------------------------------------------------------
#if !defined(vbsvgapp_h)              // Sentry, use file only if it's not already included.
#define vbsvgapp_h

#include <owl/controlb.h>
#include <owl/docking.h>
#include <owl/mailer.h>
#include <owl/opensave.h>


#include "vbsvgapp.rh"            // Definition of all resources.

struct Resolution {
  int width;
  int height;
  int depth;
};

extern string defaultSettings[11];
extern string settings[11][2];
extern Resolution *exportModes;
extern int numberModeEntries;



//
// FrameWindow must be derived to override Paint for Preview and Print.
//
//{{TDecoratedFrame = TSDIDecFrame}}
class TSDIDecFrame : public TDecoratedFrame {
  public:
    TSDIDecFrame(TWindow* parent, const char far* title, TWindow* clientWnd, bool trackMenuSelection = false, TModule* module = 0);
    ~TSDIDecFrame();

//{{TVbesvgaAppVIRTUAL_BEGIN}}
  public:
    virtual void SetupWindow();
//{{TVbesvgaAppVIRTUAL_END}}

//{{TSDIDecFrameRSP_TBL_BEGIN}}
  protected:
    void CmCursorcolor();
    void CmMoreoptionsitem3();
    void CmHelpload();
//{{TSDIDecFrameRSP_TBL_END}}
DECLARE_RESPONSE_TABLE(TSDIDecFrame);
};    //{{TSDIDecFrame}}


//{{TApplication = TVbesvgaApp}}
class TVbesvgaApp : public TApplication {
  private:

    void ProcessCmdLine(char * CmdLine);
    void RegisterInfo();
    void UnRegisterInfo();

  public:
    TVbesvgaApp();
    virtual ~TVbesvgaApp();

    THarbor*        ApxHarbor;

//{{TVbesvgaAppVIRTUAL_BEGIN}}
  public:
    virtual void InitMainWindow();
    virtual void InitInstance();
//{{TVbesvgaAppVIRTUAL_END}}

//{{TVbesvgaAppRSP_TBL_BEGIN}}
  protected:
    void CmHelpAbout();
    HBRUSH EvCtlColor(HDC hDC, THandle hWndChild, uint ctlType);
//{{TVbesvgaAppRSP_TBL_END}}
DECLARE_RESPONSE_TABLE(TVbesvgaApp);
};    //{{TVbesvgaApp}}


#endif  // vbsvgapp_h sentry.
