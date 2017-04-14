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
 *  $Id: CustomUIUnit.pas,v 1.19 2007/02/05 22:21:04 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: CustomUI.cpp
//
// Starting point for new Direct3D applications
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit CustomUIUnit;

interface

uses
  Windows, SysUtils, StrSafe,
  DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTmesh, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont:        ID3DXFont;          // Font for drawing text
  g_pTextSprite:  ID3DXSprite;        // Sprite for batching draw text calls
  g_pEffect:      ID3DXEffect;        // D3DX effect interface
  g_Mesh:         CDXUTMesh;          // Background mesh
  g_mView:        TD3DXMatrixA16;
  g_Camera:       CModelViewerCamera; // A model viewing camera
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg:  CD3DSettingsDlg;    // Device settings dialog
  g_HUD:          CDXUTDialog;        // dialog for standard controls
  g_SampleUI:     CDXUTDialog;        // dialog for sample specific controls


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_EDITBOX1            = 5;
  IDC_EDITBOX2            = 6;
  IDC_ENABLEIME           = 7;
  IDC_DISABLEIME          = 8;
  IDC_COMBOBOX            = 9;
  IDC_STATIC              = 10;
  IDC_OUTPUT              = 12;
  IDC_SLIDER              = 13;
  IDC_CHECKBOX            = 14;
  IDC_CLEAREDIT           = 15;
  IDC_RADIO1A             = 16;
  IDC_RADIO1B             = 17;
  IDC_RADIO1C             = 18;
  IDC_RADIO2A             = 19;
  IDC_RADIO2B             = 20;
  IDC_RADIO2C             = 21;
  IDC_LISTBOX             = 22;
  IDC_LISTBOXM            = 23;


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

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;

implementation


//--------------------------------------------------------------------------------------
// Initialize the app
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  iY: Integer;
  pIMEEdit: CDXUTIMEEditBox;
  pCombo: CDXUTComboBox;
  i: Integer;
  wszText: WideString;
