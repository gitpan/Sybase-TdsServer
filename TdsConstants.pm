package Sybase::TdsConstants;

#------------------------------------------------------------------------------------------------------------

=head1 NAME

Sybase::TdsConstants - Provides constants used in TDS protocol

not complete yet!

=head1 SYNOPSIS

  use Sybase::TdsConstants;

=cut

require 5.005_62;
use strict;
use warnings;

require Exporter;
  
our @ISA = qw(Exporter);

our @EXPORT = grep /^TDS_/, keys %Sybase::TdsConstants::;

# packet types
use constant TDS_RESPONSE      => 0x04;

# buffer status
use constant TDS_NORMAL_BUFFER => 0x00;
use constant TDS_LAST_BUFFER   => 0x01;

# tds token
use constant TDS_ALTFMT        => 0xa8;
use constant TDS_ALTNAME       => 0xa7;
use constant TDS_ALTROW        => 0xd3;
use constant TDS_CAPABILITY    => 0xe2;
use constant TDS_COLINFO       => 0xa5;
use constant TDS_CONTROL       => 0xae;
use constant TDS_CURCLOSE      => 0x80;
use constant TDS_CURDECLARE    => 0x86;
use constant TDS_CURDECLARE2   => 0x23;
use constant TDS_CURDELETE     => 0x81;
use constant TDS_CURFETCH      => 0x82;
use constant TDS_CURINFO       => 0x83;
use constant TDS_CUROPEN       => 0x84;
use constant TDS_CURUPDATE     => 0x85;
use constant TDS_DBRPC         => 0xe6;
use constant TDS_DONE          => 0xfd;
use constant TDS_DONEPROC      => 0xfe;
use constant TDS_DONEINPROC    => 0xff;
use constant TDS_DYNAMIC       => 0xe7;
use constant TDS_DYNAMIC2      => 0xa3;
use constant TDS_EED           => 0xe5;
use constant TDS_ENVCHANGE     => 0xe3;
use constant TDS_ERROR         => 0xaa;
use constant TDS_EVENTNOTICE   => 0xa2;
use constant TDS_INFO          => 0xab;
use constant TDS_KEY           => 0xca;
use constant TDS_LANGUAGE      => 0x21;
use constant TDS_LOGINACK      => 0xad;
use constant TDS_LOGOUT        => 0x71;
use constant TDS_MSG           => 0x65;
use constant TDS_OFFSET        => 0x78;
use constant TDS_OPTIONCMD     => 0xa6;
use constant TDS_ORDERBY       => 0xa9;
use constant TDS_ORDERBY2      => 0x22;
use constant TDS_PARAMFMT      => 0xec;
use constant TDS_PARAMFMT2     => 0x20;
use constant TDS_PARAMS        => 0xd7;
use constant TDS_RPC           => 0xe0;           # obsolete
use constant TDS_RETURNSTATUS  => 0x79;
use constant TDS_RETURNVALUE   => 0xac;           # obsolete
use constant TDS_ROW           => 0xd1;
use constant TDS_ROWFMT        => 0xee;
use constant TDS_ROWFMT2       => 0x61;
use constant TDS_TABNAME       => 0xa4;

# option commands
use constant TDS_OPT_SET       => 1;
use constant TDS_OPT_DEFAULT   => 2;
use constant TDS_OPT_LIST      => 3;
use constant TDS_OPT_INFO      => 4;

