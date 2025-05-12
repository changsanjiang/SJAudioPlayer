//
//  FFCoreFormat.h
//  LWZFFmpegLib
//
//  Created by db on 2025/5/9.
//

#import <AVFAudio/AVAudioFormat.h>
#import <string>
#import "common.h"

EXTERN_C_START
#include <libavutil/samplefmt.h>
EXTERN_C_END

namespace FFCoreFormat {

/// 固定输出格式: 44100 Hz, 32-bit float, fltp, stereo
const int FF_OUTPUT_SAMPLE_RATE = 44100;
const AVSampleFormat FF_OUTPUT_SAMPLE_FORMAT = AV_SAMPLE_FMT_FLTP;
const AVAudioCommonFormat FF_OUTPUT_AUDIO_COMMON_FORMAT = AVAudioPCMFormatFloat32;
const int FF_OUTPUT_CHANNELS = 2;
const std::string FF_OUTPUT_CHANNEL_DESC = "stereo";
const bool FF_OUTOUT_INTERLEAVED = false;

}
