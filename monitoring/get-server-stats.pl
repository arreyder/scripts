#!/usr/bin/perl
use strict;
use Data::Dumper;
use IO::Socket::INET;
use XML::Simple;
use LWP::UserAgent;
use Socket qw(IPPROTO_TCP SOL_SOCKET PF_INET SOCK_STREAM SO_KEEPALIVE inet_aton sockaddr_in);
use autodie;

$| = 1;
my $carbon_server = $ARGV[0] || die "Please provide Carbon Server IP.\n\n";
my $carbon_port = 2003;
my $hostname = `hostname`;
my $nodetool;

chomp $hostname;

my $sin = sockaddr_in($carbon_port, inet_aton($carbon_server));
socket(my $sock, PF_INET, SOCK_STREAM, getprotobyname('tcp')) or die "socket: $!";

setsockopt($sock, SOL_SOCKET,  SO_KEEPALIVE,   1);

connect($sock, $sin) or die "connect: $!";

while (1) {

  (my $all_data) = &get_meminfo . &get_netstats . &get_iostats . &get_loadavg . &get_conntrack . &get_open_files . &get_vmstats . &get_ifdata("eth0") . &get_jvm_stats . &get_disk_stats;

  if ($hostname =~ m/cass/) {
    $nodetool = &get_nodetool_path;
    if ( length $nodetool and -e $nodetool ) {
      $all_data .= &get_tpstats . &get_cfstats . &get_cass_info . &get_raw_vmstat . &get_cass_rpc . &get_cass_se_proxy . &get_cass_rpc;
    }
  }

  if (($hostname =~ m/cass/) && (-e "/service/zookeeper")) {
    $all_data .= &get_zk_stats;
  }

  if ($hostname =~ m/(agent|api|messenger)/) {
    $all_data .= &get_node_stats;
  }

  if ($hostname =~ m/(collector|-agent)/) {
    $all_data .= &get_ifdata("eth1") . &get_haproxy . &get_haproxy_stats;
  }

  if ($hostname =~ m/(collector)/) {
    $all_data .= &get_noit_stats;
    $all_data .= &count_noit_checks;
    $all_data .= &get_bind_stats;
  }

  print $all_data;
  
  unless (print $sock $all_data) {
    die "Failed to send data: $!\n";
  }
  sleep 60;
}

sub get_meminfo {
  open(MEMINFO,"/proc/meminfo") || die "status err cannot open: /proc/meminfo $!\n";;
  my $data_string;
  my $time = time;
  while (<MEMINFO>) {
    chomp;
    (my $key, my $val) = split(/:/);
    $val =~ s/^\s+//;
    $val =~ s/kB//;
    $val =~ s/\s+$//;
    $data_string .= "$hostname.system.meminfo.$key $val $time\n";
   }
   return $data_string;
}

