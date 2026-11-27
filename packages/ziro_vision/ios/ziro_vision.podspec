Pod::Spec.new do |s|
  s.name             = 'ziro_vision'
  s.version          = '0.1.0'
  s.summary          = 'Ziro palm capture for Zend.'
  s.description      = 'Camera, hand landmarks, palm templates, flash capture, Secure Enclave device key and App Attest.'
  s.homepage         = 'https://usezend.app'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Zend' => 'dev@usezend.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.swift'
  s.dependency 'Flutter'
  s.dependency 'MediaPipeTasksVision', '0.10.20'
  s.dependency 'TensorFlowLiteSwift/CoreML', '2.17.0'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'
  s.static_framework = true
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
