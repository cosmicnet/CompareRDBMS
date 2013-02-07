package CompareRDBMS;

=pod

=head1 NAME

CompareRDBMS - A tool for comparing various RDBMSs

=head1 SYNOPSIS

    # Start the tool as local web service on port 8080
    perl compareRDBMS.pl 8080
    # Then open in your browser as http://localhost:8080/

=cut

use base 'CGI::Application';
use JSON;
use DBI;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

use strict;
use warnings;

sub setup {
    my $self = shift;
    $self->tmpl_path('templates');
    $self->start_mode('home');
    $self->mode_param('rm');
    $self->run_modes(
        home                 => 'home',
        dbms_config          => 'dbms_config',
        dbms_test            => 'dbms_test',
        dbms_save            => 'dbms_save',
        profile_config       => 'profile_config',
        profile_save         => 'profile_save',
        driver_type_list     => 'driver_type_list',
        compare_driver_types         => 'compare_driver_types',
        compare_driver_type_details  => 'compare_driver_type_details',
        compare_profile_types        => 'compare_profile_types',
        compare_profile_type_details => 'compare_profile_type_details',
        compare_mixed_types          => 'compare_mixed_types',
        compare_mixed_type_details   => 'compare_mixed_type_details',
    );
}


=head1 RUNMODES

=head2 home

This is the default page for the tool. It lists which RDBMS drivers are
available, and those that have a database connection configured. It also
links to the comparison reports that are available.

=cut

sub home {
    my $self = shift;
    # Load page template
    my $tmpl = $self->load_tmpl('home.html', 'die_on_bad_params', 0);
    # Get list of available drivers
    my @driver_available = DBI->available_drivers(1);
    # Load in currently configured DB settings
    my $dbconfig = _get_dbconfig();
    # Load in currently configured profiles
    my $profile_available = _get_profile();
    
    ## Build data structures for template
    # Driver list
    my @driver_list;
    foreach my $driver ( @driver_available ) {
        push( @driver_list, {
            driver_name => $driver,
            has_config  => $dbconfig->{$driver}->{db} ? 1 : 0,
        });
    }
    # Profile list
    my @profile_list;
    foreach my $profile ( @{ $profile_available } ) {
        push( @profile_list, {
            uid   => $profile->{uid},
            label => $profile->{label},
        });
    }
    # Populate template
    $tmpl->param(
        driver_list    => \@driver_list,
        profile_list   => \@profile_list,
        profiles_exist => scalar @profile_list,
    );
    return $tmpl->output();
}


=head2 dbms_config

This is the page is where config can be set for the chosen database driver.
It includes an AJAX link to the test method, allowing the user to test the
DB settings before they save.

=cut

sub dbms_config {
    my $self = shift;
    # Load page template
    my $tmpl = $self->load_tmpl('dbms_config.html', 'die_on_bad_params', 0);
    # Get the query object
    my $q = $self->query();
    my $driver = $q->param('driver');
    # Load in currently configured DB settings
    my $dbconfig = _get_dbconfig( $driver );
    # Load in profiles valid for this driver settings
    my $profile_available = _get_profile( driver => $driver );

    ## Build data structures for template
    # Profile list
    my @profile_list;
    foreach my $profile ( @{ $profile_available } ) {
        push( @profile_list, {
            uid   => $profile->{uid},
            label => $profile->{label},
            selected => $dbconfig->{profile} eq $profile->{uid} ? 'selected="selected"' : '',
        });
    }
    # DSN templates
    my $dsn;
    if ( $driver eq 'ODBC' ) {
        $dsn = 'DBI:ODBC:Driver={SQL Server};Server={host};Database={db};';
    }
    elsif ( $driver eq 'Oracle' ) {
        $dsn = "DBI:$driver:sid={db};host={host};";
    }
    else {
        $dsn = "DBI:$driver:database={db};host={host};";
    }

    # Populate the template
    $tmpl->param(
        dsn_sample   => $dsn,
        driver_name  => $driver,
        profile_list => \@profile_list,
        label => $dbconfig->{label},
        db    => $dbconfig->{db},
        host  => $dbconfig->{host},
        user  => $dbconfig->{user},
        pass  => $dbconfig->{pass},
        dsn   => $dbconfig->{dsn},
    );
    return $tmpl->output();
}


=head2 dbms_test

This method is called by AJAX from the DB config page. It returns JSON
with the success or error message from testing the input DB settings.

=cut

