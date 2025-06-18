sudo apt install unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades

# Create a timestamped backup in the user's home directory
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BACKUP_FILE=~/50unattended-upgrades.bak.$TIMESTAMP
CONFIG_FILE="/etc/apt/apt.conf.d/50unattended-upgrades"

echo "Backing up current config to $BACKUP_FILE..."
sudo cp "$CONFIG_FILE" "$BACKUP_FILE"
sudo chown $(whoami):$(whoami) "$BACKUP_FILE"

echo "Applying new production configuration line by line..."

# Enable removal of unused dependencies
sudo sed -i -E 's/^(.*Unattended-Upgrade::Remove-Unused-Dependencies).*/Unattended-Upgrade::Remove-Unused-Dependencies "true";/' "$CONFIG_FILE"

# Enable automatic reboot and set the time to 4 AM
sudo sed -i -E 's/^(.*Unattended-Upgrade::Automatic-Reboot) .*/Unattended-Upgrade::Automatic-Reboot "true";/' "$CONFIG_FILE"
sudo sed -i -E 's/^(.*Unattended-Upgrade::Automatic-Reboot-WithUsers) .*/Unattended-Upgrade::Automatic-Reboot-WithUsers "true";/' "$CONFIG_FILE"
sudo sed -i -E 's/^(.*Unattended-Upgrade::Automatic-Reboot-Time) .*/Unattended-Upgrade::Automatic-Reboot-Time "05:00";/' "$CONFIG_FILE"

# Set the download speed limit to 50000 kb/sec
sudo sed -i -E 's/^(.*Acquire::http::Dl-Limit) .*/Acquire::http::Dl-Limit "50000";/' "$CONFIG_FILE"

echo "Configuration updated successfully."

echo "Please review the changes made to the configuration file:"
diff "$BACKUP_FILE" "$CONFIG_FILE"

echo "Testing the unattended-upgrades configuration with dry run:"
# Note that this command also applies the configuration changes
sudo unattended-upgrades --dry-run