#!/usr/bin/env ruby
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'

## Boot the application to load configuration
OT.boot! :test, false
OT.conf.nil?
#=> false

## Check if site config exists
OT.conf.key?('site')
#=> true

## Load basic configuration and check secret_options exists
OT.conf['site']['secret_options'].class
#=> Hash

## Check if passphrase config exists
OT.conf['site']['secret_options'].key?('passphrase')
#=> true

## Load basic configuration and check passphrase defaults
OT.conf.dig('site', 'secret_options', 'passphrase', 'required')
#=> false

## Load configuration with passphrase config
OT.conf.dig('site', 'secret_options', 'passphrase', 'minimum_length')
#=> 8

## Load configuration with password generation config
OT.conf.dig('site', 'secret_options', 'password_generation', 'default_length')
#=> 12

## Test password generation utility with default options
require 'onetime/utils'
password = Onetime::Utils.strand(12)
password.length
#=> 12

## Test password generation with symbols enabled
password_with_symbols = Onetime::Utils.strand(16, { symbols: true })
password_with_symbols.length
#=> 16

## Test password generation with only lowercase letters
@password_lowercase = Onetime::Utils.strand(8, {
  uppercase: false,
  lowercase: true,
  numbers: false,
  symbols: false
})
@password_lowercase.length
#=> 8

## Verify lowercase-only password contains only lowercase letters
@password_lowercase.match?(/^[a-z]+$/)
#=> true
