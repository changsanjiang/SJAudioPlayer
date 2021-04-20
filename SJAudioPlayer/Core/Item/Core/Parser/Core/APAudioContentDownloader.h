//
//  APAudioContentDownloader.h
//  AudioCore
//
//  Created by BD on 2021/3/14.
//

#import <Foundation/Foundation.h>
@protocol APAudioContentDownloaderTaskDelegate;
NS_ASSUME_NONNULL_BEGIN
@interface APAudioContentDownloader : NSObject
+ (instancetype)shared;

@property (nonatomic) NSTimeInterval timeoutInterval;

- (nullable NSURLSessionTask *)downloadWithRequest:(NSURLRequest *)request priority:(float)priority delegate:(id<APAudioContentDownloaderTaskDelegate>)delegate;

- (void)cancelAllDownloadTasks;

@property (nonatomic, readonly) NSInteger taskCount;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
@end

@protocol APAudioContentDownloaderTaskDelegate <NSObject>
- (void)downloadTask:(NSURLSessionTask *)task didReceiveResponse:(NSURLResponse *)response;
- (void)downloadTask:(NSURLSessionTask *)task didReceiveData:(NSData *)data;
- (void)downloadTask:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error;
@end
NS_ASSUME_NONNULL_END
