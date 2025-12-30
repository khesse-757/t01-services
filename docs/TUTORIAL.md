# epics-containers Tutorial: Building and Deploying IOCs

This tutorial walks through the complete workflow of creating a Generic IOC and deploying IOC instances using epics-containers. It covers both using pre-built images and building custom images.

---

## Prerequisites

### Tools Required

| Tool | Installation | Purpose |
|------|--------------|---------|
| Docker Desktop | https://docker.com | Container runtime (Mac/Windows) |
| Git | `brew install git` or system package | Version control |
| Python 3.8+ | System or pyenv | copier and ec tools |
| copier | `pip install copier` | Template scaffolding |

### Verify Installation

```bash
docker --version
git --version
python3 --version
pip install copier
```

---

## Part 1: Creating a Services Repository

A **services repository** contains IOC instance configurations for a beamline or facility area.

### Step 1.1: Generate from Template

```bash
mkdir -p ~/epics-containers-lab
cd ~/epics-containers-lab

# Create services repo from template
copier copy gh:epics-containers/services-template-compose my-services --trust
```

Answer the prompts:
- **Beamline/service name:** `my` (or your beamline name)
- **Git platform:** `github.com` (or `gitlab.com`)
- **Organization:** Your username or org

### Step 1.2: Apple Silicon Mac Fixes

If on ARM Mac, apply these fixes:

**Edit `include/ioc.yml`** - Add platform:
```yaml
services:
  linux_ioc: &linux_ioc
    platform: linux/amd64    # ADD THIS LINE
```

**Edit `compose.yaml`** - Fix init container:
```yaml
services:
  init:
    platform: linux/arm64    # ADD - runs natively
    restart: "no"            # CHANGE from "never"
```

**Set environment before docker compose:**
```bash
export DOCKER_DEFAULT_PLATFORM=linux/amd64
```

### Step 1.3: Start Services

```bash
cd my-services
source environment.sh
docker compose up -d
docker compose ps
```

---

## Part 2: Creating an IOC Instance (Pre-built Image)

An **IOC instance** is configuration that runs inside a Generic IOC container.

### Step 2.1: Copy Template IOC

```bash
cp -r services/example-test-01 services/my-ioc-01
```

### Step 2.2: Edit compose.yml

Edit `services/my-ioc-01/compose.yml`:

```yaml
services:
  my-ioc-01:                                    # Service name
    container_name: my-ioc-01                   # Container name
    extends:
      service: linux_ioc
      file: ../../include/ioc.yml
    image: ghcr.io/epics-containers/ioc-template-example-runtime:3.5.1
    labels:
      version: 0.1.0
    environment:
      IOCSH_PS1: my-ioc-01 >                    # IOC shell prompt
      IOC_NAME: my-ioc-01                       # Used in ioc.yaml
    volumes:
      - ../../opi/auto-generated/my-ioc-01:/epics/opi
    configs:
      - source: my-ioc-01_config                # Config reference
        target: epics/ioc/config

configs:
  my-ioc-01_config:                             # Must match above
    file: ./config

include:
  - path:
      ../../include/networks.yml
```

**Key points:**
- Change ALL occurrences of the old name to `my-ioc-01`
- `image:` specifies which Generic IOC to use
- `configs:` mounts the config folder into the container
- Names must be consistent throughout the file

### Step 2.3: Edit ioc.yaml

Edit `services/my-ioc-01/config/ioc.yaml`:

```yaml
ioc_name: "{{ _global.get_env('IOC_NAME') }}"
description: My IOC description

entities:
  - type: epics.EpicsEnvSet
    name: EPICS_TZ
    value: EST5EDT

  - type: devIocStats.iocAdminSoft
    IOC: "{{ ioc_name | upper }}"

  - type: epics.StartupCommand
    command: |
      dbLoadRecords("/epics/ioc/config/ioc.db")
```

**Key points:**
- `ioc_name` comes from environment variable set in compose.yml
- `entities` are processed by ibek to generate st.cmd
- `type:` must match available entity types in the Generic IOC

### Step 2.4: Create Database

Edit `services/my-ioc-01/config/ioc.db`:

