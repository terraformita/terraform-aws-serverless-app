output "bucket" {
  value = {
    arn = aws_s3_bucket.gui.arn
    id  = aws_s3_bucket.gui.id
  }
}
