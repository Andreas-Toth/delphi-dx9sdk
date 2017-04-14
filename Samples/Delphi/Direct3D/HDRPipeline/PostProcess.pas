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
 *  $Id: PostProcess.pas,v 1.5 2007/02/05 22:21:08 clootie Exp $
 *----------------------------------------------------------------------------*)
//======================================================================
//
//      HIGH DYNAMIC RANGE RENDERING DEMONSTRATION
//      Written by Jack Hoxley, November 2005
//
//======================================================================

{$I DirectX.inc}

unit PostProcess;

interface

uses
  Windows, Direct3D9, D3DX9;

// All post processing functionality is wrapped up, and consequently
// accessed via, the following namespace:
// namespace PostProcess


// This function creates the necessary resources for the
// functionality of this module.
function CreateResources(const pDevice: IDirect3DDevice9; const pDisplayDesc: TD3DSurfaceDesc): HRESULT;

// This provides the opposite functionality to the above
// 'CreateResources' - making sure that any allocated resources
// are correctly released.
function DestroyResources: HRESULT;

// The core function for this method - takes the HDR data from
// 'HDRScene' and applies the necessary steps to produce the
// post-processed input into the final image composition.
function PerformPostProcessing(const pDevice: IDirect3DDevice9): HRESULT;

// The final image composition requires the results of this modules
// work as an input texture. This function allows other modules to
// access the texture and use it as appropriate.
function GetTexture(out pTexture: IDirect3DTexture9): HRESULT;

// The following 4 pairs of functions allow the respective parameters
// to be exposed via the GUI. Because the actual GUI events are contained
// entirely in 'HDRDemo.cpp' these accessors are required:
function GetBrightPassThreshold: Single;
procedure SetBrightPassThreshold(const threshold: Single);

function GetGaussianMultiplier: Single;
procedure SetGaussianMultiplier(const multiplier: Single);

function GetGaussianMean: Single;
procedure SetGaussianMean(const mean: Single);

function GetGaussianStandardDeviation: Single;
procedure SetGaussianStandardDeviation(const sd: Single);

// This function takes all the intermediary steps created/used by
// the 'PerformPostProcessing' function (above) and displays them
// to the GUI. Also annotates the steps.
function DisplaySteps(const pDevice: IDirect3DDevice9; const pFont: ID3DXFont;
  const pTextSprite: ID3DXSprite; const pArrowTex: IDirect3DTexture9 ): HRESULT;

// A simple utility function that makes a guesstimate as to
// how much VRAM is being used by this modules key resources.
function CalculateResourceUsage: DWORD;


implementation


uses
  Math, DXUTcore, DXUTmisc, StrSafe,
  HDREnumeration, HDRScene;


//--------------------------------------------------------------------------------------
// Data Structure Definitions
//--------------------------------------------------------------------------------------
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
  g_pBrightPassTex: IDirect3DTexture9 = nil;          // The results of performing a bright pass on the original HDR imagery
  g_pDownSampledTex: IDirect3DTexture9 = nil;         // The scaled down version of the bright pass results
  g_pBloomHorizontal: IDirect3DTexture9 = nil;        // The horizontally blurred version of the downsampled texture
  g_pBloomVertical: IDirect3DTexture9 = nil;          // The vertically blurred version of the horizontal blur
  g_fmtHDR: TD3DFormat = D3DFMT_UNKNOWN;              // What HDR (128 or 64) format is being used
  g_pBrightPassPS: IDirect3DPixelShader9 = nil;       // Represents the bright pass processing
  g_pBrightPassConstants: ID3DXConstantTable = nil;
  g_pDownSamplePS: IDirect3DPixelShader9 = nil;       // Represents the downsampling processing
  g_pDownSampleConstants: ID3DXConstantTable = nil;
  g_pHBloomPS: IDirect3DPixelShader9 = nil;           // Performs the first stage of the bloom rendering
  g_pHBloomConstants: ID3DXConstantTable = nil;
  g_pVBloomPS: IDirect3DPixelShader9 = nil;           // Performs the second stage of the bloom rendering
  g_pVBloomConstants: ID3DXConstantTable = nil;
  g_BrightThreshold: Single = 0.8;                    // A configurable parameter into the pixel shader
  g_GaussMultiplier: Single = 0.4;                    // Default multiplier
  g_GaussMean: Single = 0.0;                          // Default mean for gaussian distribution
  g_GaussStdDev: Single = 0.8;                        // Default standard deviation for gaussian distribution


//--------------------------------------------------------------------------------------
// Function Prototypes
//--------------------------------------------------------------------------------------
function RenderToTexture(const pDev: IDirect3DDevice9): HRESULT; forward;
function ComputeGaussianValue(x: Single; mean: Single; std_deviation: Single): Single; forward;


    
//--------------------------------------------------------------------------------------
//  CreateResources( )
//
//      DESC:
//          This function creates all the necessary resources to produce the post-
//          processing effect for the HDR input. When this function completes successfully
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
  pCode: ID3DXBuffer;
  str: array[0..MAX_PATH-1] of WideChar; 
