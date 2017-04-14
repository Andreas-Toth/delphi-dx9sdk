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
 *  $Id: InstancingUnit.pas,v 1.17 2007/02/05 22:21:09 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: Instancing.cpp
//
// Demonstrates the geometry instancing capability of VS3.0-capable hardware by replicating
// a single box model into a pile of boxes all in one DrawIndexedPrimitive call.
// Also shows alternate ways of doing instancing on non-vs_3_0 HW
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit InstancingUnit;

interface

uses
  Windows, SysUtils, Math,
  DXTypes, Direct3D9, D3DX9, dxerr9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
const
  g_nMaxBoxes         = 1000;                 // max number of boxes to render
  g_nNumBatchInstance = 120;                  // number of batched instances; must be the same size as g_nNumBatchInstance from .fx file
var
  g_pFont: ID3DXFont;                         // Font for drawing text
  g_pTextSprite: ID3DXSprite;                 // Sprite for batching draw text calls
  g_pEffect: ID3DXEffect;                     // D3DX effect interface
  g_Camera: CModelViewerCamera;               // A model viewing camera
  g_bShowHelp: Boolean = True;                // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg;             // Device settings dialog
  g_HUD: CDXUTDialog;                         // dialog for standard controls
  g_SampleUI: CDXUTDialog;                    // dialog for sample specific controls
  g_SampleUI2: CDXUTDialog;                   // dialog for sample specific controls
  g_bAppIsDebug: Boolean = False;             // The application build is debug
  g_bRuntimeDebug: Boolean = False;           // The D3D Debug Runtime was detected
  g_NumBoxes: Integer = 500;                  // current number of boxes
  g_iUpdateCPUUsageMessage: Integer = 0;      // controls when to update the CPU usage static control
  g_fBurnAmount: Double = 0.0;                // time in seconds to burn for during each burn period
  g_HandleTechnique: TD3DXHandle;             // handle to the rendering technique
  g_HandleWorld, g_HandleView, g_HandleProjection: TD3DXHandle;     // handle to the world/view/projection matrixes
  g_HandleTexture: TD3DXHandle;               // handle to the box texture
  g_HandleBoxInstance_Position: TD3DXHandle;  // handle to the box instance position (array or the value itself)
  g_HandleBoxInstance_Color: TD3DXHandle;     // handle to the box instance color (array or the value itself)
  g_pBoxTexture: IDirect3DTexture9;           // Texture covering the box
  g_iRenderTechnique: Word = 1;               // the currently selected rendering technique
  g_vBoxInstance_Position: array[0..g_nMaxBoxes-1] of TD3DXVector4; // instance data used in shader instancing (position)
  g_vBoxInstance_Color: array[0..g_nMaxBoxes-1] of TD3DXColor; // instance data used in shader instancing (color)
  g_fLastTime: Double = 0.0;
  g_nShowUI: Integer = 2;                     // If 2, show UI.  If 1, show text only.  If 0, show no UI.

  //--------------------------------------------------------------------------------------
  //This VB holds float-valued normal, position and texture coordinates for the model (in this case, a box)
  //This will be stream 0
  g_pVBBox: IDirect3DVertexBuffer9;
  g_pIBBox: IDirect3DIndexBuffer9;

type
  // Format of the box vertices for HW instancing
  PBoxVertex = ^TBoxVertex;
  TBoxVertex = packed record
    pos: TD3DXVector3;     // Position of the vertex
    norm: TD3DXVector3;    // Normal at this vertex
    u, v: Single;          // Texture coordinates u,v
  end;

  PBoxVertexArray = ^TBoxVertexArray;
  TBoxVertexArray = array[0..MaxInt div SizeOf(TBoxVertex)-1] of TBoxVertex;

  // Format of the box vertices for shader instancing
  PBoxVertexInstance = ^TBoxVertexInstance;
  TBoxVertexInstance = packed record
    pos: TD3DXVector3;    // Position of the vertex
    norm: TD3DXVector3;   // Normal at this vertex
    u, v: Single;         // Texture coordinates u,v
    boxInstance: Single;  // Box instance index
  end;

  PBoxVertexInstanceArray = ^TBoxVertexInstanceArray;
  TBoxVertexInstanceArray = array[0..MaxInt div SizeOf(TBoxVertexInstance)-1] of TBoxVertexInstance;

//--------------------------------------------------------------------------------------
//This VB holds the positions for copies of the basic box within the pile of boxes.
//The positions are expressed as bytes in a DWORD:
//  byte 0: x position
//  byte 1: y position
//  byte 3: height of box
//  byte 4: azimuthal rotation of box
//This will be stream 1
var
  g_pVBInstanceData: IDirect3DVertexBuffer9;

//Here is the format of the box positions within the pile:
type
  PBoxInstanceDataPos = ^TBoxInstanceDataPos;
  TBoxInstanceDataPos = packed record
    color: TD3DColor;
    x: Byte;
    y: Byte;
    z: Byte;
    rotation: Byte;
  end;


