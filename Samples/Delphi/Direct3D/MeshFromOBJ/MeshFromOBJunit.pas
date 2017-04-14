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
 *  $Id: MeshFromOBJunit.pas,v 1.19 2007/02/05 22:21:10 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: MeshFromOBJ.cpp
//
// This sample shows how an ID3DXMesh object can be created from mesh data stored in an
// .obj file. It's convenient to use .x files when working with ID3DXMesh objects since
// D3DX can create and fill an ID3DXMesh object directly from an .x file; however, it's
// also easy to initialize an ID3DXMesh object with data gathered from any file format
// or memory resource.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit MeshFromOBJunit;

interface

uses
  Windows, Direct3D9, D3DX9, DXTypes, DXErr9, StrSafe, MeshLoader,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTmesh, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont: ID3DXFont;           // Font for drawing text
  g_pTextSprite: ID3DXSprite;   // Sprite for batching draw text calls
  g_pEffect: ID3DXEffect;       // D3DX effect interface
  g_Camera: CModelViewerCamera; // A model viewing camera
  g_bShowHelp: Boolean = True;  // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg; // Device settings dialog
  g_HUD: CDXUTDialog;           // dialog for standard controls
  g_SampleUI: CDXUTDialog;      // dialog for sample specific controls

  g_MeshLoader: CMeshLoader;    // Loads a mesh from an .obj file

  g_strFileSaveMessage: array[0..MAX_PATH-1] of WideChar; // Text indicating file write success/failure


//--------------------------------------------------------------------------------------
// Effect parameter handles
//--------------------------------------------------------------------------------------
var
  g_hAmbient: TD3DXHandle = nil;
  g_hDiffuse: TD3DXHandle = nil;
  g_hSpecular: TD3DXHandle = nil;
  g_hOpacity: TD3DXHandle = nil;
  g_hSpecularPower: TD3DXHandle = nil;
  g_hLightColor: TD3DXHandle = nil;
  g_hLightPosition: TD3DXHandle = nil;
  g_hCameraPosition: TD3DXHandle = nil;
  g_hTexture: TD3DXHandle = nil;
  g_hTime: TD3DXHandle = nil;
  g_hWorld: TD3DXHandle = nil;
  g_hWorldViewProjection: TD3DXHandle = nil;


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_STATIC              = -1;
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_SUBSET              = 5;
  IDC_SAVETOX             = 6;



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
procedure RenderSubset(iSubset: LongWord);
procedure SaveMeshToXFile;

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;


implementation


//--------------------------------------------------------------------------------------
// Initialize the app
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  iY: Integer;
  pElement: CDXUTElement;
