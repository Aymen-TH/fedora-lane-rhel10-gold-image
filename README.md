Absolutely — here is the **full updated README**, keeping your existing structure but making it more complete, professional, and aligned with the Fedora Lane assignment and what we have actually done so far.

````markdown
# Fedora Lane - RHEL 10 Gold Image

## Project Overview

This project provides a secure, standardized, and operationally resilient
RHEL 10 Gold Image for Fedora Lane's server fleet.

The objective is to establish a consistent operating system baseline that can
be deployed across cloud environments such as AWS and Azure.

The solution addresses Fedora Lane's challenges around:

- inconsistent server environments
- security patching and configuration drift
- untraceable administrative changes
- operational complexity
- container workload operations
- compliance and auditability

The Gold Image is manually built, configured, hardened, tested, and then
prepared for cloud deployment.

---

# Business Context

Fedora Lane operates a hybrid and multicloud environment containing
approximately 1,600 servers across on-premises infrastructure, AWS, Azure,
and other locations.

The existing environment contains multiple Linux distributions, including
Rocky Linux, Ubuntu, CentOS Stream, and Amazon Linux, with inconsistent
configurations between systems.

This creates problems with:

- configuration consistency
- security updates
- compliance
- troubleshooting
- operational efficiency
- configuration drift
- auditability
- container workload management

For example, critical security patches have failed to deploy to more than
600 servers, while manual patching requires significant operational effort
and can result in missed compliance deadlines.

The objective of this project is therefore to provide a standardized,
secure, and repeatable RHEL-based server foundation.

---

# 1. Solution

The solution is a manually built RHEL 10 Gold Image.

The Gold Image provides a standardized baseline including:

- standardized filesystem layout
- SELinux enforcing
- hardened SSH configuration
- custom SSH port
- controlled firewall rules
- standardized administrative access
- individual administrator accounts
- sudo access requiring authentication
- secured HTTP service
- custom HTTP port
- SELinux policy for custom service ports
- persistent configuration
- automatic service startup
- validation after reboot

The resulting system will then be captured as the Gold Image and used as the
basis for deploying standardized servers in AWS and/or Azure.

> The Gold Image is built manually rather than using the hosted Red Hat Image
> Builder service, as required by the exercise.

---

# 2. Architecture

The overall solution follows this flow:

```text
                    Fedora Lane Requirements
                              │
                              ▼
                 ┌─────────────────────────┐
                 │   Fedora Workstation    │
                 │       Host OS           │
                 └────────────┬────────────┘
                              │
                         KVM / libvirt
                              │
                              ▼
                 ┌─────────────────────────┐
                 │       RHEL 10 VM        │
                 │    Build Environment    │
                 └────────────┬────────────┘
                              │
                    Configure + Harden
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
          ▼                   ▼                   ▼
       Storage             Security            Services
          │                   │                   │
   /home /tmp          SELinux enforcing       httpd
   /var/log            SSH :2222              :35443
   /var/tmp            Firewall
                       Users / sudo
          │                   │                   │
          └───────────────────┼───────────────────┘
                              │
                              ▼
                 ┌─────────────────────────┐
                 │       GOLD IMAGE        │
                 │   Standard RHEL 10      │
                 └────────────┬────────────┘
                              │
                       Capture / Package
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
                   AWS                 Azure
                    │                   │
                    ▼                   ▼
              Standardized        Standardized
              RHEL servers        RHEL servers
````

The RHEL 10 VM is used as the build environment.

The system is manually configured and hardened inside the VM. After all
requirements have been implemented and validated, the configured RHEL system
is captured and prepared as the Gold Image.

The Gold Image can then be used to provision standardized servers.

---

# 3. Gold Image Requirements

## Operating System

* RHEL 10
* x86_64 architecture

## Storage

The following filesystems must be separate:

* `/var/log`
* `/home`
* `/tmp`
* `/var/tmp`

Each of these filesystems must be smaller than 5 GiB.

The root filesystem uses the remaining available disk space.

## Security

The Gold Image must provide:

* SELinux in enforcing mode
* `/tmp` mounted with `noexec`
* root SSH login disabled
* SSH password authentication disabled
* SSH listening on port `2222`
* HTTP service listening on port `35443`
* only required SSH and HTTP ports accessible through the firewall
* individual administrator accounts
* administrator group
* sudo access for administrators
* sudo must require the user's password
* no `NOPASSWD` configuration

## Web Server

The image must contain an HTTP service.

Requirements:

* `httpd`
* port `35443`
* SELinux configured for the custom HTTP port
* dummy `index.html`
* service enabled at boot
* service automatically starts after reboot

The preferred implementation is to run the HTTP workload in a container
where practical.

---

# 4. Implementation Plan

The implementation is divided into several phases.

```text
Phase 1   Build RHEL 10 environment
    ↓
