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
 *  $Id: ShadowVolumeUnit.pas,v 1.16 2007/02/05 22:21:12 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: ShadowVolume.cpp
//
// Starting point for new Direct3D applications
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit ShadowVolumeUnit;

interface

uses
  Windows, Messages, SysUtils, Math, StrSafe,
  DXTypes, Direct3D9, D3DX9, dxerr9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTMesh, DXUTSettingsDlg;
  
{.$DEFINE SYNCRO_BY_FENCE}

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders


const
  DEFMESHFILENAME = 'dwarf\dwarf.x';
  MAX_NUM_LIGHTS = 6;
  ADJACENCY_EPSILON = 0.0001;
  EXTRUDE_EPSILON = 0.1;
  AMBIENT = 0.10;

type
  TRenderType = (RENDERTYPE_SCENE, RENDERTYPE_SHADOWVOLUME, RENDERTYPE_COMPLEXITY);

var
  g_vShadowColor: array[0..MAX_NUM_LIGHTS-1] of TD3DXVector4;

type
  PLightInitData = ^TLightInitData;
  TLightInitData = record
    Position: TD3DXVector3;
    Color: TD3DXVector4;
  end;

function LightInitData(const P: TD3DXVector3; const C: TD3DXVector4): TLightInitData;

var
  g_LightInit: array[0..MAX_NUM_LIGHTS-1] of TLightInitData; 


type
  PPostProcVert = ^TPostProcVert;
  TPostProcVert = packed record
    x, y, z: Single;
    rhw: Single;
  end;

const
  TPostProcVert_Decl: array [0..1] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0;  _Type: D3DDECLTYPE_FLOAT4; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITIONT; UsageIndex: 0),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );

function PostProcVert(x, y, z, rhw: Single): TPostProcVert;

type
  PShadowVert = ^TShadowVert;
  TShadowVert = packed record
    Position: TD3DXVector3;
    Normal: TD3DXVector3;
  end;

  PShadowVertArray = ^TShadowVertArray;
  TShadowVertArray = array[0..MaxInt div SizeOf(TShadowVert)-1] of TShadowVert;

const
  TShadowVert_Decl: array [0..2] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0;  _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITION; UsageIndex: 0),
    (Stream: 0; Offset: 12;  _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_NORMAL; UsageIndex: 0),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );


type
  TMeshVert = packed record
    Position: TD3DXVector3;
    Normal: TD3DXVector3;
    Tex: TD3DXVector2;
  end;

const
  TMeshVert_Decl: array [0..3] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0;  _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITION; UsageIndex: 0),
    (Stream: 0; Offset: 12;  _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_NORMAL; UsageIndex: 0),
    (Stream: 0; Offset: 24;  _Type: D3DDECLTYPE_FLOAT2; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TEXCOORD; UsageIndex: 0),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );


type
  PEdgeMapping = ^TEdgeMapping;
  TEdgeMapping = record
    m_anOldEdge: array[0..1] of Integer;  // vertex index of the original edge
    m_aanNewEdge: array[0..1, 0..1] of Integer; // vertex indexes of the new edge
                                                // First subscript = index of the new edge
                                                // Second subscript = index of the vertex for the edge

//    CEdgeMapping()
    {
        FillMemory( m_anOldEdge, sizeof(m_anOldEdge), -1 );
        FillMemory( m_aanNewEdge, sizeof(m_aanNewEdge), -1 );
    }
  end;

function EdgeMapping: TEdgeMapping;

type
  TLight = record
    m_Position: TD3DXVector3;  // Light position
    m_Color: TD3DXVector4;     // Light color
    m_mWorld: TD3DXMatrixA16;  // World transform
  end;


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont: ID3DXFont;                         // Font for drawing text
  g_pTextSprite: ID3DXSprite;                 // Sprite for batching draw text calls
  g_pEffect: ID3DXEffect;                     // D3DX effect interface
  g_pDefaultTex: IDirect3DTexture9;           // Default texture for faces without one
  g_pMeshDecl: IDirect3DVertexDeclaration9;   // Vertex declaration for the meshes
  g_pShadowDecl: IDirect3DVertexDeclaration9; // Vertex declaration for the shadow volume
  g_pPProcDecl: IDirect3DVertexDeclaration9;  // Vertex declaration for post-process quad rendering
  g_Camera: CFirstPersonCamera;               // Viewer's camera
  g_MCamera: CModelViewerCamera;              // Camera for mesh control
  g_LCamera: CModelViewerCamera;              // Camera for easy light movement control
  g_hRenderShadow: TD3DXHandle;               // Technique handle for rendering shadow
  g_hShowShadow: TD3DXHandle;                 // Technique handle for showing shadow volume
  g_hRenderScene: TD3DXHandle;                // Technique handle for rendering scene
  g_mWorldScaling: TD3DXMatrixA16;            // Scaling to apply to mesh
  g_bShowHelp: Boolean = True;                // If true, it renders the UI control text
  g_bShowShadowVolume: Boolean = False;       // Whether the shadow volume is visibly shown.
  g_RenderType: TRenderType = RENDERTYPE_SCENE; // Type of rendering to perform
  g_nNumLights: Integer = 1;                  // Number of active lights
  g_Background: array[0..1] of CDXUTMesh;     // Background meshes
  g_mWorldBack: array[0..1] of TD3DXMatrixA16;// Additional scaling and translation for background meshes
  g_nCurrBackground: Integer = 0;             // Current background mesh
  g_LightMesh: CDXUTMesh;                     // Mesh to represent the light source
  g_Mesh: CDXUTMesh;                          // The mesh object
  g_pShadowMesh: ID3DXMesh;                   // The shadow volume mesh
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg;             // Device settings dialog
  g_HUD: CDXUTDialog;                         // dialog for standard controls
  g_SampleUI: CDXUTDialog;                    // dialog for sample specific controls
  g_mProjection: TD3DXMatrixA16;
  g_aLights: array[0..MAX_NUM_LIGHTS-1] of TLight; // Light objects
  g_bLeftButtonDown: Boolean = False;
  g_bRightButtonDown: Boolean = False;
  g_bMiddleButtonDown: Boolean = False;

//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_RENDERTYPE          = 5;
  IDC_ENABLELIGHT         = 6;
  IDC_LUMINANCELABEL      = 7;
  IDC_LUMINANCE           = 8;
  IDC_BACKGROUND          = 9;
  IDC_CHANGEMESH          = 10;
  IDC_MESHFILENAME        = 11;

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
procedure MouseProc(bLeftButtonDown, bRightButtonDown, bMiddleButtonDown, bSideButton1Down, bSideButton2Down: Boolean; nMouseWheelDelta: Integer; xPos, yPos: Integer; pUserContext: Pointer); stdcall;
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
procedure OnLostDevice(pUserContext: Pointer); stdcall;
procedure OnDestroyDevice(pUserContext: Pointer); stdcall;

procedure InitApp;
//todo: Fill bug report to MS
//function LoadMesh(const pd3dDevice: IDirect3DDevice9; wszName: PWideChar; out ppMesh: ID3DXMesh): HRESULT;
procedure RenderText;

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;



implementation



