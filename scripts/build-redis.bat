@echo off
setlocal enabledelayedexpansion

:: Build script for catalogue-redis service (Windows)
:: This script builds the Docker image and optionally pushes to a registry

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."

:: Default values
set "IMAGE_NAME=catalogue-redis"
set "IMAGE_TAG=latest"
set "PUSH_TO_REGISTRY=false"
set "REGISTRY="

:: Function to show usage
if "%1"=="--help" goto show_help
if "%1"=="-h" goto show_help

goto parse_args

:show_help
echo Usage: %0 [OPTIONS]
echo.
echo Build the catalogue-redis Docker image
echo.
echo OPTIONS:
echo     --name NAME        Image name (default: catalogue-redis)
echo     --tag TAG          Image tag (default: latest)
echo     --registry REGISTRY Registry to push to (e.g., docker.io/username)
echo     --push             Push image to registry after build
echo     --help             Show this help message
echo.
echo EXAMPLES:
echo     # Build local image
echo     %0
echo.
echo     # Build with custom name and tag
echo     %0 --name my-catalogue --tag v1.0.0
echo.
echo     # Build and push to Docker Hub
echo     %0 --registry docker.io/myusername --push
goto end

:parse_args
if "%1"=="" goto start_build

if "%1"=="--name" (
    set "IMAGE_NAME=%2"
    shift
    shift
    goto parse_args
)

if "%1"=="--tag" (
    set "IMAGE_TAG=%2"
    shift
    shift
    goto parse_args
)

if "%1"=="--registry" (
    set "REGISTRY=%2"
    shift
    shift
    goto parse_args
)

if "%1"=="--push" (
    set "PUSH_TO_REGISTRY=true"
    shift
    goto parse_args
)

echo Unknown option: %1
goto show_help

:start_build
:: Determine full image name
if not "%REGISTRY%"=="" (
    set "FULL_IMAGE_NAME=%REGISTRY%/%IMAGE_NAME%:%IMAGE_TAG%"
) else (
    set "FULL_IMAGE_NAME=%IMAGE_NAME%:%IMAGE_TAG%"
)

echo [INFO] Starting build process...
echo [INFO] Project root: %PROJECT_ROOT%
echo [INFO] Image name: %FULL_IMAGE_NAME%

:: Check if Docker is available
docker --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Docker is not installed or not in PATH
    exit /b 1
)

:: Check if we're in the right directory
if not exist "%PROJECT_ROOT%\go.mod" (
    echo [ERROR] go.mod not found. Please run this script from the project root or scripts directory.
    exit /b 1
)

:: Build metadata
for /f "tokens=1-4 delims=/ " %%a in ('date /t') do set BUILD_DATE=%%d-%%b-%%c
for /f "tokens=1-2 delims=: " %%a in ('time /t') do set BUILD_TIME=%%a:%%b
set "BUILD_VERSION=%IMAGE_TAG%"

:: Try to get git commit (fallback to "unknown" if git not available)
for /f "tokens=*" %%a in ('git rev-parse --short HEAD 2^>nul') do set COMMIT=%%a
if "%COMMIT%"=="" set "COMMIT=unknown"

echo [INFO] Build metadata:
echo [INFO]   Date: %BUILD_DATE%
echo [INFO]   Version: %BUILD_VERSION%
echo [INFO]   Commit: %COMMIT%

:: Build the Docker image
echo [INFO] Building Docker image...
cd /d "%PROJECT_ROOT%"

docker build ^
    --build-arg BUILD_DATE="%BUILD_DATE%" ^
    --build-arg BUILD_VERSION="%BUILD_VERSION%" ^
    --build-arg COMMIT="%COMMIT%" ^
    -f docker/catalogue/Dockerfile ^
    -t "%FULL_IMAGE_NAME%" ^
    .

if %errorlevel% neq 0 (
    echo [ERROR] Docker build failed
    exit /b 1
)

echo [SUCCESS] Docker image built successfully: %FULL_IMAGE_NAME%

:: Show image size
for /f "tokens=*" %%a in ('docker images --format "{{.Size}}" "%FULL_IMAGE_NAME%"') do set IMAGE_SIZE=%%a
echo [INFO] Image size: %IMAGE_SIZE%

:: Push to registry if requested
if "%PUSH_TO_REGISTRY%"=="true" (
    if "%REGISTRY%"=="" (
        echo [ERROR] Registry not specified. Use --registry option.
        exit /b 1
    )
    
    echo [INFO] Pushing image to registry...
    docker push "%FULL_IMAGE_NAME%"
    
    if %errorlevel% neq 0 (
        echo [ERROR] Failed to push image to registry
        exit /b 1
    )
    
    echo [SUCCESS] Image pushed successfully to %REGISTRY%
)

echo [SUCCESS] Build process completed!
echo [INFO] To run the image:
echo [INFO]   docker run -p 8080:8080 %FULL_IMAGE_NAME%
echo [INFO]
echo [INFO] To run with docker-compose:
echo [INFO]   Update docker-compose.yml to use image: %FULL_IMAGE_NAME%
echo [INFO]   docker-compose up

:end
endlocal
