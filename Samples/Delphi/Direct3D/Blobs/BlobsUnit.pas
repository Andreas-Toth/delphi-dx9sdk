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
 *  $Id: BlobsUnit.pas,v 1.17 2007/02/05 22:21:03 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: Blobs.cpp
//
// Desc: A pixel shader effect to mimic metaball physics in image space.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit BlobsUnit;

interface

uses
  Windows, DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTmisc, DXUTenum, DXUTgui, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders

const
  IDI_MAIN_ICON                   = 101;

//--------------------------------------------------------------------------------------
// Constants
//--------------------------------------------------------------------------------------
const
  NUM_BLOBS           = 5;
  FIELD_OF_VIEW       = (70.0/90.0)*({D3DX_PI}3.141592654/2.0);

  GAUSSIAN_TEXSIZE    = 64;
  GAUSSIAN_HEIGHT     = 1;
  GAUSSIAN_DEVIATION  = 0.125;

//--------------------------------------------------------------------------------------
// Custom types
//--------------------------------------------------------------------------------------
type
  // Vertex format for blob billboards
  PPointVertex = ^TPointVertex;
  TPointVertex = packed record
    pos: TD3DXVector3;
    size: Single;
    color: TD3DXVector3;
  end;

const
  TPointVertex_FVF = D3DFVF_XYZ or D3DFVF_PSIZE or D3DFVF_DIFFUSE;

type
  // Vertex format for screen space work
  PScreenVertex = ^TScreenVertex;
  TScreenVertex = record
    pos:    TD3DXVector4;
    tCurr:  TD3DXVector2;
    tBack:  TD3DXVector2;
    fSize:  Single;
    vColor: TD3DXVector3;
  end;
  PScreenVertexArray = ^TScreenVertexArray;
  TScreenVertexArray = array[0..MaxInt div SizeOf(TScreenVertex)-1] of TScreenVertex;
const
  TScreenVertex_FVF = D3DFVF_XYZRHW or D3DFVF_TEX4 or
                      D3DFVF_TEXTUREFORMAT2{==0} or
                      (D3DFVF_TEXTUREFORMAT1 shl ((2)*2 + 16)) or
                      (D3DFVF_TEXTUREFORMAT3 shl ((3)*2 + 16));
                     { or D3DFVF_TEXCOORDSIZE2(0)
                       or D3DFVF_TEXCOORDSIZE2(1)
                       or D3DFVF_TEXCOORDSIZE1(2)
                       or D3DFVF_TEXCOORDSIZE3(3); }

type
  TRenderTargetSet = record
    apCopyRT: array[0..1] of IDirect3DSurface9;
    apBlendRT: array[0..1] of IDirect3DSurface9;
  end;

//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont:                ID3DXFont =  nil;            // Font for drawing text
  g_pTextSprite:          ID3DXSprite = nil;           // Sprite for batching draw text calls
  g_pEffect:              ID3DXEffect = nil;           // D3DX effect interface
  g_Camera:               CModelViewerCamera;          // A model viewing camera
  g_bShowHelp:            Boolean = True;              // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg:          CD3DSettingsDlg;             // Device settings dialog
  g_HUD:                  CDXUTDialog = nil;           // dialog for standard controls

  g_pBlobVB:              IDirect3DVertexBuffer9 = nil;// Vertex buffer for blob billboards
  g_BlobTexFormat:        TD3DFormat;                  // Texture format for blob texture

  g_BlobPoints: array[0..NUM_BLOBS-1] of TPointVertex; // Position, size, and color states

  g_pTexGBuffer: array[0..3] of IDirect3DTexture9;     // Buffer textures for blending effect
  g_pTexScratch:          IDirect3DTexture9 = nil;     // Scratch texture
  g_pTexBlob:             IDirect3DTexture9 = nil;     // Blob texture

  g_pEnvMap:              IDirect3DCubeTexture9 = nil; // Environment map

  g_nPasses:    Integer = 0;                      // Number of rendering passes required
  g_nRtUsed:    Integer = 0;                      // Number of render targets used for blending
  g_aRTSet:     array[0..1] of TRenderTargetSet = ((), ());  // Render targets for each pass
  g_hBlendTech: TD3DXHandle = nil;                // Technique to use for blending


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;


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

