# RHEL 10 Golden Image - Fedora Lane

## 1. Project Overview

This project provides a standardized and hardened **RHEL 10 Golden Image** for Fedora Lane.

The objective is to create a reusable RHEL 10 server image that can be deployed consistently in cloud environments while maintaining a predefined security, storage, networking, and service configuration.

The image is built locally, hardened and configured, converted into a cloud-compatible format, imported into AWS, and deployed as an EC2 instance.

---

## 2. Business Context

Fedora Lane operates a hybrid and cloud environment where servers need to be deployed consistently.

Without a standardized image, each server may require manual configuration, which can lead to:

* Configuration drift
* Security inconsistencies
* Longer deployment times
* Repeated manual configuration
* Difficult troubleshooting
* Inconsistent server environments

The Golden Image provides a standardized baseline that can be reused for future deployments.

---

## 3. Solution

The solution is based on a hardened RHEL 10 image containing:

* Standardized filesystem layout
* SELinux in enforcing mode
* Hardened SSH configuration
* SSH on port `2222`
* Disabled root SSH login
* Disabled SSH password authentication
* Individual administrator accounts
* Administrator group and sudo access
* `/tmp` mounted with `noexec`
* Firewalld configuration
* Containerized HTTP service
* HTTP service exposed on port `35443`
* Persistent systemd/Quadlet configuration
* Automatic startup verification

The image is then converted from QCOW2 to RAW and imported into AWS.

---

## 4. Architecture

The overall workflow is:

```text
                    Fedora Workstation
                           │
                           │ KVM / libvirt
                           ▼
                  ┌───────────────────┐
                  │    RHEL 10 VM     │
                  │                   │
                  │ Hardened baseline │
                  │ SELinux           │
                  │ SSH :2222         │
                  │ HTTP :35443       │
                  │ Firewall          │
                  │ Podman            │
                  └─────────┬─────────┘
                            │
                            │ QCOW2 → RAW
                            ▼
                     ┌──────────────┐
                     │   RAW Image  │
                     └──────┬───────┘
                            │
                            │ Upload
                            ▼
                    ┌────────────────┐
                    │   Amazon S3    │
                    └───────┬────────┘
                            │
                            │ Import
                            ▼
                     ┌──────────────┐
                     │   AWS AMI    │
                     └──────┬───────┘
                            │
                            │ Launch
                            ▼
                     ┌──────────────┐
                     │ EC2 Instance │
                     │              │
                     │ RHEL 10      │
                     │ SSH :2222    │
                     │ HTTP :35443  │
                     └──────┬───────┘
                            │
                     AWS Systems Manager
                       Session Manager
                            │
                            ▼
                     Administrative Access
```

---

## 5. Gold Image Requirements

### Operating System

The image is based on:

```text
RHEL 10
x86_64
```

The build VM uses:

| Setting        | Value   |
| -------------- | ------- |
| Host OS        | Fedora  |
| Hypervisor     | KVM     |
| Virtualization | libvirt |
| Guest OS       | RHEL 10 |
| Architecture   | x86_64  |
| RAM            | 4 GiB   |
| vCPUs          | 2       |
| Virtual Disk   | 40 GiB  |

---

## 6. Filesystem Layout

The following filesystems were configured separately during the RHEL installation using custom storage configuration:

```text
/home
/tmp
/var/log
/var/tmp
```

Each required filesystem is configured below 5 GiB.

The remaining disk space is allocated to the root filesystem.

`/tmp` is also configured with the `noexec` mount option.

This storage layout provides better separation between system data, user data, logs, and temporary files.

---

## 7. Security Configuration

### SELinux

SELinux remains enabled and enforcing.

The custom services require SELinux port labeling for:

```text
SSH   → 2222/tcp
HTTP  → 35443/tcp
```

This allows the services to operate on non-default ports while maintaining SELinux protection.

---

## 8. SSH Hardening

SSH is configured to listen on:

```text
2222/tcp
```

The following hardening settings are applied:

```text
PermitRootLogin no
PasswordAuthentication no
Port 2222
```

This means:

* Root cannot log in directly through SSH.
* Password-based SSH authentication is disabled.
* SSH uses the custom port `2222`.
* Authentication is performed using SSH keys.

---

## 9. Administrator Access

Individual administrator accounts are created instead of using the root account directly.

Administrators belong to a dedicated group:

```text
administrators
```

The group receives sudo access.

Sudo requires the administrator's password.

No `NOPASSWD` configuration is used.

---

## 10. Containerized HTTP Service

The image provides a simple HTTP service using Podman.

The workload runs inside an Apache HTTPD container.

The service is exposed through:

```text
35443 → 80
```

The container serves a simple page:

```text
Fedora Lane - httpd is working in a container!
```

The container is managed through **Podman Quadlet/systemd**, allowing it to start automatically when the system boots.

---

## 11. Firewall

Firewalld is configured to allow only the required application ports.

Required ports:

```text
2222/tcp   → SSH
35443/tcp  → HTTP
```

Other unnecessary inbound ports remain blocked.

---

## 12. Automatic Startup Verification

The Gold Image contains a verification script used to verify the expected configuration.

The verification script is configured to run automatically when the machine starts.

Its purpose is to verify that the important Gold Image requirements remain correctly configured after boot, including:

* Filesystem configuration
* SELinux
* SSH configuration
* Administrator access
* Firewall
* HTTP service
* Required services
* Persistence after reboot

This avoids relying on manual validation after every startup.

---

## 13. Gold Image Creation

Once the RHEL 10 VM has been configured and hardened, the VM becomes the source for the Golden Image.

The workflow is:

