# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test;
BEGIN { plan tests => 5 };
use Sybase::TdsServer;

if (!test_with_dbi()) {
  skip('DBI and or DBD::Sybase missing') for (1..5);
}



sub test_with_dbi {
  eval {
    require 'DBI.pm';
  };
  if (!$@) {
    DBI::import;
    eval {
      require 'DBD/Sybase.pm';
    };
    if (!$@) {

      my %tests = (binary   => '62696e61727931323334',
                   bit      => '1',
                   char     => 'char123456',
                   decimal  => '1234.5678',
                   float4   => '1.1',
                   float8   => '8.8',
                   int1     => '1',
                   int2     => '2',
                   int4     => '4',
                   numeric  => '-1234.5678',
                  );

      DBD::Sybase::import;
      system('perl testserver.pl &');
      sleep 2;

      my $dbh = DBI->connect('dbi:Sybase:server=testserver;interfaces=testinterfaces', 'test', 'test', {RaiseError => 0, PrintError => 0});
      return 0 if !$dbh;

      foreach (sort keys %tests) {
        my $all = $dbh->selectall_arrayref($_);
        my $res = $tests{$_};
        ok($all->[0]->[0] =~ /^$res/);
      }




      $dbh->do('shutdown');
    }
  }
}

