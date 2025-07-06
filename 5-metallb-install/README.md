# Enabling MetalLB in MicroK8s

Step 1: Enable MetalLB in MicroK8s
First, enable the MetalLB addon. This provides the load-balancing capability for bare-metal clusters like MicroK8s.

Bash
```bash
microk8s enable metallb
```
After you run this, you'll be prompted to enter a range of IP addresses from your LAN that MetalLB can use. Make sure this IP range is outside of your router's DHCP pool to avoid IP address conflicts.

Step 2: Configure the MetalLB IP Address Pool
If you need to change the IP range later, you can create a configuration file.

Create a file named metallb-config.yaml:
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.240-192.168.1.250 # CHANGE THIS to a free IP range on your LAN
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
```
Apply the configuration:
```bash
microk8s.kubectl apply -f metallb-config.yaml
```
Alternatively, put this into the k8s directory for CI/CD pipeline integration. 