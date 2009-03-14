#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use VLDAP::Server;

VLDAP::Server->run({ port => 1389 });

1;
