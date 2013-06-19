#!/usr/bin/perl
# grab some port stats from pmacct and shove it in graphite.
use strict;
use warnings;
use IO::Socket;

my $cmd = "/usr/local/bin/pmacct -c dst_port";
my $carbon_server = "10.4.86.69";
my $carbon_port = "2003";
my $hostname = `hostname`;
chomp $hostname;
$hostname =~ /(\w+)-?/;
my $dc = $1;
$hostname =~ /(?:\w+-){2}(\w+)-?/;
my $env = $1;
my $target = "$dc-maas-$env-active-asa";

my @ports = ("2888", "7000", "1465", "80", "443", "2181", "5666", "2003", "53", "5667", "9160", "1500", "8126");

while (1) {
  my $sock = IO::Socket::INET->new(
    PeerAddr => $carbon_server,
    PeerPort => $carbon_port,
    Proto    => 'tcp'
  ) or die "ERROR in Socket Creation : $!\n";

  my $all_data;

  foreach my $port (@ports) {
    ($all_data) .= &get_data($port,"packets","in");
    ($all_data) .= &get_data($port,"packets","out");
    ($all_data) .= &get_data($port,"bytes","in");
    ($all_data) .= &get_data($port,"bytes","out");
    print $all_data;
  }
  $sock->send("$all_data");
  sleep 60;
}

sub get_data {
  (my $p,my $t,my $d) = @_;
  my $time = time;
  my $c = "$cmd -N $p -n $t -p /tmp/pmacct_$d.pipe";
  my $data = `$c`;
  chomp $data;
  return "$target.network.$t.$p.$d $data $time\n";
}
