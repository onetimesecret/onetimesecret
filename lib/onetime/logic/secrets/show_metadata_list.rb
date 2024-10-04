require 'time'

module Onetime::Logic
  module Secrets

    class ShowMetadataList < OT::Logic::Base
      attr_reader :records, :since, :now, :query_results
      attr_reader :received, :notreceived, :has_items

      def process_params
        # Calculate the timestamp for 30 days ago
        @now = Time.now
        @since = (Time.now - 30*24*60*60).to_i

      end

      def raise_concerns
        limit_action :show_metadata
      end

      def process
        # Fetch entries from the sorted set within the past 30 days
        @query_results = cust.metadata.rangebyscore(since, @now.to_i)

        #        metadata = cust.metadata_list.collect do |m|
        #          { :uri => private_uri(m),
        #            :stamp => natural_time(m.updated),
        #            :updated => epochformat(m.updated),
        #            :key => m.key,
        #            :shortkey => m.key.slice(0,8),
        #
        #            :recipients => m.recipients,
        #            :show_recipients => !m.recipients.to_s.empty?,
        #
        #            :is_received => m.state?(:received),
        #            :is_burned => m.state?(:burned),
        #            :is_destroyed => (m.state?(:received) || m.state?(:burned))}
        #        end.compact

        # Get the safe fields for each record
        @records = query_results.filter_map do |identifier|
          md = OT::Metadata.from_identifier(identifier)
          md&.safe_dump
        end

        @has_items = records.any?
        @received, @notreceived = *records.partition{ |m| m[:is_destroyed] }
        received.sort!{ |a,b| b[:updated] <=> a[:updated] }
      end

      def success_data
        {
          custid: cust.custid,
          count: records.count,
          records: records,
          details: {
            since: since,
            now: now,
            has_items: has_items,
            received: received,
            notreceived: notreceived
          }
        }
      end
    end

  end
end
