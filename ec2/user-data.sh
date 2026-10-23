#!/bin/bash
dnf install -y httpd
systemctl enable --now httpd

cat > /etc/cv-sync.conf <<'EOF'
BUCKET=cv-23l-3006
PREFIX=site/
EOF

curl -fsSL -o /usr/local/bin/sync-cv.sh   https://raw.githubusercontent.com/MHassanJalil/cv-aws-lab/main/ec2/sync-cv.sh
chmod +x /usr/local/bin/sync-cv.sh

cat > /etc/systemd/system/cv-sync.service <<'EOF'
[Unit]
Description=Sync CV from S3
[Service]
Type=oneshot
ExecStart=/usr/local/bin/sync-cv.sh
EOF

cat > /etc/systemd/system/cv-sync.timer <<'EOF'
[Unit]
Description=Run CV sync every 2 minutes
[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
/usr/local/bin/sync-cv.sh
systemctl enable --now cv-sync.timer