sub get_netstats {
  my (@ns, @snmp, $passive_opens, $active_opens, $listen_overruns, $established,
     $data_string, $InEchos, $InEchoReps, $OutEchos, $OutEchoReps, $InDestUnreachs,
     $InTimeExcds, $RetransSegs);
  my $time=time;

  open(NETSTAT,"/proc/net/netstat") || die "status err cannot open: /proc/net/netstat $!\n";
  open(SNMP,"/proc/net/snmp") || die "status err cannot open: /proc/net/snmp $!\n";

  while (<NETSTAT>) {
    if ($_ =~ m/TcpExt:/) {
      my $nextline = <NETSTAT>;
      @ns = split(/ /, $nextline);
      $listen_overruns = @ns[20];
      close NETSTAT;
    }
  }

  while (<SNMP>) {
  if ($_ =~ m/Tcp:/) {
    my $nextline = <SNMP>;
    @snmp = split(/ /, $nextline);
    $passive_opens = @snmp[6];
    $active_opens = @snmp[5];
    $established = @snmp[9];
    $RetransSegs = @snmp[12];
    close SNMP;
   }
  }
  
  open(SNMP,"/proc/net/snmp") || die "status err cannot open: /proc/net/snmp $!\n";

  while (<SNMP>) {
    if ($_ =~ m/Icmp:/) {
    my $nextline = <SNMP>;
    @snmp = split(/ /, $nextline);
    $InEchos = @snmp[8];
    $InEchoReps = @snmp[9];
    $OutEchos = @snmp[21];
    $OutEchoReps = @snmp[22];
    $InDestUnreachs = @snmp[3];
    $InTimeExcds = @snmp[4];
    close SNMP;
   }
  }
  
  my $syn_recv = `ss -s | grep -oP '(?<=synrecv )\\d+'`;
  chomp $syn_recv;

  $data_string .= "$hostname.system.netstat.passive_opens $passive_opens $time\n";
  $data_string .= "$hostname.system.netstat.active_opens $active_opens $time\n";
  $data_string .= "$hostname.system.netstat.listen_queue_overruns $listen_overruns $time\n";
  $data_string .= "$hostname.system.netstat.established $established $time\n";
  $data_string .= "$hostname.system.netstat.inechos $InEchos $time\n";
  $data_string .= "$hostname.system.netstat.inechoreps $InEchoReps $time\n";
  $data_string .= "$hostname.system.netstat.outechos $OutEchos $time\n";
  $data_string .= "$hostname.system.netstat.outechoreps $OutEchoReps $time\n";
  $data_string .= "$hostname.system.netstat.indestunreachs $InDestUnreachs $time\n";
  $data_string .= "$hostname.system.netstat.intimeexcds $InTimeExcds $time\n";
  $data_string .= "$hostname.system.netstat.syn_recv $syn_recv $time\n";
  $data_string .= "$hostname.system.netstat.RetransSegs $RetransSegs $time\n";

  return  ($data_string);
}

sub get_conntrack {
  my $conntrack=`conntrack -S`;
  my (@keys, $data_string);
  my $time=time;

  for (split /^/, $conntrack) {
    (my $key,my $value) = split;
    $data_string .= "$hostname.system.conntrack.$key $value $time\n";
  }
  return  ($data_string);
}

sub get_iostats {
  my $iostat=`iostat -n 8 -x 1`;
  my (@keys, $data_string);
  my $time=time;

  for (split /^/, $iostat) {
    my (@values, %metrics);
    if (m/^Device:/) {
      @keys = split;
      next;
    }
    elsif (m/^(s|xv)d/) {
      @values = split;
      my %metrics = map { $keys[$_] => $values[$_]  } 0..$#values;
      my $device = $metrics{'Device:'};
      while ( my ($key, $value) = each(%metrics) ) {
        $key =~ s/\//-per/;
        $key =~ s/\%/percent-/;
        $data_string .= "$hostname.system.iostats.$device.$key $value $time\n" unless $key eq "Device:";
     }
    }
  }
  return  ($data_string);
}

sub get_loadavg {
  open(LOADAVG,"/proc/loadavg") || die "status err cannot open: /proc/loadavg $!\n";;
  my $data_string;
  my $time = time;
  while (<LOADAVG>) {
    chomp;
    (my $onemin, my $fivemin, my $fifteenmin, my $scheduled, my $recentpid) = split;
    $data_string .= "$hostname.system.loadavg.1min $onemin $time\n";
    $data_string .= "$hostname.system.loadavg.5min $fivemin $time\n";
    $data_string .= "$hostname.system.loadavg.15min $fifteenmin $time\n";
   }
   return $data_string;
}

