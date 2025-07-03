# lib/onetime/services/system/print_boot_receipt/boot_receipt_generator.rb

class BootReceiptGenerator
  attr_accessor :width

  def initialize(width: 48)
    @width    = width
    @sections = []
  end

  def add_section(section)
    @sections << section
    self
  end

  def generate
    @sections.map(&:render).join("\n")
  end

  def reset
    @sections.clear
    self
  end
end

# Base section class for boot receipt sections
class BootReceiptSection
  attr_reader :generator

  def initialize(generator)
    @generator = generator
  end

  def render
    raise NotImplementedError, 'Subclasses must implement #render'
  end

  protected

  def width
    @generator.width
  end

  def center_text(text)
    padding = (width - text.length) / 2
    (' ' * padding) + text
  end

  def left_align(text)
    text.ljust(width)
  end

  def right_align(text)
    text.rjust(width)
  end

  def divider(char = '=')
    char * width
  end

  def two_column(left, right)
    available = width - right.length
    left.ljust(available) + right
  end

  def three_column(left, center, right)
    side_space = ((width - center.length) / 2) - 1
    left_part  = left[0, side_space].ljust(side_space)
    right_part = right[0, side_space].rjust(side_space)
    left_part + ' ' + center + ' ' + right_part
  end
end

# Generic text section for arbitrary content
class TextSection < BootReceiptSection
  def initialize(generator, content: '', alignment: :left)
    super(generator)
    @content   = content
    @alignment = alignment
  end

  def render
    case @alignment
    when :center
      center_text(@content)
    when :right
      right_align(@content)
    else
      left_align(@content)
    end
  end
end

# Footer section for messages and links
class FooterSection < BootReceiptSection
  def initialize(generator, messages: [], website: nil)
    super(generator)
    @messages = messages
    @website  = website
  end

  def add_message(message)
    @messages << message
    self
  end

  def render
    lines = @messages.map { |msg| center_text(msg) }
    lines << center_text(@website) if @website
    lines << divider
    lines.join("\n")
  end
end
