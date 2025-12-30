# Development Notes

## Project Info

- **Created:** December 2024
- **Template:** `services-template-compose` via copier
- **Template URL:** https://github.com/epics-containers/services-template-compose
- **Purpose:** Learning epics-containers workflow

---

## Prerequisites

### Required Tools

| Tool | Mac | Linux (RHEL/Rocky) | Purpose |
|------|-----|-------------------|---------|
| Container runtime | Docker Desktop | podman | Run containers |
| Git | `brew install git` | `dnf install git` | Version control |
| Python 3.8+ | System/pyenv | System | copier, ec tools |
| copier | `pip install copier` | `pip install copier` | Template scaffolding |
| XQuartz | `brew install --cask xquartz` | N/A (native X11) | GUI on Mac |

---

## Quick Start

```bash
cd /path/to/your-services

# Required for Apple Silicon Macs
export DOCKER_DEFAULT_PLATFORM=linux/amd64

# Set up environment
source environment.sh

# Start all services
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs <ioc-name>

# Test PVs from inside container
docker exec -it <ioc-name> caget YOUR:PV:NAME

# Access from host (development mode with gateways)
export EPICS_CA_ADDR_LIST=127.0.0.1:5064
export EPICS_CA_AUTO_ADDR_LIST=NO
caget YOUR:PV:NAME

# Shut down
docker compose down
```

---

## Adding a New IOC Instance

### Step 1: Copy an existing IOC

```bash
cp -r services/example-test-01 services/my-new-ioc
```

### Step 2: Edit compose.yml

Update all references to the new name in `services/my-new-ioc/compose.yml`:

```yaml
services:
  my-new-ioc:                              # Service name
    container_name: my-new-ioc             # Container name
    extends:
      service: linux_ioc
      file: ../../include/ioc.yml
    image: ghcr.io/epics-containers/ioc-template-example-runtime:3.5.1
    environment:
      IOCSH_PS1: my-new-ioc >              # IOC shell prompt
      IOC_NAME: my-new-ioc                 # Used in ioc.yaml
    volumes:
      - ../../opi/auto-generated/my-new-ioc:/epics/opi
    configs:
      - source: my-new-ioc_config          # Config name
        target: epics/ioc/config

configs:
  my-new-ioc_config:                       # Must match above
    file: ./config
```

### Step 3: Edit config/ioc.yaml

```yaml
ioc_name: "{{ _global.get_env('IOC_NAME') }}"
description: My new IOC description

entities:
  - type: epics.EpicsEnvSet
    name: EPICS_TZ
    value: EST5EDT

  - type: devIocStats.iocAdminSoft
    IOC: "{{ ioc_name | upper }}"

  - type: epics.StartupCommand
    command: |
      dbLoadRecords("/epics/ioc/config/my-records.db")
```

### Step 4: Create config/ioc.db

Add your EPICS database records.

### Step 5: Add to compose.yaml

Edit the main `compose.yaml` and add to the include section:

```yaml
include:
  - services/example-test-01/compose.yml
  - services/my-new-ioc/compose.yml        # ADD THIS
  - services/gateway/compose.yml
  # ...
```

### Step 6: Restart

```bash
docker compose down
docker compose up -d
docker compose ps
```

---

## IOC Console and Logs

### Accessing the IOC Shell

```bash
# Attach to IOC console (like softioc_console or telnet to procServ port)
docker attach <ioc-name>

# You'll see the IOC prompt:
ioc-name > dbl
ioc-name > dbpr MY:PV:NAME
```

**Detach:** `Ctrl-P Ctrl-Q` (may not work in all terminals - close terminal as fallback)

### Viewing Logs

```bash
# View recent logs
docker compose logs <ioc-name>

# Follow logs in real-time (like tail -f)
docker compose logs -f <ioc-name>

# See last 100 lines
docker compose logs --tail 100 <ioc-name>

# Logs from all containers
docker compose logs

# With timestamps
docker compose logs -t <ioc-name>
```

### Log Storage and Limits

By default, Docker logs grow unbounded. Configure limits in compose.yml:

```yaml
services:
  my-ioc:
    # ... other config ...
    logging:
      driver: "json-file"
      options:
        max-size: "10m"      # Max 10MB per file
        max-file: "3"        # Keep 3 rotated files
```

This gives you 30MB max per container (3 × 10MB).

### Finding Log Files

```bash
# Find where Docker stores logs for a container
docker inspect <container-name> --format='{{.LogPath}}'
```

---

## Managing Multiple Projects on One Server

### Project Isolation

Each `compose.yaml` defines a separate **project**. Docker Compose operates per-project:

```bash
# In project-a directory
cd /opt/containers/project-a
docker compose ps          # Shows only project-a containers

# In project-b directory
cd /opt/containers/project-b
docker compose ps          # Shows only project-b containers
```

### Seeing All Containers (Across All Projects)

