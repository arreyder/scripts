#!/usr/bin/perl
use strict;
use IO::Socket;

my @collectors = `grep collector /etc/hosts | grep -v syd | cut -f1 -d' '`;
my $cmd = "show checks\n";
my $port = 32322;
my $api_server = "lon3-maas-prod-api0";
my $data;
my %ed;
my $managed_token = $ARGV[0];
my $total = 0;

$| = 1;

foreach my $server (@collectors) {
  chomp $server;
  print "Getting checks on $server\n";
  my $sock = IO::Socket::INET->new( PeerAddr => $server, PeerPort => $port, Proto => 'tcp') or die "ERROR in Socket Creation : $!\n";

  $sock->autoflush(1);
  print $sock "$cmd";
  my $i = 0;
  while (<$sock>) {
    if ($_ =~ /arguments expected/) {
      $sock->close();
    }
#    print $_;
    next unless($_ =~ /`v\d:(.+)/);
    my $external_id;
    my @check = split(':',$1);
    $total++;
    if (!(defined $ed{@check[2]})) {
      $external_id = get_ed(@check[2]);
      print "-";
    }
    else {
      print "+";
      $external_id = $ed{@check[2]};
    }
    if ($external_id =~ /failed.+/) {
      print "\ncollector: $server Failed to get external_id for:\n\t$_\n\t$external_id\n";
      sleep 5;
      next;
    }
    my $response=`curl -s -k -XGET -H 'X-Managed-Token: $managed_token' https://$api_server/v1.0/$external_id/entities/@check[1]/checks/@check[0]\n`;
    if ($response =~ m/code":\s(\d{3})/) {
      my $status=$1;
      chomp $status;
      print "\ncollector: $server external: $external_id entity: @check[1] account: @check[2] check: @check[0] status: $status response:\n $response\n\t$_";
        sleep 5;
    }
    else {
      if ($response =~ m/"disabled": true/) {
        print "\nCheck is DISABLED: \ncollector: $server external: $external_id entity: @check[1] account: @check[2] check: @check[0] response:\n $response\n\t$_";
        sleep 5;
      }
      else {
       print "F";
      }
    }
  }
}

print "\n Total of checks checked: $total\n";

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
