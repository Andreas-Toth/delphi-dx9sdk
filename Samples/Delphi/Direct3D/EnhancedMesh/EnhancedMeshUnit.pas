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
 *  $Id: EnhancedMeshUnit.pas,v 1.17 2007/02/05 22:21:06 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: EnhancedMesh.cpp
//
// Starting point for new Direct3D applications
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit EnhancedMeshUnit;

interface

uses
  Windows, SysUtils, StrSafe,
  DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTenum, DXUTmesh, DXUTmisc, DXUTgui, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders

const
  MESHFILENAME = 'dwarf\dwarf.x';

type
  PD3DXMaterialArray = ^TD3DXMaterialArray;
  TD3DXMaterialArray = array[0..0] of TD3DXMaterial;

  PIDirect3DTexture9Array = ^IDirect3DTexture9Array;
  IDirect3DTexture9Array = array[0..0] of IDirect3DTexture9;

//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont: ID3DXFont               = nil;  // Font for drawing text
  g_pTextSprite: ID3DXSprite       = nil;  // Sprite for batching draw text calls
  g_pEffect: ID3DXEffect           = nil;  // D3DX effect interface
  g_Camera: CModelViewerCamera;            // A model viewing camera
  g_pDefaultTex: IDirect3DTexture9 = nil;  // Default texture for texture-less material
  g_bShowHelp: Boolean             = True; // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg;          // Device settings dialog
  g_HUD: CDXUTDialog;                      // dialog for standard controls
  g_SampleUI: CDXUTDialog;                 // dialog for sample specific controls
  g_pMeshSysMem: ID3DXMesh         = nil;  // system memory version of mesh, lives through resize's
  g_pMeshEnhanced: ID3DXMesh       = nil;  // vid mem version of mesh that is enhanced
  g_dwNumSegs: LongWord            = 2;    // number of segments per edge (tesselation level)
  g_pMaterials: PD3DXMaterialArray = nil;  // pointer to material info in m_pbufMaterials
  g_ppTextures: PIDirect3DTexture9Array = nil; // array of textures, entries are NULL if no texture specified
  g_dwNumMaterials: DWORD          = 0;    // number of materials
  g_vObjectCenter: TD3DXVector3;           // Center of bounding sphere of object
  g_fObjectRadius: Single;                 // Radius of bounding sphere of object
  g_mCenterWorld: TD3DXMatrixA16;          // World matrix to center the mesh
  g_pbufMaterials: ID3DXBuffer     = nil;  // contains both the materials data and the filename strings
  g_pbufAdjacency: ID3DXBuffer     = nil;  // Contains the adjacency info loaded with the mesh
  g_bUseHWNPatches: Boolean        = True;
  g_bWireframe: Boolean            = False;


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_FILLMODE            = 5;
  IDC_SEGMENTLABEL        = 6;
  IDC_SEGMENT             = 7;
  IDC_HWNPATCHES          = 8;


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
function GenerateEnhancedMesh(pd3dDevice: IDirect3DDevice9; dwNewNumSegs: LongWord): HRESULT;

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;


implementation

uses Math;

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

  g_HUD.SetCallback(OnGUIEvent);
  iY := 10;    g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 35, iY, 125, 22, VK_F2);

  g_SampleUI.SetCallback(OnGUIEvent);
  iY := 10;    g_SampleUI.AddComboBox(IDC_FILLMODE, 10, iY, 150, 24, Ord('F'));
  g_SampleUI.GetComboBox(IDC_FILLMODE).AddItem('(F)illmode: Solid', Pointer(0));
  g_SampleUI.GetComboBox(IDC_FILLMODE).AddItem('(F)illmode: Wireframe', Pointer(1));
  Inc(iY, 30); g_SampleUI.AddStatic(IDC_SEGMENTLABEL, 'Number of segments: 2', 10, iY, 150, 16);
  Inc(iY, 14); g_SampleUI.AddSlider(IDC_SEGMENT, 10, iY, 150, 24, 1, 10, 2);
  Inc(iY, 26); g_SampleUI.AddCheckBox(IDC_HWNPATCHES, 'Use hardware N-patches', 10, iY, 150, 20, True, Ord('H'));
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
  // Turn vsync off
  pDeviceSettings.pp.PresentationInterval := D3DPRESENT_INTERVAL_IMMEDIATE;
  g_SettingsDlg.DialogControl.GetComboBox(DXUTSETTINGSDLG_PRESENT_INTERVAL).Enabled := False;

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
// Generate a mesh that can be tesselated.
function GenerateEnhancedMesh(pd3dDevice: IDirect3DDevice9; dwNewNumSegs: LongWord): HRESULT;
var
  pMeshEnhancedSysMem: ID3DXMesh;
  pMeshTemp: ID3DXMesh;
  dwMeshEnhancedFlags: DWORD;
