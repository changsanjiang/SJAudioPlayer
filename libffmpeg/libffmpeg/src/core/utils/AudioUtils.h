//
// Created on 2025/1/17.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef FFMPEGPROJ_AUDIOUTILS_H
#define FFMPEGPROJ_AUDIOUTILS_H

#include "AudioFifo.h"
#include "MediaDecoder.h"
#include "FilterGraph.h"
#include <functional>

namespace FFAV {

class AudioUtils {
public:
    using FilterFrameCallback = std::function<int(AVFrame* _Nonnull filt_frame)>;
    
    static int transcode(
        AVPacket* _Nullable pkt,
        MediaDecoder* _Nonnull decoder, 
        AVFrame* _Nonnull dec_frame,
        FilterGraph* _Nonnull filter_graph,
        AVFrame* _Nonnull filt_frame,
        const std::string& buf_src_name,
        const std::string& buf_sink_name,
        FilterFrameCallback callback
    );
    
//    static AVSampleFormat ohToAVSampleFormat(OH_AudioStream_SampleFormat fmt);

private:
    static int process_decoded_frames(
        MediaDecoder* _Nonnull decoder, 
        AVFrame* _Nonnull dec_frame,
        FilterGraph* _Nonnull filter_graph,
        AVFrame* _Nonnull filt_frame,
        const std::string& buf_src_name,
        const std::string& buf_sink_name,
        FilterFrameCallback callback
    );
    
    static int process_filter_frame(
        AVFrame* _Nullable frame,
        FilterGraph* _Nonnull filter_graph,
        AVFrame* _Nonnull filt_frame,
        const std::string& buf_src_name,
        const std::string& buf_sink_name,
        FilterFrameCallback callback
    );
    
    static int transfer_filtered_frames(
        FilterGraph* _Nonnull filter_graph,
        AVFrame* _Nonnull filt_frame,
        const std::string& buf_sink_name,
        FilterFrameCallback callback
    );
};

}

#endif //FFMPEGPROJ_AUDIOUTILS_H

