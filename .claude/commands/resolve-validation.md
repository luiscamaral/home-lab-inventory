# .claude/commands/resolve-validation

This command helps you automatically resolve commit and push validation issues by systematically applying auto-fixes from your project's validation tools, then guiding you through manual fixes when necessary.

## Usage

```bash
claude < .claude/commands/resolve-validation
```

## Purpose

Streamline the resolution of validation errors that block commits and pushes by:
1. First attempting all available automatic fixes
2. Creating restoration points before manual changes
3. Iteratively resolving remaining issues with user approval
4. Ensuring all validations pass before completing

## Interactive Process

When you run this command, I will:

1. **Check current status** - Identify what's blocking your commit/push
2. **Detect merge conflicts** - Abort if conflicts exist (manual resolution required)
3. **Check remote sync** - Abort if pull needed (manual sync required)
4. **Apply auto-fixes** - Run all tools with their auto-fix capabilities
5. **Test validation** - Check if auto-fixes resolved all issues
6. **Handle remaining issues** - For each unresolved issue:
   - Present the specific problem
   - Suggest 2 solution options
   - Create a restoration point
   - Apply approved fix
   - Re-validate
7. **Complete commit/push** - Once all validations pass

## Process Flow

### Phase 1: Initial Assessment

I'll first check:
- Current git status and staged changes
- Whether we're blocked by commit or push validation
- Check for merge conflicts (abort if found)
- Check if branch needs updating from remote (abort if needed)

### Phase 2: Automatic Fixes

I'll attempt these auto-fixes in order:

1. **Pre-commit auto-fixable hooks**:
   ```bash
   # These hooks auto-fix when possible:
   pre-commit run trailing-whitespace --all-files
   pre-commit run end-of-file-fixer --all-files
   pre-commit run mixed-line-ending --all-files
   pre-commit run pretty-format-json --all-files
   ```

2. **Markdown auto-formatting**:
   ```bash
   npx markdownlint --fix "**/*.md" --ignore .history --ignore node_modules
   ```

3. **Full pre-commit with auto-fix**:
   ```bash
   pre-commit run --all-files
   ```

After each auto-fix attempt, I'll check if the issues are resolved.

### Phase 3: Manual Resolution

For issues that can't be auto-fixed, I'll:

1. **Present the issue clearly**:
   - Show the exact validation error
   - Identify the file(s) affected
   - Explain why it can't be auto-fixed

2. **Offer solution options**:
   - Option A: Most common/recommended fix
   - Option B: Alternative approach
   - You can also suggest your own approach

3. **Create restoration point**:
   ```bash
   git stash push -m "validation-restore-point-$(date +%s)"
   ```

4. **Apply the fix** with your approval

5. **Re-validate** to ensure the fix worked

### Phase 4: Completion

Once all validations pass:
1. Stage any changes made by fixes
2. Attempt commit with your original message
3. Push to remote if requested

## Validation Tools Coverage

### Auto-fixable Issues

These will be resolved automatically:
- Trailing whitespace
- Missing end-of-file newlines
- Mixed line endings (converted to LF)
- JSON formatting
- Some Markdown formatting issues

### Manual Resolution Required

These require your input:
- YAML syntax errors
- Dockerfile best practice violations (hadolint)
- Shell script issues (shellcheck)
- Security issues (gitleaks)
- Commit message format errors
- Docker Compose validation errors
- GitHub Actions workflow syntax

## Abort Conditions

The command will stop and provide instructions if:

1. **Merge conflicts detected**:
   - Instructions on resolving conflicts
   - Command to resume after resolution

2. **Remote changes available**:
   - Instructions to pull changes
   - Command to resume after sync

3. **User cancellation**:
   - All changes preserved in stash
   - Instructions to restore if needed

## Example Session

```
Running resolve-validation command...

🔍 Phase 1: Initial Assessment
- Git status: Changes staged for commit
- Validation blocking: pre-commit hooks
- No merge conflicts ✓
- No remote updates needed ✓

🔧 Phase 2: Applying Auto-fixes
- Running trailing-whitespace fix... Fixed 3 files ✓
- Running end-of-file-fixer... Fixed 1 file ✓
- Running markdownlint fix... Fixed 2 files ✓
- Running full validation...

❌ Remaining issues found:

📝 Issue 1: YAML Syntax Error
File: .github/workflows/deploy.yml
Line: 45
Error: Incorrect indentation

Option A: Fix indentation to 2 spaces (recommended)
Option B: Restructure the workflow step

Your choice (A/B/custom)? A

Creating restoration point...
Applying fix...
Validating... ✓

✅ All validations passed!
Completing commit and push...
Success!
```

## Tips for Success

1. **Run regularly**: Use after making changes, before attempting commit
2. **Review auto-fixes**: Check `git diff` after auto-fixes to understand changes
3. **Learn patterns**: Note which issues occur frequently to avoid them
4. **Keep tools updated**: Ensure pre-commit hooks are current

## Related Commands

- `.claude/commands/validate-changes` - Check validation without fixing
- `.claude/commands/setup-validation` - Configure validation tools
- `.claude/commands/update-hooks` - Update pre-commit hooks

## Restoration

If something goes wrong, restore your work:
```bash
# List restoration points
git stash list | grep validation-restore

# Restore latest
git stash pop

# Restore specific point
git stash apply stash@{n}
```