//--------------------------------------------------------------------------------------
var
  // Vertex Declaration for Hardware Instancing
  g_pVertexDeclHardware: IDirect3DVertexDeclaration9;

  g_VertexElemHardware: array[0..5] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0;   _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITION; UsageIndex: 0),
    (Stream: 0; Offset: 3*4; _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_NORMAL;   UsageIndex: 0),
    (Stream: 0; Offset: 6*4; _Type: D3DDECLTYPE_FLOAT2; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TEXCOORD; UsageIndex: 0),
    (Stream: 1; Offset: 0; _Type: D3DDECLTYPE_D3DCOLOR; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_COLOR;    UsageIndex: 0),
    (Stream: 1; Offset: 4; _Type: D3DDECLTYPE_D3DCOLOR; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_COLOR;    UsageIndex: 1),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );

  // Vertex Declaration for Shader Instancing
  g_pVertexDeclShader: IDirect3DVertexDeclaration9;

  g_VertexElemShader: array[0..4] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0;   _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITION; UsageIndex: 0),
    (Stream: 0; Offset: 3*4; _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_NORMAL;   UsageIndex: 0),
    (Stream: 0; Offset: 6*4; _Type: D3DDECLTYPE_FLOAT2; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TEXCOORD; UsageIndex: 0),
    (Stream: 0; Offset: 8*4; _Type: D3DDECLTYPE_FLOAT1; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TEXCOORD; UsageIndex: 1),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );

  // Vertex Declaration for Constants Instancing
  g_pVertexDeclConstants: IDirect3DVertexDeclaration9;

  g_VertexElemConstants: array[0..3] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0;   _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITION; UsageIndex: 0),
    (Stream: 0; Offset: 3*4; _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_NORMAL;   UsageIndex: 0),
    (Stream: 0; Offset: 6*4; _Type: D3DDECLTYPE_FLOAT2; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TEXCOORD; UsageIndex: 0),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_NUMBERBOXES_STATIC  = 5;
  IDC_NUMBERBOXES_SLIDER  = 6;
  IDC_RENDERMETHOD_LIST   = 7;
  IDC_BIND_CPU_STATIC     = 8;
  IDC_BIND_CPU_SLIDER     = 9;
  IDC_STATIC              = 10;
  IDC_CPUUSAGE_STATIC     = 11;
  IDC_TOGGLEUI            = 12;


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
function OnCreateBuffers(const pd3dDevice: IDirect3DDevice9): HRESULT;
procedure OnDestroyBuffers;

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;

implementation


//--------------------------------------------------------------------------------------
// Initialize the app 
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  iY: Integer;
  szMessage: WideString;
begin
  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_SampleUI.Init(g_DialogResourceManager);
  g_SampleUI2.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent);
  iY := 10;    g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 35, iY, 125, 22, VK_F2);
  Inc(iY, 24); g_HUD.AddButton(IDC_TOGGLEUI, 'Toggle UI (U)', 35, iY, 125, 22);

  g_SampleUI.SetCallback(OnGUIEvent);
  g_SampleUI2.SetCallback(OnGUIEvent);

  iY := 24;

  szMessage := WideFormat('# Boxes: %d', [g_NumBoxes]);
  Inc(iY, 24); g_SampleUI.AddStatic(IDC_NUMBERBOXES_STATIC, PWideChar(szMessage), 0, iY, 200, 22);
  Inc(iY, 24); g_SampleUI.AddSlider(IDC_NUMBERBOXES_SLIDER, 50, iY, 100, 22, 1, g_nMaxBoxes, g_NumBoxes);

  Inc(iY, 24);
  szMessage := 'Goal: 0ms/frame';
  Inc(iY, 12); g_SampleUI.AddStatic(IDC_BIND_CPU_STATIC, PWideChar(szMessage), 0, iY, 200, 22 );
  szMessage := 'Remaining for logic: 0';
  Inc(iY, 18); g_SampleUI.AddStatic(IDC_CPUUSAGE_STATIC, PWideChar(szMessage), 0, iY, 200, 22 );
  Inc(iY, 24); g_SampleUI.AddSlider(IDC_BIND_CPU_SLIDER, 50, iY, 100, 22, 0, 166, 0 );


  szMessage := 'If rendering takes less'#10 +
               'time than goal, then remaining'#10 +
               'time is spent to represent'#10 +
               'game logic. More time'#10 +
               'remaining means technique'#10 +
               'takes less CPU time';
  Inc(iY, 12*3); g_SampleUI.AddStatic(IDC_STATIC, PWideChar(szMessage), 10, iY, 170, 100);

  g_SampleUI2.AddComboBox(IDC_RENDERMETHOD_LIST, 0, 0, 166, 22);
  g_SampleUI2.GetComboBox(IDC_RENDERMETHOD_LIST).SetDropHeight( 12*4);
  g_SampleUI2.GetComboBox(IDC_RENDERMETHOD_LIST).AddItem('Hardware Instancing', nil);
  g_SampleUI2.GetComboBox(IDC_RENDERMETHOD_LIST).AddItem('Shader Instancing', nil);
  g_SampleUI2.GetComboBox(IDC_RENDERMETHOD_LIST).AddItem('Constants Instancing', nil);
  g_SampleUI2.GetComboBox(IDC_RENDERMETHOD_LIST).AddItem('Stream Instancing', nil);
  g_SampleUI2.GetComboBox(IDC_RENDERMETHOD_LIST).SetSelectedByIndex( g_iRenderTechnique);

  g_SampleUI.EnableKeyboardInput(True);
  g_SampleUI.FocusDefaultControl;
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

  // Needs PS 2.0 support
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2,0)) then Exit;

  // Needs to be DDI9 (support vertex buffer offset)
  if ((pCaps.DevCaps2 and D3DDEVCAPS2_STREAMOFFSET) = 0) then Exit;

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
    BehaviorFlags := BehaviorFlags and not D3DCREATE_MIXED_VERTEXPROCESSING;
    BehaviorFlags := BehaviorFlags and not D3DCREATE_PUREDEVICE;
    BehaviorFlags := BehaviorFlags or D3DCREATE_SOFTWARE_VERTEXPROCESSING;
  end;
{$ENDIF}
{$IFDEF DEBUG_PS}
  pDeviceSettings.DeviceType := D3DDEVTYPE_REF;
{$ENDIF}

  if not pDeviceSettings.pp.Windowed
  then pDeviceSettings.pp.SwapEffect := D3DSWAPEFFECT_FLIP;

  // For the first device created if its a REF device, optionally display a warning dialog box
  if s_bFirstTime then
  begin
    s_bFirstTime := False;
    if (pDeviceSettings.DeviceType = D3DDEVTYPE_REF) then DXUTDisplaySwitchingToREFWarning;
  end;

  Result:= True;
end;


//--------------------------------------------------------------------------------------
// Helper routine to fill faces of a cube
//--------------------------------------------------------------------------------------
procedure FillFace(
    pVertsP: PBoxVertex;
    pIndicesP: PWord;
    iFace: Integer;
    const vCenter: TD3DXVector3;
    const vNormal: TD3DXVector3;
    const vUp: TD3DXVector3);
