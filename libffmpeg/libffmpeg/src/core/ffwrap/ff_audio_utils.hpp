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
// Created by sj on 2025/1/17.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef FFAV_AudioUtils_hpp
#define FFAV_AudioUtils_hpp

#include "ff_types.hpp"
#include <functional>

namespace FFAV {

class MediaDecoder;
class FilterGraph;

class AudioFifo;
class AudioEncoder;

class AudioUtils {
public:
    // "处理一帧"的通用回调
    using FrameCallback = std::function<int(AVFrame* _Nonnull frame)>;
    using PacketCallback = std::function<int(AVPacket* _Nonnull packet)>;
    
    /** 转码:
     +---------+     +--------------+     +------+
     | Decoder | --> | FilterGraph  | --> | FIFO |
     +---------+     +--------------+     +------+
     */
    static int processPacket(
        AVPacket* _Nullable pkt,    // input pkt or nullptr(flush)
        MediaDecoder* _Nonnull decoder,
        AVFrame* _Nonnull dec_frame,    // reused: output decoded frame
        FilterGraph* _Nonnull filter_graph,
        const std::string& buf_src_name,
        const std::string& buf_sink_name,
        AVFrame* _Nonnull filt_frame, // reused: output sink filter frame
        FrameCallback callback
    );
    
    /** 编码:
     +--------------+     +------+     +---------+
     | FilterGraph  | --> | FIFO | --> | Encoder |
     +--------------+     +------+     +---------+
     */
    static int processFrame(
        AVFrame* _Nullable frame, // input frame or nullptr(flush)
        FilterGraph* _Nonnull filter_graph,
        const std::string& buf_src_name,
        const std::string& buf_sink_name,
        AVFrame* _Nonnull filt_frame, // reused: output sink filter frame
        AudioFifo* _Nonnull fifo,
        AVFrame* _Nonnull fifo_frame, // reused: output fifo frame
        AudioEncoder* _Nonnull encoder,
        AVPacket* _Nonnull enc_pkt, // reused: output encoded pkt
        PacketCallback callback
    );

private:
    /// 从 decoder 拉数据
    static int drainDecodedFrames(
        MediaDecoder* _Nonnull decoder,
        AVFrame* _Nonnull dec_frame,
        FrameCallback callback
    );
    
    /// 从 filter sink 拉数据
    static int drainFilteredFrames(
        FilterGraph* _Nonnull filter_graph,
        AVFrame* _Nonnull filt_frame,
        const std::string& buf_sink_name,
        FrameCallback callback
    );
    
    static int drainFifo(
        AudioFifo* _Nonnull fifo,
        int frame_size, // 指定每帧的样本数
        bool eof,
        AVFrame* _Nonnull fifo_frame,
        FrameCallback callback
    );
    
    static int drainEncodedPackets(
        AudioEncoder* _Nonnull encoder,
        AVPacket* _Nonnull enc_pkt,
        PacketCallback callback
    );
};

}

#endif //FFAV_AudioUtils_hpp

