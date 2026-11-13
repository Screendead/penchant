# Adds the PenchantSync background-only app to macos/Runner.xcodeproj and embeds it in Penchant.app
# at Contents/Library/LoginItems beside PenchantMenuBar. It runs the enclosing app's Dart headless,
# so it links the Flutter plugins, loads FlutterMacOS.framework and App.framework from Penchant.app,
# and carries its own GoogleService-Info.plist (stripped for emulator builds, as Runner's is). Run it
# on a project without the target:
#   GEM_HOME=/opt/homebrew/Cellar/cocoapods/1.16.2_2/libexec ruby tools/add-mac-sync-target.rb
require 'xcodeproj'

TEAM = '8N575942RT'
SHARED = %w[Snapshot.swift LogQueue.swift].freeze

project = Xcodeproj::Project.open(File.expand_path('../macos/Runner.xcodeproj', __dir__))
runner = project.targets.find { |t| t.name == 'Runner' }
assemble = project.targets.find { |t| t.name == 'Flutter Assemble' }
abort 'PenchantSync already exists' if project.targets.any? { |t| t.name == 'PenchantSync' }

ref = ->(path) { project.files.find { |f| f.path == path } || abort("no file reference #{path}") }

app = project.new_target(:application, 'PenchantSync', :osx, '14.0')
group = project.main_group.new_group('PenchantSync', 'PenchantSync')
app.add_file_references([group.new_reference('PenchantSyncApp.swift')])
%w[Info.plist DebugProfile.entitlements Release.entitlements].each { |f| group.new_reference(f) }
app.add_file_references(
  [ref.call('GeneratedPluginRegistrant.swift'), ref.call('WidgetBridge.swift')] + SHARED.map { |f| ref.call(f) },
)
app.add_resources([ref.call('Runner/GoogleService-Info.plist')])

# The plugins link statically, so this executable gets its own copy of them.
plugins = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
plugins.product_name = 'FlutterGeneratedPluginSwiftPackage'
app.package_product_dependencies << plugins
linked = project.new(Xcodeproj::Project::Object::PBXBuildFile)
linked.product_ref = plugins
app.frameworks_build_phase.files << linked

strip = app.new_shell_script_build_phase('Strip Firebase plist for emulators')
strip.always_out_of_date = '1'
strip.shell_script = "/bin/sh \"$SRCROOT/../tools/strip-firebase-plist.sh\"\n"

runner.build_configurations.each do |runner_config|
  config = app.build_configurations.find { |c| c.name == runner_config.name } ||
           app.add_build_configuration(runner_config.name, runner_config.name == 'Debug' ? :debug : :release)
  config.base_configuration_reference = runner_config.base_configuration_reference
  entitlements = runner_config.name == 'Release' ? 'Release' : 'DebugProfile'
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.screendead.penchant.sync',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'DEVELOPMENT_TEAM' => TEAM,
    'CODE_SIGN_STYLE' => 'Automatic',
    'CODE_SIGN_IDENTITY' => 'Apple Development',
    'CODE_SIGN_ENTITLEMENTS' => "PenchantSync/#{entitlements}.entitlements",
    'INFOPLIST_FILE' => 'PenchantSync/Info.plist',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'SWIFT_VERSION' => '5.0',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) PENCHANT_SYNC',
    'SKIP_INSTALL' => 'YES',
    'MACOSX_DEPLOYMENT_TARGET' => '14.0',
    # Contents/Library/LoginItems/PenchantSync.app/Contents/MacOS, five levels below Penchant.app/Contents.
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/../Frameworks',
                                  '@executable_path/../../../../../Frameworks'],
  )
  config.build_settings.delete('ENABLE_HARDENED_RUNTIME')
end

app.add_dependency(assemble)
runner.add_dependency(app)
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Login Items' } || abort('no Embed Login Items')
embed.add_file_reference(app.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

attributes = project.root_object.attributes['TargetAttributes'] ||= {}
(attributes[app.uuid] ||= {}).merge!(
  'SystemCapabilities' => { 'com.apple.ApplicationGroups.Mac' => { 'enabled' => '1' },
                            'com.apple.Sandbox' => { 'enabled' => '1' } },
  'CreatedOnToolsVersion' => '27.2', 'ProvisioningStyle' => 'Automatic',
)

project.save
