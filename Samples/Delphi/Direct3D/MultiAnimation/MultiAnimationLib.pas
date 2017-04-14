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
 *  $Id: MultiAnimationLib.pas,v 1.7 2007/02/05 22:21:10 clootie Exp $
 *----------------------------------------------------------------------------*)
//-----------------------------------------------------------------------------
// File: MultiAnimation.h
//
// Desc: Header file for the MultiAnimation library.  This contains the
//       declarations of
//
//       MultiAnimFrame              (no .cpp file)
//       MultiAnimMC                 (MultiAnimationLib.cpp)
//       CMultiAnimAllocateHierarchy (AllocHierarchy.cpp)
//       CMultiAnim                  (MultiAnimationLib.cpp)
//       CAnimInstance               (AnimationInstance.cpp)
//
// Copyright (c) Microsoft Corporation. All rights reserved
//-----------------------------------------------------------------------------

{$I DirectX.inc}

unit MultiAnimationLib;

interface

uses
  Windows, Classes, {$IFNDEF FPC}Contnrs, {$ENDIF}Direct3D9, D3DX9;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders


type
  //-----------------------------------------------------------------------------
  // Forward declarations

  PMultiAnim = ^CMultiAnim;
  CMultiAnim = class;

  PAnimInstance = ^CAnimInstance;
  CAnimInstance = class;

  

  //-----------------------------------------------------------------------------
  // Name: class CMultiAnimAllocateHierarchy
  // Desc: Inheriting from ID3DXAllocateHierarchy, this class handles the
  //       allocation and release of the memory used by animation frames and
  //       meshes.  Applications derive their own version of this class so
  //       that they can customize the behavior of allocation and release.
  //-----------------------------------------------------------------------------
  CMultiAnimAllocateHierarchy = class(ID3DXAllocateHierarchy)
  private
    m_pMA: CMultiAnim;
  public
    // callback to create a D3DXFRAME-derived object and initialize it
    function CreateFrame(Name: PAnsiChar; out ppNewFrame: PD3DXFrame): HResult; override;
    // callback to create a D3DXMESHCONTAINER-derived object and initialize it
    function CreateMeshContainer(Name: PAnsiChar; const pMeshData: TD3DXMeshData;
        pMaterials: PD3DXMaterial; pEffectInstances: PD3DXEffectInstance;
        NumMaterials: DWORD; pAdjacency: PDWORD; pSkinInfo: ID3DXSkinInfo;
        out ppNewMeshContainer: PD3DXMeshContainer): HResult; override;
    // callback to release a D3DXFRAME-derived object
    function DestroyFrame(pFrameToFree: PD3DXFrame): HResult; override;
    // callback to release a D3DXMESHCONTAINER-derived object
    function DestroyMeshContainer(pMeshContainerToFree: PD3DXMeshContainer): HResult; override;

  public
    constructor Create;

    // Setup method
    function SetMA(pMA: CMultiAnim): HRESULT;
  end;


  //-----------------------------------------------------------------------------
  // Name: struct MultiAnimFrame
  // Desc: Inherits from D3DXFRAME.  This represents an animation frame, or
  //       bone.
  //-----------------------------------------------------------------------------
  //struct MultiAnimFrame : public D3DXFRAME
  PMultiAnimFrame = ^TMultiAnimFrame;
  TMultiAnimFrame = packed record
    Name:               PAnsiChar;
    TransformationMatrix: TD3DXMatrix;

    pMeshContainer:     PD3DXMeshContainer;

    pFrameSibling:      PD3DXFrame;
    pFrameFirstChild:   PD3DXFrame;
  end;

  PAD3DXMaterial = ^AD3DXMaterial;
  AD3DXMaterial = array[0..MaxInt div SizeOf(TD3DXMaterial) - 1] of TD3DXMaterial;

  PAIDirect3DTexture9 = ^TAIDirect3DTexture9;
  TAIDirect3DTexture9 = array[0..MaxInt div SizeOf(IDirect3DTexture9) - 1] of IDirect3DTexture9;

  PAD3DXMatrix = ^AD3DXMatrix;
  AD3DXMatrix = array[0..MaxInt div SizeOf(TD3DXMatrix)-1] of TD3DXMatrix;

  PD3DXMatrixPointerArray = ^TD3DXMatrixPointerArray;
  TD3DXMatrixPointerArray = array[0..MaxInt div SizeOf(PD3DXMatrix)-1] of PD3DXMatrix;

  //-----------------------------------------------------------------------------
  // Name: struct MultiAnimMC
  // Desc: Inherits from D3DXMESHCONTAINER.  This represents a mesh object
  //       that gets its vertices blended and rendered based on the frame
  //       information in its hierarchy.
  //-----------------------------------------------------------------------------
  //struct MultiAnimMC : public D3DXMESHCONTAINER
  PMultiAnimMC = ^TMultiAnimMC;
  TMultiAnimMC = packed record
    // TD3DXMeshContainer
    Name:               PAnsiChar;

    MeshData:           TD3DXMeshData;

    pMaterials:         PAD3DXMaterial; //PD3DXMaterial;
    pEffects:           PD3DXEffectInstance;
    NumMaterials:       DWORD;
    pAdjacency:         PDWORD;

    pSkinInfo:          ID3DXSkinInfo;

    pNextMeshContainer: PD3DXMeshContainer;

    // TMultiAnimMC
    m_apTextures: PAIDirect3DTexture9; //^IDirect3DTexture9; 
    m_pWorkingMesh: ID3DXMesh;
    m_amxBoneOffsets: PAD3DXMatrix; //PD3DXMatrix;  // Bone offset matrices retrieved from pSkinInfo
    m_apmxBonePointers: PD3DXMatrixPointerArray; // ^PD3DXMatrix;  // Provides index to bone matrix lookup

    m_dwNumPaletteEntries: DWORD;
    m_dwMaxNumFaceInfls:   DWORD;
    m_dwNumAttrGroups:     DWORD;
    m_pBufBoneCombos:      ID3DXBuffer;

    // HRESULT SetupBonePtrs( D3DXFRAME * pFrameRoot );
    // function TMultiAnimMC_SetupBonePtrs(Self: PMultiAnimMC; pFrameRoot: PD3DXFrame): HRESULT;
  end;



  //-----------------------------------------------------------------------------
  // Name: class CMultiAnim
  // Desc: This class encapsulates a mesh hierarchy (typically loaded from an
  //       .X file).  It has a list of CAnimInstance objects that all share
  //       the mesh hierarchy here, as well as using a copy of our animation
  //       controller.  CMultiAnim loads and keeps an effect object that it
  //       renders the meshes with.
  //-----------------------------------------------------------------------------
  CMultiAnim = class
  { friend class CMultiAnimAllocateHierarchy;
    friend class CAnimInstance;
    friend struct MultiAnimFrame;
    friend struct MultiAnimMC; }

  protected
    m_pDevice:         IDirect3DDevice9;

    m_pEffect:         ID3DXEffect;
    m_sTechnique:      PAnsiChar;        // character rendering technique
    m_dwWorkingPaletteSize: DWORD;
    m_amxWorkingPalette: PAD3DXMatrix;   // PD3DXMatrix;

    {$IFDEF FPC}
    m_v_pAnimInstances: TList;           // must be at least 1; otherwise, clear all
    {$ELSE}
    m_v_pAnimInstances: TObjectList;     // must be at least 1; otherwise, clear all
    {$ENDIF}

    m_pFrameRoot: PMultiAnimFrame;       // shared between all instances
    m_pAC: ID3DXAnimationController;     // AC that all children clone from -- to clone clean, no keys

    // useful data an app can retrieve
    m_fBoundingRadius: Single;

  private

    function CreateInstance(out ppAnimInstance: CAnimInstance): HRESULT;
    function SetupBonePtrs(pFrame: PMultiAnimFrame): HRESULT;

  public
    constructor  Create;
    destructor Destroy; override;

    function Setup(pDevice: IDirect3DDevice9; sXFile, sFxFile: PWideChar; pAH: CMultiAnimAllocateHierarchy; pLUD: ID3DXLoadUserData = nil): HRESULT; virtual;
    function Cleanup(pAH: CMultiAnimAllocateHierarchy): HRESULT; virtual;

    function GetDevice: IDirect3DDevice9;
    function GetEffect: ID3DXEffect;
    function GetNumInstances: DWORD;
    function GetInstance(dwIndex: DWORD): CAnimInstance;
    function GetBoundingRadius: Single;

    function CreateNewInstance(out pdwNewIdx: DWORD): HRESULT; virtual;

    procedure SetTechnique(sTechnique: PChar); virtual;

    function Draw: HRESULT; virtual;
  end;




  //-----------------------------------------------------------------------------
  // Name: class CAnimInstance
  // Desc: Encapsulates an animation instance, with its own animation controller.
  //-----------------------------------------------------------------------------
  PCAnimInstance = ^CAnimInstance;
  CAnimInstance = class
  { friend class CMultiAnim; }
  protected

    m_pMultiAnim: CMultiAnim;
    m_mxWorld: TD3DXMatrix;
    m_pAC: ID3DXAnimationController;

  private

    function Setup(pAC: ID3DXAnimationController): HRESULT; virtual;
    procedure UpdateFrames(pFrame: PMultiAnimFrame; const pmxBase: TD3DXMatrix); virtual;
    procedure DrawFrames(pFrame: PMultiAnimFrame); virtual;
    procedure DrawMeshFrame(pFrame: PMultiAnimFrame); virtual;

  public

    constructor Create(pMultiAnim: CMultiAnim);
    destructor Destroy; override;

    procedure Cleanup; virtual;

    function GetMultiAnim: CMultiAnim;
    procedure GetAnimController(out ppAC: ID3DXAnimationController);

    function GetWorldTransform: TD3DXMatrix;
    procedure SetWorldTransform(const pmxWorld: TD3DXMatrix);

    function AdvanceTime(dTimeDelta: DOUBLE; var pCH: ID3DXAnimationCallbackHandler): HRESULT; virtual;
    function ResetTime: HRESULT; virtual;
    function Draw: HRESULT; virtual;
  end;


