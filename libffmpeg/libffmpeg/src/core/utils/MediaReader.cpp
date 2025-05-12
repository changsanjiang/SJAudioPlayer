//
// Created on 2025/1/7.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "MediaReader.h"

namespace FFAV {

static int interrupt_cb(void* ctx) {
    std::atomic<bool>* interrupt_requested = static_cast<std::atomic<bool>*>(ctx); 
    bool shouldInterrupt = interrupt_requested->load(); // 是否请求中断
    return shouldInterrupt ? 1 : 0; // 1 中断, 0 继续;
}

MediaReader::MediaReader() = default;

MediaReader::~MediaReader() { release(); }

int MediaReader::open(const std::string& url, const std::map<std::string, std::string>& http_options) {
    fmt_ctx = avformat_alloc_context();
    if ( fmt_ctx == nullptr ) {
        return AVERROR(ENOMEM);
    }

    fmt_ctx->interrupt_callback = { interrupt_cb, &interrupt_requested };

    AVDictionary *options = nullptr;
    for ( auto pair: http_options ) {
        av_dict_set(&options, pair.first.c_str(), pair.second.c_str(), 0);
    }
    
    int ret = avformat_open_input(&fmt_ctx, url.c_str(), nullptr, &options);
    av_dict_free(&options);
    
    if ( ret < 0 ) {
        return ret;
    }
     
    if ( interrupt_requested.load() ) {
        return AVERROR_EXIT;
    }

    ret = avformat_find_stream_info(fmt_ctx, nullptr);
    if ( ret < 0 ) {
        return  ret;
    }
    
    // 遍历流
    for (unsigned int i = 0; i < fmt_ctx->nb_streams; ++i) {
        AVStream *stream = fmt_ctx->streams[i];
        AVCodecParameters *codecpar = stream->codecpar;
        if (codecpar == NULL) {
            printf("stream %d: codecpar is NULL ❌\n", i);
        } else {
            printf("stream %d: codec type = %d ✅\n", i, codecpar->codec_type);
        }
    }
    
    return 0;
}

unsigned int MediaReader::getStreamCount() { 
    if ( fmt_ctx == nullptr ) {
        return 0;
    }

    return fmt_ctx->nb_streams; 
}

AVStream *_Nullable MediaReader::getStream(int stream_index) {
    if ( fmt_ctx == nullptr ) {
        return nullptr;
    }

    if ( stream_index < 0 || stream_index >= fmt_ctx->nb_streams ) {
        return nullptr;
    }
    
    return fmt_ctx->streams[stream_index];
}

AVStream* _Nullable MediaReader::getBestStream(AVMediaType type) {
    return getStream(findBestStream(type));
}

AVStream** _Nullable MediaReader::getStreams() {
    return fmt_ctx->streams;
}

int MediaReader::findBestStream(AVMediaType type) {
    if ( fmt_ctx == nullptr ) {
        throw std::runtime_error("AVFormatContext is not initialized");
    }

    return av_find_best_stream(fmt_ctx, type, -1, -1, nullptr, 0);
}

int MediaReader::readPacket(AVPacket* _Nonnull pkt) {
    if ( fmt_ctx == nullptr ) {
        throw std::runtime_error("AVFormatContext is not initialized");
    }

    if ( interrupt_requested.load() ) {
        return AVERROR_EXIT;
    }

    return av_read_frame(fmt_ctx, pkt);
}

int MediaReader::seek(int64_t timestamp, int stream_index, int flags) {
    if ( fmt_ctx == nullptr ) {
        throw std::runtime_error("AVFormatContext is not initialized");
    }
    
    if ( interrupt_requested.load() ) {
        return AVERROR_EXIT;
    }

    return av_seek_frame(fmt_ctx, -1, timestamp, AVSEEK_FLAG_BACKWARD);
}

void MediaReader::interrupt() {
    interrupt_requested.store(true);
}

void MediaReader::release() {
    if ( fmt_ctx ) {
        interrupt();

        avformat_close_input(&fmt_ctx);
    }
}

}
