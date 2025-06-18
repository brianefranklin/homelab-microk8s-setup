#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Fail2Ban Configuration Variables ---
# bantime: The duration (in seconds) for which an IP is banned. (e.g., 3600 = 1 hour)
FAIL2BAN_BANTIME=3600
# findtime: The time window (in seconds) during which 'maxretry' failures must occur to trigger a ban. (e.g., 600 = 10 minutes)
FAIL2BAN_FINDTIME=600
# maxretry: The number of failed login attempts before an IP is banned.
FAIL2BAN_MAXRETRY=3
# --------------------------------------

echo "Starting Fail2Ban installation and configuration..."

# 1. Update package list
echo "Updating package list..."
sudo apt update

# 2. Install Fail2Ban
echo "Installing Fail2Ban..."
sudo apt install fail2ban -y

# 3. Create a local configuration file
echo "Creating local Fail2Ban configuration file (jail.local)..."
if [ -f /etc/fail2ban/jail.local ]; then
    echo "/etc/fail2ban/jail.local already exists. Backing it up to /etc/fail2ban/jail.local.bak.$(date +%s)..."
    sudo cp /etc/fail2ban/jail.local "/etc/fail2ban/jail.local.bak.$(date +%s)"
fi
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# 4. Edit the local configuration file for [DEFAULT] settings
echo "Configuring [DEFAULT] settings in /etc/fail2ban/jail.local..."

# Configure bantime
if sudo grep -qE "^[#[:space:]]*bantime[[:space:]]*=" /etc/fail2ban/jail.local; then
    sudo sed -i -E "s/^[#[:space:]]*bantime[[:space:]]*=.*/bantime = $FAIL2BAN_BANTIME/" /etc/fail2ban/jail.local
else
    # Add under [DEFAULT] if not found at all
    sudo sed -i "/^\[DEFAULT\]/a bantime = $FAIL2BAN_BANTIME" /etc/fail2ban/jail.local
fi

# Configure findtime
if sudo grep -qE "^[#[:space:]]*findtime[[:space:]]*=" /etc/fail2ban/jail.local; then
    sudo sed -i -E "s/^[#[:space:]]*findtime[[:space:]]*=.*/findtime = $FAIL2BAN_FINDTIME/" /etc/fail2ban/jail.local
else
    # Add under [DEFAULT] if not found at all
    sudo sed -i "/^\[DEFAULT\]/a findtime = $FAIL2BAN_FINDTIME" /etc/fail2ban/jail.local
fi

# Configure maxretry
if sudo grep -qE "^[#[:space:]]*maxretry[[:space:]]*=" /etc/fail2ban/jail.local; then
    sudo sed -i -E "s/^[#[:space:]]*maxretry[[:space:]]*=.*/maxretry = $FAIL2BAN_MAXRETRY/" /etc/fail2ban/jail.local
else
    # Add under [DEFAULT] if not found at all
    sudo sed -i "/^\[DEFAULT\]/a maxretry = $FAIL2BAN_MAXRETRY" /etc/fail2ban/jail.local
fi

echo "Successfully configured bantime, findtime, and maxretry in [DEFAULT] section."

# 5. Enable and start Fail2Ban service
echo "Enabling and starting Fail2Ban service..."
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban # Use restart to ensure new config is loaded

# 6. Check Fail2Ban service status
echo "Checking Fail2Ban service status..."
sudo systemctl status fail2ban --no-pager

# 7. Echo reminder information
echo ""
echo "--- Fail2Ban Post-Install Commands Reminder ---"
echo "Here are some common commands to manage and monitor Fail2Ban:"
echo ""
echo "  Goal: Is the service running?"
echo "  Command: sudo systemctl status fail2ban"
echo ""
echo "  Goal: Which jails are active?"
echo "  Command: sudo fail2ban-client status"
echo ""
echo "  Goal: Who is currently banned from SSH (assuming 'sshd' jail is active)?"
echo "  Command: sudo fail2ban-client status sshd"
echo ""
echo "  Goal: Watch live activity log:"
echo "  Command: sudo tail -f /var/log/fail2ban.log"

echo ""
echo "Fail2Ban installation and basic configuration complete."
echo "Ensure the [sshd] jail (or other desired jails) are enabled in /etc/fail2ban/jail.local or a .conf file in /etc/fail2ban/jail.d/."