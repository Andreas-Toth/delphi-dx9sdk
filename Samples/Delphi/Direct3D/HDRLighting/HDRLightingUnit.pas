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
 *  $Id: HDRLightingUnit.pas,v 1.15 2007/02/05 22:21:08 clootie Exp $
 *----------------------------------------------------------------------------*)
//-----------------------------------------------------------------------------
// File: HDRLighting.cpp
//
// Desc: This sample demonstrates some high dynamic range lighting effects
//       using floating point textures.
//
// The algorithms described in this sample are based very closely on the
// lighting effects implemented in Masaki Kawase's Rthdribl sample and the tone
// mapping process described in the whitepaper "Tone Reproduction for Digital
// Images"
//
// Real-Time High Dynamic Range Image-Based Lighting (Rthdribl)
// Masaki Kawase
// http://www.daionet.gr.jp/~masa/rthdribl/
//
// "Photographic Tone Reproduction for Digital Images"
// Erik Reinhard, Mike Stark, Peter Shirley and Jim Ferwerda
// http://www.cs.utah.edu/~reinhard/cdrom/
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//-----------------------------------------------------------------------------

{$I DirectX.inc}

unit HDRLightingUnit;

interface

uses
  Windows, DXTypes, Direct3D9, D3DX9,
  DXUT, DXUTcore, DXUTmisc, DXUTenum, DXUTgui, DXUTSettingsDlg,
  SysUtils, Math, StrSafe, GlareDefD3D;

{.$DEFINE DEBUG_VS}   // Uncomment this line to debug vertex shaders
{.$DEFINE DEBUG_PS}   // Uncomment this line to debug pixel shaders


const
  MAX_SAMPLES           = 16;      // Maximum number of texture grabs

  NUM_LIGHTS            = 2;       // Number of lights in the scene

  EMISSIVE_COEFFICIENT  = 39.78;   // Emissive color multiplier for each lumen
                                   // of light intensity
  NUM_TONEMAP_TEXTURES  = 4;       // Number of stages in the 4x4 down-scaling
                                   // of average luminance textures
  NUM_STAR_TEXTURES     = 12;      // Number of textures used for the star
                                   // post-processing effect
  NUM_BLOOM_TEXTURES    = 3;       // Number of textures used for the bloom
                                   // post-processing effect

type
  // Texture coordinate rectangle
  PCoordRect = ^TCoordRect;
  TCoordRect = record
    fLeftU, fTopV: Single;
    fRightU, fBottomV: Single;
  end;


  // World vertex format
  PWorldVertex = ^TWorldVertex;
  TWorldVertex = packed record
    p: TD3DXVector3; // position
    n: TD3DXVector3; // normal
    t: TD3DXVector2; // texture coordinate
    // static const DWORD FVF;
  end;

const
  TWorldVertex_FVF = D3DFVF_XYZ or D3DFVF_NORMAL or D3DFVF_TEX1;


type
  // Screen quad vertex format
  PScreenVertex = ^TScreenVertex;
  TScreenVertex = packed record
    p: TD3DXVector4; // position
    t: TD3DXVector2; // texture coordinate
    // static const DWORD FVF;
  end;

const
  TScreenVertex_FVF = D3DFVF_XYZRHW or D3DFVF_TEX1;


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
var
  g_pd3dDevice: IDirect3DDevice9;                // D3D Device object
  g_pFont: ID3DXFont;                            // Font for drawing text
  g_pTextSprite: ID3DXSprite;                    // Sprite for batching draw text calls
  g_pEffect: ID3DXEffect;                        // D3DX effect interface
  g_Camera: CFirstPersonCamera;                  // A model viewing camera
  g_LuminanceFormat: TD3DFormat;                 // Format to use for luminance map
  g_bShowHelp: Boolean = True;                   // If true, it renders the UI control text
  g_DialogResourceManager: CDXUTDialogResourceManager; // manager for shared resources of dialogs
  g_SettingsDlg: CD3DSettingsDlg;                // Device settings dialog
  g_HUD: CDXUTDialog;                            // dialog for standard controls
  g_SampleUI: CDXUTDialog;                       // dialog for sample specific controls

  g_pFloatMSRT: IDirect3DSurface9;               // Multi-Sample float render target
  g_pFloatMSDS: IDirect3DSurface9;               // Depth Stencil surface for the float RT
  g_pTexScene: IDirect3DTexture9;                // HDR render target containing the scene
  g_pTexSceneScaled: IDirect3DTexture9;          // Scaled copy of the HDR scene
  g_pTexBrightPass: IDirect3DTexture9;           // Bright-pass filtered copy of the scene
  g_pTexAdaptedLuminanceCur: IDirect3DTexture9;  // The luminance that the user is currenly adapted to
  g_pTexAdaptedLuminanceLast: IDirect3DTexture9; // The luminance that the user is currenly adapted to
  g_pTexStarSource: IDirect3DTexture9;           // Star effect source texture
  g_pTexBloomSource: IDirect3DTexture9;          // Bloom effect source texture

  g_pTexWall: IDirect3DTexture9;      // Stone texture for the room walls
  g_pTexFloor: IDirect3DTexture9;     // Concrete texture for the room floor
  g_pTexCeiling: IDirect3DTexture9;   // Plaster texture for the room ceiling
  g_pTexPainting: IDirect3DTexture9;  // Texture for the paintings on the wall


  g_apTexBloom: array[0..NUM_BLOOM_TEXTURES-1] of IDirect3DTexture9;      // Blooming effect working textures
  g_apTexStar: array[0..NUM_STAR_TEXTURES-1] of IDirect3DTexture9;        // Star effect working textures
  g_apTexToneMap: array[0..NUM_TONEMAP_TEXTURES-1] of IDirect3DTexture9;  // Log average luminance samples
                                                                          // from the HDR render target

  g_pWorldMesh: ID3DXMesh;        // Mesh to contain world objects
  g_pmeshSphere: ID3DXMesh;       // Representation of point light

  g_GlareDef: CGlareDef;          // Glare defintion
  g_eGlareType: TEGlareLibType;   // Enumerated glare type

  g_avLightPosition: array[0..NUM_LIGHTS-1] of TD3DXVector4;  // Light positions in world space
  g_avLightIntensity: array[0..NUM_LIGHTS-1] of TD3DXVector4; // Light floating point intensities
  g_nLightLogIntensity: array[0..NUM_LIGHTS-1] of Integer;    // Light intensities on a log scale
  g_nLightMantissa: array[0..NUM_LIGHTS-1] of Integer;        // Mantissa of the light intensity

  g_dwCropWidth: DWORD;     // Width of the cropped scene texture
  g_dwCropHeight: DWORD;    // Height of the cropped scene texture

  g_fKeyValue: Single;      // Middle gray key value for tone mapping

  g_bToneMap: Boolean;                // True when scene is to be tone mapped
  g_bDetailedStats: Boolean;          // True when state variables should be rendered
  g_bDrawHelp: Boolean;               // True when help instructions are to be drawn
  g_bBlueShift: Boolean;              // True when blue shift is to be factored in
  g_bAdaptationInvalid: Boolean;      // True when adaptation level needs refreshing
  g_bUseMultiSampleFloat16: Boolean = False;  // True when using multisampling on a floating point back buffer
  g_MaxMultiSampleType: TD3DMultiSampleType = D3DMULTISAMPLE_NONE;   // Non-Zero when g_bUseMultiSampleFloat16 is true
  g_dwMultiSampleQuality: DWORD = 0;  // Non-Zero when we have multisampling on a float backbuffer
  g_bSupportsD16: bool = False;
  g_bSupportsD32: bool = False;
  g_bSupportsD24X8: bool = False;


//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
const
  IDC_STATIC              = -1;
  IDC_TOGGLEFULLSCREEN    = 1;
  IDC_TOGGLEREF           = 3;
  IDC_CHANGEDEVICE        = 4;
  IDC_GLARETYPE           = 5;
  IDC_LIGHT0_LABEL        = 6;
  IDC_LIGHT1_LABEL        = 7;
  IDC_LIGHT0              = 8;
  IDC_LIGHT1              = 9;
  IDC_KEYVALUE            = 10;
  IDC_KEYVALUE_LABEL      = 11;
  IDC_TONEMAP             = 12;
  IDC_BLUESHIFT           = 13;
  IDC_RESET               = 14;


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
procedure RenderText;

// Scene geometry initialization routines
procedure SetTextureCoords(pVertex: PWorldVertex; u, v: Single);
function BuildWorldMesh: HRESULT;
function BuildColumn(var pV: PWorldVertex; x, y, z: Single; width: Single): HRESULT;


// Post-processing source textures creation
function Scene_To_SceneScaled: HRESULT;
function SceneScaled_To_BrightPass: HRESULT;
function BrightPass_To_StarSource: HRESULT;
function StarSource_To_BloomSource: HRESULT;


// Post-processing helper functions
function GetTextureRect(const pTexture: IDirect3DTexture9; out pRect: TRect): HRESULT;
function GetTextureCoords(const pTexSrc: IDirect3DTexture9; pRectSrc: PRect; pTexDest: IDirect3DTexture9; pRectDest: PRect; var pCoords: TCoordRect): HRESULT;


// Sample offset calculation. These offsets are passed to corresponding
// pixel shaders.
function GetSampleOffsets_GaussBlur5x5(dwD3DTexWidth, dwD3DTexHeight: DWORD;
  var avTexCoordOffset: array of TD3DXVector2; var avSampleWeight: array of TD3DXVector4;
  fMultiplier: Single = 1.0): HRESULT;
function GetSampleOffsets_Bloom(dwD3DTexSize: DWORD;
  var afTexCoordOffset: array of Single; var avColorWeight: array of TD3DXVector4;
  fDeviation: Single; fMultiplier: Single = 1.0): HRESULT;
function GetSampleOffsets_Star(dwD3DTexSize: DWORD;
  var afTexCoordOffset: array {[15]} of Single; var avColorWeight: array of TD3DXVector4;
  fDeviation: Single): HRESULT;
function GetSampleOffsets_DownScale4x4(dwWidth, dwHeight: DWORD; var avSampleOffsets: array of TD3DXVector2): HRESULT;
function GetSampleOffsets_DownScale2x2(dwWidth, dwHeight: DWORD; var avSampleOffsets: array of TD3DXVector2): HRESULT;


// Tone mapping and post-process lighting effects
function MeasureLuminance: HRESULT;
function CalculateAdaptation: HRESULT;
function RenderStar: HRESULT;
function RenderBloom: HRESULT;


// Methods to control scene lights
function AdjustLight(iLight: LongWord; bIncrement: Boolean): HRESULT;
function RefreshLights: HRESULT;

function RenderScene: HRESULT;
function ClearTexture(pTexture: IDirect3DTexture9): HRESULT;

procedure ResetOptions;
procedure DrawFullScreenQuad(fLeftU, fTopV, fRightU, fBottomV: Single); overload;
procedure DrawFullScreenQuad(const c: TCoordRect); overload; { DrawFullScreenQuad( c.fLeftU, c.fTopV, c.fRightU, c.fBottomV ); }

procedure CreateCustomDXUTobjects;
procedure DestroyCustomDXUTobjects;



implementation



function GaussianDistribution(x, y, rho: Single): Single; forward;{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}

//--------------------------------------------------------------------------------------
// Initialize the app
//--------------------------------------------------------------------------------------
procedure InitApp;
var
  iY: Integer;
  pElement: CDXUTElement;
  pComboBox: CDXUTComboBox;
begin
  // Although multisampling is supported for render target surfaces, those surfaces
  // exist without a parent texture, and must therefore be copied to a texture
  // surface if they're to be used as a source texture. This sample relies upon
  // several render targets being used as source textures, and therefore it makes
  // sense to disable multisampling altogether.
{  CGrowableArray<D3DMULTISAMPLE_TYPE>* pMultiSampleTypeList = DXUTGetEnumeration()->GetPossibleMultisampleTypeList();
  pMultiSampleTypeList->RemoveAll();
  pMultiSampleTypeList->Add( D3DMULTISAMPLE_NONE );
  DXUTGetEnumeration()->SetMultisampleQualityMax( 0 ); }


  // Initialize dialogs
  g_SettingsDlg.Init(g_DialogResourceManager);
  g_HUD.Init(g_DialogResourceManager);
  g_SampleUI.Init(g_DialogResourceManager);

  g_HUD.SetCallback(OnGUIEvent);
  iY := 10;    g_HUD.AddButton(IDC_TOGGLEFULLSCREEN, 'Toggle full screen', 35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_TOGGLEREF, 'Toggle REF (F3)',           35, iY, 125, 22);
  Inc(iY, 24); g_HUD.AddButton(IDC_CHANGEDEVICE, 'Change device (F2)',     35, iY, 125, 22, VK_F2);
  Inc(iY, 24); g_HUD.AddButton(IDC_RESET, 'Reset Options (R)',             35, iY, 125, 22, Ord('R'));

  // Title font for comboboxes
  g_SampleUI.SetFont(1, 'Arial', 14, FW_BOLD);
  pElement := g_SampleUI.GetDefaultElement(DXUT_CONTROL_STATIC, 0);
  if Assigned(pElement) then
  begin
    pElement.iFont := 1;
    pElement.dwTextFormat := DT_LEFT or DT_BOTTOM;
  end;

  pComboBox := nil;
  g_SampleUI.SetCallback(OnGUIEvent); iY := 10;
  Inc(iY, 24); g_SampleUI.AddStatic(IDC_STATIC, '(G)lare Type', 35, iY, 125, 22);
  Inc(iY, 24); g_SampleUI.AddComboBox(IDC_GLARETYPE, 35, iY, 125, 22, Ord('G'), False, @pComboBox);
  Inc(iY, 24); g_SampleUI.AddStatic(IDC_LIGHT0_LABEL, 'Light 0', 35, iY, 125, 22);
  Inc(iY, 24); g_SampleUI.AddSlider(IDC_LIGHT0, 35, iY, 100, 22, 0, 63);
  Inc(iY, 24); g_SampleUI.AddStatic(IDC_LIGHT1_LABEL, 'Light 1', 35, iY, 125, 22);
  Inc(iY, 24); g_SampleUI.AddSlider(IDC_LIGHT1, 35, iY, 100, 22, 0, 63);
  Inc(iY, 24); g_SampleUI.AddStatic(IDC_KEYVALUE_LABEL, 'Key Value', 35, iY, 125, 22);
  Inc(iY, 24); g_SampleUI.AddSlider(IDC_KEYVALUE, 35, iY, 100, 22, 0, 100);
  Inc(iY, 34); g_SampleUI.AddCheckBox(IDC_TONEMAP, '(T)one Mapping', 35, iY, 125, 20, True, Ord('T'));
  Inc(iY, 24); g_SampleUI.AddCheckBox(IDC_BLUESHIFT, '(B)lue Shift', 35, iY, 125, 20, True, Ord('B'));

  if Assigned(pComboBox) then
  begin
    pComboBox.AddItem('Disable', Pointer(GLT_DISABLE));
    pComboBox.AddItem('Camera', Pointer(GLT_CAMERA));
    pComboBox.AddItem('Natural Bloom', Pointer(GLT_NATURAL));
    pComboBox.AddItem('Cheap Lens', Pointer(GLT_CHEAPLENS));
    pComboBox.AddItem('Cross Screen', Pointer(GLT_FILTER_CROSSSCREEN));
    pComboBox.AddItem('Spectral Cross', Pointer(GLT_FILTER_CROSSSCREEN_SPECTRAL));
    pComboBox.AddItem('Snow Cross', Pointer(GLT_FILTER_SNOWCROSS));
    pComboBox.AddItem('Spectral Snow', Pointer(GLT_FILTER_SNOWCROSS_SPECTRAL));
    pComboBox.AddItem('Sunny Cross', Pointer(GLT_FILTER_SUNNYCROSS));
    pComboBox.AddItem('Spectral Sunny', Pointer(GLT_FILTER_SUNNYCROSS_SPECTRAL));
    pComboBox.AddItem('Cinema Vertical', Pointer(GLT_CINECAM_VERTICALSLITS));
    pComboBox.AddItem('Cinema Horizontal', Pointer(GLT_CINECAM_HORIZONTALSLITS));
  end;


  (*
  g_SampleUI.AddComboBox( 19, 35, iY += 24, 125, 22 );
  g_SampleUI.GetComboBox( 19 )->AddItem( L"Text1", NULL );
  g_SampleUI.GetComboBox( 19 )->AddItem( L"Text2", NULL );
  g_SampleUI.GetComboBox( 19 )->AddItem( L"Text3", NULL );
  g_SampleUI.GetComboBox( 19 )->AddItem( L"Text4", NULL );
  g_SampleUI.AddCheckBox( 21, L"Checkbox1", 35, iY += 24, 125, 22 );
  g_SampleUI.AddCheckBox( 11, L"Checkbox2", 35, iY += 24, 125, 22 );
  g_SampleUI.AddRadioButton( 12, 1, L"Radio1G1", 35, iY += 24, 125, 22 );
  g_SampleUI.AddRadioButton( 13, 1, L"Radio2G1", 35, iY += 24, 125, 22 );
  g_SampleUI.AddRadioButton( 14, 1, L"Radio3G1", 35, iY += 24, 125, 22 );
  g_SampleUI.GetRadioButton( 14 )->SetChecked( true ); 
  g_SampleUI.AddButton( 17, L"Button1", 35, iY += 24, 125, 22 );
  g_SampleUI.AddButton( 18, L"Button2", 35, iY += 24, 125, 22 );
  g_SampleUI.AddRadioButton( 15, 2, L"Radio1G2", 35, iY += 24, 125, 22 );
  g_SampleUI.AddRadioButton( 16, 2, L"Radio2G3", 35, iY += 24, 125, 22 );
  g_SampleUI.GetRadioButton( 16 )->SetChecked( true );
  g_SampleUI.AddSlider( 20, 50, iY += 24, 100, 22 );
  g_SampleUI.GetSlider( 20 )->SetRange( 0, 100 );
  g_SampleUI.GetSlider( 20 )->SetValue( 50 );
//    g_SampleUI.AddEditBox( 20, L"Test", 35, iY += 24, 125, 22 );
  *)

  // Set light positions in world space
  g_avLightPosition[0] := D3DXVector4(4.0,  2.0,  18.0, 1.0);
  g_avLightPosition[1] := D3DXVector4(11.0, 2.0,  18.0, 1.0);

  ResetOptions;
