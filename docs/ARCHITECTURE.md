# epics-containers Architecture

## Overview

This document explains the epics-containers approach for someone familiar with traditional EPICS IOC development, specifically mapping from a workflow using shared filesystems, procServ, and facility-specific tooling.

---

## The Paradigm Shift

### Traditional EPICS Model

```
Shared Filesystem
├── /path/to/epics/R7.0.8/                 # EPICS base
├── /path/to/prod/R7.0.8/                  # Support modules (versioned)
│   ├── asyn/4-44/
│   ├── calc/3-7-4/
│   ├── StreamDevice/2.8.22/
│   ├── MyDeviceSupport/1-3/               # Your app (library mode)
│   │   ├── db/device.db
│   │   ├── dbd/
│   │   ├── stcmd/startup.db.iocexample
│   │   └── vdc/device.vdb                 # VDCT source (if used)
│   └── MyIOCApp/1-3/                      # Your app (IOC binary)
│       ├── bin/linux-x86_64/
│       └── stcmd/
│
├── /path/to/iocs/ioc-example-01/          # Boot directory (often NOT version controlled)
│   ├── startup.all                        # Hand-edited orchestrator
│   ├── startup.ipconfig                   # IP/port configuration
│   ├── config/config.111425               # Dated config snapshots (manual VC)
│   ├── MyDeviceSupportV -> ../prod/...    # Symlinks to versioned modules
│   └── resource.def -> ../resource.def   # Environment settings
│
└── Version Control (CVS, SVN, Git)        # Apps versioned, boot dirs often not
```

**Common pain points:**
- Boot directories aren't version controlled
- Dated config files as manual version control (`config.111425`, `config.032922`)
- Can't easily answer "what was running last Tuesday?"
- Symlinks track versions, but boot dir state is disconnected
- Developers can edit production boot dirs directly

### epics-containers Model

```
Git Repositories (GitHub, GitLab, etc.)
├── Generic IOC repo (ioc-streamdevice)    # Container IMAGE definition
│   ├── Dockerfile                         # Recipe: base + support modules
│   └── ibek-support/                      # Support module build definitions
│
└── Services repo (bl01-services)          # IOC INSTANCE definitions
    ├── compose.yaml                       # Which IOCs to run
    └── services/
        └── ioc-vacuum-01/
            ├── compose.yml                # Container configuration
            └── config/
                ├── ioc.yaml               # Replaces startup.all
                ├── device.db              # Database files
                └── protocols/             # StreamDevice protocols

Container Registry (ghcr.io, Docker Hub, GitLab Registry, etc.)
└── registry.example.com/ioc-streamdevice:1.0.0   # Pre-built, immutable image

Workflow:
1. Choose or build a Generic IOC image
2. Write config files (ioc.yaml, db files)
3. git commit -m "update IOC config"
4. git tag 2024.11.14
5. docker compose up -d
```

**How this solves the problems:**
- **Everything is in git** - full history, no dated files
- **Immutable images** - container image is frozen at build time
- **Reproducible** - `git checkout 2024.11.14 && docker compose up` recreates exact state
- **No direct edits to production** - changes must go through git

---

## Key Concepts

### Generic IOC (Container Image)

A **Generic IOC** is a pre-compiled container image containing:
- EPICS base (specific version)
- Support modules (asyn, calc, autosave, streamdevice, etc.)
- IOC binary
- ibek (runtime configuration tool)

Think of it as a **capability** - "this image can talk to serial devices via StreamDevice."

**The Generic IOC replaces:**
- EPICS base installation
- Support module installations  
- The IOC application binary
- RELEASE file dependencies

**What determines if you need a new Generic IOC:**

