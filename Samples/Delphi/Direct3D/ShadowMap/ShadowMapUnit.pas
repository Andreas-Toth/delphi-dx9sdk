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
 *  $Id: ShadowMapUnit.pas,v 1.19 2007/02/05 22:21:11 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: ShadowMap.cpp
//
// Starting point for new Direct3D applications
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit ShadowMapUnit;

interface

uses
  Windows, Messages, SysUtils,
  DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTmesh, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders

const
  SHADOWMAP_SIZE = 512;

const
  HELPTEXTCOLOR: TD3DXColor = (r: 0.0; g:1.0; b:0.3; a:1.0);

const
  //todo: Probably convert this back to PAnsiChar when FPC with mine bug-fixes will be out
  g_aszMeshFile: array[0..13] of PWideChar =
  (
    'room.x',
    'airplane\airplane 2.x',
    'misc\car.x',
    'misc\sphere.x',
    'UI\arrow.x',
    'UI\arrow.x',
    'UI\arrow.x',
    'UI\arrow.x',
    'UI\arrow.x',
    'UI\arrow.x',
    'UI\arrow.x',
    'UI\arrow.x',
    'ring.x',
    'ring.x'
  );

  NUM_OBJ = High(g_aszMeshFile) + 1; 

  g_amInitObjWorld: array[0..NUM_OBJ-1] of TD3DXMATRIXA16 =
  (
    (m: ((3.5, 0.0, 0.0, 0.0), (0.0, 3.0, 0.0, 0.0), (0.0, 0.0, 3.5, 0.0), (0.0, 0.0, 0.0, 1.0)) ),
    (m: ((0.43301, 0.25, 0.0, 0.0), (-0.25, 0.43301, 0.0, 0.0), (0.0, 0.0, 0.5, 0.0), (5.0, 1.33975, 0.0, 1.0)) ),
    (m: ((0.8, 0.0, 0.0, 0.0), (0.0, 0.8, 0.0, 0.0), (0.0, 0.0, 0.8, 0.0), (-14.5, -7.1, 0.0, 1.0)) ),
    (m: ((2.0, 0.0, 0.0, 0.0), (0.0, 2.0, 0.0, 0.0), (0.0, 0.0, 2.0, 0.0), (0.0, -7.0, 0.0, 1.0)) ),
    (m: ((5.5, 0.0, 0.0, 0.0), (0.0, 0.0, 5.5, 0.0), (0.0, -9.0, 0.0, 0.0), (5.0, 0.2, 5.0, 1.0)) ),
    (m: ((5.5, 0.0, 0.0, 0.0), (0.0, 0.0, 5.5, 0.0), (0.0, -9.0, 0.0, 0.0), (5.0, 0.2, -5.0, 1.0)) ),
    (m: ((5.5, 0.0, 0.0, 0.0), (0.0, 0.0, 5.5, 0.0), (0.0, -9.0, 0.0, 0.0), (-5.0, 0.2, 5.0, 1.0)) ),
    (m: ((5.5, 0.0, 0.0, 0.0), (0.0, 0.0, 5.5, 0.0), (0.0, -9.0, 0.0, 0.0), (-5.0, 0.2, -5.0, 1.0)) ),
    (m: ((5.5, 0.0, 0.0, 0.0), (0.0, 0.0, 5.5, 0.0), (0.0, -9.0, 0.0, 0.0), (14.0, 0.2, 14.0, 1.0)) ),
    (m: ((5.5, 0.0, 0.0, 0.0), (0.0, 0.0, 5.5, 0.0), (0.0, -9.0, 0.0, 0.0), (14.0, 0.2, -14.0, 1.0)) ),
    (m: ((5.5, 0.0, 0.0, 0.0), (0.0, 0.0, 5.5, 0.0), (0.0, -9.0, 0.0, 0.0), (-14.0, 0.2, 14.0, 1.0)) ),
    (m: ((5.5, 0.0, 0.0, 0.0), (0.0, 0.0, 5.5, 0.0), (0.0, -9.0, 0.0, 0.0), (-14.0, 0.2, -14.0, 1.0)) ),
    (m: ((0.9, 0.0, 0.0, 0.0), (0.0, 0.9, 0.0, 0.0), (0.0, 0.0, 0.9, 0.0), (-14.5, -9.0, 0.0, 1.0)) ),
    (m: ((0.9, 0.0, 0.0, 0.0), (0.0, 0.9, 0.0, 0.0), (0.0, 0.0, 0.9, 0.0), (14.5, -9.0, 0.0, 1.0)) )
  );


  g_aVertDecl: array[0..3] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0;  _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITION; UsageIndex: 0),
    (Stream: 0; Offset: 12; _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_NORMAL;   UsageIndex: 0),
    (Stream: 0; Offset: 24; _Type: D3DDECLTYPE_FLOAT2; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TEXCOORD; UsageIndex: 0),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );


