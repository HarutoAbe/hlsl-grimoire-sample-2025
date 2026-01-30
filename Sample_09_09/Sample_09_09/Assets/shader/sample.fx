/*!
 * @brief チェッカーボードワイプ
 */

cbuffer cb : register(b0)
{
    float4x4 mvp; // MVP行列
    float4 mulColor; // 乗算カラー
};

cbuffer NagaCB : register(b1)
{
    float negaRate; // ネガポジ反転率
    float monochromeRate; // モノクロ率
    float changeRate; // チェンジ率
};

struct VSInput
{
    float4 pos : POSITION;
    float2 uv : TEXCOORD0;
};

struct PSInput
{
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD0;
};

Texture2D<float4> colorTexture : register(t0); // カラーテクスチャ
sampler Sampler : register(s0);

PSInput VSMain(VSInput In)
{
    PSInput psIn;
    psIn.pos = mul(mvp, In.pos);
    psIn.uv = In.uv;
    return psIn;
}

float4 PSMain(PSInput In) : SV_Target0
{
    float4 color = colorTexture.Sample(Sampler, In.uv);

    
    
    // step-1 画像を徐々にネガポジ反転させていく
    float3 negaColor;
    //negaColor.x = color.x * 0.299f;
    //negaColor.y = color.y * 0.587f;
    //negaColor.z = color.z * 0.114f;
           
    float Y = 0.299f * color.r + 0.587f * color.g + 0.114f * color.b;
    negaColor = float3(Y, Y, Y);
    //color.xyz = lerp(color, monochromeColor, monochromeRate);
   // ネガポジ率を使って徐々にネガポジ画像にしていく
    color.xyz = lerp(color, negaColor, negaRate);
    changeRate += 0.01f;
    
    if (negaRate > changeRate)
    {
        color -= color;
        changeRate -= 0.01;
    }
    
    
    
        return color;
}
