//
//  HLSParser.h
//  SJMediaCacheServer_Example
//
//  Created by 畅三江 on 2020/6/9.
//  Copyright © 2020 changsanjiang@gmail.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MCSDefines.h"
@protocol HLSParserDelegate, HLSURIItem;
@class HLSAsset;

NS_ASSUME_NONNULL_BEGIN
@interface HLSParser : NSObject
+ (nullable instancetype)parserInAsset:(HLSAsset *)asset;

- (instancetype)initWithAsset:(HLSAsset *)asset request:(NSURLRequest *)request networkTaskPriority:(float)networkTaskPriority delegate:(id<HLSParserDelegate>)delegate;

- (void)prepare;

- (void)close;

@property (nonatomic, weak, readonly, nullable) HLSAsset *asset;
@property (nonatomic, readonly) NSUInteger allItemsCount;
@property (nonatomic, readonly) NSUInteger tsCount;

- (nullable id<HLSURIItem>)itemAtIndex:(NSUInteger)index;
- (BOOL)isVariantItem:(id<HLSURIItem>)item;
- (nullable NSArray<id<HLSURIItem>> *)renditionsItemsForVariantItem:(id<HLSURIItem>)item;

@property (nonatomic, readonly) BOOL isClosed;
@property (nonatomic, readonly) BOOL isDone;
@end

@protocol HLSParserDelegate <NSObject>
- (void)parserParseDidFinish:(HLSParser *)parser;
- (void)parser:(HLSParser *)parser anErrorOccurred:(NSError *)error;
@end

@protocol HLSURIItem <NSObject>
@property (nonatomic, readonly) MCSDataType type;
@property (nonatomic, copy, readonly) NSString *URI;
@property (nonatomic, copy, readonly, nullable) NSDictionary *HTTPAdditionalHeaders;
@end
NS_ASSUME_NONNULL_END