function TMultiAnimMC_SetupBonePtrs(Self: PMultiAnimMC; pFrameRoot: PD3DXFrame): HRESULT;


implementation

uses
  SysUtils, Math, DXUTmisc;


//###########################################################################//
//###########################################################################//
//###########################################################################//
//###########################################################################//
//###########################################################################//

//-----------------------------------------------------------------------------
// File: AllocHierarchy.cpp
//
// Desc: Implementation of the CMultiAnimAllocateHierarchy class, which
//       handles creating and destroying animation frames and mesh containers
//       for the CMultiAnimation library.
//
// Copyright (c) Microsoft Corporation. All rights reserved
//-----------------------------------------------------------------------------



//-----------------------------------------------------------------------------
// Name: HeapCopy()
// Desc: Allocate buffer in memory and copy the content of sName to the
//       buffer, then return the address of the buffer.
//-----------------------------------------------------------------------------
// HeapCopy == StrNew


//-----------------------------------------------------------------------------
// Name: CMultiAnimAllocateHierarchy::CMultiAnimAllocateHierarchy()
// Desc: Constructor of CMultiAnimAllocateHierarchy
//-----------------------------------------------------------------------------
constructor CMultiAnimAllocateHierarchy.Create;
begin
  m_pMA:= nil;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnimAllocateHierarchy::SetMA()
// Desc: Sets the member CMultiAnimation pointer.  This is the CMultiAnimation
//       we work with during the callbacks from D3DX.
//-----------------------------------------------------------------------------
function CMultiAnimAllocateHierarchy.SetMA(pMA: CMultiAnim): HRESULT;
begin
  m_pMA := pMA;

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnimAllocateHierarchy::CreateFrame()
// Desc: Called by D3DX during the loading of a mesh hierarchy.  The app can
//       customize its behavior.  At a minimum, the app should allocate a
//       D3DXFRAME or a child of it and fill in the Name member.
//-----------------------------------------------------------------------------
function CMultiAnimAllocateHierarchy.CreateFrame(Name: PAnsiChar; out ppNewFrame: PD3DXFrame): HResult;
var
  pFrame: PMultiAnimFrame;
