# try/unit/helpers/homepage_mode/cidr_compilation_try.rb
#
# frozen_string_literal: true

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

## IPv4 CIDR Compilation - /25 is Kept (judged via otto.ip_match)
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['192.168.1.0/25']
})
cidrs.length
#=> 1

## IPv4 CIDR Compilation - /32 is Kept (judged via otto.ip_match)
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['192.168.1.1/32']
})
cidrs.length
#=> 1

## IPv6 CIDR Compilation - /48 is Valid
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['2001:db8::/48']
})
cidrs.length
#=> 1

## IPv6 CIDR Compilation - /64 is Kept (judged via otto.ip_match)
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['2001:db8::/64']
})
cidrs.length
#=> 1

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
