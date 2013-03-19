#!/usr/bin/perl
use strict;
use warnings;
use Net::ZooKeeper;
use Parallel::ForkManager;

#my $server_list = "10.13.237.77:2181,10.13.237.78:2181,10.13.237.79:2181,10.14.238.25:2181,10.14.238.27:2181,10.8.109.145:2181,10.8.109.148:2181";
my $server_list = "127.0.0.1:2181";
my $pm = new Parallel::ForkManager(4);
my $zkh = Net::ZooKeeper->new('127.0.0.1:2181');
my $ctime = time;
my $interval = 648000;  # 7.5 days.
my $cutoff = $ctime - $interval;
my $deleted = 0;
my $root = "";

print "Interval is $cutoff. ", scalar localtime($cutoff), "\n";
my @ZNODES = $zkh->get_children('/');
undef $zkh;

foreach my $path (@ZNODES) {
  $pm->start and next;
  process_path($root,$path);
  $pm->finish;
}

$pm->wait_all_children;

sub process_path {
  my $szkh = Net::ZooKeeper->new($server_list);
  my $ppath = $_[0];
  my $cpath = $_[1];
  my $fullpath = $ppath . "/" . $cpath;
  my $stat = $szkh->stat();
  if ($szkh->exists("$fullpath", 'stat' => $stat)) {
    my %node_data = %{$stat};
    if ($node_data{'ephemeral_owner'} eq "0") {
      if ($node_data{'num_children'} eq "0") {
        my $ct = int $node_data{'ctime'}/1000;
        my $mt = int $node_data{'mtime'}/1000;
        my $created = scalar localtime($ct);
        my $modified =scalar localtime($mt);
        if ($mt < $cutoff) {
          my $result = "$fullpath ephermeral_owner: $node_data{'ephemeral_owner'} (Not Ephemeral)\n";
          $result .= "$fullpath num_children: $node_data{'num_children'}\n";
          $result .= "$fullpath Created: $created\n";
          $result .= "$fullpath Modified: $modified\n";
          if ($szkh->delete("$fullpath")) {
            $result .= "$fullpath Deleted\n";
          }
          else { $result .= "\e[33m$fullpath Delete Failed: num_children: $node_data{'num_children'}\e[0m\n"; }
          print $result;
        }
      }
      else {
        my $fp = $fullpath;
        my @CNODES = $szkh->get_children("$fp");
        foreach my $ccpath (@CNODES) {
          process_path($fp,$ccpath);
        }
      }
    }
  }
  else { print "\e[33m$fullpath Didnt stat\e[0m\n"; }
}
