#!/usr/bin/perl
use File::Tail;
use JSON;
use strict;
use warnings;
use utf8;
use IO::Socket;
use Socket qw(IPPROTO_TCP SOL_SOCKET PF_INET SOCK_STREAM SO_KEEPALIVE inet_aton sockaddr_in);
use Statistics::Descriptive;
use String::Escape qw( printable unprintable );
use autodie;

sleep 30;

$| = 1;
my ($carbon_server, $carbon_port) = split(":",$ARGV[0]);
my $chef_env = $ARGV[1] ||  die "Please provide chef environment.\n\n";
my $access_log = $ARGV[2] ||  die "Please provide access log path.\n\n";
my $file=File::Tail->new(name=>$access_log, maxinterval=>10);
my $hostname = `hostname -f`;
my %goodmethods = ('GET' => 1, 'PUT' => 1, 'POST' => 1, 'HEAD' => 1, 'DELETE' => 1,);
my $INTERVAL = 60; # Sample interval.
my %count;
my %durations;

$SIG{ALRM} = \&emit;
alarm($INTERVAL);
chomp $hostname;
chomp $chef_env;

$hostname =~ s/\./-/g;
$hostname =~ s/\.$//g;

my $prefix = $chef_env . "." . $hostname . ".system";
while (defined(my $line=$file->read)) {
  my %data;
  eval {
    %data = %{decode_json($line)};
  };
  if ($@) {
    print "Invalid JSON: $line\n";
    my $clean_line = unprintable($line);
    eval {
      %data = %{decode_json($clean_line)};
    };
    if ($@) {
      print "Still Invalid JSON: $clean_line\n";
      next;
    }
    else {
      print "Fixed JSON: $clean_line\n";
    }
  }
  my ($backend,$vhost,$date,$remote,$fr,$ua,$txn,$request,$rc,$check_name,$remote_user);
  if (defined ($rc = $data{'status'})) {
    my $d = $data{'upstream_response_time'};
    my $b = $data{'upstream_addr'};
    $b =~ s/http:\/\///;
    $b =~ s/\./-/g;
    $b =~ s/:/_/;
    my ($rc_key, $dr_key);
    $request = $data{'request'};
    my($method,$path,$protocol) = split(/\s/,$request);
    if ($path eq "/") {
      $rc_key = "root";
    }
    else {
      $path =~ s/^\///;
      $path =~ s/\/$//;
      my @parts = split(/[\/|\?]/,$path);
      $rc_key = $parts[0];
      if (@parts > 1) {
        if ($parts[1] =~ /v\d+/) {
          $dr_key = $rc_key . "." . $parts[1] . "," . $b;
          $rc_key .= "." . $parts[1] . "." . $rc;
        }
        else {
          $dr_key = $rc_key . "," . $b;
          $rc_key .= "." . $rc;
        }
      }
      else {
        $dr_key = $rc_key . "," . $b;
        $rc_key .= "." . $rc;
      }
    }
    unless($d eq "-") {
     # deal with the split duration value in the 499 status
     if ($d =~ /(\d+\.\d+),/) {
      $d=$1;
     }
     push @{$durations{$dr_key}}, $d;
    }
    if ($count{$rc_key}) {
      $count{$rc_key}++;
    }
    else {
     $count{$rc_key} = 1;
    }
    if ($rc_key =~ /50\d/) {
      print "Got a match: $rc_key ";
      unless (defined ($remote = $data{'remote_addr'})) { $remote = "undefined" };
      unless (defined ($ua = $data{'user_agent'})) { $ua = "undefined" };
      print "with method: $method request: $request ";
      if (exists($goodmethods{$method})) {
        print "Alerting. Method: $method is in the goodmethods list\n";
        unless (defined ($date = $data{'time'})) { $date = "undefined" };
        unless (defined ($remote = $data{'remote_addr'})) { $remote = "undefined" };
        unless (defined ($fr = $data{'request'})) { $fr = "undefined" };
        unless (defined ($txn = $data{'http_x_api_id'})) { $txn = "undefined" };
        unless (defined ($backend = $data{'upstream_addr'})) { $backend = "undefined" };
        unless (defined ($remote_user = $data{'remote_user'})) { $remote_user = "undefined" };
        $check_name = "check_status_code";
        my $json_status = qq({"client":{"name":"$hostname","address":"-"},"check":{"command":"$check_name","output":"CRIT Status:$rc $remote $remote_user $backend $fr $ua $date"}});
        print qq({"client":{"name":"$hostname","address":"-"},"check":{"command":"$check_name","output":"CRIT Status:$rc $date $remote $remote_user $backend $fr $ua $date"}}\n);
      }
      else {
        print "Not alerting. Method: $method is not in the goodmethods list\n";
      }
    }
  }
  else {
    print "status was not defined in $line\n";
  }
}

sub emit {
  alarm($INTERVAL);
  my $data_string;
  my $time = time;
  if (%count) {
    foreach my $key (keys(%count)) {
      my $rate = $count{$key} / $INTERVAL;
      $data_string .= "$prefix.nginx.rates.$key " . sprintf("%.3f",$rate) ." $time\n";
    }
    undef %count;
    foreach my $key ( keys %durations )  {
      my $stat = Statistics::Descriptive::Full->new();
      $stat->add_data(\@{$durations{$key}});
      my $mean = $stat->mean();
      my($path,$be)=split(/,/,$key);
      $data_string .= "$prefix.nginx.duration.$path.$be.mean " . sprintf("%.3f",$mean) . " $time\n";
    }
    undef %durations;
    my $sin = sockaddr_in($carbon_port, inet_aton($carbon_server));
    socket(my $sock, PF_INET, SOCK_STREAM, getprotobyname('tcp')) or die "socket: $!";
    setsockopt($sock, SOL_SOCKET, SO_KEEPALIVE, 1);
    connect($sock, $sin) or die "connect: $!";
    print "\n" . $data_string;
    unless (print $sock $data_string) {
      die "Failed to send data: $!\n";
    }
    close($sock);
  }
  else {
    print "No requests this interval.\n";
  }
  return;
}
