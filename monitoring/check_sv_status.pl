#!/usr/bin/perl
my $uptime;
my $service = $ARGV[0];
my $status = `sv status $service`;
if ($status =~ /(\d+)s;/) {
  $uptime = $1;
}
else {
  print "UNKNOWN: Bad sv status: $status\n";
  exit 3;
}

if ($uptime > 300) {
  print "OK: We've been running at least 5 minutes: $uptime seconds.\n";
  exit 0;
}
elsif ($uptime < 300) {
  print "CRITICAL: $service has been running less than 5 minutes this interval: $uptime seconds.\n";
  exit 2;
}
