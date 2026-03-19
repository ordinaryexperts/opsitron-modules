# LZA Foundation Module
#
# This module wraps the AWS Landing Zone Accelerator (LZA) CloudFormation
# deployment, providing a standardized way to deploy LZA for Platform clients.
#
# The module:
# - Deploys the LZA installer CloudFormation stack
# - Stores LZA configuration in SSM for Platform integration
# - Configures Lambda concurrency limits for new account compatibility

locals {
  stack_name = "AWSAccelerator-Installer"

  # LZA CloudFormation template URL - pinned to specific version for predictable deployments.
  # Updating this module version may trigger an LZA upgrade (60-90 minute process).
  # See: https://github.com/awslabs/landing-zone-accelerator-on-aws/releases
  lza_template_url = "https://s3.amazonaws.com/solutions-reference/landing-zone-accelerator-on-aws/v1.14.2/AWSAccelerator-InstallerStack.template"

  # LZA configuration defaults
  lza_config = {
    accelerator_prefix          = var.accelerator_prefix
    management_account_email    = var.management_account_email
    log_archive_account_email   = var.log_archive_account_email
    audit_account_email         = var.audit_account_email
    control_tower_enabled       = var.control_tower_enabled
    enable_approval_stage       = var.enable_approval_stage
    approval_stage_notify_email = var.approval_stage_notify_email
  }

  # S3 bucket name for LZA configuration (created automatically by LZA when using S3 source)
  config_bucket_name = "aws-accelerator-config-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.id}"

  tags = merge(var.tags, {
    ManagedBy    = "OE-Platform"
    Module       = "lza-foundation"
    ModuleSource = "github.com/ordinaryexperts/platform-modules//modules/lza-foundation"
  })
}

# Data source to get current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Prerequisite: GitHub token must exist in Secrets Manager before deploying LZA.
# The LZA pipeline uses this token to access the LZA source code repository.
# Create it manually: aws secretsmanager create-secret --name accelerator/github-token --secret-string <PAT>
# See: https://docs.aws.amazon.com/solutions/latest/landing-zone-accelerator-on-aws/prerequisites.html
data "aws_secretsmanager_secret" "github_token" {
  name = var.github_token_secret_name
}

# Deploy the LZA Installer CloudFormation stack
resource "aws_cloudformation_stack" "lza_installer" {
  name         = local.stack_name
  capabilities = ["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND"]

  # LZA CloudFormation template URL - pinned in locals
  template_url = local.lza_template_url

  parameters = {
    # LZA source code repository settings
    RepositorySource     = var.lza_source_location
    RepositoryOwner      = var.lza_source_owner
    RepositoryName       = var.lza_source_repo_name
    RepositoryBranchName = var.lza_source_branch

    # LZA configuration repository location - always S3
    # The GitHub workflow uploads config files to S3, enabling deploy-before-merge
    ConfigurationRepositoryLocation = "s3"

    # Core LZA settings
    AcceleratorPrefix      = local.lza_config.accelerator_prefix
    ManagementAccountEmail = local.lza_config.management_account_email
    LogArchiveAccountEmail = local.lza_config.log_archive_account_email
    AuditAccountEmail      = local.lza_config.audit_account_email
    ControlTowerEnabled    = local.lza_config.control_tower_enabled ? "Yes" : "No"

    # Pipeline settings
    EnableApprovalStage          = local.lza_config.enable_approval_stage ? "Yes" : "No"
    ApprovalStageNotifyEmailList = local.lza_config.approval_stage_notify_email

    # Diagnostics
    EnableDiagnosticsPack = var.enable_diagnostics_pack ? "Yes" : "No"
  }

  tags = local.tags

  # LZA deployment can take a while
  timeouts {
    create = "90m"
    update = "90m"
    delete = "60m"
  }
}

