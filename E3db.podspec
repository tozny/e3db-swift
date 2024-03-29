Pod::Spec.new do |s|
  s.name             = 'E3db'
  s.version          = '4.2.3'
  s.summary          = 'Super Easy End-to-End Encryption'
  s.swift_version    = '5.0'

  s.description      = <<-DESC
The Tozny End-to-End Encrypted Database (E3DB) is a storage platform with powerful sharing and consent management features.
E3DB provides a familiar JSON-based NoSQL-style API for reading, writing, and querying data stored securely in the cloud.
                       DESC

  s.homepage         = 'https://tozny.com/'
  s.license          = { :type => 'TOZNY NON-COMMERCIAL LICENSE', :file => 'LICENSE.md' }
  s.author           = { 'Tozny' => 'info@tozny.com' }
  s.source           = { :git => 'https://github.com/tozny/e3db-swift.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/@tozny'

  s.ios.deployment_target = '9.0'
  s.source_files = 'E3db/Classes/**/*'

  s.subspec 'Core' do |core|
    core.dependency 'ToznySwish', '~> 5.0.1'
    core.dependency 'ToznySodium', '~> 0.10.0'
    core.dependency 'Valet', '~> 3.1'
    core.dependency 'ToznyHeimdallr', '~> 4.0.2'
  end

  s.default_subspec = 'Core'
end
