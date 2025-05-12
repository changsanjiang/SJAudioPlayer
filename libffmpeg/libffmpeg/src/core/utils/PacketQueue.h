//
// Created on 2025/2/8.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef FFMPEGPROJ_PACKETQUEUE_H
#define FFMPEGPROJ_PACKETQUEUE_H

#include <cstdint>
extern "C" {
#include <libavutil/avutil.h>
#include <libavcodec/avcodec.h>
}

#include <queue>

namespace FFAV {

class PacketQueue {
public:
    PacketQueue();
    ~PacketQueue();
    
    void push(AVPacket* _Nonnull packet);
    bool pop(AVPacket* _Nonnull packet);
    void clear();
    
    int64_t getLastPushPts();
    int64_t getLastPopPts();

    int64_t getFrontPacketPts();
    
    // 获取所有数据包的数量
    size_t getCount();

    // 获取所有数据包的数据占用的字节数
    int64_t getSize();

private:
    std::queue<AVPacket*> queue;
    int64_t total_size = 0;
    int64_t last_push_pts = AV_NOPTS_VALUE; 
    int64_t last_pop_pts = AV_NOPTS_VALUE;
};

}
#endif //FFMPEGPROJ_PACKETQUEUE_H
