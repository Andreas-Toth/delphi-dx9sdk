(*----------------------------------------------------------------------------*
 *  Direct3D tutorial from DirectX 9.0 SDK                                    *
 *  Delphi adaptation by Alexey Barkovoy (e-mail: directx@clootie.ru)         *
 *                                                                            *
 *  Latest version can be downloaded from:                                    *
 *     http://www.clootie.ru                                                  *
 *     http://sourceforge.net/projects/delphi-dx9sdk                          *
 *----------------------------------------------------------------------------*
 *  $Id: Lights.dpr,v 1.7 2005/06/30 19:49:00 clootie Exp $
 *----------------------------------------------------------------------------*)
//-----------------------------------------------------------------------------
// File: Lights.cpp
//
// Desc: Rendering 3D geometry is much more interesting when dynamic lighting
//       is added to the scene. To use lighting in D3D, you must create one or
//       lights, setup a material, and make sure your geometry contains surface
//       normals. Lights may have a position, a color, and be of a certain type
//       such as directional (light comes from one direction), point (light
//       comes from a specific x,y,z coordinate and radiates in all directions)
//       or spotlight. Materials describe the surface of your geometry,
//       specifically, how it gets lit (diffuse color, ambient color, etc.).
//       Surface normals are part of a vertex, and are needed for the D3D's
//       internal lighting calculations.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//-----------------------------------------------------------------------------

{$APPTYPE GUI}
{$I DirectX.inc}

program Lights;

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

// A structure for our custom vertex type. We added a normal, and omitted the
// color (which is provided by the material)
type
  PCustomVertex = ^TCustomVertex;
  TCustomVertex = packed record
    position: TD3DVector; // The 3D position for the vertex
    normal: TD3DVector;   // The surface normal for the vertex
  end;

  PCustomVertexArray = ^TCustomVertexArray;
  TCustomVertexArray = array [0..MaxInt div SizeOf(TCustomVertex)-1] of TCustomVertex;

const
  // Our custom FVF, which describes our custom vertex structure
  D3DFVF_CUSTOMVERTEX = (D3DFVF_XYZ or D3DFVF_NORMAL);


  
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

  // Set up the structure used to create the D3DDevice. Since we are now
  // using more complex geometry, we will create a device with a zbuffer.
  FillChar(d3dpp, SizeOf(d3dpp), 0);
  d3dpp.Windowed := True;
  d3dpp.SwapEffect := D3DSWAPEFFECT_DISCARD;
  d3dpp.BackBufferFormat := D3DFMT_UNKNOWN;
  d3dpp.EnableAutoDepthStencil := True;
  d3dpp.AutoDepthStencilFormat := D3DFMT_D16;

  // Create the D3DDevice
  Result:= g_pD3D.CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hWnd,
                               D3DCREATE_SOFTWARE_VERTEXPROCESSING,
                               @d3dpp, g_pd3dDevice);
  if FAILED(Result) then
  begin
    Result:= E_FAIL;
    Exit;
  end;

  // Turn off culling
  g_pd3dDevice.SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);

  // Turn on the zbuffer
  g_pd3dDevice.SetRenderState(D3DRS_ZENABLE, iTrue);

  Result:= S_OK;
end;



//-----------------------------------------------------------------------------
// Name: InitGeometry()
// Desc: Creates the scene geometry
//-----------------------------------------------------------------------------
function InitGeometry: HRESULT;
var
  i: DWORD;
  theta: Single;
  pVertices: PCustomVertexArray;
begin
  Result:= E_FAIL;

  // Create the vertex buffer.
  if FAILED(g_pd3dDevice.CreateVertexBuffer(50*2*SizeOf(TCustomVertex),
                                            0, D3DFVF_CUSTOMVERTEX,
                                            D3DPOOL_DEFAULT, g_pVB, nil))
  then Exit;

  // Fill the vertex buffer. We are algorithmically generating a cylinder
  // here, including the normals, which are used for lighting.
  if FAILED(g_pVB.Lock(0, 0, Pointer(pVertices), 0))
  then Exit;

  for i:= 0 to 49 do
  begin
    theta := (2*D3DX_PI*i)/(50-1);
    pVertices[2*i+0].position := D3DXVector3(Sin(theta),-1.0, Cos(theta));
    pVertices[2*i+0].normal   := D3DXVector3(Sin(theta), 0.0, Cos(theta));
    pVertices[2*i+1].position := D3DXVector3(Sin(theta), 1.0, Cos(theta));
    pVertices[2*i+1].normal   := D3DXVector3(Sin(theta), 0.0, Cos(theta));
  end;
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
  matWorld, matView, matProj: TD3DMatrix;
  vEyePt, vLookatPt, vUpVec: TD3DVector;
