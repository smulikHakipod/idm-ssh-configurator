#!/bin/bash

# check if sssd.conf exists
if [ -f /etc/sssd/sssd.conf ]; then
    printf 'SSSD configuration file already exists. Please remove it (if you dont need it!) and run this script again.\n'
    exit 1
fi

# Check if pam_sss.so is already in /etc/pam.d/sshd
if [ -f /etc/pam.d/sshd ] && grep -q "pam_sss.so" /etc/pam.d/sshd; then
    printf 'pam_sss.so is already in /etc/pam.d/sshd. Please remove it and run this script again.\n'
    exit 1
fi

# grep for "this section added by idm-ssh script" in /etc/pam.d/sshd or /etc/ssh/sshd_config and if found exit with error
if [ -f /etc/pam.d/sshd ] && grep -q "this section added by idm-ssh script" /etc/pam.d/sshd; then
    printf 'Leftovers of this script found /etc/pam.d/sshd. Please remove it and run this script again.\n'
    printf 'For more info see https://github.com/smulikHakipod/idm-ssh-configurator\n'
    exit 1
fi

if [ -f /etc/ssh/sshd_config ] && grep -q "this section added by idm-ssh script" /etc/ssh/sshd_config; then
    printf 'Leftovers of this script found /etc/ssh/sshd_config. Please remove it and run this script again.\n'
    printf 'For more info see https://github.com/smulikHakipod/idm-ssh-configurator\n'
    exit 1
fi

# If it already comes from env variable, don't ask for it
while [ -z "$domain" ]; do
    # Ask for the domain
    printf 'Please enter the domain: '
    read -r domain
done

# Split the domain into its components and prefix each with dc=
IFS='.' read -ra ADDR <<< "$domain"
base_dn=""
for i in "${ADDR[@]}"; do
    if [ -z "$base_dn" ]; then
        base_dn="dc=$i"
    else
        base_dn="$base_dn,dc=$i"
    fi
done


while [ -z "$certificate_file" ]; do
    # Ask for the certificate and key files
    printf 'Please enter the full path to the certificate file (ldap-client.crt): '
    read -r certificate_file
done

while [ -z "$key_file" ]; do
    # Ask for the certificate and key files
    printf 'Please enter the full path to the key file (ldap-client.key): '
    read -r key_file
done

if [ ! -f "$key_file" ]; then
    printf 'Key file does not exist.\n'
    exit 1
fi

# Copy the certificate and key files to /var
cp "$certificate_file" /etc/sssd/ldap-client.crt
cp "$key_file" /etc/sssd/ldap-client.key

# Ask for LDAP groups
if [ -z "$ldap_groups" ]; then
    printf 'Please enter LDAP groups that should have access to the server (separated by spaces), if empty would be all: '
    read -r ldap_groups
fi

# Ask for LDAP groups with sudo access
if [ -z "$sudo_ldap_groups" ]; then
    printf 'Please enter LDAP groups that should have sudo access if any (separated by spaces), if empty would be none: '
    read -r sudo_ldap_groups
fi


# Ask for LDAP server URI
while [ -z "$ldap_server_uri" ]; do
    printf 'Please enter the LDAP server URI (e.g ldaps://ldap.google.com): '
    read -r ldap_server_uri
done

# Ask for 2FA enabled
while [ -z "$enable_2fa" ]; do
    printf "Do you want to enable 2FA? (yes/no): "
    read -r enable_2fa
    if [ "$enable_2fa" == "yes" ]; then
        # Ask for 2FA excluded user
        if [ -z "$exclude_2fa_user" ]; then
            # if empty, ask again in a loop
            while [ -z "$exclude_2fa_user" ]; do
                printf "Please enter user to exclude from 2FA (e.g centos/root/ubuntu/etc), this is recommended for 'break glass' scenarios where 2FA fail: "
                read -r exclude_2fa_user
            done

        fi
    fi
done


# Install necessary packages
# check if apt is installed and use it

if [ -x "$(command -v apt)" ]; then
    apt update
    apt install -y openssh-server sssd sudo
    if [ "$enable_2fa" == "yes" ]; then
        apt install -y libpam-google-authenticator
    fi
elif [ -x "$(command -v yum)" ]; then
    yum install -y openssh-server sssd sudo authconfig
    if [ "$enable_2fa" == "yes" ]; then
        yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
        yum install -y google-authenticator
    fi
fi

# a function that appends a file (with multiple lines) and prompting the user with the change. Also makes a backup of the file.   
function append_file {
    file=$1
    lines=$2
    backup_file=$file.bak

    # ask for confirmation with the file content and the change only if the shell is interactive
    printf "The following lines will be appended to %s:\n" "$file"
    printf "%s\n" "$lines"
    printf 'Continue? (yes/no): '
    read -r modify_file
    # if shell is not interactive, no need to ask for confirmation
    if [ -n "$PS1" ] && [ "$modify_file" != "yes" ]; then
        printf 'Aborting.\n'
        exit 1
    fi

    if [ -f "$file" ]; then
        cp "$file" "$backup_file"
        printf "Backup of %s created at %s\n" "$file" "$backup_file"
    fi

    {
      echo "# this section added by idm-ssh script"
      echo "# please remove it if you want to revert to the original configuration"
      echo "$lines"
      echo "# end of idm-ssh script section"
    } >>"$file"
}