var
  vRight: TD3DXVector3;
  pVerts: PBoxVertexArray;
  pIndices: PWordArray;
  v: TD3DXVector3;
  i: Integer;
begin
  D3DXVec3Cross(vRight, vNormal, vUp);
  pIndices:= PWordArray(pIndicesP);
  pVerts:= PBoxVertexArray(pVertsP);

  pIndices[ iFace * 6 + 0 ] := iFace * 4 + 0;
  pIndices[ iFace * 6 + 1 ] := iFace * 4 + 1;
  pIndices[ iFace * 6 + 2 ] := iFace * 4 + 2;
  pIndices[ iFace * 6 + 3 ] := iFace * 4 + 3;
  pIndices[ iFace * 6 + 4 ] := iFace * 4 + 2;
  pIndices[ iFace * 6 + 5 ] := iFace * 4 + 1;

{  pVerts[ iFace * 4 + 0 ].pos := vCenter + vRight + vUp;
  pVerts[ iFace * 4 + 1 ].pos := vCenter + vRight - vUp;
  pVerts[ iFace * 4 + 2 ].pos := vCenter - vRight + vUp;
  pVerts[ iFace * 4 + 3 ].pos := vCenter - vRight - vUp; }

  D3DXVec3Add(v, D3DXVec3Add(v, vCenter, vRight)^, vUp);
  pVerts[ iFace * 4 + 0 ].pos := v; // vCenter + vRight + vUp;
  D3DXVec3Subtract(v, D3DXVec3Add(v, vCenter, vRight)^, vUp);
  pVerts[ iFace * 4 + 1 ].pos := v; // vCenter + vRight - vUp;
  D3DXVec3Add(v, D3DXVec3Subtract(v, vCenter, vRight)^, vUp);
  pVerts[ iFace * 4 + 2 ].pos := v; // vCenter - vRight + vUp;
  D3DXVec3Subtract(v, D3DXVec3Subtract(v, vCenter, vRight)^, vUp);
  pVerts[ iFace * 4 + 3 ].pos := v; // vCenter - vRight - vUp;

  for i := 0 to 3 do
  begin
    pVerts[ iFace * 4 + i ].u := ((i div 2) and 1) * 1.0;
    pVerts[ iFace * 4 + i ].v := ((i)       and 1) * 1.0;
    pVerts[ iFace * 4 + i ].norm := vNormal;
  end;
end;


//--------------------------------------------------------------------------------------
// Helper routine to fill faces of a cube + instance data
//--------------------------------------------------------------------------------------
procedure FillFaceInstance(
    pVertsP: PBoxVertexInstance;
    pIndicesP: PWord;
    iFace: Integer;
    const vCenter: TD3DXVector3;
    const vNormal: TD3DXVector3;
    const vUp: TD3DXVector3;
    iInstanceIndex: Word);
var
  vRight: TD3DXVector3;
  offsetIndex: Word;  // offset from the beginning of the index array
  offsetVertex: Word; // offset from the beginning of the vertex array
  pVerts: PBoxVertexInstanceArray;
  pIndices: PWordArray;
  v: TD3DXVector3;
  i: Integer;
begin
  D3DXVec3Cross(vRight, vNormal, vUp);
  pVerts:= PBoxVertexInstanceArray(pVertsP);
  pIndices:= PWordArray(pIndicesP);

  offsetIndex := iInstanceIndex * 6 * 2 * 3;  // offset from the beginning of the index array
  offsetVertex := iInstanceIndex * 4 * 6;     // offset from the beginning of the vertex array

  pIndices[ offsetIndex + iFace * 6 + 0 ] := offsetVertex + iFace * 4 + 0;
  pIndices[ offsetIndex + iFace * 6 + 1 ] := offsetVertex + iFace * 4 + 1;
  pIndices[ offsetIndex + iFace * 6 + 2 ] := offsetVertex + iFace * 4 + 2;
  pIndices[ offsetIndex + iFace * 6 + 3 ] := offsetVertex + iFace * 4 + 3;
  pIndices[ offsetIndex + iFace * 6 + 4 ] := offsetVertex + iFace * 4 + 2;
  pIndices[ offsetIndex + iFace * 6 + 5 ] := offsetVertex + iFace * 4 + 1;

{  pVerts[ offsetVertex + iFace * 4 + 0 ].pos := vCenter + vRight + vUp;
  pVerts[ offsetVertex + iFace * 4 + 1 ].pos := vCenter + vRight - vUp;
  pVerts[ offsetVertex + iFace * 4 + 2 ].pos := vCenter - vRight + vUp;
  pVerts[ offsetVertex + iFace * 4 + 3 ].pos := vCenter - vRight - vUp; }

  D3DXVec3Add(v, D3DXVec3Add(v, vCenter, vRight)^, vUp);
  pVerts[ offsetVertex + iFace * 4 + 0 ].pos := v; // vCenter + vRight + vUp;
  D3DXVec3Subtract(v, D3DXVec3Add(v, vCenter, vRight)^, vUp);
  pVerts[ offsetVertex + iFace * 4 + 1 ].pos := v; // vCenter + vRight - vUp;
  D3DXVec3Add(v, D3DXVec3Subtract(v, vCenter, vRight)^, vUp);
  pVerts[ offsetVertex + iFace * 4 + 2 ].pos := v; // vCenter - vRight + vUp;
  D3DXVec3Subtract(v, D3DXVec3Subtract(v, vCenter, vRight)^, vUp);
  pVerts[ offsetVertex + iFace * 4 + 3 ].pos := v; // vCenter - vRight - vUp;

  for i := 0 to 3 do
  begin
    pVerts[ offsetVertex + iFace * 4 + i ].boxInstance := iInstanceIndex;
    pVerts[ offsetVertex + iFace * 4 + i ].u := ( ( i div 2 ) and 1 ) * 1.0;
    pVerts[ offsetVertex + iFace * 4 + i ].v := ( ( i       ) and 1 ) * 1.0;
    pVerts[ offsetVertex + iFace * 4 + i ].norm := vNormal;
  end;
