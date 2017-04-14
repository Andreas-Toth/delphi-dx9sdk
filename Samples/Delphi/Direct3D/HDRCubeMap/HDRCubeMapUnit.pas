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
 *  $Id: HDRCubeMapUnit.pas,v 1.11 2007/02/05 22:21:06 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: HDRCubeMap.cpp
//
// This sample demonstrates a common shadow technique called shadow mapping.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit HDRCubeMapUnit;

interface

uses
  Windows, Messages, SysUtils, Math,
  DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTMesh, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders


//--------------------------------------------------------------------------------------
// Defines, and constants
//--------------------------------------------------------------------------------------

const
  ENVMAPSIZE = 256;
  // Currently, 4 is the only number of lights supported.
  NUM_LIGHTS = 4;
  LIGHTMESH_RADIUS = 0.2;

  HELPTEXTCOLOR: TD3DXColor = (r: 0.0; g: 1.0; b: 0.3; a: 1.0);


  g_aVertDecl: array[0..3] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0;  _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITION; UsageIndex: 0),
    (Stream: 0; Offset: 12; _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_NORMAL;   UsageIndex: 0),
    (Stream: 0; Offset: 24; _Type: D3DDECLTYPE_FLOAT2; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TEXCOORD; UsageIndex: 0),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );


  g_atszMeshFileName: array[0..2] of PWideChar =
  (
    'misc\teapot.x',
    'misc\skullocc.x',
    'misc\car.x'
  );

  NUM_MESHES = High(g_atszMeshFileName) + 1;

type
  POrbutData = ^TOrbutData;
  TOrbutData = record
    tszXFile: PWideChar;  // X file
    vAxis:    TD3DVector; // Axis of rotation
    fRadius:  Single;     // Orbit radius
    fSpeed:   Single;     // Orbit speed in radians per second
  end;


const
// Mesh file to use for orbiter objects
// These don't have to use the same mesh file.

  g_OrbitData: array [0..1] of TOrbutData =
  (
    (tszXFile: 'airplane\airplane 2.x'; vAxis: (x:-1.0; y: 0.0; z: 0.0); fRadius: 2.0; fSpeed: {D3DX_PI}3.141592654 * 1.0),
    (tszXFile: 'airplane\airplane 2.x'; vAxis: (x: 0.3; y: 1.0; z: 0.3); fRadius: 2.5; fSpeed: {D3DX_PI}3.141592654 / 2.0)
  );


function ComputeBoundingSphere(Mesh: CDXUTMesh; out pvCtr: TD3DXVector3; out pfRadius: Single): HRESULT;



type
  //--------------------------------------------------------------------------------------
  // Encapsulate an object in the scene with its world transformation
  // matrix.
  //--------------------------------------------------------------------------------------
  CObj = class
    m_mWorld: TD3DXMatrixA16;  // World transformation
    m_Mesh:   CDXUTMesh;    // Mesh object
  public
    constructor Create; { D3DXMatrixIdentity( &m_mWorld ); }
    // destructor Destroy; override; {}
    function WorldCenterAndScaleToRadius(fRadius: Single): HRESULT;
  end;


  //--------------------------------------------------------------------------------------
  // Encapsulate an orbiter object in the scene with related data
  //--------------------------------------------------------------------------------------
  COrbiter = class(CObj)
  public
    m_vAxis:   TD3DXVector3; // orbit axis
    m_fRadius: Single;       // orbit radius
    m_fSpeed:  Single;       // Speed, angle in radian per second

  public
    constructor Create; // m_vAxis( 0.0f, 1.0f, 0.0f ), m_fRadius(1.0f), m_fSpeed( D3DX_PI )
    procedure SetOrbit(const vAxis: TD3DXVector3; fRadius: Single; fSpeed: Single);
    procedure Orbit(fElapsedTime: Single);
  end;


  PLight = ^TLight;
  TLight = record
    vPos:      TD3DXVector4;    // Position in world space
    vMoveDir:  TD3DXVector4;    // Direction in which it moves
    fMoveDist: Single;          // Maximum distance it can move
    mWorld:    TD3DXMatrixA16;  // World transform matrix for the light before animation
    mWorking:  TD3DXMatrixA16;  // Working matrix (world transform after animation)
  end;


  PTechniqueGroup = ^TTechniqueGroup;
  TTechniqueGroup = record
    hRenderScene:  TD3DXHandle;
    hRenderLight:  TD3DXHandle;
    hRenderEnvMap: TD3DXHandle;
  end;
  PATechniqueGroup = ^ATechniqueGroup;
  ATechniqueGroup = array[0..MaxInt div SizeOf(TTechniqueGroup) - 1] of TTechniqueGroup; 

  PAIDirect3DCubeTexture9 = ^AIDirect3DCubeTexture9;
  AIDirect3DCubeTexture9 = array [0..999] of IDirect3DCubeTexture9;


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont:           ID3DXFont;            // Font for drawing text
  g_pTextSprite:     ID3DXSprite;          // Sprite for batching draw text calls
  g_pEffect:         ID3DXEffect;          // D3DX effect interface
  g_Camera:          CModelViewerCamera;   // A model viewing camera
  g_bShowHelp:       Boolean  = True;      // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg:     CD3DSettingsDlg;      // Device settings dialog
  g_HUD:             CDXUTDialog;          // dialog for standard controls
  g_aLights:         array [0..NUM_LIGHTS-1] of TLight; // Parameters of light objects
  g_vLightIntensity: TD3DXVector4;         // Light intensity
  g_EnvMesh:         array [0..NUM_MESHES-1] of CObj; // Mesh to receive environment mapping
  g_nCurrMesh:       Integer = 0;          // Index of the element in m_EnvMesh we are currently displaying
  g_Room:            CDXUTMesh;            // Mesh representing room (wall, floor, ceiling)
  g_Orbiter:         array [0..High(g_OrbitData)] of COrbiter; // Orbiter meshes
  g_LightMesh:       CDXUTMesh;            // Mesh for the light object
  g_pVertDecl:       IDirect3DVertexDeclaration9; // Vertex decl for the sample
  g_apCubeMapFp:     array [0..1] of IDirect3DCubeTexture9; // Floating point format cube map
  g_pCubeMap32:      IDirect3DCubeTexture9;// 32-bit cube map (for fallback)
  g_pDepthCube:      IDirect3DSurface9;    // Depth-stencil buffer for rendering to cube texture
  g_nNumFpCubeMap:   Integer = 0;          // Number of cube maps required for using floating point
  g_aTechGroupFp:    array [0..1] of TTechniqueGroup; // Group of techniques to use with floating pointcubemaps (2 cubes max)
  g_TechGroup32:     TTechniqueGroup;      // Group of techniques to use with integer cubemaps
  g_hWorldView:      TD3DXHandle;          // Handle for world+view matrix in effect
  g_hProj:           TD3DXHandle;          // Handle for projection matrix in effect
  g_ahtxCubeMap:     array [0..1] of TD3DXHandle; // Handle for the cube texture in effect
  g_htxScene:        TD3DXHandle;          // Handle for the scene texture in effect
  g_hLightIntensity: TD3DXHandle;          // Handle for the light intensity in effect
  g_hLightPosView:   TD3DXHandle;          // Handle for view space light positions in effect
  g_hReflectivity:   TD3DXHandle;          // Handle for reflectivity in effect

  g_nNumCubes:       Integer;              // Number of cube maps used based on current cubemap format
  g_apCubeMap:       PAIDirect3DCubeTexture9 = @g_apCubeMapFp; // Cube map(s) to use based on current cubemap format
  g_pTech:           PATechniqueGroup = @g_aTechGroupFp; // Techniques to be used based on cubemap format

  g_fWorldRotX:      Single = 0.0;         // World rotation state X-axis
  g_fWorldRotY:      Single = 0.0;         // World rotation state Y-axis
  g_bUseFloatCubeMap:Boolean;              // Whether we use floating point format cube map
  g_fReflectivity:   Single;               // Reflectivity value. Ranges from 0 to 1.


