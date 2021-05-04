//
//  APAudioItem.m
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/14.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APAudioItem.h"
#import "APAudioContentParser.h"
#import "APAudioContentConverter.h"

@interface APAudioItem ()<APAudioContentParserDelegate> {
    dispatch_queue_t _queue;
    NSURL *_URL;
    id<APAudioOptions>_Nullable _options;
    APAudioContentParser *_parser;
    APAudioContentConverter *_converter;
    BOOL _isPrepared;
}
@end
  
@implementation APAudioItem
@synthesize delegate = _delegate;
@synthesize error = _error;
- (instancetype)initWithURL:(NSURL *)URL options:(nullable id<APAudioOptions>)options delegate:(id<APAudioItemDelegate>)delegate queue:(dispatch_queue_t)queue {
    self = [super init];
    if ( self ) {
        _URL = URL;
        _options = options;
        _delegate = delegate;
        _queue = queue;
    }
    return self;
}

- (APAudioItemStatus)status {
    if ( _error != nil )
        return APAudioItemStatusFailed;
    if ( _parser.isSeekable )
        return APAudioItemStatusReadyToPlay;
    return APAudioItemStatusUnknown;
}

- (BOOL)isReachedEndPosition {
    return _parser.isReachedEndPosition;
}

- (BOOL)isReachedMaximumPlayableDurationPosition {
    return _parser.isReachedMaximumPlayableDurationPosition;
}

- (nullable AVAudioFormat *)contentFormat {
    return _converter.streamFormat;
}

- (float)contentLoadProgress {
    return _parser.contentLoadProgress;
}

- (nullable AVAudioFormat *)outputFormat {
    return _converter.outputFormat;
}

- (NSTimeInterval)duration {
    return _parser.duration;
}

- (void)prepare {
    if ( _isPrepared  )
        return;
    _isPrepared = YES;
    
    _parser = [APAudioContentParser.alloc initWithURL:_URL options:_options delegate:self queue:_queue];
    [_parser prepare];
}

- (AVAudioFramePosition)startPosition {
    return _parser.startPosition;
}

- (void)seekToTime:(NSTimeInterval)time {
    [_parser seekToTime:time];
}

- (void)suspend{
    [_parser suspend];
}

- (void)resume {
    [_parser resume];
}

- (void)retry {
    _error = nil;
    [_parser retry];
}

- (void)cancelPlayableDurationLimit {
    [_parser cancelPlayableDurationLimit];
}

#pragma mark - APAudioContentParserDelegate

- (void)parser:(id<APAudioContentParser>)parser foundFormat:(AVAudioFormat *)format {
    [_delegate audioItem:self didLoadFormat:format];
}

- (void)parser:(id<APAudioContentParser>)parser foundPackets:(NSArray<id<APAudioContentPacket>> *)packets {
    if ( _converter == nil ) {
        _converter = [APAudioContentConverter.alloc initWithStreamFormat:_parser.contentFormat];
    }
    
    // 转换为PCMBuffer
    NSError *error = nil;
    AVAudioPCMBuffer *buffer = [_converter convertPackets:packets error:&error];
    if ( error != nil ) {
        [self _onError:error];
        return;
    }
    
    [_delegate audioItem:self newBufferAvailable:buffer];
}

- (void)parser:(id<APAudioContentParser>)parser contentLoadProgressDidChange:(float)progress {
    [_delegate audioItem:self contentLoadProgressDidChange:progress];
}

- (void)parser:(id<APAudioContentParser>)parser anErrorOccurred:(NSError *)error {
    [self _onError:error];
}

- (void)_onError:(NSError *)error {
    _error = error;
    [_delegate audioItem:self anErrorOccurred:error];
}
@end
