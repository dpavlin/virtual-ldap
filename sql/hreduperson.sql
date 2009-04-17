
select
	concat('uid=',trim(userid))			as dn,
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
--	categorycode					as memberOf,
	categorycode					as department,
	concat('/home/',borrowernumber)			as homeDirectory
from borrowers