| Situation | Same Generic IOC? | Why |
|-----------|-------------------|-----|
| Different IP addresses | ✅ Yes | Configuration only |
| Different databases | ✅ Yes | Configuration only |
| Different macros | ✅ Yes | Configuration only |
| Different StreamDevice protocols | ✅ Yes | Configuration only |
| Need a new support module | ❌ No | Requires recompile |
| Custom device support (.c code) | ❌ No | Requires recompile |
| Custom sequencer (.stt) | ❌ No | Requires recompile |
| Different EPICS base version | ❌ No | Requires rebuild |

### IOC Instance (Configuration)

An **IOC Instance** is configuration that runs inside a Generic IOC container:
- `ioc.yaml` - Declarative configuration (replaces startup scripts)
- `*.db` files - EPICS database files (from VDCT or hand-written)
- Protocol files - StreamDevice `.proto` files
- `compose.yml` - Docker service definition

**No compilation required.** Just configuration files in git.

**The IOC Instance replaces:**
- The boot directory
- startup.all and all startup.* fragments
- Version config file (for symlink managers)
- Process manager config entry (procServ, etc.)

### ibek - The Runtime Bridge

**ibek** (IOC Builder for EPICS and Kubernetes) runs inside the container at startup.

Traditional startup.all:
```bash
< startup.myapp.munch
< startup.ipconfig
< startup.myapp.db
< startup.device.db
< resource.def
< startup.epicsgo
< startup.caPutLog
dbpf "DEV:SENSOR.HIHI", "0.75"
```

Equivalent ioc.yaml:
```yaml
ioc_name: ioc-vacuum-01
description: Vacuum system IOC

entities:
  # Environment (replaces resource.def)
  - type: epics.EpicsEnvSet
    name: EPICS_CA_ADDR_LIST
    value: "10.0.0.255"
  
  - type: epics.EpicsEnvSet
    name: STREAM_PROTOCOL_PATH
    value: "/epics/ioc/config/protocols"

  # Asyn ports (replaces startup.ipconfig)
  - type: asyn.AsynIPPort
    name: DEV1
    host: terminal-server-01
    port: 2101

  - type: asyn.AsynIPPort
    name: DEV2
    host: terminal-server-01
    port: 2102

  # IOC stats
  - type: devIocStats.iocAdminSoft
    IOC: "{{ ioc_name | upper }}"

  # Load databases (replaces startup.*.db)
  - type: epics.StartupCommand
    command: |
      dbLoadRecords("/epics/ioc/config/device.db", "ZONE=A, PORT=DEV1")
      dbLoadRecords("/epics/ioc/config/sensor.db", "ZONE=A, PORT=DEV2")

  # Post-init commands
  - type: epics.PostStartupCommand
    command: |
      dbpf "DEV:SENSOR.HIHI", "0.75"
      dbpf "DEV:SENSOR.HIGH", "0.4"
```

ibek reads this YAML and generates the actual st.cmd at container startup.

---

## The Generic IOC Hierarchy

```
                    epics-containers base images
                    (EPICS base, build tools)
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
         ▼                    ▼                    ▼
 ┌───────────────┐   ┌───────────────┐   ┌───────────────┐
 │ioc-streamdev  │   │ioc-areadet    │   │ioc-modbus     │
 │               │   │               │   │               │
 │ asyn          │   │ ADCore        │   │ asyn          │
 │ StreamDevice  │   │ ADSimDet      │   │ modbus        │
 │ calc          │   │ calc          │   │ calc          │
 │ autosave      │   │ autosave      │   │ autosave      │
 │ iocStats      │   │ iocStats      │   │ iocStats      │
 └───────┬───────┘   └───────────────┘   └───────────────┘
         │
         │ No custom compiled code needed
         │ = Many IOC instances from one image
         │
  ┌──────┼──────┬──────────────┬──────────────┐
  │      │      │              │              │
  ▼      ▼      ▼              ▼              ▼
Gauge1  Pump1  Gauge2        Pump2         Future
inst.   inst.  inst.         inst.         Device
```

**When custom compiled code is needed:**

