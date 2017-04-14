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
 *  $Id: MeshLoader.pas,v 1.17 2007/02/05 22:21:10 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: MeshLoader.h, MeshLoader.cpp
//
// Wrapper class for ID3DXMesh interface. Handles loading mesh data from an .obj file
// and resource management for material textures.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit MeshLoader;

interface

uses
  Windows, Classes, SysUtils, StrSafe, 
  DXTypes, Direct3D9, D3DX9, DXErr9,
  DXUTcore, DXUTMisc;

type
  // Vertex format
  PVertex = ^TVertex;
  TVertex = record
    position: TD3DXVector3;
    normal: TD3DXVector3;
    texcoord: TD3DXVector2;
  end;

  // Used for a hashtable vertex cache when creating the mesh from a .obj file
  PCacheEntry = ^TCacheEntry;
  TCacheEntry = record
    index: LongWord;
    pNext: PCacheEntry;
  end;


  // Material properties per mesh subset
  PMaterial = ^TMaterial;
  TMaterial = record
    strName: array[0..MAX_PATH-1] of WideChar;

    vAmbient: TD3DXVector3;
    vDiffuse: TD3DXVector3;
    vSpecular: TD3DXVector3;

    nShininess: Integer;
    fAlpha: Single;

    bSpecular: Boolean;

    strTexture: array[0..MAX_PATH-1] of WideChar;
    pTexture: IDirect3DTexture9; //todo: Warning!!!
    hTechnique: TD3DXHandle;
  end;


  CMeshLoader = class
  private
    m_pd3dDevice: IDirect3DDevice9;      // Direct3D Device object associated with this mesh
    m_pMesh: ID3DXMesh;                  // Encapsulated D3DX Mesh

    m_VertexCache: array of PCacheEntry; // Hashtable cache for locating duplicate vertices
    m_Vertices:    array of TVertex;     // Filled and copied to the vertex buffer
    m_Indices:     array of DWORD;       // Filled and copied to the index buffer
    m_Attributes:  array of DWORD;       // Filled and copied to the attribute buffer
    m_Materials:   array of PMaterial;   // Holds material properties per subset

    m_strMediaDir: array[0..MAX_PATH-1] of WideChar; // Directory where the mesh was found

    function LoadGeometryFromOBJ(const strFilename: PWideChar): HRESULT;
    function LoadMaterialsFromMTL(const strFileName: WideString): HRESULT;
    procedure InitMaterial(var pMaterial: TMaterial);

    function AddVertex(hash: Integer; pVer: PVertex): DWORD;
    procedure DeleteCache;

    // function GetMesh() { return m_pMesh; }
    function GetMediaDirectory: PWideChar; { return m_strMediaDir; }
  public
    constructor Create;
    destructor Destroy; override;

    function CreateMesh(const pd3dDevice: IDirect3DDevice9; const strFilename: PWideChar): HRESULT;
    procedure DestroyMesh;


    function GetNumMaterials: LongWord; // const { return m_Materials.GetSize(); }
    function GetMaterial(iMaterial: LongWord): PMaterial; { return m_Materials.GetAt( iMaterial ); }

    property Mesh: ID3DXMesh read m_pMesh;
    property MediaDirectory: PWideChar read GetMediaDirectory;
    property NumMaterials: LongWord read GetNumMaterials;
    property Material[iMaterial: LongWord]: PMaterial read GetMaterial;
  end;


implementation

//--------------------------------------------------------------------------------------
// File: MeshLoader.cpp
//
// Wrapper class for ID3DXMesh interface. Handles loading mesh data from an .obj file
// and resource management for material textures.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

const
  // Vertex declaration
  VERTEX_DECL: array[0..3] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0;  _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITION; UsageIndex: 0),
    (Stream: 0; Offset: 12; _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_NORMAL;   UsageIndex: 0),
    (Stream: 0; Offset: 24; _Type: D3DDECLTYPE_FLOAT2; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TEXCOORD; UsageIndex: 0),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );



  
{ CMeshLoader }

//--------------------------------------------------------------------------------------
constructor CMeshLoader.Create;
begin
  m_pd3dDevice := nil;
  m_pMesh := nil;

  ZeroMemory(@m_strMediaDir, SizeOf(m_strMediaDir));