function GenerateGaussianTexture: HRESULT;
function FillBlobVB(const pmatWorldView: TD3DXMatrixA16): HRESULT;
function RenderFullScreenQuad(fDepth: Single): HRESULT;
procedure InitApp;
procedure RenderText;

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;

implementation


//--------------------------------------------------------------------------------------
// Initialize the app
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  i, iY: Integer;
begin
  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent); iY := 10;
  g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22); Inc(iY, 24);
  g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)',           35, iY, 125, 22); Inc(iY, 24);
  g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)',     35, iY, 125, 22, VK_F2); // Inc(iY, 24);

  // Set initial blob states
  for i:= 0 to NUM_BLOBS - 1 do
  begin
    g_BlobPoints[i].pos := D3DXVector3(0.0, 0.0, 0.0);
    g_BlobPoints[i].size := 1.0;
  end;

  g_BlobPoints[0].color := D3DXVector3(0.3, 0.0, 0.0);
  g_BlobPoints[1].color := D3DXVector3(0.0, 0.3, 0.0);
  g_BlobPoints[2].color := D3DXVector3(0.0, 0.0, 0.3);
  g_BlobPoints[3].color := D3DXVector3(0.3, 0.3, 0.0);
  g_BlobPoints[4].color := D3DXVector3(0.0, 0.3, 0.3);
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

  // No fallback, so need ps2.0
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2,0)) then Exit;

  // No fallback, so need to support render target
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
              AdapterFormat, D3DUSAGE_RENDERTARGET or D3DUSAGE_QUERY_POSTPIXELSHADER_BLENDING,
              D3DRTYPE_TEXTURE, BackBufferFormat))
  then Exit;

  // Check support for pixel formats that are going to be used
  // D3DFMT_A16B16G16R16F render target
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
              AdapterFormat, D3DUSAGE_RENDERTARGET,
              D3DRTYPE_TEXTURE, D3DFMT_A16B16G16R16F))
  then Exit;

  // D3DFMT_R32F render target
  if FAILED(pD3D.CheckDeviceFormat( pCaps.AdapterOrdinal, pCaps.DeviceType,
              AdapterFormat, D3DUSAGE_RENDERTARGET,
              D3DRTYPE_TEXTURE, D3DFMT_R32F))
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
  dwShaderFlags: DWORD;
  str: array[0..MAX_PATH-1] of WideChar;
  vecEye, vecAt: TD3DXVector3;
  Caps: TD3DCaps9;
  pD3D: IDirect3D9;
  DisplayMode: TD3DDisplayMode;
begin
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  // Query multiple RT setting and set the num of passes required
  pd3dDevice.GetDeviceCaps(Caps);
  if (Caps.NumSimultaneousRTs < 2) then
  begin
    g_nPasses := 2;
    g_nRtUsed := 1;
  end else
  begin
    g_nPasses := 1;
    g_nRtUsed := 2;
  end;

  // Determine which of D3DFMT_R16F or D3DFMT_R32F to use for blob texture
  pd3dDevice.GetDirect3D(pD3D);
  pd3dDevice.GetDisplayMode(0, DisplayMode);

  if FAILED(pD3D.CheckDeviceFormat(Caps.AdapterOrdinal, Caps.DeviceType,
              DisplayMode.Format, D3DUSAGE_RENDERTARGET,
              D3DRTYPE_TEXTURE, D3DFMT_R16F))
  then g_BlobTexFormat := D3DFMT_R32F
  else g_BlobTexFormat := D3DFMT_R16F;

  SAFE_RELEASE(pD3D);

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
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, WideString('Blobs.fx'));
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // they the .fx file failed to compile
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags,
                                     nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;


  // Initialize the technique for blending
  if (g_nPasses = 1) then
  begin
    // Multiple RT available
    g_hBlendTech := g_pEffect.GetTechniqueByName('BlobBlend');
  end else
  begin
    // Single RT. Multiple passes.
    g_hBlendTech := g_pEffect.GetTechniqueByName('BlobBlendTwoPasses');
  end;

  // Setup the camera's view parameters
  vecEye:= D3DXVector3(0.0, 0.0, -5.0);
  vecAt:=  D3DXVector3(0.0, 0.0, -0.0);
  g_Camera.SetViewParams(vecEye, vecAt);

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
  i: Integer;
  fAspectRatio: Single;
  vEyePt: TD3DXVector3;
  vLookatPt: TD3DXVector3;
  pSurf: IDirect3DSurface9;
