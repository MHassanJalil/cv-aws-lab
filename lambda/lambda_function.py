import base64
import json
import os
import time

import boto3
from botocore.exceptions import ClientError

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET"]
PREFIX = os.environ["PREFIX"]
FN = os.environ.get("AWS_LAMBDA_FUNCTION_NAME", "unknown")

PAGE = ("index.html", "text/html")
ROUTES = {
    "/": PAGE,
    "/index.html": PAGE,
    "/style.css": ("style.css", "text/css"),
    "/cv.pdf": ("cv.pdf", "application/pdf"),
}

def build_response(path):
    if path not in ROUTES:
        html = "<html><body><h1>404 - Not Found</h1><p>No such page.</p></body></html>"
        return 404, {"Content-Type": "text/html"}, html, False

    name, ctype = ROUTES[path]
    try:
        obj = s3.get_object(Bucket=BUCKET, Key=PREFIX + name)
        data = obj["Body"].read()
    except ClientError:
        html = "<html><body><h1>500 - Could not load file</h1></body></html>"
        return 500, {"Content-Type": "text/html"}, html, False

    headers = {"Content-Type": ctype}
    if ctype == "application/pdf":
        return 200, headers, base64.b64encode(data).decode("ascii"), True

    text = data.decode("utf-8")
    if name == "index.html":
        text = text.replace("{{HOSTED_ON}}", "Lambda " + FN)
        headers["Cache-Control"] = "max-age=60"
    return 200, headers, text, False

def handler(event, context):
    start = time.time()
    path = event.get("rawPath") or "/"
    status, headers, body, is_b64 = build_response(path)
    print(json.dumps({"fn": FN, "path": path, "status": status,
                      "ms": int((time.time() - start) * 1000)}))
    return {
        "statusCode": status,
        "headers": headers,
        "body": body,
        "isBase64Encoded": is_b64,
    }
