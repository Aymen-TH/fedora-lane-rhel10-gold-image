# RHEL 10 Golden Image — Reproduction Runbook

This document describes the complete workflow used to build the RHEL 10 golden image, prepare it for AWS, import it, create an EC2 instance, and configure remote administration.

The workflow is intentionally ordered chronologically:

1. Configure the RHEL machine
2. Configure SSH hardening
3. Configure firewall
4. Configure Podman and the HTTPD container
5. Configure Quadlet for automatic container startup
6. Configure the startup verification
7. Shut down and export the VM
8. Convert QCOW2 to RAW
9. Upload the RAW image to S3
10. Create the AWS VM Import/Export role
11. Import the RAW image into AWS
12. Obtain the generated AMI
13. Launch an EC2 instance
14. Attach the SSM IAM role/profile
15. Connect through SSM Session Manager
16. Inject an SSH public key and connect through SSH on port 2222

---

# 1. RHEL 10 Golden VM

The starting point is a RHEL 10 virtual machine running locally with KVM/QEMU.

The machine was installed using custom storage.

The following filesystems were created during installation:

```text
/tmp
/home
/var/log
/var/tmp
````

These are therefore **not created later with commands**. They are part of the initial RHEL storage layout.

Check the storage configuration:

```bash
lsblk -f
```

```bash
df -hT
```

Check persistent mounts:

```bash
cat /etc/fstab
```

---

# 2. Update RHEL

Update the system before configuring the golden image:

```bash
sudo dnf update -y
```

---

# 3. Install Required Packages

Install the packages required for the final image:

```bash
sudo dnf install -y \
  podman \
  firewalld \
  policycoreutils-python-utils \
  qemu-guest-agent \
  cloud-init \
  amazon-ssm-agent
```

---

# 4. Enable Required Services

Enable the services required by the image:

```bash
sudo systemctl enable --now firewalld
```

```bash
sudo systemctl enable --now qemu-guest-agent
```

```bash
sudo systemctl enable --now amazon-ssm-agent
```

---

# 5. SELinux

The golden image keeps SELinux enabled and enforcing.

Check:

```bash
getenforce
```

Expected:

```text
Enforcing
```

Detailed status:

```bash
sestatus
```

If the SELinux configuration needs to be explicitly configured:

```bash
sudo vi /etc/selinux/config
```

Set:

```text
SELINUX=enforcing
```

---

# 6. Configure SSH

The golden image uses SSH on port `2222` instead of the default port `22`.

Edit:

```bash
sudo vi /etc/ssh/sshd_config
```

The important settings are:

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

### Why?

* `Port 2222` — SSH is moved away from the default port.
* `PermitRootLogin no` — root cannot log in directly through SSH.
* `PasswordAuthentication no` — password-based SSH authentication is disabled.
* `PubkeyAuthentication yes` — SSH keys are used instead.

Validate the configuration:

```bash
sudo sshd -t
```

Restart SSH:

```bash
sudo systemctl restart sshd
```

Enable SSH at boot:

```bash
sudo systemctl enable sshd
```

Check the listening port:

```bash
sudo ss -lntp | grep ssh
```

Expected:

```text
0.0.0.0:2222
[::]:2222
```

---

# 7. Configure the Administrator User

Create the administrator account:

```bash
sudo useradd -m golden
```

Add it to the administrators group:

```bash
sudo usermod -aG wheel golden
```

Verify:

```bash
id golden
```

The user is intended to authenticate using an SSH public key rather than an SSH password.

---

# 8. Configure the RHEL Firewall

The RHEL firewall must allow the services that are intentionally exposed.

Allow SSH:

```bash
sudo firewall-cmd --permanent --add-port=2222/tcp
```

Allow the HTTPD service:

```bash
sudo firewall-cmd --permanent --add-port=35443/tcp
```

Apply the configuration:

```bash
sudo firewall-cmd --reload
```

Check:

```bash
sudo firewall-cmd --list-ports
```

Expected:

```text
2222/tcp 35443/tcp
```

---

# 9. Configure Podman

The HTTP service is not installed directly as a host `httpd` service.

Instead, it runs inside a Podman container.

Pull the HTTPD container image:

```bash
podman pull registry.access.redhat.com/ubi10/httpd-24
```

---

# 10. Create the HTTPD Web Directory

Create the directory that will contain the web content:

```bash
sudo mkdir -p /opt/fedora-lane/httpd/

