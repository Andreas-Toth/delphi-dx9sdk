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
 *  $Id: MultiAnimationUnit.pas,v 1.8 2007/02/05 22:21:10 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: MultiAnimation.cpp
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit MultiAnimationUnit;

interface

uses
  Windows, Classes, SysUtils, StrSafe,
  DXTypes, DirectSound, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTsound, DXUTSettingsDlg,
  MultiAnimationLib, Tiny;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders


const
  TXFILE_FLOOR = 'floor.jpg';
  FLOOR_TILECOUNT = 2;

//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont: ID3DXFont;               // Font for drawing text
  g_pTextSprite: ID3DXSprite;       // Sprite for batching draw text calls
  g_pEffect: ID3DXEffect;           // D3DX effect interface
  g_Camera: CFirstPersonCamera;     // A model viewing camera
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg;   // Device settings dialog
  g_HUD: CDXUTDialog;               // dialog for standard controls
  g_SampleUI: CDXUTDialog;          // dialog for sample specific controls
  g_pMeshFloor: ID3DXMesh;          // floor geometry
  g_mxFloor: TD3DXMatrixA16;        // floor world xform
  g_MatFloor: TD3DMaterial9;        // floor material
  g_pTxFloor: IDirect3DTexture9;    // floor texture
  g_DSound: CSoundManager;          // DirectSound class
  g_MultiAnim: CMultiAnim;          // the MultiAnim class for holding Tiny's mesh and frame hierarchy
  g_v_pCharacters: TTinyList;       // array of character objects; each can be associated with any of the CMultiAnims
  g_dwFollow: DWORD = $ffffffff;    // which character the camera should follow; 0xffffffff for static camera
  g_bShowHelp: Boolean = True;      // If true, it renders the UI control text
  g_bPlaySounds: Boolean = True;    // whether to play sounds
  g_fLastAnimTime: Double = 0.0;    // Time for the animations

  
//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_ADDTINY             = 5;
  IDC_NEXTVIEW            = 6;
  IDC_PREVVIEW            = 7;
  IDC_ENABLESOUND         = 8;
  IDC_CONTROLTINY         = 9;
  IDC_RELEASEALL          = 10;
  IDC_RESETCAMERA         = 11;
  IDC_RESETTIME           = 12;


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
procedure RenderText;

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;


implementation


//--------------------------------------------------------------------------------------
// Initialize the app
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  iY: Integer;
  vEye: TD3DXVector3;
  vAt: TD3DXVector3;
