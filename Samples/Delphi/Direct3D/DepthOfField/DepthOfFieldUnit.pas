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
 *  $Id: DepthOfFieldUnit.pas,v 1.16 2007/02/05 22:21:05 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: DepthOfField.cpp
//
// Starting point for new Direct3D applications
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit DepthOfFieldUnit;

interface

uses
  Windows, SysUtils,
  DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTmesh, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders


//--------------------------------------------------------------------------------------
// Vertex format
//--------------------------------------------------------------------------------------
type
  TVertex = record
    pos: TD3DXVector4;
    clr:  DWORD;
    tex1: TD3DXVector2;
    tex2: TD3DXVector2;
    tex3: TD3DXVector2;
    tex4: TD3DXVector2;
    tex5: TD3DXVector2;
    tex6: TD3DXVector2;
    // static const DWORD FVF;
  end;

const
  TVertex_FVF = D3DFVF_XYZRHW or D3DFVF_DIFFUSE or D3DFVF_TEX6;


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont: ID3DXFont;                  // Font for drawing text
  g_pTextSprite: ID3DXSprite;          // Sprite for batching draw text calls
  g_Camera: CFirstPersonCamera;        // A model viewing camera
  g_bShowHelp: Boolean = True;         // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg;      // Device settings dialog
  g_HUD: CDXUTDialog;                  // dialog for standard controls
  g_SampleUI: CDXUTDialog;             // dialog for sample specific controls

  g_Vertex: array[0..3] of TVertex;

  g_pFullScreenTexture: IDirect3DTexture9;
  g_pRenderToSurface: ID3DXRenderToSurface;
  g_pFullScreenTextureSurf: IDirect3DSurface9;

  g_pScene1Mesh: ID3DXMesh;
  g_pScene1MeshTexture: IDirect3DTexture9;
  g_pScene2Mesh: ID3DXMesh;
  g_pScene2MeshTexture: IDirect3DTexture9;
  g_nCurrentScene: Integer;
  g_pEffect: ID3DXEffect;

  g_vFocalPlane: TD3DXVector4;
  g_fChangeTime: Double;
  g_nShowMode: Integer;
  g_dwBackgroundColor: DWORD;

  g_ViewportFB: TD3DViewport9;
  g_ViewportOffscreen: TD3DViewport9;

  g_fBlurConst: Single;
  g_TechniqueIndex: DWORD;

  g_hFocalPlane: TD3DXHandle;
  g_hWorld: TD3DXHandle;
  g_hWorldView: TD3DXHandle;
  g_hWorldViewProjection: TD3DXHandle;
  g_hMeshTexture: TD3DXHandle;
  g_hTechWorldWithBlurFactor: TD3DXHandle;
  g_hTechShowBlurFactor: TD3DXHandle;
  g_hTechShowUnmodified: TD3DXHandle;
  g_hTech: array[0..4] of TD3DXHandle;

  g_TechniqueNames: array[0..2] of PAnsiChar = (
    'UsePS20ThirteenLookups',
    'UsePS20SevenLookups',
    'UsePS20SixTexcoords'
  );

const
  g_TechniqueCount = High(g_TechniqueNames)+1;



//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_CHANGE_SCENE        = 5;
  IDC_CHANGE_TECHNIQUE    = 6;
  IDC_SHOW_BLUR           = 7;
  IDC_CHANGE_BLUR         = 8;
  IDC_CHANGE_FOCAL        = 9;
  IDC_CHANGE_BLUR_STATIC  = 10;
  IDC_SHOW_UNBLURRED      = 11;
  IDC_SHOW_NORMAL         = 12;
  IDC_CHANGE_FOCAL_STATIC = 13;



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
function LoadMesh(pd3dDevice: IDirect3DDevice9; strFileName: PWideChar; out ppMesh: ID3DXMesh): HRESULT;
procedure RenderText;
procedure SetupQuad(const pBackBufferSurfaceDesc: TD3DSurfaceDesc);
function UpdateTechniqueSpecificVariables(const pBackBufferSurfaceDesc: TD3DSurfaceDesc): HRESULT;

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;

implementation

uses StrSafe;


//--------------------------------------------------------------------------------------
// Initialize the app
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  iY: Integer;
  sz: array[0..99] of WideChar; 
