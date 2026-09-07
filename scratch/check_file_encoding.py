encodings = ['utf-8', 'latin-1', 'cp1252', 'utf-16', 'mac_roman']
csv_path = r"C:\Almir_trabajos\Novaled Sistema\base de datos\lista de inventario.csv"

for enc in encodings:
    try:
        with open(csv_path, mode="r", encoding=enc) as f:
            lines = [f.readline() for _ in range(15)]
        print(f"--- Encoding: {enc} ---")
        for idx, line in enumerate(lines):
            if any(ord(c) > 127 for c in line):
                print(f"Line {idx}: {line.strip()}")
    except Exception as e:
        print(f"--- Encoding {enc} failed: {e}")
