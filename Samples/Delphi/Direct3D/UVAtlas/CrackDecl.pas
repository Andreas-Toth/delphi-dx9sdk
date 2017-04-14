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
 *  $Id: CrackDecl.pas,v 1.9 2007/02/05 22:21:13 clootie Exp $
 *----------------------------------------------------------------------------*)

{$I DirectX.inc}

unit CrackDecl;

interface

//////////////////////////////////////////////////////////////////////////////
//
//  Copyright (C) 2000 Microsoft Corporation.  All Rights Reserved.
//
//  File:       crackdecl.h
//  Content:    Used to access vertex data using Declarations or FVFs
//
//////////////////////////////////////////////////////////////////////////////

uses
  Windows, DXTypes, Direct3D9, D3DX9;

type
  PFVFDeclaration = ^TFVFDeclaration;

  //----------------------------------------------------------------------------
  // CD3DXCrackDecl
  //----------------------------------------------------------------------------
  CD3DXCrackDecl = class
  protected

    //just a pointer to the Decl! No data stored!
    {CONST} pElements: PFVFDeclaration; // PD3DVertexElement9;
    dwNumElements: DWORD;

    //still need the stream pointer though
    //and the strides
    pStream: array[0..15] of PByte;
    dwStride: array[0..15] of DWORD;

  public
    constructor Create;

    function SetDeclaration(const pDecl: PD3DVertexElement9): HRESULT;
    function SetStreamSource(Stream: LongWord; pData: Pointer; Stride: LongWord): HRESULT;

    // Get
    function GetVertexStride(Stream: LongWord): LongWord;{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}

    function GetFields(const pElement: PD3DVertexElement9): LongWord;//{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}

    function GetVertex(Stream: LongWord; Index: LongWord): PByte;{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}
    function GetElementPointer(const Element: PD3DVertexElement9; Index: LongWord): PByte;{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}


    function GetSemanticElement(Usage: TD3DDeclUsage; UsageIndex: LongWord): {CONST} PD3DVertexElement9;{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}
    //simple function that gives part of the decl back
    function GetIndexElement(Index: LongWord): {CONST} PD3DVertexElement9;{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}

    // Encode/Decode
    procedure Decode(const pElem: PD3DVertexElement9; Index: LongWord; pData: PSingle; cData: LongWord);
    procedure Encode(const pElem: PD3DVertexElement9; Index: LongWord; const pDataArray: PSingle; cData: LongWord);

    procedure DecodeSemantic(Usage: TD3DDeclUsage; UsageIndex, VertexIndex: LongWord; pData: PSingle; cData: LongWord);{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}
    procedure EncodeSemantic(Usage: TD3DDeclUsage; UsageIndex, VertexIndex: LongWord; pData: PSingle; cData: LongWord);{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}

    property Elements: PFVFDeclaration read pElements;
    property NumElements: DWORD read dwNumElements;

    property GetElements: PFVFDeclaration read pElements;  // C++ compatibility
    property GetNumElements: DWORD read dwNumElements;     // C++ compatibility


    function DeclUsageToString(usage: TD3DDeclUsage): {CONST} PWideChar;
  end;


function GetDeclElement(pDecl: {const} PD3DVertexElement9; Usage: TD3DDeclUsage; UsageIndex: Byte): {const} PD3DVertexElement9;{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}
procedure AppendDeclElement(pNew: {const} PD3DVertexElement9; const pDecl: TFVFDeclaration);//{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}


implementation


{ CD3DXCrackDecl }

constructor CD3DXCrackDecl.Create;
var
  i: LongWord;
begin
  for i := 0 to 15 do dwStride[i] := 0;
end;

procedure CD3DXCrackDecl.DecodeSemantic(Usage: TD3DDeclUsage;
  UsageIndex, VertexIndex: LongWord; pData: PSingle; cData: LongWord);
begin
  Decode(GetSemanticElement(Usage, UsageIndex), VertexIndex, pData, cData);
end;

procedure CD3DXCrackDecl.EncodeSemantic(Usage: TD3DDeclUsage;
  UsageIndex, VertexIndex: LongWord; pData: PSingle; cData: LongWord);
begin
  Encode(GetSemanticElement(Usage, UsageIndex), VertexIndex, pData, cData);
end;

function CD3DXCrackDecl.GetElementPointer(
  const Element: PD3DVertexElement9; Index: LongWord): PByte;
begin
  Result:= PByte(PtrInt(GetVertex(Element.Stream, Index)) + Element.Offset);
