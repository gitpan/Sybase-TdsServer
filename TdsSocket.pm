package Sybase::TdsSocket;

#------------------------------------------------------------------------------------------------------------

=head1 NAME

Sybase::TdsSocket - A module containing tds lowlevel functions

=head1 SYNOPSIS

  my $tdssocket = Sybase::TdsSocket->new($socket);

  $tdssocket->set_packetsize(512);
  $tdssocket->packet_type(TDS_BUF_RESPONSE);
  
  my ($length, $header, $data) = $tdssocket->read_packet();
  $tdssocket->write($data);
  
=head1 DESCRIPTION

=head1 REQUIREMENTS

=head1 EXPORTS

=head1 FUNCTIONS

=cut

require 5.005_62;
use strict;
use warnings;

our $VERSION = '0.01';

use Sybase::TdsConstants;

#-----------------------------------------------------------------------------------------------------
  
=head2 new - the constructor
   
Parameters:
    
=over
     
=item Servername

=back

Example:

$tdssocket = Sybase::TdsSocket->new('myserver');
 
=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  
sub new {
  my $that = shift;
  my $class = ref($that) || $that;
       
  my $self = { SOCKET => $_[0], PACKETSIZE => 512, PACKETTYPE => TDS_BUF_RESPONSE, BUFFER => '' };

  bless $self, $class;
                                           
  return $self;
}

#-----------------------------------------------------------------------------------------------------------------

=head2 packet_type

Sets the packet type for the next outgoing packets.

Parameters:

The type, should be one of the following:
 TDS_BUF_RESPONSE

Example:

my $res = $tdssocket->packet_type(TDS_BUF_RESPONSE);

=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub packet_type {
  my $self = shift;

  $self->{PACKETTYPE} = shift;
}
                                             
#-----------------------------------------------------------------------------------------------------------------

=head2 read_packet

Parameters:

=over

=item Socket

An IO::Socket object from which the data will be read.

=back

Returnvalues:

=over

=item Packetlength

The length of the packet in bytes.

=item Header

The 8 byte tds header

=item Data

The data.

=back

Example:

my ($len, $header, $data) = $tdssocket->read_packet;

=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub read_packet {
  my $self = shift;

  my ($header, $data);

  my $bytes = sysread $self->{SOCKET}, $header, 8;

  return undef if $bytes < 8;

  my ($token, $status, $length) = unpack 'C C n', $header;

  sysread($self->{SOCKET}, $data, $length - 8) if $length > 8;
  
  return $length, $header, $data, $status;
}

#-----------------------------------------------------------------------------------------------------------------

=head2 write

Accumulates data in a buffer and sends a tds packet if necessary.

Parameters:

=over

=item Data

The packet Data

=back

Returnvalues:

True for success, false for failure.

Example:

my $res = $tdssocket->write($data);

=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub write {
  my $self = shift;
  my $socket = $self->{SOCKET};

  my $data = shift;
  my $header = shift;

  my $packetsize = $self->{PACKETSIZE};

  $self->{BUFFER} .= $data if defined $data;

  while (length($self->{BUFFER}) > $packetsize - 8) {
    $header = pack 'C C n CCCC', $self->{PACKETTYPE}, TDS_NORMAL_BUFFER, $packetsize, 0, 0, 0, 0 if ! $header;
    syswrite $socket, $header . $self->{BUFFER}, $packetsize;
    $self->{BUFFER} = substr($self->{BUFFER}, $packetsize - 8);
  }
}

#-----------------------------------------------------------------------------------------------------------------

=head2 flush

Sends all data in buffer and truncates it.

Parameters:

None.

Example:

my $res = $tdssocket->flush;

=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub flush {
  my $self = shift;
  my $socket = $self->{SOCKET};
  my $header = shift;

  $self->write(undef, $header);
  
  $header = pack('C C n CCCC', $self->{PACKETTYPE}, TDS_LAST_BUFFER, length($self->{BUFFER}) + 8, 0, 0, 0, 0) if ! $header;
  syswrite $socket, $header . $self->{BUFFER}, length($self->{BUFFER}) + 8;
  $self->{BUFFER} = '';
}

