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
 *  $Id: HDRFormatsUnit.pas,v 1.13 2007/02/05 22:21:07 clootie Exp $
 *----------------------------------------------------------------------------*)
//-----------------------------------------------------------------------------
// File: HDRFormats.cpp
//
// Desc: This sample shows how to do a single pass motion blur effect using
//       floating point textures and multiple render targets.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//-----------------------------------------------------------------------------

{$I DirectX.inc}

unit HDRFormatsUnit;

interface

uses
  Windows, Messages, SysUtils, Math,
  DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTmesh, DXUTSettingsDlg,
  Skybox;


const
  NUM_TONEMAP_TEXTURES  = 5;          // Number of stages in the 3x3 down-scaling
                                      // of average luminance textures
  NUM_BLOOM_TEXTURES    = 2;
  RGB16_MAX             = 100;

type
  TEncodingMode = (FP16, FP32, RGB16, RGBE8); // , NUM_ENCODING_MODES);
  TRenderMode = (DECODED, RGB_ENCODED, ALPHA_ENCODED); // , NUM_RENDER_MODES);

  PTechHandles = ^TTechHandles;
  TTechHandles  = record
    Scene: TD3DXHandle;
    DownScale2x2_Lum: TD3DXHandle;
    DownScale3x3: TD3DXHandle;
    DownScale3x3_BrightPass: TD3DXHandle;
    FinalPass: TD3DXHandle;
  end;

  TScreenVertex = packed record
    pos: TD3DXVector4;
    tex: TD3DXVector2;
  end;

const
  TScreenVertex_FVF = D3DFVF_XYZRHW or D3DFVF_TEX1;


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pd3dDevice: IDirect3DDevice9;          // Direct3D device
  g_pFont: ID3DXFont;                      // Font for drawing text
  g_Camera: CModelViewerCamera;
  g_pEffect: ID3DXEffect;
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg;          // Device settings dialog
  g_HUD: CDXUTDialog;                      // manages the 3D UI
  g_SampleUI: CDXUTDialog;                 // Sample specific controls
  g_aSkybox: array[TEncodingMode] of CSkybox;
  g_pMSRT: IDirect3DSurface9;              // Multi-Sample float render target
  g_pMSDS: IDirect3DSurface9;              // Depth Stencil surface for the float RT
  g_pTexRender: IDirect3DTexture9;         // Render target texture
  g_pTexBrightPass: IDirect3DTexture9;     // Bright pass filter
  g_pMesh: ID3DXMesh;
  g_apTexToneMap: array[0..NUM_TONEMAP_TEXTURES-1] of IDirect3DTexture9;  // Tone mapping calculation textures
  g_apTexBloom: array[0..NUM_BLOOM_TEXTURES-1] of IDirect3DTexture9;      // Blooming effect intermediate texture
  g_bBloom: Boolean;                       // Bloom effect on/off
  g_eEncodingMode: TEncodingMode;
  g_eRenderMode: TRenderMode;
  g_aTechHandles: array[TEncodingMode] of TTechHandles;
  g_pCurTechnique: PTechHandles;
  g_bShowHelp: Boolean;
  g_bShowText: Boolean;
  g_aPowsOfTwo: array[0..256] of Double;   // Lookup table for log calculations
  g_bSupportsR16F: Boolean = False;
  g_bSupportsR32F: Boolean = False;
  g_bSupportsD16: Boolean = False;
  g_bSupportsD32: Boolean = False;
  g_bSupportsD24X8: Boolean = False;
  g_bUseMultiSample: Boolean = False;      // True when using multisampling on a supported back buffer
  g_MaxMultiSampleType: TD3DMultiSampleType = D3DMULTISAMPLE_NONE; // Non-Zero when g_bUseMultiSample is true
  g_dwMultiSampleQuality: DWORD = 0;       // Used when we have multisampling on a backbuffer


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_STATIC           = -1;
  IDC_TOGGLEFULLSCREEN = 1;
  IDC_TOGGLEREF        = 3;
  IDC_CHANGEDEVICE     = 4;
  IDC_ENCODING_MODE    = 5;
  IDC_RENDER_MODE      = 6;
  IDC_BLOOM            = 7;


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
//todo: report bug report to MS
//function LoadMesh(const pd3dDevice: IDirect3DDevice9; strFileName: PWideChar; out ppMesh: ID3DXMesh): HRESULT; overload;
function LoadMesh(strFileName: WideString; out ppMesh: ID3DXMesh): HRESULT; overload;
procedure RenderText(fTime: Double);
procedure DrawFullScreenQuad(fLeftU: Single = 0.0; fTopV: Single = 0.0; fRightU: Single = 1.0; fBottomV: Single = 1.0);

function RenderModel: HRESULT;

function RetrieveTechHandles: HRESULT;
function GetSampleOffsets_DownScale3x3(dwWidth, dwHeight: DWORD;
  var avSampleOffsets: array of TD3DXVector2): HRESULT;
function GetSampleOffsets_DownScale2x2_Lum(dwSrcWidth, dwSrcHeight, dwDestWidth, dwDestHeight: DWORD;
  var avSampleOffsets: array of TD3DXVector2): HRESULT;
function GetSampleOffsets_Bloom(dwD3DTexSize: DWORD;
  var afTexCoordOffset: array of Single;
  var avColorWeight: array of TD3DXVector4; fDeviation: Single; fMultiplier: Single = 1.0): HRESULT;
function RenderBloom: HRESULT;
function MeasureLuminance: HRESULT;
function BrightPassFilter: HRESULT;

function CreateEncodedTexture(const pTexSrc: IDirect3DCubeTexture9; out ppTexDest: IDirect3DCubeTexture9; eTarget: TEncodingMode): HRESULT;

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;



implementation


//--------------------------------------------------------------------------------------
// Initialize the app
//--------------------------------------------------------------------------------------
procedure InitApp;
const
  RENDER_MODE_NAMES: array[TRenderMode] of PWideChar =
  (
    'Decoded scene',
    'RGB channels',
    'Alpha channel'
  );
var
  i: Integer;
  iY: Integer;
  pElement: CDXUTElement;
  pComboBox: CDXUTComboBox;
  rm: TRenderMode;
  pMultiSampleTypeList: TD3DMultiSampleTypeArray;
