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
 *  $Id: PixelMotionBlurUnit.pas,v 1.7 2007/02/05 22:21:11 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: PixelMotionBlur.cpp
//
// Starting point for new Direct3D applications
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit PixelMotionBlurUnit;

interface

uses
  Windows, Messages, SysUtils, Math, StrSafe, 
  DXTypes, Direct3D9, D3DX9, dxerr9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTMesh, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders


//-----------------------------------------------------------------------------
// Globals variables and definitions
//-----------------------------------------------------------------------------
const
  NUM_OBJECTS = 40;
  NUM_WALLS = 250;
  MOVESTYLE_DEFAULT = 0;

type
  TScreenVertex = packed record
    pos: TD3DXVector4;
    clr: DWORD;
    tex1: TD3DXVector2;
  end;

const
  TScreenVertex_FVF = D3DFVF_XYZRHW or D3DFVF_DIFFUSE or D3DFVF_TEX1;

type
  PObjectStruct = ^TObjectStruct;
  TObjectStruct = record
    g_vWorldPos: TD3DXVector3;
    g_mWorld: TD3DXMatrixA16;
    g_mWorldLast: TD3DXMatrixA16;
    g_pMesh: ID3DXMesh;
    g_pMeshTexture: IDirect3DTexture9;
  end;


  PRenderTargetSet = ^TRenderTargetSet;
  TRenderTargetSet = record
    pRT: array[0..1, 0..1] of IDirect3DSurface9;   // Two passes, two RTs
  end;


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont: ID3DXFont;              // Font for drawing text
  g_pTextSprite: ID3DXSprite;      // Sprite for batching draw text calls
  g_pEffect: ID3DXEffect;          // D3DX effect interface
  g_VelocityTexFormat: TD3DFormat; // Texture format for velocity textures
  g_Camera: CFirstPersonCamera;
  g_bShowHelp: Boolean = True;     // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg;  // Device settings dialog
  g_HUD: CDXUTDialog;              // dialog for standard controls
  g_SampleUI: CDXUTDialog;         // dialog for sample specific controls

  g_Vertex: array[0..3] of TScreenVertex;

  g_pMesh1: ID3DXMesh;
  g_pMeshTexture1: IDirect3DTexture9;
  g_pMesh2: ID3DXMesh;
  g_pMeshTexture2: IDirect3DTexture9;
  g_pMeshTexture3: IDirect3DTexture9;

  g_pFullScreenRenderTarget: IDirect3DTexture9;
  g_pFullScreenRenderTargetSurf: IDirect3DSurface9;

  g_pPixelVelocityTexture1: IDirect3DTexture9;
  g_pPixelVelocitySurf1: IDirect3DSurface9;
  g_pPixelVelocityTexture2: IDirect3DTexture9;
  g_pPixelVelocitySurf2: IDirect3DSurface9;

  g_pLastFrameVelocityTexture: IDirect3DTexture9;
  g_pLastFrameVelocitySurf: IDirect3DSurface9;
  g_pCurFrameVelocityTexture: IDirect3DTexture9;
  g_pCurFrameVelocitySurf: IDirect3DSurface9;

  g_fChangeTime: Single;
  g_bShowBlurFactor: Boolean;
  g_bShowUnblurred: Boolean;
  g_dwBackgroundColor: DWORD;

  g_fPixelBlurConst: Single;
  g_fObjectSpeed: Single;
  g_fCameraSpeed: Single;

  g_pScene1Object: array[0..NUM_OBJECTS-1] of PObjectStruct;
  g_pScene2Object: array[0..NUM_WALLS-1] of PObjectStruct;
  g_dwMoveSytle: DWORD;
  g_nSleepTime: Integer;
  g_mViewProjectionLast: TD3DXMatrix;
  g_nCurrentScene: Integer;

  g_hWorld: TD3DXHandle;
  g_hWorldLast: TD3DXHandle;
  g_hMeshTexture: TD3DXHandle;
  g_hWorldViewProjection: TD3DXHandle;
  g_hWorldViewProjectionLast: TD3DXHandle;
  g_hCurFrameVelocityTexture: TD3DXHandle;
  g_hLastFrameVelocityTexture: TD3DXHandle;
  g_hTechWorldWithVelocity: TD3DXHandle;
  g_hPostProcessMotionBlur: TD3DXHandle;

  g_nPasses: Integer = 0;           // Number of passes required to render
  g_nRtUsed: Integer = 0;           // Number of render targets used by each pass
  g_aRTSet: array[0..1] of TRenderTargetSet; // Two sets of render targets
  g_pCurFrameRTSet: PRenderTargetSet;        // Render target set for current frame
  g_pLastFrameRTSet: PRenderTargetSet;       // Render target set for last frame


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_CHANGE_SCENE        = 5;
  IDC_ENABLE_BLUR         = 6;
  IDC_FRAMERATE           = 7;
  IDC_FRAMERATE_STATIC    = 8;
  IDC_BLUR_FACTOR         = 9;
  IDC_BLUR_FACTOR_STATIC  = 10;
  IDC_OBJECT_SPEED        = 11;
  IDC_OBJECT_SPEED_STATIC = 12;
  IDC_CAMERA_SPEED        = 13;
  IDC_CAMERA_SPEED_STATIC = 14;


