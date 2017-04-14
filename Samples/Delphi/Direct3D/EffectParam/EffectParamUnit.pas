(*----------------------------------------------------------------------------*
 *  Direct3D sample from DirectX 9.0 SDK December 2006                        *
 *  Delphi adaptation by Alexey Barkovoy (e-mail: clootie@ixbt.com)           *
 *                                                                            *
 *  Supported compilers: Delphi 5,6,7,9; FreePascal 2.0                       *
 *                                                                            *
 *  Latest version can be downloaded from:                                    *
 *     http://clootie.narod.ru                                                *
 *     http://sourceforge.net/projects/delphi-dx9sdk                          *
 *----------------------------------------------------------------------------*
 *  $Id: EffectParamUnit.pas,v 1.17 2007/02/05 22:21:05 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: EffectParam.cpp
//
// Starting point for new Direct3D applications
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit EffectParamUnit;

interface

uses
  Windows, Messages, SysUtils, Math, StrSafe, 
  DXTypes, Direct3D9, D3DX9, dxerr9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------

// SCROLL_TIME dictates the time one scroll op takes, in seconds.
const
  SCROLL_TIME = 0.5;

type  
  PMeshListData = ^TMeshListData;
  TMeshListData = record
    wszName: PWideChar; // array[0..MAX_PATH-1] of WideChar;
    wszFile: PWideChar; // array[0..MAX_PATH-1] of WideChar;
    dwNumMat: DWORD;    // Number of materials.  To be filled in when loading this mesh.
  end;

var
   g_MeshListData: array[0..6] of TMeshListData =
   (
    (wszName: 'Car';           wszFile: 'car2.x';                          dwNumMat: 0),
    (wszName: 'Banded Earth';  wszFile: 'sphereband.x';                    dwNumMat: 0),
    (wszName: 'Dwarf';         wszFile: 'dwarf\DwarfWithEffectInstance.x'; dwNumMat: 0),
    (wszName: 'Virus';         wszFile: 'cytovirus.x';                     dwNumMat: 0),
    (wszName: 'Car';           wszFile: 'car2.x';                          dwNumMat: 0),
    (wszName: 'Banded Earth';  wszFile: 'sphereband.x';                    dwNumMat: 0),
    (wszName: 'Dwarf';         wszFile: 'dwarf\DwarfWithEffectInstance.x'; dwNumMat: 0)
   );

type
  TMeshVertex = packed record
    Position: TD3DXVector3;
    Normal: TD3DXVector3;
    Tex: TD3DXVector2;
    // const static D3DVERTEXELEMENT9 Decl[4];
  end;

const
  TMeshVertex_Decl: array[0..3] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0;  _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITION; UsageIndex: 0),
    (Stream: 0; Offset: 12; _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_NORMAL;   UsageIndex: 0),
    (Stream: 0; Offset: 24; _Type: D3DDECLTYPE_FLOAT2; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TEXCOORD; UsageIndex: 0),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );


type
  TMeshMaterial = class
  private
    m_pEffect: ID3DXEffect;
    m_hParam: TD3DXHandle;
    m_pTexture: IDirect3DTexture9;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Assign(const rhs: TMeshMaterial);
  end;

  PMeshMaterialArray = ^TMeshMaterialArray;
  TMeshMaterialArray = array[0..MaxInt div SizeOf(TMeshMaterial)-1] of TMeshMaterial;


  TEffectMesh = class
  private
    m_wszMeshFile: array[0..MAX_PATH-1] of WideChar;
    m_pMesh: ID3DXMesh;
    m_pMaterials: array of TMeshMaterial; // TPMeshMaterialArray;
    m_dwNumMaterials: DWORD;

  public
    constructor Create; overload;
    constructor Copy(const old: TEffectMesh);
    destructor Destroy; override;
    procedure Assign(const rhs: TEffectMesh);

    function Create(wszFileName: PWideChar; pd3dDevice: IDirect3DDevice9): HRESULT; overload;
    procedure Render(const pd3dDevice: IDirect3DDevice9);

    property NumMaterials: DWORD read m_dwNumMaterials;
    property Mesh: ID3DXMesh read m_pMesh;
  end;


  CMeshArcBall = class(CD3DArcBall)
  public
    procedure OnBegin(nX, nY: Integer; const pmInvViewRotate: TD3DXMatrixA16);
    procedure OnMove(nX, nY: Integer; const pmInvViewRotate: TD3DXMatrixA16);
    function HandleMessages(hWnd: HWND; uMsg: Cardinal; wParam: WPARAM; lParam: LPARAM; const pmInvViewRotate: TD3DXMatrixA16): LRESULT;
  end;
  

