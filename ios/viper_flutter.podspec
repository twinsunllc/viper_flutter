# For apps that still build iOS with CocoaPods; Swift Package Manager uses Package.swift.
Pod::Spec.new do |s|
  s.name             = 'viper_flutter'
  s.version          = '0.2.1'
  s.summary          = "Viper for Flutter apps: the screenshot and shake on iOS."
  s.description      = "Viper's native side for Flutter apps on iOS."
  s.homepage         = 'https://github.com/twinsunllc/viper_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Twin Sun' => 'dev@twinsunsolutions.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'viper_flutter/Sources/viper_flutter/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.9'
end
