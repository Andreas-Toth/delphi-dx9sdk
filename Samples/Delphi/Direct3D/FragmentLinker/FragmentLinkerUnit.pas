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
 *  $Id: FragmentLinkerUnit.pas,v 1.18 2007/02/05 22:21:06 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: FragmentLinker.cpp
//
// Starting point for new Direct3D applications
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit FragmentLinkerUnit;

interface

uses
  Windows, Messages, SysUtils,
  DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTmesh, DXUTSettingsDlg;

//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont: ID3DXFont;                       // Font for drawing text
  g_pTextSprite: ID3DXSprite;               // Sprite for batching draw text calls
  g_Mesh: CDXUTMesh;                        // Mesh object
  g_Camera: CModelViewerCamera;             // A model viewing camera
  g_bShowHelp: Boolean = True;              // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg;           // Device settings dialog
  g_HUD: CDXUTDialog;                       // dialog for standard controls
  g_SampleUI: CDXUTDialog;                  // dialog for sample specific controls
  g_vObjectCenter: TD3DXVector3;            // Center of bounding sphere of object
  g_fObjectRadius: Single;                  // Radius of bounding sphere of object
  g_mCenterWorld: TD3DXMatrixA16;           // World matrix to center the mesh

  g_pFragmentLinker: ID3DXFragmentLinker;   // Fragment linker interface
  g_pCompiledFragments: ID3DXBuffer;        // Buffer containing compiled fragments

  g_pPixelShader:  IDirect3DPixelShader9;   // Pixel shader to be used
  g_pLinkedShader: IDirect3DVertexShader9;  // Vertex shader to be used; linked by LinkVertexShader
  g_pConstTable:   ID3DXConstantTable;      // g_pLinkedShader's constant table

  // Global variables used by the vertex shader
  g_vMaterialAmbient: TD3DXVector4 = (x: 0.3; y: 0.3; z:  0.3; w: 1.0);
  g_vMaterialDiffuse: TD3DXVector4 = (x: 0.6; y: 0.6; z:  0.6; w: 1.0);
  g_vLightColor:      TD3DXVector4 = (x: 1.0; y: 1.0; z:  1.0; w: 1.0);
  g_vLightPosition:   TD3DXVector4 = (x: 0.0; y: 5.0; z: -5.0; w: 1.0);

//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_STATIC              = -1;
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_ANIMATION           = 5;
  IDC_LIGHTING            = 6;



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

function LinkVertexShader: HRESULT;

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
  pComboBox: CDXUTComboBox;
