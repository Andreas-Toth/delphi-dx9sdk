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
 *  $Id: HDRPipelineUnit.pas,v 1.5 2007/02/05 22:21:08 clootie Exp $
 *----------------------------------------------------------------------------*)
//======================================================================
//
//      HIGH DYNAMIC RANGE RENDERING DEMONSTRATION
//      Written by Jack Hoxley, November 2005
//
//======================================================================

{$I DirectX.inc}

unit HDRPipelineUnit;

interface

uses
  Windows, DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTmisc, DXUTenum, DXUTgui, DXUTSettingsDlg,
  SysUtils, Math, StrSafe;


//--------------------------------------------------------------------------------------
// Data Structure Definitions
//--------------------------------------------------------------------------------------
type
  TTLVertex = record
    p: TD3DXVector4;
    t: TD3DXVector2;
  end;

const
  FVF_TLVERTEX = D3DFVF_XYZRHW or D3DFVF_TEX1;


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pFont: ID3DXFont = nil;                              // Font for drawing text
  g_pTextSprite: ID3DXSprite = nil;                      // Sprite for batching draw text calls
  g_pArrowTex: IDirect3DTexture9 = nil;                  // Used to indicate flow between cells
  g_Camera: CModelViewerCamera;                          // A model viewing camera
  g_HUD: CDXUTDialog;                                    // Dialog for standard controls
  g_Config: CDXUTDialog;                                 // Dialog for the shader/render parameters
  g_SettingsDlg: CD3DSettingsDlg;                        // Used for the "change device" button
  g_DialogResourceManager: CDXUTDialogResourceManager;   // Manager for shared resources of dialogs
  g_pFinalPassPS: IDirect3DPixelShader9 = nil;           // The pixel shader that maps HDR->LDR
  g_pFinalPassPSConsts: ID3DXConstantTable = nil;        // The interface for setting param/const data for the above PS
  g_dwLastFPSCheck: DWORD = 0;    // The time index of the last frame rate check
  g_dwFrameCount: DWORD = 0;      // How many frames have elapsed since the last check
  g_dwFrameRate: DWORD = 0;       // How many frames rendered during the PREVIOUS interval
  g_fExposure: Single = 0.5;      // The exposure bias fed into the FinalPass.psh shader (OnFrameRender )



//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 2;
  IDC_CHANGEDEVICE        = 3;
  IDC_THRESHOLDSLIDER     = 4;
  IDC_THRESHOLDLABEL      = 5;
  IDC_EXPOSURESLIDER      = 6;
  IDC_EXPOSURELABEL       = 7;
  IDC_MULTIPLIERSLIDER    = 8;
  IDC_MULTIPLIERLABEL     = 9;
  IDC_MEANSLIDER          = 10;
  IDC_MEANLABEL           = 11;
  IDC_STDDEVSLIDER        = 12;
  IDC_STDDEVLABEL         = 13;


//--------------------------------------------------------------------------------------
// HIGH DYNAMIC RANGE VARIABLES
//--------------------------------------------------------------------------------------
var
  g_FloatRenderTargetFmt: TD3DFormat = D3DFMT_UNKNOWN;    // 128 or 64 bit rendering...
  g_DepthFormat: TD3DFormat = D3DFMT_UNKNOWN;             // How many bits of depth buffer are we using?
  g_dwApproxMemory: DWORD = 0;                            // How many bytes of VRAM are we using up?
  g_pFinalTexture: IDirect3DTexture9 = nil;

