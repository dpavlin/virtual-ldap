#!/usr/bin/perl
# Copyright (c) 2006 Hans Klunder <hans.klunder@bigfoot.com>. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

# It's modified by Dobrica Pavlinusic <dpavlin@rot13.org> to include following:
#
# * rewrite LDAP bind request cn: username@domain.com -> uid=username,dc=domain,dc=com
# * rewrite search responses:
# ** expand key:value pairs from hrEduPersonUniqueNumber into hrEduPersonUniqueNumber_key
# ** augment response with yaml/dn.yaml data (for external data import)

use strict;
use warnings;

use IO::Select;
use IO::Socket;
use IO::Socket::SSL;
use warnings;
use Data::Dump qw/dump/;
use Convert::ASN1 qw(asn_read);
use Net::LDAP::ASN qw(LDAPRequest LDAPResponse);
our $VERSION = '0.3';
use fields qw(socket target);
use YAML qw/LoadFile/;

my $debug = $ENV{DEBUG} || 0;
$|=1; # flush STDOUT

my $config = {
	yaml_dir => './yaml/',
	listen => shift @ARGV || 'localhost:1389',
	upstream_ldap => 'ldap.ffzg.hr',
	upstream_ssl => 1,
	overlay_prefix => 'ffzg-',
#	log_file => 'log/ldap-rewrite.log',

};

my $log_fh;

