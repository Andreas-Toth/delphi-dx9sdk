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
 *  $Id: MultiAnimation.dpr,v 1.6 2007/02/05 22:21:10 clootie Exp $
 *----------------------------------------------------------------------------*)

{$I DirectX.inc}

program MultiAnimation;

{$R 'MultiAnimation.res' 'MultiAnimation.rc'}
{%File 'skin.vsh'}
{%File 'MultiAnimation.fx'}

uses
  SysUtils,
  Direct3D9,
  DirectSound,
  Windows,
  DXUT,
  MultiAnimationUnit in 'MultiAnimationUnit.pas',
  MultiAnimationLib in 'MultiAnimationLib.pas',
  Tiny in 'Tiny.pas';

//--------------------------------------------------------------------------------------
// Entry point to the program. Initializes everything and goes into a message processing
// loop. Idle time is used to render the scene.
//--------------------------------------------------------------------------------------
begin
  CreateCustomDXUTobjects;

  // Set the callback functions. These functions allow DXUT to notify
  // the application about device changes, user input, and windows messages.  The
  // callbacks are optional so you need only set callbacks for events you're interested
  // in. However, if you don't handle the device reset/lost callbacks then the sample
  // framework won't be able to reset your device since the application must first
  // release all device resources before resetting.  Likewise, if you don't handle the
  // device created/destroyed callbacks then DXUT won't be able to
  // recreate your device resources.
  DXUTSetCallbackDeviceCreated(OnCreateDevice);
  DXUTSetCallbackDeviceReset(OnResetDevice);
  DXUTSetCallbackDeviceLost(OnLostDevice);
  DXUTSetCallbackDeviceDestroyed(OnDestroyDevice);
  DXUTSetCallbackMsgProc(MsgProc);
  DXUTSetCallbackKeyboard(KeyboardProc);
  DXUTSetCallbackFrameRender(OnFrameRender);
  DXUTSetCallbackFrameMove(OnFrameMove);

  // Show the cursor and clip it when in full screen
  DXUTSetCursorSettings(True, True);

  InitApp;

  // Initialize DXUT and create the desired Win32 window and Direct3D 
  // device for the application. Calling each of these functions is optional, but they
  // allow you to set several options which control the behavior of the framework.
  DXUTInit(True, True, True); // Parse the command line, handle the default hotkeys, and show msgboxes
  DXUTCreateWindow('MultiAnimation');

  // We need to set up DirectSound after we have a window.
  g_DSound.Initialize(DXUTGetHWND, DSSCL_PRIORITY);

  DXUTCreateDevice(D3DADAPTER_DEFAULT, True, 640, 480, IsDeviceAcceptable, ModifyDeviceSettings);

  // Pass control to DXUT for handling the message pump and
  // dispatching render calls. DXUT will call your FrameMove
  // and FrameRender callback when there is idle time between handling window messages.
  DXUTMainLoop;

  // Perform any application-level cleanup here. Direct3D device resources are released within the
  // appropriate callback functions and therefore don't require any cleanup code here.
  {for i := 0 to g_v_pCharacters.Count - 1 do
  begin
    g_v_pCharacters[i].Cleanup;
  end;}
  g_v_pCharacters.Clear; // will automatically delete all Tiny's

  FreeAndNil(g_apSoundsTiny[0]);
  FreeAndNil(g_apSoundsTiny[1]);

  ExitCode:= DXUTGetExitCode;

  DXUTFreeState;
  DestroyCustomDXUTobjects;
end.

