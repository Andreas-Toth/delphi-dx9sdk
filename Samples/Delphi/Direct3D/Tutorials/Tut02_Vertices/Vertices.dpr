(*----------------------------------------------------------------------------*
 *  Direct3D tutorial from DirectX 9.0 SDK                                    *
 *  Delphi adaptation by Alexey Barkovoy (e-mail: directx@clootie.ru)         *
 *                                                                            *
 *  Latest version can be downloaded from:                                    *
 *     http://www.clootie.ru                                                  *
 *     http://sourceforge.net/projects/delphi-dx9sdk                          *
 *----------------------------------------------------------------------------*
 *  $Id: Vertices.dpr,v 1.6 2005/06/30 19:48:59 clootie Exp $
 *----------------------------------------------------------------------------*)
//-----------------------------------------------------------------------------
// File: Vertices.cpp
//
// Desc: In this tutorial, we are rendering some vertices. This introduces the
//       concept of the vertex buffer, a Direct3D object used to store
//       vertices. Vertices can be defined any way we want by defining a
//       custom structure and a custom FVF (flexible vertex format). In this
//       tutorial, we are using vertices that are transformed (meaning they
//       are already in 2D window coordinates) and lit (meaning we are not
//       using Direct3D lighting, but are supplying our own colors).
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//-----------------------------------------------------------------------------

{$APPTYPE GUI}
{$I DirectX.inc}

program Vertices;

uses
  Windows, Messages, Direct3D9;


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
    x, y, z, rhw: Single; // The transformed position for the vertex
    color: DWORD;         // The vertex color
  end;

const
  // Our custom FVF, which describes our custom vertex structure
  D3DFVF_CUSTOMVERTEX = (D3DFVF_XYZRHW or D3DFVF_DIFFUSE);


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

  // Device state would normally be set here

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: InitVB()
// Desc: Creates a vertex buffer and fills it with our vertices. The vertex
//       buffer is basically just a chuck of memory that holds vertices. After
//       creating it, we must Lock()/Unlock() it to fill it. For indices, D3D
//       also uses index buffers. The special thing about vertex and index
//       buffers is that they can be created in device memory, allowing some
//       cards to process them in hardware, resulting in a dramatic
//       performance gain.
//-----------------------------------------------------------------------------
function InitVB: HRESULT;
const
  // Initialize three vertices for rendering a triangle
  vertices: array[0..2] of TCustomVertex = (
    (x: 150.0; y:  50.0; z: 0.5; rhw: 1.0; color: $ffff0000), // x, y, z, rhw, color),
    (x: 250.0; y: 250.0; z: 0.5; rhw: 1.0; color: $ff00ff00),
    (x:  50.0; y: 250.0; z: 0.5; rhw: 1.0; color: $ff00ffff)
  );
var
  pVertices: Pointer;
begin
  Result:= E_FAIL;
  // Create the vertex buffer. Here we are allocating enough memory
  // (from the default pool) to hold all our 3 custom vertices. We also
  // specify the FVF, so the vertex buffer knows what data it contains.
  if FAILED(g_pd3dDevice.CreateVertexBuffer(3*SizeOf(TCustomVertex),
                                            0, D3DFVF_CUSTOMVERTEX,
                                            D3DPOOL_DEFAULT, g_pVB, nil))
  then Exit;

  // Now we fill the vertex buffer. To do this, we need to Lock() the VB to
  // gain access to the vertices. This mechanism is required becuase vertex
  // buffers may be in device memory.
  if FAILED(g_pVB.Lock(0, SizeOf(vertices), pVertices, 0))
  then Exit;

  CopyMemory(pVertices, @vertices, SizeOf(vertices));
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
// Name: Render()
// Desc: Draws the scene
//-----------------------------------------------------------------------------
procedure Render;
begin
  // Clear the backbuffer to a blue color
  g_pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET, D3DCOLOR_XRGB(0,0,255), 1.0, 0);

  // Begin the scene
  if (SUCCEEDED(g_pd3dDevice.BeginScene)) then
  begin
    // Draw the triangles in the vertex buffer. This is broken into a few
    // steps. We are passing the vertices down a "stream", so first we need
    // to specify the source of that stream, which is our vertex buffer. Then
    // we need to let D3D know what vertex shader to use. Full, custom vertex
    // shaders are an advanced topic, but in most cases the vertex shader is
    // just the FVF, so that D3D knows what type of vertices we are dealing
    // with. Finally, we call DrawPrimitive() which does the actual rendering
    // of our geometry (in this case, just one triangle).
    g_pd3dDevice.SetStreamSource(0, g_pVB, 0, SizeOf(TCustomVertex));
    g_pd3dDevice.SetFVF(D3DFVF_CUSTOMVERTEX);
    g_pd3dDevice.DrawPrimitive(D3DPT_TRIANGLELIST, 0, 1);

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
  hWindow := CreateWindow('D3D Tutorial', 'D3D Tutorial 01: CreateDevice',
                          WS_OVERLAPPEDWINDOW, 100, 100, 300, 300,
                          0, 0, wc.hInstance, nil);

  // Initialize Direct3D
  if SUCCEEDED(InitD3D(hWindow)) then
  begin
    // Create the vertex buffer
    if SUCCEEDED(InitVB) then
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
  ExitCode:= 0;
end.

