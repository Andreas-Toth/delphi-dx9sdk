(*----------------------------------------------------------------------------*
 *  Direct3D sample from DirectX 9.0 SDK December 2006                        *
 *  Delphi adaptation by Alexey Barkovoy (e-mail: directx@clootie.ru)         *
 *                                                                            *
 *  Supported compilers: Delphi 5,6,7,9; FreePascal 2.0                       *
 *                                                                            *
 *  Latest version can be downloaded from:                                    *
 *     http://www.clootie.ru                                                  *
 *     http://sourceforge.net/projects/delphi-dx9sdk                          *
 *----------------------------------------------------------------------------*
 *  $Id: Text3Dunit.pas,v 1.14 2007/02/05 22:21:13 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: Text3D.cpp
//
// Desc: Example code showing how to do text in a Direct3D scene.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit Text3Dunit;

interface

uses
  Windows, Messages, SysUtils, StrSafe,{$IFNDEF FPC} CommDlg,{$ENDIF}
  DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pTextSprite: ID3DXSprite = nil;    // Sprite for batching draw text calls
  g_Camera: CFirstPersonCamera;        // A model viewing camera
  g_bShowHelp: Boolean = True;         // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg;      // Device settings dialog
  g_HUD: CDXUTDialog;                  // dialog for standard controls
  g_SampleUI: CDXUTDialog;             // dialog for sample specific controls

  g_pFont: ID3DXFont = nil;
  g_pFont2: ID3DXFont = nil;
  g_pStatsFont: ID3DXFont = nil;
  g_pMesh3DText: ID3DXMesh = nil;
  g_strTextBuffer: PWideChar = nil;

  g_strFont: array[0..LF_FACESIZE-1] of WideChar;
  g_nFontSize: Integer;
  g_matObj1: TD3DXMatrixA16;
  g_matObj2: TD3DXMatrixA16;


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_CHANGEFONT          = 5;



//--------------------------------------------------------------------------------------
// Forward declarations
//--------------------------------------------------------------------------------------
function IsDeviceAcceptable(const pCaps: TD3DCaps9; AdapterFormat, BackBufferFormat: TD3DFormat; bWindowed: Boolean; pUserContext: Pointer): Boolean; stdcall;
function ModifyDeviceSettings(var pDeviceSettings: TDXUTDeviceSettings; const pCaps: TD3DCaps9; pUserContext: Pointer): Boolean; stdcall;
function OnCreateDevice(const pd3dDevice: IDirect3DDevice9; const pBackBufferSurfaceDesc: TD3DSurfaceDesc; pUserContext: Pointer): HRESULT; stdcall;
function OnResetDevice(const pd3dDevice: IDirect3DDevice9; const pBackBufferSurfaceDesc: TD3DSurfaceDesc; pUserContext: Pointer): HRESULT; stdcall;
procedure OnFrameMove(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
function MsgProc(hWnd: HWND; uMsg: LongWord; wParam: WPARAM; lParam: LPARAM; out pbNoFurtherProcessing: Boolean; pUserContext: Pointer): LRESULT; stdcall;
procedure KeyboardProc(nChar: LongWord; bKeyDown, bAltDown: Boolean; pUserContext: Pointer); stdcall;
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
procedure OnLostDevice(pUserContext: Pointer); stdcall;
procedure OnDestroyDevice(pUserContext: Pointer); stdcall;

procedure InitApp;
function CreateD3DXTextMesh(const pd3dDevice: IDirect3DDevice9; out ppMesh: ID3DXMesh; pstrFont: PWideChar; dwSize: DWORD; bBold, bItalic: Boolean): HRESULT;
//function CreateD3DXFont(out ppd3dxFont: ID3DXFont; pstrFont: PWideChar; dwSize: DWORD): HRESULT;

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;

implementation


const
  IDR_TXT                         = 102;

//--------------------------------------------------------------------------------------
// Initialize the app
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  rsrc: HRSRC;
  hgData: HGLOBAL;
  pvData: Pointer;
  cbData: DWORD;
  nSize: Integer;
  iY: Integer;
begin
  StringCchCopy(g_strFont, 32, 'Arial');

  rsrc := FindResource(0, MAKEINTRESOURCE(IDR_TXT), 'TEXT');
  if (rsrc <> 0) then
  begin
    cbData := SizeofResource(0, rsrc);
    if (cbData > 0) then
    begin
      hgData := LoadResource(0, rsrc);
      if (hgData <> 0) then
      begin
        pvData := LockResource(hgData);
        if (pvData <> nil) then
        begin
          nSize := cbData div SizeOf(WideChar) + 1;
          GetMem(g_strTextBuffer, SizeOf(WideChar)*nSize);
          CopyMemory(g_strTextBuffer, pvData, cbData);
          g_strTextBuffer[nSize-1] := #0;
        end;
      end;
    end;
  end;

  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_SampleUI.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent);
  iY := 10;    g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 35, iY, 125, 22, VK_F2);

  g_SampleUI.SetCallback(OnGUIEvent);
  iY := 10; g_SampleUI.AddButton(IDC_CHANGEFONT, 'Change Font', 35, iY, 125, 22);