end;


//--------------------------------------------------------------------------------------
destructor CMeshLoader.Destroy;
begin
  DestroyMesh;
  inherited;
end;


//--------------------------------------------------------------------------------------
procedure CMeshLoader.DestroyMesh;
var
  iMaterial: Integer;
  pMat, pCur: PMaterial;
  x: Integer;
begin
  for iMaterial := 0 to Length(m_Materials) - 1 do
  begin
    pMat := m_Materials[iMaterial];

    // Avoid releasing the same texture twice
    for x := iMaterial+1 to Length(m_Materials) - 1 do
    begin
      pCur := m_Materials[x];
      if (pCur.pTexture = pMat.pTexture) then pCur.pTexture := nil;
    end;

    pMat.pTexture := nil;
    //todo: ?
    FreeMem(pMat); // SAFE_DELETE(pMaterial);
  end;

  m_Materials := nil; // .RemoveAll;
  m_Vertices := nil; // .RemoveAll;
  m_Indices := nil; // .RemoveAll;
  m_Attributes := nil; // .RemoveAll;

  m_pMesh := nil;
  m_pd3dDevice := nil;
end;

//--------------------------------------------------------------------------------------
function CMeshLoader.CreateMesh(const pd3dDevice: IDirect3DDevice9;
  const strFilename: PWideChar): HRESULT;
var
  str, wstrOldDir: array[0..MAX_PATH-1] of WideChar;
  iMaterial: Integer;
  pMat, pCur: PMaterial;
  bFound: Boolean;
  x: Integer;
  pMesh: ID3DXMesh;
  pVert: PVertex;
  pIndex: PDWORD;
  pSubset: PDWORD;
  aAdjacency: PDWORD;
begin
  ZeroMemory(@str, SizeOf(str));

  // Start clean
  DestroyMesh;

  // Store the device pointer
  m_pd3dDevice := pd3dDevice;

  // Load the vertex buffer, index buffer, and subset information from a file. In this case,
  // an .obj file was chosen for simplicity, but it's meant to illustrate that ID3DXMesh objects
  // can be filled from any mesh file format once the necessary data is extracted from file.
  Result:= LoadGeometryFromOBJ(strFilename);
  if V_Failed(Result) then Exit;

  // Set the current directory based on where the mesh was found
  // WCHAR wstrOldDir[MAX_PATH] = {0};
  GetCurrentDirectoryW(MAX_PATH, wstrOldDir);
  SetCurrentDirectoryW(m_strMediaDir);

  // Load material textures
  for iMaterial := 0 to Length(m_Materials) - 1 do
  begin
    pMat := m_Materials[iMaterial];
    if (pMat.strTexture[0] <> #0) then
    begin
      // Avoid loading the same texture twice
      bFound := False;
      for x := 0 to iMaterial - 1 do
      begin
        pCur := m_Materials[x];

        if (0 = lstrcmpW(pCur.strTexture, pMat.strTexture)) then
        begin
          bFound := True;
          pMat.pTexture := pCur.pTexture;
          Break;
        end;
      end;

      // Not found, load the texture
      if not bFound then
      begin
        Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, pMat.strTexture);
        if V_Failed(Result) then Exit;
        Result := D3DXCreateTextureFromFileW(pd3dDevice, pMat.strTexture,
                                             pMat.pTexture);
        if V_Failed(Result) then Exit;
      end;
    end;
  end;

  // Restore the original current directory
  SetCurrentDirectoryW(wstrOldDir);

  // Create the encapsulated mesh
  Result := D3DXCreateMesh(Length(m_Indices) div 3, Length(m_Vertices),
                           D3DXMESH_MANAGED or D3DXMESH_32BIT, @VERTEX_DECL,
                           pd3dDevice, pMesh);
  if V_Failed(Result) then Exit;

  // Copy the vertex data
  Result := pMesh.LockVertexBuffer(0, Pointer(pVert));
  if V_Failed(Result) then Exit;
  CopyMemory(pVert, m_Vertices, Length(m_Vertices)*SizeOf(TVertex));
  pMesh.UnlockVertexBuffer;
  m_Vertices := nil; // RemoveAll;

  // Copy the index data
  Result:= pMesh.LockIndexBuffer(0, Pointer(pIndex));
  if V_Failed(Result) then Exit;
  CopyMemory(pIndex, m_Indices, Length(m_Indices)*SizeOf(DWORD));
  pMesh.UnlockIndexBuffer;
  m_Indices := nil; // RemoveAll;

  // Copy the attribute data
  Result:= pMesh.LockAttributeBuffer(0, pSubset);
  if V_Failed(Result) then Exit;
  CopyMemory(pSubset, m_Attributes, Length(m_Attributes)*SizeOf(DWORD));
  pMesh.UnlockAttributeBuffer;
  m_Attributes := nil; // RemoveAll;

  // Reorder the vertices according to subset and optimize the mesh for this graphics
  // card's vertex cache. When rendering the mesh's triangle list the vertices will
  // cache hit more often so it won't have to re-execute the vertex shader.
  try
    GetMem(aAdjacency, SizeOf(DWORD)*pMesh.GetNumFaces*3);
  except
    Result:= E_OUTOFMEMORY;
    Exit;
  end;

  V(pMesh.GenerateAdjacency(1e-6, aAdjacency));
  V(pMesh.OptimizeInplace(D3DXMESHOPT_ATTRSORT or D3DXMESHOPT_VERTEXCACHE, aAdjacency, nil, nil, nil));

  FreeMem(aAdjacency);
  m_pMesh := pMesh;

  Result:= S_OK;