begin
  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_SampleUI.Init(g_DialogResourceManager);

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

  g_SampleUI.AddStatic(IDC_STATIC, '(V)ertex Animation', 20, 0, 105, 25);
  g_SampleUI.AddComboBox(IDC_ANIMATION, 20, 25, 140, 24, Ord('V'), False, @pComboBox);
  if Assigned(pComboBox) then pComboBox.SetDropHeight(30);

  g_SampleUI.AddStatic(IDC_STATIC, '(L)ighting', 20, 50, 105, 25);
  g_SampleUI.AddComboBox(IDC_LIGHTING, 20, 75, 140, 24, Ord('L'), False, @pComboBox);
  if Assigned(pComboBox) then pComboBox.SetDropHeight(30);

  //g_SampleUI.AddCheckBox( IDC_ANIMATION, L"Vertex (A)nimation", 20, 60, 155, 20, true, 'A' );
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
  strPath: array [0..MAX_PATH-1] of WideChar;
  pVB: IDirect3DVertexBuffer9;
  pVertices: Pointer;
  pComboBox: CDXUTComboBox;
  vecEye, vecAt: TD3DXVector3;
  pCode: ID3DXBuffer;
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

  // Read the D3DX effect file

  // If this fails, there should be debug output as to
  // they the .fx file failed to compile

  Result:= DXUTFindDXSDKMediaFile(strPath, MAX_PATH, 'FragmentLinker.fx');
  if V_Failed(Result) then Exit;
  Result:= D3DXCompileShaderFromFileW(strPath, nil, nil, 'ModulateTexture', 'ps_2_0', 0, @pCode, nil, nil);
  if V_Failed(Result) then Exit;

  // Create the pixel shader
  Result := pd3dDevice.CreatePixelShader(pCode.GetBufferPointer, g_pPixelShader);
  if V_Failed(Result) then Exit;
  pCode := nil;
  Result:= pd3dDevice.SetPixelShader(g_pPixelShader);
  if V_Failed(Result) then Exit;

  // Load the mesh
  Result:= DXUTFindDXSDKMediaFile(strPath, MAX_PATH, 'dwarf\dwarf.x');
  if V_Failed(Result) then Exit;
  Result:= g_Mesh.CreateMesh(pd3dDevice, strPath);
  if V_Failed(Result) then Exit;

  // Find the mesh's center, then generate a centering matrix.
  Result:= g_Mesh.Mesh.GetVertexBuffer(pVB);
  if V_Failed(Result) then Exit;

  pVertices := nil;
  Result := pVB.Lock(0, 0, pVertices, 0);
  if FAILED(Result) then
  begin
    SAFE_RELEASE(pVB);
    Exit;
  end;

  Result := D3DXComputeBoundingSphere(PD3DXVector3(pVertices), g_Mesh.Mesh.GetNumVertices,
                                      D3DXGetFVFVertexSize(g_Mesh.Mesh.GetFVF), g_vObjectCenter,
                                      g_fObjectRadius);
  pVB.Unlock;
  SAFE_RELEASE(pVB);

  if Failed(Result) then Exit;

  D3DXMatrixTranslation(g_mCenterWorld, -g_vObjectCenter.x, -g_vObjectCenter.y, -g_vObjectCenter.z);

  // Create the fragment linker interface
  Result:= D3DXCreateFragmentLinker(pd3dDevice, 0, g_pFragmentLinker);
  if V_Failed(Result) then Exit;

  // Compile the fragments to a buffer. The fragments must be linked together to form
  // a shader before they can be used for rendering.
  Result:= DXUTFindDXSDKMediaFile(strPath, MAX_PATH, 'FragmentLinker.fx');
  if V_Failed(Result) then Exit;
  Result:= D3DXGatherFragmentsFromFileW(strPath, nil, nil, 0, g_pCompiledFragments, nil);
  if V_Failed(Result) then Exit;

  // Build the list of compiled fragments
  Result:= g_pFragmentLinker.AddFragments(PDWORD(g_pCompiledFragments.GetBufferPointer));
  if V_Failed(Result) then Exit;

  // Store the fragment handles
  pComboBox := g_SampleUI.GetComboBox(IDC_LIGHTING);
  pComboBox.RemoveAllItems;
  pComboBox.AddItem('Ambient', g_pFragmentLinker.GetFragmentHandleByName('AmbientFragment'));
  pComboBox.AddItem('Ambient & Diffuse', g_pFragmentLinker.GetFragmentHandleByName('AmbientDiffuseFragment'));

  pComboBox := g_SampleUI.GetComboBox(IDC_ANIMATION);
  pComboBox.RemoveAllItems;
  pComboBox.AddItem('On',  g_pFragmentLinker.GetFragmentHandleByName('ProjectionFragment_Animated'));
  pComboBox.AddItem('Off', g_pFragmentLinker.GetFragmentHandleByName('ProjectionFragment_Static'));

  // Link the desired fragments to create the vertex shader
  Result:= LinkVertexShader;
  if V_Failed(Result) then Exit;

  // Setup the camera's view parameters
  vecEye := D3DXVector3(3.0, 0.0, -3.0);
  vecAt  := D3DXVector3(0.0, 0.0, -0.0);
  g_Camera.SetViewParams(vecEye, vecAt);

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// Link together compiled fragments to create a vertex shader. The list of fragments
// used is determined by the currently selected UI options.
//--------------------------------------------------------------------------------------
function LinkVertexShader: HRESULT;
const
  NUM_FRAGMENTS = 2;
var
  pCode: ID3DXBuffer;
  pShaderCode: PDWORD;
  pd3dDevice: IDirect3DDevice9;
  aHandles: array[0..NUM_FRAGMENTS-1] of TD3DXHandle;