end;


const
  x_rgcbFields: array [TD3DDeclType] of Byte = (
    1, // D3DDECLTYPE_FLOAT1,        // 1D float expanded to (value, 0., 0., 1.)
    2, // D3DDECLTYPE_FLOAT2,        // 2D float expanded to (value, value, 0., 1.)
    3, // D3DDECLTYPE_FLOAT3,       / 3D float expanded to (value, value, value, 1.)
    4, // D3DDECLTYPE_FLOAT4,       / 4D float
    4, // D3DDECLTYPE_D3DCOLOR,      // 4D packed unsigned bytes mapped to 0. to 1. range
    //                      // Input is in D3DCOLOR format (ARGB) expanded to (R, G, B, A)
    4, // D3DDECLTYPE_UBYTE4,        // 4D unsigned byte
    2, // D3DDECLTYPE_SHORT2,        // 2D signed short expanded to (value, value, 0., 1.)
    4, // D3DDECLTYPE_SHORT4         // 4D signed short

    4, // D3DDECLTYPE_UBYTE4N,       // Each of 4 bytes is normalized by dividing to 255.0
    2, // D3DDECLTYPE_SHORT2N,       // 2D signed short normalized (v[0]/32767.0,v[1]/32767.0,0,1)
    4, // D3DDECLTYPE_SHORT4N,       // 4D signed short normalized (v[0]/32767.0,v[1]/32767.0,v[2]/32767.0,v[3]/32767.0)
    2, // D3DDECLTYPE_USHORT2N,      // 2D unsigned short normalized (v[0]/65535.0,v[1]/65535.0,0,1)
    4, // D3DDECLTYPE_USHORT4N,      // 4D unsigned short normalized (v[0]/65535.0,v[1]/65535.0,v[2]/65535.0,v[3]/65535.0)
    3, // D3DDECLTYPE_UDEC3,         // 3D unsigned 10 10 10 format expanded to (value, value, value, 1)
    3, // D3DDECLTYPE_DEC3N,         // 3D signed 10 10 10 format normalized and expanded to (v[0]/511.0, v[1]/511.0, v[2]/511.0, 1)
    2, // D3DDECLTYPE_FLOAT16_2,     // 2D 16 bit float expanded to (value, value, 0, 1 )
    4, // D3DDECLTYPE_FLOAT16_4,     // 4D 16 bit float
    0 // D3DDECLTYPE_UNKNOWN,       // Unknown
  );


function CD3DXCrackDecl.GetFields(const pElement: PD3DVertexElement9): LongWord;
begin
  if (pElement^._Type <= D3DDECLTYPE_FLOAT16_4)
  then Result:= x_rgcbFields[pElement._Type]
  else Result:= 0;
end;

function CD3DXCrackDecl.GetIndexElement(
  Index: LongWord): PD3DVertexElement9;
begin
  if (Index < dwNumElements)
  then Result:= @pElements[Index]
  else Result:= nil;
end;

function CD3DXCrackDecl.GetSemanticElement(Usage: TD3DDeclUsage;
  UsageIndex: LongWord): PD3DVertexElement9;
var
  pPlace: PD3DVertexElement9;
begin
  pPlace := @pElements[0];
  while (pPlace.Stream <> $ff) do
  begin
    if (pPlace.Usage = Usage) and
       (pPlace.UsageIndex = UsageIndex) then
    begin
      Result:= pPlace;
      Exit;
    end else
      Inc(pPlace);
  end;
  Result:= nil;
end;

function CD3DXCrackDecl.GetVertex(Stream, Index: LongWord): PByte;
begin
  Result:= PByte(PtrUInt(pStream[Stream]) + dwStride[Stream] * Index);
end;

function CD3DXCrackDecl.GetVertexStride(Stream: LongWord): LongWord;
begin
  Result:= dwStride[Stream];
end;

function CD3DXCrackDecl.SetDeclaration(const pDecl: PD3DVertexElement9): HRESULT;
begin
  pElements := PFVFDeclaration(pDecl);
  dwNumElements := D3DXGetDeclLength(pDecl);
  Result:= S_OK;
end;

function CD3DXCrackDecl.SetStreamSource(Stream: LongWord; pData: Pointer;
  Stride: LongWord): HRESULT;
begin
  pStream[Stream] := pData;
  if (Stride = 0)
  then dwStride[Stream] := D3DXGetDeclVertexSize(@pElements[0], Stream)
  else dwStride[Stream] := Stride;

  Result:= S_OK;
