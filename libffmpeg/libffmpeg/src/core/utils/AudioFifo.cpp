//
// Created on 2025/1/15.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "AudioFifo.h"
#include <stdexcept>
#include <stdint.h>

namespace FFAV {

AudioFifo::AudioFifo() = default;
AudioFifo::~AudioFifo() { release(); }

int AudioFifo::init(AVSampleFormat sample_fmt, int nb_channels, int nb_samples) {
    if ( fifo != nullptr ) {
        throw std::runtime_error("AudioFifo is already initialized");
    }
    
    fifo = av_audio_fifo_alloc(sample_fmt, nb_channels, nb_samples);
    if ( fifo == nullptr ) {
        return AVERROR(ENOMEM);
    }    
    return 0;
}

int AudioFifo::write(void** data, int nb_samples, int64_t pts) {
    if ( fifo == nullptr ) {
        throw std::runtime_error("AVAudioFifo is not initialized");
    }
    if ( next_pts == AV_NOPTS_VALUE ) {
        next_pts = pts;
    }
    return av_audio_fifo_write(fifo, data, nb_samples);
}

int AudioFifo::read(void** data, int nb_samples, int64_t* pts_ptr) {
    if ( fifo == nullptr ) {
        throw std::runtime_error("AVAudioFifo is not initialized");
    }
    int ret = av_audio_fifo_read(fifo, data, nb_samples);
    if ( ret > 0 ) {
        if ( pts_ptr ) {
            *pts_ptr = next_pts;
        }
        next_pts += ret;
    }
    return ret;
}

void AudioFifo::clear() {
    if ( fifo != nullptr ) {
        next_pts = AV_NOPTS_VALUE;
        av_audio_fifo_reset(fifo);
    }
}

int AudioFifo::getNumberOfSamples() {
    return fifo != nullptr ? av_audio_fifo_size(fifo) : 0;
}

int64_t AudioFifo::getNextPts() {
    return next_pts;
}

int64_t AudioFifo::getEndPts() {
    if ( next_pts != AV_NOPTS_VALUE ) {
        return next_pts + getNumberOfSamples();
    }
    return AV_NOPTS_VALUE;
}

void AudioFifo::release() {
    if ( fifo != nullptr ) {
        av_audio_fifo_free(fifo);
        fifo = nullptr;
    }
}

}