end;


//-----------------------------------------------------------------------------
// Name: ResetOptions()
// Desc: Reset all user-controlled options to default values
//-----------------------------------------------------------------------------
procedure ResetOptions;
begin
  g_bDrawHelp         := True;
  g_bDetailedStats    := True;
    
  g_SampleUI.EnableNonUserEvents(True);

  g_SampleUI.GetCheckBox(IDC_TONEMAP).Checked := True;
  g_SampleUI.GetCheckBox(IDC_BLUESHIFT).Checked := True;
  g_SampleUI.GetSlider(IDC_LIGHT0).Value := 52;
  g_SampleUI.GetSlider(IDC_LIGHT1).Value := 43;
  g_SampleUI.GetSlider(IDC_KEYVALUE).Value := 18;
  g_SampleUI.GetComboBox(IDC_GLARETYPE).SetSelectedByData(Pointer(GLT_DEFAULT));

  g_SampleUI.EnableNonUserEvents(False);
end;


//-----------------------------------------------------------------------------
// Name: AdjustLight
// Desc: Increment or decrement the light at the given index
//-----------------------------------------------------------------------------
function AdjustLight(iLight: LongWord; bIncrement: Boolean): HRESULT;
begin
  if (iLight >= NUM_LIGHTS) then
  begin
    Result:= E_INVALIDARG;
    Exit;
  end;

  if bIncrement and (g_nLightLogIntensity[iLight] < 7) then
  begin
    Inc(g_nLightMantissa[iLight]);
    if (g_nLightMantissa[iLight] > 9) then
    begin
      g_nLightMantissa[iLight] := 1;
      Inc(g_nLightLogIntensity[iLight]);
    end;
  end;

  if not bIncrement and (g_nLightLogIntensity[iLight] > -4) then
  begin
    Dec(g_nLightMantissa[iLight]);
    if (g_nLightMantissa[iLight] < 1) then
    begin
      g_nLightMantissa[iLight] := 9;
      Dec(g_nLightLogIntensity[iLight]);
    end;
  end;

  RefreshLights;
  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: RefreshLights
// Desc: Set the light intensities to match the current log luminance
//-----------------------------------------------------------------------------
function RefreshLights: HRESULT;
var
  pStatic: CDXUTStatic;
  strBuffer: WideString;
  i: Integer;
begin
  strBuffer := '';

  for i := 0 to NUM_LIGHTS - 1 do
  begin
    g_avLightIntensity[i].x := g_nLightMantissa[i] * Power(10.0, g_nLightLogIntensity[i]);
    g_avLightIntensity[i].y := g_nLightMantissa[i] * Power(10.0, g_nLightLogIntensity[i]);
    g_avLightIntensity[i].z := g_nLightMantissa[i] * Power(10.0, g_nLightLogIntensity[i]);
    g_avLightIntensity[i].w := 1.0;

    strBuffer := WideFormat('Light %d: %d.0e%d', [i, g_nLightMantissa[i], g_nLightLogIntensity[i]]);
    pStatic := g_SampleUI.GetStatic(IDC_LIGHT0_LABEL + i);
    pStatic.Text := PWideChar(strBuffer);
  end;
    
  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// Called during device initialization, this code checks the device for some
// minimum set of capabilities, and rejects those that don't pass by returning false.
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

  if (pCaps.PixelShaderVersion < D3DPS_VERSION(2,0)) then Exit;

  // No fallback yet, so need to support D3DFMT_A16B16G16R16F render target
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                  AdapterFormat, D3DUSAGE_RENDERTARGET or D3DUSAGE_QUERY_POSTPIXELSHADER_BLENDING,
                  D3DRTYPE_TEXTURE, D3DFMT_A16B16G16R16F))
  then Exit;


  // No fallback yet, so need to support D3DFMT_R32F or D3DFMT_R16F render target
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                  AdapterFormat, D3DUSAGE_RENDERTARGET,
                  D3DRTYPE_TEXTURE, D3DFMT_R32F)) then
  begin
    if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
                    AdapterFormat, D3DUSAGE_RENDERTARGET,
                    D3DRTYPE_TEXTURE, D3DFMT_R16F))
    then Exit;
  end;

  // Need to support post-pixel processing
  if FAILED(pD3D.CheckDeviceFormat(pCaps.AdapterOrdinal, pCaps.DeviceType,
      AdapterFormat, D3DUSAGE_RENDERTARGET or D3DUSAGE_QUERY_POSTPIXELSHADER_BLENDING,
      D3DRTYPE_SURFACE, BackBufferFormat))
  then Exit;

  Result:= True;
end;


//--------------------------------------------------------------------------------------
// This callback function is called immediately before a device is created to allow the
// application to modify the device settings. The supplied pDeviceSettings parameter
// contains the settings that the framework has selected for the new device, and the
// application can make any desired changes directly to this structure.  Note however that
// DXUT will not correct invalid device settings so care must be taken 
// to return valid device settings, otherwise IDirect3D9::CreateDevice() will fail.
//--------------------------------------------------------------------------------------

{static} var s_bFirstTime: Boolean = True;

function ModifyDeviceSettings(var pDeviceSettings: TDXUTDeviceSettings; const pCaps: TD3DCaps9; pUserContext: Pointer): Boolean; stdcall;
begin
  // If device doesn't support HW T&L or doesn't support 2.0 vertex shaders in HW
  // then switch to SWVP.
  if (pCaps.DevCaps and D3DDEVCAPS_HWTRANSFORMANDLIGHT = 0) or
     (pCaps.VertexShaderVersion < D3DVS_VERSION(2,0))
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

  // For the first device created if its a REF device, optionally display a warning dialog box
  if s_bFirstTime then
  begin
    s_bFirstTime := False;
    if (pDeviceSettings.DeviceType = D3DDEVTYPE_REF) then DXUTDisplaySwitchingToREFWarning;
  end;

  Result:= True;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has been 
// created, which will happen during application initialization and windowed/full screen 
// toggles. This is the best location to create D3DPOOL_MANAGED resources since these 
// resources need to be reloaded whenever the device is destroyed. Resources created  
// here should be released in the OnDestroyDevice callback. 
//--------------------------------------------------------------------------------------
function OnCreateDevice(const pd3dDevice: IDirect3DDevice9; const pBackBufferSurfaceDesc: TD3DSurfaceDesc; pUserContext: Pointer): HRESULT; stdcall;
var
  Caps: TD3DCaps9;
  pD3D: IDirect3D9;
  DisplayMode: TD3DDisplayMode;
  dwShaderFlags: DWORD;
  str: array[0..MAX_PATH-1] of WideChar; 
  vFromPt: TD3DXVector3;
  vLookatPt: TD3DXVector3;
  vMin: TD3DXVector3;
  vMax: TD3DXVector3;
  settings: TDXUTDeviceSettings;
  imst: TD3DMultiSampleType;
  msQuality: DWORD;
begin
  Result:= g_DialogResourceManager.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnCreateDevice(pd3dDevice);
  if V_Failed(Result) then Exit;

  // Determine which of D3DFMT_R16F or D3DFMT_R32F to use for luminance texture
  pD3D := DXUTGetD3DObject;
  if not Assigned(pD3D) then
  begin
    Result:= E_FAIL;
    Exit;
  end;
  pd3dDevice.GetDeviceCaps(Caps);
  pd3dDevice.GetDisplayMode(0, DisplayMode);
  // IsDeviceAcceptable already ensured that one of D3DFMT_R16F or D3DFMT_R32F is available.
  if FAILED(pD3D.CheckDeviceFormat(Caps.AdapterOrdinal, Caps.DeviceType,
                  DisplayMode.Format, D3DUSAGE_RENDERTARGET,
                  D3DRTYPE_TEXTURE, D3DFMT_R16F))
  then g_LuminanceFormat := D3DFMT_R32F
  else g_LuminanceFormat := D3DFMT_R16F;

  // Determine whether we can support multisampling on a A16B16G16R16F render target
  g_bUseMultiSampleFloat16 := False;
  g_MaxMultiSampleType := D3DMULTISAMPLE_NONE;
  settings := DXUTGetDeviceSettings;
  for imst := D3DMULTISAMPLE_2_SAMPLES to D3DMULTISAMPLE_16_SAMPLES do
  begin
    msQuality := 0;
    if SUCCEEDED(pD3D.CheckDeviceMultiSampleType(Caps.AdapterOrdinal,
                                                 Caps.DeviceType,
                                                 D3DFMT_A16B16G16R16F,
                                                 settings.pp.Windowed,
                                                 imst, @msQuality)) then
    begin
      g_bUseMultiSampleFloat16 := True;
      g_MaxMultiSampleType := imst;
      if (msQuality > 0)
      then g_dwMultiSampleQuality := msQuality-1
      else g_dwMultiSampleQuality := msQuality;
    end;
  end;

  g_bSupportsD16 := False;
  if SUCCEEDED(pD3D.CheckDeviceFormat(settings.AdapterOrdinal, settings.DeviceType,
                                      settings.AdapterFormat, D3DUSAGE_DEPTHSTENCIL,
                                      D3DRTYPE_SURFACE, D3DFMT_D16)) then
  begin
    if SUCCEEDED(pD3D.CheckDepthStencilMatch(settings.AdapterOrdinal, settings.DeviceType,
                                             settings.AdapterFormat, D3DFMT_A16B16G16R16F,
                                             D3DFMT_D16))
    then g_bSupportsD16 := True;
  end;
  g_bSupportsD32 := False;
  if SUCCEEDED(pD3D.CheckDeviceFormat(settings.AdapterOrdinal, settings.DeviceType,
                                      settings.AdapterFormat, D3DUSAGE_DEPTHSTENCIL,
                                      D3DRTYPE_SURFACE, D3DFMT_D32)) then
  begin
    if SUCCEEDED(pD3D.CheckDepthStencilMatch(settings.AdapterOrdinal, settings.DeviceType,
                                             settings.AdapterFormat, D3DFMT_A16B16G16R16F,
                                             D3DFMT_D32))
    then g_bSupportsD32 := True;
  end;
  g_bSupportsD24X8 := False;
  if SUCCEEDED(pD3D.CheckDeviceFormat(settings.AdapterOrdinal, settings.DeviceType,
                                      settings.AdapterFormat, D3DUSAGE_DEPTHSTENCIL,
                                      D3DRTYPE_SURFACE, D3DFMT_D24X8)) then
  begin
    if SUCCEEDED(pD3D.CheckDepthStencilMatch(settings.AdapterOrdinal, settings.DeviceType,
                                             settings.AdapterFormat, D3DFMT_A16B16G16R16F,
                                             D3DFMT_D24X8))
    then g_bSupportsD24X8 := True;
  end;

  // Initialize the font
  Result:= D3DXCreateFont(pd3dDevice, 15, 0, FW_BOLD, 1, FALSE, DEFAULT_CHARSET,
                          OUT_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE,
                         'Arial', g_pFont);
  if V_Failed(Result) then Exit;

  // Define DEBUG_VS and/or DEBUG_PS to debug vertex and/or pixel shaders with the 
  // shader debugger. Debugging vertex shaders requires either REF or software vertex 
  // processing, and debugging pixel shaders requires REF.  The 
  // D3DXSHADER_FORCE_*_SOFTWARE_NOOPT flag improves the debug experience in the 
  // shader debugger.  It enables source level debugging, prevents instruction 
  // reordering, prevents dead code elimination, and forces the compiler to compile 
  // against the next higher available software target, which ensures that the 
  // unoptimized shaders do not exceed the shader model limitations.  Setting these 
  // flags will cause slower rendering since the shaders will be unoptimized and 
  // forced into software.  See the DirectX documentation for more information about 
  // using the shader debugger.
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
    dwShaderFlags := dwShaderFlags or D3DXSHADER_FORCE_PS_SOFTWARE_NOOPT;
  {$ENDIF}

  // Read the D3DX effect file
  Result:= DXUTFindDXSDKMediaFile(str, MAX_PATH, 'HDRLighting.fx');
  if V_Failed(Result) then Exit;

  // If this fails, there should be debug output as to
  // they the .fx file failed to compile
  Result:= D3DXCreateEffectFromFileW(pd3dDevice, str, nil, nil, dwShaderFlags,
                                     nil, g_pEffect, nil);
  if V_Failed(Result) then Exit;

  // Initialize the camera
  vFromPt   := D3DXVector3(7.5, 1.8, 2);
  vLookatPt := D3DXVector3(7.5, 1.5, 10.0);
  g_Camera.SetViewParams(vFromPt, vLookatPt);

  // Set options for the first-person camera
  g_Camera.SetScalers(0.01, 15.0);
  g_Camera.SetDrag(True);
  g_Camera.SetEnableYAxisMovement(False);

  vMin := D3DXVector3(1.5,0.0,1.5);
  vMax := D3DXVector3(13.5,10.0,18.5);
  g_Camera.SetClipToBoundary(True, vMin, vMax);

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
// This function loads the mesh and ensures the mesh has normals; it also optimizes the
// mesh for the graphics card's vertex cache, which improves performance by organizing
// the internal triangle list for less cache misses.
//--------------------------------------------------------------------------------------
function LoadMesh(const pd3dDevice: IDirect3DDevice9; strFileName: PWideChar; out ppMesh: ID3DXMesh): HRESULT;
var
  pMesh: ID3DXMesh;
  str: array[0..MAX_PATH-1] of WideChar;
  rgdwAdjacency: PDWORD;
  pTempMesh: ID3DXMesh;
