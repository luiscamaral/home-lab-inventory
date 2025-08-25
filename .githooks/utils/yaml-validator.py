#!/usr/bin/env python3
"""
YAML Validator - Git Hook Utility
Validates YAML files, with special attention to GitHub Actions workflows.

Usage:
    yaml-validator.py [options] <file1> [file2] ...
    yaml-validator.py --help

Options:
    -h, --help          Show this help message and exit
    -q, --quiet         Suppress informational output
    -v, --verbose       Show detailed validation information
    --github-actions    Enable GitHub Actions workflow validation
    --no-color          Disable colored output

Exit codes:
    0 - All files are valid
    1 - One or more files are invalid
    2 - Script usage error
"""

import argparse
import sys
import os
from pathlib import Path
import yaml
import re


class Colors:
    """ANSI color codes for terminal output."""
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'
    WHITE = '\033[97m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    END = '\033[0m'

    @classmethod
    def disable(cls):
        """Disable all colors."""
        cls.RED = cls.GREEN = cls.YELLOW = cls.BLUE = ''
        cls.MAGENTA = cls.CYAN = cls.WHITE = cls.BOLD = ''
        cls.UNDERLINE = cls.END = ''


class YAMLValidator:
    """YAML file validator with GitHub Actions workflow support."""

    def __init__(self, verbose=False, quiet=False, github_actions=False):
        self.verbose = verbose
        self.quiet = quiet
        self.github_actions = github_actions
        self.errors = []
        self.warnings = []

    def log_info(self, message):
        """Log informational message."""
        if not self.quiet:
            print(f"{Colors.CYAN}ℹ{Colors.END}  {message}")

    def log_success(self, message):
        """Log success message."""
        if not self.quiet:
            print(f"{Colors.GREEN}✓{Colors.END}  {message}")

    def log_warning(self, message):
        """Log warning message."""
        print(f"{Colors.YELLOW}⚠{Colors.END}  {message}")
        self.warnings.append(message)

    def log_error(self, message):
        """Log error message."""
        print(f"{Colors.RED}✗{Colors.END}  {message}")
        self.errors.append(message)

    def validate_yaml_syntax(self, file_path):
        """Validate basic YAML syntax."""
        try:
            with open(file_path, 'r', encoding='utf-8') as file:
                yaml.safe_load(file)
            return True
        except yaml.YAMLError as e:
            self.log_error(f"YAML syntax error in {file_path}: {e}")
            return False
        except UnicodeDecodeError as e:
            self.log_error(f"Encoding error in {file_path}: {e}")
            return False
        except Exception as e:
            self.log_error(f"Unexpected error reading {file_path}: {e}")
            return False

    def validate_github_actions_workflow(self, file_path, data):
        """Validate GitHub Actions workflow structure."""
        if not self.github_actions:
            return True

        valid = True

        # Check for required top-level keys
        required_keys = ['on']
        for key in required_keys:
            if key not in data:
                self.log_error(f"Missing required key '{key}' in {file_path}")
                valid = False

        # Check for at least one job
        if 'jobs' not in data:
            self.log_error(f"No 'jobs' section found in {file_path}")
            valid = False
        elif not data['jobs']:
            self.log_error(f"Empty 'jobs' section in {file_path}")
            valid = False

        # Validate job structure
        if 'jobs' in data and isinstance(data['jobs'], dict):
            for job_name, job_config in data['jobs'].items():
                if not isinstance(job_config, dict):
                    self.log_error(f"Job '{job_name}' configuration must be an object in {file_path}")
                    valid = False
                    continue

                # Check for runs-on
                if 'runs-on' not in job_config:
                    self.log_error(f"Job '{job_name}' missing 'runs-on' in {file_path}")
                    valid = False

                # Validate steps
                if 'steps' in job_config:
                    if not isinstance(job_config['steps'], list):
                        self.log_error(f"Job '{job_name}' steps must be an array in {file_path}")
                        valid = False
                    elif not job_config['steps']:
                        self.log_warning(f"Job '{job_name}' has empty steps array in {file_path}")

        # Check for common issues
        if 'on' in data:
            on_config = data['on']
            if isinstance(on_config, dict):
                # Check for schedule format
                if 'schedule' in on_config:
                    schedule = on_config['schedule']
                    if isinstance(schedule, list):
                        for idx, item in enumerate(schedule):
                            if 'cron' in item:
                                cron = item['cron']
                                if not self._validate_cron_syntax(cron):
                                    self.log_warning(f"Invalid cron syntax '{cron}' in schedule[{idx}] in {file_path}")

        return valid

    def _validate_cron_syntax(self, cron_expr):
        """Basic cron syntax validation."""
        # Simple validation for 5-field cron expressions
        parts = cron_expr.strip().split()
        if len(parts) != 5:
            return False

        # Basic pattern check (not comprehensive)
        cron_pattern = r'^[0-9\*\-\,\/]+$'
        return all(re.match(cron_pattern, part) or part == '*' for part in parts)

    def is_github_actions_file(self, file_path):
        """Check if file is a GitHub Actions workflow."""
        path = Path(file_path)
        return (
            '.github/workflows' in str(path) and
            path.suffix in ['.yml', '.yaml']
        )

    def validate_file(self, file_path):
        """Validate a single YAML file."""
        if not os.path.isfile(file_path):
            self.log_error(f"File not found: {file_path}")
            return False

        self.log_info(f"Validating {file_path}")

        # Basic YAML syntax validation
        if not self.validate_yaml_syntax(file_path):
            return False

        # Load YAML data for additional checks
        try:
            with open(file_path, 'r', encoding='utf-8') as file:
                data = yaml.safe_load(file)
        except Exception as e:
            self.log_error(f"Failed to load YAML data from {file_path}: {e}")
            return False

        # GitHub Actions specific validation
        if self.is_github_actions_file(file_path) or self.github_actions:
            if not self.validate_github_actions_workflow(file_path, data):
                return False

        self.log_success(f"Valid: {file_path}")
        return True

    def validate_files(self, file_paths):
        """Validate multiple YAML files."""
        if not file_paths:
            self.log_error("No files provided for validation")
            return False

        all_valid = True

        for file_path in file_paths:
            if not self.validate_file(file_path):
                all_valid = False

        return all_valid

    def print_summary(self):
        """Print validation summary."""
        if not self.quiet:
            print(f"\n{Colors.BOLD}Validation Summary:{Colors.END}")
            print(f"  Errors: {Colors.RED}{len(self.errors)}{Colors.END}")
            print(f"  Warnings: {Colors.YELLOW}{len(self.warnings)}{Colors.END}")

            if self.verbose and (self.errors or self.warnings):
                print(f"\n{Colors.BOLD}Details:{Colors.END}")
                for error in self.errors:
                    print(f"  {Colors.RED}Error:{Colors.END} {error}")
                for warning in self.warnings:
                    print(f"  {Colors.YELLOW}Warning:{Colors.END} {warning}")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Validate YAML files, with special support for GitHub Actions workflows",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s workflow.yml
  %(prog)s --github-actions .github/workflows/*.yml
  %(prog)s --verbose --no-color file1.yaml file2.yml
        """
    )

    parser.add_argument('files', nargs='*', help='YAML files to validate')
    parser.add_argument('-q', '--quiet', action='store_true',
                       help='Suppress informational output')
    parser.add_argument('-v', '--verbose', action='store_true',
                       help='Show detailed validation information')
    parser.add_argument('--github-actions', action='store_true',
                       help='Enable GitHub Actions workflow validation')
    parser.add_argument('--no-color', action='store_true',
                       help='Disable colored output')

    args = parser.parse_args()

    # Handle help and usage
    if not args.files:
        parser.print_help()
        return 2

    # Disable colors if requested or not in TTY
    if args.no_color or not sys.stdout.isatty():
        Colors.disable()

    # Create validator instance
    validator = YAMLValidator(
        verbose=args.verbose,
        quiet=args.quiet,
        github_actions=args.github_actions
    )

    # Validate files
    success = validator.validate_files(args.files)

    # Print summary
    validator.print_summary()

    # Return appropriate exit code
    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main())
