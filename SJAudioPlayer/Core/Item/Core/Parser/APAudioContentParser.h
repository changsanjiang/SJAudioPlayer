//
//  APAudioContentParser.h
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/13.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APAudioInterfaces.h"

NS_ASSUME_NONNULL_BEGIN

@interface APAudioContentParser : NSObject<APAudioContentParser>

- (instancetype)initWithURL:(NSURL *)URL minimumCountOfBytesFoundPackets:(UInt64)size delegate:(id<APAudioContentParserDelegate>)delegate queue:(dispatch_queue_t)queue;

@end

NS_ASSUME_NONNULL_END
