//
//  FFCoreAudioReader.h
//  LWZFFmpegLib
//
//  Created by db on 2025/4/14.
//

#import <Foundation/Foundation.h>
#include "common.h"
EXTERN_C_START
#include <libavcodec/packet.h>
#include <libavformat/avformat.h>
EXTERN_C_END

@protocol FFCoreAudioReaderDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface FFCoreAudioReader : NSObject

- (instancetype)initWithURL:(NSURL *)URL delegate:(id<FFCoreAudioReaderDelegate>)delegate;

- (void)prepareWithStartTimePosition:(int64_t)startTimePosition; // in base q;
- (void)reset; // 重置所有状态(仅限报错后使用), 重置后可以重新调用 prepare 初始化;
- (void)start;
- (void)stop; // 停止后不可继续操作了;

@property (nonatomic, getter=isPacketBufferFull) BOOL packetBufferFull; // 设置缓冲是否已满; 缓冲满后将会暂停读取, 等待缓冲消费后继续;
- (void)seekToTime:(int64_t)time;  // in base q;
@end

/// 所有回调都在子线程;
@protocol FFCoreAudioReaderDelegate <NSObject>
- (void)audioReader:(FFCoreAudioReader *)reader readyToReadStream:(AVStream *)stream;
/// EOF 时 pkt 返回 null;
- (void)audioReader:(FFCoreAudioReader *)reader didReadPacket:(AVPacket *_Nullable)packet shouldFlush:(BOOL)shouldFlush;
- (void)audioReader:(FFCoreAudioReader *)reader anErrorOccurred:(int)error;
@end

NS_ASSUME_NONNULL_END
