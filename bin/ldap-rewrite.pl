#!/usr/bin/perl
# Copyright (c) 2006 Hans Klunder <hans.klunder@bigfoot.com>. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.


use strict;
use warnings;

use IO::Select;
use IO::Socket;
use warnings;
use Data::Dump qw/dump/;
use Convert::ASN1 qw(asn_read);
use Net::LDAP::ASN qw(LDAPRequest LDAPResponse);
our $VERSION = '0.2';
use fields qw(socket target);
use YAML qw/LoadFile/;

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

if(0) {
		map {
			if ( $_->{type} eq 'postalAddress' ) {
				$_->{vals} = [ 'foobar' ];
			}
		} @{ $response->{protocolOp}->{searchResEntry}->{attributes} };
}

		my $path = "yaml/$uid.yaml";
		if ( -e $path ) {
			my $data = LoadFile($path);
			warn "# yaml = ",dump($data);

			foreach my $type ( keys %$data ) {

				my $vals = $data->{$type};
				$vals =~ s{#\s*$}{};
				
				my @vals = split(/\s*#\s*/, $vals);

				push @{ $response->{protocolOp}->{searchResEntry}->{attributes} },
					{ type => "ffzg-$type", vals => [ @vals ] };
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
	LocalPort => 1389
);


my $targetsock = new IO::Socket::INET (
	Proto => 'tcp',
	PeerAddr => 'ldap.ffzg.hr',
	PeerPort => 389,
);

run_proxy($listenersock,$targetsock);

1;
