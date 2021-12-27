//
//  APAudioContentParser.m
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/13.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APAudioContentParser.h"
#import "APAudioContentPacket.h"
#import "APAudioContentReader.h"
#import "APAudioStreamParser.h"
#import "APError.h"
 
@interface APAudioContentParser ()<APAudioContentReaderDelegate> {
    APAudioContentReader *_reader;
    dispatch_queue_t _queue;
    BOOL _isPrepared;
    NSURL *_URL;
    APAudioStreamParser *_parser;
    BOOL _isFoundFormat;
    BOOL _isDiscontinuous;
    id<APAudioOptions> _options;
}

@property (nonatomic, strong, nullable) AVAudioFormat *contentFormat;
@end

@implementation APAudioContentParser
@synthesize delegate = _delegate;
@synthesize duration = _duration;
@synthesize seekable = _seekable;
@synthesize reachedMaximumPlayableDurationPosition = _reachedMaximumPlayableDurationPosition;
@synthesize reachedEndPosition = _reachedEndPosition;
@synthesize maximumPlayableDuration = _maximumPlayableDuration;
@synthesize startPosition = _startPosition;

- (instancetype)initWithURL:(NSURL *)URL options:(nullable id<APAudioOptions>)options delegate:(id<APAudioContentParserDelegate>)delegate queue:(dispatch_queue_t)queue {
    self = [super init];
    if ( self ) {
        _URL = URL;
        _options = options;
        _delegate = delegate;
        _queue = queue;
    }
    return self;
}
 
- (nullable AVAudioFormat *)contentFormat {
    return _parser.format;
}

- (float)contentLoadProgress {
    return _reader.contentLoadProgress;
}

- (void)prepare {
    if ( _isPrepared )
        return;
    _isPrepared = YES;
    _maximumPlayableDuration = _options.maximumPlayableDuration;
    _reader = [APAudioContentReader contentReaderWithURL:_URL options:_options delegate:self queue:_queue];
    [_reader resume];
}

- (void)seekToTime:(NSTimeInterval)time {
    //
    // time, packet index, bytes offset 之间的转换
    //
    if ( !_seekable ) {
        return;
    }
    
    NSTimeInterval maxDuration = _maximumPlayableDuration > 0 ? _maximumPlayableDuration : _duration;
    
    if ( time >= maxDuration )
        time = maxDuration * 0.98;
    else if ( time < 0 )
        time = 0;
     
    _isDiscontinuous = YES;
    _reachedEndPosition = NO;
    _reachedMaximumPlayableDurationPosition = NO;
    [_parser removeAllFoundPackets];
    UInt64 nBytesOffset = [self _expectedOffsetForTime:time framePosition:&_startPosition];
    [_reader seekToOffset:nBytesOffset];
}

- (void)suspend {
    [_reader suspend];
}

- (void)resume {
    if ( _reachedMaximumPlayableDurationPosition || self.isReachedEndPosition )
        return;
    [_reader resume];
}

- (void)retry {
    if ( _reachedMaximumPlayableDurationPosition || self.isReachedEndPosition )
        return;
    [_reader retry];
}

- (void)cancelPlayableDurationLimit {
    _maximumPlayableDuration = 0;
    _reachedMaximumPlayableDurationPosition = NO;
}

#pragma mark - APAudioContentReaderDelegate

- (void)contentReader:(id<APAudioContentReader>)reader contentLoadProgressDidChange:(float)progress {
    [_delegate parser:self contentLoadProgressDidChange:progress];
}

