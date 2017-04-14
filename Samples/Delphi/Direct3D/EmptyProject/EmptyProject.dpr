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
 *  $Id: EmptyProject.dpr,v 1.17 2007/02/05 22:21:05 clootie Exp $
 *----------------------------------------------------------------------------*)

{$I DirectX.inc}

program EmptyProject;

{$R 'EmptyProject.res' 'EmptyProject.rc'}

uses
  SysUtils,
  Direct3D9,
  Windows,
  DXUT,
  EmptyUnit in 'EmptyUnit.pas';

//--------------------------------------------------------------------------------------
// Entry point to the program. Initializes everything and goes into a message processing
// loop. Idle time is used to render the scene.
//--------------------------------------------------------------------------------------
begin
  // Set the callback functions
  DXUTSetCallbackDeviceCreated(OnCreateDevice);
  DXUTSetCallbackDeviceReset(OnResetDevice);
  DXUTSetCallbackDeviceLost(OnLostDevice);
  DXUTSetCallbackDeviceDestroyed(OnDestroyDevice);
  DXUTSetCallbackMsgProc(MsgProc);
  DXUTSetCallbackFrameRender(OnFrameRender);
  DXUTSetCallbackFrameMove(OnFrameMove);

  // TODO: Perform any application-level initialization here

  // Initialize DXUT and create the desired Win32 window and Direct3D device for the application
  DXUTInit(True, True, True); // Parse the command line, handle the default hotkeys, and show msgboxes
  DXUTSetCursorSettings(True, True); // Show the cursor and clip it when in full screen
  DXUTCreateWindow('EmptyProject');
  DXUTCreateDevice(D3DADAPTER_DEFAULT, true, 640, 480, IsDeviceAcceptable, ModifyDeviceSettings);

  // Start the render loop
  DXUTMainLoop;

  // TODO: Perform any application-level cleanup here

  ExitCode:= DXUTGetExitCode;

  DXUTFreeState;
end.
