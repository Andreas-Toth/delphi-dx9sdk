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
 *  $Id: ParallaxOcclusionMappingUnit.pas,v 1.5 2007/02/05 22:21:11 clootie Exp $
 *----------------------------------------------------------------------------*)
//=================================================================================================
// File: ParallaxOcclusionMapping.cpp
//
// Author: Natalya Tatarchuk
//         ATI Research, Inc.
//         3D Application Research Group
//
// Implementation of the algorithm as described in "Dynamic Parallax Occlusion Mapping with
// Approximate Soft Shadows" paper, by N. Tatarchuk, ATI Research, to appear in the proceedings
// of ACM Symposium on Interactive 3D Graphics and Games, 2006.
//
// Copyright (c) ATI Research, Inc. All rights reserved.
//=================================================================================================

{$I DirectX.inc}

unit ParallaxOcclusionMappingUnit;

interface

uses
  Windows, SysUtils, StrSafe,
  DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTenum, DXUTmisc, DXUTgui, DXUTSettingsDlg;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders

//--------------------------------------------------------------------------------------
// Global variables and parameters
//--------------------------------------------------------------------------------------
const s_iMAX_STRING_SIZE = 100;
const s_iDECL_SIZE       = 56;
const s_iNUM_TEXTURES    = 7;  // Number of loaded texturs in the program

//--------------------------------------------------------------------------------------
// Texture pair ids for use for this sample
//--------------------------------------------------------------------------------------
type
  TPOM_TextureIDs = (
    pomStones,
    pomRocks,
    pomWall,
    pomFourBumps,
    pomBumps,
    pomDents,
    pomSaint
  );

//--------------------------------------------------------------------------------------
// Id numbers for different rendering techniques used
//--------------------------------------------------------------------------------------
  TTechniqueIDs = (
    tidPOM,           // Parallax occlusion mapping
    tidBumpmap,       // Bump mapping
    tidPM             // Parallax mapping with offset limiting
  );

var
  g_nCurrentTextureID: TPOM_TextureIDs = pomStones;
  g_nCurrentTechniqueID: TTechniqueIDs = tidPOM;

//--------------------------------------------------------------------------------------
// Texture pair names for use for this sample
//--------------------------------------------------------------------------------------
const
  g_strBaseTextureNames: array [TPOM_TextureIDs] of PWideChar = (
    'stones.bmp',
    'rocks.jpg',
    'wall.jpg',
    'wood.jpg',
    'concrete.bmp',
    'concrete.bmp',
    'wood.jpg'
  );

  g_strNMHTextureNames: array [TPOM_TextureIDs] of PWideChar = (
    'stones_NM_height.tga',
    'rocks_NM_height.tga',
    'wall_NM_height.tga',
    'four_NM_height.tga',
    'bump_NM_height.tga',
    'dent_NM_height.tga',
    'saint_NM_height.tga'
  );


type
  PIDirect3DTexture9Array = ^TIDirect3DTexture9Array;
  TIDirect3DTexture9Array = array[TPOM_TextureIDs] of IDirect3DTexture9; // [0..MaxInt div SizeOf(IDirect3DTexture9) - 1]

//--------------------------------------------------------------------------------------
var
  g_pD3DDevice: IDirect3DDevice9; // A pointer to the current D3D device used for rendering

  g_pFont: ID3DXFont;             // Font for drawing text
  g_pSprite: ID3DXSprite;         // Sprite for batching draw text calls
  g_bShowHelp: Boolean = False;   // If true, it renders the UI control text
  g_Camera: CModelViewerCamera;   // A model viewing camera
  g_pEffect: ID3DXEffect;         // D3DX effect interface
  g_pMesh: ID3DXMesh;             // Mesh object

  g_pBaseTextures: PIDirect3DTexture9Array = nil; // Array of base map texture surfaces
  g_pNMHTextures: PIDirect3DTexture9Array  = nil; // Array of normal / height map texture surfaces
                                                  //       a height map in the alpha channel

  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg; // Device settings dialog
  g_HUD: CDXUTDialog;             // manages the 3D UI
  g_SampleUI: CDXUTDialog;        // dialog for sample specific controls
  g_mWorldFix: TD3DXMatrixA16;

  g_LightControl: CDXUTDirectionWidget; // Scene light
  g_fLightScale: Single;                // Light brightness scale parameter


//--------------------------------------------------------------------------------------
// UI scalar parameters
//--------------------------------------------------------------------------------------
const s_fLightScaleUIScale   = 10.0;
const s_iLightScaleSliderMin = 0;
const s_iLightScaleSliderMax = 20;

var
  g_iHeightScaleSliderMin: Integer = 0;
  g_iHeightScaleSliderMax: Integer = 100;
  g_fHeightScaleUIScale: Single = 100.0;

const s_iSliderMin = 8;
const s_iSliderMax = 130;

//--------------------------------------------------------------------------------------
// Material properties parameters:
//--------------------------------------------------------------------------------------
var
  g_colorMtrlDiffuse: TD3DXColor = (r:1.0; g:1.0; b:1.0; a:1.0);
  g_colorMtrlAmbient: TD3DXColor = (r:0.35; g:0.35; b:0.35; a:0);
  g_colorMtrlSpecular: TD3DXColor = (r:1.0; g:1.0; b:1.0; a:1.0);

  g_fSpecularExponent: Single = 60.0;        // Material's specular exponent
  g_fBaseTextureRepeat:  Single = 1.0;       // The tiling factor for base and normal map textures

  g_bVisualizeLOD: Boolean = False;          // Toggles visualization of level of detail colors
  g_bVisualizeMipLevel: Boolean = False;     // Toggles visualization of mip level
  g_bDisplayShadows: Boolean = True;         // Toggles display of self-occlusion based shadows
  g_bAddSpecular: Boolean = True;            // Toggles rendering with specular or without
  g_bRenderPOM: Boolean = True;              // Toggles whether using normal mapping or parallax occlusion mapping

  g_nLODThreshold: Integer = 3;              // The mip level id for transitioning between the full computation
                                             // for parallax occlusion mapping and the bump mapping computation
  g_nMinSamples: Integer = 8;                // The minimum number of samples for sampling the height field profile
  g_nMaxSamples: Integer = 50;               // The maximum number of samples for sampling the height field profile
  g_fShadowSoftening:  Single = 0.58;        // Blurring factor for the soft shadows computation
  g_fHeightScale:  Single;                   // This parameter controls the height map range for displacement mapping

