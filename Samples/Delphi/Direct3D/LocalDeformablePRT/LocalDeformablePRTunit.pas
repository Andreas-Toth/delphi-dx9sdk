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
 *  $Id: LocalDeformablePRTunit.pas,v 1.10 2007/02/05 22:21:09 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: LocalDeformablePRT.cpp
//
// Desc: This sample demonstrates a simple usage of Local-deformable precomputed
//       radiance transfer (LDPRT). This implementation does not require an offline
//       simulator for calulcating PRT coefficients; instead, the coefficients are
//       calculated from a 'thickness' texture. This allows an artist to create and
//       tweak sub-surface scattering PRT data in an intuitive way.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}
{$B-}

unit LocalDeformablePRTunit;

interface

uses
  Windows, SysUtils, Math,
  DXTypes, Direct3D9, D3DX9, dxerr9, StrSafe,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTSettingsDlg, 
  Skybox, SkinMesh;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont: ID3DXFont;            // Font for drawing text
  g_pTextSprite: ID3DXSprite;    // Sprite for batching draw text calls
  g_pEffect: ID3DXEffect;        // D3DX effect interface
  g_Camera: CModelViewerCamera;  // A model viewing camera
  g_bShowHelp: Boolean = True;   // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg;             // Device settings dialog
  g_HUD: CDXUTDialog;            // dialog for standard controls
  g_SampleUI: CDXUTDialog;       // dialog for sample specific controls
  g_bWireFrame: Boolean;
  g_fmtCubeMap: TD3DFormat = D3DFMT_UNKNOWN;
  g_fmtTexture: TD3DFormat = D3DFMT_UNKNOWN;
  g_Skybox: CSkybox;

  // Skinning
  g_pFrameRoot: PD3DXFrame = nil;
  g_pAnimController: ID3DXAnimationController;

  // Lights
  g_LightControl: CDXUTDirectionWidget;
  g_vLightDirection: TD3DXVector3;
  g_fLightIntensity: Single;
  g_fEnvIntensity: Single;
  g_fSkyBoxLightSH: array[0..2, 0..D3DXSH_MAXORDER*D3DXSH_MAXORDER-1] of Single;
  m_fRLC: array[0..D3DXSH_MAXORDER*D3DXSH_MAXORDER-1] of Single;
  m_fGLC: array[0..D3DXSH_MAXORDER*D3DXSH_MAXORDER-1] of Single;
  m_fBLC: array[0..D3DXSH_MAXORDER*D3DXSH_MAXORDER-1] of Single;



//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN          = 1;
  IDC_TOGGLEREF                 = 2;
  IDC_CHANGEDEVICE              = 3;
  IDC_TECHNIQUE                 = 4;
  IDC_RED_TRANSMIT_SLIDER       = 5;
  IDC_GREEN_TRANSMIT_SLIDER     = 6;
  IDC_BLUE_TRANSMIT_SLIDER      = 7;
  IDC_RED_TRANSMIT_LABEL        = 8;
  IDC_GREEN_TRANSMIT_LABEL      = 9;
  IDC_BLUE_TRANSMIT_LABEL       = 10;
  IDC_LIGHT_SLIDER              = 11;
  IDC_ENV_SLIDER                = 12;
  IDC_ENV_LABEL                 = 13;
  IDC_ANIMATION_SPEED           = 14;

  
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
procedure GetSupportedTextureFormat(const pD3D: IDirect3D9; const pCaps: TD3DCaps9;
  AdapterFormat: TD3DFormat; out fmtTexture: TD3DFormat; out fmtCubeMap: TD3DFormat);
function LoadLDPRTData(const pd3dDevice: IDirect3DDevice9; strFilePrefixIn: PWideChar): HRESULT;
procedure SHCubeFill(out pOut: TD3DXVector4; const pTexCoord, pTexelSize: TD3DXVector3; var pData); stdcall;
function LoadTechniqueObjects(const szMedia: PChar): HRESULT;
procedure UpdateLightingEnvironment;
procedure DrawFrame(const pd3dDevice: IDirect3DDevice9; pFrame: PD3DXFrame);
procedure DrawMeshContainer(const pd3dDevice: IDirect3DDevice9; pMeshContainerBase: PD3DXMeshContainer; pFrameBase: PD3DXFrame);
procedure RenderText;


procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;


implementation

type
  PSingleArray = ^TSingleArray;
  TSingleArray = Array[0..MaxInt div Sizeof(Single)-1] of Single;

//--------------------------------------------------------------------------------------
// struct SHCubeProj
// Used to generate lighting coefficients to match the skybox's light probe
//--------------------------------------------------------------------------------------
type
  PSHCubeProj = ^TSHCubeProj;
  TSHCubeProj = record
    pRed, pGreen, pBlue: PSingle;
    iOrderUse: Integer;  // order to use
    fConvCoeffs: array[0..5] of Single; // convolution coefficients
  end;

procedure TSHCubeProj_InitDiffCubeMap(var _: TSHCubeProj; pR, pG, pB: PSingle);
begin
  _.pRed := pR;
  _.pGreen := pG;
  _.pBlue := pB;

  _.iOrderUse := 3; // go to 5 is a bit more accurate...
  _.fConvCoeffs[0] := 1.0;
  _.fConvCoeffs[1] := 2.0/3.0;
  _.fConvCoeffs[2] := 1.0/4.0;
  _.fConvCoeffs[3] := 0.0;
  _.fConvCoeffs[4] := -6.0/144.0; //
  _.fConvCoeffs[5] := 0.0;
end;

