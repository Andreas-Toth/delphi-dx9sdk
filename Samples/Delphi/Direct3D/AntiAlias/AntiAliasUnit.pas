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
 *  $Id: AntiAliasUnit.pas,v 1.15 2007/02/05 22:21:00 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: AntiAlias.cpp
//
// Multisampling attempts to reduce aliasing by mimicking a higher resolution display;
// multiple sample points are used to determine each pixel's color. This sample shows
// how the various multisampling techniques supported by your video card affect the
// scene's rendering. Although multisampling effectively combats aliasing, under
// particular situations it can introduce visual artifacts of it's own. As illustrated
// by the sample, centroid sampling seeks to eliminate one common type of multisampling
// artifact. Support for centroid sampling is supported under Pixel Shader 2.0 in the
// latest version of the DirectX runtime.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit AntiAliasUnit;

interface

uses
  Windows, SysUtils, Math, StrSafe,
  DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders

//--------------------------------------------------------------------------------------
// Custom vertex
//--------------------------------------------------------------------------------------
type
  PVertex = ^TVertex;
  PVertexPointer = ^TVertex;
  TVertex = record
    Position: TD3DXVector3;
    Diffuse:  TD3DColor;
    TexCoord: TD3DXVector2;
  end;

var
  VertexElements: array [0..3] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0;  _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITION; UsageIndex: 0),
    (Stream: 0; Offset: 12; _Type: D3DDECLTYPE_D3DCOLOR; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_COLOR;   UsageIndex: 0),
    (Stream: 0; Offset: 16; _Type: D3DDECLTYPE_FLOAT2; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TEXCOORD; UsageIndex: 0),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );



//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
const
  GUI_WIDTH = 305;

var
  g_strActiveTechnique: array[0..MAX_PATH] of Char = '';
  g_mRotation:          TD3DXMatrixA16;

  g_pVertexDecl:        IDirect3DVertexDeclaration9;
  g_pVBTriangles:       IDirect3DVertexBuffer9;

  g_pMeshSphereHigh:    ID3DXMesh;
  g_pMeshSphereLow:     ID3DXMesh;

  g_pMeshQuadHigh:      ID3DXMesh;
  g_pMeshQuadLow:       ID3DXMesh;


  g_pFont:              ID3DXFont;     // Font for drawing text
  g_pTextSprite:        ID3DXSprite;   // Sprite for batching draw text calls
  g_pEffect:            ID3DXEffect;   // D3DX effect interface
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg:        CD3DSettingsDlg; // Device settings dialog
  g_HUD:                CDXUTDialog;   // dialog for standard controls

  g_DialogLabels:       CDXUTDialog;   // Labels within the current scene

  g_bCentroid:          Boolean = False;

  g_pTriangleTexture:   IDirect3DTexture9;
  g_pCheckerTexture:    IDirect3DTexture9;

  g_D3DDeviceSettings:  TDXUTDeviceSettings;



//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 2;
  IDC_CHANGEDEVICE        = 3;
  IDC_MULTISAMPLE_TYPE    = 4;
  IDC_MULTISAMPLE_QUALITY = 5;
  IDC_CENTROID            = 6;
  IDC_FILTERGROUP         = 7;
  IDC_FILTER_POINT        = 8;
  IDC_FILTER_LINEAR       = 9;
  IDC_FILTER_ANISOTROPIC  = 10;
  IDC_SCENE               = 11;
  IDC_ROTATIONGROUP       = 12;
  IDC_ROTATION_RPM        = 13;
  IDC_RPM                 = 14;
  IDC_RPM_SUFFIX          = 15;
  IDC_ROTATION_DEGREES    = 16;
  IDC_DEGREES             = 17;
  IDC_DEGREES_SUFFIX      = 18;
  IDC_LABEL0              = 19;
  IDC_LABEL1              = 20;



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

procedure RenderSceneTriangles(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single);
procedure RenderSceneQuads(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single);
procedure RenderSceneSpheres(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single);

procedure InitApp;
function FillVertexBuffer: HRESULT;
function LoadMesh(pd3dDevice: IDirect3DDevice9; strFileName: PWideChar; out ppMesh: ID3DXMesh): HRESULT;
procedure RenderText;

function InitializeUI: HRESULT;
function OnMultisampleTypeChanged: HRESULT;
function OnMultisampleQualityChanged: HRESULT;
procedure AddMultisampleType(_type: TD3DMultiSampleType);
function GetSelectedMultisampleType: TD3DMultiSampleType;
procedure AddMultisampleQuality(dwQuality: DWORD);
function GetSelectedMultisampleQuality: DWORD;
//function DXUTMultisampleTypeToString(MultiSampleType: TD3DMultiSampleType): PWideChar;
function GetCurrentDeviceSettingsCombo: PD3DEnumDeviceSettingsCombo;

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;


implementation


//--------------------------------------------------------------------------------------
// Initialize the app
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  pElement: CDXUTElement;
  iX, iY: Integer;
