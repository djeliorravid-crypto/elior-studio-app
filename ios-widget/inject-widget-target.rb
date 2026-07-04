#!/usr/bin/env ruby
# Injects a TaskWidget extension target + the TaskWidgetBridge plugin
# source into the Capacitor-generated Xcode project. Codemagic runs
# this after `npx cap add ios` and `npx cap sync ios` so the project
# layout is fully populated. Re-running it must be idempotent — we
# bail early if the target already exists.
#
# Dependency: gem install xcodeproj  (CocoaPods uses the same gem,
# already present on Codemagic Mac M2 images).

require 'xcodeproj'
require 'fileutils'

PROJECT_PATH    = ARGV[0] || 'ios/App/App.xcodeproj'
WIDGET_SRC_DIR  = ARGV[1] || 'ios-widget/TaskWidget'
PLUGIN_SRC_DIR  = ARGV[2] || 'ios-plugin/TaskWidgetBridge'
APP_TARGET_NAME = 'App'
WIDGET_TGT_NAME = 'TaskWidget'
BUNDLE_ID_MAIN  = 'com.ravidstudio.app'
BUNDLE_ID_WGT   = 'com.ravidstudio.app.TaskWidget'
APP_GROUP_ID    = 'group.com.ravidstudio.app'
APP_ENTITLEMENTS_SRC = 'ios-widget/App.entitlements'

abort "Project not found at #{PROJECT_PATH}" unless File.exist?(PROJECT_PATH)

project = Xcodeproj::Project.open(PROJECT_PATH)
app_target = project.targets.find { |t| t.name == APP_TARGET_NAME }
abort "Main app target '#{APP_TARGET_NAME}' not found" unless app_target

# ── 1. Copy ALL local Swift sources into the App target's folders:
#       Plugins/TaskWidgetBridgePlugin.swift   — widget data bridge
#       Plugins/BiometricBridgePlugin.swift    — Face ID via LAContext
#       BridgeViewController.swift             — registers ↑ with the
#                                                Capacitor bridge.
plugin_dest = "ios/App/App/Plugins"
FileUtils.mkdir_p(plugin_dest)
FileUtils.cp("#{PLUGIN_SRC_DIR}/TaskWidgetBridgePlugin.swift",
             "#{plugin_dest}/TaskWidgetBridgePlugin.swift")
FileUtils.cp("ios-plugin/BiometricBridge/BiometricBridgePlugin.swift",
             "#{plugin_dest}/BiometricBridgePlugin.swift")
FileUtils.cp("ios-plugin/IosCalendarBridge/IosCalendarBridgePlugin.swift",
             "#{plugin_dest}/IosCalendarBridgePlugin.swift")
FileUtils.cp("ios-plugin/HealthKitBridge/HealthKitBridgePlugin.swift",
             "#{plugin_dest}/HealthKitBridgePlugin.swift")
FileUtils.cp("ios-plugin/BridgeViewController.swift",
             "ios/App/App/BridgeViewController.swift")

app_group = project.main_group['App']
plugins_group = app_group['Plugins'] || app_group.new_group('Plugins', 'Plugins')

['TaskWidgetBridgePlugin.swift', 'BiometricBridgePlugin.swift', 'IosCalendarBridgePlugin.swift', 'HealthKitBridgePlugin.swift'].each do |fname|
  unless plugins_group.files.any? { |f| f.path == fname }
    ref = plugins_group.new_file(fname)
    app_target.add_file_references([ref])
    puts "✓ Added Plugins/#{fname} to App target"
  end
end

unless app_group.files.any? { |f| f.path == 'BridgeViewController.swift' }
  ref = app_group.new_file('BridgeViewController.swift')
  app_target.add_file_references([ref])
  puts "✓ Added BridgeViewController.swift to App target"
end