procedure TSHCubeProj_Init(var _: TSHCubeProj; pR, pG, pB: PSingle);
var
  i: Integer;
begin
  _.pRed := pR;
  _.pGreen := pG;
  _.pBlue := pB;

  _.iOrderUse := 6;
  for i := 0 to 5 do _.fConvCoeffs[i] := 1.0;
end;

const
  cLDPRT: PChar = 'LDPRT';
  cNdotL: PChar = 'NdotL';

//--------------------------------------------------------------------------------------
// Initialize the app
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  iX, iY: Integer;
  pElement: CDXUTElement;
begin
  //g_LightControl.SetLightDirection( D3DXVECTOR3(-0.29f, 0.557f, 0.778f));
  g_LightControl.SetLightDirection(D3DXVector3(-0.789, 0.527, 0.316));
  g_LightControl.SetButtonMask(MOUSE_MIDDLE_BUTTON);

  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_SampleUI.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent); iX := 15;
  iY := 10;    g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', iX, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)',           iX, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)',     iX, iY, 125, 22, VK_F2);

  g_SampleUI.SetCallback(OnGUIEvent);
  iX := 15; iY := 10;

  // Title font for static
  g_SampleUI.SetFont(1, 'Arial', 14, FW_NORMAL);
  pElement := g_SampleUI.GetDefaultElement(DXUT_CONTROL_STATIC, 0);
  if Assigned(pElement) then
  begin
    pElement.iFont := 1;
    pElement.dwTextFormat := DT_RIGHT or DT_VCENTER;
  end;

  // Technique
  Inc(iY, 24);
  g_SampleUI.AddStatic(-1, 'Technique', iX, iY, 115, 22);
  g_SampleUI.AddComboBox(IDC_TECHNIQUE, iX + 125, iY, 150, 22);
  g_SampleUI.GetComboBox(IDC_TECHNIQUE).SetScrollBarWidth(0);
  g_SampleUI.GetComboBox(IDC_TECHNIQUE).AddItem('Local-deformable PRT', cLDPRT);
  g_SampleUI.GetComboBox(IDC_TECHNIQUE).AddItem('N dot L lighting', cNdotL);

  // Animation speed
  Inc(iY, 10);
  Inc(iY, 24);
  g_SampleUI.AddStatic(-1, 'Animation Speed', iX, iY, 115, 22);
  g_SampleUI.AddSlider(IDC_ANIMATION_SPEED, iX + 125, iY, 125, 22, 0, 3000, 700);

  // Light intensity
  Inc(iY, 10);
  Inc(iY, 24);
  g_SampleUI.AddStatic(-1, 'Light Intensity', iX, iY, 115, 22);
  g_SampleUI.AddSlider(IDC_LIGHT_SLIDER, iX + 125, iY, 125, 22, 0, 1000, 500);
  Inc(iY, 24);
  g_SampleUI.AddStatic(IDC_ENV_LABEL, 'Env Intensity', iX, iY, 115, 22);
  g_SampleUI.AddSlider(IDC_ENV_SLIDER, iX + 125, iY, 125, 22, 0, 3000, 600);

  // Color transmission
  Inc(iY, 10);
  Inc(iY, 24);
  g_SampleUI.AddStatic(IDC_RED_TRANSMIT_LABEL, 'Transmit Red', iX, iY, 115, 22);
  g_SampleUI.AddSlider(IDC_RED_TRANSMIT_SLIDER, iX + 125, iY, 125, 22, 0, 3000, 1200);
  Inc(iY, 24);
  g_SampleUI.AddStatic(IDC_GREEN_TRANSMIT_LABEL, 'Transmit Green', iX, iY, 115, 22);
  g_SampleUI.AddSlider(IDC_GREEN_TRANSMIT_SLIDER, iX + 125, iY, 125, 22, 0, 3000, 800);
  Inc(iY, 24);
  g_SampleUI.AddStatic(IDC_BLUE_TRANSMIT_LABEL, 'Transmit Blue', iX, iY, 115, 22);
  g_SampleUI.AddSlider(IDC_BLUE_TRANSMIT_SLIDER, iX + 125, iY, 125, 22, 0, 3000, 350);
end;


//--------------------------------------------------------------------------------------
// Called during device initialization, this code checks the device for some 
// minimum set of capabilities, and rejects those that don't pass by returning false.
//--------------------------------------------------------------------------------------
function IsDeviceAcceptable(const pCaps: TD3DCaps9; AdapterFormat, BackBufferFormat: TD3DFormat; bWindowed: Boolean; pUserContext: Pointer): Boolean; stdcall;
var
  pD3D: IDirect3D9;
  fmtTexture, fmtCubeMap: TD3DFormat;
begin
  Result := False;

  // Skip backbuffer formats that don't support alpha blending
  pD3D := DXUTGetD3DObject;
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                   AdapterFormat, D3DUSAGE_QUERY_POSTPIXELSHADER_BLENDING,
                   D3DRTYPE_TEXTURE, BackBufferFormat))
  then Exit;

  // Determine texture support.  Fail if not good enough
  GetSupportedTextureFormat(pD3D, pCaps, AdapterFormat, fmtTexture, fmtCubeMap);
  if (D3DFMT_UNKNOWN = fmtTexture) or (D3DFMT_UNKNOWN = fmtCubeMap) then Exit;

  // This sample requires pixel shader 2.0, but does showcase techniques which will
  // perform well on shader model 1.1 hardware.
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2,0)) then Exit;

  Result := True;
end;


