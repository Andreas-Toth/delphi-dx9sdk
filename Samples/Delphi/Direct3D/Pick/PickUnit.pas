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
 *  $Id: PickUnit.pas,v 1.6 2007/02/05 22:21:11 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: Pick.cpp
//
// Basic starting point for new Direct3D samples
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit PickUnit;

interface

uses
  Windows, Messages, SysUtils, StrSafe,
  DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTMesh, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders


//--------------------------------------------------------------------------------------
// Vertex format
//--------------------------------------------------------------------------------------
type
  PD3DVertex = ^TD3DVertex;
  TD3DVertex = record
    p: TD3DXVector3;
    n: TD3DXVector3;
    tu, tv: Single;
  end;

const
  TD3DVertex_FVF = D3DFVF_XYZ or D3DFVF_NORMAL or D3DFVF_TEX1;

type
  PIntersectionType = ^TIntersection;
  TIntersection = record
    dwFace: DWORD;                 // mesh face that was intersected
    fBary1, fBary2: Single;         // barycentric coords of intersection
    fDist: Single;                  // distance from ray origin to intersection
    tu, tv: Single;                 // texture coords of intersection
  end;

// For simplicity's sake, we limit the number of simultaneously intersected
// triangles to 16
const
  MAX_INTERSECTIONS = 16;
  CAMERA_DISTANCE = 3.5;

//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont:              ID3DXFont;          // Font for drawing text
  g_pTextSprite:        ID3DXSprite;        // Sprite for batching draw text calls
  g_pEffect:            ID3DXEffect;        // D3DX effect interface
  g_Mesh:               CDXUTMesh;          // The mesh to be rendered
  g_Camera:             CModelViewerCamera; // A model viewing camera
  g_dwNumIntersections: DWORD;              // Number of faces intersected
  g_IntersectionArray:  array[0..MAX_INTERSECTIONS-1] of TIntersection; // Intersection info
  g_pVB:                IDirect3DVertexBuffer9; // VB for picked triangles
  g_bShowHelp:          Boolean = True;     // If true, it renders the UI control text
  g_bUseD3DXIntersect:  Boolean = True;     // Whether to use D3DXIntersect
  g_bAllHits:           Boolean = True;     // Whether to just get the first "hit" or all "hits"
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg:        CD3DSettingsDlg;    // Device settings dialog
  g_HUD:                CDXUTDialog;        // dialog for standard controls
  g_SampleUI:           CDXUTDialog;        // dialog for sample specific controls

  
