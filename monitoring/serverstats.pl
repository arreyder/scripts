#!/usr/bin/perl
use strict;
use Data::Dumper;
use IO::Socket::INET;
use LWP::UserAgent;
use Socket qw(IPPROTO_TCP SOL_SOCKET PF_INET SOCK_STREAM SO_KEEPALIVE inet_aton sockaddr_in);
use Socket::Linux qw(TCP_NODELAY TCP_KEEPIDLE TCP_KEEPINTVL TCP_KEEPCNT);
use autodie;

$| = 1;
my $target = $ARGV[0] || die "Please provide Carbon Server IP and port.\n\n";
my $chef_env = $ARGV[1] ||  die "Please provide chef environment.\n\n";
my ($carbon_server, $carbon_port) = split(":",$ARGV[0]);
my $hostname = `hostname -f`;
my $check_jmx = "/opt/serverstats/check_jmx";
#my $jmx_pass = &get_jmx_secret;
my $jmx_pass = "foo";
my $jmx_user = "cass_monitor";
my $nodetool;

chomp $hostname;
chomp $chef_env;

if ($hostname eq "") {
  die "*** Hostname must be defined, hostname: $hostname\n";
}
  
$hostname =~ s/\./-/g;
$hostname =~ s/\.$//g;

my $prefix = $chef_env . "." . $hostname . ".system";

if (-e '/etc/cassandra/bin/nodetool' ) {
  $nodetool = '/etc/cassandra/bin/nodetool';
}
elsif ( -e '/usr/local/cassandra/bin/nodetool') {
  $nodetool = '/usr/local/cassandra/bin/nodetool';
}
else {
  $nodetool = 0
}

# sleep random seconds on start to minimize flapping on server unreachable and splay out tcp connections
sleep (int(rand(21)) + 10);

my $sin = sockaddr_in($carbon_port, inet_aton($carbon_server));
socket(my $sock, PF_INET, SOCK_STREAM, getprotobyname('tcp')) or die "socket: $!";

setsockopt($sock, IPPROTO_TCP, TCP_KEEPIDLE,  120);
setsockopt($sock, IPPROTO_TCP, TCP_KEEPINTVL,  5);
setsockopt($sock, IPPROTO_TCP, TCP_KEEPCNT,    3);
setsockopt($sock, SOL_SOCKET,  SO_KEEPALIVE,   1);

connect($sock, $sin) or die "connect: $!";

while (1) {

  (my $all_data) = &get_meminfo . &get_netstats . &get_loadavg . &get_conntrack . &get_open_files . &get_raw_vmstat . &get_vmstats . &get_ifdata . &get_disk_stats . &get_df . &get_cpu_stats . &get_jvm_jstats;

  if ($nodetool) {
    $all_data .= &get_tpstats . &get_cfstats . &get_cass_info . &get_cass_rpc . &get_cass_se_proxy;
  }

  if (-e "/etc/sv/zookeeper") {
    $all_data .= &get_zk_stats;
  }

  print $all_data;
  
  unless (print $sock $all_data) {
    die "Failed to send data: $!\n";
  }
  sleep 60;
}

sub set_pfx {
  my $m = $_[0];;
  my $p = $prefix . "." . $m;
  return $p;
}

sub get_meminfo {
  my $pfx = set_pfx("meminfo"); 
  open(MEMINFO,"/proc/meminfo") || die "status err cannot open: /proc/meminfo $!\n";;
  my $data_string;
  my $time = time;
  while (<MEMINFO>) {
    chomp;
    (my $key, my $val) = split(/:/);
    $val =~ s/^\s+//;
    $val =~ s/kB//;
    $val =~ s/\s+$//;
    $data_string .= "$pfx.$key $val $time\n";
   }
   return $data_string;
}

sub get_netstats {
  my $pfx = set_pfx("netstat");
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
  
  my $syn_recv = `netstat -ant | grep -c SYN_RECV`;
  chomp $syn_recv;

  $data_string .= "$pfx.passive_opens $passive_opens $time\n";
  $data_string .= "$pfx.active_opens $active_opens $time\n";
  $data_string .= "$pfx.listen_queue_overruns $listen_overruns $time\n";
  $data_string .= "$pfx.established $established $time\n";
  $data_string .= "$pfx.inechos $InEchos $time\n";
  $data_string .= "$pfx.inechoreps $InEchoReps $time\n";
  $data_string .= "$pfx.outechos $OutEchos $time\n";
  $data_string .= "$pfx.outechoreps $OutEchoReps $time\n";
  $data_string .= "$pfx.indestunreachs $InDestUnreachs $time\n";
  $data_string .= "$pfx.intimeexcds $InTimeExcds $time\n";
  $data_string .= "$pfx.syn_recv $syn_recv $time\n";
  $data_string .= "$pfx.RetransSegs $RetransSegs $time\n";

  return  ($data_string);
}

