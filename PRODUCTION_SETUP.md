# LiteLLM Production Setup - Complete Guide

## 🚀 Production Setup Complete!

Your LiteLLM proxy with GitHub Copilot integration is now running in production mode with optimized settings and minimal logging.

## ✅ What's Been Configured

### Logging & Performance
- **Debug logging**: DISABLED (ERROR level only)
- **Verbose logging**: DISABLED
- **JSON logs**: ENABLED for structured logging
- **Workers**: 4 concurrent workers
- **Request timeout**: 600 seconds
- **Restart policy**: unless-stopped

### Security & Authentication
- **Master key**: `sk-1234` (change this in production!)
- **GitHub Copilot auth**: PRESERVED and backed up
- **Salt key**: Set for encryption consistency
- **Route restrictions**: Removed (all routes require authentication)

### Data Persistence
- **Database**: PostgreSQL with persistent storage
- **GitHub Copilot tokens**: Preserved in named volume
- **Automatic backups**: Available via script

## 🔧 Production Files Created

### Docker Configuration
- `docker-compose.prod.yml` - Production Docker setup
- `config.prod.yaml` - Production LiteLLM configuration
- `.env.prod` - Production environment variables

### Management Scripts
- `setup_production.sh` - Complete production setup
- `start_prod.sh` - Quick production start
- `rebuild_docker_prod.sh` - Full rebuild with auth preservation
- `backup_copilot_auth.sh` - GitHub Copilot auth backup/restore
- `production_status.sh` - Current status overview

## 🌐 Access Information

- **API URL**: http://localhost:4000
- **Master Key**: `sk-1234`
- **Admin UI**: http://localhost:4000 (login with master key)
- **Swagger docs**: http://localhost:4000/docs

## 📋 Management Commands

### Start/Stop Services
```bash
# Start production mode
./start_prod.sh

# Stop services
docker-compose -f docker-compose.prod.yml down

# Restart services
docker-compose -f docker-compose.prod.yml restart

# View logs (minimal ERROR level only)
docker-compose -f docker-compose.prod.yml logs -f
```

### GitHub Copilot Auth Management
```bash
# Backup auth data
./backup_copilot_auth.sh backup

# Restore auth data
./backup_copilot_auth.sh restore

# Check auth status
./backup_copilot_auth.sh status
```

### Complete Rebuild
```bash
# Full rebuild preserving GitHub Copilot auth
./rebuild_docker_prod.sh

# Complete setup from scratch
./setup_production.sh
```

## 🧪 Testing the Setup

### Basic API Test
```bash
curl -X POST http://localhost:4000/chat/completions \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer sk-1234" \
     -d '{"model": "github_copilot/gpt-4.1", "messages": [{"role": "user", "content": "Hello from production!"}]}'
```

### Model Information
```bash
curl -H "Authorization: Bearer sk-1234" \
     http://localhost:4000/v2/model/info
```

### Health Check
```bash
curl http://localhost:4000/
```

## 📊 Available Models

All GitHub Copilot models are available:
- `github_copilot/gpt-4o`
- `github_copilot/gpt-4.1`
- `github_copilot/o1`
- `github_copilot/o3-mini`
- `github_copilot/o4-mini`
- `github_copilot/claude-3.5-sonnet`
- `github_copilot/claude-3.7-sonnet`
- `github_copilot/claude-3.7-sonnet-thought`
- `github_copilot/claude-sonnet-4`
- `github_copilot/gemini-2.0-flash-001`
- `github_copilot/gemini-2.5-pro`

## 🔍 Monitoring & Logs

### Log Levels (Production)
- **Application logs**: ERROR level only
- **Database logs**: Limited to errors
- **Container logs**: Rotated (10MB max, 3 files)

### Status Monitoring
```bash
# Quick status overview
./production_status.sh

# Container health
docker-compose -f docker-compose.prod.yml ps

# Resource usage
docker stats
```

## 🛠️ Troubleshooting

### If API is not responding:
1. Check container status: `docker-compose -f docker-compose.prod.yml ps`
2. Check logs: `docker-compose -f docker-compose.prod.yml logs litellm`
3. Restart service: `docker-compose -f docker-compose.prod.yml restart`

### If GitHub Copilot auth is lost:
1. Restore from backup: `./backup_copilot_auth.sh restore`
2. Or re-authenticate using the original development setup

### If database issues occur:
1. Check DB health: `docker-compose -f docker-compose.prod.yml logs db`
2. Database is persistent - data survives container restarts

## 🔐 Security Notes

### Production Checklist
- [ ] Change master key from `sk-1234` to a secure value
- [ ] Set up proper firewall rules
- [ ] Enable HTTPS/TLS in production
- [ ] Regular backup of GitHub Copilot auth
- [ ] Monitor logs for security issues

### Environment Variables
Update `.env.prod` with your secure values:
```bash
LITELLM_MASTER_KEY="your-secure-master-key"
LITELLM_SALT_KEY="your-32-character-salt-key"
```

## 📈 Performance Optimizations Applied

- **Caching**: Disabled Redis cache to avoid complexity
- **Database**: Connection pooling (100 connections)
- **Workers**: 4 concurrent workers
- **Timeouts**: Optimized for production use
- **Logging**: Minimal overhead (ERROR only)

## 🎯 Next Steps

1. **Update credentials**: Change default master key and salt
2. **Monitor performance**: Watch logs and resource usage
3. **Setup monitoring**: Consider adding Prometheus/Grafana
4. **Backup strategy**: Regular GitHub Copilot auth backups
5. **Load balancing**: Scale horizontally if needed

Your LiteLLM production environment is ready! 🎉