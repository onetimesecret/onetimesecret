#!/usr/bin/ruby

# Config component for s3cmd (we need to create a new bucket)
KEEPERS=8
BUCKET='solutious-onetime'
S3CMD='/usr/bin/s3cmd'
TESTMODE=true
HOSTNAME=`hostname`.chomp

## DO NOT MODIFY BELOW THIS LINE (UNLESS YOU'RE A COOL WEIGHT-LIFTER)
require 'syslog'
SYSLOG = Syslog.open('onetime-backups')
def log msg
  TESTMODE ? STDERR.puts(msg) : SYSLOG.info(msg)
end
def run
  all_backups = TESTMODE ? File.readlines(DATA) : `#{S3CMD} ls s3://#{BUCKET}/#{HOSTNAME}`.split($/)
  stale_backups = all_backups[0..-(KEEPERS+1)] # should be 1 or 2 stale backups every time
  log "%d backups, %d stale" % [all_backups.size, stale_backups.size]
  stale_backups.each do |line|
    next unless line.match(/^\d/)
    date, time, size, name = *line.chomp.split(/\s+/)
    cmd = "#{S3CMD} del #{name}"
    TESTMODE ? log(cmd) : `#{cmd}`
  end
end

begin
  run
rescue => ex
  log ex.message
  STDERR.puts ex.backtrace
end

__END__
# Output from s3cmd is expected to look like this:
2011-12-22 04:01    529451   s3://BUCKET/HOSTNAME/FILANAME-2011-12-22-04:01:01.bz2
2011-12-22 05:01    525428   s3://BUCKET/HOSTNAME/FILANAME-2011-12-22-05:01:01.bz2
2011-12-22 06:01    527257   s3://BUCKET/HOSTNAME/FILANAME-2011-12-22-06:01:01.bz2
2011-12-22 07:01    528084   s3://BUCKET/HOSTNAME/FILANAME-2011-12-22-07:01:01.bz2
2011-12-22 08:01    528088   s3://BUCKET/HOSTNAME/FILANAME-2011-12-22-08:01:02.bz2
2011-12-22 09:01    526939   s3://BUCKET/HOSTNAME/FILANAME-2011-12-22-09:01:01.bz2
2011-12-22 10:01    525594   s3://BUCKET/HOSTNAME/FILANAME-2011-12-22-10:01:01.bz2
2011-12-22 11:01    526257   s3://BUCKET/HOSTNAME/FILANAME-2011-12-22-11:01:01.bz2
2011-12-22 12:01    524568   s3://BUCKET/HOSTNAME/FILANAME-2011-12-22-12:01:01.bz2
2011-12-22 13:01    522502   s3://BUCKET/HOSTNAME/FILANAME-2011-12-22-13:01:02.bz2
2011-12-22 14:01    524214   s3://BUCKET/HOSTNAME/FILANAME-2011-12-22-14:01:01.bz2
2011-12-22 15:01    520998   s3://BUCKET/HOSTNAME/FILANAME-2011-12-22-15:01:01.bz2
2011-12-22 16:01    521343   s3://BUCKET/HOSTNAME/FILANAME-2011-12-22-16:01:01.bz2
2011-12-22 17:01    512873   s3://BUCKET/HOSTNAME/FILANAME-2011-12-22-17:01:01.bz2
2011-12-22 18:01    509614   s3://BUCKET/HOSTNAME/FILANAME-2011-12-22-18:01:01.bz2
2011-12-22 19:01    507133   s3://BUCKET/HOSTNAME/FILANAME-2011-12-22-19:01:01.bz2
