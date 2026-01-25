# apps/api/domains/logic/domains.rb
#
# frozen_string_literal: true

require 'public_suffix'

require 'onetime/domain_validation/strategy'

require_relative 'base'

module DomainsAPI
  module Logic
    module Domains
      # This file serves as a namespace and requires all domain-related files
    end
  end
end

require_relative 'domains/add_domain'
require_relative 'domains/remove_domain'
require_relative 'domains/list_domains'
require_relative 'domains/get_domain'
require_relative 'domains/get_dns_widget_token'
require_relative 'domains/verify_domain'
require_relative 'domains/get_image'
require_relative 'domains/get_domain_brand'
require_relative 'domains/update_domain_brand'
require_relative 'domains/get_domain_image'
require_relative 'domains/update_domain_image'
require_relative 'domains/remove_domain_image'
