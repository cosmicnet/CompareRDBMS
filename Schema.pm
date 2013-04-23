package Schema;

=pod

=head1 NAME

Schema - Uses RDBMS profiles to turn generic DB schema definitions into RDBMS specific DDL

=head1 SYNOPSIS

    use Schema;

    my $dbh = ...; # Connect to DB
    my $profile = 'profiles/MySQL_5.xml';
    my $db_schema = 'db_schema.xml';
    my $schema = Schema->new(
        dbh     => $dbh,
        profile => $profile,
        schema  => $db_schema,
    );
    my $ddl = $schema->create;

=cut

use Carp;
use XML::TreePP;
use Data::Dumper;
$Data::Dumper::Indent = 1;

use strict;
use warnings;
my $DEBUG = 0;

=head1 METHODS

=over

=item new

    my $schema = new Schema();

Optional arguments:

    dbh => database handle
    profile => path to profile
    load => path to DB schema

=cut

sub new {
    my $class = shift;
    my %param = @_;
    # Validate params
    my %valid;
    @valid{ 'dbh', 'profile', 'schema', 'format' } = 1..4;
    my @invalid = grep { ! $valid{$_} } keys %param;
    croak( "The arguments @invalid are invalid" ) if @invalid;
    my $self = bless {}, $class;
    # Load settings
    $self->dbh( $param{dbh} ) if $param{dbh};
    $self->profile( $param{profile} ) if $param{profile};
    $self->schema( $param{schema} ) if $param{schema};
    $self->{CONFIG}->{FORMAT} = $param{format} if $param{format};
    return $self;
}#sub


=item dbh

    $schema->dbh( $dbh );
    my $dbh = $schema->dbh();

Get/Set the database handle used for quoting

=cut

sub dbh {
    my $self = shift;
    my ( $dbh ) = @_;
    $self->{CONFIG}->{DBH} = $dbh;
    return $self;
}#sub


=item profile

    $schema->profile( 'profiles/MySQL_5.xml' );
    my $profile = $schema->profile();

Set the RDBMS profile used for DDL generation. Note that the dbh must be set first,
a check is ran to ensure the profile is valid for the DB driver.

=cut

sub profile {
    my $self = shift;
    my ( $profile_file ) = @_;
    if ( $profile_file ) {
        # Check we have a DBH
        croak( 'No database handle set' ) unless ref( $self->{CONFIG}->{DBH} ) eq 'DBI::db';
        # Check the profile exists
        croak( "$profile_file does not exist" ) unless -e $profile_file;
        # Load the profile
        my $xml = XML::TreePP->new();
        $xml->set( force_array => [ qw( driver type rule symbol map map_value ) ] );
        my $profile = $xml->parsefile( $profile_file )->{profile};
        # Work the types, maps, and rules into hashes
        my %type_hash = map { $_->{-name} => $_ } @{ $profile->{type_list}->{type} };
        my %rule_hash = map { $_->{-name} => $_ } @{ $profile->{ddl}->{rule} };
        my %map_hash;
        foreach my $map ( @{ $profile->{ddl}->{map} } ) {
            %{ $map_hash{ $map->{-name} } } = map { $_->{-name} => $_->{-value} } @{ $map->{map_value} };
        }
        $profile->{type} = \%type_hash;
        $profile->{ddl}->{rule} = \%rule_hash;
        $profile->{ddl}->{map} = \%map_hash;
        # Check the profile and DBH match
        my $match = grep { $self->{CONFIG}->{DBH}->{Driver}->{Name} eq $_ } @{ $profile->{drivers}->{driver} };
        croak( "$profile is not compatible with this database driver" ) unless $match;
        $self->{CONFIG}->{PROFILE} = $profile;
    }
    else {
        # Check schema is loaded
        croak( "No profile has been loaded" ) unless ref $self->{CONFIG}->{PROFILE};
    }
    return 1;
}#sub


=item get_type_map

    my $type_hashr = $schema->get_type_map();

Get the list of available types with details.

=cut

