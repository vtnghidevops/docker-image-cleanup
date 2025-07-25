# Docker Image Cleanup Script

## Purpose

Automatically clean up Docker images to save server disk space and prevent storage overflow.

## Main Features (`docker-image-cleanup.sh`)

**Remove dangling images** - Images without tags or not being used

**Remove images older than 72h** - Automatically clean up old images

**Protect whitelist images** - Important images are never deleted

**Protect multi-stage dependencies** - Check dependencies between build stages

**Keep image:latest** - For whitelisted images, always protect the newest tag on the machine

## Setup (detailed)

### 0. Download Repository

```bash
# Clone the repository
git clone https://github.com/vtnghidevops/docker-image-cleanup.git

# Navigate to the directory
cd docker-image-cleanup
```

### 1. Script Installation

```bash
# Make executable
chmod +x docker-image-cleanup.sh

# Verify script exists and has permissions
ls -la docker-image-cleanup.sh
```

### 2. Whitelist Configuration

```bash
# Create whitelist file
sudo mkdir -p /etc/docker
sudo touch /etc/docker/whitelist_images.txt

# Copy your whitelist (if exists)
sudo cp whitelist_images.txt /etc/docker/

# Edit whitelist manually
sudo nano /etc/docker/whitelist_images.txt
```

**Whitelist format:**

```
# Production images - will be protected including newest tags
nginx
alpine
node:16
node:18
mysql:8.0
redis:latest
postgres
app-backend
app-frontend
# Add your production images here...
```

### 3. Log Setup

```bash
# Create log file with proper permissions
sudo touch /var/log/docker-image-cleanup.log
sudo chmod 666 /var/log/docker-image-cleanup.log

# Test log writing
echo "Test log entry" >> /var/log/docker-image-cleanup.log
```

### 4. Script Configuration

Edit variables in script if needed:

```bash
nano docker-image-cleanup.sh

# Key variables:
AGE_THRESHOLD_HR=72                              # Delete images older than 72h
WHITELIST_FILE="/etc/docker/whitelist_images.txt"
LOG_FILE="/var/log/docker-image-cleanup.log"
```

### 5. Test Run

```bash
# Run manually first to test
./docker-image-cleanup.sh

# Check what happened
tail -20 /var/log/docker-image-cleanup.log

# Verify important images are still there
docker images
```

### 6. Crontab Setup

```bash
# Open crontab editor
crontab -e

# Add cleanup schedule (3 AM daily)
0 3 * * * /full/path/to/docker-image-cleanup.sh

# Save and verify
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

### Update whitelist

```bash
sudo nano /etc/docker/whitelist_images.txt
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