begin
  Result:= g_DialogResourceManager.OnResetDevice;
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnResetDevice;
  if V_Failed(Result) then Exit;

  if (g_pFont <> nil) then
  begin
    Result:= g_pFont.OnResetDevice;
    if V_Failed(Result) then Exit;
  end;
  if (g_pEffect <> nil) then
  begin
    Result:= g_pEffect.OnResetDevice;
    if V_Failed(Result) then Exit;
  end;

  // Create a sprite to help batch calls when drawing many lines of text
  Result:= D3DXCreateSprite(pd3dDevice, g_pTextSprite);
  if V_Failed(Result) then Exit;

  // Create the Gaussian distribution texture
  Result:= GenerateGaussianTexture;
  if V_Failed(Result) then Exit;

  // Create the blob vertex buffer
  Result:= pd3dDevice.CreateVertexBuffer(NUM_BLOBS * 6 * SizeOf(TScreenVertex),
                                         D3DUSAGE_WRITEONLY or D3DUSAGE_DYNAMIC,
                                         TScreenVertex_FVF, D3DPOOL_DEFAULT,
                                         g_pBlobVB, nil);
  if V_Failed(Result) then Exit;

  // Create the blank texture
  Result:= pd3dDevice.CreateTexture(1, 1, 1,
                                    D3DUSAGE_RENDERTARGET,
                                    D3DFMT_A16B16G16R16F,
                                    D3DPOOL_DEFAULT,
                                    g_pTexScratch, nil);
  if V_Failed(Result) then Exit;


  // Create buffer textures
  for i:= 0 to 3 do
  begin
    Result:= pd3dDevice.CreateTexture(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height, 1,
                                      D3DUSAGE_RENDERTARGET,
                                      D3DFMT_A16B16G16R16F,
                                      D3DPOOL_DEFAULT, g_pTexGBuffer[i], nil);
    if V_Failed(Result) then Exit;
  end;

  // Initialize the render targets
  if (g_nPasses = 1) then
  begin
    // Multiple RT
    g_pTexGBuffer[2].GetSurfaceLevel(0, pSurf);
    g_aRTSet[0].apCopyRT[0] := pSurf;
    g_pTexGBuffer[3].GetSurfaceLevel(0, pSurf);
    g_aRTSet[0].apCopyRT[1] := pSurf;
    g_pTexGBuffer[0].GetSurfaceLevel(0, pSurf);
    g_aRTSet[0].apBlendRT[0] := pSurf;
    g_pTexGBuffer[1].GetSurfaceLevel(0, pSurf);
    g_aRTSet[0].apBlendRT[1] := pSurf;

    // 2nd pass is not needed. Therefore all RTs are NULL for this pass.
    g_aRTSet[1].apCopyRT[0] := nil;
    g_aRTSet[1].apCopyRT[1] := nil;
    g_aRTSet[1].apBlendRT[0] := nil;
    g_aRTSet[1].apBlendRT[1] := nil;
  end else
  begin
    // Single RT, multiple passes
    g_pTexGBuffer[2].GetSurfaceLevel(0, pSurf);
    g_aRTSet[0].apCopyRT[0] := pSurf;
    g_pTexGBuffer[3].GetSurfaceLevel(0, pSurf);
    g_aRTSet[1].apCopyRT[0] := pSurf;
    g_pTexGBuffer[0].GetSurfaceLevel(0, pSurf);
    g_aRTSet[0].apBlendRT[0] := pSurf;
    g_pTexGBuffer[1].GetSurfaceLevel(0, pSurf);
    g_aRTSet[1].apBlendRT[0] := pSurf;

    // RT 1 is not available. Therefore all RTs are NULL for this index.
    g_aRTSet[0].apCopyRT[1] := nil;
    g_aRTSet[1].apCopyRT[1] := nil;
    g_aRTSet[0].apBlendRT[1] := nil;
    g_aRTSet[1].apBlendRT[1] := nil;
  end;

  // Set the camera parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  vEyePt    := D3DXVector3(0.0, -2.0, -5.0);
  vLookatPt := D3DXVector3(0.0, 0.0, 0.0);
  g_Camera.SetViewParams(vEyePt, vLookatPt);
  g_Camera.SetProjParams(FIELD_OF_VIEW, fAspectRatio, 1.0, 100.0);
  g_Camera.SetRadius(5.0, 2.0, 20.0);
  g_Camera.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);
  g_Camera.SetInvertPitch(True);

  // Position the on-screen dialog
  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
    
  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: GenerateGaussianTexture()