begin
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_DialogLabels.Init(g_DialogResourceManager);

  // Title font for comboboxes
  g_HUD.SetFont(1, 'Arial', 14, FW_BOLD);
  pElement := g_HUD.GetDefaultElement(DXUT_CONTROL_STATIC, 0);
  if Assigned(pElement) then
  begin
    pElement.iFont := 1;
    pElement.dwTextFormat := DT_LEFT or DT_BOTTOM;

    // Scene label font
    g_DialogLabels.SetFont( 1, 'Arial', 16, FW_BOLD);
  end;
  pElement := g_DialogLabels.GetDefaultElement(DXUT_CONTROL_STATIC, 0);
  if (pElement <> nil) then
  begin
    pElement.iFont := 1;
    pElement.FontColor.Init(D3DCOLOR_RGBA(200, 200, 200, 255));
    pElement.dwTextFormat := DT_LEFT or DT_BOTTOM;
  end;

  // Initialize dialogs
  iX := 25; iY := 10;
  
  g_HUD.SetCallback(OnGUIEvent);
  g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', iX + 135, iY, 125, 22);  Inc(iY, 24);
  g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', iX + 135, iY, 125, 22); Inc(iY, 24);
  g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', iX + 135, iY, 125, 22, VK_F2);

  Inc(iY, 10); Inc(iY, 24);
  g_HUD.AddStatic(-1, 'Scene', iX, iY, 260, 22); Inc(iY, 24);
  g_HUD.AddComboBox(IDC_SCENE, iX, iY, 260, 22);
  g_HUD.GetComboBox(IDC_SCENE).AddItem('Triangles', nil);
  g_HUD.GetComboBox(IDC_SCENE).AddItem('Quads', nil);
  g_HUD.GetComboBox(IDC_SCENE).AddItem('Spheres', nil);

  Inc(iY, 10); Inc(iY, 24);
  g_HUD.AddStatic(-1, 'Multisample Type', iX, iY, 260, 22); Inc(iY, 24);
  g_HUD.AddComboBox(IDC_MULTISAMPLE_TYPE, iX, iY, 260, 22); Inc(iY, 24);
  g_HUD.AddStatic(-1, 'Multisample Quality', iX, iY, 260, 22); Inc(iY, 24);
  g_HUD.AddComboBox(IDC_MULTISAMPLE_QUALITY, iX, iY, 260, 22);

  Inc(iY, 10); Inc(iY, 24);
  g_HUD.AddStatic(-1, 'Texture Filtering', iX, iY, 260, 22);

  Inc(iY, 10);
  g_HUD.AddCheckBox(IDC_CENTROID, 'Centroid sampling', iX+150, iY+20, 260, 18, False);

  Inc(iY, 20);
  g_HUD.AddRadioButton(IDC_FILTER_POINT, IDC_FILTERGROUP, 'Point', iX+10, iY, 130, 18); Inc(iY, 20);
  g_HUD.AddRadioButton(IDC_FILTER_LINEAR, IDC_FILTERGROUP, 'Linear', iX+10, iY, 130, 18, True); Inc(iY, 20);
  g_HUD.AddRadioButton(IDC_FILTER_ANISOTROPIC, IDC_FILTERGROUP, 'Anisotropic', iX+10, iY, 130, 18);

  Inc(iY, 10); Inc(iY, 24);
  g_HUD.AddStatic(-1, 'Mesh Rotation', iX, iY, 260, 22);

  g_HUD.AddEditBox(IDC_RPM, '4.0', iX+86, iY + 32, 50, 30 );
  g_HUD.AddRadioButton(IDC_ROTATION_RPM, IDC_ROTATIONGROUP, 'Rotating at', iX+10, iY + 38, 76, 18, True);
  Inc(iY, 38);
  g_HUD.AddStatic(IDC_RPM_SUFFIX, 'rpm', iX+141, iY, 100, 18);
  pElement := g_HUD.GetStatic(IDC_RPM_SUFFIX).Element[0];
  if Assigned(pElement) then pElement.iFont := 0;
  g_HUD.AddEditBox(IDC_DEGREES, '90.0', iX+74, iY + 36, 50, 30 );
  g_HUD.AddRadioButton(IDC_ROTATION_DEGREES, IDC_ROTATIONGROUP, 'Fixed at', iX+10, iY + 42, 64, 18);
  Inc(iY, 42);
  g_HUD.AddStatic(IDC_DEGREES_SUFFIX, 'degrees', iX+129, iY, 100, 18);
  pElement := g_HUD.GetStatic(IDC_DEGREES_SUFFIX).Element[0];
  if Assigned(pElement) then pElement.iFont := 0;

  // Add labels
  g_DialogLabels.AddStatic(IDC_LABEL0, nil, 0, 0, 200, 25);
  g_DialogLabels.AddStatic(IDC_LABEL1, nil, 0, 0, 200, 25);
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
  // doesn't support at least ps1.1
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(1,1)) then Exit; 

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
  dwShaderFlags: DWORD;
