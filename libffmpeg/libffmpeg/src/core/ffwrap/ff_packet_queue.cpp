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

#include "ff_packet_queue.hpp"
#include "ff_includes.hpp"
#include <stdint.h>

namespace FFAV {

PacketQueue::PacketQueue() {
    
}

PacketQueue::~PacketQueue() {
    clear();
}

void PacketQueue::push(AVPacket* _Nonnull packet) {
    if ( !packet ) return;
    
    AVPacket* pkt = av_packet_alloc();
    av_packet_ref(pkt, packet);

    _queue.push(pkt);
    
    int64_t duration = packet->duration;
    _duration += duration;
    _total_size += packet->size;
    
    int64_t pts = packet->pts;
    if ( pts != AV_NOPTS_VALUE ) {
        int64_t end_pts = pts + duration;
        if ( _last_presentation_packet_end_pts == AV_NOPTS_VALUE ||
             end_pts > _last_presentation_packet_end_pts ) {
            _last_presentation_packet_end_pts = end_pts;
        }
    }
}

bool PacketQueue::pop(AVPacket* _Nonnull packet) {
    if ( !packet ) {
        return false;
    }
    
    AVPacket* pkt = nullptr;
    if ( !_queue.empty() ) {
        pkt = _queue.front();
        _queue.pop();
        _total_size -= pkt->size;
        _duration -= pkt->duration;
        av_packet_move_ref(packet, pkt);
        av_packet_free(&pkt);
        return true;
    }
    return false;
}

void PacketQueue::clear() {
    while(!_queue.empty()) {
        AVPacket* pkt = _queue.front();
        _queue.pop();
        av_packet_free(&pkt);
    }
    _last_presentation_packet_end_pts = AV_NOPTS_VALUE;
    _duration = 0;
    _total_size = 0;
}

int64_t PacketQueue::getLastPresentationPacketEndPts() {
    return _last_presentation_packet_end_pts;
}

int64_t PacketQueue::getDuration() {
    return _duration;
}

size_t PacketQueue::getCount() {
    return _queue.size();
}

int64_t PacketQueue::getSize() {
    return _total_size;
}

}