//--------------------------------------------------------------------------------------
// Forward declarations
//--------------------------------------------------------------------------------------
function IsDeviceAcceptable(const pCaps: TD3DCaps9; AdapterFormat, BackBufferFormat: TD3DFormat; bWindowed: Boolean; pUserContext: Pointer): Boolean; stdcall;
function ModifyDeviceSettings(var pDeviceSettings: TDXUTDeviceSettings; const pCaps: TD3DCaps9; pUserContext: Pointer): Boolean; stdcall;
function OnCreateDevice(const pd3dDevice: IDirect3DDevice9; const pBackBufferSurfaceDesc: TD3DSurfaceDesc; pUserContext: Pointer): HRESULT; stdcall;
function OnResetDevice(const pd3dDevice: IDirect3DDevice9; const pBackBufferSurfaceDesc: TD3DSurfaceDesc; pUserContext: Pointer): HRESULT; stdcall;
procedure OnFrameMove(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
function MsgProc(hWnd: HWND; uMsg: LongWord; wParam: WPARAM; lParam: LPARAM; out pbNoFurtherProcessing: Boolean; pUserContext: Pointer): LRESULT; stdcall;
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
procedure OnLostDevice(pUserContext: Pointer); stdcall;
procedure OnDestroyDevice(pUserContext: Pointer); stdcall;

//--------------------------------------------------------------------------------------
// Forward declarations 
//--------------------------------------------------------------------------------------
procedure InitApp;
procedure RenderText;
procedure DrawHDRTextureToScreen;


procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;



implementation


uses
  HDREnumeration, HDRScene, Luminance, PostProcess;


//--------------------------------------------------------------------------------------
// Debug output helper
//--------------------------------------------------------------------------------------
var g_szStaticOutput: array[0..MAX_PATH-1] of WideChar;
function DebugHelper(szFormat: PWideChar; cSizeBytes: LongWord): PWideChar;
begin
  StringCchFormat(g_szStaticOutput, MAX_PATH, szFormat, [cSizeBytes]);
  Result:= g_szStaticOutput;
end;

//--------------------------------------------------------------------------------------
// Initialize the app
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  iY: Integer;
begin
  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_Config.Init(g_DialogResourceManager);

  g_HUD.SetFont(0, 'Arial', 14, FW_NORMAL );
  g_HUD.SetCallback(OnGUIEvent);

  g_Config.SetFont(0, 'Arial', 12, FW_NORMAL);
  g_Config.SetCallback(OnGUIEvent);

  iY := 10;
  g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22);  Inc(iY, 24);
  g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', 35, iY, 125, 22); Inc(iY, 24);
  g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', 35, iY, 125, 22, VK_F2);

  g_Config.AddStatic(IDC_MULTIPLIERLABEL, 'Gaussian Multiplier: (0.4)', 35, 0, 125, 15);
  g_Config.AddSlider(IDC_MULTIPLIERSLIDER, 35, 20, 125, 16, 0, 20, 4);

  g_Config.AddStatic(IDC_MEANLABEL, 'Gaussian Mean: (0.0)', 35, 40, 125, 15);
  g_Config.AddSlider(IDC_MEANSLIDER, 35, 60, 125, 16, -10, 10, 0);

  g_Config.AddStatic(IDC_STDDEVLABEL, 'Gaussian Std. Dev: (0.8)', 35, 80, 125, 15);
  g_Config.AddSlider(IDC_STDDEVSLIDER, 35, 100, 125, 16, 0, 10, 8);

  g_Config.AddStatic(IDC_THRESHOLDLABEL, 'Bright-Pass Threshold: (0.8)', 35, 120, 125, 15);
  g_Config.AddSlider(IDC_THRESHOLDSLIDER, 35, 140, 125, 16, 0, 25, 8);

  g_Config.AddStatic(IDC_EXPOSURELABEL, 'Exposure: (0.5)', 35, 160, 125, 15);
  g_Config.AddSlider(IDC_EXPOSURESLIDER, 35, 180, 125, 16, 0, 200, 50);
end;



//--------------------------------------------------------------------------------------
// Rejects any devices that aren't acceptable by returning false
//--------------------------------------------------------------------------------------
function IsDeviceAcceptable(const pCaps: TD3DCaps9; AdapterFormat, BackBufferFormat: TD3DFormat; bWindowed: Boolean; pUserContext: Pointer): Boolean; stdcall;
var
  pD3D: IDirect3D9;
begin
  Result:= False;

  // Skip backbuffer formats that don't support alpha blending
  pD3D := DXUTGetD3DObject;
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
              AdapterFormat, D3DUSAGE_QUERY_POSTPIXELSHADER_BLENDING,
              D3DRTYPE_TEXTURE, BackBufferFormat))
  then Exit;

  // Also need post pixel processing support
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
      AdapterFormat, D3DUSAGE_RENDERTARGET or D3DUSAGE_QUERY_POSTPIXELSHADER_BLENDING,
      D3DRTYPE_SURFACE, BackBufferFormat)) then Exit;

  // We must have SM2.0 support for this sample to run. We
  // don't need to worry about the VS version as we can shift
  // that to the CPU if necessary...
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2,0)) then Exit;

  // We must have floating point render target support, where available we'll use 128bit,
  // but we can also use 64bit. We'll store the best one we can use...
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                   AdapterFormat, D3DUSAGE_RENDERTARGET,
                   D3DRTYPE_TEXTURE, D3DFMT_A32B32G32R32F)) then
  begin
    //we don't support 128bit render targets :-(
    if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                AdapterFormat, D3DUSAGE_RENDERTARGET,
                D3DRTYPE_TEXTURE, D3DFMT_A16B16G16R16F)) then
    begin
      //we don't support 128 or 64 bit render targets. This demo
      //will not work with this device.
      Exit;
    end;
  end;

  Result:= True;
end;


