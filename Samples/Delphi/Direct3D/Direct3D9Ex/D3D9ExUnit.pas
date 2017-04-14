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
 *  $Id: D3D9ExUnit.pas,v 1.5 2006/10/23 22:30:52 clootie Exp $
 *----------------------------------------------------------------------------*)
//--------------------------------------------------------------------------------------
// File: D3D9ExSample.cpp
//
// Sample showing how to use D3D9Ex advanced features.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------

{$I DirectX.inc}

unit D3D9ExUnit;

interface

uses
  Windows, Messages, Classes, Direct3D9, D3DX9, DXUTMisc;

type
  //--------------------------------------------------------------------------------------
  // structures
  //--------------------------------------------------------------------------------------
  TCursorVertex = record
    x, y, z, w: Single; // The transformed position for the vertex
    dwColor: DWORD;	    // Color
  end;

  TScreenVertex = record
    x, y, z, w: Single; // The transformed position for the vertex
    u, v: Single;	      // texture coordinate
  end;

const
  D3DFVF_CURSORVERTEX = (D3DFVF_XYZRHW or D3DFVF_DIFFUSE);
  D3DFVF_SCREENVERTEX = (D3DFVF_XYZRHW or D3DFVF_TEX1);

  CURSOR_SIZE = 60.0;


//--------------------------------------------------------------------------------------
// Function Prototypes
//--------------------------------------------------------------------------------------
function InitWindow(hInstance: THandle; nCmdShow: Integer): Boolean;
function CreateD3D9VDevice(const pD3D: IDirect3D9Ex; out ppDev9Ex: IDirect3DDevice9Ex;
  const pD3DPresentParameters: TD3DPresentParameters; hWnd: HWND): HRESULT;