begin
  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_SampleUI.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent);
  iY := 10;    g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 35, iY, 125, 22, VK_F2);

  g_SampleUI.SetCallback(OnGUIEvent); iY := 10;
  g_SampleUI.AddButton(IDC_ADDTINY,'Add Instance', 45, iY, 120, 24);
  Inc(iY, 26); g_SampleUI.AddButton(IDC_NEXTVIEW,'(N)ext View', 45, iY, 120, 24, Ord('N'));
  Inc(iY, 26); g_SampleUI.AddButton(IDC_PREVVIEW,'(P)revious View', 45, iY, 120, 24, Ord('P'));
  Inc(iY, 26); g_SampleUI.AddButton(IDC_RESETCAMERA,'(R)eset view', 45, iY, 120, 24, Ord('R'));
  Inc(iY, 26); g_SampleUI.AddCheckBox(IDC_ENABLESOUND,'Enable sound', 25, iY, 140, 24, True);
  Inc(iY, 26); g_SampleUI.AddCheckBox(IDC_CONTROLTINY,'(C)ontrol this instance', 25, iY, 140, 24, False, Ord('C'));
  g_SampleUI.GetCheckBox(IDC_CONTROLTINY).Visible := False;
  g_SampleUI.GetCheckBox(IDC_CONTROLTINY).Enabled := False;
  Inc(iY, 26); g_SampleUI.AddButton(IDC_RELEASEALL,'Auto-control all', 45, iY, 120, 24);
  Inc(iY, 26); g_SampleUI.AddButton(IDC_RESETTIME,'Reset time', 45, iY, 120, 24);

  // Setup the camera with view matrix
  vEye := D3DXVector3(0.5, 0.55, -0.2);
  vAt  := D3DXVector3(0.5, 0.125, 0.5);
  g_Camera.SetViewParams(vEye, vAt);
  g_Camera.SetScalers(0.01, 1.0);  // Camera movement parameters
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

  // Need to support ps 2.0
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2,0)) then Exit;

  // Need to support A8R8G8B8 textures
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                                   AdapterFormat, 0,
                                   D3DRTYPE_TEXTURE, D3DFMT_A8R8G8B8))
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

  // If the hardware cannot do vertex blending, use software vertex processing.
  if (pCaps.MaxVertexBlendMatrices < 2)
  then pDeviceSettings.BehaviorFlags := D3DCREATE_SOFTWARE_VERTEXPROCESSING;

  // If using hardware vertex processing, change to mixed vertex processing
  // so there is a fallback.
  if (pDeviceSettings.BehaviorFlags and D3DCREATE_HARDWARE_VERTEXPROCESSING <> 0)
  then pDeviceSettings.BehaviorFlags := D3DCREATE_MIXED_VERTEXPROCESSING;

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
  mx: TD3DXMatrix;
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

  // Initialize floor textures
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, TXFILE_FLOOR);
  if V_Failed(Result) then Exit;
  Result:= D3DXCreateTextureFromFileW(pd3dDevice, str, g_pTxFloor);
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
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'MultiAnimation.fx');
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // they the .fx file failed to compile
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags,
                                     nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;
  g_pEffect.SetTechnique('RenderScene');

  // floor geometry transform
  D3DXMatrixRotationX(g_mxFloor, -D3DX_PI / 2.0);
  D3DXMatrixRotationY(mx, D3DX_PI / 4.0);
  D3DXMatrixMultiply(g_mxFloor, g_mxFloor, mx);
  D3DXMatrixTranslation(mx, 0.5, 0.0, 0.5);
  D3DXMatrixMultiply(g_mxFloor, g_mxFloor, mx);

  // set material for floor
  g_MatFloor.Diffuse := D3DXColor(1.0, 1.0, 1.0, 0.75);
  g_MatFloor.Ambient := D3DXColor(1.0, 1.0, 1.0, 1.0);
  g_MatFloor.Specular := D3DXColor(0.0, 0.0, 0.0, 1.0);
  g_MatFloor.Emissive := D3DXColor(0.0, 0.0, 0.0, 0.0);
  g_MatFloor.Power := 0.0;

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
  // set up MultiAnim
  sXFile: array[0..MAX_PATH-1] of WideChar;
  str: array[0..MAX_PATH-1] of WideChar;
  AH: CMultiAnimAllocateHierarchy;
  caps: TD3DCaps9;
  i: Integer;
  fAspectRatio: Single;
  pTiny: CTiny;
  pMAEffect: ID3DXEffect;
  pMesh: ID3DXMesh;
  dwNumVx: DWORD;
type
  TVx = packed record
    vPos: TD3DXVector3;
    vNorm: TD3DXVector3;
    fTex: array[0..1] of Single;
  end;
var
  pVx: ^TVx;