begin
  g_pFont := nil;

  g_pFullScreenTexture := nil;
  g_pFullScreenTextureSurf := nil;
  g_pRenderToSurface := nil;
  g_pEffect := nil;

  g_vFocalPlane := D3DXVector4(0.0, 0.0, 1.0, -2.5);
  g_fChangeTime := 0.0;

  g_pScene1Mesh := nil;
  g_pScene1MeshTexture := nil;
  g_pScene2Mesh := nil;
  g_pScene2MeshTexture := nil;
  g_nCurrentScene := 1;

  g_nShowMode := 0;
  g_bShowHelp := True;
  g_dwBackgroundColor := $00003F3F;

  g_fBlurConst := 4.0;
  g_TechniqueIndex := 0;

  g_hFocalPlane := nil;
  g_hWorld := nil;
  g_hWorldView := nil;
  g_hWorldViewProjection := nil;
  g_hMeshTexture := nil;
  g_hTechWorldWithBlurFactor := nil;
  g_hTechShowBlurFactor := nil;
  g_hTechShowUnmodified := nil;
  ZeroMemory(@g_hTech, SizeOf(g_hTech));

  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_SampleUI.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent);
  iY := 10;    g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 35, iY, 125, 22, VK_F2);

  g_SampleUI.SetCallback(OnGUIEvent);
  iY := 10;    g_SampleUI.AddButton(IDC_CHANGE_SCENE, 'Change Scene', 35, iY, 125, 22, Ord('P'));
  Inc(iY, 24); g_SampleUI.AddButton(IDC_CHANGE_TECHNIQUE, 'Change Technique', 35, iY, 125, 22, Ord('N'));
  Inc(iY, 24); g_SampleUI.AddRadioButton(IDC_SHOW_NORMAL, 1, 'Show Normal', 35, iY, 125, 22, True);
  Inc(iY, 24); g_SampleUI.AddRadioButton(IDC_SHOW_BLUR, 1, 'Show Blur Factor', 35, iY, 125, 22);
  Inc(iY, 24); g_SampleUI.AddRadioButton(IDC_SHOW_UNBLURRED, 1, 'Show Unblurred', 35, iY, 125, 22);

  Inc(iY, 24); StringCchFormat(sz, 100, 'Focal Distance: %0.2f'#0, [-g_vFocalPlane.w]); sz[99] := #0;
  Inc(iY, 24); g_SampleUI.AddStatic(IDC_CHANGE_FOCAL_STATIC, sz, 35, iY, 125, 22 );
  Inc(iY, 24); g_SampleUI.AddSlider(IDC_CHANGE_FOCAL, 50, iY, 100, 22, 0, 100, Trunc(-g_vFocalPlane.w*10.0));

  Inc(iY, 24); StringCchFormat(sz, 100, 'Blur Factor: %0.2f'#0, [g_fBlurConst]); sz[99] := #0;
  Inc(iY, 24); g_SampleUI.AddStatic(IDC_CHANGE_BLUR_STATIC, sz, 35, iY, 125, 22 );
  Inc(iY, 24); g_SampleUI.AddSlider(IDC_CHANGE_BLUR, 50, iY, 100, 22, 0, 100, Trunc(g_fBlurConst*10.0));
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

  // Must support pixel shader 2.0
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2, 0))
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
  dwShaderFlags: DWORD;
begin
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  // Initialize the font
  Result:= D3DXCreateFont(pd3dDevice, 15, 0, FW_BOLD, 1, False, DEFAULT_CHARSET,
                          OUT_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE,
                          'Arial', g_pFont);
  if V_Failed(Result) then Exit;

  // Load the meshs
  Result:= LoadMesh(pd3dDevice, 'tiger\tiger.x', g_pScene1Mesh);
  if V_Failed(Result) then Exit;
  Result:= LoadMesh(pd3dDevice, 'misc\sphere.x', g_pScene2Mesh);
  if V_Failed(Result) then Exit;

  // Load the mesh textures
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'tiger\tiger.bmp');
  if V_Failed(Result) then Exit;
  Result:= D3DXCreateTextureFromFileW(pd3dDevice, str, g_pScene1MeshTexture);
  if V_Failed(Result) then Exit;

  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'earth\earth.bmp');
  if V_Failed(Result) then Exit;
  Result:= D3DXCreateTextureFromFileW(pd3dDevice, str, g_pScene2MeshTexture);
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

  // Read the D3DX effect file
  // If this fails, there should be debug output as to
  // they the .fx file failed to compile
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'DepthOfField.fx');
  if V_Failed(Result) then Exit;
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags,
                                     nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// This function loads the mesh and ensures the mesh has normals; it also optimizes the