//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 2;
  IDC_CHANGEDEVICE        = 3;
  IDC_USED3DX             = 4;
  IDC_ALLHITS             = 5;


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
function Pick: HRESULT;
function IntersectTriangle(const orig: TD3DXVector3; const dir: TD3DXVector3;
                           out v0, v1, v2: TD3DXVector3;
                           out t, u, v: Single): Boolean;

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
  g_SampleUI.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent); iY := 10;
  g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22); Inc(iY, 24);
  g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', 35, iY, 125, 22); Inc(iY, 24);
  g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 35, iY, 125, 22, VK_F2); Inc(iY, 24);
  g_HUD.AddCheckBox(IDC_USED3DX, 'Use D3DXIntersect', 35, iY, 125, 22, g_bUseD3DXIntersect, VK_F4); Inc(iY, 24);
  g_HUD.AddCheckBox(IDC_ALLHITS, 'Show All Hits', 35, iY, 125, 22, g_bAllHits, VK_F5);

  g_SampleUI.SetCallback(OnGUIEvent); // iY := 10;
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

  // Skip backbuffer formats that don't support alpha blending
  pD3D := DXUTGetD3DObject;
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                   AdapterFormat, D3DUSAGE_QUERY_POSTPIXELSHADER_BLENDING,
                   D3DRTYPE_TEXTURE, BackBufferFormat))
  then Exit;

  // No fallback defined by this app, so reject any device that
  // doesn't support at least ps2.0
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2,0)) then Exit;

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
  colorMtrl: TD3DXColor;
  vLightDir: TD3DXVector3;
  vLightDiffuse: TD3DXColor;
  vecEye, vecAt: TD3DXVector3;
  mWorld: TD3DXMatrix;
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

  // Load the mesh with D3DX and get back a ID3DXMesh*.  For this
  // sample we'll ignore the X file's embedded materials since we know
  // exactly the model we're loading.  See the mesh samples such as
  // "OptimizedMesh" for a more generic mesh loading example.
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'scanner\scannerarm.x');
  if V_Failed(Result) then Exit;

  Result:= g_Mesh.CreateMesh(pd3dDevice, str);
  if V_Failed(Result) then Exit;
  Result:= g_Mesh.SetFVF(pd3dDevice, TD3DVertex_FVF);
  if V_Failed(Result) then Exit;

  // Create the vertex buffer
  Result := pd3dDevice.CreateVertexBuffer(3*MAX_INTERSECTIONS*SizeOf(TD3DVertex),
                                          D3DUSAGE_WRITEONLY, TD3DVertex_FVF,
                                          D3DPOOL_MANAGED, g_pVB, nil);
  if Failed(Result) then
  begin
    Result:= E_FAIL;
    Exit;
  end;

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
  Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, WideString('Pick.fx'));
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // why the .fx file failed to compile
  Result := D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags, nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  // Set effect variables as needed
  colorMtrl := D3DXColor(1.0, 1.0, 1.0, 1.0);
  vLightDir := D3DXVector3(0.1, -1.0, 0.1);
  vLightDiffuse := D3DXColor(1,1,1,1);

  Result:= g_pEffect.SetValue('g_MaterialAmbientColor', @colorMtrl, SizeOf(TD3DXColor));
  if V_Failed(Result) then Exit;
  Result:= g_pEffect.SetValue('g_MaterialDiffuseColor', @colorMtrl, SizeOf(TD3DXColor));
  if V_Failed(Result) then Exit;

  Result:= g_pEffect.SetValue('g_LightDir', @vLightDir, SizeOf(TD3DXVector3));
  if V_Failed(Result) then Exit;
  Result:= g_pEffect.SetValue('g_LightDiffuse', @vLightDiffuse, SizeOf(TD3DXVector4));
  if V_Failed(Result) then Exit;

  Result:= g_pEffect.SetTexture('g_MeshTexture', g_Mesh.m_pTextures[0]);
  if V_Failed(Result) then Exit;

  // Setup the camera's view parameters
  // Setup the camera's view parameters
  vecEye := D3DXVector3(-CAMERA_DISTANCE, 0.0, -15.0);
  vecAt  := D3DXVector3(0.0, 0.0, -0.0);
  g_Camera.SetViewParams(vecEye, vecAt);

  // Setup the world matrix of the camera
  // Change this to see how picking works with a translated object
  D3DXMatrixTranslation(mWorld, 0.0, -1.7, 0.0);
  g_Camera.SetWorldMatrix(mWorld);

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

  Result:= g_Mesh.RestoreDeviceObjects(pd3dDevice);
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
  g_Camera.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);
  g_Camera.SetButtonMasks(MOUSE_LEFT_BUTTON, MOUSE_WHEEL, MOUSE_MIDDLE_BUTTON);

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation(pBackBufferSurfaceDesc.Width-170, pBackBufferSurfaceDesc.Height-350);
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
var
  vFromPt: TD3DXVector3;
  vLookatPt: TD3DXVector3;
