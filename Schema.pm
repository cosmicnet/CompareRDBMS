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

Get/Set the RDBMS profile used for DDL generation. Note that the dbh must be set first,
a check is ran to ensure the profile is valid for the DB driver. Getting the profile
returns the internal Perl data structure for it, not the original XML.

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
        $xml->set( force_array => [ qw( driver token item ) ] );
        my $profile = $xml->parsefile( $profile_file )->{profile};
        # Check the profile and DBH match
        my $match = grep { $self->{CONFIG}->{DBH}->{Driver}->{Name} eq $_ } @{ $profile->{drivers}->{driver} };
        croak( "$profile is not compatible with this database driver" ) unless $match;
        $self->{CONFIG}->{PROFILE} = $profile;
    }
    else {
        # Check schema is loaded
        croak( "No profile has been loaded" ) unless ref $self->{CONFIG}->{PROFILE};
    }
    return $self->{CONFIG}->{PROFILE};
}#sub


=item schema

    $schema->schema( 'db_schema.xml' );
    my $db_schema = $schema->schema();

Get/Set the generic DB schema. Getting the schema returns the internal
Perl data structure for it, not the original XML.

=cut

sub schema {
    my $self = shift;
    my ( $schema_file ) = @_;
    if ( $schema_file ) {
        # Check the schema exists
        croak( "Schema $schema_file does not exist" ) unless -e $schema_file;
        # Load the schema
        my $xml = XML::TreePP->new();
        $xml->set( force_array => [ qw( table column column_ref index constraint ) ] );
        my $schema = $xml->parsefile( $schema_file )->{schema};
        $self->{CONFIG}->{SCHEMA} = $schema;
    }
    else {
        # Check schema is loaded
        croak( "No schema has been loaded" ) unless ref $self->{CONFIG}->{SCHEMA};
    }
    return $self->{CONFIG}->{SCHEMA};
}#sub


=item create

    my $ddl = $schema->create();

Turn the loaded DB schema into DDL statements for the profiles database

