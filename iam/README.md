# Permissions

`provisioner-policy.json` is the least-privilege policy for the **laptop identity** that runs `devbox` (an SSO permission set, IAM user, or role). Attach it or ask your admin to. `devbox check` probes the important parts with EC2 dry runs and tells you what's missing.

## Assumptions baked into the policy

- **`DEVBOX_NAME` starts with `devbox-`** (e.g. `devbox-jdoe`). IAM is scoped to `role/devbox-*` and `instance-profile/devbox-*`, and key-pair deletion to `key-pair/devbox-*`.
- **Every devbox resource carries `purpose=devbox`** (`devbox provision` tags it). Start, stop, terminate, delete and attach are allowed only on resources with that tag. In an account shared with other workloads, the policy can't touch anything else.
- The box's own role gets only **`AmazonSSMManagedInstanceCore`**. The box has no AWS permissions of its own beyond talking to SSM; you log in on the box with your own identity (`devbox login`).

## When your org blocks parts of it

| Blocked | What to do |
|---|---|
| IAM role creation (SCP or permission boundary) | Ask an admin for an instance profile whose role has `AmazonSSMManagedInstanceCore`, and set `INSTANCE_PROFILE=<its name>`. Drop the `InstanceRoleForTheBox` statement except `iam:PassRole` on that role. |
| The DLM default role can't be created | Ask an admin to run `aws dlm create-default-role --resource-type snapshot` once per account, or set `SNAPSHOTS=off`. |
| Tag policies require tags | Put them in `EXTRA_TAGS="CostCenter=eng Team=platform"`. |
| A required KMS key for EBS | Set `EBS_KMS_KEY`, and grant `kms:CreateGrant`, `kms:Decrypt`, `kms:DescribeKey` and `kms:GenerateDataKeyWithoutPlaintext` on that key. |
| No default VPC | Set `SUBNET_ID` to a subnet with internet egress (public IP + IGW, or NAT). The box needs outbound HTTPS for SSM, apt, GitHub and Claude. |
| Session Manager restricted to VPC endpoints | Make sure the subnet can reach `ssm`, `ssmmessages` and `ec2messages` endpoints; `devbox check` can't test this. |

## Using access keys instead of SSO

It works the same way: put the keys in `~/.aws/credentials` under a profile and set `AWS_PROFILE`. The keys stay on your laptop. `devbox setup-identity` refuses to copy `~/.aws/config` to the box if it contains credentials.
