#!/bin/bash

# Development startup script for OneTimeSecret with Authentication Migration

set -e  # Exit on any error

echo "🚀 Starting OneTimeSecret Development Environment"

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "❌ docker-compose is not installed. Please install docker-compose and try again."
    exit 1
fi

# Create necessary directories
echo "📁 Creating directories..."
mkdir -p log tmp external_auth/log external_auth/data

# Start services
echo "🐳 Starting Docker services..."
docker-compose up -d postgres redis

# Wait for PostgreSQL to be ready
echo "⏳ Waiting for PostgreSQL to be ready..."
until docker-compose exec postgres pg_isready -U postgres >/dev/null 2>&1; do
    echo "   PostgreSQL is not ready yet, waiting..."
    sleep 2
done
echo "✅ PostgreSQL is ready!"

# Start auth service
echo "🔐 Starting Authentication Service..."
docker-compose up -d auth-service

# Wait for auth service to be ready
echo "⏳ Waiting for Authentication Service to be ready..."
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if curl -s http://localhost:9393/health >/dev/null 2>&1; then
        echo "✅ Authentication Service is ready!"
        break
    fi
    echo "   Attempt $attempt/$max_attempts: Auth service not ready, waiting..."
    sleep 2
    ((attempt++))
done

if [ $attempt -gt $max_attempts ]; then
    echo "❌ Authentication Service failed to start"
    docker-compose logs auth-service
    exit 1
fi

# Start main application
echo "🌟 Starting OneTimeSecret..."
docker-compose up -d onetime

# Wait for main app to be ready
echo "⏳ Waiting for OneTimeSecret to be ready..."
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if curl -s http://localhost:4567 >/dev/null 2>&1; then
        echo "✅ OneTimeSecret is ready!"
        break
    fi
    echo "   Attempt $attempt/$max_attempts: OneTimeSecret not ready, waiting..."
    sleep 2
    ((attempt++))
done

if [ $attempt -gt $max_attempts ]; then
    echo "❌ OneTimeSecret failed to start"
    docker-compose logs onetime
    exit 1
fi

echo ""
echo "🎉 Development environment is ready!"
echo ""
echo "Services:"
echo "  📝 OneTimeSecret:        http://localhost:4567"
echo "  🔐 Auth Service:         http://localhost:9393"
echo "  🗄️  PostgreSQL:          localhost:5432"
echo "  🟥 Redis:                localhost:6379"
echo ""
echo "Optional management tools:"
echo "  🐘 pgAdmin:              http://localhost:8080 (admin@onetime.local / admin)"
echo "  🟥 Redis Commander:      http://localhost:8081"
echo ""
echo "To start optional tools: docker-compose --profile tools up -d"
echo ""
echo "Useful commands:"
echo "  📋 View logs:            docker-compose logs -f [service-name]"
echo "  🔄 Restart service:      docker-compose restart [service-name]"
echo "  🛑 Stop everything:      docker-compose down"
echo "  🧹 Clean up:             docker-compose down -v (⚠️  removes data!)"
echo ""

# Show service status
docker-compose ps