begin
  g_pFont := nil;
  g_pEffect := nil;
  g_bShowHelp := False;
  g_bShowText := True;

  g_pMesh := nil;
  g_pTexRender := nil;

  g_bBloom := True;
  g_eEncodingMode := RGBE8;
  g_eRenderMode := DECODED;

  g_pCurTechnique := @g_aTechHandles[g_eEncodingMode];

  for i := 0 to 255 do g_aPowsOfTwo[i] := Power(2.0, (i - 128));

  ZeroMemory(@g_apTexToneMap, SizeOf(g_apTexToneMap));
  ZeroMemory(@g_apTexBloom, SizeOf(g_apTexBloom));
  ZeroMemory(@g_aTechHandles, SizeOf(g_aTechHandles));

  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_SampleUI.Init(g_DialogResourceManager);

  g_HUD.SetFont(0, 'Arial', 14, 400);
  g_HUD.SetCallback(OnGUIEvent); iY := 10;
  g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22); Inc(iY, 24);
  g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', 35, iY, 125, 22); Inc(iY, 24);
  g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 35, iY, 125, 22, VK_F2);

  g_SampleUI.SetCallback(OnGUIEvent);

  // Title font for comboboxes
  g_SampleUI.SetFont(1, 'Arial', 14, FW_BOLD);
  pElement := g_SampleUI.GetDefaultElement(DXUT_CONTROL_STATIC, 0);
  if Assigned(pElement) then
  begin
    pElement.iFont := 1;
    pElement.dwTextFormat := DT_LEFT or DT_BOTTOM;
  end;

  pComboBox := nil;

  g_SampleUI.AddStatic(IDC_STATIC, '(E)ncoding mode', 0, 0, 105, 25);
  g_SampleUI.AddComboBox(IDC_ENCODING_MODE, 0, 25, 140, 24, Ord('E'), False, @pComboBox);
  if Assigned(pComboBox) then pComboBox.SetDropHeight(50);

  g_SampleUI.AddStatic(IDC_STATIC, '(R)ender mode', 0, 45, 105, 25 );
  g_SampleUI.AddComboBox(IDC_RENDER_MODE, 0, 70, 140, 24, Ord('R'), False, @pComboBox);
  if Assigned(pComboBox) then pComboBox.SetDropHeight(30);

  for rm := Low(TRenderMode) to High(TRenderMode) do
    pComboBox.AddItem(RENDER_MODE_NAMES[rm], {IntToPtr}Pointer(rm));

  g_SampleUI.AddCheckBox(IDC_BLOOM, 'Show (B)loom', 0, 110, 140, 18, g_bBloom, Ord('B'));

  // Although multisampling is supported for render target surfaces, those surfaces
  // exist without a parent texture, and must therefore be copied to a texture
  // surface if they're to be used as a source texture. This sample relies upon
  // several render targets being used as source textures, and therefore it makes
  // sense to disable multisampling altogether.

  // pMultiSampleTypeList.Add(D3DMULTISAMPLE_NONE);
  SetLength(pMultiSampleTypeList, 1);
  pMultiSampleTypeList[0]:= D3DMULTISAMPLE_NONE;
  DXUTGetEnumeration.PossibleMultisampleTypeList:= pMultiSampleTypeList;
  DXUTGetEnumeration.SetMultisampleQualityMax(0);
end;


//--------------------------------------------------------------------------------------
// Called during device initialization, this code checks the device for some
// minimum set of capabilities, and rejects those that don't pass by returning E_FAIL.
//--------------------------------------------------------------------------------------
function IsDeviceAcceptable(const pCaps: TD3DCaps9; AdapterFormat, BackBufferFormat: TD3DFormat; bWindowed: Boolean; pUserContext: Pointer): Boolean; stdcall;
var
  pD3D: IDirect3D9;
begin
  Result:= False;

  // No fallback, so need ps2.0
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2,0)) then Exit;

  // Skip backbuffer formats that don't support alpha blending
  pD3D := DXUTGetD3DObject;
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                   AdapterFormat, D3DUSAGE_QUERY_POSTPIXELSHADER_BLENDING,
                   D3DRTYPE_TEXTURE, BackBufferFormat))
  then Exit;

  Result:= True;
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
  str: array[0..MAX_PATH-1] of WideChar;
  strPath: array [0..MAX_PATH-1] of WideChar;
  vecEye, vecAt: TD3DXVector3;
  dwShaderFlags: DWORD;
  pD3D: IDirect3D9;
  settings: TDXUTDeviceSettings;
  //bCreatedTexture: Boolean;
  pCubeTexture: IDirect3DCubeTexture9;
  pEncodedTexture: IDirect3DCubeTexture9;
  bSupports128FCube: Boolean;  
begin
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  // Initialize the font
  Result:= D3DXCreateFont(pd3dDevice, 15, 0, FW_BOLD, 1, FALSE, DEFAULT_CHARSET,
                          OUT_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE,
                          'Arial', g_pFont);
  if V_Failed(Result) then Exit;

  g_pd3dDevice := pd3dDevice;

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

  Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, 'HDRFormats.fx');
  if FAILED(Result) then Exit;

  Result := D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags, nil, g_pEffect, nil);

  // If this fails, there should be debug output
  if FAILED(Result) then Exit;

  RetrieveTechHandles;

  // Determine which encoding modes this device can support
  pD3D := DXUTGetD3DObject;
  settings := DXUTGetDeviceSettings;

  //bCreatedTexture := False;

  Result:= DXUTFindDXSDKMediaFile(strPath, MAX_PATH, 'Light Probes\uffizi_cross.dds');
  if V_Failed(Result) then Exit;

  g_SampleUI.GetComboBox(IDC_ENCODING_MODE).RemoveAllItems;


  g_bSupportsR16F := False;
  if SUCCEEDED(pD3D.CheckDeviceFormat(settings.AdapterOrdinal, settings.DeviceType,
                                      settings.AdapterFormat, D3DUSAGE_RENDERTARGET,
                                      D3DRTYPE_TEXTURE, D3DFMT_R16F))
  then g_bSupportsR16F := True;

  g_bSupportsR32F := False;
  if SUCCEEDED(pD3D.CheckDeviceFormat(settings.AdapterOrdinal, settings.DeviceType,
                                      settings.AdapterFormat, D3DUSAGE_RENDERTARGET,
                                      D3DRTYPE_TEXTURE, D3DFMT_R32F))
  then g_bSupportsR32F := True;

  bSupports128FCube := false;
  if SUCCEEDED(pD3D.CheckDeviceFormat(settings.AdapterOrdinal, settings.DeviceType,
                                      settings.AdapterFormat, 0,
                                      D3DRTYPE_CUBETEXTURE, D3DFMT_A16B16G16R16F))
  then bSupports128FCube := True;

  // FP16
  if (g_bSupportsR16F and bSupports128FCube) then
  begin
    // Device supports floating-point textures.
    Result:= D3DXCreateCubeTextureFromFileExW(pd3dDevice, strPath, D3DX_DEFAULT, 1, 0, D3DFMT_A16B16G16R16F,
                                              D3DPOOL_MANAGED, D3DX_FILTER_NONE, D3DX_FILTER_NONE, 0, nil, nil, pCubeTexture);
    if V_Failed(Result) then Exit;

    Result:= g_aSkybox[FP16].OnCreateDevice(pd3dDevice, 50, pCubeTexture, 'skybox.fx');
    if V_Failed(Result) then Exit;

    g_SampleUI.GetComboBox(IDC_ENCODING_MODE).AddItem('FP16', Pointer(FP16));
  end;

  // FP32
  if (g_bSupportsR32F and bSupports128FCube) then
  begin
    // Device supports floating-point textures.
    Result:= D3DXCreateCubeTextureFromFileExW(pd3dDevice, strPath, D3DX_DEFAULT, 1, 0, D3DFMT_A16B16G16R16F,
                                                D3DPOOL_MANAGED, D3DX_FILTER_NONE, D3DX_FILTER_NONE, 0, nil, nil, pCubeTexture);
    if V_Failed(Result) then Exit;

    Result:= g_aSkybox[FP32].OnCreateDevice(pd3dDevice, 50, pCubeTexture, 'skybox.fx');
    if V_Failed(Result) then Exit;

    g_SampleUI.GetComboBox(IDC_ENCODING_MODE).AddItem('FP32', Pointer(FP32));
  end;

  if ((not g_bSupportsR32F and not g_bSupportsR16F) or not bSupports128FCube) then
  begin
    // Device doesn't support floating-point textures. Use the scratch pool to load it temporarily
    // in order to create encoded textures from it.
    //bCreatedTexture := True;
    Result:= D3DXCreateCubeTextureFromFileExW(pd3dDevice, strPath, D3DX_DEFAULT, 1, 0, D3DFMT_A16B16G16R16F,
                                              D3DPOOL_SCRATCH, D3DX_FILTER_NONE, D3DX_FILTER_NONE, 0, nil, nil, pCubeTexture);
    if V_Failed(Result) then Exit;
  end;

  // RGB16
  if (D3D_OK = pD3D.CheckDeviceFormat(settings.AdapterOrdinal,
                                      settings.DeviceType,
                                      settings.AdapterFormat, 0,
                                      D3DRTYPE_CUBETEXTURE,
                                      D3DFMT_A16B16G16R16)) then
  begin
    Result:= CreateEncodedTexture(pCubeTexture, pEncodedTexture, RGB16);
    if V_Failed(Result) then Exit;
    Result:= g_aSkybox[RGB16].OnCreateDevice(pd3dDevice, 50, pEncodedTexture, 'skybox.fx');
    if V_Failed(Result) then Exit;

    g_SampleUI.GetComboBox(IDC_ENCODING_MODE).AddItem('RGB16', Pointer(RGB16));
  end;


  // RGBE8
  Result:= CreateEncodedTexture(pCubeTexture, pEncodedTexture, RGBE8);
  if V_Failed(Result) then Exit;
  Result:= g_aSkybox[RGBE8].OnCreateDevice(pd3dDevice, 50, pEncodedTexture, 'skybox.fx');
  if V_Failed(Result) then Exit;

  g_SampleUI.GetComboBox(IDC_ENCODING_MODE).AddItem('RGBE8', Pointer(RGBE8));
  g_SampleUI.GetComboBox(IDC_ENCODING_MODE).SetSelectedByText('RGBE8');

  //Clootie: not needed in Delphi
  // if bCreatedTexture then pCubeTexture:= nil;

  Result := LoadMesh('misc\teapot.x', g_pMesh);
  if Failed(Result) then Exit;

  vecEye := D3DXVector3(0.0, 0.0, -5.0);
  vecAt  := D3DXVector3(0.0, 0.0, 0.0);
  g_Camera.SetViewParams(vecEye, vecAt);

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
  i: TEncodingMode;
  fmt: TD3DFormat;
  nSampleLen: Integer;
  t: Integer;
  pCheckBox: CDXUTCheckBox;
  pComboBox: CDXUTComboBox;
  pD3D: IDirect3D9;
  settings: TDXUTDeviceSettings;
  dfmt: TD3DFormat;
  Caps: TD3DCaps9;
  imst: TD3DMultiSampleType;
  msQuality: DWORD;
  pBackBufferDesc: PD3DSurfaceDesc;