```

Create the test page:

```bash
sudo vi /opt/fedora-lane/httpd/index.html

```

Content:

```html
Fedora Lane - httpd is working in a container!
```

---

# 11. Configure SELinux for the Container Content

Because the directory is mounted into a container, configure the appropriate SELinux context.

Create the persistent SELinux rule:

```bash
sudo semanage fcontext -a -t container_file_t "/opt/httpd(/.*)?"
```

Apply the context:

```bash
sudo restorecon -Rv /opt/httpd
```

---

# 12. Create the HTTPD Container

The container exposes port `8080` internally.

The host exposes it on port `35443`.

Run:

```bash
podman run -d \
  --name httpd \
  -p 35443:8080 \
  -v /opt/httpd/html:/var/www/html:Z \
  registry.access.redhat.com/ubi10/httpd-24
```

Check the container:

```bash
podman ps
```

Test locally:

```bash
curl http://localhost:35443
```

Expected:

```text
Fedora Lane - httpd is working in a container!
```

---

# 13. Configure Podman Quadlet

The container must automatically start when the machine starts.

Instead of manually running `podman run` after every reboot, use **Quadlet**.

Quadlet allows Podman containers to be described as systemd-managed units.

Create the user Quadlet directory:

```bash
mkdir -p /etc/containers/systemd/
```

Create the container definition:

```bash
vi /etc/containers/systemd/fedora-lane-httpd.container

```

The file contains:

```ini
[Unit]
Description=Fedora Lane HTTPD Container
After=network-online.target
Wants=network-online.target

[Container]
Image=docker.io/library/httpd:2.4
ContainerName=fedora-lane-httpd
PublishPort=35443:80
Volume=/opt/fedora-lane/httpd:/usr/local/apache2/htdocs:Z

[Service]
Restart=always

[Install]
WantedBy=multi-user.target

```

---

# 14. What the Quadlet File Does

The file:

```text
/etc/containers/systemd/fedora-lane-httpd.container
```

describes how the HTTPD container should be managed.

### `[Unit]`

```ini
[Unit]
Description=Containerized HTTPD
```

Provides a description for the service.

### `[Container]`

```ini
[Container]
Image=docker.io/library/httpd:2.4
ContainerName=fedora-lane-httpd
PublishPort=35443:80
Volume=/opt/fedora-lane/httpd:/usr/local/apache2/htdocs:Z

```

Defines:

* Which container image to use.
* The port mapping.
* The directory mounted into the container.
* The `:Z` option for SELinux container labeling.

### `[Service]`

```ini
[Service]
Restart=always
```

Tells systemd to restart the container if it stops.

### `[Install]`

```ini
[Install]
WantedBy=multi-user.target
```

Makes the container part of the user's default systemd startup environment.

---

# 15. Enable the Quadlet Service

Reload the user's systemd configuration:

```bash
systemctl --user daemon-reload
```

Enable and start the generated service:

```bash
systemctl --user enable --now httpd.service
```

Check:

```bash
systemctl --user status httpd.service
```

Check the container:

```bash
podman ps
```

---

# 16. Configure the Container to Start Automatically

The important concept is:

```text
System boot
    ↓
systemd
    ↓
Quadlet
    ↓
httpd.service
    ↓
Podman container
    ↓
