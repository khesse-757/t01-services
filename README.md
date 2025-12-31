# t01-services

IOC instances and services for the t01 beamline/area.

## Quick Start

```bash
# Clone the repository
git clone https://github.com/khesse-757/t01-services.git
cd t01-services

# Apple Silicon Mac: set platform
export DOCKER_DEFAULT_PLATFORM=linux/amd64

# Start all services
docker compose up -d

# Check status
docker compose ps

# Access PVs from host
export EPICS_CA_ADDR_LIST=127.0.0.1:5064
export EPICS_CA_AUTO_ADDR_LIST=NO
caget EXAMPLE:SUM
```

## IOC Instances

| IOC | Image | Description | PVs |
|-----|-------|-------------|-----|
| example-test-01 | ioc-template-example-runtime:3.5.1 | Template example | EXAMPLE:A, EXAMPLE:B, EXAMPLE:SUM |
| t01-ea-calc-01 | ioc-template-example-runtime:3.5.1 | Scaling calculation demo | CALC:RAW, CALC:SCALED, etc. |
| t01-ea-autosave-01 | ioc-calc-autosave-runtime:0.1.0 | Autosave demonstration | DEMO:SETPOINT, DEMO:GAIN, etc. |

## Services

| Service | Purpose |
|---------|---------|
| ca-gateway | Channel Access gateway - aggregates IOC PVs |
| pvagw | PV Access gateway |
| phoebus | OPI display (requires X11) |

## Common Commands

```bash
# Start/stop all
docker compose up -d
docker compose down

# Manage individual IOCs
docker compose restart t01-ea-calc-01
docker compose stop t01-ea-calc-01
docker compose logs t01-ea-calc-01

# IOC console (detach: Ctrl-P Ctrl-Q)
docker attach t01-ea-calc-01

# Shell into container
docker exec -it t01-ea-calc-01 bash
```

## Adding a New IOC Instance

1. Copy existing IOC:
   ```bash
   cp -r services/example-test-01 services/my-new-ioc
   ```

2. Edit `services/my-new-ioc/compose.yml` - update all names

3. Edit `services/my-new-ioc/config/ioc.yaml` - configure IOC

4. Edit `services/my-new-ioc/config/ioc.db` - add records

5. Add to main `compose.yaml`:
   ```yaml
   include:
     - services/my-new-ioc/compose.yml
   ```

6. Deploy:
   ```bash
   docker compose up -d
   ```

## Apple Silicon Mac Notes

Add to `include/ioc.yml`:
```yaml
services:
  linux_ioc: &linux_ioc
    platform: linux/amd64
```

Set environment:
```bash
export DOCKER_DEFAULT_PLATFORM=linux/amd64
```

## Documentation

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - Conceptual overview, comparison to traditional EPICS
- [NOTES.md](docs/NOTES.md) - Practical reference, commands, troubleshooting
- [TUTORIAL.md](docs/TUTORIAL.md) - Step-by-step walkthrough

## Network Access

### Development Mode (Default)

IOCs run on isolated Docker network. Access through gateways:

```bash
export EPICS_CA_ADDR_LIST=127.0.0.1:5064
export EPICS_CA_AUTO_ADDR_LIST=NO
```

### Production Mode

Edit `include/ioc.yml` to use host networking:
```yaml
services:
  linux_ioc: &linux_ioc
    network_mode: host
```

## Repository Structure

```
t01-services/
├── compose.yaml              # Main orchestrator
├── .env                      # Ports, subnets
├── include/
│   ├── ioc.yml              # Base IOC definition
│   └── networks.yml         # Network configuration
├── services/
│   ├── example-test-01/     # IOC instance
│   ├── t01-ea-calc-01/      # IOC instance
│   ├── t01-ea-autosave-01/  # IOC instance (custom image)
│   ├── gateway/             # CA gateway
│   └── pvagw/               # PVA gateway
├── opi/                     # Operator displays
└── docs/                    # Documentation
```

## Links

- [epics-containers documentation](https://epics-containers.github.io/main/)
- [ioc-calc-autosave](https://github.com/khesse-757/ioc-calc-autosave) - Custom Generic IOC used by t01-ea-autosave-01