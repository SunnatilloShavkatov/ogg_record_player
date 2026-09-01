#!/bin/bash

# by default, we won't build for debugging purposes
if [ "${DEBUG}" == "true" ]; then
  echo "Compiling for debugging ..."
  OPT_CFLAGS="-O0 -fno-inline -g"
  OPT_LDFLAGS=""
  OPT_CONFIG_ARGS="--enable-assertions --disable-asm"
else
  OPT_CFLAGS="-Ofast -flto -g"
  OPT_LDFLAGS="-flto"
  OPT_CONFIG_ARGS=""
fi

DEVELOPER=$(xcode-select -print-path)
#DEVELOPER="/Applications/Xcode.app/Contents/Developer"

# Minimum deployment target. Must match `s.platform = :ios, 'x'` in the podspec
# and `platforms: [.iOS("x")]` in Package.swift.
MINIOSVERSION="${MINIOSVERSION:-15.0}"
MINMACOSVERSION="${MINMACOSVERSION:-10.15}"

# Resolved from the installed Xcode instead of hardcoded, so the scripts keep
# working across Xcode upgrades.
IPHONEOS_SDKVERSION=$(xcrun --sdk iphoneos --show-sdk-version)
MACOSX_SDKVERSION=$(xcrun --sdk macosx --show-sdk-version)

cd "$(dirname \"$0\")"
REPOROOT=$(pwd)

# Where we'll end up storing things in the end
OUTPUTDIR="${REPOROOT}/ogg_record_player"
mkdir -p ${OUTPUTDIR}/Frameworks

BUILDDIR="${REPOROOT}/build"

# where we will keep our sources and build from.
SRCDIR="${BUILDDIR}/src"
mkdir -p $SRCDIR
# where we will store intermediary builds
INTERDIR="${BUILDDIR}/built"
mkdir -p $INTERDIR

OPTION_CONFIG=""

function build_library() {
  ARCH=$1
  PLATFORM=$2

  if [ "${PLATFORM}" == "MacOSX" ]; then
    SDKNAME="macosx"
    SDKVERSION="${MACOSX_SDKVERSION}"
    EXTRA_CFLAGS="-arch ${ARCH} -target ${ARCH}-apple-macos${MINMACOSVERSION}"
    VERSION_FLAG="-mmacosx-version-min=${MINMACOSVERSION}"
  elif [ "${PLATFORM}" == "iPhoneSimulator" ]; then
    SDKNAME="iphonesimulator"
    SDKVERSION="${IPHONEOS_SDKVERSION}"
    EXTRA_CFLAGS="-arch ${ARCH} -target ${ARCH}-apple-ios${MINIOSVERSION}-simulator"
    VERSION_FLAG="-miphoneos-version-min=${MINIOSVERSION}"
  else
    SDKNAME="iphoneos"
    SDKVERSION="${IPHONEOS_SDKVERSION}"
    EXTRA_CFLAGS="-arch ${ARCH} -target ${ARCH}-apple-ios${MINIOSVERSION}"
    VERSION_FLAG="-miphoneos-version-min=${MINIOSVERSION}"
  fi
  SYSROOT=$(xcrun --sdk "${SDKNAME}" --show-sdk-path)

  if [ "${ARCH}" == "i386" ] || [ "${ARCH}" == "x86_64" ]; then
    EXTRA_CONFIG="--host=x86_64-apple-darwin"
  else
    # aarch64, not arm: with `arm-apple-darwin` libopus's configure assumes
    # ARMv7 and compiles the GNU-syntax .S files, which clang rejects.
    EXTRA_CONFIG="--host=aarch64-apple-darwin"
  fi

  local external_ldflags=""
  local external_cflags=""
  for link_framework in $3; do
    if [ "${PLATFORM}" == "iPhoneSimulator" ]; then
      external_ldflags="${external_ldflags} -L${link_framework}/ios-arm64_x86_64-simulator"
      external_cflags="${external_cflags} -I${link_framework}/ios-arm64_x86_64-simulator/Headers"
    elif [ "${PLATFORM}" == "MacOSX" ]; then
      if [ -d "${link_framework}/macos-arm64_x86_64" ]; then
        external_ldflags="${external_ldflags} -L${link_framework}/macos-arm64_x86_64"
        external_cflags="${external_cflags} -I${link_framework}/macos-arm64_x86_64/Headers"
      else
        external_ldflags="${external_ldflags} -L${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk/lib"
        external_cflags="${external_cflags} -I${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk/include"
      fi
    else
      external_ldflags="${external_ldflags} -L${link_framework}/ios-arm64"
      external_cflags="${external_cflags} -I${link_framework}/ios-arm64/Headers"
    fi
  done

  echo "Building ${PLATFORM} ${ARCH}..."

  mkdir -p "${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk"

  ./configure --enable-float-approx --disable-shared --enable-static --with-pic --disable-extra-programs --disable-doc ${EXTRA_CONFIG} \
    --prefix="${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk" \
    LDFLAGS="$LDFLAGS ${OPT_LDFLAGS} -fPIE ${VERSION_FLAG} ${external_ldflags}" \
    CFLAGS="$CFLAGS ${EXTRA_CFLAGS} ${OPT_CFLAGS} -fPIE ${VERSION_FLAG} -I${OUTPUTDIR}/include -isysroot ${SYSROOT} ${external_cflags}" \
    ${OPTION_CONFIG}

  # Build the application and install it to the fake SDK intermediary dir
  # we have set up. Make sure to clean up afterward because we will re-use
  # this source tree to cross-compile other targets.
  make -j4
  make install
  make clean
}

