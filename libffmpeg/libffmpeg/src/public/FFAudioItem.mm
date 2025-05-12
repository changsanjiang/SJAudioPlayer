//
//  FFAudioItem.m
//  LWZFFmpegLib
//
//  Created by db on 2025/4/14.
//

#import "FFAudioItem.h"
#import "FFCoreAudioReader.h"
#import "FFCoreAudioTranscoder.h"
#include <mutex>

NSErrorDomain const FFAudioItemErrorDomain = @"FFAudioItemErrorDomain";

@interface FFAudioItem ()<FFCoreAudioReaderDelegate>

@end

@implementation FFAudioItem {
    NSURL *mURL;
    NSError *mError;

    CMTime mDuration;

    int64_t mStartTimePosition; // in base q
    
    std::atomic<bool> mReadyToRead;
    std::atomic<CMTimeRange> mPlayableTimeRange;
    
    BOOL mHasError;
    BOOL mSeeking; // seeking 的时候会停止接收pkt和转码操作, 等待seek操作完成后继续;
    
    BOOL mShouldReprepareReader;
    BOOL mSeekedBeforeReprepareReader;
    BOOL mShouldOnlyFlushPackets; // flush 时是否仅清空 packets 的缓存
    
    std::mutex mtx;
    
    FFCoreAudioReader *mAudioReader;
    FFCoreAudioTranscoder *mAudioTranscoder;
}

- (instancetype)initWithURL:(NSURL *)URL options:(nullable FFAudioItemOptions *)options delegate:(id<FFAudioItemDelegate>)delegate {
    self = [super init];
    mURL = URL;
    _delegate = delegate;
    
    mDuration = kCMTimeZero;
    
    mReadyToRead.store(false, std::__1::memory_order_relaxed);
    mPlayableTimeRange.store(kCMTimeRangeZero, std::__1::memory_order_relaxed);
    
    mAudioReader = [FFCoreAudioReader.alloc initWithURL:URL delegate:self];
    
    mAudioTranscoder = [FFCoreAudioTranscoder.alloc init];
    
    int64_t startTimePosition = AV_NOPTS_VALUE;
    if ( options && CMTimeCompare(options.startTimePosition, kCMTimeZero) ) {
        startTimePosition = av_rescale_q(options.startTimePosition.value, (AVRational){ 1, options.startTimePosition.timescale }, AV_TIME_BASE_Q);
    }
    mStartTimePosition = startTimePosition;
    [mAudioReader prepareWithStartTimePosition:startTimePosition];
    return self;
}

- (void)dealloc {
#ifdef DEBUG
    NSLog(@"%@<%p>: %d : %s", NSStringFromClass(self.class), self, __LINE__, sel_getName(_cmd));
#endif
    
    [mAudioReader stop];
    mAudioReader = nil;
    mAudioTranscoder = nil;
}

- (BOOL)isReadyToRead {
    return mReadyToRead.load(std::__1::memory_order_relaxed);
}

- (CMTime)duration {
    return mReadyToRead.load(std::__1::memory_order_relaxed) ? mDuration : kCMTimeZero;
}

- (CMTimeRange)playableTimeRange {
    return mPlayableTimeRange.load(std::__1::memory_order_relaxed);
}

- (AVAudioFormat *)outputFormat {
    return mAudioTranscoder.outputFormat;
}

- (NSError *)error {
    std::lock_guard<std::mutex> lock(mtx);
    return mError;
}

- (void)seekToTime:(CMTime)time {
    std::lock_guard<std::mutex> lock(mtx);
    if ( !mReadyToRead.load(std::__1::memory_order_relaxed) || mHasError ) {
        return;
    }
    
    mSeeking = true;
    
    int64_t seekTime = av_rescale_q(time.value, (AVRational){ 1, time.timescale }, AV_TIME_BASE_Q);
    if ( mShouldReprepareReader ) {
        mSeekedBeforeReprepareReader = true;
        mShouldOnlyFlushPackets = false;
        mStartTimePosition = seekTime; // 修改 startTimePos 为 seekTime;
        [self _reprepareReaderWithStartTimePosition:mStartTimePosition];
        return;
    }
    
    [mAudioReader seekToTime:seekTime];
}

#pragma mark - FFCoreAudioReaderDelegate

- (void)audioReader:(FFCoreAudioReader *)reader readyToReadStream:(AVStream *)audio {
    std::unique_lock<std::mutex> lock(mtx);
    // reprepared
    if ( mReadyToRead.load(std::__1::memory_order_relaxed) ) {
        mSeekedBeforeReprepareReader = false;
        [reader start];
        return;
    }
    
    int ff_ret = [mAudioTranscoder prepareByAudioStream:audio];
    if ( ff_ret < 0 ) {
        goto on_exit;
    }
    
    // ready
    mDuration = CMTimeMake(audio->duration * audio->time_base.num, audio->time_base.den);
    mReadyToRead.store(true, std::__1::memory_order_relaxed);
    [mAudioReader start];
    
on_exit:
    NSError *error = nil;
    if ( ff_ret != 0 ) {
        error = [self _makeError:ff_ret];
        mError = error;
    }
    
    lock.unlock();
    
    if ( error ) {
        [_delegate audioItem:self anErrorOccurred:error];
        return;
    }
    
    [_delegate audioItemDidReadyToRead:self];
}

