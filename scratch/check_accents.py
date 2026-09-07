import sqlite3

db_path = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\novaled.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("SELECT id, nombreCompania FROM clientes")
rows = cursor.fetchall()
non_ascii = []
for r_id, name in rows:
    high_chars = [c for c in name if ord(c) > 127]
    if high_chars:
        non_ascii.append((r_id, name, [ord(c) for c in name]))
        
print(f"Total clients with non-ASCII characters: {len(non_ascii)}")
for item in non_ascii[:20]:
    print(f"ID: {item[0]}, Name: {item[1]}, Codes: {item[2]}")
    
conn.close()
