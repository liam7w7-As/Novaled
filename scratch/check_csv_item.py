import os

csv_path = r"C:\Almir_trabajos\Novaled Sistema\base de datos\lista de inventario.csv"
if not os.path.exists(csv_path):
    print("CSV not found.")
    exit(1)

with open(csv_path, 'r', encoding='utf-8-sig', errors='ignore') as f:
    for line in f:
        if "FOCO LED E-27 22W LUZ" in line or "FOCO LED E-27 22W" in line:
            print(line.strip())
