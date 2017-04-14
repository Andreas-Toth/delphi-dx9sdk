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
 *  $Id: UVAtlasUnit.pas,v 1.15 2007/02/05 22:21:13 clootie Exp $
 *----------------------------------------------------------------------------*)

{$I DirectX.inc}

unit UVAtlasUnit;

interface

uses
  Windows, Classes, SysUtils, StrSafe,
  DXTypes, Direct3D9, D3DX9, DXErr9,
  DXUTcore, DXUTmisc, 
  CrackDecl;


type
  PSingleArray = ^TSingleArray;
  TSingleArray = array[0..MaxInt div SizeOf(Single)-1] of Single;

const
  COLOR_COUNT = 8;

var
  ColorList: array [0..COLOR_COUNT-1, 0..2] of Single =
  (
    (1.0, 0.5, 0.5),
    (0.5, 1.0, 0.5),
    (1.0, 1.0, 0.5),
    (0.5, 1.0, 1.0),
    (1.0, 0.5, 0.75),
    (0.0, 0.5, 0.75),
    (0.5, 0.5, 0.75),
    (0.5, 0.5, 1.0)
  );

const
  g_cfEpsilon: Single = 1e-5;

//-----------------------------------------------------------------------------
type
  PSettings = ^TSettings;
  TSettings = record
    maxcharts, width, height: Integer;
    maxstretch, gutter: Single;
    nOutputTextureIndex: Byte;
    bTopologicalAdjacency: Boolean;
    bGeometricAdjacency: Boolean;
    bFalseEdges: Boolean;
    bFileAdjacency: Boolean;
    szAdjacencyFilename: WideString; // : array[0..MAX_PATH-1] of WideChar;
    szFalseEdgesFilename: WideString; // : array[0..MAX_PATH-1] of WideChar;

    bUserAbort, bSubDirs, bOverwrite, bOutputTexture, bColorMesh: Boolean;
    bVerbose: Boolean;
    bOutputFilenameGiven: Boolean;
    szOutputFilename: WideString; //array[0..MAX_PATH-1] of WideChar;

    bIMT: Boolean;
    bTextureSignal: Boolean;
    bPRTSignal: Boolean;
    bVertexSignal: Boolean;
    VertexSignalUsage: TD3DDeclUsage;
    VertexSignalIndex: Byte;
    nIMTInputTextureIndex: Byte;
    szIMTInputFilename: WideString; // array[0..MAX_PATH-1] of WideChar;
    bResampleTexture: Boolean;
    ResampleTextureUsage: TD3DDeclUsage;
    ResampleTextureUsageIndex: LongWord;
    szResampleTextureFile: WideString; // array[0..MAX_PATH-1] of WideChar;

    aFiles: array of WideString; //aFiles: {Wide}TStrings; // CGrowableArray<WCHAR*>
  end;


(*  //-----------------------------------------------------------------------------
  CProcessedFileList = class
  public

    destructor Destroy;
    {
        for( int i=0; i<m_fileList.GetSize(); i++ )
            SAFE_DELETE_ARRAY( m_fileList[i] );
        m_fileList.RemoveAll();
    }

    function IsInList(strFullPath: PWideChar): Boolean;
    {
        for( int i=0; i<m_fileList.GetSize(); i++ )
        {
            if( wcscmp( m_fileList[i], strFullPath ) == 0 )
                return true;
        }

        //return false;
    //}

    procedure Add(strFullPath: PWideChar)
    {
        WCHAR* strTemp = new WCHAR[MAX_PATH];
        StringCchCopy( strTemp, MAX_PATH, strFullPath );
        m_fileList.Add( strTemp );
    }

protected:
    CGrowableArray<WCHAR*> m_fileList;
};

CProcessedFileList
*)
var
  g_ProcessedFileList: TStringList;


//-----------------------------------------------------------------------------
// Function-prototypes
//-----------------------------------------------------------------------------
function ParseCommandLine(var pSettings: TSettings): Boolean;
function IsNextArg(var strCmdLine: PWideChar; strArg: PWideChar): Boolean; overload;
function IsNextArg(const strCmdLine, strArg: WideString): Boolean; overload;
function CreateNULLRefDevice: IDirect3DDevice9;
procedure SearchDirForFile(const pd3dDevice: IDirect3DDevice9; strDir: PWideChar; strFile: PWideChar; const pSettings: TSettings);
procedure SearchSubdirsForFile(const pd3dDevice: IDirect3DDevice9; strDir: PWideChar; strFile: PWideChar; const pSettings: TSettings);
function ProcessFile(const pd3dDevice: IDirect3DDevice9; strFile: PWideChar; const pSettings: TSettings): HRESULT;
procedure DisplayUsage;
function TraceD3DDeclUsageToString(u: TD3DDeclUsage): PWideChar;
function LoadFile(szFile: WideString; out ppBuffer: ID3DXBuffer): HRESULT;


implementation


function GetParamStr(P: PWideChar; var Param: WideString): PWideChar;
var
  i, Len: Integer;
  Start, S, Q: PWideChar;
