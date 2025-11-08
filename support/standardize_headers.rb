#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to standardize file headers across the codebase
# Only processes files that have ONLY filename comments and/or frozen pragma

require 'fileutils'

class HeaderStandardizer
  RUBY_FROZEN = '# frozen_string_literal: true'

  def initialize(dry_run: false)
    @dry_run = dry_run
    @updated_files = []
    @skipped_files = []
  end

  def process_file(filepath)
    return unless File.file?(filepath)

    content = File.read(filepath)
    lines = content.lines

    # Determine file type
    ext = File.extname(filepath)

    case ext
    when '.rb'
      process_ruby_file(filepath, lines)
    when '.ts', '.js'
      process_typescript_file(filepath, lines)
    when '.vue'
      process_vue_file(filepath, lines)
    else
      skip_file(filepath, "Unsupported file type: #{ext}")
    end
  end

  def summary
    puts "\n" + "="*80
    puts "SUMMARY"
    puts "="*80
    puts "Updated files: #{@updated_files.length}"
    puts "Skipped files: #{@skipped_files.length}"
  end

  private

  def process_ruby_file(filepath, lines)
    # Skip if has shebang
    if lines[0]&.start_with?('#!')
      skip_file(filepath, "Has shebang")
      return
    end

    header_info = analyze_ruby_header(lines)

    # Skip if has other content
    if header_info[:has_other_content]
      skip_file(filepath, "Has other content: #{header_info[:reason]}")
      return
    end

    # Skip if neither filename nor frozen pragma
    unless header_info[:has_filename] || header_info[:has_frozen]
      skip_file(filepath, "No filename or frozen pragma")
      return
    end

    # Build the standardized header
    new_header = build_ruby_header(filepath, header_info)

    # Get the rest of the content (after header)
    rest_content = lines[header_info[:header_end_line]..-1].join

    new_content = new_header + rest_content

    update_file(filepath, new_content)
  end

  def process_typescript_file(filepath, lines)
    header_info = analyze_typescript_header(lines)

    # Skip if has other content
    if header_info[:has_other_content]
      skip_file(filepath, "Has other content: #{header_info[:reason]}")
      return
    end

    # Skip if no filename
    unless header_info[:has_filename]
      skip_file(filepath, "No filename comment")
      return
    end

    # Build the standardized header
    new_header = build_typescript_header(filepath)

    # Get the rest of the content (after header)
    rest_content = lines[header_info[:header_end_line]..-1].join

    new_content = new_header + rest_content

    update_file(filepath, new_content)
  end

  def process_vue_file(filepath, lines)
    header_info = analyze_vue_header(lines)

    # Skip if has other content
    if header_info[:has_other_content]
      skip_file(filepath, "Has other content: #{header_info[:reason]}")
      return
    end

    # Skip if no filename
    unless header_info[:has_filename]
      skip_file(filepath, "No filename comment")
      return
    end

    # Build the standardized header
    new_header = build_vue_header(filepath)

    # Get the rest of the content (after header)
    rest_content = lines[header_info[:header_end_line]..-1].join

    new_content = new_header + rest_content

    update_file(filepath, new_content)
  end

  def analyze_ruby_header(lines)
    info = {
      has_filename: false,
      has_frozen: false,
      has_other_content: false,
      reason: nil,
      header_end_line: 0
    }

    i = 0
    while i < lines.length && i < 20  # Check first 20 lines max
      line = lines[i].strip

      # Empty line or just '#' - continue
      if line.empty? || line == '#'
        i += 1
        next
      end

      # Check for filename comment
      if line =~ /^# [a-zA-Z0-9_\-\/]+\.rb$/
        info[:has_filename] = true
        i += 1
        next
      end

      # Check for frozen pragma
      if line == RUBY_FROZEN
        info[:has_frozen] = true
        i += 1
        next
      end

      # Check for typed pragma (should skip)
      if line =~ /^# typed:/
        info[:has_other_content] = true
        info[:reason] = "Has typed pragma"
        break
      end

      # Any other comment is "other content"
      if line.start_with?('#')
        info[:has_other_content] = true
        info[:reason] = "Has other comments"
        break
      end

      # Reached actual code
      break
    end

    info[:header_end_line] = i
    info
  end

  def analyze_typescript_header(lines)
    info = {
      has_filename: false,
      has_other_content: false,
      reason: nil,
      header_end_line: 0
    }

    i = 0
    while i < lines.length && i < 20
      line = lines[i].strip

      # Empty line - continue
      if line.empty?
        i += 1
        next
      end

      # Check for filename comment
      if line =~ /^\/\/ [a-zA-Z0-9_\-\/]+\.(ts|js)$/
        info[:has_filename] = true
        i += 1
        next
      end

      # Any other comment is "other content"
      if line.start_with?('//')
        info[:has_other_content] = true
        info[:reason] = "Has other comments"
        break
      end

      # Reached actual code
      break
    end

    info[:header_end_line] = i
    info
  end

  def analyze_vue_header(lines)
    info = {
      has_filename: false,
      has_other_content: false,
      reason: nil,
      header_end_line: 0
    }

    i = 0
    while i < lines.length && i < 20
      line = lines[i].strip

      # Empty line - continue
      if line.empty?
        i += 1
        next
      end

      # Check for filename comment
      if line =~ /^&lt;!-- [a-zA-Z0-9_\-\/]+\.vue --&gt;$/
        info[:has_filename] = true
        i += 1
        next
      end

      # Any other comment is "other content"
      if line.start_with?('<!--')
        info[:has_other_content] = true
        info[:reason] = "Has other comments"
        break
      end

      # Reached actual code
      break
    end

    info[:header_end_line] = i
    info
  end

  def build_ruby_header(filepath, info)
    "# #{filepath}\n#\n#{RUBY_FROZEN}\n\n"
  end

  def build_typescript_header(filepath)
    "// #{filepath}\n\n"
  end

  def build_vue_header(filepath)
    "<!-- #{filepath} -->\n\n"
  end

  def update_file(filepath, new_content)
    if @dry_run
      puts "Would update: #{filepath}"
    else
      File.write(filepath, new_content)
      puts "Updated: #{filepath}"
    end
    @updated_files << filepath
  end

  def skip_file(filepath, reason)
    if @dry_run
      puts "Would skip: #{filepath} (#{reason})"
    end
    @skipped_files << filepath
  end
end

# Main execution
if __FILE__ == $0
  dry_run = ARGV.include?('--dry-run')

  standardizer = HeaderStandardizer.new(dry_run: dry_run)

  # Get all Ruby, TypeScript, and Vue files
  files = []
  files += Dir.glob('**/*.rb', File::FNM_DOTMATCH)
  files += Dir.glob('**/*.ts', File::FNM_DOTMATCH)
  files += Dir.glob('**/*.js', File::FNM_DOTMATCH)
  files += Dir.glob('**/*.vue', File::FNM_DOTMATCH)

  # Filter out node_modules, vendor, etc.
  files.reject! { |f| f.include?('node_modules') || f.include?('vendor') }

  puts "Processing #{files.length} files..."
  puts "DRY RUN MODE" if dry_run
  puts

  files.each do |file|
    standardizer.process_file(file)
  end

  standardizer.summary
end