begin
  Result:= g_DialogResourceManager.OnResetDevice;
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnResetDevice;
  if V_Failed(Result) then Exit;

  Result := S_OK;
  if (pd3dDevice = nil) then Exit;

  for i:= Low(i) to High(i) do
    g_aSkybox[i].OnResetDevice(pBackBufferSurfaceDesc);

  if Assigned(g_pFont) then g_pFont.OnResetDevice;
  if Assigned(g_pEffect) then g_pEffect.OnResetDevice;

  fmt := D3DFMT_UNKNOWN;
  case g_eEncodingMode of
    FP16:  fmt := D3DFMT_A16B16G16R16F;
    FP32:  fmt := D3DFMT_A16B16G16R16F;
    RGBE8: fmt := D3DFMT_A8R8G8B8;
    RGB16: fmt := D3DFMT_A16B16G16R16;
  end;

  Result := pd3dDevice.CreateTexture(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height,
                                     1, D3DUSAGE_RENDERTARGET, fmt,
                                     D3DPOOL_DEFAULT, g_pTexRender, nil);
  if Failed(Result) then Exit;

  Result := pd3dDevice.CreateTexture(pBackBufferSurfaceDesc.Width div 8, pBackBufferSurfaceDesc.Height div 8,
                                     1, D3DUSAGE_RENDERTARGET, D3DFMT_A8R8G8B8,
                                     D3DPOOL_DEFAULT, g_pTexBrightPass, nil);
  if Failed(Result) then Exit;

  // Determine whether we can and should support a multisampling on the HDR render target
  g_bUseMultiSample := False;
  pD3D := DXUTGetD3DObject;
  if not Assigned(pD3D) then
  begin
    Result:= E_FAIL;
    Exit;
  end;

  settings := DXUTGetDeviceSettings;

  g_bSupportsD16 := False;
  if SUCCEEDED(pD3D.CheckDeviceFormat(settings.AdapterOrdinal, settings.DeviceType,
                                      settings.AdapterFormat, D3DUSAGE_DEPTHSTENCIL,
                                      D3DRTYPE_SURFACE, D3DFMT_D16)) then
  begin
    if SUCCEEDED(pD3D.CheckDepthStencilMatch(settings.AdapterOrdinal, settings.DeviceType,
                                             settings.AdapterFormat, fmt,
                                             D3DFMT_D16)) then
    begin
      g_bSupportsD16 := True;
    end;
  end;
  g_bSupportsD32 := False;
  if SUCCEEDED(pD3D.CheckDeviceFormat(settings.AdapterOrdinal, settings.DeviceType,
                                      settings.AdapterFormat, D3DUSAGE_DEPTHSTENCIL,
                                      D3DRTYPE_SURFACE, D3DFMT_D32)) then
  begin
    if SUCCEEDED(pD3D.CheckDepthStencilMatch(settings.AdapterOrdinal, settings.DeviceType,
                                             settings.AdapterFormat, fmt,
                                             D3DFMT_D32)) then
    begin
      g_bSupportsD32 := True;
    end;
  end;
  g_bSupportsD24X8 := False;
  if SUCCEEDED(pD3D.CheckDeviceFormat(settings.AdapterOrdinal, settings.DeviceType,
                                      settings.AdapterFormat, D3DUSAGE_DEPTHSTENCIL,
                                      D3DRTYPE_SURFACE, D3DFMT_D24X8)) then
  begin
    if SUCCEEDED(pD3D.CheckDepthStencilMatch(settings.AdapterOrdinal, settings.DeviceType,
                                             settings.AdapterFormat, fmt,
                                             D3DFMT_D24X8)) then
    begin
      g_bSupportsD24X8 := True;
    end;
  end;

  dfmt := D3DFMT_UNKNOWN;
  if g_bSupportsD16 then dfmt := D3DFMT_D16
  else if g_bSupportsD32 then dfmt := D3DFMT_D32
  else if g_bSupportsD24X8 then dfmt := D3DFMT_D24X8;

  if (dfmt <> D3DFMT_UNKNOWN) then
  begin
    pd3dDevice.GetDeviceCaps(Caps);

    g_MaxMultiSampleType := D3DMULTISAMPLE_NONE;
    for imst := D3DMULTISAMPLE_2_SAMPLES to D3DMULTISAMPLE_16_SAMPLES do
    begin
      msQuality := 0;
      if SUCCEEDED(pD3D.CheckDeviceMultiSampleType(Caps.AdapterOrdinal,
                                                   Caps.DeviceType,
                                                   fmt,
                                                   settings.pp.Windowed,
                                                   imst, @msQuality)) then
      begin
        g_bUseMultiSample := True;
        g_MaxMultiSampleType := imst;
        if (msQuality > 0)
        then g_dwMultiSampleQuality := msQuality-1
        else g_dwMultiSampleQuality := msQuality;
      end;
    end;

    // Create the Multi-Sample floating point render target
    if g_bUseMultiSample then
    begin
      pBackBufferDesc := DXUTGetBackBufferSurfaceDesc;
      Result := g_pd3dDevice.CreateRenderTarget(pBackBufferDesc.Width, pBackBufferDesc.Height,
                                                fmt,
                                                g_MaxMultiSampleType, g_dwMultiSampleQuality,
                                                False, g_pMSRT, nil);
      if FAILED(Result) then
        g_bUseMultiSample := False
      else
      begin
        Result := g_pd3dDevice.CreateDepthStencilSurface(pBackBufferDesc.Width, pBackBufferDesc.Height,
                                                         dfmt,
                                                         g_MaxMultiSampleType, g_dwMultiSampleQuality,
                                                         True, g_pMSDS, nil);
        if FAILED(Result) then
        begin
          g_bUseMultiSample := False;
          SAFE_RELEASE(g_pMSRT);
        end;
      end;
    end;
  end;

  // For each scale stage, create a texture to hold the intermediate results
  // of the luminance calculation
  nSampleLen := 1;
  for t := 0 to NUM_TONEMAP_TEXTURES - 1 do
  begin
    fmt := D3DFMT_UNKNOWN;
    case g_eEncodingMode of
      FP16: fmt := D3DFMT_R16F;
      FP32: fmt := D3DFMT_R32F;
      RGBE8: fmt := D3DFMT_A8R8G8B8;
      RGB16: fmt := D3DFMT_A16B16G16R16;
    end;

    Result := pd3dDevice.CreateTexture(nSampleLen, nSampleLen, 1, D3DUSAGE_RENDERTARGET,
                                       fmt, D3DPOOL_DEFAULT, g_apTexToneMap[t], nil);
    if Failed(Result) then Exit;

    nSampleLen := nSampleLen * 3;
  end;

  // Create the temporary blooming effect textures
  for t := 0 to NUM_BLOOM_TEXTURES - 1 do
  begin
    Result := pd3dDevice.CreateTexture(pBackBufferSurfaceDesc.Width div 8, pBackBufferSurfaceDesc.Height div 8,
                                       1, D3DUSAGE_RENDERTARGET, D3DFMT_A8R8G8B8,
                                       D3DPOOL_DEFAULT, g_apTexBloom[t], nil);
    if Failed(Result) then Exit;
  end;

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);

  g_SampleUI.SetLocation(pBackBufferSurfaceDesc.Width - 150, pBackBufferSurfaceDesc.Height - 150);
  g_SampleUI.SetSize(150, 110);

  pCheckBox := g_SampleUI.GetCheckBox(IDC_BLOOM);
  pCheckBox.Checked := g_bBloom;

  pComboBox := g_SampleUI.GetComboBox(IDC_ENCODING_MODE);
  pComboBox.SetSelectedByData(Pointer(g_eEncodingMode));

  pComboBox := g_SampleUI.GetComboBox(IDC_RENDER_MODE);
  pComboBox.SetSelectedByData(Pointer(g_eRenderMode));

  // Setup the camera's projection parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI/4, fAspectRatio, 0.1, 5000.0);
  g_Camera.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);

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
  g_pEffect.SetValue('g_vEyePt', g_Camera.GetEyePt, SizeOf(TD3DXVector3));
