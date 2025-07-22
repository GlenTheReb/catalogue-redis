# Deploy Redis-enabled Catalogue Service to Main Application
# This script helps integrate the Redis-enabled catalogue service into the main application

Write-Host "=== Deploying Redis-enabled Catalogue Service ===" -ForegroundColor Green

# Step 1: Build the catalogue service image
Write-Host "`n1. Building catalogue service with Redis support..." -ForegroundColor Yellow
docker build -t catalogue-redis:latest -f ./docker/catalogue/Dockerfile .

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to build catalogue service image" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Catalogue service image built successfully" -ForegroundColor Green

# Step 2: Stop the main application if running
Write-Host "`n2. Stopping existing application (if running)..." -ForegroundColor Yellow
docker-compose -f docker-compose-application.yml down

# Step 3: Start the application with Redis-enabled catalogue
Write-Host "`n3. Starting application with Redis-enabled catalogue..." -ForegroundColor Yellow
docker-compose -f docker-compose-application.yml up -d

# Step 4: Wait for services to be healthy
Write-Host "`n4. Waiting for services to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Step 5: Check service status
Write-Host "`n5. Checking service status..." -ForegroundColor Yellow
docker-compose -f docker-compose-application.yml ps

# Step 6: Test the catalogue service
Write-Host "`n6. Testing catalogue service..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8080/catalogue" -TimeoutSec 10
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ Catalogue service is responding (Status: $($response.StatusCode))" -ForegroundColor Green
        
        # Parse response to show product count
        $products = $response.Content | ConvertFrom-Json
        Write-Host "📦 Found $($products.Count) products in catalogue" -ForegroundColor Cyan
    }
} catch {
    Write-Host "❌ Catalogue service test failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Step 7: Test Redis cache
Write-Host "`n7. Checking Redis cache..." -ForegroundColor Yellow
try {
    $redisKeys = docker exec $(docker-compose -f docker-compose-application.yml ps -q redis) redis-cli DBSIZE
    Write-Host "🔑 Redis cache has $redisKeys keys" -ForegroundColor Cyan
} catch {
    Write-Host "❌ Could not check Redis cache" -ForegroundColor Red
}

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
Write-Host "🌐 Application URL: http://localhost" -ForegroundColor Cyan
Write-Host "🛒 Edge Router: http://localhost:8080" -ForegroundColor Cyan
Write-Host "📊 To monitor performance, use the test_cache_performance.ps1 script" -ForegroundColor Yellow