begin
  Assert(m_pMA <> nil);
  ppNewFrame := nil;

  try
    GetMem(pFrame, SizeOf(TMultiAnimFrame));
    ZeroMemory(pFrame, SizeOf(TMultiAnimFrame));

    if (Name <> nil) then
      pFrame.Name := StrNew(Name)
    else
    begin
      // TODO: Add a counter to append to the string below
      //       so that we are using a different name for
      //       each bone.
      pFrame.Name := StrNew('<no_name>');
    end;
  except
    //todo: Fill bug report !!!
    // DestroyFrame(PD3DXFrame(pFrame));
    Result:= E_OUTOFMEMORY;
    Exit;
  end;

  ppNewFrame := PD3DXFrame(pFrame);
  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnimAllocateHierarchy::CreateMeshContainer()
// Desc: Called by D3DX during the loading of a mesh hierarchy. At a minumum,
//       the app should allocate a D3DXMESHCONTAINER or a child of it and fill
//       in the members based on the parameters here.  The app can further
//       customize the allocation behavior here.  In our case, we initialize
//       m_amxBoneOffsets from the skin info for convenience reason.
//       Then we call ConvertToIndexedBlendedMesh to obtain a new mesh object
//       that's compatible with the palette size we have to work with.
//-----------------------------------------------------------------------------
function CMultiAnimAllocateHierarchy.CreateMeshContainer(Name: PAnsiChar; const pMeshData: TD3DXMeshData;
  pMaterials: PD3DXMaterial; pEffectInstances: PD3DXEffectInstance;
  NumMaterials: DWORD; pAdjacency: PDWORD; pSkinInfo: ID3DXSkinInfo;
  out ppNewMeshContainer: PD3DXMeshContainer): HResult;
var
  pMC: PMultiAnimMC;
  dwNumFaces: DWORD;
  i: Integer;
  sNewPath: array[0..MAX_PATH-1] of WideChar;
  wszTexName: array[0..MAX_PATH-1] of WideChar;
  iPaletteSize: Integer;
  dwOldFVF: DWORD;
  dwNewFVF: DWORD;
  pMesh: ID3DXMesh;
  pDecl: TFVFDeclaration;
  pDeclCur: PD3DVertexElement9;
begin
  Assert(m_pMA <> nil);

  ppNewMeshContainer := nil;

  Result := S_OK;

  pMC := nil;
  try try
    GetMem(pMC, SizeOf(TMultiAnimMC));
    ZeroMemory(pMC, SizeOf(TMultiAnimMC));

    // if this is a static mesh, exit early; we're only interested in skinned meshes
    if (pSkinInfo = nil) then Exit; // S_OK;

    // only support mesh type
    if (pMeshData._Type <> D3DXMESHTYPE_MESH) then
    begin Result := E_FAIL; Exit; end;

    if (Name <> nil)
      then pMC.Name := StrNew(Name)
      else pMC.Name := StrNew('<no_name>');

    // copy the mesh over
    pMC.MeshData._Type := pMeshData._Type;
    pMC.MeshData.pMesh := pMeshData.pMesh;

    // copy adjacency over
    begin
      dwNumFaces := ID3DXMesh(pMC.MeshData.pMesh).GetNumFaces;
      GetMem(pMC.pAdjacency, SizeOf(DWORD) * 3 * dwNumFaces);
      Move(pAdjacency^, pMC.pAdjacency^, 3 * SizeOf(DWORD) * dwNumFaces);
    end;

    // ignore effects instances
    pMC.pEffects := nil;

    // alloc and copy materials
    pMC.NumMaterials := max(1, NumMaterials);
    GetMem(pMC.pMaterials, SizeOf(TD3DXMaterial)*pMC.NumMaterials);
    GetMem(pMC.m_apTextures, SizeOf(IDirect3DTexture9)*pMC.NumMaterials);
    ZeroMemory(pMC.m_apTextures, SizeOf(IDirect3DTexture9)*pMC.NumMaterials);

    if (NumMaterials > 0) then
    begin
      Move(pMaterials^, pMC.pMaterials^, NumMaterials * SizeOf(TD3DXMaterial));
      for i := 0 to NumMaterials - 1 do
      begin
        if (pMC.pMaterials[i].pTextureFilename <> nil) then
        begin
          // CALLBACK to get valid filename
          if (MultiByteToWideChar(CP_ACP, 0, pMC.pMaterials[i].pTextureFilename, -1, wszTexName, MAX_PATH ) = 0)
          then pMC.m_apTextures[i] := nil
          else
            if SUCCEEDED(DXUTFindDXSDKMediaFile(sNewPath, MAX_PATH, wszTexName)) then
            begin
              // create the D3D texture
              if FAILED(D3DXCreateTextureFromFileW(m_pMA.m_pDevice,
                   sNewPath,
                   pMC.m_apTextures[i]))
              then pMC.m_apTextures[i] := nil;
            end else
              pMC.m_apTextures[i] := nil;
        end else
          pMC.m_apTextures[i] := nil;
      end;
    end
    else    // mock up a default material and set it
    begin
      ZeroMemory(@pMC.pMaterials[0].MatD3D, SizeOf(TD3DMaterial9));
      pMC.pMaterials[0].MatD3D.Diffuse.r := 0.5;
      pMC.pMaterials[0].MatD3D.Diffuse.g := 0.5;
      pMC.pMaterials[0].MatD3D.Diffuse.b := 0.5;
      pMC.pMaterials[0].MatD3D.Specular := pMC.pMaterials[0].MatD3D.Diffuse;
      pMC.pMaterials[0].pTextureFilename := nil;
    end;

    // save the skininfo object
    pMC.pSkinInfo := pSkinInfo;

    // Get the bone offset matrices from the skin info
    GetMem(pMC.m_amxBoneOffsets, SizeOf(TD3DXMatrix)*pSkinInfo.GetNumBones);
    begin
      for i := 0 to pSkinInfo.GetNumBones - 1 do
        pMC.m_amxBoneOffsets[i] := pSkinInfo.GetBoneOffsetMatrix(i)^;
    end;

    //
    // Determine the palette size we need to work with, then call ConvertToIndexedBlendedMesh
    // to set up a new mesh that is compatible with the palette size.
    //
    begin
      iPaletteSize := 0;
      m_pMA.m_pEffect.GetInt('MATRIX_PALETTE_SIZE', iPaletteSize);
      pMC.m_dwNumPaletteEntries := Min(iPaletteSize, pMC.pSkinInfo.GetNumBones);
    end;

    // generate the skinned mesh - creates a mesh with blend weights and indices
    Result := pMC.pSkinInfo.ConvertToIndexedBlendedMesh(ID3DXMesh(pMC.MeshData.pMesh),
                              D3DXMESH_MANAGED or D3DXMESHOPT_VERTEXCACHE,
                              pMC.m_dwNumPaletteEntries,
                              pMC.pAdjacency,
                              nil,
                              nil,
                              nil,
                              @pMC.m_dwMaxNumFaceInfls,
                              pMC.m_dwNumAttrGroups,
                              pMC.m_pBufBoneCombos,
                              pMC.m_pWorkingMesh);
    if FAILED(Result) then Exit;

    // Make sure the working set is large enough for this mesh.
    // This is a bone array used for all mesh containers as a working
    // set during drawing.  If one was created previously that isn't
    // large enough for this mesh, we have to reallocate.
    if (m_pMA.m_dwWorkingPaletteSize < pMC.m_dwNumPaletteEntries) then
    begin
      if (m_pMA.m_amxWorkingPalette <> nil) then FreeMem(m_pMA.m_amxWorkingPalette);

      m_pMA.m_dwWorkingPaletteSize := 0;
      GetMem(m_pMA.m_amxWorkingPalette, SizeOf(TD3DXMatrix)*pMC.m_dwNumPaletteEntries);
      m_pMA.m_dwWorkingPaletteSize := pMC.m_dwNumPaletteEntries;
    end;

    // ensure the proper vertex format for the mesh
    begin
      dwOldFVF := pMC.m_pWorkingMesh.GetFVF;
      dwNewFVF := (dwOldFVF and D3DFVF_POSITION_MASK) or D3DFVF_NORMAL or D3DFVF_TEX1 or D3DFVF_LASTBETA_UBYTE4;
      if (dwNewFVF <> dwOldFVF) then
      begin
        Result := pMC.m_pWorkingMesh.CloneMeshFVF(pMC.m_pWorkingMesh.GetOptions,
                                                  dwNewFVF,
                                                  m_pMA.m_pDevice,
                                                  pMesh);
        if FAILED(Result) then Exit;

        pMC.m_pWorkingMesh := nil;
        pMC.m_pWorkingMesh := pMesh;

        // if the loaded mesh didn't contain normals, compute them here
        if (dwOldFVF and D3DFVF_NORMAL = 0) then
        begin
          Result := D3DXComputeNormals(pMC.m_pWorkingMesh, nil);
          if FAILED(Result) then Exit;
        end;
      end;
    end;

    // Interpret the UBYTE4 as a D3DCOLOR.
    // The GeForce3 doesn't support the UBYTE4 decl type.  So, we convert any
    // blend indices to a D3DCOLOR semantic, and later in the shader convert
    // it back using the D3DCOLORtoUBYTE4() intrinsic.  Note that we don't
    // convert any data, just the declaration.
    Result := pMC.m_pWorkingMesh.GetDeclaration(pDecl);
    if FAILED(Result) then Exit;

    pDeclCur := @pDecl;
    while (pDeclCur.Stream <> $ff) do
    begin
      if (pDeclCur.Usage = D3DDECLUSAGE_BLENDINDICES) and (pDeclCur.UsageIndex = 0)
        then pDeclCur._Type := D3DDECLTYPE_D3DCOLOR;
      Inc(pDeclCur);
    end;

    Result := pMC.m_pWorkingMesh.UpdateSemantics(pDecl);
    if FAILED(Result) then Exit;

  except
    on EOutOfMemory do Result:= E_OUTOFMEMORY;
  end
  finally
    if FAILED(Result) then
    begin
      if (pMC <> nil) then DestroyMeshContainer(PD3DXMeshContainer(pMC));
    end else
      ppNewMeshContainer := PD3DXMeshContainer(pMC);
  end;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnimAllocateHierarchy::DestroyFrame()
