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

#ifndef FFAV_AudioEncoder_hpp
#define FFAV_AudioEncoder_hpp

#include <cstdint>
#include "ff_types.hpp"

namespace FFAV {
/**
 * @class AudioEncoder
 * @brief 负责音频编码，将 PCM 数据转换为压缩格式。
 *
 * 该类基于 FFmpeg，提供音频编码功能。它接收 PCM 数据（AVFrame），
 * 使用指定的编码器（如 AAC、MP3）进行转换，并输出编码后的音频数据（AVPacket）。
 *
 * 主要功能：
 * - 处理 PCM 数据（AVFrame），转换为编码后的 AVPacket。
 *
 * 使用示例：
 * ```
 * AudioEncoder encoder;
 * encoder.init(encoder, AV_SAMPLE_FMT_FLTP, 44100, 2);
 * encoder.send(pcm_frame);
 * encoder.receive(output_packet);
 * ```
 */
class AudioEncoder {
public:
    AudioEncoder();
    ~AudioEncoder();
    
    AudioEncoder(AudioEncoder&&) noexcept = delete;
    AudioEncoder& operator=(AudioEncoder&&) noexcept = delete;

    int init(
        const AVCodec *encoder,
        AVSampleFormat preferred_sample_fmt,
        int32_t preferred_sample_rate,
        int preferred_nb_channels,
        int bit_rate = 128000
    );

    int send(AVFrame* frame); // eos 时传递 nullptr;
    
    int receive(AVPacket* pkt);
    
    // 获取音频配置参数, 可能与 init 传入的首选参数不一样, 不同编码器可能不支持某些首选参数;
    AVSampleFormat getSampleFormat() const;
    int getSampleRate() const;
    int getChannels() const;
    AVChannelLayout getChannelLayout() const;
    AVRational getTimeBase() const;
    int getFrameSize() const; // Number of samples per channel in an audio frame;
    
    AVCodecContext* getCodecContext() const;

private:
    AVCodecContext* _codec_ctx { nullptr };
    int64_t _next_pts { AV_NOPTS_VALUE };
};

}

#endif //FFAV_AudioEncoder_hpp