HTTPD
```

Therefore, the golden image does not require someone to manually run:

```bash
podman run ...
```

after every reboot.

The Quadlet definition is stored inside the golden image and is used to recreate/start the container automatically.

---

# 17. Startup Verification

A verification script is included in the golden image.

It runs automatically during startup and verifies the required configuration and services.

The script is stored on the RHEL machine and is associated with a systemd startup service.

List the available administrative scripts:

```bash
sudo ls -l /usr/local/sbin/
```

Check the verification service:

```bash
systemctl list-unit-files | grep -i verify
```

Check its status:

```bash
sudo systemctl status <verification-service>
```

The purpose of this script is to verify the final golden-image configuration automatically after startup.

---

# 18. Prepare the Golden VM for Export

Once the RHEL machine is completely configured, shut it down cleanly:

```bash
sudo shutdown -h now
```

The VM is now ready to be converted into an AWS-compatible image.

---

# 19. Locate the QCOW2 Image

On the Fedora/KVM host:

```bash
ls -lh /home/athabet/VirtualMachines/rhel10.06-GOLDEN.qcow2
```

Check its metadata:

```bash
qemu-img info \
  /home/athabet/VirtualMachines/rhel10.06-GOLDEN.qcow2
```

---

# 20. Convert QCOW2 to RAW

AWS VM Import/Export will use the RAW disk image.

Convert:

```bash
qemu-img convert -p \
  -f qcow2 \
  -O raw \
  /home/athabet/VirtualMachines/rhel10.06-GOLDEN.qcow2 \
  /home/athabet/VirtualMachines/golden-aws.raw
```

Check the resulting image:

```bash
qemu-img info \
  /home/athabet/VirtualMachines/golden-aws.raw
```

Check its size:

```bash
ls -lh /home/athabet/VirtualMachines/golden-aws.raw
```

The RAW image represents the complete golden VM disk.

---

# 21. Create the S3 Bucket

The RAW image must be stored in Amazon S3 before AWS can import it.

Bucket used:

```text
fedora-lane-rhel10-golden-2026-461684759506
```

If creating a new bucket:

```bash
aws s3 mb \
  s3://fedora-lane-rhel10-golden-2026-461684759506 \
  --region us-east-2
```

---

# 22. Upload the RAW Image to S3

Upload:

```bash
aws s3 cp \
  /home/athabet/VirtualMachines/golden-aws.raw \
  s3://fedora-lane-rhel10-golden-2026-461684759506/images/golden-aws.raw \
  --region us-east-2
```

Verify:

```bash
aws s3 ls \
  s3://fedora-lane-rhel10-golden-2026-461684759506/images/ \
  --region us-east-2
```

The final S3 object is:

```text
s3://fedora-lane-rhel10-golden-2026-461684759506/images/golden-aws.raw
```

---

# 23. AWS VM Import/Export Role

AWS VM Import/Export needs permission to access the S3 image and perform the import operation.

The role used for this purpose is:

```text
vmimport
```

The role is associated with the AWS VM Import/Export service.

---

# 24. Create the vmimport Trust Policy

Create:

```bash
vi trust-policy.json
```

Content:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "vmie.amazonaws.com"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "vmimport"
        }
      }
    }
  ]
}
```

Create the role:

```bash
aws iam create-role \
  --role-name vmimport \
  --assume-role-policy-document file://trust-policy.json
```

---

# 25. Create the vmimport Permissions Policy

Create:

```bash
vi role-policy.json
```

Example policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::fedora-lane-rhel10-golden-2026-461684759506",
        "arn:aws:s3:::fedora-lane-rhel10-golden-2026-461684759506/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:ModifySnapshotAttribute",
        "ec2:CopySnapshot",
        "ec2:RegisterImage",
        "ec2:Describe*"
      ],
      "Resource": "*"
    }
  ]
}
```

Attach it:

```bash
aws iam put-role-policy \
  --role-name vmimport \
  --policy-name vmimport-policy \
  --policy-document file://role-policy.json
```

Verify:

```bash
aws iam get-role \
  --role-name vmimport
```

---

# 26. Import the RAW Image into AWS

Start the import:

```bash
aws ec2 import-image \
  --description "Fedora Lane RHEL 10 Golden Image" \
  --disk-containers \
  "Format=raw,UserBucket={S3Bucket=fedora-lane-rhel10-golden-2026-461684759506,S3Key=images/golden-aws.raw}" \
  --region us-east-2
```

The import is asynchronous.

The lifecycle is approximately:

```text
pending
   ↓
converting
   ↓
completed
```

Check the import:

```bash
aws ec2 describe-import-image-tasks \
  --region us-east-2