//--------------------------------------------------------------------------------------
// Forward declarations
//--------------------------------------------------------------------------------------
function IsDeviceAcceptable(const pCaps: TD3DCaps9; AdapterFormat, BackBufferFormat: TD3DFormat; bWindowed: Boolean; pUserContext: Pointer): Boolean; stdcall;
function ModifyDeviceSettings(var pDeviceSettings: TDXUTDeviceSettings; const pCaps: TD3DCaps9; pUserContext: Pointer): Boolean; stdcall;
function OnCreateDevice(const pd3dDevice: IDirect3DDevice9; const pBackBufferSurfaceDesc: TD3DSurfaceDesc; pUserContext: Pointer): HRESULT; stdcall;
function OnResetDevice(const pd3dDevice: IDirect3DDevice9; const pBackBufferSurfaceDesc: TD3DSurfaceDesc; pUserContext: Pointer): HRESULT; stdcall;
procedure OnFrameMove(const pd3dDevice: IDirect3DDevice9; dTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
function MsgProc(hWnd: HWND; uMsg: LongWord; wParam: WPARAM; lParam: LPARAM; out pbNoFurtherProcessing: Boolean; pUserContext: Pointer): LRESULT; stdcall;
procedure KeyboardProc(nChar: LongWord; bKeyDown, bAltDown: Boolean; pUserContext: Pointer); stdcall;
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
procedure OnLostDevice(pUserContext: Pointer); stdcall;
procedure OnDestroyDevice(pUserContext: Pointer); stdcall;

procedure InitApp;
function LoadMesh(const pd3dDevice: IDirect3DDevice9; wszName: PWideChar; out ppMesh: ID3DXMesh): HRESULT;
procedure RenderText;
procedure SetupFullscreenQuad(const pBackBufferSurfaceDesc: TD3DSurfaceDesc);

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;


implementation


//--------------------------------------------------------------------------------------
// Initialize the app
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  iObject: Integer;
  iY: Integer;
  sz: array[0..99] of WideChar; 
begin
  g_pFullScreenRenderTarget := nil;
  g_pFullScreenRenderTargetSurf := nil;
  g_pPixelVelocityTexture1 := nil;
  g_pPixelVelocitySurf1 := nil;
  g_pPixelVelocityTexture2 := nil;
  g_pPixelVelocitySurf2 := nil;
  g_pLastFrameVelocityTexture := nil;
  g_pCurFrameVelocityTexture := nil;
  g_pCurFrameVelocitySurf := nil;
  g_pLastFrameVelocitySurf := nil;
  g_pEffect := nil;
  g_nSleepTime := 0;
  g_fPixelBlurConst := 1.0;
  g_fObjectSpeed := 8.0;
  g_fCameraSpeed := 20.0;
  g_nCurrentScene := 1;

  g_fChangeTime := 0.0;
  g_dwMoveSytle := MOVESTYLE_DEFAULT;
  D3DXMatrixIdentity(g_mViewProjectionLast);

  g_hWorld := nil;
  g_hWorldLast := nil;
  g_hMeshTexture := nil;
  g_hWorldViewProjection := nil;
  g_hWorldViewProjectionLast := nil;
  g_hCurFrameVelocityTexture := nil;
  g_hLastFrameVelocityTexture := nil;
  g_hTechWorldWithVelocity := nil;
  g_hPostProcessMotionBlur := nil;

  g_pMesh1 := nil;
  g_pMeshTexture1 := nil;
  g_pMesh2 := nil;
  g_pMeshTexture2 := nil;
  g_pMeshTexture3 := nil;
  g_bShowBlurFactor := False;
  g_bShowUnblurred := False;
  g_bShowHelp := True;
  g_dwBackgroundColor := $00003F3F;

  for iObject := 0 to NUM_OBJECTS - 1 do
  begin
    New(g_pScene1Object[iObject]); //:= new OBJECT;
    ZeroMemory(g_pScene1Object[iObject], SizeOf(TObjectStruct));
  end;

  for iObject := 0 to NUM_WALLS - 1 do
  begin
    New(g_pScene2Object[iObject]); // = new OBJECT;
    ZeroMemory(g_pScene2Object[iObject], SizeOf(TObjectStruct));
  end;

  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_SampleUI.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent);
  iY := 10; g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 35, iY, 125, 22, VK_F2);

  g_SampleUI.SetCallback(OnGUIEvent); iY := 10;
  Inc(iY, 24); g_SampleUI.AddButton(IDC_CHANGE_SCENE, 'Change Scene', 35, iY, 125, 22);
  Inc(iY, 24); g_SampleUI.AddCheckBox(IDC_ENABLE_BLUR, 'Enable Blur', 35, iY, 125, 22, True);

  Inc(iY, 10);
  StringCchFormat(sz, 100, 'Sleep: %dms/frame', [g_nSleepTime]);
  Inc(iY, 24); g_SampleUI.AddStatic(IDC_FRAMERATE_STATIC, sz, 35, iY, 125, 22 );
  Inc(iY, 24); g_SampleUI.AddSlider(IDC_FRAMERATE, 50, iY, 100, 22, 0, 100, g_nSleepTime );

  Inc(iY, 10);
  StringCchFormat(sz, 100, 'Blur Factor: %0.2f', [g_fPixelBlurConst]);
  Inc(iY, 24); g_SampleUI.AddStatic(IDC_BLUR_FACTOR_STATIC, sz, 35, iY, 125, 22 );
  Inc(iY, 24); g_SampleUI.AddSlider(IDC_BLUR_FACTOR, 50, iY, 100, 22, 1, 200, Trunc(g_fPixelBlurConst*100.0));

  Inc(iY, 10);
  StringCchFormat(sz, 100, 'Object Speed: %0.2f', [g_fObjectSpeed]);
  Inc(iY, 24); g_SampleUI.AddStatic(IDC_OBJECT_SPEED_STATIC, sz, 35, iY, 125, 22 );
  Inc(iY, 24); g_SampleUI.AddSlider(IDC_OBJECT_SPEED, 50, iY, 100, 22, 0, 30, Trunc(g_fObjectSpeed));

  Inc(iY, 10);
  StringCchFormat(sz, 100, 'Camera Speed: %0.2f', [g_fCameraSpeed]);
  Inc(iY, 24); g_SampleUI.AddStatic(IDC_CAMERA_SPEED_STATIC, sz, 35, iY, 125, 22 );
  Inc(iY, 24); g_SampleUI.AddSlider(IDC_CAMERA_SPEED, 50, iY, 100, 22, 0, 100, Trunc(g_fCameraSpeed));
end;


//--------------------------------------------------------------------------------------
// Called during device initialization, this code checks the device for some
// minimum set of capabilities, and rejects those that don't pass by returning false.
//--------------------------------------------------------------------------------------
function IsDeviceAcceptable(const pCaps: TD3DCaps9; AdapterFormat, BackBufferFormat: TD3DFormat; bWindowed: Boolean; pUserContext: Pointer): Boolean; stdcall;
var
  pD3D: IDirect3D9; 
begin
  Result:= False;

  // Skip backbuffer formats that don't support alpha blending
  pD3D := DXUTGetD3DObject;
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                   AdapterFormat, D3DUSAGE_QUERY_POSTPIXELSHADER_BLENDING,
                   D3DRTYPE_TEXTURE, BackBufferFormat))
  then Exit;

  // No fallback, so need ps2.0
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2, 0)) then Exit;

  // No fallback, so need to support render target
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                   AdapterFormat, D3DUSAGE_RENDERTARGET,
                   D3DRTYPE_TEXTURE, BackBufferFormat)) then Exit;

  // No fallback, so need to support D3DFMT_G16R16F or D3DFMT_A16B16G16R16F render target
  if FAILED(pD3D.CheckDeviceFormat( pCaps.AdapterOrdinal, pCaps.DeviceType,
                   AdapterFormat, D3DUSAGE_RENDERTARGET,
                   D3DRTYPE_TEXTURE, D3DFMT_G16R16F)) then
  begin
    if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                     AdapterFormat, D3DUSAGE_RENDERTARGET,
                     D3DRTYPE_TEXTURE, D3DFMT_A16B16G16R16F))
    then Exit;
  end;

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
  Caps: TD3DCaps9;
  pD3D: IDirect3D9;
  DisplayMode: TD3DDisplayMode;

  str: array[0..MAX_PATH-1] of WideChar;
  dwShaderFlags: DWORD;
  iObject: Integer;

  vPos: TD3DXVector3;
  mRot: TD3DXMatrix;
  mPos: TD3DXMatrix;
  mScale: TD3DXMatrix;
  fAspectRatio: Single;
  vecEye: TD3DXVector3;
  vecAt: TD3DXVector3;