// Desc: Called by D3DX during the release of a mesh hierarchy.  Here we should
//       free all resources allocated in CreateFrame().
//-----------------------------------------------------------------------------
function CMultiAnimAllocateHierarchy.DestroyFrame(pFrameToFree: PD3DXFrame): HResult;
var
  pFrame: PMultiAnimFrame;
begin
  Assert(m_pMA <> nil);

  pFrame := PMultiAnimFrame(pFrameToFree);

  if (pFrame.Name <> nil) then StrDispose(pFrame.Name);

  FreeMem(pFrame);

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnimAllocateHierarchy::DestroyMeshContainer()
// Desc: Called by D3DX during the release of a mesh hierarchy.  Here we should
//       free all resources allocated in CreateMeshContainer().
//-----------------------------------------------------------------------------
function CMultiAnimAllocateHierarchy.DestroyMeshContainer(pMeshContainerToFree: PD3DXMeshContainer): HResult;
var
  pMC: PMultiAnimMC;
  i: Integer;
begin
  Assert(m_pMA <> nil);

  pMC := PMultiAnimMC(pMeshContainerToFree);

  if (pMC.Name <> nil) then StrDispose(pMC.Name);
  pMC.MeshData.pMesh := nil;
  if (pMC.pAdjacency <> nil) then FreeMem(pMC.pAdjacency);
  if (pMC.pMaterials <> nil) then FreeMem(pMC.pMaterials);

  for i := 0 to pMC.NumMaterials - 1 do pMC.m_apTextures[i]:= nil;

  if (pMC.m_apTextures <> nil) then FreeMem(pMC.m_apTextures);
  pMC.pSkinInfo := nil;
  if (pMC.m_amxBoneOffsets <> nil) then FreeMem(pMC.m_amxBoneOffsets);
  pMC.m_pWorkingMesh := nil;

  pMC.m_dwNumPaletteEntries := 0;
  pMC.m_dwMaxNumFaceInfls := 0;
  pMC.m_dwNumAttrGroups := 0;

  pMC.m_pBufBoneCombos := nil;

  if (pMC.m_apmxBonePointers <> nil) then FreeMem(pMC.m_apmxBonePointers);

  FreeMem(pMeshContainerToFree);

  Result:= S_OK;
end;