//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont: ID3DXFont;                   // Font for drawing text
  g_pTextSprite: ID3DXSprite;           // Sprite for batching draw text calls
  g_pEffect: ID3DXEffect;               // D3DX effect interface
  g_pDecl: IDirect3DVertexDeclaration9; // Vertex decl for meshes
  g_pDefaultTex: IDirect3DTexture9;     // Default texture
  g_pEnvMapTex: IDirect3DCubeTexture9;  // Environment map texture
  g_dwShaderFlags: DWORD = D3DXFX_NOT_CLONEABLE; // Shader creation flag for all effects
  g_Camera: CModelViewerCamera;         // Camera for navigation
  g_ArcBall: array of CMeshArcBall;
  g_bShowHelp: Boolean = True;          // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg;       // Device settings dialog
  g_HUD: CDXUTDialog;                   // dialog for standard controls
  g_SampleUI: CDXUTDialog;              // dialog for sample specific controls
  g_pEffectPool: ID3DXEffectPool;       // Effect pool for sharing parameters

  g_Meshes: array of TEffectMesh;       // List of meshes being rendered
  g_amWorld: array of TD3DXMatrixA16;   // World transform for the meshes
  g_nActiveMesh: Integer = 0;
  g_mScroll: TD3DXMatrixA16;            // Scroll matrix
  g_fAngleToScroll: Single = 0.0;       // Total angle to scroll the meshes in radian, in current scroll op
  g_fAngleLeftToScroll: Single = 0.0;   // Angle left to scroll the meshes in radian


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_SHARE               = 5;
  IDC_SCROLLLEFT          = 6;
  IDC_SCROLLRIGHT         = 7;
  IDC_MESHNAME            = 8;
  IDC_MATCOUNT            = 9;



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

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;


implementation


//////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////

{ TMeshMaterial }

constructor TMeshMaterial.Create;
begin
  inherited Create;
  m_pEffect := nil;
  m_hParam := nil;
  m_pTexture := nil;
end;

destructor TMeshMaterial.Destroy;
begin
  m_pEffect := nil;
  m_pTexture := nil;
  inherited;
end;

procedure TMeshMaterial.Assign(const rhs: TMeshMaterial);
begin
  m_pEffect := rhs.m_pEffect;
  m_hParam := rhs.m_hParam;
  m_pTexture := rhs.m_pTexture;
end;

//////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////

constructor TEffectMesh.Create;
begin
  inherited Create;
  m_pMesh := nil;
  m_pMaterials := nil;
  m_dwNumMaterials := 0;
end;

constructor TEffectMesh.Copy(const old: TEffectMesh);
begin
  raise Exception.Create('TEffectMesh.Copy is finally called :-)');
  m_wszMeshFile:= old.m_wszMeshFile;
  m_pMesh:= old.m_pMesh;
  m_pMaterials:= old.m_pMaterials;
  m_dwNumMaterials:= old.m_dwNumMaterials;
end;

destructor TEffectMesh.Destroy;
var
  i: Integer;
begin
  for i:= 0 to Length(m_pMaterials) - 1 do m_pMaterials[i].Free;
  m_pMaterials:= nil;
  m_dwNumMaterials := 0;

  m_pMesh := nil;
  inherited;
end;

procedure TEffectMesh.Render(const pd3dDevice: IDirect3DDevice9);
var
  i: Integer;
  pMat: TMeshMaterial;
  cPasses: LongWord;
  p: Integer;
begin
  for i := 0 to m_dwNumMaterials - 1 do
  begin
    pMat := m_pMaterials[i];
    V_(pMat.m_pEffect.ApplyParameterBlock(pMat.m_hParam));

    V_(pMat.m_pEffect._Begin(@cPasses, 0));
    for p := 0 to cPasses - 1 do
    begin
      V_(pMat.m_pEffect.BeginPass(p));
      V_(m_pMesh.DrawSubset(i));
      V_(pMat.m_pEffect.EndPass);
    end;
    V_(pMat.m_pEffect._End);
  end;
end;

procedure TEffectMesh.Assign(const rhs: TEffectMesh);
var
  i: Integer;
begin
  StringCchCopy(m_wszMeshFile, MAX_PATH, rhs.m_wszMeshFile);
  m_dwNumMaterials := rhs.m_dwNumMaterials;
  m_pMesh := rhs.m_pMesh;

  for i:= 0 to Length(m_pMaterials) - 1 do m_pMaterials[i].Free;
  SetLength(m_pMaterials, m_dwNumMaterials);
  for i := 0 to m_dwNumMaterials - 1 do
  begin
    m_pMaterials[i] := TMeshMaterial.Create;
    m_pMaterials[i].Assign(rhs.m_pMaterials[i]);
  end;
end;


const
  INVALID_FILE_ATTRIBUTES = DWORD(-1);

type
  PD3DXEffectInstanceArray = ^TD3DXEffectInstanceArray;
  TD3DXEffectInstanceArray = array[0..MaxInt div SizeOf(TD3DXEffectInstance)-1] of TD3DXEffectInstance;

  PD3DXMaterialArray = ^TD3DXMaterialArray;
  TD3DXMaterialArray = array[0..0] of TD3DXMaterial;


