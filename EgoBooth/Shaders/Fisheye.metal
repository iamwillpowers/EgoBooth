//
//  Fisheye.metal
//  EgoBooth
//
//  Created by Darkstar on 4/30/21.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    packed_float2 position;
    packed_float2 texCoord;
};

struct VertexOut {
    float4 computedPosition [[position]];
    float2 texCoord;
};

vertex VertexOut vertex_func(
  const device VertexIn* vertex_array [[ buffer(0) ]],
  unsigned int vid [[ vertex_id ]]) {

    VertexIn v = vertex_array[vid];
    VertexOut outVertex = VertexOut();
    outVertex.computedPosition = float4(v.position, 0.0, 1.0);
    outVertex.texCoord = v.texCoord;
    return outVertex;
}

fragment float4 fragment_func(VertexOut interpolated [[stage_in]]) {
  return float4(interpolated.texCoord, 0.0, 1.0);
}