end;


//--------------------------------------------------------------------------------------
// Called during device initialization, this code checks the device for some
// minimum set of capabilities, and rejects those that don't pass by returning false.
//--------------------------------------------------------------------------------------
function IsDeviceAcceptable(const pCaps: TD3DCaps9; AdapterFormat, BackBufferFormat: TD3DFormat; bWindowed: Boolean; pUserContext: Pointer): Boolean; stdcall;
var
  pD3D: IDirect3D9;
begin
  Result := False;

  // Skip backbuffer formats that don't support alpha blending
  pD3D := DXUTGetD3DObject;
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                   AdapterFormat, D3DUSAGE_QUERY_POSTPIXELSHADER_BLENDING,
                   D3DRTYPE_TEXTURE, BackBufferFormat))
  then Exit;

  Result := True;
end;


//--------------------------------------------------------------------------------------
// This callback function is called immediately before a device is created to allow the
// application to modify the device settings. The supplied pDeviceSettings parameter
// contains the settings that the framework has selected for the new device, and the
// application can make any desired changes directly to this structure.  Note however that
// DXUT will not correct invalid device settings so care must be taken 
// to return valid device settings, otherwise IDirect3D9::CreateDevice() will fail.
//--------------------------------------------------------------------------------------

{static} var s_bFirstTime: Boolean = True;

function ModifyDeviceSettings(var pDeviceSettings: TDXUTDeviceSettings; const pCaps: TD3DCaps9; pUserContext: Pointer): Boolean; stdcall;
begin
  // If device doesn't support HW T&L or doesn't support 1.1 vertex shaders in HW
  // then switch to SWVP.
  if (pCaps.DevCaps and D3DDEVCAPS_HWTRANSFORMANDLIGHT = 0) or
     (pCaps.VertexShaderVersion < D3DVS_VERSION(1,1))
  then pDeviceSettings.BehaviorFlags := D3DCREATE_SOFTWARE_VERTEXPROCESSING;

  // Debugging vertex shaders requires either REF or software vertex processing
  // and debugging pixel shaders requires REF.
{$IFDEF DEBUG_VS}
  if (pDeviceSettings.DeviceType <> D3DDEVTYPE_REF) then
  with pDeviceSettings do
  begin
    BehaviorFlags := BehaviorFlags and not D3DCREATE_HARDWARE_VERTEXPROCESSING;
    BehaviorFlags := BehaviorFlags and not D3DCREATE_PUREDEVICE;
    BehaviorFlags := BehaviorFlags or D3DCREATE_SOFTWARE_VERTEXPROCESSING;
  end;
{$ENDIF}
{$IFDEF DEBUG_PS}
  pDeviceSettings.DeviceType := D3DDEVTYPE_REF;
{$ENDIF}

  // For the first device created if its a REF device, optionally display a warning dialog box
  if s_bFirstTime then
  begin
    s_bFirstTime := False;
    if (pDeviceSettings.DeviceType = D3DDEVTYPE_REF) then DXUTDisplaySwitchingToREFWarning;
  end;

  Result:= True;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has been 
// created, which will happen during application initialization and windowed/full screen 
// toggles. This is the best location to create D3DPOOL_MANAGED resources since these 
// resources need to be reloaded whenever the device is destroyed. Resources created  
// here should be released in the OnDestroyDevice callback. 
//--------------------------------------------------------------------------------------
function OnCreateDevice(const pd3dDevice: IDirect3DDevice9; const pBackBufferSurfaceDesc: TD3DSurfaceDesc; pUserContext: Pointer): HRESULT; stdcall;
var
  hDC: Windows.HDC;
  nLogPixelsY: Integer;
  nHeight: Integer;
