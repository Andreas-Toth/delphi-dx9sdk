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
 *  $Id: BasicHLSLunit.pas,v 1.23 2007/02/05 22:21:01 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: BasicHLSL.cpp
//
// This sample shows a simple example of the Microsoft Direct3D's High-Level
// Shader Language (HLSL) using the Effect interface.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit BasicHLSLunit;

interface

uses
  Windows, SysUtils, StrSafe,
  DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont:        ID3DXFont;          // Font for drawing text
  g_pSprite:      ID3DXSprite;        // Sprite for batching draw text calls
  g_bShowHelp:    Boolean = True;     // If true, it renders the UI control text
  g_Camera:       CModelViewerCamera; // A model viewing camera
  g_pEffect:      ID3DXEffect;        // D3DX effect interface
  g_pMesh:        ID3DXMesh;          // Mesh object
  g_pMeshTexture: IDirect3DTexture9;  // Mesh texture
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg:  CD3DSettingsDlg;    // Device settings dialog
  g_HUD:          CDXUTDialog;        // manages the 3D UI
  g_SampleUI:     CDXUTDialog;        // dialog for sample specific controls
  g_bEnablePreshader: Boolean;        // if TRUE, then D3DXSHADER_NO_PRESHADER is used when compiling the shader
  g_mCenterWorld: TD3DXMatrixA16;

const
  MAX_LIGHTS = 3;

var
  g_LightControl: array[0..MAX_LIGHTS-1] of CDXUTDirectionWidget;
  g_fLightScale: Single;
  g_nNumActiveLights: Integer;
  g_nActiveLight: Integer;


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_ENABLE_PRESHADER    = 5;
  IDC_NUM_LIGHTS          = 6;
  IDC_NUM_LIGHTS_STATIC   = 7;
  IDC_ACTIVE_LIGHT        = 8;
  IDC_LIGHT_SCALE         = 9;
  IDC_LIGHT_SCALE_STATIC  = 10;


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
function LoadMesh(const pd3dDevice: IDirect3DDevice9; strFileName: PWideChar; out ppMesh: ID3DXMesh): HRESULT;
procedure RenderText(fTime: Double);

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;


implementation


//--------------------------------------------------------------------------------------
// Initialize the app 
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  i: Integer;
  iY: Integer;
  sz: array[0..99] of WideChar;
