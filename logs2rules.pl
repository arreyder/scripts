#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;
use Net::Subnet;
use Socket6;

my $is_godaddy = subnet_matcher qw(
  188.121.32.0/19 198.71.128.0/17 37.148.200.0/21 46.252.192.0/20 50.62.0.0/15 63.241.136.0/24 64.202.160.0/19 68.178.128.0/17 72.167.0.0/16 97.74.0.0/16 103.1.172.0/22 118.139.160.0/19 160.153.0.0/16 173.201.0.0/16 182.50.128.0/19 184.168.0.0/16 203.124.96.0/19 208.109.0.0/16 216.69.128.0/18 166.62.0.0/17 185.7.248.0/22 192.169.128.0/17 198.12.128.0/17 192.186.192.0/18 23.229.128.0/17 107.180.0.0/17 64.202.162.0/24 64.202.166.0/24 64.202.167.0/24 64.202.165.0/24 64.202.164.0/24 64.202.168.0/21 206.16.40.0/21 64.202.163.0/24 64.202.173.0/24 64.202.174.0/24 64.202.161.0/24 64.202.175.0/24 64.202.168.0/24 64.202.169.0/24 64.202.160.0/24 64.202.170.0/24 64.202.171.0/24 64.202.172.0/24 64.202.160.0/20 64.202.167.0/21 63.241.136.0/24 64.202.160.0/19 216.69.128.0/18 68.178.128.0/17 208.109.0.0/17 208.109.0.0/16 66.210.39.0/24 216.138.70.0/23 208.109.0.0/17 208.109.14.0/24 208.109.78.0/24 216.69.128.0/18 208.109.0.0/16 68.178.128.0/17 64.202.160.0/19 63.241.136.0/24 127.0.0.0/8 10.0.0.0/8 172.0.0.0/8 192.168.0.0/16);

my $netstat = `netstat -lnutp`;
my %listeners;

for (split /^/, $netstat) {
  next unless ($_ =~ /LISTEN/);
  my @matches = $_ =~ /(?:\d+|\d+\.\d+\.\d+\.\d+)(?:\:|\/)(\w+|\d+)/g;
  my %hash = @matches;
  @listeners{keys %hash} = values %hash;
}

print Dumper(\%listeners);

while (<>) {
  next unless ($_ =~ /New Connection/);
  my @matches = $_ =~ /(IN|DST|SRC|DST|PROTO|SPT|DPT)=(\d+|\d+\.\d+\.\d+\.\d+|TCP|UDP|ICMP|lo|bond0|eth0)\s+/g;
  my %hash = @matches;
  next unless (exists $hash{'DPT'});
  my $key = $hash{'DPT'};
  if (exists $listeners{$key}) {
    if (exists $hash{'SRC'}) {
      if ($is_godaddy->($hash{'SRC'})) {
        print "-A INPUT -m state --state NEW -p tcp -s $hash{'SRC'} --dport $key -j ACCEPT\n";
      }
      else {
        print $hash{'SRC'} . " was not a godaddy address, connected on port:" . $hash{'DPT'} . "\n";
      }
    }
    else {
      print "SRC not defined for $_";
    }
  }
}