```

When the import completes, AWS generates an AMI.

---

# 27. Identify the Generated AMI

The generated AMI from the import was:

```text
ami-0aaf17a10931aa55d
```

Check:

```bash
aws ec2 describe-images \
  --image-ids ami-0aaf17a10931aa55d \
  --region us-east-2
```

The AMI now represents the RHEL golden image and can be used to launch EC2 instances.

---

# 28. Create the EC2 Instance

The AMI can now be used as the source image for an EC2 instance.

Current configuration:

```text
AMI:          ami-0aaf17a10931aa55d
Instance:     t3.micro
Region:       us-east-2
VPC:          Golden-VPC
Subnet:       GOLDEN-Subnet
```

Launch:

```bash
aws ec2 run-instances \
  --image-id ami-0aaf17a10931aa55d \
  --instance-type t3.micro \
  --security-group-ids sg-0091b79f555f4dd9a \
  --subnet-id subnet-057532d45ccde429c \
  --region us-east-2
```

The resulting instance was:

```text
i-09460381bdb622f7d
```

---

# 29. Configure the EC2 SSM IAM Role

The EC2 instance needs an IAM role so that AWS Systems Manager can manage it.

Create the trust policy:

```bash
vi ec2-ssm-trust-policy.json
```

Content:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Create the role:

```bash
aws iam create-role \
  --role-name Golden-EC2-SSM-Role \
  --assume-role-policy-document file://ec2-ssm-trust-policy.json
```

---

# 30. Attach the SSM Policy

Attach the AWS-managed policy:

```bash
aws iam attach-role-policy \
  --role-name Golden-EC2-SSM-Role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

This gives the EC2 instance the permissions required by Systems Manager.

---

# 31. Create the EC2 Instance Profile

Create:

```bash
aws iam create-instance-profile \
  --instance-profile-name Golden-EC2-SSM-Profile
```

Add the role:

```bash
aws iam add-role-to-instance-profile \
  --instance-profile-name Golden-EC2-SSM-Profile \
  --role-name Golden-EC2-SSM-Role
```

The relationship is:

```text
EC2
 │
 └── Instance Profile
       │
       └── Golden-EC2-SSM-Role
             │
             └── AmazonSSMManagedInstanceCore
```

---

# 32. Attach the SSM Instance Profile to EC2

Attach it to the instance:

```bash
aws ec2 associate-iam-instance-profile \
  --instance-id i-09460381bdb622f7d \
  --iam-instance-profile Name=Golden-EC2-SSM-Profile \
  --region us-east-2
```

The EC2 instance can now obtain temporary AWS credentials through its instance profile.

---

# 33. Reboot the EC2 Instance

Reboot so the services and IAM configuration are fully initialized:

```bash
aws ec2 reboot-instances \
  --instance-ids i-09460381bdb622f7d \
  --region us-east-2
```

---

# 34. Verify Systems Manager

Check the managed instances:

```bash
aws ssm describe-instance-information \
  --region us-east-2
```

The EC2 instance should appear as:

```text
InstanceId: i-09460381bdb622f7d
PingStatus: Online
PlatformName: Red Hat Enterprise Linux
```

---

# 35. Install Session Manager Plugin on the Fedora PC

The AWS CLI alone does not provide the interactive Session Manager terminal.

Install the Session Manager plugin:

```bash
sudo dnf install -y \
  https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm
```

Verify:

```bash
session-manager-plugin --version
```

---

# 36. Connect to EC2 Through SSM

Start an interactive Session Manager session:

```bash
aws ssm start-session \
  --target i-09460381bdb622f7d \
  --region us-east-2
```

This provides shell access to the EC2 instance without requiring SSH port `22`.

The resulting shell looks like:

```text
sh-5.2$
```

---

# 37. Generate the SSH Keypair on the PC

SSH access uses a keypair generated on the administrator PC.

Generate:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/GOLDEN-keypair
```

This creates:

```text
~/.ssh/GOLDEN-keypair
~/.ssh/GOLDEN-keypair.pub
```

The private key:

```text
GOLDEN-keypair
```

stays on the PC.

The public key:

```text
GOLDEN-keypair.pub
```

is injected into the EC2 instance.

---

# 38. Inject the Public Key Through SSM

Start an SSM session:

```bash
aws ssm start-session \
  --target i-09460381bdb622f7d \
  --region us-east-2
