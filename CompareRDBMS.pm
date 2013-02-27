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
use Tie::IxHash;
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
        profile_detail_save  => 'profile_detail_save',
        profile_type_check   => 'profile_type_check',
        profile_type_copy    => 'profile_type_copy',
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
    if ( my $dbh = DBI->connect($dsn, $q->param('user'), $q->param('pass'),
        { RaiseError => 0, PrintError => 0, PrintWarn => 0, AutoCommit => 1 }) ) {
        $dbh->disconnect;
    }
    else {
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
    # Get the query object
    my $q = $self->query();
    # Load page template
    my $tmpl = $self->load_tmpl('compare_driver_types.html', 'die_on_bad_params', 0);
    # Get list of configured databases
    my $dbconfig = _get_dbconfig();
    my @db_list = sort keys %$dbconfig;
    my @db_row;
    my %db_types;
    my %profile_hash;
    foreach my $db ( @db_list ) {
        my $profile = $dbconfig->{$db}->{profile};
        push( @db_row, {
            db      => $db,
            label   => $dbconfig->{$db}->{label},
            profile => $profile,
            colspan => $profile ? 2 : 1,
        });
        my $dbh = DBI->connect( $dbconfig->{$db}->{dsn}, $dbconfig->{$db}->{user}, $dbconfig->{$db}->{pass} );
        # Compile all types
        my $type_info = $dbh->type_info_all();
        foreach my $type ( @$type_info[1..$#$type_info] ) {
            push( @{ $db_types{ $type->[1] }->{$db} }, $type->[0] );
        }
        $dbh->disconnect;
        # Are we including profiles
        if ( $q->param('profile') && $profile ) {
            $profile_hash{$profile} = _get_profile( uid => $profile );
        }
    }#foreach

    # Get the type code -> name
    my $type_name = _get_type_names();
    # Get the collective names of types
    my $collective = _get_type_collective();

    ## Prepare types for templates
    # Start with collective type names
    my $select_type_list = {};
    my @collective_row;
    while ( my ( $collective_id, $collective_info ) = each %$collective ) {
        # Then sub types
        my @subtype_row;
        while ( my ( $subtype_id, $subtype_info ) = each %{ $collective_info->{sub_type} } ) {
            # Finally types
            my @type_row;
            foreach my $type ( @{ $subtype_info->{type} } ) {
                # With database type support
                my @support_row;
                foreach my $db ( @db_list ) {
                    my $profile = $dbconfig->{$db}->{profile};
                    my @db_type_list;
                    # Loop the DB's type names
                    foreach my $type_name ( @{ $db_types{$type}->{$db} } ) {
                        push( @db_type_list, {
                            collective_id => $collective_id,
                            subtype_id    => $subtype_id,
                            type_code     => $type,
                            type_name     => $type_name,
                            db            => $db,
                            profile       => scalar( $q->param('profile') ) && $profile,
                        });
                    }#foreach
                    my ( $profile_uid, $profile_type_name ) = ( '', '' );
                    if ( $q->param('profile') && $profile ) {
                        $profile_uid = $profile;
                        $profile_type_name = $profile_hash{$profile}->{types}->{$type}->{standard}->{TYPE_NAME};
                    }
                    push( @support_row, {
                        db_type_list      => \@db_type_list,
                        collective_id     => $collective_id,
                        subtype_id        => $subtype_id,
                        type_code         => $type,
                        profile           => $profile_uid,
                        profile_type_name => $profile_type_name,
                    });
                }#foreach
                # Add to type table row
                push( @type_row, {
                    collective_id => $collective_id,
                    subtype_id    => $subtype_id,
                    type_code     => $type,
                    type_name     => $type_name->{$type},
                    support_row   => \@support_row,
                });
                # Add to select type list
                push( @{ $select_type_list->{$collective_id} }, {
                    type_code => $type,
                    type_name => $type_name->{$type},
                });
            }#foreach
            # Add to sub type rows
            push( @subtype_row, {
                collective_id => $collective_id,
                subtype_id    => $subtype_id,
                subtype_label => $subtype_info->{label},
                colspan       => scalar @db_list + scalar( keys %profile_hash ) + 1,
                type_row      => \@type_row,
            });
        }
        # Add to collective rows
        push( @collective_row, {
            collective_id    => $collective_id,
            collective_label => $collective_info->{label},
            colspan          => scalar @db_list + scalar( keys %profile_hash ) + 1,
            subtype_row      => \@subtype_row,
        });
    }#foreach

    # Populate template
    $tmpl->param(
        type_rowspan       => scalar keys %profile_hash ? 2 : 1,
        profile            => scalar $q->param('profile'),
        db_list            => \@db_row,
        collective_row     => \@collective_row,
        numeric_type_list  => $select_type_list->{numeric},
        string_type_list   => $select_type_list->{string},
        datetime_type_list => $select_type_list->{datetime},
        misc_type_list     => $select_type_list->{misc},
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
    # Is this collective, subtype, or type specific?
    my $collective_id = $q->param('collective');
    my $subtype_id = $q->param('subtype');
    my $type_code = $q->param('type');
    # Get the type code -> name
    my $type_name = _get_type_names();
    # Get the collective names of types
    my $collective = _get_type_collective( $collective_id, $subtype_id );
    # Get the standard type details
    my $standard_map = _get_type_details( 'standard' );

    ## Prepare type details for templates
    # Start with collective type names
    my @collective_row;
    while ( my ( $collective_id, $collective_info ) = each %$collective ) {
        # Then sub types
        my @subtype_row;
        while ( my ( $subtype_id, $subtype_info ) = each %{ $collective_info->{sub_type} } ) {
            # Finally types
            my @type_row;
            my %dbh_map;
            # Either the subtype type list or a single type
            my @type_list = $type_code ? ( $type_code ) : @{ $subtype_info->{type} };
            foreach my $type ( @type_list ) {
                my @db_row;
                my %db_info;
                my $match_count = 0;
                # Loop through the driver database connections
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
                foreach my $detail ( sort { $standard_map->{$a} <=> $standard_map->{$b} } keys %$standard_map ) {
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
                # Add to type row
                push( @type_row, {
                    type_name  => $type_name->{ $type },
                    type_code  => $type,
                    has_match  => 1,
                    detail_row => \@detail_row,
                    db_row     => \@db_row,
                });
            }#foreach
            # Add to subtype row
            push( @subtype_row, {
                collective_id => $collective_id,
                subtype_id    => $subtype_id,
                subtype_label => $subtype_info->{label},
                colspan       => scalar @db_list + 1,
                type_row      => \@type_row,
            });
        }
        # Add to collective row
        push( @collective_row, {
            collective_id    => $collective_id,
            collective_label => $collective_info->{label},
            colspan          => scalar @db_list + 1,
            subtype_row      => \@subtype_row,
        });
    }#foreach

    # Populate template
    $tmpl->param(
        collective_row => \@collective_row,
    );
    return $tmpl->output();
}


=head2 compare_profile_types

Displays a table for all the types configured for the databases profile.

=cut

sub compare_profile_types {
    my $self = shift;
    # Load page template
    my $tmpl = $self->load_tmpl('compare_profile_types.html', 'die_on_bad_params', 0);
    # Get list of profiles
    my $profile_list = _get_profile();
    # Get list of configured databases
    my $dbconfig = _get_dbconfig();
    # Make profile -> db map
    my %profile_db;
    foreach my $db ( keys %$dbconfig ) {
        next unless $dbconfig->{$db}->{profile};
        push( @{ $profile_db{ $dbconfig->{$db}->{profile} } }, $dbconfig->{$db}->{label} );
    }
    ## Prepare for templates
    # Heading row
    my @profile_heading;
    foreach my $profile ( @$profile_list ) {
        my $db = 'none';
        $db = join(',', @{ $profile_db{ $profile->{uid} } } ) if ref $profile_db{ $profile->{uid} };
        push( @profile_heading, {
            uid   => $profile->{uid},
            label => $profile->{label},
            db    => $db,
        });
    }#foreach

    # Get the type code -> name
    my $type_name = _get_type_names();
    # Get the collective names of types
    my $collective = _get_type_collective();

    ## Prepare types for templates
    # Start with collective type names
    my @collective_row;
    while ( my ( $collective_id, $collective_info ) = each %$collective ) {
        # Then sub types
        my @subtype_row;
        while ( my ( $subtype_id, $subtype_info ) = each %{ $collective_info->{sub_type} } ) {
            # Finally types
            my @type_row;
            foreach my $type ( @{ $subtype_info->{type} } ) {
                # With database type support
                my @support_row;
                foreach my $profile ( @$profile_list ) {
                    # Show the profiles type name
                    push( @support_row, {
                        collective_id => $collective_id,
                        subtype_id    => $subtype_id,
                        type_code     => $type,
                        type_name     => $profile->{types}->{$type}->{standard}->{TYPE_NAME},
                        profile       => $profile->{uid},
                    });
                }#foreach
                # Add to type table row
                push( @type_row, {
                    collective_id => $collective_id,
                    subtype_id    => $subtype_id,
                    type_code     => $type,
                    type_name     => $type_name->{$type},
                    support_row   => \@support_row,
                });
            }#foreach
            # Add to sub type rows
            push( @subtype_row, {
                collective_id => $collective_id,
                subtype_id    => $subtype_id,
                subtype_label => $subtype_info->{label},
                colspan       => scalar @$profile_list + 1,
                type_row      => \@type_row,
            });
        }
        # Add to collective rows
        push( @collective_row, {
            collective_id    => $collective_id,
            collective_label => $collective_info->{label},
            colspan          => scalar @$profile_list + 1,
            subtype_row      => \@subtype_row,
        });
    }#foreach

    # Populate template
    $tmpl->param(
        profile_heading => \@profile_heading,
        collective_row  => \@collective_row,
    );
    return $tmpl->output();
}


=head2 compare_profile_type_details

Displays a table for the chosen types detailed and extended information for the selected
profile.

=cut

sub compare_profile_type_details {
    my $self = shift;
    # Load page template
    my $tmpl = $self->load_tmpl('compare_profile_type_details.html', 'die_on_bad_params', 0);
    # Get the query object
    my $q = $self->query();
    # Get list of profiles
    my $profile_list = _get_profile();
    # Is this profile specific?
    my $profile_uid = $q->param('profile');
    if ( $profile_uid ) {
        @$profile_list = grep { $_->{uid} eq $profile_uid } @$profile_list;
    }
    # Is this collective, subtype, or type specific?
    my $collective_id = $q->param('collective');
    my $subtype_id = $q->param('subtype');
    my $type_code = $q->param('type');
    # Get the type code -> name
    my $type_name = _get_type_names();
    # Get the collective names of types
    my $collective = _get_type_collective( $collective_id, $subtype_id );

    my ( $standard_map, $extended_map ) = _get_type_details();

    ## Prepare type details for templates
    # Start with collective type names
    my @collective_row;
    while ( my ( $collective_id, $collective_info ) = each %$collective ) {
        # Then sub types
        my @subtype_row;
        while ( my ( $subtype_id, $subtype_info ) = each %{ $collective_info->{sub_type} } ) {
            # Finally types
            my @type_row;
            my %dbh_map;
            # Either the subtype type list or a single type
            my @type_list = $type_code ? ( $type_code ) : @{ $subtype_info->{type} };
            foreach my $type ( @type_list ) {
                my @profile_row;
                my @action_row;
                my $match_count = 0;
                # Loop through the driver database connections
                foreach my $profile ( @$profile_list ) {
                    # Get the matching type
                    my $exist = $profile->{types}->{$type} ? 1 : 0;
                    $match_count += $exist;
                    push( @profile_row, {
                        profile => $profile->{uid},
                        label   => $profile->{label},
                    });
                    # Which actions should be visible for this profiles type
                    push( @action_row, {
                        profile_uid => $profile->{uid},
                        create => ! $exist,
                        edit   => $exist,
                        save   => 0,
                        delete => $exist,
                    });
                }#foreach

                # Now fill in the rows of type standard details
                my @standard_row;
                my $count = 0;
                foreach my $detail ( sort { $standard_map->{$a} <=> $standard_map->{$b} } keys %$standard_map ) {
                    my @detail_list;
                    foreach my $profile ( @$profile_list ) {
                        my $value = '';
                        if ( $profile->{types}->{$type} ) {
                            $value = $profile->{types}->{$type}->{standard}->{$detail};
                        }
                        push( @detail_list, {
                            value => $value,
                            name  => $detail,
                            profile_uid => $profile->{uid},
                        });
                    }#foreach
                    # Count is used to calculate the row's CSS class, making the table a bit more readable
                    $count++;
                    push( @standard_row, {
                        name        => $detail,
                        code        => $standard_map->{$detail},
                        detail_list => \@detail_list,
                        class       => $count % 2 ? 'row_a' : 'row_b',
                    });
                }#foreach

                # Now fill in the rows of type extended details
                my @extended_row;
                $count = 0;
                foreach my $detail ( sort { $extended_map->{$a} <=> $extended_map->{$b} } keys %$extended_map ) {
                    my @detail_list;
                    foreach my $profile ( @$profile_list ) {
                        my $value = '';
                        if ( $profile->{types}->{$type} ) {
                            $value = $profile->{types}->{$type}->{extended}->{$detail};
                        }
                        push( @detail_list, {
                            value => $value,
                            name  => $detail,
                            profile_uid => $profile->{uid},
                        });
                    }#foreach
                    # Count is used to calculate the row's CSS class, making the table a bit more readable
                    $count++;
                    push( @extended_row, {
                        name        => $detail,
                        code        => $extended_map->{$detail},
                        detail_list => \@detail_list,
                        class       => $count % 2 ? 'row_a' : 'row_b',
                    });
                }#foreach

                # Add to type row
                push( @type_row, {
                    type_name    => $type_name->{ $type },
                    type_code    => $type,
                    has_match    => 1,
                    colspan      => scalar @$profile_list + 1,
                    has_match    => $match_count,
                    standard_row => \@standard_row,
                    extended_row => \@extended_row,
                    profile_row  => \@profile_row,
                    action_row   => \@action_row,
                });
            }#foreach
            # Add to subtype row
            push( @subtype_row, {
                collective_id => $collective_id,
                subtype_id    => $subtype_id,
                subtype_label => $subtype_info->{label},
                colspan       => scalar @$profile_list + 1,
                type_row      => \@type_row,
            });
        }
        # Add to collective row
        push( @collective_row, {
            collective_id    => $collective_id,
            collective_label => $collective_info->{label},
            colspan          => scalar @$profile_list + 1,
            subtype_row      => \@subtype_row,
        });
    }#foreach

    # Populate template
    $tmpl->param(
        collective_row => \@collective_row,
    );
    return $tmpl->output();
}


=head2 profile_detail_save

Saves the profile detailed configuration and returns JSON result.

=cut

sub profile_detail_save {
    my $self = shift;
    # Get the query object
    my $q = $self->query();
    # Get profile uid and type
    my $profile_uid = $q->param('profile');
    my $type = $q->param('type');
    # Load, update, and save config
    my $profile = _get_profile( uid => $profile_uid );

    # Are we deleting or updating?
    if ( $q->param('delete') ) {
        delete $profile->{types}->{$type};
    }
    else {
        # Decode the JSON
        $profile->{types}->{$type} = from_json( $q->param('JSONDATA') );
    }

    my %return = (
        success => 1,
    );
    # Write out to file
    open( OUTF, ">profiles/$profile->{uid}.config" ) || do {
        %return = (
            success => 0,
            error   => "Cannot write to file profiles/$profile->{uid}.config",
        );
    };
    if ( $return{success} ) {
        print OUTF Data::Dumper->Dump([$profile], [qw(profile)]);
        close( OUTF );
    }

    return to_json(\%return);
}


=head2 profile_type_check

Checks if a particular profile type exists.

=cut

sub profile_type_check {
    my $self = shift;
    # Get the query object
    my $q = $self->query();
    # Get db and profile type
    my $db = $q->param('db');
    my $type = $q->param('type');

    # Get configured database
    my $dbconfig = _get_dbconfig( $db );

    # Prepare return
    my %return = (
        success => 1,
    );
    # Load profile
    my $profile = eval { _get_profile( uid => $dbconfig->{profile} ) };
    if ( $@ ) {
        $return{success} = 0;
        $return{error} = 'Error opening profile';
    }
    else {
        $return{exists} = 1 if ref $profile->{types}->{$type};
    }

    return to_json(\%return);
}


=head2 profile_type_copy

Copys a driver type definition to a profile type definition.

=cut

sub profile_type_copy {
    my $self = shift;
    # Get the query object
    my $q = $self->query();

    # Get destination profile type
    my $profile_type = $q->param('profile_type');
    # Get source DB driver type
    my $db = $q->param('db');
    my $db_type = $q->param('db_type');
    my $db_type_name = $q->param('db_type_name');

    ## Get DB driver type details
    # Get configured database
    my $dbconfig = _get_dbconfig( $db );
    # Create the DB DSN
    my $dbh = DBI->connect( $dbconfig->{dsn}, $dbconfig->{user}, $dbconfig->{pass} );
    # Get the matching types
    my @type_info = $dbh->type_info( $db_type );
    my ( $db_type_details ) = grep { $_->{TYPE_NAME} eq $db_type_name } @type_info;

    # Prepare return
    my %return = (
        success => 1,
        profile_uid => $dbconfig->{profile},
    );
    # Load profile
    my $profile = eval { _get_profile( uid => $dbconfig->{profile} ) };
    if ( $@ ) {
        $return{success} = 0;
        $return{error} = 'Error opening profile';
    }
    else {
        $profile->{types}->{$profile_type}->{standard} = $db_type_details;
        # Write out to file
        open( OUTF, ">profiles/$dbconfig->{profile}.config" ) || do {
            $return{success} = 0;
            $return{error} = "Cannot write to file profiles/$dbconfig->{profile}.config";
        };
        if ( $return{success} ) {
            print OUTF Data::Dumper->Dump([$profile], [qw(profile)]);
            close( OUTF );
        }
    }

    return to_json(\%return);
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
        $profile = [ sort { $a->{label} cmp $b->{label} } @$profile ];
    }#else
    return $profile;
}


=head2 _get_type_names

Returns a hash mapping the type code numbers to their names.

=cut

sub _get_type_names {
    my %type_name;
    {
        no strict 'refs';
        foreach (@{ $DBI::EXPORT_TAGS{sql_types} }) {
            next if $_ eq 'SQL_ALL_TYPES' || $_ !~ /^SQL_/;
            ( $type_name{ &{"DBI::$_"} } = $_ ) =~ s/SQL_//;
        }
    }
    return \%type_name;
}


=head2 _get_type_details

Returns two hashes for standard and extended type details.

=cut

sub _get_type_details {
    my ( $detail ) = @_;
    # Define the type details
    my %standard_map = (
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
    my %extended_map = (
        MAX_VALUE          =>  0,
        MIN_VALUE          =>  1,
        MAX_UTF8           =>  2,
    );
    # Do we want to return both, or just one?
    if ( $detail ) {
        if ( $detail eq 'standard' ) {
            return \%standard_map;
        }
        elsif ( $detail eq 'extended' ) {
            return \%extended_map;
        }
        else {
            croak( "The requested type detail $detail is unknown" );
        }
    }
    else {
        return ( \%standard_map, \%extended_map );
    }
}


=head2 _get_type_collective

This function returns data structures for data type codes grouped into collective
types and sub types, with associated group labels.

Returns:

No arguments passed: An ordered hash of types divided into collective types and an ordered hash of sub types.

A collective type passed: A hash of the collective types label and ordered hash of sub types.

A collective type, and sub type passed: A hash of the collectives sub types label, and array of type codes.

=cut

sub _get_type_collective {
    my ( $collective, $sub_type ) = @_;
    # Tie hashes with Tie::IxHash so that the keys maintain order
    tie my %numeric, 'Tie::IxHash';
    %numeric = (
        exact => {
            label => 'Exact',
            type  => [-6, 5, 4, -5, 2, 3],
        },
        approximate => {
            label => 'Approximate',
            type  => [7, 6, 8],
        },
    );
    tie my %string, 'Tie::IxHash';
    %string = (
        character => {
            label => 'Character',
            type  => [1, -8, 12, -9, -1, -10, 40, 41],
        },
        binary => {
            label => 'Binary',
            type  => [-2, -3, -4, 30, 31],
        },
    );
    tie my %datetime, 'Tie::IxHash';
    %datetime = (
        date => {
            label => 'Date',
            type  => [9, 91],
        },
        time => {
            label => 'Time',
            type  => [10, 92, 94],
        },
        timestamp => {
            label => 'Timestamp',
            type  => [11, 93, 95],
        },
        interval => {
            label => 'Interval',
            type  => [101..113],
        },
    );
    tie my %misc, 'Tie::IxHash';
    %misc = (
        all => {
            label => 'All',
            type  => [-11, -7, 16..20, 50, 51, 55, 56],
        },
    );
    # Put into list of collective types
    tie my %collective_list, 'Tie::IxHash';
    %collective_list = (
        numeric => {
            label    => 'Numeric Types',
            sub_type => \%numeric,
        },
        string => {
            label    => 'String Types',
            sub_type => \%string,
        },
        datetime => {
            label    => 'Datetime Types',
            sub_type => \%datetime,
        },
        misc => {
            label    => 'Miscellaneous Types',
            sub_type => \%misc,
        },
    );
    # Do we only want part of this list
    if ( $collective ) {
        tie my %return, 'Tie::IxHash';
        if ( $sub_type ) {
            #return $collective_list{$collective}->{sub_type}->{$sub_type};
            %return = (
                $collective => {
                    label => $collective_list{$collective}->{label},
                    sub_type => {
                        $sub_type => $collective_list{$collective}->{sub_type}->{$sub_type},
                    },
                },
            );
            return \%return;
        }
        else {
            #return $collective_list{$collective};
            %return = (
                $collective => $collective_list{$collective},
            );
            return \%return;
        }#else
    }
    return \%collective_list;
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
