#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use LDAP::Virtual;

LDAP::Virtual->run({ port => 1389 });

1;