begin
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  hDC := GetDC(0);
  nLogPixelsY := GetDeviceCaps(hDC, LOGPIXELSY);
  ReleaseDC(0, hDC);

  nHeight := -g_nFontSize * nLogPixelsY div 72;
  Result := D3DXCreateFontW(pd3dDevice,            // D3D device
                            nHeight,               // Height
                            0,                     // Width
                            FW_BOLD,               // Weight
                            1,                     // MipLevels, 0 = autogen mipmaps
                            FALSE,                 // Italic
                            DEFAULT_CHARSET,       // CharSet
                            OUT_DEFAULT_PRECIS,    // OutputPrecision
                            DEFAULT_QUALITY,       // Quality
                            DEFAULT_PITCH or FF_DONTCARE, // PitchAndFamily
                            g_strFont,             // pFaceName
                            g_pFont);              // ppFont
  if Failed(Result) then Exit;

  Result := D3DXCreateFontW(pd3dDevice, -12, 0, FW_BOLD, 1, FALSE, DEFAULT_CHARSET,
                            OUT_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE,
                            'System', g_pFont2);
  if Failed(Result) then Exit;

  Result := D3DXCreateFontW(pd3dDevice, 15, 0, FW_BOLD, 1, FALSE, DEFAULT_CHARSET,
                            OUT_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE,
                            'Arial', g_pStatsFont);
  if Failed(Result) then Exit;

  Result := D3DXCreateSprite(pd3dDevice, g_pTextSprite);
  if Failed(Result) then Exit;

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has been
// reset, which will happen after a lost device scenario. This is the best location to
// create D3DPOOL_DEFAULT resources since these resources need to be reloaded whenever
// the device is lost. Resources created here should be released in the OnLostDevice
// callback.
//--------------------------------------------------------------------------------------
function OnResetDevice(const pd3dDevice: IDirect3DDevice9; const pBackBufferSurfaceDesc: TD3DSurfaceDesc; pUserContext: Pointer): HRESULT; stdcall;
var
  light: TD3DLight9;
  vecLightDirUnnormalized: TD3DXVector3;
  matWorld: TD3DXMatrixA16;
  vecEye: TD3DXVector3;
  vecAt: TD3DXVector3;
  fAspectRatio: Single;
begin
  Result:= g_DialogResourceManager.OnResetDevice;
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnResetDevice;
  if V_Failed(Result) then Exit;

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation( pBackBufferSurfaceDesc.Width-170, pBackBufferSurfaceDesc.Height-350);
  g_SampleUI.SetSize(170, 300);

  // Restore the fonts
  g_pStatsFont.OnResetDevice;
  g_pFont.OnResetDevice;
  g_pFont2.OnResetDevice;
  g_pTextSprite.OnResetDevice;

  // Restore the textures
  pd3dDevice.SetTextureStageState(0, D3DTSS_COLORARG1, D3DTA_TEXTURE);
  pd3dDevice.SetTextureStageState(0, D3DTSS_COLORARG2, D3DTA_DIFFUSE);
  pd3dDevice.SetTextureStageState(0, D3DTSS_COLOROP, D3DTOP_MODULATE);
  pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);
  pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);

  pd3dDevice.SetRenderState(D3DRS_ZENABLE, iTrue);
  pd3dDevice.SetRenderState(D3DRS_DITHERENABLE, iTrue);
  pd3dDevice.SetRenderState(D3DRS_SPECULARENABLE, iTrue);
  pd3dDevice.SetRenderState(D3DRS_LIGHTING, iTrue);
  pd3dDevice.SetRenderState(D3DRS_AMBIENT, $80808080);
  vecLightDirUnnormalized := D3DXVector3(10.0, -10.0, 10.0);
  FillChar(light, SizeOf(TD3DLight9), #0);
  light._Type       := D3DLIGHT_DIRECTIONAL;
  light.Diffuse.r   := 1.0;
  light.Diffuse.g   := 1.0;
  light.Diffuse.b   := 1.0;
  D3DXVec3Normalize(light.Direction, vecLightDirUnnormalized);
  light.Position.x  := 10.0;
  light.Position.y  := -10.0;
  light.Position.z  := 10.0;
  light.Range       := 1000.0;
  pd3dDevice.SetLight(0, light);
  pd3dDevice.LightEnable(0, True);

  // Set the transform matrices
  D3DXMatrixIdentity(matWorld);
  pd3dDevice.SetTransform(D3DTS_WORLD, matWorld);

  // Setup the camera with view & projection matrix
  vecEye := D3DXVector3(0.0,-5.0, -10.0);
  vecAt := D3DXVector3(0.2, 0.0, 0.0);
  g_Camera.SetViewParams(vecEye, vecAt);
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI/4, fAspectRatio, 1.0, 1000.0);

  SAFE_RELEASE(g_pMesh3DText);
  Result:= CreateD3DXTextMesh(pd3dDevice, g_pMesh3DText, g_strFont, g_nFontSize, False, False);
  if FAILED(Result) then
  begin
    Result:= E_FAIL;
    Exit;
  end;

  Result:= S_OK;
