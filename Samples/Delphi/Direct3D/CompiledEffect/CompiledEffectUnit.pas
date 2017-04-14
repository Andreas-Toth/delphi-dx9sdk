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
 *  $Id: CompiledEffectUnit.pas,v 1.15 2007/02/05 22:21:03 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: CompiledEffect.cpp
//
// Desc: This sample shows how an ID3DXEffect object can be compiled when the
//       project is built and loaded directly as a binary file at run time.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit CompiledEffectUnit;

interface

uses
  Windows, SysUtils,
  DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTenum, DXUTmesh, DXUTmisc, DXUTgui, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders

//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont:         ID3DXFont;          // Font for drawing text
  g_pTextSprite:   ID3DXSprite;        // Sprite for batching draw text calls
  g_pEffect:       ID3DXEffect;        // D3DX effect interface
  g_Camera:        CModelViewerCamera; // A model viewing camera
  g_bShowHelp:     Boolean = True;     // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg:   CD3DSettingsDlg;    // Device settings dialog
  g_HUD:           CDXUTDialog;        // dialog for standard controls
  g_Mesh:          CDXUTMesh;          // Mesh object
  g_vObjectCenter: TD3DXVector3;       // Center of bounding sphere of object
  g_fObjectRadius: Single;             // Radius of bounding sphere of object
  g_mCenterWorld:  TD3DXMatrixA16;     // World matrix to center the mesh

  g_hTime: TD3DXHandle                 = nil; // Handle to var in the effect
  g_hWorld: TD3DXHandle                = nil; // Handle to var in the effect
  g_hMeshTexture: TD3DXHandle          = nil; // Handle to var in the effect
  g_hWorldViewProjection: TD3DXHandle  = nil; // Handle to var in the effect
  g_hTechniqueRenderScene: TD3DXHandle = nil; // Handle to technique in the effect

//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;



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
begin
  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent); iY := 10;
  g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22); Inc(iY, 24);
  g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', 35, iY, 125, 22); Inc(iY, 24);
  g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 35, iY, 125, 22, VK_F2);
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
  pVB: IDirect3DVertexBuffer9;
  pVertices: Pointer;
  str: array [0..MAX_PATH-1] of WideChar;
  vecEye: TD3DXVector3;
  vecAt: TD3DXVector3;
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

  // Load the mesh
  Result:= g_Mesh.CreateMesh(pd3dDevice, 'dwarf\dwarf.x');
  if V_Failed(Result) then Exit;

  // Find the mesh's center, then generate a centering matrix.
  pVB := nil;
  Result:= g_Mesh.Mesh.GetVertexBuffer(pVB);
  if V_Failed(Result) then Exit;

  pVertices:= nil;
  Result := pVB.Lock(0, 0, pVertices, 0);
  if FAILED(Result) then Exit;

  Result := D3DXComputeBoundingSphere(PD3DXVector3(pVertices), g_Mesh.Mesh.GetNumVertices,
                                  D3DXGetFVFVertexSize(g_Mesh.Mesh.GetFVF), g_vObjectCenter,
                                  g_fObjectRadius);
  pVB.Unlock;
  pVB:= nil;

  if FAILED(Result) then Exit;

  D3DXMatrixTranslation(g_mCenterWorld, -g_vObjectCenter.x, -g_vObjectCenter.y, -g_vObjectCenter.z);

  // Read the D3DX effect file
  Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, 'CompiledEffect.fxo');
  if FAILED(Result) then
  begin
    //todo: Update this statement
    MessageBox(DXUTGetHWND, 'Could not locate "CompiledEffect.fxo".'#10#10 +
                            'This file is created as part of the project build process,'#10 +
                            'so the associated project must be compiled inside Visual'#10 +
                            'Studio before attempting to run this sample.'#10#10 +
                            'If receiving this error even after compiling the project,'#10 +
                            'it''s likely there was a problem compiling the effect file.'#10 +
                            'Check the build log to verify the custom build step was'#10 +
                            'run and to look for possible fxc compile errors.',
                            'File Not Found', MB_OK);
    Result:= E_FAIL;
    Exit;
  end;

  // Since we are loading a binary file here and this effect has already been compiled,
  // you can not pass compiler flags here (for example to debug the shaders).
  // To debug the shaders, you must pass these flags to the compiler that generated the
  // binary (for example fxc.exe).  In this sample, there are 2 extra Visual Studio configurations
  // called "Debug Shaders" and "Unicode Debug Shaders" that pass the debug shader flags to fxc.exe.
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, D3DXFX_NOT_CLONEABLE, nil, g_pEffect, nil);
  if FAILED(Result) then Exit;

  // Setup the camera's view parameters
  vecEye := D3DXVector3(0.0, 0.0, -5.0);
  vecAt  := D3DXVECTOR3(0.0, 0.0, -0.0);
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
  colorMtrlDiffuse: TD3DXColor;
  colorMtrlAmbient: TD3DXColor;
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
  g_Mesh.RestoreDeviceObjects(pd3dDevice);

  // Create a sprite to help batch calls when drawing many lines of text
  Result:= D3DXCreateSprite(pd3dDevice, g_pTextSprite);
  if V_Failed(Result) then Exit;

  // Set effect variables as needed
  colorMtrlDiffuse := D3DXColor(1.0, 1.0, 1.0, 1.0);
  colorMtrlAmbient := D3DXColor(0.35, 0.35, 0.35, 0);
  g_pEffect.SetVector('g_MaterialAmbientColor', PD3DXVector4(@colorMtrlAmbient)^);
  g_pEffect.SetVector('g_MaterialDiffuseColor', PD3DXVector4(@colorMtrlDiffuse)^);

  // To read or write to D3DX effect variables we can use the string name
  // instead of using handles, however it improves perf to use handles since then
  // D3DX won't have to spend time doing string compares
  g_hTechniqueRenderScene         := g_pEffect.GetTechniqueByName('RenderScene');
  g_hTime                         := g_pEffect.GetParameterByName(nil, 'g_fTime');
  g_hWorld                        := g_pEffect.GetParameterByName(nil, 'g_mWorld');
  g_hWorldViewProjection          := g_pEffect.GetParameterByName(nil, 'g_mWorldViewProjection');
  g_hMeshTexture                  := g_pEffect.GetParameterByName(nil, 'g_MeshTexture');


  // Setup the camera's projection parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI/4, fAspectRatio, 0.1, 1000.0);
  g_Camera.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);

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
  mWorld: TD3DXMatrixA16;
  mView: TD3DXMatrixA16;
  mProj: TD3DXMatrixA16;
  mWorldViewProjection: TD3DXMatrixA16;
  m: TD3DXMatrixA16;
