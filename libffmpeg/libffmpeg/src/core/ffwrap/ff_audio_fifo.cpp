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
// Created by sj on 2025/1/15.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "ff_audio_fifo.hpp"
#include <sstream>
#include <stdint.h>
#include "ff_includes.hpp"
#include "ff_throw.hpp"

namespace FFAV {

AudioFifo::AudioFifo() { }
AudioFifo::~AudioFifo() { release(); }

int AudioFifo::init(int sample_rate, AVSampleFormat sample_fmt, int nb_channels, int nb_samples) {
    if ( _fifo != nullptr ) {
        throw_error("AudioFifo::init - AudioFifo is already initialized");
    }
    
    _fifo = av_audio_fifo_alloc(sample_fmt, nb_channels, nb_samples);
    if ( _fifo == nullptr ) {
        return AVERROR(ENOMEM);
    }
    
    _sample_rate = sample_rate;
    _sample_fmt = sample_fmt;
    _nb_channels = nb_channels;
    return 0;
}

int AudioFifo::write(void** data, int nb_samples, int64_t pts) {
    if ( _fifo == nullptr ) {
        throw_error("AudioFifo::write - AudioFifo is not initialized");
    }
    
    if ( pts != AV_NOPTS_VALUE && _next_pts != AV_NOPTS_VALUE ) {
        int64_t expected_pts = _next_pts + av_audio_fifo_size(_fifo);
        if ( pts < expected_pts ) {
            throw_error_fmt("AudioFifo::write - PTS out of order: incoming pts = %" PRId64 ", expected >= %" PRId64, pts, expected_pts);
        }
        
        if ( expected_pts < pts ) {
            int silence_samples = (int)(pts - expected_pts);
            printf("AudioFifo::write - PTS gap detected. Inserting %d silence samples. expected_pts = %" PRId64 ", incoming_pts = %" PRId64 "\n", silence_samples, expected_pts, pts);

            // 创建一个静音 AVFrame
            AVFrame *silence_frame = av_frame_alloc();
            silence_frame->sample_rate = _sample_rate;
            silence_frame->format = _sample_fmt;
            av_channel_layout_default(&silence_frame->ch_layout, _nb_channels);
            silence_frame->nb_samples = silence_samples;
            av_frame_get_buffer(silence_frame, 1);
            int sample_size = av_get_bytes_per_sample(_sample_fmt);
            if ( av_sample_fmt_is_planar(_sample_fmt) ) {
                for ( int ch = 0; ch < _nb_channels; ++ch ) {
                    memset(silence_frame->data[ch], 0, silence_samples * sample_size);
                }
            }
            else {
                memset(silence_frame->data[0], 0, silence_samples * sample_size * _nb_channels);
            }
            int ret = av_audio_fifo_write(_fifo, (void**)silence_frame->data, silence_samples);
            av_frame_free(&silence_frame);
            if ( ret < 0 ) {
                return ret;
            }
        }
    }
    
    if ( _next_pts == AV_NOPTS_VALUE ) {
        _next_pts = pts;
    }
    return av_audio_fifo_write(_fifo, data, nb_samples);
}

int AudioFifo::read(void** data, int nb_samples, int64_t* pts_ptr) {
    if ( _fifo == nullptr ) {
        throw_error("AudioFifo::read - AudioFifo is not initialized");
    }
    
    int ret = av_audio_fifo_read(_fifo, data, nb_samples);
    
    if ( ret > 0 ) {
        int samples_read = ret;
        if ( pts_ptr ) {
            *pts_ptr = _next_pts;
        }
        _next_pts += samples_read;
    }
    return ret;
}

void AudioFifo::clear() {
    if ( _fifo != nullptr ) {
        _next_pts = AV_NOPTS_VALUE;
        av_audio_fifo_reset(_fifo);
    }
}

int AudioFifo::getNumberOfSamples() {
    return _fifo != nullptr ? av_audio_fifo_size(_fifo) : 0;
}

int64_t AudioFifo::getNextPts() {
    return _next_pts;
}

int64_t AudioFifo::getEndPts() {
    return _next_pts != AV_NOPTS_VALUE ? _next_pts + getNumberOfSamples() : AV_NOPTS_VALUE;
}

void AudioFifo::release() {
    if ( _fifo != nullptr ) {
        av_audio_fifo_free(_fifo);
        _fifo = nullptr;
    }
}

}
