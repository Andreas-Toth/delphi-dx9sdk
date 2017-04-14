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
 *  $Id: SkinnedMeshUnit.pas,v 1.17 2007/02/05 22:21:13 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: SkinnedMesh.cpp
//
// Starting point for new Direct3D applications
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit SkinnedMeshUnit;

interface

uses
  Windows, SysUtils, Math,
  DXTypes, Direct3D9, D3DX9, dxerr9, StrSafe,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders

const
  MESHFILENAME = 'tiny\tiny.x';
  UINT_MAX = High(LongWord);

const
  g_wszShaderSource: array[0..3] of PWideChar =
  (
    'skinmesh1.vsh',
    'skinmesh2.vsh',
    'skinmesh3.vsh',
    'skinmesh4.vsh'
  );

type
  // enum for various skinning modes possible
  TMethod =
  (
    D3DNONINDEXED,
    D3DINDEXED,
    SOFTWARE,
    D3DINDEXEDVS,
    D3DINDEXEDHLSLVS,
    NONE
  );


  //--------------------------------------------------------------------------------------
  // Name: struct D3DXFRAME_DERIVED
  // Desc: Structure derived from D3DXFRAME so we can add some app-specific
  //       info that will be stored with each frame
  //--------------------------------------------------------------------------------------
  PD3DXFrameDerived = ^TD3DXFrameDerived;
  TD3DXFrameDerived = packed record
    Name:               PAnsiChar;
    TransformationMatrix: TD3DXMatrix;

    pMeshContainer:     PD3DXMeshContainer;

    pFrameSibling:      PD3DXFrame;
    pFrameFirstChild:   PD3DXFrame;
    ////////////////////////////////////////////
    CombinedTransformationMatrix: TD3DXMatrixA16;
  end;


  PD3DXMaterialArray = ^TD3DXMaterialArray;
  TD3DXMaterialArray = array[0..MaxInt div SizeOf(TD3DXMaterial) - 1] of TD3DXMaterial;

  PIDirect3DTexture9Array = ^TIDirect3DTexture9Array;
  TIDirect3DTexture9Array = array[0..MaxInt div SizeOf(IDirect3DTexture9) - 1] of IDirect3DTexture9;

  PD3DXMatrixPointerArray = ^TD3DXMatrixPointerArray;
  TD3DXMatrixPointerArray = array[0..MaxInt div SizeOf(Pointer) - 1] of PD3DXMatrix;

  PD3DXMatrixArray = ^TD3DXMatrixArray;
  TD3DXMatrixArray = array[0..MaxInt div SizeOf(TD3DXMatrix) - 1] of TD3DXMatrix;

  PD3DXAttributeRangeArray = ^TD3DXAttributeRangeArray;
  TD3DXAttributeRangeArray = array[0..MaxInt div SizeOf(TD3DXAttributeRange) - 1] of TD3DXAttributeRange;


  //--------------------------------------------------------------------------------------
  // Name: struct D3DXMESHCONTAINER_DERIVED
  // Desc: Structure derived from D3DXMESHCONTAINER so we can add some app-specific
  //       info that will be stored with each mesh
  //--------------------------------------------------------------------------------------
  PD3DXMeshContainerDerived = ^TD3DXMeshContainerDerived;
  TD3DXMeshContainerDerived = packed record { public D3DXMESHCONTAINER }
    Name:               PAnsiChar;

    MeshData:           TD3DXMeshData;

    pMaterials:         PD3DXMaterialArray;
    pEffects:           PD3DXEffectInstance;
    NumMaterials:       DWORD;
    pAdjacency:         PDWORD;

    pSkinInfo:          ID3DXSkinInfo;

    pNextMeshContainer: PD3DXMeshContainer;
    ////////////////////////////////////////////
    ppTextures: PIDirect3DTexture9Array; // array of textures, entries are NULL if no texture specified

    // SkinMesh info
    pOrigMesh:          ID3DXMesh;
    pAttributeTable:    array of TD3DXAttributeRange;
    NumAttributeGroups: DWORD;
    NumInfl:            DWORD;
    pBoneCombinationBuf:ID3DXBuffer;
    ppBoneMatrixPtrs:   PD3DXMatrixPointerArray;
    pBoneOffsetMatrices:PD3DXMatrixArray;
    NumPaletteEntries:  DWORD;
    UseSoftwareVP:      Boolean;
    iAttributeSW:       DWORD; // used to denote the split between SW and HW if necessary for non-indexed skinning
  end;


  //--------------------------------------------------------------------------------------
  // Name: class CAllocateHierarchy
  // Desc: Custom version of ID3DXAllocateHierarchy with custom methods to create
  //       frames and meshcontainers.
  //--------------------------------------------------------------------------------------
  CAllocateHierarchy = class(ID3DXAllocateHierarchy)
  public
    function CreateFrame(Name: PAnsiChar; out ppNewFrame: PD3DXFrame): HResult; override;
    function CreateMeshContainer(Name: PAnsiChar; const pMeshData: TD3DXMeshData;
        pMaterials: PD3DXMaterial; pEffectInstances: PD3DXEffectInstance;
        NumMaterials: DWORD; pAdjacency: PDWORD; pSkinInfo: ID3DXSkinInfo;
        out ppMeshContainerOut: PD3DXMeshContainer): HResult; override;
    function DestroyFrame(pFrameToFree: PD3DXFrame): HResult; override;
    function DestroyMeshContainer(pMeshContainerToFree: PD3DXMeshContainer): HResult; override;
  public
    // constructor Create;
  end;


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont: ID3DXFont;                   // Font for drawing text
  g_pTextSprite: ID3DXSprite;           // Sprite for batching draw text calls
  g_pEffect: ID3DXEffect;               // D3DX effect interface
  g_ArcBall: CD3DArcBall;               // Arcball for model control
  g_bShowHelp: Boolean = True;          // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg;       // Device settings dialog
  g_HUD: CDXUTDialog;                   // dialog for standard controls
  g_SampleUI: CDXUTDialog;              // dialog for sample specific controls
  g_pFrameRoot: PD3DXFrame;
  g_pAnimController: ID3DXAnimationController;
  g_vObjectCenter: TD3DXVector3;        // Center of bounding sphere of object
  g_fObjectRadius: Single;              // Radius of bounding sphere of object
  g_SkinningMethod: TMethod = D3DNONINDEXED;  // Current skinning method
  g_pBoneMatrices: array of TD3DXMatrixA16;
  g_NumBoneMatricesMax: LongWord = 0;
  g_pIndexedVertexShader: array[0..3] of IDirect3DVertexShader9;
  g_matView: TD3DXMatrixA16;            // View matrix
  g_matProj: TD3DXMatrixA16;            // Projection matrix
  g_matProjT: TD3DXMatrixA16;           // Transpose of projection matrix (for asm shader)
  g_dwBehaviorFlags: DWORD;             // Behavior flags of the 3D device
  g_bUseSoftwareVP: Boolean;            // Flag to indicate whether software vp is
                                        // required due to lack of hardware


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_METHOD              = 5;


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
//HRESULT LoadMesh( IDirect3DDevice9* pd3dDevice, WCHAR* strFileName, ID3DXMesh** ppMesh );
procedure RenderText;
procedure DrawMeshContainer(const pd3dDevice: IDirect3DDevice9; pMeshContainerBase: PD3DXMeshContainer; pFrameBase: PD3DXFrame);
procedure DrawFrame(const pd3dDevice: IDirect3DDevice9; pFrame: PD3DXFrame);
function SetupBoneMatrixPointersOnMesh(pMeshContainerBase: PD3DXMeshContainer): HRESULT;
function SetupBoneMatrixPointers(pFrame: PD3DXFrame): HRESULT;
procedure UpdateFrameMatrices(pFrameBase: PD3DXFrame; pParentMatrix: PD3DXMatrix);
procedure UpdateSkinningMethod(pFrameBase: PD3DXFrame);
function GenerateSkinnedMesh(const pd3dDevice: IDirect3DDevice9; pMeshContainer: PD3DXMeshContainerDerived): HRESULT;
procedure ReleaseAttributeTable(pFrameBase: PD3DXFrame);


procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;


implementation

//--------------------------------------------------------------------------------------
// Name: AllocateName()
// Desc: Allocates memory for a string to hold the name of a frame or mesh
//--------------------------------------------------------------------------------------
//Clootie: AllocateName == StrNew in Delphi
(*HRESULT AllocateName( LPCSTR Name, LPSTR *pNewName )
{
    UINT cbLength;

    if( Name != NULL )
    {
        cbLength = (UINT)strlen(Name) + 1;
        *pNewName = new CHAR[cbLength];
        if (*pNewName == NULL)
            return E_OUTOFMEMORY;
        memcpy( *pNewName, Name, cbLength*sizeof(CHAR) );
    }
    else
    {
        *pNewName = NULL;
    }

    return S_OK;
}*)