end;


//--------------------------------------------------------------------------------------
// This callback function will be called at the end of every frame to perform all the
// rendering calls for the scene, and it will also be called if the window needs to be
// repainted. After this function has returned, DXUT will call 
// IDirect3DDevice9::Present to display the contents of the next buffer in the swap chain
//--------------------------------------------------------------------------------------
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  pSurfBackBuffer: IDirect3DSurface9;
  pSurfDS: IDirect3DSurface9;
  pSurfRenderTarget: IDirect3DSurface9;
  mWorldViewProj: TD3DXMatrixA16;
  iPass: Integer;
  uiNumPasses: LongWord;
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  pd3dDevice.GetRenderTarget(0, pSurfBackBuffer);
  pd3dDevice.GetDepthStencilSurface(pSurfDS);
  g_pTexRender.GetSurfaceLevel(0, pSurfRenderTarget);

  // Setup the HDR render target
  if g_bUseMultiSample then
  begin
    pd3dDevice.SetRenderTarget(0, g_pMSRT);
    pd3dDevice.SetDepthStencilSurface( g_pMSDS);
  end else
  begin
    pd3dDevice.SetRenderTarget(0, pSurfRenderTarget);
  end;

  // Clear the render target
  pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, $000000FF, 1.0, 0);

  // Update matrices
  D3DXMatrixMultiply(mWorldViewProj, g_Camera.GetViewMatrix^, g_Camera.GetProjMatrix^);
  g_pEffect.SetMatrix('g_mWorldViewProj', mWorldViewProj);

  // For the first pass we'll draw the screen to the full screen render target
  // and to update the velocity render target with the velocity of each pixel
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    // Draw the skybox
    g_aSkybox[g_eEncodingMode].Render(mWorldViewProj);

    RenderModel;

    // If using floating point multi sampling, stretchrect to the rendertarget
    if g_bUseMultiSample then
    begin
      pd3dDevice.StretchRect(g_pMSRT, nil, pSurfRenderTarget, nil, D3DTEXF_NONE);
      pd3dDevice.SetRenderTarget(0, pSurfRenderTarget);
      pd3dDevice.SetDepthStencilSurface(pSurfDS);
      pd3dDevice.Clear(0, nil, D3DCLEAR_ZBUFFER, 0, 1.0, 0);
    end;

    MeasureLuminance;
    BrightPassFilter;

    if g_bBloom then RenderBloom;

    //---------------------------------------------------------------------
    // Final pass
    pd3dDevice.SetRenderTarget(0, pSurfBackBuffer);
    pd3dDevice.SetTexture(0, g_pTexRender);
    pd3dDevice.SetTexture(1, g_apTexToneMap[0]);
    if g_bBloom then pd3dDevice.SetTexture(2, g_apTexBloom[0])
    else pd3dDevice.SetTexture(2, nil);

    pd3dDevice.SetSamplerState(2, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
    pd3dDevice.SetSamplerState(2, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);

    case g_eRenderMode of
      DECODED:       g_pEffect.SetTechnique(g_pCurTechnique.FinalPass);
      RGB_ENCODED:   g_pEffect.SetTechnique('FinalPassEncoded_RGB');
      ALPHA_ENCODED: g_pEffect.SetTechnique('FinalPassEncoded_A');
    end;

    g_pEffect._Begin(@uiNumPasses, 0);

    for iPass:= 0 to uiNumPasses - 1 do
    begin
      g_pEffect.BeginPass(iPass);
      DrawFullScreenQuad;
      g_pEffect.EndPass;
    end;

    g_pEffect._End;
    pd3dDevice.SetTexture(0, nil);
    pd3dDevice.SetTexture(1, nil);
    pd3dDevice.SetTexture(2, nil);

    if g_bShowText then RenderText(fTime);

    g_HUD.OnRender(fElapsedTime);
    g_SampleUI.OnRender(fElapsedTime);

    pd3dDevice.EndScene;
  end;

  pSurfRenderTarget := nil;
  pSurfBackBuffer := nil;
  pSurfDS := nil;
end;


//--------------------------------------------------------------------------------------
// Render the help and statistics text. This function uses the ID3DXFont interface for
// efficient text rendering.
//--------------------------------------------------------------------------------------
procedure RenderText(fTime: Double);
var
  txtHelper: CDXUTTextHelper;
  pd3dsdBackBuffer: PD3DSurfaceDesc;
const
  ENCODING_MODE_NAMES: array[TEncodingMode] of PWideChar =
  (
    '16-Bit floating-point (FP16)',
    '32-Bit floating-point (FP32)',
    '16-Bit integer (RGB16)',
    '8-Bit integer w/ shared exponent (RGBE8)'
  );

  RENDER_MODE_NAMES: array[TRenderMode] of PWideChar =
  (
    'Decoded scene',
    'RGB channels of encoded textures',
    'Alpha channel of encoded textures'
  );
begin
  // The helper object simply helps keep track of text position, and color
  // and then it calls pFont->DrawText( m_pSprite, strMsg, -1, &rc, DT_NOCLIP, m_clr );
  // If NULL is passed in as the sprite object, then it will work fine however the
  // pFont->DrawText() will not be batched together.  Batching calls will improves perf.
  // TODO: Add sprite
  txtHelper := CDXUTTextHelper.Create(g_pFont, nil, 15);

  // Output statistics
  txtHelper._Begin;
  txtHelper.SetInsertionPos(2, 0);
  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));
  txtHelper.DrawTextLine(DXUTGetFrameStats);
  txtHelper.DrawTextLine(DXUTGetDeviceStats);

  txtHelper.SetForegroundColor(D3DXColor( 0.90, 0.90, 1.0, 1.0));
  txtHelper.DrawFormattedTextLine(ENCODING_MODE_NAMES[g_eEncodingMode], []);
  txtHelper.DrawFormattedTextLine(RENDER_MODE_NAMES[g_eRenderMode], []);

  if g_bUseMultiSample then
  begin
    txtHelper.DrawTextLine('Using MultiSample Render Target');
    txtHelper.DrawFormattedTextLine('Number of Samples: %d', [Integer(g_MaxMultiSampleType)]);
    txtHelper.DrawFormattedTextLine('Quality: %d', [g_dwMultiSampleQuality]);
  end;

  // Draw help
  if g_bShowHelp then
  begin
    pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
    txtHelper.SetInsertionPos(2, pd3dsdBackBuffer.Height-15*6);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
    txtHelper.DrawTextLine('Controls:');

    txtHelper.SetInsertionPos(20, pd3dsdBackBuffer.Height-15*5);
    txtHelper.DrawTextLine('Rotate model: Left mouse button'#10 +
                           'Rotate camera: Right mouse button'#10 +
                           'Zoom camera: Mouse wheel scroll'#10 +
                           'Quit: ESC');

    txtHelper.SetInsertionPos(250, pd3dsdBackBuffer.Height-15*5);
    txtHelper.DrawTextLine('Cycle encoding: E'#10 +
                           'Cycle render mode: R'#10 +
                           'Toggle bloom: B'#10 +
                           'Hide text: T'#10);

    txtHelper.SetInsertionPos(410, pd3dsdBackBuffer.Height-15*5);
    txtHelper.DrawTextLine('Hide help: F1'#10 +
                           'Change Device: F2'#10 +
                           'Toggle HAL/REF: F3'#10 +
                           'View readme: F9'#10);
  end else
  begin
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
      Ord('T'): g_bShowText := not g_bShowText;
    end;
  end;
end;


//--------------------------------------------------------------------------------------
// Handles the GUI events
//--------------------------------------------------------------------------------------
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
var
  pComboBox: CDXUTComboBox;
  pCheckBox: CDXUTCheckBox;
  pBackBufDesc: PD3DSurfaceDesc;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;

    IDC_BLOOM: g_bBloom := not g_bBloom;

    IDC_RENDER_MODE:
    begin
      pComboBox := CDXUTComboBox(pControl);
      g_eRenderMode := TRenderMode({PtrToInt}(pComboBox.GetSelectedData));
    end;

    IDC_ENCODING_MODE:
    begin
      pComboBox := CDXUTComboBox(pControl);
      g_eEncodingMode := TEncodingMode({PtrToInt}(pComboBox.GetSelectedData));
      g_pCurTechnique := @g_aTechHandles[ g_eEncodingMode ];

      // Refresh resources
      pBackBufDesc := DXUTGetBackBufferSurfaceDesc;
      OnLostDevice(nil);
      OnResetDevice(g_pd3dDevice, pBackBufDesc^, nil);
    end;
  end;

  // Update the bloom checkbox based on new state
  pCheckBox := g_SampleUI.GetCheckBox(IDC_BLOOM);
  pCheckBox.Enabled := (g_eRenderMode = DECODED);
  pCheckBox.Checked := (g_eRenderMode = DECODED) and g_bBloom;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has
// entered a lost state and before IDirect3DDevice9::Reset is called. Resources created
// in the OnResetDevice callback should be released here, which generally includes all
// D3DPOOL_DEFAULT resources. See the "Lost Devices" section of the documentation for
// information about lost devices.
//--------------------------------------------------------------------------------------
procedure OnLostDevice; stdcall;
var
  i: TEncodingMode;
  j: Integer;
begin
  g_DialogResourceManager.OnLostDevice;
  g_SettingsDlg.OnLostDevice;
  for i:= Low(i) to High(i) do g_aSkybox[i].OnLostDevice;

  if Assigned(g_pFont) then g_pFont.OnLostDevice;
  if Assigned(g_pEffect) then g_pEffect.OnLostDevice;

  g_pMSRT := nil;
  g_pMSDS := nil;

  g_pTexRender := nil;
  g_pTexBrightPass := nil;

  for j:= 0 to NUM_TONEMAP_TEXTURES - 1 do g_apTexToneMap[j] := nil;
  for j:= 0 to NUM_BLOOM_TEXTURES   - 1 do g_apTexBloom[j] := nil;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has
// been destroyed, which generally happens as a result of application termination or
// windowed/full screen toggles. Resources created in the OnCreateDevice callback
// should be released here, which generally includes all D3DPOOL_MANAGED resources.
//--------------------------------------------------------------------------------------
procedure OnDestroyDevice; stdcall;
var
  i: TEncodingMode;
begin
  g_DialogResourceManager.OnDestroyDevice;
  g_SettingsDlg.OnDestroyDevice;
  for i:= Low(i) to High(i) do g_aSkybox[i].OnDestroyDevice;

  g_pFont := nil;
  g_pEffect := nil;
  g_pMesh := nil;

  g_pd3dDevice:= nil;
end;


//--------------------------------------------------------------------------------------
function GaussianDistribution(x, y, rho: Single): Single;{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}
var
  g: Single;
begin
  g := 1.0 / Sqrt(2.0 * D3DX_PI * rho * rho);
  g := g * Exp(-(x*x + y*y)/(2*rho*rho));

  Result:= g;
end;


//--------------------------------------------------------------------------------------
function log2_ceiling(val: Single): Integer;{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}
var
  iMax, iMin, iMiddle: Integer;
begin
  iMax := 256;
  iMin := 0;

  while (iMax - iMin > 1) do
  begin
    iMiddle := (iMax + iMin) div 2;

    if (val > g_aPowsOfTwo[iMiddle]) then iMin := iMiddle
    else iMax := iMiddle;
  end;

  Result:= iMax - 128;
end;


//--------------------------------------------------------------------------------------
procedure EncodeRGBE8(pSrc: PD3DXFloat16; out ppDest: PByte);{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}
var
  r, g, b: Single;
  maxComponent: Single;
  nExp: Integer;
  fDivisor: Single;
  pDestColor: PD3DColor;
begin
  r := D3DXFloat16ToFloat((pSrc{+0})^);
  g := D3DXFloat16ToFloat(PD3DXFloat16(PWideChar(pSrc)+1)^);
  b := D3DXFloat16ToFloat(PD3DXFloat16(PWideChar(pSrc)+2)^);

  // Determine the largest color component
  maxComponent := max(max(r, g), b);

  // Round to the nearest integer exponent
  nExp := log2_ceiling(maxComponent);

  // Divide the components by the shared exponent
  fDivisor := g_aPowsOfTwo[ nExp+128 ];

  r := r / fDivisor;
  g := g / fDivisor;
  b := b / fDivisor;

  // Constrain the color components
  r := max(0, min(1, r));
  g := max(0, min(1, g));
  b := max(0, min(1, b));

  // Store the shared exponent in the alpha channel
  pDestColor := PD3DColor(ppDest);
  pDestColor^ := D3DCOLOR_RGBA(Trunc(r*255), Trunc(g*255), Trunc(b*255), nExp+128);
  Inc(ppDest, SizeOf(TD3DColor));
end;


//--------------------------------------------------------------------------------------
procedure EncodeRGB16(pSrc: PD3DXFloat16; out ppDest: PByte);{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}
var
  r, g, b: Single;
  pDestColor: PWord;
begin
  r := D3DXFloat16ToFloat((pSrc{+0})^);
  g := D3DXFloat16ToFloat(PD3DXFloat16(PWideChar(pSrc)+1)^);
  b := D3DXFloat16ToFloat(PD3DXFloat16(PWideChar(pSrc)+2)^);

  // Divide the components by the multiplier
  r := r / RGB16_MAX;
  g := g / RGB16_MAX;
  b := b / RGB16_MAX;

  // Constrain the color components
  r := max( 0, min(1, r));
  g := max( 0, min(1, g));
  b := max( 0, min(1, b));

  // Store
  pDestColor := PWord(ppDest);
  pDestColor^ := Trunc(r*65535); Inc(pDestColor);
  pDestColor^ := Trunc(g*65535); Inc(pDestColor);
  pDestColor^ := Trunc(b*65535); //Inc(pDestColor);

  Inc(ppDest, SizeOf(Int64));
end;


//-----------------------------------------------------------------------------
// Name: RetrieveTechHandles()
// Desc:
//-----------------------------------------------------------------------------
function RetrieveTechHandles: HRESULT;
const
  modes: array[TEncodingMode] of PChar = ('FP16', 'FP16', 'RGB16', 'RGBE8');
  techniques: array[0..4] of PChar = ('Scene', 'DownScale2x2_Lum', 'DownScale3x3', 'DownScale3x3_BrightPass', 'FinalPass');
var
  dwNumTechniques: DWORD;
  str: String;
  pHandle: PD3DXHandle;
  m: TEncodingMode;
  t: LongWord;
begin
  dwNumTechniques := SizeOf(TTechHandles) div SizeOf(TD3DXHandle);
  pHandle := PD3DXHandle(@g_aTechHandles);

  for m := Low(m) to High(m) do
  begin
    for t := 0 to dwNumTechniques - 1 do
    begin
      str:= Format('%s_%s', [techniques[t], modes[m]]);
      pHandle^ := g_pEffect.GetTechniqueByName(PAnsiChar(str));
      Inc(pHandle);
    end;
  end;

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: LoadMesh()
// Desc:
//-----------------------------------------------------------------------------
function LoadMesh(strFileName: WideString; out ppMesh: ID3DXMesh): HRESULT; overload;
var
  pMesh: ID3DXMesh;
  str: array[0..MAX_PATH-1] of WideChar;
  rgdwAdjacency: PDWORD;
  pTempMesh: ID3DXMesh;
begin
  DXUTFindDXSDKMediaFile(str, MAX_PATH, PWideChar(strFileName));
  Result := D3DXLoadMeshFromXW(str, D3DXMESH_MANAGED, g_pd3dDevice, nil, nil, nil, nil, pMesh);
  if FAILED(Result) or (pMesh = nil) then Exit;

  // Make sure there are normals which are required for lighting
  if (pMesh.GetFVF and D3DFVF_NORMAL = 0) then
  begin
    Result := pMesh.CloneMeshFVF(pMesh.GetOptions,
                                 pMesh.GetFVF or D3DFVF_NORMAL,
                                 g_pd3dDevice, pTempMesh);
    if FAILED(Result) then Exit;

    D3DXComputeNormals(pTempMesh, nil);

    pMesh := nil;
    pMesh := pTempMesh;
  end;

  // Optimze the mesh to make it fast for the user's graphics card
  try
    GetMem(rgdwAdjacency, SizeOf(DWORD)*pMesh.GetNumFaces*3);
  except
    Result:= E_OUTOFMEMORY;
    Exit;
  end;
  V(pMesh.GenerateAdjacency(1e-6, rgdwAdjacency));
  pMesh.OptimizeInplace(D3DXMESHOPT_VERTEXCACHE, rgdwAdjacency, nil, nil, nil);
  FreeMem(rgdwAdjacency);

  ppMesh := pMesh;

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: MeasureLuminance()
// Desc: Measure the average log luminance in the scene.
//-----------------------------------------------------------------------------
function MeasureLuminance: HRESULT;
var
  uiNumPasses: LongWord;
  iPass: Integer;
  avSampleOffsets: array[0..15] of TD3DXVector2;
  pTexSrc: IDirect3DTexture9;
  pTexDest: IDirect3DTexture9;
  pSurfDest: IDirect3DSurface9;
  descSrc: TD3DSurfaceDesc;
  descDest: TD3DSurfaceDesc;
  pd3dDevice: IDirect3DDevice9;
  i: Integer;
  desc: TD3DSurfaceDesc;
begin
  //-------------------------------------------------------------------------
  // Initial sampling pass to convert the image to the log of the grayscale
  //-------------------------------------------------------------------------
  pTexSrc := g_pTexRender;
  pTexDest := g_apTexToneMap[NUM_TONEMAP_TEXTURES-1];

  pTexSrc.GetLevelDesc(0, descSrc);
  pTexDest.GetLevelDesc(0, descDest);

  GetSampleOffsets_DownScale2x2_Lum(descSrc.Width, descSrc.Height, descDest.Width, descDest.Height, avSampleOffsets);

  g_pEffect.SetValue('g_avSampleOffsets', @avSampleOffsets, SizeOf(avSampleOffsets));
  g_pEffect.SetTechnique(g_pCurTechnique.DownScale2x2_Lum);

  Result := pTexDest.GetSurfaceLevel(0, pSurfDest);
  if FAILED(Result) then Exit;

  pd3dDevice := DXUTGetD3DDevice;

  pd3dDevice.SetRenderTarget(0, pSurfDest);
  pd3dDevice.SetTexture(0, pTexSrc);
  pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_POINT);
  pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);

  Result := g_pEffect._Begin(@uiNumPasses, 0);
  if FAILED(Result) then Exit;

  for iPass := 0 to uiNumPasses - 1 do
  begin
    g_pEffect.BeginPass(iPass);
    // Draw a fullscreen quad to sample the RT
    DrawFullScreenQuad;
    g_pEffect.EndPass;
  end;

  g_pEffect._End;
  pd3dDevice.SetTexture(0, nil);

  pSurfDest := nil;

  //-------------------------------------------------------------------------
  // Iterate through the remaining tone map textures
  //------------------------------------------------------------------------- 
  for i := NUM_TONEMAP_TEXTURES-1 downto 1 do
  begin
    // Cycle the textures
    pTexSrc := g_apTexToneMap[i];
    pTexDest := g_apTexToneMap[i-1];

    Result := pTexDest.GetSurfaceLevel(0, pSurfDest);
    if FAILED(Result) then Exit;

    pTexSrc.GetLevelDesc(0, desc);
    GetSampleOffsets_DownScale3x3(desc.Width, desc.Height, avSampleOffsets);

    g_pEffect.SetValue('g_avSampleOffsets', @avSampleOffsets, SizeOf(avSampleOffsets));
    g_pEffect.SetTechnique(g_pCurTechnique.DownScale3x3);

    pd3dDevice.SetRenderTarget(0, pSurfDest);
    pd3dDevice.SetTexture(0, pTexSrc);
    pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_POINT);
    pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);

    Result := g_pEffect._Begin(@uiNumPasses, 0);
    if FAILED(Result) then Exit;

    for iPass := 0 to uiNumPasses - 1 do
    begin
      g_pEffect.BeginPass(iPass);
      // Draw a fullscreen quad to sample the RT
      DrawFullScreenQuad;
      g_pEffect.EndPass;
    end;

    g_pEffect._End;
    pd3dDevice.SetTexture(0, nil);

    pSurfDest := nil;
  end;

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: GetSampleOffsets_DownScale3x3
// Desc: Get the texture coordinate offsets to be used inside the DownScale3x3
//       pixel shader.
//-----------------------------------------------------------------------------
function GetSampleOffsets_DownScale3x3(dwWidth, dwHeight: DWORD;
  var avSampleOffsets: array of TD3DXVector2): HRESULT;
