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
 *  $Id: Tut03_Variable.dpr,v 1.4 2006/04/23 19:40:19 clootie Exp $
 *----------------------------------------------------------------------------*)
//-----------------------------------------------------------------------------
// File: Tut03_Variable.cpp
//
// Desc: This is the third tutorial for using the XACT API. This tutorial
//       shows how to use categories and XACT variables.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//----------------------------- ------------------------------------------------

program Tut03_Variable;

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
procedure CleanupXACT; forward;
function MsgProc(hWnd: HWND; msg: LongWord; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall; forward;
function FindMediaFileCch(out strDestPath: WideString; const cchDest: Integer; const strFilename: PWideChar): HRESULT; forward;
function DoesCommandLineContainAuditionSwitch: Boolean; forward;


//-----------------------------------------------------------------------------
// Struct to hold audio game state
//-----------------------------------------------------------------------------
type
  TAudioState = record
    iZap: TXACTIndex;
    iEngine: TXACTIndex;
    iSong: TXACTIndex;

    iMusicCategory: TXACTCategory;
    iGlobalCategory: TXACTCategory;
    iRPMVariable: TXACTVariableIndex;
    nRPM: TXACTVariableValue;

    bMusicPaused: Boolean;
    fMusicVolume: Single;

    bGlobalPaused: Boolean;
    fGlobalVolume: Single;

    pEngine: IXACTEngine;
    pSoundBank: IXACTSoundBank;
    pWaveBank: IXACTWaveBank;
    pMusicCue: IXACTCue;

    // Handles to audio files to be closed upon cleanup
    pbWaveBank: Pointer;
    pbSoundBank: Pointer;
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
  {wc = { sizeof(WNDCLASSEX), 0, MsgProc, 0L, 0L, hInst, NULL,
                    LoadCursor(NULL, IDC_ARROW), hBrush,
                    NULL, L"XACTTutorial", NULL };
  ZeroMemory(@wc, SizeOf(wc));
  wc.cbSize:= SizeOf(wc);
  wc.lpfnWndProc:= @MsgProc;
  wc.hInstance:= HInstance;
  wc.hCursor:= LoadCursor(0, IDC_ARROW);
  wc.hbrBackground:= hBrush;
  wc.lpszClassName:= 'XACTTutorial';

  RegisterClassEx(wc);

  // Create the application's window
  g_hWnd := CreateWindow('XACTTutorial', 'XACT Tutorial 3: Variable',
                         WS_OVERLAPPED or WS_VISIBLE or WS_CAPTION or WS_SYSMENU or WS_MINIMIZEBOX,
                         Integer(CW_USEDEFAULT), Integer(CW_USEDEFAULT), 500, 400,
                         0, 0, HInstance, nil);
  SetTimer(g_hWnd, 0, 100, nil); // repaint every so often -- just to avoid manually triggering when to repaint

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

  // Enter the message loop
  msg.message := WM_NULL;

  while (WM_QUIT <> msg.message) do
  begin
    // Use PeekMessage() so we can use idle time to render the scene and call XACTDoWork()
    bGotMsg := PeekMessage(msg, 0, 0, 0, PM_REMOVE);

    if bGotMsg then
    begin
      // Translate and dispatch the message
      TranslateMessage(msg);
      DispatchMessage(msg);
    end else
    begin
      //-----------------------------------------------------------------------------------------
      // It is important to allow XACT to do periodic work by calling XACTDoWork().
      // However this must function be call often enough.  If you call it too infrequently,
      // streaming will suffer and resources will not be managed promptly.  On the other hand
      // if you call it too frequently, it will negatively affect performance. Calling it once
      // per frame is usually a good balance.
      //
      // In this tutorial since there is no 3D rendering taking place, we just call this while
      // idle and sleep afterward to yield CPU time
      //-----------------------------------------------------------------------------------------
      if Assigned(g_audioState.pEngine) then g_audioState.pEngine.DoWork;
      Sleep(10); // Yield CPU time to other apps.  Note that this is not normally needed when rendering
    end;
  end;

  // Clean up
  UnregisterClass('XACT Tutorial', 0);
  CleanupXACT;

  Result:= 0;
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
  // TODO: handle any notification needed here.  Make sure global data is thread safe
end;


//-----------------------------------------------------------------------------------------
// This function does the following steps:
//
//      1. Initialize XACT by calling pEngine->Initialize 
//      2. Create the XACT wave bank(s) you want to use
//      3. Create the XACT sound bank(s) you want to use
//      4. Store indices to the XACT cue(s) your game uses
//      5. Store indices to the XACT categories your game uses
//      6. Plays the back ground music that is stored in a in-memory wave bank
//-----------------------------------------------------------------------------------------
function PrepareXACT: HRESULT;
{$IFDEF FPC}
const INVALID_FILE_SIZE = DWORD($FFFFFFFF);
{$ENDIF}
var
  bAuditionMode: Boolean;
  bDebugMode: Boolean;
  dwCreationFlags: DWORD;
  str: WideString;
  hFile: THandle;
  dwFileSize: DWORD;
  dwBytesRead: DWORD;
  hMapFile: THandle;
  xrParams: TXACT_Runtime_Parameters;
  pGlobalSettingsData: Pointer;
  dwGlobalSettingsFileSize: DWORD;
  bSuccess: Boolean;
begin
  // Clear struct
  ZeroMemory(@g_audioState, SizeOf(g_audioState));
  g_audioState.fGlobalVolume := 1.0;
  g_audioState.fMusicVolume := 0.3;
  g_audioState.nRPM := 1000.0;

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

  // Load the global settings file and pass it into XACTInitialize
  pGlobalSettingsData := nil;
  dwGlobalSettingsFileSize := 0;
  bSuccess := False;
  Result := FindMediaFileCch(str, MAX_PATH, 'Tut03_Variable.xgs');
  if SUCCEEDED(Result) then
  begin
    hFile := CreateFileW(PWideChar(str), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
    if (hFile <> 0) then
    begin
      dwGlobalSettingsFileSize := GetFileSize(hFile, nil);
      if (dwGlobalSettingsFileSize <> INVALID_FILE_SIZE) then
      begin
        pGlobalSettingsData := CoTaskMemAlloc(dwGlobalSettingsFileSize);
        if (pGlobalSettingsData <> nil) then
        begin
          if ReadFile(hFile, pGlobalSettingsData^, dwGlobalSettingsFileSize, dwBytesRead, nil) then
          begin
            bSuccess := True;
          end;
        end;
      end;
      CloseHandle(hFile);
    end;
  end;
  if not bSuccess then
  begin
    if (pGlobalSettingsData <> nil) then CoTaskMemFree(pGlobalSettingsData);
    pGlobalSettingsData := nil;
    dwGlobalSettingsFileSize := 0;
  end;

  // Initialize & create the XACT runtime
  ZeroMemory(@xrParams, SizeOf(xrParams));
  xrParams.pGlobalSettingsBuffer := pGlobalSettingsData;
  xrParams.globalSettingsBufferSize := dwGlobalSettingsFileSize;
  xrParams.globalSettingsFlags := XACT_FLAG_GLOBAL_SETTINGS_MANAGEDATA; // this will tell XACT to delete[] the buffer when its unneeded
  xrParams.fnNotificationCallback := XACTNotificationCallback;
  xrParams.lookAheadTime := 250;
  Result := g_audioState.pEngine.Initialize(xrParams);
  if FAILED(Result) then Exit;

  Result := FindMediaFileCch(str, MAX_PATH, 'Sounds.xwb');
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
        g_audioState.pbWaveBank := MapViewOfFile(hMapFile, FILE_MAP_READ, 0, 0, 0);
        if (g_audioState.pbWaveBank <> nil) then
        begin
          Result := g_audioState.pEngine.CreateInMemoryWaveBank(g_audioState.pbWaveBank, dwFileSize, 0, 0, g_audioState.pWaveBank);
        end;
        CloseHandle(hMapFile); // pbWaveBank maintains a handle on the file so close this unneeded handle
      end;
    end;
    CloseHandle(hFile); // pbWaveBank maintains a handle on the file so close this unneeded handle
  end;
  if FAILED(Result) then
  begin
    Result := E_FAIL; // CleanupXACT() will cleanup state before exiting
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
        CloseHandle(hMapFile); // pbWaveBank maintains a handle on the file so close this unneeded handle
      end;
    end;
    CloseHandle(hFile); // pbWaveBank maintains a handle on the file so close this unneeded handle
  end;
  if FAILED(Result) then
  begin
    Result:= E_FAIL; // CleanupXACT() will cleanup state before exiting
    Exit;
  end;

  // Get the cue indices from the sound bank
  g_audioState.iZap := g_audioState.pSoundBank.GetCueIndex('zap');
  g_audioState.iEngine := g_audioState.pSoundBank.GetCueIndex('engine');
  g_audioState.iSong := g_audioState.pSoundBank.GetCueIndex('song1');

  // Get indices to XACT categories
  g_audioState.iMusicCategory := g_audioState.pEngine.GetCategory('Music');
  g_audioState.iGlobalCategory := g_audioState.pEngine.GetCategory('Global');

  // Get indices to XACT variables
  g_audioState.iRPMVariable := g_audioState.pEngine.GetGlobalVariableIndex('RPM');

  // Start playing the background music since it is in a in-memory wave bank
  g_audioState.pSoundBank.Play(g_audioState.iSong, 0, 0, nil);
  g_audioState.pSoundBank.Play(g_audioState.iEngine, 0, 0, nil);

  Result:= S_OK;
end;

const
  VK_OEM_PLUS       = $BB;   // '+' any country
  VK_OEM_COMMA      = $BC;   // ',' any country
  VK_OEM_MINUS      = $BD;   // '-' any country


//-----------------------------------------------------------------------------
// Window message handler
//-----------------------------------------------------------------------------
var
  s_szMessage: String = '';
  
function MsgProc(hWnd: Windows.HWND; msg: LongWord; wParam: Windows.WPARAM; lParam: Windows.LPARAM): LRESULT; stdcall;
var
  ps: TPaintStruct;
  hDC: Windows.HDC;
  rect: TRect;
  sz: String;
begin
  case msg of
    WM_KEYDOWN:
    if Assigned(g_audioState.pEngine) then
    begin
      // Upon a game event, play a cue.  For this simple tutorial,
      // pressing the space bar is a game event that will play a cue
      if (wParam = VK_SPACE)
      then g_audioState.pSoundBank.Play(g_audioState.iZap, 0, 0, nil);

      // Pause or unpause the category upon keypress
      if (wParam = Ord('M')) then
      begin
        g_audioState.bMusicPaused := not g_audioState.bMusicPaused;
        g_audioState.pEngine.Pause(g_audioState.iMusicCategory, g_audioState.bMusicPaused);
      end;
      if (wParam = Ord('P')) then
      begin
        g_audioState.bGlobalPaused := not g_audioState.bGlobalPaused;

        // When you unpause or pause a category, all child categories are also paused/unpaused.
        // All categories are a child of the "Global" category
        g_audioState.bMusicPaused := g_audioState.bGlobalPaused;

        g_audioState.pEngine.Pause(g_audioState.iGlobalCategory, g_audioState.bGlobalPaused);
      end;

      // Adjust the volume of the category
      if (wParam = Ord('J')) then
      begin
        g_audioState.fMusicVolume := g_audioState.fMusicVolume - 0.05;
        if (g_audioState.fMusicVolume < 0.0) then g_audioState.fMusicVolume := 0.0;
        g_audioState.pEngine.SetVolume(g_audioState.iMusicCategory, g_audioState.fMusicVolume);
      end;
      if (wParam = Ord('K')) then
      begin
        g_audioState.fMusicVolume := g_audioState.fMusicVolume + 0.05;
        if (g_audioState.fMusicVolume > 1.0) then  g_audioState.fMusicVolume := 1.0;
        g_audioState.pEngine.SetVolume(g_audioState.iMusicCategory, g_audioState.fMusicVolume);
      end;
      if (wParam = VK_OEM_MINUS) then
      begin
        g_audioState.fGlobalVolume := g_audioState.fGlobalVolume - 0.05;
        if (g_audioState.fGlobalVolume < 0.0) then g_audioState.fGlobalVolume := 0.0;
        g_audioState.pEngine.SetVolume(g_audioState.iGlobalCategory, g_audioState.fGlobalVolume);
      end;
      if (wParam = VK_OEM_PLUS) then
      begin
        g_audioState.fGlobalVolume := g_audioState.fGlobalVolume + 0.05;
        if (g_audioState.fGlobalVolume > 1.0) then g_audioState.fGlobalVolume := 1.0;
        g_audioState.pEngine.SetVolume(g_audioState.iGlobalCategory, g_audioState.fGlobalVolume);
      end;

      // Adjust the XACT variable based on some change
      if (wParam = Ord('Q')) then
      begin
        g_audioState.nRPM := g_audioState.nRPM - 500.0;
        if (g_audioState.nRPM < 500.0) then g_audioState.nRPM := 500.0;
        g_audioState.pEngine.SetGlobalVariable(g_audioState.iRPMVariable, g_audioState.nRPM);
      end;
      if (wParam = Ord('W')) then
      begin
        g_audioState.nRPM := g_audioState.nRPM + 500.0;
        if (g_audioState.nRPM > 8000.0) then g_audioState.nRPM := 8000.0;
        g_audioState.pEngine.SetGlobalVariable(g_audioState.iRPMVariable, g_audioState.nRPM);
      end;

      if (wParam = VK_ESCAPE) then PostQuitMessage(0);
    end;

    WM_TIMER:
    begin
      sz := Format('Press ''-'' and ''+'' to adjust the global volume level'#10 +
                   'Press ''P'' to pause the globally pause the sound'#10 +
                   'Global volume: %0.1f%%, paused: %d'#10 +
                    #10 +
                   'Press ''J'' and ''K'' to adjust the background music volume level'#10 +
                   'Press ''M'' to pause the background music'#10 +
                   'Background music volume: %0.1f%%, paused: %d'#10 +
                    #10 +
                   'Press space to play an XACT cue called ''zap'' which plays'#10 +
                   'from an in-memory wave bank'#10 +
                    #10 +
                   'Press ''Q'' and ''W'' to change the values of a custom global variable'#10 +
                   'called ''RPM''. This variable is linked to an XACT RPC that is set to'#10 +
                   'alter the pitch of the engine sound based on a ramp.'#10 +
                   'RPM: %0.1f'#10,
                    [g_audioState.fGlobalVolume * 100.0, Integer(g_audioState.bGlobalPaused),
                     g_audioState.fMusicVolume * 100.0, Integer(g_audioState.bMusicPaused),
                     g_audioState.nRPM]);

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
      SetBkColor(hDC, $FF0000);
      SetTextColor(hDC, $FFFFFF);
      GetClientRect(hWnd, rect);
      rect.top := 30;
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
  if (g_audioState.pEngine <> nil) then
  begin
    g_audioState.pEngine.ShutDown;
    g_audioState.pEngine := nil;
  end;

  // After XACTShutDown() returns, it is safe to release audio file memory
  if (g_audioState.pbSoundBank <> nil) then UnmapViewOfFile(g_audioState.pbSoundBank);
  if (g_audioState.pbWaveBank <> nil) then UnmapViewOfFile(g_audioState.pbWaveBank);

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
    StringCchLength(pstrArgList[iArg], 256, nArgLen);
    if (lstrcmpiW(pstrArgList[iArg], strAuditioning{, nArgLen}) = 0) and (nArgLen = 9)
    then Exit;
  end;
  Result:= False;
end;


begin
  ExitCode:= WinMain;
end.

