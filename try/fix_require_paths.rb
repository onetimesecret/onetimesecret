#!/usr/bin/env ruby
# Script to fix require_relative paths after reorganization

require 'pathname'

# Map of directory depth to relative path to support/
DEPTH_TO_SUPPORT = {
  1 => '../support',        # unit/, integration/, system/, etc.
  2 => '../../support',     # unit/models/, unit/logic/, etc.
  3 => '../../../support',  # unit/models/v2/, unit/logic/secrets/, etc.
  4 => '../../../../support',  # integration/middleware/domain_strategy/
}

def fix_file(file_path)
  content = File.read(file_path)
  original_content = content.dup

  # Calculate depth from try/ directory
  relative_path = Pathname.new(file_path).relative_path_from(Pathname.new('.'))
  depth = relative_path.to_s.split('/').size - 1  # -1 for the file itself

  support_path = DEPTH_TO_SUPPORT[depth]

  unless support_path
    puts "  WARNING: Unexpected depth #{depth} for #{file_path}"
    return
  end

  # Fix require_relative paths to support files
  content.gsub!(/require_relative '\.\.\/test_/, "require_relative '#{support_path}/test_")
  content.gsub!(/require_relative 'test_/, "require_relative '#{support_path}/test_")

  # Write back if changed
  if content != original_content
    File.write(file_path, content)
    puts "  ✓ Fixed #{file_path}"
  end
end

# Find all tryout files
tryout_files = Dir.glob('**/*_try.rb') + Dir.glob('experimental/*.rb')

puts "Fixing require_relative paths in #{tryout_files.size} files...\n"

tryout_files.each do |file|
  fix_file(file)
end

puts "\nDone! All require paths updated."