```bash
# Docker command (not compose) - shows EVERYTHING on this host
docker ps

# Show containers with their project names
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Label \"com.docker.compose.project\"}}"
```

Example output:
```
NAMES               STATUS          PROJECT
ioc-vacuum-01       Up 2 hours      bl01-services
ioc-motor-01        Up 2 hours      bl01-services
ioc-camera-01       Up 1 hour       bl02-services
ioc-pump-01         Up 1 hour       bl02-services
ca-gateway          Up 2 hours      bl01-services
ca-gateway          Up 1 hour       bl02-services
```

### Managing Specific Projects From Anywhere

```bash
# Explicit project targeting
docker compose -p bl01-services ps
docker compose -p bl02-services ps

# Or point to specific compose file
docker compose -f /opt/containers/bl01-services/compose.yaml ps
```

### Port and Subnet Requirements

Each project using isolated networking needs **unique ports and subnets** (in `.env`):

| Project | CA Port | PVA Port | Subnet |
|---------|---------|----------|--------|
| bl01-services | 5064 | 5075 | 170.200.0.0/16 |
| bl02-services | 5074 | 5085 | 170.201.0.0/16 |
| bl03-services | 5084 | 5095 | 170.202.0.0/16 |

**Note:** With host networking (production mode), ports/subnets are not needed.

### Useful Script: Show All IOCs

```bash
#!/bin/bash
# ioc-status.sh - Show all IOC containers across all projects
docker ps --filter "label=is_ioc=true" \
  --format "table {{.Names}}\t{{.Status}}\t{{.Label \"com.docker.compose.project\"}}"
```

---

## Network Modes

### Development Mode (Isolated + Gateways)

Default template configuration. Each project has its own isolated network with gateways.

**Use when:**
- Developing on Mac/laptop
- Testing multiple projects on same machine
- Want isolation between projects

**Client access:**
```bash
export EPICS_CA_ADDR_LIST=127.0.0.1:5064
export EPICS_CA_AUTO_ADDR_LIST=NO
```

### Production Mode (Host Network)

IOCs use host network directly - exactly like procServ.

**Configure in `include/ioc.yml`:**
```yaml
services:
  linux_ioc: &linux_ioc
    network_mode: host
    # Remove or comment out:
    # networks:
    #   - channel_access
```

**Simplify `compose.yaml`** - remove gateway services:
```yaml
include:
  - services/ioc-vacuum-01/compose.yml
  - services/ioc-motor-01/compose.yml
  # NO gateway or pvagw includes needed
```

**Use when:**
- Production servers
- Integration with existing CA nameserver
- Want IOCs to behave exactly like procServ

---

## Security Files (ACF)

### Volume Mount (Recommended)

Mount central ACF directory into containers:

```yaml
# In include/ioc.yml
services:
  linux_ioc: &linux_ioc
    volumes:
      - /path/to/acf_directory:/epics/acf:ro
```

In `ioc.yaml`:
```yaml
entities:
  - type: epics.StartupCommand
    command: |
      asSetFilename("/epics/acf/secure/myioc.acf")
```

### Refresh Security After ACF Update

```bash
#!/bin/bash
# refresh-security.sh

for container in $(docker ps --filter "label=is_ioc=true" --format "{{.Names}}"); do
    echo "Running asInit on $container"
    docker exec $container bash -c 'caput ${IOC_NAME}:asInit 1' 2>/dev/null || \
    echo "  (no asInit PV or not responding)"
done
```

---

## Apple Silicon Mac Fixes

### 1. include/ioc.yml - Add platform for IOCs

```yaml
services:
  linux_ioc: &linux_ioc
    platform: linux/amd64    # ADD THIS LINE
    labels:
      ioc_group: "t01"
```

### 2. compose.yaml - Fix init container

```yaml
services:
  init:
    image: ubuntu
    platform: linux/arm64    # ADD - runs natively on ARM
    restart: "no"            # CHANGE from "never" to "no" (with quotes)
```

### 3. Environment variable

```bash
export DOCKER_DEFAULT_PLATFORM=linux/amd64
```

---

## Phoebus on Mac

The compose-based Phoebus doesn't work on Mac. Use a manual launcher.

### Setup XQuartz (one time)

1. Install: `brew install --cask xquartz`
2. Open XQuartz → Settings → Security → Check "Allow connections from network clients"
3. **Log out and log back in**

### Launch Script (opi/mac-launch.sh)

```bash
#!/bin/bash
THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NETWORK="your-project_channel_access"

xhost + 127.0.0.1 > /dev/null
echo "Launching Phoebus on network: $NETWORK"

docker run -it --rm \
  --platform linux/amd64 \
  -e DISPLAY=host.docker.internal:0 \
  --network $NETWORK \
  -v "${THIS_DIR}:/workspace" \
  ghcr.io/epics-containers/ec-phoebus:latest \
  -resource /workspace/demo.bob \
  -settings /workspace/settings.ini
```