begin
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  // Create the vertex declaration
  Result:= pd3dDevice.CreateVertexDeclaration(@VertexElements, g_pVertexDecl);
  if V_Failed(Result) then Exit;

  // Create the vertex buffer for the triangles / quads
  Result:= pd3dDevice.CreateVertexBuffer(3 * SizeOf(TVertex), D3DUSAGE_WRITEONLY,
                                         0, D3DPOOL_MANAGED, g_pVBTriangles, nil);
  if V_Failed(Result) then Exit;

  // Initialize the font
  Result:= D3DXCreateFont(pd3dDevice, 15, 0, FW_BOLD, 1, FALSE, DEFAULT_CHARSET,
                          OUT_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE,
                          'Arial', g_pFont);
  if V_Failed(Result) then Exit;

  // Create the spheres
  Result:= DXUTFindDXSDKMediaFile(strPath, MAX_PATH, 'spherehigh.x');
  if V_Failed(Result) then Exit;
  Result:= LoadMesh(pd3dDevice, strPath, g_pMeshSphereHigh);
  if V_Failed(Result) then Exit;

  Result:= DXUTFindDXSDKMediaFile(strPath, MAX_PATH, 'spherelow.x');
  if V_Failed(Result) then Exit;
  Result:= LoadMesh(pd3dDevice, strPath, g_pMeshSphereLow);
  if V_Failed(Result) then Exit;

  Result:= DXUTFindDXSDKMediaFile(strPath, MAX_PATH, 'quadhigh.x');
  if V_Failed(Result) then Exit;
  Result:= LoadMesh(pd3dDevice, strPath, g_pMeshQuadHigh);
  if V_Failed(Result) then Exit;

  Result:= DXUTFindDXSDKMediaFile(strPath, MAX_PATH, 'quadlow.x');
  if V_Failed(Result) then Exit;
  Result:= LoadMesh(pd3dDevice, strPath, g_pMeshQuadLow);
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
  Result:= DXUTFindDXSDKMediaFile(strPath, MAX_PATH, 'AntiAlias.fx');
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // they the .fx file failed to compile
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, @strPath, nil, nil, dwShaderFlags,
                                     nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;


  // Load the textures
  Result:= DXUTFindDXSDKMediaFile(strPath, MAX_PATH, 'checker.tga');
  if V_Failed(Result) then Exit;
  Result:= D3DXCreateTextureFromFileW(pd3dDevice, @strPath, g_pCheckerTexture);
  if V_Failed(Result) then Exit;

  Result:= DXUTFindDXSDKMediaFile(strPath, MAX_PATH, 'triangle.tga');
  if V_Failed(Result) then Exit;
  Result:= D3DXCreateTextureFromFileW(pd3dDevice, @strPath, g_pTriangleTexture);
  if V_Failed(Result) then Exit;

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// This function loads the mesh and ensures the mesh has normals; it also optimizes the 
// mesh for the graphics card's vertex cache, which improves performance by organizing 
// the internal triangle list for less cache misses.
//--------------------------------------------------------------------------------------
//-----------------------------------------------------------------------------
// Name: LoadMesh()
// Desc:
//-----------------------------------------------------------------------------
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
  try
    // if (rgdwAdjacency = nil) then Result:= E_OUTOFMEMORY;
    V(pMesh.GenerateAdjacency(1e-6,rgdwAdjacency));
    V(pMesh.OptimizeInplace(D3DXMESHOPT_VERTEXCACHE, rgdwAdjacency, nil, nil, nil));
  finally
    FreeMem(rgdwAdjacency);
  end;

  ppMesh := pMesh;

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// Set the vertices for the triangles scene
//--------------------------------------------------------------------------------------
function FillVertexBuffer: HRESULT;
var
  pVertex: PVertexPointer;
  fTexel: Single;
  nBorder: Integer;
begin
  pVertex := nil;
  Result:= g_pVBTriangles.Lock(0, 0, Pointer(pVertex), 0);
  if V_Failed(Result) then Exit;

  fTexel := 1.0 / 128;
  nBorder := 5;

  pVertex.Position := D3DXVector3(1, 1, 0);
  pVertex.Diffuse := D3DCOLOR_ARGB(255, 0, 0, 0);
  pVertex.TexCoord := D3DXVector2((128 - nBorder) * fTexel, (128 - nBorder) * fTexel);
  Inc(pVertex);

  pVertex.Position := D3DXVector3(0, 1, 0);
  pVertex.Diffuse := D3DCOLOR_ARGB(255, 0, 0, 0);
  pVertex.TexCoord := D3DXVector2(nBorder * fTexel, (128 - nBorder) * fTexel);
  Inc(pVertex);

  pVertex.Position := D3DXVector3(0, 0, 0);
  pVertex.Diffuse := D3DCOLOR_ARGB(255, 0, 0, 0);
  pVertex.TexCoord := D3DXVector2(nBorder * fTexel, nBorder * fTexel);
  Inc(pVertex);

  g_pVBTriangles.Unlock;

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// Moves the world-space XY plane into screen-space for pixel-perfect perspective
//--------------------------------------------------------------------------------------
function CalculateViewAndProjection(out pViewOut, pProjectionOut: TD3DXMatrix;
  fovy, zNearOffset, zFarOffset: Single): HRESULT;
