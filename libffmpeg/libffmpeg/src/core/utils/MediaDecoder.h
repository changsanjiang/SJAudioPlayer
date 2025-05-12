//
// Created on 2025/1/7.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef FFMPEGPROJ_MEDIADECODER_H
#define FFMPEGPROJ_MEDIADECODER_H
#include "common.h"

EXTERN_C_START
#include <libavformat/avformat.h>
#include <libavcodec/packet.h>
#include <libavcodec/avcodec.h>
#include <libavutil/frame.h>
#include <libavfilter/buffersrc.h>
#include <libavutil/rational.h>
EXTERN_C_END

namespace FFAV {

/** 用于解码 */
class MediaDecoder {
public:
    MediaDecoder();
    ~MediaDecoder();

    int init(AVCodecParameters* _Nonnull codecpar);

    int send(AVPacket* _Nullable pkt);
    
    int receive(AVFrame* _Nonnull frame);

    void flush();

    // 生成 buffersrc filter 的构建参数;
    AVBufferSrcParameters* _Nullable createBufferSrcParameters(AVRational time_base);

    AVSampleFormat getSampleFormat();
    int getSampleRate();
    int getChannels();
    
private:
    AVCodecContext* _Nullable dec_ctx;      // AVCodecContext 用于解码

    // 关闭媒体文件
    void release();
};

}

#endif //FFMPEGPROJ_MEDIADECODER_H
