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

#include "ff_media_decoder.hpp"
#include "ff_includes.hpp"

namespace FFAV {

MediaDecoder::MediaDecoder() {

}

MediaDecoder::~MediaDecoder() {
    release();
}

int MediaDecoder::init(AVCodecParameters* _Nonnull codecpar) {
    // 获取解码器
    const AVCodec* codec = avcodec_find_decoder(codecpar->codec_id);
    if ( codec == nullptr ) {
        return AVERROR_DECODER_NOT_FOUND; // 找不到解码器
    }

    // 创建解码器上下文
    _dec_ctx = avcodec_alloc_context3(codec);
    if ( _dec_ctx == nullptr ) {
        return AVERROR(ENOMEM);
    }

    // 初始化解码器上下文
    // Copy decoder parameters to decoder context
    int error = avcodec_parameters_to_context(_dec_ctx, codecpar);
    if ( error < 0 ) {
        return error;
    }    
    
    // 打开解码器
    error = avcodec_open2(_dec_ctx, codec, nullptr);
    if ( error < 0 ) {
        return error;
    }
    return 0;
}

int MediaDecoder::send(AVPacket* _Nullable pkt) {
    if ( _dec_ctx == nullptr ) {
        return AVERROR_INVALIDDATA;
    }
    
    return avcodec_send_packet(_dec_ctx, pkt);
}

int MediaDecoder::receive(AVFrame* _Nonnull frame) {
    if ( _dec_ctx == nullptr ) {
        return AVERROR_INVALIDDATA;
    }
    
    return avcodec_receive_frame(_dec_ctx, frame);
}

void MediaDecoder::flush() {
    if ( _dec_ctx != nullptr ) {
        avcodec_flush_buffers(_dec_ctx);
    }
}

AVBufferSrcParameters* _Nullable MediaDecoder::createBufferSrcParameters(AVRational stream_time_base) {
    if ( _dec_ctx == nullptr ) {
        return nullptr;
    }
    
    switch(_dec_ctx->codec_type) {
        case AVMEDIA_TYPE_VIDEO: {
            AVBufferSrcParameters *params = av_buffersrc_parameters_alloc();
            params->width = _dec_ctx->width;
            params->height = _dec_ctx->height;
            params->format = _dec_ctx->pix_fmt;
            params->time_base = stream_time_base;
            params->sample_aspect_ratio = _dec_ctx->sample_aspect_ratio;
            params->hw_frames_ctx = _dec_ctx->hw_frames_ctx;
            if ( _dec_ctx->framerate.num ) params->frame_rate = _dec_ctx->framerate;
            return params;
        }
        case AVMEDIA_TYPE_AUDIO: {
            if ( _dec_ctx->ch_layout.order == AV_CHANNEL_ORDER_UNSPEC ) av_channel_layout_default(&_dec_ctx->ch_layout, _dec_ctx->ch_layout.nb_channels);
            AVBufferSrcParameters *params = av_buffersrc_parameters_alloc();
            params->time_base = stream_time_base;
            params->sample_rate = _dec_ctx->sample_rate;
            params->format = _dec_ctx->sample_fmt;
            params->ch_layout = _dec_ctx->ch_layout;
            return params;
        }
        case AVMEDIA_TYPE_UNKNOWN:
        case AVMEDIA_TYPE_DATA:
        case AVMEDIA_TYPE_SUBTITLE:
        case AVMEDIA_TYPE_ATTACHMENT:
        case AVMEDIA_TYPE_NB:
            return nullptr;
    }
}

AVSampleFormat MediaDecoder::getSampleFormat() {
    return _dec_ctx->sample_fmt;
}

int MediaDecoder::getSampleRate() {
    return _dec_ctx->sample_rate;
}

int MediaDecoder::getChannels() {
    return _dec_ctx->ch_layout.nb_channels;
}

void MediaDecoder::release() {
    if ( _dec_ctx != nullptr ) {
        avcodec_free_context(&_dec_ctx);
    }
}

}
