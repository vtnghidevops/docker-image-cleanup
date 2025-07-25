# Docker Image Cleanup Script

## Purpose

Automatically clean up Docker images to save server disk space and prevent storage overflow.

## Main Features (`docker-image-cleanup.sh`)

**Remove dangling images** - Images without tags or not being used

**Remove images older than 72h** - Automatically clean up old images

**Protect whitelist images** - Important images are never deleted

**Protect multi-stage dependencies** - Check dependencies between build stages

**Keep image:latest** - For whitelisted images, always protect the newest tag on the machine

## Setup (one-time only)

```bash
# 1. Set permissions
chmod +x docker-image-cleanup.sh

# 2. Copy whitelist
sudo cp whitelist_images.txt /etc/docker/

# 3. Setup crontab automatically
crontab -e
```

**Add to crontab:**

```bash
# Cleanup images: 3 AM daily
0 3 * * * /path/to/docker-image-cleanup.sh
```

**Check crontab**

```bash
crontab -l
```

## Daily Usage

### Run manually

```bash
./docker-image-cleanup.sh
```

### Check logs

```bash
tail -f /var/log/docker-image-cleanup.log
```

### Configure whitelist

Edit file `/etc/docker/whitelist_images.txt`:

```
# Production images - will be protected including newest tags
nginx
alpine
node
mysql
redis
postgres
app-backend
app-frontend
# Add images to keep...
```

## How it works

1. **Scan all images** on server
2. **Remove dangling images** first
3. **Check whitelist** - skip protected images (including newest tags)
4. **Check dependencies** - ensure multi-stage builds aren't broken
5. **Remove images > 72h** - only delete when safe
6. **Log detailed** all operations

## Quick Troubleshooting

**Script won't run:**

```bash
ls -la docker-image-cleanup.sh    # Check permissions
crontab -l                        # Check cron setup
```

**Can't write logs:**

```bash
sudo touch /var/log/docker-image-cleanup.log
sudo chmod 666 /var/log/docker-image-cleanup.log
```

**Important images got deleted:**

- Add to whitelist immediately
- Increase `AGE_THRESHOLD_HR=120` in script (instead of 72h)

## Custom Configuration

Variables you can adjust in script:

- `AGE_THRESHOLD_HR=72` - Image age threshold for deletion (hours)
- `WHITELIST_FILE` - Path to whitelist file
- `LOG_FILE` - Path to log file

## Common Cron Schedules

- `0 3 * * *` → 3 AM daily (recommended)
- `0 4 * * 0` → 4 AM Sundays (less frequent)
- `0 */12 * * *` → Every 12 hours (frequent)