var
  tU, tV: Single;
  index: Integer;
  x, y: Integer;
begin
  tU := 1.0 / dwWidth;
  tV := 1.0 / dwHeight;

  // Sample from the 9 surrounding points.
  index := 0;
  for y := -1 to 1 do
    for x := -1 to 1 do
    begin
      avSampleOffsets[ index ].x := x * tU;
      avSampleOffsets[ index ].y := y * tV;
      Inc(index);
    end;

  Result:= S_OK;
end;

//-----------------------------------------------------------------------------
// Name: GetSampleOffsets_DownScale2x2_Lum
// Desc: Get the texture coordinate offsets to be used inside the DownScale2x2_Lum
//       pixel shader.
//-----------------------------------------------------------------------------
function GetSampleOffsets_DownScale2x2_Lum(dwSrcWidth, dwSrcHeight, dwDestWidth, dwDestHeight: DWORD;
  var avSampleOffsets: array of TD3DXVector2): HRESULT;
var
  tU, tV, deltaU, deltaV: Single;
  index: Integer;
  x, y: Integer;
begin
  tU := 1.0 / dwSrcWidth;
  tV := 1.0 / dwSrcHeight;

  deltaU := dwSrcWidth / dwDestWidth / 2.0;
  deltaV := dwSrcHeight / dwDestHeight / 2.0;

  // Sample from 4 surrounding points.
  index := 0;
  for y := 0 to 1 do
    for x := 0 to 1 do
    begin
      avSampleOffsets[ index ].x := (x - 0.5) * deltaU * tU;
      avSampleOffsets[ index ].y := (y - 0.5) * deltaV * tV;
      Inc(index);
    end;

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: GetSampleOffsets_Bloom()
// Desc:
//-----------------------------------------------------------------------------
function GetSampleOffsets_Bloom(dwD3DTexSize: DWORD; var afTexCoordOffset: array of Single;
  var avColorWeight: array of TD3DXVector4; fDeviation: Single; fMultiplier: Single = 1.0): HRESULT;