//--------------------------------------------------------------------------------------
procedure GetSupportedTextureFormat(const pD3D: IDirect3D9; const pCaps: TD3DCaps9;
  AdapterFormat: TD3DFormat; out fmtTexture: TD3DFormat; out fmtCubeMap: TD3DFormat);
begin
  fmtTexture := D3DFMT_UNKNOWN;
  fmtCubeMap := D3DFMT_UNKNOWN;

  // check for linear filtering support of signed formats
  fmtTexture := D3DFMT_UNKNOWN;
  if SUCCEEDED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,AdapterFormat,D3DUSAGE_QUERY_FILTER,D3DRTYPE_TEXTURE, D3DFMT_A16B16G16R16F))
  then fmtTexture := D3DFMT_A16B16G16R16F
  else if SUCCEEDED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,AdapterFormat,D3DUSAGE_QUERY_FILTER,D3DRTYPE_TEXTURE, D3DFMT_Q16W16V16U16))
  then fmtTexture := D3DFMT_Q16W16V16U16
  else if SUCCEEDED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType, AdapterFormat,D3DUSAGE_QUERY_FILTER,D3DRTYPE_TEXTURE, D3DFMT_Q8W8V8U8))
  then fmtTexture := D3DFMT_Q8W8V8U8

  // no support for linear filtering of signed, just checking for format support now
  else if SUCCEEDED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType, AdapterFormat, 0, D3DRTYPE_TEXTURE, D3DFMT_A16B16G16R16F))
  then fmtTexture := D3DFMT_A16B16G16R16F
  else if SUCCEEDED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType, AdapterFormat, 0, D3DRTYPE_TEXTURE, D3DFMT_Q16W16V16U16))
  then fmtTexture := D3DFMT_Q16W16V16U16
  else if SUCCEEDED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType, AdapterFormat, 0, D3DRTYPE_TEXTURE, D3DFMT_Q8W8V8U8))
  then fmtTexture := D3DFMT_Q8W8V8U8;

  // check for support linear filtering of signed format cubemaps
  fmtCubeMap := D3DFMT_UNKNOWN;
  if SUCCEEDED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,AdapterFormat,D3DUSAGE_QUERY_FILTER, D3DRTYPE_CUBETEXTURE, D3DFMT_A16B16G16R16F))
  then fmtCubeMap := D3DFMT_A16B16G16R16F
  else if SUCCEEDED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,AdapterFormat,D3DUSAGE_QUERY_FILTER,D3DRTYPE_CUBETEXTURE, D3DFMT_Q16W16V16U16))
  then fmtCubeMap := D3DFMT_Q16W16V16U16
  else if SUCCEEDED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,AdapterFormat,D3DUSAGE_QUERY_FILTER,D3DRTYPE_CUBETEXTURE, D3DFMT_Q8W8V8U8))
  then fmtCubeMap := D3DFMT_Q8W8V8U8

  // no support for linear filtering of signed formats, just checking for format support now
  else if SUCCEEDED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,AdapterFormat, 0,D3DRTYPE_CUBETEXTURE, D3DFMT_A16B16G16R16F))
  then fmtCubeMap := D3DFMT_A16B16G16R16F
  else if SUCCEEDED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,AdapterFormat, 0,D3DRTYPE_CUBETEXTURE, D3DFMT_Q16W16V16U16))
  then fmtCubeMap := D3DFMT_Q16W16V16U16
  else if SUCCEEDED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,AdapterFormat, 0,D3DRTYPE_CUBETEXTURE, D3DFMT_Q8W8V8U8))
  then fmtCubeMap := D3DFMT_Q8W8V8U8;
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
  // Turn vsync off
  pDeviceSettings.pp.PresentationInterval := D3DPRESENT_INTERVAL_IMMEDIATE;
  g_SettingsDlg.DialogControl.GetComboBox(DXUTSETTINGSDLG_PRESENT_INTERVAL).Enabled := False;

   // If device doesn't support HW T&L or doesn't support 2.0 vertex shaders in HW
  // then switch to SWVP.
  if (pCaps.DevCaps and D3DDEVCAPS_HWTRANSFORMANDLIGHT = 0) or
     (pCaps.VertexShaderVersion < D3DVS_VERSION(2,0))
  then pDeviceSettings.BehaviorFlags := D3DCREATE_SOFTWARE_VERTEXPROCESSING;

  // Debugging vertex shaders requires either REF or software vertex processing
  // and debugging pixel shaders requires REF.
{$IFDEF DEBUG_VS}
  if (pDeviceSettings.DeviceType <> D3DDEVTYPE_REF) then
  with pDeviceSettings do
  begin
    BehaviorFlags := BehaviorFlags and not D3DCREATE_HARDWARE_VERTEXPROCESSING;
    BehaviorFlags := BehaviorFlags and not D3DCREATE_MIXED_VERTEXPROCESSING;
    BehaviorFlags := BehaviorFlags and not D3DCREATE_PUREDEVICE;
    BehaviorFlags := BehaviorFlags or D3DCREATE_SOFTWARE_VERTEXPROCESSING;
  end;
{$ENDIF}
{$IFDEF DEBUG_PS}
  pDeviceSettings.DeviceType := D3DDEVTYPE_REF;
{$ENDIF}

  if (pCaps.MaxVertexBlendMatrices < 2)
  then pDeviceSettings.BehaviorFlags := D3DCREATE_SOFTWARE_VERTEXPROCESSING;

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
  dwShaderFlags: DWORD;
  pD3D: IDirect3D9;
  Caps: TD3DCaps9;
  DisplayMode: D3DDISPLAYMODE;
  pSHCubeTex: IDirect3DCubeTexture9;
  projData: TSHCubeProj;
  str: array[0..MAX_PATH-1] of WideChar;
  vecEye: TD3DXVector3;
  vecAt: TD3DXVector3;
  quatRotation: TD3DXQuaternion;
