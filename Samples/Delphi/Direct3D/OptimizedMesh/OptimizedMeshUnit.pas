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
 *  $Id: OptimizedMeshUnit.pas,v 1.17 2007/02/05 22:21:10 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: OptimizedMesh.cpp
//
// Starting point for new Direct3D applications
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit OptimizedMeshUnit;

interface

uses
  Windows, SysUtils, StrSafe,
  DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders


const
  MESHFILENAME = 'misc\knot.x';


type
  PStripData = ^TStripData;
  TStripData = record
    m_pStrips: IDirect3DIndexBuffer9;          // strip indices (single strip)
    m_pStripsMany: IDirect3DIndexBuffer9;      // strip indices (many strips)

    m_cStripIndices: DWORD;
    m_rgcStripLengths: PDWordArray;
    m_cStrips: DWORD;
{    SStripData() :
        m_pStrips(NULL),
        m_pStripsMany(NULL),
        m_cStripIndices(0),
        m_rgcStripLengths(NULL)}
  end;


   TMeshData = class
    m_pMeshSysMem: ID3DXMesh;                  // System memory copy of mesh

    m_pMesh: ID3DXMesh;                        // Local version of mesh, copied on resize
    m_pVertexBuffer: IDirect3DVertexBuffer9;   // vertex buffer of mesh

    m_rgStripData: array of TStripData;        // strip indices split by attribute
    m_cStripDatas: DWORD;

    constructor Create;
    procedure ReleaseLocalMeshes;
    procedure ReleaseAll;
  end;

type
  PD3DXMaterialArray = ^TD3DXMaterialArray;
  TD3DXMaterialArray = array[0..0] of TD3DXMaterial;

//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont: ID3DXFont;                    // Font for drawing text
  g_pTextSprite: ID3DXSprite;            // Sprite for batching draw text calls
  g_pEffect: ID3DXEffect;                // D3DX effect interface
  g_Camera: CModelViewerCamera;          // A model viewing camera
  g_pDefaultTex: IDirect3DTexture9;      // A default texture
  g_bShowHelp: Boolean = True;           // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg;        // Device settings dialog
  g_HUD: CDXUTDialog;                    // dialog for standard controls
  g_SampleUI: CDXUTDialog;               // dialog for sample specific controls
  g_bShowVertexCacheOptimized: Boolean = True;
  g_bShowStripReordered: Boolean = False;
  g_bShowStrips: Boolean = False;
  g_bShowSingleStrip: Boolean = False;
  g_bForce32ByteFVF: Boolean = True;
  g_bCantDoSingleStrip: Boolean = False; // Single strip would be too many primitives
  g_vObjectCenter: TD3DXVector3;         // Center of bounding sphere of object
  g_fObjectRadius: Single;               // Radius of bounding sphere of object
  g_matWorld: TD3DXMatrixA16;
  g_cObjectsPerSide: Integer = 1;        // sqrt of the number of objects to draw
  g_dwMemoryOptions: DWORD = D3DXMESH_MANAGED;
  // various forms of mesh data
  g_MeshAttrSorted: TMeshData;
  g_MeshStripReordered: TMeshData;
  g_MeshVertexCacheOptimized: TMeshData;

  g_dwNumMaterials: DWORD = 0;           // Number of materials
  g_ppMeshTextures: array of IDirect3DTexture9;
  g_pMeshMaterials: array of TD3DMaterial9;


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_MESHTYPE            = 5;
  IDC_GRIDSIZE            = 6;
  IDC_PRIMTYPE            = 7;


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
//todo: Fill bug report to MS
//function LoadMesh(const pd3dDevice: IDirect3DDevice9; strFileName: PWideChar; out ppMesh: ID3DXMesh): HRESULT;
procedure RenderText;
function LoadMeshData(const pd3dDevice: IDirect3DDevice9; wszMeshFile: PWideChar; out pMeshSysMemLoaded: ID3DXMesh; ppAdjacencyBuffer: PID3DXBuffer): HRESULT;
function OptimizeMeshData(pMeshSysMem: ID3DXMesh; pAdjacencyBuffer: ID3DXBuffer; dwOptFlags: DWORD; pMeshData: TMeshData): HRESULT;
function UpdateLocalMeshes(const pd3dDevice: IDirect3DDevice9; pMeshData: TMeshData): HRESULT;
function DrawMeshData(const pd3dDevice: IDirect3DDevice9; const pEffect: ID3DXEffect; pMeshData: TMeshData): HRESULT;

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;

