package Sybase::TdsServer;

#------------------------------------------------------------------------------------------------------------

=head1 NAME

Sybase::TdsServer - A simple module to create a tds-server (like Sybase or freetds)

=head1 SYNOPSIS

  use Sybase::TdsServer;
  my $server = Sybase::TdsServer->new($servername,
                                      \&connect_handler,
                                      \&disconnect_handler,
                                      \&language_handler);
  $server->set_handler($handler, \&handling_sub);
  $server->run;
  $server->disconnect($connect_handle);
  $server->shutdown;
  $server->send_header($connect_handle, \@header);
  $server->send_row($connect_handle, \@row);
  $server->send_done($connect_handle, $status, $tran_state, $numrows);
  $server->send_eed($connect_handle, $msg_nr, $class, $tran_state, $msg, $server, $procedure, $line);

=head1 DESCRIPTION

Sybase::TdsServer lets you create a server which listens to the TDS protocol spoken by Sybase clients.
The server will accept multiple connections without threads or forking.

One possible use could be to create a server that listens to a Replication Agent running in a Sybase Server.
This server could catch the data comming from the agent and do some further processing on it.

=head1 REQUIREMENTS

None, so far.

=head1 METHODS

=cut

require 5.005_62;
use strict;
use warnings;

use Sybase::TdsConstants;
use Sybase::TdsSocket;

use IO::Socket;
use IO::Select;
use Math::BigInt;

our $VERSION = '0.03';

our %coltypes = (#name                num_type  user_type  has_len  has_prec_scale  num_bytes  pack_mask
                 "SYBBINARY"        => [ 45,        3,         1,         0,             0,        'a'],
                 "SYBBIT"           => [ 50,       16,         0,         0,             1,        'C'],
                 "SYBCHAR"          => [ 47,        1,         1,         0,             0,        'a'],
                 "SYBDATETIME"      => [ 61,       12,         0,         0,             8,        ''],
                 "SYBSMALLDATETIME" => [ 58,       22,         0,         0,             4,        ''],
                 "SYBDATETIMN"      => [111,       15,         1,         0,             0,        ''],
                 "SYBDECIMAL"       => [106,       27,         0,         1,             0,        \&_hexify_decimal],
                 "SYBFLT4"          => [ 59,       23,         0,         0,             4,        'f'],
                 "SYBFLT8"          => [ 62,        8,         0,         0,             8,        'd'],
                 "SYBFLTN"          => [109,       14,         1,         0,             0,        \&_float_length],
                 "SYBINT1"          => [ 48,        5,         0,         0,             1,        'C'],
                 "SYBINT2"          => [ 52,        6,         0,         0,             2,        'v'],
                 "SYBINT4"          => [ 56,        7,         0,         0,             4,        'V'],
                 "SYBINT8"          => [  0,        0,         0,         0,             8,        'C'], #FIXME no description of INT8
                 "SYBINTN"          => [ 38,       13,         1,         0,             0,        \&_int_length],
                 "SYBSINT1"         => [ 64,        0,         0,         0,             1,        'C'], #FIXME usertype unknown
                 "SYBUINT2"         => [ 65,       52,         0,         0,             2,        'v'],
                 "SYBUINT4"         => [ 66,       53,         0,         0,             4,        'V'],
                 "SYBUINT8"         => [ 67,       54,         0,         0,             8,        ''],  #FIXME don't know how to handle this
                 "SYBUINTN"         => [ 68,        0,         1,         0,             0,        'C'], #FIXME usertype unknown
                 "SYBMONEY"         => [ 60,       11,         0,         0,             8,        \&_money],
                 "SYBSMALLMONEY"    => [122,       21,         0,         0,             4,        \&_money4],
                 "SYBMONEYN"        => [110,       17,         1,         0,             0,        \&_moneyn],
                 "SYBNUMERIC"       => [108,       28,         0,         1,             0,        \&_hexify_decimal],
                 "SYBVARBINARY"     => [ 37,        4,         1,         0,             0,        'a'],
                 "SYBVARCHAR"       => [ 39,        2,         1,         0,             0,        'a'],
#                 "SYBREAL"          => [ 59,     not supported by now
#                 "SYBTEXT"          => [ 35,
#                 "SYBNTEXT"         => [ 99,
#                 "SYBIMAGE"         => [ 34,
#                 "SYBVOID"          => [ 31,
#                 "SYBNVARCHAR"      => [103,
                );

our %datatypes = map { ($coltypes{$_}[0], $_) } keys %coltypes;

our %token_dispatcher = (TDS_LOGOUT      , \&_tds_logout,
                         TDS_OPTIONCMD   , \&_tds_optioncmd,
                         TDS_LANGUAGE    , \&_tds_language,
                         TDS_DBRPC       , \&_tds_dbrpc,
                         TDS_RPC         , \&_tds_dbrpc,
                         TDS_PARAMFMT    , \&_tds_paramfmt,
                         TDS_PARAMFMT2   , \&_tds_paramfmt,
                         TDS_PARAMS      , \&_tds_params,
                        );




#-----------------------------------------------------------------------------------------------------

=head2 new - the constructor

Parameters:

=over

=item Servername

The name of the server that shall be created. This name must exist in the interfaces file,
from which the ip-address and the portnumber will be fetched.

=item Connect Handler

A reference to a subroutine that will be called whenever a client connects to the server.
Parameters for the connect handler are:

=over

=item connection handle

a handle identifying this connection.

=item user

the login provided by the client

=item password

the password provided by the client

=back

=item Disconnect Handler

A reference to a subroutine that will be called whenever a client disconnects from the server.
Parameters for the disconnect handler are:

=over

=item connection handle

a handle identifying this connection.

=back

=item Language Handler

A reference to a subroutine that will be called whenever a client sends data to the server.
Parameters for the language handler are:

=over

=item connection handle

a handle identifying this connection.

=item text

the text that was sent by the client

=back

=back

More on handlers further down.

Returnvalues:

The constructor returns a TdsServer-object if it succeeds, otherwise undef.

Example:

 my $s = Sybase::TdsServer->new($servername, 
                                \&conn_handler, 
                                \&disconn_handler, 
                                \&lang_handler);                                     