begin
  // Load the mesh with D3DX and get back a ID3DXMesh*.  For this
  // sample we'll ignore the X file's embedded materials since we know
  // exactly the model we're loading.  See the mesh samples such as
  // "OptimizedMesh" for a more generic mesh loading example.
  Result := DXUTFindDXSDKMediaFile(str, MAX_PATH, strFileName);
  if V_Failed(Result) then Exit;
  Result := D3DXLoadMeshFromXW(str, D3DXMESH_MANAGED, pd3dDevice, nil, nil, nil, nil, pMesh);
  if V_Failed(Result) then Exit;

  // rgdwAdjacency := nil;

  // Make sure there are normals which are required for lighting
  if (pMesh.GetFVF and D3DFVF_NORMAL = 0) then
  begin
    V(pMesh.CloneMeshFVF(pMesh.GetOptions,
                          pMesh.GetFVF or D3DFVF_NORMAL,
                          pd3dDevice, pTempMesh));
    V(D3DXComputeNormals(pTempMesh, nil));

    SAFE_RELEASE(pMesh);
    pMesh := pTempMesh;
  end;

  // Optimize the mesh for this graphics card's vertex cache
  // so when rendering the mesh's triangle list the vertices will
  // cache hit more often so it won't have to re-execute the vertex shader
  // on those vertices so it will improve perf.
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


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has been 
// reset, which will happen after a lost device scenario. This is the best location to 
// create D3DPOOL_DEFAULT resources since these resources need to be reloaded whenever 
// the device is lost. Resources created here should be released in the OnLostDevice 
// callback. 
//--------------------------------------------------------------------------------------
function OnResetDevice(const pd3dDevice: IDirect3DDevice9; const pBackBufferSurfaceDesc: TD3DSurfaceDesc; pUserContext: Pointer): HRESULT; stdcall;
var
  i: Integer;
  pBackBufferDesc: PD3DSurfaceDesc;
  fAspectRatio: Single;
  iSampleLen: Integer;
  Path: array[0..MAX_PATH-1] of WideChar;
  mProjection: TD3DXMatrix;
  dfmt: TD3DFormat;
begin
  Result:= g_DialogResourceManager.OnResetDevice;
  if V_Failed(Result) then Exit;
  Result:= g_SettingsDlg.OnResetDevice;
  if V_Failed(Result) then Exit;

  g_pd3dDevice := pd3dDevice;

  if (g_pFont <> nil) then
  begin
    Result:= g_pFont.OnResetDevice;
    if V_Failed(Result) then Exit;
  end;
  if (g_pEffect <> nil) then
  begin
    Result:= g_pEffect.OnResetDevice;
    if V_Failed(Result) then Exit;
  end;

  // Create a sprite to help batch calls when drawing many lines of text
  Result:= D3DXCreateSprite(pd3dDevice, g_pTextSprite);
  if V_Failed(Result) then Exit;

  pBackBufferDesc := DXUTGetBackBufferSurfaceDesc;


  // Create the Multi-Sample floating point render target
  dfmt := D3DFMT_UNKNOWN;
  if g_bSupportsD16 then dfmt := D3DFMT_D16
  else if g_bSupportsD32 then dfmt := D3DFMT_D32
  else if g_bSupportsD24X8 then dfmt := D3DFMT_D24X8
  else g_bUseMultiSampleFloat16 := False;

  if g_bUseMultiSampleFloat16 then
  begin
    Result := g_pd3dDevice.CreateRenderTarget(pBackBufferDesc.Width, pBackBufferDesc.Height,
                                              D3DFMT_A16B16G16R16F,
                                              g_MaxMultiSampleType, g_dwMultiSampleQuality,
                                              False, g_pFloatMSRT, nil);
    if FAILED(Result) then g_bUseMultiSampleFloat16 := False
    else
    begin
      Result := g_pd3dDevice.CreateDepthStencilSurface(pBackBufferDesc.Width, pBackBufferDesc.Height,
                                                       dfmt,
                                                       g_MaxMultiSampleType, g_dwMultiSampleQuality,
                                                       True, g_pFloatMSDS, nil);
      if FAILED(Result) then
      begin
        g_bUseMultiSampleFloat16 := False;
        SAFE_RELEASE(g_pFloatMSRT);
      end;
    end;
  end;

  // Crop the scene texture so width and height are evenly divisible by 8.
  // This cropped version of the scene will be used for post processing effects,
  // and keeping everything evenly divisible allows precise control over
  // sampling points within the shaders.
  g_dwCropWidth := pBackBufferDesc.Width - pBackBufferDesc.Width mod 8;
  g_dwCropHeight := pBackBufferDesc.Height - pBackBufferDesc.Height mod 8;

  // Create the HDR scene texture
  Result := g_pd3dDevice.CreateTexture(pBackBufferDesc.Width, pBackBufferDesc.Height,
                                       1, D3DUSAGE_RENDERTARGET, D3DFMT_A16B16G16R16F,
                                       D3DPOOL_DEFAULT, g_pTexScene, nil);
  if FAILED(Result) then Exit;

  
  // Scaled version of the HDR scene texture
  Result := g_pd3dDevice.CreateTexture(g_dwCropWidth div 4, g_dwCropHeight div 4,
                                       1, D3DUSAGE_RENDERTARGET,
                                       D3DFMT_A16B16G16R16F, D3DPOOL_DEFAULT,
                                       g_pTexSceneScaled, nil);
  if FAILED(Result) then Exit;


  // Create the bright-pass filter texture.
  // Texture has a black border of single texel thickness to fake border
  // addressing using clamp addressing
  Result := g_pd3dDevice.CreateTexture(g_dwCropWidth div 4 + 2, g_dwCropHeight div 4 + 2,
                                       1, D3DUSAGE_RENDERTARGET,
                                       D3DFMT_A8R8G8B8, D3DPOOL_DEFAULT,
                                       g_pTexBrightPass, nil);
  if FAILED(Result) then Exit;


  // Create a texture to be used as the source for the star effect
  // Texture has a black border of single texel thickness to fake border
  // addressing using clamp addressing
  Result := g_pd3dDevice.CreateTexture(g_dwCropWidth div 4 + 2, g_dwCropHeight div 4 + 2,
                                       1, D3DUSAGE_RENDERTARGET,
                                       D3DFMT_A8R8G8B8, D3DPOOL_DEFAULT,
                                       g_pTexStarSource, nil);
  if FAILED(Result) then Exit;

    
  // Create a texture to be used as the source for the bloom effect
  // Texture has a black border of single texel thickness to fake border 
  // addressing using clamp addressing
  Result := g_pd3dDevice.CreateTexture(g_dwCropWidth div 8 + 2, g_dwCropHeight div 8 + 2,
                                       1, D3DUSAGE_RENDERTARGET,
                                       D3DFMT_A8R8G8B8, D3DPOOL_DEFAULT,
                                       g_pTexBloomSource, nil);
  if FAILED(Result) then Exit;




  // Create a 2 textures to hold the luminance that the user is currently adapted
  // to. This allows for a simple simulation of light adaptation.
  Result := g_pd3dDevice.CreateTexture(1, 1, 1, D3DUSAGE_RENDERTARGET,
                                       g_LuminanceFormat, D3DPOOL_DEFAULT,
                                       g_pTexAdaptedLuminanceCur, nil);
  if FAILED(Result) then Exit;
  Result := g_pd3dDevice.CreateTexture(1, 1, 1, D3DUSAGE_RENDERTARGET,
                                       g_LuminanceFormat, D3DPOOL_DEFAULT,
                                       g_pTexAdaptedLuminanceLast, nil);
  if FAILED(Result) then Exit;


  // For each scale stage, create a texture to hold the intermediate results
  // of the luminance calculation
  for i:= 0 to NUM_TONEMAP_TEXTURES - 1 do
  begin
    iSampleLen := 1 shl (2*i);

    Result := g_pd3dDevice.CreateTexture(iSampleLen, iSampleLen, 1, D3DUSAGE_RENDERTARGET,
                                         g_LuminanceFormat, D3DPOOL_DEFAULT,
                                         g_apTexToneMap[i], nil);
    if FAILED(Result) then Exit;
  end;


  // Create the temporary blooming effect textures
  // Texture has a black border of single texel thickness to fake border
  // addressing using clamp addressing
  for i := 1 to NUM_BLOOM_TEXTURES - 1 do
  begin
    Result := g_pd3dDevice.CreateTexture(g_dwCropWidth div 8 + 2, g_dwCropHeight div 8 + 2,
                                         1, D3DUSAGE_RENDERTARGET, D3DFMT_A8R8G8B8,
                                         D3DPOOL_DEFAULT, g_apTexBloom[i], nil);
    if FAILED(Result) then Exit;
  end;

  // Create the final blooming effect texture
  Result := g_pd3dDevice.CreateTexture(g_dwCropWidth div 8, g_dwCropHeight div 8,
                                       1, D3DUSAGE_RENDERTARGET, D3DFMT_A8R8G8B8,
                                       D3DPOOL_DEFAULT, g_apTexBloom[0], nil);
  if FAILED(Result) then Exit;


  // Create the star effect textures
  for i := 0 to NUM_STAR_TEXTURES-1 do
  begin
    Result := g_pd3dDevice.CreateTexture(g_dwCropWidth div 4, g_dwCropHeight div 4,
                                         1, D3DUSAGE_RENDERTARGET,
                                         D3DFMT_A16B16G16R16F, D3DPOOL_DEFAULT,
                                         g_apTexStar[i], nil);
    if FAILED(Result) then Exit;
  end;

  // Create a texture to paint the walls
  DXUTFindDXSDKMediaFile(Path, MAX_PATH, 'misc\env2.bmp');

  Result := D3DXCreateTextureFromFileW(g_pd3dDevice, Path, g_pTexWall);
  if FAILED(Result) then Exit;


  // Create a texture to paint the floor
  DXUTFindDXSDKMediaFile(Path, MAX_PATH, 'misc\ground2.bmp');

  Result := D3DXCreateTextureFromFileW(g_pd3dDevice, Path, g_pTexFloor);
  if FAILED(Result) then Exit;


  // Create a texture to paint the ceiling
  DXUTFindDXSDKMediaFile(Path, MAX_PATH, 'misc\seafloor.bmp');

  Result := D3DXCreateTextureFromFileW(g_pd3dDevice, Path, g_pTexCeiling);
  if FAILED(Result) then Exit;


  // Create a texture for the paintings
  DXUTFindDXSDKMediaFile(Path, MAX_PATH, 'misc\env3.bmp');

  Result := D3DXCreateTextureFromFileW(g_pd3dDevice, Path, g_pTexPainting);
  if FAILED(Result) then Exit;


  // Textures with borders must be cleared since scissor rect testing will
  // be used to avoid rendering on top of the border
  ClearTexture(g_pTexAdaptedLuminanceCur);
  ClearTexture(g_pTexAdaptedLuminanceLast);
  ClearTexture(g_pTexBloomSource);
  ClearTexture(g_pTexBrightPass);
  ClearTexture(g_pTexStarSource);

  for i:= 0 to NUM_BLOOM_TEXTURES - 1 do
    ClearTexture(g_apTexBloom[i]);


  // Build the world object
  Result := BuildWorldMesh;
  if FAILED(Result) then Exit;


  // Create sphere mesh to represent the light
  Result := LoadMesh(g_pd3dDevice, 'misc\sphere0.x', g_pmeshSphere);
  if FAILED(Result) then Exit;

  // Setup the camera's projection parameters
  fAspectRatio := g_dwCropWidth / g_dwCropHeight;
  g_Camera.SetProjParams(D3DX_PI/4, fAspectRatio, 0.2, 30.0);
  mProjection := g_Camera.GetProjMatrix^;

  // Set effect file variables
  g_pEffect.SetMatrix('g_mProjection', mProjection);
  g_pEffect.SetFloat('g_fBloomScale', 1.0);
  g_pEffect.SetFloat('g_fStarScale', 0.5);

  g_HUD.SetLocation(pBackBufferSurfaceDesc.Width-170, 0);
  g_HUD.SetSize(170, 170);
  g_SampleUI.SetLocation(pBackBufferSurfaceDesc.Width-170, pBackBufferSurfaceDesc.Height-350);
  g_SampleUI.SetSize(170, 300);

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: ClearTexture()
// Desc: Helper function for RestoreDeviceObjects to clear a texture surface
//-----------------------------------------------------------------------------
function ClearTexture(pTexture: IDirect3DTexture9): HRESULT;
var
  pSurface: IDirect3DSurface9;
begin
  Result := pTexture.GetSurfaceLevel(0, pSurface);
  if SUCCEEDED(Result) then
    g_pd3dDevice.ColorFill(pSurface, nil, D3DCOLOR_ARGB(0, 0, 0, 0));

  SAFE_RELEASE(pSurface);
end;


//-----------------------------------------------------------------------------
// Name: BuildWorldMesh()
// Desc: Creates the wall, floor, ceiling, columns, and painting mesh
//-----------------------------------------------------------------------------
function BuildWorldMesh: HRESULT;
const
  fWidth  = 15.0;
  fDepth  = 20.0;
  fHeight = 3.0;
var
  i: LongWord; // Loop variable
  pWorldMeshTemp: ID3DXMesh;
  pVertex: PWorldVertex;
  pV: PWorldVertex;
  pIndex: PWord;
  pAttribs: PDWORD;
