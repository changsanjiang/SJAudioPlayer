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
    UInt64 _minimumCountOfBytesFoundPackets;
    NSTimeInterval _maximumPlayableDuration; // 可播放时长限制, 缓冲到达指定时长后, 将停止解析
    BOOL _isFoundFormat;
}

@property (nonatomic, strong, nullable) AVAudioFormat *contentFormat;
@end

@implementation APAudioContentParser
@synthesize delegate = _delegate;
@synthesize duration = _duration;
@synthesize seekable = _seekable;
@synthesize reachedEnd = _reachedEnd;
@synthesize startPosition = _startPosition;

- (instancetype)initWithURL:(NSURL *)URL minimumCountOfBytesFoundPackets:(UInt64)size delegate:(id<APAudioContentParserDelegate>)delegate queue:(dispatch_queue_t)queue {
    self = [super init];
    if ( self ) {
        _URL = URL;
        _minimumCountOfBytesFoundPackets = size;
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
    [self _prepareIfNeeded];
}

- (void)seekToTime:(NSTimeInterval)time {
    //
    // time, packet index, bytes offset 之间的转换
    //
    if ( !_seekable ) {
        return;
    }
    
    if ( time >= _duration )
        time = _duration * 0.98;
    else if ( time < 0 )
        time = 0;
    
    _reachedEnd = NO;
    [_parser clearPackets];
    UInt64 nBytesOffset = [self _offsetForTime:time framePosition:&_startPosition];
    [_reader seekToOffset:nBytesOffset];
}

- (void)suspend {
    [_reader suspend];
}

- (void)resume {
    [_reader resume];
}

- (void)retry {
    [_reader retry];
}

#pragma mark - APAudioContentReaderDelegate

- (void)contentReader:(id<APAudioContentReader>)reader contentLoadProgressDidChange:(float)progress {
    [_delegate parser:self contentLoadProgressDidChange:progress];
}

- (void)contentReader:(id<APAudioContentReader>)reader hasNewAvailableData:(NSData *)data atOffset:(UInt64)offset {
    if ( _parser == nil ) _parser = APAudioStreamParser.alloc.init;
     
    NSError *error = nil;
    if ( ![_parser process:data error:&error] ) {
        [_delegate parser:self anErrorOccurred:error];
        return;
    }
    
    AVAudioFormat *format = _parser.format;
    BOOL isFoundFormat = format != nil;
    // 未解析出文件格式期间, 将不会上报packets
    if ( !isFoundFormat ) {
        return;
    }
    
    if ( _isFoundFormat != isFoundFormat ) {
        _isFoundFormat = isFoundFormat;
        [_delegate parser:self foundFormat:format];
        [_delegate parser:self contentLoadProgressDidChange:reader.contentLoadProgress];
    }

    // 解析出足够的packets后
    //  - 将本此packets上报给代理
    //  - 清空packets, 以进行下一次计数
    //  - 更新播放时长
    _reachedEnd = reader.offset == reader.countOfBytesTotalLength; /* EOF */
    if ( _parser.countOfBytesFoundPackets >= _minimumCountOfBytesFoundPackets || _reachedEnd ) {
        // 有足够数量的packets之后, 刷新一下播放时长
        _duration = (reader.countOfBytesTotalLength - _parser.audioDataOffset) / (_parser.bitRate / 8.0);
        _seekable = YES;
        
        NSArray<id<APAudioContentPacket>> *foundPackets = _parser.foundPackets;
        // clean
        [_parser clearPackets];
        // report
        [_delegate parser:self foundPackets:foundPackets];
    }
}

- (void)contentReader:(id<APAudioContentReader>)reader anErrorOccurred:(NSError *)error {
    [_delegate parser:self anErrorOccurred:error];
}

#pragma mark - mark

- (void)_prepareIfNeeded {
    if ( _isPrepared )
        return;
    _isPrepared = YES;
    
    _reader = [APAudioContentReader contentReaderWithURL:_URL delegate:self queue:_queue];
    [_reader resume];
}

- (UInt64)_offsetForTime:(NSTimeInterval)time framePosition:(AVAudioFramePosition *)startPosition {
    UInt64 nBytesOffset = 0;
    BOOL isEstimated = NO;
    Float64 mSampleRate = _parser.format.streamDescription->mSampleRate;
    AVAudioFramePosition allFrames = time * mSampleRate;
    AVAudioFramePosition mFramesPerPacket = _parser.format.streamDescription->mFramesPerPacket;
    AVAudioPacketCount packetPosition = (AVAudioPacketCount)(allFrames * 1.0 / mFramesPerPacket);
    AVAudioFramePosition framePosition = packetPosition * mFramesPerPacket;
    if ( [_parser offsetAtPacket:packetPosition outOffset:&nBytesOffset isEstimated:&isEstimated] && !isEstimated ) {
        // nBytesOffset available
    }
    else {
        NSTimeInterval t = framePosition / mSampleRate;
        nBytesOffset = _parser.audioDataOffset + t * (_parser.bitRate / 8.0);
    }
    
    if ( startPosition != NULL ) {
        *startPosition = framePosition;
    }
    return nBytesOffset;
}
@end