begin                                                                   
  if (g_pMeshSysMem = nil) then
  begin
    Result:= S_OK;
    Exit;
  end;

  // if using hw, just copy the mesh
  if g_bUseHWNPatches then
  begin
    Result := g_pMeshSysMem.CloneMeshFVF(D3DXMESH_WRITEONLY or D3DXMESH_NPATCHES or
                                         (g_pMeshSysMem.GetOptions and D3DXMESH_32BIT),
                                         g_pMeshSysMem.GetFVF, pd3dDevice, pMeshTemp);
    if FAILED(Result) then Exit;
  end else  // tesselate the mesh in sw
  begin
    // Create an enhanced version of the mesh, will be in sysmem since source is
    Result := D3DXTessellateNPatches(g_pMeshSysMem, g_pbufAdjacency.GetBufferPointer,
                                     dwNewNumSegs, FALSE, pMeshEnhancedSysMem, nil);
    if FAILED(Result) then
    begin
      // If the tessellate failed, there might have been more triangles or vertices
      // than can fit into a 16bit mesh, so try cloning to 32bit before tessellation

      Result := g_pMeshSysMem.CloneMeshFVF(D3DXMESH_SYSTEMMEM or D3DXMESH_32BIT,
                                           g_pMeshSysMem.GetFVF, pd3dDevice, pMeshTemp);
      if FAILED(Result) then Exit;

      Result := D3DXTessellateNPatches(pMeshTemp, g_pbufAdjacency.GetBufferPointer,
                                       dwNewNumSegs, FALSE, pMeshEnhancedSysMem, nil);
      if FAILED(Result) then Exit;
      {begin
        pMeshTemp:= nil .Release;
        Exit;
      end;}

      pMeshTemp:= nil;
    end;

    // Make a vid mem version of the mesh
    // Only set WRITEONLY if it doesn't use 32bit indices, because those
    // often need to be emulated, which means that D3DX needs read-access.
    dwMeshEnhancedFlags := pMeshEnhancedSysMem.GetOptions and D3DXMESH_32BIT;
    if (dwMeshEnhancedFlags and D3DXMESH_32BIT = 0)
    then dwMeshEnhancedFlags := dwMeshEnhancedFlags or D3DXMESH_WRITEONLY;

    Result := pMeshEnhancedSysMem.CloneMeshFVF(dwMeshEnhancedFlags, g_pMeshSysMem.GetFVF,
                                               pd3dDevice, pMeshTemp);
    if FAILED(Result) then Exit;
    {begin
      SAFE_RELEASE( pMeshEnhancedSysMem);
      Result:= hr;
    end;}

    // Latch in the enhanced mesh
    SAFE_RELEASE(pMeshEnhancedSysMem);
  end;

  SAFE_RELEASE(g_pMeshEnhanced);
  g_pMeshEnhanced := pMeshTemp;
  g_dwNumSegs     := dwNewNumSegs;

  Result:= S_OK;
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
  wszMeshDir: array[0..MAX_PATH-1] of WideChar;
  wszWorkingDir: array[0..MAX_PATH-1] of WideChar;
  pVB: IDirect3DVertexBuffer9;
  d3dCaps: TD3DCaps9;
  dwShaderFlags: DWORD;
  str: array[0..MAX_PATH-1] of WideChar;
  pwszLastBSlash: PWideChar;
  pVertices: Pointer;
  i: Integer;
  strTexturePath: array[0..511] of WideChar;
  wszName: PWideChar;
  wszBuf: array[0..MAX_PATH-1] of WideChar;
  pTempMesh: ID3DXMesh; 
  lr: TD3DLockedRect;
  vecEye, vecAt: TD3DXVector3;