Optional arguments:

    output => grouped || separate # Pass statements back grouped together in a string, or as an array
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
        extras           => [],
        drop_tables      => [],
        drop_indexes     => [],
        drop_constraints => [],
        drop_extras      => [],
    };

    my $profile = $self->{CONFIG}->{PROFILE};

    # Process tables
    my $table_listr = $self->{CONFIG}->{SCHEMA}->{table_list}->{table};
    my $ddl = '';
    foreach my $table ( @$table_listr ) {
        print "Table: $table->{definition}->{-name}\n" if $DEBUG;
        $self->{context}->{table} = $table->{definition}->{-name};
        $self->{context}->{indent} = -2;
        if ( $param{output} eq 'grouped' ) {
            # Drop
            $ddl .= $self->_process_element( $profile->{ddl}->{table}->{drop}, $table ) if $param{drop};
            # Create
            $ddl .= $self->_process_element( $profile->{ddl}->{table}->{create}, $table );
        }
        else {

            # Table definition
            push( @{ $self->{ddl}->{tables} }, $self->_process_element( $profile->{ddl}->{table}->{definition}, $table->{definition} ) );
            push( @{ $self->{ddl}->{drop_tables} }, $self->_process_element( $profile->{ddl}->{table}->{drop_table}, $table->{definition} ) ) if $param{drop};

            # Loop indexes
            foreach my $index ( @{ $table->{index} } ) {
                push( @{ $self->{ddl}->{indexes} }, $self->_process_element( $profile->{ddl}->{table}->{index}, $index ) );
                push( @{ $self->{ddl}->{drop_indexes} }, $self->_process_element( $profile->{ddl}->{table}->{drop_index}, $index ) ) if $param{drop};
            }#foreach

            # Loop constraints
            foreach my $constraint ( @{ $table->{constraint} } ) {
                push( @{ $self->{ddl}->{indexes} }, $self->_process_element( $profile->{ddl}->{table}->{constraint}, $constraint ) );
                push( @{ $self->{ddl}->{drop_indexes} }, $self->_process_element( $profile->{ddl}->{table}->{drop_constraint}, $constraint ) ) if $param{drop};
            }#foreach

        }#else
    }#foreach

    return $ddl if $param{output} eq 'grouped';

    # Are we returning the separate statements as an array or string?
    if ( wantarray ) {
        return (
            @{ $self->{ddl}->{drop_constraints} },
            @{ $self->{ddl}->{drop_extras} },
            @{ $self->{ddl}->{drop_indexes} },
            @{ $self->{ddl}->{drop_tables} },
            @{ $self->{ddl}->{tables} },
            @{ $self->{ddl}->{indexes} },
            @{ $self->{ddl}->{constraints} },
            @{ $self->{ddl}->{extras} },
        );
    }#if
    else {
        my $return;
        $return .=
            join( ";\n", @{ $self->{ddl}->{drop_constraints} } ) . "\n\n" .
            join( ";\n", @{ $self->{ddl}->{drop_extras} } ) . "\n\n" .
            join( ";\n", @{ $self->{ddl}->{drop_indexes} } ) . "\n\n" .
            join( ";\n\n", @{ $self->{ddl}->{drop_tables} } ) . "\n" if $param{drop};
        $return .=
            join( ";\n\n", @{ $self->{ddl}->{tables} } ) . "\n" .
            join( ";\n", @{ $self->{ddl}->{indexes} } ) . "\n\n" .
            join( ";\n", @{ $self->{ddl}->{constraints} } ) . "\n\n" .
            join( ";\n", @{ $self->{ddl}->{extras} } );
        return $return;
    }#else
}


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

    my $ti = $self->{CONFIG}->{PROFILE}->{types}->{$type}->{standard};
    # Validate the type is known
    croak( "Cannot quote type '$type' as it is unknown for this profile") unless ref $ti;
    my $lp = $ti->{LITERAL_PREFIX} || '';
    my $ls = $ti->{LITERAL_SUFFIX} || '';
	return $value unless $lp || $ls; # no quoting required

    # Escape any of the literals in the string
	$value =~ s/$lp/$lp$lp/g
		if $lp && $lp eq $ls && ($lp eq "'" || $lp eq '"');
	return "$lp$value$ls";
}


=head1 INTERNAL FUNCTIONS

=head2 _process_element

Takes a database schema element, and the corresponding profile element syntax definition
and produces an SQL statement or list of statements. Element types are either string or list.

=cut

sub _process_element {
    my $self = shift;
    my ( $element, $input ) = @_;
    print "Element: $element->{-is}\n" if $DEBUG;
    # Dispatch to the appropriate element processing routine
    if ( $element->{-is} eq 'string' ) {
        return $self->_process_string(
            $element,
            $element->{-key} ? $input->{ $element->{-key} } : $input,
        );
    }
    elsif ( $element->{-is} eq 'list' ) {
        return $self->_process_element_list(
            $element,
            $element->{-key} ? $input->{ $element->{-key} } : $input,
        );
    }
}


=head2 _process_string

Processes string elements to produce an SQL statement.

=cut

