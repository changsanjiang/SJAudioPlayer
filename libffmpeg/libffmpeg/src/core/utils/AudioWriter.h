//
// Created on 2025/3/11.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PRIVATE_FFMPEG_HARMONY_OS_AUDIOWRITER_H
#define PRIVATE_FFMPEG_HARMONY_OS_AUDIOWRITER_H

#include "AudioEncoder.h"
#include "AudioFifo.h"
#include "AudioMuxer.h"
#include "FilterGraph.h"
#include <cstdint>

namespace FFAV {

/**
 * @class AudioWriter
 * @brief 将 PCM 音频数据写入到指定的封装格式文件中。
 *
 * 该类用于接收原始 PCM 数据，将其编码为目标格式（如 AAC、MP3、WAV），并封装到目标文件中。
 * 内部会使用 AudioEncoder 进行音频编码，并通过 AudioMuxer 进行封装和写入。
 *
 * 主要功能：
 * - 接收 PCM 音频数据并组织为 AVFrame。
 * - 调用 AudioEncoder 进行音频编码。
 * - 调用 AudioMuxer 进行封装并写入目标文件。
 *
 * 使用示例：
 * ```
 * AudioWriter writer;
 * writer.init("output.mp4", AV_SAMPLE_FMT_FLTP, 44100, 2);
 * writer.open();
 * writer.write(pcm_buffer, buffer_size);
 * writer.close();
 * ```
 * @note **注意:** 目标文件名必须包含正确的文件后缀（如 `.mp4`、`.aac`、`.wav`），以便自动推测封装格式。
 */
class AudioWriter {

public:
    AudioWriter();
    ~AudioWriter();
    
    int init(
        const std::string& out_file_path, 
        // AVCodecID codec_id, 
        AVSampleFormat in_sample_fmt,
        int in_sample_rate,
        int in_nb_channels
    );
    
    int open();
    int write(AVFrame* frame);
    int write(void *buffer, int buffer_size);
    int close();
    
private:
    AudioEncoder* encoder { nullptr };
    AudioFifo* fifo { nullptr };
    FilterGraph* filter_graph { nullptr };
    AudioMuxer* muxer { nullptr };
    
    AVSampleFormat in_sample_fmt;
    int in_sample_rate;
    int in_nb_channels;
    AVChannelLayout in_ch_layout;
    int64_t in_pts { 0 };
    
    AVSampleFormat out_sample_fmt; 
    int out_sample_rate; 
    int out_nb_channels; 
    AVChannelLayout out_ch_layout;
    int out_frame_size;
    
    AVFrame* filter_out_frame { nullptr };
    AVFrame* fifo_out_frame { nullptr };
    AVPacket* out_pkt { nullptr };
    
    int consumeAbufferSink();
    int consumeFifo(bool eos);
};

}

#endif //PRIVATE_FFMPEG_HARMONY_OS_AUDIOWRITER_H
