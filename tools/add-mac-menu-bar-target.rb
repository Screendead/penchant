# Adds the PenchantMenuBar login-item app to macos/Runner.xcodeproj and embeds it in Penchant.app at
# Contents/Library/LoginItems, where SMAppService.loginItem finds it. It is built from
# macos/PenchantMenuBar plus the widget extension's Snapshot, LogQueue and Theme sources, and drops
# the old in-process status item. Run it on a project without the target:
#   GEM_HOME=/opt/homebrew/Cellar/cocoapods/1.16.2_2/libexec ruby tools/add-mac-menu-bar-target.rb
require 'xcodeproj'

TEAM = '8N575942RT'
SHARED = %w[Snapshot.swift LogQueue.swift Theme.swift].freeze
FONTS = %w[RedHatDisplay-Variable.ttf RedHatMono-Variable.ttf RedHatText-Variable.ttf].freeze

project = Xcodeproj::Project.open(File.expand_path('../macos/Runner.xcodeproj', __dir__))
runner = project.targets.find { |t| t.name == 'Runner' }
abort 'PenchantMenuBar already exists' if project.targets.any? { |t| t.name == 'PenchantMenuBar' }

project.files.select { |f| f.path == 'StatusItemController.swift' }.each do |ref|
  ref.build_files.each(&:remove_from_project)
  ref.remove_from_project
end

# MenuBarExtra needs macOS 13; the widgets' shared sources need 14.
app = project.new_target(:application, 'PenchantMenuBar', :osx, '14.0')
group = project.main_group.new_group('PenchantMenuBar', 'PenchantMenuBar')
app.add_file_references([group.new_reference('PenchantMenuBarApp.swift')])
group.new_reference('Info.plist')
group.new_reference('PenchantMenuBar.entitlements')
widget_shared = project.main_group.find_subpath('PenchantWidgets/Shared', false)
app.add_file_references(SHARED.map { |f| widget_shared.files.find { |r| r.path == f } })
fonts = project.main_group.find_subpath('PenchantWidgets/Fonts', false)
app.add_resources(FONTS.map { |f| fonts.files.find { |r| r.path == f } })
%w[SwiftUI WidgetKit].each { |f| app.add_system_framework(f) }

runner.build_configurations.each do |runner_config|
  config = app.build_configurations.find { |c| c.name == runner_config.name } ||
           app.add_build_configuration(runner_config.name, runner_config.name == 'Debug' ? :debug : :release)
  # Runner's xcconfig carries FLUTTER_BUILD_NAME and FLUTTER_BUILD_NUMBER for the Info.plist.
  config.base_configuration_reference = runner_config.base_configuration_reference
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.screendead.penchant.menubar',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'DEVELOPMENT_TEAM' => TEAM,
    'CODE_SIGN_STYLE' => 'Automatic',
    'CODE_SIGN_IDENTITY' => 'Apple Development',
    'CODE_SIGN_ENTITLEMENTS' => 'PenchantMenuBar/PenchantMenuBar.entitlements',
    'ENABLE_HARDENED_RUNTIME' => 'YES',
    'INFOPLIST_FILE' => 'PenchantMenuBar/Info.plist',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'SWIFT_VERSION' => '5.0',
    'SKIP_INSTALL' => 'YES',
    'MACOSX_DEPLOYMENT_TARGET' => '14.0',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/../Frameworks'],
  )
end

runner.add_dependency(app)
embed = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
embed.name = 'Embed Login Items'
embed.symbol_dst_subfolder_spec = :wrapper
embed.dst_path = 'Contents/Library/LoginItems'
embed.add_file_reference(app.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
# Crashlytics reads dSYMs only from the last phase (test/apple_project_test.dart).
upload = runner.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Upload Crashlytics symbols' }
runner.build_phases.insert(upload || runner.build_phases.size, embed)

attributes = project.root_object.attributes['TargetAttributes'] ||= {}
(attributes[app.uuid] ||= {}).merge!(
  'SystemCapabilities' => { 'com.apple.ApplicationGroups.Mac' => { 'enabled' => '1' },
                            'com.apple.Sandbox' => { 'enabled' => '1' } },
  'CreatedOnToolsVersion' => '27.2', 'ProvisioningStyle' => 'Automatic',
)

project.save
