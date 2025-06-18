Configuring Hardened DNS Policy

Important Prerequisite: Backup Access
Before you begin, ensure you have a way to access your server if a networking mistake locks you out of SSH. 

Step 1: Prepare `10-custom-dns.conf`
Ensure your `10-custom-dns.conf` file is ready. This guide assumes it uses `DNSSEC=allow-downgrade`.

Note: By leaving the `DNS=` setting empty in `10-custom-dns.conf` (as shown in the template), your server will use DNS servers provided by your local network (e.g., from your gateway via DHCP). This configuration enables Split DNS. A key benefit is that internal services can obtain Let's Encrypt certificates using DNS-01 challenges without needing to be publicly accessible, though you can still choose to expose them to the internet if required.


Step 2: Upload and Deploy `10-custom-dns.conf`
1.  Upload the file to your server (e.g., to the user's home directory):
    ```bash
    scp /path/to/your/local/10-custom-dns.conf adminuser@<your_server_ip_or_hostname>:~
    ```
2.  SSH into your server:
    ```bash
ssh adminuser@<your_server_ip_or_hostname>
    ```
3.  Create the destination directory, move the file, and set permissions:
    ```bash
sudo mkdir -p /etc/systemd/resolved.conf.d/
sudo mv ~/10-custom-dns.conf /etc/systemd/resolved.conf.d/
sudo chown root:root /etc/systemd/resolved.conf.d/10-custom-dns.conf
sudo chmod 644 /etc/systemd/resolved.conf.d/10-custom-dns.conf
    ```

Step 3: Apply and Verify Configuration
1.  Restart `systemd-resolved`:
    ```bash
sudo systemctl restart systemd-resolved
    ```
2.  Verify the settings:
    ```bash
resolvectl status
    ```
    Verify the output. Since `DNS=` is empty in your `10-custom-dns.conf`, the "Current DNS Server(s)" should list servers provided by your network (DHCP).
    Your `FallbackDNS` servers from the file should also be listed.
    Additionally, confirm `DNSSEC=allow-downgrade`, `DNSOverTLS=opportunistic`, and `DNS Domain=~.`.
3.  Test DNS resolution (install `dnsutils` if `dig` is not present):
    ```bash
dig google.com
dig sigfail.verteiltesysteme.net
    ```
    With `DNSSEC=allow-downgrade`, `sigfail.verteiltesysteme.net` should resolve but lack the `ad` flag. If you used `DNSSEC=yes`, it should return `SERVFAIL`.

