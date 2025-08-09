# Remote Servers

- Access proxmox (linux) server with `ssh proxmox`
- For execute sudo on proxmox, set this first `SUDO_ASKPASS=$HOME/.config/bin/answer.sh`.
- Access NAS server (synology) with `ssh nas`
- Access dockermaster (ubuntu linux) server, repository of all home docker container, with command `ssh dockermaster`
- For execute sudo on proxmox, set this first `SUDO_ASKPASS=$HOME/.config/bin/answer`.
- 
# Inventory

- Document all servers, VMs and Containers on the files: `inventory/servers.md`, `inventory/virtual-machines.md`, and `inventory/docker-containers.md`
- Document all commands used and versions available, identifying the servers, on the file: `inventory/commands-available.md`

# General Instructions

- Use the MCP sequentialthinking, documentation, context7, and filesystem as preferences.
- Keep an updated note of this project using MCP memory.
- Use any other MCP available that can improve the results or facilitate the task you are working with or planning.
- *Always plan the task and optimize on subtasks that can be executed in parallel. Then spinout subagents with very refined and detailed instructions to complete those tasks. Instruct these agents to always use sequentialthinking and any other MCP relevant to their tasks.*




- Docker compose use `docker compose` command. Always use the latest docker ce version.