```text
RHEL 10 VM
    │
    │ Configure
    │ Harden
    │ Verify
    ▼
RHEL 10 Golden VM
    │
    │ Shutdown
    ▼
QCOW2 image
    │
    │ qemu-img convert
    ▼
RAW image
```

The original virtualization disk is stored as QCOW2.

For AWS deployment, the image is converted to RAW.

---

## 14. QCOW2 → RAW Conversion

The original RHEL disk was stored as:

```text
rhel10.06-GOLDEN.qcow2
```

The image was converted to:

```text
golden-aws.raw
```

The RAW image represents the complete RHEL disk and is used as the source for the AWS image import.

---

## 15. AWS Deployment

The RAW image is uploaded to an Amazon S3 bucket.

The deployment workflow is:

```text
RHEL 10 Golden VM
        │
        ▼
      QCOW2
        │
        ▼
       RAW
        │
        ▼
       S3
        │
        ▼
   AWS Import
        │
        ▼
       AMI
        │
        ▼
   EC2 Instance
```

The AWS deployment was performed in:

```text
Region:
us-east-2
```

The resulting AMI:

```text
ami-0aaf17a10931aa55d
```

The deployed EC2 instance:

```text
i-09460381bdb622f7d
```

---

## 16. AWS Systems Manager

AWS Systems Manager Session Manager is used as the initial administrative access mechanism.

The EC2 instance is associated with:

```text
Golden-EC2-SSM-Role
```

The role uses:

```text
AmazonSSMManagedInstanceCore
```

The corresponding instance profile is:

```text
Golden-EC2-SSM-Profile
```

This allows the instance to register with Systems Manager and provides shell access without requiring SSH to be available during the initial bootstrap phase.

---

## 17. SSH Key Management

User-specific SSH private keys are **not baked into the Golden Image**.

Instead, the SSH key is generated manually on the administrator's workstation.

The public key is then injected into the deployed EC2 instance through AWS Systems Manager.

The workflow is:

```text
Administrator PC
      │
      │ ssh-keygen
      ▼
Private key + Public key
      │
      │ SSM SendCommand
      ▼
EC2 instance
      │
      │ authorized_keys
      ▼
SSH :2222
```

The private key remains on the administrator's workstation.

This keeps user-specific credentials outside the Golden Image.

---

## 18. SSH Access

After the public key has been injected into the appropriate administrator account, SSH access is performed through port `2222`.

Example:

```bash
ssh -i ~/.ssh/golden-aws -p 2222 golden@<EC2_PUBLIC_IP>
```

The AWS Security Group and the RHEL firewall both allow:

```text
TCP 2222
```

---

## 19. Repository Structure

The repository contains the main documentation and the command reproduction guide.

```text
.
├── README.md
└── COMMANDS.md
```

`README.md` explains the architecture, implementation, design decisions, and final solution.

`COMMANDS.md` contains the commands required to reproduce the configuration and AWS deployment.

---

## 20. Secrets and Credentials

No secrets should be committed to the repository.

This includes:

* Private SSH keys
* Passwords
* AWS access keys
* API tokens
* Cloud credentials
* Certificates containing private keys
* Other sensitive information

The private SSH key remains on the administrator's workstation and is never included in the Golden Image or GitHub repository.

---

## 21. Documentation and Evidence

Important implementation steps can be documented with screenshots.

Example:

```text
docs/
└── screenshots/
    ├── 01-rhel10-iso.png
    ├── 02-vm-configuration.png
    ├── 03-filesystem-layout.png
    ├── 04-selinux.png
    ├── 05-ssh.png
    ├── 06-firewall.png
    ├── 07-httpd.png
    ├── 08-aws-import.png
    ├── 09-ec2.png
    └── 10-ssm.png
```

Screenshots should focus on important technical decisions and the final working architecture.

---

## 22. Presentation / Demonstration

The final demonstration focuses on:

### RHEL 10 Golden Image

* Filesystem architecture
* SELinux enforcement
* SSH hardening
* Administrator access
* Firewall
* Containerized HTTP service
* Automatic startup verification
* Persistence after reboot

### AWS Deployment

* RAW image creation
* S3 upload
* AMI import
* EC2 deployment
* Systems Manager integration
* SSH key injection
* SSH access on port `2222`
* HTTP service on port `35443`

---

## 23. Project Value

The Golden Image provides Fedora Lane with a consistent and reusable RHEL foundation.

The solution helps:

* Standardize the server fleet
* Reduce configuration drift
* Improve security
* Reduce manual configuration
* Simplify operations
* Improve auditability
* Simplify troubleshooting
* Provide a consistent foundation for cloud deployments

---

## 24. Final Architecture

The final solution can be summarized as:

```text
                     RHEL 10 Golden Image
                              │
                 ┌────────────┴────────────┐
                 │                         │
            Security                 Application
                 │                         │
        SELinux Enforcing            Podman HTTPD
        SSH :2222                    HTTP :35443
        Firewall                     Quadlet
        Admin + sudo
        /tmp noexec
                 │                         │
                 └────────────┬────────────┘
                              │
                         QCOW2 → RAW
                              │
                              ▼
                         Amazon S3
                              │
                              ▼
                           AWS AMI
                              │
                              ▼
                         EC2 Instance
                              │
                    ┌─────────┴─────────┐
                    │                   │
                  SSM                  SSH
              Management            Port 2222
                    │                   │
                    └─────────┬─────────┘
                              │
                       RHEL 10 Server
```

The result is a reusable, hardened RHEL 10 Golden Image that can be deployed consistently into AWS while keeping user-specific credentials outside the image.
