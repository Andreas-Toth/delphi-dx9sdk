(*----------------------------------------------------------------------------*
 *  Direct3D sample from DirectX 9.0 SDK August 2006                          *
 *  Delphi adaptation by Alexey Barkovoy (e-mail: directx@clootie.ru)         *
 *                                                                            *
 *  Supported compilers: Delphi 5,6,7,9; FreePascal 2.0                       *
 *                                                                            *
 *  Latest version can be downloaded from:                                    *
 *     http://www.clootie.ru                                                  *
 *     http://sourceforge.net/projects/delphi-dx9sdk                          *
 *----------------------------------------------------------------------------*
 *  $Id: Direct3D9Ex.dpr,v 1.2 2006/10/22 22:00:47 clootie Exp $
 *----------------------------------------------------------------------------*)

{$I DirectX.inc}

program D3D9ExSample;

uses                      
  SysUtils,
  D3D9ExUnit in 'D3D9ExUnit.pas',
  BackgroundThread in 'BackgroundThread.pas';

begin
  ExitCode := WinMain();
end.