//--------------------------------------------------------------------------------------
// Name: CAllocateHierarchy::CreateFrame()
// Desc: 
//--------------------------------------------------------------------------------------
function CAllocateHierarchy.CreateFrame(Name: PAnsiChar;
  out ppNewFrame: PD3DXFrame): HResult;
var
  pFrame: PD3DXFrameDerived;
begin
  Result := S_OK;

  // Start clean
  ppNewFrame := nil;

  // Create a new frame
  New(pFrame); // {PD3DXFrameDerived}
  try try
    // Clear the new frame
    ZeroMemory(pFrame, SizeOf(TD3DXFrameDerived));

    // Duplicate the name string
    pFrame.Name:= StrNew(Name);

    // Initialize other data members of the frame
    D3DXMatrixIdentity(pFrame.TransformationMatrix);
    D3DXMatrixIdentity(pFrame.CombinedTransformationMatrix);

    ppNewFrame := PD3DXFrame(pFrame);
    pFrame := nil;
  except
    on EOutOfMemory do Result:= E_OUTOFMEMORY;
    else raise;
  end;
  finally
    Dispose(pFrame);
  end;
end;


//--------------------------------------------------------------------------------------
// Name: CAllocateHierarchy::CreateMeshContainer()
// Desc: 
//--------------------------------------------------------------------------------------
function CAllocateHierarchy.CreateMeshContainer(Name: PAnsiChar;
  const pMeshData: TD3DXMeshData; pMaterials: PD3DXMaterial;
  pEffectInstances: PD3DXEffectInstance; NumMaterials: DWORD;
  pAdjacency: PDWORD; pSkinInfo: ID3DXSkinInfo;
  out ppMeshContainerOut: PD3DXMeshContainer): HResult;
var
  pNewMeshContainer: PD3DXMeshContainerDerived;
  pNewBoneOffsetMatrices: PD3DXMatrixArray;

  pd3dDevice: IDirect3DDevice9;

  pMesh: ID3DXMesh;
  NumFaces: LongWord;
  iMaterial: Integer;
  NumBones: DWORD;
  iBone: Integer;

  strTexturePath: array[0..MAX_PATH-1] of WideChar; 
  wszBuf: array[0..MAX_PATH-1] of WideChar;
begin
  pNewMeshContainer := nil;
  pNewBoneOffsetMatrices := nil;

  // Start clean
  ppMeshContainerOut := nil;

  Result:= E_FAIL;

  try try
    // This sample does not handle patch meshes, so fail when one is found
    if (pMeshData._Type <> D3DXMESHTYPE_MESH) then Exit;

    // Get the pMesh interface pointer out of the mesh data structure
    pMesh := pMeshData.pMesh as ID3DXMesh;

    // this sample does not FVF compatible meshes, so fail when one is found
    if (pMesh.GetFVF = 0) then Exit;

    // Allocate the overloaded structure to return as a D3DXMESHCONTAINER
    New(pNewMeshContainer); // = new D3DXMESHCONTAINER_DERIVED;
    // Clear the new mesh container
    FillChar(pNewMeshContainer^, 0, SizeOf(TD3DXMeshContainerDerived));

    //---------------------------------
    // Name
    //---------------------------------
    // Copy the name.  All memory as input belongs to caller, interfaces can be addref'd though
    pNewMeshContainer.Name := StrNew(Name);

    //---------------------------------
    // MeshData
    //---------------------------------
    // Get the device
    Result := pMesh.GetDevice(pd3dDevice);
    if FAILED(Result) then Exit;
    NumFaces := pMesh.GetNumFaces;

    // if no normals are in the mesh, add them
    if (pMesh.GetFVF and D3DFVF_NORMAL = 0) then
    begin
      pNewMeshContainer.MeshData._Type := D3DXMESHTYPE_MESH;

      // clone the mesh to make room for the normals
      Result := pMesh.CloneMeshFVF(pMesh.GetOptions,
                                   pMesh.GetFVF or D3DFVF_NORMAL,
                                   pd3dDevice, ID3DXMesh(pNewMeshContainer.MeshData.pMesh));
      if FAILED(Result) then Exit;

      // get the new pMesh pointer back out of the mesh container to use
      // NOTE: we do not release pMesh because we do not have a reference to it yet
      pMesh := pNewMeshContainer.MeshData.pMesh as ID3DXMesh;

      // now generate the normals for the pmesh
      D3DXComputeNormals(pMesh, nil);
    end
    else  // if no normals, just add a reference to the mesh for the mesh container
    begin
      pNewMeshContainer.MeshData.pMesh := pMesh;
      pNewMeshContainer.MeshData._Type := D3DXMESHTYPE_MESH;
    end;

    //---------------------------------
    // allocate memory to contain the material information.  This sample uses
    //   the D3D9 materials and texture names instead of the EffectInstance style materials
    pNewMeshContainer.NumMaterials := max(1, NumMaterials);
    GetMem(pNewMeshContainer.pMaterials, SizeOf(TD3DXMaterial)*pNewMeshContainer.NumMaterials);
    GetMem(pNewMeshContainer.ppTextures, SizeOf(IDirect3DTexture9)*pNewMeshContainer.NumMaterials);

    //---------------------------------
    // Adjacency
    //---------------------------------
    GetMem(pNewMeshContainer.pAdjacency, SizeOf(DWORD)*NumFaces*3);
    CopyMemory(pNewMeshContainer.pAdjacency, pAdjacency, SizeOf(DWORD) * NumFaces*3);
    ZeroMemory(pNewMeshContainer.ppTextures, SizeOf(IDirect3DTexture9) * pNewMeshContainer.NumMaterials);

    // if materials provided, copy them
    if (NumMaterials > 0) then
    begin
      CopyMemory(pNewMeshContainer.pMaterials, pMaterials, SizeOf(TD3DXMaterial) * NumMaterials);

      for iMaterial := 0 to NumMaterials - 1 do
      begin
        if (pNewMeshContainer.pMaterials[iMaterial].pTextureFilename <> nil) then
        begin
          MultiByteToWideChar(CP_ACP, 0, pNewMeshContainer.pMaterials[iMaterial].pTextureFilename, -1, wszBuf, MAX_PATH);
          wszBuf[MAX_PATH - 1] := #0;
          DXUTFindDXSDKMediaFile(strTexturePath, MAX_PATH, wszBuf);
          if FAILED(D3DXCreateTextureFromFileW(pd3dDevice, strTexturePath,
                                               pNewMeshContainer.ppTextures[iMaterial]))
          then pNewMeshContainer.ppTextures[iMaterial] := nil;

          // don't remember a pointer into the dynamic memory, just forget the name after loading
          pNewMeshContainer.pMaterials[iMaterial].pTextureFilename := nil;
        end;
      end;
    end
    else // if no materials provided, use a default one
    begin
      pNewMeshContainer.pMaterials[0].pTextureFilename := nil;
      ZeroMemory(@pNewMeshContainer.pMaterials[0].MatD3D, SizeOf(TD3DMaterial9));
      pNewMeshContainer.pMaterials[0].MatD3D.Diffuse.r := 0.5;
      pNewMeshContainer.pMaterials[0].MatD3D.Diffuse.g := 0.5;
      pNewMeshContainer.pMaterials[0].MatD3D.Diffuse.b := 0.5;
      pNewMeshContainer.pMaterials[0].MatD3D.Specular := pNewMeshContainer.pMaterials[0].MatD3D.Diffuse;
    end;

    //---------------------------------
    // SkinInfo
    //---------------------------------
    // if there is skinning information, save off the required data and then setup for HW skinning
    if (pSkinInfo <> nil) then
    begin
      // first save off the SkinInfo and original mesh data
      pNewMeshContainer.pSkinInfo := pSkinInfo;

      pNewMeshContainer.pOrigMesh := pMesh;
      
      // Will need an array of offset matrices to move the vertices from the figure space to the
      // bone's space
      NumBones := pSkinInfo.GetNumBones;
      GetMem(pNewBoneOffsetMatrices, SizeOf(TD3DXMatrix)*NumBones);

      // Get each of the bone offset matrices so that we don't need to get them later
      for iBone := 0 to NumBones - 1 do
      begin
        pNewBoneOffsetMatrices[iBone] := pSkinInfo.GetBoneOffsetMatrix(iBone)^;
      end;

      // Copy the pointer
      pNewMeshContainer.pBoneOffsetMatrices := pNewBoneOffsetMatrices;
      pNewBoneOffsetMatrices := nil;

      // GenerateSkinnedMesh will take the general skinning information and transform it to a
      // HW friendly version
      Result := GenerateSkinnedMesh(pd3dDevice, pNewMeshContainer);
      if FAILED(Result) then Exit;
    end;

    // Copy the mesh container and return
    ppMeshContainerOut := PD3DXMeshContainer(pNewMeshContainer);
    pNewMeshContainer := nil;
    Result := S_OK;
  except
    on EOutOfMemory do Result:= E_OUTOFMEMORY;
    else raise;
  end;
  finally
    FreeMem(pNewBoneOffsetMatrices);
    pd3dDevice := nil;

    // Call Destroy function to properly clean up the memory allocated
    if (pNewMeshContainer <> nil) then DestroyMeshContainer(PD3DXMeshContainer(pNewMeshContainer));
  end;
