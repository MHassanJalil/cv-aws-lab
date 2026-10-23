#!/usr/bin/env bash
# Usage: ./collect-evidence.sh <bucket> <ec2-address> <lambda-address>
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <bucket-name> <ec2-address> <lambda-address>"
  exit 1
fi

BUCKET="$1"; EC2_ADDR="${2%/}"; LAMBDA_ADDR="${3%/}"
case "$EC2_ADDR" in http*) ;; *) EC2_ADDR="http://$EC2_ADDR" ;; esac
case "$LAMBDA_ADDR" in http*) ;; *) LAMBDA_ADDR="https://$LAMBDA_ADDR" ;; esac
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region)}}"
OUT="evidence.txt"
export AWS_PAGER=""
: > "$OUT"

section() { printf '== %s ==\n' "$1" >> "$OUT"; }
endsec()  { printf '\n' >> "$OUT"; }
run()     { "$@" >> "$OUT" 2>&1 || echo "[FAILED] $*" >> "$OUT"; }
runsh()   { bash -o pipefail -c "$1" >> "$OUT" 2>&1 || echo "[FAILED] $1" >> "$OUT"; }
clean()   { [ "$1" = "None" ] && echo "" || echo "$1"; }

# Find my resources by their name prefix
EC2_ROLE=$(clean "$(aws iam list-roles --query "Roles[?starts_with(RoleName,'cv-ec2-role-')].RoleName | [0]" --output text 2>/dev/null)")
LAMBDA_ROLE=$(clean "$(aws iam list-roles --query "Roles[?starts_with(RoleName,'cv-lambda-role-')].RoleName | [0]" --output text 2>/dev/null)")
FUNC=$(clean "$(aws lambda list-functions --query "Functions[?starts_with(FunctionName,'cv-func-')].FunctionName | [0]" --output text 2>/dev/null)")
IID=$(clean "$(aws ec2 describe-instances --filters "Name=tag:Name,Values=cv-ec2-*" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null)")
SG=""
[ -n "$IID" ] && SG=$(clean "$(aws ec2 describe-instances --instance-ids "$IID" --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text 2>/dev/null)")

section caller;        run aws sts get-caller-identity;                          endsec
section public-access; run aws s3api get-public-access-block --bucket "$BUCKET"; endsec
section versioning;    run aws s3api get-bucket-versioning --bucket "$BUCKET";   endsec
section objects;       run aws s3 ls "s3://$BUCKET/site/" --recursive;           endsec

section ec2-policy
if [ -n "$EC2_ROLE" ]; then
  echo "role: $EC2_ROLE" >> "$OUT"
  for p in $(aws iam list-role-policies --role-name "$EC2_ROLE" --query 'PolicyNames[]' --output text 2>/dev/null); do
    run aws iam get-role-policy --role-name "$EC2_ROLE" --policy-name "$p"
  done
else echo "[FAILED] EC2 role not found" >> "$OUT"; fi
endsec

section lambda-policy
if [ -n "$LAMBDA_ROLE" ]; then
  echo "role: $LAMBDA_ROLE" >> "$OUT"
  run aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE"
  for p in $(aws iam list-role-policies --role-name "$LAMBDA_ROLE" --query 'PolicyNames[]' --output text 2>/dev/null); do
    run aws iam get-role-policy --role-name "$LAMBDA_ROLE" --policy-name "$p"
  done
else echo "[FAILED] Lambda role not found" >> "$OUT"; fi
endsec

section security-group
if [ -n "$SG" ]; then
  run aws ec2 describe-security-groups --group-ids "$SG" --query 'SecurityGroups[].IpPermissions' --output json
else echo "[FAILED] instance/security group not found" >> "$OUT"; fi
endsec

section instance
if [ -n "$IID" ]; then
  run aws ec2 describe-instances --instance-ids "$IID" --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,IMDSTokens:MetadataOptions.HttpTokens,Profile:IamInstanceProfile.Arn,PublicIp:PublicIpAddress}' --output json
else echo "[FAILED] running instance not found" >> "$OUT"; fi
endsec

probe() {
  printf '%s -> ' "$1" >> "$OUT"
  curl -s -o /dev/null -m 20 -w '%{http_code} %{content_type}\n' "$1" >> "$OUT" 2>&1 \
    || echo "[FAILED] curl $1" >> "$OUT"
}
section endpoints
for p in / /style.css /cv.pdf; do probe "$EC2_ADDR$p"; done
for p in / /style.css /cv.pdf /anything; do probe "$LAMBDA_ADDR$p"; done
probe "https://$BUCKET.s3.$REGION.amazonaws.com/site/index.html"
endsec

section lambda-logs
if [ -n "$FUNC" ]; then runsh "aws logs tail /aws/lambda/$FUNC --since 3d | tail -n 15"
else echo "[FAILED] function not found" >> "$OUT"; fi
endsec

section log-retention
if [ -n "$FUNC" ]; then
  run aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/$FUNC" --query 'logGroups[].{name:logGroupName,retentionInDays:retentionInDays}' --output json
else echo "[FAILED] function not found" >> "$OUT"; fi
endsec

echo DONE
