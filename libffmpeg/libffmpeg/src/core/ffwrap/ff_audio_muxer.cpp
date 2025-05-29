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
// Created by sj on 2025/3/11.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "ff_audio_muxer.hpp"
#include "ff_includes.hpp"
#include "ff_throw.hpp"

namespace FFAV {

AudioMuxer::AudioMuxer() {}

AudioMuxer::~AudioMuxer() {
    if ( _fmt_ctx ) {
        if ( !(_fmt_ctx->oformat->flags & AVFMT_NOFILE) && _fmt_ctx->pb ) {
            avio_closep(&_fmt_ctx->pb);
        }
        avformat_free_context(_fmt_ctx);
        _fmt_ctx = nullptr;
    }
}

int AudioMuxer::init(const std::string& file_path, AVCodecContext* codec_ctx) {
    int ret = 0;
    AVFormatContext*fmt_ctx;
    ret = avformat_alloc_output_context2(&fmt_ctx, NULL, NULL, file_path.c_str());
    if ( ret < 0 ) return ret;
    return init(file_path, codec_ctx, fmt_ctx);
}

int AudioMuxer::init(const std::string& file_path, AVCodecContext* codec_ctx, AVFormatContext* fmt_ctx) {
    if ( _fmt_ctx != nullptr ) {
        throw_error("AudioMuxer::init - AudioMuxer is already initialized");
    }
    
    int ret = 0;
    AVStream *stream = avformat_new_stream(fmt_ctx, nullptr);
    if ( !stream ) return AVERROR(ENOMEM);

    // avcodec_parameters_from_context 从 AVCodecContext 中提取参数，并将这些参数设置到对应的 AVCodecParameters 结构中
    ret = avcodec_parameters_from_context(stream->codecpar, codec_ctx);
    if ( ret < 0 ) return ret;

    // AV_CODEC_FLAG_GLOBAL_HEADER 是编码器（AVCodecContext）的标志，表示该编码器需要在输出中包含全局头信息。这个标志通常在一些要求全局头的编码器格式（如 H.264 或 AAC）中设置。
    if ( fmt_ctx->oformat->flags & AVFMT_GLOBALHEADER ) codec_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;

    stream->time_base = codec_ctx->time_base;

    _fmt_ctx = fmt_ctx;
    _stream = stream;
    _time_base = codec_ctx->time_base;
    _file_path = file_path;
    return 0;
}

int AudioMuxer::open() {
    if ( _fmt_ctx == nullptr ) {
        throw_error("AudioMuxer::open - AudioMuxer is not initialized");
    }
    
    if ( !(_fmt_ctx->oformat->flags & AVFMT_NOFILE) ) {
        return avio_open(&_fmt_ctx->pb, _file_path.c_str(), AVIO_FLAG_WRITE);
    }
    return 0;
}

int AudioMuxer::writeHeader() {
    if ( _fmt_ctx == nullptr ) {
        throw_error("AudioMuxer::writeHeader - AudioMuxer is not initialized");
    }
    
    return avformat_write_header(_fmt_ctx, nullptr);
}

int AudioMuxer::writePacket(AVPacket* pkt) {
    if ( _fmt_ctx == nullptr ) {
        throw_error("AudioMuxer::writePacket - AudioMuxer is not initialized");
    }
    
    pkt->stream_index = _stream->index;
    av_packet_rescale_ts(pkt, _time_base, _stream->time_base);
    return av_interleaved_write_frame(_fmt_ctx, pkt);
}

int AudioMuxer::writeTrailer() {
    if ( _fmt_ctx == nullptr ) {
        throw_error("AudioMuxer::writeTrailer - AudioMuxer is not initialized");
    }
    
    return av_write_trailer(_fmt_ctx);
}

}