implementation


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
  Inc(iY, 24); g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 35, iY, 125, 22, VK_F2); // Inc(iY, 24);

  g_SampleUI.SetCallback(OnGUIEvent); iY := 10;

  Inc(iY, 24);
  g_SampleUI.AddComboBox(IDC_MESHTYPE, 0, iY, 200, 20, Ord('M'));
  g_SampleUI.GetComboBox(IDC_MESHTYPE).AddItem('(M)esh type: VCache optimized', Pointer(0));
  g_SampleUI.GetComboBox(IDC_MESHTYPE).AddItem('(M)esh type: Strip reordered', Pointer(1));
  g_SampleUI.GetComboBox(IDC_MESHTYPE).AddItem('(M)esh type: Unoptimized', Pointer(2));
  Inc(iY, 24);
  g_SampleUI.AddComboBox(IDC_PRIMTYPE, 0, iY, 200, 20, Ord('P'));
  g_SampleUI.GetComboBox(IDC_PRIMTYPE).AddItem('(P)rimitive: Triangle list',    Pointer(0));
  g_SampleUI.GetComboBox(IDC_PRIMTYPE).AddItem('(P)rimitive: Single tri strip', Pointer(1));
  g_SampleUI.GetComboBox(IDC_PRIMTYPE).AddItem('(P)rimitive: Many tri strips',  Pointer(2));
  Inc(iY, 24);
  g_SampleUI.AddComboBox(IDC_GRIDSIZE, 0, iY, 200, 20, Ord('G'));
  g_SampleUI.GetComboBox(IDC_GRIDSIZE).AddItem('(G)rid size: 1 mesh',  Pointer(1));
  g_SampleUI.GetComboBox(IDC_GRIDSIZE).AddItem('(G)rid size: 4 mesh',  Pointer(2));
  g_SampleUI.GetComboBox(IDC_GRIDSIZE).AddItem('(G)rid size: 9 mesh',  Pointer(3));
  g_SampleUI.GetComboBox(IDC_GRIDSIZE).AddItem('(G)rid size: 16 mesh', Pointer(4));
  g_SampleUI.GetComboBox(IDC_GRIDSIZE).AddItem('(G)rid size: 25 mesh', Pointer(5));
  g_SampleUI.GetComboBox(IDC_GRIDSIZE).AddItem('(G)rid size: 36 mesh', Pointer(6));

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

  // Skip backbuffer formats that don't support alpha blending
  pD3D := DXUTGetD3DObject;
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                   AdapterFormat, D3DUSAGE_QUERY_POSTPIXELSHADER_BLENDING,
                   D3DRTYPE_TEXTURE, BackBufferFormat))
  then Exit;

  // No fallback defined by this app, so reject any device that
  // doesn't support at least ps2.0
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2,0)) then Exit;

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


function LoadMeshData(const pd3dDevice: IDirect3DDevice9; wszMeshFile: PWideChar; out pMeshSysMemLoaded: ID3DXMesh; ppAdjacencyBuffer: PID3DXBuffer): HRESULT;
var
  pMeshVB: IDirect3DVertexBuffer9;
  pD3DXMtrlBuffer: ID3DXBuffer;
  pVertices: Pointer;
  strMesh: WideString;
  pMeshSysMem: ID3DXMesh;
  pMeshTemp: ID3DXMesh;
  d3dxMaterials: PD3DXMaterialArray;
  i: Integer;
  strPath: array[0..511] of WideChar;
  wszBuf: array[0..MAX_PATH-1] of WideChar;
  bNormalsInFile: Boolean;