begin
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  pd3dDevice.GetDeviceCaps(d3dCaps);
  if (d3dCaps.DevCaps and D3DDEVCAPS_NPATCHES = 0) then
  begin
    // No hardware support. Disable the checkbox.
    g_bUseHWNPatches := False;
    g_SampleUI.GetCheckBox(IDC_HWNPATCHES).Checked := False;
    g_SampleUI.GetCheckBox(IDC_HWNPATCHES).Enabled := False;
  end else
    g_SampleUI.GetCheckBox(IDC_HWNPATCHES).Enabled := True;

  // Initialize the font
  Result:= D3DXCreateFont(pd3dDevice, 15, 0, FW_BOLD, 1, FALSE, DEFAULT_CHARSET,
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
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'EnhancedMesh.fx');
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // they the .fx file failed to compile
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags,
                                     nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  // Load the mesh
  Result:= DXUTFindDXSDKMediaFile(wszMeshDir, MAX_PATH, MESHFILENAME);
  if V_Failed(Result) then Exit;
  Result:= D3DXLoadMeshFromXW(wszMeshDir, D3DXMESH_SYSTEMMEM, pd3dDevice,
                              @g_pbufAdjacency, @g_pbufMaterials, nil, @g_dwNumMaterials,
                              g_pMeshSysMem);
  if V_Failed(Result) then Exit;

  // Initialize the mesh directory string
  pwszLastBSlash := WideStrRScan(wszMeshDir, '\');
  if (pwszLastBSlash <> nil) then pwszLastBSlash^ := #0
  else StringCchCopy(wszMeshDir, MAX_PATH, PWideChar('.'));

  // Lock the vertex buffer, to generate a simple bounding sphere
  Result := g_pMeshSysMem.GetVertexBuffer(pVB);
  if FAILED(Result) then Exit;

  pVertices := nil;
  Result := pVB.Lock(0, 0, pVertices, 0);
  if FAILED(Result) then Exit;
  {begin
    SAFE_RELEASE(pVB);
    Result:= hr;
  end;}

  Result := D3DXComputeBoundingSphere(PD3DXVector3(pVertices), g_pMeshSysMem.GetNumVertices,
                                      D3DXGetFVFVertexSize(g_pMeshSysMem.GetFVF), g_vObjectCenter,
                                      g_fObjectRadius);
  pVB.Unlock;
  SAFE_RELEASE(pVB);

  if FAILED(Result) then Exit;

  if (g_dwNumMaterials = 0) then
  begin
    Result:= E_INVALIDARG;
    Exit;
  end;

  D3DXMatrixTranslation(g_mCenterWorld, -g_vObjectCenter.x, -g_vObjectCenter.y, -g_vObjectCenter.z);

  // Change the current directory to the .x's directory so
  // that the search can find the texture files.
  GetCurrentDirectoryW(MAX_PATH, wszWorkingDir);
  wszWorkingDir[MAX_PATH - 1] := #0;
  SetCurrentDirectoryW(wszMeshDir);

  // Get the array of materials out of the returned buffer, allocate a
  // texture array, and load the textures
  g_pMaterials := PD3DXMaterialArray(g_pbufMaterials.GetBufferPointer);
  GetMem(g_ppTextures, SizeOf(IDirect3DTexture9)*g_dwNumMaterials);
  ZeroMemory(g_ppTextures, SizeOf(IDirect3DTexture9)*g_dwNumMaterials);

  for i := 0 to g_dwNumMaterials - 1 do
  begin
    strTexturePath[0] := #0;
    wszName := @wszBuf;
    MultiByteToWideChar(CP_ACP, 0, g_pMaterials[i].pTextureFilename, -1, wszBuf, MAX_PATH);
    wszBuf[MAX_PATH - 1] := #0;
    DXUTFindDXSDKMediaFile(strTexturePath, 512, wszName);
    if FAILED(D3DXCreateTextureFromFileW(pd3dDevice, strTexturePath, g_ppTextures[i]))
    then g_ppTextures[i] := nil;
  end;
  SetCurrentDirectoryW(wszWorkingDir);

  // Make sure there are normals, which are required for the tesselation
  // enhancement.
  if (g_pMeshSysMem.GetFVF and D3DFVF_NORMAL = 0) then
  begin
    Result:= g_pMeshSysMem.CloneMeshFVF(g_pMeshSysMem.GetOptions,
                                        g_pMeshSysMem.GetFVF or D3DFVF_NORMAL,
                                        pd3dDevice, pTempMesh);
    if V_Failed(Result) then Exit;

    D3DXComputeNormals(pTempMesh, nil);

    SAFE_RELEASE(g_pMeshSysMem);
    g_pMeshSysMem := pTempMesh;
  end;

  // Create the 1x1 white default texture
  Result:= pd3dDevice.CreateTexture(1, 1, 1, 0, D3DFMT_A8R8G8B8,
                                    D3DPOOL_MANAGED, g_pDefaultTex, nil);
  if V_Failed(Result) then Exit;
  Result:= g_pDefaultTex.LockRect(0, lr, nil, 0);
  if V_Failed(Result) then Exit;
  PDWORD(lr.pBits)^ := D3DCOLOR_RGBA(255, 255, 255, 255);
  Result:= g_pDefaultTex.UnlockRect(0);
  if V_Failed(Result) then Exit;

  // Setup the camera's view parameters
  vecEye := D3DXVector3(0.0, 0.0, -5.0);
  vecAt  := D3DXVector3(0.0, 0.0, -0.0);
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
  Result:= D3DXCreateSprite(pd3dDevice, g_pTextSprite);
  if V_Failed(Result) then Exit;

  Result:= GenerateEnhancedMesh(pd3dDevice, g_dwNumSegs);
  if V_Failed(Result) then Exit;

  if g_bWireframe
  then pd3dDevice.SetRenderState(D3DRS_FILLMODE, D3DFILL_WIREFRAME)
  else pd3dDevice.SetRenderState(D3DRS_FILLMODE, D3DFILL_SOLID);

  // Setup the camera's projection parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI/4, fAspectRatio, 0.1, 1000.0);
  g_Camera.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);

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
begin
  // Update the camera's position based on user input
  g_Camera.FrameMove(fElapsedTime);

  pd3dDevice.SetTransform(D3DTS_WORLD, g_Camera.GetWorldMatrix^);
  pd3dDevice.SetTransform(D3DTS_VIEW, g_Camera.GetViewMatrix^);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called at the end of every frame to perform all the 
