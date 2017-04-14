(*----------------------------------------------------------------------------*
 *  Direct3D tutorial from DirectX 9.0 SDK                                    *
 *  Delphi adaptation by Alexey Barkovoy (e-mail: directx@clootie.ru)         *
 *                                                                            *
 *  Latest version can be downloaded from:                                    *
 *     http://www.clootie.ru                                                  *
 *     http://sourceforge.net/projects/delphi-dx9sdk                          *
 *----------------------------------------------------------------------------*
 *  $Id: CreateDevice.dpr,v 1.6 2005/06/30 19:48:59 clootie Exp $
 *----------------------------------------------------------------------------*)
//-----------------------------------------------------------------------------
// File: CreateDevice.cpp
//
// Desc: This is the first tutorial for using Direct3D. In this tutorial, all
//       we are doing is creating a Direct3D device and using it to clear the
//       window.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//-----------------------------------------------------------------------------

{$APPTYPE GUI}
{$I DirectX.inc}

program CreateDevice;

uses
  Windows, Messages, Direct3D9;


//-----------------------------------------------------------------------------
// Global variables
//-----------------------------------------------------------------------------
var
  g_pD3D: IDirect3D9 = nil; // Used to create the D3DDevice
  g_pd3dDevice: IDirect3DDevice9 = nil; // Our rendering device


//-----------------------------------------------------------------------------
// Name: InitD3D()
// Desc: Initializes Direct3D
//-----------------------------------------------------------------------------
function InitD3D(hWnd: HWND): HRESULT;
var
  d3dpp: TD3DPresentParameters;
begin
  Result:= E_FAIL;

  // Create the D3D object, which is needed to create the D3DDevice.
  g_pD3D := Direct3DCreate9(D3D_SDK_VERSION);
  if (g_pD3D = nil) then Exit;

  // Set up the structure used to create the D3DDevice. Most parameters are
  // zeroed out. We set Windowed to TRUE, since we want to do D3D in a
  // window, and then set the SwapEffect to "discard", which is the most
  // efficient method of presenting the back buffer to the display.  And
  // we request a back buffer format that matches the current desktop display
  // format.
  FillChar(d3dpp, SizeOf(d3dpp), 0);
  d3dpp.Windowed := True;
  d3dpp.SwapEffect := D3DSWAPEFFECT_DISCARD;
  d3dpp.BackBufferFormat := D3DFMT_UNKNOWN;

  // Create the Direct3D device. Here we are using the default adapter (most
  // systems only have one, unless they have multiple graphics hardware cards
  // installed) and requesting the HAL (which is saying we want the hardware
  // device rather than a software one). Software vertex processing is
  // specified since we know it will work on all cards. On cards that support
  // hardware vertex processing, though, we would see a big performance gain
  // by specifying hardware vertex processing.
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
// Name: Cleanup()
// Desc: Releases all previously initialized objects
//-----------------------------------------------------------------------------
procedure Cleanup;
begin
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
  if (g_pd3dDevice = nil) then Exit;

  // Clear the backbuffer to a blue color
  g_pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET, D3DCOLOR_XRGB(0,0,255), 1.0, 0);

  // Begin the scene
  if (SUCCEEDED(g_pd3dDevice.BeginScene)) then
  begin
    // Rendering of scene objects can happen here

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

    WM_PAINT:
    begin
      Render;
      ValidateRect(hWnd, nil);
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
    lpfnWndProc: nil;
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
  wc.lpfnWndProc:= @MsgProc;
  wc.hInstance:= GetModuleHandle(nil);
  RegisterClassEx(wc);

  // Create the application's window
  hWindow := CreateWindow('D3D Tutorial', 'D3D Tutorial 01: CreateDevice',
                          WS_OVERLAPPEDWINDOW, 100, 100, 300, 300,
                          0, 0, wc.hInstance, nil);

  // Initialize Direct3D
  if SUCCEEDED(InitD3D(hWindow)) then
  begin
    // Show the window
    ShowWindow(hWindow, SW_SHOWDEFAULT);
    UpdateWindow(hWindow);

    // Enter the message loop
    while GetMessage(msg, 0, 0, 0) do
    begin
      TranslateMessage(msg);
      DispatchMessage(msg);
    end;
  end;

  UnregisterClass('D3D Tutorial', wc.hInstance);
//  Result:= 0;
end.

