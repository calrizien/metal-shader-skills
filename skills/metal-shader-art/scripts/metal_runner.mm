// Native, offscreen Metal 4 E2E runner. Uses no window, browser, or legacy queue.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#include <simd/simd.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <stdexcept>
#include <vector>

static void require(bool ok, NSString *message) {
    if (!ok) throw std::runtime_error(message.UTF8String ?: "Metal operation failed");
}

struct Uniforms {
    simd_float2 resolution;
    float time;
    uint32_t frame;
};
static_assert(sizeof(Uniforms) == 16);
static_assert(offsetof(Uniforms, time) == 8 && offsetof(Uniforms, frame) == 12);

static void writeJSON(NSDictionary *value, NSString *path) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value
        options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    require(data && [data writeToFile:path options:NSDataWritingAtomic error:&error],
            error.description ?: @"Cannot write receipt");
}

static void writePNG(const std::vector<float>& pixels, NSUInteger width, NSUInteger height, NSString *path) {
    std::vector<uint8_t> bytes(width * height * 4);
    for (size_t i = 0; i < bytes.size(); i++)
        bytes[i] = uint8_t(std::round(std::clamp(pixels[i], 0.0f, 1.0f) * 255.0f));
    NSData *data = [NSData dataWithBytes:bytes.data() length:bytes.size()];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef image = CGImageCreate(width, height, 8, 32, width * 4, space,
        kCGImageAlphaLast | kCGBitmapByteOrderDefault, provider, nullptr, false, kCGRenderingIntentDefault);
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
        (__bridge CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.png"), 1, nullptr);
    require(image && destination, @"Cannot create PNG");
    CGImageDestinationAddImage(destination, image, nullptr);
    bool ok = CGImageDestinationFinalize(destination);
    CFRelease(destination); CGImageRelease(image);
    CGColorSpaceRelease(space); CGDataProviderRelease(provider);
    require(ok, @"Cannot save PNG");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 5) {
            fprintf(stderr, "usage: metal-runner manifest.json output-dir width height\n");
            return 2;
        }
        NSString *manifestPath = @(argv[1]), *output = @(argv[2]);
        NSUInteger renderWidth = strtoul(argv[3], nullptr, 10), renderHeight = strtoul(argv[4], nullptr, 10);
        NSMutableDictionary *receipt = [@{@"api": @"Metal 4", @"language": @"metal4.0",
            @"mathMode": @"safe", @"status": @"running",
            @"os": NSProcessInfo.processInfo.operatingSystemVersionString,
            @"results": [NSMutableArray array]} mutableCopy];
        NSString *receiptPath = [output stringByAppendingPathComponent:@"metal-results.json"];
        try {
            require(renderWidth > 0 && renderHeight > 0 && renderWidth <= 4096 && renderHeight <= 4096,
                    @"Render size must be 1..4096 per dimension");
            NSError *error = nil;
            require([[NSFileManager defaultManager] createDirectoryAtPath:output
                withIntermediateDirectories:YES attributes:nil error:&error], error.description);
            NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
            require(manifestData != nil, @"Missing harness manifest");
            NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
            require(manifest != nil, error.description);
            id<MTLDevice> device = MTLCreateSystemDefaultDevice();
            require(device && [device supportsFamily:MTLGPUFamilyMetal4], @"A Metal 4 GPU is required");
            receipt[@"device"] = device.name;
            receipt[@"validation"] = @(getenv("MTL_DEBUG_LAYER") && strcmp(getenv("MTL_DEBUG_LAYER"), "1") == 0);
            id<MTL4CommandQueue> queue = [device newMTL4CommandQueue];
            id<MTL4CommandAllocator> allocator = [device newCommandAllocator];
            id<MTL4CommandBuffer> command = [device newCommandBuffer];
            id<MTL4Compiler> compiler = [device newCompilerWithDescriptor:[MTL4CompilerDescriptor new] error:&error];
            id<MTLSharedEvent> event = [device newSharedEvent];
            require(queue && allocator && command && compiler && event, error.description ?: @"Metal 4 initialization failed");
            MTLCompileOptions *options = [MTLCompileOptions new];
            options.languageVersion = MTLLanguageVersion4_0;
            options.mathMode = MTLMathModeSafe;
            options.mathFloatingPointFunctions = MTLMathFloatingPointFunctionsPrecise;
            NSMutableArray *jobs = [NSMutableArray array];
            for (NSString *name in [manifest[@"units"] allKeys]) {
                [jobs addObject:@{@"kind": @"compile", @"name": name, @"code": manifest[@"units"][name]}];
            }
            for (NSDictionary *item in manifest[@"tests"]) {
                NSMutableDictionary *job = [item mutableCopy]; job[@"kind"] = @"property"; [jobs addObject:job];
            }
            for (NSDictionary *item in manifest[@"renders"]) {
                NSMutableDictionary *job = [item mutableCopy]; job[@"kind"] = @"render"; [jobs addObject:job];
            }
            NSUInteger failures = 0, index = 0;
            uint64_t eventValue = 0;
            for (NSDictionary *job in jobs) {
                @autoreleasepool {
                    NSString *kind = job[@"kind"], *name = job[@"name"];
                    NSMutableDictionary *result = [@{@"kind": kind, @"name": name, @"pass": @NO} mutableCopy];
                    [receipt[@"results"] addObject:result];
                    NSString *stem = [NSString stringWithFormat:@"%03lu", (unsigned long)index++];
                    NSString *sourcePath = [output stringByAppendingPathComponent:[stem stringByAppendingString:@".metal"]];
                    require([job[@"code"] writeToFile:sourcePath atomically:YES encoding:NSUTF8StringEncoding error:&error],
                            error.description);
                    result[@"source"] = sourcePath.lastPathComponent;
                    error = nil;
                    __attribute__((objc_precise_lifetime)) id<MTLLibrary> library =
                        [device newLibraryWithSource:job[@"code"] options:options error:&error];
                    if (!library) {
                        result[@"error"] = error.description ?: @"Library compilation failed";
                    } else if ([kind isEqual:@"compile"]) {
                        result[@"pass"] = @YES;
                    } else {
                        MTL4LibraryFunctionDescriptor *vertex = [MTL4LibraryFunctionDescriptor new];
                        vertex.library = library; vertex.name = @"fullscreenVertex";
                        MTL4LibraryFunctionDescriptor *fragment = [MTL4LibraryFunctionDescriptor new];
                        fragment.library = library; fragment.name = @"shaderFragment";
                        MTL4RenderPipelineDescriptor *pipelineDesc = [MTL4RenderPipelineDescriptor new];
                        pipelineDesc.vertexFunctionDescriptor = vertex;
                        pipelineDesc.fragmentFunctionDescriptor = fragment;
                        pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA32Float;
                        __attribute__((objc_precise_lifetime)) id<MTLRenderPipelineState> pipeline =
                            [compiler newRenderPipelineStateWithDescriptor:pipelineDesc
                            compilerTaskOptions:nil error:&error];
                        if (!pipeline) {
                            result[@"error"] = error.description ?: @"Metal 4 pipeline compilation failed";
                        } else {
                            bool property = [kind isEqual:@"property"];
                            NSUInteger width = property ? 128 : renderWidth, height = property ? 128 : renderHeight;
                            Uniforms uniforms = {{float(width), float(height)}, [job[@"time"] floatValue],
                                [job[@"frame"] unsignedIntValue]};
                            __attribute__((objc_precise_lifetime)) id<MTLBuffer> uniformBuffer =
                                [device newBufferWithBytes:&uniforms length:sizeof(uniforms)
                                options:MTLResourceStorageModeShared];
                            MTLTextureDescriptor *textureDesc = [MTLTextureDescriptor
                                texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float width:width height:height mipmapped:NO];
                            textureDesc.storageMode = MTLStorageModeShared;
                            textureDesc.usage = MTLTextureUsageRenderTarget;
                            __attribute__((objc_precise_lifetime)) id<MTLTexture> texture =
                                [device newTextureWithDescriptor:textureDesc];
                            MTL4ArgumentTableDescriptor *tableDesc = [MTL4ArgumentTableDescriptor new];
                            tableDesc.maxBufferBindCount = 1;
                            __attribute__((objc_precise_lifetime)) id<MTL4ArgumentTable> table =
                                [device newArgumentTableWithDescriptor:tableDesc error:&error];
                            __attribute__((objc_precise_lifetime)) id<MTLResidencySet> residency =
                                [device newResidencySetWithDescriptor:[MTLResidencySetDescriptor new] error:&error];
                            require(uniformBuffer && texture && table && residency, error.description ?: @"Resource allocation failed");
                            [table setAddress:uniformBuffer.gpuAddress atIndex:0];
                            [residency addAllocation:uniformBuffer]; [residency addAllocation:texture]; [residency commit];
                            [queue addResidencySet:residency];
                            [allocator reset];
                            [command beginCommandBufferWithAllocator:allocator];
                            MTL4RenderPassDescriptor *pass = [MTL4RenderPassDescriptor new];
                            pass.colorAttachments[0].texture = texture;
                            pass.colorAttachments[0].loadAction = MTLLoadActionClear;
                            pass.colorAttachments[0].storeAction = MTLStoreActionStore;
                            // Sentinel catches incomplete rasterization as well as nonfinite shader output.
                            pass.colorAttachments[0].clearColor = MTLClearColorMake(NAN, NAN, NAN, NAN);
                            id<MTL4RenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
                            require(encoder != nil, @"Cannot create Metal 4 render encoder");
                            [encoder setRenderPipelineState:pipeline];
                            [encoder setArgumentTable:table atStages:MTLRenderStageFragment];
                            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
                            [encoder endEncoding]; [command endCommandBuffer];
                            id<MTL4CommandBuffer> commands[] = {command};
                            [queue commit:commands count:1];
                            [queue signalEvent:event value:++eventValue];
                            require([event waitUntilSignaledValue:eventValue timeoutMS:60000], @"GPU wait timed out");
                            std::vector<float> pixels(width * height * 4);
                            [texture getBytes:pixels.data() bytesPerRow:width * 4 * sizeof(float)
                                fromRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0];
                            [queue removeResidencySet:residency];
                            NSUInteger nonfinite = 0;
                            double energy = 0;
                            for (size_t p = 0; p < pixels.size(); p++) {
                                if (!std::isfinite(pixels[p])) nonfinite++;
                                else if (p % 4 != 3) energy += std::abs(pixels[p]);
                            }
                            result[@"nonfinite"] = @(nonfinite);
                            result[@"width"] = @(width); result[@"height"] = @(height);
                            bool passResult = nonfinite == 0;
                            if (property) {
                                NSMutableDictionary *counts = [NSMutableDictionary dictionary];
                                for (int bit = 1; bit <= 128; bit <<= 1) {
                                    NSUInteger count = 0;
                                    for (size_t p = 0; p < pixels.size(); p += 4)
                                        if (std::isfinite(pixels[p]) && (int(std::lround(pixels[p])) & bit)) count++;
                                    NSString *key = [NSString stringWithFormat:@"%d", bit];
                                    double allowance = [job[@"allow"][key] doubleValue];
                                    counts[key] = @(count);
                                    if (double(count) / (width * height) > allowance) passResult = false;
                                }
                                result[@"failureBits"] = counts;
                                result[@"allow"] = job[@"allow"] ?: @{};
                                result[@"samples"] = @(width * height);
                            } else {
                                result[@"meanAbsRGB"] = @(energy / (width * height * 3));
                                passResult = passResult && energy > 1e-6;
                                if (nonfinite == 0) {
                                    NSString *png = [name stringByAppendingPathExtension:@"png"];
                                    writePNG(pixels, width, height, [output stringByAppendingPathComponent:png]);
                                    result[@"image"] = png;
                                }
                            }
                            result[@"pass"] = @(passResult);
                        }
                    }
                    if (![result[@"pass"] boolValue]) failures++;
                    printf("%s %s %s\n", [result[@"pass"] boolValue] ? "PASS" : "FAIL", kind.UTF8String, name.UTF8String);
                    if (result[@"error"]) fprintf(stderr, "%s\n", [result[@"error"] UTF8String]);
                    fflush(stdout);
                    receipt[@"failures"] = @(failures);
                    writeJSON(receipt, receiptPath);
                }
            }
            receipt[@"status"] = failures ? @"failed" : @"passed";
            writeJSON(receipt, receiptPath);
            return failures ? 1 : 0;
        } catch (const std::exception& e) {
            receipt[@"status"] = @"failed"; receipt[@"error"] = @(e.what());
            writeJSON(receipt, receiptPath);
            fprintf(stderr, "%s\n", e.what());
            return 1;
        }
    }
}