begin
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  // Initialize the font
  Result := D3DXCreateFont(pd3dDevice, 15, 0, FW_BOLD, 1, FALSE, DEFAULT_CHARSET,
                           OUT_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE,
                           'Arial', g_pFont);
  if V_Failed(Result) then Exit;

  // Define DEBUG_VS and/or DEBUG_PS to debug vertex and/or pixel shaders with the
  // shader debugger. Debugging vertex shaders requires either REF or software vertex
  // processing, and debugging pixel shaders requires REF.  The
  // D3DXSHADER_FORCE_*_SOFTWARE_NOOPT flag improves the debug experience in the
  // shader debugger.  It enables source level debugging, prevents instruction
  // reordering, prevents dead code elimination, and forces the compiler to compile
  // against the next higher available software target, which ensures that the
  // unoptimized shaders do not exceed the shader model limitations.  Setting these
  // flags will cause slower rendering since the shaders will be unoptimized and
  // forced into software.  See the DirectX documentation for more information about
  // using the shader debugger.
  dwShaderFlags := D3DXFX_NOT_CLONEABLE;

  {$IFDEF DEBUG}
  // Set the D3DXSHADER_DEBUG flag to embed debug information in the shaders.
  // Setting this flag improves the shader debugging experience, but still allows
  // the shaders to be optimized and to run exactly the way they will run in
  // the release configuration of this program.
  dwShaderFlags := dwShaderFlags or D3DXSHADER_DEBUG;
  {$ENDIF}

  {$IFDEF DEBUG_VS}
  dwShaderFlags := dwShaderFlags or D3DXSHADER_FORCE_VS_SOFTWARE_NOOPT;
  {$ENDIF}
  {$IFDEF DEBUG_PS}
  dwShaderFlags := dwShaderFlags or D3DXSHADER_FORCE_PS_SOFTWARE_NOOPT;
  {$ENDIF}

  // Determine which LDPRT texture and SH coefficient cubemap formats are supported
  pD3D := DXUTGetD3DObject;
  pd3dDevice.GetDeviceCaps(Caps);
  pd3dDevice.GetDisplayMode(0, DisplayMode);

  GetSupportedTextureFormat(pD3D, Caps, DisplayMode.Format, g_fmtTexture, g_fmtCubeMap);
  if (D3DFMT_UNKNOWN = g_fmtTexture) or (D3DFMT_UNKNOWN = g_fmtCubeMap) then
  begin
    Result:= E_FAIL;
    Exit;
  end;

  // Create the skybox
  g_Skybox.OnCreateDevice(pd3dDevice, 50, 'Light Probes\rnl_cross.dds', 'SkyBox.fx');
  V(D3DXSHProjectCubeMap(6, g_Skybox.EnvironmentMap, @g_fSkyBoxLightSH[0], @g_fSkyBoxLightSH[1], @g_fSkyBoxLightSH[2]));

  // Now compute the SH projection of the skybox...
  V(D3DXCreateCubeTexture(pd3dDevice, 256, 1, 0, D3DFMT_A16B16G16R16F, D3DPOOL_MANAGED, pSHCubeTex));

  TSHCubeProj_Init(projData, @g_fSkyBoxLightSH[0],@g_fSkyBoxLightSH[1],@g_fSkyBoxLightSH[2]);

  V(D3DXFillCubeTexture(pSHCubeTex, SHCubeFill, @projData));
  g_Skybox.InitSH(pSHCubeTex);

  // Read the D3DX effect file
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'LocalDeformablePRT.fx');
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to they the .fx file failed to compile
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags, nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  Result:= LoadTechniqueObjects('bat');
  if V_Failed(Result) then Exit;

  Result:= g_LightControl.StaticOnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  g_LightControl.Radius := 2.0;

  // Setup the camera's view parameters
  vecEye := D3DXVector3(0.0, 0.0, -5.0);
  vecAt := D3DXVector3(0.0, 0.0, 0.0);
  g_Camera.SetViewParams(vecEye, vecAt);

  // Set the model's initial orientation
  D3DXQuaternionRotationYawPitchRoll(quatRotation, -0.5, 0.7, 0.0);
  g_Camera.SetWorldQuat(quatRotation);
end;


//--------------------------------------------------------------------------------------
procedure SHCubeFill(out pOut: TD3DXVector4; const pTexCoord, pTexelSize: TD3DXVector3; var pData); stdcall;
var
  pCP: PSHCubeProj;
  vDir: TD3DXVector3;
  fVals: array[0..35] of Single;
  l, m, uIndex: Integer;
  fConvUse: Single;
begin
  pCP := PSHCubeProj(@pData);

  D3DXVec3Normalize(vDir, pTexCoord);

  D3DXSHEvalDirection(@fVals, pCP.iOrderUse, vDir);

  pOut := D3DXVector4(0,0,0,0); // just clear it out...

  uIndex := 0;
  for l := 0 to pCP.iOrderUse - 1 do
  begin
    fConvUse := pCP.fConvCoeffs[l];
    for m := 0 to 2*l do
    begin
      pOut.x := pOut.x + fConvUse*fVals[uIndex]*PSingleArray(pCP.pRed)[uIndex];
      pOut.y := pOut.y + fConvUse*fVals[uIndex]*PSingleArray(pCP.pGreen)[uIndex];
      pOut.z := pOut.z + fConvUse*fVals[uIndex]*PSingleArray(pCP.pBlue)[uIndex];
      pOut.w := 1;

      Inc(uIndex);
    end;
  end;