end;


function BIdenticalDecls(const pDecl1, pDecl2: PD3DVertexElement9): Boolean;{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}
var
  pCurSrc, pCurDest: PD3DVertexElement9;
begin
  pCurSrc := pDecl1;
  pCurDest := pDecl2;
  while (pCurSrc.Stream <> $ff) and (pCurDest.Stream <> $ff) do
  begin
    if (pCurDest.Stream <> pCurSrc.Stream)
        and (pCurDest.Offset <> pCurSrc.Offset)
        or (pCurDest._Type <> pCurSrc._Type)
        or (pCurDest.Method <> pCurSrc.Method)
        or (pCurDest.Usage <> pCurSrc.Usage)
        or (pCurDest.UsageIndex <> pCurSrc.UsageIndex)
    then Break;

    Inc(pCurSrc);
    Inc(pCurDest);
  end;

  // it is the same decl if reached the end at the same time on both decls
  Result:= (pCurSrc.Stream = $ff) and (pCurDest.Stream = $ff);
end;

procedure CopyDecls(pDest, pSrc: PD3DVertexElement9);{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}
begin
  while (pSrc.Stream <> $ff) do
  begin
    CopyMemory(pDest, pSrc, SizeOf(TD3DVertexElement9));

    Inc(pSrc);
    Inc(pDest);
  end;
  CopyMemory(pDest, pSrc, SizeOf(TD3DVertexElement9));
end;


const
  x_rgcbTypeSizes: array [TD3DDeclType] of Byte = (
    4, // D3DDECLTYPE_FLOAT1,        // 1D float expanded to (value, 0., 0., 1.)
    8, // D3DDECLTYPE_FLOAT2,        // 2D float expanded to (value, value, 0., 1.)
    12, // D3DDECLTYPE_FLOAT3,       / 3D float expanded to (value, value, value, 1.)
    16, // D3DDECLTYPE_FLOAT4,       / 4D float
    4, // D3DDECLTYPE_D3DCOLOR,      // 4D packed unsigned bytes mapped to 0. to 1. range
    //                      // Input is in D3DCOLOR format (ARGB) expanded to (R, G, B, A)
    4, // D3DDECLTYPE_UBYTE4,        // 4D unsigned byte
    4, // D3DDECLTYPE_SHORT2,        // 2D signed short expanded to (value, value, 0., 1.)
    8, // D3DDECLTYPE_SHORT4         // 4D signed short

    4, // D3DDECLTYPE_UBYTE4N,       // Each of 4 bytes is normalized by dividing to 255.0
    4, // D3DDECLTYPE_SHORT2N,       // 2D signed short normalized (v[0]/32767.0,v[1]/32767.0,0,1)
    8, // D3DDECLTYPE_SHORT4N,       // 4D signed short normalized (v[0]/32767.0,v[1]/32767.0,v[2]/32767.0,v[3]/32767.0)
    4, // D3DDECLTYPE_USHORT2N,      // 2D unsigned short normalized (v[0]/65535.0,v[1]/65535.0,0,1)
    8, // D3DDECLTYPE_USHORT4N,      // 4D unsigned short normalized (v[0]/65535.0,v[1]/65535.0,v[2]/65535.0,v[3]/65535.0)
    4, // D3DDECLTYPE_UDEC3,         // 3D unsigned 10 10 10 format expanded to (value, value, value, 1)
    4, // D3DDECLTYPE_DEC3N,         // 3D signed 10 10 10 format normalized and expanded to (v[0]/511.0, v[1]/511.0, v[2]/511.0, 1)
    4, // D3DDECLTYPE_FLOAT16_2,     // 2D 16 bit float expanded to (value, value, 0, 1 )
    8, // D3DDECLTYPE_FLOAT16_4,     // 4D 16 bit float
    0  // D3DDECLTYPE_UNUSED,        // Unused
  );


function GetDeclElement(pDecl: {const} PD3DVertexElement9; Usage: TD3DDeclUsage; UsageIndex: Byte): {const} PD3DVertexElement9;{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}
begin
  while (pDecl.Stream <> $ff) do
  begin
    if (pDecl.Usage = Usage) and (pDecl.UsageIndex = UsageIndex) then
    begin
      Result:= pDecl;
      Exit;
    end;

    Inc(pDecl);
  end;

  Result:= nil;
end;

