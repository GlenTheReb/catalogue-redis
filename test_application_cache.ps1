# Test cache performance for the main application deployment
# This script tests the Redis cache performance when integrated with the full application

param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$ComposeFile = "docker-compose-application.yml"
)

Write-Host "=== Application Cache Performance Test ===" -ForegroundColor Green

# Helper function to measure request time
function Measure-RequestTime {
    param([string]$Url)
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-WebRequest -Uri $Url -TimeoutSec 30
        $stopwatch.Stop()
        return @{
            Time = $stopwatch.ElapsedMilliseconds
            Status = $response.StatusCode
            Success = $true
        }
    } catch {
        $stopwatch.Stop()
        return @{
            Time = $stopwatch.ElapsedMilliseconds
            Status = 0
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# 1. Check if application is running
Write-Host "`n1. Checking application status..." -ForegroundColor Yellow
$services = docker-compose -f $ComposeFile ps
if ($services -match "catalogue.*Up") {
    Write-Host "✅ Application is running" -ForegroundColor Green
} else {
    Write-Host "❌ Application not running. Please run deploy_to_application.ps1 first" -ForegroundColor Red
    exit 1
}

# 2. Clear Redis cache
Write-Host "`n2. Clearing Redis cache..." -ForegroundColor Yellow
$redisContainer = docker-compose -f $ComposeFile ps -q redis
docker exec $redisContainer redis-cli FLUSHALL
$initialKeys = docker exec $redisContainer redis-cli DBSIZE
Write-Host "   Cache keys after flush: $initialKeys" -ForegroundColor Cyan

# 3. Test cold cache (first request)
Write-Host "`n3. Testing COLD CACHE (first request - data from MySQL)..." -ForegroundColor Yellow
$coldResult = Measure-RequestTime "$BaseUrl/catalogue"
if ($coldResult.Success) {
    Write-Host "   Cold cache: $($coldResult.Time) ms (Status: $($coldResult.Status))" -ForegroundColor Cyan
} else {
    Write-Host "   ❌ Cold cache test failed: $($coldResult.Error)" -ForegroundColor Red
    exit 1
}

# 4. Check cache population
Start-Sleep -Seconds 1
$cacheKeys = docker exec $redisContainer redis-cli DBSIZE
Write-Host "`n4. Cache population after first request..." -ForegroundColor Yellow
Write-Host "   Cache keys: $cacheKeys" -ForegroundColor Cyan

if ($cacheKeys -gt 0) {
    $keysList = docker exec $redisContainer redis-cli KEYS "*"
    Write-Host "   Cached keys: $keysList" -ForegroundColor Cyan
}

# 5. Test warm cache (multiple requests)
Write-Host "`n5. Testing WARM CACHE (subsequent requests - data from Redis)..." -ForegroundColor Yellow
$warmResults = @()

for ($i = 1; $i -le 5; $i++) {
    Start-Sleep -Milliseconds 100
    $warmResult = Measure-RequestTime "$BaseUrl/catalogue"
    if ($warmResult.Success) {
        $warmResults += $warmResult.Time
        Write-Host "   Warm cache #$i`: $($warmResult.Time) ms (Status: $($warmResult.Status))" -ForegroundColor Cyan
    } else {
        Write-Host "   ❌ Warm cache test #$i failed: $($warmResult.Error)" -ForegroundColor Red
    }
}

# 6. Performance analysis
if ($warmResults.Count -gt 0) {
    $avgWarm = [math]::Round(($warmResults | Measure-Object -Average).Average, 2)
    $improvement = [math]::Round((($coldResult.Time - $avgWarm) / $coldResult.Time) * 100, 1)
    
    Write-Host "`n=== Performance Analysis ===" -ForegroundColor Green
    Write-Host "Cold cache (MySQL):     $($coldResult.Time) ms" -ForegroundColor White
    Write-Host "Warm cache (Redis):     $($warmResults -join ' ') ms" -ForegroundColor White
    Write-Host "Average warm latency:   $avgWarm ms" -ForegroundColor Cyan
    Write-Host "Performance improvement: $improvement%" -ForegroundColor Green
}

# 7. Test different endpoints
Write-Host "`n7. Testing different catalogue endpoints..." -ForegroundColor Yellow

$endpoints = @(
    @{Path = "/catalogue?size=5"; Name = "size=5"}
    @{Path = "/catalogue?size=20"; Name = "size=20"}
    @{Path = "/catalogue?page=2"; Name = "page=2"}
    @{Path = "/catalogue?order=price"; Name = "order=price"}
)

foreach ($endpoint in $endpoints) {
    $result = Measure-RequestTime "$BaseUrl$($endpoint.Path)"
    if ($result.Success) {
        Write-Host "   $($endpoint.Name): $($result.Time) ms" -ForegroundColor Cyan
    } else {
        Write-Host "   ❌ $($endpoint.Name): Failed" -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 100
}

# 8. Final cache status
Write-Host "`n8. Final cache status..." -ForegroundColor Yellow
$finalKeys = docker exec $redisContainer redis-cli DBSIZE
Write-Host "   Total cached keys: $finalKeys" -ForegroundColor Cyan

if ($finalKeys -gt 0) {
    Write-Host "   All cached keys:" -ForegroundColor Yellow
    $allKeys = docker exec $redisContainer redis-cli KEYS "*"
    $allKeys -split "`n" | ForEach-Object {
        if ($_.Trim()) {
            Write-Host "     $_" -ForegroundColor Cyan
        }
    }
}

# 9. Test front-end integration
Write-Host "`n9. Testing front-end integration..." -ForegroundColor Yellow
try {
    $frontEndResult = Measure-RequestTime "http://localhost"
    if ($frontEndResult.Success) {
        Write-Host "   ✅ Front-end accessible: $($frontEndResult.Time) ms" -ForegroundColor Green
    } else {
        Write-Host "   ❌ Front-end not accessible" -ForegroundColor Red
    }
} catch {
    Write-Host "   ❌ Front-end test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Application Cache Test Complete ===" -ForegroundColor Green
Write-Host "🌐 Full application: http://localhost" -ForegroundColor Cyan
Write-Host "🛒 Catalogue API: http://localhost:8080/catalogue" -ForegroundColor Cyan
