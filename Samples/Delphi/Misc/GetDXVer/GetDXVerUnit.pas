(*----------------------------------------------------------------------------*
 *  Direct3D sample from DirectX 9.0 SDK June 2005                            *
 *  Delphi adaptation by Alexey Barkovoy (e-mail: directx@clootie.ru)         *
 *                                                                            *
 *  Supported compilers: Delphi 5,6,7,9; FreePascal 2.0                       *
 *                                                                            *
 *  Thanks to Kai Jaeger for forcing me to write this sample conversion ;-)   *
 *                                                                            *
 *  Latest version can be downloaded from:                                    *
 *     http://www.clootie.ru                                                  *
 *     http://sourceforge.net/projects/delphi-dx9sdk                          *
 *----------------------------------------------------------------------------*
 *  $Id: GetDXVerUnit.pas,v 1.8 2005/06/30 19:49:00 clootie Exp $
 *----------------------------------------------------------------------------*)

//-----------------------------------------------------------------------------
// File: GetDXVer.cpp
//
// Desc: Demonstrates how applications can detect what version of DirectX
//       is installed.
//
// (C) Copyright Microsoft Corp.  All rights reserved.
//-----------------------------------------------------------------------------

{$I DirectX.inc}

unit GetDXVerUnit;

interface

uses
  Windows, ActiveX, SysUtils, StrSafe, DxDiag;

//-----------------------------------------------------------------------------
// Name: GetDXVersion()
// Desc: This function returns the DirectX version.
// Arguments: 
//      pdwDirectXVersion - This can be NULL.  If non-NULL, the return value is:
//              0x00000000 = No DirectX installed
//              0x00010000 = DirectX 1.0 installed
//              0x00020000 = DirectX 2.0 installed
//              0x00030000 = DirectX 3.0 installed
//              0x00030001 = DirectX 3.0a installed
//              0x00050000 = DirectX 5.0 installed
//              0x00060000 = DirectX 6.0 installed
//              0x00060100 = DirectX 6.1 installed
//              0x00060101 = DirectX 6.1a installed
//              0x00070000 = DirectX 7.0 installed
//              0x00070001 = DirectX 7.0a installed
//              0x00080000 = DirectX 8.0 installed
//              0x00080100 = DirectX 8.1 installed
//              0x00080101 = DirectX 8.1a installed
//              0x00080102 = DirectX 8.1b installed
//              0x00080200 = DirectX 8.2 installed
//              0x00090000 = DirectX 9.0 installed
//      strDirectXVersion - Destination string to receive a string name of the DirectX Version.  Can be NULL.
//      cchDirectXVersion - Size of destination buffer in characters.  Length should be at least 10 chars.
// Returns: S_OK if the function succeeds.
//          E_FAIL if the DirectX version info couldn't be determined.
//
// Please note that this code is intended as a general guideline. Your
// app will probably be able to simply query for functionality (via
// QueryInterface) for one or two components.
//
// Also please ensure your app will run on future releases of DirectX.
// For example:
//     "if( dwDirectXVersion != 0x00080100 ) return false;" is VERY BAD.
//     "if( dwDirectXVersion < 0x00080100 ) return false;" is MUCH BETTER.
//-----------------------------------------------------------------------------
function GetDXVersion(out dwDirectXVersion: DWORD; out strDirectXVersion: String): HResult;

implementation

function GetDirectXVersionViaDxDiag(out pdwDirectXVersionMajor, pdwDirectXVersionMinor: DWORD; out pcDirectXVersionLetter: Char): HRESULT; forward;
function GetDirectXVersionViaFileVersions(out pdwDirectXVersionMajor, pdwDirectXVersionMinor: DWORD; out pcDirectXVersionLetter: Char): HRESULT; forward;
function GetFileVersion(szPath: PChar; out pllFileVersion: Int64): HRESULT; forward;


function GetDXVersion(out dwDirectXVersion: DWORD; out strDirectXVersion: String): HResult;
var
  bGotDirectXVersion: bool;
  dwDirectXVersionMajor: DWORD;
  dwDirectXVersionMinor: DWORD;
  cDirectXVersionLetter: Char;
