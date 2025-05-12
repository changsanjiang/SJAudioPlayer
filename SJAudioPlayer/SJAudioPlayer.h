//
//  SJAudioPlayer.h
//  LWZFFmpegLib
//
//  Created by db on 2025/4/15.
//

#import "SJAudioPlaybackController.h"
@protocol SJAudioPlayerObserver, SJAudioPlaybackController;
@class SJAudioPlayerOptions;

typedef NS_ENUM(NSUInteger, SJPlayWhenReadyChangeReason) {
    SJPlayWhenReadyChangeReasonUserRequest,
    SJPlayWhenReadyChangeReasonAudioSessionInterrupted,
    SJPlayWhenReadyChangeReasonAudioSessionInterruptionEnded,
    SJPlayWhenReadyChangeReasonOldDeviceUnavailable,
    SJPlayWhenReadyChangeReasonReachedEndPosition,
    SJPlayWhenReadyChangeReasonReachedMaximumPlayableDurationPosition
};

NS_ASSUME_NONNULL_BEGIN
@interface SJAudioPlayer : NSObject
- (instancetype)initWithPlaybackController:(id<SJAudioPlaybackController>)playbackController;
- (instancetype)init;
+ (instancetype)player;

@property (nonatomic, strong, readonly, nullable) NSURL *URL;
@property (nonatomic, copy, readonly, nullable) __kindof SJAudioPlayerOptions *options;
@property (nonatomic, strong, readonly, nullable) NSError *error;
@property (nonatomic, readonly) BOOL playWhenReady;

@property (nonatomic, readonly) CMTime currentTime;
@property (nonatomic, readonly) CMTime duration;
@property (nonatomic, readonly) CMTimeRange playableTimeRange;
@property (nonatomic, readonly) CMTime playableDurationLimit;

@property (nonatomic) float rate;
@property (nonatomic) float volume;
@property (nonatomic, getter=isMute) BOOL mute;

/// Replaces the current audio with a new URL of audio.
///
- (void)replaceAudioWithURL:(nullable NSURL *)URL;
- (void)replaceAudioWithURL:(nullable NSURL *)URL options:(nullable __kindof SJAudioPlayerOptions *)options;
- (void)seekToTime:(CMTime)time;

- (void)play;
- (void)pause;

- (void)registerObserver:(id<SJAudioPlayerObserver>)observer;
- (void)removeObserver:(id<SJAudioPlayerObserver>)observer;
- (void)cancelPlayableDurationLimit;
@end

@interface SJAudioPlayer (FFAVAudioSessionExtended)
- (void)setCategory:(AVAudioSessionCategory)category withOptions:(AVAudioSessionCategoryOptions)options;
- (void)setActiveOptions:(AVAudioSessionSetActiveOptions)options;
@end

@interface SJAudioPlayerOptions : NSObject<NSCopying>
- (instancetype)initWithStartTimePosition:(CMTime)startTimePosition;
- (instancetype)initWithStartTimePosition:(CMTime)startTimePosition playableDurationLimit:(CMTime)playableDurationLimit;
@property (nonatomic) CMTime startTimePosition;
@property (nonatomic) CMTime playableDurationLimit; // 播放时长限制; 默认值 kCMTimeZero, 表示不限制;
@end

@protocol SJAudioPlayerObserver <NSObject>
@optional
- (void)audioPlayer:(SJAudioPlayer *)player playWhenReadyDidChange:(BOOL)isPlayWhenReady reason:(SJPlayWhenReadyChangeReason)reason;
- (void)audioPlayer:(SJAudioPlayer *)player durationDidChange:(CMTime)duration;
- (void)audioPlayer:(SJAudioPlayer *)player errorDidChange:(NSError *_Nullable)error;
@end
NS_ASSUME_NONNULL_END