begin
  g_bEnablePreshader := True;

  for i := 0 to MAX_LIGHTS - 1 do
    g_LightControl[i].SetLightDirection(D3DXVector3(sin(D3DX_PI*2*i/MAX_LIGHTS-D3DX_PI/6), 0, -cos(D3DX_PI*2*i/MAX_LIGHTS-D3DX_PI/6)));

  g_nActiveLight := 0;
  g_nNumActiveLights := 1;
  g_fLightScale := 1.0;

  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_SampleUI.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent); iY := 10;
  g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22); Inc(iY, 24);
  g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', 35, iY, 125, 22); Inc(iY, 24);
  g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 35, iY, 125, 22, VK_F2); // Inc(iY, 24);

  g_SampleUI.SetCallback(OnGUIEvent); iY := 10;

  Inc(iY, 24);
  StringCchFormat(sz, 100, '# Lights: %d'#0, [g_nNumActiveLights]);
  g_SampleUI.AddStatic(IDC_NUM_LIGHTS_STATIC, sz, 35, iY, 125, 22); Inc(iY, 24);
  g_SampleUI.AddSlider(IDC_NUM_LIGHTS, 50, iY, 100, 22, 1, MAX_LIGHTS, g_nNumActiveLights); Inc(iY, 24);

  Inc(iY, 24);
  // StringCchFormat(sz, 100, 'Light scale: %0.2f', [g_fLightScale]); // Delphi WideFormat() bug
  StringCchFormat(sz, 100, 'Light scale: %0f', [g_fLightScale]);
  g_SampleUI.AddStatic(IDC_LIGHT_SCALE_STATIC, sz, 35, iY, 125, 22); Inc(iY, 24);
  g_SampleUI.AddSlider(IDC_LIGHT_SCALE, 50, iY, 100, 22, 0, 20, Trunc(g_fLightScale * 10.0)); Inc(iY, 24);

  Inc(iY, 24);
  g_SampleUI.AddButton(IDC_ACTIVE_LIGHT, 'Change active light (K)', 35, iY, 125, 22, Ord('K')); Inc(iY, 24);
  g_SampleUI.AddCheckBox(IDC_ENABLE_PRESHADER, 'Enable preshaders', 35, iY, 125, 22, g_bEnablePreshader); // Inc(iY, 24);
end;


//--------------------------------------------------------------------------------------
// Called during device initialization, this code checks the device for some 
// minimum set of capabilities, and rejects those that don't pass by returning E_FAIL.
//--------------------------------------------------------------------------------------
function IsDeviceAcceptable(const pCaps: TD3DCaps9; AdapterFormat, BackBufferFormat: TD3DFormat; bWindowed: Boolean; pUserContext: Pointer): Boolean; stdcall;
var
  pD3D: IDirect3D9;
begin
  Result := False;

  // No fallback defined by this app, so reject any device that
  // doesn't support at least ps2.0
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2,0)) then Exit;

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
  pData: PD3DXVector3;
  vCenter: TD3DXVector3;
  fObjectRadius: Single;
  m: TD3DXMatrixA16;
  i: Integer;
  dwShaderFlags: DWORD;
  str: array [0..MAX_PATH-1] of WideChar;
  colorMtrlDiffuse, colorMtrlAmbient: TD3DXColor;
  vecEye, vecAt: TD3DXVector3;
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

  // Load the mesh
  Result := LoadMesh(pd3dDevice, 'tiny\tiny.x', g_pMesh);
  if V_Failed(Result) then Exit;

  V(g_pMesh.LockVertexBuffer(0, Pointer(pData)));
  V(D3DXComputeBoundingSphere(pData, g_pMesh.GetNumVertices, D3DXGetFVFVertexSize(g_pMesh.GetFVF), vCenter, fObjectRadius));
  V(g_pMesh.UnlockVertexBuffer);

  D3DXMatrixTranslation(g_mCenterWorld, -vCenter.x, -vCenter.y, -vCenter.z);
  D3DXMatrixRotationY(m, D3DX_PI);
  D3DXMatrixMultiply(g_mCenterWorld, g_mCenterWorld, m);
  D3DXMatrixRotationX(m, D3DX_PI / 2.0);
  D3DXMatrixMultiply(g_mCenterWorld, g_mCenterWorld, m); // g_mCenterWorld *= m;

  Result := CDXUTDirectionWidget.StaticOnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  for i := 0 to MAX_LIGHTS - 1 do
    g_LightControl[i].Radius := fObjectRadius;

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

  // Preshaders are parts of the shader that the effect system pulls out of the
  // shader and runs on the host CPU. They should be used if you are GPU limited.
  // The D3DXSHADER_NO_PRESHADER flag disables preshaders.
  if not g_bEnablePreshader then dwShaderFlags := dwShaderFlags or D3DXSHADER_NO_PRESHADER;

  // Read the D3DX effect file
  Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, WideString('BasicHLSL.fx'));
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // why the .fx file failed to compile
  Result := D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags, nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  // Create the mesh texture from a file
  Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, WideString('tiny\tiny_skin.dds'));
  if V_Failed(Result) then Exit;

  Result := D3DXCreateTextureFromFileExW(pd3dDevice, str, D3DX_DEFAULT, D3DX_DEFAULT,
                                         D3DX_DEFAULT, 0, D3DFMT_UNKNOWN, D3DPOOL_MANAGED,
                                         D3DX_DEFAULT, D3DX_DEFAULT, 0,
                                         nil, nil, g_pMeshTexture);
  if V_Failed(Result) then Exit;

  // Set effect variables as needed
  colorMtrlDiffuse := D3DXColor(1.0, 1.0, 1.0, 1.0);
  colorMtrlAmbient := D3DXColor(0.35, 0.35, 0.35, 0);

  Result:= g_pEffect.SetValue('g_MaterialAmbientColor', @colorMtrlAmbient, SizeOf(TD3DXColor));
  if V_Failed(Result) then Exit;
  Result:= g_pEffect.SetValue('g_MaterialDiffuseColor', @colorMtrlDiffuse, SizeOf(TD3DXColor));
  if V_Failed(Result) then Exit;
  Result:= g_pEffect.SetTexture('g_MeshTexture', g_pMeshTexture);
  if V_Failed(Result) then Exit;

  // Setup the camera's view parameters
  vecEye := D3DXVector3(0.0, 0.0, -15.0);
  vecAt  := D3DXVector3(0.0, 0.0, -0.0);
  g_Camera.SetViewParams(vecEye, vecAt);
  g_Camera.SetRadius(fObjectRadius*3.0, fObjectRadius*0.5, fObjectRadius*10.0);

  Result:= S_OK;
