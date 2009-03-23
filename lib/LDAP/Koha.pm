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

require 'config.pl' if -e 'config.pl';

my $dbh = DBI->connect($dsn . $database, $user,$passwd, { RaiseError => 1, AutoCommit => 0 }) || die $DBI::errstr;

# Net::LDAP::Entry will lc all our attribute names anyway, so
# we don't really care about correctCapitalization for LDAP
# attributes which won't pass through DBI
my $sth = $dbh->prepare(q{
	select
		userid			as uid,
		firstname		as givenName,
		surname			as sn,
		cardnumber		as otherPager,
		email			as mail
	from borrowers
	where
		cardnumber = ?
});

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

# the search operation
sub search {
	my $self = shift;
	my $reqData = shift;
	print "searching...\n";

	warn "# request = ", dump($reqData);

	my $base = $reqData->{'baseObject'}; # FIXME use it?

	my @entries;
	if ( $reqData->{'filter'}->{'equalityMatch'}->{'attributeDesc'} eq 'otherPager' ) {

		my $value = $reqData->{'filter'}->{'equalityMatch'}->{'assertionValue'} || die "no value?";

		$sth->execute( $value );

		warn "# ", $sth->rows, " results for: $value\n";

		while (my $row = $sth->fetchrow_hashref) {

			warn "## row = ",dump( $row );

			my $dn = 'uid=' . $row->{uid} || die "no uid";
			$dn =~ s{[@\.]}{,dc=}g;

			my $entry = Net::LDAP::Entry->new;
			$entry->dn( $dn );
			$entry->add( %$row );

			#warn "## entry ",dump( $entry );

			push @entries, $entry;
		}

	} else {
		warn "UNKNOWN request: ",dump( $reqData );
	}

	return RESULT_OK, @entries;
}

# the rest of the operations will return an "unwilling to perform"

1;
