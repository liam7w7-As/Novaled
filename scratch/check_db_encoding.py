import sqlite3

db_path = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\novaled.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("SELECT id, nombreCompania FROM clientes WHERE nombreCompania LIKE '%Yasmani%'")
rows = cursor.fetchall()
for r_id, name in rows:
    print(f"ID: {r_id}, name: {name}, char codes: {[ord(c) for c in name]}")
    
conn.close()
