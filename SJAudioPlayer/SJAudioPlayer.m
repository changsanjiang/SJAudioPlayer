//
//  SJAudioPlayer.m
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/14.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "SJAudioPlayer.h"
#import "SJAudioPlayerSubclass.h"
#import "APAudioPlaybackController.h"
#import "APAudioItem.h"
#import "APError.h"
#import "APUtils.h"
#import "APLogger.h"

@interface SJAudioPlayer ()<APAudioItemDelegate> {
    id<APAudioPlaybackController> _mPlaybackController;
    NSHashTable<id<SJAudioPlayerObserver>> *_Nullable _mObservers;
    AVAudioSessionCategory _mCategory;
    AVAudioSessionCategoryOptions _mCategoryOptions;
    AVAudioSessionSetActiveOptions _mSetActiveOptions;
    __kindof id<APAudioOptions>_Nullable _mOptions;
    NSURL *_Nullable _mURL;
}

@property (nonatomic, strong, nullable) APAudioItem *currentItem;
@property (nonatomic) NSInteger PCMBufferCount;
@end

static void *mAPQueueKey = &mAPQueueKey;
static dispatch_queue_t mAPQueue;
FOUNDATION_STATIC_INLINE void
ap_queue_init() {
    mAPQueue = dispatch_queue_create("queue.SJAudioPlayer", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(mAPQueue, mAPQueueKey, mAPQueueKey, NULL);
}

FOUNDATION_STATIC_INLINE void
ap_queue_sync(NS_NOESCAPE dispatch_block_t block) {
    if ( dispatch_get_specific(mAPQueueKey) )
        block();
    else
        dispatch_sync(mAPQueue, block);
}

FOUNDATION_STATIC_INLINE void
ap_queue_async(dispatch_block_t block) {
    dispatch_async(mAPQueue, block);
}

@implementation SJAudioPlayer

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ap_queue_init();
    });
}

+ (instancetype)player {
    return [[self alloc] init];
}

- (instancetype)init {
    return [self initWithPlaybackController:APAudioPlaybackController.alloc.init];
}

- (instancetype)initWithPlaybackController:(id<APAudioPlaybackController>)playbackController {
    NSParameterAssert(playbackController != nil);
    self = [super init];
    if ( self ) {
        _mPlaybackController = playbackController;
        _mCategory = AVAudioSessionCategoryPlayback;
        _mCategoryOptions = AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDuckOthers;
        _mSetActiveOptions = AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation;
        _status = APAudioPlaybackStatusPaused;
        [self _observeNotifies];
    }
    return self;
}

+ (Class)defaultOptionsClass {
    return APAudioOptions.class;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_mPlaybackController stop];
}

- (NSTimeInterval)currentTime {
    __block NSTimeInterval currentTime = 0;
    ap_queue_sync(^{
        currentTime = [self _currentTime];
    });
    return currentTime;
}

- (NSTimeInterval)duration {
    __block NSTimeInterval duration = 0;
    ap_queue_sync(^{
        duration = _currentItem.duration;
    });
    return duration;
}

- (__kindof id<APAudioOptions>_Nullable)options {
    __block id<APAudioOptions> options = nil;
    ap_queue_sync(^{
        options = _mOptions;
    });
    return options;
}

- (nullable NSURL *)URL {
    __block NSURL *URL;
    ap_queue_sync(^{
       URL = _mURL;
    });
    return URL;
}

- (float)bufferProgress {
    __block float progress = 0;
    ap_queue_sync(^{
        progress = _currentItem.contentLoadProgress;
    });
    return progress;
}
  
- (void)setRate:(float)rate {
    ap_queue_sync(^{
        _mPlaybackController.rate = rate;
    });
}

- (float)rate {
    __block float rate = 0;
    ap_queue_sync(^{
        rate = _mPlaybackController.rate;
    });
    return rate;
}

- (void)setVolume:(float)volume {
    ap_queue_sync(^{
        _mPlaybackController.volume = volume;
    });
}

- (float)volume {
    __block float volume = 0;
    ap_queue_sync(^{
        volume = _mPlaybackController.volume;
    });
    return volume;
}

