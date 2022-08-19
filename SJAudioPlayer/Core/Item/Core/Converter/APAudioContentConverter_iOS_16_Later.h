//
//  APAudioContentConverter_iOS_16_Later.h
//  SJAudioPlayer
//
//  Created by 畅三江 on 2022/8/19.
//

#import "APAudioInterfaces.h"

API_AVAILABLE(ios(16.0)) NS_ASSUME_NONNULL_BEGIN
@interface APAudioContentConverter_iOS_16_Later : NSObject<APAudioContentConverter>

- (instancetype)initWithStreamFormat:(AVAudioFormat *)streamFormat;

@property (nonatomic, strong, readonly) AVAudioFormat *streamFormat;
@property (nonatomic, strong, readonly) AVAudioFormat *outputFormat;
 
- (nullable AVAudioPCMBuffer *)convertPackets:(NSArray<id<APAudioContentPacket>> *)packets error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