end;


//--------------------------------------------------------------------------------------
// Name: CAllocateHierarchy::DestroyFrame()
// Desc:
//--------------------------------------------------------------------------------------
function CAllocateHierarchy.DestroyFrame(pFrameToFree: PD3DXFrame): HResult;
begin
  StrDispose(pFrameToFree.Name);
  Dispose(pFrameToFree);
  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// Name: CAllocateHierarchy::DestroyMeshContainer()
// Desc:
//--------------------------------------------------------------------------------------
function CAllocateHierarchy.DestroyMeshContainer(pMeshContainerToFree: PD3DXMeshContainer): HResult;
var
  iMaterial: LongWord;
  pMeshContainer: PD3DXMeshContainerDerived;
begin
  pMeshContainer := PD3DXMeshContainerDerived(pMeshContainerToFree);

  StrDispose(pMeshContainer.Name);
  FreeMem(pMeshContainer.pAdjacency);
  FreeMem(pMeshContainer.pMaterials);
  FreeMem(pMeshContainer.pBoneOffsetMatrices);

  // release all the allocated textures
  if (pMeshContainer.ppTextures <> nil) then
    for iMaterial := 0 to pMeshContainer.NumMaterials - 1 do
      pMeshContainer.ppTextures[iMaterial] := nil;

  FreeMem(pMeshContainer.ppTextures);
  FreeMem(pMeshContainer.ppBoneMatrixPtrs);
  SAFE_RELEASE(pMeshContainer.pBoneCombinationBuf);
  SAFE_RELEASE(pMeshContainer.MeshData.pMesh);
  SAFE_RELEASE(pMeshContainer.pSkinInfo);
  SAFE_RELEASE(pMeshContainer.pOrigMesh);
  Dispose(pMeshContainer);
  Result:= S_OK;
end;


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
  Inc(iY, 24); g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)',           35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)',     35, iY, 125, 22, VK_F2);

  // Add mixed vp to the available vp choices in device settings dialog.
  DXUTGetEnumeration.SetPossibleVertexProcessingList(True, False, False, True);

  g_SampleUI.SetCallback(OnGUIEvent); iY := 10;
  g_SampleUI.AddComboBox(IDC_METHOD, 0, iY, 230, 24, Ord('S'));
  g_SampleUI.GetComboBox(IDC_METHOD).AddItem('Fixed function non-indexed (s)kinning', Pointer(D3DNONINDEXED));
  g_SampleUI.GetComboBox(IDC_METHOD).AddItem('Fixed function indexed (s)kinning', Pointer(D3DINDEXED));
  g_SampleUI.GetComboBox(IDC_METHOD).AddItem('Software (s)kinning', Pointer(SOFTWARE));
  g_SampleUI.GetComboBox(IDC_METHOD).AddItem('ASM shader indexed (s)kinning', Pointer(D3DINDEXEDVS));
  g_SampleUI.GetComboBox(IDC_METHOD).AddItem('HLSL shader indexed (s)kinning', Pointer(D3DINDEXEDHLSLVS));

  // Supports all types of vertex processing, including mixed.
  DXUTGetEnumeration.SetPossibleVertexProcessingList(True, True, True, True);
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
  if (pDeviceSettings.BehaviorFlags and D3DCREATE_HARDWARE_VERTEXPROCESSING <> 0)
  then pDeviceSettings.BehaviorFlags := D3DCREATE_MIXED_VERTEXPROCESSING;

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
// Called either by CreateMeshContainer when loading a skin mesh, or when 
// changing methods.  This function uses the pSkinInfo of the mesh 
// container to generate the desired drawable mesh and bone combination 
// table.
//--------------------------------------------------------------------------------------
function GenerateSkinnedMesh(const pd3dDevice: IDirect3DDevice9;
  pMeshContainer: PD3DXMeshContainerDerived): HRESULT;
var
  d3dCaps: TD3DCaps9;
  rgBoneCombinations: PD3DXBoneCombination;
  cInfl: DWORD;
  i: Integer;
  iInfl: Integer;
  pMeshTmp: ID3DXMesh;
  NumMaxFaceInfl: DWORD;
  Flags: DWORD;
  pIB: IDirect3DIndexBuffer9;
  MaxMatrices: LongWord;
  NewFVF: DWORD;
  pMesh: ID3DXMesh;
  pDecl: TFVFDeclaration;
  pDeclCur: PD3DVertexElement9;
begin
  Result := S_OK;

  pd3dDevice.GetDeviceCaps(d3dCaps);

  if (pMeshContainer.pSkinInfo = nil) then Exit;

  g_bUseSoftwareVP := False;

  pMeshContainer.MeshData.pMesh := nil;
  pMeshContainer.pBoneCombinationBuf := nil;