end;

type
  TWifStream = class
  private
    FHandle: THandle; // File handle
    FMappingHandle: THandle; // File Mapping handle
    FFilePointer, FFileEnd: PAnsiChar;
    FFileSize: LongWord;
    //---------------------
    FFileName: String;
    FDelimiters: String;
    FBufferPos, FDelimPos: PChar;
    function GetPeek: Char;
    function GetRelativeChar(i: Integer): Char;
    function GetEOF: Boolean;
  public
    constructor Create(const aFileName: String);
    destructor Destroy; override;
    function GetNextToken: String;
    function GetNextTokenAsInt(out i: Integer): String;
    function GetNextTokenAsFloat(out f: Single): String;
    procedure Ignore(Count: Integer = 1; ch: Char = #0);
    property Delimiters: String read FDelimiters write FDelimiters;
    property Peek: Char read GetPeek;
    property RelativeChar[i: Integer]: Char read GetRelativeChar;
    property FileName: String read FFileName;
    property EOF: Boolean read GetEOF;
  end;

{ TWifStream }

constructor TWifStream.Create(const aFileName: String);
begin
  FFileName:= aFileName;
  FDelimiters:= ' /\,'#9#10#13;
  FHandle:= FileOpen(FileName, fmOpenRead);
  FFileSize:= GetFileSize(FHandle, nil);

  FMappingHandle:= CreateFileMapping(FHandle, nil, PAGE_READONLY, 0, 0, nil);
  FFilePointer:= MapViewOfFile(FMappingHandle, FILE_MAP_READ, 0, 0, 0);
  FFileEnd:= FFilePointer + FFileSize;
  FBufferPos:= FFilePointer;
end;

destructor TWifStream.Destroy;
begin
  UnmapViewOfFile(FFilePointer);
  CloseHandle(FMappingHandle);
  CloseHandle(FHandle);
  inherited;
end;

function TWifStream.GetPeek: Char;
begin
  // return next character, unconsumed
  Result:= FBufferPos^;
end;

function TWifStream.GetRelativeChar(i: Integer): Char;
begin
  Result:= (FBufferPos+i)^;
end;

function TWifStream.GetEOF: Boolean;
begin
  Result:= (FBufferPos >= FFileEnd); // EOF...
end;

function TWifStream.GetNextToken: String;
var
  StartPos: PChar;
begin
  // Skip all Delimiters
  while (FBufferPos < FFileEnd) do
  begin
    if StrScan(PAnsiChar(FDelimiters), FBufferPos^) = nil then Break;
    Inc(FBufferPos);
  end;

  StartPos:= FBufferPos;

  // Skip all NON-delimiters
  while (FBufferPos < FFileEnd) do
  begin
    if StrScan(PAnsiChar(FDelimiters), FBufferPos^) <> nil then Break;
    Inc(FBufferPos);
  end;

  FDelimPos:= FBufferPos;

  SetLength(Result, FDelimPos - StartPos);
  Move(StartPos^, Result[1], FDelimPos - StartPos);
end;

function TWifStream.GetNextTokenAsInt(out i: Integer): String;
begin
  Result:= GetNextToken;
  i:= StrToInt(Result); //todo: or StrToIntDef ???
end;

function TWifStream.GetNextTokenAsFloat(out f: Single): String;
{$IFDEF COMPILER7_UP}
var
  FmtSettings: TFormatSettings;
begin
  Result:= GetNextToken;
  GetLocaleFormatSettings(GetThreadLocale, FmtSettings);
  FmtSettings.DecimalSeparator:= '.'; // override System specified DecimalSeparator
  f:= StrToFloat(Result, FmtSettings);
end;
{$ELSE}
begin
  Result:= GetNextToken;
  DecimalSeparator:= '.';
  f:= StrToFloat(Result);
end;
{$ENDIF}

procedure TWifStream.Ignore(Count: Integer = 1; ch: Char = #0);
var
  StartPos: PChar;
begin
  StartPos:= FBufferPos;

  while (FBufferPos < FFileEnd) and (FBufferPos - StartPos < Count) do
  begin
    if (FBufferPos^ = ch) then Break;
    Inc(FBufferPos);
  end;
end;


//--------------------------------------------------------------------------------------
function CMeshLoader.LoadGeometryFromOBJ(const strFilename: PWideChar): HRESULT;
var
  strMaterialFilename: WideString;
  wstr: array[0..MAX_PATH-1] of WideChar;
  str: array[0..MAX_PATH-1] of Char;
  pch: PWideChar;
  // Create temporary storage for the input data. Once the data has been loaded into
  // a reasonable format we can create a D3DXMesh object and load it with the mesh data.
  Positions: array of TD3DXVector3;
  TexCoords: array of TD3DXVector2;
  Normals: array of TD3DXVector3;
  pMat: PMaterial;
  dwCurSubset: DWORD;
  strCommand: String;
  l: Integer;
  InFile: TWifStream;
  x, y, z: Single;
  u, v: Single;
  iPosition, iTexCoord, iNormal: Integer;
  vertex: TVertex;
  iFace: LongWord;
  index: DWORD;
  strName: WideString;
  bFound: Boolean;
  iMaterial: Integer;
  pCurMaterial: PMaterial;
begin
  // Find the file
  Result:= DXUTFindDXSDKMediaFile(wstr, MAX_PATH, strFileName);
  if V_Failed(Result) then Exit;
  WideCharToMultiByte(CP_ACP, 0, wstr, -1, str, MAX_PATH, nil, nil);

  // Store the directory where the mesh was found
  StringCchCopy(m_strMediaDir, MAX_PATH-1, wstr);
  pch := WideStrRScan(m_strMediaDir, '\');
  if (pch <> nil) then pch^ := #0;

  // The first subset uses the default material
  try
    pMat := New(PMaterial);
  except
    Result:= E_OUTOFMEMORY;
    Exit;
  end;

  InitMaterial(pMat^);
  StringCchCopy(pMat.strName, MAX_PATH-1, 'default');
  // m_Materials.Add(pMaterial);
  l:= Length(m_Materials);
  SetLength(m_Materials, l+1);
  m_Materials[l]:= pMat;

  dwCurSubset := 0;

  // File input
  FillChar(strCommand, SizeOf(strCommand), 0);
  InFile:= TWifStream.Create(str);
  if (InFile.FHandle = 0) then
  begin
    Result:= DXTRACE_ERR('wifstream.open', E_FAIL);
    Exit;
  end;

  while True do
  begin
    strCommand := InFile.GetNextToken;
    if InFile.EOF then Break;

    if (strCommand = '#') then
    begin
      // Comment
    end
    else if (strCommand = 'v') then
    begin
      // Vertex Position
      InFile.GetNextTokenAsFloat(x);
      InFile.GetNextTokenAsFloat(y);
      InFile.GetNextTokenAsFloat(z);
      // Positions.Add(D3DXVector3(x, y, z));
      l:= Length(Positions);
      SetLength(Positions, l+1);
      Positions[l]:= D3DXVector3(x, y, z);
    end
    else if (strCommand = 'vt') then
    begin
      // Vertex TexCoord
      InFile.GetNextTokenAsFloat(u);
      InFile.GetNextTokenAsFloat(v);
      // TexCoords.Add(D3DXVector2(u, v));
      l:= Length(TexCoords);
      SetLength(TexCoords, l+1);
      TexCoords[l]:= D3DXVector2(u, v);
    end
    else if (strCommand = 'vn') then
    begin
      // Vertex Normal
      InFile.GetNextTokenAsFloat(x);
      InFile.GetNextTokenAsFloat(y);
      InFile.GetNextTokenAsFloat(z);
      // Normals.Add(D3DXVector3(x, y, z));
      l:= Length(Normals);
      SetLength(Normals, l+1);
      Normals[l]:= D3DXVector3(x, y, z);
    end
    else if (strCommand = 'f') then
    begin
      // Face
      for iFace:= 0 to 2 do
      begin
        ZeroMemory(@vertex, SizeOf(TVertex));

        // OBJ format uses 1-based arrays
        InFile.GetNextTokenAsInt(iPosition);
        vertex.position := Positions[iPosition-1];

        if ('/' = InFile.Peek) then
        begin
          InFile.Ignore;

          if ('/' <> InFile.Peek) then
          begin
            // Optional texture coordinate
            InFile.GetNextTokenAsInt(iTexCoord);
            vertex.texcoord := TexCoords[iTexCoord-1];
          end;

          if ('/' = InFile.Peek) then
          begin
            InFile.ignore;

            // Optional vertex normal
            InFile.GetNextTokenAsInt(iNormal);
            vertex.normal := Normals[iNormal-1];
          end;
        end;

        // If a duplicate vertex doesn't exist, add this vertex to the Vertices
        // list. Store the index in the Indices array. The Vertices and Indices
        // lists will eventually become the Vertex Buffer and Index Buffer for
        // the mesh.
        index := AddVertex(iPosition, @vertex);
        // m_Indices.Add(index);
        l:= Length(m_Indices);
        SetLength(m_Indices, l+1);
        m_Indices[l]:= index;
      end;
      // m_Attributes.Add(dwCurSubset);
      l:= Length(m_Attributes);
      SetLength(m_Attributes, l+1);
      m_Attributes[l]:= dwCurSubset;
    end
    else if (strCommand = 'mtllib') then
    begin
      // Material library
      strMaterialFilename:= InFile.GetNextToken;
    end
    else if (strCommand = 'usemtl') then
    begin
      // Material
      strName := InFile.GetNextToken;

      bFound := False;
      for iMaterial:=0 to Length(m_Materials) - 1 do
      begin
        pCurMaterial := m_Materials[iMaterial];
        {$IFDEF FPC}
        if lstrcmpW(pCurMaterial.strName, PWideChar(strName)) = 0 then
        {$ELSE}
        if (pCurMaterial.strName = strName) then
        {$ENDIF}
        begin
          bFound := True;
          dwCurSubset := iMaterial;
          Break;
        end;
      end;

      if not bFound then
      begin
        try
          pMat := New(PMaterial);
        except
          Result:= E_OUTOFMEMORY;
          Exit;
        end;

        dwCurSubset := Length(m_Materials);

        InitMaterial(pMat^);
        StringCchCopy(pMat.strName, MAX_PATH-1, @strName[1]); 

        // m_Materials.Add(pMat);
        l:= Length(m_Materials);
        SetLength(m_Materials, l+1);
        m_Materials[l]:= pMat;
      end;
    end
    else
    begin
      // Unimplemented or unrecognized command
    end;

    InFile.Ignore(1000, #10);
  end;

  // Cleanup
  // InFile.Close;
  InFile.Free;
  DeleteCache;

  // If an associated material file was found, read that in as well.
  if (strMaterialFilename <> '') then
  begin
    Result:= LoadMaterialsFromMTL(strMaterialFilename);
    if V_Failed(Result) then Exit;
  end;

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
function CMeshLoader.AddVertex(hash: Integer; pVer: PVertex): DWORD;
var
  bFoundInList: Boolean;
  index, l: DWORD;
  pEntry: PCacheEntry;
  pCacheVertex: PVertex;
  pNewEntry: PCacheEntry;
  pCurEntry: PCacheEntry;
begin
  // If this vertex doesn't already exist in the Vertices list, create a new entry.
  // Add the index of the vertex to the Indices list.
  bFoundInList := False;
  index := 0;

  // Since it's very slow to check every element in the vertex list, a hashtable stores
  // vertex indices according to the vertex position's index as reported by the OBJ file
  if (Length(m_VertexCache) > hash) then
  begin
    pEntry := m_VertexCache[hash];
    while (pEntry <> nil) do
    begin
      pCacheVertex := @m_Vertices[pEntry.index];

      // If this vertex is identical to the vertex already in the list, simply
      // point the index buffer to the existing vertex
      if CompareMem(pVer, pCacheVertex, SizeOf(TVertex)) then
      begin
        bFoundInList := True;
        index := pEntry.index;
        Break;
      end;

      pEntry := pEntry.pNext;
    end;
  end;

  // Vertex was not found in the list. Create a new entry, both within the Vertices list
  // and also within the hashtable cache
  if not bFoundInList then
  begin
    // Add to the Vertices list
    index := Length(m_Vertices);
    // m_Vertices.Add(pVertex^);
    l:= index;
    SetLength(m_Vertices, l+1);
    m_Vertices[l]:= pVer^;

    // Add this to the hashtable
    try
      pNewEntry := New(PCacheEntry);
    except
      Result:= DWORD(E_OUTOFMEMORY); //todo: ???
      Exit;
    end;

    pNewEntry.index := index;
    pNewEntry.pNext := nil;

    // Grow the cache if needed
    while (Length(m_VertexCache) <= hash) do
    begin
      // m_VertexCache.Add(nil);
      l:= Length(m_VertexCache);
      SetLength(m_VertexCache, l+1);
      m_VertexCache[l]:= nil;
    end;

    // Add to the end of the linked list
    pCurEntry := m_VertexCache[hash];
    if (pCurEntry = nil) then
    begin
      // This is the head element
      m_VertexCache[hash] := pNewEntry;
    end else
    begin
      // Find the tail
      while (pCurEntry.pNext <> nil) do
        pCurEntry := pCurEntry.pNext;

      pCurEntry.pNext := pNewEntry;
    end;
  end;

  Result:= index;
end;


//--------------------------------------------------------------------------------------
procedure CMeshLoader.DeleteCache;
var
  i: Integer;
  pEntry: PCacheEntry;
  pNext: PCacheEntry;
begin
  // Iterate through all the elements in the cache and subsequent linked lists
  for i := 0 to Length(m_VertexCache)-1 do
  begin
    pEntry := m_VertexCache[i];
    while (pEntry <> nil) do
    begin
      pNext := pEntry.pNext;
      Dispose(pEntry);
      pEntry := pNext;
    end;
  end;

  m_VertexCache := nil; // RemoveAll;
end;


//--------------------------------------------------------------------------------------
function CMeshLoader.LoadMaterialsFromMTL(const strFileName: WideString): HRESULT;
var
  wstrOldDir: array[0..MAX_PATH-1] of WideChar;
  strPath: array[0..MAX_PATH-1] of WideChar;
  cstrPath: array[0..MAX_PATH-1] of AnsiChar;
  strCommand: String;
  InFile: TWifStream;
  pMat: PMaterial;
  strName: WideString;
  i: Integer;
  pCurMaterial: PMaterial;
  r, g, b: Single;
  nShininess: Integer;
  illumination: Integer;
  fAlpha: Single;
begin
  // Set the current directory based on where the mesh was found
  GetCurrentDirectoryW(MAX_PATH, wstrOldDir);
  SetCurrentDirectoryW(m_strMediaDir);

  // Find the file
  Result:= DXUTFindDXSDKMediaFile(strPath, MAX_PATH, PWideChar(strFileName));
  if V_Failed(Result) then Exit;

  WideCharToMultiByte(CP_ACP, 0, strPath, -1, cstrPath, MAX_PATH, nil, nil);

  // File input
  InFile:= TWifStream.Create(cstrPath);
  if (InFile.FHandle = 0) then
  begin
    Result:= DXTRACE_ERR('wifstream.open', E_FAIL);
    Exit;
  end;

  // Restore the original current directory
  SetCurrentDirectoryW(wstrOldDir);

  pMat := nil;

  while True do
  begin
    strCommand := InFile.GetNextToken;
    if InFile.EOF then Break;

    if (strCommand = 'newmtl') then
    begin
      // Switching active materials
      strName := InFile.GetNextToken;

      pMat := nil;
      for i := 0 to Length(m_Materials) do
      begin
        pCurMaterial := m_Materials[i];
        // if (pCurMaterial.strName = strName) then //This is "proper" way
        // if PWideChar(@pCurMaterial.strName) = strName then //todo: This is FreePascal compatible way
        if lstrcmpW(pCurMaterial.strName, PWideChar(strName)) = 0 then //too C/C++ way althrow fastest of above... :-)
        begin
          pMat := pCurMaterial;
          Break;
        end;
      end;
    end;

    // The rest of the commands rely on an active material
    if (pMat = nil) then Continue;

    if (strCommand = '#') then
    begin
      // Comment
    end
    else if (strCommand = 'Ka') then
    begin
      // Ambient color
      InFile.GetNextTokenAsFloat(r);
      InFile.GetNextTokenAsFloat(g);
      InFile.GetNextTokenAsFloat(b);
      pMat.vAmbient := D3DXVector3(r, g, b);
    end
    else if (strCommand = 'Kd') then
    begin
      // Diffuse color
      InFile.GetNextTokenAsFloat(r);
      InFile.GetNextTokenAsFloat(g);
      InFile.GetNextTokenAsFloat(b);
      pMat.vDiffuse := D3DXVector3(r, g, b);
    end
    else if (strCommand = 'Ks') then
    begin
      // Specular color
      InFile.GetNextTokenAsFloat(r);
      InFile.GetNextTokenAsFloat(g);
      InFile.GetNextTokenAsFloat(b);
      pMat.vSpecular := D3DXVector3(r, g, b);
    end
    else if (strCommand = 'd') or
            (strCommand = 'Tr') then
    begin
      // Alpha
      InFile.GetNextTokenAsFloat(fAlpha);
    end
    else if (strCommand = 'Ns') then
    begin
      // Shininess
      InFile.GetNextTokenAsInt(nShininess);
      pMat.nShininess := nShininess;
    end
    else if (strCommand = 'illum') then
    begin
      // Specular on/off
      InFile.GetNextTokenAsInt(illumination);
      pMat.bSpecular := (illumination = 2);
    end
    else if (strCommand = 'map_Kd') then
    begin
      // Texture
      strName:= InFile.GetNextToken;
      lstrcpynW(pMat.strTexture, @strName[1], MAX_PATH-1); //todo: DEbug is it right order?
    end
    else
    begin
      // Unimplemented or unrecognized command
    end;

    InFile.Ignore(1000, #10);
  end;

  InFile.Free;

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
procedure CMeshLoader.InitMaterial(var pMaterial: TMaterial);
begin
  ZeroMemory(@pMaterial, SizeOf(TMaterial));

  pMaterial.vAmbient := D3DXVector3(0.2, 0.2, 0.2);
  pMaterial.vDiffuse := D3DXVector3(0.8, 0.8, 0.8);
  pMaterial.vSpecular := D3DXVector3(1.0, 1.0, 1.0);
  pMaterial.nShininess := 0;
  pMaterial.fAlpha := 1.0;
  pMaterial.bSpecular := False;
  pMaterial.pTexture := nil;
end;


function CMeshLoader.GetMaterial(iMaterial: LongWord): PMaterial;
begin
  Result:= m_Materials[iMaterial];
end;

function CMeshLoader.GetMediaDirectory: PWideChar;
begin
  Result:= m_strMediaDir;
end;

function CMeshLoader.GetNumMaterials: LongWord;
begin
  Result:= Length(m_Materials);
end;

end.