//--------------------------------------------------------------------------------------
// Mesh file names for use
//--------------------------------------------------------------------------------------
const
  g_strMeshFileName0 = 'Disc.x';


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_TOGGLEFULLSCREEN           = 1;
  IDC_TOGGLEREF                  = 3;
  IDC_CHANGEDEVICE               = 4;
  IDC_HEIGHT_SCALE_SLIDER        = 5;
  IDC_HEIGHT_SCALE_STATIC        = 6;
  IDC_TOGGLE_SHADOWS             = 7;
  IDC_SELECT_TEXTURES_COMBOBOX   = 8;
  IDC_TOGGLE_SPECULAR            = 9;
  IDC_SPECULAR_EXPONENT_SLIDER   = 10;
  IDC_SPECULAR_EXPONENT_STATIC   = 11;
  IDC_MIN_NUM_SAMPLES_SLIDER     = 12;
  IDC_MIN_NUM_SAMPLES_STATIC     = 13;
  IDC_MAX_NUM_SAMPLES_SLIDER     = 14;
  IDC_MAX_NUM_SAMPLES_STATIC     = 15;
  IDC_TECHNIQUE_COMBO_BOX        = 16;
  IDC_RELOAD_BUTTON              = 20;


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
procedure KeyboardProc(nChar: LongWord; bKeyDown, bAltDown: Boolean; pUserContext: Pointer); stdcall;
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
procedure OnLostDevice(pUserContext: Pointer); stdcall;
procedure OnDestroyDevice(pUserContext: Pointer); stdcall;

procedure InitApp;
function LoadMesh(const pd3dDevice: IDirect3DDevice9; strFileName: PWideChar; out ppMesh: ID3DXMesh): HRESULT;
procedure RenderText(fTime: Double);

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;


implementation


//--------------------------------------------------------------------------------------
// Select a pair of base and normal map / height map textures to use and
// setup related height map range parameters, given a texture index
// Note: all texture surfaces in g_pBaseTextures and g_pNMHTextures MUST
// be created prior to calling this function.
//--------------------------------------------------------------------------------------
procedure SetPOMTextures(iTextureIndex: TPOM_TextureIDs);
begin
  g_nCurrentTextureID := iTextureIndex;

  // Bind the new active textures to the correct texture slots in the shaders:
  if Assigned(g_pD3DDevice) and Assigned(g_pEffect) then
  begin
     V(g_pEffect.SetTexture('g_baseTexture', g_pBaseTextures[g_nCurrentTextureID]));
     V(g_pEffect.SetTexture('g_nmhTexture',  g_pNMHTextures[g_nCurrentTextureID]));
  end;

  // Setup height map range slider parameters (need to be setup per-texture, as very height-map specific:
  case iTextureIndex of
    pomStones:
    begin
      // Stones texture pair:
      g_iHeightScaleSliderMin := 0;
      g_iHeightScaleSliderMax := 10;
      g_fHeightScaleUIScale   := 100.0;
      g_fHeightScale          := 0.02;

      g_fSpecularExponent  := 60.0;
      g_fBaseTextureRepeat := 1.0;

      g_nMinSamples := 8;
      g_nMaxSamples := 50;
    end;

    pomRocks:
    begin
      g_iHeightScaleSliderMin := 0;
      g_iHeightScaleSliderMax := 10;
      g_fHeightScaleUIScale   := 100.0;
      g_fHeightScale          := 0.1;

      g_fSpecularExponent  := 100.0;
      g_fBaseTextureRepeat := 1.0;

      g_nMinSamples := 8;
      g_nMaxSamples := 100;
    end;

    pomWall:
    begin
      g_iHeightScaleSliderMin := 0;
      g_iHeightScaleSliderMax := 10;
      g_fHeightScaleUIScale   := 100.0;
      g_fHeightScale          := 0.06;

      g_fSpecularExponent := 60.0;
      g_fBaseTextureRepeat := 1.0;

      g_nMinSamples := 8;
      g_nMaxSamples := 50;
    end;

    pomFourBumps:
    begin
      g_iHeightScaleSliderMin := 0;
      g_iHeightScaleSliderMax := 10;
      g_fHeightScaleUIScale   := 10.0;
      g_fHeightScale          := 0.2;

      g_fSpecularExponent := 100.0;
      g_fBaseTextureRepeat := 1.0;
      g_nMinSamples := 12;
      g_nMaxSamples := 100;
    end;

    pomBumps:
    begin
      g_iHeightScaleSliderMin := 0;
      g_iHeightScaleSliderMax := 10;
      g_fHeightScaleUIScale   := 10.0;
      g_fHeightScale          := 0.2;

      g_fSpecularExponent := 100.0;
      g_fBaseTextureRepeat := 4.0;
      g_nMinSamples := 12;
      g_nMaxSamples := 100;
    end;

    pomDents:
    begin
      g_iHeightScaleSliderMin := 0;
      g_iHeightScaleSliderMax := 10;
      g_fHeightScaleUIScale   := 10.0;
      g_fHeightScale          := 0.2;

      g_fSpecularExponent := 100.0;
      g_fBaseTextureRepeat := 4.0;
      g_nMinSamples := 12;
      g_nMaxSamples := 100;
    end;

    pomSaint:
    begin
      g_iHeightScaleSliderMin := 0;
      g_iHeightScaleSliderMax := 10;
      g_fHeightScaleUIScale   := 100.0;
      g_fHeightScale          := 0.08;

      g_fSpecularExponent := 100.0;
      g_fBaseTextureRepeat := 1.0;
      g_nMinSamples := 12;
      g_nMaxSamples := 100;
    end;
  end;
end;


//--------------------------------------------------------------------------------------
// Initialize the app: initialize the light controls and the GUI
// elements for this application.
//--------------------------------------------------------------------------------------
procedure InitApp;
const
  // UI elements parameters:
  ciPadding = 24;        // vertical padding between controls
  ciLeft    = 5;         // Left align border (x-coordinate) of the controls
  ciWidth   = 125;       // widget width
  ciHeight  = 22;        // widget height
  // Slider parameters:
  ciSliderLeft  = 15;
  ciSliderWidth = 100;
var
  iY: Integer;
  sz: array[0..s_iMAX_STRING_SIZE-1] of WideChar;
  pTechniqueComboBox: CDXUTComboBox;
  pTextureComboBox: CDXUTComboBox;
