# tests/unit/ruby/rspec/onetime/refinements/rack_refinements_spec.rb

require_relative '../../spec_helper.rb'
# require_relative "./hash_spec.rb"

require 'onetime/refinements/rack_refinements'

RSpec.describe Onetime::RackRefinements do
  # Define module for testing scope
  module RefineTest
    using Onetime::RackRefinements

    def self.fetch_with_refinements(hash, key, *args, &block)
      hash.fetch(key, *args, &block)
    end

    def self.dig_with_refinements(hash, *keys)
      hash.dig(*keys)
    end
  end

  let(:test_hash) { {"string_key" => "value1", symbol_key: "value2"} }

  shared_examples "hash access behavior" do |refined: false|
    context "#fetch" do
      if refined
        def fetch_from(hash, *args, &block)
          RefineTest.fetch_with_refinements(hash, *args, &block)
        end
      else
        def fetch_from(hash, *args, &block)
          hash.fetch(*args, &block)
        end
      end

      it "retrieves string key values" do
        expect(fetch_from(test_hash, "string_key")).to eq("value1")
      end

      it "retrieves symbol key values using string" do
        if refined
          expect(fetch_from(test_hash, "symbol_key")).to eq("value2")
        else
          expect { fetch_from(test_hash, "symbol_key") }.to raise_error(KeyError)
        end
      end

      it "retrieves symbol key values using symbol" do
        expect(fetch_from(test_hash, :symbol_key)).to eq("value2")
      end

      it "handles missing keys with default" do
        expect(fetch_from(test_hash, "missing", "default")).to eq("default")
      end

      it "handles missing keys with block" do
        expect(fetch_from(test_hash, "missing") { "block_value" }).to eq("block_value")
      end

      it "raises KeyError for missing keys" do
        expect { fetch_from(test_hash, "missing") }.to raise_error(KeyError)
      end
    end
  end

  context "with refinements" do
    include_examples "hash access behavior", refined: true
  end

  context "without refinements" do
    include_examples "hash access behavior", refined: false
  end
end