# ── 1b. Repoint Main.storyboard's initial-view-controller customClass
#        from "CAPBridgeViewController" to our subclass so the app
#        instantiates BridgeViewController (which calls our plugin
#        registrations from capacitorDidLoad).
storyboard = 'ios/App/App/Base.lproj/Main.storyboard'
if File.exist?(storyboard)
  text = File.read(storyboard)
  patched = text.sub(
    /customClass="CAPBridgeViewController"\s+customModule="Capacitor"/,
    'customClass="BridgeViewController" customModuleProvider="target"'
  )
  if patched != text
    File.write(storyboard, patched)
    puts "✓ Repointed Main.storyboard to BridgeViewController"
  else
    puts "• Main.storyboard already pointed at BridgeViewController (or pattern not found)"
  end
end

# ── 2. Stage the widget files into ios/TaskWidget/ so the Xcode
#       project references stay inside the workspace.
widget_dest = "ios/TaskWidget"
FileUtils.mkdir_p(widget_dest)
FileUtils.cp("#{WIDGET_SRC_DIR}/TaskWidget.swift",     "#{widget_dest}/TaskWidget.swift")
FileUtils.cp("#{WIDGET_SRC_DIR}/Info.plist",           "#{widget_dest}/Info.plist")
FileUtils.cp("#{WIDGET_SRC_DIR}/TaskWidget.entitlements", "#{widget_dest}/TaskWidget.entitlements")

# ── 3. Stage the App entitlements (App Group capability) and point
#       the main app at it via build settings.
app_entitlements_dest = "ios/App/App/App.entitlements"
FileUtils.cp(APP_ENTITLEMENTS_SRC, app_entitlements_dest)
app_target.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'App/App.entitlements'
end
puts "✓ Wired App.entitlements into main app target"

# ── 4. If the widget target already exists, we're done.
if project.targets.any? { |t| t.name == WIDGET_TGT_NAME }
  puts "• #{WIDGET_TGT_NAME} target already exists — saving and exiting"
  project.save
  exit 0
end

# ── 5. Create the widget extension target.
widget_target = project.new_target(:app_extension, WIDGET_TGT_NAME, :ios, '14.0')
widget_target.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER']      = BUNDLE_ID_WGT
  s['PRODUCT_NAME']                   = '$(TARGET_NAME)'
  s['INFOPLIST_FILE']                 = '$(SRCROOT)/../TaskWidget/Info.plist'
  s['CODE_SIGN_ENTITLEMENTS']         = '$(SRCROOT)/../TaskWidget/TaskWidget.entitlements'
  s['SWIFT_VERSION']                  = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET']     = '14.0'
  s['TARGETED_DEVICE_FAMILY']         = '1,2'
  s['ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME'] = 'WidgetBackground'
  s['SKIP_INSTALL']                   = 'NO'
  # CRITICAL: must be NO for app extensions. If YES, Xcode duplicates
  # libswift_Concurrency.dylib into TaskWidget.appex/Frameworks and
  # App Store rejects with code 90206 "Invalid Bundle … contains
  # disallowed file 'Frameworks'". The extension already finds Swift
  # libs via the @executable_path/../../Frameworks rpath below.
  s['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'NO'
  s['EMBEDDED_CONTENT_CONTAINS_SWIFT']       = 'NO'
  s['LD_RUNPATH_SEARCH_PATHS']        = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

# ── 6. Add the widget Swift source to the new target.
widget_group = project.main_group.new_group('TaskWidget', '../TaskWidget')
swift_ref = widget_group.new_file('TaskWidget.swift')
widget_target.add_file_references([swift_ref])

# ── 7. Embed the widget extension in the main app bundle.
embed_phase = app_target.copy_files_build_phases.find { |p| p.dst_subfolder_spec == '13' }
unless embed_phase
  embed_phase = app_target.new_copy_files_build_phase('Embed App Extensions')
  embed_phase.symbol_dst_subfolder_spec = :plug_ins  # PlugIns/ → 13
end
embed_phase.add_file_reference(widget_target.product_reference, true)

# ── 8. Make the main app build the widget first.
app_target.add_dependency(widget_target)

# ── 9. Save.
project.save
puts "✓ Created #{WIDGET_TGT_NAME} target, embedded in #{APP_TARGET_NAME}"
puts "✓ App Group: #{APP_GROUP_ID} (declared in both .entitlements files)"
puts "✓ Saved #{PROJECT_PATH}"