begin
  Result:= g_DialogResourceManager.OnResetDevice;
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnResetDevice;
  if V_Failed(Result) then Exit;

  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'MultiAnimation.fx');
  if V_Failed(Result) then Exit;
  Result:= DXUTFindDXSDKMediaFile(sXFile, MAX_PATH, 'tiny_4anim.x');
  if V_Failed(Result) then Exit;

  AH:= CMultiAnimAllocateHierarchy.Create;
  try
    AH.SetMA(g_MultiAnim);

    Result := g_MultiAnim.Setup(pd3dDevice, sXFile, str, AH);
    if V_Failed(Result) then Exit;
  finally
    AH.Free;
  end;

  // get device caps
  pd3dDevice.GetDeviceCaps(caps);

  // Select the technique that fits the shader version.
  // We could have used ValidateTechnique()/GetNextValidTechnique() to find the
  // best one, but this is convenient for our purposes.
  g_MultiAnim.SetTechnique('Skinning20');

  // Restore steps for tiny instances
  for i:= 0 to g_v_pCharacters.Count - 1 do
  begin
    g_v_pCharacters[i].RestoreDeviceObjects(pd3dDevice);
  end;

  // If there is no instance, make sure we have at least one.
  if (g_v_pCharacters.Count = 0) then
  begin
    try
      pTiny := CTiny.Create;
    except
      Result:= E_OUTOFMEMORY;
      Exit;
    end;

    {Result := }pTiny.Setup(g_MultiAnim, g_v_pCharacters, g_DSound, 0.0);
    pTiny.SetSounds(g_bPlaySounds);
  end;

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

  pMAEffect := g_MultiAnim.GetEffect;
  if Assigned(pMAEffect) then
  begin
    pMAEffect.OnResetDevice;
    pMAEffect := nil;
  end;

  // Create a sprite to help batch calls when drawing many lines of text
  Result:= D3DXCreateSprite(pd3dDevice, g_pTextSprite);
  if V_Failed(Result) then Exit;

  // Setup the camera's projection parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI/3, fAspectRatio, 0.001, 100.0);

  // set lighting
  pd3dDevice.SetRenderState(D3DRS_LIGHTING, iTrue);
  pd3dDevice.SetRenderState(D3DRS_AMBIENT, D3DCOLOR_ARGB(255, 255, 255, 255));
  pd3dDevice.LightEnable(0, True);
  pd3dDevice.SetRenderState(D3DRS_NORMALIZENORMALS, iTrue);

  // create the floor geometry
  Result := D3DXCreatePolygon(pd3dDevice, 1.2, 4, pMesh, nil);
  if V_Failed(Result) then Exit;
  Result:= pMesh.CloneMeshFVF(D3DXMESH_WRITEONLY, D3DFVF_XYZ or D3DFVF_NORMAL or D3DFVF_TEX1, pd3dDevice, g_pMeshFloor);
  if V_Failed(Result) then Exit;
  pMesh := nil;

  dwNumVx := g_pMeshFloor.GetNumVertices;

  // Initialize its texture coordinates
  Result := g_pMeshFloor.LockVertexBuffer(0, Pointer(pVx));
  if FAILED(Result) then Exit;

  for i := 0 to dwNumVx - 1 do
  begin
    if Abs(pVx.vPos.x) < 0.01 then
    begin
      if (pVx.vPos.y > 0) then
      begin
        pVx.fTex[ 0 ] := 0.0;
        pVx.fTex[ 1 ] := 0.0;
      end else
      if (pVx.vPos.y < 0.0) then
      begin
        pVx.fTex[ 0 ] := 1.0 * FLOOR_TILECOUNT;
        pVx.fTex[ 1 ] := 1.0 * FLOOR_TILECOUNT;
      end else
      begin
        pVx.fTex[ 0 ] := 0.5 * FLOOR_TILECOUNT;
        pVx.fTex[ 1 ] := 0.5 * FLOOR_TILECOUNT;
      end;
    end else
    if (pVx.vPos.x > 0.0) then
    begin
      pVx.fTex[ 0 ] := 1.0 * FLOOR_TILECOUNT;
      pVx.fTex[ 1 ] := 0.0;
    end else
    begin
      pVx.fTex[ 0 ] := 0.0;
      pVx.fTex[ 1 ] := 1.0 * FLOOR_TILECOUNT;
    end;

    Inc(pVx);
  end;

  g_pMeshFloor.UnlockVertexBuffer;

  // reset the timer
  g_fLastAnimTime := DXUTGetGlobalTimer.GetTime;

  // Adjust the dialog parameters.
  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation(pBackBufferSurfaceDesc.Width-170, pBackBufferSurfaceDesc.Height-270);
  g_SampleUI.SetSize(170, 220);

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
  i: Integer;