Phase 2   Configure filesystem layout
    ↓
Phase 3   Configure SELinux
    ↓
Phase 4   Harden SSH
    ↓
Phase 5   Configure administrators and sudo
    ↓
Phase 6   Configure HTTP service
    ↓
Phase 7   Configure firewall
    ↓
Phase 8   Validate persistence and services
    ↓
Phase 9   Reboot and validate
    ↓
Phase 10  Capture Gold Image
    ↓
Phase 11  Deploy to AWS / Azure
    ↓
Phase 12  Cloud validation
```

---

# 5. Phase 1 - Build Environment

## 5.1 Download RHEL 10 Installation Media

The RHEL 10 x86_64 DVD ISO was downloaded from the Red Hat Customer Portal.

The ISO is used as the installation media for the RHEL 10 virtual machine.

It is important to distinguish between the installation ISO and the final
Gold Image:

```text
RHEL 10 DVD ISO
      │
      │ installation media
      ▼
RHEL 10 VM
      │
      │ configure + harden + test
      ▼
RHEL 10 Gold Image
      │
      ├── AWS
      └── Azure
```

The approximately 8 GB ISO is **not** the Gold Image that will be uploaded
to AWS or Azure.

---

## 5.2 Create the RHEL 10 Build VM

The RHEL 10 build environment was created on the Fedora workstation using
KVM/libvirt.

The VM is named:

```text
rhel10.0-GOLDEN
```

### VM Configuration

| Setting            | Value                  |
| ------------------ | ---------------------- |
| VM name            | `rhel10.0-GOLDEN`      |
| Host OS            | Fedora                 |
| Hypervisor         | KVM                    |
| Virtualization     | libvirt                |
| Guest OS           | RHEL 10                |
| Architecture       | x86_64                 |
| RAM                | 4 GiB                  |
| vCPUs              | 2                      |
| Virtual disk       | 40 GiB                 |
| Installation media | RHEL 10 x86_64 DVD ISO |
| Network            | libvirt default/NAT    |

The VM provides an isolated environment where the RHEL system can be built,
configured, hardened, and tested before being captured as the Gold Image.


---

## 5.3 RHEL Installation

RHEL 10 was installed normally inside the virtual machine.

During installation, the virtual disk was configured manually so that the
required filesystems are separated.

The installation disk is:

```text
/dev/vda
```

with a total size of approximately:

```text
40 GiB
```

The installation uses the **Custom** storage configuration.

### Required filesystem layout

```text
/
├── /home
├── /tmp
├── /var/log
└── /var/tmp
```

The required dedicated filesystems are kept below 5 GiB.

The remaining disk space is used for the root filesystem and the other
required system partitions.

---

# 6. Phase 2 - Filesystem Configuration

The Gold Image must have dedicated filesystems for:

```text
/home
/tmp
/var/log
/var/tmp
```

Each filesystem must remain below 5 GiB.

The purpose of this layout is to isolate important areas of the operating
system and reduce the impact of uncontrolled filesystem growth.

For example:

* `/var/log` is isolated so that excessive logs do not consume the root
  filesystem.
* `/home` is isolated from system files.
* `/tmp` is isolated for temporary files.
* `/var/tmp` is isolated for persistent temporary data.

The filesystem configuration will be verified after installation using
standard Linux storage and mount commands.

### Validation

The final configuration will be checked using:

```bash
lsblk
df -h
findmnt
```

The configuration must also remain correct after reboot.

---

# 7. Phase 3 - SELinux

SELinux is a core security requirement of the Gold Image.

The final system must have:

```text
SELinux = enforcing
```

SELinux will also be configured to allow the custom service ports:

```text
SSH  = 2222
HTTP = 35443
```

The appropriate SELinux port contexts will be configured rather than
disabling SELinux or using permissive mode.

### Validation

The final system will be checked with:

```bash
getenforce
```

Expected result:

```text
Enforcing
```

SELinux port configuration will also be verified.

---

# 8. Phase 4 - SSH Hardening

SSH is required for remote administration but must be hardened.

The SSH configuration will use:

```text
Port 2222
```

The following security requirements will be implemented:

* SSH uses port `2222`
* root SSH login is disabled
* SSH password authentication is disabled
* administrators authenticate using their individual accounts
* SELinux allows SSH on port `2222`
* the firewall allows SSH on port `2222`

The SSH service must also start automatically after reboot.

### Validation

The configuration will be checked before reboot and again after reboot.

Examples of validation include:

```bash
ss -lnt
systemctl status sshd
```

The final system must show SSH listening on:

```text
2222
```

---

# 9. Phase 5 - Administrative Access and sudo

Administrators must use individual accounts instead of sharing the root
account.

An administrative group will be created and administrator accounts will be
added to that group.

The administrators will receive sudo access to perform privileged
operations.

Sudo must require authentication.

The configuration must **not** contain:

```text
NOPASSWD
```

The goal is to provide:

```text
Individual user
      │
      ▼