begin
  // Get a path to the media file
  Result:= DXUTFindDXSDKMediaFile(strMesh, wszMeshFile);
  if Failed(Result) then Exit;

  // Load the mesh from the specified file
  Result := D3DXLoadMeshFromXW(PWideChar(strMesh), D3DXMESH_SYSTEMMEM, pd3dDevice,
                               ppAdjacencyBuffer, @pD3DXMtrlBuffer, nil,
                               @g_dwNumMaterials, pMeshSysMem);
  if Failed(Result) then Exit;

  // Get the array of materials out of the returned buffer, and allocate a texture array
  d3dxMaterials := PD3DXMaterialArray(pD3DXMtrlBuffer.GetBufferPointer);
  try
    SetLength(g_pMeshMaterials, g_dwNumMaterials);
    SetLength(g_ppMeshTextures, g_dwNumMaterials);
  except
    Result := E_OUTOFMEMORY;
    Exit;
  end;

  for i := 0 to g_dwNumMaterials - 1 do
  begin
    g_pMeshMaterials[i] := d3dxMaterials[i].MatD3D;
    g_pMeshMaterials[i].Ambient := g_pMeshMaterials[i].Diffuse;
    g_ppMeshTextures[i] := nil;

    // Get a path to the texture
    if (d3dxMaterials[i].pTextureFilename <> nil) then
    begin
      // WCHAR wszBuf[MAX_PATH];
      MultiByteToWideChar(CP_ACP, 0, d3dxMaterials[i].pTextureFilename, -1, wszBuf, MAX_PATH);
      wszBuf[MAX_PATH - 1] := #0;
      DXUTFindDXSDKMediaFile(strPath, 255, wszBuf);

      // Load the texture
      D3DXCreateTextureFromFileW(pd3dDevice, strPath, g_ppMeshTextures[i]);
    end else
    begin
      // Use the default texture
      g_ppMeshTextures[i] := g_pDefaultTex;
    end;
  end;

  // Done with the material buffer
  pD3DXMtrlBuffer := nil;

  // Lock the vertex buffer, to generate a simple bounding sphere
  Result := pMeshSysMem.GetVertexBuffer(pMeshVB);
  if SUCCEEDED(Result) then
  begin
    Result := pMeshVB.Lock(0, 0, pVertices, D3DLOCK_NOSYSLOCK);
    if SUCCEEDED(Result) then
    begin
      D3DXComputeBoundingSphere(PD3DXVector3(pVertices), pMeshSysMem.GetNumVertices,
                                 D3DXGetFVFVertexSize(pMeshSysMem.GetFVF),
                                 g_vObjectCenter, g_fObjectRadius);
      pMeshVB.Unlock;
    end;
    pMeshVB := nil;
  end else
    Exit;

  // remember if there were normals in the file, before possible clone operation
  bNormalsInFile := (pMeshSysMem.GetFVF and D3DFVF_NORMAL <> 0);

  // if using 32byte vertices, check fvf
  if g_bForce32ByteFVF then
  begin
    // force 32 byte vertices
    if (pMeshSysMem.GetFVF <> (D3DFVF_XYZ or D3DFVF_NORMAL or D3DFVF_TEX1)) then
    begin
      Result := pMeshSysMem.CloneMeshFVF(pMeshSysMem.GetOptions, D3DFVF_XYZ or D3DFVF_NORMAL or D3DFVF_TEX1,
                                         pd3dDevice, pMeshTemp);
      if Failed(Result) then Exit;

      pMeshSysMem := pMeshTemp;
    end;
  end
  // otherwise, just make sure that there are normals in mesh
  else if (pMeshSysMem.GetFVF and D3DFVF_NORMAL = 0) then
  begin
    Result := pMeshSysMem.CloneMeshFVF(pMeshSysMem.GetOptions, pMeshSysMem.GetFVF or D3DFVF_NORMAL,
                                       pd3dDevice, pMeshTemp);
    if Failed(Result) then Exit;

    pMeshSysMem := pMeshTemp;
  end;

  // Compute normals for the mesh, if not present
  if not bNormalsInFile then D3DXComputeNormals(pMeshSysMem, nil);

  pMeshSysMemLoaded := pMeshSysMem;
  pMeshSysMem := nil; // Just in case ;-)
end;


function OptimizeMeshData(pMeshSysMem: ID3DXMesh; pAdjacencyBuffer: ID3DXBuffer; dwOptFlags: DWORD; pMeshData: TMeshData): HRESULT;
//HRESULT OptimizeMeshData( LPD3DXMESH pMeshSysMem, LPD3DXBUFFER pAdjacencyBuffer, DWORD dwOptFlags, SMeshData *pMeshData )
var
  pbufTemp: ID3DXBuffer;
  iMaterial: Integer;
  primCount: LongWord;
  pd3dDevice: IDirect3DDevice9;
  d3dCaps: TD3DCaps9;
