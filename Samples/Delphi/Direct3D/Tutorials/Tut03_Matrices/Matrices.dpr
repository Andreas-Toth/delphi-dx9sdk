(*----------------------------------------------------------------------------*
 *  Direct3D tutorial from DirectX 9.0 SDK                                    *
 *  Delphi adaptation by Alexey Barkovoy (e-mail: directx@clootie.ru)         *
 *                                                                            *
 *  Latest version can be downloaded from:                                    *
 *     http://www.clootie.ru                                                  *
 *     http://sourceforge.net/projects/delphi-dx9sdk                          *
 *----------------------------------------------------------------------------*
 *  $Id: Matrices.dpr,v 1.6 2005/06/30 19:49:00 clootie Exp $
 *----------------------------------------------------------------------------*)
//-----------------------------------------------------------------------------
// File: Matrices.cpp
//
// Desc: Now that we know how to create a device and render some 2D vertices,
//       this tutorial goes the next step and renders 3D geometry. To deal with
//       3D geometry we need to introduce the use of 4x4 matrices to transform
//       the geometry with translations, rotations, scaling, and setting up our
//       camera.
//
//       Geometry is defined in model space. We can move it (translation),
//       rotate it (rotation), or stretch it (scaling) using a world transform.
//       The geometry is then said to be in world space. Next, we need to
//       position the camera, or eye point, somewhere to look at the geometry.
//       Another transform, via the view matrix, is used, to position and
//       rotate our view. With the geometry then in view space, our last
//       transform is the projection transform, which "projects" the 3D scene
//       into our 2D viewport.
//
//       Note that in this tutorial, we are introducing the use of D3DX, which
//       is a set of helper utilities for D3D. In this case, we are using some
//       of D3DX's useful matrix initialization functions. To use D3DX, simply
//       include <d3dx9.h> and link with d3dx9.lib.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//-----------------------------------------------------------------------------

{$APPTYPE GUI}
{$I DirectX.inc}

program Matrices;

uses
  Windows,
  Messages,
  MMSystem,
  Direct3D9,
  D3DX9;

//-----------------------------------------------------------------------------
// Global variables
//-----------------------------------------------------------------------------
var
  g_pD3D: IDirect3D9 = nil; // Used to create the D3DDevice
  g_pd3dDevice: IDirect3DDevice9 = nil; // Our rendering device
  g_pVB: IDirect3DVertexBuffer9 = nil; // Buffer to hold vertices

// A structure for our custom vertex type
type
  TCustomVertex = packed record
    x, y, z: Single;      // The untransformed, 3D position for the vertex
    color: DWORD;         // The vertex color
  end;

const
  // Our custom FVF, which describes our custom vertex structure
  D3DFVF_CUSTOMVERTEX = (D3DFVF_XYZ or D3DFVF_DIFFUSE);


//-----------------------------------------------------------------------------
// Name: InitD3D()
// Desc: Initializes Direct3D
//-----------------------------------------------------------------------------
function InitD3D(hWnd: HWND): HRESULT;
var
  d3dpp: TD3DPresentParameters;
begin
  Result:= E_FAIL;

  // Create the D3D object.
  g_pD3D := Direct3DCreate9(D3D_SDK_VERSION);
  if (g_pD3D = nil) then Exit;

  // Set up the structure used to create the D3DDevice
  FillChar(d3dpp, SizeOf(d3dpp), 0);
  d3dpp.Windowed := True;
  d3dpp.SwapEffect := D3DSWAPEFFECT_DISCARD;
  d3dpp.BackBufferFormat := D3DFMT_UNKNOWN;

  // Create the D3DDevice
  Result:= g_pD3D.CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hWnd,
                               D3DCREATE_SOFTWARE_VERTEXPROCESSING,
                               @d3dpp, g_pd3dDevice);
  if FAILED(Result) then
  begin
    Result:= E_FAIL;
    Exit;
  end;

  // Turn off culling, so we see the front and back of the triangle
  g_pd3dDevice.SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);

  // Turn off D3D lighting, since we are providing our own vertex colors
  g_pd3dDevice.SetRenderState(D3DRS_LIGHTING, iFalse);

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: InitGeometry()
// Desc: Creates the scene geometry
//-----------------------------------------------------------------------------
function InitGeometry: HRESULT;
const
  // Initialize three vertices for rendering a triangle
  g_Vertices: array[0..2] of TCustomVertex = (
    (x: -1.0; y: -1.0; z: 0.0; color: $ffff0000),
    (x:  1.0; y: -1.0; z: 0.0; color: $ff0000ff),
    (x:  0.0; y:  1.0; z: 0.0; color: $ffffffff)
  );