//###########################################################################//
//###########################################################################//
//###########################################################################//
//###########################################################################//
//###########################################################################//


//-----------------------------------------------------------------------------
// File: MultiAnimationLib.cpp
//
// Desc: Implementation of the CMultiAnim class. This class manages the animation
//       data (frames and meshes) obtained from a single X file.
//
// Copyright (c) Microsoft Corporation. All rights reserved
//-----------------------------------------------------------------------------


//-----------------------------------------------------------------------------
// Name: MultiAnimMC::SetupBonePtrs()
// Desc: Initialize the m_apmxBonePointers member to point to the bone matrices
//       so that we can access the bones by index easily.  Called from
//       CMultiAnim::SetupBonePtrs().
//-----------------------------------------------------------------------------
function TMultiAnimMC_SetupBonePtrs(Self: PMultiAnimMC; pFrameRoot: PD3DXFrame): HRESULT;
var
  dwNumBones: DWORD;
  i: Integer;
  pFrame: PMultiAnimFrame;
begin
  with Self^ do
  begin
    if (pSkinInfo <> nil) then
    begin
      if (m_apmxBonePointers <> nil) then FreeMem(m_apmxBonePointers);

      dwNumBones := pSkinInfo.GetNumBones;

      try
        GetMem(m_apmxBonePointers, SizeOf(PD3DXmatrix)*dwNumBones);
      except
        Result:= E_OUTOFMEMORY;
        Exit;
      end;

      for i := 0 to dwNumBones - 1 do
      begin
        pFrame := PMultiAnimFrame(D3DXFrameFind(pFrameRoot, pSkinInfo.GetBoneName(i)));
        if (pFrame = nil) then
        begin
          Result:= E_FAIL;
          Exit;
        end;

        m_apmxBonePointers[i] := @pFrame.TransformationMatrix;
      end;
    end;
  end;

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnim::CreateInstance()
// Desc: Create a new animation instance based on our animation frames and
//       animation controller.
//-----------------------------------------------------------------------------
function CMultiAnim.CreateInstance(out ppAnimInstance: CAnimInstance): HRESULT;
//HRESULT CMultiAnim::CreateInstance( CAnimInstance ** ppAnimInstance )
var
  pNewAC: ID3DXAnimationController;
  pAI: CAnimInstance;
begin
  Result:= S_OK;
  ppAnimInstance := nil;

  pNewAC := nil;
  pAI := nil;

  try try
    // Clone the original AC.  This clone is what we will use to animate
    // this mesh; the original never gets used except to clone, since we
    // always need to be able to add another instance at any time.
    Result := m_pAC.CloneAnimationController(m_pAC.GetMaxNumAnimationOutputs,
                                             m_pAC.GetMaxNumAnimationSets,
                                             m_pAC.GetMaxNumTracks,
                                             m_pAC.GetMaxNumEvents,
                                             pNewAC);
    if SUCCEEDED(Result) then
    begin
      // create the new AI
      pAI := CAnimInstance.Create(Self);

      // set it up
      Result := pAI.Setup(pNewAC);
      if FAILED(Result) then Exit;

      ppAnimInstance := pAI;
    end;
  except
    on EOutOfMemory do Result:= E_OUTOFMEMORY;
  end;
  finally
    if FAILED(Result) then
    begin
      if (pAI <> nil) then FreeAndNil(pAI);
      if (pNewAC <> nil) then pNewAC:= nil;
    end;
  end;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnim::SetupBonePtrs()
// Desc: Recursively initialize the bone pointers for all the mesh
//       containers in the hierarchy.
//-----------------------------------------------------------------------------
function CMultiAnim.SetupBonePtrs(pFrame: PMultiAnimFrame): HRESULT;
begin
  Assert(pFrame <> nil);

  if (pFrame.pMeshContainer <> nil) then
  begin
    // call setup routine
    Result := TMultiAnimMC_SetupBonePtrs(PMultiAnimMC(pFrame.pMeshContainer), PD3DXFrame(m_pFrameRoot));
    if FAILED(Result) then Exit;
  end;

  if (pFrame.pFrameSibling <> nil) then
  begin
    // recursive call
    Result := SetupBonePtrs(PMultiAnimFrame(pFrame.pFrameSibling));
    if FAILED(Result) then Exit;
  end;

  if (pFrame.pFrameFirstChild <> nil) then
  begin
    // recursive call
    Result := SetupBonePtrs(PMultiAnimFrame(pFrame.pFrameFirstChild));
    if FAILED(Result) then Exit;
  end;

  Result:= S_OK;
end;


constructor CMultiAnim.Create;
begin
{$IFDEF FPC}
  m_v_pAnimInstances:= TList.Create;
{$ELSE}
  m_v_pAnimInstances:= TObjectList.Create;
{$ENDIF}
  m_pDevice := nil;
  m_pEffect := nil;
  m_dwWorkingPaletteSize := 0;
  m_amxWorkingPalette := nil;
  m_pFrameRoot := nil;
  m_pAC := nil;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnim::~CMultiAnim()
// Desc: Destructor for CMultiAnim
//-----------------------------------------------------------------------------
destructor CMultiAnim.Destroy;
{$IFDEF FPC}
var
  i: Integer;
{$ENDIF}
begin
  {$IFDEF FPC}
  for i:= 0 to m_v_pAnimInstances.Count - 1 do GetInstance(i).Free;
  {$ENDIF}
  // m_v_pAnimInstances.Clear;
  m_v_pAnimInstances.Free;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnim::Setup()
// Desc: The class is initialized with this method.
//       We create the effect from the fx file, and load the animation mesh
//       from the given X file.  We then call SetupBonePtrs() to initialize
//       the mesh containers to enable bone matrix lookup by index.  The
//       Allocation Hierarchy is passed by pointer to allow an app to subclass
//       it for its own implementation.
//-----------------------------------------------------------------------------
function CMultiAnim.Setup(pDevice: IDirect3DDevice9; sXFile, sFxFile: PWideChar;
  pAH: CMultiAnimAllocateHierarchy; pLUD: ID3DXLoadUserData = nil): HRESULT;
var
  vCenter: TD3DXVector3;
  pEC: ID3DXEffectCompiler;
