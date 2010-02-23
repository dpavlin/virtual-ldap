#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 4;
use Test::WWW::Mechanize;
use File::Slurp;

our $config;
require 't/config.pl';

use WWW::Mechanize;

my $mech = Test::WWW::Mechanize->new;

my $save_count = 1;
sub save {
	my $path = '/tmp/login-' . $save_count++ . '.html';
	write_file $path, @_;
	warn "# save $path ", -s $path, " bytes\n";
}
	

$mech->get_ok( 'https://localhost', 'opac' );
save $mech->content;

$mech->follow_link_ok({ text_regex => qr/Log in to Your Account/i }, 'login form' );
save $mech->content;

$mech->submit_form_ok({
	form_number => 2,
	fields => {
		userid => $config->{bind_as},
		password => $config->{password},
	},
}, 'login');
save $mech->content;

$mech->follow_link_ok({ url_regex => qr/logout/ }, 'logout' );
