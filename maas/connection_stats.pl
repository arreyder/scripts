#!/usr/bin/perl
# reports on active opens p/s, est connections, and listen que overruns (drp) p/s etc...
# quick hack that's useful in finding resource limit related network issues
# needs to be made more generic, currently targeted at api but with some collections
# commented would be useful else where.

use strict;
use Term::ANSIColor qw(:constants);

my $current_po;
my $current_ao;
my $current_lo;
my $last_po;
my $last_ao;
my $last_lo;
my $est;

($last_po,$last_ao,$last_lo,$est) = getstats();

while () {
  ($current_po,$current_ao,$current_lo,$est) = getstats();
  my $sockmem = `./get_tcp_mem.sh`;
  my $syn_recv = `netstat -ant | grep -c SYN_RECV`;
  my $tw = `netstat -ant | grep -c TIME_WAIT`;
  my $cw = `netstat -ant | grep -c CLOSE_WAIT`;
  my $fw2 = `netstat -ant | grep -c FIN_WAIT2`;
  my $ka = `netstat -antpo | grep -c keep`;
  my $fh = `cat /proc/sys/fs/file-nr`;
  my $bw = `curl -s -k https://10.14.238.14/server-status?auto | grep BusyWorkers:`;
  my $iw = `curl -s -k https://10.14.238.14/server-status?auto | grep IdleWorkers:`;

  $fh =~ s/\t/ /g;
  chomp ($syn_recv, $tw, $cw, $fh, $bw, $iw, $sockmem, $fw2, $ka);

  my $delta_po = $current_po - $last_po;
  my $delta_ao = $current_ao - $last_ao;
  my $delta_lo = $current_lo - $last_lo;
  my $color = RED if ($delta_lo gt 0);
  print $color, "$bw $iw fh:$fh $sockmem\tsynrec:$syn_recv ka:$ka tw:$tw cw:$cw fw2:$fw2 po:$delta_po ao:$delta_ao est:$est drp:$delta_lo\t" , '-' x ($delta_po/4),"\n", RESET;
  $last_po = $current_po;
  $last_ao = $current_ao;
  $last_lo = $current_lo;
  sleep 1;
 }

sub getstats {
  my @ns;
  my @snmp;
  my $passive_opens;
  my $active_opens;
  my $listen_overruns;
  my $established;

  open(NETSTAT,"/proc/net/netstat");
  open(SNMP,"/proc/net/snmp");
  while (<NETSTAT>) {
    if ($_ =~ m/TcpExt:/) {
      my $nextline = <NETSTAT>;
      @ns = split(/ /, $nextline);
      $listen_overruns = @ns[20];
      close NETSTAT;
    };
  };

  while (<SNMP>) {
  if ($_ =~ m/Tcp:/) {
    my $nextline = <SNMP>;
    @snmp = split(/ /, $nextline);
    $passive_opens = @snmp[6];
    $active_opens = @snmp[5];
    $established = @snmp[9];
    close SNMP;
   };
  };
  return  ($passive_opens,$active_opens,$listen_overruns,$established);
};

