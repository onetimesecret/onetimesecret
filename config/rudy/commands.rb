# ----------------------------------------------------------- COMMANDS --------
# The commands block defines shell commands that can be used in routines. The
# ones defined here are added to the default list defined by Rye::Cmd (Rudy 
# executes all SSH commands via Rye). 
#
# Usage: 
#
# allow COMMAND-NAME
# allow COMMAND-NAME, '/path/2/COMMAND'
# allow COMMAND-NAME, '/path/2/COMMAND', 'default argument', 'another arg'
#
commands do
  allow :yum, 'yum'
  allow :gem_install, 'gem', 'install', :V, '--no-rdoc', '--no-ri'
  allow :gem_sources, "gem", "sources"
  allow :gem_update, "gem", "update"
  allow :gem_uninstall, "gem", "uninstall", :V
  allow :update_rubygems
  allow :rake
  allow :thin, 'bundle', 'exec', 'thin', :P, '/var/run/thin/thin.pid', :l, '/var/log/thin/thin.log', :d
  allow :bundle
  allow :redis_dump, 'redis-dump'
  allow :redis_report, 'redis-report'
  allow :rm
  allow :kill
  allow :tail
  allow :ruby, 'ruby'
  allow :ulimit
  allow :sysinfo
  allow :sysinfo2
  allow :s3cmd, "/usr/local/s3cmd/s3cmd"
  allow :nginx, 'service', 'nginx' 
  allow :wget, 'wget', :q
  allow :redis, 'service', 'redis'
  allow :thin_instances, '1' 
  allow :config_env do
    case $global.environment.to_s
    when 'dev' then 'dev'
    when 'proto' then 'status' 
    when 'status' then 'status' 
    when 'prod' then 'prod'
    else
      raise "Unknown thin environment (#{$global.environment})"
    end
  end
  allow :redis_version do
    '2.0.0-rc4'
  end
end