begin
  // Rotate the camera about the y-axis
  vFromPt   := D3DXVector3Zero;
  vLookatPt := D3DXVector3Zero;

  vFromPt.x := -cos(fTime/3.0) * CAMERA_DISTANCE;
  vFromPt.y := 1.0;
  vFromPt.z :=  sin(fTime/3.0) * CAMERA_DISTANCE;

  // Update the camera's position based on time
  g_Camera.SetViewParams(vFromPt, vLookatPt);
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
  iPass, cPasses: LongWord;
  m, mWorld, mView, mProj: TD3DXMatrixA16;
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  // Check for picked triangles
  Pick;
  
  // Clear the render target and the zbuffer
  V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, D3DCOLOR_ARGB(0, 45, 50, 170), 1.0, 0));

  // Render the scene
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    // Get the projection & view matrix from the camera class
    mWorld:= g_Camera.GetWorldMatrix^;
    mProj := g_Camera.GetProjMatrix^;
    mView := g_Camera.GetViewMatrix^;

    // mWorldViewProjection = mWorld * mView * mProj;
    D3DXMatrixMultiply(m, mView, mProj);
    D3DXMatrixMultiply(mWorldViewProjection, mWorld, m);

    V(g_pEffect.SetTechnique('RenderScene'));

    // Update the effect's variables.  Instead of using strings, it would
    // be more efficient to cache a handle to the parameter by calling
    // ID3DXEffect::GetParameterByName
    V(g_pEffect.SetMatrix('g_mWorldViewProjection', mWorldViewProjection));
    V(g_pEffect.SetMatrix('g_mWorld', mWorld));
    V(g_pEffect.SetFloat('g_fTime', fTime));

    V(g_pEffect._Begin(@cPasses, 0));

    // Set render mode to lit, solid triangles
    pd3dDevice.SetRenderState(D3DRS_FILLMODE, D3DFILL_SOLID);
    pd3dDevice.SetRenderState(D3DRS_LIGHTING, iTrue);

    if (g_dwNumIntersections > 0) then
    begin
      for iPass := 0 to cPasses - 1 do
      begin
        V(g_pEffect.BeginPass(iPass));

        // Draw the picked triangle
        pd3dDevice.SetFVF(TD3DVertex_FVF);
        pd3dDevice.SetStreamSource(0, g_pVB, 0, SizeOf(TD3DVertex));
        pd3dDevice.DrawPrimitive(D3DPT_TRIANGLELIST, 0, g_dwNumIntersections);

        V(g_pEffect.EndPass);
      end;

      // Set render mode to unlit, wireframe triangles
      pd3dDevice.SetRenderState(D3DRS_FILLMODE, D3DFILL_WIREFRAME);
      pd3dDevice.SetRenderState(D3DRS_LIGHTING, iFalse);
    end;

    V(g_pEffect._End);

    // Render the mesh
    V(g_Mesh.Render(g_pEffect));

    DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'HUD / Stats'); // These events are to help PIX identify what the code is doing
    RenderText;
    g_HUD.OnRender(fElapsedTime);
    g_SampleUI.OnRender(fElapsedTime);
    DXUT_EndPerfEvent;

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
  dwIndex: DWORD;
  wstrHitStat: array[0..255] of WideChar;
begin
  // The helper object simply helps keep track of text position, and color
  // and then it calls pFont->DrawText( m_pSprite, strMsg, -1, &rc, DT_NOCLIP, m_clr );
  // If NULL is passed in as the sprite object, then it will work fine however the
  // pFont->DrawText() will not be batched together.  Batching calls will improves perf.
  txtHelper:= CDXUTTextHelper.Create(g_pFont, g_pTextSprite, 15);
  try
    // Output statistics
    txtHelper._Begin;
    txtHelper.SetInsertionPos(5, 0);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));
    txtHelper.DrawTextLine(DXUTGetFrameStats);
    txtHelper.DrawTextLine(DXUTGetDeviceStats);

    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));

    if(g_dwNumIntersections < 1) then
    begin
      txtHelper.DrawTextLine('Use mouse to pick a polygon');
    end else
    begin
      for dwIndex := 0 to g_dwNumIntersections - 1 do
      begin
        StringCchFormat(wstrHitStat, 256,
            //'Face=%d, tu=%3.02f, tv=%3.02f', //Clootie: pre Delphi9 bug
            'Face=%d, tu=%f, tv=%f',
            [g_IntersectionArray[dwIndex].dwFace,
            g_IntersectionArray[dwIndex].tu,
            g_IntersectionArray[dwIndex].tv]);

        txtHelper.DrawTextLine(wstrHitStat);
      end;
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

  // Pass all remaining windows messages to camera so it can respond to user input
  //g_Camera.HandleMessages(hWnd, uMsg, wParam, lParam);

  case uMsg of
    WM_LBUTTONDOWN:
    begin
      // Capture the mouse, so if the mouse button is
      // released outside the window, we'll get the WM_LBUTTONUP message
      DXUTGetGlobalTimer.Stop;
      SetCapture(hWnd);
      Result:= iTrue;
      Exit;
    end;

    WM_LBUTTONUP:
    begin
      ReleaseCapture;
      DXUTGetGlobalTimer.Start;
    end;

    WM_CAPTURECHANGED:
    begin
      if (Cardinal(lParam) <> hWnd) then
      begin
        ReleaseCapture;
        DXUTGetGlobalTimer.Start;
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


