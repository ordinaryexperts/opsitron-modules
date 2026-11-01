# modules/lza-foundation/tests/fixtures/main.tf
data "aws_ssm_parameter" "github_oidc_provider_arn" {
  name = "/platform-test/lza-foundation/github-oidc-provider-arn"
}

output "github_oidc_provider_arn" {
  value = data.aws_ssm_parameter.github_oidc_provider_arn.value
}
