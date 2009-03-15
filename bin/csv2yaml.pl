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

	$hash->{ $columns[$_] } = $fields[$_] foreach ( 0 .. $#fields );

	warn dump( $hash ) if $debug;

	my $uuid = $fields[0];

	DumpFile( "yaml/$uuid.yaml", $hash );
}