try

  // if non-indexed skinning mode selected, use ConvertToBlendedMesh to generate drawable mesh
  if (g_SkinningMethod = D3DNONINDEXED) then
  begin
    Result := pMeshContainer.pSkinInfo.ConvertToBlendedMesh
                               (
                                   pMeshContainer.pOrigMesh,
                                   D3DXMESH_MANAGED or D3DXMESHOPT_VERTEXCACHE,
                                   pMeshContainer.pAdjacency,
                                   nil, nil, nil,
                                   @pMeshContainer.NumInfl,
                                   pMeshContainer.NumAttributeGroups,
                                   pMeshContainer.pBoneCombinationBuf,
                                   ID3DXMesh(pMeshContainer.MeshData.pMesh)
                              );
    if FAILED(Result) then Exit;


    // If the device can only do 2 matrix blends, ConvertToBlendedMesh cannot approximate all meshes to it
    // Thus we split the mesh in two parts: The part that uses at most 2 matrices and the rest. The first is
    // drawn using the device's HW vertex processing and the rest is drawn using SW vertex processing.
    rgBoneCombinations  := PD3DXBoneCombination(pMeshContainer.pBoneCombinationBuf.GetBufferPointer);

    // look for any set of bone combinations that do not fit the caps
    for i := 0 to pMeshContainer.NumAttributeGroups - 1 do
    begin
      cInfl := 0;
      pMeshContainer.iAttributeSW := i;

      for iInfl := 0 to pMeshContainer.NumInfl - 1 do
      begin
        // if (rgBoneCombinations[pMeshContainer.iAttributeSW].BoneId[iInfl] <> UINT_MAX)
        if (rgBoneCombinations.BoneId[iInfl] <> UINT_MAX) then Inc(cInfl);
      end;

      if (cInfl > d3dCaps.MaxVertexBlendMatrices) then Break;

      Inc(rgBoneCombinations);
    end;

    // if there is both HW and SW, add the Software Processing flag
    if (pMeshContainer.iAttributeSW < pMeshContainer.NumAttributeGroups) then
    begin
      Result := ID3DXMesh(pMeshContainer.MeshData.pMesh).CloneMeshFVF(D3DXMESH_SOFTWAREPROCESSING or ID3DXMesh(pMeshContainer.MeshData.pMesh).GetOptions,
                                          ID3DXMesh(pMeshContainer.MeshData.pMesh).GetFVF,
                                          pd3dDevice, pMeshTmp);
      if FAILED(Result) then Exit;

      // pMeshContainer.MeshData.pMesh := nil;
      pMeshContainer.MeshData.pMesh := pMeshTmp;
      pMeshTmp := nil;
    end;
  end
  // if indexed skinning mode selected, use ConvertToIndexedsBlendedMesh to generate drawable mesh
  else if (g_SkinningMethod = D3DINDEXED) then
  begin
    Flags := D3DXMESHOPT_VERTEXCACHE;
    Result := pMeshContainer.pOrigMesh.GetIndexBuffer(pIB);
    if FAILED(Result) then Exit;

    Result := pMeshContainer.pSkinInfo.GetMaxFaceInfluences(pIB, pMeshContainer.pOrigMesh.GetNumFaces, NumMaxFaceInfl);
    pIB := nil;
    if FAILED(Result) then Exit;

    // 12 entry palette guarantees that any triangle (4 independent influences per vertex of a tri)
    // can be handled
    NumMaxFaceInfl := min(NumMaxFaceInfl, 12);

    if (d3dCaps.MaxVertexBlendMatrixIndex + 1 < NumMaxFaceInfl) then
    begin
      // HW does not support indexed vertex blending. Use SW instead
      pMeshContainer.NumPaletteEntries := min(256, pMeshContainer.pSkinInfo.GetNumBones);
      pMeshContainer.UseSoftwareVP := True;
      g_bUseSoftwareVP := True;
      Flags := Flags or D3DXMESH_SYSTEMMEM;
    end else
    begin
      // using hardware - determine palette size from caps and number of bones
      // If normals are present in the vertex data that needs to be blended for lighting, then
      // the number of matrices is half the number specified by MaxVertexBlendMatrixIndex.
      pMeshContainer.NumPaletteEntries := min(( d3dCaps.MaxVertexBlendMatrixIndex + 1 ) div 2,
                                              pMeshContainer.pSkinInfo.GetNumBones);
      pMeshContainer.UseSoftwareVP := False;
      Flags := Flags or D3DXMESH_MANAGED;
    end;

    Result := pMeshContainer.pSkinInfo.ConvertToIndexedBlendedMesh
                                            (
                                            pMeshContainer.pOrigMesh,
                                            Flags,
                                            pMeshContainer.NumPaletteEntries,
                                            pMeshContainer.pAdjacency,
                                            nil, nil, nil,
                                            @pMeshContainer.NumInfl,
                                            pMeshContainer.NumAttributeGroups,
                                            pMeshContainer.pBoneCombinationBuf,
                                            ID3DXMesh(pMeshContainer.MeshData.pMesh));
    if FAILED(Result) then Exit;
  end
  // if vertex shader indexed skinning mode selected, use ConvertToIndexedsBlendedMesh to generate drawable mesh
  else if (g_SkinningMethod = D3DINDEXEDVS) or (g_SkinningMethod = D3DINDEXEDHLSLVS) then
  begin
    // Get palette size
    // First 9 constants are used for other data.  Each 4x3 matrix takes up 3 constants.
    // (96 - 9) /3 i.e. Maximum constant count - used constants
    MaxMatrices := 26;
    pMeshContainer.NumPaletteEntries := min(MaxMatrices, pMeshContainer.pSkinInfo.GetNumBones);

    Flags := D3DXMESHOPT_VERTEXCACHE;
    if (d3dCaps.VertexShaderVersion >= D3DVS_VERSION(1, 1)) then
    begin
      pMeshContainer.UseSoftwareVP := False;
      Flags := Flags or D3DXMESH_MANAGED;
    end else
    begin
      pMeshContainer.UseSoftwareVP := True;
      g_bUseSoftwareVP := True;
      Flags := Flags or D3DXMESH_SYSTEMMEM;
    end;

    pMeshContainer.MeshData.pMesh := nil;

    Result := pMeshContainer.pSkinInfo.ConvertToIndexedBlendedMesh
                                            (
                                            pMeshContainer.pOrigMesh,
                                            Flags,
                                            pMeshContainer.NumPaletteEntries,
                                            pMeshContainer.pAdjacency,
                                            nil, nil, nil,
                                            @pMeshContainer.NumInfl,
                                            pMeshContainer.NumAttributeGroups,
                                            pMeshContainer.pBoneCombinationBuf,
                                            ID3DXMesh(pMeshContainer.MeshData.pMesh));
    if FAILED(Result) then Exit;


    // FVF has to match our declarator. Vertex shaders are not as forgiving as FF pipeline

    NewFVF := (ID3DXMesh(pMeshContainer.MeshData.pMesh).GetFVF and D3DFVF_POSITION_MASK) or (D3DFVF_NORMAL or D3DFVF_TEX1 or D3DFVF_LASTBETA_UBYTE4);
    if (NewFVF <> ID3DXMesh(pMeshContainer.MeshData.pMesh).GetFVF) then
    begin
      Result := ID3DXMesh(pMeshContainer.MeshData.pMesh).CloneMeshFVF(ID3DXMesh(pMeshContainer.MeshData.pMesh).GetOptions, NewFVF, pd3dDevice, pMesh);
      if not FAILED(Result) then
      begin
        // pMeshContainer.MeshData.pMesh := nil;
        pMeshContainer.MeshData.pMesh := pMesh;
        pMesh := nil;
      end;
    end;

    Result := ID3DXMesh(pMeshContainer.MeshData.pMesh).GetDeclaration(pDecl);
    if FAILED(Result) then Exit;

    // the vertex shader is expecting to interpret the UBYTE4 as a D3DCOLOR, so update the type
    //   NOTE: this cannot be done with CloneMesh, that would convert the UBYTE4 data to float and then to D3DCOLOR
    //          this is more of a "cast" operation
    pDeclCur := @pDecl;
    while (pDeclCur.Stream <> $ff) do
    begin
      if (pDeclCur.Usage = D3DDECLUSAGE_BLENDINDICES) and (pDeclCur.UsageIndex = 0)
        then pDeclCur._Type := D3DDECLTYPE_D3DCOLOR;
      Inc(pDeclCur);
    end;

    Result := ID3DXMesh(pMeshContainer.MeshData.pMesh).UpdateSemantics(pDecl);
    if FAILED(Result) then Exit;

    // allocate a buffer for bone matrices, but only if another mesh has not allocated one of the same size or larger
    if (g_NumBoneMatricesMax < pMeshContainer.pSkinInfo.GetNumBones) then
    begin
      g_NumBoneMatricesMax := pMeshContainer.pSkinInfo.GetNumBones;

      // Allocate space for blend matrices
      g_pBoneMatrices := nil;
      SetLength(g_pBoneMatrices, g_NumBoneMatricesMax);
    end;
  end
  // if software skinning selected, use GenerateSkinnedMesh to create a mesh that can be used with UpdateSkinnedMesh
  else if (g_SkinningMethod = SOFTWARE) then
  begin
    Result := pMeshContainer.pOrigMesh.CloneMeshFVF(D3DXMESH_MANAGED, pMeshContainer.pOrigMesh.GetFVF,
                                          pd3dDevice, ID3DXMesh(pMeshContainer.MeshData.pMesh));
    if FAILED(Result) then Exit;

    Result := ID3DXMesh(pMeshContainer.MeshData.pMesh).GetAttributeTable(nil, @pMeshContainer.NumAttributeGroups);
    if FAILED(Result) then Exit;

    pMeshContainer.pAttributeTable := nil;
    SetLength(pMeshContainer.pAttributeTable, pMeshContainer.NumAttributeGroups);

    Result := ID3DXMesh(pMeshContainer.MeshData.pMesh).GetAttributeTable(@pMeshContainer.pAttributeTable[0], nil);
    if FAILED(Result) then Exit;

    // allocate a buffer for bone matrices, but only if another mesh has not allocated one of the same size or larger
    if (g_NumBoneMatricesMax < pMeshContainer.pSkinInfo.GetNumBones) then 
    begin
      g_NumBoneMatricesMax := pMeshContainer.pSkinInfo.GetNumBones;

      // Allocate space for blend matrices
      g_pBoneMatrices := nil;
      SetLength(g_pBoneMatrices, g_NumBoneMatricesMax);
    end;
  end
  else  // invalid g_SkinningMethod value
  begin
    // return failure due to invalid skinning method value
    Result := E_INVALIDARG;
  end;

except
  on EOutOfMemory do
    Result := E_OUTOFMEMORY;
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
  Alloc: CAllocateHierarchy;
  dwShaderFlags: DWORD;
  str, strPath, strCWD: array[0..MAX_PATH-1] of WideChar;
  pLastSlash: PWideChar;
  cp: TD3DDeviceCreationParameters;
begin
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  Alloc:= CAllocateHierarchy.Create;

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
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'SkinnedMesh.fx');
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // they the .fx file failed to compile
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags,
                                     nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  // Load the mesh
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, MESHFILENAME);
  if V_Failed(Result) then Exit;
  
  StringCchCopy(strPath, MAX_PATH, str);
  pLastSlash := WideStrRScan(strPath, '\');
  if Assigned(pLastSlash) then
  begin
    pLastSlash^ := #0;
    Inc(pLastSlash);
  end else
  begin
    //todo: FPC: Remove after FPC 2.0 will be available...
    StringCchCopy(strPath, MAX_PATH, WideString('.'));
    pLastSlash := str;
  end;

  GetCurrentDirectoryW(MAX_PATH, strCWD);
  SetCurrentDirectoryW(strPath);
  Result:= D3DXLoadMeshHierarchyFromXW(pLastSlash, D3DXMESH_MANAGED, pd3dDevice,
                                       Alloc, nil, g_pFrameRoot, g_pAnimController);
  if V_Failed(Result) then Exit;
  Result:= SetupBoneMatrixPointers(g_pFrameRoot);
  if V_Failed(Result) then Exit;
  Result:= D3DXFrameCalculateBoundingSphere(g_pFrameRoot, g_vObjectCenter, g_fObjectRadius);
  if V_Failed(Result) then Exit;
  SetCurrentDirectoryW(strCWD);

  // Obtain the behavior flags
  pd3dDevice.GetCreationParameters(cp);
  g_dwBehaviorFlags := cp.BehaviorFlags;

  FreeAndNil(Alloc);
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
  fAspect: Single;
  dwShaderFlags: DWORD;
  iInfl: DWORD;
  pCode: ID3DXBuffer;
  str: array[0..MAX_PATH-1] of WideChar;
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

  // Setup render state
  pd3dDevice.SetRenderState(D3DRS_LIGHTING,         iTrue);
  pd3dDevice.SetRenderState(D3DRS_DITHERENABLE,     iTrue);
  pd3dDevice.SetRenderState(D3DRS_ZENABLE,          iTrue);
  pd3dDevice.SetRenderState(D3DRS_CULLMODE,         D3DCULL_CCW);
  pd3dDevice.SetRenderState(D3DRS_AMBIENT,          $33333333);
  pd3dDevice.SetRenderState(D3DRS_NORMALIZENORMALS, iTrue);
  pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
  pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);

  // load the indexed vertex shaders
  dwShaderFlags := 0;

  {$IFDEF DEBUG}
  // Set the D3DXSHADER_DEBUG flag to embed debug information in the shaders.
  // Setting this flag improves the shader debugging experience, but still allows
  // the shaders to be optimized and to run exactly the way they will run in
  // the release configuration of this program.
  dwShaderFlags := dwShaderFlags or D3DXSHADER_DEBUG;
  {$ENDIF}