end;


//--------------------------------------------------------------------------------------
// Create the vertex and index buffers, based on the selected instancing method
// called from onCreateDevice or whenever user changes parameters or rendering method
//--------------------------------------------------------------------------------------
function OnCreateBuffers(const pd3dDevice: IDirect3DDevice9): HRESULT;
var
  pVertsI: PBoxVertexInstance;
  pIndices: PWord;
  iInstance: Word;
  pVerts: PBoxVertex;
  pIPos: PBoxInstanceDataPos;
  nRemainingBoxes: Integer;
  iY, iZ, iX: Byte;
  instanceBox: TBoxInstanceDataPos;
begin
  if g_iRenderTechnique in [0, 3] then
  begin
    g_HandleTechnique := g_pEffect.GetTechniqueByName('THW_Instancing');

    // Create the vertex declaration
    Result:= pd3dDevice.CreateVertexDeclaration(@g_VertexElemHardware, g_pVertexDeclHardware);
    if V_Failed(Result) then Exit;
  end;

  if (g_iRenderTechnique = 1) then
  begin
    g_HandleTechnique := g_pEffect.GetTechniqueByName('TShader_Instancing');
    g_HandleBoxInstance_Position := g_pEffect.GetParameterBySemantic(nil, 'BOXINSTANCEARRAY_POSITION');
    g_HandleBoxInstance_Color := g_pEffect.GetParameterBySemantic(nil, 'BOXINSTANCEARRAY_COLOR');

    // First create the vertex declaration we need
    Result:= pd3dDevice.CreateVertexDeclaration(@g_VertexElemShader, g_pVertexDeclShader);
    if V_Failed(Result) then Exit;

    // Build a VB to hold the position data. Four vertices on six faces of the box
    // Create g_nNumBatchInstance copies
    Result:= pd3dDevice.CreateVertexBuffer(g_nNumBatchInstance * 4 * 6 * SizeOf(TBoxVertexInstance), 0, 0, D3DPOOL_MANAGED, g_pVBBox, nil);
    if V_Failed(Result) then Exit;

    // And an IB to go with it. We will be rendering
    // a list of independent tris, and each box face has two tris, so the box will have
    // 6 * 2 * 3 indices
    Result:= pd3dDevice.CreateIndexBuffer(g_nNumBatchInstance * (6 * 2 * 3) * SizeOf(Word), 0, D3DFMT_INDEX16, D3DPOOL_MANAGED, g_pIBBox, nil);
    if V_Failed(Result) then Exit;

    // Now, lock and fill the model VB and IB
    Result := g_pVBBox.Lock(0, 0, Pointer(pVertsI), 0);

    if SUCCEEDED(Result) then
    begin
      Result := g_pIBBox.Lock(0, 0, Pointer(pIndices), 0);

      if SUCCEEDED(Result) then
      begin
        for iInstance := 0 to g_nNumBatchInstance-1 do
        begin
          FillFaceInstance(pVertsI, pIndices, 0,
              D3DXVector3(0.0, 0.0,-1.0),
              D3DXVector3(0.0, 0.0,-1.0),
              D3DXVector3(0.0, 1.0, 0.0),
              iInstance);

          FillFaceInstance(pVertsI, pIndices, 1,
              D3DXVector3(0.0, 0.0, 1.0),
              D3DXVector3(0.0, 0.0, 1.0),
              D3DXVector3(0.0, 1.0, 0.0),
              iInstance);

          FillFaceInstance(pVertsI, pIndices,2,
              D3DXVector3(1.0, 0.0, 0.0),
              D3DXVector3(1.0, 0.0, 0.0),
              D3DXVector3(0.0, 1.0, 0.0),
              iInstance);

          FillFaceInstance(pVertsI, pIndices,3,
              D3DXVECTOR3(-1.0, 0.0, 0.0),
              D3DXVECTOR3(-1.0, 0.0, 0.0),
              D3DXVector3(0.0, 1.0, 0.0),
              iInstance);

          FillFaceInstance(pVertsI, pIndices,4,
              D3DXVector3(0.0, 1.0, 0.0),
              D3DXVector3(0.0, 1.0, 0.0),
              D3DXVector3(1.0, 0.0, 0.0),
              iInstance);

          FillFaceInstance(pVertsI, pIndices,5,
              D3DXVector3(0.0,-1.0, 0.0),
              D3DXVector3(0.0,-1.0, 0.0),
              D3DXVector3(1.0, 0.0, 0.0),
              iInstance);
        end;

        g_pIBBox.Unlock;
      end else
      begin
        DXUT_ERR('Could not lock box model IB', Result);
      end;
      g_pVBBox.Unlock;
    end else
    begin
      DXUT_ERR('Could not lock box model VB', Result);
    end;
  end;

  if (g_iRenderTechnique = 2) then
  begin
    g_HandleTechnique := g_pEffect.GetTechniqueByName('TConstants_Instancing');
    g_HandleBoxInstance_Position := g_pEffect.GetParameterBySemantic(nil, 'BOXINSTANCE_POSITION');
    g_HandleBoxInstance_Color := g_pEffect.GetParameterBySemantic(nil, 'BOXINSTANCE_COLOR');

    // Create the vertex declaration
    Result:= pd3dDevice.CreateVertexDeclaration(@g_VertexElemConstants, g_pVertexDeclConstants);
    if V_Failed(Result) then Exit;
  end;

  if (g_iRenderTechnique <> 1) then
  begin
    // Build a VB to hold the position data. Four vertices on six faces of the box
    Result:= pd3dDevice.CreateVertexBuffer(4 * 6 * SizeOf(TBoxVertex), 0, 0, D3DPOOL_MANAGED, g_pVBBox, nil);
    if V_Failed(Result) then Exit;

    // And an IB to go with it. We will be rendering
    // a list of independent tris, and each box face has two tris, so the box will have
    // 6 * 2 * 3 indices
    Result:= pd3dDevice.CreateIndexBuffer((6 * 2 * 3) * SizeOf(Word), 0, D3DFMT_INDEX16, D3DPOOL_MANAGED, g_pIBBox, nil);
    if V_Failed(Result) then Exit;

    // Now, lock and fill the model VB and IB:
    Result := g_pVBBox.Lock(0, 0, Pointer(pVerts), 0);

    if SUCCEEDED(Result) then
    begin
      Result := g_pIBBox.Lock(0, 0, Pointer(pIndices), 0);

      if SUCCEEDED(Result) then
      begin
        FillFace(pVerts, pIndices, 0,
            D3DXVector3(0.0, 0.0,-1.0),
            D3DXVector3(0.0, 0.0,-1.0),
            D3DXVector3(0.0, 1.0, 0.0));

        FillFace(pVerts, pIndices, 1,
            D3DXVector3(0.0, 0.0, 1.0),
            D3DXVector3(0.0, 0.0, 1.0),
            D3DXVector3(0.0, 1.0, 0.0));

        FillFace(pVerts, pIndices,2,
            D3DXVector3(1.0, 0.0, 0.0),
            D3DXVector3(1.0, 0.0, 0.0),
            D3DXVector3(0.0, 1.0, 0.0));

        FillFace(pVerts, pIndices,3,
            D3DXVECTOR3(-1.0, 0.0, 0.0),
            D3DXVECTOR3(-1.0, 0.0, 0.0),
            D3DXVector3(0.0, 1.0, 0.0));

        FillFace(pVerts, pIndices,4,
            D3DXVector3(0.0, 1.0, 0.0),
            D3DXVector3(0.0, 1.0, 0.0),
            D3DXVector3(1.0, 0.0, 0.0));

        FillFace(pVerts, pIndices,5,
            D3DXVector3(0.0,-1.0, 0.0),
            D3DXVector3(0.0,-1.0, 0.0),
            D3DXVector3(1.0, 0.0, 0.0));

        g_pIBBox.Unlock;
      end else
      begin
        DXUT_ERR('Could not lock box model IB', Result);
      end;
      g_pVBBox.Unlock;
    end else
    begin
      DXUT_ERR('Could not lock box model VB', Result);
    end;
  end;

  if g_iRenderTechnique in [0, 3] then
  begin
    // Create a  VB for the instancing data
    Result:= pd3dDevice.CreateVertexBuffer(g_NumBoxes * SizeOf(TBoxInstanceDataPos), 0, 0, D3DPOOL_MANAGED, g_pVBInstanceData, nil);
    if V_Failed(Result) then Exit;

    // Lock and fill the instancing buffer
    Result := g_pVBInstanceData.Lock(0, 0, Pointer(pIPos), 0);

    if SUCCEEDED(Result) then
    begin
      nRemainingBoxes := g_NumBoxes;
      for iY := 0 to 9 do
        for iZ := 0 to 9 do
          for iX := 0 to 9 do // && nRemainingBoxes > 0; iX++, nRemainingBoxes-- )
            if nRemainingBoxes > 0 then
            begin
              // Scaled so 1 box is "32" wide, the intra-pos range is 8 box widths.
              // The positins are scaled and biased.
              // The rotations are not
              instanceBox.color := D3DCOLOR_ARGB($ff,
                                                 $7f + $40 * ((g_NumBoxes - nRemainingBoxes + iX) mod 3),
                                                 $7f + $40 * ((g_NumBoxes - nRemainingBoxes+iZ+1) mod 3),
                                                 $7f + $40 * ((g_NumBoxes - nRemainingBoxes+iY+2) mod 3));
              instanceBox.x := iZ * 24;
              instanceBox.z := iX * 24;
              instanceBox.y := iY * 24;
              instanceBox.rotation := (Word(iX) + iZ + iY) * 24 div 3;
              pIPos^ := instanceBox; Inc(pIPos);
              Dec(nRemainingBoxes);
            end;
      g_pVBInstanceData.Unlock;
    end else
    begin
      DXUT_ERR('Could not lock box intra-pile-position VB', Result);
    end;
  end;

  if g_iRenderTechnique in [1, 2] then
  begin
    // Fill the instancing constants buffer
    nRemainingBoxes := g_NumBoxes;
    for iY := 0 to 9 do
      for iZ := 0 to 9 do
        for iX := 0 to 9 do // nRemainingBoxes > 0; iX++, nRemainingBoxes-- )
          if nRemainingBoxes > 0 then
          begin
            // Scaled so 1 box is "32" wide, the intra-pos range is 8 box widths.
            // The positins are scaled and biased.
            // The rotations are not
            g_vBoxInstance_Color[g_NumBoxes - nRemainingBoxes] := D3DXColorFromDWord(
              D3DCOLOR_ARGB($ff,
                            $7f + $40 * ((g_NumBoxes - nRemainingBoxes + iX) mod 3),
                            $7f + $40 * ((g_NumBoxes - nRemainingBoxes+iZ+1) mod 3),
                            $7f + $40 * ((g_NumBoxes - nRemainingBoxes+iY+2) mod 3)));
            g_vBoxInstance_Position[g_NumBoxes - nRemainingBoxes].x := iX * 24 / 255.0;
            g_vBoxInstance_Position[g_NumBoxes - nRemainingBoxes].z := iZ * 24 / 255.0;
            g_vBoxInstance_Position[g_NumBoxes - nRemainingBoxes].y := iY * 24 / 255.0;
            g_vBoxInstance_Position[g_NumBoxes - nRemainingBoxes].w := (Word(iX) + iZ + iY) * 8 / 255.0;
            Dec(nRemainingBoxes);
          end;
  end;

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// Release the vertex and index buffers, based on the selected instancing method
// called from onDestroyDevice or whenever user changes parameters or rendering method
//--------------------------------------------------------------------------------------
procedure OnDestroyBuffers;
begin
  SAFE_RELEASE(g_pVBBox);
  SAFE_RELEASE(g_pIBBox);
  SAFE_RELEASE(g_pVBInstanceData);
  SAFE_RELEASE(g_pVertexDeclHardware);
  SAFE_RELEASE(g_pVertexDeclShader);
  SAFE_RELEASE(g_pVertexDeclConstants);
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
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'Instancing.fx');
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // why the .fx file failed to compile
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags,
                                     nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  g_HandleWorld := g_pEffect.GetParameterBySemantic(nil, 'WORLD');
  g_HandleView := g_pEffect.GetParameterBySemantic(nil, 'VIEW');
  g_HandleProjection := g_pEffect.GetParameterBySemantic(nil, 'PROJECTION');
  g_HandleTexture := g_pEffect.GetParameterBySemantic(nil, 'TEXTURE');

  // Setup the camera's view parameters
  vecEye := D3DXVector3(-24.0, 36.0, -36.0);
  vecAt := D3DXVector3(0.0, 0.0, 0.0);
  g_Camera.SetViewParams(vecEye, vecAt);

  // create vertex, index buffers and vertex declaration
  Result:= OnCreateBuffers(pd3dDevice);
  if V_Failed(Result) then Exit;

  // Load the environment texture
  Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, 'Misc\env2.bmp');
  if FAILED(Result) then
  begin
    Result:= DXTRACE_ERR('DXUTFindDXSDKMediaFile', Result);
    Exit;
  end;
  Result := D3DXCreateTextureFromFileW(pd3dDevice, str, g_pBoxTexture);
  if FAILED(Result) then 
  begin
    Result:= DXTRACE_ERR('D3DXCreateTextureFromFile', Result);
    Exit;
  end;

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

  // Setup the camera's projection parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI / 3, fAspectRatio, 0.1, 1000.0);
  g_Camera.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);

  // Set the camera speed
  g_Camera.SetScalers(0.01, 10.0);

  // Constrain the camera to movement within the horizontal plane
  g_Camera.SetEnableYAxisMovement(False);
  g_Camera.SetEnablePositionMovement(True);

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation(pBackBufferSurfaceDesc.Width-170, pBackBufferSurfaceDesc.Height-400);
  g_SampleUI.SetSize(170, 400);
  g_SampleUI2.SetLocation(0, 100);
  g_SampleUI2.SetSize(200, 100);

  g_fLastTime := DXUTGetGlobalTimer.GetTime;

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
  szTmp, szMessage: WideString;
  fStartTime: Double;
  fCurTime: Double;
  fStopTime: Double;
  fTmp: Double;
  fCPUUsage: Double;
