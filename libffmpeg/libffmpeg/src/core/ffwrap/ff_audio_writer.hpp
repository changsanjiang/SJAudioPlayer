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

#ifndef FFAV_AudioWriter_hpp
#define FFAV_AudioWriter_hpp

#include "ff_types.hpp"
#include <cstdint>
#include <string>

namespace FFAV {

class AudioEncoder;
class AudioFifo;
class FilterGraph;
class AudioMuxer;

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
    AudioEncoder* _encoder { nullptr };
    AudioFifo* _fifo { nullptr };
    FilterGraph* _filter_graph { nullptr };
    AudioMuxer* _muxer { nullptr };

    AVSampleFormat _in_sample_fmt;
    int _in_sample_rate;
    int _in_nb_channels;
    AVChannelLayout _in_ch_layout;
    int64_t _in_pts { 0 };

    AVSampleFormat _out_sample_fmt;
    int _out_sample_rate;
    int _out_nb_channels;
    AVChannelLayout _out_ch_layout;
    int _out_frame_size;

    AVFrame *_in_frame { nullptr };
    AVFrame* _out_filt_frame { nullptr };
    AVFrame* _out_fifo_frame { nullptr };
    AVPacket* _out_enc_pkt { nullptr };

    bool _sent_encoder_eos { false };
};

}

#endif //FFAV_AudioWriter_hpp
