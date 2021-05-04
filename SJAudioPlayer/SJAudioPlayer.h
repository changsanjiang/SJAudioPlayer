//
//  SJAudioPlayer.h
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/14.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APDefines.h"
#import "APInterfaces.h"
#import "APAudioOptions.h"
@protocol SJAudioPlayerObserver;

NS_ASSUME_NONNULL_BEGIN
@interface SJAudioPlayer : NSObject
+ (instancetype)player;
- (instancetype)init;
- (instancetype)initWithPlaybackController:(id<APAudioPlaybackController>)playbackController;

/// The current audio URL of the player.
///
///     You can call the `replaceAudioWithURL:` to replace the current URL with a new URL of audio.
///
@property (nonatomic, strong, readonly, nullable) NSURL *URL;
@property (nonatomic, strong, readonly, nullable) APAudioOptions *options;

/// If the player.status is APAudioPlaybackStatusFailed, this describes the error that caused the failure.
///
@property (nonatomic, strong, readonly, nullable) NSError *error;

/// The current status of the player.
///
@property (nonatomic, readonly) APAudioPlaybackStatus status;
@property (nonatomic, readonly) dispatch_queue_t queue;

@property (nonatomic, readonly) NSTimeInterval currentTime;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) float bufferProgress;

@property (nonatomic) float rate;
@property (nonatomic) float volume;
@property (nonatomic, getter=isMuted) BOOL muted;

/// Replaces the current audio with a new URL of audio.
///
- (void)replaceAudioWithURL:(nullable NSURL *)URL;
- (void)replaceAudioWithURL:(nullable NSURL *)URL options:(nullable APAudioOptions *)options;
- (void)seekToTime:(NSTimeInterval)time;

- (void)play;
- (void)pause;

- (void)registerObserver:(id<SJAudioPlayerObserver>)observer;
- (void)removeObserver:(id<SJAudioPlayerObserver>)observer;
- (void)reload;
- (void)cancelPlayableDurationLimit;
@property (nonatomic, readonly, getter=isReachedEndPosition) BOOL reachedEndPosition;
@property (nonatomic, readonly, getter=isReachedMaximumPlayableDurationPosition) BOOL reachedMaximumPlayableDurationPosition;
@end

@interface SJAudioPlayer (SJAVAudioSessionExtended)
- (void)setCategory:(AVAudioSessionCategory)category withOptions:(AVAudioSessionCategoryOptions)options;
- (void)setActiveOptions:(AVAudioSessionSetActiveOptions)options;
@end

@protocol SJAudioPlayerObserver <NSObject>
@optional
- (void)audioPlayer:(SJAudioPlayer *)player statusDidChange:(APAudioPlaybackStatus)status;
- (void)audioPlayer:(SJAudioPlayer *)player bufferProgressDidChange:(float)progress;
@end

FOUNDATION_EXPORT NSNotificationName const SJAudioPlayerStatusDidChangeNotification;
FOUNDATION_EXPORT NSNotificationName const SJAudioPlayerBufferProgressDidChangeNotification;
NS_ASSUME_NONNULL_END
