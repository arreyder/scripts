#!/usr/bin/perl
# this tries to look up the checks that are mentioned in the cep logs as not reporting from all mzs
use JSON;
use strict;
use warnings;
use utf8;
use Term::ANSIColor qw(:constants);

my $api_server = "ord1-maas-prod-api0";
my $data;
my %ed;
my $managed_token = $ARGV[0];

binmode STDOUT, ":utf8";
my $json;

while (<>) {
  next unless($_ =~ /MetricHelper/);
  my %data = %{decode_json($_)};
  my $host = $data{'host'};
  my $f = $data{'facility'};
  my $message = $data{'full_message'};
  print "$message\n";
  next unless ($message =~ /\s(\w+):(\w+):(\w+):(\w+)/);
  my $ac=$1;
  my $en=$2;
  my $check=$3;
  my $external_id;
  if (!(defined $ed{$1})) {
    $external_id = get_ed($1);
    print "-";
  }
  else {
    print "+";
    $external_id = $ed{$1};
  }
  print "acct:$1 en:$2 ch:$3 al:$4 ed:$external_id\n";
  if ($external_id =~ /failed.+/) {
    print "\nFailed to get external_id for:\n\t$_\n\t$external_id\n";
    sleep 5;
    next;
  }
  my $response=`curl -s -k -XGET -H 'X-Managed-Token: $managed_token' https://$api_server/v1.0/$external_id/entities/$en/checks/$check\n`;
  if ($response =~ m/code":\s(\d{3})/) {
    my $status=$1;
    chomp $status;
    print "\n\t$external_id entity: $en account: $ac check: $check status: $status response:\n $response\n\t$_";
      sleep 5;
  }
  else {
    if ($response =~ m/"disabled": true/) {
      print YELLOW, "\nCheck is DISABLED:\n\texternal: $external_id entity: $en account: $ac check: $check response:\n $response\n\t$_", RESET;
      sleep 5;
    }
    else {
     $response =~ s/\R//g;
     $response =~ s/ +/ /g;
     print GREEN, "Check exists and is ENABLED:\n\t$response\n", RESET;
    }
  }
}

sub get_ed {
  my $account = shift;
  my $e;
  my $res=`curl -s -k http://$api_server:8068/v1.0/accounts/$account`;
  if ($res =~ /"external_id":\s"(.+)",/) {
    $e=$1;
    chomp $e;
    $ed{$account} = $e;
  }
  else {
    $e="failed " . $res;
  }
  chomp $e;
  return $e;
}
