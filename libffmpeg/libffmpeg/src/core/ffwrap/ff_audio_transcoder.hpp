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
//  AudioTranscoder.h
//  LWZFFmpegLib
//
//  Created by sj on 2025/5/16.
//

#ifndef FFAV_AudioTranscoder_hpp
#define FFAV_AudioTranscoder_hpp

#include <string>
#include "ff_types.hpp"

namespace FFAV {
class MediaDecoder;
class FilterGraph;
class PacketQueue;
class AudioFifo;

/** 用于将传入的数据包转码为指定格式的pcm数据; */
class AudioTranscoder {
    
public:
    AudioTranscoder();
    ~AudioTranscoder();
    
    int init(AVStream *_Nonnull in_stream, int output_sample_rate, AVSampleFormat output_sample_format, int output_channels);
    
    enum class FlushMode {
        /// 不清理;
        None,
        /// 只清除pkt相关的缓存(pkts + decoder + filterGraph);
        PacketOnly,
        /// 清除所有缓存(pkts + decoder + filterGraph + fifo);
        Full,
    };
    
    /// pkt 加入转码队列;
    /// eof 时 packet 请传递 nullptr;
    int enqueue(AVPacket *_Nullable packet, FlushMode mode = FlushMode::None);
    
    /// 尝试转码出指定数量的音频数据;
    ///
    /// 数据足够时返回值与frame_capacity一致;
    /// 当 eof 时可能返回的样本数量小于指定的样本数量;
    /// 如果未到 eof 数据不满足指定的样本数量时返回 0;
    int tryTranscode(void *_Nonnull*_Nonnull out_data, int frame_capacity, int64_t *_Nullable out_pts, bool *_Nullable out_eof);
    
    bool isPacketBufferFull(); // 数据包缓冲是否已超过阈值
    
    int64_t getLastPresentationPacketEndPts(); // 最后呈现的数据包的endPts(PTS + duration); in stream time base;
    int64_t getFifoEndPts(); // 获取fifo缓冲的endPts; in output time base;
    AVRational getStreamTimeBase();
    
private:
    int recreateFilterGraph();
    int createFilterGraph(AVBufferSrcParameters *_Nonnull buf_src_params, int output_sample_rate, AVSampleFormat output_sample_format, const std::string& output_channel_layout_desc, FilterGraph *_Nullable*_Nonnull out_filter_graph);
    
private:
    AVRational _in_stream_time_base;
    int64_t _in_stream_duration;
    
    int _output_sample_rate;
    AVSampleFormat _output_sample_format;
    int _output_channels;
    std::string _output_channel_layout_desc;
    int _output_bytes_per_sample;
    bool _output_interleaved;
    
    MediaDecoder *_Nullable _decoder { nullptr };
    AVBufferSrcParameters *_Nullable _buf_src_params { nullptr };
    FilterGraph *_Nullable _filter_graph { nullptr };
    PacketQueue *_Nullable _packet_queue { nullptr };
    AudioFifo *_Nullable _fifo { nullptr };
    
    AVPacket *_Nullable _pkt { nullptr };
    AVFrame *_Nullable _dec_frame { nullptr };
    AVFrame *_Nullable _filt_frame { nullptr };
    
    bool _packet_reached_eof { false };
    bool _transcoding_eof { false };
    bool _should_align_frames { false };
    bool _should_drain_packets { false };
};

}

#endif /* FFAV_AudioTranscoder_hpp */