### Settings File (opi/settings.ini)

```ini
org.phoebus.pv.ca/addr_list=host.docker.internal:5064
org.phoebus.pv.ca/auto_addr_list=false
org.phoebus.pv.pva/epics_pva_name_servers=host.docker.internal:5075
org.phoebus.pv.pva/epics_pva_auto_addr_list=false
org.phoebus.pv/default=ca
```

---

## Docker/Podman Command Reference

### Container Lifecycle

| Docker | Podman | Purpose |
|--------|--------|---------|
| `docker compose up -d` | `podman-compose up -d` | Start all services |
| `docker compose down` | `podman-compose down` | Stop and remove all |
| `docker compose stop` | `podman-compose stop` | Stop all (keep containers) |
| `docker compose stop <name>` | `podman-compose stop <name>` | Stop one service |
| `docker compose start <name>` | `podman-compose start <name>` | Start one service |
| `docker compose restart <name>` | `podman-compose restart <name>` | Restart one service |
| `docker compose ps` | `podman-compose ps` | Show project status |

### Container Interaction

| Command | Purpose |
|---------|---------|
| `docker exec -it <container> bash` | Shell into container |
| `docker exec -it <container> caget PV` | Run caget inside |
| `docker attach <container>` | Attach to IOC console |
| `Ctrl-P Ctrl-Q` | Detach from console |

### Images and Networks

| Command | Purpose |
|---------|---------|
| `docker images` | List local images |
| `docker pull <image>` | Pull image from registry |
| `docker image prune` | Remove unused images |
| `docker network ls` | List networks |
| `docker network prune` | Remove unused networks |
| `docker ps` | All containers (all projects) |

---

## Comparison to Traditional Commands

| Traditional (procServ) | Containers |
|------------------------|------------|
| `procServMgr start iocname` | `docker compose up -d iocname` |
| `procServMgr stop iocname` | `docker compose stop iocname` |
| `procServMgr restart iocname` | `docker compose restart iocname` |
| `procServMgr status` | `docker compose ps` |
| `softioc_console iocname` | `docker attach iocname` |
| `telnet localhost 20007` | `docker attach iocname` |
| Edit startup.all, restart | Edit `config/ioc.yaml`, commit, restart |
| Update symlink config | Change image tag in `compose.yml` |
| `req EPICS_VERSION` | (Version is in container image) |
| `cvshelper minor App 1 2 3` | `git tag 1.2.3 && git push origin 1.2.3` |
| View logs in /var/log | `docker compose logs iocname` |

---

## Troubleshooting

### "no matching manifest for linux/arm64/v8"

**Cause:** Container image not built for ARM
**Fix:** Add `platform: linux/amd64` or set `DOCKER_DEFAULT_PLATFORM=linux/amd64`

### "Pool overlaps with other one on this address space"

**Cause:** Another project using same Docker subnet
**Fix:** Stop other project (`docker compose down`) or change subnet in `.env`

### "Unable to open DISPLAY"

**Cause:** Phoebus can't connect to X11
**Fix:** `open -a XQuartz && xhost + 127.0.0.1`

### "restart policy 'never' is invalid"

**Cause:** Docker Compose version difference
**Fix:** Change `restart: never` to `restart: "no"` (with quotes)

### PVs timeout from host

**Cause:** Wrong EPICS_CA_ADDR_LIST
**Fix:**
```bash
export EPICS_CA_ADDR_LIST=127.0.0.1:5064
export EPICS_CA_AUTO_ADDR_LIST=NO
```

### Container keeps restarting

**Check logs:**
```bash
docker compose logs <container>
```

**Common issues:**
- Config file syntax error in ioc.yaml
- Missing database file
- Port conflict

---

## Podman Notes (Linux/Production)

### Installation (RHEL/Rocky)

```bash
sudo dnf install podman podman-compose
```

### Key Differences

- Podman is daemonless (no background service)
- Rootless by default
- Commands nearly identical to Docker
- Use `podman-compose` or `podman compose` (v4+)

---

## Git Workflow

### Creating a Version

```bash
git add -A
git commit -m "describe changes"
git push

# Tag a release (CalVer: YYYY.MM.patch)
git tag 2024.12.1
git push origin 2024.12.1
```

### Rolling Back

```bash
git log --oneline
git checkout 2024.11.14
docker compose down
docker compose up -d
```

### Updating from Template

```bash
copier update .
git diff
git add -A
git commit -m "update from template"
```

---

## Resources

- [epics-containers Documentation](https://epics-containers.github.io/main/)
- [epics-containers GitHub](https://github.com/epics-containers)
- [Docker Compose Reference](https://docs.docker.com/compose/)
- [Podman Documentation](https://docs.podman.io/)
- [ibek Documentation](https://github.com/epics-containers/ibek)
