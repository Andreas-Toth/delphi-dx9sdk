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
 *  $Id: SkinMesh.pas,v 1.6 2007/02/05 22:21:09 clootie Exp $
 *----------------------------------------------------------------------------*)
//-----------------------------------------------------------------------------
// File: SkinMesh.h, SkinMesh.cpp
//
// Desc: Skinned mesh loader
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//-----------------------------------------------------------------------------

{$I DirectX.inc}

unit SkinMesh;

interface

uses
  Windows, SysUtils, Math, 
  Direct3D9, D3DX9;

const
  MAX_BONES = 26;

type
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


  //-----------------------------------------------------------------------------
  // Name: struct D3DXMESHCONTAINER_DERIVED
  // Desc: Structure derived from D3DXMESHCONTAINER so we can add some app-specific
  //       info that will be stored with each mesh
  //-----------------------------------------------------------------------------
  PD3DXMeshContainerDerived = ^TD3DXMeshContainerDerived;
  TD3DXMeshContainerDerived = packed record { public D3DXMESHCONTAINER }
    Name:               PAnsiChar;

    MeshData:           TD3DXMeshData;

    pMaterials:         PD3DXMaterial;
    pEffects:           PD3DXEffectInstance;
    NumMaterials:       DWORD;
    pAdjacency:         PDWORD;

    pSkinInfo:          ID3DXSkinInfo;

    pNextMeshContainer: PD3DXMeshContainer;
    ////////////////////////////////////////////
    ppTextures: PIDirect3DTexture9Array; // array of textures, entries are NULL if no texture specified

    // SkinMesh info
    pAttributeTable: PD3DXAttributeRange;
    NumAttributeGroups: DWORD;
    NumInfl: DWORD;
    pBoneCombinationBuf: ID3DXBuffer;
    ppBoneMatrixPtrs:  PD3DXMatrixPointerArray;
    pBoneOffsetMatrices: PD3DXMatrixArray;
    NumPaletteEntries: DWORD;
  end;


  //-----------------------------------------------------------------------------
  // Name: class CAllocateHierarchy
  // Desc: Custom version of ID3DXAllocateHierarchy with custom methods to create
  //       frames and meshcontainers.
  //-----------------------------------------------------------------------------
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
    constructor Create;
    function FilterMesh(const pd3dDevice: IDirect3DDevice9; const pMeshIn: ID3DXMesh; out ppMeshOut: ID3DXMesh): HRESULT;
  end;


// Public functions
function SetupBoneMatrixPointersOnMesh(pMeshContainerBase: PD3DXMeshContainer; pFrameRoot: PD3DXFrame): HRESULT;
function SetupBoneMatrixPointers(pFrame: PD3DXFrame; pFrameRoot: PD3DXFrame): HRESULT;
procedure UpdateFrameMatrices(pFrameBase: PD3DXFrame; const pParentMatrix: PD3DXMatrix);
//todo: Fill Bug report to MS
//procedure UpdateSkinningMethod(pFrameBase: PD3DXFrame);
function GenerateSkinnedMesh(const pd3dDevice: IDirect3DDevice9; pMeshContainer: PD3DXMeshContainerDerived): HRESULT;


implementation

//--------------------------------------------------------------------------------------
// Name: AllocateName()
// Desc: Allocates memory for a string to hold the name of a frame or mesh
//--------------------------------------------------------------------------------------
//Clootie: AllocateName == StrNew in Delphi
(*HRESULT AllocateName( LPCSTR Name, char** ppNameOut )
{
	HRESULT hr = S_OK;
    char* pNewName = NULL;

	// Start clean
	(*ppNameOut) = NULL;

	// No work to be done if name is NULL
	if( NULL == Name )
	{
		hr = S_OK;
		goto e_Exit;
	}

	// Allocate a new buffer
    const UINT BUFFER_LENGTH = (UINT)strlen(Name) + 1;
    pNewName = new CHAR[BUFFER_LENGTH];
    if( NULL == pNewName )
	{
		hr = E_OUTOFMEMORY;
		goto e_Exit;
	}

	// Copy the string and return
	StringCchCopyA( pNewName, BUFFER_LENGTH, Name );
	(*ppNameOut) = pNewName;
    pNewName = NULL;
    hr = S_OK;

e_Exit:
	SAFE_DELETE_ARRAY( pNewName );
	return hr;
}*)


{ CAllocateHierarchy }

constructor CAllocateHierarchy.Create;
begin

end;

