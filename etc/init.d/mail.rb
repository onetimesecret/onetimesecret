# etc/init.d/mail.rb


unless config['validation'].key?('defaults')
  abort 'No Validation config found'
end
