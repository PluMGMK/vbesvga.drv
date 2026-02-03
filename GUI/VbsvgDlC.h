//----------------------------------------------------------------------------
//  Project Vbesvga
//  
//  Copyright 2026. All Rights Reserved.
//
//  SUBSYSTEM:    Vbesvga Application
//  FILE:         vbsvgdlc.h
//  AUTHOR:       
//
//  OVERVIEW
//  ~~~~~~~~
//  Class definition for TVbesvgaDlgClient (TDialog).
//
//----------------------------------------------------------------------------
#if !defined(vbsvgdlc_h)              // Sentry, use file only if it's not already included.
#define vbsvgdlc_h

#include "vbsvgapp.rh"                  // Definition of all resources.


#include <owl/listbox.h>
#include <owl/static.h>
#include <owl/groupbox.h>
#include <owl/scrollba.h>
#include <owl/commctrl.h>

#include <owl/button.h>
//{{TDialog = TVbesvgaDlgClient}}
struct TVbesvgaDlgClientXfer {
//{{TVbesvgaDlgClientXFER_DATA}}
    TListBoxData  ResolutionList;
//{{TVbesvgaDlgClientXFER_DATA_END}}
};

extern HWND dialogHWND;

class TVbesvgaDlgClient : public TDialog {
  public:
    TVbesvgaDlgClient(TWindow* parent, TResId resId = IDD_CLIENT, TModule* module = 0);
    virtual ~TVbesvgaDlgClient();


//{{TVbesvgaDlgClientXFER_DEF}}
  protected:
    TListBox* ResolutionList;

//{{TVbesvgaDlgClientXFER_DEF_END}}

//{{TVbesvgaDlgClientVIRTUAL_BEGIN}}
  public:
    virtual bool EvInitDialog(HWND hWndFocus);
//{{TVbesvgaDlgClientVIRTUAL_END}}

//{{TVbesvgaDlgClientRSP_TBL_BEGIN}}
  protected:
    HBRUSH EvCtlColor(HDC dc, HWND hWndChild, uint ctlType);
    void BNClickedSmall();
    void BNUnhiliteLarge();
    void BNClickedLarge();
    void EvSetFont(HFONT hFont, bool redraw);
    void LBNSelchange();
    void BNOKClicked();
    void LBNSetfocus();
    void CmHelpabout();
    void CmMoreoptionsitem();
    void CmHelpload();
    void EvSetFocus(THandle hWndLostFocus );
    void EvDestroy();
    void BNClickedTiny();
    void BNClickedNativeDPI();
    void BNClickedAuto();
    void LBNSelchangeResolution();
//{{TVbesvgaDlgClientRSP_TBL_END}}
DECLARE_RESPONSE_TABLE(TVbesvgaDlgClient);
};    //{{TVbesvgaDlgClient}}


#endif  // vbsvgdlc_h sentry.
