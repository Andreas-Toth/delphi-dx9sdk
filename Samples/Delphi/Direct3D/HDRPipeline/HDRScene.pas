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
 *  $Id: HDRScene.pas,v 1.5 2007/02/05 22:21:08 clootie Exp $
 *----------------------------------------------------------------------------*)
//======================================================================
//
//      HIGH DYNAMIC RANGE RENDERING DEMONSTRATION
//      Written by Jack Hoxley, October 2005
//
//======================================================================

{$I DirectX.inc}

unit HDRScene;

interface

uses
  Windows, DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTmisc, StrSafe;

// To provide some logical grouping to the functionality offered by this
// code it is wrapped up in a C++ namespace. As such, all code relating
// to the rendering of the original 3D scene containing the raw High Dynamic
// Range values is accessed via the HDRScene qualifier.
// namespace HDRScene


// This function is called when the application is first initialized or
// shortly after a restore/lost-device situation. It is responsible for
// creating all the geometric and rendering resources required to generate
// the HDR scene.
function CreateResources(const pDevice: IDirect3DDevice9; const pDisplayDesc: TD3DSurfaceDesc): HRESULT;

// This following function is effectively the opposite to the above. It is
// invoked when it is necessary to remove any resources that were previously
// created. Typically called during a lost-device or termination event.
function DestroyResources: HRESULT;

// This method takes all the necessary resources and renders them
// to the HDR render target for later processing.
function RenderScene(const pDevice: IDirect3DDevice9): HRESULT;

// This method allows the code to update any internal variables, especially
// movement/animation based ones.
function UpdateScene(const pDevice: IDirect3DDevice9; fTime: Single; const pCamera: CModelViewerCamera): HRESULT;

// The results of rendering the HDR scene feed into several other parts
// of the rendering pipeline used by this example. As such it is necessary
// for them to be able to retrieve a reference to the HDR source.
function GetOutputTexture(out pTexture: IDirect3DTexture9): HRESULT;

// This puts the HDR source texture onto the correct part of the GUI.
function DrawToScreen(const pDevice: IDirect3DDevice9; const pFont: ID3DXFont;
  const pTextSprite: ID3DXSprite; const pArrowTex: IDirect3DTexture9): HRESULT;

// A useful utility method for the GUI - HDR pipelines can take up a large
// amount of VRAM, such that it can be useful to monitor.
function CalculateResourceUsage: DWORD;


implementation

uses
  Math, HDREnumeration;


//--------------------------------------------------------------------------------------
// Data Structure Definitions
//--------------------------------------------------------------------------------------
type
  TLitVertex = record
    p: TD3DXVector3;
    c: DWORD;
  end;

const FVF_LITVERTEX = D3DFVF_XYZ or D3DFVF_DIFFUSE;

type
  TLVertex = record
    p: TD3DXVector4;
    t: TD3DXVector2;
  end;

const FVF_TLVERTEX = D3DFVF_XYZRHW or D3DFVF_TEX1;



//--------------------------------------------------------------------------------------
// Namespace-level variables
//--------------------------------------------------------------------------------------
var
  g_pCubeMesh: ID3DXMesh = nil;                            // Mesh representing the HDR source in the middle of the scene
  g_pCubePS: IDirect3DPixelShader9 = nil;                  // The pixel shader for the cube
  g_pCubePSConsts: ID3DXConstantTable = nil;               // Interface for setting parameters/constants for the above PS
  g_pCubeVS: IDirect3DVertexShader9 = nil;                 // The vertex shader for the cube
  g_pCubeVSDecl: IDirect3DVertexDeclaration9 = nil;        // The mapping from VB to VS
  g_pCubeVSConsts: ID3DXConstantTable = nil;               // Interface for setting params for the cube rendering
  g_mCubeMatrix: TD3DXMatrixA16;                           // The computed world*view*proj transform for the inner cube
  g_pTexScene: IDirect3DTexture9 = nil;                    // The main, floating point, render target
  g_fmtHDR: TD3DFormat = D3DFMT_UNKNOWN;                   // Enumerated and either set to 128 or 64 bit
  g_pOcclusionMesh: ID3DXMesh = nil;                       // The occlusion mesh surrounding the HDR cube
  g_pOcclusionVSDecl: IDirect3DVertexDeclaration9 = nil;   // The mapping for the ID3DXMesh
  g_pOcclusionVS: IDirect3DVertexShader9 = nil;            // The shader for drawing the occlusion mesh
  g_pOcclusionVSConsts: ID3DXConstantTable = nil;          // Entry point for configuring above shader
  g_mOcclusionMatrix: TD3DXMatrixA16;                      // The world*view*proj transform for transforming the POSITIONS
  g_mOcclusionNormals: TD3DXMatrixA16;                     // The transpose(inverse(world)) matrix for transforming NORMALS