end;

//--------------------------------------------------------------------------------------
// This function loads the mesh and ensures the mesh has normals; it also optimizes the
// mesh for the graphics card's vertex cache, which improves performance by organizing
// the internal triangle list for less cache misses.
//--------------------------------------------------------------------------------------
function LoadMesh(const pd3dDevice: IDirect3DDevice9; strFileName: PWideChar; out ppMesh: ID3DXMesh): HRESULT;
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
  Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, strFileName);
  if V_Failed(Result) then Exit;
  Result := D3DXLoadMeshFromXW(str, D3DXMESH_MANAGED, pd3dDevice, nil, nil, nil, nil, pMesh);
  if V_Failed(Result) then Exit;

  // rgdwAdjacency := nil;

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
  GetMem(rgdwAdjacency, SizeOf(DWORD)*pMesh.GetNumFaces*3);
  try
    // if (rgdwAdjacency = nil) then Result:= E_OUTOFMEMORY;
    V(pMesh.GenerateAdjacency(1e-6, rgdwAdjacency));
    V(pMesh.OptimizeInplace(D3DXMESHOPT_VERTEXCACHE, rgdwAdjacency, nil, nil, nil));
  finally
    FreeMem(rgdwAdjacency);
  end;

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
  i: Integer;
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

  // Create a sprite to help batch calls when drawing many lines of text
  Result:= D3DXCreateSprite(pd3dDevice, g_pSprite);
  if V_Failed(Result) then Exit;

  for i := 0 to MAX_LIGHTS - 1 do
    g_LightControl[i].OnResetDevice(pBackBufferSurfaceDesc);

  // Setup the camera's projection parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI/4, fAspectRatio, 2.0, 4000.0);
  g_Camera.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);
  g_Camera.SetButtonMasks(MOUSE_LEFT_BUTTON, MOUSE_WHEEL, MOUSE_MIDDLE_BUTTON);

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation(pBackBufferSurfaceDesc.Width-170, pBackBufferSurfaceDesc.Height-300);
  g_SampleUI.SetSize(170, 300);

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
end;


