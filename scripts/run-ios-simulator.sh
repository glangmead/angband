#!/bin/bash
#
# Build the iOS app for the simulator and run it there.  The simulator needs
# no code signing, so this is the quickest way to see a change.  Run it from
# the top of the source tree.
#
#   ./scripts/run-ios-simulator.sh              build, install and launch
#   ./scripts/run-ios-simulator.sh shot out.png screenshot the simulator
#   ./scripts/run-ios-simulator.sh rotate [left|right]
#   ./scripts/run-ios-simulator.sh idb          start idb's companion, so
#                                               that "idb ui tap" works
#
# SIM names the simulator; it defaults to a booted one, or failing that to
# any available iPad.  List them with "xcrun simctl list devices available".
#
#   SIM="iPad Pro 11-inch (M4)" ./scripts/run-ios-simulator.sh
#
# The same script works in Angband, NarSil and FAangband: the app's name
# comes from CMakeLists.txt.
#
set -eu

APP=$(sed -n 's/^[Pp][Rr][Oo][Jj][Ee][Cc][Tt](\([A-Za-z]*\).*/\1/p' CMakeLists.txt)
[ -n "$APP" ] || { echo "cannot read the project name from CMakeLists.txt" >&2; exit 1; }
BUNDLE="org.rephial.$APP"
BUILD="${BUILD:-build-sim}"
CFG="${CFG:-RelWithDebInfo}"

# Prefer a booted simulator, then any iPad; SIM overrides either.
if [ -z "${SIM:-}" ]; then
	SIM=$(xcrun simctl list devices available | sed -n 's/.*(\([0-9A-F-]\{36\}\)) (Booted)/\1/p' | head -1)
	[ -n "$SIM" ] || SIM=$(xcrun simctl list devices available |
		sed -n 's/^ *iPad[^(]*(\([0-9A-F-]\{36\}\)).*/\1/p' | head -1)
	[ -n "$SIM" ] || { echo "no iPad simulator found; set SIM" >&2; exit 1; }
fi

case "${1:-}" in
shot)
	xcrun simctl io "$SIM" screenshot "${2:-shot.png}"
	exit ;;
idb)
	# Xcode 27 dropped the private SimulatorKit.framework that idb's
	# companion needs; an older Xcode still has it and drives the
	# simulator fine.  Point OLD_XCODE at one of those.
	OLD_XCODE="${OLD_XCODE:-/Applications/Xcode.app}"
	idb kill >/dev/null 2>&1 || true
	DEVELOPER_DIR="$OLD_XCODE" nohup idb_companion --udid "$SIM" \
		> /tmp/idb_companion.log 2>&1 &
	disown
	sleep 3
	idb connect localhost 10882
	exit ;;
rotate)
	# From portrait, left gives landscape; from that landscape, right gives
	# portrait again (upside-down portrait is not allowed).  Needs
	# Accessibility permission for this terminal.
	DIR=Left; [ "${2:-}" = right ] && DIR=Right
	osascript -e 'tell application "Simulator" to activate' \
		-e "tell application \"System Events\" to tell process \"Simulator\" to click menu item \"Rotate $DIR\" of menu \"Device\" of menu bar 1" ||
		echo "Rotation needs Accessibility permission for this terminal; use Cmd-Left/Right in Simulator."
	exit ;;
esac

xcrun simctl bootstatus "$SIM" -b >/dev/null

# After an Xcode update the cached SDK no longer matches xcodebuild and the
# build fails with "SDK lookup failed"; wipe the cache so the configure below
# runs again.
if [ -f "$BUILD/CMakeCache.txt" ]; then
	SYSROOT=$(sed -n 's/^CMAKE_OSX_SYSROOT:INTERNAL=//p' "$BUILD/CMakeCache.txt")
	case "$SYSROOT" in
	"$(xcode-select -p)"/*) ;;
	*)
		echo "cached SDK $SYSROOT is not the selected Xcode's; reconfiguring"
		rm -rf "$BUILD/CMakeCache.txt" "$BUILD/CMakeFiles"
		;;
	esac
fi

if [ ! -f "$BUILD/CMakeCache.txt" ]; then
	# Reuse the SDL sources a device build already fetched, if there is one,
	# rather than cloning them a second time.
	REUSE=
	for d in "${DEPS:-build/_deps}"; do
		if [ -d "$d/sdl2-src" ]; then
			REUSE="-D FETCHCONTENT_SOURCE_DIR_SDL2=$PWD/$d/sdl2-src
				-D FETCHCONTENT_SOURCE_DIR_SDL2_TTF=$PWD/$d/sdl2_ttf-src
				-D FETCHCONTENT_SOURCE_DIR_SDL2_IMAGE=$PWD/$d/sdl2_image-src"
		fi
	done
	# shellcheck disable=SC2086
	cmake -B "$BUILD" -G Xcode \
		-D CMAKE_TOOLCHAIN_FILE=src/cmake/toolchain/ios.toolchain.cmake \
		-D ENABLE_BITCODE=0 \
		-D PLATFORM=SIMULATORARM64 \
		-D DEPLOYMENT_TARGET=18.0 \
		-D CMAKE_SYSTEM_NAME=iOS \
		-D CMAKE_BUILD_TYPE="$CFG" \
		-D CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY='' \
		-D SUPPORT_SDL2_FRONTEND=ON \
		-D CMAKE_POLICY_VERSION_MINIMUM=3.5 \
		$REUSE
fi

cmake --build "$BUILD" --config "$CFG" -j "$(sysctl -n hw.physicalcpu)" 2>&1 |
	grep -E "error:|warning: .*main-sdl2|BUILD SUCCEEDED|BUILD FAILED" || true

# Where CMake leaves the bundle depends on CMAKE_RUNTIME_OUTPUT_DIRECTORY, so
# look for it rather than assuming.
APP_PATH=$(find "$BUILD" -maxdepth 4 -type d -name "$APP.app" | head -1)
[ -n "$APP_PATH" ] || { echo "no $APP.app under $BUILD" >&2; exit 1; }

xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP_PATH"
xcrun simctl launch "$SIM" "$BUNDLE"