begin
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  // Query multiple RT setting and set the num of passes required
  pd3dDevice.GetDeviceCaps(Caps);
  if (Caps.NumSimultaneousRTs < 2) then
  begin
    g_nPasses := 2;
    g_nRtUsed := 1;
  end else
  begin
    g_nPasses := 1;
    g_nRtUsed := 2;
  end;

  // Determine which of D3DFMT_G16R16F or D3DFMT_A16B16G16R16F to use for velocity texture
  pd3dDevice.GetDirect3D(pD3D);
  pd3dDevice.GetDisplayMode(0, DisplayMode);

  if FAILED(pD3D.CheckDeviceFormat(Caps.AdapterOrdinal, Caps.DeviceType,
                   DisplayMode.Format, D3DUSAGE_RENDERTARGET,
                   D3DRTYPE_TEXTURE, D3DFMT_G16R16F))
  then g_VelocityTexFormat := D3DFMT_A16B16G16R16F
  else g_VelocityTexFormat := D3DFMT_G16R16F;

  pD3D := nil;

  // Initialize the font
  Result:= D3DXCreateFont(pd3dDevice, 15, 0, FW_BOLD, 1, FALSE, DEFAULT_CHARSET,
                          OUT_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE,
                          'Arial', g_pFont);
  if V_Failed(Result) then Exit;

  Result:= LoadMesh(pd3dDevice, 'misc\sphere.x', g_pMesh1);
  if V_Failed(Result) then Exit;
  Result:= LoadMesh(pd3dDevice, 'quad.x', g_pMesh2);
  if V_Failed(Result) then Exit;

  // Create the mesh texture from a file
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'earth\earth.bmp');
  if V_Failed(Result) then Exit;
  Result:= D3DXCreateTextureFromFileW(pd3dDevice, str, g_pMeshTexture1);
  if V_Failed(Result) then Exit;

  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'misc\env2.bmp');
  if V_Failed(Result) then Exit;
  Result:= D3DXCreateTextureFromFileW(pd3dDevice, str, g_pMeshTexture2);
  if V_Failed(Result) then Exit;

  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'misc\seafloor.bmp');
  if V_Failed(Result) then Exit;
  Result:= D3DXCreateTextureFromFileW(pd3dDevice, str, g_pMeshTexture3);
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
  dwShaderFlags := dwShaderFlags or D3DXSHADER_SKIPOPTIMIZATION or D3DXSHADER_DEBUG;
  {$ENDIF}
  {$IFDEF DEBUG_PS}
  dwShaderFlags := dwShaderFlags or D3DXSHADER_SKIPOPTIMIZATION or D3DXSHADER_DEBUG;
  {$ENDIF}

  // Read the D3DX effect file
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'PixelMotionBlur.fx');
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to 
  // they the .fx file failed to compile
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags,
                                     nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  for iObject:= 0 to NUM_OBJECTS - 1 do
  begin
    g_pScene1Object[iObject].g_pMesh := g_pMesh1;
    g_pScene1Object[iObject].g_pMeshTexture := g_pMeshTexture1;
  end;

  for iObject:= 0 to NUM_WALLS - 1 do
  begin
    g_pScene2Object[iObject].g_pMesh := g_pMesh2;

    if (iObject < NUM_WALLS/5*1) then
    begin
      g_pScene2Object[iObject].g_pMeshTexture := g_pMeshTexture3;

      // Center floor
      vPos.x := 0.0;
      vPos.y := 0.0;
      vPos.z := (iObject-NUM_WALLS/5*0) * 1.0 + 10.0;

      D3DXMatrixRotationX(mRot, -D3DX_PI/2.0);
      D3DXMatrixScaling(mScale, 1.0, 1.0, 1.0);
    end
    else if (iObject < NUM_WALLS/5*2) then
    begin
      g_pScene2Object[iObject].g_pMeshTexture := g_pMeshTexture3;

      // Right floor
      vPos.x := 1.0;
      vPos.y := 0.0;
      vPos.z := (iObject-NUM_WALLS/5*1) * 1.0 + 10.0;

      D3DXMatrixRotationX(mRot, -D3DX_PI/2.0);
      D3DXMatrixScaling(mScale, 1.0, 1.0, 1.0);
    end
    else if (iObject < NUM_WALLS/5*3) then
    begin
      g_pScene2Object[iObject].g_pMeshTexture := g_pMeshTexture3;

      // Left floor
      vPos.x := -1.0;
      vPos.y := 0.0;
      vPos.z := (iObject-NUM_WALLS/5*2) * 1.0 + 10.0;

      D3DXMatrixRotationX(mRot, -D3DX_PI/2.0);
      D3DXMatrixScaling(mScale, 1.0, 1.0, 1.0);
    end
    else if( iObject < NUM_WALLS/5*4) then
    begin
      g_pScene2Object[iObject].g_pMeshTexture := g_pMeshTexture2;

      // Right wall
      vPos.x := 1.5;
      vPos.y := 0.5;
      vPos.z := (iObject-NUM_WALLS/5*3) * 1.0 + 10.0;

      D3DXMatrixRotationY(mRot, -D3DX_PI/2.0);
      D3DXMatrixScaling(mScale, 1.0, 1.0, 1.0);
    end
    else if (iObject < NUM_WALLS/5*5) then
    begin
      g_pScene2Object[iObject].g_pMeshTexture := g_pMeshTexture2;

      // Left wall 
      vPos.x := -1.5;
      vPos.y := 0.5;
      vPos.z := (iObject-NUM_WALLS/5*4) * 1.0 + 10.0;

      D3DXMatrixRotationY(mRot, D3DX_PI/2.0);
      D3DXMatrixScaling(mScale, 1.0, 1.0, 1.0);
    end;

    // Update the current world matrix for this object
    D3DXMatrixTranslation(mPos, vPos.x, vPos.y, vPos.z);
    // g_pScene2Object[iObject].g_mWorld := mRot * mPos;
    D3DXMatrixMultiply(g_pScene2Object[iObject].g_mWorld, mRot, mPos);
    // g_pScene2Object[iObject].g_mWorld := mScale * g_pScene2Object[iObject].g_mWorld;
    D3DXMatrixMultiply(g_pScene2Object[iObject].g_mWorld, mScale, g_pScene2Object[iObject].g_mWorld);

    // The walls don't move so just copy the current world matrix
    g_pScene2Object[iObject].g_mWorldLast := g_pScene2Object[iObject].g_mWorld;
  end;

  // Setup the camera
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI/4, fAspectRatio, 1.0, 1000.0);

  vecEye := D3DXVector3(40.0, 0.0, -15.0);
  vecAt := D3DXVector3(4.0, 4.0, -15.0);
  g_Camera.SetViewParams(vecEye, vecAt);

  g_Camera.SetScalers(0.01, g_fCameraSpeed);

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// This function loads the mesh and ensures the mesh has normals; it also optimizes the
// mesh for the graphics card's vertex cache, which improves performance by organizing
// the internal triangle list for less cache misses.
//--------------------------------------------------------------------------------------
function LoadMesh(const pd3dDevice: IDirect3DDevice9; wszName: PWideChar; out ppMesh: ID3DXMesh): HRESULT;
var
  pMesh: ID3DXMesh;
  str: array[0..MAX_PATH-1] of WideChar;
  rgdwAdjacency: PDWORD;
  pTempMesh: ID3DXMesh;