var
  pBackBufferSurfaceDesc: PD3DSurfaceDesc;
  Width, Height: Single;
  fAspectRatio: Single;
  yScale: Single;
  z: Single;
begin
  // Get back buffer description and determine aspect ratio
  pBackBufferSurfaceDesc := DXUTGetBackBufferSurfaceDesc;
  Width := pBackBufferSurfaceDesc.Width;
  Height := pBackBufferSurfaceDesc.Height;
  fAspectRatio := Width / Height;

  // Determine the correct Z depth to completely fill the frustum
  yScale := 1 / tan(fovy/2);
  z := yScale * Height / 2;

  // Calculate perspective projection
  D3DXMatrixPerspectiveFovLH(pProjectionOut, fovy, fAspectRatio, z + zNearOffset, z + zFarOffset);

  // Initialize the view matrix as a rotation and translation from "screen-coordinates"
  // in world space (the XY plane from the perspective of Z+) to a plane that's centered
  // along Z+
  D3DXMatrixIdentity(pViewOut);
  pViewOut._22 := -1;
  pViewOut._33 := -1;
  pViewOut._41 := -(Width/2);
  pViewOut._42 := (Height/2);
  pViewOut._43 := z;

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
  backColor: TD3DColor;
  bottomColor: TD3DColor;
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

  Result:= FillVertexBuffer;
  if V_Failed(Result) then Exit;

  // Create a sprite to help batch calls when drawing many lines of text
  Result:= D3DXCreateSprite(pd3dDevice, g_pTextSprite);
  if V_Failed(Result) then Exit;

  backColor := D3DCOLOR_ARGB(255, 150, 150, 150);
  bottomColor := D3DCOLOR_ARGB(255, 100, 100, 100);

  g_HUD.SetBackgroundColors(bottomColor, bottomColor, backColor, backColor);
  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width - GUI_WIDTH, 0);
  g_HUD.SetSize(GUI_WIDTH, pBackBufferSurfaceDesc.Height);

  InitializeUI;

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
function InitializeUI: HRESULT;
var
  pDeviceSettingsCombo: PD3DEnumDeviceSettingsCombo;
  pMultisampleTypeCombo: CDXUTComboBox;
  ims: Integer;
  msType: TD3DMultiSampleType;
  bConflictFound: Boolean;
  iConf: Integer;
  DSMSConf: TD3DEnumDSMSConflict;
  pMultisampleQualityCombo: CDXUTComboBox;
begin
  g_D3DDeviceSettings := DXUTGetDeviceSettings;

  pDeviceSettingsCombo := GetCurrentDeviceSettingsCombo;
  if (pDeviceSettingsCombo = nil) then
  begin
    Result:= E_FAIL;
    Exit;
  end;

  pMultisampleTypeCombo := g_HUD.GetComboBox(IDC_MULTISAMPLE_TYPE);
  pMultisampleTypeCombo.RemoveAllItems;

  for ims:= 0 to Length(pDeviceSettingsCombo.multiSampleTypeList) - 1 do
  begin
    msType := pDeviceSettingsCombo.multiSampleTypeList[ims];

    bConflictFound := False;
    for iConf := 0 to Length(pDeviceSettingsCombo.DSMSConflictList) - 1 do
    begin
      DSMSConf := pDeviceSettingsCombo.DSMSConflictList[iConf];
      if (DSMSConf.DSFormat = g_D3DDeviceSettings.pp.AutoDepthStencilFormat) and
         (DSMSConf.MSType = msType) then
      begin
        bConflictFound := True;
        Break;
      end;
    end;

    if not bConflictFound then AddMultisampleType(msType);
  end;

  pMultisampleQualityCombo := g_HUD.GetComboBox(IDC_MULTISAMPLE_TYPE);
  pMultisampleQualityCombo.SetSelectedByData(ULongToPtr(g_D3DDeviceSettings.pp.MultiSampleType));

  Result := OnMultisampleTypeChanged;
  if FAILED(Result) then Exit;

  Result:= S_OK;
end;


//-------------------------------------------------------------------------------------
function GetCurrentDeviceSettingsCombo: PD3DEnumDeviceSettingsCombo;
var
    pD3DEnum: CD3DEnumeration;
begin
  pD3DEnum := DXUTGetEnumeration;
  Result:= pD3DEnum.GetDeviceSettingsCombo(g_D3DDeviceSettings.AdapterOrdinal,
                                           g_D3DDeviceSettings.DeviceType,
                                           g_D3DDeviceSettings.AdapterFormat,
                                           g_D3DDeviceSettings.pp.BackBufferFormat,
                                           g_D3DDeviceSettings.pp.Windowed);
end;