//--------------------------------------------------------------------------------------
// Name: CAllocateHierarchy::CreateFrame()
// Desc: Create a new derived D3DXFRAME object
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
// Desc: Create a new derived D3DXMESHCONTAINER object
//--------------------------------------------------------------------------------------
function CAllocateHierarchy.CreateMeshContainer(Name: PAnsiChar;
  const pMeshData: TD3DXMeshData; pMaterials: PD3DXMaterial;
  pEffectInstances: PD3DXEffectInstance; NumMaterials: DWORD;
  pAdjacency: PDWORD; pSkinInfo: ID3DXSkinInfo;
  out ppMeshContainerOut: PD3DXMeshContainer): HResult;
var
  pNewMeshContainer: PD3DXMeshContainerDerived;
  pNewAdjacency: PDWORD;
  pNewBoneOffsetMatrices: PD3DXMatrixArray;

  pd3dDevice: IDirect3DDevice9;

  pNewMesh: ID3DXMesh;
  pTempMesh: ID3DXMesh;
  NumBones: DWORD;
  iBone: Integer;
begin
  pNewMesh := nil;
  pNewMeshContainer := nil;
  pNewAdjacency := nil;
  pNewBoneOffsetMatrices := nil;

  // Start clean
  ppMeshContainerOut := nil;

  Result:= E_FAIL;

  try try
    // This sample does not handle patch meshes, so fail when one is found
    if (pMeshData._Type <> D3DXMESHTYPE_MESH) then Exit;

    // Get the pMesh interface pointer out of the mesh data structure
    pNewMesh := pMeshData.pMesh as ID3DXMesh;

    // Get the device
    Result := pNewMesh.GetDevice(pd3dDevice);
    if FAILED(Result) then Exit;

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
    // Rearrange the mesh as desired
    Result := FilterMesh(pd3dDevice, ID3DXMesh(pMeshData.pMesh), pNewMesh);
    if FAILED(Result) then Exit;

    // Copy the pointer
    pNewMeshContainer.MeshData._Type := D3DXMESHTYPE_MESH;
    pNewMeshContainer.MeshData.pMesh := pNewMesh;
    pNewMesh := nil;

    //---------------------------------
    // Materials (disabled)
    //---------------------------------
    pNewMeshContainer.NumMaterials := 0;
    pNewMeshContainer.pMaterials := nil;

    //---------------------------------
    // Adjacency
    //---------------------------------
    pTempMesh := pNewMeshContainer.MeshData.pMesh as ID3DXMesh;
    GetMem(pNewAdjacency, SizeOf(DWORD)*pTempMesh.GetNumFaces*3);

    Result := pTempMesh.GenerateAdjacency(1e-6, pNewAdjacency);
    if FAILED(Result) then Exit;

    // Copy the pointer
    pNewMeshContainer.pAdjacency := pNewAdjacency;
    pNewAdjacency := nil;

    //---------------------------------
    // SkinInfo
    //---------------------------------
    // if there is skinning information, save off the required data and then setup for HW skinning
    if (pSkinInfo <> nil) then
    begin
      // first save off the SkinInfo and original mesh data
      pNewMeshContainer.pSkinInfo := pSkinInfo;

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
    FreeMem(pNewAdjacency);
    pNewMesh := nil;
    pd3dDevice := nil;

    // Call Destroy function to properly clean up the memory allocated
    if (pNewMeshContainer <> nil) then DestroyMeshContainer(PD3DXMeshContainer(pNewMeshContainer));
  end;
end;


//--------------------------------------------------------------------------------------
// Name: CAllocateHierarchy::FilterMesh
// Desc: Alter or optimize the mesh before adding it to the new mesh container
//--------------------------------------------------------------------------------------
function CAllocateHierarchy.FilterMesh(const pd3dDevice: IDirect3DDevice9;
  const pMeshIn: ID3DXMesh; out ppMeshOut: ID3DXMesh): HRESULT;
const
  // Create a new vertex declaration to hold all the required data
  VertexDecl: array[0..6] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0;  _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITION; UsageIndex: 0),
    (Stream: 0; Offset: 12; _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_NORMAL;   UsageIndex: 0),
    (Stream: 0; Offset: 24; _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TANGENT;  UsageIndex: 0),
    (Stream: 0; Offset: 36; _Type: D3DDECLTYPE_FLOAT2; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TEXCOORD; UsageIndex: 0),
    (Stream: 0; Offset: 44; _Type: D3DDECLTYPE_FLOAT4; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_BLENDWEIGHT; UsageIndex: 0),
    (Stream: 0; Offset: 60; _Type: D3DDECLTYPE_FLOAT4; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_BLENDINDICES; UsageIndex: 0),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );
var
  pTempMesh: ID3DXMesh;
  pNewMesh: ID3DXMesh;