//--------------------------------------------------------------------------------------
// Takes an array of CEdgeMapping objects, then returns an index for the edge in the
// table if such entry exists, or returns an index at which a new entry for the edge
// can be written.
// nV1 and nV2 are the vertex indexes for the old edge.
// nCount is the number of elements in the array.
// The function returns -1 if an available entry cannot be found.  In reality,
// this should never happens as we should have allocated enough memory.
function FindEdgeInMappingTable(nV1, nV2: Integer; var pMapping: array of TEdgeMapping; nCount: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to nCount-1 do
  begin
    // If both vertex indexes of the old edge in mapping entry are -1, then
    // we have searched every valid entry without finding a match.  Return
    // this index as a newly created entry.
    if ((pMapping[i].m_anOldEdge[0] = -1) and (pMapping[i].m_anOldEdge[1] = -1) or
        // Or if we find a match, return the index.
        (pMapping[i].m_anOldEdge[1] = nV1) and (pMapping[i].m_anOldEdge[0] = nV2)) then
    begin
      Result:= i;
      Exit;
    end;
  end;

  Result:= -1;  // We should never reach this line
end;


//--------------------------------------------------------------------------------------
// Takes a mesh and generate a new mesh from it that contains the degenerate invisible
// quads for shadow volume extrusion.
function GenerateShadowMesh(const pd3dDevice: IDirect3DDevice9; const pMesh: ID3DXMesh; out ppOutMesh: ID3DXMesh): HRESULT;
var
  pInputMesh: ID3DXMesh;
  pdwAdj: PDWORD;
  pdwPtRep: PDWordArray;
  pVBData: PShadowVert;
  pdwIBData: PDWordArray;
  dwNumEdges: DWORD;
  pMapping: array of TEdgeMapping;
  nNumMaps: DWORD; // Integer;  // Number of entries that exist in pMapping
  pNewMesh: ID3DXMesh;
  pNewVBData: PShadowVertArray;
  pdwNewIBData: PDWordArray;
  nNextIndex: DWORD; // Integer;
  pNextOutVertex: PShadowVertArray;
  f: LongWord;
  v1, v2: TD3DXVector3;
  vNormal: TD3DXVector3;
  nIndex: Integer;
  nVertIndex: array[0..2] of Integer; 
  pPatchVBData: PShadowVertArray;
  pdwPatchIBData: PDWordArray;
  pPatchMesh: ID3DXMesh;
  nNextVertex: Integer;
  i, i2: Integer;
  nVertShared: Integer;
  nBefore, nAfter: Integer;
  bNeed32Bit: Boolean;
  pFinalMesh: ID3DXMesh;
  pFinalVBData: PShadowVert;
  pwFinalIBData: PWordArray;
begin
  ppOutMesh := nil;
  pMapping:= nil;

  // Convert the input mesh to a format same as the output mesh using 32-bit index.
  Result := pMesh.CloneMesh(D3DXMESH_32BIT, @TShadowVert_Decl, pd3dDevice, pInputMesh);
  if FAILED(Result) then Exit;

  DXUT_TRACE('Input mesh has %u vertices, %u faces'#10, [pInputMesh.GetNumVertices, pInputMesh.GetNumFaces]);

  // Generate adjacency information
  pdwAdj := nil;
  pdwPtRep := nil;
  try
    GetMem(pdwAdj, SizeOf(DWORD)*3*pInputMesh.GetNumFaces);
    GetMem(pdwPtRep, SizeOf(DWORD)*pInputMesh.GetNumVertices);
  except
    FreeMem(pdwAdj); FreeMem(pdwPtRep);
    Result:= E_OUTOFMEMORY;
    Exit;
  end;

  Result := pInputMesh.GenerateAdjacency(ADJACENCY_EPSILON, pdwAdj);
  if FAILED(Result) then
  begin
    FreeMem(pdwAdj); FreeMem(pdwPtRep);
    Exit;
  end;

  pInputMesh.ConvertAdjacencyToPointReps(pdwAdj, PDWORD(pdwPtRep));
  FreeMem(pdwAdj);

  pVBData:= nil; pdwIBData:= nil;
  pInputMesh.LockVertexBuffer(0, Pointer(pVBData));
  pInputMesh.LockIndexBuffer(0, Pointer(pdwIBData));

  try // "Lock" data protected block

  if Assigned(pVBData) and Assigned(pdwIBData) then
  begin
    // Maximum number of unique edges = Number of faces * 3
    dwNumEdges := pInputMesh.GetNumFaces * 3;
    try
      SetLength(pMapping, dwNumEdges);
      for i:= 0 to dwNumEdges - 1 do pMapping[i]:= EdgeMapping; // init them
    except
      pMapping:= nil;
    end;
    if Assigned(pMapping) then
    begin
      nNumMaps := 0;  // Number of entries that exist in pMapping

      // Create a new mesh
      Result := D3DXCreateMesh(pInputMesh.GetNumFaces + dwNumEdges * 2,
                               pInputMesh.GetNumFaces * 3,
                               D3DXMESH_32BIT,
                               @TShadowVert_Decl,
                               pd3dDevice,
                               pNewMesh);
      if SUCCEEDED(Result) then
      begin
        pNewVBData := nil;
        pdwNewIBData := nil;

        pNewMesh.LockVertexBuffer(0, Pointer(pNewVBData));
        pNewMesh.LockIndexBuffer(0, Pointer(pdwNewIBData));

        // nNextIndex is the array index in IB that the next vertex index value
        // will be store at.
        nNextIndex := 0;

        try // "cleanup" protected block
        
        if Assigned(pNewVBData) and Assigned(pdwNewIBData) then
        begin
          ZeroMemory(pNewVBData, pNewMesh.GetNumVertices * pNewMesh.GetNumBytesPerVertex);
          ZeroMemory(pdwNewIBData, SizeOf(DWORD) * pNewMesh.GetNumFaces * 3);

          // pNextOutVertex is the location to write the next
          // vertex to.
          pNextOutVertex := pNewVBData;

          // Iterate through the faces.  For each face, output new
          // vertices and face in the new mesh, and write its edges
          // to the mapping table.

          for f := 0 to pInputMesh.GetNumFaces - 1 do
          begin
            // Copy the vertex data for all 3 vertices
            CopyMemory(pNextOutVertex, PChar(pVBData) + pdwIBData[f * 3]*SizeOf(TShadowVert), SizeOf(TShadowVert));
            CopyMemory(@pNextOutVertex[1], PChar(pVBData) + pdwIBData[f * 3 + 1]*SizeOf(TShadowVert), SizeOf(TShadowVert));
            CopyMemory(@pNextOutVertex[2], PChar(pVBData) + pdwIBData[f * 3 + 2]*SizeOf(TShadowVert), SizeOf(TShadowVert));

            // Write out the face
            pdwNewIBData[nNextIndex] := f * 3;     Inc(nNextIndex);
            pdwNewIBData[nNextIndex] := f * 3 + 1; Inc(nNextIndex);
            pdwNewIBData[nNextIndex] := f * 3 + 2; Inc(nNextIndex);

            // Compute the face normal and assign it to
            // the normals of the vertices.
            D3DXVec3Subtract(v1, pNextOutVertex[1].Position, pNextOutVertex[0].Position);
            D3DXVec3Subtract(v2, pNextOutVertex[2].Position, pNextOutVertex[1].Position);
            D3DXVec3Cross(vNormal, v1, v2);
            D3DXVec3Normalize(vNormal, vNormal);

            pNextOutVertex[0].Normal := vNormal;
            pNextOutVertex[1].Normal := vNormal;
            pNextOutVertex[2].Normal := vNormal;

            pNextOutVertex := @pNextOutVertex[3];

            // Add the face's edges to the edge mapping table

            // Edge 1
            nVertIndex[0] :=  pdwPtRep[pdwIBData[f * 3]];
            nVertIndex[1] :=  pdwPtRep[pdwIBData[f * 3 + 1]];
            nVertIndex[2] :=  pdwPtRep[pdwIBData[f * 3 + 2]];
            nIndex := FindEdgeInMappingTable(nVertIndex[0], nVertIndex[1], pMapping, dwNumEdges);

            // If error, we are not able to proceed, so abort.
            if (-1 = nIndex) then
            begin
              Result := E_INVALIDARG;
              Exit; // goto cleanup;
            end;

            if (pMapping[nIndex].m_anOldEdge[0] = -1) and (pMapping[nIndex].m_anOldEdge[1] = -1) then
            begin
              // No entry for this edge yet.  Initialize one.
              pMapping[nIndex].m_anOldEdge[0] := nVertIndex[0];
              pMapping[nIndex].m_anOldEdge[1] := nVertIndex[1];
              pMapping[nIndex].m_aanNewEdge[0][0] := f * 3;
              pMapping[nIndex].m_aanNewEdge[0][1] := f * 3 + 1;

              Inc(nNumMaps);
            end else
            begin
              // An entry is found for this edge.  Create
              // a quad and output it.
              Assert(nNumMaps > 0);

              pMapping[nIndex].m_aanNewEdge[1][0] := f * 3;      // For clarity
              pMapping[nIndex].m_aanNewEdge[1][1] := f * 3 + 1;

              // First triangle
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[0][1]; Inc(nNextIndex);
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[0][0]; Inc(nNextIndex);
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[1][0]; Inc(nNextIndex);

              // Second triangle
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[1][1]; Inc(nNextIndex);
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[1][0]; Inc(nNextIndex);
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[0][0]; Inc(nNextIndex);

              // pMapping[nIndex] is no longer needed. Copy the last map entry
              // over and decrement the map count.

              pMapping[nIndex] := pMapping[nNumMaps-1];
              FillMemory(@pMapping[nNumMaps-1], SizeOf(pMapping[nNumMaps-1]), $ff);
              Dec(nNumMaps);
            end;

            // Edge 2
            nIndex := FindEdgeInMappingTable(nVertIndex[1], nVertIndex[2], pMapping, dwNumEdges);

            // If error, we are not able to proceed, so abort.
            if (-1 = nIndex) then
            begin
              Result := E_INVALIDARG;
              Exit; // goto cleanup;
            end;

            if (pMapping[nIndex].m_anOldEdge[0] = -1) and (pMapping[nIndex].m_anOldEdge[1] = -1) then
            begin
              pMapping[nIndex].m_anOldEdge[0] := nVertIndex[1];
              pMapping[nIndex].m_anOldEdge[1] := nVertIndex[2];
              pMapping[nIndex].m_aanNewEdge[0][0] := f * 3 + 1;
              pMapping[nIndex].m_aanNewEdge[0][1] := f * 3 + 2;

              Inc(nNumMaps);
            end else
            begin
              // An entry is found for this edge.  Create
              // a quad and output it.
              Assert(nNumMaps > 0);

              pMapping[nIndex].m_aanNewEdge[1][0] := f * 3 + 1;
              pMapping[nIndex].m_aanNewEdge[1][1] := f * 3 + 2;

              // First triangle
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[0][1]; Inc(nNextIndex);
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[0][0]; Inc(nNextIndex);
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[1][0]; Inc(nNextIndex);

              // Second triangle
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[1][1]; Inc(nNextIndex);
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[1][0]; Inc(nNextIndex);
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[0][0]; Inc(nNextIndex);

              // pMapping[nIndex] is no longer needed. Copy the last map entry
              // over and decrement the map count.

              pMapping[nIndex] := pMapping[nNumMaps-1];
              FillMemory(@pMapping[nNumMaps-1], SizeOf(pMapping[nNumMaps-1]), $ff);
              Dec(nNumMaps);
            end;

            // Edge 3
            nIndex := FindEdgeInMappingTable(nVertIndex[2], nVertIndex[0], pMapping, dwNumEdges);

            // If error, we are not able to proceed, so abort.
            if (-1 = nIndex) then
            begin
              Result := E_INVALIDARG;
              Exit; // goto cleanup;
            end;

            if (pMapping[nIndex].m_anOldEdge[0] = -1) and (pMapping[nIndex].m_anOldEdge[1] = -1) then
            begin
              pMapping[nIndex].m_anOldEdge[0] := nVertIndex[2];
              pMapping[nIndex].m_anOldEdge[1] := nVertIndex[0];
              pMapping[nIndex].m_aanNewEdge[0][0] := f * 3 + 2;
              pMapping[nIndex].m_aanNewEdge[0][1] := f * 3;

              Inc(nNumMaps);
            end else
            begin
              // An entry is found for this edge.  Create
              // a quad and output it.
              Assert(nNumMaps > 0);

              pMapping[nIndex].m_aanNewEdge[1][0] := f * 3 + 2;
              pMapping[nIndex].m_aanNewEdge[1][1] := f * 3;

              // First triangle
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[0][1]; Inc(nNextIndex);
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[0][0]; Inc(nNextIndex);
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[1][0]; Inc(nNextIndex);

              // Second triangle
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[1][1]; Inc(nNextIndex);
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[1][0]; Inc(nNextIndex);
              pdwNewIBData[nNextIndex] := pMapping[nIndex].m_aanNewEdge[0][0]; Inc(nNextIndex);

              // pMapping[nIndex] is no longer needed. Copy the last map entry
              // over and decrement the map count.

              pMapping[nIndex] := pMapping[nNumMaps-1];
              FillMemory(@pMapping[nNumMaps-1], SizeOf( pMapping[nNumMaps-1] ), $ff);
              Dec(nNumMaps);
            end;
          end;

          // Now the entries in the edge mapping table represent
          // non-shared edges.  What they mean is that the original
          // mesh has openings (holes), so we attempt to patch them.
          // First we need to recreate our mesh with a larger vertex
          // and index buffers so the patching geometry could fit.

          DXUT_TRACE('Faces to patch: %d'#10, [nNumMaps]);

          // Create a mesh with large enough vertex and
          // index buffers.

          pPatchVBData := nil;
          pdwPatchIBData := nil;

          // Make enough room in IB for the face and up to 3 quads for each patching face
          Result := D3DXCreateMesh(nNextIndex div 3 + nNumMaps * 7,
                                   (pInputMesh.GetNumFaces + nNumMaps) * 3,
                                   D3DXMESH_32BIT,
                                   @TShadowVert_Decl,
                                   pd3dDevice,
                                   pPatchMesh);
          if FAILED(Result) then Exit; // goto cleanup;

          Result := pPatchMesh.LockVertexBuffer(0, Pointer(pPatchVBData));
          if SUCCEEDED(Result) then
              Result := pPatchMesh.LockIndexBuffer(0, Pointer(pdwPatchIBData));

          if Assigned(pPatchVBData) and Assigned(pdwPatchIBData) then 
          begin
            ZeroMemory(pPatchVBData, SizeOf(TShadowVert) * (pInputMesh.GetNumFaces + nNumMaps) * 3);
            ZeroMemory(pdwPatchIBData, SizeOf(DWORD) * (nNextIndex + 3 * nNumMaps * 7));

            // Copy the data from one mesh to the other

            CopyMemory(pPatchVBData, pNewVBData, SizeOf(TShadowVert) * pInputMesh.GetNumFaces * 3);
            CopyMemory(pdwPatchIBData, pdwNewIBData, SizeOf(DWORD) * nNextIndex);
          end else
          begin
            // Some serious error is preventing us from locking.
            // Abort and return error.

            pPatchMesh := nil;
            // goto cleanup;
            Exit;
          end;

          // Replace pNewMesh with the updated one.  Then the code
          // can continue working with the pNewMesh pointer.

          pNewMesh.UnlockVertexBuffer;
          pNewMesh.UnlockIndexBuffer;
          pNewVBData := pPatchVBData;
          pdwNewIBData := pdwPatchIBData;
          pNewMesh := nil;
          pNewMesh := pPatchMesh;

          // Now, we iterate through the edge mapping table and
          // for each shared edge, we generate a quad.
          // For each non-shared edge, we patch the opening
          // with new faces.

          // nNextVertex is the index of the next vertex.
          nNextVertex := pInputMesh.GetNumFaces * 3;

          for i := 0 to nNumMaps-1 do
          begin
            if (pMapping[i].m_anOldEdge[0] <> -1) and
               (pMapping[i].m_anOldEdge[1] <> -1) then
            begin
              // If the 2nd new edge indexes is -1,
              // this edge is a non-shared one.
              // We patch the opening by creating new
              // faces.
              if (pMapping[i].m_aanNewEdge[1][0] = -1) or  // must have only one new edge
                 (pMapping[i].m_aanNewEdge[1][1] = -1) then
              begin
                // Find another non-shared edge that
                // shares a vertex with the current edge.
                for i2 := i + 1 to nNumMaps - 1 do
                begin
                  if (pMapping[i2].m_anOldEdge[0] <> -1) and       // must have a valid old edge
                     (pMapping[i2].m_anOldEdge[1] <> -1) and
                     ((pMapping[i2].m_aanNewEdge[1][0] = -1) or // must have only one new edge
                      (pMapping[i2].m_aanNewEdge[1][1] = -1)) then
                  begin
                    nVertShared := 0;
                    if (pMapping[i2].m_anOldEdge[0] = pMapping[i].m_anOldEdge[1]) then Inc(nVertShared);
                    if (pMapping[i2].m_anOldEdge[1] = pMapping[i].m_anOldEdge[0]) then Inc(nVertShared);

                    if (2 = nVertShared) then 
                    begin
                      // These are the last two edges of this particular
                      // opening. Mark this edge as shared so that a degenerate
                      // quad can be created for it.

                      pMapping[i2].m_aanNewEdge[1][0] := pMapping[i].m_aanNewEdge[0][0];
                      pMapping[i2].m_aanNewEdge[1][1] := pMapping[i].m_aanNewEdge[0][1];
                      Break;
                    end
                    else
                    if (1 = nVertShared) then
                    begin
                      // nBefore and nAfter tell us which edge comes before the other.
                      if (pMapping[i2].m_anOldEdge[0] = pMapping[i].m_anOldEdge[1]) then
                      begin
                        nBefore := i;
                        nAfter := i2;
                      end else
                      begin
                        nBefore := i2;
                        nAfter := i;
                      end;

                      // Found such an edge. Now create a face along with two
                      // degenerate quads from these two edges.

                      pNewVBData[nNextVertex] := pNewVBData[pMapping[nAfter].m_aanNewEdge[0][1]];
                      pNewVBData[nNextVertex+1] := pNewVBData[pMapping[nBefore].m_aanNewEdge[0][1]];
                      pNewVBData[nNextVertex+2] := pNewVBData[pMapping[nBefore].m_aanNewEdge[0][0]];
                      // Recompute the normal
                      D3DXVec3Subtract(v1, pNewVBData[nNextVertex+1].Position, pNewVBData[nNextVertex].Position);
                      D3DXVec3Subtract(v2, pNewVBData[nNextVertex+2].Position, pNewVBData[nNextVertex+1].Position);
                      D3DXVec3Normalize(v1, v1);
                      D3DXVec3Normalize(v2, v2);
                      D3DXVec3Cross(vNormal, v1, v2);
                      pNewVBData[nNextVertex].Normal := vNormal;
                      pNewVBData[nNextVertex+1].Normal := vNormal;
                      pNewVBData[nNextVertex+2].Normal := vNormal;

                      pdwNewIBData[nNextIndex] := nNextVertex;
                      pdwNewIBData[nNextIndex+1] := nNextVertex + 1;
                      pdwNewIBData[nNextIndex+2] := nNextVertex + 2;

                      // 1st quad

                      pdwNewIBData[nNextIndex+3] := pMapping[nBefore].m_aanNewEdge[0][1];
                      pdwNewIBData[nNextIndex+4] := pMapping[nBefore].m_aanNewEdge[0][0];
                      pdwNewIBData[nNextIndex+5] := nNextVertex + 1;

                      pdwNewIBData[nNextIndex+6] := nNextVertex + 2;
                      pdwNewIBData[nNextIndex+7] := nNextVertex + 1;
                      pdwNewIBData[nNextIndex+8] := pMapping[nBefore].m_aanNewEdge[0][0];

                      // 2nd quad

                      pdwNewIBData[nNextIndex+9] := pMapping[nAfter].m_aanNewEdge[0][1];
                      pdwNewIBData[nNextIndex+10] := pMapping[nAfter].m_aanNewEdge[0][0];
                      pdwNewIBData[nNextIndex+11] := nNextVertex;

                      pdwNewIBData[nNextIndex+12] := nNextVertex + 1;
                      pdwNewIBData[nNextIndex+13] := nNextVertex;
                      pdwNewIBData[nNextIndex+14] := pMapping[nAfter].m_aanNewEdge[0][0];

                      // Modify mapping entry i2 to reflect the third edge
                      // of the newly added face.

                      if (pMapping[i2].m_anOldEdge[0] = pMapping[i].m_anOldEdge[1]) then
                      begin
                        pMapping[i2].m_anOldEdge[0] := pMapping[i].m_anOldEdge[0];
                      end else
                      begin
                        pMapping[i2].m_anOldEdge[1] := pMapping[i].m_anOldEdge[1];
                      end;
                      pMapping[i2].m_aanNewEdge[0][0] := nNextVertex + 2;
                      pMapping[i2].m_aanNewEdge[0][1] := nNextVertex;

                      // Update next vertex/index positions

                      Inc(nNextVertex, 3);
                      Inc(nNextIndex, 15);

                      Break;
                    end;
                  end;
                end;
              end else
              begin
                // This is a shared edge.  Create the degenerate quad.

                // First triangle
                pdwNewIBData[nNextIndex] := pMapping[i].m_aanNewEdge[0][1]; Inc(nNextIndex);
                pdwNewIBData[nNextIndex] := pMapping[i].m_aanNewEdge[0][0]; Inc(nNextIndex);
                pdwNewIBData[nNextIndex] := pMapping[i].m_aanNewEdge[1][0]; Inc(nNextIndex);

                // Second triangle
                pdwNewIBData[nNextIndex] := pMapping[i].m_aanNewEdge[1][1]; Inc(nNextIndex);
                pdwNewIBData[nNextIndex] := pMapping[i].m_aanNewEdge[1][0]; Inc(nNextIndex);
                pdwNewIBData[nNextIndex] := pMapping[i].m_aanNewEdge[0][0]; Inc(nNextIndex);
              end;
            end;
          end;
        end;

        finally // cleanup:;

          if Assigned(pNewVBData) then
          begin
            pNewMesh.UnlockVertexBuffer;
            pNewVBData := nil;
          end;
          if Assigned(pdwNewIBData) then 
          begin
            pNewMesh.UnlockIndexBuffer;
            pdwNewIBData := nil;
          end;

          if SUCCEEDED(Result) then
          begin
            // At this time, the output mesh may have an index buffer
            // bigger than what is actually needed, so we create yet
            // another mesh with the exact IB size that we need and
            // output it.  This mesh also uses 16-bit index if
            // 32-bit is not necessary.

            DXUT_TRACE('Shadow volume has %u vertices, %u faces.'#10, [(pInputMesh.GetNumFaces + nNumMaps ) * 3, nNextIndex div 3]);

            bNeed32Bit := ( pInputMesh.GetNumFaces + nNumMaps ) * 3 > 65535;
            Result := D3DXCreateMesh(nNextIndex div 3,  // Exact number of faces
                                    ( pInputMesh.GetNumFaces + nNumMaps ) * 3,
                                    D3DXMESH_WRITEONLY or IfThen(bNeed32Bit, D3DXMESH_32BIT,0),
                                    @TShadowVert_Decl,
                                    pd3dDevice,
                                    pFinalMesh);
            if SUCCEEDED(Result) then
            begin
              pNewMesh.LockVertexBuffer(0, Pointer(pNewVBData));
              pNewMesh.LockIndexBuffer(0, Pointer(pdwNewIBData));

              pFinalVBData := nil;
              pwFinalIBData := nil;

              pFinalMesh.LockVertexBuffer(0, Pointer(pFinalVBData));
              pFinalMesh.LockIndexBuffer(0, Pointer(pwFinalIBData));

              if Assigned(pNewVBData) and Assigned(pdwNewIBData) and Assigned(pFinalVBData) and Assigned(pwFinalIBData) then
              begin
                CopyMemory(pFinalVBData, pNewVBData, SizeOf(TShadowVert) * (pInputMesh.GetNumFaces + nNumMaps) * 3);

                if (bNeed32Bit) then
                  CopyMemory(pwFinalIBData, pdwNewIBData, SizeOf(DWORD) * nNextIndex)
                else
                begin
                  for i := 0 to nNextIndex - 1 do
                    pwFinalIBData[i] := pdwNewIBData[i];
                end;
              end;

              if Assigned(pNewVBData) then pNewMesh.UnlockVertexBuffer;
              if Assigned(pdwNewIBData) then pNewMesh.UnlockIndexBuffer;
              if Assigned(pFinalVBData) then pFinalMesh.UnlockVertexBuffer;
              if Assigned(pwFinalIBData) then pFinalMesh.UnlockIndexBuffer;

              // Release the old
              // pNewMesh := nil;
              pNewMesh := pFinalMesh;
            end;

            ppOutMesh := pNewMesh;
          end
          else
            pNewMesh:= nil;
        end;
      end;
      pMapping:= nil; // delete[] pMapping;
    end else
      Result := E_OUTOFMEMORY;
  end else
    Result := E_FAIL;

  finally //   try // "Lock" data protected block
    if Assigned(pVBData) then pInputMesh.UnlockVertexBuffer;
    if Assigned(pdwIBData) then pInputMesh.UnlockIndexBuffer;

    FreeMem(pdwPtRep);
    pInputMesh := nil; // not necessary in Delphi
  end;
end;


//--------------------------------------------------------------------------------------
// Initialize the app
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  pDSFormats: TD3DFormatArray;
  iY: Integer;
  L: Integer;
  m: TD3DXMatrixA16;
begin
  // This sample requires a stencil buffer. See the callback function for details.
  SetLength(pDSFormats, 4);
  pDSFormats[0]:= D3DFMT_D24S8;
  pDSFormats[1]:= D3DFMT_D24X4S4;
  pDSFormats[2]:= D3DFMT_D15S1;
  pDSFormats[3]:= D3DFMT_D24FS8;
  DXUTGetEnumeration.PossibleDepthStencilFormatList:= pDSFormats;

  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_SampleUI.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent);
  iY := 10; g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 35, iY, 125, 22, VK_F2);

  g_SampleUI.SetCallback(OnGUIEvent); iY := 10;
  Inc(iY, 24);
  g_SampleUI.AddComboBox(IDC_BACKGROUND, 0, iY, 190, 22, 0, False);
  g_SampleUI.GetComboBox(IDC_BACKGROUND).SetDropHeight( 40);
  g_SampleUI.GetComboBox(IDC_BACKGROUND).AddItem('Background: Cell', Pointer(0));
  g_SampleUI.GetComboBox(IDC_BACKGROUND).AddItem('Background: Field', Pointer(1));
  Inc(iY, 24);
  g_SampleUI.AddComboBox(IDC_ENABLELIGHT, 0, iY, 190, 22, 0, false);
  g_SampleUI.GetComboBox(IDC_ENABLELIGHT).SetDropHeight( 90);
  g_SampleUI.GetComboBox(IDC_ENABLELIGHT).AddItem('1 light', Pointer(1));
  g_SampleUI.GetComboBox(IDC_ENABLELIGHT).AddItem('2 lights', Pointer(2));
  g_SampleUI.GetComboBox(IDC_ENABLELIGHT).AddItem('3 lights', Pointer(3));
  g_SampleUI.GetComboBox(IDC_ENABLELIGHT).AddItem('4 lights', Pointer(4));
  g_SampleUI.GetComboBox(IDC_ENABLELIGHT).AddItem('5 lights', Pointer(5));
  g_SampleUI.GetComboBox(IDC_ENABLELIGHT).AddItem('6 lights', Pointer(6));
  Inc(iY, 24);
  g_SampleUI.AddComboBox(IDC_RENDERTYPE, 0, iY, 190, 22, 0, False);
  g_SampleUI.GetComboBox(IDC_RENDERTYPE).SetDropHeight(50);
  g_SampleUI.GetComboBox(IDC_RENDERTYPE).AddItem('Scene with shadow', Pointer(RENDERTYPE_SCENE));
  g_SampleUI.GetComboBox(IDC_RENDERTYPE).AddItem('Show shadow volume', Pointer(RENDERTYPE_SHADOWVOLUME));
  g_SampleUI.GetComboBox(IDC_RENDERTYPE).AddItem('Shadow volume complexity', Pointer(RENDERTYPE_COMPLEXITY));
  Inc(iY, 30);
  g_SampleUI.AddStatic(IDC_LUMINANCELABEL, 'Luminance: 15.0', 45, iY, 125, 22);
  Inc(iY, 20);
  g_SampleUI.AddSlider(IDC_LUMINANCE, 45, iY, 125, 22, 1, 40, 15);
  Inc(iY, 26);
  g_SampleUI.AddButton(IDC_CHANGEMESH, 'Change mesh', 80, iY, 120, 40);

  // Initialize cameras
  g_Camera.SetRotateButtons(True, False, False);
  g_MCamera.SetButtonMasks(MOUSE_RIGHT_BUTTON, 0, 0);
  g_LCamera.SetButtonMasks(MOUSE_MIDDLE_BUTTON, 0, 0);

  // Initialize the lights
  for L := 0 to MAX_NUM_LIGHTS-1 do
  begin
    D3DXMatrixScaling(g_aLights[L].m_mWorld, 0.1, 0.1, 0.1);
    D3DXMatrixTranslation(m, g_LightInit[L].Position.x,
                             g_LightInit[L].Position.y,
                             g_LightInit[L].Position.z);
    D3DXMatrixMultiply( g_aLights[L].m_mWorld, g_aLights[L].m_mWorld, m);
    g_aLights[L].m_Position := g_LightInit[L].Position;
    g_aLights[L].m_Color := g_LightInit[L].Color;
  end;

  // Initialize the scaling and translation for the background meshes
  // Hardcode the matrices since we only have two.
  D3DXMatrixTranslation(g_mWorldBack[0], 0.0, 2.0, 0.0);
  D3DXMatrixScaling(g_mWorldBack[1], 0.3, 0.3, 0.3);
  D3DXMatrixTranslation(m, 0.0, 1.5, 0.0);
  D3DXMatrixMultiply(g_mWorldBack[1], g_mWorldBack[1], m);
end;


//--------------------------------------------------------------------------------------
// Returns true if a particular depth-stencil format can be created and used with
// an adapter format and backbuffer format combination.
function IsDepthFormatOk(DepthFormat, AdapterFormat, BackBufferFormat: TD3DFormat): Boolean;
begin
  Result:= False;

  // Verify that the depth format exists
  if Failed(DXUTGetD3DObject.CheckDeviceFormat(D3DADAPTER_DEFAULT,
                                               D3DDEVTYPE_HAL,
                                               AdapterFormat,
                                               D3DUSAGE_DEPTHSTENCIL,
                                               D3DRTYPE_SURFACE,
                                               DepthFormat))
  then Exit;

  // Verify that the backbuffer format is valid
  if Failed(DXUTGetD3DObject.CheckDeviceFormat(D3DADAPTER_DEFAULT,
                                               D3DDEVTYPE_HAL,
                                               AdapterFormat,
                                               D3DUSAGE_RENDERTARGET,
                                               D3DRTYPE_SURFACE,
                                               BackBufferFormat))
  then Exit;

  // Verify that the depth format is compatible
  if Failed(DXUTGetD3DObject.CheckDepthStencilMatch(D3DADAPTER_DEFAULT,
                                                    D3DDEVTYPE_HAL,
                                                    AdapterFormat,
                                                    BackBufferFormat,
                                                    DepthFormat))
  then Exit;

  Result:= True;
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

  // Must support pixel shader 2.0
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2,0)) then Exit;

  // Must support stencil buffer
  if not IsDepthFormatOk(D3DFMT_D24S8,
                         AdapterFormat,
                         BackBufferFormat) and
     not IsDepthFormatOk(D3DFMT_D24X4S4,
                         AdapterFormat,
                         BackBufferFormat) and
     not IsDepthFormatOk(D3DFMT_D15S1,
                         AdapterFormat,
                         BackBufferFormat) and
     not IsDepthFormatOk(D3DFMT_D24FS8,
                         AdapterFormat,
                         BackBufferFormat)
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

  // This sample requires a stencil buffer.
  if IsDepthFormatOk(D3DFMT_D24S8,
                     pDeviceSettings.AdapterFormat,
                     pDeviceSettings.pp.BackBufferFormat) 
  then
    pDeviceSettings.pp.AutoDepthStencilFormat := D3DFMT_D24S8
  else
  if IsDepthFormatOk(D3DFMT_D24X4S4,
                     pDeviceSettings.AdapterFormat,
                     pDeviceSettings.pp.BackBufferFormat)
  then
    pDeviceSettings.pp.AutoDepthStencilFormat := D3DFMT_D24X4S4
  else
  if IsDepthFormatOk(D3DFMT_D24FS8,
                     pDeviceSettings.AdapterFormat,
                     pDeviceSettings.pp.BackBufferFormat)
  then
    pDeviceSettings.pp.AutoDepthStencilFormat := D3DFMT_D24FS8
  else
  if IsDepthFormatOk(D3DFMT_D15S1,
                     pDeviceSettings.AdapterFormat,
                     pDeviceSettings.pp.BackBufferFormat)
  then
    pDeviceSettings.pp.AutoDepthStencilFormat := D3DFMT_D15S1;

  // For the first device created if its a REF device, optionally display a warning dialog box
  if s_bFirstTime then
  begin
    s_bFirstTime := False;
    if (pDeviceSettings.DeviceType = D3DDEVTYPE_REF) then DXUTDisplaySwitchingToREFWarning;
  end;

  Result:= True;
