# homelab-microk8s-setup

This repository provides the Infrastructure as Code (IaC) and configuration scripts to bootstrap a complete home lab environment from scratch. The primary goal is to create a robust, self-hosted CI/CD platform, enabling you to build, test, and deploy your applications using your own infrastructure.

## Core Technologies

This setup is built upon a foundation of powerful, open-source tools:

*   **Kubernetes (MicroK8s)**: Serves as the backbone for container orchestration, managing application lifecycles and resources.
*   **Harbor**: A private, self-hosted container registry to securely store and manage your Docker images.
*   **GitHub Actions Runner Controller (ARC)**: Integrates with your Kubernetes cluster to dynamically scale self-hosted runners for your GitHub Actions workflows.

## Prerequisites

Before you begin, ensure you have the following:

*   A server or virtual machine to act as your Kubernetes node.
*   A fresh installation of a supported Linux distribution (e.g., Ubuntu 22.04 LTS).
*   Basic familiarity with the command line, Kubernetes concepts, and YAML.
*   A GitHub account and a Personal Access Token (PAT) with appropriate permissions for using the GitHub Actions Runner Controller.

## Repository Structure

The repository is organized into numbered directories, designed to be followed sequentially. Each directory represents a logical step in the setup process and contains its own set of instructions. 

```
probablyfine-servers/
├── 1-server-config
├── 2-container-orchestration
├── 3-registry-install
├── 4-ci-cd-configuration
└── 5-metallb-install
```

## Setup Guide

To build your home lab, navigate through the numbered directories in ascending order. Each directory contains its own `README.md` with detailed instructions for that specific step.

Start with the first step:

```bash
# 1. Begin with the Kubernetes setup
cd 01-setup-kubernetes/

# 2. Follow the instructions in its README.md
# 3. Once complete, proceed to the next directory (e.g., 02-setup-harbor/)
```
