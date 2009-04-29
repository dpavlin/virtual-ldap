
select
	concat('ou=',c.categorycode,',dc=ffzg,dc=hr')	as dn,
	'organizationalunit'		as objectClass,
	c.categorycode			as ou,
	c.description			as description
from categories c

