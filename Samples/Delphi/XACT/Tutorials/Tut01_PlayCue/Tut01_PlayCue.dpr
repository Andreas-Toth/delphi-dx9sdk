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
 *  $Id: Tut01_PlayCue.dpr,v 1.4 2006/04/23 19:40:19 clootie Exp $
 *----------------------------------------------------------------------------*)
//-----------------------------------------------------------------------------
// File: Tut01_PlayCue.cpp
//
// Desc: This is the first tutorial for using the XACT API. This tutorial loads
//       an XACT wave bank and sound bank and plays a cue named "zap" when
//       the space bar is pressed.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
//-----------------------------------------------------------------------------

program Tut01_PlayCue;

{$IFDEF FPC}
{$mode objfpc}
{$ENDIF}

uses
  Windows,
  Messages,
  ActiveX,
  StrSafe,
  ShellAPI,
  xact;

//-----------------------------------------------------------------------------
// Forward declaration
//-----------------------------------------------------------------------------
function PrepareXACT: HRESULT; forward;
function MsgProc(hWnd: HWND; msg: LongWord; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall; forward;
procedure CleanupXACT; forward;
function FindMediaFileCch(out strDestPath: WideString; const cchDest: Integer; const strFilename: PWideChar): HRESULT; forward;
function DoesCommandLineContainAuditionSwitch: Boolean; forward;


//-----------------------------------------------------------------------------
// Struct to hold audio game state
//-----------------------------------------------------------------------------
type
  TAudioState = record
    pEngine: IXACTEngine;
    pWaveBank: IXACTWaveBank;
    pSoundBank: IXACTSoundBank;
    iZap: TXACTINDEX;

    // Handles to memory mapped files.  Call UnmapViewOfFile() upon cleanup to release file
    pbWaveBank: Pointer;
    pbSoundBank: Pointer;
  end;

var
  g_audioState: TAudioState;


//-----------------------------------------------------------------------------------------
// This tutorial does the follow XACT related steps: 
//
//      1. Prepare to use XACT
//      2. Allow XACT to do work periodically when the message pump is idle
//      3. Plays sounds using XACT upon a user event
//      4. XACT shutdown and cleanup 
//
// We will look at each of these steps in detail below.
//-----------------------------------------------------------------------------------------
function WinMain: Integer; // INT WINAPI WinMain( HINSTANCE hInst, HINSTANCE, LPSTR, INT )
var
  hBrush: Windows.HBRUSH;
  wc: TWndClassEx;
  hWnd: Windows.HWND;
  hr: HRESULT;
  bGotMsg: Boolean;
  msg: TMSG;
begin
  // Register the window class
  hBrush := CreateSolidBrush($ff0000);
  ZeroMemory(@wc, SizeOf(wc));
  wc.cbSize:= SizeOf(wc);
  wc.lpfnWndProc:= @MsgProc;
  wc.hInstance:= HInstance;
  wc.hCursor:= LoadCursor(0, IDC_ARROW);
  wc.hbrBackground:= hBrush;
  wc.lpszClassName:= 'XACTTutorial'; 

  RegisterClassEx(wc);

  // Create the application's window
  hWnd := CreateWindow('XACTTutorial', 'XACT Tutorial 1: PlayCue',
                       WS_OVERLAPPED or WS_VISIBLE or WS_CAPTION or WS_SYSMENU or WS_MINIMIZEBOX,
                       Integer(CW_USEDEFAULT), Integer(CW_USEDEFAULT), 400, 400,
                       0, 0, HInstance, nil);

  // Prepare to use XACT
  hr := PrepareXACT;
  if FAILED(hr) then
  begin
    if (hr = HResultFromWin32(ERROR_FILE_NOT_FOUND))
    then MessageBox(hWnd, 'Failed to init XACT because media not found.', 'XACT Tutorial', MB_OK)
    else MessageBox(hWnd, 'Failed to init XACT.', 'XACT Tutorial', MB_OK);
    CleanupXACT;
    Result:= 0;
    Exit;
  end;

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
      //-----------------------------------------------------------------------------------------
      // It is important to allow XACT to do periodic work by calling pEngine->DoWork().
      // However this must function be call often enough.  If you call it too infrequently,
      // streaming will suffer and resources will not be managed promptly.  On the other hand
      // if you call it too frequently, it will negatively affect performance. Calling it once
      // per frame is usually a good balance.
      //
      // In this tutorial since there is no 3D rendering taking place, we just call this while
      // idle and sleep afterward to yield CPU time
      //-----------------------------------------------------------------------------------------
      if (g_audioState.pEngine <> nil) then g_audioState.pEngine.DoWork;
      Sleep(10);  // Yield CPU time to other apps.  Note that this is typically not needed when rendering
    end;
  end;

  // Clean up
  UnregisterClass('XACT Tutorial', 0);
  CleanupXACT;

  Result:= 0;
end;


//-----------------------------------------------------------------------------------------
// This function does the following:
//
//      1. Initialize XACT by calling pEngine->Initialize
//      2. Create the XACT wave bank(s) you want to use
//      3. Create the XACT sound bank(s) you want to use
//      4. Store indices to the XACT cue(s) your game uses
//-----------------------------------------------------------------------------------------
function PrepareXACT: HRESULT;
var
  bAuditionMode: Boolean;
  bDebugMode: Boolean;
  dwCreationFlags: DWORD;
  hr: HRESULT;
  str: WideString;
  hFile: THandle;
  dwFileSize: DWORD;
  hMapFile: THandle;
  xrParams: TXACT_Runtime_Parameters;
begin
  // Clear struct
  ZeroMemory(@g_audioState, SizeOf(g_audioState));

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
  Result := g_audioState.pEngine.Initialize(xrParams);
  if FAILED(Result) then Exit;

  Result := FindMediaFileCch(str, MAX_PATH, 'sounds.xwb');
  if FAILED(Result) then Exit;

  // Create an "in memory" XACT wave bank file using memory mapped file IO
  // Memory mapped files tend to be the fastest for most situations assuming you
  // have enough virtual address space for a full map of the file
  hr := E_FAIL; // assume failure
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
          hr := g_audioState.pEngine.CreateInMemoryWaveBank(g_audioState.pbWaveBank, dwFileSize, 0, 0, g_audioState.pWaveBank);
        end;
        CloseHandle(hMapFile); // pbWaveBank maintains a handle on the file so close this unneeded handle
      end;
    end;
    CloseHandle(hFile); // pbWaveBank maintains a handle on the file so close this unneeded handle
  end;
  if FAILED(hr) then
  begin
    Result:= E_FAIL; // CleanupXACT() will cleanup state before exiting
    Exit;
  end;

  // Create the XACT sound bank file with using memory mapped file IO
  // Memory mapped files tend to be the fastest for most situations assuming you
  // have enough virtual address space for a full map of the file
  Result := FindMediaFileCch(str, MAX_PATH, 'sounds.xsb');
  if FAILED(Result) then Exit;
  hr := E_FAIL; // assume failure
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
          hr := g_audioState.pEngine.CreateSoundBank(g_audioState.pbSoundBank, dwFileSize, 0, 0, g_audioState.pSoundBank);
        end;
        CloseHandle(hMapFile); // pbWaveBank maintains a handle on the file so close this unneeded handle
      end;
    end;
    CloseHandle(hFile); // pbWaveBank maintains a handle on the file so close this unneeded handle
  end;
  if FAILED(hr) then
  begin
    Result:= E_FAIL; // CleanupXACT() will cleanup state before exiting
    Exit;
  end;

  // Get the sound cue index from the sound bank
  //
  // Note that if the cue does not exist in the sound bank, the index will be XACTINDEX_INVALID
  // however this is ok especially during development.  The Play or Prepare call will just fail.
  g_audioState.iZap := g_audioState.pSoundBank.GetCueIndex('zap');

  Result:= S_OK;
end;


//-----------------------------------------------------------------------------
// Window message handler
//-----------------------------------------------------------------------------
function MsgProc(hWnd: Windows.HWND; msg: LongWord; wParam: Windows.WPARAM; lParam: Windows.LPARAM): LRESULT; stdcall;
var
  ps: TPaintStruct;
  hDC: Windows.HDC;
  rect: TRect;
begin
  case msg of
    WM_KEYDOWN:
    begin
      // Upon a game event, play a cue.  For this simple tutorial,
      // pressing the space bar is a game event that will play a cue
      if (wParam = VK_SPACE) then g_audioState.pSoundBank.Play(g_audioState.iZap, 0, 0, nil);

      if (wParam = VK_ESCAPE) then PostQuitMessage(0);
    end;

    WM_PAINT:
    begin
      // Paint some simple explanation text
      hDC := BeginPaint(hWnd, ps);
      SetBkColor(hDC, $ff0000);
      SetTextColor(hDC, $ffFFFF);
      GetClientRect(hWnd, rect);
      rect.top := 100;
      DrawText(hDC, 'Press space to play an XACT cue called ''zap'''#10+
                    'This cue is defined in the XACT sound bank sounds.xsb'#10+
                    'which was built using the XACT project sounds.xap'#10+
                    ''#10+
                    'Because of the way XACT works, what sound(s) play when'#10+
                    'this cue is played can be changed without recompiling'#10+
                    'the game. This allows the audio to be designed and'#10+
                    'tweaked independently once the game events are'#10+
                    'defined and the cues are triggered by the game engine.'#10,
                    -1, rect, DT_CENTER);
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

  // After pEngine->ShutDown() returns it is safe to release memory mapped files
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