sub _process_string {
    my $self = shift;
    my ( $format, $input ) = @_;
    print 'Format: ' . Dumper( $format ) . 'Input: ' . Dumper( $input ) if $DEBUG > 2;
    my @token_list;
    # Loop through tokens
    foreach my $token ( @{ $format->{token} } ) {
        my $name = $token->{-name};
        if ( $DEBUG > 1 ) {
            my $value = defined $input->{-$name} ? $input->{-$name} : $input->{$name};
            $value ||= '';
            print "  Token: $name is $token->{-is} input: $value\n";
        }
        # See what type of token this is a process accordingly
        if ( $token->{-is} eq 'literal' ) {
            push( @token_list, $token->{-string} );
        }
        elsif ( $token->{-is} eq 'option' ) {
            if ( $input->{-$name} ) {
                push( @token_list, $token->{-if} ) if $token->{-if};
            }
            else {
                push( @token_list, $token->{-else} ) if $token->{-else};
            }
        }
        elsif ( $token->{-is} eq 'variable' ) {
            # Variables can be an attribute, tag or context
            $token->{-from} ||= 'self';
            my $variable;
            if ( $token->{-from} eq 'context' ) {
                $variable = $self->{context}->{$name};
            }
            else {
                $variable = defined $input->{-$name} ? $input->{-$name} : $input->{$name};
            }
            if ( defined $variable ) {
                # Variables can have a modifier to adjusts them
                if ( $token->{modifier} ) {
                    my $mod_option = $token->{modifier}->{-name};
                    my $mod_var = defined $input->{-$mod_option} ? $input->{-$mod_option} : $input->{$mod_option};
                    if ( defined $mod_var ) {
                        $variable = $token->{modifier}->{-prepend} . $variable if $token->{modifier}->{-prepend};
                        $variable .= $token->{modifier}->{-append} if $token->{modifier}->{-append};
                    }
                }
                # Some variables should be properly quoted (DB specific quoting is used)
                if ( $token->{-quote} ) {
                    if ( $token->{-quote} eq 'literal' ) {
                        $variable = $self->{CONFIG}->{DBH}->quote($variable);
                    }
                    elsif ( $token->{-quote} eq 'identifier' ) {
                        $variable = $self->{CONFIG}->{DBH}->quote_identifier($variable);
                    }
                }#if
                $variable = $token->{-prefix} . $variable if $token->{-prefix};
                $variable .= $token->{-suffix} if $token->{-suffix};
                push( @token_list, $variable );
            }#elsif
            # Make sure required elements exist
            elsif ( $token->{-required} ) {
                croak( "Token $name is required" );
            }
        }
        # Some tokens may be elements themselves, in which case dispatch
        elsif ( $token->{-is} eq 'element' ) {
            my $variable = defined $input->{-$name} ? $input->{-$name} : $input->{$name};
            if ( $variable ) {
                my $element = $self->_process_element(
                    $self->{CONFIG}->{PROFILE}->{ddl}->{table}->{$name},
                    $input,
                );
                $element = $token->{-prefix} . $element if $token->{-prefix};
                $element = $element . $token->{-suffix} if $token->{-suffix};
                push( @token_list, $element );
            }
            elsif ( $token->{-required} ) {
                croak( "Token $name is required" );
            }
        }
        # Some tokens will have limited options
        elsif ( $token->{-is} eq 'element_type' ) {
            if ( $input->{-$name} ) {
                my $type_string = $self->_process_element_type( $format->{type}, $input->{-$name} );
                $type_string = $token->{-prefix} . $type_string if $token->{-prefix};
                $type_string = $type_string . $token->{-suffix} if $token->{-suffix};
                push( @token_list, $type_string );
            }
            elsif ( $token->{-required} ) {
                croak( "Token $name is required" );
            }
        }
        # Some tokens will be for types, process using the type details
        elsif ( $token->{-is} eq 'type' ) {
            if ( $input->{-data_type} ) {
                my $type_string = $self->_process_type( $input );
                push( @token_list, $type_string );
            }
            elsif ( $token->{-required} ) {
                croak( "Token $name is required" );
            }
        }
    }
    my $return = join( ' ', @token_list );
    return $return;
}


=head2 _process_type

Processes data types to produce a matching SQL data type.

=cut

