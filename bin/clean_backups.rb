#!/usr/bin/ruby

require 'time'

# Config component for s3cmd (we need to create a new bucket)
BUCKET='solutious-onetime'
S3CMD='/usr/bin/s3cmd -c /root/.s3cfg --no-progress'
TESTMODE=false
NOW=TESTMODE ? Time.parse('2012-01-06 09:21 UTC').utc : Time.now.utc
THRESHOLD=NOW - 3600*3.5  # 3.5 hours ago
HOSTNAME=`/bin/hostname`.chomp.gsub(/[^0-9a-z\.\-\_]/i, '')

## DO NOT MODIFY BELOW THIS LINE (UNLESS YOU'RE A COOL WEIGHT-LIFTER)
require 'syslog'
SYSLOG = Syslog.open('ots-backup')
def log msg
  TESTMODE ? STDERR.puts(msg) : SYSLOG.info(msg)
end
def run
  cmd = "#{S3CMD} ls s3://#{BUCKET}/#{HOSTNAME}/"
  log NOW
  log "Running #{cmd}" 
  log "THIS IS TESTMODE. FILES WILL NOT BE DELETED." if TESTMODE
  all_backups = file_list
  stale_backups = all_backups.select { |info|
    stamp = Time.parse("#{info[0]} UTC")
    log '%s is old: %s (%s)' % [info[2], stamp.to_i < THRESHOLD.to_i, stamp]
    (stamp.to_i < THRESHOLD.to_i)
  }
  log "%d backups, %d stale" % [all_backups.size, stale_backups.size]
  deleted_count = 0
  stale_backups.each do |info|
    date, size, name = *info
    cmd = "#{S3CMD} del #{name}"
    log cmd
    `#{cmd}` && (deleted_count+=1) unless TESTMODE
  end
  msg = "Deleted %d backups" % deleted_count
  STDERR.tty? ? STDERR.puts(msg) : log(msg)
end
def file_list
  lines = if TESTMODE 
   %q{
2012-01-01 04:01    529451   s3://BUCKET/HOSTNAME/FILANAME-2012-01-22-04:01:01.bz2
2012-01-01 05:01    525428   s3://BUCKET/HOSTNAME/FILANAME-2012-01-22-05:01:01.bz2
2012-01-01 06:01    527257   s3://BUCKET/HOSTNAME/FILANAME-2012-01-22-06:01:01.bz2
2012-01-01 07:01    528084   s3://BUCKET/HOSTNAME/FILANAME-2012-01-22-07:01:01.bz2
2012-01-02 08:01    528088   s3://BUCKET/HOSTNAME/FILANAME-2012-01-22-08:01:02.bz2
2012-01-02 09:01    526939   s3://BUCKET/HOSTNAME/FILANAME-2012-01-22-09:01:01.bz2
2012-01-02 10:01    525594   s3://BUCKET/HOSTNAME/FILANAME-2012-01-06-00:01:01.bz2
2012-01-06 05:01    526257   s3://BUCKET/HOSTNAME/FILANAME-2012-01-06-01:01:01.bz2
2012-01-06 05:31    524568   s3://BUCKET/HOSTNAME/FILANAME-2012-01-06-02:01:01.bz2
2012-01-06 06:01    522502   s3://BUCKET/HOSTNAME/FILANAME-2012-01-06-03:01:02.bz2
2012-01-06 06:31    524214   s3://BUCKET/HOSTNAME/FILANAME-2012-01-06-04:01:01.bz2
2012-01-06 07:01    520998   s3://BUCKET/HOSTNAME/FILANAME-2012-01-06-05:01:01.bz2
2012-01-06 07:31    521343   s3://BUCKET/HOSTNAME/FILANAME-2012-01-06-06:01:01.bz2
2012-01-06 08:01    512873   s3://BUCKET/HOSTNAME/FILANAME-2012-01-06-07:01:01.bz2
2012-01-06 08:31    509614   s3://BUCKET/HOSTNAME/FILANAME-2012-01-06-08:01:01.bz2
2012-01-06 09:01    507133   s3://BUCKET/HOSTNAME/FILANAME-2012-01-06-09:01:01.bz2
}
  else
    `#{cmd}`
  end
  # Returns an array of arrays: [DATETIME, SIZE, FILEPATH]
  lines = lines.split($/).collect{|l| next if l.empty?; l.split(/\s\s+/); }.compact
end
begin
  run
rescue => ex
  log ex.message
  STDERR.puts ex.backtrace
end