var
  i: Integer;
  tu: Single;
  weight: Single;
begin
  tu := 1.0 / dwD3DTexSize;

  // Fill the center texel
  weight := 1.0 * GaussianDistribution(0, 0, fDeviation);
  avColorWeight[0] := D3DXVector4(weight, weight, weight, 1.0);

  afTexCoordOffset[0] := 0.0;
    
  // Fill the right side
  for i := 1 to 7 do 
  begin
    weight := fMultiplier * GaussianDistribution(i, 0, fDeviation);
    afTexCoordOffset[i] := i * tu;

    avColorWeight[i] := D3DXVector4(weight, weight, weight, 1.0);
  end;

  // Copy to the left side
  for i := 8 to 14 do 
  begin
    avColorWeight[i] := avColorWeight[i-7];
    afTexCoordOffset[i] := -afTexCoordOffset[i-7];
  end;

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: RenderModel()
// Desc: Render the model
//-----------------------------------------------------------------------------
function RenderModel: HRESULT;
var
  mWorldViewProj: TD3DXMatrixA16;
  iPass: Integer;
  uiNumPasses: LongWord;
begin
  // Set the transforms
  D3DXMatrixMultiply(mWorldViewProj, g_Camera.GetWorldMatrix^, g_Camera.GetViewMatrix^);
  D3DXMatrixMultiply(mWorldViewProj, mWorldViewProj, g_Camera.GetProjMatrix^);
  g_pEffect.SetMatrix('g_mWorld', g_Camera.GetWorldMatrix^);
  g_pEffect.SetMatrix('g_mWorldViewProj', mWorldViewProj);

  // Draw the mesh
  g_pEffect.SetTechnique(g_pCurTechnique.Scene);
  g_pEffect.SetTexture('g_tCube', g_aSkybox[g_eEncodingMode].EnvironmentMap);

  Result := g_pEffect._Begin(@uiNumPasses, 0);
  if FAILED(Result) then Exit;

  for iPass:=0 to uiNumPasses - 1 do
  begin
    g_pEffect.BeginPass(iPass);
    g_pMesh.DrawSubset(0);
    g_pEffect.EndPass;
  end;

  g_pEffect._End;

  Result:= S_OK;