begin
  // Initialize the light control:
  g_LightControl.SetLightDirection(D3DXVector3( Sin(D3DX_PI * 2 - D3DX_PI / 6),
                                                0,
                                                -Cos(D3DX_PI * 2 - D3DX_PI / 6)));
  g_fLightScale  := 1.0;

  // Initialize POM textures and height map parameters:
  SetPOMTextures(pomStones);

  // Initialize dialogs //
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_SampleUI.Init(g_DialogResourceManager);

  // Initialize user interface elements //

  // Top toggle buttons //
  g_HUD.SetCallback(OnGUIEvent);

  iY := 10;
  g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', ciLeft, iY, ciWidth, ciHeight); Inc(iY, ciPadding);
  g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)', ciLeft, iY, ciWidth, ciHeight); Inc(iY, ciPadding);
  g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)', ciLeft, iY, ciWidth, ciHeight, VK_F2); // Inc(iY, 24);

  // Reload button only works in debug:
  {$IFDEF _DEBUG}
   g_HUD.AddButton(IDC_RELOAD_BUTTON, 'Reload effect', ciLeft, iY, ciWidth, ciHeight);
  {$ENDIF}

  iY := 10;
  g_SampleUI.SetCallback(OnGUIEvent);

  // Technique selection combo box
  pTechniqueComboBox := nil;
  g_SampleUI.AddComboBox(IDC_TECHNIQUE_COMBO_BOX, ciLeft, iY, 200, 24, Ord('O'), False, @pTechniqueComboBox);
  if Assigned(pTechniqueComboBox) then
  begin
    pTechniqueComboBox.SetDropHeight(100);
    pTechniqueComboBox.AddItem('Parallax Occlusion Mapping',              Pointer(tidPOM));
    pTechniqueComboBox.AddItem('Bump Mapping',                            Pointer(tidBUMPMAP));
    pTechniqueComboBox.AddItem('Parallax Mapping with Offset Limiting',   Pointer(tidPM));
  end;

  // Add control for height range //
  iY := iY + ciPadding;
  StringCchFormat(sz, s_iMAX_STRING_SIZE, 'Height scale: %f', [g_fHeightScale]);
  g_SampleUI.AddStatic(IDC_HEIGHT_SCALE_STATIC, sz, ciLeft, iY, ciWidth, ciHeight);

  iY := iY + ciPadding;
  g_SampleUI.AddSlider(IDC_HEIGHT_SCALE_SLIDER, ciSliderLeft, iY, ciSliderWidth, ciHeight, g_iHeightScaleSliderMin, g_iHeightScaleSliderMax,
                       Trunc(g_fHeightScale * g_fHeightScaleUIScale));

  // Texture selection combo box:
  iY := iY + ciPadding;
  pTextureComboBox := nil;
  //todo: Fill bug request for L'O' in original sample
  g_SampleUI.AddComboBox(IDC_SELECT_TEXTURES_COMBOBOX, ciLeft, iY, 200, 24, Ord('T'), False, @pTextureComboBox);
  if Assigned(pTextureComboBox) then
  begin
     pTextureComboBox.SetDropHeight(100);
     pTextureComboBox.AddItem('Stones',                           Pointer(pomStones     ));
     pTextureComboBox.AddItem('Rocks',                            Pointer(pomROCKS      ));
     pTextureComboBox.AddItem('Wall',                             Pointer(pomWALL       ));
     pTextureComboBox.AddItem('Sphere, Triangle, Torus, Pyramid', Pointer(pomFOURBUMPS  ));
     pTextureComboBox.AddItem('Bumps',                            Pointer(pomBUMPS      ));
     pTextureComboBox.AddItem('Dents',                            Pointer(pomDENTS      ));
     pTextureComboBox.AddItem('Relief',                           Pointer(pomSAINT      ));

  end;

  // Toggle shadows checkbox
  iY := iY + ciPadding;
  g_SampleUI.AddCheckBox(IDC_TOGGLE_SHADOWS, 'Toggle self-occlusion shadows rendering: ON',
                         ciLeft, iY, 350, 24, g_bDisplayShadows, Ord('C'), False);

  // Toggle specular checkbox
  iY := iY + ciPadding;
  g_SampleUI.AddCheckBox(IDC_TOGGLE_SPECULAR, 'Toggle specular: ON',
                         ciLeft, iY, 350, 24, g_bAddSpecular, Ord('C'), False);


  // Specular exponent slider:
  iY := iY + ciPadding;
  StringCchFormat(sz, s_iMAX_STRING_SIZE, 'Specular exponent: %f', [g_fSpecularExponent]);
  g_SampleUI.AddStatic(IDC_SPECULAR_EXPONENT_STATIC, sz, ciLeft, iY, ciWidth, ciHeight);

  iY := iY + ciPadding;
  g_SampleUI.AddSlider(IDC_SPECULAR_EXPONENT_SLIDER, ciSliderLeft, iY, ciSliderWidth, ciHeight,
                       s_iSliderMin, s_iSliderMax, Trunc(g_fSpecularExponent));

  // Number of samples: minimum
  iY := iY + ciPadding;
  StringCchFormat(sz, s_iMAX_STRING_SIZE, 'Minium number of samples: %d', [g_nMinSamples]);
  g_SampleUI.AddStatic(IDC_MIN_NUM_SAMPLES_STATIC, sz, ciLeft, iY, ciWidth * 2, ciHeight);
  g_SampleUI.GetStatic(IDC_MIN_NUM_SAMPLES_STATIC).Element[0].dwTextFormat := DT_LEFT or DT_TOP or DT_WORDBREAK;

  iY := iY + ciPadding;
  g_SampleUI.AddSlider(IDC_MIN_NUM_SAMPLES_SLIDER, ciSliderLeft, iY, ciSliderWidth, ciHeight,
                       s_iSliderMin, s_iSliderMax, g_nMinSamples);

  // Number of samples: maximum
  iY := iY + ciPadding;
  StringCchFormat(sz, s_iMAX_STRING_SIZE, 'Maximum number of samples: %d', [g_nMaxSamples]);
  g_SampleUI.AddStatic(IDC_MAX_NUM_SAMPLES_STATIC, sz, ciLeft, iY, ciWidth * 2, ciHeight);
  g_SampleUI.GetStatic(IDC_MAX_NUM_SAMPLES_STATIC).Element[0].dwTextFormat := DT_LEFT or DT_TOP or DT_WORDBREAK;


  iY := iY + ciPadding;
  g_SampleUI.AddSlider(IDC_MAX_NUM_SAMPLES_SLIDER, ciSliderLeft, iY, ciSliderWidth, ciHeight,
                       s_iSliderMin, s_iSliderMax, g_nMaxSamples);
end;


//--------------------------------------------------------------------------------------
// Called during device initialization, this code checks the device for some
// minimum set of capabilities, and rejects those that don't pass by
// returning E_FAIL.
//--------------------------------------------------------------------------------------
function IsDeviceAcceptable(const pCaps: TD3DCaps9; AdapterFormat, BackBufferFormat: TD3DFormat; bWindowed: Boolean; pUserContext: Pointer): Boolean; stdcall;
var
  pD3D: IDirect3D9;
begin
  Result := False;

  // The ParallaxOcculsionMapping technique requires PS 3.0 so reject any device that
  // doesn't support at least PS 3.0.  Typically, the app would fallback but
  // ParallaxOcculsionMapping is the purpose of this sample
  if (pCaps.PixelShaderVersion < D3DPS_VERSION(3, 0)) then Exit;

  // Skip backbuffer formats that don't support alpha blending
  pD3D := DXUTGetD3DObject;
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                   AdapterFormat, D3DUSAGE_QUERY_POSTPIXELSHADER_BLENDING,
                   D3DRTYPE_TEXTURE, BackBufferFormat))
  then Exit;

  Result := True;
end;


//--------------------------------------------------------------------------------------
// Called right before creating a D3D9 device, allowing the app to modify the device settings as needed
//--------------------------------------------------------------------------------------
{static} var s_bFirstTime: Boolean = True;

