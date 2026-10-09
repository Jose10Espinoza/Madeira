#!/bin/bash
set -e
 
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$BUILD_DIR/../.." && pwd)"
WINE_SRC="$REPO_ROOT/wine"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
APP_LIB="$REPO_ROOT/app/Madeira/libwineserver.a"
SHIMS_DIR="$REPO_ROOT/build/ntdll-unix/shims"
 
# Object files and library go in build dir (clean slate for iOS-only build)
OBJ_DIR="$BUILD_DIR/obj"
rm -rf "$OBJ_DIR"
mkdir -p "$OBJ_DIR"
 
CC_FLAGS=(
    -arch arm64 -isysroot "$SDK" -miphoneos-version-min=17.0 -O2
    -I"$WINE_SRC/include" -I"$WINE_SRC/include/wine"
    -I"$WINE_SRC/build-macos/include"
    -I"$BUILD_DIR" -I"$WINE_SRC/server"
    -I"$SHIMS_DIR"
    -I"$BUILD_DIR/../madsync" -DHAVE_LINUX_NTSYNC_H=1
    -include "$BUILD_DIR/config_ios.h"
    -include stdarg.h
    -include "$BUILD_DIR/unicode_fix.h"
    -include "$BUILD_DIR/wineserver_ios_kill.h"
    -DBINDIR=\"/usr/local/bin\" -DDATADIR=\"/usr/local/share\"
    -D__WINESRC__ -DWINE_IOS=1
    -Dmain=wineserver_main
    -Wno-implicit-function-declaration
)
 
compile_one() {
    local src=$1
    local name=$2
    echo -n "  $name... "
    if xcrun -sdk iphoneos clang "${CC_FLAGS[@]}" -c "$src" -o "$OBJ_DIR/$name.o" 2>"$OBJ_DIR/err-$name.txt"; then
        echo "OK"
    else
        echo "FAILED (see $OBJ_DIR/err-$name.txt)"
        cat "$OBJ_DIR/err-$name.txt"
        return 1
    fi
}
 
