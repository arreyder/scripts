#!/usr/bin/perl
use strict;
use warnings;

system("clear");
my $ppid = `sudo -u cassandra jps -lv | awk '/CassandraDaemon/ {print \$1}'`;
chomp $ppid;

while(1) {
  my %h;
  my @jstack = `sudo -u cassandra jstack $ppid`;
  my $cmd = "top -d0.1 -n1 -b -u cassandra -H | awk '/cassandr/ {print \$1,\$9}'";
  my @threads = `$cmd`;
  foreach (@threads) {
    chomp;
    (my $k,my $v) = split;
    $h{$k}=$v;
  }

  my @keys = sort {
    $h{$b} <=> $h{$a}
    or
    "\L$a" cmp "\L$b"
  } keys %h;

  my @highest = @keys[0..30];
  system("clear");
  foreach my $k (@highest) {
    my $hex = sprintf("0x%x", $k);
    foreach (@jstack) {
      chomp;
      print "\%CPU:$h{$k}, PID:$k THREAD:$_\n" if ($_  =~ m/$hex/);
    }
  }
  sleep 10;
}
