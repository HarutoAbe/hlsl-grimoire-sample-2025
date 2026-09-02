#include "stdafx.h"
#include "system/system.h"
#include "RenderingEngine.h"
#include "ModelRender.h"

// 関数宣言
void InitRootSignature(RootSignature& rs);

///////////////////////////////////////////////////////////////////
// ウィンドウプログラムのメイン関数
///////////////////////////////////////////////////////////////////
int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance,
    LPWSTR lpCmdLine, int nCmdShow)
{
    // ゲームの初期化
    InitGame(hInstance, hPrevInstance, lpCmdLine, nCmdShow, TEXT("Game"));

    //////////////////////////////////////
    // ここから初期化を行うコードを記述する
    //////////////////////////////////////
    // ルートシグネチャを作成
    RootSignature rootSignature;
    InitRootSignature(rootSignature);

    //レンダリングパイプラインを初期化
    myRenderer::RenderingEngine renderingEngine;
    renderingEngine.Init();

    // 背景モデルのレンダラーを初期化
    myRenderer::ModelRender bgModelRender;
    bgModelRender.InitDeferredRendering(renderingEngine, "Assets/modelData/bg/bg.tkm", true);

    // step-1 ティーポットモデルの描画処理を初期化
    // Y軸回転角度（シェーダーへ渡す拡張定数バッファ）
    float rotationY = 0.0f;

    myRenderer::ModelInitDataFR modelInitData;
    modelInitData.m_tkmFilePath = "Assets/modelData/teapot.tkm";
    modelInitData.m_fxFilePath = "Assets/shader/sample.fx";
    // シェーダーへ渡す拡張定数バッファを設定（定数バッファは16バイト境界で扱われるためサイズは16に）
    modelInitData.m_expandConstantBuffer = &rotationY;
    modelInitData.m_expandConstantBufferSize = 16;

    //【注目】メインレンダリングターゲットのスナップショットテクスチャを拡張SRVに指定する
    modelInitData.m_expandShaderResoruceView[0] = &renderingEngine.GetMainRenderTargetSnapshotDrawnOpacity();
    myRenderer::ModelRender teapotModelRender;

    //フォワードレンダリングの描画パスで実行されるように初期化する
    teapotModelRender.InitForwardRendering(renderingEngine, modelInitData);
    teapotModelRender.SetShadowCasterFlag(true);

    teapotModelRender.UpdateWorldMatrix({ 0.0f, 20.0f, 0.0f }, g_quatIdentity, g_vec3One);

    //////////////////////////////////////
    // 初期化を行うコードを書くのはここまで！！！
    //////////////////////////////////////
    auto& renderContext = g_graphicsEngine->GetRenderContext();

    // Quaternion型で宣言（回転用）
    Quaternion rotation = g_quatIdentity;

    // ここからゲームループ
    while (DispatchWindowMessage())
    {
        // レンダリング開始
        g_engine->BeginFrame();
        g_camera3D->MoveForward(g_pad[0]->GetLStickYF());
        g_camera3D->MoveRight(g_pad[0]->GetLStickXF());
        g_camera3D->MoveUp(g_pad[0]->GetRStickYF());

        // Y軸回転（クォータニオンとシェーダーの角度を更新）
        rotation.AddRotationY(0.01f); // ワールド行列用
        rotationY += 0.01f; // シェーダーへ渡す角度（ラジアン）
        const float TWO_PI = Math::PI * 2.0f;
        if (rotationY >= TWO_PI) rotationY -= TWO_PI;

        //////////////////////////////////////
        // ここから絵を描くコードを記述する
        //////////////////////////////////////

        // ワールド行列に回転を適用して更新
        teapotModelRender.UpdateWorldMatrix({ 0.0f, 20.0f, 0.0f }, rotation, g_vec3One);

        bgModelRender.Draw();

        // step-2 ティーポットモデルを描画
        teapotModelRender.Draw();

        // レンダリングパイプラインを実行
        renderingEngine.Execute(renderContext);

        /////////////////////////////////////////
        // 絵を描くコードを書くのはここまで！！！
        //////////////////////////////////////
        // レンダリング終了
        g_engine->EndFrame();
    }

    return 0;
}

// ルートシグネチャの初期化
void InitRootSignature(RootSignature& rs)
{
    rs.Init(D3D12_FILTER_MIN_MAG_MIP_LINEAR,
        D3D12_TEXTURE_ADDRESS_MODE_WRAP,
        D3D12_TEXTURE_ADDRESS_MODE_WRAP,
        D3D12_TEXTURE_ADDRESS_MODE_WRAP);
}