For simple examples of the handler, look at the file test.pl in this distribution.

=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub new {
  my $that = shift;
  my $class = ref($that) || $that;

  my $self = {
    SERVERNAME      => $_[0],
    CONN_HANDLER    => $_[1],
    DISCONN_HANDLER => $_[2],
    LANG_HANDLER    => $_[3],
    DEBUG           => $_[4],
  };
 
  bless $self, $class;

#---- get server ip,port
  my ($ip, $port) = Sybase::TdsSocket->server_info($self->{SERVERNAME});
  if (!defined $ip) {
    warn "Servername not found in interfaces\n" if $self->{DEBUG};
    return undef;
  }

#---- create socket
  $self->{LISTEN_SOCKET} = IO::Socket::INET->new(LocalHost => $ip,
                                                 LocalPort => $port,
                                                 Listen    => 20,
                                                 Proto     => 'tcp',
                                                );
  if (! $self->{LISTEN_SOCKET}) {
    warn "Could not create Socket $ip:$port\n" if $self->{DEBUG}; 
    return undef; 
  }

#---- create select object for multiplexing
  $self->{READERS} = IO::Select->new() or return undef;
  if (! $self->{READERS}) {
    warn "Could not create Select object\n" if $self->{DEBUG};
    return undef;
  }

  $self->{READERS}->add($self->{LISTEN_SOCKET});

#---- setup defaullt capabilities
  $self->{CAPABILITIES_REQ} = chr(0) x 8;
  vec($self->{CAPABILITIES_REQ}, $_, 1) = 1 for (TDS_REQ_LANG,
#                                                 TDS_REQ_RPC,
                                                 TDS_REQ_PARAM,  
                                                 TDS_DATA_INT1,  
                                                 TDS_DATA_INT2, 
                                                 TDS_DATA_INT4, 
                                                 TDS_DATA_BIT,   
                                                 TDS_DATA_CHAR,  
                                                 TDS_DATA_VCHAR, 
                                                 TDS_DATA_BIN,   
                                                 TDS_DATA_VBIN, 
                                                 TDS_DATA_MNY4, 
                                                 TDS_DATA_MNY8, 
                                                 TDS_DATA_DATE4,
                                                 TDS_DATA_DATE8,
                                                 TDS_DATA_FLT4, 
                                                 TDS_DATA_FLT8, 
                                                 TDS_DATA_NUM,  
                                                 TDS_DATA_DEC,  
                                                 TDS_DATA_INTN, 
                                                 TDS_DATA_MONEYN,
                                                 TDS_DATA_FLTN,
                                                 TDS_CON_OOB,
                                                 TDS_CON_INBAND,
                                                 TDS_WIDETABLE,
                                                );
  $self->{CAPABILITIES_REQ} = reverse $self->{CAPABILITIES_REQ};

  $self->{CAPABILITIES_RES} = chr(0) x 8;
  vec($self->{CAPABILITIES_RES}, $_, 1) = 1 for (TDS_RES_NOMSG,
                                                 TDS_DATA_NOTEXT,
                                                 TDS_DATA_NOIMAGE,
                                                 TDS_DATA_NOLCHAR,
                                                 TDS_DATA_NOLBIN,
                                                 TDS_PROTO_NOTEXT,
                                                 TDS_PROTO_NOBULK,
                                                 TDS_DATA_NOSENSITIVITY,
                                                 TDS_DATA_NOBOUNDARY,
                                                 TDS_RES_NOTDSDEBUG,
                                                 TDS_DATA_NOINT8,
                                                 TDS_OBJECT_NOJAVA1,
                                                 TDS_OBJECT_NOCHAR,
                                                 TDS_OBJECT_NOBINARY,
                                                 TDS_DATA_NONLBIN,
                                                 TDS_IMAGE_NONCHAR,
                                                 TDS_BLOB_NONCHAR_16,
                                                 TDS_BLOB_NONCHAR_8,
                                                 TDS_BLOB_NONCHAR_SCSU,
                                                );
  $self->{CAPABILITIES_RES} = reverse $self->{CAPABILITIES_RES};

  return $self;
}

#-----------------------------------------------------------------------------------------------------

=head2 set_handler - setting event handling routines

Parameters:

=over

=item type of handler

type of handler is one of the following:

 capability
 optioncmd
 rpc

=item handler

handler is a reference to a subroutine which is called when the event arrives

=back

handler types:

All handlers recieve a connection handle as their first parameter.

=over

=item optioncmd

 Will be called whenever a client sends an OPTIONCMD token to the server.
 Parameters for the optioncmd handler are:

=over

=item command

The decimal value of the command of the OPTIONCMD token. One of:
 1 = set     - set an option
 2 = deafult - set option to default
 3 = list    - request current setting
 4 = info    - report current setting

=item option

The decimal value of the option, values range from 0 to 38.

=item argument length

The length of the argument for the option.

=item argument

The argument for the option.

=back

=item rpc

 Will be called whenever a client sends an rpc request.
 FIXME: not implemented yet!
 Parameters for the rpc handler are:

=over

=item command

The command

=back

=item capability

 Will be called whenever capability requests come from the client.
 Parameters for the capability handler are:
 
=over

=item capabilities requested

=item capabilities offered

=back

Both are binary values constaining one bit for each capability

=back

Example:

 $s->set_handler('optioncmd' => \&option_handler);

=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub set_handler {
  my $self = shift;
  $self->{HANDLERS}->{$_[0]} = $_[1];
}
#-----------------------------------------------------------------------------------------------------

=head2 run - running the server

Parameters:

none

Example:

$s->run;

=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub run {
  my $self = shift;

  $self->{RUN} = 1;

  while ($self->{RUN}) {
    
    my @ready = $self->{READERS}->can_read;

    for my $handle (@ready) {

#---- handling connects
      if ($handle eq $self->{LISTEN_SOCKET}) {
        my $connect = $self->{LISTEN_SOCKET}->accept();
        $self->{READERS}->add($connect);
        if (!$self->_client_connect($connect)) {
          $self->disconnect($connect);
        }
      } else {

#---- handling data
        $self->_client_input($handle);
      }
    }

  }

#---- drop connections
  foreach my $socket (keys %{$self->{SOCKETS}}) {
    $self->disconnect($self->{SOCKETS}->{$socket}->{SOCKET});
  }

  return 1;
}