const
  mac: array[0..1] of TD3DXMacro =
  (
    (Name: 'MATRIX_PALETTE_SIZE_DEFAULT'; Definition: '35'),
    (Name: nil;                           Definition: nil )
  );
var
  caps: TD3DCaps9;
  pmac: PD3DXMacro;
  wszPath: array[0..MAX_PATH-1] of WideChar;
  dwShaderFlags: DWORD;
  pNewAC: ID3DXAnimationController;
  i: Integer;
begin
  Result:= S_OK;
  Assert(pDevice <> nil);
  Assert(sXFile <> nil);
  Assert(sFxFile <> nil);
  Assert(pAH <> nil);

  // set the MA instance for CMultiAnimAllocateHierarchy
  pAH.SetMA(Self);

  // set the device
  m_pDevice := pDevice;

  // Increase the palette size if the shader allows it. We are sort
  // of cheating here since we know tiny has 35 bones. The alternative
  // is use the maximum number that vs_2_0 allows.
(*  D3DXMACRO mac[2] =
  {
      { "MATRIX_PALETTE_SIZE_DEFAULT", "35" },
      { NULL,                          NULL }
  }; *)

  // If we support VS_2_0, increase the palette size; else, use the default
  // of 26 bones from the .fx file by passing NULL
  pmac := nil;
  m_pDevice.GetDeviceCaps(caps);
  if (caps.VertexShaderVersion > D3DVS_VERSION(1,1)) then pmac := @mac;

  try
    // create effect -- do this first, so LMHFX has access to the palette size
    Result := DXUTFindDXSDKMediaFile(wszPath, MAX_PATH, sFxFile);
    if FAILED(Result) then Exit;

    // Define DEBUG_VS and/or DEBUG_PS to debug vertex and/or pixel shaders with the shader debugger.
    // Debugging vertex shaders requires either REF or software vertex processing, and debugging
    // pixel shaders requires REF.  The D3DXSHADER_FORCE_*_SOFTWARE_NOOPT flag improves the debug
    // experience in the shader debugger.  It enables source level debugging, prevents instruction
    // reordering, prevents dead code elimination, and forces the compiler to compile against the next
    // higher available software target, which ensures that the unoptimized shaders do not exceed
    // the shader model limitations.  Setting these flags will cause slower rendering since the shaders
    // will be unoptimized and forced into software.  See the DirectX documentation for more information
    // about using the shader debugger.
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

    Result := D3DXCreateEffectFromFileW(m_pDevice,
                                        wszPath,
                                        pmac,
                                        nil,
                                        dwShaderFlags,
                                        nil,
                                        m_pEffect,
                                        nil);
    if FAILED(Result) then Exit;

    // create the mesh, frame hierarchy, and animation controller from the x file
    Result := DXUTFindDXSDKMediaFile(wszPath, MAX_PATH, sXFile);
    if FAILED(Result) then Exit;

    Result := D3DXLoadMeshHierarchyFromXW(wszPath,
                                          0,
                                          m_pDevice,
                                          pAH,
                                          pLUD,
                                          PD3DXFrame(m_pFrameRoot),
                                          m_pAC);
    if FAILED(Result) then Exit;

    if (m_pAC = nil) then
    begin
      Result := E_FAIL;
      MessageBox(0,
                 'The sample is attempting to load a mesh without animation or incompatible animation.  This sample requires tiny_4anim.x or a mesh with identical animation sets.  The program will now exit.',
                 'Mesh Load Error', MB_OK);
      Exit;
    end;

    // set up bone pointers
    Result := SetupBonePtrs(m_pFrameRoot);
    if FAILED(Result) then Exit;

    // get bounding radius
    Result := D3DXFrameCalculateBoundingSphere(PD3DXFrame(m_pFrameRoot), vCenter, m_fBoundingRadius);
    if FAILED(Result) then Exit;

    // If there are existing instances, update their animation controllers.
    begin
      for i:= 0 to m_v_pAnimInstances.Count - 1 do
      begin
        pNewAC := nil;
        Result := m_pAC.CloneAnimationController(m_pAC.GetMaxNumAnimationOutputs,
                                                 m_pAC.GetMaxNumAnimationSets,
                                                 m_pAC.GetMaxNumTracks,
                                                 m_pAC.GetMaxNumEvents,
                                                 pNewAC);
        // Release existing animation controller
        with CAnimInstance (m_v_pAnimInstances[i]) do
        begin
          m_pAC:= nil;
          Setup(pNewAC);
        end;
      end;
    end;

  finally
    if FAILED(Result) then
    begin
      if (m_amxWorkingPalette <> nil) then
      begin
        FreeMem(m_amxWorkingPalette);
        m_amxWorkingPalette := nil;
        m_dwWorkingPaletteSize := 0;
      end;

      m_pAC:= nil;

      if (m_pFrameRoot <> nil) then
      begin
        D3DXFrameDestroy(PD3DXFrame(m_pFrameRoot), pAH);
        m_pFrameRoot := nil;
      end;

      m_pEffect := nil;
      pEC:= nil; //todo: What the Heck!!!!
      m_pDevice := nil;
    end;
  end;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnim::Cleanup()
// Desc: Performs clean up work and free up memory.
//-----------------------------------------------------------------------------
function CMultiAnim.Cleanup(pAH: CMultiAnimAllocateHierarchy): HRESULT;
begin
  if (m_amxWorkingPalette <> nil) then
  begin
    FreeMem(m_amxWorkingPalette);
    m_amxWorkingPalette := nil;
    m_dwWorkingPaletteSize := 0;
  end;

  m_pAC := nil;

  if (m_pFrameRoot <> nil) then
  begin
    D3DXFrameDestroy(PD3DXFrame(m_pFrameRoot), pAH);
    m_pFrameRoot := nil;
  end;

  m_pEffect := nil;
  m_pDevice := nil;

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnim::GetDevice()
// Desc: Returns the D3D device we work with.  The caller must call Release()
//       on the pointer when done with it.
//-----------------------------------------------------------------------------
function CMultiAnim.GetDevice: IDirect3DDevice9;
begin
  Result:= m_pDevice;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnim::GetEffect()
// Desc: Returns the D3D effect object that the mesh is rendered with.  The
//       caller must call Release() when done.
//-----------------------------------------------------------------------------
function CMultiAnim.GetEffect: ID3DXEffect;
begin
  Result:= m_pEffect;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnim::GetNumInstance()
