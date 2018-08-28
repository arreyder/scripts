#!/usr/bin/perl
#  The user this runs as under the collectd exec plugin must 
#  have sudo to run contrack.
#
#  Something like:
#
#      my_user ALL = NOPASSWD: /usr/sbin/conntrack
#
#  contrack must also be in the users path.  Example collectd config:
#
#     <Plugin exec>
#        Exec "my_user" "/usr/local/bin/conntrack_full.pl"
#     </Plugin>
#
#  Here's what we expect the output of the command we parse to look
#  like, any number of cpus should be handled properly.
#
#     my_user@bananapi: sudo conntrack -S
#       cpu=0           found=0 invalid=131 ignore=443267 insert=0 insert_failed=0 drop=0 early_drop=0 error=0 search_restart=2832                                                                                                
#       cpu=1           found=0 invalid=224 ignore=359074 insert=0 insert_failed=0 drop=0 early_drop=0 error=0 search_restart=5232 
#

use strict;
use warnings;

my $plugin_name = "conntrack_full";
my $hostname = $ENV{COLLECTD_HOSTNAME};
my $interval = $ENV{COLLECTD_INTERVAL};

$hostname = defined $hostname ? $hostname : "localhost";
$interval = defined $interval ? $interval : 20;

die "Missing conntrack tool, or not in path.\n" unless ( `which conntrack` );

while () {
  my $time_left;
  my $start_run = time;
  my $next_run = $start_run + $interval;
  &get_conntrack($start_run);
  while (($time_left = ($next_run - time)) > 0 ) {
    sleep $time_left;
  }
}
sub get_conntrack {
  my $conntrack=`sudo conntrack -S`;
  my (@keys, $data_string);
  my $time=shift;

  for (split /^/, $conntrack) {
    my $cpu_id;
    my @kvs = split /\s+/;
    foreach my $kv (@kvs) {
      (my $k,my $v) = split ("=",$kv);
      if ($k eq "cpu") {
        $cpu_id=$v;
        next;
      }
      printf ("PUTVAL %s/%s/counter-cpu%d_%s interval=%d %d:%d\n", $hostname, $plugin_name, $cpu_id, $k, $interval, $time, $v);
    }
  }
}