//--------------------------------------------------------------------------------------
// Function Prototypes
//--------------------------------------------------------------------------------------
function LoadMesh(strFileName: PWideChar; out ppMesh: ID3DXMesh): HRESULT; forward;



//--------------------------------------------------------------------------------------
//  CreateResources( )
//
//      DESC:
//          This function creates all the necessary resources to render the HDR scene
//          to a render target for later use. When this function completes successfully
//          rendering can commence. A call to 'DestroyResources()' should be made when
//          the application closes.
//
//      PARAMS:
//          pDevice      : The current device that resources should be created with/from
//          pDisplayDesc : Describes the back-buffer currently in use, can be useful when
//                         creating GUI based resources.
//
//      NOTES:
//          n/a
//--------------------------------------------------------------------------------------
function CreateResources(const pDevice: IDirect3DDevice9; const pDisplayDesc: TD3DSurfaceDesc): HRESULT;
var
  pCode: ID3DXBuffer;      // Container for the compiled HLSL code
  str: array[0..MAX_PATH-1] of WideChar;
  cubeVertElems: TFVFDeclaration;
  vertElems: TFVFDeclaration;
begin
  //[ 0 ] DECLARATIONS
  //------------------


  //[ 1 ] DETERMINE FP TEXTURE SUPPORT
  //----------------------------------
  Result := V(HDREnumeration.FindBestHDRFormat(HDRScene.g_fmtHDR));
  if FAILED(Result) then
  begin
    OutputDebugString('HDRScene::CreateResources() - Current hardware does not support HDR rendering!'#10);
    Exit;
  end;


  //[ 2 ] CREATE HDR RENDER TARGET
  //------------------------------
  Result := V(pDevice.CreateTexture(
                          pDisplayDesc.Width, pDisplayDesc.Height,
                          1, D3DUSAGE_RENDERTARGET, g_fmtHDR,
                          D3DPOOL_DEFAULT, HDRScene.g_pTexScene, nil));
  if FAILED(Result) then
  begin
    // We couldn't create the texture - lots of possible reasons for this. Best
    // check the D3D debug output for more details.
    OutputDebugString('HDRScene::CreateResources() - Could not create floating point render target. Examine D3D Debug Output for details.'#10);
    Exit;
  end;


  //[ 3 ] CREATE HDR CUBE'S GEOMETRY
  //--------------------------------
  Result := V(LoadMesh('misc\Cube.x', HDRScene.g_pCubeMesh));
  if FAILED(Result) then
  begin
    // Couldn't load the mesh, could be a file system error...
    OutputDebugString('HDRScene::CreateResources() - Could not load ''Cube.x''.'#10);
    Exit;
  end;



  //[ 4 ] CREATE HDR CUBE'S PIXEL SHADER
  //------------------------------------
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'Shader Code\HDRSource.psh');
  if V_Failed(Result) then Exit;
  Result:= V(D3DXCompileShaderFromFileW(
                                        str,
                                        nil, nil,
                                        'main',                 // Entry Point found in 'HDRSource.psh'
                                        'ps_2_0',               // Profile to target
                                        0,
                                        @pCode,
                                        nil,
                                        @HDRScene.g_pCubePSConsts
                                       ));
  if FAILED(Result) then
  begin
    // Couldn't compile the shader, use the 'compile_shaders.bat' script
    // in the 'Shader Code' folder to get a proper compile breakdown.
    OutputDebugString('HDRScene::CreateResources() - Compiling of ''HDRSource.psh'' failed!'#10);
    Exit;
  end;


  Result:= V(pDevice.CreatePixelShader(PDWORD(pCode.GetBufferPointer), HDRScene.g_pCubePS));
  if FAILED(Result) then
  begin
    // Couldn't turn the compiled shader into an actual, usable, pixel shader!
    OutputDebugString('HDRScene::CreateResources() : Couldn''t create a pixel shader object from ''HDRSource.psh''.'#10);
    pCode := nil;
    Exit;
  end;

  pCode := nil;

  // [ 5 ] CREATE THE CUBE'S VERTEX DECL
  //------------------------------------
  HDRScene.g_pCubeMesh.GetDeclaration(cubeVertElems);

  Result:= V(pDevice.CreateVertexDeclaration(@cubeVertElems, HDRScene.g_pCubeVSDecl));
  if FAILED(Result) then
  begin
    // Couldn't create the declaration for the loaded mesh..
    OutputDebugString('HDRScene::CreateResources() - Couldn''t create a vertex declaration for the HDR-Cube mesh.'#10);
    pCode := nil;
    Exit;
  end;



  // [ 6 ] CREATE THE CUBE'S VERTEX SHADER
  //--------------------------------------
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'Shader Code\HDRSource.vsh');
  if V_Failed(Result) then Exit;

  Result:= V(D3DXCompileShaderFromFileW(
                                        str,
                                        nil, nil,
                                        'main',
                                        'vs_2_0',
                                        0,
                                        @pCode,
                                        nil,
                                        @g_pCubeVSConsts));
  if FAILED(Result) then
  begin
    // Couldn't compile the shader, use the 'compile_shaders.bat' script
    // in the 'Shader Code' folder to get a proper compile breakdown.
    OutputDebugString('HDRScene::CreateResources() - Compilation of ''HDRSource.vsh'' Failed!'#10);
    Exit;
  end;

  Result:= V(pDevice.CreateVertexShader(PDWORD(pCode.GetBufferPointer), HDRScene.g_pCubeVS));
  if FAILED(Result) then
  begin
    // Couldn't turn the compiled shader into an actual, usable, vertex shader!
    OutputDebugString('HDRScene::CreateResources() - Could not create a VS object from the compiled ''HDRSource.vsh'' code.'#10);
    pCode := nil;
    Exit;
  end;

  pCode := nil;

  //[ 5 ] LOAD THE OCCLUSION MESH
  //-----------------------------
  Result:= V(LoadMesh('misc\OcclusionBox.x', HDRScene.g_pOcclusionMesh));
  if FAILED(Result) then
  begin
    // Couldn't load the mesh, could be a file system error...
    OutputDebugString('HDRScene::CreateResources() - Could not load ''OcclusionBox.x''.'#10);
    Exit;
  end;



  //[ 6 ] CREATE THE MESH VERTEX DECLARATION
  //----------------------------------------
  HDRScene.g_pOcclusionMesh.GetDeclaration(vertElems);

  Result:= V(pDevice.CreateVertexDeclaration(@vertElems, HDRScene.g_pOcclusionVSDecl));
  if FAILED(Result) then
  begin
    // Couldn't create the declaration for the loaded mesh..
    OutputDebugString('HDRScene::CreateResources() - Couldn''t create a vertex declaration for the occlusion mesh.'#10);
    Exit;
  end;



  //[ 7 ] CREATE THE OCCLUSION VERTEX SHADER
  //----------------------------------------
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'Shader Code\OcclusionMesh.vsh');
  if V_Failed(Result) then Exit;

  Result:= V(D3DXCompileShaderFromFileW(
                              str,
                              nil, nil,
                              'main',
                              'vs_2_0',
                              0,
                              @pCode,
                              nil,
                              @HDRScene.g_pOcclusionVSConsts
                          ));
  if FAILED(Result) then
  begin
    // Couldn't compile the shader, use the 'compile_shaders.bat' script
    // in the 'Shader Code' folder to get a proper compile breakdown.
    OutputDebugString('HDRScene::CreateResources() - Compilation of ''OcclusionMesh.vsh'' Failed!'#10);
    Exit;
  end;

  Result:= V(pDevice.CreateVertexShader(PDWORD(pCode.GetBufferPointer), HDRScene.g_pOcclusionVS));
  if FAILED(Result) then
  begin
    // Couldn't turn the compiled shader into an actual, usable, vertex shader!
    OutputDebugString('HDRScene::CreateResources() - Could not create a VS object from the compiled ''OcclusionMesh.vsh'' code.'#10);
    pCode := nil;
    Exit;
  end;

  pCode := nil;



  //[ 8 ] RETURN SUCCESS IF WE GOT THIS FAR
  //---------------------------------------
  // Result:= hr;

end;



//--------------------------------------------------------------------------------------
//  DestroyResources( )
//
//      DESC:
//          Makes sure that the resources acquired in CreateResources() are cleanly
//          destroyed to avoid any errors and/or memory leaks.
//
//--------------------------------------------------------------------------------------
function DestroyResources: HRESULT;
begin
  SAFE_RELEASE(HDRScene.g_pCubeMesh);
  SAFE_RELEASE(HDRScene.g_pCubePS);
  SAFE_RELEASE(HDRScene.g_pCubePSConsts);
  SAFE_RELEASE(HDRScene.g_pTexScene);
  SAFE_RELEASE(HDRScene.g_pCubeVS);
  SAFE_RELEASE(HDRScene.g_pCubeVSConsts);
  SAFE_RELEASE(HDRScene.g_pCubeVSDecl);
  SAFE_RELEASE(HDRScene.g_pOcclusionMesh);
  SAFE_RELEASE(HDRScene.g_pOcclusionVSDecl);
  SAFE_RELEASE(HDRScene.g_pOcclusionVS);
  SAFE_RELEASE(HDRScene.g_pOcclusionVSConsts);

  Result:= S_OK;
end;



//--------------------------------------------------------------------------------------
//  CalculateResourceUsage( )
//
//      DESC:
//          Based on the known resources this function attempts to make an accurate
//          measurement of how much VRAM is being used by this part of the application.
//
//      NOTES:
//          Whilst the return value should be pretty accurate, it shouldn't be relied
//          on due to the way drivers/hardware can allocate memory.
//
//          Only the first level of the render target is checked as there should, by
//          definition, be no mip levels.
//
//--------------------------------------------------------------------------------------
function CalculateResourceUsage: DWORD;
var
  usage: DWORD;
  texDesc: TD3DSurfaceDesc;
  index_size: DWORD;
begin
  // [ 0 ] DECLARATIONS
  //-------------------
  usage := 0;

  // [ 1 ] RENDER TARGET SIZE
  //-------------------------
  HDRScene.g_pTexScene.GetLevelDesc(0, texDesc);
  usage := usage + ( (texDesc.Width*texDesc.Height) * DWORD(IfThen(HDRScene.g_fmtHDR = D3DFMT_A16B16G16R16F, 8, 16)));

  // [ 2 ] OCCLUSION MESH SIZE
  //--------------------------
  usage := usage + (HDRScene.g_pOcclusionMesh.GetNumBytesPerVertex * HDRScene.g_pOcclusionMesh.GetNumVertices);
  index_size := IfThen(HDRScene.g_pOcclusionMesh.GetOptions and D3DXMESH_32BIT <> 0, 4, 2);
  usage := usage + (index_size * 3 * HDRScene.g_pOcclusionMesh.GetNumFaces);

  Result:= usage;
end;



//--------------------------------------------------------------------------------------
//  RenderScene( )
//
//      DESC:
//          This is the core function for this unit - when it succesfully completes the
//          render target (obtainable via GetOutputTexture) will be a completed scene
//          that, crucially, contains values outside the LDR (0..1) range ready to be
//          fed into the various stages of the HDR post-processing pipeline.
//
//      PARAMS:
//          pDevice     : The device that is currently being used for rendering
//
//      NOTES:
//          For future modifications, this is the entry point that should be used if
//          you require a different image/scene to be displayed on the screen.
//
//          This function assumes that the device is already in a ready-to-render
//          state (e.g. BeginScene() has been called).
//
//--------------------------------------------------------------------------------------
function RenderScene(const pDevice: IDirect3DDevice9): HRESULT;
var
  pPrevSurf: IDirect3DSurface9;
  pRTSurf: IDirect3DSurface9;
begin
  Result:= E_FAIL;

  // [ 0 ] CONFIGURE GEOMETRY INPUTS
  //--------------------------------
  pDevice.SetVertexShader(HDRScene.g_pCubeVS);
  pDevice.SetVertexDeclaration(HDRScene.g_pCubeVSDecl);
  HDRScene.g_pCubeVSConsts.SetMatrix(pDevice, 'matWorldViewProj', HDRScene.g_mCubeMatrix);



  // [ 1 ] PIXEL SHADER ( + PARAMS )
  //--------------------------------
  pDevice.SetPixelShader(HDRScene.g_pCubePS);
  HDRScene.g_pCubePSConsts.SetFloat(pDevice, 'HDRScalar', 5.0);
  pDevice.SetTexture(0, nil);



  // [ 2 ] GET PREVIOUS RENDER TARGET
  //---------------------------------
  if FAILED(pDevice.GetRenderTarget(0, pPrevSurf)) then
  begin
    // Couldn't retrieve the current render target (for restoration later on)
    OutputDebugString('HDRScene::RenderScene() - Could not retrieve a reference to the previous render target.'#10);
    Exit;
  end;



  // [ 3 ] SET NEW RENDER TARGET
  //----------------------------
  if FAILED(HDRScene.g_pTexScene.GetSurfaceLevel(0, pRTSurf)) then
  begin
    // Bad news! couldn't get a reference to the HDR render target. Most
    // Likely due to a failed/corrupt resource creation stage.
    OutputDebugString('HDRScene::RenderScene() - Could not get the top level surface for the HDR render target'#10);
    Exit;
  end;

  if FAILED(pDevice.SetRenderTarget(0, pRTSurf)) then
  begin
    // For whatever reason we can't set the HDR texture as the
    // the render target...
    OutputDebugString('HDRScene::RenderScene() - Could not set the HDR texture as a new render target.'#10);
    Exit;
  end;

  // It is worth noting that the colour used to clear the render target will
  // be considered for the luminance measurement stage.
  pDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, D3DCOLOR_ARGB(0, 64, 64, 192), 1.0, 0);



  // [ 4 ] RENDER THE HDR CUBE
  //--------------------------
  HDRScene.g_pCubeMesh.DrawSubset(0);



  // [ 5 ] DRAW THE OCCLUSION CUBE
  //------------------------------
  pDevice.SetPixelShader(nil);
  pDevice.SetVertexDeclaration(HDRScene.g_pOcclusionVSDecl);
  pDevice.SetVertexShader(HDRScene.g_pOcclusionVS);
  HDRScene.g_pOcclusionVSConsts.SetMatrix(pDevice, 'matWorldViewProj', HDRScene.g_mOcclusionMatrix);
  HDRScene.g_pOcclusionVSConsts.SetMatrix(pDevice, 'matInvTPoseWorld', HDRScene.g_mOcclusionNormals);

  // Due to the way that the mesh was authored, there is
  // only (and always) going to be 1 subset/group to render.
  HDRScene.g_pOcclusionMesh.DrawSubset(0);


  // [ 6 ] RESTORE PREVIOUS RENDER TARGET
  //-------------------------------------
  pDevice.SetRenderTarget(0, pPrevSurf);



  // [ 7 ] RELEASE TEMPORARY REFERENCES
  //-----------------------------------
  SAFE_RELEASE(pRTSurf);
  SAFE_RELEASE(pPrevSurf);


  Result:= S_OK;
end;



//--------------------------------------------------------------------------------------
//  UpdateScene( )
//
//      DESC:
//          An entry point for updating various parameters and internal data on a
//          per-frame basis.
//
//      PARAMS:
//          pDevice     : The currently active device
//          fTime       : The number of milliseconds elapsed since the start of execution
//          pCamera     : The arcball based camera that the end-user controls
//
//      NOTES:
//          n/a
//
//--------------------------------------------------------------------------------------
function UpdateScene(const pDevice: IDirect3DDevice9; fTime: Single; const pCamera: CModelViewerCamera): HRESULT;
var
  matWorld, matTemp, m: TD3DXMatrixA16;
begin
  // The HDR cube in the middle of the scene never changes position in world
  // space, but must respond to view changes.
  // HDRScene.g_mCubeMatrix := (*pCamera.GetViewMatrix) * (*pCamera.GetProjMatrix);
  D3DXMatrixMultiply(HDRScene.g_mCubeMatrix, pCamera.GetViewMatrix^, pCamera.GetProjMatrix^);

  // The occlusion cube must be slightly larger than the inner HDR cube, so
  // a scaling constant is applied to the world matrix.
  D3DXMatrixIdentity(matTemp);
  D3DXMatrixScaling(matTemp, 2.5, 2.5, 2.5);
  D3DXMatrixMultiply(matWorld, matTemp, pCamera.GetWorldMatrix^); //@matWorld);

  // The occlusion cube contains lighting normals, so for the shader to operate
  // on them correctly, the inverse transpose of the world matrix is needed.
  D3DXMatrixIdentity(matTemp);
  D3DXMatrixInverse(matTemp, nil, matWorld);
  D3DXMatrixTranspose(HDRScene.g_mOcclusionNormals, matTemp);

  // HDRScene.g_mOcclusionMatrix := matWorld * (*pCamera.GetViewMatrix) * (*pCamera.GetProjMatrix);
  D3DXMatrixMultiply(m, pCamera.GetViewMatrix^, pCamera.GetProjMatrix^);
  D3DXMatrixMultiply(HDRScene.g_mOcclusionMatrix, matWorld, m);

  Result:= S_OK;
end;



//--------------------------------------------------------------------------------------
//  GetOutputTexture( )
//
//      DESC:
//          The results of this modules rendering are used as inputs to several
//          other parts of the rendering pipeline. As such it is necessary to obtain
//          a reference to the internally managed texture.
//
//      PARAMS:
//          pTexture    : Should be NULL on entry, will be a valid reference on exit
//
//      NOTES:
//          The code that requests the reference is responsible for releasing their
//          copy of the texture as soon as they are finished using it.
//
//--------------------------------------------------------------------------------------
function GetOutputTexture(out pTexture: IDirect3DTexture9): HRESULT;
begin
  // [ 0 ] ERASE ANY DATA IN THE INPUT
  //----------------------------------
  //SAFE_RELEASE(pTexture);

  // [ 1 ] COPY THE PRIVATE REFERENCE
  //---------------------------------
  pTexture := HDRScene.g_pTexScene;

  // [ 2 ] INCREMENT THE REFERENCE COUNT..
  //--------------------------------------
  //(*pTexture).AddRef();

  Result:= S_OK;
end;



//--------------------------------------------------------------------------------------
//  DrawToScreen( )
//
//      DESC:
//          Part of the GUI in this application displays the "raw" HDR data as part
//          of the process. This function places the texture, created by this
//          module, in the correct place on the screen.
//
//      PARAMS:
//          pDevice     : The device to be drawn to.
//          pFont       : The font to use when annotating the display
//          pTextSprite : Used with the font for more efficient rendering
//          pArrowTex   : Stores the 4 (up/down/left/right) icons used in the GUI
//
//      NOTES:
//          n/a
//
//--------------------------------------------------------------------------------------
function DrawToScreen(const pDevice: IDirect3DDevice9; const pFont: ID3DXFont;
  const pTextSprite: ID3DXSprite; const pArrowTex: IDirect3DTexture9): HRESULT;
var
  pSurf: IDirect3DSurface9;
  d: TD3DSurfaceDesc;
  fCellWidth, fCellHeight: Single;
  txtHelper: CDXUTTextHelper;
  v: array[0..3] of HDRScene.TLVertex;
  fLumCellSize: Single;
  fLumStartX: Single;
  str: array[0..99] of WideChar;
begin

  // [ 0 ] GATHER NECESSARY INFORMATION
  //-----------------------------------
  if FAILED(pDevice.GetRenderTarget(0, pSurf)) then
  begin
    // Couldn't get the current render target!
    OutputDebugString('HDRScene::DrawToScreen() - Could not get current render target to extract dimensions.'#10);
    Result:= E_FAIL;
    Exit;
  end;

  pSurf.GetDesc(d);
  pSurf := nil;

  // Cache the dimensions as floats for later use
  fCellWidth := ( d.Width - 48.0 ) / 4.0;
  fCellHeight := ( d.Height - 36.0 ) / 4.0;

  txtHelper := CDXUTTextHelper.Create(pFont, pTextSprite, 12);
  txtHelper.SetForegroundColor(D3DXColor(1.0, 0.5, 0.0, 1.0));

  // [ 1 ] CREATE TILE GEOMETRY
  //---------------------------
  v[0].p := D3DXVector4(0.0,         fCellHeight + 16.0,               0.0, 1.0);
  v[1].p := D3DXVector4(fCellWidth,  fCellHeight + 16.0,               0.0, 1.0);
  v[2].p := D3DXVector4(0.0,         ( 2.0 * fCellHeight ) + 16.0,     0.0, 1.0);
  v[3].p := D3DXVector4(fCellWidth,  ( 2.0 * fCellHeight ) + 16.0,     0.0, 1.0);

  v[0].t := D3DXVector2(0.0, 0.0);
  v[1].t := D3DXVector2(1.0, 0.0);
  v[2].t := D3DXVector2(0.0, 1.0);
  v[3].t := D3DXVector2(1.0, 1.0);

  // [ 2 ] DISPLAY TILE ON SCREEN
  //-----------------------------
  pDevice.SetVertexShader(nil);
  pDevice.SetFVF(HDRScene.FVF_TLVERTEX);
  pDevice.SetTexture(0, HDRScene.g_pTexScene);
  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(HDRScene.TLVertex));

  // [ 3 ] RENDER CONNECTING ARROWS
  //-------------------------------
  pDevice.SetTexture(0, pArrowTex);

  v[0].p := D3DXVector4((fCellWidth / 2.0) - 8.0,   fCellHeight,               0.0, 1.0);
  v[1].p := D3DXVector4((fCellWidth / 2.0) + 8.0,   fCellHeight,               0.0, 1.0);
  v[2].p := D3DXVector4((fCellWidth / 2.0) - 8.0,   fCellHeight + 16.0,        0.0, 1.0);
  v[3].p := D3DXVector4((fCellWidth / 2.0) + 8.0,   fCellHeight + 16.0,        0.0, 1.0);

  v[0].t := D3DXVector2(0.0,  0.0);
  v[1].t := D3DXVector2(0.25, 0.0);
  v[2].t := D3DXVector2(0.0,  1.0);
  v[3].t := D3DXVector2(0.25, 1.0);

  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(HDRScene.TLVertex));

  v[0].p := D3DXVector4(fCellWidth,          fCellHeight + 8.0 + (fCellHeight / 2.0),      0.0, 1.0);
  v[1].p := D3DXVector4(fCellWidth + 16.0,   fCellHeight + 8.0 + (fCellHeight / 2.0),      0.0, 1.0);
  v[2].p := D3DXVector4(fCellWidth,          fCellHeight + 24.0 + (fCellHeight / 2.0),     0.0, 1.0);
  v[3].p := D3DXVector4(fCellWidth + 16.0,   fCellHeight + 24.0 + (fCellHeight / 2.0),     0.0, 1.0);

  v[0].t := D3DXVector2(0.25, 0.0);
  v[1].t := D3DXVector2(0.50, 0.0);
  v[2].t := D3DXVector2(0.25, 1.0);
  v[3].t := D3DXVector2(0.50, 1.0);

  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(HDRScene.TLVertex));

  fLumCellSize := ( ( d.Height - ( (2.0 * fCellHeight) + 32.0 ) ) - 32.0 ) / 3.0;
  fLumStartX := (fCellWidth + 16.0) - ((2.0 * fLumCellSize) + 32.0);

  v[0].p := D3DXVector4(fLumStartX + (fLumCellSize / 2.0) - 8.0,    ( 2.0 * fCellHeight ) + 16.0,     0.0, 1.0);
  v[1].p := D3DXVector4(fLumStartX + (fLumCellSize / 2.0) + 8.0,    ( 2.0 * fCellHeight ) + 16.0,     0.0, 1.0);
  v[2].p := D3DXVector4(fLumStartX + (fLumCellSize / 2.0) - 8.0,    ( 2.0 * fCellHeight ) + 32.0,     0.0, 1.0);
  v[3].p := D3DXVector4(fLumStartX + (fLumCellSize / 2.0) + 8.0,    ( 2.0 * fCellHeight ) + 32.0,     0.0, 1.0);

  v[0].t := D3DXVector2(0.50, 0.0);
  v[1].t := D3DXVector2(0.75, 0.0);
  v[2].t := D3DXVector2(0.50, 1.0);
  v[3].t := D3DXVector2(0.75, 1.0);

  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(HDRScene.TLVertex));

  // [ 4 ] ANNOTATE CELL
  //--------------------
  txtHelper._Begin;
  //begin
    txtHelper.SetInsertionPos(5, Trunc( 2.0*fCellHeight + 16.0 - 25.0 ));
    txtHelper.DrawTextLine('Source HDR Frame');

    HDRScene.g_pTexScene.GetLevelDesc(0, d);

    StringCchFormat(str, 100, '%dx%d', [d.Width, d.Height]);
    txtHelper.DrawTextLine(str);
  //end;
  txtHelper._End;
  txtHelper.Free;

  Result:= S_OK;
end;



//--------------------------------------------------------------------------------------
//  LoadMesh( )
//
//      DESC:
//          A utility method borrowed from the DXSDK samples. Loads a .X mesh into
//          an ID3DXMesh object for rendering.
//
//--------------------------------------------------------------------------------------
function LoadMesh(strFileName: PWideChar; out ppMesh: ID3DXMesh): HRESULT;
var
  pMesh: ID3DXMesh;
  str: array[0..MAX_PATH-1] of WideChar;
  rgdwAdjacency: PDWORD;
  pTempMesh: ID3DXMesh;
begin
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, strFileName);
  if V_Failed(Result) then Exit;

  Result := D3DXLoadMeshFromXW(str, D3DXMESH_MANAGED, DXUTGetD3DDevice, nil, nil, nil, nil, pMesh);
  if FAILED(Result) or (pMesh = nil) then Exit;

  // rgdwAdjacency := nil;

  // Make sure there are normals which are required for lighting
  if (pMesh.GetFVF and D3DFVF_NORMAL = 0) then
  begin
    Result := pMesh.CloneMeshFVF(pMesh.GetOptions, pMesh.GetFVF or D3DFVF_NORMAL, DXUTGetD3DDevice, pTempMesh);
    if FAILED(Result) then Exit;

    D3DXComputeNormals(pTempMesh, nil);

    //SAFE_RELEASE(pMesh);
    pMesh := pTempMesh;
  end;

  // Optimize the mesh to make it fast for the user's graphics card
  GetMem(rgdwAdjacency, SizeOf(DWORD)*pMesh.GetNumFaces*3);
  try
    // if (rgdwAdjacency = nil) then Result:= E_OUTOFMEMORY;
    V(pMesh.GenerateAdjacency(1e-6, rgdwAdjacency));
    V(pMesh.OptimizeInplace(D3DXMESHOPT_VERTEXCACHE, rgdwAdjacency, nil, nil, nil));
  finally
    FreeMem(rgdwAdjacency);
  end;

  ppMesh := pMesh;

  Result:= S_OK;
end;

end.

