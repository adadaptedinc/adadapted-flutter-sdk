Pod::Spec.new do |s|
  s.name             = 'adadapted_flutter_sdk'
  s.version          = '0.1.0'
  s.summary          = 'The AdAdapted Flutter SDK.'
  s.description      = <<-DESC
Integrates the AdAdapted ad platform into a Flutter app.
                       DESC
  s.homepage         = 'https://github.com/adadaptedinc/adadapted-flutter-sdk'
  s.license          = { :type => 'AdAdapted Platform License', :file => '../LICENSE' }
  s.author           = { 'AdAdapted' => 'support@adadapted.com' }
  s.source           = { :path => '.' }
  # The same sources Package.swift builds, so CocoaPods and Swift Package
  # Manager integrations stay in step with one copy of the plugin.
  s.source_files     = 'adadapted_flutter_sdk/Sources/adadapted_flutter_sdk/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Supplies the advertising identifier and the App Tracking Transparency status.
  s.frameworks = 'AdSupport', 'AppTrackingTransparency', 'CoreTelephony'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
