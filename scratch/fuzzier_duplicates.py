import os
import sqlite3
import re
import unicodedata
from collections import defaultdict

db_path = os.path.expandvars(r"%APPDATA%\com.example\novaled_app\novaled.db")
if not os.path.exists(db_path):
    db_path = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\novaled.db"

def clean_text(text):
    if not text:
        return ""
    # Remove accents
    text = ''.join(c for c in unicodedata.normalize('NFD', text) if unicodedata.category(c) != 'Mn')
    # Lowercase and remove all non-alphanumeric characters
    text = re.sub(r'[^a-zA-Z0-9]', '', text).lower()
    return text

print(f"Connecting to database: {db_path}")
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("SELECT id, nombre, precio, familia, subcategoria, folderId, finalArtId FROM articulos")
rows = cursor.fetchall()

grouped = defaultdict(list)
for r in rows:
    art_id, nombre, precio, familia, subcategoria, folderId, finalArtId = r
    cleaned = clean_text(nombre)
    grouped[cleaned].append({
        'id': art_id,
        'nombre': nombre,
        'precio': precio,
        'familia': familia,
        'subcategoria': subcategoria,
        'folderId': folderId,
        'finalArtId': finalArtId
    })

duplicates = {k: v for k, v in grouped.items() if len(v) > 1}
print(f"Found {len(duplicates)} duplicate groups with fuzzy matching.")

for i, (key, list_arts) in enumerate(duplicates.items(), 1):
    # Only print first 10 groups to avoid cluttering if there are too many, but show count
    if i <= 15:
        print(f"\nGroup {i}: Key '{key}'")
        for art in list_arts:
            print(f"  - ID: {art['id']}, Name: '{art['nombre']}', Price: {art['precio']}, FolderId: {art['folderId']}")
    elif i == 16:
        print("\n... and more groups ...")

print(f"\nTotal duplicate groups: {len(duplicates)}")
conn.close()