- (void)audioReader:(FFCoreAudioReader *)reader anErrorOccurred:(int)ff_err {
    std::unique_lock<std::mutex> lock(mtx);
    if ( ff_err == AVERROR(EIO) ||
         ff_err == AVERROR(ENETDOWN) ||
         ff_err == AVERROR(ENETUNREACH) ||
         ff_err == AVERROR(ENETRESET) ||
         ff_err == AVERROR(ECONNABORTED) ||
         ff_err == AVERROR(ECONNRESET) ||
         ff_err == AVERROR(ETIMEDOUT) ||
         ff_err == AVERROR(EHOSTUNREACH) ||
         ff_err == AVERROR_HTTP_SERVER_ERROR ||
         ff_err == AVERROR_INVALIDDATA
        ) {
        // 遇到可恢复的错误时重置reader并重新准备
        [self _setNeedsReprepareReader];
        return;
    }
    
    NSError *error = [self _makeError:ff_err];
    mError = error;
    [mAudioReader stop];
    lock.unlock();
    [_delegate audioItem:self anErrorOccurred:error];
}

- (void)audioReader:(FFCoreAudioReader *)reader didReadPacket:(AVPacket *_Nullable)packet shouldFlush:(BOOL)shouldFlush {
    std::unique_lock<std::mutex> lock(mtx);
    
    if ( shouldFlush ) {
        mSeeking = false;
        mSeekedBeforeReprepareReader = false;
    }

    // return if seeking
    if ( mSeeking ) {
        return;
    }

    CMTimeRange timeRange = kCMTimeRangeZero;
    
    // push pkt
    int ff_ret = 0;
    if ( mShouldOnlyFlushPackets ) {
        ff_ret = [mAudioTranscoder pushPacket:packet shouldOnlyFlushPackets:YES];
        mShouldOnlyFlushPackets = false;
    }
    else {
        ff_ret = [mAudioTranscoder pushPacket:packet shouldFlush:shouldFlush];
    }
    
    if ( ff_ret < 0 ) {
        goto on_exit;
    }
    
    if ( mAudioTranscoder.isPacketBufferFull ) {
        mAudioReader.packetBufferFull = true;
    }
    
    // update time range
    timeRange = mAudioTranscoder.timeRange;
    mPlayableTimeRange.store(timeRange, std::__1::memory_order_relaxed);
    
on_exit:
    NSError *error = nil;
    if ( ff_ret != 0 ) {
        error = [self _makeError:ff_ret];
        mError = error;
        [mAudioReader stop];
    }
    
    lock.unlock();
    
    if ( error ) {
        [_delegate audioItem:self anErrorOccurred:error];
        return;
    }
    
    [_delegate audioItem:self playableTimeRangeDidChange:timeRange];
    
    if ( shouldFlush ) {
        [_delegate audioItemDidSeek:self];
    }
}

- (int)tryTranscodeWithFrameCapacity:(int)frameCapacity data:(void *_Nonnull*_Nonnull)outData pts:(int64_t *)outPts eof:(BOOL *)outEOF error:(NSError **)outError {
    if ( !mReadyToRead.load(std::__1::memory_order_relaxed) || mSeeking ) {
        return 0;
    }
    
    std::unique_lock<std::mutex> lock(mtx);
    int ret = [mAudioTranscoder tryTranscodeWithFrameCapacity:frameCapacity data:outData pts:outPts eof:outEOF];
    if ( ret < 0 ) {
        NSError *error = [self _makeError:ret];
        if ( outError ) {
            *outError = error;
        }
    }
    
    if ( !mAudioTranscoder.isPacketBufferFull ) {
        [mAudioReader setPacketBufferFull:NO];
    }
    return ret;
}

#pragma mark - mark

- (NSError *)_makeError:(int)ff_err {
    return [NSError errorWithDomain:FFAudioItemErrorDomain code:-1 userInfo:@{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%s", av_err2str(ff_err)]
    }];
}

- (void)_setNeedsReprepareReader {
    mShouldReprepareReader = true;
    __weak typeof(self) _self = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
        __strong typeof(_self) self = _self;
        if ( self == nil ) return;
        [self _reprepareReaderIfNeeded];
    });
}

- (void)_reprepareReaderIfNeeded {
    std::lock_guard<std::mutex> lock(mtx);
    if ( mShouldReprepareReader ) {
        // 遇到可恢复的错误时重新创建 reader
        // 例如网络不通时延迟n秒后重试
        // 如果之前未完成初始化, 则直接重新创建 reader 即可;
        // 如果已完成初始化, 则需要考虑读取的开始位置;
        // - 等待期间用户可能调用seek, 需要从seek的位置开始播放(模糊位置)
        // - 如果未执行seek操作, 则需要从当前位置开始播放(精确位置), 需要在解码时对齐数据
        if ( !mReadyToRead || mSeekedBeforeReprepareReader ) {
            [self _reprepareReaderWithStartTimePosition:mStartTimePosition];
            return;
        }
        
        // - 如果未执行seek操作, 则需要从当前位置开始播放(精确位置), 需要在解码时对齐数据
        CMTime endPts = mAudioTranscoder.fifoEndPts;
        int64_t startTimePosition = CMTIME_IS_INVALID(endPts) ? 0 : av_rescale_q(endPts.value, (AVRational){ 1, endPts.timescale }, AV_TIME_BASE_Q);
        
        // 需要保留 fifo 中的缓存, 并且新的数据需要对齐到 fifo 中;
        mShouldOnlyFlushPackets = true;
        [self _reprepareReaderWithStartTimePosition:startTimePosition];
    }
}

- (void)_reprepareReaderWithStartTimePosition:(int64_t)startTimePosition {
    mShouldReprepareReader = false;
    mError = nil;
    [mAudioReader reset];
    [mAudioReader prepareWithStartTimePosition:startTimePosition];
}
@end


@implementation FFAudioItemOptions
- (instancetype)init {
    self = [super init];
    _startTimePosition = kCMTimeZero;
    return self;
}
@end
