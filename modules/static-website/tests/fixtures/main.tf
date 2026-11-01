# modules/static-website/tests/fixtures/main.tf
data "aws_ssm_parameter" "certificate_arn" {
  name = "/platform-test/static-website/certificate-arn"
}

data "aws_ssm_parameter" "test_domain" {
  name = "/platform-test/static-website/test-domain"
}

resource "random_id" "test" {
  byte_length = 4
}

output "certificate_arn" {
  value = data.aws_ssm_parameter.certificate_arn.value
}

output "test_domain" {
  value = data.aws_ssm_parameter.test_domain.value
}

output "test_id" {
  value = random_id.test.hex
}