//--------------------------------------------------------------------------------------
// This callback function will be called at the end of every frame to perform all the
// rendering calls for the scene, and it will also be called if the window needs to be
// repainted. After this function has returned, DXUT will call 
// IDirect3DDevice9::Present to display the contents of the next buffer in the swap chain
//--------------------------------------------------------------------------------------
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  mWorldViewProjection: TD3DXMatrixA16;
  vLightDir: array[0..MAX_LIGHTS-1] of TD3DXVector3;
  vLightDiffuse: array[0..MAX_LIGHTS-1] of TD3DXColor;
  iPass, cPasses: LongWord;
  m, mWorld, mView, mProj: TD3DXMatrixA16;
  i: Integer;
  arrowColor: TD3DXColor;
  vWhite: TD3DXColor;
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  // Clear the render target and the zbuffer
  V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, D3DXColorToDWord(D3DXColor(0.0,0.25,0.25,0.55)), 1.0, 0));

  // Render the scene
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    // Get the projection & view matrix from the camera class
    D3DXMatrixMultiply(mWorld, g_mCenterWorld, g_Camera.GetWorldMatrix^);
    mProj := g_Camera.GetProjMatrix^;
    mView := g_Camera.GetViewMatrix^;

    // mWorldViewProjection = mWorld * mView * mProj;
    D3DXMatrixMultiply(m, mView, mProj);
    D3DXMatrixMultiply(mWorldViewProjection, mWorld, m);

    // Render the light arrow so the user can visually see the light dir
    for i := 0 to g_nNumActiveLights - 1 do
    begin
      if (i = g_nActiveLight) then arrowColor := D3DXColor(1,1,0,1) else arrowColor := D3DXColor(1,1,1,1);
      V(g_LightControl[i].OnRender(arrowColor, mView, mProj, g_Camera.GetEyePt^));
      vLightDir[i] := g_LightControl[i].LightDirection;
      D3DXColorScale(vLightDiffuse[i], D3DXColor(1,1,1,1), g_fLightScale); // vLightDiffuse[i] := g_fLightScale * D3DXColor(1,1,1,1);
    end;

    V(g_pEffect.SetValue('g_LightDir', @vLightDir, SizeOf(TD3DXVector3)*MAX_LIGHTS));
    V(g_pEffect.SetValue('g_LightDiffuse', @vLightDiffuse, SizeOf(TD3DXVector4)*MAX_LIGHTS));

    // Update the effect's variables.  Instead of using strings, it would
    // be more efficient to cache a handle to the parameter by calling
    // ID3DXEffect::GetParameterByName
    V(g_pEffect.SetMatrix('g_mWorldViewProjection', mWorldViewProjection));
    V(g_pEffect.SetMatrix('g_mWorld', mWorld));
    V(g_pEffect.SetFloat('g_fTime', fTime));

    vWhite := D3DXColor(1,1,1,1);
    V(g_pEffect.SetValue('g_MaterialDiffuseColor', @vWhite, SizeOf(TD3DXColor)));
    V(g_pEffect.SetFloat('g_fTime', fTime));
    V(g_pEffect.SetInt('g_nNumLights', g_nNumActiveLights));

    // Render the scene with this technique
    // as defined in the .fx file
    if (GetDXUTState.Caps.PixelShaderVersion < D3DPS_VERSION(1, 1)) then
    case g_nNumActiveLights of
      1: V(g_pEffect.SetTechnique('RenderSceneWithTexture1LightNOPS'));
      2: V(g_pEffect.SetTechnique('RenderSceneWithTexture2LightNOPS'));
      3: V(g_pEffect.SetTechnique('RenderSceneWithTexture3LightNOPS'));
    end else
    case g_nNumActiveLights of
      1: V(g_pEffect.SetTechnique('RenderSceneWithTexture1Light'));
      2: V(g_pEffect.SetTechnique('RenderSceneWithTexture2Light'));
      3: V(g_pEffect.SetTechnique('RenderSceneWithTexture3Light'));
    end;

    
    // Apply the technique contained in the effect
    V(g_pEffect._Begin(@cPasses, 0));

    for iPass := 0 to cPasses - 1 do
    begin
      V(g_pEffect.BeginPass(iPass));

      // The effect interface queues up the changes and performs them
      // with the CommitChanges call. You do not need to call CommitChanges if
      // you are not setting any parameters between the BeginPass and EndPass.
      // V( g_pEffect->CommitChanges() );

      // Render the mesh with the applied technique
      V(g_pMesh.DrawSubset(0));

      V(g_pEffect.EndPass);
    end;
    V(g_pEffect._End);

    g_HUD.OnRender(fElapsedTime);
    g_SampleUI.OnRender(fElapsedTime);

    RenderText(fTime);

    V(pd3dDevice.EndScene);
  end;
end;


//--------------------------------------------------------------------------------------
// Render the help and statistics text. This function uses the ID3DXFont interface for 
// efficient text rendering.
//--------------------------------------------------------------------------------------
procedure RenderText(fTime: Double);
var
  txtHelper: CDXUTTextHelper;
  pd3dsdBackBuffer: PD3DSurfaceDesc;
