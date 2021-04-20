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
#import <AVFoundation/AVFoundation.h>
@protocol APAudioItemDelegate;

NS_ASSUME_NONNULL_BEGIN
@protocol APAudioPlaybackController <NSObject>
@property (nonatomic, strong, readonly) AVAudioEngine *engine;
@property (nonatomic, readonly) AVAudioFramePosition lastPosition;
@property (nonatomic, readonly) AVAudioFramePosition frameLengthInBuffers;
@property (nonatomic) float rate;
@property (nonatomic) float volume;
@property (nonatomic, getter=isMuted) BOOL muted;
/// @offset offset = startOffset(sought) + previousPCMBufferFrames
- (void)scheduleBuffer:(AVAudioPCMBuffer *)buffer atOffset:(AVAudioFramePosition)offset startOffset:(AVAudioFramePosition)startOffset completionHandler:(AVAudioNodeCompletionHandler __nullable)completionHandler;
- (BOOL)play:(NSError **)error;
- (void)pause;
- (void)stop; // stop all nodes
- (void)reset; // stop all nodes & reset last position
@end

@protocol APAudioItem <NSObject>
@property (nonatomic, readonly) APAudioItemStatus status;
@property (nonatomic, readonly, getter=isReachedEnd) BOOL reachedEnd;
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
@end

@protocol APAudioItemDelegate <NSObject>
- (void)audioItem:(id<APAudioItem>)item didLoadFormat:(AVAudioFormat *)format;
- (void)audioItem:(id<APAudioItem>)item newBufferAvailable:(AVAudioPCMBuffer *)buffer; // 转码为可播放的buffer的回调
- (void)audioItem:(id<APAudioItem>)item contentLoadProgressDidChange:(float)progress; // 文件内容加载进度的回调
- (void)audioItem:(id<APAudioItem>)item anErrorOccurred:(NSError *)error;
@end
NS_ASSUME_NONNULL_END

#endif /* APInterfaces_h */

