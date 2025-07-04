# Rakefile

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

# RSFC specific tasks
namespace :rsfc do
  desc "Run RSFC tests only"
  task :test do
    system("bundle exec rspec spec/rsfc/")
  end

  desc "Generate RSFC documentation"
  task :docs do
    system("bundle exec yard doc lib/rsfc/")
  end

  desc "Validate RSFC templates in examples"
  task :validate do
    require 'rsfc'

    examples_dir = File.join(__dir__, 'examples', 'templates')
    if Dir.exist?(examples_dir)
      Dir.glob(File.join(examples_dir, '**', '*.rue')).each do |file|
        puts "Validating #{file}..."
        begin
          RSFC::Parser.parse_file(file)
          puts "  ✓ Valid"
        rescue => e
          puts "  ✗ Error: #{e.message}"
        end
      end
    else
      puts "No examples directory found at #{examples_dir}"
    end
  end
end
