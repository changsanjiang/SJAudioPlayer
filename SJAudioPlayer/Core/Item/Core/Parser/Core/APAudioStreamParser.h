//
//  APAudioStreamParser.h
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/13.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APAudioInterfaces.h"
@protocol APAudioStreamParserDelegate;

NS_ASSUME_NONNULL_BEGIN
@interface APAudioStreamParser : NSObject

@property (nonatomic, strong, readonly, nullable) AVAudioFormat *format;
@property (nonatomic, readonly) UInt64 audioDataOffset;
@property (nonatomic, copy, readonly, nullable) NSArray<id<APAudioContentPacket>> *foundPackets;
@property (nonatomic, readonly) UInt64 countOfBytesFoundPackets;
@property (nonatomic, readonly) NSTimeInterval durationPerPacket;
@property (nonatomic, readonly) double bitRate;

- (BOOL)process:(NSData *)data isDiscontinuous:(BOOL)isDiscontinuous error:(NSError **)error; // throw exception
- (void)removeAllFoundPackets;
- (void)removeFoundPacketsInRange:(NSRange)range;

- (BOOL)offsetAtPacket:(AVAudioPacketCount)index outOffset:(UInt64 *)outOffset isEstimated:(BOOL *)isEstimated;
@end
NS_ASSUME_NONNULL_END
