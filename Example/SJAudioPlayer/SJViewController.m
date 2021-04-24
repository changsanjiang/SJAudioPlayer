//
//  SJViewController.m
//  SJAudioPlayer
//
//  Created by changsanjiang@gmail.com on 04/19/2021.
//  Copyright (c) 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "SJViewController.h"
#import "APInterfaces.h"
#import "SJAudioPlayer.h"
#import "SJButtonProgressSlider.h"
#import "NSString+SJBaseVideoPlayerExtended.h"
#import "APTimer.h"
#import "APLogger.h"

@interface SJViewController ()<SJProgressSliderDelegate, SJAudioPlayerObserver>
@property (weak, nonatomic) IBOutlet SJButtonProgressSlider *progressView;
@property (weak, nonatomic) IBOutlet SJProgressSlider *volumeSlider;
@property (weak, nonatomic) IBOutlet SJProgressSlider *RateSlider;
@property (weak, nonatomic) IBOutlet UILabel *statusLabel;
@property (weak, nonatomic) IBOutlet UIButton *playButton;
@property (nonatomic, strong) SJAudioPlayer *player;
@property (nonatomic, strong) APTimer *timer;
@end

@implementation SJViewController

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self _setupViews];
    [self _setupPlayer];
    // Do any additional setup after loading the view, typically from a nib.
}
 
- (void)_setupPlayer {
    APLogger.shared.enabledConsoleLog = YES;
    
   __weak typeof(self) _self = self;
   _timer = [APTimer.alloc initWithQueue:dispatch_get_main_queue() start:0 interval:0.2 repeats:YES block:^(APTimer * _Nonnull timer) {
       __strong typeof(_self) self = _self;
       if ( self == nil ) {
           [timer invalidate];
           return;
       }
       [self _updateTime];
   }];
    
    _player = SJAudioPlayer.alloc.init;
    [_player registerObserver:self];
}

#pragma mark - SJAudioPlayerObserver

- (void)audioPlayer:(SJAudioPlayer *)player statusDidChange:(APAudioPlaybackStatus)status {
    BOOL isPaused = player.status & APAudioPlaybackStatusPaused;
    _playButton.selected = !isPaused;
     
    // 播放态
    if ( player.status & APAudioPlaybackStatusPlaying ) {
        switch ( player.status ) {
            case APAudioPlaybackStatusPlaying:
                [_timer resume];
                _statusLabel.text = @"APAudioPlaybackStatusPlaying";
                break;
            case APAudioPlaybackStatusEvaluating:
                _statusLabel.text = @"APAudioPlaybackStatusEvaluating";
                break;
            case APAudioPlaybackStatusBuffering:
                _statusLabel.text = @"APAudioPlaybackStatusBuffering";
                break;
            case APAudioPlaybackStatusNoItemToPlay:
                _statusLabel.text = @"APAudioPlaybackStatusNoItemToPlay";
                break;
            default: break;
        }
    }
    // 暂停态
    else {
        [_timer suspend];
        switch ( player.status ) {
            case APAudioPlaybackStatusPaused:
                _statusLabel.text = @"APAudioPlaybackStatusPaused";
                break;
            case APAudioPlaybackStatusEnded:
                _statusLabel.text = @"APAudioPlaybackStatusEnded";
                break;
            case APAudioPlaybackStatusError:
                _statusLabel.text = @"APAudioPlaybackStatusError";
                break;
            default: break;
        }
    }
}

- (void)audioPlayer:(SJAudioPlayer *)player bufferProgressDidChange:(float)progress {
    _progressView.slider.bufferProgress = player.bufferProgress;
}

#pragma mark - SJProgressSliderDelegate

- (void)slider:(SJProgressSlider *)slider valueDidChange:(CGFloat)value {
    if ( slider == _volumeSlider )
        _player.volume = value;
    else if ( slider == _RateSlider )
        _player.rate = value;
}

- (void)sliderDidEndDragging:(SJProgressSlider *)slider {
    if ( slider == _progressView.slider )
        [_player seekToTime:slider.value];
}

#pragma mark - mark
  
- (IBAction)playOrPause:(UIButton *)sender {
    if ( _player.URL == nil ) {
        [self replace];
    }
    else {
        if ( _player.status == APAudioPlaybackStatusEnded )
            [_player seekToTime:0];
        else if ( _player.status == APAudioPlaybackStatusError ) {
            [_player reload];
            [_player play];
        }
        else
            _player.status & APAudioPlaybackStatusPlaying ? [_player pause] : [_player play];
    }
}

- (IBAction)replace {
    NSURL *URL = nil;
    URL = [NSBundle.mainBundle URLForResource:@"网易游戏 - 长寿村" withExtension:@"mp3"];
    [_player replaceAudioWithURL:URL];
    [_player play];
}

#pragma mark - mark

- (void)_updateTime {
    NSTimeInterval duration = _player.duration ?: 1;
    NSTimeInterval currentTime = _player.currentTime;
    
    _progressView.slider.maxValue = duration ?: 1;
    if ( !_progressView.slider.isDragging )
        _progressView.slider.value = currentTime;
    

    _progressView.leftText = [NSString stringWithCurrentTime:currentTime duration:duration];
    _progressView.rightText = [NSString stringWithCurrentTime:duration duration:duration];
}

- (void)_setupViews {
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
    _progressView.slider.tappedExeBlock = ^(SJProgressSlider * _Nonnull slider, CGFloat location) {
        __strong typeof(_self) self = _self;
        if ( self == nil ) return;
        [self.player seekToTime:location];
    };
    
    _volumeSlider.delegate =
    _RateSlider.delegate = self;
    _volumeSlider.value = 1;
    _RateSlider.maxValue = 1.5;
    _RateSlider.minValue = 0.5;
    _RateSlider.value = 1;
}
@end
