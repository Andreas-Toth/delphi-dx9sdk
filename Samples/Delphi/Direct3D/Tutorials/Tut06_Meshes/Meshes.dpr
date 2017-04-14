(*----------------------------------------------------------------------------*
 *  Direct3D tutorial from DirectX 9.0 SDK                                    *
 *  Delphi adaptation by Alexey Barkovoy (e-mail: directx@clootie.ru)         *
 *                                                                            *
 *  Latest version can be downloaded from:                                    *
 *     http://www.clootie.ru                                                  *
 *     http://sourceforge.net/projects/delphi-dx9sdk                          *
 *----------------------------------------------------------------------------*
 *  $Id: Meshes.dpr,v 1.12 2005/06/30 19:49:00 clootie Exp $
 *----------------------------------------------------------------------------*)
//-----------------------------------------------------------------------------
// File: Meshes.cpp
//
// Desc: For advanced geometry, most apps will prefer to load pre-authored
//       meshes from a file. Fortunately, when using meshes, D3DX does most of
//       the work for this, parsing a geometry file and creating vertx buffers
//       (and index buffers) for us. This tutorial shows how to use a D3DXMESH
//       object, including loading it from a file and rendering it. One thing
//       D3DX does not handle for us is the materials and textures for a mesh,
//       so note that we have to handle those manually.
//
//       Note: one advanced (but nice) feature that we don't show here is that
//       when cloning a mesh we can specify the FVF. So, regardless of how the
//       mesh was authored, we can add/remove normals, add more texture
//       coordinate sets (for multi-texturing), etc.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//-----------------------------------------------------------------------------

{$APPTYPE GUI}
{$I DirectX.inc}

program Meshes;

uses
  Windows,
  Messages,
  SysUtils,
  MMSystem,
  DXTypes,
  Direct3D9,
  D3DX9;

type
  PD3DMaterial9Array = ^TD3DMaterial9Array;
  TD3DMaterial9Array = array[0..MaxInt div SizeOf(TD3DMaterial9)-1] of TD3DMaterial9;

  PIDirect3DTexture9Array = ^IDirect3DTexture9Array;
  IDirect3DTexture9Array = array[0..MaxInt div SizeOf(IDirect3DTexture9)-1] of IDirect3DTexture9;


//-----------------------------------------------------------------------------
// Global variables
//-----------------------------------------------------------------------------
var
  g_pD3D:           IDirect3D9              = nil; // Used to create the D3DDevice
  g_pd3dDevice:     IDirect3DDevice9        = nil; // Our rendering device

  g_pMesh:          ID3DXMesh               = nil; // Our mesh object in sysmem
  g_pMeshMaterials: PD3DMaterial9Array      = nil; // Materials for our mesh
  g_pMeshTextures:  PIDirect3DTexture9Array = nil; // Textures for our mesh
  g_NumMaterials:   Integer                 = 0;   // Number of mesh materials



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

  // Turn on the zbuffer
  g_pd3dDevice.SetRenderState(D3DRS_ZENABLE, iTrue);

  // Turn on ambient lighting
  g_pd3dDevice.SetRenderState(D3DRS_AMBIENT, $ffffffff);

  Result:= S_OK;
end;



//-----------------------------------------------------------------------------
// Name: InitGeometry()
// Desc: Creates the scene geometry
//-----------------------------------------------------------------------------
function InitGeometry: HRESULT;
type
  PD3DXMaterialArray = ^TD3DXMaterialArray;
  TD3DXMaterialArray = array[0..MaxInt div SizeOf(TD3DXMaterial)-1] of TD3DXMaterial;
const
  strPrefix = '..\';
var
  pD3DXMtrlBuffer: ID3DXBuffer;
  d3dxMaterials: PD3DXMaterialArray;
  i: Integer;
  strTexture: String;