type

  //-----------------------------------------------------------------------------
  // Name: class TObj
  // Desc: Encapsulates a mesh object in the scene by grouping its world matrix
  //       with the mesh.
  //-----------------------------------------------------------------------------
  CObj = class
    m_Mesh: CDXUTMesh;
    m_mWorld: TD3DXMatrixA16;

    constructor Create;
    destructor Destroy; override;
  end;




  //-----------------------------------------------------------------------------
  // Name: class CViewCamera
  // Desc: A camera class derived from CFirstPersonCamera.  The arrow keys and
  //       numpad keys are disabled for this type of camera.
  //-----------------------------------------------------------------------------
  CViewCamera = class(CFirstPersonCamera)
  protected
    function MapKey(nKey: LongWord): TD3DUtil_CameraKeys; override;
  end;




  //-----------------------------------------------------------------------------
  // Name: class CLightCamera
  // Desc: A camera class derived from CFirstPersonCamera.  The letter keys
  //       are disabled for this type of camera.  This class is intended for use
  //       by the spot light.
  //-----------------------------------------------------------------------------
  CLightCamera = class(CFirstPersonCamera)
  protected
    function MapKey(nKey: LongWord): TD3DUtil_CameraKeys; override;
  end;


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont: ID3DXFont;                       // Font for drawing text
  g_pFontSmall: ID3DXFont;                  // Font for drawing text
  g_pTextSprite: ID3DXSprite;               // Sprite for batching draw text calls
  g_pEffect: ID3DXEffect;                   // D3DX effect interface
  g_bShowHelp: Boolean = True;              // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg;           // Device settings dialog
  g_HUD: CDXUTDialog;                       // dialog for standard controls
//todo: Fill Bug report - g_VCamera and g_LCamera should be custom cameras?
  g_VCamera: CFirstPersonCamera;            // View camera
  g_LCamera: CFirstPersonCamera;            // Camera obj to help adjust light
  g_Obj: array[0..NUM_OBJ-1] of CObj;       // Scene object meshes
  g_pVertDecl: IDirect3DVertexDeclaration9; // Vertex decl for the sample
  g_pTexDef: IDirect3DTexture9;             // Default texture for objects
  g_Light: TD3DLight9;                      // The spot light in the scene
  g_LightMesh: CDXUTMesh;
  g_pShadowMap: IDirect3DTexture9;          // Texture to which the shadow map is rendered
  g_pDSShadow: IDirect3DSurface9;           // Depth-stencil buffer for rendering to shadow map
  g_fLightFov: Single;                      // FOV of the spot light (in radian)
  g_mShadowProj: TD3DXMatrixA16;            // Projection matrix for shadow map

  g_bRightMouseDown: Boolean = False;       // Indicates whether right mouse button is held
  g_bCameraPerspective: Boolean = True;     // Indicates whether we should render view from
                                            // the camera's or the light's perspective
  g_bFreeLight: Boolean = True;             // Whether the light is freely moveable.


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN = 1;
  IDC_TOGGLEREF        = 3;
  IDC_CHANGEDEVICE     = 4;
  IDC_CHECKBOX         = 5;
  IDC_LIGHTPERSPECTIVE = 6;
  IDC_ATTACHLIGHTTOCAR = 7;