begin

  // [ 0 ] GATHER NECESSARY INFORMATION
  //-----------------------------------

  Result := V(HDREnumeration.FindBestHDRFormat(PostProcess.g_fmtHDR));
  if FAILED(Result) then
  begin
    // High Dynamic Range Rendering is not supported on this device!
    OutputDebugString('PostProcess::CreateResources() - Current hardware does not allow HDR rendering!'#10);
    Exit;
  end;



  // [ 1 ] CREATE BRIGHT PASS TEXTURE
  //---------------------------------
  // Bright pass texture is 1/2 the size of the original HDR render target.
  // Part of the pixel shader performs a 2x2 downsampling. The downsampling
  // is intended to reduce the number of pixels that need to be worked on -
  // in general, HDR pipelines tend to be fill-rate heavy.
  Result := V(pDevice.CreateTexture(
                          pDisplayDesc.Width div 2, pDisplayDesc.Height div 2,
                          1, D3DUSAGE_RENDERTARGET, PostProcess.g_fmtHDR,
                          D3DPOOL_DEFAULT, PostProcess.g_pBrightPassTex, nil));
  if FAILED(Result) then
  begin
    // We couldn't create the texture - lots of possible reasons for this...
    OutputDebugString('PostProcess::CreateResources() - Could not create bright-pass render target. Examine D3D Debug Output for details.'#10);
    Exit;
  end;


  // [ 2 ] CREATE BRIGHT PASS PIXEL SHADER
  //--------------------------------------
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'Shader Code\PostProcessing.psh');
  if V_Failed(Result) then Exit;

  Result := V(D3DXCompileShaderFromFileW(
                                          str,
                                          nil, nil,
                                          'BrightPass',
                                          'ps_2_0',
                                          0,
                                          @pCode,
                                          nil,
                                          @PostProcess.g_pBrightPassConstants
                                       ));
  if FAILED(Result) then
  begin
    // Couldn't compile the shader, use the 'compile_shaders.bat' script
    // in the 'Shader Code' folder to get a proper compile breakdown.
    OutputDebugString('PostProcess::CreateResources() - Compiling of ''BrightPass'' from ''PostProcessing.psh'' failed!'#10);
    Exit;
  end;

  Result := V(pDevice.CreatePixelShader(PDWORD(pCode.GetBufferPointer), PostProcess.g_pBrightPassPS));
  if FAILED(Result) then
  begin
    // Couldn't turn the compiled shader into an actual, usable, pixel shader!
    OutputDebugString('PostProcess::CreateResources() - Could not create a pixel shader object for ''BrightPass''.'#10);
    pCode := nil;
    Exit;
  end;

  pCode := nil;



  // [ 3 ] CREATE DOWNSAMPLED TEXTURE
  //---------------------------------
  // This render target is 1/8th the size of the original HDR image (or, more
  // importantly, 1/4 the size of the bright-pass). The downsampling pixel
  // shader performs a 4x4 downsample in order to reduce the number of pixels
  // that are sent to the horizontal/vertical blurring stages.
  Result := V(pDevice.CreateTexture(
                          pDisplayDesc.Width div 8, pDisplayDesc.Height div 8,
                          1, D3DUSAGE_RENDERTARGET, PostProcess.g_fmtHDR,
                          D3DPOOL_DEFAULT, PostProcess.g_pDownSampledTex, nil));
  if FAILED(Result) then
  begin
    // We couldn't create the texture - lots of possible reasons for this...
    OutputDebugString('PostProcess::CreateResources() - Could not create downsampling render target. Examine D3D Debug Output for details.'#10);
    Exit;
  end;


  // [ 3 ] CREATE DOWNSAMPLING PIXEL SHADER
  //---------------------------------------
  Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, 'Shader Code\PostProcessing.psh');
  if V_Failed(Result) then Exit;

  Result := V(D3DXCompileShaderFromFileW(
                                          str,
                                          nil, nil,
                                          'DownSample',
                                          'ps_2_0',
                                          0,
                                          @pCode,
                                          nil,
                                          @PostProcess.g_pDownSampleConstants
                                        ));
  if FAILED(Result) then
  begin
    // Couldn't compile the shader, use the 'compile_shaders.bat' script
    // in the 'Shader Code' folder to get a proper compile breakdown.
    OutputDebugString('PostProcess::CreateResources() - Compiling of ''DownSample'' from ''PostProcessing.psh'' failed!'#10);
    Exit;
  end;

  Result := V(pDevice.CreatePixelShader(PDWORD(pCode.GetBufferPointer), PostProcess.g_pDownSamplePS));
  if FAILED(Result) then
  begin
    // Couldn't turn the compiled shader into an actual, usable, pixel shader!
    OutputDebugString('PostProcess::CreateResources() - Could not create a pixel shader object for ''DownSample''.'#10);
    pCode := nil;
    Exit;
  end;

  pCode := nil;



  // [ 4 ] CREATE HORIZONTAL BLOOM TEXTURE
  //--------------------------------------
  // The horizontal bloom texture is the same dimension as the down sample
  // render target. Combining a 4x4 downsample operation as well as a
  // horizontal blur leads to a prohibitively high number of texture reads.
  Result := V(pDevice.CreateTexture(
                          pDisplayDesc.Width div 8, pDisplayDesc.Height div 8,
                          1, D3DUSAGE_RENDERTARGET, PostProcess.g_fmtHDR,
                          D3DPOOL_DEFAULT, PostProcess.g_pBloomHorizontal, nil));
  if FAILED(Result) then
  begin
    // We couldn't create the texture - lots of possible reasons for this...
    OutputDebugString('PostProcess::CreateResources() - Could not create horizontal bloom render target. Examine D3D Debug Output for details.'#10);
    Exit;
  end;

  // [ 5 ] CREATE HORIZONTAL BLOOM PIXEL SHADER
  //-------------------------------------------
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'Shader Code\PostProcessing.psh');
  if V_Failed(Result) then Exit;

  Result := V(D3DXCompileShaderFromFileW(
                                          str,
                                          nil, nil,
                                          'HorizontalBlur',
                                          'ps_2_0',
                                          0,
                                          @pCode,
                                          nil,
                                          @PostProcess.g_pHBloomConstants
                                      ));
  if FAILED(Result) then
  begin
    // Couldn't compile the shader, use the 'compile_shaders.bat' script
    // in the 'Shader Code' folder to get a proper compile breakdown.
    OutputDebugString('PostProcess::CreateResources() - Compiling of ''HorizontalBlur'' from ''PostProcessing.psh'' failed!'#10);
    Exit;
  end;

  Result := V(pDevice.CreatePixelShader(PDWORD(pCode.GetBufferPointer), PostProcess.g_pHBloomPS));
  if FAILED(Result) then
  begin
    // Couldn't turn the compiled shader into an actual, usable, pixel shader!
    OutputDebugString('PostProcess::CreateResources() - Could not create a pixel shader object for ''HorizontalBlur''.'#10);
    pCode := nil;
    Exit;
  end;

  pCode := nil;

  // [ 6 ] CREATE VERTICAL BLOOM TEXTURE
  //------------------------------------
  // The vertical blur texture must be the same size as the horizontal blur texture
  // so as to get a correct 2D distribution pattern.
  Result := V(pDevice.CreateTexture(
                          pDisplayDesc.Width div 8, pDisplayDesc.Height div 8,
                          1, D3DUSAGE_RENDERTARGET, PostProcess.g_fmtHDR,
                          D3DPOOL_DEFAULT, PostProcess.g_pBloomVertical, nil));
  if FAILED(Result) then
  begin
    // We couldn't create the texture - lots of possible reasons for this...
    OutputDebugString('PostProcess::CreateResources() - Could not create vertical bloom render target. Examine D3D Debug Output for details.'#10);
    Exit;
  end;


  // [ 7 ] CREATE VERTICAL BLOOM PIXEL SHADER
  //-----------------------------------------
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'Shader Code\PostProcessing.psh');
  if V_Failed(Result) then Exit;

  Result := V(D3DXCompileShaderFromFileW(
                                         str,
                                         nil, nil,
                                         'VerticalBlur',
                                         'ps_2_0',
                                         0,
                                         @pCode,
                                         nil,
                                         @PostProcess.g_pVBloomConstants
                                      ));
  if FAILED(Result) then
  begin
    // Couldn't compile the shader, use the 'compile_shaders.bat' script
    // in the 'Shader Code' folder to get a proper compile breakdown.
    OutputDebugString('PostProcess::CreateResources() - Compiling of ''VerticalBlur'' from ''PostProcessing.psh'' failed!'#10);
    Exit;
  end;

  Result := V(pDevice.CreatePixelShader(PDWORD(pCode.GetBufferPointer), PostProcess.g_pVBloomPS));
  if FAILED(Result) then
  begin
    // Couldn't turn the compiled shader into an actual, usable, pixel shader!
    OutputDebugString('PostProcess::CreateResources() - Could not create a pixel shader object for ''VerticalBlur''.'#10);
    pCode := nil;
    Exit;
  end;

  pCode := nil;
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
  SAFE_RELEASE(g_pBrightPassTex);
  SAFE_RELEASE(g_pDownSampledTex);
  SAFE_RELEASE(g_pBloomHorizontal);
  SAFE_RELEASE(g_pBloomVertical);

  SAFE_RELEASE(g_pBrightPassPS);
  SAFE_RELEASE(g_pBrightPassConstants);

  SAFE_RELEASE(g_pDownSamplePS);
  SAFE_RELEASE(g_pDownSampleConstants);

  SAFE_RELEASE(g_pHBloomPS);
  SAFE_RELEASE(g_pHBloomConstants);

  SAFE_RELEASE(g_pVBloomPS);
  SAFE_RELEASE(g_pVBloomConstants);

  Result:= S_OK;
end;



//--------------------------------------------------------------------------------------
//  PerformPostProcessing( )
//
//      DESC:
//          This is the core function for this module - it takes the raw HDR image
//          generated by the 'HDRScene' component and puts it through 4 post
//          processing stages - to end up with a bloom effect on the over-exposed
//          (HDR) parts of the image.
//
//      PARAMS:
//          pDevice : The device that will be rendered to
//
//      NOTES:
//          n/a
//
//--------------------------------------------------------------------------------------
function PerformPostProcessing(const pDevice: IDirect3DDevice9): HRESULT;
var
  pHDRSource: IDirect3DTexture9;
  pBrightPassSurf: IDirect3DSurface9;
  offsets: array[0..3] of TD3DXVector4;
  srcDesc: TD3DSurfaceDesc;
  sU, sV: Single;
  pDownSampleSurf: IDirect3DSurface9;
  destDesc: TD3DSurfaceDesc;
  dsOffsets: array[0..15] of TD3DXVector4;
  idx: Integer;
  i, j: Integer;
  pHBloomSurf: IDirect3DSurface9;
  // Configure the sampling offsets and their weights
  HBloomWeights: array[0..8] of Single;
  HBloomOffsets: array[0..8] of Single;
  VBloomWeights: array[0..8] of Single;
  VBloomOffsets: array[0..8] of Single;
  x: Single;
  pVBloomSurf: IDirect3DSurface9;
begin
  Result:= E_FAIL;

  // [ 0 ] BRIGHT PASS
  //------------------
  if FAILED(HDRScene.GetOutputTexture(pHDRSource)) then
  begin
    // Couldn't get the input - means that none of the subsequent
    // work is worth attempting!
    OutputDebugString('PostProcess.PerformPostProcessing - Unable to retrieve source HDR information!'#10);
    Exit;
  end;

  if FAILED(PostProcess.g_pBrightPassTex.GetSurfaceLevel(0, pBrightPassSurf)) then
  begin
    // Can't get the render target. Not good news!
    OutputDebugString('PostProcess::PerformPostProcessing() - Couldn''t retrieve top level surface for bright pass render target.'#10);
    Exit;
  end;

  pDevice.SetRenderTarget(0, pBrightPassSurf);         // Configure the output of this stage
  pDevice.SetTexture(0, pHDRSource);                   // Configure the input..
  pDevice.SetPixelShader(PostProcess.g_pBrightPassPS);
  PostProcess.g_pBrightPassConstants.SetFloat(pDevice, 'fBrightPassThreshold', PostProcess.g_BrightThreshold);

  // We need to compute the sampling offsets used for this pass.
  // A 2x2 sampling pattern is used, so we need to generate 4 offsets

  // Find the dimensions for the source data
  pHDRSource.GetLevelDesc(0, srcDesc);

  // Because the source and destination are NOT the same sizes, we
  // need to provide offsets to correctly map between them.
  sU := 1.0 / srcDesc.Width;
  sV := 1.0 / srcDesc.Height;

  // The last two components (z,w) are unused. This makes for simpler code, but if
  // constant-storage is limited then it is possible to pack 4 offsets into 2 float4's
  offsets[0] := D3DXVector4(-0.5 * sU,  0.5 * sV, 0.0, 0.0);
  offsets[1] := D3DXVector4( 0.5 * sU,  0.5 * sV, 0.0, 0.0);
  offsets[2] := D3DXVector4(-0.5 * sU, -0.5 * sV, 0.0, 0.0);
  offsets[3] := D3DXVector4( 0.5 * sU, -0.5 * sV, 0.0, 0.0);


  PostProcess.g_pBrightPassConstants.SetVectorArray(pDevice, 'tcDownSampleOffsets', @offsets, 4);

  RenderToTexture(pDevice);



  // [ 1 ] DOWN SAMPLE
  //------------------
  if FAILED(PostProcess.g_pDownSampledTex.GetSurfaceLevel(0, pDownSampleSurf)) then
  begin
    // Can't get the render target. Not good news!
    OutputDebugString('PostProcess::PerformPostProcessing() - Couldn''t retrieve top level surface for down sample render target.'#10);
    Exit;
  end;

  pDevice.SetRenderTarget(0, pDownSampleSurf);
  pDevice.SetTexture(0, PostProcess.g_pBrightPassTex);
  pDevice.SetPixelShader(PostProcess.g_pDownSamplePS);

  // We need to compute the sampling offsets used for this pass.
  // A 4x4 sampling pattern is used, so we need to generate 16 offsets

  // Find the dimensions for the source data
  PostProcess.g_pBrightPassTex.GetLevelDesc(0, srcDesc);

  // Find the dimensions for the destination data
  pDownSampleSurf.GetDesc(destDesc);

  // Compute the offsets required for down-sampling. If constant-storage space
  // is important then this code could be packed into 8xFloat4's. The code here
  // is intentionally less efficient to aid readability...
  idx := 0;
  for i := -2 to 1 do
  begin
    for j := -2 to 1 do
    begin
      dsOffsets[idx] := D3DXVector4(
                                  (i + 0.5) * (1.0 / destDesc.Width),
                                  (j + 0.5) * (1.0 / destDesc.Height),
                                  0.0, // unused
                                  0.0  // unused
                              );
      Inc(idx);
    end;
  end;

  PostProcess.g_pDownSampleConstants.SetVectorArray(pDevice, 'tcDownSampleOffsets', @dsOffsets, 16);

  RenderToTexture(pDevice);


  // [ 2 ] BLUR HORIZONTALLY
  //------------------------
  if FAILED(PostProcess.g_pBloomHorizontal.GetSurfaceLevel(0, pHBloomSurf)) then
  begin
    // Can't get the render target. Not good news!
    OutputDebugString('PostProcess::PerformPostProcessing() - Couldn''t retrieve top level surface for horizontal bloom render target.'#10);
    Exit;
  end;

  pDevice.SetRenderTarget(0, pHBloomSurf);
  pDevice.SetTexture(0, PostProcess.g_pDownSampledTex);
  pDevice.SetPixelShader(PostProcess.g_pHBloomPS);

  // Configure the sampling offsets and their weights
  // float HBloomWeights[9];
  // float HBloomOffsets[9];

  for i := 0 to 8 do
  begin
    // Compute the offsets. We take 9 samples - 4 either side and one in the middle:
    //     i =  0,  1,  2,  3, 4,  5,  6,  7,  8
    //Offset = -4, -3, -2, -1, 0, +1, +2, +3, +4
    HBloomOffsets[i] := (i - 4.0) * (1.0 / destDesc.Width);

    // 'x' is just a simple alias to map the [0,8] range down to a [-1,+1]
    x := (i - 4.0) / 4.0;

    // Use a gaussian distribution. Changing the standard-deviation
    // (second parameter) as well as the amplitude (multiplier) gives
    // distinctly different results.
    HBloomWeights[i] := g_GaussMultiplier * ComputeGaussianValue(x, g_GaussMean, g_GaussStdDev);
  end;

  // Commit both arrays to the device:
  PostProcess.g_pHBloomConstants.SetFloatArray(pDevice, 'HBloomWeights', @HBloomWeights, 9);
  PostProcess.g_pHBloomConstants.SetFloatArray(pDevice, 'HBloomOffsets', @HBloomOffsets, 9);

  RenderToTexture(pDevice);



  // [ 3 ] BLUR VERTICALLY
  //----------------------
  if FAILED(PostProcess.g_pBloomVertical.GetSurfaceLevel(0, pVBloomSurf)) then
  begin
    // Can't get the render target. Not good news!
    OutputDebugString('PostProcess::PerformPostProcessing() - Couldn''t retrieve top level surface for vertical bloom render target.'#10);
    Exit;
  end;

  pDevice.SetRenderTarget(0, pVBloomSurf);
  pDevice.SetTexture(0, PostProcess.g_pBloomHorizontal);
  pDevice.SetPixelShader(PostProcess.g_pVBloomPS);

  // Configure the sampling offsets and their weights

  // It is worth noting that although this code is almost identical to the
  // previous section ('H' weights, above) there is an important difference: destDesc.Height.
  // The bloom render targets are *not* square, such that you can't re-use the same offsets in
  // both directions.
  // float VBloomWeights[9];
  // float VBloomOffsets[9];

  for i := 0 to 8 do
  begin
    // Compute the offsets. We take 9 samples - 4 either side and one in the middle:
    //     i =  0,  1,  2,  3, 4,  5,  6,  7,  8
    //Offset = -4, -3, -2, -1, 0, +1, +2, +3, +4
    VBloomOffsets[i] := (i - 4.0) * (1.0 / destDesc.Height);

    // 'x' is just a simple alias to map the [0,8] range down to a [-1,+1]
    x := (i - 4.0) / 4.0;

    // Use a gaussian distribution. Changing the standard-deviation
    // (second parameter) as well as the amplitude (multiplier) gives
    // distinctly different results.
    VBloomWeights[i] := g_GaussMultiplier * ComputeGaussianValue(x, g_GaussMean, g_GaussStdDev);
  end;

  // Commit both arrays to the device:
  PostProcess.g_pVBloomConstants.SetFloatArray(pDevice, 'VBloomWeights', @VBloomWeights, 9);
  PostProcess.g_pVBloomConstants.SetFloatArray(pDevice, 'VBloomOffsets', @VBloomOffsets, 9);

  RenderToTexture(pDevice);



  // [ 4 ] CLEAN UP
  //---------------
  SAFE_RELEASE(pHDRSource);
  SAFE_RELEASE(pBrightPassSurf);
  SAFE_RELEASE(pDownSampleSurf);
  SAFE_RELEASE(pHBloomSurf);
  SAFE_RELEASE(pVBloomSurf);

  Result:= S_OK;
end;



//--------------------------------------------------------------------------------------
//  GetTexture( )
//
//      DESC:
//          The results generated by PerformPostProcessing() are required as an input
//          into the final image composition. Because that final stage is located
//          in another code module, it must be able to safely access the correct
//          texture stored internally within this module.
//
//      PARAMS:
//          pTexture    : Should be NULL on entry, will be a valid reference on exit
//
//      NOTES:
//          The code that requests the reference is responsible for releasing their
//          copy of the texture as soon as they are finished using it.
//
//--------------------------------------------------------------------------------------
function GetTexture(out pTexture: IDirect3DTexture9): HRESULT;
begin
  // [ 0 ] ERASE ANY DATA IN THE INPUT
  //----------------------------------
  //SAFE_RELEASE( *pTexture );

  // [ 1 ] COPY THE PRIVATE REFERENCE
  //---------------------------------
  pTexture := PostProcess.g_pBloomVertical;

  // [ 2 ] INCREMENT THE REFERENCE COUNT..
  //--------------------------------------
  //(*pTexture).AddRef();

  Result:= S_OK;
end;



//--------------------------------------------------------------------------------------
//  GetBrightPassThreshold( )
//
//      DESC:
//          Returns the current bright pass threshold, as used by the PostProcessing.psh
//          pixel shader.
//
//--------------------------------------------------------------------------------------
function GetBrightPassThreshold: Single;
begin
  Result:= PostProcess.g_BrightThreshold;
end;



//--------------------------------------------------------------------------------------
//  SetBrightPassThreshold( )
//
//      DESC:
//          Allows another module to configure the threshold at which a pixel is
//          considered to be "bright" and thus get fed into the post-processing
//          part of the pipeline.
//
//      PARAMS:
//          threshold   : The new value to be used
//
//--------------------------------------------------------------------------------------
procedure SetBrightPassThreshold(const threshold: Single);
begin
  PostProcess.g_BrightThreshold := threshold;
end;



//--------------------------------------------------------------------------------------
//  GetGaussianMultiplier( )
//
//      DESC:
//          Returns the multiplier used to scale the gaussian distribution.
//
//--------------------------------------------------------------------------------------
function GetGaussianMultiplier: Single;
begin
  Result:= PostProcess.g_GaussMultiplier;
end;



//--------------------------------------------------------------------------------------
//  SetGaussianMultiplier( )
//
//      DESC:
//          Allows another module to configure the general multiplier. Not strictly
//          part of the gaussian distribution, but a useful factor to help control the
//          intensity of the bloom.
//
//      PARAMS:
//          multiplier   : The new value to be used
//
//--------------------------------------------------------------------------------------
procedure SetGaussianMultiplier(const multiplier: Single);
begin
  PostProcess.g_GaussMultiplier := multiplier;
end;



//--------------------------------------------------------------------------------------
//  GetGaussianMean( )
//
//      DESC:
//          Returns the mean used to compute the gaussian distribution for the bloom
//
//--------------------------------------------------------------------------------------
function GetGaussianMean: Single;
begin
  Result:= PostProcess.g_GaussMean;
end;



//--------------------------------------------------------------------------------------
//  SetGaussianMean( )
//
//      DESC:
//          Allows another module to specify where the peak will be in the gaussian
//          distribution. Values should be between -1 and +1; a value of 0 will be
//          best.
//
//      PARAMS:
//          mean   : The new value to be used
//
//--------------------------------------------------------------------------------------
procedure SetGaussianMean(const mean: Single);
begin
  PostProcess.g_GaussMean := mean;
end;



//--------------------------------------------------------------------------------------
//  GetGaussianStandardDeviation( )
//
//      DESC:
//          Returns the standard deviation used to construct the gaussian distribution
//          used by the horizontal/vertical bloom processing.
//
//--------------------------------------------------------------------------------------
function GetGaussianStandardDeviation: Single;
begin
  Result:= PostProcess.g_GaussStdDev;
end;



//--------------------------------------------------------------------------------------
//  SetGaussianStandardDeviation( )
//
//      DESC:
//          Allows another module to configure the standard deviation
//          used to generate a gaussian distribution. Should be between
//          0.0 and 1.0 for valid results.
//
//      PARAMS:
//          sd    : The new value to be used
//
//--------------------------------------------------------------------------------------
procedure SetGaussianStandardDeviation(const sd: Single);
begin
  PostProcess.g_GaussStdDev := sd;
end;



//--------------------------------------------------------------------------------------

//--------------------------------------------------------------------------------------
//  DisplaySteps( )
//
//      DESC:
//          Part of the GUI in this application displays the four stages that make up
//          the post-processing stage of the HDR rendering pipeline. This function
//          is responsible for making sure that each stage is drawn as expected.
//
//      PARAMS:
//          pDevice     : The device to be drawn to.
//          pFont       : The font used to annotate the display
//          pTextSprite : Used to improve the performance of text rendering
//          pArrowTex   : Stores the 4 (up/down/left/right) icons used in the GUI
//
//      NOTES:
//          n/a
//
//--------------------------------------------------------------------------------------
function DisplaySteps(const pDevice: IDirect3DDevice9; const pFont: ID3DXFont;
  const pTextSprite: ID3DXSprite; const pArrowTex: IDirect3DTexture9 ): HRESULT;
var
  pSurf: IDirect3DSurface9;
  d: TD3DSurfaceDesc;
  fW, fH: Single;
  fCellW, fCellH: Single;
  v: array[0..3] of PostProcess.TLVertex;
  txtHelper: CDXUTTextHelper;
  str: array[0..99] of WideChar;
begin
  // [ 0 ] COMMON INITIALIZATION
  //----------------------------
  if FAILED(pDevice.GetRenderTarget(0, pSurf)) then
  begin
    // Couldn't get the current render target!
    OutputDebugString('PostProcess::DisplaySteps() - Could not get current render target to extract dimensions.'#10);
    Result:= E_FAIL;
    Exit;
  end;

  pSurf.GetDesc(d);
  pSurf := nil;

  // Cache the dimensions as floats for later use
  fW := d.Width;
  fH := d.Height;

  fCellW := (fW - 48.0) / 4.0;
  fCellH := (fH - 36.0) / 4.0;

  // Fill out the basic TLQuad information - this
  // stuff doesn't change for each stage
  v[0].t := D3DXVector2(0.0, 0.0);
  v[1].t := D3DXVector2(1.0, 0.0);
  v[2].t := D3DXVector2(0.0, 1.0);
  v[3].t := D3DXVector2(1.0, 1.0);

  // Configure the device for it's basic states
  pDevice.SetVertexShader(nil);
  pDevice.SetFVF(FVF_TLVERTEX);
  pDevice.SetPixelShader(nil);

  txtHelper := CDXUTTextHelper.Create(pFont, pTextSprite, 12);
  txtHelper.SetForegroundColor(D3DXColor(1.0, 0.5, 0.0, 1.0));


  // [ 1 ] RENDER BRIGHT PASS STAGE
  //-------------------------------
  v[0].p := D3DXVector4(0.0,     0.0,      0.0, 1.0);
  v[1].p := D3DXVector4(fCellW,  0.0,      0.0, 1.0);
  v[2].p := D3DXVector4(0.0,     fCellH,   0.0, 1.0);
  v[3].p := D3DXVector4(fCellW,  fCellH,   0.0, 1.0);

  pDevice.SetTexture(0, PostProcess.g_pBrightPassTex);
  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(PostProcess.TLVertex));

  txtHelper._Begin;
  begin
    txtHelper.SetInsertionPos(5, Trunc(fCellH - 25.0));
    txtHelper.DrawTextLine('Bright-Pass');

    PostProcess.g_pBrightPassTex.GetLevelDesc(0, d);

    StringCchFormat(str, 100, '%dx%d', [d.Width, d.Height]);
    txtHelper.DrawTextLine(str);
  end;
  txtHelper._End;

  // [ 2 ] RENDER DOWNSAMPLED STAGE
  //-------------------------------
  v[0].p := D3DXVector4(fCellW + 16.0,          0.0,       0.0, 1.0);
  v[1].p := D3DXVector4((2.0 * fCellW) + 16.0,  0.0,       0.0, 1.0);
  v[2].p := D3DXVector4(fCellW + 16.0,          fCellH,    0.0, 1.0);
  v[3].p := D3DXVector4((2.0 * fCellW) + 16.0,  fCellH,    0.0, 1.0);

  pDevice.SetTexture(0, PostProcess.g_pDownSampledTex);
  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(PostProcess.TLVertex));

  txtHelper._Begin;
  begin
    txtHelper.SetInsertionPos(Trunc(fCellW + 16.0) + 5, Trunc(fCellH - 25.0));
    txtHelper.DrawTextLine('Down-Sampled');

    PostProcess.g_pDownSampledTex.GetLevelDesc(0, d);

    StringCchFormat(str, 100, '%dx%d', [d.Width, d.Height]);
    txtHelper.DrawTextLine(str);
  end;
  txtHelper._End;

  // [ 3 ] RENDER HORIZONTAL BLUR STAGE
  //-----------------------------------
  v[0].p := D3DXVector4((2.0 * fCellW) + 32.0,      0.0,       0.0, 1.0);
  v[1].p := D3DXVector4((3.0 * fCellW) + 32.0,      0.0,       0.0, 1.0);
  v[2].p := D3DXVector4((2.0 * fCellW) + 32.0,      fCellH,    0.0, 1.0);
  v[3].p := D3DXVector4((3.0 * fCellW) + 32.0,      fCellH,    0.0, 1.0);

  pDevice.SetTexture(0, PostProcess.g_pBloomHorizontal);
  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(PostProcess.TLVertex));

  txtHelper._Begin;
  begin
    txtHelper.SetInsertionPos(Trunc(2.0 * fCellW + 32.0) + 5, Trunc(fCellH - 25.0));
    txtHelper.DrawTextLine('Horizontal Blur');

    PostProcess.g_pBloomHorizontal.GetLevelDesc(0, d);

    StringCchFormat(str, 100, '%dx%d', [d.Width, d.Height]);
    txtHelper.DrawTextLine(str);
  end;
  txtHelper._End;

  // [ 4 ] RENDER VERTICAL BLUR STAGE
  //---------------------------------
  v[0].p := D3DXVector4((3.0 * fCellW) + 48.0,      0.0,       0.0, 1.0);
  v[1].p := D3DXVector4((4.0 * fCellW) + 48.0,      0.0,       0.0, 1.0);
  v[2].p := D3DXVector4((3.0 * fCellW) + 48.0,      fCellH,    0.0, 1.0);
  v[3].p := D3DXVector4((4.0 * fCellW) + 48.0,      fCellH,    0.0, 1.0);

  pDevice.SetTexture(0, PostProcess.g_pBloomVertical);
  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf( PostProcess.TLVertex ));

  txtHelper._Begin;
  begin
    txtHelper.SetInsertionPos(Trunc(3.0 * fCellW + 48.0) + 5, Trunc(fCellH - 25.0));
    txtHelper.DrawTextLine('Vertical Blur');

    PostProcess.g_pDownSampledTex.GetLevelDesc(0, d);

    StringCchFormat(str, 100, '%dx%d', [d.Width, d.Height]);
    txtHelper.DrawTextLine(str);
  end;
  txtHelper._End;
  txtHelper.Free;


  // [ 5 ] RENDER ARROWS
  //--------------------
  pDevice.SetTexture(0, pArrowTex);

  // Locate the "Left" Arrow:

  v[0].t := D3DXVector2(0.25, 0.0);
  v[1].t := D3DXVector2(0.50, 0.0);
  v[2].t := D3DXVector2(0.25, 1.0);
  v[3].t := D3DXVector2(0.50, 1.0);

  // Bright-Pass -> Down Sampled:

  v[0].p := D3DXVector4(fCellW,          (fCellH / 2.0) - 8.0,     0.0, 1.0);
  v[1].p := D3DXVector4(fCellW + 16.0,   (fCellH / 2.0) - 8.0,     0.0, 1.0);
  v[2].p := D3DXVector4(fCellW,          (fCellH / 2.0) + 8.0,     0.0, 1.0);
  v[3].p := D3DXVector4(fCellW + 16.0,   (fCellH / 2.0) + 8.0,     0.0, 1.0);

  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(PostProcess.TLVertex));

  // Down Sampled -> Horizontal Blur:

  v[0].p := D3DXVector4((2.0 * fCellW) + 16.0,  (fCellH / 2.0) - 8.0,     0.0, 1.0);
  v[1].p := D3DXVector4((2.0 * fCellW) + 32.0,  (fCellH / 2.0) - 8.0,     0.0, 1.0);
  v[2].p := D3DXVector4((2.0 * fCellW) + 16.0,  (fCellH / 2.0) + 8.0,     0.0, 1.0);
  v[3].p := D3DXVector4((2.0 * fCellW) + 32.0,  (fCellH / 2.0) + 8.0,     0.0, 1.0);

  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(PostProcess.TLVertex));

  // Horizontal Blur -> Vertical Blur:

  v[0].p := D3DXVector4((3.0 * fCellW) + 32.0,  (fCellH / 2.0) - 8.0,     0.0, 1.0);
  v[1].p := D3DXVector4((3.0 * fCellW) + 48.0,  (fCellH / 2.0) - 8.0,     0.0, 1.0);
  v[2].p := D3DXVector4((3.0 * fCellW) + 32.0,  (fCellH / 2.0) + 8.0,     0.0, 1.0);
  v[3].p := D3DXVector4((3.0 * fCellW) + 48.0,  (fCellH / 2.0) + 8.0,     0.0, 1.0);

  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(PostProcess.TLVertex));

  // Locate the "Down" arrow:

  v[0].t := D3DXVector2(0.50, 0.0);
  v[1].t := D3DXVector2(0.75, 0.0);
  v[2].t := D3DXVector2(0.50, 1.0);
  v[3].t := D3DXVector2(0.75, 1.0);

  // Vertical Blur -> Final Image Composition:

  v[0].p := D3DXVector4((3.5 * fCellW) + 40.0,  fCellH,            0.0, 1.0);
  v[1].p := D3DXVector4((3.5 * fCellW) + 56.0,  fCellH,            0.0, 1.0);
  v[2].p := D3DXVector4((3.5 * fCellW) + 40.0,  fCellH + 16.0,     0.0, 1.0);
  v[3].p := D3DXVector4((3.5 * fCellW) + 56.0,  fCellH + 16.0,     0.0, 1.0);

  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(PostProcess.TLVertex));

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
  d: TD3DSurfaceDesc;
begin
  usage := 0;

  if SUCCEEDED(g_pBrightPassTex.GetLevelDesc(0, d)) then
      usage := usage + ( ( d.Width * d.Height ) * DWORD(IfThen(PostProcess.g_fmtHDR = D3DFMT_A32B32G32R32F, 16, 8)));

  if SUCCEEDED(g_pDownSampledTex.GetLevelDesc(0, d)) then
      usage := usage + ( ( d.Width * d.Height ) * DWORD(IfThen(PostProcess.g_fmtHDR = D3DFMT_A32B32G32R32F,  16, 8)));

  if SUCCEEDED(g_pBloomHorizontal.GetLevelDesc(0, d)) then
      usage := usage + ( ( d.Width * d.Height ) * DWORD(IfThen(PostProcess.g_fmtHDR = D3DFMT_A32B32G32R32F,  16, 8)));

  if SUCCEEDED(g_pBloomVertical.GetLevelDesc(0, d)) then
      usage := usage + ( ( d.Width * d.Height ) * DWORD(IfThen(PostProcess.g_fmtHDR = D3DFMT_A32B32G32R32F,  16, 8)));

  Result:= usage;
end;
    


//--------------------------------------------------------------------------------------
//  RenderToTexture( )
//
//      DESC:
//          A simple utility function that draws, as a TL Quad, one texture to another
//          such that a pixel shader (configured before this function is called) can
//          operate on the texture. Used by MeasureLuminance() to perform the
//          downsampling and filtering.
//
//      PARAMS:
//          pDevice : The currently active device
//
//      NOTES:
//          n/a
//
//--------------------------------------------------------------------------------------
function RenderToTexture(const pDev: IDirect3DDevice9): HRESULT;
var
  desc: TD3DSurfaceDesc;
  pSurfRT: IDirect3DSurface9;
  fWidth, fHeight: Single;
  v: array[0..3] of PostProcess.TLVertex;
begin
  pDev.GetRenderTarget(0, pSurfRT);
  pSurfRT.GetDesc(desc);
  pSurfRT := nil;

  // To correctly map from texels->pixels we offset the coordinates
  // by -0.5f:
  fWidth := desc.Width - 0.5;
  fHeight := desc.Height - 0.5;

  // Now we can actually assemble the screen-space geometry
  // PostProcess::TLVertex v[4];

  v[0].p := D3DXVector4(-0.5, -0.5, 0.0, 1.0);
  v[0].t := D3DXVector2(0.0, 0.0);

  v[1].p := D3DXVector4(fWidth, -0.5, 0.0, 1.0);
  v[1].t := D3DXVector2(1.0, 0.0);

  v[2].p := D3DXVector4(-0.5, fHeight, 0.0, 1.0);
  v[2].t := D3DXVector2(0.0, 1.0);

  v[3].p := D3DXVector4(fWidth, fHeight, 0.0, 1.0);
  v[3].t := D3DXVector2(1.0, 1.0);

  // Configure the device and render..
  pDev.SetVertexShader(nil);
  pDev.SetFVF(PostProcess.FVF_TLVERTEX);
  pDev.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(PostProcess.TLVertex));

  Result:= S_OK;
end;


function ComputeGaussianValue(x: Single; mean: Single; std_deviation: Single): Single;
begin
  // The gaussian equation is defined as such:
  (*
                                                   -(x - mean)^2
                                                   -------------
                                  1.0               2*std_dev^2
      f(x,mean,std_dev) = -------------------- * e^
                          sqrt(2*pi*std_dev^2)

  *)

  Result:= ( 1.0 / sqrt(2.0 * D3DX_PI * std_deviation * std_deviation) )
            * exp( (-((x-mean)*(x-mean)))/(2.0 * std_deviation * std_deviation));
end;

end.

