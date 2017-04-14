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
 *  $Id: GetDXVer.dpr,v 1.7 2005/06/30 19:49:00 clootie Exp $
 *----------------------------------------------------------------------------*)

{$I DirectX.inc}

program GetDXVer;

{$R 'GetDXVer.res' 'GetDXVer.rc'}

uses
  SysUtils,
  Windows,
  GetDXVerUnit in 'GetDXVerUnit.pas';

//-----------------------------------------------------------------------------
// Desc: Entry point to the program. Initializes everything, and pops
//       up a message box with the results of the GetDXVersion call
//-----------------------------------------------------------------------------
var
  hr: HRESULT;
  strResult: String;
  dwDirectXVersion: DWORD = 0;
  strDirectXVersion: String;
begin
  hr := GetDXVersion(dwDirectXVersion, strDirectXVersion);
  if SUCCEEDED(hr) then
  begin
    if (dwDirectXVersion > 0)
    then strResult := Format('DirectX %s installed', [strDirectXVersion])
    else strResult := 'DirectX not installed';
  end else
    strResult := 'Unknown version of DirectX installed';

  MessageBox(0, PChar(strResult), 'DirectX Version:', MB_OK or MB_ICONINFORMATION);
end.
