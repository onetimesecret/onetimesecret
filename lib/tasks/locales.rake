# lib/onetime/tasks/locales.rake
#
# frozen_string_literal: true

# bundle exec rake locales:precompile
# bundle exec rake locales:clean

require 'onetime'

namespace :locales do
  desc 'Generate merged locale cache files for OCI builds'
  task :precompile do
    $LOAD_PATH.unshift(File.expand_path('../..', __dir__))
    require 'onetime'

    OT.boot!(:cli, false)
    Onetime::Initializers::LoadLocales.precompile
  end

  desc 'Clean up all merged locale cache files'
  task :clean do
    $LOAD_PATH.unshift(File.expand_path('../..', __dir__))
    require 'onetime'

    Onetime::Initializers::LoadLocales.cleanup_caches
  end
end
