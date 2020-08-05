Pod::Spec.new do |s|
  s.name             = '${POD_NAME}'
  s.version          = '0.1.0'
  s.summary          = 'A short description of ${POD_NAME}.'
  s.homepage         = 'https://github.com/${USER_NAME}/${POD_NAME}'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { '${USER_NAME}' => '${USER_EMAIL}' }
  s.source           = { :git => '', :tag => s.version.to_s } # Used only locally for now

  s.ios.deployment_target = '11.0'
  # s.osx.deployment_target = '10.9'
  s.swift_versions = '5.0'
  s.source_files = '${POD_NAME}/Classes/**/*'
end