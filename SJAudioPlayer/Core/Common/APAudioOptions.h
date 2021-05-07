//
//  APAudioOptions.h
//  SJAudioPlayer
//
//  Created by BlueDancer on 2021/4/24.
//

#import "APInterfaces.h"

NS_ASSUME_NONNULL_BEGIN
@interface APAudioOptions : NSObject<APAudioOptions>
+ (instancetype)defaultOptions;

/// 播放时长限制. 最大可播放到的时长, 播放到该位置后将停止播放
///
///     默认值为 0, 即不做限制
///
@property (nonatomic) NSTimeInterval maximumPlayableDuration;

/// 每个 PCMBuffer packets 的字节数限制
///
///     default value is 8192;
///
@property (nonatomic) UInt64 maximumCountOfBytesPerPCMBufferPackets;

/// 当PCMBuffer的数量大于等于指定的数量后开始播放
///
///     default value is 1;
///
@property (nonatomic) NSInteger minimumCountOfPCMBufferToBePlayable;

/// PCMBuffer 缓存的最大数量
///
///     default value is 25;
///
@property (nonatomic) NSInteger maximumCountOfPCMBufferForPlayback;

/// 数据读取回调
///
@property (nonatomic, copy, nullable) NSData *(^dataReadDecoder)(NSData *data, NSUInteger offset);

/// 附加请求头
///
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *HTTPAdditionalHeaders;

@end
NS_ASSUME_NONNULL_END
