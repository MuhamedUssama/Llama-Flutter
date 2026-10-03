# llama_flutter_android

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: Android](https://img.shields.io/badge/Platform-Android-green.svg)](https://developer.android.com/)

Run GGUF models on Android with [llama.cpp](https://github.com/ggerganov/llama.cpp) - A simple, MIT-licensed Flutter plugin.

## Features

- **Android Only** - Optimized specifically for Android
- **Simple API** - Easy-to-use Dart interface with Pigeon type safety
- **Token Streaming** - Real-time token generation with EventChannel
- **Stop Generation** - Cancel text generation mid-process on Android devices
- **18 Parameters** - Complete control: temperature, penalties, mirostat, seed, and more
- **7 Chat Templates** - ChatML, Llama-2, Alpaca, Vicuna, Phi, Gemma, Zephyr
- **Auto-Detection** - Chat templates detected from model filename
- **Vulkan GPU Acceleration** - Real GPU inference via `GGML_VULKAN` on supported devices
- **GPU Detection API** - `detectGpu()` returns device name, Vulkan support, memory info, and a recommended layer count
- **llama.cpp** - Vendored b10068 sources, built with the Vulkan backend
- **ARM64 Optimized** - NEON and dot product optimizations enabled

## Requirements

- Flutter 3.24.0+
- Dart SDK 3.3.0+
- Android API 26+ (Android 8.0)
- NDK r27+ (for 16KB page size support)
- ARM64 (`arm64-v8a`)
- A host C/C++ compiler for the Vulkan shader generator. The build uses
  `glslc` from `VULKAN_SDK`/`PATH`, or the selected NDK's `shader-tools`.
- Network access on the first native configure to fetch SHA-256-checked
  Vulkan and SPIR-V headers pinned to `vulkan-sdk-1.4.350.0`.

GPU inference additionally requires a driver usable by the vendored backend:
Vulkan 1.2 or newer and 16-bit storage buffer support. CPU inference remains
available when those requirements are not met. A Vulkan 1.1 device can pass
`detectGpu()` and still be unavailable to this inference backend.

## Installation

1) Add to your `pubspec.yaml`:

```yaml
dependencies:
  llama_flutter_android:
    path: ../Llama-Flutter # Relative to the consuming app's pubspec.yaml
```

2) If your app uses R8/proguard (`minifyEnabled true`), create or extend
`android/app/proguard-rules.pro` with:

```proguard
-keep class com.write4me.llama_flutter_android.** { *; }

-keep class kotlin.jvm.functions.Function1
-keepclassmembers class * implements kotlin.jvm.functions.Function1 {
    public java.lang.Object invoke(java.lang.Object);
}

-keepclasseswithmembernames class * {
    native <methods>;
}
```

3) And reference it from `android/app/build.gradle` (or `.kts`):

```kotlin
android {
  buildTypes {
        release {
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
  }
}
```

> Note: since 0.2.5 the plugin no longer declares a foreground service or
> the `FOREGROUND_SERVICE_SPECIAL_USE` permission — nothing to declare in
> Play Console. If you need inference to survive backgrounding, run your
> own foreground service in the app.

## Quick Start

### Basic Usage

```dart
import 'package:llama_flutter_android/llama_flutter_android.dart';

// Initialize controller
final controller = LlamaController();

// Load model
await controller.loadModel(
  modelPath: '/path/to/model.gguf',
  threads: 4,
  contextSize: 2048,
);

// Generate text with streaming
StreamSubscription? subscription;
subscription = controller.generate(
  prompt: 'Write a story about a robot',
  maxTokens: 512,
  temperature: 0.7,
).listen(
  (token) => print(token),  // Print each token as it arrives
  onDone: () => print('Generation complete!'),
  onError: (error) => print('Error: $error'),
);

// Stop generation mid-process (critical for UX!)
await controller.stop();
subscription?.cancel();

// Clean up
await controller.dispose();
```

### Chat Mode with Templates

