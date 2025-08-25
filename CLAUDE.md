# Remote Servers

- Access proxmox (linux) server with `ssh proxmox`
- For execute sudo on proxmox, set this first `SUDO_ASKPASS=$HOME/.config/bin/answer.sh`.
- Access NAS server (synology) with `ssh nas`
- Access dockermaster (ubuntu linux) server, repository of all home docker container, with command `ssh dockermaster`
- For execute sudo on proxmox, set this first `SUDO_ASKPASS=$HOME/.config/bin/answer`.
- Containers can run on internal LAN using docker-servers-net, and still have access to internet.
    {
        "Name": "docker-servers-net",
        "Id": "42c3a8018724a236c20c1470c97a1aa7ddc8c69ff0a2c7f1a01cdedf8d428e3d",
        "Created": "2025-03-31T11:26:54.534393079-06:00",
        "Scope": "local",
        "Driver": "macvlan",
        "EnableIPv4": true,
        "EnableIPv6": false,
        "IPAM": {
            "Driver": "default",
            "Options": {},
            "Config": [
                {
                    "Subnet": "192.168.48.0/20",
                    "IPRange": "192.168.59.0/26",
                    "Gateway": "192.168.48.1",
                    "AuxiliaryAddresses": {
                        "host": "192.168.59.1"
                    }
                }
            ]
        },...
- We need to implement passive Continuous Deployment from dockermaster.

# Inventory

- Document all servers, VMs and Containers on the files: `inventory/servers.md`, `inventory/virtual-machines.md`, and `inventory/docker-containers.md`
- Document all commands used and versions available, identifying the servers, on the file: `inventory/commands-available.md`
- Current project status and documents must be stored at `docs` directory.
    - Create documents for architecture, CI/CD, special scripts and or translations.
- Inventory documentation should be on `inventory`
- Use memory tool mcp to register documentation tips, keywords or indexes

# General Instructions

- Use the MCP think-tool, documentation, context7, and filesystem as preferences.
- Keep an updated note of this project using MCP memory.
- Use any other MCP available that can improve the results or facilitate the task you are working with or planning.
- *Always plan the task and optimize on subtasks that can be executed in parallel. Then spinout subagents with very refined and detailed instructions to complete those tasks. Instruct these agents to always use sequentialthinking and any other MCP relevant to their tasks.*
- Docker compose use `docker compose` command. Always use the latest docker ce version.
- Use memory MCP to enhance context before each task.
- Register entities, relations and notes about the project on memory MCP.
- Don't consider using frameworks, tools or systems that are under a paywall of any sort. Even if have a freetier.
- Use multiple sub-agents to perform tasks organized by to do. The agents must receive detailed instructions, use think-tool and Sonnet model.
- We use mise, and should use mise if a different version of npm or any tool is needed.
- Create branches for big changes
- Commit between feature implementations
- Keep branches for history, don't delete them unless commanded to do it
- Prefer to use github MCP over gh command when possible

## Testing, Validation or Errors

- Never commit with a validation issue. Suggest and offer to fix it.
- Never push with a pre-push validation issue. Suggest and offer to fix it.
- When using temporary scripts for tests or partial tests, remember the files and clean then out when all tasks from todo list are completed.
- Use grep to classify and troubleshoot errors before start working on then. E.g. Use something like `git push -n origin github-runner-cicd | grep -B2 -A2 -i -E "(error|warn|style)"`. Don't check only the first lines, be smart on filtering, e.g. `git push -n origin github-runner-cicd 2>&1 | grep -i -E "(error|warn|style)" | wc -l` count the number of issues or errors.
- Only use `head` or `tail` commands to verify if "any" line exists on the return. It doesn't eliminate specific contents like errors or occurencies. For those use `grep` or `grep` + `wc -l` if too many.