begin
  // Burn CPU time
  fStartTime := DXUTGetGlobalTimer.GetTime;
  fCurTime := fStartTime;
  fStopTime := g_fLastTime + g_fBurnAmount;

  while (fCurTime < fStopTime) do
  begin
    fCurTime := DXUTGetGlobalTimer.GetTime;
    fTmp := fStartTime / g_fLastTime * 100.0;
    szTmp:= WideFormat('Test %d', [Trunc(fTmp + 0.5)]);
  end;

  if (fCurTime - g_fLastTime > 0.00001)
  then fCPUUsage := (fCurTime - fStartTime) / (fCurTime - g_fLastTime) * 100.0
  else fCPUUsage := 3.402823466e+38{FLT_MAX};

  g_fLastTime := DXUTGetGlobalTimer.GetTime;
  szMessage := WideFormat('Remaining for logic: %d%%', [Trunc(fCPUUsage + 0.5)]);

  // don't update the message every single time
  if (0 = g_iUpdateCPUUsageMessage)
    then g_SampleUI.GetStatic(IDC_CPUUSAGE_STATIC).Text := PWideChar(szMessage);
  g_iUpdateCPUUsageMessage := (g_iUpdateCPUUsageMessage + 1) mod 100;

  // Update the camera's position based on user input
  g_Camera.FrameMove(fElapsedTime);
