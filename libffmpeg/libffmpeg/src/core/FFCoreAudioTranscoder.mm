//
//  FFCoreAudioTranscoder.m
//  LWZFFmpegLib
//
//  Created by db on 2025/4/24.
//

#import "FFCoreAudioTranscoder.h"
#import "MediaReader.h"
#import "MediaDecoder.h"
#import "PacketQueue.h"
#import "FilterGraph.h"
#import "AudioFifo.h"
#import "AudioUtils.h"
#import "FFCoreFormat.h"

static const std::string FF_FILTER_BUFFER_SRC_NAME = "0:a";
static const std::string FF_FILTER_BUFFER_SINK_NAME = "result";

@implementation FFCoreAudioTranscoder {
    AVAudioFormat *mOutputAudioFormat;
    int mOutputBytesPerSample;
    int mPacketSizeThreshold; // bytes; 5M;

    BOOL mPrepared;
    BOOL mPacketEOF;
    BOOL mTranscodingEOF;
    BOOL mShouldAlignFrames;
    
    BOOL mShouldDrainPackets; // 控制缓冲， 确保流畅播放(满3s)
    
    int64_t mAudioStreamDuration;
    AVRational mAudioStreamTimeBase;
    AVBufferSrcParameters *mBufferSrcParams;
    FFAV::MediaDecoder *mAudioDecoder;
    FFAV::FilterGraph *mFilterGraph;
    FFAV::PacketQueue *mPacketQueue;
    FFAV::AudioFifo *mAudioFifo;
    
    AVPacket *mPacket;
    AVFrame *mDecFrame;
    AVFrame *mFiltFrame;
}

- (instancetype)init {
    self = [super init];
    // mOutputAudioFormat
    mOutputAudioFormat = [AVAudioFormat.alloc initWithCommonFormat:FFCoreFormat::FF_OUTPUT_AUDIO_COMMON_FORMAT
                                                        sampleRate:FFCoreFormat::FF_OUTPUT_SAMPLE_RATE
                                                          channels:FFCoreFormat::FF_OUTPUT_CHANNELS
                                                       interleaved:FFCoreFormat::FF_OUTOUT_INTERLEAVED];
    mOutputBytesPerSample = av_get_bytes_per_sample(FFCoreFormat::FF_OUTPUT_SAMPLE_FORMAT);
    mPacketSizeThreshold = 5 * 1024 * 1024;
    return self;
}

- (void)dealloc {
#ifdef DEBUG
    NSLog(@"%@<%p>: %d : %s", NSStringFromClass(self.class), self, __LINE__, sel_getName(_cmd));
#endif
    
    if ( mAudioDecoder ) delete mAudioDecoder;
    if ( mFilterGraph ) delete mFilterGraph;
    if ( mBufferSrcParams ) av_free(mBufferSrcParams);
    if ( mPacketQueue ) delete mPacketQueue;
    if ( mAudioFifo ) delete mAudioFifo;
    if ( mPacket ) av_packet_free(&mPacket);
    if ( mDecFrame ) av_frame_free(&mDecFrame);
    if ( mFiltFrame ) av_frame_free(&mFiltFrame);
}

- (BOOL)isPacketBufferFull {
    return mPacketQueue->getSize() >= mPacketSizeThreshold;
}

- (AVAudioFormat *)outputFormat {
    return mOutputAudioFormat;
}

