//
//  SJAudioPlayer.h
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/14.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APDefines.h"
#import "APInterfaces.h"
@protocol SJAudioPlayerObserver;

NS_ASSUME_NONNULL_BEGIN
@interface SJAudioPlayer : NSObject
+ (instancetype)player;
- (instancetype)init;
- (instancetype)initWithPlaybackController:(id<APAudioPlaybackController>)playbackController;

@property (nonatomic, strong, readonly, nullable) NSURL *URL;
@property (nonatomic, strong, readonly, nullable) NSError *error;
@property (nonatomic, readonly) APAudioPlaybackStatus status;

@property (nonatomic, readonly) NSTimeInterval currentTime;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) float bufferProgress;

@property (nonatomic) float rate;
@property (nonatomic) float volume;
@property (nonatomic, getter=isMuted) BOOL muted;

- (void)replaceAudioWithURL:(NSURL *)URL;
- (void)seekToTime:(NSTimeInterval)time;

- (void)play;
- (void)pause;

- (void)registerObserver:(id<SJAudioPlayerObserver>)observer;
- (void)removeObserver:(id<SJAudioPlayerObserver>)observer;
- (void)reload;
@end

@protocol SJAudioPlayerObserver <NSObject>
@optional
- (void)audioPlayer:(SJAudioPlayer *)player statusDidChange:(APAudioPlaybackStatus)status;
- (void)audioPlayer:(SJAudioPlayer *)player bufferProgressDidChange:(float)progress;
@end

FOUNDATION_EXPORT NSNotificationName const SJAudioPlayerStatusDidChangeNotification;
FOUNDATION_EXPORT NSNotificationName const SJAudioPlayerBufferProgressDidChangeNotification;
NS_ASSUME_NONNULL_END
