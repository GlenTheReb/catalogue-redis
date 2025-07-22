#!/bin/bash

# Performance test script for catalogue-redis service
# This script runs various performance tests to validate cache performance

# Configuration
SERVICE_URL="http://localhost:8080"
CONCURRENT_REQUESTS=10
TOTAL_REQUESTS=1000
WARMUP_REQUESTS=50

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if required tools are available
check_dependencies() {
    print_status "Checking dependencies..."
    
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed"
        exit 1
    fi
    
    if ! command -v ab &> /dev/null; then
        print_warning "Apache Bench (ab) not found. Install apache2-utils for load testing."
    fi
    
    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. JSON parsing will be limited."
    fi
}

# Test service health
test_health() {
    print_status "Testing service health..."
    
    response=$(curl -s -w "HTTPSTATUS:%{http_code};TIME:%{time_total}" "$SERVICE_URL/health")
    http_code=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    time_total=$(echo "$response" | grep -o "TIME:[0-9.]*" | cut -d: -f2)
    body=$(echo "$response" | sed -E 's/HTTPSTATUS:[0-9]*;TIME:[0-9.]*$//')
    
    if [ "$http_code" = "200" ]; then
        print_success "Service is healthy (${time_total}s)"
        if command -v jq &> /dev/null; then
            echo "$body" | jq '.' 2>/dev/null || echo "$body"
        else
            echo "$body"
        fi
    else
        print_error "Service health check failed (HTTP $http_code)"
        echo "$body"
        exit 1
    fi
}

