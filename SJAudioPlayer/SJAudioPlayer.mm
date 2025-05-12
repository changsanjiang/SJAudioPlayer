//
//  SJAudioPlayer.m
//  LWZFFmpegLib
//
//  Created by db on 2025/4/15.
//

#import "SJAudioPlayer.h"
#if __has_include(<libffmpeg/FFAudioItem.h>)
#import <libffmpeg/FFAudioItem.h>
#else
#import "FFAudioItem.h"
#endif

#import "SJAudioPlaybackController.h"
#include <atomic>
#include <mutex>

NSErrorDomain const SJAudioPlaybackControllerErrorDomain = @"SJAudioPlaybackControllerErrorDomain";

static void *FF_AUDIO_PLAYER_QUEUE = &FF_AUDIO_PLAYER_QUEUE;

FOUNDATION_STATIC_INLINE void
SJQueueSync(dispatch_queue_t queue, NS_NOESCAPE dispatch_block_t block) {
    if ( dispatch_get_specific(FF_AUDIO_PLAYER_QUEUE) != NULL ) {
        block();
    }
    else {
        dispatch_sync(queue, block);
    }
}

@interface SJAudioPlayer ()<FFAudioItemDelegate> {
    id<SJAudioPlaybackController> _mPlaybackController;
    FFAudioItem *_mAudioItem;
    NSURL *_mURL;
    __kindof SJAudioPlayerOptions *_mOptions;
    NSError *_mError;
    
    std::atomic<CMTime> _mDuration;
    std::atomic<CMTime> _mCurrentTime;
    std::atomic<CMTimeRange> _mPlayableTimeRange;
    std::atomic<CMTime> _mPlayableDurationLimit;

    std::atomic<BOOL> _mPlayWhenReady;
    SJPlayWhenReadyChangeReason _mPlaybackWhenReadyChangeReason;
    
    NSHashTable<id<SJAudioPlayerObserver>> *_Nullable _mObservers;
    
    AVAudioSessionCategory _mCategory;
    AVAudioSessionCategoryOptions _mCategoryOptions;
    AVAudioSessionSetActiveOptions _mSetActiveOptions;
    
    dispatch_queue_t _mQueue;
}

// atomic
- (void)setPlayWhenReady:(BOOL)playWhenReady changeReason:(SJPlayWhenReadyChangeReason)reason;
@property (nonatomic) CMTime currentTime;
@property (nonatomic) CMTime duration;
@property (nonatomic) CMTimeRange playableTimeRange;
@end

@implementation SJAudioPlayer

- (instancetype)init {
    return [self initWithPlaybackController:[SJAudioPlaybackController.alloc init]];
}

+ (instancetype)player {
    return [[self alloc] init];
}

- (instancetype)initWithPlaybackController:(id<SJAudioPlaybackController>)playbackController {
    self = [super init];
    _mQueue = dispatch_queue_create("SJAudioPlayerQueue", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(_mQueue, FF_AUDIO_PLAYER_QUEUE, FF_AUDIO_PLAYER_QUEUE, nullptr);
    
    _mDuration.store(kCMTimeZero, std::__1::memory_order_relaxed);
    _mCurrentTime.store(kCMTimeZero, std::__1::memory_order_relaxed);
    _mPlayableTimeRange.store(kCMTimeRangeZero, std::__1::memory_order_relaxed);
    _mPlayWhenReady.store(false, std::__1::memory_order_relaxed);
    
    _mPlaybackController = playbackController;
    __weak typeof(self) _self = self;
    _mPlaybackController.audioEngineConfigurationChangeHandler = ^(id<SJAudioPlaybackController>  _Nonnull playbackController) {
        __strong typeof(_self) self = _self;
        if ( self == nil ) return;
        [self handleAudioEngineConfigurationChange];
    };
    
    if ( @available(iOS 13.0, *) ) {
        _mPlaybackController.renderBlock = ^(BOOL * _Nonnull isSilence, AVAudioFrameCount frameCount, AudioBufferList * _Nonnull outputData, int64_t * _Nonnull pts) {
            __strong typeof(_self) self = _self;
            if ( self == nil ) return;
            [self handleRenderWithSilence:isSilence frameCount:frameCount outputData:outputData pts:pts];
        };
    }
    
    _mCategory = AVAudioSessionCategoryPlayback;
    _mCategoryOptions = AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDuckOthers;
    _mSetActiveOptions = AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation;
    
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioSessionInterruptionWithNote:) name:AVAudioSessionInterruptionNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioSessionRouteChangeWithNote:) name:AVAudioSessionRouteChangeNotification object:nil];
    return self;
}