//--------------------------------------------------------------------------------------
// Handles the GUI events
//--------------------------------------------------------------------------------------
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;
    IDC_USED3DX:          g_bUseD3DXIntersect := not g_bUseD3DXIntersect;
    IDC_ALLHITS:          g_bAllHits := not g_bAllHits;
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
  SAFE_RELEASE(g_pTextSprite);
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
  g_Mesh.DestroyMesh;
  SAFE_RELEASE(g_pVB);
  SAFE_RELEASE(g_pEffect);
  SAFE_RELEASE(g_pFont);
end;


//--------------------------------------------------------------------------------------
// Checks if mouse point hits geometry the scene.
//--------------------------------------------------------------------------------------
function Pick: HRESULT;
type
  PD3DXIntersectInfoArray = ^TD3DXIntersectInfoArray;
  TD3DXIntersectInfoArray = array [0..MaxInt div SizeOf(TD3DXIntersectInfo)-1] of TD3DXIntersectInfo;
  PD3DVertexArray = ^TD3DVertexArray;
  TD3DVertexArray = array [0..MaxInt div SizeOf(TD3DVertex)-1] of TD3DVertex;
var
  vPickRayDir: TD3DXVector3;
  vPickRayOrig: TD3DXVector3;
  pD3Device: IDirect3DDevice9;
  pd3dsdBackBuffer: PD3DSurfaceDesc;
  pmatProj: PD3DXMatrix;
  ptCursor: TPoint;
  v: TD3DXVector3;
  matView: TD3DXMatrix;
  matWorld: TD3DXMatrix;
  mWorldView: TD3DXMatrix;
  m: TD3DXMatrix;
  pMesh: ID3DXMesh;
  pVB: IDirect3DVertexBuffer9;
  pIB:  IDirect3DIndexBuffer9;
  pIndices: PWordArray;
  pVertices: PD3DVertexArray;
  bHit: BOOL;
  dwFace: DWORD;
  fBary1, fBary2, fDist: Single;
  pBuffer: ID3DXBuffer;
  pIntersectInfoArray: PD3DXIntersectInfoArray;
  iIntersection: Integer;
  dwNumFaces: DWORD;
  i: Integer;
  v0, v1, v2: TD3DXVector3;
  vtx: PD3DVertexArray;
  vThisTri: PD3DVertexArray;
  iThisTri: PWordArray;
  pIntersection: PIntersectionType;
  dtu1: Single;
  dtu2: Single;
  dtv1: Single;
  dtv2: Single;
