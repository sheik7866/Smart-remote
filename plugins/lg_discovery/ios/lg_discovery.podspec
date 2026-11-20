Pod::Spec.new do |s|
  s.name             = 'lg_discovery'
  s.version          = '0.1.0'
  s.summary          = 'Native discovery helpers for LG webOS TVs'
  s.description      = <<-DESC
Android multicast lock and iOS Bonjour browsing used by Smart Remote.
                       DESC
  s.homepage         = 'https://github.com/sheik7866/Smart-remote'
  s.license          = { :type => 'Proprietary', :text => 'All rights reserved.' }
  s.author           = { 'Smart Remote' => 'noreply@github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
end
