//
//  SJAudioPlaybackController.m
//  LWZFFmpegLib
//
//  Created by db on 2025/4/16.
//

#import "SJAudioPlaybackController.h"

typedef NS_ENUM(NSUInteger, SJAudioPlaybackAction) {
    SJAudioPlaybackActionUnknown,
    SJAudioPlaybackActionReset,
    SJAudioPlaybackActionPlay,
    SJAudioPlaybackActionPause,
    SJAudioPlaybackActionStop,
};

@implementation SJAudioPlaybackController {
    AVAudioEngine *mEngine;
    AVAudioSourceNode *mAudioSourceNode;
    AVAudioUnitTimePitch *mRateNode;
    AVAudioMixerNode *mOutputVolumeNode;
    AVAudioFormat *mOutputFormat;
    SJAudioPlaybackAction mLastAction;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _rate = 1.0;
        _volume = 1.0;
        // fltp, 44100, 2
        mOutputFormat = [AVAudioFormat.alloc initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:44100 channels:2 interleaved:NO];
        
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioEngineConfigurationChangeWithNote:) name:AVAudioEngineConfigurationChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
#ifdef DEBUG
    NSLog(@"%@<%p>: %d : %s", NSStringFromClass(self.class), self, __LINE__, sel_getName(_cmd));
#endif

    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)setRate:(float)rate {
    _rate = rate;
    if ( mRateNode ) mRateNode.rate = rate;
}

- (void)setVolume:(float)volume {
    _volume = volume;
    if ( mOutputVolumeNode ) mOutputVolumeNode.outputVolume = _mute ? 0 : volume;
}

- (void)setMute:(BOOL)mute {
    _mute = mute;
    if ( mOutputVolumeNode ) mOutputVolumeNode.outputVolume = mute ? 0 : _volume;
}

- (BOOL)play:(NSError **)error {
    if ( mLastAction == SJAudioPlaybackActionPlay ) {
        return YES;
    }
    
    @try {
        if ( !mEngine && ![self reset:error] ) {
            return NO;
        }
        
        NSError *err = nil;
        if ( !mEngine.isRunning && ![mEngine startAndReturnError:&err] ) {
            if ( error ) *error = [NSError errorWithDomain:SJAudioPlaybackControllerErrorDomain code:-1 userInfo:@{
                NSLocalizedDescriptionKey: err.description
             }];
            return NO;
        }
        
        mLastAction = SJAudioPlaybackActionPlay;
        return YES;
    } @catch (NSException *exception) {
        if ( error ) *error = [NSError errorWithDomain:SJAudioPlaybackControllerErrorDomain code:-1 userInfo:@{
           NSLocalizedDescriptionKey: exception.description
        }];
        return NO;
    }
}

- (BOOL)pause:(NSError **)error {
    if ( mLastAction == SJAudioPlaybackActionPause ) {
        return YES;
    }
    
    @try {
        if ( mEngine ) {
            [mEngine pause];
        }
        mLastAction = SJAudioPlaybackActionPause;
        return YES;
    } @catch (NSException *exception) {
        if ( error ) *error = [NSError errorWithDomain:SJAudioPlaybackControllerErrorDomain code:-1 userInfo:@{
           NSLocalizedDescriptionKey: exception.description
        }];
        return NO;
    }
}

// stop all nodes
- (BOOL)stop:(NSError **)error {
    if ( mLastAction == SJAudioPlaybackActionStop ) {
        return YES;
    }
    
    @try {
        if ( mEngine ) {
            [mEngine stop];
        }
        mLastAction = SJAudioPlaybackActionStop;
        return YES;
    } @catch (NSException *exception) {
        if ( error ) *error = [NSError errorWithDomain:SJAudioPlaybackControllerErrorDomain code:-1 userInfo:@{
           NSLocalizedDescriptionKey: exception.description
        }];
        return NO;
    }
}

// rest all nodes, 重新创建engine, 一般在播放报错需要重置时调用;
- (BOOL)reset:(NSError **)error {
    if ( mLastAction == SJAudioPlaybackActionReset ) {
        return YES;
    }
    
    [self stop:nullptr];
    
    @try {
        mEngine = [AVAudioEngine.alloc init];
        mRateNode = [AVAudioUnitTimePitch.alloc init];
        mOutputVolumeNode = [AVAudioMixerNode.alloc init];
        __weak typeof(self) _self = self;
        mAudioSourceNode = [AVAudioSourceNode.alloc initWithFormat:mOutputFormat renderBlock:^OSStatus(BOOL * _Nonnull isSilence, const AudioTimeStamp * _Nonnull timestamp, AVAudioFrameCount frameCount, AudioBufferList * _Nonnull outputData) {
            __strong typeof(_self) self = _self;
            int64_t pts = 0;
            self->_renderBlock(isSilence, frameCount, outputData, &pts);
            return noErr;
        }];
        
        [mEngine attachNode:mAudioSourceNode];
        [mEngine attachNode:mRateNode];
        [mEngine attachNode:mOutputVolumeNode];
        
        [mEngine connect:mAudioSourceNode to:mRateNode format:mOutputFormat];
        [mEngine connect:mRateNode to:mOutputVolumeNode format:mOutputFormat];
        [mEngine connect:mOutputVolumeNode to:mEngine.mainMixerNode format:mOutputFormat];
        
        mRateNode.rate = _rate;
        mOutputVolumeNode.outputVolume = _mute ? 0 : _volume;
        
        [mEngine prepare];
        mLastAction = SJAudioPlaybackActionReset;
        return YES;
    } @catch (NSException *exception) {
        if ( error ) *error = [NSError errorWithDomain:SJAudioPlaybackControllerErrorDomain code:-1 userInfo:@{
           NSLocalizedDescriptionKey: exception.description
        }];
        return NO;
    }
}

#pragma mark - mark

- (void)audioEngineConfigurationChangeWithNote:(NSNotification *)note {
    if ( note.object == mEngine && self.audioEngineConfigurationChangeHandler ) {
        self.audioEngineConfigurationChangeHandler(self);
    }
}
@end
