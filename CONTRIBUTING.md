# Contributing to Leap Deploy

## Schema Versioning Strategy

This project uses semantic versioning for JSON schemas with an in-document `version` field to ensure compatibility between schema definitions and configuration files.

### Directory Structure

```
v1/
  └── leap-deploy.schema.json  (accepts version: 1.x.x)
v2/
  └── leap-deploy.schema.json  (accepts version: 2.x.x, when created)
examples/
  └── leap-deploy.yaml
```

## Development Workflow

### Adding Non-Breaking Changes (v1.x.x)

When adding **optional fields** or **backward-compatible** changes:

1. **Make changes** to `schemas/v1/leap-deploy.schema.json`
   - Add new optional properties
   - Expand enums with new values
   - Add new definitions

2. **Update examples** in `examples/leap-deploy.yaml` if needed

3. **Create PR** to `main` branch
   - No need to update version patterns in the schema
   - The pattern `^1(\\.[0-9]+){0,2}$` automatically accepts all v1.x.x versions

4. **Merge PR** → CI automatically:
   - Bumps version to next minor/patch (e.g., `v1.2.0`)
   - Creates GitHub release with artifacts:
     - `leap-deploy.v1.schema.json`
     - (Future: `leap-deploy.v2.json` once v2 exists)

### Introducing Breaking Changes (v2.x.x)

When making **breaking changes** that are not backward compatible:

1. **Create v2 directory structure**
   ```bash
   mkdir -p v2
   cp schemas/v1/leap-deploy.schema.json schemas/v2/leap-deploy.schema.json
   ```

2. **Update v2 schema**
   - Change `$id` to: `https://schemas.workleap.com/leap-deploy/v2/schema.json`
   - Update version pattern: `"pattern": "^2(\\.[0-9]+){0,2}$"`
   - Update description: `"Schema version - must be a v2 version (e.g., 2, 2.0, 2.0.0)"`
   - Make your breaking changes

3. **Update CI/CD workflow** to include both schemas as artifacts:
   - Copy `schemas/v1/leap-deploy.schema.json` → `leap-deploy.v1.schema.json`
   - Copy `v2/leap-deploy.schema.json` → `leap-deploy.v2.json`
   - Attach both to every release going forward

4. **Create PR** to `main` with v2 changes

5. **Merge PR** → CI creates release `v2.0.0` with both schema artifacts

### Maintaining v1 After v2 Ships

For critical bug fixes or security updates to v1:

**Option 1: Main branch with both versions**
- Keep both `v1/` and `v2/` in main
- PRs update the appropriate directory
- Releases include both artifacts

**Option 2: Long-lived v1 branch (if separate maintenance needed)**
- Create `v1` maintenance branch
- PRs to `v1` branch for v1-only fixes
- Releases from `v1` branch tagged as `v1.x.x`
- Main branch continues with v2 development

## Schema Access URLs

Consumers access schemas via GitHub release artifacts (works within private org repos without authentication):

```yaml
# Latest v1 schema
https://github.com/workleap/wl-leap-deploy/releases/latest/download/leap-deploy.v1.schema.json

# Latest v2 schema (when available)
https://github.com/workleap/wl-leap-deploy/releases/latest/download/leap-deploy.v2.json
```

## Configuration File Format

Users must specify the `version` field in their `leap-deploy.yaml`:

```yaml
version: "1.0.0"  # or "1.0" or "1"
id: my-deployment
workloads:
  api-service:
    type: api
    # ...
```

## Version Compatibility Rules

- **v1.x.x**: All backward-compatible with v1.0.0
- **v2.x.x**: Breaking changes from v1, but v2.x.x versions are backward-compatible with v2.0.0
- Tools should read the `version` field to determine which parser/validator to use

## Testing Changes

Before submitting a PR:

1. **Validate schema syntax**
   ```bash
   # Use JSON schema validator
   jsonschema --check schemas/v1/leap-deploy.schema.json
   ```

2. **Test with example files**
   ```bash
   # Validate examples against schema
   jsonschema -i examples/leap-deploy.yaml schemas/v1/leap-deploy.schema.json
   ```

3. **Ensure backward compatibility** for minor/patch versions
   - Test that old configuration files still validate
   - Verify new optional fields don't break existing configs

## Release Process

Releases are automated via CI/CD when PRs are merged to `main`:

1. CI detects changes to schema files
2. Bumps version according to conventional commits or manual trigger
3. Creates GitHub release with tag (e.g., `v1.2.0`)
4. Attaches schema artifacts:
   - `leap-deploy.v1.schema.json`
   - `leap-deploy.v2.json` (when v2 exists)
5. Updates release notes with changes

