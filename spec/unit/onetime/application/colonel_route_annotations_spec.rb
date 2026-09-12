# spec/unit/onetime/application/colonel_route_annotations_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Unit (parses apps/api/colonel/routes.txt as data; boots nothing)
# =============================================================================
#
# #4332. The colonel route table is the only place the tier-1 network
# annotation exists, and NOTHING checks it at boot: Otto's
# validate_handler_wrappers! runs lazily on the first request and is skipped
# entirely under RSpec, so a misspelled `network=` token is a runtime 500 on a
# destructive verb rather than a boot failure.
#
# These examples are that missing check, plus the coverage guarantee:
#
#   (a) every ColonelAPI::DestructiveActions::TIER1 class has exactly one route
#       and it carries `network=admin_if_configured`;
#   (b) no tier-2 or tier-3 route carries a `network=` token at all, except the
#       one strict `network=admin` route the annotation predates;
#   (c) every `network=` token in the file spells a key that
#       Application::NetworkRequirements::STRATEGIES actually implements.
#
# (a) is deliberately TIER1-only: two tier-2 classes (ManageEntitlementOverride,
# ManageMembershipEntitlementOverride) serve two routes each, so "exactly one
# route per class" is not a property of the other tiers.
# =============================================================================

require 'spec_helper'
require 'onetime/application/network_requirements'

require_relative '../../../../apps/api/colonel/destructive_actions'

RSpec.describe 'colonel route network annotations (#4332)' do
  ROUTES_FILE = File.expand_path('../../../../apps/api/colonel/routes.txt', __dir__)

  # One parsed route line: the HTTP verb, the path, the unqualified handler
  # class name, and whatever `network=` token it carries (nil for most).
  Route = Struct.new(:verb, :path, :handler, :network, :line_number, keyword_init: true)

  # The strict token is grandfathered on exactly one route — a GET debug
  # endpoint that is SUPPOSED to be absent unless admin isolation is fully
  # configured. Widening it is a breaking change, so it is pinned by path here.
  STRICT_TOKEN_ROUTE = '/system/proxy-headers'

  def parse_routes
    File.readlines(ROUTES_FILE, encoding: 'UTF-8').each_with_index.filter_map do |line, index|
      next unless line =~ /\A(GET|POST|PUT|PATCH|DELETE)\s/

      tokens = line.split(/\s+/)
      network = tokens.find { |token| token.start_with?('network=') }

      Route.new(
        verb: tokens[0],
        path: tokens[1],
        handler: tokens[2].to_s.split('::').last,
        network: network&.split('=', 2)&.last,
        line_number: index + 1,
      )
    end
  end

  let(:routes) { parse_routes }
  let(:tier1)  { ColonelAPI::DestructiveActions::TIER1 }

  it 'parses a route table that is actually there' do
    # Guards every other example in this file: a rename or a parser regression
    # would otherwise turn all of them into assertions about an empty list.
    expect(routes.size).to be > 80
  end

  describe 'tier-1 coverage' do
    it 'gives every TIER1 class exactly one route' do
      counts = tier1.to_h { |name| [name, routes.count { |route| route.handler == name }] }

      expect(counts.reject { |_, count| count == 1 }).to be_empty
    end

    it 'annotates every TIER1 route with network=admin_if_configured' do
      unannotated = routes
        .select { |route| tier1.include?(route.handler) }
        .reject { |route| route.network == Onetime::Application::NetworkRequirements::ADMIN_IF_CONFIGURED }
        .map { |route| "#{route.verb} #{route.path} (line #{route.line_number})" }

      expect(unannotated).to be_empty
    end

    it 'annotates exactly the tier-1 set and nothing else' do
      # The inverse of the example above. Together they make the annotation and
      # the committed tier list one fact rather than two that can drift.
      annotated = routes
        .select { |route| route.network == Onetime::Application::NetworkRequirements::ADMIN_IF_CONFIGURED }
        .map(&:handler)

      expect(annotated.sort).to eq(tier1.sort)
    end
  end

  describe 'the strict network=admin token' do
    it 'is applied to exactly one route, the proxy-header diagnostic' do
      strict = routes.select { |route| route.network == Onetime::Application::NetworkRequirements::ADMIN }

      expect(strict.map(&:path)).to eq([STRICT_TOKEN_ROUTE])
    end

    it 'is never applied to a mutating route' do
      # The strict token has no fall-through: on a stock self-hosted install it
      # is an unconditional 404. On a read that is a documented diagnostic
      # posture; on a mutation it is an outage with no diagnosis.
      strict_mutations = routes.select do |route|
        route.network == Onetime::Application::NetworkRequirements::ADMIN && route.verb != 'GET'
      end

      expect(strict_mutations).to be_empty
    end
  end

  describe 'tier-2 and tier-3 routes' do
    it 'carry no network requirement' do
      # Deliberate scoping, not an oversight: a network requirement is the one
      # control in this epic that fails as a silent 404, so it covers the
      # irreversible set only. Changing this means changing the docs too.
      annotated = routes
        .reject { |route| tier1.include?(route.handler) }
        .reject { |route| route.path == STRICT_TOKEN_ROUTE }
        .select(&:network)
        .map { |route| "#{route.verb} #{route.path} (line #{route.line_number})" }

      expect(annotated).to be_empty
    end
  end

  it 'spells every network token as a strategy that exists' do
    # The check Otto cannot give us: validate_handler_wrappers! runs on the
    # first request and is skipped under RSpec, so a typo here reaches
    # production as a 500 on a destructive verb.
    unknown = routes
      .select(&:network)
      .reject { |route| Onetime::Application::NetworkRequirements::STRATEGIES.key?(route.network) }
      .map { |route| "#{route.network.inspect} on line #{route.line_number}" }

    expect(unknown).to be_empty
  end

  it 'keeps every route on the two app-layer authorization tokens' do
    # The #4332 edit rewrote 15 route lines. Nothing about a network annotation
    # may weaken the authorization that runs beneath it (design §9.2 invariant 1).
    lines = File.readlines(ROUTES_FILE, encoding: 'UTF-8').select { |line| line =~ /\A(GET|POST|PUT|PATCH|DELETE)\s/ }
    missing = lines.reject { |line| line.include?('auth=sessionauth') && line.include?('role=colonel') }

    expect(missing).to be_empty
  end
end
