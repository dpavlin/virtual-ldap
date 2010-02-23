#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 75;
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

sub check_search_attributes {
	my $search = shift;

	foreach my $entry ( $search->entries ) {
		diag dump $entry;
		map { ok( $_, "attribute $_" ) } grep { /^\Q$_\E$/i } $entry->attributes;
	}
}

sub search {
	my ($ldap,$search) = @_;
	ok( my $search = $ldap->search( filter => $search ), "search $search" );
	ldap_check_error $search;
	ok( $search->entries, 'have results' );
	return $search;
}

foreach my $search ( qw/
uid=dpavlin@ffzg.hr
pager=E00401001F77E218
/ ) {
	my $entries = search $ldap => $search;
	check_search_attributes $entries => 'uid', 'mail', 'pager', 'memberOf';

	$entries = search $ldap => "(&(objectclass=HrEduPerson)($search))";
	check_search_attributes $entries => 'uid', 'mail', 'pager', 'memberOf';
}

search $ldap => $_ foreach ( qw/
objectclass=organizationalUnit
objectclass=group
/ );

ok( $ldap->unbind, 'unbind' );