//-------------------------------------------------------------------------------------
function OnMultisampleTypeChanged: HRESULT;
var
  multisampleType: TD3DMultiSampleType;
  pDeviceSettingsCombo: PD3DEnumDeviceSettingsCombo;
  dwMaxQuality: DWORD;
  iType: Integer;
  msType: TD3DMultiSampleType;
  pMultisampleQualityCombo: CDXUTComboBox;
  iQuality: LongWord;
begin
  multisampleType := GetSelectedMultisampleType;
  g_D3DDeviceSettings.pp.MultiSampleType := multisampleType;

  // If multisampling is enabled, then centroid is a meaningful option.
  g_HUD.GetCheckBox(IDC_CENTROID).Enabled := (multisampleType <> D3DMULTISAMPLE_NONE);
  g_HUD.GetCheckBox(IDC_CENTROID).Checked := (multisampleType <> D3DMULTISAMPLE_NONE) and g_bCentroid;

  pDeviceSettingsCombo := GetCurrentDeviceSettingsCombo;
  if (pDeviceSettingsCombo = nil) then
  begin
    Result:= E_FAIL;
    Exit;
  end;

  dwMaxQuality := 0;
  for iType := 0 to Length(pDeviceSettingsCombo.multiSampleTypeList)-1 do
  begin
    msType := pDeviceSettingsCombo.multiSampleTypeList[iType];
    if (msType = multisampleType) then
    begin
      dwMaxQuality := pDeviceSettingsCombo.multiSampleQualityList[iType];
      Break;
    end;
  end;

  // DXUTSETTINGSDLG_MULTISAMPLE_QUALITY
  pMultisampleQualityCombo := g_HUD.GetComboBox(IDC_MULTISAMPLE_QUALITY);
  pMultisampleQualityCombo.RemoveAllItems;

  for iQuality := 0 to dwMaxQuality-1 do AddMultisampleQuality(iQuality);

  pMultisampleQualityCombo.SetSelectedByData(ULongToPtr(g_D3DDeviceSettings.pp.MultiSampleQuality));

  Result := OnMultisampleQualityChanged;
  if FAILED(Result) then Exit;

  Result:= S_OK;
end;


//-------------------------------------------------------------------------------------
function OnMultisampleQualityChanged: HRESULT;
var
  curDeviceSettings: TDXUTDeviceSettings;
begin
  g_D3DDeviceSettings.pp.MultiSampleQuality := GetSelectedMultisampleQuality;

  // Change the device if current settings don't match the UI settings
  curDeviceSettings := DXUTGetDeviceSettings;
  if (curDeviceSettings.pp.MultiSampleQuality <> g_D3DDeviceSettings.pp.MultiSampleQuality) or
     (curDeviceSettings.pp.MultiSampleType <> g_D3DDeviceSettings.pp.MultiSampleType) then
  begin
    if (g_D3DDeviceSettings.pp.MultiSampleType <> D3DMULTISAMPLE_NONE) then
      with g_D3DDeviceSettings.pp do Flags := Flags and not D3DPRESENTFLAG_LOCKABLE_BACKBUFFER;

    DXUTCreateDeviceFromSettings(@g_D3DDeviceSettings);
  end;

  Result:= S_OK;
end;

//-------------------------------------------------------------------------------------
procedure AddMultisampleType(_type: TD3DMultiSampleType);
var
  pComboBox: CDXUTComboBox;
begin
  pComboBox := g_HUD.GetComboBox(IDC_MULTISAMPLE_TYPE);

  if not pComboBox.ContainsItem(DXUTMultisampleTypeToString(_type))
  then pComboBox.AddItem(DXUTMultisampleTypeToString(_type), ULongToPtr(_type));
end;


//-------------------------------------------------------------------------------------
function GetSelectedMultisampleType: TD3DMultiSampleType;
var
  pComboBox: CDXUTComboBox;
begin
  pComboBox := g_HUD.GetComboBox(IDC_MULTISAMPLE_TYPE);

  Result:= TD3DMultiSampleType(PtrToUlong(pComboBox.GetSelectedData));
end;


//-------------------------------------------------------------------------------------
procedure AddMultisampleQuality(dwQuality: DWORD);
var
  pComboBox: CDXUTComboBox;
  strQuality: array[0..49] of WideChar;
begin
  pComboBox := g_HUD.GetComboBox(IDC_MULTISAMPLE_QUALITY);

  StringCchFormat(strQuality, 50, '%d', [dwQuality]);
  strQuality[49] := #0;

  if not pComboBox.ContainsItem(strQuality)
  then pComboBox.AddItem(strQuality, ULongToPtr(dwQuality));
end;


//-------------------------------------------------------------------------------------
function GetSelectedMultisampleQuality: DWORD;
var
  pComboBox: CDXUTComboBox;
begin
  pComboBox := g_HUD.GetComboBox(IDC_MULTISAMPLE_QUALITY);

  Result:= PtrToUlong(pComboBox.GetSelectedData);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called once at the beginning of every frame. This is the