# Configure sudoers
change_sudoers() {
    for group in $sudo_ldap_groups; do
        echo "%$group ALL=(ALL) ALL"
    done
}

# check if sudo_ldap_groups is not empty then append following lines to sudoers
if [ ${#sudo_ldap_groups} -gt 0 ]; then
    append_file /etc/sudoers "$(change_sudoers)"
fi


ldap_access_filter="(|"
for group in $ldap_groups; do
    ldap_access_filter+="(memberOf=cn=${group},ou=groups,$base_dn)"
done
ldap_access_filter+=")"

# Write sssd.conf
cat >/etc/sssd/sssd.conf <<EOF
[sssd]
services = nss, pam
domains = $domain

[domain/$domain]
debug_level = 9
ldap_tls_cert = /etc/sssd/ldap-client.crt
ldap_tls_key = /etc/sssd/ldap-client.key
ldap_uri = $ldap_server_uri
ldap_search_base = $base_dn
id_provider = ldap
auth_provider = ldap
ldap_schema = rfc2307bis
ldap_user_uuid = entryUUID
EOF

# check if ldap_groups is not empty then append following lines to sssd.conf
#ldap_access_order = filter
#ldap_access_filter = $ldap_access_filter

if [ -n "$ldap_groups" ]; then
    {
      echo "access_provider = ldap"
      echo "ldap_access_order = filter"
      echo "ldap_access_filter = $ldap_access_filter"
    } >> /etc/sssd/sssd.conf
fi

chmod 600 /etc/sssd/sssd.conf



pam_content_change() {
#    echo 'auth       [success=1 default=ignore]      pam_sss.so use_first_pass'
#    echo 'account    [default=bad success=ok user_unknown=ignore]     pam_sss.so'
#    echo 'password   sufficient     pam_sss.so'
#    echo 'session    optional     pam_sss.so'
    echo "session    required     pam_mkhomedir.so skel=/etc/skel/ umask=0022"
    if [ "$enable_2fa" == "yes" ]; then
        echo "auth       required     pam_google_authenticator.so nullok"
    fi
}

append_file /etc/pam.d/sshd "$(pam_content_change)"

# In case of redhat/centos run "authconfig --enablesssd --update"
if [ -x "$(command -v authconfig)" ]; then
    authconfig --enablesssd --update
fi

printf 'Services sshd and sssd restarted.\n'

cat >> /etc/ssh/banner <<EOF
Hi!
This server is managed by identity management (e.g Google/Active Directory/Okta/etc) instead of regular password or private keys.
You should login using your identity user or email e.g "ssh john@my-company.com@4.4.4.4"
EOF




ssh_banner_content() {
  echo "Banner /etc/ssh/banner"
}
append_file /etc/ssh/sshd_config "$(ssh_banner_content)"

if [ "$enable_2fa" == "yes" ]; then

cat >> /etc/ssh/banner <<EOF

This server also have 2FA enforced on it, which mean you need to register your device using Google Authenticator app if its your first time.
You will be promoted for that when you login for the first time. Please scan the barcode using Google Authenticator app and enter the code to complete the registration.
Be advised that you can share your authenticator between multiple servers.
Thank you for your cooperation.
EOF

cat > /usr/local/bin/force_command.sh <<'EOF'
#!/bin/bash
if [ -f ~/.google_authenticator ]; then
    # 2FA file exists, allow execution of the original command
    exec $SHELL
else
    echo "You must set up Two-Factor Authentication to access this server."
    printf "Do you want to import your key from another server? (yes/no): "
    read import_key
    
    if [ "$import_key" == "y" ] || [ "$import_key" == "yes" ]; then
        echo "Please enter the content of your ~/.google_authenticator file. Enter 'end' on a new line to end:"
        google_authenticator_content=""
        while read -r line; do
            if [[ $line == "end" ]]; then
                break
            fi
            google_authenticator_content+="$line"$'\n'
        done

        echo "$google_authenticator_content" > ~/.google_authenticator
        chmod 600 ~/.google_authenticator
    else
        google-authenticator
    fi
    echo "Now please login again with your 2FA code."
fi
EOF
sudo chmod +x /usr/local/bin/force_command.sh

ssh_content() {
    printf "Match User *,!%s\n" "$exclude_2fa_user"
    printf "    ForceCommand /usr/local/bin/force_command.sh\n"
    printf "ChallengeResponseAuthentication yes\n"
}

append_file /etc/ssh/sshd_config "$(ssh_content)"

fi ## enable_2fa fi


# Restart services
echo "Restarting services sshd + sssd..."
systemctl restart sshd
systemctl restart sssd