begin
  // Attribute sort - the un-optimized mesh option
  // remember the adjacency for the vertex cache optimization
  Result := pMeshSysMem.Optimize(dwOptFlags or D3DXMESH_SYSTEMMEM,
                                 pAdjacencyBuffer.GetBufferPointer,
                                 nil, nil, nil, pMeshData.m_pMeshSysMem);
  if Failed(Result) then Exit;

  pMeshData.m_cStripDatas := g_dwNumMaterials;
  try
    SetLength(pMeshData.m_rgStripData, pMeshData.m_cStripDatas);
  except
    Result := E_OUTOFMEMORY;
    Exit;
  end;

  g_bCantDoSingleStrip := False;
  for iMaterial := 0 to g_dwNumMaterials - 1 do
  begin
    Result := D3DXConvertMeshSubsetToSingleStrip(pMeshData.m_pMeshSysMem, iMaterial,
                  D3DXMESH_IB_MANAGED, pMeshData.m_rgStripData[iMaterial].m_pStrips,
                  @pMeshData.m_rgStripData[iMaterial].m_cStripIndices);
    if Failed(Result) then Exit;

    primCount := pMeshData.m_rgStripData[iMaterial].m_cStripIndices - 2;

    pMeshSysMem.GetDevice(pd3dDevice);
    pd3dDevice.GetDeviceCaps(d3dCaps);
    pd3dDevice := nil;
    if (primCount > d3dCaps.MaxPrimitiveCount) then g_bCantDoSingleStrip := True;

    Result := D3DXConvertMeshSubsetToStrips( pMeshData.m_pMeshSysMem, iMaterial,
                  D3DXMESH_IB_MANAGED, pMeshData.m_rgStripData[iMaterial].m_pStripsMany,
                  nil, @pbufTemp, @pMeshData.m_rgStripData[iMaterial].m_cStrips);
    if Failed(Result) then Exit;

    try
      with pMeshData.m_rgStripData[iMaterial] do
        GetMem(m_rgcStripLengths, SizeOf(DWORD)*m_cStrips);
    except
      Result := E_OUTOFMEMORY;
      Exit;
    end;
    CopyMemory(pMeshData.m_rgStripData[iMaterial].m_rgcStripLengths,
               pbufTemp.GetBufferPointer,
               SizeOf(DWORD) * pMeshData.m_rgStripData[iMaterial].m_cStrips);
  end;

  pbufTemp := nil;
end;


function UpdateLocalMeshes(const pd3dDevice: IDirect3DDevice9; pMeshData: TMeshData): HRESULT;
begin
  Result:= S_OK;
  
  // if a mesh was loaded, update the local meshes
  if (pMeshData.m_pMeshSysMem <> nil) then
  begin
    Result := pMeshData.m_pMeshSysMem.CloneMeshFVF(g_dwMemoryOptions or D3DXMESH_VB_WRITEONLY, pMeshData.m_pMeshSysMem.GetFVF,
                                                   pd3dDevice, pMeshData.m_pMesh);
    if Failed(Result) then Exit;

    Result := pMeshData.m_pMesh.GetVertexBuffer(pMeshData.m_pVertexBuffer);
    if Failed(Result) then Exit;
  end;
end;


function DrawMeshData(const pd3dDevice: IDirect3DDevice9; const pEffect: ID3DXEffect; pMeshData: TMeshData): HRESULT;
var
  iCurFace: DWORD;
  cPasses: LongWord;
  p, iMaterial: Integer;
  dwFVF: DWORD;
  cBytesPerVertex: DWORD;
  iStrip: DWORD;
begin
  V(pEffect.SetTechnique('RenderScene'));
  V(pEffect._Begin(@cPasses, 0));
  for p := 0 to cPasses - 1 do
  begin
    V(pEffect.BeginPass(p));

    // Set and draw each of the materials in the mesh
    for iMaterial := 0 to g_dwNumMaterials - 1 do
    begin
      V(pEffect.SetVector('g_vDiffuse', PD3DXVector4(@g_pMeshMaterials[iMaterial].Diffuse)^));
      V(pEffect.SetTexture('g_txScene', g_ppMeshTextures[iMaterial]));
      V(pEffect.CommitChanges);