#-----------------------------------------------------------------------------------------------------

=head2 disconnect - disconnects a client forcibly

Parameters:

connect handle

Example:

$s->disconnect($connect_handle);

=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub disconnect {
  my ($self, $socket, $send_close) = @_;

  $self->_close($self->{SOCKETS}->{$socket}->{TDSSOCKET}) if $send_close;
  $self->{READERS}->remove($socket);
  close $socket;
  $self->_client_disconnect($socket);
  delete $self->{SOCKETS}->{$socket};
}

#-----------------------------------------------------------------------------------------------------

=head2 shutdown - shuts the server down. 

The program will continue execution after the run.

Parameters:

none

Example:

$s->shutdown;

=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub shutdown {
  my $self = shift;

  $self->{RUN} = 0;
}

#-----------------------------------------------------------------------------------------------------

=head2 send_header - sends header information for a resultset

Parameters:

Connection Handle.

Reference to an array containing header information.

See 'Handlers' for more on header information.

Example:

 $s->send_header($conn_handle, 
                 [{ column_name => 'result', 
                    column_type => 'SYBVARCHAR', 
                    column_size => 30
                 }] 
                );

=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub send_header {
  my ($self, $socket, $header) = @_;

  return if ! defined $header;

  my $tdssocket = $self->{SOCKETS}->{$socket}->{TDSSOCKET};

  $self->{SOCKETS}->{$socket}->{LAST_HEADER} = $header;

  my $numcols = 0;
  my $fmtlength = 0;
  my $rowfmt = '';
  my ($col_head, $colhead_len);
  foreach (@$header) {
    ($col_head, $colhead_len) = _colheader_with_length($_), next if $coltypes{"$_->{column_type}"}->[2];
    ($col_head, $colhead_len) = _colheader_with_precision($_), next if $coltypes{"$_->{column_type}"}->[3];
    ($col_head, $colhead_len) = _colheader_without_length($_);
  } continue {
    $rowfmt .= $col_head;
    $numcols++;
    $fmtlength += $colhead_len;
  }
  
  push @{$self->{SOCKETS}->{$socket}->{LAST_HEADER}}, $numcols;

  my $data = pack("C v v", TDS_ROWFMT, $fmtlength + 2, $numcols) . $rowfmt . chr(TDS_CONTROL) . chr($numcols) . chr(0) x ($numcols + 1);

  $tdssocket->packet_type(TDS_BUF_RESPONSE);
  $tdssocket->write($data);
}

#-----------------------------------------------------------------------------------------------------

=head2 send_row - sends a row of the resultset

Parameters:

Connection Handle.

Reference to an array containing row data.

See 'Handlers' for more on row data.

Example:

 $s->send_row($conn_handle, ['data1', 'data2', 'data3'] );

=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub send_row {
  my ($self, $socket, $row) = @_;

  return 0 if ! defined $row;

  my $tdssocket = $self->{SOCKETS}->{$socket}->{TDSSOCKET};

  my $rowdata = '';
  my $coldata;
  foreach (0..$#$row) {
    my $header = $self->{SOCKETS}->{$socket}->{LAST_HEADER}->[$_];
    if ($coltypes{$header->{column_type}}->[2] || $coltypes{$header->{column_type}}->[3]) {     # variable length
      if (ref $coltypes{$header->{column_type}}->[5]) {
        $coldata = $coltypes{$header->{column_type}}->[5]($row->[$_], $header->{column_size}, $header->{column_scale});
      } else {
        $coldata = pack 'C' . $coltypes{$header->{column_type}}->[5] . length($row->[$_]) , length($row->[$_]), $row->[$_];
      }
    } else {
      if (ref $coltypes{$header->{column_type}}->[5]) {
        $coldata = $coltypes{$header->{column_type}}->[5]($row->[$_], $header->{column_size}, $header->{column_scale});
      } else {
        $coldata = pack $coltypes{$header->{column_type}}->[5], $row->[$_];
      }
    }

    $rowdata .= $coldata;
  }

  my $data = pack("C", TDS_ROW) . $rowdata;

  $tdssocket->packet_type(TDS_BUF_RESPONSE);
  $tdssocket->write($data);

#---- check for interupt by client
  my $rin = chr(0);
  vec($rin,fileno($self->{SOCKETS}->{$socket}->{SOCKET}),1) = 1;
  if (select($rin, undef, undef, 0)) {
    $self->_get_attn($tdssocket);
    $tdssocket->send_done(0x0020, 0, 0, MSG_OOB);
    return 0;
  }
  return 1;
}

#-----------------------------------------------------------------------------------------------------

=head2 send_done - sends a done token to the client

Parameters:

=over

=item Connection Handle.

=item Status to be sent in done token.

Status is a bitmap with the following meaning:

 0x0000   done final   Result complete, successful
 0x0001   done more    Result complete, more results to follow
 0x0002   done error   Error occured in current command
 0x0004   done inxact  Transaction in progress for command
 0x0008   done proc    Result comes from a stored procedure
 0x0010   done count
 0x0020   done attn    to acknowlegde an attention
 0x0040   done event   part of event notification

=item Status of the current transaction.

Status of the current transaction is one of the following:

 0  not in tran
 1  tran succeed
 2  tran in progress
 3  statement abort
 4  tran abort

=item Number of rows.

=back

Example:

$s->send_done($conn_handle, 0x00, 0, 1);

=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub send_done {
  my ($self, $socket, $status, $tran, $numrows, $oob) = @_;

  $status ||= 0;    # set to done final if not set
  $tran ||= 0;    # set to 0 if not set
  $numrows ||= 0;    # set to 0 if not set

  $self->{SOCKETS}->{$socket}->{TDSSOCKET}->send_done($status, $tran, $numrows, $oob);
}

#-----------------------------------------------------------------------------------------------------

=head2 send_eed - sends a eed token to the client

Parameters:

=over

=item Connection Handle.

=item Message Nr.

=item Class

