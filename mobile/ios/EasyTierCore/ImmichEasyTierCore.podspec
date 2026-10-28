Pod::Spec.new do |s|
  s.name = 'ImmichEasyTierCore'
  s.version = '0.1.0'
  s.summary = 'Pinned process-local EasyTier core; no system VPN'
  s.homepage = 'https://github.com/chinghoi/immich'
  s.license = { :type => 'LGPL-3.0', :file => '../Tailnet/Licenses/EasyTier-LGPL-3.0.txt' }
  s.author = 'Immich fork contributors'
  s.source = { :path => '.' }
  s.platform = :ios, '18.1'
  s.vendored_frameworks = 'Frameworks/ImmichEasyTier.xcframework'
  s.frameworks = 'Security', 'SystemConfiguration'
  s.libraries = 'c++', 'resolv'
end