//    V( pd3dDevice->SetMaterial( &g_pMeshMaterials[iMaterial] ) );
//    V( pd3dDevice->SetTexture( 0, g_ppMeshTextures[iMaterial] ) );

      if (not g_bShowStrips and not g_bShowSingleStrip) then
      begin
        V(pMeshData.m_pMesh.DrawSubset(iMaterial));
      end else  // drawing strips
      begin
        dwFVF := pMeshData.m_pMesh.GetFVF;
        cBytesPerVertex := D3DXGetFVFVertexSize(dwFVF);

        V(pd3dDevice.SetFVF(dwFVF));
        V(pd3dDevice.SetStreamSource(0, pMeshData.m_pVertexBuffer, 0, cBytesPerVertex));

        if g_bShowSingleStrip then
        begin
          if not g_bCantDoSingleStrip then
          begin
            V(pd3dDevice.SetIndices(pMeshData.m_rgStripData[iMaterial].m_pStrips));

            V(pd3dDevice.DrawIndexedPrimitive(D3DPT_TRIANGLESTRIP, 0,
                            0, pMeshData.m_pMesh.GetNumVertices,
                            0, pMeshData.m_rgStripData[iMaterial].m_cStripIndices - 2));
          end;
        end else
        begin
          V(pd3dDevice.SetIndices(pMeshData.m_rgStripData[iMaterial].m_pStripsMany));

          iCurFace := 0;
          for iStrip := 0 to pMeshData.m_rgStripData[iMaterial].m_cStrips - 1 do
          begin
            V(pd3dDevice.DrawIndexedPrimitive(D3DPT_TRIANGLESTRIP, 0,
                            0, pMeshData.m_pMesh.GetNumVertices,
                            iCurFace, pMeshData.m_rgStripData[iMaterial].m_rgcStripLengths[iStrip]));

            Inc(iCurFace, 2 + pMeshData.m_rgStripData[iMaterial].m_rgcStripLengths[iStrip]);
          end;
        end;
      end;
    end;
    V(pEffect.EndPass);
  end;
  V(pEffect._End);

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
  lr: TD3DLockedRect;
  str: array[0..MAX_PATH-1] of WideChar;
  pMeshSysMem: ID3DXMesh;
  pAdjacencyBuffer: ID3DXBuffer;
  vecEye, vecAt: TD3DXVector3;
  dwShaderFlags: DWORD;
begin
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  // Create the 1x1 white default texture
  Result:= pd3dDevice.CreateTexture(1, 1, 1, 0, D3DFMT_A8R8G8B8,
                                    D3DPOOL_MANAGED, g_pDefaultTex, nil);
  if V_Failed(Result) then Exit;
  Result:= g_pDefaultTex.LockRect(0, lr, nil, 0);
  if V_Failed(Result) then Exit;
  PDWORD(lr.pBits)^ := D3DCOLOR_RGBA( 255, 255, 255, 255);
  Result:= g_pDefaultTex.UnlockRect(0);
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
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'OptimizedMesh.fx');
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // they the .fx file failed to compile
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags,
                                     nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  // Load mesh
  Result := LoadMeshData(pd3dDevice, MESHFILENAME, pMeshSysMem, @pAdjacencyBuffer);
  if SUCCEEDED(Result) then
  begin
    Result := OptimizeMeshData(pMeshSysMem, pAdjacencyBuffer, D3DXMESHOPT_ATTRSORT, g_MeshAttrSorted);
    if SUCCEEDED(Result) then
      Result := OptimizeMeshData(pMeshSysMem, pAdjacencyBuffer, D3DXMESHOPT_STRIPREORDER, g_MeshStripReordered);

    if SUCCEEDED(Result) then
      Result := OptimizeMeshData(pMeshSysMem, pAdjacencyBuffer, D3DXMESHOPT_VERTEXCACHE, g_MeshVertexCacheOptimized);

    SAFE_RELEASE(pMeshSysMem);
    SAFE_RELEASE(pAdjacencyBuffer);
  end else
    // ignore load errors, just draw blank screen if mesh is invalid
    Result := S_OK;

  D3DXMatrixTranslation(g_matWorld, -g_vObjectCenter.x,
                                    -g_vObjectCenter.y,
                                    -g_vObjectCenter.z);

  // Setup the camera's view parameters
  vecEye := D3DXVector3(0.0, 0.0, -5.0);
  vecAt  := D3DXVector3(0.0, 0.0, -0.0);
  g_Camera.SetViewParams(vecEye, vecAt);

