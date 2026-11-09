# Adds the macOS PenchantWidgets WidgetKit extension to macos/Runner.xcodeproj, built from the iOS
# extension's Swift sources in ios/PenchantWidgets, and gives the Mac app the bridge and the log
# intent. The App Group entitlements are in macos/Runner/*.entitlements and
# macos/PenchantWidgets/PenchantWidgets.entitlements. Run it on a project without the target:
#   GEM_HOME=/opt/homebrew/Cellar/cocoapods/1.16.2_2/libexec ruby tools/add-mac-widget-target.rb
# To change the target's files, check out master's project.pbxproj and run it again.
require 'xcodeproj'

TEAM = '8N575942RT'
# LogControl.swift compiles to nothing on macOS; it is left out.
SOURCES = %w[PenchantWidgets.swift Snapshot.swift Theme.swift WeekDial.swift LastWeekWidget.swift LogQueue.swift
             LogIntents.swift LogWidget.swift].freeze
SHARED = %w[Snapshot.swift LogQueue.swift LogIntents.swift].freeze
FONTS = %w[RedHatDisplay-Variable.ttf RedHatMono-Variable.ttf RedHatText-Variable.ttf].freeze

project_path = File.expand_path('../macos/Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |t| t.name == 'Runner' }
abort 'PenchantWidgets already exists' if project.targets.any? { |t| t.name == 'PenchantWidgets' }

# Interactive widgets and AppIntentConfiguration need macOS 14.
ext = project.new_target(:app_extension, 'PenchantWidgets', :osx, '14.0')
group = project.main_group.new_group('PenchantWidgets', 'PenchantWidgets')
group.new_reference('Info.plist')
group.new_reference('PenchantWidgets.entitlements')
shared = group.new_group('Shared', '../../ios/PenchantWidgets')
refs = SOURCES.to_h { |f| [f, shared.new_reference(f)] }
ext.add_file_references(refs.values)
fonts = group.new_group('Fonts', '../../assets/fonts')
ext.add_resources(FONTS.map { |f| fonts.new_reference(f) })
%w[WidgetKit SwiftUI].each { |f| ext.add_system_framework(f) }

runner_group = project.main_group.find_subpath('Runner', false)
ios_runner = runner_group.new_group('iOS shared', '../../ios/Runner')
runner.add_file_references(%w[WidgetBridge.swift AppShortcuts.swift].map { |f| ios_runner.new_reference(f) })
runner.add_file_references(SHARED.map { |f| refs[f] })

runner.build_configurations.each do |runner_config|
  config = ext.build_configurations.find { |c| c.name == runner_config.name } ||
           ext.add_build_configuration(runner_config.name, runner_config.name == 'Debug' ? :debug : :release)
  # Runner's xcconfig carries Flutter's FLUTTER_BUILD_NAME and FLUTTER_BUILD_NUMBER, which the
  # extension's Info.plist takes as its version.
  config.base_configuration_reference = runner_config.base_configuration_reference
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.screendead.penchant.widgets',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'DEVELOPMENT_TEAM' => TEAM,
    'CODE_SIGN_STYLE' => 'Automatic',
    'CODE_SIGN_IDENTITY' => 'Apple Development',
    'CODE_SIGN_ENTITLEMENTS' => 'PenchantWidgets/PenchantWidgets.entitlements',
    'ENABLE_HARDENED_RUNTIME' => 'YES',
    'INFOPLIST_FILE' => 'PenchantWidgets/Info.plist',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'SWIFT_VERSION' => '5.0',
    'SKIP_INSTALL' => 'YES',
    'MACOSX_DEPLOYMENT_TARGET' => '14.0',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/../Frameworks', '@executable_path/../../../../Frameworks'],
  )
  # AppIntents arrived in macOS 13 and the app runs on 12.
  runner_config.build_settings['OTHER_LDFLAGS'] = ['$(inherited)', '-weak_framework', 'AppIntents']
end

runner.add_dependency(ext)
embed = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
embed.name = 'Embed Foundation Extensions'
embed.symbol_dst_subfolder_spec = :plug_ins
embed.add_file_reference(ext.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
# Crashlytics reads dSYMs only from the last phase (test/apple_project_test.dart).
upload = runner.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Upload Crashlytics symbols' }
runner.build_phases.insert(upload || runner.build_phases.size, embed)

attributes = project.root_object.attributes['TargetAttributes'] ||= {}
groups = { 'SystemCapabilities' => { 'com.apple.ApplicationGroups.Mac' => { 'enabled' => '1' },
                                     'com.apple.Sandbox' => { 'enabled' => '1' } } }
(attributes[runner.uuid] ||= {}).merge!(groups)
(attributes[ext.uuid] ||= {}).merge!(groups).merge!('CreatedOnToolsVersion' => '27.2', 'ProvisioningStyle' => 'Automatic')

project.save