// best location for your application to handle updates to the scene, but is not 
// intended to contain actual rendering calls, which should instead be placed in the 
// OnFrameRender callback.  
//--------------------------------------------------------------------------------------
procedure OnFrameMove(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
begin
end;


{$IFDEF DELPHI}{$IFNDEF COMPILER6_UP}
function StrToFloatDef(const S: string; const Default: Extended): Extended;
begin
  if not TextToFloat(PChar(S), Result, fvExtended) then
    Result := Default;
end;
{$ENDIF}{$ENDIF}

//--------------------------------------------------------------------------------------
// This callback function will be called at the end of every frame to perform all the
// rendering calls for the scene, and it will also be called if the window needs to be
// repainted. After this function has returned, DXUT will call 
// IDirect3DDevice9::Present to display the contents of the next buffer in the swap chain
//--------------------------------------------------------------------------------------
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  fRotate: Single;
  pSelectedItem: PDXUTComboBoxItem;
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  // Determine the active technique from the UI settings
  g_strActiveTechnique := 'Texture';

  if g_HUD.GetRadioButton(IDC_FILTER_POINT).Checked then StrCat(g_strActiveTechnique, 'Point')
  else if g_HUD.GetRadioButton(IDC_FILTER_LINEAR).Checked then StrCat(g_strActiveTechnique, 'Linear')
  else if g_HUD.GetRadioButton(IDC_FILTER_ANISOTROPIC).Checked then StrCat(g_strActiveTechnique, 'Anisotropic')
  else Exit; //error

  if g_HUD.GetCheckBox(IDC_CENTROID).Checked then StringCchCat(g_strActiveTechnique, MAX_PATH, 'Centroid');

  // Get the current rotation matrix
  if g_HUD.GetRadioButton(IDC_ROTATION_RPM).Checked then
  begin
    fRotate := StrToFloatDef(g_HUD.GetEditBox(IDC_RPM).Text, 0);
    D3DXMatrixRotationY(g_mRotation, (fTime * 2.0 * D3DX_PI * fRotate)/60.0);
  end
  else if g_HUD.GetRadioButton(IDC_ROTATION_DEGREES).Checked then
  begin
    fRotate := StrToFloatDef(g_HUD.GetEditBox(IDC_DEGREES).Text, 0);
    D3DXMatrixRotationY(g_mRotation, fRotate * (D3DX_PI/180.0));
  end;

  // Clear the render target and the zbuffer 
  V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, D3DCOLOR_ARGB(0, 255, 255, 255), 1.0, 0));
    

  // Render the scene
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    V(pd3dDevice.SetStreamSource(0, g_pVBTriangles, 0, SizeOf(TVertex)));
    V(pd3dDevice.SetVertexDeclaration(g_pVertexDecl));

    pSelectedItem := g_HUD.GetComboBox(IDC_SCENE).GetSelectedItem;

    if (0 = lstrcmpW('Triangles', pSelectedItem.strText))
    then RenderSceneTriangles(pd3dDevice, fTime, fElapsedTime)
    else if (0 = lstrcmpW('Quads', pSelectedItem.strText))
    then RenderSceneQuads(pd3dDevice, fTime, fElapsedTime)
    else if (0 = lstrcmpW('Spheres', pSelectedItem.strText))
    then RenderSceneSpheres(pd3dDevice, fTime, fElapsedTime);

    DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'HUD / Stats'); // These events are to help PIX identify what the code is doing
    RenderText;
    V(g_HUD.OnRender(fElapsedTime));
    V(g_DialogLabels.OnRender(fElapsedTime));
    DXUT_EndPerfEvent;

    V(pd3dDevice.EndScene);
  end;
end;


//-------------------------------------------------------------------------------------
procedure RenderSceneTriangles(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single);
var
  mWorld: TD3DXMatrixA16;
  mView: TD3DXMatrixA16;
  mProjection: TD3DXMatrixA16;
  mWorldViewProjection: TD3DXMatrixA16;
  mRotation: TD3DXMatrixA16;
  mScaling: TD3DXMatrixA16;
  mTranslation: TD3DXMatrixA16;
  iTriangle: Integer;
  m: TD3DXMatrixA16;
  NumPasses: LongWord;
  iPass: Integer;
const
  Width = 40;
  Height = 100;
begin
  CalculateViewAndProjection(mView, mProjection, D3DX_PI/4, -100, 100);

  // Place labels within the scene
  g_DialogLabels.GetStatic(IDC_LABEL0).SetLocation(25, 75);
  g_DialogLabels.GetStatic(IDC_LABEL0).Text := 'Solid Color Fill';

  g_DialogLabels.GetStatic(IDC_LABEL1).SetLocation(175, 75);
  g_DialogLabels.GetStatic(IDC_LABEL1).Text := 'Texturing Artifacts';

  for iTriangle := 0 to 3 do 
  begin
    case iTriangle of
      0:
      begin
        D3DXMatrixIdentity(mRotation);
        D3DXMatrixTranslation(mTranslation, 75.0 + 0.1, 125.0 -0.5, 0);
        V(g_pEffect.SetTechnique('Color'));
      end;

      1:
      begin
        mRotation := g_mRotation;
        D3DXMatrixTranslation(mTranslation, 75.0 + 0.1, 275.0 -0.5, 0);
        V(g_pEffect.SetTechnique('Color'));
      end;

      2:
      begin
        D3DXMatrixIdentity(mRotation);
        D3DXMatrixTranslation(mTranslation, 225.0 + 0.1, 125.0 -0.5, 0);
        V(g_pEffect.SetTechnique(g_strActiveTechnique));
      end;

      3:
      begin
        mRotation := g_mRotation;
        D3DXMatrixTranslation(mTranslation, 225.0 + 0.1, 275.0 -0.5, 0);
        V(g_pEffect.SetTechnique(g_strActiveTechnique));
      end;
    end;

