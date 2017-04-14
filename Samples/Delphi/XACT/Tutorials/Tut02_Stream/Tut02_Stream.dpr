(*----------------------------------------------------------------------------*
 *  XACT tutorial from DirectX 9.0 SDK April 2006                             *
 *  Delphi adaptation by Alexey Barkovoy (e-mail: directx@clootie.ru)         *
 *                                                                            *
 *  Supported compilers: Delphi 5,6,7,9; FreePascal 2.0                       *
 *                                                                            *
 *  Latest version can be downloaded from:                                    *
 *     http://www.clootie.ru                                                  *
 *     http://sourceforge.net/projects/delphi-dx9sdk                          *
 *----------------------------------------------------------------------------*
 *  $Id: Tut02_Stream.dpr,v 1.5 2006/10/21 22:17:58 clootie Exp $
 *----------------------------------------------------------------------------*)
//-----------------------------------------------------------------------------
// File: Tut02_Stream.cpp
//
// Desc: This is the second tutorial for using the XACT API. This tutorial
//       differs from the first tutorial by loading a streaming XACT wave bank
//       and playing background music that is streamed from this wave bank.
//       It also shows how to do zero-latency streaming.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//-----------------------------------------------------------------------------

program Tut02_Stream;

{$I DirectX.inc}

uses
  Windows,
  Messages,
  ActiveX,
  SysUtils,
  StrSafe,
  ShellAPI,
  xact;

