import sqlite3

db_path = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\novaled.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("SELECT COUNT(*) FROM clientes WHERE folderId IS NOT NULL AND folderId != ''")
synced = cursor.fetchone()[0]

cursor.execute("SELECT COUNT(*) FROM clientes")
total = cursor.fetchone()[0]

print(f"Synced to Drive: {synced} / {total}")
conn.close()