begin
  pd3dDevice:= DXUTGetD3DDevice;

  aHandles[0] := g_SampleUI.GetComboBox(IDC_ANIMATION).GetSelectedData;
  aHandles[1] := g_SampleUI.GetComboBox(IDC_LIGHTING).GetSelectedData;

  SAFE_RELEASE(g_pLinkedShader);

  // Link the fragments together to form a shader
  Result:= g_pFragmentLinker.LinkShader('vs_2_0', 0, @aHandles, NUM_FRAGMENTS, pCode, nil);
  if V_Failed(Result) then Exit;
  pShaderCode := pCode.GetBufferPointer;
  Result:= pd3dDevice.CreateVertexShader(pShaderCode, g_pLinkedShader);
  if V_Failed(Result) then Exit;
  Result:= D3DXGetShaderConstantTable(pShaderCode, g_pConstTable);
  if V_Failed(Result) then Exit;

  SAFE_RELEASE(pCode);

  // Set global variables
  Result:= pd3dDevice.SetVertexShader(g_pLinkedShader);
  if V_Failed(Result) then Exit;

  if Assigned(g_pConstTable) then
  begin
    g_pConstTable.SetVector(pd3dDevice, 'g_vMaterialAmbient', g_vMaterialAmbient);
    g_pConstTable.SetVector(pd3dDevice, 'g_vMaterialDiffuse', g_vMaterialDiffuse);
    g_pConstTable.SetVector(pd3dDevice, 'g_vLightColor',      g_vLightColor);
    g_pConstTable.SetVector(pd3dDevice, 'g_vLightPosition',   g_vLightPosition);
  end;
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
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, strFileName);
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
  GetMem(rgdwAdjacency, SizeOf(DWORD)*pMesh.GetNumFaces*3);
  if (rgdwAdjacency = nil) then
  begin
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

  g_Mesh.RestoreDeviceObjects(pd3dDevice);

  // Create a sprite to help batch calls when drawing many lines of text
  Result:= D3DXCreateSprite(pd3dDevice, g_pTextSprite);
  if V_Failed(Result) then Exit;

  // Setup the camera's projection parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI/4, fAspectRatio, 0.1, 1000.0);
  g_Camera.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation(pBackBufferSurfaceDesc.Width-170, pBackBufferSurfaceDesc.Height-350);
  g_SampleUI.SetSize(170, 300);

  LinkVertexShader;

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
  m, mWorld, mView, mProj: TD3DXMatrixA16;
  mWorldViewProjection: TD3DXMatrixA16;
begin
  // Update the camera's position based on user input
  g_Camera.FrameMove(fElapsedTime);

  // Get the projection & view matrix from the camera class
  D3DXMatrixMultiply(mWorld, g_mCenterWorld, g_Camera.GetWorldMatrix^);
  mProj := g_Camera.GetProjMatrix^;
  mView := g_Camera.GetViewMatrix^;

  // mWorldViewProjection = mWorld * mView * mProj;
  D3DXMatrixMultiply(m, mView, mProj);
  D3DXMatrixMultiply(mWorldViewProjection, mWorld, m);

  // Update the effect's variables.  Instead of using strings, it would
  // be more efficient to cache a handle to the parameter by calling
  // ID3DXEffect::GetConstantByName

  // Ignore return codes because not all variables might be present in
  // the constant table depending on which fragments were linked.

  if Assigned(g_pConstTable) then 
  begin
    g_pConstTable.SetMatrix(pd3dDevice, 'g_mWorldViewProjection', mWorldViewProjection);
    g_pConstTable.SetMatrix(pd3dDevice, 'g_mWorld', mWorld);
    g_pConstTable.SetFloat(pd3dDevice, 'g_fTime', fTime);
  end;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called at the end of every frame to perform all the
// rendering calls for the scene, and it will also be called if the window needs to be
// repainted. After this function has returned, DXUT will call 
// IDirect3DDevice9::Present to display the contents of the next buffer in the swap chain
//--------------------------------------------------------------------------------------
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
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
    pd3dDevice.SetSamplerState(0, D3DSAMP_MIPFILTER, D3DTEXF_LINEAR);
    pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);
    pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);

    V(g_Mesh.Render(pd3dDevice));

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
    txtHelper.DrawTextLine(DXUTGetFrameStats);
    txtHelper.DrawTextLine(DXUTGetDeviceStats);
    txtHelper.DrawTextLine('Selected fragments are linked on-the-fly to create the current shader');
    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));

    // Draw help
    if g_bShowHelp then
    begin
      pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
      txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*6);
      txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
      txtHelper.DrawTextLine('Controls:');

      txtHelper.SetInsertionPos(20, pd3dsdBackBuffer.Height-15*5);
      txtHelper.DrawTextLine('Rotate model: Left mouse button'#10+
                             'Rotate camera: Right mouse button'#10+
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
  pbNoFurtherProcessing :=g_DialogResourceManager.MsgProc(hWnd, uMsg, wParam, lParam);
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
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;
    IDC_ANIMATION:        LinkVertexShader;
    IDC_LIGHTING:         LinkVertexShader;
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
  if Assigned(g_Mesh) then g_Mesh.InvalidateDeviceObjects;
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
  SAFE_RELEASE(g_pPixelShader);
  SAFE_RELEASE(g_pLinkedShader);
  SAFE_RELEASE(g_pFont);
  if Assigned(g_Mesh) then g_Mesh.DestroyMesh;
  SAFE_RELEASE(g_pFragmentLinker);
  SAFE_RELEASE(g_pCompiledFragments);
end;


procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Mesh:= CDXUTMesh.Create;                         // Mesh object
  g_Camera := CModelViewerCamera.Create;             // A model viewing camera
  g_HUD := CDXUTDialog.Create;                       // dialog for standard controls
  g_SampleUI := CDXUTDialog.Create;                  // dialog for sample specific controls
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_Mesh);
  FreeAndNil(g_Camera);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);
end;

end.

