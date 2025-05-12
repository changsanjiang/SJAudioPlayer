//
// Created on 2025/1/15.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef FFMPEGPROJ_AUDIOFIFO_H
#define FFMPEGPROJ_AUDIOFIFO_H

#include <stdint.h>
extern "C" {
#include "libavcodec/avcodec.h"
#include "libavutil/audio_fifo.h"
#include "libavutil/samplefmt.h"
#include "libavutil/avutil.h"
#include "libavutil/rational.h"
}

namespace FFAV {

class AudioFifo {
public:
    AudioFifo();
    ~AudioFifo();

    int init(AVSampleFormat sample_fmt, int nb_channels, int nb_samples);

    int write(void** data, int nb_samples, int64_t pts);
    int read(void** data, int nb_samples, int64_t *pts_ptr);
    void clear();
    
    int getNumberOfSamples();  
    int64_t getNextPts();
    int64_t getEndPts();

private:
    AVAudioFifo* fifo = nullptr;        
    int64_t next_pts = AV_NOPTS_VALUE; // in time_base
    void release();
};

}
#endif //FFMPEGPROJ_AUDIOFIFO_H