begin
  // Create the room
  Result := D3DXCreateMeshFVF(48, 96, 0, TWorldVertex_FVF, g_pd3dDevice, pWorldMeshTemp);
  if FAILED(Result) then Exit;

  Result := pWorldMeshTemp.LockVertexBuffer(0, Pointer(pVertex));
  if FAILED(Result) then Exit;

  pV := pVertex;

  // Front wall
  SetTextureCoords(pV, 7.0, 2.0);
  pV.p := D3DXVector3(0.0,    fHeight, fDepth); Inc(pV);
  pV.p := D3DXVector3(fWidth, fHeight, fDepth); Inc(pV);
  pV.p := D3DXVector3(fWidth, 0.0,     fDepth); Inc(pV);
  pV.p := D3DXVector3(0.0,    0.0,     fDepth); Inc(pV);

  // Right wall
  SetTextureCoords(pV, 10.5, 2.0);
  pV.p := D3DXVector3(fWidth, fHeight, fDepth); Inc(pV);
  pV.p := D3DXVector3(fWidth, fHeight, 0.0   ); Inc(pV);
  pV.p := D3DXVector3(fWidth, 0.0,     0.0   ); Inc(pV);
  pV.p := D3DXVector3(fWidth, 0.0,     fDepth); Inc(pV);

  // Back wall
  SetTextureCoords(pV, 7.0, 2.0);
  pV.p := D3DXVector3(fWidth, fHeight, 0.0); Inc(pV);
  pV.p := D3DXVector3(0.0,    fHeight, 0.0); Inc(pV);
  pV.p := D3DXVector3(0.0,    0.0,     0.0); Inc(pV);
  pV.p := D3DXVector3(fWidth, 0.0,     0.0); Inc(pV);

  // Left wall
  SetTextureCoords(pV, 10.5, 2.0);
  pV.p := D3DXVector3(0.0, fHeight, 0.0);    Inc(pV);
  pV.p := D3DXVector3(0.0, fHeight, fDepth); Inc(pV);
  pV.p := D3DXVector3(0.0, 0.0,     fDepth); Inc(pV);
  pV.p := D3DXVector3(0.0, 0.0,     0.0);    Inc(pV);

  BuildColumn(pV, 4.0,  fHeight, 7.0, 0.75);
  BuildColumn(pV, 4.0,  fHeight, 13.0, 0.75);
  BuildColumn(pV, 11.0, fHeight, 7.0, 0.75);
  BuildColumn(pV, 11.0, fHeight, 13.0, 0.75);

  // Floor
  SetTextureCoords(pV, 7.0, 7.0);
  pV.p := D3DXVector3(0.0,    0.0, fDepth); Inc(pV);
  pV.p := D3DXVector3(fWidth, 0.0, fDepth); Inc(pV);
  pV.p := D3DXVector3(fWidth, 0.0, 0.0);    Inc(pV);
  pV.p := D3DXVector3(0.0,    0.0, 0.0);    Inc(pV);

  // Ceiling
  SetTextureCoords(pV, 7.0, 2.0);
  pV.p := D3DXVector3(0.0,    fHeight, 0.0); Inc(pV);
  pV.p := D3DXVector3(fWidth, fHeight, 0.0); Inc(pV);
  pV.p := D3DXVector3(fWidth, fHeight, fDepth); Inc(pV);
  pV.p := D3DXVector3(0.0,    fHeight, fDepth); Inc(pV);

  // Painting 1
  SetTextureCoords(pV, 1.0, 1.0);
  pV.p := D3DXVector3(2.0, fHeight - 0.5, fDepth - 0.01); Inc(pV);
  pV.p := D3DXVector3(6.0, fHeight - 0.5, fDepth - 0.01); Inc(pV);
  pV.p := D3DXVector3(6.0, fHeight - 2.5, fDepth - 0.01); Inc(pV);
  pV.p := D3DXVector3(2.0, fHeight - 2.5, fDepth - 0.01); Inc(pV);

  // Painting 2
  SetTextureCoords( pV, 1.0, 1.0);
  pV.p := D3DXVector3( 9.0, fHeight - 0.5, fDepth - 0.01); Inc(pV);
  pV.p := D3DXVector3(13.0, fHeight - 0.5, fDepth - 0.01); Inc(pV);
  pV.p := D3DXVector3(13.0, fHeight - 2.5, fDepth - 0.01); Inc(pV);
  pV.p := D3DXVector3( 9.0, fHeight - 2.5, fDepth - 0.01); // Inc(pV);

  pWorldMeshTemp.UnlockVertexBuffer;

  // Retrieve the indices
  Result := pWorldMeshTemp.LockIndexBuffer(0, Pointer(pIndex));
  if FAILED(Result) then Exit;

  for i := 0 to pWorldMeshTemp.GetNumFaces div 2 - 1 do
  begin
    pIndex^ := (i*4) + 0; Inc(pIndex);
    pIndex^ := (i*4) + 1; Inc(pIndex);
    pIndex^ := (i*4) + 2; Inc(pIndex);
    pIndex^ := (i*4) + 0; Inc(pIndex);
    pIndex^ := (i*4) + 2; Inc(pIndex);
    pIndex^ := (i*4) + 3; Inc(pIndex);
  end;

  pWorldMeshTemp.UnlockIndexBuffer;
    
  // Set attribute groups to draw floor, ceiling, walls, and paintings
  // separately, with different shader constants. These group numbers
  // will be used during the calls to DrawSubset().
  Result := pWorldMeshTemp.LockAttributeBuffer(0, pAttribs);
  if FAILED(Result) then Exit;

  for i:= 0 to 40-1 do
  begin
    pAttribs^ := 0;
    Inc(pAttribs);
  end;

  for i:= 0 to 1 do
  begin
    pAttribs^ := 1;
    Inc(pAttribs);
  end;

  for i:= 0 to 1 do
  begin
    pAttribs^ := 2;
    Inc(pAttribs);
  end;

  for i:= 0 to 3 do
  begin
    pAttribs^ := 3;
    Inc(pAttribs);
  end;

  pWorldMeshTemp.UnlockAttributeBuffer;
  D3DXComputeNormals(pWorldMeshTemp, nil);

  // Optimize the mesh
  Result := pWorldMeshTemp.CloneMeshFVF(D3DXMESH_VB_WRITEONLY or D3DXMESH_IB_WRITEONLY,
                                        TWorldVertex_FVF, g_pd3dDevice, g_pWorldMesh);
  if FAILED(Result) then Exit;

  Result := S_OK;

  //Clootie: Not needed in Delphi
  {SAFE_RELEASE( pWorldMeshTemp);}
end;

//-----------------------------------------------------------------------------
// Name: BuildColumn()
// Desc: Helper function for BuildWorldMesh to add column quads to the scene 
//-----------------------------------------------------------------------------
function BuildColumn(var pV: PWorldVertex; x, y, z: Single; width: Single): HRESULT;
var
  w: Single;
begin
  w := width / 2;

  SetTextureCoords(pV, 1.0, 2.0);
  pV.p := D3DXVector3(x - w, y,   z - w); Inc(pV);
  pV.p := D3DXVector3(x + w, y,   z - w); Inc(pV);
  pV.p := D3DXVector3(x + w, 0.0, z - w); Inc(pV);
  pV.p := D3DXVector3(x - w, 0.0, z - w); Inc(pV);

  SetTextureCoords(pV, 1.0, 2.0);
  pV.p := D3DXVector3(x + w, y,   z - w); Inc(pV);
  pV.p := D3DXVector3(x + w, y,   z + w); Inc(pV);
  pV.p := D3DXVector3(x + w, 0.0, z + w); Inc(pV);
  pV.p := D3DXVector3(x + w, 0.0, z - w); Inc(pV);

  SetTextureCoords(pV, 1.0, 2.0);
  pV.p := D3DXVector3(x + w, y,   z + w); Inc(pV);
  pV.p := D3DXVector3(x - w, y,   z + w); Inc(pV);
  pV.p := D3DXVector3(x - w, 0.0, z + w); Inc(pV);
  pV.p := D3DXVector3(x + w, 0.0, z + w); Inc(pV);

  SetTextureCoords(pV, 1.0, 2.0);
  pV.p := D3DXVector3(x - w, y,   z + w); Inc(pV);
  pV.p := D3DXVector3(x - w, y,   z - w); Inc(pV);
  pV.p := D3DXVector3(x - w, 0.0, z - w); Inc(pV);
  pV.p := D3DXVector3(x - w, 0.0, z + w); Inc(pV);

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: SetTextureCoords()
// Desc: Helper function for BuildWorldMesh to set texture coordinates
//       for vertices
//-----------------------------------------------------------------------------
procedure SetTextureCoords(pVertex: PWorldVertex; u, v: Single);
begin
  pVertex.t := D3DXVector2(0.0, 0.0); Inc(pVertex);
  pVertex.t := D3DXVector2(u,   0.0); Inc(pVertex);
  pVertex.t := D3DXVector2(u,   v  ); Inc(pVertex);
  pVertex.t := D3DXVector2(0.0, v  ); // Inc(pVertex);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called once at the beginning of every frame. This is the
// best location for your application to handle updates to the scene, but is not 
// intended to contain actual rendering calls, which should instead be placed in the 
// OnFrameRender callback.  
//--------------------------------------------------------------------------------------
procedure OnFrameMove(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  avLightViewPosition: array[0..NUM_LIGHTS-1] of TD3DXVector4;
  iLight: Integer;
  mView: TD3DXMatrix;
begin
  // Update the camera's position based on user input
  g_Camera.FrameMove(fElapsedTime);

  // Set the flag to refresh the user's simulated adaption level.
  // Frame move is not called when the scene is paused or single-stepped.
  // If the scene is paused, the user's adaptation level needs to remain
  // unchanged.
  g_bAdaptationInvalid := True;

  // Calculate the position of the lights in view space
  for iLight:=0 to NUM_LIGHTS - 1 do
  begin
    mView := g_Camera.GetViewMatrix^;
    D3DXVec4Transform(avLightViewPosition[iLight], g_avLightPosition[iLight], mView);
  end;

  // Set frame shader constants
  g_pEffect.SetBool('g_bEnableToneMap', g_bToneMap);
  g_pEffect.SetBool('g_bEnableBlueShift', g_bBlueShift);
  g_pEffect.SetValue('g_avLightPositionView', @avLightViewPosition, SizeOf(TD3DXVECTOR4) * NUM_LIGHTS);
  g_pEffect.SetValue('g_avLightIntensity', @g_avLightIntensity, SizeOf(TD3DXVECTOR4) * NUM_LIGHTS);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called at the end of every frame to perform all the 
// rendering calls for the scene, and it will also be called if the window needs to be
// repainted. After this function has returned, DXUT will call 
// IDirect3DDevice9::Present to display the contents of the next buffer in the swap chain
//--------------------------------------------------------------------------------------
procedure OnFrameRender(const pd3dDevice: IDirect3DDevice9; fTime: Double; fElapsedTime: Single; pUserContext: Pointer); stdcall;
var
  pSurfLDR: IDirect3DSurface9; // Low dynamic range surface for final output
  pSurfDS: IDirect3DSurface9;  // Low dynamic range depth stencil surface
  pSurfHDR: IDirect3DSurface9; // High dynamic range surface to store
                               // intermediate floating point color values
  uiPassCount: LongWord;
  iPass: Integer;
begin
  // If the settings dialog is being shown, then
  // render it instead of rendering the app's scene
  if g_SettingsDlg.Active then
  begin
    g_SettingsDlg.OnRender(fElapsedTime);
    Exit;
  end;

  // Store the old render target
  V(g_pd3dDevice.GetRenderTarget(0, pSurfLDR));
  V(g_pd3dDevice.GetDepthStencilSurface(pSurfDS));

  // Setup HDR render target
  V(g_pTexScene.GetSurfaceLevel(0, pSurfHDR));
  if g_bUseMultiSampleFloat16 then
  begin
    V(g_pd3dDevice.SetRenderTarget(0, g_pFloatMSRT));
    V(g_pd3dDevice.SetDepthStencilSurface( g_pFloatMSDS));
  end else
  begin
    V(g_pd3dDevice.SetRenderTarget(0, pSurfHDR));
  end;

  // Clear the viewport
  V(g_pd3dDevice.Clear(0, nil, D3DCLEAR_TARGET or D3DCLEAR_ZBUFFER, D3DCOLOR_RGBA(0, 0, 0, 0), 1.0, 0));

  // Render the scene
  if SUCCEEDED(pd3dDevice.BeginScene) then
  begin
    // Render the HDR Scene
    DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'Scene');
    RenderScene;
    DXUT_EndPerfEvent;

    // If using floating point multi sampling, stretchrect to the rendertarget
    if g_bUseMultiSampleFloat16 then
    begin
      V(g_pd3dDevice.StretchRect(g_pFloatMSRT, nil, pSurfHDR, nil, D3DTEXF_NONE));
      V(g_pd3dDevice.SetRenderTarget(0, pSurfHDR));
      V(g_pd3dDevice.SetDepthStencilSurface(pSurfDS));
    end;

    // Create a scaled copy of the scene
    Scene_To_SceneScaled;

    // Setup tone mapping technique
    if g_bToneMap then MeasureLuminance;

    // If FrameMove has been called, the user's adaptation level has also changed
    // and should be updated
    if g_bAdaptationInvalid then
    begin
      // Clear the update flag
      g_bAdaptationInvalid := False;

      // Calculate the current luminance adaptation level
      CalculateAdaptation;
    end;

    // Now that luminance information has been gathered, the scene can be bright-pass filtered
    // to remove everything except bright lights and reflections.
    SceneScaled_To_BrightPass;

    // Blur the bright-pass filtered image to create the source texture for the star effect
    BrightPass_To_StarSource;

    // Scale-down the source texture for the star effect to create the source texture
    // for the bloom effect
    StarSource_To_BloomSource;

    // Render post-process lighting effects
    begin
      DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'Bloom');
      RenderBloom;
      DXUT_EndPerfEvent;
    end;
    begin
      DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'Star');
      RenderStar;
      DXUT_EndPerfEvent;
    end;

    // Draw the high dynamic range scene texture to the low dynamic range
    // back buffer. As part of this final pass, the scene will be tone-mapped
    // using the user's current adapted luminance, blue shift will occur
    // if the scene is determined to be very dark, and the post-process lighting
    // effect textures will be added to the scene.
    V(g_pEffect.SetTechnique('FinalScenePass'));
    V(g_pEffect.SetFloat('g_fMiddleGray', g_fKeyValue));

    V(g_pd3dDevice.SetRenderTarget(0, pSurfLDR));
    V(g_pd3dDevice.SetTexture(0, g_pTexScene));
    V(g_pd3dDevice.SetTexture(1, g_apTexBloom[0]));
    V(g_pd3dDevice.SetTexture(2, g_apTexStar[0]));
    V(g_pd3dDevice.SetTexture(3, g_pTexAdaptedLuminanceCur));
    V(g_pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_POINT));
    V(g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT));
    V(g_pd3dDevice.SetSamplerState(1, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR));
    V(g_pd3dDevice.SetSamplerState(1, D3DSAMP_MINFILTER, D3DTEXF_LINEAR));
    V(g_pd3dDevice.SetSamplerState(2, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR));
    V(g_pd3dDevice.SetSamplerState(2, D3DSAMP_MINFILTER, D3DTEXF_LINEAR));
    V(g_pd3dDevice.SetSamplerState(3, D3DSAMP_MAGFILTER, D3DTEXF_POINT));
    V(g_pd3dDevice.SetSamplerState(3, D3DSAMP_MINFILTER, D3DTEXF_POINT));
        
  
    V(g_pEffect._Begin(@uiPassCount, 0));
    begin
      DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'Final Scene Pass');

      for iPass := 0 to uiPassCount - 1 do
      begin
        V(g_pEffect.BeginPass(iPass));
        DrawFullScreenQuad(0.0, 0.0, 1.0, 1.0);
        V(g_pEffect.EndPass);
      end;
      DXUT_EndPerfEvent;
    end;
    V(g_pEffect._End);

    V(g_pd3dDevice.SetTexture(1, nil));
    V(g_pd3dDevice.SetTexture(2, nil));
    V(g_pd3dDevice.SetTexture(3, nil));

    begin
      DXUT_BeginPerfEvent(DXUT_PERFEVENTCOLOR, 'HUD / Stats');
      RenderText;

      V(g_HUD.OnRender(fElapsedTime));
      V(g_SampleUI.OnRender(fElapsedTime));
      DXUT_EndPerfEvent;
    end;

    V(pd3dDevice.EndScene);
  end;

  // Release surfaces
  SAFE_RELEASE(pSurfHDR);
  SAFE_RELEASE(pSurfLDR);
  SAFE_RELEASE(pSurfDS);
