# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test;
BEGIN { plan tests => 9 };
use Sybase::TdsServer;

my %connections;

ok(1); # If we made it this far, we're ok.

my %connect_info;
{
  local $/=undef;
  open DEF, 'connect_info' or last;
  %connect_info = split /[:\n]/,<DEF>;
  close DEF;
}

print "Servername ($connect_info{server}): ";
my $server = <>;
chomp $server;
$server ||= $connect_info{server};
print "User ($connect_info{user}): ";
my $user = <>;
chomp $user;
$user ||= $connect_info{user};
print "Password ($connect_info{password}): ";
my $password = <>;
chomp $password;
$password ||= $connect_info{password};

my $s = Sybase::TdsServer->new($server, \&conn_handler, \&disconn_handler, \&lang_handler, 1);
ok($s);
$s->set_handler('rpc', \&rpc_handler);
print <<EOF;











Start isql or sqsh and connect to the server with user and password just entered.

'shutdown' will shutdown this server.
'let me go' will close the connection.
'lots of output' will produce just this.
'all types 1' will return the first half of all possible column types.
'all types 2' will return the second half.
most of the types can be returned individually by naming them, like: binary, int2, ...

Everything else will just be reversed.

EOF

ok($s->run);

sub conn_handler {
  $connections{$_[0]} = join '|', @_[0..2];
  my $res = $user eq $_[1]->{username} && $password eq $_[1]->{password};
  return $res;
} 

sub disconn_handler {
  delete $connections{$_[0]};
}

sub rpc_handler {
  my ($connhandle, $proc, $params, $paramfmt) = @_;

  $s->send_header($connhandle, [{column_name => $proc, column_type => 'SYBVARCHAR', column_size => 30}]);

  my $res;
  for (0..@$params - 1) {
    last if ! ($res = $s->send_row($connhandle, [$$params[$_]]));
    select(undef, undef, undef, 0.1);
  };

  $s->send_done($connhandle, 0, 0, 100) if $res;
  return undef;
}

