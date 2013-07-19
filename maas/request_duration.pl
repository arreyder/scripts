#!/usr/bin/perl
# graphs request time on "problem" accounts from the gelfef httpd logs
# find /var/log/gelf/*api* -name '*current' | xargs tail -q -F | ./request_duration.pl

use JSON;
use strict;
use warnings;
use utf8;
use IO::Socket;

binmode STDOUT, ":utf8";
my ($json, %hash);

my $INTERVAL = 3600; # Sample interval.
my $hostname = `hostname`;
chomp $hostname;
my $carbon_server = "10.13.237.104";
my $carbon_port = "2003";

my %count;
$SIG{ALRM} = \&do_average;
alarm($INTERVAL);

while (<>) {
  my %data = %{decode_json($_)};
  my ($duration, $message, $request, $tid);
  if (defined ($duration = $data{'_request-duration'})) {
    $request = $data{'_fl-request'};
    if ($request =~ m/\w+\s\/v\d+\.\d+\/(\d+\/\w+)\//) {
      $tid = $1;
      push(@{$hash{$tid}}, $duration);
    }
  }
}

sub do_average {
  alarm($INTERVAL);
  my $data_string;
  my $time = time;
  foreach my $tenant (keys %hash) {
    my $sum;
    my $points = @{$hash{$tenant}};
    foreach (@{$hash{$tenant}}) {
      $sum += $_;
    }
    my $avg = $sum / $points;
    if ($avg > 10000000) {
      #print "$tenant points: $points avg: $avg\n";
      $tenant =~ s/\//\./g;
      $avg = $avg / 1000000;
      $data_string .= "$hostname.system.accounts.avg_duration.$tenant " . sprintf("%.3f",$avg) . " $time\n";
    }
  }
  my $sock = IO::Socket::INET->new( PeerAddr => $carbon_server, PeerPort => $carbon_port, Proto => 'tcp') or die "ERROR in Socket Creation : $!\n";
  print $data_string;
  $sock->send($data_string);
  undef %hash;
}