```
 ┌─────────────────────┐
 │ioc-custom-vacuum    │  ◄── Device-specific Generic IOC
 │                     │
 │ asyn                │
 │ StreamDevice        │
 │ calc, autosave      │
 │ CustomAlarm.c  ◄────┼──── Custom device support
 │ VacuumSeq.stt  ◄────┼──── Custom sequencer
 └──────────┬──────────┘
            │
            │ Can still have multiple instances
            │ (different zones, different hardware)
            │
     ┌──────┴──────┐
     │             │
     ▼             ▼
 zone-A         zone-B
 instance       instance
```

---

## Mapping: Traditional Workflow → Containers

### Version Management

| Traditional | Containers |
|-------------|------------|
| `epics_version = R7.0.8` | Container base image tag |
| `MySupport = 1-3` | Built into Generic IOC image |
| `config.111425` (dated file) | `git tag 2024.11.14` |
| Symlink manager updates links | Image tag in compose.yml |

### Startup Fragments

| Traditional File | Container Equivalent |
|------------------|---------------------|
| startup.munch (load binary, DBD) | Built into container image |
| startup.ipconfig | `asyn.AsynIPPort` entities in ioc.yaml |
| startup.*.db | `epics.StartupCommand` with dbLoadRecords |
| resource.def | `epics.EpicsEnvSet` entities |
| startup.security / ACF files | Volume mount or config file (see Security section) |
| startup.epicsgo (iocInit) | Automatic (ibek runs iocInit) |
| startup.*.init (sequencers, dbpf) | `epics.PostStartupCommand` entities |

### Process Management

| Traditional (procServ) | Containers (docker compose) |
|------------------------|----------------------------|
| `procServMgr start iocname` | `docker compose up -d iocname` |
| `procServMgr stop iocname` | `docker compose stop iocname` |
| `procServMgr status` | `docker compose ps` |
| `softioc_console iocname` | `docker attach iocname` |
| Port 20001, 20002, etc. | Container names |
| procServ auto-restart | `restart: unless-stopped` |
| Config file with all IOCs | `compose.yaml` per project |

### VDCT Workflow

VDCT continues to work as before, but the output goes into git:

```
Developer Workstation              Git Repository
┌─────────────────────┐           ┌─────────────────────────┐
│ Edit device.vdb     │           │ services/               │
│ in VisualDCT        │           │   ioc-vacuum-01/        │
│        │            │           │     config/             │
│        ▼            │           │       ioc.yaml          │
│ make (flatdb, etc.) │           │       device.db ◄───────┼── Committed
│        │            │  commit   │     vdct/               │
│        ▼            │──────────►│       device.vdb ◄──────┼── Source committed
│ device.db           │           │       device.rules      │
└─────────────────────┘           │       Makefile          │
                                  └─────────────────────────┘
```

Both the `.vdb` source AND the `.db` output can be version controlled. The container only needs the `.db` file at runtime.

---

## Network Architecture

### Option 1: Isolated Network with Gateways (Development)

Best for developer workstations where you want isolation between projects:

```
┌─────────────────────────────────────────────────────────────────┐
│                     Container Host                               │
│                                                                  │
│   Host Network                                                   │
│   ├── localhost:5064  ◄──── CA Gateway published port           │
│   └── localhost:5075  ◄──── PVA Gateway published port          │
│                                                                  │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │           Docker Network: channel_access                 │   │
│   │                  (isolated subnet)                       │   │
│   │                                                          │   │
│   │  ┌──────────┐  ┌──────────┐  ┌──────────┐              │   │
│   │  │  IOC 1   │  │  IOC 2   │  │  IOC N   │              │   │
│   │  └────┬─────┘  └────┬─────┘  └────┬─────┘              │   │
│   │       └─────────────┼─────────────┘                      │   │
│   │                     │                                    │   │
│   │              ┌──────┴──────┐                             │   │
│   │              │ CA Gateway  │                             │   │
│   │              │ PVA Gateway │                             │   │
│   │              └─────────────┘                             │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│   Clients: EPICS_CA_ADDR_LIST=127.0.0.1:5064                    │
└─────────────────────────────────────────────────────────────────┘
```