end;


// Compute a matrix that scales Mesh to a specified size and centers around origin
procedure ComputeMeshScaling(const Mesh: CDXUTMesh; out pmScalingCenter: TD3DXMatrix);
var
  pVerts: Pointer;
  vCtr: TD3DXVector3;
  fRadius: Single;
  m: TD3DXMatrixA16;
begin
  pVerts := nil;
  D3DXMatrixIdentity(pmScalingCenter);
  if SUCCEEDED(Mesh.Mesh.LockVertexBuffer(0, pVerts)) then
  begin
    if SUCCEEDED(D3DXComputeBoundingSphere(PD3DXVector3(pVerts),
                                              Mesh.Mesh.GetNumVertices,
                                              Mesh.Mesh.GetNumBytesPerVertex,
                                              vCtr, fRadius)) then
    begin
      D3DXMatrixTranslation(pmScalingCenter, -vCtr.x, -vCtr.y, -vCtr.z);
      D3DXMatrixScaling(m, 1.0 / fRadius, 1.0 / fRadius, 1.0 / fRadius);
      D3DXMatrixMultiply(pmScalingCenter, pmScalingCenter, m);
    end;
    Mesh.Mesh.UnlockVertexBuffer;
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
  Caps: TD3DCaps9;
  vecEye: TD3DXVector3;
  vecAt: TD3DXVector3;
  lr: TD3DLockedRect;