// rendering calls for the scene, and it will also be called if the window needs to be 
// repainted. After this function has returned, DXUT will call 
// IDirect3DDevice9::Present to display the contents of the next buffer in the swap chain
//--------------------------------------------------------------------------------------
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  mWorld: TD3DXMatrixA16;
  mView: TD3DXMatrixA16;
  mProj: TD3DXMatrixA16;
  mWorldViewProjection: TD3DXMatrixA16;
  m: TD3DXMatrixA16;
  cPasses: Integer;
  p: Integer;
  i: Integer;
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  // Clear the render target and the zbuffer
  V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, D3DCOLOR_ARGB(0, 66, 75, 121), 1.0, 0));

  // Render the scene
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    // Get the projection & view matrix from the camera class
    mWorld := g_Camera.GetWorldMatrix^;
    mProj := g_Camera.GetProjMatrix^;
    mView := g_Camera.GetViewMatrix^;

    // mWorldViewProjection = g_mCenterWorld * mWorld * mView * mProj;
    D3DXMatrixMultiply(m, mView, mProj);
    D3DXMatrixMultiply(m, mWorld, m);
    D3DXMatrixMultiply(mWorldViewProjection, g_mCenterWorld, m);

    // Update the effect's variables.  Instead of using strings, it would
    // be more efficient to cache a handle to the parameter by calling
    // ID3DXEffect::GetParameterByName
    V(g_pEffect.SetMatrix('g_mWorldViewProjection', mWorldViewProjection));
    V(g_pEffect.SetMatrix('g_mWorld', mWorld));
    V(g_pEffect.SetFloat('g_fTime', fTime));

    if g_bUseHWNPatches then
    begin
      pd3dDevice.SetNPatchMode(g_dwNumSegs);
    end;

    V(g_pEffect._Begin( @cPasses, 0 ));
    for p := 0 to cPasses - 1 do
    begin
      V(g_pEffect.BeginPass(p));

      // set and draw each of the materials in the mesh
      for i := 0 to g_dwNumMaterials - 1 do
      begin
        V(g_pEffect.SetVector('g_vDiffuse', PD3DXVector4(@g_pMaterials[i].MatD3D.Diffuse)^));
        if (g_ppTextures[i] <> nil)
        then V(g_pEffect.SetTexture('g_txScene', g_ppTextures[i]))
        else V(g_pEffect.SetTexture('g_txScene', g_pDefaultTex));
        V(g_pEffect.CommitChanges);

        g_pMeshEnhanced.DrawSubset(i);
      end;

      V(g_pEffect.EndPass);
    end;
    V(g_pEffect._End);

    if g_bUseHWNPatches then pd3dDevice.SetNPatchMode(0);

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

  // Output statistics
  txtHelper._Begin;
  txtHelper.SetInsertionPos(5, 5);
  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));
  txtHelper.DrawTextLine(DXUTGetFrameStats(True)); // Show FPS
  txtHelper.DrawTextLine(DXUTGetDeviceStats);

  // Draw help
  if g_bShowHelp then
  begin
    pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*6);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
    txtHelper.DrawTextLine('Controls (F1 to hide):');

    txtHelper.SetInsertionPos(40, pd3dsdBackBuffer.Height-15*5);
    txtHelper.DrawTextLine('Rotate mesh: Left click drag'#10+
                           'Rotate camera: right click drag'#10+
                           'Zoom: Mouse wheel'#10+
                           'Quit: ESC');
  end else
  begin
    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
    txtHelper.DrawTextLine('Press F1 for help');
  end;

  txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
  txtHelper.SetInsertionPos(10, 65);
  txtHelper.DrawFormattedTextLine('NumSegs: %d'#0, [g_dwNumSegs]);
  txtHelper.DrawFormattedTextLine('NumFaces: %d', [IfThen(g_pMeshEnhanced = nil, 0, g_pMeshEnhanced.GetNumFaces)]);
  txtHelper.DrawFormattedTextLine('NumVertices: %d', [IfThen(g_pMeshEnhanced = nil, 0, g_pMeshEnhanced.GetNumVertices)]);

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


//--------------------------------------------------------------------------------------
// Handles the GUI events
//--------------------------------------------------------------------------------------
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
var
  pd3dDevice: IDirect3DDevice9;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;
    IDC_FILLMODE:
    begin
      g_bWireframe := (pControl as CDXUTComboBox).GetSelectedData <> nil;
      pd3dDevice := DXUTGetD3DDevice;
      pd3dDevice.SetRenderState(D3DRS_FILLMODE, IfThen(g_bWireframe, D3DFILL_WIREFRAME, D3DFILL_SOLID));
    end;

    IDC_SEGMENT:
    begin
      g_dwNumSegs := (pControl as CDXUTSlider).Value;
      g_SampleUI.GetStatic(IDC_SEGMENTLABEL).Text:= PWideChar(WideFormat('Number of segments: %u', [g_dwNumSegs]));
      GenerateEnhancedMesh(DXUTGetD3DDevice, g_dwNumSegs);
    end;

    IDC_HWNPATCHES:
    begin
      g_bUseHWNPatches := (pControl as CDXUTCheckBox).Checked;
      GenerateEnhancedMesh(DXUTGetD3DDevice, g_dwNumSegs);
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
  if Assigned(g_pFont) then g_pFont.OnLostDevice;
  if Assigned(g_pEffect) then g_pEffect.OnLostDevice;

  SAFE_RELEASE(g_pTextSprite);
  SAFE_RELEASE(g_pMeshEnhanced);
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

  for i := 0 to g_dwNumMaterials - 1 do SAFE_RELEASE(g_ppTextures[i]);

  SAFE_RELEASE(g_pDefaultTex);
  FreeMem(g_ppTextures);
  SAFE_RELEASE(g_pMeshSysMem);
  SAFE_RELEASE(g_pbufMaterials);
  SAFE_RELEASE(g_pbufAdjacency);
  g_dwNumMaterials := 0;
end;


procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera:= CModelViewerCamera.Create;
  g_HUD := CDXUTDialog.Create;
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

