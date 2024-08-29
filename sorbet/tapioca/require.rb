# typed: true
# frozen_string_literal: true

# Add the lib directory to the $LOAD_PATH explicitly using a relative path
lib_path = File.expand_path('../../../lib', __FILE__)
$LOAD_PATH.unshift(lib_path)

# Debugging output to verify $LOAD_PATH
puts "Current $LOAD_PATH:"
puts $LOAD_PATH[0..2], '...'

require "bcrypt"
require "bundler/setup"
require "drydock"
require "encryptor"
require "erb"
require "familia"
require "familia/tools"
require "gibbler/mixins"
require "mail"
require "mustache"
require "net/http"
require "onetime"
require "onetime/app/api/base"  # Ensure this file exists
require "onetime/app/helpers"
require "onetime/app/web/account"
require "onetime/app/web/base"
require "onetime/app/web/info"
require "onetime/app/web/views"
require "onetime/app/web/views/helpers"
require "onetime/core_ext"
require "onetime/email"
require "onetime/logic"
require "onetime/models"
require "onetime/models/customer"
require "onetime/models/metadata"
require "onetime/models/secret"
require "onetime/models/session"
require "onetime/models/splittest"
require "onetime/models/subdomain"
require "securerandom"
require "sendgrid-ruby"
require "storable"
require "sysinfo"
require "syslog"
require "timeout"
require "truemail"
require "uri"
require "yaml"
