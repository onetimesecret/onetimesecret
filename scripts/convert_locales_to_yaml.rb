#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to convert JSON locale files to YAML format for ruby-i18n gem
# Usage: ruby scripts/convert_locales_to_yaml.rb

require 'json'
require 'yaml'
require 'fileutils'

# Source and destination directories
SOURCE_DIR = File.join(__dir__, '..', 'src', 'locales')
DEST_DIR = File.join(__dir__, '..', 'config', 'locales')

# Create destination directory if it doesn't exist
FileUtils.mkdir_p(DEST_DIR)

# Get all JSON locale files
json_files = Dir.glob(File.join(SOURCE_DIR, '*.json'))

puts "Converting #{json_files.length} locale files from JSON to YAML..."
puts "Source: #{SOURCE_DIR}"
puts "Destination: #{DEST_DIR}"
puts

json_files.each do |json_file|
  # Extract locale code from filename (e.g., "en" from "en.json")
  locale_code = File.basename(json_file, '.json')

  # Read and parse JSON
  json_content = File.read(json_file)
  locale_data = JSON.parse(json_content)

  # Wrap the content with the locale code as root key
  # This is required by ruby-i18n gem: each YAML file must have the locale as root
  yaml_data = { locale_code => locale_data }

  # Generate YAML filename
  yaml_file = File.join(DEST_DIR, "#{locale_code}.yml")

  # Write YAML file
  File.write(yaml_file, YAML.dump(yaml_data))

  puts "✓ Converted #{locale_code}.json → #{locale_code}.yml"
end

puts
puts "Conversion complete! #{json_files.length} files converted."
puts "YAML locale files are now in: #{DEST_DIR}"