begin
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  // Initialize the vertex declaration
  Result:= pd3dDevice.CreateVertexDeclaration(@TMeshVert_Decl, g_pMeshDecl);
  if V_Failed(Result) then Exit;
  Result:= pd3dDevice.CreateVertexDeclaration(@TShadowVert_Decl, g_pShadowDecl);
  if V_Failed(Result) then Exit;
  Result:= pd3dDevice.CreateVertexDeclaration(@TPostProcVert_Decl, g_pPProcDecl);
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
  dwShaderFlags := dwShaderFlags or D3DXSHADER_SKIPOPTIMIZATION or D3DXSHADER_DEBUG;
  {$ENDIF}
  {$IFDEF DEBUG_PS}
  dwShaderFlags := dwShaderFlags or D3DXSHADER_SKIPOPTIMIZATION or D3DXSHADER_DEBUG;
  {$ENDIF}

  // Read the D3DX effect file
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'ShadowVolume.fx');
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // they the .fx file failed to compile
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags,
                                     nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  // Determine the rendering techniques to use based on device caps
  Result:= pd3dDevice.GetDeviceCaps(Caps);
  if V_Failed(Result) then Exit;

  g_hRenderScene := g_pEffect.GetTechniqueByName('RenderScene');

  // If 2-sided stencil is supported, use it.
  if (Caps.StencilCaps and D3DSTENCILCAPS_TWOSIDED <> 0) then
  begin
    g_hRenderShadow := g_pEffect.GetTechniqueByName('RenderShadowVolume2Sided');
    g_hShowShadow := g_pEffect.GetTechniqueByName('ShowShadowVolume2Sided');
  end else
  begin
    g_hRenderShadow := g_pEffect.GetTechniqueByName('RenderShadowVolume');
    g_hShowShadow := g_pEffect.GetTechniqueByName('ShowShadowVolume');
  end;

  // Load the meshes
  Result:= g_Background[0].CreateMesh(pd3dDevice, 'misc\cell.x');     if V_Failed(Result) then Exit;
  g_Background[0].SetVertexDecl(pd3dDevice, @TMeshVert_Decl);
  Result:= g_Background[1].CreateMesh(pd3dDevice, 'misc\seafloor.x'); if V_Failed(Result) then Exit;
  g_Background[1].SetVertexDecl(pd3dDevice, @TMeshVert_Decl);
  Result:= g_LightMesh.CreateMesh(pd3dDevice, 'misc\sphere0.x');      if V_Failed(Result) then Exit;
  g_LightMesh.SetVertexDecl(pd3dDevice, @TMeshVert_Decl);
  Result:= g_Mesh.CreateMesh(pd3dDevice, DEFMESHFILENAME);            if V_Failed(Result) then Exit;
  g_Mesh.SetVertexDecl(pd3dDevice, @TMeshVert_Decl);

  // Compute the scaling matrix for the mesh so that the size of the mesh
  // that shows on the screen is consistent.
  ComputeMeshScaling(g_Mesh, g_mWorldScaling);

  // Setup the camera's view parameters
  vecEye := D3DXVector3(0.0, 0.0, -5.0);
  vecAt  := D3DXVector3(0.0, 0.0, -0.0);
  g_Camera.SetViewParams(vecEye, vecAt);
  g_LCamera.SetViewParams(vecEye, vecAt);
  g_MCamera.SetViewParams(vecEye, vecAt);

  // Create the 1x1 white default texture
  Result:= pd3dDevice.CreateTexture(1, 1, 1, 0, D3DFMT_A8R8G8B8,
                                       D3DPOOL_MANAGED, g_pDefaultTex, nil);
  if V_Failed(Result) then Exit;
  Result:= g_pDefaultTex.LockRect(0, lr, nil, 0);
  if V_Failed(Result) then Exit;
  PDWORD(lr.pBits)^ := D3DCOLOR_RGBA(255, 255, 255, 255);
  Result:= g_pDefaultTex.UnlockRect(0);
  if V_Failed(Result) then Exit;

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
  iY: Integer;
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

  g_Background[0].RestoreDeviceObjects(pd3dDevice);
  g_Background[1].RestoreDeviceObjects(pd3dDevice);
  g_LightMesh.RestoreDeviceObjects(pd3dDevice);
  g_Mesh.RestoreDeviceObjects(pd3dDevice);

  // Create a sprite to help batch calls when drawing many lines of text
  Result:= D3DXCreateSprite(pd3dDevice, g_pTextSprite);
  if V_Failed(Result) then Exit;

  // Setup the camera's projection parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI/4, fAspectRatio, 0.1, 20.0);
  g_MCamera.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);
  g_LCamera.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);
  g_pEffect.SetFloat('g_fFarClip', 20.0 - EXTRUDE_EPSILON);
  V(g_pEffect.SetMatrix('g_mProj', g_Camera.GetProjMatrix^));

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation(0, pBackBufferSurfaceDesc.Height-200);
  g_SampleUI.SetSize(pBackBufferSurfaceDesc.Width, 150);

  iY := 10;
  Inc(iY, 24); g_SampleUI.GetControl(IDC_BACKGROUND).SetLocation(pBackBufferSurfaceDesc.Width - 200, iY);
  Inc(iY, 24); g_SampleUI.GetControl(IDC_ENABLELIGHT).SetLocation(pBackBufferSurfaceDesc.Width - 200, iY);
  Inc(iY, 24); g_SampleUI.GetControl(IDC_RENDERTYPE).SetLocation(pBackBufferSurfaceDesc.Width - 200, iY);
  Inc(iY, 30); g_SampleUI.GetControl(IDC_LUMINANCELABEL).SetLocation(pBackBufferSurfaceDesc.Width - 145, iY);
  Inc(iY, 20); g_SampleUI.GetControl(IDC_LUMINANCE).SetLocation(pBackBufferSurfaceDesc.Width - 145, iY);
  Inc(iY, 26); g_SampleUI.GetControl(IDC_CHANGEMESH).SetLocation(pBackBufferSurfaceDesc.Width - 120, iY);
  if Assigned(g_SampleUI.GetControl(IDC_MESHFILENAME))
  then g_SampleUI.GetControl(IDC_MESHFILENAME).SetLocation(pBackBufferSurfaceDesc.Width - 540, iY);

  // Generate the shadow volume mesh
  GenerateShadowMesh(pd3dDevice, g_Mesh.Mesh, g_pShadowMesh);

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
  g_MCamera.FrameMove(fElapsedTime);
  g_LCamera.FrameMove(fElapsedTime);
