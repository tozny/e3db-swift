Pod::Spec.new do |s|
  s.name             = 'E3db'
  s.version          = '1.0.0'
  s.summary          = 'Super Easy End-to-End Encryption'

  s.description      = <<-DESC
Protect your users’ data at the code level.
From the very first line to your final release, Tozny's E3db makes
protecting your users’ sensitive data as easy as a few lines of code.
                       DESC

  s.homepage         = 'https://tozny.com/'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Tozny' => 'info@tozny.com' }
  s.source           = { :git => 'https://github.com/tozny/e3db-swift.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/@tozny'

  s.ios.deployment_target = '9.0'
  s.source_files = 'E3db/Classes/**/*'

  s.subspec 'Core' do |core|
    core.dependency 'Swish', '~> 2.0'
    core.dependency 'Curry', '~> 3.0'
    core.dependency 'Sodium', '~> 0.3'
    core.dependency 'Valet', '~> 2.4'
    core.dependency 'Ogra', '~> 4.1'
    core.dependency 'Heimdallr', '~> 3.6'
  end

  s.subspec 'Logging' do |l|
    l.dependency 'ResponseDetective', '~> 1.1'
    l.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '-dE3DB_LOGGING'}
  end

  s.default_subspec = 'Core'
end
