/**
    This file is part of @sj/ffmpeg.
    
    @sj/ffmpeg is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
    
    @sj/ffmpeg is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.
    
    You should have received a copy of the GNU General Public License
    along with @sj/ffmpeg. If not, see <http://www.gnu.org/licenses/>.
 * */
//
// Created by sj on 2025/1/7.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "ff_media_reader.hpp"
#include "ff_includes.hpp"
#include "ff_throw.hpp"

namespace FFAV {

static int interrupt_cb(void* ctx) {
    std::atomic<bool>* interrupt_requested = static_cast<std::atomic<bool>*>(ctx);
    bool shouldInterrupt = interrupt_requested->load(); // 是否请求中断
    return shouldInterrupt ? 1 : 0; // 1 中断, 0 继续;
}

MediaReader::MediaReader() = default;

MediaReader::~MediaReader() { release(); }

int MediaReader::open(const std::string& url, const std::map<std::string, std::string>& http_options) {
    _fmt_ctx = avformat_alloc_context();
    if ( _fmt_ctx == nullptr ) {
        return AVERROR(ENOMEM);
    }

    _fmt_ctx->interrupt_callback = { interrupt_cb, &_interrupt_requested };

    AVDictionary *options = nullptr;
    for ( auto pair: http_options ) {
        av_dict_set(&options, pair.first.c_str(), pair.second.c_str(), 0);
    }
    
    int ret = avformat_open_input(&_fmt_ctx, url.c_str(), nullptr, &options);
    av_dict_free(&options);
    
    if ( ret < 0 ) {
        return ret;
    }
     
    if ( _interrupt_requested.load() ) {
        return AVERROR_EXIT;
    }

    ret = avformat_find_stream_info(_fmt_ctx, nullptr);
    if ( ret < 0 ) {
        return  ret;
    }
    
    // 遍历流
    for ( unsigned int i = 0; i < _fmt_ctx->nb_streams; ++i ) {
        AVStream *stream = _fmt_ctx->streams[i];
        AVCodecParameters *codecpar = stream->codecpar;
        if ( codecpar == NULL ) {
            printf("MediaReader::open - stream %d: codecpar is NULL ❌\n", i);
        } else {
            printf("MediaReader::open - stream %d: codec type = %d ✅\n", i, codecpar->codec_type);
        }
    }
    
    return 0;
}

unsigned int MediaReader::getStreamCount() { 
    if ( _fmt_ctx == nullptr ) {
        return 0;
    }

    return _fmt_ctx->nb_streams;
}

AVStream *_Nullable MediaReader::getStream(int stream_index) {
    if ( _fmt_ctx == nullptr ) {
        return nullptr;
    }

    if ( stream_index < 0 || stream_index >= _fmt_ctx->nb_streams ) {
        return nullptr;
    }
    
    return _fmt_ctx->streams[stream_index];
}

AVStream* _Nullable MediaReader::getBestStream(AVMediaType type) {
    return getStream(findBestStream(type));
}

AVStream** _Nullable MediaReader::getStreams() {
    return _fmt_ctx->streams;
}

int MediaReader::findBestStream(AVMediaType type) {
    if ( _fmt_ctx == nullptr ) {
        throw_error("MediaReader::findBestStream - AVFormatContext is not initialized");
    }

    return av_find_best_stream(_fmt_ctx, type, -1, -1, nullptr, 0);
}

int MediaReader::readPacket(AVPacket* _Nonnull pkt) {
    if ( _fmt_ctx == nullptr ) {
        throw_error("MediaReader::readPacket - AVFormatContext is not initialized");
    }

    if ( _interrupt_requested.load() ) {
        return AVERROR_EXIT;
    }

    return av_read_frame(_fmt_ctx, pkt);
}

int MediaReader::seek(int64_t timestamp, int stream_index, int flags) {
    if ( _fmt_ctx == nullptr ) {
        throw_error("MediaReader::seek - AVFormatContext is not initialized");
    }
    
    if ( _interrupt_requested.load() ) {
        return AVERROR_EXIT;
    }

    return av_seek_frame(_fmt_ctx, -1, timestamp, AVSEEK_FLAG_BACKWARD);
}

void MediaReader::setInterrupted() {
    // 中断读取
    _interrupt_requested.store(true);
}

void MediaReader::release() {
    setInterrupted();

    if ( _fmt_ctx ) {
        avformat_close_input(&_fmt_ctx);
    }
}

}
