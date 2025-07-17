# lib/onetime/services/system/print_boot_receipt/boot_receipt_sections.rb

require_relative 'boot_receipt_generator'

# System header section for application information
class SystemHeaderSection < BootReceiptSection
  def initialize(generator, app_name:, version:, subtitle: nil, environment: nil)
    super(generator)
    @app_name    = app_name
    @version     = version
    @subtitle    = subtitle
    @environment = environment
  end

  def render
    lines = []
    lines << ''
    lines << divider
    lines << center_text("#{@app_name}")
    lines << center_text("#{@version}")
    lines << center_text(@subtitle) if @subtitle
    lines << divider

    # Add timestamp and basic system info
    date_part = Time.now.strftime('%Y-%m-%d')
    time_part = Time.now.strftime('%H:%M:%S %Z')
    timestamp = format('%-s%sTime: %s', date_part, ' ' * (width - "Date: #{date_part}Time: #{time_part}".length), time_part)
    lines << "Date: #{timestamp}"

    # Format: System: ruby 3.4.4        Arch: arm64-darwin24
    platform_info = format('System: %s %s%sArch: %s', RUBY_ENGINE, RUBY_VERSION, ' ' * (width - "System: #{RUBY_ENGINE} #{RUBY_VERSION}Arch: #{RUBY_PLATFORM}".length), RUBY_PLATFORM)
    lines << platform_info

    environment_info = format('Environment: %s', @environment)
    lines << environment_info

    lines.join("\n")
  end
end

# System status section with component information
class SystemStatusSection < BootReceiptSection
  def initialize(generator, title:, subtitle: nil, rows: [])
    super(generator)
    @title    = title
    @subtitle = subtitle
    @rows     = rows
  end

  def add_row(key, value, status: nil)
    @rows << { key: key, value: value, status: status }
    self
  end

  def render
    return '' if @rows.empty?

    lines = []
    lines << divider('-')
    lines << format_title_line(@title)
    lines << center_text(@subtitle) if @subtitle
    lines << divider('-')

    @rows.each do |row|
      formatted_line = format_status_line(row[:key], row[:value], row[:status])
      lines << formatted_line
    end

    lines.join("\n")
  end

  def format_title_line(title_array)
    return '' if title_array.empty?

    if title_array.length == 2
      left_text  = title_array[0].to_s
      right_text = title_array[1].to_s
      padding    = width - left_text.length - right_text.length
      padding    = [padding, 0].max
      "#{left_text}#{' ' * padding}#{right_text}"
    elsif title_array.length == 3
      left_text   = title_array[0].to_s
      center_text = title_array[1].to_s
      right_text  = title_array[2].to_s

      # Calculate spacing
      total_text_length = left_text.length + center_text.length + right_text.length
      remaining_space   = width - total_text_length

      if remaining_space >= 2
        left_padding  = remaining_space / 2
        right_padding = remaining_space - left_padding
        "#{left_text}#{' ' * left_padding}#{center_text}#{' ' * right_padding}#{right_text}"
      else
        # If not enough space, just concatenate with minimal spacing
        "#{left_text} #{center_text} #{right_text}"[0, width]
      end
    else
      # Fallback for single item or more than 3 items
      center_text(title_array[0].to_s)
    end
  end

  private

  def format_status_line(key, value, status)
    status_width = status ? 8 : 0  # [STATUS] = 8 chars
    value_width  = 20
    key_width    = width - value_width - status_width - 2  # 2 for spaces

    key_part    = key.to_s.ljust(key_width)
    value_part  = format_value(value).ljust(value_width)
    status_part = status ? "[#{status}]".rjust(status_width) : ''

    "#{key_part} #{value_part}#{status_part}".rstrip
  end

  def format_value(value)
    case value
    when Array
      if value.length > 3
        "#{value[0..2].join(', ')}... (#{value.length} total)"
      else
        value.join(', ')
      end
    when Hash
      value.map { |k, v| "#{k}=#{v}" }.join(', ')
    when true
      'enabled'
    when false
      'disabled'
    else
      value.to_s
    end
  end
end

# Status summary section for overall system status
class StatusSummarySection < BootReceiptSection
  def initialize(generator, status: 'READY', message: 'All components verified')
    super(generator)
    @status  = status
    @message = message
  end

  def render
    lines = []
    lines << divider('-')
    lines << center_text("SYSTEM STATUS: #{@status}")
    lines << center_text(@message)
    lines << ''
    lines << divider
    lines.join("\n")
  end
end

# Text wrapping section for long content
class WrapTextSection < BootReceiptSection
  def initialize(generator, title:, content:, line_prefix: '')
    super(generator)
    @title       = title
    @content     = content
    @line_prefix = line_prefix
  end

  def render
    lines = []
    lines << divider('-')

    # Calculate available width for content after title
    title_width   = @title.length
    content_width = width - title_width

    # Wrap the content to fit within the available width
    wrapped_content = wrap_text(@content, content_width)

    # Add title to first line, then continue with wrapped lines
    wrapped_content.each_with_index do |line, index|
      lines << if index.zero?
        "#{@title}#{line}"
      else
        "#{' ' * title_width}#{line}"
               end
    end

    lines.join("\n")
  end

  private

  def wrap_text(text, max_width)
    return [text] if text.length <= max_width

    words         = text.split(' ')
    wrapped_lines = []
    current_line  = ''

    words.each do |word|
      if current_line.empty?
        current_line = word
      elsif (current_line + ' ' + word).length <= max_width
        current_line += ' ' + word
      else
        wrapped_lines << current_line
        current_line = word
      end
    end

    wrapped_lines << current_line unless current_line.empty?
    wrapped_lines
  end
end

# Key-value section for configuration data
class KeyValueSection < BootReceiptSection
  def initialize(generator, header1:, header2:, rows: [])
    super(generator)
    @header1 = header1
    @header2 = header2
    @rows    = rows
  end

  def add_row(key, value)
    @rows << [key, value]
    self
  end

  def render
    return '' if @rows.empty?

    lines = []
    lines << divider
    lines << two_column(@header1, @header2)
    lines << divider('-')

    @rows.each do |row|
      lines << two_column(row[0].to_s, row[1].to_s)
    end

    lines.join("\n")
  end
end