Administrator group
      │
      ▼
sudo
      │
      ▼
root privileges
```

This provides individual accountability while still allowing administrators
to perform required system administration tasks.

---

# 10. Phase 6 - HTTP Service

````markdown
## Containerized HTTP Service

The HTTP workload is implemented using **Podman** rather than running the
`httpd` service directly on the RHEL host.

The architecture is:

```text
Client
   │
   │ TCP 35443
   ▼
RHEL 10 Host
   │
   │ Podman port mapping
   │ 35443 → 80
   ▼
httpd Container
   │
   │ Apache HTTP Server :80
   ▼
index.html
````

The host exposes port `35443`, while Apache listens on its standard HTTP port
`80` inside the container.

The containerized implementation provides:

* Apache HTTP Server running inside a Podman container
* Host port `35443` mapped to container port `80`
* Persistent web content stored outside the container
* SELinux-compatible container volume labeling
* Firewall access limited to the required HTTP port
* Automatic container startup after reboot

### Container Configuration

The HTTP workload was configured using Podman.

The implementation consists of the following steps:

1. Create a dedicated directory on the RHEL host for the HTTP content.
2. Create a basic `index.html` file in this directory.
3. Apply the appropriate SELinux container file context to the directory.
4. Create the `httpd` container from the official Apache HTTP image.
5. Mount the host content directory into the Apache document root.
6. Map host port `35443` to port `80` inside the container.
7. Verify that the container is running and that the HTTP page is accessible.
8. Verify that the firewall allows TCP port `35443`.

### Container Persistence

A manually started container would not be sufficient for the Gold Image because
the HTTP service must automatically return after a reboot.

Podman **Quadlet** was therefore used to integrate the container with
`systemd`.

The persistence configuration consists of the following steps:

1. Create a Podman Quadlet configuration for the HTTP container.
2. Define the container image, container name, port mapping, and persistent
   volume in the Quadlet configuration.
3. Configure the container to restart automatically .
4. Integrate the container with the system boot process through the generated
   `systemd` service.
5. Reboot the RHEL VM.
6. Verify that the container is automatically recreated/started.
7. Verify that the HTTP service is still accessible on port `35443`.

This ensures that the Gold Image does not depend on manually starting the
container after every reboot.

### Persistence Architecture

```text
                    RHEL 10 Gold Image
                           │
             ┌─────────────┴─────────────┐
             │                           │
      Quadlet configuration       Persistent content
             │                           │
             ▼                           ▼
        systemd service          /opt/fedora-lane/httpd locally mounted on /usr/local/apache2/htdocs 
             │                           │
             └─────────────┬─────────────┘
                           ▼
                    Podman container
                           │
                    httpd :80
                           │
                    Host :35443
```

The container itself is treated as a replaceable workload, while the web
content is maintained on the host through the persistent volume.

### Validation

The containerized HTTP service was validated by:

* verifying the Podman container is running
* verifying port `35443` is exposed
* verifying the test `index.html` is returned
* verifying SELinux remains enforcing
* verifying the firewall allows port `35443`
* rebooting the VM
* verifying the container automatically starts after reboot
* verifying the HTTP service remains accessible after reboot


## SELinux

Because `35443` is not the standard HTTP port, SELinux must be configured
to allow `httpd` to use this port.

SELinux will remain enforcing.


# 11. Phase 7 - Firewall

The firewall will be configured so that only the required application and
administration ports are accessible.

Required ports:

```text
SSH   → 2222
HTTP  → 35443
```

Other unnecessary inbound ports must remain closed.

The firewall configuration must be persistent.

### Validation

The final firewall configuration will be checked before and after reboot.

The objective is:

```text
Internet / Network
       │
       ├──── TCP 2222  → SSH
       │
       └──── TCP 35443 → HTTP
       
       Other inbound ports → blocked
```

---

# 12. Phase 8 - Persistence and Service Configuration

All required configuration must survive a reboot.

This includes:

* filesystem mounts
* `/tmp` `noexec`
* SELinux enforcing mode
* SELinux port configuration
* SSH port `2222`
* SSH hardening
* firewall rules
* administrator accounts
* sudo configuration
* HTTP port `35443`
* HTTP service configuration
* service enablement

Services that are required at boot will be enabled using systemd.

The system must not depend on manually starting services after every reboot.

---

# 13. Phase 9 - Validation

Before creating the Gold Image, the entire system will be validated throught a script that will validate :

## Storage

Verify:

```bash
lsblk
df -h
findmnt
```

Check that:

```text
/home
/tmp
/var/log
/var/tmp
```

are separate filesystems and each is below 5 GiB.

## SELinux

Verify:

```bash
getenforce
```

Expected:

```text
Enforcing
```

## SSH

Verify:

```text
Port = 2222
Root login = disabled
Password authentication = disabled
```

## HTTP

Verify:

```text
httpd
Port = 35443
index.html = available
```

## Firewall

Verify:

```text
2222  → allowed
35443 → allowed
Other unnecessary inbound ports → blocked
```

## Services

Verify required services are enabled and running.

## Reboot Test

The VM will then be rebooted.

After reboot, the same requirements will be checked again.

This is important because the Gold Image must represent a system that is
operationally resilient and does not require manual reconfiguration after
restarting.

---

# 14. Phase 10 - Gold Image Creation

Once the RHEL 10 VM has been fully configured and validated, the system
becomes the source for the Gold Image.

The process is:

RHEL 10 VM
    │
    │ configure
    │ harden
    │ test
    │ reboot
    │ validate
    ▼
Validated RHEL 10 system
    │
    │ capture / package
    ▼
RHEL 10 Gold Image


### QCOW2 → RAW conversion

The VM was originally stored as a **QCOW2** disk image, which is optimized for virtualization and supports features such as snapshots, compression, and thin provisioning :
<img width="865" height="343" alt="image" src="https://github.com/user-attachments/assets/36b4bed8-ad1b-4df9-9db3-8332b5d4e904" />

For cloud deployment, we converted the image to **RAW**, a simple sector-by-sector disk representation that is more widely supported by cloud image-import tools :

<img width="2086" height="775" alt="image" src="https://github.com/user-attachments/assets/16f0bd25-067f-4c87-9f78-fe28e4e73618" />


```text
QCOW2
  │
  │ qemu-img convert
  ▼
RAW
  │
  ▼
Cloud image import
```


* **QCOW2:** virtualization-friendly format used by KVM/QEMU.
* **RAW:** simple representation of the VM's virtual disk, without QCOW2-specific features.
* **Why convert?** The goal is to package the validated VM disk in a format suitable for the target cloud's image-import process.

**Important:** The RAW image still represents the same **40 GiB virtual disk**; conversion does not change the OS, partitions, or configuration.


