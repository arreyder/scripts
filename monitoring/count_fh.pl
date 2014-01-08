#!/usr/bin/perl
my %l_hash;
while (1) {
  sleep 4;
  my @lsof = `lsof`;
  my %hash;
  foreach  (@lsof){
   my($proc,$crap)=split(/\s+/,$_,2);
   chomp $proc;
   $hash{$proc}=$hash{$proc}+1;
  }
  foreach my $k (keys %hash) {
    if ($hash{$k} > $l_hash{$k}) {
      print "$k:$hash{$k}\n";
      $l_hash{$k} = $hash{$k};
    }
  }
}
