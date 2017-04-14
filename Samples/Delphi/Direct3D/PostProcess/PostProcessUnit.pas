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
 *  $Id: PostProcessUnit.pas,v 1.8 2007/02/05 22:21:11 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: PostProcess.cpp
//
// Starting point for new Direct3D applications
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit PostProcessUnit;

interface

uses
  Windows, Messages, SysUtils, Math, StrSafe, 
  DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTmesh, DXUTSettingsDlg;


const
  // NUM_PARAMS is the maximum number of changeable parameters supported
  // in an effect.
  NUM_PARAMS = 2;

  // RT_COUNT is the number of simultaneous render targets used in the sample.
  RT_COUNT = 3;

  // Name of the postprocess .fx files
  g_aszFxFile: array[0..16] of PWideChar =
  (
    'PP_ColorMonochrome.fx',
    'PP_ColorInverse.fx',
    'PP_ColorGBlurH.fx',
    'PP_ColorGBlurV.fx',
    'PP_ColorBloomH.fx',
    'PP_ColorBloomV.fx',
    'PP_ColorBrightPass.fx',
    'PP_ColorToneMap.fx',
    'PP_ColorEdgeDetect.fx',
    'PP_ColorDownFilter4.fx',
    'PP_ColorUpFilter4.fx',
    'PP_ColorCombine.fx',
    'PP_ColorCombine4.fx',
    'PP_NormalEdgeDetect.fx',
    'PP_DofCombine.fx',
    'PP_NormalMap.fx',
    'PP_PositionMap.fx'
  );

  // PPCOUNT is the number of postprocess effects supported
  PPCOUNT  = High(g_aszFxFile) + 1;


  // Description of each postprocess supported
  g_aszPpDesc: array[0..16] of PWideChar =
  (
    '[Color] Monochrome',
    '[Color] Inversion',
    '[Color] Gaussian Blur Horizonta',
    '[Color] Gaussian Blur Vertica',
    '[Color] Bloom Horizonta',
    '[Color] Bloom Vertica',
    '[Color] Bright Pass',
    '[Color] Tone Mapping',
    '[Color] Edge Detection',
    '[Color] Down Filter 4x',
    '[Color] Up Filter 4x',
    '[Color] Combine',
    '[Color] Combine 4x',
    '[Normal] Edge Detection',
    'DOF Combine',
    'Normal Map',
    'Position Map'
  );


type
  //--------------------------------------------------------------------------------------
  // This is the vertex format used for the meshes.
  TMeshVert = packed record
    x, y, z: Single;      // Position
    nx, ny, nz: Single;   // Normal
    tu, tv: Single;       // Texcoord
    // const static D3DVERTEXELEMENT9 Decl[4];
  end;

const
  TMeshVert_Decl: array[0..3] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0;  _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITION; UsageIndex: 0),
    (Stream: 0; Offset: 12; _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_NORMAL;   UsageIndex: 0),
    (Stream: 0; Offset: 24; _Type: D3DDECLTYPE_FLOAT2; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TEXCOORD; UsageIndex: 0),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );


type
  //--------------------------------------------------------------------------------------
  // This is the vertex format used for the skybox.
  TSkyboxVert = packed record
    x, y, z: Single;      // Position
    tex: TD3DXVector3;    // Texcoord
    // const static D3DVERTEXELEMENT9 Decl[3];
  end;

const
  TSkyboxVert_Decl: array[0..2] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0;  _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITION; UsageIndex: 0),
    (Stream: 0; Offset: 12; _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TEXCOORD; UsageIndex: 0),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );


type
  //--------------------------------------------------------------------------------------
  // This is the vertex format used with the quad during post-process.
  PppVert = ^TppVert;
  TppVert = packed record
    x, y, z, rhw: Single;
    tu, tv: Single;       // Texcoord for post-process source
    tu2, tv2: Single;     // Texcoord for the original scene
    // const static D3DVERTEXELEMENT9 Decl[4];
  end;

const
  // Vertex declaration for post-processing
  TppVert_Decl: array[0..3] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0;  _Type: D3DDECLTYPE_FLOAT4; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITIONT; UsageIndex: 0),
    (Stream: 0; Offset: 16; _Type: D3DDECLTYPE_FLOAT2; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TEXCOORD;  UsageIndex: 0),
    (Stream: 0; Offset: 24; _Type: D3DDECLTYPE_FLOAT2; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TEXCOORD;  UsageIndex: 1),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );

type  
  //--------------------------------------------------------------------------------------
  // struct CPostProcess
  // A struct that encapsulates aspects of a render target postprocess
  // technique.
  //--------------------------------------------------------------------------------------
  CPostProcess = class
  private
    m_pEffect: ID3DXEffect;                    // Effect object for this technique
    m_hTPostProcess: TD3DXHandle;              // PostProcess technique handle
    m_nRenderTarget: Integer;                  // Render target channel this PP outputs
    m_hTexSource: array[0..3] of TD3DXHandle;  // Handle to the post-process source textures
    m_hTexScene: array[0..3] of TD3DXHandle;   // Handle to the saved scene texture
    m_bWrite: array[0..3] of Boolean;          // Indicates whether the post-process technique
                                               //   outputs data for this render target.
    m_awszParamName: array[0..NUM_PARAMS-1, 0..MAX_PATH-1] of WideChar;  // Names of changeable parameters
    m_awszParamDesc: array[0..NUM_PARAMS-1, 0..MAX_PATH-1] of WideChar;  // Names of changeable parameters
    m_ahParam: array[0..NUM_PARAMS-1] of TD3DXHandle; // Handles to the changeable parameters
    m_anParamSize: array[0..NUM_PARAMS-1] of Integer; // Size of the parameter. Indicates
                                               // how many components of float4
                                               // are used.
    m_avParamDef: array[0..NUM_PARAMS-1] of TD3DXVector4; // Parameter default

  public
    // constructor Create; // ZEROing is done automatically in Delphi
    destructor Destroy; override; // ~CPostProcess() { Cleanup(); }
    function Init(const pDev: IDirect3DDevice9; dwShaderFlags: DWORD; wszName: PWideChar): HRESULT;
    procedure Cleanup; { SAFE_RELEASE( m_pEffect ); }
    function OnLostDevice: HRESULT;
    function OnResetDevice(dwWidth, dwHeight: DWORD): HRESULT;
  end;


  //--------------------------------------------------------------------------------------
  // struct CPProcInstance
  // A class that represents an instance of a post-process to be applied
  // to the scene.
  //--------------------------------------------------------------------------------------
  CPProcInstance = class
  protected
    m_avParam: array[0..NUM_PARAMS-1] of TD3DXVector4;
    m_nFxIndex: Integer;

  public
    constructor Create; 
  end;


  CRenderTargetChain = class
    m_nNext: Integer;
    m_bFirstRender: Boolean;
    m_pRenderTarget: array[0..1] of IDirect3DTexture9;

  public
    constructor Create;
    destructor Destroy; override;

    procedure Init(const pRT: array of IDirect3DTexture9);

    procedure Cleanup;
    procedure Flip;

    function GetPrevTarget: IDirect3DTexture9; { return m_pRenderTarget[1 - m_nNext]; }
    function GetPrevSource: IDirect3DTexture9; { return m_pRenderTarget[m_nNext]; }
    function GetNextTarget: IDirect3DTexture9; { return m_pRenderTarget[m_nNext]; }
    function GetNextSource: IDirect3DTexture9; { return m_pRenderTarget[1 - m_nNext]; }
  end;


  // An CRenderTargetSet object dictates what render targets
  // to use in a pass of scene rendering.
  TRenderTargetSet = record
    pRT: array[0..RT_COUNT-1] of IDirect3DSurface9;
  end;


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
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
  g_pEnvTex: IDirect3DCubeTexture9;           // Texture for environment mapping
  g_pVertDecl: IDirect3DVertexDeclaration9;   // Vertex decl for scene rendering
  g_pSkyBoxDecl: IDirect3DVertexDeclaration9; // Vertex decl for Skybox rendering
  g_pVertDeclPP: IDirect3DVertexDeclaration9; // Vertex decl for post-processing
  g_mMeshWorld: TD3DXMatrixA16;               // World matrix (xlate and scale) for the mesh
  g_nScene: Integer = 0;                      // Indicates the scene # to render
  g_aPostProcess: array[0..PPCOUNT-1] of CPostProcess;  // Effect object for postprocesses
  g_hTRenderScene: TD3DXHandle;               // Handle to RenderScene technique
  g_hTRenderEnvMapScene: TD3DXHandle;         // Handle to RenderEnvMapScene technique
  g_hTRenderNoLight: TD3DXHandle;             // Handle to RenderNoLight technique
  g_hTRenderSkyBox: TD3DXHandle;              // Handle to RenderSkyBox technique
  g_SceneMesh: array[0..1] of CDXUTMesh;      // Mesh objects in the scene
  g_Skybox: CDXUTMesh;                        // Skybox mesh
  g_TexFormat: TD3DFormat;                    // Render target texture format
  g_pSceneSave: array[0..RT_COUNT-1] of IDirect3DTexture9; // To save original scene image before postprocess
  g_RTChain: array[0..RT_COUNT-1] of CRenderTargetChain;   // Render target chain (4 used in sample)
  g_bEnablePostProc: Boolean = True;          // Whether or not to enable post-processing

  g_nPasses: Integer = 0;                     // Number of passes required to render scene
  g_nRtUsed: Integer = 0;                     // Number of simultaneous RT used to render scene
  g_aRtTable: array[0..RT_COUNT-1] of TRenderTargetSet; // Table of which RT to use for all passes


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_SELECTSCENE         = 5;
  IDC_AVAILABLELIST       = 6;
  IDC_ACTIVELIST          = 7;
  IDC_AVAILABLELISTLABEL  = 8;
  IDC_ACTIVELISTLABEL     = 9;
  IDC_PARAM0NAME          = 10;
  IDC_PARAM1NAME          = 11;
  IDC_PARAM0              = 12;
  IDC_PARAM1              = 13;
  IDC_MOVEUP              = 14;
  IDC_MOVEDOWN            = 15;
  IDC_CLEAR               = 16;
  IDC_ENABLEPP            = 17;
  IDC_PRESETLABEL         = 18;
  IDC_PREBLUR             = 19;
  IDC_PREBLOOM            = 20;
  IDC_PREDOF              = 21;
  IDC_PREEDGE             = 22;


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
//todo: Fill Bug report to MS: LoadMesh
//function LoadMesh(const pd3dDevice: IDirect3DDevice9; strFileName: PWideChar; out ppMesh: ID3DXMesh): HRESULT; overload;
procedure RenderText;
//todo: Fill Bug report to MS: different param lists in forward and in implementation
function PerformSinglePostProcess(const pd3dDevice: IDirect3DDevice9;
  const PP: CPostProcess; const Inst: CPProcInstance;
  pVB: IDirect3DVertexBuffer9; var aQuad: array of TppVert; var fExtentX, fExtentY: Single): HRESULT;
