#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// 頂點着色器：四個頂點 + triangle_strip
vertex VertexOut vertexPassthrough(uint vertexID [[vertex_id]]) {
    VertexOut out;

    float2 positions[4] = {
        float2(-1.0, -1.0), // 左下
        float2( 1.0, -1.0), // 右下
        float2(-1.0,  1.0), // 左上
        float2( 1.0,  1.0)  // 右上
    };

    float2 texCoords[4] = {
        float2(0.0, 1.0), // 左下 → UV (0,1)
        float2(1.0, 1.0), // 右下 → UV (1,1)
        float2(0.0, 0.0), // 左上 → UV (0,0)
        float2(1.0, 0.0)  // 右上 → UV (1,0)
    };

    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

// 片段着色器：NV12 → RGB
fragment float4 fragmentNV12(VertexOut in [[stage_in]],
                             texture2d<float, access::sample> texY [[texture(0)]],
                             texture2d<float, access::sample> texUV [[texture(1)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);

    // 取樣 Y 與 UV
    float y = texY.sample(s, in.texCoord).r;
    float2 uv = texUV.sample(s, in.texCoord).rg;

    // NV12 → RGB 轉換
    float Y = 1.1643 * (y - 0.0625);
    float U = uv.x - 0.5;
    float V = uv.y - 0.5;

    float R = Y + 1.5958 * V;
    float G = Y - 0.39173 * U - 0.81290 * V;
    float B = Y + 2.017 * U;

    return float4(R, G, B, 1.0);
}