```
record(ai, "MY:VALUE") {
    field(DESC, "Example value")
    field(VAL, "42")
}

record(calc, "MY:DOUBLED") {
    field(DESC, "Value times two")
    field(INPA, "MY:VALUE CP")
    field(CALC, "A*2")
}
```

### Step 2.5: Add to Main compose.yaml

Edit the main `compose.yaml`:

```yaml
include:
  - services/example-test-01/compose.yml
  - services/my-ioc-01/compose.yml              # ADD THIS
  - services/gateway/compose.yml
  - services/pvagw/compose.yml
```

### Step 2.6: Deploy

```bash
docker compose up -d
docker compose ps
docker compose logs my-ioc-01
```

---

## Part 3: Building a Custom Generic IOC

When you need support modules not in existing images, build your own Generic IOC.

### Step 3.1: Generate from Template

```bash
cd ~/epics-containers-lab

copier copy gh:epics-containers/ioc-template ioc-my-custom --trust
```

Answer the prompts:
- **Project name:** `ioc-my-custom`
- **Description:** `Generic IOC with custom support modules`
- **Git platform:** `github.com`
- **Organization:** Your username
- **RTEMS support:** `No`

### Step 3.2: Explore Available Support Modules

```bash
cd ioc-my-custom
ls ibek-support/
```

This shows all support modules with build recipes. Common ones:
- `asyn` - Communication drivers
- `StreamDevice` - Protocol-based device support
- `modbus` - Modbus TCP/RTU
- `calc` - Calculation records
- `autosave` - Save/restore
- `motor` - Motor control
- `ADCore` - Area detector framework

### Step 3.3: Edit Dockerfile

The Dockerfile lists which support modules to include. Default template has:
- iocStats
- pvlogging
- autosave

To add more, edit `Dockerfile`. Find the section with `ansible.sh` commands:

```dockerfile
COPY ibek-support/iocStats/ iocStats
RUN ansible.sh iocStats

COPY ibek-support/pvlogging/ pvlogging/
RUN ansible.sh pvlogging

# ADD NEW MODULES HERE (order can matter for dependencies)
COPY ibek-support/calc/ calc
RUN ansible.sh calc

COPY ibek-support/autosave/ autosave
RUN ansible.sh autosave
```

**Adding asyn + StreamDevice example:**
```dockerfile
COPY ibek-support/asyn/ asyn
RUN ansible.sh asyn

COPY ibek-support/StreamDevice/ StreamDevice
RUN ansible.sh StreamDevice
```

### Step 3.4: Build the Image

```bash
# On Mac (cross-compile for x86_64)
docker build --platform linux/amd64 -t ioc-my-custom:local .

# On Linux (native)
docker build -t ioc-my-custom:local .
```

**Expected time:** 5-15 minutes (compiling EPICS and support modules)

### Step 3.5: Verify the Build

```bash
# List images
docker images | grep ioc-my-custom

# Explore inside the container
docker run --rm -it --platform linux/amd64 ioc-my-custom:local bash

# Inside container:
ls /epics/support/       # See compiled support modules
ls /epics/ioc/           # See IOC structure
exit
```

### Step 3.6: Use Local Image in Services

Edit your IOC instance `compose.yml` to use the local image:

```yaml
services:
  my-ioc-01:
    image: ioc-my-custom:local    # Local image instead of registry
```

---

## Part 4: Configuring Autosave

Autosave preserves PV values across IOC restarts.

### Step 4.1: Add Autosave Volume

Edit IOC instance `compose.yml`:

```yaml
services:
  my-ioc-01:
    # ... other config ...
    volumes:
      - ../../opi/auto-generated/my-ioc-01:/epics/opi
      - autosave-my-ioc-01:/autosave              # ADD THIS

# ADD this section at bottom
volumes:
  autosave-my-ioc-01:
```

### Step 4.2: Configure Autosave in ioc.yaml

Check available entity parameters:
```bash
cat ibek-support/autosave/*.ibek.support.yaml
```

Edit `config/ioc.yaml`:

```yaml
entities:
  # ... other entities ...

  # Add request file path BEFORE autosave entity
  - type: epics.StartupCommand
    command: |
      set_requestfile_path("/epics/ioc", "config")

  - type: autosave.Autosave
    P: "MY:"                      # PV prefix for status records
    path: /autosave               # Must match volume mount
    positions_req_period: 0       # 0 = don't save positions
    settings_req_period: 10       # Save settings every 10 seconds

  - type: epics.StartupCommand
    command: |
      dbLoadRecords("/epics/ioc/config/ioc.db")
```

