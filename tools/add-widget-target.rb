# Adds the PenchantWidgets WidgetKit extension to ios/Runner.xcodeproj, gives Runner and the
# extension the App Group entitlement, and adds Runner's WidgetBridge.swift. Run it on a project
# without the target, with the xcodeproj gem that Homebrew's CocoaPods bundles:
#   GEM_HOME=/opt/homebrew/Cellar/cocoapods/1.16.2_2/libexec ruby tools/add-widget-target.rb
# To change the target's files, check out master's project.pbxproj and run it again.
require 'xcodeproj'

TEAM = '8N575942RT'
SOURCES = %w[PenchantWidgets.swift Snapshot.swift Theme.swift WeekDial.swift LastWeekWidget.swift].freeze
FONTS = %w[RedHatDisplay-Variable.ttf RedHatMono-Variable.ttf RedHatText-Variable.ttf].freeze

project_path = File.expand_path('../ios/Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |t| t.name == 'Runner' }
abort 'PenchantWidgets already exists' if project.targets.any? { |t| t.name == 'PenchantWidgets' }

ext = project.new_target(:app_extension, 'PenchantWidgets', :ios, '17.0')
group = project.main_group.new_group('PenchantWidgets', 'PenchantWidgets')
ext.add_file_references(SOURCES.map { |f| group.new_reference(f) })
group.new_reference('Info.plist')
group.new_reference('PenchantWidgets.entitlements')
# The app's fonts, referenced where Flutter keeps them rather than copied.
fonts = group.new_group('Fonts', '../../assets/fonts')
ext.add_resources(FONTS.map { |f| fonts.new_reference(f) })
%w[WidgetKit SwiftUI].each { |f| ext.add_system_framework(f) }

runner_group = project.main_group.find_subpath('Runner', false)
runner.add_file_references([runner_group.new_reference('WidgetBridge.swift')])
runner_group.new_reference('Runner.entitlements')

xcconfig = ->(name) { project.files.find { |f| f.path == "Flutter/#{name}.xcconfig" } }
runner.build_configurations.each do |runner_config|
  config = ext.build_configurations.find { |c| c.name == runner_config.name } ||
           ext.add_build_configuration(runner_config.name, runner_config.name == 'Debug' ? :debug : :release)
  # Flutter's xcconfig carries FLUTTER_BUILD_NAME and FLUTTER_BUILD_NUMBER, which the extension's
  # Info.plist takes as its version so that it always matches the app's.
  config.base_configuration_reference = runner_config.base_configuration_reference ||
                                        xcconfig.call(runner_config.name == 'Debug' ? 'Debug' : 'Release')
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.screendead.penchant.widgets',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'DEVELOPMENT_TEAM' => TEAM,
    'CODE_SIGN_STYLE' => 'Automatic',
    'CODE_SIGN_ENTITLEMENTS' => 'PenchantWidgets/PenchantWidgets.entitlements',
    'INFOPLIST_FILE' => 'PenchantWidgets/Info.plist',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'SWIFT_VERSION' => '5.0',
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'SKIP_INSTALL' => 'YES',
    'IPHONEOS_DEPLOYMENT_TARGET' => '17.0',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
  )
  runner_config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

runner.add_dependency(ext)
embed = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
embed.name = 'Embed Foundation Extensions'
embed.symbol_dst_subfolder_spec = :plug_ins
embed.add_file_reference(ext.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
# Before Flutter's Thin Binary script, or Xcode reports a dependency cycle in Runner.
thin = runner.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
runner.build_phases.insert(thin, embed)

attributes = project.root_object.attributes['TargetAttributes'] ||= {}
groups = { 'SystemCapabilities' => { 'com.apple.ApplicationGroups.iOS' => { 'enabled' => '1' } } }
(attributes[runner.uuid] ||= {}).merge!(groups)
(attributes[ext.uuid] ||= {}).merge!(groups).merge!('CreatedOnToolsVersion' => '27.2', 'ProvisioningStyle' => 'Automatic')

project.save