function ModifyDeviceSettings(var pDeviceSettings: TDXUTDeviceSettings; const pCaps: TD3DCaps9; pUserContext: Pointer): Boolean; stdcall;
begin
  // If device doesn't support VS 3.0 then switch to SWVP
  if (pDeviceSettings.DeviceType <> D3DDEVTYPE_REF) and
     ((pCaps.DevCaps and D3DDEVCAPS_HWTRANSFORMANDLIGHT = 0) or (pCaps.VertexShaderVersion < D3DVS_VERSION(3, 0)))
  then pDeviceSettings.BehaviorFlags := D3DCREATE_SOFTWARE_VERTEXPROCESSING;

  // Debugging vertex shaders requires either REF or software vertex processing
  // and debugging pixel shaders requires REF.
{$IFDEF DEBUG_VS}
  if (pDeviceSettings.DeviceType <> D3DDEVTYPE_REF) then
  with pDeviceSettings do
  begin
    BehaviorFlags := BehaviorFlags and not D3DCREATE_HARDWARE_VERTEXPROCESSING;
    BehaviorFlags := BehaviorFlags and not D3DCREATE_PUREDEVICE;
    BehaviorFlags := BehaviorFlags or D3DCREATE_SOFTWARE_VERTEXPROCESSING;
  end;
{$ENDIF}
{$IFDEF DEBUG_PS}
  pDeviceSettings.DeviceType := D3DDEVTYPE_REF;
{$ENDIF}

  // Turn off VSynch
  pDeviceSettings.pp.PresentationInterval := D3DPRESENT_INTERVAL_IMMEDIATE;

  // For the first device created if its a REF device, optionally display a warning dialog box
  if s_bFirstTime then
  begin
    s_bFirstTime := False;
    if (pDeviceSettings.DeviceType = D3DDEVTYPE_REF) then DXUTDisplaySwitchingToREFWarning;
  end;

  Result:= True;
end;


//--------------------------------------------------------------------------------------
// Loads the effect file from disk. Note: D3D device must be created and set
// prior to calling this method.
//--------------------------------------------------------------------------------------
function LoadEffectFile: HRESULT;
var
  dwShaderFlags: DWORD;
  str: array[0..MAX_PATH-1] of WideChar;
  pErrors: ID3DXBuffer;
begin
  SAFE_RELEASE(g_pEffect);

  if (g_pD3DDevice = nil) then
  begin
    Result:= E_FAIL;
    Exit;
  end;

  dwShaderFlags := D3DXFX_NOT_CLONEABLE;

  {$IFDEF DEBUG}
  // Set the D3DXSHADER_DEBUG flag to embed debug information in the shaders.
  // Setting this flag improves the shader debugging experience, but still allows
  // the shaders to be optimized and to run exactly the way they will run in
  // the release configuration of this program.
  dwShaderFlags := dwShaderFlags or D3DXSHADER_DEBUG;
  {$ENDIF}

  {$IFDEF DEBUG_VS}
   dwShaderFlags := dwShaderFlags or D3DXSHADER_FORCE_VS_SOFTWARE_NOOPT;
  {$ENDIF}
  {$IFDEF DEBUG_PS}
   dwShaderFlags := dwShaderFlags or D3DXSHADER_FORCE_PS_SOFTWARE_NOOP;
  {$ENDIF}

  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'ParallaxOcclusionMapping.fx');
  if V_Failed(Result) then Exit;

  //todo: FIX ME!!!
  // D3DXCreateBuffer(1024, pErrors);

  Result := D3DXCreateEffectFromFileW(g_pD3DDevice, str, nil, nil, dwShaderFlags, nil, g_pEffect, @pErrors);

  if FAILED(Result) then
  begin
    // Output shader compilation errors to the shell:
    WriteLn(PChar(pErrors.GetBufferPointer));
    Result:= E_FAIL;
    Exit;
  end;

  SAFE_RELEASE(pErrors);

  Result:= S_OK;
end;

//--------------------------------------------------------------------------------------
// Create any D3D9 resources that will live through a device reset (D3DPOOL_MANAGED)
// and aren't tied to the back buffer size
//--------------------------------------------------------------------------------------
function OnCreateDevice(const pd3dDevice: IDirect3DDevice9; const pBackBufferSurfaceDesc: TD3DSurfaceDesc; pUserContext: Pointer): HRESULT; stdcall;
var
  pData: PD3DXVector3;
  vCenter: TD3DXVector3;
  fObjectRadius: Single;
  mRotation: TD3DXMatrixA16;
  str: array[0..MAX_PATH-1] of WideChar;
  vecEye, vecAt: TD3DXVector3;
  iTextureIndex: TPOM_TextureIDs;
