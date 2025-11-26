# apps/api/colonel/logic/colonel/get_database_metrics.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      class GetDatabaseMetrics < ColonelAPI::Logic::Base
        attr_reader :redis_info, :db_sizes, :total_keys, :memory_stats

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          # Get Redis INFO
          info = Familia.dbclient.info

          # Database sizes (number of keys per database)
          @db_sizes = {}
          info.each do |key, value|
            next unless key.start_with?('db')

            # Parse db0:keys=123,expires=45,avg_ttl=3600
            parts          = value.split(',').map { |p| p.split('=') }.to_h
            @db_sizes[key] = {
              keys: parts['keys'].to_i,
              expires: parts['expires'].to_i,
              avg_ttl: parts['avg_ttl'].to_i,
            }
          end

          # Total keys across all databases
          @total_keys = @db_sizes.values.sum { |db| db[:keys] }

          # Memory statistics
          @memory_stats = {
            used_memory: info['used_memory'].to_i,
            used_memory_human: info['used_memory_human'],
            used_memory_rss: info['used_memory_rss'].to_i,
            used_memory_rss_human: info['used_memory_rss_human'],
            used_memory_peak: info['used_memory_peak'].to_i,
            used_memory_peak_human: info['used_memory_peak_human'],
            mem_fragmentation_ratio: info['mem_fragmentation_ratio'].to_f,
          }

          # Server stats
          @redis_info = {
            redis_version: info['redis_version'],
            redis_mode: info['redis_mode'],
            os: info['os'],
            uptime_in_seconds: info['uptime_in_seconds'].to_i,
            uptime_in_days: info['uptime_in_days'].to_i,
            connected_clients: info['connected_clients'].to_i,
            total_commands_processed: info['total_commands_processed'].to_i,
            instantaneous_ops_per_sec: info['instantaneous_ops_per_sec'].to_i,
          }

          success_data
        end

        def success_data
          {
            record: {},
            details: {
              redis_info: redis_info,
              database_sizes: db_sizes,
              total_keys: total_keys,
              memory_stats: memory_stats,
              model_counts: {
                customers: Onetime::Customer.count,
                secrets: Onetime::Secret.new.dbclient.keys('secret*:object').count,
                metadata: Onetime::Metadata.new.dbclient.keys('metadata*:object').count,
              },
            },
          }
        end
      end
    end
  end
end
