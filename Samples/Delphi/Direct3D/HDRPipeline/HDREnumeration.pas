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
 *  $Id: HDREnumeration.pas,v 1.5 2007/02/05 22:21:08 clootie Exp $
 *----------------------------------------------------------------------------*)
//======================================================================
//
//      HIGH DYNAMIC RANGE RENDERING DEMONSTRATION
//      Written by Jack Hoxley, November 2005
//
//======================================================================

{$I DirectX.inc}

unit HDREnumeration;

interface

uses
  Windows, Direct3D9,
  DXUT, DXUTenum;

// Several modules making up this sample code need to make
// decisions based on what features the underlying hardware
// supports. These queries are contained in the following
// namespace:
// namespace HDREnumeration {}


// The following function will examine the capabilities of the device
// and store the best format in 'pBestFormat'.
function FindBestHDRFormat(out BestFormat: TD3DFormat): HRESULT;

// A similar function to above, but this one examines the single-channel
// G32R32F and G16R16F support - used by the luminance measurement calculations.
function FindBestLuminanceFormat(out BestLuminanceFormat: TD3DFormat): HRESULT;


implementation

//--------------------------------------------------------------------------------------
//  FindBestHDRFormat( )
//
//      DESC:
//          Due to High Dynamic Range rendering still being a relatively high-end
//          feature in consumer hardware, several basic properties are still not
//          uniformly available. Two particular examples are texture filtering and
//          post pixel-shader blending.
//
//          Substantially better results can be gained from this sample if texture
//          filtering is available. Post pixel-shader blending is not required. The
//          following function will enumerate supported formats in the following order:
//
//              1. Single Precision (128 bit) with support for linear texture filtering
//              2. Half Precision (64 bit) with support for linear texture filtering
//              3. Single Precision (128 bit) with NO texture filtering support
//              4. Half Precision (64 bit) with NO texture filtering support
//
//          If none of the these can be satisfied, the device should be considered
//          incompatable with this sample code.
//
//      PARAMS:
//          pBestFormat  : A container for the detected best format. Can be NULL.
//
//      NOTES:
//          The pBestFormat parameter can be set to NULL if the specific format is
//          not actually required. Because of this, the function can be used as a
//          simple predicate to determine if the device can handle HDR rendering:
//
//              if( FAILED( FindBestHDRFormat( NULL ) ) )
//              {
//                  // This device is not compatable.
//              }
//
//--------------------------------------------------------------------------------------
function FindBestHDRFormat(out BestFormat: TD3DFormat): HRESULT;
var
  info: TDXUTDeviceSettings;