sub get_conntrack {
  my $pfx = set_pfx("conntrack");
  my $conntrack=`conntrack -S`;
  my (@keys, $data_string);
  my $time=time;

  for (split /^/, $conntrack) {
    (my $key,my $value) = split;
    $data_string .= "$pfx.$key $value $time\n";
  }
  return  ($data_string);
}

sub get_loadavg {
  my $pfx = set_pfx("loadavg");
  open(LOADAVG,"/proc/loadavg") || die "status err cannot open: /proc/loadavg $!\n";;
  my $data_string;
  my $time = time;
  while (<LOADAVG>) {
    chomp;
    (my $onemin, my $fivemin, my $fifteenmin, my $scheduled, my $recentpid) = split;
    $data_string .= "$pfx.1min $onemin $time\n";
    $data_string .= "$pfx.5min $fivemin $time\n";
    $data_string .= "$pfx.15min $fifteenmin $time\n";
   }
   return $data_string;
}

sub get_tpstats {
  my $pfx = set_pfx("cassandra.tpstats");
  my $tpstats=`$nodetool -h \$HOSTNAME tpstats`;
  my (@keys, $data_string);
  my $time=time;
  my $data_string;
  my $in_mt="false";

  for (split /^/, $tpstats) {
    next if ($_ =~ m/(Pool Name)|^$/);
    if ($_ =~ m/(Message type)/) { $in_mt = "true"; next };
    unless ($in_mt eq "true") {
      (my $key, my $active, my $pending, my $completed, my $blocked, my $all_t_blocked) = split;
      $data_string .= "$pfx.$key.active $active $time\n";
      $data_string .= "$pfx.$key.pending $pending $time\n";
      $data_string .= "$pfx.tpstats.$key.completed $completed $time\n";
      $data_string .= "$pfx.$key.blocked $blocked $time\n";
      $data_string .= "$pfx.tpstats.$key.all_t_blocked $all_t_blocked $time\n";
      next;
    }
    (my $key, my $dropped) = split;
    $data_string .= "$pfx.$key.dropped $dropped $time\n";
  }
  return  ($data_string);
}

sub get_cfstats {
  my $pfx = set_pfx("cassandra.cfstats");
  my $cfstats=`$nodetool -h \$HOSTNAME cfstats`;
  my $time=time;
  my (@keys, $data_string, $keyspace, $path);
  my @ATTRIBS = ("KeyCacheHitRate");

  for (split /^/, $cfstats) {
    if ($_ =~ m/Keyspace: (.+)/) { $keyspace = $1; $path = $keyspace; next };
    if ($_ =~ m/Table: (.+)/) {
      my $cf = $1;
      $path = $keyspace . "." . $cf;
      foreach $a (@ATTRIBS) {
        my $cmd = `$check_jmx -U "service:jmx:rmi:///jndi/rmi://localhost:7199/jmxrmi" -O org.apache.cassandra.metrics:type=ColumnFamily,keyspace=$keyspace,scope=$cf,name=$a -A "Value"`;
        $cmd =~ /=(\d+(?:\.\d+)?)/; 
        my $v = $1;
        $data_string .= "$pfx.$path.$a " . sprintf("%.3f",$v) . " $time\n";
      }
      next;
    };
    if ($_ =~ m/(Average tombstones per slice|Average live cells per slice|Read Count:|Write Count:|Read Latency:|Write Latency:|SSTable count:|Number of Keys|Key cache hit rate:|Bloom Filter False Postives:|Bloom Filter Space Used:|Key cache size:|Space used|Memtable Columns Count:|Memtable Data Size:)/) {
      next if ($_ =~ m/NaN/);
      (my $key, my $value) = split(':');
      $key =~ s/\s+//g;
      $key =~ s/[\(|\)]/_/g;
      $value =~ s/\s+//g;
      $value =~ s/ms.//;
      $data_string .= "$pfx.$path.$key " . sprintf("%.3f",$value) . " $time\n";
    }
    else {
      next;
    }
  }
  return  ($data_string);
}

