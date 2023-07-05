FROM ubuntu:23.10
RUN apt update
RUN apt install -y openssh-server sssd libpam-google-authenticator
COPY ./Google_2026_07_03_27704/ /google-certs 
COPY ./configure-debian.sh /configure-debian.sh
RUN chmod +x /configure-debian.sh

ENV domain=yaronshani.info 
ENV certificate_file=/google-certs/Google_2026_07_03_27704.crt
ENV key_file=/google-certs/Google_2026_07_03_27704.key 
ENV should_be_sudoers=no
ENV ldap_groups="cool-users3 cool-users2 cool-users"
ENV sudo_ldap_groups="cool-users3 cool-users2 cool-users" 
ENV ldap_server_uri=ldaps://ldap.google.com
ENV modify_pam_conf=yes

ENV enable_2fa=yes
ENV exclude_2fa_user=ubuntu

RUN /configure-debian.sh

CMD ["/bin/sh", "-c", "sshd -o LogLevel=debug && sssd -i -d 5"]