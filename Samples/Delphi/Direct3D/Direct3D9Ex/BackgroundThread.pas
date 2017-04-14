(*----------------------------------------------------------------------------*
 *  Direct3D sample from DirectX 9.0 SDK August 2006                          *
 *  Delphi adaptation by Alexey Barkovoy (e-mail: directx@clootie.ru)         *
 *                                                                            *
 *  Supported compilers: Delphi 5,6,7,9; FreePascal 2.0                       *
 *                                                                            *
 *  Latest version can be downloaded from:                                    *
 *     http://www.clootie.ru                                                  *
 *     http://sourceforge.net/projects/delphi-dx9sdk                          *
 *----------------------------------------------------------------------------*
 *  $Id: BackgroundThread.pas,v 1.3 2006/10/23 22:30:52 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: BackgroundThread.cpp
//
// Sample showing how to use D3D9Ex advanced features.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

unit BackgroundThread;

{$I DirectX.inc}

interface

uses
  Windows, Direct3D9, D3DX9, DXUTcore;

//-----------------------------------------------------------------------------
// structures
//-----------------------------------------------------------------------------
type
  TBackgroundVertex = record
    x, y, z: Single;      // The untransformed position for the vertex
    dwColor: DWORD;       // Color
  end;

const D3DFVF_BACKGROUNDVERTEX = (D3DFVF_XYZ or D3DFVF_DIFFUSE);

//--------------------------------------------------------------------------------------
// Function Prototypes and Externs
//--------------------------------------------------------------------------------------
function BackgroundThreadProc(lpParam: Pointer): DWORD; stdcall;
function CreateCube(const pDev: IDirect3DDevice9Ex): HRESULT;
function CreateSharedRenderTexture(const pDev: IDirect3DDevice9Ex): HRESULT;
procedure RenderBackground(const pDev: IDirect3DDevice9Ex);
procedure CleanupBackground;

//--------------------------------------------------------------------------------------
// Exported
//--------------------------------------------------------------------------------------
function CreateBackgroundThread(const pD3D9: IDirect3D9Ex): THandle;
procedure KillBackgroundThread; { g_bEndThread = true; }
function GetSharedTextureHandle: THandle; { return g_SharedHandle; }
function IncreaseCubeCount: Integer;
function DecreaseCubeCount: Integer;
function GetFPS: Single;


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_RTWidth: LongWord = 1024;
  g_RTHeight: LongWord = 1024;


implementation

uses
  D3D9ExUnit;


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_bEndThread: Boolean = False;
  g_pRenderTarget: IDirect3DTexture9;
  g_pSharedTexture: IDirect3DTexture9;
  g_pCubeVB: IDirect3DVertexBuffer9;
  g_pCubeIB: IDirect3DIndexBuffer9;
  g_SharedHandle: THandle = 0;
  g_CubeCubes: Integer = 3;
  g_BoxRad: Single = 30.0;
  g_CSCubes: TRTLCriticalSection;

  g_fBackLastFrameTime: Single = 0.000001;
  g_liBackLastTimerUpdate: Int64 = 0;
  g_liBackTimerFrequency: Int64 = 0;


// main background thread proc
function BackgroundThreadProc(lpParam: Pointer): DWORD; stdcall;
var
  pDevBackground: IDirect3DDevice9Ex;
  pD3D9: IDirect3D9Ex;
  d3dpp: TD3DPresentParameters;
begin
  // Create a critsec
  InitializeCriticalSection(g_CSCubes);

  // Create a d3d9V device
  pD3D9 := IDirect3D9Ex(lpParam);

  FillChar(d3dpp, SizeOf(d3dpp), 0);

  d3dpp.Windowed := True;
  d3dpp.SwapEffect := D3DSWAPEFFECT_DISCARD;
  d3dpp.BackBufferFormat := D3DFMT_UNKNOWN;
  d3dpp.PresentationInterval := D3DPRESENT_INTERVAL_DEFAULT;

  if FAILED(CreateD3D9VDevice(pD3D9, pDevBackground, d3dpp, 0)) then
  begin
    Result:= 1;
    Exit;
  end;
  if FAILED(CreateCube(pDevBackground)) then
  begin
    Result:= 2;
    Exit;
  end;
  if FAILED(CreateSharedRenderTexture(pDevBackground)) then
  begin
    Result:= 3;
    Exit;
  end;

  // Set the GPU thread priority
  pDevBackground.SetGPUThreadPriority(-7);
  SetThreadPriority(GetCurrentThread, THREAD_PRIORITY_LOWEST);

  // Get Timer Frequency
  QueryPerformanceFrequency(g_liBackTimerFrequency);
  QueryPerformanceCounter(g_liBackLastTimerUpdate);

  while (not g_bEndThread) do
  begin
    RenderBackground(pDevBackground);
    // Uncomment next line to throttle rendering to no more then the refresh rate of the monitor.
    // pDevBackground->WaitForVBlank(0);
  end;

  // Cleanup
  DeleteCriticalSection(g_CSCubes);
  CleanupBackground;
  pDevBackground := nil;

  Result:= 0;
end;

function CreateBackgroundThread(const pD3D9: IDirect3D9Ex): THandle;
var
  dwThreadID: DWORD;
  hBackgroundThread: THandle;
begin
  // create the thread
  dwThreadID := 0;
  hBackgroundThread := CreateThread(nil,
                                    0,
                                    @BackgroundThreadProc,
                                    Pointer(pD3D9),
                                    CREATE_SUSPENDED,
                                    dwThreadID);

  if (hBackgroundThread <> 0) then
  begin
    // set the priority

    // resume the thread
    ResumeThread(hBackgroundThread);
  end;

  Result:= hBackgroundThread;
end;


const
  vertices: array[0..7] of TBackgroundVertex = (
    (x: -1.0; y:  1.0; z: -1.0; dwColor: $000066),
    (x:  1.0; y:  1.0; z: -1.0; dwColor: $006600),
    (x:  1.0; y:  1.0; z:  1.0; dwColor: $006666),
    (x: -1.0; y:  1.0; z:  1.0; dwColor: $660000),
    (x: -1.0; y: -1.0; z: -1.0; dwColor: $660066),
    (x:  1.0; y: -1.0; z: -1.0; dwColor: $666600),
    (x:  1.0; y: -1.0; z:  1.0; dwColor: $666666),
    (x: -1.0; y: -1.0; z:  1.0; dwColor: $000000)
  );

  indices: array[0..12*3-1] of Word =
  (
    3,1,0,
    2,1,3,

    0,5,4,
    1,5,0,

    3,4,7,
    0,4,3,

    1,6,5,
    2,6,1,

    2,7,6,
    3,7,2,

    6,4,5,
    7,4,6
  );

function CreateCube(const pDev: IDirect3DDevice9Ex): HRESULT;
var
  pVertices: Pointer;
  pIndices: Pointer;
begin
  Result:= E_FAIL;

  // create the vb
  if FAILED(pDev.CreateVertexBuffer(8*SizeOf(TBackgroundVertex),
                                    0,
                                    D3DFVF_BACKGROUNDVERTEX,
                                    D3DPOOL_DEFAULT,
                                    g_pCubeVB,
                                    nil))
  then Exit;

  if FAILED(g_pCubeVB.Lock(0, SizeOf(vertices), pVertices, 0)) then Exit;
  CopyMemory(pVertices, @vertices, SizeOf(vertices));
  g_pCubeVB.Unlock;


  if FAILED(pDev.CreateIndexBuffer(36*SizeOf(WORD),
                                   0,
                                   D3DFMT_INDEX16,
                                   D3DPOOL_DEFAULT,
                                   g_pCubeIB,
                                   nil))
  then Exit;

  if FAILED(g_pCubeIB.Lock(0, SizeOf(indices), pIndices, 0)) then Exit;
  CopyMemory(pIndices, @indices, SizeOf(indices));
  g_pCubeIB.Unlock;

  Result:= S_OK;
end;


function CreateSharedRenderTexture(const pDev: IDirect3DDevice9Ex): HRESULT;
var
  pRTSurf: IDirect3DSurface9;
  vp: TD3DViewport9;
begin
  Result:= E_FAIL;

  if FAILED(pDev.CreateTexture(g_RTWidth,
                               g_RTHeight,
                               1,
                               D3DUSAGE_RENDERTARGET,
                               D3DFMT_X8R8G8B8,
                               D3DPOOL_DEFAULT,
                               g_pSharedTexture,
                               @g_SharedHandle))
  then Exit;

  if (g_SharedHandle = 0) then Exit;

  // create a render target
  if FAILED(pDev.CreateTexture(g_RTWidth,
                               g_RTHeight,
                               1,
                               D3DUSAGE_RENDERTARGET,
                               D3DFMT_X8R8G8B8,
                               D3DPOOL_DEFAULT,
                               g_pRenderTarget,
                               nil))
  then Exit;

  if FAILED(g_pRenderTarget.GetSurfaceLevel(0, pRTSurf)) then Exit;

  if FAILED(pDev.SetRenderTarget(0, pRTSurf)) then Exit;

  pRTSurf := nil;

  // viewport
  vp.X := 0;
  vp.Y := 0;
  vp.Width := g_RTWidth;
  vp.Height := g_RTHeight;
  vp.MinZ := 0.0;
  vp.MaxZ := 1.0;
  pDev.SetViewport(vp);

  Result:= S_OK;
end;


var
  fRot: Single = 0.0;
   
procedure RenderBackground(const pDev: IDirect3DDevice9Ex);
var
  mWorld: TD3DXMatrix;
  mView: TD3DXMatrix;
  mProj: TD3DXMatrix;
  eye, at, up: TD3DXVector3;
  //hr: HRESULT;
  fStep, fStart, fStop: Single;
  x, y, z: Single;
  mPos: TD3DXMatrix;
  pSurfSrc: IDirect3DSurface9;
  pSurfDest: IDirect3DSurface9;
  liCurrentTime: Int64;
begin
  fRot := fRot + g_fBackLastFrameTime*60.0*(D3DX_PI/180.0);

  // setup the matrices
  D3DXMatrixRotationY(mWorld, fRot);

  eye := D3DXVector3(0, 2.0, g_BoxRad*3.5);
  at := D3DXVector3Zero;
  up := D3DXVector3(0, 1, 0);
  D3DXMatrixLookAtLH(mView, eye, at, up);
  D3DXMatrixPerspectiveFovLH(mProj, D3DX_PI/4.0, 1.0, 0.1, 1000.0);

  pDev.SetTransform(D3DTS_VIEW, mView);
  pDev.SetTransform(D3DTS_PROJECTION, mProj);

  // clear
  // hr := S_OK;
  pDev.Clear(0, nil, D3DCLEAR_TARGET, D3DCOLOR_XRGB(0,0,255), 1.0, 0);

  // Begin the scene
  if SUCCEEDED(pDev.BeginScene) then
  begin
    // set the texture stage states
    pDev.SetTextureStageState(0, D3DTSS_COLOROP, D3DTOP_SELECTARG1);
    pDev.SetTextureStageState(0, D3DTSS_COLORARG1, D3DTA_DIFFUSE);

    // disable lighting
    pDev.SetRenderState(D3DRS_LIGHTING, iFalse);

    // stream sources
    pDev.SetStreamSource(0, g_pCubeVB, 0, SizeOf(TBackgroundVertex));
    pDev.SetIndices(g_pCubeIB);
    pDev.SetFVF(D3DFVF_BACKGROUNDVERTEX);

    // draw
    if (g_CubeCubes <> 0) then
      fStep := (g_BoxRad*2) / g_CubeCubes
    else
      fStep := 0;
    fStart := -g_BoxRad + fStep/2.0;
    fStop := fStart + fStep*g_CubeCubes;

    EnterCriticalSection(g_CSCubes);

    z := fStart;
    // for float z:=fStart; z<fStop; z:= _ +fStep )
    while (z<fStop) do
    begin
      y := fStart;
      // for( float y=fStart; y<fStop; y+=fStep )
      while (y<fStop) do
      begin
        x := fStart;
        // for( float x=fStart; x<fStop; x+=fStep )
        while (x<fStop) do
        begin
          D3DXMatrixTranslation(mPos, x,y,z);
          // mPos := mWorld*mPos;
          D3DXMatrixMultiply(mPos, mWorld, mPos);
          pDev.SetTransform(D3DTS_WORLD, mPos);

          {hr := }pDev.DrawIndexedPrimitive(D3DPT_TRIANGLELIST, 0, 0, 8, 0, 12);
          x := x + fStep;
        end;
        y:= y + fStep;
      end;
      z:= z + fStep;
    end;
    LeaveCriticalSection(g_CSCubes);

    // End the scene
    pDev.EndScene;
  end;

  // Stretch rect to our shared texture
  g_pRenderTarget.GetSurfaceLevel(0, pSurfSrc);
  g_pSharedTexture.GetSurfaceLevel(0, pSurfDest);
  {hr := }pDev.StretchRect(pSurfSrc, nil, pSurfDest, nil, D3DTEXF_POINT);
  SAFE_RELEASE(pSurfSrc);
  SAFE_RELEASE(pSurfDest);

  // Get the time
  QueryPerformanceCounter(liCurrentTime);
  g_fBackLastFrameTime := (liCurrentTime - g_liBackLastTimerUpdate) / g_liBackTimerFrequency;
  g_liBackLastTimerUpdate := liCurrentTime;
end;


procedure CleanupBackground;
begin
  SAFE_RELEASE(g_pRenderTarget);
  SAFE_RELEASE(g_pSharedTexture);
  SAFE_RELEASE(g_pCubeVB);
  SAFE_RELEASE(g_pCubeIB);
end;


procedure KillBackgroundThread;
begin
  g_bEndThread := True;
end;


function GetSharedTextureHandle: THandle;
begin
  Result:= g_SharedHandle;
end;


function IncreaseCubeCount: Integer;
begin
  EnterCriticalSection(g_CSCubes);

  Inc(g_CubeCubes);
  if (g_CubeCubes > 100) then g_CubeCubes := 100;

  LeaveCriticalSection(g_CSCubes);

  Result:= g_CubeCubes;
end;


function DecreaseCubeCount: Integer;
begin
  EnterCriticalSection(g_CSCubes);

  Dec(g_CubeCubes);
  if (g_CubeCubes < 0) then g_CubeCubes := 0;

  LeaveCriticalSection(g_CSCubes);

  Result:= g_CubeCubes;
end;


function GetFPS: Single;
begin
  Result:= 1.0 / g_fBackLastFrameTime;
end;


end.