//--------------------------------------------------------------------------------------
// Forward declarations
//--------------------------------------------------------------------------------------
procedure InitializeDialogs;
function IsDeviceAcceptable(const pCaps: TD3DCaps9; AdapterFormat, BackBufferFormat: TD3DFormat; bWindowed: Boolean; pUserContext: Pointer): Boolean; stdcall;
function ModifyDeviceSettings(var pDeviceSettings: TDXUTDeviceSettings; const pCaps: TD3DCaps9; pUserContext: Pointer): Boolean; stdcall;
function OnCreateDevice(const pd3dDevice: IDirect3DDevice9; const pBackBufferSurfaceDesc: TD3DSurfaceDesc; pUserContext: Pointer): HRESULT; stdcall;
function OnResetDevice(const pd3dDevice: IDirect3DDevice9; const pBackBufferSurfaceDesc: TD3DSurfaceDesc; pUserContext: Pointer): HRESULT; stdcall;
procedure OnFrameMove(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
procedure RenderText;
function MsgProc(hWnd: HWND; uMsg: LongWord; wParam: WPARAM; lParam: LPARAM; out pbNoFurtherProcessing: Boolean; pUserContext: Pointer): LRESULT; stdcall;
procedure KeyboardProc(nChar: LongWord; bKeyDown, bAltDown: Boolean; pUserContext: Pointer); stdcall;
procedure MouseProc(bLeftButtonDown, bRightButtonDown, bMiddleButtonDown, bSideButton1Down, bSideButton2Down: Boolean; nMouseWheelDelta, xPos, yPos: Integer; pUserContext: Pointer); stdcall;
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
procedure OnLostDevice(pUserContext: Pointer); stdcall;
procedure OnDestroyDevice(pUserContext: Pointer); stdcall;
procedure RenderScene(pd3dDevice: IDirect3DDevice9; bRenderShadow: Boolean; fElapsedTime: Single; const pmView: TD3DXMatrix; const pmProj: TD3DXMatrix);

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;


implementation



//--------------------------------------------------------------------------------------
// Sets up the dialogs
//--------------------------------------------------------------------------------------
procedure InitializeDialogs;
var
  iY: Integer;
begin
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent);
  iY := 10;    g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 35, iY, 125, 22, VK_F2);
  Inc(iY, 24); g_HUD.AddCheckBox(IDC_CHECKBOX, 'Display help text', 35, iY, 125, 22, True, VK_F1);
  Inc(iY, 24); g_HUD.AddCheckBox(IDC_LIGHTPERSPECTIVE, 'View from light''s perspective', 0, iY, 160, 22, False, Ord('V'));
  Inc(iY, 24); g_HUD.AddCheckBox(IDC_ATTACHLIGHTTOCAR, 'Attach light to car', 0, iY, 160, 22, False, Ord('F'));
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
                   D3DRTYPE_TEXTURE, BackBufferFormat)) then Exit;

  // Must support pixel shader 2.0
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2, 0)) then Exit;

  // need to support D3DFMT_R32F render target
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                   AdapterFormat, D3DUSAGE_RENDERTARGET,
                   D3DRTYPE_CUBETEXTURE, D3DFMT_R32F)) then Exit;

  // need to support D3DFMT_A8R8G8B8 render target
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                   AdapterFormat, D3DUSAGE_RENDERTARGET,
                   D3DRTYPE_CUBETEXTURE, D3DFMT_A8R8G8B8)) then Exit;

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
  // Turn vsync off
  pDeviceSettings.pp.PresentationInterval := D3DPRESENT_INTERVAL_IMMEDIATE;
  g_SettingsDlg.DialogControl.GetComboBox(DXUTSETTINGSDLG_PRESENT_INTERVAL).Enabled := False;

  // If device doesn't support HW T&L or doesn't support 1.1 vertex shaders in HW
  // then switch to SWVP.
  if (pCaps.DevCaps and D3DDEVCAPS_HWTRANSFORMANDLIGHT = 0) or
     (pCaps.VertexShaderVersion < D3DVS_VERSION(1,1))
  then pDeviceSettings.BehaviorFlags := D3DCREATE_SOFTWARE_VERTEXPROCESSING
  else pDeviceSettings.BehaviorFlags := D3DCREATE_HARDWARE_VERTEXPROCESSING;

  // This application is designed to work on a pure device by not using
  // IDirect3D9::Get*() methods, so create a pure device if supported and using HWVP.
  if (pCaps.DevCaps and D3DDEVCAPS_PUREDEVICE <> 0) and
     (pDeviceSettings.BehaviorFlags and D3DCREATE_HARDWARE_VERTEXPROCESSING <> 0)
  then pDeviceSettings.BehaviorFlags := pDeviceSettings.BehaviorFlags or D3DCREATE_PUREDEVICE;

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
  dwShaderFlags: DWORD;
  str: array [0..MAX_PATH-1] of WideChar;
  i: Integer;
  mIdent: TD3DXMatrixA16;
begin
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  // Initialize the font
  Result := D3DXCreateFont(pd3dDevice, 15, 0, FW_BOLD, 1, FALSE, DEFAULT_CHARSET,
                           OUT_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE,
                           'Arial', g_pFont);
  if Failed(Result) then Exit;
  Result := D3DXCreateFont(pd3dDevice, 12, 0, FW_BOLD, 1, FALSE, DEFAULT_CHARSET,
                           OUT_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE,
                           'Arial', g_pFontSmall);
  if Failed(Result) then Exit;

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
  Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, WideString('ShadowMap.fx'));
  if Failed(Result) then Exit;

  // If this fails, there should be debug output as to 
  // they the .fx file failed to compile
  Result := D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags,
                                      nil, g_pEffect, nil);
  if Failed(Result) then Exit;

  // Create vertex declaration
  Result := pd3dDevice.CreateVertexDeclaration(@g_aVertDecl, g_pVertDecl);
  if Failed(Result) then Exit;

  // Initialize the meshes
  for i := 0 to NUM_OBJ - 1 do
  begin
    Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, g_aszMeshFile[i]);
    if Failed(Result) then Exit;
    if FAILED(g_Obj[i].m_Mesh.CreateMesh(pd3dDevice, str)) then
    begin
      Result:= DXUTERR_MEDIANOTFOUND;
      Exit;
    end;
    Result:= g_Obj[i].m_Mesh.SetVertexDecl(pd3dDevice, @g_aVertDecl);
    if Failed(Result) then Exit;
    g_Obj[i].m_mWorld := g_amInitObjWorld[i];
  end;

  // Initialize the light mesh
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, WideString('spotlight.x'));
  if Failed(Result) then Exit;
  if FAILED(g_LightMesh.CreateMesh(pd3dDevice, str)) then
  begin
    Result:= DXUTERR_MEDIANOTFOUND;
    Exit;
  end;
  Result:= g_LightMesh.SetVertexDecl(pd3dDevice, @g_aVertDecl);
  if Failed(Result) then Exit;

  // World transform to identity
  D3DXMatrixIdentity(mIdent);
  Result:= pd3dDevice.SetTransform(D3DTS_WORLD, mIdent);
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
  fAspectRatio: Single;
  lr: TD3DLockedRect;
  i: Integer;
  d3dSettings: TDXUTDeviceSettings;
  pControl: CDXUTControl;
