#!/usr/bin/perl
# quick script to do a rolling restart of cassandra on hosts from a knife search.

$user="crhodes";
$search_pattern="ord1-maas-prod-dcass*";
$delay = 120;

my $knife_command = `USER=$user knife search node \'name:$search_pattern\'` || die "Knife command failed: $!";
my @spinners = ("-", "\\", "|", "/");
$| = 1;

for (split /^/,$knife_command) {
  if ($_ =~ m/^IP:\s+(\d+\.\d+\.\d+\.\d+)/) {
    print "Restarting Cassandra on \e[33m$1\e[0m.\n";
    $restart = `ssh $user\@$1 \'hostname;sudo sv restart cassandra\'\n` || die "Restart on $1 failed: $restart $!";
    print $restart;
    sleep 5;
    my $status = `ssh $user\@$1 \'sudo sv status cassandra\'`;
    if ($status =~ m/down/) {
     die "\e[31mCass did not come back,\e[0m halting run: \e[33m$status\e[0m";
    }
    chomp $status;
    print "Status looks good: \e[32m$status\e[0m Continuing...\n"; 
    my $i = $delay;
    while ($i > 0) {
      print "\b$spinners[$index++ % @spinners]";
      sleep 1;
      $i--;
    }
  print "\b";
  }
}
