#!/usr/bin/env python3
"""
Bootstrap GitHub Actions OIDC identity provider and IAM role.

Creates:
  - OIDC Provider: token.actions.githubusercontent.com
  - IAM Role:      github-actions-terraform
  - Policies:      PowerUserAccess, IAMFullAccess (managed)
                   backup-passrole (inline, allows iam:PassRole on AWSBackupDefaultServiceRole)
                   ansible-ssm     (inline, allows SSM StartSession for Ansible)

Cannot be managed by Terraform itself (chicken-and-egg: needs the role to run).
Run once before the first GitHub Actions workflow execution.

Note: backup-passrole is also managed by Terraform (02-security/main.tf).
      Terraform will overwrite it on the first apply — that's fine.

Usage:
    python3 scripts/bootstrap_github_oidc.py
"""

import json
import sys
import boto3
from botocore.exceptions import ClientError

# --- Config ---
GITHUB_ORG = "skratzsch"               # GitHub org or username
GITHUB_REPO = "*"                      # "*" = all repos of that org, or e.g. "aws-associate-playground"
ROLE_NAME = "github-actions-terraform"
REGION = "eu-central-1"

OIDC_URL = "https://token.actions.githubusercontent.com"
OIDC_CLIENT_ID = "sts.amazonaws.com"

# GitHub's well-known OIDC thumbprints (both intermediate CAs)
OIDC_THUMBPRINTS = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
]

MANAGED_POLICIES = [
    "arn:aws:iam::aws:policy/PowerUserAccess",
    "arn:aws:iam::aws:policy/IAMFullAccess",
]


def get_account_id(sts):
    return sts.get_caller_identity()["Account"]


def ensure_oidc_provider(iam, account_id):
    provider_arn = f"arn:aws:iam::{account_id}:oidc-provider/token.actions.githubusercontent.com"
    print(f"Checking OIDC provider: {OIDC_URL}")
    try:
        iam.get_open_id_connect_provider(OpenIDConnectProviderArn=provider_arn)
        print("  OIDC provider already exists, skipping.\n")
        return provider_arn
    except ClientError as e:
        if e.response["Error"]["Code"] != "NoSuchEntityException":
            raise

    print("  Creating OIDC provider...")
    response = iam.create_open_id_connect_provider(
        Url=OIDC_URL,
        ClientIDList=[OIDC_CLIENT_ID],
        ThumbprintList=OIDC_THUMBPRINTS,
    )
    provider_arn = response["OpenIDConnectProviderArn"]
    print(f"  OIDC provider created: {provider_arn}\n")
    return provider_arn


def build_trust_policy(provider_arn):
    return json.dumps({
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Federated": provider_arn
                },
                "Action": "sts:AssumeRoleWithWebIdentity",
                "Condition": {
                    "StringEquals": {
                        "token.actions.githubusercontent.com:aud": OIDC_CLIENT_ID
                    },
                    "StringLike": {
                        "token.actions.githubusercontent.com:sub": f"repo:{GITHUB_ORG}/{GITHUB_REPO}:*"
                    }
                }
            }
        ]
    })


def ensure_role(iam, provider_arn):
    print(f"Checking IAM role: {ROLE_NAME}")
    try:
        response = iam.get_role(RoleName=ROLE_NAME)
        print("  Role already exists, skipping creation.\n")
        return response["Role"]["Arn"]
    except ClientError as e:
        if e.response["Error"]["Code"] != "NoSuchEntityException":
            raise

    print("  Creating IAM role...")
    response = iam.create_role(
        RoleName=ROLE_NAME,
        AssumeRolePolicyDocument=build_trust_policy(provider_arn),
        Description="Role for GitHub Actions Terraform deployments",
    )
    role_arn = response["Role"]["Arn"]
    print(f"  Role created: {role_arn}\n")
    return role_arn


def attach_managed_policies(iam):
    print("Attaching managed policies...")
    existing = set()
    paginator = iam.get_paginator("list_attached_role_policies")
    for page in paginator.paginate(RoleName=ROLE_NAME):
        for p in page["AttachedPolicies"]:
            existing.add(p["PolicyArn"])

    for policy_arn in MANAGED_POLICIES:
        if policy_arn in existing:
            print(f"  Already attached: {policy_arn.split('/')[-1]}")
        else:
            iam.attach_role_policy(RoleName=ROLE_NAME, PolicyArn=policy_arn)
            print(f"  Attached: {policy_arn.split('/')[-1]}")
    print()


def put_backup_passrole_policy(iam, account_id):
    policy_name = "backup-passrole"
    backup_role_arn = f"arn:aws:iam::{account_id}:role/AWSBackupDefaultServiceRole"
    print(f"Putting inline policy: {policy_name}")
    iam.put_role_policy(
        RoleName=ROLE_NAME,
        PolicyName=policy_name,
        PolicyDocument=json.dumps({
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": "iam:PassRole",
                    "Resource": backup_role_arn
                }
            ]
        })
    )
    print(f"  Inline policy set (resource: {backup_role_arn})\n")


def put_ansible_ssm_policy(iam):
    policy_name = "ansible-ssm"
    print(f"Putting inline policy: {policy_name}")
    iam.put_role_policy(
        RoleName=ROLE_NAME,
        PolicyName=policy_name,
        PolicyDocument=json.dumps({
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "ssm:StartSession",
                        "ssm:TerminateSession",
                        "ssm:ResumeSession",
                        "ssm:DescribeInstanceInformation",
                        "ssm:GetConnectionStatus"
                    ],
                    "Resource": "*"
                }
            ]
        })
    )
    print(f"  Inline policy set\n")


def main():
    session = boto3.Session(region_name=REGION)
    sts = session.client("sts")
    iam = session.client("iam")

    try:
        account_id = get_account_id(sts)
        print(f"AWS account: {account_id}\n")

        provider_arn = ensure_oidc_provider(iam, account_id)
        ensure_role(iam, provider_arn)
        attach_managed_policies(iam)
        put_backup_passrole_policy(iam, account_id)
        put_ansible_ssm_policy(iam)

    except ClientError as e:
        print(f"\nAWS error: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Bootstrap complete. Role ARN: arn:aws:iam::{account_id}:role/{ROLE_NAME}")


if __name__ == "__main__":
    main()