### Option 2: Host Network (Production)

Best for production servers - matches traditional procServ behavior:

```yaml
# In include/ioc.yml
services:
  linux_ioc: &linux_ioc
    network_mode: host        # Use host network directly
```

```
┌─────────────────────────────────────────────────────────────────┐
│                Production Server (e.g., ioc-server-01)           │
│                     IP: 10.0.5.100                               │
│                                                                  │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐             │
│  │ Container A  │ │ Container B  │ │ Container C  │             │
│  │ IOC A        │ │ IOC B        │ │ IOC C        │             │
│  └──────────────┘ └──────────────┘ └──────────────┘             │
│         │               │               │                        │
│         └───────────────┼───────────────┘                        │
│                         │                                        │
│              Host Network Interface                              │
│              (all IOCs broadcast on host IP:5064)                │
└─────────────────────────┼────────────────────────────────────────┘
                          │
                          ▼
                   Facility Network
                   CA Nameserver sees all IOCs
                   (exactly like procServ today)
```

**No gateways needed. No special subnets. IOCs behave exactly like traditional procServ IOCs.**

### When to Use Which

| Scenario | Network Mode |
|----------|--------------|
| Developer workstation (Mac/laptop) | Isolated + gateways |
| Testing multiple projects on one machine | Isolated + gateways |
| Production server | Host network |
| Integration with existing CA nameserver | Host network |

---

## Security Files (ACF)

### Volume Mount Approach (Recommended)

Mount your central security file location into containers:

```yaml
# In include/ioc.yml
services:
  linux_ioc: &linux_ioc
    volumes:
      # Mount central ACF directory read-only
      - /path/to/acf_directory:/epics/acf:ro
```

In `ioc.yaml`:
```yaml
entities:
  - type: epics.StartupCommand
    command: |
      asSetFilename("/epics/acf/secure/myioc.acf")
```

### Refreshing Security (asInit)

After updating central ACF files:

```bash
#!/bin/bash
# refresh-security.sh

# Run asInit on all IOC containers
for container in $(docker ps --filter "label=is_ioc=true" --format "{{.Names}}"); do
    echo "Running asInit on $container"
    docker exec $container bash -c 'caput ${IOC_NAME}:asInit 1' 2>/dev/null || \
    echo "  (no asInit PV or container not responding)"
done
```

### Alternative: Config Folder

Put ACF files in the IOC's config folder:
```
services/ioc-vacuum-01/
└── config/
    ├── ioc.yaml
    ├── device.db
    └── ioc-vacuum-01.acf
```

**Pro:** Version controlled with IOC config
**Con:** Must commit + restart to update

---

## Directory Structure

### Services Repository (per beamline/area)

```
bl01-services/                       # Git repository
├── .env                             # Ports, subnets
├── compose.yaml                     # Main orchestrator
├── environment.sh                   # Shell setup for development
│
├── include/                         # Shared configuration
│   ├── ioc.yml                      # Base IOC service template
│   └── networks.yml                 # Docker network config
│
├── opi/                             # Operator interfaces
│   ├── *.bob                        # Phoebus screens
│   └── *.edl                        # EDM screens (if used)
│
└── services/                        # One folder per IOC
    ├── ioc-vacuum-01/
    │   ├── compose.yml              # Container config
    │   ├── config/
    │   │   ├── ioc.yaml             # IOC configuration
    │   │   ├── device.db            # Database files
    │   │   └── protocols/           # StreamDevice protocols
    │   └── vdct/                    # VDCT source (optional)
    │       ├── device.vdb
    │       └── Makefile
    │
    ├── gateway/                     # CA Gateway (dev only)
    └── pvagw/                       # PVA Gateway (dev only)
```

