#!/usr/bin/perl
## makes sure every check in cass is on a noit
## I do lots of terrible things here for various reason. :)
## Ask me why.
## TODO: get percassa working so I do not have to use cqlsh.
## TODO: more efficient way of finding checks on the noit
## expects to be run on a cass server
##
#
use warnings;
use strict;
use JSON;
use IPC::Open3;
use IO::Socket;
use Term::ANSIColor qw(:constants);
use Parallel::ForkManager;

binmode STDOUT, ":utf8";

my $pm = new Parallel::ForkManager(16);
my @collectors = `grep collector /etc/hosts | grep -v syd | cut -f1 -d' '`;
my $api_server = "lon3-maas-stage-api0";
my $managed_token = $ARGV[0];
my $cass_server = "10.13.237.13";
my $cmd = "show checks\n";

my $pid = open3(\*WRITE, \*READ,0,"/usr/local/bin/cqlsh $cass_server 9160");

print WRITE "USE ELE;\n";
print WRITE "select * from unified_account_external_idx;\n";
close(WRITE);

my $header = <READ>; #get past a useless line
my %collectors = &get_collectors;

while ( <READ> ) {
  $pm->start and next;
  if (!(m/^$/)) {
    (my $tid,my $v2, my $v3, my $v4) = split;
    my $status = "\ntid: $tid ";
    my $account = &get_acct($tid);
    my @entities = &get_ent($tid);
    if ((defined($entities[0]))&&(!($entities[0] =~ /^$/))) {
      $status .= " ac: $account en: @entities ";
      foreach my $e (@entities) {
        my $c_ref = &get_checks($e,$tid);
        my %checks = %$c_ref;
        foreach my $key (keys %checks) {
          my @cs = split(/,/,$checks{$key});
          foreach (@cs) {
            #print "$_: ";
            #print $collectors{$_},"\n";
            my $pattern=$key . ":$e:$account:" . $_;
            #print "pattern: $pattern ";
            my $col_ip = $collectors{$_};
            my $result = &get_noit_checks($collectors{$_},$pattern);
            if ($result eq "nomatch") {
              print RED, $status, " MISSING: $pattern col: $col_ip\n", RESET;
            }
            elsif ($result eq "matched") {
                print GREEN, "m", RESET;
            }
            else {
              print RED,"WTF:MAIN",RESET;
            }
          }
        }
      }
    }
  }
  $pm->finish;
}
$pm->wait_all_children;

sub get_acct {
  print "a";
  my $t = shift;
  my $pid2 = open3(\*WRITE2, \*READ2,0,"/usr/local/bin/cqlsh $cass_server 9160");
  print WRITE2 "USE ELE;\n";
  print WRITE2 "select * from unified_account_external_idx where KEY = '$t';\n";
  close(WRITE2);
  while ( <READ2> ) {
    next unless(m/\s+KEY/);
    (my $v1,my $v2, my $ap, my $v4) = split;
    (my $ac, my $a2) = split(/:/,$ap);
    return $ac;
  }
}

sub get_ent {
  print "e";
  my $t = shift;
  my @ens;
  my @response=`curl -s -k -XGET -H 'X-Managed-Token: $managed_token' https://$api_server/v1.0/$t/entities/`;
  foreach (@response) {
    next unless (/"id":\s"(en(?:\w){8})",/);
    chomp $1;
    push(@ens,$1);
    return @ens;
  }
}

sub get_checks {
  print "c";
  my $en = shift;
  my $t = shift;
  my %c;
  my $response=`curl -s -k -XGET -H 'X-Managed-Token: $managed_token' https://$api_server/v1.0/$t/entities/$en/checks`;
  my %values = %{decode_json($response)};
  foreach my $v (@{$values{'values'}}) {
    next unless ($v->{'type'} =~ /remote\.\w+/);
    my $cid = $v->{'id'};
    #my $mz = $v->{'monitoring_zones_poll'};
    my $col;
    if (defined ($col = $v->{'collectors'})) {
      #my $col = $v->{'collectors'};
      #print "get_checks: check: $cid colls: ",join(",",@$col),"\n";
      my $cs = join(",",@$col);
      $c{$cid} = $cs;
    }
    else { print YELLOW,"b",RESET; } # bound check
  }
  return \%c;
}

sub get_collectors {
  my $response = `curl -s -k https://dfw1-maas-stage-api0.cm.k1k.me/_dashboard/monitoring_zones`;
  my %c_info = $response =~ /<td>(co(?:\w{8}))<\/td><td>(?:\d{1,3}\.){3}\d{1,3}<\/td><td>(?:\w{4}:){7}\w{4}<\/td><td>((?:\d{1,3}\.){3}\d{1,3}):\d+<\/td>/g;
  print "$_ $c_info{$_}\n" for (keys %c_info);
  return %c_info;
}

sub get_noit_checks {
  print "n";
  my $server = shift;
  my $p = shift;
  my $port = 32322;  # evetnually this may need to be passed in for multi noits
  #print "Getting checks on $server\n";
  my $sock = IO::Socket::INET->new( PeerAddr => $server, PeerPort => $port, Proto => 'tcp') or die "ERROR in Socket Creation : $!\n";
  $sock->autoflush(1);
  print $sock "$cmd";
  while (<$sock>) {
    if ($_ =~ /arguments expected/) {
      $sock->close();
      print RED, "-", RESET;
      return "nomatch";
    }
    elsif (($_ =~ /`v\d:(.+)/) && ($_ =~ /$p/)) {
      $sock->close();
      return "matched";
      last;
    }
#    else { 
#      print BLUE, "s", RESET;
#    }
  }
}