```

The Gold Image should contain the complete validated operating system
baseline.

The installation ISO itself is not uploaded as the Gold Image.

A proper cloud-compatible image/capture process will be used for the target
cloud platform.


---

# 15. Phase 11 - Cloud Deployment

The Gold Image will be prepared for deployment to AWS and/or Azure.

The deployment process will include:

1. Create an S3 bucket to store the Gold Image.
<img width="1523" height="490" alt="image" src="https://github.com/user-attachments/assets/c0ce913f-14df-45e9-8c04-bd3c23be1de6" />

2. Upload the Gold Image to the S3 bucket.

3. Import the Gold Image into the target cloud.
<img width="798" height="132" alt="image" src="https://github.com/user-attachments/assets/a3971865-bb84-4226-b228-ce6a0f12ed6b" />

4. Create a VM from the image.
5. Start the VM.
6. Connect using the configured administrative access.
7. Verify the security configuration.
8. Verify the HTTP service.
9. Verify the firewall.
10. Reboot the cloud VM.
11. Verify that the configuration remains persistent.

---

# 16. AWS Deployment

The first cloud deployment target can be AWS.

The workflow is:

```text
RHEL 10 Gold Image
        │
        ▼
    AWS Image
        │
        ▼
   EC2 Instance
        │
        ▼
Validate configuration
```

The deployed system must retain the Gold Image baseline.

Validation will include:

* RHEL version
* filesystem layout
* SELinux
* SSH configuration
* administrator access
* firewall
* HTTP service
* persistence after reboot

---

# 17. Azure Deployment

Azure is the second possible deployment target.

If implemented, the workflow is:

```text
RHEL 10 Gold Image
        │
        ▼
   Azure Image
        │
        ▼
   Azure VM
        │
        ▼
Validate configuration
```

This is considered a stretch goal if AWS is completed first.

---

# 18. Optional Stretch Goals

## Stretch Goal 1 - Security Compliance

Evaluate the Gold Image using OpenSCAP and/or a relevant CIS security
profile.

The objective is to demonstrate that the standardized image can also be
assessed against a recognized security baseline.

Possible workflow:

```text
Gold Image
    │
    ▼
OpenSCAP / CIS assessment
    │
    ▼
Identify findings
    │
    ▼
Remediate applicable findings
    │
    ▼
Re-test
```

---

## Stretch Goal 2 - Multi-Cloud Images

Create validated deployment images for both:

```text
AWS
Azure
```

This demonstrates the portability of the standardized RHEL baseline across
the customer's multicloud environment.

---

# 19. GitHub Repository

The project source code and documentation will be maintained in GitHub.

The repository should contain:

```text
.
├── README.md
├── VerifyVM.sh (to verify need config)
├── scripts.md ( all commands to reproduce , from config to deployment)
```

The exact structure may evolve during implementation.

## Repository Requirements

The repository should:

* document the purpose of the project
* explain the implementation
* document important technical decisions
* provide setup and execution instructions
* document deployment requirements
* contain relevant configuration/scripts
* contain screenshots or other evidence where useful
* document challenges and solutions

The repository should remain private if possible.

The required Red Hat reviewer:

```text
mflaim-eng
```

should be added as appropriate.

---

# 20. Secrets and Credentials

No secrets should be committed to the repository.

This includes:

* passwords
* private SSH keys
* cloud credentials
* API tokens
* access keys
* certificates containing private keys
* other sensitive information

Any required credentials should be provided separately during deployment.

If available, `rh-pre-commit` should be used to help prevent accidental
secret commits.

---

# 21. Documentation and Evidence

Important implementation steps will be documented with screenshots and
configuration evidence.

Example:

```text
docs/
└── screenshots/
    ├── 01-rhel10-iso.png
    ├── 02-vm-configuration.png
    ├── 03-installation-destination.png
    ├── 04-filesystem-layout.png
    ├── 05-selinux.png
    ├── 06-ssh.png
    ├── 07-firewall.png
    ├── 08-httpd.png
    ├── 09-validation.png
    └── 10-cloud-deployment.png
