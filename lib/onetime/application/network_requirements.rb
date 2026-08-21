# lib/onetime/application/network_requirements.rb
#
# frozen_string_literal: true

require 'json'
require 'otto/route_definition'

require_relative '../middleware/admin_network_isolation'

module Onetime
  module Application
    # Enforces declarative network requirements from Otto route options.
    #
    # `network=admin` is stricter than the general Colonel posture: the route is
    # absent unless both ADMIN_ALLOWED_HOSTS and ADMIN_ALLOWED_CIDRS were
    # explicitly configured and their gates admitted the request.
    module NetworkRequirements
      extend self

      ADMIN = 'admin'

      STRATEGIES = {
        ADMIN => ->(env) {
          env[Onetime::Middleware::AdminNetworkIsolation::ROUTE_REQUIREMENT_ENV_KEY] == true
        },
      }.freeze

      class Wrapper
        def initialize(inner_handler, route_definition, requirement, strategy)
          @inner_handler    = inner_handler
          @route_definition = route_definition
          @requirement      = requirement
          @strategy         = strategy
        end

        def call(env, *)
          return @inner_handler.call(env, *) if @strategy.call(env)

          Onetime.get_logger('NetworkRequirements').warn(
            'Route network requirement not satisfied',
            {
              requirement: @requirement,
              method: env['REQUEST_METHOD'],
              route: @route_definition.path,
            },
          )

          not_found_response
        end

        private

        def not_found_response
          if @route_definition.response_type == 'json'
            [404, { 'Content-Type' => 'application/json' }, [JSON.generate({ error: 'Not Found' })]]
          else
            [404, { 'Content-Type' => 'text/plain; charset=utf-8' }, ['Not Found']]
          end
        end
      end

      def register(router)
        router.register_handler_wrapper do |route_definition, inner_handler|
          requirement = requirement_for(route_definition)
          next inner_handler unless requirement

          strategy = STRATEGIES[requirement]
          unless strategy
            raise Otto::RouteDefinitionError,
              "Unknown network requirement #{requirement.inspect} in route definition " \
              "#{route_definition.definition.inspect}"
          end

          Wrapper.new(inner_handler, route_definition, requirement, strategy)
        end
      end

      # Otto 2.9 accepts arbitrary key=value route options, so `network=admin`
      # parses without framework changes. Until Otto treats `network` as one of
      # its fail-fast security options, validate malformed/case-varied spellings
      # here rather than allowing a bare `network` token to be ignored.
      def requirement_for(route_definition)
        tokens = route_definition.definition.split(/\s+/).drop(1).select do |token|
          token.split('=', 2).first&.downcase == 'network'
        end
        return route_definition.option(:network) if tokens.empty?

        tokens.each do |token|
          key, value = token.split('=', 2)
          next if key == 'network' && value && !value.empty?

          raise Otto::RouteDefinitionError,
            "Malformed security option #{token.inspect} in route definition " \
            "#{route_definition.definition.inspect}: expected network=value"
        end

        route_definition.option(:network)
      end
    end
  end
end
