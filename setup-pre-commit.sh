#!/bin/bash
# Setup script for pre-commit hooks in home-lab-inventory repository
# This script installs and configures all necessary tools for code quality enforcement

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect package manager
detect_package_manager() {
    if command_exists brew; then
        echo "brew"
    elif command_exists apt-get; then
        echo "apt"
    elif command_exists yum; then
        echo "yum"
    elif command_exists dnf; then
        echo "dnf"
    elif command_exists zypper; then
        echo "zypper"
    elif command_exists pacman; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

# Function to install pre-commit
install_pre_commit() {
    print_status "Installing pre-commit..."

    if command_exists pip3; then
        pip3 install --user pre-commit
    elif command_exists pip; then
        pip install --user pre-commit
    elif command_exists brew; then
        brew install pre-commit
    else
        print_error "Cannot install pre-commit. Please install pip or brew first."
        exit 1
    fi

    print_success "pre-commit installed successfully"
}

# Function to install additional tools
install_additional_tools() {
    local pkg_manager=$(detect_package_manager)

    print_status "Installing additional linting tools..."

    case "$pkg_manager" in
        "brew")
            # macOS with Homebrew
            if ! command_exists actionlint; then
                print_status "Installing actionlint..."
                brew install actionlint
            fi
            if ! command_exists hadolint; then
                print_status "Installing hadolint..."
                brew install hadolint
            fi
            if ! command_exists shellcheck; then
                print_status "Installing shellcheck..."
                brew install shellcheck
            fi
            ;;
        "apt")
            # Debian/Ubuntu
            sudo apt-get update
            if ! command_exists shellcheck; then
                print_status "Installing shellcheck..."
                sudo apt-get install -y shellcheck
            fi
            # actionlint and hadolint need to be installed manually on Ubuntu
            install_actionlint_manual
            install_hadolint_manual
            ;;
        "yum"|"dnf")
            # RHEL/CentOS/Fedora
            if ! command_exists shellcheck; then
                print_status "Installing shellcheck..."
                if [ "$pkg_manager" = "dnf" ]; then
                    sudo dnf install -y ShellCheck
                else
                    sudo yum install -y ShellCheck
                fi
            fi
            install_actionlint_manual
            install_hadolint_manual
            ;;
        *)
            print_warning "Unknown package manager. Some tools may need manual installation."
            install_actionlint_manual
            install_hadolint_manual
            ;;
    esac
}

# Function to manually install actionlint
install_actionlint_manual() {
    if ! command_exists actionlint; then
        print_status "Installing actionlint manually..."
        local os=$(uname -s | tr '[:upper:]' '[:lower:]')
        local arch=$(uname -m)

        case "$arch" in
            x86_64) arch="amd64" ;;
            arm64|aarch64) arch="arm64" ;;
            *)
                print_warning "Unsupported architecture: $arch. Skipping actionlint installation."
                return
                ;;
        esac

        local download_url="https://github.com/rhymond/actionlint/releases/latest/download/actionlint_1.6.26_${os}_${arch}.tar.gz"
        local temp_dir=$(mktemp -d)

        if curl -sL "$download_url" | tar xz -C "$temp_dir"; then
            sudo mv "$temp_dir/actionlint" /usr/local/bin/
            chmod +x /usr/local/bin/actionlint
            print_success "actionlint installed successfully"
        else
            print_warning "Failed to install actionlint. You may need to install it manually."
        fi

        rm -rf "$temp_dir"
    fi
}

# Function to manually install hadolint
install_hadolint_manual() {
    if ! command_exists hadolint; then
        print_status "Installing hadolint manually..."
        local os=$(uname -s)
        local arch=$(uname -m)

        case "$os" in
            Linux)
                case "$arch" in
                    x86_64) binary="hadolint-Linux-x86_64" ;;
                    *)
                        print_warning "Unsupported architecture: $arch. Skipping hadolint installation."
                        return
                        ;;
                esac
                ;;
            Darwin)
                binary="hadolint-Darwin-x86_64"
                ;;
            *)
                print_warning "Unsupported OS: $os. Skipping hadolint installation."
                return
                ;;
        esac

        local download_url="https://github.com/hadolint/hadolint/releases/latest/download/$binary"

        if curl -sL "$download_url" -o /tmp/hadolint; then
            sudo mv /tmp/hadolint /usr/local/bin/hadolint
            chmod +x /usr/local/bin/hadolint
            print_success "hadolint installed successfully"
        else
            print_warning "Failed to install hadolint. You may need to install it manually."
        fi
    fi
}

# Function to check Docker installation
check_docker() {
    if ! command_exists docker; then
        print_warning "Docker is not installed. Docker Compose validation will be skipped."
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        print_warning "Docker daemon is not running. Docker Compose validation may fail."
        return 1
    fi

    print_success "Docker is available and running"
    return 0
}

# Main installation function
main() {
    print_status "Setting up pre-commit hooks for home-lab-inventory repository"
    echo

    # Check if we're in the right directory
    if [ ! -f ".pre-commit-config.yaml" ]; then
        print_error "This script must be run from the repository root directory"
        exit 1
    fi

    # Install pre-commit if not already installed
    if ! command_exists pre-commit; then
        install_pre_commit
    else
        print_success "pre-commit is already installed"
    fi

    # Install additional tools
    install_additional_tools

    # Check Docker (optional)
    check_docker || true

    # Install pre-commit hooks
    print_status "Installing pre-commit hooks..."
    pre-commit install

    # Install hooks for commit messages (optional)
    if [ -f ".gitmessage" ] || [ -f ".gitmessage.txt" ]; then
        pre-commit install --hook-type commit-msg
    fi

    # Run pre-commit on all files to test the setup
    print_status "Running pre-commit on all files to test the setup..."
    if pre-commit run --all-files; then
        print_success "All pre-commit hooks passed!"
    else
        print_warning "Some pre-commit hooks failed. This is normal for the first run."
        print_status "You can fix the issues and run 'pre-commit run --all-files' again."
    fi

    echo
    print_success "Pre-commit setup completed successfully!"
    echo
    echo "Available commands:"
    echo "  pre-commit run --all-files    # Run all hooks on all files"
    echo "  pre-commit run <hook-name>    # Run specific hook"
    echo "  pre-commit autoupdate         # Update hook versions"
    echo "  pre-commit clean              # Clean cached environments"
    echo
    echo "The hooks will now run automatically on every commit."
    echo "To skip hooks temporarily, use: git commit -m 'message' --no-verify"
}

# Run main function
main "$@"