# Update the Toolkit CodeBuild project with Lambda concurrency limit
# This bypasses the Lambda concurrent execution validation that fails on new accounts
# See: https://github.com/awslabs/landing-zone-accelerator-on-aws/issues/984
#
# IMPORTANT: The LZA Pipeline creates the ToolkitProject AFTER the Installer stack completes.
# We must wait for the Pipeline to finish its initial run before modifying the project,
# otherwise the Pipeline will overwrite our changes.
resource "null_resource" "toolkit_lambda_concurrency" {
  count = var.lambda_concurrency_limit > 0 ? 1 : 0

  triggers = {
    stack_id          = aws_cloudformation_stack.lza_installer.id
    concurrency_limit = var.lambda_concurrency_limit
  }

  provisioner "local-exec" {
    environment = {
      AWS_REGION    = data.aws_region.current.name
      PROJECT_NAME  = "${var.accelerator_prefix}-ToolkitProject"
      PIPELINE_NAME = "${var.accelerator_prefix}-Pipeline"
      CONCURRENCY   = var.lambda_concurrency_limit
    }

    command = <<-EOT
      set -e

      echo "Waiting for LZA Pipeline to create ToolkitProject..."

      # Wait for the ToolkitProject to exist (max 10 minutes)
      MAX_WAIT=600
      WAITED=0
      while [ $WAITED -lt $MAX_WAIT ]; do
        if aws codebuild batch-get-projects --names "$PROJECT_NAME" --query 'projects[0].name' --output text 2>/dev/null | grep -q "$PROJECT_NAME"; then
          echo "ToolkitProject found after $${WAITED}s"
          break
        fi
        echo "Waiting for ToolkitProject to be created... ($${WAITED}s)"
        sleep 30
        WAITED=$((WAITED + 30))
      done

      if [ $WAITED -ge $MAX_WAIT ]; then
        echo "ERROR: ToolkitProject not found after $${MAX_WAIT}s"
        exit 1
      fi

      # Wait for the Pipeline to not be in progress (max 30 minutes)
      # The Pipeline runs automatically after the Installer stack and creates/updates ToolkitProject
      echo "Waiting for LZA Pipeline to stabilize..."
      MAX_PIPELINE_WAIT=1800
      WAITED=0
      while [ $WAITED -lt $MAX_PIPELINE_WAIT ]; do
        PIPELINE_STATE=$(aws codepipeline get-pipeline-state --name "$PIPELINE_NAME" \
          --query 'stageStates[0].latestExecution.status' --output text 2>/dev/null || echo "Unknown")

        if [ "$PIPELINE_STATE" = "Succeeded" ] || [ "$PIPELINE_STATE" = "Failed" ] || [ "$PIPELINE_STATE" = "Unknown" ]; then
          echo "Pipeline state: $PIPELINE_STATE - proceeding with update"
          break
        fi

        echo "Pipeline is $PIPELINE_STATE, waiting... ($${WAITED}s)"
        sleep 60
        WAITED=$((WAITED + 60))
      done

      # Now update the ToolkitProject with the concurrency limit
      echo "Updating ToolkitProject with ACCELERATOR_LAMBDA_CONCURRENCY_LIMIT=$CONCURRENCY"

      # Get current environment variables from the Toolkit project
      CURRENT_ENV=$(aws codebuild batch-get-projects \
        --names "$PROJECT_NAME" \
        --query 'projects[0].environment.environmentVariables' \
        --output json)

      # Handle null or empty environment variables
      if [ "$CURRENT_ENV" = "null" ] || [ -z "$CURRENT_ENV" ]; then
        CURRENT_ENV="[]"
      fi

      # Add the concurrency limit variable (unique_by prevents duplicates)
      NEW_ENV=$(echo "$CURRENT_ENV" | jq --arg limit "$CONCURRENCY" \
        '. + [{"name": "ACCELERATOR_LAMBDA_CONCURRENCY_LIMIT", "value": $limit, "type": "PLAINTEXT"}] | unique_by(.name)')

      # Get full environment config and update variables, writing to temp file
      TEMP_FILE=$(mktemp)
      aws codebuild batch-get-projects \
        --names "$PROJECT_NAME" \
        --query 'projects[0].environment' \
        --output json | jq --argjson envVars "$NEW_ENV" '.environmentVariables = $envVars' > "$TEMP_FILE"

      # Update the CodeBuild project using file input
      aws codebuild update-project \
        --name "$PROJECT_NAME" \
        --environment "file://$TEMP_FILE"

      rm -f "$TEMP_FILE"
      echo "Successfully added ACCELERATOR_LAMBDA_CONCURRENCY_LIMIT=$CONCURRENCY to $PROJECT_NAME"
    EOT
  }

  depends_on = [aws_cloudformation_stack.lza_installer]
}

# Store LZA configuration in SSM for Platform to retrieve
resource "aws_ssm_parameter" "lza_config" {
  name        = "/${var.accelerator_prefix}/platform/config"
  description = "LZA configuration for OE Platform integration"
  type        = "String"
  value = jsonencode({
    accelerator_prefix    = var.accelerator_prefix
    lza_source_repo       = var.lza_source_repo_name
    management_account_id = data.aws_caller_identity.current.account_id
    region                = data.aws_region.current.id
    pipeline_name         = "${var.accelerator_prefix}-Pipeline"
    config_bucket         = local.config_bucket_name
  })

  tags = local.tags
}

# IAM user for GitHub Actions to poll pipeline status during long-running deployments.
# OIDC tokens expire after ~1 hour, but LZA pipelines can take 1.5-2+ hours.
# This user has minimal read-only permissions for polling only.
#
# Access keys are NOT created here - staff generates them via AWS Console
# and stores them in the lza-config repo's GitHub secrets.
resource "aws_iam_user" "pipeline_poller" {
  name = "${var.accelerator_prefix}-pipeline-poller"
  path = "/lza/"

  tags = merge(local.tags, {
    Purpose = "GitHub Actions pipeline status polling"
  })
}

resource "aws_iam_user_policy" "pipeline_poller" {
  name = "pipeline-poll-only"
  user = aws_iam_user.pipeline_poller.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowPipelineStatusPolling"
        Effect   = "Allow"
        Action   = "codepipeline:GetPipelineExecution"
        Resource = "arn:aws:codepipeline:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${var.accelerator_prefix}-Pipeline"
      }
    ]
  })
}
