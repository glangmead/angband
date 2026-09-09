#!/bin/bash
# iPad simulator loop for the SDL2 frontend.
#   ./gregsim.sh            configure (first time), build, install, launch
#   ./gregsim.sh shot out.png   screenshot the booted simulator
#   ./gregsim.sh rotate     rotate the simulator (portrait/landscape toggle)
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
  rotate)
    # Needs Accessibility permission for this terminal; otherwise rotate by hand (Cmd-Left in Simulator).
    osascript -e 'tell application "Simulator" to activate' \
      -e 'tell application "System Events" to tell process "Simulator" to click menu item "Rotate Left" of menu "Device" of menu bar 1' \
      || echo "Rotation needs Accessibility permission for this terminal; use Cmd-Left in Simulator."; exit ;;
esac

xcrun simctl bootstatus "$SIM" -b >/dev/null
if [ ! -d "$BUILD" ]; then
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
