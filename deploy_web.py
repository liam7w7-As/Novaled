import os
import sys
import subprocess
from ftplib import FTP
import zipfile
import time
import shutil
import re
import urllib.request
import urllib.error

FTP_HOST = "62.72.62.99"
FTP_USER = "sistema@novaledbolivia.com"  # Hostinger FTP accounts use email format: user@domain
FTP_PASS = "Patasca2029@"
FTP_PORT = 21

def build_web():
    print("Iniciando compilación de Flutter Web...")
    result = subprocess.run(
        ["flutter", "build", "web", "--base-href", "/sistema/"],
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    if result.returncode != 0:
        print("Error durante la compilación:")
        print(result.stderr)
        sys.exit(1)
    print("Compilación exitosa (build/web listo).")

def create_zip_archive(source_dir, output_zip_path):
    print(f"Creando archivo comprimido {output_zip_path}...")
    with zipfile.ZipFile(output_zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk(source_dir):
            for file in files:
                # Saltar credenciales restringidas
                if "daring-fin" in file:
                    continue
                # Evitar incluir el propio zip
                if file == os.path.basename(output_zip_path):
                    continue
                # Evitar incluir unzip.php si se copió
                if file == "unzip.php":
                    continue
                
                file_path = os.path.join(root, file)
                arcname = os.path.relpath(file_path, source_dir)
                zipf.write(file_path, arcname)
    print(f"Archivo zip creado con éxito ({os.path.getsize(output_zip_path)} bytes).")

def main():
    # 1. Compilar (Si se pasa --no-build se salta esta parte)
    if "--no-build" not in sys.argv:
        build_web()
    else:
        print("Saltando compilación (usando build existente)...")
    
    local_web_dir = os.path.join("build", "web")
    if not os.path.exists(local_web_dir):
        print(f"Error: La carpeta {local_web_dir} no existe. Por favor compila primero.")
        sys.exit(1)
        
    # Copiar .htaccess manualmente a build/web/ ya que flutter build lo ignora por defecto
    src_htaccess = os.path.join("web", ".htaccess")
    dst_htaccess = os.path.join(local_web_dir, ".htaccess")
    if os.path.exists(src_htaccess):
        try:
            shutil.copy(src_htaccess, dst_htaccess)
            print("Archivo .htaccess copiado con éxito a build/web/.")
        except Exception as e:
            print(f"Advertencia: No se pudo copiar .htaccess: {e}")

    # Copiar carpeta web/api a build/web/api ya que flutter build la omite
    src_api = os.path.join("web", "api")
    dst_api = os.path.join(local_web_dir, "api")
    if os.path.exists(src_api):
        try:
            if os.path.exists(dst_api):
                shutil.rmtree(dst_api)
            shutil.copytree(src_api, dst_api)
            print("Carpeta api copiada con éxito a build/web/api.")
        except Exception as e:
            print(f"Advertencia: No se pudo copiar api: {e}")

    # Generar un ID de versión único basado en el tiempo actual para forzar la recarga
    version_id = str(int(time.time()))
    print(f"Generando versión de caché única para despliegue: {version_id}")

    # 1. Aplicar cache-busting en index.html
    index_path = os.path.join(local_web_dir, "index.html")
    if os.path.exists(index_path):
        try:
            with open(index_path, "r", encoding="utf-8") as f:
                content = f.read()
            content = content.replace("flutter_bootstrap.js", f"flutter_bootstrap.js?v={version_id}")
            with open(index_path, "w", encoding="utf-8") as f:
                f.write(content)
            print("index.html actualizado con cache-busting.")
        except Exception as e:
            print(f"Advertencia al modificar index.html: {e}")

    # 2. Bypasear y remover el registro del Service Worker en flutter_bootstrap.js y forzar main.dart.js nuevo
    bootstrap_path = os.path.join(local_web_dir, "flutter_bootstrap.js")
    if os.path.exists(bootstrap_path):
        try:
            with open(bootstrap_path, "r", encoding="utf-8") as f:
                content = f.read()
                
            # Cache-busting para main.dart.js
            content = content.replace('"mainJsPath":"main.dart.js"', f'"mainJsPath":"main.dart.js?v={version_id}"')
            content = content.replace('"main.dart.js"', f'"main.dart.js?v={version_id}"')
            
            # Reemplazar la invocación del service worker con cargador limpio
            content_modified = re.sub(
                r'_flutter\.loader\.load\(\{\s*serviceWorkerSettings:\s*\{\s*serviceWorkerVersion:\s*"[^"]*"\s*(?:\/\*[^*]*\*\/)?\s*\}\s*\}\);',
                '_flutter.loader.load();',
                content
            )
            # También soportar variaciones en el espaciado
            if content_modified == content:
                content_modified = content.replace('serviceWorkerVersion: "310344328"', '')
            
            with open(bootstrap_path, "w", encoding="utf-8") as f:
                f.write(content_modified)
            print("Registro de Service Worker desactivado y cache-busting aplicado en flutter_bootstrap.js.")
        except Exception as e:
            print(f"Advertencia al modificar flutter_bootstrap.js: {e}")
        
    # 3. Crear el archivo ZIP
    zip_filename = "deploy.zip"
    zip_local_path = os.path.join("build", zip_filename)
    create_zip_archive(local_web_dir, zip_local_path)

    # 4. Conectar a servidor FTP y subir los archivos necesarios
    print(f"Conectando a servidor FTP {FTP_HOST}:{FTP_PORT}...")
    ftp = FTP()
    try:
        ftp.connect(FTP_HOST, FTP_PORT)
    except Exception as e:
        print(f"Error de conexión física FTP: {e}")
        sys.exit(1)
        
    usernames_to_try = [
        "u321709103.sistemanovaled",
        "u321709103.sistema",
        "u321709103.sistema@novaledbolivia.com",
        "sistema@novaledbolivia.com",
        "sistema",
    ]
    
    logged_in = False
    for username in usernames_to_try:
        try:
            print(f"Intentando login con usuario: '{username}'...")
            ftp.login(username, FTP_PASS)
            print(f"¡Login exitoso con usuario: '{username}'!")
            FTP_USER = username
            logged_in = True
            break
        except Exception as e:
            print(f"Fallo login con '{username}': {e}")
            
    if not logged_in:
        print("Error: No se pudo iniciar sesión con ningún formato de usuario FTP.")
        #print("Asegúrate de que creaste la cuenta FTP en Hostinger con la contraseña 'Patasca2029@'.")
        print("Asegúrate de que creaste la cuenta FTP en Hostinger.")
        sys.exit(1)
        
    # Intentar cambiar al directorio 'sistema' por si el login no es chrooted
    try:
        # Si estamos con cuenta principal, necesitaremos ir a public_html/sistema
        ftp.cwd("public_html/sistema")
        print("Cambiado a directorio: public_html/sistema")
    except Exception:
        try:
            ftp.cwd("sistema")
            print("Cambiado a directorio: sistema")
        except Exception:
            # Si ambos fallan, asumimos que ya estamos chrooted en el directorio destino
            print(f"Directorio actual FTP: {ftp.pwd()}")
            
    # Subir unzip.php
    local_unzip_php = os.path.join("web", "unzip.php")
    print(f"Subiendo script de descompresión unzip.php desde {local_unzip_php}...")
    try:
        with open(local_unzip_php, "rb") as f:
            ftp.storbinary("STOR unzip.php", f)
        print("unzip.php subido con éxito.")
    except Exception as e:
        print(f"Error al subir unzip.php: {e}")
        ftp.quit()
        sys.exit(1)

    # Subir deploy.zip
    print(f"Subiendo {zip_filename} ({os.path.getsize(zip_local_path) / (1024*1024):.2f} MB)...")
    start_time = time.time()
    try:
        with open(zip_local_path, "rb") as f:
            ftp.storbinary(f"STOR {zip_filename}", f)
        upload_time = time.time() - start_time
        print(f"deploy.zip subido con éxito en {upload_time:.2f} segundos.")
    except Exception as e:
        print(f"Error al subir deploy.zip: {e}")
        ftp.quit()
        sys.exit(1)
        
    ftp.quit()
    print("Conexión FTP cerrada.")

    # 5. Llamar al trigger HTTP para descomprimir en el servidor
    trigger_url = "https://novaledbolivia.com/sistema/unzip.php"
    print(f"Ejecutando trigger de descompresión remota en: {trigger_url}")
    
    try:
        # Añadimos un User-Agent para evitar que Hostinger bloquee la llamada como bot simple
        req = urllib.request.Request(
            trigger_url,
            headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AntigravityDeploymentHelper'}
        )
        with urllib.request.urlopen(req, timeout=60) as response:
            result_text = response.read().decode('utf-8')
            print("\n--- Respuesta del Servidor ---")
            print(result_text)
            print("------------------------------\n")
            if "SUCCESS" in result_text:
                print("¡Despliegue finalizado con éxito! La app ya está actualizada y disponible en https://novaledbolivia.com/sistema/")
                
                # Ejecutar script de migración para agregar columna id si falta
                migration_url = "https://novaledbolivia.com/sistema/api/add_id_column.php"
                print(f"Ejecutando trigger de migración de base de datos en: {migration_url}")
                try:
                    req_mig = urllib.request.Request(
                        migration_url,
                        headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AntigravityDeploymentHelper'}
                    )
                    with urllib.request.urlopen(req_mig, timeout=60) as resp_mig:
                        mig_text = resp_mig.read().decode('utf-8')
                        print("\n--- Respuesta de la Migración ---")
                        print(mig_text)
                        print("---------------------------------\n")
                except Exception as mig_ex:
                    print(f"Error al ejecutar la migración: {mig_ex}")
            else:
                print("Advertencia: El servidor respondió pero la descompresión podría no haber reportado éxito total.")
    except urllib.error.URLError as e:
        print(f"Error al conectar con el trigger HTTP: {e}")
        print("Por favor, abre la siguiente URL manualmente en tu navegador para forzar la descompresión:")
        print(trigger_url)

    # 6. Limpieza del archivo zip local
    try:
        if os.path.exists(zip_local_path):
            os.remove(zip_local_path)
            print("Limpieza local completada (deploy.zip eliminado).")
    except Exception as e:
        print(f"Advertencia: No se pudo eliminar el archivo local {zip_local_path}: {e}")

if __name__ == "__main__":
    main()