const
  //--------------------------------------------------------------------------------------
  // UI control IDs
  //--------------------------------------------------------------------------------------
  IDC_TOGGLEFULLSCREEN  = 1;
  IDC_TOGGLEREF         = 3;
  IDC_CHANGEDEVICE      = 4;
  IDC_CHANGEMESH        = 5;
  IDC_RESETPARAM        = 6;
  IDC_SLIDERLIGHTTEXT   = 7;
  IDC_SLIDERLIGHT       = 8;
  IDC_SLIDERREFLECTTEXT = 9;
  IDC_SLIDERREFLECT     = 10;
  IDC_CHECKHDR          = 11;


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
function LoadMesh(pd3dDevice: IDirect3DDevice9; wszName: PWideChar; Mesh: CDXUTMesh): HRESULT;
procedure RenderText;

procedure ResetParameters;
procedure RenderSceneIntoCubeMap(const pd3dDevice: IDirect3DDevice9; fTime: Double);
procedure RenderScene(const pd3dDevice: IDirect3DDevice9; const pmView, pmProj: TD3DXMatrix; const pTechGroup: TTechniqueGroup; bRenderEnvMappedMesh: Boolean; fTime: Double);
procedure UpdateUiWithChanges;

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;


implementation


function ComputeBoundingSphere(Mesh: CDXUTMesh; out pvCtr: TD3DXVector3; out pfRadius: Single): HRESULT;
var
  pMeshObj: ID3DXMesh;
  decl: TFVFDeclaration; // D3DVERTEXELEMENT9 decl[MAX_FVF_DECL_SIZE];
  pVB: Pointer; // LPprocedure
  uStride: LongWord;
begin
  // Obtain the bounding sphere
  pMeshObj := Mesh.Mesh;
  if (pMeshObj = nil) then
  begin
    Result:= E_FAIL;
    Exit;
  end;

  // Obtain the declaration
  Result := pMeshObj.GetDeclaration(decl);
  if FAILED(Result) then Exit;

  // Lock the vertex buffer
  Result := pMeshObj.LockVertexBuffer(D3DLOCK_READONLY, pVB);
  if FAILED(Result) then Exit;

  // Compute the bounding sphere
  uStride := D3DXGetDeclVertexSize(@decl, 0);
  Result := D3DXComputeBoundingSphere(PD3DXVector3(pVB), pMeshObj.GetNumVertices,
                                      uStride, pvCtr, pfRadius);
  pMeshObj.UnlockVertexBuffer;
end;


//--------------------------------------------------------------------------------------
// Initialize the app 
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  pElement: CDXUTElement;
  iY: Integer;
begin
  // Change CheckBox default visual style
  pElement := g_HUD.GetDefaultElement(DXUT_CONTROL_CHECKBOX, 0);
  if Assigned(pElement) then
  begin
    pElement.FontColor.States[DXUT_STATE_NORMAL] := D3DCOLOR_ARGB(255, 0, 255, 0);
  end;

  // Change Static default visual style
  pElement := g_HUD.GetDefaultElement(DXUT_CONTROL_STATIC, 0);
  if Assigned(pElement) then
  begin
    pElement.dwTextFormat := DT_LEFT or DT_VCENTER;
    pElement.FontColor.States[DXUT_STATE_NORMAL] := D3DCOLOR_ARGB(255, 0, 255, 0);
  end;

  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent);
   iY := 10;   g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', 35, iY, 125, 22 );
  Inc(iY, 24); g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 35, iY, 125, 22 );

  Inc(iY, 24); g_HUD.AddButton(IDC_CHANGEMESH, 'Change Mesh (N)', 35, iY, 125, 22, Ord('N'));
  Inc(iY, 24); g_HUD.AddButton(IDC_RESETPARAM, 'Reset Parameters (R)', 35, iY, 125, 22, Ord('R'));
  Inc(iY, 24); g_HUD.AddCheckBox(IDC_CHECKHDR, 'Use HDR Texture (F)', 35, iY, 130, 22, True, Ord('F'));
  Inc(iY, 24); g_HUD.AddStatic(IDC_SLIDERLIGHTTEXT, 'Light Intensity', 35, iY, 125, 16);
  Inc(iY, 17); g_HUD.AddSlider(IDC_SLIDERLIGHT, 35, iY, 125, 22, 0, 1500);
  Inc(iY, 24); g_HUD.AddStatic(IDC_SLIDERREFLECTTEXT, 'Reflectivity', 35, iY, 125, 16);
  Inc(iY, 17); g_HUD.AddSlider(IDC_SLIDERREFLECT, 35, iY, 125, 22, 0, 100);
    
  ResetParameters();

  // Initialize camera parameters
  g_Camera.SetModelCenter(D3DXVector3(0.0, 0.0, 0.0));
  g_Camera.SetRadius(3.0);
  g_Camera.SetEnablePositionMovement(False);

  // Set the light positions
  g_aLights[0].vPos := D3DXVector4(-3.5, 2.3, -4.0, 1.0);
  g_aLights[0].vMoveDir := D3DXVector4(0.0, 0.0, 1.0, 0.0);
  g_aLights[0].fMoveDist := 8.0;