end;

const
  IsBold: array[False..True] of Integer = (FW_NORMAL, FW_BOLD);

//-----------------------------------------------------------------------------
// Name: CreateD3DXTextMesh()
// Desc:
//-----------------------------------------------------------------------------
function CreateD3DXTextMesh(const pd3dDevice: IDirect3DDevice9; out ppMesh: ID3DXMesh; pstrFont: PWideChar; dwSize: DWORD; bBold, bItalic: Boolean): HRESULT;
var
  pMeshNew: ID3DXMesh;
  hdc: Windows.HDC;
  nHeight: Integer;
  hFont: Windows.HFONT;
  hFontOld: Windows.HFONT;
begin
  hdc := CreateCompatibleDC(0);
  if (hdc = 0) then
  begin
    Result:= E_OUTOFMEMORY;
    Exit;
  end;
  nHeight := -MulDiv(dwSize, GetDeviceCaps(hdc, LOGPIXELSY), 72);

  hFont := CreateFontW(nHeight, 0, 0, 0, IsBold[bBold], Cardinal(bItalic), iFalse, iFalse, DEFAULT_CHARSET,
             OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE, pstrFont);

  hFontOld := SelectObject(hdc, hFont);

  Result := D3DXCreateText(pd3dDevice, hdc, 'This is calling D3DXCreateText',
                           0.001, 0.4, pMeshNew, nil, nil);

  SelectObject(hdc, hFontOld);
  DeleteObject(hFont);
  DeleteDC(hdc);

  if SUCCEEDED(Result) then ppMesh := pMeshNew;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called once at the beginning of every frame. This is the