begin
  // Load the mesh with D3DX and get back a ID3DXMesh*.  For this
  // sample we'll ignore the X file's embedded materials since we know
  // exactly the model we're loading.  See the mesh samples such as
  // "OptimizedMesh" for a more generic mesh loading example.
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, wszName);
  if V_Failed(Result) then Exit;

  Result:= D3DXLoadMeshFromXW(str, D3DXMESH_MANAGED, pd3dDevice, nil, nil, nil, nil, pMesh);
  if V_Failed(Result) then Exit;

  // Make sure there are normals which are required for lighting
  if (pMesh.GetFVF and D3DFVF_NORMAL = 0) then
  begin
    V(pMesh.CloneMeshFVF(pMesh.GetOptions,
                          pMesh.GetFVF or D3DFVF_NORMAL,
                          pd3dDevice, pTempMesh));
    V(D3DXComputeNormals(pTempMesh, nil));

    SAFE_RELEASE(pMesh);
    pMesh := pTempMesh;
  end;

  // Optimize the mesh for this graphics card's vertex cache 
  // so when rendering the mesh's triangle list the vertices will 
  // cache hit more often so it won't have to re-execute the vertex shader 
  // on those vertices so it will improve perf.
  try
    GetMem(rgdwAdjacency, SizeOf(DWORD)*pMesh.GetNumFaces*3);
  except
    Result:= E_OUTOFMEMORY;
    Exit;
  end;
  V(pMesh.GenerateAdjacency(1e-6, rgdwAdjacency));
  V(pMesh.OptimizeInplace(D3DXMESHOPT_VERTEXCACHE, rgdwAdjacency, nil, nil, nil));
  FreeMem(rgdwAdjacency);

  ppMesh := pMesh;

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
  colorWhite: TD3DXColor;
  colorBlack: TD3DXColor;
  colorAmbient: TD3DXColor;
  colorSpecular: TD3DXColor;
  desc: TD3DSurfaceDesc;
  fVelocityCapInPixels: Single;
  fVelocityCapNonHomogeneous: Single;
  fVelocityCapSqNonHomogeneous: Single;
  pOriginalRenderTarget: IDirect3DSurface9;
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

  // Create a sprite to help batch calls when drawing many lines of text
  Result:= D3DXCreateSprite(pd3dDevice, g_pTextSprite);
  if V_Failed(Result) then Exit;

  // Setup the camera's projection parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI/4, fAspectRatio, 0.1, 1000.0);

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation( pBackBufferSurfaceDesc.Width-170, pBackBufferSurfaceDesc.Height-350);
  g_SampleUI.SetSize(170, 300);

  // Create a A8R8G8B8 render target texture.  This will be used to render
  // the full screen and then rendered to the backbuffer using a quad.
  Result:= D3DXCreateTexture(pd3dDevice, pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height,
                             1, D3DUSAGE_RENDERTARGET, D3DFMT_A8R8G8B8,
                             D3DPOOL_DEFAULT, g_pFullScreenRenderTarget);
  if V_Failed(Result) then Exit;

  // Create two floating-point render targets with at least 2 channels.  These will be used to store
  // velocity of each pixel (one for the current frame, and one for last frame).
  Result:= D3DXCreateTexture(pd3dDevice, pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height,
                             1, D3DUSAGE_RENDERTARGET, g_VelocityTexFormat,
                             D3DPOOL_DEFAULT, g_pPixelVelocityTexture1);
  if V_Failed(Result) then Exit;
  Result:= D3DXCreateTexture(pd3dDevice, pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height,
                             1, D3DUSAGE_RENDERTARGET, g_VelocityTexFormat,
                             D3DPOOL_DEFAULT, g_pPixelVelocityTexture2);
  if V_Failed(Result) then Exit;

  // Store pointers to surfaces so we can call SetRenderTarget() later
  Result:= g_pFullScreenRenderTarget.GetSurfaceLevel(0, g_pFullScreenRenderTargetSurf);
  if V_Failed(Result) then Exit;
  Result:= g_pPixelVelocityTexture1.GetSurfaceLevel(0, g_pPixelVelocitySurf1);
  if V_Failed(Result) then Exit;
  Result:= g_pPixelVelocityTexture2.GetSurfaceLevel(0, g_pPixelVelocitySurf2);
  if V_Failed(Result) then Exit;

  // Setup render target sets
  if (1 = g_nPasses) then
  begin
    // Multiple RTs

    // First frame
    g_aRTSet[0].pRT[0][0] := g_pFullScreenRenderTargetSurf;
    g_aRTSet[0].pRT[0][1] := g_pPixelVelocitySurf1;
    g_aRTSet[0].pRT[1][0] := nil;  // 2nd pass is not needed
    g_aRTSet[0].pRT[1][1] := nil;  // 2nd pass is not needed

    // Second frame
    g_aRTSet[1].pRT[0][0] := g_pFullScreenRenderTargetSurf;
    g_aRTSet[1].pRT[0][1] := g_pPixelVelocitySurf2;
    g_aRTSet[1].pRT[1][0] := nil;  // 2nd pass is not needed
    g_aRTSet[1].pRT[1][1] := nil;  // 2nd pass is not needed
  end else
  begin
    // Single RT, multiple passes

    // First frame
    g_aRTSet[0].pRT[0][0] := g_pFullScreenRenderTargetSurf;
    g_aRTSet[0].pRT[0][1] := nil;  // 2nd RT is not needed
    g_aRTSet[0].pRT[1][0] := g_pPixelVelocitySurf1;
    g_aRTSet[0].pRT[1][1] := nil;  // 2nd RT is not needed

    // Second frame
    g_aRTSet[1].pRT[0][0] := g_pFullScreenRenderTargetSurf;
    g_aRTSet[1].pRT[0][1] := nil;  // 2nd RT is not needed
    g_aRTSet[1].pRT[1][0] := g_pPixelVelocitySurf2;
    g_aRTSet[1].pRT[1][1] := nil;  // 2nd RT is not needed
  end;

  // Setup the current & last pointers that are swapped every frame.
  g_pCurFrameVelocityTexture := g_pPixelVelocityTexture1;
  g_pLastFrameVelocityTexture := g_pPixelVelocityTexture2;
  g_pCurFrameVelocitySurf := g_pPixelVelocitySurf1;
  g_pLastFrameVelocitySurf := g_pPixelVelocitySurf2;
  g_pCurFrameRTSet := @g_aRTSet[0];
  g_pLastFrameRTSet := @g_aRTSet[1];

  SetupFullscreenQuad(pBackBufferSurfaceDesc);

  colorWhite := D3DXColor(1.0, 1.0, 1.0, 1.0);
  colorBlack := D3DXColor(0.0, 0.0, 0.0, 1.0);
  colorAmbient := D3DXColor(0.35, 0.35, 0.35, 0);
  colorSpecular := D3DXColor(0.5, 0.5, 0.5, 1.0);
  Result:= g_pEffect.SetVector('MaterialAmbientColor', PD3DXVECTOR4(@colorAmbient)^);
  if V_Failed(Result) then Exit;
  Result:= g_pEffect.SetVector('MaterialDiffuseColor', PD3DXVECTOR4(@colorWhite)^);
  if V_Failed(Result) then Exit;
  Result:= g_pEffect.SetTexture('RenderTargetTexture', g_pFullScreenRenderTarget);
  if V_Failed(Result) then Exit;

  Result:= g_pFullScreenRenderTargetSurf.GetDesc(desc);
  if V_Failed(Result) then Exit;
  Result:= g_pEffect.SetFloat('RenderTargetWidth', desc.Width);
  if V_Failed(Result) then Exit;
  Result:= g_pEffect.SetFloat('RenderTargetHeight', desc.Height);
  if V_Failed(Result) then Exit;

  // 12 is the number of samples in our post-process pass, so we don't want
  // pixel velocity of more than 12 pixels or else we'll see artifacts
  fVelocityCapInPixels := 3.0;
  fVelocityCapNonHomogeneous := fVelocityCapInPixels * 2 / pBackBufferSurfaceDesc.Width;
  fVelocityCapSqNonHomogeneous := fVelocityCapNonHomogeneous * fVelocityCapNonHomogeneous;

  Result:= g_pEffect.SetFloat('VelocityCapSq', fVelocityCapSqNonHomogeneous);
  if V_Failed(Result) then Exit;
  Result:= g_pEffect.SetFloat('ConvertToNonHomogeneous', 1.0 / pBackBufferSurfaceDesc.Width);
  if V_Failed(Result) then Exit;

  // Determine the technique to use when rendering world based on # of passes.
  if (1 = g_nPasses)
  then g_hTechWorldWithVelocity := g_pEffect.GetTechniqueByName('WorldWithVelocityMRT')
  else g_hTechWorldWithVelocity := g_pEffect.GetTechniqueByName('WorldWithVelocityTwoPasses');

  g_hPostProcessMotionBlur     := g_pEffect.GetTechniqueByName('PostProcessMotionBlur');
  g_hWorld                     := g_pEffect.GetParameterByName(nil, 'mWorld');
  g_hWorldLast                 := g_pEffect.GetParameterByName(nil, 'mWorldLast');
  g_hWorldViewProjection       := g_pEffect.GetParameterByName(nil, 'mWorldViewProjection');
  g_hWorldViewProjectionLast   := g_pEffect.GetParameterByName(nil, 'mWorldViewProjectionLast');
  g_hMeshTexture               := g_pEffect.GetParameterByName(nil, 'MeshTexture');
  g_hCurFrameVelocityTexture   := g_pEffect.GetParameterByName(nil, 'CurFrameVelocityTexture');
  g_hLastFrameVelocityTexture  := g_pEffect.GetParameterByName(nil, 'LastFrameVelocityTexture');

  // Turn off lighting since its done in the shaders
  Result:= pd3dDevice.SetRenderState(D3DRS_LIGHTING, iFalse);
  if V_Failed(Result) then Exit;

  // Save a pointer to the orignal render target to restore it later
  Result:= pd3dDevice.GetRenderTarget(0, pOriginalRenderTarget);
  if V_Failed(Result) then Exit;

  // Clear each RT
  Result:= pd3dDevice.SetRenderTarget(0, g_pFullScreenRenderTargetSurf);
  if V_Failed(Result) then Exit;
  Result:= pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET, $00000000, 1.0, 0);
  if V_Failed(Result) then Exit;
  Result:= pd3dDevice.SetRenderTarget(0, g_pLastFrameVelocitySurf);
  if V_Failed(Result) then Exit;
  Result:= pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET, $00000000, 1.0, 0);
  if V_Failed(Result) then Exit;
  Result:= pd3dDevice.SetRenderTarget(0, g_pCurFrameVelocitySurf);
  if V_Failed(Result) then Exit;
  Result:= pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET, $00000000, 1.0, 0);
  if V_Failed(Result) then Exit;

  // Restore the orignal RT
  Result:= pd3dDevice.SetRenderTarget(0, pOriginalRenderTarget);
  if V_Failed(Result) then Exit;

  pOriginalRenderTarget:= nil;

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: SetupFullscreenQuad()
// Desc: Sets up a full screen quad.  First we render to a fullscreen render 
//       target texture, and then we render that texture using this quad to 
//       apply a pixel shader on every pixel of the scene.
//-----------------------------------------------------------------------------
procedure SetupFullscreenQuad(const pBackBufferSurfaceDesc: TD3DSurfaceDesc);
var
  desc: TD3DSurfaceDesc;
  fWidth5, fHeight5, fTexWidth1, fTexHeight1: Single;
