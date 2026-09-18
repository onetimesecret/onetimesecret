# spec/unit/onetime/domain_validation/address_resolver_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/domain_validation/address_resolver'

# Runs against the in-process loopback DNS server; nothing leaves the machine.
RSpec.describe Onetime::DomainValidation::AddressResolver do
  a     = Resolv::DNS::Resource::IN::A
  aaaa  = Resolv::DNS::Resource::IN::AAAA
  cname = Resolv::DNS::Resource::IN::CNAME
  rcode = Resolv::DNS::RCode

  include_context 'with a loopback DNS server'

  let(:hostname) { 'secrets.example.com' }

  def resolver_for(*started, timeout: 1, attempt_timeout: 0.2)
    described_class.new(
      nameservers: started.map { |server| ['127.0.0.1', server.port] },
      timeout: timeout,
      attempt_timeout: attempt_timeout,
    )
  end

  # Answers by question type: { A => [data, ...] or an rcode Integer or :silent }
  def start_family_server(by_type)
    start_server do |s, q, _|
      plan = by_type.fetch(q.question.first[1], [])
      case plan
      when :silent then nil
      when Integer then s.reply_to(q, rcode: plan)
      else s.reply_to(q, answers: plan.map { |data| [nil, data] })
      end
    end
  end

  it 'uses a shorter time budget than the TXT lookup' do
    resolver = described_class.new(nameservers: ['127.0.0.1'])

    expect([resolver.timeout, resolver.attempt_timeout]).to eq([3, 1])
  end

  describe '#lookup' do
    it 'returns IPv4 and IPv6 addresses from both families' do
      server = start_family_server(a => [a.new('93.184.216.34')], aaaa => [aaaa.new('2606:2800:220:1::1')])
      answer = resolver_for(server).lookup(hostname)

      expect(answer).to be_resolves
      expect(answer).to be_definitive
      expect(answer.addresses).to eq(['93.184.216.34', '2606:2800:220:1::1'])
      expect(server.questions).to eq([a, aaaa])
    end

    it 'queries the absolute name, without resolv.conf search suffixes' do
      server = start_family_server({})
      resolver_for(server).lookup(hostname)

      expect(server.queries.map(&:first).uniq).to eq([hostname])
    end

    it 'follows a CNAME chain and ignores records owned by another name' do
      target = Resolv::DNS::Name.create('edge.example.net.')
      other  = Resolv::DNS::Name.create('other.example.net.')
      server = start_server do |s, q, _|
        next s.reply_to(q) unless q.question.first[1] == a

        s.reply_to(q, answers: [[nil, cname.new(target)], [target, a.new('93.184.216.34')], [other, a.new('10.0.0.1')]])
      end

      expect(resolver_for(server).lookup(hostname).addresses).to eq(['93.184.216.34'])
    end

    # RFC 1034 does not fix the order of the answer section.
    it 'follows a CNAME chain when the address is listed before the CNAME' do
      target = Resolv::DNS::Name.create('edge.example.net.')
      server = start_server do |s, q, _|
        next s.reply_to(q, answers: [[nil, cname.new(target)]]) unless q.question.first[1] == a

        s.reply_to(q, answers: [[target, a.new('93.184.216.34')], [nil, cname.new(target)]])
      end

      expect(resolver_for(server).lookup(hostname).addresses).to eq(['93.184.216.34'])
    end

    it 'follows a multi-hop CNAME chain whose links are out of order' do
      hop1   = Resolv::DNS::Name.create('hop1.example.net.')
      hop2   = Resolv::DNS::Name.create('hop2.example.net.')
      server = start_server do |s, q, _|
        chain = [[hop1, cname.new(hop2)], [nil, cname.new(hop1)]]
        next s.reply_to(q, answers: chain) unless q.question.first[1] == aaaa

        s.reply_to(q, answers: [[hop2, aaaa.new('2606:2800:220:1::1')], *chain])
      end

      expect(resolver_for(server).lookup(hostname).addresses).to eq(['2606:2800:220:1::1'])
    end

    it 'does not read an answer section with nothing for the queried name as "no address"' do
      other  = Resolv::DNS::Name.create('other.example.net.')
      server = start_server { |s, q, _| s.reply_to(q, answers: [[other, a.new('93.184.216.34')]]) }

      expect { resolver_for(server, timeout: 0.6).lookup(hostname) }
        .to raise_error(described_class::NoReplyError)
    end

    it 'does not read a referral from a non-recursive nameserver as "no address"' do
      root   = Resolv::DNS::Name.create('.')
      ns     = Resolv::DNS::Resource::IN::NS.new(Resolv::DNS::Name.create('a.root-servers.net.'))
      server = start_server { |s, q, _| s.reply_to(q, ra: 0, authority: [[root, ns]]) }

      expect { resolver_for(server, timeout: 0.6).lookup(hostname) }
        .to raise_error(described_class::NoReplyError, /neither recursive nor authoritative/)
    end

    it 'reports NXDOMAIN as definitive without asking for the other family' do
      server = start_family_server(a => rcode::NXDomain)
      answer = resolver_for(server).lookup(hostname)

      expect(answer).to be_nxdomain
      expect(answer).to be_definitive
      expect(answer).not_to be_resolves
      expect(server.questions).to eq([a])
    end

    it 'reports NOERROR with no address records in either family as definitive' do
      server = start_family_server({})
      answer = resolver_for(server).lookup(hostname)

      expect(answer.rcode_name).to eq('NOERROR')
      expect(answer).to be_definitive
      expect(answer).not_to be_resolves
    end

    it 'resolves when one family has an address and the other fails' do
      server = start_family_server(a => [a.new('93.184.216.34')], aaaa => rcode::ServFail)
      answer = resolver_for(server).lookup(hostname)

      expect(answer).to be_resolves
      expect(answer).to be_definitive
      expect(answer.addresses).to eq(['93.184.216.34'])
    end

    it 'is not definitive when one family is empty and the other is SERVFAIL' do
      server = start_family_server(aaaa => rcode::ServFail)
      answer = resolver_for(server).lookup(hostname)

      expect(answer.rcode_name).to eq('SERVFAIL')
      expect(answer).not_to be_definitive
      expect(answer).not_to be_resolves
    end

    it 'is not definitive on SERVFAIL for both families' do
      server = start_family_server(a => rcode::ServFail, aaaa => rcode::ServFail)

      expect(resolver_for(server).lookup(hostname)).not_to be_definitive
    end

    it 'raises when one family is empty and the other never replies' do
      server = start_family_server(aaaa => :silent)

      expect { resolver_for(server, timeout: 0.6).lookup(hostname) }
        .to raise_error(described_class::NoReplyError, /Incomplete DNS reply/)
    end

    it 'raises when nothing replies, within the shared budget' do
      server  = start_family_server(a => :silent, aaaa => :silent)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect { resolver_for(server, timeout: 0.5).lookup(hostname) }
        .to raise_error(described_class::NoReplyError, /No DNS reply/)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1.5
    end

    it 'rejects a blank hostname' do
      expect { resolver_for.lookup(' ') }.to raise_error(ArgumentError, /requires a hostname/)
    end
  end

  describe '#close' do
    it 'leaves no socket open after a lookup' do
      server   = start_family_server(a => [a.new('93.184.216.34')])
      resolver = resolver_for(server)
      resolver.lookup(hostname)

      expect(resolver.instance_variable_get(:@sockets)).to be_empty
      expect(resolver.close).to be_nil
    end
  end
end