- (CMTimeRange)timeRange {
    CMTimeRange timeRange = kCMTimeRangeZero;
    if ( mPrepared ) {
        int64_t startPts = 0;
        int64_t endPts = 0;
        
        int64_t fifoNextPts = mAudioFifo->getNextPts();         // range start, (还未读取的pcm数据)
        int64_t frontPts = mPacketQueue->getFrontPacketPts();   // range start, (未调用pop时取该值为起始值)
        int64_t lastPopPts = mPacketQueue->getLastPopPts();     // range start
        int64_t lastPushPts = mPacketQueue->getLastPushPts();   // range end

        // start pts
        if ( fifoNextPts != AV_NOPTS_VALUE ) {
            startPts = av_rescale_q(fifoNextPts, (AVRational) { 1, (int)mOutputAudioFormat.sampleRate }, mAudioStreamTimeBase);
        }
        else if ( mPacketEOF && mPacketQueue->getCount() == 0 ) {
            startPts = mAudioStreamDuration;
        }
        else if ( lastPopPts != AV_NOPTS_VALUE ) {
            startPts = lastPopPts;
        }
        else {
            startPts = frontPts;
        }
        
        // end pts
        if ( mPacketEOF ) {
            endPts = mAudioStreamDuration;
        }
        else {
            endPts = lastPushPts;
        }
        
        if ( startPts != AV_NOPTS_VALUE && endPts != AV_NOPTS_VALUE ) {
            CMTime rangeStart = CMTimeMake(startPts * mAudioStreamTimeBase.num, mAudioStreamTimeBase.den);
            CMTime rangeEnd = CMTimeMake(endPts * mAudioStreamTimeBase.num, mAudioStreamTimeBase.den);
            CMTime rangeDuration = CMTimeSubtract(rangeEnd, rangeStart);
            timeRange = CMTimeRangeMake(rangeStart, rangeDuration);
        }
    }
    return timeRange;
}

- (BOOL)eof {
    return mTranscodingEOF && mAudioFifo->getNumberOfSamples() == 0;
}

- (CMTime)fifoEndPts {
    if ( mPrepared ) {
        int64_t pts = mAudioFifo->getEndPts();
        if ( pts != AV_NOPTS_VALUE ) {
            return CMTimeMake(pts, (int)mOutputAudioFormat.sampleRate);
        }
    }
    return kCMTimeInvalid;
}

- (int)prepareByAudioStream:(AVStream *)stream {
    NSParameterAssert(!mPrepared);
    
    int ff_ret = 0;
    if ( stream->codecpar == nullptr ) {
        ff_ret = AVERROR_DECODER_NOT_FOUND;
        goto on_exit; // exit;
    }
    
    mAudioStreamDuration = stream->duration;
    mAudioStreamTimeBase = stream->time_base;

    // init decoder
    mAudioDecoder = new FFAV::MediaDecoder();
    ff_ret = mAudioDecoder->init(stream->codecpar);
    if ( ff_ret < 0 ) {
        goto on_exit; // exit;
    }
    
    // create buffer src params
    mBufferSrcParams = mAudioDecoder->createBufferSrcParameters(stream->time_base);
   
    // init filter graph
    mFilterGraph = [self _createFilterGraphWithError:&ff_ret];
    if ( ff_ret < 0 ) {
        goto on_exit; // exit;
    }
    
    // init pkt queue
    mPacketQueue = new FFAV::PacketQueue();
    
    // init audio fifo
    mAudioFifo = new FFAV::AudioFifo();
    ff_ret = mAudioFifo->init(FFCoreFormat::FF_OUTPUT_SAMPLE_FORMAT, FFCoreFormat::FF_OUTPUT_CHANNELS, 1);
    if ( ff_ret < 0 ) {
        goto on_exit; // exit;
    }
    
    // ready
    mPacket = av_packet_alloc();
    mDecFrame = av_frame_alloc();
    mFiltFrame = av_frame_alloc();

on_exit:
    return ff_ret;
}

- (int)push:(AVPacket *)packet {
    mPacketQueue->push(packet);
    return 0;
}

- (int)pushPacket:(AVPacket *_Nullable)packet shouldFlush:(BOOL)shouldFlush {
    if ( shouldFlush ) {
        mPacketEOF = false;
        mTranscodingEOF = false;
        
        mAudioFifo->clear();
        mPacketQueue->clear();
        mAudioDecoder->flush();
     
        int ret = 0;
        ret = [self _recreateFilterGraph];
        if ( ret < 0 ) {
            return ret;
        }
    }
    
    if ( packet ) {
        mPacketQueue->push(packet);
    }
    else {
        mPacketEOF = true;
        
        if ( mPacketQueue->getCount() == 0 ) {
            mTranscodingEOF = true;
        }
    }
    
    return 0;
}

