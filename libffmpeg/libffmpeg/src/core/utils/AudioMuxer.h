//
// Created on 2025/3/11.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef PRIVATE_FFMPEG_HARMONY_OS_AUDIOMUXER_H
#define PRIVATE_FFMPEG_HARMONY_OS_AUDIOMUXER_H

#include <string>

extern "C" {
#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libavcodec/codec.h"
#include "libavutil/frame.h"
#include "libavutil/rational.h"
}

namespace FFAV {

/**
 * @class AudioMuxer
 * @brief 负责音频数据的封装，将编码后的音频数据写入文件。
 *
 * 该类用于管理音频文件的封装过程。
 * 它接受编码后的音频数据（AVPacket），并将其写入封装格式的文件中。
 *
 * 主要功能：
 * - 处理音频流的封装，确保正确的时间戳处理。
 * - 负责文件的打开、写入音频帧以及最终的关闭。
 *
 * 使用示例：
 * ```
 * AudioMuxer muxer;
 * muxer.init("output.mp4", codec_ctx);
 * muxer.open();
 * muxer.writeHeader();
 * muxer.writePacket(encoded_packet);
 * muxer.writeTrailer();
 * ```
 */
class AudioMuxer {
public:
    AudioMuxer();
    ~AudioMuxer();

    /// 初始化封装器
    int init(const std::string& file_path, AVCodecContext* codec_ctx);
    int init(const std::string& file_path, AVCodecContext* codec_ctx, AVFormatContext* fmt_ctx);

    /// 打开文件
    int open();

    /// 写文件头
    int writeHeader();

    /// 接收编码后的音频数据并写入文件
    int writePacket(AVPacket* pkt);

    /// 结束封装
    int writeTrailer();
    
private:
    std::string file_path;
    AVFormatContext* fmt_ctx { nullptr };
    AVRational time_base;
    AVStream* stream { nullptr };
};

}

#endif //PRIVATE_FFMPEG_HARMONY_OS_AUDIOMUXER_H
