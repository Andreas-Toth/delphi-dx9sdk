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
 *  $Id: GlareDefD3D.pas,v 1.9 2007/02/05 22:21:08 clootie Exp $
 *----------------------------------------------------------------------------*)
 
{$I DirectX.inc}

unit GlareDefD3D;

interface

// File provided by Masaki Kawase
// http://www.daionet.gr.jp/~masa/rthdribl/

// GlareDefD3D.h : Define glare information
//

uses
  Windows, Direct3D9, D3DX9;

type  
  //----------------------------------------------------------
  // Star generation

  // Define each line of the star.
  PStarLine = ^TStarLine;
  TStarLine = record
    nPasses: Integer;
    fSampleLength: Single;
    fAttenuation: Single;
    fInclination: Single;
  end;


  // Simple definition of the star.
  PStarDef = ^TStarDef;
  TStarDef = record
    szStarName: PChar;
    nStarLines: Integer;
    nPasses: Integer;
    fSampleLength: Single;
    fAttenuation: Single;
    fInclination: Single;
    bRotation: Boolean;
  end;


  // Simple definition of the sunny cross filter
  PStarDef_SunnyCross = ^TStarDef_SunnyCross;
  TStarDef_SunnyCross = record
    szStarName: PChar;
    fSampleLength: Single;
    fAttenuation: Single;
    fInclination: Single;
  end;


  // Star form library
  TEStarLibType = (
    STLT_DISABLE,

    STLT_CROSS,
    STLT_CROSSFILTER,
    STLT_SNOWCROSS,
    STLT_VERTICAL,
    STLT_SUNNYCROSS // = NUM_BASESTARLIBTYPES,
//    NUM_STARLIBTYPES,
  );

const
  NUM_BASESTARLIBTYPES = STLT_VERTICAL;
  NUM_STARLIBTYPES = STLT_SUNNYCROSS;


type
  //----------------------------------------------------------
  // Star generation object
  CStarDef = class
  public
    m_strStarName: String;

    m_nStarLines: Integer;
    m_pStarLine: array of TStarLine; //// [m_nStarLines]
    m_fInclination: Single;
    m_bRotation: Boolean; //
    // Rotation is available from outside ?

  // Public method
  public
    constructor Create; overload;
    constructor Create(const src: CStarDef); overload;
    destructor Destroy; override;

    (*// CStarDef& operator =(const CStarDef& src) {
    Initialize(src) ;
    return *this ;
    }*)

    function Construct: HRESULT;
    procedure Destruct;
    procedure Release;

    function Initialize(const src: CStarDef): HRESULT; overload;

    function Initialize(eType: TEStarLibType): HRESULT; overload;

    /// Generic simple star generation
    function Initialize(const szStarName: PChar;
               nStarLines: Integer;
               nPasses: Integer;
               fSampleLength: Single;
               fAttenuation: Single;
               fInclination: Single;
               bRotation: Boolean): HRESULT; overload;

    function Initialize(const starDef: TStarDef): HRESULT; overload;

    /// Specific star generation
    //  Sunny cross filter
    function Initialize_SunnyCrossFilter(const szStarName: String = 'SunnyCross';
                      fSampleLength: Single = 1.0;
                      fAttenuation: Single = 0.88;
                      fLongAttenuation: Single = 0.95;
                      fInclination: Single = 0): HRESULT;


  // Public static method
  public
    /// Create star library
    class function InitializeStaticStarLibs: HRESULT;
    class function DeleteStaticStarLibs: HRESULT;

    /// Access to the star library
    class {const} function GetLib(dwType: TEStarLibType): CStarDef;
    class {const} function GetChromaticAberrationColor(dwID: DWORD): PD3DXColor;
  end;



  //----------------------------------------------------------
  // Glare definition

  // Glare form library
  TEGlareLibType = (
    GLT_DISABLE,

    GLT_CAMERA,
    GLT_NATURAL,
    GLT_CHEAPLENS,
    //GLT_AFTERIMAGE,
    GLT_FILTER_CROSSSCREEN,
    GLT_FILTER_CROSSSCREEN_SPECTRAL,
    GLT_FILTER_SNOWCROSS,
    GLT_FILTER_SNOWCROSS_SPECTRAL,
    GLT_FILTER_SUNNYCROSS,
    GLT_FILTER_SUNNYCROSS_SPECTRAL,
    GLT_CINECAM_VERTICALSLITS,
    GLT_CINECAM_HORIZONTALSLITS

//    GLT_USERDEF					= -1,
//    GLT_DEFAULT					= GLT_FILTER_CROSSSCREEN,
  );

