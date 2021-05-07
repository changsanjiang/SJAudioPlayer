//
//  APInterfaces.h
//  SJAudioPlayer
//
//  Created by BlueDancer on 2021/4/12.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#ifndef APInterfaces_h
#define APInterfaces_h

#import "APDefines.h"
@protocol APAudioItemDelegate;

NS_ASSUME_NONNULL_BEGIN
@protocol APAudioPlaybackController <NSObject>
@property (nonatomic, strong, readonly) AVAudioEngine *engine;
@property (nonatomic, readonly) AVAudioFramePosition lastPosition;
@property (nonatomic, readonly) AVAudioFramePosition frameLengthInBuffers;
@property (nonatomic) float rate;
@property (nonatomic) float volume;
@property (nonatomic, getter=isMuted) BOOL muted;
- (void)scheduleBuffer:(AVAudioPCMBuffer *)buffer atPosition:(APAudioPCMBufferPosition)position completionHandler:(AVAudioNodeCompletionHandler __nullable)completionHandler;
- (BOOL)play:(NSError **)error;
- (void)pause;
- (void)stop; // stop all nodes
- (void)reset; // stop all nodes & reset last position
@end

@protocol APAudioItem <NSObject>
@property (nonatomic, readonly) APAudioItemStatus status;
@property (nonatomic, readonly, getter=isReachedEndPosition) BOOL reachedEndPosition;
@property (nonatomic, readonly, getter=isReachedMaximumPlayableDurationPosition) BOOL reachedMaximumPlayableDurationPosition;
@property (nonatomic, weak, readonly, nullable) id<APAudioItemDelegate> delegate;
@property (nonatomic, strong, readonly, nullable) AVAudioFormat *contentFormat;
@property (nonatomic, strong, readonly, nullable) AVAudioFormat *outputFormat;
@property (nonatomic, strong, readonly, nullable) NSError *error;
@property (nonatomic, readonly) float contentLoadProgress;
@property (nonatomic, readonly) NSTimeInterval duration;
- (void)prepare;
@property (nonatomic, readonly) AVAudioFramePosition startPosition; // seekToTime 所处的位置
- (void)seekToTime:(NSTimeInterval)time;
- (void)suspend;
- (void)resume;
- (void)retry;
- (void)cancelPlayableDurationLimit;
@end

@protocol APAudioItemDelegate <NSObject>
- (void)audioItem:(id<APAudioItem>)item didLoadFormat:(AVAudioFormat *)format;
- (void)audioItem:(id<APAudioItem>)item newBufferAvailable:(AVAudioPCMBuffer *)buffer; // 转码为可播放的buffer的回调
- (void)audioItem:(id<APAudioItem>)item contentLoadProgressDidChange:(float)progress; // 文件内容加载进度的回调
- (void)audioItem:(id<APAudioItem>)item anErrorOccurred:(NSError *)error;
@end

@protocol APAudioOptions <NSObject>
/// 播放时长限制. 最大可播放到的时长, 播放到该位置后将停止播放
///
///     默认值为 0, 即不做限制
///
@property (nonatomic) NSTimeInterval maximumPlayableDuration;

/// 每个 PCMBuffer packets 的字节数限制
///
///     default value is 8192;
///
@property (nonatomic) UInt64 maximumCountOfBytesPerPCMBufferPackets;

/// 当PCMBuffer的数量大于等于指定的数量后开始播放
///
///     default value is 1;
///
@property (nonatomic) NSInteger minimumCountOfPCMBufferToBePlayable;

/// PCMBuffer 缓存的最大数量
///
///     default value is 25;
///
@property (nonatomic) NSInteger maximumCountOfPCMBufferForPlayback;

/// 数据读取回调
///
@property (nonatomic, copy, nullable) NSData *(^dataReadDecoder)(NSData *data, NSUInteger offset);

/// 附加请求头
///
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *HTTPAdditionalHeaders;
@end
NS_ASSUME_NONNULL_END

#endif /* APInterfaces_h */

