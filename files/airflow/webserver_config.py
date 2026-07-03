from flask_appbuilder.security.manager import AUTH_LDAP

AUTH_TYPE = AUTH_LDAP
AUTH_LDAP_SERVER = "ldaps://openldap.default.svc.cluster.local:636"
AUTH_LDAP_USE_TLS = False
AUTH_LDAP_ALLOW_SELF_SIGNED = True
AUTH_LDAP_TLS_DEMAND = False

AUTH_LDAP_SEARCH = "ou=users,dc=example,dc=org"
AUTH_LDAP_BIND_USER = "cn=admin,dc=example,dc=org"
AUTH_LDAP_BIND_PASSWORD = ""#подставляется из env

AUTH_LDAP_UID_FIELD = "uid"
AUTH_LDAP_GROUP_FIELD = "memberOf"
AUTH_LDAP_SEARCH_FILTER = "(objectClass=inetOrgPerson)"

AUTH_ROLES_SYNC_AT_LOGIN = True
AUTH_USER_REGISTRATION = True
AUTH_USER_REGISTRATION_ROLE = "Public"

AUTH_ROLES_MAPPING = {
    "cn=admins,ou=groups,dc=example,dc=org": ["Admin"],
    "cn=analysts,ou=groups,dc=example,dc=org": ["Viewer"],
}