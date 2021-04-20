//
//  SJAudioPlayer.m
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/14.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "SJAudioPlayer.h"
#import "APAudioPlaybackController.h"
#import "APAudioItem.h"
#import "APError.h"
#import "APUtils.h"
#import "APLogger.h"

static NSInteger const SJAudioPlayerMaximumPCMBufferCount = 25;
static NSInteger const SJAudioPlayerMinimumPCMBufferCountToBePlayable = 1;

@interface SJAudioPlayer ()<APAudioItemDelegate> {
    id<APAudioPlaybackController> _playbackController;
    NSHashTable<id<SJAudioPlayerObserver>> *_Nullable _observers;
}

@property (nonatomic, strong, nullable) APAudioItem *currentItem;
@property (nonatomic) NSInteger PCMBufferCount;
@end

static dispatch_queue_t ap_queue;

@implementation SJAudioPlayer

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ap_queue = dispatch_queue_create("queue.SJAudioPlayer", DISPATCH_QUEUE_SERIAL);
    });
}

+ (instancetype)player {
    return SJAudioPlayer.alloc.init;
}

- (instancetype)init {
    return [self initWithPlaybackController:APAudioPlaybackController.alloc.init];
}

- (instancetype)initWithPlaybackController:(id<APAudioPlaybackController>)playbackController {
    NSParameterAssert(playbackController != nil);
    self = [super init];
    if ( self ) {
        _playbackController = playbackController;
        _status = APAudioPlaybackStatusPaused;
        [self _observeNotifies];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_playbackController stop];
}

- (NSTimeInterval)currentTime {
    __block NSTimeInterval currentTime = 0;
    dispatch_sync(ap_queue, ^{
        currentTime = [self _currentTime];
    });
    return currentTime;
}

- (NSTimeInterval)duration {
    __block NSTimeInterval duration = 0;
    dispatch_sync(ap_queue, ^{
        duration = _currentItem.duration;
    });
    return duration;
}

- (float)bufferProgress {
    __block float progress = 0;
    dispatch_sync(ap_queue, ^{
        progress = _currentItem.contentLoadProgress;
    });
    return progress;
}
  
- (void)setRate:(float)rate {
    dispatch_sync(ap_queue, ^{
        _playbackController.rate = rate;
    });
}

- (float)rate {
    __block float rate = 0;
    dispatch_sync(ap_queue, ^{
        rate = _playbackController.rate;
    });
    return rate;
}

- (void)setVolume:(float)volume {
    dispatch_sync(ap_queue, ^{
        _playbackController.volume = volume;
    });
}

- (float)volume {
    __block float volume = 0;
    dispatch_sync(ap_queue, ^{
        volume = _playbackController.volume;
    });
    return volume;
}

- (void)setMuted:(BOOL)muted {
    dispatch_sync(ap_queue, ^{
        _playbackController.muted = muted;
    });
}

- (BOOL)isMuted {
    __block BOOL isMuted = 0;
    dispatch_sync(ap_queue, ^{
        isMuted = _playbackController.isMuted;
    });
    return isMuted;
}

- (void)replaceAudioWithURL:(NSURL *)URL {
    dispatch_sync(ap_queue, ^{
        APAudioPlayerDebugLog(@"%@: <%p>.%s { URL: %@ }\n", NSStringFromClass(self.class), self, sel_getName(_cmd), URL);

        [self _resetPlayback];
        _URL = URL;
        _currentItem = [APAudioItem.alloc initWithURL:_URL delegate:self queue:ap_queue];
        [_currentItem prepare];
        if ( _status & APAudioPlaybackStatusPlaying ) {
            [self _setStatus:APAudioPlaybackStatusEvaluating];
        }
        [self _toEvaluating];
    });
}

- (void)seekToTime:(NSTimeInterval)time {
    dispatch_sync(ap_queue, ^{
        APAudioPlayerDebugLog(@"%@: <%p>.%s { time: %lf }\n", NSStringFromClass(self.class), self, sel_getName(_cmd), time);
        
        if ( _currentItem.status == APAudioItemStatusUnknown )
            return;
        _error = nil;
        [self _stopPlayback];
        if ( _currentItem.status == APAudioItemStatusFailed )
            [_currentItem retry];
        else
            [_currentItem seekToTime:time];
        // play
        [self _setStatus:APAudioPlaybackStatusEvaluating];
        [self _toEvaluating];
    });
}

- (void)reload {
    dispatch_sync(ap_queue, ^{
        APAudioPlayerDebugLog(@"%@: <%p>.%s\n", NSStringFromClass(self.class), self, sel_getName(_cmd));

        if ( _currentItem.status == APAudioItemStatusUnknown )
            return;
        _error = nil;
        [self _stopPlayback];
        if ( _currentItem.status == APAudioItemStatusFailed )
            [_currentItem retry];
        else
            [_currentItem seekToTime:[self _currentTime]];
        if ( _status & APAudioPlaybackStatusPlaying ) {
            [self _setStatus:APAudioPlaybackStatusEvaluating];
        }
        [self _toEvaluating];
    });
}