procedure RemoveDeclElement(Usage: TD3DDeclUsage; UsageIndex: Byte; const pDecl: TFVFDeclaration);{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}
var
  pCur: PD3DVertexElement9;
  pPrev: PD3DVertexElement9;
  cbElementSize: Byte;
begin
  pCur := @pDecl[0];
  while (pCur.Stream <> $ff) do
  begin
    if (pCur.Usage = Usage) and (pCur.UsageIndex = UsageIndex) then
    begin
      Break;
    end;
    Inc(pCur);
  end;

  //. if we found one to remove, then remove it
  if (pCur.Stream <> $ff) then
  begin
    cbElementSize := x_rgcbTypeSizes[pCur._Type];

    pPrev := pCur;
    Inc(pCur);
    while (pCur.Stream <> $ff) do
    begin
      CopyMemory(pPrev, pCur, SizeOf(TD3DVertexElement9));

      pPrev.Offset := pPrev.Offset - cbElementSize;

      Inc(pPrev);
      Inc(pCur);
    end;

    // copy the end of stream down one
    CopyMemory(pPrev, pCur, SizeOf(TD3DVertexElement9));
  end;
end;

// NOTE: size checking of array should happen OUTSIDE this function!
procedure AppendDeclElement(pNew: {const} PD3DVertexElement9; const pDecl: TFVFDeclaration);//{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}
var
  pCur: PD3DVertexElement9;
  cbOffset: Byte;
begin
  pCur := @pDecl[0];
  cbOffset := 0;
  while (pCur.Stream <> $ff) do
  begin
    Inc(cbOffset, x_rgcbTypeSizes[pCur._Type]);
    Inc(pCur);
  end;

  // NOTE: size checking of array should happen OUTSIDE this function!
  // assert(pCur - pDecl + 1 < MAX_FVF_DECL_SIZE);
  Assert((PtrInt(pCur) - PtrInt(@pDecl)) div SizeOf(TD3DVertexElement9) + 1 < MAX_FVF_DECL_SIZE);

  // move the end of the stream down one
  CopyMemory(Pointer(PtrInt(pCur)+SizeOf(TD3DVertexElement9)), pCur, SizeOf(TD3DVertexElement9));

  // copy the new element in and update the offset
  CopyMemory(pCur, pNew, SizeOf(TD3DVertexElement9));
  pCur.Offset := cbOffset;
end;

// NOTE: size checking of array should happen OUTSIDE this function!
procedure InsertDeclElement(iInsertBefore: LongWord; pNew: {const} PD3DVertexElement9; const pDecl: TFVFDeclaration);{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}
var
  pCur: PD3DVertexElement9;
  cbOffset: Byte;
  cbNewOffset: Byte;
  TempElement1: TD3DVertexElement9;
  TempElement2: TD3DVertexElement9;
  iCur: LongWord;
begin
  pCur := @pDecl[0];
  cbOffset := 0;
  iCur := 0;
  while (pCur.Stream <> $ff) and (iCur < iInsertBefore) do
  begin
    Inc(cbOffset, x_rgcbTypeSizes[pCur._Type]);
    Inc(pCur);
    Inc(iCur);
  end;

  // NOTE: size checking of array should happen OUTSIDE this function!
  // assert(pCur - pDecl + 1 < MAX_FVF_DECL_SIZE);
  Assert((PtrInt(pCur) - PtrInt(@pDecl)) div SizeOf(TD3DVertexElement9) + 1 < MAX_FVF_DECL_SIZE);

  // if we hit the end, just append
  if (pCur.Stream = $ff) then
  begin
    // move the end of the stream down one
    CopyMemory(Pointer(PtrInt(pCur)+SizeOf(TD3DVertexElement9)), pCur, SizeOf(TD3DVertexElement9));

    // copy the new element in and update the offset
    CopyMemory(pCur, pNew, SizeOf(TD3DVertexElement9));
    pCur.Offset := cbOffset;
  end else  // insert in the middle
  begin
    // save off the offset for the new decl
    cbNewOffset := cbOffset;

    // calculate the offset for the first element shifted up
    Inc(cbOffset, x_rgcbTypeSizes[pNew._Type]);

    // save off the first item to move, data so that we can copy the new element in
    CopyMemory(@TempElement1, pCur, SizeOf(TD3DVertexElement9));

    // copy the new element in
    CopyMemory(pCur, pNew, SizeOf(TD3DVertexElement9));
    pCur.Offset := cbNewOffset;

    // advance pCur one because we effectively did an iteration of the loop adding the new element
    Inc(pCur);

    while (pCur.Stream <> $ff) do
    begin
      // save off the current element
      CopyMemory(@TempElement2, pCur, SizeOf(TD3DVertexElement9));

      // update the current element with the previous's value which was stored in TempElement1
      CopyMemory(pCur, @TempElement1, SizeOf(TD3DVertexElement9));

      // move the current element's value into TempElement1 for the next iteration
      CopyMemory(@TempElement1, @TempElement2, SizeOf(TD3DVertexElement9));

      pCur.Offset := cbOffset;
      Inc(cbOffset, x_rgcbTypeSizes[pCur._Type]);

      Inc(pCur);
    end;

  // now we exited one element, need to move the end back one and copy in the last element
    // move the end element back one
    CopyMemory(Pointer(PtrInt(pCur)+SizeOf(TD3DVertexElement9)), pCur, SizeOf(TD3DVertexElement9));

    // copy the prev element's data out of the temp and into the last element
    CopyMemory(pCur, @TempElement1, SizeOf(TD3DVertexElement9));
    pCur.Offset := cbOffset;
  end;
