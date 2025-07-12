#!/usr/bin/env ruby
# 3_migrate_tryouts.rb - Migrate tryout files to tryouts/ directory

require 'fileutils'
require 'pathname'

puts "=== Migrating Tryout files ==="

# Mapping of numbered prefixes to new locations
MAPPINGS = {
  '00_middleware' => 'middleware',
  '05_logging' => 'utils',
  '10_onetime_utils' => 'utils',
  '10_v1_utils' => 'utils',
  '11_cached_method' => 'utils',
  '15_config' => 'config',
  '16_config_emailer' => 'config',
  '16_config_secret_options' => 'config',
  '17_mail_validation' => 'utils',
  '19_safe_dump' => 'utils',
  '20_metadata' => 'models',
  '20_models' => 'models',
  '21_secret' => 'models',
  '22_value_encryption' => 'logic',
  '23_app_settings' => 'config',
  '23_passphrase' => 'logic',
  '25_customer' => 'models',
  '26_email_receipt' => 'logic',
  '30_session' => 'models',
  '31_session_extended' => 'models',
  '35_ratelimit' => 'logic',
  '40_email_template' => 'templates',
  '42_web_template_vuepoint' => 'templates',
  '50_middleware' => 'middleware',
  '50_subdomain' => 'logic',
  '60_logic' => 'logic',
  '68_receive_feedback' => 'logic',
  '72_approximated' => 'utils',
  '75_stripe_event' => 'logic',
  '90_routes_smoketest' => 'integration',
  '91_authentication_routes' => 'integration',
  '99_truemail_config' => 'config'
}

# Process directories first
unmapped_files = []
if Dir.exist?('tests/unit/ruby/try')
  Dir.glob('tests/unit/ruby/try/*/').each do |dir|
    dirname = File.basename(dir)
    next unless dirname =~ /^\d+_/

    mapping = MAPPINGS.find { |prefix, _| dirname.start_with?(prefix) }
    if mapping
      new_path = "tryouts/#{mapping[1]}"
      FileUtils.mkdir_p(new_path)

      # Move all files from subdirectory
      Dir.glob("#{dir}*.rb").each do |file|
        filename = File.basename(file)
        new_filename = filename.gsub(/^\d+_/, '')
        dest = "#{new_path}/#{new_filename}"

        puts "Moving #{file} → #{dest}"
        system("git mv '#{file}' '#{dest}' 2>/dev/null") || FileUtils.mv(file, dest)
      end
    else
      # Handle unmapped directories
      puts "No mapping found for directory #{dirname}, moving to unmapped/"
      FileUtils.mkdir_p('tryouts/unmapped')

      Dir.glob("#{dir}*.rb").each do |file|
        filename = File.basename(file)
        dest = "tryouts/unmapped/#{dirname}_#{filename}"
        puts "Moving unmapped #{file} → #{dest}"
        system("git mv '#{file}' '#{dest}' 2>/dev/null") || FileUtils.mv(file, dest)
        unmapped_files << dest
      end
    end
  end

  # Process individual files
  Dir.glob('tests/unit/ruby/try/*.rb').each do |file|
    basename = File.basename(file)

    # Handle helper files
    if basename.start_with?('test_')
      dest = "tryouts/helpers/#{basename}"
      FileUtils.mkdir_p('tryouts/helpers')
      puts "Moving helper #{file} → #{dest}"
      system("git mv '#{file}' '#{dest}' 2>/dev/null") || FileUtils.mv(file, dest)
      next
    end

    # Find matching mapping for regular tryout files
    mapping = MAPPINGS.find { |prefix, _| basename.start_with?(prefix) }

    if mapping
      new_dir = "tryouts/#{mapping[1]}"
      FileUtils.mkdir_p(new_dir)

      # Remove number prefix but keep _try.rb suffix
      new_name = basename.gsub(/^\d+_/, '')
      dest = "#{new_dir}/#{new_name}"

      puts "Moving #{file} → #{dest}"
      system("git mv '#{file}' '#{dest}' 2>/dev/null") || FileUtils.mv(file, dest)
    else
      # Handle unmapped individual files
      puts "No mapping found for #{basename}, moving to unmapped/"
      FileUtils.mkdir_p('tryouts/unmapped')
      dest = "tryouts/unmapped/#{basename}"
      puts "Moving unmapped #{file} → #{dest}"
      system("git mv '#{file}' '#{dest}' 2>/dev/null") || FileUtils.mv(file, dest)
      unmapped_files << dest
    end
  end
end

# Update requires in moved files
puts "\nUpdating require statements..."
Dir.glob('tryouts/**/*.rb').each do |file|
  content = File.read(file)
  original_content = content.dup

  # Update test helper requires
  content.gsub!(/require_relative ['"].*test_helpers['"]/, "require_relative '../helpers/test_helpers'")
  content.gsub!(/require_relative ['"].*test_logic['"]/, "require_relative '../helpers/test_logic'")
  content.gsub!(/require_relative ['"].*test_models['"]/, "require_relative '../helpers/test_models'")

  # Update config paths
  content.gsub!(%r{['"]\.\.?/.*config\.test\.yaml['"]}, "'../tests/unit/ruby/config.test.yaml'")

  if content != original_content
    File.write(file, content)
    puts "Updated requires in #{file}"
  end
end

# Copy config files
if File.exist?('tests/unit/ruby/config.test.yaml')
  puts "\nCopying test configuration..."
  FileUtils.cp('tests/unit/ruby/config.test.yaml', 'tryouts/config.test.yaml')
end

# Generate unmapped files report
if unmapped_files.any?
  puts "\n⚠ UNMAPPED FILES REPORT"
  puts "The following files were moved to tryouts/unmapped/ for manual review:"
  unmapped_files.each { |file| puts "  #{file}" }
  puts ""
  puts "Please review these files and:"
  puts "1. Determine appropriate categories for them"
  puts "2. Update the MAPPINGS hash in this script if needed"
  puts "3. Move them to proper locations manually"
  puts ""

  # Write unmapped files list to a file for easy reference
  File.write('tryouts/UNMAPPED_FILES.txt', unmapped_files.join("\n"))
  puts "List saved to: tryouts/UNMAPPED_FILES.txt"
end

puts "\n✓ Tryouts migration completed"
puts "\nNext steps:"
puts "1. Review moved files in tryouts/ directory"
if unmapped_files.any?
  puts "2. Review and categorize unmapped files in tryouts/unmapped/"
  puts "3. Test tryouts with: bundle exec try tryouts/**/*_try.rb"
  puts "4. Run ./4_update_ci.sh to update CI configuration"
else
  puts "2. Test tryouts with: bundle exec try tryouts/**/*_try.rb"
  puts "3. Run ./4_update_ci.sh to update CI configuration"
end
