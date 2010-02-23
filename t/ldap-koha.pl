#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 37;
use Data::Dump qw(dump);

BEGIN {
	use_ok 'Net::LDAP';
}

sub ldap_check_error {
	my $o = shift;
	ok( ! $o->code, 'no errror' );
	diag $o->error if $o->code;
}

ok( my $ldap = Net::LDAP->new( 'localhost:2389' ), 'new Net::LDAP' );

ok( my $bind = $ldap->bind, 'bind' );
ldap_check_error $bind;

my @test_searches = ( qw/
uid=dpavlin@ffzg.hr
pager=E00401001F77E218
/ );

sub check_search_attributes {
	my $search = shift;

	foreach my $entry ( $search->entries ) {
		diag dump $entry;
		map { ok( $_, "attribute $_" ) } grep { /^\Q$_\E$/i } $entry->attributes;
	}
}

foreach my $search ( @test_searches ) {

	ok( my $search = $ldap->search( filter => $search ), "search $search" );
	ldap_check_error $search;
	ok( $search->entries, 'have results' );
	check_search_attributes $search => 'uid', 'mail', 'pager', 'memberOf';

}


ok( $ldap->unbind, 'unbind' );
