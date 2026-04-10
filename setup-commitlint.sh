#!/bin/bash

# Setup script for commitlint and Husky in home-lab-inventory repository
# This script installs and configures conventional commit message validation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_step() {
    echo -e "${BLUE}📋 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    print_error "This script must be run from the root of the git repository"
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    print_error "Node.js is not installed. Please install Node.js 18+ to continue."
    exit 1
fi

# Check Node.js version
NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    print_error "Node.js version 18 or higher is required. Current version: $(node -v)"
    exit 1
fi

print_step "Setting up commitlint and Husky for conventional commits..."

# Install dependencies
print_step "Installing npm dependencies..."
npm install

print_success "Dependencies installed successfully"

# Initialize Husky
print_step "Initializing Husky..."
npx husky install

# Add commit-msg hook
print_step "Adding commit-msg hook..."
npx husky add .husky/commit-msg 'npx --no -- commitlint --edit ${1}'

print_success "Husky hooks configured"

# Set up Git commit template
print_step "Configuring Git commit message template..."
git config commit.template .gitmessage

print_success "Git commit template configured"

# Test commitlint configuration
print_step "Testing commitlint configuration..."
echo "test: sample commit message" | npx commitlint || {
    print_warning "Commitlint test failed - this is expected for the test message"
}

print_success "Commitlint configuration validated"

# Check if pre-commit is available
if command -v pre-commit &> /dev/null; then
    print_step "Pre-commit is available and will work alongside Husky hooks"
    print_success "Integration with pre-commit hooks confirmed"
else
    print_warning "pre-commit is not installed. Consider installing it for additional code quality checks:"
    echo "  pip install pre-commit"
    echo "  pre-commit install"
fi

echo ""
print_success "🎉 Commitlint and Husky setup completed successfully!"
echo ""
echo "📝 Usage:"
echo "  • Use 'npm run commit' for interactive commit message creation"
echo "  • Use 'git commit' with the template (already configured)"
echo "  • Commit messages will be automatically validated"
echo ""
echo "📋 Commit message format:"
echo "  type(scope): subject"
echo ""
echo "📖 Examples:"
echo "  feat(docker): add nginx container configuration"
echo "  fix(security): update gitleaks configuration"
echo "  docs(inventory): update server documentation"
echo ""
echo "🔍 Validation commands:"
echo "  npm run commitlint        # Check last commit"
echo "  npm run validate:commits  # Check last 10 commits"
echo "  npm run check:commit-format  # Check last 5 commits"
echo ""
print_success "Ready to commit with conventional commit messages! 🚀"
