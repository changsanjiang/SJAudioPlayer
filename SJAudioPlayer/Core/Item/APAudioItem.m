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

typedef NS_ENUM(NSUInteger, APAudioItemInnerStatus) {
    APAudioItemInnerStatusSuspend,
    APAudioItemInnerStatusRunning,
};

@interface APAudioItem ()<APAudioContentParserDelegate> {
    dispatch_queue_t _queue;
    NSURL *_URL;
    id<APAudioOptions>_Nullable _options;
    APAudioContentParser *_Nullable _parser;
    APAudioContentConverter *_Nullable _converter;
    NSMutableArray<id<APAudioContentPacket>> *_Nullable _packetBuffer;
    BOOL _isPrepared;
    APAudioItemInnerStatus _innerStatus;
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
    _innerStatus = APAudioItemInnerStatusRunning;
    [_parser prepare];
}

- (AVAudioFramePosition)startPosition {
    return _parser.startPosition;
}

- (void)seekToTime:(NSTimeInterval)time {
    _error = nil;
    _innerStatus = APAudioItemInnerStatusRunning;
    [_packetBuffer removeAllObjects];
    [_parser seekToTime:time];
}

- (void)suspend{
    switch ( _innerStatus ) {
        case APAudioItemInnerStatusSuspend:
            break;
        case APAudioItemInnerStatusRunning: {
            _innerStatus = APAudioItemInnerStatusSuspend;
            [_parser suspend];
        }
            break;
    }
}

- (void)resume {
    switch ( _innerStatus ) {
        case APAudioItemInnerStatusSuspend: {
            _innerStatus = APAudioItemInnerStatusRunning;
            [_parser resume];
            [self _convertPacketsToPCMBufferRecursively];
        }
            break;
        case APAudioItemInnerStatusRunning:
            break;
    }
}

- (void)retry {
    _error = nil;
    _innerStatus = APAudioItemInnerStatusRunning;
    [_packetBuffer removeAllObjects];
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
    if ( _packetBuffer == nil )
        _packetBuffer = [NSMutableArray arrayWithCapacity:packets.count];
    [_packetBuffer addObjectsFromArray:packets];
    [self _convertPacketsToPCMBufferRecursively];
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

- (void)_convertPacketsToPCMBufferRecursively {
    if ( _innerStatus != APAudioItemInnerStatusRunning )
        return;
    
    if ( _packetBuffer.count == 0 )
        return;
    
    if ( _converter == nil )
        _converter = [APAudioContentConverter.alloc initWithStreamFormat:_parser.contentFormat];

    NSMutableArray<id<APAudioContentPacket>> *m = NSMutableArray.array;
    UInt64 length = 0;
    BOOL isFull = NO;
    for ( id<APAudioContentPacket> packet in _packetBuffer ) {
        UInt64 packetLength = packet.data.length;
        isFull = (length + packetLength) > _options.maximumCountOfBytesPerPCMBufferPackets;
        if ( isFull )
            break;
        [m addObject:packet];
        packetLength += packet.data.length;
    }
    
    if ( isFull || _parser.isReachedEndPosition || _parser.isReachedMaximumPlayableDurationPosition ) {
        [_packetBuffer removeObjectsInRange:NSMakeRange(0, m.count)];
        
        // 转换为PCMBuffer
        NSError *error = nil;
        AVAudioPCMBuffer *buffer = [_converter convertPackets:m error:&error];
        if ( error != nil ) {
            [self _onError:error];
            return;
        }
        
        [_delegate audioItem:self newBufferAvailable:buffer];
        [self _convertPacketsToPCMBufferRecursively];
    }
}
@end