//  Result:= S_OK;
//todo: Fill bug report to ms:
//should return = hr;
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

  // update the local copies of the meshes
  UpdateLocalMeshes(pd3dDevice, g_MeshAttrSorted);
  UpdateLocalMeshes(pd3dDevice, g_MeshStripReordered);
  UpdateLocalMeshes(pd3dDevice, g_MeshVertexCacheOptimized);

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation(pBackBufferSurfaceDesc.Width-200, pBackBufferSurfaceDesc.Height-350);
  g_SampleUI.SetSize(200, 300);

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
  xOffset, yOffset: Integer;
  m: TD3DXMatrixA16;
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
    // mWorld = *g_Camera.GetWorldMatrix();
    mProj := g_Camera.GetProjMatrix^;
    mView := g_Camera.GetViewMatrix^;

    DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'Draw mesh');

    for xOffset := 0 to g_cObjectsPerSide - 1 do
    begin
      for yOffset := 0 to g_cObjectsPerSide - 1 do
      begin
        D3DXMatrixTranslation(mWorld, g_fObjectRadius * ( xOffset * 2 - g_cObjectsPerSide + 1 ),
                                      g_fObjectRadius * ( yOffset * 2 - g_cObjectsPerSide + 1 ),
                                      0);
        D3DXMatrixMultiply(mWorld, g_Camera.GetWorldMatrix^, mWorld);
        D3DXMatrixMultiply(mWorld, g_matWorld, mWorld);

        // mWorldViewProjection := mWorld * mView * mProj;
        D3DXMatrixMultiply(m, mWorld, mView);
        D3DXMatrixMultiply(mWorldViewProjection, m, mProj);

        // Update the effect's variables.  Instead of using strings, it would
        // be more efficient to cache a handle to the parameter by calling
        // ID3DXEffect::GetParameterByName
        V(g_pEffect.SetMatrix('g_mWorldViewProjection', mWorldViewProjection));
        V(g_pEffect.SetMatrix('g_mWorld', mWorld));

        if g_bShowVertexCacheOptimized
        then DrawMeshData(pd3dDevice, g_pEffect, g_MeshVertexCacheOptimized)
        else if g_bShowStripReordered
        then DrawMeshData(pd3dDevice, g_pEffect, g_MeshStripReordered)
        else DrawMeshData(pd3dDevice, g_pEffect, g_MeshAttrSorted);
      end;
    end;

    DXUT_EndPerfEvent; // end of drawing code

    begin
      // CDXUTPerfEventGenerator g( DXUT_PERFEVENTCOLOR, L"HUD / Stats" );
      DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'HUD / Stats');

      RenderText;
      V(g_HUD.OnRender(fElapsedTime));
      V(g_SampleUI.OnRender(fElapsedTime));
      DXUT_EndPerfEvent;
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
  wszOptString: PWideChar;
  cTriangles: Integer;
  fTrisPerSec: Single;
  pd3dsdBackBuffer: PD3DSurfaceDesc;
begin
  // The helper object simply helps keep track of text position, and color
  // and then it calls pFont->DrawText( m_pSprite, strMsg, -1, &rc, DT_NOCLIP, m_clr );
  // If NULL is passed in as the sprite object, then it will work however the
  // pFont->DrawText() will not be batched together.  Batching calls will improves performance.
  txtHelper := CDXUTTextHelper.Create(g_pFont, g_pTextSprite, 15);

  // Calculate and show triangles per sec, a reasonable throughput number
  if (g_MeshAttrSorted.m_pMesh <> nil)
  then cTriangles := Integer(g_MeshAttrSorted.m_pMesh.GetNumFaces) * g_cObjectsPerSide * g_cObjectsPerSide
  else cTriangles := 0;

  fTrisPerSec := DXUTGetFPS * cTriangles;

  if g_bShowVertexCacheOptimized
  then wszOptString := 'VCache Optimized'
  else if g_bShowStripReordered
  then wszOptString := 'Strip Reordered'
  else wszOptString := 'Unoptimized';

  // Output statistics
  txtHelper._Begin;
  txtHelper.SetInsertionPos( 5, 5);
  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0 ));
  txtHelper.DrawTextLine(DXUTGetFrameStats);
  txtHelper.DrawTextLine(DXUTGetDeviceStats);
