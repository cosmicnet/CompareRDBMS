#!/usr/bin/perl

=pod

=head1 NAME

compare.cgi - CompareRDBMS web server instantiation script.

=head1 SYNOPSIS

    # Start the tool as local web service on port 8080
    perl compare.cgi 8080
    # Then open in your browser as http://localhost:8080/

=head1 DESCRIPTION

This script is used to start the CompareRDBMS local web server.
It takes one command line argument for the local port that the web server
should attach itself to.

=cut

use strict;
use warnings;

use CGI::Application::Server;
use CompareRDBMS;

my $port = $ARGV[0];
$port ||= 8080;
my $server = CGI::Application::Server->new($port);
$server->document_root('./');
$server->entry_points({
    '/'          => 'CompareRDBMS',
    '/static'    => './',
});
$server->run();
