import sqlite3

db_path = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\novaled.db"
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

cursor.execute("SELECT COUNT(*) as count FROM articulos")
total = cursor.fetchone()['count']
print("Total existing articles in DB:", total)

cursor.execute("SELECT * FROM articulos LIMIT 10")
rows = cursor.fetchall()
for idx, r in enumerate(rows, 1):
    print(f"\n--- Article {idx} ---")
    for col in r.keys():
        print(f"  {col}: {r[col]}")
        
conn.close()