# Test individual endpoints for functionality
test_endpoints() {
    print_status "Testing individual endpoints..."
    
    # Test catalogue listing
    print_status "Testing /catalogue endpoint..."
    response=$(curl -s -w "TIME:%{time_total}" "$SERVICE_URL/catalogue?size=6")
    time_total=$(echo "$response" | grep -o "TIME:[0-9.]*" | cut -d: -f2)
    print_status "Catalogue listing response time: ${time_total}s"
    
    # Test catalogue count
    print_status "Testing /catalogue/size endpoint..."
    response=$(curl -s -w "TIME:%{time_total}" "$SERVICE_URL/catalogue/size")
    time_total=$(echo "$response" | grep -o "TIME:[0-9.]*" | cut -d: -f2)
    print_status "Catalogue count response time: ${time_total}s"
    
    # Test tags
    print_status "Testing /tags endpoint..."
    response=$(curl -s -w "TIME:%{time_total}" "$SERVICE_URL/tags")
    time_total=$(echo "$response" | grep -o "TIME:[0-9.]*" | cut -d: -f2)
    print_status "Tags response time: ${time_total}s"
    
    # Test individual product (get first product ID)
    product_id=$(curl -s "$SERVICE_URL/catalogue?size=1" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$product_id" ]; then
        print_status "Testing /catalogue/$product_id endpoint..."
        response=$(curl -s -w "TIME:%{time_total}" "$SERVICE_URL/catalogue/$product_id")
        time_total=$(echo "$response" | grep -o "TIME:[0-9.]*" | cut -d: -f2)
        print_status "Individual product response time: ${time_total}s"
    fi
}

# Warmup cache
warmup_cache() {
    print_status "Warming up cache with $WARMUP_REQUESTS requests..."
    
    for i in $(seq 1 $WARMUP_REQUESTS); do
        curl -s "$SERVICE_URL/catalogue?size=6" > /dev/null &
        curl -s "$SERVICE_URL/catalogue/size" > /dev/null &
        curl -s "$SERVICE_URL/tags" > /dev/null &
        
        # Add some delay to avoid overwhelming the service
        if [ $((i % 10)) -eq 0 ]; then
            wait
            print_status "Warmed up $i/$WARMUP_REQUESTS requests..."
        fi
    done
    wait
    
    # Give cache time to populate
    sleep 2
    print_success "Cache warmup completed"
}

# Performance test using Apache Bench
load_test_ab() {
    if ! command -v ab &> /dev/null; then
        print_warning "Skipping Apache Bench tests (ab not installed)"
        return
    fi
    
    print_status "Running load tests with Apache Bench..."
    
    # Test catalogue listing
    print_status "Load testing /catalogue endpoint..."
    ab -n $TOTAL_REQUESTS -c $CONCURRENT_REQUESTS -q "$SERVICE_URL/catalogue?size=6" > ab_catalogue.log 2>&1
    
    # Extract key metrics
    avg_time=$(grep "Time per request:" ab_catalogue.log | head -1 | awk '{print $4}')
    requests_per_sec=$(grep "Requests per second:" ab_catalogue.log | awk '{print $4}')
    failed_requests=$(grep "Failed requests:" ab_catalogue.log | awk '{print $3}')
    
    print_success "Catalogue listing results:"
    print_status "  Average response time: ${avg_time} ms"
    print_status "  Requests per second: ${requests_per_sec}"
    print_status "  Failed requests: ${failed_requests}"
    
    # Test individual product
    product_id=$(curl -s "$SERVICE_URL/catalogue?size=1" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$product_id" ]; then
        print_status "Load testing /catalogue/$product_id endpoint..."
        ab -n $TOTAL_REQUESTS -c $CONCURRENT_REQUESTS -q "$SERVICE_URL/catalogue/$product_id" > ab_product.log 2>&1
        
        avg_time=$(grep "Time per request:" ab_product.log | head -1 | awk '{print $4}')
        requests_per_sec=$(grep "Requests per second:" ab_product.log | awk '{print $4}')
        failed_requests=$(grep "Failed requests:" ab_product.log | awk '{print $3}')
        
        print_success "Individual product results:"
        print_status "  Average response time: ${avg_time} ms"
        print_status "  Requests per second: ${requests_per_sec}"
        print_status "  Failed requests: ${failed_requests}"
    fi
}

# Manual load test using curl
load_test_curl() {
    print_status "Running manual load test with curl..."
    
    start_time=$(date +%s.%N)
    successful_requests=0
    failed_requests=0
    total_time=0
    
    for i in $(seq 1 100); do
        response=$(curl -s -w "TIME:%{time_total};CODE:%{http_code}" "$SERVICE_URL/catalogue?size=6" 2>/dev/null)
        
        if echo "$response" | grep -q "CODE:200"; then
            successful_requests=$((successful_requests + 1))
            time_taken=$(echo "$response" | grep -o "TIME:[0-9.]*" | cut -d: -f2)
            total_time=$(echo "$total_time + $time_taken" | bc 2>/dev/null || echo "$total_time")
        else
            failed_requests=$((failed_requests + 1))
        fi
        
        if [ $((i % 20)) -eq 0 ]; then
            print_status "Completed $i/100 requests..."
        fi
    done
    
    end_time=$(date +%s.%N)
    total_duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "unknown")
    
    if [ "$successful_requests" -gt 0 ] && command -v bc &> /dev/null; then
        avg_response_time=$(echo "scale=3; $total_time / $successful_requests" | bc)
        requests_per_sec=$(echo "scale=2; $successful_requests / $total_duration" | bc)
    else
        avg_response_time="unknown"
        requests_per_sec="unknown"
    fi
    
    print_success "Manual load test results:"
    print_status "  Successful requests: $successful_requests"
    print_status "  Failed requests: $failed_requests"
    print_status "  Average response time: ${avg_response_time}s"
    print_status "  Requests per second: $requests_per_sec"
    print_status "  Total duration: ${total_duration}s"
}

# Test cache effectiveness
test_cache_effectiveness() {
    print_status "Testing cache effectiveness..."
    
    # First request (should be cache miss)
    print_status "Making first request (expected cache miss)..."
    response1=$(curl -s -w "TIME:%{time_total}" "$SERVICE_URL/catalogue?size=6")
    time1=$(echo "$response1" | grep -o "TIME:[0-9.]*" | cut -d: -f2)
    print_status "First request time: ${time1}s"
    
    # Second request (should be cache hit)
    print_status "Making second request (expected cache hit)..."
    response2=$(curl -s -w "TIME:%{time_total}" "$SERVICE_URL/catalogue?size=6")
    time2=$(echo "$response2" | grep -o "TIME:[0-9.]*" | cut -d: -f2)
    print_status "Second request time: ${time2}s"
    
    # Calculate improvement
    if command -v bc &> /dev/null; then
        improvement=$(echo "scale=2; ($time1 - $time2) / $time1 * 100" | bc 2>/dev/null)
        if [ -n "$improvement" ]; then
            print_success "Cache performance improvement: ${improvement}%"
        fi
    fi
}

# Generate performance report
generate_report() {
    print_status "Generating performance report..."
    
    {
        echo "# Catalogue-Redis Performance Test Report"
        echo "Generated on: $(date)"
        echo ""
        echo "## Configuration"
        echo "- Service URL: $SERVICE_URL"
        echo "- Concurrent requests: $CONCURRENT_REQUESTS"
        echo "- Total requests: $TOTAL_REQUESTS"
        echo "- Warmup requests: $WARMUP_REQUESTS"
        echo ""
        
        if [ -f "ab_catalogue.log" ]; then
            echo "## Apache Bench Results - Catalogue Listing"
            grep -E "(Requests per second|Time per request|Failed requests)" ab_catalogue.log
            echo ""
        fi
        
        if [ -f "ab_product.log" ]; then
            echo "## Apache Bench Results - Individual Product"
            grep -E "(Requests per second|Time per request|Failed requests)" ab_product.log
            echo ""
        fi
        
        echo "## Health Check"
        curl -s "$SERVICE_URL/health" | jq '.' 2>/dev/null || curl -s "$SERVICE_URL/health"
        
    } > performance_report.md
    
    print_success "Performance report saved to performance_report.md"
}

# Main execution
main() {
    print_status "Starting performance tests for catalogue-redis service"
    print_status "Target service: $SERVICE_URL"
    
    check_dependencies
    test_health
    test_endpoints
    warmup_cache
    test_cache_effectiveness
    load_test_ab
    load_test_curl
    generate_report
    
    print_success "Performance testing completed!"
    print_status "Check performance_report.md for detailed results"
    
    # Cleanup
    rm -f ab_catalogue.log ab_product.log
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --url)
            SERVICE_URL="$2"
            shift 2
            ;;
        --concurrent)
            CONCURRENT_REQUESTS="$2"
            shift 2
            ;;
        --total)
            TOTAL_REQUESTS="$2"
            shift 2
            ;;
        --warmup)
            WARMUP_REQUESTS="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --url URL           Service URL (default: http://localhost:8080)"
            echo "  --concurrent N      Concurrent requests (default: 10)"
            echo "  --total N           Total requests (default: 1000)"
            echo "  --warmup N          Warmup requests (default: 50)"
            echo "  -h, --help          Show this help"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

main