Class is the severity of the error.

=item Status of the current transaction.

Status of the current transaction is one of the following:

 0  not in tran
 1  tran succeed
 2  tran in progress
 3  statement abort
 4  tran abort

=item Message

The message text.

=item Servername

=item Procedurename (optional)

=item Linenr. (optional)

=back

Example:

$s->send_eed($conn_handle, 1234, 0, 0, 'error message', 'this_server');

=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub send_eed {
  my ($self, $socket, $msg_nr, $class, $tran, $msg, $server, $proc, $line) = @_;

  $msg_nr ||= 0;    # set to 0 if not set
  $class ||= 0;    # set to 0 if not set
  $tran ||= 0;    # set to 0 if not set
  $msg = '' if ! defined $msg;
  $server = '' if ! defined $server;
  $proc = '' if ! defined $proc;
  $line ||= 0;    # set to 0 if not set

  $self->{SOCKETS}->{$socket}->{TDSSOCKET}->send_eed($msg_nr, $class, $tran, $msg, $server, $proc, $line);
  $self->{SOCKETS}->{$socket}->{TDSSOCKET}->send_done(TDS_DONE_ERROR);
}





#============================================================================================================
# internal functions
#============================================================================================================


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# _client_connect is called by IO::Multiplex whenever a client connects
# it reads the connect info (user, password), calls the connect_handler
# and either establishes or drops the connection to the client
#
sub _client_connect {
  my $self = shift;
  my $socket = shift;


#---- create tdssocket  
  $self->{SOCKETS}->{$socket}->{TDSSOCKET} = Sybase::TdsSocket->new($socket);

#---- get login info
  my $loginrecref = $self->_read_login($socket);

  return $self->_make_connect($socket, $loginrecref);
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# _make_connect is called to create the connection
# this is necessary because server-to-server connections are established differently from client-con.
#
sub _make_connect {
  my $self = shift;
  my $socket = shift;
  my $loginrecref = shift;

#---- if this is a server-to-server connect
  if ($loginrecref->{type} == 0 and !$loginrecref->{username}) {
    $self->_login_ack($socket, 5, $loginrecref->{tds_version});
    $self->{SOCKETS}->{$socket}->{TDSSOCKET}->send_done(TDS_DONE_FINAL,2);
    return 1;
  }  

#---- call connect handler
  my $res = $self->{CONN_HANDLER}($socket, $loginrecref);

  if (!$res) {
    $self->_login_ack($socket, 6, $loginrecref->{tds_version});
    $self->send_eed($socket, 7221, 14, 2, 'Login failed.', $self->{SERVERNAME}, 'unknown', 0);
    $self->{DISCONN_HANDLER}($socket);
    warn "client connection failed $socket\n" if $self->{DEBUG};
    return 0;
  } else {
    $self->_login_ack($socket, 5, $loginrecref->{tds_version});
    $self->_capabilities($socket);
    $self->{SOCKETS}->{$socket}->{TDSSOCKET}->send_done(TDS_DONE_FINAL);
  }

  $self->{SOCKETS}->{$socket}->{SOCKET} = $socket;
  $self->{SOCKETS}->{$socket}->{USER} = $loginrecref->{username};
  $self->{SOCKETS}->{$socket}->{PASSWORD} = $loginrecref->{password};

  warn "client connected $socket\n" if $self->{DEBUG};
  return 1;
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# _client_disconnect is called by IO::Multiplex whenever a client disconnects
# it calls the disconnect_handler
#
sub _client_disconnect {
  my $self = shift;
  my $socket = shift;

  $self->{DISCONN_HANDLER}($self->{SOCKETS}->{$socket}->{TDSSOCKET});
  warn "client disconnected $socket\n" if $self->{DEBUG};
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# _client_input is called whenever a client sends input to the server
# it reads the input, calls the language handler, gets the resultset and returns it to the client
#
sub _client_input {
  my $self = shift;
  my $socket = shift;  

  my $tdssocket = $self->{SOCKETS}->{$socket}->{TDSSOCKET};
  my ($header, $token, $query) = $self->_get_query($tdssocket);

  my $packet_type = unpack('C', $header);
  
  if ($packet_type == TDS_BUF_LOGIN) {
    my $loginrecref = $self->_read_login($socket, unpack('n', substr($header, 2,2)), $header, pack('C',$token).$query);
    return $self->_make_connect($socket, $loginrecref);
  }
  
  if ($packet_type == TDS_BUF_SETUP) {
    $self->{WINDOWSIZE} = unpack('C', substr($header, 7, 1));
    $self->{CHANNEL} = unpack('v', substr($header, 4, 2));
    $self->_proto_ack($tdssocket);
    return;
  }

  if ($packet_type == TDS_BUF_CLOSE) {
    $self->disconnect($socket, 1); 
    return;
  }


  $self->disconnect($socket), return if (!defined $token);

  if (! exists $token_dispatcher{$token} or ! $token_dispatcher{$token}($self, $socket,$token, $query)) {
    $self->send_eed($socket, 7222, 10, 0, 'Unsupported token (' . pack('H', $token) . ') recieved.', $self->{SERVERNAME}, 'unknown', 0);
  }

  return;
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# _colheader_with_length constructs a ROWFMT entry for a given column with a given length
#
sub _colheader_with_length {
  my $header = $_[0];

  my $colname    = $header->{column_name};
  my $namelength = length($colname);
  my $status     = 0x10;                                       # FIXME status is a bitmap, can be updatable, key, nullallowed, see TDS doc
  my $usertype   = $coltypes{$header->{column_type}}->[1];
  my $datatype   = $coltypes{$header->{column_type}}->[0];
  my $length     = $header->{column_size};
  my $localelen  = 0;                                          # FIXME no locale

  my $rowfmt = pack "C a$namelength C V C C C", $namelength, $colname, $status, $usertype, $datatype, $length, $localelen;

  return $rowfmt, $namelength + 9;
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# _colheader_with_precision constructs a ROWFMT entry for a given column with a given precision, scale
#
sub _colheader_with_precision {
  my $header = $_[0];

  my $colname    = $header->{column_name};
  my $namelength = length($colname);
  my $status     = 0x10;                                       # FIXME status is a bitmap, can be updatable, key, nullallowed, see TDS doc
  my $usertype   = $coltypes{$header->{column_type}}->[1];
  my $datatype   = $coltypes{$header->{column_type}}->[0];
  my $length     = $header->{column_size};
  my $precision  = $header->{column_size};
  my $scale      = $header->{column_scale};
  my $localelen  = 0;                                          # FIXME no locale

  my $rowfmt = pack "C a$namelength C V C C C C C", $namelength, $colname, $status, $usertype, $datatype, $length, $precision, $scale, $localelen;

  return $rowfmt, $namelength + 11;
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# _colheader_without_length constructs a ROWFMT entry for a given column with a fixed length
#
sub _colheader_without_length {
  my $header = $_[0];

  my $colname    = $header->{column_name};
  my $namelength = length($colname);
  my $status     = 0x10;                                       # FIXME status is a bitmap, can be updatable, key, nullallowed, see TDS doc
  my $usertype   = $coltypes{$header->{column_type}}->[1];
  my $datatype   = $coltypes{$header->{column_type}}->[0];
  my $length     = $coltypes{$header->{column_type}}->[4];
  my $localelen  = 0;                                          # FIXME no locale

  my $rowfmt = pack "C a$namelength C V C C", $namelength, $colname, $status, $usertype, $datatype, $localelen;

  return $rowfmt, $namelength + 8;
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# _hexify_decimal converts a number into a hexstring
#
sub _hexify_decimal {

  my $int = $_[0];
  my $size = $_[1] - 1;
  my $scale = $_[2];

  my $len = int( log("10E$size") / log(256)) + 1;

  $int =~ s/(\.\d{$scale}).*/$1/;
  my ($decpart) = $int =~ /(\.\d*)/;
  $decpart ||= '.';
  $int .= '0' x ($scale + 1 - length($decpart));
  $int =~ s/[-+,. ]//g;
  my $dec = Math::BigInt->new($int);
  my $hex = '';

  while ($dec > 0) {
    my $mod = $dec % 256;
    $hex = pack('C', $mod) . $hex;
    $dec = $dec / 256;
  }
  $hex = chr(0) . $hex while (length($hex) < $len);
  $hex = (($_[0] =~ /-/) ? chr(1) : chr(0)) . $hex;
  $len = length($hex);

  return pack('C a' . $len, $len, $hex);
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# _float_length converts a number into 4 or 8 byte float
#
sub _float_length {
  my ($float, $len) = @_;

  return chr(0) if ! defined $float;

  return ($len == 4) ? pack('C f', 4, $float) : pack('C d', 8, $float);
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# _money converts a number into a money-hexstring
#
sub _money {

  my $int = $_[0];
  $int =~ s/(\.\d{4}).*/$1/;
  my ($decpart) = $int =~ /(\.\d*)/;
  $decpart ||= '.';
  $int .= '0' x (5 - length($decpart));
  $int =~ s/[+,. ]//g;
  my $dec = Math::BigInt->new($int);
  my $comp = Math::BigInt->new(0x1000000);
  $comp *= 0x1000000;
  $comp *= 0x10000;
  $dec = $comp + $dec if $dec < 0;

  my $hex = '';

  while ($dec > 0) {
    my $mod = $dec % 256;
    $hex .= pack('C', $mod);
    $dec = $dec / 256;
  }
  my $len = length($hex);
  $hex .= chr(0) x (8 - $len);
  $hex = substr($hex, 4, 4) . substr($hex, 0, 4);

  return pack('a8', $hex);
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# _money4 converts a number into a smallmoney-hexstring
#
sub _money4 {

  my $int = $_[0];
  $int =~ s/(\.\d{4}).*/$1/;
  my ($decpart) = $int =~ /(\.\d*)/;
  $decpart ||= '.';
  $int .= '0' x (5 - length($decpart));
  $int =~ s/[+,. ]//g;
  my $dec = Math::BigInt->new($int);
  my $comp = Math::BigInt->new(0xffffffff);
  $comp += 1;
  $dec = $comp + $dec if $dec < 0;

  my $hex = '';

  while ($dec > 0) {
    my $mod = $dec % 256;
    $hex .= pack('C', $mod);
    $dec = $dec / 256;
  }
  my $len = length($hex);
  $hex .= chr(0) x (4 - $len);

  return pack('a4', $hex);
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# _moneyn converts a number into nullable money/smallmoney
#
sub _moneyn {
  my ($int, $len, $scale) = @_;

  return chr(0) if ! defined $int;

  if ($len == 4) {
    return pack('C a4', 4, _money4($int, $len, $scale));
  } else {
    return pack('C a8', 8, _money($int, $len, $scale));
  }
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# _int_length converts a number into 1, 2 or 4 byte int
#
sub _int_length {
  my ($int, $len, $unpack) = @_;

  return chr(0) if ! defined $int;

  if (defined $unpack) {
    if ($len == 1) {
      return unpack('C', $int);
    } elsif ($len == 2) {
      return unpack('v', $int);
    } else {
      return unpack('V', $int);
    }
  } else {
    if ($len == 1) {
      return pack('C C', 1, $int);
    } elsif ($len == 2) {
      return pack('C v', 2, $int);
    } else {
      return pack('C V', 4, $int);
    }
  }
}


#-----------------------------------------------------------------------------------------------------------------
# _read_login reads the login packet(s) and returns the login hashref
# see 'structures' for info on login hashref

sub _read_login {
  my $self = shift;
  my ($socket, $p_len, $header, $data) = @_;
  my $tdssocket = $self->{SOCKETS}->{$socket}->{TDSSOCKET};

  my %loginrec;
  
#---- first part of loginpacket
  ($p_len, $header, $data) = $tdssocket->read_packet() if ! $p_len;
  
#---- second part, if necessary
  if ($p_len == 512) {
    my ($p_len2, $header2, $data2) = $tdssocket->read_packet();
    $data .= $data2;
    $p_len += $p_len2;
  }

#---- unpack packet step by step
  my $len = unpack 'C', substr($data, 30, 1);
  $loginrec{hostname}                = substr($data, 0, $len);
  
  $len = unpack 'C', substr($data, 61, 1);
  $loginrec{username}                = substr($data, 31, $len);
  
  $len = unpack 'C', substr($data, 92, 1);
  $loginrec{password}                = substr($data, 62, $len);
  
  $len = unpack 'C', substr($data, 123, 1);
  $loginrec{hostprocess}             = substr($data, 93, $len);

  $loginrec{byteorder2}              = unpack 'C', substr($data, 124, 1);
  $loginrec{byteorder4}              = unpack 'C', substr($data, 125, 1);
  $loginrec{ascii_ebcdic}            = unpack 'C', substr($data, 126, 1);
  $loginrec{float_representation}    = unpack 'C', substr($data, 127, 1);
  $loginrec{datetime_representation} = unpack 'C', substr($data, 128, 1);
  $loginrec{interfacespare}          = unpack 'C', substr($data, 129, 1);
  $loginrec{type}                    = unpack 'C', substr($data, 130, 1);

  $len = unpack 'C', substr($data, 170, 1);
  $loginrec{appname}                 = substr($data, 140, $len);

  $len = unpack 'C', substr($data, 201, 1);
  $loginrec{servername}              = substr($data, 171, $len);

  $loginrec{remote_password}         = substr($data, 202, 254);

  my ($v1, $v2, $v3, $v4) = unpack 'C C C C', substr($data, 458, 4);
  $loginrec{tds_version}             = join '.', $v1, $v2, $v3, $v4;

  $len = unpack 'C', substr($data, 472, 1);
  $loginrec{progname}                = substr($data, 462, $len);

  ($v1, $v2, $v3, $v4) = unpack 'C C C C', substr($data, 473, 4);
  $loginrec{prog_version} = join '.', $v1, $v2, $v3, $v4;
  
  $loginrec{noshort}                  = unpack 'C', substr($data, 477, 1);
  $loginrec{float4_representation}    = unpack 'C', substr($data, 478, 1);
  $loginrec{datetime4_representation} = unpack 'C', substr($data, 479, 1);

  return \%loginrec if $p_len < 512;
  
  $len = unpack 'C', substr($data, 510, 1);
  $loginrec{language}                 = substr($data, 480, $len);
  $loginrec{setlang}                  = unpack 'C', substr($data, 511, 1);

  $loginrec{seclogin}                 = unpack 'C', substr($data, 512, 1);
  $loginrec{secbulk}                  = unpack 'C', substr($data, 513, 1);
  $loginrec{halogin}                  = unpack 'C', substr($data, 514, 1);

  $len = unpack 'C', substr($data, 555, 1);
  $loginrec{charset}                  = substr($data, 525, $len);
  $loginrec{setcharset}               = unpack 'C', substr($data, 556, 1);

  $len = unpack 'C', substr($data, 563, 1);
  $loginrec{packetsize}               = substr($data, 557, $len);

  return \%loginrec if $p_len < 568;

# capabilities

  if (substr($data, 568, 1) eq chr(TDS_CAPABILITY)) {
    my $cap_req_len = unpack('C', substr($data, 572, 1));
    my $cap_res_len = unpack('C', substr($data, 573 + $cap_req_len, 1));
    my $cap_req = substr($data, 573, $cap_req_len);
    my $cap_res = substr($data, 573 + $cap_req_len, $cap_res_len);
  
    if (exists $self->{HANDLERS}->{capability}) {
      $self->{CAPABILITIES} = $self->{HANDLERS}->{capability}($socket, $cap_req, $cap_res);
    }
  }

  return \%loginrec;
}

#-----------------------------------------------------------------------------------------------------------------
# Sends a login acknowledge token to the client

sub _login_ack {
  my $self   = shift;
  my $socket = shift;
  my ($status, $tds_version, $serverversion) = @_;

  my $tds_ma = substr($tds_version, 0, 1);
  my $tds_mi = substr($tds_version, 2, 1);

  my $tdssocket = $self->{SOCKETS}->{$socket}->{TDSSOCKET};

  $status        ||= 6;
  $serverversion ||= '0000';

  my $serverlen = length($self->{SERVERNAME});
  
  my $data = pack "C v C C C C C C a$serverlen CCCC", TDS_LOGINACK, 10 + $serverlen, $status, $tds_ma, $tds_mi, 0, 0, $serverlen, $self->{SERVERNAME}, split('.', $serverversion);

  $tdssocket->packet_type(TDS_BUF_RESPONSE);
  return $tdssocket->write($data);
}

#-----------------------------------------------------------------------------------------------------------------
# Sends a capabilities token to the client

sub _capabilities {
  my $self      = shift;
  my $socket    = shift;
  my $tdssocket = $self->{SOCKETS}->{$socket}->{TDSSOCKET};

  my $data = pack('C v', TDS_CAPABILITY, 4 + length($self->{CAPABILITIES_REQ}) + length($self->{CAPABILITIES_RES}))
             . chr(1) . chr(length($self->{CAPABILITIES_REQ})) . $self->{CAPABILITIES_REQ}
             . chr(2) . chr(length($self->{CAPABILITIES_RES})) . $self->{CAPABILITIES_RES};

  $tdssocket->packet_type(TDS_BUF_RESPONSE);
  return $tdssocket->write($data);
}


#-----------------------------------------------------------------------------------------------------------------
# send a proto acknowledge packet

sub _proto_ack {
  my $self      = shift;
  my $tdssocket = shift;

  my $header = pack('C C n n C C', TDS_BUF_PROTO_ACK, TDS_BUFSTAT_EOM, 8, $self->{CHANNEL}, $self->{WINDOWSIZE}, $self->{WINDOWSIZE});
  $tdssocket->write(undef, $header);
  $tdssocket->flush($header);
}

#-----------------------------------------------------------------------------------------------------------------
# send a close packet

sub _close {
  my $self      = shift;
  my $tdssocket = shift;

  my $header = pack('C C n n C C', TDS_BUF_CLOSE, TDS_BUFSTAT_EOM, 8, $self->{CHANNEL}, $self->{WINDOWSIZE}, $self->{WINDOWSIZE});
  $tdssocket->write(undef, $header);
  $tdssocket->flush($header);
}



#-----------------------------------------------------------------------------------------------------------------
# get the complete query from the client

sub _get_query {
  my $self      = shift;
  my $tdssocket = shift;

  my $data = '';
  my ($length, $header, $buffer) = $tdssocket->read_packet;

  return(undef, undef) if ! defined $length;

  while (unpack('C', substr($header, 1, 1)) == TDS_NORMAL_BUFFER) {
    $data .= $buffer;
    ($length, $header, $buffer) = $tdssocket->read_packet;
  }

  return $header if ! $buffer;
  $data .= $buffer;

  return $header, unpack('C', $data), substr($data, 1);
}

#-----------------------------------------------------------------------------------------------------------------
# get the complete query from the client

sub _get_attn {
  my $self      = shift;
  my $tdssocket = shift;

  my $data = '';
  my ($length, $header, $buffer, $status) = $tdssocket->read_packet;

  return;
}

#-----------------------------------------------------------------------------------------------------------------
# process logout token

sub _tds_logout {
  my $self   = shift;
  my $socket = shift;

  $self->disconnect($socket); 

  return 1;
}

#-----------------------------------------------------------------------------------------------------------------
# process optioncmd token

sub _tds_optioncmd {
  my ($self, $socket,$token, $query) = @_;
  my $tdssocket = $self->{SOCKETS}->{$socket}->{TDSSOCKET};

  my ($op_command, $op_option, $op_arglength) = unpack('C C C', substr($query, 2));
  my $op_arg = substr($query, 5, $op_arglength);
  
  if (exists $self->{HANDLERS}->{optioncmd}) {
    $self->{HANDLERS}->{optioncmd}($socket, $op_command, $op_option, $op_arglength, $op_arg);
    $tdssocket->send_done(TDS_DONE_FINAL);
  } else {
    $tdssocket->send_eed(33897, 10, 0, 'No SRV_OPTION handler installed.', $self->{SERVERNAME}, 'unknown', 0);
    $tdssocket->send_done(TDS_DONE_FINAL);
  }

  return 1;
}
#-----------------------------------------------------------------------------------------------------------------
# process language token

sub _tds_language {
  my ($self, $socket,$token, $query) = @_;
  my $tdssocket = $self->{SOCKETS}->{$socket}->{TDSSOCKET};
  $query = substr($query, 5);
  $query =~ s/\x00$//;
  chomp $query;

  my $dataref = $self->{LANG_HANDLER}($socket, $query); 
  return  1 if ! defined $dataref;
  my $header = shift(@$dataref);
  
  $self->send_header($socket, $header);

  my $count = 0;
  while (@$dataref) {
    $self->send_row($socket, shift(@$dataref));
    $count++;
  }
  $tdssocket->send_done(TDS_DONE_FINAL, 0, $count);

  return 1;
}
#-----------------------------------------------------------------------------------------------------------------
# process dbprc token

sub _tds_dbrpc {
  my ($self, $socket, $token, $query) = @_;
  my $tdssocket = $self->{SOCKETS}->{$socket}->{TDSSOCKET};

  return undef if ! exists $self->{HANDLERS}->{rpc}; 

  $self->_proto_ack($tdssocket);

  my $namelen = unpack('C', substr($query, 2, 1));
  my $proc = substr($query, 3, $namelen);
  my $options = unpack('v', substr($query, $namelen + 3, 2));
  
  my ($params, $paramfmt);
  if ($options & TDS_RPC_PARAMS) {
    ($params, $paramfmt) = $self->_tds_params(substr($query, $namelen + 5));
  }

  my $dataref = $self->{HANDLERS}->{rpc}($socket, $proc, $params, $paramfmt); 
  return if ! defined $dataref;
  my $header = shift(@$dataref);
  
  $self->send_header($socket, $header);

  my $count = 0;
  while (@$dataref) {
    $self->send_row($socket, shift(@$dataref));
    $count++;
  }
  $tdssocket->send_done(TDS_DONE_FINAL, 0, $count);

  return 1;
}

#-----------------------------------------------------------------------------------------------------------------
# process params incl. paramfmt

sub _tds_params {
  my ($self, $query) = @_;

  my @vals;

  my ($offset, @paramfmt) = $self->_tds_paramfmt($query);

#---- get parameter values
  $offset++;
  for (0..$#paramfmt) {
    my $length;
    if ($coltypes{$datatypes{$paramfmt[$_]{datatype}}}[2] == 1) {
      $length = unpack('C', substr($query, $offset));
      $offset += 1;
    } elsif  ($coltypes{$datatypes{$paramfmt[$_]{datatype}}}[2] == 4) {
      $length = unpack('V', substr($query, $offset));
      $offset += 4;
    } else {
      $length = 0;
    }
    my $value;

    if ($length) {
      if (ref $coltypes{$datatypes{$paramfmt[$_]{datatype}}}[5]) {
        $value = $coltypes{$datatypes{$paramfmt[$_]{datatype}}}[5](substr($query, $offset, $length), $length, 1);
      } else {
        $value = unpack($coltypes{$datatypes{$paramfmt[$_]{datatype}}}[5] . '*', substr($query, $offset, $length));
      }
      $offset += $length;
    } else {
    }

    $vals[$_] = $value;
  }
  
  return \@vals, \@paramfmt;
}


#-----------------------------------------------------------------------------------------------------------------
# process paramfmt

sub _tds_paramfmt {
  my ($self, $query) = @_;

  my @pfmts;

  my $numparams = unpack('v', substr($query, 3));
  my $offset = unpack('C', $query) == TDS_PARAMFMT ? 5 : 7;

#---- get parameter formats
  for (0..$numparams - 1) {
    my $namelen  = unpack('C', substr($query, $offset));
    my $name     = substr($query, $offset + 1, $namelen);
    my $status   = unpack('C', substr($query, $offset + $namelen + 1));
    my $usertype = unpack('V', substr($query, $offset + $namelen + 2));
    my $datatype = unpack('C', substr($query, $offset + $namelen + 6));
    my $length;
    if ($coltypes{$datatypes{$datatype}}[2] == 1) {
      $length = unpack('C', substr($query, $offset + $namelen + 7));
      $offset += 8;
    } elsif  ($coltypes{$datatypes{$datatype}}[2] == 4) {
      $length = unpack('V', substr($query, $offset + $namelen + 7));
      $offset += 11;
    } else {
      $length = 0;
      $offset += 7;
    }
    my ($prec, $scale);
    if ($coltypes{$datatypes{$datatype}}[3]) {
      $prec  = unpack('C', substr($query, $offset + $namelen));
      $scale = unpack('C', substr($query, $offset + $namelen + 1));
      $offset += 2;
    }
    my $localelen = unpack('C', substr($query, $offset + $namelen));
    my $localeinfo = substr($query, $offset + $namelen + 1, $localelen);

    $offset += $namelen + 1 + $localelen;

    $pfmts[$_] = {name       => $name,
                  status     => $status,
                  usertype   => $usertype,
                  datatype   => $datatype,
                  length     => $length,
                  prec       => $prec,
                  scale      => $scale,
                  localeinfo => $localeinfo};
  }

  return $offset, @pfmts;
}



1;


__END__
 
=head1 HANDLERS

The communication between the module and the application works with handlers (callbacks).

You have to provide the following handlers:

=head2 Connect Handler

This handler is called when a new connection to the server is made.

It recieves a session-handle and a reference to the login hash, see 'structures' for info on the login hash.

Return true to acknowledge the connection, false to refuse.

=head2 Disconnect Handler

This handler is called when a client disconnects from the server.

It gives the application the opportunity to clean up on a connection.

=head2 Language Handler

This handler is called when a new connection sends a language command to the server.

It recieves a session-handle, the string that was sent by the client.

The handler processes the string and sends back a result of the following form:

An array that contains references to arrays representing the header and the rows of the result set.

The header-array contains references to hashes for each column returned.
Each row-array contains the value for the columns.

Each hash in the header-array must contain the entries:

=over

=item column_name

The column name.

=item column_type

one of:

 SYBCHAR
 SYBVARCHAR
 SYBINTN
 SYBINT1
 SYBINT2
 SYBINT4
 SYBFLT8
 SYBDATETIME
 SYBBIT
 SYBTEXT
 SYBNTEXT
 SYBIMAGE
 SYBMONEY4
 SYBMONEY
 SYBDATETIME4
 SYBREAL
 SYBBINARY
 SYBVOID
 SYBVARBINARY
 SYBNVARCHAR
 SYBNUMERIC
 SYBDECIMAL
 SYBFLTN
 SYBMONEYN
 SYBDATETIMN
 XSYBCHAR
 XSYBVARCHAR
 XSYBNVARCHAR
 XSYBNCHAR

For a further description look at the freetds documentation.

=item column_size

The size of the column

=back

=head2 Examples:

 return [
          [{column_name => 'result', column_type => 'SYBVARCHAR', column_size => 30}],
          [$answer],
        ];

Returns one row with one column name 'result', width 30.

 return [
          [{column_name => 'name',    column_type => 'SYBVARCHAR', column_size => 30},
           {column_name => 'address', column_type => 'SYBVARCHAR', column_size => 30},
           {column_name => 'city',    column_type => 'SYBVARCHAR', column_size => 30}],
          [$name[0], $address[0], $city[0]],
          [$name[1], $address[1], $city[1]],
          [$name[2], $address[2], $city[2]],
        ];

Returns three rows with three columns named 'name', 'address' and 'city'.

=head1 Structures

=head2 login hash

The tds login structure is recieved into a hash of which a reference is made available to the application

The hash has the following entries:

=over

=item hostname

The name of the computer on which the client runs

=item username

The username

=item password

The password

=item hostprocess

The process-id on the client machine

=item byteorder2

The byteorder for 2-byte integers
 2 - little endian
 3 - big endian
 
=item byteorder4

The byteorder for 4-byte integers
 2 - little endian
 3 - big endian

=item ascii_ebcdic

The character representation
 6 - ascii
 7 - ebcdic

=item float_repesentation

The floating point value representation
  4 - ieee high
  5 - VAX D
 10 - ieee low
 11 - ND5000

=item datetime_representation

The 8-byte datetime representation
 8 - LSB HI (least significant is high)
 9 - LSB LO (least significant is low)

=item interfacespare

?

=item type

Type of dialog, only in server to server communication
 1 - server to server
 2 - remote user
 4 - internal rpc

=item appname

Name of the client application

=item servername

Name of the server to which the client wants to connet to

=item remote_password

Servername and password for server-to-server connections

=item tds_version

Requested tds protocol version in dotted quad form.
 e.g.: 5.0.0.0

=item progname

Name of the client library

=item prog_version

Client library version in dotted quad form

=item noshort

Indicator whether to convert short type forms (e.g. smalldatetime) to their 8-byte respective
 0 - don't convert
 1 - convert

=item float4_representation

The 4-byte floating point value representation
 12 - ieee high
 13 - ieee low
 14 - VAX D
 15 - ND5000

=item datetime4_representation

The 4-byte datetime representation
 16 - LSB HI (least significant is high)
 17 - LSB LO (least significant is low)

=item language

The language for error messages and such

=item setlang

Indicator whether client wants to be informed of language changes by the server
 0 - don't notify
 1 - notify

=item seclogin

Bitmask for negotiated login
 0x01 - encrypt
 0x02 - challenge
 0x04 - labels
 0x08 - appdefined

=item secbulk

Bulkcopy security bitmask
 0x01 - labeled

=item halogin

High availability login request
 0x01 - session
 0x02 - resume
 0x04 - failover server

=item ha_session_id

Id for the ha session, only usefull in combination with halogin

=item charset

Requested character set

=item setcharset

Indicator whether client wants to be informed of character set changes by the server
 0 - don't notify
 1 - notify

=item packetsize

Size of tds packets

=back

=head1 AUTHOR
 
Bernd Dulfer <bdulfer@cpan.org>
 
=head1 ACKNOWLEGDEMENTS

Thanks to the team developing FreeTDS. Without their work this module would not exist.

I hope I can give something back to their project soon.

=head1 SEE ALSO
 
 Perl
 www.freetds.org
 
=cut


