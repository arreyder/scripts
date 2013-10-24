#!/usr/bin/perl
use strict;
use IO::Socket;
use Parallel::ForkManager;
use Cache::Memcached;

my @collectors = `grep collector /etc/hosts | cut -f1 -d' '`;
my $cmd = "show checks\n";
my $port = 32322;
my $api_server = "lon3-maas-prod-api0";
my $data;
my %ed;
my $managed_token = $ARGV[0];
my $total = 0;
my $index;

$| = 1;

foreach my $server (@collectors) {
  chomp $server;
  my $i = 0;
  my $a_ref = &get_checks($server);
  my @checks = @$a_ref;

  my $pm = new Parallel::ForkManager(10);

  foreach my $c (@checks) {
    $pm->start and next;
    $c =~ tr/\015//d;
    my $external_id;
    my @check = split(':',$c);
    $total++;
    $external_id = get_ed(@check[2]);
    if ($external_id =~ /failed.+/) {
      print $c . " (No External ID Found)\n";
      next;
    }
    my $response=`curl -s -k -XGET -H 'X-Managed-Token: $managed_token' https://$api_server/v1.0/$external_id/entities/@check[1]/checks/@check[0]\n`;
    $response =~ s/\R//g;
    if ($response =~ m/code":\s(\d{3})/) {
      my $status=$1;
      chomp $status;
      if ($response =~ m/Object does not exist/) {
        print $c . " (Object does not exist)\n";
      }
      elsif ($response =~ m/Parent does not exist/) {
        print $c . " (Parent does not exist)\n";
      }
    }
    else {
      if ($response =~ m/"disabled": true/) {
        print$c . " (Check is Disabled)\n";
      }
      else {
       #print $c . " (Found)\n";
      }
    }
    $pm->finish;
  }
  $pm->wait_all_children;
}

print "\n Total of checks checked: $total\n";

sub get_ed {
  my $memd = new Cache::Memcached { 'servers' => ["127.0.0.1:11211"], };
  my $account = shift;
  my $e = $memd->get($account);
  unless ($e) {
    #print "-";
    my $res=`curl -s -k http://$api_server:8068/v1.0/accounts/$account`;
    if ($res =~ /"external_id":\s"(.+)",/) {
      $e=$1;
      chomp $e;
      $memd->set( $account, $e, 900 );
    }
    else {
      $e="failed " . $res;
    }
  }
  #print "+";
  $memd->disconnect_all();
  chomp $e;
  return $e;
}

sub get_checks {
  my $server = shift;
  my @checks;
  print "Getting checks on $server\n";
  my $sock = IO::Socket::INET->new( PeerAddr => $server, PeerPort => $port, Proto => 'tcp') or die "ERROR in Socket Creation : $!\n";
  $sock->autoflush(1);
  print $sock "$cmd";
  while (<$sock>) {
    if ($_ =~ /arguments expected/) {
      $sock->close();
    }
    next unless($_ =~ /`v\d:(.+)/);
    push (@checks,$1);
  }
  print "Found " . scalar @checks . " on $server\n";
  return \@checks;
}
