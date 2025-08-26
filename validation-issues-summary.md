# Validation Issues Summary

## Classification of Current Validation Failures

### 1. YAML Check Failures (3 files)
**Issue**: Inline volume arrays with unquoted paths containing colons
**Root Cause**: yamlfix converted to inline format but didn't quote strings with colons

**Affected Files**:
- `dockermaster/docker/compose/ansible-observability/docker-compose.yml`
- `dockermaster/docker/compose/n8n-stack/docker-compose.yml`
- `dockermaster/docker/compose/nginx-rproxy/docker-compose.yml`

**Example Issue**:
```yaml
# Current (incorrect):
volumes: [/var/run/docker.sock:/docker.sock]

# Should be:
volumes: ["/var/run/docker.sock:/docker.sock"]
# Or:
volumes:
  - "/var/run/docker.sock:/docker.sock"
```

### 2. Markdownlint Failures (10+ files)
**Issues**:
- MD040: Fenced code blocks missing language specification
- MD031: Fenced code blocks not surrounded by blank lines  
- MD013: Line length violations (>120 chars)
- MD051: Invalid link fragments

**Most Affected Files**:
- `CLAUDE.md` - missing code block languages and blank lines
- `CLAUDE_proposed.md` - missing code block language
- `COMMIT_CONVENTIONS.md` - line too long, missing code language
- `CONTRIBUTING.md` - multiple link fragment issues, long lines

### 3. Shellcheck Warnings
**Issues**:
- SC2155: Declare and assign separately to avoid masking return values
- SC2250: Prefer braces around variable references

**Note**: These are warnings/style issues, not errors. The .shellcheckrc config is NOT being used by CI/CD.

### 4. Dockerfile Linting Warnings
**Issues**:
- DL3007: Using 'latest' tag is prone to errors
- DL3027: Use apt-get instead of apt

**Affected File**:
- `dockermaster/docker/compose/calibre-server/Dockerfile`

## Configuration File Status

### ✅ Config Files Present and Used:
- `.yamllint.yml` - Used by CI/CD
- `.markdownlint.json` - Used by CI/CD
- `.editorconfig` - Used by shfmt locally
- `.commitlintrc.json` - Used by git hooks
- `.pre-commit-config.yaml` - Used by pre-commit

### ⚠️ Config Files Present but NOT Used by CI/CD:
- `.shellcheckrc` - CI/CD uses hardcoded excludes instead
- `.editorconfig` - shfmt not in CI/CD pipeline

## Priority Actions

1. **Critical**: Fix YAML volume syntax (prevents validation)
2. **Critical**: Update CI/CD to use .shellcheckrc
3. **Important**: Fix Markdown code block languages
4. **Nice to have**: Fix shellcheck style warnings
5. **Nice to have**: Fix Dockerfile warnings

## CI/CD Configuration Updates Needed

In `.github/workflows/pr-validation.yml`:
- Change shellcheck to use `.shellcheckrc` config file
- Consider adding shfmt to the pipeline
