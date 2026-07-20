//----------------------------------------------------------------------------
//  Project vbesvga
//  
//  Copyright 2026. All Rights Reserved.
//
//  SUBSYSTEM:    vbesvga.apx Application
//  FILE:         vbsvgdmo.h
//  AUTHOR:       
//
//  OVERVIEW
//  ~~~~~~~~
//  Class definition for TVbesvgaDlgMoreOptions (TDialog).
//
//----------------------------------------------------------------------------
#if !defined(vbsvgdmo_h)              // Sentry, use file only if it's not already included.
#define vbsvgdmo_h

#include <owl/dialog.h>


#include <owl/edit.h>
#include <owl/combobox.h>
#include <owl/checkbox.h>
#include <owl/commctrl.h>
#include "vbsvgdlc.h"
#include "vbsvgapp.h"
#include "vbsvgapp.rh"            // Definition of all resources.


//{{TDialog = TVbesvgaDlgMoreOptions}}
struct TVbesvgaDlgMoreOptionsXfer {
//{{TVbesvgaDlgMoreOptionsXFER_DATA}}
    uint    BankedModesCheckBox;
    uint    GarishCheckBox;
    uint    SpecialCaseLinearBlitsCheckBox;
    uint    ThreeByteModeCheckBox;
    uint    BounceOnModesetCheckBox;
    TComboBoxData  DACDepthComboBox;
    char    SBIText[ 3 ];
//{{TVbesvgaDlgMoreOptionsXFER_DATA_END}}
};

class TVbesvgaDlgMoreOptions : public TDialog {
  public:
    TVbesvgaDlgMoreOptions(TWindow* parent, TResId resId = IDD_EXTRAOPT, TModule* module = 0);
    virtual ~TVbesvgaDlgMoreOptions();

//{{TVbesvgaDlgMoreOptionsVIRTUAL_BEGIN}}
  public:
    virtual bool EvInitDialog(HWND hWndFocus);
//{{TVbesvgaDlgMoreOptionsVIRTUAL_END}}

//{{TVbesvgaDlgMoreOptionsRSP_TBL_BEGIN}}
  protected:
    void BNClicked();
    void PBM_BNClicked();
    void GSP_BNClicked();
    void SCLB_BNClicked();
    void TBM_BNClicked();
    void BOM_BNClicked();
    void CBNSelchange();
    void EvSetFocus(THandle hWndLostFocus );
    void EvChar(uint key, uint repeatCount, uint flags);
    void SBIENUpdate();
    void ENUpdate();
    void EvDestroy();
    void EvClose();
    void OK_BNClicked();
//{{TVbesvgaDlgMoreOptionsRSP_TBL_END}}
DECLARE_RESPONSE_TABLE(TVbesvgaDlgMoreOptions);

//{{TVbesvgaDlgMoreOptionsXFER_DEF}}
  protected:
    TCheckBox* BankedModesCheckBox;
    TCheckBox* GarishCheckBox;
    TCheckBox* SpecialCaseLinearBlitsCheckBox;
    TCheckBox* ThreeByteModeCheckBox;
    TCheckBox* BounceOnModesetCheckBox;
    TComboBox* DACDepthComboBox;
    TEdit* SBIText;

//{{TVbesvgaDlgMoreOptionsXFER_DEF_END}}
};    //{{TVbesvgaDlgMoreOptions}}


#endif  // vbsvgdmo_h sentry.

