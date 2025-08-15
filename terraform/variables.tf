variable "aws_region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1" # óptima para latencia desde Colombia
}

variable "source_email" {
  description = "Correo verificado en SES desde el cual se enviarán las alertas"
  type        = string
}

variable "destination_email" {
  description = "Correo destino que recibirá la alerta"
  type        = string
}

variable "intake_reserved_concurrency" {
  description = "Concurrent executions reserved for intake Lambda"
  type        = number
  default     = 4
}

variable "processor_reserved_concurrency" {
  description = "Concurrent executions reserved for processor Lambda"
  type        = number
  default     = 4
}
