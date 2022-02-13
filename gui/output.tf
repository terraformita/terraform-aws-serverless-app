output "out" {
  value = {
    s3-bucket-arn = aws_s3_bucket.gui.arn
    s3-bucket-id  = aws_s3_bucket.gui.id
  }
}
