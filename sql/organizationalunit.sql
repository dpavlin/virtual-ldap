
select
	concat('ou=',categorycode)	as dn,
	'top
	organizationalUnit'		as objectClass,
	categorycode			as ou,
	description			as description,

	-- fake objectGUID since we don't have primary key
	crc32(categorycode)		as objectGUID

from categories
