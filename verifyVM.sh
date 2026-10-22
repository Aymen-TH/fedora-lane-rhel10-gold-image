#!/bin/bash

# ============================================================
# RHEL 10 GOLD IMAGE - CONFIGURATION VERIFICATION
# ============================================================

# Re-run as root automatically
if [ "$EUID" -ne 0 ]; then
    echo "Root privileges required. Re-running with sudo..."
    exec sudo "$0" "$@"
fi

export LC_ALL=C

PASS=0
FAIL=0

check() {
    local task="$1"
    local command="$2"

    echo "------------------------------------------------------------"
    echo "TASK: $task"
    echo "COMMAND: $command"
    echo "VERIFIED OUTPUT:"

    if eval "$command"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "[CHECK FAILED]"
    fi

    echo
}

echo "============================================================"
echo " RHEL 10 GOLD IMAGE - CONFIGURATION VERIFICATION"
echo "============================================================"
echo "Hostname: $(hostname)"
echo "Date:     $(date)"
echo

# ============================================================
# 1. STORAGE
# ============================================================

check \
"Verify physical disk and separate partitions" \
"lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS"

check \
"Verify persistent filesystem configuration in /etc/fstab" \
"grep -vE '^[[:space:]]*(#|$)' /etc/fstab"

check \
"Verify separate /boot partition" \
"findmnt /boot"

check \
"Verify separate /home partition" \
"findmnt /home"

check \
"Verify separate /tmp partition and noexec" \
"findmnt /tmp | grep -E 'TARGET|/tmp.*noexec'"

check \
"Verify separate /var/log partition" \
"findmnt /var/log"

check \
"Verify separate /var/tmp partition" \
"findmnt /var/tmp"

check \
"Verify swap is active" \
"swapon --show"

# ============================================================
# 2. SELINUX
# ============================================================

check \
"Verify SELinux is enforcing" \
"getenforce | grep -i '^Enforcing$'"

check \
"Verify SELinux HTTP port 35443" \
"semanage port -l | grep '^http_port_t' | grep -w '35443'"

check \
"Verify SELinux SSH port 2222" \
"semanage port -l | grep '^ssh_port_t' | grep -w '2222'"

check \
"Verify Apache document root SELinux context" \
"ls -Zd /var/www/html | grep 'httpd_sys_content_t'"

# ============================================================
# 3. HTTPD
# ============================================================

check \
"Verify httpd package is installed" \
"rpm -q httpd"

check \
"Verify Apache configuration uses port 35443" \
"grep -R '^[[:space:]]*Listen[[:space:]]*35443' /etc/httpd/conf /etc/httpd/conf.d 2>/dev/null"

check \
"Verify httpd is listening on port 35443" \
"ss -lntp | grep ':35443'"

check \
"Verify httpd service is running" \
"systemctl is-active httpd | grep '^active$'"

check \
"Verify httpd starts automatically at boot" \
"systemctl is-enabled httpd | grep '^enabled$'"

check \
"Verify test web page exists" \
"test -f /var/www/html/index.html && ls -l /var/www/html/index.html"

check \
"Verify web page is accessible on port 35443" \
"curl -fsS http://localhost:35443/index.html"

# ============================================================
# 4. SSH
# ============================================================

check \
"Verify SSH effective port is 2222" \
"sshd -T | grep '^port ' | grep -w '2222'"

check \
"Verify SSH server is listening on port 2222" \
"ss -lntp | grep ':2222'"

check \
"Verify root SSH login is disabled" \
"sshd -T | grep '^permitrootlogin ' | grep -w 'no'"

check \
"Verify SSH password authentication is disabled" \
"sshd -T | grep '^passwordauthentication ' | grep -w 'no'"

check \
"Verify sshd configuration syntax" \
"sshd -t && echo 'sshd configuration: OK'"

check \
"Verify sshd service is running" \
"systemctl is-active sshd | grep '^active$'"

check \
"Verify sshd starts automatically at boot" \
"systemctl is-enabled sshd | grep '^enabled$'"

# ============================================================
# 5. ADMIN / SUDO
# ============================================================

check \
"Verify admin group exists" \
"getent group fedora-admins"

check \
"Verify members of admin group" \
"getent group fedora-admins | cut -d: -f4"

check \
"Verify sudo configuration for admin group" \
"grep -R '^[[:space:]]*%fedora-admins[[:space:]]' /etc/sudoers /etc/sudoers.d 2>/dev/null"

check \
"Verify sudo configuration syntax" \
"visudo -c"

# ============================================================
# 6. FIREWALL
# ============================================================

check \
"Verify firewalld is running" \
"systemctl is-active firewalld | grep '^active$'"

check \
"Verify firewalld starts automatically at boot" \
"systemctl is-enabled firewalld | grep '^enabled$'"

check \
"Verify active firewall zone" \
"firewall-cmd --get-active-zones"

check \
"Verify firewall services" \
"firewall-cmd --zone=public --list-services"

check \
"Verify firewall allowed ports" \
"firewall-cmd --zone=public --list-ports"

check \
"Verify SSH port 2222 is allowed" \
"firewall-cmd --zone=public --list-ports | grep -w '2222/tcp'"

check \
"Verify HTTPD port 35443 is allowed" \
"firewall-cmd --zone=public --list-ports | grep -w '35443/tcp'"

check \
"Verify cockpit is NOT allowed" \
"! firewall-cmd --zone=public --list-services | grep -w 'cockpit'"

check \
"Verify standard SSH service is NOT allowed" \
"! firewall-cmd --zone=public --list-services | grep -w 'ssh'"

# ============================================================
# 7. NETWORK LISTENERS
# ============================================================

check \
"Display all listening network ports" \
"ss -lntup"

check \
"Verify required SSH and HTTPD listeners" \
"ss -lntup | grep -E ':2222|:35443'"

# ============================================================
# 8. FINAL SUMMARY
# ============================================================

echo "============================================================"
echo " VERIFICATION SUMMARY"
echo "============================================================"
echo
echo "Checks passed : $PASS"
echo "Checks failed : $FAIL"
echo

if [ "$FAIL" -eq 0 ]; then
    echo "RESULT: ALL CHECKS PASSED"
else
    echo "RESULT: SOME CHECKS FAILED"
    echo "Review the failed checks above."
fi

echo
echo "============================================================"
echo " EXPECTED GOLD IMAGE CONFIGURATION"
echo "============================================================"
echo
echo "Storage:"
echo "  /boot       -> separate partition"
echo "  /           -> separate partition"
echo "  /home       -> separate partition"
echo "  /tmp        -> separate partition + noexec"
echo "  /var/log    -> separate partition"
echo "  /var/tmp    -> separate partition"
echo "  swap        -> active"
echo
echo "Security:"
echo "  SELinux     -> Enforcing"
echo "  SSH         -> port 2222"
echo "  root SSH    -> disabled"
echo "  SSH password authentication -> disabled"
echo
echo "Web:"
echo "  HTTPD       -> port 35443"
echo "  HTTPD       -> enabled at boot"
echo
echo "Firewall:"
echo "  SSH         -> 2222/tcp"
echo "  HTTPD       -> 35443/tcp"
echo "  Other ports -> blocked"
echo
echo "============================================================"