if NUM_LIGHTS > 1 then
begin
  g_aLights[1].vPos := D3DXVector4(3.5, 2.3,  4.0, 1.0);
  g_aLights[1].vMoveDir := D3DXVector4(0.0, 0.0, -1.0, 0.0);
  g_aLights[1].fMoveDist := 8.0;
end;
if NUM_LIGHTS > 2 then
begin
  g_aLights[2].vPos := D3DXVECTOR4( -3.5, 2.3,  4.0, 1.0);
  g_aLights[2].vMoveDir := D3DXVECTOR4( 1.0, 0.0, 0.0, 0.0);
  g_aLights[2].fMoveDist := 7.0;
end;
if NUM_LIGHTS > 3 then
begin
  g_aLights[3].vPos := D3DXVECTOR4(  3.5, 2.3, -4.0, 1.0);
  g_aLights[3].vMoveDir := D3DXVECTOR4( -1.0, 0.0, 0.0, 0.0);
  g_aLights[3].fMoveDist := 7.0;
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

  // Must support cube textures
  if (pCaps.TextureCaps and D3DPTEXTURECAPS_CUBEMAP = 0) then Exit;

  // Must support vertex shader 1.1
  if (pCaps.VertexShaderVersion < D3DVS_VERSION(1, 1)) then Exit;

  // Must support pixel shader 2.0
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2, 0)) then Exit;

  // need to support D3DFMT_A16B16G16R16F render target
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                   AdapterFormat, D3DUSAGE_RENDERTARGET,
                   D3DRTYPE_CUBETEXTURE, D3DFMT_A16B16G16R16F)) then
  begin
    // If not, need to support D3DFMT_G16R16F render target as fallback
    if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                     AdapterFormat, D3DUSAGE_RENDERTARGET,
                     D3DRTYPE_CUBETEXTURE, D3DFMT_G16R16F))
    then Exit;
  end;

  // need to support D3DFMT_A8R8G8B8 render target
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                   AdapterFormat, D3DUSAGE_RENDERTARGET,
                   D3DRTYPE_CUBETEXTURE, D3DFMT_A8R8G8B8))
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
  pD3D: IDirect3D9; 
begin
  // Initialize the number of cube maps required when using floating point format
  pD3D := DXUTGetD3DObject;
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                                   pDeviceSettings.AdapterFormat, D3DUSAGE_RENDERTARGET,
                                   D3DRTYPE_CUBETEXTURE, D3DFMT_A16B16G16R16F))
    then g_nNumFpCubeMap := 2
    else g_nNumFpCubeMap := 1;
  g_nNumCubes := g_nNumFpCubeMap;

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


//-----------------------------------------------------------------------------
// Reset light and material parameters to default values
//-----------------------------------------------------------------------------
procedure ResetParameters;
begin
  g_bUseFloatCubeMap := True;
  g_fReflectivity    := 0.4;
  g_vLightIntensity  := D3DXVector4(24.0, 24.0, 24.0, 24.0);

  if (g_pEffect <> nil) then
  begin
    V(g_pEffect.SetFloat(g_hReflectivity, g_fReflectivity));
    V(g_pEffect.SetVector(g_hLightIntensity, g_vLightIntensity));
  end;

  UpdateUiWithChanges;
end;


//--------------------------------------------------------------------------------------
// Write the updated values to the static UI controls
procedure UpdateUiWithChanges;
var
  pStatic: CDXUTStatic;
  pSlider: CDXUTSlider;
  pCheck: CDXUTCheckBox;
