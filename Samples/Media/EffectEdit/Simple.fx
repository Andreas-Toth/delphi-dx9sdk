//
// Simple Lighting Model
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

string XFile< bool SasUiVisible = false; > = "tiger\\tiger.x";   // model

int    BCLR< bool SasUiVisible = false; > = 0xff202080;          // background

// light direction (view space)
float3 lightDir 
<  
	bool SasUiVisible = false;
	string SasBindAddress= "Sas.DirectionalLight[0].Direction";
	string UIDirectional = "Light Direction"; 
> = {0.577, -0.577, 0.577};

// light intensity
float4 I_a
<
	bool SasUiVisible = false;
	string SasBindAddress= "Sas.AmbientLight[0].Color";
> = { 0.1f, 0.1f, 0.1f, 1.0f };    // ambient

float4 I_d
<
	bool SasUiVisible = false;
	string SasBindAddress= "Sas.DirectionalLight[0].Color";
> = { 1.0f, 1.0f, 1.0f, 1.0f };    // diffuse

float4 I_s
<
	string SasUiLabel = "light specular";
	string SasUiControl = "ColorPicker";
> = { 1.0f, 1.0f, 1.0f, 1.0f };    // specular

// material reflectivity
float4 k_a : MATERIALAMBIENT
<
	string SasUiLabel = "material ambient";
	string SasUiControl = "ColorPicker";
> = { 1.0f, 1.0f, 1.0f, 1.0f };    // ambient

float4 k_d : MATERIALDIFFUSE
<
	string SasUiLabel = "material diffuse";
	string SasUiControl = "ColorPicker";
> = { 1.0f, 1.0f, 1.0f, 1.0f };    // diffuse

float4 k_s : MATERIALSPECULAR
<
	string SasUiLabel = "material specular";
	string SasUiControl = "ColorPicker";
> = { 1.0f, 1.0f, 1.0f, 1.0f };    // specular

float  k_n   : MATERIALPOWER
<
    string SasUiLabel = "Material Specular Power";
    string SasUiControl = "Slider"; 
    float SasUiMin = 1.0f; 
    float SasUiMax = 32.0f; 
    int SasUiSteps = 31;

> = 8.0f;                           // power

// texture
texture Tex0 
< 
	string SasUiLabel = "Texture Map";
	string SasUiControl= "FilePicker";
	string name = "tiger\\tiger.bmp"; 
>;

// transformations
float4x4 World      : WORLD
<
	bool SasUiVisible = false;
	string SasBindAddress= "Sas.Skeleton.MeshToJointToWorld[0]";
>;

float4x4 View       : VIEW
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
    float2 Tex  : TEXCOORD0;
};

VS_OUTPUT VS(
    float3 Pos  : POSITION, 
    float3 Norm : NORMAL, 
    float2 Tex  : TEXCOORD0)
{
    VS_OUTPUT Out = (VS_OUTPUT)0;

    float3 L = -lightDir;

    float4x4 WorldView = mul(World, View);

    float3 P = mul(float4(Pos, 1), (float4x3)WorldView);  // position (view space)
    float3 N = normalize(mul(Norm, (float3x3)WorldView)); // normal (view space)

    float3 R = normalize(2 * dot(N, L) * N - L);          // reflection vector (view space)
    float3 V = -normalize(P);                             // view direction (view space)

    Out.Pos  = mul(float4(P, 1), Projection);             // position (projected)
    Out.Diff = I_a * k_a + I_d * k_d * max(0, dot(N, L)); // diffuse + ambient
    Out.Spec = I_s * k_s * pow(max(0, dot(R, V)), k_n/4);   // specular
    Out.Tex  = Tex;                                       

    return Out;
}

sampler Sampler<bool SasUiVisible = false;> = sampler_state
{
    Texture   = (Tex0);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

float4 PS(
    float4 Diff : COLOR0,
    float4 Spec : COLOR1,
    float2 Tex  : TEXCOORD0) : COLOR
{
    return tex2D(Sampler, Tex) * Diff + Spec;
}

technique TVertexAndPixelShader
{
    pass P0
    {
        // shaders
        VertexShader = compile vs_1_1 VS();
        PixelShader  = compile ps_1_1 PS();
    }  
}

technique TVertexShaderOnly
{
    pass P0
    {
        // lighting
        Lighting       = FALSE;
        SpecularEnable = TRUE;

        // samplers
        Sampler[0] = (Sampler);

        // texture stages
        ColorOp[0]   = MODULATE;
        ColorArg1[0] = TEXTURE;
        ColorArg2[0] = DIFFUSE;
        AlphaOp[0]   = MODULATE;
        AlphaArg1[0] = TEXTURE;
        AlphaArg2[0] = DIFFUSE;

        ColorOp[1]   = DISABLE;
        AlphaOp[1]   = DISABLE;

        // shaders
        VertexShader = compile vs_1_1 VS();
        PixelShader  = NULL;
    }
}

technique TNoShader
{
    pass P0
    {
        // transforms
        WorldTransform[0]   = (World);
        ViewTransform       = (View);
        ProjectionTransform = (Projection);

        // material
        MaterialAmbient  = (k_a); 
        MaterialDiffuse  = (k_d); 
        MaterialSpecular = (k_s); 
        MaterialPower    = (k_n);
        
        // lighting
        LightType[0]      = DIRECTIONAL;
        LightAmbient[0]   = (I_a);
        LightDiffuse[0]   = (I_d);
        LightSpecular[0]  = (I_s); 
        LightDirection[0] = (lightDir);
        LightRange[0]     = 100000.0f;

        LightEnable[0] = TRUE;
        Lighting       = TRUE;
        SpecularEnable = TRUE;
        
        // samplers
        Sampler[0] = (Sampler);
        
        // texture stages
        ColorOp[0]   = MODULATE;
        ColorArg1[0] = TEXTURE;
        ColorArg2[0] = DIFFUSE;
        AlphaOp[0]   = MODULATE;
        AlphaArg1[0] = TEXTURE;
        AlphaArg2[0] = DIFFUSE;

        ColorOp[1]   = DISABLE;
        AlphaOp[1]   = DISABLE;

        // shaders
        VertexShader = NULL;
        PixelShader  = NULL;
    }
}