// best location for your application to handle updates to the scene, but is not
// intended to contain actual rendering calls, which should instead be placed in the
// OnFrameRender callback.
//--------------------------------------------------------------------------------------
procedure OnFrameMove(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  vAxis1: TD3DXVector3;
  vAxis2: TD3DXVector3;
  mScale: TD3DXMatrix;
begin
  // Setup five rotation matrices (for rotating text strings)
  vAxis1 := D3DXVector3(1.0, 2.0, 0.0);
  vAxis2 := D3DXVector3(1.0, 0.0, 0.0);
  D3DXMatrixRotationAxis(g_matObj1, vAxis1, fTime / 2.0);
  D3DXMatrixRotationAxis(g_matObj2, vAxis2, fTime);

  D3DXMatrixScaling(mScale, 0.5, 0.5, 0.5);
  // g_matObj2 := g_matObj2 * mScale;
  D3DXMatrixMultiply(g_matObj2, g_matObj2, mScale);

  // Add some translational values to the matrices
  g_matObj1._41 := 1.0;   g_matObj1._42 := 6.0;   g_matObj1._43 := 20.0;
  g_matObj2._41 := -4.0;  g_matObj2._42 := -1.0;  g_matObj2._43 := 0.0;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called at the end of every frame to perform all the 
// rendering calls for the scene, and it will also be called if the window needs to be 
// repainted. After this function has returned, DXUT will call 
// IDirect3DDevice9::Present to display the contents of the next buffer in the swap chain
//--------------------------------------------------------------------------------------
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  rc: TRect;
  mtrl: TD3DMaterial9;
  matView: TD3DXMatrixA16;
  matProj: TD3DXMatrixA16;
  matViewProj: TD3DXMatrixA16;
  nHeight: LongWord;
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  // Get the view & projection matrix from camera.
  // User can't control camera for this simple sample
  matView := g_Camera.GetViewMatrix^;
  matProj := g_Camera.GetProjMatrix^;
  // matViewProj := matView * matProj;
  D3DXMatrixMultiply(matViewProj, matView, matProj);

  pd3dDevice.SetTransform(D3DTS_VIEW,       matView);
  pd3dDevice.SetTransform(D3DTS_PROJECTION, matProj);

  // Clear the viewport
  pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, $00000000, 1.0, 0);

  // Begin the scene 
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    nHeight := DXUTGetPresentParameters.BackBufferHeight;

    DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'Demonstration Code');

    // Demonstration 1:
    // Draw a simple line using ID3DXFont::DrawText
    begin
      // CDXUTPerfEventGenerator g( DXUT_PERFEVENTCOLOR, L"Demonstration Part 1");
      DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'Demonstration Part 1');
{$ifNdef 1}
      // Pass in DT_NOCLIP so we don't have to calc the bottom/right of the rect
      SetRect(rc, 150, 200, 0, 0);
      g_pFont.DrawTextA(nil, 'This is a trivial call to ID3DXFont.DrawText', -1, @rc, DT_NOCLIP, D3DXColorToDWord(D3DXColor(1.0, 0.0, 0.0, 1.0)));
{$ELSE}
      // If you wanted to calc the bottom/rect of the rect make these 2 calls
      SetRect(rc, 150, 200, 0, 0);
      g_pFont.DrawTextA(nil, 'This is a trivial call to ID3DXFont.DrawText', -1, @rc, DT_CALCRECT, D3DXColorToDWord(D3DXColor(1.0, 0.0, 0.0, 1.0)));
      g_pFont.DrawTextA(nil, 'This is a trivial call to ID3DXFont.DrawText', -1, @rc, 0, D3DXColorToDWord(D3DXColor(1.0, 0.0, 0.0, 1.0)));
{$ENDIF}
      DXUT_EndPerfEvent;
    end;

    // Demonstration 2:
    // Allow multiple draw calls to sort by texture changes by ID3DXSprite
    // When drawing 2D text use flags: D3DXSPRITE_ALPHABLEND | D3DXSPRITE_SORT_TEXTURE
    // When drawing 3D text use flags: D3DXSPRITE_ALPHABLEND | D3DXSPRITE_SORT_BACKTOFRONT
    begin
      // CDXUTPerfEventGenerator g( DXUT_PERFEVENTCOLOR, L"Demonstration Part 2" );
      DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'Demonstration Part 2');
      g_pTextSprite._Begin(D3DXSPRITE_ALPHABLEND or D3DXSPRITE_SORT_TEXTURE);
      SetRect(rc, 10, nHeight - 15*6, 0, 0);
      g_pFont2.DrawTextA(g_pTextSprite, 'These multiple calls to ID3DXFont::DrawText using the same ID3DXSprite.', -1, @rc, DT_NOCLIP, D3DXColorToDWord(D3DXColor(1.0, 1.0, 1.0, 1.0)));
      SetRect(rc, 10, nHeight - 15*5, 0, 0);
      g_pFont2.DrawTextA(g_pTextSprite, 'ID3DXFont now caches letters on one or more textures.', -1, @rc, DT_NOCLIP, D3DXColorToDWord(D3DXColor(1.0, 1.0, 1.0, 1.0)));
      SetRect(rc, 10, nHeight - 15*4, 0, 0);
      g_pFont2.DrawTextA(g_pTextSprite, 'In order to sort by texture state changes on multiple', -1, @rc, DT_NOCLIP, D3DXColorToDWord(D3DXColor(1.0, 1.0, 1.0, 1.0)));
      SetRect(rc, 10, nHeight - 15*3, 0, 0);
      g_pFont2.DrawTextA(g_pTextSprite, 'draw calls to DrawText pass a ID3DXSprite and use', -1, @rc, DT_NOCLIP, D3DXColorToDWord(D3DXColor(1.0, 1.0, 1.0, 1.0)));
      SetRect(rc, 10, nHeight - 15*2, 0, 0);
      g_pFont2.DrawTextA(g_pTextSprite, 'flags D3DXSPRITE_ALPHABLEND or D3DXSPRITE_SORT_TEXTURE', -1, @rc, DT_NOCLIP, D3DXColorToDWord(D3DXColor(1.0, 1.0, 1.0, 1.0)));
      g_pTextSprite._End;
      DXUT_EndPerfEvent;
    end;

    // Demonstration 3:
    // Word wrapping and unicode text.
    // Note that not all fonts support dynamic font linking.
    begin
      // CDXUTPerfEventGenerator g( DXUT_PERFEVENTCOLOR, L"Demonstration Part 3" );
      DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'Demonstration Part 3');
      rc.left := 10;
      rc.top := 60;
      rc.right := DXUTGetPresentParameters.BackBufferWidth - 150;
      rc.bottom := DXUTGetPresentParameters.BackBufferHeight - 10;
      g_pFont2.DrawTextW(nil, g_strTextBuffer, -1, @rc, DT_LEFT or DT_WORDBREAK or DT_EXPANDTABS, D3DXColorToDWord(D3DXColor(1.0, 0.0, 1.0, 1.0)));
      DXUT_EndPerfEvent;
    end;

    // Demonstration 4:
    // Draw 3D extruded text using a mesh created with D3DXFont
    if (g_pMesh3DText <> nil) then
    begin
      // CDXUTPerfEventGenerator g( DXUT_PERFEVENTCOLOR, L"Demonstration Part 4" );
      DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'Demonstration Part 4');
      ZeroMemory( @mtrl, SizeOf(D3DMATERIAL9));
      mtrl.Diffuse.r := 0.0; mtrl.Ambient.r := 0.0;
      mtrl.Diffuse.g := 0.0; mtrl.Ambient.g := 0.0;
      mtrl.Diffuse.b := 1.0; mtrl.Ambient.b := 1.0;
      mtrl.Diffuse.a := 1.0; mtrl.Ambient.a := 1.0;
      pd3dDevice.SetMaterial(mtrl);
      pd3dDevice.SetTransform(D3DTS_WORLD, g_matObj2);
      g_pMesh3DText.DrawSubset(0);
      DXUT_EndPerfEvent;
    end;

    DXUT_EndPerfEvent; // end of demonstration code

    begin
      // CDXUTPerfEventGenerator g( DXUT_PERFEVENTCOLOR, L"HUD / Stats" );
      DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'HUD / Stats');
      V(g_HUD.OnRender(fElapsedTime));
      V(g_SampleUI.OnRender(fElapsedTime));

      // Show frame rate
      SetRect(rc, 2, 0, 0, 0);
      g_pStatsFont.DrawTextW(nil, DXUTGetFrameStats, -1, @rc, DT_NOCLIP, D3DXColorToDWord(D3DXColor(1.0, 1.0, 0.0, 1.0)));
      SetRect(rc, 2, 15, 0, 0);
      g_pStatsFont.DrawTextW(nil, DXUTGetDeviceStats, -1, @rc, DT_NOCLIP, D3DXColorToDWord(D3DXColor(1.0, 1.0, 0.0, 1.0)));
    end;
        
    // End the scene
    pd3dDevice.EndScene;
  end;
