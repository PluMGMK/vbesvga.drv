//----------------------------------------------------------------------------
//  Project vbesvga
//  
//  Copyright 2026. All Rights Reserved.
//
//  SUBSYSTEM:    vbesvga.apx Application
//  FILE:         vbsvgdmo.cpp
//  AUTHOR:       
//
//  OVERVIEW
//  ~~~~~~~~
//  Source file for implementation of TVbesvgaDlgMoreOptions (TDialog).
//
//----------------------------------------------------------------------------
#include <owl/pch.h>

#include "vbsvgdmo.h"
#include <stdio.h>

static char storeCheckBoxResult[2];
static TVbesvgaDlgMoreOptionsXfer TVbesvgaDlgMoreOptionsData;


//
// Build a response table for all messages/commands handled by the application.
//
DEFINE_RESPONSE_TABLE1(TVbesvgaDlgMoreOptions, TDialog)
//{{TVbesvgaDlgMoreOptionsRSP_TBL_BEGIN}}
  EV_BN_CLICKED(IDC_BANKEDMODES, PBM_BNClicked),
  EV_BN_CLICKED(IDC_GARISH, GSP_BNClicked),
  EV_BN_CLICKED(IDC_LINEARBLITS, SCLB_BNClicked),
  EV_BN_CLICKED(IDC_THREEBYTE, TBM_BNClicked),
  EV_BN_CLICKED(IDC_BOUNCE, BOM_BNClicked),
  EV_CBN_SELCHANGE(IDC_DACDEPTHOPT, CBNSelchange),
  EV_EN_UPDATE(IDC_SBIEDIT, ENUpdate),
  EV_BN_CLICKED(IDOK, OK_BNClicked),
//{{TVbesvgaDlgMoreOptionsRSP_TBL_END}}
END_RESPONSE_TABLE;


//{{TVbesvgaDlgMoreOptions Implementation}}

TVbesvgaDlgMoreOptions::TVbesvgaDlgMoreOptions(TWindow* parent, TResId resId, TModule* module)
:
    TDialog(parent, resId, module)
{
    //{{TVbesvgaDlgMoreOptionsXFER_USE}}
    BankedModesCheckBox = new TCheckBox(this, IDC_BANKEDMODES, 0);
    GarishCheckBox = new TCheckBox(this, IDC_GARISH, 0);
    SpecialCaseLinearBlitsCheckBox = new TCheckBox(this, IDC_LINEARBLITS, 0);
    ThreeByteModeCheckBox = new TCheckBox(this, IDC_THREEBYTE, 0);
    BounceOnModesetCheckBox = new TCheckBox(this, IDC_BOUNCE, 0);
    DACDepthComboBox = new TComboBox(this, IDC_DACDEPTHOPT, 1);
    SBIText = new TEdit(this, IDC_SBIEDIT, 3);

    SetTransferBuffer(&TVbesvgaDlgMoreOptionsData);
    //{{TVbesvgaDlgMoreOptionsXFER_USE_END}}

    // INSERT>> Your constructor code here.

}


TVbesvgaDlgMoreOptions::~TVbesvgaDlgMoreOptions()
{
    Destroy(IDCANCEL);

    // INSERT>> Your destructor code here.
}


bool TVbesvgaDlgMoreOptions::EvInitDialog(HWND hWndFocus)
{
    bool result;
    result = TDialog::EvInitDialog(hWndFocus);
    DACDepthComboBox->InsertString("6", 0);
    DACDepthComboBox->InsertString("8", 1);
    DACDepthComboBox->InsertString("auto", 2);
    if (settings[4][1] == "6")
    {
        DACDepthComboBox->SetSelIndex(0);
    }
    else if (settings[4][1] == "8")
    {
        DACDepthComboBox->SetSelIndex(1);
    }
    else
    {
        DACDepthComboBox->SetSelIndex(2);
    }

    SBIText->Clear();
    SBIText->Insert(settings[5][1].c_str());
    BankedModesCheckBox->SetCheck(atoi(settings[6][1].c_str()));
    GarishCheckBox->SetCheck(atoi(settings[7][1].c_str()));
    SpecialCaseLinearBlitsCheckBox->SetCheck(atoi(settings[8][1].c_str()));
    ThreeByteModeCheckBox->SetCheck(atoi(settings[9][1].c_str()));
    BounceOnModesetCheckBox->SetCheck(atoi(settings[10][1].c_str()));

    return result;
}


void TVbesvgaDlgMoreOptions::BNClicked()
{
  // INSERT>> Your code here.
}


void TVbesvgaDlgMoreOptions::PBM_BNClicked()
{

}


void TVbesvgaDlgMoreOptions::GSP_BNClicked()
{

}


void TVbesvgaDlgMoreOptions::SCLB_BNClicked()
{

}


void TVbesvgaDlgMoreOptions::TBM_BNClicked()
{

}


void TVbesvgaDlgMoreOptions::BOM_BNClicked()
{

}


void TVbesvgaDlgMoreOptions::CBNSelchange()
{
  // INSERT>> Your code here.

}


void TVbesvgaDlgMoreOptions::ENUpdate()
{
  // INSERT>> Your code here.

}

void TVbesvgaDlgMoreOptions::EvClose()
{
    TDialog::EvClose();
}


void TVbesvgaDlgMoreOptions::OK_BNClicked()
{
    SBIText->GetLine(TVbesvgaDlgMoreOptionsData.SBIText, 3, -1);

    if (atoi(TVbesvgaDlgMoreOptionsData.SBIText) < 0 || atoi(TVbesvgaDlgMoreOptionsData.SBIText) > 55 ||
        !isdigit(TVbesvgaDlgMoreOptionsData.SBIText[0]) || (!isdigit(TVbesvgaDlgMoreOptionsData.SBIText[1]) &&
        TVbesvgaDlgMoreOptionsData.SBIText[1] != ' ' && TVbesvgaDlgMoreOptionsData.SBIText[1] != '\0'))
    {
        MessageBox("Invalid input entered in Swap Buffers Interval box. Please enter a valid number from 0 to 55.");
        return;
    }

    settings[5][1] = TVbesvgaDlgMoreOptionsData.SBIText;

    switch (DACDepthComboBox->GetSelIndex())
    {
        case 0:
        {
            settings[4][1] = "6";
            break;
        }
        case 1:
        {
            settings[4][1] = "8";
            break;
        }
        default:
        {
            settings[4][1] = "auto";
            break;
        }
    }

    sprintf(storeCheckBoxResult, "%u", BankedModesCheckBox->GetCheck());
    settings[6][1] = storeCheckBoxResult;
    sprintf(storeCheckBoxResult, "%u", GarishCheckBox->GetCheck());
    settings[7][1] = storeCheckBoxResult;
    sprintf(storeCheckBoxResult, "%u", SpecialCaseLinearBlitsCheckBox->GetCheck());
    settings[8][1] = storeCheckBoxResult;
    sprintf(storeCheckBoxResult, "%u", ThreeByteModeCheckBox->GetCheck());
    settings[9][1] = storeCheckBoxResult;
    sprintf(storeCheckBoxResult, "%u", BounceOnModesetCheckBox->GetCheck());
    settings[10][1] = storeCheckBoxResult;

    TDialog::EvClose();
}

