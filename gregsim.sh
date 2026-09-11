#!/bin/bash
# iPad simulator loop for the SDL2 frontend.
#   ./gregsim.sh            configure (first time), build, install, launch
#   ./gregsim.sh shot out.png   screenshot the booted simulator
#   ./gregsim.sh rotate [left|right]   rotate the simulator
#   ./gregsim.sh idb        start the idb companion so that "idb ui tap" works
# Works from any of the three repos; the app name comes from CMakeLists.txt.
set -e
APP=$(sed -n 's/^PROJECT(\([A-Za-z]*\).*/\1/p' CMakeLists.txt)
BUNDLE="org.rephial.$APP"
SIM="${SIM:-1EF4F5CD-E295-4DB7-9427-00B9B0A3913C}"   # iPad Pro 11-inch (M5), iOS 26.5
DEPS=/Users/glangmead/proj/angband/build/_deps           # SDL sources already fetched by the device build
BUILD=build-sim
CFG=RelWithDebInfo

case "$1" in
  shot)
    xcrun simctl io "$SIM" screenshot "${2:-shot.png}"; exit ;;
  idb)
    # Xcode 27 dropped the private SimulatorKit.framework that idb's companion
    # needs; the older Xcode still has it and drives this simulator fine.
    OLD_XCODE="${OLD_XCODE:-/Applications/Xcode.app}"
    idb kill >/dev/null 2>&1 || true
    DEVELOPER_DIR="$OLD_XCODE" nohup idb_companion --udid "$SIM" > /tmp/idb_companion.log 2>&1 &
    disown; sleep 3
    idb connect localhost 10882; exit ;;
  rotate)
    # ./gregsim.sh rotate [left|right]; default left. From portrait, left gives landscape;
    # from that landscape, right gives portrait again (upside-down portrait is not allowed).
    # Needs Accessibility permission for this terminal; otherwise rotate by hand (Cmd-Left/Right in Simulator).
    DIR=Left; [ "$2" = right ] && DIR=Right
    osascript -e 'tell application "Simulator" to activate' \
      -e "tell application \"System Events\" to tell process \"Simulator\" to click menu item \"Rotate $DIR\" of menu \"Device\" of menu bar 1" \
      || echo "Rotation needs Accessibility permission for this terminal; use Cmd-Left/Right in Simulator."; exit ;;
esac

xcrun simctl bootstatus "$SIM" -b >/dev/null
# After an Xcode update the cached SDK no longer matches xcodebuild and the build
# fails with "SDK lookup failed"; wipe the cache so the configure below runs again.
if [ -f "$BUILD/CMakeCache.txt" ]; then
  SYSROOT=$(sed -n 's/^CMAKE_OSX_SYSROOT:INTERNAL=//p' "$BUILD/CMakeCache.txt")
  case "$SYSROOT" in
    "$(xcode-select -p)"/*) ;;
    *) echo "cached SDK $SYSROOT is not the selected Xcode's; reconfiguring"
       rm -rf "$BUILD/CMakeCache.txt" "$BUILD/CMakeFiles" ;;
  esac
fi
if [ ! -f "$BUILD/CMakeCache.txt" ]; then
  cmake -B "$BUILD" -G Xcode \
    -D CMAKE_TOOLCHAIN_FILE=src/cmake/toolchain/ios.toolchain.cmake \
    -D ENABLE_BITCODE=0 \
    -D PLATFORM=SIMULATORARM64 \
    -D DEPLOYMENT_TARGET=18.0 \
    -D CMAKE_SYSTEM_NAME=iOS \
    -D CMAKE_BUILD_TYPE=$CFG \
    -D CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY='' \
    -D SUPPORT_SDL2_FRONTEND=ON \
    -D CMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -D FETCHCONTENT_SOURCE_DIR_SDL2=$DEPS/sdl2-src \
    -D FETCHCONTENT_SOURCE_DIR_SDL2_TTF=$DEPS/sdl2_ttf-src \
    -D FETCHCONTENT_SOURCE_DIR_SDL2_IMAGE=$DEPS/sdl2_image-src
fi
cmake --build "$BUILD" --config $CFG -j 20 2>&1 | grep -E "error:|warning: .*main-sdl2|BUILD SUCCEEDED|BUILD FAILED" || true
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$SIM" "$BUILD/$CFG-iphonesimulator/$APP.app"
xcrun simctl launch "$SIM" "$BUNDLE"
