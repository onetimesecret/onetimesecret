# receipt_generator.rb
class ReceiptGenerator
  attr_accessor :width, :currency, :date_format

  def initialize(width: 48, currency: '$', date_format: '%Y-%m-%d %H:%M:%S')
    @width       = width
    @currency    = currency
    @date_format = date_format
    @sections    = []
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

# Base section class
class ReceiptSection
  attr_reader :generator

  def initialize(generator)
    @generator = generator
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

# Header section for store info, logos, etc.
class HeaderSection < ReceiptSection
  def initialize(generator, store_name: nil, address: [], phone: nil, logo: nil)
    super(generator)
    @store_name = store_name
    @address    = address
    @phone      = phone
    @logo       = logo
  end

  def render
    lines = []
    lines << divider
    lines << center_text(@logo) if @logo
    lines << center_text(@store_name) if @store_name
    @address.each { |line| lines << center_text(line) }
    lines << center_text(@phone) if @phone
    lines << divider
    lines.join("\n")
  end
end

# Transaction info section
class TransactionSection < ReceiptSection
  def initialize(generator, cashier: nil, register: nil, transaction_id: nil)
    super(generator)
    @cashier        = cashier
    @register       = register
    @transaction_id = transaction_id
    @timestamp      = Time.now
  end

  def render
    lines    = []
    date_str = @timestamp.strftime(@generator.date_format.split.first || '%Y-%m-%d')
    time_str = @timestamp.strftime(@generator.date_format.split.last || '%H:%M:%S')

    lines << two_column("Date: #{date_str}", "Time: #{time_str}")
    lines << two_column("Cashier: #{@cashier}", "Register: #{@register}") if @cashier || @register
    lines << "Transaction: #{@transaction_id}" if @transaction_id
    lines << divider

    lines.join("\n")
  end
end

# Items section with flexible formatting
class ItemsSection < ReceiptSection
  def initialize(generator)
    super
    @items   = []
    @headers = nil
  end

  def set_headers(item_header: 'ITEM', qty_header: 'QTY', price_header: 'PRICE', total_header: 'TOTAL')
    @headers = {
      item: item_header,
      qty: qty_header,
      price: price_header,
      total: total_header,
    }
    self
  end

  def add_item(name:, quantity: 1, price: 0.0, total: nil)
    total ||= quantity * price
    @items << {
      name: name,
      quantity: quantity,
      price: price,
      total: total,
    }
    self
  end

  def render
    return '' if @items.empty?

    lines = []

    if @headers
      lines << format_item_line(@headers[:item], @headers[:qty], @headers[:price], @headers[:total])
      lines << divider('-')
    end

    @items.each do |item|
      qty_str   = item[:quantity].to_s
      price_str = format_currency(item[:price])
      total_str = format_currency(item[:total])
      lines << format_item_line(item[:name], qty_str, price_str, total_str)
    end

    lines.join("\n")
  end

  private

  def format_item_line(name, qty, price, total)
    # Calculate column widths dynamically
    qty_width   = 3
    price_width = 6
    total_width = 7
    name_width  = width - qty_width - price_width - total_width - 3 # spaces

    name_part  = name[0, name_width].ljust(name_width)
    qty_part   = qty.to_s.center(qty_width)
    price_part = price.to_s.rjust(price_width)
    total_part = total.to_s.rjust(total_width)

    "#{name_part} #{qty_part} #{price_part} #{total_part}"
  end

  def format_currency(amount)
    "#{@generator.currency}#{format('%.2f', amount)}"
  end
end

# Totals section for subtotal, tax, discounts, final total
class TotalsSection < ReceiptSection
  def initialize(generator)
    super
    @totals = []
  end

  def add_total(label:, amount:, highlight: false)
    @totals << {
      label: label,
      amount: amount,
      highlight: highlight,
    }
    self
  end

  def add_subtotal(amount)
    add_total(label: 'SUBTOTAL:', amount: amount)
  end

  def add_tax(amount, label: 'TAX:')
    add_total(label: label, amount: amount)
  end

  def add_discount(amount, label: 'DISCOUNT:')
    add_total(label: label, amount: -amount)
  end

  def add_final_total(amount)
    add_total(label: 'TOTAL:', amount: amount, highlight: true)
  end

  def render
    return '' if @totals.empty?

    lines = []
    lines << divider('-')

    @totals.each do |total|
      amount_str = format_currency(total[:amount])
      line       = two_column('', "#{total[:label]} #{amount_str}")
      line       = line.upcase if total[:highlight]
      lines << line
    end

    lines.join("\n")
  end

  private

  def format_currency(amount)
    prefix = amount < 0 ? '-' : ''
    "#{prefix}#{@generator.currency}#{format('%.2f', amount.abs)}"
  end