const
  NUM_GLARELIBTYPES = Ord(High(TEGlareLibType)) + 1;
  GLT_DEFAULT = GLT_FILTER_CROSSSCREEN;


type
  // Simple glare definition
  PGlareDef = ^TGlareDef;
  TGlareDef = packed record
    szGlareName: PChar;
    fGlareLuminance: Single;
    fBloomLuminance: Single;
    fGhostLuminance: Single;
    fGhostDistortion: Single;
    fStarLuminance: Single;
    eStarType: TEStarLibType;
    fStarInclination: Single;
    fChromaticAberration: Single;
    fAfterimageSensitivity: Single; //
    // Current weight
    fAfterimageRatio: Single; // Af
    // Afterimage weight
    fAfterimageLuminance: Single;
  end;


  //----------------------------------------------------------
  // Glare definition

  CGlareDef = class
  public
    m_strGlareName: String;

    m_fGlareLuminance: Single; // Total glare intensity (not effect to "after image")
    m_fBloomLuminance: Single;
    m_fGhostLuminance: Single;
    m_fGhostDistortion: Single;
    m_fStarLuminance: Single;
    m_fStarInclination: Single;

    m_fChromaticAberration: Single;

    m_fAfterimageSensitivity: Single; // Current weight
    m_fAfterimageRatio: Single;  // Afterimage weight
    m_fAfterimageLuminance: Single;

    m_starDef: CStarDef;

  // Public method
  public
    constructor Create; overload;
    constructor Create(const src: CGlareDef); overload;
    destructor Destroy; override;

    (*CGlareDef& operator =(const CGlareDef& src) {
      Initialize(src) ;
      return *this ;
    }*)

    function Construct: HRESULT;
    procedure Destruct;
    procedure Release;

    function Initialize(const src: CGlareDef): HRESULT; overload;

    function Initialize(const szStarName: PChar;
               fGlareLuminance: Single;
               fBloomLuminance: Single;
               fGhostLuminance: Single;
               fGhostDistortion: Single;
               fStarLuminance: Single;
               eStarType: TEStarLibType;
               fStarInclination: Single;
               fChromaticAberration: Single;
               fAfterimageSensitivity: Single; // Current weight
               fAfterimageRatio: Single; // After Image weight
               fAfterimageLuminance: Single): HRESULT; overload;

    function Initialize(const glareDef: TGlareDef): HRESULT; overload;

    function Initialize(eType: TEGlareLibType): HRESULT; overload;

  // Public static method
  public
    /// Create glare library
    class function InitializeStaticGlareLibs: HRESULT;
    class function DeleteStaticGlareLibs: HRESULT;

    /// Access to the glare library
    class {const} function GetLib(dwType: TEGlareLibType): CGlareDef;
  end;



implementation



// File provided by Masaki Kawase 
// http://www.daionet.gr.jp/~masa/rthdribl/

// GlareDefD3D.cpp : Glare information definition
//

// var  _Rad = D3DXToRadian;

// Static star library information
var
  s_aLibStarDef: array[Low(STLT_DISABLE)..STLT_VERTICAL] of TStarDef =
  (
    // star name                    lines        passes         length               attn                 rotate                    bRotate
    (szStarName: 'Disable';     nStarLines: 0; nPasses: 0; fSampleLength: 0.0; fAttenuation: 0.00; fInclination: 0 {_Rad(00.0)}; bRotation: False), // STLT_DISABLE
    (szStarName: 'Cross';       nStarLines: 4; nPasses: 3; fSampleLength: 1.0; fAttenuation: 0.85; fInclination: 0 {_Rad(00.0)}; bRotation: True), // STLT_CROSS
    (szStarName: 'CrossFilter'; nStarLines: 4; nPasses: 3; fSampleLength: 1.0; fAttenuation: 0.95; fInclination: 0 {_Rad(00.0)}; bRotation: True), // STLT_CROSS
    (szStarName: 'snowCross';   nStarLines: 6; nPasses: 3; fSampleLength: 1.0; fAttenuation: 0.96; fInclination: 0.34 {_Rad(20.0)}; bRotation: True), // STLT_SNOWCROSS
    (szStarName: 'Vertical';    nStarLines: 2; nPasses: 3; fSampleLength: 1.0; fAttenuation: 0.96; fInclination: 0 {_Rad(00.0)}; bRotation: False) // STLT_VERTICAL
  );


