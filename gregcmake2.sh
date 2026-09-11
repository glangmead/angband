# Build with Xcode 26, not 27: iOS 27 traps apps linked against the iOS 27
# SDK that have not adopted the UIScene lifecycle, and SDL2 has not.  Xcode
# 26's SDK is below that threshold, so the app runs on an iOS 27 device.
# Override by setting DEVELOPER_DIR before running this.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app}"

# After switching Xcode the cached SDK path no longer matches the one in use
# and the build dies in ProcessInfoPlistFile with "SDK lookup failed"; wipe
# the cache (not _deps, which holds the fetched SDL sources) and reconfigure.
if [ -f build/CMakeCache.txt ]; then
  SYSROOT=$(sed -n 's/^CMAKE_OSX_SYSROOT:INTERNAL=//p' build/CMakeCache.txt)
  case "$SYSROOT" in
    "$DEVELOPER_DIR"/*) ;;
    *) echo "cached SDK $SYSROOT is not $DEVELOPER_DIR's; reconfiguring"
       rm -rf build/CMakeCache.txt build/CMakeFiles ;;
  esac
fi
cmake -B build \
-D CMAKE_TOOLCHAIN_FILE=src/cmake/toolchain/ios.toolchain.cmake \
-G Xcode \
-D ENABLE_BITCODE=0 \
-D PLATFORM=OS64 \
-D CMAKE_SYSTEM_NAME=iOS \
-D CMAKE_BUILD_TYPE=RelWithDebInfo \
-D CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY='' \
-D SUPPORT_SDL2_FRONTEND=ON \
-D CMAKE_POLICY_VERSION_MINIMUM=3.5 && \
cmake --build build --config RelWithDebInfo -j 20