end;


//--------------------------------------------------------------------------------------
procedure myFillBF(out pOut: TD3DXVector4; const pTexCoord, pTexelSize: TD3DXVector3; var pData); stdcall;
var
  vDir: TD3DXVector3;
  iBase: Integer;
  fVals: array[0..15] of Single; 
begin
  iBase := INT_PTR(@pData);

  D3DXVec3Normalize(vDir, pTexCoord);

  D3DXSHEvalDirection(@fVals, 4, vDir);

  pOut := D3DXVector4(fVals[iBase+0], fVals[iBase+1], fVals[iBase+2], fVals[iBase+3]);
end;


//--------------------------------------------------------------------------------------
// This function loads a new technique and all device objects it requires.
//--------------------------------------------------------------------------------------
function LoadTechniqueObjects(const szMedia: PChar): HRESULT;
const
  pNames: array[0..3] of PChar = ('YlmCoeff0','YlmCoeff4','YlmCoeff8','YlmCoeff12');
var
  pTexture: IDirect3DTexture9;
  pCubeTexture: IDirect3DCubeTexture9;
  pDevice: IDirect3DDevice9;
  strFileName: array[0..MAX_PATH] of WideChar;
  strPath: array[0..MAX_PATH] of WideChar;
  strTechnique: array[0..MAX_PATH-1] of AnsiChar;
  strComboTech: PAnsiChar;
  hTechnique: TD3DXHandle;
  bLDPRT: Boolean;
  i: Integer;
begin
  if (nil = g_pEffect) then
  begin
    Result:= D3DERR_INVALIDCALL;
    Exit;
  end;

  pDevice := DXUTGetD3DDevice;

  // Make sure the technique works
  strComboTech := PAnsiChar(g_SampleUI.GetComboBox(IDC_TECHNIQUE).GetSelectedData);
  StringCchCopy(strTechnique, MAX_PATH, strComboTech);
  bLDPRT := {Assigned(strTechnique) and }(0 = lstrcmp(strTechnique, 'LDPRT'));

  // If we're not a signed format, make sure we use a technnique that will unbias
  if (D3DFMT_Q16W16V16U16 <> g_fmtTexture) and (D3DFMT_Q8W8V8U8 <> g_fmtTexture)
  then StringCchCat(strTechnique, MAX_PATH, '_Unbias');

  hTechnique := g_pEffect.GetTechniqueByName(strTechnique);
  Result:= g_pEffect.SetTechnique(hTechnique);
  if V_Failed(Result) then Exit;

  // Enable/disable LDPRT-only items
  g_SampleUI.GetStatic(IDC_ENV_LABEL).Enabled := bLDPRT;
  g_SampleUI.GetSlider(IDC_ENV_SLIDER).Enabled := bLDPRT;
  g_SampleUI.GetSlider(IDC_RED_TRANSMIT_SLIDER).Enabled := bLDPRT;
  g_SampleUI.GetSlider(IDC_GREEN_TRANSMIT_SLIDER).Enabled := bLDPRT;
  g_SampleUI.GetSlider(IDC_BLUE_TRANSMIT_SLIDER).Enabled := bLDPRT;
  g_SampleUI.GetStatic(IDC_RED_TRANSMIT_LABEL).Enabled := bLDPRT;
  g_SampleUI.GetStatic(IDC_GREEN_TRANSMIT_LABEL).Enabled := bLDPRT;
  g_SampleUI.GetStatic(IDC_BLUE_TRANSMIT_LABEL).Enabled := bLDPRT;

  // Load the mesh
  StringCchFormat(strFileName, MAX_PATH, 'media\%S', [szMedia]);
  Result:= LoadLDPRTData(pDevice, strFileName);
  if V_Failed(Result) then Exit;

  // Albedo texture
  StringCchFormat(strFileName, MAX_PATH, 'media\%SAlbedo.dds', [szMedia]);
  DXUTFindDXSDKMediaFile(strPath, MAX_PATH, strFileName);
  V(D3DXCreateTextureFromFileW(pDevice, strPath, pTexture));
  g_pEffect.SetTexture('Albedo', pTexture);
  SAFE_RELEASE(pTexture);
    
  // Normal map
  StringCchFormat(strFileName, MAX_PATH, 'media\%SNormalMap.dds', [szMedia]);
  DXUTFindDXSDKMediaFile(strPath, MAX_PATH, strFileName);
  V(D3DXCreateTextureFromFileExW(pDevice, strPath, D3DX_DEFAULT, D3DX_DEFAULT, D3DX_DEFAULT, 0,
                                  g_fmtTexture, D3DPOOL_MANAGED, D3DX_DEFAULT, D3DX_DEFAULT, 0,
                                  nil, nil, pTexture));
  g_pEffect.SetTexture('NormalMap', pTexture);
  SAFE_RELEASE(pTexture);

  // Spherical harmonic basic functions
  for i := 0 to 3 do
  begin
    D3DXCreateCubeTexture(pDevice, 32, 1, 0, g_fmtCubeMap, D3DPOOL_MANAGED, pCubeTexture);
    D3DXFillCubeTexture(pCubeTexture, myFillBF, Pointer(INT_PTR(i*4)));
    g_pEffect.SetTexture(TD3DXHandle(pNames[i]), pCubeTexture);
    SAFE_RELEASE(pCubeTexture);
  end;

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// This function loads the mesh and LDPRT data.  It also centers and optimizes the 
// mesh for the graphics card's vertex cache.
//--------------------------------------------------------------------------------------
function LoadLDPRTData(const pd3dDevice: IDirect3DDevice9; strFilePrefixIn: PWideChar): HRESULT;
var
  Alloc: CAllocateHierarchy;
  str, strFileName: WideString;
