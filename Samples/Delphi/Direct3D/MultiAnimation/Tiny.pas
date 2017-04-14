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
 *  $Id: Tiny.pas,v 1.6 2007/02/05 22:21:10 clootie Exp $
 *----------------------------------------------------------------------------*)
//-----------------------------------------------------------------------------
// File: Tiny.h
//
// Desc: Header file for the CTiny class.  Its declaraction is found here.
//
// Copyright (c) Microsoft Corporation. All rights reserved
//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
// File: Tiny.cpp
//
// Desc: Defines the character class, CTiny, for the MultipleAnimation sample.
//       The class does some basic things to make the character aware of
//       its surroundings, as well as implements all actions and movements.
//       CTiny shows a full-featured example of this.  These
//       classes use the MultiAnimation class library to control the
//       animations.
//
// Copyright (c) Microsoft Corporation. All rights reserved
//-----------------------------------------------------------------------------

{$I DirectX.inc}

unit Tiny;

interface

uses
  Windows, Classes,{$IFNDEF FPC} Contnrs,{$ENDIF}
  DXTypes, Direct3D9, D3DX9, DirectSound,
  DXUTcore, DXUTmisc, DXUTsound, StrSafe, MultiAnimationLib;

const
  IDLE_TRANSITION_TIME = 0.125;
  MOVE_TRANSITION_TIME = 0.25;

const
  GUID_NULL : TGUID = '{00000000-0000-0000-0000-000000000000}';
  
const
  ANIMINDEX_FAIL      = $ffffffff;
  FOOTFALLSOUND00     = 'footfall00.wav';
  FOOTFALLSOUND01     = 'footfall01.wav';

var
  g_apSoundsTiny: array[0..1] of CSound = (nil, nil);


type
  // Callback data for pass to the callback handler
  PCallbackDataTiny = ^TCallbackDataTiny;
  TCallbackDataTiny = record
    m_dwFoot: DWORD;              // Identify which foot caused the callback
    m_pvCameraPos: PD3DXVector3;  // Camera position when callback happened
    m_pvTinyPos: PD3DXVector3;    // Tiny's position when callback happened
  end;




  //-----------------------------------------------------------------------------
  // Name: class CBHandlerTiny
  // Desc: Derived from ID3DXAnimationCallbackHandler.  Callback handler for
  //       CTiny -- plays the footstep sounds
  //-----------------------------------------------------------------------------
  CBHandlerTiny = class(ID3DXAnimationCallbackHandler)
    function HandleCallback(Track: LongWord; pCallbackData: Pointer): HResult; override;
  end;


  CTiny = class;

  //-----------------------------------------------------------------------------
  // Name: TTinyList
  // Desc: Derived from TObjectList and used instead of "vector<CTiny*>" C++ template
  //-----------------------------------------------------------------------------
  TTinyList = class({$IFNDEF FPC}TObjectList{$ELSE}TList{$ENDIF})
  protected
    function GetItems(Index: Integer): CTiny;
    procedure SetItems(Index: Integer; ATiny: CTiny);
  public
    function Add(ATiny: CTiny): Integer;
    function Remove(ATiny: CTiny): Integer;
    procedure Insert(Index: Integer; ATiny: CTiny);
    property Items[Index: Integer]: CTiny read GetItems write SetItems; default;
  end;

  //-----------------------------------------------------------------------------
  // Name: class CTiny
  // Desc: This is the character class. It handles character behaviors and the
  //       the associated animations.
  //-----------------------------------------------------------------------------
  CTiny = class
  protected

    // -- data structuring
    m_pMA:              CMultiAnim;           // pointer to mesh-type-specific object
    m_dwMultiAnimIdx:   DWORD;                // index identifying which CAnimInstance this object uses
    m_pAI:              CAnimInstance;        // pointer to CAnimInstance specific to this object
    m_pv_pChars:        TTinyList;            // pointer to global array of CTiny* s
    m_pSM:              CSoundManager;        // pointer to sound management interface
    m_dwAnimIdxLoiter,                        // Indexes of various animation sets
    m_dwAnimIdxWalk,
    m_dwAnimIdxJog:     DWORD;
    m_CallbackData: array[0..1] of TCallbackDataTiny; // Data to pass to callback handler

    // operational status
    m_dTimePrev:        Double;               // global time value before last update
    m_dTimeCurrent:     Double;               // current global time value
    m_bUserControl:     Boolean;              // true == user is controling character with the keyboard
    m_bPlaySounds:      Boolean;              // true == this instance is playing sounds
    m_dwCurrentTrack:   DWORD;                // current animation track for primary animation

    // character traits
    m_fSpeed:           Single;               // character's movement speed -- in units/second
    m_fSpeedTurn:       Single;               // character's turning speed -- in radians/second

    m_pCallbackHandler:
               ID3DXAnimationCallbackHandler; // pointer to callback inteface to handle callback keys
    m_mxOrientation:    TD3DXMatrix;          // transform that gets the mesh into a common world space
    m_fPersonalRadius:  Single;               // personal space radius -- things can't get closer than this
                                              // (note that no height information is given--not necessary for this sample)
    // character status
    m_vPos:             TD3DXVector3;         // current position in the map -- in our sample, y is always == 0
    m_fFacing:          Single;               // current direction the character is facing -- in our sample, it's 2D only
    m_vPosTarget:       TD3DXVector3;         // This indicates where we are moving to
    m_fFacingTarget:    Single;               // The direction from Tiny's current position to the final destination
    m_fSpeedWalk:       Single;
    m_fSpeedJog:        Single;
    m_bIdle:            Boolean;              // set when Tiny is idling -- not turning toward a target
    m_bWaiting:         Boolean;              // set when Tiny is not idle, but cannot move
    m_dTimeIdling:      Double;               // countdown - Tiny Idles til this goes < 0
    m_dTimeWaiting:     Double;               // countdown - Tiny is waiting til this goes < 0, then picks a new target
    m_dTimeBlocked:     Double;               // countdown - Tiny must wait a small time when encountering a blocker before starting to walk again

    m_szASName: array[0..63] of Char;         // Current track's animation set name (for preserving across device reset)

  public

    constructor Create;
    destructor Destroy; override;
    function Setup(pMA: CMultiAnim; pv_pChars: TTinyList; pSM: CSoundManager; dTimeCurrent: Double): HRESULT; virtual;
    procedure Cleanup; virtual;
    function GetAnimInstance: CAnimInstance; virtual;
    procedure GetPosition(out pV: TD3DXVector3);
    procedure GetFacing(out pV: TD3DXVector3);
    procedure Animate(dTimeDelta: Double); virtual;
    function ResetTime: HRESULT; virtual;
    function AdvanceTime(dTimeDelta: Double; pvEye: PD3DXVector3): HRESULT; virtual;
    function Draw: HRESULT; virtual;
    procedure Report(v_sReport: TStrings);
    procedure SetUserControl; virtual;
    procedure SetAutoControl; virtual;
    procedure SetSounds(bSounds: Boolean); virtual;
    procedure ChooseNewLocation(out pV: TD3DXVector3); virtual;

    function RestoreDeviceObjects(pd3dDevice: IDirect3DDevice9): HRESULT;
    function InvalidateDeviceObjects: HRESULT;

    property IsUserControl: Boolean read m_bUserControl;
    
  protected  // ************ The following are not callable by the app -- internal stuff

    function IsBlockedByCharacter(const pV: TD3DXVector3): Boolean;
    function GetAnimIndex(const sString: String): DWORD;
    function AddCallbackKeysAndCompress(pAC: ID3DXAnimationController;
        pAS: ID3DXKeyframedAnimationSet; dwNumCallbackKeys: DWORD;
        aKeys: PD3DXKeyCallback; dwCompressionFlags: TD3DXCompressionFlags;
        fCompression: Single): HRESULT;
    function SetupCallbacksAndCompression: HRESULT;
    procedure SmoothLoiter;
    procedure SetNewTarget;
    function GetSpeedScale: Double;
    procedure AnimateUserControl(dTimeDelta: Double);
    procedure AnimateIdle(dTimeDelta: Double);
    procedure AnimateMoving(dTimeDelta: Double);
    procedure ComputeFacingTarget;
    procedure SetIdleState;
    procedure SetSeekingState;
    procedure SetMoveKey;
    procedure SetIdleKey(bResetPosition: Boolean);
    function IsOutOfBounds(const pV: TD3DXVector3): Boolean; virtual;
  end;