begin
  g_pD3DDevice := pd3dDevice;

  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  // Initialize the font
  Result := D3DXCreateFont(pd3dDevice, 15, 0, FW_BOLD, 1, FALSE, DEFAULT_CHARSET,
                           OUT_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE,
                           'Arial', g_pFont);
  if V_Failed(Result) then Exit;

  // Load the mesh
  Result := LoadMesh(pd3dDevice, g_strMeshFileName0, g_pMesh);
  if V_Failed(Result) then Exit;

  V(g_pMesh.LockVertexBuffer(0, Pointer(pData)));
  V(D3DXComputeBoundingSphere(pData, g_pMesh.GetNumVertices, s_iDECL_SIZE, vCenter, fObjectRadius ));
  V(g_pMesh.UnlockVertexBuffer);

  // Align the starting frame of the mesh to be slightly toward the viewer yet to
  // see the grazing angles:
  D3DXMatrixTranslation(g_mWorldFix, -vCenter.x, -vCenter.y, -vCenter.z);
  D3DXMatrixRotationY(mRotation, -D3DX_PI / 3.0);
  D3DXMatrixMultiply(g_mWorldFix, g_mWorldFix, mRotation); // g_mWorldFix *= mRotation;
  D3DXMatrixRotationX(mRotation, D3DX_PI / 3.0);
  D3DXMatrixMultiply(g_mWorldFix, g_mWorldFix, mRotation); // g_mWorldFix *= mRotation;

  // Initialize the light control
  Result:= CDXUTDirectionWidget.StaticOnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  g_LightControl.Radius := fObjectRadius;

  Result:= LoadEffectFile;
  if V_Failed(Result) then Exit;

  // Load all textures used by the program from disk

  New(g_pBaseTextures); // g_pBaseTextures := ( IDirect3DTexture9** ) malloc( SizeOf( IDirect3DTexture9* ) * s_iNUM_TEXTURES);
  ZeroMemory(g_pBaseTextures, SizeOf(TIDirect3DTexture9Array));
  if (g_pBaseTextures = nil) then //Clootie: Delphi will raise an exception here, so actually this code will never execute
  begin
    // ERROR allocating the array for base texture pointers storage!
    WriteLn('ERROR allocating the array for base texture pointers storage!');
    Result:= E_FAIL;
    Exit;
  end;

  New(g_pNMHTextures); // g_pNMHTextures = ( IDirect3DTexture9** ) malloc( sizeof( IDirect3DTexture9* ) * s_iNUM_TEXTURES );
  ZeroMemory(g_pNMHTextures, SizeOf(TIDirect3DTexture9Array));
  if (g_pNMHTextures = nil) then
  begin
    // ERROR allocating the array for normal map / height map texture pointers storage!
    WriteLn('ERROR allocating the array for normal map / height map texture pointers storage!');
    Result:= E_FAIL;
    Exit;
  end;

  for iTextureIndex := Low(iTextureIndex) to High(iTextureIndex) do
  begin
    // Load the pair of textures (base and combined normal map / height map texture) into
    // memory for each type of POM texture pairs

    // Load the base mesh:
    Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, g_strBaseTextureNames[iTextureIndex]);
    if V_Failed(Result) then Exit;

    Result:= D3DXCreateTextureFromFileExW(pd3dDevice, str, D3DX_DEFAULT, D3DX_DEFAULT,
                                          D3DX_DEFAULT, 0, D3DFMT_UNKNOWN, D3DPOOL_MANAGED,
                                          D3DX_DEFAULT, D3DX_DEFAULT, 0,
                                          nil, nil, g_pBaseTextures[iTextureIndex]);
    if V_Failed(Result) then Exit;

    // Load the normal map / height map texture
    Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, g_strNMHTextureNames[iTextureIndex]);
    if V_Failed(Result) then Exit;

    Result:= D3DXCreateTextureFromFileExW(pd3dDevice, str, D3DX_DEFAULT, D3DX_DEFAULT,
                                          D3DX_DEFAULT, 0, D3DFMT_UNKNOWN, D3DPOOL_MANAGED,
                                          D3DX_DEFAULT, D3DX_DEFAULT, 0,
                                          nil, nil, g_pNMHTextures[iTextureIndex]);
    if V_Failed(Result) then Exit;
  end;

  SetPOMTextures( g_nCurrentTextureID);

  // Setup the camera's view parameters
  vecEye := D3DXVector3(0.0, 0.0, -15.0);
  vecAt  := D3DXVector3(0.0, 0.0, -0.0);
  g_Camera.SetViewParams(vecEye, vecAt);
  g_Camera.SetRadius(fObjectRadius*3.0, fObjectRadius*0.5, fObjectRadius*10.0);

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// This function loads the mesh and ensures the mesh has normals; it also
// optimizes the mesh for the graphics card's vertex cache, which improves
// performance by organizing the internal triangle list for less cache misses.
//--------------------------------------------------------------------------------------
var
  // Create a new vertex declaration to hold all the required data
  vertexDecl: array [0..5] of TD3DVertexElement9 =
  (
    (Stream: 0; Offset: 0;  _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_POSITION; UsageIndex: 0),
    (Stream: 0; Offset: 12; _Type: D3DDECLTYPE_FLOAT2; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TEXCOORD;   UsageIndex: 0),
    (Stream: 0; Offset: 20; _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_NORMAL; UsageIndex: 0),
    (Stream: 0; Offset: 32; _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_TANGENT; UsageIndex: 0),
    (Stream: 0; Offset: 44; _Type: D3DDECLTYPE_FLOAT3; Method: D3DDECLMETHOD_DEFAULT; Usage: D3DDECLUSAGE_BINORMAL; UsageIndex: 0),
    {D3DDECL_END()}(Stream:$FF; Offset:0; _Type:D3DDECLTYPE_UNUSED; Method:TD3DDeclMethod(0); Usage:TD3DDeclUsage(0); UsageIndex:0)
  );

function LoadMesh(const pd3dDevice: IDirect3DDevice9; strFileName: PWideChar; out ppMesh: ID3DXMesh): HRESULT;
var
  pMesh: ID3DXMesh;
  str: array[0..MAX_PATH-1] of WideChar;
  pTempMesh: ID3DXMesh;
  bHadNormal: Boolean;
  bHadTangent: Boolean;
  bHadBinormal: Boolean;
  vertexOldDecl: TFVFDeclaration;
  iChannelIndex: LongWord;
  rgdwAdjacency: PDWORD;
  pNewMesh: ID3DXMesh;
begin
  // Load the mesh with D3DX and get back a ID3DXMesh*.  For this
  // sample we'll ignore the X file's embedded materials since we know
  // exactly the model we're loading.  See the mesh samples such as
  // "OptimizedMesh" for a more generic mesh loading example.
  Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, strFileName);
  if V_Failed(Result) then Exit;
  Result := D3DXLoadMeshFromXW(str, D3DXMESH_MANAGED, pd3dDevice, nil, nil, nil, nil, pMesh);
  if V_Failed(Result) then Exit;

  // Clone mesh to match the specified declaration:
  if FAILED(pMesh.CloneMesh(pMesh.GetOptions, @vertexDecl, pd3dDevice, pTempMesh)) then
  begin
    SAFE_RELEASE(pTempMesh);
    Result:= E_FAIL;
    Exit;
  end;

  //====================================================================//
  // Check if the old declaration contains normals, tangents, binormals //
  //====================================================================//
  bHadNormal   := False;
  bHadTangent  := False;
  bHadBinormal := False;

  if Assigned(pMesh) and SUCCEEDED(pMesh.GetDeclaration(vertexOldDecl)) then
  begin
    // Go through the declaration and look for the right channels, hoping for a match:
    for iChannelIndex := 0 to D3DXGetDeclLength(@vertexOldDecl) - 1 do
    begin
      if (vertexOldDecl[iChannelIndex].Usage = D3DDECLUSAGE_NORMAL)
      then bHadNormal := True;

      if (vertexOldDecl[iChannelIndex].Usage = D3DDECLUSAGE_TANGENT)
      then bHadTangent := True;

      if (vertexOldDecl[iChannelIndex].Usage = D3DDECLUSAGE_BINORMAL)
      then bHadBinormal := True;
    end;
  end;

  if (pTempMesh = nil) and not (bHadNormal and bHadTangent and bHadBinormal) then
  begin
    // We failed to clone the mesh and we need the tangent space for our effect:
    Result:= E_FAIL;
    Exit;
  end;

  //==============================================================//
  // Generate normals / tangents / binormals if they were missing //
  //==============================================================//
  SAFE_RELEASE(pMesh);
  pMesh := pTempMesh;

  if not bHadNormal then
  begin
    // Compute normals in case the meshes have them
    D3DXComputeNormals(pMesh, nil);
  end;

  GetMem(rgdwAdjacency, SizeOf(DWORD)*pMesh.GetNumFaces*3);
  try
    // if (rgdwAdjacency = nil) then Result:= E_OUTOFMEMORY;
    V(pMesh.GenerateAdjacency(1e-6, rgdwAdjacency));
    // Optimize the mesh for this graphics card's vertex cache
    // so when rendering the mesh's triangle list the vertices will
    // cache hit more often so it won't have to re-execute the vertex shader
    // on those vertices so it will improve perf.
    V(pMesh.OptimizeInplace(D3DXMESHOPT_VERTEXCACHE, rgdwAdjacency, nil, nil, nil));

    if not bHadTangent and not bHadBinormal then
    begin
      // Compute tangents, which are required for normal mapping
      if FAILED(D3DXComputeTangentFrameEx(pMesh, DWORD(D3DDECLUSAGE_TEXCOORD), 0, DWORD(D3DDECLUSAGE_TANGENT), 0, DWORD(D3DDECLUSAGE_BINORMAL), 0,
                                          DWORD(D3DDECLUSAGE_NORMAL), 0, 0, rgdwAdjacency, -1.01,
                                          -0.01, -1.01, pNewMesh, nil)) then
      begin
        Result:= E_FAIL;
        Exit;
      end;

      SAFE_RELEASE(pMesh);
      pMesh := pNewMesh;
    end;

  finally
    FreeMem(rgdwAdjacency);
  end;

  ppMesh := pMesh;

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// Create any D3D9 resources that won't live through a device reset (D3DPOOL_DEFAULT)
// or that are tied to the back buffer size
//--------------------------------------------------------------------------------------
function OnResetDevice(const pd3dDevice: IDirect3DDevice9; const pBackBufferSurfaceDesc: TD3DSurfaceDesc; pUserContext: Pointer): HRESULT; stdcall;
const ciHUDLeftBorderOffset = 170;
const ciHUDVerticalSize     = 170;
const ciUILeftBorderOffset  = 0;
const ciUITopBorderOffset   = 40;
const ciUIVerticalSize      = 600;
const ciUIHorizontalSize    = 300;
var
  fAspectRatio: Single;