begin
  Result:= E_FAIL;
  bGotDirectXVersion := False;

  // Init values to unknown
  dwDirectXVersion := 0;
  strDirectXVersion := '';

  dwDirectXVersionMajor := 0;
  dwDirectXVersionMinor := 0;
  cDirectXVersionLetter := ' ';

  // First, try to use dxdiag's COM interface to get the DirectX version.
  // The only downside is this will only work on DirectX9 or later.
  if SUCCEEDED(GetDirectXVersionViaDxDiag(dwDirectXVersionMajor, dwDirectXVersionMinor, cDirectXVersionLetter))
  then bGotDirectXVersion := True; 

  if not bGotDirectXVersion then
  begin
    // Getting the DirectX version info from DxDiag failed,
    // so most likely we are on DirectX8.x or earlier
    if SUCCEEDED(GetDirectXVersionViaFileVersions(dwDirectXVersionMajor, dwDirectXVersionMinor, cDirectXVersionLetter))
    then bGotDirectXVersion := True;
  end;

  // If both techniques failed, then return E_FAIL
  if not bGotDirectXVersion then Exit;

  // Set the output values to what we got and return
  {$IFDEF FPC}
  cDirectXVersionLetter := LowerCase(cDirectXVersionLetter);
  {$ELSE}
  cDirectXVersionLetter := LowerCase(cDirectXVersionLetter)[1];
  {$ENDIF}

    
  // Set dwDirectXVersion to something
  // like $00080102 which would represent DirectX8.1b
  dwDirectXVersion := dwDirectXVersionMajor;
  dwDirectXVersion := dwDirectXVersion shl 8;
  dwDirectXVersion := dwDirectXVersion + dwDirectXVersionMinor;
  dwDirectXVersion := dwDirectXVersion shl 8;
  if (cDirectXVersionLetter >= 'a') and (cDirectXVersionLetter <= 'z')
  then dwDirectXVersion:= dwDirectXVersion + DWORD(Ord(cDirectXVersionLetter) - Ord('a')) + 1;

  // Set strDirectXVersion to something
  // like "8.1b" which would represent DirectX8.1b
  if (cDirectXVersionLetter = ' ')
  then strDirectXVersion:= Format('%d.%d', [dwDirectXVersionMajor, dwDirectXVersionMinor])
  else  strDirectXVersion:= Format('%d.%d%s', [dwDirectXVersionMajor, dwDirectXVersionMinor, cDirectXVersionLetter]);

  Result:= S_OK;
end;


{$IFDEF FPC}
const
  oleaut32 = 'oleaut32.dll';

function SysStringLen(bstr: TBStr): Integer; stdcall; external oleaut32 name 'SysStringLen';
{$ENDIF}