- (void)play {
    dispatch_sync(ap_queue, ^{
        APAudioPlayerDebugLog(@"%@: <%p>.%s\n", NSStringFromClass(self.class), self, sel_getName(_cmd));

        if ( _status & APAudioPlaybackStatusPlaying )
            return;
        [self _setStatus:APAudioPlaybackStatusEvaluating];
        [self _toEvaluating];
    });
}

- (void)pause {
    dispatch_sync(ap_queue, ^{
        APAudioPlayerDebugLog(@"%@: <%p>.%s\n", NSStringFromClass(self.class), self, sel_getName(_cmd));
        
        if ( _status & APAudioPlaybackStatusPaused )
            return;
        
        [self _setStatus:APAudioPlaybackStatusPaused];
        [self _toEvaluating];
    });
}

- (void)registerObserver:(id<SJAudioPlayerObserver>)observer {
    if ( observer == nil )
        return;
    dispatch_sync(ap_queue, ^{
        if ( _observers == nil ) {
            _observers = NSHashTable.weakObjectsHashTable;
        }
        [_observers addObject:observer];
    });
}

- (void)removeObserver:(id<SJAudioPlayerObserver>)observer {
    if ( observer == nil )
        return;
    dispatch_sync(ap_queue, ^{
        [_observers removeObject:observer];
    });
}

#pragma mark - APAudioItemDelegate

- (void)audioItem:(id<APAudioItem>)item didLoadFormat:(AVAudioFormat *)format {
    APAudioPlayerDebugLog(@"%@: <%p>.%s { format: %@ }\n", NSStringFromClass(self.class), self, sel_getName(_cmd), format);
    
    [self _toEvaluating];
}

- (void)audioItem:(id<APAudioItem>)item newBufferAvailable:(AVAudioPCMBuffer *)buffer {
    [self _newBufferAvailable:buffer];
}

- (void)audioItem:(id<APAudioItem>)item contentLoadProgressDidChange:(float)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
        for ( id<SJAudioPlayerObserver> observer in self->_observers ) {
            if ( [observer respondsToSelector:@selector(audioPlayer:bufferProgressDidChange:)] )
                [observer audioPlayer:self bufferProgressDidChange:self.bufferProgress];
        }
        [NSNotificationCenter.defaultCenter postNotificationName:SJAudioPlayerBufferProgressDidChangeNotification object:self];
    });
}

- (void)audioItem:(id<APAudioItem>)item anErrorOccurred:(NSError *)error {
    [self _onError:error];
}

#pragma mark - mark

- (void)_setStatus:(APAudioPlaybackStatus)status {
    if ( status != _status ) {
        _status = status;
        dispatch_async(dispatch_get_main_queue(), ^{
            for ( id<SJAudioPlayerObserver> observer in self->_observers ) {
                if ( [observer respondsToSelector:@selector(audioPlayer:statusDidChange:)] )
                    [observer audioPlayer:self statusDidChange:self.status];
            }
            [NSNotificationCenter.defaultCenter postNotificationName:SJAudioPlayerStatusDidChangeNotification object:self];
        });
    }
}

#pragma mark - mark

- (NSTimeInterval)_currentTime {
    if ( _currentItem.outputFormat == nil )
        return 0;
    Float64 sampleRate = _currentItem.outputFormat.streamDescription->mSampleRate;
    AVAudioFramePosition lastPosition = _playbackController.lastPosition;
    AVAudioFramePosition currentPosition = _currentItem.startPosition + lastPosition;
    return currentPosition / sampleRate;
}

- (BOOL)_playPlayback {
    APAudioPlayerDebugLog(@"%@: <%p>.%s\n", NSStringFromClass(self.class), self, sel_getName(_cmd));
    
    NSError *error = nil;
    // https://stackoverflow.com/questions/29036294/avaudiorecorder-not-recording-in-background-after-audio-session-interruption-end
    if ( ![AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDuckOthers error:&error] ) {
        [self _onError:error];
        return NO;
    }
    if ( ![AVAudioSession.sharedInstance setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error] ) {
        [self _onError:error];
        return NO;
    }
    if ( ![_playbackController play:&error] ) {
        [self _onError:error];
        return NO;
    }
    
    return YES;
}

- (void)_pausePlayback {
    APAudioPlayerDebugLog(@"%@: <%p>.%s\n", NSStringFromClass(self.class), self, sel_getName(_cmd));

    [_playbackController pause];
}

- (void)_stopPlayback {
    APAudioPlayerDebugLog(@"%@: <%p>.%s\n", NSStringFromClass(self.class), self, sel_getName(_cmd));

    [_playbackController stop];
}

- (void)_resetPlayback {
    APAudioPlayerDebugLog(@"%@: <%p>.%s\n", NSStringFromClass(self.class), self, sel_getName(_cmd));

    [_playbackController reset];
    _currentItem = nil;
    _PCMBufferCount = 0;
    _error = nil;
}

#pragma mark -

