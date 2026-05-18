# Opsitron Modules

Vetted OpenTofu/Terraform modules for [Opsitron](https://opsitron.com) clients.

## Usage

Reference modules from client config repositories:

```hcl
module "website" {
  source = "github.com/ordinaryexperts/opsitron-modules//modules/static-website?ref=static-website-v1.3.0"

  name            = "my-app"
  environment     = "prod1"
  domain          = "www.example.com"
  certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc123"
}
```

## Available Modules

| Module | Category | Description |
|--------|----------|-------------|
| [artifact-bucket](./modules/artifact-bucket) | Storage | S3 bucket for build artifacts with cross-account access |
| [ecr-repository](./modules/ecr-repository) | Storage | ECR repository with cross-account pull and lifecycle cleanup |
| [ecs-webapp](./modules/ecs-webapp) | Compute | ECS Fargate app with ALB, optional RDS, Redis, S3, worker, SES |
| [lza-foundation](./modules/lza-foundation) | Landing Zone | AWS Landing Zone Accelerator foundation and Opsitron integration |
| [shared-services](./modules/shared-services) | Storage | Combined ECR + artifact bucket for SharedServices account |
| [static-website](./modules/static-website) | Compute | S3 + CloudFront static website with OAC and custom domains |

Each module includes:
- `README.md` - Usage documentation and examples
- `CHANGELOG.md` - Version history
- `module.json` - Module metadata (synced to Opsitron)
- `variables.tf` - Input variables with descriptions
- `outputs.tf` - Output values
- `main.tf` - Resource definitions
- `versions.tf` - Provider version constraints

## module.json

Each module has a `module.json` that defines metadata synced to Opsitron for the module catalog and AI agent context:

```json
{
  "display_name": "Static Website",
  "description": "S3 + CloudFront static website with Origin Access Control",
  "category": "compute",
  "deployment_type": "s3_artifact",
  "well_architected": ["security", "performance_efficiency", "cost_optimization"],
  "features": ["cloudfront", "oac", "custom_domain", "https", "spa_support"]
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `display_name` | Yes | Human-readable name |
| `description` | Yes | One-line description of what the module does |
| `category` | Yes | One of: `storage`, `networking`, `compute`, `security`, `database`, `observability`, `iam`, `landing_zone`, `application` |
| `deployment_type` | No | `"container"` or `"s3_artifact"` if the module supports app code deployment |
| `stop_strategy` | No | How the module participates in Opsitron's environment stop/start feature. One of `"scale_to_zero"` (module exposes an `enabled` variable that drops costed compute to zero), `"aws_native_stop"` (module uses an AWS native stop API, e.g. `StopDBCluster`), `"always_on"` (no meaningful stop savings — leave running), or `"not_applicable"` (module is foundational and must never be stopped). Defaults to `"not_applicable"` when omitted. |
| `well_architected` | No | AWS Well-Architected pillars this module addresses |
| `features` | No | List of features/capabilities for AI agent context |

## Versioning

Modules are versioned independently using git tags following [Semantic Versioning](https://semver.org/):

```
<module-name>-v<major>.<minor>.<patch>
```

Examples:
- `static-website-v1.3.0`
- `ecs-webapp-v2.0.0`
- `shared-services-v1.1.0`

### Version Guidelines

- **Major (v2.0.0)**: Breaking changes - removed variables, renamed outputs, changed behavior
- **Minor (v1.1.0)**: New features - added variables, new resources, backwards compatible
- **Patch (v1.0.1)**: Bug fixes - no interface changes

## Development

This repository uses **trunk-based development**:

```
main           <-- trunk (always deployable)
  ^
feature/*      <-- short-lived feature branches
  |
  +-- tags     <-- module-name-v1.0.0 (release points)
```

### Workflow

1. **Create a feature branch from main:**
   ```bash
   git checkout main
   git pull origin main
   git checkout -b feature/my-change
   ```

2. **Make your changes and push:**
   ```bash
   # ... make changes ...
   git add .
   git commit -m "feat: add new capability"
   git push -u origin feature/my-change
   ```

3. **Open PR to main and merge after review**

4. **Tag a release when ready:**
   ```bash
   git checkout main
   git pull origin main
   git tag -a "static-website-v1.4.0" -m "static-website v1.4.0: Add WAF support"
   git push origin "static-website-v1.4.0"
   ```

   This triggers the release workflow which notifies Opsitron to update the module catalog.

**Key principles:**
- Keep feature branches short-lived (hours to days, not weeks)
- Merge to main frequently
- Main should always be deployable
- Dev environments track main directly
- Staging/prod environments use versioned tags

### Module Standards

All modules must include:

- [ ] `README.md` with usage example
- [ ] `CHANGELOG.md` with version history
- [ ] `module.json` with metadata (including `stop_strategy`)
- [ ] All variables have `description` and `type`
- [ ] All outputs have `description`
- [ ] `versions.tf` with provider constraints
- [ ] Pass `tofu fmt` and `tofu validate`

### Power state (`enabled` variable)

Every compute-bearing module must accept a boolean `enabled` variable (default `true`) and declare `stop_strategy: "scale_to_zero"` in its `module.json`. When `enabled = false`, the module **must**:

- Scale all costed compute to zero — ECS `desired_count`, ASG capacity, Lambda provisioned concurrency, Aurora Serverless ACU floor, etc.
- Preserve all data resources — never destroy or stop RDS instances, EFS file systems, ElastiCache clusters, S3 buckets, ECR repositories, KMS keys, or secrets. They must remain declared in state so a toggle back to `enabled = true` restores the environment on the same apply.

Modules that have no meaningful idle cost (e.g. CloudFront, S3-only buckets, ECR) declare `stop_strategy: "always_on"` and do not need an `enabled` variable. Foundational modules that must never be stopped (e.g. LZA) declare `stop_strategy: "not_applicable"`.

## License

Apache License 2.0 - See [LICENSE](./LICENSE)