begin
  Alloc := CAllocateHierarchy.Create;
  try
    // Load the mesh with D3DX and get back a ID3DXMesh*.  For this
    // sample we'll ignore the X file's embedded materials since we know
    // exactly the model we're loading.  See the mesh samples such as
    // "OptimizedMesh" for a more generic mesh loading example.
    strFileName:= WideFormat('%s.x', [strFilePrefixIn]);
    Result:= DXUTFindDXSDKMediaFile(str, PWideChar(strFileName)); //this is for FPC compatibility
    if V_Failed(Result) then Exit;

    // Delete existing resources
    if Assigned(g_pFrameRoot) then
    begin
      D3DXFrameDestroy(g_pFrameRoot, Alloc);
      g_pFrameRoot := nil;
    end;

    // Create hierarchy
    Result:= D3DXLoadMeshHierarchyFromXW(PWideChar(str), D3DXMESH_MANAGED, pd3dDevice,
                                         Alloc, nil, g_pFrameRoot, g_pAnimController);
    if V_Failed(Result) then Exit;

    SetupBoneMatrixPointers(g_pFrameRoot, g_pFrameRoot);
  finally
    FreeAndNil(Alloc);
  end;

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
  fAspectRatio: Single;
begin
  Result:= g_DialogResourceManager.OnResetDevice;
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnResetDevice;
  if V_Failed(Result) then Exit;

  if Assigned(g_pFont) then
  begin
    Result:= g_pFont.OnResetDevice;
    if V_Failed(Result) then Exit;
  end;
  if Assigned(g_pEffect) then
  begin
    Result:= g_pEffect.OnResetDevice;
    if V_Failed(Result) then Exit;
  end;

  g_LightControl.OnResetDevice(pBackBufferSurfaceDesc);
  g_Skybox.OnResetDevice(pBackBufferSurfaceDesc);

  // Create a sprite to help batch calls when drawing many lines of text
  Result:= D3DXCreateSprite(pd3dDevice, g_pTextSprite);
  if V_Failed(Result) then Exit;

  // Setup the camera's projection parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI/4, fAspectRatio, 0.001, 1000.0);
  g_Camera.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);
  g_Camera.SetButtonMasks(MOUSE_LEFT_BUTTON, MOUSE_WHEEL, MOUSE_RIGHT_BUTTON);
  g_Camera.SetAttachCameraToModel(True);
  g_Camera.SetRadius(5.0, 0.1, 20.0);

  g_HUD.SetLocation( pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation(pBackBufferSurfaceDesc.Width-300, pBackBufferSurfaceDesc.Height-245);
  g_SampleUI.SetSize(300, 300);

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called once at the beginning of every frame. This is the
// best location for your application to handle updates to the scene, but is not
// intended to contain actual rendering calls, which should instead be placed in the
// OnFrameRender callback.
//--------------------------------------------------------------------------------------
procedure OnFrameMove(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
begin
  // Update the camera's position based on user input 
  g_Camera.FrameMove(fElapsedTime);

  UpdateLightingEnvironment;

  if (g_pAnimController <> nil) then
  begin
    g_pAnimController.SetTrackSpeed(0, g_SampleUI.GetSlider(IDC_ANIMATION_SPEED).Value / 1000.0);
    g_pAnimController.AdvanceTime(fElapsedTime, nil);
  end;

  UpdateFrameMatrices( g_pFrameRoot, g_Camera.GetWorldMatrix);
end;


//--------------------------------------------------------------------------------------
procedure UpdateLightingEnvironment;
var
  fSkybox: array[0..2, 0..D3DXSH_MAXORDER*D3DXSH_MAXORDER-1] of Single; 
begin
  // Gather lighting options from the HUD
  g_vLightDirection := g_LightControl.LightDirection;
  g_fLightIntensity := g_SampleUI.Slider[IDC_LIGHT_SLIDER].Value / 100.0;
  g_fEnvIntensity := g_SampleUI.Slider[IDC_ENV_SLIDER].Value / 1000.0;

  // Create the spotlight
  D3DXSHEvalConeLight(D3DXSH_MAXORDER, g_vLightDirection, D3DX_PI/8.0,
                      g_fLightIntensity, g_fLightIntensity, g_fLightIntensity,
                      @m_fRLC, @m_fGLC, @m_fBLC);

  // Scale the light probe environment contribution based on input options
  D3DXSHScale(@fSkybox[0], D3DXSH_MAXORDER, @g_fSkyBoxLightSH[0], g_fEnvIntensity);
  D3DXSHScale(@fSkybox[1], D3DXSH_MAXORDER, @g_fSkyBoxLightSH[1], g_fEnvIntensity);
  D3DXSHScale(@fSkybox[2], D3DXSH_MAXORDER, @g_fSkyBoxLightSH[2], g_fEnvIntensity);

  // Combine the environment and the spotlight
  D3DXSHAdd(@m_fRLC, D3DXSH_MAXORDER, @m_fRLC, @fSkybox[0]);
  D3DXSHAdd(@m_fGLC, D3DXSH_MAXORDER, @m_fGLC, @fSkybox[1]);
  D3DXSHAdd(@m_fBLC, D3DXSH_MAXORDER, @m_fBLC, @fSkybox[2]);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called at the end of every frame to perform all the
// rendering calls for the scene, and it will also be called if the window needs to be
// repainted. After this function has returned, DXUT will call 
// IDirect3DDevice9::Present to display the contents of the next buffer in the swap chain
//--------------------------------------------------------------------------------------
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
const
  IsWireframe: array[False..True] of DWORD = (D3DFILL_SOLID, D3DFILL_WIREFRAME);
var
  mViewProjection: TD3DXMatrixA16;
  vColorTransmit: TD3DXVector3;
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  // Clear the render target and the zbuffer
  V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, D3DCOLOR_ARGB(0, 50, 50, 50), 1.0, 0));

  // Render the scene
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    // Get the projection & view matrix from the camera class
    // mViewProjection := g_Camera.GetViewMatrix * g_Camera.GetProjMatrix;
    D3DXMatrixMultiply(mViewProjection, g_Camera.GetViewMatrix^, g_Camera.GetProjMatrix^);

    g_Skybox.DrawSH := False;
    g_Skybox.Render(mViewProjection, 1.0, 1.0);

    V(g_pEffect.SetMatrix('g_mViewProjection', mViewProjection));
    V(g_pEffect.SetFloat('g_fTime', fTime));

    // Set the amount of transmitted light per color channel
    vColorTransmit.x := g_SampleUI.GetSlider(IDC_RED_TRANSMIT_SLIDER).Value / 1000.0;
    vColorTransmit.y := g_SampleUI.GetSlider(IDC_GREEN_TRANSMIT_SLIDER).Value / 1000.0;
    vColorTransmit.z := g_SampleUI.GetSlider(IDC_BLUE_TRANSMIT_SLIDER).Value / 1000.0;
    V(g_pEffect.SetFloatArray('g_vColorTransmit', @vColorTransmit, 3));

    // for Cubic degree rendering
    V(g_pEffect.SetFloat('g_fLightIntensity', g_fLightIntensity));
    V(g_pEffect.SetFloatArray('g_vLightDirection', @g_vLightDirection, 3 * SizeOf(Single)));
    V(g_pEffect.SetFloatArray('g_vLightCoeffsR', @m_fRLC, 4 * SizeOf(Single)));
    V(g_pEffect.SetFloatArray('g_vLightCoeffsG', @m_fGLC, 4 * SizeOf(Single)));
    V(g_pEffect.SetFloatArray('g_vLightCoeffsB', @m_fBLC, 4 * SizeOf(Single)));

    pd3dDevice.SetRenderState(D3DRS_FILLMODE, IsWireframe[g_bWireFrame]);
        
    DrawFrame(pd3dDevice, g_pFrameRoot);

    DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'HUD / Stats'); // These events are to help PIX identify what the code is doing
    RenderText;
    V(g_HUD.OnRender(fElapsedTime));
    V(g_SampleUI.OnRender(fElapsedTime));
    V(g_LightControl.OnRender(D3DXColor(1, 1, 1, 1), g_Camera.GetViewMatrix^, g_Camera.GetProjMatrix^, g_Camera.GetEyePt^));
    DXUT_EndPerfEvent;

    V(pd3dDevice.EndScene);
  end;