implementation

uses Math, SysUtils;

function CBHandlerTiny.HandleCallback(Track: LongWord; pCallbackData: Pointer): HResult;
var
  pCD: PCallbackDataTiny;
  vDiff: TD3DXVector3;
  fVolume: Single;
begin
  pCD := PCallbackDataTiny(pCallbackData);
  Result:= S_OK;

  // this is set to NULL if we're not playing sounds
  if (*fornow*) (pCD = nil) or (pCD.m_pvCameraPos = nil) then Exit;

  // scale volume by distance from tiny
  D3DXVec3Subtract(vDiff, pCD.m_pvCameraPos^, pCD.m_pvTinyPos^);
  fVolume := Min(D3DXVec3LengthSq(vDiff), 1.0);
  fVolume := fVolume * -3000;

  // play the sound
  if (pCD <> nil) and (g_apSoundsTiny[pCD.m_dwFoot] <> nil)
  then g_apSoundsTiny[pCD.m_dwFoot].Play(0, 0, Trunc(fVolume));
end;



//-----------------------------------------------------------------------------
// Name: TTinyList
// Desc: Derived from TObjectList and used instead of "vector<CTiny*>" C++ template
//-----------------------------------------------------------------------------

{ TTinyList }

function TTinyList.Add(ATiny: CTiny): Integer;
begin
  Result := inherited Add(ATiny);
end;

function TTinyList.GetItems(Index: Integer): CTiny;
begin
  Result := CTiny(inherited Items[Index]);
end;

procedure TTinyList.Insert(Index: Integer; ATiny: CTiny);
begin
  inherited Insert(Index, ATiny);
end;

function TTinyList.Remove(ATiny: CTiny): Integer;
begin
  Result := inherited Remove(ATiny);
end;

procedure TTinyList.SetItems(Index: Integer; ATiny: CTiny);
begin
  inherited Items[Index] := ATiny;
end;



//-----------------------------------------------------------------------------
// Name: class CTiny
// Desc: This is the character class. It handles character behaviors and the
//       the associated animations.
//-----------------------------------------------------------------------------

{ CTiny }


//-----------------------------------------------------------------------------
// Name: CTiny::CTiny
// Desc: Constructor for CTiny
//-----------------------------------------------------------------------------
constructor CTiny.Create;
begin
  m_pMA:= nil;
  m_dwMultiAnimIdx:= 0;
  m_pAI:= nil;
  m_pv_pChars:= nil;
  m_pSM:= nil;

  m_dTimePrev:= 0.0;
  m_dTimeCurrent:= 0.0;
  m_bUserControl:= False;
  m_bPlaySounds:= True;
  m_dwCurrentTrack:= 0;

  m_fSpeed:= 0.0;
  m_fSpeedTurn:= 0.0;
  m_pCallbackHandler:= nil;
  m_fPersonalRadius:= 0.0;

  m_fSpeedWalk:= 1.0 / 5.7;
  m_fSpeedJog:= 1.0 / 2.3;

  m_bIdle:= False;
  m_bWaiting:= False;
  m_dTimeIdling:= 0.0;
  m_dTimeWaiting:= 0.0;
  m_dTimeBlocked:= 0.0;

  D3DXMatrixIdentity(m_mxOrientation);

  m_fSpeedTurn := 1.3;
  m_pCallbackHandler := nil;
  m_fPersonalRadius := 0.035;

  m_szASName[0] := #0;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::~CTiny
// Desc: Destructor for CTiny
//-----------------------------------------------------------------------------
destructor CTiny.Destroy;
begin
  Cleanup();
  inherited;
end;




//-----------------------------------------------------------------------------
// Name: CTiny::Setup
// Desc: Initializes the class and readies it for animation
//-----------------------------------------------------------------------------
function CTiny.Setup(pMA: CMultiAnim; pv_pChars: TTinyList;
  pSM: CSoundManager; dTimeCurrent: Double): HRESULT;