- (void)contentReader:(id<APAudioContentReader>)reader hasNewAvailableData:(NSData *)data atOffset:(UInt64)offset {
    if ( _parser == nil ) _parser = APAudioStreamParser.alloc.init;

    BOOL isDiscontinuous = _isDiscontinuous;
    _isDiscontinuous = NO;
    NSError *error = nil;
    if ( ![_parser process:data isDiscontinuous:isDiscontinuous error:&error] ) {
        [self _onError:error];
        return;
    }

    AVAudioFormat *format = _parser.format;
    BOOL isFoundFormat = format != nil;
    // 未解析出文件格式期间, 将不会上报packets
    if ( !isFoundFormat )
        return;

    if ( _isFoundFormat != isFoundFormat ) {
        _isFoundFormat = isFoundFormat;
        [_delegate parser:self foundFormat:format];
        [_delegate parser:self contentLoadProgressDidChange:reader.contentLoadProgress];
    }

    NSArray<id<APAudioContentPacket>> *_Nullable foundPackets = _parser.foundPackets;
    // 数量为0时直接退出
    if ( foundPackets.count == 0 )
        return;
    // 刷新播放时长
    _duration = (reader.countOfBytesTotalLength - _parser.audioDataOffset) / (_parser.bitRate / 8.0);
    _seekable = YES;
    
    if ( _maximumPlayableDuration != 0 ) {
        // 到达时长限制的位置后
        // - 将相交packets上报给代理
        // - 清除相交部分的packets
        UInt64 maxOffset = [self _expectedOffsetForTime:_maximumPlayableDuration framePosition:NULL];
        AVAudioPacketCount maxPos = [self _expectedPacketPositionForOffset:maxOffset];
        AVAudioPacketCount curPos = [self _expectedPacketPositionForOffset:_reader.offset];
        // 确认是否到达时长限制的位置
        _reachedMaximumPlayableDurationPosition = (curPos >= foundPackets.count) && (curPos >= maxPos);
        if ( _reachedMaximumPlayableDurationPosition ) {
            // 停止读取
            [reader stop];
            
            // 删除相交部分的packets, 剩余的packets继续保留
            AVAudioPacketCount startPos = curPos - (AVAudioPacketCount)foundPackets.count;
            if ( startPos < maxPos ) {
                AVAudioPacketCount length = maxPos - startPos;
                NSRange range = NSMakeRange(0, (NSUInteger)length);
                foundPackets = [foundPackets subarrayWithRange:range];
                [_parser removeFoundPacketsInRange:range];
            }
        }
    }
    
    if ( !_reachedMaximumPlayableDurationPosition ) {
        // 确认是否已到达文件结束的位置
        _reachedEndPosition = reader.countOfBytesTotalLength != 0 && reader.offset == reader.countOfBytesTotalLength;
        //  - 清空packets, 以进行下一次解析
        [_parser removeAllFoundPackets];
    }
     
    // report
    [_delegate parser:self foundPackets:foundPackets];
}

- (void)contentReader:(id<APAudioContentReader>)reader anErrorOccurred:(NSError *)error {
    [self _onError:error];
}
 
- (UInt64)_expectedOffsetForTime:(NSTimeInterval)time framePosition:(AVAudioFramePosition *)startPosition {
    UInt64 nBytesOffset = 0;
    Float64 mSampleRate = _parser.format.streamDescription->mSampleRate;
    AVAudioFramePosition allFrames = time * mSampleRate;
    AVAudioFramePosition mFramesPerPacket = _parser.format.streamDescription->mFramesPerPacket;
    AVAudioPacketCount packetPosition = (AVAudioPacketCount)(allFrames * 1.0 / mFramesPerPacket);
    AVAudioFramePosition framePosition = packetPosition * mFramesPerPacket;
    NSTimeInterval t = framePosition / mSampleRate;
    nBytesOffset = _parser.audioDataOffset + t * (_parser.bitRate / 8.0);
    
    if ( startPosition != NULL ) {
        *startPosition = framePosition;
    }
    
    UInt64 countOfBytesTotalLength = _reader.countOfBytesTotalLength;
    if ( nBytesOffset > countOfBytesTotalLength ) {
        nBytesOffset = countOfBytesTotalLength;
    }
    return nBytesOffset;
}

- (AVAudioPacketCount)_expectedPacketPositionForOffset:(UInt64)nBytesOffset {
    if ( nBytesOffset <= _parser.audioDataOffset )
        return 0;
    Float64 mSampleRate = _parser.format.streamDescription->mSampleRate;
    AVAudioFramePosition mFramesPerPacket = _parser.format.streamDescription->mFramesPerPacket;
    NSTimeInterval t = (double)nBytesOffset / (_parser.bitRate / 8.0);
    AVAudioFramePosition allFrames = t * mSampleRate;
    AVAudioPacketCount packetPosition = (AVAudioPacketCount)(allFrames * 1.0 / mFramesPerPacket);
    return packetPosition;
}

- (void)_onError:(NSError *)error {
    [_reader stop];
    [_delegate parser:self anErrorOccurred:error];
}

@end