begin
  for i:= 0 to g_v_pCharacters.Count - 1 do
    g_v_pCharacters[i].Animate(fTime - g_fLastAnimTime);

  g_fLastAnimTime := fTime;

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
  // set up the camera
  mx, mxView, mxProj: TD3DXMatrixA16;
  vEye: TD3DXVector3;
  vLightDir: TD3DXVector3;
  pChar: CTiny;
  vCharPos: TD3DXVector3;
  vCharFacing: TD3DXVector3;
  vAt, vUp: TD3DXVector3;
  pBackBufferSurfaceDesc: PD3DSurfaceDesc;
  fAspectRatio: Single;
  pMAEffect: ID3DXEffect;
  vec: TD3DXVector4;
  i, p, cPasses: Integer;
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER,
                   D3DCOLOR_ARGB(0, $3F, $AF, $FF), 1.0, 0);

  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    // set up the camera

    // are we following a tiny, or an independent arcball camera?
    if (g_dwFollow = $ffffffff) then
    begin
      // Light direction is same as camera front (reversed)
      D3DXVec3Scale(vLightDir, g_Camera.GetWorldAhead^, -1);

      // set static transforms
      mxView := g_Camera.GetViewMatrix^;
      mxProj := g_Camera.GetProjMatrix^;
      V(pd3dDevice.SetTransform(D3DTS_VIEW, mxView));
      V(pd3dDevice.SetTransform(D3DTS_PROJECTION, mxProj));
      vEye := g_Camera.GetEyePt^;
    end else
    begin
      // set follow transforms
      pChar := g_v_pCharacters[ g_dwFollow ];

      pChar.GetPosition(vCharPos);
      pChar.GetFacing(vCharFacing);
      vEye := D3DXVector3(vCharPos.x, 0.25, vCharPos.z);
      vAt := D3DXVector3(vCharPos.x, 0.0125, vCharPos.z);
      vUp := D3DXVector3(0.0, 1.0, 0.0);
      vCharFacing.x := vCharFacing.x * 0.25;
      vCharFacing.y := 0.0;
      vCharFacing.z := vCharFacing.z * 0.25;
      // vEye -= vCharFacing;
      D3DXVec3Subtract(vEye, vEye, vCharFacing);
      // vAt += vCharFacing;
      D3DXVec3Add(vAt, vAt, vCharFacing);

      D3DXMatrixLookAtLH(mxView, vEye, vAt, vUp);
      V(pd3dDevice.SetTransform(D3DTS_VIEW, mxView));

      pBackBufferSurfaceDesc := DXUTGetBackBufferSurfaceDesc;
      fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
      D3DXMatrixPerspectiveFovLH(mxProj, D3DX_PI / 3, fAspectRatio, 0.1, 100.0);
      V(pd3dDevice.SetTransform(D3DTS_PROJECTION, mxProj));

      // Set the light direction and normalize
      D3DXVec3Subtract(vLightDir, vEye, vAt);
      D3DXVec3Normalize(vLightDir, vLightDir);
    end;

    // set view-proj
    D3DXMatrixMultiply( mx, mxView, mxProj);
    g_pEffect.SetMatrix('g_mViewProj', mx);
    pMAEffect := g_MultiAnim.GetEffect;
    if Assigned(pMAEffect) then
    begin
      pMAEffect.SetMatrix('g_mViewProj', mx);
    end;

    // Set the light direction so that the
    // visible side is lit.
    vec := D3DXVector4(vLightDir.x, vLightDir.y, vLightDir.z, 1.0);
    g_pEffect.SetVector('lhtDir', vec);
    if Assigned(pMAEffect) then pMAEffect.SetVector('lhtDir', vec);

    pMAEffect := nil;

    // set the fixed function shader for drawing the floor
    V(pd3dDevice.SetFVF(g_pMeshFloor.GetFVF));

    // Draw the floor
    V(g_pEffect.SetTexture('g_txScene', g_pTxFloor));
    V(g_pEffect.SetMatrix('g_mWorld', g_mxFloor));
    V(g_pEffect._Begin(@cPasses, 0 ));
    for p := 0 to cPasses - 1 do
    begin
      V(g_pEffect.BeginPass(p));
      V(g_pMeshFloor.DrawSubset(0));
      V(g_pEffect.EndPass);
    end;
    V(g_pEffect._End);

    // draw each tiny
    for i:= 0 to g_v_pCharacters.Count - 1 do
    with g_v_pCharacters[i] do
    begin
      // set the time to update the hierarchy
      AdvanceTime(fElapsedTime, @vEye);
      // draw the mesh
      Draw;
    end;

    //
    // Output text information
    //
    RenderText;

    V(g_HUD.OnRender(fElapsedTime));
    V(g_SampleUI.OnRender(fElapsedTime));

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
  i: Integer;
  pChar: CTiny;
  v_sReport: TStringList;