// mesh for the graphics card's vertex cache, which improves performance by organizing
// the internal triangle list for less cache misses.
//--------------------------------------------------------------------------------------
function LoadMesh(pd3dDevice: IDirect3DDevice9; strFileName: PWideChar; out ppMesh: ID3DXMesh): HRESULT;
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
    Result := V(pMesh.CloneMeshFVF(pMesh.GetOptions, pMesh.GetFVF or D3DFVF_NORMAL, pd3dDevice, pTempMesh));
      if Failed(Result) then Exit;
    Result := V(D3DXComputeNormals(pTempMesh, nil));
      if Failed(Result) then Exit;

    SAFE_RELEASE(pMesh);
    pMesh := pTempMesh;
  end;

  // Optimize the mesh for this graphics card's vertex cache
  // so when rendering the mesh's triangle list the vertices will
  // cache hit more often so it won't have to re-execute the vertex shader
  // on those vertices so it will improve perf.
  try
    GetMem(rgdwAdjacency, SizeOf(DWORD)*pMesh.GetNumFaces*3);
    V(pMesh.GenerateAdjacency(1e-6,rgdwAdjacency));
    V(pMesh.OptimizeInplace(D3DXMESHOPT_VERTEXCACHE, rgdwAdjacency, nil, nil, nil));
    FreeMem(rgdwAdjacency);
    ppMesh := pMesh;

    Result:= S_OK;
  except
    on EOutOfMemory do Result:= E_OUTOFMEMORY;
  end;
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
  vecEye: TD3DXVector3;
  vecAt: TD3DXVector3;
  desc: TD3DSurfaceDesc;
  colorWhite: TD3DXColor;
  colorBlack: TD3DXColor;
  colorAmbient: TD3DXColor;
  i: Integer;
  OriginalTechnique: DWORD;
  hTech: TD3DXHandle;
begin
  Result:= g_DialogResourceManager.OnResetDevice;
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnResetDevice;
  if V_Failed(Result) then Exit;

  Result:= S_OK;
  if (g_pFont <> nil) then Result := g_pFont.OnResetDevice;
  if V_Failed(Result) then Exit;
  if (g_pEffect <> nil) then Result:= g_pEffect.OnResetDevice;
  if V_Failed(Result) then Exit;

  // Setup the camera with view & projection matrix
  vecEye := D3DXVector3(1.3, 1.1, -3.3);
  vecAt := D3DXVector3(0.75, 0.9, -2.5);
  g_Camera.SetViewParams( vecEye, vecAt);
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DXToRadian(60.0), fAspectRatio, 0.5, 100.0);

  pd3dDevice.GetViewport(g_ViewportFB);

  // Backbuffer viewport is identical to frontbuffer, except starting at 0, 0
  g_ViewportOffscreen := g_ViewportFB;
  g_ViewportOffscreen.X := 0;
  g_ViewportOffscreen.Y := 0;

  // Create fullscreen renders target texture
  Result := D3DXCreateTexture(pd3dDevice, pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height,
                              1, D3DUSAGE_RENDERTARGET, D3DFMT_A8R8G8B8, D3DPOOL_DEFAULT, g_pFullScreenTexture);
  if FAILED(Result) then
  begin
    // Fallback to a non-RT texture
    Result:= D3DXCreateTexture(pd3dDevice, pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height,
                               1, 0, D3DFMT_A8R8G8B8, D3DPOOL_DEFAULT, g_pFullScreenTexture);
    if V_Failed(Result) then Exit;
  end;

  g_pFullScreenTexture.GetSurfaceLevel(0, g_pFullScreenTextureSurf);
  g_pFullScreenTextureSurf.GetDesc(desc);

  // Create a ID3DXRenderToSurface to help render to a texture on cards
  // that don't support render targets
  Result:= D3DXCreateRenderToSurface(pd3dDevice, desc.Width, desc.Height,
                                     desc.Format, True, D3DFMT_D16, g_pRenderToSurface);
  if V_Failed(Result) then Exit;

  // clear the surface alpha to 0 so that it does not bleed into a "blurry" background
  //   this is possible because of the avoidance of blurring in a non-blurred texel
  if SUCCEEDED(g_pRenderToSurface.BeginScene(g_pFullScreenTextureSurf, nil)) then
  begin
    pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET, $00, 1.0, 0);
    g_pRenderToSurface.EndScene(0);
  end;

  colorWhite := D3DXColor(1.0, 1.0, 1.0, 1.0);
  colorBlack := D3DXCOLOR(0.0, 0.0, 0.0, 1.0);
  colorAmbient := D3DXColor(0.25, 0.25, 0.25, 1.0);

  // Get D3DXHANDLEs to the parameters/techniques that are set every frame so 
  // D3DX doesn't spend time doing string compares.  Doing this likely won't affect
  // the perf of this simple sample but it should be done in complex engine.
  g_hFocalPlane               := g_pEffect.GetParameterByName(nil, 'vFocalPlane');
  g_hWorld                    := g_pEffect.GetParameterByName(nil, 'mWorld');
  g_hWorldView                := g_pEffect.GetParameterByName(nil, 'mWorldView');
  g_hWorldViewProjection      := g_pEffect.GetParameterByName(nil, 'mWorldViewProjection');
  g_hMeshTexture              := g_pEffect.GetParameterByName(nil, 'MeshTexture');
  g_hTechWorldWithBlurFactor  := g_pEffect.GetTechniqueByName('WorldWithBlurFactor');
  g_hTechShowBlurFactor       := g_pEffect.GetTechniqueByName('ShowBlurFactor');
  g_hTechShowUnmodified       := g_pEffect.GetTechniqueByName('ShowUnmodified');
  for i := 0 to g_TechniqueCount do
    g_hTech[i] := g_pEffect.GetTechniqueByName(g_TechniqueNames[i]);

  // Set the vars in the effect that doesn't change each frame
  Result:= g_pEffect.SetVector('MaterialAmbientColor', PD3DXVector4(@colorAmbient)^);
  if V_Failed(Result) then Exit;
  Result:= g_pEffect.SetVector('MaterialDiffuseColor', PD3DXVector4(@colorWhite)^);
  if V_Failed(Result) then Exit;
  Result:= g_pEffect.SetTexture('RenderTargetTexture', g_pFullScreenTexture);
  if V_Failed(Result) then Exit;

  // Check if the current technique is valid for the new device/settings
  // Start from the current technique, increment until we find one we can use.
  OriginalTechnique := g_TechniqueIndex;
  repeat
    hTech := g_pEffect.GetTechniqueByName(g_TechniqueNames[g_TechniqueIndex]);
    if SUCCEEDED(g_pEffect.ValidateTechnique(hTech)) then Break;

    Inc(g_TechniqueIndex);
    if (g_TechniqueIndex = g_TechniqueCount) then g_TechniqueIndex := 0;
  until (OriginalTechnique = g_TechniqueIndex);
  // while( OriginalTechnique <> g_TechniqueIndex);

  Result:= UpdateTechniqueSpecificVariables(pBackBufferSurfaceDesc);
  if V_Failed(Result) then Exit;

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation(pBackBufferSurfaceDesc.Width-170, pBackBufferSurfaceDesc.Height-300);
  g_SampleUI.SetSize(170, 250);

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// Certain parameters need to be specified for specific techniques
//--------------------------------------------------------------------------------------
function UpdateTechniqueSpecificVariables(const pBackBufferSurfaceDesc: TD3DSurfaceDesc): HRESULT;
var
  strInputArrayName, strOutputArrayName: PChar;
  nNumKernelEntries: Integer;
  hAnnotation: TD3DXHandle;
  hTech: TD3DXHandle;
  aKernel, aKernel2: PD3DXVector2;
  desc: TD3DSurfaceDesc;
  fWidthMod: Single;
  fHeightMod: Single;
  iEntry: Integer;