begin
  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_SampleUI.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent); iY := 10;
  g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22); Inc(iY, 24);
  g_HUD.AddButton(IDC_TOGGLEREF,        'Toggle REF (F3)',    35, iY, 125, 22); Inc(iY, 24);
  g_HUD.AddButton(IDC_CHANGEDEVICE,     'Change device (F2)', 35, iY, 125, 22, VK_F2); // Inc(iY, 24);

  g_SampleUI.SetCallback(OnGUIEvent);
  g_SampleUI.SetFont(1, 'Comic Sans MS', 24, FW_NORMAL);
  g_SampleUI.SetFont(2, 'Courier New', 16, FW_NORMAL);

  // Static
  g_SampleUI.AddStatic(IDC_STATIC, 'This is a static control.', 0, 0, 200, 30 );
  g_SampleUI.AddStatic(IDC_OUTPUT, 'This static control provides feedback for your action.  It will change as you interact with the UI controls.', 20, 50, 620, 300 );
  g_SampleUI.GetStatic(IDC_OUTPUT).TextColor:= D3DCOLOR_ARGB(255, 255, 0, 0); // Change color to red
  g_SampleUI.GetStatic(IDC_STATIC).TextColor:= D3DCOLOR_ARGB(255, 0, 255, 0); // Change color to green
  g_SampleUI.GetControl(IDC_OUTPUT).Element[0].dwTextFormat := DT_LEFT or DT_TOP or DT_WORDBREAK;
  g_SampleUI.GetControl(IDC_OUTPUT).Element[0].iFont := 2;
  g_SampleUI.GetControl(IDC_STATIC).Element[0].dwTextFormat := DT_CENTER or DT_VCENTER or DT_WORDBREAK;

  // Buttons
  g_SampleUI.AddButton(IDC_ENABLEIME,  'Enable (I)ME',  30, 390, 80, 35, Ord('I'));
  g_SampleUI.AddButton(IDC_DISABLEIME, 'Disable I(M)E', 30, 430, 80, 35, Ord('M'));

  // Edit box
  g_SampleUI.AddEditBox(IDC_EDITBOX1, 'Edit control with default styles. Type text here and press Enter', 20, 440, 600, 32);

  // IME-enabled edit box
  if SUCCEEDED(g_SampleUI.AddIMEEditBox(IDC_EDITBOX2,
       'IME-capable edit control with custom styles. Type and press Enter',
       20, 390, 600, 45, False, @pIMEEdit)) then 
  begin
    pIMEEdit.Element[0].iFont := 1;
    pIMEEdit.Element[1].iFont := 1;
    pIMEEdit.Element[9].iFont := 1;
    pIMEEdit.Element[0].TextureColor.Init(D3DCOLOR_ARGB( 128, 255, 255, 255 ));  // Transparent center
    pIMEEdit.BorderWidth := 7;
    pIMEEdit.TextColor := D3DCOLOR_ARGB(255, 64, 64, 64);
    pIMEEdit.CaretColor := D3DCOLOR_ARGB(255, 64, 64, 64);
    pIMEEdit.SelectedTextColor := D3DCOLOR_ARGB(255, 255, 255, 255);
    pIMEEdit.SelectedBackColor := D3DCOLOR_ARGB(255, 40, 72, 72);
  end;

  // Slider
  g_SampleUI.AddSlider(IDC_SLIDER, 200, 450, 200, 24, 0, 100, 50, False);

  // Checkbox
  g_SampleUI.AddCheckBox(IDC_CHECKBOX, 'This is a checkbox with hotkey. Press ''C'' to toggle the check state.',
                         170, 450, 350, 24, False, Ord('C'), False );
  g_SampleUI.AddCheckBox(IDC_CLEAREDIT, 'This checkbox controls whether edit control text is cleared when Enter is pressed. (T)',
                         170, 460, 450, 24, False, Ord('T'), False );

  // Combobox
  g_SampleUI.AddComboBox(IDC_COMBOBOX, 0, 0, 200, 24, Ord('O'), False, @pCombo);
  if (pCombo <> nil) then
  begin
    pCombo.SetDropHeight(100);
    pCombo.AddItem('Combobox item (O)', Pointer($11111111));
    pCombo.AddItem('Placeholder (O)', Pointer($12121212));
    pCombo.AddItem('One more (O)', Pointer($13131313));
    pCombo.AddItem('I can''t get enough (O)', Pointer($14141414));
    pCombo.AddItem('Ok, last one, I promise (O)', Pointer($15151515));
  end;

  // Radio buttons
  g_SampleUI.AddRadioButton(IDC_RADIO1A, 1, 'Radio group 1 Amy (1)', 0, 50, 220, 24, False, Ord('1'));
  g_SampleUI.AddRadioButton(IDC_RADIO1B, 1, 'Radio group 1 Brian (2)', 0, 50, 220, 24, False, Ord('2'));
  g_SampleUI.AddRadioButton(IDC_RADIO1C, 1, 'Radio group 1 Clark (3)', 0, 50, 220, 24, False, Ord('3'));

  g_SampleUI.AddRadioButton(IDC_RADIO2A, 2, 'Single (4)', 0, 50, 90, 24, False, Ord('4'));
  g_SampleUI.AddRadioButton(IDC_RADIO2B, 2, 'Double (5)', 0, 50, 90, 24, False, Ord('5'));
  g_SampleUI.AddRadioButton(IDC_RADIO2C, 2, 'Triple (6)', 0, 50, 90, 24, False, Ord('6'));

  // List box
  g_SampleUI.AddListBox(IDC_LISTBOX, 30, 400, 200, 150, NORMAL);
  for i := 0 to 14 do
  begin
    wszText := WideFormat('Single-selection listbox item %d', [i]);
    g_SampleUI.GetListBox(IDC_LISTBOX).AddItem(PWideChar(wszText), Pointer(size_t(i)));
  end;
  g_SampleUI.AddListBox(IDC_LISTBOXM, 30, 400, 200, 150, MULTISELECTION);
  for i := 0 to 29 do
  begin
    wszText := WideFormat('Multi-selection listbox item %d', [i]);
    g_SampleUI.GetListBox(IDC_LISTBOXM).AddItem(PWideChar(wszText), Pointer(size_t(i)));
  end;
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
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2, 0)) then Exit;

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
  dwShaderFlags: DWORD;
  str: array[0..MAX_PATH-1] of WideChar;
  vecEye, vecAt, vecUp: TD3DXVector3;
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

  // Read the D3DX effect file
  Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, WideString('CustomUI.fx'));
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // they the .fx file failed to compile
  Result := D3DXCreateEffectFromFileW(pd3dDevice, @str, nil, nil, dwShaderFlags,
                                     nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  g_Mesh.CreateMesh(pd3dDevice, WideString('misc\cell.x'));

  // Setup the camera's view parameters
  vecEye:= D3DXVector3(0.0, 1.5, -7.0);
  vecAt:= D3DXVector3(0.0, 0.2, 0.0);
  vecUp:= D3DXVector3(0.0, 1.0, 0.0);
  g_Camera.SetViewParams(vecEye, vecAt);
  D3DXMatrixLookAtLH(g_mView, vecEye, vecAt, vecUp);

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

  Result := D3DXLoadMeshFromX(@str, D3DXMESH_MANAGED, pd3dDevice, nil, nil, nil, nil, pMesh);
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

  // Create a sprite to help batch calls when drawing many lines of text
  Result := D3DXCreateSprite(pd3dDevice, g_pTextSprite);
  if V_Failed(Result) then Exit;

  // Setup the camera's projection parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI/4, fAspectRatio, 0.1, 1000.0);
  g_Camera.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation(0, 0);
  g_SampleUI.SetSize(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);

  g_SampleUI.GetControl(IDC_STATIC).SetSize(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height * 6 div 10);
  g_SampleUI.GetControl(IDC_OUTPUT).SetSize(pBackBufferSurfaceDesc.Width - 170, pBackBufferSurfaceDesc.Height div 4);
  g_SampleUI.GetControl(IDC_EDITBOX1).SetLocation(20, pBackBufferSurfaceDesc.Height - 230);
  g_SampleUI.GetControl(IDC_EDITBOX1).SetSize(pBackBufferSurfaceDesc.Width - 40, 32);
  g_SampleUI.GetControl(IDC_EDITBOX2).SetLocation(20, pBackBufferSurfaceDesc.Height - 280);
  g_SampleUI.GetControl(IDC_EDITBOX2).SetSize(pBackBufferSurfaceDesc.Width - 40, 45);
  g_SampleUI.GetControl(IDC_ENABLEIME).SetLocation(130, pBackBufferSurfaceDesc.Height - 80);
  g_SampleUI.GetControl(IDC_DISABLEIME).SetLocation(220, pBackBufferSurfaceDesc.Height - 80);
  g_SampleUI.GetControl(IDC_SLIDER).SetLocation(10, pBackBufferSurfaceDesc.Height - 140);
  g_SampleUI.GetControl(IDC_CHECKBOX).SetLocation(120, pBackBufferSurfaceDesc.Height - 50);
  g_SampleUI.GetControl(IDC_CLEAREDIT).SetLocation(120, pBackBufferSurfaceDesc.Height - 25);
  g_SampleUI.GetControl(IDC_COMBOBOX).SetLocation(20, pBackBufferSurfaceDesc.Height - 180);
  g_SampleUI.GetControl(IDC_RADIO1A).SetLocation(pBackBufferSurfaceDesc.Width - 160, 100);
  g_SampleUI.GetControl(IDC_RADIO1B).SetLocation(pBackBufferSurfaceDesc.Width - 160, 124);
  g_SampleUI.GetControl(IDC_RADIO1C).SetLocation(pBackBufferSurfaceDesc.Width - 160, 148);
  g_SampleUI.GetControl(IDC_RADIO2A).SetLocation(20, pBackBufferSurfaceDesc.Height - 100);
  g_SampleUI.GetControl(IDC_RADIO2B).SetLocation(20, pBackBufferSurfaceDesc.Height - 76);
  g_SampleUI.GetControl(IDC_RADIO2C).SetLocation(20, pBackBufferSurfaceDesc.Height - 52);
  g_SampleUI.GetControl(IDC_LISTBOX).SetLocation(pBackBufferSurfaceDesc.Width - 400, pBackBufferSurfaceDesc.Height - 180);
  g_SampleUI.GetControl(IDC_LISTBOX).SetSize(190, 96);
  g_SampleUI.GetControl(IDC_LISTBOXM).SetLocation(pBackBufferSurfaceDesc.Width - 200, pBackBufferSurfaceDesc.Height - 180);
  g_SampleUI.GetControl(IDC_LISTBOXM).SetSize(190, 124);
  g_Mesh.RestoreDeviceObjects(pd3dDevice);

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
begin
  D3DXMatrixRotationY(m, D3DX_PI * fElapsedTime / 40.0);
  D3DXMatrixMultiply(g_mView, m, g_mView);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called at the end of every frame to perform all the 
// rendering calls for the scene, and it will also be called if the window needs to be 
// repainted. After this function has returned, DXUT will call
// IDirect3DDevice9::Present to display the contents of the next buffer in the swap chain
//--------------------------------------------------------------------------------------
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  mat: TD3DXMatrixA16;
  mWorld: TD3DXMatrixA16;
  mView: TD3DXMatrixA16;
  mProj: TD3DXMatrixA16;
  mWorldViewProjection: TD3DXMatrixA16;
  cPasses: LongWord;
  pMesh: ID3DXMesh;
  p, m: Integer;
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
    // Get the projection & view matrix from the camera class
    mWorld := g_Camera.GetWorldMatrix^;
    mProj := g_Camera.GetProjMatrix^;
    mView := g_mView;

    // mWorldViewProjection = mWorld * mView * mProj;
    D3DXMatrixMultiply(mat, mView, mProj);
    D3DXMatrixMultiply(mWorldViewProjection, mWorld, mat);


    // Update the effect's variables.  Instead of using strings, it would
    // be more efficient to cache a handle to the parameter by calling
    // ID3DXEffect::GetParameterByName
    V(g_pEffect.SetMatrix('g_mWorldViewProjection', mWorldViewProjection));
    V(g_pEffect.SetMatrix('g_mWorld', mWorld));
    V(g_pEffect.SetFloat('g_fTime', fTime));

    if (GetDXUTState.Caps.PixelShaderVersion < D3DPS_VERSION(1, 1))
      then g_pEffect.SetTechnique('no_ps_HW')
      else g_pEffect.SetTechnique('RenderScene');

    g_pEffect._Begin(@cPasses, 0);
    pMesh := g_Mesh.Mesh;
    for p := 0 to cPasses - 1 do
    begin
      g_pEffect.BeginPass(p);
      for m := 0 to g_Mesh.m_dwNumMaterials - 1 do
      begin
        g_pEffect.SetTexture('g_txScene', g_Mesh.m_pTextures[m]);
        g_pEffect.CommitChanges;
        pMesh.DrawSubset(m);
      end;
      g_pEffect.EndPass;
    end;
    g_pEffect._End;

    RenderText;
    V(g_HUD.OnRender(fElapsedTime));
    V(g_SampleUI.OnRender(fElapsedTime));

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
begin
  // The helper object simply helps keep track of text position, and color
  // and then it calls pFont->DrawText( m_pSprite, strMsg, -1, &rc, DT_NOCLIP, m_clr );
  // If NULL is passed in as the sprite object, then it will work however the
  // pFont->DrawText() will not be batched together.  Batching calls will improves performance.
  txtHelper:= CDXUTTextHelper.Create(g_pFont, g_pTextSprite, 15 );
  try
    // Output statistics
    txtHelper._Begin;
    txtHelper.SetInsertionPos(5, 5);
    txtHelper.SetForegroundColor(D3DXCOLOR(1.0, 1.0, 0.0, 1.0));
    txtHelper.DrawTextLine(DXUTGetFrameStats);
    txtHelper.DrawTextLine(DXUTGetDeviceStats);

    txtHelper.SetForegroundColor(D3DXCOLOR(1.0, 1.0, 1.0, 1.0));

    // Draw help
    txtHelper.SetForegroundColor(D3DXCOLOR(1.0, 1.0, 1.0, 1.0));
    txtHelper.DrawTextLine('Press ESC to quit');
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
end;


//--------------------------------------------------------------------------------------
// Handles the GUI events
//--------------------------------------------------------------------------------------
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
var
  wszOutput: array[0..1023] of WideChar;
  pItem: PDXUTComboBoxItem;
  pListItem: PDXUTListBoxItem ;
  nSelected: Integer;
begin
  FillChar(wszOutput, SizeOf(wszOutput), 0);
  
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;
    IDC_ENABLEIME:
    begin
      CDXUTIMEEditBox.EnableImeSystem(True);
      g_SampleUI.GetStatic(IDC_OUTPUT).Text := 'You clicked the ''Enable IME'' button.'#10'IME text input is enabled for IME-capable edit controls.';
    end;

    IDC_DISABLEIME:
    begin
      CDXUTIMEEditBox.EnableImeSystem(False);
      g_SampleUI.GetStatic(IDC_OUTPUT).Text := 'You clicked the ''Disable IME'' button.'#10'IME text input is disabled for IME-capable edit controls.';
    end;

    IDC_EDITBOX1,
    IDC_EDITBOX2:
    case nEvent of
      EVENT_EDITBOX_STRING:
      begin
        StringCchFormat(wszOutput, 1024, 'You have pressed Enter in edit control (ID %u).'#10'The content of the edit control is:'#10'"%s"',
                        [nControlID, CDXUTEditBox(pControl).Text]);
        g_SampleUI.GetStatic(IDC_OUTPUT).Text := wszOutput;

        // Clear the text if needed
        if g_SampleUI.GetCheckBox(IDC_CLEAREDIT).Checked
        then CDXUTEditBox(pControl).Text := '';
      end;

      EVENT_EDITBOX_CHANGE:
      begin
        StringCchFormat(wszOutput, 1024, 'You have changed the content of an edit control (ID %u).'#10'It is now:'#10'"%s"',
                        [nControlID, CDXUTEditBox(pControl).Text]);
        g_SampleUI.GetStatic(IDC_OUTPUT).Text := wszOutput;
      end;
    end;

    IDC_SLIDER:
    begin
      StringCchFormat(wszOutput, 1024, 'You adjusted the slider control.'#10'The new value reported is %d',
                      [CDXUTSlider(pControl).Value]);
      g_SampleUI.GetStatic(IDC_OUTPUT).Text := wszOutput;
    end;

    IDC_CHECKBOX:
    begin
      StringCchFormat(wszOutput, 1024, 'You %s the upper check box.',
                      [IfThen(CDXUTCheckBox(pControl).Checked, 'checked', 'cleared')]);
      g_SampleUI.GetStatic(IDC_OUTPUT).Text := wszOutput;
    end;

    IDC_CLEAREDIT:
    begin
      StringCchFormat(wszOutput, 1024, 'You %s the lower check box.'#10'Now edit controls will %s',
                      [IfThen(CDXUTCheckBox(pControl).Checked, 'checked', 'cleared'),
                       IfThen(CDXUTCheckBox(pControl).Checked, 'be cleared when you press Enter to send the text', 'retain the text context when you press Enter to send the text')]);
      g_SampleUI.GetStatic(IDC_OUTPUT).Text := wszOutput;
    end;

    IDC_COMBOBOX:
    begin
      pItem := CDXUTComboBox(pControl).GetSelectedItem;
      if Assigned(pItem) then
      begin
        {todo: Fill BUG REPORT to Borland -> D7 - WideFormatBuf('%p') - @CvtPointer: - CvtInt -> CvtIntW
               Check: if FPC have the similiar bug?
               Well it's still not fixed in D9, althrow been corrected in
               TNT Unicode Controls long time ago :-((( }
        StringCchFormat(wszOutput, 1024, 'You selected a new item in the combobox.'#10 +
                        'The new item is "%s" and the associated data value is 0x%x', //was: '0x%p' and Pointer(pItem.pData)
                        {$IFDEF FPC}
                        [PWideChar(pItem.strText), pItem.pData]);
                        {$ELSE}
                        [pItem.strText, Integer(pItem.pData)]);
                        {$ENDIF}
        g_SampleUI.GetStatic(IDC_OUTPUT).Text := wszOutput;
      end;
    end;


    IDC_RADIO1A,
    IDC_RADIO1B,
    IDC_RADIO1C:
    begin
      StringCchFormat(wszOutput, 1024, 'You selected a new radio button in the UPPER radio group.'#10'The new button is "%s"',
                      [CDXUTRadioButton(pControl).Text]);
      g_SampleUI.GetStatic(IDC_OUTPUT).Text := wszOutput;
    end;

    IDC_RADIO2A,
    IDC_RADIO2B,
    IDC_RADIO2C:
    begin
      StringCchFormat(wszOutput, 1024, 'You selected a new radio button in the LOWER radio group.'#10'The new button is "%s"',
                      [CDXUTRadioButton(pControl).Text]);
      g_SampleUI.GetStatic(IDC_OUTPUT).Text := wszOutput;
    end;

    IDC_LISTBOX:
    case nEvent of
      EVENT_LISTBOX_ITEM_DBLCLK:
      begin
        pListItem := CDXUTListBox(pControl).GetItem(CDXUTListBox(pControl).GetSelectedIndex(-1));

        StringCchFormat(wszOutput, 1024, 'You double clicked an item in the left list box.  The item is'#10'"%s"',
        {$IFDEF FPC}
          [IfThen(pListItem<>nil, PWideChar(pListItem.strText), '')]);
        {$ELSE}
          [IfThen(pListItem<>nil, pListItem.strText, '')]);
        {$ENDIF}
        g_SampleUI.GetStatic(IDC_OUTPUT).Text := wszOutput;
      end;

      EVENT_LISTBOX_SELECTION:
      begin
        StringCchFormat(wszOutput, 1024, 'You changed the selection in the left list box.  The selected item is %d',
            [CDXUTListBox(pControl).GetSelectedIndex]);
        g_SampleUI.GetStatic(IDC_OUTPUT).Text := wszOutput;
      end;
    end;

    IDC_LISTBOXM:
    case nEvent of
      EVENT_LISTBOX_ITEM_DBLCLK:
      begin
        pListItem := CDXUTListBox(pControl).GetItem(CDXUTListBox(pControl).GetSelectedIndex(-1));

        StringCchFormat(wszOutput, 1024, 'You double clicked an item in the right list box.  The item is'#10'"%s"',
        {$IFDEF FPC}
             [IfThen(pListItem<>nil, PWideChar(pListItem.strText), '')]);
        {$ELSE}
             [IfThen(pListItem<>nil, pListItem.strText, '')]);
        {$ENDIF}
        g_SampleUI.GetStatic(IDC_OUTPUT).Text := wszOutput;
      end;

      EVENT_LISTBOX_SELECTION:
      begin
        StringCchFormat(wszOutput, 1024, 'You changed the selection in the right list box.  The selected item(s) are'#10, []);
        nSelected := -1;

        nSelected := CDXUTListBox(pControl).GetSelectedIndex(nSelected);
        while (nSelected <> -1) do
        begin
          {$IFDEF FPC}
          StringCchFormat(PWideChar(wszOutput + 2*lstrlenW(wszOutput)), 1024 - lstrlenW(wszOutput), '%d,', [nSelected]);
          {$ELSE}
          StringCchFormat(PWideChar(wszOutput + lstrlenW(wszOutput)), 1024 - lstrlenW(wszOutput), '%d,', [nSelected]);
          {$ENDIF}
          nSelected := CDXUTListBox(pControl).GetSelectedIndex(nSelected);
        end;
        // Remove the trailing comma if one exists.
        if (wszOutput[lstrlenW(wszOutput)-1] = ',')
          then wszOutput[lstrlenW(wszOutput)-1] := #0;
        g_SampleUI.GetStatic(IDC_OUTPUT).Text := wszOutput;
      end;
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
  g_Mesh.InvalidateDeviceObjects;

  if (g_pFont <> nil) then g_pFont.OnLostDevice;
  if (g_pEffect <> nil) then g_pEffect.OnLostDevice;
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
  if Assigned(g_Mesh) then g_Mesh.DestroyMesh;

  SAFE_RELEASE(g_pEffect);
  SAFE_RELEASE(g_pFont);
end;


procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Mesh:=     CDXUTMesh.Create;          // Background mesh
  g_Camera:=   CModelViewerCamera.Create; // A model viewing camera
  g_HUD:=      CDXUTDialog.Create;        // dialog for standard controls
  g_SampleUI:= CDXUTDialog.Create;        // dialog for sample specific controls
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_Mesh); //Clootie: Mesh will be destroyed in DXState.Free...
  FreeAndNil(g_Camera);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);
end;

end.