sub get_vmstats {
  my $pfx = set_pfx("vmstats");
  my $vmstats=`vmstat 1 1`;
  my $time=time;
  my $data_string;

  for (split /^/, $vmstats) {
    if ($_ =~ m/(procs|swpd)/) { next };
    my ($r, $b, $swpd, $free, $buff, $cache, $si, $so, $bi, $bo, $in, $cs, $us, $sy, $id, $wa ) = split;
    $data_string .= "$pfx.procs.r $r $time\n";
    $data_string .= "$pfx.procs.b $b $time\n";
    $data_string .= "$pfx.memory.swpd $swpd $time\n";
    $data_string .= "$pfx.memory.free $free $time\n";
    $data_string .= "$pfx.memory.buff $buff $time\n";
    $data_string .= "$pfx.memory.cache $cache $time\n";
    $data_string .= "$pfx.swap.si $si $time\n";
    $data_string .= "$pfx.swap.so $so $time\n";
    $data_string .= "$pfx.io.bi $bi $time\n";
    $data_string .= "$pfx.io.bo $bo $time\n";
    $data_string .= "$pfx.system.in $in $time\n";
    $data_string .= "$pfx.system.cs $cs $time\n";
    $data_string .= "$pfx.cpu.us $us $time\n";
    $data_string .= "$pfx.cpu.sy $sy $time\n";
    $data_string .= "$pfx.cpu.id $id $time\n";
    $data_string .= "$pfx.cpu.wa $wa $time\n";
  }
  return  ($data_string);
}

sub get_pcpu {
  my $pid = shift;
  my $cmd = "top -d0.1 -b -n10 -p $pid | awk '/$pid/ {sum+=\$9;i++} END {print sum/i}'";
  my $pcpu = `$cmd`;
  return ($pcpu);
}

sub get_ifdata {
  my $data_string;
  my @interfaces = `ls /sys/class/net/`;
  foreach my $int (@interfaces) {
    chomp $int;
    next if ($int =~ /bonding_masters/);
    my $p = "netstat." . $int;
    my $pfx = set_pfx($p);
    my @ifdata=`ifdata -sib -sob $int`;
    my $time=time;
    my $in=$ifdata[0];
    my $out=$ifdata[1];
    chomp $in;
    chomp $out;
    $data_string .= "$pfx.bits-in $in $time\n" if (defined($in));
    $data_string .= "$pfx.bits-out $out $time\n" if (defined($out));
  }
  return  ($data_string);
}

sub get_open_files {
  my $pfx = set_pfx("file_handles");
  my $of = `cat  /proc/sys/fs/file-nr`;
  my $time=time;
  chomp $of;
  (my $o,my $f,my $m)=split(/\s+/,$of);
  my $data_string .= "$pfx.open $o $time\n";
  $data_string .= "$pfx.max $m $time\n";
  return  ($data_string);
}

sub get_cass_info {
  my $pfx = set_pfx("cassandra.info");
  my $info=`$nodetool -h \$HOSTNAME info`;
  my $time=time;
  my $data_string;

  for (split /^/,$info) {
    if ($_ =~ m/Load\s+:\s(\d+\.\d+)/) {
      my $load = $1;
      $data_string .= "$pfx.load $load $time\n";
      next;
    }
    if ($_ =~ m/Heap\sMemory\s\(MB\)\s:\s(\d+\.\d+)\s\/\s\d+\.\d+/) {
      my $heap = $1;
      $data_string .= "$pfx.heap $heap $time\n";
      next;
    }
  }
  return  ($data_string);
}

sub get_cass_rpc {
  my $pfx = set_pfx("cassandra.rpc");
  my @ATTRIBS = ("CompletedTasks","PendingTasks","CurrentlyBlockedTasks","ActiveCount","TotalBlockedTasks");
  my $data_string;
  my $time=time;

  unless (-e $check_jmx) {
    print "check_jmx not found at $check_jmx\n";
    return;
  }
  foreach $a (@ATTRIBS) {
   my $cmd = `$check_jmx -U "service:jmx:rmi:///jndi/rmi://localhost:7199/jmxrmi" -O org.apache.cassandra.RPC-THREAD-POOL:type=RPC-Thread -A $a -K Value`;
   $cmd =~ /=(\d+(?:\.\d+)?)/;;
   my $v = $1;
   if (defined($v)) {
     $data_string .= "$pfx.$a $v $time\n";
   }
 }
 return  ($data_string);
}