function PerformPostProcess(const pd3dDevice: IDirect3DDevice9): HRESULT;
function ComputeMeshWorldMatrix(pMesh: ID3DXMesh): HRESULT;


procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;

procedure ClearActiveList;

implementation


//--------------------------------------------------------------------------------------
// Empty the active effect list except the last (blank) item.
procedure ClearActiveList;
var
  pListBox: CDXUTListBox;
  pItem: PDXUTListBoxItem;
  i: Integer;
begin
  // Clear all items in the active list except the last one.

  pListBox := g_SampleUI.GetListBox(IDC_ACTIVELIST);
  if (pListBox = nil) then Exit;

  i := pListBox.Size - 1;
  while (i > 0) do
  begin
    Dec(i);
    pItem := pListBox.GetItem(0);
    FreeMem(pItem.pData);
    pListBox.RemoveItem(0);
  end;
end;


//--------------------------------------------------------------------------------------
// Initialize the app
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  pMultiSampleTypeList: TD3DMultiSampleTypeArray;
  i, iY: Integer;
  pListBox: CDXUTListBox;
  pEditBox: CDXUTEditBox;
  pComboBox: CDXUTComboBox;
begin
  // This sample does not do multisampling.
  SetLength(pMultiSampleTypeList, 1);
  pMultiSampleTypeList[0]:= D3DMULTISAMPLE_NONE;
  DXUTGetEnumeration.PossibleMultisampleTypeList:= pMultiSampleTypeList;
  DXUTGetEnumeration.SetMultisampleQualityMax(0);

  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_SampleUI.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent);
  iY := 0;     g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 0, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', 0, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 0, iY , 125, 22, VK_F2);

  g_SampleUI.SetCallback(OnGUIEvent); iY := 5;
  g_SampleUI.EnableCaption := True;
  g_SampleUI.SetCaptionText('Effect Manager');
  g_SampleUI.SetBackgroundColors(D3DCOLOR_ARGB(100, 255, 255, 255));

  // Initialize sample-specific UI controls
  g_SampleUI.AddStatic(IDC_AVAILABLELISTLABEL, 'Available effects (Dbl click inserts effect):', 10, iY, 210, 16);
  g_SampleUI.GetStatic(IDC_AVAILABLELISTLABEL).Element[0].dwTextFormat := DT_LEFT or DT_TOP;
  Inc(iY, 18); g_SampleUI.AddListBox(IDC_AVAILABLELIST, 10, iY, 200, 82, NORMAL, @pListBox);
  if Assigned(pListBox) then
  begin
    // Populate ListBox items
    for i := 0 to PPCOUNT - 1 do
      pListBox.AddItem(g_aszPpDesc[i], Pointer(size_t(i)));
  end;
  Inc(iY, 87); g_SampleUI.AddStatic(IDC_ACTIVELISTLABEL, 'Active effects (Dbl click removes effect):', 10, iY, 210, 16);
  g_SampleUI.GetStatic(IDC_ACTIVELISTLABEL).Element[0].dwTextFormat := DT_LEFT or DT_TOP;
  Inc(iY, 18); g_SampleUI.AddListBox(IDC_ACTIVELIST, 10, iY, 200, 82, NORMAL, @pListBox);
  if Assigned(pListBox) then
  begin
    // Add a blank entry for users to add effect to the end of list.
//todo: function StringCopyWorkerW(pszDest: PWideChar; cchDest: size_t; {pointer to const} pszSrc: PWideChar): HRESULT;
{begin
  Assert(Assigned(pszSrc));}
    pListBox.AddItem('', nil);
  end;
  Inc(iY, 92);
  g_SampleUI.AddButton(IDC_MOVEUP, 'Move Up', 0, iY, 70, 22);
  g_SampleUI.AddButton(IDC_MOVEDOWN, 'Move Down', 72, iY, 75, 22);
  g_SampleUI.AddButton(IDC_CLEAR, 'Clear Al', 149, iY, 65, 22);
  Inc(iY, 24);
  g_SampleUI.AddStatic(IDC_PARAM0NAME, 'Select an active effect to set its parameter.', 5, iY, 215, 15);
  g_SampleUI.GetStatic(IDC_PARAM0NAME).Element[0].dwTextFormat := DT_LEFT or DT_TOP;
  Inc(iY, 15);
  g_SampleUI.AddEditBox(IDC_PARAM0, '', 5, iY, 210, 20, False, @pEditBox);
  if Assigned(pEditBox) then
  begin
    pEditBox.BorderWidth:= 1;
    pEditBox.Spacing:= 2;
  end;
  Inc(iY, 20);
  g_SampleUI.AddStatic(IDC_PARAM1NAME, 'Select an active effect to set its parameter.', 5, 20, 215, 15);
  g_SampleUI.GetStatic(IDC_PARAM1NAME).Element[0].dwTextFormat := DT_LEFT or DT_TOP;
  Inc(iY, 15);
  g_SampleUI.AddEditBox(IDC_PARAM1, '', 5, iY, 210, 20, False, @pEditBox);
  if Assigned(pEditBox) then
  begin
    pEditBox.BorderWidth := 1;
    pEditBox.Spacing := 2;
  end;

  // Disable the edit boxes and 2nd static control by default.
  g_SampleUI.GetControl(IDC_PARAM0).Enabled := False;
  g_SampleUI.GetControl(IDC_PARAM0).Visible := False;
  g_SampleUI.GetControl(IDC_PARAM1).Enabled := False;
  g_SampleUI.GetControl(IDC_PARAM1).Visible := False;
  g_SampleUI.GetControl(IDC_PARAM1NAME).Enabled := False;
  g_SampleUI.GetControl(IDC_PARAM1NAME).Visible := False;

  Inc(iY, 25);
  g_SampleUI.AddCheckBox(IDC_ENABLEPP, '(E)nable post-processing', 5, iY, 200, 24, true, Ord('E'));

  Inc(iY, 25);
  g_SampleUI.AddComboBox(IDC_SELECTSCENE, 5, iY, 210, 24, Ord('C'), False, @pComboBox);
  if Assigned(pComboBox) then
  begin
    pComboBox.AddItem('(C)urrent Mesh: Dwarf', Pointer(0));
    pComboBox.AddItem('(C)urrent Mesh: Skull', Pointer(1));
  end;

  Inc(iY, 28);
  g_SampleUI.AddStatic(IDC_PRESETLABEL, 'Predefined post-process combinations:', 5, iY, 210, 22);
  g_SampleUI.GetControl(IDC_PRESETLABEL).Element[0].dwTextFormat := DT_LEFT or DT_TOP;
  Inc(iY, 22);
  g_SampleUI.AddButton(IDC_PREBLUR, 'Blur', 5, iY, 100, 22);
  g_SampleUI.AddButton(IDC_PREBLOOM, 'Bloom', 115, iY, 100, 22);
  Inc(iY, 24);
  g_SampleUI.AddButton(IDC_PREDOF, 'Depth of Field', 5, iY, 100, 22);
  g_SampleUI.AddButton(IDC_PREEDGE, 'Edge Glow', 115, iY, 100, 22);

  // Initialize camera parameters
  g_Camera.SetModelCenter(D3DXVector3(0.0, 0.0, 0.0));
  g_Camera.SetRadius(2.8);
  g_Camera.SetEnablePositionMovement(False);
