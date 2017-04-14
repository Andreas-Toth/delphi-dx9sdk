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
 *  $Id: Luminance.pas,v 1.5 2007/02/05 22:21:08 clootie Exp $
 *----------------------------------------------------------------------------*)
//======================================================================
//
//      HIGH DYNAMIC RANGE RENDERING DEMONSTRATION
//      Written by Jack Hoxley, November 2005
//
//======================================================================

{$I DirectX.inc}

unit Luminance;

interface

uses
  Windows, Direct3D9, D3DX9;

// All functionality offered by this particular module
// is being wrapped up in a C++ namespace so as to make
// it clear what functions/etc.. belong together.
// namespace Luminance

// This function creates the various textures and shaders used
// to compute the overall luminance of a given scene.
function CreateResources(const pDevice: IDirect3DDevice9; const pDisplayDesc: TD3DSurfaceDesc): HRESULT;

// The functional opposite to the above function - it's job is
// to make sure that all resources are cleanly and safely tidied up.
function DestroyResources: HRESULT;

// This is the core function for this module - it will perform all
// of the necessary rendering and sampling to compute the 1x1
// luminance texture.
function MeasureLuminance(const pDevice: IDirect3DDevice9): HRESULT;

// This function will display all stages of the luminance chain
// so that the end-user can see exactly what happened.
function DisplayLuminance(const pDevice: IDirect3DDevice9; const pFont: ID3DXFont;
  const pTextSprite: ID3DXSprite; const pArrowTex: IDirect3DTexture9): HRESULT;

// The final, 1x1 texture, result of this module is needed to
// compute the final image that the user sees, as such other
// parts of this example need access to the luminance texture.
function GetLuminanceTexture(out pTex: IDirect3DTexture9): HRESULT;

// A simple statistic that reveals how much texture memory is
// used by this particular module.
function ComputeResourceUsage: DWORD;


implementation


uses
  Math, DXUT, DXUTcore, DXUTmisc, StrSafe,
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
// Namespace-Level Variables
//--------------------------------------------------------------------------------------
var
  g_pLumDispPS: IDirect3DPixelShader9 = nil;                          // PShader used to display the debug panel
  g_pLum1PS: IDirect3DPixelShader9 = nil;                             // PShader that does a 2x2 downsample and convert to greyscale
  g_pLum1PSConsts: ID3DXConstantTable = nil;                          // Interface to set the sampling points for the above PS
  g_pLum3x3DSPS: IDirect3DPixelShader9 = nil;                         // The PS that does each 3x3 downsample operation
  g_pLum3x3DSPSConsts: ID3DXConstantTable = nil;                      // Interface for the above PS
  const g_dwLumTextures = 6;                                          // How many luminance textures we're creating
                                                                      // Be careful when changing this value, higher than 6 might
                                                                      // require you to implement code that creates an additional
                                                                      // depth-stencil buffer due to the luminance textures dimensions
                                                                      // being greater than that of the default depth-stencil buffer.
var
  g_pTexLuminance: array[0..g_dwLumTextures-1] of IDirect3DTexture9;  // An array of the downsampled luminance textures
  g_fmtHDR: TD3DFormat = D3DFMT_UNKNOWN;                              // Should be either G32R32F or G16R16F depending on the hardware



//--------------------------------------------------------------------------------------
// Private Function Prototypes
//--------------------------------------------------------------------------------------
function RenderToTexture(const pDev: IDirect3DDevice9): HRESULT; forward;



//--------------------------------------------------------------------------------------
//  CreateResources( )
//
//      DESC:
//          This function creates the necessary texture chain for downsampling the
//          initial HDR texture to a 1x1 luminance texture.
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
  iTextureSize: Integer;
  i: Integer;
  str: array[0..MAX_PATH-1] of WideChar;