sub get_tpstats {
  my $tpstats=`$nodetool -h $hostname -p 9080 tpstats`;
  my (@keys, $data_string);
  my $time=time;
  my $data_string;
  my $in_mt="false";

  for (split /^/, $tpstats) {
    next if ($_ =~ m/(Pool Name)|^$/);
    if ($_ =~ m/(Message type)/) { $in_mt = "true"; next };
    unless ($in_mt eq "true") {
      (my $key, my $active, my $pending, my $completed, my $blocked, my $all_t_blocked) = split;
      $data_string .= "$hostname.system.cassandra.tpstats.$key.active $active $time\n";
      $data_string .= "$hostname.system.cassandra.tpstats.$key.pending $pending $time\n";
      $data_string .= "$hostname.system.cassandra.tpstats.$key.completed $completed $time\n";
      $data_string .= "$hostname.system.cassandra.tpstats.$key.blocked $blocked $time\n";
      $data_string .= "$hostname.system.cassandra.tpstats.$key.all_t_blocked $all_t_blocked $time\n";
      next;
    }
    (my $key, my $dropped) = split;
    $data_string .= "$hostname.system.cassandra.tpstats.$key.dropped $dropped $time\n";
  }
  return  ($data_string);
}

sub get_cfstats {
  my $cfstats=`$nodetool -h $hostname -p 9080 cfstats`;
  my $time=time;
  my (@keys, $data_string, $keyspace, $path);

  for (split /^/, $cfstats) {
    if ($_ =~ m/Keyspace: (.+)/) { $keyspace = $1; $path = $keyspace; next };
    if ($_ =~ m/Column Family: (.+)/) { $path = $keyspace . "." . $1; next };
    if ($_ =~ m/(Read Latency:|Write Latency:|SSTable count:|Number of Keys|Key cache hit rate:|Bloom Filter False Postives:|Bloom Filter Space Used:|Key cache size:)/) {
      next if ($_ =~ m/NaN/);
      (my $key, my $value) = split(':');
      $key =~ s/\s+//g;
      $key =~ s/[\(|\)]/_/g;
      $value =~ s/\s+//g;
      $value =~ s/ms.//;
      $data_string .= "$hostname.system.cassandra.cfstats.$path.$key " . sprintf("%.3f",$value) . " $time\n";
    }
    else {
      next;
    }
  }
  return  ($data_string);
}

sub get_vmstats {
  my $vmstats=`vmstat 1 1`;
  my $time=time;
  my $data_string;

  for (split /^/, $vmstats) {
    if ($_ =~ m/(procs|swpd)/) { next };
    my ($r, $b, $swpd, $free, $buff, $cache, $si, $so, $bi, $bo, $in, $cs, $us, $sy, $id, $wa ) = split;
    $data_string .= "$hostname.system.vmstat.procs.r $r $time\n";
    $data_string .= "$hostname.system.vmstat.procs.b $b $time\n";
    $data_string .= "$hostname.system.vmstat.memory.swpd $swpd $time\n";
    $data_string .= "$hostname.system.vmstat.memory.free $free $time\n";
    $data_string .= "$hostname.system.vmstat.memory.buff $buff $time\n";
    $data_string .= "$hostname.system.vmstat.memory.cache $cache $time\n";
    $data_string .= "$hostname.system.vmstat.swap.si $si $time\n";
    $data_string .= "$hostname.system.vmstat.swap.so $so $time\n";
    $data_string .= "$hostname.system.vmstat.io.bi $bi $time\n";
    $data_string .= "$hostname.system.vmstat.io.bo $bo $time\n";
    $data_string .= "$hostname.system.vmstat.system.in $in $time\n";
    $data_string .= "$hostname.system.vmstat.system.cs $cs $time\n";
    $data_string .= "$hostname.system.vmstat.cpu.us $us $time\n";
    $data_string .= "$hostname.system.vmstat.cpu.sy $sy $time\n";
    $data_string .= "$hostname.system.vmstat.cpu.id $id $time\n";
    $data_string .= "$hostname.system.vmstat.cpu.wa $wa $time\n";
  }
  return  ($data_string);
}