sub dbms_test {
    my $self = shift;
    # Get the query object
    my $q = $self->query();
    # Get the DB DSN
    my $dsn = $q->param('dsn');

    # Build data structure for return as JSON
    my %return = (
        success => 1,
    );
    # Test the DB config
    unless ( DBI->connect($dsn, $q->param('user'), $q->param('pass'),
        { RaiseError => 0, PrintError => 0, PrintWarn => 0, AutoCommit => 1 }) ) {
        $return{success} = 0;
        $return{error} = $DBI::errstr;
    }
    $self->header_add( -type => 'text/json' );
    return to_json( \%return );
}


=head2 dbms_save

Saves the DB configuration and displays success page.

=cut

sub dbms_save {
    my $self = shift;
    # Load page template
    my $tmpl = $self->load_tmpl('dbms_save.html', 'die_on_bad_params', 0);
    # Get the query object
    my $q = $self->query();
    # Load, update, and save config
    my $dbconfig = _get_dbconfig();
    $dbconfig->{ $q->param('driver') }->{label}   = $q->param('label');
    $dbconfig->{ $q->param('driver') }->{db}      = $q->param('db');
    $dbconfig->{ $q->param('driver') }->{host}    = $q->param('host');
    $dbconfig->{ $q->param('driver') }->{user}    = $q->param('user');
    $dbconfig->{ $q->param('driver') }->{pass}    = $q->param('pass');
    $dbconfig->{ $q->param('driver') }->{dsn}     = $q->param('dsn');
    $dbconfig->{ $q->param('driver') }->{profile} = $q->param('profile');
    open( OUTF, '>db.config' );
        foreach my $driver ( sort keys %$dbconfig ) {
            foreach my $key ( sort keys %{ $dbconfig->{$driver} } ) {
                print OUTF "${driver}_$key=$dbconfig->{$driver}->{$key}\n";
            }#foreach
        }#foreach
    close( OUTF );
    # Populate the template
    $tmpl->param(
        driver_name => $q->param('driver'),
    );
    return $tmpl->output();
}


=head2 profile_config

This is the page is where a profile can be configured.

=cut

sub profile_config {
    my $self = shift;
    # Load page template
    my $tmpl = $self->load_tmpl('profile_config.html', 'die_on_bad_params', 0);
    # Get the query object
    my $q = $self->query();
    my $profile_uid = $q->param('profile');
    # Load in currently configured profile settings
    my $profile = _get_profile( uid => $profile_uid ) if $profile_uid;
    # Get list of available drivers
    my @driver_available = DBI->available_drivers(1);
    
    ## Build data structures for template
    # Driver list
    my @driver_list;
    foreach my $driver ( @driver_available ) {
        push( @driver_list, {
            driver  => $driver,
            checked => _any( $profile->{driver}, $driver ) ? 'checked="checked"' : '',
        });
    }
    # Populate the template
    $tmpl->param(
        %{ $profile },
        driver_list => \@driver_list,
    );

    return $tmpl->output();
}


=head2 profile_save

Saves the profile configuration and displays success page.

=cut

sub profile_save {
    my $self = shift;
    # Load page template
    my $tmpl = $self->load_tmpl('profile_save.html', 'die_on_bad_params', 0);
    # Get the query object
    my $q = $self->query();
    my $old_uid = $q->param('old_uid');
    # Load, update, and save config
    my $profile = _get_profile( uid => $old_uid ) if $old_uid;
    $profile->{uid} = $q->param('uid');
    $profile->{label} = $q->param('label');
    $profile->{rdbms} = $q->param('rdbms');
    $profile->{version} = $q->param('version');
    # The list of drivers must be formatted as an array reference
    my @driver_list = $q->param('driver');
    $profile->{driver} = \@driver_list;
    # Write out to file
    open( OUTF, ">profiles/$profile->{uid}.config" );
        print OUTF Data::Dumper->Dump([$profile], [qw(profile)]);
    close( OUTF );

    # If the profile is changing uid, delete the old profile
    if ( $old_uid && $old_uid ne $profile->{uid} ) {
        unlink( "profiles/$old_uid.config" );
    }
    
    # Populate the template
    $tmpl->param(
        profile_name => $profile->{label},
    );
    return $tmpl->output();
}


=head2 driver_type_list

Displays a list of all the recognised types.

=cut

sub driver_type_list {
    my $self = shift;
    # Load page template
    my $tmpl = $self->load_tmpl('driver_type_list.html', 'die_on_bad_params', 0);
    # Get list of types
    my @type_list;
    # Get the type code -> name
    my $type_name = _get_type_names();
    foreach my $code ( sort { $a <=> $b } keys %$type_name ) {
        push( @type_list, {
            name => $type_name->{$code},
            code => $code,
        });
    }
    # Populate template
    $tmpl->param(
        type_list => \@type_list,
    );
    return $tmpl->output();
}