end;


//-----------------------------------------------------------------------------
// Name: RenderScene()
// Desc: Render the world objects and lights
//-----------------------------------------------------------------------------
function RenderScene: HRESULT;
var
  iPassCount: Integer;
  iPass: Integer;
  mWorld: TD3DXMatrixA16;
  mObjectToView: TD3DXMatrixA16;
  mView: TD3DXMatrix;
  iLight: Integer;
  mScale: TD3DXMatrixA16;
  vEmissive: TD3DXVector4;
begin
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_ADDRESSU, D3DTADDRESS_WRAP);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_ADDRESSV, D3DTADDRESS_WRAP);

  mView := g_Camera.GetViewMatrix^;

  g_pEffect.SetTechnique('RenderScene');
  g_pEffect.SetMatrix('g_mObjectToView', mView);
    
  Result := g_pEffect._Begin(@iPassCount, 0);
  if FAILED(Result) then Exit;

  for iPass := 0 to iPassCount - 1 do
  begin
    g_pEffect.BeginPass(iPass);

    // Turn off emissive lighting
    g_pEffect.SetVector('g_vEmissive', D3DXVector4Zero);
        
    // Enable texture
    g_pEffect.SetBool('g_bEnableTexture', True);
    g_pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
    g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);
    
    
    // Render walls and columns
    g_pEffect.SetFloat('g_fPhongExponent', 5.0);
    g_pEffect.SetFloat('g_fPhongCoefficient', 1.0);
    g_pEffect.SetFloat('g_fDiffuseCoefficient', 0.5);
    g_pd3dDevice.SetTexture(0, g_pTexWall);
    g_pEffect.CommitChanges;
    g_pWorldMesh.DrawSubset(0);

    // Render floor
    g_pEffect.SetFloat('g_fPhongExponent', 50.0);
    g_pEffect.SetFloat('g_fPhongCoefficient', 3.0);
    g_pEffect.SetFloat('g_fDiffuseCoefficient', 1.0);
    g_pd3dDevice.SetTexture(0, g_pTexFloor);
    g_pEffect.CommitChanges;
    g_pWorldMesh.DrawSubset(1);

    // Render ceiling
    g_pEffect.SetFloat('g_fPhongExponent', 5.0);
    g_pEffect.SetFloat('g_fPhongCoefficient', 0.3);
    g_pEffect.SetFloat('g_fDiffuseCoefficient', 0.3);
    g_pd3dDevice.SetTexture(0, g_pTexCeiling);
    g_pEffect.CommitChanges;
    g_pWorldMesh.DrawSubset(2);

    // Render paintings
    g_pEffect.SetFloat('g_fPhongExponent', 5.0);
    g_pEffect.SetFloat('g_fPhongCoefficient', 0.3);
    g_pEffect.SetFloat('g_fDiffuseCoefficient', 1.0);
    g_pd3dDevice.SetTexture(0, g_pTexPainting);
    g_pEffect.CommitChanges;
    g_pWorldMesh.DrawSubset(3);

    // Draw the light spheres.
    g_pEffect.SetFloat('g_fPhongExponent', 5.0);
    g_pEffect.SetFloat('g_fPhongCoefficient', 1.0);
    g_pEffect.SetFloat('g_fDiffuseCoefficient', 1.0);
    g_pEffect.SetBool('g_bEnableTexture', False);

    for iLight := 0 to NUM_LIGHTS - 1 do
    begin
      // Just position the point light -- no need to orient it
      D3DXMatrixScaling(mScale, 0.05, 0.05, 0.05);
            
      mView := g_Camera.GetViewMatrix^;
      D3DXMatrixTranslation(mWorld, g_avLightPosition[iLight].x, g_avLightPosition[iLight].y, g_avLightPosition[iLight].z);
      // mWorld := mScale * mWorld;
      D3DXMatrixMultiply(mWorld, mScale, mWorld);
      // mObjectToView := mWorld * mView;
      D3DXMatrixMultiply(mObjectToView, mWorld, mView);
      g_pEffect.SetMatrix('g_mObjectToView', mObjectToView);

      // A light which illuminates objects at 80 lum/sr should be drawn
      // at 3183 lumens/meter^2/steradian, which equates to a multiplier
      // of 39.78 per lumen.
      // vEmissive := EMISSIVE_COEFFICIENT * g_avLightIntensity[iLight];
      D3DXVec4Scale(vEmissive, g_avLightIntensity[iLight], EMISSIVE_COEFFICIENT);
      g_pEffect.SetVector('g_vEmissive', vEmissive);
    
      g_pEffect.CommitChanges;
      g_pmeshSphere.DrawSubset(0);
    end;
    g_pEffect.EndPass;
  end;

  g_pEffect._End;

  Result:= S_OK;
end;




//-----------------------------------------------------------------------------
// Name: MeasureLuminance()
// Desc: Measure the average log luminance in the scene.
//-----------------------------------------------------------------------------
function MeasureLuminance: HRESULT;
var
  iPassCount, iPass: Integer;
  i, x, y, index: Integer;
  avSampleOffsets: array[0..MAX_SAMPLES-1] of TD3DXVector2;
  dwCurTexture: DWORD;
  // Sample log average luminance
  apSurfToneMap: array[0..NUM_TONEMAP_TEXTURES-1] of IDirect3DSurface9;
  desc: TD3DSurfaceDesc;
  tU, tV: Single;
begin
  dwCurTexture := NUM_TONEMAP_TEXTURES-1;

  // Retrieve the tonemap surfaces
  for i:= 0 to NUM_TONEMAP_TEXTURES - 1 do
  begin
    Result := g_apTexToneMap[i].GetSurfaceLevel(0, apSurfToneMap[i]);
    if FAILED(Result) then Exit;
  end;

  g_apTexToneMap[dwCurTexture].GetLevelDesc(0, desc);

  // Initialize the sample offsets for the initial luminance pass.
  tU := 1.0 / (3.0 * desc.Width);
  tV := 1.0 / (3.0 * desc.Height);
    
  index := 0;
  for x := -1 to 1 do
  begin
    for y := -1 to 1 do
    begin
      avSampleOffsets[index].x := x * tU;
      avSampleOffsets[index].y := y * tV;

      Inc(index);
    end;
  end;

    
  // After this pass, the g_apTexToneMap[NUM_TONEMAP_TEXTURES-1] texture will contain
  // a scaled, grayscale copy of the HDR scene. Individual texels contain the log 
  // of average luminance values for points sampled on the HDR texture.
  g_pEffect.SetTechnique('SampleAvgLum');
  g_pEffect.SetValue('g_avSampleOffsets', @avSampleOffsets, SizeOf(avSampleOffsets));

  g_pd3dDevice.SetRenderTarget(0, apSurfToneMap[dwCurTexture]);
  g_pd3dDevice.SetTexture(0, g_pTexSceneScaled);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);
  g_pd3dDevice.SetSamplerState(1, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
  g_pd3dDevice.SetSamplerState(1, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);


  Result := g_pEffect._Begin(@iPassCount, 0);
  if FAILED(Result) then Exit;

  for iPass := 0 to iPassCount - 1 do
  begin
    g_pEffect.BeginPass(iPass);

    // Draw a fullscreen quad to sample the RT
    DrawFullScreenQuad(0.0, 0.0, 1.0, 1.0);

    g_pEffect.EndPass;
  end;

  g_pEffect._End;
  Dec(dwCurTexture);

  // Initialize the sample offsets for the iterative luminance passes
  while (dwCurTexture > 0) do
  begin
    g_apTexToneMap[dwCurTexture+1].GetLevelDesc(0, desc);
    GetSampleOffsets_DownScale4x4(desc.Width, desc.Height, avSampleOffsets);


    // Each of these passes continue to scale down the log of average
    // luminance texture created above, storing intermediate results in
    // g_apTexToneMap[1] through g_apTexToneMap[NUM_TONEMAP_TEXTURES-1].
    g_pEffect.SetTechnique('ResampleAvgLum');
    g_pEffect.SetValue('g_avSampleOffsets', @avSampleOffsets, SizeOf(avSampleOffsets));

    g_pd3dDevice.SetRenderTarget(0, apSurfToneMap[dwCurTexture]);
    g_pd3dDevice.SetTexture(0, g_apTexToneMap[dwCurTexture+1]);
    g_pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_POINT);
    g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);


    Result := g_pEffect._Begin(@iPassCount, 0);
    if FAILED(Result) then Exit;

    for iPass := 0 to iPassCount - 1 do
    begin
      g_pEffect.BeginPass(iPass);

      // Draw a fullscreen quad to sample the RT
      DrawFullScreenQuad(0.0, 0.0, 1.0, 1.0);

      g_pEffect.EndPass;
    end;

    g_pEffect._End;
    Dec(dwCurTexture);
  end;

  // Downsample to 1x1
  g_apTexToneMap[1].GetLevelDesc(0, desc);
  GetSampleOffsets_DownScale4x4(desc.Width, desc.Height, avSampleOffsets);


  // Perform the final pass of the average luminance calculation. This pass
  // scales the 4x4 log of average luminance texture from above and performs
  // an exp() operation to return a single texel cooresponding to the average
  // luminance of the scene in g_apTexToneMap[0].
  g_pEffect.SetTechnique('ResampleAvgLumExp');
  g_pEffect.SetValue('g_avSampleOffsets', @avSampleOffsets, SizeOf(avSampleOffsets));

  g_pd3dDevice.SetRenderTarget(0, apSurfToneMap[0]);
  g_pd3dDevice.SetTexture(0, g_apTexToneMap[1]);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_POINT);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);


  Result := g_pEffect._Begin(@iPassCount, 0);
  if FAILED(Result) then Exit;

  for iPass := 0 to iPassCount - 1 do
  begin
    g_pEffect.BeginPass(iPass);

    // Draw a fullscreen quad to sample the RT
    DrawFullScreenQuad(0.0, 0.0, 1.0, 1.0);

    g_pEffect.EndPass;
  end;
  g_pEffect._End;

  Result := S_OK;
end;




//-----------------------------------------------------------------------------
// Name: CalculateAdaptation()
// Desc: Increment the user's adapted luminance
//-----------------------------------------------------------------------------
function CalculateAdaptation: HRESULT;
var
  uiPass, uiPassCount: Integer;
  pTexSwap: IDirect3DTexture9;
  pSurfAdaptedLum: IDirect3DSurface9;
begin
  // Swap current & last luminance
  pTexSwap := g_pTexAdaptedLuminanceLast;
  g_pTexAdaptedLuminanceLast := g_pTexAdaptedLuminanceCur;
  g_pTexAdaptedLuminanceCur := pTexSwap;

  V(g_pTexAdaptedLuminanceCur.GetSurfaceLevel(0, pSurfAdaptedLum));

  // This simulates the light adaptation that occurs when moving from a
  // dark area to a bright area, or vice versa. The g_pTexAdaptedLuminance
  // texture stores a single texel cooresponding to the user's adapted
  // level.
  g_pEffect.SetTechnique('CalculateAdaptedLum');
  g_pEffect.SetFloat('g_fElapsedTime', DXUTGetElapsedTime);

  g_pd3dDevice.SetRenderTarget(0, pSurfAdaptedLum);
  g_pd3dDevice.SetTexture(0, g_pTexAdaptedLuminanceLast);
  g_pd3dDevice.SetTexture(1, g_apTexToneMap[0]);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_POINT);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);
  g_pd3dDevice.SetSamplerState(1, D3DSAMP_MAGFILTER, D3DTEXF_POINT);
  g_pd3dDevice.SetSamplerState(1, D3DSAMP_MINFILTER, D3DTEXF_POINT);


  V(g_pEffect._Begin(@uiPassCount, 0));

  for uiPass := 0 to uiPassCount - 1 do
  begin
    g_pEffect.BeginPass(uiPass);

    // Draw a fullscreen quad to sample the RT
    DrawFullScreenQuad(0.0, 0.0, 1.0, 1.0);

    g_pEffect.EndPass;
  end;
  g_pEffect._End;

  Result:= S_OK;
end;




const s_maxPasses = 3;
var s_aaColor: array[0..s_maxPasses-1, 0..7] of TD3DXVector4;

//-----------------------------------------------------------------------------
// Name: RenderStar()
// Desc: Render the blooming effect
//-----------------------------------------------------------------------------
function RenderStar: HRESULT;
var
  uiPassCount, uiPass: Integer;
  i, d, p, s: Integer; // Loop variables
  pSurfStar: IDirect3DSurface9;

  // Initialize the constants used during the effect
  starDef: CStarDef;
  fTanFoV: Single; // = ArcTan(D3DX_PI/8);
const
  vWhite: TD3DXVector4 = (x: 1.0; y: 1.0; z: 1.0; w: 1.0);
  nSamples = 8;
const
  s_colorWhite: TD3DXColor = (r: 0.63; g: 0.63; b: 0.63; a: 0.0);
var
  avSampleWeights: array[0..MAX_SAMPLES-1] of TD3DXVector4;
  avSampleOffsets: array[0..MAX_SAMPLES-1] of TD3DXVector2;
  pSurfSource: IDirect3DSurface9;
  pSurfDest: IDirect3DSurface9;
  apSurfStar: array[0..NUM_STAR_TEXTURES-1] of IDirect3DSurface9;
  desc: TD3DSurfaceDesc;
  srcW, srcH: Single;
  ratio: Single;
  chromaticAberrColor: TD3DXColor;
  radOffset: Single;
  pTexSource: IDirect3DTexture9;
  starLine: PStarLine;
  rad: Single;
  sn, cs: Single;
  vtStepUV: TD3DXVector2;
  attnPowScale: Single;
  iWorkTexture: Integer;
  lum: Single;
  strTechnique: AnsiString;
