locals {
  tags = merge(
    {
      Project     = var.cluster_name
      ManagedBy   = "terraform"
      Environment = "poc"
    },
    var.tags
  )
}
