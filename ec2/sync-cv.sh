#!/bin/bash
# Copies site/ from S3 into the web root, stamps the footer, logs the result.
CONF=/etc/cv-sync.conf
[ -f "$CONF" ] && . "$CONF"
BUCKET="${BUCKET:?BUCKET not set}"
PREFIX="${PREFIX:-site/}"
WEBROOT=/var/www/html
LOG=/var/log/cv-sync.log

now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# IMDSv2: get a token first, then read the instance ID
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
IID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/instance-id)

if aws s3 sync "s3://$BUCKET/$PREFIX" "$TMP" --only-show-errors \
   && [ -f "$TMP/index.html" ] && [ -n "$IID" ]; then
  sed -i "s|{{HOSTED_ON}}|EC2 $IID|g" "$TMP/index.html"
  cp -rf "$TMP"/. "$WEBROOT"/
  chmod -R a+rX "$WEBROOT"
  echo "$(now) sync OK" >> "$LOG"
else
  echo "$(now) sync FAILED" >> "$LOG"
  exit 1
fi
