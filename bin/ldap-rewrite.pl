#!/usr/bin/perl
# Copyright (c) 2006 Hans Klunder <hans.klunder@bigfoot.com>. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.


use strict;
use warnings;

use IO::Select;
use IO::Socket;
use IO::Socket::SSL;
use warnings;
use Data::Dump qw/dump/;
use Convert::ASN1 qw(asn_read);
use Net::LDAP::ASN qw(LDAPRequest LDAPResponse);
our $VERSION = '0.2';
use fields qw(socket target);
use YAML qw/LoadFile/;

my $config = {
	yaml_dir => './yaml/',
	listen => 'localhost:1389',
	upstream_ldap => 'ldap.ffzg.hr',
	upstream_ssl => 1,
	overlay_prefix => 'ffzg-',

};

if ( ! -d $config->{yaml_dir} ) {
	warn "DISABLE ", $config->{yaml_dir}," data overlay";
}

warn "# config = ",dump( $config );

sub handle {
 	my $clientsocket=shift;
	my $serversocket=shift;

	# read from client
	asn_read($clientsocket, my $reqpdu);
	log_request($reqpdu);

	return 1 unless $reqpdu;

	# send to server
	print $serversocket $reqpdu or die "Could not send PDU to server\n ";
	
	# read from server
	my $ready;
	my $sel = IO::Select->new($serversocket);
	for( $ready = 1 ; $ready ; $ready = $sel->can_read(0)) {
		asn_read($serversocket, my $respdu) or return 1;
		$respdu = log_response($respdu);
		# and send the result to the client
		print $clientsocket $respdu;
	}

	return 0;
}


sub log_request {
	my $pdu=shift;

	print '-' x 80,"\n";
	print "Request ASN 1:\n";
	Convert::ASN1::asn_hexdump(\*STDOUT,$pdu);
	print "Request Perl:\n";
	my $request = $LDAPRequest->decode($pdu);
	print dump($request);
}

sub log_response {
	my $pdu=shift;

	print '-' x 80,"\n";
	print "Response ASN 1:\n";
	Convert::ASN1::asn_hexdump(\*STDOUT,$pdu);
	print "Response Perl:\n";
	my $response = $LDAPResponse->decode($pdu);

	if ( defined $response->{protocolOp}->{searchResEntry} ) {
		my $uid = $response->{protocolOp}->{searchResEntry}->{objectName};
		warn "## SEARCH $uid";

		my @attrs;

		map {
			if ( $_->{type} eq 'hrEduPersonUniqueNumber' ) {
				foreach my $val ( @{ $_->{vals} } ) {
					next if $val !~ m{.+:.+};
					my ( $n, $v ) = split(/\s*:\s*/, $val );
					push @attrs, { type => $_->{type} . '_' . $n, vals => [ $v ] };
				}
			}
		} @{ $response->{protocolOp}->{searchResEntry}->{attributes} };

		warn "# ++ attrs ",dump( @attrs );

		push @{ $response->{protocolOp}->{searchResEntry}->{attributes} }, $_ foreach @attrs;

		my $path = $config->{yaml_dir} . "$uid.yaml";
		if ( -e $path ) {
			my $data = LoadFile($path);
			warn "# yaml = ",dump($data);

			foreach my $type ( keys %$data ) {

				my $vals = $data->{$type};
				$vals =~ s{#\s*$}{};
				
				my @vals = split(/\s*#\s*/, $vals);

				push @{ $response->{protocolOp}->{searchResEntry}->{attributes} },
					{ type => $config->{overlay_prefix} . $type, vals => [ @vals ] };
			}
		}

		$pdu = $LDAPResponse->encode($response);
	}

	print dump($response);

	return $pdu;
}

sub run_proxy {
	my $listenersock = shift;
	my $targetsock=shift;

	die "Could not create listener socket: $!\n" unless $listenersock;
	die "Could not create connection to server: $!\n" unless $targetsock;

	my $sel = IO::Select->new($listenersock);
	my %Handlers;
	while (my @ready = $sel->can_read) {
		foreach my $fh (@ready) {
			if ($fh == $listenersock) {
				# let's create a new socket
				my $psock = $listenersock->accept;
				$sel->add($psock);
			} else {
				my $result = handle($fh,$targetsock);
				if ($result) {
					# we have finished with the socket
					$sel->remove($fh);
					$fh->close;
					delete $Handlers{*$fh};
				}
			}
		}
	}
}


my $listenersock = IO::Socket::INET->new(
	Listen => 5,
	Proto => 'tcp',
	Reuse => 1,
	LocalAddr => $config->{listen},
);


my $targetsock = $config->{upstream_ssl}
	? IO::Socket::INET->new(
		Proto => 'tcp',
		PeerAddr => $config->{upstream_ldap},
		PeerPort => 389,
	)
	: IO::Socket::SSL->new( $config->{upstream_ldap} . ':ldaps')
	;

run_proxy($listenersock,$targetsock);

1;
