import Foundation

/// GPU shader source for `PostProcessor`, compiled on the device at launch (`makeLibrary(source:)`).
/// Keeping it as text means the project builds without Xcode's separate Metal toolchain.
enum PostFXShaders {
    nonisolated static let source = #"""
// Post-processing for the 3D world, run on the GPU after RealityKit has drawn each frame.
//
// 1. aoKernel        – ambient occlusion at half resolution: darkens corners, gaps and contact points
//                      (the soft "clay render" shading from the reference).
// 2. compositeKernel – blends the occlusion in (tinted indigo, never black), then a gentle colour grade
//                      and vignette, into an intermediate image (perceptual/gamma space).
// 3. fxaaKernel      – smooths jagged edges (FXAA 3.11, quality preset) and writes the final image.

#include <metal_stdlib>
using namespace metal;

struct PostUniforms {
    float4x4 projection;
    float4x4 inverseProjection;
    float4   aoTint;        // colour that occlusion fades towards (indigo)
    float2   fullSize;      // full-resolution size in pixels
    float2   halfSize;      // occlusion buffer size
    float    radius;        // occlusion search radius in metres
    float    strength;      // 0 = no occlusion, 1 = full
    float    bias;          // avoids self-shadowing acne
    float    power;         // contrast of the occlusion
    uint     flags;         // bit 0: AO on, bit 1: grade on, bit 2: debug AO, bit 3: source is linear, bit 6: FXAA
    float    vignette;
    float    contrast;
    float    saturation;
    float    bloomStrength;  // 0 = off (daytime)
    float    bloomThreshold; // brightness above which things glow
};

constant uint kAO = 1u, kGrade = 2u, kDebug = 4u, kLinear = 8u, kBloom = 32u, kFXAA = 64u, kSharpen = 128u;
constexpr sampler nearestClamp(coord::normalized, filter::nearest, address::clamp_to_edge);

// Depth at a screen uv (0…1), read from the nearest pixel.
static float depthAt(depth2d<float, access::read> t, float2 uv) {
    uint2 size = uint2(t.get_width(), t.get_height());
    uint2 p = uint2(clamp(uv * float2(size), float2(0), float2(size) - 1.0));
    return t.read(p);
}

// Centre of the full-resolution pixel under a uv. Depth must be paired with the position it was
// rendered at: using the depth of one pixel at a uv up to half a pixel away tilts flat ground by a
// sub-pixel amount that changes from pixel to pixel, which showed up as faint lines across the screen.
static float2 pixelCenter(float2 uv, float2 size) {
    return (clamp(floor(uv * size), float2(0), size - 1.0) + 0.5) / size;
}

// View-space position (camera at origin, looking down -Z) from a screen uv and a depth value.
static float3 viewPosition(float2 uv, float depth, constant PostUniforms &u) {
    float4 ndc = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
    float4 p = u.inverseProjection * ndc;
    return p.xyz / p.w;
}

static float2 projectToUV(float3 p, constant PostUniforms &u) {
    float4 clip = u.projection * float4(p, 1.0);
    float2 ndc = clip.xy / clip.w;
    return float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}

// Interleaved gradient noise: a well-distributed per-pixel random number (smooth-looking noise).
static float ign(float2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, float2(0.06711056, 0.00583715))));
}

kernel void aoKernel(depth2d<float, access::read> depthTex [[texture(0)]],
                     texture2d<half, access::write> aoOut [[texture(1)]],
                     constant PostUniforms &u [[buffer(0)]],
                     uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uint(u.halfSize.x) || gid.y >= uint(u.halfSize.y)) return;
    float2 uv = pixelCenter((float2(gid) + 0.5) / u.halfSize, u.fullSize);
    float d = depthAt(depthTex, uv);
    if (!isfinite(d) || d <= 0.0) { aoOut.write(half4(1, 0, 0, 0), gid); return; } // no usable depth (e.g. simulator)
    float3 P = viewPosition(uv, d, u);

    // Normal from neighbouring depths (pick the closer neighbour on each axis to keep edges clean)
    float2 texel = 1.0 / u.fullSize;
    float3 pr = viewPosition(uv + float2(texel.x, 0), depthAt(depthTex, uv + float2(texel.x, 0)), u);
    float3 pl = viewPosition(uv - float2(texel.x, 0), depthAt(depthTex, uv - float2(texel.x, 0)), u);
    float3 pd = viewPosition(uv + float2(0, texel.y), depthAt(depthTex, uv + float2(0, texel.y)), u);
    float3 pu = viewPosition(uv - float2(0, texel.y), depthAt(depthTex, uv - float2(0, texel.y)), u);
    float3 dx = abs(pr.z - P.z) < abs(P.z - pl.z) ? pr - P : P - pl;
    float3 dy = abs(pd.z - P.z) < abs(P.z - pu.z) ? pd - P : P - pu;
    float3 N = normalize(cross(dy, dx));
    if (dot(N, -P) < 0) N = -N;

    // Tangent frame, rotated randomly per pixel
    float angle = ign(float2(gid)) * 6.2831853;
    float3 helper = abs(N.y) < 0.95 ? float3(0, 1, 0) : float3(1, 0, 0);
    float3 T = normalize(cross(helper, N));
    float3 B = cross(N, T);
    float ca = cos(angle), sa = sin(angle);
    float3 T2 = T * ca + B * sa;
    float3 B2 = -T * sa + B * ca;

    const int count = 12;
    float occlusion = 0.0;
    for (int i = 0; i < count; i++) {
        // Points spread over a hemisphere (golden-angle spiral), denser near the centre
        float t = (float(i) + 0.5) / float(count);
        float phi = float(i) * 2.39996323;
        float r = sqrt(t);
        float3 h = float3(cos(phi) * r, sin(phi) * r, sqrt(max(0.0, 1.0 - t)));
        float scale = mix(0.15, 1.0, t * t);
        float3 S = P + (T2 * h.x + B2 * h.y + N * h.z) * (u.radius * scale);

        float2 suv = projectToUV(S, u);
        if (any(suv < 0.0) || any(suv > 1.0)) continue;
        suv = pixelCenter(suv, u.fullSize);
        // Occluded when the real surface found there rises above this pixel's tangent plane.
        // (Testing the angle instead of a depth difference keeps flat ground free of banding.)
        float3 Q = viewPosition(suv, depthAt(depthTex, suv), u);
        float3 v = Q - P;
        float dist = length(v);
        float rise = dot(v, N) / max(dist, 0.0001);
        float falloff = saturate(1.0 - dist / (u.radius * 1.6));
        occlusion += smoothstep(u.bias, u.bias + 0.35, rise) * falloff;
    }
    float ao = 1.0 - saturate(occlusion / float(count) * 1.7);
    ao = pow(saturate(ao), u.power);
    aoOut.write(half4(half(ao), half(P.z), 0, 0), gid);
}

// ---- Bloom: bright parts → quarter resolution → blurred → added back as a soft glow ----

