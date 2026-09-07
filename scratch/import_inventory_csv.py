import sqlite3
import csv
import os

db_path = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\novaled.db"
csv_path = r"C:\Almir_trabajos\Novaled Sistema\base de datos\lista de inventario.csv"

def run_import():
    print(f"Connecting to database: {db_path}")
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Verify table columns
    cursor.execute("PRAGMA table_info(articulos)")
    columns = [col[1] for col in cursor.fetchall()]
    print(f"Existing columns in 'articulos' table: {columns}")
    
    if not os.path.exists(csv_path):
        print(f"Error: CSV file not found at {csv_path}")
        return
        
    inserted_count = 0
    skipped_count = 0
    
    print(f"Reading CSV from: {csv_path}")
    with open(csv_path, mode="r", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        header = next(reader)
        print("CSV Header fields:", header)
        
        for idx, row in enumerate(reader, start=2):
            if not row or not row[0].strip():
                continue
                
            name = row[0].strip()
            
            # Parse price
            price_str = row[1].strip() if len(row) > 1 else "0.0"
            try:
                price = float(price_str)
            except ValueError:
                price = 0.0
                
            desc = row[2].strip() if len(row) > 2 else ""
            
            # Check if product name already exists (case-insensitive & trimmed)
            cursor.execute("SELECT id, precio, descripcion FROM articulos WHERE LOWER(TRIM(nombre)) = ?", (name.lower(),))
            match = cursor.fetchone()
            
            if match:
                # Complement description if empty in DB but exists in CSV
                art_id, current_price, current_desc = match
                updated = False
                if not current_desc and desc:
                    cursor.execute("UPDATE articulos SET descripcion = ? WHERE id = ?", (desc, art_id))
                    updated = True
                
                skipped_count += 1
                if updated:
                    print(f"Complemented description for existing article: '{name}'")
            else:
                # Insert new article
                cursor.execute("""
                    INSERT INTO articulos (
                        nombre, precio, precioCaja, descripcion, 
                        folderId, finalArtId, proveedor, codCaja, stockJson, 
                        familia, subcategoria, unidad, unidadDetalle
                    ) VALUES (?, ?, 0.0, ?, NULL, NULL, NULL, '', NULL, '', '', 'Unidad', '')
                """, (name, price, desc))
                inserted_count += 1
                
    conn.commit()
    conn.close()
    
    print("\n--- Import Summary ---")
    print(f"Total inserted: {inserted_count}")
    print(f"Total skipped (duplicates): {skipped_count}")
    print("Import completed successfully.")

if __name__ == "__main__":
    run_import()