// Desc: Generate a texture to store gaussian distribution results
//-----------------------------------------------------------------------------
function GenerateGaussianTexture: HRESULT;
var
  pBlobTemp: IDirect3DSurface9;
  pBlobNew: IDirect3DSurface9;
  pd3dDevice: IDirect3DDevice9;
  texTemp: IDirect3DTexture9;
  str: array[0..MAX_PATH-1] of WideChar;
  Rect: TD3DLockedRect;
  u, v: Integer;
  dx, dy, I: Single;
  pBits: PSingle;
begin
  pd3dDevice := DXUTGetD3DDevice;

  // Create a temporary texture
  Result:= pd3dDevice.CreateTexture(GAUSSIAN_TEXSIZE, GAUSSIAN_TEXSIZE, 1,
                                    D3DUSAGE_DYNAMIC, D3DFMT_R32F,
                                    D3DPOOL_DEFAULT, texTemp, nil);
  if V_Failed(Result) then Exit;

  // Create the gaussian texture
  Result:= pd3dDevice.CreateTexture(GAUSSIAN_TEXSIZE, GAUSSIAN_TEXSIZE, 1,
                                    D3DUSAGE_DYNAMIC, g_BlobTexFormat,
                                    D3DPOOL_DEFAULT, g_pTexBlob, nil);
  if V_Failed(Result) then Exit;

  // Create the environment map
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, WideString('lobby\lobbycube.dds'));
  if V_Failed(Result) then Exit;
  Result:= D3DXCreateCubeTextureFromFileW(pd3dDevice, str, g_pEnvMap);
  if V_Failed(Result) then Exit;

  // Fill in the gaussian texture data
  Result:= texTemp.LockRect(0, Rect, nil, 0);
  if V_Failed(Result) then Exit;
    
  for v:= 0 to GAUSSIAN_TEXSIZE - 1 do
  begin
    pBits := PSingle(Integer(Rect.pBits)+v*Rect.Pitch);

    for u:= 0 to GAUSSIAN_TEXSIZE - 1 do
    begin
      dx := 2.0*u/GAUSSIAN_TEXSIZE-1.0;
      dy := 2.0*v/GAUSSIAN_TEXSIZE-1.0;
      I := GAUSSIAN_HEIGHT * Exp(-(dx*dx+dy*dy)/GAUSSIAN_DEVIATION);

      pBits^:= I; Inc(pBits); // intensity
    end;
  end;

  texTemp.UnlockRect(0);

  // Copy the temporary surface to the stored gaussian texture
  Result:= texTemp.GetSurfaceLevel(0, pBlobTemp);
  if V_Failed(Result) then Exit;
  Result:= g_pTexBlob.GetSurfaceLevel(0, pBlobNew);
  if V_Failed(Result) then Exit;
  Result:= D3DXLoadSurfaceFromSurface(pBlobNew, nil, nil, pBlobTemp, nil, nil, D3DX_FILTER_NONE, 0);
  if V_Failed(Result) then Exit;
    
  SAFE_RELEASE(pBlobTemp);
  SAFE_RELEASE(pBlobNew);
  SAFE_RELEASE(texTemp);

  Result:= S_OK;
end;

    
//-----------------------------------------------------------------------------
// Name: FillBlobVB()
// Desc: Fill the vertex buffer for the blob objects
//-----------------------------------------------------------------------------
function FillBlobVB(const pmatWorldView: TD3DXMatrixA16): HRESULT;
var
  i, j: LongWord; // Loop variable
  pBlobVertex: PScreenVertexArray;
  blobPos: array[0..NUM_BLOBS-1] of TPointVertex;
  blobPosCamera: TD3DXVector4;
  posCount: Integer;

  blobScreenPos: TD3DXVector4;
  billOfs: TD3DXVector4;
  billOfsScreen: TD3DXVector4;