echo "=== Compiling all wine/server sources for iOS ==="
for src in "$WINE_SRC"/server/*.c; do
    name=$(basename "$src" .c)
    compile_one "$src" "$name" || exit 1
done
 
PATCHED_FILES=(
    "wine_log_ios:wine_log_ios.c:wine_log_ios.o"
    "request_ios:request_ios.c:request.o"
    "main_ios:main_ios.c:main.o"
    "mach_ios:mach_ios.c:mach.o"
    "unicode_ios:unicode_ios.c:unicode.o"
    "fd_ios:fd_ios.c:fd.o"
    "object:$WINE_SRC/server/object.c:object.o"
    "event:$WINE_SRC/server/event.c:event.o"
    "semaphore:$WINE_SRC/server/semaphore.c:semaphore.o"
    "handle:$WINE_SRC/server/handle.c:handle.o"
    "async:$WINE_SRC/server/async.c:async.o"
    "process_ios:$WINE_SRC/server/process.c:process.o"
    "window:$BUILD_DIR/window_ios.c:window.o"
    "user:$WINE_SRC/server/user.c:user.o"
    "mapping:$BUILD_DIR/mapping_ios.c:mapping.o"
    "class:$WINE_SRC/server/class.c:class.o"
    "region:$WINE_SRC/server/region.c:region.o"
    "queue:$BUILD_DIR/queue_ios.c:queue.o"
    "winstation:$WINE_SRC/server/winstation.c:winstation.o"
    "thread:$WINE_SRC/server/thread.c:thread.o"
    "inproc_sync:$WINE_SRC/server/inproc_sync.c:inproc_sync.o"
    "sock:$WINE_SRC/server/sock.c:sock.o"
    "hidpad_ios:hidpad_ios.c:hidpad_ios.o"
    "hidparse_ios:$REPO_ROOT/build/hidpad/hidparse_ios.c:hidparse_ios.o"
)
 
echo "=== Building kill wrapper (without kill macro) ==="
echo -n "  wineserver_ios_kill... "
KILL_FLAGS=(-arch arm64 -isysroot "$SDK" -miphoneos-version-min=17.0 -O2
    -I"$BUILD_DIR" -DWINE_IOS=1 -Wno-implicit-function-declaration)
if xcrun -sdk iphoneos clang "${KILL_FLAGS[@]}" -c "$BUILD_DIR/wineserver_ios_kill.c" -o "$OBJ_DIR/wineserver_ios_kill.o" 2>"$OBJ_DIR/err-kill.txt"; then
    echo "OK"
else
    echo "FAILED"; cat "$OBJ_DIR/err-kill.txt"; exit 1
fi
 
echo "=== Building all patched wineserver files ==="
for entry in "${PATCHED_FILES[@]}"; do
    IFS=: read -r name src old_obj <<< "$entry"
    if [[ "$src" == /* ]]; then
        compile_one "$src" "$name"
    else
        compile_one "$BUILD_DIR/$src" "$name"
    fi
done
 
echo ""
echo "=== Creating libwineserver.a from iOS objects ==="
rm -f "$OBJ_DIR/libwineserver.a"
ar rcs "$OBJ_DIR/libwineserver.a" "$OBJ_DIR"/*.o
 
echo ""
echo "=== Updating libwineserver.a ==="
REPLACEMENTS=(
    "wine_log_ios.o:wine_log_ios.o"
    "request_ios.o:request.o"
    "main_ios.o:main.o"
    "mach_ios.o:mach.o"
    "unicode_ios.o:unicode.o"
    "fd_ios.o:fd.o"
    "process_ios.o:process.o"
    "wineserver_ios_kill.o:wineserver_ios_kill.o"
    "window.o:window.o"
    "user.o:user.o"
    "class.o:class.o"
    "region.o:region.o"
    "queue.o:queue.o"
    "mapping.o:mapping.o"
    "winstation.o:winstation.o"
    "thread.o:thread.o"
    "sock.o:sock.o"
    "object.o:object.o"
    "async.o:async.o"
    "event.o:event.o"
    "semaphore.o:semaphore.o"
    "handle.o:handle.o"
    "inproc_sync.o:inproc_sync.o"
    "hidpad_ios.o:hidpad_ios.o"
    "hidparse_ios.o:hidparse_ios.o"
)
 
for entry in "${REPLACEMENTS[@]}"; do
    new_obj="${entry%%:*}"
    old_obj="${entry##*:}"
    if [ -f "$OBJ_DIR/$new_obj" ]; then
        ar d "$OBJ_DIR/libwineserver.a" "$old_obj" 2>/dev/null || true
        ar d "$OBJ_DIR/libwineserver.a" "$new_obj" 2>/dev/null || true
        ar r "$OBJ_DIR/libwineserver.a" "$OBJ_DIR/$new_obj"
    fi
done
 
echo ""
echo "=== Renaming colliding symbols in every .o (objcopy sweep) ==="
OBJCOPY=$(command -v llvm-objcopy || echo /opt/homebrew/opt/llvm/bin/llvm-objcopy)
[ -x "$OBJCOPY" ] || OBJCOPY=/opt/homebrew/Cellar/llvm/22.1.0/bin/llvm-objcopy
COLLISIONS=(
    alloc_user_handle free_user_handle get_virtual_screen_rect
    destroy_thread_windows get_window_thread is_desktop_class
    is_message_class is_window_visible mirror_region send_notify_message
    shared_session
    user_shared_data
)
RENAME_ARGS=()
for s in "${COLLISIONS[@]}"; do
    RENAME_ARGS+=(--redefine-sym "_${s}=_ws_${s}")
done
TMP_RENAME_DIR="$OBJ_DIR/rename"
rm -rf "$TMP_RENAME_DIR" && mkdir -p "$TMP_RENAME_DIR"
(cd "$TMP_RENAME_DIR" && ar x "$OBJ_DIR/libwineserver.a")
for f in "$TMP_RENAME_DIR"/*.o; do
    "$OBJCOPY" "${RENAME_ARGS[@]}" "$f"
done
rm "$OBJ_DIR/libwineserver.a"
ar rcs "$OBJ_DIR/libwineserver.a" "$TMP_RENAME_DIR"/*.o
rm -rf "$TMP_RENAME_DIR"
echo "  symbol rename + repack OK"
 
echo ""
echo "=== Verifying all objects are iOS-built ==="
TMP_CHK=$(mktemp -d)
(cd "$TMP_CHK" && ar x "$OBJ_DIR/libwineserver.a")
NOT_IOS=0
for o in "$TMP_CHK"/*.o; do
    if ! vtool -show-build "$o" 2>/dev/null | grep -q "platform IOS"; then
        echo "  NOT iOS: $(basename "$o")"
        NOT_IOS=1
    fi
done
rm -rf "$TMP_CHK"
if [ "$NOT_IOS" -ne 0 ]; then
    echo "ERROR: archive contains non-iOS objects"
    exit 1
fi
echo "  all objects verified iOS"
 
echo "Copying to app..."
cp "$OBJ_DIR/libwineserver.a" "$APP_LIB"
echo "Done! libwineserver.a: $(wc -c < "$APP_LIB" | tr -d ' ') bytes"