- (void)dealloc {
#ifdef DEBUG
    NSLog(@"%@<%p>: %d : %s", NSStringFromClass(self.class), self, __LINE__, sel_getName(_cmd));
#endif
    
    [_mPlaybackController stop:NULL];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSURL *)URL {
    __block NSURL *ret = nil;
    SJQueueSync(_mQueue, ^{
        ret = _mURL;
    });
    return ret;
}

- (__kindof SJAudioPlayerOptions *)options {
    __block __kindof SJAudioPlayerOptions *ret = nil;
    SJQueueSync(_mQueue, ^{
        ret = _mOptions.copy;
    });
    return ret;
}

- (NSError *)error {
    __block NSError *ret = nil;
    SJQueueSync(_mQueue, ^{
        ret = _mError;
    });
    return ret;
}

- (void)setPlayWhenReady:(BOOL)playWhenReady changeReason:(SJPlayWhenReadyChangeReason)reason {
    _mPlayWhenReady.store(playWhenReady, std::__1::memory_order_relaxed);
    _mPlaybackWhenReadyChangeReason = reason;
    
    [self _notifyOnPlayWhenReadyChange:playWhenReady reason:reason];
}

- (BOOL)playWhenReady {
    return _mPlayWhenReady.load(std::__1::memory_order_relaxed);
}

- (void)setCurrentTime:(CMTime)currentTime {
    _mCurrentTime.store(currentTime, std::__1::memory_order_relaxed);
}

- (CMTime)currentTime {
    return _mCurrentTime.load(std::__1::memory_order_relaxed);
}

- (void)setDuration:(CMTime)duration {
    if ( CMTimeCompare(_mDuration.exchange(duration), duration) ) {
        _mDuration.store(duration, std::__1::memory_order_relaxed);
        [self _notifyOnDurationTimeChange:duration];
    }
}

- (CMTime)duration {
    return _mDuration.load(std::__1::memory_order_relaxed);
}

- (void)setPlayableTimeRange:(CMTimeRange)timeRange {
    _mPlayableTimeRange.store(timeRange, std::__1::memory_order_relaxed);
}

- (CMTimeRange)playableTimeRange {
    return _mPlayableTimeRange.load(std::__1::memory_order_relaxed);
}

- (CMTime)playableDurationLimit {
    return _mPlayableDurationLimit.load(std::__1::memory_order_relaxed);
}

- (void)setPlayableDurationLimit:(CMTime)playableDurationLimit {
    _mPlayableDurationLimit.store(playableDurationLimit, std::__1::memory_order_relaxed);
}

- (void)cancelPlayableDurationLimit {
    _mPlayableDurationLimit.store(kCMTimeZero, std::__1::memory_order_relaxed);
}

- (void)setRate:(float)rate {
    SJQueueSync(_mQueue, ^{
        _mPlaybackController.rate = rate;
    });
}

- (float)rate {
    __block float ret;
    SJQueueSync(_mQueue, ^{
        ret = _mPlaybackController.rate;
    });
    return ret;
}

- (void)setVolume:(float)volume {
    SJQueueSync(_mQueue, ^{
        _mPlaybackController.volume = volume;
    });
}

- (float)volume {
    __block float ret;
    SJQueueSync(_mQueue, ^{
        ret = _mPlaybackController.volume;
    });
    return ret;
}

- (void)setMute:(BOOL)mute {
    SJQueueSync(_mQueue, ^{
        _mPlaybackController.mute = mute;
    });
}

