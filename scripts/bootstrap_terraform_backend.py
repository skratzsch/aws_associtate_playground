#!/usr/bin/env python3
"""
Bootstrap Terraform remote state backend.

Creates:
  - S3 bucket for state files (versioning, encryption, no public access)
  - DynamoDB table for state locking

These resources cannot be managed by Terraform itself (chicken-and-egg).
Run once before the first `terraform init`.

Usage:
    python3 scripts/bootstrap_terraform_backend.py
    # or via AWS CLI wrapper if boto3 is not installed:
    # aws-vault exec <profile> -- python3 scripts/bootstrap_terraform_backend.py
"""

import sys
import boto3
from botocore.exceptions import ClientError

BUCKET_NAME = "aws-associate-playground-terraform-state"
DYNAMODB_TABLE = "terraform-state-lock"
REGION = "eu-central-1"


def create_state_bucket(s3):
    print(f"Creating S3 bucket: {BUCKET_NAME}")
    try:
        s3.create_bucket(
            Bucket=BUCKET_NAME,
            CreateBucketConfiguration={"LocationConstraint": REGION},
        )
        print("  Bucket created.")
    except ClientError as e:
        if e.response["Error"]["Code"] in ("BucketAlreadyOwnedByYou", "BucketAlreadyExists"):
            print("  Bucket already exists, skipping.")
        else:
            raise

    print("  Enabling versioning...")
    s3.put_bucket_versioning(
        Bucket=BUCKET_NAME,
        VersioningConfiguration={"Status": "Enabled"},
    )

    print("  Enabling server-side encryption (SSE-S3)...")
    s3.put_bucket_encryption(
        Bucket=BUCKET_NAME,
        ServerSideEncryptionConfiguration={
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256",
                    },
                    "BucketKeyEnabled": True,
                }
            ]
        },
    )

    print("  Blocking all public access...")
    s3.put_public_access_block(
        Bucket=BUCKET_NAME,
        PublicAccessBlockConfiguration={
            "BlockPublicAcls": True,
            "IgnorePublicAcls": True,
            "BlockPublicPolicy": True,
            "RestrictPublicBuckets": True,
        },
    )

    print(f"  S3 bucket ready: {BUCKET_NAME}\n")


def create_lock_table(dynamodb):
    print(f"Creating DynamoDB table: {DYNAMODB_TABLE}")
    try:
        dynamodb.create_table(
            TableName=DYNAMODB_TABLE,
            AttributeDefinitions=[
                {"AttributeName": "LockID", "AttributeType": "S"},
            ],
            KeySchema=[
                {"AttributeName": "LockID", "KeyType": "HASH"},
            ],
            BillingMode="PAY_PER_REQUEST",
        )
        print("  Waiting for table to become active...")
        waiter = dynamodb.get_waiter("table_exists")
        waiter.wait(TableName=DYNAMODB_TABLE)
        print(f"  DynamoDB table ready: {DYNAMODB_TABLE}\n")
    except ClientError as e:
        if e.response["Error"]["Code"] == "ResourceInUseException":
            print("  Table already exists, skipping.\n")
        else:
            raise


def main():
    session = boto3.Session(region_name=REGION)
    s3 = session.client("s3")
    dynamodb = session.client("dynamodb")

    try:
        create_state_bucket(s3)
        create_lock_table(dynamodb)
    except ClientError as e:
        print(f"\nAWS error: {e}", file=sys.stderr)
        sys.exit(1)

    print("Bootstrap complete. You can now run `terraform init` in any module.")


if __name__ == "__main__":
    main()
