Pod::Spec.new do |s|
  s.name             = 'dhruva_connectors'
  s.version          = '0.1.0'
  s.summary          = 'Native side of the Dhruva connectors (folder grant, charging state).'
  s.description      = <<-DESC
First-party, in-repo plugin. No network access.
                       DESC
  s.homepage         = 'https://github.com/AnshRajput/dhruva-app'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Dhruva' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
