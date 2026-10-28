Pod::Spec.new do |s|
  s.name = 'ImmichTailnet'
  s.version = '0.1.0'
  s.summary = 'Optional process-local network providers for the iOS fork'
  s.homepage = 'https://github.com/chinghoi/immich'
  s.license = { :type => 'AGPL-3.0', :file => '../../../LICENSE' }
  s.author = 'Immich fork contributors'
  s.source = { :path => '.' }
  s.platform = :ios, '18.1'
  s.swift_version = '5.0'
  s.source_files = 'Sources/**/*.swift'
  s.vendored_frameworks = 'Frameworks/TailscaleKit.xcframework', 'Frameworks/ImmichEasyTier.xcframework'
  s.frameworks = 'Security', 'SystemConfiguration'
  s.libraries = 'c++', 'resolv'
  s.resource_bundles = { 'EmbeddedNetworkNotices' => ['Licenses/*'] }
  s.dependency 'Flutter'
end
