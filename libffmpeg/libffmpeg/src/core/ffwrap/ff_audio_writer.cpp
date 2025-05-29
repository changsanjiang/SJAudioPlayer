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

#include "ff_audio_writer.hpp"
#include <cerrno>
#include <cstdint>
#include <sstream>

#include "ff_audio_encoder.hpp"
#include "ff_audio_fifo.hpp"
#include "ff_audio_muxer.hpp"
#include "ff_filter_graph.hpp"
#include "ff_includes.hpp"
#include "ff_throw.hpp"
#include "ff_audio_utils.hpp"

namespace FFAV {

static const std::string FILTER_ABUFFER_SRC_NAME = "a";
static const std::string FILTER_ABUFFER_SINK_NAME = "o";

AudioWriter::AudioWriter() {
    
}

AudioWriter::~AudioWriter() {
    
    if ( _encoder ) {
        delete _encoder;
    }
    
    if ( _fifo ) {
        delete _fifo;
    }
    
    if ( _filter_graph ) {
        delete _filter_graph;
    }
    
    if ( _muxer ) {
        delete _muxer;
    }
    
    if ( _in_frame ) {
        av_frame_free(&_in_frame);
    }
    
    if ( _out_filt_frame ) {
        av_frame_free(&_out_filt_frame);
    }
    
    if ( _out_enc_pkt ) {
        av_packet_free(&_out_enc_pkt);
    }
    
    if ( _out_fifo_frame ) {
        av_frame_free(&_out_fifo_frame);
    }
}

int AudioWriter::init(
    const std::string& out_file_path,
    AVSampleFormat in_sample_fmt,
    int in_sample_rate,
    int in_nb_channels
) {
    int ret = 0;
    
    _in_sample_fmt = in_sample_fmt;
    _in_sample_rate = in_sample_rate;
    _in_nb_channels = in_nb_channels;
    av_channel_layout_default(&_in_ch_layout, in_nb_channels);
    
    char in_ch_layout_desc[64];
    av_channel_layout_describe(&_in_ch_layout, in_ch_layout_desc, sizeof(in_ch_layout_desc)); // get channel layout desc

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
    _encoder = new AudioEncoder();
    ret = _encoder->init(codec, preferred_sample_fmt, preferred_sample_rate, preferred_nb_channels);
    if ( ret < 0 ) {
        avformat_free_context(fmt_ctx);
        return ret;
    }
    
    // Create muxer
    _muxer = new AudioMuxer();
    ret = _muxer->init(out_file_path, _encoder->getCodecContext(), fmt_ctx);
    if ( ret < 0 ) {
        avformat_free_context(fmt_ctx);
        return ret;
    }
    
    // Get output formats
    _out_sample_fmt = _encoder->getSampleFormat();
    _out_sample_rate = _encoder->getSampleRate();
    _out_ch_layout = _encoder->getChannelLayout();
    _out_nb_channels = _out_ch_layout.nb_channels;
    _out_frame_size = _encoder->getFrameSize() ?: 1024;
    int out_sample_rates[] = { _out_sample_rate, -1 };
    AVSampleFormat out_sample_fmts[] = { _out_sample_fmt, AV_SAMPLE_FMT_NONE };
    
    char out_ch_layout_desc[64];
    av_channel_layout_describe(&_out_ch_layout, out_ch_layout_desc, sizeof(out_ch_layout_desc)); // get channel layout desc
    
    // Create filter graph
    _filter_graph = new FilterGraph();
    ret = _filter_graph->init();
    if ( ret < 0 ) {
        return ret;
    }
    
    ret = _filter_graph->addAudioBufferSourceFilter(
        FILTER_ABUFFER_SRC_NAME,
        (AVRational){ 1, in_sample_rate },
        in_sample_rate, 
        in_sample_fmt,
        in_ch_layout_desc
    );
    if ( ret < 0 ) {
        return ret;
    }

    ret = _filter_graph->addAudioBufferSinkFilter(
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
                    << "aformat=sample_fmts=" << av_get_sample_fmt_name(_out_sample_fmt) << ":channel_layouts=" << out_ch_layout_desc
                    << ",aresample=" << _out_sample_rate
                    << "[" << FILTER_ABUFFER_SINK_NAME << "]";
    ret = _filter_graph->parse(filter_descr_ss.str());
    if ( ret < 0 ) {
        return ret;
    }
    
    ret = _filter_graph->configure();
    if ( ret < 0 ) {
        return ret;
    }
    
    _fifo = new AudioFifo();
    ret = _fifo->init(_out_sample_rate, _out_sample_fmt, _out_nb_channels, 1);
    if ( ret < 0 ) {
        return ret;
    }
    
    _out_filt_frame = av_frame_alloc();
    _out_enc_pkt = av_packet_alloc();
    
    _out_fifo_frame = av_frame_alloc();
    _out_fifo_frame->format = _out_sample_fmt;
    _out_fifo_frame->sample_rate = _out_sample_rate;
    _out_fifo_frame->ch_layout = _out_ch_layout;
    _out_fifo_frame->nb_samples = _out_frame_size;
    av_frame_get_buffer(_out_fifo_frame, 1);
    return 0;
}

int AudioWriter::open() {
    int ret = _muxer->open();
    if ( ret < 0 ) return ret;
    return _muxer->writeHeader();
}

int AudioWriter::write(void *buffer, int buffer_size) {
    AVFrame *in_frame = av_frame_alloc();
    in_frame->format = _in_sample_fmt;
    in_frame->sample_rate = _in_sample_rate;
    in_frame->ch_layout = _in_ch_layout;
    in_frame->nb_samples = buffer_size / (av_get_bytes_per_sample(_in_sample_fmt) * _in_nb_channels);
    int ret = avcodec_fill_audio_frame(in_frame, _in_nb_channels, _in_sample_fmt, (uint8_t*)buffer, buffer_size, 1);
    if ( ret < 0 ) {
        av_frame_free(&in_frame);
        return ret;
    } 
    
    in_frame->pts = _in_pts;
    _in_pts += in_frame->nb_samples;
    
    ret = write(in_frame);
    av_frame_free(&in_frame);
    return ret;
}

int AudioWriter::write(AVFrame* frame) {
    if ( !frame ) {
        throw_error("AudioWriter::write - Frame can't be nullptr");
    }
    
    int ret = AudioUtils::processFrame(frame, _filter_graph, FILTER_ABUFFER_SRC_NAME, FILTER_ABUFFER_SINK_NAME, _out_filt_frame, _fifo, _out_fifo_frame, _encoder, _out_enc_pkt, [&](AVPacket* enc_pkt) {
        return _muxer->writePacket(enc_pkt);
    });
    
    if ( ret < 0 && ret != AVERROR(EAGAIN) ) {
        return ret;
    }
    return 0;
}

int AudioWriter::close() {
    int ret = AudioUtils::processFrame(nullptr, _filter_graph, FILTER_ABUFFER_SRC_NAME, FILTER_ABUFFER_SINK_NAME, _out_filt_frame, _fifo, _out_fifo_frame, _encoder, _out_enc_pkt, [&](AVPacket* enc_pkt) {
        return _muxer->writePacket(enc_pkt);
    });
    
    if ( ret < 0 && ret != AVERROR_EOF ) {
        return ret;
    }
    return _muxer->writeTrailer();
}


}
