# -*- perl -*-

# t/020_schema.t - load and test sample schemas

use strict;
use warnings;
use Test::More qw(no_plan);
use Data::Dumper;
use Tie::IxHash;

use lib 't', '.';

$| = 1;

BEGIN {
    use_ok( 'DBI' );
    use_ok( 'XML::TreePP' );
    use_ok( 'Schema' );
}

# Load test DB info
my $xml = XML::TreePP->new();
$xml->set( force_array => [ qw( connection ) ] );
my $db_list = $xml->parsefile( 'db_config.xml' )->{rdbms}->{connection};


# Load the sample schema into a DB
sub create_test_schema {
    my ( $dbh, $db_schema, $schema ) = @_;
    $db_schema->schema( "schemas/$schema" );
    my @test_schema = $db_schema->create(
        drop => 1,
        output => 'separate',
    );
    foreach my $sql ( @test_schema ) {
        diag( $sql );
        if ( $sql =~ /^DROP/ ) {
            TODO: {
                local $TODO = 'Table drop commands will fail is this is the first test run';
                ok( $dbh->do($sql), "Dropping tables" );
            };
        }
        else {
            ok( $dbh->do($sql), "Creating tables" ) ||
                do { print $sql, $DBI::errstr };
        }
    }#foreach
}#sub

# Try db connection, skip otherwise
tie my %stats, 'Tie::IxHash';
foreach my $connection ( @$db_list ) {
    SKIP:
    {
        # Copy dsn, swap in values
        my $dbh = DBI->connect($connection->{dsn}, $connection->{username}, $connection->{password},
            { RaiseError => 0, PrintError => 0, PrintWarn => 0, AutoCommit => 1 });
        isa_ok ($dbh, 'DBI::db', 'DBH Object created');

        unless ( ref $dbh eq 'DBI::db' ) {
            skip( "!!$connection->{label} database details are invalid!!", 1 );
        }#unless

        diag( "==Running tests on $connection->{label}==");

        # Create schema object
        my $db_schema = Schema->new(
            dbh     => $dbh,
            profile => "profiles/$connection->{profile}.xml",
            format  => 1,
        );
        isa_ok ($db_schema, 'Schema', 'Schema Object created');

        # Test numerics
        create_test_schema( $dbh, $db_schema, 'numeric.xml' );

        ## Test ranges
        # Get types from schema
        my $schema = $db_schema->schema();
        my $column_list = $schema->{table_list}->{table}->[0]->{definition}->{column_list}->{column};
        # Get ranges from profile
        my $profile = $db_schema->profile();
        my $sql_insert = 'INSERT INTO ' . $dbh->quote_identifier('test_numeric');
        foreach my $column ( @$column_list ) {
            my $type = $column->{-data_type};
            # Get max/min from type details
            my ( $max_value, $min_value ) = (
                $profile->{types}->{$type}->{extended}->{MAX_VALUE},
                $profile->{types}->{$type}->{extended}->{MIN_VALUE}
            );
            # Clean off any thousands separators
            $max_value =~ s/,//g;
            $min_value =~ s/,//g;
            # Record max/min ranges in stats
            $stats{$type}->{max}->{high} = $max_value if ! defined $stats{$type}->{max}->{high} || $max_value > $stats{$type}->{max}->{high};
            $stats{$type}->{max}->{low} = $max_value if ! defined $stats{$type}->{max}->{low} || $max_value < $stats{$type}->{max}->{low};
            $stats{$type}->{min}->{high} = $min_value if ! defined $stats{$type}->{min}->{high} || $min_value < $stats{$type}->{min}->{high};
            $stats{$type}->{min}->{low} = $min_value if ! defined $stats{$type}->{min}->{low} || $min_value > $stats{$type}->{min}->{low};
            # Test max value
            my $sql = "$sql_insert (" . $dbh->quote_identifier( $column->{-name} ) . ") VALUES (" . $db_schema->quote($max_value,$type) . ")";
            ok( $dbh->do($sql), "$type max" ) || do { print $sql, $DBI::errstr };
            # Test min value
            $sql = "$sql_insert (" . $dbh->quote_identifier( $column->{-name} ) . ") VALUES (" . $db_schema->quote($min_value,$type) . ")";
            ok( $dbh->do($sql), "$type min" ) || do { print $sql, $DBI::errstr };
        }#foreach

        # disconnect
        $dbh->disconnect();
    }#skip
}#foreach

# Return statistics
diag( Dumper(\%stats) );

done_testing();