sub get_cass_se_proxy {
  my $pfx = set_pfx("cassandra.storageproxy");
  my @ATTRIBS = ("RecentReadLatencyMicros","TotalReadLatencyMicros","TotalWriteLatencyMicros","RecentWriteLatencyMicros","ReadOperations","WriteOperations");
  my $data_string;
  my $time=time;

  unless (-e $check_jmx) {
    print "check_jmx not found at $check_jmx\n";
    return;
  }

  foreach $a (@ATTRIBS) {
   my $cmd = `$check_jmx -U "service:jmx:rmi:///jndi/rmi://localhost:7199/jmxrmi" -O org.apache.cassandra.db:type=StorageProxy -A $a -K Value`;
   $cmd =~ /=(\d+(?:\.\d+)?)/;
   my $v = $1;
   if (defined($v)) {
     $data_string .= "$pfx.$a $v $time\n";
   }
 }
 return  ($data_string);
}

sub get_raw_vmstat {
  my $pfx = set_pfx("vmstat");
  my $time=time;
  my $data_string;

  open(VMSTAT,"/proc/vmstat") || die "status err cannot open: /proc/vmstat $!\n";

  foreach (<VMSTAT>) {
    chomp;
    (my $key,my $value) = split(/\s/, $_);
    $data_string .= "$pfx.$key $value $time\n";
  }
  return ($data_string);
}

sub get_open_fh {
  my $pid = shift;
  my $of = `lsof -p $pid -n -l -P | wc -l`;
  #uncount the header line
  $of--;
  return ($of);
}

sub get_disk_stats {
  my $pfx = set_pfx("disk");
  my $data_string;
  my @disks = `lsblk -n -l --output KNAME`;
  my @keys = ("reads_completed","reads_merged","sectors_read","milliseconds_reading","writes_completed","writes_merged","sectors_written","milliseconds_writing","IO_in_progress","milliseconds_IO","weighted_milliseconds_IO");
  foreach my $disk (@disks) {
    chomp $disk;
    next unless (-e "/sys/block/$disk/stat");
    my $disk_stats=`cat /sys/block/$disk/stat`;
    $disk_stats =~ s/^\s+//;
    my $time=time;
    my @values = split (/\s+/,$disk_stats);
    my %metrics = map { $keys[$_] => $values[$_]  } 0..$#values;
    while ( my ($key, $value) = each(%metrics) ) {
      chomp $value;
      $data_string .= "$pfx.$disk.$key $value $time\n";
    };
  };
  return ($data_string);
}

sub get_jmx_secret {
  my $jmx_user="cass_monitor";
  my $jmx_credentials_file="/etc/cassandra/default.conf/jmxremote.password";
  my $jmx_secret = `awk '/cass_monitor/ {print \$2}' /etc/cassandra/default.conf/jmxremote.password`;
  $jmx_secret =~ s/&/\\&/g;
  return $jmx_secret;
}

sub fix_instance {
  my $i = shift;
  my $instance;
  if ($i =~ m/^\/apps\/tomcat\/(\w+)\//) {
    $instance = $1;
  }
  elsif ($i =~ m/^\/opt\/api-(\w+)-v\d+\//) {
    $instance = $1;
  }
  elsif ($i =~ m/^\/opt\/(logstash|serverstats)\//) {
    $instance = $1;
  }
  elsif ($i =~ m/^org\.apache\.(.+)/) {
    $instance = $1;
    $instance =~ s/\./_/g;
  }
  elsif ($i =~ m/dell/) {
    $instance = "openmanage"
  }
  else {
    $i =~ s/\./_/g;
  }
  return ($instance);
}

