import os
import sqlite3
from collections import defaultdict

db_path = os.path.expandvars(r"%APPDATA%\com.example\novaled_app\novaled.db")

if not os.path.exists(db_path):
    print(f"Error: Database file not found at {db_path}")
    # Try alternate path if APPDATA is different
    alt_path = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\novaled.db"
    if os.path.exists(alt_path):
        db_path = alt_path
    else:
        print("Could not find database anywhere.")
        exit(1)

print(f"Connecting to database: {db_path}")
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Query all articles
cursor.execute("SELECT id, nombre, precio, familia, subcategoria, folderId, finalArtId FROM articulos")
rows = cursor.fetchall()

print(f"Total articles in DB: {len(rows)}")

# Group by normalized name
grouped = defaultdict(list)
for r in rows:
    art_id, nombre, precio, familia, subcategoria, folderId, finalArtId = r
    normalized = nombre.strip().lower()
    grouped[normalized].append({
        'id': art_id,
        'nombre': nombre,
        'precio': precio,
        'familia': familia,
        'subcategoria': subcategoria,
        'folderId': folderId,
        'finalArtId': finalArtId
    })

duplicates = {k: v for k, v in grouped.items() if len(v) > 1}

print(f"Found {len(duplicates)} duplicate groups.")

total_dups_count = 0
for name, list_arts in duplicates.items():
    print(f"\nDuplicate Name: '{list_arts[0]['nombre']}' ({len(list_arts)} occurrences)")
    for art in list_arts:
        print(f"  - ID: {art['id']}, Price: {art['precio']}, Fam: {art['familia']}, Sub: {art['subcategoria']}, FolderId: {art['folderId']}, FinalArtId: {art['finalArtId']}")
    total_dups_count += len(list_arts) - 1

print(f"\nTotal duplicate rows to delete: {total_dups_count}")
conn.close()