//-----------------------------------------------------------------------------
// Name: GetDirectXVersionViaDxDiag()
// Desc: Tries to get the DirectX version from DxDiag's COM interface
//-----------------------------------------------------------------------------
function GetDirectXVersionViaDxDiag(out pdwDirectXVersionMajor, pdwDirectXVersionMinor: DWORD; out pcDirectXVersionLetter: Char): HRESULT;
var
  hr: HRESULT;
  bCleanupCOM: Boolean;
  bSuccessGettingMajor,
  bSuccessGettingMinor,
  bSuccessGettingLetter: Boolean;
  bGotDirectXVersion: Boolean;
  pDxDiagProvider: IDxDiagProvider;
  dxDiagInitParam: TDxDiagInitParams;
  pDxDiagRoot: IDxDiagContainer;
  pDxDiagSystemInfo: IDxDiagContainer;
  vari: OleVariant;
{$IFNDEF UNICODE}
  strDestination: array[0..9] of AnsiChar;
  ws: WideString;
{$ENDIF}
begin
  bSuccessGettingMajor := False;
  bSuccessGettingMinor := False;
  bSuccessGettingLetter := False;

  // Init COM.  COM may fail if its already been inited with a different
  // concurrency model.  And if it fails you shouldn't release it.
  hr := CoInitialize(nil);
  bCleanupCOM := SUCCEEDED(hr);

  // Get an IDxDiagProvider
  bGotDirectXVersion := False;
  hr := CoCreateInstance(CLSID_DxDiagProvider, nil, CLSCTX_INPROC_SERVER,
                         IID_IDxDiagProvider, pDxDiagProvider);
  if SUCCEEDED(hr) then
  begin
    // Fill out a DXDIAG_INIT_PARAMS struct
    ZeroMemory(@dxDiagInitParam, SizeOf(dxDiagInitParam));
    dxDiagInitParam.dwSize                  := SizeOf(dxDiagInitParam);
    dxDiagInitParam.dwDxDiagHeaderVersion   := DXDIAG_DX9_SDK_VERSION;
    dxDiagInitParam.bAllowWHQLChecks        := False;
    dxDiagInitParam.pReserved               := nil;

    // Init the m_pDxDiagProvider
    hr := pDxDiagProvider.Initialize(dxDiagInitParam);
    if SUCCEEDED(hr) then
    begin
      // Get the DxDiag root container
      hr := pDxDiagProvider.GetRootContainer(pDxDiagRoot);
      if SUCCEEDED(hr) then 
      begin
        // Get the object called DxDiag_SystemInfo
        hr := pDxDiagRoot.GetChildContainer('DxDiag_SystemInfo', pDxDiagSystemInfo);
        if SUCCEEDED(hr) then
        begin
          // Get the "dwDirectXVersionMajor" property
          hr := pDxDiagSystemInfo.GetProp('dwDirectXVersionMajor', vari);
          if SUCCEEDED(hr) and (TVarData(vari).VType = VT_UI4) then
          begin
           {$IFDEF FPC}
            pdwDirectXVersionMajor := TVarData(vari).VLongWord;
           {$ELSE}
            pdwDirectXVersionMajor := vari;
           {$ENDIF}
            bSuccessGettingMajor := True;
          end;

          // Get the "dwDirectXVersionMinor" property
          hr := pDxDiagSystemInfo.GetProp('dwDirectXVersionMinor', vari);
          if SUCCEEDED(hr) and (TVarData(vari).VType = VT_UI4) then
          begin
           {$IFDEF FPC}
            pdwDirectXVersionMinor := TVarData(vari).VLongWord;
           {$ELSE}
            pdwDirectXVersionMinor := vari;
           {$ENDIF}
            bSuccessGettingMinor := True;
          end;

          // Get the "szDirectXVersionLetter" property
          hr := pDxDiagSystemInfo.GetProp('szDirectXVersionLetter', vari);
          if SUCCEEDED(hr) and (TVarData(vari).VType = VT_BSTR) and
             (SysStringLen(TVarData(vari).VOleStr) <> 0) then
          begin
{$IFDEF UNICODE}
            pcDirectXVersionLetter := vari.VOleStr[0];
{$ELSE}
            {$IFDEF FPC}
            ws:= TVarData(vari).VOleStr;
            {$ELSE}
            ws:= vari;
            {$ENDIF}
            WideCharToMultiByte(CP_ACP, 0, PWideChar(ws), -1, strDestination, 10*SizeOf(AnsiChar), nil, nil);
            pcDirectXVersionLetter := strDestination[0];
{$ENDIF}
            bSuccessGettingLetter := True;
          end;

          // If it all worked right, then mark it down
          if (bSuccessGettingMajor and bSuccessGettingMinor and bSuccessGettingLetter)
          then bGotDirectXVersion := True;

          pDxDiagSystemInfo := nil;
        end;

        pDxDiagRoot := nil;
      end;
    end;

    pDxDiagProvider := nil;
  end;

  if bCleanupCOM then CoUninitialize;

  if (bGotDirectXVersion) then Result:= S_OK
  else Result:= E_FAIL;
end;



//-----------------------------------------------------------------------------
// Name: MakeInt64()
// Desc: Returns a ULARGE_INTEGER where a<<48|b<<32|c<<16|d<<0
//-----------------------------------------------------------------------------
function MakeInt64(a, b, c, d: Word): Int64; //ULARGE_INTEGER;
begin
  Int64Rec(Result).Hi := MAKELONG(b, a);
  Int64Rec(Result).Lo := MAKELONG(d, c);