begin
  Result:= g_DialogResourceManager.OnResetDevice;
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnResetDevice;
  if V_Failed(Result) then Exit;

  if Assigned(g_pFont) then
  begin
    Result:= g_pFont.OnResetDevice;
    if V_Failed(Result) then Exit;
  end;
  if Assigned(g_pEffect) then
  begin
    Result:= g_pEffect.OnResetDevice;
    if V_Failed(Result) then Exit;
  end;

  // Create a sprite to help batch calls when drawing many lines of text
  Result:= D3DXCreateSprite(pd3dDevice, g_pSprite);
  if V_Failed(Result) then Exit;

  g_LightControl.OnResetDevice(pBackBufferSurfaceDesc );

  // Setup the camera's projection parameters
  fAspectRatio := pBackBufferSurfaceDesc.Width / pBackBufferSurfaceDesc.Height;
  g_Camera.SetProjParams(D3DX_PI/4, fAspectRatio, 0.1, 5000.0);
  g_Camera.SetWindow(pBackBufferSurfaceDesc.Width, pBackBufferSurfaceDesc.Height);
  g_Camera.SetButtonMasks(MOUSE_LEFT_BUTTON, MOUSE_WHEEL, MOUSE_MIDDLE_BUTTON);

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width - ciHUDLeftBorderOffset, 0);
  g_HUD.SetSize(ciHUDLeftBorderOffset, ciHUDVerticalSize);

  g_SampleUI.SetLocation(ciUILeftBorderOffset, ciUITopBorderOffset);
  g_SampleUI.SetSize(ciUIHorizontalSize, ciUIVerticalSize);

  Result:= S_OK;
end;



//--------------------------------------------------------------------------------------
// Handle updates to the scene.  This is called regardless of which D3D API is used
//--------------------------------------------------------------------------------------
procedure OnFrameMove(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
begin
  // Update the camera's position based on user input
  g_Camera.FrameMove(fElapsedTime);
end;


//--------------------------------------------------------------------------------------
// Render the scene using the D3D9 device
//--------------------------------------------------------------------------------------
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  mWorldViewProjection: TD3DXMatrixA16;
  vLightDir: TD3DXVector3;
  vLightDiffuse: TD3DXColor;
  iPass, cPasses: LongWord;

  m, mWorld, mView, mProjection: TD3DXMatrixA16;
  arrowColor: TD3DXColor;
  vWhite: TD3DXColor;

  vEye: TD3DXVector4;
  vTemp: TD3DXVector3;
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  // Clear the render target and the zbuffer
  V(pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER,
                     D3DXColorToDWord(D3DXCOLOR(0.0, 0.25, 0.25, 0.55)), 1.0, 0));

  // Render the scene
  if FAILED(pd3dDevice.BeginScene) then
  begin
    // Failed to being rendering scene, not much we can do not:
    WriteLn('BeginScene FAILED');
    Exit;
  end;

  if Assigned(g_pEffect) then
  begin
    // Get the projection & view matrix from the camera class
    D3DXMatrixMultiply(mWorld, g_mWorldFix, g_Camera.GetWorldMatrix^);
    mProjection := g_Camera.GetProjMatrix^;
    mView := g_Camera.GetViewMatrix^;

    // mWorldViewProjection = mWorld * mView * mProj;
    D3DXMatrixMultiply(m, mView, mProjection);
    D3DXMatrixMultiply(mWorldViewProjection, mWorld, m);

    // Get camera position:
    vTemp := g_Camera.GetEyePt^;
    vEye.x := vTemp.x;
    vEye.y := vTemp.y;
    vEye.z := vTemp.z;
    vEye.w := 1.0;

    // Render the light arrow so the user can visually see the light dir
    arrowColor := D3DXColor(1,1,0,1);
    V(g_LightControl.OnRender(arrowColor, mView, mProjection, g_Camera.GetEyePt^));
    vLightDir     := g_LightControl.LightDirection;
    D3DXColorScale(vLightDiffuse, D3DXColor(1, 1, 1, 1), g_fLightScale); // vLightDiffuse := g_fLightScale * D3DXColor(1, 1, 1, 1);

    V(g_pEffect.SetValue('g_LightDir',     @vLightDir,     SizeOf(TD3DXVECTOR3)));
    V(g_pEffect.SetValue('g_LightDiffuse', @vLightDiffuse, SizeOf(TD3DXVECTOR4)));

    // Update the effect's variables.  Instead of using strings, it would
    // be more efficient to cache a handle to the parameter by calling
    // ID3DXEffect::GetParameterByName
    V(g_pEffect.SetMatrix('g_mWorldViewProjection', mWorldViewProjection));
    V(g_pEffect.SetMatrix('g_mWorld',               mWorld));
    V(g_pEffect.SetMatrix('g_mView',                mView));
    V(g_pEffect.SetVector('g_vEye',                 vEye));
    V(g_pEffect.SetValue ('g_fHeightMapScale',      @g_fHeightScale, SizeOf(Single)));

    vWhite := D3DXColor(1,1,1,1);
    V(g_pEffect.SetValue('g_materialDiffuseColor', @vWhite, SizeOf(TD3DXCOLOR)));

    V(g_pEffect.SetValue('g_materialAmbientColor',  @g_colorMtrlAmbient,  SizeOf(TD3DXCOLOR)));
    V(g_pEffect.SetValue('g_materialDiffuseColor',  @g_colorMtrlDiffuse,  SizeOf(TD3DXCOLOR)));
    V(g_pEffect.SetValue('g_materialSpecularColor', @g_colorMtrlSpecular, SizeOf(TD3DXCOLOR)));


    V(g_pEffect.SetValue('g_fSpecularExponent',  @g_fSpecularExponent,  SizeOf(Single)));
    V(g_pEffect.SetValue('g_fBaseTextureRepeat', @g_fBaseTextureRepeat, SizeOf(Single)));
    V(g_pEffect.SetValue('g_nLODThreshold',      @g_nLODThreshold,      SizeOf(Integer)));
    V(g_pEffect.SetValue('g_nMinSamples',        @g_nMinSamples,        SizeOf(Integer)));
    V(g_pEffect.SetValue('g_nMaxSamples',        @g_nMaxSamples,        SizeOf(Integer)));
    V(g_pEffect.SetValue('g_fShadowSoftening',   @g_fShadowSoftening,   SizeOf(Single)));

    V(g_pEffect.SetBool('g_bVisualizeLOD',      g_bVisualizeLOD));
    V(g_pEffect.SetBool('g_bVisualizeMipLevel', g_bVisualizeMipLevel));
    V(g_pEffect.SetBool('g_bDisplayShadows',    g_bDisplayShadows));
    V(g_pEffect.SetBool('g_bAddSpecular',       g_bAddSpecular));

    // Render the scene:
    case g_nCurrentTechniqueID of
      tidPOM:     V(g_pEffect.SetTechnique('RenderSceneWithPOM'));
      tidBumpmap: V(g_pEffect.SetTechnique('RenderSceneWithBumpMap'));
      tidPM:      V(g_pEffect.SetTechnique('RenderSceneWithPM'));
    end;

    V(g_pEffect._Begin(@cPasses, 0));
    for iPass := 0 to cPasses - 1 do
    begin
      V(g_pEffect.BeginPass(iPass));
      V(g_pMesh.DrawSubset(0));
      V(g_pEffect.EndPass);
    end;
    V( g_pEffect._End);
  end;

  g_HUD.OnRender(fElapsedTime);
  g_SampleUI.OnRender(fElapsedTime);

  RenderText(fTime);

  V(pd3dDevice.EndScene);