begin
  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_SampleUI.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent); iY := 10;
  g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22); Inc(iY, 24);
  g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', 35, iY, 125, 22); Inc(iY, 24);
  g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 35, iY, 125, 22, VK_F2);

  g_SampleUI.SetCallback(OnGUIEvent); // iY := 10;

  // Title font for comboboxes
  g_SampleUI.SetFont(1, 'Arial', 14, FW_BOLD);
  pElement:= g_SampleUI.GetDefaultElement(DXUT_CONTROL_STATIC, 0);
  if Assigned(pElement) then
  with pElement do
  begin
    iFont := 1;
    dwTextFormat := DT_LEFT or DT_BOTTOM;
  end;

  g_SampleUI.AddStatic(IDC_STATIC, '(S)ubset', 20, 0, 105, 25);
  g_SampleUI.AddComboBox(IDC_SUBSET, 20, 25, 140, 24, Ord('S'));
  g_SampleUI.AddButton(IDC_SAVETOX, 'Save Mesh To X file',  20, 50,  140, 24, Ord('X'));
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

  // No fallback defined by this app, so reject any device that
  // doesn't support at least ps2.0
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
var
  pEnum: CD3DEnumeration;
  pCombo: PD3DEnumDeviceSettingsCombo;
  sample: TD3DMultiSampleType;
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

  // Enable anti-aliasing for HAL devices which support it
  pEnum := DXUTGetEnumeration;
  pCombo := pEnum.GetDeviceSettingsCombo(pDeviceSettings);

  sample:= D3DMULTISAMPLE_4_SAMPLES;
  if (pDeviceSettings.DeviceType = D3DDEVTYPE_HAL) and
     (DynArrayContains(pCombo.multiSampleTypeList, sample, SizeOf(TD3DMultiSampleType))) then
  begin
    pDeviceSettings.pp.MultiSampleType := D3DMULTISAMPLE_4_SAMPLES;
    pDeviceSettings.pp.MultiSampleQuality := 0;
  end;
  
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
  pComboBox: CDXUTComboBox;
  i: Integer;
  pMat: PMaterial;
  dwShaderFlags: DWORD;
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



  // Create the mesh and load it with data already gathered from a file
  Result := g_MeshLoader.CreateMesh(pd3dDevice, 'media\cup.obj');
  if V_Failed(Result) then Exit;

  // Add the identified material subsets to the UI
  pComboBox := g_SampleUI.GetComboBox(IDC_SUBSET);
  pComboBox.RemoveAllItems;
  pComboBox.AddItem('All', Pointer(INT_PTR(-1)));

  for i := 0 to g_MeshLoader.NumMaterials - 1  do
  begin
    pMat := g_MeshLoader.Material[i];
    pComboBox.AddItem(pMat.strName, Pointer(INT_PTR(i)));
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
  dwShaderFlags := g_dwShaderFlags or D3DXSHADER_FORCE_VS_SOFTWARE_NOOPT;
  {$ENDIF}
  {$IFDEF DEBUG_PS}
  dwShaderFlags := g_dwShaderFlags or D3DXSHADER_FORCE_PS_SOFTWARE_NOOPT;
  {$ENDIF}

  // Read the D3DX effect file
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, WideString('MeshFromOBJ.fx'));
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // they the .fx file failed to compile
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags,
                                     nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  // Cache the effect handles
  g_hAmbient := g_pEffect.GetParameterBySemantic(nil, 'Ambient');
  g_hDiffuse := g_pEffect.GetParameterBySemantic(nil, 'Diffuse');
  g_hSpecular := g_pEffect.GetParameterBySemantic(nil, 'Specular');
  g_hOpacity := g_pEffect.GetParameterBySemantic(nil, 'Opacity');
  g_hSpecularPower := g_pEffect.GetParameterBySemantic(nil, 'SpecularPower');
  g_hLightColor := g_pEffect.GetParameterBySemantic(nil, 'LightColor');
  g_hLightPosition := g_pEffect.GetParameterBySemantic(nil, 'LightPosition');
  g_hCameraPosition := g_pEffect.GetParameterBySemantic(nil, 'CameraPosition');
  g_hTexture := g_pEffect.GetParameterBySemantic(nil, 'Texture');
  g_hTime := g_pEffect.GetParameterBySemantic(nil, 'Time');
  g_hWorld := g_pEffect.GetParameterBySemantic(nil, 'World');
  g_hWorldViewProjection := g_pEffect.GetParameterBySemantic(nil, 'WorldViewProjection');

  // Setup the camera's view parameters
  vecEye := D3DXVector3(2.0, 1.0, 0.0);
  vecAt := D3DXVector3(0.0, 0.0, -0.0);
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
  i: LongWord;
  pMat: PMaterial;
  strTechnique: PChar;
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

  // Store the correct technique handles for each material
  for i := 0 to g_MeshLoader.NumMaterials - 1 do
  begin
    pMat := g_MeshLoader.Material[i];

    strTechnique:= '';
    if      (pMat.pTexture <> nil) and     pMat.bSpecular then strTechnique := 'TexturedSpecular'
    else if (pMat.pTexture <> nil) and not pMat.bSpecular then strTechnique := 'TexturedNoSpecular'
    else if (pMat.pTexture =  nil) and     pMat.bSpecular then strTechnique := 'Specular'
    else if (pMat.pTexture =  nil) and not pMat.bSpecular then strTechnique := 'NoSpecular';

    pMat.hTechnique := g_pEffect.GetTechniqueByName(strTechnique);
  end;
    
  // Create a sprite to help batch calls when drawing many lines of text
  Result:= D3DXCreateSprite(pd3dDevice, g_pTextSprite);
  if V_Failed(Result) then Exit;

  // Setup the camera's projection parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI/4, fAspectRatio, 0.1, 1000.0);
  g_Camera.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_HUD.Refresh;

  g_SampleUI.SetLocation(pBackBufferSurfaceDesc.Width-170, pBackBufferSurfaceDesc.Height-350);
  g_SampleUI.SetSize(170, 300);
  g_SampleUI.Refresh;

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
  m: TD3DXMatrixA16;
  mWorld: TD3DXMatrixA16;
  mView: TD3DXMatrixA16;
  mProj: TD3DXMatrixA16;
  mWorldViewProjection: TD3DXMatrixA16;
  iCurSubset: LongWord;
  iSubset: LongWord;
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  // Clear the render target and the zbuffer
  V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, D3DCOLOR_ARGB(0, 141, 153, 191), 1.0, 0));

  // Render the scene
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    // Get the projection & view matrix from the camera class
    mWorld := g_Camera.GetWorldMatrix^;
    mView := g_Camera.GetViewMatrix^;
    mProj := g_Camera.GetProjMatrix^;
        
    // mWorldViewProjection = mWorld * mView * mProj;
    D3DXMatrixMultiply(m, mView, mProj);
    D3DXMatrixMultiply(mWorldViewProjection, mWorld, m);

    // Update the effect's variables. 
    V(g_pEffect.SetMatrix(g_hWorldViewProjection, mWorldViewProjection));
    V(g_pEffect.SetMatrix(g_hWorld, mWorld));
    V(g_pEffect.SetFloat(g_hTime, fTime));
    V(g_pEffect.SetValue(g_hCameraPosition, g_Camera.GetEyePt, SizeOf(TD3DXVector3)));

    iCurSubset := UINT_PTR(g_SampleUI.GetComboBox(IDC_SUBSET).GetSelectedData);

    // A subset of -1 was arbitrarily chosen to represent all subsets
    if (iCurSubset = DWORD(-1)) then
    begin
      // Iterate through subsets, changing material properties for each
      for iSubset := 0 to g_MeshLoader.NumMaterials - 1 do
        RenderSubset(iSubset);
    end else
      RenderSubset(iCurSubset);

    RenderText;
    V(g_HUD.OnRender(fElapsedTime));
    V(g_SampleUI.OnRender(fElapsedTime));

    V(pd3dDevice.EndScene);
  end;