function InitD3D: HRESULT;
function CreateFont: HRESULT;
function CreateSprite: HRESULT;
procedure Cleanup;
function CreateD3DCursor: HRESULT;
function CreateScreenVB(screenX, screenY: Single): HRESULT;
function UpdateScreenVB(screenX, screenY: Single): HRESULT;
function CreateSharedTexture: HRESULT;
procedure MoveCursor(posX, posY: LongWord);
function WndProc(hWnd: Windows.HWND; uMsg: LongWord; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
procedure Render(const pDev: IDirect3DDevice9Ex);
procedure RenderText(const pDev: IDirect3DDevice9Ex);


function WinMain: Integer;

implementation

uses
  BackgroundThread;


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_hWnd: HWND = 0;                    // Window Handle
  g_pD3D9: IDirect3D9Ex;			         // Direct3D9Ex object
  g_pDevRealTime: IDirect3DDevice9Ex;  // Device for rendering the real-time
                                       // objects like cursors

  g_D3DPresentParameters: TD3DPresentParameters; // Current present parameters

  g_hBackgroundThread: THandle = 0;    // Background thread

  g_pCursorVB: IDirect3DVertexBuffer9; // cursor vertex buffer
  g_pScreenVB: IDirect3DVertexBuffer9; // screen vertex buffer

  g_pSharedBackgroundTexture: IDirect3DTexture9; // Our shared texture

  g_pFont: ID3DXFont;                  // Font for drawing text
  g_pSprite: ID3DXSprite;              // Sprite for batching draw text calls

  g_bSkipRendering: Boolean = False;
  g_cubeCount: Integer = 3;
  g_PresentStats: TD3DPresentStats;
  g_fLastFrameTime: Single = 0.0000001;
  g_liLastTimerUpdate: Int64 = 0;
  g_liTimerFrequency: Int64 = 0;



function WinMain: Integer;
var
  msg: TMsg;
begin
  try
    FillChar(msg, SizeOf(msg), 0);
    msg.wParam := -1;

    if not InitWindow(HInstance, CmdShow) then
    begin
      Result:= 0;
      Exit;
    end;

    if FAILED(InitD3D) then
    begin
      Result:= 1;
      Exit;
    end;

    FillChar(g_D3DPresentParameters, SizeOf(g_D3DPresentParameters), 0);
    g_D3DPresentParameters.hDeviceWindow := g_hWnd;
    g_D3DPresentParameters.Windowed := True;
    g_D3DPresentParameters.SwapEffect := D3DSWAPEFFECT_DISCARD;
    g_D3DPresentParameters.PresentationInterval := D3DPRESENT_INTERVAL_DEFAULT;

    if FAILED(CreateD3D9VDevice(g_pD3D9, g_pDevRealTime, g_D3DPresentParameters, g_hWnd)) then
    begin
      Result:= 2;
      Exit;
    end;

    if FAILED(CreateD3DCursor) then
    begin
      Result:= 3;
      Exit;
    end;

    if FAILED(CreateScreenVB(800, 600)) then
    begin
      Result:= 4;
      Exit;
    end;

    if FAILED(CreateFont) then
    begin
      Result:= 5;
      Exit;
    end;

    if FAILED(CreateSprite) then
    begin
      Result:= 6;
      Exit;
    end;

    // set the realtime GPU thread priority
    g_pDevRealTime.SetGPUThreadPriority(7);
    SetThreadPriority(GetCurrentThread, THREAD_PRIORITY_HIGHEST);

    // Get Timer Frequency
    QueryPerformanceFrequency(g_liTimerFrequency);
    QueryPerformanceCounter(g_liLastTimerUpdate);

    // Create the background thread
    g_hBackgroundThread := CreateBackgroundThread(g_pD3D9);
    if (g_hBackgroundThread = 0) then
    begin
      Result := 7;
      Exit;
    end;

    if FAILED(CreateSharedTexture) then
    begin
      Result:= 5;
      Exit;
    end;

    // Hide the cursor
    ShowCursor(False);

    // Main loop
    msg.message := WM_NULL;
    PeekMessage(msg, 0, 0, 0, PM_NOREMOVE);
    while (WM_QUIT <> msg.message) do
    begin
      if PeekMessage(msg, 0, 0, 0, PM_REMOVE) then
      begin
        TranslateMessage(msg);
        DispatchMessage(msg);
      end else
      begin
        Render(g_pDevRealTime);  // Do some rendering
      end;
    end;

  finally
    if (g_hBackgroundThread <> 0) then
    begin
      KillBackgroundThread;
      WaitForSingleObject(g_hBackgroundThread,INFINITE);
    end;

    Cleanup;
  end;

  Result:= Integer(msg.wParam);
end;

//--------------------------------------------------------------------------------------
// Register class and create window
//--------------------------------------------------------------------------------------
function InitWindow(hInstance: THandle; nCmdShow: Integer): Boolean;
var
  wcex: TWndClassEx;
  rc: TRect;
begin
  Result:= FALSE;

  //
  // Register class
  //
  wcex.cbSize := SizeOf(TWndClassEx);
  wcex.style          := CS_CLASSDC;
  wcex.lpfnWndProc    := @WndProc;
  wcex.cbClsExtra     := 0;
  wcex.cbWndExtra     := 0;
  wcex.hInstance      := hInstance;
  wcex.hIcon          := 0;
  wcex.hCursor        := LoadCursor(0, IDC_ARROW);
  wcex.hbrBackground  := HBRUSH(COLOR_WINDOW+1);
  wcex.lpszMenuName   := nil;
  wcex.lpszClassName  := 'd3d9vwindowclass';
  wcex.hIconSm        := 0;

  if (RegisterClassEx(wcex) = 0) then Exit;

  //
  // Create window
  //
  rc := Rect(0, 0, 800, 600);
  AdjustWindowRectEx(rc, WS_OVERLAPPEDWINDOW, False, WS_EX_CLIENTEDGE);
  g_hWnd := CreateWindowEx(WS_EX_CLIENTEDGE, 'd3d9vwindowclass', 'Direct3D9Ex Sample', WS_OVERLAPPEDWINDOW,
                           Integer(CW_USEDEFAULT), Integer(CW_USEDEFAULT), rc.right - rc.left, rc.bottom - rc.top, 0, 0,
                           hInstance, nil);

  if (g_hWnd = 0) then Exit;

  ShowWindow(g_hWnd, nCmdShow);

  Result:= True;
end;

function CreateD3D9VDevice(const pD3D: IDirect3D9Ex; out ppDev9Ex: IDirect3DDevice9Ex;
  const pD3DPresentParameters: TD3DPresentParameters; hWnd: HWND): HRESULT;
var
  dwFlags: DWORD;
  Caps: TD3DCaps9;
begin
  // Create a d3d9ex device
  dwFlags := D3DCREATE_SOFTWARE_VERTEXPROCESSING or D3DCREATE_ENABLE_PRESENTSTATS;

  if (hWnd = 0) then
  begin
    hWnd := g_hWnd;
    dwFlags := D3DCREATE_SOFTWARE_VERTEXPROCESSING;
  end;

  Result := pD3D.CreateDeviceEx(D3DADAPTER_DEFAULT,
                                D3DDEVTYPE_HAL,
                                hWnd,
                                dwFlags,
                                @pD3DPresentParameters,
                                nil,
                                ppDev9Ex);

  if SUCCEEDED(Result) then
  begin
    // Make sure our formats are OK
    ZeroMemory(@Caps, SizeOf(Caps));
    pD3D.GetDeviceCaps(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, Caps);

    // Skip backbuffer formats that don't support alpha blending
    Result := pD3D.CheckDeviceFormat(Caps.AdapterOrdinal, Caps.DeviceType,
                     pD3DPresentParameters.BackBufferFormat, D3DUSAGE_QUERY_POSTPIXELSHADER_BLENDING,
                     D3DRTYPE_TEXTURE, pD3DPresentParameters.BackBufferFormat);
    if FAILED(Result) then ppDev9Ex := nil;
  end;
end;


function InitD3D: HRESULT;
begin
  // Create a d3d9 device
  Result := Direct3DCreate9Ex(D3D_SDK_VERSION, g_pD3D9);
end;


function Reset(pDev9Ex: IDirect3DDevice9Ex): HRESULT;
begin
  // reset the d3d9ex device
  Result := pDev9Ex.Reset(g_D3DPresentParameters);
  if FAILED(Result) then Exit;

  Result:= CreateSprite;
end;

function CreateFont: HRESULT;
begin
  if FAILED(D3DXCreateFont(g_pDevRealTime, 16, 0, FW_BOLD, 1, FALSE, DEFAULT_CHARSET,
                           OUT_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE,
                           'Arial', g_pFont)) then
  begin
    Result:= E_FAIL;
    Exit;
  end;

  Result:= S_OK;
end;


function CreateSprite: HRESULT;
begin
  // Create a sprite to help batch calls when drawing many lines of text
  Result:= D3DXCreateSprite(g_pDevRealTime, g_pSprite);
end;


//--------------------------------------------------------------------------------------
// Clean up the objects we've created
//--------------------------------------------------------------------------------------
procedure Cleanup;
begin
  g_pD3D9 := nil;
  g_pDevRealTime := nil;
  g_pCursorVB := nil;
  g_pScreenVB := nil;
  g_pSharedBackgroundTexture := nil;
  g_pFont := nil;
  g_pSprite := nil;
end;


function CreateD3DCursor: HRESULT;
begin
  // create the vb
  if FAILED(g_pDevRealTime.CreateVertexBuffer(4*SizeOf(TCursorVertex),
                                              D3DUSAGE_DYNAMIC,
                                              D3DFVF_CURSORVERTEX,
                                              D3DPOOL_DEFAULT,
                                              g_pCursorVB,
                                              nil)) then
  begin
    Result:= E_FAIL;
    Exit;
  end;

  MoveCursor(400, 300);

  Result:= S_OK;
end;


function CreateScreenVB(screenX, screenY: Single): HRESULT;
begin
  // create the vb
  if FAILED(g_pDevRealTime.CreateVertexBuffer(4*SizeOf(TScreenVertex),
                                              D3DUSAGE_DYNAMIC,
                                              D3DFVF_SCREENVERTEX,
                                              D3DPOOL_DEFAULT,
                                              g_pScreenVB,
                                              nil)) then
  begin
    Result:= E_FAIL;
    Exit;
  end;

  UpdateScreenVB(screenX, screenY);

  Result:= S_OK;
end;

function UpdateScreenVB(screenX, screenY: Single): HRESULT;
type
  TScreenVertexArray = array [0..3] of TScreenVertex;
var
  vertices: ^TScreenVertexArray;
begin
  if FAILED(g_pScreenVB.Lock(0, 4*SizeOf(TScreenVertex), Pointer(vertices), 0)) then
  begin
    Result := E_FAIL;
    Exit;
  end;

  vertices[0].x := 0;
  vertices[0].y := screenY;
  vertices[0].z := 0.5;
  vertices[0].w := 1.0;
  vertices[0].u := 0.0;
  vertices[0].v := 1.0;

  vertices[1].x := 0;
  vertices[1].y := 0;
  vertices[1].z := 0.5;
  vertices[1].w := 1.0;
  vertices[1].u := 0.0;
  vertices[1].v := 0.0;

  vertices[2].x := screenX;
  vertices[2].y := screenY;
  vertices[2].z := 0.5;
  vertices[2].w := 1.0;
  vertices[2].u := 1.0;
  vertices[2].v := 1.0;

  vertices[3].x := screenX;
  vertices[3].y := 0;
  vertices[3].z := 0.5;
  vertices[3].w := 1.0;
  vertices[3].u := 1.0;
  vertices[3].v := 0.0;

  g_pScreenVB.Unlock;

  Result:= S_OK;
end;


function CreateSharedTexture: HRESULT;
var
  hHandle: THandle;
begin
  // wait for a handle from the other thread
  hHandle := 0;
  while (hHandle = 0) do
    hHandle := GetSharedTextureHandle;

  Result := g_pDevRealTime.CreateTexture(g_RTWidth,
                             g_RTHeight,
                             1,
                             D3DUSAGE_RENDERTARGET,
                             D3DFMT_X8R8G8B8,
                             D3DPOOL_DEFAULT,
                             g_pSharedBackgroundTexture,
                             @hHandle);
  if FAILED(Result) then Result:= E_FAIL;
end;


procedure MoveCursor(posX, posY: LongWord);
type
  TCursorVertexArray = array[0..3] of TCursorVertex;
var
  x, y: Single;
  vertices: TCursorVertexArray;
  i: Integer;
  pVertices: Pointer;
begin
  x := posX;
  y := posY;

  // Initialize vertices for rendering a quad
  vertices[0].x := x;
  vertices[0].y := y;
  vertices[0].z := 0.5;
  vertices[0].w := 1.0;

  vertices[1].x := x + CURSOR_SIZE;
  vertices[1].y := y + CURSOR_SIZE*0.6;
  vertices[1].z := 0.5;
  vertices[1].w := 1.0;

  vertices[2].x := x + CURSOR_SIZE*0.6;
  vertices[2].y := y + CURSOR_SIZE;
  vertices[2].z := 0.5;
  vertices[2].w := 1.0;

  vertices[3].x := x + CURSOR_SIZE;
  vertices[3].y := y + CURSOR_SIZE;
  vertices[3].z := 0.5;
  vertices[3].w := 1.0;

  for i := 0 to 3 do
    vertices[i].dwColor := $FF0000;

{$IFDEF DEBUG}
  if not Assigned(g_pCursorVB) then
  begin
    MessageBox(0, 'MoveCursor - not Assigned !', 'MoveCursor', 0);
    Exit;
  end;
{$ENDIF}

  if FAILED(g_pCursorVB.Lock(0, SizeOf(vertices), Pointer(pVertices), 0))
  then Exit;

  CopyMemory(pVertices, @vertices, SizeOf(vertices));
  g_pCursorVB.Unlock;
end;


function WndProc(hWnd: Windows.HWND; uMsg: LongWord; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  ps: TPaintStruct;
  //hdc: Windows.HDC;
  x, y: LongWord;
  dwStyle: DWORD;
  dwExStyle: DWORD;
  Mode: TD3DDisplayMode;
  rc: TRect;
begin
  case uMsg of
    WM_PAINT:
    begin
      {hdc := }BeginPaint(hWnd, ps);
      EndPaint(hWnd, ps);
    end;

    WM_DESTROY:
      PostQuitMessage(0);

    WM_MOUSEMOVE:
    begin
      x := LOWORD(lParam);
      y := HIWORD(lParam);
      MoveCursor(x, y);
    end;

    WM_KEYUP:
    case wParam of
      VK_UP:   g_cubeCount := IncreaseCubeCount;
      VK_DOWN: g_cubeCount := DecreaseCubeCount;
      VK_ESCAPE: PostQuitMessage(0);
    end;

    WM_SYSKEYUP:
    begin
      if (wParam = VK_RETURN) and (g_pD3D9 <> nil) and (g_pDevRealTime <> nil) then
      begin
        g_D3DPresentParameters.Windowed := not g_D3DPresentParameters.Windowed;

        g_pD3D9.GetAdapterDisplayMode(D3DADAPTER_DEFAULT, Mode);

        if (g_D3DPresentParameters.Windowed) then
        begin
          //
          // Default to using the window client area size
          //
          g_D3DPresentParameters.BackBufferWidth := 800;
          g_D3DPresentParameters.BackBufferHeight := 600;

          //
          // Window styles for D3D windowed mode
          //
          dwStyle := WS_OVERLAPPEDWINDOW;
          dwExStyle := WS_EX_CLIENTEDGE;
        end else
        begin
          g_D3DPresentParameters.BackBufferWidth:=Mode.Width;
          g_D3DPresentParameters.BackBufferHeight:=Mode.Height;

          dwStyle := DWORD(WS_POPUP);
          dwExStyle := WS_EX_TOPMOST;
        end;

        SetWindowLong(g_hWnd, GWL_STYLE, dwStyle);
        SetWindowLong(g_hWnd, GWL_EXSTYLE, dwExStyle);

        if (g_D3DPresentParameters.Windowed) then
        begin
          rc := Rect(0, 0, g_D3DPresentParameters.BackBufferWidth, g_D3DPresentParameters.BackBufferHeight);
          AdjustWindowRectEx(rc, dwStyle, FALSE, dwExStyle);

          SetWindowPos(g_hWnd, HWND_NOTOPMOST,
                       0, 0,
                       rc.right - rc.left,
                       rc.bottom - rc.top,
                       SWP_SHOWWINDOW or SWP_NOMOVE);
        end;

        Result := g_pDevRealTime.Reset(g_D3DPresentParameters);

        if SUCCEEDED(Result) then
        begin
          Result := UpdateScreenVB(g_D3DPresentParameters.BackBufferWidth,
                                   g_D3DPresentParameters.BackBufferHeight);
        end;

        if FAILED(Result) then
        begin
          Result:= 0;
          Exit;
        end;
      end;
    end;
  else
    Result:= DefWindowProc(hWnd, uMsg, wParam, lParam);
    Exit;
  end;

  Result:= 0;
end;


procedure Render(const pDev: IDirect3DDevice9Ex);
var
  hr: HRESULT;
  DisplayModeFilter: TD3DDisplayModeFilter;
  // ModeCount: LongWord;
  pSwapChain: IDirect3DSwapChain9;
  pSwapChainEx: IDirect3DSwapChain9Ex;
  liCurrentTime: Int64;
begin
  // Begin the scene
  if not g_bSkipRendering and SUCCEEDED(pDev.BeginScene) then
  begin
    // disable lighting
    pDev.SetRenderState(D3DRS_LIGHTING, iFalse);


    //
    // Render the background
    //

    // set the texture
    pDev.SetTexture(0, g_pSharedBackgroundTexture);

    pDev.SetTextureStageState(0, D3DTSS_COLOROP, D3DTOP_SELECTARG1);
    pDev.SetTextureStageState(0, D3DTSS_COLORARG1, D3DTA_TEXTURE);

    // stream sources
    pDev.SetStreamSource(0, g_pScreenVB, 0, SizeOf(TScreenVertex));
    pDev.SetFVF(D3DFVF_SCREENVERTEX);

    // draw
    pDev.DrawPrimitive(D3DPT_TRIANGLESTRIP, 0, 2);


    //
    // Render the cursor
    //

    pDev.SetTexture(0, nil);

    // set the texture stage states
    pDev.SetTextureStageState(0, D3DTSS_COLOROP, D3DTOP_SELECTARG1);
    pDev.SetTextureStageState(0, D3DTSS_COLORARG1, D3DTA_DIFFUSE);

    // stream sources
    pDev.SetStreamSource(0, g_pCursorVB, 0, SizeOf(TCursorVertex));
    pDev.SetFVF(D3DFVF_CURSORVERTEX);

    // draw
    pDev.DrawPrimitive(D3DPT_TRIANGLESTRIP, 0, 2);

    // render text
    RenderText(pDev);

    // End the scene
    pDev.EndScene;
  end
  else if (g_bSkipRendering) then
    Sleep(20);	//don't hog the entire CPU

  // Present the backbuffer contents to the display
  hr := pDev.Present(nil, nil, 0, nil);

  // Handle Occluded, DeviceReset, or Mode Changes
  if (S_PRESENT_OCCLUDED = hr) then
  begin
    g_bSkipRendering := True;
  end
  else if (D3DERR_DEVICELOST = hr) then
  begin
    if FAILED(Reset(pDev)) then
      g_bSkipRendering := True;
  end
  else if (S_PRESENT_MODE_CHANGED = hr) then
  begin
    //
    // Reenumerate modes by calling IDirect3D9::GetAdapterModeCountEx
    //
    ZeroMemory(@DisplayModeFilter, SizeOf(DisplayModeFilter));

    DisplayModeFilter.Size			   := SizeOf(DisplayModeFilter);
    DisplayModeFilter.Format		   := D3DFMT_UNKNOWN;
    DisplayModeFilter.ScanLineOrdering := D3DSCANLINEORDERING_PROGRESSIVE;

    //TODO: Is it needed?
    {ModeCount := }g_pD3D9.GetAdapterModeCountEx(D3DADAPTER_DEFAULT, @DisplayModeFilter);

    if FAILED(Reset(pDev)) then
      g_bSkipRendering := True;
  end
  else if (D3DERR_DEVICEHUNG = hr) then
  begin
    MessageBox(g_hWnd,
               'This application has caused the graphics adapter to hang, check with the hardware vendor for a new driver.',
               'Graphics Adapter Hang',
               MB_OK );

    PostQuitMessage(0);
    g_bSkipRendering := True;
  end else
  begin
    g_bSkipRendering := False;
  end;

  // Get some presents stats
  if SUCCEEDED(pDev.GetSwapChain(0, pSwapChain)) then
  begin
    if SUCCEEDED(pSwapChain.QueryInterface(IID_IDirect3DSwapChain9Ex, pSwapChainEx)) then
    begin
      hr := pSwapChainEx.GetLastPresentCount(g_PresentStats.PresentCount);
      if SUCCEEDED(hr) then
        {hr := }pSwapChainEx.GetPresentStats(g_PresentStats);
      pSwapChainEx := nil;
    end;
    pSwapChain := nil;
  end;

  // Get the time
  QueryPerformanceCounter(liCurrentTime);
  g_fLastFrameTime := (liCurrentTime - g_liLastTimerUpdate) / g_liTimerFrequency;
  g_liLastTimerUpdate := liCurrentTime;
end;


procedure RenderText(const pDev: IDirect3DDevice9Ex);
var
  txtHelper: CDXUTTextHelper;
  FPS: Single;
begin
  // The helper object simply helps keep track of text position, and color
  // and then it calls pFont->DrawText( m_pSprite, strMsg, -1, &rc, DT_NOCLIP, m_clr );
  // If NULL is passed in as the sprite object, then it will work fine however the
  // pFont->DrawText() will not be batched together.  Batching calls will improves perf.
  txtHelper := CDXUTTextHelper.Create(g_pFont, g_pSprite, 15);

  // Output statistics
  txtHelper._Begin;
  txtHelper.SetInsertionPos(2, 0);
  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));
  txtHelper.DrawTextLine('This sample demonstrates rendering a cursor indepedently of geometry.');
  txtHelper.DrawTextLine('The scene (cubes in this case) is drawn by a D3D9Ex device that runs');
  txtHelper.DrawTextLine('in a lower priority background thread.  The image is copied to a shared');
  txtHelper.DrawTextLine('surface.  The main application thread contains a D3D9Ex device as well.');
  txtHelper.DrawTextLine('This thread runs at a higher priority and composites the shared image');
  txtHelper.DrawTextLine('with a D3D9Ex drawn cursor and text in real time.  This allows for');
  txtHelper.DrawTextLine('fluid cursor and text updates even when the scene is too complex to be');
  txtHelper.DrawTextLine('handled in real-time.');

  txtHelper.SetForegroundColor(D3DXColor(1.0, 0.0, 0.0, 1.0 ));
  txtHelper.DrawTextLine('');
  txtHelper.DrawTextLine('Press the UP arrow key to increase the scene complexity.');
  txtHelper.DrawTextLine('Press the DOWN arrow key to decrease the scene complexity.');
  txtHelper.DrawTextLine('');
  txtHelper.DrawTextLine('Try increasing the Number of Cubes to a very high number.  The cubes will');
  txtHelper.DrawTextLine('update slowly, but the cursor will still be responsive.');
  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
  txtHelper.DrawTextLine('');
  txtHelper.DrawFormattedTextLine('Number of Cubes: %d', [g_cubeCount*g_cubeCount]);

  // get stats from the background thread
  FPS := GetFPS;
  txtHelper.SetForegroundColor(D3DXColor(0.0, 1.0, 0.0, 1.0));
  txtHelper.DrawTextLine('');
  txtHelper.DrawTextLine('Background Thread:');
  txtHelper.DrawFormattedTextLine('FPS: %0.2f', [FPS]);
  txtHelper.DrawTextLine('');
  txtHelper.DrawTextLine('Foreground Thread:');
  txtHelper.DrawFormattedTextLine('FPS: %0.2f', [1.0 / g_fLastFrameTime]);
  txtHelper.DrawFormattedTextLine('Present Count: %d', [g_PresentStats.PresentCount]);
  txtHelper.DrawFormattedTextLine('Present Refresh Count: %d', [g_PresentStats.PresentRefreshCount]);
  txtHelper.DrawFormattedTextLine('Sync Refresh Count: %d', [g_PresentStats.SyncRefreshCount]);

  txtHelper._End;
  txtHelper.Free;
end;


end.

