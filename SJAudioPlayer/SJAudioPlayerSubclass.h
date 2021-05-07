//
//  SJAudioPlayerSubclass.h
//  Pods
//
//  Created by BlueDancer on 2021/5/7.
//

#ifndef SJAudioPlayerSubclass_h
#define SJAudioPlayerSubclass_h

#import "SJAudioPlayer.h"

NS_ASSUME_NONNULL_BEGIN
@interface SJAudioPlayer (SJAudioPlayerProtected)
- (void)resetPlaybackWithURL:(NSURL *)newURL options:(id<APAudioOptions>)options NS_REQUIRES_SUPER;
//- (void)pausePlayback NS_REQUIRES_SUPER;
//- (void)stopPlayback NS_REQUIRES_SUPER;
//- (BOOL)playPlayback NS_REQUIRES_SUPER;
@end
NS_ASSUME_NONNULL_END

#endif /* SJAudioPlayerSubclass_h */
