//
//  FFAudioItem.h
//  LWZFFmpegLib
//
//  Created by db on 2025/4/14.
//

#import <AVFoundation/AVAudioFormat.h>
#import <AVFAudio/AVAudioBuffer.h>
#import <CoreMedia/CMTime.h>
#import <CoreMedia/CMTimeRange.h>

@protocol FFAudioItemDelegate;
@class FFAudioItemOptions;

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSErrorDomain const FFAudioItemErrorDomain;

/// 固定输出格式: 44100 Hz, 32-bit float, fltp, stereo
@interface FFAudioItem : NSObject
- (instancetype)initWithURL:(NSURL *)URL options:(nullable FFAudioItemOptions *)options delegate:(id<FFAudioItemDelegate>)delegate;
@property (nonatomic, strong, readonly) AVAudioFormat *outputFormat;

@property (nonatomic, readonly, getter=isReadyToRead) BOOL readyToRead; // 可以通过`readBufferWithPts:`读取数据了;
@property (nonatomic, weak, readonly, nullable) id<FFAudioItemDelegate> delegate;

@property (nonatomic, readonly) CMTime duration;
@property (nonatomic, readonly) CMTimeRange playableTimeRange;
@property (nonatomic, strong, readonly, nullable) NSError *error;

- (void)seekToTime:(CMTime)time;

/// 返回值小于0表示报错
- (int)tryTranscodeWithFrameCapacity:(int)frameCapacity data:(void *_Nonnull*_Nonnull)outData pts:(int64_t *)outPts eof:(BOOL *)outEOF error:(NSError **)outError;
@end

@interface FFAudioItemOptions : NSObject
@property (nonatomic) CMTime startTimePosition; // 默认 kCMTimeZero;
@end

// 在子线程回调
@protocol FFAudioItemDelegate <NSObject>
- (void)audioItemDidReadyToRead:(FFAudioItem *)item; // 可以通过`readBufferWithPts:`读取数据了;
- (void)audioItem:(FFAudioItem *)item anErrorOccurred:(NSError *)error; // 发生了不可恢复的错误;
- (void)audioItem:(FFAudioItem *)item playableTimeRangeDidChange:(CMTimeRange)timeRange;
- (void)audioItemDidSeek:(FFAudioItem *)item; // seek 完成的回调
@end
NS_ASSUME_NONNULL_END