begin
  pStatic := g_HUD.GetStatic(IDC_SLIDERLIGHTTEXT);
  if (pStatic <> nil) then
  begin
    // swprintf( wszText, L"Light intensity: %0.2f", g_vLightIntensity.x);
    pStatic.Text := PWideChar(WideFormat('Light intensity: %0.2f', [g_vLightIntensity.x]));
  end;
  pStatic := g_HUD.GetStatic(IDC_SLIDERREFLECTTEXT);
  if (pStatic <> nil) then
  begin
    // swprintf( wszText, L"Reflectivity: %0.2f", g_fReflectivity);
    pStatic.Text := PWideChar(WideFormat('Reflectivity: %0.2f', [g_fReflectivity]));
  end;
  pSlider := g_HUD.GetSlider(IDC_SLIDERLIGHT);
  if (pSlider <> nil) then
  begin
    pSlider.Value := Trunc(g_vLightIntensity.x * 10.0 + 0.5);
  end;
  pSlider := g_HUD.GetSlider(IDC_SLIDERREFLECT);
  if (pSlider <> nil) then
  begin
    pSlider.Value := Trunc(g_fReflectivity * 100.0 + 0.5);
  end;
  pCheck := g_HUD.GetCheckBox(IDC_CHECKHDR);
  if (pCheck <> nil) then pCheck.Checked := g_bUseFloatCubeMap;
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
  i: Integer;
  vCtr: TD3DXVector3;
  fRadius: Single;
  mWorld, m: TD3DXMatrixA16;
  vAxis: TD3DXVector3;
  mIdent: TD3DXMatrixA16;
  vFromPt: TD3DXVector3;
  vLookatPt: TD3DXVector3;
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
  Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, 'HDRCubeMap.fx');
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // they the .fx file failed to compile
  Result := D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags,
                                      nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  g_hWorldView           := g_pEffect.GetParameterByName(nil, 'g_mWorldView');
  g_hProj                := g_pEffect.GetParameterByName(nil, 'g_mProj');
  g_ahtxCubeMap[0]       := g_pEffect.GetParameterByName(nil, 'g_txCubeMap');
  g_ahtxCubeMap[1]       := g_pEffect.GetParameterByName(nil, 'g_txCubeMap2');
  g_htxScene             := g_pEffect.GetParameterByName(nil, 'g_txScene');
  g_hLightIntensity      := g_pEffect.GetParameterByName(nil, 'g_vLightIntensity');
  g_hLightPosView        := g_pEffect.GetParameterByName(nil, 'g_vLightPosView');
  g_hReflectivity        := g_pEffect.GetParameterByName(nil, 'g_fReflectivity');

  // Determine the technique to render with

  // Integer cube map
  g_TechGroup32.hRenderScene  := g_pEffect.GetTechniqueByName('RenderScene');
  g_TechGroup32.hRenderLight  := g_pEffect.GetTechniqueByName('RenderLight');
  g_TechGroup32.hRenderEnvMap := g_pEffect.GetTechniqueByName('RenderHDREnvMap');

  ZeroMemory(@g_aTechGroupFp, SizeOf(g_aTechGroupFp));
  if (g_nNumFpCubeMap = 2) then
  begin
    // Two floating point G16R16F cube maps
    g_aTechGroupFp[0].hRenderScene  := g_pEffect.GetTechniqueByName('RenderSceneFirstHalf');
    g_aTechGroupFp[0].hRenderLight  := g_pEffect.GetTechniqueByName('RenderLightFirstHalf');
    g_aTechGroupFp[0].hRenderEnvMap := g_pEffect.GetTechniqueByName('RenderHDREnvMap2Tex');
    g_aTechGroupFp[1].hRenderScene  := g_pEffect.GetTechniqueByName('RenderSceneSecondHalf');
    g_aTechGroupFp[1].hRenderLight  := g_pEffect.GetTechniqueByName('RenderLightSecondHalf');
    g_aTechGroupFp[1].hRenderEnvMap := g_pEffect.GetTechniqueByName('RenderHDREnvMap2Tex');
  end else
  begin
    // Single floating point cube map
    g_aTechGroupFp[0].hRenderScene  := g_pEffect.GetTechniqueByName('RenderScene');
    g_aTechGroupFp[0].hRenderLight  := g_pEffect.GetTechniqueByName('RenderLight');
    g_aTechGroupFp[0].hRenderEnvMap := g_pEffect.GetTechniqueByName('RenderHDREnvMap');
  end;

  // Initialize reflectivity
  Result := g_pEffect.SetFloat(g_hReflectivity, g_fReflectivity);
  if V_Failed(Result) then Exit;

  // Initialize light intensity
  Result := g_pEffect.SetVector(g_hLightIntensity, g_vLightIntensity);
  if V_Failed(Result) then Exit;

  // Create vertex declaration
  Result := pd3dDevice.CreateVertexDeclaration(@g_aVertDecl, g_pVertDecl);
  if V_Failed(Result) then Exit;

  Result:= DXUTERR_MEDIANOTFOUND;

  // Load the mesh
  for i := 0 to NUM_MESHES - 1 do
  begin
    if FAILED(LoadMesh(pd3dDevice, g_atszMeshFileName[i], g_EnvMesh[i].m_Mesh)) then Exit;
    g_EnvMesh[i].WorldCenterAndScaleToRadius(1.0);  // Scale to radius of 1
  end;
  // Load the room object
  if FAILED(LoadMesh(pd3dDevice, 'room.x', g_Room)) then Exit;
  // Load the light object
  if FAILED(LoadMesh(pd3dDevice, 'misc\sphere0.x', g_LightMesh)) then Exit;
  // Initialize the world matrix for the lights
  if FAILED(ComputeBoundingSphere(g_LightMesh, vCtr, fRadius)) then
  begin
    Result:= E_FAIL;
    Exit;
  end;
  D3DXMatrixTranslation(mWorld, -vCtr.x, -vCtr.y, -vCtr.z);
  D3DXMatrixScaling(m, LIGHTMESH_RADIUS / fRadius,
                       LIGHTMESH_RADIUS / fRadius,
                       LIGHTMESH_RADIUS / fRadius);
  D3DXMatrixMultiply(mWorld, mWorld, m);
  for i := 0 to NUM_LIGHTS - 1 do
  begin
    D3DXMatrixTranslation(m, g_aLights[i].vPos.x,
                             g_aLights[i].vPos.y,
                             g_aLights[i].vPos.z);
    D3DXMatrixMultiply(g_aLights[i].mWorld, mWorld, m);
  end;

  // Orbiter
  for i := 0 to High(g_Orbiter) do
  begin
    if FAILED(LoadMesh(pd3dDevice, g_OrbitData[i].tszXFile, g_Orbiter[i].m_Mesh)) then Exit;

    g_Orbiter[i].WorldCenterAndScaleToRadius(0.7);
    vAxis := g_OrbitData[i].vAxis;
    g_Orbiter[i].SetOrbit(vAxis, g_OrbitData[i].fRadius, g_OrbitData[i].fSpeed);
  end;

  // World transform to identity
  D3DXMatrixIdentity(mIdent);
  Result := pd3dDevice.SetTransform(D3DTS_WORLD, mIdent);
  if V_Failed(Result) then Exit;


  // Setup the camera's view parameters
  vFromPt := D3DXVector3(0.0, 0.0, -2.5);
  vLookatPt := D3DXVector3(0.0, 0.0, 0.0);
  g_Camera.SetViewParams(vFromPt, vLookatPt);

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// Load mesh from file and convert vertices to our format
//--------------------------------------------------------------------------------------
function LoadMesh(pd3dDevice: IDirect3DDevice9; wszName: PWideChar; Mesh: CDXUTMesh): HRESULT;
begin
  Result := Mesh.CreateMesh(pd3dDevice, wszName);
  if Failed(Result) then Exit;

  Result := Mesh.SetVertexDecl(pd3dDevice, @g_aVertDecl);
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
  pControl: CDXUTControl;
  iY: Integer;
  i: Integer;
  d3dSettings: TDXUTDeviceSettings;
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
  iY := pBackBufferSurfaceDesc.Height - 170;

  pControl := g_HUD.GetControl(IDC_CHECKHDR);
  if Assigned(pControl) then pControl.SetLocation(35, iY);
  pControl := g_HUD.GetControl(IDC_CHANGEMESH); Inc(iY, 24);
  if Assigned(pControl) then pControl.SetLocation(35, iY);
  pControl := g_HUD.GetControl(IDC_RESETPARAM); Inc(iY, 24);
  if Assigned(pControl) then pControl.SetLocation(35, iY);
  pControl := g_HUD.GetControl(IDC_SLIDERLIGHTTEXT); Inc(iY, 35);
  if Assigned(pControl) then pControl.SetLocation(35, iY);
  pControl := g_HUD.GetControl(IDC_SLIDERLIGHT); Inc(iY, 17);
  if Assigned(pControl) then pControl.SetLocation(35, iY);
  pControl := g_HUD.GetControl(IDC_SLIDERREFLECTTEXT); Inc(iY, 24);
  if Assigned(pControl) then pControl.SetLocation(35, iY);
  pControl := g_HUD.GetControl(IDC_SLIDERREFLECT); Inc(iY, 17);
  if Assigned(pControl) then pControl.SetLocation(35, iY);

  // Restore meshes
  for i := 0 to NUM_MESHES - 1 do
    g_EnvMesh[i].m_Mesh.RestoreDeviceObjects(pd3dDevice);
  g_Room.RestoreDeviceObjects(pd3dDevice);
  g_LightMesh.RestoreDeviceObjects(pd3dDevice);
  for i := 0 to High(g_Orbiter) do
    g_Orbiter[i].m_Mesh.RestoreDeviceObjects(pd3dDevice);

  // Create the cube textures
  ZeroMemory(@g_apCubeMapFp, SizeOf(g_apCubeMapFp));
  Result := pd3dDevice.CreateCubeTexture(ENVMAPSIZE,
                                         1,
                                         D3DUSAGE_RENDERTARGET,
                                         D3DFMT_A16B16G16R16F,
                                         D3DPOOL_DEFAULT,
                                         g_apCubeMapFp[0],
                                         nil);
  if FAILED(Result) then
  begin
    // Create 2 G16R16 textures as fallback
    Result := pd3dDevice.CreateCubeTexture(ENVMAPSIZE,
                                           1,
                                           D3DUSAGE_RENDERTARGET,
                                           D3DFMT_G16R16F,
                                           D3DPOOL_DEFAULT,
                                           g_apCubeMapFp[0],
                                           nil);
    if V_Failed(Result) then Exit;

    Result := pd3dDevice.CreateCubeTexture(ENVMAPSIZE,
                                           1,
                                           D3DUSAGE_RENDERTARGET,
                                           D3DFMT_G16R16F,
                                           D3DPOOL_DEFAULT,
                                           g_apCubeMapFp[1],
                                           nil);
    if V_Failed(Result) then Exit;
  end;

  Result := pd3dDevice.CreateCubeTexture(ENVMAPSIZE,
                                         1,
                                         D3DUSAGE_RENDERTARGET,
                                         D3DFMT_A8R8G8B8,
                                         D3DPOOL_DEFAULT,
                                         g_pCubeMap32,
                                         nil);
  if V_Failed(Result) then Exit;

  // Create the stencil buffer to be used with the cube textures
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
  Result := pd3dDevice.CreateDepthStencilSurface(ENVMAPSIZE,
                                                 ENVMAPSIZE,
                                                 d3dSettings.pp.AutoDepthStencilFormat,
                                                 D3DMULTISAMPLE_NONE,
                                                 0,
                                                 True,
                                                 g_pDepthCube,
                                                 nil);
  if V_Failed(Result) then Exit;

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
  // Update the camera's position based on user input
  g_Camera.FrameMove(fElapsedTime);

  for i := 0 to High(g_Orbiter) do g_Orbiter[i].Orbit(fElapsedTime);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called at the end of every frame to perform all the 