end;


//--------------------------------------------------------------------------------------
// Render the help and statistics text. This function uses the ID3DXFont 
// interface for efficient text rendering.
//--------------------------------------------------------------------------------------
procedure RenderText(fTime: Double);
var
  txtHelper: CDXUTTextHelper;
  pd3dsdBackBuffer: PD3DSurfaceDesc;
begin
  // The helper object simply helps keep track of text position, and color
  // and then it calls pFont->DrawText( m_pSprite, strMsg, -1, &rc, DT_NOCLIP, m_clr );
  // If NULL is passed in as the sprite object, then it will work fine however the 
  // pFont->DrawText() will not be batched together.  Batching calls will improves perf.
  txtHelper:= CDXUTTextHelper.Create(g_pFont, g_pSprite, 15);
  try
    // Output statistics
    txtHelper._Begin;
    txtHelper.SetInsertionPos(2, 0);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));
    txtHelper.DrawTextLine(DXUTGetFrameStats(True));
    txtHelper.DrawTextLine(DXUTGetDeviceStats);

    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));

    // Draw help
    if g_bShowHelp then
    begin
      pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
      txtHelper.SetInsertionPos(2, pd3dsdBackBuffer.Height-15*6);
      txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
      txtHelper.DrawTextLine('Controls:');

      txtHelper.SetInsertionPos(20, pd3dsdBackBuffer.Height-15*5);
      txtHelper.DrawTextLine('Rotate model: Left mouse button'#10+
                             'Rotate light: Right mouse button'#10+
                             'Rotate camera: Middle mouse button'#10+
                             'Zoom camera: Mouse wheel scroll'#10);

      txtHelper.SetInsertionPos(250, pd3dsdBackBuffer.Height-15*5);
      txtHelper.DrawTextLine('Hide help: F1'#10+
                             'Quit: ESC'#10);
    end else
    begin
      txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
      txtHelper.DrawTextLine('Press F1 for help');
    end;
    txtHelper._End;
  finally
    txtHelper.Free;
  end;
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

  // Give the dialogs a chance to handle the message first
  pbNoFurtherProcessing := g_HUD.MsgProc(hWnd, uMsg, wParam, lParam);
  if pbNoFurtherProcessing then Exit;
  pbNoFurtherProcessing := g_SampleUI.MsgProc(hWnd, uMsg, wParam, lParam);
  if pbNoFurtherProcessing then Exit;

  // Pass the message to be handled to the light control:
  g_LightControl.HandleMessages( hWnd, uMsg, wParam, lParam );

  // Pass all remaining windows messages to camera so it can respond to user input
  g_Camera.HandleMessages(hWnd, uMsg, wParam, lParam);
end;


//--------------------------------------------------------------------------------------
// Handle key presses
//--------------------------------------------------------------------------------------
procedure KeyboardProc(nChar: LongWord; bKeyDown, bAltDown: Boolean; pUserContext: Pointer); stdcall;
begin
  if bKeyDown then
  begin
    case nChar of
      VK_F1: g_bShowHelp := not g_bShowHelp;
    end;
  end;
end;


//--------------------------------------------------------------------------------------
// Switches to a specified pair of the POM texture pair from user input
//--------------------------------------------------------------------------------------
procedure casePOMTextures(const pSelectedItem: PDXUTComboBoxItem);
var
  strLabel: array[0..s_iMAX_STRING_SIZE-1] of WideChar;
  pHeightRangeSlider: CDXUTSlider;
  pHeightRangeStatic: CDXUTStatic;
  pSpecularSlider: CDXUTSlider;
  pSpecularStatic: CDXUTStatic;
  pMinSlider: CDXUTSlider;
  pMinStatic: CDXUTStatic;
  pMaxSlider: CDXUTSlider;
  pMaxStatic: CDXUTStatic;
begin
  SetPOMTextures(TPOM_TextureIDs(pSelectedItem.pData));

  // Update the appropriate slider controls' bounds and values:
  pHeightRangeSlider := g_SampleUI.GetSlider(IDC_HEIGHT_SCALE_SLIDER);
  if Assigned(pHeightRangeSlider) then
  begin
    pHeightRangeSlider.SetRange(g_iHeightScaleSliderMin, g_iHeightScaleSliderMax);
    pHeightRangeSlider.Value := Trunc(g_fHeightScale * g_fHeightScaleUIScale);
  end;

  // Update the static parameter value:
  pHeightRangeStatic := g_SampleUI.GetStatic(IDC_HEIGHT_SCALE_STATIC);
  if Assigned(pHeightRangeStatic) then
  begin
    // StringCchFormat(strLabel, s_iMAX_STRING_SIZE, 'Height scale: %0.2f', [g_fHeightScale]);
    StringCchFormat(strLabel, s_iMAX_STRING_SIZE, 'Height scale: %f', [g_fHeightScale]);
    pHeightRangeStatic.Text := strLabel;
  end;

  // Update the appropriate slider controls' bounds and values:
  pSpecularSlider := g_SampleUI.GetSlider(IDC_SPECULAR_EXPONENT_SLIDER);
  if Assigned(pSpecularSlider) then
  begin
    pSpecularSlider.Value := Trunc(g_fSpecularExponent);
  end;

  pSpecularStatic := g_SampleUI.GetStatic(IDC_SPECULAR_EXPONENT_STATIC);
  if Assigned(pSpecularStatic) then
  begin
    StringCchFormat(strLabel, s_iMAX_STRING_SIZE, 'Specular exponent: %f', [g_fSpecularExponent]);
    pSpecularStatic.Text := strLabel;
  end;

  // Mininum number of samples slider
  pMinSlider := g_SampleUI.GetSlider( IDC_MIN_NUM_SAMPLES_SLIDER);
  if Assigned(pMinSlider) then
  begin
     pMinSlider.Value := g_nMinSamples;
  end;

  pMinStatic := g_SampleUI.GetStatic(IDC_MIN_NUM_SAMPLES_STATIC);
  if Assigned(pMinStatic) then
  begin
    StringCchFormat(strLabel, s_iMAX_STRING_SIZE, 'Minium number of samples: %d', [g_nMinSamples]);
    pMinStatic.Text := strLabel;
  end;

  // Maximum number of samples slider
  pMaxSlider := g_SampleUI.GetSlider(IDC_MAX_NUM_SAMPLES_SLIDER);
  if Assigned(pMaxSlider) then
  begin
    pMaxSlider.Value := g_nMaxSamples;
  end;

  pMaxStatic := g_SampleUI.GetStatic(IDC_MAX_NUM_SAMPLES_STATIC);
  if Assigned(pMaxStatic) then
  begin
    StringCchFormat(strLabel, s_iMAX_STRING_SIZE, 'Maximum number of samples: %d', [g_nMaxSamples]);
    pMaxStatic.Text := strLabel;
  end;
end;


//--------------------------------------------------------------------------------------
// Handles the GUI events
//--------------------------------------------------------------------------------------
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
var
  sz: array[0..s_iMAX_STRING_SIZE-1] of WideChar;
  pSelectedItem: PDXUTComboBoxItem;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;

    IDC_SPECULAR_EXPONENT_SLIDER:
    begin
      g_fSpecularExponent := g_SampleUI.GetSlider(IDC_SPECULAR_EXPONENT_SLIDER).Value;
      StringCchFormat(sz, s_iMAX_STRING_SIZE, 'Specular exponent: %f', [g_fSpecularExponent]);
      g_SampleUI.GetStatic(IDC_SPECULAR_EXPONENT_STATIC).Text := sz;
    end;

    IDC_HEIGHT_SCALE_SLIDER:
    begin
      g_fHeightScale := g_SampleUI.GetSlider(IDC_HEIGHT_SCALE_SLIDER).Value / g_fHeightScaleUIScale;
      StringCchFormat(sz, s_iMAX_STRING_SIZE, 'Height scale: %f', [g_fHeightScale]);
      g_SampleUI.GetStatic(IDC_HEIGHT_SCALE_STATIC).Text := sz;
    end;

    IDC_MIN_NUM_SAMPLES_SLIDER:
    begin
      g_nMinSamples := g_SampleUI.GetSlider(IDC_MIN_NUM_SAMPLES_SLIDER).Value;
      StringCchFormat(sz, s_iMAX_STRING_SIZE, 'Minimum number of samples: %d', [g_nMinSamples]);
      g_SampleUI.GetStatic(IDC_MIN_NUM_SAMPLES_STATIC).Text := sz;
    end;

    IDC_MAX_NUM_SAMPLES_SLIDER:
    begin
      g_nMaxSamples := g_SampleUI.GetSlider(IDC_MAX_NUM_SAMPLES_SLIDER).Value;
      StringCchFormat(sz, s_iMAX_STRING_SIZE, 'Maximum number of samples: %d', [g_nMaxSamples]);
      g_SampleUI.GetStatic(IDC_MAX_NUM_SAMPLES_STATIC).Text := sz;
    end;

    IDC_TOGGLE_SHADOWS:
    begin
      // Toggle shadows static button:
      g_bDisplayShadows := CDXUTCheckBox(pControl).Checked;

      if g_bDisplayShadows
      then g_SampleUI.GetCheckBox(IDC_TOGGLE_SHADOWS).Text := 'Toggle self-occlusion shadows rendering: ON '
      else g_SampleUI.GetCheckBox(IDC_TOGGLE_SHADOWS).Text := 'Toggle self-occlusion shadows rendering: OFF ';
    end;

    IDC_TECHNIQUE_COMBO_BOX:
    begin
      pSelectedItem := CDXUTComboBox(pControl).GetSelectedItem;
      if (pSelectedItem <> nil) then
        g_nCurrentTechniqueID := TTechniqueIDs(pSelectedItem.pData);
    end;

    IDC_TOGGLE_SPECULAR:
    begin
      // Toggle specular static button:
      g_bAddSpecular := CDXUTCheckBox(pControl).Checked;

      if g_bAddSpecular
      then g_SampleUI.GetCheckBox(IDC_TOGGLE_SPECULAR).Text := 'Toggle specular: ON'
      else g_SampleUI.GetCheckBox(IDC_TOGGLE_SPECULAR).Text := 'Toggle specular: OFF';
    end;

    IDC_SELECT_TEXTURES_COMBOBOX:
    begin
      pSelectedItem := CDXUTComboBox(pControl).GetSelectedItem;
      if (pSelectedItem <> nil) then
        casePOMTextures(pSelectedItem);
    end;

    IDC_RELOAD_BUTTON:
    begin
      V(LoadEffectFile);
    end;
  end;
end;


//--------------------------------------------------------------------------------------
// Release D3D9 resources created in the OnD3D9ResetDevice callback
//--------------------------------------------------------------------------------------
procedure OnLostDevice; stdcall;
begin
  g_DialogResourceManager.OnLostDevice;
  g_SettingsDlg.OnLostDevice;
  CDXUTDirectionWidget.StaticOnLostDevice;

  if Assigned(g_pFont) then g_pFont.OnLostDevice;
  if Assigned(g_pEffect) then g_pEffect.OnLostDevice;
  SAFE_RELEASE(g_pSprite);
end;


//--------------------------------------------------------------------------------------
// Release D3D9 resources created in the OnD3D9CreateDevice callback
//--------------------------------------------------------------------------------------
procedure OnDestroyDevice; stdcall;
var
  iTextureIndex: TPOM_TextureIDs;
begin
  g_DialogResourceManager.OnDestroyDevice;
  g_SettingsDlg.OnDestroyDevice;
  CDXUTDirectionWidget.StaticOnDestroyDevice;
  SAFE_RELEASE(g_pEffect);
  SAFE_RELEASE(g_pFont);
  SAFE_RELEASE(g_pMesh);

  for iTextureIndex := Low(iTextureIndex) to High(iTextureIndex) do
  begin
    SAFE_RELEASE(g_pBaseTextures[iTextureIndex]);
    SAFE_RELEASE(g_pNMHTextures[iTextureIndex]);
  end;

  Dispose(g_pBaseTextures);
  Dispose(g_pNMHTextures);
  
  g_pD3DDevice := nil;
end;


procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_LightControl:= CDXUTDirectionWidget.Create; // Scene light
  g_Camera:= CModelViewerCamera.Create; // A model viewing camera
  g_HUD:= CDXUTDialog.Create; // manages the 3D UI
  g_SampleUI:= CDXUTDialog.Create; // dialog for sample specific controls
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_LightControl);
  FreeAndNil(g_Camera);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);
end;

end.

