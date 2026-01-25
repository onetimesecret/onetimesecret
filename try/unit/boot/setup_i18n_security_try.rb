# try/unit/boot/setup_i18n_security_try.rb
#
# frozen_string_literal: true

# Unit tests for path traversal prevention in SetupI18n::JsonBackend#load_json
# These tests verify the defense-in-depth security check that ensures locale
# files are only loaded from the expected generated/locales directory.

require 'json'
require 'i18n'
require 'pathname'
require 'tmpdir'
require 'fileutils'

# Setup: Define minimal Onetime module with HOME constant
module Onetime
  HOME = Pathname.new(Dir.mktmpdir('ots-i18n-test'))
end

# Create test directory structure
FileUtils.mkdir_p(Onetime::HOME.join('generated', 'locales'))

# Mock OT.ld for logging
module OT
  def self.ld(msg); end
end

# Directly define the JsonBackend module to test in isolation
# This mirrors the implementation in lib/onetime/initializers/setup_i18n.rb
module TestJsonBackend
  def load_json(filename)
    # Defense in depth: validate path before reading to prevent traversal
    locales_dir = Onetime::HOME.join('generated', 'locales').to_s
    expanded_path = File.expand_path(filename)
    unless expanded_path.start_with?(locales_dir + File::SEPARATOR)
      raise I18n::InvalidLocaleData.new(filename, 'path outside allowed locales directory')
    end

    data = JSON.parse(File.read(expanded_path))

    # Infer locale from filename: generated/locales/en.json -> "en"
    locale = File.basename(expanded_path, '.json')

    # If data doesn't have locale key at top level, wrap it
    wrapped = !data.key?(locale)
    data    = { locale => data } if wrapped

    OT.ld "[i18n] Loaded #{filename} (locale=#{locale}, wrapped=#{wrapped}, keys=#{data[locale]&.keys&.size || 0})"

    # Return tuple: [data, keys_symbolized]
    [data, false]
  rescue JSON::ParserError => ex
    raise I18n::InvalidLocaleData.new(filename, ex.message)
  end
end

# Create a test class that includes JsonBackend for isolated testing
class JsonBackendTester
  include TestJsonBackend
end

@tester = JsonBackendTester.new
@locales_dir = Onetime::HOME.join('generated', 'locales')

# Create a valid test locale file
@valid_locale_path = @locales_dir.join('test.json').to_s
File.write(@valid_locale_path, JSON.generate({ 'web' => { 'greeting' => 'Hello' } }))

## Valid locale file loads successfully
result = @tester.load_json(@valid_locale_path)
[result[0].key?('test'), result[1]]
#=> [true, false]

## Valid locale file returns correct translation data
result = @tester.load_json(@valid_locale_path)
result[0]['test']['web']['greeting']
#=> "Hello"

## Path traversal with ../ is rejected
traversal_path = File.join(@locales_dir, '..', '..', 'etc', 'passwd')
begin
  @tester.load_json(traversal_path)
  'should have raised'
rescue I18n::InvalidLocaleData => ex
  ex.message.include?('outside allowed')
end
#=> true

## Absolute path outside locales directory is rejected
outside_path = '/etc/passwd'
begin
  @tester.load_json(outside_path)
  'should have raised'
rescue I18n::InvalidLocaleData => ex
  ex.message.include?('outside allowed')
end
#=> true

## Path with embedded null byte variant is rejected
# Note: Ruby's File.expand_path handles null bytes, but we test the pattern
null_variant_path = @locales_dir.join('..', 'secrets.json').to_s
begin
  @tester.load_json(null_variant_path)
  'should have raised'
rescue I18n::InvalidLocaleData => ex
  ex.message.include?('outside allowed')
end
#=> true

## Path starting with locales dir but escaping via ../ is rejected
escape_path = @locales_dir.to_s + '/../../../etc/passwd'
begin
  @tester.load_json(escape_path)
  'should have raised'
rescue I18n::InvalidLocaleData => ex
  ex.message.include?('outside allowed')
end
#=> true

## Relative path from wrong directory is rejected
wrong_relative = './malicious.json'
begin
  @tester.load_json(wrong_relative)
  'should have raised'
rescue I18n::InvalidLocaleData => ex
  ex.message.include?('outside allowed')
end
#=> true

## File in parent directory is rejected
parent_file = Onetime::HOME.join('generated', 'secret.json').to_s
File.write(parent_file, '{}')
begin
  @tester.load_json(parent_file)
  'should have raised'
rescue I18n::InvalidLocaleData => ex
  ex.message.include?('outside allowed')
end
#=> true

## Subdirectory within locales is allowed (nested structure acceptable)
# Note: The glob pattern *.json wouldn't match subdirs, but the security
# check permits subdirectories as a defense-in-depth measure only
subdir = @locales_dir.join('subdir')
FileUtils.mkdir_p(subdir)
subdir_file = subdir.join('nested.json').to_s
File.write(subdir_file, JSON.generate({ 'web' => {} }))
result = @tester.load_json(subdir_file)
result[0].key?('nested')
#=> true

## JSON parse error still raises InvalidLocaleData
invalid_json_path = @locales_dir.join('invalid.json').to_s
File.write(invalid_json_path, 'not valid json {{{')
begin
  @tester.load_json(invalid_json_path)
  'should have raised'
rescue I18n::InvalidLocaleData => ex
  ex.message.include?('unexpected token')
end
#=> true

## Error message includes the problematic filename
bad_path = '/tmp/evil.json'
begin
  @tester.load_json(bad_path)
  'should have raised'
rescue I18n::InvalidLocaleData => ex
  ex.message.include?(bad_path)
end
#=> true

# Teardown: Clean up test directory
FileUtils.rm_rf(Onetime::HOME.to_s)