begin
  Result:= g_DialogResourceManager.OnResetDevice;
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnResetDevice;
  if V_Failed(Result) then Exit;

  if Assigned(g_pFont) then
  begin
    Result:= g_pFont.OnResetDevice;
    if Failed(Result) then Exit;
  end;

  if Assigned(g_pFontSmall) then
  begin
    Result:= g_pFontSmall.OnResetDevice;
    if Failed(Result) then Exit;
  end;
  if Assigned(g_pEffect) then
  begin
    Result:= g_pEffect.OnResetDevice;
    if Failed(Result) then Exit;
  end;

  // Create a sprite to help batch calls when drawing many lines of text
  Result:= D3DXCreateSprite(pd3dDevice, g_pTextSprite);
  if Failed(Result) then Exit;

  // Setup the camera's projection parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_VCamera.SetProjParams(D3DX_PI/4, fAspectRatio, 0.1, 100.0);
  g_LCamera.SetProjParams(D3DX_PI/4, fAspectRatio, 0.1, 100.0);

  // Create the default texture (used when a triangle does not use a texture)
  Result:= pd3dDevice.CreateTexture(1, 1, 1, D3DUSAGE_DYNAMIC, D3DFMT_A8R8G8B8, D3DPOOL_DEFAULT, g_pTexDef, nil);
  if Failed(Result) then Exit;
  Result:= g_pTexDef.LockRect(0, lr, nil, 0);
  if Failed(Result) then Exit;
  PDWORD(lr.pBits)^ := D3DCOLOR_RGBA(255, 255, 255, 255);
  Result:= g_pTexDef.UnlockRect(0);
  if Failed(Result) then Exit;

  // Restore the scene objects
  for i := 0 to NUM_OBJ - 1 do
  begin
    Result:= g_Obj[i].m_Mesh.RestoreDeviceObjects(pd3dDevice);
    if Failed(Result) then Exit;
  end;
  Result:= g_LightMesh.RestoreDeviceObjects(pd3dDevice);
  if Failed(Result) then Exit;

  // Restore the effect variables
  Result:= g_pEffect.SetVector('g_vLightDiffuse', PD3DXVector4(@g_Light.Diffuse)^);
  if Failed(Result) then Exit;
  Result:= g_pEffect.SetFloat('g_fCosTheta', Cos(g_Light.Theta));
  if Failed(Result) then Exit;

  // Create the shadow map texture
  Result:= pd3dDevice.CreateTexture(SHADOWMAP_SIZE, SHADOWMAP_SIZE,
                                    1, D3DUSAGE_RENDERTARGET,
                                    D3DFMT_R32F,
                                    D3DPOOL_DEFAULT,
                                    g_pShadowMap,
                                    nil);
  if Failed(Result) then Exit;

  // Create the depth-stencil buffer to be used with the shadow map
  // We do this to ensure that the depth-stencil buffer is large
  // enough and has correct multisample type/quality when rendering
  // the shadow map.  The default depth-stencil buffer created during
  // device creation will not be large enough if the user resizes the
  // window to a very small size.  Furthermore, if the device is created
  // with multisampling, the default depth-stencil buffer will not
  // work with the shadow map texture because texture render targets
  // do not support multisample.
  d3dSettings := DXUTGetDeviceSettings;
  Result:= pd3dDevice.CreateDepthStencilSurface(SHADOWMAP_SIZE,
                                                SHADOWMAP_SIZE,
                                                d3dSettings.pp.AutoDepthStencilFormat,
                                                D3DMULTISAMPLE_NONE,
                                                0,
                                                True,
                                                g_pDSShadow,
                                                nil);
  if Failed(Result) then Exit;

  // Initialize the shadow projection matrix
  D3DXMatrixPerspectiveFovLH(g_mShadowProj, g_fLightFov, 1, 0.01, 100.0);

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, pBackBufferSurfaceDesc.Height);
  pControl := g_HUD.GetControl(IDC_LIGHTPERSPECTIVE);
  if Assigned(pControl) then pControl.SetLocation(0, pBackBufferSurfaceDesc.Height - 50);
  pControl := g_HUD.GetControl(IDC_ATTACHLIGHTTOCAR);
  if Assigned(pControl) then pControl.SetLocation(0, pBackBufferSurfaceDesc.Height - 25);
  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called once at the beginning of every frame. This is the