end;


//-----------------------------------------------------------------------------
// Name: GetDirectXVersionViaFileVersions()
// Desc: Tries to get the DirectX version by looking at DirectX file versions
//-----------------------------------------------------------------------------
function GetDirectXVersionViaFileVersions(out pdwDirectXVersionMajor, pdwDirectXVersionMinor: DWORD; out pcDirectXVersionLetter: Char): HRESULT;
var
  llFileVersion: Int64; // ULARGE_INTEGER;
  szPath: array [0..511] of Char;
  szFile: array [0..511] of Char;
  bFound: Boolean;
begin
  bFound := False;

  if (GetSystemDirectory(szPath, MAX_PATH) <> 0) then
  begin
    szPath[MAX_PATH-1]:= #0;

    // Switch off the ddraw version
    StringCchCopy(szFile, 512, szPath);
    StringCchCat(szFile, 512, '\ddraw.dll');
    if SUCCEEDED(GetFileVersion(szFile, llFileVersion)) then
    begin
      if (llFileVersion >= MakeInt64(4, 2, 0, 95)) then // Win9x version
      begin
        // flle is >= DirectX1.0 version, so we must be at least DirectX1.0
        pdwDirectXVersionMajor := 1;
        pdwDirectXVersionMinor := 0;
        pcDirectXVersionLetter := ' ';
        bFound := True;
      end;

      if (llFileVersion >= MakeInt64(4, 3, 0, 1096)) then // Win9x version
      begin
        // flle is is >= DirectX2.0 version, so we must DirectX2.0 or DirectX2.0a (no redist change)
        pdwDirectXVersionMajor := 2;
        pdwDirectXVersionMinor := 0;
        pcDirectXVersionLetter := ' ';
        bFound := True;
      end;

      if (llFileVersion >= MakeInt64(4, 4, 0, 68)) then // Win9x version
      begin
        // flle is is >= DirectX3.0 version, so we must be at least  DirectX3.0
        pdwDirectXVersionMajor := 3;
        pdwDirectXVersionMinor := 0;
        pcDirectXVersionLetter := ' ';
        bFound := True;
      end;
    end;

    // Switch off the d3drg8x.dll version
    StringCchCopy(szFile, 512, szPath);
    StringCchCat(szFile, 512, '\d3drg8x.dll');
    if SUCCEEDED(GetFileVersion(szFile, llFileVersion)) then
    begin
      if (llFileVersion >= MakeInt64(4, 4, 0, 70)) then // Win9x version
      begin
        // d3drg8x.dll is the DirectX3.0a version, so we must be DirectX3.0a or DirectX3.0b  (no redist change)
        pdwDirectXVersionMajor := 3;
        pdwDirectXVersionMinor := 0;
        pcDirectXVersionLetter := 'a';
        bFound := True;
      end;
    end;

    // Switch off the ddraw version
    StringCchCopy(szFile, 512, szPath);
    StringCchCat(szFile, 512, '\ddraw.dll');
    if SUCCEEDED(GetFileVersion(szFile, llFileVersion)) then
    begin
      if (llFileVersion >= MakeInt64(4, 5, 0, 155)) then // Win9x version
      begin
        // ddraw.dll is the DirectX5.0 version, so we must be DirectX5.0 or DirectX5.2 (no redist change)
        pdwDirectXVersionMajor := 5;
        pdwDirectXVersionMinor := 0;
        pcDirectXVersionLetter := ' ';
        bFound := True;
      end;

      if (llFileVersion >= MakeInt64(4, 6, 0, 318)) then // Win9x version
      begin
        // ddraw.dll is the DirectX6.0 version, so we must be at least DirectX6.0
        pdwDirectXVersionMajor := 6;
        pdwDirectXVersionMinor := 0;
        pcDirectXVersionLetter := ' ';
        bFound := True;
      end;

      if (llFileVersion >= MakeInt64(4, 6, 0, 436)) then // Win9x version
      begin
        // ddraw.dll is the DirectX6.1 version, so we must be at least DirectX6.1
        pdwDirectXVersionMajor := 6;
        pdwDirectXVersionMinor := 1;
        pcDirectXVersionLetter := ' ';
        bFound := True;
      end;
    end;

    // Switch off the dplayx.dll version
    StringCchCopy(szFile, 512, szPath);
    StringCchCat(szFile, 512, '\dplayx.dll');
    if SUCCEEDED(GetFileVersion(szFile, llFileVersion)) then
    begin
      if (llFileVersion >= MakeInt64(4, 6, 3, 518)) then // Win9x version
      begin
        // ddraw.dll is the DirectX6.1 version, so we must be at least DirectX6.1a
        pdwDirectXVersionMajor := 6;
        pdwDirectXVersionMinor := 1;
        pcDirectXVersionLetter := 'a';
        bFound := True;
      end;
    end;

    // Switch off the ddraw version
    StringCchCopy(szFile, 512, szPath);
    StringCchCat(szFile, 512, '\ddraw.dll');
    if SUCCEEDED(GetFileVersion(szFile, llFileVersion)) then
    begin
      if (llFileVersion >= MakeInt64(4, 7, 0, 700)) then // Win9x version
      begin
        // TODO: find win2k version

        // ddraw.dll is the DirectX7.0 version, so we must be at least DirectX7.0
        pdwDirectXVersionMajor := 7;
        pdwDirectXVersionMinor := 0;
        pcDirectXVersionLetter := ' ';
        bFound := True;
      end;
    end;

    // Switch off the dinput version
    StringCchCopy(szFile, 512, szPath);
    StringCchCat(szFile, 512, '\dinput.dll');
    if SUCCEEDED(GetFileVersion(szFile, llFileVersion)) then
    begin
      if (llFileVersion >= MakeInt64(4, 7, 0, 716)) then // Win9x version
      begin
        // ddraw.dll is the DirectX7.0 version, so we must be at least DirectX7.0a
        pdwDirectXVersionMajor := 7;
        pdwDirectXVersionMinor := 0;
        pcDirectXVersionLetter := 'a';
        bFound := True;
      end;
    end;

    // Switch off the ddraw version
    StringCchCopy(szFile, 512, szPath);
    StringCchCat(szFile, 512, '\ddraw.dll');
    if SUCCEEDED(GetFileVersion(szFile, llFileVersion)) then
    begin
      if ( (HIWORD(Int64Rec(llFileVersion).Hi) = 4) and (llFileVersion >= MakeInt64(4, 8, 0, 400)) or // Win9x version
           (HIWORD(Int64Rec(llFileVersion).Hi) = 5) and (llFileVersion >= MakeInt64(5, 1, 2258, 400)) // Win2k/WinXP version
         ) then
      begin
        // ddraw.dll is the DirectX8.0 version, so we must be at least DirectX8.0 or DirectX8.0a (no redist change)
        pdwDirectXVersionMajor := 8;
        pdwDirectXVersionMinor := 0;
        pcDirectXVersionLetter := ' ';
        bFound := True;
      end;
    end;

    StringCchCopy(szFile, 512, szPath);
    StringCchCat(szFile, 512, '\d3d8.dll');
    if SUCCEEDED(GetFileVersion(szFile, llFileVersion)) then
    begin
      if ( (HIWORD(Int64Rec(llFileVersion).Hi) = 4) and (llFileVersion >= MakeInt64(4, 8, 1, 881)) or // Win9x version
           (HIWORD(Int64Rec(llFileVersion).Hi) = 5) and (llFileVersion >= MakeInt64(5, 1, 2600, 881)) // Win2k/WinXP version
         ) then
      begin
        // d3d8.dll is the DirectX8.1 version, so we must be at least DirectX8.1
        pdwDirectXVersionMajor := 8;
        pdwDirectXVersionMinor := 1;
        pcDirectXVersionLetter := ' ';
        bFound := True;
      end;

      if ( (HIWORD(Int64Rec(llFileVersion).Hi) = 4) and (llFileVersion >= MakeInt64(4, 8, 1, 901)) or // Win9x version
           (HIWORD(Int64Rec(llFileVersion).Hi) = 5) and (llFileVersion >= MakeInt64(5, 1, 2600, 901)) // Win2k/WinXP version
         ) then
      begin
        // d3d8.dll is the DirectX8.1a version, so we must be at least DirectX8.1a
        pdwDirectXVersionMajor := 8;
        pdwDirectXVersionMinor := 1;
        pcDirectXVersionLetter := 'a';
        bFound := True;
      end;
    end;

    StringCchCopy(szFile, 512, szPath);
    StringCchCat(szFile, 512, '\mpg2splt.dll');
    if SUCCEEDED(GetFileVersion(szFile, llFileVersion)) then
    begin
      if (llFileVersion >= MakeInt64(6, 3, 1, 885)) then // Win9x/Win2k/WinXP version
      begin
        // quartz.dll is the DirectX8.1b version, so we must be at least DirectX8.1b
        pdwDirectXVersionMajor := 8;
        pdwDirectXVersionMinor := 1;
        pcDirectXVersionLetter := 'b';
        bFound := True;
      end;
    end;

    StringCchCopy(szFile, 512, szPath);
    StringCchCat(szFile, 512, '\dpnet.dll');
    if SUCCEEDED(GetFileVersion(szFile, llFileVersion)) then
    begin
      if ( (HIWORD(Int64Rec(llFileVersion).Hi) = 4) and (llFileVersion >= MakeInt64(4, 9, 0, 134)) or // Win9x version
           (HIWORD(Int64Rec(llFileVersion).Hi) = 5) and (llFileVersion >= MakeInt64(5, 2, 3677, 134)) // Win2k/WinXP version
         ) then
      begin
        // dpnet.dll is the DirectX8.2 version, so we must be at least DirectX8.2
        pdwDirectXVersionMajor := 8;
        pdwDirectXVersionMinor := 2;
        pcDirectXVersionLetter := ' ';
        bFound := True;
      end;
    end;

    StringCchCopy(szFile, 512, szPath);
    StringCchCat(szFile, 512, '\d3d9.dll');
    if SUCCEEDED(GetFileVersion(szFile, llFileVersion)) then
    begin
      // File exists, but be at least DirectX9
      pdwDirectXVersionMajor := 9;
      pdwDirectXVersionMinor := 0;
      pcDirectXVersionLetter := ' ';
      bFound := True;
    end;
  end;

  if not bFound then
  begin
    // No DirectX installed
    pdwDirectXVersionMajor := 0;
    pdwDirectXVersionMinor := 0;
    pcDirectXVersionLetter := ' ';
  end;

  Result:= S_OK;
