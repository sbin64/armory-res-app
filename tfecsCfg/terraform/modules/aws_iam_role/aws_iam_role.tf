resource "aws_iam_role" "this" {
  name               = var.name
  description        = var.description
  assume_role_policy = var.assume_role_policy

  dynamic "inline_policy" {
    for_each = { for key, value in var.inline_policy : key => value if value["policy"] != "" } # Skip policies
    content {
      name   = inline_policy.value["name"]
      policy = inline_policy.value["policy"]
    }
  }
  force_detach_policies = var.force_detach_policies
  tags                  = var.tags
}