begin
  while True do
  begin
    while (P[0] <> #0) and (P[0] <= ' ') do
      P := CharNextW(P);
    if (P[0] = '"') and (P[1] = '"') then Inc(P, 2) else Break;
  end;
  Len := 0;
  Start := P;
  while P[0] > ' ' do
  begin
    if P[0] = '"' then
    begin
      P := CharNextW(P);
      while (P[0] <> #0) and (P[0] <> '"') do
      begin
        Q := CharNextW(P);
        Inc(Len, Q - P);
        P := Q;
      end;
      if P[0] <> #0 then
        P := CharNextW(P);
    end
    else
    begin
      Q := CharNextW(P);
      Inc(Len, Q - P);
      P := Q;
    end;
  end;

  SetLength(Param, Len);

  P := Start;
  S := Pointer(Param);
  i := 0;
  while P[0] > ' ' do
  begin
    if P[0] = '"' then
    begin
      P := CharNextW(P);
      while (P[0] <> #0) and (P[0] <> '"') do
      begin
        Q := CharNextW(P);
        while P < Q do
        begin
          S[i] := P^;
          Inc(P);
          Inc(i);
        end;
      end;
      if P[0] <> #0 then P := CharNextW(P);
    end
    else
    begin
      Q := CharNextW(P);
      while P < Q do
      begin
        S[i] := P^;
        Inc(P);
        Inc(i);
      end;
    end;
  end;

  Result := P;
end;

function ParamCount: Integer;
var
  P: PWideChar;
  S: WideString;
begin
  Result := 0;
  P := GetParamStr(GetCommandLineW, S);
  while True do
  begin
    P := GetParamStr(P, S);
    if S = '' then Break;
    Inc(Result);
  end;
end;

function ParamStr(Index: Integer): WideString;
var
  P: PWideChar;
  Buffer: array[0..260] of WideChar;
begin
  Result := '';
  if Index = 0 then
    SetString(Result, Buffer, GetModuleFileNameW(0, Buffer, SizeOf(Buffer)))
  else
  begin
    P := GetCommandLineW;
    while True do
    begin
      P := GetParamStr(P, Result);
      if (Index = 0) or (Result = '') then Break;
      Dec(Index);
    end;
  end;
end;


//--------------------------------------------------------------------------------------
// Parses the command line for parameters.  See DXUTInit() for list
//--------------------------------------------------------------------------------------
function ParseCommandLine(var pSettings: TSettings): Boolean;
var
  bDisplayHelp: Boolean;
  strArg: WideString; // array[0..255] of WideChar;
  strCmdLine: WideString;
  nNumArgs: Integer;
  L: Integer;
  iArg: Integer;
begin
  bDisplayHelp := False;

  nNumArgs := ParamCount;

  // WCHAR** pstrArgList = CommandLineToArgvW( GetCommandLine(), &nNumArgs );
  iArg:= 1;
  while (iArg <= nNumArgs) do
  // for iArg:= 1 to nNumArgs do
  begin
    strCmdLine := ParamStr(iArg);
    Inc(iArg);

    // Handle flag args
    if (AnsiChar(strCmdLine[1]) in ['/', '-']) then
    begin
      strCmdLine:= Copy(strCmdLine, 2, MaxInt);

      if IsNextArg(strCmdLine, 'ta') then
      begin
        if (pSettings.bGeometricAdjacency or pSettings.bFileAdjacency) then
        begin
          WriteLn('Incorrect flag usage: /ta, /ga, and /fa are exclusive');
          bDisplayHelp := True;
          Continue;
        end;

        pSettings.bTopologicalAdjacency := True;
        pSettings.bGeometricAdjacency := False;
        pSettings.bFileAdjacency := False;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'ga') then
      begin
        if (pSettings.bTopologicalAdjacency or pSettings.bFileAdjacency) then
        begin
          WriteLn('Incorrect flag usage: /ta, /ga, and /fa are exclusive');
          bDisplayHelp := True;
          Continue;
        end;
        pSettings.bTopologicalAdjacency := False;
        pSettings.bGeometricAdjacency   := True;
        pSettings.bFileAdjacency        := False;
        continue;
      end;

      if IsNextArg(strCmdLine, 'fa') then
      begin
        if (pSettings.bTopologicalAdjacency or pSettings.bGeometricAdjacency) then
        begin
          WriteLn('Incorrect flag usage: /ta, /ga, and /fa are exclusive');
          bDisplayHelp := True;
        end;

        if (iArg+1 < nNumArgs) then
        begin
          pSettings.bTopologicalAdjacency := False;
          pSettings.bGeometricAdjacency   := False;
          pSettings.bFileAdjacency        := True;
          strArg := ParamStr(iArg);
          Inc(iArg);
          pSettings.szAdjacencyFilename := strArg;
          continue;
        end;
        WriteLn('Incorrect flag usage: /fa');
        bDisplayHelp := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'fe') then
      begin
        if (iArg+1 < nNumArgs) then
        begin
          strArg := ParamStr(iArg);
          Inc(iArg);
          pSettings.bFalseEdges := True;
          pSettings.szFalseEdgesFilename := strArg;
          Continue;
        end;
        WriteLn('Incorrect flag usage: /fe');
        bDisplayHelp := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 's') then
      begin
        pSettings.bSubDirs := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'c') then
      begin
        pSettings.bColorMesh := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'o') then
      begin
        if pSettings.bOverwrite then
        begin
          WriteLn('Incorrect flag usage: /f and /o');
          bDisplayHelp := True;
          Continue;
        end;

        if (iArg <= nNumArgs) then
        begin
          strArg := ParamStr(iArg);
          Inc(iArg);
          pSettings.bOutputFilenameGiven := True;
          pSettings.szOutputFilename:= strArg;
          Continue;
        end;

        WriteLn('Incorrect flag usage: /o');
        bDisplayHelp := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'it') then
      begin
        if (pSettings.bPRTSignal or pSettings.bVertexSignal) then
        begin
          WriteLn('Incorrect flag usage: /it, /ip, and /iv are exclusive');
          bDisplayHelp := True;
          Continue;
        end;

        if (iArg <= nNumArgs) then
        begin
          strArg := ParamStr(iArg);
          Inc(iArg);
          pSettings.szIMTInputFilename := strArg;
          pSettings.bIMT := True;
          pSettings.bTextureSignal := True;
          Continue;
        end;

        WriteLn('Incorrect flag usage: /it');
        bDisplayHelp := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'ip') then
      begin
        if (pSettings.bTextureSignal or pSettings.bVertexSignal) then
        begin
          WriteLn('Incorrect flag usage: /it, /ip, and /iv are exclusive');
          bDisplayHelp := True;
          Continue;
        end;

        if (iArg <= nNumArgs) then
        begin
          strArg := ParamStr(iArg);
          Inc(iArg);
          pSettings.szIMTInputFilename := strArg;
          pSettings.bIMT := True;
          pSettings.bPRTSignal := True;
          Continue;
        end;

        WriteLn('Incorrect flag usage: /ip');
        bDisplayHelp := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'iv') then
      begin
        if (pSettings.bTextureSignal or pSettings.bPRTSignal) then
        begin
          WriteLn('Incorrect flag usage: /it, /ip, and /iv are exclusive');
          bDisplayHelp := True;
          Continue;
        end;

        if (iArg <= nNumArgs) then
        begin
          strArg := ParamStr(iArg);
          Inc(iArg);
          if lstrcmpiW(PWideChar(strArg), 'COLOR') = 0 then
            pSettings.VertexSignalUsage := D3DDECLUSAGE_COLOR
          else if lstrcmpiW(PWideChar(strArg), 'NORMAL') = 0 then
            pSettings.VertexSignalUsage := D3DDECLUSAGE_NORMAL
          else if lstrcmpiW(PWideChar(strArg), 'TEXCOORD') = 0 then
            pSettings.VertexSignalUsage := D3DDECLUSAGE_TEXCOORD
          else if lstrcmpiW(PWideChar(strArg), 'TANGENT') = 0 then
            pSettings.VertexSignalUsage := D3DDECLUSAGE_TANGENT
          else if lstrcmpiW(PWideChar(strArg), 'BINORMAL') = 0 then
            pSettings.VertexSignalUsage := D3DDECLUSAGE_BINORMAL
          else
          begin
            WriteLn(WideFormat('Incorrect /iv flag usage: unknown usage parameter "%s"', [strArg]));
            bDisplayHelp := True;
            continue;
          end;
          pSettings.bIMT := True;
          pSettings.bVertexSignal := True;
          Continue;
        end;

        WriteLn('Incorrect flag usage: /ip');
        bDisplayHelp := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'f') then
      begin
        pSettings.bOverwrite := True;
        if pSettings.bOutputFilenameGiven then
        begin
          WriteLn('Incorrect flag usage: /f and /o');
          bDisplayHelp := True;
        end;
        Continue;
      end;

      if IsNextArg(strCmdLine, 't') then
      begin
          pSettings.bOutputTexture := True;
          continue;
      end;

      if IsNextArg(strCmdLine, 'v') then
      begin
        pSettings.bVerbose := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'n') then
      begin
        if (iArg <= nNumArgs) then
        begin
          strArg := ParamStr(iArg);
          Inc(iArg);
          pSettings.maxcharts := StrToInt(strArg);
          Continue;
        end;

        WriteLn('Incorrect flag usage: /n');
        bDisplayHelp := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'w') then
      begin
        if (iArg <= nNumArgs) then
        begin
          strArg := ParamStr(iArg);
          Inc(iArg);
          pSettings.width := StrToInt(strArg);
          Continue;
        end;

        WriteLn('Incorrect flag usage: /w');
        bDisplayHelp := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'h') then
      begin
        if (iArg <= nNumArgs) then
        begin
          strArg := ParamStr(iArg);
          Inc(iArg);
          pSettings.height := StrToInt(strArg);
          Continue;
        end;

        WriteLn('Incorrect flag usage: /h');
        bDisplayHelp := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'st') then
      begin
        if (iArg <= nNumArgs) then
        begin
          strArg := ParamStr(iArg);
          Inc(iArg);
          pSettings.maxstretch :=  StrToFloat(strArg);
          Continue;
        end;

        WriteLn('Incorrect flag usage: /st');
        bDisplayHelp := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'rt') then
      begin
        if (iArg+1 < nNumArgs) then
        begin
          pSettings.bResampleTexture := True;
          strArg := ParamStr(iArg);
          Inc(iArg);
          pSettings.szResampleTextureFile := strArg;
          Continue;
        end;

        WriteLn('Incorrect flag usage: /rt');
        bDisplayHelp := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'uvi') then
      begin
        if (iArg+1 < nNumArgs) then
        begin
          strArg := ParamStr(iArg);
          Inc(iArg);
          pSettings.nOutputTextureIndex := StrToInt(strArg);
          continue;
        end;

        WriteLn('Incorrect flag usage: /uvi');
        bDisplayHelp := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'rtu') then
      begin
        if (iArg+1 < nNumArgs) then
        begin
          strArg := ParamStr(iArg);
          Inc(iArg);
          if lstrcmpiW(PWideChar(strArg), 'NORMAL') = 0 then
              pSettings.ResampleTextureUsage := D3DDECLUSAGE_NORMAL
          else if lstrcmpiW(PWideChar(strArg), 'POSITION') = 0 then
              pSettings.ResampleTextureUsage := D3DDECLUSAGE_POSITION
          else if lstrcmpiW(PWideChar(strArg), 'TEXCOORD') = 0 then
              pSettings.ResampleTextureUsage := D3DDECLUSAGE_TEXCOORD
          else if lstrcmpiW(PWideChar(strArg), 'TANGENT') = 0 then
              pSettings.ResampleTextureUsage := D3DDECLUSAGE_TANGENT
          else if lstrcmpiW(PWideChar(strArg), 'BINORMAL') = 0 then
              pSettings.ResampleTextureUsage := D3DDECLUSAGE_BINORMAL
          else
          begin
            WriteLn(Format('Incorrect /rtu flag usage: unknown usage parameter "%s"', [strArg]));
            bDisplayHelp := True;
            Continue;
          end;
          Continue;
        end;

        WriteLn('Incorrect flag usage: /rtu');
        bDisplayHelp := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'rti') then
      begin
        if (iArg+1 < nNumArgs) then
        begin
          strArg := ParamStr(iArg);
          Inc(iArg);
          pSettings.ResampleTextureUsageIndex := StrToInt(strArg);
          Continue;
        end;

        WriteLn('Incorrect flag usage: /rti');
        bDisplayHelp := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, 'g') then
      begin
        if (iArg <= nNumArgs) then
        begin
          strArg := ParamStr(iArg);
          Inc(iArg);
          pSettings.gutter := StrToFloat(strArg);
          Continue;
        end;

        WriteLn('Incorrect flag usage: /g');
        bDisplayHelp := True;
        Continue;
      end;

      if IsNextArg(strCmdLine, '?') then
      begin
        DisplayUsage;
        Result:= False;
        Exit;
      end;

      // Unrecognized flag
      WriteLn(WideFormat('Unrecognized or incorrect flag usage: %s', [strCmdLine]));
      bDisplayHelp := True;
    end else
    begin
      // Handle non-flag args as seperate input files
      // pSettings.aFiles.Add(strCmdLine);
      L:= Length(pSettings.aFiles);
      SetLength(pSettings.aFiles, L+1);
      pSettings.aFiles[L]:= strCmdLine;
      Continue;
    end;
  end; // "for / while" end 

  if (Length(pSettings.aFiles) = 0) then
  begin
    DisplayUsage;
    Result:= False;
    Exit;
  end;

  if bDisplayHelp then
  begin
    WriteLn('Type "UVAtlas.exe /?" for a complete list of options');
    Result:= False;
    Exit;
  end;

  Result:= True;
end;


//--------------------------------------------------------------------------------------
function IsNextArg(var strCmdLine: PWideChar; strArg: PWideChar): Boolean;
var
  nArgLen: Integer;
