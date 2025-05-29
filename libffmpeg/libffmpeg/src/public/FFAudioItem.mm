//
//  FFAudioItem.m
//  LWZFFmpegLib
//
//  Created by db on 2025/4/14.
//

#import "FFAudioItem.h"
#import "ff_audio_item.hpp"
#import "FFCoreFormat.hpp"
#include <mutex>

NSErrorDomain const FFAudioItemErrorDomain = @"FFAudioItemErrorDomain";

@interface FFAudioItem ()

@end

@implementation FFAudioItem {
    NSError *mError;

    CMTime mDuration;
    std::atomic<bool> mReadyToRead;
    std::atomic<CMTime> mBufferedTime;
    
    std::mutex mtx;
    
    FFAV::AudioItem *mAudioItem;
    AVAudioFormat *mOutputAudioFormat;
}

- (instancetype)initWithURL:(NSURL *)resURL options:(nullable FFAudioItemOptions *)options delegate:(id<FFAudioItemDelegate>)delegate {
    self = [super init];
    _delegate = delegate;
    mDuration = kCMTimeZero;
    mReadyToRead.store(false, std::__1::memory_order_relaxed);
    mBufferedTime.store(kCMTimeZero, std::__1::memory_order_relaxed);
    
    mOutputAudioFormat = [AVAudioFormat.alloc initWithCommonFormat:FFCoreFormat::FF_OUTPUT_AUDIO_COMMON_FORMAT
                                                        sampleRate:FFCoreFormat::FF_OUTPUT_SAMPLE_RATE
                                                          channels:FFCoreFormat::FF_OUTPUT_CHANNELS
                                                       interleaved:FFCoreFormat::FF_OUTOUT_INTERLEAVED];
    int64_t startTimePos = 0;
    if ( options && CMTIME_IS_VALID(options.startTimePosition) && CMTimeCompare(options.startTimePosition, kCMTimeZero) > 0) {
        startTimePos = CMTimeConvertScale(options.startTimePosition, AV_TIME_BASE, kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
    }
    FFAV::AudioItem::Options opts;
    opts.start_time_pos = startTimePos;
    opts.output_sample_rate = FFCoreFormat::FF_OUTPUT_SAMPLE_RATE;
    opts.output_sample_format = FFCoreFormat::FF_OUTPUT_SAMPLE_FORMAT;
    opts.output_channels = FFCoreFormat::FF_OUTPUT_CHANNELS;
    
    NSString *url = resURL.isFileURL ? resURL.path : resURL.absoluteString;
    mAudioItem = new FFAV::AudioItem(url.UTF8String, opts);
    
    __weak typeof(self) _self = self;
    mAudioItem->setStreamReadyCallback([_self](int64_t duration, AVRational timeBase) {
        [_self onStreamReadyWithDuration:duration timeBase:timeBase];
    });
    mAudioItem->setBufferedTimeChangeCallback([_self](int64_t bufferedTime, AVRational timeBase) {
        [_self onBufferedTimeChange:bufferedTime timeBase:timeBase];
    });
    mAudioItem->setErrorCallback([_self](int ffErr) {
        [_self onError:ffErr];
    });
    
    mAudioItem->prepare();
    return self;
}

- (void)dealloc {
#ifdef DEBUG
    NSLog(@"%@<%p>: %d : %s", NSStringFromClass(self.class), self, __LINE__, sel_getName(_cmd));
#endif
    
    delete mAudioItem;
    mAudioItem = nil;
}

- (BOOL)isReadyToRead {
    return mReadyToRead.load(std::__1::memory_order_relaxed);
}

- (CMTime)duration {
    return mReadyToRead.load(std::__1::memory_order_relaxed) ? mDuration : kCMTimeZero;
}

- (CMTime)bufferedTime {
    return mBufferedTime.load(std::__1::memory_order_relaxed);
}

- (AVAudioFormat *)outputFormat {
    return mOutputAudioFormat;
}

- (NSError *)error {
    std::lock_guard<std::mutex> lock(mtx);
    return mError;
}

- (void)seekToTime:(CMTime)time {
    int64_t req = CMTimeConvertScale(time, AV_TIME_BASE, kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
    mAudioItem->seekTo(req);
}

#pragma mark - AudioItem callbacks

- (void)onStreamReadyWithDuration:(int64_t)duration timeBase:(AVRational)timeBase {
    {
        std::lock_guard<std::mutex> lock(mtx);
        mDuration = CMTimeMake(duration * timeBase.num, timeBase.den);
        mReadyToRead.store(true);
    }
    
    [_delegate audioItemDidReadyToRead:self];
}

- (void)onBufferedTimeChange:(int64_t)bufferedTime timeBase:(AVRational)timeBase {
    CMTime time = CMTimeMake(bufferedTime * timeBase.num, timeBase.den);
    mBufferedTime.store(time);
    [_delegate audioItem:self bufferedTimeDidChange:time];
}

- (void)onError:(int)ffErr {
    NSError *error = nil;
    {
        std::lock_guard<std::mutex> lock(mtx);
        error = [self _makeError:ffErr];
        mError = error;
    }
    [_delegate audioItem:self anErrorOccurred:error];
}

- (int)tryTranscodeWithFrameCapacity:(int)frameCapacity data:(void *_Nonnull*_Nonnull)outData pts:(int64_t *)outPts eof:(BOOL *)outEOF error:(NSError **)outError {
    int ret = 0;
    int64_t pts = 0;
    bool eof = false;
    ret = mAudioItem->tryTranscode(outData, frameCapacity, &pts, &eof);
    if ( ret < 0 ) {
        NSError *error = [self _makeError:ret];
        if ( outError ) {
            *outError = error;
        }
    }
    if ( outPts ) *outPts = pts;
    if ( outEOF ) *outEOF = eof;
    return ret;
}

#pragma mark - mark

- (NSError *)_makeError:(int)ff_err {
    return [NSError errorWithDomain:FFAudioItemErrorDomain code:-1 userInfo:@{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%s", av_err2str(ff_err)]
    }];
}
@end


@implementation FFAudioItemOptions
- (instancetype)init {
    self = [super init];
    _startTimePosition = kCMTimeZero;
    return self;
}
@end