begin
  g_pFullScreenRenderTargetSurf.GetDesc(desc);

  // Ensure that we're directly mapping texels to pixels by offset by 0.5
  // For more info see the doc page titled "Directly Mapping Texels to Pixels"
  fWidth5  := pBackBufferSurfaceDesc.Width - 0.5;
  fHeight5 := pBackBufferSurfaceDesc.Height - 0.5;

  fTexWidth1  := pBackBufferSurfaceDesc.Width / desc.Width;
  fTexHeight1 := pBackBufferSurfaceDesc.Height / desc.Height;

  // Fill in the vertex values
  g_Vertex[0].pos := D3DXVector4(fWidth5, -0.5, 0.0, 1.0);
  g_Vertex[0].clr := D3DXColorToDWord(D3DXColor(0.5, 0.5, 0.5, 0.66666));
  g_Vertex[0].tex1 := D3DXVector2(fTexWidth1, 0.0);

  g_Vertex[1].pos := D3DXVector4(fWidth5, fHeight5, 0.0, 1.0);
  g_Vertex[1].clr := D3DXColorToDWord(D3DXColor(0.5, 0.5, 0.5, 0.66666));
  g_Vertex[1].tex1 := D3DXVector2(fTexWidth1, fTexHeight1);

  g_Vertex[2].pos := D3DXVector4(-0.5, -0.5, 0.0, 1.0);
  g_Vertex[2].clr := D3DXColorToDWord(D3DXColor(0.5, 0.5, 0.5, 0.66666));
  g_Vertex[2].tex1 := D3DXVector2(0.0, 0.0);

  g_Vertex[3].pos := D3DXVector4(-0.5, fHeight5, 0.0, 1.0);
  g_Vertex[3].clr := D3DXColorToDWord(D3DXColor(0.5, 0.5, 0.5, 0.66666));
  g_Vertex[3].tex1 := D3DXVector2(0.0, fTexHeight1);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called once at the beginning of every frame. This is the
