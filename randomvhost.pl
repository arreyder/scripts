#!/usr/bin/perl
use strict;
use warnings;
use threads;
use threads::shared;
use Furl;
use Perl::Unsafe::Signals;

my $quit : shared = 0;
#my %count;

sub ctrlc { $quit = 1; }

$SIG{INT} = \&ctrlc;

my $start_time = time;
my $numthreads = $ARGV[0];
print "num threads: $numthreads, pid: $$\n";
print "Hit ctrl-c to end\n";

sub fetch {
  my $tid = shift;
#  my $furl = Furl::HTTP->new(agent => 'Furl/0.31',timeout => 10, Host => "$string.arreyder.com");
  my $start_time = time;
  my %count;
  while(!$quit) {
    my @chars = ("A".."Z", "a".."z");
    my $string;
    $string .= $chars[rand @chars] for 1..8;
    my $furl = Furl::HTTP->new(agent => 'Furl/0.31',timeout => 10, Host => "$string.arreyder.com");
    my $url = "https://$string.arreyder.com/";
    chomp $url;
#   print "start $tid: $url\n";
    my ($ver, $code, $msg, $headers, $body) = $furl->get($url);
    my $size = length $body;
    if ($count{$code}) {
      $count{$code}++ }
    else {
      $count{$code} = 1;
    }
    print "code: $code, finish $tid: $url, $size bytes, message:$msg\r"; # unless ($code eq "404" || $code eq "200");
  }
  print "\n\n\nStats per thread\n";
  &emit($start_time,$tid,\%count);
}

sub emit {
  my $start_time = $_[0];
  my $tid = $_[1];
  my %count = %{$_[2]};
  my $end_time = time;
  my $elapsed_time = $end_time - $start_time;
  my $data_string;
  if (%count) {
    foreach my $key (keys(%count)) {
      my $rate = $count{$key} / $elapsed_time;
      $data_string .= "Thread:$tid Status:$key Rate:" . sprintf("%.3f",$rate) ." Total:" . $count{$key} . " Duration:$elapsed_time seconds\n";
    }
    print "\n" . $data_string;
  }
  return;
}

my @threads;

for(my $i = 0; $i < $numthreads; ++$i) {
  my $thread = threads->create(\&fetch,$i);
  push(@threads, $thread);
}

UNSAFE_SIGNALS {
  foreach (@threads) {
    $_->join();
  }
}
