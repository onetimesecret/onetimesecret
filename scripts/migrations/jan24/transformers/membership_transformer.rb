# frozen_string_literal: true

require_relative 'base_transformer'

module Transformers
  # Handles writing generated OrganizationMembership records.
  # Memberships are created 1:1 with Customers during customer transformation.
  class MembershipTransformer < BaseTransformer
    def default_stats
      { generated: 0 }
    end

    # Memberships are generated during customer processing, not routed
    def route(_record, _key)
      nil
    end

    # Write all generated membership records to output file
    def write_generated_records(output_dir, timestamp)
      membership_file = File.join(output_dir, "org_membership_generated_#{timestamp}.jsonl")
      File.open(membership_file, 'w') do |f|
        email_to_membership.each do |_email, membership|
          record = {
            key: "org_membership:#{membership[:objid]}:object",
            type: 'hash',
            ttl_ms: -1,
            generated: true,
            fields: membership,
          }
          f.puts(JSON.generate(record))
        end
      end
      puts "  Written: #{File.basename(membership_file)} (#{email_to_membership.size} records)"
    end
  end
end
