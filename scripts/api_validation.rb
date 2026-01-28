#!/usr/bin/env ruby
# frozen_string_literal: true

require 'httparty'
require 'json'
require 'optparse'

# A script to validate the Onetime Secret API before and after a data migration.
#
# This script has two stages:
#
# 1. `create`: Creates data (secrets, passwords) via the API and saves the
#    details to a JSON file.
# 2. `validate`: Reads the JSON file and verifies that the data can be
#    accessed, burned, etc., as expected.
#
# Usage:
#
#   bundle exec scripts/api_validation.rb create
#   bundle exec scripts/api_validation.rb validate
#
class ApiValidation
  DEFAULT_HOST = 'https://dev.onetime.dev'
  VALIDATION_FILE = 'migration_validation.json'

  def initialize(host)
    @host = host
    @api_base_url = "#{host}/api/v1"
  end

  def run(mode)
    case mode
    when 'create'
      create_data
    when 'validate'
      validate_data
    else
      puts "Invalid mode: #{mode}. Must be 'create' or 'validate'."
      exit 1
    end
  end

  private

  def create_data
    puts 'Running in CREATE mode...'
    validation_data = {}

    # 1. Generate a password
    puts 'Generating a password...'
    response = HTTParty.post("#{@api_base_url}/generate", body: { ttl: 3600 })
    raise "Password generation failed: #{response.body}" unless response.code == 200
    generated_password = response.parsed_response['value']
    validation_data['generated_password'] = generated_password
    puts "  Generated password: #{generated_password}"

    # 2. Create a simple secret
    puts 'Creating a simple secret...'
    secret_message = "This is a simple secret created at #{Time.now.utc}"
    response = HTTParty.post("#{@api_base_url}/share", body: { secret: secret_message, ttl: 3600 })
    raise "Simple secret creation failed: #{response.body}" unless response.code == 200
    simple_secret_key = response.parsed_response['secret_key']
    validation_data['simple_secret'] = {
      'message' => secret_message,
      'secret_key' => simple_secret_key,
      'metadata_key' => response.parsed_response['metadata_key']
    }
    puts "  Simple secret created with key: #{simple_secret_key}"

    # 3. Create a secret with a password
    puts 'Creating a secret with a password...'
    secret_with_pass_message = "This is a secret with a password created at #{Time.now.utc}"
    response = HTTParty.post("#{@api_base_url}/share", body: { secret: secret_with_pass_message, passphrase: generated_password, ttl: 3600 })
    raise "Secret with password creation failed: #{response.body}" unless response.code == 200
    secret_with_pass_key = response.parsed_response['secret_key']
    validation_data['secret_with_password'] = {
      'message' => secret_with_pass_message,
      'secret_key' => secret_with_pass_key,
      'metadata_key' => response.parsed_response['metadata_key']
    }
    puts "  Secret with password created with key: #{secret_with_pass_key}"

    # 4. Save the results
    File.write(VALIDATION_FILE, JSON.pretty_generate(validation_data))
    puts "Validation data written to #{VALIDATION_FILE}"

    puts 'CREATE mode finished.'
  end

  def validate_data
    puts 'Running in VALIDATE mode...'
    unless File.exist?(VALIDATION_FILE)
      puts "Validation file not found: #{VALIDATION_FILE}. Run 'create' mode first."
      exit 1
    end
    validation_data = JSON.parse(File.read(VALIDATION_FILE))

    # 1. Validate the simple secret
    puts 'Validating simple secret...'
    simple_secret_data = validation_data['simple_secret']
    response = HTTParty.post("#{@api_base_url}/secret/#{simple_secret_data['secret_key']}")
    raise "Failed to retrieve simple secret: #{response.body}" unless response.code == 200
    retrieved_secret = response.parsed_response['value']
    raise "Simple secret content mismatch" unless retrieved_secret == simple_secret_data['message']
    puts '  Successfully retrieved simple secret and content matches.'

    # Verify it's burned
    response = HTTParty.post("#{@api_base_url}/secret/#{simple_secret_data['secret_key']}")
    raise "Simple secret should have been burned, but was retrieved again" unless response.code == 404
    puts '  Successfully verified that the simple secret was burned after reading.'

    # 2. Validate the secret with a password
    puts 'Validating secret with password...'
    secret_with_pass_data = validation_data['secret_with_password']
    generated_password = validation_data['generated_password']
    response = HTTParty.post("#{@api_base_url}/secret/#{secret_with_pass_data['secret_key']}", body: { passphrase: generated_password })
    raise "Failed to retrieve secret with password: #{response.body}" unless response.code == 200
    retrieved_secret_with_pass = response.parsed_response['value']
    raise "Secret with password content mismatch" unless retrieved_secret_with_pass == secret_with_pass_data['message']
    puts '  Successfully retrieved secret with password and content matches.'

    # Verify it's NOT burned yet
    response = HTTParty.post("#{@api_base_url}/secret/#{secret_with_pass_data['secret_key']}", body: { passphrase: generated_password })
    raise "Secret with password should not have been burned, but it was" unless response.code == 200
    puts '  Successfully verified that the secret was not burned after reading (since it has a password).'

    # Burn the secret
    puts 'Burning the secret with password...'
    response = HTTParty.post("#{@api_base_url}/private/#{secret_with_pass_data['metadata_key']}/burn")
    raise "Failed to burn secret with password: #{response.body}" unless response.code == 200
    puts '  Successfully burned the secret.'

    # Verify it's burned
    response = HTTParty.post("#{@api_base_url}/secret/#{secret_with_pass_data['secret_key']}", body: { passphrase: generated_password })
    raise "Secret with password should have been burned, but was retrieved again" unless response.code == 404
    puts '  Successfully verified that the secret with password is gone after burning.'

    puts 'VALIDATE mode finished. All checks passed!'
  end
end

if __FILE__ == $PROGRAM_NAME
  options = {
    host: ApiValidation::DEFAULT_HOST
  }
  OptionParser.new do |opts|
    opts.banner = 'Usage: scripts/api_validation.rb [options] [create|validate]'
    opts.on('-h', '--host HOST', 'The host of the Onetime Secret API') do |host|
      options[:host] = host
    end
  end.parse!

  mode = ARGV.pop
  unless %w[create validate].include?(mode)
    puts 'Invalid mode. Must be one of: create, validate'
    exit 1
  end

  ApiValidation.new(options[:host]).run(mode)
end