begin
  pTempMesh := nil;
  pNewMesh := nil;

  // Start clean
  ppMeshOut := nil;

  // Clone mesh to the new vertex format
  Result := pMeshIn.CloneMesh(pMeshIn.GetOptions, @VertexDecl, pd3dDevice, pTempMesh);
  if FAILED(Result) then Exit;

  // Compute tangents, which are required for normal mapping
  Result := D3DXComputeTangentFrameEx(pTempMesh, DWORD(D3DDECLUSAGE_TEXCOORD), 0, DWORD(D3DDECLUSAGE_TANGENT), 0,
                                      D3DX_DEFAULT, 0, DWORD(D3DDECLUSAGE_NORMAL), 0,
                                      0, nil, -1, 0, -1, pNewMesh, nil);
  if FAILED(Result) then Exit;
    
  // Copy the mesh and return
  ppMeshOut := pNewMesh;
  
  pNewMesh := nil;
  pTempMesh := nil;
  Result := S_OK;
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
  pMeshStart: ID3DXMesh;
  pSkinInfo: ID3DXSkinInfo;
begin
  Result:= S_OK;

  // Save off the mesh
  pMeshStart := ID3DXMesh(pMeshContainer.MeshData.pMesh);
  pMeshContainer.MeshData.pMesh := nil;

  // Start clean
  pMeshContainer.pBoneCombinationBuf := nil;

  // Get the SkinInfo
  if (pMeshContainer.pSkinInfo = nil) then Exit;
  pSkinInfo := pMeshContainer.pSkinInfo;
  if (pSkinInfo = nil) then
  begin
    Result := E_INVALIDARG;
    Exit;
  end;

  // Use ConvertToIndexedBlendedMesh to generate drawable mesh
  pMeshContainer.NumPaletteEntries := Min(MAX_BONES, pSkinInfo.GetNumBones);

  Result := pSkinInfo.ConvertToIndexedBlendedMesh(
                        pMeshStart,
                        D3DXMESHOPT_VERTEXCACHE or D3DXMESH_MANAGED,
                        pMeshContainer.NumPaletteEntries,
                        pMeshContainer.pAdjacency,
                        nil, nil, nil,
                        @pMeshContainer.NumInfl,
                        pMeshContainer.NumAttributeGroups,
                        pMeshContainer.pBoneCombinationBuf,
                        ID3DXMesh(pMeshContainer.MeshData.pMesh));
  if FAILED(Result) then Exit;

  pMeshStart := nil;
  Result := S_OK;
end;


//--------------------------------------------------------------------------------------
// Name: CAllocateHierarchy::DestroyFrame()
// Desc:
//--------------------------------------------------------------------------------------

function CAllocateHierarchy.DestroyFrame(
  pFrameToFree: PD3DXFrame): HResult;
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
  pMeshContainer: PD3DXMeshContainerDerived;
begin
  pMeshContainer := PD3DXMeshContainerDerived(pMeshContainerToFree);

  with pMeshContainer^ do
  begin
    StrDispose(Name);
    FreeMem(pAdjacency);
    FreeMem(pMaterials);
    FreeMem(pBoneOffsetMatrices);
    FreeMem(ppBoneMatrixPtrs);

    pBoneCombinationBuf := nil;
    MeshData.pMesh := nil;
    pSkinInfo := nil;
  end;
  Dispose(pMeshContainer);

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// Update the frame matrices
//--------------------------------------------------------------------------------------
procedure UpdateFrameMatrices(pFrameBase: PD3DXFrame; const pParentMatrix: PD3DXMatrix);
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
// Called to setup the pointers for a given bone to its transformation matrix
//--------------------------------------------------------------------------------------
function SetupBoneMatrixPointersOnMesh(pMeshContainerBase: PD3DXMeshContainer; pFrameRoot: PD3DXFrame): HRESULT;
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
      pFrame := PD3DXFrameDerived(D3DXFrameFind(pFrameRoot, pMeshContainer.pSkinInfo.GetBoneName(iBone)));
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
function SetupBoneMatrixPointers(pFrame: PD3DXFrame; pFrameRoot: PD3DXFrame): HRESULT;
begin
  if (pFrame.pMeshContainer <> nil) then
  begin
    Result := SetupBoneMatrixPointersOnMesh(pFrame.pMeshContainer, pFrameRoot);
    if FAILED(Result) then Exit;
  end;

  if (pFrame.pFrameSibling <> nil) then
  begin
    Result := SetupBoneMatrixPointers(pFrame.pFrameSibling, pFrameRoot);
    if FAILED(Result) then Exit;
  end;

  if (pFrame.pFrameFirstChild <> nil) then
  begin
    Result := SetupBoneMatrixPointers(pFrame.pFrameFirstChild, pFrameRoot);
    if FAILED(Result) then Exit;
  end;

  Result:= S_OK;
end;

end.

