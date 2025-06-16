# etc/init.d/mail.rb


unless config['validation'].key?('default')
  abort 'No Validation config found'
end