begin
  pD3Device := DXUTGetD3DDevice;
  pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;

  g_dwNumIntersections := 0;

  // Get the pick ray from the mouse position
  if (GetCapture <> 0) then
  begin
    pmatProj := g_Camera.GetProjMatrix;

    GetCursorPos(ptCursor);
    ScreenToClient(DXUTGetHWND, ptCursor);

    // Compute the vector of the pick ray in screen space
    v.x :=  ( ( ( 2.0 * ptCursor.x ) / pd3dsdBackBuffer.Width  ) - 1 ) / pmatProj._11;
    v.y := -( ( ( 2.0 * ptCursor.y ) / pd3dsdBackBuffer.Height ) - 1 ) / pmatProj._22;
    v.z :=  1.0;

    // Get the inverse view matrix
    matView := g_Camera.GetViewMatrix^;
    matWorld := g_Camera.GetWorldMatrix^;
    // mWorldView = matWorld * matView;
    D3DXMatrixMultiply(mWorldView, matWorld, matView);
    D3DXMatrixInverse(m, nil, mWorldView);

    // Transform the screen space pick ray into 3D space
    vPickRayDir.x  := v.x*m._11 + v.y*m._21 + v.z*m._31;
    vPickRayDir.y  := v.x*m._12 + v.y*m._22 + v.z*m._32;
    vPickRayDir.z  := v.x*m._13 + v.y*m._23 + v.z*m._33;
    vPickRayOrig.x := m._41;
    vPickRayOrig.y := m._42;
    vPickRayOrig.z := m._43;
  end;

  // Get the picked triangle
  if (GetCapture <> 0) then
  begin
    g_Mesh.Mesh.CloneMeshFVF(D3DXMESH_MANAGED,
        g_Mesh.Mesh.GetFVF, pD3Device, pMesh);

    pMesh.GetVertexBuffer(pVB);
    pMesh.GetIndexBuffer(pIB);

    pIB.Lock(0, 0, Pointer(pIndices), 0);
    pVB.Lock(0, 0, Pointer(pVertices), 0);

    if g_bUseD3DXIntersect then 
    begin
      // When calling D3DXIntersect, one can get just the closest intersection and not
      // need to work with a D3DXBUFFER.  Or, to get all intersections between the ray and 
      // the mesh, one can use a D3DXBUFFER to receive all intersections.  We show both
      // methods.
      if not g_bAllHits then 
      begin
        // Collect only the closest intersection
        D3DXIntersect(pMesh, vPickRayOrig, vPickRayDir, bHit, @dwFace, @fBary1, @fBary2, @fDist, nil, nil);
        if bHit then
        begin
          g_dwNumIntersections := 1;
          g_IntersectionArray[0].dwFace := dwFace;
          g_IntersectionArray[0].fBary1 := fBary1;
          g_IntersectionArray[0].fBary2 := fBary2;
          g_IntersectionArray[0].fDist := fDist;
        end else
        begin
          g_dwNumIntersections := 0;
        end;
      end else
      begin
        // Collect all intersections
        Result := D3DXIntersect(pMesh, vPickRayOrig, vPickRayDir, bHit, nil, nil, nil, nil, @pBuffer, @g_dwNumIntersections);
        if Failed(Result) then Exit;
        {begin
          SAFE_RELEASE(pMesh);
          SAFE_RELEASE(pVB);
          SAFE_RELEASE(pIB);

          Result:= hr;
        end;}
        if (g_dwNumIntersections > 0) then 
        begin
          pIntersectInfoArray := PD3DXIntersectInfoArray(pBuffer.GetBufferPointer);
          if (g_dwNumIntersections > MAX_INTERSECTIONS) then g_dwNumIntersections := MAX_INTERSECTIONS;
          for iIntersection := 0 to g_dwNumIntersections - 1 do
          begin
            g_IntersectionArray[iIntersection].dwFace := pIntersectInfoArray[iIntersection].FaceIndex;
            g_IntersectionArray[iIntersection].fBary1 := pIntersectInfoArray[iIntersection].U;
            g_IntersectionArray[iIntersection].fBary2 := pIntersectInfoArray[iIntersection].V;
            g_IntersectionArray[iIntersection].fDist := pIntersectInfoArray[iIntersection].Dist;
          end;
        end;
        SAFE_RELEASE(pBuffer);
      end;

    end else
    begin
      // Not using D3DX
      dwNumFaces := g_Mesh.Mesh.GetNumFaces;
      for i := 0 to dwNumFaces - 1 do
      begin
        v0 := pVertices[pIndices[3*i+0]].p;
        v1 := pVertices[pIndices[3*i+1]].p;
        v2 := pVertices[pIndices[3*i+2]].p;

        // Check if the pick ray passes through this point
        if IntersectTriangle(vPickRayOrig, vPickRayDir, v0, v1, v2, fDist, fBary1, fBary2) then 
        begin
          if (g_bAllHits or (g_dwNumIntersections = 0) or (fDist < g_IntersectionArray[0].fDist)) then
          begin
            if not g_bAllHits then g_dwNumIntersections := 0;
            g_IntersectionArray[g_dwNumIntersections].dwFace := i;
            g_IntersectionArray[g_dwNumIntersections].fBary1 := fBary1;
            g_IntersectionArray[g_dwNumIntersections].fBary2 := fBary2;
            g_IntersectionArray[g_dwNumIntersections].fDist := fDist;
            Inc(g_dwNumIntersections);
            if (g_dwNumIntersections = MAX_INTERSECTIONS) then Break;
          end;
        end;
      end;
    end;

    // Now, for each intersection, add a triangle to g_pVB and compute texture coordinates
    if (g_dwNumIntersections > 0) then
    begin
      g_pVB.Lock(0, 0, Pointer(vtx), 0);

      for iIntersection := 0 to g_dwNumIntersections - 1 do
      begin
        pIntersection := @g_IntersectionArray[iIntersection];

        vThisTri := @vtx[iIntersection * 3];
        iThisTri := @pIndices[3*pIntersection.dwFace];
        // get vertices hit
        vThisTri[0] := pVertices[iThisTri[0]];
        vThisTri[1] := pVertices[iThisTri[1]];
        vThisTri[2] := pVertices[iThisTri[2]];

        // If all you want is the vertices hit, then you are done.  In this sample, we
        // want to show how to infer texture coordinates as well, using the BaryCentric
        // coordinates supplied by D3DXIntersect
        dtu1 := vThisTri[1].tu - vThisTri[0].tu;
        dtu2 := vThisTri[2].tu - vThisTri[0].tu;
        dtv1 := vThisTri[1].tv - vThisTri[0].tv;
        dtv2 := vThisTri[2].tv - vThisTri[0].tv;
        pIntersection.tu := vThisTri[0].tu + pIntersection.fBary1 * dtu1 + pIntersection.fBary2 * dtu2;
        pIntersection.tv := vThisTri[0].tv + pIntersection.fBary1 * dtv1 + pIntersection.fBary2 * dtv2;
      end;

      g_pVB.Unlock;
    end;

    pVB.Unlock;
    pIB.Unlock;

    SAFE_RELEASE(pMesh);
    SAFE_RELEASE(pVB);
    SAFE_RELEASE(pIB);
  end;

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// Given a ray origin (orig) and direction (dir), and three vertices of a triangle, this
// function returns TRUE and the interpolated texture coordinates if the ray intersects 
// the triangle
//--------------------------------------------------------------------------------------
function IntersectTriangle(const orig: TD3DXVector3; const dir: TD3DXVector3;
                           out v0, v1, v2: TD3DXVector3;
                           out t, u, v: Single): Boolean;
