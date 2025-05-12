//
//  SJAudioPlaybackController.h
//  LWZFFmpegLib
//
//  Created by db on 2025/4/16.
//

#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSErrorDomain const SJAudioPlaybackControllerErrorDomain;

@protocol SJAudioPlaybackController <NSObject>
@property (nonatomic) float rate;
@property (nonatomic) float volume;
@property (nonatomic, getter=isMute) BOOL mute;

- (BOOL)play:(NSError **)error;
- (BOOL)pause:(NSError **)error;
- (BOOL)stop:(NSError **)error; // stop all nodes
- (BOOL)reset:(NSError **)error; // rest all nodes, 重新创建engine, 一般在播放报错需要重置时调用;

@property (nonatomic, copy, nullable) void(^audioEngineConfigurationChangeHandler)(id<SJAudioPlaybackController> playbackController);

@property (nonatomic, copy, nullable) void(^renderBlock)(BOOL *isSilence, AVAudioFrameCount frameCount, AudioBufferList *outputData, int64_t *pts);
@end

@interface SJAudioPlaybackController : NSObject<SJAudioPlaybackController>
@property (nonatomic) float rate;
@property (nonatomic) float volume;
@property (nonatomic, getter=isMute) BOOL mute;

- (BOOL)play:(NSError **)error;
- (BOOL)pause:(NSError **)error;
- (BOOL)stop:(NSError **)error; // stop all nodes
- (BOOL)reset:(NSError **)error; // rest all nodes, 重新创建engine, 一般在播放报错需要重置时调用;

@property (nonatomic, copy, nullable) void(^renderBlock)(BOOL *isSilence, AVAudioFrameCount frameCount, AudioBufferList *outputData, int64_t *pts);

@property (nonatomic, copy, nullable) void(^audioEngineConfigurationChangeHandler)(id<SJAudioPlaybackController> playbackController);
@end
NS_ASSUME_NONNULL_END
