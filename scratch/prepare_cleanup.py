import os
import sqlite3
import re
import unicodedata
from datetime import datetime

db_path = os.path.expandvars(r"%APPDATA%\com.example\novaled_app\novaled.db")
if not os.path.exists(db_path):
    db_path = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\novaled.db"

csv_path = r"C:\Almir_trabajos\Novaled Sistema\base de datos\lista de inventario.csv"

def clean_text(text):
    if not text:
        return ""
    text = ''.join(c for c in unicodedata.normalize('NFD', text) if unicodedata.category(c) != 'Mn')
    text = re.sub(r'[^a-zA-Z0-9]', '', text).lower()
    return text

# Parse CSV to find the latest date and price for each normalized name
csv_data = {}
if os.path.exists(csv_path):
    with open(csv_path, 'r', encoding='utf-8-sig', errors='ignore') as f:
        for line in f:
            parts = line.strip().split(',')
            if len(parts) >= 4:
                nombre = parts[0].strip()
                precio_str = parts[1].strip()
                date_str = parts[3].strip()
                
                cleaned = clean_text(nombre)
                try:
                    precio = float(precio_str) if precio_str else 0.0
                except ValueError:
                    precio = 0.0
                
                # Try to parse date
                try:
                    date_obj = datetime.strptime(date_str, "%Y/%m/%d")
                except ValueError:
                    date_obj = datetime.min
                
                if cleaned not in csv_data or date_obj > csv_data[cleaned]['date']:
                    csv_data[cleaned] = {
                        'nombre': nombre,
                        'precio': precio,
                        'date_str': date_str,
                        'date': date_obj
                    }

# Connect to DB
conn = sqlite3.connect(db_path)
cursor = conn.cursor()
cursor.execute("SELECT id, nombre, precio, familia, subcategoria, folderId, finalArtId FROM articulos")
rows = cursor.fetchall()

# Group by normalized name
from collections import defaultdict
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

print(f"Analyzing {len(duplicates)} duplicate groups...")

deletions = []
preserves = []

for key, list_arts in duplicates.items():
    print(f"\nGroup for key '{key}':")
    for art in list_arts:
        print(f"  - ID: {art['id']}, Name: '{art['nombre']}', Price: {art['precio']}, FolderId: {art['folderId']}, FinalArtId: {art['finalArtId']}")
    
    # Selection algorithm
    # 1. Prefer ones with finalArtId
    arts_with_final = [a for a in list_arts if a['finalArtId']]
    if len(arts_with_final) == 1:
        best = arts_with_final[0]
        reason = "has finalArtId"
    else:
        # 2. Prefer the one matching the latest CSV record (by price or name)
        csv_match = csv_data.get(key)
        if csv_match:
            # Look for exact price match or closest name
            arts_with_csv_price = [a for a in list_arts if abs(a['precio'] - csv_match['precio']) < 0.01]
            if len(arts_with_csv_price) == 1:
                best = arts_with_csv_price[0]
                reason = f"matches latest CSV price ({csv_match['precio']} on {csv_match['date_str']})"
            else:
                # 3. Prefer the one with accents/proper spelling
                accented = [a for a in list_arts if any(c in a['nombre'] for c in 'áéíóúÁÉÍÓÚñÑ')]
                if len(accented) == 1:
                    best = accented[0]
                    reason = "proper Spanish spelling (accents)"
                else:
                    # 4. Fallback: longest name or first
                    best = max(list_arts, key=lambda x: len(x['nombre']))
                    reason = "longest name / fallback"
        else:
            # No CSV record, fallback to accents or longest
            accented = [a for a in list_arts if any(c in a['nombre'] for c in 'áéíóúÁÉÍÓÚñÑ')]
            if len(accented) == 1:
                best = accented[0]
                reason = "proper Spanish spelling (accents)"
            else:
                best = list_arts[0]
                reason = "default first"
                
    print(f"  --> DECISION: Preserve ID {best['id']} (Reason: {reason})")
    
    for art in list_arts:
        if art['id'] != best['id']:
            deletions.append(art)
    preserves.append(best)

print(f"\nSummary of planned deletions:")
print(f"Total rows to delete: {len(deletions)}")
for d in deletions:
    print(f"  Delete ID {d['id']}: '{d['nombre']}' | Price: {d['precio']} | Folder: {d['folderId']}")

conn.close()