- (int)pushPacket:(AVPacket *)packet shouldOnlyFlushPackets:(BOOL)shouldOnlyFlushPackets {
    if ( shouldOnlyFlushPackets ) {
        mPacketEOF = false;
        mTranscodingEOF = false;
        mShouldAlignFrames = mAudioFifo->getNumberOfSamples() > 0;
    
        mPacketQueue->clear();
        mAudioDecoder->flush();
        
        int ret = 0;
        ret = [self _recreateFilterGraph];
        if ( ret < 0 ) {
            return ret;
        }
    }
    
    if ( packet ) {
        mPacketQueue->push(packet);
    }
    else {
        mPacketEOF = true;
        
        if ( mPacketQueue->getCount() == 0 ) {
            mTranscodingEOF = true;
        }
    }
    
    return 0;
}

- (int)tryTranscodeWithFrameCapacity:(int)frameCapacity data:(void *_Nonnull*_Nonnull)outData pts:(int64_t *)outPts eof:(BOOL *)outEOF {
    // 控制缓冲， 确保流畅播放(满3s)
    if ( !mShouldDrainPackets ) {
        if ( mPacketEOF ) {
            mShouldDrainPackets = YES;
        }
        else {
            int64_t startPts = mPacketQueue->getFrontPacketPts();
            int64_t endPts = mPacketQueue->getLastPushPts();
            if ( endPts != AV_NOPTS_VALUE && startPts != AV_NOPTS_VALUE ) {
                if ( endPts - startPts >= av_rescale_q(3, (AVRational){ 1, 1 }, mAudioStreamTimeBase) ) {
                    mShouldDrainPackets = YES; // 需要榨干pkts
                }
            }
        }
    }
    
    if ( !mShouldDrainPackets ) {
        return 0;
    }
    
    // transcoding
    if ( !mTranscodingEOF ) {
        int ff_ret = 0;
        do {
            // 如果转码后的数据足够或者已转码结束, 则退出循环
            if ( mAudioFifo->getNumberOfSamples() >= frameCapacity || mTranscodingEOF ) {
                break;
            }
            
            // 当前无可转码数据时, 退出循环
            if ( !mPacketEOF && mPacketQueue->getSize() == 0 ) {
                break;
            }
            
            // 有可转码数据或已`read eof`
            AVPacket* nextPacket = nullptr;
            if ( mPacketQueue->pop(mPacket) ) {
                nextPacket = mPacket;
            }
            
            // do transcode
            ff_ret = FFAV::AudioUtils::transcode(nextPacket, mAudioDecoder, mDecFrame, mFilterGraph, mFiltFrame, FF_FILTER_BUFFER_SRC_NAME, FF_FILTER_BUFFER_SINK_NAME, [self](AVFrame *filtFrame) {
                // flush packets 已完成 && 需要对齐时
                if ( mShouldAlignFrames ) {
                    int64_t aligned_pts = mAudioFifo->getEndPts();
                    int64_t start_pts = filtFrame->pts;
                    if ( aligned_pts != AV_NOPTS_VALUE && aligned_pts != start_pts ) {
                        if ( start_pts > aligned_pts ) {
                            return AVERROR_BUG2;
                        }

                        int64_t end_pts = start_pts + filtFrame->nb_samples;
                        if ( aligned_pts >= end_pts ) {
                            return 0;
                        }

                        // intersecting samples
                        int64_t nb_samples = end_pts - aligned_pts;
                        // LR LR LR
                        if ( FFCoreFormat::FF_OUTOUT_INTERLEAVED ) {
                            int64_t pos_offset = (aligned_pts - start_pts) * mOutputBytesPerSample * FFCoreFormat::FF_OUTPUT_CHANNELS;
                            uint8_t *ptr = filtFrame->data[0] + pos_offset;
                            mShouldAlignFrames = false;
                            return mAudioFifo->write((void **)&ptr, (int)nb_samples, aligned_pts);
                        }
                        // ch0: L L L
                        // ch1: R R R
                        else {
                            int64_t pos_offset = (aligned_pts - start_pts) * mOutputBytesPerSample;
                            uint8_t *chPtr[FFCoreFormat::FF_OUTPUT_CHANNELS];
                            for (int ch = 0; ch < FFCoreFormat::FF_OUTPUT_CHANNELS; ++ch) {
                                chPtr[ch] = filtFrame->data[ch] + pos_offset;
                            }
                            mShouldAlignFrames = false;
                            return mAudioFifo->write((void **)chPtr, (int)nb_samples, aligned_pts);
                        }
                    }
                    else {
                        mShouldAlignFrames = false;
                    }
                }
                return mAudioFifo->write((void **)filtFrame->data, filtFrame->nb_samples, filtFrame->pts);
            });
            
            if ( nextPacket ) {
                av_packet_unref(nextPacket);
            }
            
            // eof
            if ( ff_ret == AVERROR_EOF ) {
                mTranscodingEOF = true;
                break;
            }
            else if ( ff_ret == AVERROR(EAGAIN) ) {
                // nothing
            }
            // error
            else if ( ff_ret < 0 ) {
                break;
            }
        } while (true);
        
        // transcode error
        if ( ff_ret < 0 && ff_ret != AVERROR_EOF && ff_ret != AVERROR(EAGAIN) ) {
            return ff_ret;
        }
    }
    
    // read data
    int ret = 0;
    if ( mAudioFifo->getNumberOfSamples() > 0 ) {
        if ( mAudioFifo->getNumberOfSamples() >= frameCapacity || mTranscodingEOF ) {
            int64_t pts = 0;
            ret = mAudioFifo->read(outData, frameCapacity, &pts);
            if ( outPts ) *outPts = pts;
        }
    }
    
    // set eof
    if ( outEOF ) {
        *outEOF = mTranscodingEOF && mAudioFifo->getNumberOfSamples() == 0;
    }
    
    // 已榨干pkts
    if ( mShouldDrainPackets && mPacketQueue->getCount() == 0 ) {
        mShouldDrainPackets = NO;
    }
    return ret;
}