// Static glare library information
var
  s_aLibGlareDef: array[TEGlareLibType] of TGlareDef =
  (
   // glare     name       glare   bloom   ghost   distort  star   star type
   //  rotate   C.A   current  after  ai lum
   (szGlareName: 'Disable'; fGlareLuminance: 0.0; fBloomLuminance: 0.0; fGhostLuminance: 0.0; fGhostDistortion: 0.01; fStarLuminance: 0.0; eStarType: STLT_DISABLE;
      fStarInclination: 0 {_Rad(0.0f)}; fChromaticAberration: 0.5; fAfterimageSensitivity: 0.00; fAfterimageRatio: 0.00; fAfterimageLuminance: 0.0), // GLT_DISABLE
   (szGlareName: 'Camera'; fGlareLuminance: 1.5; fBloomLuminance: 1.2; fGhostLuminance: 1.0; fGhostDistortion: 0.0; fStarLuminance: 1.0; eStarType: STLT_CROSS;
      fStarInclination: 0 {_Rad(0.0f)}; fChromaticAberration: 0.5; fAfterimageSensitivity: 0.25; fAfterimageRatio: 0.90; fAfterimageLuminance: 1.0), // GLT_CAMERA
   (szGlareName: 'Natural Bloom'; fGlareLuminance: 1.5; fBloomLuminance: 1.2; fGhostLuminance: 0.0; fGhostDistortion: 0.0; fStarLuminance: 0.0; eStarType: STLT_DISABLE;
      fStarInclination: 0 {_Rad(0.0f)}; fChromaticAberration: 0.0; fAfterimageSensitivity: 0.40; fAfterimageRatio: 0.85; fAfterimageLuminance: 0.5), // GLT_NATURAL
   (szGlareName: 'Cheap Lens Camera'; fGlareLuminance: 1.25; fBloomLuminance: 2.0; fGhostLuminance: 1.5; fGhostDistortion: 0.05; fStarLuminance: 2.0; eStarType: STLT_CROSS;
      fStarInclination: 0 {_Rad(0.0f)}; fChromaticAberration: 0.5; fAfterimageSensitivity: 0.18; fAfterimageRatio: 0.95; fAfterimageLuminance: 1.0), // GLT_CHEAPLENS
  (*
     {	TEXT("Afterimage"),				        1.5f,	1.2f,	0.5f,	0.00f,	0.7f,	STLT_CROSS,
     _Rad(00.0f),	0.5f,	0.1f,	0.98f,	2.0f,  },	// GLT_AFTERIMAGE
  *)
   (szGlareName: 'Cross Screen Filter'; fGlareLuminance: 1.0; fBloomLuminance: 2.0; fGhostLuminance: 1.7; fGhostDistortion: 0.00; fStarLuminance: 1.5; eStarType: STLT_CROSSFILTER;
      fStarInclination: 0.43 {_Rad(25.0f)}; fChromaticAberration: 0.5; fAfterimageSensitivity: 0.20; fAfterimageRatio: 0.93; fAfterimageLuminance: 1.0), // GLT_FILTER_CROSSSCREEN
   (szGlareName: 'Spectral Cross Filter'; fGlareLuminance: 1.0; fBloomLuminance: 2.0; fGhostLuminance: 1.7; fGhostDistortion: 0.00; fStarLuminance: 1.8; eStarType: STLT_CROSSFILTER;
      fStarInclination: 1.22 {_Rad(70.0f)}; fChromaticAberration: 1.5; fAfterimageSensitivity: 0.20; fAfterimageRatio: 0.93; fAfterimageLuminance: 1.0), // GLT_FILTER_CROSSSCREEN_SPECTRAL
   (szGlareName: 'Snow Cross Filter'; fGlareLuminance: 1.0; fBloomLuminance: 2.0; fGhostLuminance: 1.7; fGhostDistortion: 0.00; fStarLuminance: 1.5; eStarType: STLT_SNOWCROSS;
      fStarInclination: 0.17 {_Rad(10.0f)}; fChromaticAberration: 1.0; fAfterimageSensitivity: 0.20; fAfterimageRatio: 0.93; fAfterimageLuminance: 1.0), // GLT_FILTER_SNOWCROSS
   (szGlareName: 'Spectral Snow Cross'; fGlareLuminance: 1.0; fBloomLuminance: 2.0; fGhostLuminance: 1.7; fGhostDistortion: 0.00; fStarLuminance: 1.8; eStarType: STLT_SNOWCROSS;
      fStarInclination: 0.70 {_Rad(40.0f)}; fChromaticAberration: 1.5; fAfterimageSensitivity: 0.20; fAfterimageRatio: 0.93; fAfterimageLuminance: 1.0), // GLT_FILTER_SNOWCROSS_SPECTRAL
   (szGlareName: 'Sunny Cross Filter'; fGlareLuminance: 1.0; fBloomLuminance: 2.0; fGhostLuminance: 1.7; fGhostDistortion: 0.00; fStarLuminance: 1.5; eStarType: STLT_SUNNYCROSS;
      fStarInclination: 0.00 {_Rad(00.0f)}; fChromaticAberration: 0.5; fAfterimageSensitivity: 0.20; fAfterimageRatio: 0.93; fAfterimageLuminance: 1.0), // GLT_FILTER_SUNNYCROSS
   (szGlareName: 'Spectral Sunny Cross'; fGlareLuminance: 1.0; fBloomLuminance: 2.0; fGhostLuminance: 1.7; fGhostDistortion: 0.00; fStarLuminance: 1.8; eStarType: STLT_SUNNYCROSS;
      fStarInclination: 0.78 {_Rad(45.0f)}; fChromaticAberration: 1.5; fAfterimageSensitivity: 0.20; fAfterimageRatio: 0.93; fAfterimageLuminance: 1.0), // GLT_FILTER_SUNNYCROSS_SPECTRAL
   (szGlareName: 'Cine Camera Vertical Slits'; fGlareLuminance: 1.0; fBloomLuminance: 2.0; fGhostLuminance: 1.5; fGhostDistortion: 0.00; fStarLuminance: 1.0; eStarType: STLT_VERTICAL;
      fStarInclination: 1.57 {_Rad(90.0f)}; fChromaticAberration: 0.5; fAfterimageSensitivity: 0.20; fAfterimageRatio: 0.93; fAfterimageLuminance: 1.0), // GLT_CINECAM_VERTICALSLIT
   (szGlareName: 'Cine Camera Horizontal Slits'; fGlareLuminance: 1.0; fBloomLuminance: 2.0; fGhostLuminance: 1.5; fGhostDistortion: 0.00; fStarLuminance: 1.0; eStarType: STLT_VERTICAL;
      fStarInclination: 0.00 {_Rad(00.0f)}; fChromaticAberration: 0.5; fAfterimageSensitivity: 0.20; fAfterimageRatio: 0.93; fAfterimageLuminance: 1.0) // GLT_CINECAM_HORIZONTALSLIT
  );