end;



//-----------------------------------------------------------------------------
// Name: BrightPassFilter
// Desc: Prepare for the bloom pass by removing dark information from the scene
//-----------------------------------------------------------------------------
function BrightPassFilter: HRESULT;
var
  pBackBufDesc: PD3DSurfaceDesc;
  avSampleOffsets: array[0..15] of TD3DXVector2;
  pSurfBrightPass: IDirect3DSurface9;
  iPass: Integer;
  uiNumPasses: LongWord;
begin
  pBackBufDesc := DXUTGetBackBufferSurfaceDesc;

  GetSampleOffsets_DownScale3x3(pBackBufDesc.Width div 2, pBackBufDesc.Height div 2, avSampleOffsets);

  g_pEffect.SetValue('g_avSampleOffsets', @avSampleOffsets, SizeOf(avSampleOffsets));

  Result := g_pTexBrightPass.GetSurfaceLevel(0, pSurfBrightPass);
  if FAILED(Result) then Exit;

  g_pEffect.SetTechnique(g_pCurTechnique.DownScale3x3_BrightPass);
  g_pd3dDevice.SetRenderTarget(0, pSurfBrightPass);
  g_pd3dDevice.SetTexture(0, g_pTexRender);
  g_pd3dDevice.SetTexture(1, g_apTexToneMap[0]);

  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);

  Result := g_pEffect._Begin(@uiNumPasses, 0);
  if FAILED(Result) then Exit;

  for iPass := 0 to uiNumPasses - 1 do
  begin
    g_pEffect.BeginPass(iPass);
    // Draw a fullscreen quad to sample the RT
    DrawFullScreenQuad;
    g_pEffect.EndPass;
  end;

  g_pEffect._End;
  g_pd3dDevice.SetTexture(0, nil);
  g_pd3dDevice.SetTexture(1, nil);

  pSurfBrightPass := nil;

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: RenderBloom()
// Desc: Render the blooming effect
//-----------------------------------------------------------------------------
function RenderBloom: HRESULT;
var
  iPass: Integer;
  uiPassCount: LongWord;
  i: Integer;
  avSampleOffsets: array[0..15] of TD3DXVector2;
  afSampleOffsets: array[0..15] of Single;
  avSampleWeights: array[0..15] of TD3DXVector4;
  pSurfDest: IDirect3DSurface9;
  desc: TD3DSurfaceDesc;
