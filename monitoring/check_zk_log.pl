#!/usr/bin/perl
#passive check that creates a lock on the local zk server
use strict;
use warnings;
use Net::ZooKeeper qw(:node_flags :acls);

my $hostname = `hostname`;
chomp $hostname;
my $ts = time;
my $lock = "/nagios-$hostname-$ts";
my $config;
my $server="127.0.0.1:2181";

my $status;
my $zkh = Net::ZooKeeper->new($server);
unless ($zkh->create($lock, 'nagios_check', 'flags' => ZOO_EPHEMERAL, 'acl' => ZOO_OPEN_ACL_UNSAFE)) {
  $status = "$hostname,check_zk_lock,2,\"CRIT Unable to get a lock: $lock on server: $server $zkh->get_error() \"";
}
my $stat = $zkh->stat();
if ($zkh->exists($lock, 'stat' => $stat)) {
  $status = "$hostname,check_zk_lock,0,\"OK Successfully created lock: $lock on server: $server\"";
}
undef $zkh;
send_nsca($status);

sub send_nsca {
  my $check_output = @_;
  my @hosts = `grep scribe0 /etc/hosts | cut -f1 -d' '`;
  while (<@hosts>) {
    chomp;
    my $cmd_status = `echo @_ | /usr/sbin/send_nsca -H $_ -to 30 -c /etc/send_nsca.cfg -d , 2>&1`;
    if ( $? == -1 ) {
      print "send_nsca failed to $_ when sending status for check_zk_lock: $cmd_status\n";
    }
  }
}