- (void)setMuted:(BOOL)muted {
    ap_queue_sync(^{
        _mPlaybackController.muted = muted;
    });
}

- (BOOL)isMuted {
    __block BOOL isMuted = 0;
    ap_queue_sync(^{
        isMuted = _mPlaybackController.isMuted;
    });
    return isMuted;
}

- (void)replaceAudioWithURL:(nullable NSURL *)URL {
    [self replaceAudioWithURL:URL options:nil];
}

- (void)replaceAudioWithURL:(nullable NSURL *)URL options:(nullable __kindof id<APAudioOptions>)options {
    ap_queue_sync(^{
        APAudioPlayerDebugLog(@"%@: <%p>.%s { URL: %@ }\n", NSStringFromClass(self.class), self, sel_getName(_cmd), URL);

        [self resetPlaybackWithURL:URL options:options];
    });
}

- (void)seekToTime:(NSTimeInterval)time {
    ap_queue_sync(^{
        APAudioPlayerDebugLog(@"%@: <%p>.%s { time: %lf }\n", NSStringFromClass(self.class), self, sel_getName(_cmd), time);
        
        if ( _currentItem.status == APAudioItemStatusUnknown )
            return;
        _error = nil;
        [self stopPlayback];
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
    ap_queue_sync(^{
        APAudioPlayerDebugLog(@"%@: <%p>.%s\n", NSStringFromClass(self.class), self, sel_getName(_cmd));

        if ( _currentItem.status == APAudioItemStatusUnknown )
            return;
        _error = nil;
        [self stopPlayback];
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

- (void)cancelPlayableDurationLimit {
    ap_queue_sync(^{
        APAudioPlayerDebugLog(@"%@: <%p>.%s\n", NSStringFromClass(self.class), self, sel_getName(_cmd));
        
        [_currentItem cancelPlayableDurationLimit];
        [self _pullNextBufferIfNeeded];
    });
}

- (BOOL)isReachedEndPosition {
    __block BOOL retv = NO;
    ap_queue_sync(^{
        retv = _currentItem.isReachedEndPosition;
    });
    return retv;
}

- (BOOL)isReachedMaximumPlayableDurationPosition {
    __block BOOL retv = NO;
    ap_queue_sync(^{
        retv = _currentItem.isReachedMaximumPlayableDurationPosition;
    });
    return retv;
}

- (void)play {
    ap_queue_sync(^{
        APAudioPlayerDebugLog(@"%@: <%p>.%s\n", NSStringFromClass(self.class), self, sel_getName(_cmd));

        if ( _status & APAudioPlaybackStatusPlaying )
            return;
        [self _setStatus:APAudioPlaybackStatusEvaluating];
        [self _toEvaluating];
    });
}

- (void)pause {
    ap_queue_sync(^{
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
    [self performSelectorOnMainThread:@selector(_registerObserver:) withObject:observer waitUntilDone:YES modes:@[NSRunLoopCommonModes]];
}

- (void)removeObserver:(id<SJAudioPlayerObserver>)observer {
    if ( observer == nil )
        return;
    [self performSelectorOnMainThread:@selector(_removeObserver:) withObject:observer waitUntilDone:YES modes:@[NSRunLoopCommonModes]];
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
        for ( id<SJAudioPlayerObserver> observer in self->_mObservers ) {
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
            for ( id<SJAudioPlayerObserver> observer in self->_mObservers ) {
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
    AVAudioFramePosition lastPosition = _mPlaybackController.lastPosition;
    AVAudioFramePosition currentPosition = _currentItem.startPosition + lastPosition;
    return currentPosition / sampleRate;
}

- (BOOL)playPlayback {
    APAudioPlayerDebugLog(@"%@: <%p>.%s\n", NSStringFromClass(self.class), self, sel_getName(_cmd));
    
    NSError *error = nil;
    // https://stackoverflow.com/questions/29036294/avaudiorecorder-not-recording-in-background-after-audio-session-interruption-end
    if ( ![AVAudioSession.sharedInstance setCategory:_mCategory withOptions:_mCategoryOptions error:&error] ) {
        [self _onError:error];
        return NO;
    }
    if ( ![AVAudioSession.sharedInstance setActive:YES withOptions:_mSetActiveOptions error:&error] ) {
        [self _onError:error];
        return NO;
    }
    if ( ![_mPlaybackController play:&error] ) {
        [self _onError:error];
        return NO;
    }
    
    return YES;
}

- (void)pausePlayback {
    APAudioPlayerDebugLog(@"%@: <%p>.%s\n", NSStringFromClass(self.class), self, sel_getName(_cmd));

    [_mPlaybackController pause];
}

- (void)stopPlayback {
    APAudioPlayerDebugLog(@"%@: <%p>.%s\n", NSStringFromClass(self.class), self, sel_getName(_cmd));

    [_mPlaybackController stop];
}

- (void)resetPlaybackWithURL:(NSURL *)newURL options:(id<APAudioOptions>)options {
    APAudioPlayerDebugLog(@"%@: <%p>.%s\n", NSStringFromClass(self.class), self, sel_getName(_cmd));

    [_mPlaybackController reset];
    _currentItem = nil;
    _PCMBufferCount = 0;
    _error = nil;
    
    _mURL = newURL;
    _mOptions = options ?: [[[self class] defaultOptionsClass]  defaultOptions];
    if ( _mURL != nil ) {
        _currentItem = [APAudioItem.alloc initWithURL:_mURL options:_mOptions delegate:self queue:mAPQueue];
        [_currentItem prepare];
    }
    if ( _status & APAudioPlaybackStatusPlaying ) {
        [self _setStatus:APAudioPlaybackStatusEvaluating];
    }
    [self _toEvaluating];
}

#pragma mark -

- (void)_newBufferAvailable:(AVAudioPCMBuffer *)buffer {
    _PCMBufferCount += 1;
    AVAudioFramePosition previousFrames = _mPlaybackController.frameLengthInBuffers;
    APAudioPlayerDebugLog(@"%@: <%p>.%s { newBuffer: %@, offset: %lld, curCount: %ld }\n", NSStringFromClass(self.class), self, sel_getName(_cmd), buffer, previousFrames, (long)_PCMBufferCount);
    
    if ( _PCMBufferCount >= _mOptions.maximumCountOfPCMBufferForPlayback ) {
        [_currentItem suspend];
    }
    __weak APAudioItem *item = _currentItem;
    __weak typeof(self) _self = self;
    [_mPlaybackController scheduleBuffer:buffer atPosition:(APAudioPCMBufferPosition){_currentItem.startPosition, previousFrames} completionHandler:^{
        ap_queue_async(^{
            __strong typeof(_self) self = _self;
            if ( self == nil ) return;
            if ( self.currentItem != nil && item == self.currentItem ) {
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
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioEngineConfigurationChangeWithNote:) name:AVAudioEngineConfigurationChangeNotification object:_mPlaybackController.engine];
}

- (void)audioSessionInterruptionWithNote:(NSNotification *)note {
    ap_queue_sync(^{
        APAudioPlayerDebugLog(@"%@: <%p>.%s\n", NSStringFromClass(self.class), self, sel_getName(_cmd));
        
        switch ( (AVAudioSessionInterruptionType)[note.userInfo[AVAudioSessionInterruptionTypeKey] integerValue] ) {
            case AVAudioSessionInterruptionTypeBegan: {
                if ( !(_status & APAudioPlaybackStatusPaused) ) {
                    [self _setStatus:APAudioPlaybackStatusInterruptive];
                    [self _toEvaluating];
                }
            }
                break;
            case AVAudioSessionInterruptionTypeEnded: {
                if ( _status == APAudioPlaybackStatusInterruptive ) {
                    AVAudioSessionInterruptionOptions options = [note.userInfo[AVAudioSessionInterruptionOptionKey] integerValue];
                    if ( options == AVAudioSessionInterruptionOptionShouldResume ) {
                        [self _setStatus:APAudioPlaybackStatusEvaluating];
                        [self _toEvaluating];
                    }
                }
            }
                break;
        }
    });
}

- (void)audioSessionRouteChangeWithNote:(NSNotification *)note {
    ap_queue_sync(^{
        APAudioPlayerDebugLog(@"%@: <%p>.%s\n", NSStringFromClass(self.class), self, sel_getName(_cmd));
        
        NSDictionary *info = note.userInfo;
        AVAudioSessionRouteChangeReason reason = [[info valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
        if      ( reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable ) {
            if ( !(_status & APAudioPlaybackStatusPaused) ) {
                [self _setStatus:APAudioPlaybackStatusRouteChangedOldDeviceUnavailable];
                [self _toEvaluating];
            }
        }
        else if ( reason == AVAudioSessionRouteChangeReasonNewDeviceAvailable ) {
            [self reload];
        }
    });
}

- (void)audioEngineConfigurationChangeWithNote:(NSNotification *)note {
    [self reload];
}

#pragma mark - mark

- (void)_toEvaluating {
    // 发生错误
    //TODO: 发生错误的可能不是来自AudioItem, 将来如果做retry可能会出现播放位置错误的问题
    if ( _error != nil ) {
        [self stopPlayback];
        [self _setStatus:APAudioPlaybackStatusFailed];
        return;
    }
    
    /// 已播放完毕
    ///
    BOOL isPlaybackFinished = (_currentItem.isReachedEndPosition || _currentItem.isReachedMaximumPlayableDurationPosition) && _PCMBufferCount == 0;
    if ( isPlaybackFinished ) {
        [self stopPlayback];
        [self _setStatus:APAudioPlaybackStatusFinished];
        return;
    }
    
    /// 暂停态
    ///
    if ( _status & APAudioPlaybackStatusPaused ) {
        [self pausePlayback];
        return;
    }
    
    /// 当前无item可播放
    ///
    ///     设置item后, 将会重置状态为Evaluating
    ///
    BOOL isNoItemToPlay = _status & APAudioPlaybackStatusPlaying && _currentItem == nil;
    if ( isNoItemToPlay ) {
        [self stopPlayback];
        [self _setStatus:APAudioPlaybackStatusNoItemToPlay];
        return;
    }
    
    ///
    ///     - PCMBuffer数量小于最小播放量时, 修改为缓冲状态
    ///
    BOOL isBuffering = _PCMBufferCount < (_mOptions.minimumCountOfPCMBufferToBePlayable ?: 1);
    if ( isBuffering ) {
        [self pausePlayback];
        [self _setStatus:APAudioPlaybackStatusBuffering];
        return;
    }
    
    if ( _status != APAudioPlaybackStatusPlaying && [self playPlayback] ) {
        [self _setStatus:APAudioPlaybackStatusPlaying];
    }
}

- (void)_pullNextBufferIfNeeded {
    // PCM缓存未满(未到达最大限定值), 恢复缓存
    if ( !_currentItem.isReachedEndPosition && _currentItem.error == nil && _PCMBufferCount < (_mOptions.maximumCountOfPCMBufferForPlayback * 0.5) ) {
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

- (void)_registerObserver:(id<SJAudioPlayerObserver>)observer {
    if ( _mObservers == nil ) {
        _mObservers = NSHashTable.weakObjectsHashTable;
    }
    [_mObservers addObject:observer];
}

- (void)_removeObserver:(id<SJAudioPlayerObserver>)observer {
    [_mObservers removeObject:observer];
}

@end


@implementation SJAudioPlayer (SJAVAudioSessionExtended)
- (void)setCategory:(AVAudioSessionCategory)category withOptions:(AVAudioSessionCategoryOptions)options {
    _mCategory = category;
    _mCategoryOptions = options;
}

- (void)setActiveOptions:(AVAudioSessionSetActiveOptions)options {
    _mSetActiveOptions = options;
}
@end

NSNotificationName const SJAudioPlayerStatusDidChangeNotification = @"SJAudioPlayerStatusDidChangeNotification";
NSNotificationName const SJAudioPlayerBufferProgressDidChangeNotification = @"SJAudioPlayerBufferProgressDidChangeNotification";