### Generic IOC Repository (per device type or capability)

```
ioc-streamdevice/                    # Git repository
├── Dockerfile                       # Build recipe
├── ibek-support/                    # Git submodule
│   ├── asyn/
│   │   ├── install.sh              # Build script
│   │   └── asyn.ibek.support.yaml  # ibek definitions
│   └── StreamDevice/
└── ioc/                             # IOC source (minimal)
```

For device-specific Generic IOCs with custom code:

```
ioc-custom-device/
├── Dockerfile
├── ibek-support/
└── src/                             # Custom code
    ├── CustomDriver.c               # Device support
    ├── CustomSeq.stt                # Sequencer
    └── customInclude.dbd            # DBD file
```

---

## Comparison Summary

| Aspect | Traditional | Containers |
|--------|-------------|------------|
| **EPICS base** | Shared filesystem | Inside container image |
| **Support modules** | Shared filesystem | Inside container image |
| **IOC binary** | Compiled on shared filesystem | Inside container image |
| **Version selection** | Config file + symlinks | Container image tag |
| **Boot directory** | Filesystem (often not versioned) | Git repository |
| **Startup script** | Hand-edited file | `ioc.yaml` (declarative) |
| **Device config (IPs, ports)** | Hand-edited file | Part of `ioc.yaml` |
| **Database files** | Symlinked from app | In `config/` folder |
| **VDCT source** | In app (CVS/SVN) | In IOC instance or Generic IOC (Git) |
| **Process manager** | procServ | docker compose |
| **Console access** | telnet / softioc_console | docker attach |
| **Version history** | Apps versioned, boot dirs not | Everything in Git |
| **Rollback** | Restore dated config, re-symlink | `git checkout && docker compose up` |
| **Security files (ACF)** | Symlinked from central location | Volume mount from central location |

---

## Benefits

1. **Complete version control** - Every file that affects IOC behavior is in git
2. **Reproducibility** - Container images are immutable; same image = same behavior
3. **Isolation** - Each container has its own filesystem; no shared library conflicts
4. **Simplified deployment** - No compilation on target; pull image and run
5. **Audit trail** - Git history shows who changed what, when, and why
6. **Easy rollback** - `git checkout` + restart = previous state
7. **Vanilla EPICS** - Use upstream modules without facility-specific patches

## Tradeoffs

1. **Learning curve** - New tools (Docker/Podman, compose, ibek, git)
2. **Build infrastructure** - Need CI/CD to build container images
3. **Image management** - Container registry, image sizes, cleanup
4. **Debugging** - Must exec into containers; different mental model
5. **Tool integration** - VDCT, other facility tools may need workflow adjustment

---

## Migration Decision Tree

```
Do you need to containerize an existing IOC?
│
├─► Does it use only standard support modules?
│   │
│   ├─► YES: Use an existing Generic IOC image
│   │        Just create IOC instance config
│   │
│   └─► NO: Does it have custom device support or sequencers?
│       │
│       ├─► YES: Create a new Generic IOC for this device type
│       │        Port the custom code into the container build
│       │
│       └─► NO: What's non-standard about it?
│                (Evaluate case-by-case)
│
└─► Is this a new IOC?
    │
    └─► Start with Generic IOC approach from the beginning
        Choose appropriate base image for your needs
```

---

## Next Steps for Adoption

1. **Learn the basics** - Work through tutorials with simple IOCs
2. **Identify Generic IOC types** - What categories of IOCs do you have?
3. **Pick a pilot** - Choose one simple IOC to containerize first
4. **Build infrastructure** - Set up CI/CD, container registry
5. **Document your Generic IOCs** - What support modules each contains
6. **Migrate incrementally** - New IOCs containerized; old IOCs migrated as touched
7. **Evolve tooling** - Integrate VDCT, security management, other facility tools
