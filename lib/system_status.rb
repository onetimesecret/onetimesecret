class SystemStatusSection < ReceiptSection
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
    lines << divider
    lines << center_text(@title)
    lines << center_text(@subtitle) if @subtitle
    lines << divider('-')

    @rows.each do |row|
      formatted_line = format_status_line(row[:key], row[:value], row[:status])
      lines << formatted_line
    end

    lines.join("\n")
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

class SystemHeaderSection < ReceiptSection
  def initialize(generator, app_name:, version:, subtitle: nil)
    super(generator)
    @app_name = app_name
    @version  = version
    @subtitle = subtitle
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
    timestamp = Time.now.strftime('%Y-%m-%d          Time: %H:%M:%S %Z')
    lines << "Date: #{timestamp}"

    lines.join("\n")
  end
end

class StatusSummarySection < ReceiptSection
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

class WrapTextSection < ReceiptSection
  def initialize(generator, title:, content:, line_prefix: '')
    super(generator)
    @title       = title
    @content     = content
    @line_prefix = line_prefix
  end

  def render
    lines = []
    lines << divider('-')
    lines << "#{@title}#{@content}"
    lines.join("\n")
  end
end