end;


//--------------------------------------------------------------------------------------
// Before handling window messages, DXUT passes incoming windows 
// messages to the application through this callback function. If the application sets 
// *pbNoFurtherProcessing to TRUE, then DXUT will not process this message.
//--------------------------------------------------------------------------------------
function MsgProc(hWnd: HWND; uMsg: LongWord; wParam: WPARAM; lParam: LPARAM; out pbNoFurtherProcessing: Boolean; pUserContext: Pointer): LRESULT; stdcall;
begin
  Result:= 0;

  // Always allow dialog resource manager calls to handle global messages
  // so GUI state is updated correctly
  pbNoFurtherProcessing := g_DialogResourceManager.MsgProc(hWnd, uMsg, wParam, lParam);
  if pbNoFurtherProcessing then Exit;

  if g_SettingsDlg.IsActive then
  begin
    g_SettingsDlg.MsgProc(hWnd, uMsg, wParam, lParam);
    Exit;
  end;

  // Give the dialogs a chance to handle the message first
  pbNoFurtherProcessing := g_HUD.MsgProc(hWnd, uMsg, wParam, lParam);
  if pbNoFurtherProcessing then Exit;
  pbNoFurtherProcessing := g_SampleUI.MsgProc(hWnd, uMsg, wParam, lParam);
  if pbNoFurtherProcessing then Exit;

  // Pass all remaining windows messages to camera so it can respond to user input
  g_Camera.HandleMessages(hWnd, uMsg, wParam, lParam);

  case uMsg of
    WM_SIZE:
    begin
      if (SIZE_RESTORED = wParam) then
      begin
      // if( !g_bMaximized && !g_bMinimized )
        begin
          // This sample demonstrates word wrapping, so if the
          // window size is changing because the user dragging the window
          // edges we'll recalc the size, re-init, and repaint
          // the scene as the window resizes.  This would be very
          // slow for complex scene but works here since this sample
          // is trivial.
    (*      HandlePossibleSizeChange();

          // Repaint the window
          if( g_pd3dDevice && !g_bActive && g_bWindowed &&
              g_bDeviceObjectsInited && g_bDeviceObjectsRestored )
          {
              HRESULT hr;
              Render();
              hr = g_pd3dDevice->Present( NULL, NULL, NULL, NULL );
              if( D3DERR_DEVICELOST == hr )
                  g_bDeviceLost = true;
          }*)
        end;
      end;
    end;
  end;
