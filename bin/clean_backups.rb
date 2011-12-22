#!/usr/bin/ruby

# Config component for s3cmd (we need to create a new bucket)
KEEPERS=8
BUCKET='solutious-onetime'
S3CMD='/usr/bin/s3cmd'
TESTMODE=false
HOSTNAME=`hostname`.chomp.gsub(/[^0-9a-z\.\-\_]/i, '')

## DO NOT MODIFY BELOW THIS LINE (UNLESS YOU'RE A COOL WEIGHT-LIFTER)
require 'syslog'
SYSLOG = Syslog.open('onetime-backups')
def log msg
  TESTMODE ? STDERR.puts(msg) : SYSLOG.info(msg)
end
def run
  cmd = "#{S3CMD} ls s3://#{BUCKET}/#{HOSTNAME}/"
  log "Running #{cmd}" 
  log "THIS IS TESTMODE. FILES WILL NOT BE DELETED." if TESTMODE
  all_backups = TESTMODE ? File.readlines(DATA) : `#{cmd}`.split($/)
  stale_backups = all_backups[0..-(KEEPERS+1)] # should be 1 or 2 stale backups every time
  log "%d backups, %d stale" % [all_backups.size, stale_backups.size]
  deleted_count = 0
  stale_backups.each do |line|
    next unless line.match(/^\d/)
    date, time, size, name = *line.chomp.split(/\s+/)
    cmd = "#{S3CMD} del #{name}"
    log cmd
    `#{cmd}` && (deleted_count+=1) unless TESTMODE
  end
  msg = "Deleted %d backups" % deleted_count
  STDERR.tty? ? STDERR.puts(msg) : log(msg)
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