// rendering calls for the scene, and it will also be called if the window needs to be 
// repainted. After this function has returned, the sample framework will call 
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

  RenderSceneIntoCubeMap(pd3dDevice, fTime);

  // Clear the render buffers
  V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, $000000ff, 1.0, 0));

  // Begin the scene
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    RenderScene(pd3dDevice, g_Camera.GetViewMatrix^, g_Camera.GetProjMatrix^, g_pTech[0], True, fTime);

    // Render stats and help text
    RenderText;

    g_HUD.OnRender(fElapsedTime);

    pd3dDevice.EndScene;
  end;
end;


//--------------------------------------------------------------------------------------
// Set up the cube map by rendering the scene into it.
//--------------------------------------------------------------------------------------
procedure RenderSceneIntoCubeMap(const pd3dDevice: IDirect3DDevice9; fTime: Double);
var
  mProj: TD3DXMatrixA16;
  mViewDir: TD3DXMatrixA16;
  pRTOld: IDirect3DSurface9;
  pDSOld: IDirect3DSurface9;
  nCube: Integer;
  nFace: TD3DCubemapFaces;
  pSurf: IDirect3DSurface9;
  mView: TD3DXMatrixA16;
begin
  // The projection matrix has a FOV of 90 degrees and asp ratio of 1
  D3DXMatrixPerspectiveFovLH(mProj, D3DX_PI * 0.5, 1.0, 0.01, 100.0);

  mViewDir := g_Camera.GetViewMatrix^;
  mViewDir._41 := 0.0; mViewDir._42 := 0.0; mViewDir._43 := 0.0;

  V(pd3dDevice.GetRenderTarget(0, pRTOld));
  if SUCCEEDED(pd3dDevice.GetDepthStencilSurface(pDSOld)) then
  begin
    // If the device has a depth-stencil buffer, use
    // the depth stencil buffer created for the cube textures.
    V(pd3dDevice.SetDepthStencilSurface(g_pDepthCube));
  end;

  for nCube := 0 to g_nNumCubes - 1 do
    for nFace := Low(TD3DCubemapFaces) to High(TD3DCubemapFaces) do
    begin
      V(g_apCubeMap[nCube].GetCubeMapSurface(nFace, 0, pSurf));
      V(pd3dDevice.SetRenderTarget(0, pSurf));
      SAFE_RELEASE(pSurf);

      mView := DXUTGetCubeMapViewMatrix(nFace);
      D3DXMatrixMultiply(mView, mViewDir, mView);

      V(pd3dDevice.Clear(0, nil, D3DCLEAR_ZBUFFER, $000000ff, 1.0, 0));

      // Begin the scene
      if SUCCEEDED(pd3dDevice.BeginScene) then
      begin
        RenderScene(pd3dDevice, mView, mProj, g_pTech[nCube], False, fTime);

        // End the scene.
        pd3dDevice.EndScene;
      end;
    end;

  // Restore depth-stencil buffer and render target
  if (pDSOld <> nil) then
  begin
    V(pd3dDevice.SetDepthStencilSurface(pDSOld));
    SAFE_RELEASE(pDSOld);
  end;
  V(pd3dDevice.SetRenderTarget(0, pRTOld));
  SAFE_RELEASE(pRTOld);
