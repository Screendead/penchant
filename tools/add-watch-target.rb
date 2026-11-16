# Adds the Apple Watch app (PenchantWatch) and its complications (PenchantWatchWidgets, a WidgetKit
# extension inside it) to ios/Runner.xcodeproj, embeds the watch app in Runner ("Embed Watch Content")
# and adds Runner's side of the link. Every step finds what is already there before adding it, so a
# second run changes nothing; run it again after adding a file to a list below:
#   GEM_HOME=/opt/homebrew/Cellar/cocoapods/1.16.2_2/libexec ruby tools/add-watch-target.rb
# Flutter's tool finds the companion by WKCompanionAppBundleIdentifier in ios/<target name>/Info.plist
# (IosProject.containsWatchCompanion), so the watch app's folder must keep the target's name.
require 'xcodeproj'

TEAM = '8N575942RT'
WATCHOS = '10.0'
APP = 'PenchantWatch'
EXT = 'PenchantWatchWidgets'
# Compiled into Runner too: what the iPhone sends and receives.
MODEL = %w[WatchModel.swift].freeze
# The watch app and its complications both read the watch's copy of the snapshot.
ON_WATCH = %w[WatchStore.swift WatchTheme.swift].freeze
APP_SOURCES = %w[PenchantWatchApp.swift WatchSession.swift HabitList.swift].freeze
EXT_SOURCES = %w[Complications.swift].freeze
RUNNER_SOURCES = %w[WatchLink.swift].freeze
FONTS = %w[RedHatDisplay-Variable.ttf RedHatMono-Variable.ttf RedHatText-Variable.ttf].freeze

project = Xcodeproj::Project.open(File.expand_path('../ios/Runner.xcodeproj', __dir__))
runner = project.targets.find { |t| t.name == 'Runner' }

target = lambda do |name, type|
  project.targets.find { |t| t.name == name } || project.new_target(type, name, :watchos, WATCHOS)
end
group = lambda do |name|
  project.main_group.children.find { |g| g.display_name == name } || project.main_group.new_group(name, name)
end
ref = lambda do |parent, path|
  parent.files.find { |f| f.path == path } || parent.new_reference(path)
end
compile = lambda do |t, refs|
  have = t.source_build_phase.files_references
  t.add_file_references(refs.reject { |r| have.include?(r) })
end
bundle = lambda do |t, refs|
  have = t.resources_build_phase.files_references
  t.add_resources(refs.reject { |r| have.include?(r) })
end
depend = lambda do |t, on|
  t.add_dependency(on) unless t.dependencies.any? { |d| d.target == on }
end
embed = lambda do |t, name, product|
  phase = t.copy_files_build_phases.find { |p| p.name == name }
  unless phase
    phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
    phase.name = name
    yield_phase = t.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
    # Before Flutter's Thin Binary script, or Xcode reports a dependency cycle in Runner.
    yield_phase ? t.build_phases.insert(yield_phase, phase) : t.build_phases << phase
  end
  unless phase.files_references.include?(product)
    phase.add_file_reference(product).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  end
  phase
end

app = target.call(APP, :application)
ext = target.call(EXT, :app_extension)

app_group = group.call(APP)
ext_group = group.call(EXT)
model = MODEL.map { |f| ref.call(app_group, f) }
on_watch = ON_WATCH.map { |f| ref.call(app_group, f) }
compile.call(app, model + on_watch + APP_SOURCES.map { |f| ref.call(app_group, f) })
compile.call(ext, model + on_watch + EXT_SOURCES.map { |f| ref.call(ext_group, f) })
bundle.call(app, [ref.call(app_group, 'Assets.xcassets')])
%w[Info.plist PenchantWatch.entitlements].each { |f| ref.call(app_group, f) }
%w[Info.plist PenchantWatchWidgets.entitlements].each { |f| ref.call(ext_group, f) }
# The app's fonts, the references the iPhone widgets already hold.
fonts = project.files.select { |f| FONTS.include?(f.path) }
abort 'The font references of tools/add-widget-target.rb are missing' unless fonts.size == FONTS.size
bundle.call(app, fonts)

runner_group = project.main_group.find_subpath('Runner', false)
compile.call(runner, model + RUNNER_SOURCES.map { |f| ref.call(runner_group, f) })

runner.build_configurations.each do |runner_config|
  { app => ['com.screendead.penchant.watchkitapp', "#{APP}/Info.plist", "#{APP}/#{APP}.entitlements"],
    ext => ['com.screendead.penchant.watchkitapp.widgets', "#{EXT}/Info.plist", "#{EXT}/#{EXT}.entitlements"] }
    .each do |t, (bundle_id, plist, entitlements)|
    config = t.build_configurations.find { |c| c.name == runner_config.name } ||
             t.add_build_configuration(runner_config.name, runner_config.name == 'Debug' ? :debug : :release)
    # Flutter's xcconfig carries FLUTTER_BUILD_NAME and FLUTTER_BUILD_NUMBER: a watch app's version
    # must be its iPhone app's.
    config.base_configuration_reference = runner_config.base_configuration_reference
    config.build_settings.merge!(
      'PRODUCT_BUNDLE_IDENTIFIER' => bundle_id,
      'PRODUCT_NAME' => '$(TARGET_NAME)',
      'DEVELOPMENT_TEAM' => TEAM,
      'CODE_SIGN_STYLE' => 'Automatic',
      'CODE_SIGN_ENTITLEMENTS' => entitlements,
      'INFOPLIST_FILE' => plist,
      'GENERATE_INFOPLIST_FILE' => 'NO',
      'SWIFT_VERSION' => '5.0',
      # The project's own settings name the iPhone.
      'SDKROOT' => 'watchos',
      'SUPPORTED_PLATFORMS' => 'watchos watchsimulator',
      'TARGETED_DEVICE_FAMILY' => '4',
      'WATCHOS_DEPLOYMENT_TARGET' => WATCHOS,
      'SKIP_INSTALL' => 'YES',
    )
  end
  app_settings = app.build_configurations.find { |c| c.name == runner_config.name }.build_settings
  app_settings.merge!(
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks'],
  )
  # The catalog holds the icon alone; the colours are in WatchTheme.swift.
  app_settings.delete('ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME')
  ext.build_configurations.find { |c| c.name == runner_config.name }.build_settings.merge!(
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
  )
end

depend.call(app, ext)
embed.call(app, 'Embed Foundation Extensions', ext.product_reference).symbol_dst_subfolder_spec = :plug_ins
depend.call(runner, app)
watch_content = embed.call(runner, 'Embed Watch Content', app.product_reference)
watch_content.symbol_dst_subfolder_spec = :products_directory
watch_content.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'

attributes = project.root_object.attributes['TargetAttributes'] ||= {}
[app, ext].each do |t|
  (attributes[t.uuid] ||= {}).merge!(
    'CreatedOnToolsVersion' => '27.2', 'ProvisioningStyle' => 'Automatic',
    'SystemCapabilities' => { 'com.apple.ApplicationGroups.iOS' => { 'enabled' => '1' } },
  )
end

project.save