begin

  //[ 0 ] DECLARATIONS
  //------------------


  //[ 1 ] DETERMINE FP TEXTURE SUPPORT
  //----------------------------------
  Result := V(HDREnumeration.FindBestLuminanceFormat(Luminance.g_fmtHDR));
  if FAILED(Result) then
  begin
    // Bad news!
    OutputDebugString('Luminance::CreateResources() - Current hardware does not support HDR rendering!'#10);
    Exit;
  end;



  //[ 2 ] CREATE HDR RENDER TARGETS
  //-------------------------------
  iTextureSize := 1;
  for i := 0 to Luminance.g_dwLumTextures - 1 do
  begin
    // Create this element in the array
    Result := V(pDevice.CreateTexture(iTextureSize, iTextureSize, 1,
                                      D3DUSAGE_RENDERTARGET, Luminance.g_fmtHDR,
                                      D3DPOOL_DEFAULT, Luminance.g_pTexLuminance[i], nil));
    if FAILED(Result) then
    begin
      // Couldn't create this texture, probably best to inspect the debug runtime
      // for more information
      StringCchFormat(str, MAX_PATH, 'Luminance::CreateResources() : Unable to create luminance'+
                                     ' texture of %dx%d (Element %d of %d).'#10,
                                     [iTextureSize,
                                     iTextureSize,
                                     (i+1),
                                     Luminance.g_dwLumTextures]);
      OutputDebugStringW(str);
      Exit;
    end;

    // Increment for the next texture
    iTextureSize := iTextureSize * 3;
  end;



  //[ 3 ] CREATE GUI DISPLAY SHADER
  //-------------------------------
  // Because the intermediary luminance textures are stored as either G32R32F
  // or G16R16F, we need a pixel shader that can convert this to a more meaningful
  // greyscale ARGB value. This shader doesn't actually contribute to the
  // luminance calculations - just the way they are presented to the user via the GUI.
  Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, 'Shader Code\Luminance.psh');
  if V_Failed(Result) then Exit;

  Result := V(D3DXCompileShaderFromFileW(
                                         str,
                                         nil, nil,
                                         'LuminanceDisplay',
                                         'ps_2_0',
                                         0,
                                         @pCode,
                                         nil,
                                         nil
                                        ));
  if FAILED(Result) then
  begin
    // Couldn't compile the shader, use the 'compile_shaders.bat' script
    // in the 'Shader Code' folder to get a proper compile breakdown.
    OutputDebugString('Luminance::CreateResources() - Compiling of ''LuminanceDisplay'' from ''Luminance.psh'' failed!'#10);
    Exit;
  end;

  Result := V(pDevice.CreatePixelShader(PDWORD(pCode.GetBufferPointer), Luminance.g_pLumDispPS));
  if FAILED(Result) then
  begin
    // Couldn't turn the compiled shader into an actual, usable, pixel shader!
    OutputDebugString('Luminance::CreateResources() - Could not create a pixel shader object for ''LuminanceDisplay''.'#10);
    pCode := nil;
    Exit;
  end;

  pCode := nil;



  //[ 4 ] CREATE FIRST-PASS DOWNSAMPLE SHADER
  //-----------------------------------------
  // The first pass of down-sampling has to convert the RGB data to
  // a single luminance value before averaging over the kernel. This
  // is slightly different to the subsequent down-sampling shader.
  Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, 'Shader Code\Luminance.psh');
  if V_Failed(Result) then Exit;

  Result := V(D3DXCompileShaderFromFileW(
                                          str,
                                          nil, nil,
                                          'GreyScaleDownSample',
                                          'ps_2_0',
                                          0,
                                          @pCode,
                                          nil,
                                          @Luminance.g_pLum1PSConsts
                                      ));
  if FAILED(Result) then
  begin
    // Couldn't compile the shader, use the 'compile_shaders.bat' script
    // in the 'Shader Code' folder to get a proper compile breakdown.
    OutputDebugString('Luminance::CreateResources() - Compiling of ''GreyScaleDownSample'' from ''Luminance.psh'' failed!'#10);
    Exit;
  end;

  Result := V(pDevice.CreatePixelShader(PDWORD(pCode.GetBufferPointer), Luminance.g_pLum1PS));
  if FAILED(Result) then
  begin
    // Couldn't turn the compiled shader into an actual, usable, pixel shader!
    OutputDebugString('Luminance::CreateResources() - Could not create a pixel shader object for ''GreyScaleDownSample''.'#10);
    pCode := nil;
    Exit;
  end;

  pCode := nil;



  //[ 5 ] CREATE DOWNSAMPLING PIXEL SHADER
  //--------------------------------------
  // This down-sampling shader assumes that the incoming pixels are
  // already in G16R16F or G32R32F format, and of a paired luminance/maximum value.
  Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, 'Shader Code\Luminance.psh');
  if V_Failed(Result) then Exit;
  Result := V(D3DXCompileShaderFromFileW(
                                          str,
                                          nil, nil,
                                          'DownSample',
                                          'ps_2_0',
                                          0,
                                          @pCode,
                                          nil,
                                          @Luminance.g_pLum3x3DSPSConsts
                                      ));
  if FAILED(Result) then
  begin
    // Couldn't compile the shader, use the 'compile_shaders.bat' script
    // in the 'Shader Code' folder to get a proper compile breakdown.
    OutputDebugString('Luminance::CreateResources() - Compiling of ''DownSample'' from ''Luminance.psh'' failed!'#10);
    Exit;
  end;

  Result := V(pDevice.CreatePixelShader(PDWORD(pCode.GetBufferPointer), Luminance.g_pLum3x3DSPS));
  if FAILED(Result) then
  begin
    // Couldn't turn the compiled shader into an actual, usable, pixel shader!
    OutputDebugString('Luminance::CreateResources() : Could not create a pixel shader object for ''DownSample''.'#10);
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
var
  i: Integer;
begin
  for i := 0 to Luminance.g_dwLumTextures - 1 do Luminance.g_pTexLuminance[i] := nil;

  SAFE_RELEASE(Luminance.g_pLumDispPS);
  SAFE_RELEASE(Luminance.g_pLum1PS);
  SAFE_RELEASE(Luminance.g_pLum1PSConsts);
  SAFE_RELEASE(Luminance.g_pLum3x3DSPS);
  SAFE_RELEASE(Luminance.g_pLum3x3DSPSConsts);

  Result:= S_OK;
end;



//--------------------------------------------------------------------------------------
//  MeasureLuminance( )
//
//      DESC:
//          This is the core function for this particular part of the application, it's
//          job is to take the previously rendered (in the 'HDRScene' namespace) HDR
//          image and compute the overall luminance for the scene. This is done by
//          repeatedly downsampling the image until it is only 1x1 in size. Doing it
//          this way (pixel shaders and render targets) keeps as much of the work on
//          the GPU as possible, consequently avoiding any resource transfers, locking
//          and modification.
//
//      PARAMS:
//          pDevice : The currently active device that will be used for rendering.
//
//      NOTES:
//          The results from this function will eventually be used to compose the final
//          image. See OnFrameRender() in 'HDRDemo.cpp'.
//
//--------------------------------------------------------------------------------------
function MeasureLuminance(const pDevice: IDirect3DDevice9): HRESULT;
type
  PSingleArray = ^TSingleArray;
  TSingleArray = array[0..3] of Single; 
var
  //[ 0 ] DECLARE VARIABLES AND ALIASES
  //-----------------------------------
  pSourceTex: IDirect3DTexture9;    // We use this texture as the input
  pDestTex: IDirect3DTexture9;      // We render to this texture...
  pDestSurf: IDirect3DSurface9;    // ... Using this ptr to it's top-level surface
  offsets: array[0..3] of TD3DXVector4;
  srcDesc: TD3DSurfaceDesc;
  sU, sV: Single;
  i: Integer;
  srcTexDesc: TD3DSurfaceDesc;
  DSoffsets: array[0..8] of TD3DXVector4;
  idx: Integer;
  x, y: Integer;
begin

  //[ 1 ] SET THE DEVICE TO RENDER TO THE HIGHEST
  //      RESOLUTION LUMINANCE MAP.
  //---------------------------------------------
  HDRScene.GetOutputTexture(pSourceTex);
  pDestTex := Luminance.g_pTexLuminance[ Luminance.g_dwLumTextures - 1 ];
  if FAILED(pDestTex.GetSurfaceLevel(0, pDestSurf)) then
  begin
    // Couldn't acquire this surface level. Odd!
    OutputDebugString('Luminance::MeasureLuminance( ) : Couldn''t acquire surface level for hi-res luminance map!'#10);
    Result:= E_FAIL;
    Exit;
  end;

  pDevice.SetRenderTarget(0, pDestSurf);
  pDevice.SetTexture(0, pSourceTex);

  pDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
  pDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);


  //[ 2 ] RENDER AND DOWNSAMPLE THE HDR TEXTURE
  //      TO THE LUMINANCE MAP.
  //-------------------------------------------

  // Set which shader we're going to use. g_pLum1PS corresponds
  // to the 'GreyScaleDownSample' entry point in 'Luminance.psh'.
  pDevice.SetPixelShader(Luminance.g_pLum1PS);

  // We need to compute the sampling offsets used for this pass.
  // A 2x2 sampling pattern is used, so we need to generate 4 offsets.
  //
  // NOTE: It is worth noting that some information will likely be lost
  //       due to the luminance map being less than 1/2 the size of the
  //       original render-target. This mis-match does not have a particularly
  //       big impact on the final luminance measurement. If necessary,
  //       the same process could be used - but with many more samples, so as
  //       to correctly map from HDR->Luminance without losing information.

  // Find the dimensions for the source data
  pSourceTex.GetLevelDesc(0, srcDesc);

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

  // Set the offsets to the constant table
  Luminance.g_pLum1PSConsts.SetVectorArray(pDevice, 'tcLumOffsets', @offsets, 4);

  // With everything configured we can now render the first, initial, pass
  // to the luminance textures.
  RenderToTexture(pDevice);

  // Make sure we clean up the remaining reference
  SAFE_RELEASE(pDestSurf);
  SAFE_RELEASE(pSourceTex);


  //[ 3 ] SCALE EACH RENDER TARGET DOWN
  //      The results ("dest") of each pass feeds into the next ("src")
  //-------------------------------------------------------------------
  for i := (Luminance.g_dwLumTextures - 1) downto 1 do
  begin
    // Configure the render targets for this iteration
    pSourceTex  := Luminance.g_pTexLuminance[ i ];
    pDestTex    := Luminance.g_pTexLuminance[ i - 1 ];
    if FAILED(pDestTex.GetSurfaceLevel(0, pDestSurf)) then
    begin
      // Couldn't acquire this surface level. Odd!
      OutputDebugString('Luminance::MeasureLuminance( ) : Couldn''t acquire surface level for luminance map!'#10);
      Result:= E_FAIL;
      Exit;
   end;

    pDevice.SetRenderTarget(0, pDestSurf);
    pDevice.SetTexture(0, pSourceTex);

    // We don't want any filtering for this pass
    pDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
    pDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);

    // Because each of these textures is a factor of 3
    // different in dimension, we use a 3x3 set of sampling
    // points to downscale.
    pSourceTex.GetLevelDesc(0, srcTexDesc);

    // Create the 3x3 grid of offsets
    idx := 0;

    for x := -1 to 1 do
    begin
      for y := -1 to 1 do
      begin
        DSoffsets[idx] := D3DXVector4(
                                x / srcTexDesc.Width,
                                y / srcTexDesc.Height,
                                0.0,   //unused
                                0.0    //unused
                           );
        Inc(idx);
      end;
    end;

    // Set them to the current pixel shader
    pDevice.SetPixelShader(Luminance.g_pLum3x3DSPS);
    Luminance.g_pLum3x3DSPSConsts.SetVectorArray(pDevice, 'tcDSOffsets', @DSoffsets, 9);

    // Render the display to this texture
    RenderToTexture(pDevice);

    // Clean-up by releasing the level-0 surface
    SAFE_RELEASE(pDestSurf);
  end;


  // =============================================================
  //    At this point, the g_pTexLuminance[0] texture will contain
  //    a 1x1 texture that has the downsampled luminance for the
  //    scene as it has currently been rendered.
  // =============================================================

  Result:= S_OK;
end;



//--------------------------------------------------------------------------------------
//  DisplayLuminance( )
//
//      DESC:
//          This function is for presentation purposes only - and isn't a *required*
//          part of the HDR rendering pipeline. It draws the 6 stages of the luminance
//          calculation to the appropriate part of the screen.
//
//      PARAMS:
//          pDevice     : The device to be rendered to.
//          pFont       : The font to use when adding the annotations
//          pTextSprite : Used to improve performance of the text rendering
//          pArrowTex   : Stores the 4 (up/down/left/right) icons used in the GUI
//
//      NOTES:
//          This code uses several hard-coded ratios to position the elements correctly
//          - as such, changing the underlying diagram may well break this code.
//
//--------------------------------------------------------------------------------------
function DisplayLuminance(const pDevice: IDirect3DDevice9; const pFont: ID3DXFont;
  const pTextSprite: ID3DXSprite; const pArrowTex: IDirect3DTexture9): HRESULT;
var
  pSurf: IDirect3DSurface9;
  d: TD3DSurfaceDesc;
  fW, fH: Single;
  fCellH, fCellW: Single;
  fLumCellSize: Single;
  fLumStartX: Single;
  v: array[0..3] of Luminance.TLVertex;
  txtHelper: CDXUTTextHelper;
  str: array[0..99] of WideChar;
begin
  // [ 0 ] COMMON INITIALIZATION
  //----------------------------

  if FAILED(pDevice.GetRenderTarget(0, pSurf)) then
  begin
    // Couldn't get the current render target!
    OutputDebugString('Luminance::DisplayLuminance() - Could not get current render target to extract dimensions.'#10);
    Result:= E_FAIL;
    Exit;
  end;

  pSurf.GetDesc(d);
  pSurf := nil;

  // Cache the dimensions as floats for later use
  fW := d.Width;
  fH := d.Height;
  fCellH := (fH - 36.0) / 4.0;
  fCellW := (fW - 48.0) / 4.0;
  fLumCellSize := ( ( fH - ( ( 2.0 * fCellH ) + 32.0 ) ) - 32.0 ) / 3.0;
  fLumStartX := (fCellW + 16.0) - ((2.0 * fLumCellSize) + 32.0);

  // Fill out the basic TLQuad information - this
  // stuff doesn't change for each stage
  v[0].t := D3DXVector2(0.0, 0.0);
  v[1].t := D3DXVector2(1.0, 0.0);
  v[2].t := D3DXVector2(0.0, 1.0);
  v[3].t := D3DXVector2(1.0, 1.0);

  // Configure the device for it's basic states
  pDevice.SetVertexShader(nil);
  pDevice.SetFVF(FVF_TLVERTEX);
  pDevice.SetPixelShader(g_pLumDispPS);

  txtHelper := CDXUTTextHelper.Create(pFont, pTextSprite, 12);
  txtHelper.SetForegroundColor(D3DXColor(1.0, 0.5, 0.0, 1.0));

  // [ 1 ] RENDER FIRST LEVEL
  //-------------------------
  v[0].p := D3DXVector4(fLumStartX,                   (2.0 * fCellH) + 32.0,                0.0, 1.0);
  v[1].p := D3DXVector4(fLumStartX + fLumCellSize,    (2.0 * fCellH) + 32.0,                0.0, 1.0);
  v[2].p := D3DXVector4(fLumStartX,                   (2.0 * fCellH) + 32.0 + fLumCellSize, 0.0, 1.0);
  v[3].p := D3DXVector4(fLumStartX + fLumCellSize,    (2.0 * fCellH) + 32.0 + fLumCellSize, 0.0, 1.0);

  pDevice.SetTexture(0, Luminance.g_pTexLuminance[ 5 ]);
  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(Luminance.TLVertex));

  txtHelper._Begin;
  begin
    txtHelper.SetInsertionPos(Trunc( fLumStartX ) + 2, Trunc( (2.0 * fCellH) + 32.0 + fLumCellSize ) - 24);
    txtHelper.DrawTextLine('1st Luminance');

    Luminance.g_pTexLuminance[ 5 ].GetLevelDesc(0, d);

    StringCchFormat(str, 100, '%dx%d', [d.Width, d.Height]);
    txtHelper.DrawTextLine(str);
  end;
  txtHelper._End;


  // [ 2 ] RENDER SECOND LEVEL
  //--------------------------
  v[0].p := D3DXVector4(fLumStartX,                   (2.0 * fCellH) + 48.0 + fLumCellSize,         0.0, 1.0);
  v[1].p := D3DXVector4(fLumStartX + fLumCellSize,    (2.0 * fCellH) + 48.0 + fLumCellSize,         0.0, 1.0);
  v[2].p := D3DXVector4(fLumStartX,                   (2.0 * fCellH) + 48.0 + (2.0 * fLumCellSize), 0.0, 1.0);
  v[3].p := D3DXVector4(fLumStartX + fLumCellSize,    (2.0 * fCellH) + 48.0 + (2.0 * fLumCellSize), 0.0, 1.0);

  pDevice.SetTexture(0, Luminance.g_pTexLuminance[ 4 ]);
  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(Luminance.TLVertex));

  txtHelper._Begin;
  begin
    txtHelper.SetInsertionPos(Trunc( fLumStartX ) + 2, Trunc( (2.0 * fCellH) + 48.0 + (2.0 * fLumCellSize) ) - 24);
    txtHelper.DrawTextLine('2nd Luminance');

    Luminance.g_pTexLuminance[ 4 ].GetLevelDesc(0, d);

    StringCchFormat(str, 100, '%dx%d', [d.Width, d.Height]);
    txtHelper.DrawTextLine(str);
  end;
  txtHelper._End;


  // [ 3 ] RENDER THIRD LEVEL
  //-------------------------
  v[0].p := D3DXVector4(fLumStartX,                   (2.0 * fCellH) + 64.0 + (2.0 * fLumCellSize), 0.0, 1.0);
  v[1].p := D3DXVector4(fLumStartX + fLumCellSize,    (2.0 * fCellH) + 64.0 + (2.0 * fLumCellSize), 0.0, 1.0);
  v[2].p := D3DXVector4(fLumStartX,                   (2.0 * fCellH) + 64.0 + (3.0 * fLumCellSize), 0.0, 1.0);
  v[3].p := D3DXVector4(fLumStartX + fLumCellSize,    (2.0 * fCellH) + 64.0 + (3.0 * fLumCellSize), 0.0, 1.0);

  pDevice.SetTexture(0, Luminance.g_pTexLuminance[ 3 ]);
  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(Luminance.TLVertex));

  txtHelper._Begin;
  begin
    txtHelper.SetInsertionPos( Trunc( fLumStartX ) + 2, Trunc( (2.0 * fCellH) + 64.0 + (3.0 * fLumCellSize) ) - 24);
    txtHelper.DrawTextLine('3rd Luminance');

    Luminance.g_pTexLuminance[ 3 ].GetLevelDesc(0, d);

    StringCchFormat(str,100, '%dx%d', [d.Width, d.Height]);
    txtHelper.DrawTextLine(str);
  end;
  txtHelper._End;

  // [ 4 ] RENDER FOURTH LEVEL
  //--------------------------
  v[0].p := D3DXVector4(fLumStartX + fLumCellSize + 16.0,           (2.0 * fCellH) + 64.0 + (2.0 * fLumCellSize), 0.0, 1.0);
  v[1].p := D3DXVector4(fLumStartX + (2.0 * fLumCellSize) + 16.0,   (2.0 * fCellH) + 64.0 + (2.0 * fLumCellSize), 0.0, 1.0);
  v[2].p := D3DXVector4(fLumStartX + fLumCellSize + 16.0,           (2.0 * fCellH) + 64.0 + (3.0 * fLumCellSize), 0.0, 1.0);
  v[3].p := D3DXVector4(fLumStartX + (2.0 * fLumCellSize) + 16.0,   (2.0 * fCellH) + 64.0 + (3.0 * fLumCellSize), 0.0, 1.0);

  pDevice.SetTexture(0, Luminance.g_pTexLuminance[ 2 ]);
  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(Luminance.TLVertex));

  txtHelper._Begin;
  begin
    txtHelper.SetInsertionPos( Trunc( fLumStartX + fLumCellSize + 16.0 ) + 2, Trunc( (2.0 * fCellH) + 64.0 + (3.0 * fLumCellSize) ) - 24);
    txtHelper.DrawTextLine('4th Luminance');

    Luminance.g_pTexLuminance[ 2 ].GetLevelDesc(0, d);

    StringCchFormat(str, 100, '%dx%d', [d.Width, d.Height]);
    txtHelper.DrawTextLine(str);
  end;
  txtHelper._End;

  // [ 5 ] RENDER FIFTH LEVEL
  //--------------------------
  v[0].p := D3DXVector4(fLumStartX + fLumCellSize + 16.0,           (2.0 * fCellH) + 48.0 + (1.0 * fLumCellSize), 0.0, 1.0);
  v[1].p := D3DXVector4(fLumStartX + (2.0 * fLumCellSize) + 16.0,   (2.0 * fCellH) + 48.0 + (1.0 * fLumCellSize), 0.0, 1.0);
  v[2].p := D3DXVector4(fLumStartX + fLumCellSize + 16.0,           (2.0 * fCellH) + 48.0 + (2.0 * fLumCellSize), 0.0, 1.0);
  v[3].p := D3DXVector4(fLumStartX + (2.0 * fLumCellSize) + 16.0,   (2.0 * fCellH) + 48.0 + (2.0 * fLumCellSize), 0.0, 1.0);

  pDevice.SetTexture(0, Luminance.g_pTexLuminance[ 1 ]);
  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(Luminance.TLVertex));

  txtHelper._Begin;
  begin
      txtHelper.SetInsertionPos( Trunc( fLumStartX + fLumCellSize + 16.0 ) + 2, Trunc( (2.0 * fCellH) + 48.0 + (2.0 * fLumCellSize) ) - 24);
      txtHelper.DrawTextLine('5th Luminance');

      Luminance.g_pTexLuminance[ 1 ].GetLevelDesc(0, d);

      StringCchFormat(str,100, '%dx%d', [d.Width, d.Height]);
      txtHelper.DrawTextLine(str);
  end;
  txtHelper._End;

  // [ 6 ] RENDER SIXTH LEVEL
  //--------------------------
  v[0].p := D3DXVector4(fLumStartX + fLumCellSize + 16.0,            (2.0 * fCellH) + 32.0 + (0.0 * fLumCellSize), 0.0, 1.0);
  v[1].p := D3DXVector4(fLumStartX + (2.0 * fLumCellSize) + 16.0,   (2.0 * fCellH) + 32.0 + (0.0 * fLumCellSize), 0.0, 1.0);
  v[2].p := D3DXVector4(fLumStartX + fLumCellSize + 16.0,            (2.0 * fCellH) + 32.0 + (1.0 * fLumCellSize), 0.0, 1.0);
  v[3].p := D3DXVector4(fLumStartX + (2.0 * fLumCellSize) + 16.0,   (2.0 * fCellH) + 32.0 + (1.0 * fLumCellSize), 0.0, 1.0);

  pDevice.SetTexture(0, Luminance.g_pTexLuminance[ 0 ]);
  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(Luminance.TLVertex));

  txtHelper._Begin;
  begin
    txtHelper.SetInsertionPos( Trunc( fLumStartX + fLumCellSize + 16.0 ) + 2, Trunc( (2.0 * fCellH) + 32.0 + (1.0 * fLumCellSize) ) - 24);
    txtHelper.DrawTextLine('6th Luminance');

    Luminance.g_pTexLuminance[ 0 ].GetLevelDesc(0, d);

    StringCchFormat(str, 100, '%dx%d', [d.Width, d.Height]);
    txtHelper.DrawTextLine(str);
  end;
  txtHelper._End;

  // [ 7 ] RENDER ARROWS
  //--------------------
  pDevice.SetPixelShader(nil);
  pDevice.SetTexture(0, pArrowTex);

  // Select the "down" arrow

  v[0].t := D3DXVector2(0.50, 0.0);
  v[1].t := D3DXVECTOR2(0.75, 0.0);
  v[2].t := D3DXVector2(0.50, 1.0);
  v[3].t := D3DXVector2(0.75, 1.0);

  // From 1st down to 2nd

  v[0].p := D3DXVector4(fLumStartX + (fLumCellSize / 2.0) - 8.0,    (2.0 * fCellH) + 32.0 + (1.0 * fLumCellSize), 0.0, 1.0);
  v[1].p := D3DXVector4(fLumStartX + (fLumCellSize / 2.0) + 8.0,    (2.0 * fCellH) + 32.0 + (1.0 * fLumCellSize), 0.0, 1.0);
  v[2].p := D3DXVector4(fLumStartX + (fLumCellSize / 2.0) - 8.0,    (2.0 * fCellH) + 48.0 + (1.0 * fLumCellSize), 0.0, 1.0);
  v[3].p := D3DXVector4(fLumStartX + (fLumCellSize / 2.0) + 8.0,    (2.0 * fCellH) + 48.0 + (1.0 * fLumCellSize), 0.0, 1.0);

  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(Luminance.TLVertex));

  // From 2nd down to 3rd

  v[0].p := D3DXVector4(fLumStartX + (fLumCellSize / 2.0) - 8.0,    (2.0 * fCellH) + 48.0 + (2.0 * fLumCellSize), 0.0, 1.0);
  v[1].p := D3DXVector4(fLumStartX + (fLumCellSize / 2.0) + 8.0,    (2.0 * fCellH) + 48.0 + (2.0 * fLumCellSize), 0.0, 1.0);
  v[2].p := D3DXVector4(fLumStartX + (fLumCellSize / 2.0) - 8.0,    (2.0 * fCellH) + 64.0 + (2.0 * fLumCellSize), 0.0, 1.0);
  v[3].p := D3DXVector4(fLumStartX + (fLumCellSize / 2.0) + 8.0,    (2.0 * fCellH) + 64.0 + (2.0 * fLumCellSize), 0.0, 1.0);

  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(Luminance.TLVertex));

  // Select "right" arrow

  v[0].t := D3DXVector2(0.25, 0.0);
  v[1].t := D3DXVector2(0.50, 0.0);
  v[2].t := D3DXVector2(0.25, 1.0);
  v[3].t := D3DXVector2(0.50, 1.0);

  // Across from 3rd to 4th

  v[0].p := D3DXVector4(fLumStartX + fLumCellSize,           (2.0 * fCellH) + 56.0 + (2.5 * fLumCellSize), 0.0, 1.0);
  v[1].p := D3DXVector4(fLumStartX + fLumCellSize + 16.0,    (2.0 * fCellH) + 56.0 + (2.5 * fLumCellSize), 0.0, 1.0);
  v[2].p := D3DXVector4(fLumStartX + fLumCellSize,           (2.0 * fCellH) + 72.0 + (2.5 * fLumCellSize), 0.0, 1.0);
  v[3].p := D3DXVector4(fLumStartX + fLumCellSize + 16.0,    (2.0 * fCellH) + 72.0 + (2.5 * fLumCellSize), 0.0, 1.0);

  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(Luminance.TLVertex));

  // Select "up" arrow

  v[0].t := D3DXVector2(0.00, 0.0);
  v[1].t := D3DXVector2(0.25, 0.0);
  v[2].t := D3DXVector2(0.00, 1.0);
  v[3].t := D3DXVector2(0.25, 1.0);

  // Up from 4th to 5th

  v[0].p := D3DXVector4(fLumStartX + (1.5 * fLumCellSize) + 8.0,    (2.0 * fCellH) + 48.0 + (2.0 * fLumCellSize), 0.0, 1.0);
  v[1].p := D3DXVector4(fLumStartX + (1.5 * fLumCellSize) + 24.0,   (2.0 * fCellH) + 48.0 + (2.0 * fLumCellSize), 0.0, 1.0);
  v[2].p := D3DXVector4(fLumStartX + (1.5 * fLumCellSize) + 8.0,    (2.0 * fCellH) + 64.0 + (2.0 * fLumCellSize), 0.0, 1.0);
  v[3].p := D3DXVector4(fLumStartX + (1.5 * fLumCellSize) + 24.0,   (2.0 * fCellH) + 64.0 + (2.0 * fLumCellSize), 0.0, 1.0);

  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(Luminance.TLVertex));

  // Up from 5th to 6th

  v[0].p := D3DXVector4(fLumStartX + (1.5 * fLumCellSize) + 8.0,    (2.0 * fCellH) + 32.0 + (1.0 * fLumCellSize), 0.0, 1.0);
  v[1].p := D3DXVector4(fLumStartX + (1.5 * fLumCellSize) + 24.0,   (2.0 * fCellH) + 32.0 + (1.0 * fLumCellSize), 0.0, 1.0);
  v[2].p := D3DXVector4(fLumStartX + (1.5 * fLumCellSize) + 8.0,    (2.0 * fCellH) + 48.0 + (1.0 * fLumCellSize), 0.0, 1.0);
  v[3].p := D3DXVector4(fLumStartX + (1.5 * fLumCellSize) + 24.0,   (2.0 * fCellH) + 48.0 + (1.0 * fLumCellSize), 0.0, 1.0);

  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(Luminance.TLVertex));

  // Select "right" arrow

  v[0].t := D3DXVector2(0.25, 0.0);
  v[1].t := D3DXVector2(0.50, 0.0);
  v[2].t := D3DXVector2(0.25, 1.0);
  v[3].t := D3DXVector2(0.50, 1.0);

  // From 6th to final image composition

  v[0].p := D3DXVector4(fLumStartX + (2.0 * fLumCellSize) + 16.0,   (2.0 * fCellH) + 24.0 + (0.5 * fLumCellSize), 0.0, 1.0);
  v[1].p := D3DXVector4(fLumStartX + (2.0 * fLumCellSize) + 32.0,   (2.0 * fCellH) + 24.0 + (0.5 * fLumCellSize), 0.0, 1.0);
  v[2].p := D3DXVector4(fLumStartX + (2.0 * fLumCellSize) + 16.0,   (2.0 * fCellH) + 40.0 + (0.5 * fLumCellSize), 0.0, 1.0);
  v[3].p := D3DXVector4(fLumStartX + (2.0 * fLumCellSize) + 32.0,   (2.0 * fCellH) + 40.0 + (0.5 * fLumCellSize), 0.0, 1.0);

  pDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(Luminance.TLVertex));

  txtHelper.Free;
  
  Result:= S_OK;