begin
  // Set up world matrix
  D3DXMatrixIdentity(matWorld);
  D3DXMatrixRotationX(matWorld, timeGetTime/500.0);
  g_pd3dDevice.SetTransform(D3DTS_WORLD, matWorld);

  // Set up our view matrix. A view matrix can be defined given an eye point,
  // a point to lookat, and a direction for which way is up. Here, we set the
  // eye five units back along the z-axis and up three units, look at the
  // origin, and define "up" to be in the y-direction.
  vEyePt:=    D3DXVector3(0.0, 3.0,-5.0);
  vLookatPt:= D3DXVector3Zero;
  vUpVec:=    D3DXVector3(0.0, 1.0, 0.0);
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
// Name: SetupLights()
// Desc: Sets up the lights and materials for the scene.
//-----------------------------------------------------------------------------
procedure SetupLights;
var
  mtrl: TD3DMaterial9;
  vecDir: TD3DXVector3;
  light: TD3DLight9;
begin
  // Set up a material. The material here just has the diffuse and ambient
  // colors set to yellow. Note that only one material can be used at a time.
  ZeroMemory(@mtrl, SizeOf(TD3DMaterial9));
  mtrl.Diffuse.r := 1.0; mtrl.Ambient.r := 1.0;
  mtrl.Diffuse.g := 1.0; mtrl.Ambient.g := 1.0;
  mtrl.Diffuse.b := 0.0; mtrl.Ambient.b := 0.0;
  mtrl.Diffuse.a := 1.0; mtrl.Ambient.a := 1.0;
  g_pd3dDevice.SetMaterial(mtrl);

  // Set up a white, directional light, with an oscillating direction.
  // Note that many lights may be active at a time (but each one slows down
  // the rendering of our scene). However, here we are just using one. Also,
  // we need to set the D3DRS_LIGHTING renderstate to enable lighting
  ZeroMemory(@light, SizeOf(TD3DLight9));
  light._Type      := D3DLIGHT_DIRECTIONAL;
  light.Diffuse.r  := 1.0;
  light.Diffuse.g  := 1.0;
  light.Diffuse.b  := 1.0;
  vecDir:= D3DXVector3(Cos(timeGetTime/350.0),
                       1.0,
                       Sin(timeGetTime/350.0) );
  D3DXVec3Normalize(light.Direction, vecDir);
  light.Range := 1000.0;
  g_pd3dDevice.SetLight(0, light);
  g_pd3dDevice.LightEnable(0, True);
  g_pd3dDevice.SetRenderState(D3DRS_LIGHTING, iTrue);

  // Finally, turn on some ambient light.
  g_pd3dDevice.SetRenderState(D3DRS_AMBIENT, $00202020);
end;



//-----------------------------------------------------------------------------
// Name: Render()
// Desc: Draws the scene
//-----------------------------------------------------------------------------
procedure Render;
begin
  // Clear the backbuffer and the zbuffer
  g_pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER,
                     D3DCOLOR_XRGB(0,0,255), 1.0, 0);

  // Begin the scene
  if SUCCEEDED(g_pd3dDevice.BeginScene) then
  begin
    // Setup the lights and materials
    SetupLights;

    // Setup the world, view, and projection matrices
    SetupMatrices;

    // Render the vertex buffer contents
    g_pd3dDevice.SetStreamSource(0, g_pVB, 0, SizeOf(TCustomVertex));
    g_pd3dDevice.SetFVF(D3DFVF_CUSTOMVERTEX);
    g_pd3dDevice.DrawPrimitive(D3DPT_TRIANGLESTRIP, 0, 2*50-2);

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
  hWindow := CreateWindow('D3D Tutorial', 'D3D Tutorial 04: Lights',
                          WS_OVERLAPPEDWINDOW, 100, 100, 300, 300,
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

