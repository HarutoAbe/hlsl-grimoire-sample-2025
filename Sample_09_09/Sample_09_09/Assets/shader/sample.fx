/*!
 * @brief チェッカーボードワイプ
 */

cbuffer cb : register(b0)
{
    float4x4 mvp;           // MVP行列
    float4 mulColor;        // 乗算カラー
};

//cbuffer NagaCB : register( b1 )
//{
//    float negaRate;         // ネガポジ反転率
//};

// 追加
cbuffer ExpandCB : register(b1)
{
    float time;
    float wipeRate;
}

struct VSInput
{
    float4 pos : POSITION;
    float2 uv  : TEXCOORD0;
};

struct PSInput
{
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD0;
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
    // 元のカラーをグレースケールに変換
    float gray = dot(color.rgb, float3(0.299f, 0.587f, 0.114f));
    float3 grayColor = float3(gray, gray, gray);

    // 時間で往復するネガ反転率を計算
    float negaRate = (sin(time) + 1.0f) * 0.5f;
    
    // ネガポジ反転カラー
    float3 negaColor = 1.0f - color.rgb;
    
    // 元の画像とネガポジ反転画像を混ぜる
    float3 mixedNega = lerp(color.rgb, negaColor, negaRate);

   // 上から↓へ進行するワイプ
    float wipe = step(In.uv.y, wipeRate);

    // 切り替え
    float3 finalColor = lerp(grayColor, mixedNega, wipe);

    return float4(finalColor, color.a);
}
