# apps/api/v2/logic/domains.rb

require 'public_suffix'

require 'onetime/cluster'

require_relative 'base'
require_relative 'domains/add_domain'
require_relative 'domains/remove_domain'
require_relative 'domains/list_domains'
require_relative 'domains/get_domain'
require_relative 'domains/verify_domain'
require_relative 'domains/get_image'
require_relative 'domains/get_domain_brand'
require_relative 'domains/update_domain_brand'
require_relative 'domains/get_domain_image'
require_relative 'domains/update_domain_image'
require_relative 'domains/remove_domain_image'

module V2::Logic
  module Domains
    # This file serves as a namespace and requires all domain-related files
  end
end