var
  pVertices: Pointer;
begin
  Result:= E_FAIL;
  
  // Create the vertex buffer.
  if FAILED(g_pd3dDevice.CreateVertexBuffer(3*SizeOf(TCustomVertex),
                                            0, D3DFVF_CUSTOMVERTEX,
                                            D3DPOOL_DEFAULT, g_pVB, nil))
  then Exit;

  // Now we fill the vertex buffer. To do this, we need to Lock() the VB to
  // gain access to the vertices. This mechanism is required becuase vertex
  // buffers may be in device memory.
  if FAILED(g_pVB.Lock(0, SizeOf(g_Vertices), pVertices, 0))
  then Exit;

  CopyMemory(pVertices, @g_Vertices, SizeOf(g_Vertices));
  g_pVB.Unlock;

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: Cleanup()
// Desc: Releases all previously initialized objects
//-----------------------------------------------------------------------------
procedure Cleanup;
begin
  if (g_pVB <> nil) then
    {$IFDEF TMT}
    g_pVB.Release;
    {$ELSE}
    g_pVB:= nil;
    {$ENDIF}

  if (g_pd3dDevice <> nil) then
    {$IFDEF TMT}
    g_pd3dDevice.Release;
    {$ELSE}
    g_pd3dDevice:= nil;
    {$ENDIF}

  if (g_pD3D <> nil) then
    {$IFDEF TMT}
    g_pD3D.Release;
    {$ELSE}
    g_pD3D:= nil;
    {$ENDIF}
end;


//-----------------------------------------------------------------------------
// Name: SetupMatrices()
// Desc: Sets up the world, view, and projection transform matrices.
//-----------------------------------------------------------------------------
procedure SetupMatrices;
var
  matWorld: TD3DMatrix;
  iTime: LongWord;
  fAngle: Single;

  vEyePt, vLookatPt, vUpVec: TD3DVector;
  matView: TD3DMatrix;
  matProj: TD3DMatrix;
begin
  // For our world matrix, we will just rotate the object about the y-axis.

  // Set up the rotation matrix to generate 1 full rotation (2*PI radians)
  // every 1000 ms. To avoid the loss of precision inherent in very high
  // floating point numbers, the system time is modulated by the rotation
  // period before conversion to a radian angle.
  iTime := timeGetTime mod 1000;
  fAngle := iTime * (2.0 * D3DX_PI) / 1000.0;
  D3DXMatrixRotationY(matWorld, fAngle);
  g_pd3dDevice.SetTransform(D3DTS_WORLD, matWorld);

  // Set up our view matrix. A view matrix can be defined given an eye point,
  // a point to lookat, and a direction for which way is up. Here, we set the
  // eye five units back along the z-axis and up three units, look at the
  // origin, and define "up" to be in the y-direction.
  vEyePt:= D3DXVector3(0.0, 3.0,-5.0);
  vLookatPt:= D3DXVector3(0.0, 0.0, 0.0);
  vUpVec:= D3DXVector3(0.0, 1.0, 0.0);
  D3DXMatrixLookAtLH(matView, vEyePt, vLookatPt, vUpVec);
  g_pd3dDevice.SetTransform(D3DTS_VIEW, matView);

  // For the projection matrix, we set up a perspective transform (which
  // transforms geometry from 3D view space to 2D viewport space, with
  // a perspective divide making objects smaller in the distance). To build
  // a perpsective transform, we need the field of view (1/4 pi is common),
  // the aspect ratio, and the near and far clipping planes (which define at
  // what distances geometry should be no longer be rendered).
  D3DXMatrixPerspectiveFovLH(matProj, D3DX_PI/4, 1.0, 1.0, 100.0);
  g_pd3dDevice.SetTransform(D3DTS_PROJECTION, matProj);
