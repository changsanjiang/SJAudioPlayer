xcodebuild archive \
    -project ./libffmpeg.xcodeproj \
    -scheme libffmpeg \
    -destination "generic/platform=iOS" \
    -archivePath "archives/ios/libffmpeg" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES

xcodebuild archive \
    -project ./libffmpeg.xcodeproj \
    -scheme libffmpeg \
    -destination "generic/platform=iOS Simulator" \
    -archivePath "archives/simulator/libffmpeg" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES
    
rm -rf ../SJAudioPlayer/libffmpeg.xcframework

xcodebuild -create-xcframework \
    -archive ./archives/ios/libffmpeg.xcarchive -framework libffmpeg.framework \
    -archive ./archives/simulator/libffmpeg.xcarchive -framework libffmpeg.framework \
    -output ../SJAudioPlayer/libffmpeg.xcframework

rm -rf archives