var
  //----------------------------------------------------------
  // Information object for star generation
  ms_pStarLib: array [TEStarLibType] of CStarDef {= ()};
  ms_avChromaticAberrationColor: array[0..7] of TD3DXColor;

  // Static library
  ms_pGlareLib: array [TEGlareLibType] of CGlareDef {= ()};

  

{ CStarDef }

constructor CStarDef.Create;
begin
  Construct;
end;

constructor CStarDef.Create(const src: CStarDef);
begin
  Construct;
  Initialize(src);
end;

destructor CStarDef.Destroy;
begin
  Destruct;
  inherited;
end;

function CStarDef.Construct: HRESULT;
begin
{ // not needed in Delphi
  m_strStarName := '';

  m_nStarLines:= 0;
  m_pStarLine:= nil;
  m_fInclination:= 0.0; }

  m_bRotation:= False; 
  Result:= S_OK;
end;

procedure CStarDef.Destruct;
begin
  Release;
end;

procedure CStarDef.Release;
begin
  m_pStarLine:= nil;
  m_nStarLines := 0;
end;

function CStarDef.Initialize(const src: CStarDef): HRESULT;
var
  i: Integer;
begin
  if (src = Self) then
  begin
    Result:= S_OK;
    Exit;
  end;

  // Release the data
  Release;

  // Copy the data from source
  m_strStarName := src.m_strStarName;
  m_nStarLines := src.m_nStarLines;
  m_fInclination := src.m_fInclination;
  m_bRotation := src.m_bRotation;

  try
    SetLength(m_pStarLine, m_nStarLines);
  except
    Result:= E_OUTOFMEMORY;
    Exit;
  end;

  for i := 0 to m_nStarLines - 1 do
  begin
    m_pStarLine[i] := src.m_pStarLine[i];
  end;

  Result:= S_OK;
