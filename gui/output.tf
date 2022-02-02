output "out" {
  value = {
    s3-bucket-arn = module.gui-bucket.s3_bucket_arn
    s3-bucket-id  = module.gui-bucket.s3_bucket_id
  }
}