begin
  // Retrieve important information about the current configuration
  info := DXUTGetDeviceSettings;

  Result := DXUTGetD3DObject.CheckDeviceFormat(info.AdapterOrdinal, info.DeviceType, info.AdapterFormat, D3DUSAGE_QUERY_FILTER or D3DUSAGE_RENDERTARGET, D3DRTYPE_TEXTURE, D3DFMT_A32B32G32R32F);
  if FAILED(Result) then
  begin
    // We don't support 128 bit render targets with filtering. Check the next format.
    OutputDebugString('Enumeration.FindBestHDRFormat() - Current device does *not* support single-precision floating point textures with filtering.'#10);

    Result := DXUTGetD3DObject.CheckDeviceFormat(info.AdapterOrdinal, info.DeviceType, info.AdapterFormat, D3DUSAGE_QUERY_FILTER or D3DUSAGE_RENDERTARGET, D3DRTYPE_TEXTURE, D3DFMT_A16B16G16R16F);
    if FAILED(Result) then
    begin
      // We don't support 64 bit render targets with filtering. Check the next format.
      OutputDebugString('Enumeration::FindBestHDRFormat() - Current device does *not* support half-precision floating point textures with filtering.'#10);

      Result := DXUTGetD3DObject.CheckDeviceFormat(info.AdapterOrdinal, info.DeviceType, info.AdapterFormat, D3DUSAGE_RENDERTARGET, D3DRTYPE_TEXTURE, D3DFMT_A32B32G32R32F);
      if FAILED(Result) then
      begin
        // We don't support 128 bit render targets. Check the next format.
        OutputDebugString('Enumeration::FindBestHDRFormat() - Current device does *not* support single-precision floating point textures.'#10);

        Result := DXUTGetD3DObject.CheckDeviceFormat(info.AdapterOrdinal, info.DeviceType, info.AdapterFormat, D3DUSAGE_RENDERTARGET, D3DRTYPE_TEXTURE, D3DFMT_A16B16G16R16F);
        if FAILED(Result) then
        begin
          // We don't support 64 bit render targets. This device is not compatable.
          OutputDebugString('Enumeration::FindBestHDRFormat() - Current device does *not* support half-precision floating point textures.'#10);
          OutputDebugString('Enumeration::FindBestHDRFormat() - THE CURRENT HARDWARE DOES NOT SUPPORT HDR RENDERING!'#10);
          Result:= E_FAIL;
          Exit;
        end else
        begin
          // We have support for 64 bit render targets without filtering
          OutputDebugString('Enumeration::FindBestHDRFormat() - Best available format is ''half-precision without filtering''.'#10);
          BestFormat := D3DFMT_A16B16G16R16F;
        end;
      end
      else
      begin
        // We have support for 128 bit render targets without filtering
        OutputDebugString('Enumeration::FindBestHDRFormat() - Best available format is ''single-precision without filtering''.'#10);
        BestFormat := D3DFMT_A32B32G32R32F;
      end;
    end
    else
    begin
      // We have support for 64 bit render targets with filtering
      OutputDebugString('Enumeration::FindBestHDRFormat - Best available format is ''half-precision with filtering''.'#10);
      BestFormat := D3DFMT_A16B16G16R16F;
    end;
  end else
  begin
    // We have support for 128 bit render targets with filtering
    OutputDebugString('Enumeration::FindBestHDRFormat() - Best available format is ''single-precision with filtering''.'#10);
    BestFormat := D3DFMT_A32B32G32R32F;
  end;

  Result:= S_OK;
end;



//--------------------------------------------------------------------------------------
//  FindBestLuminanceFormat( )
//
//      DESC:
//          << See notes for 'FindBestHDRFormat' >>
//          The luminance calculations store a single intensity and maximum brightness, and
//          as such don't need to use textures with the full 128 or 64 bit sizes. D3D
//          offers two formats, G32R32F and G16R16F for this sort of purpose - and this
//          function will return the best supported format. The following function will
//          enumerate supported formats in the following order:
//
//              1. Single Precision (32 bit) with support for linear texture filtering
//              2. Half Precision (16 bit) with support for linear texture filtering
//              3. Single Precision (32 bit) with NO texture filtering support
//              4. Half Precision (16 bit) with NO texture filtering support
//
//          If none of the these can be satisfied, the device should be considered
//          incompatable with this sample code.
//
//      PARAMS:
//          pBestLuminanceFormat    : A container for the detected best format. Can be NULL.
//
//      NOTES:
//          The pBestLuminanceFormatparameter can be set to NULL if the specific format is
//          not actually required. Because of this, the function can be used as a
//          simple predicate to determine if the device can handle HDR rendering:
//
//              if( FAILED( FindBestLuminanceFormat( NULL ) ) )
//              {
//                  // This device is not compatable.
//              }
//
//--------------------------------------------------------------------------------------
function FindBestLuminanceFormat(out BestLuminanceFormat: TD3DFormat): HRESULT;
var
  info: TDXUTDeviceSettings;
begin
  // Retrieve important information about the current configuration
  info := DXUTGetDeviceSettings;

  Result := DXUTGetD3DObject.CheckDeviceFormat(info.AdapterOrdinal, info.DeviceType, info.AdapterFormat, D3DUSAGE_QUERY_FILTER or D3DUSAGE_RENDERTARGET, D3DRTYPE_TEXTURE, D3DFMT_G32R32F);
  if FAILED(Result) then
  begin
    // We don't support 32 bit render targets with filtering. Check the next format.
    OutputDebugString('Enumeration::FindBestLuminanceFormat() - Current device does *not* support single-precision floating point textures with filtering.'#10);

    Result := DXUTGetD3DObject.CheckDeviceFormat(info.AdapterOrdinal, info.DeviceType, info.AdapterFormat, D3DUSAGE_QUERY_FILTER or D3DUSAGE_RENDERTARGET, D3DRTYPE_TEXTURE, D3DFMT_G16R16F);
    if FAILED(Result) then
    begin
      // We don't support 16 bit render targets with filtering. Check the next format.
      OutputDebugString('Enumeration::FindBestLuminanceFormat() - Current device does *not* support half-precision floating point textures with filtering.'#10);

      Result := DXUTGetD3DObject.CheckDeviceFormat(info.AdapterOrdinal, info.DeviceType, info.AdapterFormat, D3DUSAGE_RENDERTARGET, D3DRTYPE_TEXTURE, D3DFMT_G32R32F);
      if FAILED(Result) then
      begin
        // We don't support 32 bit render targets. Check the next format.
        OutputDebugString('Enumeration::FindBestLuminanceFormat() - Current device does *not* support single-precision floating point textures.'#10);

        Result := DXUTGetD3DObject.CheckDeviceFormat(info.AdapterOrdinal, info.DeviceType, info.AdapterFormat, D3DUSAGE_RENDERTARGET, D3DRTYPE_TEXTURE, D3DFMT_G16R16F);
        if FAILED(Result) then
        begin
          // We don't support 16 bit render targets. This device is not compatable.
          OutputDebugString('Enumeration::FindBestLuminanceFormat() - Current device does *not* support half-precision floating point textures.'#10);
          OutputDebugString('Enumeration::FindBestLuminanceFormat() - THE CURRENT HARDWARE DOES NOT SUPPORT HDR RENDERING!'#10);
          Result:= E_FAIL;
          Exit;
        end else
        begin
          // We have support for 16 bit render targets without filtering
          OutputDebugString('Enumeration::FindBestLuminanceFormat() - Best available format is ''half-precision without filtering''.'#10);
          BestLuminanceFormat := D3DFMT_G16R16F;
        end;
      end else
      begin
        // We have support for 32 bit render targets without filtering
        OutputDebugString('Enumeration::FindBestLuminanceFormat() - Best available format is ''single-precision without filtering''.'#10);
        BestLuminanceFormat := D3DFMT_G32R32F;
      end;
    end else
    begin
      // We have support for 16 bit render targets with filtering
      OutputDebugString('Enumeration::FindBestLuminanceFormat() - Best available format is ''half-precision with filtering''.'#10);
      BestLuminanceFormat := D3DFMT_G16R16F;
    end;
  end else
  begin
    // We have support for 32 bit render targets with filtering
    OutputDebugString('Enumeration::FindBestLuminanceFormat() - Best available format is ''single-precision with filtering''.'#10);
    BestLuminanceFormat := D3DFMT_G32R32F;
  end;

  Result:= S_OK;
end;

end.