{$IFDEF DEBUG_VS}
   dwShaderFlags := dwShaderFlags or D3DXSHADER_DEBUG or D3DXSHADER_SKIPVALIDATION;
{$ENDIF}
{$IFDEF DEBUG_PS}
   dwShaderFlags := dwShaderFlags or D3DXSHADER_DEBUG or D3DXSHADER_SKIPVALIDATION;
{$ENDIF}
  for iInfl := 0 to 3 do
  begin
    // Assemble the vertex shader file
    DXUTFindDXSDKMediaFile(str, MAX_PATH, g_wszShaderSource[iInfl]);
    Result := D3DXAssembleShaderFromFileW(str, nil, nil, dwShaderFlags, @pCode, nil);
    if Failed(Result) then Exit;

    // Create the vertex shader
    Result := pd3dDevice.CreateVertexShader(PDWORD(pCode.GetBufferPointer),
                                            g_pIndexedVertexShader[iInfl]);
    if Failed(Result) then Exit;

    pCode := nil;
  end;

  // Setup the projection matrix
  fAspect := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  D3DXMatrixPerspectiveFovLH(g_matProj, D3DX_PI/4, fAspect,
                             g_fObjectRadius/64.0, g_fObjectRadius*200.0);
  pd3dDevice.SetTransform(D3DTS_PROJECTION, g_matProj);
  D3DXMatrixTranspose(g_matProjT, g_matProj);

  // Setup the arcball parameters
  g_ArcBall.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height, 0.85);
  g_ArcBall.SetTranslationRadius(g_fObjectRadius);

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation(3, 45);
  g_SampleUI.SetSize(240, 70);

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
  matWorld: TD3DXMatrixA16;
  vEye, vAt, vUp: TD3DXVector3;
begin
   // Setup world matrix
  D3DXMatrixTranslation(matWorld, -g_vObjectCenter.x,
                                  -g_vObjectCenter.y,
                                  -g_vObjectCenter.z);
  D3DXMatrixMultiply(matWorld, matWorld, g_ArcBall.GetRotationMatrix^);
  D3DXMatrixMultiply(matWorld, matWorld, g_ArcBall.GetTranslationMatrix^);
  pd3dDevice.SetTransform(D3DTS_WORLD, matWorld);

  vEye := D3DXVector3(0, 0, -2*g_fObjectRadius);
  vAt := D3DXVector3(0, 0, 0);
  vUp := D3DXVector3(0, 1, 0);
  D3DXMatrixLookAtLH(g_matView, vEye, vAt, vUp);

  pd3dDevice.SetTransform(D3DTS_VIEW,  g_matView);

  if (g_pAnimController <> nil) then
    g_pAnimController.AdvanceTime(fElapsedTime, nil);

  UpdateFrameMatrices(g_pFrameRoot, @matWorld);
end;


//--------------------------------------------------------------------------------------
// Called to render a mesh in the hierarchy
//--------------------------------------------------------------------------------------
procedure DrawMeshContainer(const pd3dDevice: IDirect3DDevice9; pMeshContainerBase: PD3DXMeshContainer; pFrameBase: PD3DXFrame);
var
  pMeshContainer: PD3DXMeshContainerDerived;
  pFrame: PD3DXFrameDerived;
  i, iMaterial, iAttrib, iPaletteEntry, iPass: Integer;
  pBoneComb: PD3DXBoneCombination;
  iMatrixIndex: LongWord;
  numPasses: LongWord;
  NumBlend: LongWord;
  AttribIdPrev: DWORD;
  matTemp: TD3DXMatrixA16;
  d3dCaps: TD3DCaps9;
  vConst: TD3DXVector4;
  color1: TD3DXColor;
  color2: TD3DXColor;
  ambEmm: TD3DXColor;
  Identity: TD3DXMatrix;
  cBones: DWORD;
  iBone: DWORD;
  pbVerticesSrc: PByte;
  pbVerticesDest: PByte;