end;


//--------------------------------------------------------------------------------------
// This callback function is called by OnFrameRender
// It performs HW instancing
//--------------------------------------------------------------------------------------
procedure OnRenderHWInstancing(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single);
var
  iPass: Integer;
  cPasses: LongWord;
begin
  V(pd3dDevice.SetVertexDeclaration(g_pVertexDeclHardware));

  // Stream zero is our model, and its frequency is how we communicate the number of instances required,
  // which in this case is the total number of boxes
  V(pd3dDevice.SetStreamSource(0, g_pVBBox, 0, SizeOf(TBoxVertex)));
  V(pd3dDevice.SetStreamSourceFreq(0, D3DSTREAMSOURCE_INDEXEDDATA or Cardinal(g_NumBoxes)));

  // Stream one is the instancing buffer, so this advances to the next value
  // after each box instance has been drawn, so the divider is 1.
  V(pd3dDevice.SetStreamSource(1, g_pVBInstanceData, 0, SizeOf(TBoxInstanceDataPos)));
  V(pd3dDevice.SetStreamSourceFreq(1, D3DSTREAMSOURCE_INSTANCEDATA or 1));

  V(pd3dDevice.SetIndices(g_pIBBox));

  // Render the scene with this technique
  // as defined in the .fx file
  V(g_pEffect.SetTechnique(g_HandleTechnique));

  V(g_pEffect._Begin(@cPasses, 0));
  for iPass := 0 to cPasses - 1 do
  begin
    V(g_pEffect.BeginPass(iPass));

    // Render the boxes with the applied technique
    V(g_pEffect.SetTexture(g_HandleTexture, g_pBoxTexture));

    // The effect interface queues up the changes and performs them
    // with the CommitChanges call. You do not need to call CommitChanges if
    // you are not setting any parameters between the BeginPass and EndPass.
    V(g_pEffect.CommitChanges);

    V(pd3dDevice.DrawIndexedPrimitive(D3DPT_TRIANGLELIST, 0, 0, 4 * 6, 0, 6 * 2));

    V(g_pEffect.EndPass);
  end;
  V(g_pEffect._End);

  V(pd3dDevice.SetStreamSourceFreq(0, 1));
  V(pd3dDevice.SetStreamSourceFreq(1, 1));
end;