function TEffectMesh.Create(wszFileName: PWideChar; pd3dDevice: IDirect3DDevice9): HRESULT;
var
  str: array[0..MAX_PATH-1] of WideChar;
  wszMeshPath: array[0..MAX_PATH-1] of WideChar;
  pAdjacency: ID3DXBuffer;
  pMaterials: ID3DXBuffer;
  pEffectInstance: ID3DXBuffer;
  dwNumMaterials: DWORD;
  bHasNormals: Boolean;
  pCloneMesh: ID3DXMesh;
  pLastBSlash: PWideChar;
  pXMats: PD3DXMaterialArray;
  pEI: PD3DXEffectInstanceArray;
  i: Integer;
  wszFxName: array[0..MAX_PATH-1] of WideChar;
  szTmp: array[0..MAX_PATH-1] of WideChar;
  hTech: TD3DXHandle;
  param: Integer;
  hHandle: TD3DXHandle;
  desc: TD3DXParameterDesc;
  EffectDefault: PD3DXEffectDefault;
  wszTexName: array[0..MAX_PATH-1] of WideChar; 
  hTexture: TD3DXHandle;
begin
  // Save the mesh filename
  StringCchCopy(m_wszMeshFile, MAX_PATH, wszFileName);

  Result:= DXUTFindDXSDKMediaFile(wszMeshPath, MAX_PATH, m_wszMeshFile);
  if V_Failed(Result) then Exit;
  Result:= D3DXLoadMeshFromXW(wszMeshPath, D3DXMESH_MANAGED, pd3dDevice,
                              @pAdjacency, @pMaterials, @pEffectInstance,
                              @dwNumMaterials, m_pMesh);
  if V_Failed(Result) then Exit;
  bHasNormals := (m_pMesh.GetFVF and D3DFVF_NORMAL) <> 0;
  Result:= m_pMesh.CloneMesh(m_pMesh.GetOptions, @TMeshVertex_Decl, pd3dDevice, pCloneMesh);
  if V_Failed(Result) then Exit;
  // m_pMesh := nil; //Clootie: not needed in Delphi
  m_pMesh := pCloneMesh;

  // Extract the path of the mesh file
  pLastBSlash := WideStrRScan(wszMeshPath, '\');
  if (pLastBSlash <> nil) then (pLastBSlash + 1)^ := #0
    else StringCchCopy(wszMeshPath, MAX_PATH, '.\');

  // Ensure the mesh has correct normals.
  if not bHasNormals then
    D3DXComputeNormals(m_pMesh, pAdjacency.GetBufferPointer);

  // Allocate material array
  try
    SetLength(m_pMaterials, dwNumMaterials);
    for i := 0 to dwNumMaterials - 1 do
      m_pMaterials[i] := TMeshMaterial.Create;
  except
    Result:= E_OUTOFMEMORY;
    Exit;
  end;

  pXMats := pMaterials.GetBufferPointer;
  pEI := pEffectInstance.GetBufferPointer;
  for i := 0 to dwNumMaterials - 1 do
  begin
    // Obtain the effect

    Result := S_OK;
    // Try the mesh's directory
    StringCchCopy(str, MAX_PATH, wszMeshPath);
    MultiByteToWideChar(CP_ACP, 0, pEI[i].pEffectFilename, -1, str + lstrlenW(str), MAX_PATH);

    if (pEI[i].pEffectFilename = nil) then Result:= E_FAIL;

    MultiByteToWideChar(CP_ACP, 0, pEI[i].pEffectFilename, -1, wszFxName, MAX_PATH);

    if SUCCEEDED(Result) then
    begin
      StringCchCopy(szTmp, MAX_PATH, 'SharedFx\');
      StringCchCat(szTmp, MAX_PATH, wszFxName);
      Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, szTmp);
      if FAILED(Result) then
      begin
        // Search the SDK paths
        Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, wszFxName);
      end;
    end;

    if SUCCEEDED(Result) then
      DXUTGetGlobalResourceCache.CreateEffectFromFile(pd3dDevice, str, nil, nil, g_dwShaderFlags, g_pEffectPool,
                                                      m_pMaterials[i].m_pEffect, nil);
    if (m_pMaterials[i].m_pEffect = nil) then
    begin
      // No valid effect for this material.  Use the default.
      m_pMaterials[i].m_pEffect := g_pEffect;
    end;

    // Set the technique this material should use
    m_pMaterials[i].m_pEffect.FindNextValidTechnique(nil, hTech);
    m_pMaterials[i].m_pEffect.SetTechnique(hTech);

    // Create a parameter block to include all parameters for the effect.
    m_pMaterials[i].m_pEffect.BeginParameterBlock;
    EffectDefault:= pEI[i].pDefaults;
    for param := 0 to pEI[i].NumDefaults - 1 do
    begin
      // hHandle := m_pMaterials[i].m_pEffect.GetParameterByName(nil, pEI[i].pDefaults[param].pParamName);
      hHandle := m_pMaterials[i].m_pEffect.GetParameterByName(nil, EffectDefault.pParamName);
      if (hHandle <> nil) then
      begin
        m_pMaterials[i].m_pEffect.GetParameterDesc(hHandle, desc);
        if (desc._Type = D3DXPT_BOOL) or
           (desc._Type = D3DXPT_INT) or
           (desc._Type = D3DXPT_FLOAT) or
           (desc._Type = D3DXPT_STRING) then
        begin
          {m_pMaterials[i].m_pEffect.SetValue(pEI[i].pDefaults[param].pParamName,
                                             pEI[i].pDefaults[param].pValue,
                                             pEI[i].pDefaults[param].NumBytes);}
          m_pMaterials[i].m_pEffect.SetValue(TD3DXHandle(EffectDefault.pParamName),
                                             EffectDefault.pValue,
                                             EffectDefault.NumBytes);
        end;
      end;
      Inc(EffectDefault);
    end;

    // Obtain the texture
    Result := S_OK;

    if Assigned(pXMats[i].pTextureFilename) then
    begin
      // Try the mesh's directory first.
      StringCchCopy(str, MAX_PATH, wszMeshPath);
      MultiByteToWideChar(CP_ACP, 0, pXMats[i].pTextureFilename, -1, str + lstrlenW(str), MAX_PATH);
      // If the texture file is not in the same directory as the mesh, search the SDK paths.
      if (GetFileAttributesW(str) = INVALID_FILE_ATTRIBUTES) then
      begin
        // Search the SDK paths
        MultiByteToWideChar(CP_ACP, 0, pXMats[i].pTextureFilename, -1, wszTexName, MAX_PATH);
        Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, wszTexName);
      end;

      if SUCCEEDED(Result) then
        DXUTGetGlobalResourceCache.CreateTextureFromFile(pd3dDevice, str, m_pMaterials[i].m_pTexture);
    end;

    if (m_pMaterials[i].m_pTexture = nil) then
    begin
      // No texture or texture fails to load. Use the default texture.
      m_pMaterials[i].m_pTexture := g_pDefaultTex;
    end;

    // Include the texture in the parameter block if the effect requires one.
    hTexture := m_pMaterials[i].m_pEffect.GetParameterByName(nil, 'g_txScene');
    if Assigned(hTexture) then
      m_pMaterials[i].m_pEffect.SetTexture(hTexture, m_pMaterials[i].m_pTexture);

    // Include the environment map texture in the parameter block if the effect requires one.
    hTexture := m_pMaterials[i].m_pEffect.GetParameterByName(nil, 'g_txEnvMap');
    if Assigned(hTexture) then
      m_pMaterials[i].m_pEffect.SetTexture(hTexture, g_pEnvMapTex);

    // Save the parameter block
    m_pMaterials[i].m_hParam := m_pMaterials[i].m_pEffect.EndParameterBlock;
  end;

  pAdjacency := nil;
  pMaterials := nil;
  pEffectInstance := nil;
  m_dwNumMaterials := dwNumMaterials;
  Result:= S_OK;
