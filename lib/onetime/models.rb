# lib/onetime/models.rb
#
# frozen_string_literal: true

require_relative 'models/features'
require_relative 'models/secret'
require_relative 'models/organization'
require_relative 'models/organization_membership'
require_relative 'models/customer'
require_relative 'models/custom_domain'
# Receipt must be loaded AFTER Organization and CustomDomain because
# Receipt.participates_in declarations reference those classes
require_relative 'models/receipt'
require_relative 'models/feedback'
require_relative 'models/colonel_audit_event'
require_relative 'models/daily_metric'
require_relative 'models/email_suppression'
require_relative 'models/session_metadata'
require_relative 'models/sso_link_challenge'
require_relative 'models/sso_link_verification'
require_relative 'models/impersonation_grant'

# CustomDomain sibling configs — loaded after CustomDomain so the
# nested-class reopens (`class CustomDomain; class ApiConfig; ...`)
# resolve against the defined parent. Kept alphabetical.
require_relative 'models/custom_domain/api_config'
require_relative 'models/custom_domain/brand_settings'
require_relative 'models/custom_domain/homepage_config'
require_relative 'models/custom_domain/incoming_config'
require_relative 'models/custom_domain/mailer_config'
require_relative 'models/custom_domain/signin_config'
require_relative 'models/custom_domain/signup_config'
require_relative 'models/custom_domain/sso_config'

# Catalog of the seven per-domain config kinds (colonel config endpoints).
# Requires the config models above, so it loads after them.
require_relative 'models/custom_domain/config_registry'

# Housekeeping chores - loaded after models so chore DSL is available.
# Sort for deterministic load order across platforms.
Dir.glob(File.join(__dir__, 'models', '*', 'chores', '*.rb')).sort.each do |chore_file|
  require chore_file
end
