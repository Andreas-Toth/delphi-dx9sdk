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
 *  $Id: UVAtlas.dpr,v 1.11 2007/02/05 22:21:13 clootie Exp $
 *----------------------------------------------------------------------------*)

{$APPTYPE CONSOLE}
{$I DirectX.inc}

program UVAtlas;

uses
  Classes,
  SysUtils,
  Direct3D9,
  Windows,
  StrSafe,
  DXUT,
  DXUTmisc, 
  UVAtlasUnit in 'UVAtlasUnit.pas';

var
  nRet: Integer;
  pd3dDevice: IDirect3DDevice9;
  settings: TSettings;

label
  LCleanup;
var
  i: Integer;
  strParamFilename: WideString;
  strDir: array[0..MAX_PATH-1] of WideChar;
  strFile: array[0..MAX_PATH-1] of WideChar;
  pFilePart: PWideChar;
  dwWrote: DWORD;
begin
  nRet := 0;
  pd3dDevice := nil;
  ZeroMemory(@settings, SizeOf(TSettings));
  settings.bOverwrite := False;
  settings.bOutputFilenameGiven := False;
  // settings.szOutputFilename[0] := #0;
  settings.bUserAbort := False;
  settings.bSubDirs := False;
  settings.bTopologicalAdjacency := False;
  settings.bGeometricAdjacency   := False;
  settings.bFileAdjacency        := False;
  // settings.szAdjacencyFilename[0]:= #0;

  settings.bFalseEdges           := False;
  // settings.szFalseEdgesFilename[0]:= #0;

  settings.maxcharts := 0;
  settings.maxstretch := 1 / 6.0;
  settings.gutter := 2.0;
  settings.width := 512;
  settings.height := 512;
  settings.bOutputTexture := False;
  settings.bColorMesh := False;
  settings.nOutputTextureIndex := 0;

  settings.nIMTInputTextureIndex := 0;
  settings.bIMT := False;
  settings.bTextureSignal := False;
  settings.bPRTSignal := False;
  settings.bVertexSignal := False;
  settings.VertexSignalUsage := D3DDECLUSAGE_COLOR;
  settings.VertexSignalIndex := 0;
  settings.szIMTInputFilename := '';

  settings.bResampleTexture := False;
  settings.ResampleTextureUsage := D3DDECLUSAGE_TEXCOORD;
  settings.ResampleTextureUsageIndex := 0;
  settings.szResampleTextureFile := '';

  settings.aFiles := nil;

  if not ParseCommandLine(settings) then
  begin
    nRet := 0;
    goto LCleanup;
  end;

  DXUTGetGlobalTimer.Start;

  // Create NULLREF device
  pd3dDevice := CreateNullRefDevice;
  if (pd3dDevice = nil) then
  begin
    WriteLn('Error: Can not create NULLREF Direct3D device');
    nRet := 1;
    goto LCleanup;
  end;

  for i := 0 to Length(settings.aFiles) - 1 do
  begin
    strParamFilename := settings.aFiles[i];
    //wprintf( L"Processing command line arg filename '%s'\n", strArgFilename );

    // For this cmd line arg, extract the full dir & filename
    dwWrote := GetFullPathNameW(PWideChar(strParamFilename), MAX_PATH, strDir, pFilePart);
    if (dwWrote > 1) and Assigned(pFilePart) then
    begin
      StringCchCopy(strFile, MAX_PATH, pFilePart);
      pFilePart^ := #0;
    end;

    if settings.bSubDirs
    then SearchSubdirsForFile(pd3dDevice, strDir, strFile, settings)
    else SearchDirForFile(pd3dDevice, strDir, strFile, settings);

    if settings.bUserAbort then Break;
  end;

LCleanup:
  WriteLn;

  // Cleanup
  settings.aFiles := nil;
  pd3dDevice := nil;

  ExitCode:= nRet;
end.