end;


//////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////

{ CMeshArcBall }

procedure CMeshArcBall.OnBegin(nX, nY: Integer; const pmInvViewRotate: TD3DXMatrixA16);
var
  v: TD3DXVector4;
begin
  m_bDrag := True;
  m_qDown := m_qNow;
  m_vDownPt := ScreenToVector(nX, nY);
  D3DXVec3Transform(v, m_vDownPt, pmInvViewRotate);
  m_vDownPt := PD3DXVector3(@v)^;
end;

procedure CMeshArcBall.OnMove(nX, nY: Integer; const pmInvViewRotate: TD3DXMatrixA16);
var
  v: TD3DXVector4;
begin
  if (m_bDrag) then
  begin
    m_vCurrentPt := ScreenToVector(nX, nY);
    D3DXVec3Transform(v, m_vCurrentPt, pmInvViewRotate);
    m_vCurrentPt := PD3DXVector3(@v)^;
    D3DXQuaternionMultiply(m_qNow, m_qDown, QuatFromBallPoints(m_vDownPt, m_vCurrentPt));
  end;
end;

function CMeshArcBall.HandleMessages(hWnd: HWND; uMsg: Cardinal;
  wParam: WPARAM; lParam: LPARAM;
  const pmInvViewRotate: TD3DXMatrixA16): LRESULT;
var
  iMouseX: Integer;
  iMouseY: Integer;