end;


//--------------------------------------------------------------------------------------
// Simply renders the entire scene without any shadow handling.
procedure RenderScene(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; bRenderLight: Boolean);
var
  mWorldView: TD3DXMatrixA16;
  mViewProj: TD3DXMatrixA16;
  mWorldViewProjection: TD3DXMatrixA16;
  mm: TD3DXMatrixA16;
  hCurrTech: TD3DXHandle;
  vLightMat: TD3DXVector4;
  cPasses: LongWord;
  pMesh: ID3DXMesh;
  p, i, m: Integer;
  vAmb: TD3DXVector4;
begin
  // Get the projection & view matrix from the camera class
  D3DXMatrixMultiply(mViewProj, g_Camera.GetViewMatrix^, g_Camera.GetProjMatrix^);

  // Render the lights if requested
  if bRenderLight then
  begin
    hCurrTech := g_pEffect.GetCurrentTechnique;  // Save the current technique
    V(g_pEffect.SetTechnique('RenderSceneAmbient'));
    V(g_pEffect.SetTexture('g_txScene', g_pDefaultTex));
    vLightMat := D3DXVector4(1.0, 1.0, 1.0, 1.0);
    V(g_pEffect.SetVector('g_vMatColor', vLightMat));
    pMesh := g_LightMesh.Mesh;
    V(g_pEffect._Begin(@cPasses, 0));
    for p := 0 to cPasses - 1 do
    begin
      V(g_pEffect.BeginPass(p));
      for i := 0 to g_nNumLights - 1 do
      begin
        for m := 0 to g_LightMesh.m_dwNumMaterials - 1 do
        begin
          // mWorldView := g_aLights[i].m_mWorld * *g_LCamera.GetWorldMatrix * *g_Camera.GetViewMatrix;
          D3DXMatrixMultiply(mm, g_aLights[i].m_mWorld, g_LCamera.GetWorldMatrix^);
          D3DXMatrixMultiply(mWorldView, mm, g_Camera.GetViewMatrix^);
          // mWorldViewProjection := mWorldView * *g_Camera.GetProjMatrix;
          D3DXMatrixMultiply(mWorldViewProjection, mWorldView, g_Camera.GetProjMatrix^);
          V(g_pEffect.SetMatrix('g_mWorldView', mWorldView));
          V(g_pEffect.SetMatrix('g_mWorldViewProjection', mWorldViewProjection));
          V(g_pEffect.SetVector('g_vAmbient', g_aLights[i].m_Color));

          // The effect interface queues up the changes and performs them
          // with the CommitChanges call. You do not need to call CommitChanges if
          // you are not setting any parameters between the BeginPass and EndPass.
          V(g_pEffect.CommitChanges);

          V(pMesh.DrawSubset(m));
        end;
      end;
      V(g_pEffect.EndPass);
    end;
    V(g_pEffect._End);
    V(g_pEffect.SetTechnique(hCurrTech)); // Restore the old technique
    vAmb := D3DXVector4(AMBIENT, AMBIENT, AMBIENT, 1.0);
    V(g_pEffect.SetVector('g_vAmbient', vAmb));
  end;

  // Render the background mesh
  V(pd3dDevice.SetVertexDeclaration(g_pMeshDecl));
  // mWorldView := g_mWorldBack[g_nCurrBackground] * *g_Camera.GetViewMatrix;
  D3DXMatrixMultiply(mWorldView, g_mWorldBack[g_nCurrBackground], g_Camera.GetViewMatrix^);
  // mWorldViewProjection := g_mWorldBack[g_nCurrBackground] * mViewProj;
  D3DXMatrixMultiply(mWorldViewProjection, g_mWorldBack[g_nCurrBackground], mViewProj);
  V(g_pEffect.SetMatrix('g_mWorldViewProjection', mWorldViewProjection));
  V(g_pEffect.SetMatrix('g_mWorldView', mWorldView));
  V(g_pEffect._Begin(@cPasses, 0 ));
  for p := 0 to cPasses - 1 do
  begin
    V(g_pEffect.BeginPass(p));
    pMesh := g_Background[g_nCurrBackground].Mesh;
    for i := 0 to g_Background[g_nCurrBackground].m_dwNumMaterials - 1 do
    begin
      V(g_pEffect.SetVector('g_vMatColor', PD3DXVECTOR4(@g_Background[g_nCurrBackground].m_pMaterials[i].Diffuse)^));
      if Assigned(g_Background[g_nCurrBackground].m_pTextures[i])
      then V(g_pEffect.SetTexture('g_txScene', g_Background[g_nCurrBackground].m_pTextures[i]))
      else V(g_pEffect.SetTexture('g_txScene', g_pDefaultTex));
      // The effect interface queues up the changes and performs them
      // with the CommitChanges call. You do not need to call CommitChanges if
      // you are not setting any parameters between the BeginPass and EndPass.
      V(g_pEffect.CommitChanges);
      V(pMesh.DrawSubset(i));
    end;
    V(g_pEffect.EndPass);
  end;
  V(g_pEffect._End);

  // Render the mesh
  V(pd3dDevice.SetVertexDeclaration(g_pMeshDecl));
  // mWorldView = g_mWorldScaling * *g_MCamera.GetWorldMatrix() * *g_Camera.GetViewMatrix();
  D3DXMatrixMultiply(mm, g_mWorldScaling, g_MCamera.GetWorldMatrix^);
  D3DXMatrixMultiply(mWorldView, mm, g_Camera.GetViewMatrix^);
  // mWorldViewProjection = mWorldView * *g_Camera.GetProjMatrix();
  D3DXMatrixMultiply(mWorldViewProjection, mWorldView, g_Camera.GetProjMatrix^);
  V(g_pEffect.SetMatrix('g_mWorldViewProjection', mWorldViewProjection));
  V(g_pEffect.SetMatrix('g_mWorldView', mWorldView));
  V(g_pEffect._Begin(@cPasses, 0 ));
  for p := 0 to cPasses - 1 do
  begin
    V(g_pEffect.BeginPass(p));
    pMesh := g_Mesh.Mesh;
    for i := 0 to g_Mesh.m_dwNumMaterials - 1 do
    begin
      V(g_pEffect.SetVector('g_vMatColor', PD3DXVECTOR4(@g_Mesh.m_pMaterials[i].Diffuse)^));
      if Assigned(g_Mesh.m_pTextures[i])
      then V(g_pEffect.SetTexture('g_txScene', g_Mesh.m_pTextures[i]))
      else V(g_pEffect.SetTexture('g_txScene', g_pDefaultTex));
      // The effect interface queues up the changes and performs them
      // with the CommitChanges call. You do not need to call CommitChanges if
      // you are not setting any parameters between the BeginPass and EndPass.
      V(g_pEffect.CommitChanges);
      V(pMesh.DrawSubset(i));
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
  vAmb: TD3DXVector4;
  L, i, p: Integer;
  vLight: TD3DXVector4;
  cPasses: LongWord;
  pd3dsdBackBuffer: PD3DSurfaceDesc;
  quad: array[0..3] of TPostProcVert;
{$IFDEF SYNCRO_BY_FENCE}
  fBackBuffer: IDirect3DSurface9;
  lr: TD3DLockedRect;
  fence: IDirect3DQuery9;
{$ENDIF}
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
    DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'Demonstration Code');

    // First, render the scene with only ambient lighting
    begin
      // CDXUTPerfEventGenerator g( DXUT_PERFEVENTCOLOR, L"Scene Ambient" );
      D3DPERF_BeginEvent(DXUT_PERFEVENTCOLOR, 'Scene Ambient');

      g_pEffect.SetTechnique('RenderSceneAmbient');
      vAmb := D3DXVector4(AMBIENT, AMBIENT, AMBIENT, 1.0);
      V(g_pEffect.SetVector('g_vAmbient', vAmb));
      RenderScene(pd3dDevice, fTime, fElapsedTime, True);
      D3DPERF_EndEvent;
    end;

    // Now process the lights.  For each light in the scene,
    // render the shadow volume, then render the scene with
    // stencil enabled.

    begin
      // CDXUTPerfEventGenerator g( DXUT_PERFEVENTCOLOR, L"Shadow" );
      D3DPERF_BeginEvent(DXUT_PERFEVENTCOLOR, 'Shadow');

      for L := 0 to g_nNumLights - 1 do
      begin
        // Clear the stencil buffer
        if (g_RenderType <> RENDERTYPE_COMPLEXITY)
        then V(pd3dDevice.Clear(0, nil, D3DCLEAR_STENCIL, D3DCOLOR_ARGB(0, 170, 170, 170), 1.0, 0));

        vLight := D3DXVector4(g_aLights[L].m_Position.x, g_aLights[L].m_Position.y, g_aLights[L].m_Position.z, 1.0);
        D3DXVec4Transform(vLight, vLight, g_LCamera.GetWorldMatrix^);
        D3DXVec4Transform(vLight, vLight, g_Camera.GetViewMatrix^);
        V(g_pEffect.SetVector('g_vLightView', vLight));
        V(g_pEffect.SetVector('g_vLightColor', g_aLights[L].m_Color));

        // Render the shadow volume
        case g_RenderType of
          RENDERTYPE_COMPLEXITY: g_pEffect.SetTechnique('RenderShadowVolumeComplexity');
          RENDERTYPE_SHADOWVOLUME: g_pEffect.SetTechnique(g_hShowShadow);
        else
          g_pEffect.SetTechnique(g_hRenderShadow);
        end;

        g_pEffect.SetVector('g_vShadowColor', g_vShadowColor[L]);
                
        // If there was an error generating the shadow volume,
        // skip rendering the shadow mesh.  The scene will show
        // up without shadow.
        if Assigned(g_pShadowMesh) then
        begin
          V(pd3dDevice.SetVertexDeclaration(g_pShadowDecl));
          V(g_pEffect._Begin(@cPasses, 0));
          for i := 0 to cPasses - 1 do
          begin
            V(g_pEffect.BeginPass(i));
            V(g_pEffect.CommitChanges);
            V(g_pShadowMesh.DrawSubset(0));
            V(g_pEffect.EndPass);
          end;
          V(g_pEffect._End);
        end;

        //
        // Render the scene with stencil and lighting enabled.
        //
        if (g_RenderType <> RENDERTYPE_COMPLEXITY) then
        begin
          g_pEffect.SetTechnique(g_hRenderScene);
          RenderScene(pd3dDevice, fTime, fElapsedTime, False);
        end;
      end;
      D3DPERF_EndEvent;
    end;

    if (g_RenderType = RENDERTYPE_COMPLEXITY) then
    begin
      // CDXUTPerfEventGenerator g( DXUT_PERFEVENTCOLOR, L"Complexity" );
      D3DPERF_BeginEvent(DXUT_PERFEVENTCOLOR, 'Complexity');

      // Clear the render target
      V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET, D3DCOLOR_ARGB(0, 0, 0, 0), 1.0, 0));

      // Render scene complexity visualization
      pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
      quad[0] := PostProcVert(-0.5,                                              -0.5, 0.5, 1.0);
      quad[1] := PostProcVert(pd3dsdBackBuffer.Width-0.5,                        -0.5, 0.5, 1.0);
      quad[2] := PostProcVert(-0.5,                       pd3dsdBackBuffer.Height-0.5, 0.5, 1.0);
      quad[3] := PostProcVert(pd3dsdBackBuffer.Width-0.5, pd3dsdBackBuffer.Height-0.5, 0.5, 1.0);

      pd3dDevice.SetVertexDeclaration(g_pPProcDecl);
      g_pEffect.SetTechnique('RenderComplexity');
      g_pEffect._Begin(@cPasses, 0);
      for p := 0 to cPasses - 1 do
      begin
        g_pEffect.BeginPass(p);
        pd3dDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, quad, SizeOf(TPOSTPROCVERT));
        g_pEffect.EndPass;
      end;
      g_pEffect._End;
      D3DPERF_EndEvent;
    end;

    DXUT_EndPerfEvent; // end of draw code
{$IFDEF SYNCRO_BY_FENCE}
    DXUTGetD3DDevice.CreateQuery(D3DQUERYTYPE_EVENT, fence);
{$ENDIF}

    // Miscellaneous rendering
    begin
      // CDXUTPerfEventGenerator g( DXUT_PERFEVENTCOLOR,"HUD / Stats");
      D3DPERF_BeginEvent(DXUT_PERFEVENTCOLOR, 'HUD / Stats');

      RenderText;
      g_HUD.OnRender(fElapsedTime);
      g_SampleUI.OnRender(fElapsedTime);
      D3DPERF_EndEvent;
    end;

