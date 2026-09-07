import sqlite3

db_path = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\novaled.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("SELECT id, nombreCompania FROM clientes WHERE id >= 220")
rows = cursor.fetchall()
print(f"Total newly imported clients: {len(rows)}")

accented_new = []
for r_id, name in rows:
    high_chars = [c for c in name if ord(c) > 127]
    if high_chars:
        accented_new.append((r_id, name, [ord(c) for c in name]))

print(f"Newly imported clients with non-ASCII: {len(accented_new)}")
for item in accented_new[:10]:
    print(f"ID: {item[0]}, Name: {item[1]}, Codes: {item[2]}")
    
conn.close()