end;


//--------------------------------------------------------------------------------------
// Compute the translate and scale transform for the current mesh.
function ComputeMeshWorldMatrix(pMesh: ID3DXMesh): HRESULT;
var
  pVB: IDirect3DVertexBuffer9;
  pVBData: Pointer;
  vCtr: TD3DXVector3;
  fRadius: Single;
  m: TD3DXMatrixA16;
begin
  if FAILED(pMesh.GetVertexBuffer(pVB)) then
  begin
    Result:= E_FAIL;
    Exit;
  end;

  if SUCCEEDED(pVB.Lock(0, 0, pVBData, D3DLOCK_READONLY)) then
  begin
    D3DXComputeBoundingSphere(PD3DXVector3(pVBData), pMesh.GetNumVertices,
                              D3DXGetFVFVertexSize(pMesh.GetFVF),
                              vCtr, fRadius);

    D3DXMatrixTranslation(g_mMeshWorld, -vCtr.x, -vCtr.y, -vCtr.z);
    D3DXMatrixScaling(m, 1/fRadius, 1/fRadius, 1/fRadius);
    D3DXMatrixMultiply(g_mMeshWorld, g_mMeshWorld, m);

    pVB.Unlock;
  end;
  pVB := nil;

  Result:= S_OK;
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

  // Check 32 bit integer format support
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                                   AdapterFormat, D3DUSAGE_RENDERTARGET,
                                   D3DRTYPE_CUBETEXTURE, D3DFMT_A8R8G8B8))
  then Exit;

  // Must support pixel shader 2.0
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2,0)) then Exit;

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
  // Turn vsync off
  pDeviceSettings.pp.PresentationInterval := D3DPRESENT_INTERVAL_IMMEDIATE;
  g_SettingsDlg.DialogControl.GetComboBox(DXUTSETTINGSDLG_PRESENT_INTERVAL ).Enabled := False;

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
  Caps: TD3DCaps9;
  pD3D: IDirect3D9;
  DisplayMode: TD3DDisplayMode;
  dwShaderFlags: DWORD;
  str: array[0..MAX_PATH-1] of WideChar;
  i: Integer;
begin
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  // Query multiple RT setting and set the num of passes required
  pd3dDevice.GetDeviceCaps(Caps);
  if (Caps.NumSimultaneousRTs > 2) then
  begin
    // One pass of 3 RTs
    g_nPasses := 1;
    g_nRtUsed := 3;
  end else
  if (Caps.NumSimultaneousRTs > 1) then
  begin
    // Two passes of 2 RTs. The 2nd pass uses only one.
    g_nPasses := 2;
    g_nRtUsed := 2;
  end else
  begin
    // Three passes of single RT.
    g_nPasses := 3;
    g_nRtUsed := 1;
  end;

  // Determine which of D3DFMT_A16B16G16R16F or D3DFMT_A8R8G8B8
  // to use for scene-rendering RTs.
  pd3dDevice.GetDirect3D(pD3D);
  pd3dDevice.GetDisplayMode(0, DisplayMode);

  if FAILED(pD3D.CheckDeviceFormat(Caps.AdapterOrdinal, Caps.DeviceType,
                   DisplayMode.Format, D3DUSAGE_RENDERTARGET,
                   D3DRTYPE_TEXTURE, D3DFMT_A16B16G16R16F))
  then g_TexFormat := D3DFMT_A8R8G8B8
  else g_TexFormat := D3DFMT_A16B16G16R16F;

  pD3D := nil;

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
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'Scene.fx');
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // they the .fx file failed to compile
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags,
                                     nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  // Initialize the postprocess objects
  for i := 0 to PPCOUNT - 1 do
  begin
    Result := g_aPostProcess[i].Init(pd3dDevice, dwShaderFlags, g_aszFxFile[i]);
    if FAILED(Result) then Exit;
  end;

  // Obtain the technique handles
  case g_nPasses of
    1:
    begin
      g_hTRenderScene := g_pEffect.GetTechniqueByName('RenderScene');
      g_hTRenderEnvMapScene := g_pEffect.GetTechniqueByName('RenderEnvMapScene');
      g_hTRenderSkyBox := g_pEffect.GetTechniqueByName('RenderSkyBox');
    end;
    2:
    begin
      g_hTRenderScene := g_pEffect.GetTechniqueByName('RenderSceneTwoPasses');
      g_hTRenderEnvMapScene := g_pEffect.GetTechniqueByName('RenderEnvMapSceneTwoPasses');
      g_hTRenderSkyBox := g_pEffect.GetTechniqueByName('RenderSkyBoxTwoPasses');
    end;
    3:
    begin
      g_hTRenderScene := g_pEffect.GetTechniqueByName('RenderSceneThreePasses');
      g_hTRenderEnvMapScene := g_pEffect.GetTechniqueByName('RenderEnvMapSceneThreePasses');
      g_hTRenderSkyBox := g_pEffect.GetTechniqueByName('RenderSkyBoxThreePasses');
    end;
  end;
  g_hTRenderNoLight := g_pEffect.GetTechniqueByName('RenderNoLight');

  // Create vertex declaration for scene
  Result := pd3dDevice.CreateVertexDeclaration(@TMeshVert_Decl, g_pVertDecl);
  if FAILED(Result) then Exit;

  // Create vertex declaration for skybox
  Result := pd3dDevice.CreateVertexDeclaration(@TSkyboxVert_Decl, g_pSkyBoxDecl);
  if FAILED(Result) then Exit;

  // Create vertex declaration for post-process
  Result := pd3dDevice.CreateVertexDeclaration(@TppVert_Decl, g_pVertDeclPP);
  if FAILED(Result) then Exit;

  // Load the meshes
  Result:= DXUTERR_MEDIANOTFOUND;

  if FAILED(g_SceneMesh[0].CreateMesh(pd3dDevice, 'dwarf\\dwarf.x')) then Exit;
  g_SceneMesh[0].SetVertexDecl(pd3dDevice, @TMeshVert_Decl);
  if FAILED(g_SceneMesh[1].CreateMesh(pd3dDevice, 'misc\\skullocc.x')) then Exit;
  g_SceneMesh[1].SetVertexDecl(pd3dDevice, @TMeshVert_Decl);
  if FAILED(g_Skybox.CreateMesh(pd3dDevice, 'alley_skybox.x')) then Exit;
  g_Skybox.SetVertexDecl(pd3dDevice, @TSkyboxVert_Decl);

  // Initialize the mesh's world matrix
  ComputeMeshWorldMatrix(g_SceneMesh[g_nScene].Mesh);

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
  i, p, t: Integer;
  fAspectRatio: Single;
  pRT: array[0..1] of IDirect3DTexture9;
  str: array[0..MAX_PATH-1] of WideChar;
  pSurf: IDirect3DSurface9;