end;


procedure CD3DXCrackDecl.Decode(const pElem: PD3DVertexElement9;
  Index: LongWord; pData: PSingle; cData: LongWord);
type
  PSingleArray = ^TSingleArray;
  TSingleArray = array[0..3] of Single;
  PByteArray = ^TByteArray;
  TByteArray = array[0..3] of Byte;
  PSmallintArray = ^TSmallintArray;
  TSmallintArray = array[0..3] of Smallint;
  PWordArray = ^TWordArray;
  TWordArray = array[0..3] of Word;
var
  Data: array[0..3] of Single;
  pElement: Pointer;
  nX, nY, nZ, nW: Smallint;
  nXl, nYl, nZl: Longint;
  i: Integer;
begin
  if Assigned(pElem) then
  begin
    pElement := GetElementPointer(pElem,index);

    case pElem._Type of
      D3DDECLTYPE_FLOAT1:
      begin
        Data[0] := PSingleArray(pElement)[0];
        Data[1] := 0.0;
        Data[2] := 0.0;
        Data[3] := 1.0;
      end;

      D3DDECLTYPE_FLOAT2:
      begin
        Data[0] := PSingleArray(pElement)[0];
        Data[1] := PSingleArray(pElement)[1];
        Data[2] := 0.0;
        Data[3] := 1.0;
      end;

      D3DDECLTYPE_FLOAT3:
      begin
        Data[0] := PSingleArray(pElement)[0];
        Data[1] := PSingleArray(pElement)[1];
        Data[2] := PSingleArray(pElement)[2];
        Data[3] := 1.0;
      end;

      D3DDECLTYPE_FLOAT4:
      begin
        Data[0] := PSingleArray(pElement)[0];
        Data[1] := PSingleArray(pElement)[1];
        Data[2] := PSingleArray(pElement)[2];
        Data[3] := PSingleArray(pElement)[3];
      end;

      D3DDECLTYPE_D3DCOLOR:
      begin
        Data[0] := (1.0 / 255.0) * Byte(PD3DColor(pElement)^ shr 16);
        Data[1] := (1.0 / 255.0) * Byte(PD3DColor(pElement)^ shr  8);
        Data[2] := (1.0 / 255.0) * Byte(PD3DColor(pElement)^ shr  0);
        Data[3] := (1.0 / 255.0) * Byte(PD3DColor(pElement)^ shr 24);
      end;

      D3DDECLTYPE_UBYTE4:
      begin
        Data[0] := PByteArray(pElement)[0];
        Data[1] := PByteArray(pElement)[1];
        Data[2] := PByteArray(pElement)[2];
        Data[3] := PByteArray(pElement)[3];
      end;

      D3DDECLTYPE_SHORT2:
      begin
        Data[0] := PSmallintArray(pElement)[0];
        Data[1] := PSmallintArray(pElement)[1];
        Data[2] := 0.0;
        Data[3] := 1.0;
      end;

      D3DDECLTYPE_SHORT4:
      begin
        Data[0] := PSmallintArray(pElement)[0];
        Data[1] := PSmallintArray(pElement)[1];
        Data[2] := PSmallintArray(pElement)[2];
        Data[3] := PSmallintArray(pElement)[3];
      end;

      D3DDECLTYPE_UBYTE4N:
      begin
        Data[0] := (1.0 / 255.0) * PByteArray(pElement)[0];
        Data[1] := (1.0 / 255.0) * PByteArray(pElement)[1];
        Data[2] := (1.0 / 255.0) * PByteArray(pElement)[2];
        Data[3] := (1.0 / 255.0) * PByteArray(pElement)[3];
      end;

      D3DDECLTYPE_SHORT2N:
      begin
        nX := PSmallintArray(pElement)[0];
        nY := PSmallintArray(pElement)[1];

        if (-32768 = Integer(nX)) then Inc(nX); //  nX += (-32768 == nX);
        if (-32768 = Integer(nY)) then Inc(nY); //  nY += (-32768 == nY);

        Data[0] := (1.0 / 32767.0) * nX;
        Data[1] := (1.0 / 32767.0) * nY;
        Data[2] := 0.0;
        Data[3] := 1.0;
      end;

      D3DDECLTYPE_SHORT4N:
      begin
        nX := PSmallintArray(pElement)[0];
        nY := PSmallintArray(pElement)[1];
        nZ := PSmallintArray(pElement)[2];
        nW := PSmallintArray(pElement)[3];

        if (-32768 = Integer(nX)) then Inc(nX); //  nX += (-32768 == nX);
        if (-32768 = Integer(nY)) then Inc(nY); //  nY += (-32768 == nY);
        if (-32768 = Integer(nZ)) then Inc(nZ); //  nZ += (-32768 == nZ);
        if (-32768 = Integer(nW)) then Inc(nW); //  nW += (-32768 == nW);

        Data[0] := (1.0 / 32767.0) * nX;
        Data[1] := (1.0 / 32767.0) * nY;
        Data[2] := (1.0 / 32767.0) * nZ;
        Data[3] := (1.0 / 32767.0) * nW;
      end;

      D3DDECLTYPE_USHORT2N:
      begin
        Data[0] := (1.0 / 65535.0) * PWordArray(pElement)[0];
        Data[1] := (1.0 / 65535.0) * PWordArray(pElement)[1];
        Data[2] := 0.0;
        Data[3] := 1.0;
      end;

      D3DDECLTYPE_USHORT4N:
      begin
        Data[0] := (1.0 / 65535.0) * PWordArray(pElement)[0];
        Data[1] := (1.0 / 65535.0) * PWordArray(pElement)[1];
        Data[2] := (1.0 / 65535.0) * PWordArray(pElement)[2];
        Data[3] := (1.0 / 65535.0) * PWordArray(pElement)[3];
      end;

      D3DDECLTYPE_UDEC3:
      begin
        Data[0] := (PLongword(pElement)^ shr  0) and $3ff;
        Data[1] := (PLongword(pElement)^ shr 10) and $3ff;
        Data[2] := (PLongword(pElement)^ shr 20) and $3ff;
        Data[3] := 1.0;
      end;

      D3DDECLTYPE_DEC3N:
      begin
        nXl := (PLongint(pElement)^ shl 22) shr 22;
        nYl := (PLongint(pElement)^ shl 12) shr 22;
        nZl := (PLongint(pElement)^ shl  2) shr 22;

        if (-512 = nXl) then Inc(nXl); // nX += (-512 == nX);
        if (-512 = nYl) then Inc(nYl); // nY += (-512 == nY);
        if (-512 = nZl) then Inc(nZl); // nZ += (-512 == nZ);

        Data[0] := (1.0 / 511.0) * nXl;
        Data[1] := (1.0 / 511.0) * nYl;
        Data[2] := (1.0 / 511.0) * nZl;
        Data[3] := 1.0;
      end;

      D3DDECLTYPE_FLOAT16_2:
      begin
        D3DXFloat16To32Array(@Data, PD3DXFloat16(pElement), 2);
        Data[2] := 0.0;
        Data[3] := 1.0;
      end;

      D3DDECLTYPE_FLOAT16_4:
        D3DXFloat16To32Array(@Data, PD3DXFloat16(pElement), 4);
    end;
  end else
  begin
    Data[0] := 0.0;
    Data[1] := 0.0;
    Data[2] := 0.0;
    Data[3] := 1.0;
  end;

  if (cData > 4) then cData := 4;

  for i := 0 to cData - 1 do PSingleArray(pData)[i] := Data[i];
