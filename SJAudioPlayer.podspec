#
# Be sure to run `pod lib lint SJAudioPlayer.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'SJAudioPlayer'
  s.version          = '1.1.0'
  s.summary          = 'iOS Audio Player using AVAudioEngine.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = "https://github.com/changsanjiang/SJAudioPlayer/blob/master/README.md"

  s.homepage         = 'https://github.com/changsanjiang/SJAudioPlayer'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'changsanjiang' => 'changsanjiang@gmail.com' }
  s.source           = { :git => 'https://github.com/changsanjiang/SJAudioPlayer.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '13.0'

  s.source_files = 'SJAudioPlayer/*.{h,m,mm}'
  s.libraries = 'c++'
  s.vendored_frameworks = 'SJAudioPlayer/libffmpeg.xcframework'
  
#  s.subspec 'libffmpeg' do |ss|
#    ss.source_files = 'libffmpeg/libffmpeg/src/**/*.{h,m,mm,c,cpp}'
#
#    ss.vendored_frameworks =
#      'libffmpeg/libffmpeg/frameworks/libavcodec.xcframework',
#      'libffmpeg/libffmpeg/frameworks/libavfilter.xcframework',
#      'libffmpeg/libffmpeg/frameworks/libavformat.xcframework',
#      'libffmpeg/libffmpeg/frameworks/libavutil.xcframework',
#      'libffmpeg/libffmpeg/frameworks/libmp3lame.xcframework',
#      'libffmpeg/libffmpeg/frameworks/libswresample.xcframework',
#      'libffmpeg/libffmpeg/frameworks/libswscale.xcframework'
#    end
#  end
end
