#!/usr/bin/env ruby
# generate_familia2_patch.rb
# Script to generate a patch file for remaining Familia 2 changes
# Based on the patterns from familia2.txt

require 'find'
require 'fileutils'
require 'set'

class Familia2Patcher
  def initialize
    @changes = []
    @patterns = load_patterns
    @processed_files = Set.new
  end

  def run
    puts "🔍 Scanning codebase for Familia 2 changes..."

    # Scan all relevant directories
    scan_directories = [
      'apps',
      'lib',
      'migrate',
      'spec',
      'src',
      'examples',
      'etc',
      'docs'
    ]

    scan_directories.each do |dir|
      next unless File.exist?(dir)
      scan_directory(dir)
    end

    # Handle package.json separately
    scan_file('package.json') if File.exist?('package.json')

    puts "📝 Found #{@changes.size} changes needed"
    generate_patch_file
  end

  private

  def load_patterns
    [
      # Core Familia 2 patterns - order matters!
      {
        from: /^(\s*)identifier\s+([:\w]+)(\s*)$/,
        to: '\1identifier_field \2\3',
        description: 'Replace identifier with identifier_field'
      },
      {
        from: /^(\s*)ttl\s+(\d+\.\w+)(\s*)$/,
        to: '\1default_expiration \2\3',
        description: 'Replace ttl with default_expiration'
      },
      {
        from: /ttl:\s*(\d+\.\w+)/,
        to: 'default_expiration: \1',
        description: 'Replace ttl: with default_expiration:'
      },
      {
        from: /\.realttl\b/,
        to: '.current_expiration',
        description: 'Replace .realttl with .current_expiration'
      },
      {
        from: /\.redis\b/,
        to: '.dbclient',
        description: 'Replace .redis with .dbclient'
      },
      {
        from: /\.rediskey\b/,
        to: '.dbkey',
        description: 'Replace .rediskey with .dbkey'
      },
      {
        from: /Familia\.redis/,
        to: 'Familia.dbclient',
        description: 'Replace Familia.redis with Familia.dbclient'
      },
      {
        from: /redis_types/,
        to: 'data_types',
        description: 'Replace redis_types with data_types'
      },
      {
        from: /to_redis/,
        to: 'serialize_value',
        description: 'Replace to_redis with serialize_value'
      },
      {
        from: /from_rediskey/,
        to: 'from_dbkey',
        description: 'Replace from_rediskey with from_dbkey'
      },
      # Environment variable changes
      {
        from: /REDIS_URL/,
        to: 'VALKEY_URL',
        description: 'Replace REDIS_URL with VALKEY_URL'
      },
      {
        from: /REDIS_SERVER/,
        to: 'VALKEY_SERVER',
        description: 'Replace REDIS_SERVER with VALKEY_SERVER'
      },
      {
        from: /REDIS_CLI/,
        to: 'VALKEY_CLI',
        description: 'Replace REDIS_CLI with VALKEY_CLI'
      },
      # Comments and documentation - case insensitive
      {
        from: /redis server/i,
        to: 'database server',
        description: 'Replace redis server references'
      },
      {
        from: /redis hash/i,
        to: 'database hash',
        description: 'Replace redis hash references'
      },
      {
        from: /redis key/i,
        to: 'database key',
        description: 'Replace redis key references'
      },
      {
        from: /stored in redis/i,
        to: 'stored in the database',
        description: 'Replace "stored in redis"'
      },
      {
        from: /from redis/i,
        to: 'from the database',
        description: 'Replace "from redis"'
      },
      {
        from: /to redis/i,
        to: 'to the database',
        description: 'Replace "to redis"'
      },
      # Script name changes
      {
        from: /clean_redis\.rb/,
        to: 'clean_database.rb',
        description: 'Update script name references'
      },
      {
        from: /"redis:(\w+)"/,
        to: '"database:\1"',
        description: 'Update npm script names'
      },
      # Parameter changes
      {
        from: /\bdb:\s*(\d+)/,
        to: 'logical_database: \1',
        description: 'Replace db: with logical_database:'
      }
    ]
  end

  def scan_directory(path)
    Find.find(path) do |file|
      next if File.directory?(file)
      next unless should_process_file?(file)

      scan_file(file)
    end
  end

  def should_process_file?(file)
    # Skip certain directories and file types
    return false if file.include?('/.git/')
    return false if file.include?('/node_modules/')
    return false if file.include?('/vendor/')
    return false if file.end_with?('.log')
    return false if file.end_with?('.tmp')
    return false if file.end_with?('.min.js')

    # Include relevant file types
    extensions = %w[.rb .js .vue .json .md .yml .yaml .sh]
    extensions.any? { |ext| file.end_with?(ext) } || File.basename(file) == 'package.json'
  end

  def scan_file(file)
    return if @processed_files.include?(file)
    @processed_files.add(file)

    begin
      lines = File.readlines(file, chomp: true)

      lines.each_with_index do |line, index|
        line_number = index + 1
        original_line = line.dup
        modified_line = line

        @patterns.each do |pattern|
          if modified_line.match?(pattern[:from])
            modified_line = modified_line.gsub(pattern[:from], pattern[:to])
          end
        end

        if modified_line != original_line
          # Handle special case for identifier_field :key -> add field :key
          if original_line.match?(/^\s*identifier\s+:key\s*$/) &&
             modified_line.match?(/^\s*identifier_field\s+:key\s*$/)
            # Check if next line is not already 'field :key'
            next_line_index = index + 1
            if next_line_index < lines.length
              next_line = lines[next_line_index].strip
              unless next_line == 'field :key'
                # Add both the identifier_field change and field addition
                @changes << {
                  file: file,
                  line_start: line_number,
                  line_end: line_number,
                  original_lines: [original_line],
                  new_lines: [modified_line, "    field :key"],
                  description: 'Replace identifier :key with identifier_field :key and add field :key'
                }
                next
              end
            end
          end

          @changes << {
            file: file,
            line_start: line_number,
            line_end: line_number,
            original_lines: [original_line],
            new_lines: [modified_line],
            description: get_change_description(original_line, modified_line)
          }
        end
      end
    rescue => e
      puts "⚠️  Warning: Could not read #{file}: #{e.message}"
    end
  end

  def get_change_description(original, new)
    @patterns.each do |pattern|
      if original.match?(pattern[:from])
        return pattern[:description]
      end
    end
    "Unknown change"
  end

  def generate_patch_file
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    patch_file = "familia2_remaining_changes_#{timestamp}.patch"

    File.open(patch_file, 'w') do |f|
      f.puts "# Familia 2 Migration - Remaining Changes"
      f.puts "# Generated on #{Time.now}"
      f.puts "# Total changes: #{@changes.size}"
      f.puts ""

      # Group changes by file
      changes_by_file = @changes.group_by { |change| change[:file] }

      changes_by_file.each do |file, file_changes|
        relative_file = file.sub(/^#{Regexp.escape(Dir.pwd)}\//, '')
        f.puts "--- a/#{relative_file}"
        f.puts "+++ b/#{relative_file}"

        file_changes.each do |change|
          original_count = change[:original_lines].length
          new_count = change[:new_lines].length

          f.puts "@@ -#{change[:line_start]},#{original_count} +#{change[:line_start]},#{new_count} @@"

          change[:original_lines].each do |line|
            f.puts "-#{line}"
          end

          change[:new_lines].each do |line|
            f.puts "+#{line}"
          end
        end
        f.puts ""
      end
    end

    puts "✅ Generated patch file: #{patch_file}"
    puts ""
    puts "📊 Summary by change type:"

    # Summary by description
    summary = @changes.group_by { |c| c[:description] }
    summary.each do |desc, changes|
      puts "   #{desc}: #{changes.size} changes"
    end

    puts ""
    puts "🔧 To apply the patch:"
    puts "   patch -p1 < #{patch_file}"
    puts ""
    puts "🧪 To apply selectively, edit the patch file first"

    # Show some specific examples
    puts ""
    puts "📋 Examples of changes found:"
    @changes.first(5).each do |change|
      puts "   #{File.basename(change[:file])}:#{change[:line_start]} - #{change[:description]}"
    end
  end
end

if __FILE__ == $0
  patcher = Familia2Patcher.new
  patcher.run
end