begin
  // Update the camera's position based on user input
  g_Camera.FrameMove(fElapsedTime);

  // Get the projection & view matrix from the camera class
  // mWorld := g_mCenterWorld * g_Camera.GetWorldMatrix^;
  D3DXMatrixMultiply(mWorld, g_mCenterWorld, g_Camera.GetWorldMatrix^);
  mProj := g_Camera.GetProjMatrix^;
  mView := g_Camera.GetViewMatrix^;

  // mWorldViewProjection = mWorld * mView * mProj;
  D3DXMatrixMultiply(m, mView, mProj);
  D3DXMatrixMultiply(mWorldViewProjection, mWorld, m);

  // Update the effect's variables
  g_pEffect.SetMatrix(g_hWorldViewProjection, mWorldViewProjection);
  g_pEffect.SetMatrix(g_hWorld, mWorld);
  g_pEffect.SetFloat(g_hTime, fTime);
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
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  // Clear the render target and the zbuffer
  V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, D3DCOLOR_ARGB(0, 45, 50, 170), 1.0, 0));

  // Render the scene
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    V(g_pEffect._Begin(@cPasses, 0));
    for iPass := 0 to cPasses - 1 do
    begin
      V(g_pEffect.BeginPass(iPass));

      V(g_Mesh.Render(pd3dDevice ));

      g_pEffect.EndPass;
    end;
    g_pEffect._End;

    RenderText;
    V(g_HUD.OnRender(fElapsedTime));

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

  // Draw help
  if g_bShowHelp then
  begin
    pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*6);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
    txtHelper.DrawTextLine('Controls (F1 to hide):');

    txtHelper.SetInsertionPos(40, pd3dsdBackBuffer.Height-15*5);
    txtHelper.DrawTextLine('Rotate model: Left mouse button'#10+
                           'Rotate camera: Right mouse button'#10+
                           'Zoom camera: Mouse wheel scroll'#10+
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
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;
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
  if Assigned(g_pFont) then g_pFont.OnLostDevice;
  if Assigned(g_pEffect) then g_pEffect.OnLostDevice;
  g_Mesh.InvalidateDeviceObjects;

  SAFE_RELEASE(g_pTextSprite);
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
  g_Mesh.DestroyMesh;
end;


procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera:= CModelViewerCamera.Create;
  g_HUD := CDXUTDialog.Create;
  g_Mesh:= CDXUTMesh.Create
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_Camera);
  FreeAndNil(g_HUD);
  FreeAndNil(g_Mesh);
end;

end.