begin
  Result := g_apTexStar[0].GetSurfaceLevel(0, pSurfStar);
  if FAILED(Result) then Exit;

  // Clear the star texture
  g_pd3dDevice.ColorFill(pSurfStar, nil, D3DCOLOR_ARGB(0, 0, 0, 0));
  SAFE_RELEASE(pSurfStar);

  // Avoid rendering the star if it's not being used in the current glare
  if (g_GlareDef.m_fGlareLuminance <= 0.0) or
     (g_GlareDef.m_fStarLuminance <= 0.0) then
  begin
    Result:= S_OK;
    Exit;
  end;

  // Initialize the constants used during the effect
  starDef := g_GlareDef.m_starDef;
  fTanFoV := ArcTan(D3DX_PI/8);

  g_pd3dDevice.SetRenderState(D3DRS_SRCBLEND, D3DBLEND_ONE);
  g_pd3dDevice.SetRenderState(D3DRS_DESTBLEND, D3DBLEND_ONE);

  // Set aside all the star texture surfaces as a convenience
  for i:= 0 to NUM_STAR_TEXTURES - 1 do
  begin
    Result := g_apTexStar[i].GetSurfaceLevel(0, apSurfStar[i]);
    if FAILED(Result) then Exit;
  end;

  // Get the source texture dimensions
  Result := g_pTexStarSource.GetSurfaceLevel(0, pSurfSource);
  if FAILED(Result) then Exit;

  Result := pSurfSource.GetDesc(desc);
  if FAILED(Result) then Exit;

  SAFE_RELEASE(pSurfSource);

  srcW := desc.Width;
  srcH:= desc.Height;


  for p := 0 to s_maxPasses - 1 do
  begin
    ratio := (p + 1) / s_maxPasses;

    for s := 0 to nSamples - 1 do
    begin
      D3DXColorLerp(chromaticAberrColor,
          CStarDef.GetChromaticAberrationColor(s)^,
          s_colorWhite,
          ratio);

      D3DXColorLerp(PD3DXColor(@s_aaColor[p][s])^,
          s_colorWhite, chromaticAberrColor,
          g_GlareDef.m_fChromaticAberration);
    end;
  end;

  radOffset := g_GlareDef.m_fStarInclination + starDef.m_fInclination;


  // Direction loop
  for d := 0 to starDef.m_nStarLines - 1 do
  begin
    starLine := @starDef.m_pStarLine[d];

    pTexSource := g_pTexStarSource;

    rad := radOffset + starLine.fInclination;
    sn := sin(rad); cs := cos(rad);
    vtStepUV.x := sn / srcW * starLine.fSampleLength;
    vtStepUV.y := cs / srcH * starLine.fSampleLength;

    attnPowScale := (fTanFoV + 0.1) * 1.0 *
                    (160.0 + 120.0) / (srcW + srcH) * 1.2;

    // 1 direction expansion loop
    g_pd3dDevice.SetRenderState(D3DRS_ALPHABLENDENABLE, iFalse);

    iWorkTexture := 1;
    for p := 0 to starLine.nPasses - 1 do
    begin
      if (p = starLine.nPasses - 1) then
      begin
        // Last pass move to other work buffer
        pSurfDest := apSurfStar[d+4];
      end else
      begin
        pSurfDest := apSurfStar[iWorkTexture];
      end;

      // Sampling configration for each stage
      for i := 0 to nSamples -1 do
      begin
        lum := Power(starLine.fAttenuation, attnPowScale * i);

        // avSampleWeights[i] := s_aaColor[starLine.nPasses - 1 - p][i] * lum * (p+1.0) * 0.5;
        D3DXVec4Scale(avSampleWeights[i], s_aaColor[starLine.nPasses - 1 - p][i], lum * (p+1.0) * 0.5);


        // Offset of sampling coordinate
        avSampleOffsets[i].x := vtStepUV.x * i;
        avSampleOffsets[i].y := vtStepUV.y * i;
        if (abs(avSampleOffsets[i].x) >= 0.9) or
           (abs(avSampleOffsets[i].y) >= 0.9) then
        begin
          avSampleOffsets[i].x := 0.0;
          avSampleOffsets[i].y := 0.0;
          // avSampleWeights[i] := avSampleWeights[i] * 0.0;
        end;
      end;


      g_pEffect.SetTechnique('Star');
      g_pEffect.SetValue('g_avSampleOffsets', @avSampleOffsets, SizeOf(avSampleOffsets));
      g_pEffect.SetVectorArray('g_avSampleWeights', @avSampleWeights, nSamples);

      g_pd3dDevice.SetRenderTarget(0, pSurfDest);
      g_pd3dDevice.SetTexture(0, pTexSource);
      g_pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
      g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);


      Result := g_pEffect._Begin(@uiPassCount, 0);
      if FAILED(Result) then Exit;

      for uiPass := 0 to uiPassCount - 1 do
      begin
        g_pEffect.BeginPass(uiPass);

        // Draw a fullscreen quad to sample the RT
        DrawFullScreenQuad(0.0, 0.0, 1.0, 1.0);

        g_pEffect.EndPass;
      end;

      g_pEffect._End;

      // Setup next expansion
      D3DXVec2Scale(vtStepUV, vtStepUV, nSamples);
      attnPowScale := attnPowScale * nSamples;

      // Set the work drawn just before to next texture source.
      pTexSource := g_apTexStar[iWorkTexture];

      Inc(iWorkTexture, 1);
      if (iWorkTexture > 2) then iWorkTexture := 1;
    end;
  end;


  pSurfDest := apSurfStar[0];


  for i:= 0 to starDef.m_nStarLines - 1 do
  begin
    g_pd3dDevice.SetTexture( i, g_apTexStar[i+4]);
    g_pd3dDevice.SetSamplerState( i, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
    g_pd3dDevice.SetSamplerState( i, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);

    D3DXVec4Scale(avSampleWeights[i], vWhite, 1.0 / starDef.m_nStarLines);
  end;


  strTechnique := Format('MergeTextures_%d', [starDef.m_nStarLines]);

  g_pEffect.SetTechnique(TD3DXHandle(strTechnique));

  g_pEffect.SetVectorArray('g_avSampleWeights', @avSampleWeights, starDef.m_nStarLines);

  g_pd3dDevice.SetRenderTarget(0, pSurfDest);

  Result := g_pEffect._Begin(@uiPassCount, 0);
  if FAILED(Result) then Exit;

  for uiPass := 0 to uiPassCount - 1 do
  begin
    g_pEffect.BeginPass(uiPass);

    // Draw a fullscreen quad to sample the RT
    DrawFullScreenQuad(0.0, 0.0, 1.0, 1.0);

    g_pEffect.EndPass;
  end;
  g_pEffect._End;

  for i:= 0 to starDef.m_nStarLines - 1 do
    g_pd3dDevice.SetTexture(i, nil);

  Result := S_OK;
end;




//-----------------------------------------------------------------------------
// Name: RenderBloom()
// Desc: Render the blooming effect
//-----------------------------------------------------------------------------
function RenderBloom: HRESULT;
var
  uiPassCount, uiPass: Integer;
  i: Integer;
  avSampleOffsets: array[0..MAX_SAMPLES-1] of TD3DXVector2;
  afSampleOffsets: array[0..MAX_SAMPLES-1] of Single;
  avSampleWeights: array[0..MAX_SAMPLES-1] of TD3DXVector4;
  pSurfScaledHDR: IDirect3DSurface9;
  pSurfBloom: IDirect3DSurface9;
  pSurfHDR: IDirect3DSurface9;
  pSurfTempBloom: IDirect3DSurface9;
  pSurfBloomSource: IDirect3DSurface9;
  rectSrc: TRect;
  rectDest: TRect;
  coords: TCoordRect;
  desc: TD3DSurfaceDesc;
begin
  g_pTexSceneScaled.GetSurfaceLevel(0, pSurfScaledHDR);
  g_apTexBloom[0].GetSurfaceLevel(0, pSurfBloom);

  g_pTexScene.GetSurfaceLevel(0, pSurfHDR);
  g_apTexBloom[1].GetSurfaceLevel(0, pSurfTempBloom);
  g_apTexBloom[2].GetSurfaceLevel(0, pSurfBloomSource);

  // Clear the bloom texture
  g_pd3dDevice.ColorFill(pSurfBloom, nil, D3DCOLOR_ARGB(0, 0, 0, 0));

  GetTextureRect(g_pTexBloomSource, rectSrc);
  InflateRect(rectSrc, -1, -1);

  GetTextureRect(g_apTexBloom[2], rectDest);
  InflateRect(rectDest, -1, -1);

  GetTextureCoords(g_pTexBloomSource, @rectSrc, g_apTexBloom[2], @rectDest, coords);

  Result := g_pTexBloomSource.GetLevelDesc(0, desc);
  if FAILED(Result) then Exit;


  g_pEffect.SetTechnique('GaussBlur5x5');

  Result := GetSampleOffsets_GaussBlur5x5(desc.Width, desc.Height, avSampleOffsets, avSampleWeights, 1.0);
  if FAILED(Result) then Exit;

  g_pEffect.SetValue('g_avSampleOffsets', @avSampleOffsets, SizeOf(avSampleOffsets));
  g_pEffect.SetValue('g_avSampleWeights', @avSampleWeights, SizeOf(avSampleWeights));

  g_pd3dDevice.SetRenderTarget(0, pSurfBloomSource);
  g_pd3dDevice.SetTexture(0, g_pTexBloomSource);
  g_pd3dDevice.SetScissorRect(@rectDest);
  g_pd3dDevice.SetRenderState(D3DRS_SCISSORTESTENABLE, iTrue);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_POINT);


  Result := g_pEffect._Begin(@uiPassCount, 0);
  if FAILED(Result) then Exit;

  for uiPass := 0 to uiPassCount - 1 do
  begin
    g_pEffect.BeginPass(uiPass);

    // Draw a fullscreen quad to sample the RT
    DrawFullScreenQuad(coords);

    g_pEffect.EndPass;
  end;
  g_pEffect._End;
  g_pd3dDevice.SetRenderState(D3DRS_SCISSORTESTENABLE, iFalse);

  Result := g_apTexBloom[2].GetLevelDesc(0, desc);
  if FAILED(Result) then Exit;

  {Result := }GetSampleOffsets_Bloom(desc.Width, afSampleOffsets, avSampleWeights, 3.0, 2.0);
  for i := 0 to MAX_SAMPLES - 1 do
  begin
    avSampleOffsets[i] := D3DXVector2(afSampleOffsets[i], 0.0);
  end;


  g_pEffect.SetTechnique('Bloom');
  g_pEffect.SetValue('g_avSampleOffsets', @avSampleOffsets, SizeOf(avSampleOffsets));
  g_pEffect.SetValue('g_avSampleWeights', @avSampleWeights, SizeOf(avSampleWeights));

  g_pd3dDevice.SetRenderTarget(0, pSurfTempBloom);
  g_pd3dDevice.SetTexture(0, g_apTexBloom[2]);
  g_pd3dDevice.SetScissorRect(@rectDest);
  g_pd3dDevice.SetRenderState(D3DRS_SCISSORTESTENABLE, iTrue);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_POINT);


  g_pEffect._Begin(@uiPassCount, 0);
  for uiPass := 0 to uiPassCount - 1 do
  begin
    g_pEffect.BeginPass(uiPass);

    // Draw a fullscreen quad to sample the RT
    DrawFullScreenQuad(coords);

    g_pEffect.EndPass;
  end;
  g_pEffect._End;
  g_pd3dDevice.SetRenderState(D3DRS_SCISSORTESTENABLE, iFalse);


  Result := g_apTexBloom[1].GetLevelDesc(0, desc);
  if FAILED(Result) then Exit;

  {Result := }GetSampleOffsets_Bloom(desc.Height, afSampleOffsets, avSampleWeights, 3.0, 2.0);
  for i := 0 to MAX_SAMPLES - 1 do
  begin
    avSampleOffsets[i] := D3DXVector2(0.0, afSampleOffsets[i]);
  end;

  GetTextureRect(g_apTexBloom[1], rectSrc);
  InflateRect(rectSrc, -1, -1);

  GetTextureCoords(g_apTexBloom[1], @rectSrc, g_apTexBloom[0], nil, coords);


  g_pEffect.SetTechnique('Bloom');
  g_pEffect.SetValue('g_avSampleOffsets', @avSampleOffsets, SizeOf(avSampleOffsets));
  g_pEffect.SetValue('g_avSampleWeights', @avSampleWeights, SizeOf(avSampleWeights));

  g_pd3dDevice.SetRenderTarget(0, pSurfBloom);
  g_pd3dDevice.SetTexture(0, g_apTexBloom[1]);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_POINT);


  Result := g_pEffect._Begin(@uiPassCount, 0);
  if FAILED(Result) then Exit;

  for uiPass := 0 to uiPassCount - 1 do
  begin
    g_pEffect.BeginPass(uiPass);

    // Draw a fullscreen quad to sample the RT
    DrawFullScreenQuad(coords);

    g_pEffect.EndPass;
  end;
  g_pEffect._End;

  Result := S_OK;
end;



//-----------------------------------------------------------------------------
// Name: DrawFullScreenQuad
// Desc: Draw a properly aligned quad covering the entire render target
//-----------------------------------------------------------------------------
procedure DrawFullScreenQuad(const c: TCoordRect); overload;
begin
  DrawFullScreenQuad(c.fLeftU, c.fTopV, c.fRightU, c.fBottomV);
end;

procedure DrawFullScreenQuad(fLeftU, fTopV, fRightU, fBottomV: Single); overload;
var
  dtdsdRT: TD3DSurfaceDesc;
  pSurfRT: IDirect3DSurface9;
  fWidth5, fHeight5: Single;
  svQuad: array[0..3] of TScreenVertex; 
begin
  // Acquire render target width and height
  g_pd3dDevice.GetRenderTarget(0, pSurfRT);
  pSurfRT.GetDesc(dtdsdRT);
  pSurfRT := nil;

  // Ensure that we're directly mapping texels to pixels by offset by 0.5
  // For more info see the doc page titled "Directly Mapping Texels to Pixels"
  fWidth5 := dtdsdRT.Width - 0.5;
  fHeight5 := dtdsdRT.Height - 0.5;

  // Draw the quad
  svQuad[0].p := D3DXVector4(-0.5, -0.5, 0.5, 1.0);
  svQuad[0].t := D3DXVector2(fLeftU, fTopV);

  svQuad[1].p := D3DXVector4(fWidth5, -0.5, 0.5, 1.0);
  svQuad[1].t := D3DXVector2(fRightU, fTopV);

  svQuad[2].p := D3DXVector4(-0.5, fHeight5, 0.5, 1.0);
  svQuad[2].t := D3DXVector2(fLeftU, fBottomV);

  svQuad[3].p := D3DXVector4(fWidth5, fHeight5, 0.5, 1.0);
  svQuad[3].t := D3DXVector2(fRightU, fBottomV);

  g_pd3dDevice.SetRenderState(D3DRS_ZENABLE, iFalse);
  g_pd3dDevice.SetFVF(TScreenVertex_FVF);
  g_pd3dDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, svQuad, SizeOf(TScreenVertex));
  g_pd3dDevice.SetRenderState(D3DRS_ZENABLE, iTrue);
end;


//-----------------------------------------------------------------------------
// Name: GetTextureRect()
// Desc: Get the dimensions of the texture
//-----------------------------------------------------------------------------
function GetTextureRect(const pTexture: IDirect3DTexture9; out pRect: TRect): HRESULT;
var
  desc: TD3DSurfaceDesc;
