//
// Created on 2025/3/11.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "AudioWriter.h"
#include <cerrno>
#include <cstdint>
#include <sstream>

namespace FFAV {

static const std::string FILTER_ABUFFER_SRC_NAME = "a";
static const std::string FILTER_ABUFFER_SINK_NAME = "o";

AudioWriter::AudioWriter() {
    
}

AudioWriter::~AudioWriter() {
    
    if ( encoder ) {
        delete encoder;
    }
    
    if ( fifo ) {
        delete fifo;
    }
    
    if ( filter_graph ) {
        delete filter_graph;
    }
    
    if ( muxer ) {
        delete muxer;
    }
    
    if ( filter_out_frame ) {
        av_frame_free(&filter_out_frame);
    }
    
    if ( out_pkt ) {
        av_packet_free(&out_pkt);
    }
    
    if ( fifo_out_frame ) {
        av_frame_free(&fifo_out_frame);
    }
}

int AudioWriter::init(
    const std::string& out_file_path,
    AVSampleFormat in_sample_fmt,
    int in_sample_rate,
    int in_nb_channels
) {
    int ret = 0;
    
    this->in_sample_fmt = in_sample_fmt;
    this->in_sample_rate = in_sample_rate;
    this->in_nb_channels = in_nb_channels;
    av_channel_layout_default(&in_ch_layout, in_nb_channels);
    
    // Allocate the output format context
    AVFormatContext* fmt_ctx { nullptr };
    ret = avformat_alloc_output_context2(&fmt_ctx, NULL, NULL, out_file_path.c_str());
    if ( ret < 0 ) {
        return ret;
    }
    
    // Find the encoder for the output format
    const AVCodec* codec = avcodec_find_encoder(fmt_ctx->oformat->audio_codec);
    if ( codec == nullptr ) {
        avformat_free_context(fmt_ctx);
        return AVERROR_ENCODER_NOT_FOUND;
    }
    
    // Create encoder
    AVSampleFormat preferred_sample_fmt = in_sample_fmt;
    int preferred_sample_rate = in_sample_rate;
    int preferred_nb_channels = in_nb_channels;
    encoder = new AudioEncoder();
    ret = encoder->init(codec, preferred_sample_fmt, preferred_sample_rate, preferred_nb_channels);
    if ( ret < 0 ) {
        avformat_free_context(fmt_ctx);
        return ret;
    }
    
    // Create muxer
    muxer = new AudioMuxer();
    ret = muxer->init(out_file_path, encoder->getCodecContext(), fmt_ctx);
    if ( ret < 0 ) {
        avformat_free_context(fmt_ctx);
        return ret;
    }
    
    // Get output formats
    out_sample_fmt = encoder->getSampleFormat();
    out_sample_rate = encoder->getSampleRate();
    out_nb_channels = encoder->getChannels();
    out_ch_layout = encoder->getChannelLayout();
    out_frame_size = encoder->getFrameSize() ?: 1024;
    int out_sample_rates[] = { out_sample_rate, -1 };
    AVSampleFormat out_sample_fmts[] = { out_sample_fmt, AV_SAMPLE_FMT_NONE };
    char out_ch_layout_desc[64];
    av_channel_layout_describe(&out_ch_layout, out_ch_layout_desc, sizeof(out_ch_layout_desc)); // get channel layout desc
    
    // Create filter graph
    filter_graph = new FilterGraph();
    ret = filter_graph->init();
    if ( ret < 0 ) {
        return ret;
    }
    
    ret = filter_graph->addAudioBufferSourceFilter(
        FILTER_ABUFFER_SRC_NAME, 
        (AVRational){ 1, in_sample_rate },
        in_sample_rate, 
        in_sample_fmt,
        out_ch_layout_desc
    );
    if ( ret < 0 ) {
        return ret;
    }

    ret = filter_graph->addAudioBufferSinkFilter(
        FILTER_ABUFFER_SINK_NAME, 
        out_sample_rates,
        out_sample_fmts, 
        out_ch_layout_desc
    );
    if ( ret < 0 ) {
        return ret;
    }
    
    std::stringstream filter_descr_ss;
    filter_descr_ss << "[" << FILTER_ABUFFER_SRC_NAME << "]"
                    << "aformat=sample_fmts=" << av_get_sample_fmt_name(out_sample_fmt) << ":channel_layouts=" << out_ch_layout_desc
                    << ",aresample=" << out_sample_rate
                    << "[" << FILTER_ABUFFER_SINK_NAME << "]";
    ret = filter_graph->parse(filter_descr_ss.str());
    if ( ret < 0 ) {
        return ret;
    }
    
    ret = filter_graph->configure();
    if ( ret < 0 ) {
        return ret;
    }
    
    fifo = new AudioFifo();
    ret = fifo->init(out_sample_fmt, out_nb_channels, 1);
    if ( ret < 0 ) {
        return ret;
    }
    
    filter_out_frame = av_frame_alloc();
    out_pkt = av_packet_alloc();
    
    fifo_out_frame = av_frame_alloc();
    fifo_out_frame->format = out_sample_fmt;
    fifo_out_frame->sample_rate = out_sample_rate;
    fifo_out_frame->ch_layout = out_ch_layout;
    fifo_out_frame->nb_samples = out_frame_size;
    av_frame_get_buffer(fifo_out_frame, 1);
    
exit_init:
    if ( ret < 0 ) {
        avformat_free_context(fmt_ctx);
        return ret;
    }
    return 0;
}

int AudioWriter::open() {
    int ret = muxer->open();
    if ( ret < 0 ) return ret;
    return muxer->writeHeader();
}

int AudioWriter::write(AVFrame* frame) {
    int ret = filter_graph->addFrame(FILTER_ABUFFER_SRC_NAME, frame);
    if ( ret < 0 ) {
        return ret;
    }
    return consumeAbufferSink();
}

int AudioWriter::write(void *buffer, int buffer_size) {     
    AVFrame* frame = av_frame_alloc();
    frame->format = in_sample_fmt;
    frame->sample_rate = in_sample_rate;
    frame->ch_layout = in_ch_layout;
    frame->nb_samples = buffer_size / (av_get_bytes_per_sample(in_sample_fmt) * in_nb_channels);
    
    int ret = avcodec_fill_audio_frame(frame, in_ch_layout.nb_channels, in_sample_fmt, (uint8_t*)buffer, buffer_size, 1);
    if ( ret < 0 ) {
        return ret;
    } 
    
    frame->pts = in_pts;
    in_pts += frame->nb_samples;
    
    ret = write(frame);
    av_frame_free(&frame);
    return ret;
}

int AudioWriter::close() {
    int ret = filter_graph->addFrame(FILTER_ABUFFER_SRC_NAME, nullptr, AV_BUFFERSRC_FLAG_PUSH);
    if ( ret < 0 ) {
        return ret;
    }
    
    ret = consumeAbufferSink();
    if ( ret < 0 ) {
        return ret;
    }
    return muxer->writeTrailer();
}

int AudioWriter::consumeAbufferSink() {
    int ret = 0;
    while (true) {
        ret = filter_graph->getFrame(FILTER_ABUFFER_SINK_NAME, filter_out_frame);
        if ( ret == AVERROR(EAGAIN) ) {
            return 0;
        }
        
        if ( ret == AVERROR_EOF ) {
            return consumeFifo(true);
        }
        
        ret = fifo->write((void **)filter_out_frame->data, filter_out_frame->nb_samples, filter_out_frame->pts);
        if ( ret < 0 ) {
            return ret;
        }
        
        ret = consumeFifo(false);
        if ( ret < 0 ) {
            return ret;
        }
    }
    return 0;
}

int AudioWriter::consumeFifo(bool eos) {
    int ret = 0;
    
    while ( fifo->getNumberOfSamples() >= out_frame_size || (fifo->getNumberOfSamples() > 0 && eos) ) {
        ret = fifo->read((void **)fifo_out_frame->data, out_frame_size, &fifo_out_frame->pts);
        if ( ret < 0 ) {
            return ret;
        }
        fifo_out_frame->nb_samples = ret;
        
        ret = encoder->send(fifo_out_frame);
        if ( ret < 0 && ret != AVERROR(EAGAIN) ) {
            return ret;
        }
    }
    
    if ( eos ) {
        ret = encoder->send(nullptr);
        if ( ret < 0 && ret != AVERROR_EOF ) {
            return ret;
        }
    }
    
    while (ret >= 0) {
        ret = encoder->receive(out_pkt);
        if ( ret == AVERROR(EAGAIN) || ret == AVERROR_EOF ) {
            break;
        }
        else if (ret < 0) {
            return ret;
        }
        
        ret = muxer->writePacket(out_pkt);
        av_packet_unref(out_pkt);
    }
    return 0;
}
}
