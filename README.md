# SJAudioPlayer

[![CI Status](https://img.shields.io/travis/changsanjiang@gmail.com/SJAudioPlayer.svg?style=flat)](https://travis-ci.org/changsanjiang@gmail.com/SJAudioPlayer)
[![Version](https://img.shields.io/cocoapods/v/SJAudioPlayer.svg?style=flat)](https://cocoapods.org/pods/SJAudioPlayer)
[![License](https://img.shields.io/cocoapods/l/SJAudioPlayer.svg?style=flat)](https://cocoapods.org/pods/SJAudioPlayer)
[![Platform](https://img.shields.io/cocoapods/p/SJAudioPlayer.svg?style=flat)](https://cocoapods.org/pods/SJAudioPlayer)

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

## Installation

SJAudioPlayer is available through [CocoaPods](https://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'SJAudioPlayer'
```

## Usage

```Objective-C
#import <SJAudioPlayer/SJAudioPlayer.h>

    NSURL *URL = [NSURL URLWithString:@"http://.../auido.mp3"];
    _player = SJAudioPlayer.player;
    [_player replaceAudioWithURL:URL];
    [_player play];
```

## Author

changsanjiang@gmail.com, changsanjiang@gmail.com

## License

SJAudioPlayer is available under the MIT license. See the LICENSE file for more info.