- (BOOL)isMute {
    __block BOOL ret;
    SJQueueSync(_mQueue, ^{
        ret = _mPlaybackController.isMute;
    });
    return ret;
}

- (void)setAudioItem:(FFAudioItem *)audioItem {
    @synchronized (self) {
        _mAudioItem = audioItem;
    }
}

- (FFAudioItem *)audioItem {
    @synchronized (self) {
        return _mAudioItem;
    };
}

#pragma mark - mark

- (void)replaceAudioWithURL:(nullable NSURL *)URL {
    [self replaceAudioWithURL:URL options:nil];
}

- (void)replaceAudioWithURL:(nullable NSURL *)URL options:(nullable __kindof SJAudioPlayerOptions *)options {
    dispatch_async(_mQueue, ^{
        NSError *error = NULL;
        if ( ![self->_mPlaybackController stop:&error] && ![self->_mPlaybackController reset:&error] ) {
            [self onError:error];
            return;
        }
        
        if ( URL ) {
            FFAudioItemOptions *itemOptions = nil;
            if ( options ) {
                itemOptions = [FFAudioItemOptions.alloc init];
                itemOptions.startTimePosition = options.startTimePosition;
            }
            self.audioItem = [FFAudioItem.alloc initWithURL:URL options:itemOptions delegate:self];
        }
        else {
            self.audioItem = nil;
        }
        
        self->_mURL = URL;
        self->_mOptions = options;
        self.playableDurationLimit = options ? options.playableDurationLimit : kCMTimeZero;
        self.currentTime = kCMTimeZero;
        self.playableTimeRange = kCMTimeRangeZero;
        self.duration = kCMTimeZero;
        [self onError:nil];
        
        [self setPlayWhenReady:self.playWhenReady changeReason:SJPlayWhenReadyChangeReasonUserRequest];
        if ( self.playWhenReady ) {
            if ( ![self->_mPlaybackController play:&error] ) {
                [self onError:error];
                return;
            }
        }
    });
}

- (void)seekToTime:(CMTime)time {
    dispatch_async(_mQueue, ^{
        if ( !self.audioItem ) {
            return;
        }
        
        CMTime seekTime = time;
        CMTime playableDurationLimit = self.playableDurationLimit;
        if ( CMTimeCompare(playableDurationLimit, kCMTimeZero) != 0 ) {
            if ( CMTimeCompare(seekTime, playableDurationLimit) == 1 ) {
                seekTime = playableDurationLimit;
            }
        }
        
        if ( self->_mError ) {
            [self _onReprepareByErrorWithStartTimePosition:seekTime];
        }
        else {
            [self.audioItem seekToTime:seekTime];
        }

        NSError *error = nil;
        if ( ![self->_mPlaybackController stop:&error] && ![self->_mPlaybackController reset:&error] ) {
            [self onError:error];
            return;
        }
        [self setPlayWhenReady:YES changeReason:SJPlayWhenReadyChangeReasonUserRequest];
    });
}

- (void)play {
    dispatch_async(_mQueue, ^{
        if ( self->_mError ) {
            [self _onReprepareByErrorWithStartTimePosition:self->_mCurrentTime];
            return;
        }

        if ( self->_mPlaybackWhenReadyChangeReason == SJPlayWhenReadyChangeReasonReachedEndPosition ||
             self->_mPlaybackWhenReadyChangeReason == SJPlayWhenReadyChangeReasonReachedMaximumPlayableDurationPosition ) {
            [self.audioItem seekToTime:kCMTimeZero];
        }
        
        [self _onPlay:SJPlayWhenReadyChangeReasonUserRequest];
    });
}

- (void)pause {
    dispatch_async(_mQueue, ^{
        if ( self->_mError ) {
            return;
        }
        [self _onPause:SJPlayWhenReadyChangeReasonUserRequest];
    });
}

- (void)registerObserver:(id<SJAudioPlayerObserver>)observer {
    SJQueueSync(_mQueue, ^{
        if ( _mObservers == nil ) {
            _mObservers = NSHashTable.weakObjectsHashTable;
        }
        [_mObservers addObject:observer];
    });
}

