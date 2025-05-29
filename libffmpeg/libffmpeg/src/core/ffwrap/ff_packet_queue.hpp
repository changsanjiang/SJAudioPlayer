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
// Created by sj on 2025/2/8.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef FFAV_PacketQueue_hpp
#define FFAV_PacketQueue_hpp

#include <cstdint>
#include <queue>
#include "ff_types.hpp"

namespace FFAV {

class PacketQueue {
public:
    explicit PacketQueue();
    ~PacketQueue();
    
    PacketQueue(PacketQueue&&) noexcept = delete;
    PacketQueue& operator=(PacketQueue&&) noexcept = delete;
    
    void push(AVPacket* packet);               // 队尾插入
    bool pop(AVPacket* packet);                // 队首取出（拷贝数据，释放原始包）
    void clear();                              // 清空所有队列

    int64_t getLastPresentationPacketEndPts(); // 最后呈现的数据包的endPts(PTS + duration)
    int64_t getDuration();                     // 当前所有 packet 的时长
    int64_t getSize();                         // 当前所有 packet 的字节总数
    size_t getCount();                         // 当前 packet 数量

private:
    std::queue<AVPacket*> _queue;
    int64_t _last_presentation_packet_end_pts = AV_NOPTS_VALUE;
    int64_t _duration = 0;
    int64_t _total_size = 0;
};

}
#endif //FFAV_PacketQueue_hpp