//    const float Width = 40;
//    const float Height = 100;
    
    D3DXMatrixScaling(mScaling, Width, Height, 1);
    // mWorld = mScaling * mRotation * mTranslation;
    D3DXMatrixMultiply(m, mRotation, mTranslation);
    D3DXMatrixMultiply(mWorld, mScaling, m);
    // mWorldViewProjection = mWorld * mView * mProjection;
    D3DXMatrixMultiply(m, mView, mProjection);
    D3DXMatrixMultiply(mWorldViewProjection, mWorld, m);

    V(g_pEffect.SetMatrix('g_mWorldViewProjection', mWorldViewProjection));
    V(g_pEffect.SetTexture('g_tDiffuse', g_pTriangleTexture));
        

    V(g_pEffect._Begin(@NumPasses, 0));

    for iPass := 0 to NumPasses - 1 do
    begin
      V(g_pEffect.BeginPass(iPass));

      V(pd3dDevice.DrawPrimitive(D3DPT_TRIANGLEFAN, 0, 1));

      V(g_pEffect.EndPass);
    end;

    V(g_pEffect._End);
  end;
end;


//-------------------------------------------------------------------------------------
procedure RenderSceneQuads(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single);
var
  mWorld: TD3DXMatrixA16;
  mView: TD3DXMatrixA16;
  mProjection: TD3DXMatrixA16;
  mWorldViewProjection: TD3DXMatrixA16;
  mScaling: TD3DXMatrixA16;
  mTranslation: TD3DXMatrixA16;
  pDesc: PD3DSurfaceDesc;
  totalWidth: Single;
  radius: Single;
  iQuad: Integer;
  pMesh: ID3DXMesh;
  m: TD3DXMatrixA16;
  NumPasses: LongWord;
  iPass: Integer;  
begin
  pDesc := DXUTGetBackBufferSurfaceDesc;
  totalWidth := pDesc.Width - GUI_WIDTH;
  radius := 0.2 * totalWidth;

  // Place labels within the scene
  g_DialogLabels.GetStatic(IDC_LABEL0).SetLocation(Trunc(0.25 * totalWidth - 50), Trunc(pDesc.Height / 2.0 - radius - 50));
  g_DialogLabels.GetStatic(IDC_LABEL0).Text := '2 Triangles';

  g_DialogLabels.GetStatic(IDC_LABEL1).SetLocation(Trunc(0.75 * totalWidth - 50), Trunc(pDesc.Height / 2.0 - radius - 50));
  g_DialogLabels.GetStatic(IDC_LABEL1).Text := '8192 Triangles';

  CalculateViewAndProjection(mView, mProjection, D3DX_PI/4, -300, 300);

  V(g_pEffect.SetTechnique(g_strActiveTechnique));
  V(g_pEffect.SetTexture('g_tDiffuse', g_pCheckerTexture));

  for iQuad := 0 to 1 do
  begin
    case iQuad of
      0:
      begin
        D3DXMatrixTranslation(mTranslation, 0.25 * totalWidth, pDesc.Height / 2.0, 0);
        pMesh := g_pMeshQuadLow;
      end;

      1:
      begin
        D3DXMatrixTranslation(mTranslation, 0.75 * totalWidth, pDesc.Height / 2.0, 0);
        pMesh := g_pMeshQuadHigh;
      end;
    end;

    D3DXMatrixScaling(mScaling, 2*radius, 2*radius, 2*radius);

    // mWorld = mScaling * g_mRotation * mTranslation;
    D3DXMatrixMultiply(m, g_mRotation, mTranslation);
    D3DXMatrixMultiply(mWorld, mScaling, m);
    // mWorldViewProjection = mWorld * mView * mProjection;
    D3DXMatrixMultiply(m, mView, mProjection);
    D3DXMatrixMultiply(mWorldViewProjection, mWorld, m);

    V(g_pEffect.SetMatrix('g_mWorldViewProjection', mWorldViewProjection));

    V(g_pEffect._Begin(@NumPasses, 0));

    for iPass := 0 to NumPasses - 1 do
    begin
      V(g_pEffect.BeginPass(iPass ));

      V(pMesh.DrawSubset(0));

      V(g_pEffect.EndPass);
    end;

    V(g_pEffect._End);
  end;
