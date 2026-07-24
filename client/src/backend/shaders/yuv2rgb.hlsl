// NV12 YUV → RGB shader
// Vertex shader
struct VSInput {
    float2 pos : POSITION;
    float2 uv  : TEXCOORD0;
};

struct PSInput {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD0;
};

PSInput VSMain(VSInput input)
{
    PSInput output;
    output.pos = float4(input.pos, 0.0f, 1.0f);
    output.uv  = input.uv;
    return output;
}

// Shader resources
Texture2D texY : register(t0);   // R8_UNORM
Texture2D texUV : register(t1);  // R8G8_UNORM
SamplerState samp : register(s0);

// Pixel shader
float4 PSMain(PSInput input) : SV_TARGET
{
    float y  = texY.Sample(samp, input.uv).r;

    float2 uv = texUV.Sample(samp, input.uv).rg;
    float u = uv.x - 0.5f;
    float v = uv.y - 0.5f;

    float r = y + 1.402f * v;
    float g = y - 0.344f * u - 0.714f * v;
    float b = y + 1.772f * u;

    return float4(r, g, b, 1.0f);
}