- (void)removeObserver:(id<SJAudioPlayerObserver>)observer {
    SJQueueSync(_mQueue, ^{
        if ( _mObservers ) {
            [_mObservers removeObject:observer];
        }
    });
}

#pragma mark - mark

- (void)_onPlay:(SJPlayWhenReadyChangeReason)reason {
    if ( _mPlaybackWhenReadyChangeReason == SJPlayWhenReadyChangeReasonReachedEndPosition ) {
        return;
    }
    
    [self setPlayWhenReady:true changeReason:reason];
    
    [AVAudioSession.sharedInstance setCategory:_mCategory withOptions:_mCategoryOptions error:NULL];
    [AVAudioSession.sharedInstance setActive:YES withOptions:_mSetActiveOptions error:NULL];
    
    NSError *error = nil;
    if ( ![_mPlaybackController play:&error] ) {
        [self onError:error];
        return;
    }
}

- (void)_onPause:(SJPlayWhenReadyChangeReason)reason {
    if ( _mPlaybackWhenReadyChangeReason == SJPlayWhenReadyChangeReasonReachedEndPosition ) {
        return;
    }
    
    [self setPlayWhenReady:false changeReason:reason];

    NSError *error = nil;
    if ( ![_mPlaybackController pause:&error] ) {
        [self onError:error];
        return;
    }
}

/// 重新准备相关资源, 并设置播放
- (void)_onReprepareByErrorWithStartTimePosition:(CMTime)time {
    NSError *error = _mError;
    NSParameterAssert(error != nil);
    
    if ( error.domain == SJAudioPlaybackControllerErrorDomain ) {
        NSError *err = nil;
        if ( ![_mPlaybackController reset:&err] ) {
            [self onError:error];
            return;
        }
        [self onError:nil];
        [self _onPlay:SJPlayWhenReadyChangeReasonUserRequest];
    }
    else if ( error.domain == FFAudioItemErrorDomain ) {
        FFAudioItemOptions *options = [FFAudioItemOptions.alloc init];
        options.startTimePosition = time;
        self.audioItem = [FFAudioItem.alloc initWithURL:_mURL options:options delegate:self];
        [self onError:nil];
        [self _onPlay:SJPlayWhenReadyChangeReasonUserRequest];
    }
}

- (void)onError:(NSError *_Nullable)error {
    if ( _mError != error ) {
#ifdef DEBUG
    NSLog(@"%@<%p>: %d : %s, error: %@", NSStringFromClass(self.class), self, __LINE__, sel_getName(_cmd), error);
#endif

        _mError = error;
        
        if ( error ) {
            [self->_mPlaybackController stop:nil];
        }
        [self _notifyOnErrorChange:error];
    }
}

#pragma mark - notifies

- (NSArray<id<SJAudioPlayerObserver>> *_Nullable)getObservers {
    if ( _mObservers ) {
        return _mObservers.count > 0 ? NSAllHashTableObjects(_mObservers) : nil;
    }
    return nil;
}

- (void)_notifyOnPlayWhenReadyChange:(BOOL)playWhenReady reason:(SJPlayWhenReadyChangeReason)reason {
    NSArray<id<SJAudioPlayerObserver>> *observers = [self getObservers];
    if ( observers ) {
        dispatch_async(dispatch_get_main_queue(), ^{
            for ( id<SJAudioPlayerObserver> observer in observers ) {
                [observer audioPlayer:self playWhenReadyDidChange:playWhenReady reason:reason];
            }
        });
    }
}

- (void)_notifyOnDurationTimeChange:(CMTime)duration {
    NSArray<id<SJAudioPlayerObserver>> *observers = [self getObservers];
    if ( observers ) {
        dispatch_async(dispatch_get_main_queue(), ^{
            for ( id<SJAudioPlayerObserver> observer in observers ) {
                [observer audioPlayer:self durationDidChange:duration];
            }
        });
    }
}

