#!perl

=pod

=head1 NAME

schema.pl - Command line script to turn XML database schemas into RDBMS specific DDL statements

=head1 SYNOPSIS

    perl schema.pl DATABASE.xml RDBMS_profile
    # Where DATABASE.xml if the database schema definition in XML
    # and RDBMS is a CompareRDBMS configured database

    # Examples
    perl schema.pl sample_schema.xml MySQL_5
    perl schema.pl sample_schema.xml PostgreSQL_9
    perl schema.pl sample_schema.xml Oracle_11g
    perl schema.pl sample_schema.xml SQLServer_2012

=cut

use XML::TreePP;
use DBI;
use Data::Dumper;
$Data::Dumper::Indent = 1;

use strict;
use warnings;

use Schema;

# Validate the correct arguments are passed
die( 'Must pass XML schema filename' ) unless $ARGV[0];
die( "XML schema file $ARGV[0] does not exist" ) unless -e $ARGV[0];
die( 'Must pass RDBMS profile ID' ) unless $ARGV[1];
die( "RDBMS profile $ARGV[1] does not exist" ) unless -e "profiles/$ARGV[1].xml";

my ( $db_schema, $profile ) = @ARGV;

# Get associated database connection
my $xml = XML::TreePP->new();
$xml->set( use_ixhash => 1 );
$xml->set( force_array => [ qw( connection ) ] );
my $db_list = $xml->parsefile( 'db_config.xml' )->{rdbms}->{connection};

my $DBCONFIG;
foreach my $connection ( @$db_list ) {
    next unless $connection->{profile} eq $profile;
    $DBCONFIG = $connection;
    last;
}#foreach

# Validate the profile has a database associated with it
die( "The profile $profile doesn't have an associated database connectino set in CompareRDBMS" ) unless $DBCONFIG;

my $dbh = DBI->connect( $DBCONFIG->{dsn}, $DBCONFIG->{username}, $DBCONFIG->{password},
    { RaiseError => 0, PrintError => 0, PrintWarn => 0, AutoCommit => 1 } ) || die( "Cannot connect to $DBCONFIG->{label} database $DBCONFIG->{db}" );

my $schema = Schema->new(
    dbh     => $dbh,
    profile => "profiles/$profile.xml",
    schema  => $db_schema,
    format  => 1,
);
my $ddl = $schema->create(
    drop   => 1,
    output => 'separate',
);

print $ddl;