begin
  Result := g_apTexBloom[1].GetSurfaceLevel(0, pSurfDest);
  if FAILED(Result) then Exit;

  Result := g_pTexBrightPass.GetLevelDesc(0, desc);
  if FAILED(Result) then Exit;

  {Result := }GetSampleOffsets_Bloom(desc.Width, afSampleOffsets, avSampleWeights, 3.0, 1.25);
  for i := 0 to 15 do
    avSampleOffsets[i] := D3DXVector2(afSampleOffsets[i], 0.0);

  g_pEffect.SetTechnique('Bloom');
  g_pEffect.SetValue('g_avSampleOffsets', @avSampleOffsets, SizeOf(avSampleOffsets));
  g_pEffect.SetValue('g_avSampleWeights', @avSampleWeights, SizeOf(avSampleWeights));

  g_pd3dDevice.SetRenderTarget(0, pSurfDest);
  g_pd3dDevice.SetTexture(0, g_pTexBrightPass);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_POINT);


  g_pEffect._Begin(@uiPassCount, 0);
  for iPass := 0 to uiPassCount - 1 do
  begin
    g_pEffect.BeginPass(iPass);
    // Draw a fullscreen quad to sample the RT
    DrawFullScreenQuad;
    g_pEffect.EndPass;
  end;
  g_pEffect._End;
  g_pd3dDevice.SetTexture(0, nil);

  pSurfDest := nil;
  Result := g_apTexBloom[0].GetSurfaceLevel(0, pSurfDest);
  if FAILED(Result) then Exit;

  Result := GetSampleOffsets_Bloom(desc.Height, afSampleOffsets, avSampleWeights, 3.0, 1.25);
  for i:= 0 to 15 do
    avSampleOffsets[i] := D3DXVector2(0.0, afSampleOffsets[i]);

  g_pEffect.SetTechnique('Bloom');
  g_pEffect.SetValue('g_avSampleOffsets', @avSampleOffsets, SizeOf(avSampleOffsets));
  g_pEffect.SetValue('g_avSampleWeights', @avSampleWeights, SizeOf(avSampleWeights));

  g_pd3dDevice.SetRenderTarget(0, pSurfDest);
  g_pd3dDevice.SetTexture(0, g_apTexBloom[1]);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_POINT);


  g_pEffect._Begin(@uiPassCount, 0);

  for iPass := 0 to uiPassCount - 1 do
  begin
    g_pEffect.BeginPass(iPass);
    // Draw a fullscreen quad to sample the RT
    DrawFullScreenQuad;
    g_pEffect.EndPass;
  end;

  g_pEffect._End;
  g_pd3dDevice.SetTexture(0, nil);

  pSurfDest := nil;
end;


//-----------------------------------------------------------------------------
// Name: DrawFullScreenQuad
// Desc: Draw a properly aligned quad covering the entire render target
//-----------------------------------------------------------------------------
procedure DrawFullScreenQuad(fLeftU: Single = 0.0; fTopV: Single = 0.0; fRightU: Single = 1.0; fBottomV: Single = 1.0);
var
  dtdsdRT: TD3DSurfaceDesc;
  pSurfRT: IDirect3DSurface9;
  fWidth5: Single;
  fHeight5: Single;
  svQuad: array[0..3] of TScreenVertex; 
begin
  // Acquire render target width and height
  g_pd3dDevice.GetRenderTarget(0, pSurfRT);
  pSurfRT.GetDesc(dtdsdRT);
  pSurfRT := nil;

  // Ensure that we're directly mapping texels to pixels by offset by 0.5
  // For more info see the doc page titled "Directly Mapping Texels to Pixels"
  fWidth5 := dtdsdRT.Width - 0.5;
  fHeight5 := dtdsdRT.Height - 0.5;

  // Draw the quad

  svQuad[0].pos := D3DXVector4(-0.5, -0.5, 0.5, 1.0);
  svQuad[0].tex := D3DXVector2(fLeftU, fTopV);

  svQuad[1].pos := D3DXVector4(fWidth5, -0.5, 0.5, 1.0);
  svQuad[1].tex := D3DXVector2(fRightU, fTopV);

  svQuad[2].pos := D3DXVector4(-0.5, fHeight5, 0.5, 1.0);
  svQuad[2].tex := D3DXVector2(fLeftU, fBottomV);

  svQuad[3].pos := D3DXVector4(fWidth5, fHeight5, 0.5, 1.0);
  svQuad[3].tex := D3DXVector2(fRightU, fBottomV);

  g_pd3dDevice.SetRenderState(D3DRS_ZENABLE, iFalse);
  g_pd3dDevice.SetFVF(TScreenVertex_FVF);
  g_pd3dDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, svQuad, SizeOf(TScreenVertex));
  g_pd3dDevice.SetRenderState(D3DRS_ZENABLE, iTrue);
end;


//-----------------------------------------------------------------------------
// Name: CreateEncodedTexture
// Desc: Create a copy of the input floating-point texture with RGBE8 or RGB16
//       encoding
//-----------------------------------------------------------------------------
function CreateEncodedTexture(const pTexSrc: IDirect3DCubeTexture9; out ppTexDest: IDirect3DCubeTexture9; eTarget: TEncodingMode): HRESULT;
var
  desc: TD3DSurfaceDesc;
  fmt: TD3DFormat;
  iFace: TD3DCubemapFaces;
  rcSrc, rcDest: TD3DLockedRect;
  pSrcBytes, pDestBytes: PByte;
  x, y: LongWord;
  pSrc: PD3DXFloat16; 
  pDest: PByte;
begin
  Result:= pTexSrc.GetLevelDesc(0, desc);
  if V_Failed(Result) then Exit;

  // Create a texture with equal dimensions to store the encoded texture
  case eTarget of
    RGBE8: fmt := D3DFMT_A8R8G8B8;
    RGB16: fmt := D3DFMT_A16B16G16R16;
   else
    fmt := D3DFMT_UNKNOWN;
  end;

  Result:= g_pd3dDevice.CreateCubeTexture(desc.Width, 1, 0,
                                          fmt, D3DPOOL_MANAGED,
                                          ppTexDest, nil);
  if V_Failed(Result) then Exit;

  for iFace := Low(iFace) to High(iFace) do
  begin
    // Lock the source texture for reading
    Result:= pTexSrc.LockRect(iFace, 0, rcSrc, nil, D3DLOCK_READONLY);
    if V_Failed(Result) then Exit;

    // Lock the destination texture for writing
    Result:= ppTexDest.LockRect(iFace, 0, rcDest, nil, 0);
    if V_Failed(Result) then Exit;

    pSrcBytes := PByte(rcSrc.pBits);
    pDestBytes := PByte(rcDest.pBits);

    for y := 0 to desc.Height - 1 do
    begin
      pSrc := PD3DXFloat16(pSrcBytes);
      pDest := pDestBytes;

      for x := 0 to desc.Width - 1 do
      begin
        case eTarget of
          RGBE8: EncodeRGBE8(pSrc, pDest);
          RGB16: EncodeRGB16(pSrc, pDest);
        else
          Result:= E_FAIL;
          Exit;
        end;

        Inc(pSrc, 4);
      end;

      Inc(pSrcBytes, rcSrc.Pitch);
      Inc(pDestBytes, rcDest.Pitch);
    end;

    // Release the locks
    ppTexDest.UnlockRect(iFace, 0);
    pTexSrc.UnlockRect(iFace, 0);
  end;

  Result:= S_OK;
end;



procedure CreateCustomDXUTobjects;
var
  i: TEncodingMode;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera := CModelViewerCamera.Create;             // A model viewing camera
  g_HUD := CDXUTDialog.Create;                       // dialog for standard controls
  g_SampleUI := CDXUTDialog.Create;                  // dialog for sample specific controls

  for i:= Low(i) to High(i) do g_aSkybox[i]:= CSkybox.Create;
end;

procedure DestroyCustomDXUTobjects;
var
  i: TEncodingMode;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_Camera);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);

  for i:= Low(i) to High(i) do FreeAndNil(g_aSkybox[i]);
end;

end.

