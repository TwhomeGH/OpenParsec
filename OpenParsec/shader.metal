#include <metal_stdlib>
using namespace metal;

struct Vertex {
	float4 position [[position]];
	float2 texCoord;
};

// Vertex Shader: fullscreen triangle
vertex Vertex vertexShader(uint vertexID [[vertex_id]]) {
	float4 positions[3] = {
		float4(-1.0, -1.0, 0.0, 1.0),
		float4(3.0, -1.0, 0.0, 1.0),
		float4(-1.0, 3.0, 0.0, 1.0)
	};

	Vertex outVertex;
	outVertex.position = positions[vertexID];
	outVertex.texCoord = float2((positions[vertexID].x + 1.0) * 0.5,
								(positions[vertexID].y + 1.0) * 0.5);
	return outVertex;
}

// Fragment Shader: 顯示底色 + Parsec texture
fragment float4 fragmentShader(Vertex in [[stage_in]],
							   texture2d<float> tex [[texture(0)]]) {
	constexpr sampler samp(address::clamp_to_edge, filter::linear);

	// 取 texture 顏色
	float4 texColor = tex.sample(samp, in.texCoord);

	// 合成底色，例如淡紅色
	float4 bgColor = float4(0.5, 0.0, 0.0, 1.0);

	// 這裡可以直接回 texture
	// return texColor;

	// 或先測試混合底色 + texture
	return mix(bgColor, texColor, texColor.a);
}