begin
  if (pTexture = nil) then
  begin
    Result:= E_INVALIDARG;
    Exit;
  end;

  Result := pTexture.GetLevelDesc(0, desc);
  if FAILED(Result) then Exit;

  pRect.left := 0;
  pRect.top := 0;
  pRect.right := desc.Width;
  pRect.bottom := desc.Height;

  Result:= S_OK;
end;




//-----------------------------------------------------------------------------
// Name: GetTextureCoords()
// Desc: Get the texture coordinates to use when rendering into the destination
//       texture, given the source and destination rectangles
//-----------------------------------------------------------------------------
function GetTextureCoords(const pTexSrc: IDirect3DTexture9; pRectSrc: PRect; pTexDest: IDirect3DTexture9; pRectDest: PRect; var pCoords: TCoordRect): HRESULT;
var
  desc: TD3DSurfaceDesc;
  tU, tV: Single;
begin
  // Validate arguments
  if (pTexSrc = nil) or (pTexDest = nil) then
  begin
    Result:= E_INVALIDARG;
    Exit;
  end;

  // Start with a default mapping of the complete source surface to complete 
  // destination surface
  pCoords.fLeftU := 0.0;
  pCoords.fTopV := 0.0;
  pCoords.fRightU := 1.0; 
  pCoords.fBottomV := 1.0;

  // If not using the complete source surface, adjust the coordinates
  if (pRectSrc <> nil) then
  begin
    // Get destination texture description
    Result := pTexSrc.GetLevelDesc(0, desc);
    if FAILED(Result) then Exit;

    // These delta values are the distance between source texel centers in
    // texture address space
    tU := 1.0 / desc.Width;
    tV := 1.0 / desc.Height;

    pCoords.fLeftU   := pCoords.fLeftU   + pRectSrc.left * tU;
    pCoords.fTopV    := pCoords.fTopV    + pRectSrc.top * tV;
    pCoords.fRightU  := pCoords.fRightU  - (Integer(desc.Width) - pRectSrc.right) * tU;
    pCoords.fBottomV := pCoords.fBottomV - (Integer(desc.Height) - pRectSrc.bottom) * tV;
  end;

  // If not drawing to the complete destination surface, adjust the coordinates
  if (pRectDest <> nil) then
  begin
    // Get source texture description
    Result := pTexDest.GetLevelDesc(0, desc);
    if FAILED(Result) then Exit;

    // These delta values are the distance between source texel centers in
    // texture address space
    tU := 1.0 / desc.Width;
    tV := 1.0 / desc.Height;

    pCoords.fLeftU   := pCoords.fLeftU   - pRectDest.left * tU;
    pCoords.fTopV    := pCoords.fTopV    - pRectDest.top * tV;
    pCoords.fRightU  := pCoords.fRightU  + (Integer(desc.Width) - pRectDest.right) * tU;
    pCoords.fBottomV := pCoords.fBottomV + (Integer(desc.Height) - pRectDest.bottom) * tV;
  end;

  Result:= S_OK;
end;




//-----------------------------------------------------------------------------
// Name: Scene_To_SceneScaled()
// Desc: Scale down g_pTexScene by 1/4 x 1/4 and place the result in 
//       g_pTexSceneScaled
//-----------------------------------------------------------------------------
function Scene_To_SceneScaled: HRESULT;
var
  avSampleOffsets: array[0..MAX_SAMPLES-1] of TD3DXVector2;
  pSurfScaledScene: IDirect3DSurface9;
  pBackBufferDesc: PD3DSurfaceDesc;
  rectSrc: TRect;
  coords: TCoordRect;
  uiPassCount, uiPass: Integer;       
begin
  // Get the new render target surface
  Result := g_pTexSceneScaled.GetSurfaceLevel(0, pSurfScaledScene);
  if FAILED(Result) then Exit;

  pBackBufferDesc := DXUTGetBackBufferSurfaceDesc;

  // Create a 1/4 x 1/4 scale copy of the HDR texture. Since bloom textures
  // are 1/8 x 1/8 scale, border texels of the HDR texture will be discarded
  // to keep the dimensions evenly divisible by 8; this allows for precise
  // control over sampling inside pixel shaders.
  g_pEffect.SetTechnique('DownScale4x4');

  // Place the rectangle in the center of the back buffer surface
  rectSrc.left := (pBackBufferDesc.Width - g_dwCropWidth) div 2;
  rectSrc.top := (pBackBufferDesc.Height - g_dwCropHeight) div 2;
  rectSrc.right := rectSrc.left + Integer(g_dwCropWidth);
  rectSrc.bottom := rectSrc.top + Integer(g_dwCropHeight);

  // Get the texture coordinates for the render target
  GetTextureCoords(g_pTexScene, @rectSrc, g_pTexSceneScaled, nil, coords);

  // Get the sample offsets used within the pixel shader
  GetSampleOffsets_DownScale4x4(pBackBufferDesc.Width, pBackBufferDesc.Height, avSampleOffsets);
  g_pEffect.SetValue('g_avSampleOffsets', @avSampleOffsets, SizeOf(avSampleOffsets));

  g_pd3dDevice.SetRenderTarget(0, pSurfScaledScene);
  g_pd3dDevice.SetTexture(0, g_pTexScene);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);

  Result := g_pEffect._Begin(@uiPassCount, 0);
  if FAILED(Result) then Exit;

  for uiPass := 0 to uiPassCount - 1 do
  begin
    g_pEffect.BeginPass(uiPass);

    // Draw a fullscreen quad
    DrawFullScreenQuad(coords);

    g_pEffect.EndPass;
  end;
  g_pEffect._End;

  Result := S_OK;
end;




//-----------------------------------------------------------------------------
// Name: SceneScaled_To_BrightPass
// Desc: Run the bright-pass filter on g_pTexSceneScaled and place the result
//       in g_pTexBrightPass
//-----------------------------------------------------------------------------
function SceneScaled_To_BrightPass: HRESULT;
var
  pSurfBrightPass: IDirect3DSurface9;
  desc: TD3DSurfaceDesc;
  rectSrc: TRect;
  rectDest: TRect;
  coords: TCoordRect;
  uiPass, uiPassCount: Integer;
begin
  // Get the new render target surface
  Result := g_pTexBrightPass.GetSurfaceLevel(0, pSurfBrightPass);
  if FAILED(Result) then Exit;

  g_pTexSceneScaled.GetLevelDesc(0, desc);

  // Get the rectangle describing the sampled portion of the source texture.
  // Decrease the rectangle to adjust for the single pixel black border.
  GetTextureRect(g_pTexSceneScaled, rectSrc);
  InflateRect(rectSrc, -1, -1);

  // Get the destination rectangle.
  // Decrease the rectangle to adjust for the single pixel black border.
  GetTextureRect(g_pTexBrightPass, rectDest);
  InflateRect(rectDest, -1, -1);

  // Get the correct texture coordinates to apply to the rendered quad in order 
  // to sample from the source rectangle and render into the destination rectangle
  GetTextureCoords(g_pTexSceneScaled, @rectSrc, g_pTexBrightPass, @rectDest, coords);

  // The bright-pass filter removes everything from the scene except lights and
  // bright reflections
  g_pEffect.SetTechnique('BrightPassFilter');

  g_pd3dDevice.SetRenderTarget(0, pSurfBrightPass);
  g_pd3dDevice.SetTexture(0, g_pTexSceneScaled);
  g_pd3dDevice.SetTexture(1, g_pTexAdaptedLuminanceCur);
  g_pd3dDevice.SetRenderState(D3DRS_SCISSORTESTENABLE, iTrue);
  g_pd3dDevice.SetScissorRect(@rectDest);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_POINT);
  g_pd3dDevice.SetSamplerState(1, D3DSAMP_MINFILTER, D3DTEXF_POINT);
  g_pd3dDevice.SetSamplerState(1, D3DSAMP_MAGFILTER, D3DTEXF_POINT);

  Result := g_pEffect._Begin(@uiPassCount, 0);
  if FAILED(Result) then Exit;

  for uiPass := 0 to uiPassCount - 1 do
  begin
    g_pEffect.BeginPass(uiPass);

    // Draw a fullscreen quad to sample the RT
    DrawFullScreenQuad(coords);

    g_pEffect.EndPass;
  end;

  g_pEffect._End;
  g_pd3dDevice.SetRenderState(D3DRS_SCISSORTESTENABLE, iFalse);

  Result := S_OK;
end;




//-----------------------------------------------------------------------------
// Name: BrightPass_To_StarSource
// Desc: Perform a 5x5 gaussian blur on g_pTexBrightPass and place the result
//       in g_pTexStarSource. The bright-pass filtered image is blurred before
//       being used for star operations to avoid aliasing artifacts.
//-----------------------------------------------------------------------------
function BrightPass_To_StarSource: HRESULT;
var
  avSampleOffsets: array[0..MAX_SAMPLES-1] of TD3DXVector2;
  avSampleWeights: array[0..MAX_SAMPLES-1] of TD3DXVector4;
  pSurfStarSource: IDirect3DSurface9;
  rectDest: TRect;
  coords: TCoordRect;
  desc: TD3DSurfaceDesc;
  uiPassCount, uiPass: Integer;
begin
  // Get the new render target surface
  Result := g_pTexStarSource.GetSurfaceLevel(0, pSurfStarSource);
  if FAILED(Result) then Exit;

  // Get the destination rectangle.
  // Decrease the rectangle to adjust for the single pixel black border.
  GetTextureRect(g_pTexStarSource, rectDest);
  InflateRect(rectDest, -1, -1);

  // Get the correct texture coordinates to apply to the rendered quad in order
  // to sample from the source rectangle and render into the destination rectangle
  GetTextureCoords(g_pTexBrightPass, nil, g_pTexStarSource, @rectDest, coords);

  // Get the sample offsets used within the pixel shader
  Result := g_pTexBrightPass.GetLevelDesc(0, desc);
  if FAILED(Result) then Exit;


  GetSampleOffsets_GaussBlur5x5(desc.Width, desc.Height, avSampleOffsets, avSampleWeights);
  g_pEffect.SetValue('g_avSampleOffsets', @avSampleOffsets, SizeOf(avSampleOffsets));
  g_pEffect.SetValue('g_avSampleWeights', @avSampleWeights, SizeOf(avSampleWeights));

  // The gaussian blur smooths out rough edges to avoid aliasing effects
  // when the star effect is run
  g_pEffect.SetTechnique('GaussBlur5x5');

  g_pd3dDevice.SetRenderTarget(0, pSurfStarSource);
  g_pd3dDevice.SetTexture(0, g_pTexBrightPass);
  g_pd3dDevice.SetScissorRect(@rectDest);
  g_pd3dDevice.SetRenderState(D3DRS_SCISSORTESTENABLE, iTrue);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
   
  Result := g_pEffect._Begin(@uiPassCount, 0);
  if FAILED(Result) then Exit;

  for uiPass := 0 to uiPassCount - 1 do
  begin
    g_pEffect.BeginPass(uiPass);

    // Draw a fullscreen quad
    DrawFullScreenQuad(coords);

    g_pEffect.EndPass;
  end;
  g_pEffect._End;
  g_pd3dDevice.SetRenderState(D3DRS_SCISSORTESTENABLE, iFalse);

  Result := S_OK;
end;




//-----------------------------------------------------------------------------
// Name: StarSource_To_BloomSource
// Desc: Scale down g_pTexStarSource by 1/2 x 1/2 and place the result in
//       g_pTexBloomSource
//-----------------------------------------------------------------------------
function StarSource_To_BloomSource: HRESULT;
var
  avSampleOffsets: array[0..MAX_SAMPLES-1] of TD3DXVector2;
  pSurfBloomSource: IDirect3DSurface9;
  rectSrc: TRect;
  rectDest: TRect;
  coords: TCoordRect;
  desc: TD3DSurfaceDesc;
  uiPassCount, uiPass: Integer;       
begin
  // Get the new render target surface
  Result := g_pTexBloomSource.GetSurfaceLevel(0, pSurfBloomSource);
  if FAILED(Result) then Exit;


  // Get the rectangle describing the sampled portion of the source texture.
  // Decrease the rectangle to adjust for the single pixel black border.
  GetTextureRect(g_pTexStarSource, rectSrc);
  InflateRect(rectSrc, -1, -1);

  // Get the destination rectangle.
  // Decrease the rectangle to adjust for the single pixel black border.
  GetTextureRect(g_pTexBloomSource, rectDest);
  InflateRect(rectDest, -1, -1);

  // Get the correct texture coordinates to apply to the rendered quad in order
  // to sample from the source rectangle and render into the destination rectangle
  GetTextureCoords(g_pTexStarSource, @rectSrc, g_pTexBloomSource, @rectDest, coords);

  // Get the sample offsets used within the pixel shader
  Result := g_pTexBrightPass.GetLevelDesc(0, desc);
  if FAILED(Result) then Exit;

  GetSampleOffsets_DownScale2x2(desc.Width, desc.Height, avSampleOffsets);
  g_pEffect.SetValue('g_avSampleOffsets', @avSampleOffsets, SizeOf(avSampleOffsets));

  // Create an exact 1/2 x 1/2 copy of the source texture
  g_pEffect.SetTechnique('DownScale2x2');

  g_pd3dDevice.SetRenderTarget(0, pSurfBloomSource);
  g_pd3dDevice.SetTexture(0, g_pTexStarSource);
  g_pd3dDevice.SetScissorRect(@rectDest);
  g_pd3dDevice.SetRenderState(D3DRS_SCISSORTESTENABLE, iTrue);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
  g_pd3dDevice.SetSamplerState(0, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);

  Result := g_pEffect._Begin(@uiPassCount, 0);
  if FAILED(Result) then Exit;

  for uiPass := 0 to uiPassCount - 1 do
  begin
    g_pEffect.BeginPass(uiPass);

    // Draw a fullscreen quad
    DrawFullScreenQuad(coords);

    g_pEffect.EndPass;
  end;
  g_pEffect._End;
  g_pd3dDevice.SetRenderState(D3DRS_SCISSORTESTENABLE, iFalse);

  Result := S_OK;
end;




//-----------------------------------------------------------------------------
// Name: GetSampleOffsets_DownScale4x4
// Desc: Get the texture coordinate offsets to be used inside the DownScale4x4
//       pixel shader.
//-----------------------------------------------------------------------------
function GetSampleOffsets_DownScale4x4(dwWidth, dwHeight: DWORD; var avSampleOffsets: array of TD3DXVector2): HRESULT;
var
  tU, tV: Single;
  index: Integer;
  x, y: Integer;
begin
{  if( NULL == avSampleOffsets )
      return E_INVALIDARG; }

  tU := 1.0 / dwWidth;
  tV := 1.0 / dwHeight;

  // Sample from the 16 surrounding points. Since the center point will be in
  // the exact center of 16 texels, a 0.5f offset is needed to specify a texel
  // center.
  index := 0;
  for y := 0 to 3 do
    for x := 0 to 3 do
    begin
      avSampleOffsets[index].x := (x - 1.5) * tU;
      avSampleOffsets[index].y := (y - 1.5) * tV;

      Inc(index);
    end;

  Result:= S_OK;
end;




