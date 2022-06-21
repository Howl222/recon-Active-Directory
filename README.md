# recon-Active-Directory

### Description

This script is used to perform a scan to an Active Directory. It can enumerate RCP and SMB using the anonymous user or credentials.

- - -

### ReconAD Usage:
```
reconAD.sh [Options] IP
       -u                       User
       -p                       Password
       -d                       Domain
       --rpc                    Enum users with descriptions
       --rpcg                   Enum users with descriptions and save the users in a file
       --groups                 Enum groups
       --members  [Group]       Enum members of a group
       --shares   [Share]       Enum shares
       -S         [Share]       Enum the share
       -P         [Share]       Enum for writing permision in all directories in the share
       -D         [Share]       Dowload the share
       -B                       Enum users and shares (default)
       -L                       Enum LDAP in Active Directory
       -E         [Wordlist]    Enum users via kerberos
       -W         [File]        Create a wordlist from a file with names
       -h  --help               Help
```