//--------------------------------------------------------------------------------------
// This callback function is called by OnFrameRender
// It performs Shader instancing
//--------------------------------------------------------------------------------------
procedure OnRenderShaderInstancing(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single);
var
  nRenderBoxes: Integer;
  iPass: Integer;
  cPasses: LongWord;
  nRemainingBoxes: Integer;
begin
  V(pd3dDevice.SetVertexDeclaration(g_pVertexDeclShader));

  // Stream zero is our model
  V(pd3dDevice.SetStreamSource(0, g_pVBBox, 0, SizeOf(TBoxVertexInstance)));
  V(pd3dDevice.SetIndices(g_pIBBox));

  // Render the scene with this technique
  // as defined in the .fx file
  V(g_pEffect.SetTechnique(g_HandleTechnique));

  V(g_pEffect._Begin(@cPasses, 0));
  for iPass := 0 to cPasses - 1 do
  begin
    V(g_pEffect.BeginPass(iPass));

    // Render the boxes with the applied technique
    V(g_pEffect.SetTexture(g_HandleTexture, g_pBoxTexture ));

    nRemainingBoxes := g_NumBoxes;
    while (nRemainingBoxes > 0) do
    begin
      // determine how many instances are in this batch (up to g_nNumBatchInstance)
      nRenderBoxes := Min(nRemainingBoxes, g_nNumBatchInstance);

      // set the box instancing array
      V(g_pEffect.SetVectorArray(g_HandleBoxInstance_Position, @g_vBoxInstance_Position[g_NumBoxes - nRemainingBoxes], nRenderBoxes));
      V(g_pEffect.SetVectorArray(g_HandleBoxInstance_Color, PD3DXVector4(@g_vBoxInstance_Color[g_NumBoxes - nRemainingBoxes]), nRenderBoxes));

      // The effect interface queues up the changes and performs them
      // with the CommitChanges call. You do not need to call CommitChanges if
      // you are not setting any parameters between the BeginPass and EndPass.
      V(g_pEffect.CommitChanges);

      V(pd3dDevice.DrawIndexedPrimitive(D3DPT_TRIANGLELIST, 0, 0, nRenderBoxes * 4 * 6, 0, nRenderBoxes * 6 * 2));

      // subtract the rendered boxes from the remaining boxes
      Dec(nRemainingBoxes, nRenderBoxes);
    end;

    V(g_pEffect.EndPass);
  end;
  V(g_pEffect._End);
end;


//--------------------------------------------------------------------------------------
// This callback function is called by OnFrameRender
// It performs Constants instancing
//--------------------------------------------------------------------------------------
procedure OnRenderConstantsInstancing(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single);
var
  iPass: Integer;
  cPasses: LongWord;
  nRemainingBoxes: Integer;
begin
  V(pd3dDevice.SetVertexDeclaration( g_pVertexDeclConstants));

  // Stream zero is our model
  V(pd3dDevice.SetStreamSource(0, g_pVBBox, 0, SizeOf(TBoxVertex)));
  V(pd3dDevice.SetIndices(g_pIBBox));

  // Render the scene with this technique
  // as defined in the .fx file
  V(g_pEffect.SetTechnique(g_HandleTechnique));

  V(g_pEffect._Begin(@cPasses, 0));
  for iPass := 0 to cPasses - 1 do
  begin
    V(g_pEffect.BeginPass(iPass));

    // Render the boxes with the applied technique
    V(g_pEffect.SetTexture(g_HandleTexture, g_pBoxTexture));

    for nRemainingBoxes := 0 to g_NumBoxes - 1 do
    begin
      // set the box instancing array
      V(g_pEffect.SetVector(g_HandleBoxInstance_Position, g_vBoxInstance_Position[nRemainingBoxes]));
      V(g_pEffect.SetVector(g_HandleBoxInstance_Color, PD3DXVector4(@g_vBoxInstance_Color[nRemainingBoxes])^));

      // The effect interface queues up the changes and performs them
      // with the CommitChanges call. You do not need to call CommitChanges if
      // you are not setting any parameters between the BeginPass and EndPass.
      V(g_pEffect.CommitChanges);

      V(pd3dDevice.DrawIndexedPrimitive(D3DPT_TRIANGLELIST, 0, 0, 4 * 6, 0, 6 * 2));
    end;

    V(g_pEffect.EndPass);
  end;
  V(g_pEffect._End);
end;


//--------------------------------------------------------------------------------------
// This callback function is called by OnFrameRender
// It performs Stream instancing
//--------------------------------------------------------------------------------------
procedure OnRenderStreamInstancing(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single);
var
  iPass: Integer;
  cPasses: LongWord;
  nRemainingBoxes: Integer;
