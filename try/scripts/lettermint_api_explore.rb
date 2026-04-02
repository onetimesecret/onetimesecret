#!/usr/bin/env ruby
# frozen_string_literal: true

# Lettermint API Explorer Script
#
# Lettermint has TWO separate APIs:
#   1. Sending API - uses x-lettermint-token header (project token)
#   2. Team API    - uses Authorization: Bearer header (team token)
#
# Domain management is on the Team API, NOT the Sending API.
#
# Usage:
#   # Team API (for domain management) - use LETTERMINT_TEAM_TOKEN
#   LETTERMINT_TEAM_TOKEN=xxx bundle exec ruby try/scripts/lettermint_api_explore.rb list
#
#   # Sending API (for email) - use LETTERMINT_API_TOKEN
#   LETTERMINT_API_TOKEN=xxx bundle exec ruby try/scripts/lettermint_api_explore.rb ping
#
# Actions:
#   ping      - Test Sending API connectivity
#   list      - List all sender domains (Team API)
#   create    - Create/provision a domain (Team API)
#   get       - Get domain details (Team API)
#   verify    - Trigger DNS verification (Team API)
#   delete    - Delete a domain (Team API)

require 'bundler/setup'
require 'faraday'
require 'json'

class LettermintExplorer
  BASE_URL = 'https://api.lettermint.co/v1'

  def initialize(team_token: nil, sending_token: nil, base_url: nil)
    @team_token = team_token
    @sending_token = sending_token
    @base_url = base_url || BASE_URL

    puts "Base URL: #{@base_url}"
    puts "Team token: #{token_preview(@team_token)}" if @team_token
    puts "Sending token: #{token_preview(@sending_token)}" if @sending_token
    puts
  end

  def token_preview(token)
    return 'not set' unless token && token.length > 12
    "#{token[0..7]}...#{token[-4..]}"
  end

  # Team API connection (Bearer auth) - for domain management
  def team_connection
    raise 'LETTERMINT_TEAM_TOKEN required for domain operations' unless @team_token

    @team_connection ||= Faraday.new(url: "#{@base_url.chomp('/')}/") do |f|
      f.request :json
      f.response :json
      f.options.timeout = 30
      f.options.open_timeout = 10
      f.headers = {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json',
        'Authorization' => "Bearer #{@team_token}",
        'User-Agent' => 'Lettermint-Explorer/1.0'
      }
    end
  end

  # Sending API connection (x-lettermint-token) - for email sending
  def sending_connection
    raise 'LETTERMINT_API_TOKEN required for sending operations' unless @sending_token

    @sending_connection ||= Faraday.new(url: "#{@base_url.chomp('/')}/") do |f|
      f.request :json
      f.response :json
      f.options.timeout = 30
      f.options.open_timeout = 10
      f.headers = {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json',
        'x-lettermint-token' => @sending_token,
        'User-Agent' => 'Lettermint-Explorer/1.0'
      }
    end
  end

  def request(conn, method, path, data: nil)
    puts "#{method.upcase} #{path}"
    puts "  Data: #{data.to_json}" if data

    response = case method
               when :get then conn.get(path)
               when :post then conn.post(path) { |req| req.body = data }
               when :put then conn.put(path) { |req| req.body = data }
               when :delete then conn.delete(path)
               end

    puts "  Status: #{response.status}"
    puts "  Headers: #{response.headers.select { |k, _| k =~ /content|rate|retry/i }}"

    if response.body.is_a?(Hash) || response.body.is_a?(Array)
      puts "  Body: #{JSON.pretty_generate(response.body)}"
    elsif response.body
      puts "  Body: #{response.body[0..500]}"
    end
    puts

    { status: response.status, body: response.body, headers: response.headers }
  rescue Faraday::Error => e
    puts "  Error: #{e.class} - #{e.message}"
    puts
    { status: 0, body: nil, error: e.message }
  end

  # Test Sending API connectivity
  def ping
    puts "=" * 60
    puts "Testing Sending API (ping)"
    puts "=" * 60
    puts
    request(sending_connection, :get, '/ping')
  end

  # Team API: List all domains
  def list_domains
    puts "=" * 60
    puts "Listing Sender Domains (Team API)"
    puts "=" * 60
    puts
    request(team_connection, :get, '/domains')
  end

  # Team API: Create a new domain
  def create_domain(domain)
    puts "=" * 60
    puts "Creating Domain: #{domain} (Team API)"
    puts "=" * 60
    puts

    # The API likely expects { domain: "example.com" } or { name: "example.com" }
    # Try the most likely payload first
    result = request(team_connection, :post, '/domains', data: { domain: domain })
    return result if [200, 201].include?(result[:status])

    # If 409 conflict, domain already exists - retrieve it
    if result[:status] == 409
      puts "Domain already exists, retrieving..."
      return get_domain(domain)
    end

    # Try alternative payload format
    request(team_connection, :post, '/domains', data: { name: domain })
  end

  # Team API: Get domain details by ID
  # GET /domains/{id}?include=dnsRecords
  def get_domain(domain_id)
    puts "=" * 60
    puts "Getting Domain: #{domain_id} (Team API)"
    puts "=" * 60
    puts
    request(team_connection, :get, "/domains/#{domain_id}?include=dnsRecords")
  end

  # Team API: Verify DNS records for a domain
  # POST /domains/{id}/dns-records/verify (all records)
  # POST /domains/{id}/dns-records/{recordId}/verify (single record)
  def verify_domain(domain_id, record_id: nil)
    puts "=" * 60
    puts "Verifying Domain DNS: #{domain_id} (Team API)"
    puts "=" * 60
    puts

    path = if record_id
             "/domains/#{domain_id}/dns-records/#{record_id}/verify"
           else
             "/domains/#{domain_id}/dns-records/verify"
           end
    request(team_connection, :post, path)
  end

  # Team API: Delete a domain
  def delete_domain(domain_id)
    puts "=" * 60
    puts "Deleting Domain: #{domain_id} (Team API)"
    puts "=" * 60
    puts
    request(team_connection, :delete, "/domains/#{domain_id}")
  end
