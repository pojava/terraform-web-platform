resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name}-${var.environment}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_actions       = [aws_sns_topic.alert.arn]
  dimensions = {
    AutoScalingGroupName = var.asg_name
  }
}

resource "aws_sns_topic" "alert" {
  name = "${var.name}-${var.environment}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alert.arn
  protocol  = "email"
  endpoint  = var.alert_email
}