sub get_pcpu {
  my $pid = shift;
  my $cmd = "top -d0.1 -b -n10 -p $pid | awk '/$pid/ {sum+=\$9;i++} END {print sum/i}'";
  my $pcpu = `$cmd`;
  return ($pcpu);
}

sub get_node_stats {
  my ($data_string, @keys);
  my $node_stats=`ps -o pid,pmem,cmd -C node`;
  my $time=time;
  my @lines = split (/^/,$node_stats);
  foreach (@lines) {
    my (@values, %metrics);
    if (m/MEM CMD/) {
      @keys = split;
    }
    elsif (m/node/) {
      $_ =~ s/^\s+//;
      @values = split(/\s+/,$_,3);
      my %metrics = map { $keys[$_] => $values[$_]  } 0..$#values;
      $metrics{'percent-CPU'} = &get_pcpu($metrics{'PID'});
      while ( my ($key, $value) = each(%metrics) ) {
        chomp $key;
        chomp $value;
        my $i = $metrics{'CMD'};
        my $proc_name;
        if ($i =~ m/node\s([0-9a-zA-Z-_\/]+)\s.+-p\s(\d+).*/) {
          $proc_name = substr($1, rindex($1,"/")+1, length($1)-rindex($1,"/")-1);
          my $port = $2;
          if (($proc_name =~ m/endpoint/) || ($port = 5068)) {
            $proc_name .= "-$port";
          }
        }
        else {
          if ($i =~ m/node\s([0-9a-zA-Z-_\/]+)\s.*/) {
            $proc_name = substr($1, rindex($1,"/")+1, length($1)-rindex($1,"/")-1);
          }
          else {
            $proc_name = "unknown";
          }
        }
        $key =~ s/\//-per/;
        $key =~ s/\%/percent-/;
        $data_string .= "$hostname.system.process.node.$proc_name.$key $value $time\n" unless($key =~ m/^CMD|^PID/);
      }
    }
  }
  return ($data_string);
}

sub get_noit_stats {
  my ($data_string, @keys);
  my $noit_stats=`ps -o pid,pmem,cmd -C noitd`;
  my $time=time;
  my @lines = split (/^/,$noit_stats);
  foreach (@lines) {
    my (@values, %metrics);
    if (m/MEM CMD/) {
      @keys = split;
    }
    elsif (m/noitd/) {
      $_ =~ s/^\s+//;
      @values = split(/\s+/,$_,3);
      my %metrics = map { $keys[$_] => $values[$_]  } 0..$#values;
      $metrics{'percent-CPU'} = &get_pcpu($metrics{'PID'});
      while ( my ($key, $value) = each(%metrics) ) {
        chomp $key;
        chomp $value;
        my $i = $metrics{'CMD'};
        $i =~ m/(noit-\d+)\.conf/;
        my $instance = $1;
        $key =~ s/\//-per/;
        $key =~ s/\%/percent-/;
        $data_string .= "$hostname.system.process.noit.$instance.$key $value $time\n" unless($key =~ m/^CMD|^PID/);
      }
    }
  }
  return ($data_string);
}

sub count_noit_checks {
  my $sdir = "/service";
  my $ndir = "/opt/ele-conf/noit/";
  my $data_string;
  opendir my($dh), $sdir or die "Couldn't open dir '$sdir': $!";
  my @files = readdir $dh;
  closedir $dh;
  my $time=time;
  foreach (@files) {
    if (m/noit-(\d+)/)  {
      my $config = $ndir . $_;
      my $count = `grep -c uuid $config.conf`;
      chomp $count;
      $_ =~ s/\.conf//;
      $data_string .= "$hostname.system.process.noit.$1.checks $count $time\n";
    }
  }
  return ($data_string);
}