sub get_type_map {
    my $self = shift;
    # Check the profile has been loaded
    croak( 'No profile loaded' ) unless ref( $self->{CONFIG}->{PROFILE} );
    return $self->{CONFIG}->{PROFILE}->{type};
}#sub


=item schema

    $schema->schema( 'db_schema.xml' );

Set the generic DB schema from an XML file.

=cut

sub schema {
    my $self = shift;
    my ( $schema_file ) = @_;
    if ( $schema_file ) {
        # Check the schema exists
        croak( "Schema $schema_file does not exist" ) unless -e $schema_file;
        # Load the schema
        my $xml = XML::TreePP->new();
        $xml->set( force_array => [ qw( table column column index unique foreign ) ] );
        my $schema = $xml->parsefile( $schema_file )->{schema};
        $self->{CONFIG}->{SCHEMA} = $schema;
    }
    else {
        # Check schema is loaded
        croak( "No schema has been loaded" ) unless ref $self->{CONFIG}->{SCHEMA};
    }
    return 1;
}#sub


=item get_column_list

    my $column_list = $schema->get_column_list( $table );

Returns a list of columns from the loaded schema for the passed table.

=cut

sub get_column_list {
    my $self = shift;
    my ( $table ) = @_;
    # Check the schema has been loaded
    croak( 'No schema loaded' ) unless ref $self->{CONFIG}->{SCHEMA};
    my ( $table_info ) = grep { $_->{-name} eq $table } @{ $self->{CONFIG}->{SCHEMA}->{table_list}->{table} };
    # Check the table exists
    croak( "Table '$table' does not exist" ) unless $table_info;
    return $table_info->{column_list}->{column};
}#sub


=item create

    my $ddl = $schema->create();

Turn the loaded DB schema into DDL statements for the profiles database

Optional arguments:

    output => grouped || separate # Pass statements back grouped together by table, or as an array
    drop => 1 || 0 # Prepend drop table statements

=cut

sub create {
    my $self = shift;
    # Check we have a DBH, profile, and schema
    croak( 'No database handle set' ) unless ref( $self->{CONFIG}->{DBH} ) eq 'DBI::db';
    croak( 'No database profile set' ) unless ref( $self->{CONFIG}->{PROFILE} );
    croak( 'No database schema set' ) unless ref( $self->{CONFIG}->{SCHEMA} );
    # Load create settings
    my %param = @_;
    # Load default settings
    %param = (
        output => 'separate',
        %param,
    );

    # Prepare DDL array refs for separate statement option
    $self->{ddl} = {
        tables           => [],
        indexes          => [],
        constraints      => [],
        drop_tables      => [],
        drop_indexes     => [],
        drop_constraints => [],
    };

    my $profile = $self->{CONFIG}->{PROFILE};

    # Process tables
    my $table_listr = $self->{CONFIG}->{SCHEMA}->{table_list}->{table};
    my @ddl;
    foreach my $table ( @$table_listr ) {
        print "Table: $table->{-name}\n" if $DEBUG;
        $self->{context}->{table} = $table;
        $self->{context}->{indent} = 0;
        # The output SQL can either be grouped together by table, or separted
        if ( $param{output} eq 'grouped' ) {
            # Drop
            push( @ddl, @{ $self->_process_rule( $profile->{ddl}->{rule}->{drop}, $table ) } ) if $param{drop};
            # Create
            push( @ddl, @{ $self->_process_rule( $profile->{ddl}->{rule}->{create}, $table ) } );
        }
        else {
            # Table definition
            push( @{ $self->{ddl}->{tables} }, $self->_process_rule( $profile->{ddl}->{rule}->{create_table}, $table ) );
            push( @{ $self->{ddl}->{drop_tables} }, $self->_process_rule( $profile->{ddl}->{rule}->{drop_table}, $table ) ) if $param{drop};

            # Indexes
            push( @{ $self->{ddl}->{indexes} }, @{ $self->_process_rule( $profile->{ddl}->{rule}->{create_index_list}, $table->{index_list} ) } ) if $table->{index_list};
            push( @{ $self->{ddl}->{drop_indexes} }, @{ $self->_process_rule( $profile->{ddl}->{rule}->{drop_index_list}, $table->{index_list} ) } ) if $param{drop} && $table->{index_list};

            # Constraints
            push( @{ $self->{ddl}->{constraints} }, @{ $self->_process_rule( $profile->{ddl}->{rule}->{create_constraint_list}, $table->{constraint_list} ) } );
            push( @{ $self->{ddl}->{drop_constraints} }, @{ $self->_process_rule( $profile->{ddl}->{rule}->{drop_constraint_list}, $table->{constraint_list} ) } ) if $param{drop};
        }#else
    }#foreach

    if ( $param{output} eq 'grouped' ) {
        if ( wantarray ) {
            return @ddl;
        }
        else {
            return join( ";\n", @ddl) . ";\n";
        }
    }#if

    # Are we returning the separate statements as an array or string?
    if ( wantarray ) {
        return (
            @{ $self->{ddl}->{drop_constraints} },
            @{ $self->{ddl}->{drop_indexes} },
            @{ $self->{ddl}->{drop_tables} },
            @{ $self->{ddl}->{tables} },
            @{ $self->{ddl}->{indexes} },
            @{ $self->{ddl}->{constraints} },
        );
    }#if
    else {
        my $return;
        $return .=
            join( ";\n", @{ $self->{ddl}->{drop_constraints} } ) . "\n" .
            join( ";\n", @{ $self->{ddl}->{drop_indexes} } ) . "\n" .
            join( ";\n", @{ $self->{ddl}->{drop_tables} } ) . ";\n" if $param{drop};
        $return .=
            join( ";\n", @{ $self->{ddl}->{tables} } ) . "\n" .
            join( ";\n", @{ $self->{ddl}->{indexes} } ) . "\n" .
            join( ";\n", @{ $self->{ddl}->{constraints} } ) . ";\n";
        return $return;
    }#else
}#sub


