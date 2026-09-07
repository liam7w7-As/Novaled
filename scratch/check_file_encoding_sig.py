import sys
import csv

# Reconfigure stdout to use utf-8 to avoid encoding errors in the terminal
sys.stdout.reconfigure(encoding='utf-8')

csv_path = r"C:\Almir_trabajos\Novaled Sistema\base de datos\lista de inventario.csv"

with open(csv_path, mode="r", encoding="utf-8-sig") as f:
    reader = csv.reader(f)
    header = next(reader)
    print("CSV Header:", header)
    for idx in range(1, 15):
        row = next(reader)
        print(f"Row {idx+1}: {row}")