end;


//--------------------------------------------------------------------------------------
// Called to render a frame in the hierarchy
//--------------------------------------------------------------------------------------
procedure DrawFrame(const pd3dDevice: IDirect3DDevice9; pFrame: PD3DXFrame);
var
  pMeshContainer: PD3DXMeshContainer;
begin
  pMeshContainer := pFrame.pMeshContainer;
  while (pMeshContainer <> nil) do
  begin
    DrawMeshContainer(pd3dDevice, pMeshContainer, pFrame);
    pMeshContainer := pMeshContainer.pNextMeshContainer;
  end;

  if (pFrame.pFrameSibling <> nil) then DrawFrame(pd3dDevice, pFrame.pFrameSibling);
  if (pFrame.pFrameFirstChild <> nil) then DrawFrame(pd3dDevice, pFrame.pFrameFirstChild);
end;


//--------------------------------------------------------------------------------------
// Called to render a mesh in the hierarchy
//--------------------------------------------------------------------------------------
procedure DrawMeshContainer(const pd3dDevice: IDirect3DDevice9; pMeshContainerBase: PD3DXMeshContainer; pFrameBase: PD3DXFrame);
var
  pMeshContainer: PD3DXMeshContainerDerived;
  iMaterial, iAttrib, iPaletteEntry, iPass: Integer;
  pBoneComb: PD3DXBoneCombination;
  BoneMatrices: array[0..MAX_BONES-1] of TD3DXMatrixA16;
  iMatrixIndex: LongWord;
  numPasses: LongWord;
