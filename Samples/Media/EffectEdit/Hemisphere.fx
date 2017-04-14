//
// Hemisphere Lighting Model
// Copyright (c) Microsoft Corporation. All rights reserved.
//
// Note: This effect file works with EffectEdit.
// Note: This effect file is SAS 1.0.1 compliant and will work with DxViewer.
//

int sas : SasGlobal
<
	bool SasUiVisible = false;
	int3 SasVersion= {1,1,0};
>;


string XFile< bool SasUiVisible = false; > = "misc\\SkullOcc.x";          // model

int    BCLR< bool SasUiVisible = false; >  = 0xff202080;                  // background

// light directions (view space)
float3 DirFromLight 
< 
	bool SasUiVisible = false;
	string SasBindAddress= "Sas.SpotLight[0].Direction";
	string UIDirectional = "Light Direction"; 
> = {0.577, -0.577, 0.577};

// direction of light from sky (view space)
float3 DirFromSky 
< 
	bool SasUiVisible = false;
	string SasBindAddress= "Sas.DirectionalLight[0].Direction";
	string UIDirectional = "Direction from Sky"; 
> = { 0.0f, -1.0f, 0.0f };            

// light intensity
float4 I_a
<
	bool SasUiVisible = false;
	string SasBindAddress= "Sas.AmbientLight[0].Color";
> = { 0.5f, 0.5f, 0.5f, 1.0f };    // ambient

float4 I_b
<
	string SasUiLabel = "light ground";
	string SasUiControl = "ColorPicker";
> = { 0.1f, 0.0f, 0.0f, 1.0f };    // ground

float4 I_c
<
	string SasUiLabel = "light sky";
	string SasUiControl = "ColorPicker";
> = { 0.9f, 0.9f, 1.0f, 1.0f };    // sky

float4 I_d
<
	bool SasUiVisible = false;
	string SasBindAddress= "Sas.SpotLight[0].Color";
> = { 1.0f, 0.9f, 0.8f, 1.0f };    // diffuse

float4 I_s
<
	string SasUiLabel = "light specular";
	string SasUiControl = "ColorPicker";
> = { 1.0f, 1.0f, 1.0f, 1.0f };    // specular

// material reflectivity
float4 k_a
<
	string SasUiLabel = "material ambient";
	string SasUiControl = "ColorPicker";
> = { 0.8f, 0.8f, 0.8f, 1.0f };    // ambient

float4 k_d
<
	string SasUiLabel = "material diffuse";
	string SasUiControl = "ColorPicker";
> = { 0.4f, 0.4f, 0.4f, 1.0f };    // diffuse

float4 k_s
<
	string SasUiLabel = "material specular";
	string SasUiControl = "ColorPicker";
> = { 0.1f, 0.1f, 0.1f, 1.0f };    // specular

float  k_n
<
    string SasUiLabel = "Material Specular Power";
    string SasUiControl = "Slider"; 
    float SasUiMin = 1.0f; 
    float SasUiMax = 32.0f; 
    int SasUiSteps = 31;
> = 8.0f;                         // power


// transformations
float4x4 World  : WORLD
<
	bool SasUiVisible = false;
	string SasBindAddress= "Sas.Skeleton.MeshToJointToWorld[0]";
>;

// transformations
float4x4 View  : VIEW 
<
	bool SasUiVisible = false;
	string SasBindAddress= "Sas.Camera.WorldToView";
>;

float4x4 Projection : PROJECTION
<
	bool SasUiVisible = false;
	string SasBindAddress= "Sas.Camera.Projection";
>;

struct VS_OUTPUT
{
    float4 Pos  : POSITION;
    float4 Diff : COLOR0;
    float4 Spec : COLOR1;
};

VS_OUTPUT VS(
    float3 Pos  : POSITION, 
    float3 Norm : NORMAL, 
    float  Occ  : TEXCOORD0,
    uniform bool bHemi, 
    uniform bool bDiff,
    uniform bool bSpec)
{
    VS_OUTPUT Out = (VS_OUTPUT)0;

    float3 L = -DirFromLight;                               // diffuse direction
    float3 Y = -DirFromSky;                                 // hemisphere up axis
    
    float3 P = mul(float4(Pos, 1), World);					// position (view space)
    P= mul(float4(P, 1), View);
    
    float3 N = normalize(mul(Norm, (float3x3)World));   // normal (view space)
    N= mul(N, (float3x3)View);
    
    float3 R = normalize(2 * dot(N, L) * N - L);            // reflection vector (view space)
    float3 V = -normalize(P);                               // view direction (view space)

    float4 Amb  = k_a * I_a;
    float4 Hemi = k_a * lerp(I_b, I_c, (dot(N, Y) + 1) / 2) * (1 - Occ);
    float  temp = 1 - max(0, dot(N, L));
    float4 Diff = k_d * I_d * (1 - temp * temp);
    float4 Spec = k_s * I_s * pow(max(0, dot(R, V)), k_n/4);
    float4 Zero = 0;

    Out.Pos  = mul(float4(P, 1), Projection);               // position (projected)
    Out.Diff = (bDiff ? Diff : 0)
             + (bHemi ? Hemi : Amb);                        // diffuse + ambient/hemisphere
    Out.Spec = (bSpec ? Spec : 0);                          // specular

    return Out;
}


technique THemisphere
{
    pass P0
    {
        VertexShader = compile vs_1_1 VS(true, false, false);
    }
}

technique THemisphereDiffuse
{
    pass P0
    {
        VertexShader = compile vs_1_1 VS(true, true, false);
    }
}

technique THemisphereDiffuseSpecular
{
    pass P0
    {
        VertexShader = compile vs_1_1 VS(true, true, true);

        SpecularEnable = TRUE;
    }
}

technique TAmbient
{
    pass P0
    {
        VertexShader = compile vs_1_1 VS(false, false, false);
    }
}

technique TAmbientDiffuse
{
    pass P0
    {
        VertexShader = compile vs_1_1 VS(false, true, false);
    }
}

technique TAmbientDiffuseSpecular
{
    pass P0
    {
        VertexShader = compile vs_1_1 VS(false, true, true);

        SpecularEnable = TRUE;
    }
}