begin
  pMeshContainer := PD3DXMeshContainerDerived(pMeshContainerBase);
  pFrame := PD3DXFrameDerived(pFrameBase);

  pd3dDevice.GetDeviceCaps(d3dCaps);

  // first check for skinning
  if (pMeshContainer.pSkinInfo <> nil) then
  begin
    if (g_SkinningMethod = D3DNONINDEXED) then
    begin
      AttribIdPrev := UNUSED32;
      pBoneComb := PD3DXBoneCombination(pMeshContainer.pBoneCombinationBuf.GetBufferPointer);

      // Draw using default vtx processing of the device (typically HW)
      for iAttrib := 0 to pMeshContainer.NumAttributeGroups - 1 do
      begin
        NumBlend := 0;
        for i := 0 to pMeshContainer.NumInfl - 1 do
        begin
          if (pBoneComb.BoneId[i] <> UINT_MAX) then NumBlend := i;
        end;

        if (d3dCaps.MaxVertexBlendMatrices >= NumBlend + 1) then
        begin
          // first calculate the world matrices for the current set of blend weights and get the accurate count of the number of blends
          for i := 0 to pMeshContainer.NumInfl - 1 do
          begin
            iMatrixIndex := pBoneComb.BoneId[i];
            if (iMatrixIndex <> UINT_MAX) then
            begin
              D3DXMatrixMultiply(matTemp, pMeshContainer.pBoneOffsetMatrices[iMatrixIndex], pMeshContainer.ppBoneMatrixPtrs[iMatrixIndex]^);
              V(pd3dDevice.SetTransform(D3DTS_WORLDMATRIX(i), matTemp));
            end;
          end;

          V(pd3dDevice.SetRenderState(D3DRS_VERTEXBLEND, NumBlend));

          // lookup the material used for this subset of faces
          if (AttribIdPrev <> pBoneComb.AttribId) or (AttribIdPrev = UNUSED32) then
          begin
            V(pd3dDevice.SetMaterial(pMeshContainer.pMaterials[pBoneComb.AttribId].MatD3D));
            V(pd3dDevice.SetTexture(0, pMeshContainer.ppTextures[pBoneComb.AttribId]));
            AttribIdPrev := pBoneComb.AttribId;
          end;

          // draw the subset now that the correct material and matrices are loaded
          V(ID3DXMesh(pMeshContainer.MeshData.pMesh).DrawSubset(iAttrib));
        end;

        Inc(pBoneComb);
      end;

      // refetch it
      pBoneComb := PD3DXBoneCombination(pMeshContainer.pBoneCombinationBuf.GetBufferPointer);

      // If necessary, draw parts that HW could not handle using SW
      if (pMeshContainer.iAttributeSW < pMeshContainer.NumAttributeGroups) then
      begin
        AttribIdPrev := UNUSED32;
        V(pd3dDevice.SetSoftwareVertexProcessing(True));
        for iAttrib := pMeshContainer.iAttributeSW to pMeshContainer.NumAttributeGroups - 1 do
        begin
          NumBlend := 0;
          for i := 0 to pMeshContainer.NumInfl - 1 do
          begin
            if (pBoneComb.BoneId[i] <> UINT_MAX) then NumBlend := i;
          end;

          if (d3dCaps.MaxVertexBlendMatrices < NumBlend + 1) then
          begin
            // first calculate the world matrices for the current set of blend weights and get the accurate count of the number of blends
            for i := 0 to pMeshContainer.NumInfl - 1do
            begin
              iMatrixIndex := pBoneComb.BoneId[i];
              if (iMatrixIndex <> UINT_MAX) then
              begin
                D3DXMatrixMultiply(matTemp, pMeshContainer.pBoneOffsetMatrices[iMatrixIndex], pMeshContainer.ppBoneMatrixPtrs[iMatrixIndex]^);
                V(pd3dDevice.SetTransform(D3DTS_WORLDMATRIX(i), matTemp));
              end;
            end;

            V(pd3dDevice.SetRenderState(D3DRS_VERTEXBLEND, NumBlend));

            // lookup the material used for this subset of faces
            if (AttribIdPrev <> pBoneComb.AttribId) or (AttribIdPrev = UNUSED32) then
            begin
              V(pd3dDevice.SetMaterial(pMeshContainer.pMaterials[pBoneComb.AttribId].MatD3D));
              V(pd3dDevice.SetTexture(0, pMeshContainer.ppTextures[pBoneComb.AttribId]));
              AttribIdPrev := pBoneComb.AttribId;
            end;

            // draw the subset now that the correct material and matrices are loaded
            V(ID3DXMesh(pMeshContainer.MeshData.pMesh).DrawSubset(iAttrib));
          end;

          Inc(pBoneComb);
        end;
        V(pd3dDevice.SetSoftwareVertexProcessing(False));
      end;

      V(pd3dDevice.SetRenderState(D3DRS_VERTEXBLEND, 0));
    end
    else if (g_SkinningMethod = D3DINDEXED) then
    begin
      // if hw doesn't support indexed vertex processing, switch to software vertex processing
      if pMeshContainer.UseSoftwareVP then
      begin
        // If hw or pure hw vertex processing is forced, we can't render the
        // mesh, so just exit out.  Typical applications should create
        // a device with appropriate vertex processing capability for this
        // skinning method.
        if (g_dwBehaviorFlags and D3DCREATE_HARDWARE_VERTEXPROCESSING <> 0) then Exit;

        V(pd3dDevice.SetSoftwareVertexProcessing(True));
      end;

      // set the number of vertex blend indices to be blended
      if (pMeshContainer.NumInfl = 1)
      then V(pd3dDevice.SetRenderState(D3DRS_VERTEXBLEND, D3DVBF_0WEIGHTS))
      else V(pd3dDevice.SetRenderState(D3DRS_VERTEXBLEND, pMeshContainer.NumInfl - 1));

      if (pMeshContainer.NumInfl <> 0) then
        V(pd3dDevice.SetRenderState(D3DRS_INDEXEDVERTEXBLENDENABLE, iTrue));

      // for each attribute group in the mesh, calculate the set of matrices in the palette and then draw the mesh subset
      pBoneComb := PD3DXBoneCombination(pMeshContainer.pBoneCombinationBuf.GetBufferPointer);
      for iAttrib := 0 to pMeshContainer.NumAttributeGroups - 1 do
      begin
        // first calculate all the world matrices
        for iPaletteEntry := 0 to pMeshContainer.NumPaletteEntries - 1 do
        begin
          iMatrixIndex := pBoneComb.BoneId[iPaletteEntry];
          if (iMatrixIndex <> UINT_MAX) then
          begin
            D3DXMatrixMultiply(matTemp, pMeshContainer.pBoneOffsetMatrices[iMatrixIndex], pMeshContainer.ppBoneMatrixPtrs[iMatrixIndex]^);
            V(pd3dDevice.SetTransform(D3DTS_WORLDMATRIX(iPaletteEntry), matTemp));
          end;
        end;

        // setup the material of the mesh subset - REMEMBER to use the original pre-skinning attribute id to get the correct material id
        V(pd3dDevice.SetMaterial(pMeshContainer.pMaterials[pBoneComb.AttribId].MatD3D));
        V(pd3dDevice.SetTexture(0, pMeshContainer.ppTextures[pBoneComb.AttribId]));

        // finally draw the subset with the current world matrix palette and material state
        V(ID3DXMesh(pMeshContainer.MeshData.pMesh).DrawSubset(iAttrib));

        Inc(pBoneComb);
      end;

      // reset blending state
      V(pd3dDevice.SetRenderState(D3DRS_INDEXEDVERTEXBLENDENABLE, iFalse));
      V(pd3dDevice.SetRenderState(D3DRS_VERTEXBLEND, 0));

      // remember to reset back to hw vertex processing if software was required
      if pMeshContainer.UseSoftwareVP then V(pd3dDevice.SetSoftwareVertexProcessing(False));
    end
    else if (g_SkinningMethod = D3DINDEXEDVS) then
    begin
      // Use COLOR instead of UBYTE4 since Geforce3 does not support it
      // vConst.w should be 3, but due to COLOR/UBYTE4 issue, mul by 255 and add epsilon
      vConst := D3DXVector4(1.0, 0.0, 0.0, 765.01);

      if pMeshContainer.UseSoftwareVP then
      begin
        // If hw or pure hw vertex processing is forced, we can't render the
        // mesh, so just exit out.  Typical applications should create
        // a device with appropriate vertex processing capability for this
        // skinning method.
        if (g_dwBehaviorFlags and D3DCREATE_HARDWARE_VERTEXPROCESSING <> 0) then Exit;

        V(pd3dDevice.SetSoftwareVertexProcessing(True));
      end;

      V(pd3dDevice.SetVertexShader(g_pIndexedVertexShader[pMeshContainer.NumInfl - 1]));

      pBoneComb := PD3DXBoneCombination(pMeshContainer.pBoneCombinationBuf.GetBufferPointer);
      for iAttrib := 0 to pMeshContainer.NumAttributeGroups - 1 do
      begin
        // first calculate all the world matrices
        for iPaletteEntry := 0 to pMeshContainer.NumPaletteEntries - 1 do
        begin
          iMatrixIndex := pBoneComb.BoneId[iPaletteEntry];
          if (iMatrixIndex <> UINT_MAX) then
          begin
            D3DXMatrixMultiply(matTemp, pMeshContainer.pBoneOffsetMatrices[iMatrixIndex], pMeshContainer.ppBoneMatrixPtrs[iMatrixIndex]^);
            D3DXMatrixMultiplyTranspose(matTemp, matTemp, g_matView);
            V(pd3dDevice.SetVertexShaderConstantF(iPaletteEntry*3 + 9, PSingle(@matTemp), 3));
          end;
        end;

        // Sum of all ambient and emissive contribution
        color1 := (pMeshContainer.pMaterials[pBoneComb.AttribId].MatD3D.Ambient);
        color2 := D3DXColor(0.25, 0.25, 0.25, 1.0);
        D3DXColorModulate(ambEmm, color1, color2);
        D3DXColorAdd(ambEmm, ambEmm, pMeshContainer.pMaterials[pBoneComb.AttribId].MatD3D.Emissive);

        // set material color properties 
        V(pd3dDevice.SetVertexShaderConstantF(8, PSingle(@pMeshContainer.pMaterials[pBoneComb.AttribId].MatD3D.Diffuse), 1));
        V(pd3dDevice.SetVertexShaderConstantF(7, PSingle(@ambEmm), 1));
        vConst.y := pMeshContainer.pMaterials[pBoneComb.AttribId].MatD3D.Power;
        V(pd3dDevice.SetVertexShaderConstantF(0, PSingle(@vConst), 1));

        V(pd3dDevice.SetTexture(0, pMeshContainer.ppTextures[pBoneComb.AttribId]));

        // finally draw the subset with the current world matrix palette and material state
        V(ID3DXMesh(pMeshContainer.MeshData.pMesh).DrawSubset(iAttrib));

        Inc(pBoneComb);
      end;

      // remember to reset back to hw vertex processing if software was required
      if pMeshContainer.UseSoftwareVP then V(pd3dDevice.SetSoftwareVertexProcessing(False));
      V(pd3dDevice.SetVertexShader(nil));
    end
    else if (g_SkinningMethod = D3DINDEXEDHLSLVS) then 
    begin
