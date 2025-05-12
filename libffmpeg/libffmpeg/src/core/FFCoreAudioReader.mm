//
//  FFCoreAudioReader.m
//  LWZFFmpegLib
//
//  Created by db on 2025/4/14.
//

#import "FFCoreAudioReader.h"
#include <mutex>
#include <condition_variable>
#include "MediaReader.h"

@implementation FFCoreAudioReader {
    NSURL *mURL;
    dispatch_queue_t mQueue;
    __weak id<FFCoreAudioReaderDelegate> mDelegate;

    FFAV::MediaReader *media_reader;
    AVStream *stream;
    std::atomic<bool> stopped;
    std::atomic<bool> buffer_full;
    bool has_error;
    bool eof;
    std::atomic<int64_t> req_seek_time; // in base q; default AV_NOPTS_VALUE;
    int64_t seeking_time; // in base q; current seek time; default AV_NOPTS_VALUE;
    std::mutex mtx;
    std::condition_variable cv;
}

- (instancetype)initWithURL:(NSURL *)URL delegate:(id<FFCoreAudioReaderDelegate>)delegate {
    self = [super init];
    mURL = URL;
    mQueue = dispatch_queue_create("FF_AUDIO_READER_QUEUE", DISPATCH_QUEUE_SERIAL);
    mDelegate = delegate;
    media_reader = nullptr;

    [self reset];
    return self;
}

- (void)dealloc {
#ifdef DEBUG
    NSLog(@"%@<%p>: %d : %s", NSStringFromClass(self.class), self, __LINE__, sel_getName(_cmd));
#endif
    
    if ( media_reader ) delete media_reader;
}

- (void)prepareWithStartTimePosition:(int64_t)startTimePosition {
    dispatch_async(mQueue, ^{
        NSParameterAssert(!self->media_reader);
        
        [self onPrepareWithStartTimePosition:startTimePosition];
    });
}

- (void)start {
    dispatch_async(mQueue, ^{
        [self _onRead];
    });
}

- (void)stop {
    if ( !stopped.exchange(true, std::__1::memory_order_relaxed) ) {
        cv.notify_all();
    }
}

- (void)reset {
    dispatch_async(mQueue, ^{
        [self _onReset];
    });
}

- (void)seekToTime:(int64_t)time {
    if ( req_seek_time.exchange(time) != time ) {
        cv.notify_all();
    }
}

- (void)setPacketBufferFull:(BOOL)packetBufferFull {
    buffer_full.store(packetBufferFull, std::__1::memory_order_relaxed);
    if ( !packetBufferFull ) cv.notify_all();
}

- (BOOL)isPacketBufferFull {
    return buffer_full.load(std::__1::memory_order_relaxed);
}

#pragma mark - mark

- (void)onPrepareWithStartTimePosition:(int64_t)startTimePosition {
    media_reader = new FFAV::MediaReader();
    int ret = 0;
    
    if ( mURL.isFileURL ) {
        ret = media_reader->open([mURL.path UTF8String]); // maybe thread blocked;
    }
    else {
        ret = media_reader->open([mURL.absoluteString UTF8String]); // maybe thread blocked;
    }
    
    if ( stopped.load(std::__1::memory_order_relaxed) ) {
        return;
    }
    
    if ( ret < 0 ) {
        has_error = true;
        [mDelegate audioReader:self anErrorOccurred:ret];
        return;
    }
    
    stream = media_reader->getBestStream(AVMEDIA_TYPE_AUDIO);
    if ( !stream ) {
        ret = AVERROR_STREAM_NOT_FOUND;
        has_error = true;
        [mDelegate audioReader:self anErrorOccurred:ret];
        return;
    }

    if ( startTimePosition != AV_NOPTS_VALUE ) {
        req_seek_time.store(startTimePosition, std::__1::memory_order_relaxed);
    }

    [mDelegate audioReader:self readyToReadStream:stream];
}