const
  vTexCoords: array[0..5] of TD3DXVector2 =
   (
    (x:0.0; y:0.0),
    (x:1.0; y:0.0),
    (x:0.0; y:1.0),
    (x:0.0; y:1.0),
    (x:1.0; y:0.0),
    (x:1.0; y:1.0)
  );
var
  pmatProjection: PD3DXMatrix;
  vPosOffset: array[0..5] of TD3DXVector4;
  pBackBufferSurfaceDesc: PD3DSurfaceDesc;
begin
  Result := g_pBlobVB.Lock(0, 0, Pointer(pBlobVertex), D3DLOCK_DISCARD);
  if V_Failed(Result) then Exit;

  for i:= 0 to NUM_BLOBS - 1 do
  begin
    //transform point to camera space
    D3DXVec3Transform(blobPosCamera, g_BlobPoints[i].pos, pmatWorldView);

    blobPos[i] := g_BlobPoints[i];
    blobPos[i].pos.x := blobPosCamera.x;
    blobPos[i].pos.y := blobPosCamera.y;
    blobPos[i].pos.z := blobPosCamera.z;
  end;

  posCount:= 0;
  for i:= 0 to NUM_BLOBS - 1 do
  begin
    // For calculating billboarding
    billOfs:= D3DXVector4(blobPos[i].size, blobPos[i].size, blobPos[i].pos.z, 1);

    // Transform to screenspace
    pmatProjection:= g_Camera.GetProjMatrix;
    D3DXVec3Transform(blobScreenPos, blobPos[i].pos, pmatProjection^);
    D3DXVec4Transform(billOfsScreen, billOfs, pmatProjection^);

    // Project
    D3DXVec4Scale(blobScreenPos, blobScreenPos, 1.0/blobScreenPos.w);
    D3DXVec4Scale(billOfsScreen, billOfsScreen, 1.0/billOfsScreen.w);

    vPosOffset[0]:= D3DXVector4(-billOfsScreen.x, -billOfsScreen.y, 0.0, 0.0);
    vPosOffset[1]:= D3DXVector4( billOfsScreen.x, -billOfsScreen.y, 0.0, 0.0);
    vPosOffset[2]:= D3DXVector4(-billOfsScreen.x,  billOfsScreen.y, 0.0, 0.0);
    vPosOffset[3]:= D3DXVector4(-billOfsScreen.x,  billOfsScreen.y, 0.0, 0.0);
    vPosOffset[4]:= D3DXVector4( billOfsScreen.x, -billOfsScreen.y, 0.0, 0.0);
    vPosOffset[5]:= D3DXVector4( billOfsScreen.x,  billOfsScreen.y, 0.0, 0.0);

    pBackBufferSurfaceDesc := DXUTGetBackBufferSurfaceDesc;

    // Set constants across quad
    for j:= 0 to 5 do 
    begin
      // Scale to pixels
      D3DXVec4Add(pBlobVertex[posCount].pos, blobScreenPos, vPosOffset[j]);

      with pBlobVertex[posCount] do
      begin
        pos.x := pos.x * pBackBufferSurfaceDesc.Width;
        pos.y := pos.y * pBackBufferSurfaceDesc.Height;
        pos.x := pos.x + 0.5 * pBackBufferSurfaceDesc.Width;
        pos.y := pos.y + 0.5 * pBackBufferSurfaceDesc.Height;

        tCurr := vTexCoords[j];
        tBack := D3DXVector2((0.5 + pos.x)*(1.0/pBackBufferSurfaceDesc.Width),
                             (0.5 + pos.y)*(1.0/pBackBufferSurfaceDesc.Height));
        fSize := blobPos[i].size;
        vColor := blobPos[i].color;
      end;

      Inc(posCount);
    end;
  end;
  g_pBlobVB.Unlock;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called once at the beginning of every frame. This is the
