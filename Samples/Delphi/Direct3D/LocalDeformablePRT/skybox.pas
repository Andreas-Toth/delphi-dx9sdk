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
 *  $Id: skybox.pas,v 1.7 2007/02/05 22:21:09 clootie Exp $
 *----------------------------------------------------------------------------*)
//-----------------------------------------------------------------------------
// File: skybox.h, skybox.cpp
//
// Desc: Encapsulation of skybox geometry and textures
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//-----------------------------------------------------------------------------

{$I DirectX.inc}

unit skybox;

interface

uses
  Windows, Direct3D9, D3DX9, DXUTcore, DXUTmisc;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders

type
  CSkybox = class
  protected
    m_pEnvironmentMap: IDirect3DCubeTexture9;
    m_pEnvironmentMapSH: IDirect3DCubeTexture9;
    m_pEffect: ID3DXEffect;
    m_pVB: IDirect3DVertexBuffer9;
    m_pVertexDecl: IDirect3DVertexDeclaration9;
    m_pd3dDevice: IDirect3DDevice9;
    m_fSize: Single;

    m_bDrawSH: Boolean;

  public
    constructor Create;

    function OnCreateDevice(const pd3dDevice: IDirect3DDevice9; fSize: Single; pEnvMap: IDirect3DCubeTexture9; strEffectFileName: PWideChar): HRESULT; overload;
    function OnCreateDevice(const pd3dDevice: IDirect3DDevice9; fSize: Single; strCubeMapFile, strEffectFileName: PWideChar): HRESULT; overload;
    {$IFNDEF FPC}
    function OnCreateDevice(const pd3dDevice: IDirect3DDevice9; fSize: Single; strCubeMapFile, strEffectFileName: WideString): HRESULT; overload;{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}
    {$ENDIF}
    procedure OnResetDevice(const pBackBufferSurfaceDesc: TD3DSurfaceDesc);
    procedure Render(const pmWorldViewProj: TD3DXMatrix; fAlpha, fScale: Single);
    procedure OnLostDevice;
    procedure OnDestroyDevice;

    procedure InitSH(pSHTex: IDirect3DCubeTexture9);
    // function GetSHMap: IDirect3DCubeTexture9;  { return m_pEnvironmentMapSH; }
    // procedure SetDrawSH(bVal: Boolean); { m_bDrawSH = bVal; }
    // function GetEnvironmentMap: IDirect3DCubeTexture9; { return m_pEnvironmentMap; }

    property DrawSH: Boolean read m_bDrawSH write m_bDrawSH;
    property SHMap: IDirect3DCubeTexture9 read m_pEnvironmentMapSH;
    property EnvironmentMap: IDirect3DCubeTexture9 read m_pEnvironmentMap;
  end;

  
implementation


type
  PSkyboxVertex = ^TSkyboxVertex;
  TSkyboxVertex = packed record
    pos: TD3DXVector4;
    tex: TD3DXVector3;
  end;

  PSkyboxVertexArray = ^TSkyboxVertexArray;
  TSkyboxVertexArray = array[0..MaxInt div SizeOf(TSkyboxVertex)-1] of TSkyboxVertex;

var  
  g_aSkyboxDecl: array[0..1] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0; _Type: D3DDECLTYPE_FLOAT4; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITION; UsageIndex: 0),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );



{ CSkybox }

//-----------------------------------------------------------------------------
// Name: CSkybox
// Desc: Constructor
//-----------------------------------------------------------------------------
constructor CSkybox.Create;
begin
  m_pVB               := nil;
  m_pd3dDevice        := nil;
  m_pEffect           := nil;
  m_pVertexDecl       := nil;
  m_pEnvironmentMap   := nil;
  m_pEnvironmentMapSH := nil;
  m_fSize             := 1.0;
  m_bDrawSH           := False;
end;


//-----------------------------------------------------------------------------
function CSkybox.OnCreateDevice(const pd3dDevice: IDirect3DDevice9;
  fSize: Single; pEnvMap: IDirect3DCubeTexture9;
  strEffectFileName: PWideChar): HRESULT;
var
  dwShaderFlags: DWORD;
  str: array[0..MAX_PATH-1] of WideChar;
begin
  m_pd3dDevice := pd3dDevice;
  m_fSize := fSize;
  m_pEnvironmentMap := pEnvMap;

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

  // Read the D3DX effect file
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, strEffectFileName);
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // they the .fx file failed to compile
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil,
                                     dwShaderFlags, nil, m_pEffect, nil);
  if V_Failed(Result) then Exit;

  // Create vertex declaration
  Result:= pd3dDevice.CreateVertexDeclaration(@g_aSkyboxDecl, m_pVertexDecl);
  if V_Failed(Result) then Exit;

  Result:= S_OK;
end;


procedure CSkybox.InitSH(pSHTex: IDirect3DCubeTexture9);
begin
  m_pEnvironmentMapSH := pSHTex;
end;


//-----------------------------------------------------------------------------
function CSkybox.OnCreateDevice(const pd3dDevice: IDirect3DDevice9; fSize: Single;
  strCubeMapFile, strEffectFileName: PWideChar): HRESULT;
