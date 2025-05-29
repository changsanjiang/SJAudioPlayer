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

#include "ff_audio_utils.hpp"
#include "ff_includes.hpp"
#include "ff_audio_fifo.hpp"
#include "ff_media_decoder.hpp"
#include "ff_filter_graph.hpp"
#include "ff_audio_encoder.hpp"

namespace FFAV {

int AudioUtils::processPacket(
    AVPacket* _Nullable pkt,
    MediaDecoder* _Nonnull decoder, 
    AVFrame* _Nonnull dec_frame,
    FilterGraph* _Nonnull filter_graph,
    const std::string& buf_src_name,
    const std::string& buf_sink_name,
    AVFrame* _Nonnull filt_frame,
    FrameCallback callback
) {
    int ret = decoder->send(pkt);
    if ( ret < 0 ) {
        return ret;
    }
    
    ret = drainDecodedFrames(decoder, dec_frame, [&](AVFrame *dec_frame) {
        int push_ret = filter_graph->addFrame(buf_src_name, dec_frame);
        if ( push_ret < 0 ) {
            return push_ret;
        }
        
        int drain_ret = drainFilteredFrames(filter_graph, filt_frame, buf_sink_name, callback);
        if ( drain_ret < 0 && drain_ret != AVERROR(EAGAIN) ) {
            return drain_ret;
        }
        return 0;
    });
    
    if ( ret == AVERROR_EOF ) {
        ret = filter_graph->addFrame(buf_src_name, nullptr, AV_BUFFERSRC_FLAG_PUSH);
        if ( ret < 0 ) {
            return ret;
        }

        return drainFilteredFrames(filter_graph, filt_frame, buf_sink_name, callback);
    }
    return ret;
}


int AudioUtils::processFrame(
   AVFrame* _Nullable frame,
   FilterGraph* _Nonnull filter_graph,
   const std::string& buf_src_name,
   const std::string& buf_sink_name,
   AVFrame* _Nonnull filt_frame,
   AudioFifo* _Nonnull fifo,
   AVFrame* _Nonnull fifo_frame,
   AudioEncoder* _Nonnull encoder,
   AVPacket* _Nonnull enc_pkt,
   PacketCallback callback
) {
    int flags = frame != nullptr ? AV_BUFFERSRC_FLAG_KEEP_REF : AV_BUFFERSRC_FLAG_PUSH;
    int ret = filter_graph->addFrame(buf_src_name, frame, flags);
    if ( ret < 0 ) {
        return ret;
    }
    
    int frame_size = encoder->getFrameSize();
    if ( frame_size == 0 ) frame_size = 1024;
    
    ret = drainFilteredFrames(filter_graph, filt_frame, buf_sink_name, [&](AVFrame *filt_frame) {
        int push_ret = fifo->write((void **)filt_frame->data, filt_frame->nb_samples, filt_frame->pts);
        if ( push_ret < 0 ) {
            return push_ret;
        }
        
        return drainFifo(fifo, frame_size, false, fifo_frame, [&](AVFrame *fifo_frame) {
            int send_ret = encoder->send(fifo_frame);
            if ( send_ret < 0 ) {
                return send_ret;
            }
            
            int drain_ret = drainEncodedPackets(encoder, enc_pkt, callback);
            if ( drain_ret < 0 && drain_ret != AVERROR(EAGAIN) ) {
                return drain_ret;
            }
            return 0;
        });
    });
    
    if ( ret == AVERROR_EOF ) {
        ret = drainFifo(fifo, frame_size, true, fifo_frame, [&](AVFrame *fifo_frame) {
            int send_ret = encoder->send(fifo_frame);
            if ( send_ret < 0 ) {
                return send_ret;
            }
            
            int drain_ret = drainEncodedPackets(encoder, enc_pkt, callback);
            if ( drain_ret < 0 && drain_ret != AVERROR(EAGAIN) ) {
                return drain_ret;
            }
            return 0;
        });
        
        if ( ret < 0 ) {
            return ret;
        }
        
        ret = encoder->send(nullptr);
        if ( ret < 0 ) {
            return ret;
        }
        ret = drainEncodedPackets(encoder, enc_pkt, callback);
    }
    return ret;
}

int AudioUtils::drainDecodedFrames(
    MediaDecoder* _Nonnull decoder,
    AVFrame* _Nonnull dec_frame,
    FrameCallback callback
) {
    int ret = 0;
    do {
        ret = decoder->receive(dec_frame);
        if ( ret < 0 ) {
            break;
        }
        
        ret = callback(dec_frame); // callback
        av_frame_unref(dec_frame);
    } while(ret >= 0);
    return ret;
}

int AudioUtils::drainFilteredFrames(
    FilterGraph* _Nonnull filter_graph,
    AVFrame* _Nonnull filt_frame,
    const std::string& buf_sink_name,
    FrameCallback callback
) {
    int ret = 0;
    do {
        ret = filter_graph->getFrame(buf_sink_name, filt_frame);
        if ( ret < 0 ) {
            break;
        }
        
        ret = callback(filt_frame); // callback
        av_frame_unref(filt_frame);
    } while (ret >= 0);
    return ret;
}

int AudioUtils::drainFifo(
    AudioFifo* _Nonnull fifo,
    int frame_size,
    bool eof,
    AVFrame* _Nonnull fifo_frame,
    FrameCallback callback
) {
    int ret = 0;
    while ( ret >= 0 && (fifo->getNumberOfSamples() >= frame_size || (eof && fifo->getNumberOfSamples() > 0)) ) {
        ret = fifo->read((void **)fifo_frame->data, frame_size, &fifo_frame->pts);
        if ( ret < 0 ) {
            break;
        }
        fifo_frame->nb_samples = ret;
        ret = callback(fifo_frame);
    }
    return ret;
}

int AudioUtils::drainEncodedPackets(
    AudioEncoder* _Nonnull encoder,
    AVPacket* _Nonnull enc_pkt,
    PacketCallback callback
) {
    int ret = 0;
    do {
        ret = encoder->receive(enc_pkt);
        if ( ret < 0 ) { // error
            break;
        }
        
        ret = callback(enc_pkt);
        av_packet_unref(enc_pkt);
    } while ( ret >= 0 );
    return ret;
}


}
