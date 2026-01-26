# frozen_string_literal: true

require_relative 'base_transformer'

module Transformers
  # Handles writing generated Organization records.
  # Organizations are created 1:1 with Customers during customer transformation.
  class OrganizationTransformer < BaseTransformer
    def default_stats
      { generated: 0 }
    end

    # Organizations are generated during customer processing, not routed
    def route(_record, _key)
      nil
    end

    # Write all generated organization records to output file
    def write_generated_records(output_dir, timestamp)
      org_file = File.join(output_dir, "organization_generated_#{timestamp}.jsonl")
      File.open(org_file, 'w') do |f|
        email_to_org_data.each do |_email, org|
          record = {
            key: "organization:#{org[:objid]}:object",
            type: 'hash',
            ttl_ms: -1,
            generated: true,
            fields: org,
          }
          f.puts(JSON.generate(record))
        end
      end
      puts "  Written: #{File.basename(org_file)} (#{email_to_org_data.size} records)"
    end
  end
end
