
select
	concat('uid=',trim(userid),',ou=',categorycode,',dc=ffzg,dc=hr')	as dn,
	'person
	organizationalPerson
	inetOrgPerson
	hrEduPerson'					as objectClass,

	trim(userid)					as uid,
	firstname					as givenName,
	surname						as sn,
	concat(firstname,' ',surname)			as cn,

	-- SAFEQ specific mappings from UMgr-LDAP.conf
	borrowernumber					as objectGUID,
	surname						as displayName,
	rfid_sid					as pager,
	email						as mail,
	categorycode					as memberOf,
	categorycode					as ou,
	concat('/home/',borrowernumber)			as homeDirectory
from borrowers