function build_arch_library() {
  build_library "arm64" "iPhoneOS" "$1"
  build_library "arm64" "iPhoneSimulator" "$1"
  build_library "x86_64" "iPhoneSimulator" "$1"
  build_library "arm64" "MacOSX" "$1"
  build_library "x86_64" "MacOSX" "$1"
}

function cp_to_xc_framework() {
  local lib_name="$1"
  local lib_platform="$2"
  local lib_arch="$3"
  local lib_path="$4"
  local lib_header_path="$5"

  lib_dir="${OUTPUTDIR}/Frameworks/lib${lib_name}.xcframework/"
  if [ "$lib_platform" == "iPhoneSimulator" ]; then
    lib_dir="${lib_dir}/ios-$lib_arch-simulator"
  elif [ "$lib_platform" == "iPhoneOS" ]; then
    lib_dir="${lib_dir}/ios-$lib_arch"
  elif [ "$lib_platform" == "MacOSX" ]; then
    lib_dir="${lib_dir}/macos-$lib_arch"
  fi

  mkdir -p "$lib_dir"
  cp "${lib_path}" "${lib_dir}/lib${lib_name}.a"
  cp -r "${lib_header_path}/" "${lib_dir}/Headers"
}

function collect_build_ios_library() {
  local lib_name="$1"
  OUTPUT_LIB="lib$lib_name.a"
  ARCH="arm64"
  PLATFORM="iPhoneOS"
  INPUT_ARCH_LIB="${INTERDIR}/${PLATFORM}${IPHONEOS_SDKVERSION}-${ARCH}.sdk"
  if [ -e "$INPUT_ARCH_LIB/lib/${OUTPUT_LIB}" ]; then
    INPUT_LIBS="${INPUT_LIBS} ${INPUT_ARCH_LIB}"
    cp_to_xc_framework "${lib_name}" "${PLATFORM}" "${ARCH}" "${INPUT_ARCH_LIB}/lib/${OUTPUT_LIB}" "${INPUT_ARCH_LIB}/include"
  fi
}

