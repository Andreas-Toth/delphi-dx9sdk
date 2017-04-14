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
 *  $Id: ProgressiveMeshUnit.pas,v 1.17 2007/02/05 22:21:11 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: ProgressiveMesh.cpp
//
// Starting point for new Direct3D applications
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit ProgressiveMeshUnit;

interface

uses
  Windows, SysUtils,
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

  PID3DXPMeshArray = ^TID3DXPMeshArray;
  TID3DXPMeshArray = array [0..0] of ID3DXPMesh;

  PD3DMaterial9Array = ^TD3DMaterial9Array;
  TD3DMaterial9Array = array [0..0] of TD3DMaterial9;

  
//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont: ID3DXFont = nil;            // Font for drawing text
  g_pTextSprite: ID3DXSprite = nil;    // Sprite for batching draw text calls
  g_pEffect: ID3DXEffect = nil;        // D3DX effect interface
  g_Camera: CModelViewerCamera;        // A model viewing camera
  g_bShowHelp: Boolean = True;         // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg;      // Device settings dialog
  g_HUD: CDXUTDialog;                  // dialog for standard controls
  g_SampleUI: CDXUTDialog;             // dialog for sample specific controls
  g_ppPMeshes: PID3DXPMeshArray = nil;
  g_pPMeshFull: ID3DXPMesh = nil;
  g_cPMeshes: DWORD = 0;
  g_iPMeshCur: DWORD;
  g_mtrlMeshMaterials: PD3DMaterial9Array = nil;
  g_ppMeshTextures: PIDirect3DTexture9Array = nil; // Array of textures, entries are nil if no texture specified
  g_dwNumMaterials: DWORD = 0;         // Number of materials
  g_mWorldCenter: TD3DXMatrixA16;
  g_vObjectCenter: TD3DXVector3;       // Center of bounding sphere of object
  g_fObjectRadius: Single;             // Radius of bounding sphere of object
  g_bShowOptimized: Boolean = True;


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_DETAIL              = 5;
  IDC_DETAILLABEL         = 6;
  IDC_USEOPTIMIZED        = 7;


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
procedure SetNumVertices(dwNumVertices: DWORD);

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

  g_SampleUI.EnableKeyboardInput(True);
  g_SampleUI.SetCallback(OnGUIEvent);
  iY := 10;    g_SampleUI.AddStatic(IDC_DETAILLABEL, 'Level of Detail:', 0, iY, 200, 16);
               g_SampleUI.AddCheckBox(IDC_USEOPTIMIZED, 'Use optimized mesh', 50, iY, 200, 20, True);
  Inc(iY, 16); g_SampleUI.AddSlider(IDC_DETAIL, 10, iY, 200, 16, 4, 4, 4);

  g_Camera.SetButtonMasks(MOUSE_LEFT_BUTTON, MOUSE_WHEEL, 0);
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


procedure SetNumVertices(dwNumVertices: DWORD);
begin
  g_pPMeshFull.SetNumVertices(dwNumVertices);

  // If current pm valid for desired value, then set the number of vertices directly
  if ((dwNumVertices >= g_ppPMeshes[g_iPMeshCur].GetMinVertices) and
      (dwNumVertices <= g_ppPMeshes[g_iPMeshCur].GetMaxVertices)) then
  begin
    g_ppPMeshes[g_iPMeshCur].SetNumVertices(dwNumVertices);
  end else  // Search for the right one
  begin
    g_iPMeshCur := g_cPMeshes - 1;

    // Look for the correct "bin"
    while (g_iPMeshCur > 0) do
    begin
      // If number of vertices is less than current max then we found one to fit
      if (dwNumVertices >= g_ppPMeshes[g_iPMeshCur].GetMinVertices)
      then Break;

      Dec(g_iPMeshCur, 1);
    end;

    // Set the vertices on the newly selected mesh
    g_ppPMeshes[g_iPMeshCur].SetNumVertices(dwNumVertices);
  end;
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
  pAdjacencyBuffer: ID3DXBuffer;
  pD3DXMtrlBuffer: ID3DXBuffer;
  d3dxMaterials: PD3DXMaterialArray;
  dw32BitFlag: DWORD;
  pMesh: ID3DXMesh;
  pPMesh: ID3DXPMesh;
  pLastSlash: PWideChar;
  strCWD: array[0..MAX_PATH-1] of WideChar;
  pTempMesh: ID3DXMesh;
  Epsilons: TD3DXWeldEpsilons;
  i: Integer;
  pVertexBuffer: IDirect3DVertexBuffer9;
  pVertices: Pointer;
  m: TD3DXMatrixA16;
  cVerticesMin, cVerticesMax, cVerticesPerMesh: Integer;
  iPMesh: Integer;
  vecEye: TD3DXVector3;
  vecAt: TD3DXVector3;
