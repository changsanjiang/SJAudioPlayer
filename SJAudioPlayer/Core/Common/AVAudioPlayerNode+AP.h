//
//  AVAudioPlayerNode+AP.h
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/14.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVAudioPlayerNode (AP)

@property (nonatomic, readonly) BOOL ap_isPlaying;

@property (nonatomic, readonly) AVAudioFramePosition ap_currentFramePosition;

@end

NS_ASSUME_NONNULL_END
