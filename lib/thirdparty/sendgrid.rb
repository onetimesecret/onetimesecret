require 'httparty'
require 'pp'
 
# http://wiki.sendgrid.com/doku.php?id=web_api

class SendGrid
  include HTTParty
  #ssl_ca_file Stella::Client::SSL_CERT_PATH
  #debug_output $stdout
  base_uri 'https://sendgrid.com/api/'
  attr_accessor :api_user, :api_key, :from, :fromname, :bcc
  def initialize api_user, api_key, from, fromname=nil, bcc=nil
    @api_user, @api_key, @from, @fromname, @bcc = api_user, api_key, from, fromname, bcc
  end
  def send to, subject, text, category='ops'
    # NOTE: The heading setting below has no effect
    options = { :to => to, :subject => subject, :html => text,
                :api_user => api_user, :api_key => api_key, :from => from, :replyto => from,
                :fromname => fromname, 'x-smtpapi' => { :'category' => category, :machine => OT.sysinfo.hostname }.to_json }
    options[:bcc] = bcc unless bcc.to_s.empty?
    self.class.post("/mail.send.json", :body => options)
  end
end

# https://sendgrid.com/api/?
#   api_user=youremail@domain.com
#   api_key=secureSecret
#   to=destination@example.com
#   toname=Destination
#   subject=Example%20Subject
#   text=testingtextbody
#   from=info@domain.com