=item quote

    my $literal = $schema->quote( 'literal string', 'CHAR' );

Based on DBI's quote method, but utilises the profiles type details

=cut

sub quote {
    # Adapted from DBI's quote
    my $self = shift;
	my ( $value, $type ) = @_;

	return "NULL" unless defined $value;
	unless ($type) {
	    $value =~ s/'/''/g; # ISO SQL2
	    return "'$value'";
	}

    my $ti = $self->{CONFIG}->{PROFILE}->{type}->{$type}->{standard};
    # Validate the type is known
    croak( "Cannot quote type '$type' as it is unknown for this profile") unless ref $ti;
    my $lp = $ti->{LITERAL_PREFIX} || '';
    my $ls = $ti->{LITERAL_SUFFIX} || '';
	return $value unless $lp || $ls; # no quoting required

    # Escape any of the literals in the string
	$value =~ s/$lp/$lp$lp/g
		if $lp && $lp eq $ls && ($lp eq "'" || $lp eq '"');
	return "$lp$value$ls";
}#sub

=back

=head1 INTERNAL FUNCTIONS

=over

=item _process_rule

Takes a database schema element, and the corresponding profile syntax rule definition
and produces an SQL statement or list of statements.
Rule types are either statement_list, statement, string_group or string.

=cut

sub _process_rule {
    my $self = shift;
    my ( $rule, $input ) = @_;
    $rule->{-class} ||= 'string';
    print "Rule: $rule->{-class}\n" if $DEBUG;
    # Dispatch to the appropriate rule processing routine
    if ( $rule->{-class} eq 'statement_list' ) {
        return $self->_process_statement_list(
            $rule,
            $input,
        );
    }
    # String components grouped together
    elsif ( $rule->{-class} eq 'string_group' ) {
        my $return = $self->_process_rule_group(
            $rule,
            $input,
        );
        return "$return";
    }
    # Default to string
    else {
        return $self->_process_string(
            $rule,
            $input,
        );
    }
}#sub


=item _process_statement_list

Processes rules to produce a list of SQL statements.

=cut

