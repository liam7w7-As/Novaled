import sqlite3
import json
import os

db_path = r'c:\Almir_trabajos\Novaled Sistema\backups\novaled_latest.db'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Obtener todas las tablas
cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
tables = [t[0] for t in cursor.fetchall()]

backup_data = {}
print("=== CONTENIDO DE LA BASE DE DATOS ===")
for t in tables:
    cursor.execute(f"SELECT * FROM {t}")
    cols = [desc[0] for desc in cursor.description]
    rows = cursor.fetchall()
    backup_data[t] = [dict(zip(cols, row)) for row in rows]
    print(f"  • Tabla '{t}': {len(rows)} registros")

# Guardar JSON completo
json_out = r'c:\Almir_trabajos\Novaled Sistema\backups\novaled_historial_completo.json'
with open(json_out, 'w', encoding='utf-8') as f:
    json.dump(backup_data, f, ensure_ascii=False, indent=2)

print(f"\n[OK] Copia de seguridad exportada en: {json_out}")