end;


procedure CD3DXCrackDecl.Encode(const pElem: PD3DVertexElement9;
  Index: LongWord; const pDataArray: PSingle; cData: LongWord);
type
  PSingleArray = ^TSingleArray;
  TSingleArray = array[0..3] of Single;
  PByteArray = ^TByteArray;
  TByteArray = array[0..3] of Byte;
  PSmallintArray = ^TSmallintArray;
  TSmallintArray = array[0..3] of Smallint;
  PWordArray = ^TWordArray;
  TWordArray = array[0..3] of Word;
var
  i: LongWord;
  Data: array[0..3] of Single;
  pData: PSingleArray;
  pElement: Pointer;
begin
  pData:= PSingleArray(pDataArray);

  // Set default values
  Data[0] := 0.0; Data[1] := 0.0; Data[2] := 0.0; Data[3] := 1.0;

  if(cData > 4) then cData := 4;

  case pElem._Type of
    D3DDECLTYPE_D3DCOLOR,
    D3DDECLTYPE_UBYTE4N,
    D3DDECLTYPE_USHORT2N,
    D3DDECLTYPE_USHORT4N:
    begin
      for i:= 0 to cData - 1 do
      begin
        if (0.0 > pData[i]) then Data[i] := 0.0 else
        if (1.0 < pData[i]) then Data[i] := 1.0 else
          Data[i]:= pData[i];
      end;
    end;

    D3DDECLTYPE_SHORT2N,
    D3DDECLTYPE_SHORT4N,
    D3DDECLTYPE_DEC3N:
    begin
      for i:= 0 to cData - 1 do
      begin
        if (-1.0 > pData[i]) then Data[i] := -1.0 else
        if ( 1.0 < pData[i]) then Data[i] :=  1.0 else
          Data[i]:= pData[i];
      end;
    end;

    D3DDECLTYPE_UBYTE4,
    D3DDECLTYPE_UDEC3:
    begin
      for i:= 0 to cData - 1 do
      begin
        if (0.0 > pData[i]) then Data[i] := 0.0 else
          Data[i]:= pData[i];
      end;
    end;

  else
    for i:= 0 to cData - 1 do
      Data[i] := pData[i];
  end;

  if Assigned(pElem) then
  begin
    pElement := GetElementPointer(pElem, index);

    case pElem._Type of
      D3DDECLTYPE_FLOAT1:
        PSingleArray(pElement)[0] := Data[0];

      D3DDECLTYPE_FLOAT2:
      begin
        PSingleArray(pElement)[0] := Data[0];
        PSingleArray(pElement)[1] := Data[1];
      end;

      D3DDECLTYPE_FLOAT3:
      begin
        PSingleArray(pElement)[0] := Data[0];
        PSingleArray(pElement)[1] := Data[1];
        PSingleArray(pElement)[2] := Data[2];
      end;

      D3DDECLTYPE_FLOAT4:
      begin
        PSingleArray(pElement)[0] := Data[0];
        PSingleArray(pElement)[1] := Data[1];
        PSingleArray(pElement)[2] := Data[2];
        PSingleArray(pElement)[3] := Data[3];
      end;

      D3DDECLTYPE_D3DCOLOR:
      begin
        PD3DColor(pElement)^ :=
            ((Trunc(Data[0] * 255.0 + 0.5) and $ff) shl 16) or
            ((Trunc(Data[1] * 255.0 + 0.5) and $ff) shl  8) or
            ((Trunc(Data[2] * 255.0 + 0.5) and $ff) shl  0) or
            ((Trunc(Data[3] * 255.0 + 0.5) and $ff) shl 24);
      end;

      D3DDECLTYPE_UBYTE4:
      begin
        PByteArray(pElement)[0] := Trunc(Data[0] + 0.5);
        PByteArray(pElement)[1] := Trunc(Data[1] + 0.5);
        PByteArray(pElement)[2] := Trunc(Data[2] + 0.5);
        PByteArray(pElement)[3] := Trunc(Data[3] + 0.5);
      end;

      D3DDECLTYPE_SHORT2:
      begin
        PSmallintArray(pElement)[0] := Trunc(Data[0] + 0.5);
        PSmallintArray(pElement)[1] := Trunc(Data[1] + 0.5);
      end;

      D3DDECLTYPE_SHORT4:
      begin
        PSmallintArray(pElement)[0] := Trunc(Data[0] + 0.5);
        PSmallintArray(pElement)[1] := Trunc(Data[1] + 0.5);
        PSmallintArray(pElement)[2] := Trunc(Data[2] + 0.5);
        PSmallintArray(pElement)[3] := Trunc(Data[3] + 0.5);
      end;

      D3DDECLTYPE_UBYTE4N:
      begin
        PByteArray(pElement)[0] := Trunc(Data[0] * 255.0 + 0.5);
        PByteArray(pElement)[1] := Trunc(Data[1] * 255.0 + 0.5);
        PByteArray(pElement)[2] := Trunc(Data[2] * 255.0 + 0.5);
        PByteArray(pElement)[3] := Trunc(Data[3] * 255.0 + 0.5);
      end;

      D3DDECLTYPE_SHORT2N:
      begin
        PSmallintArray(pElement)[0] := Trunc(Data[0] * 32767.0 + 0.5);
        PSmallintArray(pElement)[1] := Trunc(Data[1] * 32767.0 + 0.5);
      end;

      D3DDECLTYPE_SHORT4N:
      begin
        PSmallintArray(pElement)[0] := Trunc(Data[0] * 32767.0 + 0.5);
        PSmallintArray(pElement)[1] := Trunc(Data[1] * 32767.0 + 0.5);
        PSmallintArray(pElement)[2] := Trunc(Data[2] * 32767.0 + 0.5);
        PSmallintArray(pElement)[3] := Trunc(Data[3] * 32767.0 + 0.5);
      end;

      D3DDECLTYPE_USHORT2N:
      begin
        PWordArray(pElement)[0] := Trunc(Data[0] * 65535.0 + 0.5);
        PWordArray(pElement)[1] := Trunc(Data[1] * 65535.0 + 0.5);
      end;

      D3DDECLTYPE_USHORT4N:
      begin
        PWordArray(pElement)[0] := Trunc(Data[0] * 65535.0 + 0.5);
        PWordArray(pElement)[1] := Trunc(Data[1] * 65535.0 + 0.5);
        PWordArray(pElement)[2] := Trunc(Data[2] * 65535.0 + 0.5);
        PWordArray(pElement)[3] := Trunc(Data[3] * 65535.0 + 0.5);
      end;

      D3DDECLTYPE_UDEC3:
      begin
        PLongint(pElement)^ :=
            ((Trunc(Data[0] + 0.5) and $3ff) shl  0) or
            ((Trunc(Data[1] + 0.5) and $3ff) shl 10) or
            ((Trunc(Data[2] + 0.5) and $3ff) shl 20);
      end;

      D3DDECLTYPE_DEC3N:
      begin
        PLongint(pElement)^ :=
            ((Trunc(Data[0]*511.0 + 0.5) and $3ff) shl  0) or
            ((Trunc(Data[1]*511.0 + 0.5) and $3ff) shl 10) or
            ((Trunc(Data[2]*511.0 + 0.5) and $3ff) shl 20);
        end;

      D3DDECLTYPE_FLOAT16_2:
        D3DXFloat32To16Array(PD3DXFloat16(pElement), @Data, 2);

      D3DDECLTYPE_FLOAT16_4:
        D3DXFloat32To16Array(PD3DXFloat16(pElement), @Data, 4);
    end;
  end;
