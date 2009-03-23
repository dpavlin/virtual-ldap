#!/usr/bin/perl

use strict;
use warnings;

use IO::Select;
use IO::Socket;
use lib 'lib';
use LDAP::Koha;

my $port = 2389;

my $sock = IO::Socket::INET->new(
	Listen => 5,
	Proto => 'tcp',
	Reuse => 1,
	LocalPort => $port,
) || die;

warn "# listening on $port";

my $sel = IO::Select->new($sock);
my %Handlers;
while (my @ready = $sel->can_read) {
	foreach my $fh (@ready) {
		if ($fh == $sock) {
			# let's create a new socket
			my $psock = $sock->accept;
			$sel->add($psock);
			$Handlers{*$psock} = LDAP::Koha->new($psock);
		} else {
			my $result = $Handlers{*$fh}->handle;
			if ($result) {
				# we have finished with the socket
				$sel->remove($fh);
				$fh->close;
				delete $Handlers{*$fh};
			}
		}
	}
}

1;
