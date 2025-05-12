//
// Created on 2025/1/17.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "AudioUtils.h"

namespace FFAV {

int AudioUtils::transcode(
    AVPacket* _Nullable pkt,
    MediaDecoder* _Nonnull decoder, 
    AVFrame* _Nonnull dec_frame,
    FilterGraph* _Nonnull filter_graph,
    AVFrame* _Nonnull filt_frame,
    const std::string& buf_src_name,
    const std::string& buf_sink_name,
    FilterFrameCallback callback
) {
    int ret = decoder->send(pkt);
    if ( ret < 0 ) {
        return ret;
    }
        
    return process_decoded_frames(decoder, dec_frame, filter_graph, filt_frame, buf_src_name, buf_sink_name, callback);
}

//AVSampleFormat AudioUtils::ohToAVSampleFormat(OH_AudioStream_SampleFormat fmt) {
//    switch (fmt) {
//        case AUDIOSTREAM_SAMPLE_U8:
//            return AV_SAMPLE_FMT_U8;  // 无符号 8-bit
//        case AUDIOSTREAM_SAMPLE_S16LE:
//            return AV_SAMPLE_FMT_S16; // 有符号 16-bit
//        case AUDIOSTREAM_SAMPLE_S32LE:
//            return AV_SAMPLE_FMT_S32; // 有符号 32-bit
//        case AUDIOSTREAM_SAMPLE_S24LE:
//            throw std::runtime_error("Unsupported format: AUDIOSTREAM_SAMPLE_S24LE (24-bit PCM has no direct AVSampleFormat)");
//        default:
//            throw std::runtime_error("Unknown OH_AudioStream_SampleFormat value");
//    }
//}

int AudioUtils::process_decoded_frames(
    MediaDecoder* _Nonnull decoder, 
    AVFrame* _Nonnull dec_frame,
    FilterGraph* _Nonnull filter_graph,
    AVFrame* _Nonnull filt_frame,
    const std::string& buf_src_name,
    const std::string& buf_sink_name,
    FilterFrameCallback callback
) {
    int ret = 0;
    do {
        ret = decoder->receive(dec_frame);
        if ( ret == AVERROR_EOF ) {
            ret = process_filter_frame(NULL, filter_graph, filt_frame, buf_src_name, buf_sink_name, callback);
            break;
        }
    
        if ( ret < 0 ) {
            break;
        }
        
        ret = process_filter_frame(dec_frame, filter_graph, filt_frame, buf_src_name, buf_sink_name, callback);
        av_frame_unref(dec_frame);
    } while(ret >= 0);
    return ret;
}

int AudioUtils::process_filter_frame(
    AVFrame* _Nullable frame,
    FilterGraph* _Nonnull filter_graph,
    AVFrame* _Nonnull filt_frame,
    const std::string& buf_src_name,
    const std::string& buf_sink_name,
    FilterFrameCallback callback
) {
    int flags = frame != nullptr ? AV_BUFFERSRC_FLAG_KEEP_REF : AV_BUFFERSRC_FLAG_PUSH;
    int ret = filter_graph->addFrame(buf_src_name, frame, flags);
    if ( ret < 0 ) {
        return ret;
    }  
    return transfer_filtered_frames(filter_graph, filt_frame, buf_sink_name, callback);
}

int AudioUtils::transfer_filtered_frames(
    FilterGraph* _Nonnull filter_graph,
    AVFrame* _Nonnull filt_frame,
    const std::string& buf_sink_name,
    FilterFrameCallback callback
) {
    int ret = 0;
    int callback_ret = 0;
    do {
        ret = filter_graph->getFrame(buf_sink_name, filt_frame);
        if ( ret < 0 ) {
            break;
        }
        callback_ret = callback(filt_frame); // callback
        if ( callback_ret < 0 ) {
            ret = callback_ret;
        }
        av_frame_unref(filt_frame);
    } while (ret >= 0);
    return ret;
}
    
}
