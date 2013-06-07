#!/usr/bin/perl
# get_asa_stats.pl <community_string> <target_ip> <target_name_used_in_metric_path> <carbon_server> <carbon_port>
# needs cisco mibs installed in default mib dir.

use strict;
use warnings;
use IO::Socket;

my $cs = $ARGV[0];
my $target = $ARGV[1];
my $target_name = $ARGV[2];
my $carbon_server = $ARGV[3];
my $carbon_port = $ARGV[4];

my $cmd_a= "snmpwalk -Oq -v2c -c $cs";
my $cmd_s = "snmpwalk -OU -Oq -v2c -c $cs";

my @arrays = ("IF-MIB::ifInErrors",
              "IF-MIB::ifHCOutOctets",
              "IF-MIB::ifHCInOctets",
              "IF-MIB::ifHCOutUcastPkts",
              "IF-MIB::ifHCInUcastPkts",
              "CISCO-PROCESS-MIB::cpmCPUTotal5sec",
              "CISCO-PROCESS-MIB::cpmCPUTotal1min",
              "CISCO-PROCESS-MIB::cpmCPUTotal5min");

my @scalars = ("CISCO-FIREWALL-MIB::cfwConnectionStatValue.protoIp.currentInUse",
               "CISCO-FIREWALL-MIB::cfwConnectionStatValue.protoIp.currentInUse",
               "CISCO-UNIFIED-FIREWALL-MIB::cufwConnGlobalConnSetupRate1.0",
               "CISCO-UNIFIED-FIREWALL-MIB::cufwConnGlobalConnSetupRate5.0");

my $sock = IO::Socket::INET->new(
  PeerAddr => $carbon_server,
  PeerPort => $carbon_port,
  Proto    => 'tcp'
) or die "ERROR in Socket Creation : $!\n";

my $all_data; 

foreach my $oid (@arrays) {
  ($all_data) .= &get_snmp_array($oid);
}

foreach my $oid (@scalars) {
  ($all_data) .= &get_snmp_scalar($oid);
}

print $all_data;
$sock->send("$all_data");


sub get_snmp_array {
  my $o = shift;
  my @d1 = split(/^/,`$cmd_a $target $o`);
  get_instances(@d1);
}

sub get_snmp_scalar {
  my $o = shift;
  my $ds;
  my $time=time;
  my $d1 = `$cmd_s $target $o`;
  (my $instance, my $value) = split(/\s/,$d1);
    unless ($value eq "0") {
      $ds .= "$target_name.network.$instance $value $time\n";
  }
  return $ds;
}

sub get_instances {
  my $ds;
  my $time=time;
  foreach my $i (@_) {
    (my $instance, my $value) = split(/\s/,$i);
    unless ($value eq "0") {
      $ds .= "$target_name.network.$instance $value $time\n";
    }
  }
  return $ds;
}