// Desc: Returns the number of animation instances using our animation frames.
//-----------------------------------------------------------------------------
function CMultiAnim.GetNumInstances: DWORD;
begin
  Result:= m_v_pAnimInstances.Count;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnim::GetInstance()
// Desc: Returns a CAnimInstance object by index.
//-----------------------------------------------------------------------------
function CMultiAnim.GetInstance(dwIndex: DWORD): CAnimInstance;
begin
  Assert(Integer(dwIndex) < m_v_pAnimInstances.Count);
  Result:= CAnimInstance(m_v_pAnimInstances[dwIndex]);
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnim::GetBoundingRadius()
// Desc: Returns the bounding radius for the mesh object.
//-----------------------------------------------------------------------------
function CMultiAnim.GetBoundingRadius: Single;
begin
  Result:= m_fBoundingRadius;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnim::CreateNewInstance()
// Desc: Creates a new animation instance and adds it to our instance array.
//       Then returns the index of the newly created instance.
//-----------------------------------------------------------------------------
function CMultiAnim.CreateNewInstance(out pdwNewIdx: DWORD): HRESULT; 
var
  pAI: CAnimInstance;
begin
  // create the AI
  Result := CreateInstance(pAI);
  if FAILED(Result) then Exit;

  // add it
  try
    m_v_pAnimInstances.Add(pAI);
  except
    Result := E_OUTOFMEMORY;
    Exit;
  end;

  pdwNewIdx := m_v_pAnimInstances.Count - 1;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnim::SetTechnique()
// Desc: Sets the name of the technique to render the mesh in.
//-----------------------------------------------------------------------------
procedure CMultiAnim.SetTechnique(sTechnique: PChar);
begin
  m_sTechnique := sTechnique;
end;


//-----------------------------------------------------------------------------
// Name: CMultiAnim::Draw()
// Desc: Render all animtion instances using our mesh frames.
//-----------------------------------------------------------------------------
function CMultiAnim.Draw: HRESULT;
var
  i: Integer;
  hr: HRESULT;
begin
  // TODO: modify this for much faster bulk rendering
  Result := S_OK;

  for i:= 0 to m_v_pAnimInstances.Count - 1 do
  begin
    hr:= CAnimInstance(m_v_pAnimInstances[i]).Draw;
    if FAILED(hr) then Result:= hr;
  end;
end;




//###########################################################################//
//###########################################################################//
//###########################################################################//
//###########################################################################//
//###########################################################################//


//-----------------------------------------------------------------------------
// File: AnimationInstance.cpp
//
// Desc: Implementation of the CAnimaInstance class, which encapsulates a
//       specific animation instance used by the CMultiAnimation library.
//
// Copyright (c) Microsoft Corporation. All rights reserved
//-----------------------------------------------------------------------------



//-----------------------------------------------------------------------------
// Name: CAnimInstance::Setup()
// Desc: Initialize ourselves to use the animation controller passed in. Then
//       initialize the animation controller.
//-----------------------------------------------------------------------------
function CAnimInstance.Setup(pAC: ID3DXAnimationController): HRESULT;
var
  i, dwTracks: DWORD;
begin
  Assert(pAC <> nil);

  m_pAC := pAC;

  // Start with all tracks disabled
  dwTracks := m_pAC.GetMaxNumTracks;
  for i := 0 to dwTracks - 1 do m_pAC.SetTrackEnable(i, False);

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: CAnimInstance::UpdateFrame()
// Desc: Recursively walk the animation frame hierarchy and for each frame,
//       transform the frame by its parent, starting with a world transform to
//       place the mesh in world space.  This has the effect of a hierarchical
//       transform over all the frames.
//-----------------------------------------------------------------------------
procedure CAnimInstance.UpdateFrames(pFrame: PMultiAnimFrame; const pmxBase: TD3DXMatrix);
begin
  Assert(pFrame <> nil);
  Assert(@pmxBase <> nil);

  // transform the bone
  D3DXMatrixMultiply(pFrame.TransformationMatrix,
                     pFrame.TransformationMatrix,
                     pmxBase);

  // transform siblings by the same matrix
  if (pFrame.pFrameSibling <> nil) then
    UpdateFrames(PMultiAnimFrame(pFrame.pFrameSibling), pmxBase);

  // transform children by the transformed matrix - hierarchical transformation
  if (pFrame.pFrameFirstChild <> nil) then
    UpdateFrames(PMultiAnimFrame(pFrame.pFrameFirstChild), pFrame.TransformationMatrix);
end;


//-----------------------------------------------------------------------------
// Name: CAnimInstance::DrawFrames()
// Desc: Recursively walk the frame hierarchy and draw each mesh container as
//       we find it.
//-----------------------------------------------------------------------------
procedure CAnimInstance.DrawFrames(pFrame: PMultiAnimFrame);
begin
  if (pFrame.pMeshContainer <> nil) then DrawMeshFrame(pFrame);

  if (pFrame.pFrameSibling <> nil) then DrawFrames(PMultiAnimFrame(pFrame.pFrameSibling));

  if (pFrame.pFrameFirstChild <> nil) then DrawFrames(PMultiAnimFrame(pFrame.pFrameFirstChild));
end;


//-----------------------------------------------------------------------------
// Name: CAnimInstance::DrawMeshFrame()
// Desc: Renders a mesh container.  Here we go through each attribute group
//       and set up the matrix palette for each group by multiplying the
//       bone offsets to its bone transformation.  This gives us the completed
//       bone matrices that can be used and blended by the pipeline.  We then
//       set up the effect and render the mesh.
//-----------------------------------------------------------------------------
type
  PD3DXBoneCombinationArray = ^TD3DXBoneCombinationArray;
  TD3DXBoneCombinationArray = array[0..0] of TD3DXBoneCombination;

procedure CAnimInstance.DrawMeshFrame(pFrame: PMultiAnimFrame);
var
  pMC: PMultiAnimMC;
  pBC: PD3DXBoneCombinationArray; // PD3DXBoneCombination;
  dwAttrib, dwPalEntry: DWORD;
  dwMatrixIndex: DWORD;
  uiPasses, uiPass: Integer;
