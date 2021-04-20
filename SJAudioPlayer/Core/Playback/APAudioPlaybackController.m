//
//  APAudioPlaybackController.m
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/14.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APAudioPlaybackController.h"
#import "APError.h"
#import "AVAudioPlayerNode+AP.h"

@interface APAudioPlaybackController () {
    AVAudioEngine *_engine;
    AVAudioPlayerNode *_playerNode;
    AVAudioUnitTimePitch *_rateNode;
    AVAudioMixerNode *_outputVolumeNode;
    AVAudioFramePosition _lastPosition;
    BOOL _isPrepared;
}
@end

@implementation APAudioPlaybackController
@synthesize rate = _rate;
@synthesize volume = _volume;
@synthesize muted = _muted;
@synthesize frameLengthInBuffers = _frameLengthInBuffers;

- (instancetype)init {
    self = [super init];
    if (self) {
        _rate = 1.0;
        _volume = 1.0;
        _engine = AVAudioEngine.alloc.init;
    }
    return self;
}

- (AVAudioEngine *)engine {
    return _engine;
}

- (AVAudioFramePosition)lastPosition {
    if ( _playerNode.ap_isPlaying ) {
        _lastPosition = [_playerNode ap_currentFramePosition];
    }
    return _lastPosition;
}

- (void)setRate:(float)rate {
    _rate = rate;
    if ( _rateNode != nil )
        _rateNode.rate = rate;
}

- (void)setVolume:(float)volume {
    _volume = volume;
    if ( _outputVolumeNode != nil )
        _outputVolumeNode.outputVolume = _muted ? 0 : volume;
}

- (void)setMuted:(BOOL)muted {
    _muted = muted;
    if ( _outputVolumeNode != nil )
        _outputVolumeNode.outputVolume = muted ? 0 : _volume;
}

- (void)scheduleBuffer:(AVAudioPCMBuffer *)buffer atOffset:(AVAudioFramePosition)offset completionHandler:(AVAudioNodeCompletionHandler)completionHandler {
    [self _prepareToPlay];
    [_playerNode scheduleBuffer:buffer completionHandler:completionHandler];
    _frameLengthInBuffers += buffer.frameLength;
}

- (BOOL)play:(NSError **)error {
    [self _prepareToPlay];
    if ( ![self _startEngine:error] ) {
        return NO;
    }
    
    [_playerNode play];
    return YES;
}

- (void)pause {
    if ( _playerNode.ap_isPlaying ) {
        _lastPosition = [_playerNode ap_currentFramePosition];
    }
    [_playerNode pause];
    [_engine pause];
}

- (void)stop {
    [_playerNode stop];
    [_engine stop];
    _frameLengthInBuffers = 0;
}

- (void)reset {
    [self stop];
    _lastPosition = 0;
}

#pragma mark - mark

- (void)_prepareToPlay {
    if ( _isPrepared )
        return;
    _isPrepared = YES;
    _playerNode = AVAudioPlayerNode.alloc.init;
    _rateNode = AVAudioUnitTimePitch.alloc.init;
    _rateNode.rate = _rate;
    _outputVolumeNode = AVAudioMixerNode.alloc.init;
    _outputVolumeNode.outputVolume = _muted ? 0 : _volume;
    
    [_engine attachNode:_outputVolumeNode];
    [_engine attachNode:_rateNode];
    [_engine attachNode:_playerNode];
    
    [_engine connect:_rateNode to:_engine.mainMixerNode format:nil];
    [_engine connect:_outputVolumeNode to:_rateNode format:nil];
    [_engine connect:_playerNode to:_outputVolumeNode format:nil];
}

- (BOOL)_startEngine:(NSError **)outError {
    if ( !_engine.isRunning ) {
        NSError *innerError = nil;
        @try {
            if ( ![_engine startAndReturnError:&innerError] ) {
                if ( outError != NULL ) {
                    *outError = [NSError ap_errorWithCode:APAudioEngineErrorUnableToStartEngine userInfo:@{
                        APErrorUserInfoErrorKey : innerError,
                        APErrorUserInfoAudioEngineKey : _engine,
                        NSLocalizedDescriptionKey : APErrorLocalizedDescription(APAudioEngineErrorUnableToStartEngine),
                    }];
                }
                return NO;
            }
        } @catch (NSException *exception) {
            if ( outError != NULL ) {
                *outError = [NSError ap_errorWithCode:APAudioEngineErrorThrowException userInfo:@{
                    APErrorUserInfoExceptionKey : exception,
                    APErrorUserInfoAudioEngineKey : _engine,
                    NSLocalizedDescriptionKey : APErrorLocalizedDescription(APAudioEngineErrorThrowException),
                }];
            }
            return NO;
        }
    }
    return YES;
}

@end
