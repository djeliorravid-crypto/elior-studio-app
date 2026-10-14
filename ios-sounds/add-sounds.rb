# Copies ios-sounds/*.wav into the App target's bundle resources so
# notifications can use them by file name (sound: 'maestro-signature.wav').
require 'xcodeproj'
proj_path, src_dir = ARGV
proj = Xcodeproj::Project.open(proj_path)
target = proj.targets.find { |t| t.name == 'App' } or abort('no App target')
group = proj.main_group.find_subpath('App', true)
Dir[File.join(src_dir, '*.wav')].sort.each do |f|
  name = File.basename(f)
  dest = File.join(File.dirname(proj_path), 'App', name)
  FileUtils.cp(f, dest)
  next if group.files.any? { |r| r.path == name }
  ref = group.new_reference(name)
  target.resources_build_phase.add_file_reference(ref, true)
  puts "added #{name}"
end
proj.save
