//
//  shader.metal
//  OpenParsec
//
//  Created by user on 2026/1/12.
//


#include <metal_stdlib>
using namespace metal;

struct VertexOut {
	float4 position [[position]];
	float2 texCoord;
};

vertex VertexOut vertexPassthrough(uint vertexID [[vertex_id]]) {
	float2 pos[6] = {
		float2(-1,-1), float2(0,1),
		float2(1,-1),  float2(1,1),
		float2(-1,1),  float2(0,0)
	};
	VertexOut out;
	out.position = float4(pos[vertexID*2], 0, 1);
	out.texCoord = pos[vertexID*2+1];
	return out;
}

fragment float4 fragmentPassthrough(VertexOut in [[stage_in]],
								   texture2d<float> tex [[texture(0)]]) {
	constexpr sampler s(coord::normalized, address::clamp_to_edge);
	return tex.sample(s, in.texCoord);
}