begin
  Result:= g_DialogResourceManager.OnResetDevice;
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnResetDevice;
  if V_Failed(Result) then Exit;

  if Assigned(g_pFont) then g_pFont.OnResetDevice;
  if Assigned(g_pEffect) then g_pEffect.OnResetDevice;

  for p := 0 to PPCOUNT - 1 do
  begin
    Result := g_aPostProcess[p].OnResetDevice(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);
    if V_Failed(Result) then Exit;
  end;

  // Create a sprite to help batch calls when drawing many lines of text
  Result:= D3DXCreateSprite(pd3dDevice, g_pTextSprite);
  if V_Failed(Result) then Exit;

  // Setup the camera's projection parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI/4, fAspectRatio, 0.1, 1000.0);
  g_pEffect.SetMatrix('g_mProj', g_Camera.GetProjMatrix^);
  g_Camera.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);

  g_SceneMesh[0].RestoreDeviceObjects(pd3dDevice);
  g_SceneMesh[1].RestoreDeviceObjects(pd3dDevice);
  g_Skybox.RestoreDeviceObjects(pd3dDevice);

  // Create scene save texture
  for i := 0 to RT_COUNT - 1 do
  begin
    Result:= pd3dDevice.CreateTexture(pBackBufferSurfaceDesc.Width,
                                      pBackBufferSurfaceDesc.Height,
                                      1,
                                      D3DUSAGE_RENDERTARGET,
                                      g_TexFormat,
                                      D3DPOOL_DEFAULT,
                                      g_pSceneSave[i],
                                      nil);
    if V_Failed(Result) then Exit;

    // Create the textures for this render target chains
    ZeroMemory(@pRT, SizeOf(pRT));
    for t := 0 to 1 do
    begin
      Result:= pd3dDevice.CreateTexture(pBackBufferSurfaceDesc.Width,
                                        pBackBufferSurfaceDesc.Height,
                                        1,
                                        D3DUSAGE_RENDERTARGET,
                                        D3DFMT_A8R8G8B8,
                                        D3DPOOL_DEFAULT,
                                        pRT[t],
                                        nil);
      if V_Failed(Result) then Exit;
    end;
    g_RTChain[i].Init(pRT);
    pRT[0] := nil;
    pRT[1] := nil;
  end;

  // Create the environment mapping texture
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'Light Probes\uffizi_cross.dds');
  if V_Failed(Result) then Exit;
  if FAILED(D3DXCreateCubeTextureFromFileW(pd3dDevice, str, g_pEnvTex)) then
  begin
    Result:= DXUTERR_MEDIANOTFOUND;
    Exit;
  end;

  // Initialize the render target table based on how many simultaneous RTs
  // the card can support.
  case g_nPasses of
    1:
    begin
      g_pSceneSave[0].GetSurfaceLevel(0, pSurf);
      g_aRtTable[0].pRT[0] := pSurf;
      g_pSceneSave[1].GetSurfaceLevel(0, pSurf);
      g_aRtTable[0].pRT[1] := pSurf;
      g_pSceneSave[2].GetSurfaceLevel(0, pSurf);
      g_aRtTable[0].pRT[2] := pSurf;
      // Passes 1 and 2 are not used
      g_aRtTable[1].pRT[0] := nil;
      g_aRtTable[1].pRT[1] := nil;
      g_aRtTable[1].pRT[2] := nil;
      g_aRtTable[2].pRT[0] := nil;
      g_aRtTable[2].pRT[1] := nil;
      g_aRtTable[2].pRT[2] := nil;
    end;

    2:
    begin
      g_pSceneSave[0].GetSurfaceLevel(0, pSurf);
      g_aRtTable[0].pRT[0] := pSurf;
      g_pSceneSave[1].GetSurfaceLevel(0, pSurf);
      g_aRtTable[0].pRT[1] := pSurf;
      g_aRtTable[0].pRT[2] := nil;  // RT 2 of pass 0 not used
      g_pSceneSave[2].GetSurfaceLevel(0, pSurf);
      g_aRtTable[1].pRT[0] := pSurf;
      // RT 1 & 2 of pass 1 not used
      g_aRtTable[1].pRT[1] := nil;
      g_aRtTable[1].pRT[2] := nil;
      // Pass 2 not used
      g_aRtTable[2].pRT[0] := nil;
      g_aRtTable[2].pRT[1] := nil;
      g_aRtTable[2].pRT[2] := nil;
    end;

    3:
    begin
      g_pSceneSave[0].GetSurfaceLevel(0, pSurf);
      g_aRtTable[0].pRT[0] := pSurf;
      // RT 1 & 2 of pass 0 not used
      g_aRtTable[0].pRT[1] := nil;
      g_aRtTable[0].pRT[2] := nil;
      g_pSceneSave[1].GetSurfaceLevel(0, pSurf);
      g_aRtTable[1].pRT[0] := pSurf;
      // RT 1 & 2 of pass 1 not used
      g_aRtTable[1].pRT[1] := nil;
      g_aRtTable[1].pRT[2] := nil;
      g_pSceneSave[2].GetSurfaceLevel(0, pSurf);
      g_aRtTable[2].pRT[0] := pSurf;
      // RT 1 & 2 of pass 2 not used
      g_aRtTable[2].pRT[1] := nil;
      g_aRtTable[2].pRT[2] := nil;
    end;
  end;

  g_HUD.SetLocation(0, 100);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation( pBackBufferSurfaceDesc.Width-225, 5);
  g_SampleUI.SetSize(220, 470);

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
// Name: PerformSinglePostProcess()
// Desc: Perform post-process by setting the previous render target as a
//       source texture and rendering a quad with the post-process technique
//       set.
//       This method changes render target without saving any. The caller
//       should ensure that the default render target is saved before calling
//       this.
//       When this method is invoked, m_dwNextTarget is the index of the
//       rendertarget of this post-process.  1 - m_dwNextTarget is the index
//       of the source of this post-process.
function PerformSinglePostProcess(const pd3dDevice: IDirect3DDevice9;
  const PP: CPostProcess; const Inst: CPProcInstance;
  pVB: IDirect3DVertexBuffer9; var aQuad: array of TppVert; var fExtentX, fExtentY: Single): HRESULT;
var
  i: Integer;
  cPasses, p: LongWord;
  bUpdateVB: Boolean;  // Inidicates whether the vertex buffer
  fScaleX, fScaleY: Single;
  hPass: TD3DXHandle;
  hExtentScaleX: TD3DXHandle;
  hExtentScaleY: TD3DXHandle;
  pVBData: Pointer;
  pTarget: IDirect3DTexture9;
  pTexSurf: IDirect3DSurface9;
begin
  //
  // The post-process effect may require that a copy of the
  // originally rendered scene be available for use, so
  // we initialize them here.
  //

  for i := 0 to RT_COUNT - 1 do
    PP.m_pEffect.SetTexture(PP.m_hTexScene[i], g_pSceneSave[i]);

  //
  // If there are any parameters, initialize them here.
  //

  for i := 0 to NUM_PARAMS - 1 do
    if Assigned(PP.m_ahParam[i]) then
      PP.m_pEffect.SetVector(PP.m_ahParam[i], Inst.m_avParam[i]);

  // Render the quad
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    PP.m_pEffect.SetTechnique('PostProcess');

    // Set the vertex declaration
    pd3dDevice.SetVertexDeclaration(g_pVertDeclPP);

    // Draw the quad
    PP.m_pEffect._Begin(@cPasses, 0);
    for p := 0 to cPasses - 1 do
    begin
      bUpdateVB := False;  // Inidicates whether the vertex buffer
                           // needs update for this pass.

      //
      // If the extents has been modified, the texture coordinates
      // in the quad need to be updated.
      //

      if (aQuad[1].tu <> fExtentX) then
      begin
        aQuad[1].tu := fExtentX; aQuad[3].tu := fExtentX;
        bUpdateVB := True;
      end;
      if (aQuad[2].tv <> fExtentY) then 
      begin
        aQuad[2].tv := fExtentY; aQuad[3].tv := fExtentY;
        bUpdateVB := True;
      end;

      //
      // Check if the pass has annotation for extent info.  Update
      // fScaleX and fScaleY if it does.  Otherwise, default to 1.0f.
      //

      fScaleX := 1.0; fScaleY := 1.0;
      hPass := PP.m_pEffect.GetPass( PP.m_hTPostProcess, p);
      hExtentScaleX := PP.m_pEffect.GetAnnotationByName(hPass, 'fScaleX');
      if Assigned(hExtentScaleX) then
        PP.m_pEffect.GetFloat(hExtentScaleX, fScaleX);
      hExtentScaleY := PP.m_pEffect.GetAnnotationByName(hPass, 'fScaleY');
      if Assigned(hExtentScaleY) then
        PP.m_pEffect.GetFloat(hExtentScaleY, fScaleY);

      //
      // Now modify the quad according to the scaling values specified for
      // this pass
      //
      if (fScaleX <> 1.0) then
      begin
        aQuad[1].x := (aQuad[1].x + 0.5) * fScaleX - 0.5;
        aQuad[3].x := (aQuad[3].x + 0.5) * fScaleX - 0.5;
        bUpdateVB := True;
      end;
      if (fScaleY <> 1.0) then
      begin
        aQuad[2].y := (aQuad[2].y + 0.5) * fScaleY - 0.5;
        aQuad[3].y := (aQuad[3].y + 0.5) * fScaleY - 0.5;
        bUpdateVB := True;
      end;

      if bUpdateVB then
      begin
        // Scaling requires updating the vertex buffer.
        if SUCCEEDED(pVB.Lock(0, 0, pVBData, D3DLOCK_DISCARD)) then
        begin
          CopyMemory(pVBData, @aQuad[0], 4 * SizeOf(TppVert));
          pVB.Unlock;
        end;
      end;
      fExtentX := fExtentX * fScaleX;
      fExtentY := fExtentY * fScaleY;

      // Set up the textures and the render target
      //
      for i := 0 to RT_COUNT - 1 do
      begin
        // If this is the very first post-process rendering,
        // obtain the source textures from the scene.
        // Otherwise, initialize the post-process source texture to
        // the previous render target.
        //
        if (g_RTChain[i].m_bFirstRender)
        then PP.m_pEffect.SetTexture(PP.m_hTexSource[i], g_pSceneSave[i])
        else PP.m_pEffect.SetTexture(PP.m_hTexSource[i], g_RTChain[i].GetNextSource);
      end;

      //
      // Set up the new render target
      //
      pTarget := g_RTChain[PP.m_nRenderTarget].GetNextTarget;
      Result := pTarget.GetSurfaceLevel(0, pTexSurf);
      if FAILED(Result) then
      begin
        Result:= DXUT_ERR('GetSurfaceLevel', Result);
        Exit;
      end;
      pd3dDevice.SetRenderTarget( 0, pTexSurf);
      pTexSurf := nil;
      // We have output to this render target. Flag it.
      g_RTChain[PP.m_nRenderTarget].m_bFirstRender := False;

      //
      // Clear the render target
      //
      pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET, $00000000, 1.0, 0);
      //
      // Render
      //
      PP.m_pEffect.BeginPass(p);
      pd3dDevice.SetStreamSource(0, pVB, 0, SizeOf(TppVert));
      pd3dDevice.DrawPrimitive(D3DPT_TRIANGLESTRIP, 0, 2);
      PP.m_pEffect.EndPass;

      // Update next rendertarget index
      g_RTChain[PP.m_nRenderTarget].Flip;
    end;
    PP.m_pEffect._End;

    // End scene
    pd3dDevice.EndScene;
  end;

  Result:= S_OK;