//  txtHelper.DrawFormattedTextLine('%s, %d tris per sec, %d triangles',
  txtHelper.DrawFormattedTextLine('%s, %n tris per sec, %n triangles',
                                  [wszOptString, fTrisPerSec, cTriangles+0.0]);

  if (g_bShowSingleStrip and g_bCantDoSingleStrip) then
    txtHelper.DrawTextLine('Couldn''t draw to single strip -- too many primitives');

  // Draw help
  if g_bShowHelp then
  begin
    pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*6);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
    txtHelper.DrawTextLine('Controls (F1 to hide):');

    txtHelper.SetInsertionPos(40, pd3dsdBackBuffer.Height-15*5);
    txtHelper.DrawTextLine('Rotate mesh: Left click drag'#10+
                           'Zoom: mouse wheel'#10+
                           'Quit: ESC');
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

    IDC_MESHTYPE:
    begin
      case INT_PTR(CDXUTComboBox(pControl).GetSelectedData) of
        0:
        begin
          g_bShowVertexCacheOptimized := True;
          g_bShowStripReordered := False;
        end;
        1:
        begin
          g_bShowVertexCacheOptimized := False;
          g_bShowStripReordered := True;
        end;

        2:
        begin
          g_bShowVertexCacheOptimized := False;
          g_bShowStripReordered := False;
        end;
      end;
    end;

    IDC_PRIMTYPE:
    begin
      case INT_PTR(CDXUTComboBox(pControl).GetSelectedData) of
        0:
        begin
          g_bShowStrips := False;
          g_bShowSingleStrip := False;
        end;
        1:
        begin
          g_bShowStrips := False;
          g_bShowSingleStrip := True;
        end;
        2:
        begin
          g_bShowStrips := True;
          g_bShowSingleStrip := False;
        end;
      end;
    end;

    IDC_GRIDSIZE:
      g_cObjectsPerSide := INT_PTR(CDXUTComboBox(pControl).GetSelectedData);
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

  g_MeshAttrSorted.ReleaseLocalMeshes;
  g_MeshStripReordered.ReleaseLocalMeshes;
  g_MeshVertexCacheOptimized.ReleaseLocalMeshes;
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

  for i := 0 to g_dwNumMaterials - 1 do g_ppMeshTextures[i] := nil;
  g_ppMeshTextures := nil;

  g_pMeshMaterials := nil;
  g_pDefaultTex := nil;

  g_MeshAttrSorted.ReleaseAll;
  g_MeshStripReordered.ReleaseAll;
  g_MeshVertexCacheOptimized.ReleaseAll;

  g_dwNumMaterials := 0;
end;



procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera:= CModelViewerCamera.Create; // A model viewing camera
  g_HUD:= CDXUTDialog.Create; // manages the 3D UI
  g_SampleUI:= CDXUTDialog.Create; // dialog for sample specific controls

  g_MeshAttrSorted:= TMeshData.Create;
  g_MeshStripReordered:= TMeshData.Create;
  g_MeshVertexCacheOptimized:= TMeshData.Create;
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_Camera);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);

  FreeAndNil(g_MeshAttrSorted);
  FreeAndNil(g_MeshStripReordered);
  FreeAndNil(g_MeshVertexCacheOptimized);
end;

{ TMeshData }

constructor TMeshData.Create;
begin
  inherited Create;
end;

procedure TMeshData.ReleaseLocalMeshes;
begin
  m_pMesh := nil;
  m_pVertexBuffer := nil;
end;

procedure TMeshData.ReleaseAll;
var
 iStripData: Integer;
begin
  SAFE_RELEASE(m_pMeshSysMem);
  SAFE_RELEASE(m_pMesh);
  SAFE_RELEASE(m_pVertexBuffer);

  for iStripData := 0 to m_cStripDatas - 1 do
  begin
    m_rgStripData[iStripData].m_pStrips := nil;
    m_rgStripData[iStripData].m_pStripsMany := nil;
    FreeMem(m_rgStripData[iStripData].m_rgcStripLengths);
  end;
  m_rgStripData:= nil;
  m_cStripDatas := 0;
end;

end.