// best location for your application to handle updates to the scene, but is not 
// intended to contain actual rendering calls, which should instead be placed in the 
// OnFrameRender callback.
//--------------------------------------------------------------------------------------
var bPaused: Boolean = False;
procedure OnFrameMove(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  mWorldView: TD3DXMatrixA16;
  mWorldViewProjection: TD3DXMatrixA16;
  pos: Single;
begin
  // Update the camera's position based on user input
  g_Camera.FrameMove(fElapsedTime );

  // Pause animatation if the user is rotating around
  if not IsIconic(DXUTGetHWND) then
  begin
    if g_Camera.IsBeingDragged and not DXUTIsTimePaused then DXUTPause(True, False);
    if not g_Camera.IsBeingDragged and DXUTIsTimePaused then DXUTPause(False, False);
  end;

  // Get the projection & view matrix from the camera class
  D3DXMatrixMultiply(mWorldView, g_Camera.GetWorldMatrix^, g_Camera.GetViewMatrix^);
  D3DXMatrixMultiply(mWorldViewProjection, mWorldView, g_Camera.GetProjMatrix^);

  // Update the effect's variables.  Instead of using strings, it would 
  // be more efficient to cache a handle to the parameter by calling 
  // ID3DXEffect::GetParameterByName
  V(g_pEffect.SetMatrix('g_mWorldViewProjection', mWorldViewProjection));

  
  // Animate the blobs
  pos := (1.0 + Cos(2 * D3DX_PI * fTime/3.0));
  g_BlobPoints[1].pos.x := pos;
  g_BlobPoints[2].pos.x := -pos;
  g_BlobPoints[3].pos.y := pos;
  g_BlobPoints[4].pos.y := -pos;
   

  FillBlobVB(mWorldView);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called at the end of every frame to perform all the
// rendering calls for the scene, and it will also be called if the window needs to be
// repainted. After this function has returned, DXUT will call
// IDirect3DDevice9::Present to display the contents of the next buffer in the swap chain
//--------------------------------------------------------------------------------------
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  apSurfOldRenderTarget: array[0..1] of IDirect3DSurface9; // = { NULL, NULL };
  pSurfOldDepthStencil: IDirect3DSurface9;
  pGBufSurf: array[0..3] of IDirect3DSurface9;
  pSurfBlank: IDirect3DSurface9;
  i: Integer;
  iPass, nNumPasses: LongWord;
  rt: Integer;
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

  // Render the scene
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    // Get the initial device surfaces
    V(pd3dDevice.GetRenderTarget(0, apSurfOldRenderTarget[0])); // Only RT 0 should've been set.
    V(pd3dDevice.GetDepthStencilSurface(pSurfOldDepthStencil));

    // Turn off Z
    V(pd3dDevice.SetRenderState(D3DRS_ZENABLE, D3DZB_FALSE));
    V(pd3dDevice.SetDepthStencilSurface(nil));

    // Clear the blank texture
    V(g_pTexScratch.GetSurfaceLevel(0, pSurfBlank));
    V(pd3dDevice.SetRenderTarget(0, pSurfBlank));
    V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET , D3DCOLOR_ARGB(0,0,0,0), 1.0, 0));
    SAFE_RELEASE(pSurfBlank);

    // clear temp textures
    for i:= 0 to 1 do
    begin
      V(g_pTexGBuffer[i].GetSurfaceLevel(0, pGBufSurf[i]));
      V(pd3dDevice.SetRenderTarget(0, pGBufSurf[i]));
      V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET, D3DCOLOR_ARGB(0,0,0,0), 1.0, 0));
    end;
    for i := 2 to 3 do
      V(g_pTexGBuffer[i].GetSurfaceLevel(0, pGBufSurf[i]));

    V(pd3dDevice.SetStreamSource(0, g_pBlobVB, 0, SizeOf(TScreenVertex)));
    V(pd3dDevice.SetFVF(TScreenVertex_FVF));
        
        
    // Render the blobs
    V(g_pEffect.SetTechnique(g_hBlendTech));

    for i:= 0 to NUM_BLOBS - 1 do
    begin
      // Copy bits off of render target into scratch surface [for blending].
      V(g_pEffect.SetTexture('g_tSourceBlob', g_pTexScratch));
      V(g_pEffect.SetTexture('g_tNormalBuffer', g_pTexGBuffer[0]));
      V(g_pEffect.SetTexture('g_tColorBuffer', g_pTexGBuffer[1]));

      if SUCCEEDED(g_pEffect._Begin(@nNumPasses, 0)) then
      begin
        for iPass:=0 to nNumPasses - 1 do
        begin
          for rt := 0 to g_nRtUsed - 1 do
            V(pd3dDevice.SetRenderTarget(rt, g_aRTSet[iPass].apCopyRT[rt]));

          V(g_pEffect.BeginPass(iPass));

          V(pd3dDevice.DrawPrimitive(D3DPT_TRIANGLELIST, i*6, 2));
          V(g_pEffect.EndPass);
        end;

        V(g_pEffect._End);
      end;

      // Render the blob
      V(g_pEffect.SetTexture('g_tSourceBlob', g_pTexBlob));
      V(g_pEffect.SetTexture('g_tNormalBuffer', g_pTexGBuffer[2]));
      V(g_pEffect.SetTexture('g_tColorBuffer', g_pTexGBuffer[3]));

      if SUCCEEDED(g_pEffect._Begin(@nNumPasses, 0)) then
      begin
        for iPass:=0 to nNumPasses - 1 do
        begin
          for rt := 0 to g_nRtUsed - 1 do
            V(pd3dDevice.SetRenderTarget(rt, g_aRTSet[iPass].apBlendRT[rt]));

          V(g_pEffect.BeginPass(iPass));

          V(pd3dDevice.DrawPrimitive(D3DPT_TRIANGLELIST, i*6, 2));
          V(g_pEffect.EndPass);
        end;

        V(g_pEffect._End);
      end;
    end;


    // Restore initial device surfaces
    V(pd3dDevice.SetDepthStencilSurface(pSurfOldDepthStencil));

    for rt := 0 to g_nRtUsed - 1 do
      V(pd3dDevice.SetRenderTarget(rt, apSurfOldRenderTarget[rt]));

    // Light and composite blobs into backbuffer
    V(g_pEffect.SetTechnique('BlobLight'));

    V(g_pEffect._Begin(@nNumPasses, 0));

    for iPass:= 0 to nNumPasses - 1 do
    begin
      V(g_pEffect.BeginPass(iPass));

      for i:= 0 to NUM_BLOBS - 1 do
      begin
        V(g_pEffect.SetTexture('g_tSourceBlob', g_pTexGBuffer[0]));
        V(g_pEffect.SetTexture('g_tColorBuffer', g_pTexGBuffer[1]));
        V(g_pEffect.SetTexture('g_tEnvMap', g_pEnvMap));
        V(g_pEffect.CommitChanges);

        V(RenderFullScreenQuad(1.0));
      end;
      V(g_pEffect.EndPass);
    end;

    V(g_pEffect._End);

    RenderText;
    V(g_HUD.OnRender(fElapsedTime));

    V(pd3dDevice.EndScene);
  end;

  for rt := 0 to g_nRtUsed - 1 do
    SAFE_RELEASE(apSurfOldRenderTarget[rt]);
  SAFE_RELEASE(pSurfOldDepthStencil);

    
  for i:= 0 to 3 do SAFE_RELEASE(pGBufSurf[i]);
