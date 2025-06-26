#!/bin/bash
# Switch to legacy iptables and ip6tables if they are available

# On modern Debian/Ubuntu systems, iptables can operate in two modes:
# 1. 'nft' (the new default): Rules are managed by the nftables kernel subsystem.
# 2. 'legacy': Rules are managed by the older, traditional iptables subsystem.
#
# MicroK8s's internal kube-proxy is compiled to write its rules to the 'legacy'
# tables. If the host OS is in 'nft' mode, a "split-brain" occurs: Kubernetes
# writes rules to one table, but the kernel only enforces the other, empty table.
#
# SYMPTOM: This leads to NodePort services being unreachable, even from the
#          host itself, with connections being refused. The `ss -ltnp` command
#          will not show the NodePort listening, even though the service and
#          application pods are healthy.
#
# SOLUTION: We must align the host's default iptables mode with what MicroK8s expects.
#           This command checks the current mode and switches it if necessary.

sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy