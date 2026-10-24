import Foundation
import Metal
import RealityKit
import simd

/// Runs the shaders in `PostFXShaders` on every frame RealityKit renders: ambient occlusion, colour grade,
/// night glow and edge smoothing.
///
/// RealityKit calls `process` on its render thread, so this class is deliberately not tied
/// to the main thread. Settings are plain values the interface may change at any time.
nonisolated final class PostProcessor: @unchecked Sendable {
    // Settings (changed from the Studio panel)
    var occlusionEnabled = true
    var gradeEnabled = true
    /// Edge smoothing (FXAA). RealityKit's own frame has hard, jagged edges.
    var antialiasingEnabled = true
    /// Contrast-adaptive sharpening of everything that isn't an edge (`-noSharpen YES` to compare).
    var sharpenEnabled = !UserDefaults.standard.bool(forKey: "noSharpen")
    var debugOcclusion = false
    var occlusionStrength: Float = 0.85
    var occlusionRadius: Float = 1.6
    /// Night glow strength (0 in daylight, so the passes are skipped).
    var bloomStrength: Float = 0

    private var aoPipeline: MTLComputePipelineState?
    private var compositePipeline: MTLComputePipelineState?
    private var extractPipeline: MTLComputePipelineState?
    private var blurPipeline: MTLComputePipelineState?
    private var fxaaPipeline: MTLComputePipelineState?
    private var graded: MTLTexture?   // composite output, gamma space, read by FXAA
    private var aoTexture: MTLTexture?
    private var bloomA: MTLTexture?
    private var bloomB: MTLTexture?

    private struct Uniforms {
        var projection: simd_float4x4
        var inverseProjection: simd_float4x4
        var aoTint: SIMD4<Float>
        var fullSize: SIMD2<Float>
        var halfSize: SIMD2<Float>
        var radius: Float
        var strength: Float
        var bias: Float
        var power: Float
        var flags: UInt32
        var vignette: Float
        var contrast: Float
        var saturation: Float
        var bloomStrength: Float
        var bloomThreshold: Float
    }

    func prepare(device: MTLDevice) {
        let library: MTLLibrary
        do { library = try device.makeLibrary(source: PostFXShaders.source, options: nil) } catch {
            NSLog("[Waybill] post-processing shaders failed to compile: %@", "\(error)")
            return
        }
        if let f = library.makeFunction(name: "aoKernel") { aoPipeline = try? device.makeComputePipelineState(function: f) }
        if let f = library.makeFunction(name: "compositeKernel") { compositePipeline = try? device.makeComputePipelineState(function: f) }
        if let f = library.makeFunction(name: "bloomExtract") { extractPipeline = try? device.makeComputePipelineState(function: f) }
        if let f = library.makeFunction(name: "bloomBlur") { blurPipeline = try? device.makeComputePipelineState(function: f) }
        if let f = library.makeFunction(name: "fxaaKernel") { fxaaPipeline = try? device.makeComputePipelineState(function: f) }
    }

    private var loggedOnce = false
    var debugDepth = false

    func process(_ context: ARView.PostProcessContext) {
        if !loggedOnce {
            loggedOnce = true
            let p = context.projection
            NSLog("[Waybill] post: color %d %dx%d, depth %d %dx%d, target %d usage %d", context.sourceColorTexture.pixelFormat.rawValue,
                  context.sourceColorTexture.width, context.sourceColorTexture.height, context.sourceDepthTexture.pixelFormat.rawValue,
                  context.sourceDepthTexture.width, context.sourceDepthTexture.height, context.targetColorTexture.pixelFormat.rawValue,
                  context.targetColorTexture.usage.rawValue)
            let dt = context.sourceDepthTexture
            NSLog("[Waybill] post: depth type %d samples %d usage %d storage %d; color type %d samples %d", dt.textureType.rawValue, dt.sampleCount,
                  dt.usage.rawValue, dt.storageMode.rawValue, context.sourceColorTexture.textureType.rawValue, context.sourceColorTexture.sampleCount)
            NSLog("[Waybill] post: projection c0 %@ c1 %@ c2 %@ c3 %@", "\(p.columns.0)", "\(p.columns.1)", "\(p.columns.2)", "\(p.columns.3)")
        }
        guard let aoPipeline, let compositePipeline, let fxaaPipeline,
              let encoder = context.commandBuffer.makeComputeCommandEncoder() else {
            copy(context)
            return
        }
        let source = context.sourceColorTexture, target = context.targetColorTexture
        let halfWidth = max(source.width / 2, 1), halfHeight = max(source.height / 2, 1)
        if aoTexture?.width != halfWidth || aoTexture?.height != halfHeight {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg16Float, width: halfWidth, height: halfHeight, mipmapped: false)
            d.usage = [.shaderRead, .shaderWrite]
            d.storageMode = .private
            aoTexture = context.device.makeTexture(descriptor: d)
        }
        let qw = max(source.width / 4, 1), qh = max(source.height / 4, 1)
        if bloomA?.width != qw || bloomA?.height != qh {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: qw, height: qh, mipmapped: false)
            d.usage = [.shaderRead, .shaderWrite]
            d.storageMode = .private
            bloomA = context.device.makeTexture(descriptor: d)
            bloomB = context.device.makeTexture(descriptor: d)
        }
        if graded?.width != source.width || graded?.height != source.height {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: source.width, height: source.height, mipmapped: false)
            d.usage = [.shaderRead, .shaderWrite]
            d.storageMode = .private
            graded = context.device.makeTexture(descriptor: d)
        }
        guard let aoTexture, let bloomA, let bloomB, let graded else { encoder.endEncoding(); copy(context); return }
        let bloomOn = bloomStrength > 0.01 && extractPipeline != nil && blurPipeline != nil

        // Formats whose values reach the shader as linear light (sRGB formats are decoded on read, encoded on write)
        let linear = [.bgra8Unorm_srgb, .rgba8Unorm_srgb, .bgra10_xr_srgb, .bgr10_xr_srgb, .rgba16Float, .rgba32Float,
                      .rg11b10Float, .rgb9e5Float].contains(source.pixelFormat)
        var flags: UInt32 = 0
        if occlusionEnabled { flags |= 1 }
        if gradeEnabled { flags |= 2 }
        if debugOcclusion { flags |= 4 }
        if debugDepth { flags |= 16 }
        if linear { flags |= 8 }
        if bloomOn { flags |= 32 }
        if antialiasingEnabled { flags |= 64 }
        if sharpenEnabled { flags |= 128 }

        var u = Uniforms(
            projection: context.projection,
            inverseProjection: context.projection.inverse,
            aoTint: SIMD4(0.56, 0.58, 0.86, 1), // indigo-lavender: occlusion never goes grey or black
            fullSize: SIMD2(Float(source.width), Float(source.height)),
            halfSize: SIMD2(Float(halfWidth), Float(halfHeight)),
            radius: occlusionRadius,
            strength: occlusionStrength,
            bias: 0.12,
            power: 1.5,
            flags: flags,
            vignette: 0.10,
            contrast: 0.14,
            saturation: 1.06,
            bloomStrength: bloomStrength * 1.6,
            bloomThreshold: 0.55)

        if occlusionEnabled {
            encoder.setComputePipelineState(aoPipeline)
            encoder.setTexture(context.sourceDepthTexture, index: 0)
            encoder.setTexture(aoTexture, index: 1)
            encoder.setBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
            dispatch(encoder, aoPipeline, width: halfWidth, height: halfHeight)
        }

        if bloomOn, let extractPipeline, let blurPipeline {
            encoder.setComputePipelineState(extractPipeline)
            encoder.setTexture(source, index: 0)
            encoder.setTexture(bloomA, index: 1)
            encoder.setBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
            dispatch(encoder, extractPipeline, width: qw, height: qh)
            encoder.setComputePipelineState(blurPipeline)
            for _ in 0..<2 { // two rounds of horizontal + vertical blur = a wide, soft glow
                var horizontal = SIMD2<Int32>(1, 0), vertical = SIMD2<Int32>(0, 1)
                encoder.setTexture(bloomA, index: 0)
                encoder.setTexture(bloomB, index: 1)
                encoder.setBytes(&horizontal, length: MemoryLayout<SIMD2<Int32>>.stride, index: 1)
                dispatch(encoder, blurPipeline, width: qw, height: qh)
                encoder.setTexture(bloomB, index: 0)
                encoder.setTexture(bloomA, index: 1)
                encoder.setBytes(&vertical, length: MemoryLayout<SIMD2<Int32>>.stride, index: 1)
                dispatch(encoder, blurPipeline, width: qw, height: qh)
            }
        }

        encoder.setComputePipelineState(compositePipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(aoTexture, index: 1)
        encoder.setTexture(context.sourceDepthTexture, index: 2)
        encoder.setTexture(graded, index: 3)
        encoder.setTexture(bloomA, index: 4)
        encoder.setBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        dispatch(encoder, compositePipeline, width: target.width, height: target.height)

        encoder.setComputePipelineState(fxaaPipeline)
        encoder.setTexture(graded, index: 0)
        encoder.setTexture(target, index: 1)
        encoder.setBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        dispatch(encoder, fxaaPipeline, width: target.width, height: target.height)
        encoder.endEncoding()
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder, _ pipeline: MTLComputePipelineState, width: Int, height: Int) {
        let w = pipeline.threadExecutionWidth
        let h = max(pipeline.maxTotalThreadsPerThreadgroup / w, 1)
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: w, height: min(h, 16), depth: 1))
    }

    /// Fallback: pass the frame through unchanged.
    private func copy(_ context: ARView.PostProcessContext) {
        guard let blit = context.commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: context.sourceColorTexture, to: context.targetColorTexture)
        blit.endEncoding()
    }

    /// Callbacks for ARView, created outside the main actor so RealityKit can call them from its render thread.
    nonisolated static func callbacks(for processor: PostProcessor) -> ARView.RenderCallbacks {
        var callbacks = ARView.RenderCallbacks()
        callbacks.prepareWithDevice = { device in processor.prepare(device: device) }
        callbacks.postProcess = { context in processor.process(context) }
        return callbacks
    }
}