```dart
// Chat with automatic template formatting
controller.generateChat(
  messages: [
    ChatMessage(role: 'system', content: 'You are a helpful assistant'),
    ChatMessage(role: 'user', content: 'Explain quantum computing'),
  ],
  template: 'chatml', // Auto-detected if null
  temperature: 0.7,
  maxTokens: 1000,
).listen((token) => print(token));
```

### Advanced Parameters

```dart
// Fine-grained control over generation
controller.generate(
  prompt: 'Explain machine learning',
  maxTokens: 1000,
  // Sampling
  temperature: 0.8,      // Creativity (0.0-2.0)
  topP: 0.9,             // Nucleus sampling
  topK: 40,              // Top-K sampling
  minP: 0.05,            // Minimum probability
  // Penalties (reduce repetition)
  repeatPenalty: 1.2,    // Penalize repeated tokens
  frequencyPenalty: 0.5, // Penalize frequent tokens
  presencePenalty: 0.3,  // Penalize token presence
  repeatLastN: 64,       // Penalty window size
  // Reproducibility
  seed: 42,              // Fixed seed for same output
  // Mirostat (perplexity control)
  mirostat: 2,           // 0=off, 1=v1, 2=v2
  mirostatTau: 5.0,      // Target perplexity
  mirostatEta: 0.1,      // Learning rate
).listen((token) => print(token));

// Stop anytime!
await controller.stop();
```

### GPU Detection

```dart
// Detect GPU capabilities before loading a model
final gpu = await controller.detectGpu();

print('Vulkan supported: ${gpu.vulkanSupported}');
print('GPU: ${gpu.gpuName}');                          // e.g. "Adreno (TM) 740"
print('Free RAM: ${gpu.freeRamBytes ~/ 1024 ~/ 1024} MB');
print('Recommended layers: ${gpu.recommendedGpuLayers}'); // 0, 16, or 99

// Use the recommendation (or override it)
await controller.loadModel(
  modelPath: '/path/to/model.gguf',
  gpuLayers: gpu.recommendedGpuLayers, // Recommendation only; benchmark smaller values first
);
```

**`recommendedGpuLayers` values:**

| Value | Meaning |
|---|---|
| `0` | CPU only — no Vulkan capability or insufficient RAM |
| `16` | Partial offload — Vulkan supported but limited RAM/VRAM |
| `99` | Full offload — llama.cpp clamps to model's actual layer count |

> **Note:** `deviceLocalMemoryBytes` on Android equals total system RAM (unified memory architecture), not dedicated VRAM. Use `freeRamBytes` for memory pressure decisions.

`detectGpu()` reports Vulkan capabilities and a model-independent memory
recommendation; it does not initialize llama.cpp's inference backend or prove
that a particular model can be offloaded. The existing `0`/`16`/`99` heuristic
is unchanged, and Mali devices are not excluded from recommendations.

This fork compiles Vulkan inference into the native libraries. `gpuLayers: 0`
(also the default when omitted) selects CPU-only execution. Positive values
request Vulkan layer offload when the backend is available; `99` is a high
request which llama.cpp clamps to the model's offloadable layer count.
GPU allocations on Android's unified memory still consume system RAM.

If backend registration fails or no compatible Vulkan device is found, loading
falls back to CPU and logs the reason. Model/context allocation failures return
a load error; retry explicitly with `gpuLayers: 0`. Driver bugs can still cause
native failures during inference, and enabling Vulkan does not guarantee better
performance on older Mali GPUs.

For a first manual benchmark on an older Mali device, compare `0`, `4`, and `8`
with the same model, prompt, context size and thread count. Dispose the loaded
model between runs. Start with partial offload instead of `99`:

```dart
await controller.loadModel(
  modelPath: modelPath,
  contextSize: 2048,
  threads: 4,
  gpuLayers: 4,
);
```

For the Galaxy A51 reporting Vulkan 1.1.213, expect CPU fallback unless its
actual runtime driver satisfies this backend's Vulkan 1.2 requirements.
`recommendedGpuLayers = 16` alone does not establish backend compatibility.