{$IFDEF SYNCRO_BY_FENCE}
    fence.Issue(D3DISSUE_END);
{$ENDIF}
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
  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0 ));
  txtHelper.DrawTextLine(DXUTGetFrameStats(True)); // Show FPS
  txtHelper.DrawTextLine(DXUTGetDeviceStats);

  // Draw help
  if g_bShowHelp then
  begin
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-80);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0 ));
    txtHelper.DrawTextLine('Controls (F1 to hide):');

    txtHelper.SetInsertionPos(20, pd3dsdBackBuffer.Height-65);
    txtHelper.DrawTextLine('Camera control: Left mouse'#10+
                           'Mesh control: Right mouse'#10+
                           'Light control: Middle mouse'#10+
                           'Quit: ESC' );
  end else
  begin
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-25);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
    txtHelper.DrawTextLine('Press F1 for help');
  end;

  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0 ));
  if not (g_bLeftButtonDown or g_bMiddleButtonDown or g_bRightButtonDown) then
  begin
    txtHelper.SetInsertionPos(pd3dsdBackBuffer.Width div 2 - 90, pd3dsdBackBuffer.Height - 40);
    txtHelper.DrawTextLine(#10'W/S/A/D/Q/E to move camera.');
  end else
  begin
    txtHelper.SetInsertionPos(pd3dsdBackBuffer.Width div 2 - 70, pd3dsdBackBuffer.Height - 40);
    if g_bLeftButtonDown then
    begin
      txtHelper.DrawTextLine('Camera Control Mode');
    end else
    if g_bMiddleButtonDown then
    begin
      txtHelper.DrawTextLine('Light Control Mode');
    end;
    if g_bRightButtonDown then
    begin
      txtHelper.DrawTextLine('Model Control Mode');
    end;
    txtHelper.SetInsertionPos(pd3dsdBackBuffer.Width div 2 - 130, pd3dsdBackBuffer.Height - 25);
    txtHelper.DrawTextLine('Move mouse to rotate. W/S/A/D/Q/E to move.');
  end;

  if (g_RenderType = RENDERTYPE_COMPLEXITY) then
  begin
    txtHelper.SetInsertionPos(5, 70);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
    txtHelper.DrawTextLine('Shadow volume complexity:');
    txtHelper.SetInsertionPos(5, 90);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.0, 1.0, 1.0));
    txtHelper.DrawTextLine('1 to 5 fills'#10);
    txtHelper.SetForegroundColor(D3DXColor(0.0, 0.0, 1.0, 1.0));
    txtHelper.DrawTextLine('6 to 10 fills'#10);
    txtHelper.SetForegroundColor(D3DXColor(0.0, 1.0, 1.0, 1.0));
    txtHelper.DrawTextLine('11 to 20 fills'#10);
    txtHelper.SetForegroundColor(D3DXColor(0.0, 1.0, 0.0, 1.0));
    txtHelper.DrawTextLine('21 to 30 fills'#10);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));
    txtHelper.DrawTextLine('31 to 40 fills'#10);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.5, 0.0, 1.0));
    txtHelper.DrawTextLine('41 to 50 fills'#10);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.0, 0.0, 1.0));
    txtHelper.DrawTextLine('51 to 70 fills'#10);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
    txtHelper.DrawTextLine('71 or more fills'#10);
  end;

  // Display an error message if unable to generate shadow mesh
  if (g_pShadowMesh = nil) then
  begin
    txtHelper.SetInsertionPos(5, 35);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.0, 0.0, 1.0 ));
    txtHelper.DrawTextLine('Unable to generate closed shadow volume for this mesh'#10);
    txtHelper.DrawTextLine('No shadow will be rendered');
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
  g_MCamera.HandleMessages(hWnd, uMsg, wParam, lParam);
  g_LCamera.HandleMessages(hWnd, uMsg, wParam, lParam);
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


procedure MouseProc(bLeftButtonDown, bRightButtonDown, bMiddleButtonDown,
  bSideButton1Down, bSideButton2Down: Boolean; nMouseWheelDelta: Integer;
  xPos, yPos: Integer; pUserContext: Pointer); stdcall;
var
  bOldLeftButtonDown: Boolean;
  bOldRightButtonDown: Boolean;
  bOldMiddleButtonDown: Boolean;
begin
  bOldLeftButtonDown := g_bLeftButtonDown;
  bOldRightButtonDown := g_bRightButtonDown;
  bOldMiddleButtonDown := g_bMiddleButtonDown;
  g_bLeftButtonDown := bLeftButtonDown;
  g_bMiddleButtonDown := bMiddleButtonDown;
  g_bRightButtonDown := bRightButtonDown;

  if (bOldLeftButtonDown and not g_bLeftButtonDown) then
  begin
    // Disable movement
    g_Camera.SetEnablePositionMovement(False);
  end else
  if (not bOldLeftButtonDown and g_bLeftButtonDown) then
  begin
    // Enable movement
    g_Camera.SetEnablePositionMovement(True);
  end;

  if (bOldRightButtonDown and not g_bRightButtonDown) then
  begin
    // Disable movement
    g_MCamera.SetEnablePositionMovement(False);
  end else
  if (not bOldRightButtonDown and g_bRightButtonDown) then
  begin
    // Enable movement
    g_MCamera.SetEnablePositionMovement(True);
    g_Camera.SetEnablePositionMovement(False);
  end;

  if (bOldMiddleButtonDown and not g_bMiddleButtonDown) then
  begin
    // Disable movement
    g_LCamera.SetEnablePositionMovement(False);
  end else
  if (not bOldMiddleButtonDown and g_bMiddleButtonDown) then
  begin
    // Enable movement
    g_LCamera.SetEnablePositionMovement(True);
    g_Camera.SetEnablePositionMovement(False);
  end;

  // If no mouse button is down at all, enable camera movement.
  if (not g_bLeftButtonDown and not g_bRightButtonDown and not g_bMiddleButtonDown)
  then g_Camera.SetEnablePositionMovement(True);
end;


//--------------------------------------------------------------------------------------
// Handles the GUI events
//--------------------------------------------------------------------------------------
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
var
  fLuminance: Single;
  i: Integer;
  NewMesh: CDXUTMesh;
  pd3dsdBackBuffer: PD3DSurfaceDesc;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;

    IDC_RENDERTYPE:  g_RenderType := TRenderType(size_t(CDXUTComboBox(pControl).GetSelectedData));
    IDC_ENABLELIGHT:
      if (nEvent = EVENT_COMBOBOX_SELECTION_CHANGED) then
      begin
        g_nNumLights := Integer(size_t(g_SampleUI.GetComboBox(IDC_ENABLELIGHT).GetSelectedData));
      end;

    IDC_LUMINANCE:
      if (nEvent = EVENT_SLIDER_VALUE_CHANGED) then
      begin
        fLuminance := CDXUTSlider(pControl).Value;
        // StringCchPrintf( wszText, 50, L"Luminance: %.1f", fLuminance );
        g_SampleUI.GetStatic(IDC_LUMINANCELABEL).Text := PWideChar(WideFormat('Luminance: %.1f', [fLuminance]));

        for i := 0 to MAX_NUM_LIGHTS - 1 do
        begin
          if (g_aLights[i].m_Color.x > 0.5) then g_aLights[i].m_Color.x := fLuminance;
          if (g_aLights[i].m_Color.y > 0.5) then g_aLights[i].m_Color.y := fLuminance;
          if (g_aLights[i].m_Color.z > 0.5) then g_aLights[i].m_Color.z := fLuminance;
        end;
      end;

      IDC_BACKGROUND:
        if (nEvent = EVENT_COMBOBOX_SELECTION_CHANGED) then
        begin
          g_nCurrBackground := Integer(size_t(g_SampleUI.GetComboBox(IDC_BACKGROUND).GetSelectedData));
        end;

      IDC_MESHFILENAME, IDC_CHANGEMESH:
      begin
        if (nControlID = IDC_MESHFILENAME) and (nEvent <> EVENT_EDITBOX_CHANGE) then
        begin
          NewMesh:= CDXUTMesh.Create;

          if SUCCEEDED(NewMesh.CreateMesh(DXUTGetD3DDevice, g_SampleUI.GetIMEEditBox(IDC_MESHFILENAME).Text)) and
             SUCCEEDED(NewMesh.SetVertexDecl(DXUTGetD3DDevice, @TMeshVert_Decl)) and
             SUCCEEDED(NewMesh.RestoreDeviceObjects(DXUTGetD3DDevice)) then
          begin
            g_Mesh.InvalidateDeviceObjects;
            g_Mesh.DestroyMesh;
            g_Mesh.Free;
            g_Mesh := NewMesh;
            // ZeroMemory(@NewMesh, SizeOf(NewMesh));
            ComputeMeshScaling(g_Mesh, g_mWorldScaling);

            // Generate the shadow mesh
            SAFE_RELEASE(g_pShadowMesh);
            GenerateShadowMesh(DXUTGetD3DDevice, g_Mesh.Mesh, g_pShadowMesh);
          end;
        end;

        // Fall through to clean up the edit box and button
        if (nControlID = IDC_MESHFILENAME) and (nEvent <> EVENT_EDITBOX_CHANGE) or
           (nControlID = IDC_CHANGEMESH) then
        begin
      {end;

      IDC_CHANGEMESH:
      begin}
          pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
          if Assigned(g_SampleUI.GetControl(IDC_MESHFILENAME)) then
          begin
            // If the edit box exists, clean up.
            g_SampleUI.RemoveControl(IDC_MESHFILENAME);
            // Change the button text back to "Change mesh"
            g_SampleUI.GetButton(IDC_CHANGEMESH).Text := 'Change mesh';
          end else
          begin
            // Create a new edit box.
            g_SampleUI.AddIMEEditBox(IDC_MESHFILENAME, '', pd3dsdBackBuffer.Width - 540, 158, 415, 34);
            g_SampleUI.GetIMEEditBox(IDC_MESHFILENAME).SetText('Type mesh name and press Enter', True);
            g_SampleUI.RequestFocus(g_SampleUI.GetControl(IDC_MESHFILENAME));
            // Change the button text to "Cancel"
            g_SampleUI.GetButton(IDC_CHANGEMESH).Text := 'Cancel';
          end;
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
begin
  g_DialogResourceManager.OnLostDevice;
  g_SettingsDlg.OnLostDevice;
  g_Background[0].InvalidateDeviceObjects;
  g_Background[1].InvalidateDeviceObjects;
  g_LightMesh.InvalidateDeviceObjects;
  g_Mesh.InvalidateDeviceObjects;
  SAFE_RELEASE(g_pShadowMesh);

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
  g_Background[0].DestroyMesh;
  g_Background[1].DestroyMesh;
  g_LightMesh.DestroyMesh;
  g_Mesh.DestroyMesh;

  SAFE_RELEASE(g_pDefaultTex);
  SAFE_RELEASE(g_pEffect);
  SAFE_RELEASE(g_pFont);
  SAFE_RELEASE(g_pMeshDecl);
  SAFE_RELEASE(g_pShadowDecl);
  SAFE_RELEASE(g_pPProcDecl);
end;

function LightInitData(const P: TD3DXVector3; const C: TD3DXVector4): TLightInitData;
begin
  Result.Position := P;
  Result.Color := C;
end;



procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera:= CFirstPersonCamera.Create;
  g_MCamera:= CModelViewerCamera.Create;
  g_LCamera:= CModelViewerCamera.Create;
  g_Background[0]:= CDXUTMesh.Create;
  g_Background[1]:= CDXUTMesh.Create;
  g_LightMesh:= CDXUTMesh.Create;
  g_Mesh:= CDXUTMesh.Create;
  g_HUD := CDXUTDialog.Create;
  g_SampleUI := CDXUTDialog.Create;
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_Camera);
  FreeAndNil(g_MCamera);
  FreeAndNil(g_LCamera);
  FreeAndNil(g_Background[0]);
  FreeAndNil(g_Background[1]);
  FreeAndNil(g_LightMesh);
  FreeAndNil(g_Mesh);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);
end;

function PostProcVert(x, y, z, rhw: Single): TPostProcVert;
begin
  Result.x := x;
  Result.y := y;
  Result.z := z;
  Result.rhw := rhw;
end;

function EdgeMapping: TEdgeMapping;
begin
  with Result do
  begin
    FillMemory(@m_anOldEdge, SizeOf(m_anOldEdge), $FF);
    FillMemory(@m_aanNewEdge, SizeOf(m_aanNewEdge), $FF);
  end;
end;

initialization
  g_vShadowColor[0]:= D3DXVector4(0.0, 1.0, 0.0, 0.2);
  g_vShadowColor[1]:= D3DXVector4(1.0, 1.0, 0.0, 0.2);
  g_vShadowColor[2]:= D3DXVector4(1.0, 0.0, 0.0, 0.2);
  g_vShadowColor[3]:= D3DXVector4(0.0, 0.0, 1.0, 0.2);
  g_vShadowColor[4]:= D3DXVector4(1.0, 0.0, 1.0, 0.2);
  g_vShadowColor[5]:= D3DXVector4(0.0, 1.0, 1.0, 0.2);

  g_LightInit[0] := LightInitData(D3DXVector3(-2.0, 3.0, -3.0), D3DXVector4(15.0, 15.0, 15.0, 1.0));
if MAX_NUM_LIGHTS > 1 then
  g_LightInit[1] := LightInitData(D3DXVector3(2.0, 3.0, -3.0), D3DXVector4(15.0, 15.0, 15.0, 1.0));
if MAX_NUM_LIGHTS > 2 then
  g_LightInit[2] := LightInitData(D3DXVector3(-2.0, 3.0, 3.0), D3DXVector4(15.0, 15.0, 15.0, 1.0));
if MAX_NUM_LIGHTS > 3 then
  g_LightInit[3] := LightInitData(D3DXVector3(2.0, 3.0, 3.0), D3DXVector4(15.0, 15.0, 15.0, 1.0));
if MAX_NUM_LIGHTS > 4 then
  g_LightInit[4] := LightInitData(D3DXVector3(-2.0, 3.0, 0.0), D3DXVector4(15.0, 0.0, 0.0, 1.0));
if MAX_NUM_LIGHTS > 5 then
  g_LightInit[5] := LightInitData(D3DXVector3(2.0, 3.0, 0.0), D3DXVector4(0.0, 0.0, 15.0, 1.0));
end.