begin
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  Result:= S_OK;
try try
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
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, WideString('ProgressiveMesh.fx'));
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // they the .fx file failed to compile
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags,
                                     nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  Result:= g_pEffect.SetTechnique('RenderScene');
  if V_Failed(Result) then Exit;

  // Load the mesh
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, WideString(MESHFILENAME));
  if V_Failed(Result) then Exit;
  Result:= D3DXLoadMeshFromXW(str, D3DXMESH_MANAGED, pd3dDevice,
                              @pAdjacencyBuffer, @pD3DXMtrlBuffer, nil,
                              @g_dwNumMaterials, pMesh);
  if V_Failed(Result) then Exit;

  // Change the current directory to the mesh's directory so we can
  // find the textures.
  pLastSlash := WideStrRScan(str, '\');
  if (pLastSlash <> nil) then(pLastSlash + 1)^ := #0;
  GetCurrentDirectoryW(MAX_PATH, strCWD);
  SetCurrentDirectoryW(str);

  dw32BitFlag := (pMesh.GetOptions and D3DXMESH_32BIT);

  // Perform simple cleansing operations on mesh
  Result := D3DXCleanMesh(D3DXCLEAN_SIMPLIFICATION, pMesh, pAdjacencyBuffer.GetBufferPointer, pTempMesh,
                          pAdjacencyBuffer.GetBufferPointer, nil);
  if FAILED(Result) then
  begin
    g_dwNumMaterials := 0;
    Exit;
  end;
  SAFE_RELEASE(pMesh);
  pMesh := pTempMesh;

  // Perform a weld to try and remove excess vertices.
  // Weld the mesh using all epsilons of 0.0f.  A small epsilon like 1e-6 works well too
  ZeroMemory(@Epsilons, SizeOf(TD3DXWeldEpsilons));
  Result := D3DXWeldVertices(pMesh, 0, @Epsilons,
                             pAdjacencyBuffer.GetBufferPointer,
                             pAdjacencyBuffer.GetBufferPointer, nil, nil);
  if FAILED(Result) then
  begin
    g_dwNumMaterials := 0;
    Exit;
  end;

  // Verify validity of mesh for simplification
  Result := D3DXValidMesh(pMesh, pAdjacencyBuffer.GetBufferPointer, nil);
  if FAILED(Result) then
  begin
    g_dwNumMaterials := 0;
    Exit;
  end;

  // Allocate a material/texture arrays
  d3dxMaterials := PD3DXMaterialArray(pD3DXMtrlBuffer.GetBufferPointer);
  GetMem(g_mtrlMeshMaterials, SizeOf(TD3DMaterial9)*g_dwNumMaterials);
  GetMem(g_ppMeshTextures, SizeOf(IDirect3DTexture9)*g_dwNumMaterials);
  ZeroMemory(g_ppMeshTextures, SizeOf(IDirect3DTexture9)*g_dwNumMaterials);

  // Copy the materials and load the textures
  for i := 0 to g_dwNumMaterials - 1 do
  begin
    g_mtrlMeshMaterials[i] := d3dxMaterials[i].MatD3D;
    g_mtrlMeshMaterials[i].Ambient := g_mtrlMeshMaterials[i].Diffuse;

    // Find the path to the texture and create that texture
    MultiByteToWideChar(CP_ACP, 0, d3dxMaterials[i].pTextureFilename, -1, str, MAX_PATH);
    str[MAX_PATH - 1] := #0;
    if FAILED(D3DXCreateTextureFromFileW(pd3dDevice, str, g_ppMeshTextures[i]))
    then g_ppMeshTextures[i] := nil;
  end;
  SAFE_RELEASE(pD3DXMtrlBuffer);

  // Restore the current directory
  SetCurrentDirectoryW(strCWD);

  // Lock the vertex buffer, to generate a simple bounding sphere
  Result := pMesh.GetVertexBuffer(pVertexBuffer);
  if FAILED(Result) then Exit;
  // goto End;

  Result := pVertexBuffer.Lock(0, 0, pVertices, D3DLOCK_NOSYSLOCK);
  if FAILED(Result) then Exit;

  Result := D3DXComputeBoundingSphere(PD3DXVector3(pVertices), pMesh.GetNumVertices,
                                      D3DXGetFVFVertexSize(pMesh.GetFVF),
                                      g_vObjectCenter, g_fObjectRadius);
  pVertexBuffer.Unlock;
  SAFE_RELEASE(pVertexBuffer);

  if FAILED(Result) then Exit;

  begin
    D3DXMatrixTranslation(g_mWorldCenter, -g_vObjectCenter.x,
                                          -g_vObjectCenter.y,
                                          -g_vObjectCenter.z);
    D3DXMatrixScaling(m, 2.0 / g_fObjectRadius,
                         2.0 / g_fObjectRadius,
                         2.0 / g_fObjectRadius);
    D3DXMatrixMultiply(g_mWorldCenter, g_mWorldCenter, m);
  end;

  // If the mesh is missing normals, generate them.
  if (pMesh.GetFVF and D3DFVF_NORMAL = 0) then
  begin
    Result := pMesh.CloneMeshFVF(dw32BitFlag or D3DXMESH_MANAGED, pMesh.GetFVF or D3DFVF_NORMAL,
                                 pd3dDevice, pTempMesh);
    if FAILED(Result) then Exit;

    D3DXComputeNormals( pTempMesh, nil);

    pMesh := nil;
    pMesh := pTempMesh;
  end;

  // Generate progressive meshes

  Result := D3DXGeneratePMesh(pMesh, pAdjacencyBuffer.GetBufferPointer,
                              nil, nil, 1, D3DXMESHSIMP_VERTEX, pPMesh);
  if FAILED(Result) then Exit;

  cVerticesMin := pPMesh.GetMinVertices;
  cVerticesMax := pPMesh.GetMaxVertices;

  cVerticesPerMesh := (cVerticesMax - cVerticesMin + 10) div 10;

  g_cPMeshes := Max(1, DWORD(Ceil((cVerticesMax - cVerticesMin + 1) / cVerticesPerMesh)));
  GetMem(g_ppPMeshes, SizeOf(ID3DXPMesh)*g_cPMeshes);
  ZeroMemory(g_ppPMeshes, SizeOf(ID3DXPMesh)*g_cPMeshes);

  // Clone full size pmesh
  Result := pPMesh.ClonePMeshFVF(D3DXMESH_MANAGED or D3DXMESH_VB_SHARE, pPMesh.GetFVF, pd3dDevice, g_pPMeshFull);
  if FAILED(Result) then Exit;

  // Clone all the separate pmeshes
  for iPMesh := 0 to g_cPMeshes - 1 do
  begin
    Result := pPMesh.ClonePMeshFVF(D3DXMESH_MANAGED or D3DXMESH_VB_SHARE, pPMesh.GetFVF, pd3dDevice, g_ppPMeshes[iPMesh]);
    if FAILED(Result) then Exit;

    // Trim to appropriate space
    Result := g_ppPMeshes[iPMesh].TrimByVertices(cVerticesMin + cVerticesPerMesh * iPMesh, cVerticesMin + cVerticesPerMesh * (iPMesh+1), nil, nil);
    if FAILED(Result) then Exit;

    Result := g_ppPMeshes[iPMesh].OptimizeBaseLOD(D3DXMESHOPT_VERTEXCACHE, nil);
    if FAILED(Result) then Exit;
  end;

  // Set current to be maximum number of vertices
  g_iPMeshCur := g_cPMeshes - 1;
  Result := g_ppPMeshes[g_iPMeshCur].SetNumVertices(cVerticesMax);
  if FAILED(Result) then Exit;

  Result := g_pPMeshFull.SetNumVertices(cVerticesMax);
  if FAILED(Result) then Exit;

  // Set up the slider to reflect the vertices range the mesh has
  g_SampleUI.GetSlider(IDC_DETAIL).SetRange(g_ppPMeshes[0].GetMinVertices, g_ppPMeshes[g_cPMeshes-1].GetMaxVertices);
  g_SampleUI.GetSlider(IDC_DETAIL).Value := g_ppPMeshes[g_iPMeshCur].GetNumVertices;

  // Setup the camera's view parameters
  begin
    vecEye := D3DXVector3(0.0, 0.0, -5.0);
    vecAt  := D3DXVector3(0.0, 0.0, -0.0);
    g_Camera.SetViewParams(vecEye, vecAt);
  end;

except
  on EOutOfMemory do Result := E_OUTOFMEMORY;
end;
finally
  SAFE_RELEASE(pAdjacencyBuffer);
  SAFE_RELEASE(pD3DXMtrlBuffer);
  SAFE_RELEASE(pMesh);
  SAFE_RELEASE(pPMesh);

  if FAILED(Result) then
  begin
    if Assigned(g_ppPMeshes) then
      for iPMesh := 0 to g_cPMeshes - 1 do SAFE_RELEASE(g_ppPMeshes[iPMesh]);

    if Assigned(g_ppPMeshes) then FreeMem(g_ppPMeshes);
    g_ppPMeshes := nil;
    g_cPMeshes := 0;
    SAFE_RELEASE(g_pPMeshFull)
  end;
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

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation(0, pBackBufferSurfaceDesc.Height-50);
  g_SampleUI.SetSize(pBackBufferSurfaceDesc.Width, 50);
  g_SampleUI.GetControl(IDC_DETAILLABEL).SetLocation(( pBackBufferSurfaceDesc.Width - 200 ) div 2, 10);
  g_SampleUI.GetControl(IDC_USEOPTIMIZED).SetLocation(pBackBufferSurfaceDesc.Width - 130, 5);
  g_SampleUI.GetControl(IDC_DETAIL).SetSize(pBackBufferSurfaceDesc.Width - 20, 16);

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
  mWorld: TD3DXMatrixA16;
  mView: TD3DXMatrixA16;
  mProj: TD3DXMatrixA16;
  mWorldViewProjection: TD3DXMatrixA16;
  m: TD3DXMatrixA16;
  i: Integer;
  cPasses: Integer;
  p: Integer; 
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
    D3DXMatrixMultiply(mWorld, g_mWorldCenter, g_Camera.GetWorldMatrix^);
    mProj := g_Camera.GetProjMatrix^;
    mView := g_Camera.GetViewMatrix^;

    // mWorldViewProjection = mWorld * mView * mProj;
    D3DXMatrixMultiply(m, mView, mProj);
    D3DXMatrixMultiply(mWorldViewProjection, mWorld, m);

    if Assigned(g_ppPMeshes) then
    begin
      // Update the effect's variables.  Instead of using strings, it would
      // be more efficient to cache a handle to the parameter by calling 
      // ID3DXEffect::GetParameterByName
      V(g_pEffect.SetMatrix('g_mWorldViewProjection', mWorldViewProjection));
      V(g_pEffect.SetMatrix('g_mWorld', mWorld));
      // Set and draw each of the materials in the mesh
      for i := 0 to g_dwNumMaterials - 1 do
      begin
        V(g_pEffect.SetVector('g_vDiffuse', PD3DXVector4(@g_mtrlMeshMaterials[i])^));
        V(g_pEffect.SetTexture('g_txScene', g_ppMeshTextures[i]));
        V(g_pEffect._Begin(@cPasses, 0));
        for p := 0 to cPasses - 1 do
        begin
          V(g_pEffect.BeginPass(p));
          if g_bShowOptimized
            then V(g_ppPMeshes[g_iPMeshCur].DrawSubset(i))
            else V(g_pPMeshFull.DrawSubset(i));
          V(g_pEffect.EndPass);
        end;
        V(g_pEffect._End);
      end;
    end;

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
  pd3dsdBackBuffer: PD3DSurfaceDesc;
  txtHelper: CDXUTTextHelper;
begin
  // The helper object simply helps keep track of text position, and color
  // and then it calls pFont->DrawText( m_pSprite, strMsg, -1, &rc, DT_NOCLIP, m_clr );
  // If NULL is passed in as the sprite object, then it will work however the
  // pFont->DrawText() will not be batched together.  Batching calls will improves performance.
  pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
  txtHelper := CDXUTTextHelper.Create(g_pFont, g_pTextSprite, 15);

  // Output statistics
  txtHelper._Begin;
  txtHelper.SetInsertionPos(5, 5);
  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0 ));
  txtHelper.DrawTextLine(DXUTGetFrameStats(True)); // Show FPS
  txtHelper.DrawTextLine(DXUTGetDeviceStats);

  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
  if g_bShowOptimized then
    txtHelper.DrawTextLine(PWideChar(WideFormat(
                                  'Using optimized mesh %d of %d'#10+
                                  'Current mesh vertices range: %u / %u'#10+
                                  'Absolute vertices range: %u / %u'#10+
                                  'Current vertices: %d'#10, [
                                  g_iPMeshCur + 1, g_cPMeshes,
                                  g_ppPMeshes[g_iPMeshCur].GetMinVertices,
                                  g_ppPMeshes[g_iPMeshCur].GetMaxVertices,
                                  g_ppPMeshes[0].GetMinVertices,
                                  g_ppPMeshes[g_cPMeshes-1].GetMaxVertices,
                                  g_ppPMeshes[g_iPMeshCur].GetNumVertices])))
  else
    txtHelper.DrawTextLine(PWideChar(WideFormat('Using unoptimized mesh'#10+
                                  'Mesh vertices range: %u / %u'#10+
                                  'Current vertices: %d'#10, [
                                  g_pPMeshFull.GetMinVertices,
                                  g_pPMeshFull.GetMaxVertices,
                                  g_pPMeshFull.GetNumVertices])));

  // Draw help
  if g_bShowHelp then
  begin
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*7);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0 ));
    txtHelper.DrawTextLine('Controls (F1 to hide):');

    txtHelper.SetInsertionPos(40, pd3dsdBackBuffer.Height-15*6);
    txtHelper.DrawTextLine('Rotate mesh: Left click drag'#10+
                           'Zoom: mouse wheel'#10+
                           'Quit: ESC');
  end else
  begin
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*4);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0 ));
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
    IDC_DETAIL:           SetNumVertices((pControl as CDXUTSlider).Value);
    IDC_USEOPTIMIZED:     g_bShowOptimized := (pControl as CDXUTCheckBox).Checked;
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
var
  i: Integer;
begin
  g_DialogResourceManager.OnDestroyDevice;
  g_SettingsDlg.OnDestroyDevice;
  SAFE_RELEASE(g_pEffect);
  SAFE_RELEASE(g_pFont);

  for i := 0 to g_dwNumMaterials - 1 do SAFE_RELEASE(g_ppMeshTextures[i]);
  FreeMem(g_ppMeshTextures);

  SAFE_RELEASE( g_pPMeshFull );
  for i := 0 to g_cPMeshes - 1 do SAFE_RELEASE(g_ppPMeshes[i]);

  g_cPMeshes := 0;
  FreeMem(g_ppPMeshes);

  FreeMem(g_mtrlMeshMaterials);
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

