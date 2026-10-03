# The NDK supplies the Android loader, but not Vulkan-Hpp or SPIR-V headers.
# Pin header-only sources independently of the developer's desktop Vulkan SDK.
include(FetchContent)
FetchContent_Declare(llama_vulkan_headers
    URL https://codeload.github.com/KhronosGroup/Vulkan-Headers/tar.gz/refs/tags/vulkan-sdk-1.4.350.0
    URL_HASH SHA256=70270d10bf2c1e074a06ee37a50b75d332993d1b80a1d9526eeed2da6d82ed22
)
FetchContent_Declare(llama_spirv_headers
    URL https://codeload.github.com/KhronosGroup/SPIRV-Headers/tar.gz/refs/tags/vulkan-sdk-1.4.350.0
    URL_HASH SHA256=9905d9341f20388adb852c77dd982f2c4d539fd68e6c1f1bcebf034715f2d1d5
)
set(VULKAN_HEADERS_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(VULKAN_HEADERS_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(SPIRV_HEADERS_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(SPIRV_HEADERS_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(llama_vulkan_headers llama_spirv_headers)
set(Vulkan_INCLUDE_DIR "${llama_vulkan_headers_SOURCE_DIR}/include"
    CACHE PATH "Vulkan headers including Vulkan-Hpp" FORCE)

# Resolve the target loader through the NDK, never a desktop SDK library.
find_library(VULKAN_LIB vulkan REQUIRED)
set(Vulkan_LIBRARY "${VULKAN_LIB}"
    CACHE FILEPATH "Android Vulkan loader" FORCE)

# glslc runs on the build host. Prefer an explicit override, SDK or PATH;
# otherwise use the shader compiler bundled with the selected Android NDK.
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
    set(_llama_shader_host darwin-x86_64)
elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
    set(_llama_shader_host windows-x86_64)
else()
    set(_llama_shader_host linux-x86_64)
endif()
find_program(Vulkan_GLSLC_EXECUTABLE NAMES glslc
    HINTS "$ENV{VULKAN_SDK}/bin" "$ENV{VULKAN_SDK}/Bin"
    NO_CMAKE_FIND_ROOT_PATH)
find_program(Vulkan_GLSLC_EXECUTABLE NAMES glslc
    PATHS "${CMAKE_ANDROID_NDK}/shader-tools/${_llama_shader_host}"
    NO_DEFAULT_PATH NO_CMAKE_FIND_ROOT_PATH)
if(NOT Vulkan_GLSLC_EXECUTABLE)
    message(FATAL_ERROR "Vulkan inference needs host glslc. Install shaderc/Vulkan SDK or set Vulkan_GLSLC_EXECUTABLE.")
endif()
message(STATUS "Android Vulkan shader compiler: ${Vulkan_GLSLC_EXECUTABLE}")
