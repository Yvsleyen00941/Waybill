#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

/// Flowing water (`Materials.flowingWater`): the water material itself, with its ripple texture scrolled on the GPU
/// from RealityKit's clock, so the river flows without the app rebuilding the material every frame.
/// Texture coordinates as PhysicallyBasedMaterial computes them (its scale and offset), plus the flow:
/// custom value xy = how far the ripples move per second, in texture repeats.
[[visible]]
void waterFlow(realitykit::geometry_parameters params)
{
    auto uniforms = params.uniforms();
    float2 offset = fract(uniforms.custom_parameter().xy * uniforms.time());
    params.geometry().set_uv0(uniforms.uv0_transform() * params.geometry().uv0() + uniforms.uv0_offset() + offset);
}