#pragma mark - mark

- (int)_recreateFilterGraph {
    int ff_ret = 0;
    if ( mFilterGraph ) delete mFilterGraph;
    mFilterGraph = [self _createFilterGraphWithError:&ff_ret];
    return ff_ret;
}

- (FFAV::FilterGraph *_Nullable)_createFilterGraphWithError:(int*)errPtr {
    NSParameterAssert(mBufferSrcParams != nil);
    
    FFAV::FilterGraph *filterGraph = new FFAV::FilterGraph();
    NSString *filter_desc = nil;
    int ff_ret = 0;
    
    ff_ret = filterGraph->init();
    if ( ff_ret < 0 ) {
        goto on_exit;
    }
    
    if ( ff_ret < 0 ) {
        goto on_exit;
    }
    
    ff_ret = filterGraph->addBufferSourceFilter(FF_FILTER_BUFFER_SRC_NAME, AVMEDIA_TYPE_AUDIO, mBufferSrcParams);
    if ( ff_ret < 0 ) {
        goto on_exit;
    }
    
    ff_ret = filterGraph->addAudioBufferSinkFilter(FF_FILTER_BUFFER_SINK_NAME, FFCoreFormat::FF_OUTPUT_SAMPLE_RATE, FFCoreFormat::FF_OUTPUT_SAMPLE_FORMAT, FFCoreFormat::FF_OUTPUT_CHANNEL_DESC);
    if ( ff_ret < 0 ) {
        goto on_exit;
    }

    filter_desc = [NSString stringWithFormat:@"[%s]aformat=sample_fmts=%s:channel_layouts=%s,aresample=%d[%s]", FF_FILTER_BUFFER_SRC_NAME.c_str(), av_get_sample_fmt_name(FFCoreFormat::FF_OUTPUT_SAMPLE_FORMAT), FFCoreFormat::FF_OUTPUT_CHANNEL_DESC.c_str(), FFCoreFormat::FF_OUTPUT_SAMPLE_RATE, FF_FILTER_BUFFER_SINK_NAME.c_str()];
        
    ff_ret = filterGraph->parse(filter_desc.UTF8String);
    
    if ( ff_ret < 0 ) {
        goto on_exit;
    }
    
    ff_ret = filterGraph->configure();
    if ( ff_ret < 0 ) {
        goto on_exit;
    }
    
    
on_exit:
    if ( ff_ret < 0 ) {
        if ( errPtr ) *errPtr = ff_ret;
        filterGraph = nullptr;
    }
    return filterGraph;
}
@end