kernel void bloomExtract(texture2d<float, access::read> source [[texture(0)]],
                         texture2d<half, access::write> out [[texture(1)]],
                         constant PostUniforms &u [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
    uint2 base = gid * 4;
    uint2 maxP = uint2(source.get_width() - 1, source.get_height() - 1);
    float3 sum = 0;
    for (uint y = 0; y < 4; y += 2) {
        for (uint x = 0; x < 4; x += 2) {
            float3 c = source.read(min(base + uint2(x + 1, y + 1), maxP)).rgb;
            if ((u.flags & kLinear) == 0) c = pow(max(c, 0.0), 2.2);
            sum += c;
        }
    }
    float3 c = sum * 0.25;
    float luma = max(c.r, max(c.g, c.b));
    float soft = smoothstep(u.bloomThreshold, u.bloomThreshold + 0.25, luma);
    out.write(half4(half3(c * soft), 1), gid);
}

static constant float kGauss[5] = { 0.2270270, 0.1945946, 0.1216216, 0.0540541, 0.0162162 };

kernel void bloomBlur(texture2d<half, access::read> src [[texture(0)]],
                      texture2d<half, access::write> dst [[texture(1)]],
                      constant int2 &dir [[buffer(1)]],
                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    int2 size = int2(src.get_width(), src.get_height());
    float3 acc = float3(src.read(gid).rgb) * kGauss[0];
    for (int i = 1; i < 5; i++) {
        int2 o = dir * (i * 2 - 1); // spread taps wider for a softer glow
        acc += float3(src.read(uint2(clamp(int2(gid) + o, int2(0), size - 1))).rgb) * kGauss[i];
        acc += float3(src.read(uint2(clamp(int2(gid) - o, int2(0), size - 1))).rgb) * kGauss[i];
    }
    dst.write(half4(half3(acc), 1), gid);
}

static float3 toGamma(float3 c) { return pow(max(c, 0.0), 1.0 / 2.2); }
static float3 toLinear(float3 c) { return pow(max(c, 0.0), 2.2); }

kernel void compositeKernel(texture2d<float, access::read> source [[texture(0)]],
                            texture2d<half, access::read> aoTex [[texture(1)]],
                            depth2d<float, access::read> depthTex [[texture(2)]],
                            texture2d<half, access::write> target [[texture(3)]],   // intermediate, gamma space
                            texture2d<half, access::sample> bloomTex [[texture(4)]],
                            constant PostUniforms &u [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= target.get_width() || gid.y >= target.get_height()) return;
    float4 color = source.read(gid);
    float3 c = color.rgb;
    bool linearSource = (u.flags & kLinear) != 0;
    float2 uv = (float2(gid) + 0.5) / u.fullSize;

    float ao = 1.0;
    if ((u.flags & kAO) != 0) {
        // Depth-aware 3×3 upsample + blur of the half-resolution occlusion (no halos around edges)
        float dHere = depthAt(depthTex, uv);
        bool validDepth = isfinite(dHere) && dHere > 0.0;
        float z = validDepth ? viewPosition(uv, dHere, u).z : 0.0;
        float2 lowPos = uv * u.halfSize - 0.5;
        int2 base = int2(floor(lowPos));
        float sum = 0.0, weights = 0.0;
        for (int y = -1; y <= 2; y++) {
            for (int x = -1; x <= 2; x++) {
                int2 q = clamp(base + int2(x, y), int2(0), int2(u.halfSize) - 1);
                half2 s = aoTex.read(uint2(q)).xy;
                float2 offset = float2(q) - lowPos;
                float spatial = exp(-dot(offset, offset) * 0.45);
                float depthDiff = abs(float(s.y) - z) / (abs(z) * 0.02 + 0.05);
                float w = spatial * exp(-depthDiff * depthDiff);
                sum += float(s.x) * w;
                weights += w;
            }
        }
        ao = (validDepth && weights > 0.0001) ? sum / weights : 1.0;
        ao = mix(1.0, ao, u.strength);
    }

    if ((u.flags & 16u) != 0) {
        float dz = depthAt(depthTex, uv);
        float vz = viewPosition(uv, dz, u).z;
        if (isnan(dz) || isinf(dz)) { target.write(half4(1, 0, 0, 1), gid); return; }
        if (dz <= 0.0) { target.write(half4(0, 1, 0, 1), gid); return; }
        target.write(half4(fract(-vz / 10.0), 0.0, saturate(-vz / 300.0) * 0.5 + 0.5, 1.0), gid);
        return;
    }
    if ((u.flags & kDebug) != 0) {
        target.write(half4(half3(ao), 1.0), gid);
        return;
    }

    // Glow (added in linear light, before grading)
    if ((u.flags & kBloom) != 0) {
        constexpr sampler linearClamp(coord::normalized, filter::linear, address::clamp_to_edge);
        float3 glow = float3(bloomTex.sample(linearClamp, uv).rgb);
        float3 lin = linearSource ? c : pow(max(c, 0.0), 2.2);
        lin += glow * u.bloomStrength;
        c = linearSource ? lin : pow(max(lin, 0.0), 1.0 / 2.2);
    }

    // Work in a perceptual (gamma) space for grading
    float3 g = linearSource ? toGamma(c) : c;
    // Occlusion fades towards the indigo tint instead of black (like the reference's blue shadows)
    g *= mix(u.aoTint.rgb, float3(1.0), ao);

    if ((u.flags & kGrade) != 0) {
        g = saturate(g);
        float3 s = g * g * (3.0 - 2.0 * g);              // gentle S-curve
        g = mix(g, s, u.contrast);
        float luma = dot(g, float3(0.2126, 0.7152, 0.0722));
        g = mix(float3(luma), g, u.saturation);
        float2 centered = (uv - 0.5) * float2(u.fullSize.x / u.fullSize.y, 1.0);
        float vig = smoothstep(0.45, 1.25, length(centered));
        g *= 1.0 - u.vignette * vig;
    }
    target.write(half4(half3(g), half(color.a)), gid);
}

// ---- FXAA 3.11 (Timothy Lottes), quality preset, as a compute pass ----

static float lumaOf(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }

kernel void fxaaKernel(texture2d<half, access::sample> src [[texture(0)]],
                       texture2d<float, access::write> target [[texture(1)]],
                       constant PostUniforms &u [[buffer(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= target.get_width() || gid.y >= target.get_height()) return;
    constexpr sampler ls(coord::normalized, filter::linear, address::clamp_to_edge);
    bool linearTarget = (u.flags & kLinear) != 0;
    float2 rcp = 1.0 / u.fullSize;
    float2 uv = (float2(gid) + 0.5) * rcp;
    float4 rgbaM = float4(src.sample(ls, uv));
    float lumaM = lumaOf(rgbaM.rgb);
    float lumaS = lumaOf(float3(src.sample(ls, uv + float2(0, rcp.y)).rgb));
    float lumaE = lumaOf(float3(src.sample(ls, uv + float2(rcp.x, 0)).rgb));
    float lumaN = lumaOf(float3(src.sample(ls, uv - float2(0, rcp.y)).rgb));
    float lumaW = lumaOf(float3(src.sample(ls, uv - float2(rcp.x, 0)).rgb));
    float rangeMax = max(max(lumaN, lumaW), max(lumaE, max(lumaS, lumaM)));
    float rangeMin = min(min(lumaN, lumaW), min(lumaE, min(lumaS, lumaM)));
    float range = rangeMax - rangeMin;
    if ((u.flags & kFXAA) == 0 || range < max(0.0312, rangeMax * 0.125)) {
        float3 c = rgbaM.rgb;
        if ((u.flags & kSharpen) != 0) {
            // Not an edge: contrast-adaptive sharpening (as in AMD's CAS) brings back the crispness the frame loses
            // in rendering. It sharpens less where the contrast is already high, so it never rings or brings back jaggies.
            float3 n = float3(src.sample(ls, uv - float2(0, rcp.y)).rgb), so = float3(src.sample(ls, uv + float2(0, rcp.y)).rgb);
            float3 e = float3(src.sample(ls, uv + float2(rcp.x, 0)).rgb), w = float3(src.sample(ls, uv - float2(rcp.x, 0)).rgb);
            float3 mn = min(c, min(min(n, so), min(e, w))), mx = max(c, max(max(n, so), max(e, w)));
            float3 amp = sqrt(saturate(min(mn, 2.0 - mx) / max(mx, 1e-4)));
            float3 wgt = amp * (-1.0 / mix(8.0, 5.0, 0.55));
            c = saturate((c + (n + so + e + w) * wgt) / (1.0 + 4.0 * wgt));
        }
        target.write(float4(linearTarget ? toLinear(c) : c, rgbaM.a), gid);
        return;
    }
    float lumaNW = lumaOf(float3(src.sample(ls, uv + float2(-rcp.x, -rcp.y)).rgb));
    float lumaSE = lumaOf(float3(src.sample(ls, uv + float2(rcp.x, rcp.y)).rgb));
    float lumaNE = lumaOf(float3(src.sample(ls, uv + float2(rcp.x, -rcp.y)).rgb));
    float lumaSW = lumaOf(float3(src.sample(ls, uv + float2(-rcp.x, rcp.y)).rgb));

    float lumaNS = lumaN + lumaS;
    float lumaWE = lumaW + lumaE;
    float subpixRcpRange = 1.0 / range;
    float subpixNSWE = lumaNS + lumaWE;
    float edgeHorz1 = (-2.0 * lumaM) + lumaNS;
    float edgeVert1 = (-2.0 * lumaM) + lumaWE;
    float lumaNESE = lumaNE + lumaSE;
    float lumaNWNE = lumaNW + lumaNE;
    float edgeHorz2 = (-2.0 * lumaE) + lumaNESE;
    float edgeVert2 = (-2.0 * lumaN) + lumaNWNE;
    float lumaNWSW = lumaNW + lumaSW;
    float lumaSWSE = lumaSW + lumaSE;
    float edgeHorz4 = (abs(edgeHorz1) * 2.0) + abs(edgeHorz2);
    float edgeVert4 = (abs(edgeVert1) * 2.0) + abs(edgeVert2);
    float edgeHorz3 = (-2.0 * lumaW) + lumaNWSW;
    float edgeVert3 = (-2.0 * lumaS) + lumaSWSE;
    float edgeHorz = abs(edgeHorz3) + edgeHorz4;
    float edgeVert = abs(edgeVert3) + edgeVert4;
    float subpixNWSWNESE = lumaNWSW + lumaNESE;
    float lengthSign = rcp.x;
    bool horzSpan = edgeHorz >= edgeVert;
    float subpixA = subpixNSWE * 2.0 + subpixNWSWNESE;
    if (!horzSpan) { lumaN = lumaW; lumaS = lumaE; } else { lengthSign = rcp.y; }
    float subpixB = (subpixA * (1.0 / 12.0)) - lumaM;
    float gradientN = lumaN - lumaM;
    float gradientS = lumaS - lumaM;
    float lumaNN = lumaN + lumaM;
    float lumaSS = lumaS + lumaM;
    bool pairN = abs(gradientN) >= abs(gradientS);
    float gradient = max(abs(gradientN), abs(gradientS));
    if (pairN) lengthSign = -lengthSign;
    float subpixC = saturate(abs(subpixB) * subpixRcpRange);

    float2 posB = uv;
    float2 offNP = horzSpan ? float2(rcp.x, 0.0) : float2(0.0, rcp.y);
    if (!horzSpan) posB.x += lengthSign * 0.5; else posB.y += lengthSign * 0.5;
    float2 posN = posB - offNP;
    float2 posP = posB + offNP;
    float subpixD = ((-2.0) * subpixC) + 3.0;
    float lumaEndN = lumaOf(float3(src.sample(ls, posN).rgb));
    float subpixE = subpixC * subpixC;
    float lumaEndP = lumaOf(float3(src.sample(ls, posP).rgb));
    if (!pairN) lumaNN = lumaSS;
    float gradientScaled = gradient * (1.0 / 4.0);
    float lumaMM = lumaM - lumaNN * 0.5;
    float subpixF = subpixD * subpixE;
    bool lumaMLTZero = lumaMM < 0.0;
    lumaEndN -= lumaNN * 0.5;
    lumaEndP -= lumaNN * 0.5;
    bool doneN = abs(lumaEndN) >= gradientScaled;
    bool doneP = abs(lumaEndP) >= gradientScaled;
    const float steps[11] = { 1.0, 1.0, 1.0, 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0 };
    for (int i = 0; i < 11 && !(doneN && doneP); i++) {
        if (!doneN) {
            posN -= offNP * steps[i];
            lumaEndN = lumaOf(float3(src.sample(ls, posN).rgb)) - lumaNN * 0.5;
            doneN = abs(lumaEndN) >= gradientScaled;
        }
        if (!doneP) {
            posP += offNP * steps[i];
            lumaEndP = lumaOf(float3(src.sample(ls, posP).rgb)) - lumaNN * 0.5;
            doneP = abs(lumaEndP) >= gradientScaled;
        }
    }
    float dstN = horzSpan ? uv.x - posN.x : uv.y - posN.y;
    float dstP = horzSpan ? posP.x - uv.x : posP.y - uv.y;
    bool goodSpanN = (lumaEndN < 0.0) != lumaMLTZero;
    bool goodSpanP = (lumaEndP < 0.0) != lumaMLTZero;
    float spanLength = dstP + dstN;
    bool directionN = dstN < dstP;
    float dst = min(dstN, dstP);
    bool goodSpan = directionN ? goodSpanN : goodSpanP;
    float subpixG = subpixF * subpixF;
    float pixelOffset = (dst * (-1.0 / spanLength)) + 0.5;
    float subpixH = subpixG * 0.5; // sub-pixel smoothing amount (lower = crisper)
    float pixelOffsetGood = goodSpan ? pixelOffset : 0.0;
    float pixelOffsetSubpix = max(pixelOffsetGood, subpixH);
    float2 finalUV = uv;
    if (!horzSpan) finalUV.x += pixelOffsetSubpix * lengthSign; else finalUV.y += pixelOffsetSubpix * lengthSign;
    float3 c = float3(src.sample(ls, finalUV).rgb);
    target.write(float4(linearTarget ? toLinear(c) : c, rgbaM.a), gid);
}
"""#
}
