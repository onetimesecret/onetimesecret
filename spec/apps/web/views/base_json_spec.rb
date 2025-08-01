# spec/apps/web/views/base_json_spec.rb

require_relative '../../../spec_helper'
require 'json'

RSpec.xdescribe Core::Views::BaseView, "JSON Output" do
  include_context "rack_test_context"

  let(:authenticated_json) do
    json_path = File.expand_path('../../../../support/window-authenticated.json', __FILE__)
    JSON.parse(File.read(json_path))
  end

  let(:not_authenticated_json) do
    json_path = File.expand_path('../../../../support/window-notauthenticated.json', __FILE__)
    JSON.parse(File.read(json_path))
  end

  describe "JSON structure validation" do
    context "for unauthenticated user" do
      let(:session) do
        instance_double('V1::Session',
          authenticated?: false,
          add_shrimp: not_authenticated_json["shrimp"],
          get_messages: not_authenticated_json["messages"] || [])
      end

      let(:customer) do
        instance_double('V2::Customer',
          'custid' => nil,
          'email' => nil,
          'anonymous?' => true,
          'planid' => 'anonymous',
          'created' => Time.now.to_i,
          'safe_dump' => nil,
          'verified?' => false,
          'active?' => false,
          'role' => 'anonymous',
          'custom_domains_list' => [])
      end

      let(:rack_request) do
        instance_double(Rack::Request,
          params: {},
          env: {
            'REMOTE_ADDR' => '127.0.0.1',
            'HTTP_HOST' => not_authenticated_json["site_host"],
            'rack.session' => {},
            'HTTP_ACCEPT' => 'application/json',
            'onetime.domain_strategy' => not_authenticated_json["domain_strategy"],
            'onetime.display_domain' => not_authenticated_json["display_domain"],
            'ots.locale' => not_authenticated_json["locale"],
          })
      end

      before do
        # Configure all OT settings to match JSON sample
        allow(OT).to receive('conf').and_return({
          'site' => {
            'host' => authenticated_json["site_host"],
            'interface' => { 'ui' => authenticated_json["ui"] },
            'authentication' => authenticated_json["authentication"],
            'domains' => { 'enabled' => authenticated_json["domains_enabled"] },
            # Ensure regions has direct enabled property
            'regions' => {
              'enabled' => authenticated_json["regions_enabled"],
              'current_jurisdiction' => authenticated_json["regions"]["current_jurisdiction"],
              'jurisdictions' => authenticated_json["regions"]["jurisdictions"],
            },
            'secret_options' => authenticated_json["secret_options"],
          },
          'development' => {
            'enabled' => true,
            'frontend_host' => authenticated_json["frontend_host"],
          },
        })

        # Set up internationalization
        allow(OT).to receive('default_locale').and_return(not_authenticated_json["default_locale"])
        allow(OT).to receive('fallback_locale').and_return(not_authenticated_json["fallback_locale"])
        allow(OT).to receive('supported_locales').and_return(not_authenticated_json["supported_locales"])
        allow(OT).to receive('i18n_enabled').and_return(not_authenticated_json["i18n_enabled"])
        allow(OT).to receive('d9s_enabled').and_return(not_authenticated_json["d9s_enabled"])

        # Create locales mock
        allow(OT).to receive('locales').and_return({
          'en' => {
            :web => {
              :COMMON => {
                :description => 'Test Description',
                :keywords => 'test,keywords',
              },
            },
          },
        })

        # Mock version info - Use double instead of OpenStruct
        allow(OT).to receive('global_banner').and_return(nil)

        allow(OT).to receive('VERSION').and_return("0.20.4 ()")

        # For domain strategy
        allow(Onetime::DomainStrategy).to receive(:canonical_domain).and_return(not_authenticated_json["canonical_domain"])
      end

      it "generates expected JSON structure for anonymous user" do
        view = described_class.new(rack_request, session, customer)
        json_output = JSON.parse(view[:window])

        # Compare key fields
        expect(json_output["authenticated"]).to eq(false)
        expect(json_output["site_host"]).to eq(not_authenticated_json["site_host"])
        expect(json_output["regions_enabled"]).to eq(not_authenticated_json["regions_enabled"])
        expect(json_output["domains_enabled"]).to eq(not_authenticated_json["domains_enabled"])

        # Test structure excluding volatile fields
        filtered_output = json_output.except("shrimp", "ot_version", "ot_version_long", "ruby_version", "messages")
        filtered_sample = not_authenticated_json.except("shrimp", "ot_version", "ot_version_long", "ruby_version", "messages")

        expect(filtered_output).to match(filtered_sample)
      end
    end

    context "for authenticated user" do
      let(:session) do
        instance_double('V1::Session',
          authenticated?: true,
          add_shrimp: authenticated_json["shrimp"],
          get_messages: authenticated_json["messages"] || [])
      end

      let(:customer) do
        # Create mock for custom domains
        custom_domains = authenticated_json["custom_domains"].map do |domain|
          instance_double('V2::CustomDomain',
            display_domain: domain,
            ready?: true,
            verified: true,
            resolving: true)
        end

        # Create customer mock
        instance_double('V2::Customer',
          custid: authenticated_json["custid"],
          email: authenticated_json["email"],
          anonymous?: false,
          planid: authenticated_json["cust"]["planid"],
          created: authenticated_json["cust"]["created"].to_i,
          safe_dump: authenticated_json["cust"],
          custom_domains_list: custom_domains,
          verified?: true,
          active?: false,
          role: authenticated_json["cust"]["role"])
      end

      let(:rack_request) do
        instance_double(Rack::Request,
          params: {},
          env: {
            'REMOTE_ADDR' => '127.0.0.1',
            'HTTP_HOST' => authenticated_json["site_host"],
            'rack.session' => {},
            'HTTP_ACCEPT' => 'application/json',
            'onetime.domain_strategy' => authenticated_json["domain_strategy"],
            'onetime.display_domain' => authenticated_json["display_domain"],
            'ots.locale' => authenticated_json["locale"],
          })
      end

      before do
        # Configure all OT settings to match JSON sample
        allow(OT).to receive('conf').and_return({
            site: {
              host: not_authenticated_json["site_host"],
              interface: { ui: not_authenticated_json["ui"] },
              authentication: not_authenticated_json["authentication"],
              domains: { enabled: not_authenticated_json["domains_enabled"] },
              # Ensure regions has direct enabled property
              regions: {
                enabled: not_authenticated_json["regions_enabled"],
                current_jurisdiction: not_authenticated_json["regions"]["current_jurisdiction"],
                jurisdictions: not_authenticated_json["regions"]["jurisdictions"],
              },
              secret_options: not_authenticated_json["secret_options"],
            },
            development: {
              enabled: true,
              frontend_host: not_authenticated_json["frontend_host"],
            },
          })

        # Set up internationalization
        allow(OT).to receive('default_locale').and_return(authenticated_json["default_locale"])
        allow(OT).to receive('fallback_locale').and_return(authenticated_json["fallback_locale"])
        allow(OT).to receive('supported_locales').and_return(authenticated_json["supported_locales"])
        allow(OT).to receive('i18n_enabled').and_return(authenticated_json["i18n_enabled"])
        allow(OT).to receive('d9s_enabled').and_return(authenticated_json["d9s_enabled"])

        # Create locales mock
        allow(OT).to receive('locales').and_return({
          'en' => {
            web: {
              COMMON: {
                description: 'Test Description',
                keywords: 'test,keywords',
              },
            },
          },
        })

        # Mock version info - Use double instead of OpenStruct
        allow(OT).to receive('global_banner').and_return(nil)

        allow(OT).to receive('VERSION').and_return("0.20.4 (plop)")

        # For domain strategy
        allow(Onetime::DomainStrategy).to receive(:canonical_domain).and_return(authenticated_json["canonical_domain"])

        # For epochdom method
        allow_any_instance_of(Core::Views::BaseView).to receive(:epochdom)
          .with(authenticated_json["cust"]["created"].to_i)
          .and_return(authenticated_json["customer_since"])
      end

      it "generates expected JSON structure for authenticated user" do
        view = described_class.new(rack_request, session, customer)
        json_output = JSON.parse(view[:window])

        # Compare key authenticated fields
        expect(json_output["authenticated"]).to eq(true)
        expect(json_output["custid"]).to eq(authenticated_json["custid"])
        expect(json_output["email"]).to eq(authenticated_json["email"])
        expect(json_output["domains_enabled"]).to eq(authenticated_json["domains_enabled"])
        expect(json_output["custom_domains"]).to match_array(authenticated_json["custom_domains"])

        # Test structure excluding volatile fields
        filtered_output = json_output.except("shrimp", "ot_version", "ot_version_long", "ruby_version", "messages")
        filtered_sample = authenticated_json.except("shrimp", "ot_version", "ot_version_long", "ruby_version", "messages")

        expect(filtered_output).to match(filtered_sample)
      end
    end
  end
end