end;


function ppVert(
  x, y, z, rhw: Single;
  tu, tv: Single;       // Texcoord for post-process source
  tu2, tv2: Single     // Texcoord for the original scene
): TppVert;
begin
  Result.x:= x;
  Result.y:= y;
  Result.z:= z;
  Result.rhw:= rhw;
  Result.tu:= tu;
  Result.tv:= tv;
  Result.tu2:= tu2;
  Result.tv2:= tv2;
end;

//--------------------------------------------------------------------------------------
// PerformPostProcess()
// Perform all active post-processes in order.
function PerformPostProcess(const pd3dDevice: IDirect3DDevice9): HRESULT;
var
  fExtentX , fExtentY: Single;
  pd3dsdBackBuffer: PD3DSurfaceDesc;
  Quad: array[0..3] of TppVert;
  pVB: IDirect3DVertexBuffer9;
  pVBData: Pointer;
  i: Integer;
  pListBox: CDXUTListBox;
  nEffIndex: Integer;
  pItem: PDXUTListBoxItem;
  pInstance: CPProcInstance;
begin
  //
  // Extents are used to control how much of the rendertarget is rendered
  // during postprocess. For example, with the extent of 0.5 and 0.5, only
  // the upper left quarter of the rendertarget will be rendered during
  // postprocess.
  //
  fExtentX := 1.0; fExtentY := 1.0;
  pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;

  //
  // Set up our quad
  //
  Quad[0] := ppVert(-0.5,                       -0.5,                        1.0, 1.0, 0.0, 0.0, 0.0, 0.0);
  Quad[1] := ppVert(pd3dsdBackBuffer.Width-0.5, -0.5,                        1.0, 1.0, 1.0, 0.0, 1.0, 0.0);
  Quad[2] := ppVert(-0.5,                       pd3dsdBackBuffer.Height-0.5, 1.0, 1.0, 0.0, 1.0, 0.0, 1.0);
  Quad[3] := ppVert(pd3dsdBackBuffer.Width-0.5, pd3dsdBackBuffer.Height-0.5, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0);

  //
  // Create a vertex buffer out of the quad
  //
  Result := pd3dDevice.CreateVertexBuffer(SizeOf(TppVert) * 4,
                                          D3DUSAGE_WRITEONLY or D3DUSAGE_DYNAMIC,
                                          0,
                                          D3DPOOL_DEFAULT,
                                          pVB,
                                          nil);
  if FAILED(Result) then
  begin
    Result:= DXUT_ERR('CreateVertexBuffer', Result);
    Exit;
  end;

  // Fill in the vertex buffer
  if SUCCEEDED(pVB.Lock(0, 0, pVBData, D3DLOCK_DISCARD)) then
  begin
    CopyMemory(pVBData, @Quad[0], SizeOf(Quad));
    pVB.Unlock;
  end;

  // Clear first-time render flags
  for i := 0 to RT_COUNT - 1 do
    g_RTChain[i].m_bFirstRender := True;

  // Perform post processing
  pListBox := g_SampleUI.GetListBox(IDC_ACTIVELIST);
  if Assigned(pListBox) then
  begin
    // The last (blank) item has special purpose so do not process it.
    for nEffIndex := 0 to pListBox.Size - 2 do
    begin
      pItem := pListBox.GetItem(nEffIndex);
      if Assigned(pItem) then
      begin
        pInstance := CPProcInstance(pItem.pData);
        PerformSinglePostProcess(pd3dDevice,
                                 g_aPostProcess[pInstance.m_nFxIndex],
                                 pInstance,
                                 pVB,
                                 Quad,
                                 fExtentX,
                                 fExtentY);
      end;
    end;
  end;

  // Release the vertex buffer
  pVB := nil;

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called at the end of every frame to perform all the 
// rendering calls for the scene, and it will also be called if the window needs to be 
// repainted. After this function has returned, DXUT will call 
// IDirect3DDevice9::Present to display the contents of the next buffer in the swap chain
//--------------------------------------------------------------------------------------
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  cPass: LongWord;
  pMeshObj: ID3DXMesh;
  mWorldView: TD3DXMatrixA16;
  pOldRT: IDirect3DSurface9;
  mRevView: TD3DXMatrix;
  p, rt, m: Integer;
  mView: TD3DXMatrixA16;
  i: Integer;
  pListBox: CDXUTListBox;
  bPerformPostProcess: Boolean;
  pd3dsdBackBuffer: PD3DSurfaceDesc;
  Quad: array[0..3] of TppVert;
  pPrevTarget: IDirect3DTexture9;
  cPasses: LongWord;
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

  // Save render target 0 so we can restore it later
  pd3dDevice.GetRenderTarget(0, pOldRT);

  // Render the scene
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    // Set the vertex declaration
    V(pd3dDevice.SetVertexDeclaration(g_pVertDecl));

    // Render the mesh
    D3DXMatrixMultiply(mWorldView, g_mMeshWorld, g_Camera.GetWorldMatrix^);
    D3DXMatrixMultiply(mWorldView, mWorldView, g_Camera.GetViewMatrix^);
    V(g_pEffect.SetMatrix('g_mWorldView', mWorldView));
    V(g_pEffect.SetTexture('g_txEnvMap', g_pEnvTex));
    mRevView := g_Camera.GetViewMatrix^;
    mRevView._41 := 0.0; mRevView._42 := 0.0; mRevView._43 := 0.0;
    D3DXMatrixInverse(mRevView, nil, mRevView);
    V(g_pEffect.SetMatrix('g_mRevView', mRevView));

    case g_nScene of
      0: V(g_pEffect.SetTechnique(g_hTRenderScene));
      1: V(g_pEffect.SetTechnique(g_hTRenderEnvMapScene));
    end;

    pMeshObj := g_SceneMesh[g_nScene].Mesh;
    V(g_pEffect._Begin(@cPass, 0));
    for p := 0 to cPass - 1 do
    begin
      // Set the render target(s) for this pass
      for rt := 0 to g_nRtUsed - 1 do
        V(pd3dDevice.SetRenderTarget(rt, g_aRtTable[p].pRT[rt]));

      V(g_pEffect.BeginPass(p));

      // Iterate through each subset and render with its texture
      for m := 0 to g_SceneMesh[g_nScene].m_dwNumMaterials - 1 do
      begin
        V(g_pEffect.SetTexture('g_txScene', g_SceneMesh[g_nScene].m_pTextures[m]));
        V(g_pEffect.CommitChanges);
        V(pMeshObj.DrawSubset(m));
      end;

      V(g_pEffect.EndPass);
    end;
    V(g_pEffect._End);

    // Render the skybox as if the camera is at center
    V(g_pEffect.SetTechnique(g_hTRenderSkyBox));
    V(pd3dDevice.SetVertexDeclaration(g_pSkyBoxDecl));

    mView := g_Camera.GetViewMatrix^;
    mView._41 := 0.0; mView._42 := 0.0; mView._43 := 0.0;

    D3DXMatrixScaling(mWorldView, 100.0, 100.0, 100.0);
    D3DXMatrixMultiply(mWorldView, mWorldView, mView);
    V(g_pEffect.SetMatrix('g_mWorldView', mWorldView));

    pMeshObj := g_Skybox.Mesh;
    V(g_pEffect._Begin(@cPass, 0));
    for p := 0 to cPass - 1 do
    begin
      // Set the render target(s) for this pass
      for rt := 0 to g_nRtUsed - 1 do
        V(pd3dDevice.SetRenderTarget(rt, g_aRtTable[p].pRT[rt]));

      V(g_pEffect.BeginPass(p));

      // Iterate through each subset and render with its texture
      for m := 0 to g_Skybox.m_dwNumMaterials - 1 do
      begin
        V(g_pEffect.SetTexture('g_txScene', g_Skybox.m_pTextures[m]));
        V(g_pEffect.CommitChanges);
        V(pMeshObj.DrawSubset(m));
      end;

      V(g_pEffect.EndPass);
    end;
    V(g_pEffect._End);

    V(pd3dDevice.EndScene);
  end;

  //
  // Swap the chains
  //
  for i := 0 to RT_COUNT - 1 do g_RTChain[i].Flip;

  // Reset all render targets used besides RT 0
  for i := 1 to g_nRtUsed - 1 do
    V(pd3dDevice.SetRenderTarget(i, nil));

  //
  // Perform post-processes
  //

  pListBox := g_SampleUI.GetListBox(IDC_ACTIVELIST);
  bPerformPostProcess := g_bEnablePostProc and Assigned(pListBox) and (pListBox.Size > 1);
  if bPerformPostProcess then PerformPostProcess(pd3dDevice);

  // Restore old render target 0 (back buffer)
  V(pd3dDevice.SetRenderTarget(0, pOldRT));
  pOldRT := nil;

  //
  // Get the final result image onto the backbuffer
  //

  pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    // Render a screen-sized quad
    Quad[0] := ppVert(-0.5,                       -0.5,                        0.5, 1.0, 0.0, 0.0, 0.0, 0.0);
    Quad[1] := ppVert(pd3dsdBackBuffer.Width-0.5, -0.5,                        0.5, 1.0, 1.0, 0.0, 0.0, 0.0);
    Quad[2] := ppVert(-0.5,                       pd3dsdBackBuffer.Height-0.5, 0.5, 1.0, 0.0, 1.0, 0.0, 0.0);
    Quad[3] := ppVert(pd3dsdBackBuffer.Width-0.5, pd3dsdBackBuffer.Height-0.5, 0.5, 1.0, 1.0, 1.0, 0.0, 0.0);

    if bPerformPostProcess then pPrevTarget := g_RTChain[0].GetPrevTarget
    else pPrevTarget := g_pSceneSave[0];

    V(pd3dDevice.SetVertexDeclaration(g_pVertDeclPP));
    V(g_pEffect.SetTechnique(g_hTRenderNoLight));
    V(g_pEffect.SetTexture('g_txScene', pPrevTarget));
    V(g_pEffect._Begin(@cPasses, 0 ));
    for p := 0 to cPasses - 1 do
    begin
      V(g_pEffect.BeginPass(p));
      V(pd3dDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, quad, SizeOf(TppVert)));
      V(g_pEffect.EndPass);
    end;
    V(g_pEffect._End);

    // Render text
    RenderText;

    // Render dialogs
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
  pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;

  // Output statistics
  txtHelper._Begin;
  txtHelper.SetInsertionPos(5, 5);
  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));
  txtHelper.DrawTextLine(DXUTGetFrameStats(True)); // Show FPS
  txtHelper.DrawTextLine(DXUTGetDeviceStats);

  // If floating point rendertarget is not supported, display a warning
  // message to the user that some effects may not work correctly.
  if (D3DFMT_A16B16G16R16F <> g_TexFormat) then
  begin
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.0, 0.0, 1.0));
    txtHelper.SetInsertionPos(5, 45);
    txtHelper.DrawTextLine('Floating-point render target not supported'#10 +
                           'by the 3D device.  Some post-process effects'#10 +
                           'may not render correctly.');
  end;

  // Draw help
  if g_bShowHelp then
  begin
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*4);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
    txtHelper.DrawTextLine('Controls (F1 to hide):');

    txtHelper.SetInsertionPos(40, pd3dsdBackBuffer.Height-15*3);
    txtHelper.DrawTextLine('Mesh Movement: Left drag mouse'#10 + 
                           'Camera Movement: Right drag mouse');
  end else
  begin
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*2);
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


