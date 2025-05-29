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

#include "ff_audio_encoder.hpp"
#include "ff_includes.hpp"
#include "ff_throw.hpp"
#include <sstream>

namespace FFAV {

/// @param sample_fmts  array of supported sample formats, or NULL if unknown, array is terminated by AV_SAMPLE_FMT_NONE
static AVSampleFormat find_best_sample_fmt(const AVSampleFormat *sample_fmts, AVSampleFormat preferred_sample_fmt) {
    if ( !sample_fmts || sample_fmts[0] == AV_SAMPLE_FMT_NONE ) {
        return preferred_sample_fmt;
    }

    AVSampleFormat best_fmt = AV_SAMPLE_FMT_NONE;
    AVSampleFormat closest_fmt = sample_fmts[0];

    for ( int idx = 0; sample_fmts[idx] != AV_SAMPLE_FMT_NONE; idx++ ) {
        AVSampleFormat cur_fmt = sample_fmts[idx];

        // 如果完全匹配，直接返回
        if ( cur_fmt == preferred_sample_fmt ) {
            return cur_fmt;
        }

        // 优先选择通用格式（U8, S16, S32, FLTP）
        if ( cur_fmt == AV_SAMPLE_FMT_U8 || cur_fmt == AV_SAMPLE_FMT_S16 ||
             cur_fmt == AV_SAMPLE_FMT_S32 || cur_fmt == AV_SAMPLE_FMT_FLTP ) {
            best_fmt = cur_fmt;
        }

        // 记录最接近的格式（与 preferred_sample_fmt 类型最相似）
        if ( av_get_bytes_per_sample(cur_fmt) == av_get_bytes_per_sample(preferred_sample_fmt) ) {
            closest_fmt = cur_fmt;
        }
    }

    // 如果找到最佳匹配的格式，则返回，否则返回最接近的格式
    return best_fmt != AV_SAMPLE_FMT_NONE ? best_fmt : closest_fmt;
}

/// @param supported_samplerates    array of supported audio sample rates, or NULL if unknown, array is terminated by 0
static int find_best_sample_rate(const int *supported_samplerates, int preferred_sample_rate) {
    if ( !supported_samplerates || supported_samplerates[0] == 0 ) {
        return preferred_sample_rate;
    }

    int best_sample_rate = supported_samplerates[0];
    int closest_sample_rate = supported_samplerates[0];
    int min_diff = abs(preferred_sample_rate - best_sample_rate);

    for ( int idx = 0; supported_samplerates[idx] != 0; idx++ ) {
        int cur_sample_rate = supported_samplerates[idx];

        // 完全匹配，直接返回
        if ( cur_sample_rate == preferred_sample_rate ) {
            return cur_sample_rate;
        }

        // 优先选择 44100, 48000, 32000
        if ( cur_sample_rate == 44100 || cur_sample_rate == 48000 || cur_sample_rate == 32000 ) {
            best_sample_rate = cur_sample_rate;
        }

        // 记录最接近的采样率
        int cur_diff = abs(preferred_sample_rate - cur_sample_rate);
        if ( cur_diff < min_diff ) {
            closest_sample_rate = cur_sample_rate;
            min_diff = cur_diff;
        }
    }

    // 优先返回 `44100, 48000, 32000` 之一，如果它们存在，否则返回最接近的值
    return best_sample_rate > 0 ? best_sample_rate : closest_sample_rate;
}

/// @param ch_layouts   Array of supported channel layouts, terminated with a zeroed layout.
static AVChannelLayout find_best_channel_layout(const AVChannelLayout *ch_layouts, int preferred_nb_channels) {
    // 如果 `ch_layouts` 为空或者第一个元素 nb_channels 为 0，直接返回 `preferred_ch_layout`
    if ( !ch_layouts || ch_layouts[0].nb_channels == 0 ) {
        AVChannelLayout ch_layout;
        av_channel_layout_default(&ch_layout, preferred_nb_channels);
        return ch_layout;
    }

    const AVChannelLayout* best_ch_layout = nullptr;
    const AVChannelLayout* closest_smaller = nullptr;
    const AVChannelLayout* closest_larger = nullptr;

    for ( int idx = 0; ch_layouts[idx].nb_channels != 0; idx++ ) {
        const AVChannelLayout* cur_ch_layout = &ch_layouts[idx];

        // 如果完全匹配，直接返回
        if ( cur_ch_layout->nb_channels == preferred_nb_channels ) {
            return *cur_ch_layout;
        }

        // 记录最接近但小于 preferred_nb_channels 的
        if ( cur_ch_layout->nb_channels < preferred_nb_channels ) {
            if ( !closest_smaller || cur_ch_layout->nb_channels > closest_smaller->nb_channels ) {
                closest_smaller = cur_ch_layout;
            }
        }

        // 记录最接近但大于 preferred_nb_channels 的
        if ( cur_ch_layout->nb_channels > preferred_nb_channels ) {
            if ( !closest_larger || cur_ch_layout->nb_channels < closest_larger->nb_channels ) {
                closest_larger = cur_ch_layout;
            }
        }
    }

    // 选择最优的布局：优先选小但最接近的，其次选大但最接近的，最后选第一个
    best_ch_layout = closest_smaller ? closest_smaller : (closest_larger ? closest_larger : &ch_layouts[0]);
    return *best_ch_layout;  // 直接返回 `AVChannelLayout` 值，避免悬空指针问题
}


AudioEncoder::AudioEncoder() {

}

AudioEncoder::~AudioEncoder() {
    if ( _codec_ctx ) {
        avcodec_free_context(&_codec_ctx);
    }
}

int AudioEncoder::init(
    const AVCodec *codec,
    AVSampleFormat preferred_sample_fmt,
    int32_t preferred_sample_rate,
    int preferred_nb_channels,
    int bit_rate
) {
    if ( _codec_ctx != nullptr ) {
        throw_error("AudioEncoder::init - AudioEncoder is already initialized");
    }
    
    _codec_ctx = avcodec_alloc_context3(codec);
    if ( !_codec_ctx ) return AVERROR(ENOMEM);

    // Set encoder parameters
    _codec_ctx->sample_fmt = find_best_sample_fmt(codec->sample_fmts, preferred_sample_fmt);
    _codec_ctx->sample_rate = find_best_sample_rate(codec->supported_samplerates, preferred_sample_rate);
    _codec_ctx->ch_layout = find_best_channel_layout(codec->ch_layouts, preferred_nb_channels);
    _codec_ctx->bit_rate = bit_rate;
    _codec_ctx->time_base = (AVRational){ 1, _codec_ctx->sample_rate };

    return avcodec_open2(_codec_ctx, codec, nullptr);
}

int AudioEncoder::send(AVFrame* _Nullable frame) {
    if ( _codec_ctx == nullptr ) {
        throw_error("AudioEncoder::send - AudioEncoder is not initialized");
    }
    
    if ( frame && frame->pts != AV_NOPTS_VALUE ) {
        if ( _next_pts != AV_NOPTS_VALUE && frame->pts != _next_pts ) {
            std::ostringstream oss;
            oss << "AudioEncoder::send - Mismatch pts. Expected: " << _next_pts << ", Provided: " << frame->pts;
            throw_error(oss.str());
        }
        _next_pts = frame->pts + frame->nb_samples;
    }
    return avcodec_send_frame(_codec_ctx, frame);
}

int AudioEncoder::receive(AVPacket* _Nonnull pkt) {
    if ( _codec_ctx == nullptr ) {
        throw_error("AudioEncoder::receive - AudioEncoder is not initialized");
    }
    return avcodec_receive_packet(_codec_ctx, pkt);
}

AVSampleFormat AudioEncoder::getSampleFormat() const {
    if ( _codec_ctx == nullptr ) {
        throw_error("AudioEncoder::getSampleFormat - AudioEncoder is not initialized");
    }
    return _codec_ctx->sample_fmt;
}

int AudioEncoder::getSampleRate() const {
    if ( _codec_ctx == nullptr ) {
        throw_error("AudioEncoder::getSampleRate - AudioEncoder is not initialized");
    }
    return _codec_ctx->sample_rate;
}

int AudioEncoder::getChannels() const {
    if ( _codec_ctx == nullptr ) {
        throw_error("AudioEncoder::getChannels - AudioEncoder is not initialized");
    }
    return _codec_ctx->ch_layout.nb_channels;
}

AVChannelLayout AudioEncoder::getChannelLayout() const {
    if ( _codec_ctx == nullptr ) {
        throw_error("AudioEncoder::getChannelLayout - AudioEncoder is not initialized");
    }
    return _codec_ctx->ch_layout;
}

AVRational AudioEncoder::getTimeBase() const {
    if ( _codec_ctx == nullptr ) {
        throw_error("AudioEncoder::getTimeBase - AudioEncoder is not initialized");
    }
    return _codec_ctx->time_base;
}

int AudioEncoder::getFrameSize() const {
    if ( _codec_ctx == nullptr ) {
        throw_error("AudioEncoder::getFrameSize - AudioEncoder is not initialized");
    }
    return _codec_ctx->frame_size;
}

AVCodecContext* AudioEncoder::getCodecContext() const {
    if ( _codec_ctx == nullptr ) {
        throw_error("AudioEncoder::getCodecContext - AudioEncoder is not initialized");
    }
    return _codec_ctx;
}

}
