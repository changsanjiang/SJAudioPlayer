//
//  APAudioContentConverter.h
//  SJAudioPlayer_Example
//
//  Created by 畅三江 on 2021/4/13.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APAudioInterfaces.h"

NS_ASSUME_NONNULL_BEGIN
@interface APAudioContentConverter : NSObject<APAudioContentConverter>

- (instancetype)initWithStreamFormat:(AVAudioFormat *)streamFormat;

@property (nonatomic, strong, readonly) AVAudioFormat *streamFormat;
@property (nonatomic, strong, readonly) AVAudioFormat *outputFormat;
 
- (nullable AVAudioPCMBuffer *)convertPackets:(NSArray<id<APAudioContentPacket>> *)packets error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