end;




//-----------------------------------------------------------------------------
// Name: GetFileVersion()
// Desc: Returns ULARGE_INTEGER with a file version of a file, or a failure code.
//-----------------------------------------------------------------------------
function GetFileVersion(szPath: PChar; out pllFileVersion: Int64): HRESULT;
var
  dwHandle: DWORD;
  cb: LongWord;
  pFileVersionBuffer: PByte;
  pVersion: PVSFixedFileInfo;
begin
  if (szPath = nil) then
  begin
    Result:= E_INVALIDARG;
    Exit;
  end;

  cb := GetFileVersionInfoSize(szPath, dwHandle);
  if (cb > 0) then
  begin
    GetMem(pFileVersionBuffer, SizeOf(Byte)*cb);
    try
      if GetFileVersionInfo(szPath, 0, cb, pFileVersionBuffer) then
      begin
        pVersion := nil;
        if VerQueryValue(pFileVersionBuffer, '\', Pointer(pVersion), cb) and
           (pVersion <> nil) then
        begin
          Int64Rec(pllFileVersion).Hi := pVersion.dwFileVersionMS;
          Int64Rec(pllFileVersion).Lo := pVersion.dwFileVersionLS;
          Result:= S_OK;
          Exit;
        end;
      end;
    finally
      FreeMem(pFileVersionBuffer);
    end;
  end;

  Result:= E_FAIL;
end;

end.


