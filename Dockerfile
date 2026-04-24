# Imagen base oficial de Python 3.12 (variante slim).
# slim reduce el tamaño eliminando herramientas del SO no esenciales.
# Python 3.12 tiene soporte activo hasta 2028.
FROM python:3.12-slim

# Directorio de trabajo dentro del contenedor
WORKDIR /app

# Copia solo requirements primero para aprovechar el cache de Docker.
# Si requirements.txt no cambia, Docker reutiliza esta capa en builds posteriores.
COPY requirements.txt .

# Instala dependencias. --no-cache-dir reduce el tamaño de la imagen.
RUN pip install --no-cache-dir -r requirements.txt

# Copia el resto del código después de instalar dependencias
COPY . .

# Puerto fijo en el que Gunicorn servirá la aplicación
EXPOSE 8000

# app.app:app = paquete app/, módulo app.py, objeto Flask llamado app
CMD ["gunicorn", "--workers=2", "--bind=0.0.0.0:8000", "app.app:app"]