var
  strPath: array[0..MAX_PATH-1] of WideChar;
  pEnvironmentMap: IDirect3DCubeTexture9;
begin
  Result:= DXUTFindDXSDKMediaFile(strPath, MAX_PATH, strCubeMapFile);
  if V_Failed(Result) then Exit;

  Result:= D3DXCreateCubeTextureFromFileExW(pd3dDevice, strPath, 512, 1, 0, D3DFMT_A16B16G16R16F,
                                            D3DPOOL_MANAGED, D3DX_FILTER_LINEAR, D3DX_FILTER_LINEAR, 0, nil, nil, pEnvironmentMap);
  if V_Failed(Result) then Exit;

  Result:= OnCreateDevice(pd3dDevice, fSize, pEnvironmentMap, strEffectFileName);
  if V_Failed(Result) then Exit;

  Result:= S_OK;
end;

{$IFNDEF FPC}
function CSkybox.OnCreateDevice(const pd3dDevice: IDirect3DDevice9; fSize: Single;
  strCubeMapFile, strEffectFileName: WideString): HRESULT;
begin
  Result := OnCreateDevice(pd3dDevice, fSize, PWideChar(strCubeMapFile), PWideChar(strEffectFileName));
end;

{$ENDIF}

//-----------------------------------------------------------------------------
procedure CSkybox.OnResetDevice(
  const pBackBufferSurfaceDesc: TD3DSurfaceDesc);
var
  pVertex: PSkyboxVertexArray;
  fHighW, fHighH, fLowW, fLowH: Single;
begin
  if Assigned(m_pEffect) then V(m_pEffect.OnResetDevice);

  V(m_pd3dDevice.CreateVertexBuffer(4 * SizeOf(TSkyboxVertex),
                                     D3DUSAGE_WRITEONLY, 0,
                                     D3DPOOL_DEFAULT, m_pVB, nil));

  // Fill the vertex buffer
  V(m_pVB.Lock(0, 0, Pointer(pVertex), 0));

  // Map texels to pixels
  fHighW := -1.0 - (1.0/pBackBufferSurfaceDesc.Width);
  fHighH := -1.0 - (1.0/pBackBufferSurfaceDesc.Height);
  fLowW  :=  1.0 + (1.0/pBackBufferSurfaceDesc.Width);
  fLowH  :=  1.0 + (1.0/pBackBufferSurfaceDesc.Height);

  pVertex[0].pos := D3DXVector4(fLowW, fLowH, 1.0, 1.0);
  pVertex[1].pos := D3DXVector4(fLowW, fHighH, 1.0, 1.0);
  pVertex[2].pos := D3DXVector4(fHighW, fLowH, 1.0, 1.0);
  pVertex[3].pos := D3DXVector4(fHighW, fHighH, 1.0, 1.0);

  m_pVB.Unlock;
end;


//-----------------------------------------------------------------------------
// Name: Render
// Desc: 
//-----------------------------------------------------------------------------
procedure CSkybox.Render(const pmWorldViewProj: TD3DXMatrix; fAlpha, fScale: Single);
var
  mInvWorldViewProj: TD3DXMatrix;
  uiPass: Integer;
  uiNumPasses: LongWord;
begin
  D3DXMatrixInverse(mInvWorldViewProj, nil, pmWorldViewProj);
  V(m_pEffect.SetMatrix('g_mInvWorldViewProjection', mInvWorldViewProj));

  if (fScale = 0.0) or (fAlpha = 0.0) then Exit; // do nothing if no intensity...

  // Draw the skybox
  V(m_pEffect.SetTechnique('Skybox'));
  V(m_pEffect.SetFloat('g_fAlpha', fAlpha));
  V(m_pEffect.SetFloat('g_fScale', fAlpha*fScale));

  if m_bDrawSH
  then V(m_pEffect.SetTexture('g_EnvironmentTexture', m_pEnvironmentMapSH))
  else V(m_pEffect.SetTexture('g_EnvironmentTexture', m_pEnvironmentMap));

  m_pd3dDevice.SetStreamSource(0, m_pVB, 0, SizeOf(TSkyboxVertex));
  m_pd3dDevice.SetVertexDeclaration(m_pVertexDecl);

  V(m_pEffect._Begin(@uiNumPasses, 0));
  for uiPass := 0 to uiNumPasses - 1 do
  begin
    V(m_pEffect.BeginPass(uiPass));
    m_pd3dDevice.DrawPrimitive(D3DPT_TRIANGLESTRIP, 0, 2);
    V(m_pEffect.EndPass);
  end;
  V(m_pEffect._End);
end;


//-----------------------------------------------------------------------------
procedure CSkybox.OnLostDevice;
begin
  if Assigned(m_pEffect) then V(m_pEffect.OnLostDevice);
  m_pVB := nil;
end;


//-----------------------------------------------------------------------------
procedure CSkybox.OnDestroyDevice;
begin
  m_pEnvironmentMap := nil;
  m_pEnvironmentMapSH := nil;
  m_pEffect := nil;
  m_pVertexDecl := nil;
  m_pd3dDevice := nil;
end;

end.