end;


/// generic simple star generation
function CStarDef.Initialize(const szStarName: PChar; nStarLines,
  nPasses: Integer; fSampleLength, fAttenuation, fInclination: Single;
  bRotation: Boolean): HRESULT;
var
  fInc: Single;
  i: Integer;
begin
  // Release the data
  Release;

  // Copy from parameters
  m_strStarName := szStarName;
  m_nStarLines:= nStarLines;
  m_fInclination:= fInclination;
  m_bRotation:= bRotation;

  SetLength(m_pStarLine, m_nStarLines);
  try
    SetLength(m_pStarLine, m_nStarLines);
  except
    Result:= E_OUTOFMEMORY;
    Exit;
  end;

  if (m_nStarLines <> 0) then fInc := D3DXToRadian(360.0 / m_nStarLines)
  else fInc := INFINITE;

  for i := 0 to m_nStarLines - 1 do
  begin
    m_pStarLine[i].nPasses:= nPasses;
    m_pStarLine[i].fSampleLength:= fSampleLength;
    m_pStarLine[i].fAttenuation:= fAttenuation;
    m_pStarLine[i].fInclination:= fInc * i;
  end;

  Result:= S_OK;
end;

function CStarDef.Initialize(const starDef: TStarDef): HRESULT;
begin
  Result:= Initialize(starDef.szStarName,
             starDef.nStarLines,
             starDef.nPasses,
             starDef.fSampleLength,
             starDef.fAttenuation,
             starDef.fInclination,
             starDef.bRotation);
end;

function CStarDef.Initialize(eType: TEStarLibType): HRESULT;
begin
  Result:= Initialize(ms_pStarLib[eType]);
end;

/// Specific start generation
//  Sunny cross filter
function CStarDef.Initialize_SunnyCrossFilter(const szStarName: String;
  fSampleLength, fAttenuation, fLongAttenuation,
  fInclination: Single): HRESULT;
var
  fInc: Single;
  i: Integer;
begin
  // Release the data
  Release;

  // Create parameters
  m_strStarName := szStarName;
  m_nStarLines:= 8;
  m_fInclination:= fInclination;
  //	m_bRotation:= true;
  m_bRotation := False;

  try
    SetLength(m_pStarLine, m_nStarLines);
  except
    Result:= E_OUTOFMEMORY;
    Exit;
  end;

  if (m_nStarLines <> 0) then fInc := D3DXToRadian(360.0 / m_nStarLines)
  else fInc := INFINITE;

  for i := 0 to m_nStarLines - 1 do
  begin
    m_pStarLine[i].fSampleLength := fSampleLength;
    m_pStarLine[i].fInclination  := fInc * i + D3DXToRadian(0.0);

    if (0 = (i mod 2)) then
    begin
      m_pStarLine[i].nPasses  := 3;
      m_pStarLine[i].fAttenuation := fLongAttenuation; // long
    end else
    begin
      m_pStarLine[i].nPasses := 3 ;
      m_pStarLine[i].fAttenuation := fAttenuation;
    end;
  end;

  Result:= S_OK;
end;

class function CStarDef.InitializeStaticStarLibs: HRESULT;
var
  i: TEStarLibType;
  avColor: array[0..7] of TD3DXColor;
