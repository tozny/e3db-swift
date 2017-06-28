#
# Be sure to run `pod lib lint E3db.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'E3db'
  s.version          = '0.1.0'
  s.summary          = 'A short description of E3db.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/gstro/E3db'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'gstro' => 'gstromire@gmail.com' }
  s.source           = { :git => 'https://github.com/gstro/E3db.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '8.0'

  s.source_files = 'E3db/Classes/**/*'
  
  # s.resource_bundles = {
  #   'E3db' => ['E3db/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'

  s.dependency 'Swish', '~> 2.0'
  s.dependency 'Curry', '~> 3.0'
  s.dependency 'ResponseDetective', '~> 1.1'
  s.dependency 'Sodium', '~> 0.3'
  s.dependency 'Valet', '~> 2.4'
end
