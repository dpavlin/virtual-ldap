#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 6;
use Test::WWW::Mechanize;

our ( $user, $passwd );
require 'config.pl';

my $url = 'https://localhost:8443'; # Koha intranet

my $mech = Test::WWW::Mechanize->new;

$mech->get_ok( $url, 'intranet' );

$mech->submit_form_ok({
	fields => {
		userid => $user,
		password => $passwd,
	},
}, 'login');

$mech->submit_form_ok({
	form_number => 2,
	fields => {
		member => 'kohatest@ffzg.hr',
	},
}, 'find patron' );

#diag $mech->content;

$mech->follow_link_ok({ url_regex => qr/moremember/ }, 'details' );

my $html = $mech->content();

if ( $html =~ m{(/cgi-bin/koha/members/deletemem\.pl\?member=\d+)}s ) {
	ok( $1, 'found deletemem' );
	$mech->get_ok( $url . $1 );
}