begin
  // Current mouse position
  iMouseX := LOWORD(lParam);
  iMouseY := HIWORD(lParam);

  Result:= iTrue;

  case uMsg of
    WM_LBUTTONDOWN,
    WM_LBUTTONDBLCLK:
    begin
      SetCapture(hWnd);
      OnBegin(iMouseX, iMouseY, pmInvViewRotate);
    end;

    WM_LBUTTONUP:
    begin
      ReleaseCapture;
      OnEnd;
    end;

    WM_CAPTURECHANGED:
    begin
      if (THandle(lParam) <> hWnd) then
      begin
        ReleaseCapture;
        OnEnd;
      end;
    end;

    WM_MOUSEMOVE:
    begin
      if (MK_LBUTTON and wParam <> 0) then
      begin
        OnMove(iMouseX, iMouseY, pmInvViewRotate);
      end;
    end;

  else
    Result:= iFalse;
  end;
end;


//////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////


//--------------------------------------------------------------------------------------
// Initialize the app
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  iY: Integer;
  i: Integer;
  l: LongWord;
  vecEye: TD3DXVector3;
  vecAt: TD3DXVector3;
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

  iY := 0;     g_SampleUI.AddStatic(IDC_MESHNAME, 'Mesh Name', 0, iY, 160, 20);
  Inc(iY, 20); g_SampleUI.AddStatic(IDC_MATCOUNT, 'Number of materials: 0', 0, iY, 160, 20);
  Inc(iY, 24); g_SampleUI.AddButton(IDC_SCROLLLEFT,  '<<',  5, iY, 70, 24);
               g_SampleUI.AddButton(IDC_SCROLLRIGHT, '>>', 85, iY, 70, 24);
  Inc(iY, 32); g_SampleUI.AddCheckBox(IDC_SHARE, 'Enable shared parameters', 0, iY, 160, 24, True);

  // Initialize the arcball
  for i := 0 to High(g_MeshListData) do // SizeOf(g_MeshListData)/SizeOf(g_MeshListData[0]); ++i )
  begin
    // g_ArcBall.Add(CMeshArcBall);
    l:= Length(g_ArcBall);
    SetLength(g_ArcBall, l+1);
    g_ArcBall[l]:= CMeshArcBall.Create;
    g_ArcBall[l].SetTranslationRadius(2.0);
  end;

  // Setup the cameras
  vecEye := D3DXVector3(0.0, 0.0, -5.0);
  vecAt := D3DXVector3(0.0, 0.0, -3.0);
  g_Camera.SetViewParams(vecEye, vecAt);
  g_Camera.SetButtonMasks(0, MOUSE_WHEEL, 0);
  g_Camera.SetRadius(5.0, 1.0);
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

  // Needs PS 1.1 support
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(1,1)) then Exit;

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
var
  bSvp, bHvp, bPHvp, bMvp: Boolean;
begin
  // Turn vsync off
  pDeviceSettings.pp.PresentationInterval := D3DPRESENT_INTERVAL_IMMEDIATE;
  g_SettingsDlg.DialogControl.GetComboBox(DXUTSETTINGSDLG_PRESENT_INTERVAL).Enabled := False;

  // If device doesn't support HW T&L or doesn't support 2.0 vertex shaders in HW
  // then switch to SWVP.
  if (pCaps.DevCaps and D3DDEVCAPS_HWTRANSFORMANDLIGHT = 0) or
     (pCaps.VertexShaderVersion < D3DVS_VERSION(2,0))
  then pDeviceSettings.BehaviorFlags := D3DCREATE_SOFTWARE_VERTEXPROCESSING;

  // If the hardware cannot do vertex blending, use software vertex processing.
  if (pCaps.MaxVertexBlendMatrices < 2)
  then pDeviceSettings.BehaviorFlags := D3DCREATE_SOFTWARE_VERTEXPROCESSING;

  // If using hardware vertex processing, change to mixed vertex processing
  // so there is a fallback.
  if (pDeviceSettings.BehaviorFlags and D3DCREATE_HARDWARE_VERTEXPROCESSING = 0)
  then pDeviceSettings.BehaviorFlags := D3DCREATE_MIXED_VERTEXPROCESSING;

  // Add mixed vp to the available vp choices in device settings dialog.
  DXUTGetEnumeration.GetPossibleVertexProcessingList(bSvp, bHvp, bPHvp, bMvp);
  DXUTGetEnumeration.SetPossibleVertexProcessingList(bSvp, False, False, True);

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
  str: WideString;
  lr: TD3DLockedRect;
  i, l: Integer;
  NewMesh: TEffectMesh;
  mW: TD3DXMatrixA16;
  pVerts: Pointer;
  vCtr: TD3DXVector3;
  fRadius: Single;
  m: TD3DXMatrixA16;
  pD3DSD: PD3DSurfaceDesc;
