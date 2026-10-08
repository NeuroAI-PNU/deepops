Example DeepOps configuration
=============================

This directory provides an example configuration for NVIDIA DeepOps.
The files in this directory will help determine the behavior of the Ansible playbooks and other scripts that DeepOps uses to set up your systems.

For more details on how this works, see [how to configure DeepOps](../docs/deepops/configuration.md).

NeuroAI cluster notes (2026-09)
-------------------------------
* `inventory`: **ldap** is slurm-master/NFS *and* a `cpu`-partition compute node; **neuroai4** is the
  login node (external port 53007) *and* a compute node. Both carry `slurm_node_extra`
  (CoreSpecCount/MemSpecLimit) in `host_vars/` so services and logins keep CPU/memory headroom.
* `playbooks/login-compute-guardrails.yml`: the systemd/PAM/epilog guardrails those two roles need
  (per-user caps on neuroai4, whole-job IO+memory caps on ldap). Run it after the slurm role.
* `group_vars/slurm-cluster.yml`: ldap and neuroai4 are reachable only through `short` (<= 4 h);
  `batch`/`cpu` list the GPU nodes explicitly. `short` and `cpu` carry `def_mem_per_cpu: 1024`,
  which is **enforced** by cgroup.conf (jobs without `--mem` are OOM-killed at 1 GB/CPU).
* `playbooks/security-baseline.yml` (2026-10): unattended security upgrades (kernel/GPU/Slurm
  excluded -> monthly drain/upgrade/reboot), key-only sshd, ufw (22 + lab networks + per-host
  `security_public_tcp_ports`), fail2ban on neuroai4, neuroai1 NIC-by-MAC netplan. The live Slurm is
  the 22.05.2 build in `/usr/local`; Ubuntu's slurm 21.08 packages are leftovers (neuroai1 keeps
  `libslurm37`/`slurm-wlm-basic-plugins` because mpich depends on them).
* Not in this repo (deliberately): the Prometheus/Grafana/alert stack, probes and timers on ldap
  (`/usr/local/bin/*-probe.sh`, `/etc/prometheus/rules/alert_rules.yml`, `/var/lib/grafana/dashboards`).