//--------------------------------------------------------------------------------------
// Before a device is created, modify the device settings as needed
//--------------------------------------------------------------------------------------
function ModifyDeviceSettings(var pDeviceSettings: TDXUTDeviceSettings; const pCaps: TD3DCaps9; pUserContext: Pointer): Boolean; stdcall;
begin
  // If device doesn't support HW T&L or doesn't support 2.0 vertex shaders in HW
  // then switch to SWVP.
  if (pCaps.DevCaps and D3DDEVCAPS_HWTRANSFORMANDLIGHT = 0) or
     (pCaps.VertexShaderVersion < D3DVS_VERSION(2,0))
  then pDeviceSettings.BehaviorFlags := D3DCREATE_SOFTWARE_VERTEXPROCESSING
  else pDeviceSettings.BehaviorFlags := D3DCREATE_HARDWARE_VERTEXPROCESSING;

  // This application is designed to work on a pure device by not using
  // IDirect3D9::Get*() methods, so create a pure device if supported and using HWVP.
  if (pCaps.DevCaps and D3DDEVCAPS_PUREDEVICE <> 0) and
     (pDeviceSettings.BehaviorFlags and D3DCREATE_HARDWARE_VERTEXPROCESSING <> 0)
  then pDeviceSettings.BehaviorFlags := pDeviceSettings.BehaviorFlags or D3DCREATE_PUREDEVICE;

  g_DepthFormat := pDeviceSettings.pp.AutoDepthStencilFormat;

  // TODO: Some devices **WILL** allow multisampled HDR targets, this can be
  // checked via a device format enumeration. If multisampling is a requirement, an
  // enumeration/check could be added here.
  if (pDeviceSettings.pp.MultiSampleType <> D3DMULTISAMPLE_NONE) then
  begin
    // Multisampling and HDRI don't play nice!
    OutputDebugString('Multisampling is enabled. Disabling now!'#10);
    pDeviceSettings.pp.MultiSampleType := D3DMULTISAMPLE_NONE;
  end;

  Result:= True;
end;


//--------------------------------------------------------------------------------------
// Create any D3DPOOL_MANAGED resources here
//--------------------------------------------------------------------------------------
function OnCreateDevice(const pd3dDevice: IDirect3DDevice9; const pBackBufferSurfaceDesc: TD3DSurfaceDesc; pUserContext: Pointer): HRESULT; stdcall;
var
  str: array[0..MAX_PATH-1] of WideChar;
  vecEye, vecAt: TD3DXVector3;
begin
  // Allow the GUI to set itself up..
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  // Determine any necessary enumerations
  Result:= HDREnumeration.FindBestHDRFormat(g_FloatRenderTargetFmt);
  if V_Failed(Result) then Exit;

  // Initialize the font
  Result:= D3DXCreateFont(pd3dDevice, 12, 0, FW_NORMAL, 1, FALSE, DEFAULT_CHARSET,
                          OUT_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE,
                          'Arial', g_pFont);
  if V_Failed(Result) then Exit;

  V(DXUTFindDXSDKMediaFile(str, MAX_PATH, 'misc\Arrows.bmp'));
  if FAILED(Result) then
  begin
    // Couldn't find the sprites
    OutputDebugString('OnCreateDevice() - Could not locate ''Arrows.bmp''.'#10);
    Exit;
  end;

  V(D3DXCreateTextureFromFileW(pd3dDevice, str, g_pArrowTex));
  if FAILED(Result) then
  begin
    // Couldn't load the sprites!
    OutputDebugString('OnCreateDevice() - Could not load ''Arrows.bmp''.'#10);
    Exit;
  end;

  // Setup the camera's view parameters
  vecEye := D3DXVector3(0.0, 0.0, -5.0);
  vecAt  := D3DXVector3(0.0, 0.0, -0.0);
  g_Camera.SetViewParams(vecEye, vecAt);

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// Create any D3DPOOL_DEFAULT resources here
//--------------------------------------------------------------------------------------
function OnResetDevice(const pd3dDevice: IDirect3DDevice9; const pBackBufferSurfaceDesc: TD3DSurfaceDesc; pUserContext: Pointer): HRESULT; stdcall;
var
  pCode: ID3DXBuffer;
  fAspectRatio: Single;
  iMultiplier: Cardinal;
  str: array[0..MAX_PATH-1] of WideChar;
begin
  // Allow the GUI time to reset itself..
  Result:= g_DialogResourceManager.OnResetDevice;
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnResetDevice;
  if V_Failed(Result) then Exit;

  if (g_pFont <> nil) then
  begin
    Result:= g_pFont.OnResetDevice;
    if V_Failed(Result) then Exit;
  end;

  // Create a sprite to help batch calls when drawing many lines of text
  Result:= D3DXCreateSprite(pd3dDevice, g_pTextSprite);
  if V_Failed(Result) then Exit;

  pd3dDevice.SetSamplerState(0, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
  pd3dDevice.SetSamplerState(0, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);

  pd3dDevice.SetSamplerState(1, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
  pd3dDevice.SetSamplerState(1, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);

  pd3dDevice.SetSamplerState(2, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
  pd3dDevice.SetSamplerState(2, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);

  // Setup the camera's projection parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI/4, fAspectRatio, 0.1, 1000.0);
  g_Camera.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);

  // Configure the GUI
  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width - 170, pBackBufferSurfaceDesc.Height - 90);
  g_HUD.SetSize(170, 170);

  g_Config.SetLocation(pBackBufferSurfaceDesc.Width - 170, pBackBufferSurfaceDesc.Height - 300);
  g_Config.SetSize(170, 210);

  // Recreate the floating point resources
  Result:= pd3dDevice.CreateTexture(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height,
                                    1, D3DUSAGE_RENDERTARGET, pBackBufferSurfaceDesc.Format,
                                    D3DPOOL_DEFAULT, g_pFinalTexture, nil);
  if V_Failed(Result) then Exit;

  //Attempt to recalulate some memory statistics:
  case pBackBufferSurfaceDesc.Format of
    //32bit modes:
    D3DFMT_A2R10G10B10,
    D3DFMT_A8R8G8B8,
    D3DFMT_X8R8G8B8:
      iMultiplier := 4;

    //24bit modes:
    D3DFMT_R8G8B8:
      iMultiplier := 3;

    //16bit modes:
    D3DFMT_X1R5G5B5,
    D3DFMT_A1R5G5B5,
    D3DFMT_R5G6B5:
      iMultiplier := 2;
   else
    iMultiplier := 1;
  end;

  //the *3 constant due to having double buffering AND the composition render target..
  g_dwApproxMemory := pBackBufferSurfaceDesc.Width * pBackBufferSurfaceDesc.Height * 3 * iMultiplier;

  case g_DepthFormat of
    //16 bit formats
    D3DFMT_D16,
    D3DFMT_D16_LOCKABLE,
    D3DFMT_D15S1:
      g_dwApproxMemory := g_dwApproxMemory + (pBackBufferSurfaceDesc.Width * pBackBufferSurfaceDesc.Height * 2);

    //32bit formats:
    D3DFMT_D32,
    D3DFMT_D32F_LOCKABLE,
    D3DFMT_D24X8,
    D3DFMT_D24S8,
    D3DFMT_D24X4S4,
    D3DFMT_D24FS8:
      g_dwApproxMemory := g_dwApproxMemory + (pBackBufferSurfaceDesc.Width * pBackBufferSurfaceDesc.Height * 4);
  end;

  {$IFDEF DEBUG}
  OutputDebugStringW(DebugHelper('HDR Demo : Basic Swap Chain/Depth Buffer Occupy %d bytes.'#13, g_dwApproxMemory));
  {$ENDIF}

  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'Shader Code\FinalPass.psh');
  if V_Failed(Result) then Exit;
  Result:= D3DXCompileShaderFromFileW(str,
                                      nil, nil,
                                      'main',
                                      'ps_2_0',
                                      0,
                                      @pCode,
                                      nil,
                                      @g_pFinalPassPSConsts
                                     );
  if V_Failed(Result) then Exit;

  Result:= pd3dDevice.CreatePixelShader(PDWORD(pCode.GetBufferPointer), g_pFinalPassPS);
  if V_Failed(Result) then Exit;

  pCode := nil;

  // Hand over execution to the 'HDRScene' module so it can perform it's
  // resource creation:
  Result:= HDRScene.CreateResources(pd3dDevice, pBackBufferSurfaceDesc);
  if V_Failed(Result) then Exit;
  g_dwApproxMemory := g_dwApproxMemory + HDRScene.CalculateResourceUsage;
  {$IFDEF DEBUG}
  OutputDebugStringW(DebugHelper('HDR Demo : HDR Scene Resources Occupy %d bytes.'#10, HDRScene.CalculateResourceUsage));
  {$ENDIF}

  // Hand over execution to the 'Luminance' module so it can perform it's
  // resource creation:
  Result:= Luminance.CreateResources(pd3dDevice, pBackBufferSurfaceDesc);
  if V_Failed(Result) then Exit;
  g_dwApproxMemory := g_dwApproxMemory + Luminance.ComputeResourceUsage;
  {$IFDEF DEBUG}
  OutputDebugStringW(DebugHelper('HDR Demo : Luminance Resources Occupy %d bytes.'#10, Luminance.ComputeResourceUsage));
  {$ENDIF}

  // Hand over execution to the 'PostProcess' module so it can perform it's
  // resource creation:
  Result:= PostProcess.CreateResources(pd3dDevice, pBackBufferSurfaceDesc);
  if V_Failed(Result) then Exit;
  g_dwApproxMemory := g_dwApproxMemory + PostProcess.CalculateResourceUsage;
  {$IFDEF DEBUG}
  begin
    OutputDebugStringW(DebugHelper('HDR Demo : Post Processing Resources Occupy %d bytes.'#10, PostProcess.CalculateResourceUsage));

    OutputDebugStringW(DebugHelper('HDR Demo : Total Graphics Resources Occupy %d bytes.'#10, g_dwApproxMemory));
  end;
  {$ENDIF}

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// Handle updates to the scene
//--------------------------------------------------------------------------------------
procedure OnFrameMove(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
begin
  // Update the camera's position based on user input
  g_Camera.FrameMove(fElapsedTime);

  // Compute the frame rate based on a 1/4 second update cycle
  if ((GetTickCount - g_dwLastFPSCheck) >= 250) then
  begin
    g_dwFrameRate := g_dwFrameCount * 4;
    g_dwFrameCount := 0;
    g_dwLastFPSCheck := GetTickCount;
  end;

  Inc(g_dwFrameCount);

  // The original HDR scene needs to update some of it's internal structures, so
  // pass the message along...
  HDRScene.UpdateScene(pd3dDevice, fTime, g_Camera);
end;


//--------------------------------------------------------------------------------------
//  OnFrameRender()
//  ---------------
//  NOTES: This function makes particular use of the 'D3DPERF_BeginEvent()' and
//         'D3DPERF_EndEvent()' functions. See the documentation for more details,
//         but these are essentially used to provide better output from PIX. If you
//         perform a full call-stream capture on this sample, PIX will group together
//         related calls, making it much easier to interpret the results.
//--------------------------------------------------------------------------------------
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  //Cache some results for later use
  pLDRSurface: IDirect3DSurface9;

  pFinalSurf: IDirect3DSurface9;
  pHDRTex: IDirect3DTexture9;
  pLumTex: IDirect3DTexture9;
  pBloomTex: IDirect3DTexture9;
  d: TD3DSurfaceDesc;

  vv: array[0..3] of TTLVertex;
  fCellWidth, fCellHeight, fFinalHeight, fFinalWidth: Single;
begin
  // If the user is currently in the process of selecting
  // a new device and/or configuration then we hand execution
  // straight back to the framework...
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  //Configure the render targets
  V(pd3dDevice.GetRenderTarget(0, pLDRSurface));        //This is the output surface - a standard 32bit device

  // Clear the render target and the zbuffer
  V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, D3DCOLOR_ARGB($ff, $ff, $ff, $ff), 1.0, 0));

  // Render the scene
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    // RENDER THE COMPLETE SCENE
    //--------------------------
    // The first part of each frame is to actually render the "core"
    // resources - those that would be required for an HDR-based pipeline.

      // HDRScene creates an unprocessed, raw, image to work with.
      D3DPERF_BeginEvent(D3DCOLOR_XRGB(255, 0, 0), 'HDRScene Rendering');
        HDRScene.RenderScene(pd3dDevice);
      D3DPERF_EndEvent;

      // Luminance attempts to calculate what sort of tone/mapping should
      // be done as part of the post-processing step.
      D3DPERF_BeginEvent(D3DCOLOR_XRGB(0, 0, 255), 'Luminance Rendering');
        Luminance.MeasureLuminance(pd3dDevice);
      D3DPERF_EndEvent;

      // The post-processing adds the blur to the bright (over-exposed) areas
      // of the image.
      D3DPERF_BeginEvent(D3DCOLOR_XRGB(255, 0, 0), 'Post-Processing Rendering');
        PostProcess.PerformPostProcessing(pd3dDevice);
      D3DPERF_EndEvent;

      // When all the individual components have been created we have the final
      // composition. The output of this is the image that will be displayed
      // on screen.
      D3DPERF_BeginEvent(D3DCOLOR_XRGB(255, 0, 255), 'Final Image Composition');
      begin
        g_pFinalTexture.GetSurfaceLevel(0, pFinalSurf);
        pd3dDevice.SetRenderTarget(0, pFinalSurf);

        HDRScene.GetOutputTexture(pHDRTex);
        Luminance.GetLuminanceTexture(pLumTex);
        PostProcess.GetTexture(pBloomTex);

        pd3dDevice.SetTexture(0, pHDRTex);
        pd3dDevice.SetTexture(1, pLumTex);
        pd3dDevice.SetTexture(2, pBloomTex);

        pd3dDevice.SetPixelShader(g_pFinalPassPS);

        pBloomTex.GetLevelDesc(0, d);
        g_pFinalPassPSConsts.SetFloat(pd3dDevice, 'g_rcp_bloom_tex_w', 1.0 / d.Width);
        g_pFinalPassPSConsts.SetFloat(pd3dDevice, 'g_rcp_bloom_tex_h', 1.0 / d.Height);
        g_pFinalPassPSConsts.SetFloat(pd3dDevice, 'fExposure', g_fExposure);
        g_pFinalPassPSConsts.SetFloat(pd3dDevice, 'fGaussianScalar', PostProcess.GetGaussianMultiplier);

        DrawHDRTextureToScreen;

        pd3dDevice.SetPixelShader(nil);

        pd3dDevice.SetTexture(2, nil);
        pd3dDevice.SetTexture(1, nil);
        pd3dDevice.SetTexture(0, nil);

        pd3dDevice.SetRenderTarget(0, pLDRSurface);

        SAFE_RELEASE(pBloomTex);
        SAFE_RELEASE(pLumTex);
        SAFE_RELEASE(pHDRTex);
        SAFE_RELEASE(pFinalSurf);
      end;
      D3DPERF_EndEvent;



    // RENDER THE GUI COMPONENTS
    //--------------------------
    // The remainder of the rendering is specific to this example rather
    // than to a general-purpose HDRI pipeline. The following code outputs
    // each individual stage of the above process so that, in real-time, you
    // can see exactly what is happening...
    D3DPERF_BeginEvent(D3DCOLOR_XRGB(255, 0, 255), 'GUI Rendering');
    begin
      pLDRSurface.GetDesc(d);

      vv[0].t := D3DXVector2(0.0, 0.0);
      vv[1].t := D3DXVector2(1.0, 0.0);
      vv[2].t := D3DXVector2(0.0, 1.0);
      vv[3].t := D3DXVector2(1.0, 1.0);

      pd3dDevice.SetPixelShader(nil);
      pd3dDevice.SetVertexShader(nil);
      pd3dDevice.SetFVF(FVF_TLVERTEX);

      fCellWidth := (d.Width - 48.0) / 4.0;
      fCellHeight := (d.Height - 36.0) / 4.0;
      fFinalHeight := d.Height - (fCellHeight + 16.0);
      fFinalWidth := fFinalHeight / 0.75;

      vv[0].p := D3DXVector4(fCellWidth + 16.0,                   fCellHeight + 16.0,                0.0, 1.0);
      vv[1].p := D3DXVector4(fCellWidth + 16.0 + fFinalWidth,     fCellHeight + 16.0,                0.0, 1.0);
      vv[2].p := D3DXVector4(fCellWidth + 16.0,                   fCellHeight + 16.0 + fFinalHeight, 0.0, 1.0);
      vv[3].p := D3DXVector4(fCellWidth + 16.0 + fFinalWidth,     fCellHeight + 16.0 + fFinalHeight, 0.0, 1.0);

      pd3dDevice.SetTexture(0, g_pFinalTexture);
      pd3dDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, vv, SizeOf(TTLVertex));

      // Draw the original HDR scene to the GUI
      D3DPERF_BeginEvent(D3DCOLOR_XRGB(255, 0, 0), 'GUI: HDR Scene');
        HDRScene.DrawToScreen(pd3dDevice, g_pFont, g_pTextSprite, g_pArrowTex);
      D3DPERF_EndEvent;

      // Draw the various down-sampling stages to the luminance measurement
      D3DPERF_BeginEvent(D3DCOLOR_XRGB(255, 0, 0), 'GUI: Luminance Measurements');
        Luminance.DisplayLuminance(pd3dDevice, g_pFont, g_pTextSprite, g_pArrowTex);
      D3DPERF_EndEvent;

      // Draw the bright-pass, downsampling and bloom steps
      D3DPERF_BeginEvent(D3DCOLOR_XRGB(255, 0, 0), 'GUI: Post-Processing Effects');
        PostProcess.DisplaySteps(pd3dDevice, g_pFont, g_pTextSprite, g_pArrowTex);
      D3DPERF_EndEvent;
    end;
    D3DPERF_EndEvent;

    D3DPERF_BeginEvent(D3DCOLOR_XRGB(64, 0, 64), 'User Interface Rendering');
      RenderText;
      V(g_HUD.OnRender(fElapsedTime));
      V(g_Config.OnRender(fElapsedTime));
    D3DPERF_EndEvent;

    // We've finished all of the rendering, so make sure that D3D
    // is aware of this...
    V(pd3dDevice.EndScene);
  end;

  //Remove any memory involved in the render target switching
  SAFE_RELEASE(pLDRSurface);
end;


//--------------------------------------------------------------------------------------
// Render the help and statistics text. This function uses the ID3DXFont interface for
// efficient text rendering.
//--------------------------------------------------------------------------------------

const iMaxStringSize = 1024;

procedure RenderText;
var
  pd3dsdBackBuffer: PD3DSurfaceDesc;
  txtHelper: CDXUTTextHelper;
  xOff: DWORD;
  strRT: WideString;
  str: array[0..iMaxStringSize-1] of WideChar;
begin
  // The helper object simply helps keep track of text position, and color
  // and then it calls pFont->DrawText( g_pSprite, strMsg, -1, &rc, DT_NOCLIP, g_clr );
  // If NULL is passed in as the sprite object, then it will work however the
  // pFont->DrawText() will not be batched together.  Batching calls will improves performance.
  pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
  txtHelper:= CDXUTTextHelper.Create(g_pFont, g_pTextSprite, 15);

  // Output statistics
  txtHelper._Begin;
  xOff := 16 + ((pd3dsdBackBuffer.Width - 48) div 4);
  txtHelper.SetInsertionPos(xOff + 5, pd3dsdBackBuffer.Height - 40);
  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));

  txtHelper.SetForegroundColor(D3DXColor(1.0, 0.5, 0.0, 1.0));

  //fill out the text...
  if (g_FloatRenderTargetFmt = D3DFMT_A16B16G16R16F)  then strRT := 'Using 64bit floating-point render targets.'#10
  else if (g_FloatRenderTargetFmt = D3DFMT_A32B32G32R32F) then strRT := 'Using 128bit floating-point render targets.'#10;

  StringCchFormat(str, iMaxStringSize, 'Final Composed Image (%dx%d) @ %dfps.'#10 +
                                       '%s Approx Memory Consumption is %d bytes.'#10,
                                       [pd3dsdBackBuffer.Width,
                                        pd3dsdBackBuffer.Height,
                                        g_dwFrameRate,
                                        strRT,
                                        g_dwApproxMemory]);

  txtHelper.DrawTextLine(str);

  txtHelper.SetInsertionPos(xOff + 5, ((pd3dsdBackBuffer.Height - 36) div 4) + 20);

  txtHelper.DrawTextLine('Drag with LEFT mouse button  : Rotate occlusion cube.');
  txtHelper.DrawTextLine('Drag with RIGHT mouse button : Rotate view of scene.');

  txtHelper._End;
  txtHelper.Free;
end;


//--------------------------------------------------------------------------------------
// Handle messages to the application
//--------------------------------------------------------------------------------------
function MsgProc(hWnd: HWND; uMsg: LongWord; wParam: WPARAM; lParam: LPARAM; out pbNoFurtherProcessing: Boolean; pUserContext: Pointer): LRESULT; stdcall;
begin
  Result:= 0;

  // Always allow dialog resource manager calls to handle global messages
  // so GUI state is updated correctly
  pbNoFurtherProcessing := g_DialogResourceManager.MsgProc(hWnd, uMsg, wParam, lParam);
  if pbNoFurtherProcessing then Exit;

  if g_SettingsDlg.IsActive then
  begin
    g_SettingsDlg.MsgProc(hWnd, uMsg, wParam, lParam);
    Exit;
  end;

  // Give on screen UI a chance to handle this message
  pbNoFurtherProcessing := g_HUD.MsgProc(hWnd, uMsg, wParam, lParam);
  if pbNoFurtherProcessing then Exit;

  pbNoFurtherProcessing := g_Config.MsgProc(hWnd, uMsg, wParam, lParam);
  if pbNoFurtherProcessing then Exit;

  // Pass all windows messages to camera so it can respond to user input
  g_Camera.HandleMessages(hWnd, uMsg, wParam, lParam);
end;


//--------------------------------------------------------------------------------------
// Handles the GUI events
//--------------------------------------------------------------------------------------
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
var
  str: array[0..99] of WideChar;
  fNewThreshold: Single;
  mul: Single;
  mean: Single;
  sd: Single;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;

    IDC_THRESHOLDSLIDER:
    begin
      fNewThreshold := g_Config.GetSlider(IDC_THRESHOLDSLIDER).Value / 10.0;
      PostProcess.SetBrightPassThreshold(fNewThreshold);
      StringCchFormat(str, 100, 'Bright-Pass Threshold: (%f)', [fNewThreshold]);
      g_Config.GetStatic(IDC_THRESHOLDLABEL).Text := str;
    end;

    IDC_EXPOSURESLIDER:
    begin
      g_fExposure := g_Config.GetSlider(IDC_EXPOSURESLIDER).Value / 100.0;
      StringCchFormat(str, 100, 'Exposure: (%f)', [g_fExposure]);
      g_Config.GetStatic(IDC_EXPOSURELABEL).Text := str;
    end;

    IDC_MULTIPLIERSLIDER:
    begin
      mul := g_Config.GetSlider(IDC_MULTIPLIERSLIDER).Value / 10.0;
      PostProcess.SetGaussianMultiplier(mul);
      StringCchFormat(str, 100, 'Gaussian Multiplier: (%f)', [mul]);
      g_Config.GetStatic(IDC_MULTIPLIERLABEL).Text := str;
    end;

    IDC_MEANSLIDER:
    begin
      mean := g_Config.GetSlider(IDC_MEANSLIDER).Value / 10.0;
      PostProcess.SetGaussianMean(mean);
      StringCchFormat(str, 100, 'Gaussian Mean: (%f)', [mean]);
      g_Config.GetStatic(IDC_MEANLABEL).Text := str;
    end;

    IDC_STDDEVSLIDER:
    begin
      sd := g_Config.GetSlider(IDC_STDDEVSLIDER).Value / 10.0;
      PostProcess.SetGaussianStandardDeviation(sd);
      StringCchFormat(str, 100, 'Gaussian Std. Dev: (%f)', [sd]);
      g_Config.GetStatic(IDC_STDDEVLABEL).Text := str;
    end;
  end;
end;


//--------------------------------------------------------------------------------------
// Release resources created in the OnResetDevice callback here
//--------------------------------------------------------------------------------------
procedure OnLostDevice(pUserContext: Pointer); stdcall;
begin
  // Let the GUI do it's lost-device work:
  g_DialogResourceManager.OnLostDevice;
  g_SettingsDlg.OnLostDevice;

  if (g_pFont <> nil) then g_pFont.OnLostDevice;
  SAFE_RELEASE(g_pTextSprite);
  SAFE_RELEASE(g_pArrowTex);

  // Free up the HDR resources
  SAFE_RELEASE(g_pFinalTexture);

  // Free up the final screen pass resources
  SAFE_RELEASE(g_pFinalPassPS);
  SAFE_RELEASE(g_pFinalPassPSConsts);

  HDRScene.DestroyResources;
  Luminance.DestroyResources;
  PostProcess.DestroyResources;
end;


//--------------------------------------------------------------------------------------
// Release resources created in the OnCreateDevice callback here
//--------------------------------------------------------------------------------------
procedure OnDestroyDevice; stdcall;
begin
  g_DialogResourceManager.OnDestroyDevice;
  g_SettingsDlg.OnDestroyDevice;

  SAFE_RELEASE(g_pFont);
  SAFE_RELEASE(g_pTextSprite);
  SAFE_RELEASE(g_pArrowTex);

  // Free up the HDR resources
  SAFE_RELEASE(g_pFinalTexture);

  // Free up the final screen pass resources
  SAFE_RELEASE(g_pFinalPassPS);
  SAFE_RELEASE(g_pFinalPassPSConsts);

  HDRScene.DestroyResources;
  Luminance.DestroyResources;
  PostProcess.DestroyResources;
end;



//--------------------------------------------------------------------------------------
//  The last stage of the HDR pipeline requires us to take the image that was rendered
//  to an HDR-format texture and map it onto a LDR render target that can be displayed
//  on screen. This is done by rendering a screen-space quad and setting a pixel shader
//  up to map HDR->LDR.
//--------------------------------------------------------------------------------------
procedure DrawHDRTextureToScreen;
var
  pDev: IDirect3DDevice9;
  desc: TD3DSurfaceDesc;
  pSurfRT: IDirect3DSurface9;
  fWidth: Single; 
  fHeight: Single;
  v: array[0..3] of TTLVertex; 
begin
  // Find out what dimensions the screen is
  pDev := DXUTGetD3DDevice;

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
  v[1].t := D3DXVector2(1.0, 0.0);

  v[2].p := D3DXVector4(-0.5, fHeight, 0.0, 1.0);
  v[2].t := D3DXVector2(0.0, 1.0);

  v[3].p := D3DXVector4(fWidth, fHeight, 0.0, 1.0);
  v[3].t := D3DXVector2(1.0, 1.0);

  // Configure the device and render..
  pDev.SetVertexShader(nil);
  pDev.SetFVF(FVF_TLVERTEX);
  pDev.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
  pDev.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);
  pDev.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, SizeOf(TTLVertex));
end;



procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera:= CModelViewerCamera.Create;
  g_HUD:= CDXUTDialog.Create;
  g_Config:= CDXUTDialog.Create;
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_Camera);
  FreeAndNil(g_HUD);
  FreeAndNil(g_Config);
end;

end.