end

# Main
team_token = ENV['LETTERMINT_TEAM_TOKEN']
sending_token = ENV['LETTERMINT_API_TOKEN']

if team_token.nil? && sending_token.nil?
  puts "Lettermint API Explorer"
  puts "=" * 60
  puts
  puts "Lettermint has TWO separate APIs with different auth:"
  puts
  puts "  1. SENDING API (x-lettermint-token header)"
  puts "     - For sending emails"
  puts "     - Uses project-level API token"
  puts "     - Endpoints: /send, /ping"
  puts
  puts "  2. TEAM API (Authorization: Bearer header)"
  puts "     - For domain management"
  puts "     - Uses team-level API token"
  puts "     - Endpoints: /domains, /domains/{id}, /domains/{id}/dns-records/verify"
  puts
  puts "Usage:"
  puts "  # Domain management (Team API)"
  puts "  LETTERMINT_TEAM_TOKEN=xxx bundle exec ruby #{__FILE__} list"
  puts "  LETTERMINT_TEAM_TOKEN=xxx bundle exec ruby #{__FILE__} create solutious.com"
  puts "  LETTERMINT_TEAM_TOKEN=xxx bundle exec ruby #{__FILE__} get <domain-id>"
  puts "  LETTERMINT_TEAM_TOKEN=xxx bundle exec ruby #{__FILE__} verify <domain-id> [record-id]"
  puts "  LETTERMINT_TEAM_TOKEN=xxx bundle exec ruby #{__FILE__} delete <domain-id>"
  puts
  puts "  # Sending API test"
  puts "  LETTERMINT_API_TOKEN=xxx bundle exec ruby #{__FILE__} ping"
  puts
  puts "Options:"
  puts "  LETTERMINT_BASE_URL - Override base URL (default: https://api.lettermint.co/v1)"
  exit 1
end

action = ARGV[0] || 'list'
arg = ARGV[1]

base_url = ENV['LETTERMINT_BASE_URL']
explorer = LettermintExplorer.new(
  team_token: team_token,
  sending_token: sending_token,
  base_url: base_url
)

case action
when 'ping'
  explorer.ping
when 'list'
  explorer.list_domains
when 'create'
  abort "Usage: #{__FILE__} create <domain>" unless arg
  explorer.create_domain(arg)
when 'get'
  abort "Usage: #{__FILE__} get <domain-id>" unless arg
  explorer.get_domain(arg)
when 'verify'
  abort "Usage: #{__FILE__} verify <domain-id> [record-id]" unless arg
  record_id = ARGV[2]
  explorer.verify_domain(arg, record_id: record_id)
when 'delete'
  abort "Usage: #{__FILE__} delete <domain-id>" unless arg
  explorer.delete_domain(arg)
else
  puts "Unknown action: #{action}"
  puts "Valid actions: ping, list, create, get, verify, delete"
  exit 1
end