sub _process_statement_list {
    my $self = shift;
    my ( $format, $input ) = @_;
    print "Statement list\nFormat: " . Dumper( $format ) . 'Input: ' . Dumper( $input ) if $DEBUG > 2;
    my @statement_list;
    # Loop through symbols
    foreach my $symbol ( @{ $format->{symbol} } ) {
        if ( $DEBUG > 1 ) {
            print "  Symbol: $symbol->{-type} ($symbol->{-name})";
        }
        # See what type of symbol this is and process accordingly
        if ( $symbol->{-type} eq 'rule' ) {
            my $key = $symbol->{-subcontext} || $symbol->{-list} || $symbol->{-name};
            my $variable;
            # See if the name, subtext, or list indicate a part of the input
            if ( $key ) {
                $variable = defined $input->{-$key} ? $input->{-$key} : $input->{$key};
            }
            # Without a value set the rule should run with the current input
            unless ( $variable || $symbol->{-subcontext} || $symbol->{-list} ) {
                $variable = $input;
            }
            if ( $DEBUG > 1 ) {
                print "  Subcontext: $symbol->{-subcontext} Variable: $variable\n";
            }
            # Does this rule have input to run
            if ( $variable ) {
                unless ( $symbol->{-list} ) {
                    $variable = [ $variable ];
                }
                # List input will need to be looped
                foreach my $value ( @$variable ) {
                    # Process the rule and add to the statement list
                    my $rule = $self->_process_rule(
                        $self->{CONFIG}->{PROFILE}->{ddl}->{rule}->{ $symbol->{-name} },
                        $value,
                    );
                    if ( ref $rule ) {
                        push( @statement_list, @$rule );
                    }
                    else {
                        push( @statement_list, $rule );
                    }
                }#foreach
            }#if
            # Error if this isn't conditional
            elsif ( ! $symbol->{-condition} ) {
                croak( "$self->{context}->{table}->{-name} $symbol->{-name} $key is missing" );
            }
        }#if
    }#foreach
    return \@statement_list;
}#sub


=item _process_string

Processes string elements to produce an SQL string.

=cut

