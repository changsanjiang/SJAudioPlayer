//
// Created on 2025/3/11.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PRIVATE_FFMPEG_HARMONY_OS_AUDIOENCODER_H
#define PRIVATE_FFMPEG_HARMONY_OS_AUDIOENCODER_H

#include <cstdint>
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/packet.h>
#include <libavcodec/avcodec.h>
#include <libavutil/frame.h>
#include <libavfilter/buffersrc.h>
#include <libavcodec/codec.h>
#include <libavutil/samplefmt.h>
#include <libavutil/channel_layout.h>
#include <libavutil/rational.h>
}

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
    
    int init(
        const AVCodec *encoder,
        AVSampleFormat preferred_sample_fmt,
        int32_t preferred_sample_rate,
        int preferred_nb_channels,
        int bit_rate = 128000
    );

    int send(AVFrame* frame); // eos 时传递 nullptr;
    
    int receive(AVPacket* pkt);
    
    AVCodecContext* getCodecContext();
    
    // 获取音频配置参数, 可能与传入的首选参数不一样, 不同编码支持的配置参数可能不包含传入的首选参数;
    AVSampleFormat getSampleFormat() const;
    int getSampleRate() const;
    int getChannels() const;
    AVChannelLayout getChannelLayout() const;
    AVRational getTimeBase() const;
    int getFrameSize(); // Number of samples per channel in an audio frame;
    
private:
    AVCodecContext* codec_ctx { nullptr };
};

}

#endif //PRIVATE_FFMPEG_HARMONY_OS_AUDIOENCODER_H