// best location for your application to handle updates to the scene, but is not 
// intended to contain actual rendering calls, which should instead be placed in the 
// OnFrameRender callback.  
//--------------------------------------------------------------------------------------
procedure OnFrameMove(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  m: TD3DXMatrixA16;
  vR: TD3DXVector3;
begin
  // Update the camera's position based on user input
  g_VCamera.FrameMove(fElapsedTime);
  g_LCamera.FrameMove(fElapsedTime);

  // Animate the plane, car and sphere meshes
  D3DXMatrixRotationY(m, D3DX_PI * fElapsedTime / 4.0);
  D3DXMatrixMultiply(g_Obj[1].m_mWorld, g_Obj[1].m_mWorld, m);
  D3DXMatrixRotationY(m, -D3DX_PI * fElapsedTime / 4.0);
  D3DXMatrixMultiply(g_Obj[2].m_mWorld, g_Obj[2].m_mWorld, m);
  vR:= D3DXVector3(0.1, 1.0, -0.2);
  D3DXMatrixRotationAxis(m, vR, -D3DX_PI * fElapsedTime / 6.0);
  D3DXMatrixMultiply(g_Obj[3].m_mWorld, m, g_Obj[3].m_mWorld);
end;


//--------------------------------------------------------------------------------------
// Renders the scene onto the current render target using the current
// technique in the effect.
//--------------------------------------------------------------------------------------
procedure RenderScene(pd3dDevice: IDirect3DDevice9; bRenderShadow: Boolean; fElapsedTime: Single; const pmView: TD3DXMatrix; const pmProj: TD3DXMatrix);
var
  v3: TD3DXVector3;
  v4: TD3DXVector4;
  m: TD3DXMatrixA16;
  v9: TD3DXVector4;
  vPos: TD3DXVector4;
  obj: Integer;
  mWorldView: TD3DXMatrixA16;
  pMesh: ID3DXMesh;
  cPass: LongWord;
  i, p: Integer;
  vDif: TD3DXVector4;
begin
  // Set the projection matrix
  V(g_pEffect.SetMatrix('g_mProj', pmProj));

  // Update the light parameters in the effect
  if g_bFreeLight then
  begin
    // Freely moveable light. Get light parameter
    // from the light camera.
    v3 := g_LCamera.GetEyePt^;
    D3DXVec3Transform(v4, v3, pmView);
    V(g_pEffect.SetVector('g_vLightPos', v4));
    PD3DXVector3(@v4)^ := g_LCamera.GetWorldAhead^;
    v4.w := 0.0;  // Set w 0 so that the translation part doesn't come to play
    D3DXVec4Transform(v4, v4, pmView);  // Direction in view space
    D3DXVec3Normalize(PD3DXVector3(@v4)^, PD3DXVector3(@v4)^);
    V(g_pEffect.SetVector('g_vLightDir', v4));
  end else
  begin
    // Light attached to car.  Get the car's world position and direction.
    m := g_Obj[2].m_mWorld;
    v3 := D3DXVector3(m._41, m._42, m._43);
    D3DXVec3Transform(vPos, v3, pmView);
    v4 := D3DXVector4(0.0, 0.0, -1.0, 1.0 );  // In object space, car is facing -Z
    m._41 := 0.0; m._42 := 0.0; m._43 := 0.0;  // Remove the translation
    D3DXVec4Transform(v4, v4, m);  // Obtain direction in world space
    v4.w := 0.0;  // Set w 0 so that the translation part doesn't come to play
    D3DXVec4Transform(v4, v4, pmView);  // Direction in view space
    D3DXVec3Normalize(PD3DXVector3(@v4)^, PD3DXVector3(@v4)^);
    V(g_pEffect.SetVector('g_vLightDir', v4));
    // vPos += v4 * 4.0f;  // Offset the center by 3 so that it's closer to the headlight.
    D3DXVec4Scale(v9, v4, 4.0);
    D3DXVec4Add(vPos, vPos, v9);
    V(g_pEffect.SetVector('g_vLightPos', vPos));
  end;

  // Clear the render buffers
  V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER,
                      $000000ff, 1.0, 0));

  if bRenderShadow then V(g_pEffect.SetTechnique('RenderShadow'));

  // Begin the scene
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    if not bRenderShadow then V(g_pEffect.SetTechnique('RenderScene'));

    // Render the objects
    for obj := 0 to NUM_OBJ - 1 do
    begin
      mWorldView := g_Obj[obj].m_mWorld;
      D3DXMatrixMultiply(mWorldView, mWorldView, pmView);
      V(g_pEffect.SetMatrix('g_mWorldView', mWorldView ));

      pMesh := g_Obj[obj].m_Mesh.Mesh;
      V(g_pEffect._Begin(@cPass, 0));
      for p := 0 to cPass - 1 do
      begin
        V(g_pEffect.BeginPass(p));

        for i := 0 to g_Obj[obj].m_Mesh.m_dwNumMaterials - 1 do
        begin
          vDif := D3DXVector4(g_Obj[obj].m_Mesh.m_pMaterials[i].Diffuse.r,
                              g_Obj[obj].m_Mesh.m_pMaterials[i].Diffuse.g,
                              g_Obj[obj].m_Mesh.m_pMaterials[i].Diffuse.b,
                              g_Obj[obj].m_Mesh.m_pMaterials[i].Diffuse.a);
          V(g_pEffect.SetVector('g_vMaterial', vDif));
          if (g_Obj[obj].m_Mesh.m_pTextures[i] <> nil)
            then V(g_pEffect.SetTexture('g_txScene', g_Obj[obj].m_Mesh.m_pTextures[i]))
            else V(g_pEffect.SetTexture('g_txScene', g_pTexDef));
          V(g_pEffect.CommitChanges);
          V(pMesh.DrawSubset(i));
        end;
        V(g_pEffect.EndPass);
      end;
      V(g_pEffect._End);
    end;

    // Render light
    if not bRenderShadow then V(g_pEffect.SetTechnique('RenderLight'));

    mWorldView := g_LCamera.GetWorldMatrix^;
    D3DXMatrixMultiply(mWorldView, mWorldView, pmView);
    V(g_pEffect.SetMatrix('g_mWorldView', mWorldView));

    pMesh := g_LightMesh.Mesh;
    V(g_pEffect._Begin(@cPass, 0));
    for p := 0 to cPass - 1 do
    begin
      V(g_pEffect.BeginPass(p));

      for i := 0 to g_LightMesh.m_dwNumMaterials - 1 do
      begin
        vDif := D3DXVector4(g_LightMesh.m_pMaterials[i].Diffuse.r,
                            g_LightMesh.m_pMaterials[i].Diffuse.g,
                            g_LightMesh.m_pMaterials[i].Diffuse.b,
                            g_LightMesh.m_pMaterials[i].Diffuse.a);
        V(g_pEffect.SetVector('g_vMaterial', vDif));
        V(g_pEffect.SetTexture('g_txScene', g_LightMesh.m_pTextures[i]));
        V(g_pEffect.CommitChanges);
        V(pMesh.DrawSubset(i));
      end;
      V(g_pEffect.EndPass);
    end;
    V(g_pEffect._End);

    if not bRenderShadow then RenderText; // Render stats and help text

    // Render the UI elements
    if not bRenderShadow then g_HUD.OnRender(fElapsedTime);

    V(pd3dDevice.EndScene);
  end;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called at the end of every frame to perform all the 
