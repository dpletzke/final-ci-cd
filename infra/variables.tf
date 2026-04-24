# infra/variables.tf

variable "environment_name" {
  description = "Nombre del entorno: staging o production."
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment_name)
    error_message = "El entorno debe ser 'staging' o 'production'."
  }
}

variable "project_name" {
  description = "Prefijo consistente para nombrar recursos del proyecto."
  type        = string
  default     = "final-ci-cd"
}

variable "docker_image_uri" {
  description = "URI completo de la imagen Docker (ej: usuario/repo:sha)."
  type        = string
}

variable "lab_role_arn" {
  description = "ARN del rol IAM 'LabRole' de AWS Academy."
  type        = string
}

variable "vpc_id" {
  description = "ID de la VPC por defecto donde desplegar."
  type        = string
}

variable "subnet_ids" {
  description = "Lista de al menos 2 IDs de subredes públicas en diferentes AZs."
  type        = list(string)
}

variable "aws_region" {
  description = "Región de AWS."
  type        = string
  default     = "us-east-1"
}

variable "secret_key" {
  description = "Clave secreta para Flask. Nunca se imprime en logs."
  type        = string
  sensitive   = true
  default     = "dev-only-insecure-key"
}