// on read thread
- (void)_onRead {
    AVPacket* pkt = av_packet_alloc();
    int ret;
    bool should_seek;
    bool should_restart;
    bool should_exit;
    bool error_occurred;
    int64_t st;
    
    do {
restart:
        ret = 0;
        should_seek = false;
        should_restart = false;
        should_exit = false;
        error_occurred = false;

        if      ( has_error || stopped.load(std::__1::memory_order_acquire) ) {
            should_exit = true;
        }
        // 仅当有变化时才触发 seek
        else if ( (st = req_seek_time.exchange(AV_NOPTS_VALUE, std::__1::memory_order_acquire)) != AV_NOPTS_VALUE ) {
            should_seek = true;
            seeking_time = st;
        }
        
        if ( should_exit ) {
            goto exit_thread;
        }
        
        // handle seek
        if ( should_seek ) {
            ret = media_reader->seek(seeking_time, -1); // maybe thread blocked;
            // recheck stop
            if ( stopped.load(std::__1::memory_order_acquire) ) {
                should_exit = true;
            }
            // recheck seek req
            else if ( req_seek_time.load(std::__1::memory_order_relaxed) != AV_NOPTS_VALUE ) {
                should_restart = true;
            }
            // seek error
            else if ( ret < 0 ) {
                // eof
                if ( ret == AVERROR_EOF ) {
                    // nothing
                }
                // error
                else {
                    has_error = true;
                    error_occurred = true;
                    [mDelegate audioReader:self anErrorOccurred:ret];
                }
            }
            // seek finish
            else {
                eof = false;
            }
        }
        
        if ( should_exit || error_occurred ) {
            goto exit_thread;
        }
        
        if ( should_restart ) {
            goto restart;
        }
        
        // read pkt
        av_packet_unref(pkt);
        ret = media_reader->readPacket(pkt); // maybe thread blocked;
        // recheck stop
        if ( stopped.load(std::__1::memory_order_acquire) ) {
            should_exit = true;
        }
        // recheck seek req
        else if ( req_seek_time.load(std::__1::memory_order_relaxed) != AV_NOPTS_VALUE ) {
            should_restart = true;
        }
        // read finish
        else if ( ret == 0 ) {
            if ( pkt->stream_index == stream->index ) {
                bool should_flush = seeking_time != AV_NOPTS_VALUE;
                if ( should_flush ) {
                    seeking_time = AV_NOPTS_VALUE;
                }
                
                [mDelegate audioReader:self didReadPacket:pkt shouldFlush:should_flush];
            }
        }
        // read eof
        else if ( ret == AVERROR_EOF ) {
            eof = true;
            
            bool should_flush = seeking_time != AV_NOPTS_VALUE;
            if ( should_flush ) {
                seeking_time = AV_NOPTS_VALUE;
            }
            
            // notify eof
            [mDelegate audioReader:self didReadPacket:nullptr shouldFlush:should_flush];
            
            {
                // wait next signal
                std::unique_lock<std::mutex> lock(mtx);
                cv.wait(lock, [self] {
                    // 这里不需要专门对 hasError 进行判断
                    
                    if ( stopped.load(std::__1::memory_order_acquire) ) {
                        return true;
                    }
                    
                    if ( req_seek_time.load(std::__1::memory_order_relaxed) != AV_NOPTS_VALUE ) {
                        return true;
                    }
                
                    return !eof && !buffer_full.load(std::__1::memory_order_relaxed);
                });
            }
        }
        // ret < 0;
        // read error
        else {
            has_error = true;
            error_occurred = true;
            [mDelegate audioReader:self anErrorOccurred:ret];
        }
        
        if ( should_exit || error_occurred ) {
            goto exit_thread;
        }
    } while (true);
    
exit_thread:
    av_packet_free(&pkt);
}

// 报错重置时, req_seek_time, seeking_time 也会一起重置
- (void)_onReset {
    if ( media_reader ) {
        delete media_reader;
        media_reader = nullptr;
    }
    
    stream = nullptr;
    stopped.store(false, std::__1::memory_order_relaxed);
    buffer_full.store(false, std::__1::memory_order_relaxed);
    has_error = false;
    eof = false;
    req_seek_time.store(AV_NOPTS_VALUE, std::__1::memory_order_relaxed);
    seeking_time = AV_NOPTS_VALUE;
}
@end