begin
  // Create the post-process quad and set the texcoords based on the blur factor
  SetupQuad(pBackBufferSurfaceDesc);

  // Get the handle to the current technique
  hTech := g_pEffect.GetTechniqueByName(g_TechniqueNames[g_TechniqueIndex]);
  if(hTech = nil) then
  begin
    Result := S_FALSE; // This will happen if the technique doesn't have this annotation
    Exit;
  end;

  // Get the value of the annotation int named "NumKernelEntries" inside the technique
  hAnnotation := g_pEffect.GetAnnotationByName(hTech, 'NumKernelEntries');
  if (hAnnotation = nil) then // This will happen if the technique doesn't have this annotation
    begin Result:= S_FALSE; Exit; end;
  Result:= g_pEffect.GetInt(hAnnotation, nNumKernelEntries);
  if V_Failed(Result) then Exit;

  // Get the value of the annotation string named "KernelInputArray" inside the technique
  hAnnotation := g_pEffect.GetAnnotationByName(hTech, 'KernelInputArray');
  if (hAnnotation = nil) then // This will happen if the technique doesn't have this annotation
    begin Result:= S_FALSE; Exit; end;
  Result:= g_pEffect.GetString(hAnnotation, strInputArrayName);
  if V_Failed(Result) then Exit;

  // Get the value of the annotation string named "KernelOutputArray" inside the technique
  hAnnotation := g_pEffect.GetAnnotationByName(hTech, 'KernelOutputArray');
  if (hAnnotation = nil) then // This will happen if the technique doesn't have this annotation
    begin Result:= S_FALSE; Exit; end;
  Result := g_pEffect.GetString(hAnnotation, strOutputArrayName);
  if V_Failed(Result) then Exit;

  // Create a array to store the input array
  try
    GetMem(aKernel, SizeOf(TD3DXVector2)*nNumKernelEntries);
  except
    Result:= E_OUTOFMEMORY;
    Exit;
  end;

  // Get the input array
  Result:= g_pEffect.GetValue(TD3DXHandle(strInputArrayName), aKernel, SizeOf(TD3DXVector2)*nNumKernelEntries);
  if V_Failed(Result) then Exit;

  // Get the size of the texture
  g_pFullScreenTextureSurf.GetDesc(desc);

  // Calculate the scale factor to convert the input array to screen space
  fWidthMod := g_fBlurConst / desc.Width ;
  fHeightMod := g_fBlurConst / desc.Height;

  // Scale the effect's kernel from pixel space to tex coord space
  // In pixel space 1 unit = one pixel and in tex coord 1 unit = width/height of texture
  aKernel2:= aKernel;
  for iEntry := 0 to nNumKernelEntries - 1 do
  begin
    aKernel2.x := aKernel.x * fWidthMod;
    aKernel2.y := aKernel.y * fHeightMod;
    Inc(aKernel2);
  end;

  // Pass the updated array values to the effect file
  Result:= g_pEffect.SetValue(TD3DXHandle(strOutputArrayName), aKernel, SizeOf(TD3DXVector2)*nNumKernelEntries);
  if V_Failed(Result) then Exit;

  FreeMem(aKernel);

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// Sets up a quad to render the fullscreen render target to the backbuffer
// so it can run a fullscreen pixel shader pass that blurs based
// on the depth of the objects.  It set the texcoords based on the blur factor
//--------------------------------------------------------------------------------------
procedure SetupQuad(const pBackBufferSurfaceDesc: TD3DSurfaceDesc);
var
  desc: TD3DSurfaceDesc;

  fWidth5, fHeight5,
  fHalf, fOffOne, fOffTwo,
  fTexWidth1, fTexHeight1,
  fWidthMod, fHeightMod        : Single;
  
