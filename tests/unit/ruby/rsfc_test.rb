# tests/unit/ruby/rsfc_test.rb

require 'tmpdir'
require 'fileutils'

# Mock OT module for testing
module OT
  def self.boot_root
    @boot_root ||= '/tmp'
  end

  def self.conf
    @conf ||= {
      'site' => {
        'host' => 'example.com',
        'ssl' => true,
      },
      'features' => {
        'account_creation' => true,
        'email_delivery' => false,
      },
      'development' => {
        'enabled' => true,
      },
    }
  end

  def self.debug?
    false
  end
end

# Load RSFC modules
require_relative '../../../lib/rsfc/parser'
require_relative '../../../lib/rsfc/context'
require_relative '../../../lib/rsfc/rhales'
require_relative '../../../lib/rsfc/hydrator'
require_relative '../../../lib/refinements/require_refinements'
require_relative '../../../lib/rsfc/view'

# Enable RSFC refinements globally for test
using Onetime::Ruequire

# Simple test framework
class RSFCTest
  attr_reader :failures

  def initialize
    @failures = []
  end

  def run_all_tests
    puts 'Running RSFC Tests...'

    test_parser
    test_context
    test_rhales_variables
    test_rhales_conditionals
    test_rhales_loops
    test_hydrator
    test_integration

    if @failures.empty?
      puts '✅ All tests passed!'
    else
      puts "❌ #{@failures.length} test(s) failed:"
      @failures.each { |failure| puts "  - #{failure}" }
    end

    @failures.empty?
  end

  private

  def assert(condition, message)
    if condition
      puts "✅ #{message}"
    else
      @failures << message
      puts "❌ #{message}"
    end
  end

  def test_parser
    puts "\n--- Testing RSFC Parser ---"

    # Create test .rue file
    rue_content = <<~RUE
      <data window="testData" schema="@/test.ts">
      {
        "user": {
          "id": "{{user.id}}",
          "name": "{{user.name}}"
        },
        "app": {
          "version": "1.0.0"
        }
      }
      </data>

      <template>
        <div>Hello {{user.name}}!</div>
        {{#if user.authenticated}}
          <p>Welcome back!</p>
        {{/if}}
        {{> header}}
      </template>
    RUE

    Dir.mktmpdir do |dir|
      rue_file = File.join(dir, 'test.rue')
      File.write(rue_file, rue_content)

      parser = RSFC::Parser.parse_file(rue_file)

      assert parser.has_section?('data'), 'Parser should find data section'
      assert parser.has_section?('template'), 'Parser should find template section'
      assert parser.window_attribute == 'testData', 'Parser should extract window attribute'
      assert parser.schema_path == '@/test.ts', 'Parser should extract schema path'
      assert parser.partials.include?('header'), 'Parser should find header partial'
      assert parser.data_variables.include?('user.id'), 'Parser should find data variables'
      assert parser.template_variables.include?('user.name'), 'Parser should find template variables'
    end
  end

  def test_context
    puts "\n--- Testing RSFC Context ---"

    business_data = {
      'user' => {
        'id' => '123',
        'name' => 'Test User',
        'authenticated' => true,
      },
    }

    context = RSFC::Context.minimal(business_data: business_data)

    assert context.get('user.id') == '123', 'Context should resolve nested variables'
    assert context.get('user.name') == 'Test User', 'Context should resolve string values'
    assert context.get('user.authenticated') == true, 'Context should resolve boolean values'
    assert context.has_variable?('user.id'), 'Context should detect existing variables'
    assert !context.has_variable?('nonexistent'), 'Context should detect missing variables'
  end

  def test_rhales_variables
    puts "\n--- Testing Rhales Variable Interpolation ---"

    context = MockContext.new({
      'name' => 'World',
      'html' => '<script>alert("xss")</script>',
      'user' => { 'first_name' => 'John' },
    },
                             )

    # Simple variable
    result = RSFC::Rhales.render('Hello {{name}}!', context)
    assert result == 'Hello World!', 'Should interpolate simple variables'

    # HTML escaping
    result = RSFC::Rhales.render('Content: {{html}}', context)
    assert result.include?('&lt;script&gt;'), 'Should escape HTML by default'

    # Raw HTML
    result = RSFC::Rhales.render('Raw: {{{html}}}', context)
    assert result.include?('<script>'), 'Should not escape raw variables'

    # Nested properties
    result = RSFC::Rhales.render('Hi {{user.first_name}}', context)
    assert result == 'Hi John', 'Should resolve nested properties'
  end

  def test_rhales_conditionals
    puts "\n--- Testing Rhales Conditionals ---"

    context = MockContext.new({
      'show_welcome' => true,
      'hide_footer' => false,
      'items' => [1, 2, 3],
    },
                             )

    # If block (truthy)
    result = RSFC::Rhales.render('{{#if show_welcome}}Welcome!{{/if}}', context)
    assert result == 'Welcome!', 'Should render if block when condition is true'

    # If block (falsy)
    result = RSFC::Rhales.render('{{#if hide_footer}}Footer{{/if}}', context)
    assert result == '', 'Should not render if block when condition is false'

    # Unless block
    result = RSFC::Rhales.render('{{#unless hide_footer}}Footer{{/unless}}', context)
    assert result == 'Footer', 'Should render unless block when condition is false'
  end

  def test_rhales_loops
    puts "\n--- Testing Rhales Loops ---"

    context = MockContext.new({
      'items' => %w[apple banana cherry],
      'users' => [
        { 'name' => 'Alice', 'age' => 30 },
        { 'name' => 'Bob', 'age' => 25 },
      ],
    },
                             )

    # Simple each
    result = RSFC::Rhales.render('{{#each items}}{{this}}, {{/each}}', context)
    assert result.include?('apple, banana, cherry'), 'Should iterate over simple array'

    # Object each
    result = RSFC::Rhales.render('{{#each users}}{{name}} ({{age}}), {{/each}}', context)
    assert result.include?('Alice (30)') && result.include?('Bob (25)'), 'Should iterate over object array'
  end

  def test_hydrator
    puts "\n--- Testing Data Hydrator ---"

    rue_content = <<~RUE
      <data window="appData">
      {
        "user_id": "{{user.id}}",
        "features": {
          "enabled": {{features.enabled}}
        }
      }
      </data>

      <template>
        <div>Test</div>
      </template>
    RUE

    Dir.mktmpdir do |dir|
      rue_file = File.join(dir, 'hydrator_test.rue')
      File.write(rue_file, rue_content)

      parser  = RSFC::Parser.parse_file(rue_file)
      context = MockContext.new({
        'user' => { 'id' => '456' },
        'features' => { 'enabled' => true },
      },
                               )

      hydration_html = RSFC::Hydrator.generate(parser, context)

      assert hydration_html.include?('window.appData'), 'Should generate correct window assignment'
      assert hydration_html.include?('application/json'), 'Should use JSON script type'
      assert hydration_html.include?('456'), 'Should interpolate user ID'
      assert hydration_html.include?('true'), 'Should interpolate boolean values'
    end
  end

  def test_integration
    puts "\n--- Testing Full Integration ---"

    # Create a complete .rue file
    rue_content = <<~RUE
      <data window="pageData">
      {
        "user": {
          "id": "{{user.id}}",
          "name": "{{user.name}}"
        },
        "meta": {
          "title": "Welcome {{user.name}}"
        }
      }
      </data>

      <template>
        <!DOCTYPE html>
        <html>
        <head>
          <title>{{meta.title}}</title>
        </head>
        <body>
          <h1>Hello {{user.name}}!</h1>
          {{#if user.authenticated}}
            <p>You are logged in.</p>
          {{/if}}
        </body>
        </html>
      </template>
    RUE

    Dir.mktmpdir do |dir|
      # Set up temporary templates directory
      templates_dir = File.join(dir, 'templates', 'web')
      FileUtils.mkdir_p(templates_dir)

      rue_file = File.join(templates_dir, 'integration_test.rue')
      File.write(rue_file, rue_content)

      # Mock OT.boot_root to point to our temp directory
      original_boot_root = OT.instance_variable_get(:@boot_root)
      OT.instance_variable_set(:@boot_root, dir)

      begin
        business_data = {
          'user' => {
            'id' => '789',
            'name' => 'Integration User',
            'authenticated' => true,
          },
          'meta' => {
            'title' => 'Welcome Integration User',
          },
        }

        view   = RSFC::View.new(nil, nil, nil, 'en', business_data: business_data)
        result = view.render('integration_test')

        assert result.include?('Hello Integration User!'), 'Should render template with user name'
        assert result.include?('You are logged in.'), 'Should render conditional content'
        assert result.include?('window.pageData'), 'Should include hydration script'
        assert result.include?('789'), 'Should include user ID in JSON data'
      ensure
        # Restore original boot_root
        OT.instance_variable_set(:@boot_root, original_boot_root)
      end
    end
  end

  # Mock context for testing
  class MockContext
    def initialize(data)
      @data = data
    end

    def get(path)
      parts   = path.split('.')
      current = @data

      parts.each do |part|
        case current
        when Hash
          current = current[part] || current[part.to_sym]
        else
          return nil
        end
        return nil if current.nil?
      end

      current
    end
  end
end

# Run tests if this file is executed directly
if __FILE__ == $0
  test    = RSFCTest.new
  success = test.run_all_tests
  exit(success ? 0 : 1)
end
