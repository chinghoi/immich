require 'xcodeproj'
require 'pathname'
root = Pathname.new(ARGV.fetch(0)).realpath
out = Pathname.new(ARGV.fetch(1)).realpath
project = Xcodeproj::Project.new(out.join('TailnetTransport.xcodeproj'))
target = project.new_target(:unit_test_bundle, 'TailnetTransportTests', :ios, '18.1')
sources = [root.join('custom/ios-tailnet/tests/TransportTests.swift'), out.join('VideoProxyServer.swift')]
sources.each { |path| target.source_build_phase.add_file_reference(project.main_group.new_file(path.to_s)) }
target.resources_build_phase.add_file_reference(project.main_group.new_file(out.join('fixture.json').to_s))
framework = project.main_group.new_file(root.join('mobile/ios/Tailnet/Frameworks/TailscaleKit.xcframework').to_s)
target.frameworks_build_phase.add_file_reference(framework)
embed = target.new_copy_files_build_phase('Embed Frameworks')
embed.dst_subfolder_spec = '10'
embed.add_file_reference(framework)
target.build_configurations.each do |configuration|
  configuration.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'io.chinghoi.immich.transporttests',
    'GENERATE_INFOPLIST_FILE' => 'YES', 'SWIFT_VERSION' => '5.0',
    'CODE_SIGNING_ALLOWED' => 'NO', 'SUPPORTED_PLATFORMS' => 'iphonesimulator',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@loader_path/Frameworks', '@executable_path/Frameworks'],
    'TEST_HOST' => '', 'ENABLE_TESTABILITY' => 'YES'
  })
end
Xcodeproj::Plist.write_to_path({
  'CFBundleIdentifier' => '$(PRODUCT_BUNDLE_IDENTIFIER)',
  'CFBundlePackageType' => 'BNDL', 'CFBundleName' => '$(PRODUCT_NAME)',
  'CFBundleExecutable' => '$(EXECUTABLE_NAME)',
  'NSAppTransportSecurity' => { 'NSAllowsArbitraryLoads' => true }
}, out.join('Test-Info.plist'))
target.build_configurations.each do |configuration|
  configuration.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  configuration.build_settings['INFOPLIST_FILE'] = out.join('Test-Info.plist').to_s
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.add_test_target(target)
scheme.save_as(project.path, 'TailnetTransport')