end;



//--------------------------------------------------------------------------------------
//  GetLuminanceTexture( )
//
//      DESC:
//          The final 1x1 luminance texture created by the MeasureLuminance() function
//          is required as an input into the final image composition. Because of this
//          it is necessary for other parts of the application to have access to this
//          particular texture.
//
//      PARAMS:
//          pTexture    : Should be NULL on entry, will be a valid reference on exit
//
//      NOTES:
//          The code that requests the reference is responsible for releasing their
//          copy of the texture as soon as they are finished using it.
//
//--------------------------------------------------------------------------------------
function GetLuminanceTexture(out pTex: IDirect3DTexture9): HRESULT;
begin
  // [ 0 ] ERASE ANY DATA IN THE INPUT
  //----------------------------------
  // SAFE_RELEASE( *pTex );

  // [ 1 ] COPY THE PRIVATE REFERENCE
  //---------------------------------
  pTex := Luminance.g_pTexLuminance[ 0 ];

  // [ 2 ] INCREMENT THE REFERENCE COUNT..
  //--------------------------------------
  //(*pTex)->AddRef( );

  Result:= S_OK;
end;



//--------------------------------------------------------------------------------------
//  ComputeResourceUsage( )
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
function ComputeResourceUsage: DWORD;
var
  usage: DWORD;
  i: Integer;
  d: TD3DSurfaceDesc;
