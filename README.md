# CV on AWS - 23L-3006

## Architecture
Visitor -> EC2 public IP:80 -> Apache -> files synced from S3 by the instance role every 2 min
Visitor -> Lambda function URL (HTTPS) -> function reads S3 using the Lambda role -> response
Both read the private bucket cv-23l-3006/site/.

## Access denied output (from the EC2 instance)
[ec2-user@ip-172-31-xx-xx ~]$ echo hello > /tmp/x.txt
[ec2-user@ip-172-31-xx-xx ~]$ aws s3 cp /tmp/x.txt s3://cv-23l-3006/site/index.html
upload failed: ../../../tmp/x.txt to s3://cv-23l-3006/site/index.html An error occurred (AccessDenied) when calling the PutObject operation: Access Denied
[ec2-user@ip-172-31-xx-xx ~]$ aws s3 rm s3://cv-23l-3006/site/cv.pdf
delete failed: s3://cv-23l-3006/site/cv.pdf An error occurred (AccessDenied) when calling the DeleteObject operation: Access Denied
[ec2-user@ip-172-31-xx-xx ~]$ tail -n 10 /var/log/cv-sync.log
2026-10-24T04:30:15Z sync OK
2026-10-24T04:32:15Z sync OK
2026-10-24T04:34:15Z sync OK
## Written answers
1. Roles give short-lived credentials automatically. Keys in user-data can leak from the repo, the instance metadata, or logs, and they never expire.
2. They see "Access Denied". Block Public Access plus no public bucket policy causes it.
3. The function URL permission lets anyone invoke the function, which is acceptable because the function’s code controls what it returns and holds its own limited role. The bucket’s files are private data.
4. EC2 costs money 24/7 (instance, disk) even with no visitors. Lambda costs about nothing when idle. At 100× traffic, Lambda scales automatically, while one EC2 instance may be overwhelmed.
5. You lose the server, its local files, and its logs. You still have the S3 bucket (and versions), the IAM roles, the Lambda site, and your repo.

## Sources / adapted work
Adapted from the course material, AWS docs, and an AI assistant guide. I can explain everything submitted.
