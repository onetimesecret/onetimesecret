# lib/onetime/cluster.rb
#
# frozen_string_literal: true

require_relative 'domain_validation/features'
require_relative 'domain_validation/approximated_client'

module Onetime
  module Cluster
    # Features - Cluster-specific configuration.
    #
    # DEPRECATION NOTICE: This module is deprecated in favor of
    # Onetime::DomainValidation::Features. New code should use
    # DomainValidation::Features directly.
    #
    # This module now delegates to DomainValidation::Features for
    # backwards compatibility with existing code.
    #
    # Migration path:
    #   - Old: Onetime::Cluster::Features.api_key
    #   - New: Onetime::DomainValidation::Features.api_key
    #
    #   - Old: Onetime::Cluster::Features.cluster_safe_dump
    #   - New: Onetime::DomainValidation::Features.safe_dump
    #
    module Features
      module ClassMethods
        # Delegated accessors - read from DomainValidation::Features
        def type
          DomainValidation::Features.strategy_name
        end

        def type=(value)
          DomainValidation::Features.strategy_name = value
        end

        def api_key
          DomainValidation::Features.api_key
        end

        def api_key=(value)
          DomainValidation::Features.api_key = value
        end

        def cluster_ip
          DomainValidation::Features.cluster_ip
        end

        def cluster_ip=(value)
          DomainValidation::Features.cluster_ip = value
        end

        def cluster_name
          DomainValidation::Features.cluster_name
        end

        def cluster_name=(value)
          DomainValidation::Features.cluster_name = value
        end

        def cluster_host
          DomainValidation::Features.cluster_host
        end

        def cluster_host=(value)
          DomainValidation::Features.cluster_host = value
        end

        def vhost_target
          DomainValidation::Features.vhost_target
        end

        def vhost_target=(value)
          DomainValidation::Features.vhost_target = value
        end

        # Delegates to DomainValidation::Features.safe_dump
        #
        # @deprecated Use DomainValidation::Features.safe_dump instead
        # @return [Hash] Configuration data safe for client exposure
        #
        def cluster_safe_dump
          DomainValidation::Features.safe_dump
        end
      end

      extend ClassMethods
    end

    # Approximated - HTTP client for approximated.app API.
    #
    # DEPRECATION NOTICE: This module is deprecated in favor of
    # Onetime::DomainValidation::ApproximatedClient. New code should use
    # ApproximatedClient directly.
    #
    # This module now delegates to DomainValidation::ApproximatedClient
    # for backwards compatibility.
    #
    # Migration path:
    #   - Old: Onetime::Cluster::Approximated.create_vhost(...)
    #   - New: Onetime::DomainValidation::ApproximatedClient.create_vhost(...)
    #
    module Approximated
      class << self
        def check_records_exist(api_key, records)
          DomainValidation::ApproximatedClient.check_records_exist(api_key, records)
        end

        def check_records_match_exactly(api_key, records)
          DomainValidation::ApproximatedClient.check_records_match_exactly(api_key, records)
        end

        def create_vhost(api_key, incoming_address, target_address, target_ports, options = {})
          DomainValidation::ApproximatedClient.create_vhost(
            api_key, incoming_address, target_address, target_ports, options
          )
        end

        def get_vhost_by_incoming_address(api_key, incoming_address, force = false)
          DomainValidation::ApproximatedClient.get_vhost_by_incoming_address(
            api_key, incoming_address, force
          )
        end

        def update_vhost(api_key, current_incoming_address, incoming_address,
                         target_address, target_ports, options = {})
          DomainValidation::ApproximatedClient.update_vhost(
            api_key,
            current_incoming_address,
            incoming_address,
            target_address,
            target_ports,
            options,
          )
        end

        def delete_vhost(api_key, incoming_address)
          DomainValidation::ApproximatedClient.delete_vhost(api_key, incoming_address)
        end

        def get_dns_widget_token(api_key)
          DomainValidation::ApproximatedClient.get_dns_widget_token(api_key)
        end
      end
    end
  end
end