sub _process_string {
    my $self = shift;
    my ( $rule, $input ) = @_;
    print 'Format: ' . Dumper( $rule ) . 'Input: ' . Dumper( $input ) if $DEBUG > 2;
    my @symbol_list;
    # Loop through the rules symbols
    foreach my $symbol ( @{ $rule->{symbol} } ) {
        my $name = $symbol->{-name} || $symbol->{-condition} || '';
        print "  Symbol: $symbol->{-type} ($name) " if $DEBUG > 1;
        # See what type of symbol this is and process accordingly
        if ( $symbol->{-type} eq 'literal' ) {
            my $value;
            # Literals can be conditional and have a true or false value
            if ( $symbol->{-condition} ) {
                if ( $input->{ -$symbol->{-condition} } || $input->{ $symbol->{-condition} } ) {
                    $value = $symbol->{-true} if $symbol->{-true};
                }
                else {
                    $value = $symbol->{-false} if $symbol->{-false};
                }
            }
            # Otherwise they are always inserted with a fixed value
            else {
                $value = $symbol->{-value};
            }
            print "Value: $value\n" if $DEBUG > 1;
            # Insert value, possibly with quoting
            if ( $value ) {
                if ( $symbol->{-quote} ) {
                    if ( $symbol->{-quote} eq 'literal' ) {
                        $value = $self->{CONFIG}->{DBH}->quote($value);
                    }
                    elsif ( $symbol->{-quote} eq 'identifier' ) {
                        $value = $self->{CONFIG}->{DBH}->quote_identifier($value);
                    }
                }#if
                push( @symbol_list, $value );
            }#if
        }#if
        elsif ( $symbol->{-type} eq 'variable' ) {
            # Variables can be an attribute, from context, or in a map
            my $value;
            if ( $symbol->{-context} ) {
                $value = $self->{context}->{ $symbol->{-context} }->{ -$symbol->{-name} };
            }
            elsif ( $symbol->{-map} ) {
                $value = $self->{CONFIG}->{PROFILE}->{ddl}->{map}->{ $symbol->{-map} }->{ $input };
                croak( "Type $symbol->{-map} not supported") unless $value;
            }
            else {
                $value = defined $input->{-$name} ? $input->{-$name} : $input->{$name};
            }
            print "Value: $value\n" if $DEBUG > 1;
            if ( defined $value ) {
                # Variables can have a modifier that adjusts them
                if ( $symbol->{modifier} ) {
                    my $mod_option = $symbol->{modifier}->{-condition};
                    my $mod_var = defined $input->{-$mod_option} ? $input->{-$mod_option} : $input->{$mod_option};
                    if ( defined $mod_var ) {
                        $value = $symbol->{modifier}->{-prepend} . $value if $symbol->{modifier}->{-prepend};
                        $value .= $symbol->{modifier}->{-append} if $symbol->{modifier}->{-append};
                    }
                }
                $value = $symbol->{-prepend} . $value if $symbol->{-prepend};
                $value .= $symbol->{-append} if $symbol->{-append};
                # Some variables should be properly quoted (DB specific quoting is used)
                if ( $symbol->{-quote} ) {
                    if ( $symbol->{-quote} eq 'literal' ) {
                        $value = $self->{CONFIG}->{DBH}->quote($value);
                    }
                    elsif ( $symbol->{-quote} eq 'identifier' ) {
                        $value = $self->{CONFIG}->{DBH}->quote_identifier($value);
                    }
                }#if
                $value = $symbol->{-prefix} . $value if $symbol->{-prefix};
                $value .= $symbol->{-suffix} if $symbol->{-suffix};
                push( @symbol_list, $value );
            }#elsif
            # Make sure required elements exist
            elsif ( ! $symbol->{-condition} ) {
                croak( "$self->{context}->{table}->{-name} $rule->{-name} $symbol->{-type} $symbol->{-name} $name is required" );
            }
        }
        # Some symbols may be rules themselves, in which case dispatch
        elsif ( $symbol->{-type} eq 'rule' ) {
            my $key = $symbol->{-condition} || $symbol->{-subcontext} || $symbol->{-name};
            my $value;
            # See if the name, condition, or subcontext indicate a part of the input
            if ( $key ) {
                $value = defined $input->{-$key} ? $input->{-$key} : $input->{$key};
            }
            # With out a value set the rule should run with the current input
            unless ( $value || $symbol->{-condition} || $symbol->{-subcontext} ) {
                $value = $input;
            }
            print "Value: $value\n" if $DEBUG > 1;
            if ( $value ) {
                my $rule = $self->_process_rule(
                    $self->{CONFIG}->{PROFILE}->{ddl}->{rule}->{$name},
                    $value,
                );
                push( @symbol_list, $rule );
            }
            elsif ( ! $symbol->{-condition} ) {
                croak( "In table '$self->{context}->{table}->{-name}' $rule->{-name} $symbol->{-type} $symbol->{-name} $key is required" );
            }
        }
        # Some symbols will be for types, process using the type details
        elsif ( $symbol->{-type} eq 'special' ) {
            print "Value: $input->{ -$symbol->{-name} }\n" if $DEBUG > 1;
            if ( $input->{ -$symbol->{-name} } ) {
                my $type_string = $self->_process_type( $input );
                push( @symbol_list, $type_string );
            }
            else {
                croak( "In table '$self->{context}->{table}->{-name}' $rule->{-name} $symbol->{-type} $symbol->{-name} $symbol->{-name} is required" );
            }
        }
    }
    my $return = join( ' ', @symbol_list );
    return $return;
}#sub


=item _process_type

Processes data types to produce a matching SQL data type.

=cut

sub _process_type {
    my $self = shift;
    my ( $input ) = @_;
    # Get type details from the profile
    my $type_details = $self->{CONFIG}->{PROFILE}->{type}->{ $input->{-type} };
    # Check the type is supported
    croak( "Type $input->{-type} not supported") unless ref $type_details;
    my $type_string = $type_details->{standard}->{TYPE_NAME};
    # Process create params if the type definition allows it
    if ( $type_details->{standard}->{CREATE_PARAMS} ) {
        my @type_param_list = split( /,/, $type_details->{standard}->{CREATE_PARAMS} );
        my @param_list;
        # Build the parameter list
        foreach my $param ( @type_param_list ) {
            if ( $input->{param}->{$param} ) {
                my $value = $input->{param}->{$param};
                $value = $type_details->{standard}->{COLUMN_SIZE} if $value eq 'max';
                push( @param_list, $value );
            }
            else {
                last;
            }
        }#foreach
        if ( @param_list ) {
            $type_string .= '(' . join( ', ', @param_list ) . ')';
        }
    }#if
    return $type_string;
}#sub