begin
  // Create basic form
  for i := Low(i) to NUM_BASESTARLIBTYPES do
  begin
    ms_pStarLib[i]:= CStarDef.Create;
    ms_pStarLib[i].Initialize(s_aLibStarDef[i]);
  end;

  // Create special form
  // Sunny cross filter
  ms_pStarLib[STLT_SUNNYCROSS]:= CStarDef.Create;
  ms_pStarLib[STLT_SUNNYCROSS].Initialize_SunnyCrossFilter;

  // Initialize color aberration table
 (* D3DXCOLOR(0.5f, 0.5f, 0.5f,  0.0f),
    D3DXCOLOR(0.3f, 0.3f, 0.8f,  0.0f),
    D3DXCOLOR(0.2f, 0.2f, 1.0f,  0.0f),
    D3DXCOLOR(0.2f, 0.4f, 0.5f,  0.0f),
    D3DXCOLOR(0.2f, 0.6f, 0.2f,  0.0f),
    D3DXCOLOR(0.5f, 0.4f, 0.2f,  0.0f),
    D3DXCOLOR(0.7f, 0.3f, 0.2f,  0.0f),
    D3DXCOLOR(1.0f, 0.2f, 0.2f,  0.0f), *)
  avColor[0]:= D3DXColor(0.5, 0.5, 0.5, 0.0); // w
  avColor[1]:= D3DXColor(0.8, 0.3, 0.3, 0.0);
  avColor[2]:= D3DXColor(1.0, 0.2, 0.2, 0.0); // r
  avColor[3]:= D3DXColor(0.5, 0.2, 0.6, 0.0);
  avColor[4]:= D3DXColor(0.2, 0.2, 1.0, 0.0); // b
  avColor[5]:= D3DXColor(0.2, 0.3, 0.7, 0.0);
  avColor[6]:= D3DXColor(0.2, 0.6, 0.2, 0.0); // g
  avColor[7]:= D3DXColor(0.3, 0.5, 0.3, 0.0);

  CopyMemory(@ms_avChromaticAberrationColor, @avColor, SizeOf(avColor));
(*ms_avChromaticAberrationColor[0] := D3DXCOLOR(0.5, 0.5, 0.5,  0.0);
  ms_avChromaticAberrationColor[1] := D3DXCOLOR(0.7f, 0.3f, 0.3f,  0.0);
  ms_avChromaticAberrationColor[2] := D3DXCOLOR(1.0, 0.2f, 0.2f,  0.0);
  ms_avChromaticAberrationColor[3] := D3DXCOLOR(0.5, 0.5, 0.5,  0.0);
  ms_avChromaticAberrationColor[4] := D3DXCOLOR(0.2f, 0.6f, 0.2f,  0.0);
  ms_avChromaticAberrationColor[5] := D3DXCOLOR(0.2f, 0.4f, 0.5,  0.0);
  ms_avChromaticAberrationColor[6] := D3DXCOLOR(0.2f, 0.3f, 0.8f,  0.0);
  ms_avChromaticAberrationColor[7] := D3DXCOLOR(0.2f, 0.2f, 1.0,  0.0);*)
  
  Result:= S_OK;
end;

class function CStarDef.DeleteStaticStarLibs: HRESULT;
var
  i: TEStarLibType;
begin
  // Delete all libraries
  for i := Low(i) to High(i) do ms_pStarLib[i].Free;;
  Result:= S_OK;
end;


class function CStarDef.GetChromaticAberrationColor(dwID: DWORD): PD3DXColor;
begin
  Result:= @ms_avChromaticAberrationColor[dwID];
end;

class function CStarDef.GetLib(dwType: TEStarLibType): CStarDef;
begin
  Result:= ms_pStarLib[dwType];
end;



{ CGlareDef }

//----------------------------------------------------------
// Glare definition

constructor CGlareDef.Create;
begin
  Construct;
end;

constructor CGlareDef.Create(const src: CGlareDef);
begin
  Construct;
  Initialize(src);
end;

destructor CGlareDef.Destroy;
begin
  Destruct;
  inherited;
end;

function CGlareDef.Construct: HRESULT;
begin
{ // Not needed in Delphi
  m_strGlareName := '';

  m_fGlareLuminance := 0.0;
  m_fBloomLuminance := 0.0;
  m_fGhostLuminance := 0.0;
  m_fStarLuminance  := 0.0;
  m_fStarInclination:= 0.0;
  m_fChromaticAberration:= 0.0;

  m_fAfterimageSensitivity:= 0.0;
  m_fAfterimageRatio:= 0.0;
  m_fAfterimageLuminance:= 0.0; }

  Result:= S_OK;
