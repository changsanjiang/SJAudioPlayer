#!/bin/bash

set -e

FFMPEG_VERSION="n6.0"
SRC_DIR="$(pwd)/FFmpeg-${FFMPEG_VERSION}"
BUILD_DIR="$SRC_DIR/ffmpeg-ios-build"
IOS_MIN_VERSION=12.0

if [ ! -d "$SRC_DIR" ]; then
  if [ ! -d "${SRC_DIR}.tar.gz" ]; then
    echo "🔍 Download lame ${VERSION}..."
    curl -L https://github.com/FFmpeg/FFmpeg/archive/refs/tags/${FFMPEG_VERSION}.tar.gz -o ${SRC_DIR}.tar.gz
  fi
  tar xzf ${SRC_DIR}.tar.gz
fi

cd "$SRC_DIR"

declare -a ARCHS=("arm64-iphoneos" "arm64-iphonesimulator" "x86_64-iphonesimulator")
OUT_DIR_IOS_ARM64="$BUILD_DIR/ios-arm64"
OUT_DIR_SIMULATOR_ARM64="$BUILD_DIR/simulator-arm64"
OUT_DIR_SIMULATOR_X86_64="$BUILD_DIR/simulator-x86_64"
OUT_DIR_SIMULATOR_UNIVERSAL="$BUILD_DIR/simulator-universal"

# 清理旧构建
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

ARCH_FLAGS=

for TARGET in "${ARCHS[@]}"; do
  echo "==== 🔨 Building FFmpeg for $TARGET ===="

  case $TARGET in
    arm64-iphoneos)
      PLATFORM="iphoneos"
      ARCH="arm64"
      HOST="aarch64-apple-darwin"
      SDK=$(xcrun --sdk iphoneos --show-sdk-path)
      CC=$(xcrun --sdk iphoneos -f clang)
      ARCH_FLAGS="-arch arm64 -target arm64-apple-ios${IOS_MIN_VERSION}"
      OUT_DIR=$OUT_DIR_IOS_ARM64
      ;;
    arm64-iphonesimulator)
      PLATFORM="iphonesimulator"
      ARCH="arm64"
      HOST="aarch64-apple-darwin"
      SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
      CC=$(xcrun --sdk iphonesimulator -f clang)
      ARCH_FLAGS="-arch arm64 -target arm64-apple-ios${IOS_MIN_VERSION}-simulator"
      OUT_DIR=$OUT_DIR_SIMULATOR_ARM64
      ;;
    x86_64-iphonesimulator)
      PLATFORM="iphonesimulator"
      ARCH="x86_64"
      HOST="x86_64-apple-darwin"
      SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
      CC=$(xcrun --sdk iphonesimulator -f clang)
      ARCH_FLAGS="-arch x86_64 -target x86_64-apple-ios${IOS_MIN_VERSION}-simulator"
      OUT_DIR=$OUT_DIR_SIMULATOR_X86_64
      ;;
    *)
      echo "❌ Unsupported target: $TARGET"
      exit 1
      ;;
  esac

  # 清理上一次 configure 的缓存
  make distclean || true

  ./configure \
    --prefix="$OUT_DIR" \
    --arch="$ARCH" \
    --target-os=darwin \
    --cc="$CC" \
    --ld="$CC" \
    --sysroot="$SDK" \
    --enable-cross-compile \
    --enable-static \
    --disable-shared \
    --disable-programs \
    --disable-everything \
    --disable-autodetect \
    --disable-doc \
    --disable-htmlpages \
    --disable-debug \
    --disable-x86asm \
    --disable-avdevice \
    --disable-postproc \
    --disable-vulkan \
    --enable-neon \
    --enable-asm \
    --enable-network \
    --enable-filter=aformat,aresample \
    --enable-protocol=file,http \
    --enable-decoder=mp3,aac,alac,flac,opus,vorbis,pcm* \
    --enable-demuxer=mp3,aac,wav,flac,ogg,opus,mov \
    --enable-parser=mp3,mpegaudio,flac,opus,vorbis \
    --extra-cflags="${ARCH_FLAGS} -mios-version-min=${IOS_MIN_VERSION}" \
    --extra-ldflags="${ARCH_FLAGS} -mios-version-min=${IOS_MIN_VERSION}"

  make -j$(sysctl -n hw.ncpu)
  make install
  make clean
done

echo "✅ FFmpeg built for arm64, arm64-simulator, and x86_64-simulator in: $BUILD_DIR"

declare -a OUT_LIB_NAMES=("libavcodec" "libavfilter" "libavformat" "libavutil" "libswresample" "libswscale")

# 合并 simulator 的两个架构
mkdir -p "${OUT_DIR_SIMULATOR_UNIVERSAL}/lib"
for TARGET in "${OUT_LIB_NAMES[@]}"; do
  LIB_ARM64="$OUT_DIR_SIMULATOR_ARM64/lib/${TARGET}.a"
  LIB_X86_64="$OUT_DIR_SIMULATOR_X86_64/lib/${TARGET}.a"
  LIB_UNIVERSAL="$OUT_DIR_SIMULATOR_UNIVERSAL/lib/${TARGET}.a"

  lipo -create "$LIB_ARM64" "$LIB_X86_64" -output "$LIB_UNIVERSAL"
  cp -r "$OUT_DIR_SIMULATOR_ARM64/include" "$OUT_DIR_SIMULATOR_UNIVERSAL/include"
done


# 创建framework
declare -a OUT_PATHS=("$OUT_DIR_IOS_ARM64" "$OUT_DIR_SIMULATOR_UNIVERSAL")
for TARGET in "${OUT_LIB_NAMES[@]}"; do
  for OUT in "${OUT_PATHS[@]}"; do
    mkdir -p "$OUT/frameworks/${TARGET}.framework/Headers"
    cp "$OUT/lib/${TARGET}.a" "$OUT/frameworks/${TARGET}.framework/${TARGET}"
    cp -r "$OUT/include/${TARGET}/" "$OUT/frameworks/${TARGET}.framework/Headers"
  done
done


# 生成 XCFramework
for TARGET in "${OUT_LIB_NAMES[@]}"; do
  XCFRAMEWORK_OUTPUT="$BUILD_DIR/frameworks/${TARGET}.xcframework"

  xcodebuild -create-xcframework \
    -framework "$BUILD_DIR/ios-arm64/frameworks/${TARGET}.framework" \
    -framework "$BUILD_DIR/simulator-universal/frameworks/${TARGET}.framework" \
    -output $XCFRAMEWORK_OUTPUT

  echo "✅ XCFramework created at: $XCFRAMEWORK_OUTPUT"
done