```

Screenshots should demonstrate important technical decisions and successful
validation rather than documenting every individual command.

---

# 22. Presentation / Demonstration

The final solution will be demonstrated in a short presentation.

The presentation should focus on:

## Opening

Explain:

* Fedora Lane's environment
* the operational problems
* why standardization is required

## Live Walkthrough

Demonstrate:

* RHEL 10 Gold Image architecture
* filesystem layout
* SELinux enforcement
* SSH hardening
* administrator access
* firewall
* HTTP service
* persistence after reboot
* cloud deployment

The walkthrough should explain the important technical decisions rather
than showing every command used during implementation.

## Value

Explain how the solution helps Fedora Lane:

* standardize the server fleet
* reduce configuration drift
* simplify operations
* improve security
* improve auditability
* simplify troubleshooting
* provide a consistent foundation for cloud deployments

---

# 23. Validation Checklist

Before considering the Gold Image complete, verify:

## Operating System

* [ ] RHEL 10 installed
* [ ] x86_64 architecture
* [ ] Gold Image build environment documented

## Storage

* [ ] `/home` is a separate filesystem
* [ ] `/tmp` is a separate filesystem
* [ ] `/var/log` is a separate filesystem
* [ ] `/var/tmp` is a separate filesystem
* [ ] Each required filesystem is below 5 GiB
* [ ] Filesystems persist after reboot

## Security

* [ ] SELinux is enforcing
* [ ] `/tmp` uses `noexec`
* [ ] SELinux allows SSH on port `2222`
* [ ] SELinux allows HTTP on port `35443`
* [ ] Root SSH login is disabled
* [ ] SSH password authentication is disabled
* [ ] Individual administrator accounts exist
* [ ] Administrators belong to the correct group
* [ ] sudo access works
* [ ] sudo requires a password
* [ ] No `NOPASSWD` configuration exists

## SSH

* [ ] SSH listens on `2222`
* [ ] SSH starts automatically
* [ ] SSH works after reboot

## HTTP

* [ ] `httpd` is installed/configured
* [ ] HTTP listens on `35443`
* [ ] `index.html` exists
* [ ] HTTP starts automatically
* [ ] HTTP works after reboot

## Firewall

* [ ] TCP `2222` allowed
* [ ] TCP `35443` allowed
* [ ] Unnecessary inbound ports blocked
* [ ] Firewall configuration persists after reboot

## Gold Image

* [ ] Full system configuration validated
* [ ] System reboot tested
* [ ] Configuration survives reboot
* [ ] Gold Image captured
* [ ] Gold Image prepared for cloud deployment

## Cloud

* [ ] Gold Image deployed to AWS and/or Azure
* [ ] Cloud VM starts successfully
* [ ] SSH access validated
* [ ] HTTP access validated
* [ ] Security configuration validated
* [ ] Reboot persistence validated

## Optional

* [ ] OpenSCAP/CIS assessment
* [ ] AWS image
* [ ] Azure image

---

# 24. Current Project Status

### Phase 1 - Build Environment

* [x] RHEL 10 x86_64 ISO downloaded
* [x] KVM/libvirt environment prepared
* [x] RHEL 10 VM created
* [x] VM configured with 4 GiB RAM
* [x] VM configured with 2 vCPUs
* [x] 40 GiB virtual disk created
* [x] RHEL 10 installation started
* [x] Custom storage configuration selected

### Remaining

* [ ] Complete filesystem configuration
* [ ] Complete RHEL 10 installation
* [ ] Configure SELinux
* [ ] Configure `/tmp` with `noexec`
* [ ] Harden SSH
* [ ] Configure administrator accounts
* [ ] Configure sudo
* [ ] Configure HTTP service
* [ ] Configure SELinux service ports
* [ ] Configure firewall
* [ ] Enable required services
* [ ] Validate configuration
* [ ] Reboot and revalidate
* [ ] Capture Gold Image
* [ ] Deploy to AWS and/or Azure
* [ ] Perform cloud validation
* [ ] Complete documentation
* [ ] Prepare final presentation

---

# 25. Expected Final Result

The final result should be a validated RHEL 10 Gold Image that provides a
standardized and secure foundation for Fedora Lane's server fleet.

```text
                 Fedora Lane
                      │
                      ▼
              RHEL 10 Gold Image
                      │
       ┌──────────────┼──────────────┐
       │              │              │
       ▼              ▼              ▼
   Standard       Secure          Auditable
   Storage        Access          Operations
       │              │              │
       └──────────────┼──────────────┘
                      │
                      ▼
               Cloud Deployment
                 ┌────┴────┐
                 ▼         ▼
                AWS      Azure
```

The Gold Image provides a repeatable baseline that can help Fedora Lane
reduce configuration drift, simplify server operations, improve security,
and establish a consistent foundation for future cloud workloads.

