package LDAP::Koha;

use strict;
use warnings;
use Data::Dump qw/dump/;

use lib '../lib';
use Net::LDAP::Constant qw(LDAP_SUCCESS);
use Net::LDAP::Server;
use base 'Net::LDAP::Server';
use fields qw();

use DBI;

# XXX test with:
#
# ldapsearch -h localhost -p 2389 -b dc=ffzg,dc=hr -x 'otherPager=200903160021'
#

our $dsn      = 'DBI:mysql:dbname=';
our $database = 'koha';
our $user     = 'unconfigured-user';
our $passwd   = 'unconfigured-password';

our $max_results = 3; # 100; # FIXME

require 'config.pl' if -e 'config.pl';

my $dbh = DBI->connect($dsn . $database, $user,$passwd, { RaiseError => 1, AutoCommit => 0 }) || die $DBI::errstr;

# Net::LDAP::Entry will lc all our attribute names anyway, so
# we don't really care about correctCapitalization for LDAP
# attributes which won't pass through DBI
my $sql_select = q{
	select
		trim(userid)					as uid,
		firstname					as givenName,
		surname						as sn,
		concat(firstname,' ',surname)			as cn,

		-- SAFEQ specific mappings from UMgr-LDAP.conf
		surname						as displayName,
		cardnumber					as pager,
		email						as mail,
		categorycode					as organizationalUnit,
		borrowernumber					as objectGUID,
		concat('/home/',borrowernumber)			as homeDirectory
	from borrowers
};

# we need reverse LDAP -> SQL mapping for where clause
my $ldap_sql_mapping = {
	'uid'		=> 'userid',
	'objectGUID'	=> 'borrowernumber',
	'displayName'	=> 'surname',
	'sn'		=> 'surname',
	'pager'		=> 'cardnumber',
};

# attributes which are same for whole set, but somehow
# LDAP clients are sending they anyway and we don't
# have them in database
my $ldap_ignore = {
	'objectclass' => 1,
};

sub __sql_column {
	my $name = shift;
	$ldap_sql_mapping->{$name} || $name;
}

use constant RESULT_OK => {
	'matchedDN' => '',
	'errorMessage' => '',
	'resultCode' => LDAP_SUCCESS
};

# constructor
sub new {
	my ($class, $sock) = @_;
	my $self = $class->SUPER::new($sock);
	print "connection from: ", $sock->peerhost(), "\n";
	return $self;
}

# the bind operation
sub bind {
	my $self = shift;
	my $reqData = shift;
	warn "# bind ",dump($reqData);
	return RESULT_OK;
}

our @values;
our @limits;

sub __ldap_search_to_sql {
	my ( $how, $what ) = @_;
	warn "### how $how\n";
	if ( $how eq 'equalityMatch' && defined $what ) {
		my $name = $what->{attributeDesc} || warn "ERROR: no attributeDesc?";
		my $value = $what->{assertionValue} || warn "ERROR: no assertionValue?";
		if ( ! $ldap_ignore->{ $name } ) {
			push @limits, __sql_column($name) . ' = ?';
			push @values, $value;
		}
	} elsif ( $how eq 'substrings' ) {
		foreach my $substring ( @{ $what->{substrings} } ) {
			my $name = $what->{type} || warn "ERROR: no type?";
			while ( my($op,$value) = each %$substring ) {
				push @limits, __sql_column($name) . ' LIKE ?';
				if ( $op eq 'any' ) {
					$value = '%' . $value . '%';
				} else {
					warn "UNSUPPORTED: op $op - using plain $value";
				}
				push @values, $value;
			}
		}
	} elsif ( $how eq 'present' ) {
		my $name = __sql_column( $what );
		push @limits, "$name IS NOT NULL and length($name) > 1";
		## XXX length(foo) > 1 to avoid empty " " strings
	} else {
		warn "UNSUPPORTED: how $how what ",dump( $what );
	}
}

# the search operation
sub search {
	my $self = shift;
	my $reqData = shift;
	print "searching...\n";

	warn "# " . localtime() . " request = ", dump($reqData);

	my $base = $reqData->{'baseObject'}; # FIXME use it?

	my @entries;
	if ( $reqData->{'filter'} ) {

		my $sql_where = '';
		@values = ();

		foreach my $join_with ( keys %{ $reqData->{'filter'} } ) {

			warn "## join_with $join_with\n";

			@limits = ();

			if ( ref $reqData->{'filter'}->{ $join_with } ) {

				foreach my $filter ( @{ $reqData->{'filter'}->{ $join_with } } ) {
					warn "### filter ",dump($filter),$/;
					foreach my $how ( keys %$filter ) {
						if ( $how eq 'or' ) {
							__ldap_search_to_sql( %$_ ) foreach ( @{ $filter->{$how} } );
						} else {
							__ldap_search_to_sql( $how, $filter->{$how} );
						}
						warn "## limits ",dump(@limits), " values ",dump(@values);
					}
				}

				$sql_where .= ' ' . join( " $join_with ", @limits );

			} else {
				__ldap_search_to_sql( $join_with, $reqData->{'filter'}->{$join_with} );
			}

		}

		if ( $sql_where ) {
			$sql_where = " where $sql_where";
		}

		warn "# SQL:\n$sql_select $sql_where\n# DATA: ",dump( @values );
		my $sth = $dbh->prepare( $sql_select . $sql_where . " LIMIT $max_results" ); # XXX remove limit?
		$sth->execute( @values );

		warn "# ", $sth->rows, " results for ",dump( $reqData->{'filter'} );

		while (my $row = $sth->fetchrow_hashref) {

			warn "## row = ",dump( $row );

			my $dn = 'uid=' . $row->{uid} || die "no uid";
			$dn =~ s{[@\.]}{,dc=}g;
			$dn .= ',' . $base unless $dn =~ m{dc}i;

			my $entry = Net::LDAP::Entry->new;
			$entry->dn( $dn );
			$entry->add( objectClass => [
				"person",
				"organizationalPerson",
				"inetOrgPerson",
				"hrEduPerson",
			] );
			$entry->add( %$row );

			#$entry->changetype( 'modify' );

			warn "### entry ",$entry->dump( \*STDERR );

			push @entries, $entry;
		}

	} else {
		warn "UNKNOWN request: ",dump( $reqData );
	}

	return RESULT_OK, @entries;
}

# the rest of the operations will return an "unwilling to perform"

1;
