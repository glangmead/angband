#!/bin/bash
#
# Build the iOS app and pack it into an .ipa, the same way the iOS workflow
# in .github/workflows/ios.yaml does.  Run it from the top of the source
# tree; the .ipa is left in build/.
#
# The app is not signed, so installing it on a device needs a tool that
# signs as it installs (Sideloadly, AltStore) or an Xcode project of your
# own.  The simulator needs no signing at all: see run-ios-simulator.sh.
#
#   ./scripts/build-ios.sh              build and pack
#   BUILD=out ./scripts/build-ios.sh    build in out/ instead of build/
#
set -eu

BUILD="${BUILD:-build}"
CFG="${CFG:-RelWithDebInfo}"

# Build with Xcode 26, not 27: iOS 27 traps apps linked against the iOS 27
# SDK that have not adopted the UIScene lifecycle, and SDL2 has not.  Xcode
# 26's SDK is below that threshold, so the app runs on an iOS 27 device.
# Override by setting DEVELOPER_DIR before running this.
if [ -z "${DEVELOPER_DIR:-}" ]; then
	for xc in $(ls -d /Applications/Xcode*.app 2>/dev/null | sort -rV); do
		sdk=$("$xc/Contents/Developer/usr/bin/xcodebuild" -showsdks 2>/dev/null |
			sed -n 's/.*-sdk iphoneos\([0-9][0-9]*\).*/\1/p' |
			sort -rn | head -1) || true
		if [ -n "${sdk:-}" ] && [ "$sdk" -lt 27 ]; then
			DEVELOPER_DIR=$xc
			break
		fi
	done
	: "${DEVELOPER_DIR:=$(dirname "$(dirname "$(xcode-select -p)")")}"
fi
export DEVELOPER_DIR
echo "using $DEVELOPER_DIR"

# After switching Xcode the cached SDK path no longer matches the one in use
# and the build dies in ProcessInfoPlistFile with "SDK lookup failed"; wipe
# the cache (not _deps, which holds the fetched SDL sources) and reconfigure.
if [ -f "$BUILD/CMakeCache.txt" ]; then
	SYSROOT=$(sed -n 's/^CMAKE_OSX_SYSROOT:INTERNAL=//p' "$BUILD/CMakeCache.txt")
	case "$SYSROOT" in
	"$DEVELOPER_DIR"/*) ;;
	*)
		echo "cached SDK $SYSROOT is not $DEVELOPER_DIR's; reconfiguring"
		rm -rf "$BUILD/CMakeCache.txt" "$BUILD/CMakeFiles"
		;;
	esac
fi

# The first configure fetches SDL2, SDL2_ttf and SDL2_image, which takes a
# while; later ones reuse what is under $BUILD/_deps.
cmake -B "$BUILD" -G Xcode \
	-D CMAKE_TOOLCHAIN_FILE=src/cmake/toolchain/ios.toolchain.cmake \
	-D ENABLE_BITCODE=0 \
	-D PLATFORM=OS64 \
	-D CMAKE_SYSTEM_NAME=iOS \
	-D CMAKE_BUILD_TYPE="$CFG" \
	-D CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY='' \
	-D SUPPORT_SDL2_FRONTEND=ON \
	-D CMAKE_POLICY_VERSION_MINIMUM=3.5

cmake --build "$BUILD" --config "$CFG" -j "$(sysctl -n hw.physicalcpu)"

# CPack wraps Payload/<App>.app into the .ipa the workflow uploads.
(cd "$BUILD" && cpack -G ZIP -C "$CFG")
ls -l "$BUILD"/*.ipa
