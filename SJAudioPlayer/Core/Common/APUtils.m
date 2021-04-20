//
//  APUtils.m
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/19.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APUtils.h"

NSArray *_Nullable
APAllHashTableObjects(NSHashTable *table) {
    return table.count != 0 ? NSAllHashTableObjects(table) : nil;
}