//todo: Check here.....    
      if (pMeshContainer.UseSoftwareVP) then
      begin
        // If hw or pure hw vertex processing is forced, we can't render the
        // mesh, so just exit out.  Typical applications should create
        // a device with appropriate vertex processing capability for this
        // skinning method.
        if (g_dwBehaviorFlags and D3DCREATE_HARDWARE_VERTEXPROCESSING <> 0) then Exit;

        V(pd3dDevice.SetSoftwareVertexProcessing(True));
      end;

      pBoneComb := PD3DXBoneCombination(pMeshContainer.pBoneCombinationBuf.GetBufferPointer);
      for iAttrib := 0 to pMeshContainer.NumAttributeGroups - 1 do
      begin
        // first calculate all the world matrices
        for iPaletteEntry := 0 to pMeshContainer.NumPaletteEntries - 1 do
        begin
          iMatrixIndex := pBoneComb.BoneId[iPaletteEntry];
          if (iMatrixIndex <> UINT_MAX) then
          begin
            D3DXMatrixMultiply(matTemp, pMeshContainer.pBoneOffsetMatrices[iMatrixIndex], pMeshContainer.ppBoneMatrixPtrs[iMatrixIndex]^);
            D3DXMatrixMultiply(g_pBoneMatrices[iPaletteEntry], matTemp, g_matView);
          end;
        end;
        V(g_pEffect.SetMatrixArray('mWorldMatrixArray', @g_pBoneMatrices[0], pMeshContainer.NumPaletteEntries));

        // Sum of all ambient and emissive contribution
        color1 := (pMeshContainer.pMaterials[pBoneComb.AttribId].MatD3D.Ambient);
        color2 := D3DXColor(0.25, 0.25, 0.25, 1.0);
        D3DXColorModulate(ambEmm, color1, color2);
        D3DXColorAdd(ambEmm, ambEmm, pMeshContainer.pMaterials[pBoneComb.AttribId].MatD3D.Emissive);

        // set material color properties
        V(g_pEffect.SetVector('MaterialDiffuse', PD3DXVector4(@pMeshContainer.pMaterials[pBoneComb.AttribId].MatD3D.Diffuse)^));
        V(g_pEffect.SetVector('MaterialAmbient', PD3DXVector4(@ambEmm)^));

        // setup the material of the mesh subset - REMEMBER to use the original pre-skinning attribute id to get the correct material id
        V(pd3dDevice.SetTexture(0, pMeshContainer.ppTextures[pBoneComb.AttribId]));

        // Set CurNumBones to select the correct vertex shader for the number of bones
        V(g_pEffect.SetInt('CurNumBones', pMeshContainer.NumInfl - 1));

        // Start the effect now all parameters have been updated
        V(g_pEffect._Begin(@numPasses, D3DXFX_DONOTSAVESTATE));
        for iPass := 0 to numPasses - 1 do
        begin
          V(g_pEffect.BeginPass(iPass));
          // draw the subset with the current world matrix palette and material state
//          if iAttrib = 1 then
          V(ID3DXMesh(pMeshContainer.MeshData.pMesh).DrawSubset(iAttrib));
          V(g_pEffect.EndPass);
        end;

        V(g_pEffect._End);
        V(pd3dDevice.SetVertexShader(nil));

        Inc(pBoneComb);
      end;

      // remember to reset back to hw vertex processing if software was required
      if pMeshContainer.UseSoftwareVP then
        V(pd3dDevice.SetSoftwareVertexProcessing(False));
    end
    else if (g_SkinningMethod = SOFTWARE) then
    begin
      cBones := pMeshContainer.pSkinInfo.GetNumBones;

      // set up bone transforms
      for iBone := 0 to cBones - 1 do
      begin
        D3DXMatrixMultiply
        (
          g_pBoneMatrices[iBone],                 // output
          pMeshContainer.pBoneOffsetMatrices[iBone],
          pMeshContainer.ppBoneMatrixPtrs[iBone]^
        );
      end;

      // set world transform
      D3DXMatrixIdentity(Identity);
      V(pd3dDevice.SetTransform(D3DTS_WORLD, Identity));

      V(pMeshContainer.pOrigMesh.LockVertexBuffer(D3DLOCK_READONLY, Pointer(pbVerticesSrc)));
      V(ID3DXMesh(pMeshContainer.MeshData.pMesh).LockVertexBuffer(0, Pointer(pbVerticesDest)));

      // generate skinned mesh
      pMeshContainer.pSkinInfo.UpdateSkinnedMesh(@g_pBoneMatrices[0], nil, pbVerticesSrc, pbVerticesDest);

      V(pMeshContainer.pOrigMesh.UnlockVertexBuffer);
      V(ID3DXMesh(pMeshContainer.MeshData.pMesh).UnlockVertexBuffer);

      for iAttrib := 0 to pMeshContainer.NumAttributeGroups - 1 do
      begin
        V(pd3dDevice.SetMaterial((pMeshContainer.pMaterials[pMeshContainer.pAttributeTable[iAttrib].AttribId].MatD3D)));
        V(pd3dDevice.SetTexture(0, pMeshContainer.ppTextures[pMeshContainer.pAttributeTable[iAttrib].AttribId]));
        V(ID3DXMesh(pMeshContainer.MeshData.pMesh).DrawSubset(pMeshContainer.pAttributeTable[iAttrib].AttribId));
      end;
    end
    else // bug out as unsupported mode
    begin
      Exit;
    end;
  end
  else  // standard mesh, just draw it after setting material properties
  begin
    V(pd3dDevice.SetTransform(D3DTS_WORLD, pFrame.CombinedTransformationMatrix));

    for iMaterial := 0 to pMeshContainer.NumMaterials - 1 do
    begin
      V(pd3dDevice.SetMaterial(pMeshContainer.pMaterials[iMaterial].MatD3D));
      V(pd3dDevice.SetTexture(0, pMeshContainer.ppTextures[iMaterial]));
      V(ID3DXMesh(pMeshContainer.MeshData.pMesh).DrawSubset(iMaterial));
    end;
  end;
end;



//--------------------------------------------------------------------------------------
// Called to render a frame in the hierarchy
//--------------------------------------------------------------------------------------
procedure DrawFrame(const pd3dDevice: IDirect3DDevice9; pFrame: PD3DXFrame);
var
  pMeshContainer: PD3DXMeshContainer;
begin
  pMeshContainer := pFrame.pMeshContainer;
  while (pMeshContainer <> nil) do
  begin
    DrawMeshContainer(pd3dDevice, pMeshContainer, pFrame);
    pMeshContainer := pMeshContainer.pNextMeshContainer;
  end;

  if (pFrame.pFrameSibling <> nil) then DrawFrame(pd3dDevice, pFrame.pFrameSibling);
  if (pFrame.pFrameFirstChild <> nil) then DrawFrame(pd3dDevice, pFrame.pFrameFirstChild);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called at the end of every frame to perform all the
// rendering calls for the scene, and it will also be called if the window needs to be
// repainted. After this function has returned, DXUT will call 
// IDirect3DDevice9::Present to display the contents of the next buffer in the swap chain
//--------------------------------------------------------------------------------------
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
const
  IsWireframe: array[False..True] of DWORD = (D3DFILL_SOLID, D3DFILL_WIREFRAME);