end;

procedure CGlareDef.Destruct;
begin
  m_starDef.Release;
end;

procedure CGlareDef.Release;
begin
end;

function CGlareDef.Initialize(const src: CGlareDef): HRESULT;
begin
  if (src = Self) then
  begin
    Result:= S_OK;
    Exit;
  end;

  // Release the data
  Release;

  // Copy data from source
  m_strGlareName := src.m_strGlareName;
  m_fGlareLuminance:= src.m_fGlareLuminance;

  m_fBloomLuminance:= src.m_fBloomLuminance;
  m_fGhostLuminance:= src.m_fGhostLuminance;
  m_fGhostDistortion:= src.m_fGhostDistortion;
  m_fStarLuminance:= src.m_fStarLuminance;
  m_fStarLuminance:= src.m_fStarLuminance;
  m_fStarInclination:= src.m_fStarInclination;
  m_fChromaticAberration:= src.m_fChromaticAberration;

  m_fAfterimageSensitivity:= src.m_fStarLuminance;
  m_fAfterimageRatio:= src.m_fStarLuminance;
  m_fAfterimageLuminance:= src.m_fStarLuminance;

  m_starDef:= src.m_starDef;

  Result:= S_OK ;
end;

function CGlareDef.Initialize(const szStarName: PChar; fGlareLuminance,
  fBloomLuminance, fGhostLuminance, fGhostDistortion,
  fStarLuminance: Single; eStarType: TEStarLibType; fStarInclination,
  fChromaticAberration, fAfterimageSensitivity, fAfterimageRatio,
  fAfterimageLuminance: Single): HRESULT;
begin
  // Release the data
  Release;

  // Create parameters
  m_strGlareName := szStarName;
  m_fGlareLuminance:= fGlareLuminance;

  m_fBloomLuminance:= fBloomLuminance;
  m_fGhostLuminance:= fGhostLuminance;
  m_fGhostDistortion:= fGhostDistortion;
  m_fStarLuminance:= fStarLuminance;
  m_fStarInclination:= fStarInclination;
  m_fChromaticAberration:= fChromaticAberration;

  m_fAfterimageSensitivity:= fAfterimageSensitivity;
  m_fAfterimageRatio:= fAfterimageRatio;
  m_fAfterimageLuminance:= fAfterimageLuminance;

  // Create star form data
  m_starDef := CStarDef.GetLib(eStarType);

  Result:= S_OK;
end;

function CGlareDef.Initialize(const glareDef: TGlareDef): HRESULT;
begin
  Result:= Initialize(glareDef.szGlareName,
             glareDef.fGlareLuminance,
             glareDef.fBloomLuminance,
             glareDef.fGhostLuminance,
             glareDef.fGhostDistortion,
             glareDef.fStarLuminance,
             glareDef.eStarType,
             glareDef.fStarInclination,
             glareDef.fChromaticAberration,
             glareDef.fAfterimageSensitivity,
             glareDef.fAfterimageRatio,
             glareDef.fAfterimageLuminance);
end;

function CGlareDef.Initialize(eType: TEGlareLibType): HRESULT;
begin
  Result:= Initialize(ms_pGlareLib[eType]);
end;

class function CGlareDef.InitializeStaticGlareLibs: HRESULT;
var
  i: TEGlareLibType;
begin
  CStarDef.InitializeStaticStarLibs;

  // Create glare form
  for i:= Low(i) to High(i) do
  begin
    ms_pGlareLib[i]:= CGlareDef.Create;
    ms_pGlareLib[i].Initialize(s_aLibGlareDef[i]);
  end;

  Result:= S_OK;
end;


class function CGlareDef.DeleteStaticGlareLibs: HRESULT;
var
  i: TEGlareLibType;
begin
  // Delete all libraries
  for i:= Low(i) to High(i) do ms_pGlareLib[i].Free;;
  Result:= S_OK;
end;


class function CGlareDef.GetLib(dwType: TEGlareLibType): CGlareDef;
begin
  Result:= ms_pGlareLib[dwType];
end;



initialization
  CStarDef.InitializeStaticStarLibs;
  CGlareDef.InitializeStaticGlareLibs;
finalization
  CGlareDef.DeleteStaticGlareLibs;
  CStarDef.DeleteStaticStarLibs;
end.