end;

const
  MAXD3DDECLUSAGE         = D3DDECLUSAGE_SAMPLE; //todo: Temporary (while headers still not fixed) - June SDK

const
  x_szDeclStrings: array [TD3DDeclUsage] of PWideChar = (
    'D3DDECLUSAGE_POSITION',
    'D3DDECLUSAGE_BLENDWEIGHT',
    'D3DDECLUSAGE_BLENDINDICES',
    'D3DDECLUSAGE_NORMAL',
    'D3DDECLUSAGE_PSIZE',
    'D3DDECLUSAGE_TEXCOORD',
    'D3DDECLUSAGE_TANGENT',
    'D3DDECLUSAGE_BINORMAL',
    'D3DDECLUSAGE_TESSFACTOR',
    'D3DDECLUSAGE_POSITIONT',
    'D3DDECLUSAGE_COLOR',
    'D3DDECLUSAGE_FOG',
    'D3DDECLUSAGE_DEPTH',
    'D3DDECLUSAGE_SAMPLE'
    // 'UNKNOWN'
  );
  x_szDeclStrings_Unknown{: PWideChar} = 'UNKNOWN';

function CD3DXCrackDecl.DeclUsageToString(usage: TD3DDeclUsage): PWideChar;
begin
  if (usage >= D3DDECLUSAGE_POSITION) and (usage <= MAXD3DDECLUSAGE)
  then Result:= x_szDeclStrings[usage]
  else Result:= x_szDeclStrings_Unknown; // x_szDeclStrings[MAXD3DDECLUSAGE+1];
end;

end.