end;


//--------------------------------------------------------------------------------------
// Renders the scene with a specific view and projection matrix.
//--------------------------------------------------------------------------------------
procedure RenderScene(const pd3dDevice: IDirect3DDevice9; const pmView, pmProj: TD3DXMatrix;
  const pTechGroup: TTechniqueGroup; bRenderEnvMappedMesh: Boolean; fTime: Double);
 function fmod(x, y: Single): Single;
 begin
   //;Description    fmod calculates  x - (y * chop (x / y));
   Result:= x - (y*Trunc(x/y));
 end;
var
  p, cPass: LongWord;
  mWorldView: TD3DXMatrixA16;
  avLightPosView: array [0..NUM_LIGHTS-1] of TD3DXVector4;
  i: Integer;
  fDisp: Single; // Distance to move
  vMove: TD3DXVector4;  // In vector form
  pMesh: ID3DXMesh;
  pMeshObj: ID3DXMesh;
  m: Integer;
begin
  V(g_pEffect.SetMatrix(g_hProj, pmProj));

  // Write camera-space light positions to effect
  for i := 0 to NUM_LIGHTS - 1 do
  begin
    // Animate the lights
    fDisp := (1.0 + cos(fmod(fTime, D3DX_PI))) * 0.5 * g_aLights[i].fMoveDist; // Distance to move
    // vMove := g_aLights[i].vMoveDir * fDisp;  // In vector form
    D3DXVec4Scale(vMove, g_aLights[i].vMoveDir, fDisp);
    D3DXMatrixTranslation(g_aLights[i].mWorking, vMove.x, vMove.y, vMove.z); // Matrix form
    D3DXMatrixMultiply(g_aLights[i].mWorking, g_aLights[i].mWorld, g_aLights[i].mWorking);
    // vMove += g_aLights[i].vPos;  // Animated world coordinates
    D3DXVec4Add(vMove, vMove, g_aLights[i].vPos);  // Animated world coordinates
    D3DXVec4Transform(avLightPosView[i], vMove, pmView);
  end;
  V(g_pEffect.SetVectorArray(g_hLightPosView, @avLightPosView, NUM_LIGHTS));

  //
  // Render the environment-mapped mesh if specified
  //

  if bRenderEnvMappedMesh then
  begin
    V(g_pEffect.SetTechnique(pTechGroup.hRenderEnvMap));

    // Combine the offset and scaling transformation with
    // rotation from the camera to form the final
    // world transformation matrix.
    D3DXMatrixMultiply(mWorldView, g_EnvMesh[g_nCurrMesh].m_mWorld, g_Camera.GetWorldMatrix^);
    D3DXMatrixMultiply(mWorldView, mWorldView, pmView);
    V(g_pEffect.SetMatrix(g_hWorldView, mWorldView ));

    V(g_pEffect._Begin(@cPass, 0));

    for i := 0 to g_nNumCubes - 1 do
      V(g_pEffect.SetTexture(g_ahtxCubeMap[i], g_apCubeMap[i]));

    for p := 0 to cPass - 1 do
    begin
      V(g_pEffect.BeginPass(p));
      pMesh := g_EnvMesh[g_nCurrMesh].m_Mesh.Mesh;
      for i := 0 to g_EnvMesh[g_nCurrMesh].m_Mesh.m_dwNumMaterials - 1 do
        V(pMesh.DrawSubset(i));
      V(g_pEffect.EndPass);
    end;
    V(g_pEffect._End);
  end;

  //
  // Render light spheres
  //

  V(g_pEffect.SetTechnique(pTechGroup.hRenderLight));

  V(g_pEffect._Begin(@cPass, 0));
  for p := 0 to cPass - 1 do
  begin
    V(g_pEffect.BeginPass(p));

    for i := 0 to NUM_LIGHTS - 1 do
    begin
      D3DXMatrixMultiply(mWorldView, g_aLights[i].mWorking, pmView);
      V(g_pEffect.SetMatrix(g_hWorldView, mWorldView));
      V(g_pEffect.CommitChanges);
      V(g_LightMesh.Render(pd3dDevice));
    end;
    V(g_pEffect.EndPass);
  end;
  V(g_pEffect._End);

  //
  // Render the rest of the scene
  //

  V(g_pEffect.SetTechnique(pTechGroup.hRenderScene));

  V(g_pEffect._Begin(@cPass, 0));
  for p := 0 to cPass - 1 do
  begin
    V(g_pEffect.BeginPass(p));

    //
    // Orbiters
    //
    for i := 0 to High(g_Orbiter) do
    begin
      D3DXMatrixMultiply(mWorldView, g_Orbiter[i].m_mWorld, pmView);
      V(g_pEffect.SetMatrix(g_hWorldView, mWorldView));
      // Obtain the D3DX mesh object
      pMeshObj := g_Orbiter[i].m_Mesh.Mesh;
      // Iterate through each subset and render with its texture
      for m := 0 to g_Orbiter[i].m_Mesh.m_dwNumMaterials - 1 do
      begin
        V(g_pEffect.SetTexture(g_htxScene, g_Orbiter[i].m_Mesh.m_pTextures[m]));
        V(g_pEffect.CommitChanges);
        V(pMeshObj.DrawSubset(m));
      end;
    end;

    //
    // The room object (walls, floor, ceiling)
    //

    V(g_pEffect.SetMatrix(g_hWorldView, pmView));
    pMeshObj := g_Room.Mesh;
    // Iterate through each subset and render with its texture
    for m := 0 to g_Room.m_dwNumMaterials - 1 do
    begin
      V(g_pEffect.SetTexture(g_htxScene, g_Room.m_pTextures[m]));
      V(g_pEffect.CommitChanges);
      V(pMeshObj.DrawSubset(m));
    end;
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
    
  // Draw help
  pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
  if g_bShowHelp then
  begin
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*12);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
    txtHelper.DrawTextLine('Controls:');

    txtHelper.SetInsertionPos(40, pd3dsdBackBuffer.Height-15*11);
    txtHelper.DrawTextLine('Rotate object: Left drag mouse'#10 +
                           'Adjust camera: Right drag mouse'#10'Zoom In/Out: Mouse wheel'#10 +
                           'Adjust reflectivity: E,D'#10'Adjust light intensity: W,S'#10 +
                           'Hide help: F1'#10 +
                           'Quit: ESC');
  end else
  begin
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
    txtHelper.DrawTextLine('Press F1 for help');
  end;

  txtHelper.SetForegroundColor(D3DXColor(0.0, 1.0, 0.0, 1.0));
  txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height - 48);
  txtHelper.DrawTextLine('Cube map format'#10 +
                         'Material reflectivity ( e/E, d/D )'#10 +
                         'Light intensity ( w/W, s/S )'#10);
  txtHelper.SetInsertionPos(190, pd3dsdBackBuffer.Height - 48);
  txtHelper.DrawFormattedTextLine('%s'#10'%.2f'#10'%.1f',
                                  [IfThen(g_bUseFloatCubeMap, 'Floating-point ( D3D9 / HDR )', 'Integer ( D3D8 )'),
                                  g_fReflectivity, g_vLightIntensity.x]);

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

  case uMsg of
    //
    // Use WM_CHAR to handle parameter adjustment so
    // that we can control the granularity based on
    // the letter cases.
    WM_CHAR:
    begin
      case Char(wParam) of
        'W', 'w':
        begin
          if (Ord('w') = wParam)
          then D3DXVec4Add(g_vLightIntensity, g_vLightIntensity, D3DXVector4(0.1, 0.1, 0.1, 0.0))
          else D3DXVec4Add(g_vLightIntensity, g_vLightIntensity, D3DXVector4(10.0, 10.0, 10.0, 0.0));
          if (g_vLightIntensity.x > 150.0) then
          begin
            g_vLightIntensity.x := 150.0;
            g_vLightIntensity.y := 150.0;
            g_vLightIntensity.z := 150.0;
          end;
          V(g_pEffect.SetVector(g_hLightIntensity, g_vLightIntensity));
          UpdateUiWithChanges;
        end;

        'S', 's':
        begin
          if (Ord('s') = wParam)
          then D3DXVec4Subtract(g_vLightIntensity, g_vLightIntensity, D3DXVector4(0.1, 0.1, 0.1, 0.0))
          else D3DXVec4Subtract(g_vLightIntensity, g_vLightIntensity, D3DXVector4(10.0, 10.0, 10.0, 0.0));
          if (g_vLightIntensity.x < 0.0) then
          begin
            g_vLightIntensity.x := 0.0;
            g_vLightIntensity.y := 0.0;
            g_vLightIntensity.z := 0.0;
          end;
          V(g_pEffect.SetVector(g_hLightIntensity, g_vLightIntensity));
          UpdateUiWithChanges;
        end;

        'D', 'd':
        begin
          if (Ord('d') = wParam)
          then g_fReflectivity := g_fReflectivity - 0.01
          else g_fReflectivity := g_fReflectivity - 0.1;
          if (g_fReflectivity < 0) then  g_fReflectivity := 0;
          V(g_pEffect.SetFloat(g_hReflectivity, g_fReflectivity));
          UpdateUiWithChanges;
        end;

        'E', 'e':
        begin
          if (Ord('e') = wParam) then g_fReflectivity := g_fReflectivity + 0.01
          else g_fReflectivity := g_fReflectivity + 0.1;
          if (g_fReflectivity > 1.0) then g_fReflectivity := 1.0;
          V(g_pEffect.SetFloat(g_hReflectivity, g_fReflectivity));
          UpdateUiWithChanges;
        end;
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
var
  pSlider: CDXUTSlider;
  pStatic: CDXUTStatic;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;
    IDC_CHECKHDR:
    begin
      g_bUseFloatCubeMap := (pControl as CDXUTCheckBox).Checked;
      if g_bUseFloatCubeMap then
      begin
        g_nNumCubes := g_nNumFpCubeMap;
        g_apCubeMap := @g_apCubeMapFp;
        g_pTech := @g_aTechGroupFp;
      end else
      begin
        g_nNumCubes := 1;
        g_apCubeMap := @g_pCubeMap32;
        g_pTech := @g_TechGroup32;
      end;
    end;

    IDC_CHANGEMESH:
    begin
      Inc(g_nCurrMesh);
      if (g_nCurrMesh = NUM_MESHES) then g_nCurrMesh := 0;
    end;

    IDC_RESETPARAM: ResetParameters;

    IDC_SLIDERLIGHT:
    begin
      if (nEvent = EVENT_SLIDER_VALUE_CHANGED) then
      begin
        pSlider := (pControl as CDXUTSlider);
        g_vLightIntensity.x := pSlider.Value * 0.1;
        g_vLightIntensity.y := pSlider.Value * 0.1;
        g_vLightIntensity.z := pSlider.Value * 0.1;
        if (g_pEffect <> nil) then g_pEffect.SetVector(g_hLightIntensity, g_vLightIntensity);
        pStatic := g_HUD.GetStatic(IDC_SLIDERLIGHTTEXT);
        if (pStatic <> nil) then
          pStatic.Text := PWideChar(WideFormat('Light intensity: %0.2f', [g_vLightIntensity.x]));
      end;
    end;

    IDC_SLIDERREFLECT:
    begin
      if (nEvent = EVENT_SLIDER_VALUE_CHANGED) then
      begin
        pSlider := (pControl as CDXUTSlider);
        g_fReflectivity := pSlider.Value * 0.01;
        if (g_pEffect <> nil) then g_pEffect.SetFloat(g_hReflectivity, g_fReflectivity);
        UpdateUiWithChanges;
        pStatic := g_HUD.GetStatic(IDC_SLIDERREFLECTTEXT);
        if (pStatic <> nil) then
          pStatic.Text := PWideChar(WideFormat('Reflectivity: %0.2f', [g_fReflectivity]));
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
procedure OnLostDevice;
var
  i: Integer;
begin
  g_DialogResourceManager.OnLostDevice;
  g_SettingsDlg.OnLostDevice;
  if Assigned(g_pFont) then g_pFont.OnLostDevice;
  if Assigned(g_pEffect) then g_pEffect.OnLostDevice;
  SAFE_RELEASE(g_pTextSprite);

  for i := 0 to NUM_MESHES - 1 do g_EnvMesh[i].m_Mesh.InvalidateDeviceObjects;
  g_Room.InvalidateDeviceObjects;
  g_LightMesh.InvalidateDeviceObjects;
  for i := 0 to High(g_Orbiter) do g_Orbiter[i].m_Mesh.InvalidateDeviceObjects;

  SAFE_RELEASE(g_apCubeMapFp[0]);
  SAFE_RELEASE(g_apCubeMapFp[1]);
  SAFE_RELEASE(g_pCubeMap32);
  SAFE_RELEASE(g_pDepthCube);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has
// been destroyed, which generally happens as a result of application termination or
// windowed/full screen toggles. Resources created in the OnCreateDevice callback
// should be released here, which generally includes all D3DPOOL_MANAGED resources.
//--------------------------------------------------------------------------------------
procedure OnDestroyDevice;
var
  i: Integer;
begin
  g_DialogResourceManager.OnDestroyDevice;
  g_SettingsDlg.OnDestroyDevice;
  SAFE_RELEASE(g_pEffect);
  SAFE_RELEASE(g_pFont);
  SAFE_RELEASE(g_pVertDecl);

  g_Room.DestroyMesh;
  g_LightMesh.DestroyMesh;
  for i := 0 to High(g_Orbiter) do g_Orbiter[i].m_Mesh.DestroyMesh;
  for i := 0 to NUM_MESHES - 1 do g_EnvMesh[i].m_Mesh.DestroyMesh;
end;



{ CObj }

constructor CObj.Create;
begin
  D3DXMatrixIdentity(m_mWorld);
  m_Mesh := CDXUTMesh.Create;
end;

//
// Compute the world transformation matrix
// to center the mesh at origin in world space
// and scale its size to the specified radius.
//
function CObj.WorldCenterAndScaleToRadius(fRadius: Single): HRESULT;
var
  fRadiusBound: Single;
  vCtr: TD3DXVector3;
  mScale: TD3DXMatrixA16;
begin
  Result := ComputeBoundingSphere(m_Mesh, vCtr, fRadiusBound);
  if FAILED(Result) then Exit;

  D3DXMatrixTranslation(m_mWorld, -vCtr.x, -vCtr.y, -vCtr.z);
  D3DXMatrixScaling(mScale, fRadius / fRadiusBound,
                            fRadius / fRadiusBound,
                            fRadius / fRadiusBound);
  D3DXMatrixMultiply(m_mWorld, m_mWorld, mScale);
end;



{ COrbiter }

constructor COrbiter.Create;
begin
  inherited;
  m_vAxis := D3DXVector3(0.0, 1.0, 0.0);
  m_fRadius := 1.0;
  m_fSpeed := D3DX_PI;
end;

// Compute the orbit transformation and apply to m_mWorld
procedure COrbiter.Orbit(fElapsedTime: Single);
var
  m: TD3DXMatrixA16;
begin
  D3DXMatrixRotationAxis(m, m_vAxis, m_fSpeed * fElapsedTime);
  D3DXMatrixMultiply(m_mWorld, m_mWorld, m);
end;

// Call this after m_mWorld is initialized
procedure COrbiter.SetOrbit(const vAxis: TD3DXVector3; fRadius, fSpeed: Single);
var
  m: TD3DXMatrixA16;
  vX: TD3DXVector3;
  vRot: TD3DXVector3;
  fAng: Single;  // Angle to rotate
  vXxRot: TD3DXVector3;  // X cross vRot
begin
  m_vAxis := vAxis; m_fRadius := fRadius; m_fSpeed := fSpeed;
  D3DXVec3Normalize(m_vAxis, m_vAxis);

  // Translate by m_fRadius in -Y direction
  D3DXMatrixTranslation(m, 0.0, -m_fRadius, 0.0);
  D3DXMatrixMultiply(m_mWorld, m_mWorld, m);

  // Apply rotation from X axis to the orbit axis
  vX := D3DXVector3(1.0, 0.0, 0.0);
  D3DXVec3Cross(vRot, m_vAxis, vX);  // Axis of rotation
  // If the cross product is 0, m_vAxis is on the X axis
  // So we either rotate 0 or PI.
  if D3DXVec3LengthSq(vRot) = 0 then
  begin
    if (m_vAxis.x < 0.0) then D3DXMatrixRotationY(m, D3DX_PI) // PI
      else D3DXMatrixIdentity(m); // 0
  end else
  begin
    fAng := ArcCos(D3DXVec3Dot(m_vAxis, vX));  // Angle to rotate
    // Find out direction to rotate
    D3DXVec3Cross(vXxRot, vX, vRot);
    if (D3DXVec3Dot(vXxRot, m_vAxis) >= 0) then fAng := -fAng;
    D3DXMatrixRotationAxis(m, vRot, fAng);
  end;
  D3DXMatrixMultiply(m_mWorld, m_mWorld, m);
end;



procedure CreateCustomDXUTobjects;
var
  i: Integer;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera:=    CModelViewerCamera.Create;   // A model viewing camera
  g_HUD:=       CDXUTDialog.Create;          // dialog for standard controls
  g_Room:=      CDXUTMesh.Create;            // Mesh representing room (wall, floor, ceiling)
  g_LightMesh:= CDXUTMesh.Create;            // Mesh for the light object

  for i:= 0 to NUM_MESHES-1 do g_EnvMesh[i]:= CObj.Create; // Mesh to receive environment mapping
  for i:= 0 to High(g_Orbiter) do g_Orbiter[i]:= COrbiter.Create; // Orbiter meshes
end;

procedure DestroyCustomDXUTobjects;
var
  i: Integer;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  g_Camera.Free;
  g_HUD.Free;
  g_Room.Free;
  g_LightMesh.Free;

  for i:= 0 to NUM_MESHES-1 do g_EnvMesh[i].Free; // Mesh to receive environment mapping
  for i:= 0 to High(g_Orbiter) do g_Orbiter[i].Free; // Orbiter meshes
end;

end.