#-----------------------------------------------------------------------------------------------------------------

=head2 send_done

Sends a done token to the client

Parameters:

=over

=item Status

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

Returnvalues:

Example:

$tdssocket->send_done($status);

=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub send_done {
  my $self = shift;
  my $socket = $self->{SOCKET};
  my ($status, $tran, $numrows, $oob) = @_;

  $status ||= TDS_DONE_FINAL;
  $tran ||= 0;
  $numrows ||= 0;

  my $data = pack "C v v V", TDS_DONE, $status, $tran, $numrows;

  $self->packet_type(TDS_BUF_RESPONSE);
  if ($oob) {
    my $header = pack 'C C n CCCC', TDS_BUF_NORMAL, TDS_BUFSTAT_ATTNACK | TDS_BUFSTAT_EOM, 8, 0, 0, 0, 0;
    $self->{BUFFER} = '';
    send($socket, $header, 0);
  } else {
    $self->write($data);
    $self->flush;
  }
}

#-----------------------------------------------------------------------------------------------------------------

=head2 send_eed

Sends a eed token to the client

Parameters:

=over

=item MsgNo

Message number.
 
=item Class

Class or severity.

=item Transtate

Status of the current transaction is one of the following:
            
 0  not in tran
 1  tran succeed
 2  tran in progress
 3  statement abort
 4  tran abort

=item Message

Text of the message.

=item Server

Servername

=item Procedure

Name of the procedure (optional)

=item Line

Line of the procedure (optional)

Returnvalues:

Example:

$tdssocket->send_eed(12345, 10, 0, 'This is a warning');

=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub send_eed {
  my $self = shift;
  my $socket = $self->{SOCKET};
  my ($msgno, $class, $tran, $msg, $server, $proc, $line) = @_;

  $msg    ||= '';
  $server ||= '';
  $proc   ||= '';
  $tran   ||= 0;
  $line   ||= 0;

  my $totallength = 16 + length($msg) + length($server) + length($proc);
  my $data = pack('C v V C C C C v v', TDS_EED, $totallength, $msgno, 0, $class, 0, 0, $tran, length($msg))
           . $msg
           . pack('C', length($server))
           . $server
           . pack('C', length($proc))
           . $proc
           . pack('v', $line);

  $self->packet_type(TDS_BUF_RESPONSE);
  $self->write($data);
}

#-----------------------------------------------------------------------------------------------------------------

=head2 server_info

Gets ip and port from interfaces file

Parameters:

Servername

Returnvalues:

IP and Portnumber

undef and errortext on failure.

Example:

my ($ip, $port) = $tdssocket->server_info('myserver');

=cut

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub server_info {
  my $self = shift;
  my $server = shift;

  if (! defined $ENV{SYBASE}) {
    return undef, 'SYBASE variable not set!';
  }

  my $file = $server->{INTERFACES} ? $server->{INTERFACES} : $^O eq 'MSWin32' ? $ENV{SYBASE}.'/ini/sql.ini' : $ENV{SYBASE}.'/interfaces';
  my $servername = $server->{SERVERNAME};

  my ($ip, $port);
  my $line;

  open INTERFACES, $file or return undef, "Interfaces file $file not found!";

  INT: while ($line = <INTERFACES>) {
    chomp $line;
    if ($^O eq 'MSWin32') {
      if ($line =~ /\[$servername\]/) {
        while ($line = <INTERFACES>) {
          chomp $line;
          if ($line =~ /\s*master\s*=/) {
            (undef, $ip, $port) = split /[ ,]+/, $_;
            last INT;
          }
        }
      }
    } else {
      if ($line =~ /^$servername$/) {
        while ($line = <INTERFACES>) {
          chomp $line;
          if ($line =~ /master/) {
            (undef, undef, undef, undef, $ip, $port) = split /\s+/, $line;
            last INT;
          }
        }
      }
    }
  }

  close INTERFACES;

  if (! defined $ip) {
    $port = "Servername $servername not found in $ENV{SYBASE}$file!";
  }

  return $ip, $port;
}

#====================================================================================================================

1;