end;


//-------------------------------------------------------------------------------------
procedure RenderSceneSpheres(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single);
var
  mWorld: TD3DXMatrixA16;
  mView: TD3DXMatrixA16;
  mProjection: TD3DXMatrixA16;
  mWorldViewProjection: TD3DXMatrixA16;
  mScaling: TD3DXMatrixA16;
  mTranslation: TD3DXMatrixA16;
  pDesc: PD3DSurfaceDesc;
  totalWidth: Single;
  radius: Single;
  iSphere: Integer;
  pMesh: ID3DXMesh;
  m: TD3DXMatrixA16;
  NumPasses: LongWord;
  iPass: Integer;
begin
  pDesc := DXUTGetBackBufferSurfaceDesc;
  totalWidth := pDesc.Width - GUI_WIDTH;
  radius := 0.2 * totalWidth;

  // Place labels within the scene
  g_DialogLabels.GetStatic(IDC_LABEL0).SetLocation(Trunc(0.25 * totalWidth - 50), Trunc(pDesc.Height / 2.0 - radius - 50));
  g_DialogLabels.GetStatic(IDC_LABEL0).Text := '180 Triangles';

  g_DialogLabels.GetStatic(IDC_LABEL1).SetLocation(Trunc(0.75 * totalWidth - 50), Trunc(pDesc.Height / 2.0 - radius - 50));
  g_DialogLabels.GetStatic(IDC_LABEL1).Text := '8064 Triangles';

  CalculateViewAndProjection(mView, mProjection, D3DX_PI/4, -300, 300);

  V(g_pEffect.SetTechnique(g_strActiveTechnique));
  V(g_pEffect.SetTexture('g_tDiffuse', g_pCheckerTexture));

  for iSphere := 0 to 1 do
  begin
    case iSphere of
      0:
      begin
        D3DXMatrixTranslation(mTranslation, 0.25 * totalWidth, pDesc.Height / 2.0, 0);
        pMesh := g_pMeshSphereLow;
      end;

      1:
      begin
        D3DXMatrixTranslation(mTranslation, 0.75 * totalWidth, pDesc.Height / 2.0, 0);
        pMesh := g_pMeshSphereHigh;
      end;
    end;

    D3DXMatrixScaling(mScaling, radius, radius, radius);
    // mWorld = mScaling * g_mRotation * mTranslation;
    D3DXMatrixMultiply(m, g_mRotation, mTranslation);
    D3DXMatrixMultiply(mWorld, mScaling, m);
    // mWorldViewProjection = mWorld * mView * mProjection;
    D3DXMatrixMultiply(m, mView, mProjection);
    D3DXMatrixMultiply(mWorldViewProjection, mWorld, m);

    V(g_pEffect.SetMatrix('g_mWorldViewProjection', mWorldViewProjection));

    V(g_pEffect._Begin(@NumPasses, 0));

    for iPass := 0 to NumPasses - 1 do
    begin
      V(g_pEffect.BeginPass(iPass));

      V(pMesh.DrawSubset(0));

      V(g_pEffect.EndPass);
    end;

    V(g_pEffect._End);
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
  txtHelper := CDXUTTextHelper.Create(g_pFont, g_pTextSprite, 15);

  // Output statistics
  txtHelper._Begin;
  txtHelper.SetInsertionPos(5, 5);
  txtHelper.SetForegroundColor(D3DXColor(0.3, 0.3, 0.7, 1.0));
  txtHelper.DrawTextLine(DXUTGetFrameStats);
  txtHelper.DrawTextLine(DXUTGetDeviceStats);

  txtHelper.SetForegroundColor(D3DXColor(0.4, 0.4, 0.6, 1.0));
  txtHelper.DrawTextLine('Please see the AntiAlias documentation');

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
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN:      DXUTToggleFullScreen;
    IDC_TOGGLEREF:             DXUTToggleREF;
    IDC_CHANGEDEVICE:          with g_SettingsDlg do Active := not Active;
    IDC_MULTISAMPLE_TYPE:      OnMultisampleTypeChanged;
    IDC_MULTISAMPLE_QUALITY:   OnMultisampleQualityChanged;
    IDC_CENTROID:              g_bCentroid := (pControl as CDXUTCheckBox).Checked; 
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
  SAFE_RELEASE(g_pVertexDecl);
  SAFE_RELEASE(g_pVBTriangles);
  SAFE_RELEASE(g_pMeshSphereHigh);
  SAFE_RELEASE(g_pMeshSphereLow);
  SAFE_RELEASE(g_pMeshQuadHigh);
  SAFE_RELEASE(g_pMeshQuadLow);
  SAFE_RELEASE(g_pCheckerTexture);
  SAFE_RELEASE(g_pTriangleTexture);
end;


procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_HUD := CDXUTDialog.Create;          // dialog for standard controls
  g_DialogLabels := CDXUTDialog.Create; // Labels within the current scene
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_HUD);
  FreeAndNil(g_DialogLabels);
end;

end.
