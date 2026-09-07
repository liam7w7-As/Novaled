import sqlite3
import csv
import os

db_path = r'c:\Almir_trabajos\Novaled Sistema\backups\novaled_latest.db'
csv_dir = r'c:\Almir_trabajos\Novaled Sistema\backups\excel_csv'
os.makedirs(csv_dir, exist_ok=True)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
tables = [t[0] for t in cursor.fetchall() if not t[0].startswith('sqlite_')]

for t in tables:
    cursor.execute(f"SELECT * FROM {t}")
    cols = [desc[0] for desc in cursor.description]
    rows = cursor.fetchall()
    
    csv_file = os.path.join(csv_dir, f"{t}.csv")
    with open(csv_file, 'w', newline='', encoding='utf-8-sig') as f:
        writer = csv.writer(f)
        writer.writerow(cols)
        writer.writerows(rows)
    print(f"Exportado: {t}.csv ({len(rows)} filas)")

print("\n[OK] Todos los CSVs exportados en formato Excel UTF-8.")
