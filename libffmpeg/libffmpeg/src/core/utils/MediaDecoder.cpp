//
// Created on 2025/1/7.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "MediaDecoder.h"

namespace FFAV {

MediaDecoder::MediaDecoder(): dec_ctx(nullptr) {

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
    dec_ctx = avcodec_alloc_context3(codec);
    if ( dec_ctx == nullptr ) {
        return AVERROR(ENOMEM);
    }

    // 初始化解码器上下文
    // Copy decoder parameters to decoder context
    int error = avcodec_parameters_to_context(dec_ctx, codecpar);
    if ( error < 0 ) {
        return error;
    }    
    
    // 打开解码器
    error = avcodec_open2(dec_ctx, codec, nullptr);
    if ( error < 0 ) {
        return error;
    }
    return 0;
}

int MediaDecoder::send(AVPacket* _Nullable pkt) {
    if ( dec_ctx == nullptr ) {
        return AVERROR_INVALIDDATA;
    }
    
    return avcodec_send_packet(dec_ctx, pkt);
}

int MediaDecoder::receive(AVFrame* _Nonnull frame) {
    if ( dec_ctx == nullptr ) {
        return AVERROR_INVALIDDATA;
    }
    
    return avcodec_receive_frame(dec_ctx, frame);
}

void MediaDecoder::flush() {
    if ( dec_ctx != nullptr ) {
        avcodec_flush_buffers(dec_ctx);
    }
}

AVBufferSrcParameters* _Nullable MediaDecoder::createBufferSrcParameters(AVRational time_base) {
    if ( dec_ctx == nullptr ) {
        return nullptr;
    }
    
    switch(dec_ctx->codec_type) {
        case AVMEDIA_TYPE_VIDEO: {
            AVBufferSrcParameters *params = av_buffersrc_parameters_alloc();
            params->width = dec_ctx->width;
            params->height = dec_ctx->height;
            params->format = dec_ctx->pix_fmt;
            params->time_base = time_base;
            params->sample_aspect_ratio = dec_ctx->sample_aspect_ratio;
            params->hw_frames_ctx = dec_ctx->hw_frames_ctx;
            if ( dec_ctx->framerate.num ) params->frame_rate = dec_ctx->framerate;
            return params;
        }
        case AVMEDIA_TYPE_AUDIO: {
            if ( dec_ctx->ch_layout.order == AV_CHANNEL_ORDER_UNSPEC ) av_channel_layout_default(&dec_ctx->ch_layout, dec_ctx->ch_layout.nb_channels);
            AVBufferSrcParameters *params = av_buffersrc_parameters_alloc();
            params->time_base = time_base;
            params->sample_rate = dec_ctx->sample_rate;
            params->format = dec_ctx->sample_fmt;
            params->ch_layout = dec_ctx->ch_layout;
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
    return dec_ctx->sample_fmt;
}

int MediaDecoder::getSampleRate() {
    return dec_ctx->sample_rate;
}

int MediaDecoder::getChannels() {
    return dec_ctx->ch_layout.nb_channels;
}

void MediaDecoder::release() {
    if ( dec_ctx != nullptr ) {
        avcodec_free_context(&dec_ctx);
    }
}

}
