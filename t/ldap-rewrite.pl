#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 8;
use Data::Dump qw(dump);

BEGIN {
	use_ok 'Net::LDAP';
}

our $config;
ok( require "t/config.pl", 'config.pl' );

sub ldap_check_error {
	my $o = shift;
	ok( ! $o->code, 'no errror' );
	diag $o->error if $o->code;
}

ok( my $ldap = Net::LDAP->new( $config->{server} ), 'new Net::LDAP ' . dump( $config->{server} ) );

ok( my $bind = $ldap->bind( $config->{bind_as}, password => $config->{password} ), 'bind ' . $config->{bind_as} );
ldap_check_error $bind;

ok( my $search = $ldap->search( %{ $config->{search} } ), 'search ' . dump( $config->{search} ) );
ldap_check_error $search;

foreach my $entry ( $search->entries ) {
	diag dump $entry;
}

ok( $ldap->unbind, 'unbind' );