// best location for your application to handle updates to the scene, but is not 
// intended to contain actual rendering calls, which should instead be placed in the 
// OnFrameRender callback.  
//--------------------------------------------------------------------------------------
procedure OnFrameMove(const pd3dDevice: IDirect3DDevice9; dTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  fTime: Single;
  iObject: Integer;
  fRadius: Single;
  vPos: TD3DXVector3;
begin
  fTime := dTime;

  // Update the camera's position based on user input
  g_Camera.FrameMove(fElapsedTime);

  if (g_nCurrentScene = 1) then
  begin
    // Move the objects around based on some simple function
    for iObject:= 0 to NUM_OBJECTS - 1 do
    begin
      fRadius := 7.0;
      if (iObject >= 30) and (iObject < 41) then
      begin
        vPos.x := Cos(g_fObjectSpeed*0.125*fTime + 2*D3DX_PI/10*(iObject-30)) * fRadius;
        vPos.y := 10.0;
        vPos.z := Sin(g_fObjectSpeed*0.125*fTime + 2*D3DX_PI/10*(iObject-30)) * fRadius - 25.0;
      end
      else if (iObject >= 20) and (iObject < 31) then
      begin
        vPos.x := Cos(g_fObjectSpeed*0.25*fTime + 2*D3DX_PI/10*(iObject-20)) * fRadius;
        vPos.y := 10.0;
        vPos.z := Sin(g_fObjectSpeed*0.25*fTime + 2*D3DX_PI/10*(iObject-20)) * fRadius - 5.0;
      end
      else if (iObject >= 10) and (iObject < 21) then
      begin
        vPos.x := Cos(g_fObjectSpeed*0.5*fTime + 2*D3DX_PI/10*(iObject-10)) * fRadius;
        vPos.y := 0.0;
        vPos.z := Sin(g_fObjectSpeed*0.5*fTime + 2*D3DX_PI/10*(iObject-10)) * fRadius - 25.0;
      end
      else
      begin
        vPos.x := Cos(g_fObjectSpeed*fTime + 2*D3DX_PI/10*iObject) * fRadius;
        vPos.y := 0.0;
        vPos.z := Sin(g_fObjectSpeed*fTime + 2*D3DX_PI/10*iObject) * fRadius - 5.0;
      end;

      g_pScene1Object[iObject].g_vWorldPos := vPos;

      // Store the last world matrix so that we can tell the effect file
      // what it was when we render this object
      g_pScene1Object[iObject].g_mWorldLast := g_pScene1Object[iObject].g_mWorld;

      // Update the current world matrix for this object
      D3DXMatrixTranslation(g_pScene1Object[iObject].g_mWorld,
                            g_pScene1Object[iObject].g_vWorldPos.x,
                            g_pScene1Object[iObject].g_vWorldPos.y,
                            g_pScene1Object[iObject].g_vWorldPos.z);
    end;
  end;

  if (g_nSleepTime > 0) then Sleep(g_nSleepTime);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called at the end of every frame to perform all the 
// rendering calls for the scene, and it will also be called if the window needs to be 
// repainted. After this function has returned, DXUT will call 
// IDirect3DDevice9::Present to display the contents of the next buffer in the swap chain
//--------------------------------------------------------------------------------------
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  pTempTex: IDirect3DTexture9;
  pTempSurf: IDirect3DSurface9;
  pTempRTSet: PRenderTargetSet;
  iObject: Integer;
  rt: Integer;

  apOriginalRenderTarget: array[0..1] of IDirect3DSurface9;
  mProj: TD3DXMatrixA16;
  mView: TD3DXMatrixA16;
  mViewProjection: TD3DXMatrixA16;
  mWorldViewProjection: TD3DXMatrixA16;
  mWorldViewProjectionLast: TD3DXMatrixA16;
  iPass, cPasses: LongWord;
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  // Swap the current frame's per-pixel velocity texture with
  // last frame's per-pixel velocity texture
  pTempTex := g_pCurFrameVelocityTexture;
  g_pCurFrameVelocityTexture := g_pLastFrameVelocityTexture;
  g_pLastFrameVelocityTexture := pTempTex;

  pTempSurf := g_pCurFrameVelocitySurf;
  g_pCurFrameVelocitySurf := g_pLastFrameVelocitySurf;
  g_pLastFrameVelocitySurf := pTempSurf;

  pTempRTSet := g_pCurFrameRTSet;
  g_pCurFrameRTSet := g_pLastFrameRTSet;
  g_pLastFrameRTSet := pTempRTSet;

  // Save a pointer to the current render target in the swap chain
  V(pd3dDevice.GetRenderTarget(0, apOriginalRenderTarget[0]));

  V(g_pEffect.SetFloat('PixelBlurConst', g_fPixelBlurConst));

  V(g_pEffect.SetTexture(g_hCurFrameVelocityTexture, g_pCurFrameVelocityTexture));
  V(g_pEffect.SetTexture(g_hLastFrameVelocityTexture, g_pLastFrameVelocityTexture));

  // Clear the velocity render target to 0
  V(pd3dDevice.SetRenderTarget(0, g_pCurFrameVelocitySurf));
  V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET, $00000000, 1.0, 0));

  // Clear the full screen render target to the background color
  V(pd3dDevice.SetRenderTarget(0, g_pFullScreenRenderTargetSurf));
  V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, g_dwBackgroundColor, 1.0, 0));

  // Turn on Z for this pass
  V(pd3dDevice.SetRenderState(D3DRS_ZENABLE, iTrue));

  // For the first pass we'll draw the screen to the full screen render target
  // and to update the velocity render target with the velocity of each pixel
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    // Set world drawing technique
    V(g_pEffect.SetTechnique(g_hTechWorldWithVelocity));

    // Get the projection & view matrix from the camera class
    mProj := g_Camera.GetProjMatrix^;
    mView := g_Camera.GetViewMatrix^;

    // mViewProjection := mView * mProj;
    D3DXMatrixMultiply(mViewProjection, mView, mProj);

    if (g_nCurrentScene = 1) then
    begin
      // For each object, tell the effect about the object's current world matrix
      // and its last frame's world matrix and render the object.
      // The vertex shader can then use both these matricies to calculate how
      // much each vertex has moved.  The pixel shader then interpolates this
      // vertex velocity for each pixel
      for iObject := 0 to NUM_OBJECTS - 1 do
      begin
        // mWorldViewProjection := g_pScene1Object[iObject].g_mWorld * mViewProjection;
        D3DXMatrixMultiply(mWorldViewProjection, g_pScene1Object[iObject].g_mWorld, mViewProjection);
        // mWorldViewProjectionLast := g_pScene1Object[iObject].g_mWorldLast * g_mViewProjectionLast;
        D3DXMatrixMultiply(mWorldViewProjectionLast, g_pScene1Object[iObject].g_mWorldLast, g_mViewProjectionLast);
    
        // Tell the effect where the camera is now
        V(g_pEffect.SetMatrix(g_hWorldViewProjection, mWorldViewProjection));
        V(g_pEffect.SetMatrix(g_hWorld, g_pScene1Object[iObject].g_mWorld));
    
        // Tell the effect where the camera was last frame
        V(g_pEffect.SetMatrix(g_hWorldViewProjectionLast, mWorldViewProjectionLast));
    
        // Tell the effect the current mesh's texture
        V(g_pEffect.SetTexture(g_hMeshTexture, g_pScene1Object[iObject].g_pMeshTexture));

        V(g_pEffect._Begin(@cPasses, 0));
        for iPass := 0 to cPasses - 1 do
        begin
          // Set the render targets here.  If multiple render targets are
          // supported, render target 1 is set to be the velocity surface.
          // If multiple render targets are not supported, the velocity
          // surface will be rendered in the 2nd pass.
          for rt := 0 to g_nRtUsed - 1 do
            V(pd3dDevice.SetRenderTarget(rt, g_pCurFrameRTSet.pRT[iPass][rt]));

          V(g_pEffect.BeginPass(iPass));
          V(g_pScene1Object[iObject].g_pMesh.DrawSubset(0));
          V(g_pEffect.EndPass);
        end;
        V(g_pEffect._End)
      end;
    end
    else if (g_nCurrentScene = 2) then
    begin
      for iObject := 0 to NUM_WALLS - 1 do
      begin
        // mWorldViewProjection := g_pScene2Object[iObject].g_mWorld * mViewProjection;
        D3DXMatrixMultiply(mWorldViewProjection, g_pScene2Object[iObject].g_mWorld, mViewProjection);
        // mWorldViewProjectionLast = g_pScene2Object[iObject]->g_mWorldLast * g_mViewProjectionLast;
        D3DXMatrixMultiply(mWorldViewProjectionLast, g_pScene2Object[iObject].g_mWorldLast, g_mViewProjectionLast);

        // Tell the effect where the camera is now
        V(g_pEffect.SetMatrix(g_hWorldViewProjection, mWorldViewProjection));
        V(g_pEffect.SetMatrix(g_hWorld, g_pScene2Object[iObject].g_mWorld));

        // Tell the effect where the camera was last frame
        V(g_pEffect.SetMatrix(g_hWorldViewProjectionLast, mWorldViewProjectionLast));

        // Tell the effect the current mesh's texture
        V(g_pEffect.SetTexture(g_hMeshTexture, g_pScene2Object[iObject].g_pMeshTexture));

        V(g_pEffect._Begin(@cPasses, 0));
        for iPass := 0 to cPasses - 1 do
        begin
          // Set the render targets here.  If multiple render targets are
          // supported, render target 1 is set to be the velocity surface.
          // If multiple render targets are not supported, the velocity
          // surface will be rendered in the 2nd pass.
          for rt := 0 to g_nRtUsed - 1 do
            V(pd3dDevice.SetRenderTarget(rt, g_pCurFrameRTSet.pRT[iPass][rt]));

          V(g_pEffect.BeginPass(iPass));
          V(g_pScene2Object[iObject].g_pMesh.DrawSubset(0));
          V(g_pEffect.EndPass);
        end;
        V(g_pEffect._End);
      end;
    end;

    V(pd3dDevice.EndScene);
  end;

  // Remember the current view projection matrix for next frame
  g_mViewProjectionLast := mViewProjection;

  // Now that we have the scene rendered into g_pFullScreenRenderTargetSurf
  // and the pixel velocity rendered into g_pCurFrameVelocitySurf 
  // we can do a final pass to render this into the backbuffer and use
  // a pixel shader to blur the pixels based on the last frame's & current frame's 
  // per pixel velocity to achieve a motion blur effect
  for rt := 0 to g_nRtUsed - 1 do
    V(pd3dDevice.SetRenderTarget(rt, apOriginalRenderTarget[rt]));
  apOriginalRenderTarget[0] := nil;
  V(pd3dDevice.SetRenderState(D3DRS_ZENABLE, iFalse));

  // Clear the render target
  V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET, $00000000, 1.0, 0));

  // Above we rendered to a fullscreen render target texture, and now we
  // render that texture using a quad to apply a pixel shader on every pixel of the scene.
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    V(g_pEffect.SetTechnique(g_hPostProcessMotionBlur));

    V(g_pEffect._Begin(@cPasses, 0));
    for iPass := 0 to cPasses - 1 do
    begin
      V(g_pEffect.BeginPass(iPass));
      V(pd3dDevice.SetFVF(TScreenVertex_FVF));
      V(pd3dDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, g_Vertex, SizeOf(TScreenVertex)));
      V(g_pEffect.EndPass);
    end;
    V(g_pEffect._End);

    V(g_HUD.OnRender(fElapsedTime));
    V(g_SampleUI.OnRender(fElapsedTime ));
    RenderText;

    V(pd3dDevice.EndScene);
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
  // and then it calls pFont->DrawText( g_pSprite, strMsg, -1, &rc, DT_NOCLIP, g_clr );
  // If NULL is passed in as the sprite object, then it will work however the
  // pFont->DrawText() will not be batched together.  Batching calls will improves performance.
  txtHelper := CDXUTTextHelper.Create(g_pFont, g_pTextSprite, 15);

  // Output statistics
  txtHelper._Begin;
  txtHelper.SetInsertionPos(5, 5);
  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));
  txtHelper.DrawTextLine(DXUTGetFrameStats);
  txtHelper.DrawTextLine(DXUTGetDeviceStats);

  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
  {$IFNDEF FPC}
  //Clootie: Delphi 5-7 WideFormat bug
  txtHelper.DrawTextLine(PAnsiChar(Format('Blur=%0.2f Object Speed=%0.1f Camera Speed=%0.1f', [g_fPixelBlurConst, g_fObjectSpeed, g_fCameraSpeed])));
  {$ELSE}
  txtHelper.DrawFormattedTextLine('Blur=%0.2f Object Speed=%0.1f Camera Speed=%0.1f', [g_fPixelBlurConst, g_fObjectSpeed, g_fCameraSpeed]);
  {$ENDIF}

  if (g_nSleepTime = 0)
  then txtHelper.DrawTextLine('Not sleeping between frames')
  else txtHelper.DrawFormattedTextLine('Sleeping %dms per frame', [g_nSleepTime]);

  // Draw help
  if g_bShowHelp then
  begin
    pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*6);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
    txtHelper.DrawTextLine('Controls (F1 to hide):');

    txtHelper.SetInsertionPos(40, pd3dsdBackBuffer.Height-15*5);
    txtHelper.DrawTextLine('Look: Left drag mouse'#10+
                           'Move: A,W,S,D or Arrow Keys'#10+
                           'Move up/down: Q,E or PgUp,PgDn'#10+
                           'Reset camera: Home'#10+
                           'Quit: ESC');
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
    end;
  end;