sub _process_type {
    my $self = shift;
    my ( $input ) = @_;
    # Get type details from the profile
    my $type_details = $self->{CONFIG}->{PROFILE}->{types}->{ $input->{-data_type} };
    # Check the type is supported
    croak( "Type $input->{-data_type} not supported") unless ref $type_details;
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


=head2 _process_element_type

Processes a limited variable field to produce a matching RDBMS specific option.

=cut

sub _process_element_type {
    my $self = shift;
    my ( $type_list, $value ) = @_;
    print 'Element type: ' . Dumper( $type_list ) . "Value: $value" if $DEBUG > 2;
    # Loop the valid options
    foreach my $type ( @$type_list ) {
        return $type->{-name} if $type->{-name} eq $value;
    }
    croak( "Type $value not supported");
}#sub


=head2 _process_element_list

Processes a list of different element types to produce SQL.

=cut

sub _process_element_list {
    my $self = shift;
    my ( $element, $input ) = @_;
    my @item_list;
    print 'Element: ' . Dumper( $element ) . 'Input: ' . Dumper( $input ) if $DEBUG > 2;
    $self->{context}->{indent} += 2;
    # Loop types of item
    foreach my $item_type ( @{ $element->{item} } ) {
        my $name = $item_type->{-name};
        my $key = $item_type->{-key} || $name;
        # Prepare the element variable name to check if this item exists
        my $variable;
        $item_type->{-from} ||= 'self';
        if ( $item_type->{-from} eq 'context' ) {
            $variable = $self->{context}->{$key};
        }
        elsif ( $item_type->{-from} eq 'this' ) {
            $variable = $input;
        }
        else {
            $variable = $input->{$key}
        }
        print "  Item: $name Key: $key Var: $variable\n" if $DEBUG > 1;
        if ( $variable ) {
            # Turn into array
            my $item_listr = $item_type->{-multiple} ? $variable : [ $variable ];
            print '    Has ' . @$item_listr . "\n" if $DEBUG > 1;
            # Loop items in input
            foreach my $item ( @$item_listr ) {
                # If this item is an element, process as an element
                if ( $item_type->{-is} eq 'element' ) {
                    my $element = $self->_process_element(
                        $self->{CONFIG}->{PROFILE}->{ddl}->{table}->{$name},
                        $item,
                    );
                    if ( $self->{CONFIG}->{FORMAT} ) {
                        my $indent = ' ' x $self->{context}->{indent};
                        $element = "$indent$element";
                    }
                    push( @item_list, $element );
                }
                # If this is just a variable, process as one
                elsif ( $item_type->{-is} eq 'variable' ) {
                    # Variables is the item itself
                    my $variable = $item;
                    if ( $item_type->{-quote} ) {
                        if ( $item_type->{-quote} eq 'literal' ) {
                            $variable = $self->{CONFIG}->{DBH}->quote($variable);
                        }
                        elsif ( $item_type->{-quote} eq 'identifier' ) {
                            $variable = $self->{CONFIG}->{DBH}->quote_identifier($variable);
                        }
                    }#if
                    # Variables might have a prefix or suffix
                    $variable = $item_type->{-prefix} . $variable if $item_type->{-prefix};
                    $variable .= $item_type->{-suffix} if $item_type->{-suffix};
                    if ( $self->{CONFIG}->{FORMAT} ) {
                        my $indent = ' ' x $self->{context}->{indent};
                        $variable = "$indent$variable";
                    }
                    push( @item_list, $variable );
                }
            }#foreach
        }#if
        # Check if the item is required or not
        elsif ( $item_type->{-required} ) {
            croak( "Item $name is required" );
        }
    }#foreach
    $self->{context}->{indent} -= 2;

    # Return here if we are returning an array
    return @item_list if wantarray;

    # Format list as a string and return
    my $indent = ' ' x $self->{context}->{indent};
    my $delimiter = $element->{delimiter};
    # Check for prefix and suffix
    my $prefix = defined $element->{prefix} ? $element->{prefix} : '';
    my $suffix = defined $element->{suffix} ? $element->{suffix} : '';
    # Apply extra formatting if needed
    if ( $self->{CONFIG}->{FORMAT} ) {
        $delimiter .= "\n";
        $prefix .= "\n" if $prefix;
    }
    # Joing string together and return
    my $return = join( $delimiter, @item_list );
    $return = $prefix . $return if $prefix;
    $return .= "\n$indent" if $self->{CONFIG}->{FORMAT} && ! $element->{statement};
    $return = $return . $suffix if $suffix;
    $return .= $element->{statement} ? ";\n" : '';
    return $return;
}#sub


1;
