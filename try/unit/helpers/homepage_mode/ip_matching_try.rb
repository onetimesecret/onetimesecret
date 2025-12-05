# try/unit/helpers/homepage_mode/ip_matching_try.rb
#
# Tests for ip_matches_homepage_cidrs? method
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

  public :compile_homepage_cidrs, :ip_matches_homepage_cidrs?
end

@controller = TestHomepageController.new({})

## IP Matching - IPv4 Match
@controller.instance_variable_set(:@cidr_matchers, @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['10.0.0.0/8']
}))
@controller.ip_matches_homepage_cidrs?('10.0.1.100')
#=> true

## IP Matching - IPv4 No Match
@controller.instance_variable_set(:@cidr_matchers, @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['10.0.0.0/8']
}))
@controller.ip_matches_homepage_cidrs?('192.168.1.1')
#=> false

## IP Matching - Multiple CIDRs
@controller.instance_variable_set(:@cidr_matchers, @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['10.0.0.0/8', '192.168.0.0/16', '172.16.0.0/12']
}))
@controller.ip_matches_homepage_cidrs?('192.168.1.100')
#=> true

## IP Matching - Empty IP
@controller.instance_variable_set(:@cidr_matchers, @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['10.0.0.0/8']
}))
@controller.ip_matches_homepage_cidrs?('')
#=> false

## IP Matching - Empty Matchers
@controller.instance_variable_set(:@cidr_matchers, [])
@controller.ip_matches_homepage_cidrs?('10.0.1.100')
#=> false