sub lang_handler {
  my ($connhandle, $query) = @_;

  if ($query =~ /^shutdown/) {
    $s->shutdown;
    return undef;
  }

  if ($query =~ /let me out/) {
    $s->disconnect($connhandle);
    return undef;
  }

  if ($query =~ /lots of output/) {
    my $numrec = 100;
    $s->send_header($connhandle, [{column_name => 'attention', column_type => 'SYBVARCHAR', column_size => 90}]);
    $s->send_row($connhandle, ["sending $numrec records, interrupt with ^C twice"]);
    $s->send_done($connhandle, 1, 0, 1);

    $s->send_header($connhandle, [{column_name => 'result', column_type => 'SYBVARCHAR', column_size => 30}]);

    my $res;
    for (0..$numrec) {
      print $_, "  ";
      last if ! ($res = $s->send_row($connhandle, ['mucho data ' . $_]));
      select(undef, undef, undef, 0.1);
    };

    $s->send_done($connhandle, 0, 0, 100) if $res;
    return undef;
  }

  if ($query =~ /all types 1/) {
    $s->send_header($connhandle, [
                            {column_name => 'SYBBINARY',        column_type => 'SYBBINARY',        column_size => 10},
                            {column_name => 'SYBBIT',           column_type => 'SYBBIT',           column_size => 0},
                            {column_name => 'SYBCHAR',          column_type => 'SYBCHAR',          column_size => 10},
                            {column_name => 'SYBDATETIME',      column_type => 'SYBDATETIME',      column_size => 0},
                            {column_name => 'SYBSMALLDATETIME', column_type => 'SYBSMALLDATETIME', column_size => 0},
                            {column_name => 'SYBDATETIMN(4)',   column_type => 'SYBDATETIMN',      column_size => 4},
                            {column_name => 'SYBDATETIMN(8)',   column_type => 'SYBDATETIMN',      column_size => 8},
                            {column_name => 'SYBDECIMAL',       column_type => 'SYBDECIMAL',       column_size => 8,   column_scale => 4},
                            {column_name => 'SYBFLT4',          column_type => 'SYBFLT4',          column_size => 0},
                            {column_name => 'SYBFLT8',          column_type => 'SYBFLT8',          column_size => 0},
                            {column_name => 'SYBFLTN(4)',       column_type => 'SYBFLTN',          column_size => 4},
                            {column_name => 'SYBFLTN(8)',       column_type => 'SYBFLTN',          column_size => 8},
                            {column_name => 'SYBINT1',          column_type => 'SYBINT1',          column_size => 0},
                            {column_name => 'SYBINT2',          column_type => 'SYBINT2',          column_size => 0},
                            {column_name => 'SYBINT4',          column_type => 'SYBINT4',          column_size => 0},
                            {column_name => 'SYBINTN(1)',       column_type => 'SYBINTN',          column_size => 1},
                           ]);
    $s->send_row($connhandle, [
                         'binary1234',
                         1,               # bit
                         'char123456',
                         '18.4.64',       # datetime
                         '21.9.2001',     # smalldatetime
                         '19.4.64',       # datetimn(4)
                         '20.4.64',       # datetimn(8)
                         1234.5678,       # decimal
                         12.34,           # flt4
                         123.456,         # flt8
                         43.21,           # fltn(4)
                         654.321,         # fltn(8)
                         12,              # int1
                         1234,            # int2
                         123456,          # int4
                         21,              # intn(1)
                        ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }

  if ($query =~ /all types 2/) {
    $s->send_header($connhandle, [
                            {column_name => 'SYBINTN(2)',       column_type => 'SYBINTN',          column_size => 2},
                            {column_name => 'SYBINTN(4)',       column_type => 'SYBINTN',          column_size => 4},
#                            {column_name => 'SYBSINT1',         column_type => 'SYBSINT1',         column_size => 0},
#                            {column_name => 'SYBUINT2',         column_type => 'SYBUINT2',         column_size => 0},
#                            {column_name => 'SYBUINT4',         column_type => 'SYBUINT4',         column_size => 0},
#                            {column_name => 'SYBUINTN(1)',      column_type => 'SYBUINTN',         column_size => 1},
#                            {column_name => 'SYBUINTN(2)',      column_type => 'SYBUINTN',         column_size => 2},
#                            {column_name => 'SYBUINTN(4)',      column_type => 'SYBUINTN',         column_size => 4},
                            {column_name => 'SYBMONEY',         column_type => 'SYBMONEY',         column_size => 0},
                            {column_name => 'SYBSMALLMONEY',    column_type => 'SYBSMALLMONEY',    column_size => 0},
                            {column_name => 'SYBMONEYN(4)',     column_type => 'SYBMONEYN',        column_size => 4},
                            {column_name => 'SYBMONEYN(8)',     column_type => 'SYBMONEYN',        column_size => 8},
                            {column_name => 'SYBNUMERIC',       column_type => 'SYBNUMERIC',       column_size => 8,   column_scale => 4},
                            {column_name => 'SYBVARBINARY',     column_type => 'SYBVARBINARY',     column_size => 10},
                            {column_name => 'SYBVARCHAR',       column_type => 'SYBVARCHAR',       column_size => 10},
                           ]);
    $s->send_row($connhandle, [
                         4321,            # intn(2)
                         654321,          # intn(4)
#                         -12,             # sint1
#                         2345,            # uint2
#                         234567,          # uint4
#                         32,              # uintn(1)
#                         5432,            # uintn(2)
#                         765432,          # uintn(4)
                         123.9876,        # money
                         1.2345,          # smallmoney
                         45.6789,         # moneyn(4)
                         12.3456,         # moneyn(8)
                         9876.5432,       # numeric
                         'varbinary',
                         'varchar',
                        ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }

  if ($query =~ /^binary/) {
    $s->send_header($connhandle, [ {column_name => 'SYBBINARY',        column_type => 'SYBBINARY',        column_size => 10}, ]);
    $s->send_row($connhandle, [ 'binary1234' ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }

  if ($query =~ /^bit/) {
    $s->send_header($connhandle, [ {column_name => 'SYBBIT',        column_type => 'SYBBIT',        column_size => 0}, ]);
    $s->send_row($connhandle, [ 1 ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }

  if ($query =~ /^char/) {
    $s->send_header($connhandle, [ {column_name => 'SYBCHAR',          column_type => 'SYBCHAR',          column_size => 10}, ]);
    $s->send_row($connhandle, [ 'char123456' ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }

  if ($query =~ /^datetime/) {
    $s->send_header($connhandle, [ {column_name => 'SYBDATETIME',          column_type => 'SYBDATETIME',          column_size => 0}, ]);
    $s->send_row($connhandle, [ 'Apr 18, 1964' ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }

  if ($query =~ /^decimal/) {
    $s->send_header($connhandle, [ {column_name => 'SYBDECIMAL',          column_type => 'SYBDECIMAL',          column_size => 8, column_scale => 4}, ]);
    $s->send_row($connhandle, [ 1234.5678 ]);
    $s->send_row($connhandle, [ 1234.567 ]);
    $s->send_row($connhandle, [ 1234.56 ]);
    $s->send_row($connhandle, [ 1234.5 ]);
    $s->send_row($connhandle, [ 1234 ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }

  if ($query =~ /^numeric/) {
    $s->send_header($connhandle, [ {column_name => 'SYBNUMERIC',          column_type => 'SYBNUMERIC',          column_size => 8, column_scale => 4}, ]);
    $s->send_row($connhandle, [ -1234.5678 ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }

  if ($query =~ /^float4/) {
    $s->send_header($connhandle, [ {column_name => 'SYBFLT4',          column_type => 'SYBFLT4',          column_size => 0}, ]);
    $s->send_row($connhandle, [ 1.1 ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }

  if ($query =~ /^float8/) {
    $s->send_header($connhandle, [ {column_name => 'SYBFLT8',          column_type => 'SYBFLT8',          column_size => 0}, ]);
    $s->send_row($connhandle, [ 8.8 ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }

  if ($query =~ /^floatn/) {
    $s->send_header($connhandle, [ {column_name => 'SYBFLTN(4)',          column_type => 'SYBFLTN',          column_size => 4},
                                   {column_name => 'SYBFLTN(8)',          column_type => 'SYBFLTN',          column_size => 8}, ]);
    $s->send_row($connhandle, [ 4.4, 8.8 ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }

  if ($query =~ /^int1/) {
    $s->send_header($connhandle, [ {column_name => 'SYBINT1',          column_type => 'SYBINT1',          column_size => 0}, ]);
    $s->send_row($connhandle, [ 1 ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }

  if ($query =~ /^int2/) {
    $s->send_header($connhandle, [ {column_name => 'SYBINT2',          column_type => 'SYBINT2',          column_size => 0}, ]);
    $s->send_row($connhandle, [ 2 ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }

  if ($query =~ /^int4/) {
    $s->send_header($connhandle, [ {column_name => 'SYBINT4',          column_type => 'SYBINT4',          column_size => 0}, ]);
    $s->send_row($connhandle, [ 4 ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }

  if ($query =~ /^intn/) {
    $s->send_header($connhandle, [ {column_name => 'SYBINT(1)',          column_type => 'SYBINTN',          column_size => 1},
                                   {column_name => 'SYBINT(2)',          column_type => 'SYBINTN',          column_size => 2},
                                   {column_name => 'SYBINT(4)',          column_type => 'SYBINTN',          column_size => 4}, ]);
    $s->send_row($connhandle, [ 1, 2, 4 ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }

  if ($query =~ /^money/) {
    $s->send_header($connhandle, [ {column_name => 'SYBMONEY',          column_type => 'SYBMONEY',          column_size => 0}, ]);
    $s->send_row($connhandle, [ 88.8888 ]);
    $s->send_row($connhandle, [ 1 ]);
    $s->send_row($connhandle, [ 0.05 ]);
    $s->send_row($connhandle, [ 65536 ]);
    $s->send_row($connhandle, [ -1 ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }
    
  if ($query =~ /^SYB/i) {
    my ($type, $size, $scale, $value) = split /\s*,\s*/, $query;
    $type = uc $type;
    $s->send_header($connhandle, [ {column_name => $type,          column_type => $type,          column_size => $size, column_scale => $scale} ]);
    $s->send_row($connhandle, [ $value ]);
    $s->send_done($connhandle, 0, 0, 1);
    return undef;
  }

    chomp $query;
    my $answer = reverse $query;

    return [
             [{column_name => 'result', column_type => 'SYBVARCHAR', column_size => 30}],
             [$answer],
           ];
}
