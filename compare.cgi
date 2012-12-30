#!/usr/bin/perl

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
