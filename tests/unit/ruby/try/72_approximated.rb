# tests/unit/ruby/try/72_approximated.rb

# These tryouts test the functionality of Approximated and the
# Approximate API. Note that this tryouts file has no _try
# suffix. This is intentional so that it is not run by
# default. Otherwise we'd be hammering the Approximated API
# with requests that are not actually going to be used in the
# application.
#
# Usage:
#
#   $ try -vf tests/unit/ruby/try/72_approximated.rb
#
# NOTE: These tryouts send real requests to the Approximated API.

require 'dotenv'

Dotenv.load('.env')

require_relative './test_helpers'
require 'onetime/models'

# Use the default config file for tests
OT.boot! :test, false

@api_key = ENV.fetch('APPROXIMATED_API_KEY', '')
@dns_records = [
  {
    address: "onetimesecret.com",
    match_against: "bogus record",
    type: "txt"
  },
  {
    address: "anapodosis.eu.onetimesecret.com",
    match_against: "v=spf1 include:amazonses.com ~all",
    type: "txt"
  },
  {
    address: "anapodosis.eu.onetimesecret.com",
    match_against: "Bogus Journey",
    type: "txt"
  }
]
@dns_records_actual = [
  {
    address: "secrets.onetime.co",
    match_against: "identity.eu.onetime.co",
    type: "cname"
  },
  {
    address: "secrets.solutious.com",
    match_against: "109.105.217.207",
    type: "a"
  },
]
@vhost1 = {
  incoming_address: "72.tryouts.deleteme.ifyou.seeme.onetimesecret.com",
  target_address: "staging.onetimesecret.com",
  target_ports: "443"
}
@mock_response = {
  check_records_exist: lambda {IndifferentHash.new(
    "code" => 200,
    "body" => {
      "records" => [
        {
          "actual_values" => [
            "v=spf1 a mx include:_spf.protonmail.ch include:amazonses.com ~all",
            "protonmail-verification=0745c38ad38819619ee67ca0508365555d3306db"
          ],
          "address" => "onetimesecret.com",
          "match" => false,
          "match_against" => "bogus record",
          "type" => "txt"
        },
        {
          "actual_values" => [
            "v=spf1 mx include:shh.onetimesecret.com include:amazonses.com ~all"
          ],
          "address" => "anapodosis.onetimesecret.com",
          "match" => false,
          "match_against" => "v=spf1 include:amazonses.com ~all",
          "type" => "txt"
        }
      ]
    }
  )}
}

@generate_request = {
  check_records_exist: lambda { ||
    OT::Cluster::Approximated.check_records_exist(@api_key, @dns_records)
  },
  check_records_match_exactly: lambda { ||
    OT::Cluster::Approximated.check_records_match_exactly(@api_key, @dns_records)
  },
  check_records_match_exactly_actual: lambda { ||
    OT::Cluster::Approximated.check_records_match_exactly(@api_key, @dns_records_actual)
  },
  create_vhost: lambda { ||
    OT::Cluster::Approximated.create_vhost(@api_key, @vhost1[:incoming_address], @vhost1[:target_address], @vhost1[:target_ports])
  },
  get_vhost_by_incoming_address: lambda  { ||
    OT::Cluster::Approximated.get_vhost_by_incoming_address(@api_key, @vhost1[:incoming_address])
  },
  delete_vhost: lambda  { ||
    OT::Cluster::Approximated.delete_vhost(@api_key, @vhost1[:incoming_address])
  }
}

## API Key has a value
@api_key.length > 1
#=> true

## Can check TXT record for domain
response = @mock_response[:check_records_exist].call
content = response.body
[content["records"].length, content["records"][0]["match"], content["records"][1]["match"]]
#=> [2, false, false]

## Can check TXT record matches exactly for domain
response = @generate_request[:check_records_match_exactly].call
content = response.parsed_response
pp response.parsed_response
[content["records"].length, content["records"][0]["match"], content["records"][1]["match"], content["records"][2]["match"]]
#=> [3, false, true, false]

## Can check actual custom domain records match exactly for domain
response = @generate_request[:check_records_match_exactly_actual].call
content = response.parsed_response
pp response.parsed_response
[content["records"].length, content["records"][0]["match"], content["records"][1]["match"]]
#=> [2, true, true]


## Can add a vhost record
response = @generate_request[:create_vhost].call
content = response.parsed_response
puts content["data"]
puts 'Recommended user message: %s' % content.dig("data", "user_message")
[content.keys.length, content.dig("data", "incoming_address"), content.dig("data", "target_address"), content.dig("data", "target_ports")]
#=> [1, @vhost1[:incoming_address], @vhost1[:target_address], @vhost1[:target_ports]]


## Raises an exception if vhost record already exists
begin
  @generate_request[:create_vhost].call

rescue HTTParty::ResponseError => e
  [e.class, e.message.include?('already been created on the cluster'), e.message.include?('incoming_address')]
end
#=> [HTTParty::ResponseError, true, true]


## Can read a vhost record
response = @generate_request[:get_vhost_by_incoming_address].call
content  = response.parsed_response
pp content
[content.keys.length, content.dig("data", "incoming_address"), content.dig("data", "target_address"), content.dig("data", "target_ports")]
#=> [1, "72.tryouts.deleteme.ifyou.seeme.onetimesecret.com", "staging.onetimesecret.com", "443"]


## Can delete a vhost record
response = @generate_request[:delete_vhost].call
content = response.parsed_response
content
#=> "Deleting #{@vhost1[:incoming_address]}"