end;


var
  {static} s_fRemember: Single = 1.0;

//--------------------------------------------------------------------------------------
// Handles the GUI events
//--------------------------------------------------------------------------------------
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
var
  vecEye, vecAt: TD3DXVector3;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;

    IDC_CHANGE_SCENE:
    begin
      g_nCurrentScene := g_nCurrentScene mod 2;
      Inc(g_nCurrentScene);

      case g_nCurrentScene of
        1:
        begin
          vecEye := D3DXVector3(40.0, 0.0, -15.0);
          vecAt := D3DXVector3(4.0, 4.0, -15.0);
          g_Camera.SetViewParams(vecEye, vecAt);
        end;

        2:
        begin
          vecEye := D3DXVector3(0.125, 1.25, 3.0);
          vecAt  := D3DXVector3(0.125, 1.25, 4.0);
          g_Camera.SetViewParams(vecEye, vecAt);
        end;
      end;
    end;

    IDC_ENABLE_BLUR:
    begin
      if g_SampleUI.GetCheckBox(IDC_ENABLE_BLUR).Checked then
      begin
        g_fPixelBlurConst := s_fRemember;
        g_SampleUI.GetStatic(IDC_BLUR_FACTOR_STATIC).Enabled := True;
        g_SampleUI.GetSlider(IDC_BLUR_FACTOR).Enabled := True;
      end else
      begin
        s_fRemember := g_fPixelBlurConst;
        g_fPixelBlurConst := 0.0;
        g_SampleUI.GetStatic(IDC_BLUR_FACTOR_STATIC).Enabled := False;
        g_SampleUI.GetSlider(IDC_BLUR_FACTOR).Enabled := False;
      end;
    end;

    IDC_FRAMERATE:
    begin
      g_nSleepTime := g_SampleUI.GetSlider(IDC_FRAMERATE).Value;
      //todo: fix WideFormatting bugs...
      g_SampleUI.GetStatic(IDC_FRAMERATE_STATIC).Text := PWideChar(WideFormat('Sleep: %dms/frame', [g_nSleepTime]));
    end;

    IDC_BLUR_FACTOR:
    begin
      g_fPixelBlurConst := g_SampleUI.GetSlider(IDC_BLUR_FACTOR).Value / 100.0;
      g_SampleUI.GetStatic(IDC_BLUR_FACTOR_STATIC).Text := PWideChar(WideFormat('Blur Factor: %0.2f', [g_fPixelBlurConst]));
    end;

    IDC_OBJECT_SPEED:
    begin
      g_fObjectSpeed := g_SampleUI.GetSlider(IDC_OBJECT_SPEED).Value;
      g_SampleUI.GetStatic(IDC_OBJECT_SPEED_STATIC).Text := PWideChar(WideFormat('Object Speed: %0.2f', [g_fObjectSpeed]));
    end;

    IDC_CAMERA_SPEED:
    begin
      g_fCameraSpeed := g_SampleUI.GetSlider(IDC_CAMERA_SPEED).Value;
      g_SampleUI.GetStatic(IDC_CAMERA_SPEED_STATIC).Text := PWideChar(WideFormat('Camera Speed: %0.2f', [g_fCameraSpeed]));
      g_Camera.SetScalers(0.01, g_fCameraSpeed);
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
var
  i, j, k: Integer;
