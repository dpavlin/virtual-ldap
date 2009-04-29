package LDAP::Koha;

use strict;
use warnings;

use lib '../lib';

use Net::LDAP::Constant qw(LDAP_SUCCESS);
use Net::LDAP::Server;
use base 'Net::LDAP::Server';
use fields qw();

use DBI;
use File::Slurp;

use Data::Dump qw/dump/;

# XXX test with:
#
# ldapsearch -h localhost -p 2389 -b dc=ffzg,dc=hr -x 'otherPager=200903160021'
#

our $dsn      = 'DBI:mysql:dbname=';
our $database = 'koha';
our $user     = 'unconfigured-user';
our $passwd   = 'unconfigured-password';

our $max_results = 3000; # FIXME must be enough for all users

our $objectclass = 'HrEduPerson';

$SIG{__DIE__} = sub {
	warn "!!! DIE ", @_;
	die @_;
};

require 'config.pl' if -e 'config.pl';

my $dbh = DBI->connect($dsn . $database, $user,$passwd, { RaiseError => 1, AutoCommit => 1 }) || die $DBI::errstr;

# we need reverse LDAP -> SQL mapping for where clause

my $ldap_sql_mapping = {
	'uid'		=> 'userid',
	'objectGUID'	=> 'borrowernumber',
	'displayName'	=> 'surname',
	'sn'		=> 'surname',
	'pager'		=> 'rfid_sid',
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
	warn "### __ldap_search_to_sql $how ",dump( $what ),"\n";
	if ( $how eq 'equalityMatch' && defined $what ) {
		my $name = $what->{attributeDesc} || warn "ERROR: no attributeDesc?";
		my $value = $what->{assertionValue} || warn "ERROR: no assertionValue?";

		if ( lc $name eq 'objectclass' ) {
			$objectclass = $value;
		} else {
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
		warn "UNSUPPORTED: $how ",dump( $what );
	}
}


# my ( $dn,$attributes ) = _dn_attributes( $row, $base );

sub _dn_attributes {
	my ($row,$base) = @_;

	warn "## row = ",dump( $row );

	die "no objectClass column in ",dump( $row ) unless defined $row->{objectClass};

	$row->{objectClass} = [ split(/\s+/, $row->{objectClass}) ] if $row->{objectClass} =~ m{\n};

	warn "## row = ",dump( $row );

	my $dn = delete( $row->{dn} ) || die "no dn in ",dump( $row );

	# this does some sanity cleanup for our data
	my $base_as_domain = $base;
	$base_as_domain =~ s{dn=}{.};
	$base_as_domain =~ s{^\.}{@};
	$dn =~ s{$base_as_domain$}{};

	$dn .= ',' . $base unless $dn =~ m{,}; # add base if none present

	return ($dn, $row);
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

		foreach my $filter ( keys %{ $reqData->{'filter'} } ) {

			warn "## filter $filter ", dump( $reqData->{'filter'}->{ $filter } ), "\n";

			@limits = ();

			if ( ref $reqData->{'filter'}->{ $filter } eq 'ARRAY' ) {

				foreach my $filter ( @{ $reqData->{'filter'}->{ $filter } } ) {
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

			} else {
				__ldap_search_to_sql( $filter, $reqData->{'filter'}->{$filter} );
			}

			$sql_where .= ' ' . join( " $filter ", @limits ) if @limits;

		}

		my $sql_select = read_file( lc "sql/$objectclass.sql" );
		if ( $sql_where ) {
			if ( $sql_select !~ m{where}i ) {
				$sql_where = " where $sql_where";
			} else {
				$sql_where = " and $sql_where";
			}
		}


		warn "# SQL:\n$sql_select\n", $sql_where ? $sql_where : '-- no where', "\n# DATA: ",dump( @values );
		my $sth = $dbh->prepare( $sql_select . $sql_where . " LIMIT $max_results" ); # XXX remove limit?
		$sth->execute( @values );

		warn "# ", $sth->rows, " results for ",dump( $reqData->{'filter'} );

		my $last_dn = '?';
		my $entry;

		while (my $row = $sth->fetchrow_hashref) {

			my ( $dn, $attributes ) = _dn_attributes( $row, $base );

			warn "# dn $last_dn ... $dn\n";

			if ( $dn ne $last_dn ) {

				if ( $entry ) {
					#$entry->changetype( 'modify' );
					warn "### entry ",$entry->dump( \*STDERR );
					push @entries, $entry;
					undef $entry;
				}

				$entry = Net::LDAP::Entry->new;
				$entry->dn( $dn );

				$entry->add( %$attributes );

			} else {
				foreach my $n ( keys %$attributes ) {
					my $v = $attributes->{$n};
					warn "# attr $n = $v\n";
					$entry->add( $n, $v ) if $entry->get_value( $n ) ne $v;
				}
			}


			$last_dn = $dn;

		}

		warn "### last entry ",$entry->dump( \*STDERR );
		push @entries, $entry;

	} else {
		warn "UNKNOWN request: ",dump( $reqData );
	}

	return RESULT_OK, @entries;
}

# the rest of the operations will return an "unwilling to perform"

1;