const
  UINT_MAX = $FFFFFFFF;
begin
  pMC := PMultiAnimMC(pFrame.pMeshContainer);
  if (pMC.pSkinInfo = nil) then Exit;

  // get bone combinations
  pBC := PD3DXBoneCombinationArray(pMC.m_pBufBoneCombos.GetBufferPointer);

  // for each palette
  for dwAttrib := 0 to pMC.m_dwNumAttrGroups - 1 do
  begin
    // set each transform into the palette
    for dwPalEntry := 0 to pMC.m_dwNumPaletteEntries - 1 do
    begin
      dwMatrixIndex := pBC[dwAttrib].BoneId[dwPalEntry];
      if (dwMatrixIndex <> UINT_MAX) then
        D3DXMatrixMultiply(m_pMultiAnim.m_amxWorkingPalette[dwPalEntry],
                           pMC.m_amxBoneOffsets[dwMatrixIndex],
                           pMC.m_apmxBonePointers[dwMatrixIndex]^);
    end;

    // set the matrix palette into the effect
    m_pMultiAnim.m_pEffect.SetMatrixArray('amPalette',
                                          PD3DXMatrix(m_pMultiAnim.m_amxWorkingPalette),
                                          pMC.m_dwNumPaletteEntries);

    // we're pretty much ignoring the materials we got from the x-file; just set
    // the texture here
    m_pMultiAnim.m_pEffect.SetTexture('g_txScene', pMC.m_apTextures[pBC[dwAttrib].AttribId]);

    // set the current number of bones; this tells the effect which shader to use
    m_pMultiAnim.m_pEffect.SetInt('CurNumBones', pMC.m_dwMaxNumFaceInfls - 1);

    // set the technique we use to draw
    if FAILED(m_pMultiAnim.m_pEffect.SetTechnique(TD3DXHandle(m_pMultiAnim.m_sTechnique))) then Exit;

    // run through each pass and draw
    m_pMultiAnim.m_pEffect._Begin(@uiPasses, 0 {D3DXFX_DONOTSAVESTATE});
    for uiPass := 0 to uiPasses - 1 do
    begin
      m_pMultiAnim.m_pEffect.BeginPass(uiPass);
      pMC.m_pWorkingMesh.DrawSubset(dwAttrib);
      m_pMultiAnim.m_pEffect.EndPass;
    end;
    m_pMultiAnim.m_pEffect._End;
  end;
end;


//-----------------------------------------------------------------------------
// Name: CAnimInstance::CAnimInstance()
// Desc: Constructor of CAnimInstance
//-----------------------------------------------------------------------------
constructor CAnimInstance.Create(pMultiAnim: CMultiAnim);
begin
  m_pMultiAnim := pMultiAnim;
  m_pAC := nil;
  Assert(pMultiAnim <> nil);
end;


//-----------------------------------------------------------------------------
// Name: CAnimInstance::~CAnimInstance()
// Desc: Destructor of CAnimInstance
//-----------------------------------------------------------------------------
destructor CAnimInstance.Destroy;
begin
  inherited;
end;


//-----------------------------------------------------------------------------
// Name: CAnimInstance::Cleanup()
// Desc: Performs the cleanup task
//-----------------------------------------------------------------------------
procedure CAnimInstance.Cleanup;
begin
  m_pAC := nil;
end;


//-----------------------------------------------------------------------------
// Name: CAnimInstance::GetMultiAnim()
// Desc: Returns the CMultiAnimation object that this instance uses.
//-----------------------------------------------------------------------------
function CAnimInstance.GetMultiAnim: CMultiAnim;
begin
  Result:= m_pMultiAnim;
end;


//-----------------------------------------------------------------------------
// Name: CAnimInstance::GetAnimController()
// Desc: Returns the animation controller for this instance.  The caller
//       must call Release() when done with it.
//-----------------------------------------------------------------------------
procedure CAnimInstance.GetAnimController(out ppAC: ID3DXAnimationController);
begin
  Assert(@ppAC <> nil);
  ppAC := m_pAC; 
end;


//-----------------------------------------------------------------------------
// Name: CAnimInstance::GetWorldTransform()
// Desc: Returns the world transformation matrix for this animation instance.
//-----------------------------------------------------------------------------
function CAnimInstance.GetWorldTransform: TD3DXMatrix;
begin
  Result:= m_mxWorld;
end;


//-----------------------------------------------------------------------------
// Name: CAnimInstance::SetWorldTransform()
// Desc: Sets the world transformation matrix for this instance.
//-----------------------------------------------------------------------------
procedure CAnimInstance.SetWorldTransform(const pmxWorld: TD3DXMatrix);
begin
  Assert(@pmxWorld <> nil);
  m_mxWorld := pmxWorld;
end;


//-----------------------------------------------------------------------------
// Name: CAnimInstance::AdvanceTime()
// Desc: Advance the local time of this instance by dTimeDelta with a
//       callback handler to handle possible callback from the animation
//       controller.  Then propagate the animations down the hierarchy while
//       transforming it into world space.
//-----------------------------------------------------------------------------
function CAnimInstance.AdvanceTime(dTimeDelta: DOUBLE; var pCH: ID3DXAnimationCallbackHandler): HRESULT;
begin
  // apply all the animations to the bones in the frame hierarchy.
  Result := m_pAC.AdvanceTime(dTimeDelta, pCH);
  if FAILED(Result) then Exit;

  // apply the animations recursively through the hierarchy, and set the world.
  UpdateFrames(m_pMultiAnim.m_pFrameRoot, m_mxWorld);

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: CAnimInstance::ResetTime()
// Desc: Resets the local time for this instance.
//-----------------------------------------------------------------------------
function CAnimInstance.ResetTime: HRESULT;
begin
  Result:= m_pAC.ResetTime;
end;


//-----------------------------------------------------------------------------
// Name: CAnimInstance::Draw()
// Desc: Renders the frame hierarchy of our CMultiAnimation object.  This is
//       normally called right after AdvanceTime() so that we render the
//       mesh with the animation for this instance.
//-----------------------------------------------------------------------------
function CAnimInstance.Draw: HRESULT;
begin
  DrawFrames(m_pMultiAnim.m_pFrameRoot);
  Result:= S_OK;
end;

end.

