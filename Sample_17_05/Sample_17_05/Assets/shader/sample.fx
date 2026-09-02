/***************************************************************************
# Copyright (c) 2018, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#  * Neither the name of NVIDIA CORPORATION nor the names of its
#    contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
# OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
***************************************************************************/

// 頂点構造
// フォーマットはTkmFile.hのSVertexと同じになっている必要がある
struct SVertex
{
    float3 pos;
    float3 normal;
    float3 tangent;
    float3 binormal;
    float2 uv;
    int4 indices;
    float4 skinweigths;
};

// カメラ構造体
// 定数バッファーなので16バイトアライメントに気を付けること
struct Camera
{
    float4x4 mCameraRot; // カメラの回転行列
    float3 pos; // カメラ座標
    float aspect; // アスペクト比
    float far; // 遠平面
    float near; // 近平面
};

cbuffer rayGenCB : register(b0)
{
    Camera g_camera; // カメラ
};

RaytracingAccelerationStructure g_raytracingWorld : register(t0); // レイトレワールド
Texture2D<float4> gAlbedoTexture : register(t1); // アルベドマップ
Texture2D<float4> g_normalMap : register(t2); // 法線マップ
Texture2D<float4> g_specularMap : register(t3); // スペキュラマップ
Texture2D<float4> g_reflectionMap : register(t4); // リフレクションマップ
Texture2D<float4> g_refractionMap : register(t5); // 屈折マップ
StructuredBuffer<SVertex> g_vertexBuffers : register(t6); // 頂点バッファー
StructuredBuffer<int> g_indexBuffers : register(t7); // インデックスバッファー

RWTexture2D<float4> gOutput : register(u0);

SamplerState s : register(s0);

struct RayPayload
{
    float3 color; // カラー
    int hit;
    int depth;
};

// UV座標を取得
float2 GetUV(BuiltInTriangleIntersectionAttributes attribs)
{
    float3 barycentrics = float3(1.0 - attribs.barycentrics.x - attribs.barycentrics.y, attribs.barycentrics.x, attribs.barycentrics.y);

    // プリミティブIDを取得
    uint primID = PrimitiveIndex();

    // プリミティブIDから頂点番号を取得する
    uint v0_id = g_indexBuffers[primID * 3];
    uint v1_id = g_indexBuffers[primID * 3 + 1];
    uint v2_id = g_indexBuffers[primID * 3 + 2];
    float2 uv0 = g_vertexBuffers[v0_id].uv;
    float2 uv1 = g_vertexBuffers[v1_id].uv;
    float2 uv2 = g_vertexBuffers[v2_id].uv;

    float2 uv = barycentrics.x * uv0 + barycentrics.y * uv1 + barycentrics.z * uv2;
    return uv;
}

// 法線を取得
float3 GetNormal(BuiltInTriangleIntersectionAttributes attribs, float2 uv)
{
    float3 barycentrics = float3(1.0 - attribs.barycentrics.x - attribs.barycentrics.y, attribs.barycentrics.x, attribs.barycentrics.y);

    // プリミティブIDを取得
    uint primID = PrimitiveIndex();

    // プリミティブIDから頂点番号を取得する
    uint v0_id = g_indexBuffers[primID * 3];
    uint v1_id = g_indexBuffers[primID * 3 + 1];
    uint v2_id = g_indexBuffers[primID * 3 + 2];

    float3 normal0 = g_vertexBuffers[v0_id].normal;
    float3 normal1 = g_vertexBuffers[v1_id].normal;
    float3 normal2 = g_vertexBuffers[v2_id].normal;
    float3 normal = barycentrics.x * normal0 + barycentrics.y * normal1 + barycentrics.z * normal2;
    normal = normalize(normal);

    float3 tangent0 = g_vertexBuffers[v0_id].tangent;
    float3 tangent1 = g_vertexBuffers[v1_id].tangent;
    float3 tangent2 = g_vertexBuffers[v2_id].tangent;
    float3 tangent = barycentrics.x * tangent0 + barycentrics.y * tangent1 + barycentrics.z * tangent2;
    tangent = normalize(tangent);

    float3 binormal = normalize(cross(tangent, normal));

    float3 binSpaceNormal = g_normalMap.SampleLevel(s, uv, 0.0f).xyz;
    binSpaceNormal = (binSpaceNormal * 2.0f) - 1.0f;

    normal = tangent * binSpaceNormal.x + binormal * binSpaceNormal.y + normal * binSpaceNormal.z;

    return normal;
}

