#!/usr/bin/perl
use JSON;
use strict;
use warnings;
use utf8;

my $end = 1354844776 * 1000;
my $before = (1354844776 - 3600) * 1000;
binmode STDOUT, ":utf8";
print "Range is $before to $end\n";
my $json;

open FILE, "1355410801.json" or die $!;
while (<FILE>) {
my %data = %{decode_json($_)};
 foreach my $entity (@{$data{'entities'}}) {
   foreach my $check (@{$entity->{'checks'}}) {
     if (($check->{'created_at'} < $end && $check->{'created_at'} >= $before) || ($check->{'updated_at'} <= $end && $check->{'updated_at'} >= $before)) {
       print $entity->{'id'} . " " . $check->{'id'} . " " . $check->{'created_at'} . " " . $check->{'updated_at'} . " " . $check->{'type'};
       if ($check->{'monitoring_zones_poll'}) {
         print " " . join(",",@{$check->{'monitoring_zones_poll'}}) . "\n";
       }
       else {
        print "\n";
      }
     }
   }
 }
}