begin
  Result:= True;
  nArgLen := lstrlenw{wcslen}(strArg);

  // if _wcsnicmp(strCmdLine, strArg, nArgLen) == 0 && strCmdLine[nArgLen] == 0 )
  if (lstrcmpiW(strCmdLine, strArg{, nArgLen}) = 0) and (strCmdLine[nArgLen] = #0)
  then Exit;

  Result:= False;
end;

function IsNextArg(const strCmdLine, strArg: WideString): Boolean; overload;
begin
  Result:= lstrcmpiW(PWideChar(strCmdLine), PWideChar(strArg)) = 0;
end;


//--------------------------------------------------------------------------------------
function GetNextArg(var strCmdLine: PWideChar; strArg: PWideChar; cchArg: Integer): Boolean;
var
  spacelen: LongWord;
  strSpace: PWideChar; 
  nArgLen: Integer;
begin
  // Place NULL terminator in strFlag after current token
  strSpace := strCmdLine;
  while (strSpace^ <> #0) and (strSpace^ in [WideChar(' ')]) // iswspace(*strSpace) )
  do Inc(strSpace);
  V_(StringCchCopy(strArg, 256, strSpace));
  spacelen := strSpace - strCmdLine;
  strSpace := strArg + (strSpace - strCmdLine);
  while (strSpace^ <> #0) and not (strSpace^ in [WideChar(' ')]) // iswspace(*strSpace) )
  // while( *strSpace && !iswspace(*strSpace) )
  do Inc(strSpace);
  strSpace^ := #0;

  // Update strCmdLine
  nArgLen := lstrlenW(strArg); //  wcslen
  strCmdLine := strCmdLine + nArgLen + spacelen;
  Result:= (nArgLen > 0);
end;


//--------------------------------------------------------------------------------------
procedure SearchSubdirsForFile(const pd3dDevice: IDirect3DDevice9; strDir: PWideChar; strFile: PWideChar; const pSettings: TSettings);
var
  strFullPath: WideString;
  strSearchDir: WideString;
  fileData: TWin32FindDataW;
  hFindFile: THandle;
  bSuccess: Boolean;
begin
  // First search this dir for the file
  SearchDirForFile(pd3dDevice, strDir, strFile, pSettings);
  if (pSettings.bUserAbort) then Exit;

  // Then search this dir for other dirs and recurse
  strSearchDir := WideString(strDir) + '*';

  ZeroMemory(@fileData, SizeOf(TWin32FindDataW));
  {$IFDEF FPC}
  hFindFile := FindFirstFileW(PWideChar(strSearchDir), @fileData);
  {$ELSE}
  hFindFile := FindFirstFileW(PWideChar(strSearchDir), fileData);
  {$ENDIF}
  if (hFindFile <> INVALID_HANDLE_VALUE) then
  begin
    bSuccess := True;
    while bSuccess do
    begin
      if (fileData.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY <> 0) then
      begin
        // Don't process '.' and '..' dirs
        if (fileData.cFileName[0] <> '.') then
        begin
          strFullPath:= strDir + WideString(fileData.cFileName) + '\';
          SearchSubdirsForFile(pd3dDevice, PWideChar(strFullPath), strFile, pSettings);
        end;
      end;
      {$IFDEF FPC}
      bSuccess := FindNextFileW(hFindFile, @fileData);
      {$ELSE}
      bSuccess := FindNextFileW(hFindFile, fileData);
      {$ENDIF}

      if (pSettings.bUserAbort) then Break;
    end;
    Windows.FindClose(hFindFile);
  end;
end;

            
//--------------------------------------------------------------------------------------
procedure SearchDirForFile(const pd3dDevice: IDirect3DDevice9; strDir: PWideChar; strFile: PWideChar; const pSettings: TSettings);
var
  strFullPath: WideString;
  strSearchDir: WideString;
  fileData: TWin32FindDataW;
  hFindFile: THandle;
  bSuccess: Boolean;
begin
  strSearchDir:= WideString(strDir) + strFile;

  WriteLn(WideFormat('Searching dir %s for %s', [strDir, strFile]));

  ZeroMemory(@fileData, SizeOf(TWin32FindDataW));
  {$IFDEF FPC}
  hFindFile := FindFirstFileW(PWideChar(strSearchDir), @fileData);
  {$ELSE}
  hFindFile := FindFirstFileW(PWideChar(strSearchDir), fileData);
  {$ENDIF}
  if (hFindFile <> INVALID_HANDLE_VALUE) then
  begin
    bSuccess := True;
    while bSuccess do
    begin
      if (fileData.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY = 0) then
      begin
        strFullPath:= strDir + WideString(fileData.cFileName);
        if (g_ProcessedFileList.IndexOf(strFullPath) = -1) then
          ProcessFile(pd3dDevice, PWideChar(strFullPath), pSettings);

        if pSettings.bOutputFilenameGiven // only process 1 file if this option is on
        then Break;
      end;
      {$IFDEF FPC}
      bSuccess := FindNextFileW(hFindFile, @fileData);
      {$ELSE}
      bSuccess := FindNextFileW(hFindFile, fileData);
      {$ENDIF}
      if pSettings.bUserAbort then Break;
    end;
    Windows.FindClose(hFindFile);
  end else
    WriteLn('File(s) not found.');
end;


function CheckMeshValidation(const pMesh: ID3DXMesh; out pMeshOut: ID3DXMesh; out ppAdjacency: PDWORD;
  bTopologicalAdjacency, bGeometricAdjacency: Boolean; const pOrigAdj: ID3DXBuffer): Boolean;
var
  hr: HRESULT;
  pAdjacencyIn: PDWORD;
  pAdjacencyAlloc: PDWORD;
  pErrorsAndWarnings: ID3DXBuffer;
  s: PAnsiChar;
label FAIL;
begin
  Result := True;
  pAdjacencyIn := nil;
  pAdjacencyAlloc := nil;

  if bTopologicalAdjacency or bGeometricAdjacency then
  begin
    //todo: Fill bug report on NEW DWORD[...] should be "	pNewAdjacency = new DWORD[pTempMesh->GetNumFaces() * 3];"
    // pAdjacencyAlloc = new DWORD[pMesh->GetNumFaces() * sizeof(DWORD)*3];
    GetMem(pAdjacencyAlloc, SizeOf(DWORD)*pMesh.GetNumFaces*3);
    pAdjacencyIn := pAdjacencyAlloc;
  end;

  if bTopologicalAdjacency then
  begin
    hr := pMesh.ConvertPointRepsToAdjacency(nil, pAdjacencyIn);
    if FAILED(hr) then
    begin
      WriteLn(WideFormat('ConvertPointRepsToAdjacency() failed: %s', [DXGetErrorString9(hr)]));
      Result := False;
      goto FAIL;
    end;
  end
  else if bGeometricAdjacency then
  begin
    hr := pMesh.GenerateAdjacency(g_cfEpsilon, pAdjacencyIn);
    if FAILED(hr) then
    begin
      WriteLn(WideFormat('GenerateAdjacency() failed: %s', [DXGetErrorString9(hr)]));
      Result := False;
      goto FAIL;
    end;
  end
  else if Assigned(pOrigAdj) then
  begin
    pAdjacencyIn := PDWORD(pOrigAdj.GetBufferPointer);
  end;

  hr := D3DXValidMesh(pMesh, pAdjacencyIn, @pErrorsAndWarnings);
  if (nil <> pErrorsAndWarnings) then
  begin
    s := PAnsiChar(pErrorsAndWarnings.GetBufferPointer);
    WriteLn(WideFormat('%s', [s]));
    SAFE_RELEASE(pErrorsAndWarnings);
  end;

  if FAILED(hr) then
  begin
    WriteLn(WideFormat('D3DXValidMesh() failed: %s.  Attempting D3DXCleanMesh()', [DXGetErrorString9(hr)]));

    hr := D3DXCleanMesh(D3DXCLEAN_SIMPLIFICATION, pMesh, pAdjacencyIn, pMeshOut, pAdjacencyIn, @pErrorsAndWarnings);

    if (nil <> pErrorsAndWarnings) then
    begin
      s := PAnsiChar(pErrorsAndWarnings.GetBufferPointer);
      WriteLn(WideFormat('%s', [s]));
    end;

    if FAILED(hr) then
    begin
      WriteLn(WideFormat('D3DXCleanMesh() failed: %s', [DXGetErrorString9(hr)]));
      Result := False;
      goto FAIL;
    end else
    begin
      WriteLn(WideFormat('D3DXCleanMesh() succeeded: %s', [DXGetErrorString9(hr)]));
    end;
  end else
  begin
    pMeshOut := pMesh;
    // (*pMeshOut).AddRef;
  end;
FAIL:
  SAFE_RELEASE(pErrorsAndWarnings);
  if (Result = False) then
  begin
    SAFE_DELETE(pAdjacencyAlloc);
    // SAFE_DELETE(pMeshOut); //todo: April: Bug report - SAFE_RELEASE
    pMeshOut:= nil;
  end;
  ppAdjacency := pAdjacencyIn;
end;


//--------------------------------------------------------------------------------------
var
  {static} s_fLastTime: Double = 0.0;

function UVAtlasCallback(fPercentDone: Single; lpUserContext: Pointer): HRESULT; stdcall;
var
  fTime: Double;
begin
  fTime := DXUTGetGlobalTimer.GetTime;

  if (fTime - s_fLastTime > 0.1) then
  begin
    WriteLn(WideFormat('%.2f%%   '#9, [fPercentDone*100]));
    s_fLastTime := fTime;
  end;

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
function PerVertexPRTIMT(const pMesh: ID3DXMesh; pPRTBuffer: ID3DXPRTBuffer;
  const cuNumCoeffs: LongWord; out ppIMTData: ID3DXBuffer): HRESULT;
var
  pPRTSignal: PSingle;
  uStride: LongWord;
  hr2: HRESULT;
label
  FAIL;
begin
  pPRTSignal := nil;

  if not (Assigned(pMesh) and {Assigned(ppIMTData) and }Assigned(pPRTBuffer)) then
  begin
    WriteLn('Error: pMesh, ppIMTData and pPRTBuffer must not be NULL');
    Result := D3DERR_INVALIDCALL;
    goto FAIL;
  end;
    
  if (pPRTBuffer.IsTexture) then
  begin
    WriteLn('Error: pPRTBuffer must be per-vertex');
    Result := D3DERR_INVALIDCALL;
    goto FAIL;
  end;

  uStride := pPRTBuffer.GetNumChannels * pPRTBuffer.GetNumCoeffs * SizeOf(Single);

  Result := pPRTBuffer.LockBuffer(0, pPRTBuffer.GetNumSamples, pPRTSignal);
  if FAILED(Result) then
  begin
    WriteLn(WideFormat('ID3DXPRTBuffer::LockBuffer() failed: %s', [DXGetErrorString9(Result)]));
    goto FAIL;
  end;

  Result := D3DXComputeIMTFromPerVertexSignal(pMesh, pPRTSignal, cuNumCoeffs, uStride, 0, nil, nil, ppIMTData);
  if FAILED(Result) then
  begin
    WriteLn(WideFormat('D3DXComputeIMTFromVertexSignal() failed: %s', [DXGetErrorString9(Result)]));
    goto FAIL;
  end;

FAIL:
  if Assigned(pPRTSignal) then
  begin
    hr2 := pPRTBuffer.UnlockBuffer;
    if FAILED(hr2) then
    begin
      WriteLn(WideFormat('ID3DXPRTBuffer::UnlockVertexBuffer() failed: %s!', [DXGetErrorString9(hr2)]));
    end;
    pPRTSignal := nil;
  end;
  SAFE_RELEASE(pPRTBuffer); //todo: ???????? - maybe handle this in Delphi differently
end;


//--------------------------------------------------------------------------------------
function PerVertexIMT(const pMesh: ID3DXMesh; const pDecl: TFVFDeclaration;
  usage: TD3DDeclUsage; usageIndex: DWORD; Crack: CD3DXCrackDecl;
  out ppIMTData: ID3DXBuffer): HRESULT;
var
  pfVertexData: PSingle;
  elmt: PD3DVertexElement9;
  uSignalDimension: LongWord;
  hr2: HRESULT;
label
  FAIL;
begin
  pfVertexData := nil;

  if not Assigned(pMesh) then // or not Assigned(ppIMTData)
  begin
    WriteLn('Error: some of pMesh and ppIMTData are == NULL');
    Result := D3DERR_INVALIDCALL;
    goto FAIL;
  end;

  elmt := GetDeclElement(@pDecl, usage, usageIndex);
  if (nil = elmt) then
  begin
    WriteLn('Error: Requested vertex data not found in mesh');
    Result := E_FAIL;
    goto FAIL;
  end;

  uSignalDimension := Crack.GetFields(elmt);

  Result := pMesh.LockVertexBuffer(D3DLOCK_NOSYSLOCK, Pointer(pfVertexData));
  if FAILED(Result) then
  begin
    WriteLn(WideFormat('ID3DXMesh.LockVertexBuffer() failed: %s', [DXGetErrorString9(Result)]));
    goto FAIL;
  end;

  Result := D3DXComputeIMTFromPerVertexSignal(pMesh, @PSingleArray(pfVertexData)[elmt.Offset],
                uSignalDimension, pMesh.GetNumBytesPerVertex, 0, nil, nil, ppIMTData);
  if FAILED(Result) then
  begin
    WriteLn(WideFormat('D3DXComputeIMTFromPerVertexSignal() failed: %s', [DXGetErrorString9(Result)]));
    goto FAIL;
  end;

FAIL:
  if Assigned(pfVertexData) then
  begin
    hr2 := pMesh.UnlockVertexBuffer;
    if FAILED(hr2) then
    begin
      WriteLn(WideFormat('pMesh.UnlockVertexBuffer() failed: %s!', [DXGetErrorString9(hr2)]));
    end;
    pfVertexData := nil;
  end;
end;


//--------------------------------------------------------------------------------------
function TextureSignalIMT(const pDevice: IDirect3DDevice9; const pMesh: ID3DXMesh;
  dwTextureIndex: DWORD; const szFilename: PWideChar; out ppIMTData: ID3DXBuffer): HRESULT;
var
  pTexture: IDirect3DTexture9;
begin
  if not Assigned(pMesh) or not Assigned(szFilename) then // or !ppIMTData)
  begin
    WriteLn('rror: some of pMesh, szFilename and ppIMTData are == NULL');
    Result := D3DERR_INVALIDCALL;
    Exit;
  end;

  Result := D3DXCreateTextureFromFileExW(pDevice, szFilename, D3DX_FROM_FILE, D3DX_FROM_FILE, 1, 0,
                                         D3DFMT_A32B32G32R32F, D3DPOOL_SCRATCH,
                                         D3DX_DEFAULT, D3DX_DEFAULT, 0, nil, nil, pTexture);
  if FAILED(Result) then
  begin
    WriteLn(WideFormat('Error: failed to load %s: %s', [szFilename, DXGetErrorString9(Result)]));
    Exit;
  end;

  Result := D3DXComputeIMTFromTexture(pMesh, pTexture, dwTextureIndex, 0, nil, nil, ppIMTData);
  if FAILED(Result) then
  begin
    WriteLn(WideFormat('D3DXComputeIMTFromTexture() failed: %s', [DXGetErrorString9(Result)]));
    Exit;
  end;
end;

//--------------------------------------------------------------------------------------
function PRTSignalIMT(const pMesh: ID3DXMesh; dwTextureIndex: DWORD; pSettings: PSettings;
  const cuNumCoeffs: LongWord; out ppIMTData: ID3DXBuffer): HRESULT;
var
  pPRTSignal: PSingle;
  pPRTBuffer: ID3DXPRTBuffer;
  cuDimension: LongWord;
  hr2: HRESULT;
label
  FAIL, DONE;
begin
  pPRTSignal := nil;
  if not Assigned(pMesh) or not Assigned(pSettings) then // or not Assigned(ppIMTData)
  begin
    WriteLn('Error: pMesh, pSettings and ppIMTData must not be NULL');
    Result := D3DERR_INVALIDCALL;
    goto FAIL;
  end;

  Result := D3DXLoadPRTBufferFromFileW(PWideChar(pSettings.szIMTInputFilename), pPRTBuffer);
  if FAILED(Result) then
  begin
    WriteLn(WideFormat('Error: failed to load %s: %s', [pSettings.szIMTInputFilename, DXGetErrorString9(Result)]));
    goto FAIL;
  end;

  if not pPRTBuffer.IsTexture then
  begin
    Result := PerVertexPRTIMT(pMesh, pPRTBuffer, cuNumCoeffs, ppIMTData);
    goto DONE;
  end;

  cuDimension := pPRTBuffer.GetNumChannels * pPRTBuffer.GetNumCoeffs;
  Result := pPRTBuffer.LockBuffer(0, pPRTBuffer.GetNumSamples, pPRTSignal);
  if FAILED(Result) then
  begin
    WriteLn(WideFormat('ID3DXPRTBuffer.LockBuffer() failed: %s', [DXGetErrorString9(Result)]));
    goto FAIL;
  end;

  Result := D3DXComputeIMTFromPerTexelSignal(pMesh, dwTextureIndex, pPRTSignal,
                pPRTBuffer.GetWidth, pPRTBuffer.GetHeight, cuNumCoeffs, cuDimension, 0, nil, nil, ppIMTData);
  if FAILED(Result) then
  begin
    WriteLn(WideFormat('D3DXComputeIMTFromPerTexelSignal() failed: %s', [DXGetErrorString9(Result)]));
    goto FAIL;
  end;

FAIL:
DONE:
  if Assigned(pPRTSignal) then
  begin
    hr2 := pPRTBuffer.UnlockBuffer;
    if FAILED(hr2) then
    begin
      WriteLn(WideFormat('"ID3DXPRTBuffer.UnlockVertexBuffer() failed: %s', [DXGetErrorString9(Result)]));
    end;
    pPRTSignal := nil;
  end;
  SAFE_RELEASE(pPRTBuffer);
end;


//--------------------------------------------------------------------------------------
function CopyUVs(const pMeshFrom: ID3DXMesh; FromUsage: TD3DDeclUsage; FromIndex: LongWord;
                 const pMeshTo: ID3DXMesh; ToUsage: TD3DDeclUsage; ToIndex: LongWord;
                 const pVertexRemapArray: ID3DXBuffer): HRESULT;
var
  declFrom: TFVFDeclaration;
  declTo: TFVFDeclaration;
  declCrackFrom: CD3DXCrackDecl;
  declCrackTo: CD3DXCrackDecl;
  pVBFrom: IDirect3DVertexBuffer9;
  pVBDataFrom: PChar;
  pVBTo: IDirect3DVertexBuffer9;
  pVBDataTo: PChar;
  pdwVertexMapping: PDWORD;
  NBPVFrom: DWORD;
  uNumVertsTo: Cardinal;
  NBPVTo: DWORD;
  viFrom: LongWord;
  uvFrom: TD3DXVector2;
  viTo: LongWord;
begin
  declCrackFrom:= CD3DXCrackDecl.Create;
  declCrackTo:= CD3DXCrackDecl.Create;
  pVBDataFrom := nil;
  pVBDataTo := nil;
  pdwVertexMapping := nil;
  if Assigned(pVertexRemapArray) then 
    pdwVertexMapping := PDWORD(pVertexRemapArray.GetBufferPointer);

  Result:= pMeshFrom.GetDeclaration(declFrom);
  if V_Failed(Result) then Exit;
  Result:= declCrackFrom.SetDeclaration(@declFrom);
  if V_Failed(Result) then Exit;

  Result:= pMeshTo.GetDeclaration(declTo);
  if V_Failed(Result) then Exit;
  Result:= declCrackTo.SetDeclaration(@declTo);
  if V_Failed(Result) then Exit;

  Result:= pMeshFrom.GetVertexBuffer(pVBFrom);
  if V_Failed(Result) then Exit;
  Result:= pVBFrom.Lock(0, 0, Pointer(pVBDataFrom), D3DLOCK_READONLY);
  if V_Failed(Result) then Exit;
  NBPVFrom := pMeshFrom.GetNumBytesPerVertex;
  declCrackFrom.SetStreamSource(0, pVBDataFrom, NBPVFrom);

  Result:= pMeshTo.GetVertexBuffer(pVBTo);
  if V_Failed(Result) then Exit;
  Result:= pVBTo.Lock(0, 0, Pointer(pVBDataTo), 0 );
  if V_Failed(Result) then Exit;
  uNumVertsTo := pMeshTo.GetNumVertices;
  NBPVTo := pMeshTo.GetNumBytesPerVertex;
  declCrackTo.SetStreamSource(0, Pointer(pVBDataTo), NBPVTo);

  for viTo := 0 to uNumVertsTo - 1 do
  begin
    // Use the vertex remap if supplied
    if Assigned(pdwVertexMapping)
    then viFrom := PDWordArray(pdwVertexMapping)[viTo]
    else viFrom := viTo;

    declCrackFrom.DecodeSemantic(FromUsage, FromIndex, viFrom, PSingle(@uvFrom), 2);
    declCrackTo.EncodeSemantic(ToUsage, ToIndex, viTo, PSingle(@uvFrom), 2);
  end;

  pVBFrom.Unlock;
  SAFE_RELEASE(pVBFrom);

  Result:= S_OK;
end;


//--------------------------------------------------------------------------------------
function ProcessFile(const pd3dDevice: IDirect3DDevice9; strFile: PWideChar; const pSettings: TSettings): HRESULT;
var
  pOrigMesh, pMesh, pMeshValid, pMeshResult, pTexResampleMesh: ID3DXMesh;
  pMaterials, pEffectInstances, pFacePartitioning, pVertexRemapArray: ID3DXBuffer;
  pIMTBuffer, pOrigAdj, pFalseEdges: ID3DXBuffer;
  pGutterHelper: ID3DXTextureGutterHelper;
  pOriginalTex, pResampledTex: IDirect3DTexture9;
  pIMTArray: PSingle;
  pAdjacency: PDWORD;
  pdwAttributeOut: PDWordArray;
  declResamp: TFVFDeclaration;
  decl: TFVFDeclaration;
  uLen: LongWord;
  dwNumMaterials, dwNumVerts, dwNumFaces: DWORD;
  stretchOut: Single;
  numchartsOut: LongWord;
  strResult, strResultTexture, szResampledTextureFile: WideString;
  szResampleTextureFileA, szResampledTextureFileA: PAnsiChar;
  declCrack: CD3DXCrackDecl;
  declElem: TD3DVertexElement9;
  pVertexData: Pointer;
  pGeneratedMaterials: array[0..COLOR_COUNT-1] of TD3DXMaterial;
  ustrLen, uPeriodPos: size_t;
  i: Integer;
  pdwChartMapping: PDWordArray;
  dwNumber: DWORD;
  pMaterialsStruct: PD3DXMaterial;
  pNormal: PD3DVertexElement9;
  normal: array[0..2] of Single;
  texcoords: array[0..1] of Single;
  strOutputFilename: array[0..MAX_PATH-1] of WideChar;
  TextureInfo: TD3DXImageInfo;
  index: DWORD;
  pDeclElement: PD3DVertexElement9;
  cdwAdjacencySize: DWORD;
  cdwFalseEdgesSize: DWORD;
  pFalseEdgesData: PDWORD;
type
  PD3DXMaterialArray = ^TD3DXMaterialArray;
  TD3DXMaterialArray = array[0..0] of TD3DXMaterial;
label FAIL;
begin
  declCrack:= CD3DXCrackDecl.Create;

  pIMTArray := nil;
  pAdjacency := nil;
  pdwAttributeOut := nil;
  numchartsOut := 0;
  szResampleTextureFileA := nil;
  szResampledTextureFileA := nil;
  pVertexData := nil;

  // add _result before the last period in the file name

  // wprintf( L"Processing file %s\n", strFile, strResult );
  WriteLn(WideFormat('Processing file %s', [strFile, strResult])); //todo: two parameters instead of single ????

  Result:= StringCchLength(strFile, 1024, ustrLen);
  if FAILED(Result) then
  begin
    WriteLn('Unable to get string length.');
    goto FAIL;
  end;

  uPeriodPos := ustrLen;
  for i := 0 to ustrLen - 1 do
    if (strFile[i] = '.') then uPeriodPos := i;

  strResult:= Copy(strFile, 0, uPeriodPos) + '_result' + (strFile + uPeriodPos);
  strResultTexture:= Copy(strFile, 0, uPeriodPos) + '_texture' + (strFile + uPeriodPos);

  Result:= D3DXLoadMeshFromXW(strFile,
                              D3DXMESH_32BIT or D3DXMESH_SYSTEMMEM,
                              pd3dDevice,
                              @pOrigAdj,
                              @pMaterials,
                              @pEffectInstances,
                              @dwNumMaterials,
                              pOrigMesh);

  if FAILED(Result) then
  begin
    WriteLn('Unable to open mesh');
    goto FAIL;
  end;

  Result:= pOrigMesh.GetDeclaration(decl);
  if FAILED(Result) then goto FAIL;
  uLen := D3DXGetDeclLength(@decl);
  pDeclElement := GetDeclElement(@decl, D3DDECLUSAGE_TEXCOORD, pSettings.nOutputTextureIndex);

  if ((pDeclElement <> nil) and (declCrack.GetFields(pDeclElement) < 2)) then
  begin
    WriteLn(WideFormat('D3DDECLUSAGE_TEXCOORD[%d] must have at least 2 components. '+
                       'Use /uvi to change the index', [pSettings.nOutputTextureIndex]));
    Result := E_FAIL;
    goto FAIL;
  end;

  if (pDeclElement = nil) then
  begin
    WriteLn('Adding texture coordinate slot to vertex decl.');
    if (uLen = MAX_FVF_DECL_SIZE) then
    begin
      WriteLn('Not enough room to store texture coordinates in mesh');
      Result := E_FAIL;
      goto FAIL;
    end;

    declElem.Stream := 0;
    declElem._Type := D3DDECLTYPE_FLOAT2;
    declElem.Method := D3DDECLMETHOD_DEFAULT;
    declElem.Usage := D3DDECLUSAGE_TEXCOORD;
    declElem.UsageIndex := pSettings.nOutputTextureIndex;

    AppendDeclElement(@declElem, decl);
  end;
  Result := declCrack.SetDeclaration(@decl);
  if FAILED(Result) then goto FAIL;

  Result := pOrigMesh.CloneMesh(D3DXMESH_32BIT or D3DXMESH_SYSTEMMEM,
                                @decl,
                                pd3dDevice,
                                pMesh);
  if FAILED(Result) then
  begin
    WriteLn('Unable to clone mesh.');
    goto FAIL;
  end;

  if (pSettings.bFileAdjacency) then
  begin
    WriteLn(WideFormat('Loading adjacency from file %s', [pSettings.szAdjacencyFilename]));
    SAFE_RELEASE(pOrigAdj);

    Result := LoadFile(pSettings.szAdjacencyFilename, pOrigAdj);
    if FAILED(Result) then
    begin
      WriteLn(WideFormat('Unable to load adjacency from file: %s!', [pSettings.szAdjacencyFilename]));
      goto FAIL;
    end;

    cdwAdjacencySize := 3*pMesh.GetNumFaces*SizeOf(DWORD);
    if (cdwAdjacencySize <> pOrigAdj.GetBufferSize) then
    begin
      WriteLn(WideFormat('Adjacency from file: %s is incorrect size: %d. Expected: %d!',
                [pSettings.szAdjacencyFilename,
                 pOrigAdj.GetBufferSize, cdwAdjacencySize]));
      goto FAIL;
    end;
  end;

  if not CheckMeshValidation(pMesh, pMeshValid, pAdjacency,
           pSettings.bTopologicalAdjacency, pSettings.bGeometricAdjacency, pOrigAdj) then
  begin
    WriteLn('Unable to clean mesh');
    goto FAIL;
  end;

  WriteLn(WideFormat('Face count: %d', [pMesh.GetNumFaces]));
  WriteLn(WideFormat('Vertex count: %d', [pMesh.GetNumVertices]));
  if (pSettings.maxcharts <> 0)
    then WriteLn(WideFormat('Max charts: %d', [pSettings.maxcharts]))
    else WriteLn(WideFormat('Max charts: Atlas will be parameterized based solely on stretch', []));
  WriteLn(WideFormat('Max stretch: %f', [pSettings.maxstretch]));
  WriteLn(WideFormat('Texture size: %d x %d', [pSettings.width, pSettings.height]));
  WriteLn(WideFormat('Gutter size: %f texels', [pSettings.gutter]));
  WriteLn(WideFormat('Updating UVs in mesh''s D3DDECLUSAGE_TEXCOORD[%d]', [pSettings.nOutputTextureIndex]));

  if (pSettings.bIMT) then
  begin
    if pSettings.bTextureSignal then
    begin
      WriteLn(WideFormat('Computing IMT from file %s', [pSettings.szIMTInputFilename]));
      Result := TextureSignalIMT(pd3dDevice, pMesh, 0, PWideChar(pSettings.szIMTInputFilename), pIMTBuffer);
    end
    else if pSettings.bPRTSignal then
    begin
      WriteLn(WideFormat('Computing IMT from file %s', [pSettings.szIMTInputFilename]));
      Result := PRTSignalIMT(pMesh, pSettings.nIMTInputTextureIndex, @pSettings, 3, pIMTBuffer);
    end else if pSettings.bVertexSignal then
    begin
      WriteLn(WideFormat('Computing IMT from %s, Index %d', [declCrack.DeclUsageToString(pSettings.VertexSignalUsage), pSettings.VertexSignalIndex]));
      Result := PerVertexIMT(pMesh, decl, pSettings.VertexSignalUsage, pSettings.VertexSignalIndex, @declCrack, pIMTBuffer);
    end else
    begin
      Result := E_FAIL;
      Assert(False);
    end;

    if FAILED(Result) then
    begin
      WriteLn(WideFormat('warn: IMT computation failed: %s', [DXGetErrorString9(Result)]));
      WriteLn('warn: proceeding w/out IMT...');
    end else
    begin
      pIMTArray := pIMTBuffer.GetBufferPointer;
    end;
  end;

  if (pSettings.bFalseEdges) then
  begin
    WriteLn(WideFormat('Loading false edges from file %s', [pSettings.szFalseEdgesFilename]));

    Result := LoadFile(pSettings.szFalseEdgesFilename, pFalseEdges);
    if FAILED(Result) then
    begin
      WriteLn(WideFormat('Unable to load false edges from file: %s!', [pSettings.szFalseEdgesFilename]));
      goto FAIL;
    end;
    cdwFalseEdgesSize := 3*pMeshValid.GetNumFaces*SizeOf(DWORD);
    if (cdwFalseEdgesSize <> pFalseEdges.GetBufferSize) then
    begin
      WriteLn(WideFormat('False edges from file: %s is incorrect size: %d. Expected: %d!',
                [pSettings.szFalseEdgesFilename,
                 pFalseEdges.GetBufferSize, cdwFalseEdgesSize]));
      goto FAIL;
    end;
  end;

  WriteLn('Executing D3DXUVAtlasCreate() on mesh...');

  if Assigned(pFalseEdges) then pFalseEdgesData := pFalseEdges.GetBufferPointer() else pFalseEdgesData := nil;

  Result := D3DXUVAtlasCreate(pMeshValid,
                              pSettings.maxcharts,
                              pSettings.maxstretch,
                              pSettings.width,
                              pSettings.height,
                              pSettings.gutter,
                              pSettings.nOutputTextureIndex,
                              pAdjacency,
                              pFalseEdgesData,
                              pIMTArray,
                              UVAtlasCallback,
                              0.0001,
                              nil,
                              D3DXUVATLAS_DEFAULT,
                              pMeshResult,
                              @pFacePartitioning,
                              @pVertexRemapArray,
                              @stretchOut,
                              @numchartsOut);

  if FAILED(Result) then
  begin
    WriteLn('UV Atlas creation failed: ');
    case Result of
      D3DXERR_INVALIDMESH: WriteLn('Non-manifold mesh');
    else
      if (numchartsOut <> 0) and (pSettings.maxcharts < Integer(numchartsOut)) then
        WriteLn(WideFormat('Minimum number of charts is %d', [numchartsOut]));
      WriteLn(WideFormat('Error code %s, check debug output for more detail', [DXGetErrorString9(Result)]));
      WriteLn(WideFormat('Try increasing the max number of charts or max stretch', []));
    end;
    goto FAIL;
  end;

  WriteLn(WideFormat('D3DXUVAtlasCreate() succeeded', []));
  WriteLn(WideFormat('Output # of charts: %d', [numchartsOut]));
  WriteLn(WideFormat('Output stretch: %f', [stretchOut]));

  if pSettings.bResampleTexture then
  begin
    WriteLn(WideFormat('Resampling texture %s using data from %s[%d]',
                       [pSettings.szResampleTextureFile,
                        TraceD3DDECLUSAGEtoString(pSettings.ResampleTextureUsage),
                        pSettings.ResampleTextureUsageIndex]));

    // Read the original texture from the file
    Result := D3DXCreateTextureFromFileExW(pd3dDevice, PWideChar(pSettings.szResampleTextureFile),
        D3DX_FROM_FILE, D3DX_FROM_FILE, 1, 0, D3DFMT_FROM_FILE, D3DPOOL_SCRATCH,
        D3DX_DEFAULT, D3DX_DEFAULT, 0, @TextureInfo, nil, pOriginalTex);
    if FAILED(Result) then
    begin
      WriteLn('Texture creation and loading failed: ');
      case Result of
        D3DERR_NOTAVAILABLE: WriteLn('This device does not support the queried technique.');
        D3DERR_OUTOFVIDEOMEMORY: WriteLn('Microsoft Direct3D does not have enough display memory to perform the operation.');
        D3DERR_INVALIDCALL: WriteLn('The method call is invalid. For example, a method''s parameter may have an invalid value.');
        D3DXERR_INVALIDDATA: WriteLn('The data is invalid.');
        E_OUTOFMEMORY: WriteLn('Out of memory');
      else
        WriteLn(WideFormat('Error code %s, check debug output for more detail', [DXGetErrorString9(Result)]));
      end;
      goto FAIL;
    end;

    // Create a new blank texture that is the same size
    Result := D3DXCreateTexture(pd3dDevice, TextureInfo.Width, TextureInfo.Height, 1, 0,
        TextureInfo.Format, D3DPOOL_SCRATCH, pResampledTex);
    if FAILED(Result) then
    begin
      WriteLn('Texture creation failed:');
      case Result of
        D3DERR_INVALIDCALL: WriteLn('The method call is invalid. For example, a method''s parameter may have an invalid value.'); 
        D3DERR_NOTAVAILABLE: WriteLn('This device does not support the queried technique.');
        D3DERR_OUTOFVIDEOMEMORY: WriteLn('Microsoft Direct3D does not have enough display memory to perform the operation.');
        E_OUTOFMEMORY: WriteLn('Out of memory');
      else
        WriteLn(WideFormat('Error code %s, check debug output for more detail', [DXGetErrorString9(Result)]));
      end;
      goto FAIL;
    end;

    // Get the decl of the original mesh
    Result := pMeshResult.GetDeclaration(declResamp);
    if FAILED(Result) then goto FAIL;
    uLen := D3DXGetDeclLength(@declResamp);

    // Ensure the decl has a D3DDECLUSAGE_TEXCOORD:0
    if (nil = GetDeclElement(@declResamp, D3DDECLUSAGE_TEXCOORD, 0)) then
    begin
      if (uLen = MAX_FVF_DECL_SIZE) then
      begin
        WriteLn('Not enough room to store texture coordinates in mesh');
        Result := E_FAIL;
        goto FAIL;
      end;

      declElem.Stream := 0;
      declElem._Type := D3DDECLTYPE_FLOAT2;
      declElem.Method := D3DDECLMETHOD_DEFAULT;
      declElem.Usage := D3DDECLUSAGE_TEXCOORD;
      declElem.UsageIndex := 0;

      AppendDeclElement(@declElem, declResamp);
    end;

    // Ensure the decl has a D3DDECLUSAGE_TEXCOORD:1
    if (nil = GetDeclElement(@declResamp, D3DDECLUSAGE_TEXCOORD, 1)) then
    begin
      if (uLen = MAX_FVF_DECL_SIZE) then
      begin
        WriteLn('Not enough room to store texture coordinates in mesh');
        Result := E_FAIL;
        goto FAIL;
      end;

      declElem.Stream := 0;
      declElem._Type := D3DDECLTYPE_FLOAT2;
      declElem.Method := D3DDECLMETHOD_DEFAULT;
      declElem.Usage := D3DDECLUSAGE_TEXCOORD;
      declElem.UsageIndex := 1;

      AppendDeclElement(@declElem, declResamp);
    end;

    // Clone the original mesh to ensure it has 2 D3DDECLUSAGE_TEXCOORD slots
    Result := pMeshResult.CloneMesh(D3DXMESH_32BIT or D3DXMESH_SYSTEMMEM,
                                    @declResamp,
                                    pd3dDevice,
                                    pTexResampleMesh);
    if FAILED(Result) then
    begin
      WriteLn('Unable to clone mesh.');
      goto FAIL;
    end;

    // Put new UVAtlas parameterization in D3DDECLUSAGE_TEXCOORD:0
    CopyUVs(pMeshResult, D3DDECLUSAGE_TEXCOORD, pSettings.nOutputTextureIndex,  // from
            pTexResampleMesh, D3DDECLUSAGE_TEXCOORD, 0, nil);  // to

    // Put original texture parameterization to D3DDECLUSAGE_TEXCOORD:1
    CopyUVs(pOrigMesh, pSettings.ResampleTextureUsage, pSettings.ResampleTextureUsageIndex, // from
            pTexResampleMesh, D3DDECLUSAGE_TEXCOORD, 1, pVertexRemapArray); // to

    // Create a gutter helper
    Result := D3DXCreateTextureGutterHelper(TextureInfo.Width, TextureInfo.Height, pTexResampleMesh, pSettings.gutter, pGutterHelper);
    if FAILED(Result) then
    begin
      WriteLn('Gutter Helper creation failed:');
      case Result of
        D3DERR_INVALIDCALL: WriteLn('The method call is invalid. For example, a method''s parameter may have an invalid value.');
        E_OUTOFMEMORY: WriteLn('Out of memory');
      else
        WriteLn(WideFormat('Error code %s, check debug output for more detail', [DXGetErrorString9(Result)]));
      end;
      goto FAIL;
    end;

    // Call ResampleTex() to convert the texture from the original parameterization in D3DDECLUSAGE_TEXCOORD:1
    // to the new UVAtlas parameterization in D3DDECLUSAGE_TEXCOORD:0
    Result := pGutterHelper.ResampleTex(pOriginalTex, pTexResampleMesh, D3DDECLUSAGE_TEXCOORD, 1, pResampledTex);
    if FAILED(Result) then
    begin
      WriteLn('Gutter Helper texture resampling failed:');
      case Result of
        D3DERR_INVALIDCALL: WriteLn('The method call is invalid. For example, a method''s parameter may have an invalid value.');
        E_OUTOFMEMORY: WriteLn('Out of memory');
      else
        WriteLn(WideFormat('Error code %s, check debug output for more detail', [DXGetErrorString9(Result)]));
      end;
      goto FAIL;
    end;

    // Create the filepath string
    ustrLen := Length(pSettings.szResampleTextureFile);
    uPeriodPos := ustrLen;
    for i := 0 to ustrLen - 1 do
      if (pSettings.szResampleTextureFile)[i] = '.' then uPeriodPos := i;

    szResampledTextureFile:= Copy(pSettings.szResampleTextureFile, 0, uPeriodPos) + '_resampled' + (strFile + uPeriodPos);
    WriteLn(WideFormat('Writing resampled texture to %s', [szResampledTextureFile]));

    // Save the new resampled texture
    Result := D3DXSaveTextureToFileW(PWideChar(szResampledTextureFile), TextureInfo.ImageFileFormat, pResampledTex, nil);
    if FAILED(Result) then
    begin
      WriteLn('Saving texture to file failed:');
      case Result of
        D3DERR_INVALIDCALL: WriteLn('The method call is invalid. For example, a method''s parameter may have an invalid value.');
      else
        WriteLn(WideFormat('Error code %s, check debug output for more detail', [DXGetErrorString9(Result)]));
      end;
      goto FAIL;
    end;
  end;

  if pSettings.bColorMesh then
  begin
    for i := 0 to COLOR_COUNT - 1 do
    begin
      pGeneratedMaterials[i].MatD3D.Ambient.a := 0;
      pGeneratedMaterials[i].MatD3D.Ambient.r := ColorList[i][0];
      pGeneratedMaterials[i].MatD3D.Ambient.g := ColorList[i][1];
      pGeneratedMaterials[i].MatD3D.Ambient.b := ColorList[i][2];

      pGeneratedMaterials[i].MatD3D.Diffuse := pGeneratedMaterials[i].MatD3D.Ambient;

      pGeneratedMaterials[i].MatD3D.Power := 0;

      pGeneratedMaterials[i].MatD3D.Emissive.a := 0;
      pGeneratedMaterials[i].MatD3D.Emissive.r := 0;
      pGeneratedMaterials[i].MatD3D.Emissive.g := 0;
      pGeneratedMaterials[i].MatD3D.Emissive.b := 0;

      pGeneratedMaterials[i].MatD3D.Specular.a := 0;
      pGeneratedMaterials[i].MatD3D.Specular.r := 0.5;
      pGeneratedMaterials[i].MatD3D.Specular.g := 0.5;
      pGeneratedMaterials[i].MatD3D.Specular.b := 0.5;

      pGeneratedMaterials[i].pTextureFilename := nil;
    end;

    Result := pMeshResult.LockAttributeBuffer(D3DLOCK_NOSYSLOCK, PDWORD(pdwAttributeOut));
    if FAILED(Result) then
    begin
      WriteLn('Unable to lock result attribute buffer.');
      goto FAIL;
    end;

    pdwChartMapping := PDWordArray(pFacePartitioning.GetBufferPointer);

    dwNumFaces := pMeshResult.GetNumFaces;

    for i := 0 to dwNumFaces - 1 do
    begin
      pdwAttributeOut[i] := pdwChartMapping[i] mod COLOR_COUNT;
    end;

    pdwAttributeOut := nil;
    Result := pMeshResult.UnlockAttributeBuffer;
    if FAILED(Result) then goto FAIL;
  end;

  if pSettings.bOverwrite then
  begin
    StringCchCopy(strOutputFilename, MAX_PATH, strFile);
  end
  else if pSettings.bOutputFilenameGiven then
  begin
    StringCchCopy(strOutputFilename, MAX_PATH, PWideChar(pSettings.szOutputFilename));
  end
  else
  begin
    StringCchCopy(strOutputFilename, MAX_PATH, PWideChar(strResult));
  end;

  if (pSettings.bResampleTexture and not pSettings.bColorMesh{ and szResampledTextureFile}) then
  begin
    GetMem(szResampleTextureFileA, SizeOf(AnsiChar)*(ustrLen + 1));
    GetMem(szResampledTextureFileA, SizeOf(AnsiChar)*(ustrLen + 12));

    WideCharToMultiByte(CP_ACP, 0, PWideChar(pSettings.szResampleTextureFile), -1, szResampleTextureFileA, ustrLen*SizeOf(AnsiChar), nil, nil);
    szResampleTextureFileA[ustrLen] := #0;

    WideCharToMultiByte(CP_ACP, 0, PWideChar(szResampledTextureFile), -1, szResampledTextureFileA, (ustrLen + 11)*SizeOf(AnsiChar), nil, nil);
    szResampledTextureFileA[ustrLen + 11] := #0;

    for index := 0 to dwNumMaterials - 1 do
    begin
      if (0 = StrComp(PD3DXMaterialArray(pMaterials.GetBufferPointer)[index].pTextureFilename, szResampleTextureFileA)) then 
      begin
        PD3DXMaterialArray(pMaterials.GetBufferPointer)[index].pTextureFilename := szResampledTextureFileA;
      end;
    end;
  end;

  if pSettings.bColorMesh then dwNumber:= COLOR_COUNT else dwNumber:= dwNumMaterials;
  if pSettings.bColorMesh then pMaterialsStruct:= @pGeneratedMaterials else pMaterialsStruct:= PD3DXMaterial(pMaterials.GetBufferPointer);

  g_ProcessedFileList.Add(strOutputFilename);
  Result := D3DXSaveMeshToXW(strOutputFilename,
                             pMeshResult,
                             nil,
                             pMaterialsStruct,
                             nil,
                             dwNumber,
                             D3DXF_FILEFORMAT_TEXT);

  if FAILED(Result) then
  begin
    WriteLn('Unable to save result mesh.');
    goto FAIL;
  end;

  if pSettings.bOutputTexture then
  begin
    Result := pMeshResult.LockVertexBuffer(D3DLOCK_NOSYSLOCK, pVertexData);
    if FAILED(Result) then
    begin
      WriteLn('Unable to lock result vertex buffer.');
      goto FAIL;
    end;

    Result := declCrack.SetStreamSource(0, pVertexData, 0);
    if FAILED(Result) then goto FAIL;

    dwNumVerts := pMeshResult.GetNumVertices;

    pNormal := declCrack.GetSemanticElement(D3DDECLUSAGE_NORMAL, 0);
        
    normal[0] := 0;
    normal[1] := 0;
    normal[2] := 1;

    for i := 0 to dwNumVerts - 1 do
    begin
      declCrack.DecodeSemantic(D3DDECLUSAGE_TEXCOORD, pSettings.nOutputTextureIndex, i, @texcoords, 2);
      declCrack.EncodeSemantic(D3DDECLUSAGE_POSITION, pSettings.nOutputTextureIndex, i, @texcoords, 2);
      if Assigned(pNormal) then declCrack.Encode(pNormal, i, @normal, 3);
    end;

    pVertexData := nil;

    Result := pMeshResult.UnlockVertexBuffer;
    if FAILED(Result) then goto FAIL;

    Result := D3DXSaveMeshToXW(PWideChar(strResultTexture),
                               pMeshResult,
                               nil,
                               pMaterialsStruct,
                               nil,
                               dwNumber,
                               D3DXF_FILEFORMAT_TEXT);
    if FAILED(Result) then
    begin
      WriteLn('Unable to save result mesh.');
      goto FAIL;
    end;
  end;

  WriteLn(WideFormat('Output mesh with new UV atlas: %s', [strOutputFilename]));
  if pSettings.bOutputTexture then
    WriteLn(WideFormat('Output UV space mesh: %s', [strResultTexture]));

FAIL:
  if FAILED(Result) then
  begin
    WriteLn(WideFormat('Failure code: %s', [DXGetErrorString9(Result)]));
  end;

  if Assigned(pVertexData) then
  begin
    pMeshResult.UnlockVertexBuffer;
    pVertexData := nil;
  end;

  if Assigned(pdwAttributeOut) then
  begin
    pMeshResult.UnlockAttributeBuffer;
    pdwAttributeOut := nil;
  end;

  SAFE_RELEASE(pOrigMesh);
  SAFE_RELEASE(pMesh);
  SAFE_RELEASE(pMeshValid);
  SAFE_RELEASE(pMeshResult);
  SAFE_RELEASE(pTexResampleMesh);
  SAFE_RELEASE(pGutterHelper);
  SAFE_RELEASE(pOriginalTex);
  SAFE_RELEASE(pResampledTex);
  SAFE_RELEASE(pMaterials);
  SAFE_RELEASE(pEffectInstances);
  SAFE_RELEASE(pOrigAdj);
  SAFE_RELEASE(pFalseEdges);
  SAFE_RELEASE(pFacePartitioning);
  SAFE_RELEASE(pVertexRemapArray);
  FreeMem(szResampleTextureFileA);
  FreeMem(szResampledTextureFileA);

  if pSettings.bGeometricAdjacency or pSettings.bTopologicalAdjacency
  then SAFE_DELETE(pAdjacency);

  declCrack.Free;
end;

function GetConsoleWindow(): HWND; stdcall; external kernel32;


//--------------------------------------------------------------------------------------
function CreateNULLRefDevice: IDirect3DDevice9;
var
  hr: HRESULT;
  pD3D: IDirect3D9;
  Mode: TD3DDisplayMode;
  pp: TD3DPresentParameters;
  pd3dDevice: IDirect3DDevice9;
begin
  Result:= nil;

  pD3D := Direct3DCreate9( D3D_SDK_VERSION);
  if (pD3D = nil) then Exit;

  pD3D.GetAdapterDisplayMode(0, Mode);

  ZeroMemory(@pp, SizeOf(TD3DPresentParameters));
  pp.BackBufferWidth  := 1;
  pp.BackBufferHeight := 1;
  pp.BackBufferFormat := Mode.Format;
  pp.BackBufferCount  := 1;
  pp.SwapEffect       := D3DSWAPEFFECT_COPY;
  pp.Windowed         := True;

  hr := pD3D.CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_NULLREF, GetConsoleWindow,
                          D3DCREATE_HARDWARE_VERTEXPROCESSING, @pp, pd3dDevice);
  pD3D := nil;
  if FAILED(hr) or (pd3dDevice = nil) then Exit;

  Result:= pd3dDevice;
end;


//--------------------------------------------------------------------------------------
procedure DisplayUsage;
begin
  WriteLn;
  WriteLn('UVAtlas - a command line tool for generating UV Atlases');
  WriteLn;
  WriteLn('Usage: UVAtlas.exe [options] [filename1] [filename2] ...');
  WriteLn;
  WriteLn('where:');
  WriteLn;
  WriteLn('  [/n #]'#9'Specifies the maximum number of charts to generate');
  WriteLn('  '#9#9'Default is 0 meaning the atlas will be parameterized based solely on stretch');
  WriteLn('  '#9#9'solely on stretch');
  WriteLn('  [/st #.##]'#9'Specifies the maximum amount of stretch, valid range is [0-1]');
  WriteLn('  '#9#9'Default is 0.16667. 0.0 means do not stretch; 1.0 means any');
  WriteLn('  '#9#9'amount of stretching is allowed.');
  WriteLn('  [/g #.##]'#9'Specifies the gutter width (default 2).');
  WriteLn('  [/w #]'#9'Specifies the texture width (default 512).');
  WriteLn('  [/h #]'#9'Specifies the texture height (default 512).');
  WriteLn('  [/uvi #]'#9'Specifies the output D3DDECLUSAGE_TEXCOORD index for the');
  WriteLn('  '#9#9'UVAtlas data (default 0).');
  WriteLn('  [/ta]'#9#9'Generate topological adjacency, where triangles are marked');
  WriteLn('  '#9#9'adjacent if they share edge vertices. Mutually exclusive with');
  WriteLn('  '#9#9'/ga & /fa.');
  WriteLn('  [/ga]'#9#9'Generate geometric adjacency, where triangles are marked');
  WriteLn('  '#9#9'adjacent if edge vertices are positioned within 1e-5 of each');
  WriteLn('  '#9#9'other. Mutually exclusive with /ta & /fa.');
  WriteLn('  [/fa file]'#9'Load adjacency array entries directly into memory from');
  WriteLn('  '#9#9'a binary file. Mutually exclusive with /ta & /ga.');
  WriteLn('  [/fe file]'#9'Load "False Edge" adjacency array entries directly into');
  WriteLn('  '#9#9'memory from a binary file. A non-false edge is indicated by -1,');
  WriteLn('  '#9#9'while a false edge is indicated by any other value, e.g. 0 or');
  WriteLn('  '#9#9'the original adjacency value. This enables the parameterization');
  WriteLn('  '#9#9'of meshes containing quads and higher order n-gons, and the');
  WriteLn('  '#9#9'internal edges of each n-gon will not be cut during the');
  WriteLn('  '#9#9'parameterization process.');
  WriteLn('  [/ip file]'#9'Calculate the Integrated Metric Tensor (IMT) array for the mesh');
  WriteLn('  '#9#9'using a PRT buffer in file.');
  WriteLn('  [/it file]'#9'Calculate the IMT for the mesh using a texture map in file.');
  WriteLn('  [/iv usage]'#9'Calculate the IMT for the mesh using a per-vertex data from the');
  WriteLn('  '#9#9'mesh. The usage parameter lets you select which part of the');
  WriteLn('  '#9#9'mesh to use (default COLOR). It must be one of NORMAL, COLOR,');
  WriteLn('  '#9#9'TEXCOORD, TANGENT, or BINORMAL.');
  WriteLn('  [/t]'#9#9'Create a separate mesh in u-v space (appending _texture).');
  WriteLn('  [/c]'#9#9'Modify the materials of the mesh to graphically show');
  WriteLn('  '#9#9'which chart each triangle is in.');
  WriteLn('  [/rt file]'#9'Resamples a texture using the new UVAtlas parameterization.');
  WriteLn('  '#9#9'The resampled texture is saved to a filename with \"_resampled\"');
  WriteLn('  '#9#9'appended. Defaults to reading old texture parameterization from');
  WriteLn('  '#9#9'D3DDECLUSAGE_TEXCOORD[0] in original mesh Use /rtu and /rti to');
  WriteLn('  '#9#9'override this.');
  WriteLn('  [/rtu usage]'#9'Specifies the vertex data usage for texture resampling (default');
  WriteLn('  '#9#9'TEXCOORD). It must be one of NORMAL, POSITION, COLOR, TEXCOORD,');
  WriteLn('  '#9#9'TANGENT, or BINORMAL.');
  WriteLn('  [/rti #]'#9'Specifies the usage index for texture resampling (default 0).');
  WriteLn('  [/o file]'#9'Output mesh filename.  Defaults to a filename with \"_result\"');
  WriteLn('  '#9#9'appended Using this option disables batch processing.');
  WriteLn('  [/f]'#9#9'Overwrite original file with output (default off).');
  WriteLn('  '#9#9'Mutually exclusive with /o.');
  WriteLn('  [/s]'#9#9'Search sub-directories for files (default off).');
  WriteLn('  [filename*]'#9'Specifies the files to generate atlases for.');
  WriteLn('  '#9#9'Wildcards and quotes are supported.');
end;


//--------------------------------------------------------------------------------------
function TraceD3DDeclUsageToString(u: TD3DDeclUsage): PWideChar;
begin
  case u of
    D3DDECLUSAGE_POSITION:     Result:= 'D3DDECLUSAGE_POSITION';
    D3DDECLUSAGE_BLENDWEIGHT:  Result:= 'D3DDECLUSAGE_BLENDWEIGHT';
    D3DDECLUSAGE_BLENDINDICES: Result:= 'D3DDECLUSAGE_BLENDINDICES';
    D3DDECLUSAGE_NORMAL:       Result:= 'D3DDECLUSAGE_NORMAL';
    D3DDECLUSAGE_PSIZE:        Result:= 'D3DDECLUSAGE_PSIZE';
    D3DDECLUSAGE_TEXCOORD:     Result:= 'D3DDECLUSAGE_TEXCOORD';
    D3DDECLUSAGE_TANGENT:      Result:= 'D3DDECLUSAGE_TANGENT';
    D3DDECLUSAGE_BINORMAL:     Result:= 'D3DDECLUSAGE_BINORMAL';
    D3DDECLUSAGE_TESSFACTOR:   Result:= 'D3DDECLUSAGE_TESSFACTOR';
    D3DDECLUSAGE_POSITIONT:    Result:= 'D3DDECLUSAGE_POSITIONT';
    D3DDECLUSAGE_COLOR:        Result:= 'D3DDECLUSAGE_COLOR';
    D3DDECLUSAGE_FOG:          Result:= 'D3DDECLUSAGE_FOG';
    D3DDECLUSAGE_DEPTH:        Result:= 'D3DDECLUSAGE_DEPTH';
    D3DDECLUSAGE_SAMPLE:       Result:= 'D3DDECLUSAGE_SAMPLE';
  else
    Result:= 'D3DDECLUSAGE Unknown';
  end;
end;


//--------------------------------------------------------------------------------------
function LoadFile(szFile: WideString; out ppBuffer: ID3DXBuffer): HRESULT;
var
  hFile: THandle;
  cdwFileSize: DWORD;
  dwRead: DWORD;
const
  INVALID_FILE_ATTRIBUTES = DWORD(-1);
begin
  hFile := 0;
  ppBuffer := nil;
  Result := E_FAIL;

  try
    if (GetFileAttributesW(PWideChar(szFile)) = INVALID_FILE_ATTRIBUTES) then Exit;

    hFile := CreateFileW(PWideChar(szFile), GENERIC_READ, 0, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL or FILE_FLAG_SEQUENTIAL_SCAN, 0);
    if (hFile = 0) then Exit;

    cdwFileSize := GetFileSize(hFile, nil);
    if (INVALID_FILE_SIZE = cdwFileSize) then Exit;

    Result := D3DXCreateBuffer(cdwFileSize, ppBuffer);
    if FAILED(Result) then Exit;

    ReadFile(hFile, ppBuffer.GetBufferPointer()^, cdwFileSize, dwRead, nil);

    if (cdwFileSize <> dwRead) then
    begin
      ppBuffer := nil;
      Result := E_FAIL;
      Exit;
    end;

    Result := S_OK;
  finally
    if (hFile <> 0) then CloseHandle(hFile);
  end;
end;

end.

