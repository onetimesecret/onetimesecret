# tests/unit/ruby/rspec/onetime/environment_security_spec.rb

require_relative '../spec_helper'

RSpec.describe "Onetime::Environment ERB Security" do
  let(:safe_binding) { Onetime::Environment.template_binding }
  let(:unsafe_binding) { binding }

  describe "safe template binding" do
    it "provides access to ENV variables" do
      template = '<%= ENV["PATH"] %>'
      result = ERB.new(template).result(safe_binding)
      expect(result).to eq(ENV["PATH"])
    end

    it "provides access to custom helper methods" do
      template = '<%= env("HOME", "/default") %>'
      result = ERB.new(template).result(safe_binding)
      expect(result).to be_a(String)
    end

    it "blocks access to dangerous system methods" do
      dangerous_methods = {
        'system("echo dangerous")' => /system.*not allowed/,
        '`echo dangerous`' => /backticks.*not allowed/,
        'exec("echo dangerous")' => /exec.*not allowed/,
        'eval("1+1")' => /eval.*not allowed/,
        'send(:env, "HOME")' => /send.*not allowed/,
        'Object.const_get(:File)' => /undefined.*constant.*Object/
      }

      dangerous_methods.each do |method_call, expected_error|
        template = "<%= #{method_call} %>"
        expect {
          result = ERB.new(template).result(safe_binding)
          puts "SECURITY BREACH: #{method_call} returned: #{result.inspect}"
          fail "Expected #{method_call} to raise an error but got: #{result.inspect}"
        }.to raise_error(expected_error), "Expected #{method_call} to be blocked"
      end
    end

    it "blocks access to instance variables from configurator" do
      template = '<%= @config_path %>'
      expect {
        ERB.new(template).result(safe_binding)
      }.to raise_error(NameError, /undefined.*variable/)
    end

    it "blocks access to local variables from calling context" do
      secret_data = "sensitive_information"
      template = '<%= secret_data %>'

      expect {
        ERB.new(template).result(safe_binding)
      }.to raise_error(NameError, /undefined.*variable/)
    end

    it "provides only expected methods" do
      allowed_methods = %w[env] # Add your helper methods here
      dangerous_methods = %w[system exec eval send const_get]

      # Check allowed methods are available
      allowed_methods.each do |method|
        template = "<%= respond_to?(:#{method}) %>"
        result = ERB.new(template).result(safe_binding)
        expect(result).to eq("true")
      end

      # Check dangerous methods are not available
      dangerous_methods.each do |method|
        template = "<%= respond_to?(:#{method}) %>"
        result = ERB.new(template).result(safe_binding)
        expect(result).to eq("false")
      end
    end
  end

  describe "comparison with unsafe binding" do
    it "demonstrates unsafe binding exposes dangerous methods" do
      template = '<%= respond_to?(:system) %>'

      safe_result = ERB.new(template).result(safe_binding)
      unsafe_result = ERB.new(template).result(unsafe_binding)

      expect(safe_result).to eq("false")
      expect(unsafe_result).to eq("true")
    end

    it "shows method count difference" do
      safe_methods = eval("methods.size", safe_binding)
      unsafe_methods = eval("methods.size", unsafe_binding)

      expect(safe_methods).to be < unsafe_methods
    end
  end

  describe "environment isolation" do
    it "cannot access configurator state" do
      configurator = OT::Configurator.new
      configurator.instance_variable_set(:@secret_data, "sensitive")

      template = '<%= @secret_data %>'
      result = ERB.new(template).result(safe_binding)

      expect(result).to be_empty
    end
  end
end