- (void)_newBufferAvailable:(AVAudioPCMBuffer *)buffer {
    _PCMBufferCount += 1;
    AVAudioFramePosition offset = _currentItem.startPosition + _playbackController.frameLengthInBuffers;
    APAudioPlayerDebugLog(@"%@: <%p>.%s { newBuffer: %@, offset: %lld, curCount: %ld }\n", NSStringFromClass(self.class), self, sel_getName(_cmd), buffer, offset, (long)_PCMBufferCount);
    
    if ( _PCMBufferCount >= SJAudioPlayerMaximumPCMBufferCount ) {
        [_currentItem suspend];
    }
    __weak APAudioItem *item = _currentItem;
    __weak typeof(self) _self = self;
    [_playbackController scheduleBuffer:buffer atOffset:offset completionHandler:^{
        dispatch_async(ap_queue, ^{
            __strong typeof(_self) self = _self;
            if ( self == nil ) return;
            if ( item == self.currentItem ) {
                [self _PCMBufferPlaybackDidComplete:buffer];
            }
        });
    }];
    [self _toEvaluating];
    [self _pullNextBufferIfNeeded];
}

- (void)_PCMBufferPlaybackDidComplete:(AVAudioPCMBuffer *)buffer {
    _PCMBufferCount -= 1;

    APAudioPlayerDebugLog(@"%@: <%p>.%s { curCount: %ld }\n", NSStringFromClass(self.class), self, sel_getName(_cmd), _PCMBufferCount);
    
    NSAssert(_PCMBufferCount >= 0, @"PCMBuffer数量计数错误!");
    
    // 没有缓存可以播放了
    //
    if ( _PCMBufferCount == 0 ) {
        [self _toEvaluating];
    }
    
    [self _pullNextBufferIfNeeded];
}

#pragma mark - notifies

- (void)_observeNotifies {
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioSessionInterruptionWithNote:) name:AVAudioSessionInterruptionNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioSessionRouteChangeWithNote:) name:AVAudioSessionRouteChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioEngineConfigurationChangeWithNote:) name:AVAudioEngineConfigurationChangeNotification object:_playbackController.engine];
}

- (void)audioSessionInterruptionWithNote:(NSNotification *)note {
    [self pause];
}

- (void)audioSessionRouteChangeWithNote:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    AVAudioSessionRouteChangeReason reason = [[info valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    if      ( reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable ) {
        [self pause];
    }
    else if ( reason == AVAudioSessionRouteChangeReasonNewDeviceAvailable ) {
        [self reload];
    }
}

- (void)audioEngineConfigurationChangeWithNote:(NSNotification *)note {
    [self reload];
}

#pragma mark - mark

- (void)_toEvaluating {
    // 发生错误
    //TODO: 发生错误的可能不是来自AudioItem, 将来如果做retry可能会出现播放位置错误的问题
    if ( _error != nil ) {
        [self _stopPlayback];
        [self _setStatus:APAudioPlaybackStatusError];
        return;
    }
    
    /// 已播放完毕
    ///
    BOOL isPlaybackFinished = _currentItem.isReachedEnd && _PCMBufferCount == 0;
    if ( isPlaybackFinished ) {
        [self _stopPlayback];
        [self _setStatus:APAudioPlaybackStatusEnded];
        return;
    }
    
    /// 暂停态
    ///
    if ( _status & APAudioPlaybackStatusPaused ) {
        [self _pausePlayback];
        return;
    }
    
    /// 当前无item可播放
    ///
    ///     设置item后, 将会重置状态为Evaluating
    ///
    BOOL isNoItemToPlay = _status & APAudioPlaybackStatusPlaying && _currentItem == nil;
    if ( isNoItemToPlay ) {
        [self _stopPlayback];
        [self _setStatus:APAudioPlaybackStatusNoItemToPlay];
        return;
    }
    
    ///
    ///     - PCMBuffer数量小于最小播放量时, 修改为缓冲状态
    ///
    BOOL isBuffering = _PCMBufferCount < SJAudioPlayerMinimumPCMBufferCountToBePlayable;
    if ( isBuffering ) {
        [self _pausePlayback];
        [self _setStatus:APAudioPlaybackStatusBuffering];
        return;
    }
    
    if ( _status != APAudioPlaybackStatusPlaying && [self _playPlayback] ) {
        [self _setStatus:APAudioPlaybackStatusPlaying];
    }
}

- (void)_pullNextBufferIfNeeded {
    // PCM缓存未满(未到达最大限定值), 恢复缓存
    if ( !_currentItem.isReachedEnd && _currentItem.error == nil && _PCMBufferCount < (SJAudioPlayerMaximumPCMBufferCount * 0.5) ) {
        [_currentItem resume];
    }
}

- (void)_onError:(NSError *)error {
#ifdef DEBUG
    NSLog(@"%@<%p>.error: %@", NSStringFromClass(self.class), self, error);
#endif
    
    APAudioPlayerDebugLog(@"%@: <%p>.error { error: %@ }\n", NSStringFromClass(self.class), self, error);
    _error = error;
    [self _toEvaluating];
}
@end

NSNotificationName const SJAudioPlayerStatusDidChangeNotification = @"SJAudioPlayerStatusDidChangeNotification";
NSNotificationName const SJAudioPlayerBufferProgressDidChangeNotification = @"SJAudioPlayerBufferProgressDidChangeNotification";
