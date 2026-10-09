#!/bin/bash
# Configure (first time) and build the ARM64EC FEX module (libarm64ecfex.dll,
# shipped as xtajit64.dll). Options mirror the development build's CMakeCache.
set -eu
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$R/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin:$PATH"
B="$R/FEX/build-arm64ec"
if [ ! -f "$B/CMakeCache.txt" ]; then
    # Patch FEX ARM64EC CMakeLists: force iOS-host link options.
    # Upstream has if(FEX_IOS_HOST_BUILD)/else()/endif() selecting between
    # iOS and non-iOS link flags; we always want the iOS branch (-static
    # plus explicit c++/c++abi/unwind) for the Madeira CI build.
    PATCH_P="$R/FEX/Source/Windows/ARM64EC/CMakeLists.txt"
    python3 - "$PATCH_P" << 'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p).read()
old = 'if (FEX_IOS_HOST_BUILD)'
if old in s:
    pattern = r'if \(FEX_IOS_HOST_BUILD\)\s+target_link_options\(arm64ecfex PRIVATE -static\)\s+else\(\)\s+target_link_options\(arm64ecfex PRIVATE -static -nostdlib[^)]+\)\s+target_link_libraries\(arm64ecfex PRIVATE \$\{LIBGCC_PATH\}\)\s+endif\(\)'
    replacement = 'target_link_options(arm64ecfex PRIVATE -static)\ntarget_link_libraries(arm64ecfex PRIVATE c++ c++abi unwind)'
    s2 = re.sub(pattern, replacement, s)
    if s2 != s:
        open(p, 'w').write(s2)
        print('patched ARM64EC CMakeLists')
    else:
        print('NOTE: pattern not matched (already patched?)')
else:
    print('NOTE: FEX_IOS_HOST_BUILD not found')
PYEOF
    cmake -S "$R/FEX" -B "$B" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="$R/FEX/Data/CMake/toolchain_mingw.cmake" \
        -DMINGW_TRIPLE=arm64ec-w64-mingw32 \
        -DTUNE_CPU=none \
        -DFEX_IOS_HOST_BUILD=ON \
        -DCMAKE_C_FLAGS="-DFEX_IOS_HOST" \
        -DCMAKE_CXX_FLAGS="-DFEX_IOS_HOST" \
        -DCMAKE_ASM_FLAGS="-DFEX_IOS_HOST" \
        -DENABLE_FEX_ALLOCATOR=ON -DENABLE_JEMALLOC_GLIBC_ALLOC=ON -DENABLE_OFFLINE_RUNTIME=ON \
        -DBUILD_FEXCONFIG=ON -DENABLE_CLANG_THUNKS=ON -DENABLE_CCACHE=ON \
        -DBUILD_TESTING=OFF -DBUILD_THUNKS=OFF -DENABLE_ASSERTIONS=OFF \
        `# ThinLTO breaks EC symbol resolution for static libc++ in lld` \
        `# (undefined __gxx_personality_seh0 etc.); keep off until lld fixes it` \
        -DENABLE_LTO=OFF
fi
cmake --build "$B" --target arm64ecfex
cp "$B/Bin/libarm64ecfex.dll" "$R/app/Madeira/arm64ec-windows/xtajit64.dll" && ls -l "$R/app/Madeira/arm64ec-windows/xtajit64.dll"
