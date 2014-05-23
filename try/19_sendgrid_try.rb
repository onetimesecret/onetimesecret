require 'onetime'
SendGrid.debug_output $stdout

## Can create SendGrid instance
@sg = SendGrid.new :user, :key, :from_email, :from_name
[@sg.class, @sg.api_user, @sg.api_key, @sg.from, @sg.fromname]
##=> [SendGrid, :user, :key, :from_email, :from_name]

## Has global emailer
OT.load!
[OT.emailer.class, OT.emailer.from, OT.emailer.fromname]
##=> [SendGrid, 'tryouts@onetimesecret.com', 'Tryouts']

## Can send email
ret = OT.emailer.send 'tryouts@onetimesecret.com', "tryouts #{OT.now}", "Hello you!"
[ret.class, ret.code]
##=> [HTTParty::Response, 200]