begin
  pMeshContainer := PD3DXMeshContainerDerived(pMeshContainerBase);

  // If there's no skinning information just draw the mesh
  if (nil = pMeshContainer.pSkinInfo) then
  begin
    for iMaterial := 0 to pMeshContainer.NumMaterials - 1 do
      V(ID3DXMesh(pMeshContainer.MeshData.pMesh).DrawSubset(iMaterial));

    Exit;
  end;

  pBoneComb := PD3DXBoneCombination(pMeshContainer.pBoneCombinationBuf.GetBufferPointer);
  for iAttrib := 0 to pMeshContainer.NumAttributeGroups - 1 do
  begin
    // first calculate all the world matrices
    for iPaletteEntry := 0 to pMeshContainer.NumPaletteEntries - 1 do
    begin
      // iMatrixIndex := pBoneComb[iAttrib].BoneId[iPaletteEntry]; -- We instead do Inc at the end of cycle
      iMatrixIndex := pBoneComb.BoneId[iPaletteEntry];
      if (iMatrixIndex <> High(LongWord){UINT_MAX}) then
        D3DXMatrixMultiply(BoneMatrices[iPaletteEntry],
                           pMeshContainer.pBoneOffsetMatrices[iMatrixIndex],
                           pMeshContainer.ppBoneMatrixPtrs[iMatrixIndex]^);
    end;

    V(g_pEffect.SetMatrixArray('g_mWorldMatrixArray', @BoneMatrices, pMeshContainer.NumPaletteEntries));

    // Set CurNumBones to select the correct vertex shader for the number of bones
    V(g_pEffect.SetInt('g_NumBones', pMeshContainer.NumInfl -1));

    // Start the effect now all parameters have been updated
    V(g_pEffect._Begin(@numPasses, D3DXFX_DONOTSAVESTATE ));
    for iPass := 0 to numPasses - 1 do
    begin
      V(g_pEffect.BeginPass(iPass));

      // Draw the subset with the current world matrix palette and material state
      V(ID3DXMesh(pMeshContainer.MeshData.pMesh).DrawSubset(iAttrib));

      V(g_pEffect.EndPass);
    end;
    V(g_pEffect._End);
    Inc(pBoneComb);
  end;
end;


//--------------------------------------------------------------------------------------
// Render the help and statistics text. This function uses the ID3DXFont interface for
// efficient text rendering.
//--------------------------------------------------------------------------------------
procedure RenderText;
var
  txtHelper: CDXUTTextHelper;
  pd3dsdBackBuffer: PD3DSurfaceDesc;
begin
  // The helper object simply helps keep track of text position, and color
  // and then it calls pFont->DrawText( m_pSprite, strMsg, -1, &rc, DT_NOCLIP, m_clr );
  // If NULL is passed in as the sprite object, then it will work however the
  // pFont->DrawText() will not be batched together.  Batching calls will improves performance.
  pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
  txtHelper := CDXUTTextHelper.Create(g_pFont, g_pTextSprite, 15);

  // Output statistics
  txtHelper._Begin;
  txtHelper.SetInsertionPos(5, 5);
  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));
  txtHelper.DrawTextLine(DXUTGetFrameStats(True)); // Show FPS
  txtHelper.DrawTextLine(DXUTGetDeviceStats);
        
  // Draw help
  if g_bShowHelp then
  begin
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*8);
    txtHelper.SetForegroundColor(D3DXCOLOR( 1.0, 0.75, 0.0, 1.0 ));
    txtHelper.DrawTextLine('Controls (F1 to hide):');

    txtHelper.SetInsertionPos(40, pd3dsdBackBuffer.Height-15*7);
    txtHelper.DrawTextLine('Rotate Model: Left Mouse');
    txtHelper.DrawTextLine('Rotate Light: Middle Mouse');
    txtHelper.DrawTextLine('Rotate Camera and Model: Right Mouse');
    txtHelper.DrawTextLine('Rotate Camera: Ctrl + Right Mouse');
    txtHelper.DrawTextLine('Wireframe: W');
    txtHelper.DrawTextLine('Quit: ESC');
  end else
  begin
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*2);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
    txtHelper.DrawTextLine('Press F1 for help');
  end;
  txtHelper._End;
  txtHelper.Free;
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
  g_LightControl.HandleMessages(hWnd, uMsg, wParam, lParam);
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
      Ord('W'): g_bWireFrame := not g_bWireFrame;
    end;
  end;
end;


//--------------------------------------------------------------------------------------
// Handles the GUI events
//--------------------------------------------------------------------------------------
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF: DXUTToggleREF;
    IDC_CHANGEDEVICE: with g_SettingsDlg do Active := not Active;
    IDC_TECHNIQUE: LoadTechniqueObjects('bat');
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
  if Assigned(g_pFont) then g_pFont.OnLostDevice;
  if Assigned(g_pEffect) then g_pEffect.OnLostDevice;

  g_LightControl.StaticOnLostDevice;
  g_Skybox.OnLostDevice;

  SAFE_RELEASE(g_pTextSprite);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has 
// been destroyed, which generally happens as a result of application termination or 
// windowed/full screen toggles. Resources created in the OnCreateDevice callback
// should be released here, which generally includes all D3DPOOL_MANAGED resources. 
//--------------------------------------------------------------------------------------
procedure OnDestroyDevice; stdcall;
var
  Alloc: CAllocateHierarchy;
begin
  g_DialogResourceManager.OnDestroyDevice;
  g_SettingsDlg.OnDestroyDevice;
  SAFE_RELEASE(g_pEffect);
  SAFE_RELEASE(g_pFont);

  g_LightControl.StaticOnDestroyDevice;
  g_Skybox.OnDestroyDevice;

  if Assigned(g_pFrameRoot) then
  begin
    Alloc := CAllocateHierarchy.Create;
    D3DXFrameDestroy(g_pFrameRoot, Alloc);
    FreeAndNil(Alloc);
    g_pFrameRoot := nil;
  end;

  SAFE_RELEASE(g_pAnimController);
end;



procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera:= CModelViewerCamera.Create;
  g_HUD:= CDXUTDialog.Create;
  g_SampleUI:= CDXUTDialog.Create;
  g_Skybox:= CSkybox.Create;
  g_LightControl:= CDXUTDirectionWidget.Create;
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_Camera);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);
  FreeAndNil(g_Skybox);
  FreeAndNil(g_LightControl);
end;

end.

