# Configure Linux machines to use Identity Provider (IdP) for login + 2FA

This project can help you connect your existing Linux machines to either
[Google Workspace](https://workspace.google.com/), [Active Directory](https://en.wikipedia.org/wiki/Active_Directory) 
and probably many others IdPs. It can also help you configure Google Authenticator 2FA for the servers.

The script configure [PAM](https://en.wikipedia.org/wiki/Pluggable_authentication_module) along with [SSSD](https://en.wikipedia.org/wiki/System_Security_Services_Daemon) and
[Google Authenticator PAM module](https://github.com/google/google-authenticator-libpam) to enable 2FA.



### Installation

**DISCLAIMER: It's best to test it on a VM with similar OS before running it on a production machine.
In some cases, it might lock you out of your machine. USE ON YOUR OWN RISK.
It can also be tested using Dockerfile, yet this is still WIP, see the `Dockerfile` for more details.**

Tested on: Ubuntu 23.04, Centos Stream 9

To install run:

`wget -O- https://raw.githubusercontent.com/smulikHakipod/idm-ssh-configurator/main/configure.sh | sudo bash`

The configurator will ask you a few questions and then configure your machine.


### Advanced configuration

The purpose of this configurator is to make a simple config, any further config should be edited by config files:

`/etc/pam.d/common-auth`
`/etc/pam.d/sshd`

Those two files can control whether IdP is optional and probably more.

`/etc/sssd/sssd.conf` can control allowed/deny groups, LDAP filters, and much more.

`/etc/ssh/sshd_config` can control excluded users.

`/etc/ssh/banner` can control the banner that will be shown to the user before login.

### Cleaning up

If you want to remove the configuration you would need to clean the

`# this section added by idm-ssh script` 

section from the above files.