function collect_build_simulator_library() {
  local lib_name="$1"
  OUTPUT_LIB="lib$lib_name.a"
  PLATFORM="iPhoneSimulator"

  INPUT_LIBS=""
  for ARCH in "x86_64" "arm64"; do
    INPUT_ARCH_LIB="${INTERDIR}/${PLATFORM}${IPHONEOS_SDKVERSION}-${ARCH}.sdk/lib/${OUTPUT_LIB}"
    echo "INPUT_ARCH_LIB: ${INPUT_ARCH_LIB}"
    if [ -e $INPUT_ARCH_LIB ]; then
      INPUT_LIBS="${INPUT_LIBS} ${INPUT_ARCH_LIB}"
    fi
  done

  echo "collect_build_simulator_library $INPUT_LIBS"

  # Combine the architectures into a universal library.
  if [ -n "$INPUT_LIBS" ]; then
    local lib_dir="${OUTPUTDIR}/Frameworks/lib${lib_name}.xcframework/ios-arm64_x86_64-simulator"
    mkdir -p "${lib_dir}"
    lipo -create $INPUT_LIBS \
      -output "${lib_dir}/${OUTPUT_LIB}"
  else
    echo "$OUTPUT_LIB does not exist, skipping (are the dependencies installed?)"
  fi
}

function collect_build_macos_library() {
  local lib_name="$1"
  OUTPUT_LIB="lib$lib_name.a"
  PLATFORM="MacOSX"

  INPUT_LIBS=""
  for ARCH in "x86_64" "arm64"; do
    INPUT_ARCH_LIB="${INTERDIR}/${PLATFORM}${MACOSX_SDKVERSION}-${ARCH}.sdk/lib/${OUTPUT_LIB}"
    echo "INPUT_ARCH_LIB: ${INPUT_ARCH_LIB}"
    if [ -e $INPUT_ARCH_LIB ]; then
      INPUT_LIBS="${INPUT_LIBS} ${INPUT_ARCH_LIB}"
    fi
  done

  echo "collect_build_macos_library $INPUT_LIBS"

  # Combine the architectures into a universal library.
  if [ -n "$INPUT_LIBS" ]; then
    local lib_dir="${OUTPUTDIR}/Frameworks/lib${lib_name}.xcframework/macos-arm64_x86_64"
    mkdir -p "${lib_dir}"
    lipo -create $INPUT_LIBS \
      -output "${lib_dir}/${OUTPUT_LIB}"
  else
    echo "$OUTPUT_LIB does not exist for macOS, skipping"
  fi
}

function collect_build_library() {
  collect_build_ios_library $1
  collect_build_simulator_library $1
  collect_build_macos_library $1

  local lib_dir="${OUTPUTDIR}/Frameworks/lib$1.xcframework"
  # Remove first: `cp -r src dst` nests into dst/Headers when dst already exists.
  rm -rf "${lib_dir}/ios-arm64_x86_64-simulator/Headers"
  rm -rf "${lib_dir}/macos-arm64_x86_64/Headers"
  cp -r "${lib_dir}/ios-arm64/Headers" "${lib_dir}/ios-arm64_x86_64-simulator/Headers"
  cp -r "${lib_dir}/ios-arm64/Headers" "${lib_dir}/macos-arm64_x86_64/Headers"

  generate_xc_framework_info_plist $1
}

function generate_xc_framework_info_plist() {
  local lib_name="$1"
  local lib_dir="${OUTPUTDIR}/Frameworks/lib${lib_name}.xcframework"
  mkdir -p "${lib_dir}"

  cat >"${lib_dir}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>HeadersPath</key>
			<string>Headers</string>
			<key>LibraryIdentifier</key>
			<string>ios-arm64_x86_64-simulator</string>
			<key>LibraryPath</key>
			<string>lib${lib_name}.a</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
				<string>x86_64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
			<key>SupportedPlatformVariant</key>
			<string>simulator</string>
		</dict>
		<dict>
			<key>HeadersPath</key>
			<string>Headers</string>
			<key>LibraryIdentifier</key>
			<string>ios-arm64</string>
			<key>LibraryPath</key>
			<string>lib${lib_name}.a</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
		</dict>
		<dict>
			<key>HeadersPath</key>
			<string>Headers</string>
			<key>LibraryIdentifier</key>
			<string>macos-arm64_x86_64</string>
			<key>LibraryPath</key>
			<string>lib${lib_name}.a</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
				<string>x86_64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>macos</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key>
	<string>XFWK</string>
	<key>XCFrameworkFormatVersion</key>
	<string>1.0</string>
</dict>
</plist>
EOF
}