begin
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  // Create the effect pool object if shared param is enabled
  if g_SampleUI.CheckBox[IDC_SHARE].Checked then
  begin
    Result:= D3DXCreateEffectPool(g_pEffectPool);
    if V_Failed(Result) then Exit;
  end;

  // Create the vertex decl
  Result:= pd3dDevice.CreateVertexDeclaration(@TMeshVertex_Decl, g_pDecl);
  if V_Failed(Result) then Exit;
  pd3dDevice.SetVertexDeclaration(g_pDecl);

  // Create the 1x1 white default texture
  Result:= pd3dDevice.CreateTexture(1, 1, 1, 0, D3DFMT_A8R8G8B8,
                                    D3DPOOL_MANAGED, g_pDefaultTex, nil);
    if V_Failed(Result) then Exit;
  Result:= g_pDefaultTex.LockRect(0, lr, nil, 0);
    if V_Failed(Result) then Exit;
  PDWORD(lr.pBits)^ := D3DCOLOR_RGBA(255, 255, 255, 255);
  Result:= g_pDefaultTex.UnlockRect(0);
    if V_Failed(Result) then Exit;

  // Create the environment map texture
  Result:= DXUTFindDXSDKMediaFile(str, 'lobby\lobbycube.dds');
  if V_Failed(Result) then Exit;
  Result:= D3DXCreateCubeTextureFromFileW(pd3dDevice, PWideChar(str), g_pEnvMapTex);
  if V_Failed(Result) then Exit;

  // Initialize the font
  Result:= DXUTGetGlobalResourceCache.CreateFont(pd3dDevice, 15, 0, FW_BOLD, 0, FALSE, DEFAULT_CHARSET,
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

  {$IFDEF DEBUG}
  // Set the D3DXSHADER_DEBUG flag to embed debug information in the shaders.
  // Setting this flag improves the shader debugging experience, but still allows
  // the shaders to be optimized and to run exactly the way they will run in
  // the release configuration of this program.
  g_dwShaderFlags := g_dwShaderFlags or D3DXSHADER_DEBUG;
  {$ENDIF}

  {$IFDEF DEBUG_VS}
  g_dwShaderFlags := g_dwShaderFlags or D3DXSHADER_FORCE_VS_SOFTWARE_NOOPT;
  {$ENDIF}
  {$IFDEF DEBUG_PS}
  g_dwShaderFlags := g_dwShaderFlags or D3DXSHADER_FORCE_PS_SOFTWARE_NOOPT;
  {$ENDIF}

  // Read the D3DX effect file
  Result:= DXUTFindDXSDKMediaFile(str, 'EffectParam.fx');
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // they the .fx file failed to compile
  Result:= DXUTGetGlobalResourceCache.CreateEffectFromFile(pd3dDevice, PWideChar(str), nil, nil, g_dwShaderFlags,
                                                           g_pEffectPool, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  // Create the meshes
  for i := 0 to High(g_MeshListData) do // ; i < SizeOf(g_MeshListData)/SizeOf(g_MeshListData[0]); ++i )
  begin
    NewMesh := TEffectMesh.Create;
    if SUCCEEDED(NewMesh.Create(g_MeshListData[i].wszFile, DXUTGetD3DDevice)) then
    begin
      // g_Meshes.Add(NewMesh);
      l:= Length(g_Meshes);
      SetLength(g_Meshes, l+1);
      g_Meshes[l]:= NewMesh;

      pVerts := nil;
      D3DXMatrixIdentity(mW);
      if SUCCEEDED(NewMesh.Mesh.LockVertexBuffer(0, pVerts)) then
      begin
        if SUCCEEDED(D3DXComputeBoundingSphere(pVerts,
                                               NewMesh.Mesh.GetNumVertices,
                                               NewMesh.Mesh.GetNumBytesPerVertex,
                                               vCtr, fRadius)) then
        begin
          D3DXMatrixTranslation(mW, -vCtr.x, -vCtr.y, -vCtr.z);
          D3DXMatrixScaling(m, 1.0 / fRadius,
                               1.0 / fRadius,
                               1.0 / fRadius);
          D3DXMatrixMultiply(mW, mW, m);
        end;
        NewMesh.Mesh.UnlockVertexBuffer;
      end;

      g_MeshListData[i].dwNumMat := NewMesh.NumMaterials;
      // g_amWorld.Add(mW);
      l:= Length(g_amWorld);
      SetLength(g_amWorld, l+1);
      g_amWorld[l]:= mW;

      // Set the arcball window size
      pD3DSD := DXUTGetBackBufferSurfaceDesc;
      g_ArcBall[Length(g_ArcBall)-1].SetWindow(pD3DSD.Width, pD3DSD.Height);
    end;
  end;

  g_SampleUI.Static[IDC_MESHNAME].Text := g_MeshListData[g_nActiveMesh].wszName;
  g_SampleUI.Static[IDC_MATCOUNT].Text := PWideChar(WideFormat('Number of materials: %u', [g_MeshListData[g_nActiveMesh].dwNumMat]));

  D3DXMatrixIdentity(g_mScroll);

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
  i: Integer;
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
  for i := 0 to Length(g_ArcBall) - 1 do
    g_ArcBall[i].SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation((pBackBufferSurfaceDesc.Width-170) div 2, pBackBufferSurfaceDesc.Height-120);
  g_SampleUI.SetSize(170, 120);

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
  fFrameAngleToScroll: Single;
  m: TD3DXMatrixA16;
begin
  // Update the scroll matrix
  fFrameAngleToScroll := g_fAngleToScroll * fElapsedTime / SCROLL_TIME;
  if (Abs(fFrameAngleToScroll) > Abs(g_fAngleLeftToScroll)) then
    fFrameAngleToScroll := g_fAngleLeftToScroll;
  g_fAngleLeftToScroll := g_fAngleLeftToScroll - fFrameAngleToScroll;
  D3DXMatrixRotationY(m, fFrameAngleToScroll);
  D3DXMatrixMultiply(g_mScroll, g_mScroll, m);
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
  mWorld, mWorldView, mViewProj: TD3DXMatrixA16;
  mWorldViewProjection: TD3DXMatrixA16;
  vLightView: TD3DXVector4;
  fAngleDelta: Single;
  i: Integer;
  mRot, mTrans, m: TD3DXMatrixA16;
  mViewInv: TD3DXMatrixA16;
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  // Clear the render target and the zbuffer
  V_(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, D3DCOLOR_ARGB(0, 66, 75, 121), 1.0, 0));

  // Render the scene
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    // Get the projection & view matrix from the camera class
    D3DXMatrixMultiply(mViewProj, g_Camera.GetViewMatrix^, g_Camera.GetProjMatrix^);

    // Update the effect's variables.  Instead of using strings, it would
    // be more efficient to cache a handle to the parameter by calling
    // ID3DXEffect::GetParameterByName
///////////////////////////////////////////////////////////////////////
    D3DXMatrixInverse(mViewInv, nil, g_Camera.GetViewMatrix^);
//    g_pEffect.SetMatrix('g_mViewInv', mViewInv);
///////////////////////////////////////////////////////////////////////
    vLightView := D3DXVector4(0.0, 0.0, -10.0, 1.0);
    V_(g_pEffect.SetVector('g_vLight', vLightView));

    fAngleDelta := D3DX_PI * 2.0 / Length(g_Meshes);
    for i := 0 to Length(g_Meshes) - 1 do
    begin
      D3DXMatrixMultiply(mWorld, g_ArcBall[i].GetRotationMatrix^, g_ArcBall[i].GetTranslationMatrix^);
      D3DXMatrixMultiply(mWorld, g_amWorld[i], mWorld);
      D3DXMatrixTranslation(mTrans, 0.0, 0.0, -3.0);
      D3DXMatrixRotationY(mRot, fAngleDelta * (i - g_nActiveMesh));
      // mWorld *= mTrans * mRot * g_mScroll;
      D3DXMatrixMultiply(m, mTrans, mRot);
      D3DXMatrixMultiply(m, m, g_mScroll);
      D3DXMatrixMultiply(mWorld, mWorld, m);

      D3DXMatrixMultiply(mWorldView, mWorld, g_Camera.GetViewMatrix^);
      D3DXMatrixMultiply(mWorldViewProjection, mWorld, mViewProj);

///////////////////////////////////////////////////////////////////
//      V(g_pEffect.SetMatrix('g_mWorldViewProjection', mWorldViewProjection));
//      V(g_pEffect.SetMatrix('g_mWorldView', mWorldView));
///////////////////////////////////////////////////////////////////
      V(g_pEffect.SetMatrix('g_mWorld', mWorld));
      V(g_pEffect.SetMatrix('g_mView', g_Camera.GetViewMatrix^));
      V(g_pEffect.SetMatrix('g_mProj', g_Camera.GetProjMatrix^));
      g_Meshes[i].Render(pd3dDevice);
    end; 

    RenderText;
    V_(g_HUD.OnRender(fElapsedTime));
    V_(g_SampleUI.OnRender(fElapsedTime));

    V_(pd3dDevice.EndScene);
  end;

  if (g_fAngleLeftToScroll = 0.0) then D3DXMatrixIdentity(g_mScroll);
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

  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
  txtHelper.DrawFormattedTextLine('Number of meshes: %d'#10, [Length(g_Meshes)]);

  // Draw help
  if g_bShowHelp then
  begin
    pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*6);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
    txtHelper.DrawTextLine('Controls (F1 to hide):');

    txtHelper.SetInsertionPos(40, pd3dsdBackBuffer.Height-15*5);
    txtHelper.DrawTextLine('Rotate Mesh: Left mouse drag'#10+
                           'Zoom: Mouse wheel'#10+
                           'Quit: ESC');
  end else
  begin
    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
    txtHelper.DrawTextLine('Press F1 for help');
  end;

  // Draw shared param description
  txtHelper.SetInsertionPos(5, 50);
  if Assigned(g_pEffectPool) then
  begin
    txtHelper.SetForegroundColor(D3DXColor(0.0, 1.0, 0.0, 1.0));
    txtHelper.DrawTextLine('Shared parameters are enabled.  When updating transformation'#10+
                           'matrices on one effect object, all effect objects automatically'#10+
                           'see the updated values.');
  end else
  begin
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.0, 0.0, 1.0));
    txtHelper.DrawTextLine('Shared parameters are disabled.  When transformation matrices'#10+
                           'are updated on the default effect object (diffuse only), only that'#10+
                           'effect object has the up-to-date values.  All other effect objects'#10+
                           'do not have valid matrices for rendering.');
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
var
  mViewRotate: TD3DXMatrixA16;
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
  mViewRotate := g_Camera.GetViewMatrix^;
  mViewRotate._41 := 0.0; mViewRotate._42 := 0.0; mViewRotate._43 := 0.0;
  D3DXMatrixInverse(mViewRotate, nil, mViewRotate);
  if (Length(g_ArcBall) > 0) then
    g_ArcBall[g_nActiveMesh].HandleMessages(hWnd, uMsg, wParam, lParam, mViewRotate);
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
    IDC_TOGGLEREF: DXUTToggleREF;
    IDC_CHANGEDEVICE: with g_SettingsDlg do Active := not Active;

    IDC_SHARE:
    begin
      // Shared param status changed. Destroy and recreate everything
      // with or without effect pool as appropriate.
      if (DXUTGetD3DDevice <> nil) then
      begin
        // We need to call the callbacks of the resource manager or the ref
        // count will not reach 0.

        OnLostDevice(nil);
        DXUTGetGlobalResourceCache.OnLostDevice;
        OnDestroyDevice(nil);
        DXUTGetGlobalResourceCache.OnDestroyDevice;
        OnCreateDevice(DXUTGetD3DDevice, DXUTGetBackBufferSurfaceDesc^, nil);
        DXUTGetGlobalResourceCache.OnCreateDevice(DXUTGetD3DDevice);
        OnResetDevice(DXUTGetD3DDevice, DXUTGetBackBufferSurfaceDesc^, nil);
        DXUTGetGlobalResourceCache.OnResetDevice(DXUTGetD3DDevice);
      end;
    end;

    IDC_SCROLLLEFT,
    IDC_SCROLLRIGHT:
    begin
      // Only scroll if we have more than one mesh
      if (Length(g_Meshes) <= 1) then Exit;

      // Only scroll if we are not already scrolling
      if (g_fAngleLeftToScroll <> 0.0) then Exit;

      // Compute the angle to scroll
      {g_fAngleToScroll = g_fAngleLeftToScroll = nControlID == IDC_SCROLLLEFT ? -D3DX_PI * 2.0f / g_Meshes.GetSize() :
                                                                               D3DX_PI * 2.0f / g_Meshes.GetSize();}
      g_fAngleLeftToScroll := IfThen(nControlID = IDC_SCROLLLEFT,
                                     -D3DX_PI * 2.0 / Length(g_Meshes),
                                      D3DX_PI * 2.0 / Length(g_Meshes));
      g_fAngleToScroll := g_fAngleLeftToScroll;

      // Initialize the scroll matrix to be reverse full-angle rotation,
      // then gradually decrease to zero (identity).
      D3DXMatrixRotationY(g_mScroll, -g_fAngleToScroll);
      // Update front mesh index
      if (nControlID = IDC_SCROLLLEFT) then
      begin
        Inc(g_nActiveMesh);
        if (g_nActiveMesh = Length(g_Meshes)) then g_nActiveMesh := 0;
      end else
      begin
        Dec(g_nActiveMesh);
        if (g_nActiveMesh < 0) then g_nActiveMesh := Length(g_Meshes) - 1;
      end;

      // Update mesh name and material count
      g_SampleUI.Static[IDC_MESHNAME].Text := g_MeshListData[g_nActiveMesh].wszName;
      g_SampleUI.Static[IDC_MATCOUNT].Text := PWideChar(WideFormat('Number of materials: %u', [g_MeshListData[g_nActiveMesh].dwNumMat]));
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
  g_pTextSprite := nil;
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

  g_pEffect := nil;
  g_pFont := nil;
  g_pDefaultTex := nil;
  g_pEffectPool := nil;
  g_pDecl := nil;
  g_pEnvMapTex := nil;

  for i := 0 to Length(g_Meshes) - 1 do g_Meshes[i].Destroy;
  g_Meshes := nil;

  g_amWorld := nil; 
end;


procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera:= CModelViewerCamera.Create;  // A model viewing camera
  g_HUD:= CDXUTDialog.Create;            // dialog for standard controls
  g_SampleUI:= CDXUTDialog.Create;       // dialog for sample specific controls
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