end

# Payment section
class PaymentSection < ReceiptSection
  def initialize(generator)
    super
    @payments = []
  end

  def add_payment(method:, amount:)
    @payments << { method: method, amount: amount }
    self
  end

  def add_cash(tendered:, change: 0)
    add_payment(method: 'CASH:', amount: tendered)
    add_payment(method: 'CHANGE:', amount: change) if change > 0
    self
  end

  def add_card(amount:, type: 'CARD')
    add_payment(method: "#{type}:", amount: amount)
    self
  end

  def render
    return '' if @payments.empty?

    lines = []
    @payments.each do |payment|
      amount_str = format_currency(payment[:amount])
      lines << two_column('', "#{payment[:method]} #{amount_str}")
    end
    lines.join("\n")
  end

  private

  def format_currency(amount)
    "#{@generator.currency}#{format('%.2f', amount)}"
  end
end

# Footer section for thank you messages, promotions, etc.
class FooterSection < ReceiptSection
  def initialize(generator, messages: [], website: nil, return_policy: nil)
    super(generator)
    @messages      = messages
    @website       = website
    @return_policy = return_policy
  end

  def add_message(message)
    @messages << message
    self
  end

  def render
    lines = []
    lines << divider

    @messages.each { |msg| lines << center_text(msg) }
    lines << center_text(@website) if @website
    lines << '' if @return_policy
    lines << center_text(@return_policy) if @return_policy

    lines << divider
    lines.join("\n")
  end
end

# Custom text section for arbitrary content
class TextSection < ReceiptSection
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

# Convenience builder class
class ReceiptBuilder
  def self.build(width: 48, currency: '$', &)
    generator = ReceiptGenerator.new(width: width, currency: currency)
    builder   = new(generator)
    builder.instance_eval(&) if block_given?
    generator.generate
  end

  def initialize(generator)
    @generator = generator
  end

  def header(store_name: nil, address: [], phone: nil, logo: nil)
    @generator.add_section(HeaderSection.new(@generator,
      store_name: store_name, address: address, phone: phone, logo: logo,
    ),
                          )
  end

  def transaction(cashier: nil, register: nil, transaction_id: nil)
    @generator.add_section(TransactionSection.new(@generator,
      cashier: cashier, register: register, transaction_id: transaction_id,
    ),
                          )
  end

  def items(&)
    section = ItemsSection.new(@generator)
    section.instance_eval(&) if block_given?
    @generator.add_section(section)
  end

  def totals(&)
    section = TotalsSection.new(@generator)
    section.instance_eval(&) if block_given?
    @generator.add_section(section)
  end

  def payment(&)
    section = PaymentSection.new(@generator)
    section.instance_eval(&) if block_given?
    @generator.add_section(section)
  end

  def footer(messages: [], website: nil, return_policy: nil)
    @generator.add_section(FooterSection.new(@generator,
      messages: messages, website: website, return_policy: return_policy,
    ),
                          )
  end

  def text(content, alignment: :left)
    @generator.add_section(TextSection.new(@generator, content: content, alignment: alignment))
  end

  def divider(char = '=')
    text(char * @generator.width, :left)
  end
end

# Example usage:
if __FILE__ == $0
  receipt = ReceiptBuilder.build(width: 48) do
    header(
      store_name: 'COFFEE CENTRAL',
      address: ['123 Main Street', 'Anytown, ST 12345'],
      phone: 'Phone: (555) 123-4567',
    )

    transaction(
      cashier: 'Alice',
      register: '#001',
    )

    items do
      set_headers(item_header: 'ITEM', qty_header: 'QTY', price_header: 'PRICE', total_header: 'TOTAL')
      add_item(name: 'Coffee (Large)', quantity: 2, price: 3.50)
      add_item(name: 'Muffin (Blueberry)', quantity: 1, price: 2.25)
      add_item(name: 'Croissant', quantity: 1, price: 1.95)
    end

    totals do
      add_subtotal(9.20)
      add_tax(0.74)
      add_final_total(9.94)
    end

    payment do
      add_cash(tendered: 10.00, change: 0.06)
    end

    footer(
      messages: ['Thank you for your visit!', 'Have a great day!'],
      website: 'www.coffeecentral.com',
    )
  end

  puts receipt
end