sub get_jvm_jstats {
  my $data_string;
  my %processes;
  my @users;
  my $old_jvm;
  my $java_version = `java -version 2>&1 | grep version`;
  if ($java_version =~ m/"1\.6\.\d+_\d+"/) {
    @users = ("root");
    $old_jvm = 1;
  }
  else {
    @users = `ls /tmp/hsperfdata_* | grep  -o -P "hsperfdata_\\w+" | cut -d"_" -f2`;
    $old_jvm = 0;
  }
  foreach my $user (@users) {
    chomp $user;
    my @jps;
    my $jstats_util;
    if ($old_jvm) {
      @jps = `/usr/bin/jps -lv`;
    }
    else {
      @jps = `sudo -u $user /usr/bin/jps -lv`;
    }
    my $pfx = set_pfx("process.jvm");
    my $time=time;
    my @keys;

    foreach my $jvm (@jps) {
      my $instance;
      next if ($jvm =~ /(process information unavailable|jps)/);
      my ($pid, $proc_name, $options) = split(' ',$jvm,3);
      if ($options =~ m/((?:cep|bf)-\d+)\.conf/) {
        $instance = $1;
      }
      else {
        $instance = $proc_name;
        chomp $instance;
      }
      next if exists $processes{$instance};
      $processes{$instance} = 1;
      $instance = &fix_instance($instance);
      if ($old_jvm) {
        $jstats_util = `/usr/bin/jstat -gcutil $pid`;
      }
      else {
        $jstats_util = `sudo -u $user /usr/bin/jstat -gcutil $pid`;
      }
      my @jstat_lines = split (/^/,$jstats_util);
      foreach (@jstat_lines) {
        $_ =~ s/^\s+|\s+$|\s+(?=\s)//g;
        my (@values, %metrics);
        if (m/S0/) {
          @keys = split;
        }
        else {
          @values = split;
          my %metrics = map { $keys[$_] => $values[$_]  } 0..$#values;
          while ( my ($key, $value) = each(%metrics) ) {
            chomp $key;
            chomp $value;
            $data_string .= "$pfx.$instance.$key $value $time\n";
          }
        }
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
            $data_string .= "$pfx.$instance.$key $value $time\n" unless($key =~ m/^CMD|^PID/);
          }
        }
      }  
    }
  }
  return ($data_string);
}

sub get_df {
  my $pfx = set_pfx("df");
  my $df=`df -P | awk '/\%/ {print \$1 " " \$5}'`;
  my (@keys, $data_string);
  my $time=time;

  for (split /^/, $df) {
    (my $key,my $value) = split;
    $key =~ s/^\///;
    $key =~ s/\//./g;
    $value =~ s/\%//g;
    $data_string .= "$pfx.$key.percent_used $value $time\n";
  }
  return  ($data_string);
}

sub get_jvm_threads {
  my $pfx = set_pfx("process.jvm");
  my $proc = shift;
  my $pid = shift;
  my %count;
  my $data_string;
  my $time=time;
  my $cmd = "sudo -u cassandra /usr/java/jdk1.7.0_60/bin/jstack $pid\n";
  print $cmd;
  my $jstat = `$cmd`;
  for (split /^/, $jstat) {
    if ($_ =~ m/"(.+)"/) {
      my ($thread,$id) = split(/:/,$1);
      $thread =~ s/\s#\d+//;
      $thread =~ s/\./_/g;
      $thread =~ s/#\d+(\s|$)//;
      $thread =~ s/-\d+(\s|$)//;
      $thread =~ s/\s+/_/g;
      $thread =~ s/\(|\)/_/g;
      $thread =~ s/\///;
      if (defined $count{$thread}) {
        $count{$thread}++;
      }
      else {
        $count{$thread} = 1;
      }
    }
  }
  while (my ($k,$v)=each %count) {
   $data_string .= "$pfx.$proc.threads.$k $v $time\n";
  }
  return ($data_string);
}

sub get_zk_stats {
  my $cmd = "mntr";
  my $port = "2181";
  my $server = "127.0.0.1";
  my $pfx = set_pfx("zk");
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
     if ($key =~ /zk_server_state/) {
       if ($value =~ /follower/) {
         $value = 0;
       }
       else {
         $value = 1;
       }
     }
     $data_string .= "$pfx.$key $value $time\n";
    }
  }
  return  ($data_string);
}

sub get_cpu_stats {
  my $pfx = set_pfx("cpu");
  my $time=time;
  my ($data_string,@keys);
  my $mpstat = `/usr/bin/mpstat -P ALL 1 10 | grep Average:`;
  my @mpstat_lines = split (/^/,$mpstat);
  foreach (@mpstat_lines) {
    next if($_ eq "") || (m/Linux/) || (m/^\s+$/);
    $_ =~ s/^\s+|\s+$|\s+(?=\s)//g;
    my (@values, %metrics);
    if (m/iowait/) {
      @keys = split;
      splice @keys,0,2;
    }
    else {
      @values = split;
      splice @values,0,1;
      my $instance = @values[0];
      splice @values,0,1;
      my %metrics = map { $keys[$_] => $values[$_]  } 0..$#values;
      while ( my ($key, $value) = each(%metrics) ) {
        $key =~ s/%/percent_/;
        chomp $key;
        chomp $value;
        $data_string .= "$pfx.$instance.$key $value $time\n";
      }
    }
  }
  return $data_string;
}