begin
  usage := 0;

  for i := 0 to Luminance.g_dwLumTextures - 1 do
  begin
    Luminance.g_pTexLuminance[ i ].GetLevelDesc(0, d);

    usage := usage + ( (d.Width * d.Height) * DWORD(IfThen(Luminance.g_fmtHDR = D3DFMT_G32R32F, 8, 4)) );
  end;

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
  v: array[0..3] of Luminance.TLVertex;
begin
  pDev.GetRenderTarget(0, pSurfRT);
  pSurfRT.GetDesc(desc);
  pSurfRT := nil;

  // To correctly map from texels->pixels we offset the coordinates
  // by -0.5f:
  fWidth := desc.Width - 0.5;
  fHeight := desc.Height - 0.5;

  // Now we can actually assemble the screen-space geometry
  v[0].p := D3DXVector4(-0.5, -0.5, 0.0, 1.0);
  v[0].t := D3DXVector2(0.0, 0.0);

  v[1].p := D3DXVector4(fWidth, -0.5, 0.0, 1.0);
  v[1].t := D3DXVECTOR2(1.0, 0.0);

  v[2].p := D3DXVector4(-0.5, fHeight, 0.0, 1.0);
  v[2].t := D3DXVector2(0.0, 1.0);

  v[3].p := D3DXVector4(fWidth, fHeight, 0.0, 1.0);
  v[3].t := D3DXVector2(1.0, 1.0);

  // Configure the device and render..
  pDev.SetVertexShader(nil);
  pDev.SetFVF(Luminance.FVF_TLVERTEX);
  pDev.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(Luminance.TLVertex));

  Result:= S_OK;
end;

end.