begin
  // The helper object simply helps keep track of text position, and color
  // and then it calls pFont->DrawText( m_pSprite, strMsg, -1, &rc, DT_NOCLIP, m_clr );
  // If NULL is passed in as the sprite object, then it will work fine however the 
  // pFont->DrawText() will not be batched together.  Batching calls will improves perf.
  txtHelper:= CDXUTTextHelper.Create(g_pFont, g_pSprite, 15);
  try
    // Output statistics
    txtHelper._Begin;
    txtHelper.SetInsertionPos(2, 0);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));
    txtHelper.DrawTextLine(DXUTGetFrameStats);
    txtHelper.DrawTextLine(DXUTGetDeviceStats);

    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
    // txtHelper.DrawFormattedTextLine('fTime: %0.1f  sin(fTime): %0.4f', [fTime, sin(fTime)]);
    {$IFDEF FPC}
    txtHelper.DrawTextLine(PWideChar(WideFormat('fTime: %0.1f  sin(fTime): %0.4f', [fTime, sin(fTime)])));
    {$ELSE}
    txtHelper.DrawTextLine(PAnsiChar(Format('fTime: %0.1f  sin(fTime): %0.4f', [fTime, sin(fTime)]))); // Delphi WideFormat bug
    {$ENDIF}

    // Draw help
    if g_bShowHelp then
    begin
      pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
      txtHelper.SetInsertionPos(2, pd3dsdBackBuffer.Height-15*6);
      txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
      txtHelper.DrawTextLine('Controls:');

      txtHelper.SetInsertionPos(20, pd3dsdBackBuffer.Height-15*5);
      txtHelper.DrawTextLine('Rotate model: Left mouse button'#10+
                             'Rotate light: Right mouse button'#10+
                             'Rotate camera: Middle mouse button'#10+
                             'Zoom camera: Mouse wheel scroll'#10);

      txtHelper.SetInsertionPos(250, pd3dsdBackBuffer.Height-15*5);
      txtHelper.DrawTextLine('Hide help: F1'#10+
                             'Quit: ESC'#10);
    end else
    begin
      txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
      txtHelper.DrawTextLine('Press F1 for help');
    end;
    txtHelper._End;
  finally
    txtHelper.Free;
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

  g_LightControl[g_nActiveLight].HandleMessages(hWnd, uMsg, wParam, lParam);

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


//--------------------------------------------------------------------------------------
// Handles the GUI events
//--------------------------------------------------------------------------------------
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
var
  sz: array[0..99] of WideChar;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;

    IDC_ENABLE_PRESHADER:
    begin
      g_bEnablePreshader := g_SampleUI.GetCheckBox(IDC_ENABLE_PRESHADER).Checked;

      if (DXUTGetD3DDevice <> nil) then 
      begin
        OnLostDevice(nil);
        OnDestroyDevice(nil);
        OnCreateDevice(DXUTGetD3DDevice, DXUTGetBackBufferSurfaceDesc^, nil);
        OnResetDevice(DXUTGetD3DDevice, DXUTGetBackBufferSurfaceDesc^, nil);
      end;
    end;

    IDC_ACTIVE_LIGHT:
    if not g_LightControl[g_nActiveLight].IsBeingDragged then
    begin
      Inc(g_nActiveLight);
      g_nActiveLight := g_nActiveLight mod g_nNumActiveLights;
    end;

    IDC_NUM_LIGHTS:
    if not g_LightControl[g_nActiveLight].IsBeingDragged then
    begin
      StringCchFormat(sz, 100, '# Lights: %d', [g_SampleUI.GetSlider(IDC_NUM_LIGHTS).Value]);
      g_SampleUI.GetStatic(IDC_NUM_LIGHTS_STATIC).Text := sz;

      g_nNumActiveLights := g_SampleUI.GetSlider(IDC_NUM_LIGHTS).Value;
      g_nActiveLight := g_nActiveLight mod g_nNumActiveLights;
    end;

    IDC_LIGHT_SCALE:
    begin
      g_fLightScale := g_SampleUI.GetSlider(IDC_LIGHT_SCALE).Value * 0.10;

      // WideFormatBuf(sz, 100, 'Light scale: %0.2f', [g_fLightScale]);
      StringCchFormat(sz, 100, 'Light scale: %f', [g_fLightScale]); // Delphi WideFormat() bug
      g_SampleUI.GetStatic(IDC_LIGHT_SCALE_STATIC).Text := sz;
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
  if Assigned(g_pFont) then g_pFont.OnLostDevice;
  if Assigned(g_pEffect) then g_pEffect.OnLostDevice;
  SAFE_RELEASE(g_pSprite);
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
  CDXUTDirectionWidget.StaticOnDestroyDevice;
  SAFE_RELEASE(g_pEffect);
  SAFE_RELEASE(g_pFont);
  SAFE_RELEASE(g_pMesh);
  SAFE_RELEASE(g_pMeshTexture);
end;


procedure CreateCustomDXUTobjects;
var
  i: Integer;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  for i:= 0 to MAX_LIGHTS-1 do g_LightControl[i]:= CDXUTDirectionWidget.Create;
  g_Camera:= CModelViewerCamera.Create; // A model viewing camera
  g_HUD:= CDXUTDialog.Create; // manages the 3D UI
  g_SampleUI:= CDXUTDialog.Create; // dialog for sample specific controls
end;

procedure DestroyCustomDXUTobjects;
var
  i: Integer;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_Camera);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);
  for i:= 0 to MAX_LIGHTS-1 do
    FreeAndNil(g_LightControl[i]);
end;

end.

