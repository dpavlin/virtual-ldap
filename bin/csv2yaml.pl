#!/usr/bin/perl

use warnings;
use strict;

# cvs2dbi.pl
#
# 03/15/2009 05:06:53 PM CET Dobrica Pavlinusic <dpavlin@rot13.org>

use Data::Dump qw/dump/;
use File::Slurp;
use YAML qw/DumpFile/;
use Text::CSV;
use Encode qw/decode/;

my $debug = 0;

my $path = shift @ARGV || die "usage: $0 file.csv\n";

my $csv = read_file( $path );
$csv = decode('utf-16', $csv);

my @columns;

foreach my $line ( split(/\r?\n/, $csv) ) {

	warn "## $line\n";

	my @fields = split(/;/, $line);
	if ( ! @columns ) {
		@columns = @fields;
		warn "# columns = ",dump( @columns ) if $debug;
		next;
	}

	my $hash;

	warn "# fields = ",dump( @fields ) if $debug;

	foreach ( 0 .. $#fields ) {
		my $n = $columns[$_];
		my $v = $fields[$_];

		$v =~ s{\s*#\s*$}{};
		$v =~ s{^\s+}{};
		$v =~ s{\s+$}{};

		if ( $v =~ m{#} ) {
			my @v = split(/\s*#\s*/, $v);
			foreach my $pos ( 0 .. $#v ) {
				$hash->{ $n . '_' . $pos } = $v[$pos];
				$hash->{ $n . '_mobitel' } = $v[$pos] if $n =~ m{tel} && $v[$pos] =~ m{^09};
			}
		}
		$hash->{ $n } = $v;
	}

	warn dump( $hash ) if $debug;

	my $uuid = $fields[0];

	DumpFile( "yaml/$uuid.yaml", $hash );
}