end;


//--------------------------------------------------------------------------------------
// As a convenience, DXUT inspects the incoming windows messages for
// keystroke messages and decodes the message parameters to pass relevant keyboard
// messages to the application.  The framework does not remove the underlying keystroke
// messages, which are still passed to the application's MsgProc callback.
//--------------------------------------------------------------------------------------
procedure KeyboardProc(nChar: LongWord; bKeyDown, bAltDown: Boolean; pUserContext: Pointer); stdcall;
begin
  if bKeyDown then
  begin
    case nChar of
      VK_F1: g_bShowHelp := not g_bShowHelp;
    end;
  end;
end;

{$IFDEF FPC}
type
  //todo -cFPC: remove PLogFontW definition after stable 1.9.7 is released
  PLogFontW = ^TLogFontW;
  LOGFONTW = record
    lfHeight: LONG;
    lfWidth: LONG;
    lfEscapement: LONG;
    lfOrientation: LONG;
    lfWeight: LONG;
    lfItalic: BYTE;
    lfUnderline: BYTE;
    lfStrikeOut: BYTE;
    lfCharSet: BYTE;
    lfOutPrecision: BYTE;
    lfClipPrecision: BYTE;
    lfQuality: BYTE;
    lfPitchAndFamily: BYTE;
    lfFaceName: array [0..LF_FACESIZE - 1] of WCHAR;
  end;
  LPLOGFONTW = ^LOGFONTW;
  NPLOGFONTW = ^LOGFONTW;
  TLogFontW = LOGFONTW;

  tagCHOOSEFONTW = packed record
    lStructSize: DWORD;
    hWndOwner: HWnd;            { caller's window handle }
    hDC: HDC;                   { printer DC/IC or nil }
    lpLogFont: PLogFontW;     { pointer to a LOGFONT struct }
    iPointSize: Integer;        { 10 * size in points of selected font }
    Flags: DWORD;               { dialog flags }
    rgbColors: COLORREF;        { returned text color }
    lCustData: LPARAM;          { data passed to hook function }
    lpfnHook: function(Wnd: HWND; Message: UINT; wParam: WPARAM; lParam: LPARAM): UINT; stdcall;
                                { pointer to hook function }
    lpTemplateName: PWideChar;    { custom template name }
    hInstance: HINST;       { instance handle of EXE that contains
                                  custom dialog template }
    lpszStyle: PWideChar;         { return the style field here
                                  must be lf_FaceSize or bigger }
    nFontType: Word;            { same value reported to the EnumFonts
                                  call back with the extra fonttype_
                                  bits added }
    wReserved: Word;
    nSizeMin: Integer;          { minimum point size allowed and }
    nSizeMax: Integer;          { maximum point size allowed if
                                  cf_LimitSize is used }
  end;
  TChooseFontW = tagCHOOSEFONTW;
{$ENDIF}  

//--------------------------------------------------------------------------------------
// Handles the GUI events
//--------------------------------------------------------------------------------------
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
var
  bWindowed: Boolean;
  hdc: Windows.HDC;
  lHeight: Longint;
  lf: TLogFontW;
  cf: TChooseFontW;
  pFontNew: ID3DXFont;
  pMesh3DTextNew: ID3DXMesh;
  pstrFontNameNew: PWideChar;
  dwFontSizeNew: Integer;
  bSuccess: Boolean;
  bBold, bItalic: Boolean;
  nLogPixelsY: Integer;
  nHeight: Integer;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;
    IDC_CHANGEFONT:
    begin
      bWindowed := DXUTIsWindowed;
      if not bWindowed then DXUTToggleFullScreen;

      hdc := GetDC(DXUTGetHWND);
      lHeight := -MulDiv(g_nFontSize, GetDeviceCaps(hdc, LOGPIXELSY), 72);
      ReleaseDC(DXUTGetHWND, hdc);

      StringCchCopy(lf.lfFaceName, 32, g_strFont);
      lf.lfHeight := lHeight;

      FillChar(cf, SizeOf(cf), #0);
      cf.lStructSize := SizeOf(cf);
      cf.hwndOwner   := DXUTGetHWND;
      cf.lpLogFont   := @lf;
      cf.Flags       := CF_SCREENFONTS or CF_INITTOLOGFONTSTRUCT or CF_TTONLY;

      {$IFDEF FPC}
      if ChooseFontW(@cf) then
      {$ELSE}
      if ChooseFontW(cf) then
      {$ENDIF}
      begin
        pFontNew := nil;
        pMesh3DTextNew := nil;
        pstrFontNameNew := lf.lfFaceName;
        dwFontSizeNew := cf.iPointSize div 10;
        bSuccess := False;
        bBold   := ((cf.nFontType and BOLD_FONTTYPE) = BOLD_FONTTYPE);
        bItalic := ((cf.nFontType and ITALIC_FONTTYPE) = ITALIC_FONTTYPE);

        hDC := GetDC(0);
        nLogPixelsY := GetDeviceCaps(hDC, LOGPIXELSY);
        ReleaseDC(0, hDC);

        nHeight := -MulDiv(dwFontSizeNew, nLogPixelsY, 72);
        if SUCCEEDED(D3DXCreateFontW(DXUTGetD3DDevice, nHeight, 0, IsBold[bBold], 1, bItalic, DEFAULT_CHARSET,
                                       OUT_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE,
                                       pstrFontNameNew, pFontNew)) then
        begin
          if SUCCEEDED(CreateD3DXTextMesh(DXUTGetD3DDevice, pMesh3DTextNew,
                         pstrFontNameNew, dwFontSizeNew, bBold, bItalic)) then 
          begin
            bSuccess := True;
            g_pFont := nil;
            g_pFont := pFontNew;
            pFontNew := nil;

            g_pMesh3DText := nil;
            g_pMesh3DText := pMesh3DTextNew;
            pMesh3DTextNew := nil;

            StringCchCopy(g_strFont, 32, pstrFontNameNew);
            g_nFontSize := dwFontSizeNew;
          end;
        end;

        pMesh3DTextNew := nil;
        pFontNew := nil;

        if not bSuccess then
        begin
          MessageBox(DXUTGetHWND, 'Could not create that font.', 'Text3D', MB_OK);
        end;
      end;

      if not bWindowed then DXUTToggleFullScreen;
    end;
  end;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has 
// entered a lost state and before IDirect3DDevice9::Reset is called. Resources created
// in the OnResetDevice callback should be released here, which generally includes all 
// D3DPOOL_DEFAULT resources. See the "Lost Devices" section of the documentation for 
// information about lost devices.
//--------------------------------------------------------------------------------------
procedure OnLostDevice; stdcall;
begin
  g_DialogResourceManager.OnLostDevice;
  g_SettingsDlg.OnLostDevice;
  CDXUTDirectionWidget.StaticOnLostDevice;
  if Assigned(g_pStatsFont) then g_pStatsFont.OnLostDevice;
  if Assigned(g_pFont) then g_pFont.OnLostDevice;
  if Assigned(g_pFont2) then g_pFont2.OnLostDevice;
  if Assigned(g_pTextSprite) then g_pTextSprite.OnLostDevice;
  SAFE_RELEASE(g_pMesh3DText);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has
// been destroyed, which generally happens as a result of application termination or
// windowed/full screen toggles. Resources created in the OnCreateDevice callback
// should be released here, which generally includes all D3DPOOL_MANAGED resources.
//--------------------------------------------------------------------------------------
procedure OnDestroyDevice; stdcall;
begin
  g_DialogResourceManager.OnDestroyDevice;
  g_SettingsDlg.OnDestroyDevice;
  SAFE_RELEASE(g_pFont);
  SAFE_RELEASE(g_pFont2);
  SAFE_RELEASE(g_pStatsFont);
  SAFE_RELEASE(g_pTextSprite);
end;


procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera:= CFirstPersonCamera.Create;
  g_HUD:= CDXUTDialog.Create;
  g_SampleUI:= CDXUTDialog.Create;
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_Camera);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);
end;

end.