```

Create the SSH directory:

```bash
sudo mkdir -p /home/golden/.ssh
```

Set ownership:

```bash
sudo chown golden:golden /home/golden/.ssh
```

Set permissions:

```bash
sudo chmod 700 /home/golden/.ssh
```

Open the authorized keys file:

```bash
sudo vi /home/golden/.ssh/authorized_keys
```

From the PC, the public key is obtained with:

```bash
cat ~/.ssh/GOLDEN-keypair.pub
```

Copy that public key into:

```text
/home/golden/.ssh/authorized_keys
```

Set the correct permissions:

```bash
sudo chown golden:golden /home/golden/.ssh/authorized_keys
```

```bash
sudo chmod 600 /home/golden/.ssh/authorized_keys
```

Restore SELinux labels:

```bash
sudo restorecon -Rv /home/golden/.ssh
```

---

# 39. SSH Into the EC2 Instance

The SSH server listens on port `2222`.

Connect from the PC:

```bash
ssh \
  -i /path_to/GOLDEN-keypair \
  -p 2222 \
  golden@<EC2_PUBLIC_IP>
```

Example:

```bash
ssh -i /root/GOLDEN-keypair.pem \
    -p 2222 golden@3.21.233.179
```

---

# 40. Final Architecture

The complete workflow is:

```text
                 LOCAL MACHINE
                      │
                      ▼
              RHEL 10 Golden VM
                      │
        ┌─────────────┼──────────────┐
        │             │              │
       SSH         Firewall       Podman
     :2222         2222/35443        │
        │                            │
        │                         Quadlet
        │                            │
        │                         HTTPD
        │                            │
        └─────────────┬──────────────┘
                      │
                      ▼
                   QCOW2
                      │
                qemu-img convert
                      │
                      ▼
                    RAW
                      │
                      ▼
                    S3
                      │
                      ▼
             AWS VM Import/Export
                      │
                  vmimport
                      │
                      ▼
                    AMI
                      │
                      ▼
                  EC2 Instance
                      │
            ┌─────────┴─────────┐
            │                   │
            ▼                   ▼
          SSM                  SSH
     Session Manager           :2222
            │                   │
            └─────────┬─────────┘
                      ▼
                 RHEL 10 EC2
                      │
                      ▼
              Podman + HTTPD
                    :35443
```

---

# 41. Final AWS Resources

```text
Region:
us-east-2

S3 bucket:
fedora-lane-rhel10-golden-2026-461684759506

S3 object:
images/golden-aws.raw

VM Import role:
vmimport

AMI:
ami-0aaf17a10931aa55d

EC2 instance:
i-09460381bdb622f7d

Instance type:
t3.micro

EC2 SSM role:
Golden-EC2-SSM-Role

EC2 instance profile:
Golden-EC2-SSM-Profile
```

---

# 42. Final Ports

```text
2222/tcp   SSH
35443/tcp  Containerized HTTPD
```

Port `22` is not used for SSH.

The HTTP service is available through:

```text
http://<EC2_PUBLIC_IP>:35443
```

The administrator can access the machine through either:

```text
AWS Systems Manager Session Manager
```

or:

```text
SSH → port 2222 → golden user → SSH public key
```

Got it. Continuing exactly from **#42**, with the verification script as the next step:

# 43. Final Verification

On the EC2 machine, run:

```bash
./verify2.sh
```

The script will verify and display the configuration we have set up, including the relevant **SSH, ports, Podman/HTTPD, and system configuration**.

Use its output as the **final validation of the golden image/EC2 configuration**.

Verify the httpd container : 
open a web browser and search : 3.135.65.14:35443

<img width="402" height="175" alt="image" src="https://github.com/user-attachments/assets/1ecfe6d0-6d60-41ba-aac4-2d2b92c92b07" />



or curl it from a cli :


<img width="522" height="76" alt="image" src="https://github.com/user-attachments/assets/6654d408-a2e9-443b-99e3-19433e446722" />






```
```