sub get_ifdata {
  my $interface=$_[0];
  my @ifdata=`ifdata -sib -sob $interface`;
  my $time=time;
  my $data_string;
  my $in=$ifdata[0];
  my $out=$ifdata[1];
  chomp $in;
  chomp $out;
  $data_string .= "$hostname.system.netstat.$interface.bits-in $in $time\n";
  $data_string .= "$hostname.system.netstat.$interface.bits-out $out $time\n";
  return  ($data_string);
}

sub get_zk_stats {
  my $cmd = "mntr";
  my $port = "2181";
  my $server = "127.0.0.1";
  my ($data, $data_string);
  my $time=time;

  my $sock = IO::Socket::INET->new(
    PeerAddr => $server,
    PeerPort => $port,
    Proto    => 'tcp'
  ) or die "ERROR in Socket Creation : $!\n";

  $sock->send("$cmd");
  $sock->recv($data,4096);
  for (split /^/, $data) {
    unless ($_ =~ /zk_version/) {
     (my $key,my $value) = split;
     $data_string .= "$hostname.system.zk.$key $value $time\n";
    }
  }
  return  ($data_string);
}

sub get_jvm_stats {
  my @jps = `jps -lv`;
  my $time=time;
  my ($data_string,@keys);

  foreach my $jvm (@jps) {
    next unless ($jvm =~ /ingestor|blueflood|cassandra|cep/);
    my $instance;
    my ($pid, $proc_name, $options) = split(' ',$jvm,3);
    if ($options =~ m/((?:cep|bf)-\d+)\.conf/) {
      $instance = $1;
    }
    else {
      $instance = $proc_name;
      chomp $instance;
    }
    my $jvm_stats=`ps -o pid,pmem,cmd -p$pid`;
    my @lines = split (/^/,$jvm_stats);
    foreach (@lines) {
      my (@values, %metrics);
      if (m/%/) {
        @keys = split;
      }
      elsif (m/java/) {
        $_ =~ s/^\s+//;
        @values = split(/\s+/,$_,3);
        my %metrics = map { $keys[$_] => $values[$_]  } 0..$#values;
        $metrics{'percent-CPU'} = &get_pcpu($metrics{'PID'});
        while ( my ($key, $value) = each(%metrics) ) {
          chomp $key;
          chomp $value;
          $key =~ s/\//-per/;
          $key =~ s/\%/percent-/;
          $data_string .= "$hostname.system.process.jvm.$instance.$key $value $time\n" unless($key =~ m/^CMD|^PID/);
        }
      }
    }
  }
  return ($data_string);
}

sub get_open_files {
  my $of = `cat  /proc/sys/fs/file-nr`;
  my $time=time;
  chomp $of;
  (my $o,my $f,my $m)=split(/\s+/,$of);
  my $data_string .= "$hostname.system.file_handles.open $o $time\n";
  $data_string .= "$hostname.system.file_handles.max $m $time\n";
  return  ($data_string);
}

sub get_haproxy {
  my @hasocks = ("aep-haproxy", "snet-haproxy");
  my $time = time;
  my $data_string = "";

  foreach my $hasock (@hasocks) {
    my $hasock_path = "/service/$hasock/locks/$hasock.sock";
    if (-e $hasock_path) {
      my $sock = new IO::Socket::UNIX (Peer => $hasock_path, Type => SOCK_STREAM, Timeout => 1) || warn "$!\n";
      next if !$sock;
      print $sock "show stat\n";
      my $k = <$sock>;
      $k =~ s/^\#\s//;
      my @keys = split(',',$k);
      while(<$sock>) {
        chomp;
        my @d = split(',');
        my %h;
        @h{@keys} = @d;
        my $prefix = "$hostname.system.haproxy.$hasock";
        if (defined($h{"pxname"})) {
          $h{"pxname"} =~ s/\./-/g;
          $prefix .= ("." . $h{"pxname"});
        }
        if (defined($h{"svname"})) {
          $h{"svname"} =~ s/\./-/g;
          $prefix .= ("." . $h{"svname"});
        }
        if (defined($h{"sid"})) {
          $h{"sid"} =~ s/\./-/g;
          $prefix .= ("." . $h{"sid"});
        }
        delete @h{qw(pxname svname sid pid iid rate type weight status chkdown)};
        while ( my ($key, $value) = each(%h) ) {
          unless ((!defined($value)) || ($value eq "")) {
            $data_string .= "$prefix.$key $value $time\n";
          }
        }
      }
      close($sock);
    }
  }
  return ($data_string);
}