end;



//-----------------------------------------------------------------------------
// Name: Render()
// Desc: Draws the scene
//-----------------------------------------------------------------------------
procedure Render;
begin
  // Clear the backbuffer to a black color
  g_pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET, D3DCOLOR_XRGB(0,0,0), 1.0, 0);

  // Begin the scene
  if (SUCCEEDED(g_pd3dDevice.BeginScene)) then
  begin
    // Setup the world, view, and projection matrices
    SetupMatrices;

    // Render the vertex buffer contents
    g_pd3dDevice.SetStreamSource(0, g_pVB, 0, SizeOf(TCustomVertex));
    g_pd3dDevice.SetFVF(D3DFVF_CUSTOMVERTEX);
    g_pd3dDevice.DrawPrimitive(D3DPT_TRIANGLESTRIP, 0, 1 );

    // End the scene
    g_pd3dDevice.EndScene;
  end;

  // Present the backbuffer contents to the display
  g_pd3dDevice.Present(nil, nil, 0, nil);
end;




//-----------------------------------------------------------------------------
// Name: MsgProc()
// Desc: The window's message handler
//-----------------------------------------------------------------------------
function MsgProc(hWnd: HWND; uMsg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
begin
  case uMsg of
    WM_DESTROY:
    begin
      Cleanup;
      PostQuitMessage(0);
      Result:= 0;
      Exit;
    end;
  end;

  Result:= DefWindowProc(hWnd, uMsg, wParam, lParam);
end;




//-----------------------------------------------------------------------------
// Name: WinMain()
// Desc: The application's entry point
//-----------------------------------------------------------------------------
// INT WINAPI WinMain( HINSTANCE hInst, HINSTANCE, LPSTR, INT )
{$IFDEF TMT}
const
{$ELSE}
var
{$ENDIF}
  wc: TWndClassEx = (
    cbSize: SizeOf(TWndClassEx);
    style: CS_CLASSDC;
    {$IFDEF FPC}
    lpfnWndProc: MsgProc;
    {$ELSE}
    lpfnWndProc: @MsgProc;
    {$ENDIF}
    cbClsExtra: 0;
    cbWndExtra: 0;
    hInstance: 0; // - filled later
    hIcon: 0;
    hCursor: 0;
    hbrBackground: 0;
    lpszMenuName: nil;
    lpszClassName: 'D3D Tutorial';
    hIconSm: 0);
var
  hWindow: HWND;
  msg: TMsg;
begin
  // Register the window class
  wc.hInstance:= GetModuleHandle(nil);
  RegisterClassEx(wc);

  // Create the application's window
  hWindow := CreateWindow('D3D Tutorial', 'D3D Tutorial 03: Matrices',
                          WS_OVERLAPPEDWINDOW, 100, 100, 256, 256,
                          0, 0, wc.hInstance, nil);

  // Initialize Direct3D
  if SUCCEEDED(InitD3D(hWindow)) then
  begin
    // Create the scene geometry
    if SUCCEEDED(InitGeometry) then 
    begin
      // Show the window
      ShowWindow(hWindow, SW_SHOWDEFAULT);
      UpdateWindow(hWindow);

      // Enter the message loop
      FillChar(msg, SizeOf(msg), 0);
      while (msg.message <> WM_QUIT) do
      begin
        if PeekMessage(msg, 0, 0, 0, PM_REMOVE) then
        begin
          TranslateMessage(msg);
          DispatchMessage(msg);
        end else
          Render;
      end;
    end;
  end;

  UnregisterClass('D3D Tutorial', wc.hInstance);
end.