- (void)_notifyOnErrorChange:(NSError *_Nullable)error {
    NSArray<id<SJAudioPlayerObserver>> *observers = [self getObservers];
    if ( observers ) {
        dispatch_async(dispatch_get_main_queue(), ^{
            for ( id<SJAudioPlayerObserver> observer in observers ) {
                [observer audioPlayer:self errorDidChange:error];
            }
        });
    }
}

#pragma mark - FFAudioItemDelegate


- (void)audioItemDidReadyToRead:(FFAudioItem *)item {
    self.duration = item.duration;
}

- (void)audioItem:(FFAudioItem *)item anErrorOccurred:(NSError *)error {
    dispatch_async(_mQueue, ^{
        [self onError:error];
    });
}

- (void)audioItem:(FFAudioItem *)item playableTimeRangeDidChange:(CMTimeRange)timeRange {
    self.playableTimeRange = timeRange;
}

- (void)audioItemDidSeek:(FFAudioItem *)item {
    dispatch_async(_mQueue, ^{
        if ( self.playWhenReady ) {
            NSError *error = nil;
            // 重置播放
            if ( ![self->_mPlaybackController stop:&error] && ![self->_mPlaybackController reset:&error] ) {
                [self onError:error];
                return;
            }
            // 恢复播放
            if ( ![self->_mPlaybackController play:&error] ) {
                [self onError:error];
                return;
            }
        }
    });
}

- (void)handleRenderWithSilence:(BOOL *)isSilence frameCount:(AVAudioFrameCount)frameCount outputData:(AudioBufferList *)outputData pts:(int64_t *)outPts {
    FFAudioItem *audioItem = self.audioItem;
    UInt32 channels = outputData->mNumberBuffers;
    if ( audioItem != nil ) {
        NSCAssert(channels == audioItem.outputFormat.channelCount, @"Channel count mismatch!");
    }
    
    // 准备每个通道的输出指针
    float *outPtrs[channels];
    for (UInt32 ch = 0; ch < channels; ch++) {
        outPtrs[ch] = (float *)outputData->mBuffers[ch].mData;
    }
    
    BOOL eof = NO;
    int64_t pts = 0;
    NSError *error = nil;
    int ret = 0;
    
    if ( audioItem != nil ) {
        ret = [audioItem tryTranscodeWithFrameCapacity:frameCount data:(void **)outPtrs pts:&pts eof:&eof error:&error];
    }
    
    AVAudioFrameCount framesRead = ret > 0 ? ret : 0;
    if ( framesRead < frameCount ) {
        for (UInt32 ch = 0; ch < channels; ch++) {
            float *chOut = outPtrs[ch] + framesRead;
            memset(chOut, 0, sizeof(float) * (frameCount - framesRead));
        }
        *isSilence = (framesRead == 0); // 完全没有数据 → 标记为静音
    }
    else {
        *isSilence = NO;
    }
    
    if ( outPts ) {
        *outPts = pts;
    }
    
    if ( error != nil ) {
        dispatch_async(_mQueue, ^{
            if ( audioItem == self.audioItem ) {
                [self onError:error];
            }
        });
        return;
    }
    
    if ( !eof && ret == 0 && pts == 0 ) {
        return;
    }
    
    CMTime duration = self.duration;
    if ( CMTimeCompare(duration, kCMTimeZero) == 0 ) {
        return;
    }
    
    CMTime currentTime = self.currentTime;
    currentTime = CMTimeMake(pts, audioItem.outputFormat.sampleRate);
    
    // 如果限制了播放时长, 则判断pts是否超出了限制;
    CMTime playableDurationLimit = _mPlayableDurationLimit.load(std::__1::memory_order_relaxed);
    if (
        CMTimeCompare(playableDurationLimit, kCMTimeZero) &&
        CMTimeCompare(currentTime, kCMTimeZero) &&
        CMTimeCompare(currentTime, playableDurationLimit) > 0
    ) {
        currentTime = playableDurationLimit;
    }
    
    if ( CMTimeCompare(currentTime, duration) > 0 ) {
        currentTime = duration;
    }
    
    // 更新当前时间
    self.currentTime = currentTime;
    
    // eof & 播放结束
    if ( eof && ret == 0 ) {
        dispatch_async(_mQueue, ^{
            if ( audioItem == self.audioItem ) {
                [self _onPause:SJPlayWhenReadyChangeReasonReachedEndPosition];
            }
        });
    }
    // 到了限制的播放时长
    else if ( playableDurationLimit.value > 0 && CMTimeCompare(currentTime, playableDurationLimit) == 0 ) {
        dispatch_async(_mQueue, ^{
            if ( audioItem == self.audioItem ) {
                [self _onPause:SJPlayWhenReadyChangeReasonReachedMaximumPlayableDurationPosition];
            }
        });
    }
}