//-----------------------------------------------------------------------------
// Forward declaration
//-----------------------------------------------------------------------------
function PrepareXACT: HRESULT; forward;
procedure UpdateAudio; forward;
procedure CleanupXACT; forward;
function MsgProc(hWnd: HWND; msg: LongWord; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall; forward;
procedure XACTNotificationCallback(const pNotification: PXACT_Notification); stdcall; forward;
function FindMediaFileCch(out strDestPath: WideString; const cchDest: Integer; const strFilename: PWideChar): HRESULT; forward;
function DoesCommandLineContainAuditionSwitch: Boolean; forward;


//-----------------------------------------------------------------------------
// Struct to hold audio game state
//-----------------------------------------------------------------------------
type
  TAudioState = record
    iZap: TXACTIndex;
    iRev: TXACTIndex;
    iSong: array[0..2] of TXACTIndex;

    pEngine: IXACTEngine;
    pSoundBank: IXACTSoundBank;
    pInMemoryWaveBank: IXACTWaveBank;
    pStreamingWaveBank: IXACTWaveBank;

    pZeroLatencyRevCue: IXACTCue;

    // Handles to audio files to be closed upon cleanup
    hStreamingWaveBankFile: THandle;
    pbInMemoryWaveBank: Pointer;
    pbSoundBank: Pointer;

    cs: TRTLCriticalSection; // CRITICAL_SECTION
    bHandleStreamingWaveBankPrepared: Boolean;
    bHandleZeroLatencyCueStop: Boolean;
    bHandleSongStopped: Boolean;

    nCurSongPlaying: Integer;
  end;

var
  g_audioState: TAudioState;
  g_hWnd: HWND;


//-----------------------------------------------------------------------------------------
// This tutorial does the follow XACT related steps:
//
//      1. Prepare to use XACT
//      2. Start playing background music when the streaming wave bank is prepared
//      3. Allow XACT to do work periodically when the message pump is idle
//      4. Plays sounds using XACT upon a user event
//      5. XACT shutdown and cleanup
//
// We will look at each of these steps in detail below.
//-----------------------------------------------------------------------------------------
function WinMain: Integer; // INT WINAPI WinMain( HINSTANCE hInst, HINSTANCE, LPSTR, INT )
var
  hBrush: Windows.HBRUSH;
  wc: TWndClassEx;
  hr: HRESULT;
  bGotMsg: Boolean;
  msg: TMSG;
begin
  // Register the window class
  hBrush := CreateSolidBrush($FF0000);
  ZeroMemory(@wc, SizeOf(wc));
  wc.cbSize:= SizeOf(wc);
  wc.lpfnWndProc:= @MsgProc;
  wc.hInstance:= HInstance;
  wc.hCursor:= LoadCursor(0, IDC_ARROW);
  wc.hbrBackground:= hBrush;
  wc.lpszClassName:= 'XACTTutorial';

  RegisterClassEx(wc);

  // Create the application's window
  g_hWnd := CreateWindow('XACTTutorial', 'XACT Tutorial 2: Streaming',
                         WS_OVERLAPPED or WS_VISIBLE or WS_CAPTION or WS_SYSMENU or WS_MINIMIZEBOX,
                         Integer(CW_USEDEFAULT), Integer(CW_USEDEFAULT), 500, 400,
                         0, 0, HInstance, nil);
  SetTimer(g_hWnd, 0, 100, nil); // update the text every so often

  // Prepare to use XACT
  hr := PrepareXACT;
  if FAILED(hr) then
  begin
    if (hr = HResultFromWin32(ERROR_FILE_NOT_FOUND))
    then MessageBox(g_hWnd, 'Failed to init XACT because media not found.', 'XACT Tutorial', MB_OK)
    else MessageBox(g_hWnd, 'Failed to init XACT.', 'XACT Tutorial', MB_OK);
    CleanupXACT;
    Result:= 0;
    Exit;
  end;

  // Book keeping - no song currently playing.
  g_audioState.nCurSongPlaying := -1;

  // Enter the message loop
  msg.message := WM_NULL;

  while (WM_QUIT <> msg.message) do
  begin
    // Use PeekMessage() so we can use idle time to render the scene and call pEngine->DoWork()
    bGotMsg := PeekMessage(msg, 0, 0, 0, PM_REMOVE);

    if bGotMsg then
    begin
      // Translate and dispatch the message
      TranslateMessage(msg);
      DispatchMessage(msg);
    end else
    begin
      UpdateAudio;

      Sleep(10); // Yield CPU time to other apps.  Note that this is not normally needed when rendering
    end;
  end;

  // Clean up
  UnregisterClass('XACT Tutorial', 0);
  CleanupXACT;

  Result:= 0;
end;


//-----------------------------------------------------------------------------------------
// This function does the following steps:
//
//      1. Initialize XACT by calling pEngine->Initialize
//      2. Register for the XACT notification desired
//      3. Create the in memory XACT wave bank(s) you want to use
//      4. Create the streaming XACT wave bank(s) you want to use
//      5. Create the XACT sound bank(s) you want to use
//      6. Store indices to the XACT cue(s) your game uses
//-----------------------------------------------------------------------------------------
function PrepareXACT: HRESULT;
var
  bAuditionMode: Boolean;
  bDebugMode: Boolean;
  dwCreationFlags: DWORD;
  str: WideString;
  hFile: THandle;
  dwFileSize: DWORD;
  hMapFile: THandle;
  xrParams: TXACT_Runtime_Parameters;
  desc: TXACT_Notification_Description;
  wsParams: TXACT_Wavebank_Streaming_Parameters;
  i: Integer;
  sz: AnsiString;
begin
  // Clear struct
  ZeroMemory(@g_audioState, SizeOf(g_audioState));
  InitializeCriticalSection(g_audioState.cs);

  Result := CoInitializeEx(nil, COINIT_MULTITHREADED);  // COINIT_APARTMENTTHREADED will work too
  if SUCCEEDED(Result) then
  begin
    // Switch to auditioning mode based on command line.  Change if desired
    bAuditionMode := DoesCommandLineContainAuditionSwitch;
    bDebugMode := False;

    dwCreationFlags := 0;
    if bAuditionMode then dwCreationFlags := dwCreationFlags or XACT_FLAG_API_AUDITION_MODE;
    if bDebugMode    then dwCreationFlags := dwCreationFlags  or XACT_FLAG_API_DEBUG_MODE;

    Result := XACTCreateEngine(dwCreationFlags, g_audioState.pEngine);
  end;
  if FAILED(Result) or (g_audioState.pEngine = nil) then
  begin
    Result:= E_FAIL;
    Exit;
  end;

  // Initialize & create the XACT runtime
  ZeroMemory(@xrParams, SizeOf(xrParams));
  xrParams.lookAheadTime := 250;
  {$IFDEF FPC}
  xrParams.fnNotificationCallback := @XACTNotificationCallback;
  {$ELSE}
  xrParams.fnNotificationCallback := XACTNotificationCallback;
  {$ENDIF FPC}
  Result := g_audioState.pEngine.Initialize(xrParams);
  if FAILED(Result) then Exit;


  //-----------------------------------------------------------------------------------------
  // Register for XACT notifications
  //-----------------------------------------------------------------------------------------

  // The "wave bank prepared" notification will let the app know when it is save to use
  // play cues that reference streaming wave data.
  ZeroMemory(@desc, SizeOf(desc));
  desc.flags := XACT_FLAG_NOTIFICATION_PERSIST;
  desc.type_ := XACTNOTIFICATIONTYPE_WAVEBANKPREPARED;
  g_audioState.pEngine.RegisterNotification(desc);

  // The "cue stop" notification will let the app know when it a song stops so a new one
  // can be played
  desc.flags := XACT_FLAG_NOTIFICATION_PERSIST;
  desc.type_ := XACTNOTIFICATIONTYPE_CUESTOP;
  desc.cueIndex := XACTINDEX_INVALID;
  g_audioState.pEngine.RegisterNotification(desc);

  // The "cue prepared" notification will let the app know when it a a cue that uses
  // streaming data has been prepared so it is ready to be used for zero latency streaming
  desc.flags := XACT_FLAG_NOTIFICATION_PERSIST;
  desc.type_ := XACTNOTIFICATIONTYPE_CUEPREPARED;
  desc.cueIndex := XACTINDEX_INVALID;
  g_audioState.pEngine.RegisterNotification(desc);


  Result := FindMediaFileCch(str, MAX_PATH, 'InMemoryWaveBank.xwb');
  if FAILED(Result) then Exit;

  // Create an "in memory" XACT wave bank file using memory mapped file IO
  Result := E_FAIL; // assume failure
  hFile := CreateFileW(PWideChar(str), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
  if (hFile <> INVALID_HANDLE_VALUE) then
  begin
    dwFileSize := GetFileSize(hFile, nil);
    if (dwFileSize <> DWORD(-1)) then
    begin
      hMapFile := CreateFileMapping(hFile, nil, PAGE_READONLY, 0, dwFileSize, nil);
      if (hMapFile <> 0) then
      begin
        g_audioState.pbInMemoryWaveBank := MapViewOfFile(hMapFile, FILE_MAP_READ, 0, 0, 0);
        if (g_audioState.pbInMemoryWaveBank <> nil) then
        begin
          Result := g_audioState.pEngine.CreateInMemoryWaveBank(g_audioState.pbInMemoryWaveBank, dwFileSize, 0, 0, g_audioState.pInMemoryWaveBank);
        end;
        CloseHandle(hMapFile); // pbInMemoryWaveBank maintains a handle on the file so close this unneeded handle
      end;
    end;
    CloseHandle(hFile); // pbInMemoryWaveBank maintains a handle on the file so close this unneeded handle
  end;
  if FAILED(Result) then
  begin
    Result := E_FAIL; // CleanupXACT() will cleanup state before exiting
    Exit;
  end;

  //-----------------------------------------------------------------------------------------
  // Create a streaming XACT wave bank file.
  // Take note of the following:
  // 1) This wave bank in the XACT project file must marked as a streaming wave bank
  //    This is set inside the XACT authoring tool)
  // 2) Use FILE_FLAG_OVERLAPPED | FILE_FLAG_NO_BUFFERING flags when opening the file
  // 3) To use cues that reference this streaming wave bank, you must wait for the
  //    wave bank to prepared first or the playing the cue will fail
  //-----------------------------------------------------------------------------------------
  Result := FindMediaFileCch( str, MAX_PATH, 'StreamingWaveBank.xwb');
  if FAILED(Result) then Exit;
  Result := E_FAIL; // assume failure
  g_audioState.hStreamingWaveBankFile := CreateFileW(PWideChar(str),
                          GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING,
                          FILE_FLAG_OVERLAPPED or FILE_FLAG_NO_BUFFERING, 0);
  if (g_audioState.hStreamingWaveBankFile <> INVALID_HANDLE_VALUE) then
  begin
    ZeroMemory(@wsParams, SizeOf(wsParams));
    wsParams.file_ := g_audioState.hStreamingWaveBankFile;
    wsParams.offset := 0;

    // 64 means to allocate a 64 * 2k buffer for streaming.
    // This is a good size for DVD streaming and takes good advantage of the read ahead cache
    wsParams.packetSize := 64;

    Result := g_audioState.pEngine.CreateStreamingWaveBank(wsParams, g_audioState.pStreamingWaveBank);
  end;
  if FAILED(Result) then
  begin
    Result:= E_FAIL; // CleanupXACT() will cleanup state before exiting
    Exit;
  end;

  // Create the XACT sound bank file with using memory mapped file IO
  Result := FindMediaFileCch(str, MAX_PATH, 'sounds.xsb');
  if FAILED(Result) then Exit;
  Result := E_FAIL; // assume failure
  hFile := CreateFileW(PWideChar(str), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
  if (hFile <> INVALID_HANDLE_VALUE) then
  begin
    dwFileSize := GetFileSize(hFile, nil);
    if (dwFileSize <> DWORD(-1)) then
    begin
      hMapFile := CreateFileMapping(hFile, nil, PAGE_READONLY, 0, dwFileSize, nil);
      if (hMapFile <> 0) then
      begin
        g_audioState.pbSoundBank := MapViewOfFile(hMapFile, FILE_MAP_READ, 0, 0, 0);
        if (g_audioState.pbSoundBank <> nil) then
        begin
          Result := g_audioState.pEngine.CreateSoundBank(g_audioState.pbSoundBank, dwFileSize, 0, 0, g_audioState.pSoundBank);
        end;
        CloseHandle(hMapFile); // pbInMemoryWaveBank maintains a handle on the file so close this unneeded handle
      end;
    end;
    CloseHandle(hFile); // pbInMemoryWaveBank maintains a handle on the file so close this unneeded handle
  end;
  if FAILED(Result) then
  begin
    Result:= E_FAIL; // CleanupXACT() will cleanup state before exiting
    Exit;
  end;

  // Get the cue indices from the sound bank
  g_audioState.iZap := g_audioState.pSoundBank.GetCueIndex('zap');
  g_audioState.iRev := g_audioState.pSoundBank.GetCueIndex('rev');
  for i:=0 to 2 do
  begin
    sz:= Format('song%d', [i+1]);
    g_audioState.iSong[i] := g_audioState.pSoundBank.GetCueIndex(PAnsiChar(sz));
  end;

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------------------
// This is the callback for handling XACT notifications.  This callback can be executed on a 
// different thread than the app thread so shared data must be thread safe.  The game 
// also needs to minimize the amount of time spent in this callbacks to avoid glitching, 
// and a limited subset of XACT API can be called from inside the callback so 
// it is sometimes necessary to handle the notification outside of this callback.
//-----------------------------------------------------------------------------------------
procedure XACTNotificationCallback(const pNotification: PXACT_Notification); stdcall;
begin
  // Use the critical section properly to make shared data thread safe while avoiding deadlocks.  
  //
  // To do this follow this advice:
  // 1) Use a specific CS only to protect the specific shared data structures between the callback and the app thread.
  // 2) Don’t make any API calls while holding the CS. Use it to access the shared data, make a local copy of the data, release the CS and then make the API call.
  // 3) Spend minimal amount of time in the CS (to prevent the callback thread from waiting too long causing a glitch).   
  // 
  // Instead of using a CS, you can also use a non-blocking queues to keep track of notifications meaning 
  // callback will push never pop only push and the app thread will only pop never push

  // In this simple tutorial, we will respond to a cue stop notification for the song 
  // cues by simply playing another song but its ultimately it's up the application 
  // and sound designer to decide what to do when a notification is received. 
  if (pNotification.type_ = XACTNOTIFICATIONTYPE_CUESTOP) and
     ((pNotification.cue.cueIndex = g_audioState.iSong[0]) or
      (pNotification.cue.cueIndex = g_audioState.iSong[1])  or
      (pNotification.cue.cueIndex = g_audioState.iSong[2])) then
  begin
      // The previous background song ended, so pick and new song to play it
      EnterCriticalSection(g_audioState.cs);
      Inc(g_audioState.nCurSongPlaying);
      g_audioState.nCurSongPlaying := g_audioState.nCurSongPlaying mod 3;
      g_audioState.bHandleSongStopped := True;
      LeaveCriticalSection(g_audioState.cs);
  end;

  if (pNotification.type_ = XACTNOTIFICATIONTYPE_WAVEBANKPREPARED) and
     (pNotification.waveBank.pWaveBank = g_audioState.pStreamingWaveBank) then
  begin
    // Respond to this notification outside of this callback so Prepare() can be called
    EnterCriticalSection(g_audioState.cs);
    g_audioState.bHandleStreamingWaveBankPrepared := True;
    LeaveCriticalSection(g_audioState.cs);
  end;

  if (pNotification.type_ = XACTNOTIFICATIONTYPE_CUEPREPARED) and
     (pNotification.cue.pCue = g_audioState.pZeroLatencyRevCue) then
  begin
    // No need to handle this notification here but its 
    // done so for demonstration purposes.  This is typically useful
    // for triggering animation as soon as zero-latency audio is prepared 
    // to ensure the audio and animation are in sync
  end;

  if (pNotification.type_ = XACTNOTIFICATIONTYPE_CUESTOP) and
     (pNotification.cue.pCue = g_audioState.pZeroLatencyRevCue) then 
  begin
    // Respond to this notification outside of this callback so Prepare() can be called
    EnterCriticalSection(g_audioState.cs);
    g_audioState.bHandleZeroLatencyCueStop := True;
    LeaveCriticalSection(g_audioState.cs);
  end;
end;


//-----------------------------------------------------------------------------------------
// Handle these notifications outside of the callback and call pEngine->DoWork()
//-----------------------------------------------------------------------------------------
var
  s_szMessage: String = '';

procedure UpdateAudio;
var
  bHandleStreamingWaveBankPrepared: Boolean;
  bHandleZeroLatencyCueStop: Boolean;
begin
  // Handle these notifications outside of the callback because
  // only a subset of XACT APIs can be called inside the callback.

  // Use the critical section properly to make shared data thread safe while avoiding deadlocks.  
  //
  // To do this follow this advice:
  // 1) Use a specific CS only to protect the specific shared data structures between the callback and the app thread.
  // 2) Don’t make any API calls while holding the CS. Use it to access the shared data, make a local copy of the data, release the CS and then make the API call.
  // 3) Spend minimal amount of time in the CS (to prevent the callback thread from waiting too long causing a glitch).   
  // 
  // Instead of using a CS, you can also use a non-blocking queues to keep track of notifications meaning 
  // callback will push never pop only push and the app thread will only pop never push
    
  EnterCriticalSection(g_audioState.cs);
  bHandleStreamingWaveBankPrepared := g_audioState.bHandleStreamingWaveBankPrepared;
  bHandleZeroLatencyCueStop := g_audioState.bHandleZeroLatencyCueStop;
  LeaveCriticalSection(g_audioState.cs);

  if bHandleStreamingWaveBankPrepared then
  begin
    EnterCriticalSection(g_audioState.cs);
    g_audioState.bHandleStreamingWaveBankPrepared := False;
    LeaveCriticalSection(g_audioState.cs);

    // Starting playing background music after the streaming wave bank
    // has been prepared but no sooner.  The background music does not need to be
    // zero-latency so the cues do not need to be prepared first
    g_audioState.nCurSongPlaying := 0;
    g_audioState.pSoundBank.Play(g_audioState.iSong[g_audioState.nCurSongPlaying], 0, 0, nil);

    // Prepare a new cue for zero-latency playback now that the wave bank is prepared
    g_audioState.pSoundBank.Prepare(g_audioState.iRev, 0, 0, g_audioState.pZeroLatencyRevCue);
  end;

  if bHandleZeroLatencyCueStop then
  begin
    EnterCriticalSection(g_audioState.cs);
    g_audioState.bHandleZeroLatencyCueStop := False;
    LeaveCriticalSection(g_audioState.cs);

    // Destroy the cue when it stops
    g_audioState.pZeroLatencyRevCue.Destroy;
    g_audioState.pZeroLatencyRevCue := nil;

    // For this tutorial, we will prepare another zero-latency cue
    // after the current one stops playing, but this isn't typical done
    // Its up to the application to define its own behavior
    g_audioState.pSoundBank.Prepare(g_audioState.iRev, 0, 0, g_audioState.pZeroLatencyRevCue);
  end;

  if g_audioState.bHandleSongStopped then
  begin
    EnterCriticalSection(g_audioState.cs);
    g_audioState.bHandleSongStopped := False;
    LeaveCriticalSection(g_audioState.cs);

    g_audioState.pSoundBank.Play(g_audioState.iSong[g_audioState.nCurSongPlaying], 0, 0, nil);
  end;


  // It is important to allow XACT to do periodic work by calling pEngine->DoWork().  
  // However this must function be call often enough.  If you call it too infrequently,
  // streaming will suffer and resources will not be managed promptly.  On the other hand
  // if you call it too frequently, it will negatively affect performance. Calling it once
  // per frame is usually a good balance.
  if Assigned(g_audioState.pEngine) then g_audioState.pEngine.DoWork;
end;


//-----------------------------------------------------------------------------
// Window message handler
//-----------------------------------------------------------------------------
function MsgProc(hWnd: Windows.HWND; msg: LongWord; wParam: Windows.WPARAM; lParam: Windows.LPARAM): LRESULT; stdcall;
var
  ps: TPaintStruct;
  hDC: Windows.HDC;
  rect: TRect;
  dwState: DWORD;
  szState, sz: String;
begin
  case msg of
    WM_KEYDOWN:
    begin
      // Upon a game event, play a cue.  For this simple tutorial,
      // pressing the space bar is a game event that will play a cue
      if (wParam = VK_SPACE)
      then g_audioState.pSoundBank.Play(g_audioState.iZap, 0, 0, nil);

      // To play a zero-latency cue:
      // 1) prepare it
      // 2) wait for it to be prepared
      // 3) play it with using the cue instance returned from the Prepare() function.
      if (wParam = Ord('A')) then
      begin
        // The Play() call on a cue will only succeed if the cue is either preparing or
        // prepared meaning it can not be playing, etc.
        g_audioState.pZeroLatencyRevCue.GetState(dwState);
        if ((dwState and (XACT_CUESTATE_PREPARING or XACT_CUESTATE_PREPARED)) <> 0)
        then g_audioState.pZeroLatencyRevCue.Play;
      end;

      if (wParam = VK_ESCAPE) then PostQuitMessage(0);
    end;

    WM_TIMER:
    begin
      // Update message string every so often
      if (g_audioState.pZeroLatencyRevCue <> nil) then
      begin
        g_audioState.pZeroLatencyRevCue.GetState(dwState);
        case dwState of
          XACT_CUESTATE_CREATED:   szState := 'Created, but nothing else';
          XACT_CUESTATE_PREPARING: szState := 'Preparing to play';
          XACT_CUESTATE_PREPARED:  szState := 'Prepared, but not yet played';
          XACT_CUESTATE_PLAYING:   szState := 'Playing, but can be paused';
          XACT_CUESTATE_STOPPING:  szState := 'Stopping';
          XACT_CUESTATE_STOPPED:   szState := 'Stopped';
          XACT_CUESTATE_PAUSED:    szState := 'Paused';
        end;
      end else
      begin
        szState := 'Not created';
      end;

      EnterCriticalSection(g_audioState.cs);
      sz := Format('Press space to play an XACT cue called ''zap'' which plays'#10 +
                   'from an in-memory wave bank'#10 +
                    #10 +
                   'Press ''A'' to play a zero-latency cue when it is preparing or prepared.'#10 +
                   'When this cue stops, the tutorial releases it and prepares a new cue'#10 +
                   'Cue state: %s'#10 +
                    #10 +
                   'This tutorial is also playing background music in that is'#10 +
                   'contained in a streaming wave bank.  When the background'#10 +
                   'music stops, a new song cue is played by the tutorial.'#10 +
                   'Currently playing: Song %d',
                   [szState, g_audioState.nCurSongPlaying+1]);
      LeaveCriticalSection(g_audioState.cs);

      if (sz <> s_szMessage) then
      begin
        // Repaint the window if needed
        s_szMessage := sz;;
        InvalidateRect(g_hWnd, nil, True);
        UpdateWindow(g_hWnd);
      end;
    end;


    WM_PAINT:
    begin
      // Paint some simple explanation text
      hDC := BeginPaint(hWnd, ps);
      SetBkColor(hDC, $ff0000);
      SetTextColor(hDC, $ffFFFF);
      GetClientRect(hWnd, rect);
      rect.top := 70;
      DrawText(hDC, PAnsiChar(s_szMessage), -1, rect, DT_CENTER);
      EndPaint(hWnd, ps);
      Result:= 0;
      Exit;
    end;

    WM_DESTROY:
    begin
      PostQuitMessage(0);
    end;
  end;

  Result:= DefWindowProc(hWnd, msg, wParam, lParam);
end;


//-----------------------------------------------------------------------------
// Releases all previously initialized XACT objects
//-----------------------------------------------------------------------------
procedure CleanupXACT;
begin
  // Shutdown XACT
  //
  // Note that pEngine->ShutDown is synchronous and will take some time to complete 
  // if there are still playing cues.  Also pEngine->ShutDown() is generally only 
  // called when a game exits and is not the preferred method of changing audio 
  // resources. To know when it is safe to free wave/sound bank data without 
  // shutting down the XACT engine, use the XACTNOTIFICATIONTYPE_SOUNDBANKDESTROYED 
  // or XACTNOTIFICATIONTYPE_WAVEBANKDESTROYED notifications 
  if (g_audioState.pEngine <> nil) then
  begin
    g_audioState.pEngine.ShutDown;
    g_audioState.pEngine := nil;
  end;

  // After pEngine->ShutDown() returns, it is safe to release audio file memory
  if (g_audioState.hStreamingWaveBankFile <> INVALID_HANDLE_VALUE) and (g_audioState.hStreamingWaveBankFile <> 0)
  then CloseHandle(g_audioState.hStreamingWaveBankFile);
  if (g_audioState.pbSoundBank <> nil) then UnmapViewOfFile(g_audioState.pbSoundBank);
  if (g_audioState.pbInMemoryWaveBank <> nil) then UnmapViewOfFile(g_audioState.pbInMemoryWaveBank);

  DeleteCriticalSection(g_audioState.cs);

  CoUninitialize;
end;


function WideStrRScan(const Str: PWideChar; Chr: WideChar): PWideChar;
var
  MostRecentFound: PWideChar;
begin
{ // let's forget about this case for now...
  if Chr = #0 then
    Result := WideStrEnd(Str)
  else }
  begin
    Result := nil;

    MostRecentFound := Str;
    while True do
    begin
      while MostRecentFound^ <> Chr do
      begin
        if MostRecentFound^ = #0 then
          Exit;
        Inc(MostRecentFound);
      end;
      Result := MostRecentFound;
      Inc(MostRecentFound);
    end;
  end;
end;

//--------------------------------------------------------------------------------------
// Helper function to try to find the location of a media file
//--------------------------------------------------------------------------------------
function FindMediaFileCch(out strDestPath: WideString; const cchDest: Integer; const strFilename: PWideChar): HRESULT;
var
  bFound: Boolean;
  strExePath: array[0..MAX_PATH-1] of WideChar;
  strExeName: array[0..MAX_PATH-1] of WideChar;
  strLastSlash: PWideChar;
  strLeafName: array[0..MAX_PATH-1] of WideChar;
  strFullPath: array[0..MAX_PATH-1] of WideChar;
  strFullFileName: array[0..MAX_PATH-1] of WideChar;
  strSearch: array[0..MAX_PATH-1] of WideChar;
  strFilePart: PWideChar;
begin
  bFound := False;

  if (nil = strFilename) or (strFilename^ = #0) or (cchDest < 10) then
  begin
    Result:= E_INVALIDARG;
    Exit;
  end;

  // Get the exe name, and exe path
  GetModuleFileNameW(0, strExePath, MAX_PATH);
  strExePath[MAX_PATH-1]:= #0;
  strLastSlash := WideStrRScan(strExePath, '\');
  if (strLastSlash <> nil) then
  begin
    StringCchCopy(strExeName, MAX_PATH, @strLastSlash[1]);

    // Chop the exe name from the exe path
    strLastSlash^ := #0;

    // Chop the .exe from the exe name
    strLastSlash := WideStrRScan(strExeName, '.');
    if (strLastSlash <> nil) then strLastSlash^ := #0;
  end;

  // SetLength(strDestPath, lstrlenW(strFilename));
  // StringCchCopy(@strDestPath[1], cchDest, strFilename);
  strDestPath:= strFilename;

  if (GetFileAttributesW(PWideChar(strDestPath)) <> $FFFFFFFF) then
  begin
    Result:= 1{iTrue};
    Exit;
  end;

  // Search all parent directories starting at .\ and using strFilename as the leaf name
  StringCchCopy(strLeafName, MAX_PATH, strFilename);

  strFilePart := nil;

  GetFullPathNameW('.', MAX_PATH, strFullPath, strFilePart);
  if (strFilePart = nil) then
  begin
    Result:= 0{False};
    Exit;
  end;

  while (strFilePart <> nil) and (strFilePart^ <> #0) do
  begin
    StringCchFormat(strFullFileName, MAX_PATH, '%s\%s', [strFullPath, strLeafName]);
    if (GetFileAttributesW(strFullFileName) <> $FFFFFFFF) then
    begin
      strDestPath := strFullFileName;
      bFound := True;
      Break;
    end;

    StringCchFormat(strFullFileName, MAX_PATH, '%s\Tutorials\%s\%s', [strFullPath, strExeName, strLeafName]);
    if (GetFileAttributesW(strFullFileName) <> $FFFFFFFF) then
    begin
      strDestPath := strDestPath + strFullFileName;
      bFound := True;
      Break;
    end;

    StringCchFormat(strSearch, MAX_PATH, '%s\..', [strFullPath]);
    GetFullPathNameW(strSearch, MAX_PATH, strFullPath, strFilePart);
  end;

  if bFound then
  begin
    Result:= S_OK;
    Exit;
  end;

  // On failure, return the file as the path but also return an error code
  strDestPath := strFilename;

  Result:= HResultFromWin32(ERROR_FILE_NOT_FOUND);
end;

//--------------------------------------------------------------------------------------
function DoesCommandLineContainAuditionSwitch: Boolean;
const
  strAuditioning = WideString('-audition');
type
  PWideCharArray = ^TWideCharArray;
  TWideCharArray = array[0..1000] of PWideChar;
var
  nArgLen: size_t;
  nNumArgs: Integer;
  pstrArgList: PWideCharArray;
  iArg: Integer;
begin
  Result:= True;
  {$IFDEF FPC}
  pstrArgList := PWideCharArray(CommandLineToArgvW(GetCommandLineW, @nNumArgs));
  {$ELSE}
  pstrArgList := PWideCharArray(CommandLineToArgvW(GetCommandLineW, nNumArgs));
  {$ENDIF FPC}
  for iArg:= 1 to nNumArgs - 1 do
  begin
    StringCchLength(pstrArgList^[iArg], 256, nArgLen);
    if (lstrcmpiW(pstrArgList^[iArg], strAuditioning{, nArgLen}) = 0) and (nArgLen = 9)
    then Exit;
  end;
  Result:= False;
end;


begin
  ExitCode:= WinMain;
end.

