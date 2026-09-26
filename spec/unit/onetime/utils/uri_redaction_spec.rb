# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'onetime/utils/uri_redaction'
require_relative '../../../../apps/web/auth/database_connection'
require 'onetime/initializers/print_log_banner'

RSpec.describe OnetimeUriRedaction do
  {
    'postgresql://app:secret@db/auth' => ['postgresql://***@db/auth', 'postgresql://app:****@db/auth'],
    'postgresql://app:p@ss:secret@db/auth' => ['postgresql://***@db/auth', 'postgresql://app:****@db/auth'],
    'postgresql://app:pa?ss@db/auth' => ['postgresql://***', 'postgresql://****'],
    'postgresql://db/auth?password=p@ss' => ['postgresql://***', 'postgresql://****'],
    'postgresql://app:secret@db/auth?password=other' => ['postgresql://***@db/auth?***', 'postgresql://app:****@db/auth?****'],
    'postgresql://app@db/auth' => ['postgresql://***@db/auth', 'postgresql://app@db/auth'],
    'postgresql://:secret@db/auth' => ['postgresql://***@db/auth', 'postgresql://:****@db/auth'],
    'postgresql://app:secret@h1,h2/auth' => ['postgresql://***@h1,h2/auth', 'postgresql://app:****@h1,h2/auth'],
    'app:secret@db/auth' => ['***@db/auth', '****'],
    '//app:secret@db/auth' => ['//***@db/auth', '****'],
    'unparseable' => ['unparseable', '****'],
    "postgresql://app:sec\nret@db/auth?password=other\nsecret" => ['postgresql://***@db/auth?***', 'postgresql://app:****@db/auth?****'],
    "postgresql://app:sec\xFFret@db/auth".b => ['postgresql://***@db/auth', 'postgresql://app:****@db/auth'],
  }.each do |input, (private_output, banner_output)|
    it "shares delimiter handling across consumers for #{input.inspect}" do
      expect(described_class.redact(input)).to eq(private_output)
      expect(Onetime::Utils.redact_uri_userinfo(input)).to eq(private_output)
      expect(Auth::DatabaseConnection.redact_url(input)).to eq(private_output)
      expect(Onetime::Initializers::PrintLogBanner.new.send(:mask_url, input)).to eq(banner_output)
    end
  end

  it 'does not mutate the input' do
    input = 'postgresql://app:secret@db/auth?password=other'.freeze
    expect { described_class.redact(input) }.not_to raise_error
    expect(input).to include('secret')
  end

  it 'preserves the nil utility contract independently of strict banner policy' do
    expect(described_class.redact(nil)).to eq('')
    expect(described_class.redact(nil, require_scheme: true, mask: '****')).to eq('****')
  end

  it 'loads the auth database helper without booting the application' do
    helper = File.expand_path('../../../../apps/web/auth/database_connection.rb', __dir__)
    script = <<~RUBY
      require ARGV.fetch(0)
      abort 'application namespace loaded' if defined?(Onetime)
      print Auth::DatabaseConnection.redact_url('postgresql://app:secret@db/auth')
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-e', script, helper)
    expect(status.success?).to be(true), stderr
    expect(stdout).to eq('postgresql://***@db/auth')
  end
end
