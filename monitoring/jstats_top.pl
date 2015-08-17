#!/usr/bin/perl
use strict;
use warnings;

my $num_args = $#ARGV + 1;
if ($num_args != 2) {
  print "\nUsage: jstat_top.pl <user the jvm runs as>  <process id as reported by jps>\n";
  exit;
}

my $user = $ARGV[0];
my $process_id = $ARGV[1];
$process_id = substr( $process_id, 0, 7 );

system("clear");
my $ppid = `sudo -u $user jps -lv | awk '/$process_id/ {print \$1}'`;
chomp $ppid;

while(1) {
  my %h;
  my @jstack = `sudo -u $user jstack $ppid`;
  my $cmd = "top -d0.1 -n1 -b -u $user -H | awk '/$process_id/ {print \$1,\$9}'";
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