Native logcat messages under `LlamaJNI` report compiled backend support,
runtime availability, registered GPU names, requested layers, and fallback/load
errors. Upstream `offloaded X/Y layers to GPU` messages report the actual
offload count; a requested positive count alone is not proof of GPU execution.

### Native build verification (no device required)

The Gradle plugin builds `android/CMakeLists.txt` from source and packages the
JNI library and its llama/ggml/Vulkan backend dependencies. It keeps the existing
ARM64 ABI and Android API 26 minimum. No prebuilt CPU-only libraries are bundled.

For a standalone package-level build, set `ANDROID_NDK` to your selected NDK
r27+ and put CMake 3.22.1+ and Ninja on `PATH`, then run from the package root:

```sh
cmake -S android -B build/android-vulkan -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26 \
  -DANDROID_STL=c++_shared -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_FLAGS=-fvisibility=hidden
cmake --build build/android-vulkan --target llama_jni --parallel 4
```

Shaders are generated on the build host and embedded in `libggml-vulkan.so`;
no shader compiler is needed on the device. If `glslc` is unavailable, install
shaderc/the Vulkan SDK or pass `-DVulkan_GLSLC_EXECUTABLE=/path/to/host/glslc`.
Optional shader features are enabled only when that compiler successfully
compiles their probes. Windows also needs a host compiler available to CMake
(for MSVC, use its developer command prompt).

For offline builds, prefetch the pinned source archives and pass
`-DFETCHCONTENT_SOURCE_DIR_LLAMA_VULKAN_HEADERS=/path/to/Vulkan-Headers` and
`-DFETCHCONTENT_SOURCE_DIR_LLAMA_SPIRV_HEADERS=/path/to/SPIRV-Headers`.

Use the NDK's `llvm-readelf` to inspect the result: `libggml.so` must depend on
`libggml-vulkan.so` and import `ggml_backend_vk_reg`; `libggml-vulkan.so` must
export that registration function and depend on Android's `libvulkan.so`.
The Android Vulkan CI workflow checks this dependency chain after compilation.

## Architecture

```
         Flutter App (Dart)
                ↓
    llama_flutter_android.dart
    (User-facing API)
                ↓
    Pigeon Generated Code
    (Type-safe bridge)
                ↓
    LlamaFlutterAndroidPlugin.kt
    (Kotlin coroutines)
                ↓
    InferenceService.kt
    (Foreground service)
                ↓
    jni_wrapper.cpp
    (JNI bridge)
                ↓
    llama.cpp
    (Native inference)
```

## API Reference

### LlamaController

The main interface for working with llama.cpp models.

**Methods:**
- `loadModel()` - Load a GGUF model file
- `generate()` - Generate text with streaming tokens
- `generateChat()` - Generate chat responses with template formatting
- `stop()` - Stop generation mid-process
- `dispose()` - Clean up resources

**Parameters:**
- Basic: `maxTokens`, `seed`
- Sampling: `temperature`, `topP`, `topK`, `minP`, `typicalP`
- Penalties: `repeatPenalty`, `frequencyPenalty`, `presencePenalty`, `repeatLastN`, `penalizeNl`
- Mirostat: `mirostat`, `mirostatTau`, `mirostatEta`
- Context: `getContextInfo()`, `clearContext()`, `setSystemPromptLength()`
- Templates: `getSupportedTemplates()`, `registerCustomTemplate()`, `unregisterCustomTemplate()`

**Supported Chat Templates:**
- `chatml` - ChatML format (default)
- `llama2` - Llama-2 format
- `alpaca` - Alpaca format
- `vicuna` - Vicuna format
- `phi` - Phi format
- `gemma` - Gemma format
- `zephyr` - Zephyr format

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Credits

- [llama.cpp](https://github.com/ggerganov/llama.cpp) - The amazing inference engine
- [Pigeon](https://pub.dev/packages/pigeon) - Type-safe platform communication

## Support

- [Issue Tracker](https://github.com/dragneel2074/Llama-Flutter/issues)
- 💬 [Discussions](https://github.com/dragneel2074/Llama-Flutter/discussions)
- 📦 [Example App](example/) - Complete working example