sub get_cass_info {
  my $info=`$nodetool -h $hostname -p 9080 info`;
  my $time=time;
  my $data_string;

  for (split /^/,$info) {
    if ($_ =~ m/Load\s+:\s(\d+\.\d+)/) {
      my $load = $1;
      $data_string .= "$hostname.system.cassandra.info.load $load $time\n";
      next;
    }
    if ($_ =~ m/Heap\sMemory\s\(MB\)\s:\s(\d+\.\d+)\s\/\s\d+\.\d+/) {
      my $heap = $1;
      $data_string .= "$hostname.system.cassandra.info.heap $heap $time\n";
      next;
    }
  }
  return  ($data_string);
}

sub get_cass_rpc {
  my @ATTRIBS = ("CompletedTasks","PendingTasks","CurrentlyBlockedTasks","ActiveCount","TotalBlockedTasks");
  my $data_string;
  my $time=time;

  unless (-e '/usr/lib/nagios/plugins/check_jmx') {
    print "check_jmx not found at /usr/lib/nagios/plugins/check_jmx\n";
    return;
  }
  foreach $a (@ATTRIBS) {
   my $cmd = `/usr/lib/nagios/plugins/check_jmx -U "service:jmx:rmi:///jndi/rmi://localhost:9080/jmxrmi" -O org.apache.cassandra.RPC-THREAD-POOL:type=RPC-Thread -A $a -K Value`;
   $cmd =~ /=(\d+)/;
   my $v = $1;
   $data_string .= "$hostname.system.cassandra.rpc.$a $v $time\n";
 }
 return  ($data_string);
}

sub get_cass_se_proxy {
  my @ATTRIBS = ("RecentReadLatencyMicros","TotalReadLatencyMicros","TotalWriteLatencyMicros","RecentWriteLatencyMicros","ReadOperations","WriteOperations");
  my $data_string;
  my $time=time;

  unless (-e '/usr/lib/nagios/plugins/check_jmx') {
    print "check_jmx not found at /usr/lib/nagios/plugins/check_jmx\n";
    return;
  }

  foreach $a (@ATTRIBS) {
   my $cmd = `/usr/lib/nagios/plugins/check_jmx -U "service:jmx:rmi:///jndi/rmi://localhost:9080/jmxrmi" -O org.apache.cassandra.db:type=StorageProxy -A $a -K Value`;
   $cmd =~ /=(\d+)/;
   my $v = $1;
   $data_string .= "$hostname.system.cassandra.storageproxy.$a $v $time\n";
 }
 return  ($data_string);
}

sub get_raw_vmstat {
  my $time=time;
  my $data_string;

  open(VMSTAT,"/proc/vmstat") || die "status err cannot open: /proc/vmstat $!\n";

  foreach (<VMSTAT>) {
    chomp;
    (my $key,my $value) = split(/\s/, $_);
    $data_string .= "$hostname.system.vmstat.$key $value $time\n";
  }
  return ($data_string);
}

sub get_nodetool_path {
  my $cass_pid;
  my $cass_type;
  my $cass_dir;
  
  if(-d '/service/dcass') {
    $cass_type = "dcass";
  } elsif (-d '/service/cass') {
    $cass_type = "cass";
  } else {
    return "";
  }
  
  $cass_pid = `cat /service/$cass_type/supervise/pid`;
  if ($cass_pid) {
    chomp $cass_pid;
    $cass_dir = `ls -l /proc/$cass_pid/fd | grep -P '/opt/cassandra-[0-9]+' | head -1 | cut -d/ -f2,3`;
    chomp $cass_dir;
    return "/$cass_dir/bin/nodetool";
  }
  return "";
}

