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
//  ff_types.hpp
//  LWZFFmpegLib
//
//  Created by sj on 2025/5/21.
//

#ifndef FFAV_Types_hpp
#define FFAV_Types_hpp

struct AVPacket;
struct AVFrame;
struct AVFormatContext;
struct AVCodecContext;
struct AVRational;
struct AVCodec;
struct AVStream;
struct AVFilterGraph;
struct AVFilterContext;
struct AVCodecParameters;
struct AVBufferSrcParameters;
struct AVFilterInOut;
struct AVChannelLayout;
struct AVAudioFifo;

extern "C" {
#include <libavutil/samplefmt.h>
#include <libavutil/pixfmt.h>
#include <libavutil/avutil.h>
#include <libavformat/avformat.h>
#include <libavfilter/avfilter.h>
#include <libavfilter/buffersrc.h>
}

#endif /* FFAV_Types_hpp */
