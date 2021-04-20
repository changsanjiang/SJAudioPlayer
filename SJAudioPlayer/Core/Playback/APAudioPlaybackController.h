//
//  APAudioPlaybackController.h
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/14.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APInterfaces.h"

NS_ASSUME_NONNULL_BEGIN
@interface APAudioPlaybackController : NSObject<APAudioPlaybackController>
@property (nonatomic, readonly) AVAudioFramePosition lastPosition;
- (void)scheduleBuffer:(AVAudioPCMBuffer *)buffer atOffset:(AVAudioFramePosition)offset completionHandler:(AVAudioNodeCompletionHandler __nullable)completionHandler;
- (BOOL)play:(NSError **)error;
- (void)pause;
- (void)stop;
- (void)reset;
@end
NS_ASSUME_NONNULL_END
