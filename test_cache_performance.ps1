# Cache Performance Test Script

Write-Host "=== Redis Cache Performance Test ===" -ForegroundColor Green
Write-Host ""

# Function to measure API call latency
function Test-APILatency {
    param($testName)
    
    $start = Get-Date
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/catalogue" -UseBasicParsing -TimeoutSec 30
        $end = Get-Date
        $latency = ($end - $start).TotalMilliseconds
        
        Write-Host "$testName`: $($latency.ToString('F2')) ms (Status: $($response.StatusCode))" -ForegroundColor Yellow
        return $latency
    }
    catch {
        $end = Get-Date
        $latency = ($end - $start).TotalMilliseconds
        Write-Host "$testName`: $($latency.ToString('F2')) ms (ERROR: $($_.Exception.Message))" -ForegroundColor Red
        return $latency
    }
}

# Function to check Redis cache status
function Get-CacheStatus {
    try {
        $keys = docker exec catalogue-redis-cache redis-cli keys "*" 2>$null
        $dbsize = docker exec catalogue-redis-cache redis-cli dbsize 2>$null
        return @{
            KeyCount = [int]$dbsize
            Keys = $keys
        }
    }
    catch {
        return @{ KeyCount = 0; Keys = @() }
    }
}

Write-Host "1. Checking initial cache status..." -ForegroundColor Cyan
$initialCache = Get-CacheStatus
Write-Host "   Cache keys: $($initialCache.KeyCount)"
if ($initialCache.KeyCount -gt 0) {
    Write-Host "   Sample keys: $($initialCache.Keys -join ', ')"
}
Write-Host ""

Write-Host "2. Testing COLD CACHE (first request - data from MySQL)..." -ForegroundColor Cyan
$coldLatency = Test-APILatency "Cold cache"
Start-Sleep -Seconds 1

Write-Host ""
Write-Host "3. Checking cache after first request..." -ForegroundColor Cyan
$afterFirstCache = Get-CacheStatus
Write-Host "   Cache keys: $($afterFirstCache.KeyCount)"
if ($afterFirstCache.KeyCount -gt 0) {
    Write-Host "   Cached keys: $($afterFirstCache.Keys -join ', ')"
}

Write-Host ""
Write-Host "4. Testing WARM CACHE (subsequent requests - data from Redis)..." -ForegroundColor Cyan

$warmLatencies = @()
for ($i = 1; $i -le 5; $i++) {
    $warmLatency = Test-APILatency "Warm cache #$i"
    $warmLatencies += $warmLatency
    Start-Sleep -Milliseconds 500
}

Write-Host ""
Write-Host "=== Performance Analysis ===" -ForegroundColor Green
Write-Host "Cold cache (MySQL):     $($coldLatency.ToString('F2')) ms" -ForegroundColor White
Write-Host "Warm cache (Redis):     $($warmLatencies | ForEach-Object { $_.ToString('F2') }) ms" -ForegroundColor White
Write-Host "Average warm latency:   $(($warmLatencies | Measure-Object -Average).Average.ToString('F2')) ms" -ForegroundColor Yellow
Write-Host "Performance improvement: $(((($coldLatency - ($warmLatencies | Measure-Object -Average).Average) / $coldLatency) * 100).ToString('F1'))%" -ForegroundColor Green

Write-Host ""
Write-Host "5. Testing different query parameters..." -ForegroundColor Cyan

# Test with different page sizes to see caching behavior
$endpoints = @(
    "http://localhost:8080/catalogue?size=5",
    "http://localhost:8080/catalogue?size=20", 
    "http://localhost:8080/catalogue?page=2",
    "http://localhost:8080/catalogue?order=price"
)

foreach ($endpoint in $endpoints) {
    $start = Get-Date
    try {
        $response = Invoke-WebRequest -Uri $endpoint -UseBasicParsing -TimeoutSec 30
        $end = Get-Date
        $latency = ($end - $start).TotalMilliseconds
        Write-Host "  $(($endpoint -split '\?')[1]): $($latency.ToString('F2')) ms" -ForegroundColor Yellow
    }
    catch {
        Write-Host "  $(($endpoint -split '\?')[1]): ERROR" -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 300
}

Write-Host ""
Write-Host "6. Final cache status..." -ForegroundColor Cyan
$finalCache = Get-CacheStatus
Write-Host "   Total cached keys: $($finalCache.KeyCount)"
if ($finalCache.KeyCount -gt 0) {
    Write-Host "   All cached keys:"
    $finalCache.Keys | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
}

Write-Host ""
Write-Host "=== Test Complete ===" -ForegroundColor Green