sub log {
	my $level = $1 if $_[0] =~ m/^(#+)/;
	return if defined($level) && length($level) > $debug;

	warn join("\n", @_);

	return unless $config->{log_file};

	if ( ! $log_fh ) {
		open($log_fh, '>>', $config->{log_file}) || die "can't open ", $config->{log_file},": $!";
		print $log_fh "# " . time;
	}
	$log_fh->autoflush(1);
	print $log_fh join("\n", @_),"\n";
}

BEGIN {
	$SIG{'__WARN__'} = sub { main::log(@_); }
}


if ( ! -d $config->{yaml_dir} ) {
	warn "DISABLE ", $config->{yaml_dir}," data overlay";
}

warn "# config = ",dump( $config );

sub h2str {
	my $str = dump(@_);
	$str =~ s/\s//g;
	return $str;
}

my $last_reqpdu = '';
my $last_respdu;

sub handle {
 	my $clientsocket=shift;
	my $serversocket=shift;

	# read from client
	asn_read($clientsocket, my $reqpdu);
	if ( ! $reqpdu ) {
		warn "# client closed connection\n";
		return 0;
	}

	if ( h2str($reqpdu) eq $last_reqpdu ) {
		warn "# cache hit";
		print $clientsocket $last_respdu || return 0;
		return 1;
	}

	my $request = $LDAPRequest->decode($reqpdu);
	warn "## request = ",dump($request);

	my $request_filter;
	if (
		exists $request->{searchRequest} &&
		exists $request->{searchRequest}->{filter}
	) {
		my $filter = dump($request->{searchRequest}->{filter});
		$filter =~ s/\s\s+/ /gs;

		warn "# FILTER $filter";
		if ( $filter =~ m/(attributeDesc => "uid")/ ) { # mark uid serach from roundcube for new_user_identity
			warn "filter uid $1";
			$request_filter->{uid} = 1;
		}
		if ( $filter =~ m/(present => "jpegphoto")/ ) {
			warn "hard-coded response for $1";
			print $clientsocket $LDAPResponse->encode( {
				messageID  => $request->{messageID},
				searchResDone => { errorMessage => "", matchedDN => "", resultCode => 0 },
			} ) || return 0;
			return 1;
		}
	}

	$reqpdu = modify_request($reqpdu, $request);

	# send to server
	print $serversocket $reqpdu or die "Could not send PDU to server\n ";

	# read from server
	my $ready;
	my $sel = IO::Select->new($serversocket);
	for( $ready = 1 ; $ready ; $ready = $sel->can_read(0)) {
		asn_read($serversocket, my $respdu);
		if ( ! $respdu ) {
			warn "server closed connection\n";
			return 0;
		}

		$respdu = modify_response($respdu, $reqpdu, $request, $request_filter);

		# cache
		$last_reqpdu = h2str($request->{searchRequest});
		warn "# last_reqpdu $last_reqpdu";
		$last_respdu = $respdu;

		# and send the result to the client
		print $clientsocket $respdu || return 0;


	}

	return 1;
}

sub modify_request {
	my ($pdu,$request)=@_;

	die "empty pdu" unless $pdu;

#	print '-' x 80,"\n";
#	print "Request ASN 1:\n";
#	Convert::ASN1::asn_hexdump(\*STDOUT,$pdu);
#	print "Request Perl:\n";
	if ( defined $request->{bindRequest} ) {
		if ( $request->{bindRequest}->{name} =~ m{@} ) {
			my $old = $request->{bindRequest}->{name};
			$request->{bindRequest}->{name} =~ s/[@\.]/,dc=/g;
			$request->{bindRequest}->{name} =~ s/^/uid=/;
			print "rewrite bind cn $old -> ", $request->{bindRequest}->{name}, "\n";
			Convert::ASN1::asn_hexdump(\*STDOUT,$pdu) if $debug;
			$pdu = $LDAPRequest->encode($request);
			Convert::ASN1::asn_hexdump(\*STDOUT,$pdu) if $debug;
		}
	}

	return $pdu;
}

sub modify_response {
	my ($pdu,$reqpdu,$request,$request_filter)=@_;
	die "empty pdu" unless $pdu;

#	print '-' x 80,"\n";
#	print "Response ASN 1:\n";
#	Convert::ASN1::asn_hexdump(\*STDOUT,$pdu);
#	print "Response Perl:\n";
	my $response = $LDAPResponse->decode($pdu);

	if ( defined $response->{protocolOp}->{searchResEntry} ) {
		my $uid = $response->{protocolOp}->{searchResEntry}->{objectName};
		warn "# rewrite objectName $uid\n";

		my @attrs;

		foreach my $attr ( @{ $response->{protocolOp}->{searchResEntry}->{attributes} } ) {
			if ( $attr->{type} =~ m/date/i ) {
				foreach my $i ( 0 .. $#{ $attr->{vals} } ) {
					$attr->{vals}->[$i] = "$1-$2-$3" if $attr->{vals}->[$i] =~ m/^([12]\d\d\d)([01]\d+)([0123]\d+)$/;
				}
=for disable
			} elsif ( $attr->{type} eq 'hrEduPersonUniqueNumber' ) {
				foreach my $val ( @{ $attr->{vals} } ) {
					next if $val !~ m{.+:.+};
					my ( $n, $v ) = split(/\s*:\s*/, $val );
					push @attrs, { type => $attr->{type} . '_' . $n, vals => [ $v ] };
				}
			} elsif ( $attr->{type} eq 'hrEduPersonGroupMember' ) {
				foreach my $i ( 0 .. $#{ $attr->{vals} } ) {
					$attr->{vals}->[$i] =~ s/^u2010/p2010/gs && warn "FIXME group";
				}
			} elsif ( $attr->{type} eq 'homePostalAddress' ) {
				foreach my $val ( @{ $attr->{vals} } ) {
					next if $val !~ m{^(.+)\s*,\s*(\d+)\s+(.+)};
					push @attrs,
						{ type => 'homePostalAddress_address', vals => [ $1 ] },
						{ type => 'homePostalAddress_zipcode', vals => [ $2 ] },
						{ type => 'homePostalAddress_city', vals => [ $3 ] };
				}
			} elsif ( $attr->{type} eq 'mail' ) {
				my @emails;
				foreach my $i ( 0 .. $#{ $attr->{vals} } ) {
					my $e = $attr->{vals}->[$i];
					if ( $e =~ m/\s+/ ) {
						push @emails, split(/\s+/, $e);
					} else {
						push @emails, $e;
					}
				}
				$attr->{vals} = [ shift @emails ];
				foreach my $i ( 0 .. $#emails ) {
					push @attrs, { type => $attr->{type} . '_' . ( $i + 1 ) , vals => [ $emails[$i] ] };
				}
=cut
			} elsif ( $attr->{type} eq 'mail' ) {
				my @emails;
				foreach my $i ( 0 .. $#{ $attr->{vals} } ) {
					my $e = $attr->{vals}->[$i];
					if ( $e =~ m/\s+/ ) {
						push @emails, split(/\s+/, $e);
					} else {
						push @emails, $e;
					}
				}
				if ( $request_filter->{uid} ) {	# only for new_user_identity plugin which does uid search
					$attr->{vals} = [ grep { m/\@ffzg/ } @emails ];	# remote all emails not @ffzg.hr @ffzg.unizg.hr
				}
			} elsif ( $attr->{type} eq 'facsimileTelephoneNumber' ) {
				my @fax;
				foreach my $i ( 0 .. $#{ $attr->{vals} } ) {
					my $e = $attr->{vals}->[$i];
					push @fax, $e;
				}
				$attr->{vals} = [ grep { ! m/\Q+385 xx xxxx xxx\E/ } @fax ];
			}
		}

		warn "# ++ attrs ",dump( @attrs );

		push @{ $response->{protocolOp}->{searchResEntry}->{attributes} }, $_ foreach @attrs;

=for removed
		my @additional_yamls = ( $uid );
		foreach my $attr ( @{ $response->{protocolOp}->{searchResEntry}->{attributes} } ) {
			foreach my $v ( @{ $attr->{vals} } ) {
				push @additional_yamls, $attr->{type} . '/' . $v;
			}
		}

		#warn "# additional_yamls ",dump( @additional_yamls );

		foreach my $path ( @additional_yamls ) {
			my $full_path = $config->{yaml_dir} . '/' . $path . '.yaml';
			next unless -e $full_path;

			my $data = LoadFile( $full_path );
			warn "# $full_path yaml = ",dump($data);

			foreach my $type ( keys %$data ) {

				my $vals = $data->{$type};

				push @{ $response->{protocolOp}->{searchResEntry}->{attributes} }, {
					type => $config->{overlay_prefix} . $type,
					vals => ref($vals) eq 'ARRAY' ? $vals : [ $vals ],
				};
			}
		}
=cut

		$pdu = $LDAPResponse->encode($response);
	}

	warn "## response = ", dump($response);

	return $pdu;
}


my $listenersock = IO::Socket::INET->new(
	Listen => 5,
	Proto => 'tcp',
	Reuse => 1,
	LocalAddr => $config->{listen},
) || die "can't open listen socket: $!";

our $server_sock;

sub connect_to_server {
	my $sock;
	if ( $config->{upstream_ssl} ) {
		$sock = IO::Socket::SSL->new( $config->{upstream_ldap} . ':ldaps' );
	} else {
		$sock = IO::Socket::INET->new(
			Proto => 'tcp',
			PeerAddr => $config->{upstream_ldap},
			PeerPort => 389,
		);
	}
	die "can't open ", $config->{upstream_ldap}, " $!\n" unless $sock;
	warn "## connected to ", $sock->peerhost, ":", $sock->peerport, "\n";
	return $sock;
}

my $sel = IO::Select->new($listenersock);
while (my @ready = $sel->can_read) {
	foreach my $fh (@ready) {
		if ($fh == $listenersock) {
			# let's create a new socket
			my $psock = $listenersock->accept;
			$sel->add($psock);
			warn "## add $psock " . time;
		} else {
			$server_sock->{$fh} ||= connect_to_server;
			if ( ! handle($fh,$server_sock->{$fh}) ) {
				warn "## remove $fh " . time;
				$sel->remove($server_sock->{$fh});
				$server_sock->{$fh}->close;
				delete $server_sock->{$fh};
				# we have finished with the socket
				$sel->remove($fh);
				$fh->close;
			}
		}
	}
}

1;
