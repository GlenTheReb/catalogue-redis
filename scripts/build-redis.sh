#!/bin/bash
set -e

# Build script for catalogue-redis service
# This script builds the Docker image and optionally pushes to a registry

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
IMAGE_NAME="catalogue-redis"
IMAGE_TAG="latest"
PUSH_TO_REGISTRY="false"
REGISTRY=""

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

# Function to show usage
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Build the catalogue-redis Docker image

OPTIONS:
    -n, --name NAME        Image name (default: catalogue-redis)
    -t, --tag TAG          Image tag (default: latest)
    -r, --registry REGISTRY Registry to push to (e.g., docker.io/username)
    -p, --push             Push image to registry after build
    -h, --help             Show this help message

EXAMPLES:
    # Build local image
    $0

    # Build with custom name and tag
    $0 --name my-catalogue --tag v1.0.0

    # Build and push to Docker Hub
    $0 --registry docker.io/myusername --push

    # Build and push to private registry
    $0 --registry myregistry.com/myproject --tag v1.2.3 --push

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -t|--tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -r|--registry)
            REGISTRY="$2"
            shift 2
            ;;
        -p|--push)
            PUSH_TO_REGISTRY="true"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Determine full image name
if [ -n "$REGISTRY" ]; then
    FULL_IMAGE_NAME="$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
else
    FULL_IMAGE_NAME="$IMAGE_NAME:$IMAGE_TAG"
fi

print_status "Starting build process..."
print_status "Project root: $PROJECT_ROOT"
print_status "Image name: $FULL_IMAGE_NAME"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed or not in PATH"
    exit 1
fi

# Check if we're in the right directory
if [ ! -f "$PROJECT_ROOT/go.mod" ]; then
    print_error "go.mod not found. Please run this script from the project root or scripts directory."
    exit 1
fi

# Build arguments for Docker
BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
BUILD_VERSION="${IMAGE_TAG}"
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

print_status "Build metadata:"
print_status "  Date: $BUILD_DATE"
print_status "  Version: $BUILD_VERSION"
print_status "  Commit: $COMMIT"

# Build the Docker image
print_status "Building Docker image..."
cd "$PROJECT_ROOT"

docker build \
    --build-arg BUILD_DATE="$BUILD_DATE" \
    --build-arg BUILD_VERSION="$BUILD_VERSION" \
    --build-arg COMMIT="$COMMIT" \
    -f docker/catalogue/Dockerfile \
    -t "$FULL_IMAGE_NAME" \
    .

if [ $? -eq 0 ]; then
    print_success "Docker image built successfully: $FULL_IMAGE_NAME"
else
    print_error "Docker build failed"
    exit 1
fi

# Show image size
IMAGE_SIZE=$(docker images --format "table {{.Size}}" "$FULL_IMAGE_NAME" | tail -n 1)
print_status "Image size: $IMAGE_SIZE"

# Push to registry if requested
if [ "$PUSH_TO_REGISTRY" = "true" ]; then
    if [ -z "$REGISTRY" ]; then
        print_error "Registry not specified. Use --registry option."
        exit 1
    fi
    
    print_status "Pushing image to registry..."
    docker push "$FULL_IMAGE_NAME"
    
    if [ $? -eq 0 ]; then
        print_success "Image pushed successfully to $REGISTRY"
    else
        print_error "Failed to push image to registry"
        exit 1
    fi
fi

print_success "Build process completed!"
print_status "To run the image:"
print_status "  docker run -p 8080:8080 $FULL_IMAGE_NAME"
print_status ""
print_status "To run with docker-compose:"
print_status "  Update docker-compose.yml to use image: $FULL_IMAGE_NAME"
print_status "  docker-compose up"