begin
  V(pd3dDevice.SetVertexDeclaration(g_pVertexDeclHardware));

  // Stream zero is our model
  V(pd3dDevice.SetStreamSource(0, g_pVBBox, 0, SizeOf(TBoxVertex)));

  V(pd3dDevice.SetIndices(g_pIBBox));

  // Render the scene with this technique
  // as defined in the .fx file
  V(g_pEffect.SetTechnique(g_HandleTechnique));

  V(g_pEffect._Begin(@cPasses, 0));
  for iPass := 0 to cPasses - 1 do
  begin
    V(g_pEffect.BeginPass(iPass));

    // Render the boxes with the applied technique
    V(g_pEffect.SetTexture(g_HandleTexture, g_pBoxTexture));

    // The effect interface queues up the changes and performs them
    // with the CommitChanges call. You do not need to call CommitChanges if
    // you are not setting any parameters between the BeginPass and EndPass.
    V(g_pEffect.CommitChanges);

    for nRemainingBoxes := 0 to g_NumBoxes - 1 do
    begin
      // Stream one is the instancing buffer
      V(pd3dDevice.SetStreamSource(1, g_pVBInstanceData, nRemainingBoxes * SizeOf(TBoxInstanceDataPos), 0));

      V(pd3dDevice.DrawIndexedPrimitive(D3DPT_TRIANGLELIST, 0, 0, 4 * 6, 0, 6 * 2));
    end;

    V(g_pEffect.EndPass);
  end;
  V(g_pEffect._End);
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
    mView := g_Camera.GetViewMatrix^;

    // Update the effect's variables
    V(g_pEffect.SetMatrix(g_HandleWorld, mWorld));
    V(g_pEffect.SetMatrix(g_HandleView, mView));
    V(g_pEffect.SetMatrix(g_HandleProjection, mProj));

    case g_iRenderTechnique of
      0: if DXUTGetDeviceCaps.VertexShaderVersion >= D3DVS_VERSION(3,0)
         then OnRenderHWInstancing(pd3dDevice, fTime, fElapsedTime);
      1: OnRenderShaderInstancing(pd3dDevice, fTime, fElapsedTime);
      2: OnRenderConstantsInstancing(pd3dDevice, fTime, fElapsedTime);
      3: OnRenderStreamInstancing(pd3dDevice, fTime, fElapsedTime);
    end;

    if (g_nShowUI > 0) then RenderText;
    if (g_nShowUI > 1) then
    begin
      V(g_HUD.OnRender(fElapsedTime));
      V(g_SampleUI.OnRender(fElapsedTime));
      V(g_SampleUI2.OnRender(fElapsedTime));
    end;

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
  txtHelper := CDXUTTextHelper.Create(g_pFont, g_pTextSprite, 15);

  // Output statistics
  txtHelper._Begin;
  txtHelper.SetInsertionPos(5, 5);
  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));
  txtHelper.DrawTextLine(DXUTGetFrameStats(True)); // Show FPS
  txtHelper.DrawTextLine(DXUTGetDeviceStats);
  if (g_nShowUI < 2) then txtHelper.DrawTextLine('Press ''U'' to toggle UI');

  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
  if g_bRuntimeDebug then txtHelper.DrawTextLine('WARNING (perf): DEBUG D3D runtime detected!');
  if g_bAppIsDebug   then txtHelper.DrawTextLine('WARNING (perf): DEBUG application build detected!');
  if (g_iRenderTechnique = 0) and (DXUTGetDeviceCaps.VertexShaderVersion < D3DVS_VERSION(3,0)) then
  begin
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.0, 0.0, 1.0));
    txtHelper.DrawTextLine('ERROR: Hardware instancing is not supported on non vs_3_0 HW');
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

  if (g_nShowUI > 1) then
  begin
    // Give the dialogs a chance to handle the message first
    pbNoFurtherProcessing := g_SampleUI.MsgProc(hWnd, uMsg, wParam, lParam);
    if pbNoFurtherProcessing then Exit;
    pbNoFurtherProcessing := g_HUD.MsgProc(hWnd, uMsg, wParam, lParam);
    if pbNoFurtherProcessing then Exit;
    pbNoFurtherProcessing := g_SampleUI2.MsgProc(hWnd, uMsg, wParam, lParam);
    if pbNoFurtherProcessing then Exit;
  end;

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
      Ord('U'):
      begin
        Dec(g_nShowUI);
        if (g_nShowUI < 0) then g_nShowUI := 2;
      end;
    end;
  end;
end;


//--------------------------------------------------------------------------------------
// Handles the GUI events
//--------------------------------------------------------------------------------------
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
var
  szMessage: WideString;
  pCBItem: PDXUTComboBoxItem;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF: DXUTToggleREF;
    IDC_CHANGEDEVICE: with g_SettingsDlg do Active := not Active;
    IDC_TOGGLEUI: KeyboardProc(Ord('U'), True, False, nil);
    IDC_NUMBERBOXES_SLIDER:
    begin
      g_NumBoxes := g_SampleUI.GetSlider(IDC_NUMBERBOXES_SLIDER).Value;
      szMessage:= WideFormat('# Boxes: %d', [g_NumBoxes]);
      g_SampleUI.GetStatic(IDC_NUMBERBOXES_STATIC).Text := PWideChar(szMessage);
      OnDestroyBuffers;
      OnCreateBuffers(DXUTGetD3DDevice);
    end;
    IDC_BIND_CPU_SLIDER:
    begin
      g_fBurnAmount := 0.0001 * g_SampleUI.GetSlider(IDC_BIND_CPU_SLIDER).Value;
      // szMessage := WideFormat('Goal: %0.1fms/frame', [g_fBurnAmount * 1000.0]); // Delphi WideFormat bug
      szMessage := Format('Goal: %0.1fms/frame', [g_fBurnAmount * 1000.0]);
      g_SampleUI.GetStatic(IDC_BIND_CPU_STATIC).Text := PWideChar(szMessage);
    end;
    IDC_RENDERMETHOD_LIST:
    begin
      pCBItem := g_SampleUI2.GetComboBox(IDC_RENDERMETHOD_LIST).GetSelectedItem;

      if pCBItem.strText = 'Hardware Instancing'  then g_iRenderTechnique := 0 else
      if pCBItem.strText = 'Shader Instancing'    then g_iRenderTechnique := 1 else
      if pCBItem.strText = 'Constants Instancing' then g_iRenderTechnique := 2 else
      if pCBItem.strText = 'Stream Instancing'    then g_iRenderTechnique := 3
      else g_iRenderTechnique := Word(-1);

      // Note hardware instancing is not supported on non vs_3_0 HW
      // This sample allows it to be set, but displays an error to the user

      // recreate the buffers
      OnDestroyBuffers;
      OnCreateBuffers(DXUTGetD3DDevice);
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
  SAFE_RELEASE(g_pTextSprite);
  SAFE_RELEASE(g_pBoxTexture);

  // destroy vertex/index buffers, vertex declaration
  OnDestroyBuffers;
end;


procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera:= CModelViewerCamera.Create;  // A model viewing camera
  g_HUD:= CDXUTDialog.Create;            // dialog for standard controls
  g_SampleUI:= CDXUTDialog.Create;       // dialog for sample specific controls
  g_SampleUI2:= CDXUTDialog.Create;      // dialog for sample specific controls
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_Camera);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);
  FreeAndNil(g_SampleUI2);
end;

end.

