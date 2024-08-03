# frozen_string_literal: true

# These tryouts test the functionality of DNSChecker and the
# Approximate API. Note that this tryouts file has no _try
# suffix. This is intentional so that it is not run by
# default. Otherwise we'd be hammering the Approximate API
# with requests that are not actually going to be used in the
# application.

# TODO: Sort out way to mock API responses, in a Tryouts way.

require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot!

@api_key = ENV.fetch('APPROXIMATED_API_KEY', '')
@records = [
  {
    address: "onetimesecret.com",
    match_against: "bogus record",
    type: "txt"
  },
  {
    address: "anapodosis.onetimesecret.com",
    match_against: "v=spf1 include:amazonses.com ~all",
    type: "txt"
  }
]
@mock_response = lambda {{
  "status" => 200,
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
}}

@generate_request = lambda do ||
  OT::Utils::DNSChecker.check_records(@api_key, @records)
end

## Can check TXT record for domain
response = @mock_response.call
content = response['body']
[content["records"].length, content["records"][0]["match"], content["records"][1]["match"]]
#=> [2, false, false]