begin
  // The helper object simply helps keep track of text position, and color
  // and then it calls pFont->DrawText( m_pSprite, strMsg, -1, &rc, DT_NOCLIP, m_clr );
  // If NULL is passed in as the sprite object, then it will work fine however the
  // pFont->DrawText() will not be batched together.  Batching calls will improves perf.
  txtHelper:= CDXUTTextHelper.Create(g_pFont, g_pTextSprite, 15);
  try
    // Output statistics
    txtHelper._Begin;
    txtHelper.SetInsertionPos(2, 0);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));
    txtHelper.DrawTextLine(DXUTGetFrameStats);
    txtHelper.DrawTextLine(DXUTGetDeviceStats);

    pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;

    // Dump out the FPS and device stats
    txtHelper.SetInsertionPos(5, 37);
    txtHelper.DrawFormattedTextLine('  Time: %2.3f', [DXUTGetGlobalTimer.GetTime]);
    txtHelper.DrawFormattedTextLine('  Number of models: %d', [g_v_pCharacters.Count]);

    txtHelper.SetInsertionPos(5, 70);

    // We can only display either the behavior text or help text,
    // with the help text having priority.
    if g_bShowHelp then
    begin
      // output data for T[m_dwFollow]
      if (Integer(g_dwFollow) <> -1) then
      begin
        txtHelper.DrawTextLine('Press F1 to hide animation info'#10+
                               'Quit: Esc');

        if (g_v_pCharacters[g_dwFollow].IsUserControl) then
        begin
          txtHelper.SetInsertionPos(pd3dsdBackBuffer.Width - 150, 150);
          txtHelper.DrawTextLine('       Tiny control:'#10+
                                 'Move forward'#10+
                                 'Run forward'#10+
                                 'Turn'#10);
          txtHelper.SetInsertionPos(pd3dsdBackBuffer.Width - 55, 150);
          txtHelper.DrawTextLine(''#10+
                                 'W'#10+
                                 'Shift-W'#10+
                                 'A,D'#10);
        end;


        v_sReport:= TStringList.Create;
        try
          pChar := g_v_pCharacters[g_dwFollow];
          pChar.Report(v_sReport);
          txtHelper.SetInsertionPos(5, pd3dsdBackBuffer.Height - 115);
          for i := 0 to 5 do txtHelper.DrawTextLine(PWideChar(WideString(v_sReport[i])));
          txtHelper.DrawTextLine(PWideChar(WideString(v_sReport[16])));

          txtHelper.SetInsertionPos(210, pd3dsdBackBuffer.Height - 85);
          for i := 6 to 10 do txtHelper.DrawTextLine(PWideChar(WideString(v_sReport[i])));

          txtHelper.SetInsertionPos(370, pd3dsdBackBuffer.Height - 85);
          for i := 11 to 15 do txtHelper.DrawTextLine(PWideChar(WideString(v_sReport[i])));
        finally
          FreeAndNil(v_sReport);
        end;
      end else
        txtHelper.DrawTextLine(''#10+
                               'Quit: Esc');
    end else
    begin
      if (g_dwFollow <> $ffffffff)
      then txtHelper.DrawTextLine('Press F1 to display animation info'#10+
                                  'Quit: Esc')
      else txtHelper.DrawTextLine(''#10+
                                  'Quit: Esc');
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

  // Pass messages to camera class for camera movement if the
  // global camera if active
  if (-1 = Integer(g_dwFollow)) then g_Camera.HandleMessages(hWnd, uMsg, wParam, lParam);
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
  pTiny: CTiny;
  i: Integer;
  pChar: CTiny;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;

    IDC_ADDTINY:
    begin
      pTiny := CTiny.Create;

      if SUCCEEDED(pTiny.Setup(g_MultiAnim, g_v_pCharacters, g_DSound, DXUTGetGlobalTimer.GetTime))
      then pTiny.SetSounds(g_bPlaySounds)
      else pTiny.Free;
    end;

    IDC_NEXTVIEW:
      if (g_v_pCharacters.Count <> 0) then
      begin
        if (g_dwFollow = $ffffffff) then g_dwFollow := 0
        else if (Integer(g_dwFollow) = g_v_pCharacters.Count - 1) then g_dwFollow := $ffffffff
        else Inc(g_dwFollow);

        if (g_dwFollow = $ffffffff) then
        begin
          g_SampleUI.GetCheckBox(IDC_CONTROLTINY).Enabled := False;
          g_SampleUI.GetCheckBox(IDC_CONTROLTINY).Visible := False;
        end else
        begin
          g_SampleUI.GetCheckBox(IDC_CONTROLTINY).Enabled := True;
          g_SampleUI.GetCheckBox(IDC_CONTROLTINY).Visible := True;
          g_SampleUI.GetCheckBox(IDC_CONTROLTINY).Checked := g_v_pCharacters[g_dwFollow].IsUserControl;
        end;
      end;

    IDC_PREVVIEW:
      if (g_v_pCharacters.Count <> 0) then
      begin
        if (g_dwFollow = $ffffffff) then g_dwFollow := g_v_pCharacters.Count - 1
        else if (g_dwFollow = 0) then g_dwFollow := $ffffffff
        else Dec(g_dwFollow);

        if (g_dwFollow = $ffffffff) then
        begin
          g_SampleUI.GetCheckBox(IDC_CONTROLTINY).Enabled := False;
          g_SampleUI.GetCheckBox(IDC_CONTROLTINY).Visible := False;
        end else
        begin
          g_SampleUI.GetCheckBox(IDC_CONTROLTINY).Enabled := True;
          g_SampleUI.GetCheckBox(IDC_CONTROLTINY).Visible := True;
          g_SampleUI.GetCheckBox(IDC_CONTROLTINY).Checked := g_v_pCharacters[g_dwFollow].IsUserControl;
        end;
      end;

    IDC_RESETCAMERA:
    begin
      g_dwFollow := $ffffffff;
      g_SampleUI.GetCheckBox(IDC_CONTROLTINY).Enabled := False;
      g_SampleUI.GetCheckBox(IDC_CONTROLTINY).Visible := False;
    end;

    IDC_ENABLESOUND:
    begin
      g_bPlaySounds := (pControl as CDXUTCheckBox).Checked;
      for i := 0 to g_v_pCharacters.Count - 1 do
        g_v_pCharacters[i].SetSounds(g_bPlaySounds);
    end;

    IDC_CONTROLTINY:
      if (g_dwFollow <> $ffffffff) then
      begin
        pChar := g_v_pCharacters[g_dwFollow];
        if (pControl as CDXUTCheckBox).Checked
        then pChar.SetUserControl
        else pChar.SetAutoControl;
      end;

    IDC_RELEASEALL:
    begin
      for i := 0 to g_v_pCharacters.Count - 1 do
        g_v_pCharacters[i].SetAutoControl;
      g_SampleUI.GetCheckBox(IDC_CONTROLTINY).Checked := False;
    end;

    IDC_RESETTIME:
    begin
      DXUTGetGlobalTimer.Reset;
      g_fLastAnimTime := DXUTGetGlobalTimer.GetTime;
      for i := 0 to g_v_pCharacters.Count - 1 do
        g_v_pCharacters[i].ResetTime;
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
  pMAEffect: ID3DXEffect;
  i: Integer;
  AH: CMultiAnimAllocateHierarchy;
begin
  g_DialogResourceManager.OnLostDevice;
  g_SettingsDlg.OnLostDevice;
  if Assigned(g_pFont) then g_pFont.OnLostDevice;
  if Assigned(g_pEffect) then g_pEffect.OnLostDevice;

  pMAEffect := g_MultiAnim.GetEffect;
  if Assigned(pMAEffect) then
  begin
    pMAEffect.OnLostDevice;
    pMAEffect := nil;
  end;

  SAFE_RELEASE(g_pTextSprite);
  SAFE_RELEASE(g_pMeshFloor);

  for i := 0 to g_v_pCharacters.Count - 1 do
    g_v_pCharacters[i].InvalidateDeviceObjects;

  AH:= CMultiAnimAllocateHierarchy.Create;
  try
    AH.SetMA(g_MultiAnim);
    g_MultiAnim.Cleanup(AH);
  finally
    AH.Free;
  end;
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
  SAFE_RELEASE(g_pEffect);
  SAFE_RELEASE(g_pFont);

  SAFE_RELEASE(g_pTxFloor);
  SAFE_RELEASE(g_pMeshFloor);
end;



procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera:= CFirstPersonCamera.Create;     // A model viewing camera
  g_HUD:= CDXUTDialog.Create;               // manages the 3D UI
  g_SampleUI:= CDXUTDialog.Create;          // dialog for sample specific controls

  g_DSound:= CSoundManager.Create;          // DirectSound class
  g_MultiAnim:= CMultiAnim.Create;          // the MultiAnim class for holding Tiny's mesh and frame hierarchy
  g_v_pCharacters:= TTinyList.Create;       // array of character objects; each can be associated with any of the CMultiAnims
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_DSound);
  FreeAndNil(g_MultiAnim);
  FreeAndNil(g_v_pCharacters);
  FreeAndNil(g_Camera);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);
end;

end.

