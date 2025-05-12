//
//  SJViewController.m
//  SJAudioPlayer
//
//  Created by changsanjiang@gmail.com on 04/19/2021.
//  Copyright (c) 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "SJViewController.h"
#import "SJAudioPlayer.h"
#import "SJButtonProgressSlider.h"
#import "NSString+SJBaseVideoPlayerExtended.h"

@interface SJViewController ()<SJProgressSliderDelegate, SJAudioPlayerObserver>
@property (weak, nonatomic) IBOutlet SJButtonProgressSlider *progressView;
@property (weak, nonatomic) IBOutlet SJProgressSlider *volumeSlider;
@property (weak, nonatomic) IBOutlet SJProgressSlider *rateSlider;
@property (weak, nonatomic) IBOutlet UILabel *statusLabel;
@property (weak, nonatomic) IBOutlet UIButton *playButton;
@property (nonatomic, strong) SJAudioPlayer *player;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation SJViewController

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _progressView.titleColor = UIColor.whiteColor;
    _progressView.spacing = 12;
    _progressView.slider.delegate = self;
    _progressView.slider.tap.enabled = YES;
    _progressView.slider.showsBufferProgress = YES;
    _progressView.slider.traceImageView.backgroundColor = [UIColor greenColor];
    _progressView.slider.trackImageView.backgroundColor = [UIColor whiteColor];
    [_progressView.slider setThumbCornerRadius:12 size:CGSizeMake(24, 24) thumbBackgroundColor:UIColor.whiteColor];
    _progressView.slider.bufferProgressColor = [UIColor yellowColor];
    __weak typeof(self) _self = self;
    _progressView.slider.tappedExeBlock = ^(SJProgressSlider * _Nonnull slider, CGFloat seekTime) {
        __strong typeof(_self) self = _self;
        if ( self == nil ) return;
        [self.player seekToTime:CMTimeMakeWithSeconds(seekTime, NSEC_PER_SEC)];
    };
    
    _volumeSlider.delegate = self;
    _rateSlider.delegate = self;
    _volumeSlider.value = 1;
    _rateSlider.maxValue = 1.5;
    _rateSlider.minValue = 0.5;
    _rateSlider.value = 1;
    
    _player = SJAudioPlayer.alloc.init;
    [_player registerObserver:self];
    
    // Do any additional setup after loading the view, typically from a nib.
}

#pragma mark - SJAudioPlayerObserver

- (void)audioPlayer:(SJAudioPlayer *)player playWhenReadyDidChange:(BOOL)isPlayWhenReady reason:(SJPlayWhenReadyChangeReason)reason {
    _playButton.selected = isPlayWhenReady;
    _statusLabel.text = isPlayWhenReady ? @"Playing" : @"Paused";
    
    if ( isPlayWhenReady ) {
        if ( _timer == nil ) {
            __weak typeof(self) _self = self;
            _timer = [NSTimer timerWithTimeInterval:0.3 repeats:YES block:^(NSTimer * _Nonnull timer) {
                __strong typeof(_self) self = _self;
                if ( self == nil ) {
                    [timer invalidate];
                    return;
                }
                NSTimeInterval currentTime = CMTimeGetSeconds(self->_player.currentTime);
                if ( !self->_progressView.slider.isDragging )
                    self->_progressView.slider.value = currentTime;
                self->_progressView.leftText = [NSString stringWithCurrentTime:currentTime duration:self->_progressView.slider.maxValue];
            }];
            [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
            [_timer fire];
        }
    }
    else {
        if ( _timer ) {
            [_timer invalidate];
            _timer = nil;
        }
    }
}

- (void)audioPlayer:(SJAudioPlayer *)player durationDidChange:(CMTime)duration {
    NSTimeInterval secs = MAX(CMTimeGetSeconds(duration), 1);
    _progressView.slider.maxValue = secs;
    _progressView.rightText = [NSString stringWithCurrentTime:secs duration:secs];
}

- (void)audioPlayer:(SJAudioPlayer *)player errorDidChange:(NSError *_Nullable)error {
    if ( error ) _playButton.selected = NO;
}

#pragma mark - SJProgressSliderDelegate

- (void)slider:(SJProgressSlider *)slider valueDidChange:(CGFloat)value {
    if ( slider == _volumeSlider )
        _player.volume = value;
    else if ( slider == _rateSlider )
        _player.rate = value;
}

- (void)sliderDidEndDragging:(SJProgressSlider *)slider {
    if ( slider == _progressView.slider )
        [_player seekToTime:CMTimeMakeWithSeconds(slider.value, NSEC_PER_SEC)];
}

#pragma mark - mark
  
- (IBAction)playOrPause:(UIButton *)sender {
    if ( _player.URL == nil ) {
        [self replace];
    }
    else {
        _player.playWhenReady ? [_player pause] : [_player play];
    }
}

- (IBAction)replace {
    NSURL *URL = nil;
    URL = [NSBundle.mainBundle URLForResource:@"网易游戏 - 长寿村.mp3" withExtension:nil];
    [_player replaceAudioWithURL:URL];
    [_player play];
}
@end