// rendering calls for the scene, and it will also be called if the window needs to be 
// repainted. After this function has returned, DXUT will call 
// IDirect3DDevice9::Present to display the contents of the next buffer in the swap chain
//--------------------------------------------------------------------------------------
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  mLightView: TD3DXMatrixA16;
  vPos, vUp: TD3DXVector3;
  vDir: TD3DXVector4;
  pOldRT: IDirect3DSurface9;
  pShadowSurf: IDirect3DSurface9;
  pOldDS: IDirect3DSurface9;
  pmView: PD3DXMatrix;
  mViewToLightProj: TD3DXMatrixA16;
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  //
  // Compute the view matrix for the light
  // This changes depending on the light mode
  // (free movement or attached)
  //
  if g_bFreeLight then mLightView := g_LCamera.GetViewMatrix^
  else
  begin
    // Light attached to car.
    mLightView := g_Obj[2].m_mWorld;
    vPos := D3DXVector3(mLightView._41, mLightView._42, mLightView._43);  // Offset z by -2 so that it's closer to headlight
    vDir := D3DXVector4(0.0, 0.0, -1.0, 1.0);  // In object space, car is facing -Z
    mLightView._41 := 0.0; mLightView._42 := 0.0; mLightView._43 := 0.0;  // Remove the translation
    D3DXVec4Transform(vDir, vDir, mLightView);  // Obtain direction in world space
    vDir.w := 0.0;  // Set w 0 so that the translation part below doesn't come to play
    D3DXVec4Normalize(vDir, vDir);
    vPos.x := vPos.x + vDir.x * 4.0;  // Offset the center by 4 so that it's closer to the headlight
    vPos.y := vPos.y + vDir.y * 4.0;
    vPos.z := vPos.x + vDir.z * 4.0;
    vDir.x := vDir.x + vPos.x;  // vDir denotes the look-at point
    vDir.y := vDir.y + vPos.y;
    vDir.z := vDir.z + vPos.z;
    vUp := D3DXVector3(0.0, 1.0, 0.0);
    D3DXMatrixLookAtLH(mLightView, vPos, PD3DXVector3(@vDir)^, vUp);
  end;

  //
  // Render the shadow map
  //
  V(pd3dDevice.GetRenderTarget(0, pOldRT));
  if SUCCEEDED(g_pShadowMap.GetSurfaceLevel(0, pShadowSurf)) then
  begin
    pd3dDevice.SetRenderTarget(0, pShadowSurf);
    SAFE_RELEASE(pShadowSurf);
  end;

  if SUCCEEDED(pd3dDevice.GetDepthStencilSurface(pOldDS)) then
    pd3dDevice.SetDepthStencilSurface(g_pDSShadow);

  try
    DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'Shadow Map'); // g:= CDXUTPerfEventGenerator.( DXUT_PERFEVENTCOLOR, L"Shadow Map");
    RenderScene(pd3dDevice, True, fElapsedTime, mLightView, g_mShadowProj);
  finally
    DXUT_EndPerfEvent;
  end;

  if (pOldDS <> nil) then
  begin
    pd3dDevice.SetDepthStencilSurface(pOldDS);
    pOldDS := nil;
  end;
  pd3dDevice.SetRenderTarget(0, pOldRT);
  SAFE_RELEASE(pOldRT);

  //
  // Now that we have the shadow map, render the scene.
  //
  if g_bCameraPerspective
  then pmView := g_VCamera.GetViewMatrix
  else pmView := @mLightView;

  // Initialize required parameter
  V(g_pEffect.SetTexture('g_txShadow', g_pShadowMap));
  // Compute the matrix to transform from view space to
  // light projection space.  This consists of
  // the inverse of view matrix * view matrix of light * light projection matrix
  mViewToLightProj := pmView^;
  D3DXMatrixInverse(mViewToLightProj, nil, mViewToLightProj);
  D3DXMatrixMultiply(mViewToLightProj, mViewToLightProj, mLightView);
  D3DXMatrixMultiply(mViewToLightProj, mViewToLightProj, g_mShadowProj);
  V(g_pEffect.SetMatrix('g_mViewToLightProj', mViewToLightProj));

  try
    DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'Scene'); // CDXUTPerfEventGenerator g( DXUT_PERFEVENTCOLOR, L"Scene" );
    RenderScene(pd3dDevice, False, fElapsedTime, pmView^, g_VCamera.GetProjMatrix^);
  finally
    DXUT_EndPerfEvent;
  end;
  g_pEffect.SetTexture('g_txShadow', nil);
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
  txtHelper := CDXUTTextHelper.Create(g_pFont, g_pTextSprite, 15);
  try
    // Output statistics
    txtHelper._Begin;
    txtHelper.SetInsertionPos(5, 5);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));
    txtHelper.DrawTextLine(DXUTGetFrameStats(True)); // Show FPS
    txtHelper.DrawTextLine(DXUTGetDeviceStats);

    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
    
    // Draw help
    if g_bShowHelp then
    begin
      pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
      txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*10);
      txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
      txtHelper.DrawTextLine('Controls:');

      txtHelper.SetInsertionPos(15, pd3dsdBackBuffer.Height-15*9);
      txtHelper.DrawFormattedTextLine(
          'Rotate camera'#10'Move camera'#10+
          'Rotate light'#10'Move light'#10+
          'Change light mode (Current: %s)'#10'Change view reference (Current: %s)'#10+
          'Hide help'#10'Quit',
          [IfThen(g_bFreeLight, 'Free', 'Car-attached'),
           IfThen(g_bCameraPerspective, 'Camera', 'Light')]);
      txtHelper.SetInsertionPos(265, pd3dsdBackBuffer.Height-15*9);
      txtHelper.DrawTextLine(
          'Left drag mouse'#10'W,S,A,D,Q,E'#10+
          'Right drag mouse'#10'W,S,A,D,Q,E while holding right mouse'#10+
          'F'#10'V'#10'F1'#10'ESC');
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

  pbNoFurtherProcessing := g_HUD.MsgProc(hWnd, uMsg, wParam, lParam);
  if pbNoFurtherProcessing then Exit;

  // Pass all windows messages to camera and dialogs so they can respond to user input
  if (WM_KEYDOWN <> uMsg) or g_bRightMouseDown
  then g_LCamera.HandleMessages(hWnd, uMsg, wParam, lParam);

  if (WM_KEYDOWN <> uMsg) or not g_bRightMouseDown then
  begin
    if g_bCameraPerspective
    then g_VCamera.HandleMessages(hWnd, uMsg, wParam, lParam)
    else g_LCamera.HandleMessages(hWnd, uMsg, wParam, lParam);
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
end;


procedure MouseProc(bLeftButtonDown, bRightButtonDown, bMiddleButtonDown, bSideButton1Down, bSideButton2Down: Boolean; nMouseWheelDelta, xPos, yPos: Integer; pUserContext: Pointer); stdcall;
begin
  g_bRightMouseDown := bRightButtonDown;
end;


//--------------------------------------------------------------------------------------
// Handles the GUI events
//--------------------------------------------------------------------------------------
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
var
  pCheck: CDXUTCheckBox;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;
    IDC_CHECKBOX:
    begin
      pCheck := CDXUTCheckBox(pControl);
      g_bShowHelp := pCheck.Checked;
    end;

    IDC_LIGHTPERSPECTIVE:
    begin
      pCheck := CDXUTCheckBox(pControl);
      g_bCameraPerspective := not pCheck.Checked;
      if g_bCameraPerspective then
      begin
        g_VCamera.SetRotateButtons(True, False, False);
        g_LCamera.SetRotateButtons(False, False, True);
      end else
      begin
        g_VCamera.SetRotateButtons(False, False, False);
        g_LCamera.SetRotateButtons(True, False, True);
      end;
    end;

    IDC_ATTACHLIGHTTOCAR:
    begin
      pCheck := CDXUTCheckBox(pControl);
      g_bFreeLight := not pCheck.Checked;
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
  i: Integer;
begin
  g_DialogResourceManager.OnLostDevice;
  g_SettingsDlg.OnLostDevice;
  if Assigned(g_pFont) then g_pFont.OnLostDevice;
  if Assigned(g_pFontSmall) then g_pFontSmall.OnLostDevice;
  if Assigned(g_pEffect) then g_pEffect.OnLostDevice;
  SAFE_RELEASE(g_pTextSprite);

  SAFE_RELEASE(g_pDSShadow);
  SAFE_RELEASE(g_pShadowMap);
  SAFE_RELEASE(g_pTexDef);

  for i := 0 to NUM_OBJ - 1 do
    if Assigned(g_Obj[i]) then g_Obj[i].m_Mesh.InvalidateDeviceObjects;
  if Assigned(g_LightMesh) then g_LightMesh.InvalidateDeviceObjects;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has
// been destroyed, which generally happens as a result of application termination or
// windowed/full screen toggles. Resources created in the OnCreateDevice callback
// should be released here, which generally includes all D3DPOOL_MANAGED resources.
//--------------------------------------------------------------------------------------
procedure OnDestroyDevice; stdcall;
var
  i: Integer;
begin
  g_DialogResourceManager.OnDestroyDevice;
  g_SettingsDlg.OnDestroyDevice;
  SAFE_RELEASE(g_pEffect);
  SAFE_RELEASE(g_pFont);
  SAFE_RELEASE(g_pFontSmall);
  SAFE_RELEASE(g_pVertDecl);

  SAFE_RELEASE(g_pEffect);

  for i := 0 to NUM_OBJ - 1 do
    if Assigned(g_Obj[i]) then g_Obj[i].m_Mesh.DestroyMesh;
  if Assigned(g_LightMesh) then g_LightMesh.DestroyMesh;
end;

{ CViewCamera }

function CViewCamera.MapKey(nKey: LongWord): TD3DUtil_CameraKeys;
begin
  // Provide custom mapping here.
  // Same as default mapping but disable arrow keys.
  case nKey of
    Ord('A'): Result:= CAM_STRAFE_LEFT;
    Ord('D'): Result:= CAM_STRAFE_RIGHT;
    Ord('W'): Result:= CAM_MOVE_FORWARD;
    Ord('S'): Result:= CAM_MOVE_BACKWARD;
    Ord('Q'): Result:= CAM_MOVE_DOWN;
    Ord('E'): Result:= CAM_MOVE_UP;

    VK_HOME:  Result:= CAM_RESET;
  else
    Result:= CAM_UNKNOWN;
  end;
end;

{ CLightCamera }

function CLightCamera.MapKey(nKey: LongWord): TD3DUtil_CameraKeys;
begin
  // Provide custom mapping here.
  // Same as default mapping but disable arrow keys.
  case nKey of
    VK_LEFT:    Result:= CAM_STRAFE_LEFT;
    VK_RIGHT:   Result:= CAM_STRAFE_RIGHT;
    VK_UP:      Result:= CAM_MOVE_FORWARD;
    VK_DOWN:    Result:= CAM_MOVE_BACKWARD;
    VK_PRIOR:   Result:= CAM_MOVE_UP;        // pgup
    VK_NEXT:    Result:= CAM_MOVE_DOWN;      // pgdn

    VK_NUMPAD4: Result:= CAM_STRAFE_LEFT;
    VK_NUMPAD6: Result:= CAM_STRAFE_RIGHT;
    VK_NUMPAD8: Result:= CAM_MOVE_FORWARD;
    VK_NUMPAD2: Result:= CAM_MOVE_BACKWARD;
    VK_NUMPAD9: Result:= CAM_MOVE_UP;
    VK_NUMPAD3: Result:= CAM_MOVE_DOWN;

    VK_HOME:    Result:= CAM_RESET;
  else
    Result:= CAM_UNKNOWN;
  end;
end;

{ CObj }

constructor CObj.Create;
begin
  m_Mesh:= CDXUTMesh.Create;
end;

destructor CObj.Destroy;
begin
  FreeAndNil(m_Mesh);
  inherited;
end;


procedure CreateCustomDXUTobjects;
var
  i: Integer;
  vFromPt, vLookatPt: TD3DXVector3;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_HUD:= CDXUTDialog.Create;                       // dialog for standard controls
  g_VCamera:= CFirstPersonCamera.Create;            // View camera
  g_LCamera:= CFirstPersonCamera.Create;            // Camera obj to help adjust light
  for i:= 0 to NUM_OBJ-1 do g_Obj[i]:= CObj.Create; // Scene object meshes
  g_LightMesh:= CDXUTMesh.Create;

  // Initialize the camera
  g_VCamera.SetScalers(0.01, 15.0);
  g_LCamera.SetScalers(0.01, 8.0);
  g_VCamera.SetRotateButtons(True, False, False);
  g_LCamera.SetRotateButtons(False, False, True);

  // Set up the view parameters for the camera
  vFromPt   := D3DXVector3(0.0, 5.0, -18.0);
  vLookatPt := D3DXVector3(0.0, -1.0, 0.0);
  g_VCamera.SetViewParams( vFromPt, vLookatPt);

  vFromPt := D3DXVector3(0.0, 0.0, -12.0);
  vLookatPt := D3DXVECTOR3(0.0, -2.0, 1.0);
  g_LCamera.SetViewParams(vFromPt, vLookatPt);

  // Initialize the spot light
  g_fLightFov := D3DX_PI / 2.0;

  g_Light.Diffuse.r := 1.0;
  g_Light.Diffuse.g := 1.0;
  g_Light.Diffuse.b := 1.0;
  g_Light.Diffuse.a := 1.0;
  g_Light.Position := D3DXVector3( -8.0, -8.0, 0.0);
  g_Light.Direction := D3DXVector3( 1.0, -1.0, 0.0);
  D3DXVec3Normalize(PD3DXVector3(@g_Light.Direction)^, PD3DXVector3(@g_Light.Direction)^);
  g_Light.Range := 10.0;
  g_Light.Theta := g_fLightFov / 2.0;
  g_Light.Phi := g_fLightFov / 2.0;
end;

procedure DestroyCustomDXUTobjects;
var
  i: Integer;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_HUD);
  FreeAndNil(g_VCamera);
  FreeAndNil(g_LCamera);
  for i:= 0 to NUM_OBJ-1 do FreeAndNil(g_Obj[i]); // Scene object meshes
  FreeAndNil(g_LightMesh);
end;

end.

