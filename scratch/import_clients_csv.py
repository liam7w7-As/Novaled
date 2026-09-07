import sqlite3
import csv
import os

db_path = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\novaled.db"
csv_path = r"C:\Almir_trabajos\Novaled Sistema\base de datos\lista de clientes.csv"

def run_import():
    print(f"Connecting to database: {db_path}")
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # 1. Upgrade schema if the new columns don't exist yet
    cursor.execute("PRAGMA table_info(clientes)")
    columns = [col[1] for col in cursor.fetchall()]
    print(f"Existing columns in 'clientes' table: {columns}")
    
    new_cols = {
        'rn': 'TEXT DEFAULT ""',
        'direccion1': 'TEXT DEFAULT ""',
        'direccion2': 'TEXT DEFAULT ""',
        'direccion3': 'TEXT DEFAULT ""',
        'direccionEnvio1': 'TEXT DEFAULT ""',
        'direccionEnvio2': 'TEXT DEFAULT ""',
        'direccionEnvio3': 'TEXT DEFAULT ""',
        'infoAdicional': 'TEXT DEFAULT ""',
        'folderId': 'TEXT'
    }
    
    for col_name, col_type in new_cols.items():
        if col_name not in columns:
            print(f"Adding column '{col_name}' to 'clientes' table...")
            cursor.execute(f"ALTER TABLE clientes ADD COLUMN {col_name} {col_type}")
            
    conn.commit()
    
    # 2. Read CSV and import records
    print(f"Reading CSV from: {csv_path}")
    if not os.path.exists(csv_path):
        print(f"Error: CSV file not found at {csv_path}")
        return
        
    inserted_count = 0
    skipped_count = 0
    
    # Using 'utf-8-sig' to automatically handle the UTF-8 BOM if present
    with open(csv_path, mode="r", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        header = next(reader)
        print("CSV Header fields:", header)
        
        for idx, row in enumerate(reader, start=2):
            if not row or not row[0].strip():
                continue
                
            name = row[0].strip()
            email = row[1].strip() if len(row) > 1 else ""
            phone = row[2].strip() if len(row) > 2 else ""
            tax = row[3].strip() if len(row) > 3 else ""
            addr1 = row[4].strip() if len(row) > 4 else ""
            addr2 = row[5].strip() if len(row) > 5 else ""
            addr3 = row[6].strip() if len(row) > 6 else ""
            ship_addr1 = row[7].strip() if len(row) > 7 else ""
            ship_addr2 = row[8].strip() if len(row) > 8 else ""
            ship_addr3 = row[9].strip() if len(row) > 9 else ""
            info = "" # Additional info is not explicitly mapped in CSV except maybe empty/general fields
            
            # Check if name already exists (case-insensitive)
            cursor.execute("SELECT id, telefono, correo FROM clientes WHERE LOWER(TRIM(nombreCompania)) = ?", (name.lower(),))
            match = cursor.fetchone()
            
            if match:
                # Update existing client empty fields if the CSV has newer info, but keep existing data
                skipped_count += 1
                # print(f"Skipped (already exists): {name}")
            else:
                cursor.execute("""
                    INSERT INTO clientes (
                        nombreCompania, telefono, correo, rn, 
                        direccion1, direccion2, direccion3, 
                        direccionEnvio1, direccionEnvio2, direccionEnvio3, 
                        infoAdicional, folderId
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                """, (name, phone, email, tax, addr1, addr2, addr3, ship_addr1, ship_addr2, ship_addr3, info))
                inserted_count += 1
                
    conn.commit()
    conn.close()
    
    print("\n--- Import Summary ---")
    print(f"Total inserted: {inserted_count}")
    print(f"Total skipped (duplicates): {skipped_count}")
    print(f"Import completed successfully.")

if __name__ == "__main__":
    run_import()