**Key points:**
- Entity type is case-sensitive (`autosave.Autosave`, not `autosave.autosave`)
- `P:` value with colon must be quoted (`"MY:"`)
- `path:` must match volume mount in compose.yml (not inside config/)

### Step 4.3: Create Request File

Create `config/autosave_settings.req`:

```
# PVs to save - one per line
MY:SETPOINT
MY:GAIN
MY:OFFSET
MY:MODE
```

### Step 4.4: Test Autosave

```bash
# Deploy
docker compose up -d

# Check autosave connected
docker compose logs my-ioc-01 | grep "PV's connected"
# Should show: "autosave_settings.sav: N of N PV's connected"

# Change a value
caput MY:SETPOINT 42.5

# Wait for save (save_period + a few seconds)
sleep 15

# Verify save file
docker exec -it my-ioc-01 cat /autosave/autosave_settings.sav

# Restart and verify persistence
docker compose restart my-ioc-01
sleep 5
caget MY:SETPOINT    # Should show 42.5
```

---

## Part 5: Network Configuration

### Development Mode (Isolated with Gateways)

Default template configuration. Each project has isolated network.

**Client access:**
```bash
export EPICS_CA_ADDR_LIST=127.0.0.1:5064
export EPICS_CA_AUTO_ADDR_LIST=NO
caget MY:PV
```

**Multiple projects need unique ports** (in `.env`):
```
CA_SERVER_PORT=5064    # Project 1
CA_SERVER_PORT=5074    # Project 2
```

### Production Mode (Host Network)

Edit `include/ioc.yml`:

```yaml
services:
  linux_ioc: &linux_ioc
    network_mode: host
    # Comment out or remove:
    # networks:
    #   - channel_access
```

Remove gateway services from `compose.yaml`:
```yaml
include:
  - services/my-ioc-01/compose.yml
  # Remove: gateway, pvagw includes
```

IOCs broadcast directly on host network - identical to procServ.

---

## Part 6: Publishing to Container Registry

### Step 6.1: Create GitHub Repository

```bash
cd ioc-my-custom
git add -A
git commit -m "Initial commit"

# Create repo on GitHub, then:
git remote set-url origin git@github.com:YOUR-USER/ioc-my-custom.git
git push -u origin main
```

### Step 6.2: GitHub Actions CI

The template includes `.github/workflows/build.yml` which:
1. Builds the container on push
2. Pushes to GitHub Container Registry (ghcr.io)
3. Tags with version and `latest`

**Required:** Enable GitHub Actions and set up GHCR permissions.

### Step 6.3: Use Published Image

After CI builds, update IOC instance `compose.yml`:

```yaml
image: ghcr.io/YOUR-USER/ioc-my-custom:latest
```

### GitLab CI Alternative

Create `.gitlab-ci.yml`:

```yaml
stages:
  - build

build:
  stage: build
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_TAG .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_TAG
  only:
    - tags
```

---

## Part 7: Common Operations

### Container Management

| Operation | Command |
|-----------|---------|
| Start all | `docker compose up -d` |
| Stop all | `docker compose down` |
| Restart one IOC | `docker compose restart ioc-name` |
| Stop one IOC | `docker compose stop ioc-name` |
| View status | `docker compose ps` |
| View logs | `docker compose logs ioc-name` |
| Follow logs | `docker compose logs -f ioc-name` |
| IOC console | `docker attach ioc-name` |
| Detach console | `Ctrl-P Ctrl-Q` |
| Shell into container | `docker exec -it ioc-name bash` |
| Run caget inside | `docker exec -it ioc-name caget MY:PV` |

### Environment Setup (Development)

```bash
# Gateway access (isolated network mode)
export EPICS_CA_ADDR_LIST=127.0.0.1:5064
export EPICS_CA_AUTO_ADDR_LIST=NO

# Clear any conflicting settings
unset EPICS_CA_NAME_SERVERS
```

### Viewing All Containers

```bash
# All containers on host (all projects)
docker ps

# With project names
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Label \"com.docker.compose.project\"}}"
```

### Log Management

