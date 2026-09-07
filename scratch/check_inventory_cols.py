import csv

csv_path = r"C:\Almir_trabajos\Novaled Sistema\base de datos\lista de inventario.csv"

with open(csv_path, mode="r", encoding="utf-8-sig") as f:
    reader = csv.reader(f)
    header = next(reader)
    print("CSV Header:", header)
    print("Number of columns:", len(header))
    
    total_rows = 0
    non_empty_desc = 0
    rows_with_more_cols = 0
    examples = []
    
    for idx, row in enumerate(reader, start=2):
        total_rows += 1
        if len(row) > 3 and row[2].strip():
            non_empty_desc += 1
        if len(row) > 4:
            rows_with_more_cols += 1
        if idx <= 15:
            examples.append((idx, row))
            
    print(f"Total Rows: {total_rows}")
    print(f"Rows with non-empty description (col 2): {non_empty_desc}")
    print(f"Rows with more than 4 columns: {rows_with_more_cols}")
    print("\nFirst few rows:")
    for idx, row in examples:
        print(f"Row {idx} ({len(row)} cols): {row}")
