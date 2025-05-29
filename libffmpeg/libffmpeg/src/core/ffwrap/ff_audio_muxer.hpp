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

#ifndef FFAV_AudioMuxer_hpp
#define FFAV_AudioMuxer_hpp

#include <string>
#include "ff_types.hpp"

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
    std::string _file_path;
    AVFormatContext* _fmt_ctx { nullptr };
    AVRational _time_base;
    AVStream* _stream { nullptr };
};

}

#endif //FFAV_AudioMuxer_hpp
