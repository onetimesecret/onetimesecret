# try/unit/helpers/homepage_mode/cidr_compilation_try.rb
#
# Tests for compile_homepage_cidrs and validate_cidr_privacy methods
# in Onetime::Helpers::HomepageModeHelpers
#
# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'rack/mock'
require_relative '../../../../apps/web/core/controllers/base'

class TestHomepageController
  include Core::Controllers::Base

  attr_accessor :req, :res

  def initialize(env = {})
    @req = Rack::Request.new(env)
    @res = Rack::Response.new
  end

  public :compile_homepage_cidrs, :validate_cidr_privacy
end

@controller = TestHomepageController.new({})

## IPv4 CIDR Compilation - Valid /24
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['192.168.1.0/24']
})
cidrs.length
#=> 1

## IPv4 CIDR Compilation - Valid /8
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['10.0.0.0/8']
})
cidrs.length
#=> 1

## IPv4 CIDR Privacy Validation - /25 is Rejected
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['192.168.1.0/25']
})
cidrs.length
#=> 0

## IPv4 CIDR Privacy Validation - /32 is Rejected
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['192.168.1.1/32']
})
cidrs.length
#=> 0

## IPv6 CIDR Privacy Validation - /48 is Valid
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['2001:db8::/48']
})
cidrs.length
#=> 1

## IPv6 CIDR Privacy Validation - /64 is Rejected
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['2001:db8::/64']
})
cidrs.length
#=> 0

## Invalid CIDR String Handling
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['invalid_cidr', '10.0.0.0/8']
})
cidrs.length
#=> 1

## Empty CIDR List
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => []
})
cidrs.length
#=> 0