# options
use constant TDS_OPT_UNUSED             =>  0;
use constant TDS_OPT_DATEFIRST          =>  1;
use constant TDS_OPT_TEXTSIZE           =>  2;
use constant TDS_OPT_STAT_TIME          =>  3;
use constant TDS_OPT_STAT_IO            =>  4;
use constant TDS_OPT_ROWCOUNT           =>  5;
use constant TDS_OPT_NATLANG            =>  6;
use constant TDS_OPT_DATEFORMAT         =>  7;
use constant TDS_OPT_ISOLATION          =>  8;
use constant TDS_OPT_AUTHON             =>  9;
use constant TDS_OPT_CHARSET            => 10;
use constant TDS_OPT_SHOWPLAN           => 13;
use constant TDS_OPT_NOEXEC             => 14;
use constant TDS_OPT_ARITHIGNOREON      => 15;
use constant TDS_OPT_ARITHABORTON       => 17;
use constant TDS_OPT_PARSEONLY          => 18;
use constant TDS_OPT_GETDATA            => 20;
use constant TDS_OPT_NOCOUNT            => 21;
use constant TDS_OPT_FORCEPLAN          => 23;
use constant TDS_OPT_FORMATONLY         => 24;
use constant TDS_OPT_CHAINXACTS         => 25;
use constant TDS_OPT_CURCLOSEONXACT     => 26;
use constant TDS_OPT_FIPSFLAG           => 27;
use constant TDS_OPT_RESTREES           => 28;
use constant TDS_OPT_IDENTITYON         => 29;
use constant TDS_OPT_CURREAD            => 30;
use constant TDS_OPT_CURWRITE           => 31;
use constant TDS_OPT_IDENTITYOFF        => 32;
use constant TDS_OPT_AUTHOFF            => 33;
use constant TDS_OPT_ANSINULL           => 34;
use constant TDS_OPT_QUOTED_IDENT       => 35;
use constant TDS_OPT_ARITHIGNOREOFF     => 36;
use constant TDS_OPT_ARITHABORTOFF      => 37;
use constant TDS_OPT_TRUNCABORT         => 38;

# done status
use constant TDS_DONE_FINAL    => 0x0000;
use constant TDS_DONE_MORE     => 0x0001;
use constant TDS_DONE_ERROR    => 0x0002;

# request capabilities
use constant TDS_REQ_LANG              =>  0;
use constant TDS_REQ_RPC               =>  1;
use constant TDS_REQ_EVT               =>  2;
use constant TDS_REQ_MSTMT             =>  3;
use constant TDS_REQ_BCP               =>  4;
use constant TDS_REQ_CURSOR            =>  5;
use constant TDS_REQ_DYNF              =>  6;
use constant TDS_REQ_MSG               =>  7;
use constant TDS_REQ_PARAM             =>  8;
use constant TDS_DATA_INT1             =>  9;
use constant TDS_DATA_INT2             => 10;
use constant TDS_DATA_INT4             => 11;
use constant TDS_DATA_BIT              => 12;
use constant TDS_DATA_CHAR             => 13;
use constant TDS_DATA_VCHAR            => 14;
use constant TDS_DATA_BIN              => 15;
use constant TDS_DATA_VBIN             => 16;
use constant TDS_DATA_MNY8             => 17;
use constant TDS_DATA_MNY4             => 18;
use constant TDS_DATA_DATE8            => 19;
use constant TDS_DATA_DATE4            => 20;
use constant TDS_DATA_FLT4             => 21;
use constant TDS_DATA_FLT8             => 22;
use constant TDS_DATA_NUM              => 23;
use constant TDS_DATA_TEXT             => 24;
use constant TDS_DATA_IMAGE            => 25;
use constant TDS_DATA_DEC              => 26;
use constant TDS_DATA_LCHAR            => 27;
use constant TDS_DATA_LBIN             => 28;
use constant TDS_DATA_INTN             => 29;
use constant TDS_DATA_DATETIMEN        => 30;
use constant TDS_DATA_MONEYN           => 31;
use constant TDS_CSR_PREV              => 32;
use constant TDS_CSR_FIRST             => 33;
use constant TDS_CSR_LAST              => 34;
use constant TDS_CSR_ABS               => 35;
use constant TDS_CSR_REL               => 36;
use constant TDS_CSR_MULTI             => 37;
use constant TDS_CON_OOB               => 38;
use constant TDS_CON_INBAND            => 39;
use constant TDS_CON_LOGICAL           => 40;
use constant TDS_PROTO_TEXT            => 41;
use constant TDS_PROTO_BULK            => 42;
use constant TDS_REQ_URGEVT            => 43;
use constant TDS_DATA_SENSITIVITY      => 44;
use constant TDS_DATA_BOUNDARY         => 45;
use constant TDS_PROTO_DYNAMIC         => 46;
use constant TDS_PROTO_DYNPROC         => 47;
use constant TDS_DATA_FLTN             => 48;
use constant TDS_DATA_BITN             => 49;
use constant TDS_DATA_INT8             => 50;
use constant TDS_DATA_VOID             => 51;
use constant TDS_DOL_BULK              => 52;
use constant TDS_OBJECT_JAVA1          => 53;
use constant TDS_OBJECT_CHAR           => 54;
use constant TDS_DATA_COLUMNSTATUS     => 55;
use constant TDS_OBJECT_BINARY         => 56;
use constant TDS_WIDETABLE             => 58;
use constant TDS_DATA_UINT2            => 60;

