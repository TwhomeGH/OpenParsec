#include <metal_stdlib>
using namespace metal;

// 頂點結構
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// 頂點着色器：生成一個全螢幕 quad
vertex VertexOut vertexPassthrough(uint vertexID [[vertex_id]]) {
    VertexOut out;

    // 六個頂點，組成兩個三角形
    float2 positions[6] = {
        float2(-1.0, -1.0), // 左下
        float2( 1.0, -1.0), // 右下
        float2(-1.0,  1.0), // 左上
        float2(-1.0,  1.0), // 左上
        float2( 1.0, -1.0), // 右下
        float2( 1.0,  1.0)  // 右上
    };

    float2 texCoords[6] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(0.0, 0.0),
        float2(1.0, 1.0),
        float2(1.0, 0.0)
    };

    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

// 片段着色器：直接取 texture 顯示
fragment float4 fragmentPassthrough(VertexOut in [[stage_in]],
                                    texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    return tex.sample(s, in.texCoord);
}
