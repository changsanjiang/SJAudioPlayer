//
// Created on 2025/3/11.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "AudioMuxer.h"

namespace FFAV {

AudioMuxer::AudioMuxer() {}

AudioMuxer::~AudioMuxer() {
    if ( fmt_ctx ) {
        if ( !(fmt_ctx->oformat->flags & AVFMT_NOFILE) && fmt_ctx->pb ) {
            avio_closep(&fmt_ctx->pb);
        }
        avformat_free_context(fmt_ctx);
        fmt_ctx = nullptr;
    }
}

int AudioMuxer::init(const std::string& file_path, AVCodecContext* codec_ctx) {
    int ret = 0;
    AVFormatContext* fmt_ctx;
    ret = avformat_alloc_output_context2(&fmt_ctx, NULL, NULL, file_path.c_str());
    if ( ret < 0 ) return ret;
    return init(file_path, codec_ctx, fmt_ctx);
}

int AudioMuxer::init(const std::string& file_path, AVCodecContext* codec_ctx, AVFormatContext* fmt_ctx) {
    int ret = 0;
    stream = avformat_new_stream(fmt_ctx, nullptr);
    if ( !stream ) return AVERROR(ENOMEM);

    // avcodec_parameters_from_context 从 AVCodecContext 中提取参数，并将这些参数设置到对应的 AVCodecParameters 结构中
    ret = avcodec_parameters_from_context(stream->codecpar, codec_ctx);
    if ( ret < 0 ) return ret;

    // AV_CODEC_FLAG_GLOBAL_HEADER 是编码器（AVCodecContext）的标志，表示该编码器需要在输出中包含全局头信息。这个标志通常在一些要求全局头的编码器格式（如 H.264 或 AAC）中设置。
    if ( fmt_ctx->oformat->flags & AVFMT_GLOBALHEADER ) codec_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    
    this->fmt_ctx = fmt_ctx;
    this->time_base = codec_ctx->time_base;
    this->file_path = file_path;
    return 0;
}

int AudioMuxer::open() {
    if ( !(fmt_ctx->oformat->flags & AVFMT_NOFILE) ) { 
        return avio_open(&fmt_ctx->pb, file_path.c_str(), AVIO_FLAG_WRITE);
    }
    return 0;
}

int AudioMuxer::writeHeader() {
    return avformat_write_header(fmt_ctx, nullptr);
}

int AudioMuxer::writePacket(AVPacket* pkt) {
    pkt->stream_index = stream->index;
    av_packet_rescale_ts(pkt, time_base, stream->time_base);
    return av_interleaved_write_frame(fmt_ctx, pkt);
}

int AudioMuxer::writeTrailer() {
    return av_write_trailer(fmt_ctx);
}

}