begin
  g_pFullScreenTextureSurf.GetDesc(desc);

  fWidth5 := pBackBufferSurfaceDesc.Width - 0.5;
  fHeight5 := pBackBufferSurfaceDesc.Height - 0.5;

  fHalf := g_fBlurConst;
  fOffOne := fHalf * 0.5;
  fOffTwo := fOffOne * sqrt(3.0);

  fTexWidth1 := pBackBufferSurfaceDesc.Width / desc.Width;
  fTexHeight1 := pBackBufferSurfaceDesc.Height / desc.Height;

  fWidthMod := 1.0 / desc.Width ;
  fHeightMod := 1.0 / desc.Height;

  // Create vertex buffer.
  // g_Vertex[0].tex1 == full texture coverage
  // g_Vertex[0].tex2 == full texture coverage, but shifted y by -fHalf*fHeightMod
  // g_Vertex[0].tex3 == full texture coverage, but shifted x by -fOffTwo*fWidthMod & y by -fOffOne*fHeightMod
  // g_Vertex[0].tex4 == full texture coverage, but shifted x by +fOffTwo*fWidthMod & y by -fOffOne*fHeightMod
  // g_Vertex[0].tex5 == full texture coverage, but shifted x by -fOffTwo*fWidthMod & y by +fOffOne*fHeightMod
  // g_Vertex[0].tex6 == full texture coverage, but shifted x by +fOffTwo*fWidthMod & y by +fOffOne*fHeightMod
  g_Vertex[0].pos := D3DXVector4(fWidth5, -0.5, 0.0, 1.0);
  g_Vertex[0].clr := D3DXColorToDWord(D3DXColor(0.5, 0.5, 0.5, 0.66666));
  g_Vertex[0].tex1 := D3DXVector2(fTexWidth1, 0.0);
  g_Vertex[0].tex2 := D3DXVector2(fTexWidth1, 0.0 - fHalf*fHeightMod);
  g_Vertex[0].tex3 := D3DXVector2(fTexWidth1 - fOffTwo*fWidthMod, 0.0 - fOffOne*fHeightMod);
  g_Vertex[0].tex4 := D3DXVector2(fTexWidth1 + fOffTwo*fWidthMod, 0.0 - fOffOne*fHeightMod);
  g_Vertex[0].tex5 := D3DXVector2(fTexWidth1 - fOffTwo*fWidthMod, 0.0 + fOffOne*fHeightMod);
  g_Vertex[0].tex6 := D3DXVector2(fTexWidth1 + fOffTwo*fWidthMod, 0.0 + fOffOne*fHeightMod);

  g_Vertex[1].pos := D3DXVector4(fWidth5, fHeight5, 0.0, 1.0);
  g_Vertex[1].clr := D3DXColorToDWord(D3DXColor(0.5, 0.5, 0.5, 0.66666));
  g_Vertex[1].tex1 := D3DXVector2(fTexWidth1, fTexHeight1);
  g_Vertex[1].tex2 := D3DXVector2(fTexWidth1, fTexHeight1 - fHalf*fHeightMod);
  g_Vertex[1].tex3 := D3DXVector2(fTexWidth1 - fOffTwo*fWidthMod, fTexHeight1 - fOffOne*fHeightMod);
  g_Vertex[1].tex4 := D3DXVector2(fTexWidth1 + fOffTwo*fWidthMod, fTexHeight1 - fOffOne*fHeightMod);
  g_Vertex[1].tex5 := D3DXVector2(fTexWidth1 - fOffTwo*fWidthMod, fTexHeight1 + fOffOne*fHeightMod);
  g_Vertex[1].tex6 := D3DXVector2(fTexWidth1 + fOffTwo*fWidthMod, fTexHeight1 + fOffOne*fHeightMod);

  g_Vertex[2].pos := D3DXVector4(-0.5, -0.5, 0.0, 1.0);
  g_Vertex[2].clr := D3DXColorToDWord(D3DXColor(0.5, 0.5, 0.5, 0.66666));
  g_Vertex[2].tex1 := D3DXVector2(0.0, 0.0);
  g_Vertex[2].tex2 := D3DXVector2(0.0, 0.0 - fHalf*fHeightMod);
  g_Vertex[2].tex3 := D3DXVector2(0.0 - fOffTwo*fWidthMod, 0.0 - fOffOne*fHeightMod);
  g_Vertex[2].tex4 := D3DXVector2(0.0 + fOffTwo*fWidthMod, 0.0 - fOffOne*fHeightMod);
  g_Vertex[2].tex5 := D3DXVector2(0.0 - fOffTwo*fWidthMod, 0.0 + fOffOne*fHeightMod);
  g_Vertex[2].tex6 := D3DXVector2(0.0 + fOffTwo*fWidthMod, 0.0 + fOffOne*fHeightMod);

  g_Vertex[3].pos := D3DXVector4(-0.5, fHeight5, 0.0, 1.0);
  g_Vertex[3].clr := D3DXColorToDWord(D3DXColor(0.5, 0.5, 0.5, 0.66666));
  g_Vertex[3].tex1 := D3DXVector2(0.0, fTexHeight1);
  g_Vertex[3].tex2 := D3DXVector2(0.0, fTexHeight1 - fHalf*fHeightMod);
  g_Vertex[3].tex3 := D3DXVector2(0.0 - fOffTwo*fWidthMod, fTexHeight1 - fOffOne*fHeightMod);
  g_Vertex[3].tex4 := D3DXVector2(0.0 + fOffTwo*fWidthMod, fTexHeight1 - fOffOne*fHeightMod);
  g_Vertex[3].tex5 := D3DXVector2(0.0 + fOffTwo*fWidthMod, fTexHeight1 + fOffOne*fHeightMod);
  g_Vertex[3].tex6 := D3DXVector2(0.0 - fOffTwo*fWidthMod, fTexHeight1 + fOffOne*fHeightMod);
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
  iPass, cPasses: Integer;
  matWorld: TD3DXMatrixA16;
  matView: TD3DXMatrixA16;
  matProj: TD3DXMatrixA16;
  matViewProj: TD3DXMatrixA16;
  pSceneMesh: ID3DXMesh;
  nNumObjectsInScene: Integer;
  mScene2WorldPos: array[0..2] of TD3DXVector3;
  iObject: Integer;
  matRot, matPos: TD3DXMatrixA16;
  matWorldViewProj, matWorldView: TD3DXMatrixA16;
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  // First render the world on the rendertarget g_pFullScreenTexture.
  if SUCCEEDED(g_pRenderToSurface.BeginScene(g_pFullScreenTextureSurf, @g_ViewportOffscreen)) then
  begin
    V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, g_dwBackgroundColor, 1.0, 0));

    // Get the view & projection matrix from camera
    matView := g_Camera.GetViewMatrix^;
    matProj := g_Camera.GetProjMatrix^;
    D3DXMatrixMultiply(matViewProj, matView, matProj);

    // Update focal plane
    g_pEffect.SetVector(g_hFocalPlane, g_vFocalPlane);

    // Set world render technique
    V(g_pEffect.SetTechnique(g_hTechWorldWithBlurFactor));

    // Set the mesh texture
    if (g_nCurrentScene = 1) then
    begin
      V(g_pEffect.SetTexture(g_hMeshTexture, g_pScene1MeshTexture));
      pSceneMesh := g_pScene1Mesh;
      nNumObjectsInScene := 25;
    end else
    begin
      V(g_pEffect.SetTexture(g_hMeshTexture, g_pScene2MeshTexture));
      pSceneMesh := g_pScene2Mesh;
      nNumObjectsInScene := 3;
    end;

    mScene2WorldPos[0]:= D3DXVector3(-0.5,-0.5,-0.5);
    mScene2WorldPos[1]:= D3DXVector3(1.0, 1.0, 2.0);
    mScene2WorldPos[2]:= D3DXVector3(3.0, 3.0, 5.0);

    for iObject:= 0 to nNumObjectsInScene - 1 do
    begin
      // setup the world matrix for the current world
      if (g_nCurrentScene = 1) then
      begin
        D3DXMatrixTranslation(matWorld, -(iObject mod 5)*1.0, 0.0, (iObject / 5)*3.0);
      end else
      begin
        D3DXMatrixRotationY(matRot, fTime * 0.66666);
        D3DXMatrixTranslation(matPos, mScene2WorldPos[iObject].x, mScene2WorldPos[iObject].y, mScene2WorldPos[iObject].z);
        D3DXMatrixMultiply(matWorld, matRot, matPos);
      end;

      // Update effect vars
      D3DXMatrixMultiply(matWorldViewProj, matWorld, matViewProj);
      D3DXMatrixMultiply(matWorldView, matWorld, matView);
      V(g_pEffect.SetMatrix(g_hWorld, matWorld));
      V(g_pEffect.SetMatrix(g_hWorldView, matWorldView));
      V(g_pEffect.SetMatrix(g_hWorldViewProjection, matWorldViewProj));

      // Draw the mesh on the rendertarget
      V(g_pEffect._Begin(@cPasses, 0));
      for iPass := 0 to cPasses - 1 do
      begin
        V(g_pEffect.BeginPass(iPass));
        V(pSceneMesh.DrawSubset(0));
        V(g_pEffect.EndPass);
      end;
      V(g_pEffect._End);
    end;

    V(g_pRenderToSurface.EndScene(0));
  end;

  // Clear the backbuffer
  V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET, $00000000, 1.0, 0));

  // Begin the scene, rendering to the backbuffer
  if SUCCEEDED(pd3dDevice.BeginScene) then 
  begin
    pd3dDevice.SetViewport(g_ViewportFB);

    // Set the post process technique
    case g_nShowMode of
      0: V(g_pEffect.SetTechnique(g_hTech[g_TechniqueIndex]));
      1: V(g_pEffect.SetTechnique(g_hTechShowBlurFactor));
      2: V(g_pEffect.SetTechnique(g_hTechShowUnmodified));
    end;

    // Render the fullscreen quad on to the backbuffer
    V(g_pEffect._Begin(@cPasses, 0));
    for iPass := 0 to cPasses - 1 do
    begin
      V(g_pEffect.BeginPass(iPass));
      V(pd3dDevice.SetFVF(TVertex_FVF));
      V(pd3dDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, g_Vertex, SizeOf(TVertex)));
      V(g_pEffect.EndPass);
    end;
    V(g_pEffect._End);

    V(g_HUD.OnRender(fElapsedTime));
    V(g_SampleUI.OnRender(fElapsedTime));

    // Render the text
    RenderText;

    // End the scene.
    pd3dDevice.EndScene;
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

  case g_nShowMode of                                  
    0: txtHelper.DrawFormattedTextLine('Technique: %S', [g_TechniqueNames[g_TechniqueIndex]]);
    1: txtHelper.DrawTextLine('Technique: ShowBlurFactor');
    2: txtHelper.DrawTextLine('Technique: ShowUnmodified');
  end;

  txtHelper.DrawFormattedTextLine('Focal Plane: (%0.1f,%0.1f,%0.1f,%0.1f)',
    [g_vFocalPlane.x, g_vFocalPlane.y, g_vFocalPlane.z, g_vFocalPlane.w]);

  // Draw help
  if g_bShowHelp then
  begin
    pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
    txtHelper.SetInsertionPos(2, pd3dsdBackBuffer.Height-15*6);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
    txtHelper.DrawTextLine('Controls (F1 to hide):');

    txtHelper.SetInsertionPos(20, pd3dsdBackBuffer.Height-15*5);
    txtHelper.DrawTextLine('Look: Left drag mouse'#10+
                           'Move: A,W,S,D or Arrow Keys'#10+
                           'Move up/down: Q,E or PgUp,PgDn'#10+
                           'Reset camera: Home'#10);
  end else
  begin
    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
    txtHelper.DrawTextLine('Press F1 for help');
  end;
  txtHelper._End;
  txtHelper.Free;
end;


//--------------------------------------------------------------------------------------
// Before handling window messages, the sample framework passes incoming windows 
// messages to the application through this callback function. If the application sets 
// *pbNoFurtherProcessing to TRUE, then the sample framework will not process this message.
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


//--------------------------------------------------------------------------------------
// Handles the GUI events
//--------------------------------------------------------------------------------------
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
var
  OriginalTechnique: DWORD;
  hTech: TD3DXHandle;
  sz: array[0..99] of WideChar; 
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;

    IDC_CHANGE_TECHNIQUE:
    begin
      OriginalTechnique := g_TechniqueIndex;
      repeat
        Inc(g_TechniqueIndex);

        if (g_TechniqueIndex = g_TechniqueCount) then g_TechniqueIndex := 0;

        hTech := g_pEffect.GetTechniqueByName(g_TechniqueNames[g_TechniqueIndex]);
        if SUCCEEDED(g_pEffect.ValidateTechnique(hTech)) then Break;
      until (OriginalTechnique = g_TechniqueIndex);

      UpdateTechniqueSpecificVariables(DXUTGetBackBufferSurfaceDesc^);
    end;

    IDC_CHANGE_SCENE:
    begin
      g_nCurrentScene := g_nCurrentScene mod 2;
      Inc(g_nCurrentScene);

      case g_nCurrentScene of
        1:
        begin
          // D3DXVECTOR3 vecEye(0.75f, 0.8, -2.3);
          // D3DXVECTOR3 vecAt (0.2f, 0.75, -1.5);
          g_Camera.SetViewParams(D3DXVector3(0.75, 0.8, -2.3), D3DXVector3(0.2, 0.75, -1.5));
        end;

        2:
        begin
          // D3DXVECTOR3 vecEye(0.0, 0.0, -3.0);
          // D3DXVECTOR3 vecAt (0.0, 0.0, 0.0);
          g_Camera.SetViewParams(D3DXVector3(0.0, 0.0, -3.0), D3DXVector3(0.0, 0.0, 0.0));
        end;
      end;
    end;

    IDC_CHANGE_FOCAL:
    begin
      g_vFocalPlane.w := -g_SampleUI.GetSlider(IDC_CHANGE_FOCAL).Value / 10.0;
      StringCchFormat(sz, 100, 'Focal Distance: %0.2f', [-g_vFocalPlane.w]);
      g_SampleUI.GetStatic(IDC_CHANGE_FOCAL_STATIC).Text := sz;
      UpdateTechniqueSpecificVariables(DXUTGetBackBufferSurfaceDesc^);
    end;

    IDC_SHOW_NORMAL:    g_nShowMode := 0;
    IDC_SHOW_BLUR:      g_nShowMode := 1;
    IDC_SHOW_UNBLURRED: g_nShowMode := 2;

    IDC_CHANGE_BLUR:
    begin
      g_fBlurConst := g_SampleUI.GetSlider(IDC_CHANGE_BLUR).Value / 10.0;
      StringCchFormat(sz, 100, 'Blur Factor: %0.2f', [g_fBlurConst]);
      g_SampleUI.GetStatic(IDC_CHANGE_BLUR_STATIC).Text := sz;
      UpdateTechniqueSpecificVariables(DXUTGetBackBufferSurfaceDesc^);
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
procedure OnLostDevice(pUserContext: Pointer); stdcall;
begin
  g_DialogResourceManager.OnLostDevice;
  g_SettingsDlg.OnLostDevice;
  if (g_pFont <> nil) then g_pFont.OnLostDevice;
  if (g_pEffect <> nil) then g_pEffect.OnLostDevice;
  SAFE_RELEASE(g_pTextSprite);
  SAFE_RELEASE(g_pFullScreenTextureSurf);
  SAFE_RELEASE(g_pFullScreenTexture);
  SAFE_RELEASE(g_pRenderToSurface);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has
// been destroyed, which generally happens as a result of application termination or
// windowed/full screen toggles. Resources created in the OnCreateDevice callback
// should be released here, which generally includes all D3DPOOL_MANAGED resources.
//--------------------------------------------------------------------------------------
procedure OnDestroyDevice(pUserContext: Pointer); stdcall;
begin
  g_DialogResourceManager.OnDestroyDevice;
  g_SettingsDlg.OnDestroyDevice;
  SAFE_RELEASE(g_pEffect);
  SAFE_RELEASE(g_pFont);

  SAFE_RELEASE(g_pFullScreenTextureSurf);
  SAFE_RELEASE(g_pFullScreenTexture);
  SAFE_RELEASE(g_pRenderToSurface);

  SAFE_RELEASE(g_pScene1Mesh);
  SAFE_RELEASE(g_pScene1MeshTexture);
  SAFE_RELEASE(g_pScene2Mesh);
  SAFE_RELEASE(g_pScene2MeshTexture);
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

