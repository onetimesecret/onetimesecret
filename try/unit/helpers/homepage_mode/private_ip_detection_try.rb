# try/unit/helpers/homepage_mode/private_ip_detection_try.rb
#
# Tests for private_ip? method
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

  public :private_ip?
end

@controller = TestHomepageController.new({})

## Private IP Detection - IPv4 Private (10.0.0.0/8)
@controller.private_ip?('10.0.1.100')
#=> true

## Private IP Detection - IPv4 Private (172.16.0.0/12)
@controller.private_ip?('172.16.5.1')
#=> true

## Private IP Detection - IPv4 Private (192.168.0.0/16)
@controller.private_ip?('192.168.1.1')
#=> true

## Private IP Detection - IPv4 Loopback
@controller.private_ip?('127.0.0.1')
#=> true

## Private IP Detection - IPv4 Link-Local
@controller.private_ip?('169.254.1.1')
#=> true

## Private IP Detection - IPv4 Public
@controller.private_ip?('203.0.113.1')
#=> false

## Private IP Detection - IPv6 Loopback
@controller.private_ip?('::1')
#=> true

## Private IP Detection - IPv6 Unique Local
@controller.private_ip?('fc00::1')
#=> true

## Private IP Detection - IPv6 Link-Local
@controller.private_ip?('fe80::1')
#=> true

## Private IP Detection - IPv6 Public
@controller.private_ip?('2001:db8::1')
#=> false

## Private IP Detection - Empty String
@controller.private_ip?('')
#=> true

## Private IP Detection - Nil
@controller.private_ip?(nil)
#=> true

## Private IP Detection - Invalid IP
@controller.private_ip?('not_an_ip')
#=> true
