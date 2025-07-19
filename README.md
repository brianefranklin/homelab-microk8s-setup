# probablyfine-servers

This repository contains the setup scripts and configuration directions for standing up a home lab environment. The primary goal is to establish the foundation for a robust CI/CD pipeline using self-hosted services.

## Key Components

*   **Kubernetes (MicroK8s)**: The container orchestration platform.
*   **Harbor**: A self-hosted container registry for storing Docker images.
*   **GitHub Actions Runner Controller (ARC)**: For managing self-hosted GitHub Actions runners within the Kubernetes cluster.

The repository is structured with numbered directories that represent the sequential steps for setting up the environment, from initial Kubernetes setup to deploying applications via CI/CD.

The user applications directory is optional and contains an example of using this setup. 