end;


//-----------------------------------------------------------------------------
// Name: RenderFullScreenQuad()
// Desc: Render a quad at the specified tranformed depth
//-----------------------------------------------------------------------------
function RenderFullScreenQuad(fDepth: Single): HRESULT;
var
  aVertices: array[0..3] of TScreenVertex;
  pd3dDevice: IDirect3DDevice9;
  pBackBufferSurfaceDesc: PD3DSurfaceDesc;
  i: Integer;
begin
  pd3dDevice := DXUTGetD3DDevice;
  pBackBufferSurfaceDesc := DXUTGetBackBufferSurfaceDesc;

  aVertices[0].pos := D3DXVector4(-0.5, -0.5, fDepth, fDepth);
  aVertices[1].pos := D3DXVector4(pBackBufferSurfaceDesc.Width - 0.5, -0.5, fDepth, fDepth);
  aVertices[2].pos := D3DXVector4(-0.5, pBackBufferSurfaceDesc.Height - 0.5, fDepth, fDepth);
  aVertices[3].pos := D3DXVector4(pBackBufferSurfaceDesc.Width - 0.5, pBackBufferSurfaceDesc.Height - 0.5, fDepth, fDepth);


  aVertices[0].tCurr := D3DXVector2(0.0, 0.0);
  aVertices[1].tCurr := D3DXVector2(1.0, 0.0);
  aVertices[2].tCurr := D3DXVector2(0.0, 1.0);
  aVertices[3].tCurr := D3DXVector2(1.0, 1.0);

  for i:= 0 to 3 do
  with aVertices[i] do
  begin
    tBack := aVertices[i].tCurr;
    tBack.x := tBack.x + (1.0/pBackBufferSurfaceDesc.Width);
    tBack.y := tBack.y + (1.0/pBackBufferSurfaceDesc.Height);
    fSize := 0.0;
  end;

  pd3dDevice.SetFVF(TScreenVertex_FVF);
  pd3dDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, aVertices, SizeOf(TScreenVertex));

  Result:= S_OK;
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
  // and then it calls pFont->DrawText( g_pSprite, strMsg, -1, &rc, DT_NOCLIP, g_clr );
  // If NULL is passed in as the sprite object, then it will work however the 
  // pFont->DrawText() will not be batched together.  Batching calls will improves performance.
  txtHelper:= CDXUTTextHelper.Create(g_pFont, g_pTextSprite, 15);

  // Output statistics
  txtHelper._Begin;
  txtHelper.SetInsertionPos(5, 5);
  txtHelper.SetForegroundColor(D3DXCOLOR(1.0, 1.0, 0.0, 1.0));
  txtHelper.DrawTextLine(DXUTGetFrameStats);
  txtHelper.DrawTextLine(DXUTGetDeviceStats);

  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
    
  // Draw help
  if g_bShowHelp then
  begin
    pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*6);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
    txtHelper.DrawTextLine('Controls (F1 to hide):');

    txtHelper.SetInsertionPos(40, pd3dsdBackBuffer.Height-15*5);
    txtHelper.DrawTextLine('Rotate model: Left mouse button'#10+
                           'Rotate camera: Right mouse button'#10+
                           'Zoom camera: Mouse wheel scroll'#10);
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
  pbNoFurtherProcessing := False;

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
  if Assigned(g_HUD) then
    pbNoFurtherProcessing := g_HUD.MsgProc(hWnd, uMsg, wParam, lParam);
  if pbNoFurtherProcessing then Exit;

  // Pass all remaining windows messages to camera so it can respond to user input
  if Assigned(g_Camera) then
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
      VK_F2: if DXUTIsTimePaused then DXUTPause(False, False);
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
  end;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has
// entered a lost state and before IDirect3DDevice9::Reset is called. Resources created
// in the OnResetDevice callback should be released here, which generally includes all
// D3DPOOL_DEFAULT resources. See the "Lost Devices" section of the documentation for
// information about lost devices.
//--------------------------------------------------------------------------------------
procedure OnLostDevice(pUserContext: Pointer); stdcall;
var
  i, p: Integer;
begin
  g_DialogResourceManager.OnLostDevice;
  g_SettingsDlg.OnLostDevice;

  if (g_pFont <> nil) then g_pFont.OnLostDevice;
  if (g_pEffect <> nil) then g_pEffect.OnLostDevice;

  SAFE_RELEASE(g_pTextSprite);
  SAFE_RELEASE(g_pBlobVB);
  SAFE_RELEASE(g_pTexScratch);
  SAFE_RELEASE(g_pTexBlob);
  SAFE_RELEASE(g_pEnvMap);

  for p := 0 to 1 do
    for i := 0 to 1 do
    begin
      SAFE_RELEASE(g_aRTSet[p].apCopyRT[i]);
      SAFE_RELEASE(g_aRTSet[p].apBlendRT[i]);
    end;

  for i:= 0 to 3 do SAFE_RELEASE(g_pTexGBuffer[i]);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has
// been destroyed, which generally happens as a result of application termination or
// windowed/full screen toggles. Resources created in the OnCreateDevice callback
// should be released here, which generally includes all D3DPOOL_MANAGED resources.
//--------------------------------------------------------------------------------------
procedure OnDestroyDevice(pUserContext: Pointer); stdcall;
begin
  g_DialogResourceManager.OnDestroyDevice;
  g_SettingsDlg.OnDestroyDevice;
  SAFE_RELEASE(g_pEffect);
  SAFE_RELEASE(g_pFont);
end;


procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera:= CModelViewerCamera.Create;
  g_HUD:= CDXUTDialog.Create;
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_HUD);
  FreeAndNil(g_Camera);
end;

end.

