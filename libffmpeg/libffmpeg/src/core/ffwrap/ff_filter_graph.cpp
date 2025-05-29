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
// Created by sj on 2025/1/10.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "ff_filter_graph.hpp"
#include <sstream>
#include "ff_includes.hpp"

namespace FFAV {

FilterGraph::FilterGraph() = default;
FilterGraph::~FilterGraph() { release(); }

int FilterGraph::init() {
    _filter_graph = avfilter_graph_alloc();
    if ( _filter_graph == nullptr ) {
        return AVERROR(ENOMEM);
    }
    return 0;
}

int FilterGraph::addAudioBufferSourceFilter(const std::string& name, const AVRational time_base, int sample_rate, AVSampleFormat sample_fmt, const std::string& ch_layout_desc) {
    if ( _filter_graph == nullptr ) {
        return AVERROR_INVALIDDATA;
    }
        
    if ( _abuffer == nullptr ) {
        _abuffer = avfilter_get_by_name("abuffer");
    }

    if ( _abuffer == nullptr ) {
        return AVERROR_FILTER_NOT_FOUND;
    }
    
    std::stringstream src_ss;
    src_ss  << "time_base=" << time_base.num << "/" << time_base.den
            << ":sample_rate=" << sample_rate
            << ":sample_fmt=" << av_get_sample_fmt_name(sample_fmt)
            << ":channel_layout=" << ch_layout_desc;

    AVFilterContext *abuffersrc_ctx = nullptr;
    int ret = avfilter_graph_create_filter(&abuffersrc_ctx, _abuffer, name.c_str(), src_ss.str().c_str(), NULL, _filter_graph);
    if ( ret < 0 ) {
        return ret;
    }

    return addBufferSourceFilter(name, abuffersrc_ctx);
}

int FilterGraph::addVideoBufferSourceFilter(const std::string& name, const AVRational time_base, int width, int height, AVPixelFormat pix_fmt, const AVRational sar, const AVRational frame_rate) {
    if ( _filter_graph == nullptr ) {
        return AVERROR_INVALIDDATA;
    }
    
    if ( _vbuffer == nullptr ) {
        _vbuffer = avfilter_get_by_name("buffer");
    }

    if ( _vbuffer == nullptr ) {
        return AVERROR_FILTER_NOT_FOUND;
    }
    
    std::stringstream src_ss;
    src_ss  << "video_size=" << width << "x" << height
            << ":pix_fmt=" << pix_fmt
            << ":time_base=" << time_base.num << "/" << time_base.den
            << ":pixel_aspect=" << sar.num << "/" << sar.den;
    if ( frame_rate.num ) {
        src_ss << ":frame_rate=" << frame_rate.num << "/" << frame_rate.den;
    }

    AVFilterContext *vbuffersrc_ctx = nullptr;
    int ret = avfilter_graph_create_filter(&vbuffersrc_ctx, _vbuffer, name.c_str(), src_ss.str().c_str(), NULL, _filter_graph);
    if ( ret < 0 ) {
        return ret;
    }

    return addBufferSourceFilter(name, vbuffersrc_ctx);
}

int FilterGraph::addBufferSourceFilter(const std::string& name, AVMediaType type, const AVBufferSrcParameters* _Nonnull params) {
    switch(type) {
    case AVMEDIA_TYPE_VIDEO:
        return addVideoBufferSourceFilter(name, params->time_base, params->width, params->height, static_cast<AVPixelFormat>(params->format), params->sample_aspect_ratio, params->frame_rate);
    case AVMEDIA_TYPE_AUDIO: {
        // get channel layout desc
        char ch_layout_desc[64];
        av_channel_layout_describe(&params->ch_layout, ch_layout_desc, sizeof(ch_layout_desc));
        return addAudioBufferSourceFilter(name, params->time_base, params->sample_rate, static_cast<AVSampleFormat>(params->format), ch_layout_desc);
    }
    case AVMEDIA_TYPE_UNKNOWN:
    case AVMEDIA_TYPE_DATA:
    case AVMEDIA_TYPE_SUBTITLE:
    case AVMEDIA_TYPE_ATTACHMENT:
    case AVMEDIA_TYPE_NB:
        return AVERROR_INVALIDDATA;
    }
}

int FilterGraph::addAudioBufferSinkFilter(const std::string& name, const int sample_rate, const AVSampleFormat sample_fmt, const std::string& channel_layout) {
    int sample_rates[] = { sample_rate, -1 };
    AVSampleFormat sample_fmts[] = { sample_fmt, AV_SAMPLE_FMT_NONE };
    return addAudioBufferSinkFilter(name, sample_rates, sample_fmts, channel_layout);
}

int FilterGraph::addAudioBufferSinkFilter(const std::string& name, const int* _Nullable sample_rates, const AVSampleFormat* _Nullable sample_fmts, const std::string& channel_layout) {
    if ( _filter_graph == nullptr ) {
        return AVERROR_INVALIDDATA;
    }

    if ( _abuffersink == nullptr ) {
        _abuffersink = avfilter_get_by_name("abuffersink");
    }
    
    if ( _abuffersink == nullptr ) {
        return AVERROR_FILTER_NOT_FOUND;
    }

    AVFilterContext *abuffersink_ctx = nullptr;
    int ret = avfilter_graph_create_filter(&abuffersink_ctx, _abuffersink, name.c_str(), NULL, NULL, _filter_graph);
    if ( ret < 0 ) {
        return ret;
    }

    ret = av_opt_set_int_list(abuffersink_ctx, "sample_rates", sample_rates, -1, AV_OPT_SEARCH_CHILDREN);
    if ( ret < 0 ) {
        return ret;
    }

    ret = av_opt_set_int_list(abuffersink_ctx, "sample_fmts", sample_fmts, AV_SAMPLE_FMT_NONE, AV_OPT_SEARCH_CHILDREN);
    if ( ret < 0 ) {
        return ret;
    }
    
    ret = av_opt_set(abuffersink_ctx, "ch_layouts", channel_layout.c_str(), AV_OPT_SEARCH_CHILDREN);
    if ( ret < 0 ) {
        return ret;
    }
    return addBufferSinkFilter(name, abuffersink_ctx);
}

int FilterGraph::addVideoBufferSinkFilter(const std::string& name, const AVPixelFormat* _Nullable pix_fmts) {
    if ( _filter_graph == nullptr ) {
        return AVERROR_INVALIDDATA;
    }

    if ( _vbuffersink == nullptr ) {
        _vbuffersink = avfilter_get_by_name("buffersink");
    }
    
    if ( _vbuffersink == nullptr ) {
        return AVERROR_FILTER_NOT_FOUND;
    }

    AVFilterContext *vbuffersink_ctx = nullptr;
    int ret = avfilter_graph_create_filter(&vbuffersink_ctx, _vbuffersink, name.c_str(), NULL, NULL, _filter_graph);
    if ( ret < 0 ) {
        return ret;
    }
    
    ret = av_opt_set_int_list(vbuffersink_ctx, "pix_fmts", pix_fmts, AV_PIX_FMT_NONE, AV_OPT_SEARCH_CHILDREN);
    if ( ret < 0 ) {
        return ret;
    }

    return addBufferSinkFilter(name, vbuffersink_ctx);    
}

int FilterGraph::addBufferSourceFilter(const std::string& name, AVFilterContext* _Nonnull buffer_ctx) {
    AVFilterInOut *node = avfilter_inout_alloc();
    if ( node == nullptr ) {
        return AVERROR(ENOMEM);
    }

    node->name = av_strdup(name.c_str());
    node->filter_ctx = buffer_ctx;
    node->pad_idx = 0;
    node->next = NULL;
    
    if ( _outputs == nullptr ) {
        _outputs = node;
    }
    else {
        _lastOutput->next = node;
    }
    _lastOutput = node;
    return 0;
}

int FilterGraph::addBufferSinkFilter(const std::string& name, AVFilterContext* _Nonnull buffersink_ctx) {
    AVFilterInOut *node = avfilter_inout_alloc();
    if ( node == nullptr ) {
        return AVERROR(ENOMEM);
    }

    node->name = av_strdup(name.c_str());
    node->filter_ctx = buffersink_ctx;
    node->pad_idx = 0;
    node->next = NULL;
    
    if ( _inputs == nullptr ) {
        _inputs = node;
    }
    else {
        _lastInput->next = node;
    }
    _lastInput = node;
    return 0;
}

int FilterGraph::parse(const std::string& filter_descr, FilterGraph::ParseLinker linker) {
    int ret = avfilter_graph_parse_ptr(_filter_graph, filter_descr.c_str(), &_inputs, &_outputs, NULL);
    if ( ret < 0 ) {
        return ret;
    }
    
    if ( linker ) {
        ret = linker(this, _inputs, _outputs);
        if ( ret < 0 ) {
            return ret;
        }
    }

    avfilter_inout_free(&_inputs);
    avfilter_inout_free(&_outputs);
    _lastOutput = nullptr;
    _lastInput = nullptr;
    _abuffer = nullptr;
    _vbuffer = nullptr;
    _abuffersink = nullptr;
    _vbuffersink = nullptr;
    return 0;
}

int FilterGraph::createAudioBufferSourceFilter(const std::string& name, const AVRational time_base, int sample_rate, AVSampleFormat sample_fmt, const std::string& ch_layout_desc, AVFilterContext *_Nullable*_Nullable filter_ctx) {
    if ( _abuffer == nullptr ) {
        _abuffer = avfilter_get_by_name("abuffer");
    }

    if ( _abuffer == nullptr ) {
        return AVERROR_FILTER_NOT_FOUND;
    }
    
    std::stringstream src_ss;
    src_ss  << "time_base=" << time_base.num << "/" << time_base.den
            << ":sample_rate=" << sample_rate
            << ":sample_fmt=" << av_get_sample_fmt_name(sample_fmt)
            << ":channel_layout=" << ch_layout_desc;

    AVFilterContext *abuffersrc_ctx = nullptr;
    int ret = avfilter_graph_create_filter(&abuffersrc_ctx, _abuffer, name.c_str(), src_ss.str().c_str(), NULL, _filter_graph);
    if ( ret < 0 ) {
        return ret;
    }
    
    if ( filter_ctx ) *filter_ctx = abuffersrc_ctx;
    return 0;
}

int FilterGraph::createVideoBufferSourceFilter(const std::string& name, const AVRational time_base, int width, int height, AVPixelFormat pix_fmt, const AVRational sar, const AVRational frame_rate, AVFilterContext *_Nullable*_Nullable filter_ctx) {
    if ( _vbuffer == nullptr ) {
        _vbuffer = avfilter_get_by_name("buffer");
    }

    if ( _vbuffer == nullptr ) {
        return AVERROR_FILTER_NOT_FOUND;
    }
    
    std::stringstream src_ss;
    src_ss  << "video_size=" << width << "x" << height
            << ":pix_fmt=" << pix_fmt
            << ":time_base=" << time_base.num << "/" << time_base.den
            << ":pixel_aspect=" << sar.num << "/" << sar.den;
    if ( frame_rate.num ) {
        src_ss << ":frame_rate=" << frame_rate.num << "/" << frame_rate.den;
    }

    AVFilterContext *vbuffersrc_ctx = nullptr;
    int ret = avfilter_graph_create_filter(&vbuffersrc_ctx, _vbuffer, name.c_str(), src_ss.str().c_str(), NULL, _filter_graph);
    if ( ret < 0 ) {
        return ret;
    }
    
    if ( filter_ctx ) *filter_ctx = vbuffersrc_ctx;
    return 0;
}

int FilterGraph::createBufferSourceFilter(const std::string& name, AVMediaType type, const AVBufferSrcParameters* _Nonnull params, AVFilterContext *_Nullable*_Nullable filter_ctx) {
    switch(type) {
    case AVMEDIA_TYPE_VIDEO:
        return createVideoBufferSourceFilter(name, params->time_base, params->width, params->height, static_cast<AVPixelFormat>(params->format), params->sample_aspect_ratio, params->frame_rate, filter_ctx);
    case AVMEDIA_TYPE_AUDIO: {
        // get channel layout desc
        char ch_layout_desc[64];
        av_channel_layout_describe(&params->ch_layout, ch_layout_desc, sizeof(ch_layout_desc));
        return createAudioBufferSourceFilter(name, params->time_base, params->sample_rate, static_cast<AVSampleFormat>(params->format), ch_layout_desc, filter_ctx);
    }
    case AVMEDIA_TYPE_UNKNOWN:
    case AVMEDIA_TYPE_DATA:
    case AVMEDIA_TYPE_SUBTITLE:
    case AVMEDIA_TYPE_ATTACHMENT:
    case AVMEDIA_TYPE_NB:
        return AVERROR_INVALIDDATA;
    }
}

int FilterGraph::createAudioBufferSinkFilter(const std::string& name, const int sample_rate, const AVSampleFormat sample_fmt, const std::string& ch_layout_desc, AVFilterContext *_Nullable*_Nullable filter_ctx) {
    if ( _abuffersink == nullptr ) {
        _abuffersink = avfilter_get_by_name("abuffersink");
    }
    
    if ( _abuffersink == nullptr ) {
        return AVERROR_FILTER_NOT_FOUND;
    }

    AVFilterContext *abuffersink_ctx = nullptr;
    int ret = avfilter_graph_create_filter(&abuffersink_ctx, _abuffersink, name.c_str(), NULL, NULL, _filter_graph);
    if ( ret < 0 ) {
        return ret;
    }
    
    int sample_rates[] = { sample_rate, -1 };
    ret = av_opt_set_int_list(abuffersink_ctx, "sample_rates", sample_rates, -1, AV_OPT_SEARCH_CHILDREN);
    if ( ret < 0 ) {
        return ret;
    }
    
    AVSampleFormat sample_fmts[] = { sample_fmt, AV_SAMPLE_FMT_NONE };
    ret = av_opt_set_int_list(abuffersink_ctx, "sample_fmts", sample_fmts, AV_SAMPLE_FMT_NONE, AV_OPT_SEARCH_CHILDREN);
    if ( ret < 0 ) {
        return ret;
    }
    
    ret = av_opt_set(abuffersink_ctx, "ch_layouts", ch_layout_desc.c_str(), AV_OPT_SEARCH_CHILDREN);
    if ( ret < 0 ) {
        return ret;
    }
    
    if ( filter_ctx ) *filter_ctx = abuffersink_ctx;
    return 0;
}

int FilterGraph::configure() {
    return avfilter_graph_config(_filter_graph, NULL);
}

int FilterGraph::addFrame(const std::string& src_name, AVFrame* _Nullable frame, int flags) {
    AVFilterContext *buffer_ctx = avfilter_graph_get_filter(_filter_graph, src_name.c_str());
    if ( buffer_ctx == nullptr ) {
        return AVERROR_FILTER_NOT_FOUND;
    }
    
    return av_buffersrc_add_frame_flags(buffer_ctx, frame, flags);
}

int FilterGraph::getFrame(const std::string& sink_name, AVFrame* _Nonnull frame) {
    AVFilterContext *buffersink_ctx = avfilter_graph_get_filter(_filter_graph, sink_name.c_str());
    if ( buffersink_ctx == nullptr ) {
        return AVERROR_FILTER_NOT_FOUND;
    }
    
    return av_buffersink_get_frame(buffersink_ctx, frame);
}

int FilterGraph::sendCommand(const std::string& target_name, const std::string& cmd, const std::string& arg, int flags) {
    return avfilter_graph_send_command(_filter_graph, target_name.c_str(), cmd.c_str(), arg.c_str(), nullptr, 0, flags);
}

void FilterGraph::release() {
    if ( _outputs != nullptr ) {
        avfilter_inout_free(&_outputs);
    }
    
    if ( _inputs != nullptr ) {
        avfilter_inout_free(&_inputs);
    }

    if ( _filter_graph != nullptr ) {
        avfilter_graph_free(&_filter_graph);
    }
}

}