//-----------------------------------------------------------------------------
// Name: GetSampleOffsets_DownScale2x2
// Desc: Get the texture coordinate offsets to be used inside the DownScale2x2
//       pixel shader.
//-----------------------------------------------------------------------------
function GetSampleOffsets_DownScale2x2(dwWidth, dwHeight: DWORD; var avSampleOffsets: array of TD3DXVector2): HRESULT;
var
  tU, tV: Single;
  index: Integer;
  x, y: Integer;
begin
{    if( NULL == avSampleOffsets )
        return E_INVALIDARG; }

  tU := 1.0 / dwWidth;
  tV := 1.0 / dwHeight;

  // Sample from the 4 surrounding points. Since the center point will be in
  // the exact center of 4 texels, a 0.5f offset is needed to specify a texel
  // center.
  index := 0;
  for y := 0 to 1 do
    for x := 0 to 1 do
    begin
      avSampleOffsets[index].x := (x - 0.5) * tU;
      avSampleOffsets[index].y := (y - 0.5) * tV;

      Inc(index);
    end;

  Result:= S_OK;
end;




//-----------------------------------------------------------------------------
// Name: GetSampleOffsets_GaussBlur5x5
// Desc: Get the texture coordinate offsets to be used inside the GaussBlur5x5
//       pixel shader.
//-----------------------------------------------------------------------------
function GetSampleOffsets_GaussBlur5x5(dwD3DTexWidth, dwD3DTexHeight: DWORD;
  var avTexCoordOffset: array of TD3DXVector2; var avSampleWeight: array of TD3DXVector4;
  fMultiplier: Single = 1.0): HRESULT;
var
  tu, tv: Single;
  vWhite: TD3DXVector4;
  totalWeight: Single;
  index: Integer;
  i, x, y: Integer;
begin
  tu := 1.0 / dwD3DTexWidth;
  tv := 1.0 / dwD3DTexHeight;

  vWhite := D3DXVector4(1.0, 1.0, 1.0, 1.0);

  totalWeight := 0.0;
  index := 0;
  for x := -2 to 2 do
    for y := -2 to 2 do
    begin
       // Exclude pixels with a block distance greater than 2. This will
       // create a kernel which approximates a 5x5 kernel using only 13
       // sample points instead of 25; this is necessary since 2.0 shaders
       // only support 16 texture grabs.
       if (abs(x) + abs(y) > 2) then Continue;

       // Get the unscaled Gaussian intensity for this offset
       avTexCoordOffset[index] := D3DXVector2(x * tu, y * tv);
       // avSampleWeight[index] := vWhite * GaussianDistribution(x, y, 1.0);
       D3DXVec4Scale(avSampleWeight[index], vWhite, GaussianDistribution(x, y, 1.0));
       totalWeight := totalWeight + avSampleWeight[index].x;

       Inc(index);
    end;

  // Divide the current weight by the total weight of all the samples; Gaussian
  // blur kernels add to 1.0f to ensure that the intensity of the image isn't
  // changed when the blur occurs. An optional multiplier variable is used to
  // add or remove image intensity during the blur.
  for i := 0 to index - 1 do
  begin
    D3DXVec4Scale(avSampleWeight[i], avSampleWeight[i], fMultiplier / totalWeight);
  end;

  Result:= S_OK; 
end;




//-----------------------------------------------------------------------------
// Name: GetSampleOffsets_Bloom
// Desc: Get the texture coordinate offsets to be used inside the Bloom
//       pixel shader.
//-----------------------------------------------------------------------------
function GetSampleOffsets_Bloom(dwD3DTexSize: DWORD;
  var afTexCoordOffset: array of Single; var avColorWeight: array of TD3DXVector4;
  fDeviation: Single; fMultiplier: Single = 1.0): HRESULT;
var
  i: Integer;
  tu: Single;
  weight: Single;
begin
  tu := 1.0 / dwD3DTexSize;

  // Fill the center texel
  weight := fMultiplier * GaussianDistribution(0, 0, fDeviation);
  avColorWeight[0] := D3DXVector4(weight, weight, weight, 1.0);

  afTexCoordOffset[0] := 0.0;

  // Fill the first half
  for i := 1 to 7 do
  begin
    // Get the Gaussian intensity for this offset
    weight := fMultiplier * GaussianDistribution(i, 0, fDeviation);
    afTexCoordOffset[i] := i * tu;

    avColorWeight[i] := D3DXVector4(weight, weight, weight, 1.0);
  end;

  // Mirror to the second half
  for i:= 8 to 14 do 
  begin
    avColorWeight[i] := avColorWeight[i-7];
    afTexCoordOffset[i] := -afTexCoordOffset[i-7];
  end;

  Result:= S_OK;
end;




//-----------------------------------------------------------------------------
// Name: GetSampleOffsets_Bloom
// Desc: Get the texture coordinate offsets to be used inside the Bloom
//       pixel shader.
//-----------------------------------------------------------------------------
function GetSampleOffsets_Star(dwD3DTexSize: DWORD;
  var afTexCoordOffset: array {[15]} of Single; var avColorWeight: array of TD3DXVector4; fDeviation: Single): HRESULT;
var
  i: Integer;
  tu: Single;
  weight: Single;
begin
  tu := 1.0 / dwD3DTexSize;

  // Fill the center texel
  weight := 1.0 * GaussianDistribution(0, 0, fDeviation);
  avColorWeight[0] := D3DXVector4(weight, weight, weight, 1.0);

  afTexCoordOffset[0] := 0.0;

  // Fill the first half
  for i := 1 to 7 do 
  begin
    // Get the Gaussian intensity for this offset
    weight := 1.0 * GaussianDistribution(i, 0, fDeviation);
    afTexCoordOffset[i] := i * tu;

    avColorWeight[i] := D3DXVector4(weight, weight, weight, 1.0);
  end;

  // Mirror to the second half
  for i := 8 to 14 do
  begin
    avColorWeight[i] := avColorWeight[i-7];
    afTexCoordOffset[i] := -afTexCoordOffset[i-7];
  end;

  Result:= S_OK;
end;




//-----------------------------------------------------------------------------
// Name: GaussianDistribution
// Desc: Helper function for GetSampleOffsets function to compute the
//       2 parameter Gaussian distrubution using the given standard deviation
//       rho
//-----------------------------------------------------------------------------
function GaussianDistribution(x, y, rho: Single): Single;{$IFDEF SUPPORTS_INLINE} inline;{$ENDIF}
var
  g: Single;
begin
  g := 1.0 / sqrt( 2.0 * D3DX_PI * rho * rho);
  g := g * exp( -(x*x + y*y)/(2*rho*rho));

  Result:= g;
end;


//--------------------------------------------------------------------------------------
// Render the help and statistics text. This function uses the ID3DXFont interface for 
// efficient text rendering.
//--------------------------------------------------------------------------------------
procedure RenderText;
var
  txtHelper: CDXUTTextHelper;
  pd3dsdBackBuffer: PD3DSurfaceDesc;
begin
  // The helper object simply helps keep track of text position, and color
  // and then it calls pFont->DrawText( g_pSprite, strMsg, -1, &rc, DT_NOCLIP, g_clr );
  // If NULL is passed in as the sprite object, then it will work however the 
  // pFont->DrawText() will not be batched together.  Batching calls will improves performance.
  txtHelper:= CDXUTTextHelper.Create(g_pFont, g_pTextSprite, 15);

  // Output statistics
  txtHelper._Begin;
  txtHelper.SetInsertionPos(5, 5);
  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 0.0, 1.0));
  txtHelper.DrawTextLine(DXUTGetFrameStats);
  txtHelper.DrawTextLine(DXUTGetDeviceStats);

  txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
  txtHelper.DrawFormattedTextLine('Glare type: %s', [g_GlareDef.m_strGlareName]);

  if g_bUseMultiSampleFloat16 then
  begin
    txtHelper.DrawTextLine('Using MultiSample Render Target');
    txtHelper.DrawFormattedTextLine('Number of Samples: %d', [Integer(g_MaxMultiSampleType)]);
    txtHelper.DrawFormattedTextLine('Quality: %d', [g_dwMultiSampleQuality]);
  end;

  // Draw help
  if g_bShowHelp then
  begin
    pd3dsdBackBuffer := DXUTGetBackBufferSurfaceDesc;
    txtHelper.SetInsertionPos(10, pd3dsdBackBuffer.Height-15*6);
    txtHelper.SetForegroundColor(D3DXColor(1.0, 0.75, 0.0, 1.0));
    txtHelper.DrawTextLine('Controls (F1 to hide):');

    txtHelper.SetInsertionPos(40, pd3dsdBackBuffer.Height-15*5);
    txtHelper.DrawTextLine('Look: Left drag mouse'#10+
                           'Move: A,W,S,D or Arrow Keys'#10+
                           'Quit: ESC');
  end else
  begin
    txtHelper.SetForegroundColor(D3DXColor(1.0, 1.0, 1.0, 1.0));
    txtHelper.DrawTextLine('Press F1 for help');
  end;
  txtHelper._End;
  txtHelper.Free;
end;


//--------------------------------------------------------------------------------------
// Before handling window messages, DXUT passes incoming windows 
// messages to the application through this callback function. If the application sets 
// *pbNoFurtherProcessing to TRUE, then DXUT will not process this message.
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

  // Pass all remaining windows messages to camera so it can respond to user input
  g_Camera.HandleMessages(hWnd, uMsg, wParam, lParam);
end;


//--------------------------------------------------------------------------------------
// As a convenience, DXUT inspects the incoming windows messages for
// keystroke messages and decodes the message parameters to pass relevant keyboard
// messages to the application.  The framework does not remove the underlying keystroke 
// messages, which are still passed to the application's MsgProc callback.
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
// Handles the GUI events
//--------------------------------------------------------------------------------------
procedure OnGUIEvent(nEvent: LongWord; nControlID: Integer; pControl: CDXUTControl; pUserContext: Pointer); stdcall;
var
  pStatic: CDXUTStatic;
  pComboBox: CDXUTComboBox;
  pSlider: CDXUTSlider;
  pCheckBox: CDXUTCheckBox;
  strBuffer: WideString;
  iLight: Integer;
begin
  case nControlID of
    IDC_TOGGLEFULLSCREEN: DXUTToggleFullScreen;
    IDC_TOGGLEREF:        DXUTToggleREF;
    IDC_CHANGEDEVICE:     with g_SettingsDlg do Active := not Active;
    IDC_RESET:            ResetOptions;

    IDC_TONEMAP:
    begin
      pCheckBox := CDXUTCheckBox(pControl);
      g_bToneMap := pCheckBox.Checked;
    end;

    IDC_BLUESHIFT:
    begin
      pCheckBox := CDXUTCheckBox(pControl);
      g_bBlueShift := pCheckBox.Checked;
    end;

    IDC_GLARETYPE:
    begin
      pComboBox := CDXUTComboBox(pControl);
      g_eGlareType := TEGlareLibType(INT_PTR(pComboBox.GetSelectedData));
      g_GlareDef.Initialize(g_eGlareType);
    end;

    IDC_KEYVALUE:
    begin
      pSlider := CDXUTSlider(pControl);
      g_fKeyValue := pSlider.Value / 100.0;

      strBuffer := Format('Key Value: %.2f', [g_fKeyValue]);
      pStatic := g_SampleUI.GetStatic(IDC_KEYVALUE_LABEL);
      pStatic.Text := PWideChar(strBuffer);
    end;

    IDC_LIGHT0, IDC_LIGHT1:
    begin
      if (nControlID = IDC_LIGHT0) then iLight := 0 else iLight := 1;
      
      pSlider := CDXUTSlider(pControl);
      g_nLightMantissa[iLight] := 1 + pSlider.Value mod 9;
      g_nLightLogIntensity[iLight] := -4 + pSlider.Value div 9;
      RefreshLights;
    end;
  end;
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has
// entered a lost state and before IDirect3DDevice9::Reset is called. Resources created
// in the OnResetDevice callback should be released here, which generally includes all
// D3DPOOL_DEFAULT resources. See the "Lost Devices" section of the documentation for
// information about lost devices.
//--------------------------------------------------------------------------------------
procedure OnLostDevice; stdcall;
var
  i: Integer;
begin
  g_DialogResourceManager.OnLostDevice;
  g_SettingsDlg.OnLostDevice;
  if (g_pFont <> nil) then g_pFont.OnLostDevice;
  if (g_pEffect <> nil) then g_pEffect.OnLostDevice;

  SAFE_RELEASE(g_pTextSprite);

  SAFE_RELEASE(g_pWorldMesh);
  SAFE_RELEASE(g_pmeshSphere);

  SAFE_RELEASE(g_pFloatMSRT);
  SAFE_RELEASE(g_pFloatMSDS);
  SAFE_RELEASE(g_pTexScene);
  SAFE_RELEASE(g_pTexSceneScaled);
  SAFE_RELEASE(g_pTexWall);
  SAFE_RELEASE(g_pTexFloor);
  SAFE_RELEASE(g_pTexCeiling);
  SAFE_RELEASE(g_pTexPainting);
  SAFE_RELEASE(g_pTexAdaptedLuminanceCur);
  SAFE_RELEASE(g_pTexAdaptedLuminanceLast);
  SAFE_RELEASE(g_pTexBrightPass);
  SAFE_RELEASE(g_pTexBloomSource);
  SAFE_RELEASE(g_pTexStarSource);

  for i:= 0 to NUM_TONEMAP_TEXTURES - 1 do SAFE_RELEASE(g_apTexToneMap[i]);
  for i:= 0 to NUM_STAR_TEXTURES - 1    do SAFE_RELEASE(g_apTexStar[i]);
  for i:= 0 to NUM_BLOOM_TEXTURES - 1   do SAFE_RELEASE(g_apTexBloom[i]);
end;


//--------------------------------------------------------------------------------------
// This callback function will be called immediately after the Direct3D device has
// been destroyed, which generally happens as a result of application termination or
// windowed/full screen toggles. Resources created in the OnCreateDevice callback
// should be released here, which generally includes all D3DPOOL_MANAGED resources.
//--------------------------------------------------------------------------------------
procedure OnDestroyDevice; stdcall;
begin
  g_DialogResourceManager.OnDestroyDevice;
  g_SettingsDlg.OnDestroyDevice;
  SAFE_RELEASE(g_pEffect);
  SAFE_RELEASE(g_pFont);
  g_pd3dDevice:= nil;
end;



procedure CreateCustomDXUTobjects;
begin
  g_DialogResourceManager:= CDXUTDialogResourceManager.Create; // manager for shared resources of dialogs
  g_SettingsDlg:= CD3DSettingsDlg.Create; // Device settings dialog
  g_Camera:= CFirstPersonCamera.Create;
  g_HUD:= CDXUTDialog.Create;
  g_SampleUI:= CDXUTDialog.Create;

  g_GlareDef:= CGlareDef.Create;
end;

procedure DestroyCustomDXUTobjects;
begin
  FreeAndNil(g_DialogResourceManager);
  FreeAndNil(g_SettingsDlg);
  FreeAndNil(g_Camera);
  FreeAndNil(g_HUD);
  FreeAndNil(g_SampleUI);
  FreeAndNil(g_GlareDef);
end;

end.