var
  edge1: TD3DXVector3;
  edge2: TD3DXVector3;
  pvec: TD3DXVector3;
  det: Single;
  tvec: TD3DXVector3;
  qvec: TD3DXVector3;
  fInvDet: Single;
begin
  Result:= False;

  // Find vectors for two edges sharing vert0
  //edge1 := v1 - v0;
  //edge2 := v2 - v0;
  D3DXVec3Subtract(edge1, v1, v0);
  D3DXVec3Subtract(edge2, v2, v0);

  // Begin calculating determinant - also used to calculate U parameter
  D3DXVec3Cross(pvec, dir, edge2);

  // If determinant is near zero, ray lies in plane of triangle
  det := D3DXVec3Dot(edge1, pvec);

  if (det > 0) then
  begin
    // tvec := orig - v0;
    D3DXVec3Subtract(tvec, orig, v0);
  end else
  begin
    // tvec := v0 - orig;
    D3DXVec3Subtract(tvec, v0, orig);
    det := -det;
  end;

  if (det < 0.0001) then Exit;

  // Calculate U parameter and test bounds
  u := D3DXVec3Dot(tvec, pvec);
  if (u < 0.0) or (u > det) then Exit;

  // Prepare to test V parameter
  D3DXVec3Cross(qvec, tvec, edge1);

  // Calculate V parameter and test bounds
  v := D3DXVec3Dot(dir, qvec);
  if (v < 0.0) or (u + v > det) then Exit;

  // Calculate t, scale parameters, ray intersects triangle
  t := D3DXVec3Dot(edge2, qvec);
  fInvDet := 1.0 / det;
  t := t * fInvDet;
  u := u * fInvDet;
  v := v * fInvDet;

  Result:= True;
end;


procedure CreateCustomDXUTobjects;
begin
  g_Mesh:= CDXUTMesh.Create; // The mesh to be rendered
  g_Camera:= CModelViewerCamera.Create; // A model viewing camera
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_HUD:= CDXUTDialog.Create; // manages the 3D UI
  g_SampleUI:= CDXUTDialog.Create; // dialog for sample specific controls
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_Mesh);
  FreeAndNil(g_Camera);
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);
end;

end.

