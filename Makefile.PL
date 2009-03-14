use inc::Module::Install;

name        'LDAP-Virtual';
version     '0.00';
license     'GPL';

requires	'Net::LDAP::Server';
requires	'URI::Escape';
requires	'IO::Socket::INET';
requires	'Data::Dump';
requires	'YAML';

auto_install;

WriteAll;