//#define IN_FLOAT_CHARSET( c ) \
//    ( (c) == L'-' || (c) == L'.' || ( (c) >= L'0' && (c) <= L'9' ) )
function IN_FLOAT_CHARSET(c: WideChar): Boolean;
begin
  Result := (c = '-') or (c = '.') or ((c >= '0') and (c <= '9'));
end;

//--------------------------------------------------------------------------------------
// Parse a string that contains a list of floats separated by space, and store
// them in the array of float pointed to by pBuffer.
// Parses up to 4 floats.
procedure ParseFloatList(const pwszText: PWideChar; pBuffer: PSingle);
var
  nWritten: Integer;  // Number of floats written
  pToken, pEnd: PWideChar;
  wszToken: array[0..29] of WideChar;
  nTokenLen: Integer;
begin
  nWritten := 0;  // Number of floats written

  pToken := pwszText;
  while (nWritten < 4) and (pToken^ <> #0) do
  begin
    // Skip leading spaces
    while (pToken^ = ' ') do Inc(pToken);

    // Locate the end of number
    pEnd := pToken;
    while IN_FLOAT_CHARSET(pEnd^) do Inc(pEnd);

    // Copy the token to our buffer
    nTokenLen := min(High(wszToken), Integer(pEnd - pToken)) + 1;
    StringCchCopy(wszToken, nTokenLen, pToken);
    pBuffer^ := StrToFloat(WideCharToString(wszToken));
    Inc(nWritten);
    Inc(pBuffer);
    pToken := pEnd;
  end;
end;


//--------------------------------------------------------------------------------------
// Inserts the postprocess effect identified by the index nEffectIndex into the
// active list.
procedure InsertEffect(nEffectIndex: Integer);
var
  nInsertPosition: Integer;
  pNewInst: CPProcInstance;
  p: Integer;
  nSelected: Integer;
begin
  nInsertPosition := g_SampleUI.GetListBox(IDC_ACTIVELIST).SelectedIndex;
  if (nInsertPosition = -1) then
    nInsertPosition := g_SampleUI.GetListBox(IDC_ACTIVELIST).Size - 1;

  // Create a new CPProcInstance object and set it as the data field of the
  // newly inserted item.
  pNewInst := CPProcInstance.Create;

  //todo: In Delphi constructors raise an error.., not return nil.
  if Assigned(pNewInst) then
  begin
    pNewInst.m_nFxIndex := nEffectIndex;
    ZeroMemory(@pNewInst.m_avParam, SizeOf(pNewInst.m_avParam));
    for p := 0 to NUM_PARAMS - 1 do
      pNewInst.m_avParam[p] := g_aPostProcess[pNewInst.m_nFxIndex].m_avParamDef[p];

    g_SampleUI.GetListBox(IDC_ACTIVELIST).InsertItem(nInsertPosition, g_aszPpDesc[nEffectIndex], pNewInst);

    // Set selection to the item after the inserted one.
    nSelected := g_SampleUI.GetListBox(IDC_ACTIVELIST).SelectedIndex;
    if (nSelected >= 0) then
      g_SampleUI.GetListBox(IDC_ACTIVELIST).SelectItem(nSelected + 1);
  end;
end;


//--------------------------------------------------------------------------------------
// Handles the GUI events
//--------------------------------------------------------------------------------------
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
type
  PFloatArray = ^TFloatArray;
  TFloatArray = array [0..3] of Single;
var
  pItem: PDXUTComboBoxItem;
  pLBItem: PDXUTListBoxItem;
  nSelected: Integer;
  pInstance: CPProcInstance;
  PP: CPostProcess;
  i, p: Integer;
  ParamText: WideString;
  pListBox: CDXUTListBox;
  pPrevItem, pNextItem: PDXUTListBoxItem;
  Temp: TDXUTListBoxItem;
  nParamIndex: Integer;
  v: TD3DXVector4;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;

    IDC_SELECTSCENE:
    begin
      //todo: Change GetSelectedItem to property
      pItem := (pControl as CDXUTComboBox).GetSelectedItem;
      if Assigned(pItem) then
      begin
        g_nScene := Integer(size_t(pItem.pData));

        // Scene mesh has chanaged. Re-initialize the world matrix
        // for the mesh.
        ComputeMeshWorldMatrix(g_SceneMesh[g_nScene].Mesh);
      end;
    end;

    IDC_AVAILABLELIST:
    begin
      case nEvent of
        EVENT_LISTBOX_ITEM_DBLCLK:
        begin
          pLBItem := (pControl as CDXUTListBox).GetSelectedItem;
          if Assigned(pLBItem) then
          begin
            // Inserts the selected effect in available list to the active list
            // before its selected item.

            InsertEffect(Integer(size_t(pLBItem.pData)));
          end;
        end;
      end;
    end;

    IDC_ACTIVELIST:
    begin
      case nEvent of
        EVENT_LISTBOX_ITEM_DBLCLK:
        begin
          nSelected := CDXUTListBox(pControl).GetSelectedIndex;

          // Do not remove the last (blank) item
          if (nSelected <> CDXUTListBox(pControl).Size - 1) then
          begin
            pLBItem := CDXUTListBox(pControl).GetSelectedItem;

            // if Assigned(pItem) then FreeMem(pLBItem.pData); //Clootie: this is checked automatically in Delphi RTL
            FreeMem(pLBItem.pData);
            CDXUTListBox(pControl).RemoveItem(nSelected);
          end;
        end;

        EVENT_LISTBOX_SELECTION:
        begin
          // Selection changed in the active list.  Update the parameter
          // controls.

          nSelected := CDXUTListBox(pControl).GetSelectedIndex;

          if (nSelected >= 0) and (nSelected < Integer(CDXUTListBox(pControl).Size) - 1) then 
          begin
            pLBItem := CDXUTListBox(pControl).GetSelectedItem;
            pInstance := CPProcInstance(pLBItem.pData);
            PP := g_aPostProcess[pInstance.m_nFxIndex];

            if Assigned(pInstance) and (PP.m_awszParamName[0][0] <> #0) then
            begin
              g_SampleUI.GetStatic(IDC_PARAM0NAME).Text := PP.m_awszParamName[0];

              // Fill the editboxes with the parameter values
              for p := 0 to NUM_PARAMS - 1 do 
              begin
                if (PP.m_awszParamName[p][0] <> #0) then
                begin
                  // Enable the label and editbox for this parameter
                  g_SampleUI.GetControl(IDC_PARAM0 + p).Enabled := True;
                  g_SampleUI.GetControl(IDC_PARAM0 + p).Visible := True;
                  g_SampleUI.GetControl(IDC_PARAM0NAME + p).Enabled := True;
                  g_SampleUI.GetControl(IDC_PARAM0NAME + p).Visible := True;

                  for i := 0 to PP.m_anParamSize[p]-1 do
                  begin
                    ParamText:= ParamText + WideFormat('%.5f ', [PFloatArray(@pInstance.m_avParam[p])[i]]);
                  end;

                  // Remove trailing space
                  if (ParamText[Length(ParamText)-1] = ' ') then
                    SetLength(ParamText, Length(ParamText)-1);
                  {$IFDEF FPC}
                  //todo: FPC "inline" related bug
                  g_SampleUI.GetEditBox(IDC_PARAM0 + p).SetText(PWideChar(ParamText));
                  {$ELSE}
                  g_SampleUI.GetEditBox(IDC_PARAM0 + p).Text := PWideChar(ParamText);
                  {$ENDIF}
                end;
              end;
            end else
            begin
              g_SampleUI.GetStatic(IDC_PARAM0NAME).Text := 'Selected effect has no parameters.';

              // Disable the edit boxes and 2nd parameter static
              g_SampleUI.GetControl(IDC_PARAM0).Enabled := False;
              g_SampleUI.GetControl(IDC_PARAM0).Visible := False;
              g_SampleUI.GetControl(IDC_PARAM1).Enabled := False;
              g_SampleUI.GetControl(IDC_PARAM1).Visible := False;
              g_SampleUI.GetControl(IDC_PARAM1NAME).Enabled := False;
              g_SampleUI.GetControl(IDC_PARAM1NAME).Visible := False;
            end;
          end else
          begin
            g_SampleUI.GetStatic(IDC_PARAM0NAME).Text := 'Select an active effect to set its parameter.';

            // Disable the edit boxes and 2nd parameter static
            g_SampleUI.GetControl(IDC_PARAM0).Enabled := False;
            g_SampleUI.GetControl(IDC_PARAM0).Visible := False;
            g_SampleUI.GetControl(IDC_PARAM1).Enabled := False;
            g_SampleUI.GetControl(IDC_PARAM1).Visible := False;
            g_SampleUI.GetControl(IDC_PARAM1NAME).Enabled := False;
            g_SampleUI.GetControl(IDC_PARAM1NAME).Visible := False;
          end;
        end;
      end;
    end;

    IDC_CLEAR: ClearActiveList;

    IDC_MOVEUP:
    begin
      pListBox := g_SampleUI.GetListBox(IDC_ACTIVELIST);
      if (pListBox = nil) then Exit;

      nSelected := pListBox.GetSelectedIndex;
      if (nSelected < 0) then Exit;

      // Cannot move up the first item or the last (blank) item.
      if (nSelected <> 0) and (nSelected <> pListBox.Size - 1) then
      begin
        pPrevItem := pListBox.GetItem(nSelected - 1);
        pLBItem := pListBox.GetItem(nSelected);
        // Swap
        Temp := pLBItem^;
        pLBItem^ := pPrevItem^;
        pPrevItem^ := Temp;

        pListBox.SelectItem(nSelected - 1);
      end;
    end;

    IDC_MOVEDOWN:
    begin
      pListBox := g_SampleUI.GetListBox(IDC_ACTIVELIST);
      if (pListBox = nil) then Exit;

      nSelected := pListBox.GetSelectedIndex;
      if (nSelected < 0) then Exit;

      // Cannot move down either of the last two item.
      if (nSelected < pListBox.Size - 2) then
      begin
        pNextItem := pListBox.GetItem(nSelected + 1);
        pLBItem := pListBox.GetItem(nSelected);

        // Swap
        if Assigned(pLBItem) and Assigned(pNextItem) then
        begin
          Temp := pLBItem^;
          pLBItem^ := pNextItem^;
          pNextItem^ := Temp;
        end;

        pListBox.SelectItem(nSelected + 1);
      end;
    end;

    IDC_PARAM0,
    IDC_PARAM1:
    begin
      if (nEvent = EVENT_EDITBOX_CHANGE) then
      begin
        case nControlID of
          IDC_PARAM0: nParamIndex := 0;
          IDC_PARAM1: nParamIndex := 1;
        else
          Exit;
        end;

        pLBItem := g_SampleUI.GetListBox(IDC_ACTIVELIST).GetSelectedItem;
        pInstance := nil;
        if Assigned(pLBItem) then pInstance := CPProcInstance(pLBItem.pData);

        if Assigned(pInstance) then
        begin
          ZeroMemory(@v, SizeOf(v));
          ParseFloatList(CDXUTEditBox(pControl).Text, @v);

          // We parsed the values. Now save them in the instance data.
          pInstance.m_avParam[nParamIndex] := v;
        end;
      end;
    end;

    IDC_ENABLEPP: g_bEnablePostProc := CDXUTCheckBox(pControl).Checked;

    IDC_PREBLUR:
    begin
      // Clear the list
      ClearActiveList;

      // Insert effects
      InsertEffect(9);
      InsertEffect(2);
      InsertEffect(3);
      InsertEffect(2);
      InsertEffect(3);
      InsertEffect(10);
    end;

    IDC_PREBLOOM:
    begin
      // Clear the list
      ClearActiveList;

      // Insert effects
      InsertEffect(9);
      InsertEffect(9);
      InsertEffect(6);
      InsertEffect(4);
      InsertEffect(5);
      InsertEffect(4);
      InsertEffect(5);
      InsertEffect(10);
      InsertEffect(12);
    end;

    IDC_PREDOF:
    begin
      // Clear the list
      ClearActiveList;

      // Insert effects
      InsertEffect(9);
      InsertEffect(2);
      InsertEffect(3);
      InsertEffect(2);
      InsertEffect(3);
      InsertEffect(10);
      InsertEffect(14);
    end;

    IDC_PREEDGE:
    begin
      // Clear the list
      ClearActiveList;

      // Insert effects
      InsertEffect(13);
      InsertEffect(9);
      InsertEffect(4);
      InsertEffect(5);
      InsertEffect(12);
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
var
  i, p, rt: Integer;
begin
  g_DialogResourceManager.OnLostDevice;
  g_SettingsDlg.OnLostDevice;
  if Assigned(g_pFont) then g_pFont.OnLostDevice;
  if Assigned(g_pEffect) then g_pEffect.OnLostDevice;
  g_pTextSprite := nil;

  for p := 0 to PPCOUNT - 1 do
    g_aPostProcess[p].OnLostDevice;

  // Release the scene save and render target textures
  for i := 0 to RT_COUNT - 1 do
  begin
    g_pSceneSave[i] := nil;
    g_RTChain[i].Cleanup;
  end;

  g_SceneMesh[0].InvalidateDeviceObjects;
  g_SceneMesh[1].InvalidateDeviceObjects;
  g_Skybox.InvalidateDeviceObjects;

  // Release the RT table's references
  for p := 0 to RT_COUNT-1 do
    for rt := 0 to RT_COUNT-1 do
      g_aRtTable[p].pRT[rt] := nil;

  g_pEnvTex := nil;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has
// been destroyed, which generally happens as a result of application termination or
// windowed/full screen toggles. Resources created in the OnCreateDevice callback
// should be released here, which generally includes all D3DPOOL_MANAGED resources.
//--------------------------------------------------------------------------------------
procedure OnDestroyDevice; stdcall;
var
  p: Integer;
begin
  g_DialogResourceManager.OnDestroyDevice;
  g_SettingsDlg.OnDestroyDevice;
  g_pEffect := nil;
  g_pFont := nil;
  g_pVertDecl := nil;
  g_pSkyBoxDecl := nil;
  g_pVertDeclPP := nil;

  g_SceneMesh[0].DestroyMesh;
  g_SceneMesh[1].DestroyMesh;
  g_Skybox.DestroyMesh;

  for p := 0 to PPCOUNT-1 do
    g_aPostProcess[p].Cleanup;
end;




{ CPostProcess }

destructor CPostProcess.Destroy;
begin
  Cleanup;
  inherited;
end;

procedure CPostProcess.Cleanup;
begin
  m_pEffect := nil;
end;

function CPostProcess.Init(const pDev: IDirect3DDevice9; dwShaderFlags: DWORD; wszName: PWideChar): HRESULT;
var
  wszPath: array[0..MAX_PATH-1] of WideChar;
  techdesc: TD3DXTechniqueDesc;
  i: Integer;
  passdesc: TD3DXPassDesc;
  aSem: array[0..MAXD3DDECLLENGTH-1] of TD3DXSemantic;
  uCount: LongWord;
  hAnno: TD3DXHandle;
  Name: AnsiString;
  szParamName: PAnsiChar;
begin
  Result:= DXUTFindDXSDKMediaFile(wszPath, MAX_PATH, wszName);
  if Failed(Result) then Exit;
  Result := D3DXCreateEffectFromFileW(pDev, wszPath, nil, nil, dwShaderFlags,
                                      nil, m_pEffect, nil);
  if Failed(Result) then Exit;

  // Get the PostProcess technique handle
  m_hTPostProcess := m_pEffect.GetTechniqueByName('PostProcess');

  // Obtain the handles to all texture objects in the effect
  m_hTexScene[0] := m_pEffect.GetParameterByName(nil, 'g_txSceneColor');
  m_hTexScene[1] := m_pEffect.GetParameterByName(nil, 'g_txSceneNormal');
  m_hTexScene[2] := m_pEffect.GetParameterByName(nil, 'g_txScenePosition');
  m_hTexScene[3] := m_pEffect.GetParameterByName(nil, 'g_txSceneVelocity');
  m_hTexSource[0] := m_pEffect.GetParameterByName(nil, 'g_txSrcColor');
  m_hTexSource[1] := m_pEffect.GetParameterByName(nil, 'g_txSrcNormal');
  m_hTexSource[2] := m_pEffect.GetParameterByName(nil, 'g_txSrcPosition');
  m_hTexSource[3] := m_pEffect.GetParameterByName(nil, 'g_txSrcVelocity');

  // Find out what render targets the technique writes to.
  if FAILED(m_pEffect.GetTechniqueDesc(m_hTPostProcess, techdesc)) then
  begin
    Result:= D3DERR_INVALIDCALL;
    Exit;
  end;

  for i := 0 to techdesc.Passes - 1 do
  begin
    if SUCCEEDED(m_pEffect.GetPassDesc(m_pEffect.GetPass(m_hTPostProcess, i), passdesc)) then
    begin
      if SUCCEEDED(D3DXGetShaderOutputSemantics(passdesc.pPixelShaderFunction, @aSem, @uCount)) then
      begin
        // Semantics received. Now examine the content and
        // find out which render target this technique
        // writes to.
        Dec(uCount);
        while (uCount <> 0) do
        begin
          if (D3DDECLUSAGE_COLOR = TD3DDeclUsage(aSem[uCount].Usage)) and (RT_COUNT > aSem[uCount].UsageIndex)
            then m_bWrite[uCount] := True;
          Dec(uCount);
        end;
      end;
    end;
  end;

  // Obtain the render target channel
  hAnno := m_pEffect.GetAnnotationByName(m_hTPostProcess, 'nRenderTarget');
  if Assigned(hAnno) then m_pEffect.GetInt(hAnno, m_nRenderTarget);

  // Obtain the handles to the changeable parameters, if any.
  for i := 0 to NUM_PARAMS-1 do
  begin
    Name:= Format('Parameter%d', [i]);
    hAnno := m_pEffect.GetAnnotationByName(m_hTPostProcess, PAnsiChar(Name));
    if Assigned(hAnno) and
       SUCCEEDED(m_pEffect.GetString(hAnno, szParamName)) then
    begin
      m_ahParam[i] := m_pEffect.GetParameterByName(nil, szParamName);
      MultiByteToWideChar(CP_ACP, 0, szParamName, -1, m_awszParamName[i], MAX_PATH);
    end;

    // Get the parameter description
    Name:= Format('Parameter%dDesc', [i]);
    hAnno := m_pEffect.GetAnnotationByName(m_hTPostProcess, PAnsiChar(Name));
    if Assigned(hAnno) and
       SUCCEEDED(m_pEffect.GetString(hAnno, szParamName)) then
    begin
      MultiByteToWideChar(CP_ACP, 0, szParamName, -1, m_awszParamDesc[i], MAX_PATH);
    end;

    // Get the parameter size
    Name:= Format('Parameter%dSize', [i]);
    hAnno := m_pEffect.GetAnnotationByName(m_hTPostProcess, PAnsiChar(Name));
    if Assigned(hAnno) then
      m_pEffect.GetInt(hAnno, m_anParamSize[i]);

    // Get the parameter default
    Name:= Format('Parameter%dDef', [i]);
    hAnno := m_pEffect.GetAnnotationByName(m_hTPostProcess, PAnsiChar(Name));
    if Assigned(hAnno) then
      m_pEffect.GetVector(hAnno, m_avParamDef[i]);
  end;

  Result:= S_OK;
end;

function CPostProcess.OnLostDevice: HRESULT;
begin
  Assert(Assigned(m_pEffect));
  m_pEffect.OnLostDevice;
  Result:= S_OK;
end;


function CPostProcess.OnResetDevice(dwWidth, dwHeight: DWORD): HRESULT;
var
  hParamToConvert: TD3DXHandle;
  hAnnotation: TD3DXHandle;
  uParamIndex: LongWord;
  szSource: PAnsiChar;
  hConvertSource: TD3DXHandle;
  desc: TD3DXParameterDesc;
  cKernel: DWORD;
  pvKernel: array of TD3DXVector4;
  i: Integer;
begin
  Assert(Assigned(m_pEffect));
  m_pEffect.OnResetDevice;

  // If one or more kernel exists, convert kernel from
  // pixel space to texel space.

  // First check for kernels.  Kernels are identified by
  // having a string annotation of name "ConvertPixelsToTexels"

  uParamIndex := 0;

  // If a top-level parameter has the "ConvertPixelsToTexels" annotation,
  // do the conversion.
  while (nil <> m_pEffect.GetParameter(nil, uParamIndex)) do
  begin
    hParamToConvert := m_pEffect.GetParameter(nil, uParamIndex);
    Inc(uParamIndex);
    hAnnotation := m_pEffect.GetAnnotationByName(hParamToConvert, 'ConvertPixelsToTexels');
    if (nil <> hAnnotation) then
    begin
      m_pEffect.GetString(hAnnotation, szSource);
      hConvertSource := m_pEffect.GetParameterByName(nil, szSource);

      if Assigned(hConvertSource) then 
      begin
        // Kernel source exists. Proceed.
        // Retrieve the kernel size
        m_pEffect.GetParameterDesc( hConvertSource, desc);
        // Each element has 2 floats
        cKernel := desc.Bytes div (2 * SizeOf(Single));
        try
          SetLength(pvKernel, cKernel);
        except
          Result:= E_OUTOFMEMORY;
          Exit;
        end;
        m_pEffect.GetVectorArray(hConvertSource, @pvKernel[0], cKernel);
        // Convert
        for i := 0 to cKernel - 1 do
        begin
          pvKernel[i].x := pvKernel[i].x / dwWidth;
          pvKernel[i].y := pvKernel[i].y / dwHeight;
        end;
        // Copy back
        m_pEffect.SetVectorArray(hParamToConvert, @pvKernel[0], cKernel);

        pvKernel := nil;
      end;
    end;
  end;

  Result:= S_OK;
end;


{ CPProcInstance }

constructor CPProcInstance.Create;
begin
  m_nFxIndex:= -1;
  // ZeroMemory( m_avParam, sizeof( m_avParam ) ); //Clootie: auto done in Delphi
end;

{ CRenderTargetChain }

constructor CRenderTargetChain.Create;
begin
  m_bFirstRender := True;
  // ZeroMemory(m_pRenderTarget, sizeof(m_pRenderTarget) );
end;

destructor CRenderTargetChain.Destroy;
begin
  Cleanup;
  inherited;
end;

procedure CRenderTargetChain.Cleanup;
begin
  m_pRenderTarget[0] := nil;
  m_pRenderTarget[1] := nil;
end;

procedure CRenderTargetChain.Flip;
begin
  m_nNext := 1 - m_nNext;
end;

function CRenderTargetChain.GetPrevTarget: IDirect3DTexture9;
begin
  Result:= m_pRenderTarget[1 - m_nNext];
end;

function CRenderTargetChain.GetPrevSource: IDirect3DTexture9;
begin
  Result:= m_pRenderTarget[m_nNext];
end;

function CRenderTargetChain.GetNextTarget: IDirect3DTexture9;
begin
  Result:= m_pRenderTarget[m_nNext];
end;

function CRenderTargetChain.GetNextSource: IDirect3DTexture9;
begin
  Result:= m_pRenderTarget[1 - m_nNext];
end;
procedure CRenderTargetChain.Init(const pRT: array of IDirect3DTexture9);
var
  i: Integer;
begin
  for i := 0 to 1 do m_pRenderTarget[i] := pRT[i];
end;



procedure CreateCustomDXUTobjects;
var
  i: Integer;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera:= CModelViewerCamera.Create;
  g_HUD:= CDXUTDialog.Create;
  g_SampleUI:= CDXUTDialog.Create;
  for i:= 0 to PPCOUNT-1 do g_aPostProcess[i]:= CPostProcess.Create;

  g_SceneMesh[0]:= CDXUTMesh.Create;
  g_SceneMesh[1]:= CDXUTMesh.Create;
  g_Skybox:= CDXUTMesh.Create;
  for i:= 0 to RT_COUNT-1 do g_RTChain[i]:= CRenderTargetChain.Create;
end;

procedure DestroyCustomDXUTobjects;
var
  i: Integer;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_Camera);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);
  for i:= 0 to PPCOUNT-1 do FreeAndNil(g_aPostProcess[i]);

  FreeAndNil(g_SceneMesh[0]);
  FreeAndNil(g_SceneMesh[1]);
  FreeAndNil(g_Skybox);
  for i:= 0 to RT_COUNT-1 do FreeAndNil(g_RTChain[i]);
end;

end.

