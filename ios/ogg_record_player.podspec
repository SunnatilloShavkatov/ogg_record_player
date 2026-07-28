#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint ogg_record_player.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'ogg_record_player'
  s.version          = '1.5.0'
  s.summary          = 'An ogg opus file player and recorder for flutter.'
  s.description      = <<-DESC
An ogg opus file player and recorder for flutter.
                       DESC
  s.homepage         = 'https://github.com/SunnatilloShavkatov/ogg_record_player'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Sunnatillo Shavkatov' => 'sunnatilloshavkatov@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'ogg_record_player/Sources/ogg_record_player/**/*.swift',
                   'ogg_record_player/Sources/ogg_record_player_c/opusenc_set_bitrate.c',
                   'ogg_record_player/Sources/ogg_record_player_c/include/*.h'
  s.public_header_files = 'ogg_record_player/Sources/ogg_record_player_c/include/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  s.ios.vendored_frameworks = 'ogg_record_player/Frameworks/libogg.xcframework',
                              'ogg_record_player/Frameworks/libopus.xcframework',
                              'ogg_record_player/Frameworks/libopusenc.xcframework',
                              'ogg_record_player/Frameworks/libopusfile.xcframework'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'ENABLE_BITCODE' => 'NO',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/ogg_record_player/Sources/ogg_record_player_c/include"',
  }
  s.swift_version = '5.0'
end
