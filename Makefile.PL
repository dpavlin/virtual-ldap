use inc::Module::Install;

name        'LDAP-Virtual';
version     '0.00';
license     'GPL';

requires	'IO::Socket::INET';
requires	'Data::Dump';
requires	'YAML';

features(
	'virtual-server.pl (Net::LDAP::Server based)' => [
		-default => 0,
		'Net::LDAP::Server',
		'URI::Escape',
	],
	'ldap-rewrite.pl' => [
		-default => 1,
		'IO::Select',
		'IO::Socket::SSL',
		'Convert::ASN1',
		'Net::LDAP::ASN',
	],
);

auto_install;
	
WriteAll;
