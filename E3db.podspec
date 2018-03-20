Pod::Spec.new do |s|
  s.name             = 'E3db'
  s.version          = '1.0.0'
  s.summary          = 'Super Easy End-to-End Encryption'

  s.description      = <<-DESC
The Tozny End-to-End Encrypted Database (E3DB) is a storage platform with powerful sharing and consent management features.
E3DB provides a familiar JSON-based NoSQL-style API for reading, writing, and querying data stored securely in the cloud.
                       DESC

  s.homepage         = 'https://tozny.com/'
  s.license          = { :file => 'LICENSE.md' }
  s.author           = { 'Tozny' => 'info@tozny.com' }
  s.source           = { :git => 'https://github.com/tozny/e3db-swift.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/@tozny'

  s.ios.deployment_target = '9.0'
  s.source_files = 'E3db/Classes/**/*'

  s.subspec 'Core' do |core|
    core.dependency 'Swish', '~> 2.0'
    core.dependency 'Curry', '~> 4.0'
    core.dependency 'Sodium', '~> 0.6'
    core.dependency 'Valet', '~> 3.0'
    core.dependency 'Ogra', '~> 4.1'
    core.dependency 'Heimdallr', '~> 3.6'
  end

  s.subspec 'Logging' do |l|
    l.dependency 'ResponseDetective', '~> 1.2'
    l.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '-DE3DB_LOGGING' }
  end

  s.default_subspec = 'Core'
end
