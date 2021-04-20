//
//  APAudioItem.h
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/14.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APInterfaces.h"

NS_ASSUME_NONNULL_BEGIN

@interface APAudioItem : NSObject<APAudioItem>
- (instancetype)initWithURL:(NSURL *)URL delegate:(id<APAudioItemDelegate>)delegate queue:(dispatch_queue_t)queue;

@end

NS_ASSUME_NONNULL_END
