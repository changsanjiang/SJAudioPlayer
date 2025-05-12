//
//  FFCoreAudioTranscoder.h
//  LWZFFmpegLib
//
//  Created by db on 2025/4/24.
//

#import <AVFAudio/AVAudioFormat.h>
#import <CoreMedia/CMTimeRange.h>

#include "common.h"
EXTERN_C_START
#include <libavcodec/packet.h>
#include <libavformat/avformat.h>
EXTERN_C_END

NS_ASSUME_NONNULL_BEGIN

@interface FFCoreAudioTranscoder : NSObject

@property (nonatomic, strong, readonly) AVAudioFormat *outputFormat;
@property (nonatomic, readonly, getter=isPacketBufferFull) BOOL packetBufferFull; // 缓冲是否已满;
@property (nonatomic, readonly) CMTimeRange timeRange;
@property (nonatomic, readonly) BOOL eof;

- (int)prepareByAudioStream:(AVStream *)stream;

- (int)pushPacket:(AVPacket *_Nullable)packet shouldFlush:(BOOL)shouldFlush;
- (int)pushPacket:(AVPacket *_Nullable)packet shouldOnlyFlushPackets:(BOOL)shouldOnlyFlushPackets;

@property (nonatomic, readonly) CMTime fifoEndPts; // 可能返回 kCMTimeInvalid;

/// 尝试转码出指定数量的音频数据;
///
/// 数据足够时返回值与frameCapacity一致;
/// 当 eof 时可能返回的样本数量小于指定的样本数量;
/// 如果未到 eof 数据不满足指定的样本数量时返回 0;
- (int)tryTranscodeWithFrameCapacity:(int)frameCapacity data:(void *_Nonnull*_Nonnull)outData pts:(int64_t *)outPts eof:(BOOL *)outEOF;

@end

NS_ASSUME_NONNULL_END
