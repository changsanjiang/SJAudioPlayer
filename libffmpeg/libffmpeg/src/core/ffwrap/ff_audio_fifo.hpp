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

#ifndef FFAV_AudioFifo_hpp
#define FFAV_AudioFifo_hpp

#include <stdint.h>
#include "ff_types.hpp"

namespace FFAV {

class AudioFifo {
public:
    AudioFifo();
    ~AudioFifo();

    int init(int sample_rate, AVSampleFormat sample_fmt, int nb_channels, int nb_samples);

    int write(void** data, int nb_samples, int64_t pts);
    int read(void** data, int nb_samples, int64_t *pts_ptr);
    void clear();
    
    int getNumberOfSamples();  
    int64_t getNextPts();
    int64_t getEndPts();

private:
    void release();

private:
    AVAudioFifo* _fifo { nullptr };
    AVSampleFormat _sample_fmt;
    int _sample_rate;
    int _nb_channels;
    int64_t _next_pts { AV_NOPTS_VALUE };
};

}
#endif //FFAV_AudioFifo_hpp