=head2 compare_driver_types

Displays a table for all the types supported by the configured databases.
The databases local name for the type is given.

=cut

sub compare_driver_types {
    my $self = shift;
    # Load page template
    my $tmpl = $self->load_tmpl('compare_driver_types.html', 'die_on_bad_params', 0);
    # Get list of configured databases
    my $dbconfig = _get_dbconfig();
    my @db_list = sort keys %$dbconfig;
    my @db_row;
    my %db_types;
    foreach my $db ( @db_list ) {
        push( @db_row, {
            db    => $db,
            label => $dbconfig->{$db}->{label},
        });
        my $dbh = DBI->connect( $dbconfig->{$db}->{dsn}, $dbconfig->{$db}->{user}, $dbconfig->{$db}->{pass} );
        # Compile all types
        my $type_info = $dbh->type_info_all();
        foreach my $type ( @$type_info[1..$#$type_info] ) {
            if ( defined $db_types{ $type->[1] }->{$db} ) {
                $db_types{ $type->[1] }->{$db} .= qq~, <a href="compare.cgi?rm=compare_type_details&type=$type->[1]&type_name=$type->[0]&db=$db">$type->[0]</a>~;
            }
            else {
                $db_types{ $type->[1] }->{$db} = qq~<a href="compare.cgi?rm=compare_type_details&type=$type->[1]&type_name=$type->[0]&db=$db">$type->[0]</a>~;
            }
        }
    }#foreach

    # Get the type code -> name
    my $type_name = _get_type_names();

    # Prepare types for templates
    my @type_row;
    foreach my $type ( sort { $a <=> $b } keys %db_types ) {
        my @support_list;
        foreach my $db ( @db_list ) {
            push( @support_list, {
                supported => $db_types{$type}->{$db} || '',
            });
        }
        push( @type_row, {
            type_code => $type,
            type_name => $type_name->{$type},
            support_list => \@support_list,
        });
    }

    # Populate template
    $tmpl->param(
        db_list  => \@db_row,
        type_row => \@type_row,
    );
    return $tmpl->output();
}


=head2 compare_driver_type_details

Displays a table for the chosen types detailed information for the configured
RDBMS's matching types.

=cut

sub compare_driver_type_details {
    my $self = shift;
    # Load page template
    my $tmpl = $self->load_tmpl('compare_driver_type_details.html', 'die_on_bad_params', 0);
    # Get the query object
    my $q = $self->query();
    # Get list of configured databases
    my $dbconfig = _get_dbconfig();
    # Is this DBMS specific?
    my @db_list;
    if ( $q->param('db') ) {
        @db_list = ( $q->param('db') );
    }
    else {
        @db_list = sort keys %$dbconfig;
    }
    # Get the type code -> name
    my $type_name = _get_type_names();
    # Is this type specific
    my @type_list;
    if ( defined $q->param('type') ) {
        @type_list = ( $q->param('type') );
    }
    else {
        @type_list = sort { $a <=> $b } keys %$type_name;
    }

    my %detail_map = (
        TYPE_NAME          =>  0,
        DATA_TYPE          =>  1,
        COLUMN_SIZE        =>  2,
        LITERAL_PREFIX     =>  3,
        LITERAL_SUFFIX     =>  4,
        CREATE_PARAMS      =>  5,
        NULLABLE           =>  6,
        CASE_SENSITIVE     =>  7,
        SEARCHABLE         =>  8,
        UNSIGNED_ATTRIBUTE =>  9,
        FIXED_PREC_SCALE   => 10,
        AUTO_UNIQUE_VALUE  => 11,
        LOCAL_TYPE_NAME    => 12,
        MINIMUM_SCALE      => 13,
        MAXIMUM_SCALE      => 14,
        SQL_DATA_TYPE      => 15,
        SQL_DATETIME_SUB   => 16,
        NUM_PREC_RADIX     => 17,
        INTERVAL_PRECISION => 18,
    );

    # Gather type information    
    my @type_row;
    my %dbh_map;
    foreach my $type ( @type_list ) {
        my @db_row;
        my %db_info;
        my $match_count = 0;
        foreach my $db ( @db_list ) {
            unless ( $dbh_map{$db} ) {
                # Create the DB DSN
                $dbh_map{$db} = DBI->connect( $dbconfig->{$db}->{dsn}, $dbconfig->{$db}->{user}, $dbconfig->{$db}->{pass} );
            }#unless
            # Get the matching types
            my @type_info = $dbh_map{$db}->type_info( $type );
            if ( $q->param('type_name') ) {
                $db_info{$db} = [ grep { $_->{TYPE_NAME} eq $q->param('type_name') } @type_info ];
            }
            else {
                $db_info{$db} = \@type_info;
            }
            my $count = @type_info;
            $match_count += $count;
            $count ||= 1;
            push( @db_row, {
                db      => $db,
                label   => $dbconfig->{$db}->{label},
                colspan => $count,
            });
        }#foreach

        # Make sure we have some matching types
        if ( ! $match_count ) {
            push( @type_row, {
                type_name  => $type_name->{ $type },
                type_code  => $type,
                has_match  => 0,
            });
            next;
        }

        my @detail_row;
        my $count = 0;
        foreach my $detail ( sort { $detail_map{$a} <=> $detail_map{$b} } keys %detail_map ) {
            my @detail_list;
            foreach my $db ( @db_list ) {
                if ( @{ $db_info{$db} } ) {
                    foreach my $type_info ( @{ $db_info{$db} } ) {
                        push( @detail_list, {
                            value => $type_info->{ $detail },
                        });
                    }
                }
                else {
                    push( @detail_list, {
                        value => '',
                    });
                }
            }#foreach
            $count ++;
            push( @detail_row, {
                name        => $detail,
                detail_list => \@detail_list,
                class       => $count % 2 ? 'row_a' : 'row_b',
            });
        }#foreach
        push( @type_row, {
            type_name  => $type_name->{ $type },
            type_code  => $type,
            has_match  => 1,
            detail_row => \@detail_row,
            db_row     => \@db_row,
        });
    }#foreach

    # Populate template
    $tmpl->param(
        type_row => \@type_row,
    );
    return $tmpl->output();
}


=head1 INTERNAL FUNCTIONS

=head2 _get_db_config

Returns a hash for the database configuration.

=cut

sub _get_dbconfig {
    my ( $driver ) = @_;
    my %DBCONFIG;
    open( INF, 'db.config' ) || return {};
        while ( <INF> ) {
            chomp( $_ );
            my ( $key, $value ) = split( /=/, $_, 2 );
            if ( $driver ) {
                next unless $key =~ s/^${driver}_//;
                $DBCONFIG{$key} = $value;
            }
            else {
                my ( $driver, $key ) = split( /_/, $key, 2 );
                $DBCONFIG{$driver}->{$key} = $value;
            }
        }#while
    close( INF );
    return \%DBCONFIG;
}


=head2 _get_profile

Returns a list of profiles or a single hash for the profile configuration.
Can be passed a profile uid to return a single profile, or a driver for a
list of profiles that are valid for that driver.

=cut

sub _get_profile {
    my %param = @_;
    my $profile;
    # Do we want just a single profile?
    if ( $param{uid} ) {
        $profile = do "profiles/$param{uid}.config";
    }
    else {
        $profile = [];
        opendir( DIR, 'profiles' ) || die( 'Cannot open profiles directory' );
            while ( readdir( DIR ) ) {
                # Skip hidden files and folders
                next if $_ =~ /^\./;
                # Skip if it isn't a config file
                next unless $_ =~ /\.config$/;
                # Add profile settings to list
                my $profile_hash = do "profiles/$_";
                # See if we are only returning profiles for a certain driver
                if ( $param{driver} ) {
                    next unless _any( $profile_hash->{driver}, $param{driver} );
                }
                push( @$profile, $profile_hash );
            }#while
        closedir( DIR );
    }#else
    return $profile;
}


=head2 _get_type_name

Returns a hash mapping the type code numbers to their names.

=cut

sub _get_type_names {
    my %type_name;
    {
        no strict 'refs';
        foreach (@{ $DBI::EXPORT_TAGS{sql_types} }) {
            next if $_ eq 'SQL_ALL_TYPES' || $_ !~ /^SQL_/;
            $type_name{ &{"DBI::$_"} } = $_;
        }
    }
    return \%type_name;
}


=head2 _any

Returns true or false dependent of whether the item exists in the array.

=cut

sub _any {
    my ( $list, $item ) = @_;
    foreach ( @$list ) {
        return 1 if $_ eq $item;
    }
    return 0;
}

=head1 CAVEATS

Currently only one RDBMS connection can be configured per driver.

=cut


1;
