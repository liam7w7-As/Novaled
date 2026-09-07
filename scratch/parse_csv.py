import csv

with open(r"C:\Almir_trabajos\Novaled Sistema\base de datos\lista de clientes.csv", mode="r", encoding="utf-8") as f:
    reader = csv.reader(f)
    header = next(reader)
    print("CSV Header:", header)
    print("CSV Header Length:", len(header))
    
    count_with_phone = 0
    count_with_email = 0
    count_with_tax = 0
    count_with_address = 0
    total_rows = 0
    
    for idx, row in enumerate(reader, start=2):
        total_rows += 1
        name = row[0] if len(row) > 0 else ""
        email = row[1] if len(row) > 1 else ""
        phone = row[2] if len(row) > 2 else ""
        tax = row[3] if len(row) > 3 else ""
        addr1 = row[4] if len(row) > 4 else ""
        
        if phone.strip():
            count_with_phone += 1
        if email.strip():
            count_with_email += 1
        if tax.strip():
            count_with_tax += 1
        if any(col.strip() for col in row[4:10]):
            count_with_address += 1
            
        # Let's print some example populated rows
        if phone.strip() or email.strip() or tax.strip() or any(col.strip() for col in row[4:10]):
            print(f"Row {idx}: Name='{name}', Email='{email}', Phone='{phone}', Tax='{tax}', Address1='{addr1}'")
            print(f"  Full row ({len(row)} cols): {row}")

    print(f"\nSummary: Total rows = {total_rows}")
    print(f"Rows with phone: {count_with_phone}")
    print(f"Rows with email: {count_with_email}")
    print(f"Rows with tax: {count_with_tax}")
    print(f"Rows with addresses: {count_with_address}")