end;


//--------------------------------------------------------------------------------------
procedure RenderSubset(iSubset: LongWord);
var
  iPass, cPasses: Integer;
  pMesh: ID3DXMesh;
  pMaterial: MeshLoader.PMaterial;
begin
  // Retrieve the ID3DXMesh pointer and current material from the MeshLoader helper
  pMesh := g_MeshLoader.Mesh;
  pMaterial := g_MeshLoader.Material[iSubset];

  // Set the lighting variables and texture for the current material
  V(g_pEffect.SetValue(g_hAmbient, @pMaterial.vAmbient, SizeOf(TD3DXVector3)));
  V(g_pEffect.SetValue(g_hDiffuse, @pMaterial.vDiffuse, SizeOf(TD3DXVector3)));
  V(g_pEffect.SetValue(g_hSpecular, @pMaterial.vSpecular, SizeOf(TD3DXVector3)));
  V(g_pEffect.SetTexture(g_hTexture, pMaterial.pTexture));
  V(g_pEffect.SetFloat(g_hOpacity, pMaterial.fAlpha));
  V(g_pEffect.SetInt(g_hSpecularPower, pMaterial.nShininess));

  V(g_pEffect.SetTechnique(pMaterial.hTechnique));
  V(g_pEffect._Begin(@cPasses, 0));

  for iPass := 0 to cPasses - 1 do
  begin
    V(g_pEffect.BeginPass(iPass));

    // The effect interface queues up the changes and performs them
    // with the CommitChanges call. You do not need to call CommitChanges if
    // you are not setting any parameters between the BeginPass and EndPass.
    // V( g_pEffect->CommitChanges() );

    // Render the mesh with the applied technique
    V(pMesh.DrawSubset(iSubset));

    V(g_pEffect.EndPass);
  end;
  V(g_pEffect._End);
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

  // Output statistics
  txtHelper._Begin;
  txtHelper.SetInsertionPos(5, 5);
  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));
  txtHelper.DrawTextLine(DXUTGetFrameStats);
  txtHelper.DrawTextLine(DXUTGetDeviceStats);

  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
  txtHelper.DrawTextLine(g_strFileSaveMessage);

  // Draw help
  if g_bShowHelp then
  begin
    pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*5);
    txtHelper.SetForegroundColor(D3DXColorFromDWord(D3DCOLOR_ARGB(200, 50, 50, 50)));
    txtHelper.DrawTextLine('Controls (F1 to hide):');

    txtHelper.SetInsertionPos(20, pd3dsdBackBuffer.Height-15*4);
    txtHelper.DrawTextLine('Rotate model: Left mouse button'#10+
                           'Rotate camera: Right mouse button'#10+
                           'Zoom camera: Mouse wheel scroll'#10);

    txtHelper.SetInsertionPos(250, pd3dsdBackBuffer.Height-15*4);
    txtHelper.DrawTextLine('Hide help: F1'#10);
    txtHelper.DrawTextLine('Quit: ESC'#10);
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
  if Assigned(g_Camera) then g_Camera.HandleMessages(hWnd, uMsg, wParam, lParam);

  Result:= 0;
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
    IDC_SAVETOX:          SaveMeshToXFile;
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
  SAFE_RELEASE(g_pEffect);
  SAFE_RELEASE(g_pFont);

  if Assigned(g_MeshLoader) then g_MeshLoader.DestroyMesh;
end;


//--------------------------------------------------------------------------------------
// Saves the mesh to X-file
//--------------------------------------------------------------------------------------
procedure SaveMeshToXFile;
var
  hr: HRESULT;
  numMaterials: LongWord;
  pMaterials: PD3DXMaterialArray;
  pStrTexture: PChar;
  i: Integer;
  pMat: PMaterial;
  strBuf: array[0..MAX_PATH-1] of WideChar;
begin
  // Fill out D3DXMATERIAL structures
  numMaterials := g_MeshLoader.NumMaterials;
  GetMem(pMaterials, SizeOf(TD3DXMaterial)*numMaterials);
  GetMem(pStrTexture, SizeOf(Char)*MAX_PATH*numMaterials);
  try
    for i := 0 to g_MeshLoader.NumMaterials - 1 do
    begin
      pMat := g_MeshLoader.Material[i];
      if (pMat <> nil) then
      begin
        pMaterials[i].MatD3D.Ambient.r := pMat.vAmbient.x;
        pMaterials[i].MatD3D.Ambient.g := pMat.vAmbient.y;
        pMaterials[i].MatD3D.Ambient.b := pMat.vAmbient.z;
        pMaterials[i].MatD3D.Ambient.a := pMat.fAlpha;

        pMaterials[i].MatD3D.Diffuse.r := pMat.vDiffuse.x;
        pMaterials[i].MatD3D.Diffuse.g := pMat.vDiffuse.y;
        pMaterials[i].MatD3D.Diffuse.b := pMat.vDiffuse.z;
        pMaterials[i].MatD3D.Diffuse.a := pMat.fAlpha;

        pMaterials[i].MatD3D.Specular.r := pMat.vSpecular.x;
        pMaterials[i].MatD3D.Specular.g := pMat.vSpecular.y;
        pMaterials[i].MatD3D.Specular.b := pMat.vSpecular.z;
        pMaterials[i].MatD3D.Specular.a := pMat.fAlpha;

        pMaterials[i].MatD3D.Emissive.r := 0;
        pMaterials[i].MatD3D.Emissive.g := 0;
        pMaterials[i].MatD3D.Emissive.b := 0;
        pMaterials[i].MatD3D.Emissive.a := 0;

        pMaterials[i].MatD3D.Power := pMat.nShininess;

        WideCharToMultiByte(CP_ACP, 0, pMat.strTexture, -1, (pStrTexture + i*MAX_PATH), MAX_PATH, nil, nil);
        pMaterials[i].pTextureFilename := (pStrTexture + i*MAX_PATH);
      end;
    end;

    // Write to file in same directory where the .obj file was found
    StringCchFormat(strBuf, MAX_PATH-1, '%s\%s', [g_MeshLoader.MediaDirectory, 'MeshFromOBJ.x']);
    hr := D3DXSaveMeshToXW(strBuf, g_MeshLoader.Mesh, nil,
                           @pMaterials[0], nil, numMaterials,
                           D3DXF_FILEFORMAT_TEXT);

    if SUCCEEDED(hr) then
    begin
      StringCchFormat(g_strFileSaveMessage, MAX_PATH-1, 'Created %s', [strBuf]);
    end else
    begin
      DXTRACE_ERR('SaveMeshToXFile.D3DXSaveMeshToX', hr);
      StringCchFormat(g_strFileSaveMessage, MAX_PATH-1, 'Error creating %s, check debug output', [strBuf]);
    end;
  finally
    FreeMem(pMaterials);
    FreeMem(pStrTexture);
  end;
end;


procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera:= CModelViewerCamera.Create; // A model viewing camera
  g_HUD:= CDXUTDialog.Create; // manages the 3D UI
  g_SampleUI:= CDXUTDialog.Create; // dialog for sample specific controls
  g_MeshLoader:= CMeshLoader.Create;    // Loads a mesh from an .obj file
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_MeshLoader);
  FreeAndNil(g_Camera);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);
end;

end.

