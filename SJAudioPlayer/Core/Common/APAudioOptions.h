//
//  APAudioOptions.h
//  SJAudioPlayer
//
//  Created by BlueDancer on 2021/4/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface APAudioOptions : NSObject
+ (instancetype)defaultOptions;

///
/// 最大可播放到的时长, 播放到该位置后将停止播放
///
///     默认值为 0, 即不做限制
///
@property (nonatomic) NSTimeInterval maximumPlayableDurationLimit;
@end

NS_ASSUME_NONNULL_END
