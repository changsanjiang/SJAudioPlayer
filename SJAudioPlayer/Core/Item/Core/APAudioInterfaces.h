//
//  APAudioInterfaces.h
//  SJAudioPlayer
//
//  Created by BlueDancer on 2021/4/14.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#ifndef APAudioInterfaces_h
#define APAudioInterfaces_h

#import <AVFoundation/AVFoundation.h>
@protocol APAudioContentPacket, APAudioContentParserDelegate, APAudioContentReaderDelegate;

NS_ASSUME_NONNULL_BEGIN
@protocol APAudioContentParser <NSObject>
@property (nonatomic, weak, readonly, nullable) id<APAudioContentParserDelegate> delegate;
@property (nonatomic, strong, readonly, nullable) AVAudioFormat *contentFormat;
@property (nonatomic, readonly) float contentLoadProgress;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) NSTimeInterval maximumPlayableDuration; // 可播放时长限制, 缓冲到达指定时长后, 将停止解析

- (void)prepare;
@property (nonatomic, readonly, getter=isSeekable) BOOL seekable;
@property (nonatomic, readonly, getter=isReachedEndPosition) BOOL reachedEndPosition;
@property (nonatomic, readonly, getter=isReachedMaximumPlayableDurationPosition) BOOL reachedMaximumPlayableDurationPosition;
@property (nonatomic, readonly) AVAudioFramePosition startPosition; // seekToTime 所处的位置
- (void)seekToTime:(NSTimeInterval)time;
- (void)suspend; // 暂停
- (void)resume;  // 恢复
- (void)retry;   // 从当前位置重试(报错后, 可调用该方法重试)
@end

@protocol APAudioContentParserDelegate <NSObject>
- (void)parser:(id<APAudioContentParser>)parser foundFormat:(AVAudioFormat *)format;
- (void)parser:(id<APAudioContentParser>)parser foundPackets:(NSArray<id<APAudioContentPacket>> *)packets;
- (void)parser:(id<APAudioContentParser>)parser contentLoadProgressDidChange:(float)progress;
- (void)parser:(id<APAudioContentParser>)parser anErrorOccurred:(NSError *)error;
@end

@protocol APAudioContentPacket <NSObject>
@property (nonatomic, strong, readonly) NSData *data;
@property (nonatomic, readonly) AudioStreamPacketDescription *desc;
@end

@protocol APAudioContentReader <NSObject>
@property (nonatomic, weak, readonly, nullable) id<APAudioContentReaderDelegate> delegate;
@property (nonatomic, readonly) UInt64 countOfBytesTotalLength;
@property (nonatomic, readonly) UInt64 offset;
@property (nonatomic, readonly) float contentLoadProgress;

- (void)seekToOffset:(UInt64)offsetInBytes;
- (void)retry;
- (void)resume;
- (void)suspend;
@end

@protocol APAudioContentReaderDelegate <NSObject>
- (void)contentReader:(id<APAudioContentReader>)reader contentLoadProgressDidChange:(float)progress;
- (void)contentReader:(id<APAudioContentReader>)reader hasNewAvailableData:(NSData *)data atOffset:(UInt64)offset;
- (void)contentReader:(id<APAudioContentReader>)reader anErrorOccurred:(NSError *)error;
@end
NS_ASSUME_NONNULL_END
#endif /* APAudioInterfaces_h */