- (void)handleAudioEngineConfigurationChange {
    dispatch_async(_mQueue, ^{
        NSError *error = nil;
        // 重置
        if ( ![self->_mPlaybackController reset:&error] ) {
            [self onError:error];
            return;
        }
        
        // 恢复播放
        if ( self.playWhenReady && ![self->_mPlaybackController play:&error] ) {
            [self onError:error];
        }
    });
}

#pragma mark - audio session events

- (void)audioSessionInterruptionWithNote:(NSNotification *)note {
    dispatch_async(_mQueue, ^{
        switch ( (AVAudioSessionInterruptionType)[note.userInfo[AVAudioSessionInterruptionTypeKey] integerValue] ) {
            case AVAudioSessionInterruptionTypeBegan: {
                if ( self->_mPlayWhenReady.load(std::__1::memory_order_relaxed) ) {
                    [self _onPause:SJPlayWhenReadyChangeReasonAudioSessionInterrupted];
                }
            }
                break;
            case AVAudioSessionInterruptionTypeEnded: {
                AVAudioSessionInterruptionOptions options = [note.userInfo[AVAudioSessionInterruptionOptionKey] integerValue];
                if ( self->_mPlaybackWhenReadyChangeReason == SJPlayWhenReadyChangeReasonAudioSessionInterrupted ) {
                    if ( options == AVAudioSessionInterruptionOptionShouldResume ) {
                        [self _onPlay:SJPlayWhenReadyChangeReasonAudioSessionInterruptionEnded];
                    }
                    else {
                        [self setPlayWhenReady:false changeReason:SJPlayWhenReadyChangeReasonAudioSessionInterruptionEnded];
                    }
                }
            }
                break;
        }
    });
}

- (void)audioSessionRouteChangeWithNote:(NSNotification *)note {
    dispatch_async(_mQueue, ^{
        NSDictionary *info = note.userInfo;
        AVAudioSessionRouteChangeReason reason = (AVAudioSessionRouteChangeReason)[[info valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
        if      ( reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable ) {
            if ( self->_mPlayWhenReady.load(std::__1::memory_order_relaxed) ) {
                [self _onPause:SJPlayWhenReadyChangeReasonOldDeviceUnavailable];
            }
        }
        else if ( reason == AVAudioSessionRouteChangeReasonNewDeviceAvailable ) {
            
        }
    });
}
@end

@implementation SJAudioPlayer (FFAVAudioSessionExtended)
- (void)setCategory:(AVAudioSessionCategory)category withOptions:(AVAudioSessionCategoryOptions)options {
    _mCategory = category;
    _mCategoryOptions = options;
}

- (void)setActiveOptions:(AVAudioSessionSetActiveOptions)options {
    _mSetActiveOptions = options;
}
@end

@implementation SJAudioPlayerOptions
- (instancetype)initWithStartTimePosition:(CMTime)startTimePosition {
    return [self initWithStartTimePosition:startTimePosition playableDurationLimit:kCMTimeZero];
}

- (instancetype)initWithStartTimePosition:(CMTime)startTimePosition playableDurationLimit:(CMTime)playableDurationLimit {
    self = [super init];
    _startTimePosition = startTimePosition;
    _playableDurationLimit = playableDurationLimit;
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    SJAudioPlayerOptions *options = [SJAudioPlayerOptions.alloc init];
    options.startTimePosition = _startTimePosition;
    options.playableDurationLimit = _playableDurationLimit;
    return options;
}
@end