sub get_haproxy_stats {
  my ($data_string, @keys);
  my $haproxy_stats=`ps -o pid,pmem,cmd -C haproxy`;
  unless ($haproxy_stats =~ m/haproxy/) {
    return("");
  }
  my $time=time;
  my @lines = split (/^/,$haproxy_stats);
  foreach (@lines) {
    my (@values, %metrics);
    if (m/MEM CMD/) {
      @keys = split;
    }
    elsif (m/haproxy/) {
      $_ =~ s/^\s+//;
      @values = split(/\s+/,$_,3);
      %metrics = map { $keys[$_] => $values[$_]  } 0..$#values;
      $metrics{'openfiles'} = &get_open_fh($metrics{'PID'});
      $metrics{'percent-CPU'} = &get_pcpu($metrics{'PID'});
      while ( my ($key, $value) = each(%metrics) ) {
        chomp $key;
        chomp $value;
        my $i = $metrics{'CMD'};
        $i =~ m/(snet|aep)-haproxy\.conf/;
        my $instance = $1;
        $key =~ s/\//-per/;
        $key =~ s/\%/percent-/;
        $data_string .= "$hostname.system.process.haproxy.$instance.$key $value $time\n" unless($key =~ m/^CMD|^PID/);
      }
    }
  }
  return ($data_string);
}

sub get_open_fh {
  my $pid = shift;
  my $of = `ls /proc/$pid/fd | wc -l`;
  return ($of);
}

# Larger scoped var for the recursive parse_bind_stats sub to store results it.
my $bind_stats;

sub get_bind_stats {
  my $ua = new LWP::UserAgent;
  my $response = $ua->get('http://127.0.0.1:8053');
  if ($response && $response->is_success) {
    my $time = time;
    my $xmlString = $response->content;
    my $ref = XMLin($xmlString);
    my $p = "";
    
    $bind_stats = "";
    &parse_bind_stats($ref,$p,$time);
    return($bind_stats);
  }
  else {
    print "get_bind_stats failed to connect to http://127.0.0.1:8053!\n";
    return;
  }
}

sub parse_bind_stats {
  my $tree=$_[0];
  my $path=$_[1];
  my $ts=$_[2];
  foreach (keys %{$tree}) {
  next if ($_ =~ /memory|servermgr|taskmgr|socketmgr|zonestat|sockstat/);
  my $p0 = $path . ".$_";
    if (ref $tree->{$_} eq 'HASH') {
      parse_bind_stats($tree->{$_},$p0,$ts);
    }
    else {
      if (($_ eq "counter")&&($tree->{$_} > 0)) {
        $bind_stats .= "$hostname.system$p0 " . $tree->{$_} . " $ts\n";
      }
    }
  }
  return;
}

sub get_disk_stats {
  my $data_string;
  my @disks = ("sda","sdb");
  my @keys = ("reads_completed","reads_merged","sectors_read","milliseconds_reading","writes_completed","writes_merged","sectors_written","milliseconds_writing","IO_in_progress","milliseconds_IO","weighted_milliseconds_IO");
  foreach my $disk (@disks) {
    next unless (-e "/sys/block/$disk/stat");
    my $disk_stats=`cat /sys/block/$disk/stat`;
    $disk_stats =~ s/^\s+//;
    my $time=time;
    my @values = split (/\s+/,$disk_stats);
    my %metrics = map { $keys[$_] => $values[$_]  } 0..$#values;
    while ( my ($key, $value) = each(%metrics) ) {
      chomp $value;
      $data_string .= "$hostname.system.disk.$disk.$key $value $time\n";
    };
  };
  return ($data_string);
}