# response capabilities
use constant TDS_RES_NOMSG             =>  0;
use constant TDS_RES_NOEED             =>  1;
use constant TDS_RES_NOPARAM           =>  2;
use constant TDS_DATA_NOINT1           =>  3;
use constant TDS_DATA_NOINT2           =>  4;
use constant TDS_DATA_NOINT4           =>  5;
use constant TDS_DATA_NOBIT            =>  6;
use constant TDS_DATA_NOCHAR           =>  7;
use constant TDS_DATA_NOVCHAR          =>  8;
use constant TDS_DATA_NOBIN            =>  9;
use constant TDS_DATA_NOVBIN           => 10;
use constant TDS_DATA_NOMNY8           => 11;
use constant TDS_DATA_NOMNY4           => 12;
use constant TDS_DATA_NODATE8          => 13;
use constant TDS_DATA_NODATE4          => 14;
use constant TDS_DATA_NOFLT4           => 15;
use constant TDS_DATA_NOFLT8           => 16;
use constant TDS_DATA_NONUM            => 17;
use constant TDS_DATA_NOTEXT           => 18;
use constant TDS_DATA_NOIMAGE          => 19;
use constant TDS_DATA_NODEC            => 20;
use constant TDS_DATA_NOLCHAR          => 21;
use constant TDS_DATA_NOLBIN           => 22;
use constant TDS_DATA_NOINTN           => 23;
use constant TDS_DATA_NODATETIMEN      => 24;
use constant TDS_DATA_NOMONEYN         => 25;
use constant TDS_CON_NOOOB             => 26;
use constant TDS_CON_NOINBAND          => 27;
use constant TDS_PROTO_NOTEXT          => 28;
use constant TDS_PROTO_NOBULK          => 29;
use constant TDS_DATA_NOSENSITIVITY    => 30;
use constant TDS_DATA_NOBOUNDARY       => 31;
use constant TDS_RES_NOTDSDEBUG        => 32;
use constant TDS_RES_NOSTRIPBLANKS     => 33;
use constant TDS_DATA_NOINT8           => 34;
use constant TDS_OBJECT_NOJAVA1        => 35;
use constant TDS_OBJECT_NOCHAR         => 36;
use constant TDS_DATA_NOZEROLEN        => 37;
use constant TDS_OBJECT_NOBINARY       => 38;
use constant TDS_DATA_NOUINT2          => 40;
use constant TDS_DATA_NOUINT4          => 41;
use constant TDS_DATA_NOUINT8          => 42;
use constant TDS_DATA_NOUINTN          => 43;
use constant TDS_NO_WIDETABLES         => 44;
use constant TDS_DATA_NONLBIN          => 45;
use constant TDS_IMAGE_NONCHAR         => 46;
use constant TDS_BLOB_NONCHAR_16       => 47;
use constant TDS_BLOB_NONCHAR_8        => 48;
use constant TDS_BLOB_NONCHAR_SCSU     => 49;


use constant TDS_BUF_NORMAL      => 15;
use constant TDS_BUFSTAT_ATTNACK => 2;
use constant TDS_BUFSTAT_EOM     => 1;

1;