// 光源に向けてレイを飛ばす
void TraceLightRay(inout RayPayload raypayload, float3 normal)
{
    float hitT = RayTCurrent();
    float3 rayDirW = WorldRayDirection();
    float3 rayOriginW = WorldRayOrigin();

    // Find the world-space hit position
    float3 posW = rayOriginW + hitT * rayDirW;

    RayDesc ray;
    ray.Origin = posW;
    ray.Direction = normalize(float3(0.5, 0.5, 0.2));
    ray.TMin = 0.01f;
    ray.TMax = 100;

    TraceRay(
        g_raytracingWorld,
        0u,
        0xFFu,
        1u,
        0u,
        1u,
        ray,
        raypayload
    );
}


// 透過で屈折を計算し、Fresnelで反射/透過を混合する
void TraceReflectionRay(inout RayPayload outPayload, float3 normal, float2 uv)
{
    if (outPayload.depth >= 3)
        return;

    float hitT = RayTCurrent();
    float3 I = normalize(WorldRayDirection());
    float3 posW = WorldRayOrigin() + hitT * I;
    float3 N = normalize(normal);

    // 反射をトレース
    float3 reflDir = normalize(reflect(I, N));
    RayDesc rRay;
    rRay.Origin = posW + reflDir * 0.01f;
    rRay.Direction = reflDir;
    rRay.TMin = 0.01f;
    rRay.TMax = 10000.0f;
    RayPayload rPayload;
    rPayload.depth = outPayload.depth + 1;
    rPayload.color = float3(0, 0, 0);
    TraceRay(g_raytracingWorld, 0u, 0xFFu, 0u, 0u, 0u, rRay, rPayload);
    float3 reflectedColor = rPayload.color;

    // テクスチャから透過率を取得
    // 0は不透過、1は透過
    float transMap = g_refractionMap.SampleLevel(s, uv, 0.0f).r;

    float3 transmitColor = float3(0, 0, 0);
    bool hasTransmit = false;

    if (transMap > 0.001f)
    {
        // 屈折率 (外側 -> 内側)
        float etaOutside = 1.0f;
        float etaInside = 1.5f;

        float cosi = clamp(dot(-I, N), -1.0f, 1.0f);
        bool entering = cosi > 0.0f;
        float3 n = N;
        float eta = etaOutside / etaInside;
        if (!entering)
        {
            n = -N;
            eta = etaInside / etaOutside;
            cosi = clamp(dot(-I, n), -1.0f, 1.0f);
        }

        float3 refrDir = refract(-I, n, eta);
        bool tir = length(refrDir) < 1e-6;

        // tirの場合は全反射となるので、透過例は飛ばさない
        if (!tir)
        {
            RayDesc tRay;
            tRay.Origin = posW + refrDir * 0.01f;
            tRay.Direction = normalize(refrDir);
            tRay.TMin = 0.01f;
            tRay.TMax = 10000.0f;
            RayPayload tPayload;
            tPayload.depth = outPayload.depth + 1;
            tPayload.color = float3(0, 0, 0);
            TraceRay(g_raytracingWorld, 0u, 0xFFu, 0u, 0u, 0u, tRay, tPayload);
            transmitColor = tPayload.color;
            hasTransmit = true;
        }
        else
        {
            hasTransmit = false;
        }
    }

    // Fresnel
    // 反射率の計算
    float3 F0 = float3(0.04f, 0.04f, 0.04f);
    float cosTheta = saturate(dot(-I, N));
    float3 fresnel = F0 + (1.0f - F0) * pow(1.0f - cosTheta, 5.0f);
    float fresnelFactor = fresnel.x;

    // マテリアルの反射率を取得
    float materialRefl = g_reflectionMap.SampleLevel(s, uv, 0.0f).r;

    
    // 反射と透過の重みを計算
    float reflW = saturate(fresnelFactor * materialRefl);
    float transW = hasTransmit ? saturate(transMap * (1.0f - fresnelFactor)) : 0.0f;

    // 重みの合計を計算
    float sum = reflW + transW;
    float3 outColor;
    
    // 反射と透過の重みを正規化して混合する
    if (sum > 1e-6f)
    {
        outColor = (reflectedColor * reflW + transmitColor * transW) / sum;
    }
    else
    {
        outColor = reflectedColor;
    }

    outPayload.color = outColor;
}