=item _process_rule_group

Processes several string types and groups them together.

=cut

sub _process_rule_group {
    my $self = shift;
    my ( $rule_group, $input ) = @_;
    my @item_list;
    $self->{context}->{indent} += 2;
    print 'Rule-group: ' . Dumper( $rule_group ) . "Indent: $self->{context}->{indent} Input: " . Dumper( $input ) if $DEBUG > 2;
    # Loop types of symbol
    foreach my $symbol ( @{ $rule_group->{symbol} } ) {
        my $name = $symbol->{-name};
        # Prepare the element variable name to check if this item exists
        my $value;
        if ( $symbol->{-list} ) {
            $value = $input->{ $symbol->{-list} };
        }
        else {
            $value = $input;
        }
        print "  Symbol: $symbol Value: " . Dumper( $value ) . "\n" if $DEBUG > 1;
        if ( $value ) {
            # Turn into array
            my $input_listr = ref $value eq 'ARRAY' ? $value : [ $value ];
            print '    Has ' . @$input_listr . "\n" if $DEBUG > 1;
            # Loop items in input
            foreach my $item ( @$input_listr ) {
                # If this item is a rule, process as such
                if ( $symbol->{-type} eq 'rule' ) {
                    my $return = $self->_process_rule(
                        $self->{CONFIG}->{PROFILE}->{ddl}->{rule}->{$name},
                        $item,
                    );
                    if ( $self->{CONFIG}->{FORMAT} ) {
                        my $indent = ' ' x $self->{context}->{indent};
                        $return = "$indent$return";
                    }
                    push( @item_list, $return );
                }
                # If this is just a variable, process as one
                elsif ( $symbol->{-type} eq 'variable' ) {
                    # Variable is the item itself
                    my $value = $item;
                    if ( ref $item ) {
                        $value = $item->{-value} || $item->{-name};
                    }
                    if ( $symbol->{-quote} ) {
                        if ( $symbol->{-quote} eq 'literal' ) {
                            $value = $self->{CONFIG}->{DBH}->quote($value);
                        }
                        elsif ( $symbol->{-quote} eq 'identifier' ) {
                            $value = $self->{CONFIG}->{DBH}->quote_identifier($value);
                        }
                    }#if
                    if ( $self->{CONFIG}->{FORMAT} ) {
                        my $indent = ' ' x $self->{context}->{indent};
                        $value = "$indent$value";
                    }
                    push( @item_list, $value );
                }
            }#foreach
        }#if
        # Check if the item is required or not
        else {
            croak( "In table '$self->{context}->{table}->{-name}' $rule_group->{-name} $symbol->{-type} $symbol->{-name} $name is required" );
        }
    }#foreach
    $self->{context}->{indent} -= 2;

    # Return here if we are returning an array
    return @item_list if wantarray;

    # Format list as a string and return
    my $indent = ' ' x $self->{context}->{indent};
    my $delimiter = $rule_group->{delimiter};
    # Check for prefix and suffix
    my $prefix = defined $rule_group->{prefix} ? $rule_group->{prefix} : '';
    my $suffix = defined $rule_group->{suffix} ? $rule_group->{suffix} : '';
    # Apply extra formatting if needed
    if ( $self->{CONFIG}->{FORMAT} ) {
        $delimiter .= "\n";
        $prefix .= "\n" if $prefix;
    }
    # Join string together and return
    my $return = join( $delimiter, @item_list );
    $return = $prefix . $return if $prefix;
    $return .= "\n$indent" if $self->{CONFIG}->{FORMAT} && ! $rule_group->{statement};
    $return = $return . $suffix if $suffix;
    $return .= $rule_group->{statement} ? ";\n" : '';
    return $return;
}#sub

=back

=cut

1;