begin
  Result:= E_FAIL;

  // Load the mesh from the specified file
  // Load the mesh from the specified file
  if FAILED(D3DXLoadMeshFromX('Tiger.x', D3DXMESH_SYSTEMMEM,
                              g_pd3dDevice, nil,
                              @pD3DXMtrlBuffer, nil, @g_NumMaterials,
                              g_pMesh)) then
  begin
    // If model is not in current folder, try parent folder
    if FAILED(D3DXLoadMeshFromX('..\Tiger.x', D3DXMESH_SYSTEMMEM,
                                g_pd3dDevice, nil,
                                @pD3DXMtrlBuffer, nil, @g_NumMaterials,
                                g_pMesh)) then
    begin
      MessageBox(0, 'Could not find tiger.x', 'Meshes.exe', MB_OK);
      Exit;
    end;
  end;

  // We need to extract the material properties and texture names from the
  // pD3DXMtrlBuffer
  d3dxMaterials := pD3DXMtrlBuffer.GetBufferPointer;
  try
    GetMem(g_pMeshMaterials, SizeOf(TD3DMaterial9)*g_NumMaterials);
    GetMem(g_pMeshTextures, SizeOf(IDirect3DTexture9)*g_NumMaterials);
  except
    Result:= E_OUTOFMEMORY;
    Exit;
  end;
  ZeroMemory(g_pMeshTextures, SizeOf(IDirect3DTexture9)*g_NumMaterials);

  i:= 0;
  while (i < g_NumMaterials) do
  begin
    // Copy the material
    g_pMeshMaterials[i] := d3dxMaterials[i].MatD3D;

    // Set the ambient color for the material (D3DX does not do this)
    g_pMeshMaterials[i].Ambient := g_pMeshMaterials[i].Diffuse;

    g_pMeshTextures[i] := nil;
    if (d3dxMaterials[i].pTextureFilename <> nil) and
       (StrLen(d3dxMaterials[i].pTextureFilename) > 0) then
    begin
      if FAILED(D3DXCreateTextureFromFile(g_pd3dDevice,
                                          d3dxMaterials[i].pTextureFilename,
                                          g_pMeshTextures[i])) then
      begin
        // If texture is not in current folder, try parent folder
        strTexture:= strPrefix + d3dxMaterials[i].pTextureFilename;
        // If texture is not in current folder, try parent folder
        if FAILED(D3DXCreateTextureFromFile(g_pd3dDevice,
                                            PChar(strTexture),
                                            g_pMeshTextures[i])) then
        begin
          MessageBox(0, 'Could not find texture map', 'Meshes.exe', MB_OK);
        end;
      end;
    end;
    Inc(i);
  end;

  // Done with the material buffer
  {$IFDEF TMT}
  pD3DXMtrlBuffer.Release;
  {$ELSE}
  pD3DXMtrlBuffer:= nil;
  {$ENDIF}

  Result:= S_OK;
end;



//-----------------------------------------------------------------------------
// Name: Cleanup()
// Desc: Releases all previously initialized objects
//-----------------------------------------------------------------------------
procedure Cleanup;
var
  i: Integer;
begin
  if (g_pMeshMaterials <> nil) then
    FreeMem(g_pMeshMaterials);

  if (g_pMeshTextures <> nil)  then
  begin
    i:= 0;
    while (i < g_NumMaterials) do
    begin
      {$IFDEF TMT}
      if (g_pMeshTextures[i] <> nil) then g_pMeshTextures[i].Release;
      {$ELSE}
      g_pMeshTextures[i]:= nil;
      {$ENDIF}

      Inc(i);
    end;
    FreeMem(g_pMeshTextures);
  end;

{$IFDEF TMT}
  if (g_pMesh <> nil) then g_pMesh.Release;
  if (g_pd3dDevice <> nil) then g_pd3dDevice.Release;
  if (g_pD3D <> nil) then g_pD3D.Release;
{$ELSE}
  g_pMesh:= nil;
  g_pd3dDevice:= nil;
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
  D3DXMatrixRotationY(matWorld, timeGetTime/1000.0);
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
// Name: Render()
// Desc: Draws the scene
//-----------------------------------------------------------------------------
procedure Render;
var
  i: Integer;
begin
  // Clear the backbuffer and the zbuffer
  g_pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER,
                     D3DCOLOR_XRGB(0,0,255), 1.0, 0);

  // Begin the scene
  if SUCCEEDED(g_pd3dDevice.BeginScene) then
  begin
    // Setup the world, view, and projection matrices
    SetupMatrices;

    // Meshes are divided into subsets, one for each material. Render them in
    // a loop
    i:= 0;
    while (i < g_NumMaterials) do
    begin
      // Set the material and texture for this subset
      g_pd3dDevice.SetMaterial(g_pMeshMaterials[i]);
      g_pd3dDevice.SetTexture(0, g_pMeshTextures[i]);

      // Draw the mesh subset
      g_pMesh.DrawSubset(i);

      Inc(i);
    end;

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
// Name: program start 
// Desc: The application's entry point
//-----------------------------------------------------------------------------
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
  hWindow := CreateWindow('D3D Tutorial', 'D3D Tutorial 06: Meshes',
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

