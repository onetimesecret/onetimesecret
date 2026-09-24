# spec/unit/onetime/initializers/print_log_banner_spec.rb
#
# frozen_string_literal: true

# The boot banner prints the authdb URLs. Whatever shape a URL takes, no
# part of its password may reach the log: not from the userinfo, not from a
# `?password=` query, and not as the trailing characters of a fallback mask.

require 'spec_helper'
require 'onetime/initializers/print_log_banner'

RSpec.describe Onetime::Initializers::PrintLogBanner do
  let(:instance) { described_class.new }

  describe '#mask_sensitive_value with type: :url' do
    {
      'postgresql://app:s3cret@db:5432/auth' => 'postgresql://app:****@db:5432/auth',
      'postgresql://app:s3cret@h1:5432,h2:5433/auth' => 'postgresql://app:****@h1:5432,h2:5433/auth',
      'postgresql://app:p@ss:s3cret@db/auth' => 'postgresql://app:****@db/auth',
      'postgresql://:s3cret@db/auth' => 'postgresql://:****@db/auth',
      'postgresql://db/auth?password=s3cret' => 'postgresql://db/auth?****',
      'postgresql://app:s3cret@db/auth?sslmode=require' => 'postgresql://app:****@db/auth?****',
      'postgresql://db/auth?password=p@ss' => 'postgresql://****',
      'postgresql://app:pa?ss@db/auth' => 'postgresql://****',
      'postgresql://app@db:5432/auth' => 'postgresql://app@db:5432/auth',
      'sqlite://data/auth.db' => 'sqlite://data/auth.db',
      'app:s3cret@db/auth' => '****',
    }.each do |input, expected|
      it "renders #{input.inspect} as #{expected.inspect}" do
        expect(instance.send(:mask_sensitive_value, input, type: :url)).to eq(expected)
      end
    end
  end
end