begin
  g_DialogResourceManager.OnLostDevice;
  g_SettingsDlg.OnLostDevice;
  if Assigned(g_pFont) then g_pFont.OnLostDevice;
  if Assigned(g_pEffect) then g_pEffect.OnLostDevice;

  SAFE_RELEASE(g_pTextSprite);
  SAFE_RELEASE(g_pFullScreenRenderTargetSurf);
  SAFE_RELEASE(g_pFullScreenRenderTarget);
  SAFE_RELEASE(g_pPixelVelocitySurf1);
  SAFE_RELEASE(g_pPixelVelocityTexture1);
  SAFE_RELEASE(g_pPixelVelocitySurf2);
  SAFE_RELEASE(g_pPixelVelocityTexture2);

  for i:= 0 to High(g_aRTSet) do
    for j:= 0 to 1 do
      for k:= 0 to 1 do
        g_aRTSet[i].pRT[j][k] := nil;

  g_pLastFrameVelocityTexture:= nil;
  g_pLastFrameVelocitySurf:= nil;
  g_pCurFrameVelocityTexture:= nil;
  g_pCurFrameVelocitySurf:= nil;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has
// been destroyed, which generally happens as a result of application termination or
// windowed/full screen toggles. Resources created in the OnCreateDevice callback
// should be released here, which generally includes all D3DPOOL_MANAGED resources.
//--------------------------------------------------------------------------------------
procedure OnDestroyDevice; stdcall;
var
  iObject: Integer;
begin
  g_DialogResourceManager.OnDestroyDevice;
  g_SettingsDlg.OnDestroyDevice;
  SAFE_RELEASE(g_pEffect);
  SAFE_RELEASE(g_pFont);

  SAFE_RELEASE(g_pFullScreenRenderTargetSurf);
  SAFE_RELEASE(g_pFullScreenRenderTarget);

  SAFE_RELEASE(g_pMesh1);
  SAFE_RELEASE(g_pMeshTexture1);
  SAFE_RELEASE(g_pMesh2);
  SAFE_RELEASE(g_pMeshTexture2);
  SAFE_RELEASE(g_pMeshTexture3);

  for iObject:= 0 to NUM_OBJECTS - 1 do
  begin
    g_pScene1Object[iObject].g_pMesh := nil;
    g_pScene1Object[iObject].g_pMeshTexture := nil;
  end;

  for iObject:= 0 to NUM_WALLS - 1 do
  begin
    g_pScene2Object[iObject].g_pMesh := nil;
    g_pScene2Object[iObject].g_pMeshTexture := nil;
  end;
end;



procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera:= CFirstPersonCamera.Create;
  g_HUD := CDXUTDialog.Create;
  g_SampleUI := CDXUTDialog.Create;
end;

procedure DestroyCustomDXUTobjects;
var
  iObject: Integer;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_Camera);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);

  for iObject:= 0 to NUM_OBJECTS - 1 do Dispose(g_pScene1Object[iObject]);
  for iObject:= 0 to NUM_WALLS - 1 do Dispose(g_pScene2Object[iObject]);
end;

end.