[shader("raygeneration")]
void rayGen()
{
    uint3 launchIndex = DispatchRaysIndex();
    uint3 launchDim = DispatchRaysDimensions();

    float2 crd = float2(launchIndex.xy);
    float2 dims = float2(launchDim.xy);

    float2 d = ((crd / dims) * 2.f - 1.f);
    float aspectRatio = dims.x / dims.y;

    // ピクセル方向に打ち出すレイを作成する
    RayDesc ray;
    ray.Origin = g_camera.pos;
    ray.Direction = normalize(float3(d.x * g_camera.aspect, -d.y, -1));
    ray.Direction = mul(g_camera.mCameraRot, ray.Direction);

    ray.TMin = 0;
    ray.TMax = 10000;

    RayPayload payload;
    payload.depth = 0;

    //TraceRay
    TraceRay(g_raytracingWorld, 0u /*rayFlags*/, 0xFFu, 0u /* ray index*/, 0u, 0u, ray, payload);

    float3 col = payload.color;

    gOutput[launchIndex.xy] = float4(col, 1);
}

[shader("miss")]
void miss(inout RayPayload payload)
{
    payload.color = float3(0.1, 0.0, 0.0);
}

[shader("closesthit")]
void chs(inout RayPayload payload, in BuiltInTriangleIntersectionAttributes attribs)
{
    payload.depth++;
    // ヒットしたプリミティブのUV座標を取得
    float2 uv = GetUV(attribs);

    // ヒットしたプリミティブの法線を取得
    float3 normal = GetNormal(attribs, uv);

    // ワールド空間に変換するのがめんどいので、超適当に・・・。さーせん
    float cs = cos(-1.57f);
    float sn = sin(-1.57f);
    float4x4 m;
    m[0][0] = 1.0f;
    m[0][1] = 0.0f;
    m[0][2] = 0.0f;
    m[0][3] = 0.0f;

    m[1][0] = 0.0f;
    m[1][1] = cs;
    m[1][2] = sn;
    m[1][3] = 0.0f;

    m[2][0] = 0.0f;
    m[2][1] = -sn;
    m[2][2] = cs;
    m[2][3] = 0.0f;

    m[3][0] = 0.0f;
    m[3][1] = 0.0f;
    m[3][2] = 0.0f;
    m[3][3] = 1.0f;

    m = transpose(m);
    normal = mul(m, normal);

    // 光源にむかってレイを飛ばす
    TraceLightRay(payload, normal);
    float lig = 0.0f;
    if (payload.hit == 0)
    {
        float3 ligDir = normalize(float3(0.5, 0.5, 0.2));
        float t = max(0.0f, dot(ligDir, normal));
        lig = t;
    }

    //環境光
    lig += 0.5f;
    RayPayload refPayload;
    refPayload.depth = payload.depth;
    refPayload.color = float3(0.0f, 0.0f, 0.0f);

    // 反射／透過レイ（uv を渡す）
    TraceReflectionRay(refPayload, normal, uv);

    // このプリミティブの反射率を取得
    float reflectRate = g_reflectionMap.SampleLevel(s, uv, 0.0f).r;
    float3 color = gAlbedoTexture.SampleLevel(s, uv, 0.0f).rgb;
    color *= lig;
    // 反射率で反射色とベースカラーを混ぜる
    payload.color = lerp(color, refPayload.color, reflectRate);

    payload.depth--;
}

[shader("closesthit")]
void shadowChs(inout RayPayload payload, in BuiltInTriangleIntersectionAttributes attribs)
{
    payload.hit = 1;
}

[shader("miss")]
void shadowMiss(inout RayPayload payload)
{
    payload.hit = 0;
}