var
  light: TD3DLight9;
  vecLightDirUnnormalized: TD3DXVector3;
  vLightDir: TD3DXVector4;
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  // Clear the render target and the zbuffer
  pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, D3DCOLOR_ARGB(0, 66, 75, 121), 1.0, 0);

  // Setup the light
  vecLightDirUnnormalized := D3DXVector3(0.0, -1.0, 1.0);
  ZeroMemory(@light, SizeOf(TD3DLIGHT9));
  light._Type       := D3DLIGHT_DIRECTIONAL;
  light.Diffuse.r   := 1.0;
  light.Diffuse.g   := 1.0;
  light.Diffuse.b   := 1.0;
  D3DXVec3Normalize(light.Direction, vecLightDirUnnormalized);
  light.Position.x   := 0.0;
  light.Position.y   := -1.0;
  light.Position.z   := 1.0;
  light.Range        := 1000.0;
  V(pd3dDevice.SetLight(0, light));
  V(pd3dDevice.LightEnable(0, True));

  // Set the projection matrix for the vertex shader based skinning method
  if (g_SkinningMethod = D3DINDEXEDVS) then
  begin
    V(pd3dDevice.SetVertexShaderConstantF(2, PSingle(@g_matProjT), 4));
  end else
  if (g_SkinningMethod = D3DINDEXEDHLSLVS) then
  begin
    V(g_pEffect.SetMatrix('mViewProj', g_matProj));
  end;

  // Set Light for vertex shader
  vLightDir := D3DXVector4(0.0, 1.0, -1.0, 0.0);
  D3DXVec4Normalize(vLightDir, vLightDir);
  V(pd3dDevice.SetVertexShaderConstantF(1, @vLightDir.x, 1));
  V(g_pEffect.SetVector('lhtDir', vLightDir));

  // Begin the scene
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    DrawFrame(pd3dDevice, g_pFrameRoot);

    RenderText;
    V(g_HUD.OnRender(fElapsedTime));
    V(g_SampleUI.OnRender(fElapsedTime));

    // End the scene.
    pd3dDevice.EndScene;
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
  pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
  txtHelper := CDXUTTextHelper.Create(g_pFont, g_pTextSprite, 15);

  // Output statistics
  txtHelper._Begin;
  txtHelper.SetInsertionPos(5, 5);
  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));
  txtHelper.DrawTextLine(DXUTGetFrameStats(True)); // Show FPS
  txtHelper.DrawTextLine(DXUTGetDeviceStats);

  txtHelper.SetForegroundColor( D3DXCOLOR( 1.0, 1.0, 1.0, 1.0 ));
  // Output statistics
  case g_SkinningMethod of
    D3DNONINDEXED: txtHelper.DrawTextLine('Using fixed-function non-indexed skinning'#10);
    D3DINDEXED:    txtHelper.DrawTextLine('Using fixed-function indexed skinning'#10);
    SOFTWARE:      txtHelper.DrawTextLine('Using software skinning'#10);
    D3DINDEXEDVS:  txtHelper.DrawTextLine('Using assembly vertex shader indexed skinning'#10);
    D3DINDEXEDHLSLVS: txtHelper.DrawTextLine('Using HLSL vertex shader indexed skinning'#10);
  else
    txtHelper.DrawTextLine( 'No skinning'#10);
  end;

  // Draw help
  if g_bShowHelp then
  begin
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*6);
    txtHelper.SetForegroundColor(D3DXCOLOR(1.0, 0.75, 0.0, 1.0 ));
    txtHelper.DrawTextLine('Controls (F1 to hide):');

    txtHelper.SetInsertionPos(40, pd3dsdBackBuffer.Height-15*5);
    txtHelper.DrawTextLine('Rotate model: Left click drag'#10 +
                           'Zoom: Middle click drag'#10 +
                           'Pane: Right click drag'#10 +
                           'Quit: ESC');
  end else
  begin
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*2);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
    txtHelper.DrawTextLine('Press F1 for help');
  end;

  // If software vp is required and we are using a hwvp device,
  // the mesh is not being displayed and we output an error message here.
  if g_bUseSoftwareVP and (g_dwBehaviorFlags and D3DCREATE_HARDWARE_VERTEXPROCESSING <> 0) then
  begin
    txtHelper.SetInsertionPos(5, 85);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.0, 0.0, 1.0));
    txtHelper.DrawTextLine('The HWVP device does not support this skinning method.'#10 + 
                           'Select another skinning method or switch to mixed or software VP.');
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

  // Pass all remaining windows messages to arcball so it can respond to user input
  g_ArcBall.HandleMessages( hWnd, uMsg, wParam, lParam );
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
  NewSkinningMethod: TMethod;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF: DXUTToggleREF;
    IDC_CHANGEDEVICE: with g_SettingsDlg do Active := not Active;

    IDC_METHOD:
    begin
      NewSkinningMethod := TMETHOD(size_t(CDXUTComboBox(pControl).GetSelectedData));

      // If the selected skinning method is different than the current one
      if (g_SkinningMethod <> NewSkinningMethod) then
      begin
        g_SkinningMethod := NewSkinningMethod;

        // update the meshes to the new skinning method
        UpdateSkinningMethod(g_pFrameRoot);
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
procedure OnLostDevice; stdcall;
var
  iInfl: DWORD;
begin
  g_DialogResourceManager.OnLostDevice;
  g_SettingsDlg.OnLostDevice;
  if Assigned(g_pFont) then g_pFont.OnLostDevice;
  if Assigned(g_pEffect) then g_pEffect.OnLostDevice;

  g_pTextSprite := nil;

  // Release the vertex shaders
  for iInfl := 0 to 3 do g_pIndexedVertexShader[iInfl] := nil;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has
// been destroyed, which generally happens as a result of application termination or
// windowed/full screen toggles. Resources created in the OnCreateDevice callback
// should be released here, which generally includes all D3DPOOL_MANAGED resources.
//--------------------------------------------------------------------------------------
procedure OnDestroyDevice; stdcall;
var
  Alloc: CAllocateHierarchy;
begin
  g_DialogResourceManager.OnDestroyDevice;
  g_SettingsDlg.OnDestroyDevice;
  SAFE_RELEASE(g_pEffect);
  SAFE_RELEASE(g_pFont);

  Alloc:= CAllocateHierarchy.Create;
  D3DXFrameDestroy(g_pFrameRoot, Alloc);
  g_pAnimController := nil;
  Alloc.Free;
end;


//--------------------------------------------------------------------------------------
// Called to setup the pointers for a given bone to its transformation matrix
//--------------------------------------------------------------------------------------
function SetupBoneMatrixPointersOnMesh(pMeshContainerBase: PD3DXMeshContainer): HRESULT;
var
  iBone, cBones: Integer;
  pFrame: PD3DXFrameDerived;
  pMeshContainer: PD3DXMeshContainerDerived;
begin
  pMeshContainer := PD3DXMeshContainerDerived(pMeshContainerBase);

  // if there is a skinmesh, then setup the bone matrices
  if (pMeshContainer.pSkinInfo <> nil) then
  begin
    cBones := pMeshContainer.pSkinInfo.GetNumBones;

    // pMeshContainer.ppBoneMatrixPtrs := new D3DXMATRIX*[cBones];
    try
      GetMem(pMeshContainer.ppBoneMatrixPtrs, SizeOf(PD3DXMatrix)*cBones);
    except
      Result:= E_OUTOFMEMORY;
      Exit;
    end;

    for iBone := 0 to cBones - 1 do
    begin
      pFrame := PD3DXFrameDerived(D3DXFrameFind(g_pFrameRoot, pMeshContainer.pSkinInfo.GetBoneName(iBone)));
      if (pFrame = nil) then
      begin
        Result:= E_FAIL;
        Exit;
      end;

      pMeshContainer.ppBoneMatrixPtrs[iBone] := @pFrame.CombinedTransformationMatrix;
    end;
  end;

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// Called to setup the pointers for a given bone to its transformation matrix
//--------------------------------------------------------------------------------------
function SetupBoneMatrixPointers(pFrame: PD3DXFrame): HRESULT;
begin
  if (pFrame.pMeshContainer <> nil) then
  begin
    Result := SetupBoneMatrixPointersOnMesh(pFrame.pMeshContainer);
    if FAILED(Result) then Exit;
  end;

  if (pFrame.pFrameSibling <> nil) then
  begin
    Result := SetupBoneMatrixPointers(pFrame.pFrameSibling);
    if FAILED(Result) then Exit;
  end;

  if (pFrame.pFrameFirstChild <> nil) then
  begin
    Result := SetupBoneMatrixPointers(pFrame.pFrameFirstChild);
    if FAILED(Result) then Exit;
  end;

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// update the frame matrices
//--------------------------------------------------------------------------------------
procedure UpdateFrameMatrices(pFrameBase: PD3DXFrame; pParentMatrix: PD3DXMatrix);
var
  pFrame: PD3DXFrameDerived;
begin
  pFrame := PD3DXFrameDerived(pFrameBase);

  // Concatenate all matrices in the chain
  if (pParentMatrix <> nil)
  then D3DXMatrixMultiply(pFrame.CombinedTransformationMatrix, pFrame.TransformationMatrix, pParentMatrix^)
  else pFrame.CombinedTransformationMatrix := pFrame.TransformationMatrix;

  // Call siblings
  if Assigned(pFrame.pFrameSibling)
  then UpdateFrameMatrices(pFrame.pFrameSibling, pParentMatrix);

  // Call children
  if Assigned(pFrame.pFrameFirstChild)
  then UpdateFrameMatrices(pFrame.pFrameFirstChild, @pFrame.CombinedTransformationMatrix);
end;


//--------------------------------------------------------------------------------------
// update the skinning method
//--------------------------------------------------------------------------------------
procedure UpdateSkinningMethod(pFrameBase: PD3DXFrame);
var
  pFrame: PD3DXFrameDerived;
  pMeshContainer: PD3DXMeshContainerDerived;
begin
  pFrame := PD3DXFrameDerived(pFrameBase);

  pMeshContainer := PD3DXMeshContainerDerived(pFrame.pMeshContainer);

  while (pMeshContainer <> nil) do
  begin
    GenerateSkinnedMesh(DXUTGetD3DDevice, pMeshContainer);
    pMeshContainer := PD3DXMeshContainerDerived(pMeshContainer.pNextMeshContainer);
  end;

  if (pFrame.pFrameSibling <> nil) then UpdateSkinningMethod(pFrame.pFrameSibling);
  if (pFrame.pFrameFirstChild <> nil) then UpdateSkinningMethod(pFrame.pFrameFirstChild);
end;

procedure ReleaseAttributeTable(pFrameBase: PD3DXFrame);
var
  pFrame: PD3DXFrameDerived;
  pMeshContainer: PD3DXMeshContainerDerived;
begin
  pFrame := PD3DXFrameDerived(pFrameBase);

  pMeshContainer := PD3DXMeshContainerDerived(pFrame.pMeshContainer);

  while (pMeshContainer <> nil) do
  begin
    pMeshContainer.pAttributeTable:= nil; {delete[]} 

    pMeshContainer := PD3DXMeshContainerDerived(pMeshContainer.pNextMeshContainer);
  end;

  if (pFrame.pFrameSibling <> nil) then
  begin
    ReleaseAttributeTable(pFrame.pFrameSibling);
  end;

  if (pFrame.pFrameFirstChild <> nil) then
  begin
    ReleaseAttributeTable(pFrame.pFrameFirstChild);
  end;
end;


procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_ArcBall:= CD3DArcBall.Create;
  g_HUD:= CDXUTDialog.Create;
  g_SampleUI:= CDXUTDialog.Create;
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_ArcBall);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);
end;

end.

