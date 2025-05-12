#!/bin/bash

set -e

VERSION="3.100"
SRC_DIR="$(pwd)/lame-${VERSION}"
IOS_MIN_VERSION=12.0
BUILD_DIR="${SRC_DIR}/lame-ios-build"
XCFRAMEWORK_OUTPUT="${BUILD_DIR}/libmp3lame.xcframework"
declare -a ARCHS=("arm64-iphoneos" "arm64-iphonesimulator" "x86_64-iphonesimulator")

if [ ! -d "${SRC_DIR}" ]; then
  if [ ! -d "${SRC_DIR}.tar.gz" ]; then
    echo "🔍 Download lame ${VERSION}..."
    curl -L https://nchc.dl.sourceforge.net/project/lame/lame/${VERSION}/lame-${VERSION}.tar.gz -o ${SRC_DIR}.tar.gz
  fi
  tar xzf ${SRC_DIR}.tar.gz
fi

cd "$SRC_DIR"

# 清理旧文件
rm -rf "$BUILD_DIR" "$XCFRAMEWORK_OUTPUT"
mkdir -p "$BUILD_DIR"

for ARCH in "${ARCHS[@]}"; do
  echo "==== Building for $ARCH ===="
  case $ARCH in
    arm64-iphoneos)
      PLATFORM="iphoneos"
      HOST="arm-apple-darwin"
      ARCH_FLAG="-arch arm64 -target arm64-apple-ios${IOS_MIN_VERSION}"
      PREFIX="$BUILD_DIR/ios-arm64"
      ;;
    arm64-iphonesimulator)
      PLATFORM="iphonesimulator"
      HOST="aarch64-apple-darwin"
      ARCH_FLAG="-arch arm64 -target arm64-apple-ios${IOS_MIN_VERSION}-simulator"
      PREFIX="$BUILD_DIR/simulator-arm64"
      ;;
    x86_64-iphonesimulator)
      PLATFORM="iphonesimulator"
      HOST="x86_64-apple-darwin"
      ARCH_FLAG="-arch x86_64 -target x86_64-apple-ios${IOS_MIN_VERSION}-simulator"
      PREFIX="$BUILD_DIR/simulator-x86_64"
      ;;
  esac

  SDK_PATH=$(xcrun --sdk $PLATFORM --show-sdk-path)
  CC_BIN=$(xcrun --sdk $PLATFORM -f clang)
  CFLAGS="$ARCH_FLAG -isysroot $SDK_PATH -mios-version-min=$IOS_MIN_VERSION -DHAVE_MEMCPY=1 -DSTDC_HEADERS"
  LDFLAGS="$ARCH_FLAG -isysroot $SDK_PATH -mios-version-min=$IOS_MIN_VERSION"

  make distclean || true

  ./configure \
    --disable-shared \
    --enable-static \
    --disable-frontend \
    --host=$HOST \
    --prefix="$PREFIX" \
    CC="$CC_BIN" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS"

  make -j$(sysctl -n hw.ncpu)
  make install
done

# 合并 simulator 的两个架构
mkdir -p "$BUILD_DIR/simulator-universal/lib"
lipo -create \
  "$BUILD_DIR/simulator-arm64/lib/libmp3lame.a" \
  "$BUILD_DIR/simulator-x86_64/lib/libmp3lame.a" \
  -output "$BUILD_DIR/simulator-universal/lib/libmp3lame.a"

cp -r "$BUILD_DIR/simulator-arm64/include" "$BUILD_DIR/simulator-universal/include"

# 生成 XCFramework
xcodebuild -create-xcframework \
  -library "$BUILD_DIR/ios-arm64/lib/libmp3lame.a" -headers "$BUILD_DIR/ios-arm64/include" \
  -library "$BUILD_DIR/simulator-universal/lib/libmp3lame.a" -headers "$BUILD_DIR/simulator-universal/include" \
  -output "$XCFRAMEWORK_OUTPUT"

echo "✅ XCFramework created at: $XCFRAMEWORK_OUTPUT"