var
  bBlocked: Boolean;
  dwAttempts: DWORD;
  sPath: array[0..MAX_PATH-1] of WideChar;
  mx: TD3DXMatrix;
  fScale: Single;
  pAC: ID3DXAnimationController;
begin
  m_pMA := pMA;
  m_pv_pChars := pv_pChars;
  m_pSM := pSM;

  m_dTimePrev := dTimeCurrent;
  m_dTimeCurrent := dTimeCurrent;

  try
    Result := m_pMA.CreateNewInstance(m_dwMultiAnimIdx);
    if FAILED(Result) then
    begin
      Result:= E_OUTOFMEMORY;
      Exit;
    end;

    m_pAI := m_pMA.GetInstance(m_dwMultiAnimIdx);

    // set initial position
    // bBlocked := True;
    // for( dwAttempts = 0; dwAttempts < 1000 && bBlocked; ++ dwAttempts )
    for dwAttempts := 0 to 1000-1 do
    begin
      ChooseNewLocation(m_vPos);
      bBlocked := IsBlockedByCharacter(m_vPos);
      if not bBlocked then Break;
    end;

    m_fFacing := 0.0;

    // set up anim indices
    m_dwAnimIdxLoiter := GetAnimIndex('Loiter');
    m_dwAnimIdxWalk := GetAnimIndex('Walk');
    m_dwAnimIdxJog := GetAnimIndex('Jog');
    if (m_dwAnimIdxLoiter = ANIMINDEX_FAIL) or
       (m_dwAnimIdxWalk = ANIMINDEX_FAIL) or
       (m_dwAnimIdxJog = ANIMINDEX_FAIL) then
    begin
      Result:= E_FAIL;
      Exit;
    end;

    // set up callback key data
    m_CallbackData[0].m_dwFoot := 0;
    m_CallbackData[0].m_pvTinyPos := @m_vPos;
    m_CallbackData[1].m_dwFoot := 1;
    m_CallbackData[1].m_pvTinyPos := @m_vPos;

    // set up footstep callbacks
    SetupCallbacksAndCompression;
    m_pCallbackHandler := CBHandlerTiny.Create;

    // set up footstep sounds
    if (g_apSoundsTiny[0] = nil) then
    begin
      Result := DXUTFindDXSDKMediaFile(sPath, MAX_PATH, FOOTFALLSOUND00);
      if FAILED(Result) then
        StringCchCopy(sPath, MAX_PATH, FOOTFALLSOUND00);

      Result := m_pSM.Create(g_apSoundsTiny[0], sPath, DSBCAPS_CTRLVOLUME, GUID_NULL);
      if FAILED(Result) then
      begin
        OutputDebugString(FOOTFALLSOUND00 + ' not found; continuing without sound.'#10);
        m_bPlaySounds := False;
      end;
    end;

    if (g_apSoundsTiny[1] = nil) then
    begin
      Result := DXUTFindDXSDKMediaFile(sPath, MAX_PATH, FOOTFALLSOUND01);
      if FAILED(Result) then
        StringCchCopy(sPath, MAX_PATH, FOOTFALLSOUND01);

      Result := m_pSM.Create(g_apSoundsTiny[1], sPath, DSBCAPS_CTRLVOLUME, GUID_NULL);
      if FAILED(Result) then
      begin
        OutputDebugString(FOOTFALLSOUND01 + ' not found; continuing without sound.'#10);
        m_bPlaySounds := False;
      end;
    end;

    // compute reorientation matrix based on default orientation and bounding radius
    fScale := 1.0 / m_pMA.GetBoundingRadius / 7.0;
    D3DXMatrixScaling(mx, fScale, fScale, fScale);
    m_mxOrientation := mx;
    D3DXMatrixRotationX(mx, -D3DX_PI / 2.0);
    D3DXMatrixMultiply(m_mxOrientation, m_mxOrientation, mx);
    D3DXMatrixRotationY(mx, D3DX_PI / 2.0);
    D3DXMatrixMultiply(m_mxOrientation, m_mxOrientation, mx);

    // set starting target
    SetSeekingState;
    ComputeFacingTarget;

    m_pAI.GetAnimController(pAC);
    pAC.AdvanceTime(m_dTimeCurrent, nil);
    pAC:= nil;

    // Add this instance to the list
    pv_pChars.Add(Self);
  except
    Result:= E_OUTOFMEMORY;
    Exit;
  end;

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::Cleanup()
// Desc: Performs cleanup tasks for CTiny
//-----------------------------------------------------------------------------
procedure CTiny.Cleanup;
begin
  FreeAndNil(m_pCallbackHandler);
end;


//-----------------------------------------------------------------------------
// Name: CTiny::GetAnimInstance()
// Desc: Returns the CAnimInstance object that this instance of CTiny
//       embeds.
//-----------------------------------------------------------------------------
function CTiny.GetAnimInstance: CAnimInstance;
begin
  Result:= m_pAI;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::GetPosition()
// Desc: Returns the position of this instance.
//-----------------------------------------------------------------------------
procedure CTiny.GetPosition(out pV: TD3DXVector3);
begin
  pV := m_vPos;
end;




//-----------------------------------------------------------------------------
// Name: CTiny::GetFacing()
// Desc: Returns a unit vector representing the direction this CTiny
//       instance is facing.
//-----------------------------------------------------------------------------
procedure CTiny.GetFacing(out pV: TD3DXVector3);
var
  m: TD3DXMatrix;
begin
  pV := D3DXVector3(1.0, 0.0, 0.0);
  D3DXVec3TransformCoord(pV, pV, D3DXMatrixRotationY(m, -m_fFacing)^);
end;


//-----------------------------------------------------------------------------
// Name: CTiny::Animate()
// Desc: Advances the local time by dTimeDelta. Determine an action for Tiny,
//       then update the animation controller's tracks to reflect the action.
//-----------------------------------------------------------------------------
procedure CTiny.Animate(dTimeDelta: Double);
var
  mxWorld, mx: TD3DXMatrix;
begin
  // adjust position and facing based on movement mode
  if (m_bUserControl) then
    AnimateUserControl(dTimeDelta)  // user-controlled
  else if (m_bIdle) then
    AnimateIdle(dTimeDelta)         // idling - not turning toward
  else
    AnimateMoving(dTimeDelta);      // moving or waiting - turning toward

  // loop the loiter animation back on itself to avoid the end-to-end jerk
  SmoothLoiter;

  // compute world matrix based on pos/face
  D3DXMatrixRotationY(mxWorld, -m_fFacing);
  D3DXMatrixTranslation(mx, m_vPos.x, m_vPos.y, m_vPos.z);
  D3DXMatrixMultiply(mxWorld, mxWorld, mx);
  D3DXMatrixMultiply(mxWorld, m_mxOrientation, mxWorld);
  m_pAI.SetWorldTransform(mxWorld);
end;


//-----------------------------------------------------------------------------
// Name: CTiny::ResetTime()
// Desc: Resets the local time for this CTiny instance.
//-----------------------------------------------------------------------------
function CTiny.ResetTime: HRESULT;
begin
  m_dTimePrev := 0.0;
  m_dTimeCurrent := 0.0;
  Result:= m_pAI.ResetTime;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::AdvanceTime()
// Desc: Advances the local animation time by dTimeDelta, and call
//       CAnimInstance to set up its frames to reflect the time advancement.
//-----------------------------------------------------------------------------
function CTiny.AdvanceTime(dTimeDelta: Double; pvEye: PD3DXVector3): HRESULT;
begin
  // if we're playing sounds, set the sound source position
  if m_bPlaySounds then
  begin
    m_CallbackData[ 0 ].m_pvCameraPos := pvEye;
    m_CallbackData[ 1 ].m_pvCameraPos := pvEye;
  end
  else    // else, set it to null to let the handler know to be quiet
  begin
    m_CallbackData[ 0 ].m_pvCameraPos := nil;
    m_CallbackData[ 1 ].m_pvCameraPos := nil;
  end;

  m_dTimePrev := m_dTimeCurrent;
  m_dTimeCurrent := m_dTimeCurrent + dTimeDelta;
  Result:= m_pAI.AdvanceTime(dTimeDelta, m_pCallbackHandler);
end;


//-----------------------------------------------------------------------------
// Name: CTiny::Draw()
// Desc: Renders this CTiny instace using the current animation frames.
//-----------------------------------------------------------------------------
function CTiny.Draw: HRESULT;
begin
  Result:= m_pAI.Draw;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::Report()
// Desc: Add to the vector of strings, v_sReport, with useful information
//       about this instance of CTiny.
//-----------------------------------------------------------------------------
procedure CTiny.Report(v_sReport: TStrings);
var
  s: array[0..255] of Char;
  pAC: ID3DXAnimationController;
  pAS: ID3DXAnimationSet;
  td: TD3DXTrackDesc;
begin
  try
    StrFmt(s, 'Pos: %f, %f', [m_vPos.x, m_vPos.z]);
    v_sReport.Add(s);
    StrFmt(s, 'Facing: %f', [m_fFacing]);
    v_sReport.Add(s);
    StrFmt(s, 'Local time: %f', [m_dTimeCurrent]);
    v_sReport.Add(s);
    StrFmt(s, 'Pos Target: %f, %f', [m_vPosTarget.x, m_vPosTarget.z]);
    v_sReport.Add(s);
    StrFmt(s, 'Facing Target: %f', [m_fFacingTarget]);
    v_sReport.Add(s);
    StrFmt(s, 'Status: %s', [IfThen(m_bIdle, 'Idle', IfThen(m_bWaiting, 'Waiting', 'Moving'))]);
    v_sReport.Add(s);

    // report track data
    m_pAI.GetAnimController(pAC);

    pAC.GetTrackAnimationSet(0, pAS);
    StrFmt(s, 'Track 0: %s%s', [pAS.GetName, IfThen(m_dwCurrentTrack = 0, ' (current)', '')]);
    v_sReport.Add(s);
    pAS:= nil;

    pAC.GetTrackDesc(0, @td);
    StrFmt(s, '  Weight: %f', [td.Weight]);
    v_sReport.Add(s);
    StrFmt(s, '  Speed: %f', [td.Speed]);
    v_sReport.Add(s);
    StrFmt(s, '  Position: %f', [td.Position]);
    v_sReport.Add(s);
    StrFmt(s, '  Enable: %s', [IfThen(td.Enable, 'true', 'false')]);
    v_sReport.Add(s);

    pAC.GetTrackAnimationSet(1, pAS);
    StrFmt(s, 'Track 1: %s%s', [pAS.GetName, IfThen(m_dwCurrentTrack = 1, ' (current)', '')]);
    v_sReport.Add(s);
    pAS:= nil;

    pAC.GetTrackDesc(1, @td); //todo: "GetTrackDesc( ... out xxx: Txxx)"
    StrFmt(s, '  Weight: %f', [td.Weight]);
    v_sReport.Add(s);
    StrFmt(s, '  Speed: %f', [td.Speed]);
    v_sReport.Add(s);
    StrFmt(s, '  Position: %f', [td.Position]);
    v_sReport.Add(s);
    StrFmt(s, '  Enable: %s', [IfThen(td.Enable, 'true', 'false')]);
    v_sReport.Add(s);

    if (m_bUserControl)
      then v_sReport.Add('Control: USER')
      else v_sReport.Add('Control: AUTO');

    pAC:= nil;
  except
  end;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::SetUserControl()
// Desc: Specifies that this instance of CTiny is controlled by the user.
//-----------------------------------------------------------------------------
procedure CTiny.SetUserControl;
begin
  m_bUserControl := True;
end;


//-----------------------------------------------------------------------------
// Specifies that this instance of CTiny is controlled by the application.
procedure CTiny.SetAutoControl;
begin
  if m_bUserControl then
  begin
    m_bUserControl := False;
    SetSeekingState;
  end;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::SetSounds()
// Desc: Enables or disables the sound support for this instance of CTiny.
//       In this case, whether we hear the footstep sound or not.
//-----------------------------------------------------------------------------
procedure CTiny.SetSounds(bSounds: Boolean);
begin
  m_bPlaySounds := bSounds;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::ChooseNewLocation()
// Desc: Determine a new location for this character to move to.  In this case
//       we simply randomly pick a spot on the floor as the new location.
//-----------------------------------------------------------------------------
procedure CTiny.ChooseNewLocation(out pV: TD3DXVector3);
begin
  pV.x := Random; // (float) ( rand % 256 ) / 256.f;
  pV.y := 0.0;
  pV.z := Random; // (float) ( rand % 256 ) / 256.f;
end;




//-----------------------------------------------------------------------------
// Name: CTiny::IsBlockedByCharacter()
// Desc: Goes through the character list nad returns true if this instance is
//       blocked by any other such that it cannot move, or false otherwise.
//-----------------------------------------------------------------------------
function CTiny.IsBlockedByCharacter(const pV: TD3DXVector3): Boolean;
var
  i: Integer;
  pChar: CTiny;
  vSub: TD3DXVector3;
  fRadiiSq: Single;
begin
  // move through each character to see if it blocks this
  for i:= 0 to m_pv_pChars.Count - 1 do
  begin
    pChar := m_pv_pChars[i];
    if (pChar = Self) then Continue;  // don't test against ourselves

    D3DXVec3Subtract(vSub, pChar.m_vPos, pV);
    fRadiiSq := pChar.m_fPersonalRadius + m_fPersonalRadius;
    fRadiiSq := fRadiiSq * fRadiiSq;

    // test distance
    if (D3DXVec3LengthSq(vSub) < fRadiiSq) then
    begin
      Result:= true;
      Exit;
    end;
  end;

  Result:= False;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::IsOutOfBounds()
// Desc: Checks this instance against its bounds.  Returns true if it has moved
//       outside the boundaries, or false if not.  In this case, we check if
//       x and z are within the required range (0 to 1).
//-----------------------------------------------------------------------------
function CTiny.IsOutOfBounds(const pV: TD3DXVector3): Boolean;
begin
  Result:= (pV.x < 0.0) or (pV.x > 1.0) or (pV.z < 0.0) or (pV.z > 1.0);
end;


//-----------------------------------------------------------------------------
// Name: CTiny::GetAnimIndex()
// Desc: Returns the index of an animation set within this animation instance's
//       animation controller given an animation set name.
//-----------------------------------------------------------------------------
function CTiny.GetAnimIndex(const sString: String): DWORD;
var
  hr: HRESULT;
  pAC: ID3DXAnimationController;
  pAS: ID3DXAnimationSet;
  dwRet: DWORD;
  i: Integer;
begin
  dwRet := ANIMINDEX_FAIL;

  m_pAI.GetAnimController(pAC);

  for i := 0 to pAC.GetNumAnimationSets - 1 do
  begin
    hr := pAC.GetAnimationSet(i, pAS);
    if FAILED(hr) then Continue;

    if (pAS.GetName <> nil) and
       (StrLComp(pAS.GetName, PAnsiChar(sString), min(StrLen(pAS.GetName), Length(sString)))=0) then
    begin
      dwRet := i;
      pAS:= nil;
      Break;
    end;

    pAS:= nil;
  end;

  pAC:= nil;

  Result:= dwRet;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::AddCallbackKeysAndCompress()
// Desc: Replaces an animation set in the animation controller with the
//       compressed version and callback keys added to it.
//-----------------------------------------------------------------------------
function CTiny.AddCallbackKeysAndCompress(pAC: ID3DXAnimationController;
  pAS: ID3DXKeyframedAnimationSet; dwNumCallbackKeys: DWORD;
  aKeys: PD3DXKeyCallback; dwCompressionFlags: TD3DXCompressionFlags;
  fCompression: Single): HRESULT;
var
  pASNew: ID3DXCompressedAnimationSet;
  pBufCompressed: ID3DXBuffer;
begin
  Result := pAS.Compress(DWORD(dwCompressionFlags), fCompression, nil, pBufCompressed);
  if FAILED(Result) then Exit;

  Result := D3DXCreateCompressedAnimationSet(pAS.GetName,
                                             pAS.GetSourceTicksPerSecond,
                                             pAS.GetPlaybackType,
                                             pBufCompressed,
                                             dwNumCallbackKeys,
                                             aKeys,
                                             pASNew);
  pBufCompressed:= nil;

  if FAILED(Result) then Exit;

  pAC.UnregisterAnimationSet(pAS);
  pAS:= nil;

  Result := pAC.RegisterAnimationSet(pASNew);
  if FAILED(Result) then Exit;

  pASNew := nil;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::SetupCallbacksAndCompression()
// Desc: Add callback keys to the walking and jogging animation sets in the
//       animation controller for playing footstepping sound.  Then compress
//       all animation sets in the animation controller.
//-----------------------------------------------------------------------------
function CTiny.SetupCallbacksAndCompression: HRESULT;
var
  pAC: ID3DXAnimationController;
  pASLoiter, pASWalk, pASJog: ID3DXKeyframedAnimationSet;
  aKeysWalk: array[0..1] of TD3DXKeyCallback;
  aKeysJog: array[0..7] of TD3DXKeyCallback;
  i: Integer;
begin
  m_pAI.GetAnimController(pAC);
  pAC.GetAnimationSet(m_dwAnimIdxLoiter, ID3DXAnimationSet(pASLoiter));
  pAC.GetAnimationSet(m_dwAnimIdxWalk, ID3DXAnimationSet(pASWalk));
  pAC.GetAnimationSet(m_dwAnimIdxJog, ID3DXAnimationSet(pASJog));

  aKeysWalk[ 0 ].Time := 0;
  aKeysWalk[ 0 ].pCallbackData := @m_CallbackData[ 0 ];
  aKeysWalk[ 1 ].Time := pASWalk.GetPeriod / 2.0 * pASWalk.GetSourceTicksPerSecond;
  aKeysWalk[ 1 ].pCallbackData := @m_CallbackData[ 1 ];

  for i := 0 to 7 do
  begin
    aKeysJog[ i ].Time := pASJog.GetPeriod / 8 * i * pASWalk.GetSourceTicksPerSecond;
    aKeysJog[ i ].pCallbackData := @m_CallbackData[ ( i + 1 ) mod 2 ];
  end;

  AddCallbackKeysAndCompress(pAC, pASLoiter, 0, nil, D3DXCOMPRESS_DEFAULT, 0.8);
  AddCallbackKeysAndCompress(pAC, pASWalk, 2, @aKeysWalk, D3DXCOMPRESS_DEFAULT, 0.4);
  AddCallbackKeysAndCompress(pAC, pASJog, 8, @aKeysJog, D3DXCOMPRESS_DEFAULT, 0.25);

  m_dwAnimIdxLoiter := GetAnimIndex('Loiter');
  m_dwAnimIdxWalk := GetAnimIndex('Walk');
  m_dwAnimIdxJog := GetAnimIndex('Jog');
  if (m_dwAnimIdxLoiter = ANIMINDEX_FAIL) or
     (m_dwAnimIdxWalk = ANIMINDEX_FAIL) or
     (m_dwAnimIdxJog = ANIMINDEX_FAIL) then
  begin
    Result:= E_FAIL;
    Exit;
  end;

  pAC:= nil;

  Result:= S_OK;
end;




//-----------------------------------------------------------------------------
// Name: CTiny::SmoothLoiter()
// Desc: If Tiny is loitering, check if we have reached the end of animation.
//       If so, set up a new track to play Loiter animation from the start and
//       smoothly transition to the track, so that Tiny can loiter more.
//-----------------------------------------------------------------------------
procedure CTiny.SmoothLoiter;
var
  pAC: ID3DXAnimationController;
  pASTrack, pASLoiter: ID3DXAnimationSet;
  td: TD3DXTrackDesc;
begin
  m_pAI.GetAnimController(pAC);

  // check if we're loitering
  pAC.GetTrackAnimationSet(m_dwCurrentTrack, pASTrack);
  pAC.GetAnimationSet(m_dwAnimIdxLoiter, pASLoiter);
  if (pASTrack <> nil) and (pASTrack = pASLoiter) then
  begin
    pAC.GetTrackDesc(m_dwCurrentTrack, @td);
    if (td.Position > pASTrack.GetPeriod - IDLE_TRANSITION_TIME) // come within the change delta of the end
    then SetIdleKey(True);
  end;

  SAFE_RELEASE(pASTrack);
  SAFE_RELEASE(pASLoiter);
  SAFE_RELEASE(pAC);
end;


//-----------------------------------------------------------------------------
// Name: CTiny::SetNewTarget()
// Desc: This only applies when Tiny is under automatic movement control.  If
//       this instnace of Tiny is blocked by either the edge of another
//       instance of Tiny, find a new location to walk to.
//-----------------------------------------------------------------------------
procedure CTiny.SetNewTarget;
var
  bBlocked: Boolean;
  dwAttempts: DWORD;
begin
  // get new position
  // bBlocked := True;
  // for( dwAttempts = 0; dwAttempts < 1000 && bBlocked; ++ dwAttempts )
  for dwAttempts := 0 to 999 do
  begin
    ChooseNewLocation(m_vPosTarget);
    bBlocked := IsBlockedByCharacter(m_vPosTarget);
    if not bBlocked then Break;
  end;

  ComputeFacingTarget;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::GetSpeedScale()
// Desc: Returns the speed of the current track.
//-----------------------------------------------------------------------------
function CTiny.GetSpeedScale: Double;
var
  pAC: ID3DXAnimationController;
  td: TD3DXTrackDesc;
begin
  if m_bIdle then
    Result:= 1.0
  else
  begin
    m_pAI.GetAnimController(pAC);
    pAC.GetTrackDesc(m_dwCurrentTrack, @td);
    pAC:= nil;

    Result:= td.Speed;
  end;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::AnimateUserControl()
// Desc: Reads user input and update Tiny's state and animation accordingly.
//-----------------------------------------------------------------------------
procedure CTiny.AnimateUserControl(dTimeDelta: Double);
var
  bCanMove: Boolean;
  vMovePos: TD3DXVector3;
begin
  // use keyboard controls to make Tiny move

  if (GetKeyState(Ord('V')) < 0) then
  begin
    m_bUserControl := False;
    SetSeekingState;
    Exit;
  end;

  if (GetKeyState(Ord('W')) < 0) then
  begin
    bCanMove := True;

    if (GetAsyncKeyState(VK_SHIFT) < 0) then
    begin
      if (m_fSpeed = m_fSpeedWalk) then
      begin
        m_fSpeed := m_fSpeedJog;
        m_bIdle := True;  // Set idle to true so that we can reset the movement animation below
      end;
    end else
    begin
      if (m_fSpeed = m_fSpeedJog) then
      begin
        m_fSpeed := m_fSpeedWalk;
        m_bIdle := True;  // Set idle to true so that we can reset the movement animation below
      end;
    end;

    GetFacing(vMovePos);
    D3DXVec3Scale(vMovePos, vMovePos, m_fSpeed * GetSpeedScale * dTimeDelta);
    D3DXVec3Add(vMovePos, vMovePos, m_vPos);

    // is our step ahead going to take us out of bounds?
    if IsOutOfBounds(vMovePos) then bCanMove := False;

    // are we stepping on someone else?
    if IsBlockedByCharacter(vMovePos) then bCanMove := False;

    if bCanMove then m_vPos := vMovePos;
  end else
    bCanMove := False;


  if (m_bIdle and bCanMove) then
  begin
    SetMoveKey;
    m_bIdle := False;
  end;

  if (not m_bIdle and not bCanMove) then
  begin
    SetIdleKey(True);
    m_bIdle := True;
  end;

  // turn
  if (GetKeyState(Ord('A')) < 0) then
    m_fFacing := m_fFacing + m_fSpeedTurn * dTimeDelta;

  if (GetKeyState(Ord('D')) < 0) then
    m_fFacing := m_fFacing - m_fSpeedTurn * dTimeDelta;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::AnimateIdle()
// Desc: Checks if Tiny has been idle for long enough.  If so, initialize Tiny
//       to move again to a new location.
//-----------------------------------------------------------------------------
procedure CTiny.AnimateIdle(dTimeDelta: Double);
begin
  // count down the idle counters
  if (m_dTimeIdling > 0.0) then
     m_dTimeIdling := m_dTimeIdling - dTimeDelta;

  // if idle time runs out, pick a new location
  if (m_dTimeIdling <= 0.0) then SetSeekingState;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::AnimateMoving()
// Desc: Here we try to figure out if we're moving and can keep moving,
//       or if we're waiting / blocked and must keep waiting / blocked,
//       or if we have reached our destination.
//-----------------------------------------------------------------------------
procedure CTiny.AnimateMoving(dTimeDelta: Double);
var
  vMovePos: TD3DXVector3;
  vSub: TD3DXVector3;
  fDist: Single;
  dSpeedScale: Double;
  bCanMove: Boolean;
  bOrbit: Boolean;
  fFacing: Single;
  fDiff: Single;
begin
  // move, then turn

  if m_bWaiting then
  begin
    if (m_dTimeWaiting > 0.0) then
      m_dTimeWaiting := m_dTimeWaiting - dTimeDelta;

    if (m_dTimeWaiting <= 0.0) then
    begin
      SetNewTarget;
      m_dTimeWaiting := 4.0;
    end;
  end;

  // get distance from target
  D3DXVec3Subtract(vSub, m_vPos, m_vPosTarget);
  fDist := D3DXVec3LengthSq(vSub);
  dSpeedScale := GetSpeedScale;

  if (m_dTimeBlocked > 0.0) then   // if we're supposed to wait, then turn only
  begin
    m_dTimeBlocked := m_dTimeBlocked - dTimeDelta;
  end
  // TODO: help next line
  else if (m_fSpeed * dSpeedScale * dTimeDelta * m_fSpeed * dSpeedScale * dTimeDelta >= fDist) then
  begin
    // we're within reach; set the exact point
    m_vPos := m_vPosTarget;
    SetIdleState;
  end else
  begin
    // moving forward
    GetFacing(vMovePos);
    D3DXVec3Scale(vMovePos, vMovePos, m_fSpeed * dSpeedScale * dTimeDelta);
    D3DXVec3Add(vMovePos, vMovePos, m_vPos);

    bCanMove := True;
    bOrbit := False;

    // is our step ahead going to take us out of bounds?
    if IsOutOfBounds(vMovePos) then bCanMove := False;

    // are we stepping on someone else?
    if IsBlockedByCharacter(vMovePos) then bCanMove := False;

    // are we orbiting our target?
    if (m_fFacing <> m_fFacingTarget) and
       (fDist <= ( (m_fSpeed * m_fSpeed) / (m_fSpeedTurn * m_fSpeedTurn) )) then
    begin
      bOrbit := True;
      bCanMove := False;
    end;

    // set keys if we have to
    if (bCanMove and m_bWaiting) then
    begin
      SetMoveKey;
      m_bWaiting := False;
    end;

    if not bCanMove and not m_bWaiting then
    begin
      SetIdleKey(False);
      m_bWaiting := True;
      if not bOrbit then m_dTimeBlocked := 1.0;
    end;

    if bCanMove then m_vPos := vMovePos;
  end;

  // turning
  if (m_fFacingTarget <> m_fFacing) then
  begin
    fFacing := m_fFacingTarget;
    if (m_fFacingTarget > m_fFacing) then fFacing := fFacing - 2 * D3DX_PI;

    fDiff := m_fFacing - fFacing;
    if (fDiff < D3DX_PI) then      // cw turn
    begin
      // if we're overturning
      if (m_fFacing - m_fSpeedTurn * dTimeDelta <= fFacing)
      then m_fFacing := m_fFacingTarget
      else m_fFacing := m_fFacing - m_fSpeedTurn * dTimeDelta;
    end else                       // ccw turn
    begin
      // if we're overturning
      if (m_fFacing + m_fSpeedTurn * dTimeDelta - 2 * D3DX_PI >= fFacing)
      then m_fFacing := m_fFacingTarget
      else m_fFacing := m_fFacing + m_fSpeedTurn * dTimeDelta;
    end;

    ComputeFacingTarget;
  end;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::ComputeFacingTarget()
// Desc: Computes the direction in forms of both an angle and a vector that
//       Tiny is facing.
//-----------------------------------------------------------------------------
procedure CTiny.ComputeFacingTarget;
var
  vDiff: TD3DXVector3;
begin
  D3DXVec3Subtract(vDiff, m_vPosTarget, m_vPos);
  D3DXVec3Normalize(vDiff, vDiff);

  if (vDiff.z = 0.0) then
  begin
    if (vDiff.x > 0.0)
    then m_fFacingTarget := 0.0
    else m_fFacingTarget := D3DX_PI;
  end
  else
    if (vDiff.z > 0.0)
    then m_fFacingTarget := ArcCos(vDiff.x)
    else m_fFacingTarget := ArcCos(- vDiff.x) + D3DX_PI;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::SetIdleState()
// Desc: This only applies when Tiny is not controlled by the user.  Called
//       when Tiny has just reached a destination.  We let Tiny remain idle
//       for a period of time before a new action is taken.
//-----------------------------------------------------------------------------
procedure CTiny.SetIdleState;
begin
  m_bIdle := True;
  m_dTimeIdling := 4.0;

  SetIdleKey(False);
end;


//-----------------------------------------------------------------------------
// Name: CTiny::SetSeekingState()
// Desc: Used when the computer controls Tiny.  Find a new location to move
//       Tiny to, then set the animation controller's tracks to reflect the
//       change of action.
//-----------------------------------------------------------------------------
procedure CTiny.SetSeekingState;
begin
  m_bIdle := False;
  m_bWaiting := False;

  SetNewTarget;

  if (Random > 0.2)
  then m_fSpeed := m_fSpeedWalk
  else m_fSpeed := m_fSpeedJog;

  SetMoveKey;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::SetMoveKey()
// Desc: Initialize a new track in the animation controller for the movement
//       animation (run or walk), and set up the smooth transition from the idle
//       animation (current track) to it (new track).
//-----------------------------------------------------------------------------
procedure CTiny.SetMoveKey;
var
  dwNewTrack: DWORD;
  pAC: ID3DXAnimationController;
  pAS: ID3DXAnimationSet;
begin
  dwNewTrack := IfThen(m_dwCurrentTrack = 0, 1, 0);
  m_pAI.GetAnimController(pAC);

  if (m_fSpeed = m_fSpeedWalk)
  then pAC.GetAnimationSet(m_dwAnimIdxWalk, pAS)
  else pAC.GetAnimationSet(m_dwAnimIdxJog, pAS);

  pAC.SetTrackAnimationSet(dwNewTrack, pAS);
  pAS:= nil;

  pAC.UnkeyAllTrackEvents(m_dwCurrentTrack);
  pAC.UnkeyAllTrackEvents(dwNewTrack);

  pAC.KeyTrackEnable(m_dwCurrentTrack, False, m_dTimeCurrent + MOVE_TRANSITION_TIME);
  pAC.KeyTrackSpeed(m_dwCurrentTrack, 0.0, m_dTimeCurrent, MOVE_TRANSITION_TIME, D3DXTRANSITION_LINEAR);
  pAC.KeyTrackWeight(m_dwCurrentTrack, 0.0, m_dTimeCurrent, MOVE_TRANSITION_TIME, D3DXTRANSITION_LINEAR);
  pAC.SetTrackEnable(dwNewTrack, True);
  pAC.KeyTrackSpeed(dwNewTrack, 1.0, m_dTimeCurrent, MOVE_TRANSITION_TIME, D3DXTRANSITION_LINEAR);
  pAC.KeyTrackWeight(dwNewTrack, 1.0, m_dTimeCurrent, MOVE_TRANSITION_TIME, D3DXTRANSITION_LINEAR);

  m_dwCurrentTrack := dwNewTrack;

  pAC:= nil;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::SetIdleKey()
// Desc: Initialize a new track in the animation controller for the idle
//       (loiter ) animation, and set up the smooth transition from the
//       movement animation (current track) to it (new track).
//
//       bResetPosition controls whether we start the Loiter animation from
//       its beginning or current position.
//-----------------------------------------------------------------------------
procedure CTiny.SetIdleKey(bResetPosition: Boolean);
var
  dwNewTrack: DWORD;
  pAC: ID3DXAnimationController;
  pAS: ID3DXAnimationSet;
begin
  dwNewTrack := IfThen(m_dwCurrentTrack = 0, 1, 0);
  m_pAI.GetAnimController(pAC);

  pAC.GetAnimationSet(m_dwAnimIdxLoiter, pAS);
  pAC.SetTrackAnimationSet(dwNewTrack, pAS);
  pAS:= nil;

  pAC.UnkeyAllTrackEvents(m_dwCurrentTrack);
  pAC.UnkeyAllTrackEvents(dwNewTrack);

  pAC.KeyTrackEnable(m_dwCurrentTrack, False, m_dTimeCurrent + IDLE_TRANSITION_TIME);
  pAC.KeyTrackSpeed(m_dwCurrentTrack, 0.0, m_dTimeCurrent, IDLE_TRANSITION_TIME, D3DXTRANSITION_LINEAR);
  pAC.KeyTrackWeight(m_dwCurrentTrack, 0.0, m_dTimeCurrent, IDLE_TRANSITION_TIME, D3DXTRANSITION_LINEAR);
  pAC.SetTrackEnable(dwNewTrack, True);
  pAC.KeyTrackSpeed(dwNewTrack, 1.0, m_dTimeCurrent, IDLE_TRANSITION_TIME, D3DXTRANSITION_LINEAR);
  pAC.KeyTrackWeight(dwNewTrack, 1.0, m_dTimeCurrent, IDLE_TRANSITION_TIME, D3DXTRANSITION_LINEAR);
  if bResetPosition then pAC.SetTrackPosition(dwNewTrack, 0.0);

  m_dwCurrentTrack := dwNewTrack;

  pAC:= nil;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::RestoreDeviceObjects()
// Desc: Reinitialize necessary objects
//-----------------------------------------------------------------------------
function CTiny.RestoreDeviceObjects(pd3dDevice: IDirect3DDevice9): HRESULT;
var
  pAC: ID3DXAnimationController;
  dwActiveSet: DWORD;
  pAS: ID3DXAnimationSet;
begin
  // Compress the animation sets in the new animation controller
  SetupCallbacksAndCompression;

  m_pAI.GetAnimController(pAC);
  pAC.ResetTime;
  pAC.AdvanceTime(m_dTimeCurrent, nil);

  // Initialize current track
  if (m_szASName[0] <> #0) then
  begin
    dwActiveSet := GetAnimIndex(m_szASName);
    pAC.GetAnimationSet(dwActiveSet, pAS);
    pAC.SetTrackAnimationSet(m_dwCurrentTrack, pAS);
    SAFE_RELEASE(pAS);
  end;

  pAC.SetTrackEnable(m_dwCurrentTrack, True);
  pAC.SetTrackWeight(m_dwCurrentTrack, 1.0);
  pAC.SetTrackSpeed(m_dwCurrentTrack, 1.0);

  SAFE_RELEASE(pAC);

  // Call animate to initialize the tracks.
  Animate(0.0);

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Name: CTiny::RestoreDeviceObjects()
// Desc: Free D3D objects so that the device can be reset.
//-----------------------------------------------------------------------------
function CTiny.InvalidateDeviceObjects: HRESULT;
var
  pAC: ID3DXAnimationController;
  pAS: ID3DXAnimationSet;
begin
  // Save the current track's animation set name
  // so we can reset it again in RestoreDeviceObjects later.
  m_pAI.GetAnimController(pAC);
  if (pAC <> nil) then
  begin
    pAC.GetTrackAnimationSet(m_dwCurrentTrack, pAS);
    if (pAS <> nil) then
    begin
      if (pAS.GetName <> nil) then StringCchCopy(m_szASName, 64, pAS.GetName);
      SAFE_RELEASE(pAS);
    end;
    SAFE_RELEASE(pAC);
  end;

  Result:= S_OK;
end;

end.