Add to compose.yml to limit log size:

```yaml
services:
  my-ioc-01:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

---

## Part 8: Comparison to Traditional Workflow

### Process Management

| Traditional | Containers |
|-------------|------------|
| `procServMgr start ioc` | `docker compose up -d ioc` |
| `procServMgr stop ioc` | `docker compose stop ioc` |
| `procServMgr restart ioc` | `docker compose restart ioc` |
| `procServMgr status` | `docker compose ps` |
| `softioc_console ioc` | `docker attach ioc` |
| `telnet host 20007` | `docker attach ioc` |

### Version Control

| Traditional | Containers |
|-------------|------------|
| CVS/SVN for apps | Git for everything |
| Dated config files | Git commits/tags |
| Symlinks to versions | Container image tags |
| Boot dirs not versioned | Config in Git |

### File Locations

| Traditional | Containers |
|-------------|------------|
| `/opt/epics/base` | Inside container image |
| `/path/to/support/module` | Inside container image |
| `/path/to/iocs/boot-dir/` | `services/ioc-name/config/` |
| `startup.all` | `config/ioc.yaml` |
| `startup.ipconfig` | Entities in `ioc.yaml` |
| `resource.def` | `epics.EpicsEnvSet` entities |
| Autosave files | Docker named volume |

### Building/Compiling

| Traditional | Containers |
|-------------|------------|
| `make` in app directory | `docker build` |
| RELEASE file dependencies | Dockerfile `ansible.sh` lines |
| Shared EPICS installation | Each container has own copy |
| Architecture-specific binaries | Multi-arch images possible |

---

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker compose logs ioc-name

# Common issues:
# - YAML syntax error in ioc.yaml
# - Wrong entity type name (case sensitive)
# - Missing database file
# - Mount path conflict
```

### Entity Type Not Found

Error: `Input tag 'xxx.yyy' does not match any of the expected tags`

**Fix:** Check exact entity name in ibek-support YAML:
```bash
cat ibek-support/MODULE/*.ibek.support.yaml
```

Entity types are case-sensitive!

### YAML Syntax Error

Error: `mapping values are not allowed in this context`

**Fix:** Quote strings containing colons:
```yaml
# Wrong:
P: DEMO:

# Right:
P: "DEMO:"
```

### Autosave "0 of 0 PV's connected"

**Fix:** Create manual request file and add path:
```yaml
- type: epics.StartupCommand
  command: |
    set_requestfile_path("/epics/ioc", "config")
```

### "Identical process variable names" Warning

Normal when running caget inside container (sees both IOC and gateway). Use:
```bash
docker exec -it ioc bash -c "EPICS_CA_AUTO_ADDR_LIST=NO EPICS_CA_ADDR_LIST=localhost caget PV"
```

Or access from host through gateway.

### Mac Network Errors

Set environment:
```bash
export EPICS_CA_ADDR_LIST=127.0.0.1:5064
export EPICS_CA_AUTO_ADDR_LIST=NO
unset EPICS_CA_NAME_SERVERS
```

---

## Quick Reference: File Naming Consistency

When creating an IOC instance, these names must match:

```
services/my-ioc-01/compose.yml:
  services:
    my-ioc-01:                    ─┐
      container_name: my-ioc-01    │ All must match
      environment:                 │
        IOC_NAME: my-ioc-01       ─┤
      configs:                     │
        - source: my-ioc-01_config ─┘ (with _config suffix)
  configs:
    my-ioc-01_config:             ← Must match source above
```

```
compose.yaml:
  include:
    - services/my-ioc-01/compose.yml  ← Directory name
```

---

## Quick Reference: Entity Types

Common entity types (case-sensitive):

| Module | Entity Type | Purpose |
|--------|-------------|---------|
| epics | `epics.EpicsEnvSet` | Set environment variable |
| epics | `epics.StartupCommand` | Pre-iocInit command |
| epics | `epics.PostStartupCommand` | Post-iocInit command |
| devIocStats | `devIocStats.iocAdminSoft` | IOC statistics |
| autosave | `autosave.Autosave` | Save/restore setup |
| asyn | `asyn.AsynIPPort` | IP port configuration |

Check available entities:
```bash
cat ibek-support/MODULE/*.ibek.support.yaml
```